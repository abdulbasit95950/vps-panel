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

apply_nginx_config() {
    local MY_DOMAIN=$(get_domain)
    
    if [[ "$MY_DOMAIN" == "No Domain Set" || -z "$MY_DOMAIN" ]]; then
        return
    fi

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

    location ${CUSTOM_PATH} {
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

    location ${CUSTOM_PATH} {
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
        mkdir -p /etc/raretriccks
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

    echo -e "${BLUE}[1/6] Updating Packages...${NC}"
    apt update -y && apt upgrade -y

    echo -e "${BLUE}[2/6] Installing Required Tools...${NC}"
    apt install -y curl wget unzip tar net-tools socat jq openssl nginx dropbear certbot python3 python3-pip lsof iptables

    echo -e "${BLUE}[3/6] Configuring Dropbear SSH & Banner...${NC}"
    
    cat << 'BANNER_EOF' > $BANNER_FILE
<font color="green">==========================================</font><br>
<font color="yellow"><b>WELCOME TO RARETRICCKS VIP VPN</b></font><br>
<font color="red"><b>- NO TORRENT / NO MULTILOGIN</b></font><br>
<font color="green">==========================================</font><br>
BANNER_EOF

    sed -i 's/NO_START=1/NO_START=0/g' /etc/default/dropbear
    sed -i 's/DROPBEAR_PORT=22/DROPBEAR_PORT=109/g' /etc/default/dropbear
    sed -i 's/DROPBEAR_EXTRA_ARGS=/DROPBEAR_EXTRA_ARGS="-p 447 -b \/etc\/issue.net"/g' /etc/default/dropbear
    
    sed -i 's/#Banner none/Banner \/etc\/issue.net/g' /etc/ssh/sshd_config
    systemctl restart ssh
    systemctl restart dropbear

    echo -e "${BLUE}[4/6] Creating Multi-Payload Python WebSocket Service...${NC}"
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
    except Exception:
        pass

def handle_client(client_socket, client_addr):
    real_ip = client_addr[0]
    try:
        client_socket.settimeout(10)
        request = client_socket.recv(4096).decode('utf-8', errors='ignore')
        if not request:
            client_socket.close()
            return

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
                if not data:
                    return
                other.sendall(data)
    except Exception:
        pass
    finally:
        client_socket.close()

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

    echo -e "${BLUE}[5/6] Installing Bandwidth & IPTables Tracking Engine...${NC}"
    install_python_tracker

    echo -e "\n${GREEN}[SUCCESS] Base components & Protection Engine Installed!${NC}"
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
        echo -e "${GREEN}[SUCCESS] Nginx SSL & WebSocket Proxy Configured!${NC}"
    else
        echo -e "${RED}[ERROR] SSL Fail ho gaya! Domain A Record IP par pointed hai ya nahi check karein.${NC}"
    fi

    press_any_key
}

check_connected_ips() {
    clear
    echo -e "${CYAN}====================================================================${NC}"
    echo -e "${YELLOW}${BOLD}                     CONNECTED IPS & ACTIVE USERS                   ${NC}"
    echo -e "${CYAN}====================================================================${NC}"
    
    echo -e "${GREEN}Active Online SSH / WebSocket Sessions:${NC}"
    echo -e "${CYAN}--------------------------------------------------------------------${NC}"
    
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

    local active_sockets=$(ss -tnp 2>/dev/null | grep ":109" | grep -i "ESTAB" | wc -l)
    if [[ $total_count -lt $active_sockets ]]; then
        echo -e "${YELLOW} Detected ${active_sockets} Active Tunnel Socket(s) connected to Dropbear Core.${NC}"
        [[ $total_count -eq 0 ]] && total_count=$active_sockets
    fi

    if [[ $total_count -eq 0 ]]; then
        echo -e "${YELLOW} Filhal koi active user connected nahi hai.${NC}"
    fi

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

    mkdir -p /etc/raretriccks/users

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
                
                useradd -M -s /bin/false -e "$exp_date" "$username" &>/dev/null
                echo "$username:$password" | chpasswd
                
                mkdir -p /etc/raretriccks/users
                echo "IP_LIMIT=$ip_limit" > "/etc/raretriccks/users/${username}.conf"
                echo "GB_LIMIT=$gb_limit" >> "/etc/raretriccks/users/${username}.conf"
                echo "USED_MB=0.0" >> "/etc/raretriccks/users/${username}.conf"

                echo -e "\n${GREEN}====================================================${NC}"
                echo -e "${YELLOW}           ACCOUNT CREATED BY RARETRICCKS           ${NC}"
                echo -e "${GREEN}====================================================${NC}"
                echo -e " Domain       : ${CYAN}${cur_dom}${NC}"
                echo -e " Username     : ${CYAN}${username}${NC}"
                echo -e " Password     : ${CYAN}${password}${NC}"
                echo -e " Expired On   : ${CYAN}${exp_date}${NC}"
                echo -e " Max IP Limit : ${CYAN}${ip_limit} Device(s)${NC}"
                echo -e " Data Limit   : ${CYAN}${gb_limit} GB${NC}"
                echo -e "${CYAN}----------------------------------------------------${NC}"
                echo -e " SSH Direct   : ${CYAN}22, 109, 447${NC}"
                echo -e " SSH WS (HTTP): ${CYAN}80${NC}"
                echo -e " SSH WS (SSL) : ${CYAN}443${NC}"
                echo -e "${CYAN}----------------------------------------------------${NC}"
                press_any_key
                ;;
            2)
                read -rp "Username to delete: " username
                userdel -f "$username" 2>/dev/null
                rm -f "/etc/raretriccks/users/${username}.conf"
                echo -e "${GREEN}User ${username} deleted successfully!${NC}"
                press_any_key
                ;;
            3) check_connected_ips ;;
            4) check_gb_usage ;;
            5)
                read -rp "Username to Renew: " username
                if id "$username" &>/dev/null; then
                    read -rp "Kitne additional days add karne hain? (e.g. 30): " r_days
                    new_exp=$(date -d "+$r_days days" +%Y-%m-%d)
                    usermod -e "$new_exp" "$username"
                    passwd -u "$username" 2>/dev/null
                    echo -e "${GREEN}[SUCCESS] User ${username} Expiry Extended. New Expiry: ${new_exp}${NC}"
                else
                    echo -e "${RED}[ERROR] User exist nahi karta!${NC}"
                fi
                press_any_key
                ;;
            6)
                read -rp "Username to change IP Limit: " username
                if [[ -f "/etc/raretriccks/users/${username}.conf" ]]; then
                    read -rp "Nayi IP Limit enter karein (e.g. 2 ya 3): " new_ip_l
                    sed -i "s/IP_LIMIT=.*/IP_LIMIT=${new_ip_l}/g" "/etc/raretriccks/users/${username}.conf"
                    passwd -u "$username" 2>/dev/null
                    echo -e "${GREEN}[SUCCESS] IP limit updated to ${new_ip_l} Device(s).${NC}"
                    echo -e "${GREEN}[INFO] Account ${username} is now UNLOCKED and Active!${NC}"
                else
                    echo -e "${RED}[ERROR] User config nahi mili!${NC}"
                fi
                press_any_key
                ;;
            7)
                read -rp "Username to extend GB limit: " username
                if [[ -f "/etc/raretriccks/users/${username}.conf" ]]; then
                    read -rp "Naya Data Limit GB me enter karein (e.g. 1 ya 50): " new_gb
                    sed -i "s/GB_LIMIT=.*/GB_LIMIT=${new_gb}/g" "/etc/raretriccks/users/${username}.conf"
                    passwd -u "$username" 2>/dev/null
                    echo -e "${GREEN}[SUCCESS] GB Limit updated to ${new_gb} GB.${NC}"
                    echo -e "${GREEN}[INFO] Account ${username} is now UNLOCKED and Active!${NC}"
                else
                    echo -e "${RED}[ERROR] User config nahi mili!${NC}"
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

    local ngx_badge="${RED}[ INACTIVE ]${NC}"
    local db_badge="${RED}[ INACTIVE ]${NC}"
    local ws_badge="${RED}[ INACTIVE ]${NC}"
    local ak_badge="${RED}[ INACTIVE ]${NC}"

    [[ "$nginx_status" == "active" ]] && ngx_badge="${GREEN}[ ACTIVE ]${NC}"
    [[ "$dropbear_status" == "active" ]] && db_badge="${GREEN}[ ACTIVE ]${NC}"
    [[ "$ws_status" == "active" ]] && ws_badge="${GREEN}[ ACTIVE ]${NC}"
    [[ "$ak_status" == "active" ]] && ak_badge="${GREEN}[ ACTIVE ]${NC}"

    echo -e "${CYAN}====================================================================${NC}"
    echo -e "${YELLOW}${BOLD}                     SYSTEM & PROTOCOL STATUS                       ${NC}"
    echo -e "${CYAN}====================================================================${NC}"
    echo -e " Target Domain : ${BOLD}${current_dom}${NC}"
    echo -e " Active Path   : ${BOLD}${CUSTOM_PATH}${NC}\n"

    echo -e "${CYAN} SERVICES STATUS${NC}"
    echo -e "${CYAN} ------------------------------------------------------------------${NC}"
    printf "   %-28s : %b\n" "Nginx SSL Proxy Engine" "$ngx_badge"
    printf "   %-28s : %b\n" "Dropbear SSH Core" "$db_badge"
    printf "   %-28s : %b\n" "Python WebSocket Service" "$ws_badge"
    printf "   %-28s : %b\n" "Auto-Lock & Bandwidth Daemon" "$ak_badge"
    echo ""

    echo -e "${CYAN}====================================================================${NC}"
    press_any_key
}

