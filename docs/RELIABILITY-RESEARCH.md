# Reliability research

Research date: 2026-08-24. This historical decision record explains the reliability choices made for the 1.6.0 work. The current support contract remains `route-steward capabilities` and `docs/COMPATIBILITY.md`. This record is not the runtime source of truth.

## Decision

Route Steward 1.6.0 adds optional Hysteria2 port hopping and updates the pinned official Hysteria server/client to 2.12.2.

Port hopping is appropriate for persistent throttling or filtering of individual UDP destination ports. Hysteria documents that it does not help when UDP is blocked as a whole. RST accepts exactly one consecutive range of 2–8 UDP ports, such as `20000-20003`; the range must begin at `listen_port`. The small bound keeps firewall exposure, collision detection, and incident diagnostics understandable.

The canonical route state, firewall rule, remote Hysteria listener, scoped systemd capability drop-in, audit hash, private payload, headless configuration, and migration checkpoint carry the selected range. During a relay-exit replacement, the unchanged entry temporarily needs both paths, so the replacement reserves a same-width non-overlapping range and the health-gated client switch publishes it only after it works. Deployment uses Hysteria's Linux packet-filter helper and therefore requires `nft` or `iptables`; base setup installs `nftables`. A hopping Route opens only its exact UFW UDP range and grants `CAP_NET_ADMIN` only to that RST service unit.

## One client contract

The supported output is deliberately the common feature set rather than a renderer-specific approximation:

| Client path | Port-hopping output |
| --- | --- |
| Mihomo | Clash `ports` field |
| Karing | The same tested Clash YAML contract |
| Shadowrocket node/subscription | Standard Hysteria multi-port URI authority |
| Official headless client | Multi-port `server` plus the interoperable fixed `30s` UDP hop interval |

RST does not expose a random or arbitrary hop interval. Mihomo can express one, but the standard Hysteria URI cannot, so adding it would create a setting that Shadowrocket cannot receive or verify through the same contract.

Audit verifies the desired range, remote listener configuration, UFW range, capability drop-in, and configuration hash. `health` and `proxy --check` start an actual official client configured with the advertised range and verify traffic through it. They are point-in-time checks: they do not claim to observe every later periodic hop or measure packet loss.

## Features considered and not added

| Candidate | Decision | Reason |
| --- | --- | --- |
| Port hopping | Implemented | The official server/client format and all four supported Route Steward client paths close end to end. |
| Hysteria 2.12.2 | Implemented | Current official release at research time; pinned server/client binaries and hashes are updated together. |
| Existing salamander obfuscation | Retained | It is already part of the managed, pinned TLS client contract; this change does not introduce an unrendered alternate obfuscator. |
| Existing fixed 404 masquerade | Retained, not counted as a reliability control | It gives a predictable minimal HTTP response but is not an operator-controlled site mimic and does not improve loss, throttling, or UDP filtering. |
| Mimic | Rejected | It requires Linux/kernel or external-program setup, matching client configuration, and Hysteria documents that it cannot be combined with port hopping. That is not a complete current multi-client Route Steward lifecycle. |
| Gecko, ECH, Realms, or extra transport controls | Rejected | No complete, tested deployment, audit, migration, recovery, and four-client rendering path exists in RST for them. They are not exposed as partial knobs. |
| A real-site proxy masquerade | Rejected | It would require an operator-controlled external site/domain and ongoing content behavior outside the current dedicated-IP Route contract. The existing fixed 404 response remains a server behavior, not a reliability claim. |

## Sources

- [Hysteria port hopping](https://v2.hysteria.network/docs/advanced/Port-Hopping/) — scope, Linux packet-filter requirements, and per-port limitation.
- [Hysteria URI scheme](https://v2.hysteria.network/docs/developers/URI-Scheme/) — standard multi-port URI form and the absence of a standardized hop-interval query field.
- [Mihomo Hysteria2 proxy configuration](https://wiki.metacubex.one/en/config/proxies/hysteria2/) — `ports` and hop-interval support.
- [Karing Clash compatibility](https://karing.app/clash) — Hysteria2 port-hopping support in the current Karing compatibility path.
- [Hysteria Mimic](https://v2.hysteria.network/docs/advanced/Mimic/) — deployment restrictions and incompatibility with port hopping.
- [Hysteria 2.12.2 release](https://github.com/HyNetworks/hysteria/releases/tag/app/v2.12.2) — pinned release provenance.
