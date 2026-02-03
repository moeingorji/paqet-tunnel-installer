#!/bin/bash
#
# Paqet Automated Installer v10.0 (Config Fix)
#
# Fixes:
# - Adds mandatory "role: server/client" to YAML config
# - Keeps the working Download Logic (Alpha Support)
#

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Please run as root (sudo bash setup.sh)"
  exit
fi

echo "=================================================="
echo "      PAQET AUTOMATED INSTALLER (v10.0)           "
echo "=================================================="
echo ""

# 1. Install Dependencies
apt update -q
apt install -y curl wget iptables-persistent netfilter-persistent file tar

# 2. Setup Directories
mkdir -p /opt/paqet
cd /opt/paqet
rm -f paqet paqet_archive.tar.gz

# 3. DOWNLOAD LOGIC (Using the working Alpha detection)
ARCH=$(uname -m)
REPO="hanselime/paqet"
echo "[+] Detected Architecture: $ARCH"
echo "[+] Fetching release info..."

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

if [ -z "$FOUND_BIN" ]; then
    echo "❌ Error: Extraction failed."
    exit 1
fi

mv "$FOUND_BIN" paqet
chmod +x paqet
rm -f paqet_archive.tar.gz

# --------------------------------------------------
# CONFIGURATION (FIXED: Added 'role' field)
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

    # FIX: Added 'role: server' to the top
    cat <<EOF > server.yaml
role: server
listen:
  addr: ":$PORT"
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

    # Firewall
    iptables -t raw -A PREROUTING -p tcp --dport $PORT -j NOTRACK
    iptables -t raw -A OUTPUT -p tcp --sport $PORT -j NOTRACK
    iptables -t mangle -A OUTPUT -p tcp --sport $PORT --tcp-flags RST RST -j DROP
    netfilter-persistent save

    COMMAND="/opt/paqet/paqet run -c server.yaml"

elif [ "$ROLE" == "2" ]; then
    # IRAN SERVER
    read -p "Enter Foreign IP: " FOREIGN_IP
    read -p "Enter Tunnel Password: " TUNNEL_PASS
    read -p "App Username: " PROXY_USER
    read -p "App Password: " PROXY_PASS

    # FIX: Added 'role: client' to the top
    cat <<EOF > client.yaml
role: client
server:
  addr: "$FOREIGN_IP:443"
socks5:
  - listen: "0.0.0.0:1080"
    username: "$PROXY_USER"
    password: "$PROXY_PASS"
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

    # Firewall
    iptables -A INPUT -p tcp --dport 1080 -j ACCEPT
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
    journalctl -u paqet -n 10 --no-pager
fi
