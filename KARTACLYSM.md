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

### Free setup (Oracle Cloud Always Free + nip.io), no terminal needed
1. Sign up at https://www.oracle.com/cloud/free/ (a card is needed to verify you; Always Free resources are not
   charged). Pick a home region close to the players, e.g. Italy Northwest (Milan): it cannot be changed later.
2. Compute > Instances > Create instance:
   * Image: Canonical Ubuntu 24.04. Shape: `VM.Standard.E2.1.Micro` (x86, 1 GB; install.sh adds swap) or
     `VM.Standard.A1.Flex` (ARM; the x86 compiler runs through emulation). Both are "Always Free-eligible".
   * Networking: keep "Assign a public IPv4 address". SSH keys: "Generate a key pair for me", save both files.
   * Advanced options > Management > Initialization script > Paste cloud-init script: the whole of
     `deploy/oracle-init.sh`. Create.
3. On the instance page: Subnet > Default Security List > Add Ingress Rules: Source CIDR `0.0.0.0/0`,
   IP Protocol `All Protocols`. (The server's own firewall, set up by install.sh, only opens the game ports.)
4. Wait 15-30 minutes, then open `http://<public IP>/api/stats`: `{"global":...}` means it works.
   The domain is the IP in hex + `.nip.io` (e.g. 64.176.22.9 -> `40b01609.nip.io`); put it into `wfc_domain`
   in the Kartaclysm `pack.json` and publish the pack.

Notes: the nip.io name is the IP, so keep the same instance (a new IP means a new `wfc_domain`, and players
rebuild once). Oracle may stop Always Free VMs that look idle for 7 days; switching the account to Pay As You Go
avoids that and stays free within the Always Free limits.

**Back up `deploy/payload/private-key.pem`.** With a new key, every player has to rebuild their game.
When the pack gets more tracks, rebuild with `KARTACLYSM_LAST_SLOT=<new last slot> REBUILD_CLIENT=1`
(same key, so players do not rebuild).

Native PC mode (WiiCompiled) still uses Pulsar's built-in Wiimmfi code; it needs a Pulsar rebuild to use this server.
