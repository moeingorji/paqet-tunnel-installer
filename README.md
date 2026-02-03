# 🚀 Paqet Tunnel Automated Installer

[![Bash](https://img.shields.io/badge/Language-Bash-4EAA25?style=flat-square&logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Systemd](https://img.shields.io/badge/Service-Systemd-e0115f?style=flat-square&logo=systemd&logoColor=white)]()

**[English](#-english-guide) | [فارسی](#-راهنمای-فارسی)**

A high-performance **Raw Socket Tunnel** designed to bypass heavy internet censorship. Paqet uses low-level packet injection to establish a stable connection between a restricted server (Bridge) and a free server (Upstream).

---

## 🇬🇧 English Guide

### ⚠️ Critical Requirement (Fix for "Shared Object" Error)
On many modern servers (Ubuntu 22.04/24.04), you **must** install the packet capture library before or immediately after installing Paqet. If the service fails to start, run this:

```bash
sudo apt update
sudo apt install -y libpcap-dev
sudo systemctl restart paqet
