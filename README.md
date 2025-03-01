# Possible ASUS X870E Network Fix

## TL;DR
Permanently set the ASPM policy to `performance`

## Uptime
10 days and counting

## Problem
Ubuntu server (Ubuntu 24.04.2 LTS) would reliably lose network connection after a seemingly random number of days of uptime.

Several sources recommended to turn of [EEE](https://en.wikipedia.org/wiki/Energy-Efficient_Ethernet), but it was disabled already:

```sh
(base) psaegert@solomon:~$ ethtool --show-eee eno1
EEE settings for eno1:
        EEE status: disabled
        Tx LPI: disabled
        Supported EEE link modes:  Not reported
        Advertised EEE link modes:  Not reported
        Link partner advertised EEE link modes:  Not reported
```

## Instructions
1. Open the GRUB configuration file 
```sh
sudo nano /etc/default/grub
```
2. Add ` pcie_aspm.policy=performance`  to the  `GRUB_CMDLINE_LINUX_DEFAULT` value:
```
GRUB_CMDLINE_LINUX_DEFAULT="... pcie_aspm.policy=performance"
```
3. Save the file
4. Update GRUB
```sh
sudo update-grub
```
5. Reboot
```sh
sudo reboot
```

## Sources
- https://kagi.com/assistant/c59f19c7-7ff8-498b-bf95-a0f0621d64a0
- https://forum.proxmox.com/threads/network-card-drop-igc-0000-09-00-0-eno1-pcie-link-lost.121295/page-2
- https://www.reddit.com/r/pcmasterrace/comments/17vbkkf/connectivity_issue_with_marvell_aqtion_aqc113cs/
