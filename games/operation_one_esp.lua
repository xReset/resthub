--------------------------------------------------------------------------
-- operation_one_esp.lua -- Operation One (PlaceId 72920620366355) player ESP + gun duck + optional soft aim
-- op1-2026-08-19.1-gunduck (2026-08-19)
--
-- Re-inject safe: self-teardown on load; K = unload
-- UNLOADS_ON_INJECT: __OP1_ESP
--
-- Client visuals/input/audio-mixer only. No remotes, no hookfunction/hookmetamethod,
-- no camera writes, no hitbox edits. Log to file only (no print/warn).
--
-- AC (dump 2026-08-14T06-44-06Z anticheat_deep.txt): CLIENT INSPECTION=0,
-- LOG MONITORING=0. AntiCheat lives in ServerStorage (0821.lua server gate only).
-- Gun duck uses SoundService.World.Gunshots.Volume + routes Shoot/SilencedShoot
-- onto that group. Footsteps already use World.Footsteps (properties.txt) and
-- are never touched. Settings only write World.Volume (0794.lua) -- safe.
--
-- Dump adapters fitted to PlaceId 72920620366355 (Character tag / Viewmodels).
-- RightShift = toggle panel | K = unload
--
-- Changelog:
--   2026-08-19.1  Gun duck via World.Gunshots (AC-safe; preserve footsteps)
--   2026-08-14.3  Utility ESP + exposure tint
--------------------------------------------------------------------------

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local SoundService = game:GetService("SoundService")

local LP = Players.LocalPlayer
local RNG = Random.new()

local GENV = (getgenv and getgenv()) or _G
if type(GENV) ~= "table" then
	GENV = _G
end

local GKEY = "__OP1_ESP"

-- hub.lua publishes __R3ST_HOST immediately before running us and clears it the
-- moment we return. When it is set, the hub owns the ScreenGui, the window
-- chrome, the drag and RightShift, so the CONTROL PANEL renders inside its
-- content host. The ESP/visual layer is deliberately left alone: it has to stay
-- a full-screen CoreGui layer, never a child of a hub panel.
local __HUBENV = (type(getgenv) == "function" and getgenv()) or _G
local HOST = (type(__HUBENV.__R3ST_HOST) == "table"
	and typeof(__HUBENV.__R3ST_HOST.host) == "Instance") and __HUBENV.__R3ST_HOST or nil

local BUILD_VERSION = "op1-2026-08-19.1-gunduck" -- bump on every deploy: the log line proves which build is live
local CONFIG_FILE = "operation_one_esp_config.json"
local LEGACY_STATE_FILE = "operation_one_esp.state"

local function queueReinject()
	local payload = [[
pcall(function()
	local f = loadfile("operation_one_esp.lua")
	if f then f() end
end)
]]
	local function tryQueue(fn)
		local ok, result = pcall(fn, payload)
		return ok and result ~= false
	end
	local queued = false
	if type(queue_on_teleport) == "function" then
		queued = tryQueue(queue_on_teleport)
	end
	if not queued and type(queueonteleport) == "function" then
		queued = tryQueue(queueonteleport)
	end
	if not queued and type(syn) == "table" and type(syn.queue_on_teleport) == "function" then
		queued = tryQueue(syn.queue_on_teleport)
	end
	return queued
end

if GENV[GKEY] and type(GENV[GKEY].destroy) == "function" then
	pcall(GENV[GKEY].destroy)
end

local Log
do
	local ok, mod = pcall(function()
		return loadfile("log.lua")()
	end)
	if ok and type(mod) == "function" then
		Log = mod("operation_one_esp")
	else
		local buf = {}
		local function flush(tag, m)
			table.insert(buf, string.format("[%s] %s", tag, tostring(m)))
			pcall(writefile, "logs/operation_one_esp.log", table.concat(buf, "\n") .. "\n")
		end
		Log = {
			session = function(m)
				flush("session", m)
			end,
			step = function(m)
				flush("step", m)
			end,
			info = function(m)
				flush("info", m)
			end,
			warn = function(m)
				flush("warn", m)
			end,
			err = function(m, e)
				flush("err", tostring(m) .. " " .. tostring(e))
			end,
		}
	end
end

local teleportQueued = queueReinject()
if teleportQueued then
	Log.info("teleport queued job=" .. tostring(game.JobId))
else
	Log.warn("teleport queue unavailable or failed")
end

GENV[GKEY] = GENV[GKEY] or {}
local ESP = GENV[GKEY]

local DEFAULTS = {
	Chams = true,
	Healthbars = true,
	Names = true,
	Arrows = true,
	Tracers = false,
	Utility = true,
	GunDuck = true,
	GunVolume = 0.18, -- SoundGroup.Volume 0..1; footsteps stay on World.Footsteps
	SoftAim = false,
	AimFov = 36,
	AimSmooth = 0.66,
	AimMaxStepPx = 30,
	AimStrength = 66,
	AimTuneVersion = 4,
	AimPart = "Closest",
	ShowAimFov = true,
	EspHz = 0.28,
	MaxDist = 650,
	UiVisible = true,
}

local VALIDATORS = {
	Chams = function(v) return type(v) == "boolean" end,
	Healthbars = function(v) return type(v) == "boolean" end,
	Names = function(v) return type(v) == "boolean" end,
	Arrows = function(v) return type(v) == "boolean" end,
	Tracers = function(v) return type(v) == "boolean" end,
	Utility = function(v) return type(v) == "boolean" end,
	GunDuck = function(v) return type(v) == "boolean" end,
	GunVolume = function(v) return type(v) == "number" and v >= 0 and v <= 1 end,
	SoftAim = function(v) return type(v) == "boolean" end,
	AimFov = function(v) return type(v) == "number" and v >= 2 and v <= 45 end,
	AimSmooth = function(v) return type(v) == "number" and v >= 0 and v <= 1 end,
	AimMaxStepPx = function(v) return type(v) == "number" and v >= 1 and v <= 200 end,
	AimStrength = function(v) return type(v) == "number" and v >= 1 and v <= 100 end,
	AimTuneVersion = function(v) return v == 4 end,
	AimPart = function(v) return v == "Closest" or v == "Head" or v == "Body" end,
	ShowAimFov = function(v) return type(v) == "boolean" end,
	EspHz = function(v) return type(v) == "number" and v >= 0.03 and v <= 5 end,
	MaxDist = function(v) return type(v) == "number" and v >= 10 and v <= 10000 end,
	UiVisible = function(v) return type(v) == "boolean" end,
}

local function readConfig()
	local ok, raw = pcall(readfile, CONFIG_FILE)
	if not ok or type(raw) ~= "string" then
		Log.info("config missing; using defaults")
		return {}
	end
	local decodedOk, data = pcall(HttpService.JSONDecode, HttpService, raw)
	if not decodedOk or type(data) ~= "table" then
		Log.warn("config corrupt; using defaults")
		return {}
	end
	Log.info("config loaded " .. CONFIG_FILE)
	return data
end

ESP.CFG = {}
local diskConfig = readConfig()
for k, default in pairs(DEFAULTS) do
	local candidate = diskConfig[k]
	ESP.CFG[k] = VALIDATORS[k](candidate) and candidate or default
end
local CFG = ESP.CFG
if CFG.AimTuneVersion ~= 4 then
	CFG.AimFov = 36
	CFG.AimSmooth = 0.66
	CFG.AimMaxStepPx = 30
	CFG.AimPart = "Closest"
	CFG.AimTuneVersion = 4
end
if diskConfig.UiVisible == nil then
	local ok, legacy = pcall(readfile, LEGACY_STATE_FILE)
	if ok and type(legacy) == "string" then
		legacy = string.lower((legacy:gsub("%s+", "")))
		if legacy == "1" or legacy == "true" then CFG.UiVisible = true end
		if legacy == "0" or legacy == "false" then CFG.UiVisible = false end
	end
end

local function saveConfig()
	local data = {}
	for k in pairs(DEFAULTS) do data[k] = CFG[k] end
	local encodedOk, payload = pcall(HttpService.JSONEncode, HttpService, data)
	local saved = encodedOk and pcall(writefile, CONFIG_FILE, payload)
	if saved then Log.info("config saved " .. CONFIG_FILE) else Log.warn("config save failed") end
	return saved
end

-- Creates/migrates config now; later user-facing changes save immediately.
saveConfig()

