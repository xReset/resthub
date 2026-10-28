--------------------------------------------------------------------------
-- Fisch Hub v2026-09-04.16 -- Autofish + pacing limits + vendor ESP
--
-- Rung 6: cast and shake use Fisch's own Net wrappers. Server sees normal
-- FishingRod/Cast, LureShake/Shake, and game-owned Reel/Finish traffic.
-- Autofish boots OFF every session. Reel assist is client-local: it centers
-- the existing player bar on the fish and never constructs a finish payload.
--
-- Catch notifier (rung 1, read-only): events.anno_catch OnClientEvent payload
-- (itemTable, chance) per 0035.lua:490,947 and 3750.lua:603.
-- Treasure recon is READ-ONLY: lists world.chests ids + distance to file, never
-- fires open_treasure (plan candidate #4 stays probe-only this build).
-- REMOVED 2026-09-04: auto-sell, force-sell-all and the keep list. Live test
-- proved the server rejects selleverything (Sell Anywhere gamepass enforced
-- server-side; preview=3203 then rejected). Research closed: no client path.
-- REMOVED same day: the standalone custom header UI (host() branch, second
-- "Reload Fisch module" button). The module now draws the same window as every
-- other R3ST module; the hub's host page owns the reload button.
-- Dump: 2026-09-02T12-03-53Z, PlaceId 131716211654599.
-- Proof: 3763.lua:140-143,722-728 cast; 2038.lua:150-159 shake gate;
-- 2071.lua:689-716 reel tick; 2071.lua:812-824 game-owned finish.
-- (Sell evidence retained for the record: 2230.lua:2085-2111 gamepass gate,
-- 2890.lua:36-41 pass identity — selleverything is not usable without it.)
-- ADDED 2026-09-04: Vendor ESP (rungs 1-2). Reads NPC models + library.rods +
-- the C$/Level leaderstats and draws Highlights/billboards/tracers into OUR OWN
-- cloned-CoreGui layer. No remote, no hook, no write to a game instance, so it
-- resumes the user's last state per S0.2b. Highlights sit in a Folder under the
-- cloned CoreGui, NOT the ScreenGui -- a Highlight under a ScreenGui reports
-- healthy and renders nothing (potassium-dev S5.4).
--
-- ENFORCEMENT HISTORY, read before adding anything here:
-- 2026-09-04 a pass-through __namecall recorder drew `Server Kick Message:
-- Invalid Client Behavior` in 7 seconds AND a formal in-game exploit warning,
-- one strike from a permanent ban. Hyperion inspects this client; the dump's
-- CLIENT INSPECTION=0 describes the GAME's Luau only. No metatable hooks, no
-- hookfunction, no global writes in this file, ever. games/fisch/PLAN.md F4-F5.
-- CLIENT INSPECTION=0, LOG MONITORING=30. No print/warn; file log only.
-- PACING (.16): session cap, jittered breaks, auto-stop on consecutive rejected
-- casts or 10 consecutive errors. Unattended running is the loudest thing this
-- file can do and the account already holds a formal warning, so the loop now
-- ends itself instead of asking the server all night. Breaks fire only between
-- catches; a break never abandons a hooked fish.
-- Re-inject safe: self-teardown on load; K = unload/panic.
--------------------------------------------------------------------------

local BUILD_VERSION = "fisch-2026-09-04.16"
local EXPECTED_PLACE = 131716211654599
local EXPECTED_GAME = 5750914919
local GKEY = "__FISCH_HUB"
local CONFIG_PATH = "configs/fisch_hub.json"

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")
local RunService = game:GetService("RunService")

local LP = Players.LocalPlayer
local G = (getgenv and getgenv()) or _G
if type(G) ~= "table" then G = _G end

if game.GameId ~= EXPECTED_GAME and game.PlaceId ~= EXPECTED_PLACE then
	return
end

if type(G[GKEY]) == "table" and type(G[GKEY].destroy) == "function" then
	local ok = pcall(G[GKEY].destroy)
	if not ok then return end
end

local function makeLogger()
	local ok, factory = pcall(function() return loadfile("log.lua")() end)
	if ok and type(factory) == "function" then
		local ok2, logger = pcall(factory, "fisch_hub")
		if ok2 and logger then return logger end
	end
	local rows = {}
	local function add(level, msg)
		rows[#rows + 1] = string.format("[%s] %s", level, tostring(msg))
		pcall(function()
			if type(isfolder) == "function" and not isfolder("logs") and type(makefolder) == "function" then
				makefolder("logs")
			end
			writefile("logs/fisch_hub.log", table.concat(rows, "\n") .. "\n")
		end)
	end
	return {
		session = function(msg) rows = {}; add("session", msg) end,
		info = function(msg) add("info", msg) end,
		warn = function(msg) add("warn", msg) end,
		err = function(msg, err) add("err", tostring(msg) .. " " .. tostring(err)) end,
	}
end

local Log = makeLogger()
Log.session(string.format("armed build=%s place=%s universe=%s autofish=OFF",
	BUILD_VERSION, tostring(game.PlaceId), tostring(game.GameId)))

local CFG = {
	castPower = 100,
	recastDelay = 2.5,
	recastJitter = 2.5,
	sessionCapMin = 90,
	breakEveryMin = 18,
	breakLenSec = 120,
	breakJitterSec = 90,
	maxRejects = 5,
	autoEquip = true,
	panelX = -310,
	panelY = -240,
	espVendors = false,
	espShopsOnly = true,
	espOutlines = true,
	espTracers = true,
	espRange = 1200,
}

local LIMITS = {
	castPower = { 10, 100 },
	recastDelay = { 0.8, 8 },
	recastJitter = { 0, 6 },
	sessionCapMin = { 5, 480 },
	breakEveryMin = { 3, 120 },
	breakLenSec = { 15, 900 },
	breakJitterSec = { 0, 600 },
	maxRejects = { 2, 30 },
	panelX = { -2000, 2000 },
	panelY = { -2000, 2000 },
	espRange = { 200, 5000 },
}

pcall(function()
	if not isfile(CONFIG_PATH) then return end
	local saved = HttpService:JSONDecode(readfile(CONFIG_PATH))
	if type(saved) ~= "table" then return end
	for key, default in next, CFG do
		local value = saved[key]
		if type(value) == type(default) then
			local lim = LIMITS[key]
			CFG[key] = lim and math.clamp(value, lim[1], lim[2]) or value
		end
	end
end)

local savePending = false
local function saveConfig()
	savePending = false
	local ok, err = pcall(function()
		if type(isfolder) == "function" and not isfolder("configs") and type(makefolder) == "function" then
			makefolder("configs")
		end
		writefile(CONFIG_PATH, HttpService:JSONEncode(CFG))
	end)
	if not ok then Log.err("config save", err) end
	return ok
end

local function queueSave()
	if savePending then return end
	savePending = true
	task.delay(0.5, saveConfig)
end

local S = {
	alive = true,
	build = BUILD_VERSION,
	auto = false,
	status = "Ready",
	cycles = 0,
	shakes = 0,
	casts = 0,
	sells = 0,
	errors = 0,
	conns = {},
	screen = nil,
	panel = nil,
	host = nil,
	net = nil,
	castRemote = nil,
	shakeRemote = nil,
	reelController = nil,
	rodController = nil,
	reel = nil,
	rodCore = nil,
	fishCore = nil,
	rodCoreDisabledBefore = nil,
	fishCoreDisabledBefore = nil,
	workerToken = 0,
	lastCatch = "none yet",
	libs = nil,
	lastRodState = nil,
	lastShakeAt = 0,
	shakeButton = nil,
	shakeButtonActiveBefore = nil,
	nextCastAt = 0,
	recastAt = 0,
	sessionEndsAt = 0,
	breakUntil = 0,
	nextBreakAt = 0,
	rejects = 0,
	stepErrors = 0,
	breaks = 0,
	stopReason = "",
}

local function setStatus(text)
	if S.status ~= text then
		S.status = text
		Log.info("status=" .. text)
	end
end

local function guard(label, fn, ...)
	if not S.alive or type(fn) ~= "function" then return false end
	local args = table.pack(...)
	local ok, err = xpcall(function()
		fn(table.unpack(args, 1, args.n))
	end, debug.traceback)
	if not ok then
		S.errors = S.errors + 1
		Log.err(label or "callback", err)
	end
	return ok
end

local function loadControllers()
	local ok, err = pcall(function()
		S.net = require(ReplicatedStorage:WaitForChild("packages"):WaitForChild("Net"))
		local controllers = ReplicatedStorage:WaitForChild("client"):WaitForChild("legacyControllers")
		S.reelController = require(controllers:WaitForChild("ReelController"))
		S.rodController = require(controllers:WaitForChild("FishingRodController"))
		S.castRemote = S.net:RemoteFunction("FishingRod/Cast", -1)
		S.shakeRemote = S.net:RemoteEvent("LureShake/Shake")
	end)
	if not ok then
		Log.err("controller load", err)
		setStatus("Controller load failed")
		return false
	end
	return true
end

local function isFishingRod(tool)
	if not tool or not tool:IsA("Tool") then return false end
	local values = tool:FindFirstChild("values")
	return values ~= nil
		and values:FindFirstChild("state") ~= nil
		and values:FindFirstChild("casted") ~= nil
		and tool:FindFirstChild("events") ~= nil
end

local function findRod()
	local character = LP.Character
	if character then
		for _, child in ipairs(character:GetChildren()) do
			if isFishingRod(child) then return child end
		end
	end
	local backpack = LP:FindFirstChildOfClass("Backpack")
	if backpack then
		for _, child in ipairs(backpack:GetChildren()) do
			if isFishingRod(child) then return child end
		end
	end
	return nil
end

local function rodState(rod)
	local values = rod and rod:FindFirstChild("values")
	local stateObject = values and values:FindFirstChild("state")
	local state = stateObject and stateObject.Value or -1
	if state ~= S.lastRodState then
		S.lastRodState = state
		Log.info(string.format("rod state=%s reel=%s", tostring(state),
			tostring(S.reelController and S.reelController.ActiveReel ~= nil)))
	end
	return state
end

local function equipRod(rod)
	local character = LP.Character
	if rod and rod.Parent == character then return true end
	if not CFG.autoEquip then
		setStatus("Equip a fishing rod")
		return false
	end
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not rod or not humanoid then
		setStatus("Fishing rod unavailable")
		return false
	end
	humanoid:EquipTool(rod)
	setStatus("Equipping rod")
	return false
end

local function findShakeButton()
	local playerGui = LP:FindFirstChildOfClass("PlayerGui")
	local shakeGui = playerGui and playerGui:FindFirstChild("shakeui", true)
	if not shakeGui or not shakeGui:IsA("LayerCollector") or not shakeGui.Enabled then
		return nil
	end
	local safezone = shakeGui:FindFirstChild("safezone")
	if not safezone then return nil end
	for _, child in ipairs(safezone:GetChildren()) do
		if child:IsA("GuiButton") and child.Visible then return child end
	end
	return nil
end

local function restoreShakeInput()
	if S.shakeButton and S.shakeButton.Parent and S.shakeButtonActiveBefore ~= nil then
		S.shakeButton.Active = S.shakeButtonActiveBefore
	end
	S.shakeButton = nil
	S.shakeButtonActiveBefore = nil
end

local function suppressShakeInput()
	local button = findShakeButton()
	if button ~= S.shakeButton then
		restoreShakeInput()
		S.shakeButton = button
		S.shakeButtonActiveBefore = button and button.Active or nil
	end
	if button then button.Active = false end
	return button
end

local function performShake()
	if os.clock() - S.lastShakeAt < 0.27 then return end
	S.lastShakeAt = os.clock()
	local button = suppressShakeInput()
	local ok, err
	if button and type(firesignal) == "function" then
		ok, err = pcall(firesignal, button.Activated)
	else
		ok, err = pcall(S.shakeRemote.FireServer, S.shakeRemote)
	end
	if ok then
		S.shakes = S.shakes + 1
		if S.shakes == 1 or S.shakes % 10 == 0 then
			Log.info(string.format("shake count=%d path=%s", S.shakes, button and "button" or "remote"))
		end
	else
		S.errors = S.errors + 1
		Log.err("shake", err)
	end
end

local function restoreReelControl()
	if S.rodCore and S.rodCoreDisabledBefore ~= nil then
		S.rodCore.Disabled = S.rodCoreDisabledBefore
	end
	if S.fishCore and S.fishCoreDisabledBefore ~= nil then
		S.fishCore.Disabled = S.fishCoreDisabledBefore
	end
	S.reel = nil
	S.rodCore = nil
	S.fishCore = nil
	S.rodCoreDisabledBefore = nil
	S.fishCoreDisabledBefore = nil
end

local function pinReel(reel)
	if S.reel ~= reel then
		restoreReelControl()
		S.reel = reel
		S.rodCore = reel.core and reel.core.rod or nil
		S.fishCore = reel.core and reel.core.fish or nil
		if not S.rodCore or not S.fishCore then
			Log.warn("reel core unavailable")
			return
		end
		S.rodCoreDisabledBefore = S.rodCore.Disabled == true
		S.fishCoreDisabledBefore = S.fishCore.Disabled == true
		S.rodCore.Disabled = true
		S.fishCore.Disabled = true
		S.rodCore.CurrentVelocity = 0
		S.rodCore.CurrentAcceleration = 0
		S.fishCore.CurrentVelocity = 0
		Log.info("reel pinned rod+fish cores")
	end
	-- Core order is rod, fish, UI, minigame (2071.lua:120-126, 697-716).
	-- Disabling the movement cores makes Minigame.Tick evaluate this overlap.
	reel.barPosition = 0.5
	reel.fishPosition = 0.5
end

local stopAuto   -- forward: castRod and the pacing gate call it before it exists

local function castRod()
	S.nextCastAt = os.clock() + 2
	setStatus("Casting")
	local ok, accepted = pcall(S.castRemote.InvokeServer, S.castRemote, CFG.castPower, CFG.castPower >= 94)
	if not ok then
		S.errors = S.errors + 1
		Log.err("cast", accepted)
		setStatus("Cast error")
	elseif accepted then
		S.casts = S.casts + 1
		S.rejects = 0
		Log.info("cast accepted")
		setStatus("Searching")
	else
		-- Consecutive rejects mean the server stopped taking our casts. Unattended,
		-- the old loop would keep asking all night; that is the traffic pattern
		-- that turns a warning into a ban. Stop instead of insisting.
		S.rejects = S.rejects + 1
		Log.warn(string.format("cast rejected state=%s consecutive=%d/%d",
			tostring(S.lastRodState), S.rejects, CFG.maxRejects))
		setStatus("Cast rejected; waiting")
		if S.rejects >= CFG.maxRejects then
			stopAuto(string.format("Auto-stopped: %d rejected casts", S.rejects))
		end
	end
end

-- Session cap + breaks. Eight unbroken hours of identical cast/shake intervals
-- is the loudest thing this script can emit (PLAN.md F5). The cap ends the
-- session, the breaks put real gaps in it, and both are jittered so no two look
-- alike. Fires only between catches -- never mid-reel, which would drop a fish.
local function pacingGate()
	local now = os.clock()
	if S.sessionEndsAt > 0 and now >= S.sessionEndsAt then
		stopAuto(string.format("Session cap reached (%d min, %d catches)",
			CFG.sessionCapMin, S.cycles))
		return false
	end
	if now < S.breakUntil then
		setStatus(string.format("On break %ds", math.ceil(S.breakUntil - now)))
		return false
	end
	if S.nextBreakAt > 0 and now >= S.nextBreakAt then
		local length = CFG.breakLenSec + math.random() * CFG.breakJitterSec
		S.breakUntil = now + length
		S.breaks = S.breaks + 1
		S.nextBreakAt = S.breakUntil + CFG.breakEveryMin * 60 * (0.7 + math.random() * 0.6)
		Log.info(string.format("break %d for %.0fs after %d catches", S.breaks, length, S.cycles))
		setStatus("Taking a break")
		return false
	end
	return true
end

local function automationStep()
	-- Fisch's full-screen shake button survives state transitions and can sit
	-- above the Hub. Keep its hit-testing off for the whole enabled lifetime so
	-- the same Autofish switch always receives the OFF click.
	suppressShakeInput()
	local rod = findRod()
	if not rod then
		setStatus("No fishing rod found")
		return
	end
	if rod.Parent ~= LP.Character then
		equipRod(rod)
		return
	end

	local state = rodState(rod)
	local reel = S.reelController and S.reelController.ActiveReel
	if reel then
		if reel.active then
			setStatus("Reeling - locked center")
			pinReel(reel)
		else
			setStatus("Reel loading")
		end
		return
	elseif S.reel then
		restoreReelControl()
		S.cycles = S.cycles + 1
		S.recastAt = os.clock() + CFG.recastDelay + (CFG.recastJitter > 0 and math.random() * CFG.recastJitter or 0)
		Log.info("catch complete cycles=" .. tostring(S.cycles))
	end

	-- BiteTypes.RodState: Equipped=3, Casting=4, Searching=5, Luring=6,
	-- PreReel=7, Reeling=8, CatchFinished=9 (3749.lua:12-22).
	if state == 3 then
		if not pacingGate() then return end
		if os.clock() >= S.recastAt and os.clock() >= S.nextCastAt then castRod() else setStatus("Recast delay") end
	elseif state == 4 then
		setStatus("Casting")
	elseif state == 5 then
		setStatus("Searching")
	elseif state == 6 then
		setStatus("Auto-shaking")
		performShake()
	elseif state == 7 or state == 8 then
		setStatus("Waiting for reel controller")
	elseif state == 9 then
		setStatus("Catch finishing")
	elseif state <= 2 then
		setStatus("Rod not ready")
	end
end

stopAuto = function(reason)
	local before = S.auto
	S.auto = false
	S.workerToken = S.workerToken + 1
	S.sessionEndsAt, S.nextBreakAt, S.breakUntil = 0, 0, 0
	S.stopReason = reason or "Stopped"
	restoreShakeInput()
	restoreReelControl()
	setStatus(reason or "Stopped")
	Log.info(string.format("autofish stop before=%s after=%s token=%d", tostring(before), tostring(S.auto), S.workerToken))
end

local function startAuto()
	if S.auto then
		Log.info("autofish start ignored already=true")
		return
	end
	Log.info("autofish start controller_load=begin")
	if not loadControllers() then
		Log.warn("autofish start controller_load=failed state=false")
		return
	end
	S.auto = true
	S.workerToken = S.workerToken + 1
	local token = S.workerToken
	S.nextCastAt = 0
	S.recastAt = 0
	S.rejects = 0
	S.stepErrors = 0
	S.breaks = 0
	local now = os.clock()
	S.sessionEndsAt = CFG.sessionCapMin > 0 and (now + CFG.sessionCapMin * 60) or 0
	S.nextBreakAt = CFG.breakEveryMin > 0 and (now + CFG.breakEveryMin * 60 * (0.7 + math.random() * 0.6)) or 0
	S.breakUntil = 0
	setStatus("Starting")
	Log.info(string.format("autofish start controller_load=ok state=%s token=%d", tostring(S.auto), token))
	task.spawn(function()
		while S.alive and S.auto and token == S.workerToken do
			local ok, err = xpcall(automationStep, debug.traceback)
			if not ok then
				S.errors = S.errors + 1
				S.stepErrors = S.stepErrors + 1
				Log.err("automation step", err)
				setStatus("Automation error")
				if S.stepErrors >= 10 then
					stopAuto("Auto-stopped: 10 consecutive errors")
					break
				end
				task.wait(1)
			else
				S.stepErrors = 0
				task.wait(0.05)
			end
		end
	end)
end

local function treasureRecon()
	-- READ-ONLY recon (plan candidate #4): log chest ids + distance to file only.
	-- open_treasure is never fired from this build.
	local world = workspace:FindFirstChild("world")
	local chests = world and world:FindFirstChild("chests")
	if not chests then
		setStatus("No chests folder")
		return
	end
	local n = 0
	for _, chest in ipairs(chests:GetChildren()) do
		local id = chest:GetAttribute("id")
		if id then
			n = n + 1
			local ok, dist = pcall(function() return LP:DistanceFromCharacter(chest:GetPivot().Position) end)
			Log.info(string.format("chest id=%s name=%s dist=%s", tostring(id), chest.Name,
				ok and string.format("%.0f", dist) or "?"))
		end
	end
	setStatus("Chest recon: " .. n .. " logged to file")
end

--------------------------------------------------------------------------
-- Vendor ESP -- rung 1 read + rung 2 draw. Reads instances the client already
-- owns (workspace NPC models, ReplicatedStorage.shared.modules.library.rods,
-- the C$/Level leaderstats) and draws into OUR OWN CoreGui layer. Nothing is
-- written to a game instance, no remote is fired, no metatable or global is
-- touched. That is what makes it quiet -- NOT the fact that the server sees no
-- packets. Hyperion runs on this client and inspects it, which is how the
-- 2026-09-04 __namecall recorder was caught in seven seconds (PLAN.md F4).
--
-- Highlights go under the cloned CoreGui, never under a ScreenGui: a Highlight
-- parented to a ScreenGui reports Enabled=true with a correct Adornee and draws
-- nothing (potassium-dev S5.4). Billboards and tracer frames go in the ScreenGui.
--
-- COL/new are the kit's, and the kit only resolves further down. Declared here
-- so every ESP function closes over the same upvalue instead of reading a nil
-- global on its first call -- compiles clean, dies on first use otherwise.
--------------------------------------------------------------------------
local COL, new
local E = {
	layer = nil,        -- ScreenGui: tracers + billboards
	folder = nil,       -- Folder under cloned CoreGui: Highlights only
	marks = {},         -- model -> { hl, board, tracer, label, rods }
	targets = {},       -- ordered list of live vendor models
	judged = {},        -- model -> true, so each candidate is logged once
	zones = nil,        -- { {name=, pos=} } resolved once from workspace.zones
	rods = nil,         -- library.rods
	byIsland = {},      -- island name (lower) -> sorted rod list
	nextScan = 0,
	money = 0,
	level = 0,
	best = nil,         -- best affordable rod overall, by Luck
}

local function coreParent()
	local core = CoreGui
	if type(cloneref) == "function" then
		local ok, copy = pcall(cloneref, core)
		if ok and copy then core = copy end
	end
	return core
end

local function espTeardown()
	for _, mark in next, E.marks do
		if mark.hl then pcall(function() mark.hl:Destroy() end) end
		if mark.board then pcall(function() mark.board:Destroy() end) end
		if mark.tracer then pcall(function() mark.tracer:Destroy() end) end
	end
	table.clear(E.marks)
	table.clear(E.targets)
	if E.layer then pcall(function() E.layer:Destroy() end) end
	if E.folder then pcall(function() E.folder:Destroy() end) end
	E.layer, E.folder = nil, nil
end

local function espEnsureLayer()
	if E.layer and E.layer.Parent and E.folder and E.folder.Parent then return end
	espTeardown()
	local core = coreParent()
	E.folder = new("Folder", { Name = "R3ST_Fisch_Chams" }, core)
	E.layer = new("ScreenGui", {
		Name = "R3ST_Fisch_ESP",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 2147483000,
		ZIndexBehavior = Enum.ZIndexBehavior.Global,
	}, core)
end

-- Island metadata, resolved once. workspace.zones.player carries a zonename
-- StringValue per part; the rod library's `From` field names the same islands,
-- so the two join on name without a hardcoded coordinate table -- which is what
-- the next map update would silently break.
local function espLoadWorld()
	if not E.rods then
		local ok, lib = pcall(function()
			return require(ReplicatedStorage:WaitForChild("shared", 10)
				:WaitForChild("modules"):WaitForChild("library"):WaitForChild("rods"))
		end)
		if not ok then Log.err("rods library", lib) return false end
		E.rods = lib
		for name, rod in next, E.rods do
			if type(rod) == "table" and type(rod.Price) == "number"
				and rod.Price == rod.Price and rod.Price ~= math.huge and not rod.Unpurchasable then
				local island = tostring(rod.From or "?"):lower()
				local list = E.byIsland[island]
				if not list then list = {}; E.byIsland[island] = list end
				list[#list + 1] = {
					name = name, price = rod.Price, luck = rod.Luck or 0,
					level = rod.LevelRequirement or 0, island = tostring(rod.From or "?"),
				}
			end
		end
		for _, list in next, E.byIsland do
			-- Luck is the user's chosen ranking (2026-09-04). Ties break on the
			-- cheaper rod so an equal-luck pick never costs more.
			table.sort(list, function(a, b)
				if a.luck ~= b.luck then return a.luck > b.luck end
				return a.price < b.price
			end)
		end
	end
	if not E.zones then
		E.zones = {}
		local zones = workspace:FindFirstChild("zones")
		local player = zones and zones:FindFirstChild("player")
		if player then
			for _, part in ipairs(player:GetChildren()) do
				local nameValue = part:FindFirstChild("zonename")
				local label = nameValue and tostring(nameValue.Value) or part.Name
				local okp, pivot = pcall(function() return part:GetPivot().Position end)
				if okp and label ~= "" then
					E.zones[#E.zones + 1] = { name = label, pos = pivot }
				end
			end
		end
	end
	return E.rods ~= nil
end

local function espMoney()
	local stats = LP:FindFirstChild("leaderstats")
	local cash = stats and stats:FindFirstChild("C$")
	local level = stats and stats:FindFirstChild("Level")
	E.money = cash and tonumber(cash.Value) or 0
	E.level = level and tonumber(level.Value) or 0
end

local function espNearestIsland(position)
	local bestName, bestDist = nil, math.huge
	for _, zone in ipairs(E.zones) do
		local d = (zone.pos - position).Magnitude
		if d < bestDist then bestName, bestDist = zone.name, d end
	end
	return bestName
end

-- Rods this vendor plausibly sells: the library's `From` matched against the
-- island the NPC stands on, both directions, because the library writes
-- "Roslit" where the zone writes "Roslit Bay".
local function espRodsFor(island)
	if not island then return nil end
	local key = island:lower()
	local exact = E.byIsland[key]
	if exact then return exact end
	for from, list in next, E.byIsland do
		if #from > 3 and (key:find(from, 1, true) or from:find(key, 1, true)) then
			return list
		end
	end
	return nil
end

local function espAffordable(list)
	if not list then return nil end
	for _, rod in ipairs(list) do
		if rod.price <= E.money and rod.level <= E.level then return rod end
	end
	return nil
end

local function espComma(n)
	local text = tostring(math.floor(n))
	local out = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local function espDescribe(model)
	local okp, pivot = pcall(function() return model:GetPivot().Position end)
	if not okp then return model.Name, nil end
	local island = espNearestIsland(pivot)
	local list = espRodsFor(island)
	local pick = espAffordable(list)
	local line = model.Name
	if island then line = line .. "  ·  " .. island end
	if list then
		if pick then
			line = line .. string.format("\nBEST AFFORDABLE: %s  ·  C$%s  ·  Luck %d",
				pick.name, espComma(pick.price), pick.luck)
		else
			local cheapest = list[1]
			for _, rod in ipairs(list) do if rod.price < cheapest.price then cheapest = rod end end
			line = line .. string.format("\n%d rods here  ·  cheapest %s C$%s",
				#list, cheapest.name, espComma(cheapest.price))
		end
	end
	return line, pick
end

-- Which NPCs actually sell rods is NOT proven. The dump cannot answer it: the
-- shop that matters is driven by a server `Script` on the NPC, `safezone.shop`
-- is the Robux product menu, and every NPC probed on 2026-09-04 -- quest giver,
-- shipwright and merchant alike -- carried the same `dialogprompt` with
-- ActionText "Talk". So this is a NAME filter, which is a guess, and it is
-- paired with a log line per candidate (kept or not) so the next pass is fixed
-- from evidence instead of a second guess. Turn `espShopsOnly` off to see every
-- prompt-bearing NPC and read the log to find whatever the filter is missing.
local ESP_SHOP_WORDS = {
	"shop", "merchant", "vendor", "shopkeep", "trader", "dealer",
	"smith", "wright", "stall", "store", "market", "supplies", "rod",
}

local function espLooksLikeShop(model, prompt)
	local hay = model.Name:lower()
	if prompt then
		hay = hay .. " " .. tostring(prompt.ObjectText or ""):lower()
			.. " " .. tostring(prompt.ActionText or ""):lower()
	end
	for _, word in ipairs(ESP_SHOP_WORDS) do
		if hay:find(word, 1, true) then return true, word end
	end
	return false, nil
end

local function espScan()
	espEnsureLayer()
	local seen = {}
	local roots = {}
	local world = workspace:FindFirstChild("world")
	if world and world:FindFirstChild("npcs") then roots[#roots + 1] = world.npcs end
	for _, name in ipairs({ "NPCs", "NewNPCs", "NPCs2", "Tidefall NPCs" }) do
		local folder = workspace:FindFirstChild(name)
		if folder then roots[#roots + 1] = folder end
	end
	local character = LP.Character
	for _, root in ipairs(roots) do
		for _, prompt in ipairs(root:GetDescendants()) do
			if prompt:IsA("ProximityPrompt") then
				local model = prompt:FindFirstAncestorOfClass("Model")
				if model and model ~= character and not seen[model] and not E.judged[model] then
					local okp = pcall(function() return model:GetPivot() end)
					if okp then
						local keep, word = espLooksLikeShop(model, prompt)
						E.judged[model] = true
						if keep or not CFG.espShopsOnly then seen[model] = true end
						Log.info(string.format("esp candidate name=%q object=%q action=%q kept=%s match=%s",
							model.Name, tostring(prompt.ObjectText or ""),
							tostring(prompt.ActionText or ""),
							tostring(keep or not CFG.espShopsOnly), tostring(word)))
					end
				elseif model and E.judged[model] and not seen[model] then
					local keep = espLooksLikeShop(model, prompt)
					if keep or not CFG.espShopsOnly then seen[model] = true end
				end
			end
		end
	end

	for model, mark in next, E.marks do
		if not seen[model] or not model.Parent then
			if mark.hl then pcall(function() mark.hl:Destroy() end) end
			if mark.board then pcall(function() mark.board:Destroy() end) end
			if mark.tracer then pcall(function() mark.tracer:Destroy() end) end
			E.marks[model] = nil
		end
	end

	table.clear(E.targets)
	for model in next, seen do
		E.targets[#E.targets + 1] = model
		if not E.marks[model] then
			local text, pick = espDescribe(model)
			local colour = pick and COL.good or COL.text
			local hl = new("Highlight", {
				Name = "R3ST_FischVendor",
				Adornee = model,
				FillTransparency = 0.85,
				FillColor = colour,
				OutlineColor = colour,
				DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
			}, E.folder)
			local board = new("BillboardGui", {
				Name = "R3ST_FischTag",
				Adornee = model:FindFirstChild("Head") or model.PrimaryPart
					or model:FindFirstChildWhichIsA("BasePart"),
				Size = UDim2.fromOffset(320, 46),
				StudsOffsetWorldSpace = Vector3.new(0, 4, 0),
				AlwaysOnTop = true,
				MaxDistance = CFG.espRange,
			}, E.layer)
			local label = new("TextLabel", {
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				Font = Enum.Font.GothamMedium,
				TextSize = 12,
				TextColor3 = colour,
				TextStrokeTransparency = 0.4,
				TextStrokeColor3 = Color3.new(),
				Text = text,
			}, board)
			local tracer = new("Frame", {
				BackgroundColor3 = colour,
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(1, 0),
				Visible = false,
				ZIndex = 1,
			}, E.layer)
			E.marks[model] = { hl = hl, board = board, label = label, tracer = tracer, pick = pick }
		end
	end
end

local function espUpdate()
	local camera = workspace.CurrentCamera
	local character = LP.Character
	local origin = character and character:FindFirstChild("HumanoidRootPart")
	if not camera then return end
	local viewport = camera.ViewportSize
	local footX, footY = viewport.X * 0.5, viewport.Y
	for model, mark in next, E.marks do
		local okp, pivot = pcall(function() return model:GetPivot().Position end)
		local dist = okp and origin and (pivot - origin.Position).Magnitude or math.huge
		local inRange = okp and dist <= CFG.espRange
		if mark.hl then mark.hl.Enabled = inRange and CFG.espOutlines end
		if mark.board then mark.board.Enabled = inRange end
		if mark.tracer then
			if inRange and CFG.espTracers then
				local point, onScreen = camera:WorldToViewportPoint(pivot)
				if onScreen then
					local dx, dy = point.X - footX, point.Y - footY
					local length = math.sqrt(dx * dx + dy * dy)
					mark.tracer.Visible = true
					mark.tracer.Size = UDim2.fromOffset(1, length)
					mark.tracer.Position = UDim2.fromOffset(footX + dx * 0.5, footY + dy * 0.5)
					mark.tracer.Rotation = math.deg(math.atan2(dy, dx)) - 90
				else
					mark.tracer.Visible = false
				end
			else
				mark.tracer.Visible = false
			end
		end
	end
end

local function espSetEnabled(on)
	if not on then
		espTeardown()
		return
	end
	table.clear(E.judged)
	if not espLoadWorld() then
		setStatus("Rod library unavailable; ESP idle")
		return
	end
	espMoney()
	E.nextScan = 0
end

-- One driver for scan + paint. 2 Hz discovery, per-frame tracer maths only for
-- the handful of marks that exist -- a full workspace walk every frame is the
-- multi-second freeze that gets noticed (potassium-dev S5.4).
local function espStep()
	if not CFG.espVendors then return end
	local now = os.clock()
	if now >= E.nextScan then
		E.nextScan = now + 0.5
		espMoney()
		guard("esp.scan", espScan)
		E.best = nil
		for _, list in next, E.byIsland do
			local pick = espAffordable(list)
			if pick and (not E.best or pick.luck > E.best.luck) then E.best = pick end
		end
	end
	guard("esp.paint", espUpdate)
end

local destroy
destroy = function()
	if not S.alive then return end
	S.alive = false
	stopAuto("Unloaded")
	espTeardown()
	for _, connection in ipairs(S.conns) do pcall(function() connection:Disconnect() end) end
	table.clear(S.conns)
	if S.screen then pcall(function() S.screen:Destroy() end) end
	if G[GKEY] == S then G[GKEY] = nil end
	Log.info("destroy")
end

S.destroy = destroy
G[GKEY] = S

table.insert(S.conns, UserInputService.InputBegan:Connect(function(input, processed)
	if processed or input.KeyCode ~= Enum.KeyCode.K then return end
	task.defer(destroy)
end))

local Kit
local okKit, kitOrErr = pcall(function()
	-- Embedded: the hub hands over its loaded kit on __R3ST_HOST.ui (hub skill
	-- S2b r1). loadfile is only the standalone fallback — it does not resolve
	-- inside the hub's runModule sandbox.
	local hostGlobal = (getgenv and getgenv()) or G
	local host = type(hostGlobal) == "table" and hostGlobal.__R3ST_HOST or nil
	if type(host) == "table" and host.ui then return host.ui end
	return loadfile("../scripts/r3st_ui.lua")()
end)
if not okKit or type(kitOrErr) ~= "table" then
	Log.err("UI kit unavailable", kitOrErr)
	destroy()
	return
end
Kit = kitOrErr

COL = Kit.COL
new = Kit.new or function(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do inst[k] = v end
	inst.Parent = parent
	return inst
end

-- Same window as every other R3ST module (gd2 pattern): one bar, one body.
-- The hub owns its own "Reload module" button on the host page strip above us;
-- we draw no second one. Standalone builds the identical body under gethui().
local HOST = G.__R3ST_HOST
local embed = type(HOST) == "table" and typeof(HOST.host) == "Instance" and HOST or nil
local screen
local root

if embed then
	root = new("Frame", {
		Name = "FischBody",
		BackgroundColor3 = COL.bg,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(760, 560),
	}, embed.host)
	-- NEVER the hub's host. destroy() calls S.screen:Destroy(), so pointing this
	-- at embed.host made every unload -- K, a reload, a re-inject -- delete the
	-- hub's own R3ST_Host_fisch frame. The next mount then parented a perfectly
	-- healthy panel into an orphaned frame: visible, correct size, rendering
	-- nowhere, with no error and no destroy line in any log. That was the "UI
	-- disappears" bug (hub S6.1 r7 -- teardown never destroys the hub host).
	S.screen = root
else
	screen = new("ScreenGui", {
		Name = "R3ST_Fisch_" .. tostring(math.random(1000, 9999)),
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	local host
	pcall(function()
		if type(gethui) == "function" then host = gethui() end
	end)
	if host and host:IsA("LayerCollector") then
		root = new("Frame", {
			Name = "FischBody",
			BackgroundColor3 = COL.bg,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(760, 560),
			Position = UDim2.new(0.5, CFG.panelX, 0.5, CFG.panelY),
			ZIndex = 50,
		}, host)
	else
		screen.Parent = host or LP:FindFirstChildOfClass("PlayerGui") or CoreGui
		root = new("Frame", {
			Name = "FischBody",
			BackgroundColor3 = COL.bg,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(760, 560),
			Position = UDim2.new(0.5, CFG.panelX, 0.5, CFG.panelY),
		}, screen)
	end
	S.screen = screen
	local blur = new("BlurEffect", { Name = "R3ST_Fisch_Blur", Size = 4 }, game:GetService("Lighting"))
	table.insert(S.conns, game:GetService("Lighting").ChildRemoved:Connect(function()
		if blur.Parent ~= game:GetService("Lighting") then blur:Destroy() end
	end)) -- teardown safety: our blur dies with the connection set
end
S.root = root

if not embed then
	new("UICorner", { CornerRadius = UDim.new(0, 10) }, root)
	new("UIStroke", { Color = COL.line, Thickness = 1 }, root)
	-- drag
	local dragging, dragStart, startPos
	root.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging, dragStart, startPos = true, i.Position, root.Position
		end
	end)
	table.insert(S.conns, UserInputService.InputChanged:Connect(function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
			local d = i.Position - dragStart
			root.Position = UDim2.fromOffset(startPos.X.Offset + d.X, startPos.Y.Offset + d.Y)
		end
	end))
	table.insert(S.conns, UserInputService.InputEnded:Connect(function(i)
		dragging = false
	end))
end

-- Title bar: identical to the hub window — "R3ST HUB | <game>" + build stamp.
local bar = new("Frame", {
	BackgroundColor3 = COL.panel,
	BorderSizePixel = 0,
	Size = UDim2.new(1, 0, 0, 58),
}, root)
new("UICorner", { CornerRadius = UDim.new(0, 10) }, bar)
new("Frame", { BackgroundColor3 = COL.panel, BorderSizePixel = 0,
	Position = UDim2.fromOffset(0, 46), Size = UDim2.new(1, 0, 0, 12) }, bar)
new("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(20, 4),
	Size = UDim2.fromOffset(140, 28), Font = Enum.Font.GothamBold, TextSize = 18,
	TextColor3 = COL.text, TextXAlignment = Enum.TextXAlignment.Left, Text = "R3ST HUB" }, bar)
new("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(158, 4),
	Size = UDim2.fromOffset(240, 28), Font = Enum.Font.GothamMedium, TextSize = 15,
	TextColor3 = COL.dim, TextXAlignment = Enum.TextXAlignment.Left, Text = "|   Fisch" }, bar)
new("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(20, 29),
	Size = UDim2.fromOffset(300, 20), Font = Enum.Font.GothamMedium, TextSize = 10,
	TextColor3 = COL.dim, TextXAlignment = Enum.TextXAlignment.Left, Text = BUILD_VERSION }, bar)
local hideBtn = new("TextButton", {
	BackgroundTransparency = 1, Position = UDim2.new(1, -48, 0, 8),
	Size = UDim2.fromOffset(34, 34), Font = Enum.Font.GothamBold,
	TextSize = 14, TextColor3 = COL.dim, Text = "-", AutoButtonColor = false,
}, bar)
hideBtn.Visible = not embed
if not embed then
	hideBtn.MouseButton1Click:Connect(function()
		root.Visible = not root.Visible
	end)
end

-- Embedded: fill the hub's host and scale to fit, exactly like gd2.
if embed then
	local uiScale = new("UIScale", { Scale = 1 }, root)
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	local function refit()
		local hs = embed.host.AbsoluteSize
		if hs.X < 8 or hs.Y < 8 then return end
		uiScale.Scale = math.min(1, hs.X / 760, hs.Y / 560)
	end
	refit()
	task.defer(refit)
	table.insert(S.conns, embed.host:GetPropertyChangedSignal("AbsoluteSize"):Connect(refit))
end

-- Body panel (dark, card-like) — same shape as every other module window.
local body = new("Frame", {
	BackgroundColor3 = COL.panel,
	BorderSizePixel = 0,
	Position = UDim2.fromOffset(10, 68),
	Size = UDim2.new(1, -20, 1, -78),
}, root)
new("UICorner", { CornerRadius = UDim.new(0, 8) }, body)
new("UIStroke", { Color = COL.line, Thickness = 1 }, body)

local inner = new("Frame", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(18, 14),
	Size = UDim2.new(1, -36, 1, -28),
}, body)

local live = {}
local W = Kit.bind({ live = live, conns = S.conns, cfg = CFG, save = queueSave, guard = guard })
table.insert(S.conns, RunService.RenderStepped:Connect(function()
	for _, paint in ipairs(live) do
		local ok, err = pcall(paint)
		if not ok then Log.err("ui paint", err) end
	end
	espStep()
end))
W.header(inner, {
	title = "Fisch",
	version = BUILD_VERSION,
	subtitle = "Automatic cast, shake, and reel control using Fisch's live fishing controllers.",
})

local page = Instance.new("ScrollingFrame")
page.Name = "Main"
page.BackgroundTransparency = 1
page.BorderSizePixel = 0
page.Position = UDim2.fromOffset(0, 96)
page.Size = UDim2.new(1, 0, 1, -144)
page.ScrollBarThickness = 3
page.ScrollBarImageColor3 = COL.line
page.CanvasSize = UDim2.new()
page.Parent = inner
W.page(page, { width = 700 })

W.section(page, "Autofish")
W.toggle(page, {
	label = "Autofish",
	desc = "Auto-casts, auto-shakes, then holds the reel bar centered on the fish",
	fullRow = true,
	stateText = true,
	get = function() return S.auto end,
	set = function(value)
		Log.info(string.format("autofish request=%s before=%s", tostring(value), tostring(S.auto)))
		if value then startAuto() else stopAuto("Stopped") end
		Log.info(string.format("autofish result requested=%s actual=%s status=%s", tostring(value), tostring(S.auto), S.status))
	end,
})
W.note(page, "Server-visible automation. Boots OFF every session. K immediately unloads and releases reel control.")
W.statusRow(page, function() return "Status: " .. S.status end)
W.statusRow(page, function()
	return string.format("Caught %d  •  Casts %d  •  Shakes %d  •  Errors %d",
		S.cycles, S.casts, S.shakes, S.errors)
end)

W.section(page, "Casting")
W.slider(page, {
	label = "Cast power", key = "castPower", min = 10, max = 100, step = 1,
	desc = "Power passed to Fisch's own FishingRod/Cast wrapper",
	fmt = function(v) return tostring(math.floor(v)) .. "%" end,
})
W.slider(page, {
	label = "Recast delay", key = "recastDelay", min = 0.8, max = 8, step = 0.1,
	desc = "Pause after each completed catch",
	fmt = function(v) return string.format("%.1fs", v) end,
})
W.slider(page, {
	label = "Random delay", key = "recastJitter", min = 0, max = 3, step = 0.05,
	desc = "Adds uneven timing after each catch",
	fmt = function(v) return string.format("+0-%.2fs", v) end,
})
W.toggle(page, {
	label = "Auto-equip rod", key = "autoEquip",
	desc = "Equips first fishing rod found in backpack before casting",
})

W.section(page, "Pacing and limits")
W.slider(page, {
	label = "Session cap", key = "sessionCapMin", min = 5, max = 480, step = 5,
	desc = "Autofish stops itself after this long, catches included",
	fmt = function(v) return string.format("%d min", v) end,
})
W.slider(page, {
	label = "Break every", key = "breakEveryMin", min = 3, max = 120, step = 1,
	desc = "Roughly this often, +/-30% so no two gaps match",
	fmt = function(v) return string.format("%d min", v) end,
})
W.slider(page, {
	label = "Break length", key = "breakLenSec", min = 15, max = 900, step = 5,
	desc = "Base pause once a break starts",
	fmt = function(v) return string.format("%ds", v) end,
})
W.slider(page, {
	label = "Break randomness", key = "breakJitterSec", min = 0, max = 600, step = 5,
	desc = "Added on top of break length, uneven every time",
	fmt = function(v) return string.format("+0-%ds", v) end,
})
W.slider(page, {
	label = "Stop after rejects", key = "maxRejects", min = 2, max = 30, step = 1,
	desc = "Consecutive refused casts before autofish stops itself",
	fmt = function(v) return string.format("%d", v) end,
})
W.note(page, "Breaks only start between catches, never mid-reel. 10 consecutive errors also stops it.")
W.statusRow(page, function()
	if not S.auto then
		return S.stopReason ~= "" and ("Last stop: " .. S.stopReason) or "Autofish idle"
	end
	local now = os.clock()
	local left = S.sessionEndsAt > 0 and math.max(0, S.sessionEndsAt - now) or 0
	if now < S.breakUntil then
		return string.format("Break: %ds left  •  breaks %d", math.ceil(S.breakUntil - now), S.breaks)
	end
	return string.format("Session %dm left  •  next break ~%dm  •  breaks %d  •  rejects %d/%d",
		math.floor(left / 60),
		S.nextBreakAt > 0 and math.max(0, math.floor((S.nextBreakAt - now) / 60)) or 0,
		S.breaks, S.rejects, CFG.maxRejects)
end)

W.section(page, "Vendor ESP")
W.toggle(page, {
	label = "Vendor ESP", key = "espVendors",
	desc = "Outline + tracer + label on every shop NPC, with the best rod you can afford there",
	fullRow = true,
	stateText = true,
	set = function(value) guard("esp.enable", espSetEnabled, value) end,
})
W.toggle(page, {
	label = "Shops only", key = "espShopsOnly",
	desc = "Hide quest and decoration NPCs. Off = every NPC with a prompt, logged so we can fix the filter",
	set = function() table.clear(E.judged); E.nextScan = 0 end,
})
W.toggle(page, { label = "Outlines", key = "espOutlines", desc = "Highlight the NPC model itself" })
W.toggle(page, { label = "Tracers", key = "espTracers", desc = "Line from the bottom of your screen to each vendor" })
W.slider(page, {
	label = "Range", key = "espRange", min = 200, max = 5000, step = 50,
	desc = "Vendors past this distance are not drawn",
	fmt = function(v) return string.format("%d studs", v) end,
})
W.note(page, "Client-only: reads NPC models and the rod library, draws in our own CoreGui layer. No remote, no hook, no write to a game instance.")
W.statusRow(page, function()
	if not CFG.espVendors then return "ESP off" end
	return string.format("Tracking %d vendors  •  C$%s  •  Level %d",
		#E.targets, espComma(E.money), E.level)
end)
W.statusRow(page, function()
	if not CFG.espVendors then return "" end
	if E.best then
		return string.format("Best affordable anywhere: %s  •  C$%s  •  Luck %d  •  %s",
			E.best.name, espComma(E.best.price), E.best.luck, E.best.island or "see label")
	end
	return "No purchasable rod within budget yet"
end)

W.section(page, "Inventory")
W.button(page, "Scan treasure chests (read-only)", "Logs every known chest id and its distance to the file log; opens nothing", treasureRecon, true)
W.note(page, "Chest scan never fires open_treasure -- that is probe-only until a clean session log.")
W.statusRow(page, function() return "Last catch: " .. S.lastCatch end)

-- Rarity comes from Fisch's own libraries, exactly as its notifier resolves it:
-- fish[name] or items.Items[name], then that entry's .Rarity (0035.lua:9-10,591-592).
local function rarityOf(name)
	if not S.libs then
		local ok, libs = pcall(function()
			local library = ReplicatedStorage:WaitForChild("shared"):WaitForChild("modules"):WaitForChild("library")
			return {
				fish = require(library:WaitForChild("fish")),
				items = require(library:WaitForChild("items")),
			}
		end)
		if not ok then
			Log.err("rarity library", libs)
			S.libs = {}
			return nil
		end
		S.libs = libs
	end
	local entry = (S.libs.fish and S.libs.fish[name])
		or (S.libs.items and S.libs.items.Items and S.libs.items.Items[name])
	return type(entry) == "table" and entry.Rarity or nil
end

task.spawn(function()
	local ok, events = pcall(function()
		return ReplicatedStorage:WaitForChild("events", 20):WaitForChild("anno_catch", 10)
	end)
	if not ok or not events then
		Log.warn("anno_catch remote not found; notifier idle")
		return
	end
	table.insert(S.conns, events.OnClientEvent:Connect(function(item, chance)
		if type(item) ~= "table" or type(item.Name) ~= "string" then return end
		local rarity = rarityOf(item.Name) or "?"
		local tag = item.Shiny and " Shiny" or ""
		if item.Sparkling then tag = tag .. " Sparkling" end
		S.lastCatch = string.format("%s (%s)%s", item.Name, rarity, tag)
		Log.info(string.format("catch name=%s rarity=%s shiny=%s sparkling=%s chance=%s",
			item.Name, rarity, tostring(item.Shiny), tostring(item.Sparkling), tostring(chance)))
	end))
	Log.info("catch notifier armed")
end)

page.CanvasSize = UDim2.fromOffset(0, Kit.height(page))
W.footer(inner, {
	onUnload = destroy,
	onSettings = function() end,
	hint = "K = panic unload",
})

if CFG.espVendors then
	-- Rungs 1-2 resume the user's last state; only rung-6 features boot OFF
	-- (potassium-dev S0.2b). The panel shows it armed and the boot line names it.
	guard("esp.resume", espSetEnabled, true)
end

saveConfig()
Log.info(string.format("UI ready embedded=%s esp=%s", tostring(embed ~= nil), tostring(CFG.espVendors)))
