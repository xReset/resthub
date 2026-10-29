-- Vantage Hub v2026-10-29.7 (2026-10-29)
-- Reads + owned Drawing overlays (rungs 1/2); softaim uses strength-scaled mouse
-- smoothing; instant aimbot requests the full screen error each frame, without
-- reaction/speed/acceleration limits. This is conspicuous, not legitimate-looking.
-- Crosshair accuracy uses rung-3 local Spread Value writes, consumed by native
-- normal single-bullet fire (34425:2571-2573,2892-2919); no shot interception.
-- Reads alone cannot alter the random cone. Server sees native shot reports;
-- server acceptance is unknown. Owned values restore on OFF/equip/panic/unload.
-- Bhop requests normal Humanoid.Jump only. No hooks, remotes, velocity,
-- speed, jump-height, camera CFrame or anti-check changes. Server sees normal
-- resulting camera/character motion and shots; undetected use is NOT guaranteed.
-- Proof: capture 9818227981/2026-10-29T04-33-22Z, 34425:2238,2451-2533,3367-3382;
-- 0025:1351-1365,1563-1642,3412-3417; 34319:610-644. AttachGuard 34427 untouched.
-- Re-inject safe: self-teardown on load; F8 = panic OFF; End = unload.
-- Knives: rung-2 synthetic local cosmetic entry + rung-3 owned selection Value;
-- native builder/animations on next equip (34425:454-478,580-584; 34420:695-795).
-- No unlock/purchase/inspect calls. Missing local templates/prices stay unavailable.
-- .6 Modern GunConfig cone ownership; sensitivity-aware angular mouse input.
-- .5 Searchable native knife catalog/preview; closest visible real aim part.
-- .4 Reversible crosshair accuracy for supported normal single-bullet firearms.
-- .3 Simple softaim strength; separate, mutually exclusive instant aimbot toggle.
-- .2 Capture an Aim key directly; optional toggle activation, transient latch.
-- .1 Custom ESP, held softaim, ordinary grounded bhop, experimental spike marker.
-- .7 Friendship recovery, immediate roster cleanup, global closest-part and triggerbot.
-- Trigger boots OFF: native fire sends shots (per-session opt-in); proved by
-- 0025:3180-3250,3332-3348. Server sees ordinary shots; no hooks/forgery.
local BUILD_VERSION = "2026-10-29.7"
local G = getgenv()
local HOST = G.__R3ST_HOST
local GKEY = "__VANTAGE_HUB"
if game.GameId ~= 3631977525 and game.PlaceId ~= 9818227981 then return end
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local Http = game:GetService("HttpService")
local GuiService = game:GetService("GuiService")
local LP = Players.LocalPlayer
local Log
local okLog, factory = pcall(function() return loadfile("log.lua")() end)
if okLog and type(factory) == "function" then Log = factory("vantage_hub", {print = false}) end
if not Log then return end -- Never fall back to console output in this game.
if G[GKEY] and G[GKEY].destroy then pcall(G[GKEY].destroy) end
if not (HOST and HOST.ui) then Log.info("Hub host required"); return end
local Kit = HOST.ui
if Kit.SHELL_CONTRACT ~= "1" then Log.info("Unsupported shell contract"); return end

local DEFAULTS = {
    Esp = false, Boxes = true, Corners = true, Names = true, Health = true,
    Distance = true, Skeleton = false, Snaplines = false, ShowTeam = false,
    VisibleOnly = true, Friends = false, EspRange = 600, EspHz = 20,
    Opacity = 0.8, Thickness = 1, TextSize = 13, EnemyHue = 0.04,
    TeamHue = 0.55, HiddenHue = 0.78, Saturation = 0.55,
    Aim = false, RawAim = false, AimBind = "MouseButton2", AimToggle = false, AimPart = "UpperTorso",
    Fov = 65, ShowFov = true, AimRange = 400, SoftStrength = 1,
    Sticky = true, ExcludeFriends = true, TargetMarker = false,
    NoSpread = false, ClosestPart = false, Trigger = false, KnifePreview = false, KnifeSkin = "",
    Bhop = false, BhopMoving = true, HopInterval = 0.22,
    Spike = false, SpikeRange = 1000,
}
local LIMITS = {
    EspRange = {50, 3000}, EspHz = {5, 30}, Opacity = {0.1, 1},
    Thickness = {1, 3}, TextSize = {10, 24}, EnemyHue = {0, 1},
    TeamHue = {0, 1}, HiddenHue = {0, 1}, Saturation = {0, 1},
    Fov = {10, 300}, AimRange = {25, 1500}, SoftStrength = {0.1, 10},
    HopInterval = {0.15, 0.6}, SpikeRange = {50, 3000},
}
local CHOICES = {
    AimPart = {"UpperTorso", "Head"},
}
local CFG = table.clone(DEFAULTS)
local FILE = "vantage_hub_config.json"
local M = { build = BUILD_VERSION, cfg = CFG, closed = false, ready = false }
local conns, live, bundles, drawings = {}, {}, {}, {}
local Shell, pendingSave, syncAccuracy, syncKnives, restoreKnives, loadKnifeCatalog
local target
local lastAimLog = -math.huge
local aimLatched, capturingBind = false, false
local focused, hopChar, hopLatched, lastHop = true, nil, false, -math.huge
local friendCache, roster, lastScan = {}, {}, -math.huge
local drawingReady, mouseReady = false, type(mousemoverel) == "function"
local Aspect
local aspectPending, aspectRetryAt = false, 0
local abilityState, abilityModule, abilityPending, abilityRetryAt = nil, nil, false, 0
local friendReads, playerConns = {}, {}
local triggerHeld = false
local triggerReady = type(mouse1press) == "function" and type(mouse1release) == "function"
local function releaseTrigger()
    if triggerHeld then
        mouse1release() -- Keep ownership if release throws; teardown retries.
        triggerHeld = false
    end
end
G[GKEY] = M

local function bindingEnum(name)
    if name == "MouseButton1" or name == "MouseButton2" or name == "MouseButton3" then
        return Enum.UserInputType[name]
    end
    if table.find({"Unknown", "Escape", "Backspace", "Delete", "F8", "End", "RightShift", "K"}, name) then return nil end
    local ok, value = pcall(function() return Enum.KeyCode[name] end)
    return ok and value or nil
