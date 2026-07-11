#!/bin/bash
# Install the igc NIC fix stack (ASPM disable service + timer, detach watchdog).
# Run as root from the repo's fix/ directory. Idempotent.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run as root" >&2; exit 1; }
DIR=$(cd "$(dirname "$0")" && pwd)

install -m755 "$DIR/disable-nic-aspm.sh"    /usr/local/sbin/disable-nic-aspm.sh
install -m755 "$DIR/nic-detach-watchdog.sh" /usr/local/sbin/nic-detach-watchdog.sh
install -m644 "$DIR/disable-nic-aspm.service" "$DIR/disable-nic-aspm.timer" \
              "$DIR/nic-detach-watchdog.service" /etc/systemd/system/

# GRUB: the kernel must OWN ASPM for the sysfs knobs to exist.
#  - remove `pcie_aspm=off` (trap 1: it leaves BIOS-programmed ASPM running)
#  - remove `pcie_aspm=performance` (trap 4: invalid value, silently ignored)
#  - ensure `pcie_aspm.policy=performance` (the valid policy form)
if grep -qE 'pcie_aspm=(off|performance)' /etc/default/grub; then
  sed -i.bak -E 's/pcie_aspm=(off|performance)/pcie_aspm.policy=performance/' /etc/default/grub
  update-grub
elif ! grep -q 'pcie_aspm\.policy=performance' /etc/default/grub; then
  sed -i.bak 's/^GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="pcie_aspm.policy=performance /' /etc/default/grub
  update-grub
fi

# apply the policy immediately if the kernel owns ASPM on this boot
# (fails harmlessly when the current boot still has pcie_aspm=off)
echo performance > /sys/module/pcie_aspm/parameters/policy 2>/dev/null || true

systemctl daemon-reload
systemctl enable --now disable-nic-aspm.service disable-nic-aspm.timer nic-detach-watchdog.service

echo "--- verdict (must say OK; WARNING is expected only on a pcie_aspm=off boot):"
journalctl -t disable-nic-aspm -n 1 --no-pager || true
