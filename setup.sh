#!/bin/bash
# ==========================================================================
# Computor Backend Master Setup Script
# ==========================================================================
set -e

GITHUB_ORG="computor-org"
SERVER_REPO="computor-installer"
BRANCH="main"
RAW_BASE_URL="https://github.com/$GITHUB_ORG/$SERVER_REPO/$BRANCH"
INSTALL_BASE_DIR="/opt/computor"

# Farben
BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

fetch_script() {
    local script_name=$1
    log "Lade $script_name von GitHub..."
    curl -sSL "$RAW_BASE_URL/$script_name" -o "$script_name" || log "Warnung: $script_name fehlt."
    [ -f "$script_name" ] && chmod +x "$script_name"
}

# Parameter
DOMAIN=""
EMAIL=""
ADMIN_PASS="admin123"

while getopts "d:m:p:gch" opt; do
    case $opt in
        d) DOMAIN="$OPTARG" ;;
        m) EMAIL="$OPTARG" ;;
        p) ADMIN_PASS="$OPTARG" ;;
        g) INSTALL_GITLAB=true ;;
        c) INSTALL_CODER=true ;;
        h) echo "Usage: setup.sh -d domain.at -m mail@domain.at [-p pass] [-g] [-c]"; exit 0 ;;
    esac
done

if [[ -z "$DOMAIN" ]]; then error "Domain (-d) erforderlich!"; fi

mkdir -p "$INSTALL_BASE_DIR"
cd "$INSTALL_BASE_DIR"

# 1. Scripte holen
fetch_script "certify.sh"
fetch_script "gitlab-setup.sh"
fetch_script "coder-setup.sh"

# 2. System-Vorbereitung (Einmalig für alle)
log "Bereite System vor (Docker & Nginx)..."
apt-get update && apt-get install -y curl nginx
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com | sh
fi

# 3. GitLab (wenn gewünscht)
if [ "$INSTALL_GITLAB" = true ]; then
    ./gitlab-setup.sh -u "git.$DOMAIN" -p 8080 -s "$ADMIN_PASS" -w
    ./certify.sh -d "git.$DOMAIN" -m "$EMAIL"
fi

# 4. Coder (wenn gewünscht)
if [ "$INSTALL_CODER" = true ]; then
    ./coder-setup.sh -u "coder.$DOMAIN" -p 7080 -d "$INSTALL_BASE_DIR/coder" -w
    ./certify.sh -d "coder.$DOMAIN" -m "$EMAIL"
fi

success "Alles erledigt!"
