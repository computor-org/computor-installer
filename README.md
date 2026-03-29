# Computor Backend Installer

Dieses Repository enthält eine Suite von Scripten zur automatisierten Einrichtung eines professionellen Entwicklungs-Backends (GitLab & Coder) auf einem frischen Debian/Ubuntu-Server.

## 🚀 Schnellstart (Master Setup)

Verwende das `setup.sh` Script, um das gesamte System (Docker, Nginx, GitLab, Coder) inklusive SSL-Zertifikaten in einem Rutsch zu installieren.

```bash
# Script laden
curl -O https://raw.githubusercontent.com/computor-org/computor-installer/main/setup.sh
chmod +x setup.sh

# Installation starten
# WICHTIG: Passwörter mit Sonderzeichen (z.B. #) immer in einfache Anführungszeichen setzen!
sudo ./setup.sh -d meinserver.at -m admin@meinserver.at -p 'Mein#Passwort123' -g -c
```

### Optionen (`setup.sh`)
| Flag | Beschreibung | Erforderlich | Default |
|------|-------------|--------------|---------|
| `-d` | Hauptdomain des Servers (z.B. `computor.at`) | **Ja** | - |
| `-m` | E-Mail für SSL (Let's Encrypt) & Admin-Accounts | **Ja** | - |
| `-p` | Globales Admin-Passwort für alle Dienste | Nein | `admin123` |
| `-g` | GitLab installieren (`git.domain.tld`) | Nein | Deaktiviert |
| `-c` | Coder installieren (`coder.domain.tld`) | Nein | Deaktiviert |

---

## 🛠 Einzel-Scripte (Standalone)

Jedes Script kann auch unabhängig für gezielte Wartung oder isolierte Setups verwendet werden.

### 1. Coder Setup (`coder-setup.sh`)
Installiert Coder via Docker und legt automatisch einen Admin-Account an, damit die Instanz sofort geschützt ist.

```bash
./coder-setup.sh -u coder.domain.at -m admin@domain.at -s 'Passwort' -w
```

| Flag | Beschreibung | Default |
|------|-------------|---------|
| `-u` | Domain für Coder | **Erforderlich** |
| `-m` | E-Mail für den Admin-Account | **Erforderlich** |
| `-s` | Passwort für den Admin-Account | **Erforderlich** |
| `-w` | Nginx-Konfiguration (inkl. IPv6) erstellen | Deaktiviert |
| `-p` | Interner Port für den Container | `7080` |
| `-d` | Installationsverzeichnis | `/opt/computor/coder` |

### 2. GitLab Setup (`gitlab-setup.sh`)
Richtet eine GitLab-Instanz (EE) via Docker-Compose ein.

```bash
./gitlab-setup.sh -u git.domain.at -s 'Passwort' -w
```

| Flag | Beschreibung | Default |
|------|-------------|---------|
| `-u` | Domain für GitLab | **Erforderlich** |
| `-s` | Initiales Root-Passwort | **Erforderlich** |
| `-w` | Nginx-Konfiguration (inkl. IPv6) erstellen | Deaktiviert |
| `-p` | Host-Port für GitLab (HTTP) | `8080` |
| `-d` | Installationsverzeichnis | `/opt/gitlab-data` |

### 3. SSL Zertifizierung (`certify.sh`)
Automatisiert den Bezug von Let's Encrypt Zertifikaten für Nginx.

```bash
./certify.sh -d domain.at -m email@domain.at
```
- Erzwingt HTTP-zu-HTTPS Weiterleitung.
- Erstellt automatisch einen Renewal-Check.
- Funktioniert nahtlos mit den generierten Nginx-Configs.

---

## 🏗 Architektur & Features

- **Dual-Stack Support**: Alle Nginx-Konfigurationen unterstützen nativ **IPv4 und IPv6** (`listen [::]:80`).
- **Status-Report**: Nach Abschluss von `setup.sh` wird eine übersichtliche Tabelle ausgegeben, die den Status jeder Komponente (App & SSL) anzeigt.
- **Sicherheit**: 
    - Dienste binden sich nur an `127.0.0.1`. Zugriff erfolgt ausschließlich über den Nginx Reverse Proxy.
    - Automatisches Admin-Provisioning für Coder (verhindert offene Registrierung nach Installation).
- **Persistenz**: Alle relevanten Daten werden zentral unter `/opt/computor/` verwaltet.

## ⚠️ Voraussetzungen
- **DNS**: Die (Sub-)Domains müssen bereits per **A-Record** (und optional AAAA-Record) auf die Server-IP zeigen.
- **OS**: Optimiert für Debian 12 (empfohlen) und Ubuntu 22.04/24.04.
- **User**: Ausführung als `root` oder mit `sudo` Rechten.
