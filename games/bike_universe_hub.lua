-- Bike Universe Hub v2026-10-28.2 (2026-10-28)
-- Rungs 3/5: local live tune attributes and owned-rider controller state.
-- Server sees stock RiderInput and resulting motion. No new remotes, namecall
-- hooks, direct CFrame/velocity writes, print/warn, or anticheat bypass.
-- Proof: 2026-10-26T12-26-37Z capture: 0106:2003-2054,2820-2889;
-- 0065:1247-1276,1361-1483; 0094:893-984; 0067:109-130; 0023:289-299.
-- Local crash guards are not server immunity. No server arrest/fine bypass.
-- Hands-free state, real tail contact and owned Trick writes reuse stock input.
-- Banking waits for stock idle payout and observed Cash; never forges a score.
-- DETECTED: speed-hacking kick recorded 2026-10-28; movement boots OFF.
-- Wheelie assist resumes normally; no wheelie-specific enforcement proven.
-- Re-inject safe: self-teardown on load; K = unload, Delete = saved panic OFF.
local BUILD_VERSION = "2026-10-28.2"
local EXPECTED_GAME = 10768284407
local EXPECTED_PLACE = 98628861455414
local GKEY = "__BIKE_UNIVERSE_HUB"
local CONFIG_FILE = "bike_universe_hub_config.json"
if game.GameId ~= EXPECTED_GAME and game.PlaceId ~= EXPECTED_PLACE then return end
local G = getgenv()
if G[GKEY] and G[GKEY].destroy then pcall(G[GKEY].destroy) end
local Log = loadfile("log.lua")()("bike_universe_hub", { print = false })
Log.session(BUILD_VERSION)
local HOST = G.__R3ST_HOST
if type(HOST) ~= "table" or not HOST.ui or not HOST.host or not HOST.host.Parent then
	Log.err("Hub host missing; open Bike Universe through hub.lua")
	return
end

-- CORE BEGIN: tested from the actual source, without Roblox.
local Core = {}
Core.safeGround = {[1]=true, [2]=true, [3]=true, [6]=true, [8]=true}
Core.defaults = {
	movement = false, speed = 1.25, power = 1.5, reverse = 1, coast = 1,
	handling = false, grip = 1.2, brakes = 1.2, turn = 1, lean = 1, steer = 1,
	suspension = false, frequency = 1, damping = 1, rebound = 1, travel = 1, pitch = 1,
	stunts = false, strength = 1, hold = false, angle = 65, pop = 1, gravity = 1,
	airRate = 1, whip = 1, crashGuard = false, trafficGuard = false,
	auto = false, scrape = false, scrapeOffset = 0, margin = 8,
	modifiers = false, bank = false, bankSeconds = 60, releaseRate = 60,
	combo = false, segmentSeconds = 10,
}
Core.limits = {
	speed = {0.5, 4}, power = {0.5, 8}, reverse = {0.5, 3}, coast = {0, 2},
	grip = {0.5, 3}, brakes = {0.5, 3}, turn = {0.4, 2}, lean = {0.5, 1.5},
	steer = {0.5, 1.5}, frequency = {0.5, 2}, damping = {0.5, 2},
	rebound = {0.5, 2}, travel = {0.5, 2}, pitch = {0.5, 2}, strength = {0.25, 3},
	angle = {20, 105}, pop = {0.5, 3}, gravity = {0.5, 1.5}, airRate = {0.5, 3}, whip = {0.5, 2},
	scrapeOffset = {-3, 3}, margin = {5, 20}, bankSeconds = {15, 300}, releaseRate = {20, 90},
	segmentSeconds = {8, 30},
}
Core.globalDefaults = { camera = false, fov = 80, audio = false, volume = 1,
	esp = false, names = true, distance = true }
Core.globalLimits = { fov = {50, 115}, volume = {0, 1} }
-- {category, attribute, fallback, profile multiplier}. Stock step owns all forces.
Core.specs = {
	{"movement", "MaxSpeedKmh", 80, "speed"},
	{"movement", "LaunchAccel", 4, "power"},
	{"movement", "PowerPerKg", 20, "power"},
	{"movement", "ReverseSpeedKmh", 5, "reverse"},
	{"movement", "EngineBrake", 0.35, "coast"},
	{"handling", "TireGrip", 0.9, "grip"},
	{"handling", "BrakeDecel", 7.5, "brakes"},
	{"handling", "TurnInTime", 0.5, "turn"},
	{"handling", "MaxLeanDeg", 28, "lean"},
	{"handling", "MaxSteerDeg", 30, "steer"},
	{"suspension", "RideFrequency", 2, "frequency"},
	{"suspension", "RideDamping", 0.35, "damping"},
	{"suspension", "RideReboundDamping", 0.9, "rebound"},
	{"suspension", "SuspensionTravel", 0.55, "travel"},
	{"suspension", "PitchDamping", 0.5, "pitch"},
	{"stunts", "WheelieStrength", 1, "strength"},
	{"stunts", "PopHeight", 2.2, "pop"},
	{"stunts", "AirGravity", 196.2, "gravity"},
	{"stunts", "AirTrickRate", 1, "airRate"},
	{"stunts", "TailwhipTime", 0.95, "whip"},
}
function Core.finite(n)
	return type(n) == "number" and n == n and math.abs(n) < math.huge
end
function Core.clean(saved, defaults, limits)
	local out = table.clone(defaults)
	if type(saved) ~= "table" or getmetatable(saved) then return out end
	for key, value in next, out do
		local v = rawget(saved, key)
		if type(v) == type(value) then
			if type(v) == "number" then
				if Core.finite(v) then out[key] = math.clamp(v, limits[key][1], limits[key][2]) end
			else out[key] = v end
		end
	end
	return out
