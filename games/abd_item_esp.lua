-- A Bizarre Day : Classic Items v2026-10-24.1 (2026-10-24)
-- ESP: rungs 1-2. Collection: rung 5, character physics we own; normal contact
-- pickup needs proximity. Server/nearby players see teleports and accepted pickups.
-- Items: no remotes, hooks, reparenting, speed/jump changes or console output.
-- Loading (scripts/0203.lua:22-64) checks speed/jump/fly, not CFrame distance;
-- this is NOT evidence of server teleport safety. Collector is user-requested.
-- Proof: dump 2026-10-20T02-57-50Z, scripts/0209.lua:7-30;
-- trees/Workspace.txt:63336-64002,68617-71128 (Tool + Handle, root/ItFolder).
-- Pickup evidence: trees/Workspace.txt:70717-70720,71129-71140, Handle TouchInterest.
-- Re-inject safe: self-teardown; K unload; P stops items/combat; Hub owns RightShift.
-- Player: execute hub.lua, arm Collect all for ONE sweep; confirm inventory/return.
-- Music: local mixer only; scripts/0057.lua:8-24, 0220.lua:45-50,73-78.
-- Banknote proof: trees/Workspace.txt:70717-70720,71129-71140 (Tool/Handle).
-- Cooldowns: controller-local upvalues; no hooks or synthesized attacks.
-- No attribute/property limiter exists here. Decompile-derived slot mapping fails
-- closed on changed controllers. Native busy/animation/cleanup and TS stay intact.
-- Player: enable Local cooldowns, summon SPTW, use E/R/T/V normally; compare
-- target HP in a consenting test. Logs prove LOCAL flag release, not server hits.
-- TS movement: rung 5, foreign-TS-only Anchored containment; no remote, speed,
-- teleport or limiter-script disable. Other players may see movement; enforcement
-- unknown. Proof: 0032.lua:25-58 and live SPTW timestopmovement (612-668).
-- Player: enable BEFORE a consenting player's TS, then move. Requires SPTW;
-- logs measure local displacement ONLY. A second observer must verify replication.
-- Anti-blind: local overlay properties only, 0222.lua:13-40 / 0039.lua:167-194.
-- Player: toggle Anti-blind before a consenting effect test; KCOverlay.Blind and
-- S&W Blinded only. No damage/status immunity or erased-target reconstruction.
-- Power: exact-source SPTW hito/hito2 environment adapters, NOT engine hooks.
-- Damage/radius affect normal user attacks only; accepted hits remain UNVERIFIED.
-- Defense: rung 6 Dodge()/SuperArmor(bool), native SPTW requests (live lines
-- 13,157-170,692). Server sees calls; no proof of immunity/eligibility. No spam:
-- Dodge >=3.5s, idle/healthy only; armor edge-triggered, yields to native barrage.
-- Defense toggles boot OFF every session because they fire remotes. Other
-- settings resume. OFF/P/unload restores owned helpers and releases owned armor;
-- already requested dodge expires natively. No RTZ/Deflect/invented payloads.
-- Player: arm experiments manually against consenting targets; compare target-side
-- HP, native block/regen, reach and OFF/unload/respawn. No live test was performed.
-- Changelog: 2026-10-24.1 Scoped damage/reach and experimental dodge/armor requests.
-- 2026-10-20.4 Owned anti-blind, combat readouts and independent faults.
-- 2026-10-20.3 Scoped foreign-TS movement and local outcome diagnostics.
-- 2026-10-20.2 SPTW local cooldowns, support diagnostics and restoration.
-- 2026-10-20.1 Dedicated saved Banknotes filter and count.
-- .4 All dropped-Tool ESP, including both vampire masks (0209.lua:7-30).
-- .3 Saved music toggle, music-only routing and owned unload restore.
-- .2 All dropped-Tool collection sweep with confirmed pickups and return.
-- .1 Hub-only arrows/Requiem/fruit ESP, saved filters and distances.

