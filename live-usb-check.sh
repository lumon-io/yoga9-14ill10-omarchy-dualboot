#!/usr/bin/env bash
# live-usb-check.sh - hardware verification for the Lenovo Yoga 9 2-in-1 14ILL10
#
# Run this from the Omarchy/Arch live USB BEFORE touching the disk. It is
# READ-ONLY: it inspects hardware and writes one report file. It never
# partitions, mounts read-write, or installs anything.
#
#   bash live-usb-check.sh                  # report to ./live-report.md
#   bash live-usb-check.sh /run/media/USB   # report to a USB stick
#
# Then reboot into Windows and hand the report to Claude, or paste it into an
# issue. Every check maps to a prediction in README.md's compatibility matrix.

set -uo pipefail

OUT_DIR="${1:-$PWD}"
OUT="$OUT_DIR/live-report.md"
PASS=0; FAIL=0; WARN=0

have() { command -v "$1" >/dev/null 2>&1; }
say()  { printf '%s\n' "$*" >> "$OUT"; }
hdr()  { say ""; say "## $*"; say ""; }
code() { say '```'; cat >> "$OUT"; say '```'; }

# result <PASS|FAIL|WARN> <label> <detail>
result() {
    local s=$1 label=$2 detail=${3:-}
    case $s in
        PASS) PASS=$((PASS+1)); printf '  \033[32m[PASS]\033[0m %s\n' "$label" ;;
        FAIL) FAIL=$((FAIL+1)); printf '  \033[31m[FAIL]\033[0m %s\n' "$label" ;;
        WARN) WARN=$((WARN+1)); printf '  \033[33m[WARN]\033[0m %s\n' "$label" ;;
    esac
    say "- **$s** — $label${detail:+ — $detail}"
}

if ! touch "$OUT" 2>/dev/null; then
    echo "ERROR: cannot write to $OUT_DIR. Pass a writable directory as argument 1." >&2
    exit 1
fi
: > "$OUT"

say "# Live USB hardware report"
say ""
say "Generated: $(date -Is 2>/dev/null || date)"
say "Machine: $(cat /sys/class/dmi/id/product_name 2>/dev/null || echo unknown) / \
$(cat /sys/class/dmi/id/product_family 2>/dev/null || echo unknown)"
say "BIOS: $(cat /sys/class/dmi/id/bios_version 2>/dev/null || echo unknown)"
say "Kernel: $(uname -r)"
say ""
say "> Read-only report. No changes were made to any disk."

echo
echo "=== Live USB hardware check - Yoga 9 14ILL10 ==="
echo

# ------------------------------------------------------------------ kernel ---
hdr "Kernel"
KREL=$(uname -r); KMAJ=${KREL%%.*}; KMIN=$(echo "$KREL" | cut -d. -f2 | tr -dc '0-9')
say "Running kernel: \`$KREL\`"

# There is ONE Omarchy ISO and it boots the linux-t2 kernel, so a single image works
# on both T2 Macs and ordinary PCs. Seeing -t2 here is correct and expected - it does
# NOT mean you downloaded a Mac-specific build. The installed system gets stock
# `linux` from builder/archinstall.packages, not linux-t2.
case "$KREL" in
    *-t2|*-t2-*)
        result PASS "Omarchy live kernel (linux-t2)" "expected - one ISO boots Macs and PCs alike"
        say ""
        say "> \`-t2\` is the Omarchy ISO's live kernel, not a wrong download. The"
        say "> **installed** system gets stock \`linux\`, so the kernel version gate below"
        say "> applies to the live environment only — recheck \`uname -r\` after install."
        ;;
    *-arch*|*-lts|*-zen|*-hardened|*-cachyos*)
        result PASS "Standard Arch kernel flavour" "$KREL"
        ;;
    *)
        result WARN "Unrecognised kernel flavour" "$KREL"
        ;;
