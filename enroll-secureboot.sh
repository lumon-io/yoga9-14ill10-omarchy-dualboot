#!/usr/bin/env bash
# enroll-secureboot.sh - re-enable Secure Boot with custom keys on the Yoga 9 14ILL10,
# so Limine boots AND Windows Hello keeps working.
#
# The problem this solves:
#   Secure Boot ON  -> firmware rejects unsigned Limine; only Windows boots.
#   Secure Boot OFF -> both boot, but VBS cannot start, so Windows Hello
#                      face + fingerprint are disabled (PIN survives).
#
# The fix: enroll our own Platform Key, keep Microsoft's certs alongside it so
# Windows still boots, then sign Limine and the UKI with our key.
#
# CRITICAL, verified on this machine 2026-08-30:
#   bootmgfw.efi is signed by "Windows UEFI CA 2023", NOT "Microsoft Windows
#   Production PCA 2011". Enrolling only the 2011 cert makes Windows unbootable.
#   This script enrolls the FIRMWARE's built-in db/KEK, which carries both, and
#   refuses to proceed unless it can prove the 2023 CA is going in.
#
# Nothing here is unrecoverable. If Windows will not boot afterwards:
#   BIOS (F2) -> Security -> Secure Boot -> Restore Factory Keys, or just
#   disable Secure Boot. The firmware Boot0002 Windows entry is never touched.
#
# Run it twice:
#   pass 1  (normal boot)      -> backs up keys, checks prerequisites, tells you
#                                 to put the firmware in Setup Mode
#   pass 2  (after Setup Mode) -> enrolls keys, signs binaries, verifies

set -uo pipefail

BACKUP_DIR=/var/lib/sbctl-backup
EFIVARS=/sys/firmware/efi/efivars
GUID=8be4df61-93ca-11d2-aa0d-00e098032b8c   # EFI_GLOBAL_VARIABLE
MS_2023="Windows UEFI CA 2023"
MS_2011="Microsoft Windows Production PCA 2011"

red()  { printf '\033[31m%s\033[0m\n' "$*"; }
grn()  { printf '\033[32m%s\033[0m\n' "$*"; }
ylw()  { printf '\033[33m%s\033[0m\n' "$*"; }
hdr()  { printf '\n\033[1m== %s ==\033[0m\n' "$*"; }
die()  { red "ERROR: $*"; exit 1; }

[ "$(id -u)" -eq 0 ] || die "must run as root:  sudo bash $0"
[ -d "$EFIVARS" ]    || die "no efivarfs at $EFIVARS - not booted via UEFI?"
command -v sbctl >/dev/null || die "sbctl not installed:  sudo pacman -S sbctl"

# Read an EFI boolean variable. efivars files carry a 4-byte attribute prefix,
# so the value we want is byte 5. Parsing this directly avoids depending on
# sbctl's human-readable output format, which is unicode-decorated.
efibool() {
    local f="$EFIVARS/$1-$GUID"
    [ -f "$f" ] || { echo "missing"; return; }
    od -An -tu1 -j4 -N1 "$f" 2>/dev/null | tr -d ' \n'
}

SETUP_MODE=$(efibool SetupMode)
SECURE_BOOT=$(efibool SecureBoot)

hdr "Firmware state"
echo "  SetupMode  : $SETUP_MODE   (1 = Setup Mode, keys clearable)"
echo "  SecureBoot : $SECURE_BOOT   (1 = enforcing)"

# ---------------------------------------------------------------------------
# Backup first. This is our only offline copy of the 2023 CA if the firmware
# turns out not to expose dbDefault.
# ---------------------------------------------------------------------------
hdr "Backing up current Secure Boot variables"
mkdir -p "$BACKUP_DIR"
for v in PK KEK db dbx PKDefault KEKDefault dbDefault; do
    src="$EFIVARS/$v-$GUID"
    if [ -f "$src" ]; then
        if cp -f "$src" "$BACKUP_DIR/$v.efivar" 2>/dev/null; then
            echo "  saved  $v  ($(stat -c%s "$src") bytes)"
        else
            echo "  FAILED $v"
        fi
    else
        echo "  absent $v"
    fi
done
echo "  -> $BACKUP_DIR"

# ---------------------------------------------------------------------------
# Prove the 2023 CA is available to enroll. X.509 subject strings sit as plain
# ASCII inside the DER, so a raw grep over the variable is a reliable test.
# ---------------------------------------------------------------------------
hdr "Checking which Microsoft CAs the firmware can give us"
have_2023=no
src_used=""
for v in dbDefault db; do
    f="$EFIVARS/$v-$GUID"
    [ -f "$f" ] || continue
    g2023=no; g2011=no
    grep -qa "$MS_2023" "$f" && g2023=yes
    grep -qa "$MS_2011" "$f" && g2011=yes
    printf '  %-10s 2023 CA: %-3s  2011 PCA: %s\n' "$v" "$g2023" "$g2011"
    if [ "$g2023" = yes ] && [ -z "$src_used" ]; then
        have_2023=yes
        src_used=$v
    fi
done

if [ "$have_2023" = yes ]; then
    grn "  OK - '$MS_2023' is present in $src_used and will be enrolled."
else
    red "  '$MS_2023' NOT found in dbDefault or db."
    ylw "  Your Windows Boot Manager is signed by that CA. Enrolling without it"
    ylw "  means Windows will not boot with Secure Boot on."
    ylw "  Stop here and work out where to get the cert before continuing."
    exit 1