end
local function validValue(key, value)
    local default = DEFAULTS[key]
    if type(value) ~= type(default) then return nil end
    if type(default) == "number" then
        if value ~= value or math.abs(value) == math.huge then return nil end
        return math.clamp(value, LIMITS[key][1], LIMITS[key][2])
    end
    if key == "KnifeSkin" and (#value > 128 or string.find(value, "%c")) then return nil end
    if key == "AimBind" and not bindingEnum(value) then return nil end
    if CHOICES[key] and not table.find(CHOICES[key], value) then return nil end
    return value
end
local function flush()
    if M.closed or G[GKEY] ~= M then return end
    local snapshot = {}
    for key in pairs(DEFAULTS) do snapshot[key] = CFG[key] end
    local ok = pcall(function() writefile(FILE, Http:JSONEncode(snapshot)) end)
    if not ok then Log.info("Config write failed") end
end
local function saveConfig()
    if M.closed or G[GKEY] ~= M then return end
    if pendingSave then task.cancel(pendingSave) end
    pendingSave = task.delay(0.5, function()
        pendingSave = nil
        if not M.closed and G[GKEY] == M then flush() end
    end)
end
local function loadConfig()
    local ok, data = pcall(function() return Http:JSONDecode(readfile(FILE)) end)
    if not ok or type(data) ~= "table" then return end
    for key in pairs(DEFAULTS) do
        local value = validValue(key, data[key])
        if value ~= nil then CFG[key] = value end
    end
    if CFG.RawAim then CFG.Aim = false end -- Never restore two mouse controllers.
    CFG.Trigger = false -- Native fire sends shots; require per-session opt-in.
end
local function resetAim()
    target = nil
end
local function set(key, value)
    if M.closed then return end
    local checked = validValue(key, value)
    if checked == nil then return end
    CFG[key] = checked
    if key == "Trigger" and not checked then releaseTrigger() end
    if checked == true and (key == "Aim" or key == "RawAim") then
        local other = key == "Aim" and "RawAim" or "Aim"
        CFG[other] = false
        Log.info(other .. "=false (exclusive aim mode)")
    end
    if type(checked) == "boolean" then Log.info(key .. "=" .. tostring(checked)) end
    if key == "Aim" or key == "RawAim" or key == "AimBind" or key == "AimToggle" or key == "AimPart" or key == "ClosestPart" then
        aimLatched = false
        resetAim()
    end
    if key == "NoSpread" and syncAccuracy then syncAccuracy() end
    if (key == "KnifePreview" or key == "KnifeSkin") and syncKnives then syncKnives(true) end
    saveConfig()
end

-- Native templates, never guessed meshes or replicated ownership/purchase calls.
-- This backend changes cosmetic selection only. The user equips/inspects normally.
do
    local catalog, owned, blocked = {}, nil, false
    M.knifeCatalog = catalog
    local function child(parent, name) return parent and parent:FindFirstChild(name) end
    local function template(skin)
        local first = child(child(child(RS, "WeaponEngine"), "Skins"), "FirstPerson")
        local model = child(child(first, "Knife"), "v_Knife-" .. skin)
        return model and model:IsA("Model") and model or nil
    end
    M.knifeAvailable = function(skin) return template(skin) ~= nil end
    M.knifeRows = function(query)
        local rows = {}
        query = string.lower(query or "")
        for _, row in ipairs(catalog) do
            if string.find(row.search, query, 1, true) then table.insert(rows, row) end
        end
        return rows
    end
    local function catalogFailure(reason)
        M.knifeCatalogStatus = reason
        Log.info(reason)
        return false
    end
    loadKnifeCatalog = function()
        if M.closed or G[GKEY] ~= M then return false end
        local module = child(child(RS, "Modules"), "KnifeCatalog")
        if not module then return catalogFailure("Native KnifeCatalog is not resident; refresh after match loads") end
        local ok, data = pcall(require, module)
        if M.closed or G[GKEY] ~= M then return false end
        if not ok then return catalogFailure("KnifeCatalog read failed: " .. tostring(data)) end
        if type(data) ~= "table" or type(data.StarList) ~= "function" then
            return catalogFailure("KnifeCatalog schema unsupported; no selection changed")
        end
        local got, stars = pcall(data.StarList)
        if not got then return catalogFailure("KnifeCatalog.StarList failed: " .. tostring(stars)) end
        if type(stars) ~= "table" then return catalogFailure("KnifeCatalog list unsupported") end
        local seen = {}
        for _, row in ipairs(catalog) do seen[row.skin] = true end -- Merge partial refreshes.
        local function merge(items, star)
            for _, item in ipairs(items) do
                if type(item) == "table" and type(item.Skin) == "string" and #item.Skin <= 128
                    and not seen[item.Skin] then
                    local tier = star and (data.Tier or "Special") or item.Tier
                    if type(tier) ~= "string" then tier = "Unknown" end
                    local row = {skin = item.Skin, tier = tier,
                        kind = type(item.Type) == "string" and item.Type or "Themed melee",
                        finish = type(item.Finish) == "string" and item.Finish or "Original",
                        draw = type(item.Draw) == "string" and item.Draw or "Native",
                        inspect = type(item.Inspect) == "string" and item.Inspect or "Native"}
                    -- Value is a multiplier, not a price. No invented credits.
                    row.search = string.lower(row.skin .. " " .. row.kind .. " " .. row.finish .. " " .. tier)
                    table.insert(catalog, row); seen[row.skin] = true
                end
            end
        end
        merge(stars, true)
        if type(data.Melees) == "table" then merge(data.Melees, false) end
        table.sort(catalog, function(a, b) return a.skin < b.skin end)
        M.knifeCatalogStatus = tostring(#catalog) .. " native catalog entries"
        return true
    end
    restoreKnives = function()
        local state = owned
        owned = nil
        if not state then return end
        pcall(function()
            if state.selector.Parent == state.parent and state.selector.Value == state.id then
                state.selector.Value = state.original
            end
        end)
        pcall(function()
            if state.entry.Parent == state.skins then state.entry:Destroy() end
        end)
    end
    syncKnives = function(retry)
        if M.closed or G[GKEY] ~= M then return end
        if retry then blocked = false end
        if not CFG.KnifePreview then
            restoreKnives(); M.knivesStatus = "Local preview: OFF (re-equip knife to refresh)"; return
        end
        local inventory = child(child(LP, "Data"), "Inventory")
        local skins = child(inventory, "Skins")
        local selector = child(child(child(inventory, "Equipped"), "Skins"), "Knife")
        if owned then
            if selector ~= owned.selector or skins ~= owned.skins or owned.selector.Parent ~= owned.parent then
                restoreKnives() -- Rebind replacement player data; do not retain stale pointers.
            elseif owned.selector.Value ~= owned.id or owned.item.Value ~= owned.skin
                or owned.item.Parent ~= owned.entry or owned.entry.Parent ~= owned.skins then
                restoreKnives(); blocked = true -- A later writer wins; never oscillate.
            elseif owned.skin ~= CFG.KnifeSkin or not template(owned.skin) then
                restoreKnives()
            else
                M.knivesStatus = "Local: " .. owned.skin .. " — re-equip knife; use normal inspect key"
                return
            end
        end
        if blocked then M.knivesStatus = "Selection changed outside Hub; OFF/ON to retry"; return end
        local selected
        for _, row in ipairs(catalog) do if row.skin == CFG.KnifeSkin then selected = row; break end end
        if not selected then M.knivesStatus = "Preview ON: select a catalog knife"; return end
        if not template(selected.skin) then
            M.knivesStatus = "Unavailable locally: " .. selected.skin .. " (no native model; no unlock attempted)"; return
        end
        if not (skins and selector and selector:IsA("StringValue") and child(child(LP, "Inventory"), "Knife")) then
            M.knivesStatus = "Waiting for native knife inventory"; return
        end
        local id = "__R3ST_LocalKnife_" .. tostring(LP.UserId)
        if child(skins, id) then M.knivesStatus = "Local preview ID already owned; unchanged"; return end
        local entry = Instance.new("Folder")
        entry.Name = id
        local item = Instance.new("StringValue")
        item.Name, item.Value, item.Parent = "Item", selected.skin, entry
        -- Missing Float/Seed intentionally use SkinWear.Resolve's native defaults.
        owned = {selector = selector, parent = selector.Parent, original = selector.Value,
            id = id, entry = entry, item = item, skins = skins, skin = selected.skin}
        entry.Parent = skins
        selector.Value = id
        M.knivesStatus = "Local: " .. selected.skin .. " — re-equip knife; use normal inspect key"
    end
    M.refreshKnives = loadKnifeCatalog
end

local accuracyWeapon, accuracyOwned, accuracyConfig, accuracyFields = nil, {}, nil, {}
local cachedGunModule, gunConfig, gunRetryAt
local CONE_FIELDS = {"Base", "AdsBase", "Walk", "Run", "Jump", "Land", "BloomPerShot", "MaxBloom"}
local function restoreAccuracy()
    for object, original in pairs(accuracyOwned) do
        pcall(function()
            if object.Parent == original.parent and object.Value == 0 and original.value ~= 0 then
                object.Value = original.value
            end
        end)
    end
    if accuracyConfig then
        for key, original in pairs(accuracyFields) do
            if rawget(accuracyConfig, key) == 0 then rawset(accuracyConfig, key, original) end
        end
    end
    accuracyWeapon, accuracyOwned, accuracyConfig, accuracyFields = nil, {}, nil, {}
end
local function nativeGunConfig(name)
    local modules = RS:FindFirstChild("Modules")
    local module = modules and modules:FindFirstChild("GunConfig")
    if not module then return nil end -- Old/legacy firearm path only.
    if cachedGunModule ~= module or not gunConfig then
        if cachedGunModule == module and gunRetryAt and os.clock() < gunRetryAt then
            return nil, "Waiting to retry native GunConfig"
        end
        cachedGunModule = module
        local ok, result = pcall(require, module)
        if not ok or type(result) ~= "table" or type(result.Get) ~= "function" then
            gunConfig, gunRetryAt = nil, os.clock() + 1
            return nil, "Native GunConfig unavailable; unchanged"
        end
        gunConfig = result
    end
    local ok, config = pcall(gunConfig.Get, name)
    if not ok then return nil, "Native GunConfig.Get failed; unchanged" end
    if config ~= nil and (type(config) ~= "table" or getmetatable(config) ~= nil) then
        return nil, "Unsupported native gun schema; unchanged"
    end
    return config
end
local function numericValue(object)
    if not object or not (object:IsA("NumberValue") or object:IsA("IntValue")) then return nil end
    local value = object.Value
    if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge or value < 0 then return nil end
    return value
end
syncAccuracy = function()
    if M.closed or G[GKEY] ~= M then return end
    if not CFG.NoSpread then
        if accuracyWeapon then restoreAccuracy() end
        M.accuracyStatus = "Crosshair accuracy: OFF"
        return
    end
    local engine = RS:FindFirstChild("WeaponEngine")
    local weapons = engine and engine:FindFirstChild("Weapons")
    local gui = LP:FindFirstChild("PlayerGui")
    local hud = gui and gui:FindFirstChild("Hud")
    local framework = hud and hud:FindFirstChild("Framework")
    local vars = framework and framework:FindFirstChild("Variables")
    local equipped = vars and vars:FindFirstChild("equipped")
    local weapon = weapons and equipped and type(equipped.Value) == "string"
        and weapons:FindFirstChild(equipped.Value)
    local config, configError
    if weapon then config, configError = nativeGunConfig(weapon.Name) end
    if configError then
        if accuracyWeapon then restoreAccuracy() end
        if M.accuracyStatus ~= configError then Log.info(configError) end
        M.accuracyStatus = configError
        return
    end
    if weapon == accuracyWeapon and config == accuracyConfig and weapon then
        local changed = false
        for object, original in pairs(accuracyOwned) do
            if object.Parent ~= original.parent or object.Value ~= 0 then changed = true; break end
        end
        if not changed and config then
            for key in pairs(accuracyFields) do if rawget(config, key) ~= 0 then changed = true; break end end
        end
        if changed then
            restoreAccuracy() -- A later writer wins; restore only unchanged owned fields.
            accuracyWeapon, accuracyConfig = weapon, config -- Block retry until equip change or OFF/ON.
            M.accuracyStatus = "Spread changed outside Hub; switch OFF/ON to retry"
            Log.info(M.accuracyStatus)
        end
        return
    end
    if accuracyWeapon then restoreAccuracy() end
    M.accuracyStatus = "Waiting for a supported equipped firearm"
    if not weapon then return end
    if weapon:FindFirstChild("Knife") or weapon:FindFirstChild("Projectile")
        or table.find({"Classy", "Heal Orb", "Resurrection", "SPIKE", "Blade Storm"}, weapon.Name)
        or numericValue(weapon:FindFirstChild("Bullets")) ~= 1
        or not numericValue(weapon:FindFirstChild("FireRate")) then
        M.accuracyStatus = "Unsupported weapon (special, projectile, knife or multi-pellet)"
        return
    end
    if config then
        if config.Melee or (config.Pellets ~= nil and config.Pellets ~= 1) then
            M.accuracyStatus = "Unsupported native melee or multi-pellet gun"; return
        end
        for _, key in ipairs(CONE_FIELDS) do
            local value = rawget(config, key)
            if type(value) ~= "number" or value ~= value or value < 0 or value == math.huge then
                M.accuracyStatus = "Incomplete native cone schema; unchanged"; return
            end
        end
    end
    local spread = weapon:FindFirstChild("Spread")
    local values = {}
    if spread then
        table.insert(values, spread)
        for _, name in ipairs({"Move", "Jump", "Crouch"}) do
            local value = spread:FindFirstChild(name)
            if value then table.insert(values, value) end
        end
    end
    local legacyValid = #values == 4
    for _, value in ipairs(values) do if numericValue(value) == nil then legacyValid = false; break end end
    if not legacyValid then
        if not config then M.accuracyStatus = "Incomplete/invalid spread schema; unchanged"; return end
        values = {} -- Modern fire ignores this legacy schema; never patch a partial one.
    end
    -- 34425:3593-3600 selects GunConfig.Get's cached table, not the old Spread
    -- Values. ErrorParts at 3398-3474 consumes these eight cone fields. Preserve
    -- recoil/pattern, ammo, cadence, pellet count, camera and all shot calls.
    accuracyWeapon, accuracyConfig = weapon, config
    if config then
        for _, key in ipairs(CONE_FIELDS) do
            accuracyFields[key] = rawget(config, key)
            if accuracyFields[key] ~= 0 then rawset(config, key, 0) end
        end
    end
    for _, value in ipairs(values) do
        accuracyOwned[value] = {parent = value.Parent, value = value.Value}
        if value.Value ~= 0 then value.Value = 0 end
    end
    M.accuracyStatus = (config and "Modern + compatible legacy cone zeroed: " or "Legacy spread zeroed: ") .. weapon.Name
    Log.info(M.accuracyStatus)
end
local function draw(kind, props)
    local object = Drawing.new(kind)
    table.insert(drawings, object)
    object.Visible = false
    for key, value in pairs(props or {}) do object[key] = value end
    return object
end
local function hide(bundle)
    for _, object in ipairs(bundle.all) do object.Visible = false end
end
local function removeBundle(bundle)
    for _, object in ipairs(bundle.all) do
        pcall(function() object:Remove() end)
        local index = table.find(drawings, object)
        if index then table.remove(drawings, index) end
    end
end
local function status(player, key)
    local folder = player:FindFirstChild("Status")
    local value = folder and folder:FindFirstChild(key)
    return value and value.Value
end
local function living(player)
    local char = player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    return char, hum, hum ~= nil and hum.Health > 0 and status(player, "Alive") == true
end
local function enemy(player)
    if player == LP then return false end
    local info = RS:FindFirstChild("GameInfo")
    local mode = info and info:FindFirstChild("Gamemode")
    if mode and mode.Value == "Deathmatch" then return true end
    local own, other = status(LP, "TeamValue"), status(player, "TeamValue")
    local ownValid = own == "Attackers" or own == "Defenders"
    local otherValid = other == "Attackers" or other == "Defenders"
    return ownValid and otherValid and own ~= other
end
local function knownTeam(player)
    local a, b = status(LP, "TeamValue"), status(player, "TeamValue")
    return (a == "Attackers" or a == "Defenders") and a == b
end
local function project(camera, position)
    if Aspect then return Aspect.Project(camera, position, false) end
    return camera:WorldToViewportPoint(position)
end
local function point2(v) return Vector2.new(v.X, v.Y) end
local function rayParams(camera, char)
    local ignore = {camera}
    if LP.Character then table.insert(ignore, LP.Character) end
    local geometry = workspace:FindFirstChild("Geometry")
    if geometry then
        for _, name in ipairs({"Ray_Ignore", "Debris"}) do
            local object = geometry:FindFirstChild(name)
            if object then table.insert(ignore, object) end
        end
        local map = geometry:FindFirstChild("Map")
        if map then
            for _, name in ipairs({"Ray_Ignore", "AttackersSpawns", "DefendersSpawns", "SpawnPoints"}) do
                local object = map:FindFirstChild(name)
                if object then table.insert(ignore, object) end
            end
        end
    end
    -- Ignore cosmetic hitboxes, not actual body parts or intervening enemies.
    for _, name in ipairs({"HeadHB", "FakeHead", "Union"}) do
        local part = char:FindFirstChild(name)
        if part then table.insert(ignore, part) end
    end
    for _, child in ipairs(char:GetChildren()) do
        if child:IsA("Accoutrement") then table.insert(ignore, child) end
    end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = ignore
    params.IgnoreWater = true
    return params
end
local function visible(camera, char, part)
    local origin = camera.CFrame.Position
    local hit = workspace:Raycast(origin, part.Position - origin, rayParams(camera, char))
    return hit == nil or hit.Instance:IsDescendantOf(char)
end
local function uiBusy()
    if not focused or UIS:GetFocusedTextBox() or GuiService.MenuIsOpen then return true end
    if HOST.host and HOST.host:IsDescendantOf(game) then
        local node, hubRoot = HOST.host, nil
        while node and not node:IsA("ScreenGui") do
            if node:IsA("GuiObject") then hubRoot = node end
            node = node.Parent
        end
        -- Check the whole Hub, not this game's tab (another visible tab also blocks).
        if node and node.Enabled and hubRoot and hubRoot.Visible then return true end
    end
    return _G.BuyMenuOpen == true or _G.CommsWheelOpen == true
end
local function localReady(camera)
    local char, hum, alive = living(LP)
    if not alive or not camera or uiBusy() then return nil end
    if camera.CameraType ~= Enum.CameraType.Custom or camera.CameraSubject ~= hum then return nil end
    if hum.Sit or hum.PlatformStand then return nil end
    local gui = LP:FindFirstChild("PlayerGui")
    local hud = gui and gui:FindFirstChild("Hud")
    local framework = hud and hud:FindFirstChild("Framework")
    local vars = framework and framework:FindFirstChild("Variables")
    if not vars or status(LP, "FinishedEquipping") ~= true then return nil end
    for _, key in ipairs({"Planting", "CharacterIsBusy", "Reloading"}) do
        local flag = vars:FindFirstChild(key)
        if not flag or flag.Value ~= false then return nil end
    end
    local arms = camera:FindFirstChild("Arms")
    if arms and (arms:FindFirstChild("Equipping") or arms:FindFirstChild("Debounce")) then return nil end
    return char, hum
end
local function bindHeld()
    if CFG.AimBind == "MouseButton2" then return UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) end
    if CFG.AimBind == "MouseButton1" then return UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) end
    if CFG.AimBind == "MouseButton3" then return UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton3) end
    return UIS:IsKeyDown(Enum.KeyCode[CFG.AimBind])
