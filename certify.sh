#!/bin/bash
set -e

###########################
# CLI PARAMETERS
###########################

# Default values
DOMAIN=""
EMAIL=""

# Parse command line arguments
while getopts "d:m:h" opt; do
  case $opt in
    d)
      DOMAIN="$OPTARG"
      ;;
    m)
      EMAIL="$OPTARG"
      ;;
    h)
      echo "Usage: $0 -d DOMAIN -m EMAIL"
      echo "  -d DOMAIN  Die Domain für das SSL Zertifikat"
      echo "  -m EMAIL   E-Mail für Certbot Benachrichtigungen"
      echo "  -h         Diese Hilfe anzeigen"
      exit 0
      ;;
    \?)
      echo "Ungültige Option: -$OPTARG" >&2
      exit 1
      ;;
  esac
done

# Check if mandatory parameters are set
if [ -z "$DOMAIN" ] || [ -z "$EMAIL" ]; then
  echo "Fehler: Domain (-d) und E-Mail (-m) sind erforderlich."
  echo "Beispiel: $0 -d computor.at -m admin@computor.at"
  exit 1
fi

###########################
# ROOT CHECK
###########################

if [ "$EUID" -ne 0 ]; then
  echo "Bitte als root ausführen."
  exit 1
fi

echo "Konfiguration gestartet für Domain: $DOMAIN (E-Mail: $EMAIL)"

###########################
# ENSURE SNAPD & CERTBOT
###########################

echo "Installiere Snapd und Certbot..."

apt update
apt install -y snapd

systemctl restart snapd
# Kurze Pause um sicherzustellen, dass snapd bereit ist
sleep 3

snap install core || true
snap refresh core || true

# Alte Certbot Versionen entfernen falls vorhanden
apt-get remove -y certbot || true

# Certbot via Snap installieren
snap install --classic certbot || true
ln -sf /snap/bin/certbot /usr/bin/certbot

###########################
# RUN CERTBOT (NON-INTERACTIVE)
###########################

echo ""
echo "-----------------------------------------------------"
echo "Beziehe SSL-Zertifikat von Let's Encrypt..."
echo "-----------------------------------------------------"
echo ""

# --non-interactive: Keine Fragen stellen
# --agree-tos: Nutzungsbedingungen zustimmen
# -m: E-Mail für wichtige Benachrichtigungen
# --nginx: Automatische Nginx Konfiguration
# -d: Die gewünschte Domain
# --redirect: Erzwingt die Weiterleitung von HTTP auf HTTPS
certbot --nginx \
  --non-interactive \
  --agree-tos \
  -m "$EMAIL" \
  -d "$DOMAIN" \
  --redirect

###########################
# TEST RENEWAL
###########################

echo "Teste automatische Erneuerung (Dry-Run)..."
certbot renew --dry-run

###########################
# FINISHED
###########################

echo ""
echo "====================================================="
echo "HTTPS Konfiguration erfolgreich abgeschlossen."
echo "Seite erreichbar unter:"
echo "   https://${DOMAIN}/"
echo ""
echo "Die Zertifikate werden automatisch durch Certbot erneuert."
echo "====================================================="