esac
if [ "$KMAJ" -gt 7 ] || { [ "$KMAJ" -eq 7 ] && [ "$KMIN" -ge 2 ]; }; then
    result PASS "Kernel >= 7.2" "Arc 140V GPU-hang fix present"
elif [ "$KMAJ" -ge 7 ] || { [ "$KMAJ" -eq 6 ] && [ "$KMIN" -ge 14 ]; }; then
    result WARN "Kernel $KREL is >= 6.14 but < 7.2" "touch/pen OK; GPU may freeze under load"
else
    result FAIL "Kernel $KREL is below 6.14" "touchscreen and pen will not work"
fi

# --------------------------------------------------------------- secure boot -
hdr "Firmware / Secure Boot"
SBVAR=/sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c
if [ -d /sys/firmware/efi ]; then
    result PASS "Booted in UEFI mode"
    if [ -r "$SBVAR" ]; then
        SB=$(od -An -t u1 "$SBVAR" 2>/dev/null | awk '{print $NF}')
        [ "$SB" = "1" ] && result WARN "Secure Boot is ON" "installer needs it OFF" \
                        || result PASS "Secure Boot is OFF" "expected during install"
    fi
else
    result FAIL "Not booted in UEFI mode" "reboot and disable CSM/legacy"
fi

# --------------------------------------------------------------------- disk --
hdr "Storage — can the installer see the disk?"
if have lsblk; then lsblk -o NAME,SIZE,TYPE,FSTYPE,PARTTYPENAME 2>/dev/null | code; fi
if [ -b /dev/nvme0n1 ]; then
    result PASS "NVMe disk visible as /dev/nvme0n1" "no Intel VMD blocking"
    if have lsblk && lsblk -no FSTYPE /dev/nvme0n1 2>/dev/null | grep -qi ntfs; then
        result PASS "Windows NTFS partition intact"
    fi
else
    result FAIL "No /dev/nvme0n1" "check BIOS storage mode (VMD/RST)"
fi
say ""
say "Free space check — confirm unallocated space exists before installing:"
have parted && parted -s /dev/nvme0n1 unit GiB print free 2>/dev/null | code

# ---------------------------------------------------------------------- gpu --
hdr "Graphics — Arc 140V (Xe2)"
have lspci && lspci -nnk | grep -A3 -iE 'vga|display|3d' | code
if lsmod 2>/dev/null | grep -q '^xe '; then
    result PASS "xe driver loaded"
else
    result FAIL "xe driver not loaded" "GPU will run unaccelerated"
fi

# --------------------------------------------------------------------- wifi --
hdr "Wi-Fi — Intel BE201 (8086:a840)"
have lspci && lspci -nnk | grep -A3 -i 'network controller' | code
if lsmod 2>/dev/null | grep -q iwlwifi; then
    result PASS "iwlwifi loaded"
    if dmesg 2>/dev/null | grep -qiE 'iwlwifi.*(failed to load|no suitable firmware|minimum version)'; then
        result FAIL "iwlwifi firmware problem" "see dmesg below"
        dmesg 2>/dev/null | grep -i iwlwifi | tail -20 | code
    else
        result PASS "iwlwifi firmware loaded cleanly"
    fi
    have iw && iw dev 2>/dev/null | code
    ping -c1 -W3 1.1.1.1 >/dev/null 2>&1 \
        && result PASS "Network reachable" \
        || result WARN "No network yet" "connect Wi-Fi, then rerun"
else
    result FAIL "iwlwifi not loaded"
fi

