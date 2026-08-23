#!/usr/bin/env bash
set -Eeuo pipefail

umask 077

INTERFACE=""
LOCAL_CIDR=""
PEER_IP=""
PEER_PUBLIC_KEY=""
EXIT_ENDPOINT=""
TUNNEL_PORT=""
PROXY_PORT=""
ENTRY_IPV4=""
ENTRY_IPV6=""
EXIT_IPV4=""
NAME=""
VIA_NAME=""
OUTPUT="/var/lib/private-proxy-manager/relay-client-payload.yaml"
UNIT_DIR=""
CREDENTIAL_DIR=""
HY_BIN="/usr/local/lib/private-proxy-manager/hysteria"
STAGE="$(mktemp -d /run/private-proxy-manager-relay-entry.XXXXXX)"
HY_PID=""

cleanup() {
  if [[ -n "${HY_PID}" ]] && kill -0 "${HY_PID}" 2>/dev/null; then
    kill -TERM "${HY_PID}" 2>/dev/null || true
    wait "${HY_PID}" 2>/dev/null || true
  fi
  rm -rf "${STAGE}"
}
trap cleanup EXIT

while (($#)); do
  case "$1" in
    --interface) INTERFACE="${2:-}"; shift 2 ;;
    --local-cidr) LOCAL_CIDR="${2:-}"; shift 2 ;;
    --peer-ip) PEER_IP="${2:-}"; shift 2 ;;
    --peer-public-key) PEER_PUBLIC_KEY="${2:-}"; shift 2 ;;
    --exit-endpoint) EXIT_ENDPOINT="${2:-}"; shift 2 ;;
    --tunnel-port) TUNNEL_PORT="${2:-}"; shift 2 ;;
    --proxy-port) PROXY_PORT="${2:-}"; shift 2 ;;
    --entry-ipv4) ENTRY_IPV4="${2:-}"; shift 2 ;;
    --entry-ipv6) ENTRY_IPV6="${2:-}"; shift 2 ;;
    --exit-ipv4) EXIT_IPV4="${2:-}"; shift 2 ;;
    --name) NAME="${2:-}"; shift 2 ;;
    --via-name) VIA_NAME="${2:-}"; shift 2 ;;
    --output) OUTPUT="${2:-}"; shift 2 ;;
    --unit-dir) UNIT_DIR="${2:-}"; shift 2 ;;
    --credential-dir) CREDENTIAL_DIR="${2:-}"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [[ "${EUID}" -ne 0 ]]; then echo "Run as root." >&2; exit 1; fi
