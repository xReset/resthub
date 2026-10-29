-- R3ST Telemetry Client v2026-10-29.3
-- Explicit opt-in, metadata-only diagnostics. No raw logs or free-form events.
-- Old queue/state files are left untouched and are NEVER replayed by this build.
local VERSION = 3
local GKEY = "__RESTHUB_TELEMETRY"
local CONFIG_FILE = "resthub_telemetry.json"
local QUEUE_FILE = "resthub_telemetry_queue_v3.json"
local MAX_QUEUE, MAX_BATCH = 150, 24
local DEFAULT_INTERVAL, HEARTBEAT_INTERVAL = 30, 180
local HttpService = game:GetService("HttpService")
local G = getgenv()
if type(G[GKEY]) == "table" and type(G[GKEY].destroy) == "function" then pcall(G[GKEY].destroy) end
local alive, queue, inFlight = true, {}, false
local sessionId = HttpService:GenerateGUID(false)
local lastHeartbeat, lastAttempt, lastUpload, lastError = 0, nil, nil, nil

local function readJson(path)
    local ok, raw = pcall(readfile, path)
    if not ok or type(raw) ~= "string" or #raw > 262144 then return nil end
    local decoded, value = pcall(HttpService.JSONDecode, HttpService, raw)
    return decoded and type(value) == "table" and value or nil
end
local function writeQueue()
    if type(G[GKEY]) ~= "table" or G[GKEY].sessionId ~= sessionId then return end
    local ok, raw = pcall(HttpService.JSONEncode, HttpService, queue)
    if ok and type(raw) == "string" and #raw <= 262144 then pcall(writefile, QUEUE_FILE, raw) end
end
local function guid(value)
    return type(value) == "string" and value:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") ~= nil
end
local function integer(value, maximum)
    return type(value) == "number" and value >= 0 and value <= maximum and value == math.floor(value)
end
local function stamp(value)
    if type(value) == "string" and #value <= 80 and value:match("^[%w%._%-]+$")
        and value:find("%d") then return value end
end
local cfg = readJson(CONFIG_FILE)
if not cfg or cfg.optIn ~= true then return end
-- No userinfo, query/fragment credentials, non-default port or control chars.
if type(cfg.endpoint) ~= "string" or #cfg.endpoint > 2048 or cfg.endpoint:find("[%c]")
    or not (cfg.endpoint:match("^https://[%w%.%-]+/[^%s?#@\\]*$")
        or cfg.endpoint:match("^https://[%w%.%-]+$")) then return end
if not guid(cfg.installId) or type(cfg.ingestKey) ~= "string" or #cfg.ingestKey < 16
    or #cfg.ingestKey > 512 or cfg.ingestKey:find("[%s%c]") then return end
local requestApi = request or (syn and syn.request) or http_request
if type(requestApi) ~= "function" then return end
local requestedInterval = tonumber(cfg.intervalSeconds)
local interval = integer(requestedInterval, 300) and math.max(15, requestedInterval) or DEFAULT_INTERVAL

local SOURCES = { telemetry = true, hub = true, ["resthub-loader"] = true, resthub = true,
    blr = true, ["ghost-driver"] = true, agent = true, module = true }
local KINDS = { ["session.start"] = true, ["session.heartbeat"] = true,
    ["script.error"] = true, ["script.decision"] = true, ["script.lifecycle"] = true,
    ["agent.note"] = true, ["agent.probe"] = true, ["agent.verification"] = true }
local SEVERITIES = { info = true, debug = true, warn = true, error = true }
local ENUMS = {
    check = { compile = true, restore = true, lifecycle = true, readiness = true,
        hash = true, privacy = true, network = true, performance = true },
    result = { pass = true, fail = true, unverified = true, skipped = true },
    action = { mount = true, unmount = true, reload = true, start = true, stop = true,
        skip = true, restore = true },
    code = { compile = true, runtime = true, teardown = true, config = true,
        network = true, unknown = true },
}
local function cleanData(data)
    if type(data) ~= "table" or getmetatable(data) ~= nil then return nil end
    local result, count = {}, 0
    for key, value in pairs(data) do
        count += 1
        if count > 6 then return nil end
        if ENUMS[key] then
            if type(value) ~= "string" or not ENUMS[key][value] then return nil end
        elseif key == "count" or key == "queued" then
            if not integer(value, key == "queued" and MAX_QUEUE or 1000000) then return nil end
        else return nil end -- no messages, URLs, logs, identifiers or nested tables
        result[key] = value
    end
    return result
