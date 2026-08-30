#!/usr/bin/env bash
# install-ish-firmware.sh - install Intel ISH sensor-hub firmware on the Yoga 9 14ILL10
#
# The Integrated Sensor Hub drives the accelerometer and gyro. Without its firmware
# you get no auto-rotate, no tablet-mode keyboard disable, and no screen rotation.
# Intel had not shipped Lunar Lake ISH firmware to linux-firmware at the time of
# writing, so it has to be extracted from the Windows driver store.
#
# Extract on the Windows side first (PowerShell, no admin needed):
#
#   Get-ChildItem C:\Windows\System32\DriverStore\FileRepository `
#     -Recurse -Filter 'ishS_SI_*.bin' | Select FullName
#
# The path contains .../FwImage/0003/ - the 0003 is the Lunar Lake platform id.
# Copy that .bin somewhere this script can reach, then run:
#
#   sudo bash install-ish-firmware.sh /path/to/ishS_SI_5.8.0.7727.bin
#
# Reference machine blob (verify yours matches before trusting a copy):
#   ishS_SI_5.8.0.7727.bin   990.5 KB   SHA256 BE67CD231D6FE40D...
#
# NOTE: this firmware is Intel's proprietary blob. It is deliberately NOT committed
# to this repository - extract it from your own machine's Windows install.

set -euo pipefail

BLOB=${1:-}
FWDIR=/lib/firmware/intel/ish

if [ -z "$BLOB" ]; then
    echo "usage: sudo bash $0 /path/to/ishS_SI_<version>.bin" >&2
    exit 2
fi
if [ ! -f "$BLOB" ]; then
    echo "error: $BLOB not found" >&2
    exit 1
fi
if [ "$(id -u)" -ne 0 ]; then
    echo "error: must run as root" >&2
    exit 1
fi

# Sanity-check it really is an Intel CPD firmware image, not a renamed something-else.
# Header: '$CPD' magic, with 'ISHM' at offset 12.
magic=$(head -c 4 "$BLOB")
tag=$(dd if="$BLOB" bs=1 skip=12 count=4 2>/dev/null)
if [ "$magic" != '$CPD' ]; then
    echo "error: $BLOB is not an Intel CPD image (magic '$magic', expected '\$CPD')" >&2
    exit 1
fi
echo "OK: Intel CPD image, tag '$tag'"

# The kernel asks for an exact filename, and it varies by kernel version - some
# request a plain name, newer ones append a platform hash. Take the name from
# dmesg rather than assuming; guessing here just produces a silent no-op.
echo
echo "What this kernel actually requested:"
REQ=$(dmesg 2>/dev/null | grep -oE 'intel/ish/ish[A-Za-z0-9_]*\.bin' | tail -1 || true)
if [ -n "$REQ" ]; then
    echo "  $REQ"
    TARGET="/lib/firmware/$REQ"
else
    echo "  (nothing in dmesg - falling back to ish_lnlm.bin)"
    echo "  If sensors stay dead, check 'dmesg | grep -i ish' for the exact name"
    echo "  the loader asked for and rerun with that filename."
    TARGET="$FWDIR/ish_lnlm.bin"
fi

mkdir -p "$FWDIR"
if [ -e "$TARGET" ]; then
    cp -a "$TARGET" "$TARGET.bak.$(date +%s)"
    echo "backed up existing firmware"
fi
install -m 0644 "$BLOB" "$TARGET"
echo "installed: $TARGET"

echo
echo "Reloading intel_ish_ipc..."
modprobe -r intel_ishtp_hid intel_ish_ipc 2>/dev/null || true
modprobe intel_ish_ipc 2>/dev/null || true
sleep 2

echo
echo "Result:"
if dmesg 2>/dev/null | tail -40 | grep -qi 'ish.*loaded\|ISH firmware.*ok'; then
    echo "  firmware loaded"
elif dmesg 2>/dev/null | tail -40 | grep -qi 'ish loader.*failed'; then
    echo "  STILL FAILING - check 'dmesg | grep -i ish'"
    echo "  A 'cmd 2 failed' usually means the wrong blob or wrong filename."
else
    echo "  inconclusive - reboot and check 'dmesg | grep -i ish'"
fi

echo
echo "IIO sensors present:"
ls /sys/bus/iio/devices/ 2>/dev/null | sed 's/^/  /' || echo "  none"
echo
echo "A reboot is the reliable test. Then check auto-rotate and tablet mode."
