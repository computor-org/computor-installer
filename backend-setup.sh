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

# Hilfsfunktionen
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

if [[ -z "$DOMAIN" || -z "$ADMIN_EMAIL" ]]; then
    echo "Fehler: Domain (-u) und Email (-m) erforderlich!"
    exit 1
fi

# 1. Repo klonen
if ! command -v git &> /dev/null; then apt-get update && apt-get install -y git; fi
if [ ! -d "$BACKEND_DIR" ]; then
    git clone https://github.com/computor-org/computor-backend.git "$BACKEND_DIR"
fi
cd "$BACKEND_DIR"

# 2. .env erstellen & konfigurieren
cp "$TEMPLATE_PATH" .env
update_env() { sed -i "s|^$1=.*|$1=$2|g" .env; }

log "Konfiguriere Passwörter und Secrets..."
# (Hier alle update_env Aufrufe wie zuvor...)
update_env "POSTGRES_PASSWORD" "$(gen_pass)"
update_env "API_ADMIN_PASSWORD" "$(gen_pass)"
update_env "TOKEN_SECRET" "$(gen_base64)"
update_env "AUTH_SECRET" "$(gen_base64)"
update_env "API_URL" "https://${DOMAIN}"
update_env "NEXT_PUBLIC_API_URL" "https://${DOMAIN}"
update_env "CODER_URL" "https://$(echo $DOMAIN | sed 's/api\./coder\./')"
update_env "MATLAB_TESTING_WORKER_REPLICAS" "0"

# ==========================================================================
# 3. DER FIX: DOCKER-COMPOSE & DOCKERFILES REINIGEN
# ==========================================================================
log "Bereinige Docker-Konfiguration für Debian 13..."

# Schritt A: Entferne den fehlerhaften MATLAB-Dienst komplett aus der YAML
# Wir löschen den Block von 'temporal-worker-matlab:' bis zum nächsten Service
sed -i '/temporal-worker-matlab:/,/^[[:space:]]*[a-zA-Z0-9_-]*:$/{/^[[:space:]]*[a-zA-Z0-9_-]*:$/!d}' docker-compose.yml
# (Zusatz-Fix falls die Formatierung leicht anders ist)
sed -i '/temporal-worker-matlab:/,+15d' docker-compose.yml 2>/dev/null || true

# Schritt B: Alle Python 3.10 Referenzen durch Standard-Python 3 ersetzen
# Debian 13 hat kein 3.10 Paket, aber 3.11/3.12 (als "python3")
log "Patsche Python-Versionen in Dockerfiles..."
find . -name "Dockerfile*" -type f -exec sed -i 's/python3\.10/python3/g' {} +
find . -name "Dockerfile*" -type f -exec sed -i 's/libpython3\.10-dev/libpython3-dev/g' {} +
find . -name "Dockerfile*" -type f -exec sed -i 's/python3\.10-venv/python3-venv/g' {} +

# ==========================================================================

# 4. Nginx Proxy (wie zuvor)
if [ "$CONFIGURE_NGINX" = true ]; then
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

# 5. Starten
log "Starte Build..."
chmod +x startup.sh
./startup.sh prod --build

success "Backend erfolgreich gestartet!"
