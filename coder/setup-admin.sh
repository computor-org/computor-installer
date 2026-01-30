#!/bin/bash
set -e

###########################
# CLI PARAMETERS
###########################

CODER_DIR=""
ADMIN_USERNAME=""
ADMIN_EMAIL=""
ADMIN_PASSWORD=""

# Parse command line arguments
while getopts "d:u:e:p:h" opt; do
  case $opt in
    d)
      CODER_DIR="$OPTARG"
      ;;
    u)
      ADMIN_USERNAME="$OPTARG"
      ;;
    e)
      ADMIN_EMAIL="$OPTARG"
      ;;
    p)
      ADMIN_PASSWORD="$OPTARG"
      ;;
    h)
      echo "Usage: $0 [-d DIRECTORY] [-u USERNAME] [-e EMAIL] [-p PASSWORD]"
      echo ""
      echo "Creates an admin user for an existing Coder installation."
      echo ""
      echo "Options:"
      echo "  -d DIRECTORY  Coder installation directory (auto-detected if not provided)"
      echo "  -u USERNAME   Admin username (will prompt if not provided)"
      echo "  -e EMAIL      Admin email (will prompt if not provided)"
      echo "  -p PASSWORD   Admin password (will prompt if not provided)"
      echo "  -h            Show this help"
      echo ""
      echo "Examples:"
      echo "  $0                                           # Interactive mode"
      echo "  $0 -u admin -e admin@example.com -p secret   # Non-interactive"
      echo "  $0 -d /opt/coder -u admin -e admin@example.com"
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
# DETECT CODER DIRECTORY
###########################

if [ -z "$CODER_DIR" ]; then
  # Try to find docker-compose.yml in common locations
  if [ -f "./docker-compose.yml" ]; then
    CODER_DIR="."
  elif [ -f "/root/coder/docker-compose.yml" ]; then
    CODER_DIR="/root/coder"
  else
    read -p "Enter Coder installation directory: " CODER_DIR
  fi
fi

# Verify directory exists
if [ ! -f "${CODER_DIR}/docker-compose.yml" ]; then
  echo "ERROR: docker-compose.yml not found in ${CODER_DIR}"
  exit 1
fi

echo "Coder directory: $CODER_DIR"
cd "$CODER_DIR"

###########################
# EXTRACT POSTGRES PASSWORD
###########################

# Extract postgres password from docker-compose.yml
POSTGRES_PASSWORD=$(grep -A1 "POSTGRES_PASSWORD:" docker-compose.yml | head -1 | sed 's/.*POSTGRES_PASSWORD: //' | tr -d ' ')

if [ -z "$POSTGRES_PASSWORD" ]; then
  echo "ERROR: Could not extract PostgreSQL password from docker-compose.yml"
  exit 1
fi

###########################
# USER INPUT
###########################

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

###########################
# VALIDATE INPUT
###########################

if [ -z "$ADMIN_USERNAME" ] || [ -z "$ADMIN_EMAIL" ] || [ -z "$ADMIN_PASSWORD" ]; then
  echo "ERROR: Username, email, and password are required"
  exit 1
fi

###########################
# CREATE ADMIN USER
###########################

echo "Stopping Coder temporarily..."
docker compose stop coder

echo "Creating admin user..."
docker compose run --rm \
  -e CODER_USERNAME="$ADMIN_USERNAME" \
  -e CODER_EMAIL="$ADMIN_EMAIL" \
  -e CODER_PASSWORD="$ADMIN_PASSWORD" \
  coder server create-admin-user \
  --postgres-url "postgresql://coder:${POSTGRES_PASSWORD}@database/coder?sslmode=disable"

echo "Starting Coder..."
docker compose up -d coder

echo ""
echo "====================================================="
echo "Admin user created successfully!"
echo ""
echo "Username: $ADMIN_USERNAME"
echo "Email:    $ADMIN_EMAIL"
echo "====================================================="
