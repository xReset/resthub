-- Volleyball Legends Hub v2026-09-01.6 (2026-09-01)
-- Rungs 1, 2, 5 and 6. Server sees normal BallService interactions from Auto Hit and
-- our character motion while air movement is enabled. Client hitboxes are locally enlarged.
-- Proof: dump 0195.lua:33-178, 0198.lua:61-197, 0201.lua:67-337, 0187.lua:99-239.
-- Auto Hit boots OFF because it can cause a server interaction. P = panic; K = unload.
-- Re-inject safe: self-teardown restores module functions, hitboxes, highlights and movement.
-- Changelog: .6 add conservative court-aware open-lane targeting.
--            .5 ignore the locally served ball until it leaves the reaction radius.
--            .4 apply camera-facing air rotation after game updates; restore AutoRotate.
--            .3 Auto Hit waits for Perfect Distance and fires once per ball approach.
--            .2 fix directional/auto-tilt precedence; add rate-limited feature telemetry.
--            .1 local embedded module with combat, hitbox, movement and look ESP controls.

local BUILD_VERSION = "2026-09-01.6"
local GKEY = "__VBL_HUB"
local EXPECTED_PLACE = 73956553001240
local EXPECTED_GAME = 6931042565

if game.GameId ~= EXPECTED_GAME and game.PlaceId ~= EXPECTED_PLACE then return end

local G = getgenv()
if G[GKEY] and G[GKEY].destroy then pcall(G[GKEY].destroy) end

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")
local LocalPlayer = Players.LocalPlayer
local HOST = type(G.__R3ST_HOST) == "table" and G.__R3ST_HOST or nil
local CONFIG_FILE = "vbl_hub_config.json"

local function fallbackLog(level, message)
    pcall(function()
        local path = "logs/vbl_hub.log"
        local old = isfile and isfile(path) and readfile(path) or ""
        writefile(path, old .. os.date("[%Y-%m-%d %H:%M:%S] ") .. level .. " " .. tostring(message) .. "\n")
    end)
end
local Log = { info = function(m) fallbackLog("INFO", m) end, warn = function(m) fallbackLog("WARN", m) end }
pcall(function() Log = loadfile("log.lua")()("vbl_hub") end)

local defaults = {
    directionalHit = false, courtAim = false, onlyJumping = false, onlyServing = false, autoTilt = false,
    diveAimbot = false, autoHit = false, reactionRadius = 14, perfectDistance = 4,
    expandHitboxes = false, hitboxScale = 1.5, noCooldown = false, cooldownDelay = 0,
    moveInAir = false, midAirRotation = false, airSpeed = 1.4, enemyLookEsp = false,
}
local cfg = table.clone(defaults)
do
    local ok, raw = pcall(readfile, CONFIG_FILE)
    if ok then
        local ok2, saved = pcall(HttpService.JSONDecode, HttpService, raw)
        if ok2 and type(saved) == "table" then
            for key, fallback in next, defaults do
                if typeof(saved[key]) == typeof(fallback) then cfg[key] = saved[key] end
            end
        end
    end
end
-- Rung-6 automation never resumes without a fresh per-session choice.
cfg.autoHit = false

local savePending = false
local function saveConfig()
    if savePending then return end
    savePending = true
    task.delay(0.5, function()
        savePending = false
        local ok, raw = pcall(HttpService.JSONEncode, HttpService, cfg)
        if ok then pcall(writefile, CONFIG_FILE, raw) end
    end)
end

