--------------------------------------------------------------------------
-- Runaways Intel v3.0 -- R3ST Hub module (embedded) + intel + opt-in power
-- runaways-2026-09-02.22
--
-- Identity: universe 7585140258 FIRST, place 117311404196294 second, so the
-- module still arms inside a VIP / private server (hub skill S2a).
--
-- Draws with scripts/r3st_ui.lua and mounts into the hub's content host via
-- __R3ST_HOST. Standalone injection still works with the global absent.
-- Marker billboards stay in their own full-screen CoreGui layer and are never
-- reparented into the hub panel (hub S6.1 r8).
--
-- POSTURE (potassium-dev S5.6), against dump 2026-09-02T11-34-05Z:
--   anticheat_deep.txt: CLIENT INSPECTION=0, LOG MONITORING=0, ENFORCEMENT=7
--   (all Cmdr admin kick + Lyra DataStore kicks -- no cheat path), REPORTING=1
--   (FlowClient requires CoreGui.FlowSourcemap.AntiCheat, same as the
--   2026-08-20 dump: 0148:217 then, 0149:430 now -- unchanged, not new).
--   The only client movement limiter is AntiYeetClient 0150:53, which zeroes
--   HumanoidRootPart velocity above 300. Every speed control here stays under
--   it: WalkSpeed caps at 150, vehicle fly at 500 acts on the chassis, not the
--   HRP.
--   Rung 1 reads replicated instances. Rung 2 creates local UI, marker
--   billboards and sound-group writes. Rung 3 pins client-only properties the
--   game's own client code already writes (gasLevel, CameraMode, WalkSpeed).
--   Rung 5 writes owned-chassis physics -- resulting motion is server-visible.
--   Rung 6 is NPC aura / auto-smash only, and those call stock Tool:Activate;
--   0220-equivalent stock handler keeps 3-stud overlap, LOS, damage and rate.
--   The remote monitor observes existing namecalls; it never fires or edits one.
--
-- DUMP CITATIONS (2026-09-02T11-34-05Z, PlaceId 117311404196294):
--   loot value           scripts/0138.lua:75  Data.Loot.GetItemValue
--   tool rate            scripts/0142.lua:28  Data.Tools.GetToolConfig
--                        scripts/0144.lua     hitsPerSecond per weapon
--   velocity limiter     scripts/0150.lua:53  AntiYeetClient, >300 -> zero
--   camera first person  scripts/0153.lua:34  Camera.SetMode(bool)
--                        :78 re-forces first person on every character effect
--                        0185.lua:404,446,453 Spectate re-forces it too
--   walk / sprint speed  scripts/0160.lua:99  setSpeed tweens Humanoid.WalkSpeed
--                        walk 15, crouch 10, sprint 26*SprintMult, downed <=10
--   music groups         scripts/0193.lua     MuteMusic tweens SoundService
--                        .Music and .PhysicalMusic Volume between 0 and 1
--                        trees/SoundService.txt:2,4 -- both are SoundGroups
--   escape route         scripts/0187.lua     Gui.DistanceToBorderClient
--   vehicle attributes   attributes_catalog.txt -- GasCapacity, TopSpeedMPH,
--                        FullTankRange, BrakingPower, Downforce,
--                        TurningAngleSpeedFactor on Vehicles.*.VehicleProperty
--   tags confirmed live  tags.txt -- MainVehicle, VehicleTire, DamageToOpen,
--                        ForbiddenLoot, ShopliftingLoot, GasPump, Repair,
--                        PawnCounter, ATM, PathfindingRoad, PathfindingFloor
--
-- All client-only controls resume the user's last saved state on inject
-- (potassium-dev S0.2b). The two rung-6 controls (NPC aura, auto-smash) boot
-- OFF every session by contract and are never persisted.
--
-- Changelog:
--   2026-09-02.22 Rewrite onto scripts/r3st_ui.lua and the __R3ST_HOST mount.
--                 New: music volume, third person, WalkSpeed. Sliders replace
--                 the cycling tune/fly buttons. Kit `key=` owns autosave.
--                 Fixed: unguarded workspace.Map.StartArea index in auto
--                 escape; tire restore wrote back live props instead of nil.
--                 Dump citations re-derived against 2026-09-02 (the game
--                 updated 2026-08-29 and every script index shifted).
--   2026-08-20.21 Camera-aware fly: yaw-preserving level frame.
--   2026-08-20.17 Manual camera-relative vehicle fly with autosaved speed.
--   2026-08-20.16 Physics-only escape assist; ground/obstacle fail-safe braking.
--   2026-08-20.12 Auto Escape Drive follows generated PathfindingRoad centers.
--   2026-08-20.9  Autosave tune, ESP toggles, fuel, and selected tab.
--   2026-08-20.4  Vehicle tune presets/upright; stock-path NPC aura/auto-smash.
--   2026-08-20.1  Initial five-tab intel GUI and decoded remote monitor.
--------------------------------------------------------------------------

local BUILD_VERSION = "runaways-2026-09-02.22"
local EXPECTED_PLACE = 117311404196294
local EXPECTED_GAME = 7585140258
local CONFIG_PATH = "configs/runaways.json"

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")

local LP = Players.LocalPlayer
local G = (getgenv and getgenv()) or _G
local GKEY = "__RUNAWAYS_INTEL"

if G[GKEY] then
	if type(G[GKEY].destroy) ~= "function" then return end
	local removed = pcall(G[GKEY].destroy)
	if not removed then return end -- never stack a new build over a failed teardown
end

