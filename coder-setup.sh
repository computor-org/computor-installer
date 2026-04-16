#!/bin/bash
set -e

CODER_DIR="/opt/computor/coder"
CONFIGURE_NGINX=false
DOMAIN=""
PORT="7080"
ADMIN_EMAIL=""
ADMIN_PASS=""

while getopts "d:wihu:p:m:s:" opt; do
  case $opt in
    d) CODER_DIR="$OPTARG" ;;
    u) DOMAIN="$OPTARG" ;;
    p) PORT="$OPTARG" ;;
    m) ADMIN_EMAIL="$OPTARG" ;;
    s) ADMIN_PASS="$OPTARG" ;;
    w) CONFIGURE_NGINX=true ;;
  esac
done

if [ -z "$DOMAIN" ] || [ -z "$ADMIN_EMAIL" ] || [ -z "$ADMIN_PASS" ]; then
    echo "Fehler: Domain, Email und Passwort erforderlich!"
    exit 1
fi

DOCKER_GID=$(getent group docker | cut -d: -f3 || echo "999")
mkdir -p "$CODER_DIR"
cd "$CODER_DIR"

# 1. WICHTIG: Falls eine alte kaputte Datenbank existiert -> weg damit!
# Nur so greift die automatische Erstellung beim ersten Start.
if [ -f "docker-compose.yml" ]; then
    echo "Bereinige alte Instanz..."
    docker compose down -v || true
fi

# 2. Docker Compose mit SICHEREN Anführungszeichen erstellen
cat <<EOF > docker-compose.yml
services:
  coder:
    image: ghcr.io/coder/coder:latest
    ports:
      - "127.0.0.1:${PORT}:6080"
    environment:
      CODER_PG_CONNECTION_URL: "postgresql://coder:coder_password@database/coder?sslmode=disable"
      CODER_HTTP_ADDRESS: "0.0.0.0:6080"
      CODER_ACCESS_URL: "https://${DOMAIN}"
      # HIER WIRD DER ADMIN ERSTELLT (Strings in einfache Anführungszeichen!)
      CODER_FIRST_USER_EMAIL: '${ADMIN_EMAIL}'
      CODER_FIRST_USER_PASSWORD: '${ADMIN_PASS}'
      CODER_FIRST_USER_USERNAME: 'admin'
      CODER_FIRST_USER_TRIAL: 'true'
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

# 3. Nginx Konfig (mit IPv6 Support)
if [ "$CONFIGURE_NGINX" = true ]; then
  cat <<EOF > /etc/nginx/sites-available/coder.conf
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};
    location / {
        proxy_pass http://127.0.0.1:${PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
  ln -sf /etc/nginx/sites-available/coder.conf /etc/nginx/sites-enabled/
  systemctl restart nginx
fi

# 4. Starten
docker compose up -d

echo "Warte auf Coder Start..."
sleep 10

# 5. SICHERHEITS-CHECK: Falls die Automatik versagt hat, erzwingen wir es jetzt!
echo "Prüfe Admin-Account..."
if ! docker compose logs coder | grep -q "first user"; then
    echo "Erzwinge Admin-Erstellung via CLI..."
    docker compose exec -T coder coder server create-admin-user \
      --email "${ADMIN_EMAIL}" \
      --password "${ADMIN_PASS}" \
      --username "admin" \
      --postgres-url "postgresql://coder:coder_password@database/coder?sslmode=disable" || echo "Admin existiert bereits oder Erstellung übersprungen."
fi

echo "Fertig! Admin: $ADMIN_EMAIL"
