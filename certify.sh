#!/bin/bash
set -e

DOMAIN=""
EMAIL=""

while getopts "d:m:h" opt; do
  case $opt in
    d) DOMAIN="$OPTARG" ;;
    m) EMAIL="$OPTARG" ;;
    h) echo "Usage: $0 -d domain -m email"; exit 0 ;;
  esac
done

if [ -z "$DOMAIN" ] || [ -z "$EMAIL" ]; then echo "Domain und Email erforderlich"; exit 1; fi

if ! command -v certbot &> /dev/null; then
    echo "Installiere Certbot..."
    apt-get update && apt-get install -y python3-certbot-nginx
fi

echo "Beziehe Zertifikat für $DOMAIN..."
certbot --nginx \
  --non-interactive \
  --agree-tos \
  -m "$EMAIL" \
  -d "$DOMAIN" \
  --redirect

# Automatischer Renewal Test
certbot renew --dry-run
