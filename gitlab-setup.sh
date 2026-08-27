#!/bin/bash
set -e

GITLAB_DIR="/opt/gitlab-data"
CONFIGURE_NGINX=false
INSTALL_DOCKER=false
DOMAIN=""
PORT="8080"
PASSWORD=""

while getopts "d:wihu:p:s:" opt; do
  case $opt in
    d) GITLAB_DIR="$OPTARG" ;;
    u) DOMAIN="$OPTARG" ;;
    p) PORT="$OPTARG" ;;
    s) PASSWORD="$OPTARG" ;;
    w) CONFIGURE_NGINX=true ;;
    i) INSTALL_DOCKER=true ;;
    *) exit 2 ;;
  esac
done

if [ -z "$DOMAIN" ] || [ -z "$PASSWORD" ]; then
  echo "Fehler: Domain (-u) und Passwort (-s) erforderlich."
  exit 1
fi

if [ "$INSTALL_DOCKER" = true ]; then
  echo "Install Docker from a verified package source before running this installer."
  exit 1
fi

mkdir -p "$GITLAB_DIR"
cd "$GITLAB_DIR"

cat <<EOF > docker-compose.yml
services:
  gitlab:
    image: gitlab/gitlab-ee@sha256:b5167605564d64acf896be614791092d1409ac3f78214a9e4394ebb24a0be1b5
    container_name: gitlab
    restart: always
    hostname: ${DOMAIN}
    environment:
      GITLAB_OMNIBUS_CONFIG: |
        external_url 'https://${DOMAIN}'
        nginx['listen_port'] = 80
        nginx['listen_https'] = false
        gitlab_rails['initial_root_password'] = '${PASSWORD}'
    ports:
      - "127.0.0.1:${PORT}:80"
      - "2222:22"
    volumes:
      - ./config:/etc/gitlab
      - ./logs:/var/log/gitlab
      - ./data:/var/opt/gitlab
EOF

if [ "$CONFIGURE_NGINX" = true ]; then
  cat <<EOF > /etc/nginx/sites-available/gitlab.conf
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};

    location / {
        proxy_pass http://127.0.0.1:${PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF
  ln -sf /etc/nginx/sites-available/gitlab.conf /etc/nginx/sites-enabled/
  systemctl restart nginx
fi

docker compose up -d
echo "GitLab wird gestartet (dies kann 5-10 Min dauern)."
