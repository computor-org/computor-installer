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