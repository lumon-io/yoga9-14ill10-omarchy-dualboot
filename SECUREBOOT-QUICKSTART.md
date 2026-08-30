# Secure Boot quickstart — copy/paste from Omarchy

## The two commands

Once the repo is cloned, these are the only things you ever need to type. Both
update the repo first, so a fix made from the Windows side lands automatically.

```bash
sudo ~/dualboot/sb
```

Reports where Secure Boot stands and names the single next command. Changes nothing.

```bash
sudo ~/dualboot/sb go
```

Does the next step: enrolls keys if the firmware is in Setup Mode, then verifies
`db` and signs Limine and the UKI. Safe to re-run — it works out its own stage.

Everything below is the long form, for reference or if `sb` is unavailable.

---

Everything you need to re-enable Secure Boot with custom keys, so **Limine boots and
Windows Hello keeps working**. Written to be pasted straight into a terminal.

**Start here, booted into Omarchy, Secure Boot still off.**

---

## 0. Get this repo onto the machine

The only line you have to type from memory:

```bash
git clone https://github.com/lumon-io/yoga9-14ill10-omarchy-dualboot ~/dualboot && cd ~/dualboot
```

Already cloned? Update instead:

```bash
cd ~/dualboot && git pull
```

### No network? Read it off the Windows partition

Everything in this repo also lives on the Windows side at
`C:\Users\jerem\omarchy-dualboot`. Mount it read-only:

```bash
sudo mkdir -p /mnt/win
sudo mount -o ro /dev/nvme0n1p3 /mnt/win
ls /mnt/win/Users/jerem/omarchy-dualboot
```

Read-only is deliberate — never mount that partition `rw` unless Windows shut down
cleanly. Copy the script out and run it from `~`:

```bash
cp /mnt/win/Users/jerem/omarchy-dualboot/enroll-secureboot.sh ~/
sudo umount /mnt/win
```

---

## 1. Pass 1 — backup and pre-flight

Changes nothing. Backs up your firmware keys, then checks the one thing that can
brick the Windows boot.

```bash
sudo bash enroll-secureboot.sh
```

Expect it to end with **"Next step: put the firmware in Setup Mode"**.

It must print this line before it will let you continue:

```
OK - 'Windows UEFI CA 2023' is present in dbDefault and will be enrolled.
```

If it does **not**, stop — your `bootmgfw.efi` is signed by that CA, and enrolling
without it makes Windows unbootable. See assumption 6 in `INSTALL-LOG.md`.

---

## 2. Reboot into BIOS and clear the platform key

1. Reboot, press **F2**
2. **Security → Secure Boot**
3. **"Reset to Setup Mode"** → Enter
4. **F10** to save, boot back into Omarchy

> **Do NOT touch "Clear Intel PTT Key"** on that same screen. It wipes the TPM and
> takes your Windows Hello PIN — and any BitLocker recovery binding — with it.
>
> **"Restore Factory Keys"**, also on that screen, is your undo button for everything
> in this document.

---

## 3. Pass 2 — enroll and sign

Same command. The script detects Setup Mode and takes the other branch.

```bash
cd ~/dualboot && sudo bash enroll-secureboot.sh
```

It will ask `Proceed? [y/N]`. It then:

- creates keys, and enrolls with `sbctl enroll-keys -m -f db,KEK`
- **re-reads `db` and aborts if `Windows UEFI CA 2023` did not land**
- signs every `.efi` under `/boot/EFI` except `EFI/Microsoft/`, using `sbctl sign -s`
  so the pacman hook re-signs them after kernel and Limine upgrades
- runs `sbctl verify`

`sbctl verify` should list your Limine binary **and** `/boot/EFI/Linux/omarchy_linux.efi`
as signed. The UKI matters as much as the bootloader — Limine loads it with
`protocol: efi`, which is a firmware `LoadImage()` call, so Secure Boot checks it too.
Signing only Limine gives you a boot menu that then refuses to start Linux.

---

## 4. Turn Secure Boot back on

