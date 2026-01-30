#!/bin/bash
set -e

###########################
# CREATE USER + WORKSPACE
# Creates a new Coder user and their workspace
###########################

CODER_URL="${CODER_URL:-http://localhost:8446}"
TEMPLATE_NAME="${TEMPLATE_NAME:-docker-workspace}"
ADMIN_EMAIL=""
ADMIN_PASSWORD=""
NEW_USERNAME=""
NEW_EMAIL=""
NEW_PASSWORD=""
WORKSPACE_NAME=""
SKIP_WORKSPACE=false

# Parse command line arguments
while getopts "U:t:a:A:u:e:p:w:sh" opt; do
  case $opt in
    U)
      CODER_URL="$OPTARG"
      ;;
    t)
      TEMPLATE_NAME="$OPTARG"
      ;;
    a)
      ADMIN_EMAIL="$OPTARG"
      ;;
    A)
      ADMIN_PASSWORD="$OPTARG"
      ;;
    u)
      NEW_USERNAME="$OPTARG"
      ;;
    e)
      NEW_EMAIL="$OPTARG"
      ;;
    p)
      NEW_PASSWORD="$OPTARG"
      ;;
    w)
      WORKSPACE_NAME="$OPTARG"
      ;;
    s)
      SKIP_WORKSPACE=true
      ;;
    h)
      echo "Usage: $0 -a ADMIN_EMAIL -A ADMIN_PASS -u USERNAME -e EMAIL -p PASSWORD [-w WORKSPACE] [-t TEMPLATE] [-U URL] [-s]"
      echo ""
      echo "Creates a new Coder user and optionally their workspace."
      echo ""
      echo "Required:"
      echo "  -a EMAIL      Admin email for authentication"
      echo "  -A PASSWORD   Admin password for authentication"
      echo "  -u USERNAME   New user's username"
      echo "  -e EMAIL      New user's email"
      echo "  -p PASSWORD   New user's password"
      echo ""
      echo "Optional:"
      echo "  -w WORKSPACE  Workspace name (default: USERNAME-workspace)"
      echo "  -t TEMPLATE   Template name (default: docker-workspace)"
      echo "  -U URL        Coder URL (default: http://localhost:8446)"
      echo "  -s            Skip workspace creation (user only)"
      echo "  -h            Show this help"
      echo ""
      echo "Examples:"
      echo "  $0 -a admin@example.com -A adminpass -u john -e john@example.com -p johnpass"
      echo "  $0 -a admin@example.com -A adminpass -u john -e john@example.com -p johnpass -w my-workspace"
      echo "  $0 -a admin@example.com -A adminpass -u john -e john@example.com -p johnpass -s"
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

if [ -z "$ADMIN_EMAIL" ] || [ -z "$ADMIN_PASSWORD" ]; then
  echo "ERROR: Admin credentials required (-a EMAIL -A PASSWORD)"
  exit 1
fi

if [ -z "$NEW_USERNAME" ] || [ -z "$NEW_EMAIL" ] || [ -z "$NEW_PASSWORD" ]; then
  echo "ERROR: New user details required (-u USERNAME -e EMAIL -p PASSWORD)"
  exit 1
fi

# Default workspace name
if [ -z "$WORKSPACE_NAME" ]; then
  WORKSPACE_NAME="${NEW_USERNAME}-workspace"
fi

###########################
# AUTHENTICATE AS ADMIN
###########################

echo "Authenticating as admin..."

TOKEN=$(curl -s -X POST "${CODER_URL}/api/v2/users/login" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"${ADMIN_EMAIL}\",\"password\":\"${ADMIN_PASSWORD}\"}" \
  | sed -n 's/.*"session_token":"\([^"]*\)".*/\1/p')

if [ -z "$TOKEN" ]; then
  echo "ERROR: Failed to authenticate as admin"
  exit 1
fi

echo "Authentication successful."

###########################
# GET ORGANIZATION ID
###########################

echo "Getting organization ID..."

ORG_ID=$(curl -s -X GET "${CODER_URL}/api/v2/organizations" \
  -H "Coder-Session-Token: ${TOKEN}" \
  | sed -n 's/.*"id":"\([^"]*\)".*/\1/p' | head -1)