set_banner() {
    clear
    echo -e "${CYAN}====================================================${NC}"
    echo -e "${YELLOW}       ${PANEL_NAME} - SET SSH / WS BANNER       ${NC}"
    echo -e "${CYAN}====================================================${NC}"
    echo -e "1) Write HTML / Custom Banner"
    echo -e "2) View Current Banner"
    echo -e "3) Reset/Clear Banner"
    echo -e "4) Back"
    read -rp "Option [1-4]: " b_opt

    case $b_opt in
        1)
            echo -e "${YELLOW}Text banner paste karke [ENTER] dabayein (Ending line par END likhein):${NC}"
            > $BANNER_FILE
            while IFS= read -r line; do
                [[ $line == "END" ]] && break
                echo "$line" >> $BANNER_FILE
            done
            systemctl restart dropbear
            systemctl restart ssh
            echo -e "${GREEN}[SUCCESS] Banner updated!${NC}"
            press_any_key
            ;;
        2)
            clear
            echo -e "${CYAN}--- Current SSH Banner ---${NC}"
            cat $BANNER_FILE
            press_any_key
            ;;
        3)
            echo "" > $BANNER_FILE
            systemctl restart dropbear
            systemctl restart ssh
            echo -e "${GREEN}Banner cleared!${NC}"
            press_any_key
            ;;
        *) return ;;
    esac
}