local S = {
	alive = true,
	gui = nil,
	root = nil,
	folder = nil,
	esp = {},
	hb = nil,
	input = nil,
	playerAdded = nil,
	playerRemoving = nil,
	aimRender = nil,
	fovDraw = nil,
	arrows = {},
	tracers = {},
	util = {},
	dragInput = nil,
	stickyChar = nil,
	stickyUntil = 0,
	aimLastNote = nil,
	aimLastLog = 0,
	charConns = {},
	soundAdded = nil,
	gunGroup = nil,
	gunVolSaved = nil,
}

local COL = {
	bg = Color3.fromRGB(8, 8, 10),
	stroke = Color3.fromRGB(28, 28, 32),
	text = Color3.fromRGB(230, 230, 235),
	dim = Color3.fromRGB(140, 140, 148),
	on = Color3.fromRGB(60, 180, 90),
	off = Color3.fromRGB(48, 48, 54),
	enemyFill = Color3.fromRGB(205, 72, 72),
	enemyOut = Color3.fromRGB(255, 215, 215),
	exposedLo = Color3.fromRGB(235, 235, 240), -- fully behind cover
	exposedHi = Color3.fromRGB(235, 45, 45), -- fully exposed to us
	hpHi = Color3.fromRGB(70, 210, 90),
	hpLo = Color3.fromRGB(210, 60, 60),
	name = Color3.fromRGB(240, 240, 245),
	dist = Color3.fromRGB(178, 178, 188),
	arrow = Color3.fromRGB(235, 235, 240),
	-- Utility splits by what it does to you, not by who owns it: everything
	-- drawn is already enemy-only, so the colour is free to carry threat.
	utilLethal = Color3.fromRGB(255, 140, 60),  -- kills you
	utilTactic = Color3.fromRGB(90, 190, 255),  -- blinds//slows/watches you
}

local function blandName(prefix)
	return prefix .. string.format("%04x", RNG:NextInteger(0, 65535))
end

-- gethui() on this client returns RobloxGui, which is a ScreenGui. A BillboardGui
-- nested inside a ScreenGui does not render, so chams/healthbars were created,
-- enabled and correctly adorned but invisible. Only accept a container that is
-- not a GUI object.
local function usableParent(inst)
	return inst and not inst:IsA("LayerCollector") and not inst:IsA("GuiObject")
end

local function getParent()
	if typeof(gethui) == "function" then
		local ok, hui = pcall(gethui)
		if ok and usableParent(hui) then
			return hui
		end
	end
	local core = game:GetService("CoreGui")
	if usableParent(core) then
		return core
	end
	return LP:FindFirstChildOfClass("PlayerGui") or LP:WaitForChild("PlayerGui", 5)
end

local function ensureFolder()
	if S.folder and S.folder.Parent then
		return S.folder
	end
	local parent = getParent()
	if ESP.folderName then
		local old = parent:FindFirstChild(ESP.folderName)
		if old then
			old:Destroy()
		end
	end
	ESP.folderName = blandName("UI")
	local f = Instance.new("Folder")
	f.Name = ESP.folderName
	f.Parent = parent
	S.folder = f
	return f
end

-- Operation One rig (dump full_dump/trees/Workspace.txt): character Model parented
-- straight under Workspace, named by username. Parts are ONLY:
--   HumanoidRootPart [Part] (1.5, 5, 0.75)  legs [Part]  collision [UnionOperation]
-- No Head / UpperTorso / Torso exists -- template defaults would find nothing.
--
-- DO NOT TRUST Player.Character. Measured live, 6 of 8 players had a Character
-- that was either a dead rig under ReplicatedStorage.Garbage or an old model
-- left in Workspace under a different name (Workspace.SamPeeleCritical for
-- MarchingTsugikuni, Workspace.Allusion for dawson927). That is what made
-- players go missing from the ESP.
--
-- The game's own entity list is the "Character" CollectionService tag:
-- StateObject classes are built from Util.hook_tagged (0815.lua:111) and the
-- interface iterates StateObject.get_all("Character") (0203.lua:229), skipping
-- objects whose StateObject.clean is set. Each rig carries UserId and usually
-- Team attributes, so a rig is identifiable without going through the Player.
local CHAR_TAG = "Character"

local function rigAlive(rig)
	if not rig:IsDescendantOf(workspace) then
		return false
	end
	if not rig:FindFirstChild("HumanoidRootPart") then
		return false
	end
	local so = rig:FindFirstChild("StateObject")
	local clean = so and so:FindFirstChild("clean")
	if clean and clean.Value then
		return false
	end
	local hum = rig:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0
end

local function liveRigs()
	local out = {}
	for _, rig in ipairs(CollectionService:GetTagged(CHAR_TAG)) do
		if rig:IsA("Model") and rigAlive(rig) then
			table.insert(out, rig)
		end
	end
	return out
end

local function rigUserId(rig)
	local uid = rig:GetAttribute("UserId")
	return type(uid) == "number" and uid or nil
end

local function rigOwner(rig)
	local uid = rigUserId(rig)
	if uid then
		local plr = Players:GetPlayerByUserId(uid)
		if plr then
			return plr
		end
	end
	return Players:FindFirstChild(rig.Name)
end

local function getCharacter(plr)
	if not plr then
		return nil
	end
	for _, rig in ipairs(liveRigs()) do
		if rigUserId(rig) == plr.UserId then
			return rig
		end
	end
	-- Fall back to Player.Character only if it is a live tagged rig.
	local char = plr.Character
	if char and CollectionService:HasTag(char, CHAR_TAG) and rigAlive(char) then
		return char
	end
	return nil
end

-- Health source per full_dump/characters.txt: Humanoid.Health on the rig.
local function getHumanoid(char)
	return char and char:FindFirstChildOfClass("Humanoid")
end

-- Team model (ReplicatedStorage.Modules.Util, script 0824.lua:280 + 0203.lua:229):
-- team is the "Team" string attribute on the Player ("Red"/"Blue"/"Spectate"),
-- Player.Team mirrors it; "Spectator" attribute marks a spectating player.
local function playerTeam(plr)
	local attr = plr and plr:GetAttribute("Team")
	if type(attr) == "string" then
		return attr
	end
	return plr and plr.Team and plr.Team.Name or nil
end

-- Rigs carry their own Team attribute, but not always (full_dump/characters.txt
-- has rigs with "flags: none"), so fall back to the owning player.
local function charTeam(char, plr)
	local attr = char and char:GetAttribute("Team")
	if type(attr) == "string" then
		return attr
	end
	return playerTeam(plr)
end

local function targetAllowed(plr, char)
	if char == nil then
		return false
	end
	-- Identify self by rig, not by player: Player.Character lies.
	if char == LP.Character or rigUserId(char) == LP.UserId then
		return false
	end
	if plr == LP then
		return false
	end
	if plr and plr:GetAttribute("Spectator") then
		return false
	end
	local team = charTeam(char, plr)
	if team == "Spectate" then
		return false
	end
	local myTeam = charTeam(getCharacter(LP), LP)
	if team and myTeam and team == myTeam then
		return false
	end
	-- Unknown team (no attribute, no player object yet) is still drawn: a rig
	-- that is tagged, alive and not ours is a body worth seeing.
	return true
end

-- The rendered body for a character is a separate Model under
-- Workspace.Viewmodels, marked with the "Viewmodels" attribute. Nothing links it
-- back to the player: the game CFrames it onto the character each frame with the
-- character's own Motor6Ds disabled (0184.lua setup_viewmodels), so its pivot sits
-- exactly on the character root. Match on that.
-- The offset is NOT ~0: measured over 1483 frames it sits anywhere from 0.6 to
-- 3.0 studs depending on stance (lean, prone, crouch move the rig pivot). A
-- 2-stud cutoff made one player flicker as it crossed the line and another never
-- match at all. Use a loose cutoff and settle ambiguity with a mutual-nearest
-- test instead of a tight radius.
local VM_MATCH_DIST = 8

-- Workspace.Viewmodels holds pooled rigs too: measured live, 7 of 11 had every
-- part at Transparency = 1 for all 1460 sampled frames. A Highlight on one of
-- those draws nothing, which reads as the outline blinking out.
local function viewmodelRendered(model)
	for _, part in ipairs(model:GetChildren()) do
		if part:IsA("BasePart") and part.Transparency < 1 then
			return true
		end
	end
	return false
end

-- A crouched/prone rig measures ~2.0 studs tall against ~6.0 standing, so its
-- silhouette folds into a blob that is hard to read through a wall. Below this
-- height a thin full-height stem is drawn on the character root as a position cue.
local CROUCH_HEIGHT = 4
local STEM_HEIGHT = 5