local BUILD_VERSION = "2026-10-24.1"
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
    distances = true, range = 0, collect = false, music = true, masks = true, other = true, banknotes = true,
    cooldowns = false, tsMovement = false, antiBlind = false, combatReadouts = true,
    damage = false, damageScale = 1.25, reach = false, reachScale = 1.25,
    dodgeGuard = false, armorHold = false,
}
local S = {
    alive = true, build = BUILD_VERSION, embedded = true, cfg = CFG,
    connections = {}, entries = {}, counts = { arrows = 0, requiem = 0, fruits = 0 },
    shown = 0, dirty = true, collectStatus = "Idle", cancelCollect = false, musicEntries = {},
}
local Shell, layer
local Combat = { bindings = {}, status = "Cooldowns OFF", nextBind = 0, releases = 0 }
S.combat = Combat
local TSState = { baseline = {}, owned = {}, status = "TS movement OFF", reanchors = 0 }
S.timeStop = TSState
local Vision = { owned = {}, status = "Anti-blind OFF", suppressions = 0 }
S.vision = Vision
S.failures = {}
local Power = { status = "Power experiments OFF", nextBind = 0, nextDodge = 0, calls = 0, nextLog = 0 }
S.power = Power
local OTHER_TYPE = { key = "other", color = Color3.fromRGB(150, 220, 255) }
local TYPES = {
    ["Banknote"] = { key = "banknotes", color = Color3.fromRGB(110, 235, 145) },
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
    for _, key in ipairs({ "damageScale", "reachScale" }) do
        local value = saved[key]
        if type(value) == "number" and value == value then CFG[key] = math.clamp(value, 1, 2) end
    end
    -- Remote actuation is per-session, never silently resumed from disk.
    CFG.dodgeGuard = false
    CFG.armorHold = false
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
    return ("enabled=%s arrows=%s requiem=%s fruits=%s distances=%s range=%d collect=%s music=%s banknotes=%s"):format(
        tostring(CFG.enabled), tostring(CFG.arrows), tostring(CFG.requiem), tostring(CFG.fruits),
        tostring(CFG.distances), CFG.range, tostring(CFG.collect), tostring(CFG.music), tostring(CFG.banknotes))
        .. (" cooldowns=%s tsMovement=%s antiBlind=%s combatReadouts=%s"):format(
            tostring(CFG.cooldowns), tostring(CFG.tsMovement), tostring(CFG.antiBlind), tostring(CFG.combatReadouts))
        .. (" damage=%s/%.2fx reach=%s/%.2fx dodgeGuard=%s armorHold=%s"):format(
            tostring(CFG.damage), CFG.damageScale, tostring(CFG.reach), CFG.reachScale,
            tostring(CFG.dodgeGuard), tostring(CFG.armorHold))
end

local function applyConfig()
    -- Signal callbacks mutate Lua state only; the spawned worker writes Instances.
    S.dirty = true
end

-- Bind only the equipped, source-verified controller. Never infer upvalue slots
-- from captured indices: the decompiler's per-function reference list owns them.
local function combatStatus(text)
    if Combat.status ~= text then Combat.status = text; Log.info("combat " .. text) end
end

local function restoreCooldowns()
    for _, b in ipairs(Combat.bindings) do
        -- Native sleeping cooldown threads were never cancelled. Return an owned
        -- early release to their control only BEFORE a proved lower-bound expiry;
        -- never resurrect a flag after its native timer may already have ended.
        if b.released and b.deadline and os.clock() < b.deadline then
            local ok, value = pcall(debug.getupvalue, b.fn, b.cd)
            if ok and value == false then
                local restored, err = pcall(debug.setupvalue, b.fn, b.cd, true)
                if not restored then Log.err("cooldown restore " .. b.name, err) end
            end
        end
    end
    table.clear(Combat.bindings)
    Combat.controller = nil
end
S.restoreCooldowns = restoreCooldowns

local function bindCooldowns(controller)
    assert(type(filtergc) == "function" and type(decompile) == "function", "filtergc/decompile unavailable")
    assert(type(debug.getupvalue) == "function" and type(debug.setupvalue) == "function", "upvalue API unavailable")
    local source = decompile(controller)
    assert(type(source) == "string", "controller decompile unavailable")
    local specs = { barrage = 5, strongpunch = 6, bearingshot = 8, dash = 6 }
    local bindings = {}
    for name, delay in pairs(specs) do
        local body = source:match("\nfunction " .. name .. "%(%)(.-)\nend;")
        assert(body, name .. " definition changed")
        local refs = body:match("%-%- upvalues: ([^\n]+)")
        assert(refs, name .. " reference list missing")
        local slots, index = {}, 0
        for symbol in refs:gmatch("([%w_]+) %([%w]+%)") do index += 1; slots[symbol] = index end
        local prefix, seconds, cdSymbol = body:match("(.*)task%.wait%(([%d%.]+)%);%s*([%w_]+) = false;%s*$")
        assert(prefix and tonumber(seconds) == delay and slots[cdSymbol], name .. " cooldown tail changed")
        local busySymbol
        for symbol in prefix:gmatch("([%w_]+) = false;") do
            if slots[symbol] and symbol ~= cdSymbol then busySymbol = symbol end
        end
        assert(busySymbol and slots[busySymbol] ~= slots[cdSymbol], name .. " busy flag missing")
        assert(body:find(cdSymbol .. " = true;", 1, true), name .. " cooldown arm missing")
        local matches = filtergc("function", { Name = name }, false)
        assert(type(matches) == "table" and getmetatable(matches) == nil, "invalid function search")
        local found
        for _, fn in next, matches do
            local ok, env = pcall(getfenv, fn)
            if ok and type(env) == "table" and rawget(env, "script") == controller then
                assert(not found, name .. " has ambiguous live closures")
                found = fn
            end
        end
        assert(found, name .. " live closure unavailable")
        local cd, busy = slots[cdSymbol], slots[busySymbol]
        assert(type(debug.getupvalue(found, cd)) == "boolean" and type(debug.getupvalue(found, busy)) == "boolean",
            name .. " live flags changed")
        bindings[#bindings + 1] = { name = name, fn = found, cd = cd, busy = busy, delay = delay,
            sampleCD = debug.getupvalue(found, cd), sampleAt = os.clock() }
        Log.info(("cooldown mapped %s cd=%d busy=%d native=%ds"):format(name, cd, busy, delay))
    end
    -- decompile may yield. A replaced/unloaded generation must never publish
    -- bindings or touch a newly spawned controller after it resumes.
    local data = Players.LocalPlayer:FindFirstChild("Data")
    local stand = data and data:FindFirstChild("Stand")
    assert(S.alive and G[GKEY] == S and CFG.cooldowns and controller.Parent == Players.LocalPlayer.Character
        and not controller.Disabled and stand and stand.Value == 40, "binding cancelled: lifecycle changed")
    Combat.bindings = bindings
    Combat.controller = controller
end

local function cooldownStep()
    local character = Players.LocalPlayer.Character
    local data = Players.LocalPlayer:FindFirstChild("Data")
    local stand = data and data:FindFirstChild("Stand")
    local controller = character and character:FindFirstChild("StarPlatinumTheWorld")
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local supported = stand and stand.Value == 40 and controller and controller:IsA("LocalScript")
        and not controller.Disabled and humanoid and humanoid.Health > 0
    if not CFG.cooldowns or not supported or Combat.controller ~= controller then
        restoreCooldowns()
    end
    if not CFG.cooldowns then combatStatus("Cooldowns OFF"); return end
    if not supported then
        combatStatus("Unsupported/currently unavailable stand=" .. tostring(stand and stand.Value) .. "; SPTW only")
        return
    end
    if not Combat.controller then
        if os.clock() < Combat.nextBind then return end
        Combat.nextBind = os.clock() + 5
        local ok, err = pcall(bindCooldowns, controller)
        if not ok then combatStatus("Cooldown binding FAILED: " .. tostring(err)); return end
        combatStatus("SPTW local cooldowns READY (E/R/T/V); server acceptance UNVERIFIED")
    end
    for _, b in ipairs(Combat.bindings) do
        local cd = debug.getupvalue(b.fn, b.cd)
        local busy = debug.getupvalue(b.fn, b.busy)
        assert(type(cd) == "boolean" and type(busy) == "boolean", "live cooldown flags changed: " .. b.name)
        -- A shared busy flag can belong to a DIFFERENT move. Track this move's
        -- own false -> true cooldown edge, then its busy -> idle cleanup.
        if cd and not b.sampleCD then
            b.tracking = true; b.sawBusy = false; b.idleSince = nil; b.released = false
            -- Previous false sample predates the native action. Its timestamp
            -- + tail delay is a LOWER bound on native expiry, never an estimate
            -- after expiry that could restore true with no timer left to clear it.
            b.deadline = b.sampleAt + b.delay
        end
        if b.tracking and busy then b.sawBusy = true; b.idleSince = nil end
        if b.tracking and b.sawBusy and not busy and not b.idleSince then
            b.idleSince = os.clock()
        end
        if cd and not busy and b.idleSince and not b.released and os.clock() - b.idleSince >= 0.15 then
            debug.setupvalue(b.fn, b.cd, false)
            assert(debug.getupvalue(b.fn, b.cd) == false, "cooldown write did not stick: " .. b.name)
            cd = false
            b.released = true; b.tracking = false; b.sawBusy = false; b.idleSince = nil
            Combat.releases += 1
            Log.info("cooldown LOCAL_RELEASE " .. b.name .. " native=" .. b.delay .. "s; server acceptance UNVERIFIED")
        end
        b.sampleCD = cd; b.sampleAt = os.clock()
    end
end

local function tsStatus(text)
    if TSState.status ~= text then TSState.status = text; Log.info("TS " .. text) end
end

local function foreignTimeStop(character)
    local lighting = game:GetService("Lighting")
    local ts = lighting and lighting:FindFirstChild("TS")
    local caster = lighting and lighting:FindFirstChild("TSer")
    return ts and caster and ts.Value == true and caster.Value ~= nil and caster.Value ~= character
end

local function restoreTimeStop()
    local character = TSState.character
    local foreign = character and foreignTimeStop(character)
    for part in pairs(TSState.owned) do
        -- SPTW has no receiver grace in TSclientHandler. While a foreign TS
        -- continues, return our unanchored parts to native freeze; at TS end
        -- leave the still-running native receiver in charge. Never unanchor here.
        if part.Parent and part:IsDescendantOf(character) and part.Anchored == false and foreign then
            part.Anchored = true
        end
    end
    if TSState.origin then
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local moved = root and (root.Position - TSState.origin).Magnitude or 0
        Log.info(("TS END localDisplacement=%.2f reanchors=%d replication=UNVERIFIED"):format(moved, TSState.reanchors))
    end
    TSState.origin = nil
    TSState.active = false
    table.clear(TSState.owned)
end
S.restoreTimeStop = restoreTimeStop

local function timeStopStep()
    local player = Players.LocalPlayer
    local character = player.Character
    if TSState.character ~= character then
        restoreTimeStop()
        table.clear(TSState.baseline)
        TSState.character = character
    end
    local data = player:FindFirstChild("Data")
    local stand = data and data:FindFirstChild("Stand")
    local controller = character and character:FindFirstChild("StarPlatinumTheWorld")
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local disabled = character and character:FindFirstChild("Disabled")
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local receiver = character and character:FindFirstChild("TSclientHandler")
    local supported = stand and stand.Value == 40 and controller and controller:IsA("LocalScript")
        and not controller.Disabled and receiver and receiver:IsA("LocalScript") and not receiver.Disabled
    local foreign = character and foreignTimeStop(character)
    local state = humanoid and humanoid:GetState()
    local states = Enum.HumanoidStateType
    local healthy = humanoid and humanoid.Health > 0 and not humanoid.Sit
        and not humanoid.PlatformStand and not (disabled and disabled.Value) and not S.collection
        and state ~= states.Ragdoll and state ~= states.FallingDown and state ~= states.Dead and state ~= states.Seated
        and humanoid:GetStateEnabled(states.Jumping) -- SPTW KnockClient disables Jumping during its knock window.
    if not CFG.tsMovement or not supported or not healthy or not root then
        restoreTimeStop()
        table.clear(TSState.baseline)
        tsStatus(not CFG.tsMovement and "TS movement OFF" or
            (not supported and "UNSUPPORTED: active SPTW + TSclientHandler required" or "PAUSED: dead/stunned/knocked/seated/collecting"))
        return
    end
    if not foreign then
        restoreTimeStop()
        -- Record non-TS anchoring, not a guess from an already-frozen character.
        table.clear(TSState.baseline)
        local ts = game:GetService("Lighting"):FindFirstChild("TS")
        if ts and ts.Value == false then
            for _, part in ipairs(character:GetDescendants()) do
                if part:IsA("BasePart") then TSState.baseline[part] = part.Anchored end
            end
        end
        tsStatus("ARMED SPTW: waiting for foreign TS (enable before stop)")
        return
    end
    if TSState.baseline[root] ~= false then
        tsStatus("WAITING: no unfrozen pre-TS root baseline; retry next foreign TS")
        return
    end
    if not TSState.active then
        TSState.active = true; TSState.origin = root.Position; TSState.reanchors = 0
        TSState.started = os.clock(); TSState.nextLog = os.clock() + 2
        Log.info("TS BEGIN scoped unanchor; native receiver remains running; server acceptance UNVERIFIED")
    end
    local released = 0
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") and TSState.baseline[part] == false then
            TSState.owned[part] = true
            if part.Anchored then
                part.Anchored = false
                assert(part.Anchored == false, "TS unanchor did not stick: " .. part.Name)
                TSState.reanchors += 1
            end
            released += 1
        end
    end
    local moved = (root.Position - TSState.origin).Magnitude
    TSState.localDisplacement = moved
    tsStatus(("ACTIVE: %d parts | replication UNVERIFIED"):format(released))
    if os.clock() >= TSState.nextLog then
        TSState.nextLog = os.clock() + 2
        Log.info(("TS SAMPLE localDisplacement=%.2f reanchors=%d; stationary is inconclusive without player input; replication UNVERIFIED")
            :format(moved, TSState.reanchors))
    end
end

local function restoreVision()
    for obj, entry in pairs(Vision.owned) do
        if obj.Parent and obj[entry.prop] == false then obj[entry.prop] = entry.original end
        Vision.owned[obj] = nil
    end
end
S.restoreVision = restoreVision

local function visionStep()
    local gui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local targets, kcReady, blinded, unsupported = {}, false, 0, 0
    if CFG.antiBlind and gui then
        for _, obj in ipairs(gui:GetChildren()) do
            if obj.Name == "Blinded" then
                local image = obj:FindFirstChildOfClass("ImageLabel")
                if obj:IsA("ScreenGui") and image then
                    targets[obj] = "Enabled"; blinded += 1
                else unsupported += 1 end
            elseif obj.Name == "KCOverlay" then
                local blind = obj:FindFirstChild("Blind")
                if obj:IsA("ScreenGui") and blind and blind:IsA("ImageLabel") then
                    targets[blind] = "Visible"; kcReady = true
                else unsupported += 1 end
            end
        end
    end
    for obj, entry in pairs(Vision.owned) do
        if not targets[obj] then
            if obj.Parent and obj[entry.prop] == false then obj[entry.prop] = entry.original end
            Vision.owned[obj] = nil
        end
    end
    for obj, prop in pairs(targets) do
        if not Vision.owned[obj] then
            Vision.owned[obj] = { prop = prop, original = obj[prop] }
            Log.info("anti-blind acquired " .. obj:GetFullName() .. "." .. prop .. " original=" .. tostring(obj[prop]))
        end
        if obj[prop] ~= false then
            obj[prop] = false
            assert(obj[prop] == false, "overlay containment did not stick: " .. obj.Name)
            Vision.suppressions += 1
        end
    end
    local status = not CFG.antiBlind and "Anti-blind OFF" or not gui and "WAITING for PlayerGui" or
        ("ARMED: KC=%s S&W=%d unsupported=%d (visual-only)"):format(kcReady and "ready" or "waiting", blinded, unsupported)
    if Vision.status ~= status then Vision.status = status; Log.info("anti-blind " .. status) end
end

local function combatReadoutStep()
    if not CFG.combatReadouts then Combat.readout = "Combat readouts OFF"; return end
    local player = Players.LocalPlayer
    local character = player.Character
    local data = player:FindFirstChild("Data")
    local stand = data and data:FindFirstChild("Stand")
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local disabled = character and character:FindFirstChild("Disabled")
    local lighting = game:GetService("Lighting")
    local ts = lighting and lighting:FindFirstChild("TS")
    local caster = lighting and lighting:FindFirstChild("TSer")
    local text = ("stand=%s HP=%s disabled=%s rootAnchored=%s TS=%s caster=%s"):format(
        tostring(stand and stand.Value), tostring(humanoid and humanoid.Health), tostring(disabled and disabled.Value),
        tostring(root and root.Anchored), tostring(ts and ts.Value), tostring(caster and caster.Value))
    Combat.readout = text
    if Combat.lastReadout ~= text then Combat.lastReadout = text; Log.info("STATE " .. text) end
end

-- Global helper replacement is confined to this controller's own environment.
-- No hookfunction/hookmetamethod, global remote interception or synthesized attack.
local function powerStatus(text)
    if Power.status ~= text then Power.status = text; Log.info("power " .. text) end
end

local function powerHealthy(b)
    local c = Players.LocalPlayer.Character
    local h = c and c:FindFirstChildOfClass("Humanoid")
    local d = c and c:FindFirstChild("Disabled")
    local ragdoll = c and c:FindFirstChild("Ragdoll")
    local root = c and c:FindFirstChild("HumanoidRootPart")
    local data = Players.LocalPlayer:FindFirstChild("Data")
    local stand = data and data:FindFirstChild("Stand")
    local state = h and h:GetState()
    return S.alive and G[GKEY] == S and c == b.character and stand and stand.Value == 40
        and b.controller.Parent == c and not b.controller.Disabled
        and h and h.Health > 0 and not h.Sit and not h.PlatformStand
        and not (d and d.Value) and not (ragdoll and ragdoll.Value)
        and state ~= Enum.HumanoidStateType.Ragdoll and state ~= Enum.HumanoidStateType.FallingDown
        and h:GetStateEnabled(Enum.HumanoidStateType.Jumping) and not foreignTimeStop(c)
        and root and not root.Anchored and not S.collection and not CFG.collect
end

local function releaseArmor(b)
    if not b.armorOwned then return end
    if Players.LocalPlayer.Character ~= b.character then
        b.armorOwned = false -- never send an old character's cleanup to a new spawn
        Log.info("ARMOR old-character ownership retired; no request sent to replacement")
        return
    end
    -- Once native E is running it owns armor and ALWAYS sends its own false.
    -- Do not overwrite that lifetime with our OFF/unload cleanup.
    local counter = debug.getupvalue(b.barrage, b.counter)
    if counter > 0 then
        b.armorOwned = false
        Log.info("ARMOR ownership returned to native barrage cleanup")
        return
    end
    b.armorRemote:FireServer(false)
    b.armorOwned = false
    Log.info("ARMOR release requested; server result UNVERIFIED")
end

local function restorePower()
    local b = Power.binding
    if not b then return end
    for _, entry in ipairs(b.helpers) do
        if rawget(b.env, entry.name) == entry.wrapper then rawset(b.env, entry.name, entry.original) end
    end
    -- Keep ownership for retry, but never turn a failed release into 20 Hz spam.
    local ok, err = pcall(releaseArmor, b)
    if not ok then Power.releaseRetry = os.clock() + 5; error(err) end
    Power.releaseRetry = nil
    Power.binding = nil
    Power.nextBind = 0
end
S.restorePower = restorePower

local function bindPower(controller)
    assert(type(decompile) == "function" and type(filtergc) == "function", "power APIs unavailable")
    local source = decompile(controller)
    assert(type(source) == "string" and #source == 33119, "SPTW source size changed")
    assert(type(crypt) == "table" and type(crypt.hash) == "function", "source hash API unavailable")
    assert(string.lower(crypt.hash(source, "sha256")) ==
        "14c1452f84d5875e134edd6aa5573e9ccb11e41f471074660e269761a8995990",
        "SPTW source fingerprint changed; adapter refused")
    local function owned(name)
        local matches = filtergc("function", { Name = name }, false)
        assert(type(matches) == "table" and getmetatable(matches) == nil, "invalid power closure search")
        local found, environment
        for _, fn in next, matches do
            local ok, env = pcall(getfenv, fn)
            if ok and type(env) == "table" and rawget(env, "script") == controller then
                assert(not found, name .. " has ambiguous closures")
                found, environment = fn, env
            end
        end
        assert(found, name .. " closure unavailable")
        return found, environment
    end
    local barrage, env = owned("barrage")
    local body = source:match("\nfunction barrage%(%)(.-)\nend;")
    local refs = body and body:match("%-%- upvalues: ([^\n]+)")
    assert(refs, "barrage references missing")
    local slots, index = {}, 0
    for symbol in refs:gmatch("([%w_]+) %([%w]+%)") do index += 1; slots[symbol] = index end
    local counter = body:match("([%w_]+) = %1 %+ 0%.5;")
    local busy = body:match("if ([%w_]+) == true then")
    assert(slots[counter] and slots[busy], "barrage state mapping changed")
    assert(type(debug.getupvalue(barrage, slots[counter])) == "number"
        and type(debug.getupvalue(barrage, slots[busy])) == "boolean", "barrage state types changed")
    local rs = game:GetService("ReplicatedStorage")
    local dodge, armor = rs:FindFirstChild("Dodge"), rs:FindFirstChild("SuperArmor")
    assert(dodge and dodge:IsA("RemoteEvent") and armor and armor:IsA("RemoteEvent"), "native defense remotes missing")
    local b = { controller = controller, character = controller.Parent, env = env, barrage = barrage,
        counter = slots[counter], busy = slots[busy], helpers = {}, dodgeRemote = dodge, armorRemote = armor }
    for _, name in ipairs({ "hito", "hito2" }) do
        local original, helperEnv = owned(name)
        assert(helperEnv == env and rawget(env, name) == original, name .. " environment has another owner")
        local entry = { name = name, original = original }
        entry.wrapper = function(part, frame, radius, damage, ...)
            if powerHealthy(b) and type(radius) == "number" and radius > 0 and radius <= 3
                and type(damage) == "number" and damage > 0 and damage <= 45 then
                local r = CFG.reach and radius * math.clamp(CFG.reachScale, 1, 2) or radius
                local d = CFG.damage and damage * math.clamp(CFG.damageScale, 1, 2) or damage
                if r ~= radius or d ~= damage then
                    Power.calls += 1
                    if os.clock() >= Power.nextLog then
                        Power.nextLog = os.clock() + 2
                        Log.info(("LOCAL_ARGS %s damage=%.2f->%.2f radius=%.2f->%.2f helperCalls=%d server=UNVERIFIED")
                            :format(name, damage, d, radius, r, Power.calls))
                    end
                end
                return original(part, frame, r, d, ...)
            end
            return original(part, frame, radius, damage, ...)
        end
        b.helpers[#b.helpers + 1] = entry
    end
    -- decompile can yield: revalidate BEFORE publishing or mutating the environment.
    assert(powerHealthy(b) and (CFG.damage or CFG.reach or CFG.dodgeGuard or CFG.armorHold),
        "power binding cancelled: lifecycle changed")
    Power.binding = b
end

local function powerStep()
    if Power.releaseRetry and os.clock() < Power.releaseRetry then
        powerStatus("Armor release FAILED; cleanup retry pending; no new requests")
        return
    end
    local enabled = CFG.damage or CFG.reach or CFG.dodgeGuard or CFG.armorHold
    local b = Power.binding
    local c = Players.LocalPlayer.Character
    if b and (not enabled or b.character ~= c or b.controller.Parent ~= c or b.controller.Disabled) then
        restorePower()
        b = nil
    end
    if not enabled then powerStatus("Power experiments OFF"); return end
    if not b then
        if os.clock() < Power.nextBind then return end
        Power.nextBind = os.clock() + 5
        local controller = c and c:FindFirstChild("StarPlatinumTheWorld")
        if not controller or not controller:IsA("LocalScript") then
            powerStatus("Power unavailable: SPTW only"); return
        end
        local ok, err = pcall(bindPower, controller)
        if not ok then powerStatus("Power binding FAILED: " .. tostring(err)); return end
        b = Power.binding
    end
    -- Do not retake another script's helper replacement. Restore only our own slots.
    for _, entry in ipairs(b.helpers) do
        local current = rawget(b.env, entry.name)
        assert(current == entry.original or current == entry.wrapper, entry.name .. " ownership changed")
        local desired = (CFG.damage or CFG.reach) and entry.wrapper or entry.original
        if current ~= desired then rawset(b.env, entry.name, desired) end
    end
    local healthy = powerHealthy(b)
    local counter = debug.getupvalue(b.barrage, b.counter)
    local busy = debug.getupvalue(b.barrage, b.busy)
    if counter > 0 and b.armorOwned then
        b.armorOwned = false -- native E took over; its existing false handles release
        Log.info("ARMOR native barrage took ownership")
    end
    if not CFG.armorHold or not healthy then releaseArmor(b)
    elseif not busy and counter == 0 and not b.armorOwned then
        b.armorRemote:FireServer(true)
        b.armorOwned = true
        Log.info("ARMOR hold requested; no damage-immunity claim; server=UNVERIFIED")
    end
    local dodgeFlag = c and c:FindFirstChild("Dodge")
    if CFG.dodgeGuard and healthy and not busy and not rawget(b.env, "dodgecooldown")
        and not rawget(b.env, "dodging") and not (dodgeFlag and dodgeFlag.Value)
        and os.clock() >= Power.nextDodge then
        Power.nextDodge = os.clock() + 3.5 -- at least native C's 0.4 + 3s spacing
        b.dodgeRemote:FireServer()
        Log.info("DODGE requested; native duration only; server=UNVERIFIED")
    end
    powerStatus((healthy and "SPTW experiments ARMED" or "SPTW experiments PAUSED")
        .. " | damage/reach local; defense requests; server UNVERIFIED")
end

local function safeRestore(label, fn)
    local ok, err = pcall(fn)
    if not ok then Log.err("restore " .. label, err) end
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
    local counts = { arrows = 0, requiem = 0, fruits = 0, masks = 0, other = 0, banknotes = 0 }
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
        safeRestore("music", restoreMusic)
        safeRestore("cooldowns", restoreCooldowns)
        safeRestore("time stop", restoreTimeStop)
        safeRestore("anti-blind", restoreVision)
        safeRestore("power", restorePower)
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
    if previous and previous.restoreCooldowns then safeRestore("previous cooldowns", previous.restoreCooldowns) end
    if previous and previous.restoreTimeStop then safeRestore("previous TS", previous.restoreTimeStop) end
    if previous and previous.restoreVision then safeRestore("previous anti-blind", previous.restoreVision) end
    if previous and previous.restorePower then safeRestore("previous power", previous.restorePower) end
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
        subtitle = "Items and stand-aware combat controls", gameId = EXPECTED_GAME, placeId = EXPECTED_PLACE,
        tabs = { "Items", "Combat", "Settings" }, keep = { layer }, cfg = CFG, save = saveConfig,
        conns = S.connections, onUnload = destroy,
        onSettings = function() Shell.show("Settings") end,
        hint = "P stops items/combat | K unloads | Hub owns RightShift",
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
    W.toggle(items, { label = "Banknotes", key = "banknotes", set = applyConfig })
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
    W.statusRow(items, function() return ("Masks: %d | Banknotes: %d | Other: %d"):format(S.counts.masks or 0, S.counts.banknotes or 0, S.counts.other or 0) end)
    W.note(items, "All replicated dropped Tools with Handles, including Vampire/Golden Vampire Masks and Requiem Arrows. Held tools and spawn markers are excluded.")
    W.note(items, "Requiem Arrow is in the game catalog but none appeared in this capture. Zero means none currently observed, not that it cannot spawn.")
    local combat = Shell.page("Combat")
    W.section(combat, "Local cooldowns")
    W.toggle(combat, { label = "Local cooldowns (SPTW)", key = "cooldowns", set = applyConfig })
    W.statusRow(combat, function() return Combat.status end)
    W.statusRow(combat, function() return "Local releases: " .. Combat.releases .. " | server acceptance UNVERIFIED" end)
    W.note(combat, "SPTW E/R/T/V only. Preserves native action timing, animations and cleanup. Time-stop casting, H/Y, block and dodge are unchanged. Unsupported stands fail closed.")
    W.note(combat, "Use moves normally. Logs identify binding/write failures and each local release; only observed target HP can prove extra hits. OFF returns known-pending cooldowns to native timers. Near uncertain expiry it leaves the flag alone rather than risk a stuck cooldown.")
    W.section(combat, "Experimental damage and melee radius (SPTW)")
    W.toggle(combat, { label = "Modify requested melee damage", key = "damage", set = applyConfig })
    W.slider(combat, { label = "Requested damage multiplier", key = "damageScale", min = 1, max = 2,
        step = 0.05, set = applyConfig })
    W.toggle(combat, { label = "Extend melee selection radius", key = "reach", set = applyConfig })
    W.slider(combat, { label = "Melee radius multiplier", key = "reachScale", min = 1, max = 2,
        step = 0.05, set = applyConfig })
    W.note(combat, "Normal SPTW E/M1/R/Y melee only. Requested damage and numerical 2-3 stud radii scale up to 2x. No part resizing, auto-attacks, extra hit requests, projectile changes or engine hooks. Server may clamp/reject; compare target-side HP and range.")
    W.section(combat, "Experimental defense requests - NOT confirmed invincibility")
    W.toggle(combat, { label = "Periodic native dodge request", key = "dodgeGuard", set = applyConfig })
    W.toggle(combat, { label = "Request armor hold", key = "armorHold", set = applyConfig })
    W.statusRow(combat, function() return Power.status end)
    W.note(combat, "Defense sends real server requests and always starts OFF each session. Dodge: idle/healthy only, >=3.5s apart, no movement; OFF stops new requests, existing dodge expires natively. Armor: one true per owned interval, false on OFF; native E retains its own armor cleanup. Armor may prevent stun without preventing damage. Neither is godmode.")
    W.note(combat, "Exact captured SPTW source only; changed/unsupported controllers fail closed. Damage/reach resume saved choices. OFF/P/unload restores owned helper functions. No RTZ, Deflect, death bypass, infinite TS or unproved projectile hitbox control.")
    W.section(combat, "Foreign time-stop movement")
    W.toggle(combat, { label = "Move during foreign TS (SPTW)", key = "tsMovement", set = applyConfig })
    W.statusRow(combat, function()
        return TSState.status .. (TSState.active and (" | local %.1f studs"):format(TSState.localDisplacement or 0) or "")
    end)
    W.note(combat, "Enable BEFORE someone else stops time. Only previously unanchored SPTW parts are released; no TS casting, duration extension, speed edits or new remotes. Native H remains unchanged.")
    W.note(combat, "Pauses for stun/knock/ragdoll, seats, death and collection. OFF during foreign TS returns owned parts to native freeze. Local motion is not proof the server or another player sees it; logs separate these claims.")
    W.section(combat, "Combat visibility")
    W.toggle(combat, { label = "Anti-blind (KC / Soft & Wet)", key = "antiBlind", set = applyConfig })
    W.statusRow(combat, function() return Vision.status end)
    W.note(combat, "Hides ONLY KCOverlay.Blind and S&W Blinded; native effect timers keep running. Does not reveal erased targets, remove stun or prevent damage. OFF/unload restores owned visibility.")
    W.toggle(combat, { label = "Combat state readouts + logs", key = "combatReadouts", set = applyConfig })
    W.statusRow(combat, function() return Combat.readout or "Waiting for character state" end)
    W.statusRow(combat, function()
        local failures = {}
        for name, err in pairs(S.failures) do failures[#failures + 1] = name .. ": " .. err end
        return #failures > 0 and ("Last failures: " .. table.concat(failures, " | ")) or "No feature worker failures recorded"
    end)
    W.note(combat, "Diagnostics: logs/abd_item_esp.log. READY/LOCAL_RELEASE describe client state, never confirmed server damage. Every feature has independent failure containment; P stops all combat overrides, K unloads.")
    local settings = Shell.page("Settings")
    W.section(settings, "Display")
    W.toggle(settings, { label = "Show distance", key = "distances", set = applyConfig })
    W.slider(settings, { label = "Range (0 = unlimited)", key = "range", min = 0, max = 10000, step = 100,
        set = applyConfig })
    W.note(settings, "Settings resume on inject, including an interrupted armed sweep. Completion saves collection OFF. Unload restores owned combat/audio state, removes labels and returns the same surviving character.")
    S.connections[#S.connections + 1] = UIS.InputBegan:Connect(function(input, processed)
        if processed or UIS:GetFocusedTextBox() then return end
        if input.KeyCode == Enum.KeyCode.P then
            CFG.enabled = false
            CFG.collect = false
            CFG.cooldowns = false
            CFG.tsMovement = false
            CFG.antiBlind = false
            CFG.damage = false
            CFG.reach = false
            CFG.dodgeGuard = false
            CFG.armorHold = false
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
                local combatOK, combatErr = pcall(cooldownStep)
                if not S.alive then break end
                if not combatOK then
                    safeRestore("cooldowns", restoreCooldowns)
                    CFG.cooldowns = false
                    S.failures.cooldowns = tostring(combatErr)
                    Log.err("cooldown worker", combatErr)
                    saveConfig()
                    combatStatus("Cooldown worker FAILED: " .. tostring(combatErr))
                end
                local powerOK, powerErr = pcall(powerStep)
                if not S.alive then break end
                if not powerOK then
                    if not Power.releaseRetry then safeRestore("power", restorePower) end
                    CFG.damage, CFG.reach, CFG.dodgeGuard, CFG.armorHold = false, false, false, false
                    S.failures.power = tostring(powerErr)
                    Log.err("power worker", powerErr)
                    saveConfig()
                    powerStatus("Power worker FAILED: " .. tostring(powerErr))
                end
                local tsOK, tsErr = pcall(timeStopStep)
                if not tsOK then
                    safeRestore("time stop", restoreTimeStop)
                    CFG.tsMovement = false
                    S.failures.tsMovement = tostring(tsErr)
                    Log.err("TS worker", tsErr)
                    saveConfig()
                    tsStatus("TS worker FAILED: " .. tostring(tsErr))
                end
                local visionOK, visionErr = pcall(visionStep)
                if not visionOK then
                    safeRestore("anti-blind", restoreVision)
                    CFG.antiBlind = false
                    S.failures.antiBlind = tostring(visionErr)
                    Log.err("anti-blind worker", visionErr)
                    saveConfig()
                end
                if os.clock() >= nextRender then
                    local readOK, readErr = pcall(combatReadoutStep)
                    if not readOK then
                        CFG.combatReadouts = false
                        S.failures.combatReadouts = tostring(readErr)
                        Log.err("combat readouts", readErr)
                        saveConfig()
                    end
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
