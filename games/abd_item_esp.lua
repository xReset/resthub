-- A Bizarre Day : Classic Items v2026-10-19.4 (2026-10-19)
-- ESP: rungs 1-2. Collection: rung 5, character physics we own; normal contact
-- pickup needs proximity. Server/nearby players see teleports and accepted pickups.
-- No remotes, hooks, item reparenting, WalkSpeed/JumpPower changes or console output.
-- Loading (scripts/0203.lua:22-64) checks speed/jump/fly, not CFrame distance;
-- this is NOT evidence of server teleport safety. Collector is user-requested.
-- Proof: dump 2026-10-20T02-57-50Z, scripts/0209.lua:7-30;
-- trees/Workspace.txt:63336-64002,68617-71128 (Tool + Handle, root/ItFolder).
-- Pickup evidence: trees/Workspace.txt:70717-70720,71129-71140, Handle TouchInterest.
-- Re-inject safe: self-teardown; K unload; P stops ESP/collection; Hub owns RightShift.
-- Player: execute hub.lua, arm Collect all for ONE sweep; confirm inventory/return.
-- Music: local mixer only; scripts/0057.lua:8-24, 0220.lua:45-50,73-78.
-- Changelog: .4 All dropped-Tool ESP, including both vampire masks (0209.lua:7-30).
-- .3 Saved music toggle, music-only routing and owned unload restore.
-- .2 All dropped-Tool collection sweep with confirmed pickups and return.
-- .1 Hub-only arrows/Requiem/fruit ESP, saved filters and distances.

local BUILD_VERSION = "2026-10-19.4"
local EXPECTED_GAME = 969567031
local EXPECTED_PLACE = 120318126233314
local GKEY = "__ABD_ITEM_ESP"
local CONFIG_FILE = "abd_item_esp_config.json"
local RETURN_KEY = "__ABD_ITEM_RETURN"
local G = getgenv()
local HOST = G.__R3ST_HOST
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local World = game:GetService("Workspace")
local Log = loadfile("log.lua")()("abd_item_esp", { print = false })

if game.GameId ~= EXPECTED_GAME and game.PlaceId ~= EXPECTED_PLACE then
    Log.info("identity rejected place=" .. tostring(game.PlaceId) .. " game=" .. tostring(game.GameId))
    return
end
local previous = G[GKEY]
if previous and previous.destroy then pcall(previous.destroy) end
if not (HOST and HOST.ui and HOST.host) then
    Log.info("Hub host required; execute hub.lua, not abd_item_esp.lua")
    return
end

local CFG = {
    schema = 1, enabled = true, arrows = true, requiem = true, fruits = true,
    distances = true, range = 0, collect = false, music = true, masks = true, other = true,
}
local S = {
    alive = true, build = BUILD_VERSION, embedded = true, cfg = CFG,
    connections = {}, entries = {}, counts = { arrows = 0, requiem = 0, fruits = 0 },
    shown = 0, dirty = true, collectStatus = "Idle", cancelCollect = false, musicEntries = {},
}
local Shell, layer
local OTHER_TYPE = { key = "other", color = Color3.fromRGB(150, 220, 255) }
local TYPES = {
    ["Vampire Mask"] = { key = "masks", color = Color3.fromRGB(255, 150, 90) },
    ["Golden Vampire Mask"] = { key = "masks", color = Color3.fromRGB(255, 220, 100) },
    ["Arrow"] = { key = "arrows", color = Color3.fromRGB(255, 208, 90) },
    ["Requiem Arrow"] = { key = "requiem", color = Color3.fromRGB(202, 150, 255) },
    ["Rokakaka Fruit"] = { key = "fruits", color = Color3.fromRGB(255, 112, 142) },
}

local function loadConfig()
    local ok, raw = pcall(readfile, CONFIG_FILE)
    if not ok then return end
    local decoded, saved = pcall(HttpService.JSONDecode, HttpService, raw)
    if not decoded or type(saved) ~= "table" or saved.schema ~= 1 then return end
    for key, default in pairs(CFG) do
        if type(default) == "boolean" and type(saved[key]) == "boolean" then CFG[key] = saved[key] end
    end
    if type(saved.range) == "number" and saved.range == saved.range then
        CFG.range = math.clamp(math.floor(saved.range), 0, 10000)
    end
end

