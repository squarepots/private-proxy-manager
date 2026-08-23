# Privacy boundary

PPM separates product source, local private state, the chosen AI runtime, remote servers, and optional Cloudflare delivery. These layers are not interchangeable.

## What stays local by product design

The deterministic engine reads and writes the selected private directory. Inventory, credentials, Provider URLs, subscription state, generated client files, observed evidence, and recovery archives are not part of the tracked source tree. The engine has no product telemetry or hosted PPM database.

## What the AI runtime may receive

The runtime that operates PPM may send prompts and tool arguments to its model provider. Depending on the operation, that can include server addresses, SSH usernames, local key paths, and stable Route/Profile/ClientTarget IDs. Returned machine results avoid internal absolute paths and raw diagnostics, but the operation still needs enough context to act.

Use an offline model/runtime when the model provider must not receive those arguments. A private Git repository or ignored local directory is not the same as encryption or an offline runtime.

## Local protection

Private state is plaintext by default. Protect the directory with operating-system permissions, encrypted disks where appropriate, controlled backups, and careful chat/log handling. Encrypted recovery archives are portable backups, not a replacement for key rotation after compromise.

Never place real addresses, credentials, subscription URLs/tokens, SSH material, generated client files, recovery archives, or private state in public issues. Use synthetic reproductions for ordinary bug reports.

## Remote visibility

SSH/VPS providers see the network and account metadata inherent to their role. An optional Cloudflare subscription Worker can see request metadata such as source IP, time, and User-Agent. Destination services see the exit IP and normal application-layer metadata. PPM does not promise anonymity or invisibility.
