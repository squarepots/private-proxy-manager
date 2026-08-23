# External research

Use web/browser research when the answer depends on current external facts that RST does not own.

High-value cases:

- VPS provider regions, prices, products, UDP/IPv6 support, and current purchase requirements;
- cloud/provider firewall or network configuration documentation;
- current proxy-client import/config/protocol support;
- current Cloudflare/Wrangler behavior for the optional subscription Worker;
- current protocol/client interoperability needed to diagnose a user request.

Prefer official/provider documentation for compatibility and operational facts. Community sources can supplement experience reports but are not capability truth.

## Boundary

Research may help the agent recommend or plan. It does not authorize:

- purchasing a VPS or paid service;
- creating/terminating external resources;
- changing unrelated account configuration;
- credential rotation;
- a destructive migration step;
- claiming RST supports a protocol/client/provider integration that the repository does not implement.

Map research findings back to `capabilities` and a scoped preflight before execution.

## No browser available

If the runtime cannot browse, use the repository's local capability metadata for what RST supports and ask for the smallest missing current fact. Do not invent prices, client support, provider procedures, or cloud requirements.
