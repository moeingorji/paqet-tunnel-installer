#!/bin/bash
#
# Paqet Automated Installer
# Wrapper script created by [Your Name/Handle]
#
# This script automates the installation of Paqet.
# Original Paqet Core by: https://github.com/parviz-f/paqet

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (sudo bash setup_paqet.sh)"
  exit
fi

echo "=================================================="
echo "      PAQET AUTOMATED INSTALLER (High Speed)      "
echo "=================================================="
echo ""

# 1. Install Dependencies
echo "[+] Installing dependencies..."
apt update -q
apt install -y wget iptables-persistent netfilter-persistent

# 2. Setup Directories
mkdir -p /opt/paqet
cd /opt/paqet

# 3. Download Binary (Auto-detects latest version)
# Hardcoded to a known working version logic or direct link for stability
if [ ! -f "paqet" ]; then
    echo "[+] Downloading Paqet..."
    wget -q --show-progress https://github.com/parviz-f/paqet/releases/latest/download/paqet_linux_amd64 -O paqet
    chmod +x paqet
else
    echo "[+] Paqet binary already exists. Skipping download."
fi

# 4. Ask User for Role
echo ""
echo "Which server is this?"
echo "  1) Foreign Server (Italy/Germany/etc) - The Exit Node"
echo "  2) Iran Server (Bridge) - The Middle Man"
read -p "Select [1 or 2]: " ROLE

if [ "$ROLE" == "1" ]; then
    # ==========================
    # FOREIGN SERVER SETUP
    # ==========================
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

    # Firewall Rules for Server
    echo "[+] Applying Firewall Rules (Port $PORT)..."
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
    # ==========================
    # IRAN BRIDGE SETUP
    # ==========================
    read -p "Enter Foreign Server IP: " FOREIGN_IP
    read -p "Enter Foreign Server Port (Default 443): " FOREIGN_PORT
    FOREIGN_PORT=${FOREIGN_PORT:-443}
    read -p "Enter the Tunnel Password (from Foreign Server): " TUNNEL_PASS
    
    echo ""
    echo "--- SOCKS5 Proxy Setup ---"
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

    # Firewall Rules for Client
    echo "[+] Applying Firewall Rules (Port 1080)..."
    iptables -A INPUT -p tcp --dport 1080 -j ACCEPT
    # MSS Clamping (Fixes mobile data packet issues)
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

# 5. Create Systemd Service
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

# 6. Start Service
echo "[+] Starting Service..."
systemctl daemon-reload
systemctl enable paqet
systemctl restart paqet

# Check status
if systemctl is-active --quiet paqet; then
    echo "✅ Service is RUNNING successfully."
else
    echo "❌ Service failed to start. Check logs with: sudo journalctl -u paqet -f"
fi
