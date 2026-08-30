# Hardware report

Generated: 2026-08-29 22:07:04 -07:00
Elevated: **False**  <- rerun as admin for BitLocker + Secure Boot state

## System

| Field | Value |
|---|---|
| Manufacturer | LENOVO |
| Model | 83LC |
| Family | Yoga 9 2-in-1 14ILL10 |
| BIOS | Q9CN30WW (2026-04-15) |
| CPU | Intel(R) Core(TM) Ultra 7 258V |
| Cores / Threads | 8 / 8 |
| RAM | 31.5 GB |
| OS | Microsoft Windows 11 Pro Insider Preview |
| Build | 10.0.26300 (26300) |

## Firmware / Secure Boot

- UEFI Secure Boot enabled (registry): `1` (1 = on)
- `Confirm-SecureBootUEFI`: _requires admin_
- Firmware mode: `UEFI`

## VBS / Device Guard / Windows Hello ESS

> This is the section that decides whether turning Secure Boot off will break
> Windows Hello biometrics. See README for the full explanation.

- VirtualizationBasedSecurityStatus: `2` (0=off, 1=configured, 2=running)
- SecurityServicesRunning: `2, 3, 4`
  - 1=Credential Guard, 2=HVCI, 3=System Guard Secure Launch, 4=SMM Firmware Measurement
- RequiredSecurityProperties: `1, 2, 3`
  - 1=base virtualization, **2=Secure Boot**, 3=DMA protection

**VBS on this machine requires Secure Boot.** Disabling Secure Boot will stop VBS,
which stops Enhanced Sign-in Security, which disables Hello face + fingerprint.

- ESSCapableOnLastStart: `1`
- EnableESSPreviousValue: `1`
- FaceBioUnitConfigured: `1`
- SecureBioAvailabilityInCensus: `1`

## BitLocker

> Omarchy's free-space installer refuses to run against an encrypted drive.

- BootStatus (registry hint only): `0` (0 suggests not protected)
- Run elevated `manage-bde -status C:` to confirm.

## Storage

> Intel VMD / RST 'RAID mode' is the classic reason Linux installers see no disk.
> A `Standard NVM Express Controller` below means you are fine.

### Controllers

```
Microsoft Storage Spaces Controller
Standard NVM Express Controller
Xvdd SCSI Miniport
```

### Disks

```
Number FriendlyName                    BusType PartitionStyle SizeGB
------ ------------                    ------- -------------- ------
     0 WD PC SN7100S SDFPMSL-1T00-1101 NVMe    GPT            953.90
     1 USB SanDisk 3.2Gen1             USB     MBR             28.70
```

### Partitions

```
DiskNumber PartitionNumber DriveLetter Type     SizeGB OffsetGB
---------- --------------- ----------- ----     ------ --------
         0               1            System     0.25     0.00
         0               2            Reserved   0.02     0.25
         0               3           C Basic    951.65     0.27
         0               4            Recovery   1.95   951.92
         1               1            Unknown    0.02     5.82
```

### Free space

```
DriveLetter FileSystemLabel FileSystem SizeGB FreeGB
----------- --------------- ---------- ------ ------
          C Windows-SSD     NTFS       951.60 725.10
```

- **ESP size: 260 MB.** Under ~512 MB is too small for
  Limine + Unified Kernel Images + Snapper snapshot entries alongside Windows Boot Manager.

## Peripherals

### Network

```
Name    InterfaceDescription          Status
----    --------------------          ------
Wi-Fi 3 Intel(R) Wi-Fi 7 BE201 320MHz Not Present
Wi-Fi 2 Intel(R) Wi-Fi 7 BE201 320MHz Not Present
Wi-Fi   Intel(R) Wi-Fi 7 BE201 320MHz Up
```

### Audio (Lunar Lake SoundWire is the highest-risk subsystem on Linux)

> Paired Bluetooth audio endpoints are filtered out — they carry personal device
> names. Pass -IncludePaired to keep them (do not publish that output).

```
Microsoft Streaming Service Proxy
Cirrus Logic XU
Intel® Smart Sound Technology for Bluetooth® Audio
SoundWire ACX Streaming for SDW - Headset Earphone
CS42L43 AMP
SoundWire ACX Streaming for SDW - Speaker
Intel® Smart Sound Technology for Bluetooth® LE Audio
Intel® Smart Sound Technology for Digital Microphones
Intel ACX Streaming for SDW
CS42L43 UAJ
SoundWire ACX Streaming for SDW - Headset Microphone
SoundWire Audio
Intel® Smart Sound Technology for USB Audio
Cirrus Logic XU
Cirrus Logic XU
```

### Biometric

```
Status FriendlyName
------ ------------
OK     Goodix MOC Fingerprint
OK     Facial Recognition (Windows Hello) Software Device
```

### Cameras

```
Status FriendlyName
------ ------------
OK     Integrated Camera
OK     Integrated IR Camera
```

## PCI / hardware IDs

> Match these against your own machine to confirm you have the same silicon.

