---
name: resthub-maintainer
description: Mandatory gate for any resthub change: public-repo security, canonical sync, immutable loader releases, telemetry, validation, and publishing.
---

# Resthub maintainer

## 0. Stop conditions

This repo is public executable distribution. Stop if a diff contains credentials, private endpoints, enrollment maps, collected logs, usernames/IDs, `.env`, `.mcp.json`, or telemetry service state. Do not read secret files. Inspect staged content before every push.

## 1. Source ownership

Potassium is canonical; resthub is a generated distribution:

| Canonical | Mirror |
|---|---|
| `scripts/hub.lua` | `hub.lua` |
| `scripts/r3st_ui.lua` | `r3st_ui.lua` |
| `scripts/anims.lua` | `anims.lua` |
| `games/blue-lock-rivals/scripts/blr_hub.lua` | `games/blr_hub.lua` |
| `games/ghost-driver/scripts/gd2.lua` | `games/gd2.lua` |

For mirrored Luau: load Potassium's required skills, edit canonical source, pass `ship-luau`, then run `tools/sync-from-potassium.ps1`. Never fix only the mirror.

## 2. Loader invariants

- Stable one-line entry point fetches `loader.lua` from `main`.
- `main/manifest.json` is only a release pointer.
- Executables are fetched from `manifest.revision`, a full immutable commit SHA.
- Every executable has a SHA-256 pin; acquire and compile all mandatory files before cache writes or execution.
- Retry network failures; fallback only to cache matching the current hash.
- Match `game.GameId` before `game.PlaceId`; fetch only the matching game module.
- Bound response sizes and reject unsafe paths/schema/duplicate identity matches.
- Telemetry failure never blocks Hub startup.

## 3. Telemetry gate

Read `docs/TELEMETRY.md` before telemetry work. It is the common evidence plane for local MCP agents, repo agents, and remote friend support.

Required: explicit ignored local opt-in; HTTPS; per-install random UUID/auth;
metadata-only schema 3; build/game context; strict field/enum allowlists;
size/rate bounds; validated disk queue/retry; revocation; no Roblox identity.
Never upload raw logs, arbitrary nested data, free-form messages, executor
fingerprints or JobId. `collect()` is a non-reading compatibility stub. Old
queues are not replayed or deleted. Endpoint, credentials, stored events and
enrollment records stay private. A private service must support schema 3;
publishing the client does not authorize service changes or live uploads.

Live MCP loop:

```lua
local T=getgenv().__RESTHUB_TELEMETRY
return T and T.status()
```

Use `status()`/`snapshot()` for metadata. `collect()` never reads logs. For exact
checks, `emit("agent.verification", "agent", {check="privacy", result="pass"}, "info")`
uses only documented enums, never free-form evidence. Emit only measured facts.
Runtime inspection/upload still needs session authorization. Do not read private
telemetry configs, queues or enrollment files while developing this repo.

## 4. Immutable publish sequence

1. Sync and modify executable/docs/tool files.
2. Compile all Luau and review diff.
3. Commit executable state; record its full SHA as `REV`.
4. Run `tools/sync-from-potassium.ps1 -Revision $REV -Release <version>` to generate hashes/pointer without changing canonical content again.
5. Run `powershell -File tools/gate.ps1`.
6. Commit `manifest.json`, push both commits, then verify raw loader/manifest/revision URLs return HTTP 200.

Never set `manifest.revision` to the manifest commit: it points to the preceding executable-state commit.

## 5. Done

`tools/gate.ps1` passes; staged secret review is clean; immutable files/hashes match; commits are pushed; raw URLs respond; loader is tested in Potassium. If in-client testing is unavailable, say so—do not claim runtime success.
