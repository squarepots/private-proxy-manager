# Client research record

Research date: 2026-08-24. This historical decision record explains the first expansion beyond the existing Mihomo/Clash Verge-compatible, Shadowrocket, and headless Hysteria2 contracts. The current support contract remains `route-steward capabilities` and `docs/COMPATIBILITY.md`; external client facts still require fresh authoritative sources when they can change.

## Coverage before this change

The existing GUI contracts covered desktop Mihomo/Clash clients and Shadowrocket, while the official Hysteria2 renderer covered servers, scripts, and CI. The meaningful gap was a first-class Android client and one tested GUI import path spanning Windows, macOS, Linux, iOS, and Android.

## Selected: Karing

Karing 1.2.23.2606 is the compatibility baseline. It was the current release during research, its repository remained active, and its official platform list covers Windows, macOS, Linux, iOS, Android, and tvOS. Karing documents full Clash configuration support, exposes a local YAML file-import flow, and its official Hysteria2 example defines `fingerprint` as the SHA-256 certificate fingerprint used for SSL pinning.

Route Steward therefore adds a `karing` ClientTarget that emits the same deterministic private Clash YAML contract as the Mihomo renderer. The separate renderer identity records the selected app and adds a fail-closed Karing check for the certificate pin, self-signed TLS setting, ALPN, and salamander obfuscation. Users import the generated `.yaml` as a local Clash profile; manual field editing is outside the supported flow.

Validation is deterministic fixture/structure testing plus the existing local Clash-core check when a compatible core is available. Route Steward does not automate or bundle the Karing GUI, and the compatibility baseline is stated explicitly so future format changes can be reassessed.

Primary evidence:

- [Karing release 1.2.23.2606](https://github.com/KaringX/karing/releases/tag/v1.2.23.2606)
- [Karing supported platforms and Clash configuration contract](https://github.com/KaringX/karing/blob/v1.2.23.2606/README.md)
- [Karing local configuration file import](https://github.com/KaringX/karing/blob/v1.2.23.2606/lib/screens/add_profile_by_import_from_file_screen.dart)
- [Karing Hysteria2 and SHA-256 certificate-pinning example](https://github.com/KaringX/karing/blob/v1.2.23.2606/README_examples/clash/config.yaml)

## Not selected in this tranche

- Hiddify is active and multi-platform, but its official Hysteria2 URL conversion test does not preserve `pinSHA256` in the generated outbound. Supporting the simple URI import would weaken Route Steward's managed self-signed TLS identity. A separate full Sing-box renderer was not added as an untested workaround. Evidence: [Hiddify URL scheme](https://github.com/hiddify/hiddify.com/blob/9fc39756405e1f7665ce11488f3f80bdcb911ff6/docs/app/URL-Scheme.md) and [official Hysteria2 conversion test](https://github.com/hiddify/ray2sing/blob/caf5e9ac03eaba54dc339319670748d32a073a39/ray2sing_test/hysteria2_test.go).
- v2rayN supports Hysteria2 subscriptions but does not close the iOS/Android platform gap, and its current certificate-validation semantics are still changing. It remains protocol-compatible, not Route Steward-supported. Evidence: [official subscription formats](https://github.com/2dust/v2rayN/wiki/Description-of-subscription) and [current Hysteria2 subscription regression](https://github.com/2dust/v2rayN/issues/9985).

Adding either client later requires a complete import artifact that preserves certificate identity plus an app-specific maintained validation contract.

## Mihomo process-name routing

Research date: 2026-08-28.

The selected behavior is a Mihomo-only ClientTarget feature for app- or game-specific routing in Clash Verge-compatible clients. The reusable Profile continues to select Routes, Providers, and policy; concrete process names are target-specific local client behavior and remain private.

Mihomo's official route-rule documentation lists `PROCESS-NAME` as a rule type and states that route rules are matched from top to bottom by priority. Its general configuration documents `find-process-mode: strict` as the default process matching mode, and the TUN documentation covers process/package-related routing inputs. RST therefore renders plain `PROCESS-NAME` rules, sets `find-process-mode: strict`, and places those rules after private-address direct rules but before geography rules so LAN/private destinations stay direct while selected processes can be manually routed through either `DIRECT` or the selected Profile route.

RST intentionally does not expose process paths, wildcards, regular expressions, or app-specific hard-coded defaults. Process names are limited to plain executable/package names, are accepted only on Mihomo ClientTargets, and appear in sanitized context only as counts.

Primary evidence:

- [Mihomo route rules and `PROCESS-NAME`](https://wiki.metacubex.one/en/config/rules/)
- [Mihomo process matching mode](https://wiki.metacubex.one/en/config/general/#process-matching-mode)
- [Mihomo TUN configuration](https://wiki.metacubex.one/en/config/inbound/tun/)
