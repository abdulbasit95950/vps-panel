#!/bin/bash
# RareTriccks VPN Panel - updated menu installer
# Dropbear compatibility fix for current Debian/Ubuntu packages.
# This keeps the original menu features and patches the broken Dropbear block.

set -euo pipefail

RAW_URL="https://raw.githubusercontent.com/abdulbasit95950/vps-panel/main/menu.sh"
TMP="$(mktemp /tmp/raretriccks-menu.XXXXXX)"
trap 'rm -f "$TMP"' EXIT

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}[ERROR] Is script ko ROOT ke taur par run karein.${NC}"
  exit 1
fi

echo -e "${CYAN}[1/4] Original menu.sh download ho raha hai...${NC}"
if command -v curl >/dev/null 2>&1; then
  curl -fsSL "$RAW_URL" -o "$TMP"
elif command -v wget >/dev/null 2>&1; then
  wget -qO "$TMP" "$RAW_URL"
elif command -v python3 >/dev/null 2>&1; then
  python3 - "$RAW_URL" "$TMP" <<'PY'
import sys, urllib.request
urllib.request.urlretrieve(sys.argv[1], sys.argv[2])
PY
else
  echo -e "${RED}[ERROR] curl/wget/python3 me se koi available nahi.${NC}"
  exit 1
fi

[[ -s "$TMP" ]] || { echo -e "${RED}[ERROR] menu.sh download empty hai.${NC}"; exit 1; }

echo -e "${CYAN}[2/4] Dropbear compatibility patch apply ho raha hai...${NC}"
python3 - "$TMP" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
s = p.read_text()

start = s.find('install_all_components() {')
if start < 0:
    raise SystemExit('install_all_components() not found')

marker = 'setup_ssl() {'
end = s.find(marker, start)
if end < 0:
    raise SystemExit('setup_ssl() marker not found')

block = s[start:end]

# Replace only the Dropbear setup portion inside install_all_components().
old_start = block.find('    echo -e "${BLUE}[2/6] Installing Required Tools...${NC}"')
old_end = block.find('    echo -e "${BLUE}[4/6] Creating Multi-Payload Python WebSocket Service...${NC}"')
if old_start < 0 or old_end < 0:
    raise SystemExit('Expected Dropbear installation section not found')

