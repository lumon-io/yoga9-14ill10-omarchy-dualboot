<#
.SYNOPSIS
    Collects the Windows-side facts that matter before dual-booting Linux on a
    Lenovo Yoga 9 2-in-1 14ILL10 (or any modern Windows laptop).

.DESCRIPTION
    Read-only. Makes no changes. Emits Markdown to stdout so you can paste the
    result straight into a bug report, forum post, or PR.

    Run elevated for complete output. Unelevated still works, but BitLocker and
    Secure Boot state will come back as "requires admin".

.EXAMPLE
    .\collect-hardware.ps1 | Tee-Object -FilePath hardware-report.md
#>

[CmdletBinding()]
param(
    # Keep paired Bluetooth audio endpoints in the output. These carry personal
    # device names ("Jane's Pixel"), so they are filtered out by default. Do not
    # publish output generated with this switch.
    [switch]$IncludePaired
)

$ErrorActionPreference = 'Continue'

function Test-Elevated {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-Safe {
    param([scriptblock]$Block, [string]$Fallback = '_unavailable_')
    try {
        $v = & $Block
        if ($null -eq $v -or "$v" -eq '') { return $Fallback }
        # Some PnP device strings carry embedded NUL / control bytes. Left in, they
        # make git classify the report as binary, so it never renders as Markdown.
        if ($v -is [string]) { return ($v -replace '[\x00-\x08\x0B\x0C\x0E-\x1F]', '') }
        return $v
    } catch {
        return "_error: $($_.Exception.Message)_"
    }
}

$elevated = Test-Elevated

"# Hardware report"
""
"Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')"
"Elevated: **$elevated**" + $(if (-not $elevated) { "  <- rerun as admin for BitLocker + Secure Boot state" } else { "" })
""

# ---------------------------------------------------------------- system ----
"## System"
""
$cs  = Get-Safe { Get-CimInstance Win32_ComputerSystem }
$bios= Get-Safe { Get-CimInstance Win32_BIOS }
$os  = Get-Safe { Get-CimInstance Win32_OperatingSystem }
$cpu = Get-Safe { Get-CimInstance Win32_Processor }

"| Field | Value |"
"|---|---|"
"| Manufacturer | $($cs.Manufacturer) |"
"| Model | $($cs.Model) |"
"| Family | $($cs.SystemFamily) |"
"| BIOS | $($bios.SMBIOSBIOSVersion) ($(Get-Safe { ([datetime]$bios.ReleaseDate).ToString('yyyy-MM-dd') })) |"
"| CPU | $($cpu.Name) |"
"| Cores / Threads | $($cpu.NumberOfCores) / $($cpu.NumberOfLogicalProcessors) |"
"| RAM | $([math]::Round($cs.TotalPhysicalMemory/1GB,1)) GB |"
"| OS | $($os.Caption) |"
"| Build | $($os.Version) ($($os.BuildNumber)) |"
""

# ------------------------------------------------------------ firmware/SB ----
"## Firmware / Secure Boot"
""
$sbReg = Get-Safe { (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State' -EA Stop).UEFISecureBootEnabled }
"- UEFI Secure Boot enabled (registry): ``$sbReg`` (1 = on)"
if ($elevated) {
    "- ``Confirm-SecureBootUEFI``: $(Get-Safe { Confirm-SecureBootUEFI })"
} else {
    "- ``Confirm-SecureBootUEFI``: _requires admin_"
}
$fw = Get-Safe {
    # PEFirmwareType is only present in WinPE. On a full install, infer from the
    # presence of a SecureBoot state key plus a GPT disk carrying an ESP.
    $hasSbKey = Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State'
    $hasEsp   = [bool](Get-Partition -EA SilentlyContinue | Where-Object Type -eq 'System')
    if ($hasSbKey -and $hasEsp) { 'UEFI' } elseif ($hasEsp) { 'UEFI (no SecureBoot key)' } else { 'Legacy/BIOS' }
}
"- Firmware mode: ``$fw``"
""

# ------------------------------------------------------------------ VBS -----
"## VBS / Device Guard / Windows Hello ESS"
""
"> This is the section that decides whether turning Secure Boot off will break"
"> Windows Hello biometrics. See README for the full explanation."
""
$dg = Get-Safe { Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard -EA Stop }
if ($dg -isnot [string]) {
    "- VirtualizationBasedSecurityStatus: ``$($dg.VirtualizationBasedSecurityStatus)`` (0=off, 1=configured, 2=running)"
    "- SecurityServicesRunning: ``$($dg.SecurityServicesRunning -join ', ')``"
    "  - 1=Credential Guard, 2=HVCI, 3=System Guard Secure Launch, 4=SMM Firmware Measurement"
    "- RequiredSecurityProperties: ``$($dg.RequiredSecurityProperties -join ', ')``"
    "  - 1=base virtualization, **2=Secure Boot**, 3=DMA protection"
    if ($dg.RequiredSecurityProperties -contains 2) {
        ""
        "**VBS on this machine requires Secure Boot.** Disabling Secure Boot will stop VBS,"
        "which stops Enhanced Sign-in Security, which disables Hello face + fingerprint."
    }
} else {
    "- Device Guard query: $dg"
}
""
$winbio = Get-Safe { Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WinBio' -EA Stop }
if ($winbio -isnot [string]) {
    "- ESSCapableOnLastStart: ``$($winbio.ESSCapableOnLastStart)``"
    "- EnableESSPreviousValue: ``$($winbio.EnableESSPreviousValue)``"
    "- FaceBioUnitConfigured: ``$($winbio.FaceBioUnitConfigured)``"
    "- SecureBioAvailabilityInCensus: ``$($winbio.SecureBioAvailabilityInCensus)``"
}
""

# ------------------------------------------------------------- bitlocker ----
"## BitLocker"
""
"> Omarchy's free-space installer refuses to run against an encrypted drive."
""
if ($elevated) {
    "``````"
    (Get-Safe { manage-bde -status C: 2>&1 | Out-String }).Trim()
    "``````"
} else {
    $bl = Get-Safe { (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\BitlockerStatus' -EA Stop).BootStatus }
    "- BootStatus (registry hint only): ``$bl`` (0 suggests not protected)"
    "- Run elevated ``manage-bde -status C:`` to confirm."
}
""

# ------------------------------------------------------------------ disk ----
"## Storage"
""
"> Intel VMD / RST 'RAID mode' is the classic reason Linux installers see no disk."
"> A ``Standard NVM Express Controller`` below means you are fine."
""
"### Controllers"
""
"``````"
(Get-Safe { Get-PnpDevice -Class SCSIAdapter,HDC -EA SilentlyContinue |
    Where-Object Status -eq 'OK' |
    Select-Object -ExpandProperty FriendlyName | Out-String }).Trim()
"``````"
""
"### Disks"
""
"``````"
(Get-Safe { Get-Disk | Select-Object Number, FriendlyName, BusType, PartitionStyle,
    @{n='SizeGB';e={[math]::Round($_.Size/1GB,1)}} | Format-Table -AutoSize | Out-String }).Trim()
"``````"
""
"### Partitions"
""
"``````"
(Get-Safe { Get-Partition | Select-Object DiskNumber, PartitionNumber, DriveLetter, Type,
    @{n='SizeGB';e={[math]::Round($_.Size/1GB,2)}},
    @{n='OffsetGB';e={[math]::Round($_.Offset/1GB,2)}} | Format-Table -AutoSize | Out-String }).Trim()
"``````"
""
"### Free space"
""
"``````"
(Get-Safe { Get-Volume | Where-Object DriveLetter |
    Select-Object DriveLetter, FileSystemLabel, FileSystem,
    @{n='SizeGB';e={[math]::Round($_.Size/1GB,1)}},
    @{n='FreeGB';e={[math]::Round($_.SizeRemaining/1GB,1)}} | Format-Table -AutoSize | Out-String }).Trim()
"``````"
""
$esp = Get-Partition | Where-Object { $_.Type -eq 'System' } | Select-Object -First 1
if ($esp) {
    "- **ESP size: $([math]::Round($esp.Size/1MB,0)) MB.** Under ~512 MB is too small for"
    "  Limine + Unified Kernel Images + Snapper snapshot entries alongside Windows Boot Manager."
}
""

# --------------------------------------------------------------- peripherals -
"## Peripherals"
""
"### Network"
""
"``````"
(Get-Safe { Get-NetAdapter -Physical -EA SilentlyContinue |
    Select-Object Name, InterfaceDescription, Status | Format-Table -AutoSize | Out-String }).Trim()
"``````"
""
"### Audio (Lunar Lake SoundWire is the highest-risk subsystem on Linux)"
""
"> Paired Bluetooth audio endpoints are filtered out — they carry personal device"
"> names. Pass -IncludePaired to keep them (do not publish that output)."
""
"``````"
(Get-Safe { Get-PnpDevice -Class MEDIA -EA SilentlyContinue |
    Where-Object Status -eq 'OK' |
    Select-Object -ExpandProperty FriendlyName |
    Where-Object { $IncludePaired -or $_ -notmatch 'A2DP|AVRCP|Hands-Free|Headset .*(SNK|Source)|\bSNK\b' } |
    Out-String }).Trim()
"``````"
""
"### Biometric"
""
"``````"
(Get-Safe { Get-PnpDevice -Class Biometric -EA SilentlyContinue |
    Select-Object Status, FriendlyName | Format-Table -AutoSize | Out-String }).Trim()
"``````"
""
"### Cameras"
""
"``````"
(Get-Safe { Get-PnpDevice -Class Camera,Image -EA SilentlyContinue |
    Select-Object Status, FriendlyName | Format-Table -AutoSize | Out-String }).Trim()
"``````"
""

# ------------------------------------------------------------- hardware IDs -
"## PCI / hardware IDs"
""
"> Match these against your own machine to confirm you have the same silicon."
""
"``````"
(Get-Safe { Get-PnpDevice -PresentOnly -EA SilentlyContinue |
    Where-Object { $_.InstanceId -like 'PCI\*' -and $_.Status -eq 'OK' } |
    Where-Object { $_.Class -in @('Display','Net','MEDIA','SCSIAdapter','System','Bluetooth','USB') } |
    Select-Object Class, FriendlyName, InstanceId |
    Sort-Object Class |
    Format-Table -AutoSize -Wrap | Out-String }).Trim()
"``````"
""

# ------------------------------------------------------------- pre-flight ---
"## Pre-flight blockers"
""
$hiber = Get-Safe { (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled -EA Stop).HiberbootEnabled }
$hiberMsg = if ($hiber -eq 1) { "**ON — must disable with ``powercfg /h off``**" } else { "off (good)" }
"- Fast Startup / hiberboot: $hiberMsg"
if ($sbReg -eq 1) {
    "- Secure Boot is ON. The Linux installer needs it OFF; re-enable afterwards with custom keys to keep Hello working."
}
""
"---"
""
"_Generated by ``collect-hardware.ps1``. Read-only; no changes were made._"
