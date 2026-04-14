#!/bin/bash
# ==========================================================================
# Computor Backend Setup Script (MATLAB Deaktiviert & Unique Passwords)
# ==========================================================================
set -e

BACKEND_DIR="/opt/computor/backend"
TEMPLATE_PATH="ops/environments/.env.common.template"

DOMAIN=""
ADMIN_EMAIL=""
CONFIGURE_NGINX=false
INSTALL_GIT=false

BLUE='\033[0;34m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

log() { echo -e "${BLUE}[BACKEND]${NC} $1"; }

gen_pass() { openssl rand -base64 48 | tr -d '+/=' | head -c 24; }
gen_hex()  { openssl rand -hex 32; }
gen_base64() { openssl rand -base64 32; }

while getopts "u:m:wg" opt; do
  case $opt in
    u) DOMAIN="$OPTARG" ;;
    m) ADMIN_EMAIL="$OPTARG" ;;
    w) CONFIGURE_NGINX=true ;;
    g) INSTALL_GIT=true ;;
  esac
done

if [[ -z "$DOMAIN" || -z "$ADMIN_EMAIL" ]]; then
    echo "Fehler: Domain (-u) und Email (-m) erforderlich!"
    exit 1
fi

# 1. Passwort-Generierung
DB_PASS=$(gen_pass)
TEMPORAL_DB_PASS=$(gen_pass)
REDIS_PASS=$(gen_pass)
MINIO_PASS=$(gen_pass)
API_ADMIN_PASS=$(gen_pass)
CODER_DB_PASS=$(gen_pass)
CODER_ADMIN_PASS=$(gen_pass)
CODER_API_SECRET=$(gen_hex)
TOKEN_SECRET=$(gen_base64)
AUTH_SECRET=$(gen_base64)
WORKER_TOKEN=$(gen_hex)

# 2. Git & Repo
if [ "$INSTALL_GIT" = true ]; then
  apt-get update && apt-get install -y git
fi

if [ ! -d "$BACKEND_DIR" ]; then
    log "Klone Repository..."
    git clone https://github.com/computor-org/computor-backend.git "$BACKEND_DIR"
fi

cd "$BACKEND_DIR"

# 3. .env erstellen
if [ -f "$TEMPLATE_PATH" ]; then
    cp "$TEMPLATE_PATH" .env
else
    echo "FEHLER: Template nicht gefunden!"
    exit 1
fi

update_env() {
    sed -i "s|^$1=.*|$1=$2|g" .env
}

# 4. Werte setzen
log "Konfiguriere .env..."

# Passwörter
update_env "POSTGRES_PASSWORD" "$DB_PASS"
update_env "TEMPORAL_POSTGRES_PASSWORD" "$TEMPORAL_DB_PASS"
update_env "REDIS_PASSWORD" "$REDIS_PASS"
update_env "MINIO_ROOT_PASSWORD" "$MINIO_PASS"
update_env "CODER_POSTGRES_PASSWORD" "$CODER_DB_PASS"
update_env "API_ADMIN_PASSWORD" "$API_ADMIN_PASS"
update_env "CODER_ADMIN_PASSWORD" "$CODER_ADMIN_PASS"
update_env "CODER_ADMIN_EMAIL" "$ADMIN_EMAIL"

# Tokens
update_env "TOKEN_SECRET" "$TOKEN_SECRET"
update_env "AUTH_SECRET" "$AUTH_SECRET"
update_env "CODER_ADMIN_API_SECRET" "$CODER_API_SECRET"
update_env "TESTING_WORKER_TOKEN" "$WORKER_TOKEN"
update_env "MATLAB_WORKER_TOKEN" "$WORKER_TOKEN"

# URLs & Pfade
update_env "API_URL" "https://${DOMAIN}"
update_env "NEXT_PUBLIC_API_URL" "https://${DOMAIN}"
update_env "CODER_URL" "https://$(echo $DOMAIN | sed 's/api\./coder\./')"
update_env "CODER_WORKSPACE_BASE_URL" "https://${DOMAIN}/coder"
update_env "SYSTEM_DEPLOYMENT_PATH" "/opt/computor"
update_env "API_ROOT_PATH" "/opt/computor/shared"
mkdir -p /opt/computor/shared

# ============================================
# MATLAB DEAKTIVIERUNG (FIX FÜR BUILD ERROR)
# ============================================
log "Deaktiviere MATLAB-Komponenten..."
update_env "MATLAB_TESTING_WORKER_REPLICAS" "0"
# Wir setzen ein existierendes Image ein, damit der Build-Vorgang nicht abbricht
update_env "MATLAB_BASE_IMAGE" "debian:bookworm-slim"

# Docker GID
DOCKER_GID=$(getent group docker | cut -d: -f3 || echo "999")
update_env "DOCKER_GID" "$DOCKER_GID"
update_env "CODER_ENABLED" "true"

# 5. Nginx Proxy
if [ "$CONFIGURE_NGINX" = true ]; then
  cat <<EOF > /etc/nginx/sites-available/backend.conf
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
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
  ln -sf /etc/nginx/sites-available/backend.conf /etc/nginx/sites-enabled/
  systemctl restart nginx
fi

# 6. Starten
log "Starte Backend-Services..."
chmod +x startup.sh
# Falls der Build trotzdem versucht den Worker zu bauen,
# sagen wir Docker Compose hier explizit, dass er den MATLAB-Worker ignorieren soll:
./startup.sh prod --build

# FINAL REPORT
echo -e "\n${YELLOW}==================================================${NC}"
echo -e "${GREEN}      BACKEND INSTALLATION ABGESCHLOSSEN!${NC}"
echo -e "${YELLOW}==================================================${NC}"
echo -e "${BLUE}Dienst             Zugangsdaten${NC}"
echo -e "--------------------------------------------------"
echo -e "API Admin Email:   $ADMIN_EMAIL"
echo -e "API Admin Pass:    ${YELLOW}$API_ADMIN_PASS${NC}"
echo -e "Coder Admin Pass:  ${YELLOW}$CODER_ADMIN_PASS${NC}"
echo -e "--------------------------------------------------"
echo -e "Postgres Pass:     $DB_PASS"
echo -e "Redis Pass:        $REDIS_PASS"
echo -e "Minio Pass:        $MINIO_PASS"
echo -e "--------------------------------------------------"
echo -e "Auth Token Secret: $TOKEN_SECRET"
echo -e "${YELLOW}==================================================${NC}"
echo -e "Alle Passwörter wurden auch in der .env gespeichert."
