-- Backseat Rally Hub v2026-10-26.6
-- Camera: local FovOffset/CameraLean/CameraShake and DriverEye Attachment only.
-- Proof: dump 0029:438-442,515-516,737-738,769-786; no body CFrame writes.
-- Rollover resistance: dump 0027:1342-1345 lifts tyre force toward COM.
-- This reduces tyre-induced roll/pitch, not collision or airborne recovery.
-- Rungs 2/3/5: private driver tune, local PaceVoice, TTS and Music SoundGroup volume.
-- Music proof: dump 0011:71-130,174-187; 0064:555-571. No SetOptionRE calls.
-- Server sees stock telemetry and resulting motion. No remotes, hooks or
-- body CFrame/velocity writes. Higher grip/power is visible; acceptance is unknown.
-- Proof: 2026-10-26 dump 0020:200-202,336-383; 0027:930-1075,1187-1227,
-- 1437-1491; 0045:1564-1716. Stages anticheat config: 0175:153-173.
-- Shared cached CarTune tables are never modified. RPM/audio bands unchanged.
-- Re-inject safe: self-teardown; K unload, Delete panic. Saved state resumes.
local BUILD_VERSION = "2026-10-26.6"
local EXPECTED_GAME = 10769543742
local EXPECTED_PLACE = 94278659624110
local GKEY = "__BACKSEAT_RALLY_HUB"
local CONFIG_FILE = "backseat_rally_hub_config.json"
if game.GameId ~= EXPECTED_GAME and game.PlaceId ~= EXPECTED_PLACE then return end
local G = getgenv()
local Log = loadfile("log.lua")()("backseat_rally_hub", { print = false })
local HOST = G.__R3ST_HOST
if not (HOST and HOST.ui and HOST.host and HOST.host.Parent) then
	Log.info("Hub host unavailable; open through hub.lua")
	return
end
if G[GKEY] and G[GKEY].destroy then pcall(G[GKEY].destroy) end
local Players = game:GetService("Players")
local Http = game:GetService("HttpService")
local SoundService = game:GetService("SoundService")
local UIS = game:GetService("UserInputService")
local LP = Players.LocalPlayer

-- CORE BEGIN
local Core = {}
Core.defaults = { enabled = false, power = 1.35, speed = 1.1, grip = 1.3,
	stability = 1.15, brakes = 1.15, planted = 0 }
Core.limits = { power = { 1, 4 }, speed = { 1, 1.2 }, grip = { 1, 3 },
	stability = { 1, 2 }, brakes = { 1, 2.5 }, planted = { 0, 1 } }
function Core.profile(saved)
	local p = table.clone(Core.defaults)
	if type(saved) ~= "table" or getmetatable(saved) then return p end
	for k, default in next, p do
		local v = rawget(saved, k)
		if type(v) == type(default) then
			if type(v) == "boolean" then p[k] = v
			elseif v == v and math.abs(v) < math.huge then
				p[k] = math.clamp(v, Core.limits[k][1], Core.limits[k][2])
			end
		end
	end
	return p
end
Core.cameraDefaults = { enabled = false, fov = 20, back = 0, height = 0,
	pitch = 0, lean = 1, shake = 1 }
Core.cameraLimits = { fov = { 0, 40 }, back = { 0, 12 }, height = { -1, 6 },
	pitch = { -30, 20 }, lean = { 0, 1 }, shake = { 0, 1 } }
function Core.camera(saved)
	local out = table.clone(Core.cameraDefaults)
	if type(saved) ~= "table" or getmetatable(saved) then return out end
	for key, default in next, out do
		local value = rawget(saved, key)
		if type(value) == type(default) then
			if type(value) == "boolean" then out[key] = value
			elseif value == value and math.abs(value) < math.huge then
				out[key] = math.clamp(value, Core.cameraLimits[key][1], Core.cameraLimits[key][2])
			end
		end
	end
	return out
end
function Core.volume(value)
	if type(value) == "number" and value == value and math.abs(value) < math.huge then
		return math.clamp(value, 0, 1)
	end
	return nil
