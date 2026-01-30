#!/bin/bash
set -e

###########################
# CLI PARAMETERS
###########################

# Coder installation directory (can be overridden with -d flag)
CODER_DIR="/root/coder"

# Parse command line arguments
while getopts "d:h" opt; do
  case $opt in
    d)
      CODER_DIR="$OPTARG"
      echo "Coder directory set to: $CODER_DIR"
      ;;
    h)
      echo "Usage: $0 [-d DIRECTORY]"
      echo "  -d DIRECTORY  Coder installation directory (default: /root/coder)"
      echo "  -h            Show this help"
      exit 0
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      echo "Use -h for help" >&2
      exit 1
      ;;
  esac
done

###########################
# USER INPUT
###########################

read -p "Enter domain (e.g. computor.at): " DOMAIN
echo "Domain set to: $DOMAIN"

CODER_ACCESS_URL="https://${DOMAIN}"
echo "Coder Access URL set to: $CODER_ACCESS_URL"

read -p "Enter port for Coder (e.g. 8443): " PORT
echo "Port set to: $PORT"

###########################
# GET DOCKER GID
###########################

echo "Getting Docker Group ID for permissions..."
DOCKER_GID=$(getent group docker | cut -d: -f3)

if [ -z "$DOCKER_GID" ]; then
  echo "WARNING: Could not find Docker group. Using fallback 999."
  DOCKER_GID="999"
else
  echo "Docker Group ID found: $DOCKER_GID"
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
# START CODER
###########################

docker compose up -d

echo ""
echo "====================================================="
echo "CODER is running."
echo "Docker GID set to: $DOCKER_GID"
echo "Access URL: $CODER_ACCESS_URL"
echo "====================================================="
