--------------------------------------------------------------------------
-- flee_facility_esp.lua — Flee the Facility v2026-10-24.1 (2026-10-24)
-- Changelog:
--   2026-10-24.1: embedded kit page, keyed autosave, standalone kit fallback.
-- Dump (LOBBY): game_dumps/893973440/
--   2026-08-11T15-28-48Z_1786462128545_3DDEDB14-E125-47F2-AB07-1A7059D29309
--
-- Re-inject safe: self-teardown on load; K = unload
-- UNLOADS_ON_INJECT: __FTF_ESP
--
-- ESP only. No aim, movement, remotes FireServer, hooks, Size, CanCollide.
-- Policy: gethui + Adornee only; Highlight/Billboard never parented into chars/map;
--   never FireServer; no locker transparency (InsideDetectionScript is crawl-only).
--
-- Role (0079 TempPlayerStatsModule children — read directly, never require):
--   IsBeast / Captured / Escaped BoolValues; Health IntValue 0–100
-- Secondary beast: char.BeastPowers folder (0189)
-- Char: Workspace.<Name> / Player.Character — R6 (Head/Torso/HRP)
--
-- Computers (0202 UpdateActionBox): CurrentMap → Trigger + ActionSign==20 (Hack)
-- ActionSign ref (header): 10 Open Door / 11 Close Door / 12 Exit / 20 Hack / 30 Trap / 31 Free
--
-- RightShift = toggle panel | K = unload
-- Execute: loadfile("flee_facility_esp.lua")()  or run in Potassium picker
--------------------------------------------------------------------------

if game.PlaceId ~= 893973440 then
	error("[FTF_ESP] wrong place " .. tostring(game.PlaceId) .. " (need 893973440)", 0)
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local LP = Players.LocalPlayer
local Camera = Workspace.CurrentCamera
local RNG = Random.new()
local PLACE_ID = 893973440

local GENV = (getgenv and getgenv()) or _G
if type(GENV) ~= "table" then
	GENV = _G
end

local GKEY = "__FTF_ESP"
local BUILD_VERSION = "2026-10-24.1"
local CONFIG_FILE = "flee_facility_esp_config.json"
local HOST = GENV.__R3ST_HOST
if GENV[GKEY] and type(GENV[GKEY].destroy) == "function" then
	pcall(GENV[GKEY].destroy)
end

local Log
do
	local ok, mod = pcall(function()
		return loadfile("log.lua")()
	end)
	if ok and type(mod) == "function" then
		Log = mod("flee_facility_esp")
	else
		local buf = {}
		Log = {
			session = function(m)
				table.insert(buf, "[session] " .. tostring(m))
				pcall(writefile, "logs/flee_facility_esp.log", table.concat(buf, "\n") .. "\n")
			end,
			step = function(m)
				table.insert(buf, "[step] " .. tostring(m))
				pcall(writefile, "logs/flee_facility_esp.log", table.concat(buf, "\n") .. "\n")
			end,
			info = function(m)
				table.insert(buf, "[info] " .. tostring(m))
				pcall(writefile, "logs/flee_facility_esp.log", table.concat(buf, "\n") .. "\n")
			end,
			warn = function(m)
				table.insert(buf, "[warn] " .. tostring(m))
				pcall(writefile, "logs/flee_facility_esp.log", table.concat(buf, "\n") .. "\n")
			end,
			err = function(m, e)
				table.insert(buf, "[err] " .. tostring(m) .. " " .. tostring(e))
				pcall(writefile, "logs/flee_facility_esp.log", table.concat(buf, "\n") .. "\n")
			end,
		}
	end
end

Log.session(string.format("boot place=%s expect=%s", tostring(game.PlaceId), tostring(PLACE_ID)))

local FTF = { build = BUILD_VERSION, embedded = false }
GENV[GKEY] = FTF

local DEFAULTS = {
	Chams = true,
	InfoHud = true,
	Skeleton = false,
	Box = false,
	Snaplines = false,
	Offscreen = true,
	ComputerEsp = true,
	ComputerChams = false,
	CompBox = false,
	CompSnap = false,
	RoleColors = true,
	EspHz = 0.1,
	CompScanHz = 2.0,
	CompMaxDist = 500,
	MaxDist = 900,
	UiVisible = true,
	Preset = "Radar",
}

if type(FTF.CFG) ~= "table" then
	FTF.CFG = {}
end
for k, v in pairs(DEFAULTS) do
	if FTF.CFG[k] == nil then
		FTF.CFG[k] = v
	end
end
local CFG = FTF.CFG

local S = {
	alive = true,
	gui = nil,
	root = nil,
	folder = nil,
	footerL = nil,
	esp = {},
	draw = {},
	compEsp = {},
	compDraw = {},
	hackCache = {},
	hackDirty = true,
	mapDescConns = {},
	hb = nil,
	input = nil,
	playerAdded = nil,
	charConns = {},
	statsConns = {},
	uiConns = {},
	dragEndConn = nil,
	mapConn = nil,
	gameStatusConn = nil,
	computersConn = nil,
	acc = 0,
	compScanAcc = 0,
	lastDiagAt = 0,
	workspaceFallbackUsed = false,
}

local saveTask
local function flushConfig()
	if not S.alive or GENV[GKEY] ~= FTF then return end
	local snapshot = {}
	for key in pairs(DEFAULTS) do snapshot[key] = CFG[key] end
	local ok, raw = pcall(HttpService.JSONEncode, HttpService, snapshot)
	if ok then pcall(writefile, CONFIG_FILE, raw) end
end

local function saveConfig()
	if not S.alive or GENV[GKEY] ~= FTF or saveTask then return end
	saveTask = task.delay(0.5, function()
		saveTask = nil
		flushConfig()
	end)
end

local function loadConfig()
	local ok, raw = pcall(readfile, CONFIG_FILE)
	if not ok or type(raw) ~= "string" then return end
	local decoded, saved = pcall(HttpService.JSONDecode, HttpService, raw)
	if not decoded or type(saved) ~= "table" then return end
	for key, default in pairs(DEFAULTS) do
		local value = saved[key]
		if type(default) == "boolean" and type(value) == "boolean" then
			CFG[key] = value
		elseif type(default) == "number" and type(value) == "number"
			and value > 0 and value < math.huge then
			CFG[key] = value
		elseif key == "Preset" and (value == "Legit" or value == "Duel"
			or value == "Radar" or value == "Ghost") then
			CFG[key] = value
		end
	end
end

