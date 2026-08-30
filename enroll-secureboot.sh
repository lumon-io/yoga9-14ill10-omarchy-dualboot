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
#   refuses to sign anything unless it can prove the 2023 CA is really in db.
#
# Nothing here is unrecoverable. If Windows will not boot afterwards:
#   BIOS (F2) -> Security -> Secure Boot -> Restore Factory Keys, or just
#   disable Secure Boot. The firmware Boot0002 Windows entry is never touched.
#
# The script is re-runnable and picks its own stage:
#   keys not enrolled, not in Setup Mode -> back up, pre-flight, send you to BIOS
#   in Setup Mode                        -> enroll, verify, sign
#   already enrolled                     -> verify and sign only

set -uo pipefail

# --check reports state and changes nothing: no backup written, no keys
# enrolled, no binaries signed. Used by 'sb' with no arguments.
CHECK_ONLY=0
case "${1:-}" in
    -c|--check) CHECK_ONLY=1 ;;
    "") ;;
    *) echo "usage: $0 [--check]" >&2; exit 2 ;;
esac

BACKUP_DIR=/var/lib/sbctl-backup
EFIVARS=/sys/firmware/efi/efivars
SBCTL_KEYS=/var/lib/sbctl/keys

# Two different namespaces, and mixing them up costs you an afternoon:
#   PK, KEK, SetupMode, SecureBoot, and every *Default -> EFI_GLOBAL_VARIABLE
#   db, dbx, dbt, dbr                                  -> EFI_IMAGE_SECURITY_DATABASE
GLOBAL_GUID=8be4df61-93ca-11d2-aa0d-00e098032b8c
SECDB_GUID=d719b2cb-3d3a-4596-a3bc-dad00e67656f

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

efivar_path() {
    case "$1" in
        db|dbx|dbt|dbr) echo "$EFIVARS/$1-$SECDB_GUID" ;;
        *)              echo "$EFIVARS/$1-$GLOBAL_GUID" ;;
    esac
}

# Read an EFI boolean. efivars files carry a 4-byte attribute prefix, so the
# value is byte 5. Reading it directly beats parsing sbctl's decorated output.
efibool() {
    local f
    f=$(efivar_path "$1")
    [ -f "$f" ] || { echo "missing"; return; }
    od -An -tu1 -j4 -N1 "$f" 2>/dev/null | tr -d ' \n'
}

SETUP_MODE=$(efibool SetupMode)
SECURE_BOOT=$(efibool SecureBoot)

hdr "Firmware state"
echo "  SetupMode  : $SETUP_MODE   (1 = Setup Mode, keys clearable)"
echo "  SecureBoot : $SECURE_BOOT   (1 = enforcing)"

ENROLLED=no
[ -d "$SBCTL_KEYS" ] && [ -n "$(ls -A "$SBCTL_KEYS" 2>/dev/null)" ] && ENROLLED=yes
echo "  sbctl keys : $ENROLLED"

# ---------------------------------------------------------------------------
# Backup. Only meaningful before Setup Mode clears things - once PK/KEK/db are
# gone there is nothing left to copy, and the *Default variables plus the BIOS
# "Restore Factory Keys" option are what actually get you back.
#
# Use cat, not cp: efivarfs entries carry the immutable attribute and cp trips
# over it, reporting a failure after having read the data perfectly well.
# ---------------------------------------------------------------------------
hdr "Backing up current Secure Boot variables"
if [ "$CHECK_ONLY" = 1 ]; then
    echo "  skipped - --check writes nothing"
else
    mkdir -p "$BACKUP_DIR"
    for v in PK KEK db dbx PKDefault KEKDefault dbDefault dbxDefault; do
        src=$(efivar_path "$v")
        if [ -f "$src" ]; then
            if cat "$src" > "$BACKUP_DIR/$v.efivar" 2>/dev/null; then
                echo "  saved  $v  ($(stat -c%s "$BACKUP_DIR/$v.efivar") bytes)"
            else
                echo "  FAILED $v"
                rm -f "$BACKUP_DIR/$v.efivar"
            fi
        else
            echo "  absent $v"
        fi
    done
    echo "  -> $BACKUP_DIR"
fi

# ---------------------------------------------------------------------------
# Prove the 2023 CA is somewhere we can get at. X.509 subject strings sit as
# plain ASCII inside the DER, so a raw grep over the variable is a fair test.
# ---------------------------------------------------------------------------
hdr "Checking which Microsoft CAs the firmware can give us"
src_used=""
for v in dbDefault db; do
    f=$(efivar_path "$v")
    [ -f "$f" ] || { printf '  %-10s (not present)\n' "$v"; continue; }
    g2023=no; g2011=no
    grep -qa "$MS_2023" "$f" && g2023=yes
    grep -qa "$MS_2011" "$f" && g2011=yes
    printf '  %-10s 2023 CA: %-3s  2011 PCA: %s\n' "$v" "$g2023" "$g2011"
    [ "$g2023" = yes ] && [ -z "$src_used" ] && src_used=$v
