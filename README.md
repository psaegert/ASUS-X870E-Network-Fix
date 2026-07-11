# ASUS X870E Network Fix

Fix for the onboard Intel I225/I226 (`igc`) NIC falling off the PCIe bus on an ASUS X870E board (Ubuntu Server 24.04):

```
kernel: igc 0000:0b:00.0 eno1: PCIe link lost, device now detached
```

The OS keeps running, but the network is gone until a **full power-off** — a warm reboot is not always enough, and Wake-on-LAN cannot help because the NIC is the thing that died. The failure strikes an *idle* link (in the documented incident, hours after the last real traffic, with only ~0.65 kB/s of LAN background chatter), which points at ASPM L1: the link naps after microseconds of idle and one day never wakes up.

## TL;DR

No single kernel parameter fixed this permanently (see [History](#history)). What holds is defense in depth:

1. Let the kernel **own** ASPM (no `pcie_aspm=off` — counter-intuitive, see trap 1) and set the valid policy form `pcie_aspm.policy=performance`.
2. A systemd service (at boot + every 10 min) that writes the per-device sysfs knobs (`link/l1_aspm = 0` etc.) and **verifies by reading the register back**, logging the truth.
3. A watchdog that greps the current boot's kernel log for the literal `PCIe link lost` and then self-power-cycles via `rtcwake -m off -s 180` — a true cold boot with no human hands, at most once per boot.

```sh
sudo ./fix/install.sh   # then reboot once
```

Verify any time:

```sh
journalctl -t disable-nic-aspm -n 1   # must say: OK: ASPM disabled on <device>
```

## Four traps

Everything below was verified on the live machine; each trap cost real debugging time.

### 1. `pcie_aspm=off` does not turn ASPM off

With `pcie_aspm=off`, the kernel *declines* ASPM control in the ACPI `_OSC` handshake (`_OSC: not requesting OS control`) — so whatever the **BIOS** programmed into the link registers stays live. Here, both ends of the NIC's link kept `ASPM L1 Enabled`, and the NIC died *while `pcie_aspm=off` was active*:

```
LnkCtl: ASPM L1 Enabled; ...        # upstream switch port
LnkCtl: ASPM L1 Enabled; ...        # I226 endpoint
```

In this mode the kernel's per-device sysfs ASPM knobs (`/sys/bus/pci/devices/<dev>/link/l1_aspm`) do not exist at all. Registers are the only truth: `lspci -vv -s <dev> | grep LnkCtl:`

### 2. Secure Boot lockdown blocks `setpci` — even for root

With UEFI Secure Boot, Ubuntu enables kernel lockdown (`integrity`), which forbids raw PCI config writes from userspace:

```
kernel: Lockdown: setpci: direct PCI access is restricted; see man kernel_lockdown.7
```

There is no way to clear the ASPM bits from userspace on a locked-down boot. The sanctioned path is the sysfs knob — which only exists once the kernel owns ASPM (trap 1).

### 3. `setpci` exits 0 even when the write was blocked

The lockdown denial above still results in exit code 0, so `setpci ... && echo done` reports false success. Never trust it: verify with an `lspci` **readback** (reads are allowed under lockdown). The service in this repo logs `OK` / `WARNING` based on readback only.

### 4. `pcie_aspm=performance` is not a valid parameter

`pcie_aspm=` accepts only `off` and `force`. The policy is set with the module-parameter form `pcie_aspm.policy=performance`. The invalid form is **silently ignored** — the machine boots, nothing complains, and the policy stays `default`:

```sh
cat /sys/module/pcie_aspm/parameters/policy   # [default] performance powersave powersupersave
```

## What the fix installs

| File | Purpose |
|---|---|
| `/usr/local/sbin/disable-nic-aspm.sh` | Writes `0` to the NIC's `link/*aspm*` sysfs knobs (plus a `setpci` attempt for non-lockdown setups), then reads `LnkCtl` back via `lspci` and logs `OK`/`WARNING`. Device path is derived from `eno1` at runtime with a hardcoded fallback. |
| `disable-nic-aspm.service` + `.timer` | Runs the script at boot and re-asserts every 10 minutes (survives anything silently re-enabling ASPM mid-uptime). |
| `/usr/local/sbin/nic-detach-watchdog.sh` + `.service` | Checks the current boot's kernel log every 60 s for `PCIe link lost`. On hit (once per boot, `/run` flag): logs, `sync`, `rtcwake -m off -s 180` (S5 power-off, RTC wakes the board 3 min later = the cold cycle this failure needs); falls back to a warm `reboot` if `rtcwake` fails. It never triggers on generic network trouble — only on the literal kernel message. |

`fix/install.sh` also rewrites `pcie_aspm=off` / the invalid `pcie_aspm=performance` in `/etc/default/grub` to `pcie_aspm.policy=performance` and runs `update-grub`.

Adjust the interface name (`eno1`) and the fallback PCI address (`0000:0b:00.0`) in `disable-nic-aspm.sh` for your board if they differ.

## Verify

```sh
cat /proc/cmdline | grep -o 'pcie_aspm[^ ]*'            # pcie_aspm.policy=performance
cat /sys/module/pcie_aspm/parameters/policy              # [performance] ...
cat /sys/bus/pci/devices/0000:0b:00.0/link/l1_aspm       # 0
journalctl -t disable-nic-aspm -n 1                      # OK: ASPM disabled on 0000:0b:00.0
systemctl is-active nic-detach-watchdog.service          # active
sudo lspci -vv -s 0b:00.0 | grep LnkCtl:                 # ...ASPM Disabled...
```

## History

Chronology of attempts on this machine, for anyone tempted by the simpler fixes:

- **EEE off** — was already disabled (`ethtool --show-eee eno1`); not the cause.
- **`pcie_aspm.policy=performance` alone** — held for about a year, then the same failure returned.
- **`pcie_aspm=off`** — held for a while; NIC detached again on 2026-07-10 from an idle link, with the registers still showing BIOS-programmed `ASPM L1 Enabled` (trap 1). Machine was unreachable for ~28 h until a manual power cycle (the OS itself ran fine the whole time — cron kept firing while `systemd-timesyncd` timed out against the router).
- **Current stack** (2026-07-11): kernel owns ASPM + policy `performance` + readback-verified per-device disable at boot and every 10 min + `rtcwake` self-power-cycle watchdog as the last line. Even if some yet-unknown failure mode remains, the worst case is now a ~5-minute self-healing outage instead of a dead box.

Still on the list, next time physically at the machine: disable ASPM in BIOS setup and update the BIOS (vendor updates bundle I225/I226 NVM fixes for exactly this bug).

## Sources

- https://forum.proxmox.com/threads/network-card-drop-igc-0000-09-00-0-eno1-pcie-link-lost.121295/page-2
- https://www.reddit.com/r/pcmasterrace/comments/17vbkkf/connectivity_issue_with_marvell_aqtion_aqc113cs/
- https://www.kernel.org/doc/html/latest/admin-guide/kernel-parameters.html (`pcie_aspm=`, `pcie_aspm.policy=`)
- `man 7 kernel_lockdown` — why root cannot `setpci` under Secure Boot
- https://kagi.com/assistant/c59f19c7-7ff8-498b-bf95-a0f0621d64a0
