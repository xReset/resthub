-- WideOpen Hub v2026-10-24.1 (2026-10-24)
-- Rungs 3/5: local contact detectors, attributes and owned-bike configuration.
-- Server sees stock telemetry/resulting braking; native settings may use the
-- game's debounced save. No new remotes, CFrame/velocity writes or namecall hooks.
-- Traffic prediction is local, constant-velocity, not server immunity.
-- Proof: 2026-10-20T03-58-56Z dump, 0006:785-860, 0008:451-554,
-- 0013:329-408, 0007:93-199, 0288:263-312, 0273:10-22.
-- ErrorReport listens to ScriptContext.Error: file logging only.
-- Re-inject safe: owned-field restore. Hub-only; K unload, Delete panic.
-- .2: vehicle guard gates local swept contact before crash reporting; not immunity.
-- Evidence: 0033:2657-2736, 0066:2366-2444, 0137:4625-4768, 0404:125-153,238-505.
-- .3: saved per-bike W + Space limiter runs at Bar, before the stock loop check.
-- 0013:396-415 calls StuntTricks.Bar after integration and before loop reporting.
-- .4: saved Ghost Driver-style player name/distance tags; bike visuals first.
-- 0198:82-97,145-205,340-347 and 0372:955-959 prove owner/visual-root mapping.
-- .5: per-bike crash flight recorder, swept warning/braking and native view/run shortcuts.
-- Proof: 0404:238-505, 0137:4538-4539,4673-4698, 0008:419-461,
-- 0005:457-519, 0273:87-91, 0137:1485-1525. No outgoing-report interception.
-- .6: predictor bypasses our Test adapter during pure nested Sweep calls.
-- .7: flush the old bike's window before despawn/rebind can clear it.
local BUILD_VERSION = "2026-10-24.1"
local EXPECTED_PLACE = 109959833715820
local EXPECTED_GAME = 10766812776
local GKEY = "__WIDEOPEN_HUB"
local CONFIG_FILE = "wideopen_hub_config.json"
if game.GameId ~= EXPECTED_GAME and game.PlaceId ~= EXPECTED_PLACE then return end
local G = getgenv()
local HOST = G.__R3ST_HOST
if type(HOST) ~= "table" or not HOST.ui then return end
if typeof(HOST.host) ~= "Instance" or not HOST.host.Parent then return end
if G[GKEY] and G[GKEY].destroy then pcall(G[GKEY].destroy) end
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local UIS = game:GetService("UserInputService")
local LP = Players.LocalPlayer
local Log = loadfile("log.lua")()("wideopen_hub", { print = false })
Log.session(BUILD_VERSION)

-- CORE BEGIN: pure functions, exercised by tests/test_wideopen.py.
local Core = {}
Core.defaults = {
	enabled = false, power = 1.35, speed = 1.2, shifts = 1,
	handling = false, grip = 1.2, brakes = 1.15, coast = 1, slide = 1,
	stunts = false, hold = false, fall = 0.5, rearBrake = 1.25, rise = 0.75,
	ecu = false, map = 2, pops = 2, flames = 2, color = 1, trafficBrake = false,
}
Core.limits = {
	power = { 0.5, 5 }, speed = { 0.75, 3 }, shifts = { 0.25, 2 },
	grip = { 0.5, 3 }, brakes = { 0.5, 3 }, coast = { 0.1, 2 }, slide = { 0, 1 },
	fall = { 0, 1 }, rearBrake = { 0.5, 3 }, rise = { 0.25, 1.5 },
	map = { 1, 3 }, pops = { 1, 4 }, flames = { 1, 4 }, color = { 1, 6 },
}
function Core.profile(saved)
	local out = table.clone(Core.defaults)
	if type(saved) ~= "table" or getmetatable(saved) then return out end
	for key, default in next, out do
		local v = rawget(saved, key)
		if type(v) == type(default) then
			if type(v) == "number" then
				if v == v and math.abs(v) < math.huge then
					local lim = Core.limits[key]
					out[key] = math.clamp(v, lim[1], lim[2])
					if key == "map" or key == "pops" or key == "flames" or key == "color" then
						out[key] = math.floor(out[key] + 0.5)
					end
				end
			else out[key] = v end
		end
	end
	return out
end
function Core.espAnchor(player, bikes, presentation)
	local bike = bikes and bikes:FindFirstChild(player.Name .. "_Bike")
	if bike then
		if bike:GetAttribute("OwnerUserId") ~= player.UserId then return end
		local record = presentation and presentation.records and presentation.records[bike]
		if record then
			local frame = presentation.Frame(bike)
			-- An inactive visual has no current location. Never tag its parked
			-- physics chassis as though that were the rendered rider.
			if not frame then return end
			local root = record.visualRoot
			if root and root.Parent and root:IsA("BasePart") then return root, frame.Position end
		end
		local root = bike:FindFirstChild("chassis_chassis")
		if root and root.Parent and root:IsA("BasePart") then return root, root.Position end
		return
	end
	-- Stock AdminPanel also falls back to the player's character off-bike.
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root and root.Parent and root:IsA("BasePart") then return root, root.Position end
end
function Core.espText(player, names, distance, position, origin)
	local text = names and player.Name or ""
	if distance and position and origin then
		text ..= (text ~= "" and "  " or "") .. math.floor((position - origin).Magnitude + 0.5) ..
			" studs"
	end
	return text
end
function Core.limitWheelie(ctx)
	local input, bike = ctx.input, ctx.BikeCfg
	local state = ctx.RideState or {}
	if not input or not bike or not input.Wheelie or not input.W or input.S
		or ctx.stunned or ctx.wheelieLooped or ctx.loopOut or state.Crash or state.Intro
		or (ctx.absSpeed or 0) < (bike.WheelieMinSpeed or 0) then return end
	local loop, angle, velocity = ctx.WHEELIE_LOOP, ctx.wheelieAngle, ctx.wheelieVel
	if type(loop) ~= "number" or type(angle) ~= "number" or type(velocity) ~= "number"
		or loop ~= loop or angle ~= angle or velocity ~= velocity
		or loop < math.rad(25) or loop >= math.huge or math.abs(velocity) == math.huge then return end
	-- Stock balance moves forward when clutch-sitting; stay below that balance
	-- and at least 12 degrees below loop-out. No loop flags/remotes are touched.
	local clutch = math.clamp(ctx.Trick and ctx.Trick.clutch or 0, 0, 1)
	local balance = loop * math.clamp(bike.WheelieBalanceFrac or 0.62, 0.35, 0.85)
		- math.rad(bike.ClutchSitBackDeg or 9) * clutch
	local ceiling = math.clamp(balance - math.rad(5), math.rad(8), loop - math.rad(12))
	if angle >= ceiling then
		ctx.wheelieAngle = ceiling
		ctx.wheelieVel = math.min(velocity, 0)
	end
	if type(ctx.wheelieTarget) == "number" then ctx.wheelieTarget = math.min(ctx.wheelieTarget,
		ceiling) end
	return ceiling
end
function Core.barAdapter(original, limit)
	local function finish(ctx, ...)
		limit(ctx)
		return ...
	end
	return function(ctx, ...)
		return finish(ctx, original(ctx, ...))
	end
