#!/usr/bin/env bash
set -Eeuo pipefail

ROLE=""
INTERFACE=""
NAME=""
INGRESS_PORT=""
PORT_HOPPING_RANGE=""
TUNNEL_PORT=""
SUBNET=""
PEER_IP=""
EXPECTED_EXIT=""
EXPECTED_PEER_PUBLIC_KEY=""
EXPECTED_FINGERPRINT=""
EXPECTED_CONFIG_HASH=""
RST_BIN=/usr/local/lib/route-steward/hysteria

fail_category() {
  printf 'RST_AUDIT_CATEGORY=%s\n' "$1"
  exit 1
}

while (($#)); do
  case "$1" in
    --role) ROLE="${2:-}"; shift 2 ;;
    --interface) INTERFACE="${2:-}"; shift 2 ;;
    --name) NAME="${2:-}"; shift 2 ;;
    --ingress-port) INGRESS_PORT="${2:-}"; shift 2 ;;
    --port-hopping-range) PORT_HOPPING_RANGE="${2:-}"; shift 2 ;;
    --tunnel-port) TUNNEL_PORT="${2:-}"; shift 2 ;;
    --subnet) SUBNET="${2:-}"; shift 2 ;;
    --peer-ip) PEER_IP="${2:-}"; shift 2 ;;
    --expected-exit) EXPECTED_EXIT="${2:-}"; shift 2 ;;
    --expected-peer-public-key) EXPECTED_PEER_PUBLIC_KEY="${2:-}"; shift 2 ;;
    --expected-fingerprint) EXPECTED_FINGERPRINT="${2:-}"; shift 2 ;;
    --expected-config-hash) EXPECTED_CONFIG_HASH="${2:-}"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [[ "${EUID}" -ne 0 ]]; then echo "Run as root." >&2; exit 1; fi
