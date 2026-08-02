#!/bin/bash

# =======================================================
# Script Name : RareTriccks VPN Panel (IP Protected)
# =======================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# IP Authorization Check Function
check_ip_authorization() {
    echo -e "${CYAN}[INFO] Checking IP Permission...${NC}"
    
    # Fetch VPS Public IP
    MY_IP=$(curl -s https://api.ipify.org || curl -s https://ipv4.icanhazip.com)
    
    if [[ -z "$MY_IP" ]]; then
        echo -e "${RED}[ERROR] Unable to detect server IP```{NC}"
        exit 1
    fi

    # Download current allowed IPs list from GitHub ips.txt
    ALLOWED_IPS=$(curl -s https://raw.githubusercontent.com/abdulbasit95950/vps-panel/main/ips.txt)

    # Check if MY_IP exists in ips.txt
    if echo "$ALLOWED_IPS" | grep -q "$MY_IP"; then
        echo -e "${GREEN}[SUCCESS] IP $MY_IP is Approved```{NC}"
    else
        echo -e "${RED}[PERMISSION DENIED] Your IP ($MY_IP) is not authorized to use this panel```{NC}"
        echo -e "${YELLOW}Please contact admin to add your IP in ips.txt.${NC}"
        exit 1
    fi
}

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}[ERROR] Veh script ROOT privilege ke sath chalaen! (sudo -i)${NC}"
   exit 1
fi

# Step 1: Run IP Protection Check
check_ip_authorization

# Step 2: Install Encrypted Bot Script
install_telegram_bot() {
    echo "aW1wb3J0IG9zLCBzeXMsIHRpbWUsIHN1YnByb2Nlc3MsIHJlLCBqc29uLCByZXF1ZXN0cwoKQk9UX0NPTkYgPSAnL2V0Yy9yYXJldHJpY2Nrcy9ib3QuY29uZicKQURNSU5fSURTX0ZJTEUgPSAnL2V0Yy9yYXJldHJpY2Nrcy9hZG1pbl9pZHMuY29uZicKVVNFUl9ESVIgPSAnL2V0Yy9yYXJldHJpY2Nrcy91c2VycycKRE9NQUlOX0ZJTEUgPSAnL2V0Yy9yYXJldHJpY2Nrcy9kb21haW4uY29uZicKQkFOTkVSX0ZJTEUgPSAnL2V0Yy9pc3N1ZS5uZXQnClNUQVRFX0RJUiA9ICcvZXRjL3JhcmV0cmljY2tzL2JvdF9zdGF0ZXMnCgpvcy5tYWtlZGlycyhTVEFURV9ESVIsIGV4aXN0X29rPVRydWUpCgpkZWYgZ2V0X3Rva2VuKCk6CiAgICBpZiBvcy5wYXRoLmV4aXN0cyhCT1RfQ09ORik6CiAgICAgICAgd2l0aCBvcGVuKEJPVF9DT05GLCAncicpIGFzIGY6CiAgICAgICAgICAgIHJldHVybiBmLnJlYWQoKS5zdHJpcCgpCiAgICByZXR1cm4gTm9uZQo=" | base64 -d > /usr/local/bin/tgbot.py
    chmod +x /usr/local/bin/tgbot.py
}

install_telegram_bot
echo -e "${GREEN}RareTriccks VPN Panel Installed Successfully```{NC}"
