# ðŸš€ RareTriccks VPN Panel

A powerful VPN management panel with Dropbear SSH, Nginx SSL WebSocket Proxy, Automated Bandwidth tracking, and Interactive Telegram Bot Integration.

---

### ðŸš¨ Fast 1-Line Installation

Run this command as root:

```bash
wget -q -O /usr/local/bin/menu https://raw.githubusercontent.com/abdulbasit95950/vps-panel/main/menu.sh && chmod +x /usr/local/bin/menu
```

---

### ðŸ”Œ Supported Ports

* **SSH Direct:** 22, 109, 447
* **SSH WebSocket (HTTP):** 80
* **SSH WebSocket (SSL):** 443
* **WS Internal Proxy:** 2082

---

### âœ¨ Key Features

* **Dynamic Domain:** Assign and update custom domain easily.
* **SSL Certificate:** Auto Let's Encrypt SSL.
* **WebSocket Engine:** Built-in Python proxy service.
* **User Manager:** Account lifecycle & expiration tracking.
* **Auto-Kill System:** Bandwidth & IP overuse protection.
* **Telegram Bot Control:** Full GUI-like menu interface with interactive buttons (`tgbot.py`).

---

### ðŸ¤– Bot Features (Button-Based GUI)

Manage your VPN server with single-click inline buttons directly inside Telegram:

* **ðŸ”˜ Create Account** - Interactive step-by-step SSH/VPN account creation.
* **ðŸ”˜ Renew User** - Quickly extend user validity and expiration dates.
* **ðŸ”˜ Delete User** - Instant account termination and access removal.
* **ðŸ”˜ User List** - View all active users, expiry dates, and usage stats.
* **ðŸ”˜ Server Status** - Real-time monitoring for RAM, CPU, Uptime, and Active SSH Sessions.
* **ðŸ”˜ Restart Services** - One-click restart for Dropbear, Nginx, and Python WebSocket services.

---

Powered by RareTriccks â€¢ Managed via menu command & Telegram Bot
