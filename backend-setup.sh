#!/bin/bash
set -e

BACKEND_DIR="/opt/computor/backend"
TEMPLATE_PATH="ops/environments/.env.common.template"
DOMAIN=""
ADMIN_EMAIL=""
CONFIGURE_NGINX=false

BLUE='\033[0;34m'
YELLOW='\033[1;33m'
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
  esac
done

# 1. Repo klonen
if ! command -v git &> /dev/null; then apt-get update && apt-get install -y git; fi
if [ ! -d "$BACKEND_DIR" ]; then
    git clone https://github.com/computor-org/computor-backend.git "$BACKEND_DIR"
fi
cd "$BACKEND_DIR"

# 2. .env erstellen
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
update_env "SYSTEM_DEPLOYMENT_PATH" "/opt/computor"
update_env "API_ROOT_PATH" "/opt/computor/shared"
mkdir -p /opt/computor/shared

# ==========================================================================
# 3. SICHERER FIX FÜR DEBIAN 13 (MATLAB-ENTFERNUNG)
# ==========================================================================
log "Bereinige YAML-Dateien in ops/docker/ (Sichere Methode)..."

# Wir nutzen Python, um den MATLAB-Block sauber zu entfernen
# Dies verhindert das Verschieben von 'depends_on' Keys
python3 - <<EOF
import os

def clean_yaml(filepath):
    if not os.path.exists(filepath): return
    with open(filepath, 'r') as f:
        lines = f.readlines()

    new_lines = []
    skip = False
    indent = 0

    for line in lines:
        stripped = line.lstrip()
        if not stripped: # Leerzeile
            new_lines.append(line)
            continue

        current_indent = len(line) - len(stripped)

        # Start des zu löschenden Blocks finden
        if "temporal-worker-matlab:" in line:
            skip = True
            indent = current_indent
            continue

        # Ende des Blocks finden (wenn Einrückung wieder kleiner/gleich ist)
        if skip:
            if current_indent <= indent and stripped:
                skip = False
            else:
                continue

        new_lines.append(line)

    with open(filepath, 'w') as f:
        f.writelines(new_lines)

# Wende die Reinigung auf alle Compose-Files an
for root, dirs, files in os.walk("ops/docker"):
    for file in files:
        if file.endswith(".yaml") or file.endswith(".yml"):
            clean_yaml(os.path.join(root, file))
EOF

log "Patsche Dockerfiles von python3.10 auf python3..."
find . -name "Dockerfile*" -type f -exec sed -i 's/python3\.10/python3/g' {} +
find . -name "Dockerfile*" -type f -exec sed -i 's/libpython3\.10-dev/libpython3-dev/g' {} +
log "✓ System für Debian 13 vorbereitet."

# ==========================================================================

# 4. Nginx Proxy
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

# 5. Starten
log "Starte Build & Deploy via startup.sh..."
chmod +x startup.sh
./startup.sh prod --build -d

log "Backend erfolgreich gestartet!"
