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
* `client/build-client.sh <domain>`: builds the WiiLink wfc-patcher stage0 Gecko codes for all 4 regions
  (RMCPD00/RMCED00/RMCJD00/RMCKD00) + signed payloads for our domain (<= 16 chars) in the official devkitPPC
  Docker image, with our own RSA key (`deploy/payload/private-key.pem`, never in git).
  `client/kartaclysm-payload.patch` adapts the payload to LE-CODE:
  * the anti-cheat accepts LE-CODE track slots 0x44..`KARTACLYSM_LAST_SLOT` (default 0xCB, the last slot of the
    pack's 34 custom cups) and LE-CODE's random slots 0x3D..0x41 as votes; anything else is still kicked
  * the "report the upcoming match" hook is left out: LE-CODE hooks the same call site for its own course
    decision (checked against LE-CODE's patch table for all 4 regions; it is the only overlap)
* `deploy/`: Docker Compose (Postgres 17, wwfc, Caddy) + `install.sh` for a one-command VPS deploy. Caddy also
  serves the stage0 files at `https://<domain>/client/RMC?D00.txt`; the Kartaclysm launcher downloads the one
  for the player's region and writes it into the game's main.dol on the player's PC.

## Ports
TCP 80 (NAS, plain HTTP for the Wii), 443 (Caddy: stats page, game patches), 28910, 29900, 29901, 29920; UDP 27900, 27901.

## DNS
`<domain>` and `*.<domain>` -> VPS IP. The game uses nas., naswii., gpcm.gs., gpsp.gs., *.available.gs.,
*.master.gs., *.ms<n>.gs., natneg<n>.gs., gamestats.gs., etc.; a wildcard covers them all.

## Deploy
1. A VPS (Debian 12/13 or Ubuntu 22.04+, 1 GB RAM is enough) and a domain of at most 16 characters.
2. DNS: `<domain>` and `*.<domain>` -> the VPS IP.
3. On the VPS, as root:
```sh
git clone https://github.com/franxakathegoat-boop/kartaclysm-wfc /opt/kartaclysm-wfc
DOMAIN=kartaclysm.net ACME_EMAIL=you@example.com /opt/kartaclysm-wfc/deploy/install.sh
```
   It installs Docker, creates the signing key, builds the game patches (a few minutes), opens the firewall and
   starts everything. Run it again to update; `REBUILD_CLIENT=1` rebuilds the patches with the same key.
4. Kartaclysm repo: set `"wfc_domain": "<domain>"` in `pack.json` and publish the pack. Every player's next PLAY
   rebuilds their game for the server (Dolphin and real Wii, all regions).

**Back up `deploy/payload/private-key.pem`.** With a new key, every player has to rebuild their game.
When the pack gets more tracks, rebuild with `KARTACLYSM_LAST_SLOT=<new last slot> REBUILD_CLIENT=1`
(same key, so players do not rebuild).

Native PC mode (WiiCompiled) still uses Pulsar's built-in Wiimmfi code; it needs a Pulsar rebuild to use this server.
