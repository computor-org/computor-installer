# Coder Setup Script

Quick setup script for Coder deployment with Docker and optional Nginx configuration.

## Usage

```bash
./coder-setup.sh [OPTIONS]
```

## Options

| Flag | Description | Default |
|------|-------------|---------|
| `-d DIRECTORY` | Coder installation directory | `/root/coder` |
| `-i` | Install Docker and system updates | Disabled |
| `-w` | Configure Nginx webserver | Disabled |
| `-h` | Show help | - |

## Examples

```bash
# Basic installation (Docker and Nginx must already be installed)
./coder-setup.sh

# Install everything (Docker + Coder + Nginx)
./coder-setup.sh -i -w

# Custom directory without Docker/Nginx
./coder-setup.sh -d /opt/coder

# Full custom setup
./coder-setup.sh -d /opt/coder -i -w
```

## Requirements

- Root access
- Debian-based Linux system (if using `-i` flag)
- Domain name and port will be prompted during execution

---

# GitLab Setup Script

Automated setup for GitLab Omnibus using Docker and optional Nginx proxy.

## Usage

```bash
./gitlab-setup.sh -u DOMAIN -p PORT -s PASSWORD [OPTIONS]
```

## Options

| Flag | Description | Mandatory | Default |
|------|-------------|-----------|---------|
| `-u DOMAIN` | Domain for GitLab (e.g., git.example.com) | Yes | - |
| `-p PORT` | Internal Port for GitLab container | Yes | - |
| `-s PASSWORD` | Initial Admin (root) password | Yes | - |
| `-d DIRECTORY` | Installation directory | No | `/root/dev-gitlab` |
| `-i` | Install Docker and system updates | No | Disabled |
| `-w` | Configure Nginx webserver | No | Disabled |
| `-h` | Show help | No | - |

## Examples

```bash
# Full installation including Docker and Nginx
./gitlab-setup.sh -u git.computor.at -p 8080 -s MySecretPass123 -i -w

# Only create GitLab configuration in custom directory
./gitlab-setup.sh -u git.computor.at -p 8080 -s MySecretPass123 -d /opt/gitlab
```

---

# Certify Script

Fully automated SSL certificate acquisition via Let's Encrypt and Certbot for Nginx.

## Usage

```bash
./certify.sh -d DOMAIN -m EMAIL [OPTIONS]
```

## Options

| Flag | Description | Mandatory |
|------|-------------|-----------|
| `-d DOMAIN` | The domain to secure (must point to this server) | Yes |
| `-m EMAIL` | Email for Let's Encrypt notifications | Yes |
| `-h` | Show help | No |

## Examples

```bash
# Secure the domain without any interactive prompts
./certify.sh -d git.computor.at -m admin@computor.at
```

## Notes

- This script installs Certbot via `snapd`.
- It automatically configures Nginx to redirect all HTTP traffic to HTTPS.
- A dry-run for automatic renewal is performed at the end of the script.
