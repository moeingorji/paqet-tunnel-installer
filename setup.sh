#!/bin/bash
#
# Paqet Automated Installer v11.0 (Raw Socket Fix)
#
# Fixes:
# - Auto-detects Network Interface (eth0/ens3)
# - Auto-detects Local IP & Gateway MAC (Required for Raw Sockets)
# - Generates valid 'network' block in config
#

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Please run as root (sudo bash setup.sh)"
  exit
fi

echo "=================================================="
echo "      PAQET AUTOMATED INSTALLER (v11.0)           "
echo "=================================================="
echo ""

# 1. Install Dependencies
apt update -q
apt install -y curl wget iptables-persistent netfilter-persistent file tar iproute2 net-tools

# 2. Setup Directories
mkdir -p /opt/paqet
cd /opt/paqet
rm -f paqet paqet_archive.tar.gz

# 3. DOWNLOAD LOGIC (Alpha Support)
ARCH=$(uname -m)
REPO="hanselime/paqet"
echo "[+] Detected Architecture: $ARCH"

API_RESPONSE=$(curl -s "https://api.github.com/repos/$REPO/releases")

if [[ "$ARCH" == "x86_64" ]]; then
    DOWNLOAD_URL=$(echo "$API_RESPONSE" | grep "browser_download_url" | grep "linux-amd64" | head -n 1 | cut -d '"' -f 4)
elif [[ "$ARCH" == "aarch64" ]]; then
    DOWNLOAD_URL=$(echo "$API_RESPONSE" | grep "browser_download_url" | grep "linux-arm64" | head -n 1 | cut -d '"' -f 4)
fi

if [ -z "$DOWNLOAD_URL" ]; then
    echo "⚠️ Auto-detect failed. Using Fallback..."
    if [[ "$ARCH" == "x86_64" ]]; then
        DOWNLOAD_URL="https://github.com/hanselime/paqet/releases/download/v1.0.0-alpha.12/paqet-linux-amd64-v1.0.0-alpha.12.tar.gz"
    else
        DOWNLOAD_URL="https://github.com/hanselime/paqet/releases/download/v1.0.0-alpha.12/paqet-linux-arm64-v1.0.0-alpha.12.tar.gz"
    fi
fi

echo "[+] Downloading: $DOWNLOAD_URL"
wget -q --show-progress -O paqet_archive.tar.gz "$DOWNLOAD_URL"

echo "[+] Extracting..."
tar -xzf paqet_archive.tar.gz
FOUND_BIN=$(find . -type f -executable ! -name "*.tar.gz" | head -n 1)
if [ -z "$FOUND_BIN" ]; then echo "❌ Extraction failed."; exit 1; fi
mv "$FOUND_BIN" paqet
chmod +x paqet
rm -f paqet_archive.tar.gz

# --------------------------------------------------
# SMART NETWORK DETECTION (CRITICAL FOR PAQET)
# --------------------------------------------------
echo "[+] Detecting Network Details..."

# 1. Detect Default Interface
DEFAULT_IFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
echo "    Interface: $DEFAULT_IFACE"

# 2. Detect Local IP of that Interface
LOCAL_IP=$(ip -4 addr show "$DEFAULT_IFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1)
echo "    Local IP:  $LOCAL_IP"

# 3. Detect Gateway IP & MAC
GATEWAY_IP=$(ip route | grep default | awk '{print $3}' | head -n1)
# Ping gateway once to ensure it's in ARP table
ping -c 1 -W 1 "$GATEWAY_IP" > /dev/null 2>&1
GATEWAY_MAC=$(ip neigh show "$GATEWAY_IP" | awk '{print $5}' | head -n1)

if [ -z "$GATEWAY_MAC" ]; then
    echo "⚠️ Warning: Could not detect Gateway MAC automatically."
    echo "   Using a generic broadcast MAC (might work, might not)."
    GATEWAY_MAC="ff:ff:ff:ff:ff:ff"
else
    echo "    Gateway MAC: $GATEWAY_MAC"
fi

# --------------------------------------------------
# CONFIGURATION
# --------------------------------------------------

echo ""
echo "Which server is this?"
echo "  1) Foreign Server"
echo "  2) Iran Server"
read -p "Select [1 or 2]: " ROLE

if [ "$ROLE" == "1" ]; then
    # FOREIGN SERVER
    read -p "Enter Tunnel Password: " TUNNEL_PASS
    PORT=443

    # FIX: Added 'network' block with detected values
    cat <<EOF > server.yaml
role: server
listen:
  addr: ":$PORT"
network:
  interface: "$DEFAULT_IFACE"
  ipv4:
    addr: "$LOCAL_IP:$PORT"
    router_mac: "$GATEWAY_MAC"
transport:
  protocol: "kcp"
  kcp:
    mode: "fast"
    mtu: 1350
    sndwnd: 1024
    rcvwnd: 1024
    dshard: 10
    pshard: 3
    block: "aes"
    key: "$TUNNEL_PASS"
EOF

    # Raw socket firewall rules (Critical)
    iptables -t raw -A PREROUTING -p tcp --dport $PORT -j NOTRACK
    iptables -t raw -A OUTPUT -p tcp --sport $PORT -j NOTRACK
    iptables -t mangle -A OUTPUT -p tcp --sport $PORT --tcp-flags RST RST -j DROP
    netfilter-persistent save

    COMMAND="/opt/paqet/paqet run -c server.yaml"

elif [ "$ROLE" == "2" ]; then
    # IRAN SERVER
    read -p "Enter Foreign Server IP: " FOREIGN_IP
    read -p "Enter Tunnel Password: " TUNNEL_PASS
    read -p "App Username: " PROXY_USER
    read -p "App Password: " PROXY_PASS

    # FIX: Added 'network' block (Client uses port 0 for random src port)
    cat <<EOF > client.yaml
role: client
server:
  addr: "$FOREIGN_IP:443"
socks5:
  - listen: "0.0.0.0:1080"
    username: "$PROXY_USER"
    password: "$PROXY_PASS"
network:
  interface: "$DEFAULT_IFACE"
  ipv4:
    addr: "$LOCAL_IP:0"
    router_mac: "$GATEWAY_MAC"
transport:
  protocol: "kcp"
  kcp:
    mode: "fast"
    mtu: 1350
    sndwnd: 1024
    rcvwnd: 1024
    dshard: 10
    pshard: 3
    block: "aes"
    key: "$TUNNEL_PASS"
EOF

    iptables -A INPUT -p tcp --dport 1080 -j ACCEPT
    # MSS Clamping
    iptables -t mangle -A OUTPUT -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 900
    iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 900
    netfilter-persistent save

    COMMAND="/opt/paqet/paqet run -c client.yaml"
fi

# Service Creation
cat <<EOF > /etc/systemd/system/paqet.service
[Unit]
Description=Paqet Tunnel Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/paqet
ExecStart=$COMMAND
Restart=always
RestartSec=3
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable paqet
systemctl restart paqet

sleep 2

if systemctl is-active --quiet paqet; then
    echo "✅ Service is RUNNING successfully."
else
    echo "❌ Service failed. Check logs:"
    journalctl -u paqet -n 20 --no-pager
fi
