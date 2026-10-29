# resthub

Public, code-only distribution for R3ST Hub. The maintained sources are mirrored from the Potassium development repository.

## Load in Potassium

```lua
loadstring(httpget("https://raw.githubusercontent.com/xReset/resthub/main/loader.lua"), "=resthub")()
```

The loader fetches a release manifest, downloads executable files from its immutable 40-character commit revision, verifies SHA-256 hashes, compiles the complete release before updating cache, and loads only the module matching the current Roblox universe/place. Release `2026-10-29.1` includes every module in the canonical Hub registry (31 games), the shared runtime, UI, logger and Anims. The exact game identities, files and hashes live in [`manifest.json`](manifest.json), generated from the canonical registry rather than a separate hand-maintained game list.

This includes Vantage, the current Hub teleport handoff/notifications, current Bike Universe controls, and privacy-hardened reports/catalogs. Backseat Rally's saved 1–3x downforce/gravity control, Clover controls and RoChess solvers remain included. Gravity defaults to stock 1x; live jump handling is not certified. Offline tests and disk hashes do not prove gameplay or server acceptance.

Loader v6 verifies the shared runtime and logger for fresh installs before Hub startup and prevents a matching place from overriding a foreign universe. This release requires v6 so an older cached loader cannot skip the runtime. Gates and mocked lifecycle tests do not certify combat, active-harvest input priority, rewards or server acceptance.

## Diagnostics

Manual **Send report** keeps `logs/r3st_report_last.txt` locally and sends only bounded build metadata and public game/place IDs. It never sends raw logs, notes, player identity or executor fingerprints. Sending requires a private HTTPS destination supplied locally through `getgenv().__R3ST_REPORT_URL`; no endpoint is included in public source.

Remote diagnostics are disabled by default. Telemetry v3 requires an explicitly opted-in local config, random installation UUID and per-install ingest key. It accepts only typed metadata/enums, never raw logs or free-form/nested event data. Old queues are left untouched and never replayed. The receiver still sees network IPs and random support IDs, so this is not anonymity.

The private service must support schema 3 before uploads work; publication does not upgrade that service or authorize live uploads. MCP agents can inspect safe status and emit typed evidence through `getgenv().__RESTHUB_TELEMETRY`; see [`docs/TELEMETRY.md`](docs/TELEMETRY.md) for the contract and synthetic configuration example.

## Maintenance

Do not edit mirrored Luau here first. Update and ship the canonical Potassium source, then run `tools/sync-from-potassium.ps1`. Agents must read `AGENTS.md` and `.agents/skills/resthub-maintainer/SKILL.md` before changing distribution files.

A canonical Git push alone does **not** update the public loadstring. A Hub delivery must also sync this distribution, gate it, commit the executable state, pin the manifest to that commit, push both repositories, and verify the remote hashes. Sync automatically includes all canonical registry modules and the shared runtime, so new registry rows cannot be silently left out. Publishing does not reload an already-running client.
