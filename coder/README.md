# Coder Installation

Quick setup script for deploying Coder with Docker.

## Prerequisites

- Docker with Docker Compose plugin
- Root access (for default installation directory)

## Quick Start

```bash
# Basic installation (first signup becomes admin)
./install.sh

# With pre-created admin user
./install.sh -u admin -e admin@example.com -w secret
```

## Usage

```bash
./install.sh [OPTIONS]
```

## Options

| Flag | Description | Default |
|------|-------------|---------|
| `-d DIRECTORY` | Installation directory | `/root/coder` |
| `-p PASSWORD` | PostgreSQL password | `coder_password` |
| `-Q PGPORT` | PostgreSQL host port | `5439` |
| `-P PORT` | Coder port | (prompted) |
| `-D DOMAIN` | Coder domain | (prompted) |
| `-H` | Use HTTP instead of HTTPS | HTTPS |
| `-u USERNAME` | Admin username (optional) | - |
| `-e EMAIL` | Admin email (optional) | - |
| `-w PASSWORD` | Admin password (optional) | - |
| `-t TEMPLATE` | Template name | `docker-workspace` |
| `-i IMAGE` | Workspace image name | `localhost:5000/computor-workspace:latest` |
| `-h` | Show help | - |

## Examples

```bash
# Interactive mode (no admin, first signup = admin)
./install.sh

# Production (HTTPS)
./install.sh -D example.com -P 8443

# Local development (HTTP)
./install.sh -D localhost -P 8443 -H

# With admin user
./install.sh -D example.com -P 8443 -u admin -e admin@example.com -w secretpass

# Custom directory and database password
./install.sh -d /opt/coder -p mydbpassword -D example.com -P 8443
```

## Admin User Management

### During Installation

Provide admin credentials to pre-create an admin user:

```bash
./install.sh -D example.com -P 8443 -u admin -e admin@example.com -w secret
```

### After Installation

Use the standalone script to create admin users anytime:

```bash
# Interactive
./setup-admin.sh

# Non-interactive
./setup-admin.sh -u admin -e admin@example.com -p secret

# Specify coder directory
./setup-admin.sh -d /opt/coder -u admin -e admin@example.com -p secret
```

### Why Pre-Create Admin?

By default, Coder grants admin privileges to the **first user who signs up**. This can be a security concern. Pre-creating an admin user ensures:

- You control who gets admin access
- No race condition on first signup
- Predictable initial credentials

### How It Works

The docker-compose orchestrates multiple services with proper dependencies:

```
1. registry starts → healthy (local Docker registry on port 5000)
2. image-builder runs:
   - Waits for registry
   - Builds workspace Dockerfile
   - Pushes to localhost:5000/computor-workspace:latest
3. database starts → healthy
4. coder starts → healthy (waits for database + image-builder)
5. coder-admin-setup runs:
   - If admin credentials provided → creates admin
   - If no credentials → skips (exits successfully)
   - If admin exists → skips gracefully
6. coder-template-setup runs:
   - If admin credentials provided → logs in via API, pushes template
   - If no credentials → skips
```

All services share a `coder-network` bridge network, allowing workspace containers to connect back to Coder.

Single docker-compose.yml handles all cases. No conditional files, no sleep hacks - fully declarative with `depends_on: service_completed_successfully`.

Re-running `docker compose up -d` is safe (idempotent).

## What Gets Created

```
/root/coder/
├── docker-compose.yml          # Full stack: Coder + PostgreSQL + registry + setup containers
├── .env                        # Environment variables for docker-compose
├── setup-admin.sh              # Admin user creation script (for later use)
└── templates/docker/           # Workspace template files
    ├── main.tf                 # Terraform configuration
    └── Dockerfile              # Workspace image (with computor extension)
```

### Docker Services

| Service | Description |
|---------|-------------|
| `registry` | Local Docker registry (port 5000) for workspace images |
| `image-builder` | Builds and pushes workspace image to registry |
| `coder` | Main Coder server |
| `coder-admin-setup` | Creates admin user (if credentials provided) |
| `coder-template-setup` | Creates and pushes template (if credentials provided) |
| `database` | PostgreSQL database |