-- Nameplate. A BillboardGui sized in offset still shrinks with distance, so a
-- fixed TextSize is unreadable past ~80 studs. Children are sized in SCALE and
-- the labels are TextScaled, so scaling the gui by distance/NAME_REF_DIST holds
-- the whole plate at a constant on-screen size instead. Capped both ways: below
-- the floor a point-blank plate would shrink to nothing, above the ceiling a
-- 600-stud target would paint a billboard across half the screen.
local NAME_BASE_W = 180
local NAME_BASE_H = 38
local NAME_REF_DIST = 28
local NAME_SCALE_MIN = 0.8
local NAME_SCALE_MAX = 4

local function modelHeight(model)
	local ok, _, size = pcall(model.GetBoundingBox, model)
	return ok and size and size.Y or nil
end

local function viewmodelPivot(model)
	local ok, pivot = pcall(function()
		return model:GetPivot().Position
	end)
	return ok and pivot or nil
end

local function nearestRigTo(pivot, rigs)
	local best, bestDist = nil, math.huge
	for _, rig in ipairs(rigs) do
		local root = rig:FindFirstChild("HumanoidRootPart")
		if root then
			local dist = (root.Position - pivot).Magnitude
			if dist < bestDist then
				best, bestDist = rig, dist
			end
		end
	end
	return best
end

local function viewmodelFor(char)
	local root = char:FindFirstChild("HumanoidRootPart")
	local container = workspace:FindFirstChild("Viewmodels")
	if not root or not container then
		return nil
	end
	local rigs = liveRigs()
	local best, bestDist = nil, VM_MATCH_DIST
	for _, model in ipairs(container:GetChildren()) do
		if model:IsA("Model") then
			local pivot = viewmodelPivot(model)
			if pivot then
				local dist = (pivot - root.Position).Magnitude
				-- Only claim a viewmodel whose own nearest rig is this rig, so two
				-- players standing on top of each other cannot steal each other's.
				if dist < bestDist and viewmodelRendered(model) and nearestRigTo(pivot, rigs) == char then
					best, bestDist = model, dist
				end
			end
		end
	end
	return best
end

-- Healthbar anchor: chest hull, else legs, else root.
local function adornPart(char)
	return char:FindFirstChild("collision")
		or char:FindFirstChild("legs")
		or char:FindFirstChild("HumanoidRootPart")
end

-- plr may be nil: a tagged rig can exist before its Player object resolves.
local function isTarget(plr, char)
	if not S.alive or plr == LP then
		return false
	end
	if not char or not char.Parent then
		return false
	end
	local hum = getHumanoid(char)
	if not hum or hum.Health <= 0 then
		return false
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local myChar = getCharacter(LP)
	local myHrp = myChar and myChar:FindFirstChild("HumanoidRootPart")
	if hrp and myHrp then
		if (hrp.Position - myHrp.Position).Magnitude > CFG.MaxDist then
			return false
		end
	end
	if not targetAllowed(plr, char) then
		return false
	end
	return true
end

-- ==========================================================
--  Enemy utility ESP
--
--  Every fact below is read from the dump, not guessed:
--  game_dumps/72920620366355/2026-08-14T06-24-33Z_.../
--
--  Deployed utility is a Model carrying attributes, e.g.
--    RemoteC4 [Model] {Attachable=true, Bounces=0, Health=20,
--                      ItemName="RemoteC4", Owner=7086152648, Soft=true,
--                      StartPosition=(40.4,82.4,59.0), Weak=true}
--                     #Breakable #Electronic #Interact #Prop #RemoteC4 #Thrown
--
--    Owner    = UserId of the player who deployed it -> the enemy filter
--    ItemName = display label
--    Health   = HP for placeables (RemoteC4 = 20); absent on plain grenades
--
--  The 23 type names come from ReplicatedStorage.Modules.Items.Item.Utility
--  .Placeable.* and .Throwable.* (scripts_index.txt) and each is a registered
--  CollectionService tag (tags.txt). Enumerating by tag is parent-agnostic,
--  which matters because a live item and a spent one sit in different places:
--  spent/pooled items land in ReplicatedStorage.Garbage, the same bucket dead
--  rigs go to. IsDescendantOf(workspace) is what separates them.
-- ==========================================================
local UTIL_TAGS = {
	-- Placeable.*
	{ tag = "BarbedWire", label = "Wire", lethal = false },
	{ tag = "BreachCharge", label = "Breach", lethal = true },
	{ tag = "BulletproofCamera", label = "Cam", lethal = false },
	{ tag = "Claymore", label = "Claymore", lethal = true },
	{ tag = "Defuser", label = "Defuser", lethal = false },
	{ tag = "DeployableShield", label = "Shield", lethal = false },
	{ tag = "HardBreachCharge", label = "HardBreach", lethal = true },
	{ tag = "IncendiaryCanister", label = "Incend", lethal = true },
	{ tag = "ShockBattery", label = "Shock", lethal = true },
	{ tag = "SignalDisruptor", label = "Jammer", lethal = false },
	{ tag = "ThermiteCharge", label = "Thermite", lethal = true },
	-- Throwable.*
	{ tag = "Drone", label = "Drone", lethal = false },
	{ tag = "EMPGrenade", label = "EMP", lethal = false },
	{ tag = "FragGrenade", label = "FRAG", lethal = true },
	{ tag = "ImpactGrenade", label = "Impact", lethal = true },
	{ tag = "IncendiaryGrenade", label = "Fire", lethal = true },
	{ tag = "SmokeGrenade", label = "Smoke", lethal = false },
	{ tag = "StunGrenade", label = "Stun", lethal = false },
	-- Throwable.Underthrow.*
	{ tag = "NeedleMine", label = "Needle", lethal = true },
	{ tag = "ProximityAlarm", label = "Alarm", lethal = false },
	{ tag = "RemoteC4", label = "C4", lethal = true },
	{ tag = "StickyCamera", label = "Sticky", lethal = false },
	{ tag = "ToxicCharge", label = "Toxic", lethal = true },
}

-- Owner is a UserId number attribute. Team comes from the owning Player the
-- same way it does for rigs, so a utility item and its owner always agree.
local function utilEnemy(inst)
	local owner = inst:GetAttribute("Owner")
	if type(owner) ~= "number" then
		-- No owner attribute means we cannot prove it is hostile. Drawing it
		-- anyway would put a marker on our own team's gear, which is worse than
		-- drawing nothing -- the whole point of this layer is "not mine".
		return false
	end
	if owner == LP.UserId then
		return false
	end
	local plr = Players:GetPlayerByUserId(owner)
	if not plr then
		-- Owner left the round. The item is still live and still not ours.
		return true
	end
	local theirTeam = playerTeam(plr)
	local myTeam = playerTeam(LP)
	if theirTeam and myTeam and theirTeam == myTeam then
		return false
	end
	return true, plr
end

local function utilAdornee(inst)
	if inst:IsA("BasePart") then
		return inst
	end
	if inst:IsA("Model") then
		return inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function clearUtil(inst)
	local e = S.util[inst]
	if not e then
		return
	end
	if e.hl then e.hl:Destroy() end
	if e.bb then e.bb:Destroy() end
	S.util[inst] = nil
end

