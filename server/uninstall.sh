#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${EUID}" -ne 0 ]]; then echo "Run as root." >&2; exit 1; fi
if [[ "${1:-}" != --confirm ]]; then echo "Usage: uninstall.sh --confirm" >&2; exit 2; fi

systemctl disable --now route-steward-hysteria.service >/dev/null 2>&1 || true
while read -r unit _; do
  [[ -n "${unit}" ]] || continue
  systemctl disable --now "${unit}" >/dev/null 2>&1 || true
done < <(systemctl list-units --all --type=service 'route-steward-relay@*.service' --no-legend 2>/dev/null || true)

# Remove only RST-managed Link interfaces. Do not touch unrelated WireGuard
# configuration on the host.
for config in /etc/wireguard/wg-rst*.conf; do
  [[ -e "${config}" ]] || continue
  interface="$(basename "${config}" .conf)"
  systemctl disable --now "wg-quick@${interface}.service" >/dev/null 2>&1 || true
  rm -f "/etc/wireguard/${interface}.conf" "/etc/wireguard/${interface}.key" "/etc/wireguard/${interface}.pub"
done

rm -f /etc/systemd/system/route-steward-hysteria.service /etc/systemd/system/route-steward-relay@.service
rm -rf /etc/systemd/system/route-steward-relay@*.service.d
rm -rf /etc/route-steward /var/lib/route-steward /usr/local/lib/route-steward

# Remove only host policy files installed under RST-owned names. Do not reset
# UFW, remove unrelated packages, delete swap, or touch unrelated SSH/WireGuard
# state.
rm -f \
  /etc/sysctl.d/99-route-steward.conf \
  /etc/sysctl.d/99-route-steward-relay.conf \
  /etc/ssh/sshd_config.d/99-route-steward-ssh.conf \
  /etc/modules-load.d/route-steward-bbr.conf \
  /etc/systemd/journald.conf.d/99-route-steward.conf \
  /etc/apt/apt.conf.d/52-route-steward-unattended-upgrades

if id route-steward-hysteria >/dev/null 2>&1; then userdel route-steward-hysteria >/dev/null 2>&1 || true; fi
systemctl daemon-reload
sysctl --system >/dev/null 2>&1 || true
if command -v sshd >/dev/null 2>&1 && sshd -t >/dev/null 2>&1; then systemctl reload ssh >/dev/null 2>&1 || true; fi
systemctl restart systemd-journald >/dev/null 2>&1 || true
echo 'RST_UNINSTALLED=1'