end
function Core.profile(saved) return Core.clean(saved, Core.defaults, Core.limits) end
function Core.config(saved)
	local cfg = Core.clean(saved, Core.globalDefaults, Core.globalLimits)
	cfg.default = Core.profile(type(saved) == "table" and rawget(saved, "default"))
	cfg.profiles = {}
	local profiles = type(saved) == "table" and rawget(saved, "profiles")
	if type(profiles) == "table" and not getmetatable(profiles) then
		local count = 0
		for key, value in next, profiles do
			if type(key) == "string" and #key <= 100 and count < 256 then
				cfg.profiles[key] = Core.profile(value)
				count += 1
			end
		end
	end
	-- Recorded speed enforcement: activation requires this session's choice.
	cfg.default.movement = false
	for _, profile in next, cfg.profiles do profile.movement = false end
	return cfg
end
function Core.patch(base, p)
	local patch = {}
	for _, spec in ipairs(Core.specs) do
		local category, attr, fallback, key = table.unpack(spec)
		if p[category] then
			local value = base[attr]
			if not Core.finite(value) then value = fallback end
			local multiplier = p[key]
			if attr == "PowerPerKg" then multiplier *= p.speed end
			if attr == "TurnInTime" or attr == "TailwhipTime" then multiplier = 1 / multiplier end
			patch[attr] = value * multiplier
		end
	end
	return patch
end
function Core.put(target, records, key, value, get, set)
	local record = records[key]
	local current = get(target, key)
	if not record then record = {old = current}; records[key] = record
	elseif current ~= record.last then record.old = current end
	set(target, key, value)
	record.last = value
end
function Core.restore(target, records, get, set)
	for key, record in next, records do
		if get(target, key) == record.last then set(target, key, record.old) end
	end
	table.clear(records)
end
function Core.holdTarget(ctx, p, scrapeAngle, clearance, adjustment, dt)
	local loop = ctx.model:GetAttribute("LoopOutDeg")
	if not Core.finite(loop) then loop = 110 end
	local limit = math.rad(loop - p.margin)
	if not p.scrape then return math.min(math.rad(p.angle), limit), "balance", 0 end
	if not Core.finite(scrapeAngle) then return nil, "scrape geometry unavailable", 0 end
	local base = scrapeAngle + math.rad(p.scrapeOffset)
	if base <= math.rad(10) or base >= limit then return nil, "scrape outside loop margin", 0 end
	adjustment = adjustment or 0
	if Core.finite(clearance) and Core.finite(dt) and dt > 0 then
		adjustment = math.clamp(adjustment + (clearance - 0.08) * math.rad(25) * dt, -math.rad(3), math.rad(3))
	end
	return math.clamp(base + adjustment, math.rad(10.5), limit), "scrape", adjustment
end
function Core.farm(state, p, ctx, dt, blocked, cash, pending)
	if not p.auto or blocked then
		state.phase = p.auto and "paused" or "off"
		state.elapsed, state.wait, state.started, state.forceBank = 0, 0, false, false
		return
	end
	if not Core.finite(dt) or dt <= 0 then return end
	if state.phase == nil or state.phase == "off" or state.phase == "paused" then state.phase = "holding" end
	if state.phase == "holding" then
		if (ctx.wheelieAngle or 0) > math.rad(10) then
			state.elapsed = (state.elapsed or 0) + dt
			state.segmentElapsed = (state.segmentElapsed or 0) + dt
		end
		if state.forceBank or p.bank and (state.elapsed or 0) >= p.bankSeconds then
			state.phase, state.forceBank, state.releaseFor = "lowering", false, "bank"
		elseif p.combo and (state.segments or 0) < 3 and (state.segmentElapsed or 0) >= p.segmentSeconds then
			state.phase, state.releaseFor = "lowering", "segment"
		end
	elseif state.phase == "lowering" then
		if (ctx.wheelieAngle or 0) <= math.rad(0.5) then
			state.phase = state.releaseFor == "segment" and "linking" or "banking"
			state.wait, state.cashBefore = 0, cash
		end
	elseif state.phase == "linking" then
		-- Finish the ground entry's 0.2s grace without exhausting the 4.5s chain ring.
		state.wait = (state.wait or 0) + dt
		if state.wait >= 0.35 then
			state.segments, state.segmentElapsed, state.started = (state.segments or 0) + 1, 0, false
			state.phase = "holding"
		end
	elseif state.phase == "banking" then
		state.wait = (state.wait or 0) + dt
		-- Native entry grace + up to 4.5s ring expiry. Never restart on timeout alone.
		if state.wait >= 5 and Core.finite(cash) and Core.finite(state.cashBefore)
			and cash > state.cashBefore and pending == 0 then
			state.bankCash = (state.bankCash or 0) + cash - state.cashBefore
			state.cycles, state.elapsed, state.started = (state.cycles or 0) + 1, 0, false
			state.segments, state.segmentElapsed = 0, 0
			state.phase = "holding"
		end
	end
end
function Core.assist(ctx, p, dt, throttle, desired)
	if not p.hold and not p.auto then return nil, "off" end
	if not ctx.wheelieHeld then return nil, "released" end
	if ctx.rearBrakeHeld or throttle < -0.05 then return nil, "manual brake" end
	if ctx.stoppieHeld then return nil, "stoppie" end
	if ctx.crash or ctx.loopedOut then return nil, "crashed" end
	if ctx.grind or ctx.vert or ctx.vertAir then return nil, "special surface" end
	if (ctx.airTime or 0) > 0 then return nil, "airborne" end
	if not Core.finite(dt) or dt <= 0 then return nil, "invalid step" end
	local loop = ctx.model:GetAttribute("LoopOutDeg")
	if not Core.finite(loop) then loop = 110 end
	local ceiling = desired or math.rad(math.max(0, math.min(p.angle, loop - p.margin)))
	local floor = p.auto and math.min(math.rad(math.max(0, loop - p.margin)),
		math.max(0, (ctx.wheelieAngle or 0) - math.rad(p.releaseRate) * dt)) or 0
	ceiling = math.max(ceiling, floor)
	-- Stock raises target at 80 degrees/s. Preserve its ramp until the limit.
	-- Use the real dt: stock does not skip slow frames either (0106:1959,2839).
	local target = Core.finite(ctx.wheelieTarget) and ctx.wheelieTarget or 0
	ctx.wheelieTarget = math.clamp(target, 0, math.max(0, ceiling - math.rad(80) * dt))
	if Core.finite(ctx.wheelieAngle) then
		ctx.wheelieAngle = math.min(ctx.wheelieAngle, ceiling)
		if Core.finite(ctx.wheelieRate) then
			ctx.wheelieRate = math.clamp(ctx.wheelieRate, -math.rad(p.releaseRate), math.max(0, (ceiling - ctx.wheelieAngle) / dt))
		end
	end
	return ceiling, "holding", floor