end
local function snapshot()
    local context = { telemetryVersion = VERSION, builds = {} }
    if integer(game.GameId, 9007199254740991) then context.gameId = game.GameId end
    if integer(game.PlaceId, 9007199254740991) then context.placeId = game.PlaceId end
    for _, key in ipairs({ "__R3ST_HUB", "__BLR_HUB", "__GD2" }) do
        local handle = G[key]
        local build = type(handle) == "table" and stamp(handle.build)
        if build then context.builds[key] = build end
    end
    -- Executor names, JobId, player identity and arbitrary loader fields excluded.
    return context
end
local function makeEvent(kind, source, data, severity, eventId)
    if type(kind) ~= "string" or not KINDS[kind] or type(source) ~= "string" or not SOURCES[source]
        or type(severity) ~= "string" or not SEVERITIES[severity] then return nil end
    local clean = cleanData(data)
    if not clean then return nil end
    return { schema = 3, eventId = eventId or HttpService:GenerateGUID(false),
        sessionId = sessionId, installId = cfg.installId, timestamp = os.time(),
        kind = kind, source = source, severity = severity, context = snapshot(), data = clean }
end
-- Only this version's queue is read. Reconstruct every event from typed fields;
-- persisted context, identifiers and unknown fields are never copied to uploads.
local saved = readJson(QUEUE_FILE)
if saved then
    for _, event in ipairs(saved) do
        if #queue >= MAX_QUEUE then break end
        if type(event) == "table" and event.schema == 3 and event.installId == cfg.installId and guid(event.eventId) then
            local clean = makeEvent(event.kind, event.source, event.data, event.severity, event.eventId)
            if clean then queue[#queue + 1] = clean end
        end
    end
end
local function enqueue(kind, source, data, severity)
    if not alive then return false, "telemetry stopped" end
    local event = makeEvent(kind, source or "resthub", data, severity or "info")
    if not event then return false, "unsupported metadata schema" end
    queue[#queue + 1] = event
    while #queue > MAX_QUEUE do table.remove(queue, 1) end
    writeQueue()
    return event.eventId
end
local function collect()
    return false, "raw log collection is disabled"
end
local function flush()
    if not alive then return false, "telemetry stopped" end
    if #queue == 0 then return true, "empty" end
    if inFlight then return false, "upload busy" end
    if lastAttempt and os.clock() - lastAttempt < interval then return false, "rate limited" end
    local count, events = math.min(#queue, MAX_BATCH), {}
    for i = 1, count do
        local event = queue[i]
        -- Revalidate at send time too; only fresh context is serialized.
        local clean = makeEvent(event.kind, event.source, event.data, event.severity, event.eventId)
        if not clean then return false, "invalid queued metadata" end
        events[i] = clean
    end
    local encoded, body = pcall(HttpService.JSONEncode, HttpService,
        { schema = 3, client = "resthub", telemetryVersion = VERSION, events = events })
    if not encoded or type(body) ~= "string" or #body > 65536 then return false, "batch size/encode failed" end
    lastAttempt, inFlight = os.clock(), true
    local ok, response = pcall(requestApi, { Url = cfg.endpoint, Method = "POST",
        Headers = { ["Content-Type"] = "application/json", Authorization = "Bearer " .. cfg.ingestKey }, Body = body })
    inFlight = false
    if not alive or type(G[GKEY]) ~= "table" or G[GKEY].sessionId ~= sessionId then
        return false, "telemetry stopped"
    end
    local code = ok and type(response) == "table" and tonumber(response.StatusCode) or 0
    if not integer(code, 599) or code < 200 or code >= 300 then
        -- Never echo request exceptions, response bodies or private destinations.
        lastError = "upload failed"
        writeQueue()
        return false, lastError
    end
    for _ = 1, count do table.remove(queue, 1) end
    lastUpload, lastError = os.time(), nil
    writeQueue()
    return true, "uploaded metadata"
end
local function status()
    return { alive = alive, version = VERSION, consent = true, queued = #queue,
        lastUpload = lastUpload, lastError = lastError, snapshot = snapshot() }
end
local function destroy()
    alive = false
    writeQueue()
    if type(G[GKEY]) == "table" and G[GKEY].sessionId == sessionId then G[GKEY] = nil end
end
G[GKEY] = { version = VERSION, sessionId = sessionId, emit = enqueue,
    collect = collect, flush = flush, snapshot = snapshot, status = status, destroy = destroy }
enqueue("session.start", "telemetry", {}, "info")
flush()
task.spawn(function()
    while alive do
        task.wait(interval)
        if not alive then break end
        if os.time() - lastHeartbeat >= HEARTBEAT_INTERVAL then
            lastHeartbeat = os.time()
            enqueue("session.heartbeat", "telemetry", { queued = #queue }, "debug")
        end
        flush()
    end
end)
