import os, sys, time, subprocess, re, json, requests

BOT_CONF = "/etc/raretriccks/bot.conf"
ADMIN_IDS_FILE = "/etc/raretriccks/admin_ids.conf"
USER_DIR = "/etc/raretriccks/users"
DOMAIN_FILE = "/etc/raretriccks/domain.conf"
STATE_DIR = "/etc/raretriccks/bot_states"

os.makedirs(STATE_DIR, exist_ok=True)

def get_token():
    if os.path.exists(BOT_CONF):
        with open(BOT_CONF, 'r') as f: return f.read().strip()
    return None

def get_admins():
    if os.path.exists(ADMIN_IDS_FILE):
        with open(ADMIN_IDS_FILE, 'r') as f: return [line.strip() for line in f if line.strip()]
    return []

def get_domain():
    if os.path.exists(DOMAIN_FILE):
        with open(DOMAIN_FILE, 'r') as f: return f.read().strip()
    return "No Domain Set"

TOKEN = get_token()
if not TOKEN: sys.exit(0)
API_URL = f"https://api.telegram.org/bot{TOKEN}/"

def send_api(method, payload):
    try: return requests.post(API_URL + method, json=payload, timeout=10).json()
    except Exception: return {}

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

def send_main_menu(chat_id):
    send_api("sendMessage", {
        "chat_id": chat_id,
        "text": "<b>🤖 RareTriccks VPN Control Panel</b>\nChoose an option below:",
        "parse_mode": "HTML",
        "reply_markup": build_main_keyboard()
    })

def edit_message(chat_id, message_id, text, keyboard=None):
    payload = {"chat_id": chat_id, "message_id": message_id, "text": text, "parse_mode": "HTML"}
    if keyboard: payload["reply_markup"] = keyboard
    send_api("editMessageText", payload)

def handle_callback(chat_id, message_id, data):
    set_user_state(chat_id, {})
    if data == "menu_main": edit_message(chat_id, message_id, "<b>🤖 RareTriccks VPN Control Panel</b>", build_main_keyboard())
    elif data == "menu_users": edit_message(chat_id, message_id, "<b>👤 Account Management Menu:</b>", build_users_keyboard())
    elif data == "menu_domain": edit_message(chat_id, message_id, f"<b>🌐 Domain & SSL Setup:</b>\nCurrent Domain: <code>{get_domain()}</code>", build_domain_keyboard())
    elif data == "menu_services": edit_message(chat_id, message_id, "<b>⚙️ System & Services Control:</b>", build_services_keyboard())
    elif data == "menu_admins": edit_message(chat_id, message_id, "<b>👮 Admin Management Center:</b>", build_admins_keyboard())
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
        edit_message(chat_id, message_id, "🌐 Enter your <b>Domain Name</b>:")
    elif data == "act_add_admin":
        set_user_state(chat_id, {"step": "admin_add"})
        edit_message(chat_id, message_id, "➕ Enter <b>Telegram Numeric User ID</b>:")
    elif data == "act_del_admin":
        set_user_state(chat_id, {"step": "admin_del"})
        edit_message(chat_id, message_id, "➖ Enter <b>Telegram Numeric User ID</b> to Remove:")
    elif data == "cmd_status":
        nginx = subprocess.call(["systemctl", "is-active", "--quiet", "nginx"]) == 0
        db = subprocess.call(["systemctl", "is-active", "--quiet", "dropbear"]) == 0
        ws = subprocess.call(["systemctl", "is-active", "--quiet", "ws-proxy"]) == 0
        ak = subprocess.call(["systemctl", "is-active", "--quiet", "autokill"]) == 0
        res = f"⚙️ <b>SERVICES STATUS:</b>\n\n🔹 Nginx: {'🟢 Active' if nginx else '🔴 Inactive'}\n🔹 Dropbear: {'🟢 Active' if db else '🔴 Inactive'}\n🔹 WebSocket: {'🟢 Active' if ws else '🔴 Inactive'}\n🔹 AutoKill: {'🟢 Active' if ak else '🔴 Inactive'}"
        edit_message(chat_id, message_id, res, build_services_keyboard())
    elif data == "act_list_admins":
        admins = get_admins()
        res = "📋 <b>ALLOWED ADMIN Telegram IDs:</b>\n\n" + "\n".join([f"• <code>{i}</code>" for i in admins]) if admins else "No admins configured."
        edit_message(chat_id, message_id, res, build_admins_keyboard())
    elif data == "cmd_fix":
        edit_message(chat_id, message_id, "🔄 Restarting all system engines...")
        for s in ["dropbear", "ws-proxy", "autokill", "nginx"]: subprocess.call(["systemctl", "restart", s])
        edit_message(chat_id, message_id, "✅ <b>All System Services Refreshed & Active!</b>", build_main_keyboard())

