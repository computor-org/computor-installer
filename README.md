# Computor Backend Installer

Dieses Repository enthält eine Suite von Scripten zur automatisierten Einrichtung eines professionellen Entwicklungs-Backends (GitLab, Coder & Computor Backend) auf einem frischen Debian/Ubuntu-Server.

## 🚀 Schnellstart (Master Setup)

Verwende das `setup.sh` Script, um das gesamte Ökosystem inklusive Docker, Nginx und SSL-Zertifikaten in einem Rutsch zu installieren.

```bash
# Script laden
curl -O https://raw.githubusercontent.com/computor-org/computor-installer/main/setup.sh
chmod +x setup.sh

# Installation starten (Beispiel mit GitLab, Coder und Backend)
# WICHTIG: Passwörter mit Sonderzeichen (z.B. #) immer in einfache Anführungszeichen setzen!
sudo ./setup.sh -d meinserver.at -m admin@meinserver.at -p 'Mein#Passwort123' -g -c -b
```

### Optionen (`setup.sh`)
| Flag | Beschreibung | Erforderlich | Default |
|------|-------------|--------------|---------|
| `-d` | Hauptdomain des Servers (z.B. `computor.at`) | **Ja** | - |
| `-m` | E-Mail für SSL (Let's Encrypt) & Admin-Accounts | **Ja** | - |
| `-p` | Globales Passwort für GitLab & Coder | Nein | `admin123` |
| `-g` | GitLab installieren (`git.domain.tld`) auf Port 9080 | Nein | Deaktiviert |
| `-c` | Coder installieren (`coder.domain.tld`) auf Port 7080 | Nein | Deaktiviert |
| `-b` | Computor Backend installieren (`api.domain.tld`) auf Port 8080 | Nein | Deaktiviert |

---

## 🛠 Einzel-Scripte (Standalone)

### 1. Computor Backend Setup (`backend-setup.sh`)
Klone das Backend-Repository, generiert eine `.env` aus dem Template und erzeugt **hochgeladene, individuelle Passwörter** für alle internen Dienste (Postgres, Redis, Minio, etc.).

```bash
./backend-setup.sh -u api.domain.at -m admin@domain.at -w
```
- **Vollautomatisch**: Erzeugt alle kryptografischen Secrets (JWT, Auth, Coder-API) via OpenSSL.
- **Isoliert**: Jede Datenbank erhält ein eigenes, zufälliges Passwort.
- **Nginx**: Konfiguriert den Proxy-Zugriff auf das interne Traefik-Gateway (Port 8080).

### 2. Coder Setup (`coder-setup.sh`)
Installiert Coder via Docker und legt automatisch einen Admin-Account an.

```bash
./coder-setup.sh -u coder.domain.at -m admin@domain.at -s 'Passwort' -w
```
- Nutzt Port 7080.
- Verhindert die offene Registrierung durch automatisches Admin-Provisioning.

### 3. GitLab Setup (`gitlab-setup.sh`)
Richtet eine GitLab-Instanz (EE) via Docker-Compose ein.

```bash
./gitlab-setup.sh -u git.domain.at -s 'Passwort' -p 9080 -w
```
- **Hinweis**: Standardmäßig auf Port **9080**, um Konflikte mit dem Backend-Gateway (8080) zu vermeiden.

### 4. SSL Zertifizierung (`certify.sh`)
Automatisiert den Bezug von Let's Encrypt Zertifikaten für Nginx.

---

## 🏗 Architektur & Ports

| Dienst | Subdomain (Beispiel) | Interner Port |
|--------|----------------------|---------------|
| **GitLab** | `git.computor.at` | `9080` |
| **Coder** | `coder.computor.at` | `7080` |
| **Backend (API)** | `api.computor.at` | `8080` |

- **Dual-Stack Support**: Alle Nginx-Konfigurationen unterstützen nativ **IPv4 und IPv6**.
- **Security**: Dienste binden sich an `127.0.0.1`. Der Zugriff erfolgt gesichert über den Nginx Reverse Proxy (Port 80/443).
- **Status-Report**: Das Master-Skript liefert am Ende eine Zusammenfassung aller installierten Komponenten.
- **Individuelle Secrets**: Das Backend-Setup generiert für jedes Deployment einzigartige Token und Passwörter, die am Ende der Installation angezeigt werden.

## ⚠️ Voraussetzungen
- **DNS**: A-Records für alle Subdomains (`api`, `git`, `coder`) müssen auf die Server-IP zeigen. **Lösche vorhandene AAAA-Records**, falls IPv6 nicht explizit auf dem Server konfiguriert ist, um SSL-Fehler zu vermeiden.
- **OS**: Optimiert für Debian 12 (empfohlen) und Ubuntu 22.04/24.04.
- **Hardware**: Mindestens 4GB RAM empfohlen (vor allem für GitLab).