--==========================================================================
-- Logging
--==========================================================================
local function makeLogger()
	local ok, factory = pcall(function() return loadfile("log.lua")() end)
	if ok and type(factory) == "function" then
		local ok2, logger = pcall(factory, "runaways_intel")
		if ok2 then return logger end
	end
	local rows = {}
	local function add(level, msg)
		rows[#rows + 1] = string.format("[%s] %s", level, tostring(msg))
		pcall(writefile, "logs/runaways_intel.log", table.concat(rows, "\n") .. "\n")
	end
	return {
		session = function(m) rows = {}; add("session", m) end,
		info = function(m) add("info", m) end,
		warn = function(m) add("warn", m) end,
		err = function(m, e) add("err", tostring(m) .. " " .. tostring(e)) end,
	}
end

local Log = makeLogger()
Log.session(string.format("armed build=%s place=%s universe=%s",
	BUILD_VERSION, tostring(game.PlaceId), tostring(game.GameId)))

-- Universe first: a private server keeps the GameId and changes the PlaceId.
if game.GameId ~= EXPECTED_GAME and game.PlaceId ~= EXPECTED_PLACE then
	Log.err("wrong experience", tostring(game.GameId) .. "/" .. tostring(game.PlaceId))
	return
end

--==========================================================================
-- Config -- flat keys so the kit's `key =` autosave owns every control
--==========================================================================
local CFG = {
	tab = "Overview",
	panelX = -320,
	panelY = -260,
	-- overlays
	espLoot = false,
	espPlayers = false,
	espNPCs = false,
	espVehicles = false,
	espBreakables = false,
	espStations = false,
	lootRadius = 650,
	-- vehicle
	infiniteFuel = false,
	highGrip = false,
	vehicleTune = 1,
	flySpeed = 220,
	-- client comfort (all rung 2/3, all resumed on inject)
	musicOn = false,
	musicVolume = 100,
	thirdPerson = false,
	walkSpeedOn = false,
	walkSpeed = 15,
}

local NUM_LIMITS = {
	panelX = { -2000, 2000 }, panelY = { -2000, 2000 },
	lootRadius = { 100, 2000 },
	vehicleTune = { 1, 8 }, flySpeed = { 40, 500 },
	musicVolume = { 0, 200 }, walkSpeed = { 15, 150 },
}

pcall(function()
	if not isfile(CONFIG_PATH) then return end
	local loaded = HttpService:JSONDecode(readfile(CONFIG_PATH))
	if type(loaded) ~= "table" then return end
	-- v2 stored overlays under `flags`; migrate rather than lose them.
	if type(loaded.flags) == "table" then
		for old, key in next, { Loot = "espLoot", Players = "espPlayers", NPCs = "espNPCs",
			Vehicles = "espVehicles", Breakables = "espBreakables", Stations = "espStations" } do
			if type(loaded.flags[old]) == "boolean" then loaded[key] = loaded.flags[old] end
		end
	end
	if type(loaded.selectedTab) == "string" and loaded.tab == nil then loaded.tab = loaded.selectedTab end
	for key, default in next, CFG do
		local v = loaded[key]
		if type(v) == type(default) then
			if type(v) == "number" then
				local lim = NUM_LIMITS[key]
				CFG[key] = lim and math.clamp(v, lim[1], lim[2]) or v
			else
				CFG[key] = v
			end
		end
	end
end)

local saveQueued = false
local function saveConfig()
	saveQueued = false
	local ok, err = pcall(function()
		if type(isfolder) == "function" and not isfolder("configs") then makefolder("configs") end
		writefile(CONFIG_PATH, HttpService:JSONEncode(CFG))
		local verified = HttpService:JSONDecode(readfile(CONFIG_PATH))
		assert(type(verified) == "table", "config decode failed")
		assert(verified.musicVolume == CFG.musicVolume, "config readback mismatch")
	end)
	if not ok then Log.err("config save failed", err) end
	return ok
end
saveConfig() -- creates and validates the autosave file on every load

--==========================================================================
-- State
--==========================================================================
local S = {
	alive = true,
	conns = {},
	markers = {},
	remoteRows = {},
	remoteSeen = {},
	remoteHook = nil,
	remoteEnabled = false,
	remoteDirty = false,
	vehicleOriginals = {},
	fuelOriginals = {},
	tireOriginals = {},
	musicOriginals = {},
	cameraOriginals = nil,
	walkOriginal = nil,
	aura = false,      -- rung 6: never persisted, boots OFF
	autoSmash = false, -- rung 6: never persisted, boots OFF
	autoEscape = false,
	vehicleFly = false,
	escapeCollisions = {},
	nextPowerAction = 0,
	powerNote = "idle",
}

local UILive = {}

local function connect(signal, fn)
	local c = signal:Connect(fn)
	S.conns[#S.conns + 1] = c
	return c
end

local function guard(what, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then Log.err("ERR " .. tostring(what), err) end
	return ok
end

local function powerStatus(note)
	if S.powerNote ~= note then
		S.powerNote = note
		Log.info("power status " .. note)
	end
end

--==========================================================================
-- Game reads
--==========================================================================
local function firstPart(inst)
	if inst:IsA("BasePart") then return inst end
	if inst:IsA("Model") then
		return inst.PrimaryPart or inst:FindFirstChild("HumanoidRootPart") or inst:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function humanoid()
	local char = LP.Character
	return char and char:FindFirstChildOfClass("Humanoid") or nil
end

local lootApi
pcall(function() lootApi = require(ReplicatedStorage.Data.Loot) end)

local function lootValue(name)
	if lootApi and type(lootApi.GetItemValue) == "function" then
		local ok, value = pcall(lootApi.GetItemValue, name)
		if ok and type(value) == "number" then return value end
	end
	return nil
end

local function localDrivenVehicle()
	local hum = humanoid()
	if not hum then return nil end
	for _, vehicle in CollectionService:GetTagged("MainVehicle") do
		local seat = vehicle:FindFirstChildWhichIsA("VehicleSeat", true)
		if seat and seat.Occupant == hum then return vehicle end
	end
	return nil
end

local function drivenChassis()
	local vehicle = localDrivenVehicle()
	local system = vehicle and vehicle:FindFirstChild("system")
	local chassis = system and system:FindFirstChild("chassis")
	if chassis and chassis:IsA("BasePart") then return vehicle, chassis end
	return vehicle, nil
end

local function owned(part)
	if type(isnetworkowner) ~= "function" then return true end
	local ok, result = pcall(isnetworkowner, part)
	if not ok then return true end
	return result
end

local function countTags()
	local loot = workspace:FindFirstChild("Loot")
	return string.format("Loot %d  ·  NPCs %d  ·  vehicles %d  ·  breakables %d  ·  repairs %d  ·  pumps %d",
		loot and #loot:GetChildren() or 0,
		#CollectionService:GetTagged("NPC"), #CollectionService:GetTagged("MainVehicle"),
		#CollectionService:GetTagged("DamageToOpen"), #CollectionService:GetTagged("Repair"),
		#CollectionService:GetTagged("GasPump"))
end

local function vehicleSummary()
	local out = {}
	for _, v in CollectionService:GetTagged("MainVehicle") do
		local prop = v:FindFirstChild("VehicleProperty")
		local hp = v:FindFirstChild("vehicleHealth")
		local gas = v:FindFirstChild("gasLevel")
		local cap = prop and prop:GetAttribute("GasCapacity")
		out[#out + 1] = string.format("%s  ·  HP %s  ·  fuel %s/%s  ·  top %s MPH  ·  range %s",
			v.Name, hp and math.floor(hp.Value) or "?",
			gas and math.floor(gas.Value * 10) / 10 or "?", cap or "?",
			prop and prop:GetAttribute("TopSpeedMPH") or "?",
			prop and prop:GetAttribute("FullTankRange") or "?")
	end
	if #out == 0 then out[1] = "No streamed MainVehicle" end
	return out
end

local function backpackSummary()
	local backpack = LP:FindFirstChildOfClass("Backpack")
	local rows, total = {}, 0
	if not backpack then return rows, total end
	for _, item in backpack:GetChildren() do
		if item:IsA("Tool") then
			local value = lootValue(item.Name) or 0
			total += value
			local extras = {}
			local ammo = item:GetAttribute("Ammo")
			if ammo ~= nil then extras[#extras + 1] = "ammo " .. tostring(ammo) end
			local ammoType = item:GetAttribute("AmmoType")
			if ammoType ~= nil then extras[#extras + 1] = tostring(ammoType) end
			rows[#rows + 1] = { name = item.Name, value = value, extra = table.concat(extras, " · ") }
		end
	end
	table.sort(rows, function(a, b) return a.value > b.value end)
	return rows, total
end

local function bestLoot()
	local found = {}
	local folder = workspace:FindFirstChild("Loot")
	if folder then
		for _, item in folder:GetChildren() do
			found[#found + 1] = { name = item.Name, value = lootValue(item.Name) or -1 }
		end
	end
	table.sort(found, function(a, b) return a.value > b.value end)
	return found
end

--==========================================================================
-- Marker layer -- ALWAYS its own full-screen CoreGui ScreenGui.
-- Reparenting billboards into the hub panel clips them to its rectangle
-- (hub S6.1 r8), so this layer is independent of where the panel lives.
--==========================================================================
local markerLayer
do
	local core = CoreGui
	if type(cloneref) == "function" then
		local ok, copy = pcall(cloneref, core)
		if ok and copy then core = copy end
	end
	markerLayer = Instance.new("ScreenGui")
	markerLayer.Name = "rw_markers_" .. tostring(math.random(100000, 999999))
	markerLayer.ResetOnSpawn = false
	markerLayer.IgnoreGuiInset = true
	markerLayer.DisplayOrder = 10
	markerLayer.Parent = core
end

local function markerKey(kind, inst)
	return kind .. ":" .. inst:GetFullName() -- full paths distinguish repeated item names
end

local function setMarker(kind, inst, text, color)
	local key = markerKey(kind, inst)
	local existing = S.markers[key]
	if existing then
		existing.label.Text = text
		return
	end
	local adornee = firstPart(inst)
	if not adornee then return end
	local gui = Instance.new("BillboardGui")
	gui.Name = "rw_m"
	gui.Adornee = adornee
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromOffset(190, 34)
	gui.StudsOffset = Vector3.new(0, 2.8, 0)
	gui.MaxDistance = 1200
	gui.Parent = markerLayer
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(9, 9, 9)
	label.BackgroundTransparency = 0.28
	label.BorderSizePixel = 0
	label.Font = Enum.Font.GothamBold
	label.TextSize = 12
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.45
	label.Text = text
	label.Parent = gui
	Instance.new("UICorner", label).CornerRadius = UDim.new(0, 4)
	S.markers[key] = { gui = gui, label = label, instance = inst, kind = kind }
end

local function clearMarkers(kind)
	for key, item in next, S.markers do
		if not kind or item.kind == kind then
			item.gui:Destroy()
			S.markers[key] = nil
		end
	end
end

local function refreshMarkers()
	if not S.alive then return end
	local char = LP.Character
	local rootPart = char and char:FindFirstChild("HumanoidRootPart")
	if CFG.espPlayers then
		for _, player in Players:GetPlayers() do
			if player ~= LP and player.Character then
				local hum = player.Character:FindFirstChildOfClass("Humanoid")
				local hp = hum and math.max(0, math.floor(hum.Health)) or 0
				setMarker("Players", player.Character, player.DisplayName .. "  HP " .. hp, Color3.fromRGB(255, 105, 105))
			end
		end
	end
	if CFG.espNPCs then
		for _, npc in CollectionService:GetTagged("NPC") do
			setMarker("NPCs", npc, "NPC  " .. npc.Name, Color3.fromRGB(255, 193, 92))
		end
	end
	if CFG.espVehicles then
		for _, vehicle in CollectionService:GetTagged("MainVehicle") do
			local health = vehicle:FindFirstChild("vehicleHealth")
			local gas = vehicle:FindFirstChild("gasLevel")
			local info = vehicle:FindFirstChild("VehicleProperty")
			local cap = info and info:GetAttribute("GasCapacity")
			local fuel = gas and cap and cap > 0 and math.floor(gas.Value / cap * 100) or nil
			setMarker("Vehicles", vehicle, string.format("%s  HP %s  FUEL %s", vehicle.Name,
				health and math.floor(health.Value) or "?", fuel and (fuel .. "%") or "?"),
				Color3.fromRGB(92, 204, 255))
		end
	end
	if CFG.espLoot and rootPart then
		local folder = workspace:FindFirstChild("Loot")
		for _, loot in folder and folder:GetChildren() or {} do
			local part = firstPart(loot)
			if part and (part.Position - rootPart.Position).Magnitude <= CFG.lootRadius then
				local value = lootValue(loot.Name)
				local tag = CollectionService:HasTag(loot, "ForbiddenLoot") and "FORBIDDEN"
					or (CollectionService:HasTag(loot, "ShopliftingLoot") and "SHOP" or "LOOT")
				local color = value and value >= 500 and Color3.fromRGB(255, 209, 77) or Color3.fromRGB(116, 235, 151)
				setMarker("Loot", loot, loot.Name .. "  $" .. tostring(value or "?") .. "  " .. tag, color)
			end
		end
	end
	if CFG.espBreakables then
		for _, object in CollectionService:GetTagged("DamageToOpen") do
			local health = object:FindFirstChild("Health")
			local maxHealth = object:FindFirstChild("MaxHealth")
			setMarker("Breakables", object, string.format("%s  HP %s/%s", object.Name,
				health and math.max(0, math.floor(health.Value)) or "?",
				maxHealth and math.floor(maxHealth.Value) or "?"), Color3.fromRGB(255, 128, 92))
		end
	end
	if CFG.espStations then
		for _, tag in { "GasPump", "Repair", "PawnCounter", "ATM" } do
			for _, object in CollectionService:GetTagged(tag) do
				setMarker("Stations", object, tag .. "  " .. object.Name, Color3.fromRGB(112, 220, 255))
			end
		end
	end
	local flagOf = {
		Players = "espPlayers", NPCs = "espNPCs", Vehicles = "espVehicles",
		Loot = "espLoot", Breakables = "espBreakables", Stations = "espStations",
	}
	for key, item in next, S.markers do
		if not item.instance.Parent or not item.instance:IsDescendantOf(workspace) or not CFG[flagOf[item.kind]] then
			item.gui:Destroy()
			S.markers[key] = nil
		end
	end
end

--==========================================================================
-- Remote monitor (observe only)
--==========================================================================
local function summarize(args)
	local out = {}
	for i = 1, math.min(args.n or #args, 5) do
		local v = args[i]
		local kind = typeof(v)
		if kind == "Instance" then
			out[i] = v.ClassName .. ":" .. v.Name
		elseif kind == "table" then
			out[i] = "{table}"
		elseif kind == "string" then
			out[i] = string.format("%q", v:sub(1, 42))
		else
			out[i] = tostring(v):sub(1, 42)
		end
	end
	return table.concat(out, ", ")
end

local function captureRemote(remote, method, args)
	local module = type(args[1]) == "string" and args[1] or "?"
	local action = type(args[2]) == "string" and args[2] or "?"
	local key = table.concat({ method, remote.Name, module, action }, "|")
	local entry = S.remoteSeen[key]
	if entry then
		entry.count += 1
		entry.time = os.date("%H:%M:%S")
		entry.args = summarize(args)
		if entry.count == 10 or entry.count == 50 or entry.count % 250 == 0 then
			Log.info(string.format("REMOTE x%d %s %s.%s", entry.count, method, module, action))
		end
		S.remoteDirty = true
		return
	end
	entry = {
		time = os.date("%H:%M:%S"), remote = remote.Name, method = method,
		module = module, action = action, args = summarize(args), count = 1,
	}
	S.remoteSeen[key] = entry
	table.insert(S.remoteRows, 1, entry)
	while #S.remoteRows > 80 do table.remove(S.remoteRows) end
	Log.info(string.format("REMOTE %s %s.%s (%s)", method, module, action, entry.args))
	S.remoteDirty = true
end

local function armRemoteMonitor()
	if S.remoteHook then
		S.remoteEnabled = true
		return true
	end
	if type(hookmetamethod) ~= "function" or type(getnamecallmethod) ~= "function" then
		Log.warn("remote monitor unavailable on this executor")
		return false
	end
	local old
	old = hookmetamethod(game, "__namecall", function(self, ...)
		local method = getnamecallmethod()
		if S.alive and S.remoteEnabled and (method == "FireServer" or method == "InvokeServer") then
			local ok, isRemote = pcall(function()
				return self:IsA("RemoteEvent") or self:IsA("RemoteFunction") or self:IsA("UnreliableRemoteEvent")
			end)
			if ok and isRemote then
				captureRemote(self, method, table.pack(...))
			end
		end
		return old(self, ...)
	end)
	S.remoteHook = old
	S.remoteEnabled = true
	Log.info("remote monitor armed")
	return true
end

local remoteInv, remoteInvAt = {}, 0
local function remoteInventory()
	local now = os.clock()
	if now - remoteInvAt < 5 and #remoteInv > 0 then return remoteInv end
	remoteInvAt = now
	local result = {}
	for _, inst in game:GetDescendants() do
		if inst:IsA("RemoteEvent") or inst:IsA("RemoteFunction") or inst:IsA("UnreliableRemoteEvent") then
			result[#result + 1] = inst.ClassName .. "  " .. inst:GetFullName()
		end
	end
	table.sort(result)
	remoteInv = result
	return result
end

--==========================================================================
-- Client comfort: music, camera, walk speed
--
-- All three are properties the game's OWN client code writes, so pinning them
-- inherits the game's behaviour instead of inventing new behaviour (rung 3).
--==========================================================================
local MUSIC_GROUPS = { "Music", "PhysicalMusic" }

local function applyMusic()
	if not CFG.musicOn then return end
	local target = CFG.musicVolume / 100
	for _, name in MUSIC_GROUPS do
		local group = SoundService:FindFirstChild(name)
		if group and group:IsA("SoundGroup") then
			if S.musicOriginals[group] == nil then S.musicOriginals[group] = group.Volume end
			if math.abs(group.Volume - target) > 0.001 then group.Volume = target end
		end
	end
end

local function restoreMusic()
	for group, volume in next, S.musicOriginals do
		if group and group.Parent then pcall(function() group.Volume = volume end) end
	end
	S.musicOriginals = {}
end

-- 0153:34 SetMode(true) sets LockFirstPerson + MinZoom 0; :78 re-runs it on
-- every character effect and Spectate (0185:404,446,453) re-runs it again, so
-- one write is not enough -- the value has to be pinned.
local function applyCamera()
	if not CFG.thirdPerson then return end
	if S.cameraOriginals == nil then
		S.cameraOriginals = {
			mode = LP.CameraMode,
			minZoom = LP.CameraMinZoomDistance,
			maxZoom = LP.CameraMaxZoomDistance,
		}
	end
	if LP.CameraMode ~= Enum.CameraMode.Classic then LP.CameraMode = Enum.CameraMode.Classic end
	if LP.CameraMinZoomDistance ~= 0.5 then LP.CameraMinZoomDistance = 0.5 end
	if LP.CameraMaxZoomDistance < 25 then LP.CameraMaxZoomDistance = 25 end
end

local function restoreCamera()
	local o = S.cameraOriginals
	S.cameraOriginals = nil
	if not o then return end
	-- Put back exactly what the game's own SetMode(true) leaves behind.
	pcall(function()
		LP.CameraMinZoomDistance = o.minZoom
		LP.CameraMaxZoomDistance = o.maxZoom
		LP.CameraMode = o.mode
	end)
end

-- 0160:99 setSpeed tweens Humanoid.WalkSpeed on every crouch/sprint/stop
-- transition, so a single write is reverted by the next state change. Pinning
-- from Heartbeat runs after TweenService, so our value is the one that lands.
-- Cap 150 keeps HRP velocity far under AntiYeetClient's 300 (0150:53).
local function applyWalkSpeed()
	if not CFG.walkSpeedOn then return end
	local hum = humanoid()
	if not hum then return end
	if S.walkOriginal == nil then S.walkOriginal = hum.WalkSpeed end
	if hum:GetAttribute("Downed") == true then return end -- do not fight the downed clamp
	local target = math.clamp(CFG.walkSpeed, 15, 150)
	if math.abs(hum.WalkSpeed - target) > 0.05 then hum.WalkSpeed = target end
end

local function restoreWalkSpeed()
	local hum = humanoid()
	if hum and S.walkOriginal then pcall(function() hum.WalkSpeed = S.walkOriginal end) end
	S.walkOriginal = nil
end

--==========================================================================
-- Vehicle power
--==========================================================================
local TUNE_ATTRS = { "TopSpeedMPH", "Acceleration", "Torque", "BrakingPower", "Downforce", "TurningAngleSpeedFactor" }

local function restoreVehicleTunes()
	for cfgObj, values in next, S.vehicleOriginals do
		if cfgObj and cfgObj.Parent then
			for name, value in next, values do cfgObj:SetAttribute(name, value) end
		end
	end
	S.vehicleOriginals = {}
end

local function applyVehicleTune()
	restoreVehicleTunes()
	local mult = CFG.vehicleTune
	if mult <= 1.001 then
		Log.info("vehicle tune stock")
		return
	end
	for _, vehicle in CollectionService:GetTagged("MainVehicle") do
		local cfgObj = vehicle:FindFirstChild("VehicleProperty")
		if cfgObj then
			local originals = {}
			for _, name in TUNE_ATTRS do
				local value = cfgObj:GetAttribute(name)
				if type(value) == "number" then
					originals[name] = value
					if name == "TurningAngleSpeedFactor" then
						cfgObj:SetAttribute(name, math.max(0.03, value / mult))
					else
						cfgObj:SetAttribute(name, value * mult)
					end
				end
			end
			S.vehicleOriginals[cfgObj] = originals
		end
	end
	Log.info(string.format("vehicle tune %.2fx applied; re-enter driver seat", mult))
end

local function restoreGrip()
	for wheel, original in next, S.tireOriginals do
		if wheel and wheel.Parent then
			-- `false` is the sentinel for "had no CustomPhysicalProperties". v2.21
			-- stored the live properties instead, so unload left the tyres pinned
			-- to whatever they were at arm time rather than back on the material.
			pcall(function() wheel.CustomPhysicalProperties = original ~= false and original or nil end)
		end
	end
	S.tireOriginals = {}
	S.highGripVehicle = nil
end

local function applyHighGrip()
	if not CFG.highGrip then return end
	local vehicle = localDrivenVehicle()
	if not vehicle then return end
	if S.highGripVehicle and S.highGripVehicle ~= vehicle then restoreGrip() end
	S.highGripVehicle = vehicle
	for _, wheel in CollectionService:GetTagged("VehicleTire") do
		if wheel:IsA("BasePart") and wheel:IsDescendantOf(vehicle) and S.tireOriginals[wheel] == nil then
			local custom = wheel.CustomPhysicalProperties
			local base = custom or wheel.CurrentPhysicalProperties
			S.tireOriginals[wheel] = custom or false
			wheel.CustomPhysicalProperties = PhysicalProperties.new(base.Density, 2, base.Elasticity, 100, base.ElasticityWeight)
		end
	end
end

local function applyInfiniteFuel()
	if not CFG.infiniteFuel then return end
	local vehicle = localDrivenVehicle()
	if not vehicle then return end
	local gas = vehicle:FindFirstChild("gasLevel")
	local props = vehicle:FindFirstChild("VehicleProperty")
	local capacity = props and props:GetAttribute("GasCapacity")
	if gas and gas:IsA("NumberValue") and type(capacity) == "number" and capacity > 0 then
		if S.fuelOriginals[gas] == nil then S.fuelOriginals[gas] = gas.Value end
		if gas.Value < capacity then gas.Value = capacity end
	end
end

local function restoreFuel()
	for gas, value in next, S.fuelOriginals do
		if gas and gas.Parent then pcall(function() gas.Value = value end) end
	end
	S.fuelOriginals = {}
end

local function stabilizeDrivenVehicle(dt)
	if not CFG.highGrip then return end
	local _, chassis = drivenChassis()
	if not chassis or not owned(chassis) then return end
	local speed = chassis.AssemblyLinearVelocity.Magnitude
	if speed < 80 then return end
	local localVelocity = chassis.CFrame:VectorToObjectSpace(chassis.AssemblyLinearVelocity)
	local slipDecay = math.exp(-10 * math.min(dt, 0.05))
	localVelocity = Vector3.new(localVelocity.X * slipDecay, math.min(localVelocity.Y, 40), localVelocity.Z)
	chassis.AssemblyLinearVelocity = chassis.CFrame:VectorToWorldSpace(localVelocity)
	local localAngular = chassis.CFrame:VectorToObjectSpace(chassis.AssemblyAngularVelocity)
	local yawLimit = math.clamp(140 / speed, 0.18, 0.8)
	localAngular = Vector3.new(math.clamp(localAngular.X, -0.22, 0.22),
		math.clamp(localAngular.Y, -yawLimit, yawLimit), math.clamp(localAngular.Z, -0.22, 0.22))
	chassis.AssemblyAngularVelocity = chassis.CFrame:VectorToWorldSpace(localAngular)
end

local function restoreEscapeFlight()
	local _, chassis = drivenChassis()
	if S.escapeVehicle then
		local system = S.escapeVehicle:FindFirstChild("system")
		chassis = system and system:FindFirstChild("chassis") or chassis
	end
	if chassis and chassis:IsA("BasePart") and owned(chassis) then
		chassis.AssemblyLinearVelocity = Vector3.zero
		chassis.AssemblyAngularVelocity = Vector3.zero
	end
	for part, original in next, S.escapeCollisions do
		if part and part.Parent then pcall(function() part.CanCollide = original end) end
	end
	S.escapeCollisions = {}
	S.escapeVehicle = nil
end

local function escapeEndZ()
	local endZ
	pcall(function()
		local routeModule = require(ReplicatedStorage.FlowClient.Gui.DistanceToBorderClient)
		local getuvs = debug and debug.getupvalues
		if type(getuvs) ~= "function" or type(routeModule) ~= "table" then return end
		local target = routeModule.SetEndPos_event or routeModule.SetEndPos
		if type(target) ~= "function" then return end
		for _, value in next, getuvs(target) do
			if type(value) == "number" and math.abs(value) > 1000 then endZ = value; break end
		end
	end)
	return endZ
end

-- v2.21 indexed workspace.Map.StartArea.Helpers.ProgressionStart directly, every
-- frame, with no guard: one streaming-out of that folder threw inside Heartbeat
-- and took the whole loop with it.
local function progressionStartZ()
	local map = workspace:FindFirstChild("Map")
	local area = map and map:FindFirstChild("StartArea")
	local helpers = area and area:FindFirstChild("Helpers")
	local part = helpers and helpers:FindFirstChild("ProgressionStart")
	return part and part:IsA("BasePart") and part.Position.Z or nil
end

local function stopEscape(reason)
	S.autoEscape = false
	powerStatus("escape stopped: " .. reason)
	restoreEscapeFlight()
end

local function runAutoEscape()
	if not S.autoEscape then return end
	local vehicle, chassis = drivenChassis()
	if not chassis then return stopEscape("driver seat lost") end
	if not owned(chassis) then return stopEscape("server revoked chassis") end
	if S.escapeVehicle and S.escapeVehicle ~= vehicle then restoreEscapeFlight() end
	S.escapeVehicle = vehicle

	local position = chassis.Position
	local endZ = escapeEndZ()
	local startZ = progressionStartZ()
	local directionSign
	if endZ then
		directionSign = endZ > position.Z and 1 or -1
	elseif startZ then
		directionSign = position.Z > startZ and 1 or -1
	else
		directionSign = 1
	end

	local target, bestScore
	for _, point in CollectionService:GetTagged("PathfindingRoad") do
		if point:IsA("BasePart") then
			local dz = (point.Position.Z - position.Z) * directionSign
			local dx = math.abs(point.Position.X - position.X)
			if dz > 12 and dz < 450 and dx < 220 then
				local score = dz + dx * 2
				if not bestScore or score < bestScore then target, bestScore = point, score end
			end
		end
	end
	if not target then return stopEscape("no safe road ahead") end

	local flatDelta = Vector3.new(target.Position.X - position.X, 0, target.Position.Z - position.Z)
	if flatDelta.Magnitude < 1 then return end
	local direction = flatDelta.Unit

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { vehicle }
	local ground = workspace:Raycast(position + direction * 35 + Vector3.new(0, 20, 0), Vector3.new(0, -70, 0), params)
	if not ground or ground.Normal.Y < 0.55 then
		chassis.AssemblyLinearVelocity = Vector3.zero
		chassis.AssemblyAngularVelocity = Vector3.zero
		powerStatus("escape braking: no ground ahead")
		return
	end

	local currentSpeed = Vector3.new(chassis.AssemblyLinearVelocity.X, 0, chassis.AssemblyLinearVelocity.Z).Magnitude
	local stopDistance = math.clamp(currentSpeed * 0.8 + 35, 55, 220)
	local origin = position + Vector3.new(0, 3, 0)
	for _, offset in { -5, 0, 5 } do
		local side = Vector3.new(-direction.Z, 0, direction.X) * offset
		local hit = workspace:Raycast(origin + side, direction * stopDistance, params)
		if hit and hit.Instance and not hit.Instance:HasTag("PathfindingRoad") and not hit.Instance:HasTag("PathfindingFloor") then
			chassis.AssemblyLinearVelocity *= 0.2
			chassis.AssemblyAngularVelocity = Vector3.zero
			powerStatus("escape braking: obstacle ahead")
			return
		end
	end

	local speed = 220
	local forward = Vector3.new(chassis.CFrame.LookVector.X, 0, chassis.CFrame.LookVector.Z)
	if forward.Magnitude > 0.1 then
		local yawError = math.asin(math.clamp(forward.Unit:Cross(direction).Y, -1, 1))
		chassis.AssemblyAngularVelocity = Vector3.new(0, yawError * 2.5, 0)
	end
	local vertical = math.clamp(chassis.AssemblyLinearVelocity.Y, -8, 8)
	chassis.AssemblyLinearVelocity = direction * speed + Vector3.new(0, vertical, 0)
	if endZ and (endZ - position.Z) * directionSign <= 0 then
		stopEscape("endpoint crossed")
	else
		powerStatus(string.format("escape assist %.0f MPH", speed * 0.6263))
	end
end

local function runVehicleFly()
	if not S.vehicleFly then return end
	local _, chassis = drivenChassis()
	if not chassis then
		S.vehicleFly = false
		powerStatus("fly stopped: driver seat lost")
		return
	end
	if not owned(chassis) then
		S.vehicleFly = false
		powerStatus("fly stopped: server revoked chassis")
		return
	end
	local camera = workspace.CurrentCamera
	if not camera then return end
	local look = Vector3.new(camera.CFrame.LookVector.X, 0, camera.CFrame.LookVector.Z)
	local right = Vector3.new(camera.CFrame.RightVector.X, 0, camera.CFrame.RightVector.Z)
	if look.Magnitude < 0.1 or right.Magnitude < 0.1 then return end
	look, right = look.Unit, right.Unit
	local move = Vector3.zero
	if UserInputService:IsKeyDown(Enum.KeyCode.W) then move += look end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) then move -= look end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then move += right end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then move -= right end
	if UserInputService:IsKeyDown(Enum.KeyCode.Space) then move += Vector3.yAxis end
	if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl) then
		move -= Vector3.yAxis
	end
	local speed = CFG.flySpeed
	chassis.AssemblyLinearVelocity = move.Magnitude > 0 and move.Unit * speed or Vector3.zero
	local flatForward = Vector3.new(chassis.CFrame.LookVector.X, 0, chassis.CFrame.LookVector.Z)
	if flatForward.Magnitude > 0.01 then
		chassis.CFrame = CFrame.lookAt(chassis.Position, chassis.Position + flatForward.Unit, Vector3.yAxis)
	end
	chassis.AssemblyAngularVelocity = Vector3.zero
	powerStatus(string.format("vehicle fly %.0f MPH", speed * 0.6263))
end

local function uprightNearestVehicle()
	local char = LP.Character
	local playerRoot = char and char:FindFirstChild("HumanoidRootPart")
	if not playerRoot then return false, "no character" end
	local best, bestPart, bestDist
	for _, vehicle in CollectionService:GetTagged("MainVehicle") do
		local system = vehicle:FindFirstChild("system")
		local part = system and system:FindFirstChild("chassis") or firstPart(vehicle)
		if part then
			local dist = (part.Position - playerRoot.Position).Magnitude
			if not bestDist or dist < bestDist then best, bestPart, bestDist = vehicle, part, dist end
		end
	end
	if not bestPart or bestDist > 35 then return false, "no vehicle within 35 studs" end
	if not owned(bestPart) then return false, "vehicle not client-owned" end
	local look = bestPart.CFrame.LookVector * Vector3.new(1, 0, 1)
	look = look.Magnitude < 0.01 and Vector3.new(0, 0, -1) or look.Unit
	local lift = bestPart.Position + Vector3.new(0, 2.5, 0)
	bestPart.CFrame = CFrame.lookAt(lift, lift + look)
	bestPart.AssemblyAngularVelocity = Vector3.zero
	Log.info("upright applied " .. best.Name)
	return true, best.Name
end

--==========================================================================
-- Combat automation -- rung 6, stock path only, never persisted
--==========================================================================
local function equippedMelee()
	local char = LP.Character
	if not char then return nil, nil end
	local tool = char:FindFirstChildOfClass("Tool")
	if not tool then return nil, nil end
	local ok, cfgObj = pcall(function() return require(ReplicatedStorage.Data).Tools.GetToolConfig(tool.Name) end)
	if not ok or type(cfgObj) ~= "table" or type(cfgObj.hitsPerSecond) ~= "number" or not tool:FindFirstChild("Handle") then
		return nil, nil
	end
	return tool, cfgObj
end

local function stockTargetNear(tag, origin)
	for _, part in workspace:GetPartBoundsInRadius(origin, 3) do
		local target = part.Parent
		if target and target:HasTag(tag) then
			local hum = target:FindFirstChildOfClass("Humanoid")
			if not hum or hum.Health > 1 then return true end
		end
	end
	return false
end

local function runPowerAutomation(now)
	if (not S.aura and not S.autoSmash) or now < S.nextPowerAction then return end
	local tool, toolCfg = equippedMelee()
	if not tool then powerStatus("waiting: no equipped melee"); return end
	local handle = tool:FindFirstChild("Handle")
	local shouldActivate = S.aura and stockTargetNear("NPC", handle.Position)
	if not shouldActivate and S.autoSmash then shouldActivate = stockTargetNear("DamageToOpen", handle.Position) end
	if shouldActivate then
		S.nextPowerAction = now + 1 / math.max(0.1, toolCfg.hitsPerSecond)
		local ok, err = pcall(function() tool:Activate() end) -- stock handler owns LOS/range/damage remotes
		powerStatus(ok and ("activated " .. tool.Name) or ("activate FAILED " .. tostring(err)))
	else
		powerStatus("waiting: no target part within stock 3 studs")
	end
end

--==========================================================================
-- UI -- one control template, drawn with scripts/r3st_ui.lua
--==========================================================================
local HOST = (type(G.__R3ST_HOST) == "table" and typeof(G.__R3ST_HOST.host) == "Instance"
	and G.__R3ST_HOST.host.Parent ~= nil) and G.__R3ST_HOST or nil

-- Explorer folder first: Potassium roots the file API at workspace\, so a bare
-- readfile reads the wrong folder and can load a months-old copy (hub S11).
local KIT_PATHS = { "../scripts/r3st_ui.lua", "r3st_ui.lua", "scripts/r3st_ui.lua" }

local function loadKit()
	if HOST and type(HOST.ui) == "table" then
		Log.info("ui kit " .. tostring(HOST.ui.VERSION) .. " <- host")
		return HOST.ui
	end
	for _, path in KIT_PATHS do
		local ok, src = pcall(readfile, path)
		if ok and type(src) == "string" and #src > 0 then
			local chunk = loadstring(src, "=r3st_ui.lua")
			if type(chunk) == "function" then
				local ran, kit = pcall(chunk)
				if ran and type(kit) == "table" then
					Log.info("ui kit " .. tostring(kit.VERSION) .. " <- " .. path .. " (" .. #src .. " bytes)")
					return kit
				end
			end
		end
	end
	return nil
end

local destroy -- forward: the footer and the unload key bind it before it exists

local Kit = loadKit()
if not Kit then
	Log.err("r3st_ui.lua not found", table.concat(KIT_PATHS, " | "))
	return
end
local COL = Kit.COL

local screen, panel, inner
if HOST then
	panel = Instance.new("Frame")
	panel.Name = "RunawaysPanel"
	panel.Size = UDim2.fromScale(1, 1)
	panel.BackgroundTransparency = 1
	panel.BorderSizePixel = 0
	panel.Active = true
	panel.Visible = true -- r5: a saved "hidden" is about the standalone window
	panel.Parent = HOST.host
	screen = panel -- destroy() tears this down; the hub owns the ScreenGui
else
	local core = CoreGui
	if type(cloneref) == "function" then
		local ok, copy = pcall(cloneref, core)
		if ok and copy then core = copy end
	end
	screen = Instance.new("ScreenGui")
	screen.Name = "R3ST_RW_" .. tostring(math.random(1000, 9999))
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Global
	screen.DisplayOrder = 2147483647
	pcall(sethiddenproperty, screen, "OnTopOfCoreBlur", true)
	screen.Parent = core
	panel = Instance.new("Frame")
	panel.Name = "RunawaysPanel"
	panel.Size = UDim2.fromOffset(760, 560)
	panel.Position = UDim2.new(0.5, CFG.panelX, 0.5, CFG.panelY)
	panel.BackgroundColor3 = COL.bg
	panel.BorderSizePixel = 0
	panel.Active = true
	panel.Parent = screen
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 12)
	Instance.new("UIStroke", panel).Color = COL.line
end

inner = Instance.new("Frame")
inner.BackgroundTransparency = 1
inner.BorderSizePixel = 0
inner.Position = UDim2.fromOffset(HOST and 12 or 18, HOST and 8 or 14)
inner.Size = UDim2.new(1, HOST and -24 or -36, 1, HOST and -16 or -28)
inner.Parent = panel

local W = Kit.bind({ live = UILive, conns = S.conns, cfg = CFG, save = saveConfig, guard = guard })

local TABS = { "Overview", "Loot", "Entities", "Vehicle", "Client", "Power", "Remotes" }
local pages, repaintTabs = {}, nil

local function setTab(name)
	if not pages[name] then name = "Overview" end
	CFG.tab = name
	for k, p in next, pages do p.Visible = (k == name) end
	W.saveNow()
end

W.header(inner, {
	title = "Runaways",
	version = "v" .. BUILD_VERSION,
	subtitle = "Loot, entity and vehicle awareness, client comfort and opt-in power. Universe " .. tostring(EXPECTED_GAME) .. ".",
	gameId = EXPECTED_GAME,
	placeId = EXPECTED_PLACE,
	onInfo = function()
		setTab("Client")
		if repaintTabs then repaintTabs() end
	end,
})

local strip
strip, repaintTabs = W.tabstrip(inner, {
	names = TABS,
	position = UDim2.fromOffset(0, 80),
	get = function() return CFG.tab end,
	set = setTab,
})

local BODY_Y = 122
local function pageWidth()
	local w = inner.AbsoluteSize.X
	if w < 200 then w = 724 end
	return w - 10 -- scrollbar gutter
end

for _, name in TABS do
	local page = Instance.new("ScrollingFrame")
	page.Name = name
	page.BackgroundTransparency = 1
	page.BorderSizePixel = 0
	page.Position = UDim2.fromOffset(0, BODY_Y)
	page.Size = UDim2.new(1, 0, 1, -(BODY_Y + 52))
	page.ScrollBarThickness = 3
	page.ScrollBarImageColor3 = COL.line
	page.CanvasSize = UDim2.new()
	page.Visible = false
	page.Parent = inner
	pages[name] = page
	W.page(page, { width = pageWidth() })
end

-- A fixed bank of live rows beats rebuilding a page every quarter second: the
-- layout never moves under the cursor and the kit only repaints visible text.
local function listRows(page, count, getLine)
	for i = 1, count do
		W.statusRow(page, function() return getLine(i) or "" end)
	end
end

local function espToggle(page, key, label, desc, kind)
	W.toggle(page, {
		label = label, desc = desc, key = key,
		set = function(v)
			if not v then clearMarkers(kind) end
			refreshMarkers()
			Log.info(key .. "=" .. tostring(v))
		end,
	})
end

--------------------------------------------------------------- Overview
do
	local page = pages.Overview
	W.section(page, "Session")
	W.statusRow(page, function() return "Build " .. BUILD_VERSION end)
	W.statusRow(page, countTags)
	W.statusRow(page, function()
		local stats = LP:FindFirstChild("leaderstats")
		local cash = stats and stats:FindFirstChild("Cash 💵")
		return "Cash $" .. tostring(cash and cash.Value or "?") .. "  ·  players " .. tostring(#Players:GetPlayers())
	end)
	W.statusRow(page, function()
		local hum = humanoid()
		return string.format("WalkSpeed %s  ·  camera %s  ·  music %s",
			hum and math.floor(hum.WalkSpeed) or "?",
			LP.CameraMode == Enum.CameraMode.Classic and "third person" or "first person",
			CFG.musicOn and (CFG.musicVolume .. "%") or "game default")
	end)

	W.section(page, "Power status")
	W.statusRow(page, function() return S.powerNote end)
	W.statusRow(page, function()
		local vehicle = localDrivenVehicle()
		return vehicle and ("Driving " .. vehicle.Name) or "Not seated in a vehicle"
	end)

	W.section(page, "Safety posture")
	W.note(page, "Intel and overlays are client-only. Vehicle power writes owned-chassis physics, which is visible as motion. NPC aura and auto-smash call the stock Tool:Activate and boot OFF every session.")
	W.note(page, "The only client speed limiter in the dump zeroes your character above 300 velocity. WalkSpeed caps at 150 to stay well under it.")
end

--------------------------------------------------------------- Loot
do
	local page = pages.Loot
	W.section(page, "Overlay")
	espToggle(page, "espLoot", "Loot ESP", "Pawn value and crime tag over every streamed item", "Loot")
	W.slider(page, {
		label = "Scan radius", key = "lootRadius", min = 100, max = 2000, step = 50,
		fmt = function(v) return string.format("%d studs", v) end,
		stock = function() return 650 end,
		tradeoff = "Wider costs more markers per refresh; 650 is the shipped default.",
	})

	W.section(page, "Backpack ledger")
	local bagCache, bagTotal = {}, 0
	W.statusRow(page, function()
		bagCache, bagTotal = backpackSummary()
		return string.format("%d tools  ·  pawn total $%d", #bagCache, bagTotal)
	end)
	listRows(page, 10, function(i)
		local item = bagCache[i]
		if not item then return "" end
		return item.name .. "  ·  $" .. tostring(item.value) .. (item.extra ~= "" and ("  ·  " .. item.extra) or "")
	end)

	W.section(page, "Best streamed loot")
	local lootCache = {}
	W.statusRow(page, function()
		lootCache = bestLoot()
		return #lootCache .. " items streamed"
	end)
	listRows(page, 14, function(i)
		local item = lootCache[i]
		if not item then return "" end
		return item.name .. "  ·  $" .. tostring(item.value >= 0 and item.value or "?")
	end)
end

--------------------------------------------------------------- Entities
do
	local page = pages.Entities
	W.section(page, "World overlays")
	espToggle(page, "espPlayers", "Players", "Display name and health", "Players")
	espToggle(page, "espNPCs", "NPCs", "Everything tagged NPC", "NPCs")
	espToggle(page, "espVehicles", "Vehicles", "Health and fuel percentage", "Vehicles")
	espToggle(page, "espBreakables", "Breakables", "DamageToOpen health out of max", "Breakables")
	espToggle(page, "espStations", "Stations", "Gas pumps, repair, pawn counter and ATMs", "Stations")

	W.section(page, "Live counts")
	W.statusRow(page, countTags)
	W.statusRow(page, function() return string.format("%d markers drawn", (function()
		local n = 0
		for _ in next, S.markers do n += 1 end
		return n
	end)()) end)
end

--------------------------------------------------------------- Vehicle
do
	local page = pages.Vehicle
	W.section(page, "Telemetry")
	local vehCache = {}
	W.statusRow(page, function()
		vehCache = vehicleSummary()
		return #vehCache .. " streamed"
	end)
	listRows(page, 4, function(i) return vehCache[i] end)

	W.section(page, "Stock limits")
	W.note(page, "Low-fuel warning at 25%. No-fuel grace 60 seconds. AntiYeetClient zeroes your character above 300 velocity.")
	W.statusRow(page, function()
		local _, chassis = drivenChassis()
		if not chassis then return "No owned chassis" end
		return string.format("Chassis %.0f studs/sec  ·  %.0f MPH  ·  %s",
			chassis.AssemblyLinearVelocity.Magnitude,
			chassis.AssemblyLinearVelocity.Magnitude * 0.6263,
			owned(chassis) and "client-owned" or "server-owned")
	end)
end

--------------------------------------------------------------- Client
do
	local page = pages.Client

	W.section(page, "Audio")
	W.toggle(page, {
		label = "Override music volume", key = "musicOn",
		desc = "Takes over SoundService.Music and PhysicalMusic",
		set = function(v)
			if v then applyMusic() else restoreMusic() end
			Log.info("music override " .. (v and "ON" or "OFF"))
		end,
	})
	W.slider(page, {
		label = "Music volume", key = "musicVolume", min = 0, max = 200, step = 5,
		fmt = function(v) return string.format("%d%%", v) end,
		stock = function() return 100 end,
		tradeoff = "100% is what the game sets. 0% is the same result as its own Mute button.",
		set = function() applyMusic() end,
	})
	W.note(page, "The game's topbar Mute button tweens both groups between 0 and 1. While this override is on it wins; turn it off to hand control back.")

	W.section(page, "Camera")
	W.toggle(page, {
		label = "Third person", key = "thirdPerson",
		desc = "Unlocks the camera the game locks to first person on every spawn",
		set = function(v)
			if v then applyCamera() else restoreCamera() end
			Log.info("third person " .. (v and "ON" or "OFF"))
		end,
	})
	W.note(page, "FlowClient.Camera re-forces first person on every character effect and on leaving spectate, so this is pinned rather than set once. Unload restores exactly what the game left.")
	W.statusRow(page, function()
		return string.format("CameraMode %s  ·  zoom %.1f to %.0f",
			tostring(LP.CameraMode):gsub("Enum.CameraMode.", ""),
			LP.CameraMinZoomDistance, LP.CameraMaxZoomDistance)
	end)

	W.section(page, "Movement")
	W.toggle(page, {
		label = "Override WalkSpeed", key = "walkSpeedOn",
		desc = "Pins Humanoid.WalkSpeed against the game's own speed tween",
		set = function(v)
			if not v then restoreWalkSpeed() else applyWalkSpeed() end
			Log.info("walkspeed override " .. (v and "ON" or "OFF"))
		end,
	})
	W.slider(page, {
		label = "WalkSpeed", key = "walkSpeed", min = 15, max = 150, step = 1,
		fmt = function(v) return string.format("%d", v) end,
		stock = function() return 15 end,
		tradeoff = "Stock walk 15, crouch 10, sprint 26 x SprintMult. 150 stays far under the 300 velocity limiter.",
		live = function(v) return string.format("about %.0f MPH on foot", v * 0.6263) end,
	})
	W.note(page, "The downed state keeps its own clamp: while Downed is set this override stands aside rather than fighting it.")
end

--------------------------------------------------------------- Power
do
	local page = pages.Power

	W.section(page, "Vehicle")
	W.toggle(page, {
		label = "Infinite fuel", key = "infiniteFuel",
		desc = "Pins your occupied car's local gasLevel to GasCapacity",
		set = function(v)
			if not v then restoreFuel() else applyInfiniteFuel() end
			Log.info("infinite fuel " .. (v and "ON" or "OFF"))
		end,
	})
	W.toggle(page, {
		label = "Maximum tire grip", key = "highGrip",
		desc = "Tire friction 2, friction weight 100, plus high-speed slip damping",
		set = function(v)
			if not v then restoreGrip() else applyHighGrip() end
			Log.info("high grip " .. (v and "ON" or "OFF"))
		end,
	})
	W.slider(page, {
		label = "Vehicle tune", key = "vehicleTune", min = 1, max = 8, step = 0.25,
		fmt = function(v) return string.format("%.2fx", v) end,
		stock = function() return 1 end,
		tradeoff = "Scales top speed, acceleration, torque, braking and downforce. Exit and re-enter the seat after a change.",
		commit = function() applyVehicleTune() end,
	})
	W.button(page, "Emergency upright nearest vehicle", "Within 35 studs, client-owned only", function()
		local ok, note = uprightNearestVehicle()
		powerStatus((ok and "uprighted " or "upright blocked: ") .. note)
	end, true)

	W.section(page, "Escape and fly")
	W.toggle(page, {
		label = "Auto escape drive",
		desc = "Physics-only road assist at 220 studs/sec; brakes for missing ground",
		get = function() return S.autoEscape end,
		set = function(v)
			S.autoEscape = v
			if v then S.vehicleFly = false else restoreEscapeFlight() end
			Log.info("auto escape " .. (v and "ON" or "OFF"))
		end,
	})
	W.toggle(page, {
		label = "Vehicle fly",
		desc = "Camera-relative WASD, Space up, Ctrl down; keeps the car level",
		get = function() return S.vehicleFly end,
		set = function(v)
			S.vehicleFly = v
			if v then S.autoEscape = false end
			Log.info("vehicle fly " .. (v and "ON" or "OFF"))
		end,
	})
	W.slider(page, {
		label = "Fly speed", key = "flySpeed", min = 40, max = 500, step = 20,
		fmt = function(v) return string.format("%d studs/sec", v) end,
		stock = function() return 220 end,
		live = function(v) return string.format("about %.0f MPH", v * 0.6263) end,
	})
	W.note(page, "Both act on the chassis you own, never on your character, so the 300 velocity limiter is not involved. Neither moves position directly or disables collision.")

	W.section(page, "Combat")
	W.note(page, "These two fire the game's normal attack and boot OFF every session by contract. Equip a melee weapon first.")
	W.toggle(page, {
		label = "NPC aura",
		desc = "Stock 3-stud overlap, stock LOS, stock damage, stock rate",
		get = function() return S.aura end,
		set = function(v) S.aura = v; Log.info("NPC aura " .. (v and "ON" or "OFF")) end,
	})
	W.toggle(page, {
		label = "Auto-smash breakables",
		desc = "Same stock path, targets DamageToOpen instead",
		get = function() return S.autoSmash end,
		set = function(v) S.autoSmash = v; Log.info("auto-smash " .. (v and "ON" or "OFF")) end,
	})
	W.statusRow(page, function() return S.powerNote end)
end

--------------------------------------------------------------- Remotes
do
	local page = pages.Remotes
	W.section(page, "Passive monitor")
	W.toggle(page, {
		label = "Remote monitor",
		desc = "Records calls the game already makes; never fires or replays one",
		get = function() return S.remoteEnabled end,
		set = function(v)
			if v then
				if not armRemoteMonitor() then S.remoteEnabled = false end
			else
				S.remoteEnabled = false
				Log.info("remote monitor paused")
			end
		end,
	})
	W.statusRow(page, function() return #S.remoteRows .. " distinct calls captured" end)

	W.section(page, "Recent outgoing calls")
	listRows(page, 16, function(i)
		local v = S.remoteRows[i]
		if not v then return "" end
		return string.format("%s  x%d  %s.%s  [%s]  %s", v.time, v.count, v.module, v.action, v.remote, v.args)
	end)

	W.section(page, "Visible remote inventory")
	listRows(page, 14, function(i)
		local inv = remoteInventory()
		return inv[i]
	end)
end

--------------------------------------------------------------- Chrome
local function relayoutAll()
	local w = pageWidth()
	for _, page in next, pages do
		Kit.relayout(page, w)
		page.CanvasSize = UDim2.fromOffset(0, Kit.height(page))
	end
end

W.footer(inner, {
	onUnload = function() destroy() end,
	onSettings = function()
		setTab("Client")
		if repaintTabs then repaintTabs() end
	end,
	hint = HOST and "K unload  ·  the hub owns the window and the hide key"
		or "K unload  ·  RightShift panel",
})

setTab(CFG.tab)
task.defer(relayoutAll)
connect(inner:GetPropertyChangedSignal("AbsoluteSize"), function() task.defer(relayoutAll) end)

-- Standalone only: drag strip over the header, and a resize grip.
if not HOST then
	local grip = Instance.new("TextButton")
	grip.BackgroundTransparency = 1
	grip.Text = ""
	grip.AutoButtonColor = false
	grip.Size = UDim2.new(1, 0, 0, 76)
	grip.ZIndex = 0
	grip.Parent = inner
	local dragging, dragStart, panelStart
	connect(grip.InputBegan, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging, dragStart, panelStart = true, input.Position, panel.Position
		end
	end)
	connect(UserInputService.InputChanged, function(input)
		if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			local delta = input.Position - dragStart
			panel.Position = UDim2.new(panelStart.X.Scale, panelStart.X.Offset + delta.X,
				panelStart.Y.Scale, panelStart.Y.Offset + delta.Y)
		end
	end)
	connect(UserInputService.InputEnded, function(input)
		if dragging and input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = false
			CFG.panelX = math.clamp(panel.Position.X.Offset, -2000, 2000)
			CFG.panelY = math.clamp(panel.Position.Y.Offset, -2000, 2000)
			panel.Position = UDim2.new(0.5, CFG.panelX, 0.5, CFG.panelY)
			W.saveNow()
		end
	end)
	Kit.resizeGrip(panel, { min = Vector2.new(700, 480), onResize = relayoutAll, onCommit = relayoutAll })
end

--==========================================================================
-- Lifecycle
--==========================================================================
destroy = function()
	if not S.alive then return end
	S.alive = false
	S.aura, S.autoSmash, S.autoEscape, S.vehicleFly = false, false, false, false
	S.remoteEnabled = false
	restoreEscapeFlight()
	restoreFuel()
	restoreGrip()
	restoreVehicleTunes()
	restoreMusic()
	restoreCamera()
	restoreWalkSpeed()
	if S.remoteHook and type(restorefunction) == "function" then pcall(restorefunction, S.remoteHook) end
	S.remoteHook = nil
	for _, c in S.conns do pcall(function() c:Disconnect() end) end
	S.conns = {}
	clearMarkers()
	if markerLayer then markerLayer:Destroy() end
	if screen then screen:Destroy() end
	G[GKEY] = nil
	Log.info("unloaded")
end

G[GKEY] = { destroy = destroy, unload = destroy, state = S, build = BUILD_VERSION, cfg = CFG }

-- Embedded, RightShift belongs to the hub: a module that also hides its root
-- comes back to a blank tab (hub S6.1 r4). Standalone it hides our panel.
connect(UserInputService.InputBegan, function(input, processed)
	if input.KeyCode == Enum.KeyCode.RightShift then
		if not HOST then panel.Visible = not panel.Visible end
		return
	end
	if processed then return end
	if input.KeyCode == Enum.KeyCode.K then destroy() end
end)

-- Re-pin the client comfort settings across respawns: SetMode(true) at 0153:78
-- and the WalkSpeed tween both re-run on every new character.
connect(LP.CharacterAdded, function()
	S.walkOriginal = nil
	task.delay(1, function()
		if not S.alive then return end
		applyCamera()
		applyWalkSpeed()
	end)
end)

local nextSlow, nextUI = 0, 0

connect(RunService.Heartbeat, function(dt)
	if not S.alive then return end
	local now = os.clock()

	-- every frame: physics and pins that lose a race if they are throttled
	applyInfiniteFuel()
	applyHighGrip()
	stabilizeDrivenVehicle(dt)
	applyWalkSpeed()
	runVehicleFly()
	runAutoEscape()
	runPowerAutomation(now)

	if now >= nextSlow then
		nextSlow = now + 0.25
		applyCamera()
		applyMusic()
		if CFG.vehicleTune > 1.001 then
			for _, vehicle in CollectionService:GetTagged("MainVehicle") do
				local cfgObj = vehicle:FindFirstChild("VehicleProperty")
				if cfgObj and not S.vehicleOriginals[cfgObj] then
					applyVehicleTune()
					break
				end
			end
		end
		refreshMarkers()
	end

	if now >= nextUI and panel.Visible then
		nextUI = now + 0.1
		S.remoteDirty = false
		for _, fn in UILive do pcall(fn) end
	end
end)

-- Resume the user's saved client-only state, visibly, before the first frame.
if CFG.musicOn then applyMusic() end
if CFG.thirdPerson then applyCamera() end
if CFG.walkSpeedOn then applyWalkSpeed() end
if CFG.vehicleTune > 1.001 then applyVehicleTune() end
refreshMarkers()

Log.info(string.format("ready hosted=%s tab=%s music=%s/%d thirdPerson=%s walk=%s/%d tune=%.2fx esp[L%s P%s N%s V%s B%s S%s]",
	tostring(HOST ~= nil), CFG.tab, tostring(CFG.musicOn), CFG.musicVolume,
	tostring(CFG.thirdPerson), tostring(CFG.walkSpeedOn), CFG.walkSpeed, CFG.vehicleTune,
	tostring(CFG.espLoot), tostring(CFG.espPlayers), tostring(CFG.espNPCs),
	tostring(CFG.espVehicles), tostring(CFG.espBreakables), tostring(CFG.espStations)))