local function ensureUtil(inst, meta, origin)
	local part = utilAdornee(inst)
	if not part then
		clearUtil(inst)
		return
	end
	local dist = origin and (part.Position - origin).Magnitude or nil
	if dist and dist > CFG.MaxDist then
		clearUtil(inst)
		return
	end

	local folder = ensureFolder()
	local e = S.util[inst]
	if not e then
		e = {}
		S.util[inst] = e
		e.destroyConn = inst.Destroying:Connect(function()
			clearUtil(inst)
		end)
	end

	local colour = meta.lethal and COL.utilLethal or COL.utilTactic

	if not e.hl or not e.hl.Parent then
		local hl = Instance.new("Highlight")
		hl.Name = blandName("UH")
		hl.FillTransparency = 1 -- outline only, same read as the player chams
		hl.OutlineTransparency = 0
		hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		hl.Parent = folder
		e.hl = hl
	end
	e.hl.Adornee = inst
	e.hl.OutlineColor = colour
	e.hl.Enabled = true

	if not e.bb or not e.bb.Parent then
		local bb = Instance.new("BillboardGui")
		bb.Name = blandName("UN")
		bb.AlwaysOnTop = true
		bb.Size = UDim2.fromOffset(NAME_BASE_W, NAME_BASE_H * 0.5)
		bb.StudsOffset = Vector3.new(0, 1.2, 0)
		bb.Parent = folder

		local lbl = Instance.new("TextLabel")
		lbl.BackgroundTransparency = 1
		lbl.Size = UDim2.fromScale(1, 1)
		lbl.Font = Enum.Font.GothamBold
		lbl.TextScaled = true
		lbl.TextXAlignment = Enum.TextXAlignment.Center
		lbl.Text = ""
		lbl.Parent = bb
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(0, 0, 0)
		stroke.Thickness = 1
		stroke.Transparency = 0.3
		stroke.Parent = lbl

		e.bb = bb
		e.lbl = lbl
	end

	-- Health only exists on placeables; grenades have none. Showing "20hp" on a
	-- Claymore tells you it is destructible, which is actionable -- omitting it
	-- on a frag avoids implying the same.
	local hp = inst:GetAttribute("Health")
	local text = meta.label
	if dist then
		text = text .. "  " .. tostring(math.floor(dist + 0.5)) .. "m"
	end
	if type(hp) == "number" then
		text = text .. "  " .. tostring(math.floor(hp + 0.5)) .. "hp"
	end
	e.lbl.Text = text
	e.lbl.TextColor3 = colour
	e.bb.Adornee = part
	e.bb.MaxDistance = CFG.MaxDist
	-- Same constant-screen-size trick as the player nameplate.
	local scale = dist and math.clamp(dist / NAME_REF_DIST, NAME_SCALE_MIN, NAME_SCALE_MAX) or 1
	e.bb.Size = UDim2.fromOffset(NAME_BASE_W * scale, NAME_BASE_H * 0.5 * scale)
	e.bb.Enabled = true
end

local function sweepUtil(origin)
	if not CFG.Utility then
		for inst in pairs(S.util) do
			clearUtil(inst)
		end
		return
	end
	local live = {}
	for _, meta in ipairs(UTIL_TAGS) do
		for _, inst in ipairs(CollectionService:GetTagged(meta.tag)) do
			-- Spent/pooled items sit in ReplicatedStorage.Garbage; only what is
			-- actually in the world can hurt us.
			if inst:IsDescendantOf(workspace) and utilEnemy(inst) then
				live[inst] = true
				ensureUtil(inst, meta, origin)
			end
		end
	end
	for inst in pairs(S.util) do
		if not live[inst] then
			clearUtil(inst)
		end
	end
end

local function clearEsp(char)
	local e = S.esp[char]
	if not e then
		return
	end
	if e.conn then
		e.conn:Disconnect()
	end
	if e.destroyConn then
		e.destroyConn:Disconnect()
	end
	if e.hl then
		e.hl:Destroy()
	end
	if e.stem then
		e.stem:Destroy()
	end
	if e.bb then
		e.bb:Destroy()
	end
	S.esp[char] = nil
end

local function wipeEsp()
	for char in pairs(S.esp) do
		clearEsp(char)
	end
	-- Utility visuals live in the same folder, so they die with it. Drop the
	-- bookkeeping too or the next sweep holds entries pointing at destroyed
	-- instances.
	for inst in pairs(S.util) do
		clearUtil(inst)
	end
	if S.folder then
		S.folder:Destroy()
		S.folder = nil
	end
	if S.gui then
		S.gui:Destroy()
		S.gui = nil
	end
	S.root = nil
end

-- ==========================================================
--  Gun duck (AC-safe mixer path)
--
--  Dump facts:
--    SoundService.World.{Gunshots,Explosions,Footsteps} exist
--    Audio.init_sound (0181.lua) tags every Sound "Sound" and sets
--      SoundGroup = existing or World
--    Footstep templates already use World.Footsteps (properties.txt)
--    Shoot / SilencedShoot clones fall through to World (no group set)
--    Settings write World.Volume only (0794.lua) -- never Gunshots
--
--  Mechanism: route shot cues onto Gunshots, lower that group's Volume.
--  No hooks, no World.Volume writes, Footsteps group untouched.
-- ==========================================================
local GUN_CUE = {
	Shoot = true,
	SilencedShoot = true,
	Shoot2 = true, -- some attachment/skin templates (RS tree)
}

local function gunGroup()
	local world = SoundService:FindFirstChild("World")
	local g = world and world:FindFirstChild("Gunshots")
	if g and g:IsA("SoundGroup") then
		return g
	end
	return nil
end

local function routeGunSound(snd)
	if not S.alive or not CFG.GunDuck then
		return
	end
	if not snd or not snd:IsA("Sound") then
		return
	end
	if not GUN_CUE[snd.Name] then
		return
	end
	-- Never touch footsteps / UI / music: only rename-matched shot cues.
	local g = S.gunGroup or gunGroup()
	if not g then
		return
	end
	S.gunGroup = g
	if snd.SoundGroup ~= g then
		snd.SoundGroup = g
	end
end

local function applyGunDuck()
	local g = gunGroup()
	if not g then
		Log.warn("gun duck: World.Gunshots missing")
		return
	end
	S.gunGroup = g
	if S.gunVolSaved == nil then
		S.gunVolSaved = g.Volume
	end
	if CFG.GunDuck then
		g.Volume = math.clamp(CFG.GunVolume, 0, 1)
		Log.info(string.format("gun duck on vol=%.2f (saved=%.2f)", g.Volume, S.gunVolSaved))
		for _, snd in ipairs(CollectionService:GetTagged("Sound")) do
			routeGunSound(snd)
		end
	else
		g.Volume = S.gunVolSaved
		Log.info("gun duck off restored=" .. tostring(S.gunVolSaved))
	end
end

local function restoreGunDuck()
	local g = S.gunGroup or gunGroup()
	if g and S.gunVolSaved ~= nil then
		g.Volume = S.gunVolSaved
	end
	S.gunVolSaved = nil
	S.gunGroup = nil
end

local function armGunDuck()
	applyGunDuck()
	if S.soundAdded then
		S.soundAdded:Disconnect()
		S.soundAdded = nil
	end
	-- Game already tags via Audio.init_sound; listen only, never hook Play.
	S.soundAdded = CollectionService:GetInstanceAddedSignal("Sound"):Connect(function(inst)
		routeGunSound(inst)
	end)
end

local function teardown()
	S.alive = false
	if S.hb then
		S.hb:Disconnect()
		S.hb = nil
	end
	if S.input then
		S.input:Disconnect()
		S.input = nil
	end
	if S.playerAdded then
		S.playerAdded:Disconnect()
		S.playerAdded = nil
	end
	if S.playerRemoving then
		S.playerRemoving:Disconnect()
		S.playerRemoving = nil
	end
	if S.tagAdded then
		S.tagAdded:Disconnect()
		S.tagAdded = nil
	end
	if S.tagRemoved then
		S.tagRemoved:Disconnect()
		S.tagRemoved = nil
	end
	if S.aimRender then
		S.aimRender:Disconnect()
		S.aimRender = nil
	end
	if S.fovDraw then
		pcall(function() S.fovDraw:Remove() end)
		S.fovDraw = nil
	end
	for _, tri in ipairs(S.arrows) do
		pcall(function() tri:Remove() end)
	end
	table.clear(S.arrows)
	for _, line in ipairs(S.tracers) do
		pcall(function() line:Remove() end)
	end
	table.clear(S.tracers)
	if S.dragInput then
		S.dragInput:Disconnect()
		S.dragInput = nil
	end
	for inst in pairs(S.util) do
		clearUtil(inst)
	end
	for _, c in pairs(S.charConns) do
		c:Disconnect()
	end
	table.clear(S.charConns)
	if S.soundAdded then
		S.soundAdded:Disconnect()
		S.soundAdded = nil
	end
	restoreGunDuck()
	wipeEsp()
	if GENV[GKEY] == ESP then
		GENV[GKEY] = nil
	end
	Log.step("teardown")
end

-- Shared with the soft-aim gate: walks hits the way Util.can_ray_reach does
-- (0824.lua:1858-1882). A hit only stops the ray if the part or its parent has
-- the "Hard" attribute, or it is CanCollide with Transparency < 1, lands more
-- than 0.3 studs short of the target, and its middle dimension is over 1 stud
-- (0.5 when tagged WallPart). Transparent and thin parts are not cover.
local RAY_STEPS = 12

local function selfIgnore()
	local ignore = {}
	local myChar = getCharacter(LP)
	if myChar then
		table.insert(ignore, myChar)
		local myVm = viewmodelFor(myChar)
		if myVm then
			table.insert(ignore, myVm)
		end
	end
	return ignore
