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

### Pre-flight — **DONE 2026-08-29 22:42**, verdict CLEAR

- [x] BitLocker OFF — `Protection: OFF, Fully decrypted` (confirmed elevated, not inferred)
- [x] `powercfg /h off` applied — `HibernateEnabled=0`, no `hiberfil.sys`
- [x] Shrink headroom — 678.11 GB shrinkable, needed 250
- [x] Windows recovery USB created — 2026-08-30
- [x] `bcdedit /enum firmware` saved (UTF-16 LE, 3376 bytes). Baseline firmware order:
      `{bootmgr}` (Windows Boot Manager) → EFI USB Device → EFI DVD/CDROM → EFI Network
- [x] ISH firmware extracted — `ishS_SI_5.8.0.7727.bin` (990.5 KB) and
      `ishS_MEU_aligned.bin` (514.5 KB), both `$CPD`/`ISHM` images from
      `FwImage/0003/` (0003 = Lunar Lake). Gitignored, not redistributable.
- [ ] Backup — **in progress 2026-08-30**
- [x] BIOS update — **none available.** Vantage reports no BIOS update; `Q9CN30WW`
      (2026-04-15) appears to be current. Lenovo's download pages return 403 to
      automated checks, so Vantage is the authority. The goal of this step was to
      avoid a firmware update landing *after* Phase 5 and wiping enrolled Secure
      Boot keys — already satisfied if no update exists.

#### Observed: the Secure Boot → VBS chain, both directions

Empirical confirmation of the README's central claim, from this machine:

| State | `UEFISecureBootEnabled` | `VirtualizationBasedSecurityStatus` | `SecurityServicesRunning` |
|---|---|---|---|
| Before live boot | 1 | 2 (running) | 2, 3, 4 |
| Secure Boot off (live USB) | 0 | — VBS cannot launch | — |
| Back in Windows, SB re-enabled | 1 | 2 (running) | 2, 3, 4 |

VBS returns on its own once Secure Boot is back, and with it ESS and Hello
biometrics. Nothing needs re-enrolling — this is not a destructive toggle.

**Sequencing note:** do the BIOS update *before* disabling Secure Boot for the
install. Firmware updates re-enable it, so doing it the other way round means
turning it off twice.

#### After the BIOS update, re-verify before booting the installer

Firmware updates routinely reset settings to defaults. Check all three:

1. **Secure Boot is OFF again.** Updates commonly re-enable it, and the installer
   will not boot with it on.
2. **`Reset to Setup Mode` still present** under Security → Secure Boot. The whole
   keep-Windows-Hello plan depends on it.
3. **Firmware boot order** against the baseline above — updates can reorder it.

### Shrink — **DONE 2026-08-29 22:43**

| | Before | After |
|---|---|---|
| C: | 951.65 GB | **701.65 GB** |
| Unallocated | none | **250.00 GB** @ 701.92–951.92 GB |
| Recovery | 951.92–953.87 GB | untouched |

C: healthy, 467.97 GB free. Gap is contiguous and sits between C: and Recovery,
exactly as planned — no partition move was needed.

### Live USB test (before writing anything to disk)

Boot the Omarchy ISO and check. This is the cheap, zero-risk verification pass —
everything here is a research prediction until ticked.

**Run 1 — 2026-08-29 22:24 UTC. PASS 11 · WARN 5 · FAIL 0. Valid run.**
Kernel `7.1.8-arch1-Watanare-T2-2-t2`.

> **Correction.** This was first read as the wrong ISO. It is not. There is one
> Omarchy ISO and it boots the **linux-t2** kernel so a single image works on both
> T2 Macs and ordinary PCs — `configs/airootfs/etc/mkinitcpio.d/linux-t2.preset`
> in `omacom-io/omarchy-iso`. The **installed** system gets stock `linux` from
> `builder/archinstall.packages`. Seeing `-t2` live is correct.
>
> The live kernel being 7.1.8 (below the 7.2 Arc freeze fix) therefore says nothing
> about the installed system. Recheck `uname -r` after install.

