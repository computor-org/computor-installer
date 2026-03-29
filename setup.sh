#!/bin/bash
# ==========================================================================
# Computor Backend Master Setup Script (mit Status-Report)
# ==========================================================================

# Wir entfernen set -e, damit das Skript bei Fehlern nicht sofort stoppt!

GITHUB_ORG="computor-org"
SERVER_REPO="computor-installer"
BRANCH="main"
RAW_BASE_URL="raw.githubusercontent.com/$GITHUB_ORG/$SERVER_REPO/$BRANCH"
INSTALL_BASE_DIR="/opt/computor"

# Farben
BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; } # exit 1 entfernt

# Status-Variablen (Default: Übersprungen)
STATUS_PREP="⏩ Übersprungen"
STATUS_GITLAB="⏩ Übersprungen"
STATUS_GITLAB_SSL="⏩ Übersprungen"
STATUS_CODER="⏩ Übersprungen"
STATUS_CODER_SSL="⏩ Übersprungen"

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

if [[ -z "$DOMAIN" ]]; then
    echo -e "${RED}Fehler: Domain (-d) erforderlich!${NC}"
    exit 1
fi

mkdir -p "$INSTALL_BASE_DIR"
cd "$INSTALL_BASE_DIR"

# 1. Scripte holen
fetch_script "certify.sh"
fetch_script "gitlab-setup.sh"
fetch_script "coder-setup.sh"

# 2. System-Vorbereitung
log "Bereite System vor (Docker & Nginx)..."
if apt-get update && apt-get install -y curl nginx; then
    # Docker Check/Install
    if ! command -v docker &> /dev/null; then
        curl -fsSL https://get.docker.com | sh && STATUS_PREP="✅ Erfolgreich" || STATUS_PREP="❌ Docker Fehler"
    else
        STATUS_PREP="✅ Erfolgreich (bereits installiert)"
    fi
    # Nginx Default Seite entfernen (verhindert oft SSL Fehler)
    rm -f /etc/nginx/sites-enabled/default && systemctl restart nginx || true
else
    STATUS_PREP="❌ System-Update fehlgeschlagen"
fi

# 3. GitLab
if [ "$INSTALL_GITLAB" = true ]; then
    log "Installiere GitLab..."
    if ./gitlab-setup.sh -u "git.$DOMAIN" -p 8080 -s "$ADMIN_PASS" -w; then
        STATUS_GITLAB="✅ Erfolgreich"
        log "Starte SSL-Zertifizierung für GitLab..."
        if ./certify.sh -d "git.$DOMAIN" -m "$EMAIL"; then
            STATUS_GITLAB_SSL="✅ Erfolgreich"
        else
            STATUS_GITLAB_SSL="❌ Fehlgeschlagen (DNS/IPv6 prüfen!)"
        fi
    else
        STATUS_GITLAB="❌ Fehlgeschlagen"
    fi
fi

# 4. Coder
if [ "$INSTALL_CODER" = true ]; then
    log "Installiere Coder..."
    if ./coder-setup.sh -u "coder.$DOMAIN" -p 7080 -d "$INSTALL_BASE_DIR/coder" -m "$EMAIL" -s "$ADMIN_PASS" -w; then
        STATUS_CODER="✅ Erfolgreich"
        log "Starte SSL-Zertifizierung für Coder..."
        if ./certify.sh -d "coder.$DOMAIN" -m "$EMAIL"; then
            STATUS_CODER_SSL="✅ Erfolgreich"
        else
            STATUS_CODER_SSL="❌ Fehlgeschlagen (DNS/IPv6 prüfen!)"
        fi
    else
        STATUS_CODER="❌ Fehlgeschlagen"
    fi
fi

# ==========================================================================
# FINALER STATUS REPORT
# ==========================================================================
echo -e "\n${BLUE}==================================================${NC}"
echo -e "${YELLOW}           INSTALLATIONS-ZUSAMMENFASSUNG${NC}"
echo -e "${BLUE}==================================================${NC}"
echo -e "System-Vorbereitung:   $STATUS_PREP"
echo -e "GitLab App:            $STATUS_GITLAB"
echo -e "GitLab SSL (HTTPS):    $STATUS_GITLAB_SSL"
echo -e "Coder App:             $STATUS_CODER"
echo -e "Coder SSL (HTTPS):     $STATUS_CODER_SSL"
echo -e "${BLUE}==================================================${NC}"

if [[ "$STATUS_GITLAB_SSL" == *"❌"* || "$STATUS_CODER_SSL" == *"❌"* ]]; then
    echo -e "${RED}HINWEIS:${NC} SSL-Fehler liegen meist an IPv6 (AAAA-Records) im DNS."
    echo -e "Bitte AAAA-Records löschen und ./certify.sh manuell starten."
fi

success "Skript-Durchlauf beendet!"
