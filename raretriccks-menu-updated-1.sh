#!/bin/bash
# ==============================================================================
# RareTriccks VPN Panel - Updated menu.sh
# Dropbear compatibility fix for modern Debian/Ubuntu
# Ports:
#   SSH Direct: 22 (OpenSSH), 109 + 447 (Dropbear)
#   SSH WebSocket: 80
#   SSH WebSocket SSL: 443
#   Internal WS Proxy: 2082
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
USERS_DIR="/etc/raretriccks/users"

[[ $EUID -eq 0 ]] || { echo -e "${RED}[ERROR] Root ke sath run karein.${NC}"; exit 1; }

get_domain() {
    if [[ -f "$DOMAIN_FILE" ]]; then
        tr -d '\r\n' < "$DOMAIN_FILE"
    else
        echo "No Domain Set"
    fi
}

press_any_key() {
    echo -e "\n${YELLOW}Press [ENTER] key to return to main menu...${NC}"
    read -r
}

install_python_tracker() {
    cat > /usr/local/bin/autokill.py <<'PY_EOF'
#!/usr/bin/env python3
import os, time, subprocess, re

USER_DIR="/etc/raretriccks/users"
last_pid_bytes={}

def logs():
    out=""
    try:
        out=subprocess.check_output(
            ["journalctl","-u","dropbear","--no-pager","-n","500"],
            stderr=subprocess.DEVNULL
        ).decode(errors="ignore")
    except Exception:
        pass
    try:
        if os.path.exists("/var/log/auth.log"):
            out += "\n" + open("/var/log/auth.log",errors="ignore").read()
    except Exception:
        pass
    return out

def active_users(raw):
    result={}
    try:
        ps=subprocess.check_output(["ps","-eo","pid,args"],stderr=subprocess.DEVNULL).decode(errors="ignore")
        for line in ps.splitlines():
            if "dropbear" not in line or "grep" in line:
                continue
            pid=line.strip().split(None,1)[0]
            hits=[x for x in raw.splitlines()
                  if f"dropbear[{pid}]" in x and
                  ("Password auth succeeded" in x or "Password auth successful" in x)]
            if not hits:
                continue
            m=re.search(r"for ['\"]?([A-Za-z0-9_-]+)",hits[-1])
            if m:
                result.setdefault(m.group(1),[]).append(pid)
    except Exception:
        pass
    return result

def io_bytes(pid):
    total=0
    try:
        with open(f"/proc/{pid}/io") as f:
            for line in f:
                if line.startswith(("rchar:","wchar:")):
                    total += int(line.split(":",1)[1])
    except Exception:
        pass
    return total

while True:
    try:
        if os.path.isdir(USER_DIR):
            raw=logs()
            users=active_users(raw)
            for fname in os.listdir(USER_DIR):
                if not fname.endswith(".conf"):
                    continue
                uname=fname[:-5]
                p=os.path.join(USER_DIR,fname)
                try:
                    lines=open(p).readlines()
                except Exception:
                    continue
                data={}
                for line in lines:
                    if "=" in line:
                        k,v=line.rstrip("\n").split("=",1)
                        data[k]=v
                used=float(data.get("USED_MB","0") or 0)
                for pid in users.get(uname,[]):
                    now=io_bytes(pid)
                    if pid in last_pid_bytes:
                        diff=now-last_pid_bytes[pid]
                        if diff>0:
                            used += diff/1048576.0
                    last_pid_bytes[pid]=now
                new=[]
                found=False
                for line in lines:
                    if line.startswith("USED_MB="):
                        new.append(f"USED_MB={used:.2f}\n")
                        found=True
                    else:
                        new.append(line)
                if not found:
                    new.append(f"USED_MB={used:.2f}\n")
                try:
                    open(p,"w").writelines(new)
                except Exception:
                    pass

                limit=data.get("GB_LIMIT","Unlimited")
                try:
                    if limit.lower()!="unlimited" and used >= float(limit)*1024:
                        subprocess.call(["passwd","-l",uname],
                                        stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
                        for pid in users.get(uname,[]):
                            subprocess.call(["kill","-9",pid],
                                            stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
                except Exception:
                    pass

                try:
                    ip_limit=int(data.get("IP_LIMIT","0") or 0)
                    if ip_limit>0 and len(users.get(uname,[]))>ip_limit:
                        subprocess.call(["passwd","-l",uname],
                                        stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
                        for pid in users.get(uname,[]):
                            subprocess.call(["kill","-9",pid],
                                            stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
                except Exception:
                    pass
    except Exception:
        pass
    time.sleep(3)
PY_EOF
    chmod +x /usr/local/bin/autokill.py

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

configure_dropbear() {
    echo -e "${BLUE}[3/6] Configuring Dropbear SSH & Banner...${NC}"

    mkdir -p /etc/dropbear /etc/raretriccks
    cat > "$BANNER_FILE" <<'EOF'
<font color="green">==========================================</font><br>
<font color="yellow"><b>WELCOME TO RARETRICCKS VIP VPN</b></font><br>
<font color="red"><b>- NO TORRENT / NO MULTILOGIN</b></font><br>
<font color="green">==========================================</font><br>
EOF

    # IMPORTANT:
    # Modern Debian/Ubuntu Dropbear packages may ignore the old NO_START
    # configuration. Rewrite /etc/default/dropbear instead of using fragile
    # sed substitutions.
    if [[ -f /etc/default/dropbear ]]; then
        sed -i \
            -e '/^[[:space:]]*NO_START[[:space:]]*=/d' \
            -e '/^[[:space:]]*DROPBEAR_PORT[[:space:]]*=/d' \
            -e '/^[[:space:]]*DROPBEAR_EXTRA_ARGS[[:space:]]*=/d' \
            -e '/^[[:space:]]*DROPBEAR_RECEIVE_WINDOW[[:space:]]*=/d' \
            /etc/default/dropbear
    else
        touch /etc/default/dropbear
    fi

    cat >> /etc/default/dropbear <<'EOF'

# RareTriccks Dropbear configuration
DROPBEAR_PORT=109
DROPBEAR_EXTRA_ARGS="-p 447 -b /etc/issue.net"
DROPBEAR_RECEIVE_WINDOW=65536
EOF

    # Generate missing host keys if necessary.
    if command -v dropbearkey >/dev/null 2>&1; then
        [[ -s /etc/dropbear/dropbear_rsa_host_key ]] || \
            dropbearkey -t rsa -f /etc/dropbear/dropbear_rsa_host_key >/dev/null 2>&1 || true
        [[ -s /etc/dropbear/dropbear_ecdsa_host_key ]] || \
            dropbearkey -t ecdsa -f /etc/dropbear/dropbear_ecdsa_host_key >/dev/null 2>&1 || true
        [[ -s /etc/dropbear/dropbear_ed25519_host_key ]] || \
            dropbearkey -t ed25519 -f /etc/dropbear/dropbear_ed25519_host_key >/dev/null 2>&1 || true
    fi

    # Keep OpenSSH on port 22 and use the same banner.
    if [[ -f /etc/ssh/sshd_config ]]; then
        if grep -Eq '^[[:space:]]*#?[[:space:]]*Banner[[:space:]]+' /etc/ssh/sshd_config; then
            sed -i -E 's|^[[:space:]]*#?[[:space:]]*Banner[[:space:]].*|Banner /etc/issue.net|' /etc/ssh/sshd_config
        else
            printf '\nBanner /etc/issue.net\n' >> /etc/ssh/sshd_config
        fi
        if command -v sshd >/dev/null 2>&1 && sshd -t 2>/dev/null; then
            systemctl restart ssh 2>/dev/null || systemctl restart ssh.service 2>/dev/null || true
        fi
    fi

    systemctl stop dropbear 2>/dev/null || true
    systemctl daemon-reload
    systemctl enable dropbear >/dev/null 2>&1 || true
    systemctl restart dropbear

    sleep 1
    if ! systemctl is-active --quiet dropbear; then
        echo -e "${RED}[ERROR] Dropbear start nahi hua.${NC}"
        journalctl -u dropbear -n 40 --no-pager 2>/dev/null || true
        return 1
    fi

    if ! ss -lnt 2>/dev/null | grep -Eq ':(109|447)[[:space:]]'; then
        echo -e "${RED}[ERROR] Dropbear ACTIVE hai lekin 109/447 listen nahi kar rahe.${NC}"
        ss -lntp 2>/dev/null | grep -E ':(22|109|447)[[:space:]]' || true
        return 1
    fi

    echo -e "${GREEN}[SUCCESS] Dropbear ACTIVE: ports 109 + 447${NC}"
}

install_ws_proxy() {
    echo -e "${BLUE}[4/6] Creating Python WebSocket Service...${NC}"

    cat > /usr/local/bin/ws-proxy.py <<'PY_EOF'
#!/usr/bin/env python3
import socket, threading, select, time

PORT=2082
TARGET_HOST="127.0.0.1"
TARGET_PORT=109
LOG_FILE="/var/log/ws-proxy.log"

def log_ip(ip):
    try:
        with open(LOG_FILE,"a") as f:
            f.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} - REAL_IP:{ip}\n")
    except Exception:
        pass

def relay(client, addr):
    real_ip=addr[0]
    try:
        client.settimeout(10)
        request=client.recv(4096)
        if not request:
            return
        text=request.decode("utf-8","ignore")
        for line in text.split("\r\n"):
            low=line.lower()
            if low.startswith("x-forwarded-for:") or low.startswith("x-real-ip:"):
                real_ip=line.split(":",1)[1].strip().split(",")[0].strip()
                break
        log_ip(real_ip)

        client.sendall(
            b"HTTP/1.1 101 Switching Protocols\r\n"
            b"Upgrade: websocket\r\n"
            b"Connection: Upgrade\r\n\r\n"
        )
        target=socket.create_connection((TARGET_HOST,TARGET_PORT),10)
        sockets=[client,target]
        client.settimeout(None)
        while True:
            readable,_,_=select.select(sockets,[],[])
            for s in readable:
                other=target if s is client else client
                data=s.recv(8192)
                if not data:
                    return
                other.sendall(data)
    except Exception:
        pass
    finally:
        try: client.close()
        except Exception: pass
        try: target.close()
        except Exception: pass

server=socket.socket(socket.AF_INET,socket.SOCK_STREAM)
server.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
server.bind(("0.0.0.0",PORT))
server.listen(200)

while True:
    client,addr=server.accept()
    threading.Thread(target=relay,args=(client,addr),daemon=True).start()
PY_EOF
    chmod +x /usr/local/bin/ws-proxy.py

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
    nginx -t && systemctl restart nginx
}

install_all_components() {
    clear
    echo -e "${CYAN}====================================================${NC}"
    echo -e "${YELLOW}   ${PANEL_NAME} - SYSTEM INSTALLATION${NC}"
    echo -e "${CYAN}====================================================${NC}"

    echo -e "${BLUE}[1/6] Updating Packages...${NC}"
    apt update -y

    echo -e "${BLUE}[2/6] Installing Required Tools...${NC}"
    DEBIAN_FRONTEND=noninteractive apt install -y \
        curl wget unzip tar net-tools socat jq openssl nginx dropbear \
        certbot python3 python3-pip python3-venv lsof iptables

    configure_dropbear || {
        echo -e "${RED}[ERROR] Dropbear configuration failed.${NC}"
        press_any_key
        return
    }

    install_ws_proxy

    echo -e "${BLUE}[5/6] Installing Bandwidth & Auto-Lock Engine...${NC}"
    install_python_tracker

    echo -e "${BLUE}[6/6] Applying Nginx configuration...${NC}"
    apply_nginx_config || true

    echo -e "\n${GREEN}====================================================${NC}"
    echo -e "${GREEN}[SUCCESS] Base components installed successfully!${NC}"
    echo -e "${GREEN}OpenSSH : 22${NC}"
    echo -e "${GREEN}Dropbear: 109 + 447${NC}"
    echo -e "${GREEN}WS Proxy: 2082 -> Dropbear 109${NC}"
    echo -e "${GREEN}HTTP WS : 80${NC}"
    echo -e "${GREEN}SSL WS  : 443 (after SSL setup)${NC}"
    echo -e "${GREEN}====================================================${NC}"
    press_any_key
}

add_domain_option() {
    clear
    echo -e "${CYAN}====================================================${NC}"
    echo -e "${YELLOW} ADD / CHANGE DOMAIN NAME${NC}"
    echo -e "${CYAN}====================================================${NC}"
    read -rp "Apna Domain Enter Karein: " new_dom
    if [[ -z "$new_dom" ]]; then
        echo -e "${RED}[ERROR] Domain khaali nahi chhod sakte!${NC}"
    else
        mkdir -p /etc/raretriccks
        printf '%s\n' "$new_dom" > "$DOMAIN_FILE"
        echo -e "${GREEN}[SUCCESS] Domain set: ${new_dom}${NC}"
        apply_nginx_config || true
    fi
    press_any_key
}

setup_ssl() {
    clear
    local dom
    dom="$(get_domain)"
    if [[ "$dom" == "No Domain Set" || -z "$dom" ]]; then
        echo -e "${RED}[ERROR] Pehle Domain set karein.${NC}"
        press_any_key
        return
    fi

    echo -e "${YELLOW}SSL issue ho raha hai: ${dom}${NC}"
    systemctl stop nginx 2>/dev/null || true
    certbot certonly --standalone --preferred-challenges http \
        --agree-tos --register-unsafely-without-email -d "$dom"

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
        rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
        nginx -t && systemctl restart nginx
        echo -e "${GREEN}[SUCCESS] SSL Active for ${dom}${NC}"
    else
        echo -e "${RED}[ERROR] SSL issue nahi hua. DNS A record check karein.${NC}"
        systemctl restart nginx 2>/dev/null || true
    fi
    press_any_key
}

create_user() {
    local cur_dom
    cur_dom="$(get_domain)"
    read -rp "Username: " username
    read -rp "Password: " password
    read -rp "Days Expiry: " days
    read -rp "Max IP Limit: " ip_limit
    read -rp "Quota / Data Limit GB (e.g. 5 ya Unlimited): " gb_limit

    if ! [[ "$username" =~ ^[a-zA-Z_][a-zA-Z0-9_-]{0,31}$ ]]; then
        echo -e "${RED}[ERROR] Invalid username.${NC}"
        return
    fi
    if ! [[ "$days" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}[ERROR] Invalid expiry days.${NC}"
        return
    fi

    local exp_date
    exp_date="$(date -d "+${days} days" +%Y-%m-%d)"
    if ! useradd -M -s /bin/bash -e "$exp_date" "$username"; then
        echo -e "${RED}[ERROR] User create nahi hua. Shayad already exists.${NC}"
        return
    fi

    echo "$username:$password" | chpasswd
    mkdir -p "$USERS_DIR"
    {
        echo "IP_LIMIT=${ip_limit:-1}"
        echo "GB_LIMIT=${gb_limit:-Unlimited}"
        echo "USED_MB=0.0"
    } > "$USERS_DIR/${username}.conf"

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
    echo -e "${CYAN}Payload: GET ${CUSTOM_PATH} HTTP/1.1[crlf]Host: ${cur_dom}[crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]${NC}"
}

list_users() {
    clear
    echo -e "${CYAN}================ USER STATUS ================${NC}"
    mkdir -p "$USERS_DIR"
    shopt -s nullglob
    local found=0
    for conf in "$USERS_DIR"/*.conf; do
        found=1
        local uname
        uname="$(basename "$conf" .conf)"
        local ip gb used status exp
        ip="$(grep '^IP_LIMIT=' "$conf" | cut -d= -f2)"
        gb="$(grep '^GB_LIMIT=' "$conf" | cut -d= -f2)"
        used="$(grep '^USED_MB=' "$conf" | cut -d= -f2)"
        [[ -z "$used" ]] && used=0
        if id "$uname" >/dev/null 2>&1; then
            status="Active"
            passwd -S "$uname" 2>/dev/null | grep -q ' L ' && status="LOCKED"
            exp="$(chage -l "$uname" 2>/dev/null | awk -F: '/Account expires/{gsub(/^ /,"",$2);print $2}')"
        else
            status="Deleted"
            exp="N/A"
        fi
        printf "%-16s | IP:%-3s | Used:%-8.2f MB | Limit:%-10s | %-8s | %s\n" \
            "$uname" "$ip" "$used" "$gb" "$status" "$exp"
    done
    shopt -u nullglob
    [[ $found -eq 0 ]] && echo -e "${YELLOW}Koi user nahi mila.${NC}"
    press_any_key
}

delete_user() {
    read -rp "Username to delete: " username
    [[ -z "$username" ]] && return
    userdel -f "$username" 2>/dev/null || true
    rm -f "$USERS_DIR/${username}.conf"
    echo -e "${GREEN}User ${username} deleted.${NC}"
}

renew_user() {
    read -rp "Username to renew: " username
    if id "$username" >/dev/null 2>&1; then
        read -rp "Additional days: " days
        if [[ "$days" =~ ^[0-9]+$ ]]; then
            local exp
            exp="$(date -d "+${days} days" +%Y-%m-%d)"
            usermod -e "$exp" "$username"
            passwd -u "$username" >/dev/null 2>&1 || true
            echo -e "${GREEN}New expiry: ${exp}${NC}"
        fi
    else
        echo -e "${RED}User exist nahi karta.${NC}"
    fi
}

modify_limits() {
    read -rp "Username: " username
    local conf="$USERS_DIR/${username}.conf"
    [[ -f "$conf" ]] || { echo -e "${RED}User config nahi mili.${NC}"; return; }
    echo "1) IP Limit"
    echo "2) GB Limit"
    read -rp "Option: " x
    case "$x" in
        1)
            read -rp "New IP Limit: " v
            sed -i "s/^IP_LIMIT=.*/IP_LIMIT=${v}/" "$conf"
            ;;
        2)
            read -rp "New GB Limit: " v
            sed -i "s/^GB_LIMIT=.*/GB_LIMIT=${v}/" "$conf"
            ;;
        *) return ;;
    esac
    passwd -u "$username" >/dev/null 2>&1 || true
    echo -e "${GREEN}Limit updated and account unlocked.${NC}"
}

check_connected_ips() {
    clear
    echo -e "${CYAN}=========== CONNECTED IPS / PORTS ===========${NC}"
    ss -tnp 2>/dev/null | grep -E ':(22|109|447|80|443|2082)[[:space:]]' || \
        echo -e "${YELLOW}No active matching connections.${NC}"
    echo
    echo -e "${GREEN}Listening ports:${NC}"
    ss -lntp 2>/dev/null | grep -E ':(22|109|447|80|443|2082)[[:space:]]' || true
    press_any_key
}

status_check() {
    clear
    local dom
    dom="$(get_domain)"
    echo -e "${CYAN}====================================================================${NC}"
    echo -e "${YELLOW}${BOLD}SYSTEM & PROTOCOL STATUS${NC}"
    echo -e "${CYAN}====================================================================${NC}"
    echo -e "Target Domain : ${BOLD}${dom}${NC}"
    echo -e "Active Path   : ${BOLD}${CUSTOM_PATH}${NC}"
    for svc in nginx dropbear ws-proxy autokill; do
        local s
        s="$(systemctl is-active "$svc" 2>/dev/null || true)"
        if [[ "$s" == "active" ]]; then
            printf " %-14s : ${GREEN}[ ACTIVE ]${NC}\n" "$svc"
        else
            printf " %-14s : ${RED}[ INACTIVE ]${NC}\n" "$svc"
        fi
    done
    echo
    ss -lntp 2>/dev/null | grep -E ':(22|80|109|443|447|2082)[[:space:]]' || true
    press_any_key
}

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
            > "$BANNER_FILE"
            while IFS= read -r line; do
                [[ "$line" == "END" ]] && break
                echo "$line" >> "$BANNER_FILE"
            done
            systemctl restart dropbear
            systemctl restart ssh 2>/dev/null || true
            echo -e "${GREEN}Banner updated.${NC}"
            press_any_key
            ;;
        2)
            clear
            cat "$BANNER_FILE" 2>/dev/null || true
            press_any_key
            ;;
        3)
            : > "$BANNER_FILE"
            systemctl restart dropbear
            systemctl restart ssh 2>/dev/null || true
            echo -e "${GREEN}Banner cleared.${NC}"
            press_any_key
            ;;
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
    press_any_key
}

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
            [[ -n "$token" && "$admin" =~ ^[0-9]+$ ]] || {
                echo -e "${RED}Invalid token/ID.${NC}"; press_any_key; return;
            }
            apt install -y python3-venv python3-pip
            rm -rf /opt/rr-tgbot-venv
            python3 -m venv /opt/rr-tgbot-venv
            /opt/rr-tgbot-venv/bin/pip install --upgrade pip >/dev/null
            /opt/rr-tgbot-venv/bin/pip install "python-telegram-bot==20.7"
            mkdir -p /etc/raretriccks/tgbot
            printf '{"token":"%s","super_admin":%s}\n' "$token" "$admin" > /etc/raretriccks/tgbot/config.json
            cat > /usr/local/bin/tgbot.py <<'PY_EOF'
