#!/bin/bash
# ==============================================================================
# RareTriccks VPN Panel - Standalone menu.sh
# Modern Debian/Ubuntu Dropbear + self-installing menu command
#
# Ports:
#   OpenSSH       : 22
#   Dropbear      : 109, 447
#   WebSocket     : 80
#   WebSocket SSL : 443 (after SSL)
#   Internal WS   : 2082
# ==============================================================================

set -u

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
USERS_DIR="/etc/raretriccks/users"

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[ERROR] Root ke sath run karein.${NC}"
    exit 1
fi

# ------------------------------------------------------------------------------
# Install this exact script as the permanent `menu` command.
# This fixes: "menu: command not found" after installation.
# ------------------------------------------------------------------------------
install_menu_command() {
    local src="${BASH_SOURCE[0]}"
    local real_src
    real_src="$(readlink -f "$src" 2>/dev/null || printf '%s' "$src")"

    # Do not copy if we are already running from /usr/local/bin/menu.
    if [[ "$real_src" != "/usr/local/bin/menu" ]]; then
        cp -f "$real_src" /usr/local/bin/menu 2>/dev/null || true
        chmod 755 /usr/local/bin/menu 2>/dev/null || true
    fi

    # /usr/bin/menu is a normal symlink, so both PATH locations work.
    ln -sf /usr/local/bin/menu /usr/bin/menu 2>/dev/null || true
}

install_menu_command

mkdir -p /etc/raretriccks "$USERS_DIR"

get_domain() {
    if [[ -f "$DOMAIN_FILE" ]]; then
        local d
        d="$(tr -d '\r\n' < "$DOMAIN_FILE")"
        [[ -n "$d" ]] && printf '%s\n' "$d" || printf '%s\n' "No Domain Set"
    else
        printf '%s\n' "No Domain Set"
    fi
}

press_enter() {
    echo
    echo -e "${YELLOW}Press [ENTER] key to return to main menu...${NC}"
    read -r
}

service_status() {
    local svc="$1"
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        printf "${GREEN}[ ACTIVE ]${NC}"
    else
        printf "${RED}[ INACTIVE ]${NC}"
    fi
}

# ------------------------------------------------------------------------------
# Dropbear
# ------------------------------------------------------------------------------
configure_dropbear() {
    echo -e "${BLUE}Configuring Dropbear...${NC}"

    mkdir -p /etc/dropbear

    cat > "$BANNER_FILE" <<'EOF'
<font color="green">==========================================</font><br>
<font color="yellow"><b>WELCOME TO RARETRICCKS VIP VPN</b></font><br>
<font color="red"><b>- NO TORRENT / NO MULTILOGIN</b></font><br>
<font color="green">==========================================</font><br>
EOF

    touch /etc/default/dropbear

    # Remove only conflicting values written by this panel/old versions.
    sed -i \
        -e '/^[[:space:]]*DROPBEAR_PORT[[:space:]]*=/d' \
        -e '/^[[:space:]]*DROPBEAR_EXTRA_ARGS[[:space:]]*=/d' \
        -e '/^[[:space:]]*DROPBEAR_RECEIVE_WINDOW[[:space:]]*=/d' \
        -e '/^[[:space:]]*NO_START[[:space:]]*=/d' \
        /etc/default/dropbear

    cat >> /etc/default/dropbear <<'EOF'

# RareTriccks Dropbear configuration
DROPBEAR_PORT=109
DROPBEAR_EXTRA_ARGS="-p 447 -b /etc/issue.net"
DROPBEAR_RECEIVE_WINDOW=65536
EOF

    if command -v dropbearkey >/dev/null 2>&1; then
        [[ -s /etc/dropbear/dropbear_rsa_host_key ]] || \
            dropbearkey -t rsa -f /etc/dropbear/dropbear_rsa_host_key >/dev/null 2>&1 || true
        [[ -s /etc/dropbear/dropbear_ecdsa_host_key ]] || \
            dropbearkey -t ecdsa -f /etc/dropbear/dropbear_ecdsa_host_key >/dev/null 2>&1 || true
        [[ -s /etc/dropbear/dropbear_ed25519_host_key ]] || \
            dropbearkey -t ed25519 -f /etc/dropbear/dropbear_ed25519_host_key >/dev/null 2>&1 || true
    fi

    # Keep OpenSSH on port 22.
    if [[ -f /etc/ssh/sshd_config ]] && command -v sshd >/dev/null 2>&1; then
        if grep -Eq '^[[:space:]]*#?[[:space:]]*Banner[[:space:]]+' /etc/ssh/sshd_config; then
            sed -i -E \
                's|^[[:space:]]*#?[[:space:]]*Banner[[:space:]].*|Banner /etc/issue.net|' \
                /etc/ssh/sshd_config
        else
            printf '\nBanner /etc/issue.net\n' >> /etc/ssh/sshd_config
        fi

        if sshd -t 2>/dev/null; then
            systemctl restart ssh.service 2>/dev/null || \
            systemctl restart ssh 2>/dev/null || true
        fi
    fi

    systemctl stop dropbear.service 2>/dev/null || \
    systemctl stop dropbear 2>/dev/null || true

    systemctl daemon-reload
    systemctl enable dropbear.service >/dev/null 2>&1 || \
    systemctl enable dropbear >/dev/null 2>&1 || true

    if ! systemctl restart dropbear.service 2>/dev/null; then
        systemctl restart dropbear 2>/dev/null || true
    fi

    sleep 1

    if systemctl is-active --quiet dropbear.service 2>/dev/null || \
       systemctl is-active --quiet dropbear 2>/dev/null; then
        echo -e "${GREEN}[OK] Dropbear ACTIVE (109 + 447).${NC}"
        return 0
    fi

    echo -e "${RED}[ERROR] Dropbear start nahi hua.${NC}"
    journalctl -u dropbear.service -n 25 --no-pager 2>/dev/null || \
    journalctl -u dropbear -n 25 --no-pager 2>/dev/null || true
    return 1
}

