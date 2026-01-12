#!/bin/bash
set -e

###########################
# CLI PARAMETERS
###########################

# Coder installation directory (can be overridden with -d flag)
CODER_DIR="/root/coder"
# Flag to control nginx configuration (default: false)
CONFIGURE_NGINX=false
# Flag to control system update and Docker installation (default: false)
INSTALL_DOCKER=false

# Parse command line arguments
while getopts "d:wih" opt; do
  case $opt in
    d)
      CODER_DIR="$OPTARG"
      echo "Coder Verzeichnis gesetzt auf: $CODER_DIR"
      ;;
    w)
      CONFIGURE_NGINX=true
      echo "Nginx Konfiguration wird durchgeführt"
      ;;
    i)
      INSTALL_DOCKER=true
      echo "System Update und Docker Installation wird durchgeführt"
      ;;
    h)
      echo "Usage: $0 [-d DIRECTORY] [-w] [-i]"
      echo "  -d DIRECTORY  Coder Installationsverzeichnis (default: /root/coder)"
      echo "  -w            Mit Nginx/Webserver Konfiguration"
      echo "  -i            System Update und Docker installieren"
      echo "  -h            Diese Hilfe anzeigen"
      exit 0
      ;;
    \?)
      echo "Ungültige Option: -$OPTARG" >&2
      echo "Verwende -h für Hilfe" >&2
      exit 1
      ;;
  esac
done

###########################
# USER INPUT
###########################

read -p "Bitte Domain eingeben (z.B. computor.at): " DOMAIN
echo "Domain gesetzt auf: $DOMAIN"

CODER_ACCESS_URL="https://${DOMAIN}"
echo "Coder Access URL gesetzt auf: $CODER_ACCESS_URL"

read -p "Bitte Port für Coder eingeben (z.B. 8443): " PORT
echo "Port gesetzt auf: $PORT"

# ###########################
# # ROOT CHECK
# ###########################

# if [ "$EUID" -ne 0 ]; then
#   echo "Bitte als root ausführen."
#   exit 1
# fi

###########################
# DOCKER INSTALLATION (OPTIONAL)
###########################

if [ "$INSTALL_DOCKER" = true ]; then
  echo "Führe System Update und Docker Installation durch..."

  ###########################
  # UPDATE SYSTEM
  ###########################

  apt update
  apt upgrade -y

  ###########################
  # INSTALL DOCKER
  ###########################

  apt install -y ca-certificates curl gnupg lsb-release

  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/debian \
    $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

  apt update
  apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  ###########################
  # GET DOCKER GID (AUTO-FIX)
  ###########################

  echo "Ermittle Docker Group ID für Berechtigungen..."
  # Hier holen wir die ID automatisch
  DOCKER_GID=$(getent group docker | cut -d: -f3)

  if [ -z "$DOCKER_GID" ]; then
    echo "WARNUNG: Konnte Docker Gruppe nicht finden. Setze Fallback auf 999."
    DOCKER_GID="999"
  else
    echo "Docker Group ID gefunden: $DOCKER_GID"
  fi
else
  echo "Docker Installation übersprungen (verwende -i Flag um sie zu aktivieren)"
fi

###########################
# CREATE DIRECTORIES
###########################

mkdir -p ${CODER_DIR}
cd ${CODER_DIR}

###########################
# CREATE docker-compose.yml
###########################

cat <<EOF > ${CODER_DIR}/docker-compose.yml
services:
  coder:
    image: ghcr.io/coder/coder:latest
    ports:
      - "${PORT}:7080"
    environment:
      CODER_PG_CONNECTION_URL: "postgresql://coder:coder_password@database/coder?sslmode=disable"
      CODER_HTTP_ADDRESS: "0.0.0.0:7080"
      CODER_ACCESS_URL: "${CODER_ACCESS_URL}"
    group_add:
      - "${DOCKER_GID}"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - coder_home:/home/coder
    depends_on:
      database:
        condition: service_healthy
  database:
    image: "postgres:17"
    environment:
      POSTGRES_USER: coder
      POSTGRES_PASSWORD: coder_password
      POSTGRES_DB: coder
    volumes:
      - coder_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U coder -d coder"]
      interval: 5s
      timeout: 5s
      retries: 5
volumes:
  coder_data:
  coder_home:
EOF

###########################
# NGINX CONFIGURATION (OPTIONAL)
###########################

if [ "$CONFIGURE_NGINX" = true ]; then
  echo "Konfiguriere Nginx..."

  ###########################
  # INSTALL NGINX
  ###########################

  apt install -y nginx

  ###########################
  # NGINX HTTP CONFIG
  ###########################

  cat <<EOF > /etc/nginx/sites-available/coder.conf
server {
    listen 80;
    listen [::]:80;

    server_name ${DOMAIN};

    location / {
        # WICHTIG: 127.0.0.1 statt 'coder'
        proxy_pass http://127.0.0.1:${PORT};

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

  mkdir -p /var/www/certbot
  chown www-data:www-data /var/www/certbot

  ln -sf /etc/nginx/sites-available/coder.conf /etc/nginx/sites-enabled/coder.conf
  nginx -t
  systemctl restart nginx
else
  echo "Nginx Konfiguration übersprungen (verwende -w Flag um sie zu aktivieren)"
fi

###########################
# START CODER
###########################

docker compose up -d

echo ""
echo "====================================================="
echo "CODER läuft (HTTP only)."
echo "Docker GID wurde auf $DOCKER_GID gesetzt."
echo "Bitte führe nun das SSL-Skript aus."
echo "====================================================="
