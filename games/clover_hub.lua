-- Clover RPG v2026-10-26.28 (2026-10-26)
-- .28 Resume all saved automation choices by explicit user request; lease active harvest aim listeners.
-- .27 Native parry pulses; fresh replay/multihit cues; broad PvE marker coverage and due-hit selection.
-- .26 Keep native guard/key teardown off the Hub remount thread.
-- .25 Time verified sword/spear HitWindow markers; release spent parry guard; trace manual broom requests.
-- .24 Permit the native grounded/detached broom Attachment; isolate game-call polls from UI.
-- .23 Accept the native ByteNet packet descriptor metatable; still require raw send.
-- .22 Isolate native map redraw calls from Hub UI/teardown threads (§9 executor quirks).
-- .21 Parry: release on readiness loss; no-fallback is one attempt per cue;
-- ignore animation callbacks without our root. Native waypoint travel without
-- a client-only nearby-portal gate; server unlock/eligibility still applies.
-- .20 Town travel page: native WaypointRemote GetData/Teleport (0136,0900),
-- rung 6, deliberate button actions only; preserves portal/unlock/server gates.
-- Progression labels are approximate, not invented level requirements.
-- .19 Experimental PvE/PvP reactive parry/guard; native BlockInput (1029:96-126,
-- 0725:20-24), rung 6, server sees normal guard requests. Default OFF; saved choice resumes.
-- Per-session bounded JSONL diagnostics; no claims of universal/impact-timed parry.
-- Broom client altitude cap/debounce lifts; native no-fly/combat/server gates stay.
-- .18 Quest assistance: one-shot nearby hymn solve (0129,0887), display-only
-- map reveal via captured quest_recon_MapService.lua render config/records, owned restore.
-- Hymn sends one native ChurchRemote Check; never fabricates Completed.
-- Auto mine/harvest start ready profession trials through native
-- startChallenge (0059:835-874); XP, busy and cooldown checks stay native.
-- Rung 6: normal ProfessionRemote Challenge request; no movement writes.
-- Native failure may warn; no console output is introduced by this module.
-- .17 Bind climb directly from the complete jump signal listing, without
-- waiting for a broad heap scan; keep bounded heap discovery as fallback.
-- .16 Resolve Climb.Start through the native JumpRequest callback (W1034:482-
-- 484), retaining exact table/capture checks when the heap scan is incomplete.
-- .15 Discover the native movement consumer from its HealthChanged signal
-- (W1030:230-250), even when the heap exceeds the bounded scan ceiling.
-- .14 Native Best armor sends: unheld Equip proved by exact replicated Face
-- acknowledgment (armor_unheld_proof.log). Native cached StateManager.get,
-- game-environment _G.Use and ProcessingInventory tag gate each request.
-- One pending, 1s spacing, 5s acknowledgment watchdog, six sends per enable.
-- .13 Combat movement: consumer-only native StateManager view ignores self-
-- action speed locks/guard slowdown and retains the pre-action sprint mode.
-- W1030:146-226; W0840:458-500. No replicated-state, WalkSpeed or physics
-- writes of our own. Native resulting motion is server-visible; acceptance
-- remains unverified. Real incapacitation, flight/crouch/swim stay native.
-- .12 Native Best armor preview + bounded queue. Rung 6 requires the native
-- Equip packet (W0001:30-64,W0725:123-127); local writes cannot equip gear.
-- Historical .12 sends were blocked pending idle/unheld proof (subsequently .14).
-- No print/warn, movement writes or automatic gear reversal.
-- W0022:94-175 scores actual rolls; W0647:69-125 owns metadata/requirements.
-- Rungs 1-2: observed entities + owned adornments; rung 3: local environment
-- and native Swiftness/Tailwind consumers. No hooks or HP writes.
-- Material/loot assistants use native callbacks/prompt holds or the exact
-- server-provided loot remotes (0082:158-164,247-329). Server sees normal
-- round reports/nearby prompt interactions (rung 6). Explicit user override:
-- all saved automation choices resume visibly; absent choices stay OFF.
-- Harvest cursor priority: lease only active session aim callbacks (0076:437-458),
-- restore on OFF/focus/close/unload; native smoothing/reports/cancel remain untouched.
-- Loot still waits for a freshly opened chest. Cursor image leases Parent/ZIndex only
-- (0086:13-28); wood ESP reads buy piles only (Workspace:54307-54325,0341:275+).
-- 0294:634-773 proves timing press; 0076:340-397 proves smooth ring aim;
-- 0341:22-31 proves MinePrompt/HarvestPrompt; 1026:361-369,605-623
-- prove native Tailwind speed and local 1s broom input debounce (not server CD).
-- Server sees resulting movement only; server acceptance/tolerances are unknown.
-- World dump 2026-10-26T00-59-25Z: 0138:24-26, 0110:144-195,
-- 0123:447-515, 0136:59-64, 0288:7-20, 1030:209-258, 0520:383-403.
-- No universal auto dodge/parry claims: server hit timing/eligibility unproved.
-- Re-inject safe: self-teardown; F8 panic, End unload; Hub owns RightShift.
-- Climb: local native-table limiter wrapper (rung 4 equivalent, no script disable).
-- 1034:183-186,376-494; 0840:650-660. Native motion is server-visible;
-- no physics/remote writes. Default OFF; saved client-only choice resumes.
-- Dash: instance CanDash skips DashCooldown; replicated Dodging is replaced
-- by actual native active-motion handles (0840:480-483,591-600; 1036:173-196).
-- Manual input retains native packets/velocity; server cooldown/i-frames unknown.
-- .9 Dump-only advanced movement: native fall-report flag (1039:62-83),
-- slide timer table (1037:155-175), selected penalty table (1030:23-92),
-- shared broom bonus cell (1026:359-369,429,515-567). Fall uses rung 3;
-- other native VM table/upvalue patches are outside the numbered ladder:
-- no equivalent attribute was found; Tailwind alone cannot supply a slider.
-- No new remotes, hookfunction/metatable hooks, HP or direct physics writes.
-- Native motion remains server-visible; damage prevention/server acceptance
-- and runtime adapter access are LIVE_UNVERIFIED. Saved choices resume visibly.
-- Changelog: .11 Shared bounded adapter discovery, lean validation,
-- kit-owned UI polling and admission-first passive recording. No new game calls.
-- .10 Chain local dashes after native StopDash; do not wait for
-- replicated Dodging to clear (1036:173-196,230-235; 0840:480-483,591-599).
-- Active native motion and all non-cooldown combat locks remain intact.
-- .9 Four movement controls with owned restore and broom bonus slider.
-- .8 Manual local dash cooldown gate; attack-specific defense capture.
-- .7 Triple ESP range, including saved distances and label draw cap.
-- .6 Buyable wood ESP, requested material resume, native cursor lift.
-- .5 Respect replicated loot timer, cancel stale/dead sessions,
-- observe container removals (not inventory receipt), truthful assistant status.
-- .4 Ownership-checked native CanClimb wrapper; no latch writes.
-- .3 Gathering: retry late adapters, stop on character loss,
-- validate resource roots/held prompts and release stale ring ownership.
-- .2 Hub shipment: native gathering, opened-chest collection,
-- local broom controls and reviewed session/lifecycle guards.
-- .1 Streamed awareness, adaptive fullbright, native local swiftness,
-- vitals/cooldown readouts and passive PvE event recording for defense research.
local BUILD_VERSION = "2026-10-26.28"
local GKEY = "__CLOVER_HUB"
local CONFIG_FILE = "clover_hub_config.json"
local G = getgenv()
local HOST = G.__R3ST_HOST
local Log = loadfile("log.lua")()("clover_hub", { print = false })
if game.GameId ~= 3164482049 or (game.PlaceId ~= 8248288152 and game.PlaceId ~= 8248164019) then
    Log.info("identity rejected")
    return
end
if G[GKEY] and G[GKEY].destroy then pcall(G[GKEY].destroy) end
if not (HOST and HOST.ui and HOST.host) then
    Log.info("Hub required: execute hub.lua")
    return
end
local Players = game:GetService("Players")
local Collection = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Http = game:GetService("HttpService")
local UIS = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer

-- CORE_BEGIN: actual-source tests execute these helpers, not translated copies.
local Core = {}
Core.defaults = {
    schema = 1, esp = false, players = true, enemies = true, indicators = true,
    npcs = true, ores = true, crops = true, wood = true, waypoints = true, chams = true,
    range = 3600, rangeVersion = 2, limit = 48, filter = "", healthBars = true, healthRange = 600, fullbright = false,
    brightness = 2, exposure = 0, movement = false, speed = 4.5, record = false,
    broomSpeed = false, broomDelay = false, autoMine = false, autoHarvest = false, autoStart = false,
    autoLoot = false, lootItems = false, climb = false, dash = false, autoArmor = false,
    noFall = false, chainSlide = false, combatMove = false, broomBoost = false, broomBonus = 25,
    revealMap = false, autoParry = false, parryPve = true, parryPvp = true,
    parryFallback = true, parryRange = 24, parrySpellRange = 90, broomAltitude = false,
}
function Core.config(saved)
    local cfg = table.clone(Core.defaults)
    if type(saved) ~= "table" or saved.schema ~= 1 then return cfg end
    for k, v in pairs(cfg) do
        if type(v) == "boolean" and type(saved[k]) == "boolean" then cfg[k] = saved[k] end
    end
    -- Upgrade saved ESP distances once; keep subsequent user choices unchanged.
    local range = saved.range
    if type(range) == "number" and range == range then
        if saved.rangeVersion ~= 2 then range = math.clamp(range, 50, 3000) * 3 end
        cfg.range = math.clamp(range, 150, 9000)
    end
    for k, bounds in pairs({ healthRange = {50, 3000}, limit = {8, 64}, brightness = {1, 4},
        exposure = {-1, 1}, speed = {0, 4.5}, broomBonus = {0, 200}, parryRange = {8, 60}, parrySpellRange = {20, 150} }) do
        local v = saved[k]
        if type(v) == "number" and v == v and (k ~= "broomBonus" or math.abs(v) < math.huge) then
            cfg[k] = math.clamp(v, bounds[1], bounds[2])
        end
    end
    -- Explicit user request permits ALL saved automation choices to resume.
    -- Missing choices remain OFF; preserve native readiness/manual ownership.
    cfg.limit = math.floor(cfg.limit)
    if type(saved.filter) == "string" then cfg.filter = saved.filter:sub(1, 64) end
    return cfg
end
function Core.healthStyle(hp, maxHp, distance, range)
    local visible = type(hp) == "number" and type(maxHp) == "number" and maxHp > 0
        and hp > 0 and distance <= range
    return {visible = visible, fraction = visible and math.clamp(hp / maxHp, 0, 1) or 0,
        width = math.floor(70 + 70 * math.clamp(1 - distance / math.max(range, 1), 0, 1))}
end
-- Every owned field carries its baseline and last written value. Environmental
-- updates become the new restore target; movement instead yields to other writers.
function Core.own(store, object, key, desired, read, write, adaptive)
    local fields = store[object]
    if not fields then fields = {}; store[object] = fields end
    local item = fields[key]
    local current = read(object, key)
    if not item then
        item = { original = current, last = current }; fields[key] = item
    elseif current ~= item.last then
        if not adaptive then item.conflict = true; return false end
        item.original = current
    end
    if item.conflict then return false end
    if current ~= desired then write(object, key, desired) end
    item.last = desired
    return true
end
function Core.restore(store, read, write)
    for object, fields in pairs(store) do
        for key, item in pairs(fields) do
            pcall(function()
                if not item.conflict and read(object, key) == item.last then write(object, key, item.original) end
            end)
        end
    end
    table.clear(store)