end
function Core.contactAdapter(original, active)
	return function(...)
		if active() then return nil, math.huge, 0 end
		return original(...)
	end
end
function Core.restore(target, records)
	for key, r in next, records do
		if target[key] == r.last then target[key] = r.old end
	end
	table.clear(records)
end
function Core.write(target, records, key, value)
	local r = records[key]
	if not r then r = { old = target[key] }; records[key] = r end
	target[key] = value
	r.last = value
end
function Core.resolve(base, gears, p, baseMap, margin)
	local patch, derived = {}, {}
	local function scale(key, factor, fallback)
		local n = base[key]
		if type(n) ~= "number" then n = fallback end
		if n ~= nil then patch[key] = n * factor end
	end
	if p.ecu then
		local acc, lift = { 0.985, 1, 1.03 }, { 0.82, 1, 1.15 }
		scale("Acceleration", acc[p.map] / acc[baseMap])
		scale("WheelieBias", lift[p.map] / lift[baseMap], lift[baseMap])
	end
	if p.enabled then
		patch.Acceleration = (patch.Acceleration or base.Acceleration) * p.power
		scale("TopSpeed", p.speed)
		-- Scale drag with acceleration/speed^2 so the stock force relationship
		-- survives a preset; raising only TopSpeed leaves the drag wall intact.
		scale("DragCoefficient", p.power / (p.speed * p.speed), 0)
		local tops = {}
		for i, v in ipairs(gears) do tops[i] = v * p.speed end
		patch.GearTops = tops
		derived.GEAR_TOPS = tops
		derived.TOP_GEAR = #tops
	end
	if p.enabled or p.ecu then
		local a = patch.Acceleration or base.Acceleration
		local speed = (patch.TopSpeed or base.TopSpeed) * (base.DriveCeilingMargin or margin or 1)
		local d = a / (speed * speed) - (patch.DragCoefficient or base.DragCoefficient or 0)
		derived.DRIVE_TOP = d <= 1e-9 and speed * 4 or math.sqrt(a / d)
	end
	if p.handling then
		scale("TyreGrip", p.grip, 155)
		scale("BrakeDeceleration", p.brakes)
		scale("EngineBrakeDeceleration", p.coast)
		scale("RollingDeceleration", p.coast, 1.2)
		scale("SlideDriveLoss", p.slide, 0.35)
	end
	if p.stunts then
		scale("WheelieFallGain", p.fall, 6.5)
		scale("WheelieFallKick", p.fall, 0.45)
		scale("WheelieRearBrake", p.rearBrake, 9.5)
		scale("WheelieRiseNearBP", p.rise, 34)
		scale("WheelieRiseFree", p.rise, 90)
	end
	return patch, derived
end
function Core.finite(v)
	return type(v) == "number" and v == v and math.abs(v) < math.huge
end
function Core.brakeBudget(ctx, reaction)
	local b = ctx.BikeCfg
	local decel = b.BrakeDeceleration
	if not Core.finite(decel) or decel <= 0 then return end
	local rear = (ctx.wheelieAngle or 0) > 0.05 and (b.WheelieRearBrakeFrac or 0.35) or 1
	local f = math.clamp(((ctx.stoppieAngle or 0) / math.max(ctx.STOPPIE_LOOP or 1, 0.001) - 0.15) /
		0.2, 0, 1)
	decel *= rear * (1 - (1 - (b.StoppieBrakeFrac or 0.35)) * f * f * (3 - 2 * f))
	decel *= (ctx.RideState or {}).TouchBrk or 1
	if decel <= 0 then return end
	local speed = math.max(0, ctx.forwardSpeed or 0)
	return speed / decel + reaction, speed * speed / (2 * decel) + speed * reaction, decel
end
function Core.brakeAllowed(ctx)
	local r = ctx.RideState or {}
	return ctx.input and (ctx.forwardSpeed or 0) > 8 and not (ctx.stunned or ctx.loopOut
		or ctx.wheelieLooped or r.Crash or r.Intro or r.ReplayWorld or r.Photo
		or r.Tutorial or r.DuelResultOpen or ctx.lotMode or ctx.stoppieLooped
		or (ctx.Drift and ctx.Drift.burn and (ctx.Drift.burn.strength or 0) > 0.05))
end
function Core.brakeCall(original, active, ctx, ...)
	if not active or not Core.brakeAllowed(ctx) then return original(ctx, ...) end
	local old = ctx.input
	local input = table.clone(old)
	input.W, input.S = false, true
	ctx.input = input
	local result = table.pack(pcall(original, ctx, ...))
	-- Never leave a simulated key held or overwrite a newer input owner.
	if ctx.input == input then ctx.input = old end
	if not result[1] then error(result[2], 0) end
	return table.unpack(result, 2, result.n)
end
-- CORE END

local cfg = { profiles = {}, default = Core.profile(), railGuard = false,
	camera = false, fov = 78, sway = true, shake = false,
	esp = false, espNames = true, espDistance = true,
	diagnostics = true, trafficWarning = true }
do
	local ok, raw = pcall(readfile, CONFIG_FILE)
	local decoded, saved = false, nil
	if ok then decoded, saved = pcall(HttpService.JSONDecode, HttpService, raw) end
	if decoded and type(saved) == "table" then
		cfg.default = Core.profile(saved.default)
		if type(saved.profiles) == "table" then
			for key, p in next, saved.profiles do
				if type(key) == "string" then cfg.profiles[key] = Core.profile(p) end
			end
		end
		for _, key in ipairs({ "railGuard", "camera", "sway", "shake", "esp", "espNames", "espDistance",
			"diagnostics", "trafficWarning" }) do
			if type(saved[key]) == "boolean" then cfg[key] = saved[key] end
		end
		if type(saved.fov) == "number" and saved.fov == saved.fov then cfg.fov = math.clamp(saved.fov,
			55, 110) end
	end
end
local S = { alive = true, revision = 0, conns = {}, live = {}, session = nil,
	status = "Waiting for BikeController", dirtyAt = nil, modules = nil, cameraRecords = {},
	rail = nil, shell = nil, profileKey = nil, retired = {}, build = BUILD_VERSION,
	contactRecords = {}, trickRecords = {}, contactSkips = 0, guardAt = 0, guardLast = nil,
	tags = {}, espStatus = "ESP: off", espError = nil, espLast = nil,
	trafficStatus = "Traffic: waiting for bike", traffic = {}, frameDt = 0, maxFrameDt = 0 }
local function saveNow()
	S.dirtyAt = nil
	local ok, result = pcall(function() writefile(CONFIG_FILE, HttpService:JSONEncode(cfg)) end)
	if not ok then Log.err("config save", result) end
end
local function changed()
	S.revision += 1
	S.dirtyAt = os.clock()
end
local function profile()
	if S.profileKey then
		if not cfg.profiles[S.profileKey] then cfg.profiles[S.profileKey] = Core.profile(cfg.default) end
		return cfg.profiles[S.profileKey]
	end
	return cfg.default
end
local function setProfile(key, value)
	if not S.alive then return end
	profile()[key] = value
	changed()
