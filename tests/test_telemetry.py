"""Run the actual telemetry client offline. All identifiers/configs are synthetic."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
LUAU = ROOT.parent / "Potassium/tools/luau.exe"
SOURCE = (ROOT / "telemetry.lua").read_text(encoding="utf-8")


class TelemetryTests(unittest.TestCase):
    def run_client(self, setup="", checks=""):
        driver = r'''
local objects, sent, reads, writes = {}, {}, {}, {}
local cfg = { optIn = true, endpoint = "https://ingest.example/v3/events",
    installId = "11111111-1111-4111-8111-111111111111", ingestKey = "synthetic-key-for-tests-only" }
local saved = {}
local G = { __R3ST_HUB = { build = "2026-10-29.3" } }
local clock, ids, onRequest, failRequest = 1000, 0, nil, false
local os = { clock = function() return clock end, time = function() return 1234567890 end }
local service = {}
function service:GenerateGUID()
    ids += 1
    return string.format("22222222-2222-4222-8222-%012d", ids)
end
function service:JSONDecode(raw)
    if raw == "config" then return cfg end
    if raw == "saved" then return saved end
    error("unexpected decode")
end
function service:JSONEncode(value)
    local token = "encoded-" .. tostring(#objects + 1)
    objects[#objects + 1] = value
    objects[token] = value
    return token
end
local game = { GameId = 123, PlaceId = 456, JobId = "PRIVATE_FIXTURE",
    Players = { LocalPlayer = { Name = "PRIVATE_FIXTURE", UserId = 987654321 } } }
function game:GetService(name) assert(name == "HttpService"); return service end
local function getgenv() return G end
local function identifyexecutor() error("executor identity must never be collected") end
local function readfile(path)
    reads[path] = true
    if path == "resthub_telemetry.json" then return "config" end
    if path == "resthub_telemetry_queue_v3.json" then return "saved" end
    error("unexpected private/log/old queue file read")
end
local function writefile(path, raw) writes[#writes + 1] = { path = path, value = objects[raw] } end
local function request(options)
    sent[#sent + 1] = { options = options, body = objects[options.Body] }
    if onRequest then onRequest() end
    if failRequest then error("PRIVATE_FIXTURE request exception") end
    return { StatusCode = 200, Success = true }
end
local task = { spawn = function() end }
'''
        script = driver + setup + "\nlocal function boot()\n" + SOURCE + "\nend\nboot()\n" + checks
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "telemetry-test.luau"
            path.write_text(script, encoding="utf-8")
            result = subprocess.run([str(LUAU), str(path)], capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_no_consent_or_invalid_config_never_sends(self):
        for setup in ["cfg.optIn = false", "cfg.optIn = nil", 'cfg.endpoint = "http://ingest.example"',
                      'cfg.endpoint = "https://name:secret@ingest.example/path"',
                      'cfg.endpoint = "https://ingest.example/path?key=fixture"',
                      'cfg.endpoint = "https://ingest.example/path#fragment"',
                      'cfg.endpoint = "https://ingest.example/path\\nfixture"',
                      'cfg.installId = "PrivatePlayer"', 'cfg.ingestKey = nil']:
            with self.subTest(setup=setup):
                self.run_client(setup, 'assert(#sent == 0 and #writes == 0 and G.__RESTHUB_TELEMETRY == nil)')

    def test_metadata_only_and_old_files_never_read(self):
        self.run_client('cfg.includeJobId = true', r'''
local T = G.__RESTHUB_TELEMETRY
assert(T and #sent == 1)
local event = sent[1].body.events[1]
assert(event.schema == 3 and event.kind == "session.start")
assert(event.context.gameId == 123 and event.context.placeId == 456)
assert(event.context.executor == nil and event.context.jobId == nil and event.context.player == nil)
assert(next(event.data) == nil)
for path in pairs(reads) do
    assert(path == "resthub_telemetry.json" or path == "resthub_telemetry_queue_v3.json")
end
assert(not T.collect())
assert(not T.emit("agent.note", "agent", { message = "PRIVATE_FIXTURE" }))
assert(not T.emit("agent.probe", "agent", { nested = { value = "PRIVATE_FIXTURE" } }))
assert(not T.emit("agent.probe", "PRIVATE_FIXTURE", {}))
assert(not T.emit("log.delta", "hub", { text = "PRIVATE_FIXTURE" }))
assert(not T.emit("agent.verification", "agent", { result = "PRIVATE_FIXTURE" }))
assert(T.emit("agent.verification", "agent", { check = "privacy", result = "pass", count = 1 }))
assert(not T.flush(), "manual flushing must honor the rate limit")
clock += 31
assert(T.flush() and #sent == 2)
assert(sent[2].body.events[1].data.check == "privacy")
assert(T.status().endpointHost == nil and T.status().installId == nil)
T.destroy()
assert(not T.emit("agent.note", "agent", {}) and not T.flush())
''')

    def test_persisted_events_are_reconstructed_not_trusted(self):
        self.run_client(r'''
saved = {
 {schema=1, eventId="33333333-3333-4333-8333-333333333333", installId=cfg.installId,
  kind="agent.note", source="agent", severity="info", data={message="PRIVATE_FIXTURE"}},
 {schema=3, eventId="44444444-4444-4444-8444-444444444444", installId=cfg.installId,
  kind="agent.verification", source="agent", severity="info", data={check="privacy",result="pass"},
  context={jobId="PRIVATE_FIXTURE"}, sessionId="PRIVATE_FIXTURE", timestamp="PRIVATE_FIXTURE"},
 {schema=3, eventId="55555555-5555-4555-8555-555555555555", installId=cfg.installId,
  kind="agent.note", source="agent", severity="info", data={nested={value="PRIVATE_FIXTURE"}}}
}
''', r'''
assert(#sent == 1 and #sent[1].body.events == 2)
local event = sent[1].body.events[1]
assert(event.data.check == "privacy" and event.context.jobId == nil)
assert(event.sessionId ~= "PRIVATE_FIXTURE" and type(event.timestamp) == "number")
''')

    def test_request_exceptions_never_expose_private_details(self):
        self.run_client('failRequest = true', r'''
local T = G.__RESTHUB_TELEMETRY
assert(T.status().lastError == "upload failed" and T.status().queued == 1)
assert(not T.flush() and #sent == 1)
''')

    def test_stop_during_request_does_not_overwrite_replacement(self):
        self.run_client('onRequest = function() G.__RESTHUB_TELEMETRY.destroy(); G.__RESTHUB_TELEMETRY = {sessionId="new-owner"} end', r'''
assert(G.__RESTHUB_TELEMETRY.sessionId == "new-owner")
assert(#writes == 2, "only enqueue and owned teardown may persist")
''')


if __name__ == "__main__":
    unittest.main()
