# Install log

Real results, filled in as the install happens. Nothing below is confirmed until it
has a date and an outcome next to it.

Template per attempt — copy the block, don't overwrite previous entries.

---

## Attempt 1 — _(date)_

| Field | Value |
|---|---|
| BIOS version | |
| Omarchy ISO version | |
| Kernel after install | `uname -r` -> |
| Mesa version | |
| alsa-lib version | |
| Outcome | not started |

### Pre-flight

- [ ] `manage-bde -status C:` shows Protection Off
- [ ] `powercfg /h off` applied
- [ ] `Get-PartitionSupportedSize -DriveLetter C` allows the intended shrink
- [ ] BIOS updated
- [ ] Backup taken, Windows recovery USB created
- [ ] `bcdedit /enum firmware` saved to `boot-entries-before.txt`
- [ ] ISH firmware copied out of `C:\Windows\System32\DriverStore\FileRepository`

### Live USB test (before writing anything to disk)

Boot the Omarchy ISO and check. This is the cheap, zero-risk verification pass —
everything here is a research prediction until ticked.

**Run 1 — 2026-08-29 22:24 UTC. PASS 11 · WARN 5 · FAIL 0.**
Kernel `7.1.8-arch1-Watanare-T2-2-t2` — **wrong ISO, this is the Apple T2 Mac image.**
Results below are still informative (linux-t2 is Arch plus Apple patches) but must be
re-run on the standard Omarchy ISO before they count.

| Test | Predicted | Actual (run 1) | Notes |
|---|---|---|---|
| Installer sees the NVMe disk | yes (no VMD) | **PASS** | all 4 Windows partitions visible, NTFS intact |
| Wi-Fi BE201 | yes | **PASS** | `iwlwifi` loaded, firmware clean, `wlan0` up. Not associated, so no internet test |
| Bluetooth adapter | likely | **inconclusive** | `btintel_pcie` present in `Modules linked in:` but no adapter registered. Checker bug — now distinguishes driver-loaded from adapter-registered |
| GPU | yes on ≥7.2 | **PASS (driver)** | `xe` bound to `8086:64a0`, DMC firmware v2.29 loaded. Kernel is 7.1.8 — **below the 7.2 freeze fix**; no load test done |
| Speakers audible | no — UCM fix | **WORSE than predicted** | `--- no soundcards ---`. No SOF modules loaded at all, not a UCM matcher problem. Suspect the T2 ISO ships no `sof-firmware` |
| Touchscreen | yes (quicki2c) | **PASS** | `quicki2c-hid 056A:53E6 Touchscreen` registered; wacom renames it "Finger". Reported a false WARN — checker fixed |
| Pen | yes | **PASS** | `Wacom quicki2c-hid 056A:53E6 Pen`. Wacom AES digitizer, vendor `056A` |
| Touchpad | yes | **PASS** | `ELAN06FA:00 04F3:3293 Touchpad` via `hid-multitouch` |
| Fingerprint | yes | **PASS** | `27c6:650c` enumerated on USB bus 003 |
| Auto-rotate | no — ISH firmware | **BETTER than predicted** | `iio:device0`, `iio:device1` present, though `ish_lnlm.bin` load failed (`cmd 2 failed 10` ×3). Partial |
| Secure Boot off / UEFI | — | **PASS** | booted UEFI, Secure Boot confirmed off |
| Free space for install | — | **none yet** | `parted` shows 0 GiB free — C: not shrunk yet, as expected |

**Not yet tested:** speakers by ear, pen pressure/tilt via `evtest`, mic, headphone jack,
brightness keys, webcam, suspend/resume, GPU under load.

**Decision gate:** if the disk is visible, Wi-Fi works, and touchscreen works, proceed.
Audio and auto-rotate are expected to fail here and are fixable post-install.

### Partitioning

- Shrink amount actually achieved:
- Resulting layout:

### Install

- Path taken: guided free-space install / manual archinstall
- Did Omarchy accept a separate 2 GB boot partition?
- Errors hit:

### Bootloader

- [ ] `limine-scan` detected Windows
- [ ] Both entries boot
- Fallback needed?

### Secure Boot re-enable

- [ ] BIOS supports Custom Mode / clearing keys on this Lenovo BIOS **(unverified — first real test)**
- [ ] `sbctl status` showed Setup Mode enabled
- [ ] `sbctl enroll-keys -m` succeeded
- [ ] Limine signed, `sbctl verify` clean
- [ ] Secure Boot re-enabled, both OSes still boot
- [ ] **Windows Hello face + fingerprint working again**
- [ ] `VirtualizationBasedSecurityStatus = 2` confirmed in Windows

### Post-install fixes applied

- Audio UCM matcher:
- ISH firmware for auto-rotate:
- Touchpad wake disable:
- Other:

### Still broken

---

## Known-unverified assumptions carried into attempt 1

These are the places the research could be wrong. Ranked by how much damage a wrong
answer does.

1. ~~**Lenovo consumer BIOS supports custom Secure Boot key enrollment.**~~
   **RESOLVED 2026-08-29 — verified in BIOS Q9CN30WW.** Security → Secure Boot offers
   **"Reset to Setup Mode"** ("Clear PK, disable secure boot and enter Setup Mode"),
   which is exactly what `sbctl` requires, plus **"Restore Factory Keys"** as rollback.
   Note there is no "Custom" Secure Boot Mode on this firmware — Standard/User Mode is
   all it exposes, and that is fine. The keep-Windows-Hello plan is viable.
2. **Omarchy tolerates a separate 2 GB ESP-flagged boot partition.** Its installer
   assumes ESP and `/boot` are one partition. ← now the biggest unknown
3. **Limine detects Windows on a separate ESP.** Reported to fail sometimes.
4. **Bluetooth `btintel_pcie` works on this exact adapter.** Run 1 was inconclusive:
   driver present, no adapter registered. Recheck on the correct ISO.
5. **BitLocker is off.** Inferred from a registry hint, not confirmed.
6. **`sbctl enroll-keys -m` enrolls a Microsoft cert that can actually validate THIS
   Windows Boot Manager.** ← new, and the one that can leave Windows unbootable.
   Run 1's dmesg shows the firmware db carries **two** Microsoft certs:

   ```
   integrity: Loaded X.509 cert 'Microsoft Windows Production PCA 2011: a929023...'
   integrity: Loaded X.509 cert 'Microsoft Corporation: Windows UEFI CA 2023: aefc5fb...'
   ```

   Microsoft is migrating bootloader signing from the 2011 PCA to the **Windows UEFI
   CA 2023**. This machine runs Windows 11 Insider build 26300, so its Boot Manager may
   well be signed by the 2023 CA. If sbctl's bundled Microsoft certs are 2011-only,
   enrolling them and turning Secure Boot on would leave **Windows refusing to boot**.

   Before Phase 5: check which CA signed the bootloader, and consider
   `sbctl enroll-keys -m --firmware-builtin` (or equivalent) to also carry over the
   certs already in the firmware db. Rollback is *Restore Factory Keys* in BIOS.
