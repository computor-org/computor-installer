#!/bin/bash
set -e

CODER_DIR="/root/coder"
CONFIGURE_NGINX=false
INSTALL_DOCKER=false
DOMAIN=""
PORT="7080"
ADMIN_EMAIL=""
ADMIN_PASS=""

# getopts erweitert um m: (Email) und s: (Passwort)
while getopts "d:wihu:p:m:s:" opt; do
  case $opt in
    d) CODER_DIR="$OPTARG" ;;
    u) DOMAIN="$OPTARG" ;;
    p) PORT="$OPTARG" ;;
    m) ADMIN_EMAIL="$OPTARG" ;;
    s) ADMIN_PASS="$OPTARG" ;;
    w) CONFIGURE_NGINX=true ;;
    i) INSTALL_DOCKER=true ;;
    h)
      echo "Usage: $0 [-d DIR] [-u DOMAIN] [-p PORT] [-m EMAIL] [-s PASS] [-w] [-i]"
      exit 0
      ;;
  esac
done

if [ -z "$DOMAIN" ] || [ -z "$ADMIN_EMAIL" ] || [ -z "$ADMIN_PASS" ]; then
    echo "Fehler: Domain (-u), Email (-m) und Passwort (-s) erforderlich!"
    exit 1
fi

# Docker Installation (nur wenn -i gesetzt)
if [ "$INSTALL_DOCKER" = true ]; then
  apt update && apt install -y ca-certificates curl gnupg lsb-release
  curl -fsSL https://get.docker.com | sh
fi

DOCKER_GID=$(getent group docker | cut -d: -f3 || echo "999")
mkdir -p "$CODER_DIR"
cd "$CODER_DIR"

# Docker Compose Erstellung mit Admin-Auto-Setup
cat <<EOF > docker-compose.yml
services:
  coder:
    image: ghcr.io/coder/coder:latest
    ports:
      - "127.0.0.1:${PORT}:7080"
    environment:
      CODER_PG_CONNECTION_URL: "postgresql://coder:coder_password@database/coder?sslmode=disable"
      CODER_HTTP_ADDRESS: "0.0.0.0:7080"
      CODER_ACCESS_URL: "https://${DOMAIN}"
      # AUTOMATISCHER ADMIN ACCOUNT:
      CODER_FIRST_USER_EMAIL: "${ADMIN_EMAIL}"
      CODER_FIRST_USER_PASSWORD: "${ADMIN_PASS}"
      CODER_FIRST_USER_USERNAME: "admin"
      CODER_FIRST_USER_TRIAL: "true"
    group_add: ["${DOCKER_GID}"]
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - coder_home:/home/coder
    depends_on:
      database: { condition: service_healthy }
  database:
    image: "postgres:17"
    environment:
      POSTGRES_USER: coder
      POSTGRES_PASSWORD: coder_password
      POSTGRES_DB: coder
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U coder -d coder"]
      interval: 5s
volumes:
  coder_data:
  coder_home:
EOF

# Nginx Konfiguration (unverändert)
if [ "$CONFIGURE_NGINX" = true ]; then
  cat <<EOF > /etc/nginx/sites-available/coder.conf
server {
    listen 80;
    server_name ${DOMAIN};
    location / {
        proxy_pass http://127.0.0.1:${PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF
  ln -sf /etc/nginx/sites-available/coder.conf /etc/nginx/sites-enabled/
  systemctl restart nginx
fi

docker compose up -d
echo "Coder auf https://$DOMAIN gestartet. Admin: $ADMIN_EMAIL"
