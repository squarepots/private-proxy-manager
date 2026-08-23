#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root." >&2
  exit 1
fi
# shellcheck source=/dev/null
. /etc/os-release
[[ "${ID}" == ubuntu && "${VERSION_ID}" == 24.04 ]] || {
  echo "Only Ubuntu 24.04 is supported; found ${PRETTY_NAME}." >&2
  exit 1
}
[[ "$(dpkg --print-architecture)" == amd64 ]] || {
  echo "Only x86_64/amd64 is supported." >&2
  exit 1
}
[[ "$(uname -m)" == x86_64 ]] || {
  echo "Kernel architecture must be x86_64." >&2
  exit 1
}
echo 'PREFLIGHT_OK=1'
