# Compatibility

This page lists the capability set implemented and tested by the current release. The machine-readable response from `route-steward capabilities` is the runtime source of truth. Anything absent from both surfaces is outside the current support contract.

## Host and compute

| Capability | Supported contract |
| --- | --- |
| Compute | Bring-your-own server over SSH |
| Operating system | Ubuntu 24.04 |
| Architecture | amd64 |
| Ownership | Dedicated, rebuildable host with `compute.host_ownership=dedicated` |
| SSH identity | Valid Unix username and local private-key path |

Initial setup changes host-wide UFW, swap/fstab, SMTP egress, SSH/sysctl/journald, package, unattended-upgrades, and vnstat state. Uninstall removes RST-owned resources and named policy files; it leaves unknown prior global settings, installed packages, and swap in place.

## Network topology

| Capability | Supported contract |
| --- | --- |
| Ingress | Hysteria2, with the server binary version and SHA-256 pinned in deployment code |
| Direct Route | Client → Hysteria2 Server → declared exit |
| Relay Route | Client → Hysteria2 entry → one WireGuard Link → exit/NAT |
| Link | Single-hop WireGuard over an isolated RST interface/port/subnet |
| Address families | Hysteria2 client ingress supports IPv4 and IPv6; the relay Link uses IPv4 |
| Optional port hopping | One `port_hopping` range of 2–8 consecutive UDP ports, starting at the Route listener; requires the server's nftables or iptables helper and opens that exact UFW range |

## Desired state

Inventory schema `1` is the persisted desired-state contract:

- Server with `compute.driver=byo-ssh`;
- Link with `driver=wireguard`;
- Route with `ingress.driver=hysteria2`;
- optional Provider with `source_type=mihomo-http`;
- Profile for reusable Route, Provider, and explicit China/service routing selection;
- ClientTarget for renderer and delivery identity.

Product SemVer in `version.txt` is independent from inventory schema compatibility. Recovery accepts schema 1 and resets disposable observed evidence.

Migration checkpoints use a separate private schema-1 file. Recovery preserves them and forces remote/client revalidation; no migration evidence is treated as current merely because it was archived.

Clean bootstrap creates a valid neutral inventory, empty secret index, and empty observed state. It waits for actual user context before creating Profiles or ClientTargets.

## Clients and rendering

| Capability | Supported contract |
| --- | --- |
| Mihomo | Private YAML output for Mihomo/Clash Verge-compatible clients, with explicit `GLOBAL`/emergency selection, Provider `use` composition, Profile service routing, and optional target-scoped `PROCESS-NAME` routing; compatibility baseline Mihomo 1.19.27 |
| Karing | Private Clash YAML imported from a local file; compatibility baseline 1.2.23.2606; Windows, macOS, Linux, iOS, Android, and tvOS |
| Shadowrocket offline | Private node-import HTML generated without external page resources |
| Shadowrocket subscription | Optional isolated Cloudflare Worker delivery for one ClientTarget |
| Hysteria2 headless | Private official-client JSON plus foreground loopback HTTP/SOCKS5 runtime for one selected Route |
| Profile routing | `routing.china_direct` plus `openai` and `youtube` service bindings to enabled included Route IDs |

A ClientTarget selects the renderer and delivery. Its referenced Profile selects Routes, optional Providers, and explicit routing. A schema-1 Profile without `routing` remains readable through the legacy fallback: `balanced-cn` means China-direct rules, while `privacy` or blank means no China-direct rules. An explicit routing object is authoritative.

The shared Mihomo/Karing YAML leaves TUN, system-proxy, auto-route, strict-route, interface detection, and DNS-hijack ownership to the client. RST does not expose an externally reachable DNS listener. Mihomo receives an explicit `GLOBAL` selector listing managed Route nodes, `DIRECT`, `REJECT`, and included Provider sets; it does not depend on the core's implicit built-in GLOBAL expansion. Provider nodes nested under `Private Routes` remain available there, and the explicit `GLOBAL` `use` entries make them direct emergency choices instead of making their absence from a client's built-in GLOBAL view look like data loss. The final rule is always `MATCH,Private Routes`.

The Mihomo renderer may also carry `mihomo_process_names` on the ClientTarget. Values are limited to plain executable/package names and are not accepted on Profiles or other renderers. When present, rendering sets Mihomo's process matching mode to `strict`, creates an `Applications` select group with `DIRECT` and `Private Routes`, and emits `PROCESS-NAME` rules after private-address direct rules and before Profile service/China rules. Sanitized context reports only process-name counts; concrete process names remain private.

