#!/usr/bin/env bash
# Install the CSI firmware blobs and the csidump package (plus its two runtime
# libraries) on a router running a CSI-capable mt76, i.e. the upstream v0.1
# image. That image ships without mt7981_rom_patch/wa/wm.bin, so the wifi probe
# fails until they are copied in. Fully offline: everything comes from
# openwrt/out/deps, produced by openwrt/build.sh.
#
#   ROUTER_PASSWORD='...' bash openwrt/deploy.sh
set -euo pipefail

ROUTER="${ROUTER:-192.168.77.1}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
DEPS="$REPO/openwrt/out/deps"

if [ -z "${ROUTER_PASSWORD:-}" ]; then
  read -r -s -p "Router root password: " ROUTER_PASSWORD; echo
fi
export SSHPASS="$ROUTER_PASSWORD"
SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=8)
rsh()  { sshpass -e ssh -n "${SSH_OPTS[@]}" "root@$ROUTER" "$@"; }
rscp() { sshpass -e scp -O "${SSH_OPTS[@]}" "$@"; }
log()  { printf '\n==> %s\n' "$*"; }

ls "$DEPS"/csidump_*.ipk "$DEPS"/libnl-tiny1_*.ipk "$DEPS"/libstdcpp6_*.ipk >/dev/null

log "Uploading packages to $ROUTER"
rsh 'rm -rf /tmp/csidump-deploy && mkdir -p /tmp/csidump-deploy'
rscp "$DEPS"/*.ipk "root@$ROUTER:/tmp/csidump-deploy/"

if ls "$DEPS"/firmware/mt7981_*.bin >/dev/null 2>&1; then
  log "Installing MT7981 CSI firmware blobs"
  rscp "$DEPS"/firmware/mt7981_*.bin "root@$ROUTER:/lib/firmware/mediatek/"
  rsh 'cd /lib/firmware/mediatek && sha256sum mt7981_*.bin | cut -c1-16,65-'
  log "Re-probing the wifi (mt798x-wmac bind)"
  rsh 'D=/sys/bus/platform/drivers/mt798x-wmac; [ -e $D/18000000.wifi ] && echo 18000000.wifi > $D/unbind; echo 18000000.wifi > $D/bind 2>&1 || true; sleep 4; echo "phys: $(ls /sys/class/ieee80211 | tr "\n" " ")"; dmesg | grep -iE "wmac|mt7981" | tail -6'
fi

log "Installing (opkg, offline)"
rsh 'cd /tmp/csidump-deploy && opkg install libnl-tiny1_*.ipk libstdcpp6_*.ipk 2>&1 | grep -vE "^Installing|^Configuring" || true; opkg install --force-reinstall csidump_*.ipk'

log "Smoke test: the binary must start and print its usage line"
rsh '/usr/bin/CSIdump; echo "exit=$?"' || true
rsh 'echo "wifi ifs: $(ls /sys/class/net | grep -E "phy|wlan" | tr "\n" " ")"; echo "mt7915e: $(lsmod | grep -c "^mt7915e") loaded"'

log "Done. Start capture with:  ssh root@$ROUTER 'CSIdump phy0-sta0 100 8888'"
