-- RoChess Hub v2026-10-27.3 (2026-10-27)
-- Rungs 1-2 (read session, Hub UI) and 6 (normal App.onBoardMove online).
-- Server sees normal move packets AND the game's existing integrity telemetry.
-- Proof: dump 2026-10-27T07-16-25Z, 0020.lua:1350-1460,1922-2032; 0040.lua:15-130.
-- Puzzles use native puzzleMove/rushMove validation + nextPuzzle, 0037.lua:360-479,1273-1320,1991-2282.
-- Puzzle toggles boot OFF (rung 6); never forge scores, reveal answers or modify puzzle/run state.
-- No hooks, telemetry edits, arrows or built-in Bot searches. No safety/undetectability promise.
-- Chess Toggle boots OFF on fresh injection. User-authorized teleport continuation may resume ON.
-- Teleport handoff is short-lived, single-use and universe-guarded; no telemetry bypass.
-- Re-inject safe: self-teardown on load; P = panic, K = unload (outside text fields).
-- Changelog: .3 add Auto Puzzle and Auto Puzzle Sprint; .2 teleport resume; .1 Stockfish.
local BUILD_VERSION = "2026-10-27.3"
local GKEY = "__ROCHESS_HUB"
local EXPECTED_GAME, EXPECTED_PLACE = 10768845402, 139717576471404
if game.GameId ~= EXPECTED_GAME and game.PlaceId ~= EXPECTED_PLACE then return end
local G = getgenv()
local HOST = G.__R3ST_HOST
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local CONFIG_FILE = "rochess_hub_config.json"
local Log = { info = function() end, err = function() end }
pcall(function() Log = loadfile("log.lua")()("rochess_hub") end)
if not (HOST and HOST.ui) then Log.err("Hub host required"); return end
if G[GKEY] and G[GKEY].destroy then pcall(G[GKEY].destroy) end
local Kit = HOST.ui
assert(Kit.SHELL_CONTRACT == "1", "R3ST shell contract mismatch")
local App = require(game:GetService("ReplicatedStorage").ChessClient.App)
local Engine = require(game:GetService("ReplicatedStorage").Chess.Engine)
local cfg = { enabled = false, autoPuzzle = false, autoSprint = false, resumeOnTeleport = true, analysisOnly = false, fullStrength = true, elo = 2000,
    thinkMs = 1000, delayMs = 500, jitterMs = 250 }
local bounds = { elo = {1320,3190}, thinkMs = {50,10000}, delayMs = {0,10000}, jitterMs = {0,5000} }
do
    local ok, raw = pcall(readfile, CONFIG_FILE)
    if ok then
        local decoded, saved = pcall(HttpService.JSONDecode, HttpService, raw)
        if decoded and type(saved) == "table" then
            for key, value in next, cfg do
                if key ~= "enabled" and key ~= "autoPuzzle" and key ~= "autoSprint" and type(saved[key]) == type(value) then
                    if type(value) == "number" then
                        local v = saved[key]
                        if v == v and math.abs(v) < math.huge then cfg[key] = math.clamp(math.floor(v), bounds[key][1], bounds[key][2]) end
                    else cfg[key] = saved[key] end
                end
            end
        end
    end
end
cfg.enabled = false
local continued = false
if G.__ROCHESS_TELEPORT_RESUME then
    G.__ROCHESS_TELEPORT_RESUME = nil
    local ok, raw = pcall(readfile, "rochess_teleport_resume.json")
    if ok then
        local decoded, marker = pcall(HttpService.JSONDecode, HttpService, raw)
        if decoded and type(marker) == "table" and type(marker.expires) == "number"
            and marker.expires >= os.time() and marker.expires <= os.time()+300
            and marker.sourceJob ~= game.JobId and cfg.resumeOnTeleport then
            cfg.enabled = marker.enabled == true
            continued = true
        end
    end
    pcall(writefile, "rochess_teleport_resume.json", "{}")
end
local state = { alive = true, busy = false, generation = 0, conns = {}, live = {},
    bridge = "Connecting", engine = "Stockfish", message = cfg.enabled and "Resuming chess after teleport" or "OFF - turn on when ready", best = "-",
    teleport = "Not queued", teleporting = false,
    detail = "No analysis yet", fen = "-", ply = 0, kind = "idle", turn = "-", moves = 0,
    health = false, nextHealth = 0, retryAt = 0, analyzedKey = nil, attemptedKey = nil,
    pending = nil, requestCount = 0, staleCount = 0, nextPuzzle = nil, advancedSession = nil, lastPuzzleAttempt = nil }
