#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE_DIR=${1:-/tmp/private-proxy-manager/config}
HYSTERIA_VERSION=v2.9.3
HYSTERIA_SHA256=66dbdb0608f25f3057b433afe975a9fc1af2ca8e512479e294988b3ef363d6c1
PPM_BIN_DIR=/usr/local/lib/private-proxy-manager
HYSTERIA_BIN=${PPM_BIN_DIR}/hysteria
PPM_CONFIG_DIR=/etc/private-proxy-manager/hysteria
PPM_STATE_DIR=/var/lib/private-proxy-manager/hysteria

install -d -m 0755 "${PPM_BIN_DIR}"
if [[ ! -x "${HYSTERIA_BIN}" || "$(sha256sum "${HYSTERIA_BIN}" | awk '{print $1}')" != "${HYSTERIA_SHA256}" ]]; then
  work_dir=$(mktemp -d)
  trap 'rm -rf "${work_dir}"' EXIT
  curl -fL --retry 3 --connect-timeout 15 \
    -o "${work_dir}/hysteria-linux-amd64" \
    "https://github.com/apernet/hysteria/releases/download/app/${HYSTERIA_VERSION}/hysteria-linux-amd64"
  printf '%s  %s\n' "${HYSTERIA_SHA256}" "${work_dir}/hysteria-linux-amd64" | sha256sum --check --strict
  install -m 0755 "${work_dir}/hysteria-linux-amd64" "${HYSTERIA_BIN}"
fi
id ppm-hysteria >/dev/null 2>&1 || useradd --system --create-home --home-dir "${PPM_STATE_DIR}" --shell /usr/sbin/nologin ppm-hysteria
install -d -o ppm-hysteria -g ppm-hysteria -m 0750 "${PPM_CONFIG_DIR}" "${PPM_CONFIG_DIR}/tls" "${PPM_STATE_DIR}"
install -m 0644 "${SOURCE_DIR}/private-proxy-manager-hysteria.service" /etc/systemd/system/private-proxy-manager-hysteria.service
systemctl daemon-reload

printf 'HYSTERIA=%s\n' "$("${HYSTERIA_BIN}" version | head -n 1)"
sha256sum "${HYSTERIA_BIN}"
printf 'PROXY_BINARIES_OK\n'