end
local function aimCandidate(player, camera, center)
    if not enemy(player) then return nil end
    -- Unknown friend status fails closed until the asynchronous read completes.
    if CFG.ExcludeFriends and friendCache[player.UserId] ~= false then return nil end
    local char, _, alive = living(player)
    if not alive then return nil end
    -- Only real R15 body parts; never HRP, cosmetic hitboxes or accessory handles.
    local names = CFG.ClosestPart and {"Head", "UpperTorso", "LowerTorso",
        "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand",
        "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot"}
        or {CFG.AimPart}
    local best, chosen, distance = nil, nil, math.huge
    for _, name in ipairs(names) do
        local part = char:FindFirstChild(name)
        if part and part:IsA("BasePart") and (part.Position - camera.CFrame.Position).Magnitude <= CFG.AimRange then
            local p, onscreen = project(camera, part.Position)
            if onscreen and p.Z > 0 then
                local delta = point2(p) - center
                local length = delta.Magnitude
                if length <= CFG.Fov and length < distance and visible(camera, char, part) then
                    best, chosen, distance = delta, part, length
                end
            end
        end
    end
    return best, chosen
end
local cameraSettings
pcall(function()
    local factory = getfenv().UserSettings
    if type(factory) == "function" then cameraSettings = factory():GetService("UserGameSettings") end
end)
local function aimMouseInput(camera, part, delta)
    -- CameraInput 0076:23,173-200 uses 0.5 degrees per X input count and
    -- 0.385 per Y count, not one screen pixel. Read sensitivities; never write
    -- camera CFrame or mouse settings. Resolve scope changes every frame.
    if type(camera.CFrame.PointToObjectSpace) ~= "function" then
        M.aimInputStatus = "Screen-input fallback (camera transform unavailable)"
        return delta
    end
    local sensitivity = UIS.MouseDeltaSensitivity
    local mouseSensitivity = cameraSettings and cameraSettings.MouseSensitivity or 1
    if type(sensitivity) ~= "number" or sensitivity ~= sensitivity or sensitivity <= 0
        or sensitivity == math.huge or type(mouseSensitivity) ~= "number"
        or mouseSensitivity ~= mouseSensitivity or mouseSensitivity <= 0 or mouseSensitivity == math.huge then
        M.aimInputStatus = "Mouse sensitivity unavailable or zero; no input"
        return nil
    end
    local point = camera.CFrame:PointToObjectSpace(part.Position)
    if point.Z >= 0 then return nil end
    local yaw = math.atan2(point.X, -point.Z)
    local pitch = -math.atan2(point.Y, math.sqrt(point.X * point.X + point.Z * point.Z))
    local invert = cameraSettings and cameraSettings:GetCameraYInvertValue() or 1
    if invert ~= 1 and invert ~= -1 then return nil end
    local scale = math.rad(0.5) * sensitivity * mouseSensitivity
    M.aimInputStatus = string.format("Angular mouse input | sensitivity %.3g | engine %.3g", sensitivity, mouseSensitivity)
    return Vector2.new(yaw / scale, pitch / (scale * 0.77 * invert))
