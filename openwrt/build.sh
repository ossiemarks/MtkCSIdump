#!/usr/bin/env bash
# Build a CSIdump .ipk with the OpenWrt SDK and bake it into an OpenWrt One
# sysupgrade image with the ImageBuilder, overlaying the CSI-capable mt76
# kernel modules and MT7981 firmware from the upstream MtkCSIdump v0.1 release.
#
# Must run on Linux x86_64 (use a container on macOS). Needs roughly 6 GB free.
#
#   docker run --rm -it --platform linux/amd64 -v "$PWD:/work" -w /work \
#       -v csidump-build:/build -e CSIDUMP_WORK=/build \
#       ubuntu:24.04 bash openwrt/build.sh
#
# The SDK and ImageBuilder must be unpacked on a native Linux filesystem
# (symlinks, case sensitivity), hence the named volume for the work tree.
#
# Output: openwrt/out/openwrt-24.10.1-mediatek-filogic-openwrt_one-squashfs-sysupgrade.itb
set -euo pipefail

VER=24.10.1
TARGET=mediatek/filogic
PROFILE=openwrt_one
BASE_URL="https://downloads.openwrt.org/releases/$VER/targets/$TARGET"
RELEASE_URL="https://github.com/MtkWifiRev/MtkCSIdump/releases/download/v0.1"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${CSIDUMP_WORK:-$REPO/openwrt/work}"
OUT="$REPO/openwrt/out"
mkdir -p "$WORK" "$OUT"

SDK_TAR="openwrt-sdk-$VER-mediatek-filogic_gcc-13.3.0_musl.Linux-x86_64.tar.zst"
IB_TAR="openwrt-imagebuilder-$VER-mediatek-filogic.Linux-x86_64.tar.zst"
SDK_DIR="$WORK/${SDK_TAR%.tar.zst}"
IB_DIR="$WORK/${IB_TAR%.tar.zst}"

log() { printf '\n==> %s\n' "$*"; }

if [ "$(uname -s)" != "Linux" ] || [ "$(uname -m)" != "x86_64" ]; then
  echo "This script needs Linux x86_64 (run it inside a container)." >&2
  exit 1
fi

if command -v apt-get >/dev/null && [ "$(id -u)" = 0 ]; then
  log "Installing host build dependencies"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq build-essential clang flex bison g++ gawk gcc-multilib \
    gettext git libncurses5-dev libssl-dev python3-setuptools rsync swig \
    unzip zlib1g-dev file wget zstd curl ca-certificates python3 >/dev/null
fi

fetch() { # url dest
  [ -f "$2" ] && return 0
  log "Downloading $(basename "$2")"
  curl -fL --retry 3 -o "$2.part" "$1" && mv "$2.part" "$2"
}

cd "$WORK"
fetch "$BASE_URL/$SDK_TAR" "$WORK/$SDK_TAR"
fetch "$BASE_URL/$IB_TAR" "$WORK/$IB_TAR"
[ -d "$SDK_DIR" ] || { log "Extracting SDK"; tar --zstd -xf "$SDK_TAR"; }
[ -d "$IB_DIR" ] || { log "Extracting ImageBuilder"; tar --zstd -xf "$IB_TAR"; }

# ---- upstream CSI-capable driver modules and firmware -----------------------
PREBUILT="$WORK/prebuilt"
mkdir -p "$PREBUILT"
for f in mt76.ko mt76-connac-lib.ko mt7915e.ko \
         mt7981_rom_patch.bin mt7981_wa.bin mt7981_wm.bin mt7981_wo.bin; do
  fetch "$RELEASE_URL/$f" "$PREBUILT/$f"
done

# ---- kernel version sanity check --------------------------------------------
# The ImageBuilder records the exact kernel patch level in include/kernel-<major>.
KVER="$(awk '/^LINUX_VERSION-[0-9.]+ *=/ { sub(/^LINUX_VERSION-/, "", $1); print $1 $3; exit }' \
        "$IB_DIR"/include/kernel-[0-9]* 2>/dev/null)"
if [ -z "$KVER" ]; then
  for f in "$IB_DIR"/packages/kernel_*; do
    [ -e "$f" ] || break
    KVER="$(basename "$f" | sed -n 's/^kernel_\([0-9][0-9.]*\).*/\1/p')"
    break
  done
fi
[ -n "$KVER" ] || { echo "Could not determine ImageBuilder kernel version" >&2; exit 1; }
# grep the binary directly: a strings|grep -m1 pipeline trips pipefail with SIGPIPE
VERMAGIC="$(grep -a -o -m1 'vermagic=[^[:space:]]*' "$PREBUILT/mt7915e.ko" | cut -d= -f2)"
log "ImageBuilder kernel: $KVER   prebuilt mt7915e.ko vermagic: $VERMAGIC"
if [ "$KVER" != "$VERMAGIC" ]; then
  echo "Kernel version mismatch: upstream .ko files were built for $VERMAGIC, ImageBuilder is $KVER." >&2
  echo "Pin VER to the release the modules were built against, or rebuild mt76 from source." >&2
  exit 1
fi

# ---- build the csidump package with the SDK ---------------------------------
log "Building csidump package"
PKG_DST="$SDK_DIR/package/csidump"
rm -rf "$PKG_DST"
mkdir -p "$PKG_DST/src"
cp "$REPO/openwrt/package/csidump/Makefile" "$PKG_DST/Makefile"
rsync -a --exclude '.git' --exclude 'openwrt' --exclude '*.gif' --exclude '*.py' \
  "$REPO/" "$PKG_DST/src/"

cd "$SDK_DIR"
./scripts/feeds update base >/dev/null
./scripts/feeds install libnl-tiny >/dev/null
make defconfig >/dev/null
make package/csidump/compile -j"$(nproc)" V=s
IPK="$(find "$SDK_DIR/bin/packages" -name 'csidump_*.ipk' -print -quit)"
[ -n "$IPK" ] || { echo "csidump ipk not produced" >&2; exit 1; }
cp "$IPK" "$OUT/"

# ---- assemble the image with the ImageBuilder -------------------------------
log "Assembling OpenWrt One image"
cd "$IB_DIR"
mkdir -p packages
cp "$IPK" packages/
FILES="$WORK/files"
rm -rf "$FILES"
mkdir -p "$FILES/lib/modules/$KVER" "$FILES/lib/firmware/mediatek"
cp "$PREBUILT"/*.ko "$FILES/lib/modules/$KVER/"
cp "$PREBUILT"/mt7981_*.bin "$FILES/lib/firmware/mediatek/"

make image PROFILE="$PROFILE" \
  PACKAGES="csidump libnl-tiny1 libstdcpp" \
  FILES="$FILES" \
  BIN_DIR="$OUT"

log "Done. Images in $OUT:"
ls -l "$OUT"/*openwrt_one* 2>/dev/null || ls -l "$OUT"
