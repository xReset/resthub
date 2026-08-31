-- R3ST Telemetry Client v2026-08-31.2
-- Explicit opt-in diagnostics transport for users, MCP agents, and remote support.
-- No Roblox username, chat, hardware ID, cookies, or executor secrets are collected.

local VERSION = 2
local GKEY = "__RESTHUB_TELEMETRY"
local CONFIG_FILE = "resthub_telemetry.json"
local STATE_FILE = "resthub_telemetry_state.json"
local QUEUE_FILE = "resthub_telemetry_queue.json"
local MAX_LOG_TAIL = 32000
local MAX_EVENT_TEXT = 12000
local MAX_QUEUE = 150
local MAX_BATCH = 24
local DEFAULT_INTERVAL = 30
local HEARTBEAT_INTERVAL = 180
local HttpService = game:GetService("HttpService")
local G = getgenv()

if type(G[GKEY]) == "table" and type(G[GKEY].destroy) == "function" then
    pcall(G[GKEY].destroy)
end

local alive = true
local sessionId = HttpService:GenerateGUID(false)
local queue = {}
local offsets = {}
local lastHeartbeat = 0
local lastError
local lastUpload
local cfg

local function jsonDecode(raw)
    local ok, value = pcall(HttpService.JSONDecode, HttpService, raw)
    if ok and type(value) == "table" then return value end
end

local function jsonEncode(value)
    local ok, raw = pcall(HttpService.JSONEncode, HttpService, value)
    if ok then return raw end
end

local function readJson(path)
    local ok, raw = pcall(readfile, path)
    if not ok or type(raw) ~= "string" then return nil end
    return jsonDecode(raw)
end

local function writeJson(path, value)
    local raw = jsonEncode(value)
    if raw then return pcall(writefile, path, raw) end
    return false
end

