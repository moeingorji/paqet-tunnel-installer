#!/bin/bash
#
# Paqet Automated Installer v6.0 (Archive Support)
# Wrapper script created by [Your Name/Handle]
#
# Fixes:
# - Matches 'linux-amd64' (Hyphen) correctly
# - AUTO-EXTRACTS .tar.gz archives
# - Finds the binary inside the archive automatically
#
# Original Software: https://github.com/hanselime/paqet
#

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Please run as root (sudo bash setup.sh)"
  exit
fi

echo "=================================================="
echo "      PAQET AUTOMATED INSTALLER (v6.0)            "
echo "=================================================="
echo ""

# 1. Install Dependencies
echo "[+] Installing dependencies..."
apt update -q
apt install -y curl wget iptables-persistent netfilter-persistent file tar

# 2. Setup Directories
mkdir -p /opt/paqet
cd /opt/paqet

# 3. Dynamic Download & Extraction Logic
# --------------------------------------------------
rm -f paqet paqet.tar.gz # Clean start

ARCH=$(uname -m)
REPO="hanselime/paqet"
echo "[+] Detected Architecture: $ARCH"
echo "[+] Querying GitHub API for latest release of $REPO..."

# Fetch the latest release data
API_RESPONSE=$(curl -s "https://api.github.com/repos/$REPO/releases/latest")

if [[ "$ARCH" == "x86_64" ]]; then
    # Look for 'linux-amd64' (Hyphen) OR 'linux_amd64' (Underscore)
    DOWNLOAD_URL=$(echo "$API_RESPONSE" | grep "browser_download_url" | grep -E "linux[-_]amd64" | cut -d '"' -f 4 | head -n 1)
elif [[ "$ARCH" == "aarch64" ]]; then
    # Look for 'linux-arm64' OR 'linux_arm64'
    DOWNLOAD_URL=$(echo "$API_RESPONSE" | grep "browser_download_url" | grep -E "linux[-_]arm64" | cut -d '"' -f 4 | head -n 1)
else
    echo "❌ Error: Unsupported Architecture ($ARCH)."
    exit 1
fi

# Validation
if [ -z "$DOWNLOAD_URL" ] || echo "$DOWNLOAD_URL" | grep -q "null"; then
    echo "❌ Error: Could not auto-detect download link."
    echo "   Manual Mode: Please paste the .tar.gz download link."
    read -p "Paste URL here: " DOWNLOAD_URL
    if [ -z "$DOWNLOAD_URL" ]; then echo "Exiting."; exit 1; fi
fi

echo "[+] Downloading from: $DOWNLOAD_URL"
# Download as archive
curl -L -o paqet_archive.tar.gz "$DOWNLOAD_URL"

echo "[+] Extracting archive..."
# Extract the tar.gz
tar -xzf paqet_archive.tar.gz

# Find the binary inside (It might be named 'paqet' or 'paqet-linux-amd64...')
# We look for the largest executable file extracted
EXTRACTED_BIN=$(find . -maxdepth 1 -type f -executable ! -name "*.tar.gz" | sort -rn | head -n 1)

if [ -z "$EXTRACTED_BIN" ]; then
    # Fallback: Look for file explicitly named 'paqet'
    if [ -f "paqet" ]; then
        EXTRACTED_BIN="./paqet"
    else
        echo "❌ Extraction Error: Could not find the 'paqet' binary inside the archive."
        exit 1
    fi
fi

# Rename it to standard 'paqet'
mv "$EXTRACTED_BIN" paqet
chmod +x paqet

# Final Integrity Check
FILE_TYPE=$(file paqet)
if echo "$FILE_TYPE" | grep -qE "HTML|ASCII|empty|text"; then
    echo "❌ CRITICAL: Final binary is not a program."
    rm paqet
    exit 1
fi

echo "[+] Binary Installed Successfully."
rm -f paqet_archive.tar.gz # Cleanup
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
