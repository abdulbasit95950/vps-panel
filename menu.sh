#!/bin/bash

# =======================================================
# Script Name : RareTriccks VPN Panel (Encrypted Bot)
# =======================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

PANEL_NAME="RareTriccks VPN Panel"

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}[ERROR] Veh script ROOT privilege ke sath chalaen! (sudo -i)${NC}"
   exit 1
fi

install_telegram_bot() {
    # Decrypt and write tgbot.py automatically on VPS
    echo "aW1wb3J0IG9zLCBzeXMsIHRpbWUsIHN1YnByb2Nlc3MsIHJlLCBqc29uLCByZXF1ZXN0cwoKQk9UX0NPTkYgPSAnL2V0Yy9yYXJldHJpY2Nrcy9ib3QuY29uZicKQURNSU5fSURTX0ZJTEUgPSAnL2V0Yy9yYXJldHJpY2Nrcy9hZG1pbl9pZHMuY29uZicKVVNFUl9ESVIgPSAnL2V0Yy9yYXJldHJpY2Nrcy91c2VycycKRE9NQUlOX0ZJTEUgPSAnL2V0Yy9yYXJldHJpY2Nrcy9kb21haW4uY29uZicKQkFOTkVSX0ZJTEUgPSAnL2V0Yy9pc3N1ZS5uZXQnClNUQVRFX0RJUiA9ICcvZXRjL3JhcmV0cmljY2tzL2JvdF9zdGF0ZXMnCgpvcy5tYWtlZGlycyhTVEFURV9ESVIsIGV4aXN0X29rPVRydWUpCgpkZWYgZ2V0X3Rva2VuKCk6CiAgICBpZiBvcy5wYXRoLmV4aXN0cyhCT1RfQ09ORik6CiAgICAgICAgd2l0aCBvcGVuKEJPVF9DT05GLCAncicpIGFzIGY6CiAgICAgICAgICAgIHJldHVybiBmLnJlYWQoKS5zdHJpcCgpCiAgICByZXR1cm4gTm9uZQo=" | base64 -d > /usr/local/bin/tgbot.py
    chmod +x /usr/local/bin/tgbot.py
}

install_telegram_bot
