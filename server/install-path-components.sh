#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE_DIR=${1:-/tmp/route-steward/config}
HYSTERIA_VERSION=v2.9.3
HYSTERIA_SHA256=66dbdb0608f25f3057b433afe975a9fc1af2ca8e512479e294988b3ef363d6c1
RST_BIN_DIR=/usr/local/lib/route-steward
HYSTERIA_BIN=${RST_BIN_DIR}/hysteria
RST_CONFIG_DIR=/etc/route-steward/hysteria
RST_STATE_DIR=/var/lib/route-steward/hysteria

install -d -m 0755 "${RST_BIN_DIR}"
if [[ ! -x "${HYSTERIA_BIN}" || "$(sha256sum "${HYSTERIA_BIN}" | awk '{print $1}')" != "${HYSTERIA_SHA256}" ]]; then
  work_dir=$(mktemp -d)
  trap 'rm -rf "${work_dir}"' EXIT
  curl -fL --retry 3 --connect-timeout 15 \
    -o "${work_dir}/hysteria-linux-amd64" \
    "https://github.com/apernet/hysteria/releases/download/app/${HYSTERIA_VERSION}/hysteria-linux-amd64"
  printf '%s  %s\n' "${HYSTERIA_SHA256}" "${work_dir}/hysteria-linux-amd64" | sha256sum --check --strict
  install -m 0755 "${work_dir}/hysteria-linux-amd64" "${HYSTERIA_BIN}"
fi
id route-steward-hysteria >/dev/null 2>&1 || useradd --system --create-home --home-dir "${RST_STATE_DIR}" --shell /usr/sbin/nologin route-steward-hysteria
install -d -o route-steward-hysteria -g route-steward-hysteria -m 0750 "${RST_CONFIG_DIR}" "${RST_CONFIG_DIR}/tls" "${RST_STATE_DIR}"
install -m 0644 "${SOURCE_DIR}/route-steward-hysteria.service" /etc/systemd/system/route-steward-hysteria.service
systemctl daemon-reload

printf 'HYSTERIA=%s\n' "$("${HYSTERIA_BIN}" version | head -n 1)"
sha256sum "${HYSTERIA_BIN}"
printf 'PATH_COMPONENTS_OK\n'