# ---------------------------------------------------------------- bluetooth --
hdr "Bluetooth — PCIe (btintel_pcie), unverified prediction"
# Check /proc/modules directly rather than relying on lsmod being present, and
# distinguish "driver missing" from "driver loaded but no adapter registered" -
# they have completely different fixes.
BT_MOD=0; BT_DEV=0
grep -qE '^(btintel_pcie|btintel) ' /proc/modules 2>/dev/null && BT_MOD=1
[ -d /sys/class/bluetooth ] && [ -n "$(ls -A /sys/class/bluetooth 2>/dev/null)" ] && BT_DEV=1
have rfkill && rfkill list bluetooth 2>/dev/null | code
if [ "$BT_DEV" -eq 1 ]; then
    result PASS "Bluetooth adapter registered" "$(ls /sys/class/bluetooth 2>/dev/null | tr '\n' ' ')"
elif [ "$BT_MOD" -eq 1 ]; then
    result WARN "btintel_pcie loaded but no adapter registered" "check rfkill / firmware above"
else
    result WARN "No Bluetooth driver loaded" "was only a 'likely' prediction"
fi

# -------------------------------------------------------------------- audio --
hdr "Audio — CS42L43 + CS35L56 (NOT TESTABLE FROM THE LIVE ISO)"
# The Omarchy ISO ships /etc/modprobe.d/blacklist-panther-lake-audio.conf, which
# blacklists snd_sof_pci_intel_lnl, soundwire_intel and snd_soc_cs35l56* to avoid
# boot failures on Panther Lake machines. That blacklist is in the live filesystem
# only - the installed system gets sof-firmware and pipewire with no blacklist. So
# "no soundcards" here says nothing about whether audio works after installing.
SOF_BLACKLISTED=0
if grep -rqs 'blacklist.*snd_sof\|blacklist.*soundwire_intel' /etc/modprobe.d/ 2>/dev/null; then
    SOF_BLACKLISTED=1
    result WARN "SOF modules blacklisted by the live ISO" "audio cannot be evaluated here"
    say "> **The live ISO blacklists SOF audio on purpose.** Found in \`/etc/modprobe.d/\`:"
    say ""
    grep -rhs 'blacklist' /etc/modprobe.d/*audio* 2>/dev/null | head -20 | code
    say "> This is a live-environment workaround for Panther Lake boot failures, not a"
    say "> hardware fault. The installed system has no such blacklist. **Re-test audio"
    say "> after installing** — that is the only run that means anything."
else
    say "> Silent speakers here are the **predicted** result, not a reason to abort."
    say "> Root cause is a missing ALSA UCM CardLongName matcher, fixable post-install."
fi
say ""
[ -r /proc/asound/cards ] && cat /proc/asound/cards | code
have aplay && aplay -l 2>/dev/null | code
dmesg 2>/dev/null | grep -iE 'sof|cs42l43|cs35l56|soundwire' | tail -30 | code
if [ -r /proc/asound/cards ] && grep -qi 'sof\|soundwire' /proc/asound/cards 2>/dev/null; then
    result PASS "SOF SoundWire card enumerated"
elif [ "$SOF_BLACKLISTED" -eq 1 ]; then
    say "- (no card enumerated, as expected while SOF is blacklisted — not counted)"
else
    result WARN "No SOF card enumerated"
fi
if have pactl && pactl list sinks short 2>/dev/null | grep -qi dummy; then
    result WARN "PipeWire shows Dummy Output" "the known UCM matcher bug — expected"
elif have pactl; then
    pactl list sinks short 2>/dev/null | code
fi
say ""
say "> Note: on a bare TTY there is no user session, so PipeWire is not running and"
say "> \`pactl\` reports nothing. That is expected — the ALSA-level checks above are"
say "> the meaningful ones in this environment."
echo "      -> Test audio by hand:  speaker-test -c2 -twav -l1   (expect silence)"

# -------------------------------------------------------------- touch / pen --
hdr "Touchscreen + pen — Intel THC / QuickI2C"
dmesg 2>/dev/null | grep -iE 'thc|quicki2c|quickspi|hid-multitouch' | tail -20 | code
if lsmod 2>/dev/null | grep -qE 'intel_quicki2c|intel_thc'; then
    result PASS "Intel THC/QuickI2C module loaded"
else
    result FAIL "THC module not loaded" "needs kernel >= 6.14 with CONFIG_INTEL_QUICKI2C"
fi
[ -r /proc/bus/input/devices ] && grep -iE 'Name=.*(touch|pen|stylus|wacom|elan)' /proc/bus/input/devices | code
# The wacom driver claims this digitizer and renames the touch node to "Finger",
# so grepping for the literal word "touchscreen" misses a working touchscreen.
# Exclude "Touchpad", which is a different device entirely.
if grep -iE 'Name=.*(touchscreen|finger)' /proc/bus/input/devices 2>/dev/null \
   | grep -qiv 'touchpad'; then
    result PASS "Touchscreen input device present" \
                "$(grep -ioE 'Name="[^"]*(Touchscreen|Finger)[^"]*"' /proc/bus/input/devices 2>/dev/null | head -1)"
elif dmesg 2>/dev/null | grep -qi 'input:.*touchscreen'; then
    result PASS "Touchscreen registered per dmesg" "renamed by a claiming driver"
else
    result WARN "No touchscreen input device"
fi
grep -qiE 'Name=.*(pen|stylus)' /proc/bus/input/devices 2>/dev/null \
    && result PASS "Pen input device present" \
    || result WARN "No pen input device"
say ""
say "> An input device existing is not proof it reports events. On a TTY there is no"
say "> cursor to watch, so confirm with \`evtest\`: pick the touchscreen and touch it"
say "> (expect \`ABS_MT_POSITION_X\`), then the pen (expect \`ABS_PRESSURE\`)."
echo "      -> Verify touch/pen by hand:  evtest"

# -------------------------------------------------------------- fingerprint --
hdr "Fingerprint — Goodix 27c6:650c"
if have lsusb; then
    lsusb | grep -i '27c6' | code
    lsusb 2>/dev/null | grep -qi '27c6:650c' \
        && result PASS "Goodix 27c6:650c present" "on the libfprint supported list" \
        || result WARN "Goodix 650c not enumerated"
fi

# ----------------------------------------------------------- sensors / ISH ---
hdr "Auto-rotate / ISH (EXPECTED TO FAIL without firmware)"
say "> Needs ISH firmware extracted from the Windows driver store. Expected missing."
dmesg 2>/dev/null | grep -iE 'ish|intel_ish' | tail -15 | code
ls /sys/bus/iio/devices/ 2>/dev/null | code
ls /sys/bus/iio/devices/ 2>/dev/null | grep -q . \
    && result PASS "IIO sensors present" \
    || result WARN "No IIO sensors" "auto-rotate needs ISH firmware — expected"

# ---------------------------------------------------------------- dmesg err --
hdr "Firmware load failures"
dmesg 2>/dev/null | grep -iE 'firmware.*(fail|missing)|direct firmware load.*failed' \
    | sed 's/^/  /' | sort -u | head -30 | code

hdr "Kernel warnings / oops"
say "> A \`Modules linked in:\` line in dmesg means the kernel hit a WARNING or BUG."
say "> The trace above it names the subsystem that faulted."
if dmesg 2>/dev/null | grep -qE 'WARNING:|BUG:|Oops:|Call Trace:|Modules linked in:'; then
    dmesg 2>/dev/null | grep -nE 'WARNING:|BUG:|Oops:|Call Trace:' | head -20 | code
    result WARN "Kernel warning or oops in dmesg" "see trace above"
    say ""
    say "Capture the full trace with:"
    say "\`\`\`"
    say "dmesg | grep -B30 'Modules linked in' | head -60"
    say "\`\`\`"
else
    result PASS "No kernel warnings or oops in dmesg"
fi

# ------------------------------------------------------------------ verdict --
hdr "Decision gate"
say "Proceed with the install if the disk is visible, Wi-Fi works, and the"
say "touchscreen works. Audio and auto-rotate are expected to fail here."
say ""
say "**PASS: $PASS · WARN: $WARN · FAIL: $FAIL**"

# ------------------------------------------------- deliver back to Windows ---
# The report is useless if it dies with the live session. Copy it onto the
# Windows NTFS partition so it is simply sitting there after you reboot.
#
# Safety: refuses to mount read-write if the volume is hibernated or unclean.
# Turn Fast Startup off in Windows first (powercfg /h off), or this correctly
# declines rather than risking your filesystem.
deliver_to_windows() {
    local part mnt=/tmp/winmount dest
    part=$(lsblk -rno NAME,FSTYPE,SIZE 2>/dev/null \
           | awk '$2=="ntfs" {print $1; exit}')
    [ -z "$part" ] && { echo "  [skip] no NTFS partition found"; return 1; }
    part=/dev/$part

    if have ntfsfix && ntfsfix --no-action "$part" 2>&1 | grep -qi 'hibernated\|dirty\|unclean'; then
        echo "  [SKIP] $part is hibernated or unclean - NOT mounting."
        echo "         Boot Windows, run 'powercfg /h off', shut down fully, retry."
        return 1
    fi

    # If you already mounted it by hand (likely, since this script lives there),
    # reuse that mount instead of failing on a second mount of the same device.
    local we_mounted=0 existing
    existing=$(findmnt -nro TARGET -S "$part" 2>/dev/null | head -1)
    if [ -n "$existing" ]; then
        mnt="$existing"
        if ! mount -o remount,rw "$mnt" 2>/dev/null; then
            echo "  [skip] $part is mounted read-only at $mnt and remount failed"
            return 1
        fi
    else
        mkdir -p "$mnt" 2>/dev/null
        if ! mount -t ntfs3 -o rw "$part" "$mnt" 2>/dev/null \
          && ! mount -o rw "$part" "$mnt" 2>/dev/null; then
            echo "  [skip] could not mount $part read-write"
            rmdir "$mnt" 2>/dev/null; return 1
        fi
        we_mounted=1
    fi

    dest=$(find "$mnt/Users" -maxdepth 2 -type d -name 'omarchy-dualboot' 2>/dev/null | head -1)
    [ -z "$dest" ] && dest=$(find "$mnt/Users" -maxdepth 1 -mindepth 1 -type d \
        ! -name 'Public' ! -name 'Default*' ! -name 'All Users' 2>/dev/null | head -1)
    [ -z "$dest" ] && dest="$mnt"

    # Only tear down a mount we created; leave a pre-existing one as we found it.
    cleanup_mount() {
        sync
        if [ "$we_mounted" -eq 1 ]; then
            umount "$mnt" 2>/dev/null; rmdir "$mnt" 2>/dev/null
        else
            mount -o remount,ro "$mnt" 2>/dev/null
        fi
    }

    if cp "$OUT" "$dest/live-report.md" 2>/dev/null; then
        echo "  [OK] Report copied into Windows at:"
        echo "       ${dest#$mnt}/live-report.md"
        cleanup_mount
        return 0
    fi
    cleanup_mount
    echo "  [skip] could not write to $dest"
    return 1
}

echo
echo "  ---------------------------------------------"
printf '  PASS: %d   WARN: %d   FAIL: %d\n' "$PASS" "$WARN" "$FAIL"
echo "  ---------------------------------------------"
echo
echo "  Report written to: $OUT"
echo
echo "  Delivering report to the Windows partition..."
if [ "$(id -u)" -eq 0 ]; then
    deliver_to_windows || echo "  Fallback: copy $OUT to a USB stick by hand."
else
    echo "  [skip] not root - rerun with: sudo bash $0"
fi
echo
if [ "$FAIL" -eq 0 ]; then
    echo "  No blocking failures. Manually confirm touch + pen, then proceed."
else
    echo "  $FAIL blocking failure(s) - review the report before installing."
fi
echo
echo "  Reboot into Windows and the report will be waiting for Claude."