end
local function stepAim(dt, camera)
    if not (CFG.Aim or CFG.RawAim) or capturingBind or not drawingReady or not mouseReady or not localReady(camera)
        or UIS.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
        aimLatched = false
        resetAim(); return
    end
    local active = CFG.AimToggle and aimLatched or (not CFG.AimToggle and bindHeld())
    if not active then resetAim(); return end
    local center = camera.ViewportSize / 2
    local chosen, delta, aimPart
    if CFG.Sticky and not CFG.ClosestPart and target then
        delta, aimPart = aimCandidate(target, camera, center)
        if delta then chosen = target end
    end
    if not chosen then
        local best = math.huge
        for _, player in ipairs(roster) do
            local candidate, part = aimCandidate(player, camera, center)
            if candidate and candidate.Magnitude < best then
                chosen, delta, aimPart, best = player, candidate, part, candidate.Magnitude
            end
        end
    end
    if not chosen then resetAim(); return end
    if chosen ~= target then
        target = chosen
        local now = os.clock()
        if now - lastAimLog >= 1 then
            lastAimLog = now
            Log.info(string.format("aim acquired=%s radius=%.1f mode=%s strength=%.1fx", chosen.Name,
                delta.Magnitude, CFG.RawAim and "instant" or "soft", CFG.SoftStrength))
        end
    end
    local correction = aimMouseInput(camera, aimPart, delta)
    if not correction then return end
    if CFG.RawAim then
        -- Full angular correction on the first eligible frame, converted to
        -- mouse counts for current sensitivity. No smoothing or speed cap.
        if delta.Magnitude > 0 then mousemoverel(correction.X, correction.Y) end
        return
    end
    if delta.Magnitude <= 0.5 then return end -- fixed subpixel jitter guard
    -- One understandable multiplier: higher = stronger/faster. Exponential
    -- smoothing is frame-time-aware and cannot overshoot the current target.
    dt = math.clamp(dt, 0, 1 / 30)
    if dt <= 0 then return end
    local move = correction * (1 - math.exp(-10 * CFG.SoftStrength * dt))
    mousemoverel(move.X, move.Y)
end
local function stepBhop(camera)
    if not CFG.Bhop or not UIS:IsKeyDown(Enum.KeyCode.Space) then
        hopLatched = false; return
    end
    local char, hum = localReady(camera)
    if not char or char:FindFirstChild("NoJump") or hum.JumpHeight <= 0
        or not hum:GetStateEnabled(Enum.HumanoidStateType.Jumping) then return end
    if char ~= hopChar then hopChar, hopLatched, lastHop = char, false, -math.huge end
    local state = hum:GetState()
    if hum.FloorMaterial == Enum.Material.Air or state == Enum.HumanoidStateType.Freefall
        or state == Enum.HumanoidStateType.Jumping then hopLatched = false; return end
    if state ~= Enum.HumanoidStateType.Running and state ~= Enum.HumanoidStateType.Landed then return end
    if CFG.BhopMoving and hum.MoveDirection.Magnitude < 0.05 then return end
    if hopLatched or os.clock() - lastHop < CFG.HopInterval then return end
    -- Same normal jump request as framework Mobile.Jump; no persistent physics override.
    hum.Jump = true
    hopLatched, lastHop = true, os.clock()
