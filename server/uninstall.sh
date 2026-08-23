#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${EUID}" -ne 0 ]]; then echo "Run as root." >&2; exit 1; fi
if [[ "${1:-}" != --confirm ]]; then echo "Usage: uninstall.sh --confirm" >&2; exit 2; fi

systemctl disable --now private-proxy-manager-hysteria.service >/dev/null 2>&1 || true
while read -r unit _; do
  [[ -n "${unit}" ]] || continue
  systemctl disable --now "${unit}" >/dev/null 2>&1 || true
done < <(systemctl list-units --all --type=service 'private-proxy-manager-relay@*.service' --no-legend 2>/dev/null || true)

# Remove only PPM-managed Link interfaces. Do not touch unrelated WireGuard
# configuration on the host.
for config in /etc/wireguard/wg-ppm*.conf; do
  [[ -e "${config}" ]] || continue
  interface="$(basename "${config}" .conf)"
  systemctl disable --now "wg-quick@${interface}.service" >/dev/null 2>&1 || true
  rm -f "/etc/wireguard/${interface}.conf" "/etc/wireguard/${interface}.key" "/etc/wireguard/${interface}.pub"
done

rm -f /etc/systemd/system/private-proxy-manager-hysteria.service /etc/systemd/system/private-proxy-manager-relay@.service
rm -rf /etc/systemd/system/private-proxy-manager-relay@*.service.d
rm -rf /etc/private-proxy-manager /var/lib/private-proxy-manager /usr/local/lib/private-proxy-manager

# Remove only host policy files installed under PPM-owned names. Do not reset
# UFW, remove unrelated packages, delete swap, or touch unrelated SSH/WireGuard
# state.
rm -f \
  /etc/sysctl.d/99-private-proxy-manager.conf \
  /etc/sysctl.d/99-private-proxy-manager-relay.conf \
  /etc/ssh/sshd_config.d/99-private-proxy-manager-ssh.conf \
  /etc/modules-load.d/private-proxy-manager-bbr.conf \
  /etc/systemd/journald.conf.d/99-private-proxy-manager.conf \
  /etc/apt/apt.conf.d/52-private-proxy-manager-unattended-upgrades

if id ppm-hysteria >/dev/null 2>&1; then userdel ppm-hysteria >/dev/null 2>&1 || true; fi
systemctl daemon-reload
sysctl --system >/dev/null 2>&1 || true
if command -v sshd >/dev/null 2>&1 && sshd -t >/dev/null 2>&1; then systemctl reload ssh >/dev/null 2>&1 || true; fi
systemctl restart systemd-journald >/dev/null 2>&1 || true
echo 'PPM_UNINSTALLED=1'