# ------------------------------------------------------------------------------
# WebSocket proxy
# ------------------------------------------------------------------------------
install_ws_proxy() {
    echo -e "${BLUE}Installing WebSocket proxy...${NC}"

    cat > /usr/local/bin/ws-proxy.py <<'PYEOF'
#!/usr/bin/env python3
import socket
import threading
import select
import time

LISTEN_HOST = "0.0.0.0"
LISTEN_PORT = 2082
TARGET_HOST = "127.0.0.1"
TARGET_PORT = 109
LOG_FILE = "/var/log/ws-proxy.log"

def log_ip(ip):
    try:
        with open(LOG_FILE, "a") as f:
            f.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} - REAL_IP:{ip}\n")
    except Exception:
        pass

def relay(client, addr):
    target = None
    real_ip = addr[0]
    try:
        client.settimeout(10)
        request = client.recv(4096)
        if not request:
            return

        text = request.decode("utf-8", "ignore")
        for line in text.split("\r\n"):
            low = line.lower()
            if low.startswith("x-forwarded-for:") or low.startswith("x-real-ip:"):
                real_ip = line.split(":", 1)[1].strip().split(",", 1)[0].strip()
                break

        log_ip(real_ip)

        client.sendall(
            b"HTTP/1.1 101 Switching Protocols\r\n"
            b"Upgrade: websocket\r\n"
            b"Connection: Upgrade\r\n\r\n"
        )

        target = socket.create_connection((TARGET_HOST, TARGET_PORT), 10)
        client.settimeout(None)

        sockets = [client, target]
        while True:
            readable, _, _ = select.select(sockets, [], [])
            for sock in readable:
                other = target if sock is client else client
                data = sock.recv(8192)
                if not data:
                    return
                other.sendall(data)
    except Exception:
        pass
    finally:
        try:
            client.close()
        except Exception:
            pass
        if target:
            try:
                target.close()
            except Exception:
                pass

def main():
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((LISTEN_HOST, LISTEN_PORT))
    server.listen(200)

    while True:
        client, addr = server.accept()
        threading.Thread(target=relay, args=(client, addr), daemon=True).start()

if __name__ == "__main__":
    main()
PYEOF

    chmod 755 /usr/local/bin/ws-proxy.py

    cat > /etc/systemd/system/ws-proxy.service <<'EOF'
[Unit]
Description=RareTriccks WebSocket Proxy Service
After=network.target

[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/ws-proxy.py
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable ws-proxy >/dev/null 2>&1
    systemctl restart ws-proxy
}

