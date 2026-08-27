# Computor Backend Installer

This repository contains a small set of scripts to automate the setup of a production-ready development backend stack on a fresh Debian/Ubuntu server.

It can install:
- GitLab
- Coder
- Computor Backend
- Nginx and TLS via Let's Encrypt
- Docker if needed

## 🚀 Quick start

Use `setup.sh` to install the full stack in one step.

```bash
# Download the installer
curl -fsSL https://raw.githubusercontent.com/computor-org/computor-installer/main/setup.sh -o setup.sh
chmod +x setup.sh

# Example: install all services with SSL enabled
# Important: wrap passwords with special characters in single quotes
sudo ./setup.sh -d meinserver.at -m admin@meinserver.at -p 'Mein#Passwort123' -g -c -b
```

This will configure the services for:
- GitLab: `git.example.com`
- Coder: `coder.example.com`
- Computor Backend: `example.com` or the configured domain

If you want to skip SSL and use HTTP only, add `-n`:

```bash
sudo ./setup.sh -d meinserver.at -m admin@meinserver.at -n -g -c -b
```

## Options (`setup.sh`)

| Flag | Description | Required | Default |
|------|-------------|----------|---------|
| `-d` | Main server domain | Yes | - |
| `-m` | Email for SSL and admin accounts | Yes | - |
| `-p` | Global password for GitLab, Coder and backend | No | `admin123` |
| `-g` | Install GitLab (`git.domain.tld`) on port `9080` | No | Disabled |
| `-c` | Install Coder (`coder.domain.tld`) on port `7080` | No | Disabled |
| `-b` | Install Computor Backend (`domain.tld`) on port `8080` | No | Disabled |
| `-n` | Skip SSL / Let's Encrypt and use HTTP only | No | `false` |

---

## 🛠 Standalone scripts

### 1. Computor Backend setup (`backend-setup.sh`)

Clones the backend repository, creates the `.env` configuration, and generates the required secrets.

```bash
./backend-setup.sh -u api.domain.eu -m admin@domain.eu -s 'Password' -w
```

- Debian 13 compatibility fixes
- Automatic patching for Python 3.10 references to generic `python3`
- Optional Nginx setup via `-w`
- Generates the required JWT and auth secrets automatically

### 2. Coder setup (`coder-setup.sh`)

Installs Coder with Docker and creates an admin user automatically.

```bash
./coder-setup.sh -u coder.domain.eu -m admin@domain.eu -s 'Password' -w
```

- Creates a default admin account automatically
- Maps Docker group permissions so workspaces can run containerized jobs
- Optional Nginx setup via `-w`

### 3. GitLab setup (`gitlab-setup.sh`)

Creates a GitLab instance with Docker Compose.

```bash
./gitlab-setup.sh -u git.domain.eu -s 'Password' -p 9080 -w
```

- Uses port `9080` by default
- Sets the initial root password automatically
- Optional Nginx setup via `-w`

### 4. SSL certificate setup (`certify.sh`)

Requests a Let's Encrypt certificate for a domain and enables automatic HTTP-to-HTTPS redirect.

```bash
./certify.sh -d example.com -m admin@example.com
```

---

## 🏗 Architecture and ports

| Service | Example subdomain | Internal port |
|---------|-------------------|---------------|
| GitLab | `git.computor.eu` | `9080` |
| Coder | `coder.computor.eu` | `7080` |
| Backend | `api.computor.eu` | `8080` |

- Nginx configurations support IPv4 and IPv6 natively
- `-n` disables SSL and keeps the setup on port 80 only
- `setup.sh` prints a final status summary after installation

## ⚠️ Requirements

- DNS records for the required subdomains must point to the server IP
- Valid domain ownership for Let's Encrypt certificate requests
- Ubuntu 22.04/24.04 or Debian 12/13
- Sudo/root access
- At least 4 GB RAM recommended (8 GB recommended for all services)