end
function Core.after(ctx, guard, previousCrash, previousLoop, ceiling, floor, releaseRate)
	if guard then
		if not previousCrash then ctx.crash = nil end
		if not previousLoop then ctx.loopedOut = previousLoop end
	end
	if ceiling and not previousCrash and not previousLoop and not ctx.crash
		and (ctx.airTime or 0) == 0 and not (ctx.grind or ctx.vert or ctx.vertAir) then
		if Core.finite(ctx.wheelieAngle) and ctx.wheelieAngle > ceiling then
			ctx.wheelieAngle = ceiling
			ctx.wheelieRate = math.min(ctx.wheelieRate or 0, 0)
		end
		if floor and ctx.wheelieAngle < floor then
			ctx.wheelieAngle = floor
			ctx.wheelieRate = math.max(ctx.wheelieRate or 0, -math.rad(releaseRate))
		end
		ctx.loopedOut = previousLoop
	end
end
-- CORE END

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local UIS = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local SoundService = game:GetService("SoundService")
local LP = Players.LocalPlayer
local cfg = Core.config()
local okRead, raw = pcall(readfile, CONFIG_FILE)
if okRead then
	local ok, saved = pcall(HttpService.JSONDecode, HttpService, raw)
	if ok then cfg = Core.config(saved) end
end
local S = {alive = true, revision = 0, live = {}, conns = {}, patches = {}, tags = {},
	writing = false, error = nil, saveTask = nil, session = nil,
	started = os.clock(), cashStart = LP:GetAttribute("Cash") or 0, guardSaves = 0, banks = 0}
local Shell, Physics, Traffic, Loadout, Touch, refreshGrace
local function safe(label, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok and S.error ~= tostring(err) then
		S.error = tostring(err)
		Log.err(label .. ": " .. S.error)
	end
	return ok
end
local function saveNow()
	local ok, payload = pcall(HttpService.JSONEncode, HttpService, cfg)
	if ok then
		local written, err = pcall(writefile, CONFIG_FILE, payload)
		if not written then Log.err("config write: " .. tostring(err)) end
	else Log.err("config encode: " .. tostring(payload)) end
end
local function cancelSave()
	if S.saveTask then pcall(task.cancel, S.saveTask); S.saveTask = nil end
end
local function saveConfig()
	if not S.alive then return end
	cancelSave()
	S.saveTask = task.delay(0.4, function()
		S.saveTask = nil
		if S.alive then saveNow() end
	end)
end
local function attrGet(target, key) return target:GetAttribute(key) end
local function attrSet(target, key, value) target:SetAttribute(key, value) end
local function fieldGet(target, key) return target[key] end
local function fieldSet(target, key, value) target[key] = value end
local function manualWheelie()
	return UIS:IsKeyDown(Enum.KeyCode.LeftControl) or UIS:IsKeyDown(Enum.KeyCode.RightControl)
		or UIS:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonL1)
		or Touch and Touch.isHeld("Wheelie") or false
end
local function restoreActions(session)
	local held = session.inputs.wheelieHeld
	if held then held.old = manualWheelie() end
	Core.restore(session.ctx, session.inputs, fieldGet, fieldSet)
	Core.restore(session.ctx.model, session.tricks, attrGet, attrSet)
	session.farm.started = false
end
local function resetFarm(session)
	restoreActions(session)
	session.farm, session.contactAdjust = {}, 0
	session.modTime, session.modManual, session.modNote, session.lastCycles = 0, false, nil, 0
end
local function own(ctx)
	if type(ctx) ~= "table" or not ctx.model or not ctx.model.Parent
		or not ctx.chassis or not ctx.chassis.Parent or not ctx.seat or not ctx.seat.Parent then return false end
	local char = LP.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0 and ctx.seat.Occupant == hum
		and hum.SeatPart == ctx.seat and ctx.seat:GetAttribute("IsScooterSeat") == true
		and ctx.model:GetAttribute("Owner") == LP.UserId
end
local function active()
	local ctx = Physics and Physics.active
	return own(ctx) and ctx or nil
end
local function restoreAudio(session)
	for sound, record in next, session.sounds do
		pcall(function()
			if sound.Parent and sound.SoundGroup == session.group then sound.SoundGroup = record.old end
		end)
	end
	table.clear(session.sounds)
	if session.group then session.group:Destroy(); session.group = nil end
end
local function release()
	local session = S.session
	if not session then return end
	S.session = nil
	if session.conn then session.conn:Disconnect() end
	S.writing = true
	safe("restore attributes", Core.restore, session.ctx.model, session.attrs, attrGet, attrSet)
	S.writing = false
	safe("restore grace", Core.restore, session.ctx, session.fields, fieldGet, fieldSet)
	safe("restore actions", restoreActions, session)
	restoreAudio(session)
