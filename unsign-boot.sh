#!/usr/bin/env bash
# unsign-boot.sh - undo the Secure Boot signing, and fix the Limine hash mismatch
# it causes.
#
# Why this exists:
#   This firmware discards custom Secure Boot keys on every boot (see assumption 1
#   in INSTALL-LOG.md), so the signatures sbctl applied are worthless. They are not
#   harmless, though: limine.conf pins the UKI by BLAKE2b hash, and appending an
#   Authenticode signature changes the file, so Limine warns at every boot:
#
#     WARNING: Blake2b hash for URI 'boot():/EFI/Linux/omarchy_linux.efi'
#              does not match!
#
#   Worse, sbctl installs a pacman hook that re-signs after every kernel update,
#   which would re-break the hash each time. So the files have to come out of
#   sbctl's database, not just get re-hashed once.

set -uo pipefail

UKI=/boot/EFI/Linux/omarchy_linux.efi
CONF=/boot/limine.conf

red() { printf '\033[31m%s\033[0m\n' "$*"; }
grn() { printf '\033[32m%s\033[0m\n' "$*"; }
ylw() { printf '\033[33m%s\033[0m\n' "$*"; }
hdr() { printf '\n\033[1m== %s ==\033[0m\n' "$*"; }

[ "$(id -u)" -eq 0 ] || { red "must run as root: sudo bash $0"; exit 1; }

# Compare the hash limine.conf pins against the file as it stands. Limine uses
# BLAKE2b-512, which is what b2sum produces by default.
hash_ok() {
    local want have
    want=$(grep -oE 'omarchy_linux\.efi#[0-9a-f]+' "$CONF" 2>/dev/null | head -1 | cut -d'#' -f2)
    [ -n "$want" ] || return 2          # no hash pinned at all
    have=$(b2sum "$UKI" 2>/dev/null | cut -d' ' -f1)
    [ "$want" = "$have" ]
}

hdr "Before"
if hash_ok; then
    grn "  hash already matches - nothing to fix"
    exit 0
else
    ylw "  hash mismatch confirmed (this is what Limine is warning about)"
fi

# ---------------------------------------------------------------------------
# 1. Stop sbctl re-signing on every kernel update.
# ---------------------------------------------------------------------------
hdr "Removing files from sbctl's signing database"
for f in "$UKI" /boot/EFI/limine/limine_x64.efi; do
    if sbctl remove-file "$f" 2>/dev/null; then
        echo "  removed  $f"
    else
        echo "  not registered  $f"
    fi
done

# ---------------------------------------------------------------------------
# 2. Re-pin the hash. Cheapest first: regenerating the config re-hashes whatever
#    is on disk now, signature and all, which is enough to stop the warning.
# ---------------------------------------------------------------------------
hdr "Regenerating limine.conf"
limine-update || ylw "  limine-update returned non-zero"

if hash_ok; then
    grn "  hash matches now"
else
    # The config generator kept the old hash, so rebuild the UKI itself. With the
    # file out of sbctl's database above, this produces an unsigned image and the
    # regenerated config hashes that.
    ylw "  still mismatched - rebuilding the UKI"
    hdr "mkinitcpio -P"
    mkinitcpio -P || { red "  mkinitcpio failed"; exit 1; }
    hdr "Regenerating limine.conf again"
    limine-update || ylw "  limine-update returned non-zero"
fi

hdr "Result"
if hash_ok; then
    grn "  hash matches - Limine will boot without the warning"
else
    red "  hash STILL does not match"
    ylw "  Booting works: press Y at the warning. 'hash_mismatch_panic: no' is"
    ylw "  already set in limine.conf, so this is a prompt, not a failure."
    exit 1
fi

hdr "Windows entry still present?"
if grep -q 'bootmgfw.efi' "$CONF"; then
    grn "  yes - the chainload entry survived the regeneration"
else
    red "  NO - limine-update dropped it. Re-append the block from"
    red "  SECUREBOOT-QUICKSTART.md, section 'Re-adding the Windows entry'."
fi
