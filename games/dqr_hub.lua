-- Dungeon Quest Reborn Hub v2026-09-02.24 (2026-09-02)
-- Rungs 1-6. Server sees: normal ability calls while Auto Abilities is ON, a normal readyUp call
-- while Auto Ready is ON, and our own character
-- motion (we hold network ownership of our HumanoidRootPart — network_ownership.txt, OWNED PARTS).
-- Proof: 0408.lua:37-160 (PrecastHitbox builds every enemy attack volume locally with
-- cframe/size/delayUntilAttack/startTime and dispatches through the module table it returns),
-- 0103.lua:3793-3821 (boss movement-integrity self-report), 0082.lua:15-31 (wave/difficulty),
-- 0451.lua:13-17 (readyUp), trees/Workspace.txt:8-286 (run values, enemyFolder, aggroRange,
-- playerSpawn parts used by Fix Me).
--
-- EVERY toggle resumes exactly as the user left it. This overrides the usual boot-OFF rule for
-- rung 6 (potassium-dev §0.2b) on the user's explicit standing instruction 2026-08-26 ("make sure
-- every feature autoloads"). The boot log names everything that came back armed; P disarms all.
--
-- LOUD FEATURES, know what they look like to a bystander:
--   Auto Dodge steps your character out of an attack volume the instant before it lands.
--   Walkspeed above ~30 is motion no legitimate client produces.
-- Both are your character's own motion under your network ownership (rung 5), visible to everyone.
--
-- H = Fix Me (unstick — NOT F, the game binds F to its own ability-set swap, 0085.lua:1408).
-- LeftAlt = toggle Auto Abilities.
-- P = panic; K = unload; Insert / RShift = panel.
-- Re-inject safe: self-teardown on load; speed, PrecastHitbox wrappers, telegraph markers and mob
-- adornments are all restored on unload.
-- DETECTED 2026-09-02: Walkspeed booted at 132 immediately before server anti-cheat kick.
-- Walkspeed is disabled until new evidence establishes a server-accepted path.
-- Changelog:
--  .24 Disable detected Walkspeed; move every active control onto the shared R3ST kit.
--  .23 Removed teleport re-injection and its coupled broken-replay auto-rejoin path.
--  .17 LeftAlt toggles Auto Abilities.
--  .16 Fix Me skips the roof directly under the player and searches for the lower map floor.
--  .15 Fix Me now lands on collidable geometry below the player and never uses playerSpawn.
--  .14 Auto Abilities: alternates q and e and fires each the instant its own cooldown hits zero.
--      No set switching. Does not try to beat the cooldown — probe stage C proved the server owns
--      it — it just never leaves one sitting ready.
--  .13 measured that server-side cooldown; Fix Me moved F -> H (F is the game's own swap bind)
--  .12 REMOVED Kill Aura, Fast M1 and the blink entirely — the blink stranded the character (a
--      respawn mid-blink moved the NEW character to the OLD origin, and a restore into geometry
--      wedged it). Added Fix Me (F): clears PlatformStand/Sit/anchor/velocity, restores HipHeight
--      and WalkSpeed, then puts you on the nearest playerSpawn, or on the floor directly below.
--  .11 walkspeed slider max 120 -> 240
--  .10 Kill Aura blink range; Auto Dodge via PrecastHitbox wrap; removed Auto Aim + Abilities;
--      RShift hides panel; every toggle autoloads
--   .9 mob ESP labels show the server's own aggroRange (trees/Workspace.txt:286)
--   .8 FIX mob ESP/chams regression
--   .7 telegraph overlay, run HUD, drop feed, boss integrity guard, auto-ready
--   .1 mob ESP/chams, walkspeed

local BUILD_VERSION = "2026-09-02.24"
local GKEY = "__DQR_HUB"

-- hub.lua publishes __R3ST_HOST immediately before running us and clears it the
-- moment we return. When it is set, the hub owns the ScreenGui, the window
-- chrome, the drag and RightShift, so the CONTROL PANEL renders inside its
-- content host. The ESP/visual layer is deliberately left alone: it has to stay
-- a full-screen CoreGui layer, never a child of a hub panel.
local __HUBENV = (type(getgenv) == "function" and getgenv()) or _G
local HOST = (type(__HUBENV.__R3ST_HOST) == "table"
	and typeof(__HUBENV.__R3ST_HOST.host) == "Instance") and __HUBENV.__R3ST_HOST or nil

local CONFIG_FILE = "dqr_hub_config.json"

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

local CoreGui = game:GetService("CoreGui")
if type(cloneref) == "function" then
    local ok, copy = pcall(cloneref, CoreGui)
    if ok and copy then CoreGui = copy end
end

local G = getgenv()
if G[GKEY] and G[GKEY].destroy then pcall(G[GKEY].destroy) end

local function fallbackLog()
    local function write(level, message)
        pcall(function()
            local path = "logs/dqr_hub.log"
            local old = isfile and isfile(path) and readfile(path) or ""
            writefile(path, old .. os.date("[%Y-%m-%d %H:%M:%S] ") .. level .. " " .. tostring(message) .. "\n")
        end)
    end
    return {
        info = function(message) write("INFO", message) end,
        warn = function(message) write("WARN", message) end,
        err = function(message) write("ERROR", message) end,
    }
end

local Log = fallbackLog()
pcall(function()
    local factory = loadfile("log.lua")()
    Log = factory("dqr_hub")
end)

-- ---------------------------------------------------------------- config

local defaults = {
    esp = true,
    telegraph = true,
    autoDodge = false,
    runHud = true,
    dropFeed = true,
    integrityGuard = true,
    speed = false,
    autoReady = false,
    autoAbilities = false,
    dodgeLead = 0.15,
    walkSpeed = 20,
    panelX = 24,
    panelY = 220,
}
local settings = table.clone(defaults)

local function loadConfig()
    local ok, raw = pcall(readfile, CONFIG_FILE)
    if not ok then return end
    local ok2, saved = pcall(HttpService.JSONDecode, HttpService, raw)
    if not ok2 or type(saved) ~= "table" then return end
    for key, fallback in next, defaults do
        if typeof(saved[key]) == typeof(fallback) then settings[key] = saved[key] end
    end
end
-- Standing user instruction 2026-08-26: every feature autoloads, remote-firing ones included.
loadConfig()
-- Recorded enforcement overrides the old resume instruction: Roblox logged
-- "Kicked by anti-cheat" after this feature resumed at 132 on 2026-09-02.
settings.speed = false

local saveQueued = false
local function saveConfig()
    if saveQueued then return end
    saveQueued = true
    task.delay(0.5, function()
        saveQueued = false
        local snapshot = {}
        for key in next, defaults do snapshot[key] = settings[key] end
        local ok, payload = pcall(HttpService.JSONEncode, HttpService, snapshot)
        if ok then pcall(writefile, CONFIG_FILE, payload) end
    end)
end

-- ---------------------------------------------------------------- state

local state = {
    alive = true,
    connections = {},
    mobs = {},
    folders = {},
    marks = {},
    markCount = 0,
    drops = {},
    gui = nil,
    blinking = false,
    dodges = 0,
    speedHumanoid = nil,
    originalWalkSpeed = nil,
    stock = { walkSpeed = 16, hipHeight = 0, jumpPower = 50, platformStand = false, rootSize = 4.24 },
    inDanger = false,
    lastReady = "",
}

local function connect(signal, callback)
    local connection = signal:Connect(callback)
    state.connections[#state.connections + 1] = connection
    return connection
end

local function remote(name)
    local folder = ReplicatedStorage:FindFirstChild("remotes")
    return folder and folder:FindFirstChild(name) or nil
end

local function myRoot()
    local character = LocalPlayer.Character
    return character and character:FindFirstChild("HumanoidRootPart") or nil
end

-- ---------------------------------------------------------------- mob ESP

local function isMob(model)
    if not model:IsA("Model") then return false end
    if not model:FindFirstChildOfClass("Humanoid") or not model:FindFirstChild("HumanoidRootPart") then return false end
    local parent = model.Parent
    return parent ~= nil and parent.Name == "enemyFolder"
end

local function unbindMob(model)
    local record = state.mobs[model]
    if not record then return end
    if record.highlight then record.highlight:Destroy() end
    if record.label then record.label:Destroy() end
    state.mobs[model] = nil
end

local function bindMob(model)
    if state.mobs[model] or not isMob(model) then return end
    local highlight = Instance.new("Highlight")
    highlight.Name = "DQR_Mob"
    highlight.Adornee = model
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.FillColor = Color3.fromRGB(255, 72, 72)
    highlight.FillTransparency = 0.55
    highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
    highlight.OutlineTransparency = 0
    highlight.Enabled = settings.esp
    highlight.Parent = state.gui

    local label = Instance.new("BillboardGui")
    label.Name = "DQR_MobInfo"
    label.Adornee = model.HumanoidRootPart
    label.AlwaysOnTop = true
    label.Size = UDim2.fromOffset(190, 42)
    label.StudsOffset = Vector3.new(0, 3.2, 0)
    label.Enabled = settings.esp
    label.Parent = state.gui
    local text = Instance.new("TextLabel")
    text.BackgroundTransparency = 1
    text.Size = UDim2.fromScale(1, 1)
    text.Font = Enum.Font.GothamBold
    text.TextSize = 13
    text.TextColor3 = Color3.new(1, 1, 1)
    text.TextStrokeTransparency = 0.25
    text.Parent = label

    state.mobs[model] = { highlight = highlight, label = label, text = text }
end

local function bindFolder(folder)
    if state.folders[folder] then return end
    state.folders[folder] = true
    for _, child in ipairs(folder:GetChildren()) do bindMob(child) end
    connect(folder.ChildAdded, function(child) task.defer(bindMob, child) end)
end

local mobRoots = { "dungeon", "enemies", "enemyPool" }

local function scanFolders()
    local found = 0
    for _, name in ipairs(mobRoots) do
        local root = workspace:FindFirstChild(name)
        if root then
            for _, descendant in ipairs(root:GetDescendants()) do
                if descendant:IsA("Folder") and descendant.Name == "enemyFolder" then
                    bindFolder(descendant)
                elseif isMob(descendant) then
                    bindMob(descendant)
                    found += 1
                end
            end
        end
    end
    -- Mob counts churn constantly as rooms stream; log only a real change, at most every 10s,
    -- or this line buries every other piece of telemetry in the file.
    local now = os.clock()
    if math.abs(found - (state.lastFound or -1)) >= 5 and now - (state.lastFoundLog or 0) > 10 then
        state.lastFound, state.lastFoundLog = found, now
        Log.info("mob scan bound=" .. found)
    end
end

local function nearestMob(maxRange)
    local playerRoot = myRoot()
    if not playerRoot then return nil end
    local best, bestDistance
    for model in next, state.mobs do
        local humanoid = model:FindFirstChildOfClass("Humanoid")
        local root = model:FindFirstChild("HumanoidRootPart")
        if humanoid and humanoid.Health > 0 and root then
            local distance = (root.Position - playerRoot.Position).Magnitude
            if distance <= maxRange and (not bestDistance or distance < bestDistance) then
                best, bestDistance = model, distance
            end
        end
    end
    return best, bestDistance
end

-- ---------------------------------------------------------------- telegraph + auto dodge

-- PrecastHitbox returns a module table whose Cube/Circle entries the bridge handler indexes on
-- every enemy attack (0408.lua:132-135). Wrapping those two entries hands us the server's exact
-- geometry and impact time before the game draws anything. Restored on unload, ownership-checked.
local Precast, origCube, origCircle
local wrapCube, wrapCircle

local function looksLikeTelegraph(part)
    return part:IsA("BasePart") and part.Anchored and not part.CanCollide
        and not part.CanQuery and not part.CanTouch and part.Material == Enum.Material.Neon
end

local function dropMark(source)
    local mark = state.marks[source]
    if not mark then return end
    if mark.part then mark.part:Destroy() end
    if mark.conn then pcall(function() mark.conn:Disconnect() end) end
    state.marks[source] = nil
    state.markCount -= 1
end

local function addMark(source)
    if state.marks[source] or not settings.telegraph then return end
    if state.markCount >= 40 then return end
    local part = Instance.new("Part")
    part.Name = "DQR_Warn"
    part.Anchored = true
    part.CanCollide = false
    part.CanQuery = false
    part.CanTouch = false
    part.Material = Enum.Material.Neon
    part.Color = Color3.fromRGB(255, 60, 60)
    part.Transparency = 0.72
    part.Shape = source.Shape
    part.Size = source.Size
    part.CFrame = source.CFrame
    part.Parent = workspace
    state.markCount += 1
    state.marks[source] = {
        part = part,
        conn = source.AncestryChanged:Connect(function(_, parent)
            if not parent then dropMark(source) end
        end),
    }
end

local function clearMarks()
    for source in next, state.marks do dropMark(source) end
    state.markCount = 0
end

-- Move the root out of a volume by the shortest route, capped so this stays a sidestep.
local function escapeTo(position)
    local root = myRoot()
    if not root or not position then return false end
    local distance = (position - root.Position).Magnitude
    if distance > 60 then return false end
    root.CFrame = CFrame.new(position) * (root.CFrame - root.CFrame.Position)
    return true
end

local function dodgeCube(cframe, size)
    local root = myRoot()
    if not root then return end
    local localPos = cframe:PointToObjectSpace(root.Position)
    local half = size * 0.5
    if math.abs(localPos.X) > half.X or math.abs(localPos.Z) > half.Z then return end
    if math.abs(localPos.Y) > half.Y + 8 then return end
    local outX = half.X - math.abs(localPos.X)
    local outZ = half.Z - math.abs(localPos.Z)
    local target
    if outX < outZ then
        local sign = localPos.X >= 0 and 1 or -1
        target = cframe:PointToWorldSpace(Vector3.new(sign * (half.X + 4), localPos.Y, localPos.Z))
    else
        local sign = localPos.Z >= 0 and 1 or -1
        target = cframe:PointToWorldSpace(Vector3.new(localPos.X, localPos.Y, sign * (half.Z + 4)))
    end
    if escapeTo(target) then
        state.dodges += 1
        Log.info(string.format("dodge cube out=%.1f", math.min(outX, outZ)))
    end
end

local function dodgeCircle(center, radius)
    local root = myRoot()
    if not root then return end
    local flat = Vector3.new(root.Position.X - center.X, 0, root.Position.Z - center.Z)
    if flat.Magnitude > radius then return end
    local direction = flat.Magnitude > 0.1 and flat.Unit or Vector3.new(1, 0, 0)
    local target = Vector3.new(center.X, root.Position.Y, center.Z) + direction * (radius + 4)
    if escapeTo(target) then
        state.dodges += 1
        Log.info(string.format("dodge circle radius=%.1f", radius))
    end
end

-- startTime/delayUntilAttack are in workspace:GetServerTimeNow() terms (0408.lua:96-100).
local function scheduleDodge(handler, delayUntilAttack, startTime)
    if not settings.autoDodge then return end
    if type(delayUntilAttack) ~= "number" or type(startTime) ~= "number" then return end
    local wait = (startTime + delayUntilAttack) - workspace:GetServerTimeNow() - settings.dodgeLead
    task.delay(math.max(wait, 0), function()
        if state.alive and settings.autoDodge then pcall(handler) end
    end)
end

local function installPrecastWrap()
    if Precast then return end
    local ok, module = pcall(function()
        local modules = ReplicatedStorage:WaitForChild("modules", 5)
        return modules and require(modules:WaitForChild("PrecastHitbox", 5))
    end)
    if not ok or type(module) ~= "table" then
        Log.warn("PrecastHitbox wrap unavailable — auto dodge and exact timing are off")
        return
    end
    Precast = module
    origCube, origCircle = module.Cube, module.Circle

    wrapCube = function(cframe, size, delayUntilAttack, startTime, properties)
        if typeof(cframe) == "CFrame" and typeof(size) == "Vector3" then
            scheduleDodge(function() dodgeCube(cframe, size) end, delayUntilAttack, startTime)
        end
        return origCube(cframe, size, delayUntilAttack, startTime, properties)
    end
    wrapCircle = function(position, radius, delayUntilAttack, startTime, properties)
        if typeof(position) == "Vector3" and type(radius) == "number" then
            scheduleDodge(function() dodgeCircle(position, radius) end, delayUntilAttack, startTime)
        end
        return origCircle(position, radius, delayUntilAttack, startTime, properties)
    end

    module.Cube, module.Circle = wrapCube, wrapCircle
    Log.info("PrecastHitbox wrapped (auto dodge armed)")
end

local function removePrecastWrap()
    if not Precast then return end
    if Precast.Cube == wrapCube then Precast.Cube = origCube end
    if Precast.Circle == wrapCircle then Precast.Circle = origCircle end
    Precast = nil
end

local function dangerNow()
    local root = myRoot()
    if not root or state.markCount == 0 then return false end
    for source in next, state.marks do
        if source.Parent then
            local localPos = source.CFrame:PointToObjectSpace(root.Position)
            local half = source.Size * 0.5
            if math.abs(localPos.X) <= half.X and math.abs(localPos.Y) <= half.Y + 8 and math.abs(localPos.Z) <= half.Z then
                return true
            end
        end
    end
    return false
end

-- ---------------------------------------------------------------- fix me (unstick)

-- Kill Aura's blink stranded the character (v.11 and earlier): if the character respawned during
-- a blink, the delayed restore moved the NEW character back to the OLD origin, and a restore into
-- room geometry left the player wedged. The feature is gone; this puts the character back.
-- Rung 5 — our own character, under our own network ownership. No remote, no server request.
-- Drop straight down onto collidable map geometry, ignoring our own character.
local function groundBelow(root)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local excluded = { LocalPlayer.Character }
    params.FilterDescendantsInstances = excluded
    local origin = root.Position + Vector3.new(0, 10, 0)
    for _ = 1, 24 do
        local hit = workspace:Raycast(origin, Vector3.new(0, -5000, 0), params)
        if not hit then return nil end
        local drop = root.Position.Y - hit.Position.Y
        if hit.Instance.CanCollide and drop >= 12 then
            return hit.Position, hit.Instance, drop
        end
        table.insert(excluded, hit.Instance)
        params.FilterDescendantsInstances = excluded
        origin = hit.Position - Vector3.new(0, 0.05, 0)
    end
    return nil
end

local function fixMe()
    local character = LocalPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not root or not humanoid then
        Log.warn("fix me: no character")
        return
    end

    -- 1. clear every state that pins a character in place
    state.blinking = false
    root.Anchored = false
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
    humanoid.PlatformStand = false
    humanoid.Sit = false
    if humanoid:GetState() ~= Enum.HumanoidStateType.Dead then
        humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
    end
    humanoid.WalkSpeed = settings.speed and settings.walkSpeed or (state.originalWalkSpeed or 16)
    humanoid.HipHeight = state.stock.hipHeight

    -- 2. land on actual geometry below us. Never use playerSpawn: it can sit above the map.
    local ground, groundPart, groundDrop = groundBelow(root)
    local destination = ground and (ground + Vector3.new(0, 4, 0)) or nil
    if destination then
        root.CFrame = CFrame.new(destination) * (root.CFrame - root.CFrame.Position)
    end

    Log.info(string.format("fix me: floor=%s drop=%s moved=%s",
        groundPart and groundPart:GetFullName() or "none",
        groundDrop and string.format("%.1f", groundDrop) or "-",
        tostring(destination ~= nil)))
end

-- ---------------------------------------------------------------- auto abilities

-- The server owns ability cooldowns and refuses an early cast on the same tool — measured, not
-- assumed: dqr_ability_probe stage C fired five casts with cooldown and busyCasting zeroed
-- locally and the countdown never restarted once (those values are server-owned, so the writes
-- never left this machine; 0068.lua:157-166 only reads them for the UI).
-- So this does not try to beat the cooldown. It just never wastes one: it alternates q and e and
-- fires each the moment its own countdown hits zero, using the game's exact call shape
-- (0013.lua:54-89 — localEvent:Fire() then abilityUsed:FireServer(slot, tool)).
local function abilityTool(slot)
    for _, source in ipairs({ LocalPlayer.Backpack, LocalPlayer.Character }) do
        if source then
            for _, child in ipairs(source:GetChildren()) do
                local abilitySlot = child:IsA("Tool") and child:FindFirstChild("abilitySlot")
                if abilitySlot and abilitySlot.Value == slot then return child end
            end
        end
    end
end

local function castSlot(slot)
    local tool = abilityTool(slot)
    if not tool then return false end
    local cooldown = tool:FindFirstChild("cooldown")
    local localEvent = tool:FindFirstChild("localEvent")
    if not localEvent or not cooldown or cooldown.Value > 0 then return false end
    local abilityUsed = remote("abilityUsed")
    if not abilityUsed then return false end
    localEvent:Fire()
    abilityUsed:FireServer(slot, tool)
    state.casts = (state.casts or 0) + 1
    Log.info(string.format("auto ability %s slot=%s cooldownLength=%s", tool.Name, slot,
        tostring(tool:FindFirstChild("cooldownLength") and tool.cooldownLength.Value or "-")))
    return true
end

local function autoAbilities()
    if not settings.autoAbilities then return end
    local character = LocalPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local busy = character and character:FindFirstChild("busyCasting")
    if not humanoid or humanoid.Health <= 0 or not busy or busy.Value then return end
    -- the game refuses to act in town (0013.lua:91); firing there is pointless server traffic
    local peaceful = LocalPlayer:FindFirstChild("peaceful")
    if peaceful and peaceful.Value == true then return end
    -- one cast per ~0.35s at most, so a double-ready pair does not go out on the same frame
    local now = os.clock()
    if now - (state.lastCast or 0) < 0.35 then return end

    -- alternate: try the slot whose turn it is, fall back to the other
    local first = state.nextSlot == "e" and "e" or "q"
    local second = first == "q" and "e" or "q"
    if castSlot(first) then
        state.nextSlot, state.lastCast = second, now
    elseif castSlot(second) then
        state.nextSlot, state.lastCast = first, now
    end
end

local function autoReady()
    if not settings.autoReady then return end
    local progress = workspace:FindFirstChild("dungeonProgress")
    local value = progress and tostring(progress.Value) or ""
    if value == "" or value == "inProgress" or value == state.lastReady then return end
    local readyUp = remote("readyUp")
    if not readyUp then return end
    state.lastReady = value
    readyUp:FireServer()
    Log.info("auto ready fired at progress=" .. value)
end

-- ---------------------------------------------------------------- speed + integrity guard

local function applySpeed()
    if not settings.speed then return end
    local character = LocalPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end
    if state.speedHumanoid ~= humanoid then
        state.speedHumanoid = humanoid
        state.originalWalkSpeed = humanoid.WalkSpeed
        state.stock.walkSpeed = humanoid.WalkSpeed
        state.stock.hipHeight = humanoid.HipHeight
        state.stock.jumpPower = humanoid.UseJumpPower and humanoid.JumpPower or humanoid.JumpHeight
        local root = character:FindFirstChild("HumanoidRootPart")
        if root then state.stock.rootSize = root.Size.Magnitude end
    end
    humanoid.WalkSpeed = settings.walkSpeed
end

local function restoreSpeed()
    local humanoid = state.speedHumanoid
    if humanoid and humanoid.Parent and humanoid.WalkSpeed == settings.walkSpeed then
        humanoid.WalkSpeed = state.originalWalkSpeed or 16
    end
    state.speedHumanoid = nil
    state.originalWalkSpeed = nil
end

-- Two bosses ask the client to self-report WalkSpeed/HipHeight/jump/PlatformStand/root size and
-- the client answers honestly (0103.lua:3793-3821). The game handler is connected at load, so it
-- runs before ours in the same frame — the only place to correct the answer is on the way out.
local function installIntegrityGuard()
    if state.hooked or type(hookmetamethod) ~= "function" then return end
    local ok = pcall(function()
        local original
        original = hookmetamethod(game, "__namecall", function(self, ...)
            if state.alive and settings.integrityGuard and getnamecallmethod() == "FireServer"
                and typeof(self) == "Instance" and self.Name:match("BossSpecficEvents$") then
                local payload = ...
                if type(payload) == "table" then
                    for _, entry in next, payload do
                        if type(entry) == "table" and entry.walkSpeed ~= nil then
                            entry.walkSpeed = state.stock.walkSpeed
                            entry.hipHeight = state.stock.hipHeight
                            entry.jumpPower = state.stock.jumpPower
                            entry.platformStand = state.stock.platformStand
                            if entry.rootSizeMagnitude ~= nil then entry.rootSizeMagnitude = state.stock.rootSize end
                            Log.info("integrity guard sanitised " .. self.Name)
                        end
                    end
                end
            end
            return original(self, ...)
        end)
        state.hooked = true
    end)
    if not ok then Log.warn("integrity guard install failed") end
end

-- ---------------------------------------------------------------- panel

local uiLive = {}
local destroy

local Kit = HOST and HOST.ui or nil
if not Kit then
    for _, path in ipairs({ "../scripts/r3st_ui.lua", "r3st_ui.lua", "scripts/r3st_ui.lua" }) do
        local ok, loaded = pcall(loadfile, path)
        if ok and type(loaded) == "function" then
            local ok2, value = pcall(loaded)
            if ok2 and type(value) == "table" then Kit = value; break end
        end
    end
end
if not Kit then error("R3ST UI kit unavailable") end

local screen = Instance.new("ScreenGui")
screen.Name = "DQR_" .. tostring(math.random(1000, 9999))
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.ZIndexBehavior = Enum.ZIndexBehavior.Global
screen.DisplayOrder = 2147483647
pcall(sethiddenproperty, screen, "OnTopOfCoreBlur", true)
screen.Parent = CoreGui
state.gui = screen

local panel = Instance.new("Frame")
panel.Position = UDim2.fromOffset(settings.panelX, settings.panelY)
panel.Size = UDim2.fromOffset(760, 580)
panel.BackgroundColor3 = Kit.COL.bg
panel.BorderSizePixel = 0
panel.Active = true
panel.Draggable = not HOST
panel.Parent = screen
if not HOST then
    Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 12)
    Instance.new("UIStroke", panel).Color = Kit.COL.line
end

local H = Kit.host({ screen = screen, root = panel, keep = { screen } })
local hideConn = H.hideBind(function() panel.Visible = not panel.Visible end)
if hideConn then state.connections[#state.connections + 1] = hideConn end

local inner = Instance.new("Frame")
inner.BackgroundTransparency = 1
inner.BorderSizePixel = 0
inner.Position = UDim2.fromOffset(16, 12)
inner.Size = UDim2.new(1, -32, 1, -24)
inner.Parent = panel

local W = Kit.bind({
    live = uiLive,
    conns = state.connections,
    cfg = settings,
    save = saveConfig,
    guard = function(what, fn, ...)
        local ok, result = pcall(fn, ...)
        if not ok then Log.err(tostring(what) .. ": " .. tostring(result)) end
        return ok, result
    end,
})

W.header(inner, {
    title = "Dungeon Quest Reborn",
    version = "v" .. BUILD_VERSION,
    subtitle = "Dungeon awareness, automatic defense and ability timing.",
    gameId = 9931749389,
    placeId = 77649408247578,
})

local body = Instance.new("ScrollingFrame")
body.Name = "Controls"
body.BackgroundTransparency = 1
body.BorderSizePixel = 0
body.Position = UDim2.fromOffset(0, 84)
body.Size = UDim2.new(1, 0, 1, -136)
body.ScrollBarThickness = 3
body.ScrollBarImageColor3 = Kit.COL.line
body.CanvasSize = UDim2.new()
body.Parent = inner
W.page(body, { width = 718 })

local function setToggle(key, value)
    settings[key] = value and true or false
    saveConfig()
    if key == "esp" then
        for _, record in next, state.mobs do
            record.highlight.Enabled = settings[key]
            record.label.Enabled = settings[key]
        end
    elseif key == "telegraph" and not settings[key] then
        clearMarks()
    elseif key == "autoDodge" and settings[key] then
        installPrecastWrap()
    elseif key == "speed" then
        if settings[key] then applySpeed() else restoreSpeed() end
    elseif key == "autoReady" then
        state.lastReady = ""
    end
    Log.info(key .. "=" .. (settings[key] and "ON" or "OFF"))
end

local function addToggle(key, label, desc)
    W.toggle(body, {
        label = label,
        desc = desc,
        key = key,
        get = function() return settings[key] end,
        set = function(value) setToggle(key, value) end,
    })
end

W.section(body, "Awareness")
addToggle("esp", "Mob ESP + chams", "Names, health, distance and server aggro range")
addToggle("telegraph", "Attack telegraph overlay", "Shows the game's local attack volumes")
addToggle("runHud", "Run HUD", "Wave, tier, progress, time and mob count")
addToggle("dropFeed", "Drop feed", "Keeps the two newest announced drops")

W.section(body, "Automation")
addToggle("autoDodge", "Auto dodge", "Moves your character just before a telegraphed hit")
addToggle("integrityGuard", "Boss integrity guard", "Sanitizes the boss client self-report")
addToggle("autoReady", "Auto ready", "Sends the normal ready-up call")
addToggle("autoAbilities", "Auto abilities", "Alternates Q and E when each cooldown is ready")

W.section(body, "Timing")
W.slider(body, {
    label = "Dodge lead",
    key = "dodgeLead",
    min = 0.05,
    max = 0.4,
    step = 0.01,
    fmt = function(value) return string.format("%.2fs", value) end,
})
W.button(body, "Fix me", "H · clears stuck movement state and lands on floor geometry", fixMe, true)

W.section(body, "Safety")
W.note(body, "Walkspeed disabled: server anti-cheat kick recorded 2026-09-02 after speed resumed at 132.")
W.statusRow(body, function()
    local alive = 0
    for model in next, state.mobs do
        local humanoid = model:FindFirstChildOfClass("Humanoid")
        if humanoid and humanoid.Health > 0 then alive += 1 end
    end
    return string.format("mobs %d  ·  dodges %d  ·  H fix  ·  Alt abilities  ·  P panic  ·  K unload", alive, state.dodges)
end)

W.footer(inner, {
    onUnload = function() if destroy then destroy() end end,
    hint = "RightShift hides the Hub. P disarms automation.",
})

for _, key in ipairs({ "esp", "telegraph", "autoDodge", "runHud", "dropFeed", "integrityGuard", "autoReady", "autoAbilities" }) do
    setToggle(key, settings[key])
end

-- ---------------------------------------------------------------- run HUD

local hud = Instance.new("Frame")
hud.AnchorPoint = Vector2.new(0.5, 0)
hud.Position = UDim2.new(0.5, 0, 0, 8)
hud.Size = UDim2.fromOffset(380, 74)
hud.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
hud.BackgroundTransparency = 0.25
hud.BorderSizePixel = 0
hud.Visible = settings.runHud
hud.Parent = screen
Instance.new("UICorner", hud).CornerRadius = UDim.new(0, 6)

local hudRun = Instance.new("TextLabel")
hudRun.BackgroundTransparency = 1
hudRun.Position = UDim2.fromOffset(8, 4)
hudRun.Size = UDim2.fromOffset(364, 18)
hudRun.Font = Enum.Font.GothamBold
hudRun.TextColor3 = Color3.new(1, 1, 1)
hudRun.TextSize = 13
hudRun.TextXAlignment = Enum.TextXAlignment.Left
hudRun.Text = "-"
hudRun.Parent = hud

local hudInfo = Instance.new("TextLabel")
hudInfo.BackgroundTransparency = 1
hudInfo.Position = UDim2.fromOffset(8, 22)
hudInfo.Size = UDim2.fromOffset(364, 16)
hudInfo.Font = Enum.Font.Gotham
hudInfo.TextColor3 = Color3.fromRGB(198, 204, 218)
hudInfo.TextSize = 12
hudInfo.TextXAlignment = Enum.TextXAlignment.Left
hudInfo.Text = "-"
hudInfo.Parent = hud

local hudDrops = Instance.new("TextLabel")
hudDrops.BackgroundTransparency = 1
hudDrops.Position = UDim2.fromOffset(8, 38)
hudDrops.Size = UDim2.fromOffset(364, 32)
hudDrops.Font = Enum.Font.Gotham
hudDrops.TextColor3 = Color3.fromRGB(255, 214, 120)
hudDrops.TextSize = 11
hudDrops.TextXAlignment = Enum.TextXAlignment.Left
hudDrops.TextYAlignment = Enum.TextYAlignment.Top
hudDrops.Text = ""
hudDrops.Parent = hud

local warning = Instance.new("TextLabel")
warning.AnchorPoint = Vector2.new(0.5, 0.5)
warning.Position = UDim2.new(0.5, 0, 0.28, 0)
warning.Size = UDim2.fromOffset(320, 40)
warning.BackgroundTransparency = 1
warning.Font = Enum.Font.GothamBlack
warning.TextColor3 = Color3.fromRGB(255, 74, 74)
warning.TextStrokeTransparency = 0.4
warning.TextSize = 26
warning.Text = "MOVE"
warning.Visible = false
warning.Parent = screen

local function runValue(name, fallback)
    local value = workspace:FindFirstChild(name)
    if value and value:IsA("ValueBase") then return value.Value end
    return fallback
end

local dropRemote = remote("AnnounceDrop")
if dropRemote then
    connect(dropRemote.OnClientEvent, function(message, rarity)
        if not settings.dropFeed then return end
        local line = tostring(rarity or "?") .. "  " .. tostring(message)
        table.insert(state.drops, 1, line)
        while #state.drops > 2 do table.remove(state.drops) end
        Log.info("drop " .. line)
    end)
end

-- ---------------------------------------------------------------- wiring

connect(workspace.ChildAdded, function(child)
    if settings.telegraph and looksLikeTelegraph(child) then addMark(child) end
end)
connect(workspace.DescendantAdded, function(instance)
    if instance.Name == "enemyFolder" and instance:IsA("Folder") then
        bindFolder(instance)
    elseif instance:IsA("Model") then
        task.defer(bindMob, instance)
    end
end)
connect(workspace.DescendantRemoving, function(instance)
    if state.mobs[instance] then unbindMob(instance) end
end)
connect(UserInputService.InputBegan, function(input, processed)
    if processed then return end
    local key = input.KeyCode
    if key == Enum.KeyCode.Insert and not HOST then
        panel.Visible = not panel.Visible
    elseif key == Enum.KeyCode.H then
        fixMe()
    elseif key == Enum.KeyCode.LeftAlt then
        setToggle("autoAbilities", not settings.autoAbilities)
    elseif key == Enum.KeyCode.P then
        setToggle("autoReady", false)
        setToggle("autoAbilities", false)
        setToggle("autoDodge", false)
        setToggle("speed", false)
    elseif key == Enum.KeyCode.K and getgenv()[GKEY] then
        getgenv()[GKEY].destroy()
    end
end)

local lastTick = 0
connect(RunService.Heartbeat, function()
    if not state.alive then return end
    local now = os.clock()
    -- ~10 Hz for UI and scans; nothing here needs per-frame work any more.
    if now - lastTick >= 0.1 then
        lastTick = now
        scanFolders()
        local playerRoot = myRoot()
        local count, alive = 0, 0
        for model, record in next, state.mobs do
            if not model.Parent then
                unbindMob(model)
            else
                count += 1
                local humanoid = model:FindFirstChildOfClass("Humanoid")
                local root = model:FindFirstChild("HumanoidRootPart")
                if humanoid and root then
                    if humanoid.Health > 0 then alive += 1 end
                    local ratio = humanoid.MaxHealth > 0 and humanoid.Health / humanoid.MaxHealth or 0
                    record.highlight.FillColor = Color3.fromRGB(255, math.floor(72 + 150 * (1 - ratio)), 72)
                    if settings.esp then
                        local distance = playerRoot and (root.Position - playerRoot.Position).Magnitude or 0
                        -- aggroRange is the server's own pull distance (trees/Workspace.txt:286).
                        local aggro = model:FindFirstChild("aggroRange")
                        record.text.Text = string.format("%s  %.0f/%.0f  [%.0fm%s]",
                            model.Name, humanoid.Health, humanoid.MaxHealth, distance,
                            aggro and aggro:IsA("ValueBase") and (" / aggro " .. tostring(aggro.Value)) or "")
                    end
                end
            end
        end

        state.inDanger = settings.telegraph and dangerNow() or false
        warning.Visible = state.inDanger
        hud.Visible = settings.runHud
        if settings.runHud then
            local wave = tonumber(runValue("currentWave", 0)) or 0
            hudRun.Text = string.format("%s   WAVE %d   +%d%%", tostring(runValue("dungeonName", "-")), wave, math.floor(wave / 15) * 25)
            hudInfo.Text = string.format("tier %s | %s | time %s | mobs %d/%d | dodges %d%s",
                tostring(runValue("tier", "-")), tostring(runValue("dungeonProgress", "-")),
                tostring(runValue("timeLeft", "-")), alive, count, state.dodges,
                runValue("hardcore", false) and " | HARDCORE" or "")
            hudDrops.Text = settings.dropFeed and table.concat(state.drops, "\n") or ""
        end

        for _, refresh in ipairs(uiLive) do refresh() end
        applySpeed()
        autoReady()
        autoAbilities()
    end
end)

-- ---------------------------------------------------------------- teardown

destroy = function()
    if not state.alive then return end
    state.alive = false
    restoreSpeed()
    removePrecastWrap()
    clearMarks()
    for model in next, state.mobs do unbindMob(model) end
    table.clear(state.mobs)
    table.clear(state.folders)
    for _, connection in ipairs(state.connections) do pcall(function() connection:Disconnect() end) end
    if panel then
        settings.panelX = panel.AbsolutePosition.X
        settings.panelY = panel.AbsolutePosition.Y
        saveConfig()
    end
    if screen then screen:Destroy() end
    getgenv()[GKEY] = nil
    Log.info("unloaded " .. BUILD_VERSION)
end

G[GKEY] = { destroy = destroy }
installIntegrityGuard()
if settings.autoDodge then installPrecastWrap() end
scanFolders()
for _, child in ipairs(workspace:GetChildren()) do
    if looksLikeTelegraph(child) then addMark(child) end
end
Log.info(string.format("boot %s place=%d resumed esp=%s telegraph=%s dodge=%s hud=%s drops=%s guard=%s speed=%s(%d) ready=%s abilities=%s",
    BUILD_VERSION, game.PlaceId, tostring(settings.esp), tostring(settings.telegraph), tostring(settings.autoDodge),
    tostring(settings.runHud), tostring(settings.dropFeed), tostring(settings.integrityGuard),
    tostring(settings.speed), settings.walkSpeed, tostring(settings.autoReady), tostring(settings.autoAbilities)))
