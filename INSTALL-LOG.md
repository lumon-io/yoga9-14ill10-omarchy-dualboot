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

| Test | Predicted | Actual | Notes |
|---|---|---|---|
| Installer sees the NVMe disk | yes (no VMD) | | |
| Wi-Fi BE201 associates | yes | | `dmesg \| grep iwlwifi` |
| Bluetooth adapter present | likely | | needs `btintel_pcie` |
| GPU — no freeze under load | yes on ≥7.2 | | try a WebGL/glxgears load |
| Speakers audible | **no — UCM fix needed** | | the expected failure |
| Internal mic captures | unknown | | |
| Headphone jack | yes | | |
| Touchscreen responds | yes (quicki2c) | | `dmesg \| grep -i thc` |
| Pen: pressure + tilt + buttons | yes | | |
| Touchpad | yes | | |
| Screen brightness keys | unknown | | |
| Auto-rotate | **no — ISH firmware needed** | | expected failure |
| Webcam | likely | | |
| Suspend / resume | may wake instantly | | ELAN touchpad wake source |

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
4. **Bluetooth `btintel_pcie` works on this exact adapter.**
5. **BitLocker is off.** Inferred from a registry hint, not confirmed.