local COL = {
	bg = Color3.fromRGB(10, 10, 12),
	stroke = Color3.fromRGB(32, 32, 36),
	text = Color3.fromRGB(235, 235, 240),
	dim = Color3.fromRGB(140, 140, 148),
	on = Color3.fromRGB(60, 180, 90),
	off = Color3.fromRGB(48, 48, 54),
	fill = Color3.fromRGB(255, 1, 1),
	outline = Color3.fromRGB(255, 80, 80),
	beastFill = Color3.fromRGB(255, 1, 1),
	beastOut = Color3.fromRGB(255, 80, 80),
	survFill = Color3.fromRGB(60, 120, 220),
	survOut = Color3.fromRGB(160, 200, 255),
	pcFill = Color3.fromRGB(40, 220, 255),
	pcOut = Color3.fromRGB(255, 230, 60),
	hpHi = Color3.fromRGB(70, 210, 90),
	hpLo = Color3.fromRGB(210, 60, 60),
	box = Color3.fromRGB(255, 200, 200),
	skel = Color3.fromRGB(255, 230, 230),
	snap = Color3.fromRGB(255, 120, 120),
	arrow = Color3.fromRGB(255, 180, 60),
	pcBox = Color3.fromRGB(120, 240, 255),
	pcSnap = Color3.fromRGB(255, 220, 80),
}

local R6_BONES = {
	{ "Head", "Torso" },
	{ "Torso", "HumanoidRootPart" },
	{ "Torso", "Left Arm" },
	{ "Torso", "Right Arm" },
	{ "Torso", "Left Leg" },
	{ "Torso", "Right Leg" },
}

local HAS_DRAWING = typeof(Drawing) == "table" or typeof(Drawing) == "userdata"

local function blandName(prefix)
	return prefix .. string.format("%04x", RNG:NextInteger(0, 65535))
end

local function playerDrawEnabled()
	return CFG.Skeleton or CFG.Box or CFG.Snaplines or CFG.Offscreen
end

local function compDrawEnabled()
	return CFG.CompBox or CFG.CompSnap
end

local function getParent()
	if typeof(gethui) == "function" then
		local ok, hui = pcall(gethui)
		if ok and hui then
			return hui
		end
	end
	return LP:FindFirstChildOfClass("PlayerGui") or LP:WaitForChild("PlayerGui", 5)
		or game:GetService("CoreGui")
end

local function ensureFolder()
	if S.folder and S.folder.Parent then
		return S.folder
	end
	local parent = getParent()
	if FTF.folderName then
		local old = parent:FindFirstChild(FTF.folderName)
		if old then
			old:Destroy()
		end
	end
	FTF.folderName = blandName("UI")
	local f = Instance.new("Folder")
	f.Name = FTF.folderName
	f.Parent = parent
	S.folder = f
	return f
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

local function newDraw(kind)
	if not HAS_DRAWING then
		return nil
	end
	local ok, obj = pcall(function()
		return Drawing.new(kind)
	end)
	if ok then
		return obj
	end
	return nil
end

local function destroyDraw(obj)
	if not obj then
		return
	end
	pcall(function()
		obj:Remove()
	end)
end

local function applyPreset(name)
	CFG.Preset = name
	if name == "Legit" then
		CFG.Chams = true
		CFG.InfoHud = true
		CFG.Skeleton = false
		CFG.Box = false
		CFG.Snaplines = false
		CFG.Offscreen = false
		CFG.ComputerEsp = true
		CFG.ComputerChams = false
		CFG.CompBox = false
		CFG.CompSnap = false
	elseif name == "Duel" then
		CFG.Chams = true
		CFG.InfoHud = false
		CFG.Skeleton = true
		CFG.Box = true
		CFG.Snaplines = true
		CFG.Offscreen = false
		CFG.ComputerEsp = true
		CFG.ComputerChams = false
		CFG.CompBox = false
		CFG.CompSnap = true
	elseif name == "Radar" then
		CFG.Chams = true
		CFG.InfoHud = true
		CFG.Skeleton = false
		CFG.Box = false
		CFG.Snaplines = false
		CFG.Offscreen = true
		CFG.ComputerEsp = true
		CFG.ComputerChams = false
		CFG.CompBox = false
		CFG.CompSnap = false
	elseif name == "Ghost" then
		CFG.Chams = false
		CFG.InfoHud = false
		CFG.Skeleton = true
		CFG.Box = true
		CFG.Snaplines = true
		CFG.Offscreen = true
		CFG.ComputerEsp = false
		CFG.ComputerChams = false
		CFG.CompBox = false
		CFG.CompSnap = false
	end
end

if CFG.Preset and CFG.Preset ~= "" and FTF._booted ~= true then
	applyPreset(CFG.Preset)
	FTF._booted = true
end
-- Load after the initial preset so individual saved toggle choices win.
loadConfig()
Log.session("build=" .. BUILD_VERSION)
Log.info("resumed " .. HttpService:JSONEncode(CFG))

local function statsModule(plr)
	return plr and plr:FindFirstChild("TempPlayerStatsModule")
end

local function statBool(plr, key)
	local mod = statsModule(plr)
	local v = mod and mod:FindFirstChild(key)
	if v and v:IsA("BoolValue") then
		return v.Value
	end
	return nil
end

local function statInt(plr, key)
	local mod = statsModule(plr)
	local v = mod and mod:FindFirstChild(key)
	if v and (v:IsA("IntValue") or v:IsA("NumberValue")) then
		return v.Value
	end
	return nil
end

local function isBeast(plr, char)
	if char and char:FindFirstChild("BeastPowers") then
		return true
	end
	return statBool(plr, "IsBeast") == true
end

local function hasHammerHint(char)
	if not char then
		return false
	end
	for _, ch in ipairs(char:GetChildren()) do
		if type(ch.Name) == "string" and string.match(ch.Name, "Hammer") then
			return true
		end
	end
	return false
end

local function isTriggerName(name)
	return type(name) == "string" and string.match(name, "Trigger") ~= nil
end

local function isEscaped(plr)
	return statBool(plr, "Escaped") == true
end

local function isCaptured(plr)
	return statBool(plr, "Captured") == true
end

local function playerHealth(plr, char)
	local hp = statInt(plr, "Health")
	if hp ~= nil then
		return hp, 100
	end
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		return hum.Health, math.max(hum.MaxHealth, 1)
	end
	return 0, 100
end

local function roleColors(plr, char)
	if not CFG.RoleColors then
		return COL.fill, COL.outline
	end
	if isBeast(plr, char) then
		return COL.beastFill, COL.beastOut
	end
	return COL.survFill, COL.survOut
