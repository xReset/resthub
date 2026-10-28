--------------------------------------------------------------------------
-- arsenal_esp.lua — Arsenal PlaceId 286090429  BUILD 2026-09-04.2
-- Dump: game_dumps/286090429/2026-08-21T04-24-21Z_...
--
-- Re-inject safe: self-teardown on load; K = unload
-- UNLOADS_ON_INJECT: __ARSENAL_ESP
--
-- Rung 1-2: read Player.NRPBS / Status + client-local Highlight/Billboard/mousemoverel.
-- Server sees: nothing from ESP; soft-aim only produces local mouse deltas (default OFF).
-- AC (anticheat_deep): CLIENT INSPECTION 0, LOG MONITORING 1 (false+ ScriptContext),
--   MOVEMENT 0, ENFORCEMENT Kick via ShadowNotify. No print/warn.
--
-- Dump facts:
--   HP     = Players.<P>.NRPBS.Health / MaxHealth  (NOT Humanoid — 0011/0015/0008)
--   Alive  = Status.Alive + NRPBS.Health > 0; skip Status.Team == "Spectator"
--   Team   = Status.Team; enemy unless FFA or gametype=="Juggernaut" (0011:275)
--   Char   = Player.Character @ Workspace.<Name> R15; aim HeadHB/Head/UpperTorso
--   Hitbox = #AlwaysInvisible — never use as adorn; Highlight Adornee=char OK
--
-- RightShift = toggle panel | K = unload
--------------------------------------------------------------------------

if game.PlaceId ~= 286090429 then
	error("[ARSENAL_ESP] wrong place " .. tostring(game.PlaceId) .. " (need 286090429)", 0)
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local LP = Players.LocalPlayer
local RNG = Random.new()
local PLACE_ID = 286090429

local GENV = (getgenv and getgenv()) or _G
if type(GENV) ~= "table" then
	GENV = _G
end

local GKEY = "__ARSENAL_ESP"

-- hub.lua publishes __R3ST_HOST immediately before running us and clears it the
-- moment we return. When it is set, the hub owns the ScreenGui, the window
-- chrome, the drag and RightShift, so the CONTROL PANEL renders inside its
-- content host. The ESP/visual layer is deliberately left alone: it has to stay
-- a full-screen CoreGui layer, never a child of a hub panel.
local __HUBENV = (type(getgenv) == "function" and getgenv()) or _G
local HOST = (type(__HUBENV.__R3ST_HOST) == "table"
	and typeof(__HUBENV.__R3ST_HOST.host) == "Instance") and __HUBENV.__R3ST_HOST or nil

local BUILD_VERSION = "2026-09-04.2"
local CONFIG_FILE = "arsenal_esp_config.json"
local LEGACY_STATE_FILE = "arsenal_esp.state"