cfg = readJson(CONFIG_FILE)
if type(cfg) ~= "table" or cfg.optIn ~= true then return end
if type(cfg.endpoint) ~= "string" or not cfg.endpoint:match("^https://") then return end
if type(cfg.installId) ~= "string" or not cfg.installId:match("^[%w%._%-]+$") or #cfg.installId < 8 or #cfg.installId > 80 then return end
if cfg.ingestKey ~= nil and (type(cfg.ingestKey) ~= "string" or #cfg.ingestKey < 16 or #cfg.ingestKey > 512) then return end
if type(request) ~= "function" then return end

local interval = math.clamp(tonumber(cfg.intervalSeconds) or DEFAULT_INTERVAL, 15, 300)
local state = readJson(STATE_FILE)
if type(state) == "table" and type(state.offsets) == "table" then offsets = state.offsets end
local savedQueue = readJson(QUEUE_FILE)
if type(savedQueue) == "table" then
    for _, event in ipairs(savedQueue) do
        if type(event) == "table" and #queue < MAX_QUEUE then queue[#queue + 1] = event end
    end
end

local ALLOWED_LOGS = {
    ["resthub-loader"] = "logs/resthub_loader.log",
    ["hub"] = "logs/rbx_hub.log",
    ["reload"] = "logs/r3st_reload.log",
    ["blr"] = "logs/blr_hub.log",
    ["ghost-driver"] = "logs/gd2.log",
}

local function redact(text)
    text = tostring(text or "")
    text = text:gsub("[Aa]uthorization:%s*[^%s]+", "Authorization: [REDACTED]")
    text = text:gsub("[Bb]earer%s+[%w%._%-]+", "Bearer [REDACTED]")
    text = text:gsub("gh[pousr]_[%w]+", "[GITHUB_TOKEN_REDACTED]")
    text = text:gsub("[Cc]ookie:%s*[^\r\n]+", "Cookie: [REDACTED]")
    text = text:gsub("[Pp]assword%s*[=:]%s*[^%s,]+", "password=[REDACTED]")
    if #text > MAX_EVENT_TEXT then text = text:sub(#text - MAX_EVENT_TEXT + 1) end
    return text
end

local function buildSnapshot()
    local builds = {}
    local keys = { "__R3ST_HUB", "__BLR_HUB", "__GD2" }
    for _, key in ipairs(keys) do
        local handle = G[key]
        if type(handle) == "table" and handle.build ~= nil then builds[key] = tostring(handle.build) end
    end
    local executorName, executorVersion = "unknown", "unknown"
    if type(identifyexecutor) == "function" then
        local ok, name, version = pcall(identifyexecutor)
        if ok then executorName, executorVersion = tostring(name), tostring(version) end
    end
    return {
        telemetryVersion = VERSION,
        gameId = game.GameId,
        placeId = game.PlaceId,
        jobId = cfg.includeJobId == true and tostring(game.JobId) or nil,
        executor = { name = executorName, version = executorVersion },
        builds = builds,
        loader = type(G.__RESTHUB_LOADER) == "table" and {
            version = G.__RESTHUB_LOADER.version,
            release = G.__RESTHUB_LOADER.release,
            revision = G.__RESTHUB_LOADER.revision,
            module = G.__RESTHUB_LOADER.module,
        } or nil,
    }
end

local function persist()
    writeJson(STATE_FILE, { schema = 1, offsets = offsets })
    writeJson(QUEUE_FILE, queue)
end

local function enqueue(kind, source, data, severity)
    local event = {
        schema = 1,
        eventId = HttpService:GenerateGUID(false),
        sessionId = sessionId,
        installId = cfg.installId,
        timestamp = os.time(),
        kind = tostring(kind),
        source = tostring(source or "resthub"),
        severity = tostring(severity or "info"),
        context = buildSnapshot(),
        data = type(data) == "table" and data or { message = redact(data) },
    }
    if type(event.data.message) == "string" then event.data.message = redact(event.data.message) end
    queue[#queue + 1] = event
    while #queue > MAX_QUEUE do table.remove(queue, 1) end
    persist()
    return event.eventId
end

local function collectLogs()
    for source, path in pairs(ALLOWED_LOGS) do
        local ok, body = pcall(readfile, path)
        if ok and type(body) == "string" then
            local previousOffset = tonumber(offsets[path]) or 0
            if previousOffset < 0 or previousOffset > #body then previousOffset = 0 end
            if #body > previousOffset then
                local startAt = math.max(previousOffset + 1, #body - MAX_LOG_TAIL + 1)
                local chunk = body:sub(startAt)
                offsets[path] = #body
                enqueue("log.delta", source, {
                    path = path,
                    from = startAt,
                    to = #body,
                    truncated = startAt > previousOffset + 1,
                    text = redact(chunk),
                }, "debug")
            end
        end
    end
end

local function flush()
    if #queue == 0 then return true, "empty" end
    local count = math.min(#queue, MAX_BATCH)
    local events = {}
    for i = 1, count do events[i] = queue[i] end
    local body = jsonEncode({ schema = 1, client = "resthub", telemetryVersion = VERSION, events = events })
    if not body then return false, "encode failed" end
    local headers = { ["Content-Type"] = "application/json", ["User-Agent"] = "resthub-telemetry/" .. VERSION }
    if type(cfg.ingestKey) == "string" then headers.Authorization = "Bearer " .. cfg.ingestKey end
    local ok, response = pcall(request, { Url = cfg.endpoint, Method = "POST", Headers = headers, Body = body })
    if not ok or type(response) ~= "table" or response.Success ~= true
        or tonumber(response.StatusCode) == nil or response.StatusCode < 200 or response.StatusCode >= 300 then
        lastError = ok and ("HTTP " .. tostring(response and response.StatusCode)) or tostring(response)
        persist()
        return false, lastError
    end
    for _ = 1, count do table.remove(queue, 1) end
    lastUpload, lastError = os.time(), nil
    persist()
    return true, "uploaded " .. count
end

local function status()
    return {
        alive = alive,
        version = VERSION,
        consent = true,
        sessionId = sessionId,
        installId = cfg.installId,
        endpointHost = cfg.endpoint:match("^https://([^/]+)"),
        queued = #queue,
        lastUpload = lastUpload,
        lastError = lastError,
        snapshot = buildSnapshot(),
    }
end

local function destroy()
    alive = false
    persist()
    if G[GKEY] and G[GKEY].sessionId == sessionId then G[GKEY] = nil end
end

G[GKEY] = {
    version = VERSION,
    sessionId = sessionId,
    emit = enqueue,       -- emit(kind, source, dataTable|string, severity?)
    collect = collectLogs,
    flush = flush,
    snapshot = buildSnapshot,
    status = status,
    destroy = destroy,
}

enqueue("session.start", "telemetry", { message = "R3ST telemetry session started" }, "info")
collectLogs()
flush()

task.spawn(function()
    while alive do
        task.wait(interval)
        if not alive then break end
        collectLogs()
        if os.time() - lastHeartbeat >= HEARTBEAT_INTERVAL then
            lastHeartbeat = os.time()
            enqueue("session.heartbeat", "telemetry", { queued = #queue }, "debug")
        end
        flush()
    end
end)