end
local BONES = {
    {"Head", "UpperTorso"}, {"UpperTorso", "LowerTorso"},
    {"UpperTorso", "LeftUpperArm"}, {"LeftUpperArm", "LeftLowerArm"}, {"LeftLowerArm", "LeftHand"},
    {"UpperTorso", "RightUpperArm"}, {"RightUpperArm", "RightLowerArm"}, {"RightLowerArm", "RightHand"},
    {"LowerTorso", "LeftUpperLeg"}, {"LeftUpperLeg", "LeftLowerLeg"}, {"LeftLowerLeg", "LeftFoot"},
    {"LowerTorso", "RightUpperLeg"}, {"RightUpperLeg", "RightLowerLeg"}, {"RightLowerLeg", "RightFoot"},
}
local function newBundle()
    local bundle = {all = {}, edges = {}, bones = {}}
    local function add(kind, props)
        local object = draw(kind, props)
        table.insert(bundle.all, object)
        return object
    end
    for i = 1, 8 do bundle.edges[i] = add("Line") end
    for i = 1, #BONES do bundle.bones[i] = add("Line") end
    bundle.label = add("Text", {Center = true, Outline = true, Font = 2})
    bundle.hp = add("Line")
    bundle.hpBack = add("Line", {Color = Color3.new(0, 0, 0), Thickness = 4})
    bundle.snap = add("Line")
    return bundle
end
local function line(object, a, b, color, width)
    object.From, object.To = a, b
    object.Color, object.Thickness = color, width or CFG.Thickness
    object.Transparency, object.Visible = CFG.Opacity, true
end
local function paintPlayer(player, camera)
    local bundle = bundles[player]
    if not bundle then return end
    hide(bundle)
    if not CFG.Esp then return end
    local isEnemy = enemy(player)
    if not isEnemy and not (CFG.ShowTeam and knownTeam(player)) then return end
    if not CFG.Friends and friendCache[player.UserId] == true then return end
    local char, hum, alive = living(player)
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local head = char and char:FindFirstChild("Head")
    if not alive or not root or not head then return end
    local distance = (root.Position - camera.CFrame.Position).Magnitude
    if distance > CFG.EspRange then return end
    local p, onscreen = project(camera, root.Position)
    if not onscreen or p.Z <= 0 then return end
    local seen = visible(camera, char, head)
    if CFG.VisibleOnly and not seen then return end
    local hue = not seen and CFG.HiddenHue or (isEnemy and CFG.EnemyHue or CFG.TeamHue)
    local color = Color3.fromHSV(hue, CFG.Saturation, 1)
    -- Project a rig-height proxy, not GetBoundingBox (accessory sizes can be enormous).
    local upper = project(camera, root.Position + Vector3.new(0, 3, 0))
    local lower = project(camera, root.Position - Vector3.new(0, 3, 0))
    if upper.Z <= 0 or lower.Z <= 0 then return end
    local h = math.clamp(math.abs(lower.Y - upper.Y), 8, camera.ViewportSize.Y * 2)
    local side = camera.CFrame.RightVector * 1.5
    local left = project(camera, root.Position - side)
    local right = project(camera, root.Position + side)
    if left.Z <= 0 or right.Z <= 0 then return end
    local w = math.clamp(math.abs(right.X - left.X), 4, camera.ViewportSize.X * 2)
    local x, y = p.X - w / 2, math.min(upper.Y, lower.Y)
    if CFG.Boxes then
        local tl, tr = Vector2.new(x, y), Vector2.new(x + w, y)
        local bl, br = Vector2.new(x, y + h), Vector2.new(x + w, y + h)
        if CFG.Corners then
            local dx, dy = Vector2.new(w * 0.25, 0), Vector2.new(0, h * 0.2)
            local segments = {{tl, tl + dx}, {tl, tl + dy}, {tr, tr - dx}, {tr, tr + dy},
                {bl, bl + dx}, {bl, bl - dy}, {br, br - dx}, {br, br - dy}}
            for i, pair in ipairs(segments) do line(bundle.edges[i], pair[1], pair[2], color) end
        else
            for i, pair in ipairs({{tl, tr}, {tr, br}, {br, bl}, {bl, tl}}) do
                line(bundle.edges[i], pair[1], pair[2], color)
            end
        end
    end
    local text = {}
    if CFG.Names then table.insert(text, player.DisplayName) end
    if CFG.Distance then table.insert(text, tostring(math.floor(distance)) .. " st") end
    if #text > 0 then
        bundle.label.Text, bundle.label.Size = table.concat(text, " | "), CFG.TextSize
        bundle.label.Position, bundle.label.Color = Vector2.new(p.X, y - CFG.TextSize - 3), color
        bundle.label.Transparency, bundle.label.Visible = CFG.Opacity, true
    end
    if CFG.Health then
        local ratio = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
        local bottom = Vector2.new(x - 5, y + h)
        line(bundle.hpBack, bottom, Vector2.new(x - 5, y), Color3.new(0, 0, 0), 4)
        line(bundle.hp, bottom, Vector2.new(x - 5, y + h * (1 - ratio)), Color3.fromHSV(ratio / 3, 0.8, 1), 2)
    end
    if CFG.Snaplines then
        line(bundle.snap, Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y), Vector2.new(p.X, y + h), color)
    end
    if CFG.Skeleton then
        for i, pair in ipairs(BONES) do
            local a, b = char:FindFirstChild(pair[1]), char:FindFirstChild(pair[2])
            if a and b and a:IsA("BasePart") and b:IsA("BasePart") then
                local ap, av = project(camera, a.Position)
                local bp, bv = project(camera, b.Position)
                if av and bv and ap.Z > 0 and bp.Z > 0 then line(bundle.bones[i], point2(ap), point2(bp), color) end
            end
        end
    end
end
local ring, marker, spikeLabel
local function paintExtras(camera)
    ring.Visible, marker.Visible, spikeLabel.Visible = false, false, false
    if (CFG.Aim or CFG.RawAim) and CFG.ShowFov then
        ring.Position, ring.Radius = camera.ViewportSize / 2, CFG.Fov
        ring.Color, ring.Transparency, ring.Visible = Color3.fromHSV(0.7, 0.4, 1), CFG.Opacity, true
    end
    if CFG.TargetMarker and target then
        local _, part = aimCandidate(target, camera, camera.ViewportSize / 2)
        if part then
            local p, onscreen = project(camera, part.Position)
            marker.Position, marker.Visible = point2(p), onscreen and p.Z > 0
        end
    end
    if not CFG.Spike then return end
    local info = RS:FindFirstChild("GameInfo")
    local round = info and info:FindFirstChild("Round")
    local planted = round and round:FindFirstChild("SpikePlanted")
    if not planted or planted.Value ~= true then return end
    local geometry = workspace:FindFirstChild("Geometry")
    local debris = geometry and geometry:FindFirstChild("Debris")
    local spike = debris and debris:FindFirstChild("SPIKE")
    local handle = spike and spike:FindFirstChild("Handle")
    local defused = handle and handle:FindFirstChild("Defused")
    if not handle or not handle:IsA("BasePart") or (defused and defused.Value == true) then return end
    local distance = (handle.Position - camera.CFrame.Position).Magnitude
    local p, onscreen = project(camera, handle.Position)
    if distance > CFG.SpikeRange or not onscreen or p.Z <= 0 then return end
    spikeLabel.Text, spikeLabel.Position = "SPIKE | " .. math.floor(distance) .. " st", point2(p)
    spikeLabel.Size, spikeLabel.Visible = CFG.TextSize, true
