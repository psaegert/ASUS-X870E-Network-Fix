#!/bin/bash
FLAG=/run/nic-detach-recovery-fired
while true; do
  if [ ! -e "$FLAG" ] && journalctl -k -b 0 --no-pager 2>/dev/null | grep -q "PCIe link lost"; then
    touch "$FLAG"
    logger -t nic-watchdog "igc PCIe link lost — self power-cycling (rtcwake, wake in 180s)"
    sync
    rtcwake -m off -s 180 || { logger -t nic-watchdog "rtcwake failed — warm reboot fallback"; systemctl reboot; }
  fi
  sleep 60
done