end

local function rayReaches(from, targetPos, targetModel, ignore)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	params.FilterDescendantsInstances = ignore or selfIgnore()

	for _ = 1, RAY_STEPS do
		local hit = workspace:Raycast(from, targetPos - from, params)
		if not hit then
			return true
		end
		local inst = hit.Instance
		if inst:IsDescendantOf(targetModel) then
			return true
		end
		params:AddToFilter(inst)
		if inst:GetAttribute("Hard") or (inst.Parent and inst.Parent:GetAttribute("Hard")) then
			return false
		end
		if inst.CanCollide and inst.Transparency < 1 and (hit.Position - targetPos).Magnitude > 0.3 then
			local dims = { inst.Size.X, inst.Size.Y, inst.Size.Z }
			table.sort(dims)
			local mid = dims[2]
			if mid > 1 or (inst:HasTag("WallPart") and mid > 0.5) then
				return false
			end
		end
	end
	return false
end

-- How much of the rig we can actually shoot, 0 (fully behind cover) to 1 (in the
-- open). One sample per limb, tested from the camera with the game's own cover
-- rules, so the tint answers "can I hit this" rather than "is it drawn".
local EXPOSURE_PARTS = { "head", "torso", "arm1", "arm2", "hip1", "hip2", "leg1", "leg2" }

local function exposure(vm)
	local camera = workspace.CurrentCamera
	if not camera then
		return 0
	end
	local from = camera.CFrame.Position
	local ignore = selfIgnore()
	local seen, total = 0, 0
	for _, name in ipairs(EXPOSURE_PARTS) do
		local part = vm:FindFirstChild(name)
		if part then
			total += 1
			if rayReaches(from, part.Position, vm, ignore) then
				seen += 1
			end
		end
	end
	if total == 0 then
		return 0
	end
	return seen / total
end

-- origin: where distances are measured from (our root, else the camera). Passed
-- in rather than looked up per rig -- getCharacter(LP) walks every tagged rig.
local function ensureEsp(plr, char, origin)
	if not isTarget(plr, char) then
		clearEsp(char)
		return
	end
	local folder = ensureFolder()
	local e = S.esp[char]
	if not e then
		e = {}
		S.esp[char] = e
		local hum = getHumanoid(char)
		if hum then
			e.conn = hum.Died:Connect(function()
				clearEsp(char)
			end)
		end
		e.destroyConn = char.Destroying:Connect(function()
			clearEsp(char)
		end)
	end

	-- Highlight must adorn the VIEWMODEL, not the character. Character parts
	-- (HumanoidRootPart / legs / collision) are permanently Transparency = 1 and
	-- Highlight does not draw fully transparent parts. The body you actually see
	-- is the rig the game builds per player under Workspace.Viewmodels
	-- (ReplicatedStorage.Modules.Character -> setup_viewmodels, 0184.lua:115);
	-- its parts (head/arm1/leg1/torso plus gear meshes) do render.
	if CFG.Chams then
		-- Hysteresis: keep the viewmodel already adorned while it is still alive and
		-- near the rig, so a momentary match miss cannot blink the outline off.
		local vm
		local held = e.hl and e.hl.Adornee
		if held and held.Parent then
			local root = char:FindFirstChild("HumanoidRootPart")
			local pivot = root and viewmodelPivot(held)
			if pivot and (pivot - root.Position).Magnitude < VM_MATCH_DIST
				and viewmodelRendered(held) then
				vm = held
			end
		end
		vm = vm or viewmodelFor(char)
		if vm then
			if not e.hl or not e.hl.Parent then
				local hl = Instance.new("Highlight")
				hl.Name = blandName("HL")
				hl.FillColor = COL.enemyFill
				hl.OutlineColor = COL.enemyOut
				hl.FillTransparency = 1 -- outline only: user wants the silhouette edge, no red fill
				hl.OutlineTransparency = 0
				hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
				hl.Parent = folder
				e.hl = hl
			end
			-- Cached so tracers can tint off the same number instead of firing a
			-- second round of rays for the identical answer.
			e.exposure = exposure(vm)
			e.hl.Adornee = vm
			e.hl.OutlineColor = COL.exposedLo:Lerp(COL.exposedHi, e.exposure)
			e.hl.Enabled = true
		else
			e.exposure = nil
			if e.hl then
				e.hl.Enabled = false
			end
		end

		local root = char:FindFirstChild("HumanoidRootPart")
		local height = vm and modelHeight(vm)
		if root and height and height < CROUCH_HEIGHT then
			if not e.stem or not e.stem.Parent then
				local stem = Instance.new("BoxHandleAdornment")
				stem.Name = blandName("ST")
				stem.AlwaysOnTop = true
				stem.ZIndex = 10
				stem.Color3 = COL.enemyOut
				stem.Transparency = 0.3
				stem.Size = Vector3.new(0.12, STEM_HEIGHT, 0.12)
				stem.Parent = folder
				e.stem = stem
			end
			e.stem.Adornee = root
			e.stem.Visible = true
		elseif e.stem then
			e.stem.Visible = false
		end
	else
		e.exposure = nil
		if e.hl then
			e.hl.Enabled = false
		end
		if e.stem then
			e.stem.Visible = false
		end
	end

	-- One billboard carries both the healthbar and the nameplate so a target costs
	-- a single instance whichever of the two is on.
	if CFG.Healthbars or CFG.Names then
		local head = adornPart(char)
		local hum = getHumanoid(char)
		if head and hum then
			-- Rebuild if any child slot is missing, not just the gui: an entry left
			-- by a pre-nameplate build has a valid e.bb but no labels, and the
			-- update block below indexes them unguarded.
			if not e.bb or not e.bb.Parent or not e.nameLbl or not e.distLbl or not e.track then
				if e.bb then
					e.bb:Destroy()
				end
				local bb = Instance.new("BillboardGui")
				bb.Name = blandName("NT")
				bb.Adornee = head
				bb.AlwaysOnTop = true
				bb.Size = UDim2.fromOffset(NAME_BASE_W, NAME_BASE_H)
				bb.StudsOffset = Vector3.new(-2.05, 1.6, 0)
				bb.Parent = folder

				-- Children sit in scale space so the whole plate rescales as one.
				-- The bar keeps its old on-screen spot: it spans x 86..90 of 180,
				-- which straddles the gui centre the 4px-wide original sat on.
				local track = Instance.new("Frame")
				track.BackgroundColor3 = Color3.fromRGB(12, 12, 14)
				track.BackgroundTransparency = 0.12
				track.BorderSizePixel = 0
				track.Position = UDim2.fromScale(86 / NAME_BASE_W, 0)
				track.Size = UDim2.fromScale(4 / NAME_BASE_W, 1)
				track.Parent = bb

				local fill = Instance.new("Frame")
				fill.AnchorPoint = Vector2.new(0, 1)
				fill.Position = UDim2.fromScale(0, 1)
				fill.BackgroundColor3 = COL.hpHi
				fill.BorderSizePixel = 0
				fill.Size = UDim2.fromScale(1, 1)
				fill.Parent = track

				local function label(y, h, font, colour, strokeAlpha)
					local lbl = Instance.new("TextLabel")
					lbl.BackgroundTransparency = 1
					lbl.Position = UDim2.fromScale(96 / NAME_BASE_W, y)
					lbl.Size = UDim2.fromScale(80 / NAME_BASE_W, h)
					lbl.Font = font
					lbl.TextScaled = true
					lbl.TextColor3 = colour
					lbl.TextXAlignment = Enum.TextXAlignment.Left
					lbl.TextYAlignment = Enum.TextYAlignment.Center
					lbl.Text = ""
					lbl.Parent = bb
					-- Dark outline: white-on-white is the usual way a nameplate
					-- becomes unreadable against sky or a lit wall.
					local stroke = Instance.new("UIStroke")
					stroke.Color = Color3.fromRGB(0, 0, 0)
					stroke.Thickness = 1
					stroke.Transparency = strokeAlpha
					stroke.Parent = lbl
					return lbl
				end

				e.bb = bb
				e.track = track
				e.fill = fill
				-- Label heights drive text size (TextScaled fills the box), so these
				-- shrink the text without touching the healthbar track.
				e.nameLbl = label(0.10, 0.34, Enum.Font.GothamBold, COL.name, 0.3)
				e.distLbl = label(0.48, 0.28, Enum.Font.Gotham, COL.dist, 0.45)
			end

			local pct = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
			e.fill.Size = UDim2.fromScale(1, pct)
			e.fill.BackgroundColor3 = COL.hpLo:Lerp(COL.hpHi, pct)
			e.track.Visible = CFG.Healthbars

			local dist = origin and (char:FindFirstChild("HumanoidRootPart"))
				and (char.HumanoidRootPart.Position - origin).Magnitude or nil
			e.nameLbl.Visible = CFG.Names
			e.distLbl.Visible = CFG.Names
			if CFG.Names then
				e.nameLbl.Text = plr and plr.Name or char.Name
				e.distLbl.Text = dist and string.format("%dm  %d", math.floor(dist + 0.5), math.floor(hum.Health + 0.5))
					or string.format("%d", math.floor(hum.Health + 0.5))
			end

			-- Hold a constant on-screen size: apparent size falls off as 1/distance,
			-- so scale up by distance/ref to cancel it.
			local scale = dist and math.clamp(dist / NAME_REF_DIST, NAME_SCALE_MIN, NAME_SCALE_MAX) or 1
			e.bb.Size = UDim2.fromOffset(NAME_BASE_W * scale, NAME_BASE_H * scale)
			-- Re-applied every sweep: MaxDist is user-tunable at runtime.
			e.bb.MaxDistance = CFG.MaxDist
			e.bb.Enabled = true
			e.bb.Adornee = head
		end
	elseif e.bb then
		e.bb.Enabled = false
	end