end

local function roleTag(plr, char)
	if isBeast(plr, char) then
		return "BEAST"
	end
	if isCaptured(plr) then
		return "CAPTURED"
	end
	return "SURV"
end

local function getChar(plr)
	if plr and plr.Character then
		return plr.Character
	end
	if plr then
		return Workspace:FindFirstChild(plr.Name)
	end
	return nil
end

local function isValidTarget(plr, char, myHrp)
	if not S.alive then
		return false
	end
	if not plr or plr == LP then
		return false
	end
	if not char or not char.Parent then
		return false
	end
	if isEscaped(plr) then
		return false
	end
	if not isCaptured(plr) and not isBeast(plr, char) then
		local hum = char:FindFirstChildOfClass("Humanoid")
		local hp = statInt(plr, "Health")
		if hp ~= nil then
			if hp <= 0 then
				return false
			end
		elseif not hum or hum.Health <= 0 then
			return false
		end
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return false
	end
	if not myHrp then
		local myChar = LP.Character or Workspace:FindFirstChild(LP.Name)
		myHrp = myChar and myChar:FindFirstChild("HumanoidRootPart")
	end
	if myHrp then
		if (hrp.Position - myHrp.Position).Magnitude > CFG.MaxDist then
			return false
		end
	end
	return true
end

local function partOf(char, name)
	return char:FindFirstChild(name)
end

local function clearDrawBundle(bundle)
	if not bundle then
		return
	end
	for _, obj in pairs(bundle) do
		if type(obj) == "table" then
			for _, o in ipairs(obj) do
				destroyDraw(o)
			end
		else
			destroyDraw(obj)
		end
	end
end

local function clearEsp(char)
	local e = S.esp[char]
	if e then
		if e.conns then
			for _, c in ipairs(e.conns) do
				c:Disconnect()
			end
		end
		if e.hl then
			e.hl:Destroy()
		end
		if e.bb then
			e.bb:Destroy()
		end
		S.esp[char] = nil
	end
	if S.draw[char] then
		clearDrawBundle(S.draw[char])
		S.draw[char] = nil
	end
end

local function clearCompEsp(part)
	local e = S.compEsp[part]
	if e then
		if e.conns then
			for _, c in ipairs(e.conns) do
				c:Disconnect()
			end
		end
		if e.hl then
			e.hl:Destroy()
		end
		if e.bb then
			e.bb:Destroy()
		end
		S.compEsp[part] = nil
	end
	if S.compDraw[part] then
		clearDrawBundle(S.compDraw[part])
		S.compDraw[part] = nil
	end
end

local function wipeComputers()
	for part in pairs(S.compEsp) do
		clearCompEsp(part)
	end
	for part in pairs(S.compDraw) do
		clearCompEsp(part)
	end
end

local function wipeAll()
	for char in pairs(S.esp) do
		clearEsp(char)
	end
	for char in pairs(S.draw) do
		clearEsp(char)
	end
	wipeComputers()
	if S.folder then
		S.folder:Destroy()
		S.folder = nil
	end
	S.gui = nil
	S.root = nil
	S.footerL = nil
end

local function disconnectMapDescConns()
	for _, c in ipairs(S.mapDescConns) do
		c:Disconnect()
	end
	table.clear(S.mapDescConns)
end

local function markHackDirty()
	S.hackDirty = true
end

local function teardown()
	if not S.alive then return end
	if saveTask then
		task.cancel(saveTask)
		saveTask = nil
	end
	flushConfig()
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
	if S.mapConn then
		S.mapConn:Disconnect()
		S.mapConn = nil
	end
	if S.gameStatusConn then
		S.gameStatusConn:Disconnect()
		S.gameStatusConn = nil
	end
	if S.computersConn then
		S.computersConn:Disconnect()
		S.computersConn = nil
	end
	disconnectMapDescConns()
	table.clear(S.hackCache)
	for _, c in pairs(S.charConns) do
		c:Disconnect()
	end
	table.clear(S.charConns)
	for _, c in pairs(S.statsConns) do
		if type(c) == "table" and c.Disconnect then
			c:Disconnect()
		elseif typeof(c) == "RBXScriptConnection" then
			c:Disconnect()
		end
	end
	table.clear(S.statsConns)
	if S.dragEndConn then
		S.dragEndConn:Disconnect()
		S.dragEndConn = nil
	end
	for _, c in ipairs(S.uiConns) do
		c:Disconnect()
	end
	table.clear(S.uiConns)
	if S.shell then
		S.shell.destroy()
		S.shell = nil
	end
	wipeAll()
	Log.step("teardown")
end

local function destroy()
	teardown()
	if GENV[GKEY] == FTF then
		GENV[GKEY] = nil
	end
end
FTF.destroy = destroy
FTF.teardown = teardown

local function actionSignValue(part)
	local sign = part and part:FindFirstChild("ActionSign")
	if sign then
		local n = tonumber(sign.Value)
		if n ~= nil then
			return n, sign
		end
	end
	return nil, sign
end

local function isHackTrigger(part)
	if not part or not part:IsA("BasePart") then
		return false
	end
	if not isTriggerName(part.Name) then
		return false
	end
	local val = actionSignValue(part)
	return val == 20
end

local function getMapModel()
	local cm = ReplicatedStorage:FindFirstChild("CurrentMap")
	if cm and cm:IsA("ObjectValue") and cm.Value and typeof(cm.Value) == "Instance" then
		return cm.Value
	end
	return nil
end

local function gameStatusText()
	local gs = ReplicatedStorage:FindFirstChild("GameStatus")
	if gs and (gs:IsA("StringValue") or gs:IsA("IntValue")) then
		return tostring(gs.Value)
	end
	return "?"
end

local function computersLeftNum()
	local cl = ReplicatedStorage:FindFirstChild("ComputersLeft")
	if cl and (cl:IsA("IntValue") or cl:IsA("NumberValue")) then
		return cl.Value
	end
	return 0
end

local function isGameActiveValue()
	local iga = ReplicatedStorage:FindFirstChild("IsGameActive")
	if iga and iga:IsA("BoolValue") then
		return iga.Value
	end
	return nil
end

local function shouldWorkspaceFallback()
	local left = computersLeftNum()
	if left <= 0 then
		return false
	end
	local active = isGameActiveValue()
	if active == true then
		return true
	end
	local gs = gameStatusText()
	if gs ~= "?" and string.upper(gs) ~= "WAITING" then
		return true
	end
	return left > 0
