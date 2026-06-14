#!/bin/bash
set -e

BACKEND_DIR="/opt/computor/backend"
TEMPLATE_PATH="ops/environments/.env.common.template"
DOMAIN=""
ADMIN_EMAIL=""
API_ADMIN_PASS=""
CONFIGURE_NGINX=false

BLUE='\033[0;34m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

log() { echo -e "${BLUE}[BACKEND]${NC} $1"; }

gen_pass() { openssl rand -base64 48 | tr -d '+/=' | head -c 24; }
gen_hex()  { openssl rand -hex 32; }
gen_base64() { openssl rand -base64 32; }

while getopts "u:m:s:wg" opt; do
  case $opt in
    u) DOMAIN="$OPTARG" ;;
    m) ADMIN_EMAIL="$OPTARG" ;;
    s) API_ADMIN_PASS="$OPTARG" ;;
    w) CONFIGURE_NGINX=true ;;
  esac
done

if [ -z "$API_ADMIN_PASS" ]; then API_ADMIN_PASS=$(gen_pass); fi

# 1. Repository frisch klonen (Tabula Rasa)
if [ -d "$BACKEND_DIR" ]; then rm -rf "$BACKEND_DIR"; fi
log "Klone Repository"
git clone -b release/2026.10 https://github.com/computor-org/computor-backend.git "$BACKEND_DIR"
cd "$BACKEND_DIR"

# 2. .env erstellen (mit Auto-Erkennung von Maximilians neuem setup-env.sh)
log "Konfiguriere Umgebungsvariablen (.env)..."

# Suchen nach Maximilians setup-env.sh im geklonten Repository
ENV_SCRIPT=""
if [ -f "./setup-env.sh" ]; then
    ENV_SCRIPT="./setup-env.sh"
elif [ -f "./ops/scripts/setup-env.sh" ]; then
    ENV_SCRIPT="./ops/scripts/setup-env.sh"
elif [ -f "./ops/environments/setup-env.sh" ]; then
    ENV_SCRIPT="./ops/environments/setup-env.sh"
fi

if [ -n "$ENV_SCRIPT" ]; then
    log "Gefunden: $ENV_SCRIPT. Führe automatische Basis-Konfiguration aus..."
    chmod +x "$ENV_SCRIPT"

    # --auto konfiguriert Defaults ohne Prompts, --force erzwingt das Überschreiben der .env.common
    # Dies erzeugt alle kryptografischen Schlüssel für Keycloak, Temporal etc.
    ./"$ENV_SCRIPT" --auto --force

    log "Passe erzeugte .env an Produktion an für Domain: $DOMAIN..."
    update_env() {
        # Wir nutzen | als Trenner, damit Sonderzeichen in Emails (@) oder Secrets nicht stören
        sed -i "s|^$1=.*|$1=$2|g" .env
    }

    # 2.1. Globale Produktionseinstellungen erzwingen
    update_env "DEBUG_MODE" "production"
    update_env "DISABLE_API_DEBUG_INFO" "true"
    update_env "TEMPORAL_WORKER_REPLICAS" "2"
    update_env "TESTING_WORKER_REPLICAS" "2"
    update_env "API_URL" "http://uvicorn:8000"
    update_env "PUBLIC_DOMAIN" "https://${DOMAIN}"
    update_env "NEXT_PUBLIC_API_URL" ""

    # 2.2. Keycloak Einstellungen für Produktion
    update_env "KEYCLOAK_TRAEFIK_ENABLED" "true"
    update_env "KEYCLOAK_HTTP_RELATIVE_PATH" "/auth"
    update_env "KEYCLOAK_PUBLIC_URL" ""

    # 2.3. Coder & Backend Pfade
    update_env "CODER_URL" "http://coder:7080"
    update_env "BACKEND_EXTERNAL_URL" "http://localhost:8080/api"

    # 2.4. Custom-Zugangsdaten eintragen
    update_env "API_ADMIN_PASSWORD" "$API_ADMIN_PASS"
    update_env "KEYCLOAK_ADMIN_PASSWORD" "$API_ADMIN_PASS"
    update_env "CODER_ADMIN_EMAIL" "$ADMIN_EMAIL"
    update_env "KEYCLOAK_SERVER_URL_INTERNAL" "http://computor-keycloak:8080/auth"

    # 2.5. Coder und Forgejo (Git Server) aktivieren und konfigurieren
    update_env "CODER_ENABLED" "true"
    update_env "GIT_SERVER" "forgejo"
    update_env "GIT_SERVER_ADMIN_PASSWORD" "$API_ADMIN_PASS"
    update_env "FORGEJO_TRAEFIK_ENABLED" "true"
    update_env "FORGEJO_DOMAIN" ""
    update_env "FORGEJO_ROOT_URL" ""

