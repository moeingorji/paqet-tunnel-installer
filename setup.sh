#!/bin/bash
#
# Paqet Automated Installer v13.0 (Fixed Port Logic)
#
# Fixes based on your working config:
# - Forces Client Source Port to 30000 (Critical for Raw Sockets)
# - Sets MTU to 1200 (Stable)
# - Adds explicit Firewall rules for Port 30000
#

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Please run as root (sudo bash setup.sh)"
  exit
fi

echo "=================================================="
echo "      PAQET AUTOMATED INSTALLER (v13.0)           "
echo "=================================================="
echo ""

# 1. Install Dependencies
apt update -q
apt install -y curl wget iptables-persistent netfilter-persistent file tar iproute2 net-tools

# 2. Setup Directories
mkdir -p /opt/paqet
cd /opt/paqet
rm -f paqet paqet_archive.tar.gz

# 3. DOWNLOAD LOGIC
ARCH=$(uname -m)
REPO="hanselime/paqet"
echo "[+] Detected Architecture: $ARCH"

API_RESPONSE=$(curl -s "https://api.github.com/repos/$REPO/releases")

if [[ "$ARCH" == "x86_64" ]]; then
    DOWNLOAD_URL=$(echo "$API_RESPONSE" | grep "browser_download_url" | grep "linux-amd64" | head -n 1 | cut -d '"' -f 4)
elif [[ "$ARCH" == "aarch64" ]]; then
    DOWNLOAD_URL=$(echo "$API_RESPONSE" | grep "browser_download_url" | grep "linux-arm64" | head -n 1 | cut -d '"' -f 4)
fi

# Fallback
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
tar -xzf paqet_archive.tar.gz
FOUND_BIN=$(find . -type f -executable ! -name "*.tar.gz" | head -n 1)
mv "$FOUND_BIN" paqet
chmod +x paqet
rm -f paqet_archive.tar.gz

# --------------------------------------------------
# NETWORK DETECTION (INTERACTIVE)
# --------------------------------------------------
echo ""
echo "[+] Detecting Network Details..."

DEFAULT_IFACE=$(ip -4 route show default | awk '{print $5}' | head -n1)

if [ -z "$DEFAULT_IFACE" ]; then
    echo "⚠️  Could not detect Network Interface automatically."
    read -p "👉 Enter your Network Interface Name (e.g. eth0): " DEFAULT_IFACE
else
    echo "    ✅ Auto-detected Interface: $DEFAULT_IFACE"
    read -p "    Press ENTER to confirm (or type a new name): " USER_IFACE
    if [ ! -z "$USER_IFACE" ]; then DEFAULT_IFACE="$USER_IFACE"; fi
fi

LOCAL_IP=$(ip -4 addr show "$DEFAULT_IFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1)
echo "    ✅ Local IP: $LOCAL_IP"

GATEWAY_IP=$(ip -4 route show default | awk '{print $3}' | head -n1)
ping -c 1 -W 1 "$GATEWAY_IP" > /dev/null 2>&1
GATEWAY_MAC=$(ip neigh show "$GATEWAY_IP" | awk '{print $5}' | head -n1)

if [ -z "$GATEWAY_MAC" ]; then
    echo "⚠️  Warning: Could not detect Gateway MAC."
    GATEWAY_MAC="ff:ff:ff:ff:ff:ff"
else
    echo "    ✅ Gateway MAC: $GATEWAY_MAC"
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
    # ========================
    # FOREIGN SERVER SETUP
    # ========================
    read -p "Enter Tunnel Password: " TUNNEL_PASS
    PORT=443

    rm -f server.yaml
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
    mtu: 1200
    sndwnd: 1024
    rcvwnd: 1024
    dshard: 10
    pshard: 3
    block: "aes"
    key: "$TUNNEL_PASS"
EOF

    # Firewall Rules (Foreign)
    iptables -t raw -A PREROUTING -p tcp --dport $PORT -j NOTRACK
    iptables -t raw -A OUTPUT -p tcp --sport $PORT -j NOTRACK
    # Important: Allow return traffic to random high ports (Raw Socket behavior)
    iptables -t raw -A PREROUTING -p tcp --sport $PORT -j NOTRACK
    iptables -t mangle -A OUTPUT -p tcp --sport $PORT --tcp-flags RST RST -j DROP
    netfilter-persistent save

    COMMAND="/opt/paqet/paqet run -c server.yaml"
    CONFIG_FILE="server.yaml"

elif [ "$ROLE" == "2" ]; then
    # ========================
    # IRAN SERVER SETUP
    # ========================
    read -p "Enter Foreign Server IP: " FOREIGN_IP
    read -p "Enter Tunnel Password: " TUNNEL_PASS
    read -p "App Username: " PROXY_USER
    read -p "App Password: " PROXY_PASS

    CLIENT_SRC_PORT=30000

    rm -f client.yaml
    # FIX: Using fixed port 30000 instead of 0
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
    addr: "$LOCAL_IP:$CLIENT_SRC_PORT"
    router_mac: "$GATEWAY_MAC"
transport:
  protocol: "kcp"
  kcp:
    mode: "fast"
    mtu: 1200
    sndwnd: 1024
    rcvwnd: 1024
    dshard: 10
    pshard: 3
    block: "aes"
    key: "$TUNNEL_PASS"
EOF

    # Firewall Rules (Iran)
    iptables -A INPUT -p tcp --dport 1080 -j ACCEPT
    
    # CRITICAL FIX: Allow the Fixed Source Port (30000)
    iptables -t raw -A PREROUTING -p tcp --dport $CLIENT_SRC_PORT -j NOTRACK
    iptables -t raw -A OUTPUT -p tcp --sport $CLIENT_SRC_PORT -j NOTRACK
    
    # MSS Clamping
    iptables -t mangle -A OUTPUT -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 900
    iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 900
    netfilter-persistent save

    COMMAND="/opt/paqet/paqet run -c client.yaml"
    CONFIG_FILE="client.yaml"
fi

# DEBUG: Print Config
echo ""
echo "------------------------------------------------"
echo "Checking generated config ($CONFIG_FILE):"
cat $CONFIG_FILE
echo "------------------------------------------------"
echo ""

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