end

local DIAG_PATH = "logs/flee_facility_esp_diag.txt"

local function writeDiag(reason)
	local map = getMapModel()
	local mapPath = nil
	local mapDescendants = 0
	local triggerNameHits = 0
	local actionSignHist = {}

	if map then
		mapPath = map:GetFullName()
		local desc = map:GetDescendants()
		mapDescendants = #desc
		for _, d in ipairs(desc) do
			if d:IsA("BasePart") and isTriggerName(d.Name) then
				triggerNameHits += 1
				local val = actionSignValue(d)
				if val ~= nil then
					local k = tostring(val)
					actionSignHist[k] = (actionSignHist[k] or 0) + 1
				end
			end
		end
	end

	local hackCacheN = 0
	for _ in pairs(S.hackCache) do
		hackCacheN += 1
	end

	local espCount, drawCount, compEspCount = 0, 0, 0
	for _ in pairs(S.esp) do
		espCount += 1
	end
	for _ in pairs(S.draw) do
		drawCount += 1
	end
	for _ in pairs(S.compEsp) do
		compEspCount += 1
	end

	local active = isGameActiveValue()
	local activeStr = active == nil and "nil" or tostring(active)

	local lines = {
		"utc=" .. os.date("!%Y-%m-%dT%H:%M:%SZ"),
		"reason=" .. tostring(reason),
		string.format(
			"place=%s gameStatus=%s isGameActive=%s computersLeft=%s",
			tostring(game.PlaceId),
			gameStatusText(),
			activeStr,
			tostring(computersLeftNum())
		),
		"map=" .. tostring(mapPath),
		"mapDescendants=" .. tostring(mapDescendants),
		"triggerNameHits=" .. tostring(triggerNameHits),
	}

	local histParts = {}
	local histKeys = {}
	for k in pairs(actionSignHist) do
		table.insert(histKeys, k)
	end
	table.sort(histKeys, function(a, b)
		return (tonumber(a) or 0) < (tonumber(b) or 0)
	end)
	for _, k in ipairs(histKeys) do
		table.insert(histParts, string.format("[%s]=%d", k, actionSignHist[k]))
	end
	table.insert(lines, "actionSignHist= " .. table.concat(histParts, " "))
	table.insert(lines, "hackCache=" .. tostring(hackCacheN))
	table.insert(lines, "workspaceFallbackUsed=" .. tostring(S.workspaceFallbackUsed))
	table.insert(lines, "players:")

	for _, plr in ipairs(Players:GetPlayers()) do
		local char = getChar(plr)
		local mod = statsModule(plr)
		local ib = statBool(plr, "IsBeast")
		local ibStr = ib == nil and "nil" or tostring(ib)
		local bp = char and char:FindFirstChild("BeastPowers") ~= nil
		local cap = statBool(plr, "Captured")
		local esc = statBool(plr, "Escaped")
		local hp = statInt(plr, "Health")
		local hammer = hasHammerHint(char)
		local espYes = char and S.esp[char] ~= nil and "yes" or "no"
		local valid = isValidTarget(plr, char, nil)
		table.insert(lines, string.format(
			"  %s IsBeast=%s BeastPowers=%s Captured=%s Escaped=%s Health=%s"
				.. " hasMod=%s hammer=%s char=%s esp=%s valid=%s",
			plr.Name,
			ibStr,
			tostring(bp),
			tostring(cap),
			tostring(esc),
			tostring(hp),
			tostring(mod ~= nil),
			tostring(hammer),
			char and char.Name or "nil",
			espYes,
			valid and "yes" or "no"
		))
	end

	table.insert(lines, string.format("espCount=%d drawCount=%d compEspCount=%d",
		espCount, drawCount, compEspCount))

	local body = table.concat(lines, "\n")
	pcall(writefile, DIAG_PATH, body)
	Log.info(string.format(
		"diag reason=%s hackCache=%d triggerHits=%d map=%s fallback=%s",
		tostring(reason),
		hackCacheN,
		triggerNameHits,
		tostring(mapPath ~= nil),
		tostring(S.workspaceFallbackUsed)
	))
end

local function maybeWriteDiag(reason)
	local now = os.clock()
	if reason == "boot" or reason == "map" or reason == "manual" then
		writeDiag(reason)
		S.lastDiagAt = now
		return
	end
	if now - (S.lastDiagAt or 0) >= 3 then
		writeDiag(reason or "refresh")
		S.lastDiagAt = now
	end
end

local function refreshHackCache(diagReason)
	local prevSize = 0
	for _ in pairs(S.hackCache) do
		prevSize += 1
	end

	table.clear(S.hackCache)
	S.workspaceFallbackUsed = false
	local map = getMapModel()
	if map then
		for _, d in ipairs(map:GetDescendants()) do
			if isHackTrigger(d) then
				S.hackCache[d] = true
			end
		end
	end

	if next(S.hackCache) == nil and shouldWorkspaceFallback() then
		S.workspaceFallbackUsed = true
		for _, d in ipairs(Workspace:GetDescendants()) do
			if isHackTrigger(d) then
				S.hackCache[d] = true
			end
		end
	end

	local newSize = 0
	for _ in pairs(S.hackCache) do
		newSize += 1
	end
	if newSize ~= prevSize then
		Log.info(string.format("pcs cache %d (was %d)", newSize, prevSize))
	end

	maybeWriteDiag(diagReason or "refresh")
end

local function collectHackTriggers()
	return S.hackCache
end

local function bindMapDescendants(map)
	disconnectMapDescConns()
	if not map then
		return
	end
	table.insert(S.mapDescConns, map.DescendantAdded:Connect(function(inst)
		if isTriggerName(inst.Name) then
			markHackDirty()
		end
	end))
	table.insert(S.mapDescConns, map.DescendantRemoving:Connect(function(inst)
		if isTriggerName(inst.Name) then
			S.hackCache[inst] = nil
			clearCompEsp(inst)
			markHackDirty()
		end
	end))
end

local function onMapChanged()
	wipeComputers()
	bindMapDescendants(getMapModel())
	refreshHackCache("map")
end

local function computersLeftText()
	local cl = ReplicatedStorage:FindFirstChild("ComputersLeft")
	if cl and (cl:IsA("IntValue") or cl:IsA("NumberValue")) then
		return tostring(cl.Value)
	end
	return "?"
end

local function selfBeastText()
	local beast = isBeast(LP, LP.Character or Workspace:FindFirstChild(LP.Name))
	return beast and "yes" or "no"