The `karing` renderer reuses the deterministic Clash YAML contract rather than maintaining a divergent approximation. Rendering fails unless every managed Hysteria2 node retains `skip-cert-verify: true`, Hysteria2 ALPN, salamander obfuscation, and a valid SHA-256 certificate fingerprint. Import the resulting `.yaml` with Karing's local Clash-file flow; no field editing is part of the supported setup. See the [client research record](CLIENT-RESEARCH.md) for the selection evidence and rejected candidates.

A `hysteria2` ClientTarget additionally selects exactly one enabled Route from its Profile, a loopback listener, and `auto`, `ipv4`, or `ipv6` ingress. `auto` prefers IPv4 and falls back to IPv6. This renderer does not compose Profile Providers or GUI policy rules. Multiple concurrently running targets need distinct local ports.

When a Route has `port_hopping`, its canonical payload keeps `port` at the range start and adds `ports`. Mihomo and Karing receive that Clash field, Shadowrocket receives the standard multi-port Hysteria URI authority, and the headless official-client JSON uses the range plus Hysteria's fixed interoperable 30-second hop interval. The range is deliberately limited to 2–8 ports so its firewall exposure and diagnostics remain bounded. The historical [reliability research record](RELIABILITY-RESEARCH.md) explains the source evidence and rejected candidates; capability discovery remains the current support truth.

## Providers

The optional `mihomo-http` Provider accepts an HTTP or HTTPS source URL stored in local secret storage. RST remains fully usable with zero Providers.

## Agent interfaces

| Interface | Supported contract |
| --- | --- |
| Repository Skill | Canonical model-neutral operating instructions |
| `route-steward` | Native sanitized JSON CLI for Linux, macOS, and Windows on amd64/arm64 |
| `route-steward mcp` | In-process local stdio MCP over the same Go engine |
| `agent/route-steward-agent.ps1` | Compatibility forwarder for older callers |
| AI runtime | Any capable runtime that can read the repository and invoke the local machine surface without changing core behavior |

## Audit, drift, migration, and recovery

Read-only Route audit and sanitized desired-versus-observed drift cover RST service/configuration, firewall/network, WireGuard, Hysteria2 listener/certificate, egress, ClientTarget render, and undetermined state.

Persisted `migrate-route` transactions support direct Route replacement and replacement of either endpoint of a relay Route. They reuse BYO SSH deployment, WireGuard Links, end-to-end health, ClientTarget rendering, and existing Shadowrocket subscription publication. A relay-exit replacement of a hopping Route uses a same-width non-overlapping range while both paths are live, then switches client output only after health succeeds. Old external capacity is preserved; cloud provisioning and destructive provider retirement remain outside this supported workflow.

On-demand `health` supports both direct and relay Routes. It runs the SHA-256-pinned official Hysteria2 client version reported by `route-steward capabilities` from a private local cache and checks the real client handshake, Internet access, DNS through a hostname request, declared exit identity, IPv4, optional declared IPv6, and request latency. Relay results also include the bounded WireGuard audit. For a hopping Route, audit verifies the configured range, firewall range, scoped service capability drop-in, and desired configuration hash; health starts a real client configured with that range. It is still a point-in-time traffic test, not proof that every later periodic hop succeeds. Health uses ipify's address-family endpoints and Cloudflare's `/cdn-cgi/trace` endpoint; it is not continuous monitoring. Exact public IPs are omitted unless explicitly requested. Packet loss is currently reported as unsupported because no stable safe metric is implemented.

`route-steward proxy` uses the same verified Hysteria2 cache and generated private JSON. `--check` starts the target temporarily, makes a real HTTP request through its loopback proxy, compares the observed IPv4 exit with the selected Route, omits the address from output, and stops. Run mode stays in the foreground so the operator's service manager owns restart policy. Public/LAN listeners, automatic multi-Route failover, Provider composition, and service installation are outside this renderer contract.

Migration uses an overlap-first workflow composed from add, deploy, audit, and render operations. Encrypted recovery verifies the archive manifest and path safety, relocates SSH material, validates schema-1 state, resets observed evidence, and performs no remote mutation by itself.

## Optional Cloudflare delivery

The Worker delivers a token-protected Shadowrocket subscription body for one isolated ClientTarget. The body is checked as UTF-8 and must be no larger than 5120 bytes. Subscription-token rotation is target-scoped, requires explicit current approval, and leaves Route and other ClientTarget credentials unchanged.
