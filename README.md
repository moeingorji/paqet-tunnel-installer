# 🚀 Paqet Tunnel Automated Installer

This is a simple bash script to automate the setup of **[Paqet](https://github.com/parviz-f/paqet)**, a high-speed censorship bypass tunnel based on KCP.

It handles everything automatically:
- ✅ Installs dependencies
- ✅ Configures the Server (Foreign VPS)
- ✅ Configures the Client (Iran/Bridge VPS)
- ✅ Sets up Systemd Service (Auto-start on boot)
- ✅ Optimizes Network (MTU, Window Size, Firewall)

## 📋 Prerequisites
- **Server A (Foreign):** Ubuntu/Debian VPS (e.g., Italy, Germany)
- **Server B (Iran):** Ubuntu/Debian VPS (e.g., ParsVDS)

## ⚡ Quick Start

Run this command on **BOTH** servers:

```bash
wget -O setup.sh https://raw.githubusercontent.com/moeingorji/paqet-tunnel-installer/main/setup.sh
sudo bash setup.sh