end

local function updateFooter()
	if not S.footerL then
		return
	end
	S.footerL.Text = string.format(
		"%s  |  PCs:%s  |  Beast:%s",
		gameStatusText(),
		computersLeftText(),
		selfBeastText()
	)
end

local function ensureEsp(char, plr, trusted, myHrp)
	if not trusted and not isValidTarget(plr, char, myHrp) then
		clearEsp(char)
		return
	end

	local folder = ensureFolder()
	local e = S.esp[char]
	if not e then
		e = { conns = {} }
		S.esp[char] = e
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			table.insert(e.conns, hum.Died:Connect(function()
				clearEsp(char)
			end))
		end
		table.insert(e.conns, char.Destroying:Connect(function()
			clearEsp(char)
		end))
	end

	local fillC, outC = roleColors(plr, char)

	if CFG.Chams then
		if not e.hl or not e.hl.Parent then
			local hl = Instance.new("Highlight")
			hl.Name = blandName("HL")
			hl.Adornee = char
			hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			hl.Parent = folder
			e.hl = hl
			e.lastFill = nil
			e.lastOut = nil
		end
		e.hl.Adornee = char
		e.hl.Enabled = true
		if e.lastFill ~= fillC then
			e.hl.FillColor = fillC
			e.lastFill = fillC
		end
		if e.lastOut ~= outC then
			e.hl.OutlineColor = outC
			e.lastOut = outC
		end
		e.hl.FillTransparency = 0.35
		e.hl.OutlineTransparency = 0.2
	elseif e.hl then
		e.hl.Enabled = false
	end

	local head = partOf(char, "Head") or char:FindFirstChild("HumanoidRootPart")
	local hp, hpMax = playerHealth(plr, char)
	if CFG.InfoHud and head then
		if not e.bb or not e.bb.Parent then
			local bb = Instance.new("BillboardGui")
			bb.Name = blandName("NT")
			bb.Adornee = head
			bb.AlwaysOnTop = true
			bb.Size = UDim2.fromOffset(168, 46)
			bb.StudsOffset = Vector3.new(0, 2.6, 0)
			bb.MaxDistance = CFG.MaxDist
			bb.Parent = folder

			local nameL = mk("TextLabel", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 14),
				Position = UDim2.fromOffset(0, 0),
				Font = Enum.Font.GothamBold,
				TextSize = 12,
				TextColor3 = COL.text,
				TextStrokeTransparency = 0.4,
				Text = "",
			}, bb)

			local infoL = mk("TextLabel", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 12),
				Position = UDim2.fromOffset(0, 14),
				Font = Enum.Font.Gotham,
				TextSize = 11,
				TextColor3 = COL.dim,
				TextStrokeTransparency = 0.5,
				Text = "",
			}, bb)

			local track = mk("Frame", {
				BackgroundColor3 = Color3.fromRGB(12, 12, 14),
				BackgroundTransparency = 0.2,
				BorderSizePixel = 0,
				Size = UDim2.new(1, -20, 0, 4),
				Position = UDim2.new(0, 10, 0, 30),
			}, bb)
			mk("UICorner", { CornerRadius = UDim.new(0, 2) }, track)
			local fill = mk("Frame", {
				BackgroundColor3 = COL.hpHi,
				BorderSizePixel = 0,
				Size = UDim2.fromScale(1, 1),
			}, track)
			mk("UICorner", { CornerRadius = UDim.new(0, 2) }, fill)

			e.bb = bb
			e.nameL = nameL
			e.infoL = infoL
			e.fill = fill
		end

		local hrp = char:FindFirstChild("HumanoidRootPart")
		local dist = 0
		if hrp and myHrp then
			dist = (hrp.Position - myHrp.Position).Magnitude
		end
		local pct = math.clamp(hp / math.max(hpMax, 1), 0, 1)
		local tag = roleTag(plr, char)
		e.nameL.Text = string.format("%s [%s]", plr.DisplayName, tag)
		if tag == "CAPTURED" then
			e.infoL.TextColor3 = COL.dim
			e.infoL.Text = string.format("%dm  |  CAPTURED", math.floor(dist + 0.5))
		else
			e.infoL.TextColor3 = COL.dim
			e.infoL.Text = string.format("%dm  |  HP %d", math.floor(dist + 0.5), math.floor(hp + 0.5))
		end
		e.fill.Size = UDim2.fromScale(pct, 1)
		e.fill.BackgroundColor3 = COL.hpLo:Lerp(COL.hpHi, pct)
		e.bb.Adornee = head
		e.bb.Enabled = true
	elseif e.bb then
		e.bb.Enabled = false
	end
end

local function ensureDraw(char, plr, trusted, myHrp)
	if not HAS_DRAWING or not playerDrawEnabled() then
		return
	end
	if not trusted and not isValidTarget(plr, char, myHrp) then
		if S.draw[char] then
			clearDrawBundle(S.draw[char])
			S.draw[char] = nil
		end
		return
	end

	local d = S.draw[char]
	if not d then
		d = {
			bones = {},
			box = {},
			snap = nil,
			arrow = nil,
		}
		if CFG.Skeleton then
			for i = 1, #R6_BONES do
				local line = newDraw("Line")
				if line then
					line.Thickness = 1.4
					line.Color = COL.skel
					line.Transparency = 0.15
					line.Visible = false
					d.bones[i] = line
				end
			end
		end
		if CFG.Box then
			for i = 1, 4 do
				local line = newDraw("Line")
				if line then
					line.Thickness = 1.5
					line.Color = COL.box
					line.Transparency = 0.1
					line.Visible = false
					d.box[i] = line
				end
			end
		end
		if CFG.Snaplines then
			local line = newDraw("Line")
			if line then
				line.Thickness = 1
				line.Color = COL.snap
				line.Transparency = 0.35
				line.Visible = false
				d.snap = line
			end
		end
		if CFG.Offscreen then
			local tri = newDraw("Triangle")
			if tri then
				tri.Filled = true
				tri.Color = COL.arrow
				tri.Transparency = 0.15
				tri.Visible = false
				d.arrow = tri
			end
		end
		S.draw[char] = d
	end
end

local function worldToView(pos)
	local v, onScreen = Camera:WorldToViewportPoint(pos)
	return Vector2.new(v.X, v.Y), onScreen, v.Z
end

