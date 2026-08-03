cat << 'EOF' > /usr/local/bin/menu
#!/bin/bash

# ==============================================================================
# Script Name   : RareTriccks VPN Panel (Dynamic Domain Supported)
# Custom Path   : /raretriccks
# ==============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

PANEL_NAME="RareTriccks VPN Panel"
BANNER_FILE="/etc/issue.net"
CUSTOM_PATH="/raretriccks"
DOMAIN_FILE="/etc/raretriccks/domain.conf"

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}[ERROR] Yeh script ROOT privilege ke sath chalaen! (sudo -i)${NC}"
   exit 1
fi

get_domain() {
    if [[ -f "$DOMAIN_FILE" ]]; then
        cat "$DOMAIN_FILE" | tr -d '\r\n'
    else
        echo "No Domain Set"
    fi
}

press_any_key() {
    echo -e "\n${YELLOW}Press [ENTER] key to return to main menu...${NC}"
    read -r
}

install_python_tracker() {
    cat << 'PY_EOF' > /usr/local/bin/autokill.py
import os
import sys
import time
import subprocess
import re

USER_DIR = "/etc/raretriccks/users"
LOG_FILE = "/var/log/autokill.log"

def get_auth_logs():
    raw = ""
    try:
        raw = subprocess.check_output(["journalctl", "-u", "dropbear", "--no-pager", "-n", "300"], stderr=subprocess.DEVNULL).decode("utf-8", errors="ignore")
    except Exception:
        pass
    if os.path.exists("/var/log/auth.log"):
        try:
            with open("/var/log/auth.log", "r", encoding="utf-8", errors="ignore") as f:
                raw += "\n" + f.read()
        except Exception:
            pass
    return raw

def get_active_users_and_pids(raw_logs):
    user_pids = {}
    try:
        ps_out = subprocess.check_output(["ps", "aux"], stderr=subprocess.DEVNULL).decode("utf-8", errors="ignore")
        for line in ps_out.splitlines():
            if "dropbear" in line and "grep" not in line:
                parts = line.split()
                if len(parts) > 1:
                    pid = parts[1]
                    matches = [l for l in raw_logs.splitlines() if f"dropbear[{pid}]" in l and "Password auth succeeded" in l]
                    if matches:
                        last_line = matches[-1]
                        m = re.search(r"for \x27(\w+)\x27", last_line)
                        if not m:
                            m = re.search(r"for (\w+)", last_line)
                        if m:
                            uname = m.group(1)
                            if uname not in user_pids:
                                user_pids[uname] = []
                            user_pids[uname].append(pid)
    except Exception:
        pass
    return user_pids

def get_pid_io_bytes(pid):
    io_file = f"/proc/{pid}/io"
    total_bytes = 0
    if os.path.exists(io_file):
        try:
            with open(io_file, "r") as f:
                for line in f:
                    if line.startswith("rchar:") or line.startswith("wchar:"):
                        total_bytes += int(line.split(":")[1].strip())
        except Exception:
            pass
    return total_bytes

last_pid_bytes = {}

while True:
    try:
        raw_logs = get_auth_logs()
        user_pids_map = get_active_users_and_pids(raw_logs)

        if os.path.exists(USER_DIR):
            for fname in os.listdir(USER_DIR):
                if not fname.endswith(".conf"):
                    continue

                uname = fname[:-5]
                conf_path = os.path.join(USER_DIR, fname)

                ip_limit = 0
                gb_limit = "Unlimited"
                used_mb = 0.0

                with open(conf_path, "r") as f:
                    lines = f.readlines()

                for line in lines:
                    if line.startswith("IP_LIMIT="):
                        try: ip_limit = int(line.strip().split("=")[1])
                        except Exception: pass
                    elif line.startswith("GB_LIMIT="):
                        gb_limit = line.strip().split("=")[1]
                    elif line.startswith("USED_MB="):
                        try: used_mb = float(line.strip().split("=")[1])
                        except Exception: pass

                active_pids = user_pids_map.get(uname, [])

                for pid in active_pids:
                    current_b = get_pid_io_bytes(pid)
                    if pid in last_pid_bytes:
                        diff = current_b - last_pid_bytes[pid]
                        if diff > 0:
                            used_mb += (diff / (1024.0 * 1024.0))
                    last_pid_bytes[pid] = current_b

                new_lines = []
                for line in lines:
                    if line.startswith("USED_MB="):
                        new_lines.append(f"USED_MB={used_mb:.2f}\n")
                    else:
                        new_lines.append(line)
                with open(conf_path, "w") as f:
                    f.writelines(new_lines)

                if gb_limit != "Unlimited":
                    try:
                        max_mb = float(gb_limit) * 1024.0
                        if used_mb >= max_mb:
                            subprocess.call(["passwd", "-l", uname], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                            for pid in active_pids:
                                subprocess.call(["kill", "-9", pid], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    except Exception:
                        pass

                if ip_limit > 0 and len(active_pids) > ip_limit:
                    subprocess.call(["passwd", "-l", uname], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    for pid in active_pids:
                        subprocess.call(["kill", "-9", pid], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    except Exception:
        pass

    time.sleep(3)
PY_EOF
    chmod +x /usr/local/bin/autokill.py

    cat << 'SVC_EOF' > /etc/systemd/system/autokill.service
[Unit]
Description=RareTriccks Auto-Kill & Bandwidth Tracking Service
After=network.target

[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/autokill.py
Restart=always

[Install]
WantedBy=multi-user.target
SVC_EOF

    systemctl daemon-reload
    systemctl enable autokill
    systemctl restart autokill
}

install_tgbot_script() {
    cat << 'PY_EOF' > /usr/local/bin/tgbot.py
import os
import re
import json
import asyncio
import subprocess
from datetime import datetime, timedelta

from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import (
    Application, CommandHandler, CallbackQueryHandler,
    MessageHandler, ContextTypes, filters,
)

PANEL_NAME = "RareTriccks VPN Panel"
CONFIG_FILE = "/etc/raretriccks/tgbot/config.json"
ADMINS_FILE = "/etc/raretriccks/tgbot/admins.json"
USERS_DIR = "/etc/raretriccks/users"
DOMAIN_FILE = "/etc/raretriccks/domain.conf"
BANNER_FILE = "/etc/issue.net"

NGINX_TEMPLATE = """server {{
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name {dom} _;

    location / {{
        proxy_redirect off;
        proxy_pass http://127.0.0.1:2082;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }}

    location /raretriccks {{
        proxy_redirect off;
        proxy_pass http://127.0.0.1:2082;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }}
}}

server {{
    listen 443 ssl http2 default_server;
    listen [::]:443 ssl http2 default_server;
    server_name {dom} _;

    ssl_certificate /etc/letsencrypt/live/{dom}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/{dom}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;

    location / {{
        proxy_redirect off;
        proxy_pass http://127.0.0.1:2082;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }}

    location /raretriccks {{
        proxy_redirect off;
        proxy_pass http://127.0.0.1:2082;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }}
}}
"""

FLOWS = {
    "add_user": [
        ("username", "👤 Username enter karein:"),
        ("password", "🔑 Password enter karein:"),
        ("days", "📅 Expiry days enter karein (e.g. 30):"),
        ("ip_limit", "🌐 Max IP Limit enter karein (e.g. 1):"),
        ("gb_limit", "💾 Data Limit GB enter karein (e.g. 5, ya Unlimited):"),
    ],
    "del_user": [("username", "👤 Delete karne ke liye Username enter karein:")],
    "renew_user": [
        ("username", "👤 Username enter karein jise renew karna hai:"),
        ("days", "📅 Kitne additional days add karne hain?"),
    ],
    "ip_limit": [
        ("username", "👤 Username enter karein:"),
        ("value", "🌐 Naya IP Limit enter karein:"),
    ],
    "gb_limit": [
        ("username", "👤 Username enter karein:"),
        ("value", "💾 Naya GB Limit enter karein:"),
    ],
    "domain": [("value", "🌐 Naya domain enter karein (e.g. sub.example.com):")],
    "banner": [("value", "📢 Naya SSH banner text bhejein:")],
    "add_admin": [("value", "👑 Naye Admin ka Telegram User ID enter karein:")],
    "remove_admin": [("value", "🗑️ Remove karne ke liye Admin ka Telegram User ID enter karein:")],
}


def load_config():
    with open(CONFIG_FILE) as f:
        return json.load(f)


def load_admins():
    if not os.path.exists(ADMINS_FILE):
        return []
    with open(ADMINS_FILE) as f:
        return json.load(f)


def save_admins(admins):
    with open(ADMINS_FILE, "w") as f:
        json.dump(admins, f)


def is_admin(uid):
    return uid in load_admins()


def is_super(uid):
    cfg = load_config()
    return uid == cfg.get("super_admin")


def sh(cmd_list, input_data=None):
    return subprocess.run(cmd_list, capture_output=True, text=True, input=input_data)


def run(cmd_str):
    return subprocess.run(cmd_str, shell=True, capture_output=True, text=True)


def get_domain():
    if os.path.exists(DOMAIN_FILE):
        with open(DOMAIN_FILE) as f:
            d = f.read().strip()
            return d if d else "No Domain Set"
    return "No Domain Set"


def apply_nginx_config():
    dom = get_domain()
    if dom == "No Domain Set":
        return
    os.makedirs("/etc/nginx/conf.d", exist_ok=True)
    with open("/etc/nginx/conf.d/vpn.conf", "w") as f:
        f.write(NGINX_TEMPLATE.format(dom=dom))
    sh(["rm", "-f", "/etc/nginx/sites-enabled/default"])
    sh(["systemctl", "restart", "nginx"])


def valid_username(u):
    return re.match(r"^[a-zA-Z_][a-zA-Z0-9_-]{0,31}$", u) is not None


def add_user(username, password, days, ip_limit, gb_limit):
    if not valid_username(username):
        return False, "Invalid username (letter se start, sirf a-z 0-9 _ - allowed)."
    try:
        exp_date = (datetime.now() + timedelta(days=int(days))).strftime("%Y-%m-%d")
    except ValueError:
        return False, "Invalid days value."
    r = sh(["useradd", "-M", "-s", "/bin/bash", "-e", exp_date, username])
    if r.returncode != 0:
        return False, (r.stderr.strip() or "User create failed (already exists?)")
    sh(["chpasswd"], input_data=f"{username}:{password}\n")
    os.makedirs(USERS_DIR, exist_ok=True)
    with open(f"{USERS_DIR}/{username}.conf", "w") as f:
        f.write(f"IP_LIMIT={ip_limit}\nGB_LIMIT={gb_limit}\nUSED_MB=0.0\n")
    return True, exp_date


def delete_user(username):
    sh(["userdel", "-f", username])
    try:
        os.remove(f"{USERS_DIR}/{username}.conf")
    except FileNotFoundError:
        pass


def renew_user(username, days):
    r = sh(["id", username])
    if r.returncode != 0:
        return False
    try:
        new_exp = (datetime.now() + timedelta(days=int(days))).strftime("%Y-%m-%d")
    except ValueError:
        return False
    sh(["usermod", "-e", new_exp, username])
    sh(["passwd", "-u", username])
    return True


def update_conf_field(username, field, value):
    path = f"{USERS_DIR}/{username}.conf"
    if not os.path.exists(path):
        return False
    lines = open(path).readlines()
    new_lines = []
    found = False
    for line in lines:
        if line.startswith(f"{field}="):
            new_lines.append(f"{field}={value}\n")
            found = True
        else:
            new_lines.append(line)
    if not found:
        new_lines.append(f"{field}={value}\n")
    with open(path, "w") as f:
        f.writelines(new_lines)
    sh(["passwd", "-u", username])
    return True


def list_users_text():
    if not os.path.isdir(USERS_DIR):
        return "Koi user nahi mila."
    entries = []
    for fname in sorted(os.listdir(USERS_DIR)):
        if not fname.endswith(".conf"):
            continue
        uname = fname[:-5]
        data = {}
        for l in open(f"{USERS_DIR}/{fname}"):
            if "=" in l:
                k, v = l.strip().split("=", 1)
                data[k] = v
        exists = sh(["id", uname]).returncode == 0
        status = "Deleted"
        if exists:
            p = sh(["passwd", "-S", uname])
            status = "LOCKED" if " L " in f" {p.stdout} " else "Active"
        used_mb = 0.0
        try:
            used_mb = float(data.get("USED_MB", "0") or 0)
        except ValueError:
            pass
        used_gb = round(used_mb / 1024, 2)
        entries.append(
            f"👤 {uname} | IP:{data.get('IP_LIMIT', '?')} | "
            f"Used:{used_gb}GB / {data.get('GB_LIMIT', '?')}GB | {status}"
        )
    return "\n".join(entries) if entries else "Koi user nahi mila."


def connected_ips_text():
    r = sh(["ss", "-tnp"])
    lines = [l for l in r.stdout.splitlines() if (":109" in l or ":447" in l) and "ESTAB" in l]
    return f"🔌 Active SSH/WS sessions (approx): {len(lines)}"


def status_text():
    def st(svc):
        r = sh(["systemctl", "is-active", svc])
        return "🟢 ACTIVE" if r.stdout.strip() == "active" else "🔴 INACTIVE"

    dom = get_domain()
    return (
        f"🌍 Domain: {dom}\n\n"
        f"Nginx: {st('nginx')}\n"
        f"Dropbear: {st('dropbear')}\n"
        f"WS Proxy: {st('ws-proxy')}\n"
        f"Auto-Kill: {st('autokill')}"
    )


def set_domain(new_domain):
    os.makedirs("/etc/raretriccks", exist_ok=True)
    with open(DOMAIN_FILE, "w") as f:
        f.write(new_domain)
    apply_nginx_config()


def setup_ssl():
    dom = get_domain()
    if dom == "No Domain Set":
        return False, "Pehle domain set karein."
    sh(["systemctl", "stop", "nginx"])
    r = sh([
        "certbot", "certonly", "--standalone", "--preferred-challenges", "http",
        "--agree-tos", "--register-unsafely-without-email", "-d", dom,
    ])
    ok = os.path.exists(f"/etc/letsencrypt/live/{dom}/fullchain.pem")
    if ok:
        apply_nginx_config()
        return True, "SSL issued successfully."
    return False, "SSL fail ho gaya. Domain A record VPS IP par pointed hai check karein."


def fix_websocket():
    sh(["systemctl", "restart", "dropbear"])
    sh(["systemctl", "daemon-reload"])
    sh(["systemctl", "restart", "ws-proxy"])
    sh(["systemctl", "restart", "autokill"])
    apply_nginx_config()
    return "WebSocket & Bandwidth engine restarted."


def schedule_self_removal():
    subprocess.Popen([
        "bash", "-c",
        "sleep 3 && systemctl disable tgbot 2>/dev/null; "
        "systemctl stop tgbot 2>/dev/null; "
        "rm -f /etc/systemd/system/tgbot.service /usr/local/bin/tgbot.py; "
        "systemctl daemon-reload",
    ])


def back_keyboard():
    return InlineKeyboardMarkup([[InlineKeyboardButton("⬅️ Back to Menu", callback_data="back_main")]])


def main_menu_keyboard(uid):
    rows = [
        [InlineKeyboardButton("➕ Add User", callback_data="add_user"),
         InlineKeyboardButton("🗑️ Delete User", callback_data="del_user")],
        [InlineKeyboardButton("📋 User List", callback_data="list_users"),
         InlineKeyboardButton("⏳ Renew User", callback_data="renew_user")],
        [InlineKeyboardButton("🌐 IP Limit", callback_data="ip_limit"),
         InlineKeyboardButton("💾 GB Limit", callback_data="gb_limit")],
        [InlineKeyboardButton("🔌 Connected IPs", callback_data="conn_ips"),
         InlineKeyboardButton("⚙️ Status", callback_data="sys_status")],
        [InlineKeyboardButton("🌍 Domain", callback_data="domain"),
         InlineKeyboardButton("🔒 SSL", callback_data="ssl")],
        [InlineKeyboardButton("📢 Banner", callback_data="banner"),
         InlineKeyboardButton("🛠️ Fix WebSocket", callback_data="fix_ws")],
        [InlineKeyboardButton("📦 Install Components", callback_data="install"),
         InlineKeyboardButton("🧨 Uninstall Panel", callback_data="uninstall")],
    ]
    if is_super(uid):
        rows.append([InlineKeyboardButton("👑 Admin Management", callback_data="admin_mgmt")])
    return InlineKeyboardMarkup(rows)


def admins_text():
    cfg = load_config()
    admins = load_admins()
    lines = ["👑 *Admin Management*\n"]
    for a in admins:
        tag = " (Super Admin)" if a == cfg.get("super_admin") else ""
        lines.append(f"• `{a}`{tag}")
    return "\n".join(lines)


def admin_menu_keyboard():
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("➕ Add Admin", callback_data="add_admin"),
         InlineKeyboardButton("➖ Remove Admin", callback_data="remove_admin")],
        [InlineKeyboardButton("⬅️ Back", callback_data="back_main")],
    ])


async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    uid = update.effective_user.id
    if not is_admin(uid):
        await update.message.reply_text("⛔ Access Denied. Aap authorized admin nahi hain.")
        return
    context.user_data['flow'] = None
    await update.message.reply_text(
        f"👋 Welcome to {PANEL_NAME}\n\nApna option chunein:",
        reply_markup=main_menu_keyboard(uid),
    )


async def cancel(update: Update, context: ContextTypes.DEFAULT_TYPE):
    context.user_data['flow'] = None
    await update.message.reply_text("Cancelled.")


async def execute_flow(flow, data, update: Update):
    if flow == "add_user":
        ok, info = add_user(data["username"], data["password"], data["days"], data["ip_limit"], data["gb_limit"])
        if ok:
            dom = get_domain()
            msg = (
                f"✅ *Account Created*\n\n"
                f"Domain: `{dom}`\n"
                f"Username: `{data['username']}`\n"
                f"Password: `{data['password']}`\n"
                f"Expiry: `{info}`\n"
                f"IP Limit: `{data['ip_limit']}`\n"
                f"GB Limit: `{data['gb_limit']}`\n\n"
                f"SSH Direct: 22, 109, 447\nSSH WS (HTTP): 80\nSSH WS (SSL): 443"
            )
        else:
            msg = f"❌ User create fail: {info}"
        await update.message.reply_text(msg, parse_mode="Markdown", reply_markup=back_keyboard())
    elif flow == "renew_user":
        ok = renew_user(data["username"], data["days"])
        await update.message.reply_text(
            "✅ Renewed." if ok else "❌ User not found.", reply_markup=back_keyboard()
        )
    elif flow == "ip_limit":
        ok = update_conf_field(data["username"], "IP_LIMIT", data["value"])
        await update.message.reply_text(
            "✅ IP limit updated." if ok else "❌ User config not found.",
            reply_markup=back_keyboard(),
        )
    elif flow == "gb_limit":
        ok = update_conf_field(data["username"], "GB_LIMIT", data["value"])
        await update.message.reply_text(
            "✅ GB limit updated." if ok else "❌ User config not found.",
            reply_markup=back_keyboard(),
        )
    elif flow == "domain":
        set_domain(data["value"])
        await update.message.reply_text(f"✅ Domain set to {data['value']}", reply_markup=back_keyboard())
    elif flow == "banner":
        with open(BANNER_FILE, "w") as f:
            f.write(data["value"])
        sh(["systemctl", "restart", "dropbear"])
        sh(["systemctl", "restart", "ssh"])
        await update.message.reply_text("✅ Banner updated.", reply_markup=back_keyboard())
    elif flow == "add_admin":
        try:
            new_id = int(data["value"])
        except ValueError:
            await update.message.reply_text("❌ Invalid ID.")
            return
        admins = load_admins()
        if new_id in admins:
            await update.message.reply_text("⚠️ Already an admin.")
        else:
            admins.append(new_id)
            save_admins(admins)
            await update.message.reply_text(f"✅ Admin {new_id} added.", reply_markup=admin_menu_keyboard())


async def text_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    uid = update.effective_user.id
    if not is_admin(uid):
        return
    flow = context.user_data.get('flow')
    if not flow:
        return
    step = context.user_data.get('step', 0)
    field, _ = FLOWS[flow][step]
    context.user_data.setdefault('data', {})[field] = update.message.text.strip()
    step += 1
    if step < len(FLOWS[flow]):
        context.user_data['step'] = step
        await update.message.reply_text(FLOWS[flow][step][1])
        return

    data = context.user_data['data']
    context.user_data['flow'] = None

    if flow == "del_user":
        username = data["username"]
        kb = InlineKeyboardMarkup([[
            InlineKeyboardButton("✅ Confirm Delete", callback_data=f"do_del:{username}"),
            InlineKeyboardButton("❌ Cancel", callback_data="back_main"),
        ]])
        await update.message.reply_text(f"⚠️ '{username}' delete karna confirm karein:", reply_markup=kb)
        return

    if flow == "remove_admin":
        try:
            target = int(data["value"])
        except ValueError:
            await update.message.reply_text("❌ Invalid ID.")
            return
        cfg = load_config()
        if target == cfg.get("super_admin"):
            await update.message.reply_text("❌ Super admin remove nahi ho sakta.")
            return
        kb = InlineKeyboardMarkup([[
            InlineKeyboardButton("✅ Confirm Remove", callback_data=f"rm_admin:{target}"),
            InlineKeyboardButton("❌ Cancel", callback_data="back_main"),
        ]])
        await update.message.reply_text(f"⚠️ Admin {target} remove karna confirm karein:", reply_markup=kb)
        return

    await execute_flow(flow, data, update)


async def button_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    q = update.callback_query
    uid = q.from_user.id
    if not is_admin(uid):
        await q.answer("Access denied.", show_alert=True)
        return
    data = q.data
    await q.answer()

    if data == "back_main":
        context.user_data['flow'] = None
        await q.edit_message_text("📋 Main Menu", reply_markup=main_menu_keyboard(uid))
    elif data in FLOWS:
        context.user_data['flow'] = data
        context.user_data['step'] = 0
        context.user_data['data'] = {}
        field, prompt = FLOWS[data][0]
        await q.edit_message_text(prompt)
    elif data == "list_users":
        await q.edit_message_text(list_users_text(), reply_markup=back_keyboard())
    elif data == "conn_ips":
        await q.edit_message_text(connected_ips_text(), reply_markup=back_keyboard())
    elif data == "sys_status":
        await q.edit_message_text(status_text(), reply_markup=back_keyboard())
    elif data == "ssl":
        await q.edit_message_text("🔒 SSL issue ho raha hai, wait karein...")
        ok, msg = await asyncio.to_thread(setup_ssl)
        await q.message.reply_text(("✅ " if ok else "❌ ") + msg, reply_markup=back_keyboard())
    elif data == "fix_ws":
        msg = fix_websocket()
        await q.edit_message_text(f"✅ {msg}", reply_markup=back_keyboard())
    elif data == "install":
        await q.edit_message_text("📦 Poora system install ho raha hai (packages + Dropbear + WebSocket + Auto-Kill), 2-5 min lagega...")
        await asyncio.to_thread(install_components_sync)
        await q.message.reply_text(
            "✅ Installation complete! Packages, Dropbear, Banner, WebSocket Proxy aur "
            "Auto-Kill/Bandwidth service sab deploy ho gaye hain.\n"
            "ℹ️ Agar aapne pehle domain set nahi kiya to Nginx SSL block abhi apply nahi hoga "
            "— pehle Domain option se domain set karein, phir SSL issue karein.",
            reply_markup=back_keyboard(),
        )
    elif data == "uninstall":
        kb = InlineKeyboardMarkup([[
            InlineKeyboardButton("✅ Haan, Uninstall karein", callback_data="do_uninstall"),
            InlineKeyboardButton("❌ Cancel", callback_data="back_main"),
        ]])
        await q.edit_message_text(
            "⚠️ Yeh sab kuch permanently remove kar dega (users, services, config, is bot samet). "
            "Confirm karein:",
            reply_markup=kb,
        )
    elif data == "do_uninstall":
        await q.edit_message_text("🧨 Uninstalling...")
        await asyncio.to_thread(uninstall_all)
        await q.message.reply_text("✅ Uninstall complete. Bot khud bhi band ho raha hai.")
        schedule_self_removal()
    elif data == "admin_mgmt":
        if not is_super(uid):
            await q.answer("Sirf Super Admin ke liye.", show_alert=True)
            return
        await q.edit_message_text(admins_text(), parse_mode="Markdown", reply_markup=admin_menu_keyboard())
    elif data.startswith("do_del:"):
        username = data.split(":", 1)[1]
        delete_user(username)
        await q.edit_message_text(f"✅ User {username} deleted.", reply_markup=back_keyboard())
    elif data.startswith("rm_admin:"):
        target = int(data.split(":", 1)[1])
        cfg = load_config()
        if target == cfg.get("super_admin"):
            await q.answer("Super admin remove nahi ho sakta.", show_alert=True)
            return
        admins = load_admins()
        if target in admins:
            admins.remove(target)
            save_admins(admins)
        await q.edit_message_text(admins_text(), parse_mode="Markdown", reply_markup=admin_menu_keyboard())


def main():
    cfg = load_config()
    app = Application.builder().token(cfg["token"]).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("cancel", cancel))
    app.add_handler(CallbackQueryHandler(button_handler))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, text_handler))
    app.run_polling()


if __name__ == "__main__":
    main()
PY_EOF
    chmod +x /usr/local/bin/tgbot.py

    cat << 'SVC_EOF' > /etc/systemd/system/tgbot.service
[Unit]
Description=RareTriccks Telegram Bot
After=network.target

[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/tgbot.py
Restart=always

[Install]
WantedBy=multi-user.target
SVC_EOF
}