end
function Core.resolve(base, p)
	if not p.enabled then return base end
	local tune = table.clone(base)
	for _, key in ipairs({ "Engine", "Gears", "Tyres", "Steering", "Brakes", "Drag" }) do
		assert(type(base[key]) == "table", "unsupported tune: " .. key)
		tune[key] = table.clone(base[key])
	end
	-- Ratio reduction increases road speed at unchanged RPM; compensate thrust.
	tune.Gears.Ratios = table.clone(base.Gears.Ratios)
	for i, ratio in ipairs(base.Gears.Ratios) do tune.Gears.Ratios[i] = ratio / p.speed end
	tune.Engine.Force = base.Engine.Force * p.power * p.speed
	-- Compensate reverse ratio too: reverse thrust scales by power, not speed.
	tune.Gears.Reverse = base.Gears.Reverse / p.speed
	tune.Drag.Air = base.Drag.Air / (p.speed * p.speed)
	tune.Tyres.LateralGrip = base.Tyres.LateralGrip * p.grip
	tune.Tyres.LongitudinalGrip = base.Tyres.LongitudinalGrip * p.grip
	-- Stock chassis applies tyre force at contact + Up * height-to-COM * ForceLift.
	-- 1 removes the vertical lever arm, rather than clamping grip or faking rotation.
	if p.planted > 0 and type(base.Tyres.ForceLift) == "number" then
		tune.Tyres.ForceLift = base.Tyres.ForceLift + (1 - base.Tyres.ForceLift) * p.planted
	end
	tune.Steering.Stability = base.Steering.Stability * p.stability
	tune.Steering.BetaStability = base.Steering.BetaStability * p.stability
	tune.Steering.Rate = base.Steering.Rate * math.sqrt(p.stability)
	tune.Steering.ReturnRate = base.Steering.ReturnRate * math.sqrt(p.stability)
	tune.Brakes.Force = base.Brakes.Force * p.brakes
	return tune
end
function Core.release(session)
	if session and session.chassis.Tune == session.applied then
		session.chassis.Tune = session.base
	end
end
-- CORE END

local cfg = { profiles = {}, default = Core.profile(), muteNarrator = false, camera = Core.camera() }
local S = { alive = true, live = {}, conns = {}, status = "Waiting for driver adapter",
	revision = 0, volumes = {}, cameraAttrs = {}, cameraStatus = "Stock camera" }
local Shell
local function loadConfig()
	local ok, raw = pcall(readfile, CONFIG_FILE)
	if not ok then return end
	local decoded, data = pcall(Http.JSONDecode, Http, raw)
	if not decoded or type(data) ~= "table" then return end
	cfg.default = Core.profile(data.default)
	cfg.muteNarrator = data.muteNarrator == true
	cfg.musicVolume = Core.volume(data.musicVolume)
	cfg.camera = Core.camera(data.camera)
	if type(data.profiles) == "table" then
		for id, p in next, data.profiles do
			if type(id) == "string" and #id <= 80 then cfg.profiles[id] = Core.profile(p) end
		end
	end
end
local function saveNow()
	S.dirtyAt = nil
	local ok, raw = pcall(Http.JSONEncode, Http, cfg)
	if not ok then Log.err("config encode", raw); return end
	local written, err = pcall(writefile, CONFIG_FILE, raw)
	if not written then Log.err("config write", err) end
end
local function changed()
	S.revision += 1
	S.dirtyAt = os.clock()
end
local function profile()
	return S.profileKey and cfg.profiles[S.profileKey] or cfg.default
end
local function setProfile(key, value)
	-- UI callbacks change plain state only; the worker owns Instance writes.
	if not S.alive then return end
	local p = table.clone(profile())
	p[key] = value
	p = Core.profile(p)
	if S.profileKey then cfg.profiles[S.profileKey] = p else cfg.default = p end
	changed()
end
local function owned(chassis)
	return chassis and chassis.Car and chassis.Car.Parent and chassis.Body and chassis.Body.Parent
		and S.controller.LocalRole == "Driver" and S.controller.LocalCar == chassis.Car
		and chassis.Car:GetAttribute("DriverUserId") == LP.UserId
		and type(isnetworkowner) == "function" and isnetworkowner(chassis.Body)