fi

# sbctl needs --firmware-builtin to pull those certs across. Older builds lack it.
if ! sbctl enroll-keys --help 2>&1 | grep -q -- "--firmware-builtin"; then
    die "this sbctl has no --firmware-builtin flag; upgrade sbctl before continuing"
fi

# ---------------------------------------------------------------------------
# Pass 1: not in Setup Mode yet. Stop and hand over to the firmware.
# ---------------------------------------------------------------------------
if [ "$SETUP_MODE" != "1" ]; then
    hdr "Next step: put the firmware in Setup Mode"
    cat <<'PASS1'
  Everything checked out. The firmware still holds its factory keys, so
  sbctl cannot enroll ours yet.

    1. Reboot and press F2 for BIOS setup.
    2. Security -> Secure Boot
    3. "Reset to Setup Mode"  [Enter]
       - do NOT touch "Clear Intel PTT Key" - that wipes the TPM, and with it
         your Windows Hello PIN and any BitLocker recovery binding
       - "Restore Factory Keys" on the same screen is your undo button
    4. F10 to save, boot back into Omarchy.
    5. Run this script again.

  Between now and then Windows still boots normally with Secure Boot off.
PASS1
    exit 0
fi

# ---------------------------------------------------------------------------
# Pass 2: Setup Mode is live. Enroll.
# ---------------------------------------------------------------------------
hdr "Setup Mode is active - ready to enroll"
echo "  This replaces the platform keys with:"
echo "    - a new key pair generated here, for signing Limine and the UKI"
echo "    - Microsoft's certs from the firmware's built-in db and KEK, which"
echo "      keeps Windows bootable and lets Windows still deliver dbx updates"
echo
read -rp "  Proceed? [y/N] " ans
case "$ans" in
    y|Y) ;;
    *) echo "aborted"; exit 0 ;;
esac

hdr "Creating keys"
if [ -d /var/lib/sbctl/keys ] && [ -n "$(ls -A /var/lib/sbctl/keys 2>/dev/null)" ]; then
    ylw "  keys already exist in /var/lib/sbctl/keys - reusing them"
else
    sbctl create-keys || die "sbctl create-keys failed"
fi

hdr "Enrolling keys"
# -m  : Microsoft's certs as sbctl bundles them
# -f  : the firmware's own built-in db and KEK - this is what carries the 2023 CA
sbctl enroll-keys -m -f db,KEK \
    || die "sbctl enroll-keys failed. If Windows stops booting, recover with BIOS -> Restore Factory Keys."

hdr "Verifying what actually landed in db"
dbf="$EFIVARS/db-$GUID"
if grep -qa "$MS_2023" "$dbf"; then
    grn "  present: $MS_2023"
else
    red "  MISSING: $MS_2023"
    red "  Windows will NOT boot with Secure Boot enabled."
    ylw "  Leave Secure Boot off. Recover with BIOS -> Restore Factory Keys."
    exit 1
fi
if grep -qa "$MS_2011" "$dbf"; then
    grn "  present: $MS_2011"
else
    ylw "  absent : $MS_2011 - fine, it is not what signs your bootmgfw"
fi

# ---------------------------------------------------------------------------
# Sign. Two things need our signature, for different reasons:
#   - Limine's EFI binary: the firmware LoadImage()s it directly.
#   - the UKI: Limine chainloads it with 'protocol: efi', which is also a
#     firmware LoadImage() call, so Secure Boot validates it too. Signing only
#     Limine gets you a boot menu that then refuses to start Linux.
# 'sbctl sign -s' records each file in sbctl's database, so the pacman hook
# re-signs them automatically after a limine or kernel upgrade.
# ---------------------------------------------------------------------------
hdr "Signing boot binaries"
signed=0
while IFS= read -r f; do
    case "$f" in
        */EFI/Microsoft/*) continue ;;   # Microsoft-signed already; never re-sign
    esac
    echo "  -> $f"
    if sbctl sign -s "$f"; then
        signed=$((signed + 1))
    else
        red "     failed: $f"
    fi
done < <(find /boot/EFI /efi/EFI -type f -iname '*.efi' 2>/dev/null | sort -u)

[ "$signed" -gt 0 ] || die "signed nothing - is /boot mounted?"
echo "  signed $signed binaries"

hdr "sbctl verify"
sbctl verify

hdr "sbctl status"
sbctl status

hdr "Done - what to do next"
cat <<'DONE'
  1. Reboot into BIOS (F2) -> Security -> Secure Boot -> Enabled. F10.
  2. You should land in the Limine menu. Boot Omarchy first - if the UKI was
     missed by the signing step the firmware refuses it here, and you can just
     turn Secure Boot back off.
  3. Then reboot and boot the Windows entry. If it fails, F12 -> Windows Boot
     Manager still works, and BIOS -> Restore Factory Keys undoes everything.
  4. In Windows, confirm Hello came back. In an elevated PowerShell:
       Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard `
         -ClassName Win32_DeviceGuard |
         Select-Object VirtualizationBasedSecurityStatus, SecurityServicesRunning
     VirtualizationBasedSecurityStatus should be 2 (running), and face and
     fingerprint should be offered again at the lock screen.

  Backups of the original firmware keys are in /var/lib/sbctl-backup.
DONE