end
local function bind(ctx)
	if S.session and S.session.ctx == ctx then return S.session end
	release()
	if not own(ctx) then return end
	local kind = ctx.model:GetAttribute("Kind")
	if type(kind) ~= "string" or kind == "" then return end
	if not cfg.profiles[kind] then cfg.profiles[kind] = Core.profile(cfg.default); saveConfig() end
	local session = {ctx = ctx, key = kind, attrs = {}, fields = {}, base = {}, sounds = {}, rev = -1,
		inputs = {}, tricks = {}, farm = {}, contactAdjust = 0}
	for _, spec in ipairs(Core.specs) do session.base[spec[2]] = ctx.model:GetAttribute(spec[2]) end
	-- AirGravity defaults to workspace gravity, not a universal constant.
	if session.base.AirGravity == nil then session.base.AirGravity = workspace.Gravity end
	session.conn = ctx.model.AttributeChanged:Connect(function(key)
		if S.writing or not S.alive or S.session ~= session then return end
		for _, spec in ipairs(Core.specs) do
			if spec[2] == key then
				local value = ctx.model:GetAttribute(key)
				local record = session.attrs[key]
				-- Deferred Roblox signals can arrive after S.writing was cleared.
				if record and value == record.last then return end
				session.base[key] = value
				if record then record.old = value end
				session.rev = -1
				break
			end
		end
	end)
	S.session = session
	local p = cfg.profiles[kind]
	Log.info(("bind %s movement=%s speed=%.2f power=%.2f hold=%s crash=%s traffic=%s auto=%s scrape=%s modifiers=%s bank=%s")
		:format(kind, tostring(p.movement), p.speed, p.power, tostring(p.hold),
			tostring(p.crashGuard), tostring(p.trafficGuard), tostring(p.auto), tostring(p.scrape),
			tostring(p.modifiers), tostring(p.bank)))
	return session
end
local function currentProfile()
	local session = bind(active())
	return session and cfg.profiles[session.key] or cfg.default
end
local function changed()
	S.revision += 1
	saveConfig()
end
local function setProfile(key, value)
	if not S.alive or Core.defaults[key] == nil then return end
	local profile = Core.profile(currentProfile())
	profile[key] = value
	profile = Core.profile(profile)
	if S.session then cfg.profiles[S.session.key] = profile else cfg.default = profile end
	if S.session and key == "crashGuard" then refreshGrace(S.session, profile) end
	if S.session and (key == "auto" or key == "modifiers" or key == "scrape" or key == "bank" or key == "combo") then
		resetFarm(S.session)
	end
	changed()
end
local function setGlobal(key, value)
	if not S.alive or Core.globalDefaults[key] == nil then return end
	local patch = {[key] = value}
	cfg[key] = Core.clean(patch, Core.globalDefaults, Core.globalLimits)[key]
	changed()
end
local function applyTune(session)
	if session.rev == S.revision then return end
	local patch = Core.patch(session.base, cfg.profiles[session.key])
	S.writing = true
	-- Restore only fields no longer requested; keep the bind baseline otherwise.
	for key, record in next, session.attrs do
		if patch[key] == nil then
			if attrGet(session.ctx.model, key) == record.last then attrSet(session.ctx.model, key, record.old) end
			session.attrs[key] = nil
		end
	end
	for key, value in next, patch do
		if attrGet(session.ctx.model, key) ~= value then
			Core.put(session.ctx.model, session.attrs, key, value, attrGet, attrSet)
		end
	end
	S.writing = false
	session.rev = S.revision
	Log.info(("apply %s revision=%d speed=%.1f power=%.1f"):format(session.key, S.revision,
		patch.MaxSpeedKmh or session.base.MaxSpeedKmh or 80,
		patch.PowerPerKg or session.base.PowerPerKg or 20))
