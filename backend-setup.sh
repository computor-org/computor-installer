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
log "Klone Repository frisch..."
git clone https://github.com/computor-org/computor-backend.git "$BACKEND_DIR"
cd "$BACKEND_DIR"

# 2. .env erstellen
cp "$TEMPLATE_PATH" .env
update_env() {
    # Wir nutzen | als Trenner, damit Sonderzeichen in Emails (@) oder Secrets nicht stören
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
update_env "CODER_URL" "http://computor-coder:7080"
update_env "API_URL" "https://${DOMAIN}"
update_env "NEXT_PUBLIC_API_URL" "https://${DOMAIN}"
update_env "CODER_WORKSPACE_BASE_URL" "https://${DOMAIN}/coder"
update_env "DOCKER_GID" "$(getent group docker | cut -d: -f3 || echo 999)"
update_env "MATLAB_TESTING_WORKER_REPLICAS" "0"
mkdir -p /opt/computor/shared

# ==========================================================================
# 3. DIE ENTSCHEIDENDEN FIXES (ROUTING, DEBIAN 13, CODER)
# ==========================================================================
log "Patsche Konfigurationen für Debian 13 und Routing-Priorität..."

# Schritt A: MATLAB-Dienst entfernen (Verhindert Build-Abbruch)
# Wir verwenden einen Regex, um den gesamten Service-Block zu entfernen.
python3 - <<EOF
import re
file_path = 'ops/docker/docker-compose.prod.yaml'
with open(file_path, 'r') as f:
    content = f.read()

# Match the service block starting with '  temporal-worker-matlab:' and ending before the next service block
# The regex looks for the service name, then all following lines that are indented, 
# or lines starting with '#' which are comments belonging to that block.
new_content = re.sub(r'\n\s*# MATLAB Testing Worker\n\s*temporal-worker-matlab:[\s\S]*?(?=\n\n|\n\s*#)', '', content)

with open(file_path, 'w') as f:
    f.write(new_content)
EOF

# Schritt B: Backend-Routing massiv erweitern (Der Login-Fix!)
# Wir fügen alle Pfade hinzu, die das Backend direkt bedient.
# Da sed bei komplexen Pfadregeln oft an Delimitern scheitert, nutzen wir ein kleines Python-Skript zur Konfigurationsanpassung.

#python3 - <<EOF
#import re
#file_path = 'ops/docker/docker-compose.prod.yaml'
#with open(file_path, 'r') as f:
#    content = f.read()

#new_rule = 'PathPrefix(\`/api\`) || PathPrefix(\`/auth\`) || PathPrefix(\`/v1\`) || PathPrefix(\`/user\`) || PathPrefix(\`/users\`) || PathPrefix(\`/docs\`) || PathPrefix(\`/openapi.json\`) || PathPrefix(\`/coder\`) || PathPrefix(\`/service-types\`) || PathPrefix(\`/profiles\`) || PathPrefix(\`/student-profiles\`) || PathPrefix(\`/tutors\`) || PathPrefix(\`/lecturers\`) || PathPrefix(\`/user-roles\`) || PathPrefix(\`/role-claims\`) || PathPrefix(\`/service-accounts\`) || PathPrefix(\`/api-tokens\`) || PathPrefix(\`/tasks\`) || PathPrefix(\`/team-management\`) || PathPrefix(\`/course-member-import\`) || PathPrefix(\`/course-member-gradings\`) || PathPrefix(\`/storage\`) || PathPrefix(\`/examples\`) || PathPrefix(\`/extensions\`) || PathPrefix(\`/submissions\`) || PathPrefix(\`/course-member-comments\`) || PathPrefix(\`/messages\`) || PathPrefix(\`/sessions\`) || PathPrefix(\`/ws\`) || PathPrefix(\`/workspaces\`)'

# Ersetze die alte (kurze) Regel durch die neue Regel
#content = re.sub(r'PathPrefix\(\`/api\`\)', new_rule, content)

#with open(file_path, 'w') as f:
#    f.write(content)
#EOF

# Schritt C: Stripprefix Middleware deaktivieren
#sed -i 's/uvicorn-stripprefix/# disabled-stripprefix/g' ops/docker/docker-compose.prod.yaml
#sed -i 's|traefik.http.routers.uvicorn.middlewares=uvicorn-stripprefix||g' ops/docker/docker-compose.prod.yaml

# Schritt D: Python 3.10 -> Python 3 Fix (Debian Trixie/13 Support)
find . -name "Dockerfile*" -exec sed -i 's/python3\.10/python3/g' {} +
find . -name "Dockerfile*" -exec sed -i 's/libpython3\.10-dev/libpython3-dev/g' {} +

# Schritt E: Coder-CLI Fix (Nutze Binary statt instabilem install.sh im Docker-Build)
#find . -name "Dockerfile*" -type f -exec sed -i 's|curl -fsSL https://coder.com/install.sh \| sh|curl -fsSL https://github.com/coder/coder/releases/download/v2.12.0/coder_2.12.0_linux_amd64.tar.gz -o coder.tar.gz \&\& tar -xzf coder.tar.gz \&\& mv coder /usr/bin/coder \&\& rm coder.tar.gz|g' {} +

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