end
local function restoreAttributes(sess)
	if not sess or not sess.bike.Parent then return end
	for key, r in next, sess.attrs do
		if sess.bike:GetAttribute(key) == r.last then sess.bike:SetAttribute(key, r.old) end
	end
	table.clear(sess.attrs)
end
local function clearSession()
	local sess = S.session
	if not sess then return end
	Core.restore(sess.config, sess.fields)
	-- The stock controller reuses one context across bikes. Its new cache is
	-- not ours even when an old scalar happens to equal the previous tune.
	if sess.ctx.currentBike == sess.bike and sess.ctx.BikeCfg == sess.config then
		Core.restore(sess.ctx, sess.cached)
	end
	-- Attribute writes must run in the worker, not the stock Heartbeat callback.
	S.retired[#S.retired + 1] = sess
	S.session = nil
end
local function owned(ctx)
	return type(ctx) == "table" and ctx.currentBike and ctx.currentBike.Parent
		and ctx.currentBike:GetAttribute("OwnerUserId") == LP.UserId
		and ctx.chassis and ctx.chassis.Parent and type(ctx.BikeCfg) == "table"
end
local function guardActive()
	local sess = S.session
	if S.readingTraffic or not S.alive or S.fault or not cfg.railGuard or not sess then return false
		end
	local ctx = sess.ctx
	local state = ctx.RideState or {}
	if not owned(ctx) or ctx.currentBike ~= sess.bike or ctx.BikeCfg ~= sess.config
		or ctx.loopOut or ctx.stunned or state.Crash or state.Intro or state.ReplayWorld then return
			false end
	S.contactSkips += 1
	return true
end
local function limitWheelie(ctx)
	local sess = S.session
	if not S.alive or S.fault or not sess or sess.ctx ~= ctx or not profile().hold
		or not owned(ctx) or ctx.currentBike ~= sess.bike or ctx.BikeCfg ~= sess.config then return end
	local success, fault = pcall(Core.limitWheelie, ctx)
	if not success then S.fault = tostring(fault) end
end
local function tune(ctx)
	if not S.alive or not owned(ctx) then return end
	local sess = S.session
	if not sess or sess.bike ~= ctx.currentBike or sess.config ~= ctx.BikeCfg then
		clearSession()
		local id = tostring(ctx.currentBike:GetAttribute("BikeId") or ctx.currentBike.Name)
		S.profileKey = id
		sess = { bike = ctx.currentBike, ctx = ctx, config = ctx.BikeCfg,
			fields = {}, cached = {}, attrs = {}, revision = -1, attrRevision = -1,
			baseMap = math.clamp(math.floor(tonumber(ctx.currentBike:GetAttribute("NFNC_EcuMap")) or 2), 1,
				3) }
		S.session = sess
		Log.info("bound bike=" .. id .. " trafficBrake=" .. tostring(profile().trafficBrake))
	end
	if sess.revision == S.revision then return end
	Core.restore(sess.config, sess.fields)
	Core.restore(ctx, sess.cached)
	local p = profile()
	local patch, derived = Core.resolve(sess.config, ctx.GEAR_TOPS, p, sess.baseMap,
		ctx.GameConfig and ctx.GameConfig.DriveCeilingMargin)
	if p.enabled then derived.SHIFT_CUT = ctx.SHIFT_CUT * p.shifts end
	for key, v in next, patch do Core.write(sess.config, sess.fields, key, v) end
	for key, v in next, derived do Core.write(ctx, sess.cached, key, v) end
	sess.revision = S.revision
	S.status = "Bound: " .. S.profileKey
	Log.info(string.format("apply bike=%s tune=%s power=%.2f speed=%.2f handling=%s stunts=%s "
		.. "hold=%s ecu=%s",
		S.profileKey, tostring(p.enabled), p.power, p.speed, tostring(p.handling), tostring(p.stunts),
			tostring(p.hold), tostring(p.ecu)))
end
local function applyAttributes()
	local sess = S.session
	if not sess or sess.attrRevision == S.revision then return end
	local p = profile()
	restoreAttributes(sess)
	if p.ecu and sess.bike.Parent then
		-- Map response is applied to the config only. Leaving NFNC_EcuMap
		-- untouched prevents a stock rebind from baking our map into its base.
		for key, value in next, { NFNC_EcuPops = p.pops,
			NFNC_EcuFlames = p.flames, NFNC_EcuCol = p.color } do
			local old = sess.bike:GetAttribute(key)
			sess.bike:SetAttribute(key, value)
			sess.attrs[key] = { old = old, last = value }
		end
	end
	sess.attrRevision = S.revision
end
local function applyRail()
	if cfg.railGuard then
		if not S.rail then
			S.rail = { old = workspace:GetAttribute("NFNC_NOCRASH"), last = true }
			workspace:SetAttribute("NFNC_NOCRASH", true)
		elseif workspace:GetAttribute("NFNC_NOCRASH") ~= true then
			-- Preserve a newer external value for unload, then re-arm our guard.
			S.rail.old = workspace:GetAttribute("NFNC_NOCRASH")
			workspace:SetAttribute("NFNC_NOCRASH", true)
			Log.info("guard attribute re-armed after external change")
		end
	elseif S.rail then
		if workspace:GetAttribute("NFNC_NOCRASH") == S.rail.last then
			workspace:SetAttribute("NFNC_NOCRASH", S.rail.old) end
		S.rail = nil
	end
end
local function applyCamera()
	if not S.modules then return end
	local settings = S.modules.settings
	if not settings then return end
	Core.restore(settings, S.cameraRecords)
	if cfg.camera then
		Core.write(settings, S.cameraRecords, "FOV", cfg.fov)
		Core.write(settings, S.cameraRecords, "CameraSway", cfg.sway)
		Core.write(settings, S.cameraRecords, "CameraShake", cfg.shake)
	end
end
-- TRAFFIC BEGIN: bounded flight recorder + observational geometry, never report calls.
local Assist = { ring = {}, head = 0, count = 0, events = {}, bikeConns = {}, previous = {}, seq =
	0,
	part = 1, bytes = 0, nextBeat = 0, lastScan = 0, nearest = {}, path = "not started" }
function Assist.value(v)
	local kind = typeof(v)
	if kind == "Vector3" then return { v.X, v.Y, v.Z } end
	if kind == "CFrame" then return { v:GetComponents() } end
	if kind == "number" then return Core.finite(v) and v or tostring(v) end
	if kind == "string" or kind == "boolean" then return v end
	return v ~= nil and tostring(v) or nil
end
function Assist.attributes(bike)
	local out = {}
	for k, v in next, bike:GetAttributes() do out[k] = Assist.value(v) end
	return out
end
function Assist.write(record)
	record.schema, record.build, record.run = 1, BUILD_VERSION, Assist.run
	local line = HttpService:JSONEncode(record) .. "\n"
	if Assist.bytes + #line > 4 * 1024 * 1024 then
		Assist.part = Assist.part == 1 and 2 or 1
		Assist.path = Assist.prefix .. Assist.part .. ".jsonl"
		writefile(Assist.path, "") -- only files this recorder created in this run
		Assist.bytes = 0
	end
	appendfile(Assist.path, line)
	Assist.bytes += #line
end
function Assist.snapshot()
	local sess = S.session
	local out = { clock = os.clock(), serverTime = workspace:GetServerTimeNow(), dt = S.frameDt,
		maxDt = S.maxFrameDt, scanAt = Assist.lastScan, nearest = Assist.nearest,
		guard = cfg.railGuard, noCrash = workspace:GetAttribute("NFNC_NOCRASH"), skipped = S.contactSkips,
		trafficSetting = S.modules and S.modules.settings.Traffic, trafficActive =
			LP:GetAttribute("Traffic"),
		bindId = Assist.bindId, revision = S.revision,
		worldEpoch = S.modules and S.modules.shift and S.modules.shift.LocalEpoch(),
		worldOffset = S.modules and S.modules.shift and S.modules.shift.LocalOffset(),
		ping = LP:GetNetworkPing(), brakeRequested = S.traffic.brake == true,
		brakeApplied = S.lastBrakeApplied == true, brakeTickAt = S.lastBrakeTickAt,
		brakeArmed = profile().trafficBrake, bikeId = S.profileKey }
	if sess then
		local c, b = sess.ctx, sess.bike
		local r = c.RideState or {}
		out.bike = b.Name
		out.contextMatchesBike = c.currentBike == b and c.BikeCfg == sess.config
		out.position, out.velocity = Assist.value(c.chassis.Position),
			Assist.value(c.chassis.AssemblyLinearVelocity)
		out.frame = Assist.value(c.chassis.CFrame)
		out.angularVelocity = Assist.value(c.chassis.AssemblyAngularVelocity)
		out.attributes = Assist.attributes(b)
		out.inputs = {}
		for k, v in next, c.input or {} do if type(v) ~= "table" then out.inputs[k] = Assist.value(v) end
			end
		out.state = {}
		for _, k in ipairs({ "forwardSpeed", "absSpeed", "wheelieAngle", "wheelieVel", "wheelieTarget",
			"stoppieAngle", "stoppieVel", "loopOut", "stunned", "wheelieLooped", "bikeScale", "lotMode" }) do
			out.state[k] = Assist.value(c[k])
		end
		out.ride = {}
		for _, k in ipairs({ "Crash", "Intro", "LoopOut", "Lean", "ReplayWorld", "Photo", "TouchBrk" }) do
			local v = r[k]
			if type(v) == "table" then
				local crash = {}
				for _, key in ipairs({ "cause", "t", "start", "active" }) do crash[key] = Assist.value(v[key])
					end
				out.ride[k] = crash
			else out.ride[k] = Assist.value(v) end
		end
	end
	return out
end
function Assist.event(kind, detail)
	if not S.alive or not cfg.diagnostics then return end
	local ok, sample = pcall(Assist.snapshot)
	if not ok then return end -- observers must never throw into ScriptContext.Error
	Assist.seq += 1
	if #Assist.events >= 16 then table.remove(Assist.events, 1) end
	Assist.events[#Assist.events + 1] = { kind = "event", event = kind, detail =
		tostring(detail):sub(1, 160),
		seq = Assist.seq, sample = sample }
end
function Assist.history()
	local out = {}
	for i = 1, Assist.count do out[i] = Assist.ring[(Assist.head - Assist.count + i - 1) % 80 + 1] end
	return out
end
function Assist.bind()
	local sess = S.session
	if Assist.session == sess then return end
	-- Crash/despawn may retire the session before this worker sees the event.
	-- Preserve the OLD window before clearing the ring for a different bike.
	if cfg.diagnostics and Assist.count > 0 then
		Assist.write({ kind = "vehicle_window", bindId = Assist.bindId, clock = os.clock(), frames =
			Assist.history() })
	end
	for _, conn in ipairs(Assist.bikeConns) do conn:Disconnect() end
	table.clear(Assist.bikeConns)
	Assist.session, Assist.previous, Assist.nearest, Assist.lastPose = sess, {}, {}, nil
	Assist.bindId = (Assist.bindId or 0) + 1
	Assist.configRevision = nil
	Assist.ring, Assist.head, Assist.count = {}, 0, 0
	S.traffic = {}
	if not sess then return end
	local config = {}
	for k, v in next, sess.config do
		if type(v) == "number" or type(v) == "boolean" or type(v) == "string" then config[k] =
			Assist.value(v) end
	end
	config.GearTops = sess.config.GearTops
	if cfg.diagnostics then
		Assist.write({ kind = "bind", sample = Assist.snapshot(), effectiveConfig = config,
			profile = table.clone(profile()), configChanges = sess.fields,
			note = "nav is distance,speed,lane; nearest geometry is client-rendered, not server truth" })
	end
	for _, key in ipairs({ "NFNC_Doomed", "NFNC_Crashed", "NFNC_Ghost", "NFNC_OffBike" }) do
		Assist.bikeConns[#Assist.bikeConns + 1] =
			sess.bike:GetAttributeChangedSignal(key):Connect(function()
			if S.session == sess then Assist.event("attribute:" .. key, sess.bike:GetAttribute(key)) end
		end)
	end
end
function Assist.sweep(...)
	-- Stock Sweep calls its module's Test in two branches (0404:287,502).
	-- Bypass only our guard while evaluating that pure, non-yielding geometry.
	-- Do not swap shared functions; restore the flag even if the stock call fails.
	local old = S.readingTraffic
	S.readingTraffic = true
	local result = table.pack(pcall(S.modules.rawSweep, ...))
	S.readingTraffic = old
	if not result[1] then error(result[2], 0) end
	return table.unpack(result, 2, result.n)
end
function Assist.scan()
	local sess, now = S.session, os.clock()
	S.traffic = {}
	if not sess or not owned(sess.ctx) then S.trafficStatus = "Traffic: waiting for your bike"; return
		end
	local c = sess.ctx
	local pos, velocity = c.chassis.Position, c.chassis.AssemblyLinearVelocity
	local look = c.chassis.CFrame.LookVector * Vector3.new(1, 0, 1)
	look = look.Magnitude > 0.0001 and look.Unit or Vector3.new(1, 0, 0)
	local reaction = LP:GetNetworkPing() + math.max(S.frameDt, 0.1) + 0.25
	local stopTime, stopDistance, decel = Core.brakeBudget(c, reaction)
	local horizon = math.clamp(stopTime or 2, 1.5, 4)
	local scoring = S.modules.gameConfig.Scoring or {}
	local halfW = (scoring.BikeHalfWidth or 0.55) * (1 - math.abs((c.RideState or {}).Lean or 0) *
		0.22)
	local halfL = scoring.BikeHalfLength or 2.2
	local folder = workspace:FindFirstChild("Traffic")
	local rows, previous, count, fresh, best, bestCar, bestRow = {}, {}, 0, 0, nil, nil, nil
	local pose = Assist.lastPose
	local poseOK = pose and now - pose.at <= 0.3 and (pos - pose.pos).Magnitude <= math.max(180, (now
		- pose.at) * 1500)
	for _, model in ipairs(folder and folder:GetChildren() or {}) do
		local root = model:IsA("Model") and model.PrimaryPart
		if not root then continue end
		count += 1
		local cf, offset = root.CFrame, model:GetAttribute("RootOffset")
		if typeof(offset) == "CFrame" then cf *= offset:Inverse() end
		local old = Assist.previous[model]
		local draw = (S.modules.state.TrafficDraw or {})[model]
		local stamp = (S.modules.state.TrafficNavT or {})[model] or (draw and draw.nt)
		local age = Core.finite(stamp) and workspace:GetServerTimeNow() - stamp or nil
		local width, length, height = model:GetAttribute("Width") or 8.4, model:GetAttribute("Length") or
			16, model:GetAttribute("PivotToBottom") or 3.5
		local row = { id = model:GetAttribute("TrafficId"), name = model.Name, distance = (cf.Position -
			pos).Magnitude,
			frame = Assist.value(cf), width = width, length = length, pivotToBottom = height,
			nav = Assist.value(model:GetAttribute("Nav")), navAge = age, navA = model:GetAttribute("NavA"),
			drawAge = draw and draw.drawAt and now - draw.drawAt, drawX = draw and draw.drawX,
			drawLat = draw and draw.drawLat, navX = draw and draw.nx, navSpeed = draw and draw.nv,
			braking = model:GetAttribute("Braking") }
		previous[model] = { cf = cf, at = now, root = root }
		local dt = old and now - old.at or 0
		local valid = old and old.root == root and dt >= 0.02 and dt <= 0.3
			and (cf.Position - old.cf.Position).Magnitude <= math.max(80, dt * 450)
		local carVelocity = valid and (cf.Position - old.cf.Position) / dt or nil
		-- A shift, stale feed, swapped root or first observation must not arm braking.
		valid = valid and poseOK and carVelocity.Magnitude < 600 and age and age >= -0.2 and age < 2
		row.fresh = not not valid
		row.velocity = carVelocity and Assist.value(carVelocity)
		if valid then
			fresh += 1
			if row.distance < (velocity.Magnitude + carVelocity.Magnitude) * horizon + 80 then
				local hit, gap, _, fraction = Assist.sweep(cf, cf, width * 0.5, length * 0.5, height,
					pos, pos + (velocity - carVelocity) * horizon, look, look, halfW, halfL)
				row.predictedKind, row.predictedGap = hit, Assist.value(gap)
				if hit == "hit" and Core.finite(fraction) then
					row.ttc = math.clamp(fraction, 0, 1) * horizon
					if not best or row.ttc < best then best, bestCar, bestRow = row.ttc, row.id or row.name, row
						end
				end
				local actual = Assist.sweep(old.cf, cf, width * 0.5, length * 0.5, height,
					pose.pos, pos, pose.look, look, halfW, halfL)
				row.observedSweep = actual
			end
		end
		rows[#rows + 1] = row
	end
	table.sort(rows, function(a, b) return a.distance < b.distance end)
	while #rows > 6 do table.remove(rows) end
	if bestRow then
		bestRow.threat = true
		if not table.find(rows, bestRow) then rows[math.max(1, #rows)] = bestRow end
	end
	Assist.previous, Assist.nearest, Assist.lastScan = previous, rows, now
	Assist.lastPose = { pos = pos, look = look, at = now, velocity = velocity }
	local brake = best and stopTime and best <= stopTime and Core.brakeAllowed(c)
	S.traffic = { at = now, bike = sess.bike, brake = profile().trafficBrake and not not brake,
		needsBrake = not not brake, ttc = best,
		car = bestCar, stopTime = stopTime, stopDistance = stopDistance, decel = decel, horizon = horizon,
		cars = count, fresh = fresh,
		observedDeceleration = poseOK and (pose.velocity - velocity):Dot(look) / (now - pose.at) or nil }
	if not cfg.trafficWarning and not profile().trafficBrake then S.trafficStatus =
		"Traffic warning: off (recorder may remain active)"
	elseif best then
		S.trafficStatus = string.format("%s: car %s in %.2fs | stop %.1fs / %.0f studs (estimate)",
			profile().trafficBrake and brake and "BRAKING" or "COLLISION WARNING", tostring(bestCar), best,
				stopTime or 0, stopDistance or 0)
	elseif fresh == 0 then S.trafficStatus =
		string.format("Forecast UNKNOWN: 0/%d fresh cars | braking released", count)
	else S.trafficStatus =
		string.format("No predicted hit in %.1fs | %d/%d cars fresh; NOT a safety guarantee", horizon,
		fresh, count) end
end
function Assist.step()
	Assist.bind()
	if not cfg.diagnostics and not cfg.trafficWarning and not profile().trafficBrake then
		S.traffic = {}; S.trafficStatus = "Traffic assistance: off"; return
	end
	Assist.scan()
	local now = os.clock()
	if cfg.diagnostics then
		local snapshot = Assist.snapshot()
		snapshot.prediction = table.clone(S.traffic); snapshot.prediction.bike = nil
		Assist.head = Assist.head % 80 + 1
		Assist.ring[Assist.head] = snapshot
		Assist.count = math.min(80, Assist.count + 1)
		if Assist.configRevision ~= S.revision and now >= (Assist.configAt or 0) then
			local config = {}
			if S.session then
				for k, v in next, S.session.config do
					if type(v) == "number" or type(v) == "boolean" or type(v) == "string" then config[k] =
						Assist.value(v) end
				end
			end
			Assist.write({ kind = "configuration", clock = now, bikeId = S.profileKey, bindId =
				Assist.bindId,
				revision = S.revision, effectiveConfig = config, profile = table.clone(profile()) })
			Assist.configRevision, Assist.configAt = S.revision, now + 0.4
		end
		if #Assist.events > 0 then
			Assist.write({ kind = "pre_event_window", clock = now, frames = Assist.history() })
			for _, event in ipairs(Assist.events) do Assist.write(event) end
			table.clear(Assist.events)
			Assist.postUntil, Assist.nextBeat = now + 3, 0
		end
		if now >= Assist.nextBeat then
			Assist.write({ kind = "sample", sample = snapshot })
			Assist.nextBeat = now + (Assist.postUntil and now < Assist.postUntil and 0.1 or 2)
		end
	else table.clear(Assist.events); Assist.ring, Assist.count, Assist.head = {}, 0, 0 end
	S.maxFrameDt = 0
end
function Assist.start()
	Assist.run = tostring(DateTime.now().UnixTimestampMillis) .. "_" .. tostring(math.random(1000,
		9999))
	Assist.prefix = "logs/wideopen_traffic_" .. Assist.run .. "_"
	Assist.path = Assist.prefix .. "1.jsonl"
	writefile(Assist.path, "")
	Assist.write({ kind = "session", diagnostics = cfg.diagnostics, warning = cfg.trafficWarning,
		note = "80-frame (~8s) event window; two 4MiB rolling files per run; no report hooks" })
	local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
	local event = remotes and remotes:FindFirstChild("CrashEvent")
	if event and event:IsA("RemoteEvent") then
		S.conns[#S.conns + 1] = event.OnClientEvent:Connect(function(cause) Assist.event("CrashEvent",
			cause) end)
	end
end
function Assist.stop()
	for _, conn in ipairs(Assist.bikeConns) do conn:Disconnect() end
	table.clear(Assist.bikeConns)
	if Assist.run and cfg.diagnostics then
		pcall(function()
			for _, event in ipairs(Assist.events) do Assist.write(event) end
			Assist.write({ kind = "unload", clock = os.clock(), frames = Assist.history() })
		end)
	end
end
-- TRAFFIC END
-- ESP BEGIN: PlayerGui billboards, never children of the Hub ScreenGui.
local ESP = {}
function ESP.clearTag(player)
	local entry = S.tags[player]
	if entry then
		S.tags[player] = nil
		entry.gui:Destroy()
	end
end
function ESP.clear()
	for player in next, S.tags do ESP.clearTag(player) end
end
function ESP.makeTag(player, root, host)
	local gui = Instance.new("BillboardGui")
	local entry = { gui = gui }
	S.tags[player] = entry -- register before setting properties for fault cleanup
	gui.Name = "WideOpen_Player_" .. player.UserId
	gui.Adornee = root
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	gui.MaxDistance = math.huge
	gui.Size = UDim2.fromOffset(340, 52)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 3.6, 0)
	local label = Instance.new("TextLabel")
	label.Name = "L"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 21
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.TextStrokeTransparency = 0.25
	label.RichText = false
	label.Text = player.Name
	label.Parent = gui
	entry.label = label
	gui.Parent = host
	return entry
end
function ESP.step()
	if not cfg.esp or not (cfg.espNames or cfg.espDistance) then
		ESP.clear()
		S.espStatus = cfg.esp and "ESP: names and distance hidden" or "ESP: off"
		return
	end
	local host = LP:FindFirstChildOfClass("PlayerGui")
	if not host or not host.Parent then ESP.clear(); S.espStatus = "ESP: waiting for PlayerGui";
		return end
	local bikes = workspace:FindFirstChild("ActiveBikes")
	local presentation = S.modules and S.modules.presentation
	local _, origin = Core.espAnchor(LP, bikes, presentation)
	local seen, count, others = {}, 0, 0
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LP then
			others += 1
			local root, position = Core.espAnchor(player, bikes, presentation)
			if root then
				seen[player] = true
				local entry = S.tags[player]
				if entry and (entry.gui.Parent ~= host or not entry.label or entry.label.Parent ~= entry.gui)
					then
					ESP.clearTag(player); entry = nil
				end
				if not entry then entry = ESP.makeTag(player, root, host) end
				entry.gui.Adornee = root
				entry.label.Text = Core.espText(player, cfg.espNames, cfg.espDistance, position, origin)
				entry.gui.Enabled = entry.label.Text ~= ""
				if entry.gui.Enabled then count += 1 end
			end
		end
	end
	for player in next, S.tags do if not seen[player] then ESP.clearTag(player) end end
	S.espStatus = string.format("ESP: %d tags / %d other players (streamed locations only)", count,
		others)
end
-- ESP END
local function panic()
	cfg.default.enabled, cfg.default.handling, cfg.default.stunts, cfg.default.hold, cfg.default.ecu =
		false, false, false, false, false
	for _, p in next, cfg.profiles do p.enabled, p.handling, p.stunts, p.hold, p.ecu = false, false,
		false, false, false end
	cfg.railGuard, cfg.camera, cfg.esp, cfg.trafficWarning = false, false, false, false
	cfg.default.trafficBrake = false
	for _, p in next, cfg.profiles do p.trafficBrake = false end
	S.traffic = {}
	changed()
	S.status = "Panic: all features OFF"
end
local function destroy()
	if not S.alive then return end
	S.alive = false
	saveNow()
	for _, c in ipairs(S.conns) do c:Disconnect() end
	if S.modules and S.modules.drive.step == S.modules.wrapper then S.modules.drive.step =
		S.modules.original end
	clearSession()
	for _, sess in ipairs(S.retired) do restoreAttributes(sess) end
	table.clear(S.retired)
	if S.rail and workspace:GetAttribute("NFNC_NOCRASH") == true then
		workspace:SetAttribute("NFNC_NOCRASH", S.rail.old) end
	if S.modules and S.modules.settings then Core.restore(S.modules.settings, S.cameraRecords) end
	if S.modules and S.modules.contact then Core.restore(S.modules.contact, S.contactRecords) end
	if S.modules and S.modules.tricks then Core.restore(S.modules.tricks, S.trickRecords) end
	ESP.clear()
	if S.recorder then S.recorder.stop() end
	if S.shell then S.shell.destroy() end
	if G[GKEY] == S then G[GKEY] = nil end
	Log.info("unloaded " .. BUILD_VERSION)
end
S.destroy = destroy
G[GKEY] = S

local function main()
	local Kit = HOST.ui
	assert(Kit.SHELL_CONTRACT == "1", "R3ST shell contract mismatch")
	local Shell
	Shell = Kit.moduleShell({ id = "wideopen", title = "WideOpen", version = BUILD_VERSION, hostGlobal
		= HOST,
		subtitle = "Bike tuning, stunts, exhaust and player names", gameId = EXPECTED_GAME, placeId =
			EXPECTED_PLACE,
		tabs = { "Speed", "Handling", "Traffic", "Stunts", "Exhaust", "ESP", "Settings" }, cfg = {}, save
			= changed,
		live = S.live, conns = S.conns, onUnload = function() task.spawn(destroy) end,
		onSettings = function() Shell.show("Settings") end })
	S.shell, S.root = Shell, Shell.root
	local W = Shell.W
	local function toggle(page, key, label, desc)
		W.toggle(page, { label = label, desc = desc, key = key,
			get = function() return profile()[key] end, set = function(v) setProfile(key, v) end })
	end
	local function slider(page, key, label, step, names)
		local lim = Core.limits[key]
		W.slider(page, { label = label, key = key, min = lim[1], max = lim[2], step = step,
			get = function() return profile()[key] end, set = function(v) setProfile(key, v) end,
			fmt = function(v) return names and names[math.floor(v + 0.5)] or string.format("%.2fx", v) end })
	end
	local speed = Shell.page("Speed")
	W.section(speed, "Bike profile")
	W.statusRow(speed, function() return "Editing: " .. (S.profileKey or "defaults for new bikes") end)
	toggle(speed, "enabled", "Drive tuning", "Applies saved power, gearing and drag to your bike.")
	slider(speed, "power", "Acceleration", 0.05)
	slider(speed, "speed", "Top speed / gearing", 0.05)
	slider(speed, "shifts", "Shift cut duration", 0.05)
	W.section(speed, "Presets")
	local function preset(values)
		local p = Core.profile()
		for k, v in next, values do p[k] = v end
		if S.profileKey then cfg.profiles[S.profileKey] = p else cfg.default = p end
		changed()
	end
	W.button(speed, "Balanced", "1.35x acceleration, 1.2x gearing; mild handling.", function()
		preset({ enabled = true, power = 1.35, speed = 1.2, handling = true }) end)
	W.button(speed, "Fast", "2x acceleration, 1.6x gearing; stronger grip and brakes.", function()
		preset({ enabled = true, power = 2, speed = 1.6, shifts = 0.75, handling = true, grip = 1.5,
			brakes = 1.4 }) end)
	W.button(speed, "Stunt", "Stock drive; reduced wheelie fall and slower rise.", function()
		preset({ stunts = true, fall = 0.3, rearBrake = 1.5, rise = 0.6 }) end)
	W.button(speed, "Restore this bike", "Disarms this profile and restores its original fields.",
		function() preset({}) end)
	W.note(speed,
		"No cash, unlock or nitrous packets. Increased speed is visible to other players; server "
		.. "tolerance is unknown.")
	local handling = Shell.page("Handling")
	W.section(handling, "Road feel")
	toggle(handling, "handling", "Handling tuning", "Separate from the drive master.")
	slider(handling, "grip", "Tire grip", 0.05)
	slider(handling, "brakes", "Braking force", 0.05)
	slider(handling, "coast", "Coasting drag", 0.05)
	slider(handling, "slide", "Slide power loss", 0.05)
	W.section(handling, "Contact")
	W.toggle(handling, { label = "Vehicle / contact guard", key = "railGuard", get = function() return
		cfg.railGuard end,
		set = function(v) cfg.railGuard = v; changed() end,
		desc = "Gates local traffic sweeps and supported contact reports before a crash starts." })
	W.note(handling,
		"Cars already use non-colliding visuals; geometry still reports hits. No server immunity, "
		.. "loop-out or boundary-correction guarantee.")
	local traffic = Shell.page("Traffic")
	W.section(traffic, "Predictive assistance")
	W.toggle(traffic, { label = "Traffic collision warning", key = "trafficWarning", get = function()
		return cfg.trafficWarning end,
		set = function(v) cfg.trafficWarning = v; changed() end, desc =
			"Sweeps full car dimensions against relative motion; status below, not immunity." })
	toggle(traffic, "trafficBrake", "Predictive braking (this bike)",
		"Experimental: stock brake branch only; cuts throttle during predicted danger. Saved per "
		.. "bike, OFF initially.")
	W.statusRow(traffic, function() return S.trafficStatus end)
	W.note(traffic,
		"Constant-velocity forecast up to 4 seconds. Stale/missing traffic releases braking, not "
		..
		"proof of safety. Corners, sudden lane changes, wheelies and server geometry can defeat "
		.. "it. Brake/steer yourself.")
	W.section(traffic, "Crash flight recorder")
	W.toggle(traffic, { label = "Detailed crash telemetry", key = "diagnostics", get = function()
		return cfg.diagnostics end,
		set = function(v) cfg.diagnostics = v; changed() end, desc =
			"Per-bike config, inputs, 8s pre-event buffer, nearest traffic, ping and incoming "
			.. "crash/attribute events. Local files only." })
	W.statusRow(traffic, function() return "Recorder: " .. Assist.path end)
	W.button(traffic, "Save traffic snapshot",
		"Writes the buffered window on the next worker tick when telemetry is ON.", function()
		Assist.event("manual", "Hub snapshot") end)
	W.note(traffic,
		"Two rolling 4 MiB files per injection; previous injections remain separate. No synthetic "
		..
		"crash and no outgoing-report hook. Nearest-car frames are client observations, not "
		.. "server hitboxes.")
	W.section(traffic, "Traffic for next run")
	W.statusRow(traffic, function()
		return "Next run: " .. tostring(S.modules and S.modules.settings.Traffic) .. " | active: " ..
			tostring(LP:GetAttribute("Traffic"))
	end)
	for _, choice in ipairs({ "None", "Light", "Mild", "Heavy" }) do
		W.button(traffic, "Traffic: " .. choice,
			"Stock setting; start the next run normally. Does not remove active traffic.", function()
			if S.modules and type(S.modules.settings.Set) == "function" then
				S.modules.settings.Set("Traffic", choice)
				Log.info("native traffic next run=" .. choice)
			end
		end)
	end
	local stunts = Shell.page("Stunts")
	W.section(stunts, "Wheelie assistance")
	toggle(stunts, "hold", "Wheelie limiter / hold",
		"Hold W + Space: catches pitch below balance before the loop-out check. Independent of "
		.. "drive tuning.")
	toggle(stunts, "stunts", "Wheelie physics tuning",
		"Optional fall, rear-brake and rise adjustments; does not fake inputs.")
	slider(stunts, "fall", "Over-balance fall strength", 0.05)
	slider(stunts, "rearBrake", "Rear-brake correction", 0.05)
	slider(stunts, "rise", "Wheelie rise rate", 0.05)
	W.note(stunts,
		"Limiter releases on brake, Space release, low speed or a crash. Stoppies and other crash "
		.. "paths remain stock. Saved per bike and armed on reload.")
	local exhaust = Shell.page("Exhaust")
	W.section(exhaust, "Local ECU and effects")
	toggle(exhaust, "ecu", "ECU / exhaust override",
		"Local settings only; does not purchase or save upgrades on the server.")
	slider(exhaust, "map", "ECU response", 1, { "Smooth", "Sport", "Race" })
	slider(exhaust, "pops", "Exhaust pops", 1, { "Clean", "Stock", "Loud", "Full send" })
	slider(exhaust, "flames", "Flames", 1, { "Off", "Stock", "Big", "Huge" })
	slider(exhaust, "color", "Flame color", 1, { "Classic", "Blue", "Purple", "Green", "Red", "Pink" })
	W.note(exhaust,
		"Stock readers may require equipped exhaust hardware. Other players are not guaranteed to "
		.. "see local effects.")
	local esp = Shell.page("ESP")
	W.section(esp, "Player names")
	for _, row in ipairs({ { "esp", "Player ESP" }, { "espNames", "Show names" }, { "espDistance",
		"Show distance" } }) do
		local key = row[1]
		W.toggle(esp, { label = row[2], key = key, get = function() return cfg[key] end,
			set = function(v) cfg[key] = v; changed() end })
	end
	W.statusRow(esp, function() return S.espStatus end)
	W.note(esp,
		"Ghost Driver-style names through walls, with distance in studs. Tracks rendered bikes, "
		.. "or characters off-bike. Saved ON resumes automatically; unstreamed players have no tag.")
	local settings = Shell.page("Settings")
	W.section(settings, "Camera perspective")
	W.note(settings,
		"Stock bind: B cycles first person, third-person locked and third-person free while "
		.. "riding. These buttons use the native camera API; no camera hook.")
	local views = { "First person", "Third person - locked", "Third person - free",
		"Third person - tight" }
	W.statusRow(settings, function()
		local cam = S.modules and S.modules.state and S.modules.state.CamTouch
		return "View: " .. tostring(cam and views[cam.mode()] or "waiting for camera")
	end)
	for mode, label in ipairs(views) do
		W.button(settings, label,
			"Selects the game's camera view and saves through its normal settings path.", function()
			local cam = S.modules and S.modules.state and S.modules.state.CamTouch
			if cam and type(cam.set) == "function" then
				cam.set(mode)
				S.modules.settings.Set("CamView", mode)
				Log.info("native camera=" .. label)
			end
		end)
	end
	W.section(settings, "Camera effects")
	for _, row in ipairs({ { "camera", "Camera override" }, { "sway", "Camera sway" }, { "shake",
		"Camera shake" } }) do
		local key = row[1]
		W.toggle(settings, { label = row[2], key = key, get = function() return cfg[key] end,
			set = function(v) cfg[key] = v; changed() end })
	end
	W.slider(settings, { label = "Field of view", key = "fov", min = 55, max = 110, step = 1,
		get = function() return cfg.fov end, set = function(v) cfg.fov = v; changed() end })
	W.section(settings, "Lifecycle")
	W.statusRow(settings, function() return S.status end)
	W.button(settings, "Panic restore", "Disarms every saved bike profile. Delete does the same.",
		panic)
	W.note(settings,
		"K unloads and restores stock without forgetting your choices. Reinject hub.lua to load a "
		.. "new build.")
	Shell.ready()
	S.conns[#S.conns + 1] = UIS.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode == Enum.KeyCode.Delete then panic()
		elseif input.KeyCode == Enum.KeyCode.K then task.spawn(destroy) end
	end)
	Log.info(string.format("boot %s embedded=true guard=%s camera=%s esp=%s diagnostics=%s "
		.. "warning=%s", BUILD_VERSION,
		tostring(cfg.railGuard), tostring(cfg.camera), tostring(cfg.esp), tostring(cfg.diagnostics),
			tostring(cfg.trafficWarning)))
	-- No game function is called on the UI loading thread. The plain-table
	-- adapter observes the exact context the stock driver passes each tick.
	task.spawn(function()
		local ok, err = xpcall(function()
			local ps = LP:WaitForChild("PlayerScripts", 10)
			local controllers = ps and ps:WaitForChild("Controllers", 10)
			local bikeController = controllers and controllers:WaitForChild("BikeController", 10)
			local module = bikeController and bikeController:WaitForChild("Drivetrain", 10)
			assert(module, "live BikeController.Drivetrain unavailable")
			local drive = require(module)
			local modules = game:GetService("ReplicatedStorage"):FindFirstChild("Modules")
			local settingsModule = modules and modules:FindFirstChild("ClientSettings")
			local settingsTable = settingsModule and require(settingsModule)
			local contactModule = modules and modules:FindFirstChild("TrafficContact")
			local contact = contactModule and require(contactModule)
			local tricksModule = bikeController:FindFirstChild("StuntTricks")
			local tricks = tricksModule and require(tricksModule)
			local presentationModule = modules and modules:FindFirstChild("RemoteBikePresentation")
			local presentation = presentationModule and require(presentationModule)
			if presentation then
				assert(type(presentation) == "table" and type(presentation.Frame) == "function"
					and type(presentation.records) == "table", "unsupported RemoteBikePresentation")
			end
			if not S.alive then return end
			assert(type(tricks) == "table" and type(tricks.Bar) == "function", "unsupported StuntTricks.Bar")
			assert(type(contact) == "table" and type(contact.Test) == "function"
				and type(contact.Sweep) == "function", "unsupported TrafficContact")
			assert(type(drive) == "table" and type(drive.step) == "function", "unsupported drivetrain")
			local original = drive.step
			local wrapper = function(ctx, ...)
				local dt = select(1, ...)
				if Core.finite(dt) then S.frameDt = dt; S.maxFrameDt = math.max(S.maxFrameDt, dt) end
				if S.alive and not S.fault then
					local success, fault = pcall(tune, ctx)
					if not success then S.fault = tostring(fault) end
				end
				-- Logging and cleanup run in the worker: even their failure must
				-- never stop the original drivetrain from running.
				local t = S.traffic
				local active = S.alive and not S.fault and S.session and S.session.ctx == ctx
					and S.session.bike == ctx.currentBike and profile().trafficBrake
					and t.bike == ctx.currentBike and t.brake and os.clock() - t.at <= 0.2
				S.lastBrakeApplied = not not (active and Core.brakeAllowed(ctx))
				S.lastBrakeTickAt = os.clock()
				return Core.brakeCall(original, active, ctx, ...)
			end
			S.modules = { drive = drive, original = original, wrapper = wrapper, settings = settingsTable,
				contact = contact, tricks = tricks, presentation = presentation }
			S.modules.state = require(modules.RideState)
			S.modules.gameConfig = require(modules.GameConfig)
			local shift = modules:FindFirstChild("WorldShift")
			S.modules.shift = shift and require(shift)
			S.modules.rawSweep = contact.Sweep
			S.recorder = Assist
			Assist.start()
			drive.step = wrapper
			Core.write(tricks, S.trickRecords, "Bar", Core.barAdapter(tricks.Bar, limitWheelie))
			for _, key in ipairs({ "Test", "Sweep" }) do
				Core.write(contact, S.contactRecords, key, Core.contactAdapter(contact[key], function()
					local success, active = pcall(guardActive)
					if not success then S.fault = tostring(active) end
					return success and active
				end))
			end
			S.status = "Adapter ready; enter your bike"
			local appliedRevision = -1
			while S.alive do
				if S.fault then error(S.fault) end
				if S.modules.drive.step ~= wrapper then S.status = "Drivetrain adapter replaced; reload module"
					end
				local sess = S.session
				if sess and (not owned(sess.ctx) or sess.ctx.currentBike ~= sess.bike or sess.ctx.BikeCfg ~=
					sess.config) then
					clearSession(); S.profileKey = nil; S.status = "Waiting for your bike"
				end
				for _, retired in ipairs(S.retired) do restoreAttributes(retired) end
				table.clear(S.retired)
				if S.session then tune(S.session.ctx) end
				applyAttributes()
				applyRail()
				if appliedRevision ~= S.revision then
					applyCamera(); appliedRevision = S.revision
				end
				if cfg.railGuard and S.session and os.clock() >= S.guardAt then
					local ctx = S.session.ctx
					local state = ctx.RideState or {}
					local report = string.format("guard skipped=%d crash=%s loop=%s serverCrashed=%s doomed=%s",
						S.contactSkips, tostring(state.Crash), tostring(ctx.loopOut),
						tostring(S.session.bike:GetAttribute("NFNC_Crashed")),
							tostring(S.session.bike:GetAttribute("NFNC_Doomed")))
					if report ~= S.guardLast then Log.info(report); S.guardLast = report end
					S.guardAt = os.clock() + 2
				end
				local trafficOK, trafficErr = pcall(Assist.step)
				if not trafficOK then
					S.traffic = {}; S.trafficStatus = "Traffic data unavailable; braking released"
					if Assist.lastError ~= tostring(trafficErr) then Log.err("traffic", trafficErr);
						Assist.lastError = tostring(trafficErr) end
				end
				-- A streamed/destroyed GUI must not take the drivetrain adapter down.
				local espOK, espErr = pcall(ESP.step)
				if not espOK then
					pcall(ESP.clear)
					S.espStatus = "ESP error; retrying"
					if S.espError ~= tostring(espErr) then Log.err("esp", espErr); S.espError = tostring(espErr)
						end
				else S.espError = nil end
				if S.espLast ~= S.espStatus then Log.info(S.espStatus); S.espLast = S.espStatus end
				if S.dirtyAt and os.clock() - S.dirtyAt >= 0.4 then saveNow() end
				task.wait(0.1)
			end
		end, debug.traceback)
		if not ok then
			S.status = "Adapter error: " .. tostring(err)
			Log.err("adapter", err)
			-- A partial initialization cannot leave a tuning wrapper armed.
			pcall(destroy)
		end
	end)
end
local ok, err = xpcall(main, debug.traceback)
if not ok then Log.err("main", err); pcall(destroy) end
