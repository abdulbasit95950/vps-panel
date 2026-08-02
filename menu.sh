#!/bin/bash
# === MD5 HASH IP APPROVAL SYSTEM ===
AUTHORIZED_HASHES_URL="https://raw.githubusercontent.com/Abdulbasit95950/vps-panel/main/ips.txt"
SERVER_IP=$(curl -s https://ipinfo.io/ip || curl -s ifconfig.me)

if [[ -n "$SERVER_IP" ]]; then
    # Server IP ka MD5 hash generate karna
    SERVER_IP_HASH=$(echo -n "$SERVER_IP" | md5sum | awk '{print $1}')
    
    # GitHub se ips.txt file fetch karke hash match karna
    CHECK_HASH=$(curl -s "$AUTHORIZED_HASHES_URL" | grep -w "$SERVER_IP_HASH")
    
    if [[ -z "$CHECK_HASH" ]]; then
        echo -e "\033[0;31m[ERROR] Yeh IP ($SERVER_IP) authorized nahi hai!\033[0m"
        echo -e "\033[1;33mPlease contact developer @Abdulbasit95950 to approve your IP.\033[0m"
        exit 1
    fi
else
    echo -e "\033[0;31m[ERROR] Server IP detect nahi ho saki!\033[0m"
    exit 1
fi


# ==============================================================================
# Script Name   : RareTriccks VPN Panel (Full Telegram Buttons & Admin Control)
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
DOMAIN_FILE="/etc/raretriccks/domain.conf"
BOT_CONF="/etc/raretriccks/bot.conf"
ADMIN_IDS_FILE="/etc/raretriccks/admin_ids.conf"
USER_STATE_DIR="/etc/raretriccks/bot_states"

mkdir -p /etc/raretriccks /etc/raretriccks/users "$USER_STATE_DIR"

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

get_service_status() {
    local s_name="$1"
    if systemctl is-active --quiet "$s_name" 2>/dev/null; then
        echo -e "${GREEN}ON${NC}"
    else
        echo -e "${RED}OFF${NC}"
    fi
}

press_any_key() {
    echo -e "\n${YELLOW}Press [ENTER] key to return to menu...${NC}"
    read -r
}

# ==============================================================================
# FULL BUTTON-BASED TELEGRAM BOT ENGINE
# ==============================================================================
install_telegram_bot() {
    cat << 'TG_EOF' > /usr/local/bin/tgbot.py
import os, sys, time, subprocess, re, json, requests

BOT_CONF = "/etc/raretriccks/bot.conf"
ADMIN_IDS_FILE = "/etc/raretriccks/admin_ids.conf"
USER_DIR = "/etc/raretriccks/users"
DOMAIN_FILE = "/etc/raretriccks/domain.conf"
BANNER_FILE = "/etc/issue.net"
STATE_DIR = "/etc/raretriccks/bot_states"

os.makedirs(STATE_DIR, exist_ok=True)

def get_token():
    if os.path.exists(BOT_CONF):
        with open(BOT_CONF, 'r') as f:
            return f.read().strip()
    return None

def get_admins():
    if os.path.exists(ADMIN_IDS_FILE):
        with open(ADMIN_IDS_FILE, 'r') as f:
            return [line.strip() for line in f if line.strip()]
    return []

def get_domain():
    if os.path.exists(DOMAIN_FILE):
        with open(DOMAIN_FILE, 'r') as f:
            return f.read().strip()
    return "No Domain Set"

TOKEN = get_token()
if not TOKEN:
    sys.exit(0)

API_URL = f"https://api.telegram.org/bot{TOKEN}/"

def send_api(method, payload):
    try:
        r = requests.post(API_URL + method, json=payload, timeout=10)
        return r.json()
    except Exception:
        return {}

def get_user_state(chat_id):
    path = f"{STATE_DIR}/{chat_id}.json"
    if os.path.exists(path):
        try:
            with open(path, 'r') as f: return json.load(f)
        except Exception: pass
    return {}

def set_user_state(chat_id, data):
    path = f"{STATE_DIR}/{chat_id}.json"
    if not data:
        if os.path.exists(path): os.remove(path)
    else:
        with open(path, 'w') as f: json.dump(data, f)

def build_main_keyboard():
    return {
        "inline_keyboard": [
            [{"text": "👤 Account Management", "callback_data": "menu_users"}, {"text": "🌐 Domain & SSL", "callback_data": "menu_domain"}],
            [{"text": "📊 Live Online Users", "callback_data": "cmd_online"}, {"text": "⚙️ System & Services", "callback_data": "menu_services"}],
            [{"text": "👮 Manage Admins", "callback_data": "menu_admins"}, {"text": "🔄 Restart All Services", "callback_data": "cmd_fix"}],
            [{"text": "📋 User List & Usage", "callback_data": "cmd_users_list"}]
        ]
    }

def build_users_keyboard():
    return {
        "inline_keyboard": [
            [{"text": "➕ Create Account", "callback_data": "act_add_start"}, {"text": "❌ Delete Account", "callback_data": "act_del_start"}],
            [{"text": "📅 Renew Expiry", "callback_data": "act_renew_start"}, {"text": "📱 Modify IP Limit", "callback_data": "act_ip_start"}],
            [{"text": "📊 Modify GB Limit", "callback_data": "act_gb_start"}],
            [{"text": "🔙 Main Menu", "callback_data": "menu_main"}]
        ]
    }

def build_domain_keyboard():
    return {
        "inline_keyboard": [
            [{"text": "✏️ Set / Change Domain", "callback_data": "act_domain_start"}],
            [{"text": "🔒 Issue / Renew SSL Certificate", "callback_data": "act_ssl_run"}],
            [{"text": "🔙 Main Menu", "callback_data": "menu_main"}]
        ]
    }

def build_services_keyboard():
    return {
        "inline_keyboard": [
            [{"text": "🔄 Restart Nginx", "callback_data": "srv_restart_nginx"}, {"text": "🔄 Restart Dropbear", "callback_data": "srv_restart_dropbear"}],
            [{"text": "🔄 Restart WS Proxy", "callback_data": "srv_restart_ws"}, {"text": "🔄 Restart AutoKill", "callback_data": "srv_restart_autokill"}],
            [{"text": "🔍 Check Status", "callback_data": "cmd_status"}],
            [{"text": "🔙 Main Menu", "callback_data": "menu_main"}]
        ]
    }

def build_admins_keyboard():
    return {
        "inline_keyboard": [
            [{"text": "➕ Add Admin ID", "callback_data": "act_add_admin"}, {"text": "➖ Remove Admin ID", "callback_data": "act_del_admin"}],
            [{"text": "📋 View Allowed Admins", "callback_data": "act_list_admins"}],
            [{"text": "🔙 Main Menu", "callback_data": "menu_main"}]
        ]
    }

def send_main_menu(chat_id, text="<b>🤖 RareTriccks VPN Control Panel</b>\nChoose an option below:"):
    send_api("sendMessage", {
        "chat_id": chat_id,
        "text": text,
        "parse_mode": "HTML",
        "reply_markup": build_main_keyboard()
    })

def edit_message(chat_id, message_id, text, keyboard=None):
    payload = {
        "chat_id": chat_id,
        "message_id": message_id,
        "text": text,
        "parse_mode": "HTML"
    }
    if keyboard: payload["reply_markup"] = keyboard
    send_api("editMessageText", payload)

def get_connected_ips_text():
    try:
        raw_logs = ""
        try:
            raw_logs = subprocess.check_output(["journalctl", "-u", "dropbear", "--no-pager", "-n", "300"], stderr=subprocess.DEVNULL).decode("utf-8", errors="ignore")
        except Exception: pass
        if os.path.exists("/var/log/auth.log"):
            with open("/var/log/auth.log", "r", encoding="utf-8", errors="ignore") as f:
                raw_logs += "\n" + f.read()

        ps_out = subprocess.check_output(["ps", "aux"], stderr=subprocess.DEVNULL).decode("utf-8", errors="ignore")
        pids = [l.split()[1] for l in ps_out.splitlines() if "dropbear" in l and "grep" not in l]

        online = []
        for pid in pids:
            matches = [l for l in raw_logs.splitlines() if f"dropbear[{pid}]" in l and "Password auth succeeded" in l]
            if matches:
                last_line = matches[-1]
                m = re.search(r"for \x27(\w+)\x27", last_line)
                if not m: m = re.search(r"for (\w+)", last_line)
                ip_m = re.search(r"from (\S+):", last_line)
                if m:
                    uname = m.group(1)
                    ip = ip_m.group(1) if ip_m else "WS-Proxy Client"
                    online.append(f"👤 <b>{uname}</b> ➔ <code>{ip}</code>")
        if not online: return "❌ No Active Online Sessions Found."
        return "🟢 <b>ACTIVE ONLINE USERS:</b>\n\n" + "\n".join(online)
    except Exception as e:
        return f"Error: {str(e)}"

def handle_callback(chat_id, message_id, data):
    set_user_state(chat_id, {})
    
    if data == "menu_main":
        edit_message(chat_id, message_id, "<b>🤖 RareTriccks VPN Control Panel</b>", build_main_keyboard())
    elif data == "menu_users":
        edit_message(chat_id, message_id, "<b>👤 Account Management Menu:</b>", build_users_keyboard())
    elif data == "menu_domain":
        dom = get_domain()
        edit_message(chat_id, message_id, f"<b>🌐 Domain & SSL Setup:</b>\nCurrent Domain: <code>{dom}</code>", build_domain_keyboard())
    elif data == "menu_services":
        edit_message(chat_id, message_id, "<b>⚙️ System & Services Control:</b>", build_services_keyboard())
    elif data == "menu_admins":
        edit_message(chat_id, message_id, "<b>👮 Admin Management Center:</b>", build_admins_keyboard())

    # --- ACTION FLOWS ---
    elif data == "act_add_start":
        set_user_state(chat_id, {"step": "add_username"})
        edit_message(chat_id, message_id, "✍️ <b>Step 1/5:</b> Enter NEW <b>Username</b>:")
    elif data == "act_del_start":
        set_user_state(chat_id, {"step": "del_username"})
        edit_message(chat_id, message_id, "🗑️ Enter <b>Username</b> to Delete:")
    elif data == "act_renew_start":
        set_user_state(chat_id, {"step": "renew_username"})
        edit_message(chat_id, message_id, "📅 Enter <b>Username</b> to Renew:")
    elif data == "act_ip_start":
        set_user_state(chat_id, {"step": "ip_username"})
        edit_message(chat_id, message_id, "📱 Enter <b>Username</b> to Change IP Limit:")
    elif data == "act_gb_start":
        set_user_state(chat_id, {"step": "gb_username"})
        edit_message(chat_id, message_id, "📊 Enter <b>Username</b> to Change Data Limit (GB):")
    elif data == "act_domain_start":
        set_user_state(chat_id, {"step": "domain_set"})
        edit_message(chat_id, message_id, "🌐 Enter your <b>Domain Name</b> (e.g. sub.mydomain.com):")
    elif data == "act_add_admin":
        set_user_state(chat_id, {"step": "admin_add"})
        edit_message(chat_id, message_id, "➕ Enter <b>Telegram Numeric User ID</b> to Allow:")
    elif data == "act_del_admin":
        set_user_state(chat_id, {"step": "admin_del"})
        edit_message(chat_id, message_id, "➖ Enter <b>Telegram Numeric User ID</b> to Remove:")

    # --- DIRECT COMMAND EXECUTIONS ---
    elif data == "cmd_online":
        edit_message(chat_id, message_id, get_connected_ips_text(), build_main_keyboard())
    elif data == "cmd_status":
        nginx = subprocess.call(["systemctl", "is-active", "--quiet", "nginx"]) == 0
        db = subprocess.call(["systemctl", "is-active", "--quiet", "dropbear"]) == 0
        ws = subprocess.call(["systemctl", "is-active", "--quiet", "ws-proxy"]) == 0
        ak = subprocess.call(["systemctl", "is-active", "--quiet", "autokill"]) == 0
        res = (
            "⚙️ <b>SYSTEM SERVICES STATUS:</b>\n\n"
            f"🔹 Nginx Engine: {'🟢 Active' if nginx else '🔴 Inactive'}\n"
            f"🔹 Dropbear SSH: {'🟢 Active' if db else '🔴 Inactive'}\n"
            f"🔹 WebSocket Proxy: {'🟢 Active' if ws else '🔴 Inactive'}\n"
            f"🔹 AutoKill Daemon: {'🟢 Active' if ak else '🔴 Inactive'}"
        )
        edit_message(chat_id, message_id, res, build_services_keyboard())
    elif data == "cmd_users_list":
        if not os.path.exists(USER_DIR):
            edit_message(chat_id, message_id, "No Users Registered.", build_main_keyboard())
            return
        out = "📋 <b>REGISTERED ACCOUNTS & USAGE:</b>\n\n"
        for fname in os.listdir(USER_DIR):
            if fname.endswith(".conf"):
                u = fname[:-5]
                ip_l, gb_l, used_m = "1", "Unlimited", "0"
                with open(f"{USER_DIR}/{fname}") as f:
                    for l in f:
                        if l.startswith("IP_LIMIT="): ip_l = l.strip().split("=")[1]
                        elif l.startswith("GB_LIMIT="): gb_l = l.strip().split("=")[1]
                        elif l.startswith("USED_MB="): used_m = l.strip().split("=")[1]
                used_gb = round(float(used_m)/1024.0, 2)
                out += f"👤 <b>{u}</b> | IP: {ip_l} | Used: {used_gb}GB / {gb_l}GB\n"
        edit_message(chat_id, message_id, out, build_main_keyboard())

    elif data == "act_ssl_run":
        dom = get_domain()
        if dom == "No Domain Set":
            edit_message(chat_id, message_id, "❌ <b>Error:</b> Please set a Domain first!", build_domain_keyboard())
            return
        edit_message(chat_id, message_id, f"⏳ Issuing SSL Certificate for <b>{dom}</b>... Please wait.")
        subprocess.call(["systemctl", "stop", "nginx"])
        r = subprocess.call(["certbot", "certonly", "--standalone", "--preferred-challenges", "http", "--agree-tos", "--register-unsafely-without-email", "-d", dom])
        if os.path.exists(f"/etc/letsencrypt/live/{dom}/fullchain.pem"):
            subprocess.call(["/usr/local/bin/menu", "apply_nginx"])
            edit_message(chat_id, message_id, f"✅ <b>SSL Activated Successfully for {dom}!</b>", build_domain_keyboard())
        else:
            edit_message(chat_id, message_id, f"❌ <b>SSL Failed!</b> Make sure A-Record points to server IP.", build_domain_keyboard())

    elif data.startswith("srv_restart_"):
        srv = data.replace("srv_restart_", "")
        s_name = "nginx" if srv == "nginx" else ("dropbear" if srv == "dropbear" else ("ws-proxy" if srv == "ws" else "autokill"))
        subprocess.call(["systemctl", "restart", s_name])
        edit_message(chat_id, message_id, f"🔄 Service <b>{s_name}</b> restarted successfully!", build_services_keyboard())

    elif data == "act_list_admins":
        admins = get_admins()
        res = "📋 <b>ALLOWED ADMIN TELEGRAM IDs:</b>\n\n" + "\n".join([f"• <code>{i}</code>" for i in admins]) if admins else "No admins configured."
        edit_message(chat_id, message_id, res, build_admins_keyboard())

    elif data == "cmd_fix":
        edit_message(chat_id, message_id, "🔄 Restarting all system engines...")
        subprocess.call(["systemctl", "restart", "dropbear"])
        subprocess.call(["systemctl", "restart", "ws-proxy"])
        subprocess.call(["systemctl", "restart", "autokill"])
        subprocess.call(["systemctl", "restart", "nginx"])
        edit_message(chat_id, message_id, "✅ <b>All System Services Refreshed & Active!</b>", build_main_keyboard())

def handle_text(chat_id, text):
    state = get_user_state(chat_id)
    step = state.get("step")

    if not step:
        send_main_menu(chat_id)
        return

    # CREATE USER MULTI-STEP FLOW
    if step == "add_username":
        set_user_state(chat_id, {"step": "add_password", "u": text})
        send_api("sendMessage", {"chat_id": chat_id, "text": "🔑 <b>Step 2/5:</b> Enter <b>Password</b>:", "parse_mode": "HTML"})

    elif step == "add_password":
        u = state.get("u")
        set_user_state(chat_id, {"step": "add_days", "u": u, "p": text})
        send_api("sendMessage", {"chat_id": chat_id, "text": "📅 <b>Step 3/5:</b> Enter <b>Expiry Days</b> (e.g. 30):", "parse_mode": "HTML"})

    elif step == "add_days":
        u, p = state.get("u"), state.get("p")
        set_user_state(chat_id, {"step": "add_ip", "u": u, "p": p, "d": text})
        send_api("sendMessage", {"chat_id": chat_id, "text": "📱 <b>Step 4/5:</b> Enter <b>Max IP Limit</b> (e.g. 1):", "parse_mode": "HTML"})

    elif step == "add_ip":
        u, p, d = state.get("u"), state.get("p"), state.get("d")
        set_user_state(chat_id, {"step": "add_gb", "u": u, "p": p, "d": d, "ip": text})
        send_api("sendMessage", {"chat_id": chat_id, "text": "📊 <b>Step 5/5:</b> Enter <b>GB Limit</b> (e.g. 50 ya Unlimited):", "parse_mode": "HTML"})

    elif step == "add_gb":
        u, p, d, ip_l = state.get("u"), state.get("p"), state.get("d"), state.get("ip")
        gb_l = text
        set_user_state(chat_id, {})
        try:
            exp_date = subprocess.check_output(["date", "-d", f"+{d} days", "+%Y-%m-%d"]).decode().strip()
            subprocess.call(["useradd", "-M", "-s", "/bin/false", "-e", exp_date, u])
            subprocess.run(f"echo '{u}:{p}' | chpasswd", shell=True)
            with open(f"{USER_DIR}/{u}.conf", "w") as f:
                f.write(f"IP_LIMIT={ip_l}\nGB_LIMIT={gb_l}\nUSED_MB=0.0\n")
            dom = get_domain()
            res = (
                f"✅ <b>ACCOUNT CREATED SUCCESSFULLY</b>\n\n"
                f"🌐 <b>Domain:</b> <code>{dom}</code>\n"
                f"👤 <b>Username:</b> <code>{u}</code>\n"
                f"🔑 <b>Password:</b> <code>{p}</code>\n"
                f"📅 <b>Expiry Date:</b> {exp_date}\n"
                f"📱 <b>Max IP Limit:</b> {ip_l} Device(s)\n"
                f"📊 <b>Data Quota:</b> {gb_l} GB\n\n"
                f"🔌 <b>Ports:</b> Direct: 22, 109, 447 | WS: 80 | WSS: 443"
            )
            send_api("sendMessage", {"chat_id": chat_id, "text": res, "parse_mode": "HTML", "reply_markup": build_users_keyboard()})
        except Exception as e:
            send_api("sendMessage", {"chat_id": chat_id, "text": f"❌ Failed: {str(e)}", "reply_markup": build_users_keyboard()})

    # DELETE USER
    elif step == "del_username":
        set_user_state(chat_id, {})
        u = text.strip()
        subprocess.call(["userdel", "-f", u], stderr=subprocess.DEVNULL)
        if os.path.exists(f"{USER_DIR}/{u}.conf"): os.remove(f"{USER_DIR}/{u}.conf")
        send_api("sendMessage", {"chat_id": chat_id, "text": f"🗑️ User <b>{u}</b> deleted!", "parse_mode": "HTML", "reply_markup": build_users_keyboard()})

    # RENEW USER
    elif step == "renew_username":
        set_user_state(chat_id, {"step": "renew_days", "u": text})
        send_api("sendMessage", {"chat_id": chat_id, "text": "📅 Enter <b>Days to add</b> (e.g. 30):", "parse_mode": "HTML"})

    elif step == "renew_days":
        u = state.get("u")
        d = text.strip()
        set_user_state(chat_id, {})
        try:
            exp_date = subprocess.check_output(["date", "-d", f"+{d} days", "+%Y-%m-%d"]).decode().strip()
            subprocess.call(["usermod", "-e", exp_date, u])
            subprocess.call(["passwd", "-u", u], stderr=subprocess.DEVNULL)
            send_api("sendMessage", {"chat_id": chat_id, "text": f"🎉 Extended <b>{u}</b> for {d} days.\n📅 New Expiry: <b>{exp_date}</b>", "parse_mode": "HTML", "reply_markup": build_users_keyboard()})
        except Exception as e:
            send_api("sendMessage", {"chat_id": chat_id, "text": f"❌ Error: {str(e)}", "reply_markup": build_users_keyboard()})

    # MODIFY IP
    elif step == "ip_username":
        set_user_state(chat_id, {"step": "ip_val", "u": text})
        send_api("sendMessage", {"chat_id": chat_id, "text": "📱 Enter <b>NEW IP Limit</b> (e.g. 2):", "parse_mode": "HTML"})

    elif step == "ip_val":
        u = state.get("u")
        new_ip = text.strip()
        set_user_state(chat_id, {})
        conf_path = f"{USER_DIR}/{u}.conf"
        if os.path.exists(conf_path):
            with open(conf_path, "r") as f: lines = f.readlines()
            with open(conf_path, "w") as f:
                for l in lines:
                    if l.startswith("IP_LIMIT="): f.write(f"IP_LIMIT={new_ip}\n")
                    else: f.write(l)
            subprocess.call(["passwd", "-u", u], stderr=subprocess.DEVNULL)
            send_api("sendMessage", {"chat_id": chat_id, "text": f"✅ IP Limit for <b>{u}</b> updated to {new_ip} & account UNLOCKED!", "parse_mode": "HTML", "reply_markup": build_users_keyboard()})
        else:
            send_api("sendMessage", {"chat_id": chat_id, "text": f"❌ User config for {u} not found!", "reply_markup": build_users_keyboard()})

    # MODIFY GB
    elif step == "gb_username":
        set_user_state(chat_id, {"step": "gb_val", "u": text})
        send_api("sendMessage", {"chat_id": chat_id, "text": "📊 Enter <b>NEW GB Quota</b> (e.g. 100):", "parse_mode": "HTML"})

    elif step == "gb_val":
        u = state.get("u")
        new_gb = text.strip()
        set_user_state(chat_id, {})
        conf_path = f"{USER_DIR}/{u}.conf"
        if os.path.exists(conf_path):
            with open(conf_path, "r") as f: lines = f.readlines()
            with open(conf_path, "w") as f:
                for l in lines:
                    if l.startswith("GB_LIMIT="): f.write(f"GB_LIMIT={new_gb}\n")
                    else: f.write(l)
            subprocess.call(["passwd", "-u", u], stderr=subprocess.DEVNULL)
            send_api("sendMessage", {"chat_id": chat_id, "text": f"✅ GB Limit for <b>{u}</b> updated to {new_gb} GB & account UNLOCKED!", "parse_mode": "HTML", "reply_markup": build_users_keyboard()})
        else:
            send_api("sendMessage", {"chat_id": chat_id, "text": f"❌ User config for {u} not found!", "reply_markup": build_users_keyboard()})

    # DOMAIN SET
    elif step == "domain_set":
        set_user_state(chat_id, {})
        new_dom = text.strip()
        with open(DOMAIN_FILE, "w") as f: f.write(new_dom)
        subprocess.call(["/usr/local/bin/menu", "apply_nginx"])
        send_api("sendMessage", {"chat_id": chat_id, "text": f"🌐 Domain successfully set to: <code>{new_dom}</code>", "parse_mode": "HTML", "reply_markup": build_domain_keyboard()})

    # ADMIN MANAGEMENT
    elif step == "admin_add":
        set_user_state(chat_id, {})
        new_aid = text.strip()
        with open(ADMIN_IDS_FILE, "a") as f: f.write(f"{new_aid}\n")
        send_api("sendMessage", {"chat_id": chat_id, "text": f"👮 Telegram ID <code>{new_aid}</code> authorized!", "parse_mode": "HTML", "reply_markup": build_admins_keyboard()})

    elif step == "admin_del":
        set_user_state(chat_id, {})
        rem_aid = text.strip()
        if os.path.exists(ADMIN_IDS_FILE):
            with open(ADMIN_IDS_FILE, "r") as f: lines = f.readlines()
            with open(ADMIN_IDS_FILE, "w") as f:
                for l in lines:
                    if l.strip() != rem_aid: f.write(l)
        send_api("sendMessage", {"chat_id": chat_id, "text": f"🗑️ Admin ID <code>{rem_aid}</code> removed!", "parse_mode": "HTML", "reply_markup": build_admins_keyboard()})

def main():
    offset = 0
    while True:
        try:
            admins = get_admins()
            res = send_api("getUpdates", {"offset": offset, "timeout": 10})
            if res.get("ok"):
                for update in res.get("result", []):
                    offset = update["update_id"] + 1

                    # Handle Callback Buttons
                    if "callback_query" in update:
                        cb = update["callback_query"]
                        chat_id = str(cb["message"]["chat"]["id"])
                        msg_id = cb["message"]["message_id"]
                        data = cb["data"]
                        send_api("answerCallbackQuery", {"callback_query_id": cb["id"]})
                        
                        if chat_id in admins:
                            handle_callback(chat_id, msg_id, data)
                        else:
                            send_api("sendMessage", {"chat_id": chat_id, "text": f"⛔ <b>Access Denied!</b>\nYour ID: <code>{chat_id}</code> is not authorized.", "parse_mode": "HTML"})

                    # Handle Incoming Text Inputs
                    elif "message" in update and "text" in update["message"]:
                        msg = update["message"]
                        chat_id = str(msg["chat"]["id"])
                        text = msg["text"]
                        
                        if chat_id in admins:
                            if text == "/start":
                                set_user_state(chat_id, {})
                                send_main_menu(chat_id)
                            else:
                                handle_text(chat_id, text)
                        else:
                            send_api("sendMessage", {"chat_id": chat_id, "text": f"⛔ <b>Access Denied!</b>\nYour ID: <code>{chat_id}</code> is not authorized.", "parse_mode": "HTML"})
        except Exception: pass
        time.sleep(2)

if __name__ == "__main__":
    main()
TG_EOF
    chmod +x /usr/local/bin/tgbot.py

    cat << SVC_EOF > /etc/systemd/system/tgbot.service
[Unit]
Description=RareTriccks VPN Telegram Bot Control Service
After=network.target

[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/tgbot.py
Restart=always

[Install]
WantedBy=multi-user.target
SVC_EOF

    systemctl daemon-reload
    systemctl enable tgbot
    systemctl restart tgbot
}

# ==============================================================================
# TELEGRAM BOT MANAGEMENT MENU
# ==============================================================================
telegram_bot_menu() {
    while true; do
        clear
        echo -e "${CYAN}====================================================${NC}"
        echo -e "${YELLOW}     TELEGRAM BOT CONTROL & ACCESS CENTER          ${NC}"
        echo -e "${CYAN}====================================================${NC}"
        
        local bot_status="${RED}[ NOT CONFIGURED ]${NC}"
        if [[ -f "$BOT_CONF" && -s "$BOT_CONF" ]]; then
            if systemctl is-active --quiet tgbot; then
                bot_status="${GREEN}[ ACTIVE & RUNNING ]${NC}"
            else
                bot_status="${YELLOW}[ STOPPED / ERROR ]${NC}"
            fi
        fi

        echo -e " Bot Status : ${bot_status}"
        echo -e "${CYAN}----------------------------------------------------${NC}"
        echo -e " 1) Set / Change Bot Token"
        echo -e " 2) Add Allowed Admin Telegram ID"
        echo -e " 3) Remove Admin Telegram ID"
        echo -e " 4) View Allowed Telegram Admin IDs"
        echo -e " 5) Restart Bot Service"
        echo -e " 6) Stop Bot Service"
        echo -e " 7) Back to Main Menu"
        echo -e "${CYAN}====================================================${NC}"
        read -rp "Option [1-7]: " tg_opt

        case $tg_opt in
            1)
                read -rp "Enter Telegram Bot Token (from @BotFather): " token_input
                if [[ -n "$token_input" ]]; then
                    echo "$token_input" > "$BOT_CONF"
                    install_telegram_bot
                    echo -e "${GREEN}[SUCCESS] Bot token saved & service restarted!${NC}"
                else
                    echo -e "${RED}[ERROR] Token empty nahi ho sakta!${NC}"
                fi
                press_any_key
                ;;
            2)
                read -rp "Enter Telegram Numeric User ID to Allow: " admin_id
                if [[ -n "$admin_id" ]]; then
                    echo "$admin_id" >> "$ADMIN_IDS_FILE"
                    sed -i '/^$/d' "$ADMIN_IDS_FILE"
                    echo -e "${GREEN}[SUCCESS] ID ${admin_id} is now authorized to use Bot!${NC}"
                else
                    echo -e "${RED}[ERROR] ID cannot be empty!${NC}"
                fi
                press_any_key
                ;;
            3)
                read -rp "Enter Telegram ID to Remove: " admin_id
                if [[ -f "$ADMIN_IDS_FILE" ]]; then
                    sed -i "/^${admin_id}$/d" "$ADMIN_IDS_FILE"
                    echo -e "${GREEN}[SUCCESS] ID ${admin_id} removed!${NC}"
                fi
                press_any_key
                ;;
            4)
                clear
                echo -e "${CYAN}--- Allowed Telegram Admin IDs ---${NC}"
                if [[ -f "$ADMIN_IDS_FILE" ]]; then
                    cat "$ADMIN_IDS_FILE"
                else
                    echo "No IDs added yet."
                fi
                press_any_key
                ;;
            5)
                systemctl restart tgbot
                echo -e "${GREEN}[SUCCESS] Telegram Bot Restarted!${NC}"
                press_any_key
                ;;
            6)
                systemctl stop tgbot
                echo -e "${YELLOW}[INFO] Telegram Bot Stopped!${NC}"
                press_any_key
                ;;
            7) return ;;
            *) echo "Invalid option"; sleep 1 ;;
        esac
    done
}