| Test | Predicted | Actual (run 1) | Notes |
|---|---|---|---|
| Installer sees the NVMe disk | yes (no VMD) | **PASS** | all 4 Windows partitions visible, NTFS intact |
| Wi-Fi BE201 | yes | **PASS** | `iwlwifi` loaded, firmware clean, `wlan0` up. Not associated, so no internet test |
| Bluetooth adapter | likely | **inconclusive** | `btintel_pcie` present in `Modules linked in:` but no adapter registered. Checker bug — now distinguishes driver-loaded from adapter-registered |
| GPU | yes on ≥7.2 | **PASS (driver)** | `xe` bound to `8086:64a0`, DMC firmware v2.29 loaded. Kernel is 7.1.8 — **below the 7.2 freeze fix**; no load test done |
| Speakers audible | no — UCM fix | **NOT TESTABLE** | `--- no soundcards ---`, but the ISO ships `/etc/modprobe.d/blacklist-panther-lake-audio.conf` blacklisting `snd_sof_pci_intel_lnl`, `soundwire_intel` and `snd_soc_cs35l56*`. Live-filesystem only; installed system gets `sof-firmware` + `pipewire` unblacklisted. **Audio verdict deferred to post-install** |
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

- Shrink amount actually achieved: 250.00 GB, as planned.
- Resulting layout (`lsblk`, verified 2026-08-30 post-install):

  | Part | PARTLABEL | Size | Contents |
  |---|---|---|---|
  | `nvme0n1p1` | EFI system partition | 260M | Windows ESP, `SYSTEM_DRV` — **untouched** |
  | `nvme0n1p2` | Microsoft reserved partition | 16M | untouched |
  | `nvme0n1p3` | Basic data partition | 701.6G | `Windows-SSD` NTFS — untouched |
  | `nvme0n1p4` | Basic data partition | 2G | `WINRE_DRV` — untouched |
  | `nvme0n1p5` | OMARCHY_EFI | 2G | new, FAT32, mounted at `/boot` |
  | `nvme0n1p6` | OMARCHY_ROOT | 248G | new, LUKS2 → btrfs `OMARCHY` |

  Windows' ESP was left alone and Omarchy built its own. That matters — see
  Bootloader below.

### Install

- Path taken: _(not recorded — fill in.)_ Whatever it was, it landed the new
  partitions in the 250 GB gap without touching the Windows ones.
- Did Omarchy accept a separate 2 GB boot partition? **Yes** — `nvme0n1p5`
  (`OMARCHY_EFI`, 2 GB, FAT32) is mounted at `/boot` and holds the UKI at
  `/boot/EFI/Linux/omarchy_linux.efi`. Assumption 2 resolved.
- Errors hit: none at install time. The problem surfaced at first boot — see below.

### Bootloader — **Windows entry missing on first boot; fixed 2026-08-30**

- [x] ~~`limine-scan` detected Windows~~ — **NO. Assumption 3 confirmed as a real
      failure on this machine.** After install, the Limine menu offered Omarchy only.
- [ ] Both entries boot — **not yet confirmed.** The entry is written and
      `limine-update` accepts it, but Windows has not actually been booted
      through Limine yet. Tick this only after it has.
- Fallback needed? **Yes, one config entry.**

#### What actually happened

Nothing was damaged. Every Windows component survived the install intact:

- `EFI/Microsoft/Boot/bootmgfw.efi` present on `nvme0n1p1`, dated 2026-08-23
- the firmware entry `Boot0002* Windows Boot Manager` still in `efibootmgr -v`,
  pointing at `HD(1,GPT,54ea1b94-7dee-4187-a8b2-a1d486fb5170)`
- `Windows-SSD` and `WINRE_DRV` mount clean

