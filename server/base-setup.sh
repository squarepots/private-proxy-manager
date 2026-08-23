#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR=${1:-/tmp/route-steward/config}

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates \
  curl \
  jq \
  openssl \
  ufw \
  unattended-upgrades \
  mtr-tiny \
  vnstat

install -D -m 0644 "$SOURCE_DIR/99-route-steward-ssh.conf" /etc/ssh/sshd_config.d/99-route-steward-ssh.conf
install -D -m 0644 "$SOURCE_DIR/99-route-steward-sysctl.conf" /etc/sysctl.d/99-route-steward.conf
install -D -m 0644 "$SOURCE_DIR/bbr.conf" /etc/modules-load.d/route-steward-bbr.conf
install -D -m 0644 "$SOURCE_DIR/99-limits.conf" /etc/systemd/journald.conf.d/99-route-steward.conf
install -D -m 0644 "$SOURCE_DIR/52unattended-upgrades-local" /etc/apt/apt.conf.d/52-route-steward-unattended-upgrades

install -d -m 0755 /run/sshd
sshd -t
systemctl reload ssh.service

modprobe tcp_bbr
sysctl --system >/dev/null

if ! swapon --show=NAME --noheadings | grep -qx '/swapfile'; then
  if [ ! -f /swapfile ]; then
    fallocate -l 1G /swapfile
    chmod 0600 /swapfile
    mkswap /swapfile >/dev/null
  fi
  swapon /swapfile
fi
if ! grep -qE '^/swapfile[[:space:]]' /etc/fstab; then
  sed -i '$a /swapfile none swap sw 0 0' /etc/fstab
fi

sed -i 's/^IPV6=.*/IPV6=yes/' /etc/default/ufw
ufw default deny incoming >/dev/null
ufw default allow outgoing >/dev/null
ufw limit 22/tcp comment 'RST SSH key-only' >/dev/null
ufw deny out 25/tcp comment 'RST block SMTP abuse' >/dev/null
ufw deny out 465/tcp comment 'RST block SMTPS abuse' >/dev/null
ufw deny out 587/tcp comment 'RST block submission abuse' >/dev/null
ufw --force enable >/dev/null

systemctl restart systemd-journald.service
systemctl enable --now unattended-upgrades.service vnstat.service >/dev/null

printf 'BASE_SETUP_OK\n'
printf 'TCP_CC=%s\n' "$(sysctl -n net.ipv4.tcp_congestion_control)"
printf 'DEFAULT_QDISC=%s\n' "$(sysctl -n net.core.default_qdisc)"
printf 'RMEM_MAX=%s\n' "$(sysctl -n net.core.rmem_max)"
printf 'WMEM_MAX=%s\n' "$(sysctl -n net.core.wmem_max)"
swapon --show
ufw status verbose
test -f /var/run/reboot-required && printf 'REBOOT_REQUIRED=yes\n' || printf 'REBOOT_REQUIRED=no\n'
