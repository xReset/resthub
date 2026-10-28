-- Azure Latch Hub v2026-09-02.7 (2026-09-02)
-- Rungs 1-2 and 6. ESP/status are client-only. Gameplay hooks alter existing use packets only.
-- Server sees stronger kick power and potentially faster action cadence while those toggles are ON.
-- Proof: 0982.lua:203-227 (cooldowns), 0982.lua:297 and 617-876 (kick packet),
--        characters.txt, trees/ReplicatedStorage.txt:71718, 0980.lua:88-112 (awareness).
-- All gameplay toggles boot OFF every session because they affect server-visible actions.
-- Re-inject safe: self-teardown on load; P = panic; K = unload.
-- Changelog: .7 optionally promote normal kicks to the game-native full-power value 95.
--            .6 restore stock kick packets; power/curve rewrites caused server rejection.
--            .5 bypass dash()'s second state gate for forward tackle; run telemetry
--               proves repeated packets already send, so remaining run rejection is server-side.
--            .4 bind hooks onto starterPlayer.metatable.baseClient, the live controller
--               instance Rin actually calls; class-table hooks produced zero action logs.
--            .3 hook the real use() bypass for dribble/run, clear existing cooldowns,
--               correct A/D curve packet sides, and log every intercepted action.
--            .2 BLR-style gameplay, tuning, awareness and live-state sections.
--            .1 embedded R3ST panel with player and ball awareness.

local BUILD_VERSION = "2026-09-02.7"
local GKEY = "__AZURE_LATCH_HUB"
local EXPECTED_PLACE = 94647229517154
local EXPECTED_GAME = 6945584306
if game.GameId ~= EXPECTED_GAME and game.PlaceId ~= EXPECTED_PLACE then return end

local G = getgenv()
if G[GKEY] and G[GKEY].destroy then pcall(G[GKEY].destroy) end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")
if type(cloneref) == "function" then local ok, copy = pcall(cloneref, CoreGui); if ok then CoreGui = copy end end
local LocalPlayer = Players.LocalPlayer
local HOST = type(G.__R3ST_HOST) == "table" and G.__R3ST_HOST or nil
local CONFIG_FILE = "azure_latch_hub_config.json"

local function fallbackLog(message)
    pcall(function()
        local path = "logs/azure_latch_hub.log"
        local old = isfile and isfile(path) and readfile(path) or ""
        writefile(path, old .. os.date("[%Y-%m-%d %H:%M:%S] ") .. tostring(message) .. "\n")
    end)
end
local Log = { info = fallbackLog }
pcall(function() Log = loadfile("log.lua")()("azure_latch_hub") end)

