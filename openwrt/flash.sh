#!/usr/bin/env bash
# Flash the built OpenWrt One image over Ethernet, fully offline.
#
#   ROUTER_PASSWORD='...' bash openwrt/flash.sh --check   # verify only, no flash
#   ROUTER_PASSWORD='...' bash openwrt/flash.sh           # flash, keep settings
#   ROUTER_PASSWORD='...' bash openwrt/flash.sh --reset   # flash, wipe settings
#   IMAGE=openwrt/out/upstream-v0.1-openwrt_one-squashfs-sysupgrade.itb ROUTER_PASSWORD='...' bash openwrt/flash.sh
#
# Needs: sshpass, ssh, scp (all present on this Mac). Router at 192.168.77.1
# (override with ROUTER=...). With --reset the router comes back on 192.168.1.1.
set -euo pipefail

ROUTER="${ROUTER:-192.168.77.1}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
# IMAGE=path overrides the image (e.g. the upstream v0.1 image whose kernel matches its CSI modules).
IMG="${IMAGE:-$(ls "$REPO"/openwrt/out/openwrt-*openwrt_one-squashfs-sysupgrade.itb 2>/dev/null | head -1)}"
MODE="flash"
case "${1:-}" in
  --check) MODE="check" ;;
  --reset) MODE="reset" ;;
  "") ;;
  *) echo "usage: $0 [--check|--reset]" >&2; exit 1 ;;
esac

if [ -z "${ROUTER_PASSWORD:-}" ]; then
  read -r -s -p "Router root password: " ROUTER_PASSWORD; echo
fi
export SSHPASS="$ROUTER_PASSWORD"

SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=8)
rsh()  { sshpass -e ssh "${SSH_OPTS[@]}" "root@$ROUTER" "$@"; }
rscp() { sshpass -e scp -O "${SSH_OPTS[@]}" "$@"; }  # -O: dropbear has no sftp-server
log()  { printf '\n==> %s\n' "$*"; }

[ -f "$IMG" ] || { echo "No sysupgrade image in $REPO/openwrt/out. Run openwrt/build.sh first." >&2; exit 1; }
LOCAL_SHA="$(shasum -a 256 "$IMG" | cut -d' ' -f1)"
log "Image: $(basename "$IMG") ($(du -h "$IMG" | cut -f1), sha256 ${LOCAL_SHA:0:16}...)"

log "Reaching $ROUTER"
ping -c 1 -W 2000 "$ROUTER" >/dev/null || { echo "Router not reachable. Is the Ethernet cable in and the router booted?" >&2; exit 1; }

log "Logging in"
MODEL="$(rsh 'cat /tmp/sysinfo/model 2>/dev/null')" || { echo "SSH login failed (wrong password?)" >&2; exit 1; }
echo "model:   $MODEL"
rsh 'grep -E "DISTRIB_(RELEASE|TARGET)" /etc/openwrt_release | sed "s/DISTRIB_/  /"; echo "  kernel:  $(uname -r)"; echo "  free /tmp: $(df -h /tmp | awk "NR==2{print \$4}")"'
case "$MODEL" in
  *"OpenWrt One"*) ;;
  *) echo "Refusing to flash: model is '$MODEL', not an OpenWrt One." >&2; exit 1 ;;
esac

if [ "$MODE" = "check" ]; then
  log "Check passed. Run without --check to flash."
  exit 0
fi

log "Uploading image to /tmp on the router"
rscp "$IMG" "root@$ROUTER:/tmp/sysupgrade.itb"
REMOTE_SHA="$(rsh 'sha256sum /tmp/sysupgrade.itb' | cut -d' ' -f1)"
[ "$REMOTE_SHA" = "$LOCAL_SHA" ] || { echo "Checksum mismatch after upload, aborting." >&2; exit 1; }
echo "checksum verified on router"

log "Validating image with sysupgrade --test"
rsh 'sysupgrade --test /tmp/sysupgrade.itb'

FLAGS=""; [ "$MODE" = "reset" ] && FLAGS="-n"
log "Flashing (settings $([ "$MODE" = reset ] && echo discarded || echo kept)). The router will reboot; this takes 2 to 4 minutes."
rsh "sysupgrade $FLAGS /tmp/sysupgrade.itb" || true   # connection drops when it reboots

if [ "$MODE" = "reset" ]; then
  ROUTER="192.168.1.1"
  echo "Settings were discarded, so the router will come back on $ROUTER."
fi
log "Waiting for the router to come back on $ROUTER"
sleep 45
for i in $(seq 1 60); do
  if ping -c 1 -W 2000 "$ROUTER" >/dev/null 2>&1 && rsh 'true' 2>/dev/null; then break; fi
  sleep 5
  [ "$i" = 60 ] && { echo "Router did not come back within 6 minutes. Check its LEDs; recovery mode is documented in the OpenWrt One wiki." >&2; exit 1; }
done

log "Post-flash verification"
rsh '
echo "release:  $(grep DISTRIB_RELEASE /etc/openwrt_release | cut -d\" -f2)   kernel: $(uname -r)"
echo "CSIdump:  $(ls -l /usr/bin/CSIdump 2>/dev/null || echo MISSING)"
echo "mt7915e:  $(sha256sum /lib/modules/$(uname -r)/mt7915e.ko | cut -c1-16)  (expect c8074d69c935cf83)"
echo "wm fw:    $(sha256sum /lib/firmware/mediatek/mt7981_wm.bin | cut -c1-16)  (expect a31abbf77bab86fe)"
echo "modules:  $(lsmod | grep -oE "^mt7915e|^mt76_connac_lib|^mt76 " | tr "\n" " ")"
echo "wifi ifs: $(ls /sys/class/net | grep -E "phy|wlan" | tr "\n" " ")"
echo "--- dmesg (mt7915/mt76):"; dmesg | grep -iE "mt7915|mt76|firmware" | tail -8
'

log "Done. Next: join a Wi-Fi network as a client (LuCI > Wireless > Scan), then on the router:"
echo "    CSIdump phy0-sta0 100 8888"
echo "and on this Mac:"
echo "    python3 csi_udp_client_gui.py $ROUTER 8888"
