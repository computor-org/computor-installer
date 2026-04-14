#!/bin/bash
set -e

BACKEND_DIR="/opt/computor/backend"
DOMAIN=""
ADMIN_PASS=""
CONFIGURE_NGINX=false

while getopts "u:s:w" opt; do
  case $opt in
    u) DOMAIN="$OPTARG" ;;
    s) ADMIN_PASS="$OPTARG" ;;
    w) CONFIGURE_NGINX=true ;;
  esac
done

log() { echo -e "\033[0;34m[BACKEND]\033[0m $1"; }

# 1. Klonen
if [ ! -d "$BACKEND_DIR" ]; then
    log "Klone Repository..."
    git clone https://github.com/computor-org/computor-backend "$BACKEND_DIR"
fi

cd "$BACKEND_DIR"

# 2. .env Datei vorbereiten
log "Konfiguriere .env Datei..."
if [ -f ".env.example" ]; then
    cp .env.example .env
fi

# Zufällige Secrets generieren
JWT_SECRET=$(openssl rand -hex 32)
ENCRYPTION_KEY=$(openssl rand -hex 16)

# Werte in .env setzen (Anpassung an deine Struktur)
sed -i "s|DATABASE_PASSWORD=.*|DATABASE_PASSWORD=$ADMIN_PASS|g" .env
sed -i "s|JWT_SECRET=.*|JWT_SECRET=$JWT_SECRET|g" .env
sed -i "s|API_DOMAIN=.*|API_DOMAIN=$DOMAIN|g" .env

# 3. Nginx für API (Port 8080)
if [ "$CONFIGURE_NGINX" = true ]; then
  cat <<EOF > /etc/nginx/sites-available/backend.conf
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};
    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
  ln -sf /etc/nginx/sites-available/backend.conf /etc/nginx/sites-enabled/
  systemctl restart nginx
fi

# 4. Startup ausführen
log "Starte Backend mit Docker..."
chmod +x startup.sh
./startup.sh prod --build

log "Backend erfolgreich gestartet."
