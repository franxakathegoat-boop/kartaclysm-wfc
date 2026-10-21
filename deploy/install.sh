#!/usr/bin/env bash
# One-command Kartaclysm WFC deploy on a fresh Debian 12/13 or Ubuntu 22.04+ VPS (run as root):
#   git clone https://github.com/franxakathegoat-boop/kartaclysm-wfc /opt/kartaclysm-wfc
#   DOMAIN=kartaclysm.net ACME_EMAIL=you@example.com /opt/kartaclysm-wfc/deploy/install.sh
# Before running: copy the signed payload (client/out/<domain>/payload) to deploy/payload/, and point
# DNS for <domain> and *.<domain> (A record, plus AAAA if you like) at this server.
set -euo pipefail
cd "$(dirname "$0")"
: "${DOMAIN:?set DOMAIN, e.g. DOMAIN=kartaclysm.net}"
: "${ACME_EMAIL:?set ACME_EMAIL for the Let's Encrypt account}"
[ "$(id -u)" = 0 ] || { echo "run as root"; exit 1; }
[ -f payload/stage1v1.bin ] || { echo "deploy/payload/ missing: run client/build-client.sh $DOMAIN on the build box and copy client/out/$DOMAIN/payload here"; exit 1; }
# wwfc signs every payload download on the fly, so the signing key must be on the server (never in git).
[ -f payload/private-key.pem ] || { echo "deploy/payload/private-key.pem missing (scp it from the build box, chmod 600)"; exit 1; }
chmod 600 payload/private-key.pem

# 1. Docker
if ! command -v docker >/dev/null || ! docker compose version >/dev/null 2>&1; then
  apt-get update -q && apt-get install -y -q ca-certificates curl
  curl -fsSL https://get.docker.com | sh
fi

# 2. Firewall: SSH + game ports + HTTPS stats page
apt-get install -y -q ufw >/dev/null
ufw allow 22/tcp
ufw allow 80/tcp        # NAS (Wii login, plain HTTP) + payload
ufw allow 443/tcp       # Caddy: public stats page / API (TLS)
ufw allow 28910/tcp     # server browser (matchmaking list)
ufw allow 29900/tcp     # GPCM (login, friends, presence)
ufw allow 29901/tcp     # GPSP (profile search)
ufw allow 29920/tcp     # gamestats
ufw allow 27900/udp     # QR2 (rooms / heartbeats, VR reports)
ufw allow 27901/udp     # NATNEG
ufw --force enable

# 3. Secrets (kept only on the VPS)
if [ ! -f .env ]; then
  umask 077
  cat > .env <<ENV
DOMAIN=$DOMAIN
ACME_EMAIL=$ACME_EMAIL
POSTGRES_PASSWORD=$(openssl rand -hex 24)
API_SECRET=$(openssl rand -hex 24)
ALLOW_DOLPHIN_KEYS=true
ENV
fi
mkdir -p data/postgres data/logs data/state data/caddy

# 4. Start (and on reboot: restart policy unless-stopped)
docker compose up -d --build
sleep 8
docker compose ps
curl -fsS "http://127.0.0.1/api/stats" && echo && echo "OK: https://stats.$DOMAIN"
