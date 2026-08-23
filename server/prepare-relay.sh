#!/usr/bin/env bash
set -Eeuo pipefail

INTERFACE=""
PRIVATE_KEY_FILE=""

while (($#)); do
  case "$1" in
    --interface) INTERFACE="${2:-}"; shift 2 ;;
    --private-key-file) PRIVATE_KEY_FILE="${2:-}"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root." >&2
  exit 1
fi
if [[ ! "${INTERFACE}" =~ ^[a-z0-9][a-z0-9_-]{0,14}$ ]]; then
  echo "A valid WireGuard interface is required." >&2
  exit 2
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends wireguard-tools iptables >/dev/null
install -d -m 0700 -o root -g root /etc/wireguard

KEY_FILE="/etc/wireguard/${INTERFACE}.key"
PUBLIC_FILE="/etc/wireguard/${INTERFACE}.pub"
if [[ -n "${PRIVATE_KEY_FILE}" ]]; then
  [[ -s "${PRIVATE_KEY_FILE}" ]] || { echo "Managed WireGuard private key file is missing." >&2; exit 2; }
  managed_key="$(tr -d '\r\n' <"${PRIVATE_KEY_FILE}")"
  [[ "${managed_key}" =~ ^[A-Za-z0-9+/]{43}=$ ]] || { echo "Managed WireGuard private key is invalid." >&2; exit 2; }
  if [[ -s "${KEY_FILE}" ]] && [[ "$(tr -d '\r\n' <"${KEY_FILE}")" != "${managed_key}" ]]; then
    echo "Managed WireGuard key does not match existing state; use an explicit Link migration." >&2
    exit 1
  fi
  printf '%s\n' "${managed_key}" >"${KEY_FILE}"
elif [[ ! -s "${KEY_FILE}" ]]; then
  umask 077
  wg genkey >"${KEY_FILE}"
fi
wg pubkey <"${KEY_FILE}" >"${PUBLIC_FILE}"
chmod 0600 "${KEY_FILE}"
chmod 0644 "${PUBLIC_FILE}"
printf 'PUBLIC_KEY=%s\n' "$(cat "${PUBLIC_FILE}")"