else
    log "setup-env.sh nicht gefunden. Verwende manuelles Fallback für .env..."
    if [ -f "$TEMPLATE_PATH" ]; then
        cp "$TEMPLATE_PATH" .env
        update_env() {
            sed -i "s|^$1=.*|$1=$2|g" .env
        }

        update_env "POSTGRES_PASSWORD" "$(gen_pass)"
        update_env "REDIS_PASSWORD" "$(gen_pass)"
        update_env "API_ADMIN_PASSWORD" "$API_ADMIN_PASS"
        update_env "CODER_ADMIN_PASSWORD" "$API_ADMIN_PASS"
        update_env "CODER_ADMIN_EMAIL" "$ADMIN_EMAIL"
        update_env "TOKEN_SECRET" "$(gen_base64)"
        update_env "AUTH_SECRET" "$(gen_base64)"
        update_env "CODER_ADMIN_API_SECRET" "$(gen_hex)"
        update_env "CODER_ENABLED" "true"
        update_env "CODER_URL" "http://computor-coder:7080"
        update_env "API_URL" "https://${DOMAIN}/api"
        update_env "NEXT_PUBLIC_API_URL" "https://${DOMAIN}/api"
        update_env "CODER_WORKSPACE_BASE_URL" "https://${DOMAIN}/coder"
        update_env "DOCKER_GID" "$(getent group docker | cut -d: -f3 || echo 999)"
        update_env "MATLAB_TESTING_WORKER_REPLICAS" "0"
    else
        log "Fehler: Weder setup-env.sh noch $TEMPLATE_PATH wurden gefunden!"
        exit 1
    fi
fi

mkdir -p /opt/computor/shared

# ==========================================================================
# 3. DIE ENTSCHEIDENDEN FIXES (ROUTING, DEBIAN 13, CODER)
# ==========================================================================
log "Patsche Konfigurationen für Debian 13 und Routing-Priorität..."

# Schritt A: MATLAB-Dienst entfernen (Verhindert Build-Abbruch)
if [ -f "ops/docker/docker-compose.prod.yaml" ]; then
    python3 - <<EOF || log "Warnung: MATLAB-Patch konnte nicht angewendet werden (evtl. bereits entfernt)."
import re
file_path = 'ops/docker/docker-compose.prod.yaml'
with open(file_path, 'r') as f:
    content = f.read()

# Match the service block starting with '  temporal-worker-matlab:' and ending before the next service block
new_content = re.sub(r'\n\s*# MATLAB Testing Worker\n\s*temporal-worker-matlab:[\s\S]*?(?=\n\n|\n\s*#)', '', content)

with open(file_path, 'w') as f:
    f.write(new_content)
EOF
else
    log "Hinweis: ops/docker/docker-compose.prod.yaml nicht gefunden. Überspringe MATLAB-Patch."
fi

# Schritt D: Python 3.10 -> Python 3 Fix (Debian Trixie/13 Support)
find . -name "Dockerfile*" -exec sed -i 's/python3\.10/python3/g' {} + || true
find . -name "Dockerfile*" -exec sed -i 's/libpython3\.10-dev/libpython3-dev/g' {} + || true

# ==========================================================================

# 4. NGINX
if [ "$CONFIGURE_NGINX" = true ]; then
  log "Erstelle Nginx Konfiguration für $DOMAIN..."
  cat <<EOF > /etc/nginx/sites-available/${DOMAIN}.conf
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};
    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
  ln -sf /etc/nginx/sites-available/${DOMAIN}.conf /etc/nginx/sites-enabled/
  nginx -t && systemctl restart nginx
fi

# 5. Starten
log "Starte Build & Deploy via startup.sh..."
chmod +x startup.sh
./startup.sh prod --build -d

# 6. STATUS REPORT
echo -e "\n${GREEN}==================================================${NC}"
echo -e "${GREEN}      ZUGANGSDATEN COMPUTOR BACKEND${NC}"
echo -e "${GREEN}==================================================${NC}"
echo -e "Backend URL:   https://$DOMAIN"
echo -e "Admin User:    admin"
echo -e "Admin Pass:    ${YELLOW}$API_ADMIN_PASS${NC}"
echo -e "--------------------------------------------------"
echo -e "Coder Admin:   $ADMIN_EMAIL"
echo -e "==================================================${NC}"
