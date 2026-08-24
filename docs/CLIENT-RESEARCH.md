# Client research record

Research date: 2026-08-24. This record explains the first expansion beyond the existing Mihomo/Clash Verge-compatible, Shadowrocket, and headless Hysteria2 contracts. Current application facts come from the named projects' official repositories and documentation; Route Steward support still requires an implemented renderer and tests.

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