end
local function clearSession()
	Core.release(S.session)
	S.session = nil
	S.profileKey = nil
end
local function tuneStep()
	local chassis = S.controller.GetChassis()
	if not owned(chassis) then
		clearSession(); S.status = "Enter the driver seat of your car"
		return
	end
	local id = chassis.Car:GetAttribute("CarId")
	if type(id) ~= "string" or id == "" then clearSession(); S.status = "CarId unavailable"; return end
	local sess = S.session
	if not sess or sess.chassis ~= chassis or sess.id ~= id
		or chassis.Tune ~= sess.applied then
		clearSession()
		cfg.profiles[id] = cfg.profiles[id] or Core.profile(cfg.default)
		S.profileKey = id
		sess = { chassis = chassis, id = id, base = chassis.Tune, applied = chassis.Tune, revision = -1 }
		S.session = sess
	end
	if sess.revision ~= S.revision then
		local p = profile()
		local resolved = Core.resolve(sess.base, p)
		chassis.Tune = resolved
		sess.applied = resolved
		sess.revision = S.revision
		Log.info(string.format("applied car=%s enabled=%s power=%.2f speed=%.2f grip=%.2f stability=%.2f brakes=%.2f force=%.3f->%.3f lateral=%.3f->%.3f gear1=%.3f->%.3f",
			id, tostring(p.enabled), p.power, p.speed, p.grip, p.stability, p.brakes,
			sess.base.Engine.Force, resolved.Engine.Force,
			sess.base.Tyres.LateralGrip, resolved.Tyres.LateralGrip,
			sess.base.Gears.Ratios[1], resolved.Gears.Ratios[1]))
		Log.info(string.format("rollover car=%s support=%.0f%% forceLift=%s->%s",
			id, p.planted * 100, tostring(sess.base.Tyres.ForceLift), tostring(resolved.Tyres.ForceLift)))
	end
	S.status = id .. (profile().enabled and " - Tuning ON" or " - Tuning OFF (stock)")
		.. string.format(" | rollover %.0f%%", profile().planted * 100)
end
local function tuneStatus()
	local sess = S.session
	if not sess then return "No active driver tune to compare" end
	local base, applied = sess.base, sess.chassis.Tune
	return string.format("Stock -> applied: force %.2f -> %.2f | grip %.2f -> %.2f",
		base.Engine.Force, applied.Engine.Force,
		base.Tyres.LateralGrip, applied.Tyres.LateralGrip)
end
local function restoreAudio()
	if S.paceOwned and LP:GetAttribute("PaceVoice") == false then
		LP:SetAttribute("PaceVoice", S.paceOriginal)
	end
	S.paceOwned = nil
	for obj, record in next, S.volumes do
		pcall(function() if obj.Parent and obj.Volume == 0 then obj.Volume = record.old end end)
	end
	table.clear(S.volumes)
end
local function audioStep()
	if not cfg.muteNarrator then restoreAudio(); return end
	if not S.paceOwned then
		S.paceOriginal = LP:GetAttribute("PaceVoice")
		LP:SetAttribute("PaceVoice", false)
		S.paceOwned = true
	end
	-- Only this game's local pace-note TTS, never partner voice or engine audio.
	for _, folder in ipairs(SoundService:GetChildren()) do
		if folder.Name == "PaceCallVoice" then
			for _, obj in ipairs(folder:GetDescendants()) do
				if obj:IsA("AudioTextToSpeech") and not S.volumes[obj] then
					S.volumes[obj] = { old = obj.Volume }
					obj.Volume = 0
				end
			end
		end
	end
	for obj in next, S.volumes do if not obj.Parent then S.volumes[obj] = nil end end
end
local function restoreMusic()
	local rec = S.music
	if rec then
		if rec.obj.Parent and rec.obj.Volume == rec.applied then rec.obj.Volume = rec.old end
		S.music = nil
	end