import json, subprocess
from telegram import Update
from telegram.ext import Application, CommandHandler, ContextTypes
CFG="/etc/raretriccks/tgbot/config.json"
async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    c=json.load(open(CFG))
    if update.effective_user.id != c["super_admin"]:
        return
    await update.message.reply_text("RareTriccks VPN Panel Bot is online.")
def main():
    c=json.load(open(CFG))
    app=Application.builder().token(c["token"]).build()
    app.add_handler(CommandHandler("start",start))
    app.run_polling()
if __name__=="__main__":
    main()
PY_EOF
            chmod +x /usr/local/bin/tgbot.py
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
            press_any_key
            ;;
        2) systemctl restart tgbot; echo "Bot restarted."; press_any_key ;;
        3) systemctl stop tgbot; echo "Bot stopped."; press_any_key ;;
        4) systemctl status tgbot --no-pager; press_any_key ;;
    esac
}

uninstall_panel() {
    clear
    echo -e "${RED}${BOLD}WARNING: Panel components/users remove honge.${NC}"
    read -rp "Confirm ke liye YES likhein: " confirm
    [[ "$confirm" == "YES" ]] || { echo "Cancelled."; press_any_key; return; }

    systemctl stop ws-proxy autokill tgbot 2>/dev/null || true
    systemctl disable ws-proxy autokill tgbot 2>/dev/null || true
    rm -f /etc/systemd/system/ws-proxy.service /etc/systemd/system/autokill.service /etc/systemd/system/tgbot.service
    rm -f /usr/local/bin/ws-proxy.py /usr/local/bin/autokill.py /usr/local/bin/tgbot.py
    rm -rf /opt/rr-tgbot-venv
    rm -f /etc/nginx/conf.d/vpn.conf
    if [[ -d "$USERS_DIR" ]]; then
        for conf in "$USERS_DIR"/*.conf; do
            [[ -e "$conf" ]] || continue
            userdel -f "$(basename "$conf" .conf)" 2>/dev/null || true
        done
    fi
    rm -rf /etc/raretriccks
    systemctl daemon-reload
    systemctl restart nginx 2>/dev/null || true
    rm -f /usr/local/bin/menu /usr/bin/menu
    echo -e "${GREEN}Uninstall complete.${NC}"
    exit 0
}

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
    echo " 5) Check Status & Ports"
    echo " 6) Set / Edit SSH Banner"
    echo " 7) Fix SSH WS & WS+SSL Connection"
    echo " 8) Setup / Manage Telegram Bot"
    echo " 9) Uninstall Panel"
    echo " 10) Exit Panel"
    echo -e "${CYAN}====================================================${NC}"
    read -rp "Select Option [1-10]: " opt
    case "$opt" in
        1) install_all_components ;;
        2) add_domain_option; press_any_key ;;
        3) setup_ssl ;;
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
                    1) create_user; press_any_key ;;
                    2) delete_user; press_any_key ;;
                    3) check_connected_ips ;;
                    4) list_users ;;
                    5) renew_user; press_any_key ;;
                    6) modify_limits; press_any_key ;;
                    7) break ;;
                esac
            done
            ;;
        5) status_check ;;
        6) set_banner ;;
        7) fix_websocket ;;
        8) setup_telegram_bot ;;
        9) uninstall_panel ;;
        10) exit 0 ;;
        *) echo "Invalid option"; sleep 1 ;;
    esac
done
