#!/bin/bash
# Kartaclysm online server for Oracle Cloud (or any Ubuntu/Debian server with cloud-init): paste this whole file
# into "Initialization script" when creating the instance. On first boot it installs everything by itself
# (about 15-30 minutes on the free 1 GB VM). Log: /var/log/kartaclysm-install.log
# Done when http://<public IP>/api/stats shows {"global":...}.
export HOME=/root
until command -v git >/dev/null || apt-get -o DPkg::Lock::Timeout=900 -y -q install git; do sleep 10; done
git clone -b claude/cartaclysm-mod-check-dcu330 https://github.com/franxakathegoat-boop/kartaclysm-wfc /opt/kartaclysm-wfc
DOMAIN=auto /opt/kartaclysm-wfc/deploy/install.sh > /var/log/kartaclysm-install.log 2>&1