local function saveConfig()
    -- The kit owns the debounce. Old callbacks cannot write after unload/reinject.
    if not S.alive or G[GKEY] ~= S then return end
    local ok, payload = pcall(HttpService.JSONEncode, HttpService, CFG)
    if ok then
        local wrote, err = pcall(writefile, CONFIG_FILE, payload)
        if not wrote then Log.err("config save", err) end
    end
end

local function resumed()
    return ("enabled=%s arrows=%s requiem=%s fruits=%s distances=%s range=%d collect=%s music=%s"):format(
        tostring(CFG.enabled), tostring(CFG.arrows), tostring(CFG.requiem), tostring(CFG.fruits),
        tostring(CFG.distances), CFG.range, tostring(CFG.collect), tostring(CFG.music))
end

local function applyConfig()
    -- Signal callbacks mutate Lua state only; the spawned worker writes Instances.
    S.dirty = true
end

local function releaseMusic(sound, entry)
    -- Ownership check prevents an old cleanup overwriting a newer routing choice.
    if sound.SoundGroup == entry.group then
        sound.SoundGroup = entry.originalGroup
        if entry.unmuted and sound.Volume == 0.1 then sound.Volume = entry.originalVolume end
        if entry.muted and entry.muted.Parent == sound then entry.muted.Value = entry.originalMuted end
    end
    entry.group:Destroy()
    S.musicEntries[sound] = nil
end

local function restoreMusic()
    for sound, entry in pairs(S.musicEntries) do releaseMusic(sound, entry) end
end
S.restoreMusic = restoreMusic

local function musicStep()
    local folder = World:FindFirstChild("Music")
    for sound, entry in pairs(S.musicEntries) do
        if not folder or sound.Parent ~= folder or sound.SoundGroup ~= entry.group then
            releaseMusic(sound, entry)
        end
    end
    if not folder then return end
    for _, sound in ipairs(folder:GetChildren()) do
        if sound:IsA("Sound") then
            local entry = S.musicEntries[sound]
            if not entry then
                local group = Instance.new("SoundGroup")
                group.Name = "ABD_Music"
                group.Volume = CFG.music and 1 or 0
                -- Nest beneath the original group to retain its volume/effects.
                group.Parent = sound.SoundGroup or game:GetService("SoundService")
                local muted = sound:FindFirstChild("IsMuted")
                if not (muted and muted:IsA("BoolValue")) then muted = nil end
                entry = { group = group, originalGroup = sound.SoundGroup,
                    originalVolume = sound.Volume, muted = muted, originalMuted = muted and muted.Value }
                S.musicEntries[sound] = entry
                sound.SoundGroup = group
            end
            entry.group.Volume = CFG.music and 1 or 0
            -- The game's own music button unmutes at 0.1 (0057.lua:14-16).
            -- OFF uses mixer gain instead, retaining native track fades/selection.
            if CFG.music and entry.muted and entry.muted.Value then
                entry.muted.Value = false
                if sound.Volume == 0 then sound.Volume = 0.1; entry.unmuted = true end
            end
        end
    end
end

local function worldTool(tool)
    if not tool:IsA("Tool") then return nil end
    local parent = tool.Parent
    local itemFolder = World:FindFirstChild("ItFolder")
    if parent ~= World and not (itemFolder and itemFolder:IsA("Folder") and parent == itemFolder) then
        return nil
    end
    local used = tool:FindFirstChild("Used")
    if used and used:IsA("BoolValue") and used.Value then return nil end
    local handle = tool:FindFirstChild("Handle")
    if handle and handle:IsA("BasePart") then return handle end
    return nil
end

local function worldItem(tool)
    return worldTool(tool), TYPES[tool.Name] or OTHER_TYPE
end

local function pickupHandle(tool)
    local handle = worldTool(tool)
    local touch = handle and handle:FindFirstChild("TouchInterest")
    if touch and touch:IsA("TouchTransmitter") and handle.CanTouch ~= false then return handle end
    return nil
end

local function inInventory(tool, character)
    local backpack = Players.LocalPlayer:FindFirstChildOfClass("Backpack")
    return tool.Parent == character or (backpack ~= nil and tool.Parent == backpack)
end

local function returnTrip(trip)
    if not trip or G[RETURN_KEY] ~= trip then return false end
    G[RETURN_KEY] = nil -- a stale cleanup can never return a newer trip
    if not trip.moved then return true end
    local humanoid = trip.character:FindFirstChild("Humanoid")
    if Players.LocalPlayer.Character ~= trip.character or trip.root.Parent ~= trip.character
        or not humanoid or humanoid.Health <= 0 then return false end
    local ok, err = pcall(function()
        trip.root.CFrame = trip.frame
        trip.root.AssemblyLinearVelocity = trip.linear
        trip.root.AssemblyAngularVelocity = trip.angular
    end)
    if not ok then Log.err("collection return", err) end
    return ok
