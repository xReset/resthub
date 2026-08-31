-- R3ST Hub remote loader v2026-08-31.2
-- Public bootstrap: immutable release fetch, SHA-256 verification, verified cache fallback.
-- Rung 2: distribution/bootstrap only; no game state or Roblox remotes touched.

local LOADER_VERSION = 2
local OWNER, REPO, CHANNEL = "xReset", "resthub", "main"
local RAW_ROOT = ("https://raw.githubusercontent.com/%s/%s/"):format(OWNER, REPO)
local MANIFEST_URL = RAW_ROOT .. CHANNEL .. "/manifest.json"
local LOG_FILE = "logs/resthub_loader.log"
local LOCK_KEY = "__RESTHUB_LOADER"
local MAX_MANIFEST_BYTES = 128 * 1024
local MAX_SOURCE_BYTES = 2 * 1024 * 1024
local DOWNLOAD_ATTEMPTS = 3
local HttpService = game:GetService("HttpService")
local G = getgenv()

local previous = G[LOCK_KEY]
if type(previous) == "table" and previous.running == true then
    return
end
local run = { running = true, version = LOADER_VERSION, started = os.time() }
G[LOCK_KEY] = run

local function ensureLogFolder()
    pcall(function()
        if type(makefolder) == "function" and type(isfolder) == "function" and not isfolder("logs") then
            makefolder("logs")
        end
    end)
end

local function log(level, message)
    ensureLogFolder()
    local clean = tostring(message):gsub("[\r\n]+", " | ")
    local line = ("[%s] [%s] loader=%d %s\n"):format(os.date("%Y-%m-%d %H:%M:%S"), level, LOADER_VERSION, clean)
    pcall(function()
        if type(isfile) == "function" and isfile(LOG_FILE) and type(appendfile) == "function" then
            appendfile(LOG_FILE, line)
        elseif type(writefile) == "function" then
            writefile(LOG_FILE, line)
        end
    end)
end

local function fail(message)
    run.running = false
    run.error = tostring(message)
    log("ERROR", message)
    error("resthub: " .. tostring(message), 0)
end

local function isInteger(value)
    return type(value) == "number" and value == math.floor(value)
end

local function fetchOnce(url)
    if type(request) == "function" then
        local ok, response = pcall(request, {
            Url = url,
            Method = "GET",
            Headers = { ["Cache-Control"] = "no-cache", ["User-Agent"] = "resthub-loader/" .. LOADER_VERSION },
        })
        if ok and type(response) == "table" then
            local status = tonumber(response.StatusCode)
            local body = response.Body
            if response.Success == true and status and status >= 200 and status < 300 and type(body) == "string" then
                return body
            end
            return nil, "HTTP " .. tostring(status or response.StatusMessage or "request failed")
        end
    end
    if type(httpget) == "function" then
        local ok, body = pcall(httpget, url)
        if ok and type(body) == "string" then return body end
        return nil, tostring(body)
    end
    return nil, "no supported HTTP function"
end

local function fetch(url, maxBytes)
    local lastError = "unknown download failure"
    for attempt = 1, DOWNLOAD_ATTEMPTS do
        local body, err = fetchOnce(url)
        if type(body) == "string" then
            if #body == 0 then
                lastError = "empty response"
            elseif #body > maxBytes then
                return nil, ("response exceeds %d bytes"):format(maxBytes)
            else
                return body
            end
        else
            lastError = tostring(err)
        end
        if attempt < DOWNLOAD_ATTEMPTS then task.wait(0.35 * attempt) end
    end
    return nil, lastError
end

local function decodeJson(raw, label)
    local ok, value = pcall(HttpService.JSONDecode, HttpService, raw)
    if not ok or type(value) ~= "table" then return nil, label .. " is not valid JSON object" end
    return value
end

local function sha256(body)
    if type(crypt) ~= "table" or type(crypt.hash) ~= "function" then
        return nil, "Potassium crypt.hash is unavailable"
    end
    local ok, digest = pcall(crypt.hash, body, "sha256")
    if not ok or type(digest) ~= "string" or #digest ~= 64 then
        return nil, "crypt.hash returned an invalid SHA-256 digest"
    end
    return string.lower(digest)
end

local function verify(body, expected)
    local actual, err = sha256(body)
    if not actual then return false, err end
    if actual ~= string.lower(expected) then
        return false, ("SHA-256 mismatch expected=%s actual=%s"):format(expected, actual)
    end
    return true, actual
end

local manifestRaw, manifestFetchError = fetch(MANIFEST_URL, MAX_MANIFEST_BYTES)
if not manifestRaw then fail("manifest download failed: " .. tostring(manifestFetchError)) end
local manifest, manifestDecodeError = decodeJson(manifestRaw, "manifest")
if not manifest then fail(manifestDecodeError) end

if manifest.schema ~= 1 then fail("unsupported manifest schema " .. tostring(manifest.schema)) end
if not isInteger(manifest.minLoader) or manifest.minLoader > LOADER_VERSION then
    fail(("release requires loader %s; this loader is %d"):format(tostring(manifest.minLoader), LOADER_VERSION))
