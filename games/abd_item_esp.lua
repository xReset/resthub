-- A Bizarre Day : Classic Item ESP v2026-10-19.1 (2026-10-19)
-- Rungs 1-2: replicated item reads + client-created adornments only. No remotes,
-- hooks, physics writes or console output. Server/game item state is unchanged.
-- Proof: dump 2026-10-20T02-57-50Z, scripts/0209.lua:7-30;
-- trees/Workspace.txt:63336-64002,68617-71128 (Tool + Handle, root/ItFolder).
-- Re-inject safe: self-teardown; K unload; P disables ESP; Hub owns RightShift.
-- Player: execute hub.lua here, then test labels on world arrows and fruits.
-- Changelog: .1 Hub-only arrows/Requiem/fruit ESP, saved filters and distances.

local BUILD_VERSION = "2026-10-19.1"
local EXPECTED_GAME = 969567031
local EXPECTED_PLACE = 120318126233314
local GKEY = "__ABD_ITEM_ESP"
local CONFIG_FILE = "abd_item_esp_config.json"
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
if G[GKEY] and G[GKEY].destroy then pcall(G[GKEY].destroy) end
if not (HOST and HOST.ui and HOST.host) then
    Log.info("Hub host required; execute hub.lua, not abd_item_esp.lua")
    return
end

local CFG = {
    schema = 1, enabled = true, arrows = true, requiem = true, fruits = true,
    distances = true, range = 0,
}
local S = {
    alive = true, build = BUILD_VERSION, embedded = true, cfg = CFG,
    connections = {}, entries = {}, counts = { arrows = 0, requiem = 0, fruits = 0 },
    shown = 0, dirty = true,
}
local Shell, layer
local TYPES = {
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
    return ("enabled=%s arrows=%s requiem=%s fruits=%s distances=%s range=%d"):format(
        tostring(CFG.enabled), tostring(CFG.arrows), tostring(CFG.requiem), tostring(CFG.fruits),
        tostring(CFG.distances), CFG.range)
end

local function applyConfig()
    -- Signal callbacks mutate Lua state only; the spawned worker writes Instances.
    S.dirty = true
end

local function worldItem(tool)
    if not tool:IsA("Tool") or not TYPES[tool.Name] then return nil end
    local parent = tool.Parent
    local itemFolder = World:FindFirstChild("ItFolder")
    if parent ~= World and not (itemFolder and itemFolder:IsA("Folder") and parent == itemFolder) then
        return nil
    end
    local used = tool:FindFirstChild("Used")
    if used and used:IsA("BoolValue") and used.Value then return nil end
    local handle = tool:FindFirstChild("Handle")
    if handle and handle:IsA("BasePart") then return handle, TYPES[tool.Name] end
    return nil
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
    local counts = { arrows = 0, requiem = 0, fruits = 0 }
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
        subtitle = "World arrows and Rokakaka fruits", gameId = EXPECTED_GAME, placeId = EXPECTED_PLACE,
        tabs = { "Items", "Settings" }, keep = { layer }, cfg = CFG, save = saveConfig,
        conns = S.connections, onUnload = destroy,
        onSettings = function() Shell.show("Settings") end,
        hint = "P disables ESP | K unloads | Hub owns RightShift",
    })
    S.root = Shell.root
    local W = Shell.W
    W.liveHz = 10
    local items = Shell.page("Items")
    W.section(items, "Item ESP")
    W.toggle(items, { label = "Item ESP", key = "enabled", set = applyConfig })
    W.toggle(items, { label = "Arrows", key = "arrows", set = applyConfig })
    W.toggle(items, { label = "Requiem Arrows", key = "requiem", set = applyConfig })
    W.toggle(items, { label = "Rokakaka Fruits", key = "fruits", set = applyConfig })
    W.section(items, "World items")
    W.statusRow(items, function()
        return ("Arrows: %d | Requiem: %d | Fruits: %d"):format(S.counts.arrows, S.counts.requiem, S.counts.fruits)
    end)
    W.statusRow(items, function() return ("ESP %s | %d labels shown"):format(CFG.enabled and "ON" or "OFF", S.shown) end)
    W.note(items, "Gold: Arrow | Purple: Requiem | Pink: Rokakaka. Only replicated world items; held tools and spawn markers are excluded.")
    W.note(items, "Requiem Arrow is in the game catalog but none appeared in this capture. Zero means none currently observed, not that it cannot spawn.")
    local settings = Shell.page("Settings")
    W.section(settings, "Display")
    W.toggle(settings, { label = "Show distance", key = "distances", set = applyConfig })
    W.slider(settings, { label = "Range (0 = unlimited)", key = "range", min = 0, max = 10000, step = 100,
        set = applyConfig })
    W.note(settings, "Settings save per game and resume on inject. Unload removes every owned label without changing items.")
    S.connections[#S.connections + 1] = UIS.InputBegan:Connect(function(input, processed)
        if processed or UIS:GetFocusedTextBox() then return end
        if input.KeyCode == Enum.KeyCode.P then
            CFG.enabled = false
            applyConfig()
            saveConfig()
        elseif input.KeyCode == Enum.KeyCode.K then destroy() end
    end)
    Shell.ready()
    -- 10 Hz label updates, 2 Hz shallow reconciliation; no RenderStepped writes.
    task.spawn(function()
        local nextScan = 0
        local ok, err = xpcall(function()
            while S.alive do
                if os.clock() >= nextScan then
                    scan()
                    nextScan = os.clock() + 0.5
                end
                render()
                task.wait(0.1)
            end
        end, debug.traceback)
        if not ok then Log.err("worker", err); destroy() end
    end)
end

local ok, err = xpcall(main, debug.traceback)
if not ok then Log.err("main", err); destroy() end
return S
