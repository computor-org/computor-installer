# Computor Backend Installer

Dieses Repository enthält eine Suite von Scripten zur automatisierten Einrichtung eines Backends inklusive GitLab und Coder auf einem frischen Debian/Ubuntu-Server.

## 🚀 Schnellstart (Master Setup)

Verwende das `setup.sh` Script, um das gesamte System (Docker, Nginx, Backend, GitLab, Coder) in einem Rutsch zu installieren.

```bash
# Script laden
curl -O https://raw.githubusercontent.com/computor-org/computor-installer/main/setup.sh
chmod +x setup.sh

# Installation starten (Beispiel)
./setup.sh -d meinserver.at -m admin@meinserver.at -p MeinPasswort123 -g -c
```

### Optionen (`setup.sh`)
| Flag | Beschreibung | Erforderlich |
|------|-------------|--------------|
| `-d` | Hauptdomain des Servers (z.B. `computor.at`) | Ja |
| `-m` | E-Mail für SSL-Zertifikate (Let's Encrypt) | Ja |
| `-p` | Admin-Passwort für alle Dienste | Nein (Default: admin123) |
| `-g` | GitLab installieren (`git.domain.tld`) | Nein |
| `-c` | Coder installieren (`coder.domain.tld`) | Nein |

---

## 🛠 Einzel-Scripte (Standalone)

Jedes Script kann auch unabhängig verwendet werden.

### 1. Coder Setup (`coder-setup.sh`)

Installiert Coder in einem Docker-Container und konfiguriert Nginx als Reverse Proxy.

#### Nutzung
```bash
./coder-setup.sh -u coder.deinedomain.at [OPTIONS]
```

#### Optionen
| Flag | Beschreibung | Default |
|------|-------------|---------|
| `-u DOMAIN` | Domain für Coder | **Erforderlich** |
| `-p PORT` | Interner Port für den Container | `7080` |
| `-d DIRECTORY` | Installationsverzeichnis | `/opt/coder` |
| `-w` | Nginx-Konfiguration erstellen | Deaktiviert |
| `-i` | Docker & System-Updates installieren | Deaktiviert |

---

### 2. GitLab Setup (`gitlab-setup.sh`)

Richtet eine GitLab Omnibus Instanz via Docker ein.

#### Nutzung
```bash
./gitlab-setup.sh -u git.domain.at -p 8080 -s PASSWORT [OPTIONS]
```

#### Optionen
| Flag | Beschreibung | Mandatory | Default |
|------|-------------|-----------|---------|
| `-u DOMAIN` | Domain für GitLab | Ja | - |
| `-p PORT` | Host-Port für GitLab (HTTP) | Ja | `8080` |
| `-s PASSWORD` | Initiales Root-Passwort | Ja | - |
| `-d DIRECTORY` | Installationsverzeichnis | Nein | `/opt/gitlab-data` |
| `-w` | Nginx-Konfiguration erstellen | Nein | Deaktiviert |
| `-i` | Docker & System-Updates installieren | Nein | Deaktiviert |

---

### 3. SSL Zertifizierung (`certify.sh`)

Automatisiert den Bezug von SSL-Zertifikaten über Let's Encrypt für Nginx.

#### Nutzung
```bash
./certify.sh -d DOMAIN -m EMAIL
```

#### Details
- Installiert Certbot via `apt` oder `snap`.
- Erkennt bestehende Nginx-Konfigurationen für die Domain automatisch.
- Erzwingt eine HTTP-zu-HTTPS Weiterleitung.
- Richtet einen automatischen Erneuerungs-Check (Cron) ein.

---

## 🏗 Architektur-Hinweise

- **Reverse Proxy**: Alle Dienste binden sich an `127.0.0.1` (Localhost). Nur Nginx auf dem Host ist von außen über Port 80/443 erreichbar. Dies erhöht die Sicherheit drastisch.
- **SSL**: Jede Subdomain erhält ein eigenes Zertifikat.
- **Persistenz**: Alle Daten werden in `/opt/` gespeichert, um sie einfach sichern zu können.
- **Betriebssystem**: Optimiert für Debian 11/12 und Ubuntu 22.04/24.04.

## ⚠️ Voraussetzungen
- Ein Root-Benutzer oder Sudo-Berechtigungen.
- Die Domains/Subdomains müssen bereits per DNS (A-Record) auf die Server-IP zeigen.
