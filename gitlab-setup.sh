#!/bin/bash
set -e

###########################
# USER INPUT
###########################

read -p "Bitte Domain eingeben (z.B. computor.at): " DOMAIN
echo "Domain gesetzt auf: $DOMAIN"

read -p "Bitte Port für Gitlab eingeben (z.B. 8443): " PORT
echo "Port gesetzt auf: $PORT"
###########################
# ROOT CHECK
###########################

if [ "$EUID" -ne 0 ]; then
  echo "Bitte als root ausführen."
  exit 1
fi

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
# CREATE DIRECTORIES
###########################


read -p "Bitte Admin Passwort setzen " PASSWORD
echo "Admin Passwort wurde auf $PASSWORD gesetzt"

mkdir -p /root/dev-gitlab
cd /root/dev-gitlab

###########################
# CREATE docker-compose.yml
###########################

cat <<EOF > /root/dev-gitlab/docker-compose.yml
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
      - "$PORT:80"
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
# INSTALL NGINX
###########################

apt install -y nginx

###########################
# NGINX HTTP CONFIG
###########################

cat <<EOF > /etc/nginx/sites-available/gitlab.conf
server {
    listen 80;
    listen [::]:80;

    server_name ${DOMAIN};

    # ACME Challenge
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    # Proxy to GitLab (HTTP only)
    location / {
        proxy_pass http://127.0.0.1:$PORT/;
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

###########################
# START GITLAB
###########################

docker compose up -d

echo ""
echo "====================================================="
echo "GitLab läuft jetzt über HTTP."
echo "Bitte das zweite Skript ausführen, um HTTPS zu aktivieren."
echo "====================================================="
