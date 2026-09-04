# Reliability research

Research date: 2026-08-24. This record explains the reliability choices made for version 1.6.0. Current support is listed by `route-steward capabilities` and `docs/COMPATIBILITY.md`.

## Decision

Route Steward 1.6.0 adds optional Hysteria2 port hopping and updates the pinned official Hysteria server/client to 2.12.2.

Port hopping addresses persistent throttling or filtering of individual UDP destination ports. Hysteria documents that it cannot carry traffic when UDP is blocked as a whole. RST accepts one consecutive range of 2–8 UDP ports, such as `20000-20003`, beginning at `listen_port`. The limit keeps firewall exposure and collision checks manageable.

Inventory, the firewall rule, Hysteria listener, systemd capability file, audit hash, client payloads, and migration checkpoint carry the selected range. During a relay-exit replacement, the shared entry serves both paths, so the replacement reserves a same-width, non-overlapping range until the client switch. Deployment uses Hysteria's Linux packet-filter helper and requires `nft` or `iptables`; base setup installs `nftables`. A hopping Route opens its selected UFW range and grants `CAP_NET_ADMIN` to that service unit.

## Client output

Each renderer carries the same port range:

| Client path | Port-hopping output |
| --- | --- |
| Mihomo | Clash `ports` field |
| Karing | The same tested Clash YAML format |
| Shadowrocket node/subscription | Standard Hysteria multi-port URI authority |
| Official headless client | Multi-port `server` plus the interoperable fixed `30s` UDP hop interval |

The standard Hysteria URI has no hop-interval field, so RST uses the official client's 30-second interval across its generated output.

Audit verifies the selected range, remote listener, UFW rule, capability file, and configuration hash. `health` and `proxy --check` run the official client with that range and verify traffic. These checks run at one point in time and do not measure packet loss.

## Options considered

| Candidate | Decision | Reason |
| --- | --- | --- |
| Port hopping | Implemented | The official server/client format and all four supported Route Steward client paths close end to end. |
| Hysteria 2.12.2 | Implemented | Current official release at research time; pinned server/client binaries and hashes are updated together. |
| Existing salamander obfuscation | Retained | It was already present in every managed client output. |
| Existing fixed 404 response | Retained | It gives a predictable HTTP response but does not improve packet loss, throttling, or UDP filtering. |
| Mimic | Rejected | It conflicts with port hopping and requires additional Linux or external-program setup plus matching client configuration. |
| Gecko, ECH, Realms, or extra transport controls | Rejected | Each would require new deployment, audit, migration, recovery, and renderer support. |
| A real-site proxy masquerade | Rejected | It requires an external site or domain and continuing content management. |

## Sources

- [Hysteria port hopping](https://v2.hysteria.network/docs/advanced/Port-Hopping/) — scope, Linux packet-filter requirements, and per-port limitation.
- [Hysteria URI scheme](https://v2.hysteria.network/docs/developers/URI-Scheme/) — standard multi-port URI form and the absence of a standardized hop-interval query field.
- [Mihomo Hysteria2 proxy configuration](https://wiki.metacubex.one/en/config/proxies/hysteria2/) — `ports` and hop-interval support.
- [Karing Clash compatibility](https://karing.app/clash) — Hysteria2 port-hopping support in the current Karing compatibility path.
- [Hysteria Mimic](https://v2.hysteria.network/docs/advanced/Mimic/) — deployment restrictions and incompatibility with port hopping.
- [Hysteria 2.12.2 release](https://github.com/HyNetworks/hysteria/releases/tag/app/v2.12.2) — pinned release provenance.