end
function Core.choose(rows, cfg)
    local chosen = {}
    local filter = cfg.filter:lower()
    for _, row in ipairs(rows) do
        if cfg[row.category] and row.distance <= cfg.range and row.alive ~= false
            and (filter == "" or row.name:lower():find(filter, 1, true)) then
            chosen[#chosen + 1] = row
        end
    end
    table.sort(chosen, function(a, b)
        if a.distance == b.distance then return a.order < b.order end
        return a.distance < b.distance
    end)
    for i = #chosen, cfg.limit + 1, -1 do chosen[i] = nil end
    return chosen
end
function Core.mineReady(round, now)
    if type(round) ~= "table" or getmetatable(round) ~= nil or round.pressed then return false end
    for _, key in ipairs({"StartTime", "StartPos", "Speed", "RedStart", "RedSize", "drawnTime"}) do
        local v = round[key]
        if type(v) ~= "number" or v ~= v or math.abs(v) == math.huge then return false end
    end
    local t = round.drawnTime
    if t < round.StartTime or t > now or now - t > 0.15 or round.RedSize <= 0 or round.RedSize > 1 then return false end
    local direction = round.Direction or 1
    if direction ~= 1 and direction ~= -1 then return false end
    local position = (round.StartPos + direction * round.Speed * (t - round.StartTime)) % 1
    local center = (round.RedStart + round.RedSize / 2) % 1
    return math.abs((position - center + 0.5) % 1 - 0.5) <= round.RedSize * 0.3
end
function Core.ringTarget(rings, now)
    local first, deadline
    for _, ring in next, rings do
        if type(ring) == "table" and getmetatable(ring) == nil and not ring.reported
            and type(ring.startTime) == "number" and type(ring.travel) == "number"
            and type(ring.gapCenter) == "number" and type(ring.spin) == "number" then
            local when = ring.startTime + ring.travel
            if when >= now - 0.05 and (not deadline or when < deadline) then first = ring; deadline = when end
        end
    end
    if not first then return nil end
    return (first.gapCenter + first.spin * first.travel) % 360
end
-- Armor data and queue are pure: no Instances are modified and no game calls
-- are discovered here. Tests provide explicit adapters; production stays gated.
Core.armorSlots = {"Back", "Chest", "Face", "Helmet", "Legs", "Neck"}
function Core.armorNumber(v)
    return type(v) == "number" and v == v and math.abs(v) < math.huge
end
function Core.parseArmorStats(text)
    if type(text) ~= "string" then return nil, "unknown Stats" end
    -- Keep the native token pattern, but fail closed on changed/malformed data.
    local residue = text:gsub("([%w_]+)%s+(%-?[%d%.]+)", ""):gsub("[%s,]", "")
    if residue ~= "" then return nil, "unknown Stats shape" end
    local stats = {}
    for key, number in text:gmatch("([%w_]+)%s+(%-?[%d%.]+)") do
        local value = tonumber(number)
        if not Core.armorNumber(value) then return nil, "invalid Stats" end
        stats[key] = (stats[key] or 0) + value
        if not Core.armorNumber(stats[key]) then return nil, "invalid Stats sum" end
    end
    return stats
end
function Core.armorEligible(row, attributes)
    if not row.owned or not Core.armorNumber(row.stock) or row.stock <= 0 then return false end
    local required = row.definition.Required
    if required == nil then return true end
    if type(required) ~= "table" or getmetatable(required) ~= nil then return false end
    for key, minimum in pairs(required) do
        if type(key) ~= "string" or not Core.armorNumber(minimum)
            or not Core.armorNumber(attributes[key]) or attributes[key] < minimum then return false end
    end
    return true
end
function Core.rankArmor(snapshot, checkpoint)
    local maxima, byName, winners, scores = {}, {}, {}, {}
    local result = {plan = {}, paused = {}, scores = scores}
    for _, row in ipairs(snapshot.rows) do
        if checkpoint and not checkpoint() then return nil, "cancelled" end
        local def = row.definition
        if type(def) ~= "table" or getmetatable(def) ~= nil or type(def.Type) ~= "string" then
            return nil, "unknown definition"
        end
        byName[row.name] = row
        -- Native weapons do not enter the rolled-stat normalization population.
        if not def.BaseDamage then
            local stats, reason = Core.parseArmorStats(row.stats)
            if not stats then return nil, reason end
            scores[row] = stats
            for key, value in pairs(stats) do maxima[key] = math.max(maxima[key] or 0, value) end
        end
    end
    local function better(a, b)
        if not b or a.score > b.score then return true end
        if a.score ~= b.score then return false end
        if a.quality ~= b.quality then return a.quality > b.quality end
        if a.display ~= b.display then return a.display < b.display end
        return a.name < b.name
    end
    for _, row in ipairs(snapshot.rows) do
        if checkpoint and not checkpoint() then return nil, "cancelled" end
        local stats = scores[row]
        if stats then
            local score = 0
            for key, value in pairs(stats) do score += value / math.max(maxima[key], 1) end
            if not Core.armorNumber(score) then return nil, "invalid score" end
            scores[row] = score
            local def = row.definition
            local slotKnown = table.find(Core.armorSlots, def.ArmorType) ~= nil
            if def.Type == "Armor" and slotKnown and Core.armorEligible(row, snapshot.attributes) then
                local candidate = {row = row, score = score, name = row.name,
                    quality = Core.armorNumber(row.quality) and row.quality or 0,
                    display = tostring(def.DisplayName or row.name:match("^[^_]+") or row.name):lower()}
                if better(candidate, winners[def.ArmorType]) then winners[def.ArmorType] = candidate end
            end
        end
    end
    for _, slot in ipairs(Core.armorSlots) do
        local name, best = snapshot.equipped[slot], winners[slot]
        local current = name and name ~= "" and byName[name] or nil
        if name and name ~= "" and (not current or not current.owned
            or not Core.armorEligible(current, snapshot.attributes)
            or current.definition.Type ~= "Armor" or current.definition.ArmorType ~= slot
            or type(scores[current]) ~= "number") then
            result.paused[slot] = "unknown current item"
        elseif best and best.score > 0 and (not current or best.score - scores[current] > 1e-9) then
            result.plan[#result.plan + 1] = {slot = slot, row = best.row, score = best.score}
        end
    end
    return result
end
-- One serialized queue. Every send rebuilds and compares the current winner.
-- Watchdog/budget pauses latch until explicit re-enable; no remote retry loop.
function Core.armorQueue(adapter)
    local q = {enabled = false, generation = 0, status = "OFF", sent = 0, rebuilds = 0}
    function q.stop(reason)
        q.generation += 1; q.pending = nil; q.plan = nil; q.due = nil
        q.enabled = false; q.status = reason or "OFF"
    end
    function q.markDirty(now)
        q.generation += 1; q.plan = nil
        if not q.due then q.due = now + 0.25 end
    end
    function q.enable(now)
        q.stop(); q.enabled = true; q.sent = 0; q.nextSend = now
        q.markDirty(now); q.status = "Scanning armor"
    end
    function q.pause(reason)
        q.stop("Paused: " .. reason)
    end
    local function rank()
        local generation = q.generation
        local snapshot, reason = adapter.snapshot()
        if not q.enabled or generation ~= q.generation then return nil, "cancelled" end
        if not snapshot then return nil, reason end
        local result, why = Core.rankArmor(snapshot, function()
            if adapter.checkpoint then adapter.checkpoint() end
            return q.enabled and generation == q.generation
        end)
        if not q.enabled or generation ~= q.generation then return nil, "cancelled" end
        q.rebuilds += 1
        return result, why
    end
    function q.step(now)
        if not q.enabled then return end
        if q.pending then
            local p = q.pending
            if not adapter.owned(p.row) then q.pause("pending item removed"); return end
            local equipped = adapter.equipped(p.slot)
            if equipped == p.row.name then
                q.pending = nil; q.markDirty(now)
            elseif equipped ~= p.previous then q.pause("slot mismatch"); return
            elseif now - p.time >= 5 then q.pause("unconfirmed equip (no retry)"); return
            else return end
        end
        if q.due and now >= q.due then
            q.due = nil -- a dirty event during a yield must schedule a NEW batch
            local result, reason = rank()
            if not result then
                if reason ~= "cancelled" then q.status = "Paused: " .. tostring(reason) end
                return
            end
            q.plan = result.plan; q.paused = result.paused
        end
        if not q.plan then return end
        if #q.plan == 0 then
            q.status = next(q.paused) and "Paused: unknown current item" or "Best usable armor equipped"
            return
        end
        local reason = adapter.safe()
        if reason then q.status = reason; return end
        if not adapter.proven then q.status = "Paused: idle/unheld equip proof required (preview only)"; return end
        if q.sent >= 6 then q.pause("six-request budget exhausted"); return end
        if now < q.nextSend then return end
        local planned, generation = q.plan[1], q.generation
        local fresh, why = rank()
        if not fresh then
            if why ~= "cancelled" then q.status = "Paused: " .. tostring(why) end
            return
        end
        local winner = fresh.plan[1]
        if not winner or winner.slot ~= planned.slot or winner.row.item ~= planned.row.item
            or winner.row.name ~= planned.row.name or winner.row.stats ~= planned.row.stats then
            q.markDirty(now); return
        end
        if not q.enabled or generation ~= q.generation or not adapter.owned(winner.row) then return end
        reason = adapter.safe()
        if reason then q.status = reason; return end
        if not q.enabled or generation ~= q.generation then return end
        if type(adapter.send) ~= "function" then q.pause("native packet unavailable"); return end
        q.pending = {row = winner.row, slot = winner.slot, previous = adapter.equipped(winner.slot), time = now}
        q.sent += 1; q.nextSend = now + 1; q.status = "Equipping " .. winner.slot
        -- Set pending BEFORE calling the packet: it has no success return.
        local ok = pcall(adapter.send, winner.row.item)
        if not ok then q.pause("native packet error (no retry)") end
    end
    return q
end
-- CORE_END

local CFG = Core.config(nil)
local S = { alive = true, build = BUILD_VERSION, embedded = true, cfg = CFG,
    conns = {}, live = {}, shown = 0, discovered = 0, overflow = false,
    events = 0, latest = "No events observed", movementStatus = "OFF", failures = {} }
local Shell, layer, saveTask
local environment, clockFields, movementFields = {}, {}, {}
local ringFields, broomObject, broomAction, broomBoundCharacter = {}, nil, nil, nil
local nextBroomBind = 0
local Armor -- event-driven inventory owner; production packet path is proof-gated
local Climb -- owns only the native table slot, never the shared airborne/ledge cells
local Dash -- owns only the current character's StateManager.CanDash slot
local Advanced -- dump-backed owned native movement adapters; no remote calls
local lootSession, lootStatus = nil, "Open a chest after enabling"
local lootArmed = false -- arm only after observing the native loot UI closed
local lootSequence, nextLootSend = 0, 0
local nativeTiming, nativePress, nativeRings
local HarvestInput
local materialCharacter, nextMaterialBind = nil, 0
local holdPrompt, holdDeadline, retryAt = nil, 0, setmetatable({}, {__mode = "k"})
local materialStatus, broomStatus = "Manual start; assistants OFF", "OFF"
local markers, records, queue = {}, {}, {}
local candidates, selectionCache = {}, {}
local stagedRecords, stagedCandidates, discovering = {}, {}, false
local cursor, nextDiscovery, lastCharacter = 1, 0, nil
local attributesRead = function(o, k) return o:GetAttribute(k) end
local attributesWrite = function(o, k, v) o:SetAttribute(k, v) end
local propertiesRead = function(o, k) return o[k] end
local propertiesWrite = function(o, k, v) o[k] = v end
-- 0086 retains this exact image and keeps native position/image updates alive.
-- Never write input, camera, visibility or image fields. No clone or extra GUI.
local NativeCursor = {lease = nil, blocked = setmetatable({}, {__mode = "k"})}
function NativeCursor.release()
    local lease = NativeCursor.lease
    NativeCursor.lease = nil
    if not lease then return end
    pcall(function()
        if lease.icon.ZIndex == lease.z then lease.icon.ZIndex = lease.originalZ end
    end)
    pcall(function()
        if lease.icon.Parent == lease.screen then
            -- Do not strand the image under a Hub that is about to be destroyed
            -- if its native screen has itself gone away.
            lease.icon.Parent = lease.permanent.Parent and lease.permanent or nil
        end
    end)
end
function NativeCursor.step()
    local hub = G.__R3ST_HUB
    local view = hub and type(hub.inspect) == "function" and hub.inspect()
    local screen = view and view.screen
    local open = view and view.alive and screen and screen.Parent and screen.Enabled
        and view.root and view.root.Parent and view.root.Visible and HOST.host:IsDescendantOf(screen)
    local gui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local permanent = gui and gui:FindFirstChild("Permanent")
    local controller = permanent and permanent:FindFirstChild("Cursor")
    local nativeReady = permanent and permanent:IsA("ScreenGui") and permanent.Enabled
        and controller and controller:IsA("LocalScript") and not controller.Disabled
    local sameSpace = nativeReady and screen and permanent.IgnoreGuiInset == screen.IgnoreGuiInset
        and permanent.AbsolutePosition == screen.AbsolutePosition and permanent.AbsoluteSize == screen.AbsoluteSize
    local lease = NativeCursor.lease
    if lease then
        local owned = lease.icon.Parent == lease.screen and lease.icon.ZIndex == lease.z
        if not owned then NativeCursor.blocked[lease.icon] = true end
        local replacement = permanent and permanent:FindFirstChild("MouseIcon")
        if not owned or not open or not nativeReady or not sameSpace or permanent ~= lease.permanent
            or screen ~= lease.screen or controller ~= lease.controller or not lease.icon.Visible
            or (replacement and replacement ~= lease.icon) then NativeCursor.release() end
        return
    end
    if not open or not nativeReady or not sameSpace then return end
    local icon = permanent:FindFirstChild("MouseIcon")
    if not (icon and icon:IsA("ImageLabel") and icon.Visible) or NativeCursor.blocked[icon] then return end
    NativeCursor.lease = {icon = icon, permanent = permanent, controller = controller,
        screen = screen, originalZ = icon.ZIndex, z = 10000}
    icon.ZIndex = 10000; icon.Parent = screen
end
local COLORS = {
    enemies = Color3.fromRGB(255, 125, 105), indicators = Color3.fromRGB(255, 205, 90),
    players = Color3.fromRGB(135, 195, 255), npcs = Color3.fromRGB(170, 150, 255),
    ores = Color3.fromRGB(100, 230, 240), crops = Color3.fromRGB(120, 235, 140),
    waypoints = Color3.fromRGB(245, 235, 160), wood = Color3.fromRGB(215, 170, 110),
}
local function guard(tag, fn)
    local ok, err = xpcall(fn, debug.traceback)
    if not ok and not S.failures[tag] then S.failures[tag] = true; Log.err(tag, err) end
    return ok
end
local function loadConfig()
    local ok, raw = pcall(readfile, CONFIG_FILE)
    if not ok then return end
    local decoded, data = pcall(Http.JSONDecode, Http, raw)
    if decoded then CFG = Core.config(data); S.cfg = CFG end
end
local function saveConfig()
    if not S.alive or G[GKEY] ~= S then return end
    local ok, raw = pcall(Http.JSONEncode, Http, CFG)
    if ok then
        local wrote, err = pcall(writefile, CONFIG_FILE, raw)
        if not wrote then Log.err("config", err) end
    end
end
local function scheduleSave()
    if saveTask then pcall(task.cancel, saveTask) end
    saveTask = task.delay(0.5, function()
        saveTask = nil
        if S.alive and G[GKEY] == S then saveConfig() end
    end)
end
local function connect(signal, fn)
    local c = signal:Connect(fn); S.conns[#S.conns + 1] = c; return c
end
local function rootOf(model)
    if model:IsA("BasePart") then return model end
    if not model:IsA("Model") then return nil end
    local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
        or model:FindFirstChild("Handle") or model:FindFirstChild("Torso") or model:FindFirstChild("Head")
        or model:FindFirstChildWhichIsA("BasePart")
    return root and root:IsA("BasePart") and root or nil
end
local function clearMarkers()
    for object, item in pairs(markers) do
        item.gui:Destroy(); item.highlight:Destroy(); markers[object] = nil
    end
    S.shown = 0
end
local function releaseEnvironment()
    Core.restore(environment, propertiesRead, propertiesWrite)
    Core.restore(clockFields, attributesRead, attributesWrite)
end
local function releaseMovement()
    Core.restore(movementFields, attributesRead, attributesWrite)
    lastCharacter = nil
    S.movementStatus = "OFF"
end
local function releaseHold()
    if holdPrompt then pcall(function() holdPrompt:InputHoldEnd() end); holdPrompt = nil end
end
local function releaseMaterials()
    if HarvestInput then HarvestInput.release() end
    Core.restore(ringFields, propertiesRead, propertiesWrite)
    S.lastHarvestSession = nil
    releaseHold()
end
local function materialAlive()
    if not (CFG.autoMine or CFG.autoHarvest or CFG.autoStart) then
        materialCharacter = nil; S.materialCharacterLost = false
        materialStatus = "Manual start; assistants OFF"
        return false
    end
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not materialCharacter and not S.materialCharacterLost and (not hum or hum.Health <= 0) then
        materialStatus = "Saved assistants ON · waiting for a living character"
        return false
    end
    if S.materialCharacterLost or not char or not hum or hum.Health <= 0 or (materialCharacter and materialCharacter ~= char) then
        S.materialCharacterLost = false
        CFG.autoMine = false; CFG.autoHarvest = false; CFG.autoStart = false
        materialCharacter = nil; releaseMaterials(); scheduleSave()
        materialStatus = "Character lost · re-enable material assistants this session"
        Log.info("materials OFF: character lost/replaced")
        return false
    end
    materialCharacter = char
    return true
end
local function releaseBroom()
    if broomObject then broomObject:Destroy(); broomObject = nil end
    broomStatus = "OFF"
end
local function applyConfig()
    if not CFG.autoHarvest then
        if HarvestInput then HarvestInput.release() end
        Core.restore(ringFields, propertiesRead, propertiesWrite); S.lastHarvestSession = nil
    end
    if not CFG.autoStart or not (CFG.autoMine or CFG.autoHarvest) then releaseHold() end
    if not CFG.broomSpeed then releaseBroom() end
    if not CFG.climb and Climb then Climb.release(); Climb.blocked = nil end
    if not CFG.dash and Dash then Dash.release(); Dash.blocked = nil end
    if Advanced then Advanced.apply() end
    if not CFG.esp then clearMarkers() end
    if not CFG.fullbright then releaseEnvironment() end
    if not CFG.movement then releaseMovement() end
end
local function requestApply() S.pendingApply = true end
local function requestUnload() S.unloadRequested = true end
local function fullbrightStep()
    if not CFG.fullbright then return end
    Core.own(clockFields, Lighting, "ClockDisabled", true, attributesRead, attributesWrite, true)
    local desired = {
        ClockTime = 14, Brightness = CFG.brightness, ExposureCompensation = CFG.exposure,
        Ambient = Color3.fromRGB(170, 170, 170), OutdoorAmbient = Color3.fromRGB(170, 170, 170),
        GlobalShadows = false, FogStart = 0, FogEnd = 100000,
        EnvironmentDiffuseScale = 1, EnvironmentSpecularScale = 0.5,
    }
    for key, value in pairs(desired) do Core.own(environment, Lighting, key, value, propertiesRead, propertiesWrite, true) end
    -- Only environment postprocessing, never warning UI or combat effects.
    for _, parent in ipairs({ Lighting, workspace.CurrentCamera or Lighting }) do
        local children = parent:GetChildren()
        for i = 1, math.min(#children, 96) do
            local effect = children[i]
            if effect:IsA("Atmosphere") then
                for key, value in pairs({Density = 0, Haze = 0, Glare = 0}) do
                    Core.own(environment, effect, key, value, propertiesRead, propertiesWrite, true)
                end
            elseif effect:IsA("ColorCorrectionEffect") or effect:IsA("BloomEffect")
                or effect:IsA("DepthOfFieldEffect") or effect:IsA("SunRaysEffect") then
                Core.own(environment, effect, "Enabled", false, propertiesRead, propertiesWrite, true)
            end
        end
    end
    -- Removed streamed effects must not remain strongly retained forever.
    for object in pairs(environment) do if not object.Parent and object ~= Lighting then environment[object] = nil end end
end
local function movementStep()
    local char = LocalPlayer.Character
    if not CFG.movement or not char then return end
    if char ~= lastCharacter then
        releaseMovement(); lastCharacter = char
        local untilTime = workspace:GetServerTimeNow() + 225
        Core.own(movementFields, char, "PotionEnd_Swiftness", untilTime, attributesRead, attributesWrite, false)
        Core.own(movementFields, char, "PotionPower_Swiftness", CFG.speed, attributesRead, attributesWrite, false)
        S.movementStatus = "Native local +" .. tostring(CFG.speed) .. " (225s; server unverified)"
    else
        local fields = movementFields[char]
        for key, item in pairs(fields or {}) do
            if char:GetAttribute(key) ~= item.last then item.conflict = true; S.movementStatus = "Yielded to game update" end
        end
        local expiry = char:GetAttribute("PotionEnd_Swiftness")
        local power = fields and fields.PotionPower_Swiftness
        local ending = fields and fields.PotionEnd_Swiftness
        if power and ending and not power.conflict and not ending.conflict
            and type(expiry) == "number" and expiry > workspace:GetServerTimeNow() then
            -- Apply a live slider edit without renewing the original 225s window.
            Core.own(movementFields, char, "PotionPower_Swiftness", CFG.speed, attributesRead, attributesWrite, false)
            S.movementStatus = "Native local +" .. tostring(CFG.speed) .. " (225s; server unverified)"
        end
        if type(expiry) == "number" and expiry <= workspace:GetServerTimeNow() then S.movementStatus = "Window expired; toggle to rebind" end
    end
end
-- Gathering introspects two known signals; climb uses scoped GC discovery below.
-- Verify closure names, source instances and runtime shapes; fail closed on drift.
local function ups(fn)
    local ok, values = pcall(getupvalues, fn)
    return ok and type(values) == "table" and getmetatable(values) == nil and values or {}
end
-- One heap snapshot shared by climb and advanced consumers. Keep only likely
-- candidates, not the executor heap. Three attempts per character/Humanoid at
-- 0/5/20s; an unavailable adapter then stays fail-closed until respawn/reinject.
local HeapDiscovery = (function()
    local owner, humanoid, attempts, nextTry, busy = nil, nil, 0, 0, false
    local candidates = {}
    local api = {}
    -- Complete scoped signal listings survive an incomplete broad heap scan.
    -- W1030:248 HealthChanged -> updateHumanoid; W1034:482-484 JumpRequest
    -- callback up1 -> native Climb table -> Start. Consumers validate captures.
    local function signalFunctions(signal)
        if type(getconnections) ~= "function" or not signal then return {} end
        local ok, connections = pcall(getconnections, signal)
        if not ok or type(connections) ~= "table" or getmetatable(connections) ~= nil then return {} end
        local rows, count = {}, 0
        for _, connection in next, connections do
            count += 1
            if count > 128 then return {} end -- incomplete list cannot disambiguate
            local read, fn = pcall(function() return connection.Function end)
            if read and type(fn) == "function" then rows[#rows + 1] = fn end
        end
        return rows
    end
    local function nativeSignals(char, hum)
        local rows = {}
        local function named(fn, source, name)
            if type(fn) ~= "function" then return false end
            local ok, s, n = pcall(debug.info, fn, "sn")
            return ok and s == source and (not name or n == name)
        end
        local prefix = char:GetFullName()
        for _, fn in ipairs(signalFunctions(hum.HealthChanged)) do
            if named(fn, prefix .. ".CharacterScripts.HumanoidHandler", "updateHumanoid") then
                rows[#rows + 1] = fn
            end
        end
        local source = prefix .. ".CharacterScripts.State Handler.Client.Climb"
        for _, fn in ipairs(signalFunctions(UIS.JumpRequest)) do
            if named(fn, source) then
                local module = ups(fn)[1]
                if type(module) == "table" and getmetatable(module) == nil then
                    local start = rawget(module, "Start")
                    if named(start, source, "Start") and ups(start)[5] == module then
                        rows[#rows + 1] = start
                    end
                end
            end
        end
        -- W1026:690-740 owns this exact closure chain even while grounded.
        -- It survives a heap above the broad-scan ceiling without partial scans.
        local broomSource = prefix .. ".BroomClient"
        if char.GetAttributeChangedSignal then
            for _, fn in ipairs(signalFunctions(char:GetAttributeChangedSignal("Flying"))) do
                local values = ups(fn)
                if named(fn, broomSource, "syncFlyAttribute") and values[2] == char
                    and named(values[17], broomSource, "flyStep") and ups(values[17])[5] == char then
                    rows[#rows + 1] = values[17]
                end
            end
        end
        return rows
    end
    api.signals = nativeSignals
    function api.get(char, hum)
        if owner ~= char or humanoid ~= hum then
            owner, humanoid, attempts, nextTry, busy = char, hum, 0, 0, false
            candidates = {}
        end
        if busy or attempts >= 3 or os.clock() < nextTry then return candidates end
        attempts += 1; nextTry = os.clock() + (attempts == 1 and 5 or 15)
        if type(getgc) ~= "function" or type(getupvalues) ~= "function" then return candidates end
        busy = true
        local scoped = nativeSignals(char, hum)
        local ok, gc = pcall(getgc, true)
        local rows, budget, visits = table.clone(scoped), os.clock(), 0
        local prefix = char:GetFullName()
        local function current()
            return S.alive and G[GKEY] == S and LocalPlayer.Character == char
                and char:FindFirstChildOfClass("Humanoid") == hum and hum.Health > 0
                and S.defenseTransition ~= char
        end
        if ok and type(gc) == "table" and getmetatable(gc) == nil then
            for _, value in next, gc do
                visits += 1
                if visits > 250000 then rows = scoped; break end -- keep only complete signal evidence
                if type(value) == "function" then
                    local passed, source = pcall(debug.info, value, "s")
                    if passed and type(source) == "string" and source:sub(1, #prefix + 1) == prefix .. "." then
                        rows[#rows + 1] = value
                    end
                elseif type(value) == "table" and getmetatable(value) == nil
                    and type(rawget(value, "IsOnCooldown")) == "function" then
                    rows[#rows + 1] = value
                end
                if os.clock() - budget >= 0.003 then
                    task.wait(); budget = os.clock()
                    if not current() then
                        if owner == char and humanoid == hum then busy = false end
                        return {}
                    end
                end
            end
        end
        if owner ~= char or humanoid ~= hum then return {} end
        busy = false
        if not current() then return {} end
        candidates = rows
        return candidates
    end
    function api.note()
        return attempts >= 3 and "discovery paused · respawn/reinject to retry" or "retrying with backoff"
    end
    return api
end)()
-- W/1034: native callers dispatch through this exact returned table. Read-only
-- probes prove Start up5 and the StateManager __index table; never require/call
-- a module during discovery, invoke arbitrary metamethods, or reset u12/u13.
Climb = (function()
    local api = { status = "OFF", nextBind = 0 }
    local owned
    local function named(fn, source, name)
        if type(fn) ~= "function" then return false end
        local okS, s = pcall(debug.info, fn, "s")
        local okN, n = pcall(debug.info, fn, "n")
        return okS and okN and s == source and n == name
    end
    local function stateMethods(sm)
        if type(sm) ~= "table" then return nil end
        local mt = getmetatable(sm)
        if type(mt) ~= "table" or getmetatable(mt) ~= nil
            or rawget(mt, "__newindex") ~= nil or rawget(mt, "__pairs") ~= nil then return nil end
        local index = rawget(mt, "__index")
        if type(index) ~= "table" or getmetatable(index) ~= nil
            or rawget(sm, "CanClimb") ~= nil or rawget(sm, "IsSwimming") ~= nil then return nil end
        local can, swim = rawget(index, "CanClimb"), rawget(index, "IsSwimming")
        if not named(can, "ReplicatedStorage.Modules.StateManager", "CanClimb")
            or not named(swim, "ReplicatedStorage.Modules.StateManager", "IsSwimming") then return nil end
        return can, swim
    end
    local function valid(a, slot)
        if getmetatable(a.module) ~= nil or rawget(a.module, "CanClimb") ~= slot then return false end
        for _, name in ipairs({"Start", "TryClimb", "TryLedgeClimb", "StartClimb", "Stop", "LedgeClimb"}) do
            if rawget(a.module, name) ~= a[name] or not named(a[name], a.source, name) then return false end
        end
        local can, swim = stateMethods(a.sm)
        return can == a.can and swim == a.swim and ups(a.original)[2] == a.sm
            and type(ups(a.original)[1]) == "boolean" and ups(a.Start)[5] == a.module
            and ups(a.TryLedgeClimb)[2] == a.sm and ups(a.StartClimb)[1] == a.sm
            and ups(a.TryClimb)[1] == a.root and ups(a.TryLedgeClimb)[1] == a.hum
            and ups(a.Start)[6] == a.hum
    end
    function api.release()
        if owned then
            -- Do not overwrite a game/other script replacement or a new metatable.
            if getmetatable(owned.module) == nil and rawget(owned.module, "CanClimb") == owned.wrapper then
                rawset(owned.module, "CanClimb", owned.original)
            end
            owned = nil
        end
        api.status = "OFF"
    end
    function api.step()
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not CFG.climb or not char or not hum or hum.Health <= 0 then api.release(); return end
        if owned then
            if char == owned.char and valid(owned, owned.wrapper) then return end
            local sameCharacter = char == owned.char
            api.release()
            if sameCharacter then api.blocked = char; api.status = "Climb adapter changed; toggle OFF to retry"; return end
        end
        if api.blocked == char then return end
        if api.bindChar ~= char then api.bindChar = char; api.nextBind = 0 end
        if os.clock() < api.nextBind then return end
        api.nextBind = os.clock() + 2
        api.status = "Native climb adapter unavailable; " .. HeapDiscovery.note()
        local source = char:GetFullName() .. ".CharacterScripts.State Handler.Client.Climb"
        local root = char:FindFirstChild("HumanoidRootPart")
        if not root then return end
        local gc = HeapDiscovery.signals(char, hum)
        local direct = false
        for _, fn in ipairs(gc) do
            if named(fn, source, "Start") then direct = true; break end
        end
        if not direct then gc = HeapDiscovery.get(char, hum) end
        api.status = "Native climb adapter unavailable; " .. HeapDiscovery.note()
        local found, visits, budget = nil, 0, os.clock()
        for _, fn in next, gc do
            visits += 1
            if visits > 250000 then return end
            if named(fn, source, "Start") then
                local module = ups(fn)[5]
                if type(module) == "table" and getmetatable(module) == nil then
                    local a = {char = char, hum = hum, root = root, module = module, source = source,
                        original = rawget(module, "CanClimb")}
                    for _, name in ipairs({"Start", "TryClimb", "TryLedgeClimb", "StartClimb", "Stop", "LedgeClimb"}) do
                        a[name] = rawget(module, name)
                    end
                    if named(a.original, source, "CanClimb") and a.Start == fn then
                        a.sm = ups(a.original)[2]; a.can, a.swim = stateMethods(a.sm)
                        if a.can and valid(a, a.original) then
                            if found and found.module ~= module then return end -- ambiguous live generation
                            found = a
                        end
                    end
                end
            end
            if os.clock() - budget >= 0.003 then task.wait(); budget = os.clock() end
        end
        -- Discovery can yield: reject departing character/module/setting ownership.
        if not found or not S.alive or G[GKEY] ~= S or not CFG.climb
            or LocalPlayer.Character ~= char or hum.Health <= 0 or not valid(found, found.original) then return end
        local a = found
        a.wrapper = function(self)
            if self ~= a.module or not S.alive or LocalPlayer.Character ~= a.char or a.hum.Health <= 0
                or not valid(a, a.wrapper) then return false end
            if not CFG.climb then return a.original(self) end
            -- Exact native predicate with only the airborne u12 term removed.
            -- Keep original StateManager self, swimming OR, all native caller
            -- geometry, ledge u13, input, and stop timers. Never write an upvalue.
            local passed, result = pcall(function() return a.can(a.sm) or a.swim(a.sm) end)
            return passed and result or false
        end
        rawset(a.module, "CanClimb", a.wrapper)
        owned = a
        api.status = "Native airborne latch bypass · manual input · server motion unverified"
        Log.info("climb native table bound; manual input only; server motion unverified")
    end
    return api
end)()
-- Live Roll bind probe: CreateBindableAction.update up4 -> callback up1 ->
-- Dash instance.State. Never require a game module or patch shared prototypes.
Dash = (function()
    local api = {status = "OFF", nextBind = 0}
    local owned
    local names = {"CanDash", "IsAlive", "HasAnyState", "IsFlying", "IsIncapacitated",
        "IsUsingSkill", "IsDodging", "IsParrying"}
    local function named(fn, source, name)
        if type(fn) ~= "function" then return false end
        local okS, s = pcall(debug.info, fn, "s")
        local okN, n = pcall(debug.info, fn, "n")
        return okS and okN and s == source and (not name or n == name)
    end
    local function indexOf(t)
        if type(t) ~= "table" then return nil end
        local mt = getmetatable(t)
        if type(mt) ~= "table" or getmetatable(mt) ~= nil
            or rawget(mt, "__newindex") or rawget(mt, "__pairs") then return nil end
        local index = rawget(mt, "__index")
        return type(index) == "table" and getmetatable(index) == nil and index or nil
    end
    local function valid(a, slot)
        if LocalPlayer.Character ~= a.char or rawget(a.instance, "Character") ~= a.char
            or a.char:FindFirstChildOfClass("Humanoid") ~= a.hum or rawget(a.instance, "Humanoid") ~= a.hum
            or not a.root or not a.root:IsA("BasePart")
            or a.char:FindFirstChild("HumanoidRootPart") ~= a.root or rawget(a.instance, "Root") ~= a.root
            or rawget(a.instance, "State") ~= a.sm or rawget(a.sm, "Model") ~= a.char
            or indexOf(a.instance) ~= a.dashIndex or indexOf(a.sm) ~= a.stateIndex
            or rawget(a.dashIndex, "RequestDash") ~= a.request
            or ups(a.update)[4] ~= a.callback or ups(a.callback)[1] ~= a.instance
            or rawget(a.sm, "CanDash") ~= slot then return false end
        for _, name in ipairs(names) do
            if rawget(a.stateIndex, name) ~= a.methods[name]
                or (name ~= "CanDash" and rawget(a.sm, name) ~= nil) then return false end
        end
        return true
    end
    function api.release()
        if owned then
            if rawget(owned.sm, "CanDash") == owned.wrapper then rawset(owned.sm, "CanDash", nil) end
            owned = nil
        end
        api.status = "OFF"
    end
    function api.step()
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not CFG.dash or not char or not hum or hum.Health <= 0 or S.defenseTransition then api.release(); return end
        if owned then
            if valid(owned, owned.wrapper) then return end
            local same = char == owned.char
            api.release()
            if same then api.blocked = char; api.status = "Dash adapter changed; toggle OFF to retry"; return end
        end
        if api.blocked == char or os.clock() < api.nextBind then return end
        api.nextBind = os.clock() + 2
        api.status = "Native dash adapter unavailable; retrying (no patch)"
        if type(getconnections) ~= "function" or type(getupvalues) ~= "function" then return end
        local binds = LocalPlayer:FindFirstChild("Binds")
        local roll = binds and binds:FindFirstChild("Roll")
        if not roll then return end
        local ok, connections = pcall(getconnections, roll:GetPropertyChangedSignal("Value"))
        if not ok or type(connections) ~= "table" then return end
        local found
        local source = char:GetFullName() .. ".CharacterScripts.State Handler.Client.Dash"
        for i, connection in ipairs(connections) do
            if i > 64 then return end
            local update = connection.Function
            if named(update, "ReplicatedStorage.Modules.CreateBindableAction", "update") then
                local callback = ups(update)[4]
                if named(callback, source) then
                    local instance = ups(callback)[1]
                    local di = indexOf(instance)
                    local sm = di and rawget(instance, "State")
                    local si = indexOf(sm)
                    local request = di and rawget(di, "RequestDash")
                    if si and named(request, source, "RequestDash") then
                        local a = {char = char, hum = hum, root = char:FindFirstChild("HumanoidRootPart"), instance = instance, sm = sm,
                            dashIndex = di, stateIndex = si, request = request, update = update,
                            callback = callback, methods = {}}
                        local matches = true
                        for _, name in ipairs(names) do
                            a.methods[name] = rawget(si, name)
                            if not named(a.methods[name], "ReplicatedStorage.Modules.StateManager", name) then matches = false end
                        end
                        if matches and valid(a, nil) then
                            if found and found.sm ~= sm then return end
                            found = a
                        end
                    end
                end
            end
        end
        if not found or not S.alive or G[GKEY] ~= S or not CFG.dash then return end
        local a = found
        a.wrapper = function(self)
            if self ~= a.sm then return a.methods.CanDash(self) end
            if not S.alive or not CFG.dash then return a.methods.CanDash(self) end
            if S.defenseTransition or a.hum.Health <= 0 or not valid(a, a.wrapper) then return false end
            local m = a.methods
            -- W/0840:591-599: DashCooldown and replicated Dodging are two
            -- separate gates. IsDodging reads only the server-fed state flag
            -- (480-483), not local dash lifetime. W/1036 StopDash clears these
            -- three handles; ground movement ends at 0.3s. Use those actual
            -- handles for the active-dash lock, with no added timer or wait
            -- for Dodging to replicate away. Keep every other native lock.
            -- Never clear states, start/stop movement or dispatch a packet here.
            if not m.IsAlive(self) then return nil end
            if m.HasAnyState(self, "Parried", "Occupied", "Stunned", "ParriedAttack", "Attacking")
                or m.IsFlying(self) or m.IsIncapacitated(self) or m.IsUsingSkill(self) or m.IsParrying(self) then
                api.status = "Native combat/flight lock · local dash cooldown bypass armed"
                return nil
            end
            if rawget(a.instance, "ActiveVelocity") ~= nil or rawget(a.instance, "DashConnection") ~= nil
                or rawget(a.instance, "ActiveAnimation") ~= nil then
                api.status = "Native dash active · next manual dash after native StopDash"
                return nil
            end
            api.status = "Native dash ready · no local post-dash wait · server cooldown/i-frames unverified"
            return true
        end
        rawset(a.sm, "CanDash", a.wrapper)
        owned = a
        api.status = "Native dash ready · no local post-dash wait · server cooldown/i-frames unverified"
        Log.info("dash instance bound; DashCooldown/stale Dodging wait bypassed; native active motion and combat locks retained")
    end
    return api
end)()
-- W1037/1030/1026: exact source + current character captures disambiguate
-- stale generations. GC inspection never requires or invokes a game module.
Advanced = (function()
    local api = {noFall = "OFF", chainSlide = "OFF", combatMove = "OFF", broomBoost = "OFF"}
    local fallFields, fallChar, fallScript = {}, nil, nil
    local slide, combat, flight
    local blocked, scanned, scanMask = {}, nil, nil
    local penalties = {Swinging = {-3, true}, Stunned = {-10, true}, Slowed = {-12, true},
        Parried = {-5, true}, Airborne = {-6, true}, SoftStun = {-10, false}}
    local function plain(t) return type(t) == "table" and getmetatable(t) == nil end
    local function finite(n) return type(n) == "number" and n == n and math.abs(n) < math.huge end
    local function named(fn, source, name)
        if type(fn) ~= "function" then return false end
        local ok, s, n = pcall(debug.info, fn, "sn")
        return ok and s == source and n == name
    end
    local function current(char, hum)
        return S.alive and G[GKEY] == S and LocalPlayer.Character == char and hum.Health > 0
            and char:FindFirstChildOfClass("Humanoid") == hum and S.defenseTransition ~= char
    end
    local function stateModel(sm, char)
        if type(sm) ~= "table" or rawget(sm, "Model") ~= char then return false end
        local mt = getmetatable(sm)
        return plain(mt) and plain(rawget(mt, "__index"))
            and rawget(mt, "__newindex") == nil and rawget(mt, "__pairs") == nil
    end
    -- Native refresh runs on its own thread, never the shell/lease worker.
    -- An old queued refresh cannot act on a newer inject or different character.
    local function refresh(a)
        task.spawn(function()
            if (G[GKEY] == S or G[GKEY] == nil) and LocalPlayer.Character == a.char and a.hum.Health > 0
                and a.char:FindFirstChildOfClass("Humanoid") == a.hum
                and named(a.fn, a.source, "updateHumanoid") and ups(a.fn)[1] == a.hum
                and ups(a.fn)[8] == a.char and ups(a.fn)[6] == a.entries
                and (not a.sm or ups(a.fn)[3] == a.sm or ups(a.fn)[3] == a.view) then
                guard("combat movement refresh", a.fn)
            end
        end)
    end
    local function slideValid(a, slot)
        if not plain(a.module) or rawget(a.module, "IsOnCooldown") ~= slot
            or not named(a.original, a.source, "IsOnCooldown") or not finite(ups(a.original)[1]) then return false end
        for name, fn in pairs(a.methods) do
            if rawget(a.module, name) ~= fn or not named(fn, a.source, name) then return false end
        end
        local start, can, stop, sliding = ups(a.methods.TryStart), ups(a.methods.CanStart), ups(a.methods.Stop), ups(a.methods.IsSliding)
        return a.char:FindFirstChild("HumanoidRootPart") == a.root and a.root:IsA("BasePart")
            and a.char:FindFirstChildOfClass("Humanoid") == a.hum
            and start[1] == a.root and start[8] == a.hum and start[11] == a.sm and can[1] == a.sm
            and stop[1] == a.sm and stop[5] == a.hum and sliding[1] == a.sm and stateModel(a.sm, a.char)
    end
    -- Only HumanoidHandler's own StateManager capture is replaced. Other
    -- consumers (attack eligibility, dash, remote reports) keep the real state.
    local function combatViewValid(a)
        if not a.view then return false end
        local capture = ups(a.fn)[3]
        if capture ~= a.view or not stateModel(a.sm, a.char) then return false end
        local methods = rawget(getmetatable(a.sm), "__index")
        for name, fn in pairs(a.stateMethods) do
            if rawget(methods, name) ~= fn or (rawget(a.sm, name) ~= nil and rawget(a.sm, name) ~= fn)
                or not named(fn, "ReplicatedStorage.Modules.StateManager", name) then return false end
        end
        return true
    end
    local function installCombatView(a)
        if type(setupvalue) ~= "function" then return false end
        local sm = ups(a.fn)[3]
        if not stateModel(sm, a.char) then return false end
        local methods = rawget(getmetatable(sm), "__index")
        local originals, viewMethods = {}, {}
        for _, name in ipairs({"HasState", "IsSprinting", "IsBlocking", "IsFlying", "IsSwimming",
            "IsCrouching", "IsIncapacitated", "IsUsingSkill", "HasAnyState"}) do
            local fn = rawget(methods, name)
            if not named(fn, "ReplicatedStorage.Modules.StateManager", name)
                or (rawget(sm, name) ~= nil and rawget(sm, name) ~= fn) then return false end
            originals[name] = fn
            viewMethods[name] = function(_, ...) return fn(sm, ...) end
        end
        a.sm, a.stateMethods = sm, originals
        local function action()
            return originals.IsUsingSkill(sm) or originals.IsBlocking(sm) or originals.HasAnyState(sm,
                "Attacking", "Swinging", "Using Skill", "Uppercutting", "CombatDebounce")
        end
        local function active()
            return CFG.combatMove and combat == a and current(a.char, a.hum)
                and combatViewValid(a) and not originals.IsIncapacitated(sm)
        end
        viewMethods.HasState = function(_, name, ...)
            if active() and action() and (name == "OneSpeed" or name == "CantMove" or name == "Locked") then
                return false
            end
            return originals.HasState(sm, name, ...)
        end
        -- Blocking's 8-speed overwrite is outside the penalty table. Suppress
        -- only its movement view, never the real guard/combat state.
        viewMethods.IsBlocking = function()
            if active() then return false end
            return originals.IsBlocking(sm)
        end
        a.sprint = originals.IsSprinting(sm)
        viewMethods.IsSprinting = function()
            local native = originals.IsSprinting(sm)
            if active() and action() then return a.sprint or native end
            a.sprint = native
            return native
        end
        a.view = setmetatable({Model = a.char}, {__index = viewMethods})
        local ok = pcall(setupvalue, a.fn, 3, a.view)
        if not ok or not combatViewValid(a) then
            if ups(a.fn)[3] == a.view then pcall(setupvalue, a.fn, 3, sm) end
            a.view = nil; return false
        end
        return true
    end
    local function combatValid(a, owned)
        local captures = ups(a.fn)
        if a.char:FindFirstChildOfClass("Humanoid") ~= a.hum
            or not named(a.fn, a.source, "updateHumanoid") or captures[1] ~= a.hum
            or captures[8] ~= a.char or captures[6] ~= a.entries or not plain(a.entries)
            or not stateModel(captures[3], a.char) then return false end
        if owned and ((a.view and not combatViewValid(a)) or (not a.view and captures[3] ~= a.sm)) then return false end
        for name, expected in pairs(penalties) do
            local entry = rawget(a.entries, name)
            if not plain(entry) or entry ~= a.refs[name] then return false end
            if owned then
                if rawget(entry, "Speed") ~= nil or rawget(entry, "jumpDisabled") ~= false then return false end
            elseif rawget(entry, "Speed") ~= expected[1] or rawget(entry, "jumpDisabled") ~= expected[2] then
                return false
            end
        end
        -- Hard immobilizers are deliberately not part of this feature.
        for _, name in ipairs({"Frozen", "Knocked", "Locked", "CantMove", "BlockBroken"}) do
            local entry = rawget(a.entries, name)
            if not plain(entry) or rawget(entry, "Speed") ~= 0 or rawget(entry, "jumpDisabled") ~= true then return false end
        end
        return true
    end
    local function flightValid(a)
        local f, m = ups(a.fn), ups(a.max)
        return a.char:FindFirstChild("HumanoidRootPart") == a.root and a.root:IsA("BasePart")
            and a.char:FindFirstChildOfClass("Humanoid") == a.hum
            and named(a.fn, a.source, "flyStep") and named(a.max, a.source, "updateMaxFlySpeed")
            and f[4] == a.root and f[5] == a.char and m[6] == a.char and f[1] == m[2]
            and stateModel(f[1], a.char) and f[19] == a.velocity and a.velocity.Parent ~= nil
            and a.velocity:IsDescendantOf(a.root) and finite(f[23]) and f[23] == m[4]
    end
    local function releaseFall()
        Core.restore(fallFields, attributesRead, attributesWrite)
        fallChar, fallScript = nil, nil; api.noFall = "OFF"
    end
    local function releaseSlide()
        if slide and plain(slide.module) and rawget(slide.module, "IsOnCooldown") == slide.wrapper then
            rawset(slide.module, "IsOnCooldown", slide.original)
        end
        slide = nil; api.chainSlide = "OFF"
    end
    local function releaseCombat()
        if combat then
            local a = combat; combat = nil
            if a.view and ups(a.fn)[3] == a.view then pcall(setupvalue, a.fn, 3, a.sm) end
            Core.restore(a.fields, function(o, k) return rawget(o, k) end, rawset)
            refresh(a)
        end
        api.combatMove = "OFF"
    end
    local function releaseFlight()
        if flight then
            local a = flight; flight = nil
            -- A native profession update/foreign writer owns any changed value.
            if flightValid(a) and ups(a.fn)[23] == a.last then
                local ok, err = pcall(setupvalue, a.fn, 23, a.original)
                if not ok then Log.err("broom bonus restore", tostring(err)) end
            end
        end
        api.broomBoost = "OFF"
    end
    function api.release()
        releaseFall(); releaseSlide(); releaseCombat(); releaseFlight()
    end
    function api.apply()
        scanned = nil
        if not CFG.noFall then releaseFall() end
        if not CFG.chainSlide then releaseSlide(); blocked.chainSlide = nil end
        if not CFG.combatMove then releaseCombat(); blocked.combatMove = nil end
        if not CFG.broomBoost then releaseFlight(); blocked.broomBoost = nil end
    end
    local function fallStep(char)
        if fallChar and fallChar ~= char then releaseFall() end
        local script = char:FindFirstChild("FallDamage")
        if not script or not script:IsA("LocalScript") or script.Disabled or (fallScript and script ~= fallScript) then
            releaseFall(); api.noFall = "Native FallDamage script unavailable · no change"; return
        end
        fallChar, fallScript = char, script
        -- Native landing resets this flag. Renew on the lease worker, never
        -- from an Instance signal callback; retain the latest game baseline.
        Core.own(fallFields, char, "DisableFallDamage", true, attributesRead, attributesWrite, true)
        api.noFall = "Native fall report suppressed · server damage unverified"
    end
    local function inspectSlide(module, char, hum, root, source)
        if not plain(module) or not named(rawget(module, "IsOnCooldown"), source, "IsOnCooldown") then return nil end
        local a = {module = module, char = char, hum = hum, root = root, source = source,
            original = rawget(module, "IsOnCooldown"), methods = {}}
        for _, name in ipairs({"CanStart", "TryStart", "Stop", "IsSliding"}) do
            a.methods[name] = rawget(module, name)
            if not named(a.methods[name], source, name) then return nil end
        end
        a.sm = ups(a.methods.CanStart)[1]
        return slideValid(a, a.original) and a or nil
    end
    local function discover(char, hum, root)
        local wantSlide = CFG.chainSlide and not slide and blocked.chainSlide ~= char
        local wantCombat = CFG.combatMove and not combat and blocked.combatMove ~= char
        local wantFlight = CFG.broomBoost and not flight and blocked.broomBoost ~= char
        if not (wantSlide or wantCombat or wantFlight) then return end
        local gc = HeapDiscovery.get(char, hum)
        local note = HeapDiscovery.note()
        if wantSlide then api.chainSlide = "Native slide adapter unavailable · " .. note end
        if wantCombat then api.combatMove = "Native penalty adapter unavailable · " .. note end
        if wantFlight then api.broomBoost = "Native flight adapter unavailable · " .. note end
        local mask = tostring(wantSlide) .. tostring(wantCombat) .. tostring(wantFlight)
        if scanned == gc and scanMask == mask then return end
        scanned, scanMask = gc, mask
        local prefix = char:GetFullName()
        local slideSource = prefix .. ".CharacterScripts.State Handler.Client.Slide"
        local combatSource = prefix .. ".CharacterScripts.HumanoidHandler"
        local flightSource = prefix .. ".BroomClient"
        local found, ambiguous, fly, maxFly = {}, {}, {}, {}
        local function accept(key, a, identity)
            if found[key] and found[key].identity ~= identity then ambiguous[key] = true end
            a.identity = identity; found[key] = a
        end
        local budget, visits = os.clock(), 0
        for _, value in next, gc do
            visits += 1
            if visits > 250000 then return end
            if wantSlide and plain(value) then
                local a = inspectSlide(value, char, hum, root, slideSource)
                if a then accept("chainSlide", a, value) end
            elseif type(value) == "function" then
                if wantCombat and named(value, combatSource, "updateHumanoid") then
                    local u = ups(value)
                    local a = {fn = value, source = combatSource, char = char, hum = hum, sm = u[3], entries = u[6], refs = {}, fields = {}}
                    if plain(a.entries) then
                        for name in pairs(penalties) do a.refs[name] = rawget(a.entries, name) end
                        if combatValid(a, false) then accept("combatMove", a, value) end
                    end
                elseif wantFlight and named(value, flightSource, "flyStep") and ups(value)[5] == char then
                    fly[value] = true
                elseif wantFlight and named(value, flightSource, "updateMaxFlySpeed") and ups(value)[6] == char then
                    maxFly[value] = true
                end
            end
            if os.clock() - budget >= 0.003 then
                task.wait(); budget = os.clock()
                if not current(char, hum) then return end
            end
        end
        if wantFlight and type(setupvalue) == "function" then
            for fn in pairs(fly) do for max in pairs(maxFly) do
                local u = ups(fn)
                local velocity = u[19]
                if typeof(velocity) == "Instance" and velocity:IsA("LinearVelocity") then
                    local a = {fn = fn, max = max, source = flightSource, char = char, hum = hum,
                        root = root, velocity = velocity, original = u[23], last = u[23]}
                    if flightValid(a) then
                        if found.broomBoost and (found.broomBoost.fn ~= fn or found.broomBoost.max ~= max) then ambiguous.broomBoost = true end
                        found.broomBoost = a
                    end
                end
            end end
        end
        -- Every consumer can yield above. Recheck both generation and settings
        -- before *any* mutation; a departing worker never installs a new lease.
        if not current(char, hum) then return end
        local a = found.chainSlide
        if a and not ambiguous.chainSlide and CFG.chainSlide and not slide and slideValid(a, a.original) then
            local owner = a
            a.wrapper = function(self)
                if self == owner.module and slide == owner and CFG.chainSlide and current(owner.char, owner.hum)
                    and slideValid(owner, owner.wrapper) then return false end
                return owner.original(self)
            end
            rawset(a.module, "IsOnCooldown", a.wrapper); slide = a
        end
        a = found.combatMove
        if a and not ambiguous.combatMove and CFG.combatMove and not combat and combatValid(a, false) then
            for _, entry in pairs(a.refs) do
                -- Speed=0 is a hard stop in native code. Remove the penalty
                -- with nil, never zero, and leave the hard-lock entries alone.
                Core.own(a.fields, entry, "Speed", nil, rawget, rawset, false)
                Core.own(a.fields, entry, "jumpDisabled", false, rawget, rawset, false)
            end
            combat = a
            a.fullMovement = installCombatView(a)
            refresh(a)
        end
        a = found.broomBoost
        if a and not ambiguous.broomBoost and CFG.broomBoost and not flight and flightValid(a) then flight = a end
    end
    function api.step()
        if not S.alive or G[GKEY] ~= S then return end
        api.apply()
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not char or not hum or not root or not current(char, hum) then api.release(); return end
        if CFG.noFall then fallStep(char) end
        if slide and (slide.char ~= char or not slideValid(slide, slide.wrapper)) then
            local same = slide.char == char; releaseSlide()
            if same then blocked.chainSlide = char end
        end
        if combat and (combat.char ~= char or not combatValid(combat, true)) then
            local same = combat.char == char; releaseCombat()
            if same then blocked.combatMove = char end
        end
        if flight and (flight.char ~= char or not flightValid(flight) or ups(flight.fn)[23] ~= flight.last) then
            local same = flight.char == char; releaseFlight()
            if same then blocked.broomBoost = char end
        end
        discover(char, hum, root)
        if not current(char, hum) then return end
        if slide then api.chainSlide = "Native slide cooldown bypass · manual slide · server motion unverified" end
        if combat then
            api.combatMove = combat.fullMovement
                and "M1/skill/guard slowdown removed · prior sprint mode retained · incapacitation stays native"
                or "Partial: six soft penalties removed · native action-speed adapter unavailable"
        end
        if flight and CFG.broomBoost then
            local a = flight
            local desired = a.original + CFG.broomBonus / 100
            if desired ~= a.last then
                local ok = pcall(setupvalue, a.fn, 23, desired)
                if not ok or not flightValid(a) or ups(a.max)[4] ~= desired then
                    -- If cells are not shared in this runtime, roll back only
                    -- our write and do not guess a second patch point.
                    if ups(a.fn)[23] == desired then pcall(setupvalue, a.fn, 23, a.last) end
                    releaseFlight(); blocked.broomBoost = char
                else a.last = desired end
            end
            if flight then api.broomBoost = ("Native base flight bonus +%g%% · server motion unverified"):format(CFG.broomBonus) end
        end
        for key, owner in pairs(blocked) do
            if owner == char and CFG[key] then api[key] = "Native adapter changed · toggle OFF to retry" end
        end
    end
    return api
end)()
local function findNative(signal, target, remote)
    if type(getconnections) ~= "function" or type(getupvalues) ~= "function" then return nil end
    local ok, connections = pcall(getconnections, signal)
    if not ok then return nil end
    local seen, visits = {}, 0
    local function visit(fn, depth)
        if type(fn) ~= "function" or seen[fn] or depth > 2 or visits >= 64 then return nil end
        seen[fn] = true; visits += 1
        local infoOk, name = pcall(debug.info, fn, "n")
        local values = ups(fn)
        if infoOk and name == target then
            for _, value in next, values do if value == remote then return fn end end
        end
        for _, value in next, values do
            if type(value) == "function" then local found = visit(value, depth + 1); if found then return found end end
        end
        return nil
    end
    for _, connection in ipairs(connections) do
        local fn = connection.Function
        if type(fn) == "function" then
            if target == "listener" then
                local values = ups(fn)
                for _, value in next, values do
                    if type(value) == "function" then
                        local named, name = pcall(debug.info, value, "n")
                        if named and name == "open" then
                            for _, nested in next, ups(value) do
                                if nested == remote then return fn end
                                -- Timing open captures onPress, which captures its remote.
                                if type(nested) == "function" then
                                    local namedPress, pressName = pcall(debug.info, nested, "n")
                                    if namedPress and pressName == "onPress" then
                                        for _, capture in next, ups(nested) do if capture == remote then return fn end end
                                    end
                                end
                            end
                        end
                    end
                end
            else local found = visit(fn, 0); if found then return found end end
        end
    end
    return nil
end
local function bindMaterialNatives()
    local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
    local timing = remotes and remotes:FindFirstChild("HarvestTiming")
    local rings = remotes and remotes:FindFirstChild("HarvestRings")
    nativeTiming, nativePress, nativeRings = nil, nil, nil
    if timing then
        nativeTiming = findNative(timing.OnClientEvent, "listener", timing)
        nativePress = findNative(timing.OnClientEvent, "onPress", timing)
    end
    if rings then nativeRings = findNative(rings.OnClientEvent, "listener", rings) end
end
local function nativeSession(fn)
    if type(fn) ~= "function" then return nil end
    local session = ups(fn)[2]
    return type(session) == "table" and getmetatable(session) == nil and not session.closed and session or nil
end
-- Native MouseMovement sets useMouse=true before its render callback; merely
-- rewriting it in PreSimulation loses that race. Lease only the two verified
-- active-session aim listeners, not global mouse input or unrelated UI/cancel.
HarvestInput = (function()
    local api, lease, retry = {}, nil, 0
    function api.release()
        local old = lease; lease = nil; retry = 0
        if not old then return end
        for _, item in ipairs(old.inputs) do
            pcall(function()
                if item.connection.Function == item.fn and item.connection.Enabled == false then
                    item.connection:Enable()
                end
            end)
        end
    end
    function api.step(session)
        if lease and lease.session == session then return true end
        if lease then api.release() end
        if not session or os.clock() < retry or type(getconnections) ~= "function" then return false end
        retry = os.clock() + 0.5
        local inputs, matched = {}, 0
        for _, signal in ipairs({UIS.InputBegan, UIS.InputChanged}) do
            local ok, list = pcall(getconnections, signal)
            local found = false
            if ok and type(list) == "table" then
                for i, connection in ipairs(list) do
                    if i > 256 then break end
                    local fn = connection.Function
                    if type(fn) == "function" and ups(fn)[1] == session then
                        found = true
                        if connection.Enabled == true then
                            local disabled = pcall(function() connection:Disable() end)
                            if disabled and connection.Enabled == false then
                                inputs[#inputs + 1] = {connection = connection, fn = fn}
                            else found = false end
                        elseif connection.Enabled ~= false then found = false end
                    end
                end
            end
            if found then matched += 1 end
        end
        lease = {session = session, inputs = inputs}
        if matched ~= 2 then api.release(); retry = os.clock() + 0.5; return false end
        return true
    end
    return api
end)()
local Challenge = (function()
    local api = {}
    local nextCheck, page, adapters, pending = 0, nil, {}, false
    local function named(fn, name)
        if type(fn) ~= "function" then return false end
        local ok, value = pcall(debug.info, fn, "n")
        return ok and value == name
    end
    local function discover(currentPage)
        adapters = {}; page = currentPage
        if not page or type(getconnections) ~= "function" then return end
        local count = 0
        for _, button in ipairs(page:GetDescendants()) do
            if button:IsA("GuiButton") and button.Name == "Start" then
                count += 1
                if count > 256 then adapters = {}; return end
                local ok, connections = pcall(getconnections, button.Activated)
                if ok then for _, connection in ipairs(connections) do
                    local captures = ups(connection.Function)
                    local start, profession = captures[1], captures[2]
                    if (profession == "Mining" or profession == "Harvesting") and named(start, "startChallenge") then
                        local values = ups(start)
                        if named(values[2], "getChallengeStatus") and named(values[3], "getNextChallenge")
                            and values[4] == game:GetService("ReplicatedStorage") then
                            local old = adapters[profession]
                            if old and old.start ~= start then adapters = {}; return end
                            adapters[profession] = {start = start, status = values[2], next = values[3], button = button}
                        end
                    end
                end end
            end
        end
    end
    function api.busy()
        if pending then return true end
        for _, a in pairs(adapters) do if ups(a.start)[1] ~= nil then return true end end
        return false
    end
    function api.step()
        if pending or os.clock() < nextCheck then return end
        nextCheck = os.clock() + 2
        if not (CFG.autoMine or CFG.autoHarvest) or not materialAlive() or UIS:GetFocusedTextBox() then return end
        -- Never overlap a node/minigame, nor start a trial without its assistant.
        if nativeSession(nativeTiming) or nativeSession(nativeRings) then return end
        local char = LocalPlayer.Character
        if LocalPlayer:GetAttribute("InCombat") or char:GetAttribute("Flying")
            or char:GetAttribute("State_Stunned") or char:GetAttribute("State_Knocked") then return end
        local gui = LocalPlayer:FindFirstChild("PlayerGui")
        local current = gui
        for _, name in ipairs({"Gameplay", "Main", "Menu", "Pages", "Professions"}) do
            current = current and current:FindFirstChild(name)
        end
        if current ~= page or not next(adapters) then discover(current) end
        for _, profession in ipairs({"Mining", "Harvesting"}) do
            local enabled = profession == "Mining" and CFG.autoMine or profession == "Harvesting" and CFG.autoHarvest
            local a = adapters[profession]
            local readyAdapter = profession == "Mining" and nativePress or profession == "Harvesting" and nativeRings
            if enabled and readyAdapter and a and a.button:IsDescendantOf(current) then
                local definition = a.next(profession)
                local status = a.status(profession)
                if type(definition) == "table" and definition.Type == profession
                    and type(status) == "table" and status.Enabled == true then
                    -- Native start rechecks readiness and owns busy/result cleanup.
                    releaseHold()
                    pending = true
                    -- InvokeServer may yield. Keep restores and the Hub worker
                    -- alive while the native controller waits for its response.
                    task.spawn(function()
                        local stillEnabled = profession == "Mining" and CFG.autoMine or profession == "Harvesting" and CFG.autoHarvest
                        if S.alive and stillEnabled and materialAlive() and LocalPlayer.Character == char
                            and a.button:IsDescendantOf(current) and not UIS:GetFocusedTextBox()
                            and not nativeSession(nativeTiming) and not nativeSession(nativeRings)
                            and not LocalPlayer:GetAttribute("InCombat") and not char:GetAttribute("Flying")
                            and not char:GetAttribute("State_Stunned") and not char:GetAttribute("State_Knocked") then
                            local ok, err = pcall(a.start, profession)
                            if ok then Log.info("profession native challenge requested: " .. profession)
                            else Log.err("profession challenge", err) end
                        end
                        pending = false
                    end)
                    return
                end
            end
        end
    end
    return api
end)()
local QuestAssist = (function()
    local api = {status = "Open the hymn beside its book, then click Solve", mapStatus = "Map reveal OFF"}
    local fields, map, refresh, filtersChanged = {}, nil, nil, nil
    local requested, nextSolve, awaiting = false, 0, nil
    local order = {"Earth", "Wind", "Light", "Flame", "Shadow", "Water"}
    local function plain(value) return type(value) == "table" and getmetatable(value) == nil end
    local function redraw(tiles, discovery, filters)
        -- Game calls can remove the caller's CoreGui capability (§9 executor
        -- quirks). Never contaminate the UI worker or Hub's unload/remount thread.
        task.spawn(function()
            if G[GKEY] ~= S and G[GKEY] ~= nil then return end
            if tiles then pcall(tiles, true) end
            if discovery then pcall(discovery) end
            if filters then pcall(filters) end
        end)
    end
    function api.release()
        local changed = next(fields) ~= nil
        Core.restore(fields, rawget, rawset)
        if changed then redraw(refresh, nil, filtersChanged) end
        map, refresh, filtersChanged = nil, nil, nil
        api.mapStatus = "Map reveal OFF"
    end
    function api.request() requested = true end
    function api.cancel() requested = false; awaiting = nil; api.release() end
    local function solve()
        if not requested then return end
        requested = false
        if os.clock() < nextSolve then return end
        nextSolve = os.clock() + 2
        local gui = LocalPlayer:FindFirstChild("PlayerGui")
        local ui = gui and gui:FindFirstChild("HymnUI")
        local owner = ui and ui:FindFirstChild("Object")
        owner = owner and owner.Value
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local root, book = char and rootOf(char), owner and rootOf(owner)
        if not ui or not ui.Enabled or not hum or hum.Health <= 0 or not root or not book
            or (root.Position - book.Position).Magnitude > 15 or UIS:GetFocusedTextBox() then
            api.status = "Open the hymn within 15 studs of its book first"; return
        end
        local objects = owner.Parent
        local completed = objects and objects:FindFirstChild("Completed")
        if completed and completed.Value then api.status = "Church puzzle already completed"; return end
        local box = ui:FindFirstChild("ChatBox")
        local code = box and box:FindFirstChild("Code")
        local rs = game:GetService("ReplicatedStorage")
        local remotes = rs:FindFirstChild("Remotes")
        local remote = remotes and remotes:FindFirstChild("ChurchRemote")
        local slots, buttons, native = {}, {}, nil
        if code and remote then
            for i = 1, 6 do
                local slot = code:FindFirstChild(tostring(i))
                local button = slot and slot:FindFirstChildWhichIsA("ImageButton")
                if not button or buttons[button.Name] then api.status = "Hymn layout changed; no request sent"; return end
                slots[i] = slot; buttons[button.Name] = button
                native = native or findNative(button.InputBegan, "checkCode", remote)
            end
        end
        if not native or ups(native)[1] ~= code then api.status = "Native hymn adapter unavailable; no request sent"; return end
        for _, name in ipairs(order) do
            if not buttons[name] then api.status = "Unknown hymn symbols; no request sent"; return end
        end
        -- The six poem lines name these elements in order. Reparenting uses the
        -- game's own Parent listener for centering; then one normal Check call.
        for i, name in ipairs(order) do buttons[name].Parent = slots[i] end
        native()
        awaiting = completed
        api.status = "Hymn submitted: Earth > Wind > Light > Flame > Shadow > Water; awaiting server"
        Log.info("hymn native Check submitted once; awaiting Completed")
    end
    local function mapStep()
        if not CFG.revealMap then if map then api.release() end; return end
        if not map then
            local modules = game:GetService("ReplicatedStorage"):FindFirstChild("Modules")
            local source = modules and modules:FindFirstChild("MapService")
            if not source then api.mapStatus = "Native map unavailable"; return end
            map = require(source)
        end
        local init, marker = ups(map.init), ups(map.addMarker)
        local colors, fog, filters, callbacks, markers = init[4], init[10], init[16], init[54], marker[7]
        if not plain(colors) or colors.Discovered == nil or colors.Undiscovered == nil
            or not plain(fog) or type(fog.Transparency) ~= "number" or not plain(filters)
            or not plain(callbacks) or type(callbacks.discoveryChanged) ~= "function" or not plain(markers) then
            api.mapStatus = "Native map layout changed; reveal unavailable"; return
        end
        local draw = ups(callbacks.discoveryChanged)[1]
        local ok, name = pcall(debug.info, draw, "n")
        if not ok or name ~= "refreshTiles" then api.mapStatus = "Map renderer unavailable"; return end
        refresh = draw; filtersChanged = callbacks.filtersChanged
        local changed = colors.Undiscovered ~= colors.Discovered or fog.Transparency ~= 1 or filters.QuestGivers ~= true
        Core.own(fields, colors, "Undiscovered", colors.Discovered, rawget, rawset, true)
        Core.own(fields, fog, "Transparency", 1, rawget, rawset, true)
        Core.own(fields, filters, "QuestGivers", true, rawget, rawset, true)
        local count, visited = 0, 0
        for _, record in next, markers do
            visited += 1; if visited > 2048 then break end
            if plain(record) and record.category == "QuestGivers" and record.gui then
                changed = changed or not record.alwaysVisible
                Core.own(fields, record, "alwaysVisible", true, rawget, rawset, true)
                count += 1
            end
        end
        if changed then redraw(refresh, callbacks.discoveryChanged, filtersChanged) end
        api.mapStatus = ("Full map display · %d known quest givers · real discovery unchanged"):format(count)
    end
    function api.step()
        solve()
        if awaiting and awaiting.Parent and awaiting.Value then
            api.status = "Church puzzle completed (server confirmation)"
            Log.info("hymn Completed observed true"); awaiting = nil
        end
        mapStep()
    end
    return api
end)()
local function broomStep()
    broomStatus = "OFF"
    local char = LocalPlayer.Character
    if broomBoundCharacter ~= char then
        releaseBroom(); broomAction = nil; broomBoundCharacter = char; nextBroomBind = 0
    end
    if char and not broomAction and os.clock() >= nextBroomBind then
        nextBroomBind = os.clock() + 2
        local binds = LocalPlayer:FindFirstChild("Binds")
        local bind = binds and binds:FindFirstChild("Broom")
        local remote = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
        remote = remote and remote:FindFirstChild("BroomRemote")
        if bind and remote then broomAction = findNative(bind:GetPropertyChangedSignal("Value"), "broomAction", remote) end
    end
    if broomObject and broomObject.Parent ~= char then broomObject:Destroy(); broomObject = nil end
    if CFG.broomSpeed and char then
        if char:FindFirstChild("Tailwind") == nil and not broomObject then
            broomObject = Instance.new("Folder"); broomObject.Name = "Tailwind"; broomObject.Parent = char
        end
        broomStatus = "Native Tailwind +15% · server acceptance unverified"
    end
    if CFG.broomDelay then
        if broomAction and type(setupvalue) == "function" then
            broomStatus = broomStatus .. " · F7 fast broom key ready"
        else broomStatus = "Broom input callback unavailable; retrying" end
    end
end
local function manualBroom()
    if not S.broomRequest or S.broomBusy then return end
    S.broomRequest = false
    if not CFG.broomDelay or not broomAction or UIS:GetFocusedTextBox() then return end
    local values = ups(broomAction)
    if (values[1] ~= nil and type(values[1]) ~= "boolean") or type(values[2]) ~= "function" or type(setupvalue) ~= "function" then return end
    -- One explicit manual action, not a continuous clear. Verify native gates
    -- first; broomAction immediately sets a fresh debounce/timer for this call.
    -- OFF/unload therefore leaves no cleared native cooldown to restore.
    S.broomBusy = true
    local ok, err = pcall(function()
        if not values[2]() then return end
        setupvalue(broomAction, 1, false)
        broomAction("Broom", Enum.UserInputState.Begin)
        Log.info("manual F7 native broom request; native timer retained")
    end)
    S.broomBusy = false
    if not ok then Log.err("manual broom", err) end
end
local function materialFrame()
    if not materialAlive() then releaseMaterials(); return end
    local now = workspace:GetServerTimeNow()
    local mining = CFG.autoMine and nativeSession(nativeTiming) or nil
    local harvest = CFG.autoHarvest and nativeSession(nativeRings) or nil
    if not CFG.autoMine and not CFG.autoHarvest then
        materialStatus = "Manual start; assistants OFF"
    elseif not mining and not harvest then
        local states = {}
        if CFG.autoMine then states[#states + 1] = nativePress and "Mine ready" or "Mine adapter unavailable" end
        if CFG.autoHarvest then states[#states + 1] = nativeRings and "Harvest ready" or "Harvest adapter unavailable" end
        materialStatus = table.concat(states, " · ") .. " · start a nearby node manually"
    end
    -- Release the previous session even if another minigame is still open.
    if S.lastHarvestSession ~= harvest or not CFG.autoHarvest then
        HarvestInput.release()
        Core.restore(ringFields, propertiesRead, propertiesWrite); S.lastHarvestSession = nil
    end
    if UIS:GetFocusedTextBox() then
        HarvestInput.release()
        Core.restore(ringFields, propertiesRead, propertiesWrite); S.lastHarvestSession = nil
        return
    end
    if CFG.autoMine and mining and nativePress and Core.mineReady(mining.round, now) then
        nativePress("HarvestTimingPress", Enum.UserInputState.Begin)
        Log.info("mining native critical press id=" .. tostring(mining.round.Id))
        materialStatus = "Native critical press sent; awaiting server result"
    end
    if CFG.autoHarvest and harvest and type(harvest.rings) == "table" and getmetatable(harvest.rings) == nil then
        -- Keep aim ownership between ring arrivals too; otherwise mouse motion
        -- can seed the next native frame before a newly arrived ring is steered.
        local exclusive = HarvestInput.step(harvest)
        Core.own(ringFields, harvest, "useMouse", false, propertiesRead, propertiesWrite, true)
        Core.own(ringFields, harvest, "stick", nil, propertiesRead, propertiesWrite, true)
        local target = Core.ringTarget(harvest.rings, now)
        if target then
            if S.lastHarvestSession ~= harvest then S.lastHarvestSession = harvest; Log.info("harvest native steering bound") end
            Core.own(ringFields, harvest, "target", target, propertiesRead, propertiesWrite, true)
        end
        S.lastHarvestSession = harvest
        materialStatus = exclusive and "Exclusive harvest aim · normal 540°/s turn cap"
            or "Native ring steering · mouse lock unavailable"
    elseif harvest then
        HarvestInput.release()
        Core.restore(ringFields, propertiesRead, propertiesWrite); S.lastHarvestSession = nil
        materialStatus = "Native harvest shape changed · manual aim restored"
    end
    if not mining and not harvest then
        HarvestInput.release()
        Core.restore(ringFields, propertiesRead, propertiesWrite)
    end
end
local function lootNote(note)
    if lootStatus ~= note then lootStatus = note; Log.info("loot " .. note) end
end
local function observeLoot(session)
    if not session.tracked or os.clock() < (session.nextObserve or 0) then return end
    session.nextObserve = os.clock() + 0.25
    local removed = 0
    for _, item in ipairs(session.tracked) do
        if item.Parent ~= session.container then removed += 1 end
    end
    if removed ~= session.removed then
        session.removed = removed
        lootNote(("%d/%d tracked item folders removed · not inventory receipt"):format(removed, #session.tracked))
    end
end
local function lootFrame()
    local session = lootSession
    if not CFG.autoLoot then lootSession = nil; lootArmed = false; lootNote("OFF · open a chest after enabling"); return end
    local char = LocalPlayer.Character
    local root = char and rootOf(char)
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if session then observeLoot(session) end
    if not hum or hum.Health <= 0 or (session and session.character ~= char) or S.materialCharacterLost then
        lootSession = nil; lootArmed = false
        lootNote("Character lost/replaced · pending loot cancelled"); return
    end
    local gui = LocalPlayer:FindFirstChild("PlayerGui")
    local lootUI = gui and gui:FindFirstChild("LootUI")
    local display = lootUI and lootUI:FindFirstChild("LootDisplay")
    local client = display and display:FindFirstChild("LootClient")
    if not client then
        lootSession = nil; lootArmed = false; lootNote("Native loot UI unavailable · no requests sent"); return
    end
    if not client:GetAttribute("Viewing") then
        if session then
            session.nextObserve = 0; observeLoot(session)
            lootNote("UI closed · " .. lootStatus .. " · no further requests")
        elseif not lootArmed then lootNote("Ready · open an unnamed chest") end
        lootSession = nil; lootArmed = true; return
    end
    if not session then return end
    if not root or not session.container.Parent or not session.collector.Parent
        or (root.Position - session.position).Magnitude > 11 then
        lootSession = nil; lootNote("Closed/out of range; nothing else sent"); return
    end
    if session.done or os.clock() < nextLootSend then return end
    nextLootSend = os.clock() + 0.1
    if not session.individual then
        -- W/0082:329-350 exposes a per-user countdown. Never spend the one
        -- attempt while it is positive. No inferred local expiry or retries.
        local cooldown = session.collector:FindFirstChild(tostring(LocalPlayer.UserId))
        if cooldown then
            local timer = cooldown:GetAttribute("timer") or cooldown:GetAttribute("cooldownTime")
            if type(timer) ~= "number" or timer ~= timer or math.abs(timer) == math.huge then
                lootNote("Unknown native Collect All cooldown · no request sent"); return
            end
            if timer > 0 then lootNote("Waiting for native Collect All cooldown · no request sent"); return end
        end
        session.done = true -- before request; errors also never cause retries
        session.tracked = {}
        for _, item in ipairs(session.container:GetChildren()) do
            if item:IsA("Folder") then
                session.tracked[#session.tracked + 1] = item
                if #session.tracked >= 64 then break end
            end
        end
        session.removed = 0
        local ok, err = pcall(function() session.collector:FireServer() end)
        if ok then
            lootNote("Collect All requested once · no removal observed · inventory unverified")
        else
            lootNote("Collect All request failed · " .. tostring(err):sub(1, 200) .. " · no retry")
        end
        return
    end
    if not session.items then
        session.items = {}
        for _, item in ipairs(session.container:GetChildren()) do
            if item:IsA("Folder") then
                local remote = item:FindFirstChildWhichIsA("RemoteEvent")
                if remote then
                    session.items[#session.items + 1] = {item = item, remote = remote}
                    if #session.items >= 64 then session.capped = true; break end
                end
            end
        end
        session.index = 1; session.sent = 0
    end
    -- Native per-item path, at most4 requests/0.1s and64/open. No retry loops,
    -- no forged loot IDs, no player-owned containers, no cooldown edits.
    for _ = 1, 4 do
        local item = session.items[session.index]
        if not item then session.done = true; break end
        session.index += 1
        if item.item.Parent == session.container and item.remote.Parent == item.item then
            item.remote:FireServer(); session.sent += 1
        end
    end
    lootStatus = ("%d individual requests · %s"):format(session.sent,
        session.done and (session.capped and "64-item cap; reopen for more" or "awaiting server inventory result") or "collecting")
end
local function bindLoot()
    local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
    local remote = remotes and remotes:FindFirstChild("LOOT")
    if not remote or not remote:IsA("RemoteEvent") then return end
    connect(remote.OnClientEvent, function(prompt, owner, container, position, collector)
        if not CFG.autoLoot or not lootArmed then return end
        -- Consume exactly the first event after an observed closed UI. The
        -- native handler ignores ALL further opens while Viewing, even if a
        -- different container is supplied. Never replace its accepted session.
        lootArmed = false
        -- Named loot includes player loot. Do not automatically take it.
        if owner ~= "" then lootNote("Named/player loot skipped"); return end
        if typeof(prompt) ~= "Instance" or not prompt:IsA("ProximityPrompt")
            or typeof(container) ~= "Instance" or typeof(position) ~= "Vector3"
            or typeof(collector) ~= "Instance" or not collector:IsA("RemoteEvent") then
            lootNote("Unknown loot event shape; no requests sent"); return
        end
        if lootSession and lootSession.container == container then return end
        lootSequence += 1
        lootSession = {id = lootSequence, container = container, position = position,
            collector = collector, individual = CFG.lootItems, done = false, character = LocalPlayer.Character}
        lootNote("Opened unnamed container " .. tostring(lootSequence) .. " queued")
    end)
end
local function promptDistance(prompt, char, root, folder)
    if not folder or not S.prompts[prompt] or not prompt.Enabled then return nil end
    local kind = (prompt.Name == "MinePrompt" and CFG.autoMine and nativePress and "Ores")
        or (prompt.Name == "HarvestPrompt" and CFG.autoHarvest and nativeRings and "Crops")
    local nodes = kind and folder:FindFirstChild(kind)
    if not nodes or not prompt:IsDescendantOf(nodes) then return nil end
    local parent = prompt.Parent
    local point = parent and (parent:IsA("Attachment") and parent.WorldPosition or (parent:IsA("BasePart") and parent.Position))
    if not point then return nil end
    local d = (point - root.Position).Magnitude
    if d > math.min(prompt.MaxActivationDistance, 15) then return nil end
    if prompt.RequiresLineOfSight then
        local ray = RaycastParams.new(); ray.FilterType = Enum.RaycastFilterType.Exclude; ray.FilterDescendantsInstances = {char}
        local from = workspace.CurrentCamera and workspace.CurrentCamera.CFrame.Position or root.Position
        local hit = workspace:Raycast(from, point - from, ray)
        local model = prompt:FindFirstAncestorWhichIsA("Model")
        if hit and not (model and hit.Instance:IsDescendantOf(model)) then return nil end
    end
    return d
end
local function promptStep()
    if not materialAlive() then releaseHold(); return end
    local char = LocalPlayer.Character
    local root = char and rootOf(char)
    local map = workspace:FindFirstChild("Map")
    local folder = map and map:FindFirstChild("Harvestable")
    local blocked = not CFG.autoStart or Challenge.busy() or not root or UIS:GetFocusedTextBox()
        or not game:GetService("ProximityPromptService").Enabled
        or LocalPlayer:GetAttribute("InCombat") or char:GetAttribute("Flying")
        or char:GetAttribute("State_Stunned") or char:GetAttribute("State_Knocked")
    if holdPrompt and (blocked or os.clock() >= holdDeadline
        or not promptDistance(holdPrompt, char, root, folder)) then releaseHold() end
    if blocked or holdPrompt or nativeSession(nativeTiming) or nativeSession(nativeRings) then return end
    local closest, distance
    -- Only shown prompts in the correct resource root; recheck held work too.
    for prompt in pairs(S.prompts) do
        if os.clock() >= (retryAt[prompt] or 0) then
            local d = promptDistance(prompt, char, root, folder)
            if d and (not distance or d < distance) then closest = prompt; distance = d end
        end
    end
    if closest then
        retryAt[closest] = os.clock() + math.max(2, closest.HoldDuration + 1)
        holdPrompt = closest; holdDeadline = os.clock() + closest.HoldDuration + 0.1
        closest:InputHoldBegin()
        Log.info("nearby prompt hold " .. closest.Name)
        materialStatus = "Holding nearby " .. closest.Name .. " · native tools still required"
    end
end
local function addCandidate(object, category)
    if not object or not object:IsA("Model") or object == LocalPlayer.Character then return end
    local existing = stagedRecords[object]
    if existing then
        if category == "indicators" then existing.category = category end
        return
    end
    if #stagedCandidates >= 1536 then S.overflow = true; return end
    local item = records[object] or { object = object }
    item.category = category; item.order = #stagedCandidates + 1
    stagedCandidates[#stagedCandidates + 1] = item; stagedRecords[object] = item
end
local function enqueueChildren(folder, category, recurse)
    if not folder then return end
    for _, child in ipairs(folder:GetChildren()) do
        if #queue >= 4096 then S.overflow = true; break end
        queue[#queue + 1] = { child, category, recurse }
    end
end
-- Tree 54307-54325: Objects.ShopObjects.Materials.Wood, not Map props.
-- ShopObject alone also tags clothes/weapons; this bounded folder + exact native
-- BuyPrompt/Price/Req shape avoids both unrelated shops and decorative logs.
local function woodRoot(object)
    local objects = workspace:FindFirstChild("Objects")
    local shops = objects and objects:FindFirstChild("ShopObjects")
    local materials = shops and shops:FindFirstChild("Materials")
    if not materials or object.Parent ~= materials or object.Name ~= "Wood" or not object:IsA("Model") then return nil end
    for index, part in ipairs(object:GetChildren()) do
        if index > 64 then break end
        if part.Name == "WoodStack" and part:IsA("BasePart") then
            local prompt = part:FindFirstChild("BuyPrompt")
            local price = prompt and prompt:FindFirstChild("Price")
            local req = prompt and prompt:FindFirstChild("Req")
            if prompt and prompt:IsA("ProximityPrompt") and prompt.Enabled ~= false
                and price and price:IsA("IntValue") and req and req:IsA("IntValue") then return part end
        end
    end
    return nil
end
local function discoveryStep(now)
    if not CFG.esp then return end
    if now >= nextDiscovery and not discovering then
        nextDiscovery = now + 2
        S.overflow = false; discovering = true
        stagedRecords, stagedCandidates = {}, {}
        enqueueChildren(workspace:FindFirstChild("FightableNPCS"), "enemies", false)
        enqueueChildren(workspace:FindFirstChild("NPCS"), "npcs", true)
        for _, p in ipairs(Players:GetPlayers()) do if p ~= LocalPlayer then addCandidate(p.Character, "players") end end
        local map = workspace:FindFirstChild("Map")
        local harvest = map and map:FindFirstChild("Harvestable")
        enqueueChildren(harvest and harvest:FindFirstChild("Ores"), "ores", false)
        enqueueChildren(harvest and harvest:FindFirstChild("Crops"), "crops", false)
        local objects = workspace:FindFirstChild("Objects")
        local shops = objects and objects:FindFirstChild("ShopObjects")
        enqueueChildren(shops and shops:FindFirstChild("Materials"), "wood", false)
        for _, m in ipairs(Collection:GetTagged("Waypoint")) do addCandidate(m, "waypoints") end
        for _, m in ipairs(Collection:GetTagged("ShowIndicator")) do addCandidate(m, "indicators") end
    end
    local start = os.clock()
    for _ = 1, 128 do
        local item = table.remove(queue)
        if not item then break end
        local object, category, recurse = item[1], item[2], item[3]
        if object:IsA("Model") then
            -- Dialogue registration expects humanoid + Head/Torso; do not turn
            -- arbitrary grouped prop Models into quest NPCs.
            if (category ~= "wood" or woodRoot(object)) and (category ~= "npcs"
                or (object:FindFirstChildOfClass("Humanoid") and object:FindFirstChild("Head") and object:FindFirstChild("Torso"))) then
                addCandidate(object, category)
            end
        elseif recurse and object:IsA("Folder") then enqueueChildren(object, category, true) end
        if os.clock() - start > 0.003 then break end
    end
    if discovering and #queue == 0 then
        records, candidates = stagedRecords, stagedCandidates
        discovering = false; cursor = 1
        for object in pairs(selectionCache) do if not records[object] then selectionCache[object] = nil end end
    end
    S.discovered = #candidates
end
local function makeMarker(row)
    local gui = Instance.new("BillboardGui")
    gui.Name = "CloverMarker"; gui.AlwaysOnTop = true; gui.Size = UDim2.fromOffset(230, 82)
    gui.StudsOffset = Vector3.new(0, 3.5, 0); gui.MaxDistance = 9300; gui.Parent = layer
    local label = Instance.new("TextLabel")
    label.Size = UDim2.fromOffset(230, 66); label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamMedium; label.TextSize = 12; label.TextStrokeTransparency = 0.25
    label.RichText = false; label.Parent = gui
    local highlight = Instance.new("Highlight")
    highlight.Name = "CloverOutline"; highlight.FillTransparency = 0.85; highlight.OutlineTransparency = 0.1
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop; highlight.Parent = layer
    local bar = Instance.new("Frame")
    bar.Name = "CloverHealthBar"; bar.BorderSizePixel = 0; bar.BackgroundColor3 = Color3.fromRGB(18, 22, 28)
    bar.BackgroundTransparency = 0.12; bar.ClipsDescendants = true; bar.Parent = gui
    local fill = Instance.new("Frame")
    fill.Name = "HealthFill"; fill.BorderSizePixel = 0; fill.Parent = bar
    local item = { gui = gui, label = label, highlight = highlight, bar = bar, fill = fill }
    markers[row.object] = item; return item
end
local function espStep()
    if not CFG.esp then return end
    local camera = workspace.CurrentCamera
    local localRoot = LocalPlayer.Character and rootOf(LocalPlayer.Character)
    local origin = localRoot and localRoot.Position or (camera and camera.CFrame.Position)
    if not origin then clearMarkers(); return end
    -- Rolling cache: update at most256 records/paint; never a Workspace render scan.
    local start = os.clock()
    for _ = 1, math.min(256, #candidates) do
        if cursor > #candidates then cursor = 1 end
        local row = candidates[cursor]; cursor += 1
        local object = row.object
        local root = object.Parent and (row.category == "wood" and woodRoot(object) or (row.category ~= "wood" and rootOf(object)))
        if root and object ~= LocalPlayer.Character then
            local hum = object:FindFirstChildOfClass("Humanoid")
            row.root = root; row.name = row.category == "wood" and "Wood pile (buy)"
                or (hum and hum.DisplayName ~= "" and hum.DisplayName or object.Name)
            row.distance = (root.Position - origin).Magnitude
            row.alive = not hum or hum.Health > 0
            row.hp = hum and math.floor(hum.Health) or nil; row.maxHp = hum and math.floor(hum.MaxHealth) or nil
            selectionCache[object] = row
        else selectionCache[object] = nil end
        if os.clock() - start > 0.003 then break end
    end
    local rows = {}
    for object, row in pairs(selectionCache) do
        if object.Parent and row.root and row.root.Parent then rows[#rows + 1] = row else selectionCache[object] = nil end
    end
    local chosen = Core.choose(rows, CFG)
    local keep = {}
    for _, row in ipairs(chosen) do
        keep[row.object] = true
        local item = markers[row.object] or makeMarker(row)
        local color = COLORS[row.category]
        item.gui.Adornee = row.root
        item.label.TextColor3 = color
        local style = Core.healthStyle(row.hp, row.maxHp, row.distance, CFG.healthRange)
        item.bar.Visible = CFG.healthBars and style.visible
            and (row.category == "enemies" or row.category == "players" or row.category == "indicators")
        item.bar.Size = UDim2.fromOffset(style.width, 7)
        item.bar.Position = UDim2.fromOffset((230 - style.width) / 2, 69)
        item.fill.Size = UDim2.fromScale(style.fraction, 1)
        item.fill.BackgroundColor3 = style.fraction > 0.6 and Color3.fromRGB(87, 211, 151)
            or (style.fraction > 0.3 and Color3.fromRGB(242, 193, 80) or Color3.fromRGB(243, 95, 105))
        local states = {}
        for _, state in ipairs({"Alerted", "Aggressive", "State_Attacking", "State_Dodging", "State_Parrying", "State_Knocked"}) do
            if row.object:GetAttribute(state) == true then states[#states + 1] = state:gsub("State_", "") end
        end
        local health = row.hp and ("HP %d/%d"):format(row.hp, row.maxHp) or ""
        item.label.Text = ("%s · %s\n%d studs  %s\n%s"):format(row.name, row.category, row.distance, health, table.concat(states, " · "))
        item.highlight.Adornee = row.object; item.highlight.Enabled = CFG.chams
        item.highlight.FillColor = color; item.highlight.OutlineColor = color
    end
    for object, item in pairs(markers) do
        if not keep[object] then item.gui:Destroy(); item.highlight:Destroy(); markers[object] = nil end
    end
    S.shown = #chosen
end

local eventBuffer, rateStart, rateCount, eventSequence = {}, 0, 0, 0
local criticalCount, outcomeCount, droppedEvents = 0, 0, 0
local captureSession = BUILD_VERSION .. ":" .. tostring(workspace:GetServerTimeNow())
local function describe(value, depth)
    local kind = typeof(value)
    if kind == "Instance" then return value:GetFullName() end
    if kind == "table" then
        if depth >= 1 or getmetatable(value) ~= nil then return "[table]" end
        local items = {}
        for k, v in next, value do
            items[#items + 1] = tostring(k):sub(1, 40) .. "=" .. describe(v, depth + 1)
            if #items >= 10 then break end
        end
        return "{" .. table.concat(items, ",") .. "}"
    end
    if kind == "string" then return value:gsub("[\r\n]", " "):sub(1, 100) end
    return tostring(value):sub(1, 100)
end
local function admitted(source)
    if not CFG.record then return false end
    local now = os.clock()
    if now - rateStart >= 1 then rateStart = now; rateCount = 0; criticalCount = 0; outcomeCount = 0 end
    local outcome = source == "Health" or source == "LocalState"
    local critical = source == "ThreatAnim" or source == "ThreatState"
    -- Separate budgets: neither global FX nor animation floods consume local
    -- outcome allowance. The last 64 buffer slots are reserved for outcomes.
    if #eventBuffer >= 256 or (outcome and outcomeCount >= 100)
        or (not outcome and #eventBuffer >= 192) or (critical and criticalCount >= 100)
        or (not outcome and not critical and (rateCount >= 20 or #eventBuffer >= 128)) then
        return false
    end
    return true
end
local function observe(source, ...)
    if not admitted(source) then
        if CFG.record then droppedEvents += 1 end
        return
    end
    local outcome = source == "Health" or source == "LocalState"
    local critical = source == "ThreatAnim" or source == "ThreatState"
    if outcome then outcomeCount += 1 elseif critical then criticalCount += 1 else rateCount += 1 end
    eventSequence += 1
    local args = table.pack(...)
    local parts = {}
    for i = 1, math.min(args.n, 8) do parts[#parts + 1] = describe(args[i], 0) end
    S.events += 1; S.latest = source .. " " .. (parts[1] or "")
    eventBuffer[#eventBuffer + 1] = ("%d %.3f %s %s | session=%s"):format(eventSequence, workspace:GetServerTimeNow(), source, table.concat(parts, " | "), captureSession)
end
local function flushEvents()
    if #eventBuffer == 0 and droppedEvents == 0 then return end
    local batch = table.concat(eventBuffer, "\n") .. "\n"
    if droppedEvents > 0 then batch ..= ("CAPTURE_DROPPED %d session=%s\n"):format(droppedEvents, captureSession) end
    local path = "logs/clover_defense_observer.log"
    local ok, err = pcall(function()
        if isfile(path) then appendfile(path, batch) else writefile(path, batch) end
    end)
    if ok then table.clear(eventBuffer); droppedEvents = 0 elseif not S.failures.observerLog then S.failures.observerLog = true; Log.err("observer file", err) end
end
-- Native waypoint travel. No coordinate teleport, unlock spoof or auto-travel.
local TownTravel = (function()
    local api = {status = "Refresh unlocks, then choose a destination", unlocked = {}}
    api.towns = {
        {id = "KamoWaypoint", name = "Kamo Village", tier = "1 · Starter town"},
        {id = "MushroomWaypoint", name = "Dewcap Village", tier = "2 · After Kamo / Mushroom Forest"},
        {id = "EldritchWaypoint", name = "Forsaken Village", tier = "3 · Later region / Eldritch"},
        {id = "SwampWaypoint", name = "Swamp", tier = "4 · Advanced wilderness (not a town)"},
    }
    local pending, nextRequest, generation = false, 0, 0
    local function context()
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local root = char and rootOf(char)
        if not S.alive or not hum or hum.Health <= 0 or not root or S.defenseTransition then return nil, "Character unavailable" end
        if UIS:GetFocusedTextBox() then return nil, "Finish text input first" end
        if char:GetAttribute("InCombat") or LocalPlayer:GetAttribute("InCombat") or char:GetAttribute("Flying")
            or char:GetAttribute("State_Stunned") or char:GetAttribute("State_Downed") then return nil, "Wait until idle, grounded and out of combat" end
        local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
        local remote = remotes and remotes:FindFirstChild("WaypointRemote")
        remote = remote and remote:FindFirstChild("Invoke")
        if not remote or not remote:IsA("RemoteFunction") then return nil, "Native waypoint service unavailable" end
        return {char = char, root = root, remote = remote}
    end
    function api.label(id)
        return api.unlocked[id] and "Unlocked" or "Locked / not checked"
    end
    function api.request(id)
        if pending then api.status = "Waiting for native waypoint response"; return end
        if os.clock() < nextRequest then api.status = "Wait two seconds between requests"; return end
        local ctx, reason = context()
        if not ctx then api.status = reason; return end
        if id then
            local known = false; for _, town in ipairs(api.towns) do if town.id == id then known = true end end
            if not known then api.status = "Unknown destination"; return end
            if not api.unlocked[id] then api.status = "Destination locked / not checked · refresh unlocks first"; return end
            for _, portal in ipairs(Collection:GetTagged("Waypoint")) do
                if portal.Name == id and portal:IsA("Model") and portal.PrimaryPart
                    and (ctx.root.Position - portal.PrimaryPart.Position).Magnitude <= 15 then
                    api.status = "Already at this waypoint"; return
                end
            end
        end
        pending = true; nextRequest = os.clock() + 2
        local token = generation
        api.status = id and "Requesting native travel…" or "Reading native waypoint unlocks…"
        task.spawn(function()
            if not S.alive or generation ~= token or LocalPlayer.Character ~= ctx.char then pending = false; return end
            -- Recheck live eligibility after the scheduling boundary, before any request.
            local fresh = context()
            if not fresh or fresh.char ~= ctx.char then pending = false; api.status = "Travel cancelled · state changed"; return end
            local ok, result = pcall(function() return ctx.remote:InvokeServer(id and "Teleport" or "GetData", id) end)
            if not S.alive or generation ~= token or LocalPlayer.Character ~= ctx.char then pending = false; return end
            pending = false
            if not ok then api.status = "Native request failed · no retry"; Log.err("town travel", tostring(result)); return end
            if not id then
                if type(result) ~= "table" or getmetatable(result) ~= nil then api.status = "Unknown unlock response · no change"; return end
                local data, count = {}, 0
                for _, town in ipairs(api.towns) do if rawget(result, town.id) then data[town.id] = true; count += 1 end end
                api.unlocked = data; api.status = tostring(count) .. "/4 waypoints unlocked · choose a destination"
            else
                api.status = result == true and "Native travel accepted · check arrival in-world" or "Native travel declined · unlock/quest/server rules remain"
            end
            Log.info("town travel " .. tostring(id or "GetData") .. ": " .. api.status)
        end)
    end
    function api.cancel() generation += 1; api.status = "Travel cancelled · no automatic retry" end
    return api
end)()
-- Client broom leases: no synthetic mounts, motor writes, or no-fly bypass.
local BroomFlex = (function()
    local api = {altitude = "OFF", cooldown = "OFF"}
    local altitude, binding, scanned, retryAt, pending = nil, nil, nil, 0, false
    local function current(char)
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        return S.alive and LocalPlayer.Character == char and hum and hum.Health > 0
    end
    local function named(fn, name, source)
        if type(fn) ~= "function" then return false end
        local ok, n = pcall(debug.info, fn, "n")
        local good, env = pcall(getfenv, fn)
        return ok and n == name and good and rawget(env, "script") == source
    end
    local function releaseAltitude()
        if altitude then
            local a = altitude; altitude = nil
            if ups(a.fn)[8] == a.last then pcall(setupvalue, a.fn, 8, a.original) end
        end
        api.altitude = "OFF"
    end
    local function releaseBinding()
        if binding then
            local a = binding; binding = nil
            if ups(a.update)[4] == a.wrapper then
                pcall(setupvalue, a.update, 4, a.original)
                if S.alive then pcall(a.update)
                else task.spawn(function() pcall(a.update) end) end
            end
        end
        api.cooldown = "OFF"
    end
    function api.release() releaseAltitude(); releaseBinding(); scanned = nil end
    function api.apply()
        if not CFG.broomAltitude then releaseAltitude(); scanned = nil end
        if not CFG.broomDelay then releaseBinding() end
    end
    local function valid(a)
        local u = ups(a.fn)
        return named(a.fn, "flyStep", a.source) and u[5] == a.char and u[4] == a.root
            and type(u[8]) == "number" and u[8] == u[8] and math.abs(u[8]) < math.huge
            and type(u[1]) == "table" and rawget(u[1], "Model") == a.char
            and typeof(u[19]) == "Instance" and u[19]:IsA("LinearVelocity")
            and (u[19]:IsDescendantOf(a.root)
                -- W1026:714: the native controller detaches its Attachment
                -- while grounded. Accept only its captured velocity/Attachment0;
                -- never reparent it or actuate flight to make discovery pass.
                or (u[19].Attachment0 and u[19].Parent == u[19].Attachment0
                    and u[19].Attachment0:IsA("Attachment") and u[19].Attachment0.Parent == nil))
    end
    function api.step()
        api.apply()
        local char = LocalPlayer.Character
        if not current(char) then api.release(); return end
        local source = char:FindFirstChild("BroomClient")
        local root = rootOf(char)
        if altitude and (altitude.char ~= char or not valid(altitude)) then releaseAltitude(); scanned = nil end
        if binding and (binding.char ~= char or ups(binding.update)[4] ~= binding.wrapper) then releaseBinding(); retryAt = os.clock() + 2 end
        if binding and binding.request then
            local request = binding.request
            if (char:GetAttribute("Flying") == true) ~= request.flying then
                api.cooldown = "Native flight state changed · local debounce bypass active"
                Log.info("broom key result: Flying changed after manual request"); binding.request = nil
            elseif os.clock() - request.at >= 1.25 then
                api.cooldown = "No flight change after request · native/server gate unresolved"
                Log.info("broom key result: no Flying change; not proof of cooldown bypass"); binding.request = nil
            end
        end
        if CFG.broomAltitude and not altitude and root and source and type(setupvalue) == "function" then
            local gc = HeapDiscovery.get(char, char:FindFirstChildOfClass("Humanoid"))
            if gc ~= scanned then
                scanned = gc
                local found, ambiguous
                local start, visits = os.clock(), 0
                for _, fn in next, gc do
                    visits += 1; if visits > 250000 then break end
                    if named(fn, "flyStep", source) then
                        local a = {fn = fn, char = char, root = root, source = source}
                        if valid(a) then if found and found.fn ~= fn then ambiguous = true end; found = a end
                    end
                    if os.clock() - start >= 0.003 then
                        task.wait(); start = os.clock()
                        if not current(char) or not CFG.broomAltitude then return end
                    end
                end
                if found and not ambiguous and current(char) and CFG.broomAltitude then
                    found.original = ups(found.fn)[8]; found.last = found.original; altitude = found
                end
            end
            api.altitude = "Native altitude adapter unavailable · " .. HeapDiscovery.note()
        end
        if altitude and CFG.broomAltitude then
            local a = altitude
            local value = ups(a.fn)[8]
            if value ~= a.last then a.original = value end -- native profession update
            local ok = pcall(setupvalue, a.fn, 8, 1000000) -- finite: no infinity/NaN in native meter
            if ok then a.last = 1000000; api.altitude = "Client altitude ceiling lifted · no-fly/water gates stay native"
            else releaseAltitude(); api.altitude = "Altitude cell unavailable" end
        end
        if not CFG.broomDelay or binding or os.clock() < retryAt then return end
        retryAt = os.clock() + 2
        local binds = LocalPlayer:FindFirstChild("Binds")
        local bind = binds and binds:FindFirstChild("Broom")
        api.cooldown = "Native broom key adapter unavailable · F7 fallback"
        if not bind or not source or type(getconnections) ~= "function" or type(setupvalue) ~= "function" then return end
        for _, conn in ipairs(getconnections(bind:GetPropertyChangedSignal("Value"))) do
            local u = ups(conn.Function)
            local ok, name = pcall(debug.info, conn.Function, "n")
            if ok and name == "update" and u[1] == bind and u[3] == "Broom" and named(u[4], "broomAction", source) then
                local a = {char = char, original = u[4], update = conn.Function}
                local captures = ups(a.original)
                if type(captures[2]) ~= "function" or type(captures[3]) ~= "table" or rawget(captures[3], "Model") ~= char then return end
                a.wrapper = function(action, state, input)
                    if binding ~= a or not CFG.broomDelay or not current(char) then return a.original(action, state, input) end
                    if state == Enum.UserInputState.Begin then
                        if pending then api.cooldown = "Previous native broom request still pending"; return end
                        if UIS:GetFocusedTextBox() then return end
                        local values = ups(a.original)
                        if values[1] ~= nil and type(values[1]) ~= "boolean" then return end
                        if values[2] ~= captures[2] or values[3] ~= captures[3] or values[4] ~= captures[4] then return end
                        if not values[2]() then
                            api.cooldown = "Native broom eligibility lock"
                            Log.info("broom key blocked by native canUseBroom (combat/no-fly/climb/water/body mover)"); return
                        end
                        setupvalue(a.original, 1, false)
                        pending = true
                        a.request = {flying = char:GetAttribute("Flying") == true, at = os.clock()}
                        Log.info("broom key request: manual native action; local debounce cleared; Flying=" .. tostring(a.request.flying))
                        local success, err = pcall(a.original, action, state, input)
                        pending = false
                        if not success then
                            a.request = nil; Log.err("broom key", err); api.cooldown = "Native broom request failed"
                        else api.cooldown = "Native broom request sent · awaiting flight state change" end
                        return
                    end
                    return a.original(action, state, input)
                end
                setupvalue(a.update, 4, a.wrapper); binding = a
                if not pcall(a.update) then releaseBinding(); return end
                api.cooldown = "Manual broom key ready · local 1s debounce bypass · server timer unknown"
                return
            end
        end
    end
    return api
end)()
-- Candidate cues are NOT impact timestamps or proof of parryability. This
-- controller requests ordinary native guard and records enough to tune misses.
local AutoParry = (function()
    local api = {status = "OFF · saved choice resumes", requests = 0, damage = 0}
    local watched, localConns, catalog = {}, {}, nil
    local adapter, character, held, heldCue
    local attemptedCues, activeCues = {}, {}
    -- Captured asset HitWindow markers, not server parryability guarantees.
    -- parry_timing_assets / clover_melee_hitwindows / clover_all_melee_windows
    -- logs, nonces parry-timing-77b1 / melee-hitwindows-6f2c / clover-all-melee-windows-f52e.
    -- Offline lookup only: no asset/network requests in the combat loop.
    local hitWindows = {
        ["86722279259826"] = {0.5}, ["107811934597910"] = {0.416666657},
        ["122307357536158"] = {0.449999988}, ["89849437438829"] = {0.449999988},
        ["89652204450491"] = {0.416666657}, ["74594683886829"] = {0.433333337},
        ["9757167816"] = {0.25}, -- AerialKickUp
        ["9922542154"] = {1.639999986}, -- AlkeRoar
        ["13756358680"] = {0.551666677}, -- Attack 1
        ["13756407921"] = {0.600000024}, -- Attack 2
        ["13756521296"] = {1.066666722}, -- Attack 3
        ["85982255640312"] = {0.516666651}, -- BlightSlashLeft
        ["125482975672454"] = {0.5}, -- BlightSlashRight
        ["16790816582"] = {2.708333254}, -- Bomb
        ["80495839788581"] = {0.449999988}, -- Brute Slam
        ["112682800928139"] = {0.566666663}, -- Brute Swing 1
        ["72354029824787"] = {0.616666675}, -- Brute Swing 2
        ["127837901620547"] = {0.533333361}, -- Cinderblade
        ["81129151966619"] = {0.366666675}, -- Combat
        ["16786767788"] = {1, 1.208333373, 1.458333373, 1.708333373, 1.958333373, 2.166666746}, -- Consecutive
        ["90147459897801"] = {0.449999988}, -- CrawlerCritical
        ["112272302102744"] = {0.183333337}, -- CrawlerLeft
        ["75576032954820"] = {0.449999988}, -- CrawlerRight
        ["70936328766912"] = {0.466666669}, -- Dagger1
        ["120283215167024"] = {0.200000003}, -- Dagger2
        ["94189509684810"] = {0.300000012}, -- Dagger3
        ["11262591531"] = {0.233333334}, -- DaggerSpin
        ["16889541896"] = {0.958333313}, -- Double
        ["125318199927195"] = {1.100000024, 1.633333325}, -- Elderthorne
        ["18320514554"] = {1.791666627}, -- ElkStomp1
        ["18192998083"] = {1.791666627}, -- ElkStomp2
        ["78707415805986"] = {0.816666663}, -- Elkstrider
        ["14158890923"] = {0.669166684}, -- Golem 1
        ["14158953103"] = {0.463333338}, -- Golem 2
        ["11469887779"] = {1.116666675}, -- GrabLunge
        ["11100902766"] = {0.280000001}, -- Greataxe2
        ["11100897909"] = {0.400000006}, -- Greataxe3
        ["106122835616423"] = {0.433333337}, -- Greatsword
        ["11169772012"] = {0.333333343}, -- GreatswordSprint
        ["18133497814"] = {0.699999988}, -- GrovePounce
        ["18133501787"] = {1}, -- GroveTailSwipe
        ["8594363819"] = {0.600000024}, -- Heavy
        ["17564283859"] = {0.039999999}, -- HeavyGreataxe
        ["11100915060"] = {0.533333361}, -- HeavyGreatsword
        ["14452988294"] = {0.800000012}, -- HeavyKatana
        ["76395852273763"] = {0.283333331}, -- HeavyScythe
        ["10017994824"] = {0.583333313}, -- HeavySpear
        ["12955527930"] = {1.233333349}, -- HeavyStaff
        ["75088128678260"] = {0.783333361}, -- HeavySword
        ["132013056786173"] = {0.883333325, 1.649999976}, -- HollowseerBite
        ["16992820686"] = {0.416666657}, -- Jump attack
        ["14527230703"] = {0.766666651}, -- Katana1
        ["14527234407"] = {0.699999988}, -- Katana2
        ["112932641545194"] = {0.720000029}, -- Katana3
        ["99787918237880"] = {0.383333325}, -- Knockback
        ["17049621435"] = {1}, -- LeftStrike
        ["103140391021149"] = {0.633333325}, -- LizardBoss1
        ["110876955202970"] = {0.654999971}, -- LizardBoss2
        ["120129566668137"] = {0.766666651}, -- LizardBoss3
        ["73042737238490"] = {0.633333325}, -- LizardBossStomp
        ["71375698527524"] = {0.533333361}, -- LizardSoldier1
        ["115413726601821"] = {0.566666663}, -- LizardSoldier2
        ["100328615092856"] = {0.538333356}, -- LizardSoldier3
        ["87606723288055"] = {0.616666675}, -- LizardSoldier4
        ["13960430722"] = {0.800000012}, -- Mace Swing 1
        ["13960433818"] = {0.159999996}, -- Mace Swing 2
        ["10250846568"] = {0.216666669}, -- Misdirect
        ["71734496574082"] = {0.779999971}, -- MushknightGrab
        ["106981115410840"] = {0.566666663}, -- MushmiteHeadbutt
        ["114135137062549"] = {1}, -- MushRushAnim
        ["17861866763"] = {0.833333313}, -- OgreSwipe1
        ["17861869512"] = {0.333333343}, -- OgreSwipe2
        ["117064630778013"] = {1.016666651}, -- PrimevalBattleaxe
        ["123693468061117"] = {0.349999994}, -- Punch1
        ["111510911006717"] = {0.416666657}, -- Punch2
        ["85570415456598"] = {0.366666675}, -- Punch3
        ["16926676358"] = {0.791666687}, -- RageScreech
        ["123565976636065"] = {0.533333361}, -- Rapier1
        ["88525660121099"] = {0.483333319}, -- Rapier2
        ["75817196379763"] = {0.533333361}, -- Rapier3
        ["17049581150"] = {1}, -- RightStrike
        ["136129024555254"] = {0.349999994}, -- RunningDagger
        ["16933879612"] = {1.625}, -- Rupture
        ["16386284918"] = {1.416666627}, -- Screech
        ["131449711194289"] = {0.433333337}, -- Scythe
        ["104165983064642"] = {0.483333319}, -- Scythe1
        ["70574481445445"] = {0.5}, -- Scythe2
        ["115704466488110"] = {0.466666669}, -- Scythe3
        ["96581414677240"] = {0.550000012}, -- ScytheSprint
        ["16380529517"] = {1.791666627}, -- Slam
        ["13822736997"] = {0.699999988}, -- Slam
        ["16434619660"] = {0.466666669}, -- Slam
        ["18334915919"] = {0.433333337}, -- Spirit1
        ["18334923698"] = {0.333333343}, -- Spirit2
        ["10230852540"] = {0.216666669}, -- SprintKick
        ["12808226586"] = {0.233333334}, -- Staff1
        ["12808233350"] = {0.083333336}, -- Staff2
        ["10017557380"] = {0.400000006}, -- Staff3
        ["13822728105"] = {0.600000024}, -- Swing 1
        ["13822732009"] = {0.283333331}, -- Swing 2
        ["85853530330509"] = {0.416666657}, -- Sword
        ["10017535748"] = {0.383333325}, -- Trident1
        ["10017543126"] = {0.300000012}, -- Trident2
        ["75695780896011"] = {0.5}, -- Uppercut
        ["113524095169996"] = {1.166666627}, -- VenomFang
        ["125957249913572"] = {0.896666646}, -- Wolf1
        ["73629219095110"] = {0.862083316}, -- Wolf2
        ["11892996649"] = {0.516666651}, -- Zombie1
        ["11893001175"] = {0.433333337}, -- Zombie2
        ["11893004134"] = {0.600000024}, -- ZombieKnockback
    }
    local nextScan, nextTick, nextSend, lastDecision, serial, actorSerial = 0, 0, 0, nil, 0, 0
    local queue, dropped, bytes, part, prefix, logPath = {}, 0, 0, 0, nil, nil
    local nextFlush, nextSummary, lastCue, lastRequest = 0, 0, nil, nil
    local emitWindow, emitCount, latest = 0, 0, nil
    local function plain(v) return type(v) == "table" and getmetatable(v) == nil end
    local function pos(v) return {v.X, v.Y, v.Z} end
    local function openLog()
        if prefix then return end
        prefix = "logs/clover_parry_" .. tostring(os.time()) .. "_" .. tostring(math.floor(os.clock() * 1000))
        logPath = prefix .. ".0.jsonl"
    end
    local function emit(kind, data)
        openLog()
        local now = os.clock()
        if now - emitWindow >= 1 then emitWindow = now; emitCount = 0 end
        if #queue >= 128 or emitCount >= 64 then dropped += 1; return end
        emitCount += 1
        local row = data or {}
        row.event = kind; row.build = BUILD_VERSION; row.clock = now
        row.serverTime = workspace:GetServerTimeNow(); row.session = prefix
        queue[#queue + 1] = Http:JSONEncode(row)
    end
    function api.flush(force)
        if not prefix or (not force and os.clock() < nextFlush) then return end
        nextFlush = os.clock() + 0.5
        if #queue == 0 then return end
        local text = table.concat(queue, "\n") .. "\n"
        local ok, err = pcall(function()
            if bytes + #text > 2097152 then part = 1 - part; bytes = 0; logPath = prefix .. "." .. tostring(part) .. ".jsonl" end
            if bytes == 0 then writefile(logPath, text) else appendfile(logPath, text) end
            bytes += #text
            writefile("logs/clover_parry_latest.json", Http:JSONEncode({build = BUILD_VERSION,
                session = prefix, current = logPath, bytes = bytes, dropped = dropped}))
        end)
        if ok then table.clear(queue)
        elseif not S.failures.parryLog then S.failures.parryLog = true; Log.err("parry log", err) end
    end
    local function states(char)
        local values = {}
        for _, key in ipairs({"Parrying", "ParryCooldown", "Blocking", "SwordBlocking", "Attacking", "Occupied",
            "Stunned", "Dodging", "SkillActive", "Downed", "Ragdoll", "Parried", "ParriedAttack"}) do
            if char:GetAttribute("State_" .. key) then values[#values + 1] = key end
        end
        return table.concat(values, ",")
    end
    local function manual()
        return adapter and ups(adapter.block)[1] == true
    end
    local function send(action, reason, cue)
        if not adapter or adapter.char ~= LocalPlayer.Character then return false end
        local target = adapter
        local function deliver()
            local ok, err = pcall(target.send, {Action = action})
            emit(ok and "request" or "request_error", {action = action, reason = reason, cue = cue and cue.id,
                detail = cue, states = states(target.char), error = not ok and tostring(err) or nil})
            if ok and action == "Block Input" then api.requests += 1; lastRequest = os.clock() end
            if not S.alive then api.flush(true) end
            return ok
        end
        -- Native closures can strip the caller's CoreGui capability (§9).
        -- On unload capture the adapter before release clears it, then finish
        -- native End Block on its own task, never the Hub's remount thread.
        if not S.alive then task.spawn(deliver); return true end
        return deliver()
    end
    local function endGuard(reason)
        if not held then return end
        if manual() then emit("manual_takeover", {reason = reason, cue = heldCue})
        else send("End Block", reason) end
        held, heldCue = nil, nil
        nextSend = os.clock() -- native readiness, not an extra release timer, gates the next pulse
    end
    local function forget(object)
        local entry = watched[object]
        if not entry then return end
        for _, conn in ipairs(entry.conns) do conn:Disconnect() end
        watched[object] = nil
    end
    function api.release(reason)
        endGuard(reason or "OFF")
        local objects = {}; for object in pairs(watched) do objects[#objects + 1] = object end
        for _, object in ipairs(objects) do forget(object) end
        for _, conn in ipairs(localConns) do conn:Disconnect() end
        table.clear(localConns)
        adapter, character, lastDecision, lastCue = nil, nil, nil, nil
        table.clear(attemptedCues); table.clear(activeCues)
        nextScan = 0; api.status = "OFF · saved choice resumes"
        api.flush(true)
    end
    local function named(fn, name, source)
        if type(fn) ~= "function" then return false end
        local ok, n = pcall(debug.info, fn, "n")
        if not ok or n ~= name then return false end
        if source then local good, env = pcall(getfenv, fn); return good and rawget(env, "script") == source end
        return true
    end
    local function bind(char)
        local scripts = char:FindFirstChild("CharacterScripts")
        local source = scripts and scripts:FindFirstChild("CombatClient")
        local binds = LocalPlayer:FindFirstChild("Binds")
        local block = binds and binds:FindFirstChild("Block")
        if not source or not block or type(getconnections) ~= "function" then return false end
        for _, conn in ipairs(getconnections(block:GetPropertyChangedSignal("Value"))) do
            local values = ups(conn.Function)
            if named(conn.Function, "update") and values[1] == block and values[3] == "Block"
                and named(values[4], "blockAction", source) then
                local fn = values[4]
                local captures = ups(fn)
                local packets = plain(captures[2]) and rawget(captures[2], "Combat")
                packets = plain(packets) and rawget(packets, "packets")
                packets = plain(packets) and rawget(packets, "BlockInput")
                local modules = game:GetService("ReplicatedStorage"):FindFirstChild("Modules")
                local smSource = modules and modules:FindFirstChild("StateManager")
                -- Native ByteNet descriptors have a metatable (live nonce
                -- parry-validation-43e7a2); raw send avoids invoking its __index.
                if type(packets) == "table" and type(rawget(packets, "send")) == "function" and smSource then
                    local sm = require(smSource).require(char)
                    if sm.Model == char and type(sm.CanParry) == "function" and type(sm.CanBlock) == "function" then
                        adapter = {char = char, source = source, block = fn, bind = block, send = packets.send, sm = sm}
                        emit("adapter", {source = source:GetFullName(), bind = tostring(block.Value), native = "BlockInput", gate = "CanParry/CanBlock"})
                        return true
                    end
                end
            end
        end
        return false
    end
    local function buildCatalog()
        catalog = {}
        local animations = game:GetService("ReplicatedStorage"):FindFirstChild("Animations")
        if not animations then return end
        local total = 0
        for _, spec in ipairs({{"Server", "melee"}, {"Combat", "melee"}, {"Crit", "melee"},
            {"Aerials", "melee"}, {"Uppercuts", "melee"}, {"NPCS", "npc"}, {"Skills", "spell"}, {"Magic", "spell"}}) do
            local folder = animations:FindFirstChild(spec[1])
            if folder then for _, animation in ipairs(folder:GetDescendants()) do
                total += 1; if total > 4096 then break end
                if animation:IsA("Animation") then
                    local name = animation.Name:lower()
                    local idle = name:find("idle", 1, true) or name == "walk" or name == "run" or name == "jump"
                        or name:find("stagger", 1, true) or name:find("death", 1, true) or name:find("block", 1, true)
                    local id = animation.AnimationId:match("%d+")
                    if id and (hitWindows[id] or not idle) and not catalog[id] then
                        catalog[id] = {name = animation.Name, path = animation:GetFullName(), kind = spec[2], hits = hitWindows[id]}
                    end
                end
            end end
            if total > 4096 then break end
        end
        local count = 0; for _ in pairs(catalog) do count += 1 end
        local profiles = 0; for _ in pairs(hitWindows) do profiles += 1 end
        emit("catalog", {count = count, scanned = total, profiles = profiles,
            timing = "captured native HitWindow markers; per-hit pulses, unknown active attacks uncalibrated"})
    end
    local function add(object, hum, root, animator, kind)
        actorSerial += 1
        local entry = {object = object, hum = hum, root = root, animator = animator, kind = kind,
            id = actorSerial, tracks = {}, conns = {}, stateSerial = 0, attacking = false}
        watched[object] = entry
        local function started(track, phase)
            if watched[object] ~= entry or not CFG.autoParry or (phase ~= "start" and entry.tracks[track]) then return end
            local selfRoot = character and rootOf(character)
            if not selfRoot or not selfRoot.Parent or LocalPlayer.Character ~= character then return end
            local count = 0; for old in pairs(entry.tracks) do
                if not old.IsPlaying then entry.tracks[old] = nil elseif old ~= track then count += 1 end
            end
            if count >= 16 then dropped += 1; return end
            serial += 16 -- reserve distinct identities for every hit within a reused animation
            local id = track.Animation and track.Animation.AnimationId:match("%d+")
            local info = id and catalog[id]
            local cue = {id = serial, actor = entry.id, object = object:GetFullName(), scope = kind,
                animation = id or "unknown", name = info and info.name or "unclassified", kind = info and info.kind,
                hits = info and info.hits,
                first = os.clock(), phase = phase}
            entry.tracks[track] = cue
            emit("animation", {cue = cue, time = track.TimePosition, speed = track.Speed, length = track.Length,
                distance = (root.Position - selfRoot.Position).Magnitude})
        end
        entry.conns[#entry.conns + 1] = object.AttributeChanged:Connect(function(key)
            if watched[object] == entry and (key == "State_Parried" or key == "State_ParriedAttack" or key == "State_BlockBroken") then
                emit("opponent_state", {actor = entry.id, object = object:GetFullName(), key = key,
                    value = object:GetAttribute(key), lastCue = lastCue,
                    lastRequestAge = lastRequest and os.clock() - lastRequest,
                    note = "Replicated opponent state; correlation, not attributed parry success"})
            end
        end)
        entry.conns[#entry.conns + 1] = animator.AnimationPlayed:Connect(function(track) started(track, "start") end)
        for i, track in ipairs(animator:GetPlayingAnimationTracks()) do if i > 16 then break end; started(track, "present") end
    end
    local function scan(root)
        nextScan = os.clock() + 0.2
        local rows = {}
        local function candidate(object, kind)
            if not object or object == character or not object:IsA("Model") then return end
            local hum = object:FindFirstChildOfClass("Humanoid")
            local other = hum and rootOf(object)
            local animator = hum and hum:FindFirstChildOfClass("Animator")
            if not other or not animator or hum.Health <= 0 then return end
            local distance = (other.Position - root.Position).Magnitude
            if distance <= math.max(120, CFG.parrySpellRange) then rows[#rows + 1] = {object, hum, other, animator, kind, distance} end
            return true
        end
        if CFG.parryPve then
            local visited = 0
            local function visit(folder, depth)
                for _, object in ipairs(folder:GetChildren()) do
                    if object:IsA("Model") or object:IsA("Folder") then
                        visited += 1; if visited > 1024 then return end
                        if not candidate(object, "pve") and depth < 4 then visit(object, depth + 1) end
                    end
                end
            end
            for _, name in ipairs({"FightableNPCS", "NPCS"}) do
                local folder = workspace:FindFirstChild(name)
                if folder then visit(folder, 0) end
            end
        end
        if CFG.parryPvp then for i, player in ipairs(Players:GetPlayers()) do if i > 100 then break end; candidate(player.Character, "pvp") end end
        table.sort(rows, function(a, b) return a[6] < b[6] end)
        local keep = {}
        for i = 1, math.min(48, #rows) do
            local row = rows[i]; local object = row[1]; keep[object] = true
            local entry = watched[object]
            if entry and (entry.animator ~= row[4] or entry.root ~= row[3]) then forget(object); entry = nil end
            if not entry then add(object, row[2], row[3], row[4], row[5]) end
        end
        local remove = {}; for object in pairs(watched) do if not keep[object] then remove[#remove + 1] = object end end
        for _, object in ipairs(remove) do forget(object) end
    end
    local function startLocal(char, hum)
        character = char
        openLog()
        emit("armed", {pve = CFG.parryPve, pvp = CFG.parryPvp, range = CFG.parryRange,
            spellRange = CFG.parrySpellRange, fallback = CFG.parryFallback, job = game.JobId,
            note = "No exact impact/eligibility claim. State_Parrying is not success."})
        local hp = hum.Health
        localConns[#localConns + 1] = hum.HealthChanged:Connect(function(value)
            if value < hp then api.damage += 1 end
            emit("health", {before = hp, after = value, loss = math.max(0, hp - value),
                lastCue = lastCue, lastRequestAge = lastRequest and os.clock() - lastRequest,
                held = held == true, states = states(char), decision = lastDecision})
            hp = value
        end)
        localConns[#localConns + 1] = char.AttributeChanged:Connect(function(key)
            if key:sub(1, 6) == "State_" or key == "Flying" then
                emit("local_state", {key = key, value = char:GetAttribute(key), cue = lastCue, held = held == true})
            end
        end)
        local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
        local client = remotes and remotes:FindFirstChild("Client")
        for _, name in ipairs({"ClientVFX", "NPCVFX"}) do
            local remote = client and client:FindFirstChild(name)
            if remote then localConns[#localConns + 1] = remote.OnClientEvent:Connect(function(effect, object)
                if object == char then emit("local_fx", {channel = name, effect = tostring(effect), cue = lastCue,
                    note = "FX observation, not attributed success"}) end
            end) end
        end
    end
    local function decide(reason, cue, extra)
        local key = reason .. ":" .. tostring(cue and cue.id or "none")
        api.status = reason .. (cue and (" · " .. cue.object .. " / " .. cue.name) or "")
        if key ~= lastDecision then
            lastDecision = key
            emit("decision", {reason = reason, cue = cue, states = character and states(character), detail = extra})
        end
    end
    local function earlier(due, distance, id, bestDue, nearest, best)
        return not best or due < bestDue or (due == bestDue
            and (distance < nearest or (distance == nearest and id > best.id)))
    end
    local function choose(root)
        table.clear(activeCues)
        local best, nearest, bestDue, rejected
        for object, entry in pairs(watched) do
            if object.Parent and entry.hum.Health > 0 and entry.root.Parent
                and ((entry.kind == "pve" and CFG.parryPve) or (entry.kind == "pvp" and CFG.parryPvp)) then
                local distance = (entry.root.Position - root.Position).Magnitude
                local active = object:GetAttribute("State_Attacking") == true or object:GetAttribute("State_SkillActive") == true
                    or object:GetAttribute("State_Using_Skill") == true
                if active and not entry.attacking then serial += 16; entry.stateSerial = serial end
                entry.attacking = active
                if active then activeCues[entry.stateSerial] = true end
                local any = false
                for track, cue in pairs(entry.tracks) do
                    if not track.IsPlaying then
                        emit("animation_end", {cue = cue.id, time = track.TimePosition}); entry.tracks[track] = nil
                    elseif cue.kind and (cue.hits or active or cue.kind == "spell") then
                        -- Marker-backed attacks do not need a replicated windup
                        -- flag. Unknown mob idle/spawn/reaction clips do.
                        activeCues[cue.id] = true
                        any = true
                        local limit = cue.kind == "spell" and CFG.parrySpellRange or CFG.parryRange
                        local selected, remaining, hit
                        if cue.hits then
                            for i, marker in ipairs(cue.hits) do
                                if i > 16 then break end
                                local id = cue.id + i - 1
                                activeCues[id] = true
                                local delta = track.Speed > 0 and (marker - track.TimePosition) / track.Speed
                                if not selected and delta and (delta >= -0.025 or (heldCue == id and delta >= -0.12))
                                    and (attemptedCues[id] ~= "parry" or heldCue == id) then
                                    selected, remaining, hit = id, delta, marker
                                end
                            end
                        else selected = cue.id end
                        if distance <= limit and selected then
                            -- A farther hit due now beats a nearer long windup.
                            local due = math.max(0, remaining or 0.1)
                            if earlier(due, distance, selected, bestDue, nearest, best) then
                                best = table.clone(cue); nearest, bestDue = distance, due
                                best.id = selected; best.animationCue = cue.id; best.hit = hit
                                best.time = track.TimePosition; best.speed = track.Speed; best.length = track.Length
                                best.remaining = remaining
                            end
                        elseif distance > limit and not rejected then rejected = cue end
                    end
                end
                if active and not any and distance <= CFG.parryRange
                    and earlier(0.1, distance, entry.stateSerial, bestDue, nearest, best) then
                    best = {id = entry.stateSerial, actor = entry.id, object = object:GetFullName(), scope = entry.kind,
                        name = "replicated attack state", kind = "state", first = os.clock()}; nearest, bestDue = distance, 0.1
                end
                if best and best.actor == entry.id then
                    best.distance = distance; best.position = pos(entry.root.Position); best.self = pos(root.Position)
                    best.facing = pos(entry.root.CFrame.LookVector); best.selfFacing = pos(root.CFrame.LookVector)
                end
            end
        end
        -- At most the live watchers' tracks/states, not an ever-growing history.
        for id in pairs(attemptedCues) do if not activeCues[id] then attemptedCues[id] = nil end end
        return best, rejected
    end
    function api.step()
        if os.clock() < nextTick then return end
        nextTick = os.clock() + 1 / 120
        if not CFG.autoParry or not S.alive then if character then api.release("OFF") end; return end
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local root = char and rootOf(char)
        if not char or not hum or hum.Health <= 0 or not root or S.defenseTransition then
            if character then emit("paused", {reason = "character/death/transition"}); api.release("character/death/transition") end
            return
        end
        if character and character ~= char then api.release("character replaced") end
        if not character then startLocal(char, hum) end
        if not catalog then buildCatalog() end
        if os.clock() >= nextScan then
            if adapter and (adapter.source.Parent == nil or adapter.char ~= char) then endGuard("stale adapter"); adapter = nil end
            if not adapter then bind(char) end
            scan(root)
        end
        local cue, rejected = choose(root)
        if cue then lastCue = cue end
        if os.clock() >= nextSummary then
            nextSummary = os.clock() + 5
            local count = 0; for _ in pairs(watched) do count += 1 end
            emit("heartbeat", {actors = count, requests = api.requests, damageEvents = api.damage, dropped = dropped,
                decision = lastDecision, held = held == true, hp = hum.Health, cue = cue})
        end
        if not adapter then decide("native adapter unavailable", cue); return end
        if manual() then
            if held then held, heldCue = nil, nil; emit("manual_takeover", {cue = cue}) end
            decide("manual block owns input", cue); return
        end
        local sm = adapter.sm
        local gate = UIS:GetFocusedTextBox() and "text focus" or sm:IsIncapacitated() and "incapacitated"
            or sm:IsFlying() and "flying" or sm:IsDodging() and "dodging" or sm:IsUsingSkill() and "local skill active"
            or sm:HasAnyState("Stunned", "Occupied", "Attacking") and "native action lock"
        if gate then endGuard(gate); decide(gate, cue); return end
        if not cue then endGuard("no in-range candidate"); decide(rejected and "candidate out of range" or "watching for attacks", rejected); return end
        local parrying = sm:IsParrying()
        if held then
            if parrying then
                -- .26 baseline 8609.846 End Block -> 8610.074 Parrying ended:
                -- releasing input preserves the native window. Clear Blocking
                -- now, not a network round trip AFTER a successful parry.
                attemptedCues[heldCue] = "parry"
                endGuard("native parry acknowledged · release pulse")
                decide("native parry window · input released (not success)", cue); return
            end
            if not parrying and not sm:IsBlocking() and not sm:CanBlock() then
                endGuard("native readiness lost"); decide("native readiness lock", cue); return
            end
            local upgradeFallback = attemptedCues[heldCue] == "block" and not parrying and not sm:HasState("ParryCooldown")
            if upgradeFallback then attemptedCues[heldCue] = nil end
            if upgradeFallback or (heldCue ~= cue.id and not parrying and not sm:HasState("ParryCooldown"))
                -- CanParry is false while Blocking, even after cooldown ends.
                -- A spent parry must release even when fallback is enabled.
                or (not parrying and sm:HasState("ParryCooldown")
                    and (not CFG.parryFallback or attemptedCues[heldCue] == "parry")) then
                endGuard("new cue / parry window ended")
                decide("release before fresh parry", cue); return
            end
            if attemptedCues[heldCue] == "block" and os.clock() >= nextSend then
                if not send("Block Input", "held native guard refresh", cue) then endGuard("send error"); CFG.autoParry = false; return end
                nextSend = os.clock() + 0.1
            end
            decide(parrying and "native parry state (not success)" or "holding fallback guard", cue)
            return
        end
        if (not CFG.parryFallback or cue.hit) and attemptedCues[cue.id] then decide("cue already attempted · waiting for next attack", cue); return end
        if cue.hit then
            if cue.remaining and cue.remaining < -0.025 then decide("hit window already passed", cue); return end
            -- Default lead100ms covers the observed ~243ms parry state. Add
            -- bounded native ping, not animation Length or guessed weapon speed.
            local okPing, ping = pcall(function() return LocalPlayer:GetNetworkPing() end)
            local lead = 0.1 + (okPing and type(ping) == "number" and math.clamp(ping, 0, 0.06) or 0)
            if cue.remaining and cue.remaining > lead then
                decide("waiting for native hit window", cue, {remaining = cue.remaining, lead = lead}); return
            end
        end
        if os.clock() < nextSend then decide("input spacing", cue); return end
        local canParry, canBlock = sm:CanParry() == true, sm:CanBlock() == true
        if not canParry and not (CFG.parryFallback and canBlock) then
            decide("native readiness lock", cue, {canParry = canParry, canBlock = canBlock}); return
        end
        if send("Block Input", canParry and "candidate onset parry attempt" or "cooldown block fallback", cue) then
            held, heldCue = true, cue.id
            attemptedCues[cue.id] = canParry and "parry" or "block"
            nextSend = os.clock() + 0.1
            decide(canParry and "parry requested (unconfirmed)" or "block fallback requested", cue)
        else CFG.autoParry = false end
    end
    function api.sync()
        if not CFG.autoParry then api.release("toggle OFF") end
    end
    return api
end)()
-- Passive near-NPC animation/state correlation. Never invokes combat callbacks.
local DefenseCapture = (function()
    local api, owned, nextScan = {}, {}, 0
    local function release(object)
        local entry = owned[object]
        if entry then for _, conn in ipairs(entry.conns) do conn:Disconnect() end; owned[object] = nil end
    end
    function api.release()
        local remove = {}; for object in pairs(owned) do remove[#remove + 1] = object end
        for _, object in ipairs(remove) do release(object) end
    end
    local function sample(entry, phase, track)
        if not CFG.record or not S.alive or S.defenseTransition then return end
        -- Admission precedes object/track reads and vector formatting. Do not
        -- mark rejected samples as seen; a later admitted sample may record it.
        if not admitted("ThreatAnim") then droppedEvents += 1; return end
        local char = LocalPlayer.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not root or not hum or hum.Health <= 0 or not entry.object.Parent or not entry.root.Parent then return end
        local distance = (entry.root.Position - root.Position).Magnitude
        if distance > 120 then return end
        local animation = track.Animation
        local id = animation and animation.AnimationId or "unknown"
        local previous = entry.samples[track]
        local position, npc, facing = root.Position, entry.root.Position, entry.root.CFrame.LookVector
        if phase == "sample" and previous and previous.id == id and previous.time == track.TimePosition
            and previous.speed == track.Speed and previous.length == track.Length
            and previous.position == position and previous.npc == npc and previous.facing == facing then return end
        entry.samples[track] = {id = id, time = track.TimePosition, speed = track.Speed, length = track.Length,
            position = position, npc = npc, facing = facing}
        observe("ThreatAnim", phase, entry.object, id,
            ("t=%.3f speed=%.3f len=%.3f"):format(track.TimePosition, track.Speed, track.Length),
            distance, "self=" .. tostring(root.Position), "npc=" .. tostring(entry.root.Position),
            "facing=" .. tostring(entry.root.CFrame.LookVector))
    end
    local function add(object, hum, root, animator)
        local entry = {object = object, root = root, hum = hum, animator = animator, conns = {}, tracks = {}, samples = {}}
        owned[object] = entry
        local function started(track, phase)
            if not CFG.record or not S.alive or owned[object] ~= entry then return end
            local count = 0
            for previous in pairs(entry.tracks) do
                if not previous.IsPlaying then
                    sample(entry, "stop", previous); entry.tracks[previous] = nil; entry.samples[previous] = nil
                else count += 1 end
            end
            if count >= 16 and not entry.tracks[track] then droppedEvents += 1; return end
            entry.tracks[track] = true; sample(entry, phase, track)
        end
        entry.conns[#entry.conns + 1] = animator.AnimationPlayed:Connect(function(track) started(track, "start") end)
        entry.conns[#entry.conns + 1] = object.AttributeChanged:Connect(function(name)
            if not CFG.record or not S.alive or owned[object] ~= entry then return end
            if name == "State_Attacking" or name == "State_Swinging" or name == "State_Using_Skill"
                or name == "State_Parrying" or name == "State_Stunned" then
                observe("ThreatState", object, name, object:GetAttribute(name), "npc=" .. tostring(root.Position))
            end
        end)
        -- Already-playing tracks are not labelled as attack starts.
        for i, track in ipairs(animator:GetPlayingAnimationTracks()) do
            if i > 16 then break end
            started(track, "present")
        end
    end
    function api.step()
        local char = LocalPlayer.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not CFG.record or not root or not hum or hum.Health <= 0 or S.defenseTransition then api.release(); return end
        local now = os.clock()
        if now >= nextScan then
            nextScan = now + 1
            local folder = workspace:FindFirstChild("FightableNPCS")
            local rows = {}
            if folder then
                for i, object in ipairs(folder:GetChildren()) do
                    if i > 512 then break end
                    local npcHum = object:IsA("Model") and object:FindFirstChildOfClass("Humanoid")
                    local npcRoot = npcHum and rootOf(object)
                    local animator = npcHum and npcHum:FindFirstChildOfClass("Animator")
                    if npcRoot and animator and npcHum.Health > 0 then
                        local distance = (npcRoot.Position - root.Position).Magnitude
                        if distance <= 120 then rows[#rows + 1] = {object, npcHum, npcRoot, animator, distance} end
                    end
                end
            end
            table.sort(rows, function(a, b) return a[5] < b[5] end)
            local keep = {}
            for i = 1, math.min(12, #rows) do
                local row = rows[i]; keep[row[1]] = true
                local entry = owned[row[1]]
                if entry and (entry.root ~= row[3] or entry.animator ~= row[4]) then release(row[1]); entry = nil end
                if not entry then add(row[1], row[2], row[3], row[4]) end
            end
            local remove = {}; for object in pairs(owned) do if not keep[object] then remove[#remove + 1] = object end end
            for _, object in ipairs(remove) do release(object) end
        end
        for _, entry in pairs(owned) do
            local count = 0
            for track in pairs(entry.tracks) do
                count += 1
                if not track.IsPlaying then
                    sample(entry, "stop", track); entry.tracks[track] = nil; entry.samples[track] = nil
                elseif count <= 16 then sample(entry, "sample", track) end
            end
        end
    end
    return api
end)()
local observerConns, observedCharacter = {}, nil
local function bindHealthObserver()
    local char = LocalPlayer.Character
    if char == observedCharacter then return end
    for _, c in ipairs(observerConns) do c:Disconnect() end
    table.clear(observerConns); observedCharacter = char
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then
        local last = hum.Health
        observerConns[#observerConns + 1] = hum.HealthChanged:Connect(function(hp)
            observe("Health", last, hp); last = hp
        end)
        observerConns[#observerConns + 1] = char.AttributeChanged:Connect(function(name)
            if name:sub(1, 6) == "State_" then observe("LocalState", name, char:GetAttribute(name)) end
        end)
    else observedCharacter = nil end
end
local function bindEvents()
    local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
    local client = remotes and remotes:FindFirstChild("Client")
    for _, spec in ipairs({ {client, "NPCVFX"}, {client, "ClientVFX"}, {client, "DamageIndicator"},
        {remotes, "Combat"}, {remotes, "Sword"}, {remotes, "Burn"}, {remotes, "Freeze"} }) do
        local remote = spec[1] and spec[1]:FindFirstChild(spec[2])
        if remote and remote:IsA("RemoteEvent") then
            local name = spec[2]
            connect(remote.OnClientEvent, function(...) observe(name, ...) end)
        end
    end
end
local function vitals()
    local c = LocalPlayer.Character
    local h = c and c:FindFirstChildOfClass("Humanoid")
    local states = c and c:FindFirstChild("States")
    local energy = states and states:FindFirstChild("Energy")
    local maxEnergy = states and states:FindFirstChild("MaxEnergy")
    return ("HP %s/%s · Energy %s/%s"):format(h and math.floor(h.Health) or "?", h and math.floor(h.MaxHealth) or "?",
        energy and tostring(energy.Value) or "?", maxEnergy and tostring(maxEnergy.Value) or "?")
end
local function defenseState()
    local c = LocalPlayer.Character
    if not c then return "Waiting for character" end
    local out = {}
    for _, key in ipairs({"DashCooldown", "ParryCooldown", "Dodging", "Parrying", "Blocking", "Stunned", "StatusFire"}) do
        if c:GetAttribute("State_" .. key) == true then out[#out + 1] = key end
    end
    return #out > 0 and table.concat(out, " · ") or "No observed defense locks"
end
-- Native Items supplies shared attributes + parent-first Required (W0647).
-- No heap scan, GUI sort, native filter edit or new network observer is needed.
Armor = (function()
    local api = {conns = {}, items = {}, level = "?", status = "OFF"}
    local nativeItems, attempted = nil, false
    local inventory, folder, character
    local function disconnect(list)
        for _, c in ipairs(list) do c:Disconnect() end
        table.clear(list)
    end
    local function watch(sig, callback, list)
        list[#list + 1] = sig:Connect(callback)
    end
    local function getItems()
        if attempted then return nativeItems end
        attempted = true
        local modules = game:GetService("ReplicatedStorage"):FindFirstChild("Modules")
        local module = modules and modules:FindFirstChild("Items")
        if not module or not module:IsA("ModuleScript") then return nil end
        local ok, value = pcall(require, module)
        if not ok or type(value) ~= "table" or type(value.AllItems) ~= "table"
            or getmetatable(value.AllItems) ~= nil or type(value.LookupItem) ~= "function" then return nil end
        local sourceOK, source = pcall(debug.info, value.LookupItem, "s")
        if not sourceOK or type(source) ~= "string" or not source:match("Modules%.Items$") then return nil end
        nativeItems = value
        return value
    end
    -- Approved one-request proof: logs/armor_unheld_proof.log, exact target
    -- became EquippedFace without holding it. Native wrappers only; no bytes.
    local native
    local function named(fn, source, name)
        if type(fn) ~= "function" then return false end
        local ok, s, n = pcall(debug.info, fn, "sn")
        return ok and s == source and n == name
    end
    local function resolveNative(items)
        if native then return end
        local modules = game:GetService("ReplicatedStorage"):FindFirstChild("Modules")
        local packetModule = modules and modules:FindFirstChild("Packets")
        local stateModule = modules and modules:FindFirstChild("StateManager")
        if not packetModule or not stateModule or type(getfenv) ~= "function" then return end
        local ok, result = pcall(function()
            local packets, states = require(packetModule), require(stateModule)
            local equip = packets.Inventory.packets.Equip
            local get = states.get -- cached read only; never creates a manager
            if not named(equip.send, "ReplicatedStorage.Modules.ByteNetMax.packets.packet", "send")
                or not named(get, "ReplicatedStorage.Modules.StateManager", "get") then return nil end
            local globals = getfenv(items.LookupItem)._G
            if type(globals) ~= "table" or getmetatable(globals) ~= nil then return nil end
            return {equip = equip, send = equip.send, states = states, get = get, globals = globals}
        end)
        if ok then native = result end
    end
    local adapter = {proven = true} -- native unheld path proved, not a UI override
    function adapter.owned(row)
        return inventory and row.item.Parent == inventory and row.item.Name == row.name
    end
    function adapter.equipped(slot)
        return folder and folder:GetAttribute("Equipped" .. slot)
    end
    function adapter.safe()
        if game.GameId ~= 3164482049 or (game.PlaceId ~= 8248288152 and game.PlaceId ~= 8248164019) then
            return "Paused: wrong game"
        end
        local hum = character and character:FindFirstChildOfClass("Humanoid")
        if LocalPlayer.Character ~= character or not hum or hum.Health <= 0 or S.defenseTransition then
            return "Paused: character transition"
        end
        if character:GetAttribute("InCombat") == true or LocalPlayer:GetAttribute("InCombat") == true
            or (folder and folder:GetAttribute("InCombat") == true) then return "Waiting: combat" end
        for _, object in ipairs({character, LocalPlayer, folder}) do
            local timer = object:GetAttribute("CombatTimer")
            if Core.armorNumber(timer) and timer > 0 then return "Waiting: combat" end
        end
        if character:FindFirstChildOfClass("Tool") then return "Waiting: item in use" end
        if not native or native.equip.send ~= native.send or native.states.get ~= native.get
            or not named(native.send, "ReplicatedStorage.Modules.ByteNetMax.packets.packet", "send")
            or not named(native.get, "ReplicatedStorage.Modules.StateManager", "get") then
            return "Paused: native equip adapter unavailable"
        end
        local ok, reason = pcall(function()
            local sm = native.get(character)
            if not sm or sm.Model ~= character
                or not named(sm.IsIncapacitated, "ReplicatedStorage.Modules.StateManager", "IsIncapacitated")
                or not named(sm.IsUsingSkill, "ReplicatedStorage.Modules.StateManager", "IsUsingSkill")
                or not named(sm.HasAnyState, "ReplicatedStorage.Modules.StateManager", "HasAnyState") then
                return "Paused: native state adapter unavailable"
            end
            if LocalPlayer:HasTag("ProcessingInventory") then return "Waiting: inventory processing" end
            if sm:IsIncapacitated() then return "Waiting: incapacitated" end
            if sm:IsUsingSkill() or sm:HasAnyState("Attacking", "Swinging", "Using Skill", "CombatDebounce")
                or not rawget(native.globals, "Use") then return "Waiting: item in use" end
            return nil
        end)
        if not ok then return "Paused: native equip gate error" end
        return reason
    end
    function adapter.send(item)
        assert(native and item.Parent == inventory, "armor ownership changed")
        native.send({Item = item})
    end
    local rankBudget = 0
    function adapter.checkpoint()
        if os.clock() - rankBudget >= 0.002 then task.wait(); rankBudget = os.clock() end
    end
    function adapter.snapshot()
        local items = getItems()
        if not items then return nil, "native Items adapter unavailable" end
        resolveNative(items)
        if not inventory or not folder then return nil, "inventory/data unavailable" end
        local generation, bound = api.queue.generation, character
        local snapshot = {rows = {}, attributes = folder:GetAttributes(), equipped = {}}
        api.level = snapshot.attributes.Level or "?"
        for _, slot in ipairs(Core.armorSlots) do snapshot.equipped[slot] = adapter.equipped(slot) end
        local budget = os.clock()
        for _, item in ipairs(inventory:GetChildren()) do
            local base = item.Name:match("^[^_]+")
            local definition = base and rawget(items.AllItems, base)
            -- Copy data: a yielding batch never keeps mutable native metadata.
            if type(definition) == "table" and getmetatable(definition) == nil then
                definition = table.clone(definition)
                if type(definition.Required) == "table" and getmetatable(definition.Required) == nil then
                    definition.Required = table.clone(definition.Required)
                end
            end
            local stock = item:GetAttribute("Stock")
            snapshot.rows[#snapshot.rows + 1] = {item = item, name = item.Name, definition = definition,
                stats = item:GetAttribute("Stats"), quality = item:GetAttribute("Quality"),
                stock = stock == nil and 1 or stock, owned = item.Parent == inventory}
            if os.clock() - budget >= 0.002 then
                task.wait(); budget = os.clock()
                if not S.alive or not CFG.autoArmor or generation ~= api.queue.generation
                    or LocalPlayer.Character ~= bound then return nil, "cancelled" end
            end
        end
        rankBudget = os.clock()
        return snapshot
    end
    api.queue = Core.armorQueue(adapter)
    function api.markDirty()
        if CFG.autoArmor and api.queue.enabled then api.queue.markDirty(os.clock()) end
    end
    local function addItem(item)
        if api.items[item] then return end
        local list = {}; api.items[item] = list
        watch(item.AttributeChanged, api.markDirty, list)
        watch(item:GetPropertyChangedSignal("Name"), api.markDirty, list)
        watch(item.AncestryChanged, api.markDirty, list)
    end
    function api.stop(reason)
        api.queue.stop(reason); api.status = api.queue.status
        disconnect(api.conns)
        for _, list in pairs(api.items) do disconnect(list) end
        table.clear(api.items)
        inventory = nil; folder = nil; character = nil; native = nil
    end
    function api.bind()
        api.stop()
        if not CFG.autoArmor then return end
        character = LocalPlayer.Character
        inventory = LocalPlayer:FindFirstChild("Inventory")
        folder = LocalPlayer:FindFirstChild("PlayerFolder")
        api.queue.enable(os.clock()); api.status = api.queue.status
        if not inventory or not folder then
            api.queue.pause("inventory/data unavailable; toggle OFF then ON")
            api.status = api.queue.status; return
        end
        for _, item in ipairs(inventory:GetChildren()) do addItem(item) end
        watch(inventory.ChildAdded, function(item) addItem(item); api.markDirty() end, api.conns)
        watch(inventory.ChildRemoved, function(item)
            if api.items[item] then disconnect(api.items[item]); api.items[item] = nil end
            api.markDirty()
        end, api.conns)
        watch(folder.AttributeChanged, api.markDirty, api.conns)
        watch(LocalPlayer.ChildAdded, api.markDirty, api.conns)
        watch(LocalPlayer.ChildRemoved, api.markDirty, api.conns)
        watch(inventory.AncestryChanged, api.markDirty, api.conns)
        watch(folder.AncestryChanged, api.markDirty, api.conns)
    end
    function api.step()
        if not CFG.autoArmor then if api.queue.enabled then api.stop() end; return end
        local hum = character and character:FindFirstChildOfClass("Humanoid")
        if api.queue.enabled and (LocalPlayer.Character ~= character or not hum or hum.Health <= 0
            or S.defenseTransition or inventory.Parent ~= LocalPlayer or folder.Parent ~= LocalPlayer) then
            api.stop("Paused: character/data changed; toggle OFF then ON"); return
        end
        api.queue.step(os.clock()); api.status = api.queue.status
    end
    return api
end)()
local function panic()
    CFG.esp = false; CFG.fullbright = false; CFG.movement = false; CFG.record = false
    CFG.autoArmor = false; Armor.stop()
    CFG.revealMap = false; QuestAssist.cancel()
    CFG.autoMine = false; CFG.autoHarvest = false; CFG.autoStart = false; CFG.broomSpeed = false; CFG.broomDelay = false
    CFG.autoLoot = false; lootSession = nil; lootArmed = false; S.broomRequest = false
    CFG.climb = false; Climb.release(); Climb.blocked = nil
    CFG.dash = false; Dash.release(); Dash.blocked = nil
    CFG.noFall = false; CFG.chainSlide = false; CFG.combatMove = false; CFG.broomBoost = false
    -- Instance writes must stay off signal threads; the lease worker applies
    -- panic within 0.05s. Table/upvalue wrappers also consult CFG immediately.
    CFG.autoParry = false; CFG.broomAltitude = false
    TownTravel.cancel(); AutoParry.release("panic OFF"); BroomFlex.release(); DefenseCapture.release()
    requestApply(); saveConfig(); Log.info("panic OFF")
end
local function destroy()
    if not S.alive then return end
    if saveTask then pcall(task.cancel, saveTask); saveTask = nil end
    saveConfig(); flushEvents(); S.alive = false
    for _, c in ipairs(S.conns) do pcall(function() c:Disconnect() end) end
    for _, c in ipairs(observerConns) do pcall(function() c:Disconnect() end) end
    clearMarkers(); releaseEnvironment(); releaseMovement(); releaseMaterials(); releaseBroom(); Climb.release(); Dash.release()
    TownTravel.cancel(); NativeCursor.release(); DefenseCapture.release(); AutoParry.release("unload"); BroomFlex.release()
    Advanced.release(); Armor.stop(); QuestAssist.cancel()
    if Shell then Shell.destroy() end
    if layer then layer:Destroy() end
    if G[GKEY] == S then G[GKEY] = nil end
    Log.info("unloaded: owned state restored")
end
S.destroy = destroy
S.panic = panic
S.setAutoParry = function(enabled)
    CFG.autoParry = enabled == true
    AutoParry.sync(); scheduleSave()
    return AutoParry.status
end
S.setAutoArmor = function(enabled)
    CFG.autoArmor = enabled == true
    Armor.bind(); scheduleSave()
    return Armor.status
end
S.snapshot = function() return { build = BUILD_VERSION, shown = S.shown, discovered = S.discovered, vitals = vitals(),
    defense = defenseState(), latest = S.latest, events = S.events, movement = S.movementStatus,
    materials = materialStatus, broom = broomStatus, climb = Climb.status, dash = Dash.status, loot = lootStatus,
    hymn = QuestAssist.status, map = QuestAssist.mapStatus, travel = TownTravel.status,
    autoParry = AutoParry.status, parryEnabled = CFG.autoParry, parryRequests = AutoParry.requests,
    parryDamageEvents = AutoParry.damage, broomAltitude = BroomFlex.altitude, broomCooldown = BroomFlex.cooldown,
    armor = Armor.status, armorRebuilds = Armor.queue.rebuilds, armorSends = Armor.queue.sent,
    noFall = Advanced.noFall, chainSlide = Advanced.chainSlide, combatMove = Advanced.combatMove, broomBoost = Advanced.broomBoost } end
G[GKEY] = S
local function boot()
    loadConfig()
    local coreGui = game:GetService("CoreGui")
    if type(cloneref) == "function" then coreGui = cloneref(coreGui) end
    layer = Instance.new("Folder"); layer.Name = "CloverAwareness"; layer.Parent = coreGui
    local Kit = HOST.ui
    assert(Kit.SHELL_CONTRACT == "1", "R3ST shell contract mismatch")
    Shell = Kit.moduleShell({ id = "clover-rpg", title = "Clover RPG", version = BUILD_VERSION,
        subtitle = "World awareness · local vision · evidence-backed tools", gameId = 3164482049,
        placeId = 8248288152, tabs = {"Awareness", "Vision", "Movement", "Materials", "Teleports", "Quest assistance", "Equipment", "Defense", "Settings"},
        keep = {layer}, cfg = CFG, save = scheduleSave, live = S.live, conns = S.conns,
        onUnload = requestUnload, onSettings = function() Shell.show("Settings") end })
    local W = Shell.W
    local p = Shell.page("Awareness")
    W.section(p, "World ESP")
    W.toggle(p, {label = "ESP", key = "esp", set = requestApply})
    for _, spec in ipairs({{"enemies", "Combat NPCs"}, {"indicators", "Boss / elite indicators"},
        {"players", "Other players"}, {"npcs", "Dialogue / quest NPCs"}, {"ores", "Ore nodes"},
        {"crops", "Crop nodes"}, {"wood", "Wood piles (buy)"}, {"waypoints", "Waypoints"}, {"chams", "Through-wall outlines"}}) do
        W.toggle(p, {label = spec[2], key = spec[1], set = requestApply})
    end
    W.slider(p, {label = "Range (studs)", key = "range", min = 150, max = 9000, step = 50, set = requestApply})
    W.toggle(p, {label = "Mob / player health bars", key = "healthBars", set = requestApply})
    W.slider(p, {label = "Health bar distance", key = "healthRange", min = 50, max = 3000, step = 50, set = requestApply})
    W.slider(p, {label = "Marker budget", key = "limit", min = 8, max = 64, step = 1, set = requestApply})
    local searchRow = W.row(p, 36)
    W.search(searchRow, {placeholder = "Filter names (literal text)", text = CFG.filter,
        changed = function(text) CFG.filter = tostring(text):sub(1, 64); scheduleSave() end})
    W.statusRow(p, function() return ("%d markers · %d discovered%s"):format(S.shown, S.discovered, S.overflow and " · discovery cap reached" or "") end)
    W.note(p, "Streamed objects only. NPCs may be neutral; indicator tag does not prove boss status. Chest spawn points are not live loot.")
    p = Shell.page("Teleports")
    W.section(p, "Towns · approximate progression order")
    W.note(p, "Uses the game's server-controlled waypoint travel, not forced coordinate jumps. No exact town level requirements were found; the order below is a rough guide, not a level gate.")
    W.button(p, "Refresh waypoint unlocks", "One native GetData request; nothing happens automatically", function() TownTravel.request() end)
    W.statusRow(p, function() return TownTravel.status end)
    for _, town in ipairs(TownTravel.towns) do
        local destination = town
        W.section(p, destination.tier)
        W.button(p, "Travel to " .. destination.name, "Native waypoint request · must be unlocked", function() TownTravel.request(destination.id) end)
        W.statusRow(p, function() return destination.name .. " · " .. TownTravel.label(destination.id) end)
    end
    W.note(p, "Refresh unlocks, then request native travel from your current position. Server unlock/quest/combat rules still decide acceptance; there are no forced coordinate jumps or automatic retries. Swamp is the fourth native travel destination, not a town.")
    p = Shell.page("Quest assistance")
    W.section(p, "Quest map")
    W.toggle(p, {label = "Full map + quest givers", key = "revealMap", set = requestApply,
        desc = "Display-only reveal on the normal map key; keeps real exploration untouched"})
    W.statusRow(p, function() return QuestAssist.mapStatus end)
    W.note(p, "Shows known native quest-giver markers beyond explored regions. Yellow = one-time, cyan = repeatable, grey = in progress. Unstreamed NPCs may be missing; this does not accept or complete quests.")
    W.section(p, "Ancient hymn · Church")
    W.button(p, "Solve ancient hymn", "Open the book nearby first; arrange the six symbols and submit once", QuestAssist.request)
    W.statusRow(p, function() return QuestAssist.status end)
    W.note(p, "Poem order: Earth, Wind, Light, Flame, Shadow, Water. Requires the open hymn within 15 studs. Completion is reported only after the native server confirmation.")
    p = Shell.page("Vision")
    W.section(p, "Adaptive fullbright")
    W.toggle(p, {label = "Fullbright", key = "fullbright", set = requestApply,
        desc = "Daylight, fog removal, neutral colors and clear postprocessing"})
    W.slider(p, {label = "Brightness", key = "brightness", min = 1, max = 4, step = 0.1, set = requestApply})
    W.slider(p, {label = "Exposure", key = "exposure", min = -1, max = 1, step = 0.1, set = requestApply})
    W.note(p, "Keeps combat warning effects. New weather/camera effects are handled; OFF restores owned fields to the last observed game values.")
    p = Shell.page("Movement")
    W.section(p, "Native client prediction")
    W.toggle(p, {label = "Local swiftness", key = "movement", set = requestApply,
        desc = "Native potion consumer; 225s window, not proven server movement"})
    W.slider(p, {label = "Swiftness bonus", key = "speed", min = 0, max = 4.5, step = 0.5,
        set = requestApply})
    W.statusRow(p, function() return S.movementStatus end)
    W.note(p, "Uses the highest cited base potion tier. Respects native movement locks and yields on game updates.")
    W.toggle(p, {label = "No climb cooldown (native airborne latch)", key = "climb", set = requestApply,
        hint = "Manual input only. Keeps native state, wall/ledge checks and timers. Server motion acceptance unverified."})
    W.statusRow(p, function() return Climb.status end)
    W.toggle(p, {label = "Chain dashes (no local post-dash wait)", key = "dash", set = requestApply,
        hint = "Manual dash key only. Repeats as soon as native motion ends, without waiting for DashCooldown/Dodging. Keeps combat locks; server cooldown and i-frames are not bypassed."})
    W.statusRow(p, function() return Dash.status end)
    W.section(p, "Dump-backed advanced movement")
    W.toggle(p, {label = "No fall damage (local report)", key = "noFall", set = requestApply,
        hint = "Maintains the native DisableFallDamage flag. Server damage protection is unverified."})
    W.statusRow(p, function() return Advanced.noFall end)
    W.toggle(p, {label = "Chain slide (no local cooldown)", key = "chainSlide", set = requestApply,
        hint = "Manual slide only. Keeps sprint, ground, active-slide and native eligibility checks."})
    W.statusRow(p, function() return Advanced.chainSlide end)
    W.toggle(p, {label = "No combat slowdown (M1 / abilities / guard)", key = "combatMove", set = requestApply,
        hint = "Keeps native walk/sprint pace during self-actions and removes guard/soft penalties. Real incapacitation, frozen, block-broken and normal flight/crouch/swim stay native. Server acceptance unverified."})
    W.statusRow(p, function() return Advanced.combatMove end)
    W.note(p, "Dump-only adapters: no live session was available. An unknown or changed native shape makes no change; inspect the status row. OFF restores only owned fields.")
    W.section(p, "Native broom controls")
    W.toggle(p, {label = "Broom speed boost", key = "broomBoost", set = requestApply,
        hint = "Extra native base-speed bonus. OFF restores the native profession bonus; steering and flight gates stay native."})
    W.slider(p, {label = "Extra base flight speed (%)", key = "broomBonus", min = 0, max = 200, step = 5, set = requestApply})
    W.statusRow(p, function() return Advanced.broomBoost end)
    W.toggle(p, {label = "Broom Tailwind speed (+15%)", key = "broomSpeed", set = requestApply,
        desc = "Uses the native speed consumer; no click teleport or CFrame jumps"})
    W.toggle(p, {label = "No local broom cooldown (normal key / F7)", key = "broomDelay", set = function() BroomFlex.apply(); requestApply() end,
        desc = "Saved choice. Native manual mount/dismount; removes 1s input debounce, not server locks."})
    W.statusRow(p, function() return broomStatus end)
    W.statusRow(p, function() return BroomFlex.cooldown end)
    W.toggle(p, {label = "Lift broom altitude ceiling (client)", key = "broomAltitude", set = function() BroomFlex.apply(); requestApply() end,
        hint = "Removes the practical local ascent/ceiling pull-down limit. No-fly zones, water, combat and server checks remain."})
    W.statusRow(p, function() return BroomFlex.altitude end)
    W.note(p, "Speed bonus stacks with Tailwind; +100% adds one base-speed unit. Altitude uses a finite high native cap, not a new flight motor. OFF restores the latest owned profession value. No no-fly/combat bypass or direct velocity writes; server acceptance is unverified.")
    p = Shell.page("Materials")
    W.section(p, "Native material minigames")
    W.toggle(p, {label = "Auto mine critical timing", key = "autoMine", set = requestApply,
        desc = "Starts ready Mining challenges and presses native critical timing"})
    W.toggle(p, {label = "Auto harvest ring steering", key = "autoHarvest", set = requestApply,
        desc = "Exclusive ring aim while active; mouse cannot override; native turn limits and cancel stay intact"})
    W.toggle(p, {label = "Auto start nearby nodes", key = "autoStart", set = requestApply,
        desc = "Native prompt holds only, within prompt range and line of sight"})
    W.statusRow(p, function() return materialStatus end)
    W.statusRow(p, function() return ("Saved choices: Mine %s · Harvest %s · Auto start %s"):format(
        CFG.autoMine and "ON" or "OFF", CFG.autoHarvest and "ON" or "OFF", CFG.autoStart and "ON" or "OFF") end)
    W.note(p, "Your saved material choices resume on load by request. F8 stops them. No teleport, tool bypass, timestamp spoof, instant rings, crafting spend or reward spoof. Keep the required tool equipped. Server outcomes need live proof.")
    W.section(p, "Opened chest collection")
    W.toggle(p, {label = "Auto take opened chest loot", key = "autoLoot", set = requestApply,
        desc = "Saved choice. Waits for a freshly opened chest and native Collect All timer; skips named/player loot."})
    W.toggle(p, {label = "Use individual-item actions", key = "lootItems", set = requestApply,
        desc = "Uses native item actions instead of Collect All; does not wait on its timer. Server checks remain."})
    W.statusRow(p, function() return lootStatus end)
    W.note(p, "Default sends one Collect All request immediately. Item mode is bounded to64 items/open and4 calls/0.1s. No cooldown or reward bypass is promised. Open the chest after enabling.")
    p = Shell.page("Equipment")
    W.section(p, "Owned armor")
    W.toggle(p, {label = "Auto Equip Best Armor", key = "autoArmor", set = function() S.setAutoArmor(CFG.autoArmor) end,
        hint = "Saved choice. Equips owned usable upgrades while idle; one request at a time, six per run."})
    W.statusRow(p, function() return Armor.status .. " · Method: native Best • owned armor • level " .. tostring(Armor.level) end)
    W.note(p, "Scores actual rolls, screens current requirements and keeps ties. Native Best, not build-aware damage optimization. Waits during combat, held tools, skills or inventory use. No weapons/vanity/tool changes; no retries. OFF stops future requests without reversing gear.")
    p = Shell.page("Defense")
    W.section(p, "Observed combat state")
    W.statusRow(p, vitals); W.statusRow(p, defenseState)
    W.section(p, "Reactive auto-parry / guard · experimental")
    W.toggle(p, {label = "Auto parry (saved choice)", key = "autoParry", set = function() S.setAutoParry(CFG.autoParry) end,
        hint = "PvE/PvP attack animation/state cues. Normal native guard only; no cooldown/stun bypass or perfect protection claim."})
    W.toggle(p, {label = "PvE threats", key = "parryPve", set = requestApply})
    W.toggle(p, {label = "PvP threats", key = "parryPvp", set = requestApply})
    W.toggle(p, {label = "Hold normal block if parry unavailable", key = "parryFallback", set = requestApply})
    W.slider(p, {label = "Melee / NPC range", key = "parryRange", min = 8, max = 60, step = 1, set = requestApply})
    W.slider(p, {label = "Skill / magic cue range", key = "parrySpellRange", min = 20, max = 150, step = 5, set = requestApply})
    W.statusRow(p, function() return AutoParry.status end)
    W.statusRow(p, function() return tostring(AutoParry.requests) .. " guard requests · " .. tostring(AutoParry.damage) .. " HP-loss events" end)
    W.note(p, "Captured player/mob HitWindow profiles use playback speed and bounded latency lead. One pulse per hit; input releases as native Parrying starts so successful parries can chain. Replayed clips and multi-hit markers get fresh attempts. Unknown active attacks remain uncalibrated. Respects manual block, focus, death, native skill/stun/cooldown locks. Grabs, AoE, projectiles and unstreamed threats may get through. Does not auto-turn or attack. Native Parrying/FX is not proven success.")
    W.note(p, "Enhanced JSONL diagnostics are automatic while enabled: candidates/playback, decisions, native requests/states/FX and HP changes. Bounded per-session files: logs/clover_parry_*.jsonl; pointer: clover_parry_latest.json. Play normally for useful combat evidence.")
    W.note(p, "Recording also captures nearby combat NPC animation IDs, playback timing, positions/facing and state changes (120 studs, nearest 12). These are observations, not proven incoming attacks; drops and build sessions are labelled.")
    W.toggle(p, {label = "Record passive PvE evidence", key = "record", set = requestApply,
        desc = "Incoming effects + local state/HP. No attacks, block requests or dodges."})
    W.statusRow(p, function() return tostring(S.events) .. " recorded · " .. S.latest end)
    W.note(p, "Play normally to gather evidence. File: logs/clover_defense_observer.log. Remote FX can arrive after impact; records are observations, not threat predictions.")
    p = Shell.page("Settings")
    W.section(p, "Safety and lifecycle")
    W.note(p, "F8: turn all master features OFF and save. End: unload and restore owned state. RightShift: Hub visibility. Settings save automatically.")
    W.button(p, "Panic OFF", "Disable awareness, vision, movement and recording", panic, true)
    W.button(p, "Unload", "Restore owned changes and remove this module", requestUnload, true)
    connect(UIS.InputBegan, function(input, handled)
        if handled or UIS:GetFocusedTextBox() then return end
        if input.KeyCode == Enum.KeyCode.F8 then panic()
        elseif input.KeyCode == Enum.KeyCode.F7 and CFG.broomDelay then S.broomRequest = true
        elseif input.KeyCode == Enum.KeyCode.End then requestUnload() end
    end)
    S.prompts = setmetatable({}, {__mode = "k"})
    local promptService = game:GetService("ProximityPromptService")
    connect(promptService.PromptShown, function(prompt)
        if prompt.Name == "MinePrompt" or prompt.Name == "HarvestPrompt" then S.prompts[prompt] = true end
    end)
    connect(promptService.PromptHidden, function(prompt) S.prompts[prompt] = nil end)
    local function characterLost()
        S.materialCharacterLost = true
        S.defenseTransition = LocalPlayer.Character
        TownTravel.cancel(); Dash.release(); DefenseCapture.release(); AutoParry.release("character transition"); BroomFlex.release()
        Armor.stop("Paused: character transition; toggle OFF then ON")
        lootSession = nil; lootArmed = false
        lootNote("Character transition · pending loot cancelled")
    end
    connect(LocalPlayer.CharacterRemoving, characterLost)
    connect(LocalPlayer.OnTeleport, characterLost)
    bindMaterialNatives(); bindLoot()
    if CFG.autoArmor then Armor.bind() end
    -- Frame timing is required for narrow critical arcs and native ring steering.
    connect(game:GetService("RunService").PreSimulation, function() guard("materials.frame", materialFrame) end)
    connect(game:GetService("RunService").PreSimulation, function() guard("broom.manual", manualBroom) end)
    connect(game:GetService("RunService").PreSimulation, function() guard("loot", lootFrame) end)
    connect(game:GetService("RunService").PreSimulation, function()
        if not guard("parry.frame", AutoParry.step) then CFG.autoParry = false; AutoParry.release("controller error") end
    end)
    bindEvents(); applyConfig(); Shell.ready()
    local resumed = {}
    for key, value in pairs(CFG) do resumed[#resumed + 1] = key .. "=" .. tostring(value) end
    table.sort(resumed)
    Log.info("BUILD " .. BUILD_VERSION .. " resumed: " .. table.concat(resumed, " "))
    task.spawn(function()
        while S.alive and G[GKEY] == S do
            guard("advanced movement", Advanced.step)
            if not S.alive or G[GKEY] ~= S then break end
            guard("broom local limits", BroomFlex.step)
            task.wait(0.05)
        end
    end)
    -- Challenge status/next and hymn submission are game closures (§9).
    -- Their thread must never become the CoreGui cursor/ESP worker.
    task.spawn(function()
        while S.alive and G[GKEY] == S do
            guard("quest assistance", QuestAssist.step)
            guard("materials.challenge", Challenge.step)
            task.wait(0.2)
        end
    end)
    task.spawn(function()
        local nextFlush = 0
        while S.alive and G[GKEY] == S do
            if S.unloadRequested then destroy(); break end
            if S.pendingApply then
                S.pendingApply = false; applyConfig()
                Log.info(("apply esp=%s fullbright=%s movement=%s broom=%s fastKey=%s mine=%s harvest=%s start=%s loot=%s itemMode=%s climb=%s record=%s"):format(
                    tostring(CFG.esp), tostring(CFG.fullbright), tostring(CFG.movement), tostring(CFG.broomSpeed), tostring(CFG.broomDelay),
                    tostring(CFG.autoMine), tostring(CFG.autoHarvest), tostring(CFG.autoStart), tostring(CFG.autoLoot), tostring(CFG.lootItems),
                    tostring(CFG.climb), tostring(CFG.record)))
            end
            guard("vision", fullbrightStep); guard("movement", movementStep)
            if S.defenseTransition and LocalPlayer.Character ~= S.defenseTransition then S.defenseTransition = nil end
            guard("broom", broomStep); guard("climb", Climb.step)
            -- Climb discovery yields. Never resume an old worker after unload.
            if not S.alive or G[GKEY] ~= S then break end
            guard("dash", Dash.step)
            guard("armor", Armor.step)
            if not S.alive or G[GKEY] ~= S then break end
            guard("cursor", NativeCursor.step)
            if (CFG.autoMine or CFG.autoHarvest or CFG.autoStart) and os.clock() >= nextMaterialBind then
                nextMaterialBind = os.clock() + 2
                guard("materials.bind", bindMaterialNatives)
            end
            guard("materials.prompt", promptStep)
            guard("discovery", function() discoveryStep(os.clock()) end)
            guard("esp", espStep); guard("observer", bindHealthObserver)
            guard("defense.capture", DefenseCapture.step)
            guard("parry.flush", AutoParry.flush)
            -- Kit.moduleShell owns the visibility-gated live driver.
            if os.clock() >= nextFlush then
                nextFlush = os.clock() + 1; flushEvents()
                S.decisions = S.decisions or {}
                for feature, note in pairs({materials = materialStatus, broom = broomStatus,
                    movement = S.movementStatus, climb = Climb.status, dash = Dash.status, armor = Armor.status,
                    noFall = Advanced.noFall, chainSlide = Advanced.chainSlide,
                    combatMove = Advanced.combatMove, broomBoost = Advanced.broomBoost,
                    broomAltitude = BroomFlex.altitude, broomCooldown = BroomFlex.cooldown}) do
                    if S.decisions[feature] ~= note then
                        S.decisions[feature] = note; Log.info(feature .. " status: " .. note)
                    end
                end
            end
            task.wait(0.2)
        end
    end)
end
if not guard("boot", boot) then destroy() end
