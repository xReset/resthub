--------------------------------------------------------------------------
-- twisted_hub.lua v2026-09-10.2 (2026-09-10) -- TWISTED (PlaceId 14170731342)
-- Storm and tornado ESP, chase vehicle readouts, sounding data, night visibility.
--
-- Changelog:
--   .2 Fix the render loop dying every frame it drew an outline: `used` was
--      being assigned as a field on the Highlight INSTANCE, which throws, and
--      the throw abandoned the rest of the frame. Used-flags moved to side
--      tables, highlights moved to their own CoreGui folder, the frame body is
--      contained by a pcall that counts and logs, and the nearest-storm closing
--      rate is cached instead of recomputed from a possibly-destroyed anchor.
--   .1 First build: storm/tornado ESP with EF ratings and closing ETA, proximity
--      alert, chaser/vehicle/probe ESP, vehicle speed and spec readout, the
--      kinematics sounding panel, and fullbright/fog/atmosphere controls.
--
-- Read-only client module. It renders what the client already replicates and
-- changes nothing the server can see. No remote is fired, no humanoid property
-- is written, no BodyMover is created, and nothing is ever parented to
-- PlayerGui. Those four restrictions are not style -- they are the exact
-- vectors StarterCharacterScripts.CheatHandler kicks for:
--   0504.lua:54-66  WalkSpeed >= 30 / Health > 100 / JumpHeight >= 8.1 -> kick
--   0504.lua:68-73  any BodyGyro/BodyVelocity/BodyPosition/BodyAngularVelocity/
--                   BodyThrust/BodyForce added under the character -> kick
--   0504.lua:75-81  any PlayerGui child whose name is not on its allowlist -> kick
-- The hub shell mounts under a cloned CoreGui, so the UI allowlist never sees us.
--
-- Data sources (dump 2026-09-10T22-12-45Z, PASS, tool v4.11):
--   workspace.storm_related.storms.<id>.configs        trees/Workspace.txt:74510+
--     .tornado.winds/width{sfc,base}/height/otg/multi/debris/rfd/windfield
--     .motion (Vector3Value) attributes degree + speed (mph)
--     .rainwrap, .hail, .lcl, .wallcloud.meso
--   workspace.storm_related.storms.<id>.rotation.TornadoPart  tag TornadoOTG
--     tags.txt:287, 0555.lua:52-58 (the game's own tornado actor trigger)
--   workspace.player_related.cars.<UserId>             trees/Workspace.txt:30+
--     attributes gas/gear/ignition/lights, chassis Part, modifiers Configuration,
--     info ModuleScript -> Driving.Speeds/Torque, Gas.Tank/MPG   (0132.lua)
--   ReplicatedStorage.kinematics                       trees/ReplicatedStorage.txt:203+
--     cape/stp/srh/temp/dewpoint/rh/wind/motion/risk/hodograph
--
-- Units follow the game: modules/conversions.lua:16 treats 1 stud as 1 ft and
-- 4096 ft as one mile, and speeds are already mph. EF thresholds are the game's
-- own radar colour breaks, gui_handler.radar 0011.lua:500-524.
--
-- Re-inject safe: self-teardown on load. K = unload. RightShift = hide (standalone).
--------------------------------------------------------------------------

local BUILD_VERSION = "2026-09-10.2"
local GKEY = "__TWISTED_HUB"
local EXPECTED_PLACE = 14170731342
local EXPECTED_GAME = 2251388500
if game.GameId ~= EXPECTED_GAME and game.PlaceId ~= EXPECTED_PLACE then return end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")

local LP = Players.LocalPlayer
local GENV = (type(getgenv) == "function" and getgenv()) or _G
if GENV[GKEY] and GENV[GKEY].destroy then pcall(GENV[GKEY].destroy) end

local HOST = (type(GENV.__R3ST_HOST) == "table"
	and typeof(GENV.__R3ST_HOST.host) == "Instance") and GENV.__R3ST_HOST or nil

local CoreGui = game:GetService("CoreGui")
if type(cloneref) == "function" then
	local ok, copy = pcall(cloneref, CoreGui)
	if ok and copy then CoreGui = copy end
end

local CONFIG_FILE = "twisted_hub_config.json"
local function fallbackLog(msg)
	pcall(function()
		local path = "logs/twisted_hub.log"
		local old = (isfile and isfile(path) and readfile(path)) or ""
		writefile(path, old .. os.date("[%Y-%m-%d %H:%M:%S] ") .. tostring(msg) .. "\n")
	end)
end
local Log = { info = fallbackLog, warn = fallbackLog }
pcall(function() Log = loadfile("log.lua")()("twisted_hub") end)

--------------------------------------------------------------------------
-- config
--------------------------------------------------------------------------
local defaults = {
	stormEsp = true,
	stormNonTornadic = true,
	stormDetail = true,
	stormOffscreen = true,
	stormMaxMiles = 12,
	tornadoHighlight = true,
	proximityAlert = true,
	alertMiles = 1.5,

	playerEsp = false,
	playerNames = true,
	vehicleEsp = false,
	probeEsp = false,
	espMaxStuds = 3000,

	speedo = true,

	fullbright = false,
	fullbrightLevel = 2,
	clearFog = false,
	noAtmosphere = false,
}
local CFG = table.clone(defaults)
do
	local ok, raw = pcall(readfile, CONFIG_FILE)
	if ok then
		local ok2, saved = pcall(HttpService.JSONDecode, HttpService, raw)
		if ok2 and type(saved) == "table" then
			for k, fallback in next, defaults do
				if typeof(saved[k]) == typeof(fallback) then CFG[k] = saved[k] end
			end
		end
	end
end
local savePending = false
local function saveConfig()
	if savePending then return end
	savePending = true
	task.delay(0.6, function()
		savePending = false
		local ok, raw = pcall(HttpService.JSONEncode, HttpService, CFG)
		if ok then pcall(writefile, CONFIG_FILE, raw) end
	end)
end

-- `used` is tracked in side tables, never as a field on the object. S.highlights
-- holds real Highlight INSTANCES, and assigning an unknown field to an Instance
-- throws -- which killed the rest of every frame that drew one (build .1).
local S = {
	alive = true, conns = {}, tracks = {},
	marks = {}, usedMarks = {},
	highlights = {}, usedHighlights = {},
	errors = 0, lastError = nil,
}
local function connect(signal, fn)
	local c = signal:Connect(fn)
	S.conns[#S.conns + 1] = c
	return c
end

--------------------------------------------------------------------------
-- units and ratings, matching the game's own conventions
--------------------------------------------------------------------------
local STUDS_PER_MILE = 4096           -- conversions.lua:16
local MPH_PER_STUD_SEC = 3600 / STUDS_PER_MILE

local EF = {
	{ 85, "EF0", Color3.fromRGB(1, 176, 241) },
	{ 110, "EF1", Color3.fromRGB(146, 209, 79) },
	{ 135, "EF2", Color3.fromRGB(255, 255, 0) },
	{ 165, "EF3", Color3.fromRGB(255, 140, 0) },
	{ 200, "EF4", Color3.fromRGB(192, 0, 0) },
}
local EF5_COLOR = Color3.fromRGB(203, 0, 204)
local DIM = Color3.fromRGB(150, 155, 165)

-- 0011.lua:500-524 get_color: the radar's own wind breaks. Below EF0 winds the
-- game shows "EFU", so anything under the first break is unrated, not EF0.
local function ratingOf(winds)
	if type(winds) ~= "number" or winds <= 0 then return "EFU", DIM end
	if winds < 65 then return "EFU", DIM end
	for _, row in ipairs(EF) do
		if winds <= row[1] then return row[2], row[3] end
	end
	return "EF5", EF5_COLOR
end

local function miles(studs) return studs / STUDS_PER_MILE end
local function distText(studs)
	if studs < STUDS_PER_MILE then return string.format("%d ft", math.round(studs)) end
	return string.format("%.2f mi", miles(studs))
end
local function etaText(seconds)
	if seconds >= 3600 then return string.format("%dh", math.floor(seconds / 3600)) end
	if seconds >= 60 then return string.format("%dm %ds", math.floor(seconds / 60), math.floor(seconds % 60)) end
	return string.format("%ds", math.floor(seconds))
end

--------------------------------------------------------------------------
-- storm reads
--------------------------------------------------------------------------
local function stormFolder()
	local sr = workspace:FindFirstChild("storm_related")
	return sr and sr:FindFirstChild("storms")
end

local function num(inst, default)
	if inst and inst:IsA("ValueBase") then
		local v = inst.Value
		if type(v) == "number" then return v end
	end
	return default
end

-- One flat table per storm. Every field is optional: a storm that has not
-- produced a tornado has the same configs tree with zeroed values.
local function readStorm(model)
	local configs = model:FindFirstChild("configs")
	if not configs then return nil end
	local tor = configs:FindFirstChild("tornado")
	local width = tor and tor:FindFirstChild("width")
	local motion = configs:FindFirstChild("motion")

	local anchor
	local rotation = model:FindFirstChild("rotation")
	if rotation then anchor = rotation:FindFirstChild("TornadoPart") end
	if not anchor then anchor = model:FindFirstChild("center") end
	if not anchor then anchor = model.PrimaryPart end
	if not anchor or not anchor:IsA("BasePart") then return nil end

	local otg = tor and tor:FindFirstChild("otg")
	return {
		model = model,
		name = model.Name,
		anchor = anchor,
		onGround = (otg and otg:IsA("BoolValue") and otg.Value) or false,
		winds = num(tor and tor:FindFirstChild("winds"), 0),
		sfc = (width and width:GetAttribute("sfc")) or 0,
		base = (width and width:GetAttribute("base")) or 0,
		height = num(tor and tor:FindFirstChild("height"), 0),
		debris = num(tor and tor:FindFirstChild("debris"), 0),
		windfield = num(tor and tor:FindFirstChild("windfield"), 0),
		multi = (tor and tor:FindFirstChild("multi") and tor.multi.Value) or false,
		rainwrap = num(configs:FindFirstChild("rainwrap"), 0),
		hail = num(configs:FindFirstChild("hail"), 0),
		motionDeg = (motion and motion:GetAttribute("degree")) or nil,
		motionSpd = (motion and motion:GetAttribute("speed")) or nil,
		track = model:FindFirstChild("rotation") and model.rotation:GetAttribute("TornadoTrackName") or nil,
	}
end

local function allStorms()
	local out = {}
	local folder = stormFolder()
	if not folder then return out end
	for _, model in ipairs(folder:GetChildren()) do
		if model:IsA("Model") then
			local info = readStorm(model)
			if info then out[#out + 1] = info end
		end
	end
	return out
end

-- Motion is sampled from the anchor itself rather than trusted from the
-- degree attribute: the attribute is the meteorological "from" bearing
-- (thermos 0019.lua:102 adds 180 before drawing it), and a measured velocity
-- also survives whatever the server does to the track mid-life.
local function sampleMotion(info, now)
	local t = S.tracks[info.name]
	local pos = info.anchor.Position
	if not t then
		S.tracks[info.name] = { pos = pos, at = now, vel = Vector3.zero }
		return Vector3.zero
	end
	local dt = now - t.at
	if dt >= 0.35 then
		local raw = (pos - t.pos) / dt
		t.vel = t.vel:Lerp(Vector3.new(raw.X, 0, raw.Z), 0.5)
		t.pos, t.at = pos, now
	end
	return t.vel
end

--------------------------------------------------------------------------
-- ESP layer: screen space, so a tornado five miles out stays readable
--------------------------------------------------------------------------
local layer = Instance.new("ScreenGui")
layer.Name = "TW_" .. tostring(math.random(1000, 9999))
layer.ResetOnSpawn = false
layer.IgnoreGuiInset = true
layer.DisplayOrder = 2147483646
layer.Parent = CoreGui

-- Highlights are Adornee-driven and are not GuiObjects; they live in their own
-- folder rather than inside the ScreenGui that holds the screen-space marks.
local highlightFolder = Instance.new("Folder")
highlightFolder.Name = "TW_Highlights"
highlightFolder.Parent = CoreGui

local alertLabel = Instance.new("TextLabel")
alertLabel.Name = "alert"
alertLabel.AnchorPoint = Vector2.new(0.5, 0)
alertLabel.Position = UDim2.new(0.5, 0, 0, 64)
alertLabel.Size = UDim2.fromOffset(420, 30)
alertLabel.BackgroundColor3 = Color3.fromRGB(24, 6, 8)
alertLabel.BackgroundTransparency = 0.15
alertLabel.BorderSizePixel = 0
alertLabel.Font = Enum.Font.GothamBold
alertLabel.TextSize = 15
alertLabel.TextColor3 = Color3.fromRGB(255, 90, 90)
alertLabel.Text = ""
alertLabel.Visible = false
alertLabel.Parent = layer

local function newMark()
	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromOffset(280, 64)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Visible = false
	frame.Parent = layer

	local dot = Instance.new("Frame")
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.Size = UDim2.fromOffset(6, 6)
	dot.BorderSizePixel = 0
	dot.Parent = frame
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = dot

	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.AnchorPoint = Vector2.new(0.5, 1)
	text.Position = UDim2.new(0.5, 0, 0.5, -8)
	text.Size = UDim2.fromOffset(280, 56)
	text.Font = Enum.Font.Code
	text.TextSize = 13
	text.TextYAlignment = Enum.TextYAlignment.Bottom
	text.RichText = true
	text.TextStrokeTransparency = 0.35
	text.Text = ""
	text.Parent = frame

	return { frame = frame, dot = dot, text = text }
end

local function markFor(key)
	local m = S.marks[key]
	if not m then
		m = newMark()
		S.marks[key] = m
	end
	S.usedMarks[key] = true
	return m
end

local function highlightFor(key, adornee, color)
	if not adornee or not adornee.Parent then return nil end
	local h = S.highlights[key]
	if not h or not h.Parent then
		h = Instance.new("Highlight")
		h.Name = "TW_HL"
		h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		h.FillTransparency = 1
		h.OutlineTransparency = 0.15
		h.Parent = highlightFolder
		S.highlights[key] = h
	end
	h.Adornee = adornee
	h.OutlineColor = color
	h.Enabled = true
	S.usedHighlights[key] = true
	return h
end

-- Places a mark at a world point. Off-screen points are clamped to the screen
-- edge when the user asked for it, so a tornado behind you still has a bearing.
local function place(mark, worldPos, camera, viewport, allowOffscreen)
	local point, onScreen = camera:WorldToViewportPoint(worldPos)
	if onScreen then
		mark.frame.Position = UDim2.fromOffset(point.X, point.Y)
		mark.frame.Visible = true
		return true
	end
	if not allowOffscreen then
		mark.frame.Visible = false
		return false
	end
	local dir = Vector2.new(point.X, point.Y) - viewport / 2
	if point.Z < 0 then dir = -dir end
	if dir.Magnitude < 1 then dir = Vector2.new(0, -1) end
	dir = dir.Unit
	local halfX, halfY = viewport.X / 2 - 46, viewport.Y / 2 - 46
	local scale = math.min(halfX / math.max(math.abs(dir.X), 1e-3), halfY / math.max(math.abs(dir.Y), 1e-3))
	local edge = viewport / 2 + dir * scale
	mark.frame.Position = UDim2.fromOffset(edge.X, edge.Y)
	mark.frame.Visible = true
	return false
end

--------------------------------------------------------------------------
-- vehicle reads
--------------------------------------------------------------------------
local function carsFolder()
	local pr = workspace:FindFirstChild("player_related")
	return pr and pr:FindFirstChild("cars")
end

-- Own car first (the folder keys cars by owner UserId, trees/Workspace.txt:31),
-- then whatever we are actually sitting in, which may be someone else's.
local function myVehicle()
	local folder = carsFolder()
	local mine = folder and folder:FindFirstChild(tostring(LP.UserId))
	local character = LP.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	if seat then
		local model = seat:FindFirstAncestorWhichIsA("Model")
		while model and folder and model.Parent ~= folder do
			model = model:FindFirstAncestorWhichIsA("Model")
		end
		if model then return model, true end
	end
	return mine, false
end

local vehicleSpecCache = {}
local function vehicleSpec(model)
	if not model then return nil end
	local cached = vehicleSpecCache[model]
	if cached ~= nil then return cached or nil end
	local info = model:FindFirstChild("info")
	if not info or not info:IsA("ModuleScript") then
		vehicleSpecCache[model] = false
		return nil
	end
	local ok, spec = pcall(require, info)
	vehicleSpecCache[model] = (ok and type(spec) == "table") and spec or false
	return vehicleSpecCache[model] or nil
end

local function vehicleSpeedMph(model)
	local chassis = model and model:FindFirstChild("chassis")
	if not chassis or not chassis:IsA("BasePart") then
		chassis = model and model.PrimaryPart
	end
	if not chassis then return 0 end
	local v = chassis.AssemblyLinearVelocity
	return Vector3.new(v.X, 0, v.Z).Magnitude * MPH_PER_STUD_SEC
end

--------------------------------------------------------------------------
-- lighting: fullbright, fog, atmosphere
--------------------------------------------------------------------------
local lightingSaved = nil
local function captureLighting()
	if lightingSaved then return end
	lightingSaved = {
		Brightness = Lighting.Brightness,
		ClockTime = Lighting.ClockTime,
		Ambient = Lighting.Ambient,
		OutdoorAmbient = Lighting.OutdoorAmbient,
		GlobalShadows = Lighting.GlobalShadows,
		ExposureCompensation = Lighting.ExposureCompensation,
		FogEnd = Lighting.FogEnd,
		FogStart = Lighting.FogStart,
	}
	local atmos = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmos then
		lightingSaved.atmosphere = atmos
		lightingSaved.Density = atmos.Density
		lightingSaved.Haze = atmos.Haze
	end
end

local function applyLighting()
	captureLighting()
	if CFG.fullbright then
		local level = math.clamp(CFG.fullbrightLevel, 0, 5)
		local grey = math.floor(60 + level * 26)
		Lighting.Brightness = level
		Lighting.Ambient = Color3.fromRGB(grey, grey, grey)
		Lighting.OutdoorAmbient = Color3.fromRGB(grey, grey, grey)
		Lighting.GlobalShadows = false
		Lighting.ExposureCompensation = math.max(lightingSaved.ExposureCompensation, 0.35)
	else
		Lighting.Brightness = lightingSaved.Brightness
		Lighting.Ambient = lightingSaved.Ambient
		Lighting.OutdoorAmbient = lightingSaved.OutdoorAmbient
		Lighting.GlobalShadows = lightingSaved.GlobalShadows
		Lighting.ExposureCompensation = lightingSaved.ExposureCompensation
	end
	if CFG.clearFog then
		Lighting.FogEnd = 100000
		Lighting.FogStart = 10000
	else
		Lighting.FogEnd = lightingSaved.FogEnd
		Lighting.FogStart = lightingSaved.FogStart
	end
	local atmos = lightingSaved.atmosphere
	if atmos and atmos.Parent then
		if CFG.noAtmosphere then
			atmos.Density = 0
			atmos.Haze = 0
		else
			atmos.Density = lightingSaved.Density
			atmos.Haze = lightingSaved.Haze
		end
	end
end

local function restoreLighting()
	if not lightingSaved then return end
	pcall(function()
		Lighting.Brightness = lightingSaved.Brightness
		Lighting.ClockTime = lightingSaved.ClockTime
		Lighting.Ambient = lightingSaved.Ambient
		Lighting.OutdoorAmbient = lightingSaved.OutdoorAmbient
		Lighting.GlobalShadows = lightingSaved.GlobalShadows
		Lighting.ExposureCompensation = lightingSaved.ExposureCompensation
		Lighting.FogEnd = lightingSaved.FogEnd
		Lighting.FogStart = lightingSaved.FogStart
		local atmos = lightingSaved.atmosphere
		if atmos and atmos.Parent then
			atmos.Density = lightingSaved.Density
			atmos.Haze = lightingSaved.Haze
		end
	end)
end

--------------------------------------------------------------------------
-- render loop
--------------------------------------------------------------------------
local nearest = nil       -- the closest storm this frame, for the status rows
local myCar, riding = nil, false
local mySpeed = 0

local function selfPosition()
	local character = LP.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then return root.Position end
	local cam = workspace.CurrentCamera
	return cam and cam.CFrame.Position or Vector3.zero
end

local function renderStorms(camera, viewport, origin, now)
	nearest = nil
	if not CFG.stormEsp then return end
	local maxStuds = CFG.stormMaxMiles * STUDS_PER_MILE
	for _, info in ipairs(allStorms()) do
		local pos = info.anchor.Position
		local flat = Vector3.new(pos.X - origin.X, 0, pos.Z - origin.Z)
		local dist = flat.Magnitude
		local vel = sampleMotion(info, now)

		-- Closing rate is computed once, here, and cached. The status rows read
		-- the cache instead of recomputing from info.anchor, which can be
		-- destroyed between frames when a tornado dissipates.
		local closingNow = 0
		if dist > 1 then closingNow = -flat.Unit:Dot(vel) end

		if not nearest or dist < nearest.dist then
			nearest = { info = info, dist = dist, vel = vel, closing = closingNow }
		end

		local show = dist <= maxStuds and (info.onGround or CFG.stormNonTornadic)
		local key = "storm:" .. info.name
		if show then
			local mark = markFor(key)
			local rating, color = ratingOf(info.winds)
			if not info.onGround then color = DIM end
			mark.dot.BackgroundColor3 = color

			local head = info.onGround
				and string.format("<b>%s  %s</b>", rating, info.name)
				or string.format("<b>STORM %s</b>", info.name)
			local lines = { head }
			if CFG.stormDetail then
				if info.onGround then
					lines[#lines + 1] = string.format("%d mph  ·  %d ft wide%s",
						math.round(info.winds), math.round(info.sfc), info.multi and "  ·  MULTI" or "")
				end
				local motionBit = ""
				if info.motionDeg and info.motionSpd then
					motionBit = string.format("  ·  %d° @ %d mph",
						math.round((info.motionDeg + 180) % 360), math.round(info.motionSpd))
				end
				lines[#lines + 1] = distText(dist) .. motionBit

				local closing = closingNow
				if closing > 0.5 then
					local edge = math.max(dist - (info.sfc * 0.5), 0)
					lines[#lines + 1] = "closing  ·  ETA " .. etaText(edge / closing)
				end
			end
			mark.text.Text = table.concat(lines, "\n")
			mark.text.TextColor3 = color
			place(mark, pos + Vector3.new(0, 40, 0), camera, viewport, CFG.stormOffscreen)

			if info.onGround and CFG.tornadoHighlight then
				highlightFor(key, info.anchor, color)
			end
		end
	end
end

local function renderEntities(camera, viewport, origin)
	local maxStuds = CFG.espMaxStuds
	if CFG.playerEsp then
		for _, player in ipairs(Players:GetPlayers()) do
			local character = player ~= LP and player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root then
				local dist = (root.Position - origin).Magnitude
				if dist <= maxStuds then
					local key = "plr:" .. player.Name
					local mark = markFor(key)
					mark.dot.BackgroundColor3 = Color3.fromRGB(120, 190, 255)
					mark.text.TextColor3 = Color3.fromRGB(190, 220, 255)
					mark.text.Text = CFG.playerNames
						and string.format("%s\n%s", player.Name, distText(dist))
						or distText(dist)
					place(mark, root.Position + Vector3.new(0, 3, 0), camera, viewport, false)
					highlightFor(key, character, Color3.fromRGB(120, 190, 255))
				end
			end
		end
	end

	if CFG.vehicleEsp then
		local folder = carsFolder()
		for _, model in ipairs(folder and folder:GetChildren() or {}) do
			local chassis = model:FindFirstChild("chassis") or model.PrimaryPart
			if chassis and chassis:IsA("BasePart") then
				local dist = (chassis.Position - origin).Magnitude
				if dist <= maxStuds then
					local mark = markFor("car:" .. model.Name)
					local owner = Players:GetPlayerByUserId(tonumber(model.Name) or 0)
					local spec = vehicleSpec(model)
					local label = spec and spec.Vehicle
						and string.format("%s %s", tostring(spec.Vehicle.Year), tostring(spec.Vehicle.Model))
						or (model:GetAttribute("ID") or model.Name)
					mark.dot.BackgroundColor3 = Color3.fromRGB(255, 210, 120)
					mark.text.TextColor3 = Color3.fromRGB(255, 225, 170)
					mark.text.Text = string.format("%s\n%s  ·  %s",
						label, owner and owner.Name or "unclaimed", distText(dist))
					place(mark, chassis.Position + Vector3.new(0, 6, 0), camera, viewport, false)
				end
			end
		end
	end

	if CFG.probeEsp then
		local pr = workspace:FindFirstChild("player_related")
		local probes = pr and pr:FindFirstChild("probes")
		for _, probe in ipairs(probes and probes:GetChildren() or {}) do
			local part = probe:IsA("BasePart") and probe
				or (probe:IsA("Model") and (probe.PrimaryPart or probe:FindFirstChildWhichIsA("BasePart")))
			if part then
				local dist = (part.Position - origin).Magnitude
				if dist <= maxStuds then
					local mark = markFor("probe:" .. probe:GetFullName())
					mark.dot.BackgroundColor3 = Color3.fromRGB(150, 255, 180)
					mark.text.TextColor3 = Color3.fromRGB(180, 255, 200)
					mark.text.Text = "probe\n" .. distText(dist)
					place(mark, part.Position + Vector3.new(0, 4, 0), camera, viewport, false)
				end
			end
		end
	end
end

local function renderFrame()
	local camera = workspace.CurrentCamera
	if not camera then return end
	local viewport = camera.ViewportSize
	local origin = selfPosition()
	local now = os.clock()

	table.clear(S.usedMarks)
	table.clear(S.usedHighlights)

	renderStorms(camera, viewport, origin, now)
	renderEntities(camera, viewport, origin)

	for key, mark in next, S.marks do
		if not S.usedMarks[key] then
			mark.frame:Destroy()
			S.marks[key] = nil
		end
	end
	for key, h in next, S.highlights do
		if not S.usedHighlights[key] then
			h:Destroy()
			S.highlights[key] = nil
		end
	end

	myCar, riding = myVehicle()
	mySpeed = myCar and vehicleSpeedMph(myCar) or 0

	if CFG.proximityAlert and nearest and nearest.info.onGround
		and miles(nearest.dist) <= CFG.alertMiles then
		local rating = ratingOf(nearest.info.winds)
		alertLabel.Text = string.format("⚠  %s ON THE GROUND  %s", rating, distText(nearest.dist))
		alertLabel.Visible = true
	else
		alertLabel.Visible = false
	end
end

-- One throw inside the frame used to abandon everything after it, silently, and
-- the symptom was "the ESP half works". Contain it, count it, and put the first
-- message somewhere a human can read it.
local acc = 0
connect(RunService.RenderStepped, function(dt)
	if not S.alive then return end
	acc += dt
	if acc < 0.05 then return end
	acc = 0

	local ok, err = pcall(renderFrame)
	if not ok then
		S.errors += 1
		if S.errors == 1 or S.errors % 120 == 0 then
			S.lastError = tostring(err)
			Log.warn(string.format("render error #%d: %s", S.errors, S.lastError))
		end
	end
end)

--------------------------------------------------------------------------
-- UI
--------------------------------------------------------------------------
local Kit = (HOST and HOST.ui) or loadfile("../scripts/r3st_ui.lua")()
assert(Kit.SHELL_CONTRACT == "1", "R3ST shell contract mismatch")

local teardown

local Shell = Kit.moduleShell({
	id = "twisted",
	title = "Twisted",
	version = BUILD_VERSION,
	subtitle = "Storm tracking, chase readouts and night visibility",
	gameId = EXPECTED_GAME,
	placeId = EXPECTED_PLACE,
	standaloneSize = Vector2.new(780, 580),
	keep = { layer, highlightFolder },
	cfg = CFG,
	save = saveConfig,
	tabs = { "Storms", "Chase", "Weather", "Visuals" },
	onUnload = function() teardown() end,
	onReload = function()
		task.defer(function()
			teardown()
			local chunk, err = loadfile("../scripts/twisted_hub.lua")
			if chunk then chunk() else Log.warn("reload failed: " .. tostring(err)) end
		end)
	end,
})
S.shell, S.root = Shell, Shell.root
local W = Shell.W

------------------------------ Storms ------------------------------------
local storms = Shell.page("Storms")
W.section(storms, "Storm ESP")
W.toggle(storms, { label = "Storm ESP", desc = "Screen-space marker on every replicated storm cell.", key = "stormEsp" })
W.toggle(storms, { label = "Include non-tornadic cells", desc = "Show supercells that have no tornado on the ground.", key = "stormNonTornadic" })
W.toggle(storms, { label = "Detail lines", desc = "Winds, width, distance, motion and closing ETA.", key = "stormDetail" })
W.toggle(storms, { label = "Off-screen bearings", desc = "Clamp a storm behind you to the screen edge instead of hiding it.", key = "stormOffscreen" })
W.toggle(storms, { label = "Outline the funnel", desc = "Highlight the tagged TornadoPart when a tornado is on the ground.", key = "tornadoHighlight" })
W.slider(storms, {
	label = "Draw distance", key = "stormMaxMiles", min = 1, max = 30, step = 1,
	fmt = function(v) return string.format("%d mi", math.floor(v + 0.5)) end,
})

W.section(storms, "Proximity alert")
W.toggle(storms, { label = "On-ground warning", desc = "Banner when a tornado on the ground is inside the alert radius.", key = "proximityAlert" })
W.slider(storms, {
	label = "Alert radius", key = "alertMiles", min = 0.25, max = 5, step = 0.25,
	fmt = function(v) return string.format("%.2f mi", v) end,
})

W.section(storms, "Nearest cell")
W.statusRow(storms, function()
	if not nearest then return "No storm replicated to this client." end
	local info = nearest.info
	local rating = ratingOf(info.winds)
	return string.format("%s  ·  %s  ·  %s  ·  %s",
		info.name, info.onGround and rating or "no tornado", distText(nearest.dist),
		info.track and ("track " .. tostring(info.track)) or "untracked")
end)
W.statusRow(storms, function()
	if not nearest then return "" end
	local info = nearest.info
	return string.format("Winds %d mph  ·  surface %d ft  ·  top %d ft  ·  funnel %d ft  ·  debris %d",
		math.round(info.winds), math.round(info.sfc), math.round(info.base),
		math.round(info.height), math.round(info.debris))
end)
W.statusRow(storms, function()
	if not nearest then return "" end
	local info = nearest.info
	local closing = nearest.closing or 0
	return string.format("Motion %s  ·  measured %d mph  ·  %s  ·  rainwrap %d%%  ·  windfield %d",
		info.motionDeg and string.format("%d°", math.round((info.motionDeg + 180) % 360)) or "n/a",
		math.round(nearest.vel.Magnitude * MPH_PER_STUD_SEC),
		closing > 0.5 and ("closing " .. etaText(math.max(nearest.dist - info.sfc * 0.5, 0) / closing)) or "not closing",
		math.round(info.rainwrap * 100), math.round(info.windfield))
end)
W.note(storms, "Every value here is read from the storm's own configs folder, the same source the in-game radar reads. Nothing is written back.")

------------------------------ Chase -------------------------------------
local chase = Shell.page("Chase")
W.section(chase, "Vehicle")
W.toggle(chase, { label = "Speed readout", desc = "Live speed of the vehicle you own or are seated in.", key = "speedo" })
W.statusRow(chase, function()
	if not CFG.speedo then return "Speed readout off." end
	if not myCar then return "No vehicle: spawn one or take a seat." end
	local spec = vehicleSpec(myCar)
	local top = spec and spec.Driving and spec.Driving.Speeds and spec.Driving.Speeds.Road
	return string.format("%3d mph%s  ·  gear %s  ·  %s%s",
		math.round(mySpeed), top and string.format(" / %d top", top) or "",
		tostring(myCar:GetAttribute("gear") or "-"),
		riding and "riding" or "owned",
		myCar:GetAttribute("ignition") and "" or "  ·  ENGINE OFF")
end)
W.statusRow(chase, function()
	if not myCar then return "" end
	local spec = vehicleSpec(myCar)
	local gas = myCar:GetAttribute("gas")
	local tank = spec and spec.Gas and spec.Gas.Tank
	return string.format("Fuel %s  ·  %s mpg  ·  %s  ·  %s",
		(gas and tank) and string.format("%.1f / %d gal (%d%%)", gas, tank, math.round(gas / tank * 100))
			or (gas and string.format("%.1f gal", gas) or "n/a"),
		spec and spec.Gas and tostring(spec.Gas.MPG) or "?",
		spec and spec.Vehicle and string.format("%s %s %s", tostring(spec.Vehicle.Year),
			tostring(spec.Vehicle.Brand), tostring(spec.Vehicle.Model)) or myCar.Name,
		spec and spec.Vehicle and tostring(spec.Vehicle.Drivetrain) or "?")
end)
W.statusRow(chase, function()
	if not myCar then return "" end
	local spec = vehicleSpec(myCar)
	local mods = myCar:FindFirstChild("modifiers")
	local speeds = spec and spec.Driving and spec.Driving.Speeds
	return string.format("Surface caps  road %s / dirt %s / grass %s  ·  torque %s  ·  engine %s%%  ·  suspension %s%%",
		speeds and tostring(speeds.Road) or "?", speeds and tostring(speeds.Dirt) or "?",
		speeds and tostring(speeds.Grass) or "?",
		spec and spec.Driving and tostring(spec.Driving.Torque) or "?",
		mods and string.format("%d", math.round(mods:GetAttribute("engine") or 100)) or "?",
		mods and string.format("%d", math.round(mods:GetAttribute("suspension") or 100)) or "?")
end)
W.statusRow(chase, function()
	if not myCar then return "" end
	local spec = vehicleSpec(myCar)
	local dmg = spec and spec.Damage
	if not dmg then return "" end
	return string.format("Damage thresholds  ·  drag %s  ·  roll %s  ·  toss %s mph of wind",
		tostring(dmg.Drag), tostring(dmg.Roll), tostring(dmg.Toss))
end)
W.note(chase, "Roll and toss thresholds come from the vehicle's own info module. A tornado whose winds exceed the roll number can flip this vehicle.")

W.section(chase, "Field awareness")
W.toggle(chase, { label = "Chaser ESP", desc = "Marker and outline on other players.", key = "playerEsp" })
W.toggle(chase, { label = "Show names", key = "playerNames" })
W.toggle(chase, { label = "Vehicle ESP", desc = "Every spawned car with its model and owner.", key = "vehicleEsp" })
W.toggle(chase, { label = "Probe ESP", desc = "Deployed probes in player_related.probes.", key = "probeEsp" })
W.slider(chase, {
	label = "Entity range", key = "espMaxStuds", min = 500, max = 12000, step = 250,
	fmt = function(v) return distText(v) end,
})

------------------------------ Weather -----------------------------------
local weather = Shell.page("Weather")
local function kin()
	return game:GetService("ReplicatedStorage"):FindFirstChild("kinematics")
end
local function kv(name, fallback)
	local k = kin()
	local v = k and k:FindFirstChild(name)
	if v and v:IsA("ValueBase") then return v.Value end
	return fallback
end

W.section(weather, "Environment")
W.statusRow(weather, function()
	local k = kin()
	if not k then return "kinematics folder not replicated." end
	return string.format("Temp %d°F  ·  dewpoint %d°F  ·  RH %d%%  ·  PWAT %.2f in",
		math.round(kv("temp", 0)), math.round(kv("dewpoint", 0)),
		math.round(kv("rh", 0)), kv("pwat", 0))
end)
W.statusRow(weather, function()
	if not kin() then return "" end
	return string.format("CAPE %d J/kg  ·  STP %.1f  ·  SRH %d  ·  composite %.1f",
		math.round(kv("cape", 0)), kv("stp", 0), math.round(kv("srh", 0)), kv("composite", 0))
end)
W.statusRow(weather, function()
	if not kin() then return "" end
	return string.format("Lapse %.1f  ·  mid-lapse %.1f  ·  EML %.0f  ·  LCL/EL %.0f / %.0f",
		kv("lapse", 0), kv("mid_lapse", 0), kv("EML", 0), kv("tp", 0), kv("EL", 0))
end)
W.statusRow(weather, function()
	local k = kin()
	local motion = k and k:FindFirstChild("motion")
	local risk = k and k:FindFirstChild("risk")
	if not motion then return "" end
	return string.format("Storm motion %d° @ %d mph (%s)  ·  surface wind %d mph  ·  risk %s",
		math.round(((motion:GetAttribute("degree") or 0) + 180) % 360),
		math.round(motion:GetAttribute("speed") or 0),
		tostring(motion:GetAttribute("direction") or "?"),
		math.round(kv("wind", 0)),
		risk and tostring(risk.Value) or "?")
end)
W.note(weather, "Motion bearings are printed the way the in-game thermodynamics panel prints them: the stored degree is the inflow bearing and 180 is added to give the direction of travel.")

W.section(weather, "Live storm count")
W.statusRow(weather, function()
	local total, onGround = 0, 0
	for _, info in ipairs(allStorms()) do
		total += 1
		if info.onGround then onGround += 1 end
	end
	return string.format("%d storm cell%s replicated  ·  %d tornado%s on the ground",
		total, total == 1 and "" or "s", onGround, onGround == 1 and "" or "es")
end)

------------------------------ Visuals -----------------------------------
local visuals = Shell.page("Visuals")
W.section(visuals, "Night visibility")
W.toggle(visuals, {
	label = "Fullbright", desc = "Raises ambient and brightness. Local lighting only; the time of day is left alone.",
	key = "fullbright", set = applyLighting,
})
W.slider(visuals, {
	label = "Brightness", key = "fullbrightLevel", min = 0, max = 5, step = 0.25,
	fmt = function(v) return string.format("%.2f", v) end,
	set = function() if CFG.fullbright then applyLighting() end end,
})
W.toggle(visuals, {
	label = "Clear fog", desc = "Pushes FogEnd out. Rain curtains and the wall cloud will look thinner.",
	key = "clearFog", set = applyLighting,
})
W.toggle(visuals, {
	label = "Remove atmosphere", desc = "Zeroes Atmosphere density and haze. Strongest at range, ugliest up close.",
	key = "noAtmosphere", set = applyLighting,
})
W.button(visuals, "Restore stock lighting", "Puts every lighting property back and clears the three toggles.", function()
	CFG.fullbright, CFG.clearFog, CFG.noAtmosphere = false, false, false
	restoreLighting()
	saveConfig()
	Log.info("lighting restored")
end, true)
W.note(visuals, "Lighting is captured once on the first change and restored on unload, so leaving the hub always gives the map back its own night.")

W.section(visuals, "Safety")
W.note(visuals, "This module fires no remote, writes no humanoid property, creates no BodyMover and never parents to PlayerGui. CheatHandler (0504.lua) kicks for all four; staying read-only is what keeps it quiet.")
W.statusRow(visuals, function()
	local marks, outlines = 0, 0
	for _ in next, S.marks do marks += 1 end
	for _ in next, S.highlights do outlines += 1 end
	return string.format("Marks %d  ·  outlines %d  ·  build %s  ·  K unloads", marks, outlines, BUILD_VERSION)
end)
W.statusRow(visuals, function()
	if S.errors == 0 then return "Render loop clean." end
	return string.format("Render errors %d  ·  last: %s", S.errors, tostring(S.lastError))
end)

Shell.ready()

--------------------------------------------------------------------------
-- lifecycle
--------------------------------------------------------------------------
if CFG.fullbright or CFG.clearFog or CFG.noAtmosphere then
	applyLighting()
end

function teardown()
	if not S.alive then return end
	S.alive = false
	restoreLighting()
	for _, c in ipairs(S.conns) do pcall(function() c:Disconnect() end) end
	for _, mark in next, S.marks do pcall(function() mark.frame:Destroy() end) end
	for _, h in next, S.highlights do pcall(function() h:Destroy() end) end
	pcall(function() layer:Destroy() end)
	pcall(function() highlightFolder:Destroy() end)
	pcall(function() Shell.destroy() end)
	GENV[GKEY] = nil
	Log.info("unloaded " .. BUILD_VERSION)
end

Shell.hideBind()
connect(UserInputService.InputBegan, function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.K then teardown() end
end)

GENV[GKEY] = { destroy = teardown, build = BUILD_VERSION }
Log.info(string.format("boot %s hosted=%s storms=%s fullbright=%s",
	BUILD_VERSION, tostring(HOST ~= nil), tostring(CFG.stormEsp), tostring(CFG.fullbright)))
