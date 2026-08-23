# FAQ

## Is PPM a VPN service?

No. PPM manages supported self-hosted infrastructure and renders client configuration. Mihomo/Clash-compatible clients or Shadowrocket carry traffic.

## Can I use a shared server?

Not with the current contract. The supported baseline is a dedicated, rebuildable Ubuntu 24.04 amd64 host because setup changes host-wide UFW, swap/fstab, SSH, sysctl, journald, package, and unattended-upgrade state.

## Does PPM buy a VPS or delete one for me?

No. Cloud purchasing and destructive server retirement are outside the current deterministic core and require explicit external decisions.

## Does PPM connect my bank or move money?

No. PPM is a proxy infrastructure tool. It does not provide a hosted control plane, billing, traffic analytics, or account management.

## Will an AI model see my server details?

Possibly. The chosen AI runtime may see tool arguments required for an operation, including an IP, SSH username, local key path, and selected IDs. PPM sanitizes returned artifacts, but local-first is not a promise that a cloud model sees zero metadata. Use an offline runtime for a fully local model boundary.

## Are private files encrypted?

Not by default. Private state is local plaintext protected by your operating-system permissions, backup policy, and recovery handling. Encrypted recovery archives are available for portable backup.

## Does PPM promise anonymity?

No. Network providers, VPS providers, optional Cloudflare delivery, and destination services retain the metadata visible to their roles.

## What happens if a route drifts?

PPM reports typed evidence. It does not silently self-heal or overwrite an uncertain remote state. A repair must map to a supported operation, pass preflight, and match the user's authority.

## Which operating systems and clients are supported?

See [Compatibility](COMPATIBILITY.md). The initial baseline is Ubuntu 24.04 amd64, Hysteria2, single-hop WireGuard, Mihomo/Clash-compatible output, and Shadowrocket output. External documentation does not add support automatically.

## What does the subscription Worker do?

It is an optional private configuration-delivery endpoint for one Shadowrocket ClientTarget. It is not a PPM database or proxy data plane. The current Worker secret payload has a 5120-byte UTF-8 limit; larger payloads fail locally before publication.
