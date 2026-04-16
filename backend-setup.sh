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
update_env() { sed -i "s|^$1=.*|$1=$2|g" .env; }

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
update_env "CODER_URL" "http://computor-coder:7080"
update_env "API_URL" "https://${DOMAIN}"
update_env "NEXT_PUBLIC_API_URL" "https://${DOMAIN}"
update_env "CODER_WORKSPACE_BASE_URL" "https://${DOMAIN}/coder"
update_env "DOCKER_GID" "$(getent group docker | cut -d: -f3 || echo 999)"
update_env "MATLAB_TESTING_WORKER_REPLICAS" "0"

# ==========================================================================
# 3. FIX FÜR DEBIAN 13 & ROUTING
# ==========================================================================
log "Bereine YAML-Konfigurationen und patsche Routing..."

python3 -c '
import os

def patch_file(filepath):
    if not os.path.exists(filepath): return
    with open(filepath, "r") as f:
        lines = f.readlines()

    new_lines = []
    skip = False
    for line in lines:
        # A: MATLAB entfernen
        if "temporal-worker-matlab:" in line:
            skip = True
            continue
        if skip and line.strip() and not line.startswith("    ") and not line.startswith("  "):
            skip = False

        # B: TRAEFIK PRIORITÄT PATCH (Der Login-Fix)
        # Wenn wir die uvicorn Sektion finden, fügen wir eine hohe Priorität hinzu
        if "traefik.http.routers.computor-api" in line and "rule" in line:
            new_lines.append(line)
            indent = line[:line.find("traefik")]
            new_lines.append(f"{indent}traefik.http.routers.computor-api-prod.priority=100\n")
            new_lines.append(f"{indent}traefik.http.routers.computor-api-dev.priority=100\n")
            continue

        if not skip:
            new_lines.append(line)

    with open(filepath, "w") as f:
        f.writelines(new_lines)

# Alle YAMLs in ops/docker patchen
for root, dirs, files in os.walk("ops/docker"):
    for file in files:
        if file.endswith(".yaml"):
            patch_file(os.path.join(root, file))
'

# C: Python 3.10 Fix & Coder CLI Fix
find . -name "Dockerfile*" -exec sed -i "s/python3\.10/python3/g" {} +
find . -name "Dockerfile*" -type f -exec sed -i "s|curl -fsSL https://coder.com/install.sh \| sh|curl -fsSL https://github.com/coder/coder/releases/download/v2.12.0/coder_2.12.0_linux_amd64.tar.gz -o coder.tar.gz \&\& tar -xzf coder.tar.gz \&\& mv coder /usr/bin/coder \&\& rm coder.tar.gz|g" {} +

# ==========================================================================

# 4. NGINX
if [ "$CONFIGURE_NGINX" = true ]; then
  cat <<EOF > /etc/nginx/sites-available/${DOMAIN}.conf
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
  ln -sf /etc/nginx/sites-available/${DOMAIN}.conf /etc/nginx/sites-enabled/
  nginx -t && systemctl restart nginx
fi

# 5. Starten
chmod +x startup.sh
./startup.sh prod --build -d

log "Backend mit Routing-Fix gestartet!"