local function puzzleKind(kind) return kind == "puzzle" or kind == "rush" end
local function active(kind)
    if kind == "puzzle" then return cfg.autoPuzzle end
    if kind == "rush" then return cfg.autoSprint end
    return cfg.enabled
end
local Shell, handle
local function saveConfig()
    local ok, raw = pcall(HttpService.JSONEncode, HttpService, cfg)
    if ok then pcall(writefile, CONFIG_FILE, raw) end
end
local function invalidate()
    state.generation += 1
    state.pending = nil
    state.nextPuzzle = nil
    state.analyzedKey = nil
    state.retryAt = 0
end
local function setEnabled(value)
    if not state.alive then return false end
    cfg.enabled = value == true
    if cfg.enabled then state.attemptedKey = nil end
    invalidate()
    state.message = cfg.enabled and "Reading current game" or "OFF - no moves will be made"
    Log.info("Chess Toggle=" .. tostring(cfg.enabled) .. " analysisOnly=" .. tostring(cfg.analysisOnly))
    return true
end
local function setSetting(key, value)
    if key == "enabled" then return setEnabled(value) end
    if cfg[key] == nil or type(value) ~= type(cfg[key]) then return false end
    if key == "autoPuzzle" or key == "autoSprint" then
        cfg[key] = value
        if value then
            cfg[key == "autoPuzzle" and "autoSprint" or "autoPuzzle"] = false
            state.attemptedKey = nil
            state.advancedSession = nil
            state.lastPuzzleAttempt = nil
        end
        invalidate()
        state.message = value and "Puzzle automation armed - open the mode in game" or "Puzzle automation OFF"
        Log.info(key .. "=" .. tostring(value))
        return true
    end
    if bounds[key] then
        if value ~= value or math.abs(value) == math.huge then return false end
        value = math.clamp(math.floor(value), bounds[key][1], bounds[key][2])
    end
    cfg[key] = value
    invalidate()
    return true
end
local function destroy()
    if not state.alive then return end
    saveConfig() -- flush choices before clearing runtime; enabled never resumes
    state.alive = false
    invalidate()
    for _, conn in ipairs(state.conns) do pcall(function() conn:Disconnect() end) end
    if Shell then Shell.destroy() end
    if G[GKEY] == handle then G[GKEY] = nil end
    Log.info("unloaded; pending moves cancelled")
end
local http = request or (syn and syn.request) or http_request
local function fetch(path, payload)
    if type(http) ~= "function" then error("Executor HTTP request unavailable") end
    local headers = { ["Content-Type"] = "application/json" }
    local options = { Url = "http://127.0.0.1:8765" .. path, Method = payload and "POST" or "GET", Headers = headers, Timeout = 16 }
    if payload then
        local ok, token = pcall(readfile, "rochess_bridge_token.txt")
        if not ok then error("Start tools/start_rochess_bridge.ps1 on this PC first") end
        headers["X-R3ST-Token"] = string.gsub(token, "%s", "")
        options.Body = HttpService:JSONEncode(payload)
    end
    local result = http(options)
    if type(result) ~= "table" then error("Local bridge did not reply") end
    local ok, data = pcall(HttpService.JSONDecode, HttpService, result.Body or "")
    if not ok or type(data) ~= "table" then error("Invalid local bridge reply") end
    if result.StatusCode ~= 200 or data.ok ~= true then error(tostring(data.error or ("HTTP " .. tostring(result.StatusCode)))) end
    return data
end
local function snapshot()
    local s = App.session
    if not s or not s.engine or type(s.ucis) ~= "table" then return nil end
    local fen = s.engine:getFen()
    local pz = puzzleKind(s.kind) and s.pz or nil
    local positionKey = tostring(s) .. ":" .. tostring(s.id) .. ":" .. #s.ucis .. ":" .. fen
        .. (pz and (":" .. tostring(pz.step)) or "")
    return { session = s, fen = fen, ply = #s.ucis, id = s.id, kind = s.kind, pz = pz,
        step = pz and pz.step, token = pz and pz.token, run = pz and pz.run,
        generation = state.generation, attemptKey = positionKey, key = positionKey .. (pz and (":" .. tostring(pz.token)) or ""),
        startFen = s.startFen or Engine.START_FEN, moves = table.clone(s.ucis) }