end

local function sweepEsp()
	if not S.alive then
		return
	end
	-- Arrows and tracers read S.esp, so entries must keep being built while one of
	-- them is the only feature on.
	if not (CFG.Chams or CFG.Healthbars or CFG.Names or CFG.Arrows or CFG.Tracers
		or CFG.Utility) then
		for char in pairs(S.esp) do
			clearEsp(char)
		end
		sweepUtil(nil)
		return
	end

	local myChar = getCharacter(LP)
	local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
	local camera = workspace.CurrentCamera
	local origin = (myRoot and myRoot.Position) or (camera and camera.CFrame.Position)
	-- Sweep the tagged rigs, not the player list: a rig can be live and tagged
	-- before Player.Character points at it, and players can hold a Character that
	-- is a corpse in ReplicatedStorage.Garbage.
	local live = {}
	for _, char in ipairs(liveRigs()) do
		live[char] = true
		ensureEsp(rigOwner(char), char, origin)
	end
	for char in pairs(S.esp) do
		if not live[char] then
			clearEsp(char)
		end
	end
	sweepUtil(origin)
end

-- Mirrors Util.can_ray_reach (0824.lua:1858-1882) rule for rule. A single
-- raycast is WRONG here: measured live, every enemy was rejected because a
-- Doorway part with Transparency = 1 sat in the way, and the game does not treat
-- that as cover. Only these stop a shot:
--   * the part or its parent has the "Hard" attribute
--   * CanCollide and Transparency < 1 and the hit is more than 0.3 studs short
--     of the target, AND its middle dimension is over 1 stud (over 0.5 when the
--     part is tagged WallPart)
-- Everything else is skipped and the ray continues, so this walks hits the same
-- way the game does.
local function aimVisible(cameraPos, part, targetModel)
	return rayReaches(cameraPos, part.Position, targetModel)
end

local AIM_PRIMARY = { "head", "torso" }
local AIM_FALLBACK = { "arm1", "arm2", "shoulder1", "shoulder2", "hip1", "hip2", "leg1", "leg2" }

local function aimPoints(char)
	local vm = viewmodelFor(char)
	if not vm then
		return {}
	end
	if CFG.AimPart == "Head" then
		local head = vm:FindFirstChild("head")
		return head and { head } or {}
	end
	if CFG.AimPart == "Body" then
		local torso = vm:FindFirstChild("torso")
		return torso and { torso } or {}
	end
	local points = {}
	for _, name in ipairs(AIM_PRIMARY) do
		local part = vm:FindFirstChild(name)
		if part then table.insert(points, part) end
	end
	if #points == 0 then
		for _, name in ipairs(AIM_FALLBACK) do
			local part = vm:FindFirstChild(name)
			if part then table.insert(points, part) end
		end
	end
	return points
end

local function aimCandidate(char, camera, center)
	if not char or not char.Parent then return nil end
	local plr = rigOwner(char)
	if not isTarget(plr, char) then return nil end
	local best
	for _, part in ipairs(aimPoints(char)) do
		local offset = part.Position - camera.CFrame.Position
		if offset.Magnitude >= 0.01 then
			local angle = math.deg(math.acos(math.clamp(camera.CFrame.LookVector:Dot(offset.Unit), -1, 1)))
			local screen, onScreen = camera:WorldToViewportPoint(part.Position)
			if angle <= CFG.AimFov and onScreen and screen.Z > 0
				and aimVisible(camera.CFrame.Position, part, part.Parent) then
				local delta = Vector2.new(screen.X, screen.Y) - center
				if not best or delta.Magnitude < best.score then
					best = { player = plr, char = char, part = part, delta = delta, score = delta.Magnitude }
				end
			end
		end
	end
	return best
end

local function pickAimTarget(camera, center)
	local now = os.clock()
	if S.stickyChar and now <= S.stickyUntil then
		local sticky = aimCandidate(S.stickyChar, camera, center)
		if sticky then return sticky end
	end
	local best
	for _, char in ipairs(liveRigs()) do
		local candidate = aimCandidate(char, camera, center)
		if candidate and (not best or candidate.score < best.score) then
			best = candidate
		end
	end
	if best then
		S.stickyChar = best.char
		S.stickyUntil = now + 0.18
	end
	return best
end

local function aimNote(note)
	local now = os.clock()
	if note ~= S.aimLastNote or now - S.aimLastLog >= 3 then
		S.aimLastNote = note
		S.aimLastLog = now
		Log.info("soft aim " .. note)
	end
end

local function updateFovCircle(camera)
	if not CFG.ShowAimFov or not CFG.SoftAim or type(Drawing) ~= "table"
		or type(Drawing.new) ~= "function" or not camera then
		if S.fovDraw then S.fovDraw.Visible = false end
		return
	end
	if not S.fovDraw then
		local ok, circle = pcall(Drawing.new, "Circle")
		if not ok or not circle then return end
		circle.Thickness = 1
		circle.NumSides = 96
		circle.Filled = false
		circle.Color = Color3.fromRGB(235, 235, 240)
		circle.Transparency = 0.55
		S.fovDraw = circle
	end
	local vp = camera.ViewportSize
	local focal = (vp.Y * 0.5) / math.tan(math.rad(camera.FieldOfView * 0.5))
	S.fovDraw.Position = vp * 0.5
	S.fovDraw.Radius = math.min(focal * math.tan(math.rad(CFG.AimFov)), vp.Magnitude)
	S.fovDraw.Visible = true
end

-- Off-screen arrows. A thin ring of small translucent triangles sitting on the
-- Drawing overlay -- the same layer the FOV circle already lives on, so this adds
-- no new surface to the game's own instance tree.
-- Positions are read live every frame off the rig root (S.esp only refreshes at
-- EspHz), so an arrow tracks smoothly instead of stepping 3x a second.
local ARROW_MAX = 10 -- a full ring of arrows is noise; nearest few is the signal
local ARROW_RING = 0.10 -- fraction of the short viewport axis
local ARROW_SIZE = 24
local ARROW_NEAR = 60 -- at/below this, arrow is at its most solid
local ARROW_FAR = 400 -- at/beyond this, it is barely there
local ARROW_ALPHA_NEAR = 0.62
local ARROW_ALPHA_FAR = 0.2

local function hideArrows(from)
	for i = from, #S.arrows do
		S.arrows[i].Visible = false
	end
end