# ------------------------------------------------------------------------------
# Auto-kill / bandwidth
# ------------------------------------------------------------------------------
install_autokill() {
    echo -e "${BLUE}Installing Auto-Kill & Bandwidth daemon...${NC}"

    cat > /usr/local/bin/autokill.py <<'PYEOF'
#!/usr/bin/env python3
import os
import time
import subprocess
import re

USER_DIR = "/etc/raretriccks/users"
last_pid_bytes = {}

def logs():
    out = ""
    try:
        out += subprocess.check_output(
            ["journalctl", "-u", "dropbear", "--no-pager", "-n", "500"],
            stderr=subprocess.DEVNULL
        ).decode(errors="ignore")
    except Exception:
        pass
    try:
        if os.path.exists("/var/log/auth.log"):
            with open("/var/log/auth.log", errors="ignore") as f:
                out += "\n" + f.read()
    except Exception:
        pass
    return out

def active_users(raw):
    result = {}
    try:
        ps = subprocess.check_output(
            ["ps", "-eo", "pid,args"], stderr=subprocess.DEVNULL
        ).decode(errors="ignore")
        for line in ps.splitlines():
            if "dropbear" not in line or "grep" in line:
                continue
            parts = line.strip().split(None, 1)
            if not parts:
                continue
            pid = parts[0]
            hits = [
                x for x in raw.splitlines()
                if f"dropbear[{pid}]" in x and
                ("Password auth succeeded" in x or
                 "Password auth successful" in x)
            ]
            if hits:
                m = re.search(r"for ['\"]?([A-Za-z0-9_-]+)", hits[-1])
                if m:
                    result.setdefault(m.group(1), []).append(pid)
    except Exception:
        pass
    return result

def io_bytes(pid):
    total = 0
    try:
        with open(f"/proc/{pid}/io") as f:
            for line in f:
                if line.startswith(("rchar:", "wchar:")):
                    total += int(line.split(":", 1)[1])
    except Exception:
        pass
    return total

while True:
    try:
        if os.path.isdir(USER_DIR):
            raw = logs()
            users = active_users(raw)

            for fname in os.listdir(USER_DIR):
                if not fname.endswith(".conf"):
                    continue

                uname = fname[:-5]
                path = os.path.join(USER_DIR, fname)

                try:
                    lines = open(path).readlines()
                except Exception:
                    continue

                data = {}
                for line in lines:
                    if "=" in line:
                        k, v = line.rstrip("\n").split("=", 1)
                        data[k] = v

                used = float(data.get("USED_MB", "0") or 0)

                for pid in users.get(uname, []):
                    now = io_bytes(pid)
                    if pid in last_pid_bytes:
                        diff = now - last_pid_bytes[pid]
                        if diff > 0:
                            used += diff / 1048576.0
                    last_pid_bytes[pid] = now

                new_lines = []
                found = False
                for line in lines:
                    if line.startswith("USED_MB="):
                        new_lines.append(f"USED_MB={used:.2f}\n")
                        found = True
                    else:
                        new_lines.append(line)

                if not found:
                    new_lines.append(f"USED_MB={used:.2f}\n")

                try:
                    with open(path, "w") as f:
                        f.writelines(new_lines)
                except Exception:
                    pass

                limit = data.get("GB_LIMIT", "Unlimited")
                try:
                    if limit.lower() != "unlimited" and used >= float(limit) * 1024:
                        subprocess.call(["passwd", "-l", uname],
                                        stdout=subprocess.DEVNULL,
                                        stderr=subprocess.DEVNULL)
                        for pid in users.get(uname, []):
                            subprocess.call(["kill", "-9", pid],
                                            stdout=subprocess.DEVNULL,
                                            stderr=subprocess.DEVNULL)
                except Exception:
                    pass

                try:
                    ip_limit = int(data.get("IP_LIMIT", "0") or 0)
                    if ip_limit > 0 and len(users.get(uname, [])) > ip_limit:
                        subprocess.call(["passwd", "-l", uname],
                                        stdout=subprocess.DEVNULL,
                                        stderr=subprocess.DEVNULL)
                        for pid in users.get(uname, []):
                            subprocess.call(["kill", "-9", pid],
                                            stdout=subprocess.DEVNULL,
                                            stderr=subprocess.DEVNULL)
                except Exception:
                    pass
    except Exception:
        pass

    time.sleep(3)
PYEOF

    chmod 755 /usr/local/bin/autokill.py

    cat > /etc/systemd/system/autokill.service <<'EOF'
[Unit]
Description=RareTriccks Auto-Kill & Bandwidth Tracking Service
After=network.target

[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/autokill.py
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable autokill >/dev/null 2>&1
    systemctl restart autokill
}

# ------------------------------------------------------------------------------
# Nginx / domain
# ------------------------------------------------------------------------------
apply_nginx_config() {
    local dom
    dom="$(get_domain)"

    [[ "$dom" == "No Domain Set" || -z "$dom" ]] && return 0

    mkdir -p /etc/nginx/conf.d

    cat > /etc/nginx/conf.d/vpn.conf <<EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name ${dom} _;

    location / {
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

    location ${CUSTOM_PATH} {
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
EOF

    rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true

    if nginx -t 2>/dev/null; then
        systemctl restart nginx
    else
        echo -e "${RED}[ERROR] Nginx configuration invalid.${NC}"
        nginx -t 2>&1 || true
        return 1
    fi
}

set_domain() {
    local new_dom
    read -rp "Apna Domain Enter Karein: " new_dom

    if [[ -z "$new_dom" ]]; then
        echo -e "${RED}[ERROR] Domain khaali nahi ho sakta.${NC}"
        return
    fi

    if [[ ! "$new_dom" =~ ^[A-Za-z0-9.-]+$ ]]; then
        echo -e "${RED}[ERROR] Invalid domain.${NC}"
        return
    fi

    printf '%s\n' "$new_dom" > "$DOMAIN_FILE"
    echo -e "${GREEN}[SUCCESS] Domain set: ${new_dom}${NC}"
    apply_nginx_config || true
}

setup_ssl() {
    clear
    local dom
    dom="$(get_domain)"

    if [[ "$dom" == "No Domain Set" ]]; then
        echo -e "${RED}[ERROR] Pehle domain set karein.${NC}"
        press_enter
        return
    fi

    echo -e "${YELLOW}SSL issue ho raha hai: ${dom}${NC}"
    echo -e "${YELLOW}DNS A record VPS IP par point hona chahiye.${NC}"

    systemctl stop nginx 2>/dev/null || true

    if certbot certonly --standalone --preferred-challenges http \
        --agree-tos --register-unsafely-without-email -d "$dom"; then
        if [[ -f "/etc/letsencrypt/live/$dom/fullchain.pem" ]]; then
            cat > /etc/nginx/conf.d/vpn.conf <<EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name ${dom} _;
    location / {
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
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name ${dom} _;

    ssl_certificate /etc/letsencrypt/live/${dom}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${dom}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;

    location / {
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

    location ${CUSTOM_PATH} {
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
EOF
            if nginx -t 2>/dev/null; then
                systemctl restart nginx
                echo -e "${GREEN}[SUCCESS] SSL Active for ${dom}.${NC}"
            else
                nginx -t 2>&1 || true
                systemctl restart nginx 2>/dev/null || true
            fi
        fi
    else
        echo -e "${RED}[ERROR] SSL issue nahi hua.${NC}"
        systemctl restart nginx 2>/dev/null || true
    fi

    press_enter
}

# ------------------------------------------------------------------------------
# Full component installation
# ------------------------------------------------------------------------------
install_all_components() {
    clear
    echo -e "${CYAN}====================================================${NC}"
    echo -e "${YELLOW}   ${PANEL_NAME} - SYSTEM INSTALLATION${NC}"
    echo -e "${CYAN}====================================================${NC}"

    echo -e "${BLUE}[1/5] Updating packages...${NC}"
    apt-get update -y

    echo -e "${BLUE}[2/5] Installing required packages...${NC}"
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        curl wget unzip tar net-tools socat jq openssl nginx dropbear \
        certbot python3 python3-pip python3-venv lsof iptables iproute2

    echo -e "${BLUE}[3/5] Configuring Dropbear...${NC}"
    if ! configure_dropbear; then
        echo -e "${RED}[ERROR] Dropbear configuration failed.${NC}"
        press_enter
        return
    fi

    echo -e "${BLUE}[4/5] Installing WebSocket + Auto-Kill...${NC}"
    install_ws_proxy
    install_autokill

    echo -e "${BLUE}[5/5] Applying Nginx configuration...${NC}"
    apply_nginx_config || true

    echo
    echo -e "${GREEN}====================================================${NC}"
    echo -e "${GREEN}[SUCCESS] Base components installed successfully!${NC}"
    echo -e "${GREEN}OpenSSH : 22${NC}"
    echo -e "${GREEN}Dropbear: 109 + 447${NC}"
    echo -e "${GREEN}WS Proxy: 2082 -> Dropbear 109${NC}"
    echo -e "${GREEN}HTTP WS : 80${NC}"
    echo -e "${GREEN}SSL WS  : 443 (after SSL setup)${NC}"
    echo -e "${GREEN}====================================================${NC}"
    press_enter
}

# ------------------------------------------------------------------------------
# User management
# ------------------------------------------------------------------------------
create_user() {
    clear
    local cur_dom username password days ip_limit gb_limit exp_date

    cur_dom="$(get_domain)"

    read -rp "Username: " username
    read -rp "Password: " password
    read -rp "Days Expiry: " days
    read -rp "Max IP Limit: " ip_limit
    read -rp "Quota / Data Limit GB (e.g. 5 ya Unlimited): " gb_limit

    if ! [[ "$username" =~ ^[a-zA-Z_][a-zA-Z0-9_-]{0,31}$ ]]; then
        echo -e "${RED}[ERROR] Invalid username.${NC}"
        press_enter
        return
    fi

    if ! [[ "$days" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}[ERROR] Invalid expiry days.${NC}"
        press_enter
        return
    fi

    if ! [[ "$ip_limit" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}[ERROR] Invalid IP limit.${NC}"
        press_enter
        return
    fi

    [[ -n "$gb_limit" ]] || gb_limit="Unlimited"

    if id "$username" >/dev/null 2>&1; then
        echo -e "${RED}[ERROR] User already exists.${NC}"
        press_enter
        return
    fi

    exp_date="$(date -d "+${days} days" +%Y-%m-%d)"

    if ! useradd -M -s /bin/bash -e "$exp_date" "$username"; then
        echo -e "${RED}[ERROR] User create nahi hua.${NC}"
        press_enter
        return
    fi

    echo "$username:$password" | chpasswd

    mkdir -p "$USERS_DIR"
    cat > "$USERS_DIR/${username}.conf" <<EOF
IP_LIMIT=${ip_limit}
GB_LIMIT=${gb_limit}
USED_MB=0.0
EOF

    echo -e "${GREEN}====================================================${NC}"
    echo -e "${YELLOW}ACCOUNT CREATED BY RARETRICCKS${NC}"
    echo -e "${GREEN}====================================================${NC}"
    echo -e "Domain       : ${CYAN}${cur_dom}${NC}"
    echo -e "Username     : ${CYAN}${username}${NC}"
    echo -e "Password     : ${CYAN}${password}${NC}"
    echo -e "Expired On   : ${CYAN}${exp_date}${NC}"
    echo -e "Max IP Limit : ${CYAN}${ip_limit}${NC}"
    echo -e "Data Limit   : ${CYAN}${gb_limit}${NC}"
    echo -e "SSH Direct   : ${CYAN}22, 109, 447${NC}"
    echo -e "SSH WS HTTP  : ${CYAN}80${NC}"
    echo -e "SSH WS SSL   : ${CYAN}443${NC}"
    echo
    echo -e "${CYAN}Payload: GET ${CUSTOM_PATH} HTTP/1.1[crlf]Host: ${cur_dom}[crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]${NC}"
    press_enter
}

delete_user() {
    clear
    read -rp "Username to delete: " username
    [[ -z "$username" ]] && return

    userdel -f "$username" 2>/dev/null || true
    rm -f "$USERS_DIR/${username}.conf"

    echo -e "${GREEN}User ${username} deleted.${NC}"
    press_enter
}

list_users() {
    clear
    echo -e "${CYAN}================ USER STATUS ================${NC}"

    local found=0 conf uname ip gb used status exp

    shopt -s nullglob
    for conf in "$USERS_DIR"/*.conf; do
        found=1
        uname="$(basename "$conf" .conf)"
        ip="$(grep '^IP_LIMIT=' "$conf" | cut -d= -f2)"
        gb="$(grep '^GB_LIMIT=' "$conf" | cut -d= -f2)"
        used="$(grep '^USED_MB=' "$conf" | cut -d= -f2)"
        [[ -z "$used" ]] && used=0

        if id "$uname" >/dev/null 2>&1; then
            status="Active"
            passwd -S "$uname" 2>/dev/null | grep -q ' L ' && status="LOCKED"
            exp="$(chage -l "$uname" 2>/dev/null |
                awk -F: '/Account expires/{gsub(/^ /,"",$2);print $2}')"
        else
            status="Deleted"
            exp="N/A"
        fi

        printf "%-16s | IP:%-3s | Used:%-8.2f MB | Limit:%-10s | %-8s | %s\n" \
            "$uname" "$ip" "$used" "$gb" "$status" "$exp"
    done
    shopt -u nullglob

    [[ $found -eq 0 ]] && echo -e "${YELLOW}Koi user nahi mila.${NC}"
    press_enter
}

renew_user() {
    clear
    read -rp "Username to renew: " username

    if id "$username" >/dev/null 2>&1; then
        read -rp "Additional days: " days

        if [[ "$days" =~ ^[0-9]+$ ]]; then
            local exp
            exp="$(date -d "+${days} days" +%Y-%m-%d)"
            usermod -e "$exp" "$username"
            passwd -u "$username" >/dev/null 2>&1 || true
            echo -e "${GREEN}New expiry: ${exp}${NC}"
        else
            echo -e "${RED}Invalid days.${NC}"
        fi
    else
        echo -e "${RED}User exist nahi karta.${NC}"
    fi

    press_enter
}

modify_limits() {
    clear
    read -rp "Username: " username

    local conf="$USERS_DIR/${username}.conf"
    [[ -f "$conf" ]] || {
        echo -e "${RED}User config nahi mili.${NC}"
        press_enter
        return
    }

    echo "1) IP Limit"
    echo "2) GB Limit"
    read -rp "Option: " x

    case "$x" in
        1)
            read -rp "New IP Limit: " v
            [[ "$v" =~ ^[0-9]+$ ]] || {
                echo -e "${RED}Invalid value.${NC}"
                press_enter
                return
            }
            sed -i "s/^IP_LIMIT=.*/IP_LIMIT=${v}/" "$conf"
            ;;
        2)
            read -rp "New GB Limit: " v
            [[ -n "$v" ]] || v="Unlimited"
            sed -i "s/^GB_LIMIT=.*/GB_LIMIT=${v}/" "$conf"
            ;;
        *)
            return
            ;;
    esac

    passwd -u "$username" >/dev/null 2>&1 || true
    echo -e "${GREEN}Limit updated and account unlocked.${NC}"
    press_enter
}

check_connected_ips() {
    clear
    echo -e "${CYAN}=========== CONNECTED IPS ===========${NC}"
    local count
    count="$(ss -tn 2>/dev/null |
        grep -E ':(22|109|447|80|443|2082)[[:space:]]' |
        grep -c ESTAB || true)"
    echo -e "Active matching connections: ${GREEN}${count}${NC}"
    press_enter
}

# ------------------------------------------------------------------------------
# Status screen -- intentionally NO ss/listen/port dump here.
# ------------------------------------------------------------------------------
status_check() {
    clear
    local dom
    dom="$(get_domain)"

    echo -e "${CYAN}====================================================${NC}"
    echo -e "${YELLOW}${BOLD}SYSTEM & PROTOCOL STATUS${NC}"
    echo -e "${CYAN}====================================================${NC}"
    echo -e "Target Domain : ${BOLD}${dom}${NC}"
    echo -e "Active Path   : ${BOLD}${CUSTOM_PATH}${NC}"
    echo
    printf " Nginx        : "
    service_status nginx
    echo
    printf " Dropbear     : "
    service_status dropbear
    echo
    printf " WS-Proxy     : "
    service_status ws-proxy
    echo
    printf " Auto-Kill    : "
    service_status autokill
    echo
    echo -e "${CYAN}====================================================${NC}"

    press_enter
}

# ------------------------------------------------------------------------------
# Banner
# ------------------------------------------------------------------------------
set_banner() {
    clear
    echo "1) Write custom banner"
    echo "2) View banner"
    echo "3) Reset banner"
    echo "4) Back"

    read -rp "Option: " b

    case "$b" in
        1)
            echo "Banner text paste karein. Last line par END likhein."
            : > "$BANNER_FILE"

            while IFS= read -r line; do
                [[ "$line" == "END" ]] && break
                echo "$line" >> "$BANNER_FILE"
            done

            systemctl restart dropbear 2>/dev/null || true
            systemctl restart ssh 2>/dev/null || true
            echo -e "${GREEN}Banner updated.${NC}"
            press_enter
            ;;
        2)
            clear
            cat "$BANNER_FILE" 2>/dev/null || true
            press_enter
            ;;
        3)
            : > "$BANNER_FILE"
            systemctl restart dropbear 2>/dev/null || true
            systemctl restart ssh 2>/dev/null || true
            echo -e "${GREEN}Banner cleared.${NC}"
            press_enter
            ;;
        4) ;;
    esac
}

fix_websocket() {
    clear
    echo -e "${YELLOW}Fixing SSH WS & WS+SSL engine...${NC}"

    configure_dropbear || true
    systemctl daemon-reload
    systemctl restart ws-proxy 2>/dev/null || true
    systemctl restart autokill 2>/dev/null || true
    apply_nginx_config || true

    echo -e "${GREEN}[COMPLETED] WebSocket system restarted.${NC}"
    press_enter
}

# ------------------------------------------------------------------------------
# Telegram bot (simple admin bot)
# ------------------------------------------------------------------------------
setup_telegram_bot() {
    clear
    echo -e "${YELLOW}Telegram Bot setup${NC}"
    echo "1) Install / Configure Bot"
    echo "2) Restart Bot"
    echo "3) Stop Bot"
    echo "4) Status"
    echo "5) Back"

    read -rp "Option: " tb

    case "$tb" in
        1)
            read -rp "Telegram Bot Token: " token
            read -rp "Super Admin Telegram ID: " admin

            if [[ -z "$token" || ! "$admin" =~ ^[0-9]+$ ]]; then
                echo -e "${RED}Invalid token/ID.${NC}"
                press_enter
                return
            fi

            DEBIAN_FRONTEND=noninteractive apt-get install -y \
                python3-venv python3-pip >/dev/null 2>&1

            rm -rf /opt/rr-tgbot-venv
            python3 -m venv /opt/rr-tgbot-venv
            /opt/rr-tgbot-venv/bin/pip install --upgrade pip >/dev/null 2>&1
            /opt/rr-tgbot-venv/bin/pip install "python-telegram-bot==20.7" >/dev/null 2>&1

            mkdir -p /etc/raretriccks/tgbot

            python3 - "$token" "$admin" <<'PYEOF'
import json, sys
token = sys.argv[1]
admin = int(sys.argv[2])
with open("/etc/raretriccks/tgbot/config.json", "w") as f:
    json.dump({"token": token, "super_admin": admin}, f)
PYEOF

            cat > /usr/local/bin/tgbot.py <<'PYEOF'
import json
from telegram import Update
from telegram.ext import Application, CommandHandler, ContextTypes

CFG = "/etc/raretriccks/tgbot/config.json"

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    with open(CFG) as f:
        c = json.load(f)
    if update.effective_user.id != c["super_admin"]:
        return
    await update.message.reply_text("RareTriccks VPN Panel Bot is online.")

def main():
    with open(CFG) as f:
        c = json.load(f)
    app = Application.builder().token(c["token"]).build()
    app.add_handler(CommandHandler("start", start))
    app.run_polling()

if __name__ == "__main__":
    main()
PYEOF

            chmod 755 /usr/local/bin/tgbot.py

            cat > /etc/systemd/system/tgbot.service <<'EOF'
[Unit]
Description=RareTriccks Telegram Bot
After=network.target

[Service]
ExecStart=/opt/rr-tgbot-venv/bin/python3 /usr/local/bin/tgbot.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

            systemctl daemon-reload
            systemctl enable tgbot >/dev/null 2>&1
            systemctl restart tgbot

            echo -e "${GREEN}Telegram Bot Active.${NC}"
            press_enter
            ;;
        2)
            systemctl restart tgbot 2>/dev/null || true
            echo "Bot restarted."
            press_enter
            ;;
        3)
            systemctl stop tgbot 2>/dev/null || true
            echo "Bot stopped."
            press_enter
            ;;
        4)
            systemctl status tgbot --no-pager
            press_enter
            ;;
        5) ;;
    esac
}