local state = {
    alive = true, conns = {}, hitboxes = {}, esp = {}, lastHit = 0,
    lastTiltLog = 0, lastAirLog = 0, lastCooldownLog = 0,
    hitAttempts = 0, hitSuccess = 0, scaledHitboxes = 0,
    approachBall = nil, approachFired = false,
    rotateHumanoid = nil, originalAutoRotate = nil,
    wasServing = false, servedBall = nil,
}
local function connect(signal, fn)
    local c = signal:Connect(fn)
    state.conns[#state.conns + 1] = c
    return c
end
local function character()
    local model = LocalPlayer.Character
    return model, model and model:FindFirstChild("HumanoidRootPart"), model and model:FindFirstChildOfClass("Humanoid")
end
local function balls()
    return CollectionService:GetTagged("Ball")
end
local function nearestBall(root)
    local best, distance
    for _, ball in ipairs(balls()) do
        local part = ball:IsA("BasePart") and ball or ball.PrimaryPart
        if part then
            local d = (part.Position - root.Position).Magnitude
            if not distance or d < distance then best, distance = part, d end
        end
    end
    return best, distance or math.huge
end
local function isJumping(humanoid)
    if not humanoid then return false end
    local s = humanoid:GetState()
    return s == Enum.HumanoidStateType.Jumping or s == Enum.HumanoidStateType.Freefall
end
local function isServing()
    return LocalPlayer:GetAttribute("Context_IsServing") == true
end

local controllers = ReplicatedFirst:WaitForChild("Controllers")
local gameControllerFolder = controllers:WaitForChild("GameController")
local actions = gameControllerFolder:WaitForChild("Actions")
local moveFolder = actions:WaitForChild("Move")
local doMoveFolder = moveFolder:WaitForChild("DoMove")
local okHandlers, Handlers = pcall(require, gameControllerFolder:WaitForChild("Handlers"))
local okOrchestrator, Orchestrator = pcall(require, doMoveFolder:WaitForChild("Orchestrator"))
local okDoMove, DoMove = pcall(require, doMoveFolder)
local originalApply = okOrchestrator and Orchestrator._applyCooldown or nil

if originalApply then
    Orchestrator._applyCooldown = function(delay)
        if cfg.noCooldown then
            local applied = math.clamp(cfg.cooldownDelay, 0, 1)
            if os.clock() - state.lastCooldownLog >= 2 then
                state.lastCooldownLog = os.clock()
                Log.info(string.format("cooldown stock=%.3f applied=%.3f", tonumber(delay) or -1, applied))
            end
            return originalApply(applied)
        end
        return originalApply(delay)
    end
end

local function looksLikeClientHitbox(part)
    return part:IsA("BasePart") and part.Anchored and not part.CanCollide and not part.CanTouch
        and not part.CanQuery and part.Material == Enum.Material.Neon and part.Transparency >= 0.79
end
local function scaleHitbox(part)
    if not cfg.expandHitboxes or not looksLikeClientHitbox(part) or state.hitboxes[part] then return end
    state.hitboxes[part] = part.Size
    part.Size = part.Size * cfg.hitboxScale
    state.scaledHitboxes += 1
    Log.info(string.format("hitbox scaled #%d %.1fx size=%s", state.scaledHitboxes, cfg.hitboxScale, tostring(part.Size)))
end
connect(workspace.ChildAdded, function(child) task.defer(scaleHitbox, child) end)

local function opponent(player)
    return player ~= LocalPlayer and player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        and (not LocalPlayer.Team or player.Team ~= LocalPlayer.Team)
end
local function clearEsp(player)
    local h = state.esp[player]
    if h then h:Destroy(); state.esp[player] = nil end
end
local function updateLookEsp(root)
    for _, player in ipairs(Players:GetPlayers()) do
        if opponent(player) then
            local theirRoot = player.Character.HumanoidRootPart
            local delta = root.Position - theirRoot.Position
            local looking = delta.Magnitude > 0 and theirRoot.CFrame.LookVector:Dot(delta.Unit) > 0.8
            local h = state.esp[player]
            if cfg.enemyLookEsp and looking then
                if not h then
                    h = Instance.new("Highlight")
                    h.Name = "VBL_Looking"
                    h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                    h.FillColor = Color3.fromRGB(255, 92, 92)
                    h.FillTransparency = 0.55
                    h.OutlineColor = Color3.new(1, 1, 1)
                    h.Adornee = player.Character
                    h.Parent = player.Character
                    state.esp[player] = h
                end
            else clearEsp(player) end
        else clearEsp(player) end
    end
end

local function courtTarget()
    local court
    for _, tagged in ipairs(CollectionService:GetTagged("Courtlines")) do
        if tagged:IsA("BasePart") and tagged:IsDescendantOf(workspace) then court = tagged; break end
    end
    local net = CollectionService:GetTagged("Net")[1]
    if not court or not net or not LocalPlayer.Team then return nil end
    local index = LocalPlayer.Team:GetAttribute("Index")
    if index ~= 1 and index ~= 2 then return nil end
    local half = court.Size * 0.5
    local minX, maxX = court.Position.X - half.X + 3, court.Position.X + half.X - 3
    local minZ, maxZ = court.Position.Z - half.Z + 3, court.Position.Z + half.Z - 3
    local farZ = index == 1 and minZ or maxZ
    local targetZ = net.Position.Z + (farZ - net.Position.Z) * 0.62
    local lanes = {
        math.clamp(court.Position.X - half.X * 0.55, minX, maxX),
        math.clamp(court.Position.X, minX, maxX),
        math.clamp(court.Position.X + half.X * 0.55, minX, maxX),
    }
    local best, bestClearance
    for _, x in ipairs(lanes) do
        local candidate = Vector3.new(x, court.Position.Y, math.clamp(targetZ, minZ, maxZ))
        local clearance = math.huge
        for _, player in ipairs(Players:GetPlayers()) do
            if opponent(player) then
                local pos = player.Character.HumanoidRootPart.Position
                clearance = math.min(clearance, (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(candidate.X, 0, candidate.Z)).Magnitude)
            end
        end
        if not bestClearance or clearance > bestClearance then best, bestClearance = candidate, clearance end
    end
    return best, bestClearance or -1
end

local function setTilt(root, humanoid, ball)
    if not okHandlers or not Handlers.Values then return end
    if cfg.onlyJumping and not isJumping(humanoid) then return end
    if cfg.onlyServing and not isServing() then return end
    local direction, source, target, clearance
    -- Court Aim owns the actionable contact; Directional Hit and Auto Tilt are fallbacks.
    if cfg.courtAim and ball and (ball.Position - root.Position).Magnitude <= cfg.reactionRadius then
        target, clearance = courtTarget()
        if target then
            direction = target - ball.Position
            source = "court"
        end
    end
    if not direction and cfg.directionalHit and ball and (ball.Position - root.Position).Magnitude <= cfg.reactionRadius then
        direction = ball.Position - root.Position
        source = "ball"
    elseif not direction and cfg.autoTilt then
        direction = workspace.CurrentCamera.CFrame.LookVector
        source = "camera"
    end
    if direction and direction.Magnitude > 0 then
        Handlers.Values.TiltDirection = Vector3.new(direction.X, 0, direction.Z).Unit * 2
        if os.clock() - state.lastTiltLog >= 2 then
            state.lastTiltLog = os.clock()
            Log.info(string.format("tilt source=%s distance=%.2f jumping=%s serving=%s%s", source,
                ball and (ball.Position - root.Position).Magnitude or -1, tostring(isJumping(humanoid)), tostring(isServing()),
                target and string.format(" target=(%.1f,%.1f) clearance=%.1f", target.X, target.Z, clearance) or ""))
        end
    end
end

local function autoHit(root, humanoid, ball, distance)
    local serving = isServing()
    if serving then
        state.wasServing = true
        if ball then state.servedBall = ball end
        return
    elseif state.wasServing then
        state.wasServing = false
        if ball then state.servedBall = ball end
        if state.servedBall then Log.info("auto hit suppress served ball until exit") end
    end
    if state.servedBall then
        if not state.servedBall.Parent or (state.servedBall.Position - root.Position).Magnitude > cfg.reactionRadius + 3 then
            Log.info("auto hit served ball exited; re-armed")
            state.servedBall = nil
        elseif ball == state.servedBall then
            return
        end
    end
    if not cfg.autoHit or not okDoMove or type(DoMove) ~= "function" or not ball then
        state.approachBall = nil
        state.approachFired = false
        return
    end
    if state.approachBall ~= ball then
        state.approachBall = ball
        state.approachFired = false
    end
    if distance > cfg.reactionRadius + 3 then
        state.approachFired = false
        return
    end
    if state.approachFired or distance > cfg.perfectDistance or math.abs(ball.Position.Y - root.Position.Y) > 10 then return end
    if os.clock() - state.lastHit < 0.35 then return end
    state.lastHit = os.clock()
    state.approachFired = true
    state.hitAttempts += 1
    local action = isJumping(humanoid) and "Spike" or "Bump"
    Log.info(string.format("auto hit attempt #%d action=%s distance=%.2f threshold=%.2f", state.hitAttempts,
        action, distance, cfg.perfectDistance))
    task.spawn(function()
        local ok, err = pcall(DoMove, {
            ActionName = action,
            IsAlreadyHit = false,
            Duration = 0.2,
            Debounce = 0.35,
        })
        if ok then
            state.hitSuccess += 1
            Log.info(string.format("auto hit call ok #%d/%d", state.hitSuccess, state.hitAttempts))
        else
            state.approachFired = false
            Log.warn("auto hit failed: " .. tostring(err))
        end
    end)
end

local lastTick = 0
connect(RunService.Heartbeat, function()
    if not state.alive then return end
    local _, root, humanoid = character()
    if not root or not humanoid then return end
    local ball, distance = nearestBall(root)
    setTilt(root, humanoid, ball)
    autoHit(root, humanoid, ball, distance)
    if isJumping(humanoid) then
        local move = humanoid.MoveDirection
        if cfg.moveInAir and move.Magnitude > 0 then
            local v = root.AssemblyLinearVelocity
            local speed = humanoid.WalkSpeed * cfg.airSpeed
            root.AssemblyLinearVelocity = Vector3.new(move.X * speed, v.Y, move.Z * speed)
        end
        if (cfg.moveInAir or cfg.midAirRotation) and os.clock() - state.lastAirLog >= 2 then
            state.lastAirLog = os.clock()
            Log.info(string.format("air move=%s rotate=%s speed=%.1fx velocity=%.1f", tostring(cfg.moveInAir),
                tostring(cfg.midAirRotation), cfg.airSpeed, root.AssemblyLinearVelocity.Magnitude))
        end
        if cfg.diveAimbot and ball and distance <= cfg.reactionRadius then
            local flat = ball.Position - root.Position
            if flat.Magnitude > 0 then root.CFrame = CFrame.lookAt(root.Position, root.Position + Vector3.new(flat.X, 0, flat.Z)) end
        end
    end
    local now = os.clock()
    if now - lastTick >= 0.1 then lastTick = now; updateLookEsp(root) end
end)

-- Run after character/camera render work so the game's own controller cannot overwrite
-- the facing direction later in the same frame (dump 0195.lua:105-167).
local ROTATE_BIND = "VBL_AirRotate_" .. tostring(math.random(1000, 9999))
RunService:BindToRenderStep(ROTATE_BIND, Enum.RenderPriority.Last.Value, function()
    if not state.alive then return end
    local _, root, humanoid = character()
    if not root or not humanoid then return end
    local airborne = isJumping(humanoid)
    if cfg.midAirRotation and airborne then
        if state.rotateHumanoid ~= humanoid then
            if state.rotateHumanoid and state.rotateHumanoid.Parent and state.originalAutoRotate ~= nil then
                state.rotateHumanoid.AutoRotate = state.originalAutoRotate
            end
            state.rotateHumanoid = humanoid
            state.originalAutoRotate = humanoid.AutoRotate
        end
        humanoid.AutoRotate = false
        local look = workspace.CurrentCamera.CFrame.LookVector
        local flat = Vector3.new(look.X, 0, look.Z)
        if flat.Magnitude > 0.01 then
            flat = flat.Unit
            root.CFrame = CFrame.lookAt(root.Position, root.Position + flat)
            if os.clock() - state.lastAirLog >= 2 then
                state.lastAirLog = os.clock()
                Log.info(string.format("air rotation applied facingDot=%.3f autoRotate=%s", root.CFrame.LookVector:Dot(flat), tostring(humanoid.AutoRotate)))
            end
        end
    elseif state.rotateHumanoid then
        if state.rotateHumanoid.Parent and state.originalAutoRotate ~= nil then
            state.rotateHumanoid.AutoRotate = state.originalAutoRotate
        end
        state.rotateHumanoid = nil
        state.originalAutoRotate = nil
    end
end)

local CoreGui = game:GetService("CoreGui")
if type(cloneref) == "function" then local ok, copy = pcall(cloneref, CoreGui); if ok then CoreGui = copy end end
local screen = Instance.new("ScreenGui")
screen.Name = "VBL_" .. tostring(math.random(1000, 9999))
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.DisplayOrder = 2147483647
screen.Parent = CoreGui
local panel = Instance.new("Frame")
panel.Size = UDim2.fromOffset(760, 610)
panel.Position = UDim2.new(0.5, -380, 0.5, -305)
panel.BackgroundColor3 = Color3.fromRGB(9, 9, 11)
panel.BorderSizePixel = 0
panel.Parent = screen
local body = Instance.new("ScrollingFrame")
body.Position = UDim2.fromOffset(18, 76)
body.Size = UDim2.new(1, -36, 1, -130)
body.BackgroundTransparency = 1
body.BorderSizePixel = 0
body.ScrollBarThickness = 4
body.Parent = panel

local Kit = (HOST and HOST.ui) or loadfile("../scripts/r3st_ui.lua")()
local H = Kit.host({ screen = screen, root = panel })
local W = Kit.bind({ live = {}, conns = state.conns, cfg = cfg, save = saveConfig })
W.header(panel, { title = "Volleyball Legends", version = BUILD_VERSION, subtitle = "Dump-backed match assists", gameId = EXPECTED_GAME, placeId = EXPECTED_PLACE })
W.page(body, { width = 720 })
W.section(body, "Combat")
W.toggle(body, { label = "Directional hit", key = "directionalHit", set = function(v) cfg.directionalHit = v end })
W.toggle(body, { label = "Court aim", desc = "Targets the clearest safe lane on the opponent half.", key = "courtAim", set = function(v) cfg.courtAim = v end })
W.toggle(body, { label = "Only while jumping", key = "onlyJumping", set = function(v) cfg.onlyJumping = v end })
W.toggle(body, { label = "Only while serving", key = "onlyServing", set = function(v) cfg.onlyServing = v end })
W.toggle(body, { label = "Auto tilt", key = "autoTilt", set = function(v) cfg.autoTilt = v end })
W.toggle(body, { label = "Dive aimbot", key = "diveAimbot", set = function(v) cfg.diveAimbot = v end })
W.toggle(body, { label = "Enable auto hit", key = "autoHit", set = function(v) cfg.autoHit = v end })
W.slider(body, { label = "Reaction radius", min = 5, max = 25, step = 1, key = "reactionRadius", get = function() return cfg.reactionRadius end, set = function(v) cfg.reactionRadius = v end, fmt = function(v) return string.format("%d studs", v) end })
W.slider(body, { label = "Perfect distance", min = 1, max = 8, step = 1, key = "perfectDistance", get = function() return cfg.perfectDistance end, set = function(v) cfg.perfectDistance = v end, fmt = function(v) return string.format("%d studs", v) end })
W.section(body, "Hitbox")
W.toggle(body, { label = "Expand hitboxes", key = "expandHitboxes", set = function(v) cfg.expandHitboxes = v end })
W.slider(body, { label = "Hitbox scale", min = 1, max = 4, step = 0.1, get = function() return cfg.hitboxScale end, set = function(v) cfg.hitboxScale = v end, fmt = function(v) return string.format("%.1fx", v) end })
W.toggle(body, { label = "No cooldown", key = "noCooldown", set = function(v) cfg.noCooldown = v end })
W.slider(body, { label = "No cooldown delay", min = 0, max = 1, step = 0.05, get = function() return cfg.cooldownDelay end, set = function(v) cfg.cooldownDelay = v end, fmt = function(v) return string.format("%.2fs", v) end })
W.section(body, "Movement")
W.toggle(body, { label = "Move in air", key = "moveInAir", set = function(v) cfg.moveInAir = v end })
W.toggle(body, { label = "Mid-air rotation", key = "midAirRotation", set = function(v) cfg.midAirRotation = v end })
W.slider(body, { label = "Air speed", min = 1, max = 3, step = 0.1, get = function() return cfg.airSpeed end, set = function(v) cfg.airSpeed = v end, fmt = function(v) return string.format("%.1fx", v) end })
W.section(body, "Visuals")
W.toggle(body, { label = "Enemy look ESP", key = "enemyLookEsp", set = function(v) cfg.enemyLookEsp = v end })
W.note(body, "Auto roll and infinite lucky spins are omitted: rolls and spin balances are server-authoritative (0528.lua:637-718).")
body.CanvasSize = UDim2.fromOffset(0, W.height(body))

local function panic()
    cfg.autoHit = false; cfg.moveInAir = false; cfg.midAirRotation = false
    cfg.directionalHit = false; cfg.courtAim = false; cfg.autoTilt = false; cfg.diveAimbot = false
    saveConfig(); Log.info("panic")
end
local function destroy()
    if not state.alive then return end
    state.alive = false
    panic()
    RunService:UnbindFromRenderStep(ROTATE_BIND)
    if state.rotateHumanoid and state.rotateHumanoid.Parent and state.originalAutoRotate ~= nil then
        state.rotateHumanoid.AutoRotate = state.originalAutoRotate
    end
    if originalApply and Orchestrator._applyCooldown ~= originalApply then Orchestrator._applyCooldown = originalApply end
    for part, size in next, state.hitboxes do if part.Parent then pcall(function() part.Size = size end) end end
    for player in next, state.esp do clearEsp(player) end
    for _, c in ipairs(state.conns) do pcall(function() c:Disconnect() end) end
    if screen then screen:Destroy() end
    G[GKEY] = nil
    Log.info("unloaded " .. BUILD_VERSION)
end
H.hideBind(function() panel.Visible = not panel.Visible end)
connect(UserInputService.InputBegan, function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.P then panic() elseif input.KeyCode == Enum.KeyCode.K then destroy() end
end)
G[GKEY] = { destroy = destroy, build = BUILD_VERSION }
Log.info(string.format("boot %s autoHit=OFF resumed directional=%s courtAim=%s autoTilt=%s hitbox=%s cooldown=%s air=%s rotate=%s esp=%s",
    BUILD_VERSION, tostring(cfg.directionalHit), tostring(cfg.courtAim), tostring(cfg.autoTilt), tostring(cfg.expandHitboxes),
    tostring(cfg.noCooldown), tostring(cfg.moveInAir), tostring(cfg.midAirRotation), tostring(cfg.enemyLookEsp)))
