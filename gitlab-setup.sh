#!/bin/bash
set -e

###########################
# CLI PARAMETERS
###########################

# Standardwerte
GITLAB_DIR="/root/dev-gitlab"
CONFIGURE_NGINX=false
INSTALL_DOCKER=false
DOMAIN=""
PORT=""
PASSWORD=""

# Parse command line arguments
# u = url/domain, p = port, s = secret/password
while getopts "d:wihu:p:s:" opt; do
  case $opt in
    d)
      GITLAB_DIR="$OPTARG"
      ;;
    w)
      CONFIGURE_NGINX=true
      ;;
    i)
      INSTALL_DOCKER=true
      ;;
    u)
      DOMAIN="$OPTARG"
      ;;
    p)
      PORT="$OPTARG"
      ;;
    s)
      PASSWORD="$OPTARG"
      ;;
    h)
      echo "Usage: $0 -u DOMAIN -p PORT -s PASSWORD [-d DIRECTORY] [-w] [-i]"
      echo "  -u DOMAIN     Domain für GitLab (z.B. git.computor.at)"
      echo "  -p PORT       Interner Port für GitLab (z.B. 8443)"
      echo "  -s PASSWORD   Admin-Passwort für GitLab"
      echo "  -d DIRECTORY  Installationsverzeichnis (default: /root/dev-gitlab)"
      echo "  -w            Nginx Konfiguration erstellen"
      echo "  -i            System Update und Docker installieren"
      echo "  -h            Diese Hilfe anzeigen"
      exit 0
      ;;
    \?)
      echo "Ungültige Option: -$OPTARG" >&2
      exit 1
      ;;
  esac
done

# Pflichtparameter prüfen
if [ -z "$DOMAIN" ] || [ -z "$PORT" ] || [ -z "$PASSWORD" ]; then
  echo "Fehler: Domain (-u), Port (-p) und Passwort (-s) sind erforderlich."
  echo "Beispiel: $0 -u git.example.com -p 8080 -s MeinSicheresPasswort -w -i"
  exit 1
fi

echo "Konfiguration: Domain=$DOMAIN, Port=$PORT, Verzeichnis=$GITLAB_DIR"

###########################
# ROOT CHECK
###########################

if [ "$EUID" -ne 0 ]; then
  echo "Bitte als root ausführen."
  exit 1
fi

###########################
# DOCKER INSTALLATION (OPTIONAL)
###########################

if [ "$INSTALL_DOCKER" = true ]; then
  echo "Führe System Update und Docker Installation durch..."
  apt update
  apt upgrade -y
  apt install -y ca-certificates curl gnupg lsb-release
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
  apt update
  apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
else
  echo "Docker Installation übersprungen."
fi

###########################
# CREATE DIRECTORIES
###########################

mkdir -p ${GITLAB_DIR}
cd ${GITLAB_DIR}

###########################
# CREATE docker-compose.yml
###########################

cat <<EOF > ${GITLAB_DIR}/docker-compose.yml
version: "3"
services:
  gitlab:
    image: gitlab/gitlab-ee:latest
    container_name: gitlab
    restart: always
    hostname: ${DOMAIN}
    environment:
      GITLAB_OMNIBUS_CONFIG: |
        external_url "http://${DOMAIN}"
        gitlab_rails['initial_root_password'] = '${PASSWORD}'
    ports:
      - "${PORT}:80"
      - "2222:22"
    volumes:
      - gitlab-config:/etc/gitlab
      - gitlab-logs:/var/log/gitlab
      - gitlab-data:/var/opt/gitlab
volumes:
  gitlab-config:
  gitlab-logs:
  gitlab-data:
EOF

###########################
# NGINX CONFIGURATION (OPTIONAL)
###########################

if [ "$CONFIGURE_NGINX" = true ]; then
  echo "Konfiguriere Nginx..."
  apt install -y nginx
  cat <<EOF > /etc/nginx/sites-available/gitlab.conf
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
    location / {
        proxy_pass http://127.0.0.1:${PORT}/;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-For \$remote_addr;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF
  mkdir -p /var/www/certbot
  chown www-data:www-data /var/www/certbot
  ln -sf /etc/nginx/sites-available/gitlab.conf /etc/nginx/sites-enabled/gitlab.conf
  nginx -t
  systemctl restart nginx
else
  echo "Nginx Konfiguration übersprungen."
fi

###########################
# START GITLAB
###########################

docker compose up -d

echo ""
echo "====================================================="
echo "GitLab wird im Hintergrund gestartet."
echo "Domain: http://${DOMAIN}"
echo "Passwort wurde gesetzt."
echo "Bitte führe nun certify.sh aus für HTTPS."
echo "====================================================="
