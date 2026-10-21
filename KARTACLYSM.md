# Kartaclysm WFC

Fork of [WiiLink24/wfc-server](https://github.com/WiiLink24/wfc-server) (AGPL-3.0) for the
Kartaclysm Mario Kart Wii pack. All changes are published here under the same license.

## Changes vs upstream
* **VR/BR history + rankings (phase 1)**: VR/BR values that clients report in QR2 heartbeats
  (public worldwide/regional rooms only, 1-9999) are stored when they change:
  * `player_ratings` (current rating per profile and kind), `vr_history` (every change).
  * `GET /api/leaderboard?type=vr|br&limit=50&offset=0` (banned players hidden)
  * `GET /api/vrhistory?pid=<profile id>&type=vr|br&limit=100`
  * Code: `database/vr.go`, `qr2/ratings.go`, `api/leaderboard.go`; DB test `WWFC_TEST_DB=1 go test ./database`.
* `schema.sql` is owner-agnostic and can be applied repeatedly (fixes the `users_pkey` error on reruns).
* `web/index.html`: public stats page (players online, rooms, VR/BR top 100).
* `client/build-client.sh <domain>`: builds the WiiLink wfc-patcher stage0 Gecko code + signed payloads
  for our domain (<= 16 chars) with our own RSA key (kept outside git).
* `deploy/`: Docker Compose (Postgres 17, wwfc, Caddy) + `install.sh` for a one-command VPS deploy.

## Ports
TCP 80 (NAS, plain HTTP for the Wii), 443 (Caddy stats page), 28910, 29900, 29901, 29920; UDP 27900, 27901.

## DNS
`<domain>` and `*.<domain>` -> VPS IP. The game uses nas., naswii., gpcm.gs., gpsp.gs., *.available.gs.,
*.master.gs., *.ms<n>.gs., natneg<n>.gs., gamestats.gs., etc.; a wildcard covers them all.

## Deploy
```sh
git clone https://github.com/franxakathegoat-boop/kartaclysm-wfc /opt/kartaclysm-wfc
# copy client/out/<domain>/payload/* and the signing key (as private-key.pem) to deploy/payload/
DOMAIN=kartaclysm.net ACME_EMAIL=you@example.com /opt/kartaclysm-wfc/deploy/install.sh
```
