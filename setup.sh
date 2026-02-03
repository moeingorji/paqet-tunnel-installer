#!/bin/bash
#
# Paqet Automated Installer v7.0 (Manual Override)
#
# Fixes:
# - Removes broken Auto-Detection
# - Asks you for the LINK (Since you have one that works)
# - Handles .tar.gz extraction automatically
#

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Please run as root (sudo bash setup.sh)"
  exit
fi

echo "=================================================="
echo "      PAQET INSTALLER (Manual Link Mode)          "
echo "=================================================="
echo ""

# 1. Install Dependencies
apt update -q
apt install -y curl wget iptables-persistent netfilter-persistent file tar

# 2. Setup Directories
mkdir -p /opt/paqet
cd /opt/paqet
rm -f paqet paqet.tar.gz  # Clean old junk

# 3. ASK FOR LINK
echo "---------------------------------------------------------"
echo "Paste the working download link for your architecture."
echo "For Intel/AMD, use the link you found earlier:"
echo "https://github.com/hanselime/paqet/releases/download/v1.0.0-alpha.12/paqet-linux-amd64-v1.0.0-alpha.12.tar.gz"
echo "---------------------------------------------------------"
read -p "Paste Link Here: " DOWNLOAD_URL

if [ -z "$DOWNLOAD_URL" ]; then
    echo "❌ No link provided. Exiting."
    exit 1
fi

echo "[+] Downloading..."
wget -O paqet_archive.tar.gz "$DOWNLOAD_URL"

# 4. Extract and Find Binary
echo "[+] Extracting..."
tar -xzf paqet_archive.tar.gz

# Find the executable file inside the extracted mess
# We look for any file that is executable and NOT a .tar.gz
FOUND_BIN=$(find . -type f -executable ! -name "*.tar.gz" | head -n 1)

if [ -z "$FOUND_BIN" ]; then
    echo "❌ Error: Could not find the executable file inside the archive."
    echo "Debug: Listing files..."
    ls -R
    exit 1
fi

echo "[+] Found binary at: $FOUND_BIN"
mv "$FOUND_BIN" paqet
chmod +x paqet

# 5. Final Check
FILE_TYPE=$(file paqet)
if echo "$FILE_TYPE" | grep -qE "HTML|ASCII|empty"; then
    echo "❌ CRITICAL: The file is invalid ($FILE_TYPE)."
    exit 1
fi

echo "[+] Binary Installed Successfully!"
rm -f paqet_archive.tar.gz

# --------------------------------------------------
# STANDARD SETUP CONTINUES BELOW
# --------------------------------------------------

echo ""
echo "Which server is this?"
echo "  1) Foreign Server"
echo "  2) Iran Server"
read -p "Select [1 or 2]: " ROLE

if [ "$ROLE" == "1" ]; then
    # FOREIGN SETUP
    read -p "Enter a secret password: " TUNNEL_PASS
    PORT=443

    cat <<EOF > server.yaml
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

    iptables -t raw -A PREROUTING -p tcp --dport $PORT -j NOTRACK
    iptables -t raw -A OUTPUT -p tcp --sport $PORT -j NOTRACK
    iptables -t mangle -A OUTPUT -p tcp --sport $PORT --tcp-flags RST RST -j DROP
    netfilter-persistent save

    COMMAND="/opt/paqet/paqet run -c server.yaml"

elif [ "$ROLE" == "2" ]; then
    # IRAN SETUP
    read -p "Enter Foreign Server IP: " FOREIGN_IP
    read -p "Enter Foreign Server Port (Default 443): " FOREIGN_PORT
    FOREIGN_PORT=${FOREIGN_PORT:-443}
    read -p "Enter Tunnel Password: " TUNNEL_PASS
    
    echo "--- SOCKS5 Proxy Setup ---"
    read -p "Username for App: " PROXY_USER
    read -p "Password for App: " PROXY_PASS

    cat <<EOF > client.yaml
server:
  addr: "$FOREIGN_IP:$FOREIGN_PORT"
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
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable paqet
systemctl restart paqet

if systemctl is-active --quiet paqet; then
    echo "✅ Service is RUNNING successfully."
else
    echo "❌ Service failed. Check logs."
    journalctl -u paqet -n 5 --no-pager
fi
