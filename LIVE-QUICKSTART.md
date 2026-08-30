# Live USB quickstart

Four commands to run from the Omarchy live environment. Read-only: nothing is
partitioned, formatted, or installed. Safe to abort at any point.

## Before you boot

1. BIOS (F2) → Security → Secure Boot → **Disabled**.
   Required: the Omarchy ISO is not Microsoft-signed, and this machine ships with
   *Allow Microsoft 3rd Party UEFI CA* disabled, so even shim-signed distros are
   rejected. Windows Hello biometrics break while it's off — expected, restored later.
2. In Windows first: `powercfg /h off` (elevated). Without it the Windows filesystem
   stays hibernated and the report can't be written back.
3. Boot the USB (F12 for the boot menu).

## Run the check

The script lives on your Windows partition, so you don't need a network connection
or a second USB stick.

```bash
# 1. Find the Windows NTFS partition (usually nvme0n1p3)
lsblk -o NAME,SIZE,FSTYPE,LABEL

# 2. Mount it read-only and grab the script
sudo mkdir -p /mnt/win
sudo mount -o ro /dev/nvme0n1p3 /mnt/win
cp /mnt/win/Users/<you>/omarchy-dualboot/live-usb-check.sh /tmp/
sudo umount /mnt/win

# 3. Run it (root, so it can write the report back into Windows)
sudo bash /tmp/live-usb-check.sh /tmp
```

If Wi-Fi is up you can skip all of that:

```bash
curl -fsSLO https://raw.githubusercontent.com/lumon-io/yoga9-14ill10-omarchy-dualboot/main/live-usb-check.sh
sudo bash live-usb-check.sh /tmp
```

The script prints a PASS/WARN/FAIL summary, writes `live-report.md`, and copies it
into your Windows user folder. Reboot into Windows and it's waiting there.

## Also worth doing by hand

The script can't judge these — you have to look and listen:

```bash
speaker-test -c2 -twav -l1      # expect SILENCE (known UCM bug, fixable)
```

- Touch the screen. Does the cursor move?
- Draw with the pen. Pressure and tilt?
- Fold into tablet mode. Does the keyboard disable? (expected: no, needs ISH firmware)
- Suspend and resume: `systemctl suspend` — does it wake immediately on its own?

## Reading the result

**Expected failures — not reasons to abort:**

- Silent speakers (missing ALSA UCM matcher)
- No auto-rotate / no IIO sensors (needs ISH firmware from the Windows driver)

**Real blockers — stop and reassess:**

- No `/dev/nvme0n1` — the installer can't see your disk
- No Wi-Fi
- No touchscreen (means the kernel is older than 6.14)
- Kernel below 6.14

**Decision gate:** disk visible + Wi-Fi working + touchscreen working → proceed.

## If the report can't be written back

The script refuses to mount the Windows filesystem read-write when it's hibernated
or unclean. That's deliberate — forcing it risks corrupting your Windows install.

Fix: boot Windows, run `powercfg /h off` elevated, shut down fully (not restart),
then try again. Or copy `/tmp/live-report.md` onto any FAT32 or exFAT USB stick by
hand — do **not** use the Omarchy installer stick, which is read-only ISO9660.
