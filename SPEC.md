# SPEC: Dual-boot Omarchy + Windows 11 on Lenovo Yoga 9 2-in-1 14ILL10

Written 2026-08-29. Start a fresh session from this file.

## Target machine (verified, not assumed)

| Item | Value |
|---|---|
| Model | LENOVO 83LC — Yoga 9 2-in-1 14ILL10 |
| BIOS | Q9CN30WW (2026-04-15) |
| CPU | Intel Core Ultra 7 258V (Lunar Lake), 8C/8T, Arc 140V (Xe2) |
| Disk | WD PC SN7100S, 953.9 GB, NVMe, GPT, **Standard NVMe controller (no Intel VMD/RST)** |
| Partitions | 1: ESP 256 MB · 2: MSR 16 MB · 3: C: 951.65 GB · 4: Recovery 1.95 GB (at end of disk) |
| Free on C: | 720.4 GB |
| OS | Windows 11 Pro **Insider Preview**, build 26300 |
| Wi-Fi | Intel BE201 (Wi-Fi 7) |
| Audio | Cirrus Logic CS42L43 + CS35L56 amps over SoundWire; Intel SST digital mics |
| Biometrics | Goodix MOC fingerprint + IR camera (Windows Hello face) |
| Security | Secure Boot ON; VBS running; HVCI + System Guard Secure Launch + SMM measurement active; ESS (Enhanced Sign-in Security) enabled |
| BitLocker | `BitlockerStatus\BootStatus = 0` — probably OFF, **must be confirmed with elevated `manage-bde -status C:`** |
| Fast Startup | **ON** — must be disabled |

## Decisions made

1. **Secure Boot: keep it ON via custom keys.** Enroll own keys plus Microsoft's (`sbctl enroll-keys -m`), sign only the Limine EFI binary. Preserves Windows Hello face/fingerprint, VBS/HVCI and System Guard. Secure Boot is OFF only during the install window.
2. **Space for Omarchy: ~250 GB.** Leaves Windows ~700 GB.
3. **Separate boot partition.** The 256 MB Windows ESP cannot hold Omarchy's ~100 MB UKIs plus Snapper snapshot entries. Because Omarchy assumes one partition is both ESP and `/boot`, this is implemented as a **second 2 GB FAT32 partition with boot+esp flags** mounted at `/boot`, not a true XBOOTLDR (ea00) partition. The Windows ESP is left untouched.

## Why Secure Boot matters here (context from prior investigation)

`Win32_DeviceGuard.RequiredSecurityProperties = {1,2,3}` includes **2 = Secure Boot**, and `RequirePlatformSecurityFeatures = 3`. With Secure Boot off, VBS refuses to launch, so there is no VTL1 secure kernel. ESS runs Hello's biometric matching and template storage inside VTL1, so face and fingerprint sign-in stop working entirely. The PIN is TPM-bound rather than Credential Guard-bound (CG is absent from `SecurityServicesRunning`), so the PIN survives.

---

## Phase 0 — Windows prep (all of this before touching partitions)

1. **Confirm BitLocker is off.** Elevated PowerShell: `manage-bde -status C:`
   If ON: Settings > Privacy & Security > Device encryption > toggle off, and **wait for full decryption**. Omarchy's free-space install refuses to run against an encrypted drive.
2. **Save the BitLocker recovery key** regardless: https://account.microsoft.com/devices/recoverykey
3. **Disable Fast Startup and hibernation** (elevated): `powercfg /h off`
   Prevents Linux from mounting a hibernated, dirty NTFS volume.