def handle_text(chat_id, text):
    state = get_user_state(chat_id)
    step = state.get("step")
    if not step:
        send_main_menu(chat_id)
        return
    if step == "add_username":
        set_user_state(chat_id, {"step": "add_password", "u": text})
        send_api("sendMessage", {"chat_id": chat_id, "text": "🔑 <b>Step 2/5:</b> Enter <b>Password</b>:", "parse_mode": "HTML"})
    elif step == "add_password":
        set_user_state(chat_id, {"step": "add_days", "u": state.get("u"), "p": text})
        send_api("sendMessage", {"chat_id": chat_id, "text": "📅 <b>Step 3/5:</b> Enter <b>Expiry Days</b> (e.g. 30):", "parse_mode": "HTML"})
    elif step == "add_days":
        set_user_state(chat_id, {"step": "add_ip", "u": state.get("u"), "p": state.get("p"), "d": text})
        send_api("sendMessage", {"chat_id": chat_id, "text": "📱 <b>Step 4/5:</b> Enter <b>Max IP Limit</b> (e.g. 1):", "parse_mode": "HTML"})
    elif step == "add_ip":
        set_user_state(chat_id, {"step": "add_gb", "u": state.get("u"), "p": state.get("p"), "d": state.get("d"), "ip": text})
        send_api("sendMessage", {"chat_id": chat_id, "text": "📊 <b>Step 5/5:</b> Enter <b>GB Limit</b> (e.g. 50):", "parse_mode": "HTML"})
    elif step == "add_gb":
        u, p, d, ip_l, gb_l = state.get("u"), state.get("p"), state.get("d"), state.get("ip"), text
        set_user_state(chat_id, {})
        try:
            exp_date = subprocess.check_output(["date", "-d", f"+{d} days", "+%Y-%m-%d"]).decode().strip()
            subprocess.call(["useradd", "-M", "-s", "/bin/false", "-e", exp_date, u])
            subprocess.run(f"echo '{u}:{p}' | chpasswd", shell=True)
            with open(f"{USER_DIR}/{u}.conf", "w") as f: f.write(f"IP_LIMIT={ip_l}\nGB_LIMIT={gb_l}\nUSED_MB=0.0\n")
            res = f"✅ <b>ACCOUNT CREATED</b>\n\n👤 User: <code>{u}</code>\n🔑 Pass: <code>{p}</code>\n📅 Expiry: {exp_date}\n📱 IP Limit: {ip_l}\n📊 GB Limit: {gb_l}"
            send_api("sendMessage", {"chat_id": chat_id, "text": res, "parse_mode": "HTML", "reply_markup": build_users_keyboard()})
        except Exception as e:
            send_api("sendMessage", {"chat_id": chat_id, "text": f"❌ Error: {str(e)}", "reply_markup": build_users_keyboard()})
    elif step == "del_username":
        set_user_state(chat_id, {})
        u = text.strip()
        subprocess.call(["userdel", "-f", u], stderr=subprocess.DEVNULL)
        if os.path.exists(f"{USER_DIR}/{u}.conf"): os.remove(f"{USER_DIR}/{u}.conf")
        send_api("sendMessage", {"chat_id": chat_id, "text": f"🗑️ User <b>{u}</b> deleted!", "parse_mode": "HTML", "reply_markup": build_users_keyboard()})

def main():
    offset = 0
    while True:
        try:
            admins = get_admins()
            res = send_api("getUpdates", {"offset": offset, "timeout": 10})
            if res.get("ok"):
                for update in res.get("result", []):
                    offset = update["update_id"] + 1
                    if "callback_query" in update:
                        cb = update["callback_query"]
                        chat_id, msg_id, data = str(cb["message"]["chat"]["id"]), cb["message"]["message_id"], cb["data"]
                        send_api("answerCallbackQuery", {"callback_query_id": cb["id"]})
                        if chat_id in admins: handle_callback(chat_id, msg_id, data)
                    elif "message" in update and "text" in update["message"]:
                        msg = update["message"]
                        chat_id, text = str(msg["chat"]["id"]), msg["text"]
                        if chat_id in admins:
                            if text == "/start":
                                set_user_state(chat_id, {})
                                send_main_menu(chat_id)
                            else: handle_text(chat_id, text)
        except Exception: pass
        time.sleep(2)

if __name__ == "__main__":
    main()