end
local function current(snap)
    if not state.alive or not active(snap.kind) or state.teleporting or state.generation ~= snap.generation then return false end
    local s = App.session
    if s ~= snap.session or s.id ~= snap.id or s.kind ~= snap.kind or #s.ucis ~= snap.ply
        or s.engine:getFen() ~= snap.fen or s.over or s.viewPly ~= #s.ucis then return false end
    if snap.pz then
        local pz = s.pz
        return pz == snap.pz and pz.step == snap.step and pz.token == snap.token and pz.run == snap.run
            and not (pz.busy or pz.done or pz.wrong or pz.revealing)
            and App.pages.current == (snap.kind == "puzzle" and "puzzles" or "rush")
            and (not pz.run or not pz.run.deadline or pz.run.deadline > os.clock())
    end
    return true
end
local function eligible(snap)
    local s = snap.session
    if s.over then return false, "Game over - waiting for next game" end
    if puzzleKind(snap.kind) then
        local pz = s.pz
        if not pz then return false, "Waiting for puzzle state" end
        if App.pages.current ~= (snap.kind == "puzzle" and "puzzles" or "rush") then return false, "Puzzle page closed - paused" end
        if pz.done then return false, "Puzzle complete - waiting for next" end
        if pz.busy or pz.revealing then return false, "Waiting for puzzle animation / server reply" end
        if pz.wrong then return false, "Waiting for wrong-move recovery" end
        if pz.run and pz.run.deadline and pz.run.deadline <= os.clock() then return false, "Sprint time is up" end
        if not s:isMyTurn() then return false, "Waiting for puzzle opponent's move" end
    elseif snap.kind ~= "online" and snap.kind ~= "bot" and snap.kind ~= "analysis" then
        return false, "Waiting for a game (midgame is supported)"
    end
    if s.viewPly ~= #s.ucis then return false, "Viewing history - return to latest move" end
    if not cfg.analysisOnly then
        if snap.kind == "analysis" then return false, "Enable Analysis only for the analysis board" end
        if not s:isMyTurn() then return false, "Opponent's turn - watching moves" end
    end
    return true
end
local function timeBudget(s)
    if s.kind == "rush" and s.pz and s.pz.run and s.pz.run.deadline then
        local remaining = math.max(0, (s.pz.run.deadline - os.clock()) * 1000)
        return math.max(10, math.min(cfg.thinkMs, math.floor(remaining * 0.25))), remaining
    end
    if not s.clocks or #s.ucis < 2 then return cfg.thinkMs, math.huge end
    local color = s.myColor or s.engine.side
    local remain = s:clockFor(color, workspace:GetServerTimeNow())
    return math.max(10, math.min(cfg.thinkMs, math.floor(math.max(10, remain - 600) * 0.25))), remain
end
local function analyse(snap)
    state.busy = true
    state.requestCount += 1
    local requestId = tostring(state.requestCount) .. ":" .. snap.ply .. ":" .. snap.generation
    local budget = timeBudget(snap.session)
    local payload = { start_fen = snap.startFen, moves = snap.moves, movetime_ms = budget, request_id = requestId }
    if not cfg.fullStrength and not puzzleKind(snap.kind) then payload.elo = cfg.elo end
    state.message = "Thinking (" .. budget .. " ms)"
    task.spawn(function()
        local ok, result = xpcall(function() return fetch("/analyse", payload) end, tostring)
        state.busy = false
        if not state.alive then return end
        if not current(snap) then state.staleCount += 1; return end
        if not ok then
            state.message = "Engine error - " .. tostring(result)
            state.retryAt = os.clock() + 4
            Log.err(state.message)
            return
        end
        if result.request_id ~= requestId then
            state.message = "Discarded mismatched engine reply"; state.retryAt = os.clock() + 4; return
        end
        state.analyzedKey = snap.key
        if type(result.bestmove) ~= "string" then state.message = "No legal move / terminal position"; return end
        local move = snap.session.engine:moveFromUci(result.bestmove)
        if not move then state.message = "Discarded illegal engine move"; return end
        local chosen = result.bestmove
        local expected = snap.pz and type(snap.pz.sol) == "table" and snap.pz.sol[snap.step]
        -- A puzzle may accept one exact line even when Stockfish finds an equally good alternative.
        -- Only use an already-provided legal move; never reveal answers or alter native judging.
        if type(expected) == "string" and snap.session.engine:moveFromUci(expected) then chosen = expected end
        state.best = chosen
        state.detail = "Depth " .. tostring(result.depth or "-") .. " | " .. (result.mate and ("Mate " .. result.mate) or ("Score " .. tostring(result.score_cp or "-") .. " cp")) .. " (side to move)"
            .. (chosen ~= result.bestmove and " | Native puzzle line" or "")
        if cfg.analysisOnly then state.message = "Analysis ready - no moves sent"; return end
        local _, remaining = timeBudget(snap.session)
        local delay = math.max(0, cfg.delayMs + (math.random() * 2 - 1) * cfg.jitterMs)
        delay = math.min(delay, math.max(0, remaining - 500))
        state.pending = { snap = snap, uci = chosen, due = os.clock() + delay / 1000 }
        state.message = "Move ready - waiting " .. string.format("%.2f", delay / 1000) .. " s"
    end)
