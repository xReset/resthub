--------------------------------------------------------------------------
-- rivals_esp.lua v2026-10-24.1 -- RIVALS player ESP + guarded soft aim/backstab
--
-- CHANGELOG v2026-10-24.1: remove undefined guard from module shell options.
--
-- Re-inject safe: self-teardown on load; K = unload
-- UNLOADS_ON_INJECT: __RIVALS_ESP
--
-- Uses only the game's stock item-input method. No remotes, hooks, camera writes, or hitbox edits.
-- Customize getCharacter/getHumanoid/targetAllowed/aimPoints for each game.
-- RightShift = toggle panel | K = unload
-- Manual test: equip Knife, enable Auto stab, then approach an enemy's back while aiming at them.
--------------------------------------------------------------------------

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local LP = Players.LocalPlayer
local RNG = Random.new()

local GENV = (getgenv and getgenv()) or _G
if type(GENV) ~= "table" then
	GENV = _G
end

local GKEY = "__RIVALS_ESP"

-- hub.lua publishes __R3ST_HOST immediately before running us and clears it the
-- moment we return. When it is set, the hub owns the ScreenGui, the window
-- chrome, the drag and RightShift, so the CONTROL PANEL renders inside its
-- content host. The ESP/visual layer is deliberately left alone: it has to stay
-- a full-screen CoreGui layer, never a child of a hub panel.
local __HUBENV = (type(getgenv) == "function" and getgenv()) or _G
local HOST = (type(__HUBENV.__R3ST_HOST) == "table"
	and typeof(__HUBENV.__R3ST_HOST.host) == "Instance") and __HUBENV.__R3ST_HOST or nil

local TELEPORT_KEY = "__RIVALS_ESP_TELEPORT_JOB"
local BUILD_VERSION = "2026-10-24.1"
local CONFIG_FILE = "rivals_esp_config.json"
local LEGACY_STATE_FILE = "rivals_esp.state"
local LOAD_STATE_FILE = "rivals_esp_loaded.state"