[[ "${INTERFACE}" =~ ^[a-z0-9][a-z0-9_-]{0,14}$ ]] || { echo "A valid WireGuard interface is required." >&2; exit 2; }
for address in "${PEER_IP}" "${EXIT_ENDPOINT}" "${ENTRY_IPV4}" "${EXIT_IPV4}"; do
  [[ "${address}" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || { echo "A required IPv4 address is invalid." >&2; exit 2; }
done
if [[ -n "${ENTRY_IPV6}" && ! "${ENTRY_IPV6}" =~ ^[0-9A-Fa-f:]+$ ]]; then echo "Invalid entry IPv6 address." >&2; exit 2; fi
[[ "${LOCAL_CIDR}" =~ ^[0-9.]+/[0-9]{1,2}$ ]] || { echo "A valid local tunnel CIDR is required." >&2; exit 2; }
[[ "${PEER_PUBLIC_KEY}" =~ ^[A-Za-z0-9+/]{43}=$ ]] || { echo "A valid peer public key is required." >&2; exit 2; }
for port in "${TUNNEL_PORT}" "${PROXY_PORT}"; do
  if [[ ! "${port}" =~ ^[0-9]{1,5}$ ]] || ((port < 1 || port > 65535)); then echo "A valid port is required." >&2; exit 2; fi
done
for label in "${NAME}" "${VIA_NAME}"; do
  [[ "${label}" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "A valid Route/entry name is required." >&2; exit 2; }
done
[[ -d "${UNIT_DIR}" ]] || { echo "Service unit directory is missing." >&2; exit 1; }
[[ -x "${HY_BIN}" ]] || { echo "Missing PPM-managed Hysteria2 binary." >&2; exit 1; }
for required in jq openssl wg wg-quick curl; do command -v "${required}" >/dev/null 2>&1 || { echo "Missing ${required}." >&2; exit 1; }; done

KEY_FILE="/etc/wireguard/${INTERFACE}.key"
[[ -s "${KEY_FILE}" ]] || { echo "WireGuard private key is missing." >&2; exit 1; }
ROUTE_METRIC=42760
if [[ "${INTERFACE}" =~ ^wg-ppm([0-9]{2})$ ]]; then ROUTE_METRIC=$((42760 + 10#${BASH_REMATCH[1]})); fi
cat >"${STAGE}/${INTERFACE}.conf" <<EOF
[Interface]
Address = ${LOCAL_CIDR}
PrivateKey = $(cat "${KEY_FILE}")
MTU = 1380
Table = off
PostUp = ip route del default dev %i metric ${ROUTE_METRIC} 2>/dev/null || true; ip route add default dev %i metric ${ROUTE_METRIC}
PostUp = sysctl -q -w net.ipv4.conf.%i.rp_filter=2
PostDown = ip route del default dev %i metric ${ROUTE_METRIC} 2>/dev/null || true

[Peer]
PublicKey = ${PEER_PUBLIC_KEY}
Endpoint = ${EXIT_ENDPOINT}:${TUNNEL_PORT}
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF
WG_RESTART_REQUIRED=0
cmp -s "${STAGE}/${INTERFACE}.conf" "/etc/wireguard/${INTERFACE}.conf" || WG_RESTART_REQUIRED=1
install -m 0600 -o root -g root "${STAGE}/${INTERFACE}.conf" "/etc/wireguard/${INTERFACE}.conf"
systemctl enable "wg-quick@${INTERFACE}.service" >/dev/null
if ! systemctl is-active --quiet "wg-quick@${INTERFACE}.service"; then
  systemctl start "wg-quick@${INTERFACE}.service"
elif [[ "${WG_RESTART_REQUIRED}" -eq 1 ]]; then
  systemctl restart "wg-quick@${INTERFACE}.service"
fi
if ! ping -4 -I "${INTERFACE}" -c 3 -W 3 "${PEER_IP}" >/dev/null; then
  echo "WireGuard peer is unreachable. Check the exit endpoint and UDP firewall." >&2
  exit 1
fi

STATE_DIR="/var/lib/private-proxy-manager/relays"
STATE_FILE="${STATE_DIR}/${NAME}.json"
HY_DIR="/etc/private-proxy-manager/hysteria/relays/${NAME}"
install -d -m 0700 -o root -g root "${STATE_DIR}" "$(dirname "${OUTPUT}")"
install -d -m 0750 -o ppm-hysteria -g ppm-hysteria "${HY_DIR}" /var/lib/private-proxy-manager/hysteria

load_state() {
  [[ -s "${STATE_FILE}" ]] || return 1
  jq -e '.schema == 1 and .hysteria.auth and .hysteria.obfs' "${STATE_FILE}" >/dev/null
  HY_AUTH="$(jq -r '.hysteria.auth' "${STATE_FILE}")"
  HY_OBFS="$(jq -r '.hysteria.obfs' "${STATE_FILE}")"
}

if [[ -n "${CREDENTIAL_DIR}" ]]; then
  [[ -s "${CREDENTIAL_DIR}/credentials.json" && -s "${CREDENTIAL_DIR}/server.crt" && -s "${CREDENTIAL_DIR}/server.key" ]] || { echo "Managed relay credential bundle is incomplete." >&2; exit 2; }
  HY_AUTH="$(jq -er '.hysteria.auth' "${CREDENTIAL_DIR}/credentials.json")"
  HY_OBFS="$(jq -er '.hysteria.obfs' "${CREDENTIAL_DIR}/credentials.json")"
  if load_state && [[ "$(jq -r '.hysteria.auth' "${STATE_FILE}")" != "${HY_AUTH}" || "$(jq -r '.hysteria.obfs' "${STATE_FILE}")" != "${HY_OBFS}" ]]; then
    echo "Managed relay credentials do not match existing state; use the explicit overlapping rotation workflow." >&2
    exit 1
  fi
elif ! load_state; then
  HY_AUTH="$(openssl rand -hex 32)"
  HY_OBFS="$(openssl rand -hex 32)"
fi
for secret in HY_AUTH HY_OBFS; do
  [[ -n "${!secret:-}" && "${!secret}" != "null" ]] || { echo "Relay credential generation failed." >&2; exit 1; }
done
jq -n --arg auth "${HY_AUTH}" --arg obfs "${HY_OBFS}" '{schema:1,hysteria:{auth:$auth,obfs:$obfs}}' >"${STAGE}/credentials.json"

if [[ -n "${CREDENTIAL_DIR}" ]]; then
  openssl x509 -in "${CREDENTIAL_DIR}/server.crt" -checkend 0 -noout >/dev/null || { echo "Managed relay certificate is expired." >&2; exit 1; }
  openssl x509 -in "${CREDENTIAL_DIR}/server.crt" -checkip "${ENTRY_IPV4}" -noout >/dev/null || { echo "Managed relay certificate does not match the entry address." >&2; exit 1; }
  if [[ -n "${ENTRY_IPV6}" ]]; then openssl x509 -in "${CREDENTIAL_DIR}/server.crt" -checkip "${ENTRY_IPV6}" -noout >/dev/null || { echo "Managed relay certificate does not match the entry IPv6." >&2; exit 1; }; fi
  if [[ -s "${HY_DIR}/server.crt" ]] && [[ "$(openssl x509 -in "${HY_DIR}/server.crt" -noout -fingerprint -sha256)" != "$(openssl x509 -in "${CREDENTIAL_DIR}/server.crt" -noout -fingerprint -sha256)" ]]; then
    echo "Managed relay certificate does not match existing state; use the explicit overlapping rotation workflow." >&2
    exit 1
  fi
  cp "${CREDENTIAL_DIR}/server.crt" "${STAGE}/server.crt"
  cp "${CREDENTIAL_DIR}/server.key" "${STAGE}/server.key"
elif [[ -s "${HY_DIR}/server.crt" && -s "${HY_DIR}/server.key" ]]; then
  openssl x509 -in "${HY_DIR}/server.crt" -checkend 0 -noout >/dev/null || { echo "Existing relay certificate is expired; use the explicit rotation workflow." >&2; exit 1; }
  openssl x509 -in "${HY_DIR}/server.crt" -checkip "${ENTRY_IPV4}" -noout >/dev/null || { echo "Existing relay certificate does not match the entry address." >&2; exit 1; }
  cp "${HY_DIR}/server.crt" "${STAGE}/server.crt"
  cp "${HY_DIR}/server.key" "${STAGE}/server.key"
else
  openssl ecparam -name prime256v1 -genkey -noout -out "${STAGE}/server.key"
  openssl req -new -x509 -sha256 -key "${STAGE}/server.key" -out "${STAGE}/server.crt" -days 3650 -subj "/CN=${ENTRY_IPV4}" -addext "subjectAltName=IP:${ENTRY_IPV4}" -addext "keyUsage=critical,digitalSignature,keyEncipherment" -addext "extendedKeyUsage=serverAuth"
fi
CERT_FINGERPRINT="$(openssl x509 -in "${STAGE}/server.crt" -noout -fingerprint -sha256 | cut -d= -f2)"

cat >"${STAGE}/hysteria-stage.yaml" <<EOF
listen: :0
tls:
  cert: ${STAGE}/server.crt
  key: ${STAGE}/server.key
  sniGuard: disable
obfs:
  type: salamander
  salamander:
    password: ${HY_OBFS}
auth:
  type: password
  password: ${HY_AUTH}
congestion:
  type: bbr
  bbrProfile: standard
speedTest: false
disableUDP: false
outbounds:
  - name: relay-via-wireguard
    type: direct
    direct:
      mode: 4
      bindDevice: ${INTERFACE}
      fastOpen: false
acl:
  inline:
    - reject(all, tcp/25)
    - reject(all, tcp/465)
    - reject(all, tcp/587)
    - reject(0.0.0.0/8)
    - reject(10.0.0.0/8)
    - reject(100.64.0.0/10)
    - reject(127.0.0.0/8)
    - reject(169.254.0.0/16)
    - reject(172.16.0.0/12)
    - reject(192.168.0.0/16)
    - reject(198.18.0.0/15)
    - reject(224.0.0.0/4)
    - reject(240.0.0.0/4)
    - reject(::/128)
    - reject(::1/128)
    - reject(fc00::/7)
    - reject(fe80::/10)
    - reject(ff00::/8)
masquerade:
  type: string
  string:
    content: Not Found
    statusCode: 404
    headers:
      content-type: text/plain; charset=utf-8
EOF
sed "s/^listen: :0$/listen: :${PROXY_PORT}/; s#cert: .*/server.crt#cert: ${HY_DIR}/server.crt#; s#key: .*/server.key#key: ${HY_DIR}/server.key#" "${STAGE}/hysteria-stage.yaml" >"${STAGE}/hysteria.yaml"

"${HY_BIN}" --disable-update-check --log-level warn server -c "${STAGE}/hysteria-stage.yaml" >"${STAGE}/hysteria.log" 2>&1 &
HY_PID=$!
sleep 2
if ! kill -0 "${HY_PID}" 2>/dev/null; then
  echo "Hysteria2 relay staged validation failed." >&2
  sed -E 's/(password: )[[:graph:]]+/\1[redacted]/g' "${STAGE}/hysteria.log" >&2
  exit 1
fi
kill -TERM "${HY_PID}"
wait "${HY_PID}" 2>/dev/null || true
HY_PID=""

RESTART_REQUIRED=0
cmp -s "${STAGE}/hysteria.yaml" "${HY_DIR}/config.yaml" || RESTART_REQUIRED=1
cmp -s "${STAGE}/server.key" "${HY_DIR}/server.key" || RESTART_REQUIRED=1
cmp -s "${STAGE}/server.crt" "${HY_DIR}/server.crt" || RESTART_REQUIRED=1
install -m 0640 -o ppm-hysteria -g ppm-hysteria "${STAGE}/hysteria.yaml" "${HY_DIR}/config.yaml"
install -m 0600 -o ppm-hysteria -g ppm-hysteria "${STAGE}/server.key" "${HY_DIR}/server.key"
install -m 0644 -o ppm-hysteria -g ppm-hysteria "${STAGE}/server.crt" "${HY_DIR}/server.crt"
install -m 0600 -o root -g root "${STAGE}/credentials.json" "${STATE_FILE}"
install -m 0644 "${UNIT_DIR}/private-proxy-manager-relay@.service" /etc/systemd/system/private-proxy-manager-relay@.service
DROP_IN="/etc/systemd/system/private-proxy-manager-relay@${NAME}.service.d"
install -d -m 0755 "${DROP_IN}"
cat >"${DROP_IN}/10-wireguard.conf" <<EOF
[Unit]
After=wg-quick@${INTERFACE}.service
Requires=wg-quick@${INTERFACE}.service
EOF

write_node() {
  local suffix="$1" address="$2"
  cat <<EOF
  - name: ${NAME}-HY2-${suffix}
    type: hysteria2
    server: '${address}'
    port: ${PROXY_PORT}
    password: '${HY_AUTH}'
    sni: '${ENTRY_IPV4}'
    skip-cert-verify: true
    fingerprint: '${CERT_FINGERPRINT}'
    alpn: [h3]
    obfs: salamander
    obfs-password: '${HY_OBFS}'
EOF
}
{
  printf '%s\n' 'schema: 1' "name: '${NAME}'" "kind: 'relay'" "via: '${VIA_NAME}'" "ipv4: '${EXIT_IPV4}'" "entry_ipv4: '${ENTRY_IPV4}'"
  [[ -z "${ENTRY_IPV6}" ]] || printf '%s\n' "entry_ipv6: '${ENTRY_IPV6}'"
  printf '%s\n' 'proxies:'
  [[ -z "${ENTRY_IPV6}" ]] || write_node v6 "${ENTRY_IPV6}"
  write_node v4 "${ENTRY_IPV4}"
} >"${STAGE}/client-payload.yaml"
install -m 0600 -o root -g root "${STAGE}/client-payload.yaml" "${OUTPUT}"

ufw --force delete allow "${PROXY_PORT}/tcp" >/dev/null 2>&1 || true
ufw allow "${PROXY_PORT}/udp" comment "PPM ${NAME} Hysteria2" >/dev/null
systemctl daemon-reload
systemctl enable "private-proxy-manager-relay@${NAME}.service" >/dev/null
if ! systemctl is-active --quiet "private-proxy-manager-relay@${NAME}.service"; then
  systemctl start "private-proxy-manager-relay@${NAME}.service"
elif [[ "${RESTART_REQUIRED}" -eq 1 ]]; then
  systemctl restart "private-proxy-manager-relay@${NAME}.service"
fi
systemctl is-active --quiet "private-proxy-manager-relay@${NAME}.service"

echo "RELAY_ENTRY_CONFIGURED=1"
echo "RELAY_WIREGUARD_RESTARTED=${WG_RESTART_REQUIRED}"
echo "RELAY_HYSTERIA_RESTARTED=${RESTART_REQUIRED}"
echo "RELAY_CLIENT_PAYLOAD=${OUTPUT}"