end
local function tick()
    local snap = snapshot()
    if snap then
        state.fen, state.ply, state.kind = snap.fen, snap.ply, snap.kind
        state.turn = snap.session.engine.side == 1 and "White" or "Black"
    end
    if not (cfg.enabled or cfg.autoPuzzle or cfg.autoSprint) then return end
    if state.teleporting then state.message = "Teleporting - moves paused"; return end
    if not snap then state.message = "Waiting for board state"; return end
    if not active(snap.kind) then state.pending = nil; state.message = "Waiting for enabled mode - start it in game"; return end
    if snap.pz and snap.pz.wrong and state.lastPuzzleAttempt == snap.session then
        setSetting(snap.kind == "puzzle" and "autoPuzzle" or "autoSprint", false)
        state.message = "Puzzle answer rejected - automation stopped; review the move"
        saveConfig()
        return
    end
    -- Only request the next regular puzzle after native judging confirms solved.
    -- Sprint owns its own 0.35 s transition; never advance its run or change its score here.
    if snap.kind == "puzzle" and snap.pz and snap.pz.done and snap.pz.outcome == "solved" and not cfg.analysisOnly then
        state.pending = nil
        if App.pages.current ~= "puzzles" then state.nextPuzzle = nil; return end
        if state.advancedSession == snap.session then state.message = "Loading next puzzle - use native Next if loading fails"; return end
        if not state.nextPuzzle or state.nextPuzzle.session ~= snap.session then
            state.nextPuzzle = {session = snap.session, due = os.clock()+0.8, generation = state.generation}
        end
        local nextPuzzle = state.nextPuzzle
        if os.clock() >= nextPuzzle.due and nextPuzzle.generation == state.generation then
            state.advancedSession = snap.session
            state.nextPuzzle = nil
            -- Public Puzzle dispatcher returns before the unrelated base App.debug handler.
            App.debug({type = "nextPuzzle"})
            state.message = "Loading next puzzle"
        end
        return
    end
    state.nextPuzzle = nil
    local can, reason = eligible(snap)
    if not can then state.pending = nil; state.message = reason; return end
    if not state.health then state.message = "Bridge offline - run start_rochess_bridge.ps1"; return end
    local pending = state.pending
    if pending then
        if not current(pending.snap) then state.pending = nil; state.staleCount += 1
        elseif os.clock() >= pending.due then
            state.pending = nil
            if state.attemptedKey == pending.snap.attemptKey then return end
            -- Normal game path, including its existing telemetry. Never use plain-UCI helper or spoof input.
            local s = App.session
            local legal = s.engine:moveFromUci(pending.uci)
            if not legal or not s:isMyTurn() or cfg.analysisOnly then return end
            state.attemptedKey = pending.snap.attemptKey -- no retry after native rollback/token changes
            if puzzleKind(s.kind) then state.lastPuzzleAttempt = s end
            local from, to = Engine.moveSquares64(legal)
            local accepted = App.onBoardMove(from, to, Engine.movePromo(legal), false)
            state.message = accepted and "Move applied locally - watching server state" or "Move rejected locally - toggle OFF/ON to retry"
            if accepted then state.moves += 1 end
            Log.info("move=" .. pending.uci .. " locallyApplied=" .. tostring(accepted) .. " ply=" .. pending.snap.ply)
        end
        return
    end
    if state.attemptedKey == snap.attemptKey and not cfg.analysisOnly then
        state.message = "Move already submitted - waiting for native state; OFF/ON retries"
        return
    end
    if state.busy or os.clock() < state.retryAt or state.analyzedKey == snap.key then return end
    analyse(snap)