end

local function confirmPickups(c)
    for tool in pairs(c.pending) do
        if inInventory(tool, c.trip.character) then
            c.pending[tool] = nil
            c.collected += 1
            Log.info("collection confirmed " .. tool.Name)
        end
    end
end

local function finishCollection(reason, keepArmed)
    local c = S.collection
    if not c then return end
    confirmPickups(c)
    local returned = returnTrip(c.trip)
    S.collection = nil
    if not keepArmed then CFG.collect = false end
    S.collectStatus = ("%s | %d/%d confirmed, %d visited, %d unconfirmed | %s"):format(
        reason, c.collected, #c.queue, c.visited, #c.queue - c.collected,
        returned and "returned" or "return unavailable (character changed/dead or error)")
    S.dirty = true
    saveConfig()
    Log.info("collection " .. S.collectStatus)
end

local function collectionStep()
    local c = S.collection
    if S.cancelCollect then
        S.cancelCollect = false
        if c then finishCollection("Stopped", CFG.collect); return end
    end
    if c and not CFG.collect then finishCollection("Stopped"); return end
    if not CFG.collect then return end
    local character = Players.LocalPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local humanoid = character and character:FindFirstChild("Humanoid")
    local ready = root and root:IsA("BasePart") and root.Parent == character
        and character.Parent and humanoid and humanoid.Health > 0
        and not root.Anchored and not humanoid.Sit and not humanoid.SeatPart
        and humanoid.WalkSpeed < 200 and humanoid.JumpPower < 140
    if c and (not ready or character ~= c.trip.character or root ~= c.trip.root) then
        finishCollection("Stopped: character changed, dead, seated or movement locked")
        return
    end
    if not ready then S.collectStatus = "Waiting for a living, unseated, unlocked character"; return end
    if not c then
        -- A previous inject may have scheduled its cleanup but not run it yet.
        if G[RETURN_KEY] then returnTrip(G[RETURN_KEY]) end
        local queue = {}
        local function visit(parent)
            for _, tool in ipairs(parent:GetChildren()) do
                local handle = pickupHandle(tool)
                if handle then queue[#queue + 1] = { tool = tool, distance = (handle.Position - root.Position).Magnitude } end
            end
        end
        visit(World)
        local folder = World:FindFirstChild("ItFolder")
        if folder and folder:IsA("Folder") then visit(folder) end
        if #queue == 0 then
            CFG.collect = false
            S.collectStatus = "No replicated dropped items"
            saveConfig()
            return
        end
        table.sort(queue, function(a, b) return a.distance < b.distance end)
        local trip = { owner = S, character = character, root = root, frame = root.CFrame,
            linear = root.AssemblyLinearVelocity, angular = root.AssemblyAngularVelocity, moved = false }
        G[RETURN_KEY] = trip
        c = { trip = trip, queue = queue, index = 0, visited = 0, collected = 0, pending = {} }
        S.collection = c
        Log.info("collection started snapshot=" .. tostring(#queue))
    end
    confirmPickups(c)
    if c.target then
        if c.pending[c.target] and pickupHandle(c.target) and os.clock() < c.deadline then return end
        c.target = nil
    end
    while c.index < #c.queue do
        c.index += 1
        local tool = c.queue[c.index].tool
        local handle = pickupHandle(tool)
        if handle then
            c.trip.moved = true -- return even if a later physics assignment errors
            root.CFrame = c.trip.frame + (handle.Position - c.trip.frame.Position)
            root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
            root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
            c.visited += 1
            c.pending[tool] = true
            c.target, c.deadline = tool, os.clock() + 0.25
            S.collectStatus = ("Collecting %d/%d | %d confirmed | %s"):format(c.visited, #c.queue, c.collected, tool.Name)
            return -- yield for physics/network contact; never reparent or activate Tools
        end
    end
    -- Brief final reconciliation catches delayed transfers without calling them failures.
    if not c.settleUntil then c.settleUntil = os.clock() + 0.3 end
    if next(c.pending) == nil or os.clock() >= c.settleUntil then finishCollection("Sweep complete") end
end

local function applyCollect()
    if not CFG.collect then S.cancelCollect = true end
    applyConfig()
end

local function forget(tool)
    local entry = S.entries[tool]
    if not entry then return end
    entry.billboard:Destroy()
    S.entries[tool] = nil
end

local function makeEntry(tool, handle, kind)
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "ABD_Item"
    billboard.Adornee = handle
    billboard.AlwaysOnTop = true
    billboard.LightInfluence = 0
    billboard.Size = UDim2.fromOffset(210, 42)
    billboard.StudsOffsetWorldSpace = Vector3.new(0, 2, 0)
    billboard.Enabled = false
    billboard.Parent = layer
    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Size = UDim2.fromScale(1, 1)
    label.Font = Enum.Font.GothamBold
    label.TextSize = 14
    label.TextColor3 = kind.color
    label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    label.TextStrokeTransparency = 0.15
    label.Text = tool.Name
    label.Parent = billboard
    -- Billboard labels cover every item without Roblox's limited Highlight slots.
    return { handle = handle, kind = kind, billboard = billboard, label = label }
end

local function scan()
    local seen = {}
    local counts = { arrows = 0, requiem = 0, fruits = 0, masks = 0, other = 0 }
    local function visit(parent)
        for _, tool in ipairs(parent:GetChildren()) do
            local handle, kind = worldItem(tool)
            if handle then
                seen[tool] = true
                counts[kind.key] += 1
                local old = S.entries[tool]
                if old and (old.handle ~= handle or old.kind ~= kind) then forget(tool) end
                if not S.entries[tool] then S.entries[tool] = makeEntry(tool, handle, kind) end
            end
        end
    end
    -- Do not walk the 96k-instance world. Both spawn containers are dump-proven.
    visit(World)
    local folder = World:FindFirstChild("ItFolder")
    if folder and folder:IsA("Folder") then visit(folder) end
    for tool in pairs(S.entries) do
        if not seen[tool] then forget(tool) end
    end
    local previous = S.counts
    S.counts = counts
    if previous.arrows ~= counts.arrows or previous.requiem ~= counts.requiem or previous.fruits ~= counts.fruits then
        Log.info(("items arrows=%d requiem=%d fruits=%d"):format(counts.arrows, counts.requiem, counts.fruits))
    end
end

local function render()
    local camera = World.CurrentCamera
    local character = Players.LocalPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local origin = root and root.Position or (camera and camera.CFrame.Position)
    local shown = 0
    for tool, entry in pairs(S.entries) do
        local handle = worldItem(tool)
        local distance = handle and origin and (handle.Position - origin).Magnitude
        local visible = CFG.enabled and CFG[entry.kind.key] and handle == entry.handle
            and (CFG.range == 0 or (distance ~= nil and distance <= CFG.range))
        entry.billboard.Enabled = visible == true
        if visible then
            shown += 1
            entry.label.Text = tool.Name .. (CFG.distances and distance and ("\n%d studs"):format(distance) or "")
        end
    end
    S.shown = shown
    if S.dirty then
        S.dirty = false
        Log.info("applied " .. resumed())
    end
end

local function destroy()
    if not S.alive then return end
    saveConfig() -- flush the user's choices before changing lifecycle state
    S.alive = false
    for _, connection in ipairs(S.connections) do connection:Disconnect() end
    table.clear(S.connections)
    -- Never destroy HOST.host. Release only our root/adornments from a worker.
    task.spawn(function()
        restoreMusic()
        if S.collection then finishCollection("Unloaded", true) end
        local trip = G[RETURN_KEY]
        if trip and trip.owner == S then returnTrip(trip) end
        for tool in pairs(S.entries) do forget(tool) end
        if layer then layer:Destroy() end
        if Shell then Shell.destroy() end
    end)
    if G[GKEY] == S then G[GKEY] = nil end
    Log.info("destroy " .. BUILD_VERSION)
end
S.destroy = destroy
G[GKEY] = S

local function main()
    -- Drain a prior inject's deferred restoration before capturing audio ownership.
    if previous and previous.restoreMusic then previous.restoreMusic() end
    previous = nil
    loadConfig()
    Log.session("build=" .. BUILD_VERSION .. " resumed " .. resumed())
    local Kit = HOST.ui
    assert(Kit.SHELL_CONTRACT == "1", "R3ST shell contract mismatch")
    local core = game:GetService("CoreGui")
    if type(cloneref) == "function" then core = cloneref(core) end
    layer = Instance.new("Folder")
    layer.Name = "ABD_Items_" .. tostring(math.random(1000, 9999))
    layer.Parent = core
    Shell = Kit.moduleShell({
        id = "bizarre-day-classic", title = "A Bizarre Day : Classic", version = BUILD_VERSION,
        subtitle = "Item ESP and ground-item collection", gameId = EXPECTED_GAME, placeId = EXPECTED_PLACE,
        tabs = { "Items", "Settings" }, keep = { layer }, cfg = CFG, save = saveConfig,
        conns = S.connections, onUnload = destroy,
        onSettings = function() Shell.show("Settings") end,
        hint = "P stops ESP/collection | K unloads | Hub owns RightShift",
    })
    S.root = Shell.root
    local W = Shell.W
    W.liveHz = 10
    local items = Shell.page("Items")
    W.section(items, "Audio")
    W.toggle(items, { label = "Game music", key = "music", set = applyConfig })
    W.note(items, "Music only, including Skate/Soccer tracks; combat and item sounds stay on. Original audio routing restores on unload.")
    W.section(items, "Item ESP")
    W.toggle(items, { label = "Item ESP", key = "enabled", set = applyConfig })
    W.toggle(items, { label = "Arrows", key = "arrows", set = applyConfig })
    W.toggle(items, { label = "Requiem Arrows", key = "requiem", set = applyConfig })
    W.toggle(items, { label = "Rokakaka Fruits", key = "fruits", set = applyConfig })
    W.toggle(items, { label = "Vampire Masks (including Golden)", key = "masks", set = applyConfig })
    W.toggle(items, { label = "All other dropped items", key = "other", set = applyConfig })
    W.section(items, "Collection")
    W.toggle(items, { label = "Collect all (one sweep)", key = "collect", set = applyCollect })
    W.statusRow(items, function() return S.collectStatus end)
    W.note(items, "Visits ALL replicated dropped Tools, including Banknotes; ESP filters/range do not limit collection. Returns after one sweep, then turns OFF.")
    W.note(items, "Visible teleporting; server checks are unknown. Stop/P returns early. Death or respawn cancels without moving the new character. Only inventory transfers count as confirmed.")
    W.section(items, "World items")
    W.statusRow(items, function()
        return ("Arrows: %d | Requiem: %d | Fruits: %d"):format(S.counts.arrows, S.counts.requiem, S.counts.fruits)
    end)
    W.statusRow(items, function() return ("ESP %s | %d labels shown"):format(CFG.enabled and "ON" or "OFF", S.shown) end)
    W.statusRow(items, function() return ("Masks: %d | Other items: %d"):format(S.counts.masks or 0, S.counts.other or 0) end)
    W.note(items, "All replicated dropped Tools with Handles, including Vampire/Golden Vampire Masks and Requiem Arrows. Held tools and spawn markers are excluded.")
    W.note(items, "Requiem Arrow is in the game catalog but none appeared in this capture. Zero means none currently observed, not that it cannot spawn.")
    local settings = Shell.page("Settings")
    W.section(settings, "Display")
    W.toggle(settings, { label = "Show distance", key = "distances", set = applyConfig })
    W.slider(settings, { label = "Range (0 = unlimited)", key = "range", min = 0, max = 10000, step = 100,
        set = applyConfig })
    W.note(settings, "Settings resume on inject, including an interrupted armed sweep. Completion saves collection OFF. Unload removes labels and returns the same surviving character.")
    S.connections[#S.connections + 1] = UIS.InputBegan:Connect(function(input, processed)
        if processed or UIS:GetFocusedTextBox() then return end
        if input.KeyCode == Enum.KeyCode.P then
            CFG.enabled = false
            CFG.collect = false
            S.cancelCollect = true
            applyConfig()
            saveConfig()
        elseif input.KeyCode == Enum.KeyCode.K then destroy() end
    end)
    Shell.ready()
    -- Collection 20 Hz for contact confirmation; labels 10 Hz, shallow scan 2 Hz.
    -- All physics/Instance writes run here, never in sandboxed signal callbacks.
    task.spawn(function()
        local nextScan, nextRender = 0, 0
        local ok, err = xpcall(function()
            while S.alive do
                if os.clock() >= nextScan then
                    scan()
                    nextScan = os.clock() + 0.5
                end
                collectionStep()
                musicStep()
                if os.clock() >= nextRender then
                    render()
                    nextRender = os.clock() + 0.1
                end
                task.wait(0.05)
            end
        end, debug.traceback)
        if not ok then Log.err("worker", err); destroy() end
    end)
end

local ok, err = xpcall(main, debug.traceback)
if not ok then Log.err("main", err); destroy() end
return S
