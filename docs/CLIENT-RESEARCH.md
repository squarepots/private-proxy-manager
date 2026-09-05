# Client research record

> **Superseded routing model (2026-09-05):** country- and service-specific Profile fields described below are historical research for the 1.x line. Current Profile routing uses ordered generic match/action rules; schema-1 state is translated for compatibility.

Research date: 2026-08-24. This record explains the selection of the first additional GUI client. Current support is listed by `route-steward capabilities` and `docs/COMPATIBILITY.md`.

## Coverage before this change

Existing outputs covered desktop Mihomo/Clash clients, Shadowrocket, and headless Hysteria2. The gap was an Android client with a tested import path across desktop and mobile platforms.

## Selected: Karing

Karing 1.2.23.2606 is the compatibility baseline. It was the current release during research, its repository remained active, and its official platform list covers Windows, macOS, Linux, iOS, Android, and tvOS. Karing documents full Clash configuration support, exposes a local YAML file-import flow, and its official Hysteria2 example defines `fingerprint` as the SHA-256 certificate fingerprint used for SSL pinning.

Route Steward therefore added a `karing` ClientTarget using the shared Clash YAML renderer. Karing output is checked for the certificate pin, self-signed TLS setting, ALPN, and salamander obfuscation. Users import the generated `.yaml` as a local Clash profile.

Validation uses fixture and structure tests plus a local Clash-core check when a compatible core is available. The documented version baseline makes later format changes reviewable.

Primary evidence:

- [Karing release 1.2.23.2606](https://github.com/KaringX/karing/releases/tag/v1.2.23.2606)
- [Karing supported platforms and Clash configuration](https://github.com/KaringX/karing/blob/v1.2.23.2606/README.md)
- [Karing local configuration file import](https://github.com/KaringX/karing/blob/v1.2.23.2606/lib/screens/add_profile_by_import_from_file_screen.dart)
- [Karing Hysteria2 and SHA-256 certificate-pinning example](https://github.com/KaringX/karing/blob/v1.2.23.2606/README_examples/clash/config.yaml)

## Other candidates

- Hiddify is active and multi-platform, but its official Hysteria2 URL conversion test drops `pinSHA256` from the generated outbound. That URI path did not meet the certificate-identity requirement. Evidence: [Hiddify URL scheme](https://github.com/hiddify/hiddify.com/blob/9fc39756405e1f7665ce11488f3f80bdcb911ff6/docs/app/URL-Scheme.md) and [official Hysteria2 conversion test](https://github.com/hiddify/ray2sing/blob/caf5e9ac03eaba54dc339319670748d32a073a39/ray2sing_test/hysteria2_test.go).
- v2rayN supports Hysteria2 subscriptions but did not cover the iOS/Android gap, and its certificate-validation behavior was changing. Evidence: [official subscription formats](https://github.com/2dust/v2rayN/wiki/Description-of-subscription) and [Hysteria2 subscription regression](https://github.com/2dust/v2rayN/issues/9985).

Either client can be reconsidered when Route Steward can generate and test an import artifact that preserves certificate identity.

## Mihomo process-name routing

Research date: 2026-08-28.

Process routing belongs to a Mihomo ClientTarget. Profiles remain reusable across targets, while concrete process names stay in private target state.

Mihomo documents `PROCESS-NAME`, top-to-bottom rule evaluation, and `find-process-mode: strict`. RST renders plain process rules after private-address direct rules and before Profile service and China rules. The generated `Applications` group offers `DIRECT` and `Private Routes`. Client applications control TUN and DNS capture.

RST accepts up to 32 plain executable or package names on Mihomo ClientTargets. Sanitized context reports only their count.

Primary evidence:

- [Mihomo route rules and `PROCESS-NAME`](https://wiki.metacubex.one/en/config/rules/)
- [Mihomo process matching mode](https://wiki.metacubex.one/en/config/general/#process-matching-mode)
- [Mihomo TUN configuration](https://wiki.metacubex.one/en/config/inbound/tun/)

## Profile service routing and explicit global selection

Research date: 2026-09-02. Mihomo supports `GEOSITE`, top-to-bottom rule evaluation, explicit proxy lists, and Provider `use` sets. RST uses them for `openai` and `youtube` Profile bindings, per-Route selectors, and a Mihomo `GLOBAL` group. Compatibility tests use Mihomo 1.19.27 supplied by the test environment and exercise Provider refresh through the selector.

Primary evidence:

- [Mihomo rule configuration](https://wiki.metacubex.one/en/config/rules/)
- [Mihomo proxy groups](https://wiki.metacubex.one/en/config/proxy-groups/)
- [Mihomo built-in GLOBAL behavior](https://wiki.metacubex.one/en/config/proxy-groups/built-in/)
