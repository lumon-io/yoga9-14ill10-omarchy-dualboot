# Live USB quickstart

Four commands to run from the Omarchy live environment. Read-only: nothing is
partitioned, formatted, or installed. Safe to abort at any point.

## Before you boot

1. BIOS (F2) → Security → Secure Boot → **Disabled**.
   Required: the Omarchy ISO is not Microsoft-signed, and this machine ships with
   *Allow Microsoft 3rd Party UEFI CA* disabled, so even shim-signed distros are
   rejected. Windows Hello biometrics break while it's off — expected, restored later.
2. In Windows first: `powercfg /h off` (elevated), then **shut down fully, not restart**.
   Verify with `powercfg /a` — *Hibernate* and *Fast Startup* should both read as
   unavailable. Ignore `HiberbootEnabled` in the registry; it stays at `1` and is only
   a preference flag. Without this the Windows filesystem stays hibernated, and the
   script will refuse to write the report back rather than risk corrupting it.
3. Boot the USB (F12 for the boot menu).

## There is no live desktop — get a shell first

The Omarchy ISO boots **straight into the installer**. There is no live session to
poke around in. It is archiso underneath: root auto-logs in on **TTY1**, and the shell
profile launches `.automated_script.sh` only when it detects TTY1.

So switch to another console:

```
Ctrl+Alt+F2          # F3 or F4 if F2 is occupied
login: root          # empty password, just press Enter
```

`Ctrl+Alt+F1` goes back to the installer. Nothing has been written to disk at this
point — the installer does not touch anything until you confirm a partition layout.

If the TTY switch doesn't work, press `Ctrl+C` in the installer to abort to a root
shell on TTY1. If the screen never renders at all, press `e` at the boot menu and add
`nomodeset` to the kernel line.

## Run the check

From that root shell. The script lives on your Windows partition, so you don't need a
network connection or a second USB stick.

You are already root on the TTY, so no `sudo` is needed.

```bash
# 1. Find the Windows NTFS partition (usually nvme0n1p3)
lsblk -o NAME,SIZE,FSTYPE,LABEL

# 2. Mount it read-only and grab the script
mkdir -p /mnt/win
mount -o ro /dev/nvme0n1p3 /mnt/win
cp /mnt/win/Users/<you>/omarchy-dualboot/live-usb-check.sh /tmp/
umount /mnt/win

# 3. Run it — writes the report back into Windows
bash /tmp/live-usb-check.sh /tmp
```

If Wi-Fi is up you can skip all of that:

```bash
curl -fsSLO https://raw.githubusercontent.com/lumon-io/yoga9-14ill10-omarchy-dualboot/main/live-usb-check.sh
bash live-usb-check.sh /tmp
```

The script prints a PASS/WARN/FAIL summary, writes `live-report.md`, and copies it
into your Windows user folder. Reboot into Windows and it's waiting there.

## Also worth doing by hand

From a bare TTY there is no cursor and no desktop, so "does the pointer move" is not
a test you can run. Use the event devices directly instead.

**Audio** — expect silence; that is the known UCM bug, not a hardware failure:

```bash
speaker-test -c2 -twav -l1
```

PipeWire is not running on a bare TTY, so `pactl` reports nothing. That is normal.
The ALSA-level checks (`aplay -l`, `/proc/asound/cards`) are the meaningful ones here.

**Touchscreen and pen** — watch for raw events:

```bash
libinput list-devices | grep -iE 'touch|pen|stylus'
evtest                      # pick the touchscreen, then touch it; Ctrl+C to stop
evtest                      # rerun, pick the pen, press with the stylus
```

`evtest` printing `ABS_MT_POSITION_X` on touch, or `ABS_PRESSURE` on pen contact,
proves the digitizer works. If `evtest` isn't installed and you have Wi-Fi:
`pacman -Sy evtest`.

**Tablet mode / rotation:**

```bash
ls /sys/bus/iio/devices/    # expect empty - needs ISH firmware
```

**Suspend:**

```bash
systemctl suspend           # then wake it; does it resume, or wake instantly on its own?
```

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
