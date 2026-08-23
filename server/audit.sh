#!/usr/bin/env bash
set -Eeuo pipefail

PROXY_PORT="443"
EXPECTED_FINGERPRINT=""
EXPECTED_CONFIG_HASH=""
PPM_SERVICE=private-proxy-manager-hysteria.service
PPM_CONFIG=/etc/private-proxy-manager/hysteria/config.yaml
PPM_CERT=/etc/private-proxy-manager/hysteria/tls/server.crt
PPM_STATE=/var/lib/private-proxy-manager/credentials.json
PPM_BIN=/usr/local/lib/private-proxy-manager/hysteria

fail_category() {
  printf 'PPM_AUDIT_CATEGORY=%s\n' "$1"
  exit 1
}

while (($#)); do
  case "$1" in
    --proxy-port) PROXY_PORT="${2:-}"; shift 2 ;;
    --expected-fingerprint) EXPECTED_FINGERPRINT="${2:-}"; shift 2 ;;
    --expected-config-hash) EXPECTED_CONFIG_HASH="${2:-}"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [[ "${EUID}" -ne 0 ]]; then echo "Run as root." >&2; exit 1; fi
if [[ ! "${PROXY_PORT}" =~ ^[0-9]{1,5}$ ]] || ((PROXY_PORT < 1 || PROXY_PORT > 65535)); then echo "Invalid HY2 port." >&2; exit 2; fi
if [[ -n "${EXPECTED_FINGERPRINT}" && ! "${EXPECTED_FINGERPRINT}" =~ ^[0-9a-fA-F]{64}$ ]]; then echo "Invalid expected certificate fingerprint." >&2; exit 2; fi
if [[ -n "${EXPECTED_CONFIG_HASH}" && ! "${EXPECTED_CONFIG_HASH}" =~ ^[0-9a-fA-F]{64}$ ]]; then echo "Invalid expected configuration hash." >&2; exit 2; fi

systemctl is-enabled --quiet "${PPM_SERVICE}" || fail_category service-missing
systemctl is-active --quiet "${PPM_SERVICE}" || fail_category service-missing
[[ "$(systemctl show -p User --value "${PPM_SERVICE}")" == ppm-hysteria ]] || fail_category remote-config-mismatch
[[ -x "${PPM_BIN}" && -s "${PPM_CONFIG}" && -s "${PPM_CERT}" && -s "${PPM_STATE}" ]] || fail_category remote-config-mismatch
jq -e '.schema == 1 and .hysteria.auth and .hysteria.obfs and (has("reality") | not)' "${PPM_STATE}" >/dev/null 2>&1 || fail_category remote-config-mismatch

ss -H -lun "sport = :${PROXY_PORT}" | grep -q . || fail_category hysteria-listener-mismatch
if ss -H -ltn "sport = :${PROXY_PORT}" | grep -q .; then fail_category hysteria-listener-mismatch; fi
config_listen="$(awk '/^listen:/{gsub(/^.*:/,"",$0); gsub(/[[:space:]]/,"",$0); print; exit}' "${PPM_CONFIG}")"
[[ "${config_listen}" == "${PROXY_PORT}" ]] || fail_category remote-config-mismatch
state_auth="$(jq -r '.hysteria.auth' "${PPM_STATE}")"
state_obfs="$(jq -r '.hysteria.obfs' "${PPM_STATE}")"
config_auth="$(awk '/^auth:/{f=1;next} f && /^[^ ]/{f=0} f && $1=="password:"{print $2; exit}' "${PPM_CONFIG}")"
config_obfs="$(awk '/^[[:space:]]+salamander:/{f=1;next} f && /^[[:space:]]{0,2}[^ ]/{f=0} f && $1=="password:"{print $2; exit}' "${PPM_CONFIG}")"
[[ -n "${state_auth}" && -n "${state_obfs}" && "${config_auth}" == "${state_auth}" && "${config_obfs}" == "${state_obfs}" ]] || fail_category remote-config-mismatch

openssl x509 -checkend 0 -noout -in "${PPM_CERT}" >/dev/null 2>&1 || fail_category certificate-mismatch
actual_fingerprint="$(openssl x509 -in "${PPM_CERT}" -noout -fingerprint -sha256 | cut -d= -f2 | tr -d ':[:space:]' | tr 'A-F' 'a-f')"
if [[ -n "${EXPECTED_FINGERPRINT}" && "${actual_fingerprint}" != "${EXPECTED_FINGERPRINT,,}" ]]; then fail_category certificate-mismatch; fi
if [[ -n "${EXPECTED_CONFIG_HASH}" ]]; then
  material="hysteria2|port=${PROXY_PORT}|auth=${state_auth}|obfs=${state_obfs}|cert=${actual_fingerprint}"
  actual_hash="$(printf '%s' "${material}" | sha256sum | awk '{print $1}')"
  [[ "${actual_hash}" == "${EXPECTED_CONFIG_HASH,,}" ]] || fail_category remote-config-mismatch
fi

ufw status | grep -q '^Status: active' || fail_category firewall-network-mismatch
ufw status | grep -Eq "(^|[[:space:]])${PROXY_PORT}/udp([[:space:]]|$)" || fail_category firewall-network-mismatch
if ufw status | grep -Eq "(^|[[:space:]])${PROXY_PORT}/tcp([[:space:]]|$)"; then fail_category firewall-network-mismatch; fi
sshd -t >/dev/null 2>&1 || fail_category remote-config-mismatch
ssh_effective="$(sshd -T 2>/dev/null)" || fail_category remote-config-mismatch
grep -q '^passwordauthentication no$' <<<"${ssh_effective}" || fail_category remote-config-mismatch
grep -q '^pubkeyauthentication yes$' <<<"${ssh_effective}" || fail_category remote-config-mismatch

actual_ipv4="$(curl -4 -fsS --max-time 10 https://checkip.amazonaws.com 2>/dev/null | tr -d '\r\n')" || fail_category undetermined
[[ "${actual_ipv4}" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || fail_category undetermined
printf 'IPV4=%s\n' "${actual_ipv4}"
printf 'HYSTERIA_VERSION=%s\n' "$("${PPM_BIN}" version 2>/dev/null | head -n 1 | tr -d '\r\n')"
if command -v wg >/dev/null 2>&1; then printf 'WIREGUARD_VERSION=%s\n' "$(wg --version | head -n 1 | tr -d '\r\n')"; fi
printf 'PPM_AUDIT_CATEGORY=in-sync\n'
printf 'AUDIT_OK=1\n'