end
local function refreshRoster()
    roster = Players:GetPlayers()
    local present = {}
    for _, player in ipairs(roster) do
        if player ~= LP then
            present[player] = true
            if drawingReady and not bundles[player] then bundles[player] = newBundle() end
            local read = friendReads[player]
            if not read or read.char ~= player.Character then
                read = {char = player.Character, attempts = 0, retryAt = 0}
                friendReads[player] = read
                friendCache[player.UserId] = nil
            end
            if not read.pending and friendCache[player.UserId] == nil and os.clock() >= read.retryAt then
                read.pending, read.attempts = true, math.min(read.attempts + 1, 3)
                task.spawn(function()
                    local ok, result = pcall(LP.IsFriendsWith, LP, player.UserId)
                    if M.closed or G[GKEY] ~= M or friendReads[player] ~= read
                        or player.Character ~= read.char then return end
                    read.pending, read.retryAt = false, os.clock() + (read.attempts >= 3 and 30 or 1)
                    if ok and type(result) == "boolean" then friendCache[player.UserId] = result end
                end)
            end
        end
    end
    for player, bundle in pairs(bundles) do
        if not present[player] then removeBundle(bundle); bundles[player] = nil end
    end
    for player in pairs(friendReads) do
        if not present[player] then friendReads[player] = nil; friendCache[player.UserId] = nil end
    end
end
local function recoverAspect()
    if Aspect or aspectPending or os.clock() < aspectRetryAt then return end
    local modules = RS:FindFirstChild("Modules")
    local module = modules and modules:FindFirstChild("AspectRatio")
    aspectRetryAt = os.clock() + 1
    if not module then return end
    aspectPending = true
    task.spawn(function()
        local ok, result = pcall(require, module)
        if M.closed or G[GKEY] ~= M then return end
        aspectPending = false
        if ok and type(result) == "table" and type(result.Project) == "function" then Aspect = result end
    end)
end
local function recoverTriggerState()
    local modules = RS:FindFirstChild("Modules")
    local module = modules and modules:FindFirstChild("AbilityModule")
    if module ~= abilityModule then abilityState = nil end
    if abilityState or abilityPending or os.clock() < abilityRetryAt then return end
    abilityRetryAt = os.clock() + 1
    if not module then return end
    abilityModule, abilityPending = module, true
    task.spawn(function()
        local ok, state = pcall(require, module)
        if M.closed or G[GKEY] ~= M then return end
        abilityPending = false
        if ok and type(state) == "table" and getmetatable(state) == nil then abilityState = state end
    end)
end
local BODY_PARTS = {Head = true, UpperTorso = true, LowerTorso = true,
    LeftUpperArm = true, LeftLowerArm = true, LeftHand = true,
    RightUpperArm = true, RightLowerArm = true, RightHand = true,
    LeftUpperLeg = true, LeftLowerLeg = true, LeftFoot = true,
    RightUpperLeg = true, RightLowerLeg = true, RightFoot = true}
local function stepTrigger(camera)
    -- Pulse native input; release next frame before any guard or weapon read.
    if triggerHeld then releaseTrigger(); return end
    if not CFG.Trigger or not triggerReady or capturingBind or not localReady(camera)
        or not abilityState or rawget(abilityState, "Armed") or rawget(abilityState, "Volley")
        or UIS.MouseBehavior ~= Enum.MouseBehavior.LockCenter
        or UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then return end
    local gui = LP:FindFirstChild("PlayerGui")
    local hud = gui and gui:FindFirstChild("Hud")
    local nativeHud = hud and hud:FindFirstChild("hud")
    if not hud or hud.Enabled == false or not nativeHud or nativeHud.Visible ~= true then return end
    local framework = hud:FindFirstChild("Framework")
    local vars = framework and framework:FindFirstChild("Variables")
    local equipped = vars and vars:FindFirstChild("equipped")
    local engine = RS:FindFirstChild("WeaponEngine")
    local weapons = engine and engine:FindFirstChild("Weapons")
    local gun = equipped and weapons and weapons:FindFirstChild(equipped.Value)
    local abilities = RS:FindFirstChild("AbilityEngine")
    if not gun or (abilities and abilities:FindFirstChild(gun.Name))
        or gun:FindFirstChild("Knife") or gun:FindFirstChild("Projectile")
        or table.find({"Classy", "Heal Orb", "Resurrection", "SPIKE", "Blade Storm"}, gun.Name)
        or (numericValue(gun:FindFirstChild("Bullets")) or 0) < 1
        or (numericValue(gun:FindFirstChild("FireRate")) or 0) <= 0 then return end
    local origin = camera.CFrame.Position
    local hit = workspace:Raycast(origin, camera.CFrame.LookVector * CFG.AimRange, rayParams(camera, LP.Character))
    local part = hit and hit.Instance
    if not part or not part:IsA("BasePart") or not BODY_PARTS[part.Name] then return end
    for _, player in ipairs(roster) do
        local char, _, alive = living(player)
        if part.Parent == char and alive and enemy(player) and friendCache[player.UserId] == false then
            triggerHeld = true -- Even a throwing press API must get a release.
            mouse1press()
            return
        end
    end
end
local function destroy()
    if M.closed then return end
    if pendingSave then task.cancel(pendingSave); pendingSave = nil end
    flush()
    M.closed, M.ready = true, false
    pcall(releaseTrigger)
    restoreAccuracy()
    restoreKnives()
    aimLatched, capturingBind = false, false
    resetAim()
    for _, conn in ipairs(conns) do conn:Disconnect() end
    for _, conn in pairs(playerConns) do conn:Disconnect() end
    table.clear(playerConns)
    table.clear(friendReads)
    for _, object in ipairs(drawings) do pcall(function() object:Remove() end) end
    if Shell then Shell.destroy() end
    if G[GKEY] == M then G[GKEY] = nil end
    Log.info("unloaded " .. BUILD_VERSION)
end
M.destroy = destroy
local function panic()
    aimLatched, capturingBind = false, false
    for _, key in ipairs({"Esp", "Aim", "RawAim", "Trigger", "NoSpread", "KnifePreview", "Bhop", "Spike", "ShowFov", "TargetMarker"}) do CFG[key] = false end
    resetAim()
    releaseTrigger()
    syncAccuracy()
    syncKnives(true)
    for _, bundle in pairs(bundles) do hide(bundle) end
    if ring then ring.Visible, marker.Visible, spikeLabel.Visible = false, false, false end
    saveConfig()
    Log.info("panic: all features OFF")
end
M.panic = panic