end
local function patchField(target, key, wrapper)
	S.patches[#S.patches + 1] = {target = target, key = key, old = target[key], last = wrapper}
	target[key] = wrapper
end
refreshGrace = function(session, p)
	if p.crashGuard then
		Core.put(session.ctx, session.fields, "noImpactUntil", os.clock() + 0.5, fieldGet, fieldSet)
	elseif next(session.fields) then Core.restore(session.ctx, session.fields, fieldGet, fieldSet) end
end
local function protectTrick(session, p)
	local ctx = session.ctx
	if not p.crashGuard or (ctx.airTime or 0) > 0 then return end
	local trick = ctx.model:GetAttribute("Trick")
	local corner = trick == 4 and math.abs(ctx.speed or 0) > 3
		and math.abs((ctx.speed or 0) * (ctx.groundYawRate or 0)) / 9.81 > 0.35
	if trick == 5 or corner then
		Core.put(ctx.model, session.tricks, "Trick", 0, attrGet, attrSet)
		-- Native grounded Superman is consumed, not a persistent preference.
		session.tricks.Trick.old = 0
		S.guardSaves += 1
		Log.info("guard cancelled risky ground trick " .. tostring(trick))
	end
end
local function rotateModifiers(session, p, dt, enabled)
	local ctx, farm = session.ctx, session.farm
	local record = session.tricks.Trick
	local current = ctx.model:GetAttribute("Trick") or 0
	if record and current ~= record.last then
		session.tricks.Trick = nil
		session.modManual = current ~= 0
	end
	if not enabled or not p.modifiers or not Loadout or not Loadout.inSlot then
		Core.restore(ctx.model, session.tricks, attrGet, attrSet)
		return
	end
	if current ~= 0 and not session.tricks.Trick then session.modManual = true end
	if session.modManual then
		if current ~= 0 then return end
		session.modManual = false
	end
	local passenger = ctx.model:FindFirstChild("PassengerSeat")
	local occupied = passenger and passenger.Occupant ~= nil
	local choices, names = {}, {}
	for slot = 1, 4 do
		local item = Loadout.inSlot("ground", slot)
		if item and Core.safeGround[item.id]
			and (not occupied or item.id == 3) and not names[item.name] then
			names[item.name] = true
			choices[#choices + 1] = item.id
		end
	end
	if #choices == 0 then
		Core.restore(ctx.model, session.tricks, attrGet, attrSet)
		session.modNote = "no compatible equipped tricks"
		return
	end
	local start = ((farm.cycles or 0) + (farm.segments or 0)) % #choices
	local second = math.min(math.floor((session.modTime or 0) / 0.45), 1)
	local id = choices[(start + second) % #choices + 1]
	Core.put(ctx.model, session.tricks, "Trick", id, attrGet, attrSet)
	session.modTime = (session.modTime or 0) + dt
	session.modNote = #choices > 1 and "two equipped modifiers" or "one compatible modifier"
end
local function prepareRiding(session, p, dt, throttle)
	local ctx, farm = session.ctx, session.farm
	session.target = nil
	local blocked = UIS:GetFocusedTextBox() ~= nil or LP:GetAttribute("PhoneOut") == true
		or ctx.rearBrakeHeld or throttle < -0.05 or ctx.stoppieHeld or ctx.crash or ctx.loopedOut
		or ctx.grind or ctx.vert or ctx.vertAir or (ctx.airTime or 0) > 0
	local target, targetReason
	if (p.auto or p.hold) and not blocked then
		local angle, clearance
		if p.scrape and Physics.tail then
			local point
			angle, point = Physics.tail(ctx.model)
			if not point then angle = nil end
			if Physics.tailGround then clearance = Physics.tailGround(ctx.model) end
		end
		target, targetReason, session.contactAdjust = Core.holdTarget(ctx, p, angle, clearance, session.contactAdjust, dt)
		if not target then blocked = true end
	end
	Core.farm(farm, p, ctx, dt, blocked, LP:GetAttribute("Cash"), LP:GetAttribute("CashHold") or 0)
	if not p.auto or blocked or farm.phase == "banking" or farm.phase == "linking" then
		restoreActions(session)
		session.modTime = 0
	else
		if not farm.started then
			if type(ctx.setWheelie) == "function" then ctx:setWheelie(true) end
			farm.started = true
		end
		Core.put(ctx, session.inputs, "wheelieHeld", true, fieldGet, fieldSet)
		if farm.phase == "lowering" then
			target = math.max(0, (ctx.wheelieAngle or 0) - math.rad(p.releaseRate) * dt)
		end
	end
	rotateModifiers(session, p, dt, p.auto and not blocked and farm.phase == "holding"
		and (ctx.wheelieAngle or 0) > math.rad(10))
	if farm.phase == "lowering" then session.modTime = 0 end
	if blocked then return nil, targetReason or "manual / surface pause" end
	if p.auto and farm.phase == "banking" then return nil, "waiting for native bank + Cash" end
	if p.auto and farm.phase == "linking" then return nil, "linking native combo" end
	session.target = target and math.deg(target)
	local ceiling, reason, floor = Core.assist(ctx, p, dt, throttle, target)
	return ceiling, ceiling and (p.auto and farm.phase or "holding") or reason, floor
end
local function install()
	local pm = RS:FindFirstChild("ScooterPhysics")
	local tm = RS:FindFirstChild("HighwayTraffic")
	assert(pm and tm, "Bike Universe modules not replicated")
	Physics, Traffic = require(pm), require(tm)
	local lm, tc = RS:FindFirstChild("TrickLoadout"), RS:FindFirstChild("TouchControls")
	Loadout, Touch = lm and require(lm), tc and require(tc)
	assert(type(Physics.step) == "function" and type(Traffic.collide) == "function", "Drive API changed")
	if type(Physics.new) == "function" then
		local make = Physics.new
		patchField(Physics, "new", function(...)
			local result = table.pack(make(...))
			if S.alive and own(result[1]) then
				safe("constructor grace", function()
					local session = bind(result[1])
					if session then refreshGrace(session, cfg.profiles[session.key]) end
				end)
			end
			return table.unpack(result, 1, result.n)
		end)
	end
	local original = Physics.step
	patchField(Physics, "step", function(ctx, dt, throttle, steer, coasting, ...)
		if not S.alive or coasting or ctx ~= active() or not Core.finite(dt) or dt <= 0 then
			return original(ctx, dt, throttle, steer, coasting, ...)
		end
		local session, ceiling, floor, p
		local previousCrash, previousLoop = ctx.crash, ctx.loopedOut
		local prepared = safe("pre-step", function()
			session = bind(ctx)
			if not session then return end
			applyTune(session)
			p = cfg.profiles[session.key]
			refreshGrace(session, p)
			protectTrick(session, p)
			ceiling, session.assist, floor = prepareRiding(session, p, dt, throttle)
		end)
		if not prepared then
			S.writing = false
			release()
		end
		local result = table.pack(original(ctx, dt, throttle, steer, coasting, ...))
		if prepared and p and session == S.session and own(ctx) then
			safe("post-step", function()
				if (ctx.airTime or 0) == 0 and (ctx.wheelieAngle or 0) > math.rad(10) then
					session.wheelieSeconds = (session.wheelieSeconds or 0) + dt
				else session.wheelieSeconds = 0 end
				-- Observe the stock result BEFORE either local guard clears its flags.
				local failure = tostring(ctx.crash) .. "|" .. tostring(ctx.loopedOut)
				if (ctx.crash or ctx.loopedOut) and failure ~= session.lastFailure then
					if p.crashGuard and not previousCrash and not previousLoop then S.guardSaves += 1 end
					Log.info(("stock outcome %s crash=%s loop=%s kmh=%.1f angle=%.1f rate=%.1f held=%s brake=%s wheelie=%.2fs dt=%.3f"):format(
						session.key, tostring(ctx.crash), tostring(ctx.loopedOut), math.abs(ctx.speed or 0) * 3.6,
						math.deg(ctx.wheelieAngle or 0), math.deg(ctx.wheelieRate or 0), tostring(ctx.wheelieHeld),
						tostring(ctx.rearBrakeHeld), session.wheelieSeconds, dt))
				end
				session.lastFailure = failure
				Core.after(ctx, p.crashGuard, previousCrash, previousLoop, ceiling, floor, p.releaseRate)
				protectTrick(session, p)
				if session.lastPhase ~= session.farm.phase or session.lastAssist ~= session.assist then
					session.lastPhase, session.lastAssist = session.farm.phase, session.assist
					Log.info(("farm %s phase=%s assist=%s target=%s"):format(session.key,
						tostring(session.farm.phase), tostring(session.assist), tostring(session.target)))
				end
				local cycles = session.farm.cycles or 0
				if cycles > (session.lastCycles or 0) then
					S.banks += cycles - (session.lastCycles or 0)
					session.lastCycles = cycles
					Log.info("bank wait complete; observed total Cash delta=" .. tostring(session.farm.bankCash))
				end
			end)
		end
		return table.unpack(result, 1, result.n)
	end)
	local collide = Traffic.collide
	patchField(Traffic, "collide", function(cf, size, ...)
		local session = S.session
		if S.alive and session and session.ctx == active() and cfg.profiles[session.key].trafficGuard then
			local matching = false
			safe("traffic scope", function()
				local ctx = session.ctx
				local geo = Physics.geometry(ctx.model)
				local a, b, radii = geo.axles[1], geo.axles[2], geo.radii
				local low = math.min(a.Y - radii[1], b.Y - radii[2])
				local z0, z1 = math.min(a.Z - radii[1], b.Z - radii[2]), math.max(a.Z + radii[1], b.Z + radii[2])
				local expected = ctx.chassis.CFrame * CFrame.new((a.X + b.X) / 2, low + 2.75, (z0 + z1) / 2)
				local dimensions = Vector3.new(1.6, 5.5, z1 - z0)
				matching = typeof(cf) == "CFrame" and typeof(size) == "Vector3"
					and (cf.Position - expected.Position).Magnitude < 0.001
					and (size - dimensions).Magnitude < 0.001
					and cf.LookVector:Dot(expected.LookVector) > 0.99999
					and cf.UpVector:Dot(expected.UpVector) > 0.99999
			end)
			if matching then return nil end
		end
		return collide(cf, size, ...)
	end)
end
local function applyAudio(session)
	if not cfg.audio then restoreAudio(session); return end
	if not session.group then
		session.group = Instance.new("SoundGroup")
		session.group.Name = "R3ST_BikeUniverse_OwnAudio"
		session.group.Parent = SoundService
	end
	session.group.Volume = cfg.volume
	-- Stock engine code continuously changes Sound.Volume; a group avoids fighting it.
	local attachment = session.ctx.chassis:FindFirstChild("BikeSounds")
	if attachment then
		for _, sound in ipairs(attachment:GetDescendants()) do
			if sound:IsA("Sound") and not session.sounds[sound] then
				session.sounds[sound] = {old = sound.SoundGroup}
				sound.SoundGroup = session.group
			end
		end
	end
	for sound in next, session.sounds do if not sound.Parent then session.sounds[sound] = nil end end
end
local function restoreCamera()
	local c = S.camera
	if not c then return end
	if c.script and c.script.Parent and c.script.Disabled == true then c.script.Disabled = c.disabled end
	if c.camera and c.camera.Parent and c.camera.FieldOfView == c.last then c.camera.FieldOfView = c.old end
	S.camera = nil
end
local function applyCamera()
	local camera = workspace.CurrentCamera
	if not cfg.camera or not camera then restoreCamera(); return end
	if S.camera and S.camera.camera ~= camera then restoreCamera() end
	if not S.camera then
		local ps = LP:FindFirstChild("PlayerScripts")
		local scriptInstance = ps and ps:FindFirstChild("BikeCameraFOV")
		if not scriptInstance or not scriptInstance:IsA("LocalScript") then return end
		S.camera = {camera = camera, old = camera.FieldOfView, script = scriptInstance, disabled = scriptInstance.Disabled}
		scriptInstance.Disabled = true
	end
	camera.FieldOfView = cfg.fov
	S.camera.last = cfg.fov
end
local function clearTags()
	for player, tag in next, S.tags do tag.gui:Destroy(); S.tags[player] = nil end
end
local function updateTags()
	if not cfg.esp then clearTags(); return end
	local anchors = {}
	for _, bike in ipairs(CollectionService:GetTagged("Scooter")) do
		if bike.Parent then
			local owner = bike:GetAttribute("Owner")
			local chassis = bike:FindFirstChild("Chassis")
			local seat = bike:FindFirstChildWhichIsA("VehicleSeat")
			if chassis and seat and seat.Occupant then anchors[owner] = chassis end
		end
	end
	local seen = {}
	local camera = workspace.CurrentCamera
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LP then
			seen[player] = true
			local char = player.Character
			local root = anchors[player.UserId] or (char and char:FindFirstChild("HumanoidRootPart"))
			local tag = S.tags[player]
			if root and root.Parent and (cfg.names or cfg.distance) then
				if not tag then
					local gui = Instance.new("BillboardGui")
					gui.Name = "R3ST_BikeUniverse_Tag"
					gui.Size = UDim2.fromOffset(220, 24)
					gui.StudsOffset = Vector3.new(0, 4, 0)
					gui.AlwaysOnTop = true
					gui.MaxDistance = 6000
					local label = Instance.new("TextLabel")
					label.Size = UDim2.fromScale(1, 1)
					label.BackgroundTransparency = 1
					label.TextColor3 = Color3.new(1, 1, 1)
					label.TextStrokeTransparency = 0.3
					label.Font = Enum.Font.GothamMedium
					label.TextSize = 13
					label.Parent = gui
					gui.Parent = LP:FindFirstChildOfClass("PlayerGui")
					tag = {gui = gui, label = label}
					S.tags[player] = tag
				end
				tag.gui.Adornee = root
				tag.gui.Enabled = true
				local name = cfg.names and player.Name or ""
				if cfg.distance and camera then
					name ..= (name ~= "" and "  " or "") .. tostring(math.floor((root.Position - camera.CFrame.Position).Magnitude + 0.5)) .. " studs"
				end
				tag.label.Text = name
			elseif tag then tag.gui.Enabled = false end
		end
	end
	for player, tag in next, S.tags do
		if not seen[player] then tag.gui:Destroy(); S.tags[player] = nil end
	end
end
local function disarm(profile)
	for key, value in next, Core.defaults do if type(value) == "boolean" then profile[key] = false end end
end
local function panic()
	disarm(cfg.default)
	for _, profile in next, cfg.profiles do disarm(profile) end
	cfg.camera, cfg.audio, cfg.esp = false, false, false
	changed()
	release(); restoreCamera(); clearTags()
	Log.info("panic: all local overrides OFF")
end
local function destroy()
	if not S.alive then return end
	S.alive = false
	cancelSave(); saveNow()
	for _, conn in ipairs(S.conns) do conn:Disconnect() end
	release(); restoreCamera(); clearTags()
	for i = #S.patches, 1, -1 do
		local patch = S.patches[i]
		if patch.target[patch.key] == patch.last then patch.target[patch.key] = patch.old end
	end
	if Shell then Shell.destroy() end
	if G[GKEY] and G[GKEY].destroy == destroy then G[GKEY] = nil end
	Log.info("unload: owned values restored")
end
local function preset(name)
	local p = Core.profile()
	if name == "Balanced" then p.movement, p.handling = true, true
	elseif name == "Fast" then
		p.movement, p.handling = true, true
		p.speed, p.power, p.grip, p.brakes = 1.8, 2.5, 1.5, 1.5
	elseif name == "Stunt" then
		p.stunts, p.hold, p.pop, p.strength = true, true, 1.2, 1.25
	elseif name == "Farm" or name == "Scrape Farm" then
		p.auto, p.crashGuard, p.trafficGuard, p.modifiers, p.bank, p.combo = true, true, true, true, true, true
		p.scrape = name == "Scrape Farm"
	end
	bind(active())
	if S.session then resetFarm(S.session) end
	if S.session then cfg.profiles[S.session.key] = p else cfg.default = p end
	if S.session then refreshGrace(S.session, p) end
	changed()
end
local function buildUI()
	local Kit = HOST.ui
	assert(Kit.SHELL_CONTRACT == "1", "R3ST shell contract mismatch")
	Shell = Kit.moduleShell({id = "bike-universe", title = "Bike Universe", version = BUILD_VERSION, hostGlobal = HOST,
		subtitle = "Per-bike tuning and riding assists", gameId = EXPECTED_GAME, placeId = EXPECTED_PLACE,
		tabs = {"Speed", "Handling", "Stunts", "Guards", "View", "Config"}, cfg = {},
		save = saveConfig, live = S.live, conns = S.conns, onUnload = destroy,
		onSettings = function() Shell.show("Config") end})
	local W = Shell.W
	local function toggle(page, label, key, desc, global)
		W.toggle(page, {label = label, key = key, desc = desc,
			ready = function()
				if key == "scrape" then return Physics and type(Physics.tail) == "function" and type(Physics.tailGround) == "function", "Tail geometry API unavailable" end
				if key == "modifiers" then return Loadout and type(Loadout.inSlot) == "function", "Native trick loadout unavailable" end
				return true
			end,
			get = function() return global and cfg[key] or (not global and currentProfile()[key]) end,
			set = function(value) if global then setGlobal(key, value) else setProfile(key, value) end end})
	end
	local function slider(page, label, key, global)
		local range = global and Core.globalLimits[key] or Core.limits[key]
		W.slider(page, {label = label, key = key, min = range[1], max = range[2],
			get = function() return global and cfg[key] or currentProfile()[key] end,
			set = function(value) if global then setGlobal(key, value) else setProfile(key, value) end end,
			fmt = function(value)
				if key == "bankSeconds" or key == "segmentSeconds" then return string.format("%.0fs", value) end
				if key == "releaseRate" then return string.format("%.0f°/s", value) end
				if key == "angle" or key == "fov" or key == "scrapeOffset" or key == "margin" then return string.format("%.1f°", value) end
				return string.format("%.2fx", value)
			end})
	end
	local speed = Shell.page("Speed")
	W.section(speed, "Movement")
	W.statusRow(speed, function()
		local session = S.session
		return session and ("Bike: " .. session.key) or "No owned bike — editing defaults"
	end)
	W.statusRow(speed, function()
		local ctx = active()
		return ctx and ("Ride: %.0f km/h · stock tune: %.0f km/h"):format(math.abs(ctx.speed or 0) * 3.6,
			S.session and S.session.base.MaxSpeedKmh or 80) or "Ride: no owned bike"
	end)
	toggle(speed, "Movement tuning", "movement", "Speed-hacking kick recorded. Starts OFF each load; server limit unknown.")
	for _, row in ipairs({{"Top speed", "speed"}, {"Acceleration", "power"}, {"Reverse speed", "reverse"}, {"Coasting drag", "coast"}}) do slider(speed, row[1], row[2]) end
	for _, name in ipairs({"Balanced", "Fast", "Stunt", "Farm", "Scrape Farm", "Stock"}) do
		W.button(speed, name, "Apply to this bike type", function() preset(name) end)
	end
	local handling = Shell.page("Handling")
	W.section(handling, "Grip and steering")
	toggle(handling, "Handling tuning", "handling")
	for _, row in ipairs({{"Tire grip", "grip"}, {"Braking", "brakes"}, {"Turn-in speed", "turn"}, {"Lean angle", "lean"}, {"Steering angle", "steer"}}) do slider(handling, row[1], row[2]) end
	W.section(handling, "Suspension")
	toggle(handling, "Suspension tuning", "suspension")
	for _, row in ipairs({{"Spring frequency", "frequency"}, {"Compression damping", "damping"}, {"Rebound damping", "rebound"}, {"Suspension travel", "travel"}, {"Pitch damping", "pitch"}}) do slider(handling, row[1], row[2]) end
	local stunts = Shell.page("Stunts")
	W.section(stunts, "Wheelie assistance")
	toggle(stunts, "Wheelie hold assist", "hold", "Hold Ctrl / L1 / touch wheelie. Release or Space / B to lower.")
	toggle(stunts, "Auto wheelie", "auto", "Hands-free wheelie. Steer and throttle manually; brake, phone or text pauses.")
	toggle(stunts, "Scrape mode", "scrape", "Uses this bike's real tail contact. Unreachable scrape angles pause the assist.")
	W.statusRow(stunts, function()
		local session = S.session
		return session and ("Wheelie: %.1f° · %.1fs · %s"):format(math.deg(session.ctx.wheelieAngle or 0),
			session.wheelieSeconds or 0, session.assist or "idle")
			.. (session.target and (" · target %.1f°"):format(session.target) or "") or "Wheelie: no owned bike"
	end)
	slider(stunts, "Hold angle", "angle")
	slider(stunts, "Scrape angle offset", "scrapeOffset")
	slider(stunts, "Loop-out margin", "margin")
	W.section(stunts, "Chain farming")
	toggle(stunts, "Auto modifiers", "modifiers", "Two compatible equipped ground tricks. Manual tricks take priority.")
	toggle(stunts, "Combo linking", "combo", "Completes three varied entries with short gaps, then holds the chain.")
	slider(stunts, "Combo segment", "segmentSeconds")
	toggle(stunts, "Automatic banking", "bank", "Requires Auto wheelie. Gently lowers, waits for stock cash-out and observed Cash.")
	slider(stunts, "Bank interval", "bankSeconds")
	slider(stunts, "Release speed", "releaseRate")
	W.button(stunts, "Bank chain now", "Gently release and wait for the game's normal payout", function()
		if S.session and currentProfile().auto then S.session.farm.forceBank = true end
	end)
	W.statusRow(stunts, function()
		local session = S.session
		return session and ("Farm: %s · links %d/3 · %s"):format(session.farm.phase or "off",
			session.farm.segments or 0, session.modNote or "manual tricks") or "Farm: waiting for owned bike"
	end)
	W.statusRow(stunts, function()
		local delta = (LP:GetAttribute("Cash") or S.cashStart) - S.cashStart
		return ("Cash delta: %.0f · %.0f/min · banks %d · guard saves %d"):format(delta,
			delta * 60 / math.max(1, os.clock() - S.started), S.banks, S.guardSaves)
	end)
	toggle(stunts, "Stunt tuning", "stunts")
	for _, row in ipairs({{"Wheelie strength", "strength"}, {"Pop height", "pop"}, {"Air gravity", "gravity"}, {"Air trick speed", "airRate"}, {"Tailwhip speed", "whip"}}) do slider(stunts, row[1], row[2]) end
	local guards = Shell.page("Guards")
	W.section(guards, "Local crash guards")
	toggle(guards, "Physics crash guard", "crashGuard", "New physics crashes and impact grace; not every trick or server crash.")
	toggle(guards, "Traffic contact guard", "trafficGuard", "Skips this bike's local traffic collision response; not server immunity.")
	W.statusRow(guards, function() return "Server validation is unknown. Existing crashes are not reversed." end)
	W.statusRow(guards, function()
		local police, traffic = LP:GetAttribute("Set_Police"), LP:GetAttribute("Set_Traffic")
		return ("Native police: %s · traffic: %s · wanted %s (keep both ON)"):format(
			police == nil and "unknown" or police and "ON" or "OFF",
			traffic == nil and "unknown" or traffic and "ON" or "OFF", tostring(LP:GetAttribute("WantedStars") or 0))
	end)
	local view = Shell.page("View")
	W.section(view, "Camera")
	toggle(view, "Fixed FOV", "camera", "Replaces only the game's dynamic FOV script while enabled.", true)
	slider(view, "Field of view", "fov", true)
	W.section(view, "Audio")
	toggle(view, "Own-bike audio mixer", "audio", "Engine, wind and tire sounds; stock RPM and pitch stay intact.", true)
	slider(view, "Own-bike volume", "volume", true)
	W.section(view, "Player tags")
	toggle(view, "Player ESP", "esp", nil, true)
	toggle(view, "Names", "names", nil, true)
	toggle(view, "Distance", "distance", nil, true)
	local config = Shell.page("Config")
	W.section(config, "Lifecycle")
	W.statusRow(config, function() return "Build " .. BUILD_VERSION .. " · Delete panic · K unload" end)
	W.statusRow(config, function() return S.error and ("Error: " .. S.error) or "Local overrides only · saved per bike type" end)
	W.button(config, "Resync bike", "Restore owned overrides, then recapture current stock attributes", function() release(); S.revision += 1 end)
	W.button(config, "Restore this bike", "Reset only this bike profile", function() preset("Stock") end)
	W.button(config, "Panic", "Disable all saved local overrides", panic)
	W.button(config, "Unload", "Restore owned values; preserve saved choices", destroy)
	Shell.ready()
end
local function start()
	install()
	Log.info("movement starts OFF: speed-hacking kick recorded 2026-10-28; saved multipliers retained")
	G[GKEY] = {build = BUILD_VERSION, destroy = destroy, embedded = true,
		setProfile = setProfile, setGlobal = setGlobal, panic = panic,
		status = function() return {build = BUILD_VERSION, bike = S.session and S.session.key,
			error = S.error, profile = Core.profile(currentProfile()),
			farm = S.session and S.session.farm.phase, assist = S.session and S.session.assist,
			banks = S.banks, guardSaves = S.guardSaves, cashDelta = (LP:GetAttribute("Cash") or S.cashStart) - S.cashStart} end}
	buildUI()
	S.conns[#S.conns + 1] = UIS.InputBegan:Connect(function(input, processed)
		if processed or UIS:GetFocusedTextBox() then return end
		if input.KeyCode == Enum.KeyCode.Delete then panic()
		elseif input.KeyCode == Enum.KeyCode.K then destroy() end
	end)
	-- Stock step drives simulation; this worker only handles UI/seat/audio at 10Hz.
	local elapsed = 0
	S.conns[#S.conns + 1] = RunService.Heartbeat:Connect(function(dt)
		if not S.alive then return end
		elapsed += dt
		if elapsed < 0.1 then return end
		elapsed = 0
		safe("worker", function()
			local session = bind(active())
			if session then applyTune(session); refreshGrace(session, cfg.profiles[session.key]); applyAudio(session) end
			applyCamera(); updateTags()
			for _, fn in ipairs(S.live) do safe("ui.live", fn) end
		end)
		S.writing = false
	end)
	Log.info(("resumed camera=%s audio=%s esp=%s; bike profiles=%d"):format(
		tostring(cfg.camera), tostring(cfg.audio), tostring(cfg.esp), (function()
			local n = 0; for _ in next, cfg.profiles do n += 1 end; return n
		end)()))
end
local ok, err = xpcall(start, function(message) return tostring(message) end)
if not ok then Log.err("entry: " .. tostring(err)); destroy() end
