#!/bin/bash
set -e

BACKEND_DIR="/opt/computor/backend"
TEMPLATE_PATH="ops/environments/.env.common.template"
DOMAIN=""
ADMIN_EMAIL=""
CONFIGURE_NGINX=false

BLUE='\033[0;34m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

log() { echo -e "${BLUE}[BACKEND]${NC} $1"; }

# Hilfsfunktionen für Passwörter
gen_pass() { openssl rand -base64 48 | tr -d '+/=' | head -c 24; }
gen_hex()  { openssl rand -hex 32; }
gen_base64() { openssl rand -base64 32; }

while getopts "u:m:wg" opt; do
  case $opt in
    u) DOMAIN="$OPTARG" ;;
    m) ADMIN_EMAIL="$OPTARG" ;;
    w) CONFIGURE_NGINX=true ;;
  esac
done

# 1. Repo klonen
if ! command -v git &> /dev/null; then apt-get update && apt-get install -y git; fi
if [ ! -d "$BACKEND_DIR" ]; then
    git clone https://github.com/computor-org/computor-backend.git "$BACKEND_DIR"
fi
cd "$BACKEND_DIR"

# 2. .env erstellen & konfigurieren
cp "$TEMPLATE_PATH" .env
update_env() { sed -i "s|^$1=.*|$1=$2|g" .env; }

log "Konfiguriere .env..."
update_env "POSTGRES_PASSWORD" "$(gen_pass)"
update_env "API_ADMIN_PASSWORD" "$(gen_pass)"
update_env "TOKEN_SECRET" "$(gen_base64)"
update_env "AUTH_SECRET" "$(gen_base64)"
update_env "API_URL" "https://${DOMAIN}"
update_env "NEXT_PUBLIC_API_URL" "https://${DOMAIN}"
update_env "CODER_URL" "https://$(echo $DOMAIN | sed 's/api\./coder\./')"
update_env "MATLAB_TESTING_WORKER_REPLICAS" "0"

# ==========================================================================
# 3. DER FIX: DATEIEN IM OPS-ORDNER PATCHEN (BEVOR STARTUP.SH LÄUFT)
# ==========================================================================
log "Bereine YAML-Dateien in ops/docker/ für Debian 13..."

# Schritt A: MATLAB-Dienst aus den Docker-Compose Dateien entfernen
# Wir suchen in allen YAML-Dateien im ops-Ordner nach dem matlab-worker und löschen den Block
find ops/docker/ -name "*.yaml" -type f -exec sed -i '/temporal-worker-matlab:/,+15d' {} +
log "✓ MATLAB-Dienste aus YAML-Dateien entfernt."

# Schritt B: Dockerfiles patchen (Python 3.10 -> Python 3)
# Da Debian 13 kein python3.10 hat, müssen wir die Dockerfiles im Repo anpassen
log "Patsche Dockerfiles von python3.10 auf python3..."
find . -name "Dockerfile*" -type f -exec sed -i 's/python3\.10/python3/g' {} +
find . -name "Dockerfile*" -type f -exec sed -i 's/libpython3\.10-dev/libpython3-dev/g' {} +
find . -name "Dockerfile*" -type f -exec sed -i 's/python3\.10-venv/python3-venv/g' {} +
log "✓ Python-Versionen in Dockerfiles angepasst."

# ==========================================================================

# 4. Nginx Proxy (wie gehabt)
if [ "$CONFIGURE_NGINX" = true ]; then
  log "Konfiguriere Nginx..."
  cat <<EOF > /etc/nginx/sites-available/backend.conf
server {
    listen 80; listen [::]:80;
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

# 5. Starten (jetzt wird startup.sh die modifizierten YAMLs finden)
log "Starte Build & Deploy via startup.sh..."
chmod +x startup.sh
./startup.sh prod --build -d

echo -e "\n${GREEN}Backend erfolgreich auf Debian 13 gestartet!${NC}"
