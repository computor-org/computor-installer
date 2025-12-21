#!/bin/bash
set -e

###########################
# ROOT CHECK
###########################

if [ "$EUID" -ne 0 ]; then
  echo "Bitte als root ausführen."
  exit 1
fi

###########################
# ENSURE SNAPD & CERTBOT
###########################

apt install -y snapd

systemctl restart snapd
sleep 3

snap install snapd || true
snap install core || true
snap refresh core || true

apt-get remove -y certbot || true
snap install --classic certbot || true
ln -sf /snap/bin/certbot /usr/bin/certbot

###########################
# RUN CERTBOT (INTERACTIVE)
###########################

echo ""
echo "-----------------------------------------------------"
echo "Starte Certbot. Bitte E-Mail eingeben und zustimmen."
echo "-----------------------------------------------------"
echo ""

certbot --nginx

###########################
# TEST RENEWAL
###########################

certbot renew --dry-run

###########################
# FINISHED
###########################

echo ""
echo "====================================================="
echo "HTTPS Konfiguration abgeschlossen."
echo "Seite erreichbar unter:"
echo "   https://${DOMAIN}/"
echo ""
echo "SSH Zugriff:"
echo "   ssh -p 2222 git@${DOMAIN}"
echo ""
echo "====================================================="
