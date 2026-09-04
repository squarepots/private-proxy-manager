# Synthetic examples

Files in this directory describe the public object model with reserved example addresses and placeholder secret references. They contain no live endpoints, credentials, subscription URLs, SSH paths, or generated client payloads.

`inventory.example.json` is an **architecture example, not a ready-to-deploy private proxy configuration**. Real RST state is created by the agent-guided bootstrap and stored under ignored local `private/`, where secret references resolve to owner-only files.

The example demonstrates the final separation between:

- Server / Link / Route infrastructure objects, including an optional 2–8-port hopping range;
- optional Provider sources;
- reusable Profile selections;
- renderer-specific ClientTargets.

Never replace the placeholders in this tracked example with real private values. Put real values only in local ignored state.