local defaults = {
    noCooldowns = false, noDribbleCooldown = false, noRunCooldown = false, noTackleCooldown = false,
    stockFullPower = false, shotPower = false, shotPowerMult = 1.15, correctCurve = false,
    playerEsp = false, teamEsp = false, ballEsp = false,
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
-- Both features affect calls the server receives, so saved ON never arms them.
cfg.noCooldowns = false
cfg.noDribbleCooldown = false
cfg.noRunCooldown = false
cfg.noTackleCooldown = false
cfg.stockFullPower = false
cfg.shotPower = false
cfg.correctCurve = false
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

local state = { alive = true, conns = {}, playerMarks = {}, powerEdits = 0, cooldownSkips = 0, bypasses = 0, curves = 0 }
local clientFolder = ReplicatedStorage:WaitForChild("client")
local BaseClient = require(clientFolder:WaitForChild("baseClient"))
local originalAddCooldown = BaseClient.addCooldown
local originalFindCooldown = BaseClient.findCooldown
local originalUse = BaseClient.use
local originalSendUse = BaseClient.senduse
local addCooldownWrapper
local findCooldownWrapper
local useWrapper
local sendUseWrapper

local function actionLog(message)
    Log.info(message)
end
addCooldownWrapper = function(self, name, duration, draw)
    if cfg.noCooldowns then
        state.cooldownSkips += 1
        actionLog(string.format("cooldown skip name=%s duration=%s", tostring(name), tostring(duration)))
        return
    end
    return originalAddCooldown(self, name, duration, draw)
end
findCooldownWrapper = function(self, name)
    if cfg.noCooldowns then return false end
    return originalFindCooldown(self, name)
end
useWrapper = function(self, name, bypass)
    if cfg.noTackleCooldown and name == "dash" then
        local root = self.humanoidRootPart
        local human = self.human
        local relative = root and human and root.CFrame:VectorToObjectSpace(human.MoveDirection)
        if relative and math.abs(math.round(relative.X)) ~= 1 then
            state.bypasses += 1
            actionLog("use bypass action=tackle direct")
            return originalSendUse(self, { "tackle" })
        end
    end
    local force = (cfg.noDribbleCooldown and name == "drib") or (cfg.noRunCooldown and name == "superDash")
    if force then
        state.bypasses += 1
        actionLog("use bypass action=" .. tostring(name))
        bypass = true
    end
    return originalUse(self, name, bypass)
end
sendUseWrapper = function(self, payload)
    if type(payload) == "table" and payload[1] == "kick" then
        local character = Players.LocalPlayer.Character
        local holder = workspace:FindFirstChild("ballHolder")
        local before = holder and holder.Value
        local oldPower = payload[2]
        if cfg.stockFullPower and type(oldPower) == "number" and oldPower < 95 then
            payload = table.clone(payload)
            payload[2] = 95
            state.powerEdits += 1
        end
        actionLog(string.format("kick power=%s->%s curve=%s holder=%s kickActive=%s moveActive=%s",
            tostring(oldPower), tostring(payload[2]), tostring(payload[3]), before and before.Name or "nil",
            tostring(self.kickactived), tostring(self.moveactived)))
        task.delay(0.35, function()
            local after = holder and holder.Parent and holder.Value
            actionLog(string.format("kick result released=%s holder=%s frozen=%s noM1=%s",
                tostring(before ~= after), after and after.Name or "nil",
                tostring(character and character:GetAttribute("frozen")),
                tostring(character and character:GetAttribute("noM1kick"))))
        end)
    elseif type(payload) == "table" and (payload[1] == "dribble" or payload[1] == "run") then
        actionLog("send action=" .. tostring(payload[1]))
    end
    return originalSendUse(self, payload)
end
BaseClient.addCooldown = addCooldownWrapper
BaseClient.findCooldown = findCooldownWrapper
BaseClient.findcooldown = findCooldownWrapper
BaseClient.use = useWrapper
BaseClient.senduse = sendUseWrapper

local StarterPlayerModule = require(clientFolder:WaitForChild("starterPlayer"))
local liveBase = StarterPlayerModule and StarterPlayerModule.metatable and StarterPlayerModule.metatable.baseClient
if type(liveBase) == "table" then
    liveBase.addCooldown = addCooldownWrapper
    liveBase.addcooldown = addCooldownWrapper
    liveBase.findCooldown = findCooldownWrapper
    liveBase.findcooldown = findCooldownWrapper
    liveBase.use = useWrapper
    liveBase.senduse = sendUseWrapper
    actionLog("hooks bound target=starterPlayer.metatable.baseClient style=" .. tostring(liveBase.style))
else
    actionLog("hooks FAILED live baseClient unavailable")
end

local function connect(signal, fn)
    local c = signal:Connect(fn)
    state.conns[#state.conns + 1] = c
    return c
end
local visuals = Instance.new("Folder")
visuals.Name = "AzureLatchVisuals"
visuals.Parent = CoreGui
local ballAnchor = Instance.new("Part")
ballAnchor.Name = "BallPosition"
ballAnchor.Anchored = true
ballAnchor.CanCollide = false
ballAnchor.CanQuery = false
ballAnchor.CanTouch = false
ballAnchor.Transparency = 1
ballAnchor.Size = Vector3.new(2.5, 2.5, 2.5)
ballAnchor.Parent = workspace
local ballMark = Instance.new("Highlight")
ballMark.Name = "BallESP"
ballMark.Adornee = ballAnchor
ballMark.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
ballMark.FillColor = Color3.fromRGB(255, 255, 255)
ballMark.FillTransparency = 0.25
ballMark.OutlineColor = Color3.fromRGB(90, 205, 255)
ballMark.Enabled = cfg.ballEsp
ballMark.Parent = visuals

local function teamOf(character)
    local folder = character and character:FindFirstChild("state")
    local value = folder and folder:FindFirstChild("team")
    return value and value.Value or nil
end
local function updatePlayers()
    local myTeam = teamOf(LocalPlayer.Character)
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local character = player.Character
            local mark = state.playerMarks[player]
            if not mark and character then
                mark = Instance.new("Highlight")
                mark.Name = "AzureLatchPlayerESP"
                mark.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                mark.FillTransparency = 0.62
                mark.OutlineTransparency = 0
                mark.Parent = visuals
                state.playerMarks[player] = mark
            end
            if mark then
                local sameTeam = myTeam and teamOf(character) == myTeam
                mark.Adornee = character
                mark.FillColor = sameTeam and Color3.fromRGB(80, 170, 255) or Color3.fromRGB(255, 90, 90)
                mark.OutlineColor = Color3.new(1, 1, 1)
                mark.Enabled = character ~= nil and cfg.playerEsp and (cfg.teamEsp or not sameTeam)
            end
        end
    end
    for player, mark in next, state.playerMarks do
        if player.Parent ~= Players then mark:Destroy(); state.playerMarks[player] = nil end
    end
end
local elapsed = 0
connect(RunService.Heartbeat, function(dt)
    elapsed += dt
    if elapsed < 0.1 then return end
    elapsed = 0
    updatePlayers()
    local cfBall = ReplicatedStorage:FindFirstChild("CFBall")
    ballMark.Enabled = cfg.ballEsp and cfBall ~= nil
    if cfBall and cfBall:IsA("CFrameValue") then ballAnchor.CFrame = cfBall.Value end
end)

local screen = Instance.new("ScreenGui")
screen.Name = "AzureLatch_" .. tostring(math.random(1000, 9999))
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
local H = Kit.host({ screen = screen, root = panel, keep = { visuals } })
local W = Kit.bind({ live = {}, conns = state.conns, cfg = cfg, save = saveConfig })
W.header(panel, { title = "Azure Latch", version = BUILD_VERSION, subtitle = "Gameplay tuning and match awareness", gameId = EXPECTED_GAME, placeId = EXPECTED_PLACE })
W.page(body, { width = 720 })
W.section(body, "Gameplay")
W.toggle(body, { label = "No action cooldowns", desc = "Makes every local cooldown lookup open and clears existing entries. Server validation still applies; boots OFF.", key = "noCooldowns", set = function(v)
    cfg.noCooldowns = v
    if v then
        if liveBase and type(liveBase.cooldowntable) == "table" then table.clear(liveBase.cooldowntable) end
    end
    actionLog("toggle noCooldowns=" .. tostring(v))
end })
W.toggle(body, { label = "No dribble cooldown", desc = "Calls the game's drib action with its own local gates bypassed; boots OFF.", key = "noDribbleCooldown", set = function(v) cfg.noDribbleCooldown = v; actionLog("toggle noDribbleCooldown=" .. tostring(v)) end })
W.toggle(body, { label = "No run cooldown", desc = "Sends run through the open local path. Repeated sends are server-rejected after the first; boots OFF.", key = "noRunCooldown", set = function(v) cfg.noRunCooldown = v; actionLog("toggle noRunCooldown=" .. tostring(v)) end })
W.toggle(body, { label = "No tackle cooldown", desc = "Forward Q sends tackle before dash()'s second local state gate; side dash stays normal. Boots OFF.", key = "noTackleCooldown", set = function(v) cfg.noTackleCooldown = v; actionLog("toggle noTackleCooldown=" .. tostring(v)) end })
W.toggle(body, { label = "Force stock full power", desc = "Promotes normal kick power to the game's native full-charge value 95; boots OFF.", key = "stockFullPower", set = function(v) cfg.stockFullPower = v; actionLog("toggle stockFullPower=" .. tostring(v)) end })
W.label(body, "Kick telemetry records the requested power and whether possession released after each shot.")
W.section(body, "Awareness")
W.toggle(body, { label = "Player ESP", desc = "Highlights replicated R6 character models by team.", key = "playerEsp", set = function(v) cfg.playerEsp = v end })
W.toggle(body, { label = "Show teammates", desc = "Blue for teammates; red for opponents.", key = "teamEsp", set = function(v) cfg.teamEsp = v end })
W.toggle(body, { label = "Ball ESP", desc = "Marks the replicated CFBall position through walls.", key = "ballEsp", set = function(v) cfg.ballEsp = v; ballMark.Enabled = v end })
W.section(body, "Live match")
W.statusRow(body, function()
    local character = LocalPlayer.Character
    local stateFolder = character and character:FindFirstChild("state")
    local style = LocalPlayer:GetAttribute("style") or (stateFolder and stateFolder:FindFirstChild("style") and stateFolder.style.Value) or "unknown"
    local role = stateFolder and stateFolder:FindFirstChild("role") and stateFolder.role.Value or "unknown"
    local flow = stateFolder and stateFolder:FindFirstChild("flow") and stateFolder.flow.Value or 0
    return string.format("Style %s  ·  Role %s  ·  Flow %s%%", tostring(style), tostring(role), tostring(math.floor(tonumber(flow) or 0)))
end)
W.statusRow(body, function()
    local character = LocalPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local cfBall = ReplicatedStorage:FindFirstChild("CFBall")
    local distance = root and cfBall and cfBall:IsA("CFrameValue") and (root.Position - cfBall.Value.Position).Magnitude
    return string.format("Ball %s  ·  CD %d  ·  Bypass %d  ·  Power %d  ·  Curves %d", distance and string.format("%.0f studs", distance) or "unavailable", state.cooldownSkips, state.bypasses, state.powerEdits, state.curves)
end)
W.section(body, "Safety")
W.note(body, "P immediately disarms gameplay and visuals. No auto-action or fabricated packet is sent; hooks only alter actions you perform.")
body.CanvasSize = UDim2.fromOffset(0, W.height(body))

local function panic()
    cfg.noCooldowns = false; cfg.noDribbleCooldown = false; cfg.noRunCooldown = false; cfg.noTackleCooldown = false
    cfg.stockFullPower = false; cfg.shotPower = false; cfg.correctCurve = false
    cfg.playerEsp = false; cfg.teamEsp = false; cfg.ballEsp = false
    ballMark.Enabled = false
    for _, mark in next, state.playerMarks do mark.Enabled = false end
    saveConfig(); Log.info("panic")
end
local function destroy()
    if not state.alive then return end
    state.alive = false
    if BaseClient.addCooldown == addCooldownWrapper then BaseClient.addCooldown = originalAddCooldown end
    if BaseClient.findCooldown == findCooldownWrapper then BaseClient.findCooldown = originalFindCooldown end
    if BaseClient.findcooldown == findCooldownWrapper then BaseClient.findcooldown = originalFindCooldown end
    if BaseClient.use == useWrapper then BaseClient.use = originalUse end
    if BaseClient.senduse == sendUseWrapper then BaseClient.senduse = originalSendUse end
    if liveBase then
        if liveBase.addCooldown == addCooldownWrapper then liveBase.addCooldown = nil end
        if liveBase.addcooldown == addCooldownWrapper then liveBase.addcooldown = nil end
        if liveBase.findCooldown == findCooldownWrapper then liveBase.findCooldown = nil end
        if liveBase.findcooldown == findCooldownWrapper then liveBase.findcooldown = nil end
        if liveBase.use == useWrapper then liveBase.use = nil end
        if liveBase.senduse == sendUseWrapper then liveBase.senduse = nil end
    end
    for _, c in ipairs(state.conns) do pcall(function() c:Disconnect() end) end
    for _, mark in next, state.playerMarks do pcall(function() mark:Destroy() end) end
    pcall(function() ballAnchor:Destroy() end)
    pcall(function() visuals:Destroy() end)
    pcall(function() screen:Destroy() end)
    G[GKEY] = nil
    Log.info("unloaded " .. BUILD_VERSION)
end
H.hideBind(function() panel.Visible = not panel.Visible end)
connect(UserInputService.InputBegan, function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.P then panic() elseif input.KeyCode == Enum.KeyCode.K then destroy() end
end)
G[GKEY] = { destroy = destroy, build = BUILD_VERSION }
Log.info(string.format("boot %s gameplay=OFF resumed player=%s team=%s ball=%s power=%.2fx", BUILD_VERSION, tostring(cfg.playerEsp), tostring(cfg.teamEsp), tostring(cfg.ballEsp), cfg.shotPowerMult))