```
Class       FriendlyName                                                    InstanceId
-----       ------------                                                    ----------
Bluetooth   Intel(R) Bluetooth(R) PCI Enumerator                            PCI\VEN_8086&DEV_A876&SUBSYS_000E8086&REV_10
                                                                            \3&11583659&1&A7
Display     Intel(R) Arc(TM) 140V GPU (16GB)                                PCI\VEN_8086&DEV_64A0&SUBSYS_3DA217AA&REV_04
                                                                            \3&11583659&1&10
Net         Intel(R) Wi-Fi 7 BE201 320MHz                                   PCI\VEN_8086&DEV_A840&SUBSYS_00E48086&REV_10
                                                                            \3&11583659&1&A3
SCSIAdapter Standard NVM Express Controller                                 PCI\VEN_15B7&DEV_5044&SUBSYS_504415B7&REV_01
                                                                            \4&147A36D8&0&00E0
System      PCI standard RAM Controller                                     PCI\VEN_8086&DEV_A87F&SUBSYS_381617AA&REV_10
                                                                            \3&11583659&1&A2
System      Intel(R) SPI (flash) Controller - A823                          PCI\VEN_8086&DEV_A823&SUBSYS_383317AA&REV_10
                                                                            \3&11583659&1&FD
System      PCI Express Root Port                                           PCI\VEN_8086&DEV_A84E&SUBSYS_380617AA&REV_10
                                                                            \3&11583659&1&38
System      Intel(R) Serial IO I2C Host Controller - A850                   PCI\VEN_8086&DEV_A850&SUBSYS_382417AA&REV_10
                                                                            \3&11583659&1&C8
System      Intel(R) Serial IO I2C Host Controller - A878                   PCI\VEN_8086&DEV_A878&SUBSYS_381917AA&REV_10
                                                                            \3&11583659&1&A8
System      PCI Express Root Port                                           PCI\VEN_8086&DEV_A838&SUBSYS_382617AA&REV_10
                                                                            \3&11583659&1&E0
System      Intel(R) Integrated Sensor Solution                             PCI\VEN_8086&DEV_A845&SUBSYS_380F17AA&REV_10
                                                                            \3&11583659&1&90
System      PCI Express Root Port                                           PCI\VEN_8086&DEV_A84F&SUBSYS_380417AA&REV_10
                                                                            \3&11583659&1&39
System      PCI standard ISA bridge                                         PCI\VEN_8086&DEV_A807&SUBSYS_382F17AA&REV_10
                                                                            \3&11583659&1&F8
System      PCI standard host CPU bridge                                    PCI\VEN_8086&DEV_6400&SUBSYS_380317AA&REV_04
                                                                            \3&11583659&1&00
System      Intel(R) Serial IO I2C Host Controller - A879                   PCI\VEN_8086&DEV_A879&SUBSYS_381A17AA&REV_10
                                                                            \3&11583659&1&A9
System      Intel(R) Management Engine Interface #1                         PCI\VEN_8086&DEV_A870&SUBSYS_381D17AA&REV_10
                                                                            \3&11583659&1&B0
System      Intel(R) Serial IO I2C Host Controller - A87A                   PCI\VEN_8086&DEV_A87A&SUBSYS_381B17AA&REV_10
                                                                            \3&11583659&1&AA
System      Intel(R) Serial IO I2C Host Controller - A851                   PCI\VEN_8086&DEV_A851&SUBSYS_382517AA&REV_10
                                                                            \3&11583659&1&C9
System      Intel(R) Innovation Platform Framework Processor Participant    PCI\VEN_8086&DEV_641D&SUBSYS_380117AA&REV_04
                                                                            \3&11583659&1&20
System      Intel® Smart Sound Technology BUS                               PCI\VEN_8086&DEV_A828&SUBSYS_383217AA&REV_10
                                                                            \3&11583659&1&FB
System      Intel(R) Platform Monitoring Technology (PMT) Driver            PCI\VEN_8086&DEV_647D&SUBSYS_72708086&REV_04
                                                                            \3&11583659&1&50
System      Intel(R) SMBus - A822                                           PCI\VEN_8086&DEV_A822&SUBSYS_72708086&REV_10
                                                                            \3&11583659&1&FC
System      PCI Express Root Port                                           PCI\VEN_8086&DEV_A860&SUBSYS_380517AA&REV_10
                                                                            \3&11583659&1&3A
USB         USB4(TM) Host Router (Microsoft)                                PCI\VEN_8086&DEV_A833&SUBSYS_72708086&REV_10
                                                                            &USB4_MS_CM\3&11583659&1&6A
USB         USB4(TM) Host Router (Microsoft)                                PCI\VEN_8086&DEV_A834&SUBSYS_72708086&REV_10
                                                                            &USB4_MS_CM\3&11583659&1&6B
USB         Intel(R) USB 3.20 eXtensible Host Controller - 1.20 (Microsoft) PCI\VEN_8086&DEV_A87D&SUBSYS_381517AA&REV_10
                                                                            \3&11583659&1&A0
USB         Intel(R) USB 3.20 eXtensible Host Controller - 1.20 (Microsoft) PCI\VEN_8086&DEV_A831&SUBSYS_380817AA&REV_10
                                                                            \3&11583659&1&68
```

## Pre-flight blockers

- Fast Startup: **off / inoperative** (good) — `HibernateEnabled=0`, hiberfil.sys present: False
  - `HiberbootEnabled` is still `1`, but that is only a preference flag. Fast
    Startup cannot run without hibernation, so this is fine. Do not chase it.
- Verify independently with `powercfg /a`: both *Hibernate* and *Fast Startup* should be listed as unavailable.
- Secure Boot is ON. The Linux installer needs it OFF; re-enable afterwards with custom keys to keep Hello working.

---

_Generated by `collect-hardware.ps1`. Read-only; no changes were made._