local function updateDraw(char, plr, trusted, myHrp)
	if not HAS_DRAWING or not playerDrawEnabled() then
		return
	end
	local d = S.draw[char]
	if not d then
		return
	end
	if not trusted and not isValidTarget(plr, char, myHrp) then
		clearDrawBundle(d)
		S.draw[char] = nil
		return
	end

	local hrp = char:FindFirstChild("HumanoidRootPart")
	local head = partOf(char, "Head")
	if not hrp then
		return
	end

	local hp, hpMax = playerHealth(plr, char)
	local pct = math.clamp(hp / math.max(hpMax, 1), 0, 1)
	local fillC = roleColors(plr, char)
	local col = COL.hpLo:Lerp(fillC, pct)

	local vp = Camera.ViewportSize
	local centerBottom = Vector2.new(vp.X * 0.5, vp.Y - 2)
	local hrp2, onScreen, z = worldToView(hrp.Position)

	if CFG.Skeleton and d.bones then
		for i, pair in ipairs(R6_BONES) do
			local line = d.bones[i]
			if line then
				local a = partOf(char, pair[1])
				local b = partOf(char, pair[2])
				if a and b then
					local p1, o1 = worldToView(a.Position)
					local p2, o2 = worldToView(b.Position)
					if o1 and o2 then
						line.From = p1
						line.To = p2
						line.Color = col
						line.Visible = true
					else
						line.Visible = false
					end
				else
					line.Visible = false
				end
			end
		end
	elseif d.bones then
		for _, line in pairs(d.bones) do
			line.Visible = false
		end
	end

	if CFG.Box and d.box and head and onScreen and z > 0 then
		local top = worldToView((head.CFrame * CFrame.new(0, 0.85, 0)).Position)
		local bot = worldToView((hrp.CFrame * CFrame.new(0, -3.1, 0)).Position)
		local h = math.abs(bot.Y - top.Y)
		local w = h * 0.5
		local cx = (top.X + bot.X) * 0.5
		local y1, y2 = math.min(top.Y, bot.Y), math.max(top.Y, bot.Y)
		local x1, x2 = cx - w * 0.5, cx + w * 0.5
		local edges = {
			{ Vector2.new(x1, y1), Vector2.new(x2, y1) },
			{ Vector2.new(x2, y1), Vector2.new(x2, y2) },
			{ Vector2.new(x2, y2), Vector2.new(x1, y2) },
			{ Vector2.new(x1, y2), Vector2.new(x1, y1) },
		}
		for i = 1, 4 do
			local line = d.box[i]
			if line then
				line.From = edges[i][1]
				line.To = edges[i][2]
				line.Color = col
				line.Visible = true
			end
		end
	elseif d.box then
		for _, line in pairs(d.box) do
			line.Visible = false
		end
	end

	if CFG.Snaplines and d.snap and onScreen and z > 0 then
		d.snap.From = centerBottom
		d.snap.To = hrp2
		d.snap.Color = COL.snap
		d.snap.Visible = true
	elseif d.snap then
		d.snap.Visible = false
	end

	if CFG.Offscreen and d.arrow then
		if not onScreen or z <= 0 then
			local dir = Vector2.new(hrp2.X - vp.X * 0.5, hrp2.Y - vp.Y * 0.5)
			if dir.Magnitude < 1e-3 then
				dir = Vector2.new(0, -1)
			else
				dir = dir.Unit
			end
			local margin = 28
			local edge = Vector2.new(
				math.clamp(vp.X * 0.5 + dir.X * (vp.X * 0.45), margin, vp.X - margin),
				math.clamp(vp.Y * 0.5 + dir.Y * (vp.Y * 0.45), margin, vp.Y - margin)
			)
			local ang = math.atan2(dir.Y, dir.X)
			local tip = edge
			local left = tip - Vector2.new(math.cos(ang - 0.5) * 14, math.sin(ang - 0.5) * 14)
			local right = tip - Vector2.new(math.cos(ang + 0.5) * 14, math.sin(ang + 0.5) * 14)
			d.arrow.PointA = tip
			d.arrow.PointB = left
			d.arrow.PointC = right
			d.arrow.Color = fillC
			d.arrow.Visible = true
		else
			d.arrow.Visible = false
		end
	elseif d.arrow then
		d.arrow.Visible = false
	end
end

local function ensureCompDraw(part)
	if not HAS_DRAWING or not compDrawEnabled() or not CFG.ComputerEsp then
		return
	end
	if not S.hackCache[part] then
		if S.compDraw[part] then
			clearDrawBundle(S.compDraw[part])
			S.compDraw[part] = nil
		end
		return
	end

	local d = S.compDraw[part]
	if not d then
		d = { box = {}, snap = nil }
		if CFG.CompBox then
			for i = 1, 4 do
				local line = newDraw("Line")
				if line then
					line.Thickness = 1.5
					line.Color = COL.pcBox
					line.Transparency = 0.1
					line.Visible = false
					d.box[i] = line
				end
			end
		end
		if CFG.CompSnap then
			local line = newDraw("Line")
			if line then
				line.Thickness = 1
				line.Color = COL.pcSnap
				line.Transparency = 0.35
				line.Visible = false
				d.snap = line
			end
		end
		S.compDraw[part] = d
	end
end

local function updateCompDraw(part)
	if not HAS_DRAWING or not compDrawEnabled() then
		return
	end
	local d = S.compDraw[part]
	if not d or not S.hackCache[part] then
		if d then
			clearDrawBundle(d)
			S.compDraw[part] = nil
		end
		return
	end

	local pos = part.Position
	local center2, onScreen, z = worldToView(pos)
	local vp = Camera.ViewportSize
	local centerBottom = Vector2.new(vp.X * 0.5, vp.Y - 2)

	if CFG.CompBox and d.box and onScreen and z > 0 then
		local sz = 18
		local x1, y1 = center2.X - sz, center2.Y - sz
		local x2, y2 = center2.X + sz, center2.Y + sz
		local edges = {
			{ Vector2.new(x1, y1), Vector2.new(x2, y1) },
			{ Vector2.new(x2, y1), Vector2.new(x2, y2) },
			{ Vector2.new(x2, y2), Vector2.new(x1, y2) },
			{ Vector2.new(x1, y2), Vector2.new(x1, y1) },
		}
		for i = 1, 4 do
			local line = d.box[i]
			if line then
				line.From = edges[i][1]
				line.To = edges[i][2]
				line.Color = COL.pcBox
				line.Visible = true
			end
		end
	elseif d.box then
		for _, line in pairs(d.box) do
			line.Visible = false
		end
	end

	if CFG.CompSnap and d.snap and onScreen and z > 0 then
		d.snap.From = centerBottom
		d.snap.To = center2
		d.snap.Color = COL.pcSnap
		d.snap.Visible = true
	elseif d.snap then
		d.snap.Visible = false
	end
