# resthub

Public, code-only distribution for R3ST Hub. The maintained sources are mirrored from the Potassium development repository.

## Load in Potassium

```lua
loadstring(httpget("https://raw.githubusercontent.com/xReset/resthub/main/loader.lua"), "=resthub")()
```

The loader fetches a release manifest, downloads executable files from its immutable 40-character commit revision, verifies SHA-256 hashes, compiles the complete release before updating cache, and loads only the module matching the current Roblox universe/place. Current game modules:

- A Bizarre Day : Classic (`abd_item_esp.lua`) — dropped-item ESP, including Banknotes
- Blue Lock Rivals (`blr_hub.lua`)
- Ghost Driver (`gd2.lua`)
- Dungeon Quest Reborn (`dqr_hub.lua`)
- WideOpen (`wideopen_hub.lua`) — bike tuning, contact guard, W + Space wheelie limiter, player names/distance
- Clover RPG (`clover_hub.lua`) — build `2026-10-26.28`, gathering/professions, quests/map, manual town travel, broom controls and experimental PvE/PvP auto-parry
- Bike Universe (`bike_universe_hub.lua`) — saved bike tuning, stunts and local crash guards
- Backseat Rally (`backseat_rally_hub.lua`) — bike tuning, camera, sound and restorable local controls

Release `2026-10-26.1` publishes the current shared Studio UI, Hub `2026-10-26.13-public`, Anims, Clover `.28`, Bike Universe and Backseat Rally, alongside the existing modules. Clover includes 110 captured attack-marker profiles, one native parry pulse per hit, replay/multi-hit rearming and nested PvE detection. Native cooldowns, manual ownership and unblockable attacks still apply; every-hit success is not certified. Broom server cooldown bypass, native town arrival and hymn completion remain unverified. Saved automation choices resume, including parry, mining, harvest, armor, chest loot and manual broom debounce; missing choices stay OFF. Harvest steering leases only the active minigame's native mouse/touch aim listeners, preserving unrelated input and native cancel/smoothing. Three supported Clover remounts preserve saved choices; active harvesting mouse priority still needs player confirmation.

Loader v5 verifies the shared logger for fresh installs before Hub startup and prevents a matching place from overriding a foreign universe. Gates and mocked lifecycle tests do not certify combat, active-harvest input priority, rewards or server acceptance.

## Diagnostics

Manual **Send report** keeps `logs/r3st_report_last.txt` locally. Sending requires a private HTTPS destination supplied locally through `getgenv().__R3ST_REPORT_URL`; no report endpoint is included in public source.

Remote diagnostics are disabled by default. A friend must explicitly create `resthub_telemetry.json` in their Potassium workspace:

```json
{"optIn":true,"endpoint":"https://PRIVATE-ENDPOINT.example/upload","installId":"RANDOM-NONIDENTIFYING-ID"}
```

The endpoint is intentionally not included in git. Telemetry continuously ships structured session/build/capability data and incremental allowlisted R3ST log tails through a bounded local retry queue. It does not send Roblox usernames. MCP agents can inspect and emit evidence through `getgenv().__RESTHUB_TELEMETRY`; see [`docs/TELEMETRY.md`](docs/TELEMETRY.md).

## Maintenance

Do not edit mirrored Luau here first. Update and ship the canonical Potassium source, then run `tools/sync-from-potassium.ps1`. Agents must read `AGENTS.md` and `.agents/skills/resthub-maintainer/SKILL.md` before changing distribution files.