4. **Full backup.** Non-negotiable — repartitioning is the risky step.
5. **Create a Windows recovery USB** (`recoverydrive.exe`) as the escape hatch.
6. **Update BIOS via Lenovo Vantage now, not later.** Firmware updates can clear enrolled Secure Boot keys; doing it after Phase 5 means redoing key enrollment.
7. **Record current firmware boot entries:** `bcdedit /enum firmware > .\boot-entries-before.txt`
   (gitignored — the BCD GUIDs are machine-identifying, don't publish it)
8. **Copy out the ISH firmware** for auto-rotate/tablet mode, needed in Phase 6. Search `C:\Windows\System32\DriverStore\FileRepository` for Intel ISH firmware and stash it somewhere reachable from Linux.

## Phase 1 — Shrink C:

Disk Management > C: > Shrink Volume > **256000 MB** (250 GB).

If Windows offers far less than requested, unmovable files are pinned near the end of the volume. Fix: temporarily disable the pagefile and System Protection, reboot, shrink, then re-enable. Hibernation is already off from Phase 0.

Result: ~250 GB unallocated between C: and the Recovery partition. Do not touch the Recovery partition.

## Phase 2 — Install media

- Write the Omarchy ISO to USB (Rufus in GPT/UEFI mode, or Ventoy).
- **Disable Secure Boot in BIOS** (F2 at boot). Required to boot the installer. Hello biometrics will be broken from here until Phase 5 — expected, not a bug.
- Known gotcha: zero-fill the unallocated space before partitioning if the installer throws metadata parsing errors.

## Phase 3 — Install

Use `archinstall` manual partitioning. Omarchy's guided "Free space install" would claim the 256 MB Windows ESP, which is exactly what we are avoiding.

Layout inside the 250 GB of free space:

| Partition | Size | FS | Mount | Flags |
|---|---|---|---|---|
| Omarchy boot | 2 GB | fat32 | `/boot` | boot, esp |
| Omarchy root | remainder (~248 GB) | btrfs, LUKS2, `compress=zstd` | `/` | — |

Btrfs subvolumes: `@` → `/`, `@home` → `/home`, `@log` → `/var/log`, `@pkg` → `/var/cache/pacman/pkg`

Bootloader: Limine. Leave the Windows ESP unmounted and unmodified.

## Phase 4 — Boot menu

- Run `limine-scan` and accept the prompts to add Windows Boot Manager.
- Verify **both** entries boot before proceeding.
- Known issue: Limine sometimes fails to detect Windows on a separate ESP (omarchy#4579). Fallbacks in order: add the Windows entry to `/boot/limine.conf` by hand; use the firmware boot menu (F12); or switch to GRUB, which auto-detects Windows.

## Phase 5 — Re-enable Secure Boot (restores Windows Hello)

Order is strict — enrolling the config checksum *after* signing invalidates the signature.

```bash
# Remove splash from cmdline first (breaks signed boot otherwise)
sudo nvim /etc/default/limine     # "quiet splash" -> "quiet"
sudo limine-mkinitcpio

# BIOS (F2) -> Security -> Secure Boot -> "Reset to Setup Mode" [Enter], then reboot.
# That entry clears the PK, disables Secure Boot and enters Setup Mode in one action.
# This firmware has NO "Custom" Secure Boot Mode - Standard/User Mode is all it offers,
# and "Reset to Setup Mode" is the supported way in. Verified on BIOS Q9CN30WW.
sudo sbctl status                 # must show: Setup Mode: Enabled
sudo sbctl create-keys
sudo sbctl enroll-keys -m         # -m is MANDATORY: without Microsoft's keys, Windows will not boot
sudo sbctl list-enrolled-keys

# Extract a clean Limine binary, enroll config checksum, THEN sign
sudo bsdtar -xOf /var/cache/pacman/pkg/limine-*.pkg.tar.zst usr/share/limine/BOOTX64.EFI \
  | sudo tee /boot/EFI/limine/limine_x64.efi > /dev/null
pesign -S -i /boot/EFI/limine/limine_x64.efi     # expect: no signatures
b2sum /boot/limine.conf                          # copy hash only
sudo limine enroll-config /boot/EFI/limine/limine_x64.efi <HASH>
sudo sbctl sign -s /boot/EFI/limine/limine_x64.efi
sudo sbctl verify                                # only limine_x64.efi should be signed
```

Then in BIOS: Security → Secure Boot → **Enabled**. Once your PK is enrolled, *Platform
Mode* should read **User Mode** again and *Secure Boot Mode* stays **Standard** — that is
correct on this firmware, not a sign the custom keys failed. Set the boot order under
Boot → UEFI Boot Order: Limine first, Windows Boot Manager second.

**If enrollment goes wrong:** Security → Secure Boot → **Restore Factory Keys** puts PK,
KEK, db and dbx back to factory defaults. One-click rollback; Windows boots again.

**Two BIOS specifics on this machine:**

- *Allow Microsoft 3rd Party UEFI CA* is **Disabled** from the factory. That is the CA
  that signs shim, so a shim-based distro would not boot Secure Boot without enabling it.
  Irrelevant for the Limine + custom keys path — and `sbctl enroll-keys -m` enrolls
  Microsoft's certs from its own bundle regardless of this toggle.
- *Administrator Password* is **Not Set**. With no BIOS password, anyone with physical
  access can walk into this menu and hit "Restore Factory Keys", undoing your enrollment.
  Consider setting one after Phase 5 completes, since the whole point here is preserving
  a security posture.

**Do not touch "Clear Intel PTT Key."** Intel PTT is the firmware TPM holding your Hello
PIN and any BitLocker keys. Clearing it is unrelated to Secure Boot and will destroy both.

**Sign only `limine_x64.efi`.** Do not sign kernels, initramfs, or the `BOOTX64.EFI` fallback loader.

Re-signing is required after every Limine or kernel update. Automate with a pacman hook — see https://github.com/peregrinus879/omarchy-secure-boot-manager

**Verify Hello is restored:** boot Windows, confirm face/fingerprint sign-in works and that `Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard` reports `VirtualizationBasedSecurityStatus = 2` again.

## Phase 6 — Hardware fixes for this specific laptop

Reference for the same model: https://github.com/johnmeade/linux-yoga-9i-2-in-1-aura

- **Kernel: confirm >= 7.2.** The Arc 140V caused full system freezes under GPU load until the fix landed in mainline 7.2. Check `uname -r`; if Arch stable is behind, consider `linux-mainline` temporarily.
- **Audio (highest risk).** CS42L43 + CS35L56 over SoundWire. Works on current kernels but regressed on 6.17.8–6.18.4. Needs current `sof-firmware` and correct ALSA UCM configs. Symptom of the bad state: PipeWire shows streams playing, speakers silent, HDMI/USB audio fine.
- **Touchscreen + pen:** need kernel 6.14+. Pressure, tilt and side buttons all supported.
- **Auto-rotate / tablet mode:** install the ISH firmware saved in Phase 0. Without it: no gyro, no auto-rotate, no keyboard-disable in tent/tablet mode. Hyprland auto-rotate needs manual wiring — there is no drop-in equivalent to GNOME's handling.
- **Suspend:** may wake instantly from ELAN touchpad signals. Fix by disabling that wake source via a systemd service.
- **Post-wake lag:** cores can stick at 400 MHz for 1–2 min; switch to Performance power mode if persistent.
- **Fingerprint (Goodix):** reported working on 6.12+.
- **Copilot key:** emits a junk macro; remap with Input Remapper.
- Battery expectation on Linux: ~6–8 h balanced.

## Rollback

- Windows won't boot: recovery USB > `bootrec /rebuildbcd`, or restore boot order from `boot-entries-before.txt`.
- Abandon Omarchy: delete its two partitions, extend C: back, reset firmware boot order to Windows Boot Manager.
- Secure Boot enrollment went wrong: BIOS > restore factory Secure Boot keys, then re-run Phase 5.

## Open risks / verify at the time

- Two ESPs on one disk is off-spec. Widely reported working, but it is the least-standard part of this plan.
- Omarchy's installer expects ESP and `/boot` to be the same partition. If manual partitioning fights this, fall back to: guided free-space install onto the 256 MB Windows ESP, keep retained Snapper snapshots very low, and migrate `/boot` afterward.
- Windows Insider builds update aggressively and can reset firmware boot order. Re-check after large Windows updates.
- BitLocker state is inferred, not confirmed. Confirm in Phase 0 step 1.

## Sources

- Omarchy dual-boot manual: https://omarchy.org/manual/dual-boot-install/
- Manual archinstall partitioning for Omarchy: https://github.com/basecamp/omarchy/discussions/1651
- Omarchy Secure Boot + Windows dual boot: https://github.com/basecamp/omarchy/discussions/5306
- sbctl: https://github.com/Foxboron/sbctl
- Arch Wiki, EFI system partition: https://wiki.archlinux.org/title/EFI_system_partition
- Yoga 9i 2-in-1 Aura Linux support: https://github.com/johnmeade/linux-yoga-9i-2-in-1-aura
- CS42L43 kernel regression report: https://forum.endeavouros.com/t/regression-no-audio-on-kernel-6-17-8-intel-lunar-lake-cs42l43-works-on-6-17-7/76594