end
if type(manifest.release) ~= "string" or #manifest.release < 1 or #manifest.release > 80 then fail("invalid release name") end
if type(manifest.revision) ~= "string" or not manifest.revision:match("^[0-9a-fA-F]+$") or #manifest.revision ~= 40 then
    fail("manifest revision must be a full 40-character git commit SHA")
end
if type(manifest.files) ~= "table" or type(manifest.modules) ~= "table" then fail("manifest files/modules missing") end

local selected
for _, module in ipairs(manifest.modules) do
    if type(module) ~= "table" or type(module.id) ~= "string" or type(module.path) ~= "string" then
        fail("invalid module entry")
    end
    local identityMatch = (isInteger(module.gameId) and module.gameId == game.GameId)
        or (isInteger(module.placeId) and module.placeId == game.PlaceId)
    if identityMatch then
        if selected then fail("manifest has multiple modules matching this experience") end
        selected = module
    end
end

local required = { "hub.lua", "r3st_ui.lua" }
if selected then required[#required + 1] = selected.path end
local optional = { "telemetry.lua" }
local releaseRoot = RAW_ROOT .. manifest.revision .. "/"
local staged = {}
local specs = {}

local function validateSpec(remotePath)
    if type(remotePath) ~= "string" or remotePath:find("..", 1, true) or remotePath:sub(1, 1) == "/" then
        fail("unsafe manifest path " .. tostring(remotePath))
    end
    local spec = manifest.files[remotePath]
    if type(spec) ~= "table" then fail("missing file specification for " .. remotePath) end
    if type(spec.sha256) ~= "string" or not spec.sha256:match("^[0-9a-fA-F]+$") or #spec.sha256 ~= 64 then
        fail("invalid SHA-256 for " .. remotePath)
    end
    if type(spec.localName) ~= "string" or spec.localName:find("..", 1, true)
        or spec.localName:find("[/\\]") or not spec.localName:match("^[%w%._%-]+$") then
        fail("unsafe cache filename for " .. remotePath)
    end
    specs[remotePath] = spec
    return spec
end

local function stageFile(remotePath, mandatory)
    local spec = validateSpec(remotePath)
    local body, downloadError = fetch(releaseRoot .. remotePath, MAX_SOURCE_BYTES)
    if body then
        local valid, verifyError = verify(body, spec.sha256)
        if valid then
            staged[remotePath] = { body = body, source = "network" }
            return true
        end
        downloadError = verifyError
    end

    local cacheOk, cached = pcall(readfile, spec.localName)
    if cacheOk and type(cached) == "string" and #cached <= MAX_SOURCE_BYTES then
        local cacheValid = verify(cached, spec.sha256)
        if cacheValid then
            staged[remotePath] = { body = cached, source = "verified-cache" }
            log("WARN", "using verified cache for " .. remotePath .. ": " .. tostring(downloadError))
            return true
        end
    end
    if mandatory then fail("unable to obtain verified " .. remotePath .. ": " .. tostring(downloadError)) end
    log("WARN", "optional file unavailable " .. remotePath .. ": " .. tostring(downloadError))
    return false
end

-- Validate and acquire every mandatory file before changing any cache file.
for _, remotePath in ipairs(required) do stageFile(remotePath, true) end
for _, remotePath in ipairs(optional) do stageFile(remotePath, false) end

-- Compile every executable before publishing the staged release to cache.
local compiled = {}
for remotePath, item in pairs(staged) do
    local chunk, compileError = loadstring(item.body, "=resthub/" .. remotePath)
    if not chunk then
        if specs[remotePath] and remotePath ~= "telemetry.lua" then fail("compile failed for " .. remotePath .. ": " .. tostring(compileError)) end
        log("WARN", "optional compile failed for " .. remotePath .. ": " .. tostring(compileError))
        staged[remotePath] = nil
    else
        compiled[remotePath] = chunk
    end
end

for remotePath, item in pairs(staged) do
    if item.source == "network" then
        local ok, writeError = pcall(writefile, specs[remotePath].localName, item.body)
        if not ok then fail("cache write failed for " .. remotePath .. ": " .. tostring(writeError)) end
    end
end

local hubChunk = compiled["hub.lua"]
if type(hubChunk) ~= "function" then fail("verified hub chunk missing") end
local okHub, hubError = xpcall(hubChunk, debug.traceback)
if not okHub then fail("hub runtime error: " .. tostring(hubError)) end

-- Diagnostics never blocks Hub startup. It is itself inert without an explicit,
-- ignored local opt-in config and private HTTPS endpoint.
if type(compiled["telemetry.lua"]) == "function" then
    task.spawn(function()
        local ok, telemetryError = pcall(compiled["telemetry.lua"])
        if not ok then log("WARN", "telemetry client error: " .. tostring(telemetryError)) end
    end)
end

run.running = false
run.release = manifest.release
run.revision = manifest.revision
run.module = selected and selected.id or "none"
log("INFO", ("boot release=%s revision=%s gameId=%s placeId=%s module=%s"):format(
    manifest.release, manifest.revision:sub(1, 12), tostring(game.GameId), tostring(game.PlaceId), run.module))
