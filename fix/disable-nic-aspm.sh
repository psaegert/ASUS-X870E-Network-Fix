#!/bin/bash
# Disable ASPM on the I226 NIC link, then VERIFY BY READBACK.
# (Under Secure Boot lockdown, setpci writes are blocked but still exit 0.)
DEVPATH=$(readlink -f /sys/class/net/eno1/device 2>/dev/null)
[ -z "$DEVPATH" ] && DEVPATH=/sys/bus/pci/devices/0000:0b:00.0
DEV=$(basename "$DEVPATH"); UP=$(basename "$(dirname "$DEVPATH")")
# attempt 1: kernel sysfs knobs (sanctioned; exist once kernel owns ASPM)
for f in "$DEVPATH"/link/*aspm* "$DEVPATH"/link/clkpm; do
  [ -e "$f" ] && echo 0 > "$f" 2>/dev/null
done
# attempt 2: raw register write (only works without lockdown)
setpci -s "$UP"  CAP_EXP+10.w=0000:0003 2>/dev/null
setpci -s "$DEV" CAP_EXP+10.w=0000:0003 2>/dev/null
# readback = ground truth
STATE=$(lspci -vv -s "$DEV" 2>/dev/null | grep -m1 "LnkCtl:")
case "$STATE" in
  *"ASPM Disabled"*) logger -t disable-nic-aspm "OK: ASPM disabled on $DEV" ;;
  *) logger -t disable-nic-aspm "WARNING: ASPM still enabled on $DEV — kernel does not own ASPM on this boot (pcie_aspm=off?) and lockdown blocks setpci" ;;
esac
