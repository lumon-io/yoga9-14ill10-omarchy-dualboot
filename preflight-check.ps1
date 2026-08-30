<#
.SYNOPSIS
    Elevated pre-flight checks before shrinking Windows for a Linux dual boot.

.DESCRIPTION
    MUST run as Administrator. Read-only: reports state, changes nothing.

    Checks the three things that block a dual-boot install:
      1. BitLocker  - the installer refuses to touch an encrypted drive
      2. Shrink headroom - unmovable files routinely cap this far below free space
      3. Fast Startup - leaves NTFS hibernated, which Linux must not write to

    Writes preflight-report.txt next to this script.

.EXAMPLE
    # In an elevated PowerShell (Win+X -> Terminal (Admin)):
    cd $HOME\omarchy-dualboot
    .\preflight-check.ps1
#>

[CmdletBinding()]
param(
    # How much you intend to give Linux, in GB.
    [int]$WantGB = 250
)

$ErrorActionPreference = 'Continue'
$out = Join-Path $PSScriptRoot 'preflight-report.txt'
$lines = [System.Collections.Generic.List[string]]::new()
function W { param([string]$s = '') ; $lines.Add($s); Write-Host $s }

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$elevated = (New-Object Security.Principal.WindowsPrincipal $id).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

W "Pre-flight report - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
W ("=" * 60)
W ""

if (-not $elevated) {
    W "NOT ELEVATED. Re-run from an admin prompt:"
    W "  Win+X -> Terminal (Admin), then:"
    W "  cd `$HOME\omarchy-dualboot ; .\preflight-check.ps1"
    $lines | Set-Content -Path $out -Encoding utf8
    exit 1
}
W "Elevated: yes"
W ""

$blockers = 0

# ------------------------------------------------------------- 1. BitLocker --
W "[1] BitLocker"
W ("-" * 60)
try {
    $vols = Get-CimInstance -Namespace root\cimv2\security\MicrosoftVolumeEncryption `
                            -ClassName Win32_EncryptableVolume -ErrorAction Stop
    foreach ($v in $vols) {
        $prot = switch ($v.ProtectionStatus) { 0 {'OFF'} 1 {'ON'} 2 {'UNKNOWN'} default {"$($v.ProtectionStatus)"} }
        $conv = switch ($v.ConversionStatus) {
            0 {'Fully decrypted'} 1 {'Fully encrypted'} 2 {'Encryption in progress'}
            3 {'Decryption in progress'} 4 {'Encryption paused'} 5 {'Decryption paused'}
            default {"$($v.ConversionStatus)"} }
        W ("  {0,-4} Protection: {1,-8} Status: {2}" -f $v.DriveLetter, $prot, $conv)
        if ($v.DriveLetter -eq 'C:' -and $v.ProtectionStatus -ne 0) {
            W "  >> BLOCKER: BitLocker is ON for C:."
            W "     Settings > Privacy & Security > Device encryption > off, and WAIT"
            W "     for full decryption before continuing."
            $blockers++
        }
    }
    if (-not ($vols | Where-Object { $_.DriveLetter -eq 'C:' -and $_.ProtectionStatus -ne 0 })) {
        W "  OK - C: is not BitLocker-protected."
    }
} catch {
    W "  ERROR querying BitLocker: $($_.Exception.Message)"
    $blockers++
}
W ""

# ---------------------------------------------------------- 2. Shrink room ---
W "[2] Shrink headroom (want $WantGB GB for Linux)"
W ("-" * 60)
try {
    $part = Get-Partition -DriveLetter C -ErrorAction Stop
    $sz   = Get-PartitionSupportedSize -DriveLetter C -ErrorAction Stop
    $shrinkable = ($part.Size - $sz.SizeMin) / 1GB
    $vol  = Get-Volume -DriveLetter C
    W ("  Current size   : {0,10:N2} GB" -f ($part.Size / 1GB))
    W ("  Free space     : {0,10:N2} GB" -f ($vol.SizeRemaining / 1GB))
    W ("  Minimum size   : {0,10:N2} GB" -f ($sz.SizeMin / 1GB))
    W ("  Shrinkable by  : {0,10:N2} GB" -f $shrinkable)
    W ""
    if ($shrinkable -ge $WantGB) {
        W "  OK - $WantGB GB shrink is achievable."
    } else {
        W "  >> BLOCKER: can only shrink $([math]::Round($shrinkable,1)) GB, wanted $WantGB GB."
        W "     Unmovable files (pagefile, System Restore, shadow copies) are pinned"
        W "     near the end of the volume. To free them up:"
        W "       1. Disable the pagefile   (System Properties > Advanced > Performance)"
        W "       2. Disable System Protection (System Properties > System Protection)"
        W "       3. vssadmin delete shadows /all"
        W "       4. Reboot, re-run this script, shrink, then re-enable 1 and 2."
        $blockers++
    }
} catch {
    W "  ERROR querying partition: $($_.Exception.Message)"
    $blockers++
}
W ""

# --------------------------------------------------------- 3. Fast Startup ---
W "[3] Fast Startup / hibernation"
W ("-" * 60)
$hibernate = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' `
              -Name HibernateEnabled -ErrorAction SilentlyContinue).HibernateEnabled
$hiberboot = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' `
              -Name HiberbootEnabled -ErrorAction SilentlyContinue).HiberbootEnabled
$hiberfil  = Test-Path 'C:\hiberfil.sys'
W "  HibernateEnabled : $hibernate   (this is the one that matters)"
W "  HiberbootEnabled : $hiberboot   (preference flag only - ignore if 1)"
W "  hiberfil.sys     : $hiberfil"
if ($hibernate -eq 0 -or -not $hiberfil) {
    W "  OK - Fast Startup is inoperative. NTFS will shut down clean."
} else {
    W "  >> BLOCKER: run 'powercfg /h off', then SHUT DOWN FULLY (not restart)."
    $blockers++
}
W ""

# ------------------------------------------------------------- 4. Partitions -
W "[4] Current disk layout"
W ("-" * 60)
Get-Partition -DiskNumber 0 | ForEach-Object {
    W ("  #{0}  {1,-28} {2,10:N2} GB  @ {3,8:N2} GB  {4}" -f `
        $_.PartitionNumber, $_.Type, ($_.Size/1GB), ($_.Offset/1GB), $_.DriveLetter)
}
W ""

# ----------------------------------------------------------------- verdict ---
W ("=" * 60)
if ($blockers -eq 0) {
    W "VERDICT: CLEAR - no blockers. Safe to shrink C: by $WantGB GB."
    W ""
    W "Shrink via Disk Management (diskmgmt.msc) > C: > Shrink Volume,"
    W "or:  Resize-Partition -DriveLetter C -Size ((Get-Partition -DriveLetter C).Size - ${WantGB}GB)"
    W "Leave the resulting unallocated space alone - the Omarchy installer claims it."
} else {
    W "VERDICT: $blockers BLOCKER(S) - resolve the items marked '>>' above first."
}
W ("=" * 60)

$lines | Set-Content -Path $out -Encoding utf8
Write-Host ""
Write-Host "Report written to: $out"