The cause is the separate-ESP layout from Partitioning above. `limine-entry-tool`
generates entries only for the ESP it lives on (`ESP_PATH="/boot"` =
`nvme0n1p5`). It never looks at `nvme0n1p1`, so `/boot/limine.conf` was written
with exactly one OS entry and no Windows.

So assumptions 2 and 3 interact: *because* Omarchy accepted its own boot
partition, Limine could not see Windows. Getting 2 right is what made 3 fail.

#### Fix — manual chainload entry

Appended to `/boot/limine.conf`:

```
/Windows
comment: Windows Boot Manager
protocol: efi
path: guid(54ea1b94-7dee-4187-a8b2-a1d486fb5170):/EFI/Microsoft/Boot/bootmgfw.efi
```

The GUID is `nvme0n1p1`'s GPT partition UUID. Limine's `guid()` resolver searches
filesystem and GPT partition GUIDs across the whole disk in one namespace
(`/usr/share/doc/limine/CONFIG.md`), so it reaches an ESP that is not its own.
`hdd(1:1):/...` would also work but breaks if disk enumeration changes.

Placement matters: the entry goes at the **end** of the file. `default_entry: 2`
is a positional index, and appending leaves Omarchy at position 2.

- Original saved to `/boot/limine.conf.prewindows`.
- Ran `limine-update` afterwards and re-grepped: the entry **survives config
  regeneration**, so kernel updates will not drop it. `limine-entry-tool` only
  rewrites the block tagged with its `machine-id` comment.
- **`omarchy refresh limine` WILL delete it** — that command does
  `mv /boot/limine.conf /boot/limine.conf.bak` then copies the stock default over
  it. If you ever run it, re-append the block above.
- Independent fallback, if the Limine entry is ever lost: F12 one-time boot menu,
  or `sudo efibootmgr -n 0002 && reboot`. The firmware entry is untouched by any
  of this.

#### Versions at time of fix (2026-08-30)

| Field | Value |
|---|---|
| BIOS version | `Q9CN30WW` (2026-04-16), Lenovo `83LC` |
| Omarchy | 4.0.1-1 |
| Kernel — running | `7.1.8-arch1-3` |
| Kernel — installed, pending reboot | `7.1.9-arch1-2` |
| Mesa | `1:26.2.1-1` |
| alsa-lib | `1.2.16.1-1` |

**Still below the 7.2 Arc freeze fix**, both running and pending. The live-USB
note said to recheck `uname -r` after install — done, and it does not clear the
bar. GPU-under-load remains untested and is still the open risk.

### Secure Boot re-enable

Observed state after install, before any key enrollment — both directions confirmed:

| Secure Boot | Limine | Windows | Windows Hello |
|---|---|---|---|
| **ON** | rejected (unsigned) | boots normally, direct via `Boot0002` | face + fingerprint work |
| **OFF** | boots, both entries offered | boots | **face + fingerprint disabled**, PIN only |

That is exactly the trade the custom-key plan exists to dissolve. Procedure lives in
`enroll-secureboot.sh` — run it once normally, once after Setup Mode.

- [x] BIOS supports clearing keys on this Lenovo BIOS — *Reset to Setup Mode*, verified 2026-08-29
- [x] Identified the CA that signs `bootmgfw.efi` — **Windows UEFI CA 2023** (see assumption 6)
- [ ] Original `PK`/`KEK`/`db`/`dbx` backed up to `/var/lib/sbctl-backup`
- [ ] `sbctl status` showed Setup Mode enabled
- [ ] `sbctl enroll-keys -m -f db,KEK` succeeded
- [ ] `db` re-checked post-enrollment: still contains `Windows UEFI CA 2023`
- [ ] Limine **and the UKI** signed, `sbctl verify` clean
- [ ] Secure Boot re-enabled, Omarchy still boots
- [ ] Secure Boot re-enabled, Windows still boots
- [ ] **Windows Hello face + fingerprint working again**
- [ ] `VirtualizationBasedSecurityStatus = 2` confirmed in Windows