install_python_tracker() {
    cat << 'PY_EOF' > /usr/local/bin/autokill.py
import os, sys, time, subprocess, re

USER_DIR = "/etc/raretriccks/users"

def get_auth_logs():
    raw = ""
    try:
        raw = subprocess.check_output(["journalctl", "-u", "dropbear", "--no-pager", "-n", "300"], stderr=subprocess.DEVNULL).decode("utf-8", errors="ignore")
    except Exception: pass
    if os.path.exists("/var/log/auth.log"):
        try:
            with open("/var/log/auth.log", "r", encoding="utf-8", errors="ignore") as f:
                raw += "\n" + f.read()
        except Exception: pass
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
                        if not m: m = re.search(r"for (\w+)", last_line)
                        if m:
                            uname = m.group(1)
                            if uname not in user_pids: user_pids[uname] = []
                            user_pids[uname].append(pid)
    except Exception: pass
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
        except Exception: pass
    return total_bytes

last_pid_bytes = {}

while True:
    try:
        raw_logs = get_auth_logs()
        user_pids_map = get_active_users_and_pids(raw_logs)

        if os.path.exists(USER_DIR):
            for fname in os.listdir(USER_DIR):
                if not fname.endswith(".conf"): continue
                uname = fname[:-5]
                conf_path = os.path.join(USER_DIR, fname)
                
                ip_limit, gb_limit, used_mb = 0, "Unlimited", 0.0
                with open(conf_path, "r") as f: lines = f.readlines()

                for line in lines:
                    if line.startswith("IP_LIMIT="):
                        try: ip_limit = int(line.strip().split("=")[1])
                        except Exception: pass
                    elif line.startswith("GB_LIMIT="): gb_limit = line.strip().split("=")[1]
                    elif line.startswith("USED_MB="):
                        try: used_mb = float(line.strip().split("=")[1])
                        except Exception: pass

                active_pids = user_pids_map.get(uname, [])

                for pid in active_pids:
                    current_b = get_pid_io_bytes(pid)
                    if pid in last_pid_bytes:
                        diff = current_b - last_pid_bytes[pid]
                        if diff > 0: used_mb += (diff / (1024.0 * 1024.0))
                    last_pid_bytes[pid] = current_b

                new_lines = []
                for line in lines:
                    if line.startswith("USED_MB="): new_lines.append(f"USED_MB={used_mb:.2f}\n")
                    else: new_lines.append(line)
                with open(conf_path, "w") as f: f.writelines(new_lines)

                if gb_limit != "Unlimited":
                    try:
                        max_mb = float(gb_limit) * 1024.0
                        if used_mb >= max_mb:
                            subprocess.call(["passwd", "-l", uname], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                            for pid in active_pids: subprocess.call(["kill", "-9", pid], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    except Exception: pass

                if ip_limit > 0 and len(active_pids) > ip_limit:
                    subprocess.call(["passwd", "-l", uname], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    for pid in active_pids: subprocess.call(["kill", "-9", pid], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception: pass
    time.sleep(3)
PY_EOF
    chmod +x /usr/local/bin/autokill.py

    cat << SVC_EOF > /etc/systemd/system/autokill.service
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

apply_nginx_config() {
    local MY_DOMAIN=$(get_domain)
    if [[ "$MY_DOMAIN" == "No Domain Set" || -z "$MY_DOMAIN" ]]; then return; fi

    cat << NGX_EOF > /etc/nginx/conf.d/vpn.conf
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name ${MY_DOMAIN} _;

    location / {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:2082;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }
}

server {
    listen 443 ssl http2 default_server;
    listen [::]:443 ssl http2 default_server;
    server_name ${MY_DOMAIN} _;

    ssl_certificate /etc/letsencrypt/live/${MY_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${MY_DOMAIN}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;

    location / {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:2082;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }
}
NGX_EOF
    rm -f /etc/nginx/sites-enabled/default
    systemctl restart nginx 2>/dev/null
}

add_domain_option() {
    clear
    echo -e "${CYAN}====================================================${NC}"
    echo -e "${YELLOW}        ADD / CHANGE DOMAIN NAME                    ${NC}"
    echo -e "${CYAN}====================================================${NC}"
    read -rp " Apna Domain Enter Karein (e.g. sub.yourdomain.com): " new_dom

    if [[ -z "$new_dom" ]]; then
        echo -e "${RED}[ERROR] Domain khaali nahi chhod sakte!${NC}"
    else
        echo "$new_dom" > "$DOMAIN_FILE"
        echo -e "\n${GREEN}[SUCCESS] Domain successfully set to: ${CYAN}${new_dom}${NC}"
        apply_nginx_config
    fi
    press_any_key
}

install_all_components() {
    clear
    echo -e "${CYAN}====================================================${NC}"
    echo -e "${YELLOW}   ${PANEL_NAME} - SYSTEM INSTALLATION           ${NC}"
    echo -e "${CYAN}====================================================${NC}"

    echo -e "${YELLOW}[STEP 1/7] Domain Input Setup${NC}"
    while true; do
        read -rp "Apna Domain Name Enter Karein (e.g. sub.yourdomain.com): " target_domain
        if [[ -n "$target_domain" ]]; then
            echo "$target_domain" > "$DOMAIN_FILE"
            break
        else
            echo -e "${RED}[ERROR] Domain khaali nahi chhod sakte! Dobara try karein.${NC}"
        fi
    done

    echo -e "\n${BLUE}[2/7] Updating Packages...${NC}"
    apt update -y && apt upgrade -y

    echo -e "\n${BLUE}[3/7] Installing Required Tools & Certbot...${NC}"
    apt install -y curl wget unzip tar net-tools socat jq openssl nginx dropbear certbot python3 python3-pip python3-requests lsof iptables cron

    echo -e "\n${BLUE}[4/7] Auto Issuing SSL Certificate for ${target_domain}...${NC}"
    systemctl stop nginx 2>/dev/null
    certbot certonly --standalone --preferred-challenges http --agree-tos --register-unsafely-without-email -d "$target_domain"

    if [[ -f "/etc/letsencrypt/live/$target_domain/fullchain.pem" ]]; then
        echo -e "${GREEN}[SUCCESS] SSL Certificate successfully issued!${NC}"
        
        # Setup Auto SSL Renewal via Cron
        (crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet --pre-hook 'systemctl stop nginx' --post-hook 'systemctl restart nginx'") | crontab -
        echo -e "${GREEN}[SUCCESS] Auto SSL Renewal Cronjob Configured!${NC}"
    else
        echo -e "${RED}[WARNING] SSL Issue fail hua! Make sure A-Record VPS IP par pointed hai. Aap ise bad me bhi retry kar sakte hain.${NC}"
    fi

    echo -e "\n${BLUE}[5/7] Configuring Dropbear SSH & Banner...${NC}"
    touch $BANNER_FILE
    sed -i 's/NO_START=1/NO_START=0/g' /etc/default/dropbear
    sed -i 's/DROPBEAR_PORT=22/DROPBEAR_PORT=109/g' /etc/default/dropbear
    sed -i 's/DROPBEAR_EXTRA_ARGS=/DROPBEAR_EXTRA_ARGS="-p 447 -b \/etc\/issue.net"/g' /etc/default/dropbear
    
    sed -i 's/#Banner none/Banner \/etc\/issue.net/g' /etc/ssh/sshd_config
    systemctl restart ssh
    systemctl restart dropbear

    echo -e "\n${BLUE}[6/7] Creating Multi-Payload Python WebSocket Service & Nginx Proxy...${NC}"
    cat << 'WS_EOF' > /usr/local/bin/ws-proxy.py
import socket, threading, select, time

PORT = 2082
TARGET_HOST = '127.0.0.1'
TARGET_PORT = 109
LOG_FILE = '/var/log/ws-proxy.log'

def log_client_ip(ip):
    try:
        with open(LOG_FILE, 'a') as f:
            f.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} - REAL_IP:{ip}\n")
    except Exception: pass

def handle_client(client_socket, client_addr):
    real_ip = client_addr[0]
    try:
        client_socket.settimeout(10)
        request = client_socket.recv(4096).decode('utf-8', errors='ignore')
        if not request: client_socket.close(); return

        for line in request.split('\r\n'):
            if line.lower().startswith('x-forwarded-for:') or line.lower().startswith('x-real-ip:'):
                real_ip = line.split(':')[1].strip().split(',')[0].strip()
                break

        log_client_ip(real_ip)
        response = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n"
        client_socket.sendall(response.encode('utf-8'))

        target_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        target_socket.connect((TARGET_HOST, TARGET_PORT))

        sockets = [client_socket, target_socket]
        client_socket.settimeout(None)

        while True:
            readable, _, _ = select.select(sockets, [], [])
            for s in readable:
                other = target_socket if s is client_socket else client_socket
                data = s.recv(8192)
                if not data: return
                other.sendall(data)
    except Exception: pass
    finally: client_socket.close()

server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.bind(('0.0.0.0', PORT))
server.listen(200)

while True:
    client, addr = server.accept()
    threading.Thread(target=handle_client, args=(client, addr), daemon=True).start()
WS_EOF

    cat << SVC_EOF > /etc/systemd/system/ws-proxy.service
[Unit]
Description=RareTriccks WebSocket Proxy Service
After=network.target

[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/ws-proxy.py
Restart=always

[Install]
WantedBy=multi-user.target
SVC_EOF

    systemctl daemon-reload
    systemctl enable ws-proxy
    systemctl restart ws-proxy
    apply_nginx_config

    echo -e "\n${BLUE}[7/7] Installing Bandwidth Engine & Telegram Bot...${NC}"
    install_python_tracker
    install_telegram_bot

    echo -e "\n${GREEN}[SUCCESS] All Components & Services Installed with Auto SSL!${NC}"
    press_any_key
}

setup_ssl() {
    clear
    local current_dom=$(get_domain)

    if [[ "$current_dom" == "No Domain Set" || -z "$current_dom" ]]; then
        echo -e "${RED}[ERROR] Pehle Option 2 se Domain Add karein!${NC}"
        press_any_key
        return
    fi

    echo -e "${CYAN}====================================================${NC}"
    echo -e "${YELLOW}  ${PANEL_NAME} - ISSUING SSL (${current_dom}) ${NC}"
    echo -e "${CYAN}====================================================${NC}"

    systemctl stop nginx
    certbot certonly --standalone --preferred-challenges http --agree-tos --register-unsafely-without-email -d "$current_dom"

    if [[ -f "/etc/letsencrypt/live/$current_dom/fullchain.pem" ]]; then
        echo -e "\n${GREEN}[SUCCESS] SSL Active for ${current_dom}!${NC}"
        apply_nginx_config
    else
        echo -e "${RED}[ERROR] SSL Fail ho gaya! Domain IP check karein.${NC}"
    fi
    press_any_key
}

check_connected_ips() {
    clear
    echo -e "${CYAN}====================================================================${NC}"
    echo -e "${YELLOW}${BOLD}                     CONNECTED IPS & ACTIVE USERS                   ${NC}"
    echo -e "${CYAN}====================================================================${NC}"
    
    local total_count=0
    local raw_logs=""
    if command -v journalctl &>/dev/null; then
        raw_logs=$(journalctl -u dropbear --no-pager -n 400 2>/dev/null)
    fi
    [[ -f "/var/log/auth.log" ]] && raw_logs+=$'\n'$(cat /var/log/auth.log 2>/dev/null)

    mapfile -t external_ips < <(ss -tnp 2>/dev/null | grep -E ":(80|443|2082)" | grep "ESTAB" | awk '{print $5}' | cut -d: -f1 | grep -vE "^127\.|^::1" | sort -u)
    mapfile -t ws_logged_ips < <(grep -oP "(?<=REAL_IP:)\S+" /var/log/ws-proxy.log 2>/dev/null | tail -n 20 | sort -u)

    local real_ip_pool=($(echo "${external_ips[@]} ${ws_logged_ips[@]}" | tr ' ' '\n' | sort -u))
    local ip_index=0

    for pid in $(ps aux | grep dropbear | grep -v grep | awk '{print $2}'); do
        local user_match=$(echo "$raw_logs" | grep "dropbear\[$pid\]" | grep -i "Password auth succeeded" | tail -n 1)
        
        if [[ -n "$user_match" ]]; then
            local username=$(echo "$user_match" | grep -oP "(?<=for ')\w+(?=')" || echo "$user_match" | awk '{for(i=1;i<=NF;i++) if($i=="for") print $(i+1)}')
            local logged_ip=$(echo "$user_match" | grep -oP "(?<=from )\S+(?=:)")
            local final_ip="$logged_ip"

            if [[ "$logged_ip" == "127.0.0.1" || -z "$logged_ip" ]]; then
                if [[ ${#real_ip_pool[@]} -gt 0 && $ip_index -lt ${#real_ip_pool[@]} ]]; then
                    final_ip="${real_ip_pool[$ip_index]} (WS Tunnel)"
                    ip_index=$((ip_index + 1))
                else
                    final_ip="WS-Proxy Client"
                fi
            fi
            
            if [[ -n "$username" ]]; then
                printf " User: %-18s | IP/Source: %-25s [ONLINE]\n" "$username" "$final_ip"
                total_count=$((total_count + 1))
            fi
        fi
    done

    echo -e "${CYAN}====================================================================${NC}"
    echo -e " Total Active Sessions: ${BOLD}${total_count}${NC}"
    echo -e "${CYAN}====================================================================${NC}"
    press_any_key
}

check_gb_usage() {
    clear
    echo -e "${CYAN}====================================================================${NC}"
    echo -e "${YELLOW}${BOLD}                USER BANDWIDTH / EXPIRY & LOCK STATUS               ${NC}"
    echo -e "${CYAN}====================================================================${NC}"
    printf " %-14s | %-7s | %-10s | %-12s | %-10s\n" "USERNAME" "IP LIMIT" "DATA USED" "DATA LIMIT" "STATUS"
    echo -e "${CYAN}--------------------------------------------------------------------${NC}"

    for conf in /etc/raretriccks/users/*.conf; do
        [[ -e "$conf" ]] || continue
        local uname=$(basename "$conf" .conf)
        local limit=$(grep "^GB_LIMIT=" "$conf" | cut -d= -f2)
        local ip_l=$(grep "^IP_LIMIT=" "$conf" | cut -d= -f2)
        local used_mb=$(grep "^USED_MB=" "$conf" | cut -d= -f2)
        
        [[ -z "$limit" ]] && limit="Unlimited"
        [[ -z "$ip_l" ]] && ip_l="1"
        [[ -z "$used_mb" ]] && used_mb="0"

        local used_gb=$(python3 -c "print(f'{$used_mb/1024:.2f}')")

        local status="${GREEN}Active${NC}"
        if id "$uname" &>/dev/null; then
            if passwd -S "$uname" 2>/dev/null | grep -q "L"; then
                status="${RED}LOCKED${NC}"
            fi
        else
            status="${RED}Deleted${NC}"
        fi

        printf " %-14s | %-8s | %-7s GB | %-9s GB | %b\n" "$uname" "$ip_l" "$used_gb" "$limit" "$status"
    done

    echo -e "${CYAN}====================================================================${NC}"
    press_any_key
}

user_menu() {
    local cur_dom=$(get_domain)
    while true; do
        clear
        echo -e "${CYAN}====================================================${NC}"
        echo -e "${YELLOW}       ${PANEL_NAME} - USER MANAGEMENT           ${NC}"
        echo -e "${CYAN}====================================================${NC}"
        echo -e " 1) Add New User"
        echo -e " 2) Delete User"
        echo -e " 3) Check Connected IPs & Active Online Users"
        echo -e " 4) Check User Status, Quota & Limits"
        echo -e " 5) Renew Account Expiry Days"
        echo -e " 6) Extend / Modify IP Limit (Auto Unlock)"
        echo -e " 7) Extend / Modify GB Data Quota (Auto Unlock)"
        echo -e " 8) Back to Main Menu"
        echo -e "${CYAN}====================================================${NC}"
        read -rp "Option [1-8]: " u_choice

        case $u_choice in
            1)
                read -rp "Username: " username
                read -rp "Password: " password
                read -rp "Days Expiry (e.g. 30): " days
                read -rp "Max IP Limit (e.g. 1 ya 2): " ip_limit
                read -rp "Quota / Data Limit in GB (e.g. 0.5 ya 50): " gb_limit

                exp_date=$(date -d "+$days days" +%Y-%m-%d)
                useradd -M -s /bin/false -e "$exp_date" "$username"
                echo "$username:$password" | chpasswd
                
                echo "IP_LIMIT=$ip_limit" > "/etc/raretriccks/users/${username}.conf"
                echo "GB_LIMIT=$gb_limit" >> "/etc/raretriccks/users/${username}.conf"
                echo "USED_MB=0.0" >> "/etc/raretriccks/users/${username}.conf"

                echo -e "\n${GREEN}[SUCCESS] Account Created Successfully!${NC}"
                press_any_key
                ;;
            2)
                read -rp "Username to delete: " username
                userdel -f "$username" 2>/dev/null
                rm -f "/etc/raretriccks/users/${username}.conf"
                echo -e "${GREEN}User ${username} deleted!${NC}"
                press_any_key
                ;;
            3) check_connected_ips ;;
            4) check_gb_usage ;;
            5)
                read -rp "Username to Renew: " username
                if id "$username" &>/dev/null; then
                    read -rp "Days to add: " r_days
                    new_exp=$(date -d "+$r_days days" +%Y-%m-%d)
                    usermod -e "$new_exp" "$username"
                    passwd -u "$username" 2>/dev/null
                    echo -e "${GREEN}[SUCCESS] User extended to: ${new_exp}${NC}"
                fi
                press_any_key
                ;;
            6)
                read -rp "Username: " username
                if [[ -f "/etc/raretriccks/users/${username}.conf" ]]; then
                    read -rp "New IP Limit: " new_ip_l
                    sed -i "s/IP_LIMIT=.*/IP_LIMIT=${new_ip_l}/g" "/etc/raretriccks/users/${username}.conf"
                    passwd -u "$username" 2>/dev/null
                    echo -e "${GREEN}[SUCCESS] Updated and Unlocked!${NC}"
                fi
                press_any_key
                ;;
            7)
                read -rp "Username: " username
                if [[ -f "/etc/raretriccks/users/${username}.conf" ]]; then
                    read -rp "New GB Limit: " new_gb
                    sed -i "s/GB_LIMIT=.*/GB_LIMIT=${new_gb}/g" "/etc/raretriccks/users/${username}.conf"
                    passwd -u "$username" 2>/dev/null
                    echo -e "${GREEN}[SUCCESS] Updated and Unlocked!${NC}"
                fi
                press_any_key
                ;;
            8) return ;;
            *) echo "Invalid Option"; sleep 1 ;;
        esac
    done
}

status_check() {
    clear
    local current_dom=$(get_domain)
    local nginx_status=$(systemctl is-active nginx 2>/dev/null)
    local dropbear_status=$(systemctl is-active dropbear 2>/dev/null)
    local ws_status=$(systemctl is-active ws-proxy 2>/dev/null)
    local ak_status=$(systemctl is-active autokill 2>/dev/null)
    local bot_status=$(systemctl is-active tgbot 2>/dev/null)

    echo -e "${CYAN}====================================================================${NC}"
    echo -e "${YELLOW}${BOLD}                     SYSTEM & PROTOCOL STATUS                       ${NC}"
    echo -e "${CYAN}====================================================================${NC}"
    printf "   %-28s : %s\n" "Nginx SSL Proxy" "$nginx_status"
    printf "   %-28s : %s\n" "Dropbear SSH Core" "$dropbear_status"
    printf "   %-28s : %s\n" "Python WebSocket" "$ws_status"
    printf "   %-28s : %s\n" "AutoKill Daemon" "$ak_status"
    printf "   %-28s : %s\n" "Telegram Bot Engine" "$bot_status"
    echo -e "${CYAN}====================================================================${NC}"
    press_any_key
}

set_banner() {
    clear
    echo -e "${CYAN}====================================================${NC}"
    echo -e "${YELLOW}       ${PANEL_NAME} - SET SSH / WS BANNER       ${NC}"
    echo -e "${CYAN}====================================================${NC}"
    echo -e "1) Write Custom Banner"
    echo -e "2) View Banner"
    echo -e "3) Clear Banner"
    echo -e "4) Back"
    read -rp "Option [1-4]: " b_opt

    case $b_opt in
        1)
            echo -e "${YELLOW}Banner text paste karke last line par END likhein:${NC}"
            > $BANNER_FILE
            while IFS= read -r line; do
                [[ $line == "END" ]] && break
                echo "$line" >> $BANNER_FILE
            done
            systemctl restart dropbear && systemctl restart ssh
            echo -e "${GREEN}Banner updated!${NC}"
            press_any_key
            ;;
        2) cat $BANNER_FILE; press_any_key ;;
        3) echo "" > $BANNER_FILE; systemctl restart dropbear; echo "Cleared!"; press_any_key ;;
        *) return ;;
    esac
}

fix_websocket() {
    clear
    systemctl restart dropbear
    systemctl restart ws-proxy
    systemctl restart tgbot
    install_python_tracker
    apply_nginx_config
    echo -e "\n${GREEN}[COMPLETED] All Engines Restarted & Active!${NC}"
    press_any_key
}

# ==============================================================================
# FULL SCRIPT UNINSTALLATION FUNCTION
# ==============================================================================
uninstall_script() {
    clear
    echo -e "${RED}====================================================${NC}"
    echo -e "${YELLOW}${BOLD}       UNINSTALL RARETRICCKS VPN PANEL              ${NC}"
    echo -e "${RED}====================================================${NC}"
    echo -e "${RED}[WARNING] Kya aap sach me poori script aur iske sabhi components uninstall karna chahte hain?${NC}"
    read -rp "Type 'y' ya 'YES' to confirm: " confirm_un

    if [[ "$confirm_un" == "y" || "$confirm_un" == "YES" || "$confirm_un" == "Y" ]]; then
        echo -e "\n${BLUE}[1/5] Stopping and removing systemd services...${NC}"
        systemctl stop tgbot ws-proxy autokill 2>/dev/null
        systemctl disable tgbot ws-proxy autokill 2>/dev/null
        rm -f /etc/systemd/system/tgbot.service
        rm -f /etc/systemd/system/ws-proxy.service
        rm -f /etc/systemd/system/autokill.service
        systemctl daemon-reload

        echo -e "${BLUE}[2/5] Cleaning Nginx configs...${NC}"
        rm -f /etc/nginx/conf.d/vpn.conf
        systemctl restart nginx 2>/dev/null

        echo -e "${BLUE}[3/5] Cleaning Cronjobs...${NC}"
        (crontab -l 2>/dev/null | grep -v "certbot renew") | crontab -

        echo -e "${BLUE}[4/5] Removing script files & directories...${NC}"
        rm -rf /etc/raretriccks
        rm -f /usr/local/bin/tgbot.py
        rm -f /usr/local/bin/ws-proxy.py
        rm -f /usr/local/bin/autokill.py
        rm -f /var/log/ws-proxy.log

        echo -e "${BLUE}[5/5] Removing main menu commands...${NC}"
        rm -f /usr/bin/menu
        rm -f /usr/local/bin/menu

        echo -e "\n${GREEN}[SUCCESS] RareTriccks VPN Panel aur sabhi components VPS se successfully uninstall ho gaye hain!${NC}"
        exit 0
    else
        echo -e "\n${GREEN}[CANCELLED] Uninstallation cancel kar di gayi hai.${NC}"
        press_any_key
    fi
}

if [[ "$1" == "apply_nginx" ]]; then
    apply_nginx_config
    exit 0
fi

while true; do
    clear
    CURRENT_DOM=$(get_domain)

    NGINX_ST=$(get_service_status "nginx")
    DROPBEAR_ST=$(get_service_status "dropbear")
    WS_ST=$(get_service_status "ws-proxy")
    AUTOKILL_ST=$(get_service_status "autokill")
    BOT_ST=$(get_service_status "tgbot")

    echo -e "${CYAN}====================================================${NC}"
    echo -e "${GREEN}              ${PANEL_NAME}                       ${NC}"
    echo -e "${CYAN}====================================================${NC}"
    echo -e " Domain Target: ${YELLOW}${CURRENT_DOM}${NC}"
    echo -e " Nginx: ${NGINX_ST} | Dropbear: ${DROPBEAR_ST} | WS Proxy: ${WS_ST}"
    echo -e " AutoKill: ${AUTOKILL_ST} | Telegram Bot: ${BOT_ST}"
    echo -e "${CYAN}----------------------------------------------------${NC}"
    echo -e " 1) Auto Install System Components"
    echo -e " 2) Add / Change Domain Name"
    echo -e " 3) Issue SSL Certificate"
    echo -e " 4) Manage Accounts (Add/Delete/Renew/Limits)"
    echo -e " 5) Check Status & Ports"
    echo -e " 6) Set / Edit SSH Banner"
    echo -e " 7) Fix SSH WS Engine"
    echo -e " 8) Telegram Bot Control Center (Set Token & Access)"
    echo -e " 9) ${RED}Uninstall Entire Script & Remove Components${NC}"
    echo -e " 10) Exit Panel"
    echo -e "${CYAN}====================================================${NC}"
    read -rp "Select Option [1-10]: " opt

    case $opt in
        1) install_all_components ;;
        2) add_domain_option ;;
        3) setup_ssl ;;
        4) user_menu ;;
        5) status_check ;;
        6) set_banner ;;
        7) fix_websocket ;;
        8) telegram_bot_menu ;;
        9) uninstall_script ;;
        10) exit 0 ;;
        *) echo "Invalid option"; sleep 1 ;;
    esac
done
