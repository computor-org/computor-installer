# Computor Backend Installer

Dieses Repository enthält eine Suite von Scripten zur automatisierten Einrichtung eines professionellen Entwicklungs-Backends (GitLab, Coder & Computor Backend) auf einem frischen Debian/Ubuntu-Server.

## 🚀 Schnellstart (Master Setup)

Verwende das `setup.sh` Script, um das gesamte Ökosystem inklusive Docker und Nginx in einem Rutsch zu installieren.

```bash
# Script laden
curl -O https://raw.githubusercontent.com/computor-org/computor-installer/main/setup.sh
chmod +x setup.sh

# Installation starten (Beispiel: Alle Dienste, inklusive SSL)
# WICHTIG: Passwörter mit Sonderzeichen (z.B. #) immer in einfache Anführungszeichen setzen!
sudo ./setup.sh -d meinserver.eu -m admin@meinserver.eu -p 'Mein#Passwort123' -g -c -b
```

### Optionen (`setup.sh`)
| Flag | Beschreibung | Erforderlich | Default |
|------|-------------|--------------|---------|
| `-d` | Hauptdomain des Servers (z.B. `computor.eu`) | **Ja** | - |
| `-m` | E-Mail für SSL (Let's Encrypt) & Admin-Accounts | **Ja** | - |
| `-p` | Globales Passwort für GitLab & Coder | Nein | `admin123` |
| `-g` | GitLab installieren (`git.domain.tld`) auf Port 9080 | Nein | Deaktiviert |
| `-c` | Coder installieren (`coder.domain.tld`) auf Port 7080 | Nein | Deaktiviert |
| `-b` | Computor Backend installieren (`api.domain.tld`) auf Port 8080 | Nein | Deaktiviert |
| `-n` | **No-SSL**: Überspringt die SSL-Zertifizierung (Hilfreich bei Rate-Limits) | Nein | `false` |

---

## 🛠 Einzel-Scripte (Standalone)

### 1. Computor Backend Setup (`backend-setup.sh`)
Klone das Backend-Repository, generiert eine `.env` aus dem Template und erzeugt individuelle Passwörter für alle internen Dienste.

```bash
./backend-setup.sh -u api.domain.eu -m admin@domain.eu -s 'Passwort' -w
```
- **Debian 13 Fixes**: 
  - Entfernt automatisch inkompatible MATLAB-Worker-Dienste.
  - Patcht Python 3.10 Abhängigkeiten auf generisches `python3` (Support für Debian Trixie).
  - Optimiert den Coder-CLI Build-Prozess (direkter Binary-Download statt Install-Script).
- **Erweitertes Routing**: Konfiguriert Traefik-Regeln für alle API-Endpunkte (`/api`, `/auth`, `/v1`, `/user`, `/docs`, `/coder`), um 404-Fehler im Frontend zu vermeiden.
- **Vollautomatisch**: Erzeugt alle kryptografischen Secrets (JWT, Auth, Coder-API) via OpenSSL.

### 2. Coder Setup (`coder-setup.sh`)
Installiert Coder via Docker und legt automatisch einen Admin-Account an.

```bash
./coder-setup.sh -u coder.domain.eu -m admin@domain.eu -s 'Passwort' -w
```
- **Admin-Force**: Enthält einen Fallback-Mechanismus, der die Admin-Erstellung via CLI erzwingt, falls die automatische Provisionierung beim ersten Start fehlschlägt.
- **Docker-Integration**: Mappt die Docker-GID automatisch, damit Coder-Workspaces nahtlos Docker-Container starten können.

### 3. GitLab Setup (`gitlab-setup.sh`)
Richtet eine GitLab-Instanz (EE) via Docker-Compose ein. 

```bash
./gitlab-setup.sh -u git.domain.eu -s 'Passwort' -p 9080 -w
```
- Standardmäßig auf Port **9080** vorkonfiguriert (über `setup.sh`).
- Automatische Setzung des initialen Root-Passworts.

### 4. SSL Zertifizierung (`certify.sh`)
Automatisiert den Bezug von Let's Encrypt Zertifikaten für Nginx inklusive automatischer HTTP-zu-HTTPS Umleitung.

---

## 🏗 Architektur & Ports

| Dienst | Subdomain (Beispiel) | Interner Port |
|--------|----------------------|---------------|
| **GitLab** | `git.computor.eu` | `9080` |
| **Coder** | `coder.computor.eu` | `7080` |
| **Backend (API/Traefik)** | `api.computor.eu` | `8080` |

- **Dual-Stack Support**: Alle Nginx-Konfigurationen unterstützen nativ **IPv4 und IPv6**.
- **No-SSL Modus**: Mit dem Flag `-n` wird Nginx nur für Port 80 konfiguriert. Ideal für lokale Tests oder Entwicklungsumgebungen.
- **Status-Report**: Das Master-Skript liefert am Ende eine detaillierte Zusammenfassung aller installierten Komponenten und deren SSL-Status.

## ⚠️ Voraussetzungen
- **DNS**: A/AAAA-Records für alle Subdomains (`api`, `git`, `coder`) müssen auf die Server-IP zeigen. 
- **Let's Encrypt**: Achte auf das Rate-Limit. Nutze im Zweifel das `-n` Flag für die initiale Einrichtung.
- **OS**: Optimiert für **Debian 13 (Trixie)**, Debian 12 und Ubuntu 22.04/24.04.
- **Hardware**: Mindestens 4GB RAM erforderlich (8GB empfohlen bei Nutzung aller Dienste).