### The actual fix: "Enhanced Windows Biometric Security" in BIOS

Since custom keys cannot persist, the trade-off has to be dissolved from the Windows
side instead. **BIOS (F2) → Security → Enhanced Windows Biometric Security → Disabled.**

That option *is* Enhanced Sign-in Security. Its own help text says so:

> `[Enabled]` Enhanced sign-in security is enabled.
> `[Disabled]` Enhanced sign-in security is disabled.

With ESS off, Hello's face and fingerprint fall back to the pre-ESS path, which does
not use a VBS enclave and therefore does not need Secure Boot. So:

| | Secure Boot | Limine | Windows | Hello face/print |
|---|---|---|---|---|
| ESS on (factory) | must be **on** | rejected | boots | works |
| ESS on (factory) | **off** | works | works | **broken** |
| **ESS off** | **off** | works | works | **works** |

**What this costs, stated plainly.** This is a real security reduction, not a free win:

- Biometric templates and matching leave the VTL1 enclave and run in the normal kernel.
  This is how Windows Hello worked before ESS existed. The credential is still
  TPM-bound, but the isolation is gone.
- Running with Secure Boot off separately costs you **VBS, HVCI/memory integrity, and
  Credential Guard**. That loss is unrelated to ESS and is the price of booting Limine.

If either matters more than a single boot menu, the alternative is to leave everything
at factory and **toggle Secure Boot in BIOS per OS** — on for Windows, off for Omarchy.
Fully secure, and genuinely tedious.

- [ ] ESS disabled in BIOS
- [ ] Hello face + fingerprint re-enrolled and working with Secure Boot off
- [ ] Both OSes boot from the Limine menu

> Expect to **re-enroll face and fingerprint** after changing this. Windows generally
> invalidates existing biometric enrollments when the ESS state changes, since the
> templates were sealed to the enclave. The PIN is unaffected.

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
   **RESOLVED 2026-08-30 — NO. Enrollment works but does not persist. The custom-key
   plan is dead on this machine.**

   The BIOS does offer **"Reset to Setup Mode"**, `sbctl` does enter Setup Mode, and
   enrollment genuinely succeeds — `sbctl` reports *"Enrolled keys to the EFI
   variables!"* and signing works. **The keys are gone by the next boot.**

   What the earlier note got wrong: it observed there is no "Custom" Secure Boot Mode,
   only Standard, and concluded *"that is fine."* It is not. On this Insyde firmware
   **Standard Mode means re-provision the factory key set** — `PK`/`KEK`/`db` are
   restored from the `*Default` variables on boot. There is no window in which custom
   keys survive.

   Measured after a reboot, with Secure Boot still **off**, so this is not something
   the enable step did:

   | Variable | Size | Content |
   |---|---|---|
   | `PK` | 852 B | `Trust - Lenovo Certificate` — factory, **not ours** |
   | `db` | 7237 B | **byte-identical to `dbDefault`** |
   | `KEK` | 3066 B | identical to `KEKDefault` |

   `sbctl status` corroborated it at the time by reporting `Vendor Keys: … builtin-PK`.
   Read from the Windows side with `Get-SecureBootUEFI -Name PK|KEK|db`.

   The binaries themselves were signed correctly — both `limine_x64.efi` and
   `omarchy_linux.efi` carry `CN=Database Key` — so the failure is purely that the
   firmware discarded the key those signatures chain to.

   **This invalidated the project's original premise.** See "Enhanced Windows Biometric
   Security" below for what actually solves it.

1b. **The verification gate that missed it.** `enroll-secureboot.sh` originally checked
   only that *Microsoft's* CAs were in `db`. The factory `db` contains those, so a
   firmware that had thrown away our key still passed, and the script went on to sign
   two binaries against a key that no longer existed. It now also requires
   `CN=Database Key` to be present and refuses if `db` is byte-identical to `dbDefault`.