end
local function musicStep()
	local value = cfg.musicVolume
	if value == nil then restoreMusic(); return end
	local group = SoundService:FindFirstChild("Music")
	if not (group and group:IsA("SoundGroup")) then restoreMusic(); return end
	if S.music and S.music.obj ~= group then restoreMusic() end
	if not S.music then S.music = { obj = group, old = group.Volume } end
	local rec = S.music
	-- The dedicated bus preserves song fades/changes. No per-track volume writes.
	-- Do not fight a later game-settings write; a new slider choice takes control.
	if rec.applied ~= value then
		group.Volume = value
		rec.applied = value
		Log.info(string.format("music group volume %.2f (original %.2f)", value, rec.old))
	end
end
local function musicValue()
	if cfg.musicVolume ~= nil then return cfg.musicVolume end
	local group = SoundService:FindFirstChild("Music")
	return group and group:IsA("SoundGroup") and group.Volume or 1
end
local function restoreCamera()
	for key, rec in next, S.cameraAttrs do
		if LP:GetAttribute(key) == rec.applied then LP:SetAttribute(key, rec.old) end
	end
	table.clear(S.cameraAttrs)
	local eye = S.eye
	if eye and eye.obj.Parent and eye.obj.CFrame == eye.applied then eye.obj.CFrame = eye.old end
	S.eye = nil
	S.cameraStatus = "Stock camera"
end
local function cameraAttribute(key, value, additive)
	local rec = S.cameraAttrs[key]
	if not rec then
		rec = { old = LP:GetAttribute(key) }
		S.cameraAttrs[key] = rec
	end
	local target = value + (additive and type(rec.old) == "number" and rec.old or 0)
	if rec.applied ~= target then
		LP:SetAttribute(key, target)
		rec.applied = target
		Log.info("camera attribute=" .. key .. " applied=" .. tostring(target))
	end
end
local function cameraStep()
	local c, sess = cfg.camera, S.session
	if not c.enabled or not sess or not owned(sess.chassis) then restoreCamera(); return end
	cameraAttribute("FovOffset", c.fov, true)
	cameraAttribute("CameraLean", c.lean)
	cameraAttribute("CameraShake", c.shake)
	local primary = sess.chassis.Car.PrimaryPart
	local eye = primary and primary:FindFirstChild("DriverEye")
	if not (eye and eye:IsA("Attachment")) then
		-- Never move a BasePart, create a fallback attachment or replace the camera loop.
		local rec = S.eye
		if rec and rec.obj.Parent and rec.obj.CFrame == rec.applied then rec.obj.CFrame = rec.old end
		S.eye = nil
		S.cameraStatus = "FOV active; DriverEye Attachment unavailable"
		return
	end
	if S.eye and S.eye.obj ~= eye then
		local rec = S.eye
		if rec.obj.Parent and rec.obj.CFrame == rec.applied then rec.obj.CFrame = rec.old end
		S.eye = nil
	end
	local signature = string.format("%.4f/%.4f/%.4f", c.back, c.height, c.pitch)
	if not S.eye then S.eye = { obj = eye, old = eye.CFrame } end
	local rec = S.eye
	if rec.signature ~= signature then
		-- A later writer wins until the user makes a new camera choice.
		if rec.applied and eye.CFrame ~= rec.applied then rec.old = eye.CFrame end
		local target = rec.old * CFrame.new(0, c.height, c.back) * CFrame.Angles(math.rad(c.pitch), 0, 0)
		eye.CFrame = target
		rec.applied, rec.signature = target, signature
		Log.info(string.format("camera back=%.2f height=%.2f pitch=%.1f extraFov=%.1f",
			c.back, c.height, c.pitch, c.fov))
	end
	S.cameraStatus = string.format("Camera ON | extra FOV +%.0f | back %.1f | height %.1f | tilt %.0f",
		c.fov, c.back, c.height, c.pitch)
end
local function setCamera(key, value)
	if not S.alive then return end
	local c = table.clone(cfg.camera)
	c[key] = value
	cfg.camera = Core.camera(c)
	changed()
end
local function panic()
	if not S.alive then return end
	cfg.default.enabled = false
	for _, p in next, cfg.profiles do p.enabled = false end
	cfg.muteNarrator = false
	cfg.musicVolume = nil
	cfg.camera.enabled = false
	restoreCamera()
	changed()