replacement = r'''    echo -e "${BLUE}[2/6] Installing Required Tools...${NC}"
    DEBIAN_FRONTEND=noninteractive apt install -y curl wget unzip tar net-tools socat jq openssl nginx dropbear certbot python3 python3-pip lsof iptables

    echo -e "${BLUE}[3/6] Configuring Dropbear SSH & Banner...${NC}"
    cat << 'BANNER_EOF' > "$BANNER_FILE"
<font color="green">==========================================</font><br>
<font color="yellow"><b>WELCOME TO RARETRICCKS VIP VPN</b></font><br>
<font color="red"><b>- NO TORRENT / NO MULTILOGIN</b></font><br>
<font color="green">==========================================</font><br>
BANNER_EOF

    # Modern Debian/Ubuntu Dropbear uses systemd and /etc/default/dropbear.
    # The old script used fragile sed replacements and NO_START, which is
    # obsolete in modern Dropbear packages. Rewrite the actual variables.
    mkdir -p /etc/dropbear

    if [[ -f /etc/default/dropbear ]]; then
        sed -i \
          -e '/^[[:space:]]*DROPBEAR_PORT[[:space:]]*=/d' \
          -e '/^[[:space:]]*DROPBEAR_EXTRA_ARGS[[:space:]]*=/d' \
          -e '/^[[:space:]]*NO_START[[:space:]]*=/d' \
          /etc/default/dropbear
    else
        : > /etc/default/dropbear
    fi

    cat >> /etc/default/dropbear << 'DROPBEAR_CFG_EOF'

# RareTriccks Dropbear configuration
DROPBEAR_PORT=109
DROPBEAR_EXTRA_ARGS="-p 447 -b /etc/issue.net"
DROPBEAR_RECEIVE_WINDOW=65536
DROPBEAR_CFG_EOF

    # Generate host keys when they are missing.
    if command -v dropbearkey >/dev/null 2>&1; then
        [[ -s /etc/dropbear/dropbear_rsa_host_key ]] || dropbearkey -t rsa -f /etc/dropbear/dropbear_rsa_host_key >/dev/null 2>&1 || true
        [[ -s /etc/dropbear/dropbear_ecdsa_host_key ]] || dropbearkey -t ecdsa -f /etc/dropbear/dropbear_ecdsa_host_key >/dev/null 2>&1 || true
        [[ -s /etc/dropbear/dropbear_ed25519_host_key ]] || dropbearkey -t ed25519 -f /etc/dropbear/dropbear_ed25519_host_key >/dev/null 2>&1 || true
    fi

    # OpenSSH remains on port 22; only its banner is changed.
    if [[ -f /etc/ssh/sshd_config ]]; then
        if grep -Eq '^[[:space:]]*#?[[:space:]]*Banner[[:space:]]+' /etc/ssh/sshd_config; then
            sed -i -E 's|^[[:space:]]*#?[[:space:]]*Banner[[:space:]].*|Banner /etc/issue.net|' /etc/ssh/sshd_config
        else
            printf '\nBanner /etc/issue.net\n' >> /etc/ssh/sshd_config
        fi
        sshd -t 2>/dev/null && (systemctl restart ssh.service 2>/dev/null || systemctl restart ssh 2>/dev/null || true)
    fi

    systemctl stop dropbear.service 2>/dev/null || systemctl stop dropbear 2>/dev/null || true
    systemctl daemon-reload
    systemctl enable dropbear.service 2>/dev/null || systemctl enable dropbear 2>/dev/null || true
    systemctl restart dropbear.service 2>/dev/null || systemctl restart dropbear

    sleep 1
    if ! systemctl is-active --quiet dropbear.service 2>/dev/null && ! systemctl is-active --quiet dropbear 2>/dev/null; then
        echo -e "${RED}[ERROR] Dropbear start nahi hua.${NC}"
        journalctl -u dropbear.service -n 30 --no-pager 2>/dev/null || journalctl -u dropbear -n 30 --no-pager 2>/dev/null || true
        return 1
    fi

    if ! ss -lnt 2>/dev/null | grep -Eq ':(109|447)[[:space:]]'; then
        echo -e "${RED}[ERROR] Dropbear active hai lekin 109/447 ports listen nahi kar rahe.${NC}"
        ss -lntp 2>/dev/null | grep -E ':(109|447|22)[[:space:]]' || true
        return 1
    fi

'''

block = block[:old_start] + replacement + block[old_end:]
s = s[:start] + block + s[end:]
p.write_text(s)
PY

bash -n "$TMP"

# Back up the installed menu if present.
if [[ -f /usr/local/bin/menu ]]; then
  cp -a /usr/local/bin/menu "/usr/local/bin/menu.backup.$(date +%Y%m%d-%H%M%S)"
fi

# The downloaded original menu is itself an installer script. Execute it so
# the patched menu gets written to /usr/local/bin/menu and /usr/bin/menu.
echo -e "${CYAN}[3/4] Patched menu install ho raha hai...${NC}"
bash "$TMP"

# Ensure executable permissions.
chmod +x /usr/local/bin/menu 2>/dev/null || true
cp -f /usr/local/bin/menu /usr/bin/menu 2>/dev/null || true
chmod +x /usr/bin/menu 2>/dev/null || true

echo -e "${CYAN}[4/4] Final Dropbear verification...${NC}"
systemctl daemon-reload
systemctl restart dropbear.service 2>/dev/null || systemctl restart dropbear 2>/dev/null || true
sleep 1

if systemctl is-active --quiet dropbear.service 2>/dev/null || systemctl is-active --quiet dropbear 2>/dev/null; then
  echo -e "${GREEN}[SUCCESS] Dropbear service ACTIVE.${NC}"
else
  echo -e "${RED}[ERROR] Dropbear service inactive.${NC}"
  journalctl -u dropbear.service -n 30 --no-pager 2>/dev/null || journalctl -u dropbear -n 30 --no-pager 2>/dev/null || true
  exit 1
fi

ss -lntp 2>/dev/null | grep -E ':(109|447|22)[[:space:]]' || true

echo -e "${GREEN}====================================================${NC}"
echo -e "${GREEN} RareTriccks menu.sh updated successfully!${NC}"
echo -e "${GREEN} Dropbear: 109 + 447${NC}"
echo -e "${GREEN} OpenSSH : 22${NC}"
echo -e "${GREEN}====================================================${NC}"
