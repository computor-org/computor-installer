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
  esac
done

if [ -z "$DOMAIN" ] || [ -z "$PASSWORD" ]; then
  echo "Fehler: Domain (-u) und Passwort (-s) erforderlich."
  exit 1
fi

if [ "$INSTALL_DOCKER" = true ]; then
  apt update && apt install -y curl
  curl -fsSL https://get.docker.com | sh
fi

mkdir -p "$GITLAB_DIR"
cd "$GITLAB_DIR"

cat <<EOF > docker-compose.yml
services:
  gitlab:
    image: gitlab/gitlab-ee:latest
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
    server_name ${DOMAIN};
    location / {
        proxy_pass http://127.0.0.1:${PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
  ln -sf /etc/nginx/sites-available/gitlab.conf /etc/nginx/sites-enabled/
  systemctl restart nginx
fi

docker compose up -d
echo "GitLab wird gestartet (dies kann 5-10 Min dauern)."
