# Privacy boundary

This document describes what Route Steward, the chosen AI runtime, remote servers, and optional Cloudflare delivery can see.

## What stays local by product design

The Go engine reads and writes the selected private directory. Inventory, credentials, Provider URLs, subscription state, generated client files, observed evidence, and recovery archives stay outside the tracked source tree. Route Steward has no product telemetry or hosted database.

## What the AI runtime may receive

The runtime that operates RST may send prompts and tool arguments to its model provider. Depending on the operation, that can include server addresses, SSH usernames, local key paths, and stable Route/Profile/ClientTarget IDs. Migration checkpoints retain the supplied replacement Server context inside the selected private directory so an interrupted workflow can resume. Returned machine results avoid addresses, internal absolute paths, and raw diagnostics, but the operation still needs enough context to act.

Use an offline model or runtime when the model provider must not receive those arguments. Private Git storage and ignored files do not prevent a cloud model from receiving tool inputs.

## Local protection

Private state is plaintext by default. Protect the directory with operating-system permissions, encrypted disks where appropriate, controlled backups, and careful chat/log handling. Encrypted recovery archives are portable backups. Rotate exposed credentials after a compromise.

Never place real addresses, credentials, subscription URLs/tokens, SSH material, generated client files, recovery archives, or private state in public issues. Use synthetic reproductions for ordinary bug reports.

## Remote visibility

SSH/VPS providers see the network and account metadata inherent to their role. An optional Cloudflare subscription Worker can see request metadata such as source IP, time, and User-Agent. An on-demand `health` check sends small requests through the managed proxy to ipify's IPv4/IPv6 address endpoints and Cloudflare's `/cdn-cgi/trace` endpoint; headless `proxy --check` contacts the ipify IPv4 endpoint. Those services see the Route's exit IP and request metadata. Destination services see the exit IP and normal application-layer metadata. Route Steward provides no anonymity guarantee.

Health stores bounded status, time, latency, and match results in the local private observed state. Exact public IP values are omitted from normal agent output and are returned only when the operator explicitly requests them.

## Profile routing values

Profile routing match values are desired state. Sanitized context may return their domain suffix, geosite, or geoip values to the operating AI runtime so it can inspect and modify routing intent. Credentials, Provider URLs, server addresses, and generated client secrets remain excluded by the existing sanitization boundary.
