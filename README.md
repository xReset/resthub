# resthub

Public, code-only distribution for R3ST Hub. The maintained sources are mirrored from the Potassium development repository.

## Load in Potassium

```lua
loadstring(httpget("https://raw.githubusercontent.com/xReset/resthub/main/loader.lua"), "=resthub")()
```

The loader fetches a release manifest, downloads executable files from its immutable 40-character commit revision, verifies SHA-256 hashes, compiles the complete release before updating cache, and loads only the module matching the current Roblox universe/place. Current game modules:

- Blue Lock Rivals (`blr_hub.lua`)
- Ghost Driver (`gd2.lua`)

## Diagnostics

Remote diagnostics are disabled by default. A friend must explicitly create `resthub_telemetry.json` in their Potassium workspace:

```json
{"optIn":true,"endpoint":"https://PRIVATE-ENDPOINT.example/upload","installId":"RANDOM-NONIDENTIFYING-ID"}
```

The endpoint is intentionally not included in git. Telemetry continuously ships structured session/build/capability data and incremental allowlisted R3ST log tails through a bounded local retry queue. It does not send Roblox usernames. MCP agents can inspect and emit evidence through `getgenv().__RESTHUB_TELEMETRY`; see [`docs/TELEMETRY.md`](docs/TELEMETRY.md).

## Maintenance

Do not edit mirrored Luau here first. Update and ship the canonical Potassium source, then run `tools/sync-from-potassium.ps1`. Agents must read `AGENTS.md` and `.agents/skills/resthub-maintainer/SKILL.md` before changing distribution files.