## Post-Installation

1. Access Coder at `https://your-domain`
2. Login with your admin credentials (if created) or sign up
3. Template is auto-created if admin credentials were provided, otherwise import manually

## Authentication Options

Coder supports multiple authentication methods. Edit `docker-compose.yml` to configure:

### Disable Password Auth (OIDC only)
```yaml
environment:
  CODER_DISABLE_PASSWORD_AUTH: "true"
```

### OIDC Configuration
```yaml
environment:
  CODER_OIDC_ISSUER_URL: "https://auth.example.com"
  CODER_OIDC_CLIENT_ID: "coder"
  CODER_OIDC_CLIENT_SECRET: "your-secret"
  CODER_OIDC_EMAIL_DOMAIN: "example.com"
  CODER_OIDC_ALLOW_SIGNUPS: "false"
```

### GitHub OAuth
```yaml
environment:
  CODER_OAUTH2_GITHUB_CLIENT_ID: "your-client-id"
  CODER_OAUTH2_GITHUB_CLIENT_SECRET: "your-secret"
  CODER_OAUTH2_GITHUB_ALLOW_SIGNUPS: "false"
```

After editing, restart Coder:
```bash
cd /root/coder
docker compose up -d
```

## Files

| File | Description |
|------|-------------|
| `install.sh` | Main installation script |
| `stop.sh` | Stop/cleanup script |
| `setup-admin.sh` | Standalone admin user creation |
| `create-user.sh` | Create user + workspace via API |
| `docker-compose.yml` | Docker Compose configuration |
| `main.tf` | Terraform template for workspaces |
| `Dockerfile` | Workspace image with computor extension |

## Stopping Coder

```bash
# Stop services (keep data)
./stop.sh

# Stop and remove all data
./stop.sh -v

# Custom directory
./stop.sh -d /opt/coder
```

## Creating Users

Use `create-user.sh` to create users and their workspaces via the Coder API:

```bash
# Create user with workspace
./create-user.sh \
  -a admin@example.com -A adminpass \
  -u johndoe -e john@example.com -p userpass

# Create user with full name (for git config)
./create-user.sh \
  -a admin@example.com -A adminpass \
  -u johndoe -e john@example.com -p userpass \
  -n "John Doe"

# Create user with custom workspace name
./create-user.sh \
  -a admin@example.com -A adminpass \
  -u johndoe -e john@example.com -p userpass \
  -w my-custom-workspace

# Create user only (no workspace)
./create-user.sh \
  -a admin@example.com -A adminpass \
  -u johndoe -e john@example.com -p userpass \
  -s
```

### Options

| Flag | Description |
|------|-------------|
| `-a EMAIL` | Admin email (required) |
| `-A PASSWORD` | Admin password (required) |
| `-u USERNAME` | New user's username (required) |
| `-e EMAIL` | New user's email (required) |
| `-p PASSWORD` | New user's password (required) |
| `-n NAME` | Full name / display name (used for git config) |
| `-w WORKSPACE` | Workspace name (default: USERNAME-workspace) |
| `-t TEMPLATE` | Template name (default: docker-workspace) |
| `-U URL` | Coder URL (default: http://localhost:8446) |
| `-s` | Skip workspace creation |

## Architecture

### Network

All services run on a shared `coder-network` bridge network. Workspace containers created by Terraform also join this network, allowing agents to connect to the Coder server via `coder:7080` internally.

```
┌─────────────────────────────────────────────────────────────┐
│                     coder-network                           │
│                                                             │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌─────────────┐ │
│  │ registry │  │ database │  │  coder   │  │  workspace  │ │
│  │  :5000   │  │  :5432   │  │  :7080   │◄─│  containers │ │
│  └──────────┘  └──────────┘  └──────────┘  └─────────────┘ │
│                                    │                        │
└────────────────────────────────────┼────────────────────────┘
                                     │
                              ┌──────▼──────┐
                              │  Host:PORT  │
                              │  (external) │
                              └─────────────┘
```

### Image Registry

The local registry (`localhost:5000`) stores pre-built workspace images. This avoids rebuilding images for each workspace, making startup much faster.