if [ -z "$ORG_ID" ]; then
  echo "ERROR: Failed to get organization ID"
  exit 1
fi

echo "Organization ID: ${ORG_ID}"

###########################
# CREATE USER
###########################

echo "Creating user '${NEW_USERNAME}'..."

USER_RESULT=$(curl -s -X POST "${CODER_URL}/api/v2/users" \
  -H "Content-Type: application/json" \
  -H "Coder-Session-Token: ${TOKEN}" \
  -d "{
    \"username\": \"${NEW_USERNAME}\",
    \"email\": \"${NEW_EMAIL}\",
    \"password\": \"${NEW_PASSWORD}\",
    \"user_status\": \"active\",
    \"organization_ids\": [\"${ORG_ID}\"]
  }")

if echo "$USER_RESULT" | grep -q '"id"'; then
  USER_ID=$(echo "$USER_RESULT" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p' | head -1)
  echo "User created successfully (ID: ${USER_ID})"
elif echo "$USER_RESULT" | grep -q 'already exists'; then
  echo "User '${NEW_USERNAME}' already exists, skipping creation."
else
  echo "ERROR: Failed to create user"
  echo "$USER_RESULT"
  exit 1
fi

###########################
# CREATE WORKSPACE
###########################

if [ "$SKIP_WORKSPACE" = true ]; then
  echo "Skipping workspace creation (-s flag)."
  echo ""
  echo "Done! User '${NEW_USERNAME}' created."
  echo "Login: ${CODER_URL}"
  exit 0
fi

echo "Getting template ID for '${TEMPLATE_NAME}'..."

TEMPLATE_ID=$(curl -s -X GET "${CODER_URL}/api/v2/templates" \
  -H "Coder-Session-Token: ${TOKEN}" \
  | grep -o "\"id\":\"[^\"]*\",\"name\":\"${TEMPLATE_NAME}\"" \
  | sed -n 's/.*"id":"\([^"]*\)".*/\1/p' \
  | head -1)

if [ -z "$TEMPLATE_ID" ]; then
  # Try alternative parsing
  TEMPLATE_ID=$(curl -s -X GET "${CODER_URL}/api/v2/templates" \
    -H "Coder-Session-Token: ${TOKEN}" \
    | sed -n "s/.*\"id\":\"\([^\"]*\)\".*\"name\":\"${TEMPLATE_NAME}\".*/\1/p" \
    | head -1)
fi

if [ -z "$TEMPLATE_ID" ]; then
  echo "ERROR: Template '${TEMPLATE_NAME}' not found"
  echo "User created but workspace skipped."
  exit 1
fi

echo "Template ID: ${TEMPLATE_ID}"
echo "Creating workspace '${WORKSPACE_NAME}' for user '${NEW_USERNAME}'..."

WS_RESULT=$(curl -s -X POST "${CODER_URL}/api/v2/organizations/default/members/${NEW_USERNAME}/workspaces" \
  -H "Content-Type: application/json" \
  -H "Coder-Session-Token: ${TOKEN}" \
  -d "{
    \"name\": \"${WORKSPACE_NAME}\",
    \"template_id\": \"${TEMPLATE_ID}\"
  }")

if echo "$WS_RESULT" | grep -q '"id"'; then
  WS_ID=$(echo "$WS_RESULT" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p' | head -1)
  echo "Workspace created successfully (ID: ${WS_ID})"
elif echo "$WS_RESULT" | grep -q 'already exists'; then
  echo "Workspace '${WORKSPACE_NAME}' already exists."
else
  echo "ERROR: Failed to create workspace"
  echo "$WS_RESULT"
  exit 1
fi

###########################
# SUMMARY
###########################

echo ""
echo "====================================================="
echo "User and workspace created successfully!"
echo ""
echo "User:      ${NEW_USERNAME}"
echo "Email:     ${NEW_EMAIL}"
echo "Workspace: ${WORKSPACE_NAME}"
echo ""
echo "Login URL: ${CODER_URL}"
echo "====================================================="
