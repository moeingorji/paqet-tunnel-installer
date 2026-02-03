# 🚀 Paqet Tunnel Installer

[![Bash](https://img.shields.io/badge/Language-Bash-4EAA25?style=flat-square&logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Systemd](https://img.shields.io/badge/Service-Systemd-e0115f?style=flat-square&logo=systemd&logoColor=white)]()

**[English](#-english-guide) | [فارسی](#-راهنمای-فارسی)**

A high-performance **Raw Socket Tunnel** designed to bypass heavy internet censorship. Paqet uses low-level packet injection to establish a stable connection between a restricted server (Bridge) and a free server (Upstream).

---

## 🇬🇧 English Guide

### ⚠️ Critical Requirement
On modern servers (Ubuntu 22.04/24.04), you **must** run these commands first to install the required network library. If you skip this, the service may not start.

```bash
sudo apt update
sudo apt install -y libpcap-dev
sudo systemctl restart paqet
```

### 📋 Prerequisites
* **Server A (Foreign):** VPS in a free country (e.g., Germany, Netherlands).
* **Server B (Bridge/Iran):** VPS in the restricted country.
* **Root Access:** All commands must be run as `root` (or with `sudo`).
* **Ports:** Ensure ports `443` (Foreign) and `1080` (Iran) are open.

### ⚡ Installation
Run this command on **BOTH** servers to download the binary and set up the systemd service:

```bash
wget -O setup.sh [https://raw.githubusercontent.com/moeingorji/REPO_NAME/main/setup.sh](https://raw.githubusercontent.com/moeingorji/REPO_NAME/main/setup.sh)
sudo bash setup.sh
```

### ⚙️ Setup Instructions
1.  **Foreign Server:** Run the script and select **Option 1**. Enter a strong tunnel password.
2.  **Iran Server:** Run the script and select **Option 2**. Enter the Foreign Server's IP, the same tunnel password, and create a Username/Password for your client connection.

### 📱 Client Connection (NetMod / NekoBox)
To connect your phone or PC:

1.  **Download App:** **NetMod Syna** (Android/PC) or **NekoBox**.
2.  **Create Profile:** Select **SOCKS5 Proxy**.
3.  **IP:** Enter your **Iran Server IP**.
4.  **Port:** `1080`.
5.  **Authentication:** Enter the **Username** and **Password** you created during the Iran server setup.
6.  **UDP Relay:** Turn **ON** (Required for WhatsApp/Instagram calls).
7.  **Connect!** 🚀

---

## 🇮🇷 راهنمای فارسی

### ⚠️ نکته بسیار مهم (نصب کتابخانه)
در اکثر سرورهای جدید (مثل Ubuntu 24.04)، برای اجرای صحیح برنامه حتماً باید دستورات زیر را قبل از نصب اجرا کنید:

```bash
sudo apt update
sudo apt install -y libpcap-dev
sudo systemctl restart paqet
```

### 📋 پیش‌نیازها
* **سرور خارج:** یک سرور مجازی در خارج از کشور.
* **سرور ایران:** یک سرور مجازی در ایران (به عنوان پل).
* **دسترسی روت:** تمامی دستورات باید با کاربر `root` اجرا شوند.

### ⚡ نصب و راه‌اندازی
دستور زیر را در **هر دو سرور** اجرا کنید تا برنامه نصب و سرویس آن به صورت خودکار ساخته شود:

```bash
wget -O setup.sh [https://raw.githubusercontent.com/moeingorji/REPO_NAME/main/setup.sh](https://raw.githubusercontent.com/moeingorji/REPO_NAME/main/setup.sh)
sudo bash setup.sh
```

### ⚙️ راهنمای تنظیمات
۱. **سرور خارج:** اسکریپت را اجرا کرده و گزینه **۱** را انتخاب کنید. یک رمز عبور قوی برای تانل تعیین کنید.
۲. **سرور ایران:** اسکریپت را اجرا کرده و گزینه **۲** را انتخاب کنید. آی‌پی سرور خارج و رمز عبور تانل را وارد کنید. سپس یک نام‌کاربری و رمز عبور برای اتصال گوشی خود بسازید.

### 📱 اتصال با NetMod یا NekoBox
برای اتصال گوشی یا کامپیوتر به تانل:

۱. برنامه **NetMod Syna** یا **NekoBox** را دانلود کنید.
۲. یک پروفایل جدید از نوع **SOCKS5** بسازید.
۳. **آی‌پی:** آی‌پی سرور ایران خود را وارد کنید.
۴. **پورت:** `1080`.
۵. **نام‌کاربری/رمز:** مقادیری که در مرحله نصب سرور ایران تعیین کردید را وارد کنید.
۶. گزینه **UDP Relay** را حتماً روشن کنید (برای تماس‌های صوتی و تصویری).
۷. متصل شوید! 🚀
