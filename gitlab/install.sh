#!/bin/bash
set -e

###########################
# CLI PARAMETERS
###########################

GITLAB_DIR="/root/gitlab"
GITLAB_PORT=""
GITLAB_DOMAIN=""
GITLAB_SSH_PORT="2222"
ROOT_PASSWORD=""

# Parse command line arguments
while getopts "d:P:D:s:p:h" opt; do
  case $opt in
    d)
      GITLAB_DIR="$OPTARG"
      ;;
    P)
      GITLAB_PORT="$OPTARG"
      ;;
    D)
      GITLAB_DOMAIN="$OPTARG"
      ;;
    s)
      GITLAB_SSH_PORT="$OPTARG"
      ;;
    p)
      ROOT_PASSWORD="$OPTARG"
      ;;
    h)
      echo "Usage: $0 [-d DIRECTORY] [-P PORT] [-D DOMAIN] [-s SSH_PORT] [-p PASSWORD]"
      echo ""
      echo "Options:"
      echo "  -d DIRECTORY  GitLab installation directory (default: /root/gitlab)"
      echo "  -P PORT       GitLab HTTP port (will prompt if not provided)"
      echo "  -D DOMAIN     GitLab domain (will prompt if not provided)"
      echo "  -s SSH_PORT   GitLab SSH port (default: 2222)"
      echo "  -p PASSWORD   Root admin password (will prompt if not provided)"
      echo "  -h            Show this help"
      echo ""
      echo "Examples:"
      echo "  $0                                        # Interactive mode"
      echo "  $0 -D gitlab.example.com -P 8080          # Non-interactive (prompts password)"
      echo "  $0 -D gitlab.example.com -P 8080 -p secret # Fully non-interactive"
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

# Check if docker is available
if ! command -v docker &> /dev/null; then
  echo "ERROR: Docker is not installed or not in PATH"
  exit 1
fi

# Check if docker is running
if ! docker info &> /dev/null; then
  echo "ERROR: Docker daemon is not running"
  exit 1
fi

# Check if docker compose is available
if ! docker compose version &> /dev/null; then
  echo "ERROR: Docker Compose is not available"
  exit 1
fi

###########################
# USER INPUT (if not provided via flags)
###########################

if [ -z "$GITLAB_DOMAIN" ]; then
  read -p "Enter domain (e.g. gitlab.example.com): " GITLAB_DOMAIN
fi
echo "Domain set to: $GITLAB_DOMAIN"

if [ -z "$GITLAB_PORT" ]; then
  read -p "Enter HTTP port for GitLab (e.g. 8080): " GITLAB_PORT
fi
echo "Port set to: $GITLAB_PORT"

if [ -z "$ROOT_PASSWORD" ]; then
  read -sp "Enter root admin password: " ROOT_PASSWORD
  echo ""
fi
echo "Root password configured."

###########################
# CREATE DIRECTORIES
###########################

echo "Creating GitLab directory: $GITLAB_DIR"
mkdir -p "${GITLAB_DIR}"

###########################
# CREATE docker-compose.yml
###########################

echo "Creating docker-compose.yml..."
cat <<EOF > "${GITLAB_DIR}/docker-compose.yml"
services:
  gitlab:
    image: gitlab/gitlab-ee:latest
    container_name: gitlab
    restart: always
    hostname: ${GITLAB_DOMAIN}
    environment:
      GITLAB_OMNIBUS_CONFIG: |
        external_url "http://${GITLAB_DOMAIN}"
        gitlab_rails['initial_root_password'] = '${ROOT_PASSWORD}'
    ports:
      - "${GITLAB_PORT}:80"
      - "${GITLAB_SSH_PORT}:22"
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
# START GITLAB
###########################

echo "Starting GitLab..."
cd "${GITLAB_DIR}"
docker compose up -d

echo ""
echo "====================================================="
echo "GitLab is starting (may take a few minutes to initialize)."
echo ""
echo "Access URL: http://${GITLAB_DOMAIN}:${GITLAB_PORT}"
echo "SSH access: ssh -p ${GITLAB_SSH_PORT} git@${GITLAB_DOMAIN}"
echo "Username:   root"
echo "Password:   (as configured)"
echo ""
echo "Installation directory: $GITLAB_DIR"
echo "====================================================="
