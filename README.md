# Omarchy + Windows 11 dual boot on the Lenovo Yoga 9 2-in-1 14ILL10

Pre-install compatibility research and a dual-boot procedure for the Lenovo Yoga 9
2-in-1 14ILL10 (machine type **83LC**, Intel Core Ultra 7 258V "Lunar Lake").

> **Status: PLANNED, NOT YET EXECUTED.**
> The hardware inventory and driver cross-references below are **verified** — measured
> on the machine and checked against upstream sources. The install procedure is
> **untested**. See [INSTALL-LOG.md](INSTALL-LOG.md) for real results as they land.
> Do not treat the procedure section as a known-good walkthrough yet.

## Why this document exists

Two things were missing from every dual-boot guide we could find:

1. **Nobody explains that disabling Secure Boot breaks Windows Hello biometrics** on
   machines like this one, or that you can avoid it. Every Omarchy dual-boot guide
   says "disable Secure Boot" and stops there. On this laptop that silently costs you
   face and fingerprint sign-in. [See below](#the-secure-boot--windows-hello-trap).
2. **Model-specific driver status for the 14ILL10 in one place**, with the actual
   hardware IDs so you can confirm you have the same silicon.

## TL;DR verdict

**Worth attempting.** No hardware wall. Every component either works on a current
kernel or has a known, documented config fix. The two rough edges are audio UCM
config and auto-rotate firmware extraction — both solvable, neither a blocker.

---

## Verified hardware inventory

Generated with [`collect-hardware.ps1`](collect-hardware.ps1) (read-only; run it on
your own machine and compare). Full output in [HARDWARE.md](HARDWARE.md).

| Item | Value |
|---|---|
| Model | LENOVO 83LC — Yoga 9 2-in-1 14ILL10 |
| BIOS | Q9CN30WW (2026-04-15) |
| CPU | Intel Core Ultra 7 258V (Lunar Lake), 8C/8T |
| RAM | 32 GB (soldered) |
| GPU | Intel Arc 140V (Xe2), 16 GB shared |
| Disk | WD PC SN7100S 1 TB NVMe, GPT |
| ESP | **260 MB** (this matters — see [boot partition](#the-260-mb-esp-problem)) |

## Compatibility matrix

Legend: **verified** = checked against an upstream source, linked.
**likely** = strong indication, not directly confirmed.

| Component | Hardware ID | Linux driver | Status |
|---|---|---|---|
| GPU Arc 140V (Xe2) | `PCI 8086:64A0` | `xe` | **Green on kernel ≥ 7.2.** Earlier kernels had full system freezes under GPU load; fix landed in mainline 7.2. |
| NVMe SSD | `PCI 15B7:5044` | `nvme` | **Green, verified.** Enumerates as a *Standard NVM Express Controller* — no Intel VMD/RST. This is the usual reason Linux installers see no disk on Lenovo machines; you are not affected. |
| Wi-Fi 7 BE201 | `PCI 8086:A840` | `iwlwifi` | **Green on 6.11+**, needs current `linux-firmware`. Firmware-not-found errors on older distro kernels are common. |
| Bluetooth | `PCI 8086:A876` | `btintel_pcie` | **Likely green.** Lunar Lake moved Bluetooth to PCIe, needing the newer `btintel_pcie` driver rather than the old USB path. Not directly verified — confirm from live USB. |
| Fingerprint (Goodix MOC) | `USB 27c6:650c` | `libfprint` | **Green, verified.** [`27c6:650c` is on the libfprint supported-devices list](https://fprint.freedesktop.org/supported-devices.html). Notable — many Goodix MOC readers are not. |
| Touchscreen + pen | `PCI 8086:A848` (Intel THC) | `intel-quicki2c` | **Green, verified.** Lunar Lake uses the Intel Touch Host Controller, not classic I2C-HID. [`CONFIG_INTEL_QUICKI2C`](https://cateee.net/lkddb/web-lkddb/INTEL_QUICKI2C.html) (kernel 6.14+, requires `CONFIG_INTEL_THC_HID`) explicitly lists *Core Ultra 200V Series Touch Host Controllers*. Pen pressure, tilt and side buttons all work. |
| Audio — speakers/mic | SoundWire ctlr `A828`; CS42L43 codec + CS35L56 amps | `snd_sof_intel` / SoundWire | **Yellow — config fix required.** See [audio](#audio-the-one-you-will-actually-hit). |
| Auto-rotate / tablet mode | `VID 8087&PID 0AC2` (Intel ISH) | `intel-ish-hid` | **Yellow.** Needs ISH firmware extracted from the Windows driver. Without it: no gyro, no auto-rotate, no keyboard-disable in tent/tablet mode. |
| Ambient light / presence | Elliptic Labs `ELAS E551` | none | **Red, cosmetic.** No Linux driver for the Elliptic Labs human-presence sensor. Nothing depends on it. |
| Webcam + IR camera | `USB 5986:2177` | `uvcvideo` | **Likely green** for the RGB camera. IR camera is only useful with Howdy; there is no Hello-equivalent out of the box. |
| Copilot key | — | — | Emits a junk macro. Remap with Input Remapper. |

**Minimum kernel: 6.14.** **Recommended: 7.2+** (GPU freeze fix). Arch's rolling
kernel makes this a non-issue; fixed-release distros will struggle.

---

## The Secure Boot → Windows Hello trap

This is the part no other guide covers.

Every Omarchy dual-boot guide tells you to disable Secure Boot, because Limine is not
signed by Microsoft. On this laptop, that has a consequence nobody mentions:
**Windows Hello face and fingerprint stop working entirely.**

The chain:

```
Secure Boot OFF
  -> VBS refuses to launch (RequiredSecurityProperties includes 2 = Secure Boot)
    -> no VTL1 secure kernel
      -> Enhanced Sign-in Security (ESS) has no enclave
        -> Hello face + fingerprint disabled
```

Confirm it on your own machine:

```powershell
Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard |
  Select-Object VirtualizationBasedSecurityStatus, SecurityServicesRunning, RequiredSecurityProperties
```

If `RequiredSecurityProperties` contains **2**, VBS on your machine requires Secure
Boot. On the 14ILL10 it reads `{1, 2, 3}` — base virtualization, Secure Boot, DMA
protection — and `RequirePlatformSecurityFeatures = 3`.

ESS is active if `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WinBio` shows
`ESSCapableOnLastStart = 1`. ESS runs biometric matching and template storage inside
VTL1, which is why it dies with VBS.

**Your PIN survives.** Credential Guard is not running (absent from
`SecurityServicesRunning`), so the Hello NGC container is TPM-bound rather than
VBS-bound. If your PIN *also* broke, the TPM was cleared — a different problem.

**The fix:** don't leave Secure Boot off. Enroll your own keys alongside Microsoft's
and sign Limine yourself. Secure Boot goes back on, VBS restarts, Hello returns.
Procedure in [SPEC.md](SPEC.md) Phase 5. The critical flag is `sbctl enroll-keys -m`
— **without `-m`, Microsoft's keys are excluded and Windows stops booting.**

### Does this BIOS actually allow it? Yes — verified

Checked in BIOS **Q9CN30WW** (Security → Secure Boot). This is the prerequisite the
whole plan rests on, so confirm it on your own machine before starting:

| Setting | Factory value | Meaning |
|---|---|---|
| Secure Boot Status | Enabled | |
| Platform Mode | User Mode | Factory PK enrolled |
| Secure Boot Mode | **Standard** | **There is no "Custom" mode on this firmware** |
| Reset to Setup Mode | `[Enter]` | "Clear PK, disable secure boot and enter Setup Mode" — **this is what `sbctl` needs** |
| Restore Factory Keys | `[Enter]` | Restores PK, KEK, db, dbx — one-click rollback |
| Allow Microsoft 3rd Party UEFI CA | **Disabled** | The CA that signs shim. Irrelevant for Limine + custom keys |
| Enhanced Windows Biometric Security | Enabled | ESS, at the firmware level — the Hello dependency above |
| Intel Platform Trust Technology | Enabled | fTPM. **Never use "Clear Intel PTT Key"** — it destroys your Hello PIN and BitLocker keys |
| Administrator Password | Not Set | Nothing stops someone restoring factory keys; consider setting one |

Guides written for ASUS boards tell you to set "Secure Boot Mode: Custom". That option
does not exist here. **Use "Reset to Setup Mode" instead**, enroll, then set Secure Boot
back to Enabled — Platform Mode returns to *User Mode* and Secure Boot Mode stays
*Standard*. That is correct, not a failed enrollment.

> **If you photograph your own BIOS, don't publish the shots as-is.** The Information
> page exposes your Lenovo serial, UUID, MTM and OA3 key ID, and the Security page shows
> the SSD serial. Redact before posting anywhere.

---

## The 260 MB ESP problem

Omarchy uses Unified Kernel Images: kernel + initramfs + cmdline fused into one EFI
file, roughly 100 MB each. Its Snapper integration wants one UKI per bootable
snapshot. Windows created a 260 MB ESP here, already holding Windows Boot Manager.

Two UKIs will not fit. You will hit "no space left on device" during a kernel update.

Complicating this: **Omarchy assumes one partition serves as both ESP and `/boot`**,
and people attempting a spec-compliant separate-EFI layout have hit installer
failures. The community workaround is a **second 2 GB FAT32 partition with boot+esp
flags**, mounted at `/boot`, leaving the Windows ESP untouched. Two ESPs on one disk
is technically off-spec but is widely reported working.

Alternatives, if that fights you:
- Install onto the existing 260 MB ESP and keep retained Snapper snapshots very low.
- Grow the ESP to 1 GB by shifting MSR and C: rightward with GParted. Slow and risky
  on a 1 TB drive; not recommended.

---

## Audio: the one you will actually hit

Symptom: PipeWire shows streams playing, speakers silent, HDMI and USB audio fine.
`dmesg` shows cs42l43 and cs35l56 reporting missing power supplies and "using dummy
regulator".

Root cause is **not** a missing driver. ALSA UCM has no matcher for this machine's
`CardLongName`, so no profile loads and output falls back to Dummy Output. The
`sof-soundwire` profile already contains the correct cs42l43/cs35l56 routes — it just
never gets selected. Adding a device-specific matcher under `/usr/share/alsa/ucm2/`
is the fix.

Also relevant:
- Some UCM files require **Syntax 7**; an older ALSA runtime cannot activate the
  speaker path even with the right profile. Check your `alsa-lib` version.
- Audio **regressed on kernels 6.17.8–6.18.4** on this codec combination and worked
  on 6.17.7. If audio breaks after an update, suspect the kernel before your config.
- Keep `sof-firmware` current.

Related upstream reports: [alsa-ucm-conf#619](https://github.com/alsa-project/alsa-ucm-conf/issues/619) ·
[thesofproject/sof#9720](https://github.com/thesofproject/sof/issues/9720) ·
[Ubuntu #2137115](https://bugs.launchpad.net/ubuntu/+source/linux-firmware/+bug/2137115)

---

## Before you start

Run [`collect-hardware.ps1`](collect-hardware.ps1) elevated and compare against
[HARDWARE.md](HARDWARE.md). Then confirm these four:

1. **BitLocker is OFF** — `manage-bde -status C:`. Omarchy's free-space installer
   refuses to run against an encrypted drive. Save your recovery key regardless.
2. **Fast Startup is OFF** — `powercfg /h off`. Otherwise Linux may mount a
   hibernated, dirty NTFS volume and corrupt it.
3. **Shrink actually yields what you need** — `Get-PartitionSupportedSize -DriveLetter C`.
   Unmovable files pinned near the end of the volume routinely cap this far below
   free space. Disable pagefile + System Protection, reboot, then shrink.
4. **BIOS updated first.** Firmware updates can clear enrolled Secure Boot keys,
   which means redoing key enrollment.

**Then boot the live USB before committing anything.** Fifteen minutes of testing
audio, Wi-Fi, touchscreen and pen from the live environment tells you more than any
research. Nothing is written to disk.

Run [`live-usb-check.sh`](live-usb-check.sh) from the live environment — read-only,
writes one report file:

```bash
curl -fsSLO https://raw.githubusercontent.com/lumon-io/yoga9-14ill10-omarchy-dualboot/main/live-usb-check.sh
bash live-usb-check.sh /run/media/<your-usb>     # or just: bash live-usb-check.sh
```

It checks every row of the compatibility matrix above and prints PASS/WARN/FAIL plus
a decision gate. **Audio and auto-rotate are expected to FAIL there** — those are the
known-fixable ones, not a reason to abort.

## Working across the reboot

Notes for anyone doing this with an AI assistant, or just keeping their own records —
the live USB is a context break, so plan for it.

| Phase | What works |
|---|---|
| **Windows, pre-install** | Normal session. Run `collect-hardware.ps1`, do the pre-flight. |
| **Live USB** | No session — the Windows install it lived on is not running. Use `live-usb-check.sh`, save the report to a USB stick, reboot to Windows and hand the file over. Rebooting back is free at this stage since nothing is installed yet. |
| **During install** | Don't try. The installer owns the screen. Keep this repo open on your phone; photograph anything that goes wrong. |
| **Omarchy, post-install** | Normal session again — install the assistant on Linux, `git clone` this repo, continue from [SPEC.md](SPEC.md). |

Optionally you *can* run an assistant inside the live environment: it needs working
Wi-Fi (which is itself one of the tests, so it doubles as a check). The archiso overlay
defaults to 2 GB — press `e` at the boot menu and add `cow_spacesize=8G` if you plan to
install packages there. Everything is lost on reboot, including the transcript, which is
why the report file is the more reliable path.

The repo itself is the handoff mechanism: it survives the reboot, and a fresh session on
the Linux side can pick up from `SPEC.md` and `INSTALL-LOG.md` with no lost context.

## Files

| File | Purpose |
|---|---|
| `README.md` | This document — compatibility research |
| `SPEC.md` | The step-by-step install procedure |
| `HARDWARE.md` | Full generated hardware report from the reference machine |
| `collect-hardware.ps1` | Read-only collector; run on your machine to compare |
| `LIVE-QUICKSTART.md` | Four commands to run from the live USB |
| `live-usb-check.sh` | Read-only hardware check to run from the live USB |
| `INSTALL-LOG.md` | Actual results, filled in during the install |

## Sources

- [Omarchy dual-boot manual](https://omarchy.org/manual/dual-boot-install/)
- [Omarchy manual archinstall partitioning](https://github.com/basecamp/omarchy/discussions/1651)
- [Omarchy Secure Boot + Windows dual boot](https://github.com/basecamp/omarchy/discussions/5306)
- [sbctl](https://github.com/Foxboron/sbctl) · [sbctl: Linux/Windows dual boot with BitLocker](https://github.com/Foxboron/sbctl/wiki/Linux-Windows-Dual-Boot-with-Windows-Bitlocker)
- [libfprint supported devices](https://fprint.freedesktop.org/supported-devices.html)
- [Intel THC kernel documentation](https://docs.kernel.org/hid/intel-thc-hid.html) · [CONFIG_INTEL_QUICKI2C](https://cateee.net/lkddb/web-lkddb/INTEL_QUICKI2C.html)
- [Arch Wiki: EFI system partition](https://wiki.archlinux.org/title/EFI_system_partition) · [Arch Wiki: Limine](https://wiki.archlinux.org/title/Limine)
- [johnmeade/linux-yoga-9i-2-in-1-aura](https://github.com/johnmeade/linux-yoga-9i-2-in-1-aura) — same model, general Linux notes
- [CS42L43 kernel regression report](https://forum.endeavouros.com/t/regression-no-audio-on-kernel-6-17-8-intel-lunar-lake-cs42l43-works-on-6-17-7/76594)

## Contributing

If you run this on a 14ILL10, please open a PR against `INSTALL-LOG.md` with your
BIOS version, kernel version, and what worked or didn't. The audio UCM matcher in
particular deserves an upstream fix rather than a per-machine workaround.