local function queueReinject()
	if GENV[TELEPORT_KEY] == game.JobId then
		return true, false
	end
	local payload = [[
task.defer(function()
	local function bootLog(stage)
		local line = string.format("[%s] job=%s %s\n", tostring(os.clock()), tostring(game.JobId), tostring(stage))
		local ok = pcall(appendfile, "logs/rivals_esp_boot.log", line)
		if not ok then
			local readOk, prior = pcall(readfile, "logs/rivals_esp_boot.log")
			pcall(writefile, "logs/rivals_esp_boot.log", (readOk and tostring(prior) or "") .. line)
		end
	end
	local ok, err = xpcall(function()
		bootLog("deferred")
		local stateOk, state = pcall(readfile, "rivals_esp_loaded.state")
		if stateOk and tostring(state):match("^%s*0%s*$") then
			bootLog("abort disabled")
			return
		end

		bootLog("waiting basic readiness")
		local Players = game:GetService("Players")
		while not (game:IsLoaded() and Players.LocalPlayer ~= nil) do
			stateOk, state = pcall(readfile, "rivals_esp_loaded.state")
			if stateOk and tostring(state):match("^%s*0%s*$") then
				bootLog("abort disabled while waiting")
				return
			end
			task.wait(1)
		end

		local G = getgenv()
		local now = os.clock()
		if G.__RIVALS_ESP_ARRIVAL_JOB == game.JobId
			and now - (G.__RIVALS_ESP_ARRIVAL_AT or 0) < 90 then
			bootLog("dedupe arrival")
			return
		end
		G.__RIVALS_ESP_ARRIVAL_JOB = game.JobId
		G.__RIVALS_ESP_ARRIVAL_AT = now
		G.__RIVALS_ESP_TELEPORT_JOB = nil
		bootLog("ready; delaying 10s")
		task.wait(10)
		stateOk, state = pcall(readfile, "rivals_esp_loaded.state")
		if stateOk and tostring(state):match("^%s*0%s*$") then
			bootLog("abort disabled after delay")
			return
		end
		local f, loadErr = loadfile("rivals_esp.lua")
		if not f then
			bootLog("loadfile failed: " .. tostring(loadErr))
			return
		end
		bootLog("delay complete; injecting")
		local ran, runErr = xpcall(f, debug.traceback)
		if not ran then
			bootLog("script error: " .. tostring(runErr))
		end
	end, debug.traceback)
	if not ok then
		bootLog("error: " .. tostring(err))
	end
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
	if queued then
		GENV[TELEPORT_KEY] = game.JobId
	end
	return queued, queued
end

if not game:IsLoaded() then
	game.Loaded:Wait()
end

if GENV[GKEY] and type(GENV[GKEY].destroy) == "function" then
	pcall(GENV[GKEY].destroy, false)
end

local Log
do
	local ok, mod = pcall(function()
		return loadfile("log.lua")()
	end)
	if ok and type(mod) == "function" then
		Log = mod("rivals_esp")
	else
		local buf = {}
		local function flush(tag, m)
			table.insert(buf, string.format("[%s] %s", tag, tostring(m)))
			pcall(writefile, "logs/rivals_esp.log", table.concat(buf, "\n") .. "\n")
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

local teleportReady, teleportQueued = queueReinject()
if teleportQueued then
	Log.info("teleport queued job=" .. tostring(game.JobId))
elseif teleportReady then
	Log.info("teleport already queued job=" .. tostring(game.JobId))
else
	Log.warn("teleport queue unavailable or failed")
end

GENV[GKEY] = GENV[GKEY] or {}
local ESP = GENV[GKEY]

local DEFAULTS = {
	Chams = true,
	Healthbars = true,
	SoftAim = false,
	AimFov = 36,
	AimSmooth = 0.66,
	AimMaxStepPx = 30,
	AimStrength = 66,
	AimTuneVersion = 4,
	AimPart = "Closest",
	ShowAimFov = true,
	AutoBackstab = false,
	EspHz = 0.28,
	MaxDist = 650,
	UiVisible = true,
}

local VALIDATORS = {
	Chams = function(v) return type(v) == "boolean" end,
	Healthbars = function(v) return type(v) == "boolean" end,
	SoftAim = function(v) return type(v) == "boolean" end,
	AimFov = function(v) return type(v) == "number" and v >= 2 and v <= 45 end,
	AimSmooth = function(v) return type(v) == "number" and v >= 0 and v <= 1 end,
	AimMaxStepPx = function(v) return type(v) == "number" and v >= 1 and v <= 200 end,
	AimStrength = function(v) return type(v) == "number" and v >= 1 and v <= 100 end,
	AimTuneVersion = function(v) return v == 4 end,
	AimPart = function(v) return v == "Closest" or v == "Head" or v == "Body" end,
	ShowAimFov = function(v) return type(v) == "boolean" end,
	AutoBackstab = function(v) return type(v) == "boolean" end,
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
	shell = nil,
	folder = nil,
	esp = {},
	hb = nil,
	input = nil,
	playerAdded = nil,
	playerRemoving = nil,
	aimRender = nil,
	fovDraw = nil,
	dragInput = nil,
	stickyPlayer = nil,
	stickyUntil = 0,
	aimLastNote = nil,
	aimLastLog = 0,
	backstabLastNote = nil,
	backstabLastLog = 0,
	backstabLastFire = 0,
	backstabLatch = nil,
	backstabClearSince = nil,
	mechanics = nil,
	mechanicsTriedAt = 0,
	charConns = {},
}
ESP.alive = true

local COL = {
	bg = Color3.fromRGB(8, 8, 10),
	stroke = Color3.fromRGB(28, 28, 32),
	text = Color3.fromRGB(230, 230, 235),
	dim = Color3.fromRGB(140, 140, 148),
	on = Color3.fromRGB(60, 180, 90),
	off = Color3.fromRGB(48, 48, 54),
	enemyFill = Color3.fromRGB(205, 72, 72),
	enemyOut = Color3.fromRGB(255, 215, 215),
	hpHi = Color3.fromRGB(70, 210, 90),
	hpLo = Color3.fromRGB(210, 60, 60),
}

local function blandName(prefix)
	return prefix .. string.format("%04x", RNG:NextInteger(0, 65535))
end

local function getParent()
	if typeof(gethui) == "function" then
		local ok, hui = pcall(gethui)
		if ok and hui then
			return hui
		end
	end
	return LP:FindFirstChildOfClass("PlayerGui") or LP:WaitForChild("PlayerGui", 5) or game:GetService("CoreGui")
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

-- Game-specific character adapter goes here.
local function getCharacter(plr)
	return plr and plr.Character
end

-- Game-specific health adapter goes here.
local function getHumanoid(char)
	return char and char:FindFirstChildOfClass("Humanoid")
end

-- RIVALS team filter. Dump callers compare Player @TeamID; nil means FFA/lobby.
local function targetAllowed(plr, char)
	if not plr or plr == LP or not char then return false end
	local myTeam = LP:GetAttribute("TeamID")
	local theirTeam = plr:GetAttribute("TeamID")
	return not myTeam or not theirTeam or myTeam ~= theirTeam
end

local function adornPart(char)
	return char:FindFirstChild("Head")
		or char:FindFirstChild("UpperTorso")
		or char:FindFirstChild("HumanoidRootPart")
end

local function isTarget(plr, char)
	if not S.alive or not plr or plr == LP then
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
	if e.bb then
		e.bb:Destroy()
	end
	S.esp[char] = nil
end

local function wipeEsp()
	for char in pairs(S.esp) do
		clearEsp(char)
	end
	if S.folder then
		S.folder:Destroy()
		S.folder = nil
	end
	if S.gui then
		S.gui:Destroy()
		S.gui = nil
	end
	if S.shell then
		S.shell.destroy()
		S.shell = nil
	end
	S.root = nil
end

local function teardown(markUnloaded)
	if markUnloaded then
		pcall(writefile, LOAD_STATE_FILE, "0")
	end
	S.alive = false
	ESP.alive = false
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
	if S.aimRender then
		S.aimRender:Disconnect()
		S.aimRender = nil
	end
	if S.fovDraw then
		pcall(function() S.fovDraw:Remove() end)
		S.fovDraw = nil
	end
	if S.dragInput then
		S.dragInput:Disconnect()
		S.dragInput = nil
	end
	for _, c in pairs(S.charConns) do
		c:Disconnect()
	end
	table.clear(S.charConns)
	wipeEsp()
	if GENV[GKEY] == ESP then
		GENV[GKEY] = nil
	end
	Log.step("teardown")
end

local function ensureEsp(plr, char)
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

	if CFG.Chams then
		if not e.hl or not e.hl.Parent then
			local hl = Instance.new("Highlight")
			hl.Name = blandName("HL")
			hl.Adornee = char
			hl.FillColor = COL.enemyFill
			hl.OutlineColor = COL.enemyOut
			hl.FillTransparency = 0.62
			hl.OutlineTransparency = 0.32
			hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			hl.Parent = folder
			e.hl = hl
		else
			e.hl.Adornee = char
			e.hl.Enabled = true
		end
	elseif e.hl then
		e.hl.Enabled = false
	end

	if CFG.Healthbars then
		local head = adornPart(char)
		local hum = getHumanoid(char)
		if head and hum then
			if not e.bb or not e.bb.Parent then
				local bb = Instance.new("BillboardGui")
				bb.Name = blandName("NT")
				bb.Adornee = head
				bb.AlwaysOnTop = true
				bb.Size = UDim2.fromOffset(4, 38)
				bb.StudsOffset = Vector3.new(-2.05, 0.1, 0)
				bb.MaxDistance = CFG.MaxDist
				bb.Parent = folder

				local track = Instance.new("Frame")
				track.BackgroundColor3 = Color3.fromRGB(12, 12, 14)
				track.BackgroundTransparency = 0.12
				track.BorderSizePixel = 0
				track.Size = UDim2.fromScale(1, 1)
				track.Parent = bb

				local fill = Instance.new("Frame")
				fill.AnchorPoint = Vector2.new(0, 1)
				fill.Position = UDim2.fromScale(0, 1)
				fill.BackgroundColor3 = COL.hpHi
				fill.BorderSizePixel = 0
				fill.Size = UDim2.fromScale(1, 1)
				fill.Parent = track

				e.bb = bb
				e.fill = fill
			end
			local pct = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
			e.fill.Size = UDim2.fromScale(1, pct)
			e.fill.BackgroundColor3 = COL.hpLo:Lerp(COL.hpHi, pct)
			e.bb.Enabled = true
			e.bb.Adornee = head
		end
	elseif e.bb then
		e.bb.Enabled = false
	end
end

local function sweepEsp()
	if not S.alive or not game:IsLoaded() then
		return
	end
	if not (CFG.Chams or CFG.Healthbars) then
		for char in pairs(S.esp) do
			clearEsp(char)
		end
		return
	end
	local live = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = getCharacter(plr)
		if char then
			live[char] = true
			ensureEsp(plr, char)
		end
	end
	for char in pairs(S.esp) do
		if not live[char] then
			clearEsp(char)
		end
	end
end

local function aimVisible(cameraPos, part, char)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local myChar = getCharacter(LP)
	params.FilterDescendantsInstances = myChar and { myChar } or {}
	params.IgnoreWater = true
	local hit = workspace:Raycast(cameraPos, part.Position - cameraPos, params)
	return not hit or hit.Instance:IsDescendantOf(char)
end

local BACKSTAB_REAR_MIN = 0.8
local BACKSTAB_MAX_ROOT_DIST = 5.5
local BACKSTAB_MAX_AIM_DEG = 6
local BACKSTAB_LOCAL_DEBOUNCE = 1.25

local function backstabNote(stateKey, details, force)
	local now = os.clock()
	if force or stateKey ~= S.backstabLastNote or now - S.backstabLastLog >= 3 then
		-- Keys contain stable states only; changing numeric telemetry cannot force a write.
		if force or now - S.backstabLastLog >= 0.12 then
			S.backstabLastNote = stateKey
			S.backstabLastLog = now
			Log.info("auto backstab " .. details)
		end
	end
end

local function getMechanicsController()
	if S.mechanics then return S.mechanics end
	local now = os.clock()
	if now - S.mechanicsTriedAt < 3 then return nil end
	S.mechanicsTriedAt = now
	local ok, controller = pcall(function()
		return require(LP.PlayerScripts.Controllers.MechanicsController)
	end)
	if ok and type(controller) == "table" then
		S.mechanics = controller
		backstabNote("mechanics-ready", "mechanics ready")
		return controller
	end
	backstabNote("mechanics-error", "blocked: MechanicsController require FAILED " .. tostring(controller), true)
	return nil
end

local function horizontal(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function backstabLos(cameraCFrame, targetChar, myChar)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = myChar and { myChar } or {}
	params.IgnoreWater = true
	local hit = workspace:Raycast(cameraCFrame.Position, cameraCFrame.LookVector * 7, params)
	return hit ~= nil and hit.Instance:IsDescendantOf(targetChar)
end

local function findBackstabCandidate(camera, myChar, myRoot)
	local best, nearestNote
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = getCharacter(plr)
		if isTarget(plr, char) then
			local root = char:FindFirstChild("HumanoidRootPart")
			if root then
				local targetPos = root.Position
				local separation = horizontal(myRoot.Position - targetPos)
				local distance = separation.Magnitude
				local victimForward = horizontal(root.CFrame.LookVector)
				local rearScore = distance > 0.01 and victimForward.Magnitude > 0.01
					and -victimForward.Unit:Dot(separation.Unit) or -1
				local cameraDelta = targetPos - camera.CFrame.Position
				local aimAngle = cameraDelta.Magnitude > 0.01
					and math.deg(math.acos(math.clamp(camera.CFrame.LookVector:Dot(cameraDelta.Unit), -1, 1))) or 180
				local los = backstabLos(camera.CFrame, char, myChar)
				local details = string.format(
					"candidate=%s dist=%.2f rear=%.3f aim=%.2f los=%s",
					plr.Name, distance, rearScore, aimAngle, tostring(los)
				)
				if not nearestNote or distance < nearestNote.distance then
					nearestNote = { distance = distance, text = details }
				end
				if distance <= BACKSTAB_MAX_ROOT_DIST and rearScore >= BACKSTAB_REAR_MIN
					and aimAngle <= BACKSTAB_MAX_AIM_DEG and los
					and (not best or distance < best.distance) then
					best = { player = plr, character = char, distance = distance, details = details }
				end
			end
		end
	end
	return best, nearestNote and nearestNote.text or "searching: no valid enemy"
end

local function autoBackstabStep()
	if not S.alive or not CFG.AutoBackstab then
		S.backstabLatch = nil
		S.backstabClearSince = nil
		return
	end
	local camera = workspace.CurrentCamera
	local myChar = getCharacter(LP)
	local myHum = getHumanoid(myChar)
	local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
	if not camera or not myHum or myHum.Health <= 0 or not myRoot then
		backstabNote("local-not-ready", "blocked: local character/camera not ready")
		return
	end
	local controller = getMechanicsController()
	if not controller then return end
	local fighter = controller.LocalFighter
	local item = fighter and fighter.EquippedItem
	local itemName = item and (item.Name or (item.Info and item.Info.Name))
	if not fighter or not item or itemName ~= "Knife" then
		backstabNote("knife-not-equipped", "blocked: Knife not equipped item=" .. tostring(itemName))
		return
	end
	local nativeOk, nativeReady, nativeReason = pcall(function()
		if type(fighter.AreItemsLocked) == "function" and fighter:AreItemsLocked() then
			return false, "items locked"
		end
		if type(item.IsEquipping) == "function" and item:IsEquipping() then
			return false, "equipping"
		end
		if type(item._attack_cooldown) == "number" and tick() < item._attack_cooldown then
			return false, string.format("native cooldown %.2fs", item._attack_cooldown - tick())
		end
		return true, "ready"
	end)
	if not nativeOk then
		backstabNote("readiness-error", "blocked: native readiness FAILED " .. tostring(nativeReady), true)
		return
	end
	if not nativeReady then
		local reasonKey = tostring(nativeReason):match("^native cooldown") and "native-cooldown" or tostring(nativeReason)
		backstabNote("native-blocked:" .. reasonKey, "blocked: " .. tostring(nativeReason))
		return
	end
	local candidate, nearest = findBackstabCandidate(camera, myChar, myRoot)
	if not candidate then
		if not S.backstabClearSince then S.backstabClearSince = os.clock() end
		if os.clock() - S.backstabClearSince >= 0.2 then S.backstabLatch = nil end
		local targetName = nearest:match("^candidate=([^ ]+)") or "none"
		backstabNote("geometry:" .. targetName, nearest .. " result=blocked geometry")
		return
	end
	S.backstabClearSince = nil
	if S.backstabLatch == candidate.player then
		backstabNote("latched:" .. candidate.player.Name, candidate.details .. " result=latched")
		return
	end
	if os.clock() - S.backstabLastFire < BACKSTAB_LOCAL_DEBOUNCE then
		backstabNote("local-debounce:" .. candidate.player.Name, candidate.details .. " result=local debounce")
		return
	end
	S.backstabLatch = candidate.player
	S.backstabLastFire = os.clock()
	local targetHum = getHumanoid(candidate.character)
	local healthBefore = targetHum and targetHum.Health or nil
	local cooldownBefore = type(item._attack_cooldown) == "number" and item._attack_cooldown or nil
	local callOk, callErr = pcall(controller.EquippedItemInput, controller, "StartAiming")
	if callOk then
		local cooldownAfter = type(item._attack_cooldown) == "number" and item._attack_cooldown or nil
		local cooldownAdvanced = cooldownAfter and (not cooldownBefore or cooldownAfter > cooldownBefore)
		local result = cooldownAdvanced and "submitted; cooldown advanced" or "submitted; cooldown unchanged"
		backstabNote("fire:" .. candidate.player.Name, candidate.details .. " native " .. result, true)
		task.delay(0.6, function()
			if not S.alive then return end
			local healthAfter = targetHum and targetHum.Parent and targetHum.Health or nil
			if healthBefore and healthAfter and healthAfter < healthBefore then
				local outcome = healthAfter <= 0 and "elimination observed" or string.format(
					"damage observed %.1f->%.1f", healthBefore, healthAfter
				)
				backstabNote("outcome:" .. candidate.player.Name, "candidate=" .. candidate.player.Name .. " " .. outcome, true)
			else
				backstabNote("outcome:" .. candidate.player.Name, "candidate=" .. candidate.player.Name .. " no damage observed", true)
			end
		end)
	else
		S.backstabLatch = nil
		backstabNote("fire-error:" .. candidate.player.Name, candidate.details .. " native FAILED=" .. tostring(callErr), true)
	end
end

local function aimPoints(char)
	-- Game-specific aim-point adapter goes here.
	local head = char:FindFirstChild("Head")
	local body = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
		or char:FindFirstChild("HumanoidRootPart")
	if CFG.AimPart == "Head" then return head and { head } or {} end
	if CFG.AimPart == "Body" then return body and { body } or {} end
	local points = {}
	for _, name in ipairs({ "Head", "UpperTorso", "Torso", "HumanoidRootPart" }) do
		local part = char:FindFirstChild(name)
		if part then table.insert(points, part) end
	end
	return points
end

local function aimCandidate(plr, camera, center)
	local char = getCharacter(plr)
	if not isTarget(plr, char) then return nil end
	local best
	for _, part in ipairs(aimPoints(char)) do
		local offset = part.Position - camera.CFrame.Position
		if offset.Magnitude >= 0.01 then
			local angle = math.deg(math.acos(math.clamp(camera.CFrame.LookVector:Dot(offset.Unit), -1, 1)))
			local screen, onScreen = camera:WorldToViewportPoint(part.Position)
			if angle <= CFG.AimFov and onScreen and screen.Z > 0
				and aimVisible(camera.CFrame.Position, part, char) then
				local delta = Vector2.new(screen.X, screen.Y) - center
				if not best or delta.Magnitude < best.score then
					best = { player = plr, part = part, delta = delta, score = delta.Magnitude }
				end
			end
		end
	end
	return best
end

local function pickAimTarget(camera, center)
	local now = os.clock()
	if S.stickyPlayer and now <= S.stickyUntil then
		local sticky = aimCandidate(S.stickyPlayer, camera, center)
		if sticky then return sticky end
	end
	local best
	for _, plr in ipairs(Players:GetPlayers()) do
		local candidate = aimCandidate(plr, camera, center)
		if candidate and (not best or candidate.score < best.score) then
			best = candidate
		end
	end
	if best then
		S.stickyPlayer = best.player
		S.stickyUntil = now + 0.18
	end
	return best
end

local function aimNote(note)
	local now = os.clock()
	-- Hard cap: rapid state flips must never become synchronous disk/console spam.
	if now - S.aimLastLog >= 3 then
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

local function softAimStep(dt)
	if not S.alive then return end
	if not game:IsLoaded() then return end
	local camera = workspace.CurrentCamera
	updateFovCircle(camera)
	if not CFG.SoftAim then return end
	if type(mousemoverel) ~= "function" then
		aimNote("blocked: mousemoverel unavailable")
		return
	end
	if UserInputService:GetFocusedTextBox()
		or UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
		S.stickyPlayer = nil
		aimNote("waiting: mouse not locked")
		return
	end
	if not (UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
		or UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)) then
		S.stickyPlayer = nil
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
		aimNote(string.format("moving: %s %.1fpx", target.player.Name, move.Magnitude))
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
			S.stickyPlayer = nil
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

local function buildLegacyUI()
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
		Size = UDim2.fromOffset(210, 228),
		Position = UDim2.new(0, 14, 0.36, 0),
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
		Text = "RIVALS ESP",
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

	addRow(root, 90, "Soft aim", function()
		return CFG.SoftAim
	end, function(v)
		CFG.SoftAim = v
		Log.info("soft aim toggle=" .. tostring(v))
		if not v then
			S.stickyPlayer = nil
		end
	end)

	addRow(root, 112, "Auto stab", function()
		return CFG.AutoBackstab
	end, function(v)
		CFG.AutoBackstab = v
		S.backstabLatch = nil
		S.backstabClearSince = nil
		backstabNote("toggle:" .. tostring(v), "toggle=" .. tostring(v), true)
	end)

	addChoiceRow(root, 134, "Aim part", function()
		return CFG.AimPart
	end, function()
		if CFG.AimPart == "Closest" then
			CFG.AimPart = "Head"
		elseif CFG.AimPart == "Head" then
			CFG.AimPart = "Body"
		else
			CFG.AimPart = "Closest"
		end
		S.stickyPlayer = nil
		Log.info("aim part=" .. CFG.AimPart)
	end)

	addFovRow(root, 156)

	addStrengthRow(root, 178)

	addRow(root, 200, "Show FOV", function()
		return CFG.ShowAimFov
	end, function(v)
		CFG.ShowAimFov = v
	end)
end

local function buildUI()
	wipeEsp()
	local folder = ensureFolder()
	local Kit = (HOST and HOST.ui) or loadfile("../scripts/r3st_ui.lua")()
	assert(Kit.SHELL_CONTRACT == "1", "R3ST shell contract mismatch")
	local Shell = Kit.moduleShell({
		id = "rivals",
		title = "Rivals",
		version = BUILD_VERSION,
		subtitle = "Player awareness, guarded soft aim and backstab assist",
		gameId = 6035872082,
		placeId = 117398147513099,
		standaloneSize = Vector2.new(760, 560),
		keep = { folder },
		cfg = CFG,
		save = saveConfig,
		onUnload = function() teardown(true) end,
		onReload = function()
			task.defer(function()
				teardown(false)
				local chunk, err = loadfile("../scripts/rivals_esp.lua")
				if chunk then chunk() else Log.warn("reload failed: " .. tostring(err)) end
			end)
		end,
	})
	S.shell, S.root = Shell, Shell.root
	local W = Shell.W
	local page = Shell.page("Main")

	W.section(page, "Awareness")
	W.toggle(page, { label = "Chams", desc = "Highlight valid enemy characters.", key = "Chams", set = sweepEsp })
	W.toggle(page, { label = "Healthbars", desc = "Show enemy health beside each target.", key = "Healthbars", set = sweepEsp })
	W.toggle(page, { label = "Show aim FOV", key = "ShowAimFov" })

	W.section(page, "Aim assist")
	W.toggle(page, {
		label = "Soft aim", desc = "Moves toward the selected enemy while RMB is held.", key = "SoftAim",
		set = function(v)
			Log.info("soft aim toggle=" .. tostring(v))
			if not v then S.stickyPlayer = nil end
		end,
	})
	local aimPart
	aimPart = W.button(page, "Aim part: " .. CFG.AimPart, "Cycle closest, head and body targeting.", function()
		if CFG.AimPart == "Closest" then CFG.AimPart = "Head"
		elseif CFG.AimPart == "Head" then CFG.AimPart = "Body"
		else CFG.AimPart = "Closest" end
		S.stickyPlayer = nil
		aimPart.Text = "Aim part: " .. CFG.AimPart
		Log.info("aim part=" .. CFG.AimPart)
		saveConfig()
	end, true)
	W.slider(page, {
		label = "Aim FOV", key = "AimFov", min = 2, max = 45, step = 1,
		fmt = function(v) return tostring(math.floor(v + 0.5)) .. " deg" end,
		set = function() S.stickyPlayer = nil end,
	})
	W.slider(page, {
		label = "Strength", key = "AimStrength", min = 1, max = 100, step = 1,
		fmt = function(v) return tostring(math.floor(v + 0.5)) .. "%" end,
	})

	W.section(page, "Knife")
	W.toggle(page, {
		label = "Auto stab", desc = "Uses the game's stock item-input method behind a valid enemy.", key = "AutoBackstab",
		set = function(v)
			S.backstabLatch = nil
			S.backstabClearSince = nil
			backstabNote("toggle:" .. tostring(v), "toggle=" .. tostring(v), true)
		end,
	})
	Shell.ready()
end

buildUI()

local acc = 0
S.hb = RunService.Heartbeat:Connect(function(dt)
	if not S.alive then
		return
	end
	if not game:IsLoaded() then
		return
	end
	acc += dt
	if acc >= CFG.EspHz then
		acc = 0
		sweepEsp()
	end
end)

S.aimRender = RunService.RenderStepped:Connect(softAimStep)

local backstabAcc = 0
local backstabConn = RunService.Heartbeat:Connect(function(dt)
	backstabAcc += dt
	if backstabAcc >= 0.05 then
		backstabAcc = 0
		autoBackstabStep()
	end
end)
table.insert(S.charConns, backstabConn)

S.input = UserInputService.InputBegan:Connect(function(input, gp)
	if gp or not S.alive then
		return
	end
	if input.KeyCode == Enum.KeyCode.RightShift and S.root and not HOST then
		CFG.UiVisible = not CFG.UiVisible
		S.root.Visible = CFG.UiVisible
		saveConfig()
	elseif input.KeyCode == Enum.KeyCode.K then
		teardown(true)
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

ESP.destroy = function(markUnloaded)
	teardown(markUnloaded ~= false)
end
ESP.sweep = sweepEsp
ESP.saveConfig = saveConfig

Log.session(string.format("armed build=%s place=%s game=%s", BUILD_VERSION, tostring(game.PlaceId), tostring(game.GameId)))
pcall(writefile, LOAD_STATE_FILE, "1")
print(string.format("[RIVALS_ESP] armed place=%s chams=%s hp=%s", tostring(game.PlaceId), tostring(CFG.Chams), tostring(CFG.Healthbars)))