end

local function ensureCompEsp(part)
	if not CFG.ComputerEsp then
		clearCompEsp(part)
		return
	end
	if not S.hackCache[part] then
		clearCompEsp(part)
		return
	end

	local folder = ensureFolder()
	local e = S.compEsp[part]
	if not e then
		e = { conns = {} }
		S.compEsp[part] = e
		local _, sign = actionSignValue(part)
		if sign then
			table.insert(e.conns, sign:GetPropertyChangedSignal("Value"):Connect(function()
				if not isHackTrigger(part) then
					clearCompEsp(part)
					S.hackCache[part] = nil
				end
				markHackDirty()
			end))
		end
		table.insert(e.conns, part.Destroying:Connect(function()
			S.hackCache[part] = nil
			clearCompEsp(part)
		end))
	end

	if CFG.ComputerChams then
		if not e.hl or not e.hl.Parent then
			local hl = Instance.new("Highlight")
			hl.Name = blandName("HL")
			hl.Adornee = part
			hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			hl.Parent = folder
			e.hl = hl
		end
		e.hl.Adornee = part
		e.hl.Enabled = true
		e.hl.FillColor = COL.pcFill
		e.hl.OutlineColor = COL.pcOut
		e.hl.FillTransparency = 0.45
		e.hl.OutlineTransparency = 0.15
	elseif e.hl then
		e.hl:Destroy()
		e.hl = nil
	end

	if CFG.ComputerEsp then
		if not e.bb or not e.bb.Parent then
			local bb = Instance.new("BillboardGui")
			bb.Name = blandName("PC")
			bb.Adornee = part
			bb.AlwaysOnTop = true
			bb.Size = UDim2.fromOffset(52, 20)
			bb.StudsOffset = Vector3.new(0, 1.2, 0)
			bb.MaxDistance = CFG.CompMaxDist
			bb.Parent = folder

			mk("TextLabel", {
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				Font = Enum.Font.GothamBold,
				TextSize = 9,
				TextColor3 = COL.pcOut,
				TextStrokeTransparency = 0.35,
				Text = "PC",
			}, bb)

			e.bb = bb
		end
		e.bb.MaxDistance = CFG.CompMaxDist
		e.bb.Adornee = part
		e.bb.Enabled = true
	elseif e.bb then
		e.bb.Enabled = false
	end
end

local function collectChars(myHrp)
	local set = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LP then
			local char = getChar(plr)
			if char and isValidTarget(plr, char, myHrp) then
				set[char] = plr
			end
		end
	end
	return set
end

local function sweepPlayers()
	if not S.alive then
		return
	end
	Camera = Workspace.CurrentCamera
	local myChar = LP.Character or Workspace:FindFirstChild(LP.Name)
	local myHrp = myChar and myChar:FindFirstChild("HumanoidRootPart")
	local live = collectChars(myHrp)
	local drawOn = playerDrawEnabled()
	for char, plr in pairs(live) do
		ensureEsp(char, plr, true, myHrp)
		if drawOn then
			ensureDraw(char, plr, true, myHrp)
			updateDraw(char, plr, true, myHrp)
		end
	end
	for char in pairs(S.esp) do
		if not live[char] then
			clearEsp(char)
		end
	end
	if drawOn then
		for char in pairs(S.draw) do
			if not live[char] then
				clearEsp(char)
			end
		end
	else
		for char in pairs(S.draw) do
			clearEsp(char)
		end
	end
end

local function updateComputerVisuals()
	if not CFG.ComputerEsp then
		wipeComputers()
		return
	end
	local live = S.hackCache
	local compDrawOn = compDrawEnabled()
	for part in pairs(live) do
		if part.Parent then
			ensureCompEsp(part)
			if compDrawOn then
				ensureCompDraw(part)
				updateCompDraw(part)
			end
		else
			S.hackCache[part] = nil
			clearCompEsp(part)
		end
	end
	for part in pairs(S.compEsp) do
		if not live[part] then
			clearCompEsp(part)
		end
	end
	if compDrawOn then
		for part in pairs(S.compDraw) do
			if not live[part] then
				clearCompEsp(part)
			end
		end
	else
		for part in pairs(S.compDraw) do
			clearCompEsp(part)
		end
	end
end

local function sweep()
	if not S.alive then
		return
	end
	markHackDirty()
	S.compScanAcc = 0
	S.hackDirty = false
	refreshHackCache()
	sweepPlayers()
	updateComputerVisuals()
	updateFooter()
end
FTF.sweep = sweep
FTF.applyPreset = applyPreset
FTF.diag = function()
	writeDiag("manual")
end

-- Preserve the legacy toggle/preset invalidation paths; only the controls move.
local function resetDrawings()
	for char in pairs(S.draw) do
		clearDrawBundle(S.draw[char])
		S.draw[char] = nil
	end
	for part in pairs(S.compDraw) do
		clearDrawBundle(S.compDraw[part])
		S.compDraw[part] = nil
	end
end

local function applyToggle()
	resetDrawings()
	for part in pairs(S.compEsp) do
		local e = S.compEsp[part]
		if e and e.hl and not CFG.ComputerChams then
			e.hl:Destroy()
			e.hl = nil
		end
	end
	sweep()
end

