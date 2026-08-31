# Resthub repository gate

**Before any work, read `.agents/skills/resthub-maintainer/SKILL.md` completely.** It owns security, canonical-source sync, loader invariants, telemetry, validation, and publishing.

Non-negotiable:

1. This repo is public. Never read or commit secrets, private endpoints, enrollment data, user logs, identifiers, `.env`, `.mcp.json`, or telemetry service state.
2. Mirrored Hub/game Luau is changed in the canonical Potassium repo first, shipped there, then synced here. Never patch only the mirror.
3. Releases use an immutable full commit SHA plus SHA-256 file pins. Game routing is universe-first and foreign modules are never fetched.
4. Telemetry is opt-in and non-identifying. Private ingestion/query infrastructure stays outside git.
5. Before done, run `powershell -File tools/gate.ps1`. A failed gate means nothing ships.