2. ~~**Omarchy tolerates a separate 2 GB ESP-flagged boot partition.**~~
   **RESOLVED 2026-08-30 — yes.** `nvme0n1p5` (`OMARCHY_EFI`, 2 GB) is mounted at
   `/boot` and boots. The installer had no trouble with it.
3. ~~**Limine detects Windows on a separate ESP.**~~
   **RESOLVED 2026-08-30 — it does NOT.** Confirmed failure on this machine, not
   an intermittent one: `limine-entry-tool` scans only its own `ESP_PATH`, so a
   Windows ESP on another partition is structurally invisible to it. Fixed with a
   manual `guid()` chainload entry — see the Bootloader section. Note this is a
   direct consequence of 2 succeeding.
4. **Bluetooth `btintel_pcie` works on this exact adapter.** Run 1 was inconclusive:
   driver present, no adapter registered. Recheck on the correct ISO.
5. ~~**BitLocker is off.**~~ **RESOLVED 2026-08-29** — confirmed elevated:
   `Protection: OFF, Fully decrypted`.
6. ~~**`sbctl enroll-keys -m` enrolls a Microsoft cert that can actually validate THIS
   Windows Boot Manager.**~~ **RESOLVED 2026-08-30 — the risk is REAL. `-m` alone is
   not enough on this machine.**

   Run 1's dmesg showed the firmware db carries **two** Microsoft certs:

   ```
   integrity: Loaded X.509 cert 'Microsoft Windows Production PCA 2011: a929023...'
   integrity: Loaded X.509 cert 'Microsoft Corporation: Windows UEFI CA 2023: aefc5fb...'
   ```

   Measured from Windows which one actually matters, elevated, ESP mounted at `S:`:

   ```powershell
   mountvol S: /s
   Get-AuthenticodeSignature S:\EFI\Microsoft\Boot\bootmgfw.efi
   ```

   | Field | Value |
   |---|---|
   | Status | `Valid` |
   | Signer | `CN=Microsoft Windows, O=Microsoft Corporation, …` |
   | **Issuer** | **`CN=Windows UEFI CA 2023, O=Microsoft Corporation, C=US`** |
   | Root | `CN=Microsoft Root Certificate Authority 2010` |

   So this Boot Manager chains to the **2023 CA**, not the 2011 PCA. Enrolling a
   2011-only Microsoft bundle and turning Secure Boot on would leave **Windows
   refusing to boot**.

   **Mitigation, implemented in `enroll-secureboot.sh`:** enroll the firmware's own
   built-in databases alongside sbctl's keys —

   ```bash
   sbctl enroll-keys -m -f db,KEK
   ```

   `-f db,KEK` copies `dbDefault`/`KEKDefault`, which carry both Microsoft CAs.
   Keeping Microsoft's **KEK** matters for a second reason: without it Windows can
   no longer deliver signed `dbx` revocation updates.

   The script proves the 2023 CA is present *before* enrolling and re-checks `db`
   *after*, refusing to continue if it is missing. It also backs up `PK`/`KEK`/`db`/
   `dbx` to `/var/lib/sbctl-backup` first. Rollback remains *Restore Factory Keys*
   in BIOS, or simply disabling Secure Boot.

7. **Signing Limine is not sufficient — the UKI needs signing too.** Omarchy boots
   `/boot/EFI/Linux/omarchy_linux.efi` and Limine loads it with `protocol: efi`,
   which is a firmware `LoadImage()` call and therefore subject to Secure Boot
   validation. Signing only the bootloader yields a Limine menu that then refuses
   to start Linux. `enroll-secureboot.sh` signs every `.efi` under `/boot/EFI`
   except `EFI/Microsoft/`, using `sbctl sign -s` so the pacman hook re-signs after
   kernel and Limine upgrades.
