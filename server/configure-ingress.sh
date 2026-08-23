#!/usr/bin/env bash
set -Eeuo pipefail

umask 077

STATIC_V4=""
STATIC_V6=""
NAME="RST-Route"
INGRESS_PORT="443"
OUTPUT="/var/lib/route-steward/client-payload.yaml"
ROTATE=0
CREDENTIAL_DIR=""
STATE_DIR="/var/lib/route-steward"
STATE_FILE="${STATE_DIR}/credentials.json"
HY_DIR="/etc/route-steward/hysteria"
HY_BIN="/usr/local/lib/route-steward/hysteria"
STAGE="$(mktemp -d /run/route-steward.XXXXXX)"
HY_PID=""

usage() {
  cat <<'EOF'
Usage: configure-ingress.sh --ipv4 ADDRESS [options]

Options:
  --ipv6 ADDRESS          Optional public IPv6 address.
  --name NAME             Safe node prefix (default: RST-Route).
  --port PORT             HY2 UDP listener (default: 443).
  --output PATH           Root-only client payload output path.
  --credential-dir PATH   Optional locally generated canonical credential bundle.
  --rotate                Generate new Hysteria2 credentials.
EOF
}

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
    --ipv4) STATIC_V4="${2:-}"; shift 2 ;;
    --ipv6) STATIC_V6="${2:-}"; shift 2 ;;
    --name) NAME="${2:-}"; shift 2 ;;
    --port) INGRESS_PORT="${2:-}"; shift 2 ;;
    --output) OUTPUT="${2:-}"; shift 2 ;;
    --credential-dir) CREDENTIAL_DIR="${2:-}"; shift 2 ;;
    --rotate) ROTATE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ "${EUID}" -ne 0 ]]; then echo "Run as root." >&2; exit 1; fi