local function updateArrows(camera)
	if not CFG.Arrows or not camera or type(Drawing) ~= "table" or type(Drawing.new) ~= "function" then
		hideArrows(1)
		return
	end

	local cf = camera.CFrame
	local vp = camera.ViewportSize
	local centre = Vector2.new(vp.X, vp.Y) * 0.5
	local radius = math.min(vp.X, vp.Y) * ARROW_RING

	local pending = {}
	for char in pairs(S.esp) do
		local root = char:FindFirstChild("HumanoidRootPart")
		if root then
			local pos = root.Position
			local dist = (pos - cf.Position).Magnitude
			if dist <= CFG.MaxDist then
				local screen, onScreen = camera:WorldToViewportPoint(pos)
				if not onScreen then
					-- Behind the camera the projection mirrors through the centre,
					-- so flip it to get the true bearing.
					local v = Vector2.new(screen.X, screen.Y) - centre
					if screen.Z <= 0 then
						v = -v
					end
					v = v.Magnitude > 1e-3 and v.Unit or Vector2.new(0, -1)
					table.insert(pending, { dir = v, dist = dist })
				end
			end
		end
	end

	table.sort(pending, function(a, b)
		return a.dist < b.dist
	end)

	local shown = 0
	for i = 1, math.min(#pending, ARROW_MAX) do
		local item = pending[i]
		local tri = S.arrows[i]
		if not tri then
			local ok, made = pcall(Drawing.new, "Triangle")
			if not ok or not made then
				break
			end
			made.Filled = true
			made.Thickness = 1
			made.Color = COL.arrow
			S.arrows[i] = made
			tri = made
		end

		local d = item.dir
		local perp = Vector2.new(-d.Y, d.X)
		local base = centre + d * radius
		tri.PointA = base + d * ARROW_SIZE
		tri.PointB = base - d * ARROW_SIZE * 0.4 + perp * ARROW_SIZE * 0.62
		tri.PointC = base - d * ARROW_SIZE * 0.4 - perp * ARROW_SIZE * 0.62
		-- Solid when they are on top of us, near-invisible at range: the arrow
		-- earns attention only as someone closes in.
		local t = math.clamp((item.dist - ARROW_NEAR) / (ARROW_FAR - ARROW_NEAR), 0, 1)
		tri.Transparency = ARROW_ALPHA_NEAR + (ARROW_ALPHA_FAR - ARROW_ALPHA_NEAR) * t
		tri.Visible = true
		shown = i
	end
	hideArrows(shown + 1)
end

-- Tracers. Deliberately the complement of the arrows: arrows handle what is off
-- screen, tracers handle what is on it, so the two never draw for the same rig
-- and the screen stays readable with both on.
-- Drawn from the bottom centre, which reads as "coming from me" without the line
-- ever crossing the crosshair the way a centre-anchored tracer does.
local TRACER_MAX = 16
local TRACER_ALPHA = 0.4 -- Drawing alpha: 1 = opaque, matches the FOV circle
local TRACER_THICK = 1

local function hideTracers(from)
	for i = from, #S.tracers do
		S.tracers[i].Visible = false
	end
end

local function updateTracers(camera)
	if not CFG.Tracers or not camera or type(Drawing) ~= "table" or type(Drawing.new) ~= "function" then
		hideTracers(1)
		return
	end

	local vp = camera.ViewportSize
	local from = Vector2.new(vp.X * 0.5, vp.Y)
	local camPos = camera.CFrame.Position
	local shown = 0

	for char, e in pairs(S.esp) do
		if shown >= TRACER_MAX then
			break
		end
		local root = char:FindFirstChild("HumanoidRootPart")
		if root then
			local pos = root.Position
			if (pos - camPos).Magnitude <= CFG.MaxDist then
				local screen, onScreen = camera:WorldToViewportPoint(pos)
				if onScreen and screen.Z > 0 then
					local line = S.tracers[shown + 1]
					if not line then
						local ok, made = pcall(Drawing.new, "Line")
						if not ok or not made then
							break
						end
						made.Thickness = TRACER_THICK
						S.tracers[shown + 1] = made
						line = made
					end
					shown += 1
					line.From = from
					line.To = Vector2.new(screen.X, screen.Y)
					-- Same tint as the chams outline, so a line and its outline
					-- always agree about whether that body is shootable.
					line.Color = e.exposure and COL.exposedLo:Lerp(COL.exposedHi, e.exposure) or COL.arrow
					line.Transparency = TRACER_ALPHA
					line.Visible = true
				end
			end
		end
	end
	hideTracers(shown + 1)
end

local function softAimStep(dt)
	if not S.alive then return end
	local camera = workspace.CurrentCamera
	updateFovCircle(camera)
	updateArrows(camera)
	updateTracers(camera)
	if not CFG.SoftAim then return end
	if type(mousemoverel) ~= "function" then
		aimNote("blocked: mousemoverel unavailable")
		return
	end
	if UserInputService:GetFocusedTextBox()
		or UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
		S.stickyChar = nil
		aimNote("waiting: mouse not locked")
		return
	end
	if not (UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
		or UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)) then
		S.stickyChar = nil
		aimNote("waiting: hold LMB/RMB")
		return
	end
	if not camera then
		aimNote("blocked: no camera")
		return
	end
	local target = pickAimTarget(camera, camera.ViewportSize * 0.5)
	if not target then
		aimNote("searching: no valid target")
		return
	end
	local strengthScale = math.clamp(CFG.AimStrength, 1, 100) / 100
	local move = target.delta * strengthScale
	local maxStep = CFG.AimMaxStepPx * (strengthScale / 0.66) * math.clamp(dt * 60, 0.25, 2)
	if move.Magnitude > maxStep then
		move = move.Unit * maxStep
	end
	local ok, err = pcall(mousemoverel, move.X, move.Y)
	if ok then
		-- player is nil for a rig whose Player object has not resolved yet.
		local who = (target.player and target.player.Name) or target.char.Name
		aimNote(string.format("moving: %s %.1fpx", who, move.Magnitude))
	else
		aimNote("FAILED: " .. tostring(err))
	end
end

local function mk(class, props, parent)
	local i = Instance.new(class)
	for k, v in pairs(props) do
		i[k] = v
	end
	if parent then
		i.Parent = parent
	end
	return i
end

local function paintToggle(btn, on)
	btn.Text = on and "ON" or "OFF"
	btn.BackgroundColor3 = on and COL.on or COL.off
	btn.TextColor3 = on and Color3.fromRGB(255, 255, 255) or COL.dim
end

local function addRow(parent, y, label, get, set, extra)
	mk("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 10, 0, y),
		Size = UDim2.new(1, -78, 0, 18),
		Font = Enum.Font.GothamMedium,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = COL.text,
		Text = label,
	}, parent)

	local btn = mk("TextButton", {
		Position = UDim2.new(1, -62, 0, y),
		Size = UDim2.fromOffset(52, 18),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		TextSize = 11,
		AutoButtonColor = false,
		Text = "",
	}, parent)
	mk("UICorner", { CornerRadius = UDim.new(0, 3) }, btn)
	paintToggle(btn, get())
	btn.MouseButton1Click:Connect(function()
		set(not get())
		paintToggle(btn, get())
		if extra then
			extra()
		end
		saveConfig()
	end)
	return btn
end

local function addChoiceRow(parent, y, label, text, click)
	mk("TextLabel", {
		BackgroundTransparency = 1, Position = UDim2.new(0, 10, 0, y),
		Size = UDim2.new(1, -90, 0, 18), Font = Enum.Font.GothamMedium,
		TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = COL.text, Text = label,
	}, parent)
	local btn = mk("TextButton", {
		Position = UDim2.new(1, -76, 0, y), Size = UDim2.fromOffset(66, 18),
		BorderSizePixel = 0, Font = Enum.Font.GothamBold, TextSize = 11,
		AutoButtonColor = false, BackgroundColor3 = COL.off,
		TextColor3 = COL.text, Text = text(),
	}, parent)
	mk("UICorner", { CornerRadius = UDim.new(0, 3) }, btn)
	btn.MouseButton1Click:Connect(function()
		click()
		btn.Text = text()
		saveConfig()
	end)
end

local function addFovRow(parent, y)
	mk("TextLabel", {
		BackgroundTransparency = 1, Position = UDim2.new(0, 10, 0, y),
		Size = UDim2.fromOffset(70, 18), Font = Enum.Font.GothamMedium,
		TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = COL.text, Text = "Aim FOV",
	}, parent)
	local value = mk("TextLabel", {
		BackgroundTransparency = 1, Position = UDim2.new(1, -72, 0, y),
		Size = UDim2.fromOffset(34, 18), Font = Enum.Font.GothamBold,
		TextSize = 11, TextColor3 = COL.text, Text = tostring(CFG.AimFov) .. " deg",
	}, parent)
	local function stepButton(x, text, delta)
		local btn = mk("TextButton", {
			Position = UDim2.new(1, x, 0, y), Size = UDim2.fromOffset(18, 18),
			BorderSizePixel = 0, Font = Enum.Font.GothamBold, TextSize = 12,
			BackgroundColor3 = COL.off, TextColor3 = COL.text, Text = text,
		}, parent)
		mk("UICorner", { CornerRadius = UDim.new(0, 3) }, btn)
		btn.MouseButton1Click:Connect(function()
			CFG.AimFov = math.clamp(CFG.AimFov + delta, 2, 45)
			value.Text = tostring(CFG.AimFov) .. " deg"
			S.stickyChar = nil
			Log.info("aim fov=" .. tostring(CFG.AimFov))
			saveConfig()
		end)
	end
	stepButton(-94, "-", -2)
	stepButton(-28, "+", 2)