local function rebuildUI()
	local folder = ensureFolder()
	local Kit = HOST and HOST.ui
	if not Kit then
		for _, path in ipairs({ "../scripts/r3st_ui.lua", "r3st_ui.lua", "scripts/r3st_ui.lua" }) do
			local ok, loaded = pcall(function() return loadfile(path)() end)
			if ok and type(loaded) == "table" then Kit = loaded; break end
		end
	end
	assert(Kit and Kit.SHELL_CONTRACT == "1", "R3ST shell contract mismatch")
	local Shell = Kit.moduleShell({
		id = "flee-facility", title = "Flee Facility ESP", version = BUILD_VERSION,
		subtitle = "Player and computer ESP", gameId = 372226183, placeId = PLACE_ID,
		hostGlobal = HOST, standaloneSize = Vector2.new(760, 560), keep = { folder },
		cfg = CFG, save = saveConfig, saveDelay = 0, live = {}, conns = S.uiConns,
		onUnload = destroy,
	})
	S.shell, S.root = Shell, Shell.root
	FTF.embedded = Shell.hosted
	local W, page = Shell.W, Shell.page("Main")
	W.section(page, "Flee Facility ESP")
	W.note(page, "RShift hide | K unload | Draw=" .. (HAS_DRAWING and "yes" or "no"))
	local rows = {
		{ "Chams", "Chams" },
		{ "Info HUD", "InfoHud" },
		{ "Skeleton", "Skeleton" },
		{ "Box", "Box" },
		{ "Snaplines", "Snaplines" },
		{ "Offscreen", "Offscreen" },
		{ "Computer ESP", "ComputerEsp" },
		{ "Computer chams", "ComputerChams" },
		{ "Role colors", "RoleColors" },
	}
	for _, row in ipairs(rows) do
		W.toggle(page, { label = row[1], key = row[2], set = applyToggle, stateText = true })
	end
	W.section(page, "Presets")
	for _, name in ipairs({ "Legit", "Duel", "Radar", "Ghost" }) do
		local button = W.button(page, name, nil, function()
			applyPreset(name)
			resetDrawings()
			sweep()
			saveConfig()
		end, true)
		-- Keep the selected preset visible without rebuilding the owning shell.
		table.insert(Shell.W.live, function()
			button.BackgroundColor3 = CFG.Preset == name and COL.on or COL.off
		end)
	end
	S.footerL = W.statusRow(page, function()
		return string.format("%s  |  PCs:%s  |  Beast:%s",
			gameStatusText(), computersLeftText(), selfBeastText())
	end)
	updateFooter()
	if not Shell.hosted then S.root.Visible = CFG.UiVisible end
	Shell.hideBind(function()
		CFG.UiVisible = not CFG.UiVisible
		S.root.Visible = CFG.UiVisible
		saveConfig()
	end)
	Shell.ready()
end

local function bindStats(plr)
	local key = plr.UserId
	if S.statsConns[key] then
		if type(S.statsConns[key]) == "table" and S.statsConns[key].Disconnect then
			S.statsConns[key]:Disconnect()
		elseif typeof(S.statsConns[key]) == "RBXScriptConnection" then
			S.statsConns[key]:Disconnect()
		end
		S.statsConns[key] = nil
	end

	local function hookMod(mod)
		if not mod or mod.Name ~= "TempPlayerStatsModule" then
			return
		end
		local bag = {}
		for _, name in ipairs({ "IsBeast", "Captured", "Escaped", "Health" }) do
			local v = mod:FindFirstChild(name)
			if v then
				table.insert(bag, v:GetPropertyChangedSignal("Value"):Connect(function()
					task.defer(sweep)
				end))
			end
		end
		table.insert(bag, mod.ChildAdded:Connect(function(ch)
			if ch.Name == "IsBeast" or ch.Name == "Captured" or ch.Name == "Escaped"
				or ch.Name == "Health" then
				task.defer(function()
					bindStats(plr)
					sweep()
				end)
			end
		end))
		S.statsConns[key] = {
			Disconnect = function()
				for _, c in ipairs(bag) do
					c:Disconnect()
				end
			end,
		}
	end

	local mod = statsModule(plr)
	if mod then
		hookMod(mod)
	else
		S.statsConns[key] = plr.ChildAdded:Connect(function(ch)
			if ch.Name == "TempPlayerStatsModule" then
				hookMod(ch)
				task.defer(sweep)
			end
		end)
	end
end

local function bindPlayer(plr)
	if S.charConns[plr] then
		S.charConns[plr]:Disconnect()
	end
	S.charConns[plr] = plr.CharacterAdded:Connect(function()
		task.defer(sweep)
	end)
	bindStats(plr)
end

local function bindWorldSignals()
	local cm = ReplicatedStorage:FindFirstChild("CurrentMap")
	if cm and cm:IsA("ObjectValue") then
		S.mapConn = cm.Changed:Connect(function()
			onMapChanged()
		end)
		onMapChanged()
	end

	local gs = ReplicatedStorage:FindFirstChild("GameStatus")
	if gs then
		S.gameStatusConn = gs:GetPropertyChangedSignal("Value"):Connect(function()
			updateFooter()
		end)
	end

	local cl = ReplicatedStorage:FindFirstChild("ComputersLeft")
	if cl then
		S.computersConn = cl:GetPropertyChangedSignal("Value"):Connect(function()
			markHackDirty()
			updateFooter()
		end)
	end
end

-- boot
S.alive = true
rebuildUI()
bindWorldSignals()

S.hb = RunService.Heartbeat:Connect(function(dt)
	if not S.alive then
		return
	end
	S.acc += dt
	S.compScanAcc += dt
	if S.hackDirty or S.compScanAcc >= CFG.CompScanHz then
		S.compScanAcc = 0
		S.hackDirty = false
		refreshHackCache()
	end
	if S.acc >= CFG.EspHz then
		S.acc = 0
		sweepPlayers()
		updateComputerVisuals()
		updateFooter()
	end
end)

S.input = UserInputService.InputBegan:Connect(function(input, gp)
	if gp then
		return
	end
	if input.KeyCode == Enum.KeyCode.K then
		destroy()
		Log.info("unloaded via K")
	end
end)

S.playerAdded = Players.PlayerAdded:Connect(bindPlayer)
for _, plr in ipairs(Players:GetPlayers()) do
	bindPlayer(plr)
end

sweep()
writeDiag("boot")

local targetN = 0
do
	local myChar = LP.Character or Workspace:FindFirstChild(LP.Name)
	local myHrp = myChar and myChar:FindFirstChild("HumanoidRootPart")
	for _ in pairs(collectChars(myHrp)) do
		targetN += 1
	end
end
local pcN = 0
for _ in pairs(collectHackTriggers()) do
	pcN += 1
end

Log.info(string.format(
	"armed preset=%s drawing=%s targets=%d pcs=%d map=%s beast=%s",
	tostring(CFG.Preset),
	tostring(HAS_DRAWING),
	targetN,
	pcN,
	tostring(getMapModel() ~= nil),
	selfBeastText()
))

pcall(writefile, "flee_facility_esp_status.txt", string.format(
	"OK place=%s preset=%s drawing=%s targets=%d pcs=%d armed=1 t=%s",
	tostring(game.PlaceId),
	tostring(CFG.Preset),
	tostring(HAS_DRAWING),
	targetN,
	pcN,
	tostring(os.time())
))

print(string.format(
	"[FTF_ESP] armed preset=%s drawing=%s targets=%d pcs=%d place=%s",
	tostring(CFG.Preset),
	tostring(HAS_DRAWING),
	targetN,
	pcN,
	tostring(game.PlaceId)
))