[[ "${ROLE}" == entry || "${ROLE}" == exit ]] || { echo "Role must be entry or exit." >&2; exit 2; }
[[ "${INTERFACE}" =~ ^[a-z0-9][a-z0-9_-]{0,14}$ ]] || { echo "A valid interface is required." >&2; exit 2; }
[[ "${PEER_IP}" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || { echo "A valid peer IPv4 is required." >&2; exit 2; }
if [[ -n "${EXPECTED_PEER_PUBLIC_KEY}" && ! "${EXPECTED_PEER_PUBLIC_KEY}" =~ ^[A-Za-z0-9+/]{43}=$ ]]; then echo "Invalid expected peer key." >&2; exit 2; fi
if [[ -n "${EXPECTED_FINGERPRINT}" && ! "${EXPECTED_FINGERPRINT}" =~ ^[0-9a-fA-F]{64}$ ]]; then echo "Invalid expected certificate fingerprint." >&2; exit 2; fi
if [[ -n "${EXPECTED_CONFIG_HASH}" && ! "${EXPECTED_CONFIG_HASH}" =~ ^[0-9a-fA-F]{64}$ ]]; then echo "Invalid expected configuration hash." >&2; exit 2; fi

systemctl is-enabled --quiet "wg-quick@${INTERFACE}.service" || fail_category wireguard-link-mismatch
systemctl is-active --quiet "wg-quick@${INTERFACE}.service" || fail_category wireguard-link-mismatch
wg show "${INTERFACE}" >/dev/null 2>&1 || fail_category wireguard-link-mismatch
if [[ -n "${EXPECTED_PEER_PUBLIC_KEY}" ]]; then
  actual_peer="$(wg show "${INTERFACE}" peers 2>/dev/null | head -n 1)"
  [[ "${actual_peer}" == "${EXPECTED_PEER_PUBLIC_KEY}" ]] || fail_category wireguard-link-mismatch
fi
ping -4 -I "${INTERFACE}" -c 2 -W 3 "${PEER_IP}" >/dev/null 2>&1 || fail_category wireguard-link-mismatch
latest="$(wg show "${INTERFACE}" latest-handshakes 2>/dev/null | awk 'NR==1 {print $2}')"
now="$(date +%s)"
if [[ ! "${latest}" =~ ^[0-9]+$ ]] || ((latest <= 0 || now - latest >= 180)); then fail_category wireguard-link-mismatch; fi
printf 'WIREGUARD_VERSION=%s\n' "$(wg --version | head -n 1 | tr -d '\r\n')"

if [[ "${ROLE}" == exit ]]; then
  if [[ ! "${TUNNEL_PORT}" =~ ^[0-9]{1,5}$ ]] || ((TUNNEL_PORT < 1 || TUNNEL_PORT > 65535)); then echo "A valid tunnel port is required." >&2; exit 2; fi
  [[ "${SUBNET}" =~ ^10\.77\.[0-9]{1,3}\.0/30$ ]] || { echo "A valid relay subnet is required." >&2; exit 2; }
  [[ "$(sysctl -n net.ipv4.ip_forward)" == 1 ]] || fail_category firewall-network-mismatch
  ss -H -lun "sport = :${TUNNEL_PORT}" | grep -q . || fail_category wireguard-link-mismatch
  iptables -t nat -S POSTROUTING | grep -Fq "${SUBNET}" || fail_category firewall-network-mismatch
  ufw status | grep -q '^Status: active' || fail_category firewall-network-mismatch
  printf 'RST_AUDIT_CATEGORY=in-sync\n'
  printf 'RELAY_EXIT_AUDIT_OK=1\n'
  exit 0
fi

[[ "${NAME}" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "A valid relay Route name is required." >&2; exit 2; }
if [[ ! "${INGRESS_PORT}" =~ ^[0-9]{1,5}$ ]] || ((INGRESS_PORT < 1 || INGRESS_PORT > 65535)); then echo "A valid proxy port is required." >&2; exit 2; fi
PORT_HOPPING_ENABLED=0
EXPECTED_LISTEN="${INGRESS_PORT}"
FIREWALL_PORT="${INGRESS_PORT}"
if [[ -n "${PORT_HOPPING_RANGE}" ]]; then
  [[ "${PORT_HOPPING_RANGE}" =~ ^([1-9][0-9]{0,4})-([1-9][0-9]{0,4})$ ]] || { echo "Invalid Hysteria2 port-hopping range." >&2; exit 2; }
  HOP_START=$((10#${BASH_REMATCH[1]}))
  HOP_END=$((10#${BASH_REMATCH[2]}))
  ((HOP_START == INGRESS_PORT && HOP_END > HOP_START && HOP_END <= 65535 && HOP_END - HOP_START + 1 <= 8)) || { echo "Port hopping must start at --ingress-port and contain 2..8 UDP ports." >&2; exit 2; }
  PORT_HOPPING_ENABLED=1
  EXPECTED_LISTEN="${PORT_HOPPING_RANGE}"
  FIREWALL_PORT="${HOP_START}:${HOP_END}"
fi
[[ "${EXPECTED_EXIT}" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || { echo "Expected exit IPv4 is required." >&2; exit 2; }

service="route-steward-relay@${NAME}.service"
systemctl is-enabled --quiet "${service}" || fail_category service-missing
systemctl is-active --quiet "${service}" || fail_category service-missing
[[ "$(systemctl show -p User --value "${service}")" == route-steward-hysteria ]] || fail_category remote-config-mismatch

state="/var/lib/route-steward/relays/${NAME}.json"
hy_dir="/etc/route-steward/hysteria/relays/${NAME}"
[[ -x "${RST_BIN}" && -s "${state}" && -s "${hy_dir}/config.yaml" && -s "${hy_dir}/server.crt" ]] || fail_category remote-config-mismatch
jq -e '.schema == 1 and .hysteria.auth and .hysteria.obfs and (has("reality") | not)' "${state}" >/dev/null 2>&1 || fail_category remote-config-mismatch
ss -H -lun "sport = :${INGRESS_PORT}" | grep -q . || fail_category hysteria-listener-mismatch
if ss -H -ltn "sport = :${INGRESS_PORT}" | grep -q .; then fail_category hysteria-listener-mismatch; fi
config_listen="$(awk '/^listen:/{gsub(/^.*:/,"",$0); gsub(/[[:space:]]/,"",$0); print; exit}' "${hy_dir}/config.yaml")"
[[ "${config_listen}" == "${EXPECTED_LISTEN}" ]] || fail_category remote-config-mismatch
grep -Fq "bindDevice: ${INTERFACE}" "${hy_dir}/config.yaml" || fail_category remote-config-mismatch
state_auth="$(jq -r '.hysteria.auth' "${state}")"
state_obfs="$(jq -r '.hysteria.obfs' "${state}")"
config_auth="$(awk '/^auth:/{f=1;next} f && /^[^ ]/{f=0} f && $1=="password:"{print $2; exit}' "${hy_dir}/config.yaml")"
config_obfs="$(awk '/^[[:space:]]+salamander:/{f=1;next} f && /^[[:space:]]{0,2}[^ ]/{f=0} f && $1=="password:"{print $2; exit}' "${hy_dir}/config.yaml")"
[[ "${config_auth}" == "${state_auth}" && "${config_obfs}" == "${state_obfs}" ]] || fail_category remote-config-mismatch

openssl x509 -checkend 0 -noout -in "${hy_dir}/server.crt" >/dev/null 2>&1 || fail_category certificate-mismatch
actual_fingerprint="$(openssl x509 -in "${hy_dir}/server.crt" -noout -fingerprint -sha256 | cut -d= -f2 | tr -d ':[:space:]' | tr 'A-F' 'a-f')"
if [[ -n "${EXPECTED_FINGERPRINT}" && "${actual_fingerprint}" != "${EXPECTED_FINGERPRINT,,}" ]]; then fail_category certificate-mismatch; fi
if [[ -n "${EXPECTED_CONFIG_HASH}" ]]; then
  material="hysteria2-relay|port=${INGRESS_PORT}|hop=${PORT_HOPPING_RANGE:-none}|auth=${state_auth}|obfs=${state_obfs}|cert=${actual_fingerprint}|bind=${INTERFACE}"
  actual_hash="$(printf '%s' "${material}" | sha256sum | awk '{print $1}')"
  [[ "${actual_hash}" == "${EXPECTED_CONFIG_HASH,,}" ]] || fail_category remote-config-mismatch
fi

ufw status | grep -q '^Status: active' || fail_category firewall-network-mismatch
ufw status | grep -Eq "(^|[[:space:]])${FIREWALL_PORT}/udp([[:space:]]|$)" || fail_category firewall-network-mismatch
if ufw status | grep -Eq "(^|[[:space:]])${FIREWALL_PORT}/tcp([[:space:]]|$)"; then fail_category firewall-network-mismatch; fi
PORT_HOPPING_DROP_IN="/etc/systemd/system/route-steward-relay@${NAME}.service.d/20-port-hopping.conf"
if [[ "${PORT_HOPPING_ENABLED}" -eq 1 ]]; then
  [[ -s "${PORT_HOPPING_DROP_IN}" ]] || fail_category remote-config-mismatch
  grep -Fqx 'AmbientCapabilities=CAP_NET_RAW CAP_NET_ADMIN' "${PORT_HOPPING_DROP_IN}" || fail_category remote-config-mismatch
elif [[ -e "${PORT_HOPPING_DROP_IN}" ]]; then
  fail_category remote-config-mismatch
fi

actual_exit="$(curl -4 --interface "${INTERFACE}" --connect-timeout 8 --max-time 15 -fsS https://checkip.amazonaws.com 2>/dev/null | tr -d '\r\n')" || fail_category undetermined
[[ "${actual_exit}" == "${EXPECTED_EXIT}" ]] || fail_category egress-mismatch
printf 'RELAY_EGRESS_IPV4=%s\n' "${actual_exit}"
printf 'HYSTERIA_VERSION=%s\n' "$("${RST_BIN}" version 2>/dev/null | head -n 1 | tr -d '\r\n')"
printf 'RST_AUDIT_CATEGORY=in-sync\n'
printf 'RELAY_ENTRY_AUDIT_OK=1\n'
printf 'RELAY_EGRESS_OK=1\n'