end

local function addStrengthRow(parent, y)
	mk("TextLabel", {
		BackgroundTransparency = 1, Position = UDim2.new(0, 10, 0, y),
		Size = UDim2.fromOffset(70, 18), Font = Enum.Font.GothamMedium,
		TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = COL.text, Text = "Strength",
	}, parent)
	local value = mk("TextLabel", {
		BackgroundTransparency = 1, Position = UDim2.new(1, -72, 0, y),
		Size = UDim2.fromOffset(34, 18), Font = Enum.Font.GothamBold,
		TextSize = 11, TextColor3 = COL.text, Text = tostring(CFG.AimStrength) .. "%",
	}, parent)
	local function stepButton(x, text, delta)
		local btn = mk("TextButton", {
			Position = UDim2.new(1, x, 0, y), Size = UDim2.fromOffset(18, 18),
			BorderSizePixel = 0, Font = Enum.Font.GothamBold, TextSize = 12,
			BackgroundColor3 = COL.off, TextColor3 = COL.text, Text = text,
		}, parent)
		mk("UICorner", { CornerRadius = UDim.new(0, 3) }, btn)
		btn.MouseButton1Click:Connect(function()
			CFG.AimStrength = math.clamp(CFG.AimStrength + delta, 1, 100)
			value.Text = tostring(CFG.AimStrength) .. "%"
			Log.info("aim strength=" .. tostring(CFG.AimStrength))
			saveConfig()
		end)
	end
	stepButton(-94, "-", -1)
	stepButton(-28, "+", 1)
end

local function buildUI()
	wipeEsp()
	local folder = ensureFolder()
	local gui = mk("ScreenGui", {
		Name = blandName("SG"),
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 55,
	}, folder)
	S.gui = gui

	local root = mk("Frame", {
		-- 296 (last row top) + 18 (row height) + 10 pad.
		Size = UDim2.fromOffset(210, 324),
		Position = UDim2.new(0, 14, 0.30, 0),
		BackgroundColor3 = COL.bg,
		BackgroundTransparency = 0.04,
		BorderSizePixel = 0,
		Active = true,
		Visible = CFG.UiVisible,
	}, gui)
	S.root = root
	mk("UICorner", { CornerRadius = UDim.new(0, 6) }, root)
	mk("UIStroke", { Color = COL.stroke, Thickness = 1 }, root)
	if HOST then
		root.Position = UDim2.new()
		root.Visible = true
		root.Parent = HOST.host
		-- Our own teardown destroys folder; ride that signal so a reparented panel
		-- can never outlive the module inside the hub.
		folder.Destroying:Connect(function() pcall(function() root:Destroy() end) end)
	end

	if not HOST then
		local dragging, start, startPos
		root.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				dragging = true
				start = input.Position
				startPos = root.Position
				input.Changed:Connect(function()
					if input.UserInputState == Enum.UserInputState.End then
						dragging = false
					end
				end)
			end
		end)
		S.dragInput = UserInputService.InputChanged:Connect(function(input)
			if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
				local d = input.Position - start
				root.Position = UDim2.new(
					startPos.X.Scale,
					startPos.X.Offset + d.X,
					startPos.Y.Scale,
					startPos.Y.Offset + d.Y
				)
			end
		end)
	end

	mk("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 10, 0, 8),
		Size = UDim2.new(1, -20, 0, 16),
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = COL.text,
		Text = "OP1 ESP",
	}, root)

	mk("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 10, 0, 26),
		Size = UDim2.new(1, -20, 0, 12),
		Font = Enum.Font.Gotham,
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = COL.dim,
		Text = "RShift hide | K unload",
	}, root)

	addRow(root, 46, "Chams", function()
		return CFG.Chams
	end, function(v)
		CFG.Chams = v
	end, sweepEsp)

	addRow(root, 68, "Healthbars", function()
		return CFG.Healthbars
	end, function(v)
		CFG.Healthbars = v
	end, sweepEsp)

	addRow(root, 90, "Names", function()
		return CFG.Names
	end, function(v)
		CFG.Names = v
	end, sweepEsp)

	addRow(root, 112, "Arrows", function()
		return CFG.Arrows
	end, function(v)
		CFG.Arrows = v
	end, sweepEsp)

	addRow(root, 134, "Tracers", function()
		return CFG.Tracers
	end, function(v)
		CFG.Tracers = v
	end, sweepEsp)

	addRow(root, 156, "Utility", function()
		return CFG.Utility
	end, function(v)
		CFG.Utility = v
	end, sweepEsp)

	addRow(root, 178, "Gun duck", function()
		return CFG.GunDuck
	end, function(v)
		CFG.GunDuck = v
		applyGunDuck()
	end)

	mk("Frame", {
		Position = UDim2.new(0, 10, 0, 200),
		Size = UDim2.new(1, -20, 0, 1),
		BackgroundColor3 = COL.stroke,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
	}, root)

	addRow(root, 208, "Soft aim", function()
		return CFG.SoftAim
	end, function(v)
		CFG.SoftAim = v
		Log.info("soft aim toggle=" .. tostring(v))
		if not v then
			S.stickyChar = nil
		end
	end)

	addChoiceRow(root, 230, "Aim part", function()
		return CFG.AimPart
	end, function()
		if CFG.AimPart == "Closest" then
			CFG.AimPart = "Head"
		elseif CFG.AimPart == "Head" then
			CFG.AimPart = "Body"
		else
			CFG.AimPart = "Closest"
		end
		S.stickyChar = nil
		Log.info("aim part=" .. CFG.AimPart)
	end)

	addFovRow(root, 252)

	addStrengthRow(root, 274)

	addRow(root, 296, "Show FOV", function()
		return CFG.ShowAimFov
	end, function(v)
		CFG.ShowAimFov = v
	end)
end

buildUI()
armGunDuck()

local acc = 0
S.hb = RunService.Heartbeat:Connect(function(dt)
	if not S.alive then
		return
	end
	acc += dt
	if acc >= CFG.EspHz then
		acc = 0
		sweepEsp()
	end
end)

S.aimRender = RunService.RenderStepped:Connect(softAimStep)

S.input = UserInputService.InputBegan:Connect(function(input, gp)
	if gp or not S.alive then
		return
	end
	if input.KeyCode == Enum.KeyCode.RightShift and S.root and not HOST then
		CFG.UiVisible = not CFG.UiVisible
		S.root.Visible = CFG.UiVisible
		saveConfig()
	elseif input.KeyCode == Enum.KeyCode.K then
		teardown()
	end
end)

local function bindChar(plr)
	if S.charConns[plr] then
		S.charConns[plr]:Disconnect()
	end
	S.charConns[plr] = plr.CharacterAdded:Connect(function()
		task.defer(sweepEsp)
	end)
end

S.playerAdded = Players.PlayerAdded:Connect(function(plr)
	bindChar(plr)
end)
S.playerRemoving = Players.PlayerRemoving:Connect(function(plr)
	if S.charConns[plr] then
		S.charConns[plr]:Disconnect()
		S.charConns[plr] = nil
	end
	local char = getCharacter(plr)
	if char then clearEsp(char) end
end)
for _, plr in ipairs(Players:GetPlayers()) do
	bindChar(plr)
end

-- Rigs appear and disappear by tag, ahead of Player.Character, so drive the
-- sweep off the tag as well as off the heartbeat timer.
S.tagAdded = CollectionService:GetInstanceAddedSignal(CHAR_TAG):Connect(function()
	task.defer(sweepEsp)
end)
S.tagRemoved = CollectionService:GetInstanceRemovedSignal(CHAR_TAG):Connect(function(inst)
	clearEsp(inst)
	task.defer(sweepEsp)
end)

ESP.destroy = teardown
ESP.sweep = sweepEsp
ESP.saveConfig = saveConfig
ESP.applyGunDuck = applyGunDuck

Log.session(string.format("armed build=%s place=%s game=%s", BUILD_VERSION, tostring(game.PlaceId), tostring(game.GameId)))
