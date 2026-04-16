#!/bin/bash
set -e

BACKEND_DIR="/opt/computor/backend"
TEMPLATE_PATH="ops/environments/.env.common.template"
DOMAIN=""
ADMIN_EMAIL=""
API_ADMIN_PASS="" # Wird über -s befüllt
CONFIGURE_NGINX=false

BLUE='\033[0;34m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

log() { echo -e "${BLUE}[BACKEND]${NC} $1"; }

# Passwort-Generatoren für technische Accounts
gen_pass() { openssl rand -base64 48 | tr -d '+/=' | head -c 24; }
gen_hex()  { openssl rand -hex 32; }
gen_base64() { openssl rand -base64 32; }

# Getopts: Wir fangen -s ab
while getopts "u:m:s:wg" opt; do
  case $opt in
    u) DOMAIN="$OPTARG" ;;
    m) ADMIN_EMAIL="$OPTARG" ;;
    s) API_ADMIN_PASS="$OPTARG" ;; # Dein Passwort von setup.sh
    w) CONFIGURE_NGINX=true ;;
  esac
done

# Fallback: Falls doch kein Passwort übergeben wurde
if [ -z "$API_ADMIN_PASS" ]; then API_ADMIN_PASS=$(gen_pass); fi

# 1. Repo klonen
if ! command -v git &> /dev/null; then apt-get update && apt-get install -y git; fi
if [ ! -d "$BACKEND_DIR" ]; then
    git clone https://github.com/computor-org/computor-backend.git "$BACKEND_DIR"
fi
cd "$BACKEND_DIR"

# 2. .env erstellen
cp "$TEMPLATE_PATH" .env

# 3. TECHNISCHE PASSWÖRTER GENERIEREN
DB_PASS=$(gen_pass)
REDIS_PASS=$(gen_pass)
MINIO_PASS=$(gen_pass)
# CODER_ADMIN_PASS setzen wir auch auf dein Master-Passwort für Konsistenz
CODER_ADMIN_PASS="$API_ADMIN_PASS"
TOKEN_SECRET=$(gen_base64)
AUTH_SECRET=$(gen_base64)

update_env() {
    sed -i "s@^$1=.*@$1=$2@g" .env
}

log "Schreibe Konfiguration in .env..."
update_env "POSTGRES_PASSWORD" "$DB_PASS"
update_env "TEMPORAL_POSTGRES_PASSWORD" "$(gen_pass)"
update_env "REDIS_PASSWORD" "$REDIS_PASS"
update_env "MINIO_ROOT_PASSWORD" "$MINIO_PASS"
update_env "API_ADMIN_PASSWORD" "$API_ADMIN_PASS" # Dein Wunsch-Passwort
update_env "CODER_ADMIN_PASSWORD" "$CODER_ADMIN_PASS" # Ebenfalls dein Wunsch-Passwort
update_env "TOKEN_SECRET" "$TOKEN_SECRET"
update_env "AUTH_SECRET" "$AUTH_SECRET"
update_env "CODER_ADMIN_API_SECRET" "$(gen_hex)"
update_env "CODER_ENABLED" "true"
update_env "CODER_ADMIN_EMAIL" "$ADMIN_EMAIL"
update_env "API_URL" "https://${DOMAIN}"
update_env "NEXT_PUBLIC_API_URL" "https://${DOMAIN}"
update_env "CODER_URL" "https://$(echo $DOMAIN | sed 's/api\./coder\./')"
update_env "DOCKER_GID" "$(getent group docker | cut -d: -f3 || echo 999)"

# 4. FIX FÜR DEBIAN 13 (MATLAB & Python)
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
find . -name "Dockerfile*" -exec sed -i 's/python3\.10/python3/g' {} +

# 5. Starten
chmod +x startup.sh
./startup.sh prod --build -d

# 6. DER STATUS REPORT
echo -e "\n${GREEN}==================================================${NC}"
echo -e "${GREEN}      ZUGANGSDATEN COMPUTOR BACKEND${NC}"
echo -e "${GREEN}==================================================${NC}"
echo -e "Backend URL:   https://$DOMAIN"
echo -e "Admin User:    admin"
echo -e "Admin Pass:    ${YELLOW}$API_ADMIN_PASS${NC} (Dein Master-Passwort)"
echo -e "--------------------------------------------------"
echo -e "Coder Admin:   $ADMIN_EMAIL"
echo -e "Coder Pass:    ${YELLOW}$CODER_ADMIN_PASS${NC}"
echo -e "--------------------------------------------------"
echo -e "Techn. DB Pass: $DB_PASS (Zufällig generiert)"
echo -e "==================================================${NC}"