done

if [ -n "$src_used" ]; then
    grn "  OK - '$MS_2023' is reachable via $src_used."
else
    red "  '$MS_2023' NOT found in dbDefault or db."
    ylw "  Your Windows Boot Manager is signed by that CA. Without it, Windows"
    ylw "  will not boot once Secure Boot is on."
    ylw "  Stop here and work out where to get the cert before continuing."
    exit 1
fi

if ! sbctl enroll-keys --help 2>&1 | grep -q -- "--firmware-builtin"; then
    die "this sbctl has no --firmware-builtin flag; upgrade sbctl before continuing"
fi

# ---------------------------------------------------------------------------
# Stage 1: nothing enrolled and the firmware still holds its factory keys.
# ---------------------------------------------------------------------------
if [ "$SETUP_MODE" != "1" ] && [ "$ENROLLED" = no ]; then
    hdr "Next step: put the firmware in Setup Mode"
    if [ "$CHECK_ONLY" = 1 ]; then
        echo "  Nothing enrolled yet, and the firmware still holds its factory keys."
        echo "  Reboot -> F2 -> Security -> Secure Boot -> 'Reset to Setup Mode', F10,"
        echo "  boot back into Omarchy, then run:  sudo ~/dualboot/sb go"
        echo
        echo "  Do NOT touch 'Clear Intel PTT Key' - it wipes the TPM and your Hello PIN."
        exit 0
    fi
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
# Stage 2: Setup Mode is live and we have not enrolled yet. Enroll.
# ---------------------------------------------------------------------------
if [ "$SETUP_MODE" = "1" ] && [ "$CHECK_ONLY" = 1 ]; then
    hdr "Setup Mode is active - keys not enrolled yet"
    echo "  The firmware is waiting for keys. To enroll and sign, run:"
    echo "      sudo ~/dualboot/sb go"
    exit 0
fi

if [ "$SETUP_MODE" = "1" ]; then
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
    if [ "$ENROLLED" = yes ]; then
        ylw "  keys already exist in $SBCTL_KEYS - reusing them"
    else
        sbctl create-keys || die "sbctl create-keys failed"
    fi

    hdr "Enrolling keys"
    # -m  : Microsoft's certs as sbctl bundles them
    # -f  : the firmware's own built-in db and KEK - this is what carries 2023
    sbctl enroll-keys -m -f db,KEK \
        || die "sbctl enroll-keys failed. If Windows stops booting, recover with BIOS -> Restore Factory Keys."
else
    hdr "Keys already enrolled - skipping to verification and signing"
fi

# ---------------------------------------------------------------------------
# Verify what is actually in db now. This is the gate: if the 2023 CA is not
# there, signing Limine would only get you a machine that boots Linux and not
# Windows, which is the wrong half of the trade.
# ---------------------------------------------------------------------------
hdr "Verifying what actually landed in db"
dbf=$(efivar_path db)
if [ ! -f "$dbf" ]; then
    red "  db variable not present at $dbf"
    red "  Enrollment did not take. Leave Secure Boot off."
    exit 1
fi
if grep -qa "$MS_2023" "$dbf"; then
    grn "  present: $MS_2023   <- this is what boots your Windows"
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
if [ "$CHECK_ONLY" = 1 ]; then
    hdr "Signature status of the boot binaries"
    sbctl verify
    hdr "sbctl status"
    sbctl status
    hdr "Verdict"
    if [ "$SECURE_BOOT" = "1" ]; then
        grn "  Secure Boot is ON and your keys are enrolled. Nothing to do."
    else
        echo "  Keys are enrolled and '$MS_2023' is in db, so Windows will still boot."
        echo "  If anything above is listed as not signed, run:  sudo ~/dualboot/sb go"
        echo "  Once everything is signed: reboot -> F2 -> Secure Boot -> Enabled -> F10,"
        echo "  and boot Omarchy first."
    fi
    exit 0
fi

hdr "Signing boot binaries"
signed=0
failed=0
while IFS= read -r f; do
    case "$f" in
        */EFI/Microsoft/*) continue ;;   # Microsoft-signed already; never re-sign
    esac
    echo "  -> $f"
    if sbctl sign -s "$f"; then
        signed=$((signed + 1))
    else
        red "     failed: $f"
        failed=$((failed + 1))
    fi
done < <(find /boot/EFI /efi/EFI -type f -iname '*.efi' 2>/dev/null | sort -u)

[ "$signed" -gt 0 ] || die "signed nothing - is /boot mounted?"
echo "  signed $signed binaries, $failed failures"

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

  Backups of the firmware key variables are in /var/lib/sbctl-backup.
DONE
