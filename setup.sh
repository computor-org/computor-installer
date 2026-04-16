#!/bin/bash
# ==========================================================================
# Computor Backend Master Setup Script (mit Skip-SSL Option)
# ==========================================================================

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
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Status-Variablen
STATUS_PREP="⏩ Übersprungen"
STATUS_GITLAB="⏩ Übersprungen"
STATUS_GITLAB_SSL="⏩ Übersprungen"
STATUS_CODER="⏩ Übersprungen"
STATUS_CODER_SSL="⏩ Übersprungen"
STATUS_BACKEND="⏩ Übersprungen"

# NEU: Variable für SSL-Skip
SKIP_SSL=false

fetch_script() {
    local script_name=$1
    log "Lade $script_name von GitHub..."
    curl -sSL "$RAW_BASE_URL/$script_name" -o "$script_name" || log "Warnung: $script_name fehlt."
    [ -f "$script_name" ] && chmod +x "$script_name"
}

# Parameter (JETZT MIT 'n' für No-SSL)
while getopts "d:m:p:gcbnh" opt; do
    case $opt in
        d) DOMAIN="$OPTARG" ;;
        m) EMAIL="$OPTARG" ;;
        p) ADMIN_PASS="$OPTARG" ;;
        g) INSTALL_GITLAB=true ;;
        c) INSTALL_CODER=true ;;
        b) INSTALL_BACKEND=true ;;
        n) SKIP_SSL=true ;; # NEU: SSL überspringen
        h) echo "Usage: setup.sh -d domain.at -m mail@domain.at [-p pass] [-g] [-c] [-b] [-n]"; exit 0 ;;
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
fetch_script "backend-setup.sh"

# 2. System-Vorbereitung
log "Bereite System vor (Docker, Nginx & Git)..."
if apt-get update && apt-get install -y curl nginx git; then
    if ! command -v docker &> /dev/null; then
        curl -fsSL https://get.docker.com | sh && STATUS_PREP="✅ Erfolgreich" || STATUS_PREP="❌ Docker Fehler"
    else
        STATUS_PREP="✅ Erfolgreich (bereits installiert)"
    fi
    rm -f /etc/nginx/sites-enabled/default && systemctl restart nginx || true
else
    STATUS_PREP="❌ System-Update fehlgeschlagen"
fi

# 3. GitLab
if [ "$INSTALL_GITLAB" = true ]; then
    log "Installiere GitLab..."
    if ./gitlab-setup.sh -u "git.$DOMAIN" -p 9080 -s "$ADMIN_PASS" -w; then
        STATUS_GITLAB="✅ Erfolgreich"
        if [ "$SKIP_SSL" = false ]; then
            log "Starte SSL-Zertifizierung für GitLab..."
            ./certify.sh -d "git.$DOMAIN" -m "$EMAIL" && STATUS_GITLAB_SSL="✅ Erfolgreich" || STATUS_GITLAB_SSL="❌ Fehler"
        else
            STATUS_GITLAB_SSL="⏩ Übersprungen (-n)"
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
        if [ "$SKIP_SSL" = false ]; then
            log "Starte SSL-Zertifizierung für Coder..."
            ./certify.sh -d "coder.$DOMAIN" -m "$EMAIL" && STATUS_CODER_SSL="✅ Erfolgreich" || STATUS_CODER_SSL="❌ Fehler"
        else
            STATUS_CODER_SSL="⏩ Übersprungen (-n)"
        fi
    else
        STATUS_CODER="❌ Fehlgeschlagen"
    fi
fi

# 5. Backend
if [ "$INSTALL_BACKEND" = true ]; then
    log "Installiere Computor Backend..."
    if ./backend-setup.sh -u "code.$DOMAIN" -m "$EMAIL" -w; then
        STATUS_BACKEND="✅ Erfolgreich"
        if [ "$SKIP_SSL" = false ]; then
            ./certify.sh -d "code.$DOMAIN" -m "$EMAIL"
        fi
    else
        STATUS_BACKEND="❌ Fehlgeschlagen"
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
echo -e "Backend:               $STATUS_BACKEND"
echo -e "${BLUE}==================================================${NC}"

if [ "$SKIP_SSL" = true ]; then
    echo -e "${YELLOW}HINWEIS:${NC} SSL wurde übersprungen. Zugriff aktuell nur über HTTP möglich."
fi

success "Skript-Durchlauf beendet!"
