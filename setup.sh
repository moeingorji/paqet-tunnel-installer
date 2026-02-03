#!/bin/bash
#
# Paqet Automated Installer v9.0 (Alpha & Archive Support)
#
# Fixes:
# - Correctly detects Pre-releases (Alpha/Beta)
# - Matches exact filenames from your screenshot (linux-amd64)
# - Auto-extracts .tar.gz archives
#

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Please run as root (sudo bash setup.sh)"
  exit
fi

echo "=================================================="
echo "      PAQET AUTOMATED INSTALLER (Auto-Update)     "
echo "=================================================="
echo ""

# 1. Install Dependencies
apt update -q
apt install -y curl wget iptables-persistent netfilter-persistent file tar

# 2. Setup Directories
mkdir -p /opt/paqet
cd /opt/paqet
# Remove old files to prevent conflicts
rm -f paqet paqet_archive.tar.gz

# 3. SMART DOWNLOAD LOGIC
ARCH=$(uname -m)
REPO="hanselime/paqet"
echo "[+] Detected Architecture: $ARCH"
echo "[+] Searching for newest release (including Alphas)..."

# Fetch ALL releases (not just 'latest') to see Alpha versions
API_RESPONSE=$(curl -s "https://api.github.com/repos/$REPO/releases")

if [[ "$ARCH" == "x86_64" ]]; then
    # Look for file containing "linux-amd64" (Matches your screenshot)
    DOWNLOAD_URL=$(echo "$API_RESPONSE" | grep "browser_download_url" | grep "linux-amd64" | head -n 1 | cut -d '"' -f 4)
elif [[ "$ARCH" == "aarch64" ]]; then
    # Look for file containing "linux-arm64"
    DOWNLOAD_URL=$(echo "$API_RESPONSE" | grep "browser_download_url" | grep "linux-arm64" | head -n 1 | cut -d '"' -f 4)
fi

# Fallback: If API fails, use the hardcoded link you found
if [ -z "$DOWNLOAD_URL" ]; then
    echo "⚠️ Auto-detect failed (GitHub API rate limit?)."
    echo "   Using Hardcoded Fallback (v1.0.0-alpha.12)..."
    if [[ "$ARCH" == "x86_64" ]]; then
        DOWNLOAD_URL="https://github.com/hanselime/paqet/releases/download/v1.0.0-alpha.12/paqet-linux-amd64-v1.0.0-alpha.12.tar.gz"
    else
        DOWNLOAD_URL="https://github.com/hanselime/paqet/releases/download/v1.0.0-alpha.12/paqet-linux-arm64-v1.0.0-alpha.12.tar.gz"
    fi
fi

echo "[+] Downloading: $DOWNLOAD_URL"
wget -q --show-progress -O paqet_archive.tar.gz "$DOWNLOAD_URL"

# 4. Extract and Install
echo "[+] Extracting archive..."
tar -xzf paqet_archive.tar.gz

# Find the binary inside the folder
# We look for an executable file that is NOT the .tar.gz itself
FOUND_BIN=$(find . -type f -executable ! -name "*.tar.gz" | head -n 1)

if [ -z "$FOUND_BIN" ]; then
    echo "❌ Error: Could not find executable file inside the archive."
    echo "   The download might be corrupted."
    exit 1
fi

echo "[+] Found binary: $FOUND_BIN"
mv "$FOUND_BIN" paqet
chmod +x paqet

# Final Integrity Check
if file paqet | grep -qE "HTML|ASCII|empty"; then
    echo "❌ CRITICAL: Extracted file is invalid."
    exit 1
fi

echo "[+] Paqet Installed Successfully!"
rm -f paqet_archive.tar.gz

# --------------------------------------------------
# CONFIGURATION
# --------------------------------------------------

echo ""
echo "Which server is this?"
echo "  1) Foreign Server"
echo "  2) Iran Server"
read -p "Select [1 or 2]: " ROLE

if [ "$ROLE" == "1" ]; then
    # FOREIGN SETUP
    read -p "Enter Tunnel Password: " TUNNEL_PASS
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
    read -p "Enter Foreign IP: " FOREIGN_IP
    read -p "Enter Tunnel Password: " TUNNEL_PASS
    read -p "App Username: " PROXY_USER
    read -p "App Password: " PROXY_PASS

    cat <<EOF > client.yaml
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
