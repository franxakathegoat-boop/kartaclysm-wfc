#!/usr/bin/env bash
# One-command Kartaclysm WFC deploy on a fresh Debian 12/13 or Ubuntu 22.04+ VPS (run as root):
#   git clone https://github.com/franxakathegoat-boop/kartaclysm-wfc /opt/kartaclysm-wfc
#   DOMAIN=kartaclysm.net ACME_EMAIL=you@example.com /opt/kartaclysm-wfc/deploy/install.sh
# Before running: point DNS for <domain> and *.<domain> (A record, plus AAAA if you like) at this server.
# No domain? DOMAIN=auto uses a free nip.io name made from this server's IP (no DNS setup needed).
# Safe to run again (updates); REBUILD_CLIENT=1 rebuilds the game patches with the same key.
set -euo pipefail
cd "$(dirname "$0")"
: "${DOMAIN:?set DOMAIN, e.g. DOMAIN=kartaclysm.net, or DOMAIN=auto for a free nip.io name}"
: "${ACME_EMAIL:?set ACME_EMAIL, the e-mail for the HTTPS certificate}"
[ "$(id -u)" = 0 ] || { echo "run as root"; exit 1; }

# 1. Docker (+ what the client build needs)
apt-get update -q && apt-get install -y -q ca-certificates curl git openssl python3 >/dev/null
if ! command -v docker >/dev/null || ! docker compose version >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sh
fi
# the devkitPPC compiler image is x86 only: on ARM servers (e.g. Oracle's free Ampere VMs) run it through emulation
[ "$(uname -m)" = x86_64 ] || docker run --privileged --rm tonistiigi/binfmt --install amd64 >/dev/null
# small servers (e.g. Oracle's free 1 GB VM): add swap so the build and Postgres fit
if [ "$(awk '/MemTotal/ {print $2}' /proc/meminfo)" -lt 1600000 ] && [ -z "$(swapon --show)" ]; then
  fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile
  grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi
# DOMAIN=auto: free nip.io name from this server's public IP in hex (e.g. 8ba1f20e.nip.io, 15 characters);
# it resolves every subdomain the game uses. It changes if the server's IP changes.
if [ "$DOMAIN" = auto ]; then
  ip=$(curl -4 -fsS https://api.ipify.org)
  [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "could not detect the public IP (got: $ip)"; exit 1; }
  DOMAIN=$(printf '%02x%02x%02x%02x.nip.io' ${ip//./ }); echo "Domain: $DOMAIN"
fi

# 2. Game patches for all 4 regions + signed payloads, built here so the signing key never leaves this server.
#    wwfc signs every payload download with deploy/payload/private-key.pem; keep a backup of it (never in git).
if [ ! -f payload/stage1v1.bin ] || [ "$(cat payload/.domain 2>/dev/null)" != "$DOMAIN" ] || [ -n "${REBUILD_CLIENT:-}" ]; then
  WWFC_KEY="$PWD/payload/private-key.pem" ../client/build-client.sh "$DOMAIN"
  cp -r "../client/out/$DOMAIN/payload/." payload/
  rm -rf data/client && mkdir -p data/client && cp "../client/out/$DOMAIN/client/"* data/client/
  echo "$DOMAIN" > payload/.domain
fi
chmod 600 payload/private-key.pem

# 3. Firewall: SSH + game ports + HTTPS (stats page, game patch downloads)
apt-get install -y -q ufw >/dev/null
ufw allow 22/tcp
ufw allow 80/tcp        # NAS (Wii login, plain HTTP) + payload
ufw allow 443/tcp       # Caddy: public stats page / API / game patches (TLS)
ufw allow 28910/tcp     # server browser (matchmaking list)
ufw allow 29900/tcp     # GPCM (login, friends, presence)
ufw allow 29901/tcp     # GPSP (profile search)
ufw allow 29920/tcp     # gamestats
ufw allow 27900/udp     # QR2 (rooms / heartbeats, VR reports)
ufw allow 27901/udp     # NATNEG
ufw --force enable
# Oracle Cloud images reject everything but SSH in iptables before ufw's rules are reached: hand the firewall to ufw
if iptables -C INPUT -j REJECT --reject-with icmp-host-prohibited 2>/dev/null; then
  iptables -D INPUT -j REJECT --reject-with icmp-host-prohibited
  iptables -D FORWARD -j REJECT --reject-with icmp-host-prohibited 2>/dev/null || true
  [ -f /etc/iptables/rules.v4 ] && sed -i '/icmp-host-prohibited/d' /etc/iptables/rules.v4
fi

# 4. Secrets (kept only on the VPS)
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
sed -i -e "s|^DOMAIN=.*|DOMAIN=$DOMAIN|" -e "s|^ACME_EMAIL=.*|ACME_EMAIL=$ACME_EMAIL|" .env
mkdir -p data/postgres data/logs data/state data/caddy

# 5. Start (and on reboot: restart policy unless-stopped)
docker compose up -d --build
sleep 8
docker compose ps
curl -fsS "http://127.0.0.1/api/stats" && echo && echo "OK: https://stats.$DOMAIN"
curl -fsS -o /dev/null --resolve "$DOMAIN:443:127.0.0.1" "https://$DOMAIN/client/RMCPD00.txt" && echo "OK: game patches at https://$DOMAIN/client/" \
  || echo "Game patches not reachable over HTTPS yet (certificate pending? check: docker compose logs caddy)"
echo "Last step: set \"wfc_domain\": \"$DOMAIN\" in the Kartaclysm pack.json and publish the pack."