[[ "${STATIC_V4}" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || { echo "--ipv4 must be an IPv4 address." >&2; exit 2; }
if [[ -n "${STATIC_V6}" && ! "${STATIC_V6}" =~ ^[0-9A-Fa-f:]+$ ]]; then echo "--ipv6 must be an IPv6 address." >&2; exit 2; fi
[[ "${NAME}" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "Invalid node name." >&2; exit 2; }
if [[ ! "${INGRESS_PORT}" =~ ^[0-9]{1,5}$ ]] || ((INGRESS_PORT < 1 || INGRESS_PORT > 65535)); then
  echo "Invalid HY2 port." >&2
  exit 2
fi
[[ -x "${HY_BIN}" ]] || { echo "Missing RST-managed Hysteria2 binary." >&2; exit 1; }
for required in jq openssl; do command -v "${required}" >/dev/null 2>&1 || { echo "Missing ${required}." >&2; exit 1; }; done

install -d -m 0700 -o root -g root "${STATE_DIR}" "$(dirname "${OUTPUT}")"
install -d -m 0750 -o route-steward-hysteria -g route-steward-hysteria "${HY_DIR}" "${HY_DIR}/tls" /var/lib/route-steward/hysteria

load_state() {
  [[ -s "${STATE_FILE}" ]] || return 1
  jq -e '.schema == 1 and .hysteria.auth and .hysteria.obfs' "${STATE_FILE}" >/dev/null
  HY_AUTH="$(jq -r '.hysteria.auth' "${STATE_FILE}")"
  HY_OBFS="$(jq -r '.hysteria.obfs' "${STATE_FILE}")"
}

import_existing_config() {
  [[ -s "${HY_DIR}/config.yaml" ]] || return 1
  HY_AUTH="$(awk '/^auth:/{f=1;next} f && /^[^ ]/{f=0} f && $1=="password:"{print $2; exit}' "${HY_DIR}/config.yaml")"
  HY_OBFS="$(awk '/^[[:space:]]+salamander:/{f=1;next} f && /^[[:space:]]{0,2}[^ ]/{f=0} f && $1=="password:"{print $2; exit}' "${HY_DIR}/config.yaml")"
  [[ -n "${HY_AUTH}" && -n "${HY_OBFS}" ]]
}

generate_state() {
  HY_AUTH="$(openssl rand -hex 32)"
  HY_OBFS="$(openssl rand -hex 32)"
}

if [[ -n "${CREDENTIAL_DIR}" ]]; then
  [[ "${ROTATE}" -eq 0 ]] || { echo "Managed credentials cannot be combined with --rotate." >&2; exit 2; }
  [[ -s "${CREDENTIAL_DIR}/credentials.json" && -s "${CREDENTIAL_DIR}/server.crt" && -s "${CREDENTIAL_DIR}/server.key" ]] || { echo "Managed credential bundle is incomplete." >&2; exit 2; }
  HY_AUTH="$(jq -er '.hysteria.auth' "${CREDENTIAL_DIR}/credentials.json")"
  HY_OBFS="$(jq -er '.hysteria.obfs' "${CREDENTIAL_DIR}/credentials.json")"
  if load_state && [[ "$(jq -r '.hysteria.auth' "${STATE_FILE}")" != "${HY_AUTH}" || "$(jq -r '.hysteria.obfs' "${STATE_FILE}")" != "${HY_OBFS}" ]]; then
    echo "Managed credentials do not match existing server state; use the explicit overlapping rotation workflow." >&2
    exit 1
  fi
  echo "CREDENTIALS=managed-local"
elif [[ "${ROTATE}" -eq 0 ]] && load_state; then
  echo "CREDENTIALS=preserved"
elif [[ "${ROTATE}" -eq 0 ]] && import_existing_config; then
  echo "CREDENTIALS=imported-existing"
else
  generate_state
  echo "CREDENTIALS=generated"
fi
for secret in HY_AUTH HY_OBFS; do
  [[ -n "${!secret:-}" && "${!secret}" != "null" ]] || { echo "Missing Hysteria2 credential." >&2; exit 1; }
done
jq -n --arg auth "${HY_AUTH}" --arg obfs "${HY_OBFS}" '{schema:1,hysteria:{auth:$auth,obfs:$obfs}}' >"${STAGE}/credentials.json"

make_certificate() {
  local san="IP:${STATIC_V4}"
  [[ -z "${STATIC_V6}" ]] || san+=",IP:${STATIC_V6}"
  openssl ecparam -name prime256v1 -genkey -noout -out "${STAGE}/server.key"
  openssl req -new -x509 -sha256 -key "${STAGE}/server.key" -out "${STAGE}/server.crt" \
    -days 3650 -subj "/CN=${STATIC_V4}" -addext "subjectAltName=${san}" \
    -addext "keyUsage=critical,digitalSignature,keyEncipherment" -addext "extendedKeyUsage=serverAuth"
}

CERT_CHANGED=0
if [[ -n "${CREDENTIAL_DIR}" ]]; then
  openssl x509 -checkend 0 -noout -in "${CREDENTIAL_DIR}/server.crt" >/dev/null 2>&1 || { echo "Managed certificate is expired." >&2; exit 1; }
  openssl x509 -in "${CREDENTIAL_DIR}/server.crt" -checkip "${STATIC_V4}" -noout >/dev/null 2>&1 || { echo "Managed certificate does not match the static IPv4." >&2; exit 1; }
  if [[ -n "${STATIC_V6}" ]]; then openssl x509 -in "${CREDENTIAL_DIR}/server.crt" -checkip "${STATIC_V6}" -noout >/dev/null 2>&1 || { echo "Managed certificate does not match the public IPv6." >&2; exit 1; }; fi
  if [[ -s "${HY_DIR}/tls/server.crt" ]] && [[ "$(openssl x509 -in "${HY_DIR}/tls/server.crt" -noout -fingerprint -sha256)" != "$(openssl x509 -in "${CREDENTIAL_DIR}/server.crt" -noout -fingerprint -sha256)" ]]; then
    echo "Managed certificate does not match existing server state; use the explicit overlapping rotation workflow." >&2; exit 1
  fi
  install -m 0600 "${CREDENTIAL_DIR}/server.key" "${STAGE}/server.key"
  install -m 0644 "${CREDENTIAL_DIR}/server.crt" "${STAGE}/server.crt"
  echo "CERTIFICATE=managed-local"
elif [[ "${ROTATE}" -eq 0 && -s "${HY_DIR}/tls/server.crt" && -s "${HY_DIR}/tls/server.key" ]]; then
  openssl x509 -checkend 0 -noout -in "${HY_DIR}/tls/server.crt" >/dev/null 2>&1 || { echo "Existing certificate is expired; use the explicit rotation workflow." >&2; exit 1; }
  openssl x509 -in "${HY_DIR}/tls/server.crt" -checkip "${STATIC_V4}" -noout >/dev/null 2>&1 || { echo "Existing certificate does not match the static IPv4." >&2; exit 1; }
  if [[ -n "${STATIC_V6}" ]]; then openssl x509 -in "${HY_DIR}/tls/server.crt" -checkip "${STATIC_V6}" -noout >/dev/null 2>&1 || { echo "Existing certificate does not match the public IPv6." >&2; exit 1; }; fi
  install -m 0600 "${HY_DIR}/tls/server.key" "${STAGE}/server.key"
  install -m 0644 "${HY_DIR}/tls/server.crt" "${STAGE}/server.crt"
  echo "CERTIFICATE=preserved"
else
  make_certificate
  CERT_CHANGED=1
  echo "CERTIFICATE=generated"
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
  - name: direct-v4
    type: direct
    direct:
      mode: 4
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
sed "s/^listen: :0$/listen: :${INGRESS_PORT}/; s#cert: .*/server.crt#cert: ${HY_DIR}/tls/server.crt#; s#key: .*/server.key#key: ${HY_DIR}/tls/server.key#" "${STAGE}/hysteria-stage.yaml" >"${STAGE}/hysteria.yaml"

"${HY_BIN}" --disable-update-check --log-level warn server -c "${STAGE}/hysteria-stage.yaml" >"${STAGE}/hysteria-validation.log" 2>&1 &
HY_PID=$!
sleep 2
if ! kill -0 "${HY_PID}" 2>/dev/null; then
  echo "Hysteria2 staged validation failed." >&2
  sed -E 's/(password: )[[:graph:]]+/\1[redacted]/g' "${STAGE}/hysteria-validation.log" >&2
  exit 1
fi
kill -TERM "${HY_PID}"
wait "${HY_PID}" 2>/dev/null || true
HY_PID=""

RESTART_REQUIRED=0
cmp -s "${STAGE}/hysteria.yaml" "${HY_DIR}/config.yaml" || RESTART_REQUIRED=1
cmp -s "${STAGE}/server.key" "${HY_DIR}/tls/server.key" || RESTART_REQUIRED=1
cmp -s "${STAGE}/server.crt" "${HY_DIR}/tls/server.crt" || RESTART_REQUIRED=1
install -m 0640 -o route-steward-hysteria -g route-steward-hysteria "${STAGE}/hysteria.yaml" "${HY_DIR}/config.yaml"
install -m 0600 -o route-steward-hysteria -g route-steward-hysteria "${STAGE}/server.key" "${HY_DIR}/tls/server.key"
install -m 0644 -o route-steward-hysteria -g route-steward-hysteria "${STAGE}/server.crt" "${HY_DIR}/tls/server.crt"
install -m 0600 -o root -g root "${STAGE}/credentials.json" "${STATE_FILE}"

write_node() {
  local suffix="$1" address="$2"
  cat <<EOF
  - name: ${NAME}-HY2-${suffix}
    type: hysteria2
    server: '${address}'
    port: ${INGRESS_PORT}
    password: '${HY_AUTH}'
    sni: '${STATIC_V4}'
    skip-cert-verify: true
    fingerprint: '${CERT_FINGERPRINT}'
    alpn: [h3]
    obfs: salamander
    obfs-password: '${HY_OBFS}'
EOF
}
{
  printf '%s\n' 'schema: 1' "name: '${NAME}'" "ipv4: '${STATIC_V4}'"
  [[ -z "${STATIC_V6}" ]] || printf '%s\n' "ipv6: '${STATIC_V6}'"
  printf '%s\n' 'proxies:'
  [[ -z "${STATIC_V6}" ]] || write_node v6 "${STATIC_V6}"
  write_node v4 "${STATIC_V4}"
} >"${STAGE}/client-payload.yaml"
install -m 0600 -o root -g root "${STAGE}/client-payload.yaml" "${OUTPUT}"

ufw --force delete allow "${INGRESS_PORT}/tcp" >/dev/null 2>&1 || true
ufw allow "${INGRESS_PORT}/udp" comment "RST ${NAME} Hysteria2" >/dev/null
systemctl daemon-reload
systemctl enable route-steward-hysteria.service >/dev/null
if ! systemctl is-active --quiet route-steward-hysteria.service; then
  systemctl start route-steward-hysteria.service
elif [[ "${RESTART_REQUIRED}" -eq 1 ]]; then
  systemctl restart route-steward-hysteria.service
fi
systemctl is-active --quiet route-steward-hysteria.service

echo "CONFIGURATION_VALIDATED=1"
echo "CREDENTIAL_ROTATED=${ROTATE}"
echo "CERTIFICATE_CHANGED=${CERT_CHANGED}"
echo "HYSTERIA_RESTARTED=${RESTART_REQUIRED}"
echo "CLIENT_PAYLOAD=${OUTPUT}"