local function boot()
    loadConfig()
    loadKnifeCatalog()
    if M.closed or G[GKEY] ~= M then return end
    recoverAspect()
    recoverTriggerState()
    -- Projection must match the game's stretch mode; missing adapter blocks actuation.
    if not Aspect then Log.info("AspectRatio module unavailable; aim/ESP require adapter") end
    local ok = pcall(function()
        ring = draw("Circle", {NumSides = 64, Thickness = 1, Filled = false})
        marker = draw("Circle", {Radius = 4, Thickness = 1, Color = Color3.new(1, 1, 1), Filled = false})
        spikeLabel = draw("Text", {Center = true, Outline = true, Font = 2, Color = Color3.fromRGB(225, 180, 100)})
    end)
    drawingReady = ok
    Shell = Kit.moduleShell({
        id = "vantage", title = "Vantage", version = BUILD_VERSION,
        subtitle = "Softaim or instant aim / no detection guarantee",
        gameId = 3631977525, placeId = 9818227981,
        tabs = {"ESP", "Aim", "Weapons", "Knives", "Movement", "Experimental", "Settings"},
        cfg = CFG, save = saveConfig, live = live, conns = conns,
        onUnload = destroy, onSettings = function() Shell.show("Settings") end,
    })
    local W = Shell.W
    local function capability(key)
        if key == "Trigger" and not triggerReady then return false, "native mouse press/release unavailable" end
        if key == "NoSpread" then
            local engine = RS:FindFirstChild("WeaponEngine")
            if not (engine and engine:FindFirstChild("Weapons")) then return false, "WeaponEngine not ready" end
        end
        if (key == "Aim" or key == "RawAim") and not mouseReady then return false, "mousemoverel unavailable" end
        if key == "Esp" or key == "Aim" or key == "RawAim" or key == "Spike" or key == "ShowFov" or key == "TargetMarker" then
            if not drawingReady then return false, "Drawing unavailable" end
            if not Aspect then return false, "native AspectRatio projection unavailable" end
        end
        if key == "Aim" or key == "RawAim" or key == "NoSpread" or key == "Bhop" then
            local gui = LP:FindFirstChild("PlayerGui")
            local hud = gui and gui:FindFirstChild("Hud")
            local framework = hud and hud:FindFirstChild("Framework")
            if not (framework and framework:FindFirstChild("Variables")) then
                return false, "match framework not ready"
            end
        end
        return true
    end
    local function toggle(page, key, label)
        W.toggle(page, {label = label, key = key, get = function() return CFG[key] end,
            ready = function() return capability(key) end,
            set = function(value) set(key, value) end})
    end
    local function slider(page, key, label, step)
        W.slider(page, {label = label, key = key, min = LIMITS[key][1], max = LIMITS[key][2],
            step = step or 1, get = function() return CFG[key] end, set = function(value) set(key, value) end})
    end
    local function cycle(page, key, label)
        W.statusRow(page, function()
            local name = key == "AimPart" and (CFG[key] == "Head" and "Head" or "Chest") or CFG[key]
            return label .. ": " .. name
        end)
        W.button(page, "Change " .. label, "Cycle supported choices", function()
            local list = CHOICES[key]
            set(key, list[(table.find(list, CFG[key]) or 0) % #list + 1])
        end)
    end
    local esp = Shell.page("ESP")
    W.section(esp, "Player awareness")
    W.note(esp, "Reads replicated players. Visibility-only by default. Unknown life/team is skipped. Only confirmed friends are hidden; failed friend reads retry three times.")
    for _, row in ipairs({{"Esp", "Enable ESP"}, {"Boxes", "Boxes"}, {"Corners", "Corner boxes"},
        {"Names", "Names"}, {"Health", "Health bars"}, {"Distance", "Distance (studs)"},
        {"Skeleton", "R15 skeleton"}, {"Snaplines", "Bottom snaplines"},
        {"VisibleOnly", "Visible targets only"}, {"ShowTeam", "Include known teammates"}, {"Friends", "Include friends"}}) do
        toggle(esp, row[1], row[2])
    end
    for _, row in ipairs({{"EspRange", "ESP range (studs)", 25}, {"EspHz", "ESP updates / second", 1},
        {"Opacity", "Opacity", 0.05}, {"Thickness", "Line width", 0.5}, {"TextSize", "Text size", 1},
        {"EnemyHue", "Enemy hue", 0.01}, {"TeamHue", "Team hue", 0.01},
        {"HiddenHue", "Occluded hue", 0.01}, {"Saturation", "Color saturation", 0.05}}) do slider(esp, row[1], row[2], row[3]) end
    local aim = Shell.page("Aim")
    W.section(aim, "Shared aim controls")
    W.note(aim, "Hide Hub first. Requires locked mouse and your live character camera. Never fires. Click Aim key, then press a key or mouse button. Escape cancels; F8, End, RightShift and K stay reserved.")
    W.keybind(aim, {label = "Aim key", key = "AimBind",
        get = function() return bindingEnum(CFG.AimBind) end,
        set = function(value)
            if not value or not bindingEnum(value.Name) then return false, "Reserved or unsupported key" end
            set("AimBind", value.Name)
        end,
        capturing = function() return capturingBind end,
        onCapture = function() capturingBind = true; aimLatched = false; resetAim() end,
        onCancel = function() capturingBind = false end,
    })
    toggle(aim, "AimToggle", "Toggle aim with key (OFF = hold)")
    W.statusRow(aim, function()
        return CFG.AimToggle and (aimLatched and "Toggle: active" or "Toggle: press Aim key to activate")
            or "Hold Aim key to activate"
    end)
    W.note(aim, "Toggle activation stops on focus loss, menus, death or camera unlock. Press the key again after returning.")
    cycle(aim, "AimPart", "aim point")
    toggle(aim, "ClosestPart", "Closest aim part")
    W.note(aim, "Closest ON: nearest visible real body part to the crosshair (not nearest player distance). OFF: use Head/Chest above. Same range, circle and target checks in both modes.")
    toggle(aim, "ShowFov", "Show aim circle")
    slider(aim, "Fov", "Aim circle size (pixels)", 5)
    W.section(aim, "Softaim")
    toggle(aim, "Aim", "Enable softaim")
    slider(aim, "SoftStrength", "Softaim strength (x)", 0.1)
    W.note(aim, "1x = normal. Below 1x = gentler. Above 1x = stronger/faster. No separate reaction, acceleration or speed settings.")
    W.section(aim, "Instant aimbot (separate mode)")
    toggle(aim, "RawAim", "Enable instant aimbot")
    W.note(aim, "Full angular correction with current mouse/scope sensitivity compensation. No smoothing, delay or speed cap. Uses the same Aim key; disables softaim. Very obvious movement. Input response still needs live verification.")
    W.statusRow(aim, function() return M.aimInputStatus or "Mouse response: waiting for an active target" end)
    W.section(aim, "Target checks (both modes)")
    toggle(aim, "Sticky", "Stay on same target (fixed part only)")
    toggle(aim, "ExcludeFriends", "Skip friends")
    toggle(aim, "TargetMarker", "Mark current target")
    slider(aim, "AimRange", "Maximum target distance (studs)", 25)
    W.note(aim, "Both modes require a live enemy inside the aim circle with a clear camera ray. Neither shoots for you or aims through walls.")
    local weapons = Shell.page("Weapons")
    W.section(weapons, "Native-input triggerbot")
    toggle(weapons, "Trigger", "Enable triggerbot (OFF at boot)")
    W.note(weapons, "Hide Hub. Actual center-ray enemy body hit and known non-friend required. Native mouse pulses; game owns ammo/cadence. UI, death, reload, swap, panic and unload stop input.")
    W.section(weapons, "Crosshair accuracy")
    toggle(weapons, "NoSpread", "Crosshair accuracy (no spread)")
    W.statusRow(weapons, function() return M.accuracyStatus or "Waiting for weapon state" end)
    W.note(weapons, "Zeros the modern gun's base, scoped, walking, running, jumping, landing and bloom cone; also covers compatible legacy guns. Crosshair only, not enemy targeting. Recoil remains. No automatic firing or silent redirection.")
    W.note(weapons, "Skips shotguns, projectiles, knives, abilities and Classy special fire. Local ray accuracy is supported by the dump; server hit acceptance is unverified. OFF, panic and unload restore owned values.")
    local knives = Shell.page("Knives")
    W.section(knives, "Local knife loader")
    toggle(knives, "KnifePreview", "Enable local knife preview")
    W.statusRow(knives, function() return M.knivesStatus or "Reading local catalog" end)
    W.statusRow(knives, function() return "Selected: " .. (CFG.KnifeSkin ~= "" and CFG.KnifeSkin or "None") end)
    W.note(knives, "Only your client changes. Re-equip the knife after selecting or turning OFF. Use the game's normal inspect key. No purchase, ownership unlock or new inspect calls.")
    W.note(knives, "Native models must already exist locally; missing models are marked unavailable. Prices: Unknown (no verified shop/market source). Catalog value multipliers are not prices.")
    W.section(knives, "Knife catalog")
    local query, pageIndex, cards = "", 1, {}
    local list, rebuild
    local function selectKnife(skin)
        set("KnifeSkin", skin)
        if rebuild then rebuild() end
    end
    rebuild = function()
        if M.closed or not list then return end
        for _, card in ipairs(cards) do card:Destroy() end
        table.clear(cards)
        local rows = M.knifeRows(query)
        local pages = math.max(1, math.ceil(#rows / 8))
        pageIndex = math.clamp(pageIndex, 1, pages)
        M.knifeBrowserStatus = string.format("%d results • page %d/%d • name A–Z", #rows, pageIndex, pages)
        for index = 1, 8 do
            local row = rows[(pageIndex - 1) * 8 + index]
            if not row then break end
            local available = M.knifeAvailable(row.skin)
            local card = W.card(list, {title = row.skin,
                desc = row.tier .. " | Price: Unknown | " .. (available and "Local model" or "Model unavailable"),
                active = row.skin == CFG.KnifeSkin, index = index,
                size = UDim2.new(1, 0, 0, 76), position = UDim2.fromOffset(0, (index - 1) * 84),
                activated = function() selectKnife(row.skin) end})
            table.insert(cards, card)
        end
        if #rows == 0 then
            table.insert(cards, W.empty(list, {title = "No matching knives",
                desc = #M.knifeCatalog == 0 and M.knifeCatalogStatus or "Try another search or refresh the local catalog."}))
        end
    end
    W.search(W.row(knives, 40), {placeholder = "Search knife, finish or rarity...", changed = function(text)
        query, pageIndex = text, 1
        rebuild()
    end})
    W.statusRow(knives, function() return M.knifeBrowserStatus or "Loading catalog" end)
    W.button(knives, "Previous page", nil, function() pageIndex = math.max(1, pageIndex - 1); rebuild() end)
    W.button(knives, "Next page", nil, function() pageIndex += 1; rebuild() end)
    W.button(knives, "Refresh local catalog", "Recheck resident models; never downloads or unlocks items", function()
        loadKnifeCatalog(); syncKnives(); rebuild()
    end)
    list = W.row(knives, 8 * 84)
    rebuild()
    W.statusRow(knives, function()
        for _, row in ipairs(M.knifeCatalog) do
            if row.skin == CFG.KnifeSkin then return "Native draw: " .. row.draw .. " / inspect: " .. row.inspect end
        end
        return "Select a knife to see native animation styles"
    end)
    local movement = Shell.page("Movement")
    W.section(movement, "Normal grounded jumps")
    W.note(movement, "Hold Space. No speed, air-strafe, jump-height or velocity override. Respects NoJump and disabled Jumping. Native movement/AttachGuard remain untouched.")
    toggle(movement, "Bhop", "Auto-bhop while holding Space")
    toggle(movement, "BhopMoving", "Require movement input")
    slider(movement, "HopInterval", "Minimum jump interval (seconds)", 0.01)
    local experimental = Shell.page("Experimental")
    W.section(experimental, "Read-only spike marker")
    W.note(experimental, "Experimental: captured planted spike handle only. No defuse, interaction, timer guesses or remote calls.")
    toggle(experimental, "Spike", "Planted spike marker")
    slider(experimental, "SpikeRange", "Spike range (studs)", 25)
    local settings = Shell.page("Settings")
    W.section(settings, "State and safety")
    W.statusRow(settings, function()
        return string.format("Resumed/live: ESP=%s Softaim=%s Instant=%s Accuracy=%s Knives=%s Bhop=%s Spike=%s Trigger=%s",
            tostring(CFG.Esp), tostring(CFG.Aim), tostring(CFG.RawAim), tostring(CFG.NoSpread), tostring(CFG.KnifePreview), tostring(CFG.Bhop), tostring(CFG.Spike), tostring(CFG.Trigger))
    end)
    W.statusRow(settings, function()
        return string.format("Drawing=%s Mouse=%s Projection=%s", tostring(drawingReady), tostring(mouseReady), tostring(Aspect ~= nil))
    end)
    W.note(settings, "AttachGuard is active in the dump. No detection guarantee. F8: panic OFF. End: unload. Saved ON resumes except triggerbot, which always boots OFF.")
    W.button(settings, "Panic OFF", "Stop every feature now and save OFF", panic)
    W.button(settings, "Unload", "Disconnect and remove owned drawings", destroy)
    Shell.ready()
    M.embedded, M.root = Shell.hosted, Shell.root
    if M.closed then return end
    Log.session(string.format("boot build=%s resumed: esp=%s softaim=%s instant=%s accuracy=%s knives=%s closest=%s bhop=%s spike=%s", BUILD_VERSION,
        tostring(CFG.Esp), tostring(CFG.Aim), tostring(CFG.RawAim), tostring(CFG.NoSpread), tostring(CFG.KnifePreview), tostring(CFG.ClosestPart), tostring(CFG.Bhop), tostring(CFG.Spike)))
    syncAccuracy()
    syncKnives()
    table.insert(conns, UIS.WindowFocused:Connect(function() focused = true end))
    table.insert(conns, UIS.WindowFocusReleased:Connect(function()
        focused = false; aimLatched, capturingBind = false, false; resetAim(); releaseTrigger()
    end))
    table.insert(conns, UIS.InputBegan:Connect(function(input, processed)
        local okInput, err = pcall(function()
            local mouse = input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.MouseButton2
                or input.UserInputType == Enum.UserInputType.MouseButton3
            local name = mouse and input.UserInputType.Name or input.KeyCode.Name
            if not UIS:GetFocusedTextBox() then
                if input.KeyCode == Enum.KeyCode.F8 then panic(); return end
                if input.KeyCode == Enum.KeyCode.End then destroy(); return end
            end
            if capturingBind then
                if input.KeyCode == Enum.KeyCode.Escape then capturingBind = false; return end
                if bindingEnum(name) then set("AimBind", name); capturingBind = false end
                return -- Capturing a bind must never activate it in the same event.
            end
            if processed or UIS:GetFocusedTextBox() then return end
            if (CFG.Aim or CFG.RawAim) and CFG.AimToggle and name == CFG.AimBind
                and not uiBusy() and UIS.MouseBehavior == Enum.MouseBehavior.LockCenter
                and localReady(workspace.CurrentCamera) then
                aimLatched = not aimLatched
                resetAim()
            end
        end)
        if not okInput then Log.info("input stopped: " .. tostring(err)); panic() end
    end))
    local function watchPlayer(player)
        if player == LP or playerConns[player] then return end
        playerConns[player] = player.CharacterAdded:Connect(function()
            friendReads[player], friendCache[player.UserId] = nil, nil
            if bundles[player] then hide(bundles[player]) end
            refreshRoster()
        end)
    end
    for _, player in ipairs(Players:GetPlayers()) do watchPlayer(player) end
    table.insert(conns, Players.PlayerAdded:Connect(function(player)
        watchPlayer(player); refreshRoster()
    end))
    table.insert(conns, Players.PlayerRemoving:Connect(function(player)
        if bundles[player] then removeBundle(bundles[player]); bundles[player] = nil end
        friendReads[player], friendCache[player.UserId] = nil, nil
        if playerConns[player] then playerConns[player]:Disconnect(); playerConns[player] = nil end
        local index = table.find(roster, player)
        if index then table.remove(roster, index) end
        if target == player then resetAim() end
        releaseTrigger()
    end))
    refreshRoster()
    local elapsed = 0
    -- Mouse smoothing needs frame dt; entity refresh stays at 2 Hz and ESP at configured Hz.
    table.insert(conns, RunService.RenderStepped:Connect(function(dt)
        if M.closed then return end
        local success, err = pcall(function()
            -- Constant-size equipped-path reads catch swaps/late definitions before
            -- the next render; writes occur only on enable/equip, never oscillate.
            syncAccuracy()
            local camera = workspace.CurrentCamera
            if not camera then aimLatched = false; resetAim(); releaseTrigger(); return end
            recoverAspect()
            recoverTriggerState()
            if os.clock() - lastScan >= 0.5 then
                lastScan = os.clock(); refreshRoster(); syncKnives() -- Cosmetic checks capped at 2 Hz.
            end
            if Aspect then stepAim(dt, camera) else aimLatched = false; resetAim() end
            stepTrigger(camera)
            stepBhop(camera)
            elapsed = elapsed + dt
            if drawingReady and elapsed >= 1 / CFG.EspHz then
                elapsed = 0
                if Aspect then
                    for _, player in ipairs(roster) do if player ~= LP then paintPlayer(player, camera) end end
                    paintExtras(camera)
                end
            end
        end)
        if not success then
            -- Fail closed without emitting unprotected errors to ScriptContext/MessageOut.
            Log.info("frame stopped: " .. tostring(err))
            destroy()
        end
    end))
    M.ready = true
end
local success, err = pcall(boot)
if not success then Log.info("startup stopped: " .. tostring(err)); destroy() end
return M
