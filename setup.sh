#!/bin/bash
#
# Paqet Automated Installer v5.0 (Dynamic Updates)
# Wrapper script created by [Your Name/Handle]
#
# Features:
# - AUTO-DETECTS latest version using GitHub API (Future-proof)
# - Handles CPU architecture (AMD64/ARM64)
# - Verifies download integrity
#
# Original Software: https://github.com/hanselime/paqet
#

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Please run as root (sudo bash setup.sh)"
  exit
fi

echo "=================================================="
echo "      PAQET AUTOMATED INSTALLER (Dynamic)         "
echo "=================================================="
echo ""

# 1. Install Dependencies
echo "[+] Installing dependencies..."
apt update -q
apt install -y curl wget iptables-persistent netfilter-persistent file

# 2. Setup Directories
mkdir -p /opt/paqet
cd /opt/paqet

# 3. Dynamic Download Logic
# --------------------------------------------------
rm -f paqet # Clean start

ARCH=$(uname -m)
REPO="hanselime/paqet" # The Source Repository
echo "[+] Detected Architecture: $ARCH"
echo "[+] Querying GitHub API for latest release of $REPO..."

# Fetch the latest release data from GitHub API
API_RESPONSE=$(curl -s "https://api.github.com/repos/$REPO/releases/latest")

if [[ "$ARCH" == "x86_64" ]]; then
    # Filter for 'linux_amd64' inside the JSON response
    DOWNLOAD_URL=$(echo "$API_RESPONSE" | grep "browser_download_url" | grep "linux_amd64" | cut -d '"' -f 4)
elif [[ "$ARCH" == "aarch64" ]]; then
    # Filter for 'linux_arm64'
    DOWNLOAD_URL=$(echo "$API_RESPONSE" | grep "browser_download_url" | grep "linux_arm64" | cut -d '"' -f 4)
else
    echo "❌ Error: Unsupported Architecture ($ARCH)."
    exit 1
fi

# Validation: Did we find a URL?
if [ -z "$DOWNLOAD_URL" ] || echo "$DOWNLOAD_URL" | grep -q "null"; then
    echo "❌ Error: Could not find a download link for your architecture."
    echo "   GitHub API might be rate-limited or the repo changed."
    echo "   Manual Mode: Please paste the download link from: https://github.com/$REPO/releases"
    read -p "Paste URL here: " DOWNLOAD_URL
    if [ -z "$DOWNLOAD_URL" ]; then echo "Exiting."; exit 1; fi
fi

echo "[+] Found latest version. Downloading from:"
echo "    $DOWNLOAD_URL"
curl -L -o paqet "$DOWNLOAD_URL"

# 4. Verify Integrity
FILE_TYPE=$(file paqet)
if echo "$FILE_TYPE" | grep -qE "HTML|ASCII|empty|text"; then
    echo "❌ CRITICAL: Download failed (File is text/HTML, not a program)."
    echo "   The server might be blocking GitHub."
    rm paqet
    exit 1
fi

chmod +x paqet
echo "[+] Binary Verified Successfully."
# --------------------------------------------------

# 5. Ask User for Role
echo ""
echo "Which server is this?"
echo "  1) Foreign Server (Italy/Germany/etc) - The Exit Node"
echo "  2) Iran Server (Bridge) - The Middle Man"
read -p "Select [1 or 2]: " ROLE

if [ "$ROLE" == "1" ]; then
    # FOREIGN SERVER SETUP
    read -p "Enter a secret password for the tunnel: " TUNNEL_PASS
    PORT=443

    echo "[+] Creating Server Config..."
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

    # Firewall
    iptables -t raw -A PREROUTING -p tcp --dport $PORT -j NOTRACK
    iptables -t raw -A OUTPUT -p tcp --sport $PORT -j NOTRACK
    iptables -t mangle -A OUTPUT -p tcp --sport $PORT --tcp-flags RST RST -j DROP
    netfilter-persistent save

    COMMAND="/opt/paqet/paqet run -c server.yaml"
    
    echo ""
    echo "✅ INSTALLATION COMPLETE!"
    echo "Your Server is ready on Port $PORT."
    echo "Use the password '$TUNNEL_PASS' on your Iran client."

elif [ "$ROLE" == "2" ]; then
    # IRAN BRIDGE SETUP
    read -p "Enter Foreign Server IP: " FOREIGN_IP
    read -p "Enter Foreign Server Port (Default 443): " FOREIGN_PORT
    FOREIGN_PORT=${FOREIGN_PORT:-443}
    read -p "Enter the Tunnel Password (from Foreign Server): " TUNNEL_PASS
    
    echo ""
    read -p "Set a Username for your App (e.g. myuser): " PROXY_USER
    read -p "Set a Password for your App: " PROXY_PASS

    echo "[+] Creating Client Config..."
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

    # Firewall
    iptables -A INPUT -p tcp --dport 1080 -j ACCEPT
    # MSS Clamping
    iptables -t mangle -A OUTPUT -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 900
    iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 900
    netfilter-persistent save

    COMMAND="/opt/paqet/paqet run -c client.yaml"
    
    echo ""
    echo "✅ INSTALLATION COMPLETE!"
    echo "Your Bridge is ready."
    echo "Connect your phone to IP: (Your_Iran_IP) Port: 1080"

else
    echo "Invalid selection. Exiting."
    exit 1
fi

# 6. Create Service
echo "[+] Creating Background Service..."
cat <<EOF > /etc/systemd/system/paqet.service
[Unit]
Description=Paqet Tunnel Service
After=network.target network-online.target
Wants=network-online.target

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

# 7. Start Service
echo "[+] Starting Service..."
systemctl daemon-reload
systemctl enable paqet
systemctl restart paqet

if systemctl is-active --quiet paqet; then
    echo "✅ Service is RUNNING successfully."
else
    echo "❌ Service failed to start. Logs:"
    journalctl -u paqet -n 10 --no-pager
fi