end
local function checkHealth()
    state.busy = true
    task.spawn(function()
        local ok, reply = xpcall(function() return fetch("/health") end, tostring)
        state.busy = false
        if not state.alive then return end
        state.health = ok and reply.service == "r3st-rochess-bridge-v2"
        state.bridge = state.health and (reply.engine or "Connected") or "Offline - start bridge on this PC"
        if state.health then state.engine = reply.engine or "Stockfish" end
    end)
end
handle = { build = BUILD_VERSION, embedded = true, ready = false, destroy = destroy,
    setEnabled = function(v) local ok = setEnabled(v); saveConfig(); return ok end,
    panic = function() setEnabled(false); cfg.autoPuzzle = false; cfg.autoSprint = false; saveConfig() end,
    set = function(k,v) local ok = setSetting(k,v); if ok then saveConfig() end; return ok end,
    status = function() return { build = BUILD_VERSION, enabled = cfg.enabled, autoPuzzle = cfg.autoPuzzle, autoSprint = cfg.autoSprint, analysisOnly = cfg.analysisOnly,
        bridge = state.bridge, health = state.health, message = state.message, bestmove = state.best,
        fen = state.fen, ply = state.ply, kind = state.kind, busy = state.busy, pending = state.pending ~= nil,
        moves = state.moves, requests = state.requestCount, stale = state.staleCount, teleport = state.teleport, continued = continued, settings = table.clone(cfg) } end }