local function queueReinject()
	local payload = [[
pcall(function()
	local f = loadfile("arsenal_esp.lua")
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
		Log = mod("arsenal_esp")
	else
		local buf = {}
		local function flush(tag, m)
			table.insert(buf, string.format("[%s] %s", tag, tostring(m)))
			pcall(writefile, "logs/arsenal_esp.log", table.concat(buf, "\n") .. "\n")
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
	TeamColors = true,
	SoftAim = false,
	AimFov = 36,
	AimSmooth = 0.66,
	AimMaxStepPx = 30,
	AimStrength = 66,
	AimTuneVersion = 4,
	AimPart = "Closest",
	ShowAimFov = true,
	EspHz = 0.12,
	MaxDist = 650,
	UiVisible = true,
}

local VALIDATORS = {
	Chams = function(v) return type(v) == "boolean" end,
	Healthbars = function(v) return type(v) == "boolean" end,
	TeamColors = function(v) return type(v) == "boolean" end,
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
	charConns = {},
	hostIsLayer = false,
}

local COL = {
	bg = Color3.fromRGB(8, 8, 10),
	stroke = Color3.fromRGB(28, 28, 32),
	text = Color3.fromRGB(230, 230, 235),
	dim = Color3.fromRGB(140, 140, 148),
	on = Color3.fromRGB(60, 180, 90),
	off = Color3.fromRGB(48, 48, 54),
	enemyFill = Color3.fromRGB(220, 55, 55),
	enemyOut = Color3.fromRGB(255, 245, 245),
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
	S.hostIsLayer = typeof(parent) == "Instance" and parent:IsA("LayerCollector")
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

--------------------------------------------------------------------------
-- Arsenal adapters (dump-backed)
--------------------------------------------------------------------------

local function getWkspc()
	return ReplicatedStorage:FindFirstChild("wkspc")
end

local function isFfaMode()
	local wk = getWkspc()
	if not wk then
		return false
	end
	local ffa = wk:FindFirstChild("FFA")
	if ffa and ffa:IsA("BoolValue") and ffa.Value == true then
		return true
	end
	local gt = wk:FindFirstChild("gametype")
	if gt and gt:IsA("StringValue") and gt.Value == "Juggernaut" then
		return true
	end
	return false
end

local function statusFolder(plr)
	return plr and plr:FindFirstChild("Status")
end

local function nrpbs(plr)
	return plr and plr:FindFirstChild("NRPBS")
end

local function arsenalTeam(plr)
	local st = statusFolder(plr)
	local t = st and st:FindFirstChild("Team")
	if t and (t:IsA("StringValue") or t:IsA("ValueBase")) then
		return tostring(t.Value)
	end
	if plr and plr.Team then
		return plr.Team.Name
	end
	return nil
end

local function getHealth(plr, char)
	local nb = nrpbs(plr)
	local hv = nb and nb:FindFirstChild("Health")
	local mv = nb and nb:FindFirstChild("MaxHealth")
	if hv and hv:IsA("NumberValue") then
		local maxH = (mv and mv:IsA("NumberValue") and mv.Value > 0) and mv.Value or 100
		return hv.Value, maxH, hv, mv
	end
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		return hum.Health, math.max(hum.MaxHealth, 1), nil, nil
	end
	return 0, 1, nil, nil
end

local function isAlive(plr, char)
	local st = statusFolder(plr)
	local team = arsenalTeam(plr)
	if team == "Spectator" then
		return false
	end
	if st then
		local alive = st:FindFirstChild("Alive")
		if alive and alive:IsA("BoolValue") and alive.Value == false then
			return false
		end
		local spec = st:FindFirstChild("SpecMode")
		if spec and spec:IsA("BoolValue") and spec.Value == true then
			return false
		end
	end
	local hp = getHealth(plr, char)
	return hp > 0
end

local function getCharacter(plr)
	return plr and plr.Character
end

local function targetAllowed(plr, char)
	if not plr or plr == LP or not char then
		return false
	end
	local theirTeam = arsenalTeam(plr)
	if theirTeam == "Spectator" then
		return false
	end
	local myTeam = arsenalTeam(LP)
	if myTeam == "Spectator" then
		return false
	end
	if isFfaMode() then
		return true
	end
	if myTeam and theirTeam then
		return myTeam ~= theirTeam
	end
	-- fallback: Roblox Team instance
	if LP.Team and plr.Team then
		return LP.Team ~= plr.Team
	end
	return true
end

local function adornPart(char)
	return char:FindFirstChild("Head")
		or char:FindFirstChild("UpperTorso")
		or char:FindFirstChild("HumanoidRootPart")
end

local function teamTint(plr)
	if not CFG.TeamColors then
		return COL.enemyFill, COL.enemyOut
	end
	if plr.TeamColor then
		local c = plr.TeamColor.Color
		local fill = Color3.new(
			math.clamp(c.R * 0.85 + 0.15, 0, 1),
			math.clamp(c.G * 0.55, 0, 1),
			math.clamp(c.B * 0.55, 0, 1)
		)
		local out = Color3.new(
			math.clamp(c.R * 0.35 + 0.65, 0, 1),
			math.clamp(c.G * 0.35 + 0.65, 0, 1),
			math.clamp(c.B * 0.35 + 0.65, 0, 1)
		)
		return fill, out
	end
	return COL.enemyFill, COL.enemyOut
end

local function isTarget(plr, char)
	if not S.alive or not plr or plr == LP then
		return false
	end
	if not char or not char.Parent then
		return false
	end
	if not isAlive(plr, char) then
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
	if e.hpConn then
		e.hpConn:Disconnect()
	end
	if e.maxConn then
		e.maxConn:Disconnect()
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
	if S.gui and S.gui ~= S.folder then
		pcall(function()
			S.gui:Destroy()
		end)
	end
	S.gui = nil
	if S.folder then
		pcall(function()
			S.folder:Destroy()
		end)
		S.folder = nil
	end
	if S.shell then
		S.shell.destroy()
		S.shell = nil
	end
	S.root = nil
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

local function applyHealthBar(e, plr, char)
	if not e or not e.fill or not e.bb then
		return
	end
	local hp, maxH = getHealth(plr, char)
	local pct = math.clamp(hp / math.max(maxH, 1), 0, 1)
	e.fill.Size = UDim2.fromScale(1, pct)
	e.fill.BackgroundColor3 = COL.hpLo:Lerp(COL.hpHi, pct)
	e.bb.Enabled = true
end

local function ensureEsp(plr, char)
	if not isTarget(plr, char) then
		clearEsp(char)
		return
	end
	local folder = ensureFolder()
	local e = S.esp[char]
	if not e then
		e = { plr = plr }
		S.esp[char] = e
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			e.conn = hum.Died:Connect(function()
				clearEsp(char)
			end)
		end
		e.destroyConn = char.Destroying:Connect(function()
			clearEsp(char)
		end)
		local _, _, hv, mv = getHealth(plr, char)
		if hv then
			e.hpConn = hv:GetPropertyChangedSignal("Value"):Connect(function()
				if not S.alive then return end
				if not isAlive(plr, char) then
					clearEsp(char)
					return
				end
				applyHealthBar(e, plr, char)
			end)
		end
		if mv then
			e.maxConn = mv:GetPropertyChangedSignal("Value"):Connect(function()
				if not S.alive then return end
				applyHealthBar(e, plr, char)
			end)
		end
	end
	e.plr = plr

	local fillCol, outCol = teamTint(plr)

	if CFG.Chams then
		if not e.hl or not e.hl.Parent then
			local hl = Instance.new("Highlight")
			hl.Name = blandName("HL")
			hl.Adornee = char
			hl.FillColor = fillCol
			hl.OutlineColor = outCol
			hl.FillTransparency = 0.72
			hl.OutlineTransparency = 0.05
			hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			hl.Parent = folder
			e.hl = hl
		else
			e.hl.Adornee = char
			e.hl.FillColor = fillCol
			e.hl.OutlineColor = outCol
			e.hl.FillTransparency = 0.72
			e.hl.OutlineTransparency = 0.05
			e.hl.Enabled = true
		end
	elseif e.hl then
		e.hl.Enabled = false
	end

	if CFG.Healthbars then
		local head = adornPart(char)
		if head then
			if not e.bb or not e.bb.Parent then
				local bb = Instance.new("BillboardGui")
				bb.Name = blandName("NT")
				bb.Adornee = head
				bb.AlwaysOnTop = true
				bb.Size = UDim2.fromOffset(5, 42)
				bb.StudsOffset = Vector3.new(-2.15, 0.15, 0)
				bb.MaxDistance = CFG.MaxDist
				bb.Parent = folder

				local track = Instance.new("Frame")
				track.BackgroundColor3 = Color3.fromRGB(10, 10, 12)
				track.BackgroundTransparency = 0.08
				track.BorderSizePixel = 0
				track.Size = UDim2.fromScale(1, 1)
				track.Parent = bb

				local stroke = Instance.new("UIStroke")
				stroke.Color = Color3.fromRGB(40, 40, 44)
				stroke.Thickness = 1
				stroke.Transparency = 0.25
				stroke.Parent = track

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
			e.bb.Adornee = head
			applyHealthBar(e, plr, char)
		end
	elseif e.bb then
		e.bb.Enabled = false
	end
end

local function sweepEsp()
	if not S.alive then
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
	local filter = {}
	if myChar then
		table.insert(filter, myChar)
	end
	-- Hitbox is AlwaysInvisible but still blocks rays; ignore tagged hitboxes on target
	local hitbox = char:FindFirstChild("Hitbox")
	if hitbox then
		table.insert(filter, hitbox)
	end
	params.FilterDescendantsInstances = filter
	params.IgnoreWater = true
	local hit = Workspace:Raycast(cameraPos, part.Position - cameraPos, params)
	return not hit or hit.Instance:IsDescendantOf(char)
end

local function aimPoints(char)
	local headHb = char:FindFirstChild("HeadHB")
	local head = char:FindFirstChild("Head")
	local body = char:FindFirstChild("UpperTorso")
		or char:FindFirstChild("Torso")
		or char:FindFirstChild("HumanoidRootPart")
	if CFG.AimPart == "Head" then
		if headHb then return { headHb } end
		return head and { head } or {}
	end
	if CFG.AimPart == "Body" then
		return body and { body } or {}
	end
	local points = {}
	for _, name in ipairs({ "HeadHB", "Head", "UpperTorso", "Torso", "HumanoidRootPart" }) do
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

local function softAimStep(dt)
	if not S.alive then return end
	local camera = Workspace.CurrentCamera
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
	local myHp = getHealth(LP, getCharacter(LP))
	if myHp <= 0 or arsenalTeam(LP) == "Spectator" then
		S.stickyPlayer = nil
		aimNote("waiting: local dead/spec")
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
	local guiParent = folder
	-- Potassium gethui() is a ScreenGui — never nest another ScreenGui under it.
	if not S.hostIsLayer then
		local gui = mk("ScreenGui", {
			Name = blandName("SG"),
			ResetOnSpawn = false,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
			DisplayOrder = 55,
		}, folder)
		S.gui = gui
		guiParent = gui
	else
		S.gui = folder
	end

	local root = mk("Frame", {
		Size = UDim2.fromOffset(210, 250),
		Position = UDim2.new(0, 14, 0.32, 0),
		BackgroundColor3 = COL.bg,
		BackgroundTransparency = 0.04,
		BorderSizePixel = 0,
		Active = true,
		Visible = CFG.UiVisible,
	}, guiParent)
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
		Text = "ARSENAL ESP  " .. BUILD_VERSION,
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

	addRow(root, 90, "Team colors", function()
		return CFG.TeamColors
	end, function(v)
		CFG.TeamColors = v
	end, sweepEsp)

	addRow(root, 112, "Soft aim", function()
		return CFG.SoftAim
	end, function(v)
		CFG.SoftAim = v
		Log.info("soft aim toggle=" .. tostring(v))
		if not v then
			S.stickyPlayer = nil
		end
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

	mk("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 10, 0, 224),
		Size = UDim2.new(1, -20, 0, 12),
		Font = Enum.Font.Gotham,
		TextSize = 9,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = COL.dim,
		Text = "HP=NRPBS  team=Status.Team",
	}, root)
end

local function buildUI()
	wipeEsp()
	local folder = ensureFolder()
	local Kit = (HOST and HOST.ui) or loadfile("../scripts/r3st_ui.lua")()
	assert(Kit.SHELL_CONTRACT == "1", "R3ST shell contract mismatch")
	local Shell = Kit.moduleShell({
		id = "arsenal", title = "Arsenal", version = BUILD_VERSION,
		subtitle = "Player ESP and guarded soft aim",
		gameId = 111958650, placeId = 286090429,
		standaloneSize = Vector2.new(760, 560), keep = { folder },
		cfg = CFG, save = saveConfig,
		onUnload = teardown,
		onReload = function()
			task.defer(function()
				teardown()
				local chunk, err = loadfile("../scripts/arsenal_esp.lua")
				if chunk then chunk() else Log.warn("reload failed: " .. tostring(err)) end
			end)
		end,
	})
	S.shell, S.root = Shell, Shell.root
	local W, page = Shell.W, Shell.page("Main")
	W.section(page, "Awareness")
	W.toggle(page, { label = "Chams", key = "Chams", set = sweepEsp })
	W.toggle(page, { label = "Healthbars", key = "Healthbars", set = sweepEsp })
	W.toggle(page, { label = "Team colors", key = "TeamColors", set = sweepEsp })
	W.toggle(page, { label = "Show aim FOV", key = "ShowAimFov" })
	W.note(page, "Health: NRPBS · teams: Status.Team")
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
	W.slider(page, { label = "Aim FOV", key = "AimFov", min = 2, max = 45, step = 1,
		fmt = function(v) return tostring(math.floor(v + 0.5)) .. " deg" end,
		set = function() S.stickyPlayer = nil end })
	W.slider(page, { label = "Strength", key = "AimStrength", min = 1, max = 100, step = 1,
		fmt = function(v) return tostring(math.floor(v + 0.5)) .. "%" end })
	Shell.ready()
end

local okMain, errMain = xpcall(function()
	buildUI()

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

	ESP.destroy = teardown
	ESP.sweep = sweepEsp
	ESP.saveConfig = saveConfig

	Log.session(string.format(
		"armed build=%s place=%s ffa=%s myTeam=%s soft=%s",
		BUILD_VERSION,
		tostring(game.PlaceId),
		tostring(isFfaMode()),
		tostring(arsenalTeam(LP)),
		tostring(CFG.SoftAim)
	))
end, debug.traceback)

if not okMain then
	Log.err("boot failed", errMain)
	pcall(teardown)
end
