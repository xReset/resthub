# resthub

Public, code-only distribution for R3ST Hub. The maintained sources are mirrored from the Potassium development repository.

## Load in Potassium

```lua
loadstring(httpget("https://raw.githubusercontent.com/xReset/resthub/main/loader.lua"), "=resthub")()
```

The loader fetches a release manifest, downloads executable files from its immutable 40-character commit revision, verifies SHA-256 hashes, compiles the complete release before updating cache, and loads only the module matching the current Roblox universe/place. Release `2026-10-28.1` includes every module in the canonical Hub registry (30 games), the shared runtime, UI, logger and Anims. The exact game identities, files and hashes live in [`manifest.json`](manifest.json), generated from the canonical registry rather than a separate hand-maintained game list.

This includes Backseat Rally's saved 1–3x downforce/gravity control, the latest Clover controls and performance fixes, and RoChess solvers. Gravity defaults to stock 1x; live jump handling is not certified. Existing gameplay and server-acceptance limits remain unchanged.

Loader v6 verifies the shared runtime and logger for fresh installs before Hub startup and prevents a matching place from overriding a foreign universe. This release requires v6 so an older cached loader cannot skip the runtime. Gates and mocked lifecycle tests do not certify combat, active-harvest input priority, rewards or server acceptance.

## Diagnostics

Manual **Send report** keeps `logs/r3st_report_last.txt` locally. Sending requires a private HTTPS destination supplied locally through `getgenv().__R3ST_REPORT_URL`; no report endpoint is included in public source.

Remote diagnostics are disabled by default. A friend must explicitly create `resthub_telemetry.json` in their Potassium workspace:

```json
{"optIn":true,"endpoint":"https://PRIVATE-ENDPOINT.example/upload","installId":"RANDOM-NONIDENTIFYING-ID"}
```

The endpoint is intentionally not included in git. Telemetry continuously ships structured session/build/capability data and incremental allowlisted R3ST log tails through a bounded local retry queue. It does not send Roblox usernames. MCP agents can inspect and emit evidence through `getgenv().__RESTHUB_TELEMETRY`; see [`docs/TELEMETRY.md`](docs/TELEMETRY.md).

## Maintenance

Do not edit mirrored Luau here first. Update and ship the canonical Potassium source, then run `tools/sync-from-potassium.ps1`. Agents must read `AGENTS.md` and `.agents/skills/resthub-maintainer/SKILL.md` before changing distribution files.

A canonical Git push alone does **not** update the public loadstring. A Hub delivery must also sync this distribution, gate it, commit the executable state, pin the manifest to that commit, push both repositories, and verify the remote hashes. Sync automatically includes all canonical registry modules and the shared runtime, so new registry rows cannot be silently left out. Publishing does not reload an already-running client.