1. Reboot, **F2** → **Security → Secure Boot → Enabled**, **F10**
2. **Boot Omarchy first.** It is the cheaper failure to discover, and if the UKI was
   missed you just turn Secure Boot back off and re-run step 3.
3. Reboot and boot the **Windows** entry.

Check from Omarchy that it really is enforcing:

```bash
sudo sbctl status
```

Want `Secure Boot: ✓ Enabled` and `Setup Mode: ✗ Disabled`.

---

## 5. Confirm Windows Hello came back

In Windows, **elevated** PowerShell:

```powershell
Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard |
    Select-Object VirtualizationBasedSecurityStatus, SecurityServicesRunning
```

- `VirtualizationBasedSecurityStatus` = **2** (running)
- `SecurityServicesRunning` containing **2** (HVCI) and **3** (System Guard Secure Launch)

Then check the lock screen actually offers face and fingerprint again.

---

## If something goes wrong

Nothing here is one-way. In rough order of how much you undo:

| Symptom | Fix |
|---|---|
| Windows entry missing from Limine | **F12** → *Windows Boot Manager*, or `sudo efibootmgr -n 0002 && reboot` |
| Linux refuses to boot with Secure Boot on | BIOS → Secure Boot → **Disabled**. Re-run step 3. |
| **Windows** refuses to boot with Secure Boot on | BIOS → Secure Boot → **Disabled**, then → **Restore Factory Keys** |
| Want the whole thing gone | BIOS → **Restore Factory Keys**, then `sudo sbctl reset` |

Your original firmware keys are dumped to `/var/lib/sbctl-backup` by pass 1.
The firmware's `Boot0002` Windows entry is never modified by any of this.

---

## Re-adding the Windows entry to Limine

`omarchy refresh limine` overwrites `/boot/limine.conf` and **deletes** the Windows
chainload entry. Ordinary `limine-update` runs do not. If you lose it, append this to
the **end** of `/boot/limine.conf` — the end matters, because `default_entry` is a
positional index:

```
/Windows
comment: Windows Boot Manager
protocol: efi
path: guid(54ea1b94-7dee-4187-a8b2-a1d486fb5170):/EFI/Microsoft/Boot/bootmgfw.efi
```

That GUID is `nvme0n1p1`'s GPT partition UUID on this machine. Confirm yours with:

```bash
lsblk -o NAME,PARTLABEL,PARTUUID /dev/nvme0n1
```

A saved copy of the pre-Windows config is at `/boot/limine.conf.prewindows`.

---

## Doing it by hand

If you would rather not run the script, this is all it does that matters:

```bash
# pass 1 - check the CA your Windows loader actually needs
sudo grep -qa 'Windows UEFI CA 2023' \
  /sys/firmware/efi/efivars/dbDefault-8be4df61-93ca-11d2-aa0d-00e098032b8c && echo PRESENT

# ... BIOS: Reset to Setup Mode ...

sudo sbctl status                 # want: Setup Mode: Enabled
sudo sbctl create-keys
sudo sbctl enroll-keys -m -f db,KEK

# confirm it landed, BEFORE enabling Secure Boot.
# NOTE the different GUID: db and dbx live under EFI_IMAGE_SECURITY_DATABASE
# (d719b2cb-...), while PK, KEK, SetupMode, SecureBoot and every *Default
# variable live under EFI_GLOBAL_VARIABLE (8be4df61-...). Grepping db under the
# global GUID just reports "No such file or directory".
sudo grep -qa 'Windows UEFI CA 2023' \
  /sys/firmware/efi/efivars/db-d719b2cb-3d3a-4596-a3bc-dad00e67656f && echo SAFE

# sign the bootloader AND the UKI; -s registers them for the pacman hook
sudo sbctl sign -s /boot/EFI/BOOT/BOOTX64.EFI
sudo sbctl sign -s /boot/EFI/Linux/omarchy_linux.efi
sudo sbctl verify
```

Find the real filenames first if those paths differ:

```bash
find /boot/EFI -iname '*.efi' -not -path '*/Microsoft/*'
```
