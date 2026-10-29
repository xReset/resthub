# R3ST telemetry contract

Telemetry v3 is optional, **metadata-only** support transport. The public repo
contains the client/schema, not the endpoint, credentials, enrollment records or
stored events. This contract applies whether or not the Hub is sold.

## Consent and privacy

Nothing runs without an ignored local `resthub_telemetry.json` containing explicit
`optIn: true`, an HTTPS destination, a per-install random UUID and ingest key.
Never read or paste a real config, queue or enrollment record into agent context.
Use synthetic fixtures when developing the client.

The client never collects raw logs, free-form notes, Roblox names/UserIds, chat,
HWIDs, cookies, personal paths, executor fingerprints or JobId. Old `includeJobId`
settings are ignored. The receiver necessarily sees the network IP address;
random support/session IDs still permit correlation, so this is not anonymity.

Synthetic configuration example (not credentials or a real destination):

```json
{
  "optIn": true,
  "endpoint": "https://ingest.example/v3/events",
  "ingestKey": "synthetic-key-for-tests-only",
  "installId": "11111111-1111-4111-8111-111111111111",
  "intervalSeconds": 30
}
```

The destination must have no userinfo, query, fragment, control characters or
non-default port. Missing/invalid config disables telemetry without blocking Hub.
No hardcoded private receiver is distributed.

## Schema 3

Batches carry `{schema: 3, client, telemetryVersion, events}`. Each event contains
freshly built context and only these envelope fields:

- random `eventId`, `sessionId`, enrolled `installId`, numeric `timestamp`
- allowlisted `kind`, `source`, `severity`
- public numeric game/place IDs, known module build constants
- typed, allowlisted `data`; never an arbitrary nested object

Kinds: `session.start`, `session.heartbeat`, `script.error`, `script.decision`,
`script.lifecycle`, `agent.note`, `agent.probe`, `agent.verification`.
Sources: `telemetry`, `hub`, `resthub-loader`, `resthub`, `blr`, `ghost-driver`,
`agent`, `module`. Severity: `info`, `debug`, `warn`, `error`.

Allowed data fields (at most six):

| Field | Allowed values |
|---|---|
| `check` | `compile`, `restore`, `lifecycle`, `readiness`, `hash`, `privacy`, `network`, `performance` |
| `result` | `pass`, `fail`, `unverified`, `skipped` |
| `action` | `mount`, `unmount`, `reload`, `start`, `stop`, `skip`, `restore` |
| `code` | `compile`, `runtime`, `teardown`, `config`, `network`, `unknown` |
| `count` | Integer 0–1,000,000 |
| `queued` | Integer 0–150 |

Unknown fields, raw strings, nested data and unsupported enum values reject the
whole event. No regex redaction promise substitutes for the positive allowlist.
Do not encode private data into otherwise valid metadata fields.

## Local interface

`getgenv().__RESTHUB_TELEMETRY` exposes `status`, `snapshot`, `emit`, `flush`,
`collect`, `destroy`. `status` excludes destination and support/session identity.
`collect()` is a compatibility stub: it returns false and never reads logs.

With session authorization, exact structured verification can use:

```lua
local T = getgenv().__RESTHUB_TELEMETRY
if T then
    return T.emit("agent.verification", "agent", {
        check = "privacy", result = "pass"
    }, "info")
end
```

Only emit evidence actually measured. An enqueue result does not prove upload or
successful gameplay. Unsupported older free-form events now return false.

## Queue, lifecycle and service compatibility

The client reads/writes only `resthub_telemetry_queue_v3.json`. Old queue/state files
are left untouched, never replayed or deleted. Saved v3 entries are schema-checked
and reconstructed with fresh context; persisted context and unknown fields are
never copied into a batch. A different installation's events are not restored.

Queue/batch caps are 150/24 events and 64 KiB per request. Uploads honor the local
interval even when callers manually flush, reject concurrent sends, and retry
failures. Request exceptions/response bodies are not exposed in status. Stopped
instances cannot overwrite a replacement's queue or handle.

**The private service must accept schema 3 before uploads can work.** No service
upgrade, credentials or live upload is part of publishing this client. An older
service may reject batches; that never blocks Hub startup. Keep support data
private, authenticate each install, support revocation, deduplicate `eventId`,
rate-limit, bound requests/retention and encrypt storage.

## Checks

Run `python -m unittest discover -s tests -v` and `powershell -File tools/gate.ps1`.
Tests run actual Luau under offline mocks and synthetic configs only. The gate
also scans the actual manifest payloads for known privacy patterns. Pattern PASS
is not a whole-history, supply-chain or live-runtime security certification.
