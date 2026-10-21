#!/usr/bin/env bash
# Kartaclysm WFC client build: stage0 Gecko patches + signed stage1/stage2 payloads.
# Usage: client/build-client.sh [DOMAIN]   (default: kartaclysm.net, max 16 chars)
# Env:   WWFC_KEY=/home/box/secrets/kartaclysm-wfc-payload.pem (created if missing; NEVER commit it)
#        PATCHER_REV=<git rev of WiiLink24/wfc-patcher-wii>
set -euo pipefail
DOMAIN="${1:-kartaclysm.net}"
KEY="${WWFC_KEY:-/home/box/secrets/kartaclysm-wfc-payload.pem}"
REV="${PATCHER_REV:-0d9d7a697d7fb299ecc629f2c5da071d116369f2}"
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="${WORK:-$HERE/.patcher}"
OUT="$HERE/out/$DOMAIN"
export DEVKITPRO="${DEVKITPRO:-/opt/devkitpro}" DEVKITPPC="${DEVKITPPC:-/opt/devkitpro/devkitPPC}"
[ ${#DOMAIN} -le 16 ] || { echo "domain must be <= 16 chars (length of nintendowifi.net)"; exit 1; }
mkdir -p "$(dirname "$KEY")" && chmod 700 "$(dirname "$KEY")"
[ -d "$WORK/.git" ] || git clone -q https://github.com/WiiLink24/wfc-patcher-wii "$WORK"
git -C "$WORK" fetch -q origin && git -C "$WORK" checkout -q "$REV"
# make.sh calls `python`
mkdir -p "$WORK/.bin"; ln -sf "$(command -v python3)" "$WORK/.bin/python"; export PATH="$WORK/.bin:$PATH"
cd "$WORK/misc"
if [ ! -f "$KEY" ]; then
  python3 generate-key.py new "$KEY" wwfcPayloadPublicKey-OUT.hpp; chmod 600 "$KEY"
else
  python3 generate-key.py privin "$KEY" wwfcPayloadPublicKey-OUT.hpp
fi
cp wwfcPayloadPublicKey-OUT.hpp ../include/wwfcPayloadPublicKey.hpp
cp "$KEY" private-key-OUT.pem
trap 'rm -f "$WORK/misc/private-key-OUT.pem" "$WORK/dist/private-key.pem"' EXIT
cd "$WORK"
./make.sh --clean --payload --stage1 --patch -- -j"$(nproc)" -gRMC "-DWWFC_DOMAIN=\"$DOMAIN\""
rm -rf "$OUT"; mkdir -p "$OUT/payload"
cp -r dist/binary dist/stage1.bin "$OUT/payload/"
# stage0 (patch/wwfcPatch.s) requests /w1, which the server maps to stage1v1.bin
cp dist/stage1.bin "$OUT/payload/stage1v1.bin"
cp patch/build/*RMC*.txt "$OUT/" 2>/dev/null || cp patch/build/*.txt "$OUT/"
cp include/wwfcPayloadPublicKey.hpp "$OUT/"
echo "Built for $DOMAIN -> $OUT (copy $OUT/payload next to the wwfc binary)"
