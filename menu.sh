Cat << 'EOF' > /usr/local/bin/menu
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
    If [[ -f "$DOMAIN_FILE" ]]; then
        Cat "$DOMAIN_FILE" | tr -d '\r\n'
    Else
        Echo "No Domain Set"
    Fi
}

press_any_key() {
    Echo -e "\n${YELLOW}Press [ENTER] key to return to main menu...${NC}"
    Read -r
}

install_python_tracker() {
    Cat << 'PY_EOF' > /usr/local/bin/autokill.py
Import os
import sys
import time
import subprocess
import re

USER_DIR = "/etc/raretriccks/users"
LOG_FILE = "/var/log/autokill.log"

def get_auth_logs():
    Raw = ""
    Try:
        Raw = subprocess.check_output(["journalctl", "-u", "dropbear", "--no-pager", "-n", "300"], stderr=subprocess.DEVNULL).decode("utf-8", errors="ignore")
    Except Exception:
        Pass
    If os.path.exists("/var/log/auth.log"):
        Try:
            With open("/var/log/auth.log", "r", encoding="utf-8", errors="ignore") as f:
                Raw += "\n" + f.read()
        Except Exception:
            Pass
    Return raw

def get_active_users_and_pids(raw_logs):
    User_pids = {}
    Try:
        Ps_out = subprocess.check_output(["ps", "aux"], stderr=subprocess.DEVNULL).decode("utf-8", errors="ignore")
        For line in ps_out.splitlines():
            If "dropbear" in line and "grep" not in line:
                Parts = line.split()
                If len(parts) > 1:
                    Pid = parts[1]
                    Matches = [l for l in raw_logs.splitlines() if f"dropbear[{pid}]" in l and "Password auth succeeded" in l]
                    If matches:
                        Last_line = matches[-1]
                        M = re.search(r"for \x27(\w+)\x27", last_line)
                        If not m:
                            M = re.search(r"for (\w+)", last_line)
                        If m:
                            Uname = m.group(1)
                            If uname not in user_pids:
                                User_pids[uname] = []
                            User_pids[uname].append(pid)
    Except Exception:
        Pass
    Return user_pids

def get_pid_io_bytes(pid):
    Io_file = f"/proc/{pid}/io"
    Total_bytes = 0
    If os.path.exists(io_file):
        Try:
            With open(io_file, "r") as f:
                For line in f:
                    If line.startswith("rchar:") or line.startswith("wchar:"):
                        Total_bytes += int(line.split(":")[1].strip())
        Except Exception:
            Pass
    Return total_bytes

last_pid_bytes = {}

While True:
    Try:
        Raw_logs = get_auth_logs()
        User_pids_map = get_active_users_and_pids(raw_logs)

        If os.path.exists(USER_DIR):
            For fname in os.listdir(USER_DIR):
                If not fname.endswith(".conf"):
                    Continue
                
                Uname = fname[:-5]
                Conf_path = os.path.join(USER_DIR, fname)
                
                Ip_limit = 0
                Gb_limit = "Unlimited"
                Used_mb = 0.0

                With open(conf_path, "r") as f:
                    Lines = f.readlines()

                For line in lines:
                    If line.startswith("IP_LIMIT="):
                        Try: ip_limit = int(line.strip().split("=")[1])
                        Except Exception: pass
                    Elif line.startswith("GB_LIMIT="):
                        Gb_limit = line.strip().split("=")[1]
                    Elif line.startswith("USED_MB="):
                        Try: used_mb = float(line.strip().split("=")[1])
                        Except Exception: pass

                Active_pids = user_pids_map.get(uname, [])

                For pid in active_pids:
                    Current_b = get_pid_io_bytes(pid)
                    If pid in last_pid_bytes:
                        Diff = current_b - last_pid_bytes[pid]
                        If diff > 0:
                            Used_mb += (diff / (1024.0 * 1024.0))
                    Last_pid_bytes[pid] = current_b

                New_lines = []
                For line in lines:
                    If line.startswith("USED_MB="):
                        New_lines.append(f"USED_MB={used_mb:.2f}\n")
                    Else:
                        New_lines.append(line)
                With open(conf_path, "w") as f:
                    F.writelines(new_lines)

                If gb_limit != "Unlimited":
                    Try:
                        Max_mb = float(gb_limit) * 1024.0
                        If used_mb >= max_mb:
                            Subprocess.call(["passwd", "-l", uname], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                            For pid in active_pids:
                                Subprocess.call(["kill", "-9", pid], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    Except Exception:
                        Pass

                If ip_limit > 0 and len(active_pids) > ip_limit:
                    Subprocess.call(["passwd", "-l", uname], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    For pid in active_pids:
                        Subprocess.call(["kill", "-9", pid], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    Except Exception:
        Pass

    Time.sleep(3)
PY_EOF
    Chmod +x /usr/local/bin/autokill.py

    Cat << 'SVC_EOF' > /etc/systemd/system/autokill.service
[Unit]
Description=RareTriccks Auto-Kill & Bandwidth Tracking Service
After=network.target

[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/autokill.py
Restart=always

[Install]
WantedBy=multi-user.target
SVC_EOF

    Systemctl daemon-reload
    Systemctl enable autokill
    Systemctl restart autokill
}

apply_nginx_config() {
    Local MY_DOMAIN=$(get_domain)
    
    If [[ "$MY_DOMAIN" == "No Domain Set" || -z "$MY_DOMAIN" ]]; then
        Return
    Fi

    Cat << NGX_EOF > /etc/nginx/conf.d/vpn.conf
server {
    Listen 80 default_server;
    Listen [::]:80 default_server;
    Server_name ${MY_DOMAIN} _;

    Location / {
        Proxy_redirect off;
        Proxy_pass http://127.0.0.1:2082;
        Proxy_http_version 1.1;
        Proxy_set_header Upgrade \$http_upgrade;
        Proxy_set_header Connection "upgrade";
        Proxy_set_header Host \$host;
        Proxy_set_header X-Real-IP \$remote_addr;
        Proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        Proxy_read_timeout 86400s;
        Proxy_send_timeout 86400s;
    }

    Location ${CUSTOM_PATH} {
        Proxy_redirect off;
        Proxy_pass http://127.0.0.1:2082;
        Proxy_http_version 1.1;
        Proxy_set_header Upgrade \$http_upgrade;
        Proxy_set_header Connection "upgrade";
        Proxy_set_header Host \$host;
        Proxy_set_header X-Real-IP \$remote_addr;
        Proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        Proxy_read_timeout 86400s;
        Proxy_send_timeout 86400s;
    }
}

server {
    Listen 443 ssl http2 default_server;
    Listen [::]:443 ssl http2 default_server;
    Server_name ${MY_DOMAIN} _;

    Ssl_certificate /etc/letsencrypt/live/${MY_DOMAIN}/fullchain.pem;
    Ssl_certificate_key /etc/letsencrypt/live/${MY_DOMAIN}/privkey.pem;
    Ssl_protocols TLSv1.2 TLSv1.3;

    Location / {
        Proxy_redirect off;
        Proxy_pass http://127.0.0.1:2082;
        Proxy_http_version 1.1;
        Proxy_set_header Upgrade \$http_upgrade;
        Proxy_set_header Connection "upgrade";
        Proxy_set_header Host \$host;
        Proxy_set_header X-Real-IP \$remote_addr;
        Proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        Proxy_read_timeout 86400s;
        Proxy_send_timeout 86400s;
    }

    Location ${CUSTOM_PATH} {
        Proxy_redirect off;
        Proxy_pass http://127.0.0.1:2082;
        Proxy_http_version 1.1;
        Proxy_set_header Upgrade \$http_upgrade;
        Proxy_set_header Connection "upgrade";
        Proxy_set_header Host \$host;
        Proxy_set_header X-Real-IP \$remote_addr;
        Proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        Proxy_read_timeout 86400s;
        Proxy_send_timeout 86400s;
    }
}
NGX_EOF
    Rm -f /etc/nginx/sites-enabled/default
    Systemctl restart nginx 2>/dev/null
}

add_domain_option() {
    Clear
    Echo -e "${CYAN}====================================================${NC}"
    Echo -e "${YELLOW}        ADD / CHANGE DOMAIN NAME                    ${NC}"
    Echo -e "${CYAN}====================================================${NC}"
    Read -rp " Apna Domain Enter Karein (e.g. sub.yourdomain.com): " new_dom

    If [[ -z "$new_dom" ]]; then
        Echo -e "${RED}[ERROR] Domain khaali nahi chhod sakte!${NC}"
    Else
        Mkdir -p /etc/raretriccks
        Echo "$new_dom" > "$DOMAIN_FILE"
        Echo -e "\n${GREEN}[SUCCESS] Domain successfully set to: ${CYAN}${new_dom}${NC}"
        Apply_nginx_config
    Fi
    Press_any_key
}

install_all_components() {
    Clear
    Echo -e "${CYAN}====================================================${NC}"
    Echo -e "${YELLOW}   ${PANEL_NAME} - SYSTEM INSTALLATION           ${NC}"
    Echo -e "${CYAN}====================================================${NC}"

    Echo -e "${BLUE}[1/6] Updating Packages...${NC}"
    Apt update -y && apt upgrade -y

    Echo -e "${BLUE}[2/6] Installing Required Tools...${NC}"
    Apt install -y curl wget unzip tar net-tools socat jq openssl nginx dropbear certbot python3 python3-pip lsof iptables

    Echo -e "${BLUE}[3/6] Configuring Dropbear SSH & Banner...${NC}"
    
    # Updated Colored HTML Banner configured here automatically
    Cat << 'BANNER_EOF' > $BANNER_FILE
<font color="green">==========================================</font><br>
<font color="yellow"><b>WELCOME TO RARETRICCKS VIP VPN</b></font><br>
<font color="red"><b>- NO TORRENT / NO MULTILOGIN</b></font><br>
<font color="green">==========================================</font><br>
BANNER_EOF

    Sed -i 's/NO_START=1/NO_START=0/g' /etc/default/dropbear
    Sed -i 's/DROPBEAR_PORT=22/DROPBEAR_PORT=109/g' /etc/default/dropbear
    Sed -i 's/DROPBEAR_EXTRA_ARGS=/DROPBEAR_EXTRA_ARGS="-p 447 -b \/etc\/issue.net"/g' /etc/default/dropbear
    
    Sed -i 's/#Banner none/Banner \/etc\/issue.net/g' /etc/ssh/sshd_config
    Systemctl restart ssh
    Systemctl restart dropbear

    Echo -e "${BLUE}[4/6] Creating Multi-Payload Python WebSocket Service...${NC}"
    Cat << 'WS_EOF' > /usr/local/bin/ws-proxy.py
Import socket, threading, select, time

PORT = 2082
TARGET_HOST = '127.0.0.1'
TARGET_PORT = 109
LOG_FILE = '/var/log/ws-proxy.log'

def log_client_ip(ip):
    Try:
        With open(LOG_FILE, 'a') as f:
            F.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} - REAL_IP:{ip}\n")
    Except Exception:
        Pass

def handle_client(client_socket, client_addr):
    Real_ip = client_addr[0]
    Try:
        Client_socket.settimeout(10)
        Request = client_socket.recv(4096).decode('utf-8', errors='ignore')
        If not request:
            Client_socket.close()
            Return

        For line in request.split('\r\n'):
            If line.lower().startswith('x-forwarded-for:') or line.lower().startswith('x-real-ip:'):
                Real_ip = line.split(':')[1].strip().split(',')[0].strip()
                Break

        Log_client_ip(real_ip)

        Response = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n"
        Client_socket.sendall(response.encode('utf-8'))

        Target_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        Target_socket.connect((TARGET_HOST, TARGET_PORT))

        Sockets = [client_socket, target_socket]
        Client_socket.settimeout(None)

        While True:
            Readable, _, _ = select.select(sockets, [], [])
            For s in readable:
                Other = target_socket if s is client_socket else client_socket
                Data = s.recv(8192)
                If not data:
                    Return
                Other.sendall(data)
    Except Exception:
        Pass
    Finally:
        Client_socket.close()

Server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
Server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
Server.bind(('0.0.0.0', PORT))
Server.listen(200)

While True:
    Client, addr = server.accept()
    Threading.Thread(target=handle_client, args=(client, addr), daemon=True).start()
WS_EOF

    Cat << SVC_EOF > /etc/systemd/system/ws-proxy.service
[Unit]
Description=RareTriccks WebSocket Proxy Service
After=network.target

[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/ws-proxy.py
Restart=always

[Install]
WantedBy=multi-user.target
SVC_EOF

    Systemctl daemon-reload
    Systemctl enable ws-proxy
    Systemctl restart ws-proxy
    Apply_nginx_config

    Echo -e "${BLUE}[5/6] Installing Bandwidth & IPTables Tracking Engine...${NC}"
    Install_python_tracker

    Echo -e "\n${GREEN}[SUCCESS] Base components & Protection Engine Installed!${NC}"
    Press_any_key
}

setup_ssl() {
    Clear
    Local current_dom=$(get_domain)

    If [[ "$current_dom" == "No Domain Set" || -z "$current_dom" ]]; then
        Echo -e "${RED}[ERROR] Pehle Option 2 se Domain Add karein!${NC}"
        Press_any_key
        Return
    Fi

    Echo -e "${CYAN}====================================================${NC}"
    Echo -e "${YELLOW}  ${PANEL_NAME} - ISSUING SSL (${current_dom}) ${NC}"
    Echo -e "${CYAN}====================================================${NC}"

    Systemctl stop nginx

    Certbot certonly --standalone --preferred-challenges http --agree-tos --register-unsafely-without-email -d "$current_dom"

    If [[ -f "/etc/letsencrypt/live/$current_dom/fullchain.pem" ]]; then
        Echo -e "\n${GREEN}[SUCCESS] SSL Active for ${current_dom}!${NC}"
        Apply_nginx_config
        Echo -e "${GREEN}[SUCCESS] Nginx SSL & WebSocket Proxy Configured!${NC}"
    Else
        Echo -e "${RED}[ERROR] SSL Fail ho gaya! Domain A Record IP par pointed hai ya nahi check karein.${NC}"
    Fi

    Press_any_key
}

check_connected_ips() {
    Clear
    Echo -e "${CYAN}====================================================================${NC}"
    Echo -e "${YELLOW}${BOLD}                     CONNECTED IPS & ACTIVE USERS                   ${NC}"
    Echo -e "${CYAN}====================================================================${NC}"
    
    Echo -e "${GREEN}Active Online SSH / WebSocket Sessions:${NC}"
    Echo -e "${CYAN}--------------------------------------------------------------------${NC}"
    
    Local total_count=0
    Local raw_logs=""
    If command -v journalctl &>/dev/null; then
        Raw_logs=$(journalctl -u dropbear --no-pager -n 400 2>/dev/null)
    Fi
    [[ -f "/var/log/auth.log" ]] && raw_logs+=$'\n'$(cat /var/log/auth.log 2>/dev/null)

    Mapfile -t external_ips < <(ss -tnp 2>/dev/null | grep -E ":(80|443|2082)" | grep "ESTAB" | awk '{print $5}' | cut -d: -f1 | grep -vE "^127\.|^::1" | sort -u)
    Mapfile -t ws_logged_ips < <(grep -oP "(?<=REAL_IP:)\S+" /var/log/ws-proxy.log 2>/dev/null | tail -n 20 | sort -u)

    Local real_ip_pool=($(echo "${external_ips[@]} ${ws_logged_ips[@]}" | tr ' ' '\n' | sort -u))
    Local ip_index=0

    For pid in $(ps aux | grep dropbear | grep -v grep | awk '{print $2}'); do
        Local user_match=$(echo "$raw_logs" | grep "dropbear\[$pid\]" | grep -i "Password auth succeeded" | tail -n 1)
        
        If [[ -n "$user_match" ]]; then
            Local username=$(echo "$user_match" | grep -oP "(?<=for ')\w+(?=')" || echo "$user_match" | awk '{for(i=1;i<=NF;i++) if($i=="for") print $(i+1)}')
            Local logged_ip=$(echo "$user_match" | grep -oP "(?<=from )\S+(?=:)")
            Local final_ip="$logged_ip"

            If [[ "$logged_ip" == "127.0.0.1" || -z "$logged_ip" ]]; then
                If [[ ${#real_ip_pool[@]} -gt 0 && $ip_index -lt ${#real_ip_pool[@]} ]]; then
                    Final_ip="${real_ip_pool[$ip_index]} (WS Tunnel)"
                    Ip_index=$((ip_index + 1))
                Else
                    Final_ip="WS-Proxy Client"
                Fi
            Fi
            
            If [[ -n "$username" ]]; then
                Printf " User: %-18s | IP/Source: %-25s [ONLINE]\n" "$username" "$final_ip"
                Total_count=$((total_count + 1))
            Fi
        Fi
    done

    Local active_sockets=$(ss -tnp 2>/dev/null | grep ":109" | grep -i "ESTAB" | wc -l)
    If [[ $total_count -lt $active_sockets ]]; then
        Echo -e "${YELLOW} Detected ${active_sockets} Active Tunnel Socket(s) connected to Dropbear Core.${NC}"
        [[ $total_count -eq 0 ]] && total_count=$active_sockets
    Fi

    If [[ $total_count -eq 0 ]]; then
        Echo -e "${YELLOW} Filhal koi active user connected nahi hai.${NC}"
    Fi

    Echo -e "${CYAN}====================================================================${NC}"
    Echo -e " Total Active Sessions: ${BOLD}${total_count}${NC}"
    Echo -e "${CYAN}====================================================================${NC}"
    Press_any_key
}

check_gb_usage() {
    Clear
    Echo -e "${CYAN}====================================================================${NC}"
    Echo -e "${YELLOW}${BOLD}                USER BANDWIDTH / EXPIRY & LOCK STATUS               ${NC}"
    Echo -e "${CYAN}====================================================================${NC}"
    
    Printf " %-14s | %-7s | %-10s | %-12s | %-10s\n" "USERNAME" "IP LIMIT" "DATA USED" "DATA LIMIT" "STATUS"
    Echo -e "${CYAN}--------------------------------------------------------------------${NC}"

    Mkdir -p /etc/raretriccks/users

    For conf in /etc/raretriccks/users/*.conf; do
        [[ -e "$conf" ]] || continue
        Local uname=$(basename "$conf" .conf)
        Local limit=$(grep "^GB_LIMIT=" "$conf" | cut -d= -f2)
        Local ip_l=$(grep "^IP_LIMIT=" "$conf" | cut -d= -f2)
        Local used_mb=$(grep "^USED_MB=" "$conf" | cut -d= -f2)
        
        [[ -z "$limit" ]] && limit="Unlimited"
        [[ -z "$ip_l" ]] && ip_l="1"
        [[ -z "$used_mb" ]] && used_mb="0"

        Local used_gb=$(python3 -c "print(f'{$used_mb/1024:.2f}')")

        Local status="${GREEN}Active${NC}"
        If id "$uname" &>/dev/null; then
            If passwd -S "$uname" 2>/dev/null | grep -q "L"; then
                Status="${RED}LOCKED${NC}"
            Fi
        Else
            Status="${RED}Deleted${NC}"
        Fi

        Printf " %-14s | %-8s | %-7s GB | %-9s GB | %b\n" "$uname" "$ip_l" "$used_gb" "$limit" "$status"
    done

    Echo -e "${CYAN}====================================================================${NC}"
    Press_any_key
}

user_menu() {
    Local cur_dom=$(get_domain)
    While true; do
        Clear
        Echo -e "${CYAN}====================================================${NC}"
        Echo -e "${YELLOW}       ${PANEL_NAME} - USER MANAGEMENT           ${NC}"
        Echo -e "${CYAN}====================================================${NC}"
        Echo -e " 1) Add New User"
        Echo -e " 2) Delete User"
        Echo -e " 3) Check Connected IPs & Active Online Users"
        Echo -e " 4) Check User Status, Quota & Limits"
        Echo -e " 5) Renew Account Expiry Days"
        Echo -e " 6) Extend / Modify IP Limit (Auto Unlock)"
        Echo -e " 7) Extend / Modify GB Data Quota (Auto Unlock)"
        Echo -e " 8) Back to Main Menu"
        Echo -e "${CYAN}====================================================${NC}"
        Read -rp "Option [1-8]: " u_choice

        Case $u_choice in
            1)
                Read -rp "Username: " username
                Read -rp "Password: " password
                Read -rp "Days Expiry (e.g. 30): " days
                Read -rp "Max IP Limit (e.g. 1 ya 2): " ip_limit
                Read -rp "Quota / Data Limit in GB (e.g. 0.5 ya 50): " gb_limit

                Exp_date=$(date -d "+$days days" +%Y-%m-%d)
                
                # FIXED USER CREATION BLOCK
                Useradd -M -s /bin/false -e "$exp_date" "$username" &>/dev/null
                Echo "$username:$password" | chpasswd
                
                Mkdir -p /etc/raretriccks/users
                Echo "IP_LIMIT=$ip_limit" > "/etc/raretriccks/users/${username}.conf"
                Echo "GB_LIMIT=$gb_limit" >> "/etc/raretriccks/users/${username}.conf"
                Echo "USED_MB=0.0" >> "/etc/raretriccks/users/${username}.conf"

                Echo -e "\n${GREEN}====================================================${NC}"
                Echo -e "${YELLOW}           ACCOUNT CREATED BY RARETRICCKS           ${NC}"
                Echo -e "${GREEN}====================================================${NC}"
                Echo -e " Domain       : ${CYAN}${cur_dom}${NC}"
                Echo -e " Username     : ${CYAN}${username}${NC}"
                Echo -e " Password     : ${CYAN}${password}${NC}"
                Echo -e " Expired On   : ${CYAN}${exp_date}${NC}"
                Echo -e " Max IP Limit : ${CYAN}${ip_limit} Device(s)${NC}"
                Echo -e " Data Limit   : ${CYAN}${gb_limit} GB${NC}"
                Echo -e "${CYAN}----------------------------------------------------${NC}"
                Echo -e " SSH Direct   : ${CYAN}22, 109, 447${NC}"
                Echo -e " SSH WS (HTTP): ${CYAN}80${NC}"
                Echo -e " SSH WS (SSL) : ${CYAN}443${NC}"
                Echo -e "${CYAN}----------------------------------------------------${NC}"
                Press_any_key
                ;;
            2)
                Read -rp "Username to delete: " username
                Userdel -f "$username" 2>/dev/null
                Rm -f "/etc/raretriccks/users/${username}.conf"
                Echo -e "${GREEN}User ${username} deleted successfully!${NC}"
                Press_any_key
                ;;
            3) check_connected_ips ;;
            4) check_gb_usage ;;
            5)
                Read -rp "Username to Renew: " username
                If id "$username" &>/dev/null; then
                    Read -rp "Kitne additional days add karne hain? (e.g. 30): " r_days
                    New_exp=$(date -d "+$r_days days" +%Y-%m-%d)
                    Usermod -e "$new_exp" "$username"
                    Passwd -u "$username" 2>/dev/null
                    Echo -e "${GREEN}[SUCCESS] User ${username} Expiry Extended. New Expiry: ${new_exp}${NC}"
                Else
                    Echo -e "${RED}[ERROR] User exist nahi karta!${NC}"
                Fi
                Press_any_key
                ;;
            6)
                Read -rp "Username to change IP Limit: " username
                If [[ -f "/etc/raretriccks/users/${username}.conf" ]]; then
                    Read -rp "Nayi IP Limit enter karein (e.g. 2 ya 3): " new_ip_l
                    Sed -i "s/IP_LIMIT=.*/IP_LIMIT=${new_ip_l}/g" "/etc/raretriccks/users/${username}.conf"
                    Passwd -u "$username" 2>/dev/null
                    Echo -e "${GREEN}[SUCCESS] IP limit updated to ${new_ip_l} Device(s).${NC}"
                    Echo -e "${GREEN}[INFO] Account ${username} is now UNLOCKED and Active!${NC}"
                Else
                    Echo -e "${RED}[ERROR] User config nahi mili!${NC}"
                Fi
                Press_any_key
                ;;
            7)
                Read -rp "Username to extend GB limit: " username
                If [[ -f "/etc/raretriccks/users/${username}.conf" ]]; then
                    Read -rp "Naya Data Limit GB me enter karein (e.g. 1 ya 50): " new_gb
                    Sed -i "s/GB_LIMIT=.*/GB_LIMIT=${new_gb}/g" "/etc/raretriccks/users/${username}.conf"
                    Passwd -u "$username" 2>/dev/null
                    Echo -e "${GREEN}[SUCCESS] GB Limit updated to ${new_gb} GB.${NC}"
                    Echo -e "${GREEN}[INFO] Account ${username} is now UNLOCKED and Active!${NC}"
                Else
                    Echo -e "${RED}[ERROR] User config nahi mili!${NC}"
                Fi
                Press_any_key
                ;;
            8) return ;;
            *) echo "Invalid Option"; sleep 1 ;;
        esac
    done
}

status_check() {
    Clear
    Local current_dom=$(get_domain)
    Local nginx_status=$(systemctl is-active nginx 2>/dev/null)
    Local dropbear_status=$(systemctl is-active dropbear 2>/dev/null)
    Local ws_status=$(systemctl is-active ws-proxy 2>/dev/null)
    Local ak_status=$(systemctl is-active autokill 2>/dev/null)

    Local ngx_badge="${RED}[ INACTIVE ]${NC}"
    Local db_badge="${RED}[ INACTIVE ]${NC}"
    Local ws_badge="${RED}[ INACTIVE ]${NC}"
    Local ak_badge="${RED}[ INACTIVE ]${NC}"

    [[ "$nginx_status" == "active" ]] && ngx_badge="${GREEN}[ ACTIVE ]${NC}"
    [[ "$dropbear_status" == "active" ]] && db_badge="${GREEN}[ ACTIVE ]${NC}"
    [[ "$ws_status" == "active" ]] && ws_badge="${GREEN}[ ACTIVE ]${NC}"
    [[ "$ak_status" == "active" ]] && ak_badge="${GREEN}[ ACTIVE ]${NC}"

    Echo -e "${CYAN}====================================================================${NC}"
    Echo -e "${YELLOW}${BOLD}                     SYSTEM & PROTOCOL STATUS                       ${NC}"
    Echo -e "${CYAN}====================================================================${NC}"
    Echo -e " Target Domain : ${BOLD}${current_dom}${NC}"
    Echo -e " Active Path   : ${BOLD}${CUSTOM_PATH}${NC}\n"

    Echo -e "${CYAN} SERVICES STATUS${NC}"
    Echo -e "${CYAN} ------------------------------------------------------------------${NC}"
    Printf "   %-28s : %b\n" "Nginx SSL Proxy Engine" "$ngx_badge"
    Printf "   %-28s : %b\n" "Dropbear SSH Core" "$db_badge"
    Printf "   %-28s : %b\n" "Python WebSocket Service" "$ws_badge"
    Printf "   %-28s : %b\n" "Auto-Lock & Bandwidth Daemon" "$ak_badge"
    Echo ""

    Echo -e "${CYAN}====================================================================${NC}"
    Press_any_key
}

set_banner() {
    Clear
    Echo -e "${CYAN}====================================================${NC}"
    Echo -e "${YELLOW}       ${PANEL_NAME} - SET SSH / WS BANNER       ${NC}"
    Echo -e "${CYAN}====================================================${NC}"
    Echo -e "1) Write HTML / Custom Banner"
    Echo -e "2) View Current Banner"
    Echo -e "3) Reset/Clear Banner"
    Echo -e "4) Back"
    Read -rp "Option [1-4]: " b_opt

    Case $b_opt in
        1)
            Echo -e "${YELLOW}Text banner paste karke [ENTER] dabayein (Ending line par END likhein):${NC}"
            > $BANNER_FILE
            While IFS= read -r line; do
                [[ $line == "END" ]] && break
                Echo "$line" >> $BANNER_FILE
            Done
            Systemctl restart dropbear
            Systemctl restart ssh
            Echo -e "${GREEN}[SUCCESS] Banner updated!${NC}"
            Press_any_key
            ;;
        2)
            Clear
            Echo -e "${CYAN}--- Current SSH Banner ---${NC}"
            Cat $BANNER_FILE
            Press_any_key
            ;;
        3)
            Echo "" > $BANNER_FILE
            Systemctl restart dropbear
            Systemctl restart ssh
            Echo -e "${GREEN}Banner cleared!${NC}"
            Press_any_key
            ;;
        *) return ;;
    esac
}

fix_websocket() {
    Clear
    Echo -e "${CYAN}====================================================${NC}"
    Echo -e "${YELLOW}       FIXING SSH WS & WS+SSL ENGINE               ${NC}"
    Echo -e "${CYAN}====================================================${NC}"

    Systemctl restart dropbear
    Systemctl daemon-reload
    Systemctl restart ws-proxy
    Install_python_tracker
    Apply_nginx_config

    Echo -e "\n${GREEN}[COMPLETED] WebSocket System & Bandwidth Engine Active!${NC}"
    Press_any_key
}

While true; do
    Clear
    CURRENT_DOM=$(get_domain)
    Echo -e "${CYAN}====================================================${NC}"
    Echo -e "${GREEN}              ${PANEL_NAME}                       ${NC}"
    Echo -e "${CYAN}====================================================${NC}"
    Echo -e " Domain Target: ${YELLOW}${CURRENT_DOM}${NC}"
    Echo -e " Custom Path  : ${YELLOW}${CUSTOM_PATH}${NC}"
    Echo -e "${CYAN}----------------------------------------------------${NC}"
    Echo -e " 1) Auto Install System Components"
    Echo -e " 2) Add / Change Domain Name"
    Echo -e " 3) Issue SSL Certificate"
    Echo -e " 4) Manage Accounts (Add/Delete/Renew/Limits)"
    Echo -e " 5) Check Status & Ports"
    Echo -e " 6) Set / Edit SSH Banner"
    Echo -e " 7) Fix SSH WS & WS+SSL Connection"
    Echo -e " 8) Exit Panel"
    Echo -e "${CYAN}====================================================${NC}"
    Read -rp "Select Option [1-8]: " opt

    Case $opt in
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

Chmod +x /usr/local/bin/menu
Cp /usr/local/bin/menu /usr/bin/menu 2>/dev/null