G[GKEY] = handle
local ok, err = xpcall(function()
    Shell = Kit.moduleShell({ id = "rochess", title = "RoChess", version = BUILD_VERSION,
        subtitle = "Local Stockfish - exact board state", gameId = EXPECTED_GAME, placeId = EXPECTED_PLACE,
        tabs = { "Chess", "Settings" }, cfg = cfg, save = saveConfig, live = state.live, conns = state.conns,
        onUnload = destroy, onSettings = function() Shell.show("Settings") end, hint = "P stops chess | K unloads | RightShift hides Hub" })
    -- Register once per client lifetime; never clear another script's teleport queue.
    local queueTeleport = queueonteleport or queue_on_teleport
    if type(queueTeleport) == "function" then
        if not G.__ROCHESS_TELEPORT_QUEUED then
            local queued = pcall(queueTeleport, [[
                task.spawn(function()
                    local G = getgenv()
                    if G.__ROCHESS_TELEPORT_BOOT then return end
                    G.__ROCHESS_TELEPORT_BOOT = true
                    if not game:IsLoaded() then game.Loaded:Wait() end
                    if game.GameId ~= 10768845402 and game.PlaceId ~= 139717576471404 then return end
                    G.__ROCHESS_TELEPORT_RESUME = true
                    local ok, err = xpcall(function()
                        local chunk, why = loadfile("../scripts/hub.lua")
                        if not chunk then chunk, why = loadfile("hub.lua") end
                        assert(chunk, why)()
                    end, tostring)
                    if not ok then pcall(writefile, "logs/rochess_teleport_error.log", tostring(err)) end
                end)
            ]])
            G.__ROCHESS_TELEPORT_QUEUED = queued
        end
        state.teleport = G.__ROCHESS_TELEPORT_QUEUED and "Hub auto-reload queued" or "Queue failed - reinject may be needed"
    else state.teleport = "Executor teleport queue unavailable" end
    local player = game:GetService("Players").LocalPlayer
    state.conns[#state.conns+1] = player.OnTeleport:Connect(function(phase)
        if phase == Enum.TeleportState.Started or phase == Enum.TeleportState.InProgress then
            state.teleporting = true
            saveConfig()
            local marker = { enabled = cfg.enabled and cfg.resumeOnTeleport, sourceJob = game.JobId, expires = os.time()+300 }
            local encoded, raw = pcall(HttpService.JSONEncode, HttpService, marker)
            if encoded then pcall(writefile, "rochess_teleport_resume.json", raw) end
            invalidate()
        elseif phase == Enum.TeleportState.Failed then
            state.teleporting = false
            pcall(writefile, "rochess_teleport_resume.json", "{}")
        end
    end)
    local W = Shell.W
    local main = Shell.page("Chess")
    W.section(main, "Play")
    W.toggle(main, { label = "Chess Toggle", key = "enabled", set = setEnabled,
        desc = "Reads the current position, including moves already played." })
    W.toggle(main, { label = "Analysis only", key = "analysisOnly", set = function(v) return setSetting("analysisOnly", v) end,
        desc = "Show the engine move without moving a piece." })
    W.statusRow(main, function() return state.message end)
    W.section(main, "Puzzles")
    W.toggle(main, { label = "Auto Puzzle", key = "autoPuzzle", set = function(v) return setSetting("autoPuzzle",v) end,
        desc = "Open Puzzles in game. Solves and loads the next after success." })
    W.toggle(main, { label = "Auto Puzzle Sprint", key = "autoSprint", set = function(v) return setSetting("autoSprint",v) end,
        desc = "Start Sprint in game. Solves each board; native Sprint handles scoring." })
    W.note(main, "Puzzles use full-strength Stockfish and a legal provided solution when available. Shared think time / delay apply. Analysis only blocks moves. P stops all.")
    W.section(main, "Live board")
    W.statusRow(main, function() return state.bridge .. " | " .. state.kind .. " | " .. state.turn .. " to move | Ply " .. state.ply end)
    W.statusRow(main, function() return "Best move: " .. state.best .. " | Moves applied: " .. state.moves end)
    W.statusRow(main, function() return state.detail end)
    W.note(main, "Use assistance only where allowed. Online play sends the game's normal integrity telemetry.")
    local settings = Shell.page("Settings")
    W.section(settings, "Engine strength")
    W.toggle(settings, { label = "Full strength", key = "fullStrength", set = function(v) return setSetting("fullStrength", v) end,
        desc = "OFF uses the Elo target below. ON ignores it." })
    W.slider(settings, { label = "Elo target (approximate)", key = "elo", min = 1320, max = 3190, step = 10,
        set = function(v) return setSetting("elo",v) end })
    W.note(settings, "Stockfish 19 supports Elo 1320-3190. This is not a guaranteed RoChess rating.")
    W.slider(settings, { label = "Think time (ms)", key = "thinkMs", min = 50, max = 10000, step = 50,
        set = function(v) return setSetting("thinkMs",v) end })
    W.section(settings, "Move timing")
    W.slider(settings, { label = "Delay after thinking (ms)", key = "delayMs", min = 0, max = 10000, step = 50,
        set = function(v) return setSetting("delayMs",v) end })
    W.slider(settings, { label = "Random delay +/- (ms)", key = "jitterMs", min = 0, max = 5000, step = 50,
        set = function(v) return setSetting("jitterMs",v) end })
    W.note(settings, "Total = think time + delay +/- jitter, clamped near flagfall. Jitter is not detection protection.")
    W.statusRow(settings, function() return "Delay range: " .. math.max(0,cfg.delayMs-cfg.jitterMs) .. "-" .. (cfg.delayMs+cfg.jitterMs) .. " ms after search" end)
    W.section(settings, "Between games")
    W.toggle(settings, { label = "Keep chess on after teleport", key = "resumeOnTeleport", set = function(v) return setSetting("resumeOnTeleport",v) end,
        desc = "Reload Hub and resume your choice in the next RoChess game." })
    W.statusRow(settings, function() return state.teleport end)
    W.section(settings, "Connection")
    W.note(settings, "If offline: run tools/start_rochess_bridge.ps1 -Background on this PC. Settings apply to the next search.")
    W.button(settings, "Reconnect bridge", "Retry the local connection", function() state.nextHealth = 0 end)
    state.conns[#state.conns+1] = UserInputService.InputBegan:Connect(function(input, processed)
        if processed or UserInputService:GetFocusedTextBox() then return end
        if input.KeyCode == Enum.KeyCode.P then handle.panic()
        elseif input.KeyCode == Enum.KeyCode.K then destroy() end
    end)
    Shell.ready()
    handle.ready = true
    task.spawn(function()
        while state.alive do
            local tickOk, tickErr = xpcall(function()
                for _, painter in ipairs(state.live) do painter() end
                if not state.busy and os.clock() >= state.nextHealth then state.nextHealth = os.clock()+10; checkHealth() end
                tick()
            end, tostring)
            if not tickOk then handle.panic(); state.message = "Paused after error - " .. tostring(tickErr); Log.err(tickErr) end
            task.wait(0.15)
        end
    end)
    Log.info("boot " .. BUILD_VERSION .. " resumed: Chess=" .. tostring(cfg.enabled) .. " teleportContinuation=" .. tostring(continued) .. " AutoPuzzle=OFF AutoSprint=OFF fullStrength=" .. tostring(cfg.fullStrength) .. " elo=" .. cfg.elo)
end, tostring)
if not ok then Log.err(err); destroy(); error(err, 0) end
return handle