fix_websocket() {
    clear
    echo -e "${CYAN}====================================================${NC}"
    echo -e "${YELLOW}       FIXING SSH WS & WS+SSL ENGINE               ${NC}"
    echo -e "${CYAN}====================================================${NC}"

    systemctl restart dropbear
    systemctl daemon-reload
    systemctl restart ws-proxy
    install_python_tracker
    apply_nginx_config

    echo -e "\n${GREEN}[COMPLETED] WebSocket System & Bandwidth Engine Active!${NC}"
    press_any_key
}

while true; do
    clear
    CURRENT_DOM=$(get_domain)
    echo -e "${CYAN}====================================================${NC}"
    echo -e "${GREEN}              ${PANEL_NAME}                       ${NC}"
    echo -e "${CYAN}====================================================${NC}"
    echo -e " Domain Target: ${YELLOW}${CURRENT_DOM}${NC}"
    echo -e " Custom Path  : ${YELLOW}${CUSTOM_PATH}${NC}"
    echo -e "${CYAN}----------------------------------------------------${NC}"
    echo -e " 1) Auto Install System Components"
    echo -e " 2) Add / Change Domain Name"
    echo -e " 3) Issue SSL Certificate"
    echo -e " 4) Manage Accounts (Add/Delete/Renew/Limits)"
    echo -e " 5) Check Status & Ports"
    echo -e " 6) Set / Edit SSH Banner"
    echo -e " 7) Fix SSH WS & WS+SSL Connection"
    echo -e " 8) Exit Panel"
    echo -e "${CYAN}====================================================${NC}"
    read -rp "Select Option [1-8]: " opt

    case $opt in
        1) install_all_components ;;
        2) add_domain_option ;;
        3) setup_ssl ;;
        4) user_menu ;;
        5) status_check ;;
        6) set_banner ;;
        7) fix_websocket ;;
        8) exit 0 ;;
        *) echo "Invalid option"; sleep 1 ;;
    esac
done
EOF

chmod +x /usr/local/bin/menu
cp /usr/local/bin/menu /usr/bin/menu 2>/dev/null