end
local function destroy()
	if not S.alive then return end
	S.alive = false
	if S.worker then pcall(task.cancel, S.worker); S.worker = nil end
	saveNow()
	for _, conn in ipairs(S.conns) do pcall(function() conn:Disconnect() end) end
	clearSession()
	restoreAudio()
	restoreMusic()
	restoreCamera()
	if Shell then Shell.destroy() end
	if G[GKEY] == S.handle then G[GKEY] = nil end
	Log.info("unloaded; owned tune and narrator state restored")
end
local function main()
	Log.session(BUILD_VERSION)
	loadConfig()
	local Kit = HOST.ui
	assert(Kit.SHELL_CONTRACT == "1", "R3ST shell contract mismatch")
	Shell = Kit.moduleShell({ id = "backseat-rally", title = "Backseat Rally", version = BUILD_VERSION,
		subtitle = "Traction, handling, speed and pace notes", gameId = EXPECTED_GAME,
		placeId = EXPECTED_PLACE, tabs = { "Driving", "Camera", "Audio", "Settings" }, cfg = cfg,
		save = changed, live = S.live, conns = S.conns, onUnload = function() task.spawn(destroy) end,
		onSettings = function() Shell.show("Settings") end })
	local W = Shell.W
	local driving = Shell.page("Driving")
	W.section(driving, "Active car")
	W.statusRow(driving, function() return S.status end)
	W.statusRow(driving, tuneStatus)
	W.toggle(driving, { label = "Tuning enabled", desc = "Applies to the active car; sliders do not turn tuning on.",
		stateText = true, get = function() return profile().enabled end,
		set = function(v) setProfile("enabled", v) end })
	W.note(driving, "Saved per car. Check ON after changing cars. Before seating, edits set defaults for newly seen cars.")
	W.section(driving, "Speed and control")
	W.note(driving, "Raise one setting at a time. More power can add wheelspin; more grip can upset balance. Maximums are not a tested preset.")
	for _, row in ipairs({ { "power", "Acceleration" }, { "speed", "Top-speed gearing" },
		{ "grip", "Traction" }, { "stability", "Steering stability" }, { "brakes", "Braking" } }) do
		local key, label = row[1], row[2]
		W.slider(driving, { label = label, min = Core.limits[key][1], max = Core.limits[key][2], step = 0.05,
			get = function() return profile()[key] end,
			set = function(v) setProfile(key, v) end, fmt = function(v) return string.format("%.2fx", v) end })
	end
	W.slider(driving, { label = "Rollover resistance", min = 0, max = 1, step = 0.05,
		get = function() return profile().planted end,
		set = function(v) setProfile("planted", v) end,
		fmt = function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end })
	W.note(driving, "100% removes the tyre force's vertical roll/pitch lever arm. Helps high-grip turns, not impacts or jumps. Requires Tuning ON; no fake downforce.")
	W.button(driving, "Restore this car", "Disarms and resets only the current car profile.", function()
		if S.profileKey then cfg.profiles[S.profileKey] = Core.profile()
		else cfg.default = Core.profile() end
		changed()
	end)
	local camera = Shell.page("Camera")
	W.section(camera, "Driving view")
	W.statusRow(camera, function() return S.cameraStatus end)
	W.toggle(camera, { label = "Camera adjustments enabled", get = function() return cfg.camera.enabled end,
		set = function(v) setCamera("enabled", v) end })
	for _, row in ipairs({ { "fov", "Extra FOV", 1, " deg" }, { "back", "Camera distance", 0.25, " studs" },
		{ "height", "Camera height", 0.25, " studs" }, { "pitch", "Camera tilt", 1, " deg" },
		{ "lean", "Camera lean", 0.05, "x" }, { "shake", "Camera shake", 0.05, "x" } }) do
		local key, label, step, suffix = row[1], row[2], row[3], row[4]
		W.slider(camera, { label = label, min = Core.cameraLimits[key][1], max = Core.cameraLimits[key][2], step = step,
			get = function() return cfg.camera[key] end, set = function(v) setCamera(key, v) end,
			fmt = function(v) return string.format("%.2f%s", v, suffix) end })
	end
	W.button(camera, "Wide cockpit", "Wider road view, less head movement; enables camera adjustments.", function()
		cfg.camera = Core.camera({ enabled = true, fov = 20, lean = 0.25, shake = 0.25 }); changed()
	end)
	W.button(camera, "Raised road view", "Experimental rearward, raised view; enables camera adjustments.", function()
		cfg.camera = Core.camera({ enabled = true, fov = 20, back = 8, height = 3, pitch = -8, lean = 0, shake = 0 }); changed()
	end)
	W.button(camera, "Restore stock camera", "Disables adjustments and restores owned camera settings.", function()
		cfg.camera = Core.camera(); restoreCamera(); changed()
	end)
	W.note(camera, "Driver only; independent of Tuning ON. Distance moves the eye back, not the car. Negative tilt looks down. Stock FOV still changes with speed and caps at 120 degrees.")
	W.note(camera, "Raised view is experimental: the cockpit camera has no chase-camera wall avoidance and can hide the car body. Reset if the view clips.")
	local audio = Shell.page("Audio")
	W.section(audio, "Pace-note narrator")
	W.toggle(audio, { label = "Mute left / right callouts", key = "muteNarrator",
		get = function() return cfg.muteNarrator end,
		set = function(v) cfg.muteNarrator = v; changed() end })
	W.note(audio, "Mutes only the generated pace-note voice. Engine, music and partner voice stay unchanged.")
	W.section(audio, "Music")
	W.slider(audio, { label = "Music volume", min = 0, max = 1, step = 0.01,
		get = musicValue, set = function(v) cfg.musicVolume = Core.volume(v); changed() end,
		fmt = function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end })
	W.note(audio, "Saved music-only volume. 0% mutes songs; engine, pace notes and partner voice are separate.")
	W.button(audio, "Restore game music volume", "Releases the saved override and restores the owned original volume.", function()
		cfg.musicVolume = nil; changed()
	end)
	local settings = Shell.page("Settings")
	W.section(settings, "Restore")
	W.button(settings, "Panic restore", "Turns off tunes, camera, narrator mute and music override. Delete does the same.", panic)
	W.note(settings, "K unloads and restores stock without forgetting saved choices.")
	Shell.ready()
	S.handle = { build = BUILD_VERSION, embedded = true, destroy = destroy, panic = panic,
		status = function() return S.status end, tuneStatus = tuneStatus,
		cameraStatus = function() return S.cameraStatus end }
	G[GKEY] = S.handle
	S.conns[#S.conns + 1] = UIS.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode == Enum.KeyCode.Delete then panic()
		elseif input.KeyCode == Enum.KeyCode.K then task.spawn(destroy) end
	end)
	Log.info("boot " .. BUILD_VERSION .. " embedded=true narratorMute=" .. tostring(cfg.muteNarrator)
		.. " camera=" .. tostring(cfg.camera.enabled) .. " extraFov=" .. tostring(cfg.camera.fov))
	S.worker = task.spawn(function()
		local ok, err = xpcall(function()
			local ps = LP:WaitForChild("PlayerScripts", 10)
			local client = ps and ps:WaitForChild("Client", 10)
			local init = client and client:WaitForChild("Init", 10)
			local car = init and init:WaitForChild("Car", 10)
			local module = car and car:WaitForChild("CarController", 10)
			assert(module, "CarController unavailable")
			local controller = require(module)
			if not S.alive then return end
			assert(type(controller.GetChassis) == "function", "unsupported CarController")
			S.controller = controller
			while S.alive do
				tuneStep()
				audioStep()
				musicStep()
				cameraStep()
				if S.dirtyAt and os.clock() - S.dirtyAt >= 0.4 then saveNow() end
				-- Detect seat/build changes at 10 Hz; never rewrite a stable tune per frame.
				task.wait(0.1)
			end
		end, debug.traceback)
		if not ok and S.alive then
			S.status = "Adapter error: " .. tostring(err)
			Log.err("adapter", err)
			S.worker = nil
			destroy()
		end
	end)
end
local ok, err = xpcall(main, debug.traceback)
if not ok then Log.err("main", err); pcall(destroy) end
