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

# 1. Repo klonen
if ! command -v git &> /dev/null; then apt-get update && apt-get install -y git; fi
if [ ! -d "$BACKEND_DIR" ]; then
    log "Klone Repository..."
    git clone https://github.com/computor-org/computor-backend.git "$BACKEND_DIR"
fi
cd "$BACKEND_DIR"

# 2. .env erstellen
cp "$TEMPLATE_PATH" .env

update_env() {
    # Wir nutzen '|' als Trenner für Email-Sicherheit
    sed -i "s|^$1=.*|$1=$2|g" .env
}

log "Konfiguriere .env..."
update_env "POSTGRES_PASSWORD" "$(gen_pass)"
update_env "REDIS_PASSWORD" "$(gen_pass)"
update_env "API_ADMIN_PASSWORD" "$API_ADMIN_PASS"
update_env "CODER_ADMIN_PASSWORD" "$API_ADMIN_PASS"
update_env "CODER_ADMIN_EMAIL" "$ADMIN_EMAIL"
update_env "TOKEN_SECRET" "$(gen_base64)"
update_env "AUTH_SECRET" "$(gen_base64)"
update_env "CODER_ADMIN_API_SECRET" "$(gen_hex)"
update_env "CODER_ENABLED" "true"

# WICHTIG: Interne Docker-URL verwenden, um SSL-Verifikationsfehler zu vermeiden!
update_env "CODER_URL" "http://computor-coder:7080"

update_env "API_URL" "https://${DOMAIN}"
update_env "NEXT_PUBLIC_API_URL" "https://${DOMAIN}"
update_env "CODER_WORKSPACE_BASE_URL" "https://${DOMAIN}/coder"
update_env "DOCKER_GID" "$(getent group docker | cut -d: -f3 || echo 999)"
update_env "MATLAB_TESTING_WORKER_REPLICAS" "0"

log "Bereine Konfiguration und patsche Dockerfiles..."

# Schritt A: MATLAB-Dienst sauber aus allen YAMLs entfernen
python3 -c '
import os
def clean(f):
    if not os.path.exists(f): return
    with open(f,"r") as r: lines=r.readlines()
    with open(f,"w") as w:
        skip=False
        for l in lines:
            if "temporal-worker-matlab:" in l: skip=True; continue
            if skip and l.strip() and not l.startswith("    "): skip=False
            if not skip: w.write(l)
for r, d, fs in os.walk("ops/docker"):
    for f in fs: clean(os.path.join(r, f))
'

# Schritt B: Python 3.10 -> Python 3 Fix (Debian 13)
find . -name "Dockerfile*" -exec sed -i 's/python3\.10/python3/g' {} +
find . -name "Dockerfile*" -exec sed -i 's/libpython3\.10-dev/libpython3-dev/g' {} +

# Schritt C: Coder-CLI Installation fixen (Binary statt Script)
find . -name "Dockerfile*" -type f -exec sed -i 's|curl -fsSL https://coder.com/install.sh \| sh|curl -fsSL https://github.com/coder/coder/releases/download/v2.12.0/coder_2.12.0_linux_amd64.tar.gz -o coder.tar.gz \&\& tar -xzf coder.tar.gz \&\& mv coder /usr/bin/coder \&\& rm coder.tar.gz|g' {} +

# 4. NGINX KONFIGURATION (Mit Domain-Name für Certbot)
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
chmod +x startup.sh
./startup.sh prod --build -d

log "Backend erfolgreich gestartet!"