uninstall_panel() {
    clear
    echo -e "${RED}${BOLD}WARNING: Panel components/users remove honge.${NC}"
    read -rp "Confirm ke liye YES likhein: " confirm

    [[ "$confirm" == "YES" ]] || {
        echo "Cancelled."
        press_enter
        return
    }

    systemctl stop ws-proxy autokill tgbot 2>/dev/null || true
    systemctl disable ws-proxy autokill tgbot 2>/dev/null || true

    rm -f \
        /etc/systemd/system/ws-proxy.service \
        /etc/systemd/system/autokill.service \
        /etc/systemd/system/tgbot.service

    rm -f \
        /usr/local/bin/ws-proxy.py \
        /usr/local/bin/autokill.py \
        /usr/local/bin/tgbot.py

    rm -rf /opt/rr-tgbot-venv
    rm -f /etc/nginx/conf.d/vpn.conf

    if [[ -d "$USERS_DIR" ]]; then
        shopt -s nullglob
        local conf
        for conf in "$USERS_DIR"/*.conf; do
            userdel -f "$(basename "$conf" .conf)" 2>/dev/null || true
        done
        shopt -u nullglob
    fi

    rm -rf /etc/raretriccks
    systemctl daemon-reload
    systemctl restart nginx 2>/dev/null || true

    rm -f /usr/local/bin/menu /usr/bin/menu

    echo -e "${GREEN}Uninstall complete.${NC}"
    exit 0
}

# ------------------------------------------------------------------------------
# Main menu
# ------------------------------------------------------------------------------
while true; do
    clear
    CURRENT_DOM="$(get_domain)"

    echo -e "${CYAN}====================================================${NC}"
    echo -e "${GREEN}              ${PANEL_NAME}${NC}"
    echo -e "${CYAN}====================================================${NC}"
    echo -e " Domain Target: ${YELLOW}${CURRENT_DOM}${NC}"
    echo -e " Custom Path  : ${YELLOW}${CUSTOM_PATH}${NC}"
    echo -e "${CYAN}----------------------------------------------------${NC}"
    echo " 1) Auto Install System Components"
    echo " 2) Add / Change Domain Name"
    echo " 3) Issue SSL Certificate"
    echo " 4) Manage Accounts"
    echo " 5) Check Status"
    echo " 6) Set / Edit SSH Banner"
    echo " 7) Fix SSH WS & WS+SSL Connection"
    echo " 8) Setup / Manage Telegram Bot"
    echo " 9) Uninstall Panel"
    echo " 10) Exit Panel"
    echo -e "${CYAN}====================================================${NC}"

    read -rp "Select Option [1-10]: " opt

    case "$opt" in
        1)
            install_all_components
            ;;
        2)
            clear
            set_domain
            press_enter
            ;;
        3)
            setup_ssl
            ;;
        4)
            while true; do
                clear
                echo "1) Add New User"
                echo "2) Delete User"
                echo "3) Check Connected IPs"
                echo "4) Check User Status / Quota"
                echo "5) Renew Account"
                echo "6) Modify IP/GB Limit"
                echo "7) Back"
                read -rp "Option [1-7]: " u

                case "$u" in
                    1) create_user ;;
                    2) delete_user ;;
                    3) check_connected_ips ;;
                    4) list_users ;;
                    5) renew_user ;;
                    6) modify_limits ;;
                    7) break ;;
                    *) echo "Invalid option"; sleep 1 ;;
                esac
            done
            ;;
        5)
            status_check
            ;;
        6)
            set_banner
            ;;
        7)
            fix_websocket
            ;;
        8)
            setup_telegram_bot
            ;;
        9)
            uninstall_panel
            ;;
        10)
            exit 0
            ;;
        *)
            echo "Invalid option"
            sleep 1
            ;;
    esac
done
