# GitLab Installation

Quick setup script for deploying GitLab EE with Docker.

## Prerequisites

- Docker with Docker Compose plugin
- Root access (for default installation directory)

## Usage

```bash
./install.sh [OPTIONS]
```

## Options

| Flag | Description | Default |
|------|-------------|---------|
| `-d DIRECTORY` | Installation directory | `/root/gitlab` |
| `-P PORT` | GitLab HTTP port | (prompted) |
| `-D DOMAIN` | GitLab domain | (prompted) |
| `-s SSH_PORT` | GitLab SSH port | `2222` |
| `-p PASSWORD` | Root admin password | (prompted) |
| `-h` | Show help | - |

## Examples

```bash
# Interactive mode (prompts for all required values)
./install.sh

# Non-interactive with domain and port (prompts for password)
./install.sh -D gitlab.example.com -P 8080

# Fully non-interactive
./install.sh -D gitlab.example.com -P 8080 -p mysecretpassword

# Custom directory and SSH port
./install.sh -d /opt/gitlab -s 2222 -D gitlab.example.com -P 8080

# Show help
./install.sh -h
```

## What Gets Created

```
/root/gitlab/
└── docker-compose.yml    # GitLab EE service
```

## Post-Installation

1. Wait for GitLab to initialize (check with `docker logs -f gitlab`)
2. Access GitLab at `http://your-domain:port`
3. Login with username `root` and your configured password
4. Configure SSL/TLS with a reverse proxy for production use

## Git Access

```bash
# Clone via SSH
git clone ssh://git@your-domain:2222/group/project.git

# Clone via HTTP
git clone http://your-domain:port/group/project.git
```
