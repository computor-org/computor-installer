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
DOCKER_NETWORK="coder-network"

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
# CREATE docker-compose.yml
###########################

echo "Creating docker-compose.yml..."

cat <<EOF > "${CODER_DIR}/docker-compose.yml"
services:
  # Local Docker registry for workspace images
  registry:
    image: registry:2
    ports:
      - "127.0.0.1:5000:5000"
    volumes:
      - registry_data:/var/lib/registry
    networks:
      - ${DOCKER_NETWORK}
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost:5000/v2/"]
      interval: 5s
      timeout: 5s
      retries: 5

  # Build workspace image and push to local registry
  image-builder:
    image: docker:latest
    entrypoint: ["/bin/sh", "-c"]
    command:
      - |
        echo "Waiting for registry to be ready..."
        until wget -q --spider http://registry:5000/v2/; do
          sleep 1
        done
        echo "Registry is ready."

        if [ ! -f /workspace/Dockerfile ]; then
          echo "No Dockerfile found, skipping image build."
          exit 0
        fi

        echo "Building workspace image..."
        cd /workspace
        docker build -t ${WORKSPACE_IMAGE} .

        echo "Pushing image to local registry..."
        docker push ${WORKSPACE_IMAGE}

        echo "Workspace image built and pushed successfully."
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ${TEMPLATE_DIR}:/workspace:ro
    networks:
      - ${DOCKER_NETWORK}
    depends_on:
      registry:
        condition: service_healthy
    restart: "no"

  coder:
    image: ghcr.io/coder/coder:latest
    ports:
      - "${CODER_PORT}:7080"
    environment:
      CODER_PG_CONNECTION_URL: "postgresql://coder:${POSTGRES_PASSWORD}@database:${POSTGRES_PORT}/coder?sslmode=disable"
      CODER_HTTP_ADDRESS: "0.0.0.0:7080"
      CODER_ACCESS_URL: "${CODER_ACCESS_URL}"
    group_add:
      - "${DOCKER_GID}"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - coder_home:/home/coder
    networks:
      - ${DOCKER_NETWORK}
    depends_on:
      database:
        condition: service_healthy
      image-builder:
        condition: service_completed_successfully
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:7080/api/v2/buildinfo"]
      interval: 5s
      timeout: 5s
      retries: 30
      start_period: 10s

  # Post-start container: creates admin user after Coder is healthy
  coder-admin-setup:
    image: ghcr.io/coder/coder:latest
    entrypoint: ["/bin/sh", "-c"]
    command:
      - |
        if [ -z "\$\$CODER_INIT_USERNAME" ]; then
          echo "No admin credentials provided, skipping admin creation."
          exit 0
        fi
        echo "Creating admin user: \$\$CODER_INIT_USERNAME"
        coder server create-admin-user \\
          --username "\$\$CODER_INIT_USERNAME" \\
          --email "\$\$CODER_INIT_EMAIL" \\
          --password "\$\$CODER_INIT_PASSWORD" \\
          --postgres-url "\$\$CODER_PG_CONNECTION_URL" \\
          && echo "Admin user created successfully." \\
          || echo "Admin creation skipped (may already exist)."
        exit 0
    environment:
      CODER_PG_CONNECTION_URL: "postgresql://coder:${POSTGRES_PASSWORD}@database:${POSTGRES_PORT}/coder?sslmode=disable"
      CODER_INIT_USERNAME: "${ADMIN_USERNAME}"
      CODER_INIT_EMAIL: "${ADMIN_EMAIL}"
      CODER_INIT_PASSWORD: "${ADMIN_PASSWORD}"
    networks:
      - ${DOCKER_NETWORK}
    depends_on:
      coder:
        condition: service_healthy
    restart: "no"

  # Post-admin container: creates template after admin is set up
  coder-template-setup:
    image: ghcr.io/coder/coder:latest
    entrypoint: ["/bin/sh", "-c"]
    command:
      - |
        if [ -z "\$\$CODER_INIT_EMAIL" ] || [ -z "\$\$CODER_INIT_PASSWORD" ]; then
          echo "No admin credentials provided, skipping template creation."
          exit 0
        fi

        if [ ! -f /templates/main.tf ]; then
          echo "No template files found, skipping template creation."
          exit 0
        fi

        echo "Logging in to Coder..."

        # Login via API and get session token
        SESSION_TOKEN=\$\$(curl -s -X POST "http://coder:7080/api/v2/users/login" \\
          -H "Content-Type: application/json" \\
          -d "{\"email\":\"\$\$CODER_INIT_EMAIL\",\"password\":\"\$\$CODER_INIT_PASSWORD\"}" \\
          | sed -n 's/.*"session_token":"\([^"]*\)".*/\1/p')

        if [ -z "\$\$SESSION_TOKEN" ]; then
          echo "Failed to get session token, skipping template creation."
          exit 0
        fi

        echo "Session token obtained."
        export CODER_SESSION_TOKEN="\$\$SESSION_TOKEN"
        export CODER_URL="http://coder:7080"

        echo "Pushing template: \$\$TEMPLATE_NAME"
        cd /templates
        coder templates push "\$\$TEMPLATE_NAME" --directory . --yes \\
          && echo "Template '\$\$TEMPLATE_NAME' created successfully." \\
          || echo "Template creation skipped (may already exist)."

        exit 0
    environment:
      CODER_INIT_EMAIL: "${ADMIN_EMAIL}"
      CODER_INIT_PASSWORD: "${ADMIN_PASSWORD}"
      TEMPLATE_NAME: "${TEMPLATE_NAME}"
    volumes:
      - ${TEMPLATE_DIR}:/templates:ro
    networks:
      - ${DOCKER_NETWORK}
    depends_on:
      coder-admin-setup:
        condition: service_completed_successfully
    restart: "no"

  database:
    image: "postgres:17"
    ports:
      - "127.0.0.1:${POSTGRES_PORT}:${POSTGRES_PORT}"
    environment:
      POSTGRES_USER: coder
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: coder
      PGPORT: ${POSTGRES_PORT}
    volumes:
      - coder_data:/var/lib/postgresql/data
    networks:
      - ${DOCKER_NETWORK}
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U coder -d coder -p ${POSTGRES_PORT}"]
      interval: 5s
      timeout: 5s
      retries: 5

volumes:
  coder_data:
  coder_home:
  registry_data:

networks:
  ${DOCKER_NETWORK}:
    name: ${DOCKER_NETWORK}
    driver: bridge
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
echo "To create additional admin users later, run:"
echo "  ${CODER_DIR}/setup-admin.sh"
echo "====================================================="
