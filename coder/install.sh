#!/bin/bash
set -e

###########################
# CLI PARAMETERS
###########################

CODER_DIR="/root/coder"
POSTGRES_PASSWORD="coder_password"
POSTGRES_PORT="5439"
CODER_PORT=""
CODER_DOMAIN=""
USE_HTTP=false
ADMIN_USERNAME=""
ADMIN_EMAIL=""
ADMIN_PASSWORD=""
TEMPLATE_NAME="docker-workspace"
WORKSPACE_IMAGE="localhost:5000/computor-workspace:latest"

# Parse command line arguments
while getopts "d:p:Q:P:D:Hu:e:w:t:i:h" opt; do
  case $opt in
    d)
      CODER_DIR="$OPTARG"
      ;;
    p)
      POSTGRES_PASSWORD="$OPTARG"
      ;;
    Q)
      POSTGRES_PORT="$OPTARG"
      ;;
    P)
      CODER_PORT="$OPTARG"
      ;;
    D)
      CODER_DOMAIN="$OPTARG"
      ;;
    H)
      USE_HTTP=true
      ;;
    u)
      ADMIN_USERNAME="$OPTARG"
      ;;
    e)
      ADMIN_EMAIL="$OPTARG"
      ;;
    w)
      ADMIN_PASSWORD="$OPTARG"
      ;;
    t)
      TEMPLATE_NAME="$OPTARG"
      ;;
    i)
      WORKSPACE_IMAGE="$OPTARG"
      ;;
    h)
      echo "Usage: $0 [-d DIRECTORY] [-p PASSWORD] [-Q PGPORT] [-P PORT] [-D DOMAIN] [-H] [-u USER] [-e EMAIL] [-w PASS] [-t TEMPLATE] [-i IMAGE]"
      echo ""
      echo "Options:"
      echo "  -d DIRECTORY  Coder installation directory (default: /root/coder)"
      echo "  -p PASSWORD   PostgreSQL password (default: coder_password)"
      echo "  -Q PGPORT     PostgreSQL host port (default: 5439)"
      echo "  -P PORT       Coder port (will prompt if not provided)"
      echo "  -D DOMAIN     Coder domain (will prompt if not provided)"
      echo "  -H            Use HTTP instead of HTTPS (for local development)"
      echo "  -u USERNAME   Admin username (optional, enables auto-setup)"
      echo "  -e EMAIL      Admin email (optional)"
      echo "  -w PASSWORD   Admin password (optional)"
      echo "  -t TEMPLATE   Template name (default: docker-workspace)"
      echo "  -i IMAGE      Workspace image name (default: localhost:5000/computor-workspace:latest)"
      echo "  -h            Show this help"
      echo ""
      echo "Examples:"
      echo "  $0                                    # No admin, first signup = admin"
      echo "  $0 -D example.com -P 8443             # Production (HTTPS)"
      echo "  $0 -D localhost -P 8443 -H            # Local development (HTTP)"
      echo "  $0 -D example.com -P 8443 -u admin -e admin@example.com -w secret"
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
# VALIDATION
###########################

if ! command -v docker &> /dev/null; then
  echo "ERROR: Docker is not installed or not in PATH"
  exit 1
fi

if ! docker info &> /dev/null; then
  echo "ERROR: Docker daemon is not running"
  exit 1
fi

if ! docker compose version &> /dev/null; then
  echo "ERROR: Docker Compose is not available"
  exit 1
fi

###########################
# USER INPUT (if not provided via flags)
###########################

if [ -z "$CODER_DOMAIN" ]; then
  read -p "Enter domain (e.g. computor.at): " CODER_DOMAIN
fi
echo "Domain set to: $CODER_DOMAIN"

if [ "$USE_HTTP" = true ]; then
  CODER_ACCESS_URL="http://${CODER_DOMAIN}"
else
  CODER_ACCESS_URL="https://${CODER_DOMAIN}"
fi
echo "Coder Access URL set to: $CODER_ACCESS_URL"

if [ -z "$CODER_PORT" ]; then
  read -p "Enter port for Coder (e.g. 8443): " CODER_PORT
fi
echo "Port set to: $CODER_PORT"

###########################
# GENERATE ADMIN API SECRET
###########################

echo "Generating Admin API Secret for workspace creation protection..."
ADMIN_API_SECRET=$(openssl rand -hex 32)
echo "Admin API Secret generated."

###########################
# ADMIN USER INPUT (if partial info provided)
###########################

