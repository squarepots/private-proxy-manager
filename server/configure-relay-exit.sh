#!/usr/bin/env bash
set -Eeuo pipefail

INTERFACE=""
LISTEN_PORT=""
LOCAL_CIDR=""
SUBNET=""
PEER_IP=""
PEER_PUBLIC_KEY=""
ENTRY_PUBLIC_IP=""

while (($#)); do
  case "$1" in
    --interface) INTERFACE="${2:-}"; shift 2 ;;
    --listen-port) LISTEN_PORT="${2:-}"; shift 2 ;;
    --local-cidr) LOCAL_CIDR="${2:-}"; shift 2 ;;
    --subnet) SUBNET="${2:-}"; shift 2 ;;
    --peer-ip) PEER_IP="${2:-}"; shift 2 ;;
    --peer-public-key) PEER_PUBLIC_KEY="${2:-}"; shift 2 ;;
    --entry-public-ip) ENTRY_PUBLIC_IP="${2:-}"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [[ "${EUID}" -ne 0 ]]; then echo "Run as root." >&2; exit 1; fi
[[ "${INTERFACE}" =~ ^[a-z0-9][a-z0-9_-]{0,14}$ ]] || { echo "A valid interface name is required." >&2; exit 2; }
if [[ ! "${LISTEN_PORT}" =~ ^[0-9]{1,5}$ ]] || ((LISTEN_PORT < 1 || LISTEN_PORT > 65535)); then echo "A valid WireGuard port is required." >&2; exit 2; fi
for address in "${PEER_IP}" "${ENTRY_PUBLIC_IP}"; do
  [[ "${address}" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || { echo "A required IPv4 address is invalid." >&2; exit 2; }
done
[[ "${LOCAL_CIDR}" =~ ^[0-9.]+/[0-9]{1,2}$ ]] || { echo "A valid local tunnel CIDR is required." >&2; exit 2; }
[[ "${SUBNET}" =~ ^10\.77\.[0-9]{1,3}\.0/30$ ]] || { echo "A valid tunnel subnet is required." >&2; exit 2; }
[[ "${PEER_PUBLIC_KEY}" =~ ^[A-Za-z0-9+/]{43}=$ ]] || { echo "A valid peer public key is required." >&2; exit 2; }

KEY_FILE="/etc/wireguard/${INTERFACE}.key"
[[ -s "${KEY_FILE}" ]] || { echo "WireGuard private key is missing." >&2; exit 1; }
DEFAULT_IF="$(ip -4 route show default | awk 'NR==1 {print $5}')"
[[ -n "${DEFAULT_IF}" ]] || { echo "Default IPv4 interface was not found." >&2; exit 1; }
STAGE="$(mktemp -d /run/route-steward-relay-exit.XXXXXX)"
trap 'rm -rf "${STAGE}"' EXIT

cat >"${STAGE}/${INTERFACE}.conf" <<EOF
[Interface]
Address = ${LOCAL_CIDR}
ListenPort = ${LISTEN_PORT}
PrivateKey = $(cat "${KEY_FILE}")
MTU = 1380
PostUp = iptables -t nat -C POSTROUTING -s ${SUBNET} -o ${DEFAULT_IF} -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -s ${SUBNET} -o ${DEFAULT_IF} -j MASQUERADE
PostUp = iptables -C FORWARD -i %i -o ${DEFAULT_IF} -j ACCEPT 2>/dev/null || iptables -I FORWARD 1 -i %i -o ${DEFAULT_IF} -j ACCEPT
PostUp = iptables -C FORWARD -i ${DEFAULT_IF} -o %i -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || iptables -I FORWARD 1 -i ${DEFAULT_IF} -o %i -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -s ${SUBNET} -o ${DEFAULT_IF} -j MASQUERADE 2>/dev/null || true
PostDown = iptables -D FORWARD -i %i -o ${DEFAULT_IF} -j ACCEPT 2>/dev/null || true
PostDown = iptables -D FORWARD -i ${DEFAULT_IF} -o %i -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true

[Peer]
PublicKey = ${PEER_PUBLIC_KEY}
AllowedIPs = ${PEER_IP}/32
EOF

cat >"${STAGE}/99-route-steward-relay.conf" <<'EOF'
net.ipv4.ip_forward=1
EOF

WG_RESTART_REQUIRED=0
cmp -s "${STAGE}/${INTERFACE}.conf" "/etc/wireguard/${INTERFACE}.conf" || WG_RESTART_REQUIRED=1
install -m 0600 -o root -g root "${STAGE}/${INTERFACE}.conf" "/etc/wireguard/${INTERFACE}.conf"
install -m 0644 -o root -g root "${STAGE}/99-route-steward-relay.conf" /etc/sysctl.d/99-route-steward-relay.conf
sysctl --system >/dev/null

ufw allow from "${ENTRY_PUBLIC_IP}" to any port "${LISTEN_PORT}" proto udp comment "RST ${INTERFACE} WireGuard" >/dev/null
ufw allow in on "${INTERFACE}" comment "RST ${INTERFACE} tunnel" >/dev/null
ufw deny out 25/tcp comment 'Block SMTP abuse' >/dev/null
ufw deny out 465/tcp comment 'Block SMTPS abuse' >/dev/null
ufw deny out 587/tcp comment 'Block submission abuse' >/dev/null
ufw --force enable >/dev/null

systemctl enable "wg-quick@${INTERFACE}.service" >/dev/null
if ! systemctl is-active --quiet "wg-quick@${INTERFACE}.service"; then
  systemctl start "wg-quick@${INTERFACE}.service"
elif [[ "${WG_RESTART_REQUIRED}" -eq 1 ]]; then
  systemctl restart "wg-quick@${INTERFACE}.service"
fi
systemctl is-active --quiet "wg-quick@${INTERFACE}.service"
echo "RELAY_EXIT_CONFIGURED=1"
echo "RELAY_WIREGUARD_RESTARTED=${WG_RESTART_REQUIRED}"
