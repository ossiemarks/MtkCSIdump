# CSI UDP Client with GUI Visualization

CSI server and client to display real-time CSI data. Based on https://github.com/LukasVirecGL/meta-gl-motion-detection.

![Demo](https://raw.githubusercontent.com/MtkWifiRev/MtkCSIdump/refs/heads/main/csi_demo.gif)

## Features

- Real-time CSI data visualization
- Multiple antenna support with separate plots
- Raw CSI samples display
- Phase visualization

## Usage (after dependencies are fulfilled)

### Connect to a wireless network as client
- can be done using the webinterface using "scan". 

### Setting up the Server

```bash
./CSIdump phy0-sta0 <rate> <port>
```

Example:
```bash
./CSIdump phy0-sta0 100 8888
```

### Running the GUI Client

```bash
python3 csi_udp_client_gui.py <server ip> <port>
```

Example:
```bash
python3 csi_udp_client_gui.py 192.168.1.1 8888
```

## Dependencies OpenWRT

### Base Image: tested on for OpenWRT One:
-  see releases for squashfs update bin, based on [24.10.1 (r28597-0425664679)](https://firmware-selector.openwrt.org/?version=24.10.1&target=mediatek%2Ffilogic&id=openwrt_one)

### Copy mt76 firmware:
- see releses for binaries: `mt7981_rom_patch.bin`, `mt7981_wa.bin`, `mt7981_wm.bin`, `mt7981_wo.bin`
- copy them to `/lib/firmware/mediatek/`
- Reboot

### Additional Packages (might not be necessary)
install with `opkg install <dependency>`
- libnl-tiny1
- libstdcpp

### Copy CSIdump binary to OpenWRT
- see releases for `CSIDump` binary

## Building and flashing for OpenWrt One

Stock OpenWrt mt76 does not implement the MediaTek CSI vendor command, so
`CSIdump` refuses to start on an unmodified image. The upstream v0.1 release
ships a full OpenWrt One image (24.10.1, kernel 6.6.86) with a CSI-capable
mt76, but without three of the four MT7981 firmware blobs, so wifi does not
come up until they are copied in. The prebuilt `.ko` files from that release do
**not** load on the release 24.10.1 kernel (struct module size mismatch), so an
ImageBuilder image with those modules overlaid has no wifi at all. The working
procedure is therefore: flash the upstream image, then deploy the blobs and this
package on top.

Scripts live in `openwrt/`. `build.sh` needs Linux x86_64 and about 6 GB of
disk; on macOS run it in a container with a named volume for the work tree:

```bash
docker run --rm -it --platform linux/amd64 -v "$PWD:/work" -w /work \
    -v csidump-build:/build -e CSIDUMP_WORK=/build ubuntu:24.04 bash openwrt/build.sh
```

That produces `openwrt/out/csidump_*.ipk` and copies `libnl-tiny1`,
`libstdcpp6` and the firmware blobs into `openwrt/out/deps/`. Then, over
Ethernet (router at 192.168.77.1 by default, `ROUTER=...` overrides):

```bash
sudo bash openwrt/net-setup.sh apply          # macOS only: keep Wi-Fi as the internet route
ROUTER_PASSWORD='...' bash openwrt/flash.sh --check
IMAGE=openwrt/out/upstream-v0.1-openwrt_one-squashfs-sysupgrade.itb \
    ROUTER_PASSWORD='...' bash openwrt/flash.sh   # flash upstream image, keep settings
ROUTER_PASSWORD='...' bash openwrt/deploy.sh      # blobs + csidump + libs, rebind wifi
```

`flash.sh` refuses anything that is not an OpenWrt One, verifies the image
checksum on the router and runs `sysupgrade --test` first. `--reset` wipes
settings, after which the router returns on 192.168.1.1. Reboot once after
`deploy.sh` so the radios are numbered phy0/phy1.

## Dependencies Python UI

- Python 3.6+
- PyQt5 >= 5.15.0
- pyqtgraph >= 0.13.1
- numpy >= 1.21.0
- matplotlib >= 3.5.0
