#!/usr/bin/env bash
# Keep Wi-Fi as the internet route while the USB Ethernet adapter talks to the
# router. macOS picks its default route by network service order, so this moves
# Wi-Fi to the top and leaves everything else in its current order.
#
#   bash openwrt/net-setup.sh            # dry run: show the order it would apply
#   sudo bash openwrt/net-setup.sh apply # apply it
set -euo pipefail

WIFI="Wi-Fi"
ORDER=("$WIFI")
while IFS= read -r s; do
  [ -n "$s" ] && [ "$s" != "$WIFI" ] && ORDER+=("$s")
done < <(networksetup -listnetworkserviceorder | sed -n 's/^([0-9*]*) //p')

echo "Service order to apply (first wins the default route):"
printf '  %s\n' "${ORDER[@]}"

if [ "${1:-}" != "apply" ]; then
  echo; echo "Dry run. Re-run as: sudo bash $0 apply"; exit 0
fi
[ "$(id -u)" = 0 ] || { echo "apply needs sudo" >&2; exit 1; }

networksetup -ordernetworkservices "${ORDER[@]}"
echo; echo "Applied. Default route now:"
sleep 2
route -n get default | grep -E 'gateway|interface'
