# R3ST telemetry contract

Telemetry is the shared diagnostic plane for local MCP agents, repository agents, and remote support. The public repository contains only the client and schema. The endpoint, ingest credentials, stored events, and friend enrollment records remain private.

## Consent and identity

Telemetry does nothing unless `%LOCALAPPDATA%\Potassium\workspace\resthub_telemetry.json` contains `"optIn": true`. `installId` is a random support identifier supplied during enrollment. Roblox usernames, user IDs, chat, hardware IDs, cookies, and credentials are never collected. `JobId` is excluded unless `includeJobId` is explicitly true.

```json
{
  "optIn": true,
  "endpoint": "https://private-ingest.example/v1/events",
  "ingestKey": "private-per-installation-key",
  "installId": "friend-random-identifier",
  "intervalSeconds": 30,
  "includeJobId": false
}
```

This file is ignored and must never be committed or pasted into agent context.

## Event envelope

Every uploaded batch is `{schema, client, telemetryVersion, events}`. Every event carries:

- `eventId`, `sessionId`, `installId`, `timestamp`
- `kind`, `source`, `severity`
- `context.gameId`, `context.placeId`, executor name/version
- active Hub/module build stamps and loader release/revision
- event-specific `data`

Core kinds:

- `session.start`, `session.heartbeat`
- `log.delta` for incremental allowlisted file logs
- `script.error`, `script.decision`, `script.lifecycle`
- `agent.note`, `agent.probe`, `agent.verification`

## Local MCP/LLM interface

An MCP-connected agent can inspect the live client without console output:

```lua
local T = getgenv().__RESTHUB_TELEMETRY
return T and T.status()
```

Force collection/upload:

```lua
local T = getgenv().__RESTHUB_TELEMETRY
if T then T.collect(); return T.flush() end
```

Record structured evidence:

```lua
local T = getgenv().__RESTHUB_TELEMETRY
if T then
    T.emit("agent.verification", "blr", {
        build = "2026-08-31.24",
        check = "shot profile restored",
        result = "pass"
    }, "info")
end
```

Agents should emit evidence, not conclusions without evidence. Never put secrets, raw tokens, usernames, or unbounded dumps into an event.

## Reliability

The client tails only allowlisted logs, tracks byte offsets, detects truncation, redacts common credentials, caps each delta, queues events locally, retries failed batches, and never blocks Hub startup. Queue/state files remain in the local Potassium workspace.

## Private service requirements

The ingestion service must authenticate each installation separately, rate-limit, cap request size, deduplicate by `eventId`, timestamp receipt, encrypt storage, support revocation, and expose read-only filtered queries for agents. Do not use Discord webhooks or GitHub tokens in distributed Luau.
