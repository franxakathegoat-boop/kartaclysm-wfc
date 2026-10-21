#!/usr/bin/env bash
# Kartaclysm WFC client build: stage0 Gecko codes for all 4 regions + signed stage1/payloads, compiled in the
# official devkitPPC Docker image. deploy/install.sh runs this on the server, so the signing key never leaves it.
# Usage: client/build-client.sh DOMAIN   (max 16 chars, e.g. kartaclysm.net)
# Env:   WWFC_KEY=<pem>   signing key (default deploy/payload/private-key.pem; created if missing; NEVER commit it)
#        KARTACLYSM_LAST_SLOT=<hex>  last LE-CODE track slot of the pack (default 0xCB: 34 custom cups)
#        PATCHER_REV=<git rev of WiiLink24/wfc-patcher-wii>, DEVKITPPC_IMAGE=<docker image>
# Output: client/out/<domain>/payload (server side) and client/out/<domain>/client/RMC[PEJK]D00.txt (stage0,
# public: the launcher downloads the one for the player's region and patches it into main.dol)
set -euo pipefail
DOMAIN="${1:?usage: client/build-client.sh DOMAIN}"
HERE="$(cd "$(dirname "$0")" && pwd)"
KEY="${WWFC_KEY:-$HERE/../deploy/payload/private-key.pem}"
REV="${PATCHER_REV:-0d9d7a697d7fb299ecc629f2c5da071d116369f2}"
LAST="${KARTACLYSM_LAST_SLOT:-0xCB}"
IMAGE="${DEVKITPPC_IMAGE:-devkitpro/devkitppc@sha256:d50f8a886f2ce1d3c22685a774afb0845379876b47d9b41a9b729f4f63a54813}"
WORK="${WORK:-$HERE/.patcher}"
OUT="$HERE/out/$DOMAIN"
[ ${#DOMAIN} -le 16 ] || { echo "domain must be <= 16 chars (length of nintendowifi.net)"; exit 1; }
[[ "$DOMAIN" =~ ^[a-z0-9.-]+$ ]] || { echo "domain must be lowercase letters, digits, dots and dashes"; exit 1; }

# 1. pinned wfc-patcher-wii + Kartaclysm changes: LE-CODE track slots pass the anti-cheat, and the match report
#    hook is left out because LE-CODE hooks the same call site for its own course decision
[ -d "$WORK/.git" ] || git clone -q https://github.com/WiiLink24/wfc-patcher-wii "$WORK"
git -C "$WORK" cat-file -e "$REV^{commit}" 2>/dev/null || git -C "$WORK" fetch -q origin "$REV"
git -C "$WORK" checkout -q -f "$REV" && git -C "$WORK" clean -q -fdx
git -C "$WORK" apply "$HERE/kartaclysm-payload.patch"

# 2. signing key (RSA-2048) and the public key compiled into stage1/payloads
if [ ! -f "$KEY" ]; then
  mkdir -p "$(dirname "$KEY")"
  (umask 077 && openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$KEY" 2>/dev/null)
  echo "Created signing key $KEY (back it up: a new key means every player has to rebuild)"
fi
python3 "$HERE/pubkey-hpp.py" "$KEY" > "$WORK/include/wwfcPayloadPublicKey.hpp"
install -m 600 "$KEY" "$WORK/misc/private-key-OUT.pem"   # make.sh only checks that it exists
trap 'rm -f "$WORK/misc/private-key-OUT.pem" "$WORK/dist/private-key.pem"' EXIT

# 3. compile (Docker Hub rate-limits anonymous pulls; Google's mirror serves the same image)
docker image inspect "$IMAGE" >/dev/null 2>&1 || docker pull -q "$IMAGE" >/dev/null || { IMAGE="mirror.gcr.io/$IMAGE"; docker pull -q "$IMAGE" >/dev/null; }
docker run --rm -u "$(id -u):$(id -g)" -v "$WORK:/src" -w /src "$IMAGE" sh -c '
  mkdir -p .bin && ln -sf "$(command -v python3)" .bin/python && export PATH="/src/.bin:$PATH"
  ./make.sh --clean --payload --stage1 --patch -- -j"$(nproc)" -gRMC "-DWWFC_DOMAIN=\"$0\"" -DKARTACLYSM=1 "-DKARTACLYSM_LAST_SLOT=$1"
' "$DOMAIN" "$LAST"

# 4. collect: payload/ for the server, client/ for the players
rm -rf "$OUT" && mkdir -p "$OUT/payload" "$OUT/client"
cp -r "$WORK/dist/binary" "$WORK/dist/stage1.bin" "$OUT/payload/"
cp "$WORK/dist/stage1.bin" "$OUT/payload/stage1v1.bin"   # stage0 requests /w1, which the server maps to stage1v1.bin
for r in P E J K; do cp "$WORK/patch/build/RMC${r}D00.txt" "$OUT/client/"; done
( cd "$OUT/client" && printf '{"domain": "%s", "patcher": "%s", "last_slot": "%s"}\n' "$DOMAIN" "$REV" "$LAST" > info.json && sha256sum RMC*D00.txt > SHA256SUMS )
echo "Built for $DOMAIN -> $OUT"