if [ -n "$ADMIN_USERNAME" ] || [ -n "$ADMIN_EMAIL" ] || [ -n "$ADMIN_PASSWORD" ]; then
  echo ""
  echo "Admin user creation enabled."

  if [ -z "$ADMIN_USERNAME" ]; then
    read -p "Enter admin username: " ADMIN_USERNAME
  fi

  if [ -z "$ADMIN_EMAIL" ]; then
    read -p "Enter admin email: " ADMIN_EMAIL
  fi

  if [ -z "$ADMIN_PASSWORD" ]; then
    read -sp "Enter admin password: " ADMIN_PASSWORD
    echo ""
  fi
fi

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

echo "Creating Coder directory: $CODER_DIR"
mkdir -p "${CODER_DIR}"

###########################
# COPY TEMPLATE FILES FIRST
###########################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="${CODER_DIR}/templates/docker"

if [ -f "${SCRIPT_DIR}/main.tf" ] && [ -f "${SCRIPT_DIR}/Dockerfile" ]; then
  echo "Copying template files to ${TEMPLATE_DIR}..."
  mkdir -p "${TEMPLATE_DIR}"
  cp "${SCRIPT_DIR}/main.tf" "${TEMPLATE_DIR}/"
  cp "${SCRIPT_DIR}/Dockerfile" "${TEMPLATE_DIR}/"
  echo "Template files copied successfully."
  HAVE_TEMPLATE=true
else
  echo "Note: Template files (main.tf, Dockerfile) not found in script directory."
  echo "You can add them later to: ${TEMPLATE_DIR}"
  HAVE_TEMPLATE=false
fi

###########################
# COPY docker-compose.yml AND CREATE .env
###########################

echo "Copying docker-compose.yml..."
cp "${SCRIPT_DIR}/docker-compose.yml" "${CODER_DIR}/docker-compose.yml"

echo "Copying blocked.conf for Traefik protection..."
cp "${SCRIPT_DIR}/blocked.conf" "${CODER_DIR}/blocked.conf"

echo "Creating .env file..."
cat > "${CODER_DIR}/.env" <<EOF
WORKSPACE_IMAGE=${WORKSPACE_IMAGE}
TEMPLATE_DIR=${TEMPLATE_DIR}
CODER_PORT=${CODER_PORT}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_PORT=${POSTGRES_PORT}
CODER_ACCESS_URL=${CODER_ACCESS_URL}
DOCKER_GID=${DOCKER_GID}
ADMIN_USERNAME=${ADMIN_USERNAME}
ADMIN_EMAIL=${ADMIN_EMAIL}
ADMIN_PASSWORD=${ADMIN_PASSWORD}
TEMPLATE_NAME=${TEMPLATE_NAME}
ADMIN_API_SECRET=${ADMIN_API_SECRET}
EOF

###########################
# COPY SETUP-ADMIN SCRIPT
###########################

if [ -f "${SCRIPT_DIR}/setup-admin.sh" ]; then
  cp "${SCRIPT_DIR}/setup-admin.sh" "${CODER_DIR}/"
  chmod +x "${CODER_DIR}/setup-admin.sh"
  echo "Admin setup script copied to: ${CODER_DIR}/setup-admin.sh"
fi

###########################
# START CODER
###########################

echo "Starting Coder..."
cd "${CODER_DIR}"
docker compose up -d

echo ""
echo "====================================================="
echo "CODER is running."
echo "Docker GID set to: $DOCKER_GID"
echo "Access URL: $CODER_ACCESS_URL"
echo "Installation directory: $CODER_DIR"
echo ""
echo "Local registry: localhost:5000"
echo "Workspace image: $WORKSPACE_IMAGE"
if [ -d "${TEMPLATE_DIR}" ]; then
  echo "Template files: ${TEMPLATE_DIR}"
fi
if [ -n "$ADMIN_USERNAME" ]; then
  echo ""
  echo "Admin user: $ADMIN_USERNAME ($ADMIN_EMAIL)"
  echo "Template: $TEMPLATE_NAME (will be created automatically)"
fi
echo ""
echo "WORKSPACE CREATION PROTECTION:"
echo "  Admin API Secret: $ADMIN_API_SECRET"
echo "  Use this header to create users/workspaces from your backend:"
echo "    X-Admin-Secret: $ADMIN_API_SECRET"
echo ""
echo "To create additional admin users later, run:"
echo "  ${CODER_DIR}/setup-admin.sh"
echo "====================================================="
