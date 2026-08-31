--------------------------------------------------------------------------
-- gd2.lua -- R3ST Hub / Ghost Driver v2026-08-31.gd2.34 (2026-08-31)   PlaceId 137228775845999
-- 2026-08-31.gd2.34: adopt the shared R3ST control template (scripts/r3st_ui.lua).
--   The seven tabs, every toggle, slider, button and readout are unchanged --
--   the kit exposes the same widget signatures -- but they now draw as two
--   columns of cards with pill toggles and track sliders, the same as every
--   other module in the hub. Embedded, the kit comes from __R3ST_HOST.ui so hub
--   and module cannot run two versions. No controller, tuning or physics code
--   touched.
-- 2026-08-28.gd2.33: honour hub.lua's __R3ST_HOST contract -- when the hub mounts
--   us we render into its content host, scaled to fit, and create no ScreenGui,
--   blur, drag or hide key of our own. Standalone inject unchanged; no controller
--   or physics code touched.
-- 2026-08-28.gd2.32: add return-to-hub navigation for unified module transition.
-- 2026-08-28.gd2.31: port frontend to R3ST Hub shell; backend/controllers unchanged.
-- 2026-08-26.gd2.30: add saved CONFIG toggle for RightAlt + left-click seated-car teleport.
-- 2026-08-26.gd2.29: Vehicle master now lowers every owned-car sound; expose engine, exhaust/backfire, tire, brake, horn and accessory levels.
-- 2026-08-26.gd2.28: label nonlinear backfire modes correctly and clear lingering particles when OFF.
-- 2026-08-26.gd2.27: other-car mixer uses one SoundGroup, eliminating hundreds of Volume feedback loops.
-- 2026-08-26.gd2.26: add independent mixer for other players' complete vehicle audio.
-- 2026-08-26.gd2.25: vehicle mixer covers owned-car backfire, tire, brake, horn and accessory sounds.
-- 2026-08-26.gd2.24: seed stock tuning stages for newly spawned limited cars already hooked by TuningApplier.
-- 2026-08-26.gd2.23: cash magnet disables touch on expanded sensors, preventing remote mod-shop popups.
-- 2026-08-26.gd2.22: one 8 Hz scheduler, one seat resolver, custom presets
--   readable, log truncates per inject, history moved to GHOST_DRIVER.md.
-- 2026-08-26.gd2.21: road prefetch -- fixes wheels vanishing / falling out of
--   the map at a highway race start (the car outran instance streaming).
-- 2026-08-25.gd2.20: huge cash range, preview visibility, adaptive server-budget mode.
-- 2026-08-25.gd2.19: add session-only cash magnet using visible expanded near-miss sensors.
-- 2026-08-24.gd2.18: stop stale looped swerve heartbeat when danger bar/UI ends.
--
-- DETECTION POSTURE (potassium-dev SS5.6)
--   Rung 3 (local SetAttribute the game's own client code reacts to) for the
--   whole tune path, rung 2 (writes to client-owned instances) for audio,
--   forces and hitboxes, and rung 5 for click-teleport of the network-owned car.
--   No remote is called directly by click-teleport. Cash magnet
--   makes the stock TrafficClientHitbox send normal TrafficSwerveEvent calls,
--   so it boots OFF every inject and is armed only by its panel button.
--   * A client SetAttribute on a replicated attribute does NOT replicate, but
--     it DOES raise the local AttributeChanged that TuningApplier listens on
--     (0562.lua:1112). The game's own applier then does the physics.
--   * LOG MONITORING = 1: PerformanceSender calls LogService:GetLogHistory()
--     (anticheat_deep.txt:26-29, 0356.lua:921). This file never print/warns.
--     TuningApplier itself prints one "TUNING APPLIED" line per apply
--     (0562.lua:540), so a whole panel change is staged behind ONE apply:
--     its AttributeChanged connection is disabled while we write, re-enabled,
--     then a single trigger attribute is flipped. One user action, one line.
--   * ENFORCEMENT 0 / REPORTING 0 / CLIENT INSPECTION 0 (anticheat_deep.txt
--     :14-22). That describes the GAME's code only; the server still bans.
--   * Network-visible regardless of this file: EngineTelemetry:FireServer
--     (rpm/throttle/boost, 0205.lua:513) and HitboxAudit:FireServer (which
--     TrafficCollision* parts EXIST, 0481.lua:186-203). The crash guard
--     therefore RESIZES those parts instead of removing them - the audit only
--     tests FindFirstChild, so a resized part still reports present.
--   * CarSpeedLimits (0225.lua) is required by no client script -> a server
--     script uses it. Speed above ratedMph * 1.6 * upgradeScale is the one
--     real exposure here. The GUARD readout states it; nothing auto-throttles,
--     because an oscillating limiter would spam TUNING APPLIED lines. The
--     gearbox is PLANNED under that ceiling once per apply (Trans.fit), which
--     is a single write, not a control loop.
--
-- POWER LEVER: Drive builds RPM-indexed power tables ONCE at car load and
--   Engine() reads them by [gear+2][floor(rpm/100)] (0026.lua:742-871,
--   1218-1245); RefreshTuneCache rebuilds the scalar cache only, so a live
--   Horsepower write moves the HUD and nothing else. DriveHook rebuilds those
--   tables in place through Drive's own GetNCurve/GetTCurve/GetSCurve.
--
-- GEARBOX: Drive upshifts on SPEED, not RPM (0026.lua:913), so the shift point
--   is capped at 88% of redline (Tune.resolve) and the whole box is scaled to
--   fit the real ceiling (Trans.fit). Why both exist: GHOST_DRIVER.md,
--   "gd2.lua incident history".
--
-- HP LEVER: StockHorsepower, not BaseHorsepower. applyEngineSwapClient
--   rewrites BaseHorsepower = swap.Power or StockHorsepower on EVERY apply
--   (0562.lua:202), so a BaseHorsepower write is clobbered before it is read.
--   StockHorsepower / StockWeight are only written when nil (0562.lua:185-190)
--   and BaseRedline / BasePeakRPM only when nil (0562.lua:427-429), so those
--   four are the durable inputs. All four are on the applier's ignore list,
--   so writing them raises no apply by itself - that is what makes the single
--   batched trigger possible.
--
-- Re-inject safe: self-teardown on load. Restores everything on unload.
-- UNLOADS_ON_INJECT: __GD2
-- RightShift = show/hide | RightControl = unload | Delete = panic restore
--------------------------------------------------------------------------

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local HttpService = game:GetService("HttpService")

local LP = Players.LocalPlayer
local BUILD_VERSION = "2026-08-31.gd2.34"
local LOG_FILE = "logs/gd2.log"
local CFG_FILE = "gd2_config.json"
local OLD_CFG_FILE = "gd_config.json"

local GENV = (getgenv and getgenv()) or _G
if type(GENV) ~= "table" then
	GENV = _G
end
local GKEY = "__GD2"

-- LogService:GetLogHistory() is read by the game's PerformanceSender.
-- File only. Never print, never warn, not even on error.
--
-- Potassium's appendfile only appends to a file that ALREADY EXISTS
-- (Potassium-API-Docs.md:2444). On a brand new log name every append throws,
-- and a pcall around it turns the whole script silent. So the file is created
-- with writefile first, and the boot stamp is written unbuffered before
-- anything else can fail.
local LOGBUF, LOGLAST = {}, 0

local function logRaw(blob)
	if type(writefile) ~= "function" then
		return false
	end
	local exists = type(isfile) == "function" and isfile(LOG_FILE)
	if not exists then
		return (pcall(writefile, LOG_FILE, blob))
	end
	if type(appendfile) == "function" then
		local ok = pcall(appendfile, LOG_FILE, blob)
		if ok then
			return true
		end
	end
	-- last resort: read-modify-write, so a broken appendfile is never silent
	local ok, prev = pcall(readfile, LOG_FILE)
	return (pcall(writefile, LOG_FILE, (ok and prev or "") .. blob))
end

local function logflush()
	if #LOGBUF == 0 then
		return
	end
	local blob = table.concat(LOGBUF)
	LOGBUF = {}
	logRaw(blob)
end

local function log(msg)
	LOGBUF[#LOGBUF + 1] = ("[%.2f] %s\n"):format(os.clock(), tostring(msg))
	if #LOGBUF < 24 and os.clock() - LOGLAST < 2 then
		return
	end
	LOGLAST = os.clock()
	logflush()
end

-- Written before the teardown block, before Config, before anything that can
-- throw. If this line is missing from the log, the file never executed.
--
-- It TRUNCATES, like cs_core.log does. An append-only gd2.log reached 298 KB
-- across sessions, which costs twice: every diagnosis has to first work out
-- which of a dozen boots it is reading (the log-triage mistake ledger entry
-- "diagnosed a truncated log" is the same failure from the other side), and
-- the read-modify-write fallback in logRaw rewrites the whole file per
-- append. One inject, one log.
pcall(writefile, LOG_FILE,
	("===== gd2 boot %s | clock %.2f =====\n"):format(BUILD_VERSION, os.clock()))

-- teardown any previous injection before we build anything
do
	local prev = GENV[GKEY]
	if type(prev) == "table" and type(prev.unload) == "function" then
		pcall(prev.unload)
	end
	GENV[GKEY] = nil
end

--==========================================================================
-- Util
--==========================================================================
local U = {}

function U.clamp(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

function U.lerp(a, b, t)
	return a + (b - a) * t
end

function U.round(v, places)
	local m = 10 ^ (places or 0)
	return math.floor(v * m + 0.5) / m
end

-- studs/s -> mph. CarSpeedLimits.studsFor is mph/0.35 (0225.lua:52).
function U.mph(studs)
	return studs * 0.35
end

-- The seated car, resolved from the character. THE one copy: CarBinder, the
-- crash guard, the cash magnet and the road prefetch all need exactly this and
-- each had grown its own identical version, with CashMagnet and StreamAhead
-- reaching into Guard.seated for it.
--
-- Deliberately weaker than a CarBinder session: it needs a seat and a model
-- and nothing else. A session additionally proves the A-Chassis Interface, the
-- tune module and (for tuning) EngineStage, and a car missing any of those --
-- an untuned Voss RT8 -- never produces one. Crash protection and prefetch
-- must still work on that car, so they stop here.
function U.seatedCar()
	local char = LP.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.SeatPart
	if not (seat and seat:IsA("VehicleSeat") and seat.Parent) then
		return nil, nil
	end
	local model = seat:FindFirstAncestorWhichIsA("Model")
	if not (model and model.Parent) then
		return nil, nil
	end
	return model, seat
end

--==========================================================================
-- Limits -- the two speed ceilings the gearbox has to fit under
--
--   * AeroDrag brakes hard once seat speed * 0.56315 passes 400 km/h
--     (0483.lua:58-64). That is the wall the car hits in practice.
--   * CarSpeedLimits.ceilingFor is the server's cap: ratedMph / 0.35 *
--     HEADROOM(1.6) * upgradeScale, in studs/s (0225.lua:52,96).
--
-- Declared this early because TransmissionPlanner needs it and Aero, which
-- owns whether the brake is live, is defined much further down.
--==========================================================================
local Limits = {}
Limits.AERO_WALL_MPH = U.mph(400 / 0.56315)   -- ~248.6 mph
Limits.limiterActive = true                   -- Aero.setLimiter keeps this true

local speedMod, speedRetryAt = nil, 0

-- Never a WaitForChild: it would stall every caller for its timeout, and one
-- caller is an 8 Hz status row. But a single miss must not latch either --
-- this file can be injected before ReplicatedStorage has finished
-- replicating, and the old code marked CarSpeedLimits "not available" for the
-- rest of the session on that one miss, so Trans.fit planned every gearbox
-- against the aero wall alone and never saw the server cap. Retry on a 2 s
-- backoff until it resolves, then latch.
function Limits.serverMph(car)
	if not speedMod and os.clock() >= speedRetryAt then
		speedRetryAt = os.clock() + 2
		local inst = ReplicatedStorage:FindFirstChild("CarSpeedLimits")
		if inst and inst:IsA("ModuleScript") then
			local ok, mod = pcall(require, inst)
			if ok and type(mod) == "table" and type(mod.ceilingFor) == "function" then
				speedMod = mod
				log("limits: CarSpeedLimits resolved")
			end
		end
	end
	if not speedMod or not car then
		return nil
	end
	local ok2, studs = pcall(speedMod.ceilingFor, car)
	if not ok2 or type(studs) ~= "number" then
		return nil
	end
	return U.mph(studs)
end

-- Highest speed this car can actually reach, in mph, or nil if unknown.
function Limits.ceilingMph(car)
	local cap = Limits.limiterActive and Limits.AERO_WALL_MPH or nil
	local srv = Limits.serverMph(car)
	if srv and (not cap or srv < cap) then
		cap = srv
	end
	return cap
end

function U.copy(t)
	local o = {}
	for k, v in pairs(t) do
		o[k] = (type(v) == "table") and U.copy(v) or v
	end
	return o
end

function U.merge(base, over)
	local o = U.copy(base)
	if type(over) == "table" then
		for k, v in pairs(over) do
			if type(v) == "table" and type(o[k]) == "table" then
				o[k] = U.merge(o[k], v)
			else
				o[k] = v
			end
		end
	end
	return o
end

-- pcall wrapper that logs instead of throwing. Used at every subsystem edge
-- so one failed controller cannot stop the others (Phase 7 gate).
function U.guard(tag, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		log(("ERR %s: %s"):format(tag, tostring(err)))
	end
	return ok, err
end

--==========================================================================
-- Config -- versioned, per-car profiles, universal presets
--==========================================================================
local Config = {}
Config.VERSION = 3

-- A profile is one coherent tune outcome. Every field is a normalised intent,
-- never a raw A-Chassis value; TuneController resolves it against the car's
-- captured stock state, so the same profile means the same thing on any car.
Config.PROFILE_DEFAULT = {
	powerMult = 1.8,   -- x stock crank HP
	rpmMult = 1.0,     -- x stock redline (audio windows scale with it)
	balance = 0.5,     -- 0 = all acceleration, 1 = all top speed
	launch = 0.35,     -- 0..1 -> launch RPM + first gear bias
	shiftBias = 0.0,   -- -1 shift early .. +1 shift late
	tireStage = 3,     -- 1..5  grip (drives TireGripMult, 0562.lua:696)
	brakeStage = 3,    -- 1..5  BrakeForce 2500..6500
	drivetrain = 1,    -- 1 STOCK, 2 FWD, 3 RWD, 4 AWD
	weightStage = 2,   -- 1..5  -100 lb per stage, floor 0.5x
	fuelStage = 1,     -- 1..3
	dragPct = 1.0,     -- x chassis quadratic drag
	downPct = 1.0,     -- x front/rear downforce
	limiter = true,    -- game's 400 km/h AeroDrag brake left enabled
	stance = { fRide = nil, rRide = nil, fCamber = nil, rCamber = nil, fOff = 0, rOff = 0, link = true },
	exhaust = { low = 0, mid = 0, high = 0, muffler = 1, backfire = 1 },
}

Config.PRESETS = {
	{
		name = "Realistic Strong",
		desc = "Fast road car. Stock rev range, stock sound, keeps the game's speed brake.",
		profile = { powerMult = 1.8, rpmMult = 1.0, balance = 0.5, launch = 0.3,
			tireStage = 3, brakeStage = 3, weightStage = 2, fuelStage = 2,
			dragPct = 1.0, downPct = 1.0, limiter = true },
	},
	{
		name = "Extreme Controllable",
		desc = "Roughly four times stock power, longer rev range, grip and brakes to match.",
		profile = { powerMult = 4.0, rpmMult = 1.35, balance = 0.5, launch = 0.45,
			tireStage = 5, brakeStage = 5, weightStage = 4, fuelStage = 3,
			dragPct = 0.55, downPct = 1.6, limiter = false },
	},
	{
		name = "Absurd Max",
		desc = "No pretence. Very high power, long gearing, almost no drag. Hard to drive.",
		profile = { powerMult = 15.0, rpmMult = 2.2, balance = 0.62, launch = 0.6,
			tireStage = 5, brakeStage = 5, weightStage = 5, fuelStage = 3,
			dragPct = 0.15, downPct = 2.4, limiter = false },
	},
}

function Config.presetByName(n)
	for _, p in ipairs(Config.PRESETS) do
		if p.name == n then
			return p
		end
	end
	return Config.PRESETS[1]
end

Config.DEFAULT = {
	version = Config.VERSION,
	ui = { tab = "SPEED", x = 40, y = 120, hidden = false },
	preset = "Realistic Strong",
	custom = {},          -- name -> profile
	cars = {},            -- car type name -> resolved profile
	audio = {
		music = 1, engine = 1, whoosh = 1, impact = 1,
		ui = 1, ambience = 1, otherCars = 1, radios = 1,
		vehicleEngine = 1, vehicleExhaust = 1, vehicleTires = 1,
		vehicleBrakes = 1, vehicleHorn = 1, vehicleAccessories = 1,
	},
	esp = { enabled = false, name = true, dist = true },
	crashGuard = false,
	clickTeleport = false,
	cashPreview = 0.15,
	-- Road prefetch. ON by default: without it any speed the panel can reach
	-- outruns the game's streaming radius and the car falls through unloaded
	-- road (see StreamAhead). Client-local request, nothing to restore.
	streamAhead = true,
	-- Nitrous: a held-key torque surge. Defaults to OFF (potassium-dev S5.7
	-- item 5) -- a power spike live in a lobby you did not mean to enter is
	-- exactly the "feature left ON through an inject" case.
	nitro = { on = false, mult = 2.5, burn = 4, cooldown = 6, key = "LeftAlt" },
}

Config.data = U.copy(Config.DEFAULT)

local function readJSON(path)
	if not (isfile and isfile(path)) then
		return nil
	end
	local ok, raw = pcall(readfile, path)
	if not ok or type(raw) ~= "string" or raw == "" then
		return nil
	end
	local ok2, tbl = pcall(function()
		return HttpService:JSONDecode(raw)
	end)
	if ok2 and type(tbl) == "table" then
		return tbl
	end
	return nil
end

-- Migration from the old single-scope gd_config.json. The old file kept ONE
-- global desired tune plus per-car ratios (GHOST_DRIVER.md "Bad persistence
-- boundary"); we keep only what still has meaning under the new schema.
--
-- Audio levels are deliberately NOT carried over. The old file's mixer values
-- are the contamination GHOST_DRIVER.md documents: whoosh 0 and impact 0.06,
-- with an impact base near 0.01 persisted as if it were the game's intent.
-- Importing them made a fresh install start with the near-miss whoosh muted
-- and impacts at 6%, which reads exactly like "the audio tab does nothing".
function Config.migrate(old)
	local out = U.copy(Config.DEFAULT)
	if type(old) ~= "table" then
		return out
	end
	if type(old.ui) == "table" then
		out.ui.x = tonumber(old.ui.x) or out.ui.x
		out.ui.y = tonumber(old.ui.y) or out.ui.y
	end
	if type(old.esp) == "table" and old.esp.enabled ~= nil then
		out.esp.enabled = old.esp.enabled == true
	end
	log("config: migrated legacy gd_config.json (tune and mixer values dropped)")
	return out
end

function Config.load()
	local raw = readJSON(CFG_FILE)
	if raw and tonumber(raw.version) == Config.VERSION then
		Config.data = U.merge(Config.DEFAULT, raw)
		log("config: loaded v" .. Config.VERSION)
		return
	end
	if raw then
		-- v2 shipped with the legacy mixer values imported, so anyone who ran
		-- it has whoosh muted and impact at 6% saved as if they chose it.
		-- Reset the mixer once on the way to v3; everything else survives.
		local upgraded = U.merge(Config.DEFAULT, raw)
		if (tonumber(raw.version) or 0) < 3 then
			upgraded.audio = U.copy(Config.DEFAULT.audio)
			log("config: v" .. tostring(raw.version) .. " -> v3, mixer levels reset to 100%")
		end
		upgraded.version = Config.VERSION
		Config.data = upgraded
		return
	end
	local legacy = readJSON(OLD_CFG_FILE)
	if legacy then
		Config.data = Config.migrate(legacy)
		return
	end
	Config.data = U.copy(Config.DEFAULT)
	log("config: fresh defaults")
end

local saveQueued = false
function Config.save()
	if saveQueued then
		return
	end
	saveQueued = true
	task.delay(0.75, function()
		saveQueued = false
		U.guard("config.save", function()
			Config.data.version = Config.VERSION
			writefile(CFG_FILE, HttpService:JSONEncode(Config.data))
		end)
	end)
end

function Config.saveNow()
	U.guard("config.saveNow", function()
		Config.data.version = Config.VERSION
		writefile(CFG_FILE, HttpService:JSONEncode(Config.data))
	end)
end

-- A known car resumes its own resolved profile; a new car starts from the
-- selected universal preset and is then saved under its own key.
function Config.profileFor(carType)
	local d = Config.data
	local p = d.cars[carType]
	if type(p) == "table" then
		return U.merge(Config.PROFILE_DEFAULT, p)
	end
	local preset = Config.presetByName(d.preset)
	local resolved = U.merge(Config.PROFILE_DEFAULT, preset.profile)
	d.cars[carType] = resolved
	Config.save()
	log(("config: new car %s seeded from preset %s"):format(tostring(carType), preset.name))
	return U.copy(resolved)
end

function Config.setProfile(carType, prof)
	Config.data.cars[carType] = U.copy(prof)
	Config.save()
end

function Config.clearCar(carType)
	Config.data.cars[carType] = nil
	Config.save()
end

--==========================================================================
-- CarBinder -- one session object per seat generation
--
-- Identity is proved, not assumed. GHOST_DRIVER.md "Weak live binding": the
-- old script accepted a stale Values folder and then reported gear 0 / RPM 0
-- on a moving car. Here a session is only valid when the PlayerGui
-- A-Chassis Interface's Car ObjectValue IS the model our seat belongs to.
--==========================================================================
local Binder = {}
Binder.session = nil
Binder.gen = 0
Binder.conns = {}
Binder.listeners = {}

function Binder.onChange(fn)
	Binder.listeners[#Binder.listeners + 1] = fn
end

local function fire(ev, sess)
	for _, fn in ipairs(Binder.listeners) do
		U.guard("binder.listener." .. ev, fn, ev, sess)
	end
end

-- CarSpeedLimits.nameFrom: strip the "<player>_" prefix (0225.lua:63-72).
local function carTypeOf(model)
	local n = model and model.Name or ""
	return n:match("^[^_]+_(.+)$") or n
end

-- Identity is proved by interfaceFor below -- the PlayerGui A-Chassis
-- Interface whose Car ObjectValue IS this model. That is a stronger test than
-- any attribute, so this function does NOT require EngineStage.
--
-- It used to. That attribute is stamped by the garage/upgrade system
-- (0087.lua:4418, 0088.lua:3205) and an untuned car may never receive it, so
-- a Voss RT8 produced no session at all: no profile loaded, no profile saved,
-- and every slider reset on every reseat. The tune path alone genuinely needs
-- it -- TuningApplier refuses to hook a car without it (0562.lua:1070) -- and
-- Tune.apply now says so in one clear line instead of the whole panel going
-- dark.
local seatedCar = U.seatedCar

-- The live interface is the PlayerGui copy whose Car ObjectValue points at
-- this exact model. The per-car copies under "A-Chassis Tune" are templates.
local function interfaceFor(model)
	local pg = LP:FindFirstChildOfClass("PlayerGui")
	if not pg then
		return nil
	end
	for _, gui in ipairs(pg:GetChildren()) do
		if gui.Name == "A-Chassis Interface" then
			local carVal = gui:FindFirstChild("Car")
			local values = gui:FindFirstChild("Values")
			local drive = gui:FindFirstChild("Drive")
			if carVal and carVal:IsA("ObjectValue") and carVal.Value == model
				and values and values:FindFirstChild("RPM") and drive then
				return gui, values, drive
			end
		end
	end
	return nil
end

local function tuneModuleFor(model)
	-- waitForTuneModule uses the same lookup (0562.lua:149).
	local m = model:FindFirstChild("A-Chassis Tune", true) or model:FindFirstChild("Tuner", true)
	if m and m:IsA("ModuleScript") then
		return m
	end
	return nil
end

function Binder.destroySession(reason)
	local s = Binder.session
	if not s then
		return
	end
	Binder.session = nil
	log(("bind: session %d destroyed (%s)"):format(s.gen, tostring(reason)))
	fire("unbound", s)
end

-- Change-only reason reporting. tryBind runs at 2 Hz, so a plain log() on
-- every failure would flood the file; but returning silently is what made the
-- first "no UI, no bind, no clue" session cost an hour. Log the reason once,
-- each time it changes, and surface it in the panel.
function Binder.setWhy(why)
	if Binder.why == why then
		return
	end
	Binder.why = why
	log("bind: " .. tostring(why))
end

local function tryBind()
	local model, seat = seatedCar()
	if not model then
		if Binder.session then
			Binder.destroySession("left seat")
		end
		local char = LP.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local sp = hum and hum.SeatPart
		if not char then
			Binder.setWhy("waiting: no character")
		elseif not hum then
			Binder.setWhy("waiting: no humanoid")
		elseif not sp then
			Binder.setWhy("waiting: not seated")
		elseif not sp:IsA("VehicleSeat") then
			Binder.setWhy("waiting: seat is " .. sp.ClassName .. ", not a VehicleSeat")
		else
			Binder.setWhy("waiting: seat has no Model ancestor")
		end
		return
	end
	if Binder.session and Binder.session.car == model and model.Parent then
		return
	end
	if Binder.session then
		Binder.destroySession("car changed")
	end

	local gui, values, drive = interfaceFor(model)
	if not gui then
		Binder.setWhy(("waiting: no A-Chassis Interface in PlayerGui points at %s"):format(model.Name))
		return -- interface not published yet; the poll will retry
	end
	local tuneMod = tuneModuleFor(model)
	if not tuneMod then
		Binder.setWhy(("waiting: no 'A-Chassis Tune' ModuleScript under %s"):format(model.Name))
		return
	end
	local ok, tune = pcall(require, tuneMod)
	if not ok or type(tune) ~= "table" then
		Binder.setWhy("blocked: tune module require failed: " .. tostring(tune))
		return
	end
	if type(tune.Ratios) ~= "table" or #tune.Ratios < 3 then
		Binder.setWhy("blocked: tune table has no usable Ratios")
		return
	end
	Binder.why = nil

	Binder.gen = Binder.gen + 1
	Binder.session = {
		gen = Binder.gen,
		car = model,
		seat = seat,
		type = carTypeOf(model),
		gui = gui,
		values = values,
		drive = drive,
		tune = tune,
		boundAt = os.clock(),
		gears = #tune.Ratios - 2,
		state = "BOUND",
	}
	log(("bind: gen=%d car=%s type=%s gears=%d"):format(Binder.gen, model.Name, Binder.session.type, Binder.session.gears))
	fire("bound", Binder.session)
end

function Binder.start()
	local function hookChar(char)
		local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 10)
		if not hum then
			return
		end
		Binder.conns[#Binder.conns + 1] = hum.Seated:Connect(function()
			task.defer(function() U.guard("bind.seated", tryBind) end)
		end)
	end
	if LP.Character then
		hookChar(LP.Character)
	end
	Binder.conns[#Binder.conns + 1] = LP.CharacterAdded:Connect(function(c)
		Binder.destroySession("respawn")
		hookChar(c)
	end)
end

-- 2 Hz reconcile, driven by the one tick in main(). Not a repair loop: it only
-- creates or drops a session, it never rewrites a tune value.
function Binder.tick()
	local s = Binder.session
	if s and (not s.car.Parent or s.gui.Parent == nil) then
		Binder.destroySession("car or interface destroyed")
	end
	tryBind()
end

function Binder.stop()
	for _, c in ipairs(Binder.conns) do
		pcall(function() c:Disconnect() end)
	end
	Binder.conns = {}
	Binder.destroySession("unload")
end

--==========================================================================
-- DriveHook -- rebuild Drive's precomputed power tables
--
-- Drive builds u145 (natural) / u147 (turbo) / u148 (super) / u146 (electric)
-- once at car load and Engine() reads them by [gear+2][floor(rpm/100)]
-- (0026.lua:742-871, 1224-1266). RefreshTuneCache (0026.lua:648, called every
-- Heartbeat at :1462) refreshes the scalars only. Without rebuilding these,
-- a horsepower change is cosmetic -- that is the "33,231 HP, 400 live HP"
-- result in the old log.
--
-- Upvalue order inside Engine is fixed by first reference: u145, u147, u148,
-- u146 (0026.lua:1028 upvalue list). We take the curve-shaped upvalues in
-- index order and require exactly four; anything else disables the rebuild
-- and says so, rather than guessing.
--==========================================================================
local DriveHook = {}

local function looksLikeCurveTable(v)
	if type(v) ~= "table" then
		return false
	end
	local inner = rawget(v, 1) or rawget(v, 2) or rawget(v, 3)
	if type(inner) ~= "table" then
		return false
	end
	local cell = rawget(inner, 1) or rawget(inner, 0)
	return type(cell) == "table" and cell.Horsepower ~= nil and cell.HpSlope ~= nil
end

-- One silent probe. Bind races the Drive LocalScript: interfaceFor succeeds
-- as soon as the Instance + Values.RPM exist, but Engine / GetNCurve /
-- RefreshTuneCache and the four power tables are assigned hundreds of lines
-- later (0026.lua:648-1027). A single early attach left sess.drv nil for the
-- whole seat generation, so live applies wrote attributes (HUD HP) and never
-- rebuilt the tables Engine() actually reads — felt like "must re-enter car".
local function driveAttachOnce(sess)
	sess.drv = nil
	if not (getsenv and debug and debug.getupvalues) then
		sess.drvErr = "executor lacks getsenv/debug.getupvalues"
		return false
	end
	if not (sess.drive and sess.drive.Parent) then
		sess.drvErr = "Drive script gone"
		return false
	end
	local ok, env = pcall(getsenv, sess.drive)
	if not ok or type(env) ~= "table" then
		sess.drvErr = "getsenv(Drive) failed"
		return false
	end
	if type(env.Engine) ~= "function" or type(env.GetNCurve) ~= "function"
		or type(env.RefreshTuneCache) ~= "function" then
		sess.drvErr = "Drive still initializing"
		return false
	end
	local ok2, ups = pcall(debug.getupvalues, env.Engine)
	if not ok2 or type(ups) ~= "table" then
		sess.drvErr = "getupvalues(Engine) failed"
		return false
	end
	local curves = {}
	for i = 1, 250 do
		local v = ups[i]
		if v ~= nil and looksLikeCurveTable(v) then
			curves[#curves + 1] = v
		end
	end
	if #curves ~= 4 then
		sess.drvErr = ("expected 4 power tables in Drive, found %d"):format(#curves)
		return false
	end
	sess.drv = {
		env = env,
		N = curves[1], T = curves[2], S = curves[3], E = curves[4],
	}
	sess.drvErr = nil
	return true
end

-- waitBudget: seconds to poll while Drive finishes top-level init. 0 = one try.
function DriveHook.attach(sess, waitBudget)
	waitBudget = tonumber(waitBudget) or 0
	local deadline = os.clock() + math.max(waitBudget, 0)
	local attempts = 0
	repeat
		attempts = attempts + 1
		if driveAttachOnce(sess) then
			log(("drive: power tables located (N/T/S/E) after %d try(s)")
				:format(attempts))
			return true
		end
		if os.clock() >= deadline then
			break
		end
		task.wait(0.1)
	until false
	log("drive: " .. tostring(sess.drvErr) .. (" (%d tries)"):format(attempts))
	return false
end

-- Late recovery for a seat generation that bound before Drive finished.
function DriveHook.ensure(sess, waitBudget)
	if sess.drv then
		return true
	end
	return DriveHook.attach(sess, waitBudget or 0)
end

-- Exact reproduction of the game's build loop (0026.lua:747-871), written
-- into the same table objects so Engine() picks it up on its next frame.
function DriveHook.rebuild(sess)
	local d = sess.drv
	if not d then
		return false, sess.drvErr or "no drive hook"
	end
	local tune = sess.tune
	local env = d.env
	local ok, err = pcall(function()
		env.RefreshTuneCache()
		local nRatios = #tune.Ratios
		local steps = math.ceil((tune.Redline + 100) / 100)
		local engineOn = tune.Engine and true or false
		local elecOn = tune.Electric and true or false
		local turbo = (tonumber(tune.Turbochargers) or 0) > 0
		local super = (tonumber(tune.Superchargers) or 0) > 0

		for k = 1, nRatios do
			local gear = k - 2
			local tN, tT, tS, tE = d.N[k], d.T[k], d.S[k], d.E[k]
			if type(tN) ~= "table" then tN = {}; d.N[k] = tN end
			if type(tT) ~= "table" then tT = {}; d.T[k] = tT end
			if type(tS) ~= "table" then tS = {}; d.S[k] = tS end
			if type(tE) ~= "table" then tE = {}; d.E[k] = tE end

			for i = 0, steps do
				local n, e, t, s = tN[i], tE[i], tT[i], tS[i]
				if type(n) ~= "table" then n = {}; tN[i] = n end
				if type(e) ~= "table" then e = {}; tE[i] = e end
				if type(t) ~= "table" then t = {}; tT[i] = t end
				if type(s) ~= "table" then s = {}; tS[i] = s end

				local nhp, ntq, thp, ttq, shp, stq, ehp, etq = 0, 0, 0, 0, 0, 0, 0, 0
				if i == 0 then
					n.Horsepower, n.Torque = 0, 0
					e.Horsepower, e.Torque = 0, 0
					t.Horsepower, t.Torque = 0, 0
					s.Horsepower, s.Torque = 0, 0
				else
					if engineOn then
						n.Horsepower, n.Torque = env.GetNCurve(i * 100, gear)
						if turbo then
							t.Horsepower, t.Torque = env.GetTCurve(i * 100, gear)
						else
							t.Horsepower, t.Torque = 0, 0
						end
						if super then
							s.Horsepower, s.Torque = env.GetSCurve(i * 100, gear)
						else
							s.Horsepower, s.Torque = 0, 0
						end
					else
						n.Horsepower, n.Torque = 0, 0
						t.Horsepower, t.Torque = 0, 0
						s.Horsepower, s.Torque = 0, 0
					end
					if elecOn then
						e.Horsepower, e.Torque = env.GetECurve(i * 100, gear)
					else
						e.Horsepower, e.Torque = 0, 0
					end
				end

				if engineOn then
					nhp, ntq = env.GetNCurve((i + 1) * 100, gear)
					if turbo then
						thp, ttq = env.GetTCurve((i + 1) * 100, gear)
					end
					if super then
						shp, stq = env.GetSCurve((i + 1) * 100, gear)
					end
				end
				if elecOn then
					ehp, etq = env.GetECurve((i + 1) * 100, gear)
				end

				n.HpSlope, n.TqSlope = nhp - n.Horsepower, ntq - n.Torque
				e.HpSlope, e.TqSlope = ehp - e.Horsepower, etq - e.Torque
				t.HpSlope, t.TqSlope = thp - t.Horsepower, ttq - t.Torque
				s.HpSlope, s.TqSlope = shp - s.Horsepower, stq - s.Torque
			end
		end
	end)
	if not ok then
		log("drive.rebuild failed: " .. tostring(err))
		return false, tostring(err)
	end
	log(("drive: rebuilt curves (redline=%d hp=%.0f gears=%d)")
		:format(tune.Redline or 0, tune.Horsepower or 0, #tune.Ratios - 2))
	return true
end

-- Predicted road speed in mph at a given RPM in a given forward gear.
-- Drive: studs/s = (wheelDia * pi / 60) * rpm / (ratio * FinalDrive * FDMult)
-- (0026.lua:584-587, 913).
function DriveHook.speedAt(sess, rpm, gearIndex)
	return DriveHook.speedForRatio(sess, rpm, sess.tune.Ratios[gearIndex + 2])
end

-- Same prediction for a ratio that is planned but not applied yet, so the
-- planner can test a gearbox before it writes it.
function DriveHook.speedForRatio(sess, rpm, ratio)
	if not ratio or ratio <= 0 then
		return 0
	end
	local dia = sess.wheelDia
	if not dia or dia <= 0 then
		return 0
	end
	local tune = sess.tune
	local fd = (tune.FinalDrive or 1) * (tune.FDMult or 1)
	if fd <= 0 then
		return 0
	end
	return U.mph(dia * math.pi / 60 * rpm / (ratio * fd))
end

-- Drive measures wheel diameter as the largest Size.X among the DIRECT
-- children of the car's Wheels folder (0026.lua:337-341). Same rule here, so
-- predicted gear speeds match what Drive actually uses.
function DriveHook.measureWheels(sess)
	local wheels = sess.car:FindFirstChild("Wheels")
	local best = 0
	if wheels then
		for _, child in ipairs(wheels:GetChildren()) do
			if child:IsA("BasePart") and child.Size.X > best then
				best = child.Size.X
			end
		end
	end
	sess.wheelDia = best > 0 and best or nil
	if not sess.wheelDia then
		log("drive: no Wheels folder; speed predictions unavailable")
	end
	return sess.wheelDia
end

--==========================================================================
-- Nitrous -- a held-key torque surge
--
-- The lever is the same one DriveHook already owns: Drive's four RPM-indexed
-- power tables (u145/u146/u147/u148), built ONCE at car load and read every
-- frame by Engine() (0026.lua:742-871, 1218-1245). Scaling every entry in
-- place multiplies real engine output on the very next frame -- no remote, no
-- attribute, no TuningApplier round trip, and no "TUNING APPLIED" line for
-- the game's PerformanceSender to read back out of GetLogHistory.
--
-- Rung 2 of the ladder (potassium-dev S5.1): these tables live in the Drive
-- LocalScript's own environment on this client. The server never sees them;
-- it only ever sees the resulting motion, exactly as it does for the power
-- slider that is already here.
--
-- Why it is a burst and not a slider: a constant multiplier is just the power
-- slider with extra steps, and a permanently raised ceiling is the thing the
-- server-side CarSpeedLimits cap actually watches (0225.lua:96). A few
-- seconds on, then a cooldown, keeps peak speed episodic. Burn and cooldown
-- are both adjustable, cooldown down to 0 if you want it.
--
-- Restore is by inverse scale, tracked through Nitro.applied, so a tune apply
-- landing mid-surge (which rebuilds the tables from Drive's own curves) can
-- never leave a stale multiplier baked in -- see Nitro.forget.
--==========================================================================
local Nitro = {}
Nitro.applied = 1        -- factor currently baked into the live tables
Nitro.active = false
Nitro.until_ = 0         -- os.clock() when the current burn must end
Nitro.readyAt = 0        -- os.clock() when the next burn is allowed
Nitro.held = false
Nitro.status = "off"

local NITRO_FIELDS = { "Horsepower", "Torque", "HpSlope", "TqSlope" }

-- Multiply every entry of the four prebuilt curve tables by k, in place.
local function nitroScale(sess, k)
	local d = sess and sess.drv
	if not d or k == 1 then
		return false
	end
	local ok, err = pcall(function()
		for _, tbl in ipairs({ d.N, d.T, d.S, d.E }) do
			for _, byRPM in pairs(tbl) do
				if type(byRPM) == "table" then
					for _, e in pairs(byRPM) do
						if type(e) == "table" then
							for _, f in ipairs(NITRO_FIELDS) do
								local v = e[f]
								if type(v) == "number" then
									e[f] = v * k
								end
							end
						end
					end
				end
			end
		end
	end)
	if not ok then
		log("nitro: scale failed: " .. tostring(err))
		return false
	end
	return true
end

-- Called by anything that rebuilds the tables from scratch. The rebuild wrote
-- clean stock curves, so whatever we had baked in is gone -- drop the
-- bookkeeping instead of trying to divide it back out of fresh numbers.
function Nitro.forget()
	Nitro.applied = 1
	if Nitro.active then
		Nitro.active = false
		Nitro.held = false
		Nitro.status = "reset by a tune apply"
	end
end

function Nitro.cfg()
	local c = Config.data.nitro or {}
	return {
		on = c.on == true,
		mult = U.clamp(tonumber(c.mult) or 2.5, 1, 6),
		burn = U.clamp(tonumber(c.burn) or 4, 0.5, 20),
		cooldown = U.clamp(tonumber(c.cooldown) or 6, 0, 30),
	}
end

-- Bring the live tables to `want`, whatever they are at now.
local function nitroSet(sess, want)
	if math.abs(want - Nitro.applied) < 0.001 then
		return true
	end
	if not nitroScale(sess, want / Nitro.applied) then
		return false
	end
	Nitro.applied = want
	return true
end

function Nitro.engage()
	local c = Nitro.cfg()
	if not c.on then
		return
	end
	local sess = Binder.session
	if not (sess and sess.car.Parent) then
		Nitro.status = "no car"
		return
	end
	if not DriveHook.ensure(sess, 0) then
		Nitro.status = "engine tables not hooked yet"
		return
	end
	local now = os.clock()
	if now < Nitro.readyAt then
		Nitro.status = ("cooling down %.1fs"):format(Nitro.readyAt - now)
		return
	end
	if Nitro.active then
		return
	end
	if not nitroSet(sess, c.mult) then
		Nitro.status = "could not scale the power tables"
		return
	end
	Nitro.active = true
	Nitro.until_ = now + c.burn
	Nitro.status = ("SURGE x%.1f"):format(c.mult)
	log(("nitro: surge x%.1f for %.1fs"):format(c.mult, c.burn))
end

function Nitro.release(why)
	if not Nitro.active then
		return
	end
	local sess = Binder.session
	Nitro.active = false
	if sess then
		nitroSet(sess, 1)
	else
		Nitro.applied = 1 -- car is gone; the tables went with it
	end
	local c = Nitro.cfg()
	Nitro.readyAt = os.clock() + c.cooldown
	Nitro.status = c.cooldown > 0 and ("cooling down %.0fs"):format(c.cooldown) or "ready"
	log("nitro: released (" .. tostring(why) .. ")")
end

-- Held-key semantics with a hard burn limit, so leaning on the key is not a
-- permanent power increase. Polled rather than timed off the keypress: a
-- task.delay would keep running after the car despawned.
function Nitro.tick()
	if Nitro.active and (os.clock() >= Nitro.until_ or not Nitro.held) then
		Nitro.release(Nitro.held and "burn spent" or "key released")
	elseif not Nitro.active and Nitro.held then
		Nitro.engage()
	end
end

function Nitro.keyDown()
	Nitro.held = true
	Nitro.engage()
end

function Nitro.keyUp()
	Nitro.held = false
	if Nitro.active then
		Nitro.release("key released")
	end
end

--==========================================================================
-- TransmissionPlanner
--
-- A gearbox is generated as one unit, never eight independent sliders.
-- Gear COUNT is fixed: Drive sized its power tables from #Ratios at load
-- (0026.lua:747) and indexes them by gear+2, so adding a gear would index a
-- table that does not exist. Only the values move.
--==========================================================================
local Trans = {}

function Trans.stockRatios(sess)
	local out = {}
	for i = 1, sess.gears do
		local a = sess.car:GetAttribute("DefaultGear_" .. i)
		out[i] = tonumber(a) or (sess.stock.ratios and sess.stock.ratios[i]) or 1
	end
	return out
end

-- balance 0 = short gears (acceleration), 1 = tall gears (top speed).
-- Extra power buys taller top gearing; that is why powerMult appears here.
function Trans.plan(sess, prof)
	local stock = Trans.stockRatios(sess)
	local n = sess.gears
	if n < 1 then
		return {}
	end
	local b = U.clamp(prof.balance or 0.5, 0, 1)
	local pm = math.max(1, prof.powerMult or 1)
	local pull = pm ^ 0.28

	local first = stock[1] * U.lerp(1.28, 0.94, b) * U.lerp(1.0, 1.30, U.clamp(prof.launch or 0, 0, 1))
	local last = stock[n] * U.lerp(1.12, 0.42, b) / pull

	if n == 1 then
		return { U.round(first, 3) }
	end
	if last >= first then
		last = first * 0.35
	end
	last = math.max(last, 0.03)

	local out, ratio = {}, (last / first) ^ (1 / (n - 1))
	for i = 1, n do
		out[i] = U.round(first * ratio ^ (i - 1), 3)
	end
	-- guarantee strict monotonic decrease after rounding
	for i = 2, n do
		if out[i] >= out[i - 1] then
			out[i] = U.round(out[i - 1] * 0.97, 3)
		end
	end
	return out
end

-- Fit the planned box under the speed the car can actually reach.
--
-- Drive upshifts on SPEED, not RPM: it waits for road speed to pass the speed
-- at (PeakRPM + AutoUpThresh) in the CURRENT gear (0026.lua:913). So the last
-- upshift is the binding constraint -- if gear n-1's shift speed sits above
-- the ceiling, the box parks in gear n-1 and every gear above it is dead
-- weight. That is exactly what a high rpmMult plus tall top gearing produced:
-- a 7-speed that never left 4th because leaving it wanted more speed than the
-- 400 km/h brake allows.
--
-- Scaling every ratio by the same factor divides every shift speed by that
-- factor and leaves the spacing the planner chose untouched.
function Trans.fit(sess, r)
	local n = #r.ratios
	if n < 2 or not sess.wheelDia then
		return
	end
	local ceiling = Limits.ceilingMph(sess.car)
	if not ceiling or ceiling <= 0 then
		return
	end
	local shiftRPM = (r.peak or 0) + (r.upThresh or 0)
	if shiftRPM <= 0 then
		return
	end
	-- 0.78, not 0.92. At 0.92 the last upshift landed at 312 mph against a 339
	-- mph ceiling, so the top gear was unreachable in practice: the box parked
	-- in gear n-1 pinned on the redline, Drive kept driving AV.AngularVelocity
	-- at a wheel rate the car could not exceed (0026.lua:1414), and any
	-- overspeed met the full MotorMaxTorque of a 31837 HP tune as a wheel
	-- brake -- the hop/spin at 290-310 mph. 0.78 puts the last upshift near
	-- 264 mph and leaves the top gear real range under the ceiling.
	local target = ceiling * 0.78
	local need = DriveHook.speedForRatio(sess, shiftRPM, r.ratios[n - 1])
	if need <= 0 or need <= target then
		return
	end
	local scale = U.clamp(need / target, 1, 6)
	for i = 1, n do
		r.ratios[i] = U.round(r.ratios[i] * scale, 3)
	end
	r.gearScale = scale
	log(("trans: box shortened x%.2f -- gear %d upshift wanted %.0f mph, ceiling %.0f mph")
		:format(scale, n - 1, need, ceiling))
	local top = DriveHook.speedForRatio(sess, r.redline or 0, r.ratios[n])
	if top > 0 and top < ceiling then
		log(("trans: top gear now tops out at %.0f mph, under the %.0f mph ceiling")
			:format(top, ceiling))
	end
end

--==========================================================================
-- TuneController -- ONE transaction, ONE game apply, ONE verification
--
-- Sequence (rewrite contract "Tune transaction"):
--   1 capture immutable stock (once per car type, persisted)
--   2 disable TuningApplier's AttributeChanged handler on this car
--   3 write every non-trigger and trigger attribute
--   4 re-enable, then flip one dedicated trigger -> exactly one apply
--   5 wait past the applier's own debounce
--   6 verify from the live Tune table, rebuild Drive's curves, retune audio
--   7 on failure restore once and report. Never a repair loop.
--==========================================================================
local Audio -- defined below; TuneController calls it after a verify
local Tune = {}
Tune.state = "IDLE"
Tune.detail = ""
Tune.applySeq = 0
Tune.pending = nil

local TRIGGER_ATTR = "GDApplyStage" -- contains "Stage" -> matches 0562.lua:1004

-- Every attribute this controller ever writes. Snapshotted per car generation
-- before the first apply so Restore puts back the player's real purchased
-- stages, not a hard-coded 1.
local OWNED_ATTRS = {
	"StockHorsepower", "StockWeight", "BaseRedline", "BasePeakRPM",
	"TireStage", "BrakeStage", "WeightStage", "FuelStage", "DrivetrainStage",
	"FrontRideHeight", "RearRideHeight", "FrontCamber", "RearCamber",
	"FrontWheelOffset", "RearWheelOffset",
	"ExhaustLow", "ExhaustMid", "ExhaustHigh", "ExhaustMuffler", "BackfireStage",
}

function Tune.snapshotAttrs(sess)
	if sess.origAttrs then
		return
	end
	local snap = {}
	for _, name in ipairs(OWNED_ATTRS) do
		snap[name] = sess.car:GetAttribute(name)
	end
	for i = 1, sess.gears do
		snap["GearRatio_" .. i] = sess.car:GetAttribute("GearRatio_" .. i)
	end
	sess.origAttrs = snap
end

function Tune.setState(s, d)
	Tune.state = s
	Tune.detail = d or ""
	log(("tune: %s %s"):format(s, Tune.detail))
end

-- Stock capture is keyed by car TYPE and persisted, because our own writes
-- overwrite the game's StockHorsepower on the live model; after a re-inject
-- the model can no longer tell us what stock was.
function Tune.captureStock(sess)
	Config.data.stock = Config.data.stock or {}
	local saved = Config.data.stock[sess.type]
	local car, tune = sess.car, sess.tune
	if type(saved) == "table" and saved.hp then
		sess.stock = U.copy(saved)
		return
	end
	local ratios = {}
	for i = 1, sess.gears do
		ratios[i] = tonumber(car:GetAttribute("DefaultGear_" .. i)) or tune.Ratios[i + 2]
	end
	sess.stock = {
		hp = tonumber(car:GetAttribute("StockHorsepower")) or tune.Horsepower or 300,
		weight = tonumber(car:GetAttribute("StockWeight")) or tune.Weight or 3000,
		redline = tonumber(car:GetAttribute("StockRedline")) or tune.Redline or 8000,
		peak = tonumber(car:GetAttribute("StockPeakRPM")) or tune.PeakRPM or 6800,
		ratios = ratios,
		upThresh = tune.AutoUpThresh or -200,
		dnThresh = tune.AutoDownThresh or 1400,
		idleThrottle = tune.IdleThrottle or 3,
		fRide = tune.FSusLength or 2,
		rRide = tune.RSusLength or 2,
		fCam = tonumber(car:GetAttribute("DefaultFCamber")) or tune.FCamber or 0,
		rCam = tonumber(car:GetAttribute("DefaultRCamber")) or tune.RCamber or 0,
	}
	Config.data.stock[sess.type] = U.copy(sess.stock)
	Config.save()
	log(("tune: stock captured for %s hp=%.0f redline=%d peak=%d")
		:format(sess.type, sess.stock.hp, sess.stock.redline, sess.stock.peak))
end

-- Resolve a normalised profile into concrete attribute values for THIS car.
function Tune.resolve(sess, prof)
	local st = sess.stock
	-- The applier computes Horsepower = BaseHorsepower x engine x turbo x
	-- super x fuel (0562.lua:471-491) and BaseHorsepower is itself rewritten
	-- to StockHorsepower every apply (0562.lua:202). So StockHorsepower is
	-- the pre-stage input: writing st.hp * powerMult gives exactly powerMult
	-- times the car's real current output, whatever stages the player owns.
	-- sess.stageMult is measured live at bind, never assumed.
	local baseHP = st.hp * math.max(0.1, prof.powerMult or 1)
	local redline = math.floor(st.redline * U.clamp(prof.rpmMult or 1, 0.5, 6) + 0.5)
	local peak = math.floor(U.clamp(st.peak / math.max(st.redline, 1), 0.4, 0.96) * redline + 0.5)

	-- Shift point. Drive tests road speed against the speed at
	-- (PeakRPM + AutoUpThresh) in the current gear (0026.lua:913), so this
	-- number sets how much of each gear has to be used before it will shift.
	-- Stock is 6600 of 8000 = 82.5% of redline. shiftBias +1 used to push it
	-- to ~96.5%, which means every gear must be run to within a whisker of
	-- the limiter -- and in the tall gears that speed is past the 400 km/h
	-- brake, so the shift never comes. Cap it at 88% of redline.
	local upThresh = st.upThresh + U.clamp(prof.shiftBias or 0, -1, 1) * math.max(redline - peak, 100) * 0.85
	local maxShift = redline * 0.88
	if peak + upThresh > maxShift then
		upThresh = maxShift - peak
	end

	local r = {
		baseHP = baseHP,
		expectHP = baseHP * (sess.stageMult or 1),
		redline = redline,
		peak = peak,
		weight = st.weight,
		ratios = nil,
		upThresh = upThresh,
		dnThresh = st.dnThresh,
	}
	return r
end

local function applierConnections(car)
	if type(getconnections) ~= "function" then
		return {}
	end
	local ok, conns = pcall(getconnections, car.AttributeChanged)
	if not ok or type(conns) ~= "table" then
		return {}
	end
	local out = {}
	for _, c in ipairs(conns) do
		local scr = nil
		pcall(function() scr = c.Script end)
		if scr and scr.Name == "TuningApplier" then
			out[#out + 1] = c
		end
	end
	return out
end

function Tune.apply(sess, prof, why)
	if not sess or not sess.car.Parent then
		Tune.setState("NEEDS CAR", "no bound car")
		return false
	end
	-- TuningApplier hooks each newly spawned owned car through workspace.ChildAdded
	-- before it checks stage attributes (0633.lua:1079-1089). New limited cars
	-- arrive with no stages at all, so prove the hook exists and seed stock stage
	-- 1 inside the normal batched write. An unhooked car remains a hard stop.
	local held = applierConnections(sess.car)
	if sess.car:GetAttribute("EngineStage") == nil and #held == 0 then
		Tune.setState("NO APPLIER",
			"this car has no EngineStage attribute and no TuningApplier connection. Power, gearing, stance and exhaust cannot apply.")
		return false
	end
	if Tune.state == "APPLYING" then
		Tune.pending = { sess = sess, prof = U.copy(prof), why = why }
		return false
	end
	Tune.captureStock(sess)
	Tune.snapshotAttrs(sess)
	local r = Tune.resolve(sess, prof)
	r.ratios = Trans.plan(sess, prof)
	Trans.fit(sess, r)
	sess.resolved = r

	Tune.setState("APPLYING", why or "apply")
	Tune.applySeq = Tune.applySeq + 1
	local seq = Tune.applySeq
	local car = sess.car

	-- Batch: silence the applier, write everything, restore it, fire once.
	for _, c in ipairs(held) do
		pcall(function() c:Disable() end)
	end

	local writeOk, writeErr = pcall(function()
		if car:GetAttribute("EngineStage") == nil then
			car:SetAttribute("EngineStage", 1)
			car:SetAttribute("TurboStage", 1)
			log("tune: seeded stock stage attributes for " .. sess.type)
		end
		-- non-trigger inputs (ignored by the applier's filter, 0562.lua:995)
		car:SetAttribute("StockHorsepower", r.baseHP)
		car:SetAttribute("StockWeight", r.weight)
		car:SetAttribute("BaseRedline", r.redline)
		car:SetAttribute("BasePeakRPM", r.peak)
		-- trigger inputs
		car:SetAttribute("TireStage", math.floor(U.clamp(prof.tireStage or 3, 1, 5)))
		car:SetAttribute("BrakeStage", math.floor(U.clamp(prof.brakeStage or 3, 1, 5)))
		car:SetAttribute("WeightStage", math.floor(U.clamp(prof.weightStage or 1, 1, 5)))
		car:SetAttribute("FuelStage", math.floor(U.clamp(prof.fuelStage or 1, 1, 3)))
		car:SetAttribute("DrivetrainStage", math.floor(U.clamp(prof.drivetrain or 1, 1, 4)))
		local s = prof.stance or {}
		car:SetAttribute("FrontRideHeight", U.clamp(tonumber(s.fRide) or sess.stock.fRide, 0.2, 6))
		car:SetAttribute("RearRideHeight", U.clamp(tonumber(s.rRide) or sess.stock.rRide, 0.2, 6))
		car:SetAttribute("FrontCamber", U.clamp(tonumber(s.fCamber) or sess.stock.fCam, -15, 15))
		car:SetAttribute("RearCamber", U.clamp(tonumber(s.rCamber) or sess.stock.rCam, -15, 15))
		car:SetAttribute("FrontWheelOffset", U.clamp(tonumber(s.fOff) or 0, -2, 2))
		car:SetAttribute("RearWheelOffset", U.clamp(tonumber(s.rOff) or 0, -2, 2))
		local e = prof.exhaust or {}
		car:SetAttribute("ExhaustLow", U.clamp(tonumber(e.low) or 0, -10, 10))
		car:SetAttribute("ExhaustMid", U.clamp(tonumber(e.mid) or 0, -10, 10))
		car:SetAttribute("ExhaustHigh", U.clamp(tonumber(e.high) or 0, -10, 10))
		car:SetAttribute("ExhaustMuffler", math.floor(U.clamp(tonumber(e.muffler) or 1, 1, 3)))
		local backfireStage = math.floor(U.clamp(tonumber(e.backfire) or 1, 1, 5))
		car:SetAttribute("BackfireStage", backfireStage)
		if backfireStage == 5 then
			for _, descendant in ipairs(car:GetDescendants()) do
				if descendant:IsA("ParticleEmitter") and descendant.Name:sub(1, 4) == "BFX_" then
					descendant.Enabled = false
					descendant:Clear()
				elseif descendant:IsA("Sound") and descendant.Name:sub(1, 4) == "BFX_" then
					descendant:Stop()
				end
			end
		end
		for i = 1, sess.gears do
			car:SetAttribute("GearRatio_" .. i, r.ratios[i])
		end
	end)

	for _, c in ipairs(held) do
		pcall(function() c:Enable() end)
	end

	if not writeOk then
		Tune.setState("ERROR", "attribute write failed: " .. tostring(writeErr))
		return false
	end
	if #held == 0 then
		log("tune: getconnections unavailable; the game may log two applies")
	end

	-- one deliberate supported trigger, last
	car:SetAttribute(TRIGGER_ATTR, (tonumber(car:GetAttribute(TRIGGER_ATTR)) or 0) + 1)

	-- 6: wait past the applier's own waits (0.1 poll loop + task.wait(0.2) +
	-- the 0.15 drain wait, 0562.lua:257-279,1096) before looking at anything.
	task.delay(1.35, function()
		U.guard("tune.verify", function()
			if seq ~= Tune.applySeq then
				return -- superseded by a newer apply
			end
			if not (sess.car.Parent and Binder.session == sess) then
				Tune.setState("NEEDS CAR", "car went away during apply")
				return
			end
			Tune.verify(sess, prof, r)
			local p = Tune.pending
			Tune.pending = nil
			if p and Binder.session == p.sess then
				Tune.apply(p.sess, p.prof, p.why)
			end
		end)
	end)
	return true
end

-- Verify from live effects, never from an attribute echo.
function Tune.verify(sess, prof, r)
	local tune = sess.tune
	local liveHP = tonumber(tune.Horsepower) or 0
	local liveRed = tonumber(tune.Redline) or 0
	if r.baseHP > 0 then
		sess.stageMult = liveHP / r.baseHP -- re-measure from live effect
	end
	sess.liveHP = liveHP

	if liveRed < r.redline - 1 or liveRed > r.redline + 500 then
		Tune.setState("ERROR", ("redline did not take (want %d, live %d)"):format(r.redline, liveRed))
		return
	end
	if liveHP <= 0 then
		Tune.setState("ERROR", "tune reports no horsepower")
		return
	end
	-- ratios: the applier copies GearRatio_i into Ratios[i+2] (0562.lua:678)
	local bad = nil
	for i = 1, sess.gears do
		local want, got = r.ratios[i], tune.Ratios[i + 2]
		if not got or math.abs(got - want) > 0.005 then
			bad = i
			break
		end
	end
	if bad then
		Tune.setState("ERROR", ("gear %d ratio did not take"):format(bad))
		return
	end

	-- shift point is a live Tune field Drive reads every frame (0026.lua:902);
	-- it needs no apply and produces no log line.
	tune.AutoUpThresh = r.upThresh
	tune.AutoDownThresh = r.dnThresh

	-- If the player owns an engine swap, applyEngineSwapClient forces
	-- BaseHorsepower = swap.Power and ignores StockHorsepower entirely
	-- (0562.lua:202), so the staged value lands short. Correct it once, here,
	-- on the live Tune table: RefreshTuneCache re-reads Horsepower every
	-- Heartbeat (0026.lua:648) and the curve rebuild below is what carries it
	-- to the wheels. One write, from the one owner, never a loop.
	local want = r.baseHP * (sess.stageMult or 1)
	if want > 0 and math.abs(liveHP - want) / want > 0.02 then
		log(("tune: horsepower %.0f -> %.0f (applier ignored StockHorsepower)"):format(liveHP, want))
		tune.Horsepower = want
		liveHP = want
		sess.hpCorrected = true
	else
		sess.hpCorrected = false
	end

	-- Idle creep has to be scaled back by the same factor the power went up.
	-- Drive floors the throttle at IdleThrottle/100 (0026.lua:72,393) and
	-- always commands the drive motor to redline wheel speed
	-- (0026.lua:1414), with MotorMaxTorque = torque * throttle
	-- (0026.lua:1364,1367,1399). Stock that is a gentle creep; on a rebuilt
	-- curve at several times the power it becomes a car that will not slow
	-- down and feels like a stuck throttle. Holding
	-- idleThrottle * torque constant keeps the creep at its stock force.
	local st = sess.stock
	-- stock snapshots persisted by builds before this field existed have no
	-- idleThrottle; backfill it once rather than dividing by nil
	if type(st.idleThrottle) ~= "number" then
		st.idleThrottle = tonumber(tune.IdleThrottle) or 3
		Config.data.stock = Config.data.stock or {}
		if type(Config.data.stock[sess.type]) == "table" then
			Config.data.stock[sess.type].idleThrottle = st.idleThrottle
			Config.save()
		end
	end
	local powerK = 1
	local stockLive = st.hp * (sess.stageMult or 1)
	if stockLive > 0 then
		powerK = math.max(liveHP / stockLive, 1)
	end
	local idle = U.clamp(st.idleThrottle / powerK, 0.4, st.idleThrottle)
	if math.abs((tune.IdleThrottle or 0) - idle) > 0.01 then
		tune.IdleThrottle = idle
		log(("tune: idle throttle %.2f -> %.2f (power x%.2f) to keep creep at stock force")
			:format(st.idleThrottle, idle, powerK))
	end

	-- Engine audio follows the redline that actually landed, by ONE factor.
	if Audio and sess.stock.redline > 0 then
		Audio.applyRpmScale(liveRed / sess.stock.redline)
	end

	-- Live apply must hit Drive's precomputed tables. If bind raced Drive init,
	-- sess.drv is nil and a rebuild would no-op the real power change.
	if not DriveHook.ensure(sess, 1.5) then
		Tune.setState("ERROR", "power tables not rebuilt: " .. tostring(sess.drvErr))
		return
	end

	-- A rebuild writes clean stock curves, so any live surge is gone with it.
	Nitro.forget()
	local rebuilt, rerr = DriveHook.rebuild(sess)
	if not rebuilt then
		Tune.setState("ERROR", "power tables not rebuilt: " .. tostring(rerr))
		return
	end

	sess.applied = U.copy(prof)
	Config.setProfile(sess.type, prof)
	Tune.setState("READY", ("%.0f HP @ %d rpm"):format(liveHP, liveRed))
end

-- Restore Stock: put every value we touched back and let the game re-apply
-- once. Clears only the active car profile.
function Tune.restore(sess, keepProfile)
	if not (sess and sess.car.Parent) then
		return false
	end
	Tune.captureStock(sess)
	Tune.snapshotAttrs(sess)
	local st = sess.stock
	local car = sess.car
	local snap = sess.origAttrs or {}
	Tune.applySeq = Tune.applySeq + 1

	local held = applierConnections(car)
	for _, c in ipairs(held) do
		pcall(function() c:Disable() end)
	end
	pcall(function()
		-- exactly what was on the car when we bound it
		for _, name in ipairs(OWNED_ATTRS) do
			car:SetAttribute(name, snap[name])
		end
		for i = 1, sess.gears do
			car:SetAttribute("GearRatio_" .. i, snap["GearRatio_" .. i])
		end
		-- the four Stock* / Base* inputs are only read from the model, and
		-- the model may still be carrying OUR values from a previous session,
		-- so those come from the persisted stock capture instead.
		car:SetAttribute("StockHorsepower", st.hp)
		car:SetAttribute("StockWeight", st.weight)
		car:SetAttribute("BaseRedline", st.redline)
		car:SetAttribute("BasePeakRPM", st.peak)
	end)
	for _, c in ipairs(held) do
		pcall(function() c:Enable() end)
	end
	car:SetAttribute(TRIGGER_ATTR, (tonumber(car:GetAttribute(TRIGGER_ATTR)) or 0) + 1)

	if not keepProfile then
		Config.clearCar(sess.type)
	end
	sess.applied = nil
	sess.hpCorrected = false
	sess.tune.AutoUpThresh = st.upThresh
	sess.tune.AutoDownThresh = st.dnThresh
	if type(st.idleThrottle) == "number" then
		sess.tune.IdleThrottle = st.idleThrottle
	end
	if Audio then
		Audio.applyRpmScale(1)
	end
	Tune.setState("APPLYING", "restoring stock")
	task.delay(1.35, function()
		U.guard("tune.restoreVerify", function()
			if Binder.session ~= sess then
				return
			end
			sess.tune.AutoUpThresh = st.upThresh
			sess.tune.AutoDownThresh = st.dnThresh
			if type(st.idleThrottle) == "number" then
				sess.tune.IdleThrottle = st.idleThrottle
			end
			Nitro.forget()
			DriveHook.rebuild(sess)
			Tune.setState("READY", "stock")
		end)
	end)
	return true
end

--==========================================================================
-- AeroController -- single owner of drag and downforce
--
-- Two independent client drag systems exist:
--   * A-Chassis Aerodynamics writes Body.Drag.T.Force = speed^2 * 0.011333
--     and the two downforce thrusts, every Heartbeat (0010.lua:15-19).
--   * AeroDrag removes speed above 400 km/h (0483.lua:59-64).
-- Disabling Aerodynamics wholesale would remove downforce with the drag, so
-- instead its connection is disabled and this controller writes the same
-- three forces with a user multiplier on each. One writer, no pinning race,
-- identical math. Both connections are re-enabled on unload.
--==========================================================================
local Aero = {}
Aero.dragMult = 1
Aero.downMult = 1
Aero.windLevel = 1   -- follows the vehicle/engine mixer level
Aero.limiter = true
Aero.held = {}
Aero.conn = nil
Aero.parts = nil

local function grabConnections(pred)
	if type(getconnections) ~= "function" then
		return {}
	end
	local ok, conns = pcall(getconnections, RunService.Heartbeat)
	if not ok or type(conns) ~= "table" then
		return {}
	end
	local out = {}
	for _, c in ipairs(conns) do
		local scr
		pcall(function() scr = c.Script end)
		if scr and pred(scr) then
			out[#out + 1] = c
		end
	end
	return out
end

-- The 400 km/h brake is StarterPlayerScripts.AeroDrag, a LocalScript whose
-- only job is that brake (0483.lua:29-66), so disabling the script is rung 4
-- of the ladder: a purely local limiter, nothing replicates.
--
-- The old path matched connections on Connection.Script, which Potassium
-- leaves nil for game-owned connections. It found nothing every time and
-- still logged "disabled", so the brake was live while the panel said it was
-- off -- and the gearbox was planned against a ceiling that did not exist.
local function aeroDragScript()
	local ps = LP:FindFirstChild("PlayerScripts")
	local s = ps and ps:FindFirstChild("AeroDrag")
	if s and s:IsA("LocalScript") then
		return s
	end
	return nil
end

-- Instance writes made directly from a signal callback thread are rejected on
-- Potassium ("lacking capability Plugin"), and every caller here is a UI
-- toggle. task.spawn runs the body immediately on a fresh thread, so this
-- stays synchronous and still lands.
local function setScriptDisabled(scr, off)
	task.spawn(function()
		pcall(function() scr.Disabled = off end)
	end)
	return scr.Disabled == off
end

function Aero.setLimiter(on)
	Aero.limiter = on and true or false

	-- put the brake back first, whichever handle we took last time
	if Aero.held.limiterScript then
		setScriptDisabled(Aero.held.limiterScript, false)
		Aero.held.limiterScript = nil
	end
	for _, c in ipairs(Aero.held.limiter or {}) do
		pcall(function() c:Enable() end)
	end
	Aero.held.limiter = nil

	if Aero.limiter then
		Limits.limiterActive = true
		log("aero: 400 km/h limiter left enabled")
		return
	end

	local killed = false
	local scr = aeroDragScript()
	if scr and setScriptDisabled(scr, true) then
		Aero.held.limiterScript = scr
		killed = true
		log("aero: 400 km/h limiter disabled (AeroDrag LocalScript)")
	end
	if not killed then
		-- fallback for executors that do populate Connection.Script
		local found = grabConnections(function(s)
			return s.Name == "AeroDrag"
		end)
		for _, c in ipairs(found) do
			pcall(function() c:Disable() end)
		end
		Aero.held.limiter = found
		killed = #found > 0
		if killed then
			log(("aero: 400 km/h limiter disabled (%d connection(s))"):format(#found))
		end
	end
	if not killed then
		log("aero: 400 km/h limiter NOT disabled -- no handle; gearing stays under the wall")
	end
	Limits.limiterActive = not killed
end

function Aero.bind(sess)
	Aero.unbind()
	local body = sess.car:FindFirstChild("Body")
	if not body then
		Aero.err = "car has no Body part"
		return false
	end
	local drag = body:FindFirstChild("Drag")
	local dF = body:FindFirstChild("DownforceF")
	local dR = body:FindFirstChild("DownforceR")
	if not (drag and drag:FindFirstChild("T") and dF and dF:FindFirstChild("T")
		and dR and dR:FindFirstChild("T")) then
		Aero.err = "aero force objects missing on this car"
		log("aero: " .. Aero.err)
		return false
	end
	Aero.parts = {
		sess = sess,
		seat = sess.car:FindFirstChild("DriveSeat") or sess.seat,
		dragT = drag.T,
		dfT = dF.T,
		drT = dR.T,
		wind = drag:FindFirstChild("Wind"),
		body = drag:FindFirstChild("Body"),
	}
	Aero.err = nil

	-- take ownership: disable the game's Aerodynamics handler for THIS car
	local found = grabConnections(function(s)
		return s.Name == "Aerodynamics" and s:IsDescendantOf(sess.gui)
	end)
	for _, c in ipairs(found) do
		pcall(function() c:Disable() end)
	end
	Aero.held.aero = found
	if #found == 0 then
		Aero.err = "could not take over Aerodynamics; drag controls inactive"
		log("aero: " .. Aero.err)
		Aero.parts = nil
		return false
	end

	Aero.conn = RunService.Heartbeat:Connect(function()
		local p = Aero.parts
		if not p or not p.seat or not p.seat.Parent then
			return
		end
		-- Aerodynamics drives the wind and body-drag sounds at speed/500
		-- (0010.lua:16-17), which is volume 1.0 at ~500 studs/s and gets
		-- brutal once EchoZone switches AmbientReverb to ParkingLot in a
		-- tunnel (0492.lua:34-60). We own this handler now, so these two are
		-- scaled by the vehicle/engine level instead of running wide open.
		local spd = p.seat.Velocity.Magnitude
		local vol = spd / 500 * Aero.windLevel
		if p.wind then p.wind.Volume = vol end
		if p.body then p.body.Volume = vol end
		p.dfT.Force = Vector3.new(0, spd / -300 * 125 * Aero.downMult, 0)
		p.drT.Force = Vector3.new(0, spd / -300 * 150 * Aero.downMult, 0)
		p.dragT.Force = Vector3.new(0, 0, spd * spd * 0.011333333333333334 * Aero.dragMult)
	end)
	log(("aero: bound (drag x%.2f, downforce x%.2f)"):format(Aero.dragMult, Aero.downMult))
	return true
end

function Aero.unbind()
	if Aero.conn then
		pcall(function() Aero.conn:Disconnect() end)
		Aero.conn = nil
	end
	local p = Aero.parts
	Aero.parts = nil
	-- hand the forces back exactly as the game would next frame
	if p then
		pcall(function()
			local spd = p.seat and p.seat.Parent and p.seat.Velocity.Magnitude or 0
			p.dfT.Force = Vector3.new(0, spd / -300 * 125, 0)
			p.drT.Force = Vector3.new(0, spd / -300 * 150, 0)
			p.dragT.Force = Vector3.new(0, 0, spd * spd * 0.011333333333333334)
		end)
	end
	for _, c in ipairs(Aero.held.aero or {}) do
		pcall(function() c:Enable() end)
	end
	Aero.held.aero = nil
end

function Aero.restoreAll()
	Aero.unbind()
	if Aero.held.limiterScript then
		setScriptDisabled(Aero.held.limiterScript, false)
		Aero.held.limiterScript = nil
	end
	for _, c in ipairs(Aero.held.limiter or {}) do
		pcall(function() c:Enable() end)
	end
	Aero.held.limiter = nil
	Limits.limiterActive = true
end

--==========================================================================
-- TrafficGuard -- undo the traffic crash penalty, measured not guessed
--
-- TrafficClientHitbox multiplies seat velocity by 0.15 and wipes the combo
-- when any of the four TrafficCollision* boxes overlaps a traffic part
-- (0481.lua:280-295).
--
-- Two geometric levers on our own boxes were tried and are PROVEN DEAD by
-- gd2_probe: with the four boxes already at 0.05 studs AND CanQuery=false,
-- crashes still landed. GetPartsInPart uses the query part's geometry and
-- ignores its CanQuery, and shrinking leaves a point exactly where the impact
-- happens. Moving them is worse than useless -- the boxes are welded into the
-- car assembly (probe: "CFrame write holds=NO", and the attempt teleported the
-- whole car 500 studs into the sky).
--
-- The lever is on the far side of the query: GetPartsInPart returns candidate
-- parts and DOES respect the candidates' CanQuery, while ignoring the query
-- part's own. LocalTrafficRenderer builds each traffic car with Body and
-- Shadow at CanQuery=false and ONE queryable part, CoreHitbox, sized
-- (bbox.X*0.3, bbox.Y, bbox.Z*0.3) -- a narrow full-height pillar down the
-- middle of the car (0499.lua:115-131). Traffic is client-spawned, so that
-- pillar is ours to write. Suppressing our OWN TrafficCollision* boxes does
-- nothing: gd2_probe had all four at 0.05 studs and CanQuery=false and
-- crashes still landed, because the query ignores the query part's CanQuery.
--
-- Two geometric levers on our own boxes are PROVEN DEAD by gd2_probe, and the
-- guard has been through four versions to get the lead and the ownership
-- right. Both stories, with the log lines: GHOST_DRIVER.md, "Crash guard, v1
-- to v4". Do not re-derive them.
--==========================================================================
local Guard = {}
Guard.enabled = false
Guard.saves = 0
Guard.rescues = 0
Guard.status = "off"
Guard.conns = {}
Guard.suppressed = {}
Guard.crashLocal = nil
Guard.NAMES = { "TrafficCollisionFront", "TrafficCollisionRear", "TrafficCollisionLeft", "TrafficCollisionRight" }

local G_MARGIN = 4.0
local G_LEAD_TIME = 0.18
local G_CLEAR_DIST = 130
local G_MIN_KMH = 62             -- the game only tests above 70 (0481.lua:279)
local KMH_PER_STUD = 0.5631499999999999
local CRASH_FACTOR = 0.15        -- 0481.lua:281
local CRASH_TOL = 0.025

-- axis-aligned extent of a possibly-rotated box, in the reference frame
local function aabbExtent(rel, halfSize)
	return Vector3.new(
		math.abs(rel.RightVector.X) * halfSize.X + math.abs(rel.UpVector.X) * halfSize.Y + math.abs(rel.LookVector.X) * halfSize.Z,
		math.abs(rel.RightVector.Y) * halfSize.X + math.abs(rel.UpVector.Y) * halfSize.Y + math.abs(rel.LookVector.Y) * halfSize.Z,
		math.abs(rel.RightVector.Z) * halfSize.X + math.abs(rel.UpVector.Z) * halfSize.Y + math.abs(rel.LookVector.Z) * halfSize.Z
	)
end

local function guardRestoreAll()
	for part, originalCanQuery in pairs(Guard.suppressed) do
		if typeof(part) == "Instance" and part.Parent then
			pcall(function() part.CanQuery = originalCanQuery end)
		end
		Guard.suppressed[part] = nil
	end
end

function Guard.release()
	if #Guard.conns > 0 then
		log(("guard: released -- %d avoided, %d recovered this session")
			:format(Guard.saves, Guard.rescues))
	end
	for _, c in ipairs(Guard.conns) do
		pcall(function() c:Disconnect() end)
	end
	Guard.conns = {}
	guardRestoreAll()
	Guard.crashLocal = nil
	Guard.lastMag, Guard.lastVel = nil, nil
end

-- Union AABB of the four crash boxes in seat-local space. This is the exact
-- volume TrafficClientHitbox tests, so the guard can strictly contain it.
function Guard.computeCrashLocal(model, seat)
	local minV, maxV
	for _, n in ipairs(Guard.NAMES) do
		local p = model:FindFirstChild(n, true)
		if p and p:IsA("BasePart") then
			local rel = seat.CFrame:ToObjectSpace(p.CFrame)
			local ext = aabbExtent(rel, p.Size * 0.5)
			local lo, hi = rel.Position - ext, rel.Position + ext
			minV = minV and Vector3.new(math.min(minV.X, lo.X), math.min(minV.Y, lo.Y), math.min(minV.Z, lo.Z)) or lo
			maxV = maxV and Vector3.new(math.max(maxV.X, hi.X), math.max(maxV.Y, hi.Y), math.max(maxV.Z, hi.Z)) or hi
		end
	end
	if not minV then
		return nil, "no crash boxes on this car"
	end
	local size = maxV - minV
	-- An earlier build of this script shrank those boxes to 0.05 studs and
	-- could be replaced without restoring them. A degenerate union would make
	-- the guard far narrower than the car, so fall back to the real body.
	if size.X < 2 or size.Z < 2 then
		local ok, cf, bsize = pcall(function()
			return model:GetBoundingBox()
		end)
		if ok and typeof(bsize) == "Vector3" and bsize.X > 1 then
			local rel = seat.CFrame:ToObjectSpace(cf)
			log("guard: crash boxes are degenerate from an older build; using the car body instead (respawn the car to restore them)")
			return { center = rel.Position, size = bsize }, "car body"
		end
	end
	return { center = (minV + maxV) * 0.5, size = size }, "crash boxes"
end

-- The guard resolves its own car through U.seatedCar, deliberately: a
-- CarBinder session additionally needs EngineStage, and an untuned car never
-- gets one, so routing the guard through a session left the panel reporting
-- crash protection ON while nothing was armed. See U.seatedCar.
function Guard.applyTo()
	Guard.release()
	Guard.boundCar = nil
	if not Guard.enabled then
		Guard.status = "off"
		return
	end
	local car, vseat = U.seatedCar()
	if not car then
		Guard.status = "waiting for a car"
		return
	end
	-- A failure below leaves boundCar nil, so the 2 Hz poll keeps retrying --
	-- correct, because crash boxes and TrafficFolder can both arrive late.
	-- Log the reason once per distinct reason, not twice a second.
	local function fail(why)
		Guard.status = why
		if Guard.lastFail ~= why then
			Guard.lastFail = why
			log(("guard: %s (%s)"):format(why, car.Name))
		end
	end

	local trafficFolder = workspace:FindFirstChild("TrafficFolder")
	if not trafficFolder then
		fail("no TrafficFolder in this place")
		return
	end

	local seat = car:FindFirstChild("DriveSeat") or vseat
	local cl, src = Guard.computeCrashLocal(car, seat)
	if not cl then
		fail(tostring(src))
		return
	end
	Guard.lastFail = nil
	Guard.crashLocal = cl
	Guard.boundCar = car
	Guard.saves, Guard.rescues = 0, 0
	local half = cl.size * 0.5
	local lastReport = 0

	-- Per frame, deliberately: the game's handler connected first and so runs
	-- first, leaving us exactly one frame of lead that a throttle would spend.
	-- Below the speed gate this returns immediately (potassium-dev S5.4).
	Guard.conns[#Guard.conns + 1] = RunService.Heartbeat:Connect(function()
		if not (seat and seat.Parent) then
			return
		end
		local seatCF = seat.CFrame
		local pos = seatCF.Position

		-- distance-based restore: a suppressed part is invisible to queries,
		-- so it is tracked by position, never by a timer that can expire
		-- while still in contact
		for part, orig in pairs(Guard.suppressed) do
			if not (typeof(part) == "Instance" and part.Parent) then
				Guard.suppressed[part] = nil
			elseif (part.Position - pos).Magnitude > G_CLEAR_DIST then
				pcall(function() part.CanQuery = orig end)
				Guard.suppressed[part] = nil
			end
		end

		local vel = seat.AssemblyLinearVelocity
		local speed = vel.Magnitude
		if speed * KMH_PER_STUD < G_MIN_KMH then
			Guard.lastMag, Guard.lastVel = speed, vel
			return
		end

		-- Lead on every axis from the seat-local velocity. Lateral closing is
		-- mostly our own steering, and v2 gave it no lead at all.
		local vLocal = seatCF:VectorToObjectSpace(vel)
		local leadX = math.clamp(math.abs(vLocal.X) * G_LEAD_TIME, 0, 40)
		local leadY = math.clamp(math.abs(vLocal.Y) * G_LEAD_TIME, 0, 20)
		local leadZ = math.clamp(math.abs(vLocal.Z) * G_LEAD_TIME, 0, 90)
		local hx = half.X + G_MARGIN + leadX
		local hy = half.Y + G_MARGIN + leadY
		local hz = half.Z + G_MARGIN + leadZ

		local trafficInCrashBox = false
		local nearD, nearName = math.huge, "none"
		for _, m in ipairs(trafficFolder:GetChildren()) do
			local hb = m:FindFirstChild("CoreHitbox")
			if hb and hb:IsA("BasePart") then
				local rel = seatCF:ToObjectSpace(hb.CFrame)
				local ext = aabbExtent(rel, hb.Size * 0.5)
				local d = rel.Position - cl.center
				local dx, dy, dz = math.abs(d.X), math.abs(d.Y), math.abs(d.Z)
				-- clearance to the REAL crash volume, for the miss diagnostic
				local clear = math.max(dx - half.X - ext.X, dy - half.Y - ext.Y, dz - half.Z - ext.Z)
				if clear < nearD then
					nearD, nearName = clear, m.Name
				end
				-- inside the guarded volume?
				if dx <= hx + ext.X and dy <= hy + ext.Y and dz <= hz + ext.Z then
					if Guard.suppressed[hb] == nil then
						Guard.suppressed[hb] = hb.CanQuery
						pcall(function() hb.CanQuery = false end)
						Guard.saves = Guard.saves + 1
						if Guard.saves == 1 or Guard.saves % 25 == 0 then
							log(("guard: suppressed #%d (%s) at %.0f MPH, clearance %.1f studs")
								:format(Guard.saves, m.Name, U.mph(speed), clear))
						end
					end
					-- inside the REAL crash volume, unexpanded? that is what
					-- distinguishes a traffic hit from a wall for the rescue
					if dx <= half.X + ext.X and dy <= half.Y + ext.Y and dz <= half.Z + ext.Z then
						trafficInCrashBox = true
					end
				end
			end
		end

		-- Last line: if a hit still landed, undo it. Requires BOTH the exact
		-- 0.15 multiply the game applies AND traffic genuinely inside the
		-- crash volume this frame, so a wall or hard braking cannot trigger it.
		local prevMag, prevVel = Guard.lastMag, Guard.lastVel
		if prevMag and prevVel and prevMag * KMH_PER_STUD >= G_MIN_KMH and speed > 0.01 then
			local ratio = speed / prevMag
			if trafficInCrashBox and math.abs(ratio - CRASH_FACTOR) <= CRASH_TOL then
				seat.AssemblyLinearVelocity = prevVel
				Guard.rescues = Guard.rescues + 1
				local now = os.clock()
				if now - lastReport > 2 then
					lastReport = now
					log(("guard: RESCUE #%d -- a hit got through at %.0f MPH (suppressed=%d, box %.1fx%.1f, lead x%.1f z%.1f)")
						:format(Guard.rescues, U.mph(prevMag), Guard.saves, cl.size.X, cl.size.Z, leadX, leadZ))
				end
				Guard.lastMag, Guard.lastVel = prevMag, prevVel
				Guard.status = ("armed -- %d avoided, %d recovered"):format(Guard.saves, Guard.rescues)
				return
			end
			-- A 0.15 velocity cut with NO traffic inside the crash volume is
			-- not something this guard covers -- it is a wall, another player,
			-- or a hit we never saw coming. Log it rather than stay silent,
			-- because "the guard does nothing" and "the crash was not traffic"
			-- look identical from the driver's seat.
			if not trafficInCrashBox and math.abs(ratio - CRASH_FACTOR) <= CRASH_TOL then
				local now = os.clock()
				if now - lastReport > 2 then
					lastReport = now
					log(("guard: MISS -- 0.15 cut at %.0f MPH with no traffic in the crash box (nearest %s, clearance %.1f studs, suppressed=%d)")
						:format(U.mph(prevMag), nearName,
							nearD == math.huge and -1 or nearD, Guard.saves))
				end
			end
		end
		Guard.lastMag, Guard.lastVel = speed, vel
		if Guard.saves > 0 or Guard.rescues > 0 then
			Guard.status = ("armed -- %d avoided, %d recovered"):format(Guard.saves, Guard.rescues)
		end
	end)

	Guard.status = ("armed -- 0 avoided, 0 recovered (%s, %.1f x %.1f studs)")
		:format(src, cl.size.X, cl.size.Z)
	log(("guard: %s on %s"):format(Guard.status, car.Name))
end

-- 2 Hz, its own loop. CarBinder's poll cannot serve this: Binder is declared
-- above Guard, so Binder.start's closure cannot see it, and more to the point
-- the guard has to arm on cars Binder rejects.
function Guard.poll()
	if not Guard.enabled then
		return
	end
	local car = U.seatedCar()
	if car ~= Guard.boundCar then
		Guard.applyTo()
	end
end

function Guard.set(on)
	Guard.enabled = on and true or false
	Guard.applyTo()
end

function Guard.shutdown()
	Guard.enabled = false
	Guard.release()
	Guard.status = "off"
end

--==========================================================================
-- CashMagnet -- expand the stock near-miss query parts, never move the car
--
-- TrafficClientHitbox queries TrafficHitboxLeft/Right at 30 Hz, then sends
-- only the resulting combo to TrafficSwerveEvent (0481.lua:87-145, 298-320).
-- Live execute_script probe, 2026-08-25: 30 stock swerves and +3963 cash in
-- 12 seconds; exact original sizes restored. This is session-only because the
-- game's downstream remote is server-visible. Green SelectionBoxes make the
-- active query volume impossible to miss.
--==========================================================================
local CashMagnet = {}
CashMagnet.enabled = false
CashMagnet.auto = false
CashMagnet.boundCar = nil
CashMagnet.held = {}
CashMagnet.status = "off"
CashMagnet.swerves = 0
CashMagnet.paid = 0
CashMagnet.pending = 0
CashMagnet.cashStart = nil
CashMagnet.cashValue = nil
CashMagnet.startedAt = nil
CashMagnet.lastPaidAt = 0
CashMagnet.lastSwerveAt = 0
CashMagnet.phase = "off"
CashMagnet.cooldownUntil = 0
CashMagnet.cooldownSec = 9.75
CashMagnet.cooldowns = 0
CashMagnet.TARGET_X = 500
CashMagnet.TARGET_Z = 1000

function CashMagnet.paintBox(box)
	local vis = math.clamp(tonumber(Config.data.cashPreview) or 0.15, 0, 1)
	box.Visible = vis > 0
	box.SurfaceTransparency = 1 - (0.3 * vis)
	box.LineThickness = 0.015 + (0.065 * vis)
	local dim = Color3.fromRGB(18, 70, 35)
	local bright = Color3.fromRGB(70, 255, 120)
	box.Color3 = dim:Lerp(bright, vis)
	box.SurfaceColor3 = box.Color3
end

function CashMagnet.setVisibility(v)
	Config.data.cashPreview = math.clamp(tonumber(v) or 0, 0, 1)
	for _, held in pairs(CashMagnet.held) do
		if held.box then CashMagnet.paintBox(held.box) end
	end
end

function CashMagnet.release()
	for part, held in pairs(CashMagnet.held) do
		if held.box then
			pcall(function() held.box:Destroy() end)
		end
		if part and part.Parent and part.Size == held.applied then
			pcall(function() part.Size = held.original end)
		end
		if part and part.Parent and part.CanTouch == false then
			pcall(function() part.CanTouch = held.canTouch end)
		end
		CashMagnet.held[part] = nil
	end
	CashMagnet.boundCar = nil
end

function CashMagnet.applyTo()
	CashMagnet.release()
	if not CashMagnet.enabled then
		CashMagnet.status = "off"
		return
	end
	local car = U.seatedCar()
	if not car then
		CashMagnet.status = "waiting for a car"
		return
	end
	for _, name in ipairs({ "TrafficHitboxLeft", "TrafficHitboxRight" }) do
		local part = car:FindFirstChild(name, true)
		if not (part and part:IsA("BasePart")) then
			CashMagnet.release()
			CashMagnet.status = "missing " .. name
			return
		end
		local applied = Vector3.new(
			math.max(part.Size.X, CashMagnet.TARGET_X),
			part.Size.Y,
			math.max(part.Size.Z, CashMagnet.TARGET_Z))
		local box = Instance.new("SelectionBox")
		box.Name = "GD2CashMagnet"
		box.Adornee = part
		CashMagnet.paintBox(box)
		box.Parent = part
		CashMagnet.held[part] = {
			original = part.Size,
			applied = applied,
			canTouch = part.CanTouch,
			box = box,
		}
		-- ModShopPad and DealershipPad use TouchInterest. These welded query
		-- parts remain valid GetPartsInPart volumes with touch disabled, but can
		-- no longer enter shop pads from hundreds of studs away.
		part.CanTouch = false
		part.Size = applied
	end
	CashMagnet.boundCar = car
	if CashMagnet.auto then
		if CashMagnet.phase ~= "probe" then CashMagnet.phase = "earning" end
		CashMagnet.status = CashMagnet.phase == "probe" and "probing refilled budget" or "earning -- budget watched"
	else
		CashMagnet.phase = "manual"
		CashMagnet.status = "manual -- unlimited combo range"
	end
	local cash = LP:FindFirstChild("leaderstats") and LP.leaderstats:FindFirstChild("Cash")
	if CashMagnet.cashStart == nil then CashMagnet.cashStart = cash and cash.Value or nil end
	CashMagnet.cashValue = cash and cash.Value or CashMagnet.cashValue
	log(("cash magnet: armed on %s (%dx%d sensors)")
		:format(car.Name, CashMagnet.TARGET_X, CashMagnet.TARGET_Z))
end

function CashMagnet.cooldown(reason)
	CashMagnet.cooldowns = CashMagnet.cooldowns + 1
	CashMagnet.phase = "cooldown"
	CashMagnet.cooldownUntil = os.clock() + CashMagnet.cooldownSec
	CashMagnet.pending = 0
	CashMagnet.release()
	CashMagnet.status = ("cooling %.1fs -- %s"):format(CashMagnet.cooldownSec, reason)
	log(("cash budget: cooling %.2fs after %s"):format(CashMagnet.cooldownSec, reason))
end

function CashMagnet.poll()
	if not CashMagnet.enabled then return end
	local now = os.clock()
	if CashMagnet.auto and CashMagnet.phase == "cooldown" then
		local left = CashMagnet.cooldownUntil - now
		if left > 0 then
			CashMagnet.status = ("budget cooling %.1fs"):format(left)
			return
		end
		CashMagnet.phase = "probe"
		CashMagnet.pending = 0
		CashMagnet.lastPaidAt = now
		CashMagnet.applyTo()
		CashMagnet.status = "probing refilled budget"
		return
	end
	local car = U.seatedCar()
	if car ~= CashMagnet.boundCar then
		CashMagnet.applyTo()
	end
	if CashMagnet.auto and CashMagnet.pending >= 3 and now - CashMagnet.lastPaidAt >= 1.1 then
		if CashMagnet.phase == "probe" then
			CashMagnet.cooldownSec = math.min(14, CashMagnet.cooldownSec + 1)
		end
		CashMagnet.cooldown(("%d unpaid swerves"):format(CashMagnet.pending))
	end
end

function CashMagnet.set(on)
	CashMagnet.enabled = on and true or false
	if CashMagnet.enabled then
		CashMagnet.swerves = 0
		CashMagnet.paid = 0
		CashMagnet.pending = 0
		CashMagnet.cooldowns = 0
		CashMagnet.cashStart = nil
		CashMagnet.startedAt = os.clock()
		CashMagnet.lastPaidAt = os.clock()
		CashMagnet.phase = CashMagnet.auto and "earning" or "manual"
	end
	CashMagnet.applyTo()
	if not CashMagnet.enabled then
		CashMagnet.phase = "off"
		log("cash magnet: off; original sensors restored")
	end
end

function CashMagnet.setAuto(on)
	CashMagnet.auto = on and true or false
	CashMagnet.pending = 0
	CashMagnet.cooldownUntil = 0
	if CashMagnet.enabled then
		CashMagnet.phase = CashMagnet.auto and "earning" or "manual"
		CashMagnet.lastPaidAt = os.clock()
		CashMagnet.applyTo()
	end
	log("cash budget: auto " .. (CashMagnet.auto and "on" or "off"))
end

function CashMagnet.onSwerve()
	if not CashMagnet.enabled then return end
	CashMagnet.swerves = CashMagnet.swerves + 1
	CashMagnet.lastSwerveAt = os.clock()
	if CashMagnet.auto and CashMagnet.phase ~= "cooldown" then
		CashMagnet.pending = CashMagnet.pending + 1
	end
end

function CashMagnet.onCash(value)
	value = tonumber(value)
	if not value then return end
	local old = CashMagnet.cashValue
	CashMagnet.cashValue = value
	if not (CashMagnet.enabled and old) then return end
	local delta = value - old
	-- Passive driving income changes by 1-7. Every observed swerve award was
	-- 20+, usually 140-152 (2026-08-25 clean-budget trace).
	if delta >= 20 and (CashMagnet.pending > 0 or os.clock() - CashMagnet.lastSwerveAt <= 0.5) then
		CashMagnet.paid = CashMagnet.paid + 1
		if CashMagnet.pending > 0 then CashMagnet.pending = CashMagnet.pending - 1 end
		CashMagnet.lastPaidAt = os.clock()
		if CashMagnet.phase == "probe" then
			CashMagnet.cooldownSec = math.max(8.5, CashMagnet.cooldownSec - 0.25)
			CashMagnet.phase = "earning"
			CashMagnet.status = "earning -- budget refilled"
			log(("cash budget: refill confirmed; next probe %.2fs"):format(CashMagnet.cooldownSec))
		end
	end
end

function CashMagnet.shutdown()
	CashMagnet.enabled = false
	CashMagnet.auto = false
	CashMagnet.release()
	CashMagnet.status = "off"
end

--==========================================================================
-- StreamAhead -- keep the road in front of us loaded
--
-- Workspace.StreamingEnabled = true, StreamingMinRadius 512,
-- FallenPartsDestroyHeight = -2000 (properties.txt), and no script in this
-- game ever calls RequestStreamingAroundPosition. Above ~200 MPH the car
-- crosses the guaranteed radius in under a second and arrives on road that has
-- not streamed in: the wheels find no ground and every part that passes -2000
-- studs is destroyed. The game's 400 km/h AeroDrag brake (0483.lua:58-64) is
-- what normally prevents that and the fast presets disable it. Full write-up:
-- GHOST_DRIVER.md, "Falling out of the map at a highway race start".
--
-- Player:RequestStreamingAroundPosition is the first-party client API for
-- exactly this case. It asks for the same radii around a point we are about
-- to reach instead of the point we are at. Rung 1 of the ladder: no game
-- remote, no game code touched, nothing to restore on unload -- the client
-- already requests streaming implicitly every time it moves.
--==========================================================================
local Stream = {}
Stream.last = 0
Stream.requests = 0
Stream.lastLog = 0
Stream.status = "idle"

Stream.MIN_STUDS = 150     -- ~52 MPH; below this the stock radius is plenty
Stream.LEAD_TIME = 2.0     -- seconds of road to ask for ahead of the car
Stream.MAX_LEAD = 1200     -- studs; beyond this the request is off the map
Stream.RATE = 0.25         -- 4 Hz

function Stream.step()
	if Config.data.streamAhead == false then
		Stream.status = "off"
		return
	end
	local now = os.clock()
	if now - Stream.last < Stream.RATE then
		return
	end
	Stream.last = now
	local car, vseat = U.seatedCar()
	if not car then
		Stream.status = "idle (no car)"
		return
	end
	local seat = car:FindFirstChild("DriveSeat") or vseat
	if not (seat and seat.Parent) then
		return
	end
	local vel = seat.AssemblyLinearVelocity
	local speed = vel.Magnitude
	if speed < Stream.MIN_STUDS then
		Stream.status = ("idle (%.0f MPH)"):format(U.mph(speed))
		return
	end
	local lead = math.min(speed * Stream.LEAD_TIME, Stream.MAX_LEAD)
	local ahead = seat.Position + vel.Unit * lead
	local ok = pcall(function()
		LP:RequestStreamingAroundPosition(ahead)
	end)
	if not ok then
		Stream.status = "unavailable on this client"
		Config.data.streamAhead = false
		log("stream: RequestStreamingAroundPosition failed; prefetch disabled")
		return
	end
	Stream.requests = Stream.requests + 1
	Stream.status = ("prefetching %.0f studs ahead at %.0f MPH"):format(lead, U.mph(speed))
	if now - Stream.lastLog > 30 then
		Stream.lastLog = now
		log(("stream: %d prefetch requests, %s"):format(Stream.requests, Stream.status))
	end
end

--==========================================================================
-- AudioController
--
-- Engine audio is NOT mixed per-sound: EngineAudio.ApplyTelemetry rewrites
-- every layer Volume every frame (0207.lua:184-254), so any per-sound write
-- would be overwritten and any base-tracking would read our own value back --
-- exactly the feedback bug in the old gd.lua. Instead the car's sound config
-- table is edited: DriverAudio reads config.MasterVolume every frame
-- (0205.lua:459) and EngineAudio holds a direct reference to each layer's
-- config subtable as .Data (0207.lua:113-121), so editing the required table
-- is the supported single-writer path.
--
-- Redline scaling: layer windows and PitchRef are authored for the stock rev
-- range (0204.lua:9-57 tops out at 8200 for a 8000 redline). Every window and
-- pitch reference is scaled by ONE factor k = newRedline / stockRedline, so
-- the engine keeps its authored shape at any redline instead of pinning
-- PlaybackSpeed against the 2.5 clamp (0207.lua:212).
--
-- Everything else is an ephemeral multiplier over the game's latest raw
-- write, never a persisted scaled value.
--==========================================================================
Audio = {}
Audio.bound = nil
Audio.cfgTable = nil
Audio.rpmK = 1
Audio.tracked = {}   -- Sound -> { cat, base, expected, conn }
Audio.levels = nil   -- points at Config.data.audio
Audio.AMBIENCE = { Rain = true, Storm = true, DayAmbience = true, NightAmbience = true, RainInterior = true }
Audio.danger = nil
Audio.carSounds = {}
Audio.carConn = nil
Audio.otherGroup = nil
Audio.otherSounds = {} -- Sound -> original SoundGroup

-- DriverAudio resolves its config from ReplicatedStorage.AC6Shared.CarConfigs
-- by the car's AC6SoundConfig attribute, and separately requires the
-- PreviewSoundConfig one when an engine-swap preview is active; ApplyTelemetry
-- is then handed whichever of the two is live (0205.lua:55-62, 200-205, 507).
-- CarConfigsInterior is a DIFFERENT folder used by InteriorAudio, so the
-- lookup is exact, never a recursive name search.
local function cfgTables(car)
	local shared = ReplicatedStorage:FindFirstChild("AC6Shared")
	local folder = shared and shared:FindFirstChild("CarConfigs")
	if not folder then
		return {}
	end
	local out, seen = {}, {}
	for _, attr in ipairs({ "AC6SoundConfig", "PreviewSoundConfig" }) do
		local name = car:GetAttribute(attr)
		if type(name) == "string" and name ~= "" and not seen[name] then
			seen[name] = true
			local mod = folder:FindFirstChild(name)
			if mod and mod:IsA("ModuleScript") then
				local ok, t = pcall(require, mod)
				if ok and type(t) == "table" then
					out[#out + 1] = { name = name, t = t }
				end
			end
		end
	end
	return out
end

function Audio.unbindCar()
	local bound = Audio.bound
	Audio.bound = nil
	Audio.cfgTable = nil
	if Audio.carConn then
		pcall(function() Audio.carConn:Disconnect() end)
		Audio.carConn = nil
	end
	for sound in pairs(Audio.carSounds) do
		Audio.carSounds[sound] = nil
		Audio.untrack(sound)
	end
	for _, b in ipairs(bound or {}) do
		pcall(function()
			b.t.MasterVolume = b.saved.MasterVolume
			for name, orig in pairs(b.saved.layers) do
				local layer = b.t[name]
				if type(layer) == "table" then
					layer.PitchRef = orig.PitchRef
					layer.MinRPM = orig.MinRPM
					layer.PeakRPM = orig.PeakRPM
					layer.MaxRPM = orig.MaxRPM
				end
			end
		end)
	end
	Audio.rpmK = 1
	log("audio: car sound config restored")
end

local function configDrivenCarSound(sound, car)
	local p = sound.Parent
	while p and p ~= car do
		if p.Name == "AC6_EngineSounds" or p.Name == "AC6_DriverLocalSounds" then
			return true
		end
		if p.Name == "Drag" and p.Parent and p.Parent.Name == "Body" then
			return true
		end
		p = p.Parent
	end
	return false
end

local function carSoundCategory(sound, car)
	local parts = { sound.Name }
	local p = sound.Parent
	while p and p ~= car do
		parts[#parts + 1] = p.Name
		p = p.Parent
	end
	local hay = table.concat(parts, " "):lower()
	if hay:find("backfire", 1, true) or hay:find("exhaust", 1, true)
		or hay:find("bfx_", 1, true) then
		return "vehicleExhaust"
	elseif hay:find("tire", 1, true) or hay:find("tyre", 1, true)
		or hay:find("skid", 1, true) or hay:find("squeal", 1, true) then
		return "vehicleTires"
	elseif hay:find("brake", 1, true) then
		return "vehicleBrakes"
	elseif hay:find("horn", 1, true) or hay:find("siren", 1, true) then
		return "vehicleHorn"
	end
	return "vehicleAccessories"
end

function Audio.bindCarSounds(car)
	local function adopt(d)
		if d:IsA("Sound") and not configDrivenCarSound(d, car) then
			Audio.releaseOtherSound(d)
			Audio.carSounds[d] = true
			Audio.track(carSoundCategory(d, car), d)
		end
	end
	for _, d in ipairs(car:GetDescendants()) do adopt(d) end
	Audio.carConn = car.DescendantAdded:Connect(adopt)
	local count = 0
	for _ in pairs(Audio.carSounds) do count = count + 1 end
	log(("audio: vehicle mixer adopted %d discrete car sound(s)"):format(count))
end

function Audio.bindCar(sess)
	Audio.unbindCar()
	Audio.bindCarSounds(sess.car)
	local found = cfgTables(sess.car)
	if #found == 0 then
		Audio.cfgErr = "sound config for this car not found in AC6Shared.CarConfigs"
		log("audio: " .. Audio.cfgErr)
		return false
	end
	local bound = {}
	for _, f in ipairs(found) do
		local saved = { MasterVolume = rawget(f.t, "MasterVolume"), layers = {} }
		-- Every RPM-referenced entry, discovered rather than listed. The live
		-- sound set on a Shelly LZ1 carries RelA/RelB/RevA/RevB/Startup on top
		-- of the seven documented layers, and a fixed list silently skipped
		-- them, leaving part of the engine unscaled at a raised redline.
		for name, layer in pairs(f.t) do
			if type(layer) == "table" and (layer.PitchRef or layer.MinRPM) then
				saved.layers[name] = {
					PitchRef = layer.PitchRef,
					MinRPM = layer.MinRPM,
					PeakRPM = layer.PeakRPM,
					MaxRPM = layer.MaxRPM,
				}
			end
		end
		bound[#bound + 1] = { name = f.name, t = f.t, saved = saved }
	end
	Audio.bound = bound
	Audio.cfgTable = bound[1].t
	Audio.cfgErr = nil
	-- start from the authored range; the tune verify sets the real factor
	Audio.rpmK = 1
	Audio.applyEngine()
	local names = {}
	for _, b in ipairs(bound) do
		names[#names + 1] = b.name
	end
	log("audio: bound sound config " .. table.concat(names, ", "))
	return true
end

function Audio.applyEngine()
	local lvl = U.clamp(Audio.levels.engine or 1, 0, 1)
		* U.clamp(Audio.levels.vehicleEngine or 1, 0, 1)
	for _, b in ipairs(Audio.bound or {}) do
		local base = b.saved.MasterVolume or 1
		b.t.MasterVolume = base * lvl
	end
	-- the wind and body-drag sounds belong to the vehicle, not to ambience
	Aero.windLevel = lvl
end

-- ONE documented factor over the authored windows and pitch references, so a
-- longer rev range keeps the engine's authored shape instead of pinning
-- PlaybackSpeed against the 2.5 clamp (0207.lua:212).
function Audio.applyRpmScale(k)
	k = tonumber(k) or 1
	if k <= 0 then
		k = 1
	end
	Audio.rpmK = k
	for _, b in ipairs(Audio.bound or {}) do
		for name, orig in pairs(b.saved.layers) do
			local layer = b.t[name]
			if type(layer) == "table" then
				if orig.PitchRef then layer.PitchRef = orig.PitchRef * k end
				if orig.MinRPM then layer.MinRPM = orig.MinRPM * k end
				if orig.PeakRPM then layer.PeakRPM = orig.PeakRPM * k end
				if orig.MaxRPM then layer.MaxRPM = orig.MaxRPM * k end
			end
		end
	end
	log(("audio: rev-range factor %.2f applied to layer windows"):format(k))
end

-- --- per-sound mixer for the categories the game writes discretely ---

local function mult(cat)
	local level = U.clamp(Audio.levels[cat] or 1, 0, 1)
	if cat:sub(1, 7) == "vehicle" then
		level = level * U.clamp(Audio.levels.engine or 1, 0, 1)
	end
	return level
end

function Audio.ensureOtherGroup()
	if Audio.otherGroup and Audio.otherGroup.Parent then return Audio.otherGroup end
	local group = Instance.new("SoundGroup")
	group.Name = "GD2OtherCars"
	group.Volume = mult("otherCars")
	group.Parent = SoundService
	Audio.otherGroup = group
	return group
end

function Audio.trackOtherSound(sound)
	if Audio.otherSounds[sound] ~= nil or not sound.Parent then return end
	Audio.otherSounds[sound] = sound.SoundGroup or false
	sound.SoundGroup = Audio.ensureOtherGroup()
end

function Audio.releaseOtherSound(sound, gone)
	local original = Audio.otherSounds[sound]
	if original == nil then return end
	Audio.otherSounds[sound] = nil
	if not gone and sound.Parent and sound.SoundGroup == Audio.otherGroup then
		sound.SoundGroup = original or nil
	end
end

-- A base of 0 is unrecoverable by a multiplier: 0 * anything is 0, and base
-- only updates when the GAME writes a new volume. That is fine for sounds the
-- game authors every time it plays them (impact rewrites Volume before each
-- Play, 0488.lua:66; menu and showroom music are tweened), but the near-miss
-- whoosh is a persistent instance whose Volume the game NEVER writes --
-- 0481.lua:141-142 sets PlaybackSpeed and calls Play, nothing else. The old
-- gd.lua left it at 0, so it stayed 0 forever and the slider looked dead.
-- Only categories listed here get a floor, so a legitimately silent sound
-- (rain when it is not raining) is never forced audible.
Audio.BASE_FLOOR = { whoosh = 1 }

local function push(rec)
	local base = rec.base
	if base <= 0 and Audio.BASE_FLOOR[rec.cat] then
		base = Audio.BASE_FLOOR[rec.cat]
	end
	local want = base * mult(rec.cat)
	rec.expected = want
	pcall(function() rec.sound.Volume = want end)
end

function Audio.track(cat, sound)
	if Audio.tracked[sound] then
		return
	end
	local rec = { cat = cat, sound = sound, base = sound.Volume, expected = nil }
	Audio.tracked[sound] = rec
	-- Base is the game's latest INTENDED volume. A change we did not make is
	-- a new intent; a change equal to what we wrote is our own echo.
	rec.conn = sound:GetPropertyChangedSignal("Volume"):Connect(function()
		local r = Audio.tracked[sound]
		if not r then
			return
		end
		if r.expected and math.abs(sound.Volume - r.expected) < 1e-4 then
			return
		end
		r.base = sound.Volume
		push(r)
	end)
	rec.gone = sound.AncestryChanged:Connect(function(_, parent)
		if not parent then
			Audio.untrack(sound, true)
		end
	end)
	push(rec)
end

function Audio.untrack(sound, gone)
	local rec = Audio.tracked[sound]
	if not rec then
		return
	end
	Audio.tracked[sound] = nil
	-- World sounds hold a slot in the WORLD_CAP budget. Without giving it
	-- back, a long session fills the cap with destroyed sounds and the mixer
	-- silently stops adopting new ones -- the gas station radio you drive up
	-- to an hour in never gets a level.
	if rec.world then
		Audio.worldCount = math.max(Audio.worldCount - 1, 0)
	end
	pcall(function() rec.conn:Disconnect() end)
	pcall(function() rec.gone:Disconnect() end)
	if not gone and sound.Parent then
		pcall(function() sound.Volume = rec.base end)
	end
end

function Audio.applyCat(cat)
	if cat == "otherCars" then
		Audio.ensureOtherGroup().Volume = mult(cat)
		return
	end
	for _, rec in pairs(Audio.tracked) do
		if rec.cat == cat or (cat == "engine" and rec.cat:sub(1, 7) == "vehicle") then
			push(rec)
		end
	end
	if cat == "engine" or cat == "vehicleEngine" then
		Audio.applyEngine()
	end
end

-- BuildComboUI creates a looped DangerHeartbeat and normally stops it when
-- AdrenalineFill leaves the danger range (0484.lua:484-548). If that update
-- branch is skipped, the loop survives after the bar or whole combo UI ends.
-- Mirror the game's exact danger test and stop only the stale local sound.
function Audio.bindDangerHeartbeat()
	local pg = LP:FindFirstChildOfClass("PlayerGui")
	local gui = pg and pg:FindFirstChild("ComboUI")
	local box = gui and gui:FindFirstChild("ComboContainer")
	local sound = box and box:FindFirstChild("DangerHeartbeat")
	local bg = box and box:FindFirstChild("AdrenalineBg")
	local fill = bg and bg:FindFirstChild("AdrenalineFill")
	if not (sound and sound:IsA("Sound") and fill and fill:IsA("GuiObject")) then
		return
	end
	if Audio.danger and Audio.danger.sound == sound then
		return
	end
	if Audio.danger then
		for _, conn in ipairs(Audio.danger.conns) do pcall(function() conn:Disconnect() end) end
	end
	local rec = { sound = sound, conns = {} }
	Audio.danger = rec
	local function stopStale()
		local level = fill.Size.X.Scale
		local active = gui.Enabled and box.Visible and level > 0 and level <= 0.2
		if not active and sound.IsPlaying then
			sound:Stop()
			log(("audio: stopped stale swerve heartbeat (bar %.3f)"):format(level))
		end
	end
	for _, signal in ipairs({
		fill:GetPropertyChangedSignal("Size"),
		box:GetPropertyChangedSignal("Visible"),
		gui:GetPropertyChangedSignal("Enabled"),
		sound:GetPropertyChangedSignal("Playing"),
	}) do
		rec.conns[#rec.conns + 1] = signal:Connect(stopStale)
	end
	rec.conns[#rec.conns + 1] = sound.AncestryChanged:Connect(function(_, parent)
		if not parent and Audio.danger == rec then Audio.danger = nil end
	end)
	stopStale()
	log("audio: swerve heartbeat fail-safe bound")
end

function Audio.setLevel(cat, v)
	Audio.levels[cat] = U.clamp(v, 0, 1)
	Audio.applyCat(cat)
	Config.save()
end

-- World-placed sounds: the gas station music, tunnel and area beds, anything
-- a builder parented to a part in the map. These are invisible to the fixed
-- roots below, which is why the music slider left them untouched.
--
-- Scanned ONCE at startup, then kept current by DescendantAdded, so there is
-- no repeating workspace-wide walk. Cars, characters, traffic and the AC6
-- audio containers are excluded because they are owned by other controllers.
Audio.MUSIC_TOKENS = { "music", "radio", "jukebox", "song", "station", "speaker", "boombox", "stereo" }
Audio.WORLD_CAP = 150
Audio.worldCount = 0

local function ownedElsewhere(sound)
	local p = sound.Parent
	while p and p ~= workspace do
		local n = p.Name
		if n == "TrafficFolder" or n == "ClientImpactFX_Pool" or n:sub(1, 4) == "AC6_" then
			return true
		end
		if p:FindFirstChild("DriveSeat") or p:FindFirstChildOfClass("Humanoid") then
			return true
		end
		p = p.Parent
	end
	return false
end

function Audio.trackWorldSound(s)
	if Audio.worldCount >= Audio.WORLD_CAP or Audio.tracked[s] then
		return
	end
	if not (s:IsA("Sound") and s:IsDescendantOf(workspace)) then
		return
	end
	if ownedElsewhere(s) then
		return
	end
	local hay = (s.Name .. " " .. (s.Parent and s.Parent.Name or "")):lower()
	local cat = "ambience"
	for _, t in ipairs(Audio.MUSIC_TOKENS) do
		if hay:find(t, 1, true) then
			cat = "music"
			break
		end
	end
	Audio.worldCount = Audio.worldCount + 1
	Audio.track(cat, s)
	local rec = Audio.tracked[s]
	if rec then
		rec.world = true -- so untrack can return the slot to WORLD_CAP
	end
	if Audio.worldCount <= 40 then
		log(("audio: world sound -> %s   %s"):format(cat, s:GetFullName()))
	end
end

function Audio.scanWorld()
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("Sound") then
			U.guard("audio.world", Audio.trackWorldSound, d)
		end
	end
	log(("audio: world scan done, %d sound(s) adopted"):format(Audio.worldCount))
	Audio.worldConn = workspace.DescendantAdded:Connect(function(d)
		if d:IsA("Sound") then
			task.defer(function()
				U.guard("audio.worldAdded", Audio.trackWorldSound, d)
			end)
		end
	end)
end

-- Bounded discovery. Fixed roots only, never a workspace-wide descendant
-- walk, and only top-level workspace children for other players' radios.
function Audio.discover()
	local pg = LP:FindFirstChildOfClass("PlayerGui")
	Audio.bindDangerHeartbeat()
	local menu = pg and pg:FindFirstChild("MainGameMenu")
	if menu then
		for _, n in ipairs({ "MenuMusic" }) do
			local s = menu:FindFirstChild(n)
			if s and s:IsA("Sound") then Audio.track("music", s) end
		end
		for _, n in ipairs({ "HoverSound", "ClickSound" }) do
			local s = menu:FindFirstChild(n)
			if s and s:IsA("Sound") then Audio.track("ui", s) end
		end
	end
	for _, s in ipairs(SoundService:GetChildren()) do
		if s:IsA("Sound") then
			if s.Name == "ShowroomMusic" then
				Audio.track("music", s)
			elseif Audio.AMBIENCE[s.Name] then
				Audio.track("ambience", s)
			elseif s.Name == "PedalSound_Throttle" then
				Audio.track("ui", s)
			end
		end
	end
	local ps = LP:FindFirstChild("PlayerScripts")
	local whoosh = ps and ps:FindFirstChild("WhooshSound")
	if whoosh and whoosh:IsA("Sound") then
		Audio.track("whoosh", whoosh)
	end
	local pool = workspace:FindFirstChild("ClientImpactFX_Pool")
	if pool then
		local s = pool:FindFirstChildOfClass("Sound")
		if s then Audio.track("impact", s) end
	end
	-- radios: NewRadioController parents the local sound to the car's Body
	-- (0502.lua:518-520); other players' are replicated GlobalCarRadio sounds.
	local sess = Binder.session
	local myCar = (sess and sess.car) or U.seatedCar()
	for _, model in ipairs(workspace:GetChildren()) do
		if model:IsA("Model") then
			local body = model:FindFirstChild("Body")
			local driveSeat = model:FindFirstChild("DriveSeat", true)
			if body and driveSeat then
				if model ~= myCar then
					for _, d in ipairs(model:GetDescendants()) do
						local isRadio = d:IsA("Sound") and d.Parent == body
							and (d.Name == "GlobalCarRadio" or d.Name == "Sound")
						if d:IsA("Sound") and not isRadio then
							Audio.trackOtherSound(d)
						end
					end
				else
					for _, d in ipairs(model:GetDescendants()) do
						if d:IsA("Sound") then Audio.releaseOtherSound(d) end
					end
				end
				for _, s in ipairs(body:GetChildren()) do
					if s:IsA("Sound") and (s.Name == "GlobalCarRadio" or s.Name == "Sound") then
						Audio.track(model == myCar and "music" or "radios", s)
					end
				end
			end
		end
	end

	-- Change-only census. A category that finds nothing is the difference
	-- between "the slider does nothing" and "there was never a sound to move",
	-- and without this line the mixer fails completely silently.
	local tally, total = {}, 0
	for _, rec in pairs(Audio.tracked) do
		tally[rec.cat] = (tally[rec.cat] or 0) + 1
		total = total + 1
	end
	local otherCount = 0
	for sound in pairs(Audio.otherSounds) do
		if sound.Parent then
			otherCount = otherCount + 1
		else
			Audio.releaseOtherSound(sound, true)
		end
	end
	tally.otherCars = otherCount
	total = total + otherCount
	local parts = {}
	for _, cat in ipairs({ "music", "whoosh", "impact", "ui", "ambience", "otherCars", "radios" }) do
		parts[#parts + 1] = ("%s=%d"):format(cat, tally[cat] or 0)
	end
	local census = table.concat(parts, " ")
	if census ~= Audio.lastCensus then
		Audio.lastCensus = census
		Audio.settled = 0
		log(("audio: tracking %d sounds  %s  | engine cfg %s"):format(
			total, census, Audio.bound and "bound" or (Audio.cfgErr or "not bound (no car)")))
	else
		Audio.settled = (Audio.settled or 0) + 1
	end
end

-- Every pass walks PlayerGui, SoundService, PlayerScripts, the impact pool and
-- every top-level workspace model. That is the right sweep while the place is
-- still loading in and cars, radios and menus keep appearing, and pure waste
-- once the census stops moving -- which it does within a few passes and then
-- stays put for the rest of the session. Back off to 10 s once six
-- consecutive passes find nothing new, and go straight back to 2 s the moment
-- one does. New world sounds are never missed either way: DescendantAdded
-- already adopts those the instant they appear (Audio.scanWorld).
Audio.SETTLED_PASSES = 6
Audio.nextAt = 0

function Audio.tick()
	local now = os.clock()
	if now < Audio.nextAt then
		return
	end
	Audio.discover()
	local slow = (Audio.settled or 0) >= Audio.SETTLED_PASSES
	Audio.nextAt = now + (slow and 10 or 2)
end

function Audio.start()
	Audio.levels = Config.data.audio
	task.spawn(function()
		U.guard("audio.scanWorld", Audio.scanWorld)
	end)
	-- First census now, then off the one tick in main() on Audio.tick's own
	-- 2 s / 10 s schedule.
	U.guard("audio.discover", Audio.tick)
end

function Audio.stop()
	if Audio.worldConn then
		pcall(function() Audio.worldConn:Disconnect() end)
		Audio.worldConn = nil
	end
	if Audio.danger then
		for _, conn in ipairs(Audio.danger.conns) do pcall(function() conn:Disconnect() end) end
		Audio.danger = nil
	end
	for sound in pairs(Audio.tracked) do
		Audio.untrack(sound)
	end
	for sound in pairs(Audio.otherSounds) do Audio.releaseOtherSound(sound) end
	if Audio.otherGroup then pcall(function() Audio.otherGroup:Destroy() end) end
	Audio.otherGroup = nil
	Audio.unbindCar()
end

--==========================================================================
-- ESP -- players only, name and distance
--==========================================================================
local ESP = {}
ESP.tags = {}
ESP.enabled = false
ESP.host = nil

-- A BillboardGui is itself a LayerCollector, so it can NOT live inside a
-- ScreenGui -- and on Potassium gethui() returns one (the log shows
-- "gethui -> RobloxGui (ScreenGui)"). Parenting straight to PlayerGui is the
-- one placement that is unambiguously rendered, so that is what we use; the
-- tags are tracked in ESP.tags for teardown instead of by a host folder.
local function espHost()
	if ESP.host and ESP.host.Parent then
		return ESP.host
	end
	local pg = LP:FindFirstChildOfClass("PlayerGui")
	if not pg then
		log("esp: no PlayerGui; cannot draw")
		return nil
	end
	ESP.host = pg
	log("esp: host = " .. pg:GetFullName())
	return pg
end

local function clearTag(plr)
	local t = ESP.tags[plr]
	if t then
		ESP.tags[plr] = nil
		pcall(function() t:Destroy() end)
	end
end

function ESP.clearAll()
	for plr in pairs(ESP.tags) do
		clearTag(plr)
	end
	-- ESP.host is PlayerGui itself now; never destroy it, just forget it
	ESP.host = nil
end

local function makeTag(plr, part)
	local host = espHost()
	if not host then
		return nil
	end
	local b = Instance.new("BillboardGui")
	b.Name = "t" .. tostring(math.random(100000, 999999))
	b.Adornee = part
	b.AlwaysOnTop = true
	-- billboard grows with the text so a long name plus distance never clips
	b.Size = UDim2.fromOffset(300, 52)
	b.StudsOffset = Vector3.new(0, 3.6, 0)
	-- unlimited range: BillboardGui culls at MaxDistance, and math.huge is the
	-- property's own "never cull" value. Not stored in config because
	-- JSONEncode cannot serialise a non-finite number.
	b.MaxDistance = math.huge
	local lbl = Instance.new("TextLabel")
	lbl.Name = "L"
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.Font = Enum.Font.GothamMedium
	lbl.TextSize = 21
	lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
	-- heavier stroke so the bigger text still reads against a bright road
	lbl.TextStrokeTransparency = 0.25
	lbl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	lbl.Text = plr.Name
	lbl.Parent = b
	b.Parent = host
	ESP.tags[plr] = b
	return b
end

function ESP.step()
	if not ESP.enabled then
		return
	end
	local cfg = Config.data.esp
	local myChar = LP.Character
	local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LP then
			local char = plr.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			local tag = ESP.tags[plr]
			if not root then
				if tag then clearTag(plr) end
			else
				-- The host is PlayerGui, which the game clears on respawn. A
				-- destroyed tag keeps its own properties but loses its
				-- children, so "tag.L" then throws every frame -- that was
				-- hundreds of ERR lines per minute in gd2.log. Test the
				-- parent and the label, and rebuild instead of erroring.
				local lbl = tag and tag:FindFirstChild("L")
				if tag and (not tag.Parent or not lbl or tag.Adornee ~= root) then
					clearTag(plr)
					tag, lbl = nil, nil
				end
				if not tag then
					tag = makeTag(plr, root)
					lbl = tag and tag:FindFirstChild("L")
				end
				if lbl then
					local txt = cfg.name and plr.Name or ""
					if cfg.dist and myRoot then
						local d = math.floor((root.Position - myRoot.Position).Magnitude)
						txt = (txt ~= "" and (txt .. "  ") or "") .. d .. "m"
					end
					lbl.Text = txt
				end
			end
		end
	end
	for plr in pairs(ESP.tags) do
		if plr.Parent ~= Players then
			clearTag(plr)
		end
	end
end

function ESP.set(on)
	ESP.enabled = on and true or false
	Config.data.esp.enabled = ESP.enabled
	Config.save()
	if not ESP.enabled then
		ESP.clearAll()
		log("esp: off")
		return
	end
	-- say immediately whether there is anything to draw, so "ESP isn't
	-- working" is answerable from the log instead of by guessing
	local others, withRoot = 0, 0
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LP then
			others = others + 1
			local c = plr.Character
			if c and c:FindFirstChild("HumanoidRootPart") then
				withRoot = withRoot + 1
			end
		end
	end
	log(("esp: on -- %d other player(s), %d with a HumanoidRootPart"):format(others, withRoot))
end

--==========================================================================
-- ClickTeleport -- RightAlt + left-click while seated
--
-- Mirrors TutorialController's own seated-car path (0126.lua:489-542): zero
-- the assembly, preserve its bounding-box offset, anchor one assembly part,
-- PivotTo, then release. The click ray ignores our character/car and respects
-- CanCollide, so invisible trigger volumes cannot become destinations.
--==========================================================================
ClickTP = {}
ClickTP.busy = false

function ClickTP.go()
	if ClickTP.busy or Config.data.clickTeleport ~= true then return end
	local s = Binder.session
	local car = (s and s.car) or U.seatedCar()
	local char = LP.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not (car and hum and hum.SeatPart and hum.SeatPart:IsDescendantOf(car)) then
		log("clicktp: blocked -- sit in your car first")
		return
	end
	local cam = workspace.CurrentCamera
	if not cam then
		log("clicktp: blocked -- no camera")
		return
	end
	local mouse = UserInputService:GetMouseLocation()
	local ray = cam:ViewportPointToRay(mouse.X, mouse.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { car, char }
	params.IgnoreWater = false
	params.RespectCanCollide = true
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 10000, params)
	if not hit then
		log("clicktp: blocked -- click did not hit collidable world geometry")
		return
	end
	if hit.Normal.Y < 0.5 then
		log("clicktp: blocked -- click a road or upward-facing surface")
		return
	end

	ClickTP.busy = true
	pcall(function() LP:RequestStreamAroundAsync(hit.Position, 10) end)
	if not (GD.running and car.Parent and hum.SeatPart and hum.SeatPart:IsDescendantOf(car)) then
		ClickTP.busy = false
		log("clicktp: cancelled -- car changed while streaming")
		return
	end
	for _, d in ipairs(car:GetDescendants()) do
		if d:IsA("BasePart") then
			d.AssemblyLinearVelocity = Vector3.zero
			d.AssemblyAngularVelocity = Vector3.zero
		end
	end
	local boxCF, boxSize = car:GetBoundingBox()
	local pivot = car:GetPivot()
	local pivotToBox = pivot:ToObjectSpace(boxCF)
	local _, yaw = pivot:ToOrientation()
	local target = CFrame.new(hit.Position.X, hit.Position.Y + boxSize.Y / 2 + 0.5, hit.Position.Z)
		* CFrame.Angles(0, yaw, 0)
	local root = car.PrimaryPart or hum.SeatPart
	local wasAnchored = root.Anchored
	root.Anchored = true
	car:PivotTo(target * pivotToBox:Inverse())
	task.delay(0.5, function()
		if root and root.Parent and root.Anchored then root.Anchored = wasAnchored end
		ClickTP.busy = false
	end)
	log(("clicktp: moved %s to %.1f, %.1f, %.1f"):format(
		car.Name, hit.Position.X, hit.Position.Y, hit.Position.Z))
end

-- UI -- black surface, white text, white neon accents, sparse star detail.
-- Every control states what improves, what gets worse, and what changed live.
--==========================================================================
local UI = {}
UI.conns = {}
UI.tabs = {}
UI.order = { "SPEED", "HANDLING", "STANCE", "EXHAUST", "AUDIO", "ESP", "CONFIG" }
UI.live = {}      -- functions run at 8 Hz to refresh readouts
UI.prof = nil     -- working copy of the active car profile
UI.bindCapture = false   -- true while the nitrous bind button is listening
UI.gui = nil

local COL = {
	bg = Color3.fromRGB(7, 7, 9),
	panel = Color3.fromRGB(13, 13, 16),
	row = Color3.fromRGB(18, 18, 22),
	line = Color3.fromRGB(42, 42, 50),
	text = Color3.fromRGB(240, 240, 245),
	dim = Color3.fromRGB(146, 146, 158),
	white = Color3.fromRGB(255, 255, 255),
	bad = Color3.fromRGB(255, 120, 120),
}

local function new(cls, props, parent)
	local o = Instance.new(cls)
	for k, v in pairs(props) do
		o[k] = v
	end
	if parent then
		o.Parent = parent
	end
	return o
end

local function corner(o, r)
	new("UICorner", { CornerRadius = UDim.new(0, r or 6) }, o)
	return o
end

-- returns the UIStroke, not the parent: callers recolour it on hover and on
-- tab select, and returning the parent made every one of those a runtime
-- "Color is not a valid member of TextButton"
local function stroke(o, col, t)
	return new("UIStroke", { Color = col or COL.line, Transparency = t or 0, Thickness = 1 }, o)
end

local function label(parent, text, size, col, x, y, w, h, align)
	return new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(w, h),
		Font = Enum.Font.Gotham,
		TextSize = size,
		TextColor3 = col,
		Text = text,
		TextXAlignment = align or Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
	}, parent)
end

--------------------------------------------------------------------------
-- widgets -- the shared R3ST control template (scripts/r3st_ui.lua)
--
-- Same call signatures the hand-rolled widgets had -- section(page, title),
-- toggle(page, o), slider(page, o), button(page, text, desc, fn, wide),
-- note/statusRow -- so not one of the seven page builders below changed. What
-- changed is the look: two columns of cards, pill toggles, track sliders,
-- identical to every other module in the hub.
--------------------------------------------------------------------------
local KIT_PATHS = { "../scripts/r3st_ui.lua", "r3st_ui.lua", "scripts/r3st_ui.lua" }

local UIKit
do
	local GH = GENV.__R3ST_HOST
	if type(GH) == "table" and type(GH.ui) == "table" then
		-- Embedded: the hub already loaded it, so we cannot diverge from it.
		UIKit = GH.ui
	else
		for _, path in ipairs(KIT_PATHS) do
			local ok, src = pcall(readfile, path)
			if ok and type(src) == "string" and #src > 0 then
				local chunk = loadstring(src, "=r3st_ui.lua")
				if type(chunk) == "function" then
					local ran, kit = pcall(chunk)
					if ran and type(kit) == "table" then
						UIKit = kit
						log("ui: kit " .. tostring(kit.VERSION) .. " <- " .. path)
						break
					end
				end
			end
		end
	end
end
if not UIKit then
	-- Deploy flattens every module into BOTH Potassium roots; if the kit is in
	-- neither, say so once instead of drawing a broken panel.
	log("ui: FATAL r3st_ui.lua not found in " .. table.concat(KIT_PATHS, " | "))
	error("r3st_ui.lua missing -- deploy it to the Potassium Explorer folder", 0)
end
-- One palette for the whole hub: adopt the kit's, keeping this table's identity
-- so the shell code above and below keeps working.
for k, v in pairs(UIKit.COL) do
	COL[k] = v
end


local W = UIKit.bind({ live = UI.live, conns = UI.conns, guard = U.guard })

local function nextY(page)
	return W.height(page)
end

local section = W.section
local note = W.note
local slider = W.slider
local toggle = W.toggle
local statusRow = W.statusRow
local button = W.button

--------------------------------------------------------------------------
-- profile plumbing
--------------------------------------------------------------------------
local commitTimer = nil

local function sess()
	return Binder.session
end

local function profile()
	if not UI.prof then
		local s = sess()
		UI.prof = s and Config.profileFor(s.type) or U.copy(Config.PROFILE_DEFAULT)
	end
	return UI.prof
end

-- Batched: a slider drag costs one apply, not one per pixel.
local function commitTune(why)
	local s = sess()
	if not s then
		Tune.setState("NEEDS CAR", "sit in a car")
		return
	end
	if commitTimer then
		pcall(task.cancel, commitTimer)
	end
	commitTimer = task.delay(0.35, function()
		commitTimer = nil
		U.guard("ui.commitTune", function()
			local s2 = sess()
			if not s2 then
				return
			end
			Config.setProfile(s2.type, UI.prof)
			Tune.apply(s2, UI.prof, why or "panel")
		end)
	end)
end

-- Local-only changes: no game apply, no log line.
local function commitLocal()
	local s = sess()
	Aero.dragMult = UI.prof.dragPct or 1
	Aero.downMult = UI.prof.downPct or 1
	Aero.setLimiter(UI.prof.limiter)
	if s then
		Config.setProfile(s.type, UI.prof)
	end
end

local function liveMPH()
	local s = sess()
	if not s or not s.seat or not s.seat.Parent then
		return 0
	end
	return U.mph(s.seat.AssemblyLinearVelocity.Magnitude)
end

-- CarSpeedLimits server cap, reported as a fact; nothing here throttles to
-- it. Same resolver the transmission planner uses (Limits.serverMph).
local function speedCeiling()
	local s = sess()
	if not s then
		return nil
	end
	return Limits.serverMph(s.car)
end

local function topGearMPH()
	local s = sess()
	if not s or not s.wheelDia then
		return nil
	end
	return DriveHook.speedAt(s, s.tune.Redline or 0, s.gears)
end

--------------------------------------------------------------------------
-- pages
--------------------------------------------------------------------------
local function buildSpeed(page)
	section(page, "PRESET")
	-- Two live rows instead of two hand-placed labels: the card layout owns
	-- placement now, and statusRow already repaints on the same 8 Hz tick that
	-- paintPreset was called by hand for.
	statusRow(page, function() return Config.presetByName(Config.data.preset).name end)
	statusRow(page, function() return Config.presetByName(Config.data.preset).desc end)
	local function paintPreset() end
	button(page, "Next preset", nil, function()
		local list = Config.PRESETS
		local idx = 1
		for i, p in ipairs(list) do
			if p.name == Config.data.preset then idx = i end
		end
		Config.data.preset = list[(idx % #list) + 1].name
		paintPreset()
		local s = sess()
		if s then
			UI.prof = U.merge(Config.PROFILE_DEFAULT, Config.presetByName(Config.data.preset).profile)
			Config.setProfile(s.type, UI.prof)
			commitLocal()
			commitTune("preset " .. Config.data.preset)
			UI.refreshAll()
		end
		Config.save()
	end, true)

	section(page, "POWER")
	slider(page, {
		label = "Speed amount (x stock power)", min = 0.5, max = 25, step = 0.1,
		get = function() return profile().powerMult end,
		set = function(v) profile().powerMult = v end,
		stock = function() return 1 end,
		fmt = function(v) return ("%.1fx"):format(v) end,
		tradeoff = "More pull everywhere. Costs traction and makes the server-side speed ceiling matter.",
		live = function(v)
			local s = sess()
			if not s or not s.stock then return "sit in a car" end
			local want = s.stock.hp * v * (s.stageMult or 1)
			return ("stock %.0f HP -> %.0f HP  |  live tune says %.0f HP")
				:format(s.stock.hp * (s.stageMult or 1), want, s.tune.Horsepower or 0)
		end,
		commit = function() commitTune("power") end,
	})
	slider(page, {
		label = "Rev range (x stock redline)", min = 0.6, max = 3.5, step = 0.05,
		get = function() return profile().rpmMult end,
		set = function(v) profile().rpmMult = v end,
		stock = function() return 1 end,
		fmt = function(v) return ("%.2fx"):format(v) end,
		tradeoff = "Holds each gear longer. Engine sound windows are stretched by the same factor.",
		live = function(v)
			local s = sess()
			if not s or not s.stock then return "" end
			return ("redline %d -> %d rpm  |  live %d")
				:format(s.stock.redline, math.floor(s.stock.redline * v), s.tune.Redline or 0)
		end,
		commit = function() commitTune("rev range") end,
	})

	section(page, "NITROUS")
	toggle(page, {
		label = "Nitrous",
		desc = "Hold the bind for a torque surge. Off on load, every load.",
		get = function() return Config.data.nitro.on end,
		set = function(v)
			Config.data.nitro.on = v
			if not v then
				Nitro.release("switched off")
			end
			Config.save()
		end,
	})
	local bindBtn
	bindBtn = button(page, "", nil, function()
		if UI.bindCapture then
			UI.bindCapture = false
			bindBtn.Text = "Bind: " .. Config.data.nitro.key .. "  (click to rebind)"
			return
		end
		UI.bindCapture = true
		bindBtn.Text = "press any key...  (click again to cancel)"
	end, true)
	bindBtn.Text = "Bind: " .. Config.data.nitro.key .. "  (click to rebind)"
	UI.paintNitroBind = function()
		if not UI.bindCapture then
			bindBtn.Text = "Bind: " .. Config.data.nitro.key .. "  (click to rebind)"
		end
	end
	slider(page, {
		label = "Surge power (x current output)", min = 1, max = 6, step = 0.1,
		get = function() return Config.data.nitro.mult end,
		set = function(v) Config.data.nitro.mult = v end,
		stock = function() return 2.5 end,
		fmt = function(v) return ("%.1fx"):format(v) end,
		tradeoff = "Multiplies whatever the car already makes, on top of the power slider. Traction, not power, is what runs out first.",
		live = function(v)
			local s = sess()
			if not s then return "sit in a car" end
			return ("%.0f HP -> %.0f HP while held")
				:format(s.tune.Horsepower or 0, (s.tune.Horsepower or 0) * v)
		end,
		commit = function() Config.save() end,
	})
	slider(page, {
		label = "Burn time", min = 0.5, max = 20, step = 0.5,
		get = function() return Config.data.nitro.burn end,
		set = function(v) Config.data.nitro.burn = v end,
		stock = function() return 4 end,
		fmt = function(v) return ("%.1fs"):format(v) end,
		tradeoff = "How long one hold can last before it cuts out on its own.",
		commit = function() Config.save() end,
	})
	slider(page, {
		label = "Cooldown", min = 0, max = 30, step = 0.5,
		get = function() return Config.data.nitro.cooldown end,
		set = function(v) Config.data.nitro.cooldown = v end,
		stock = function() return 6 end,
		fmt = function(v) return v <= 0 and "none" or ("%.1fs"):format(v) end,
		tradeoff = "Set to none for unlimited re-triggering. A constant surge is just the power slider, and it is the sustained speed the server cap watches.",
		commit = function() Config.save() end,
	})
	statusRow(page, function() return "nitrous: " .. tostring(Nitro.status or "off") end)

	section(page, "GEARING")
	slider(page, {
		label = "Acceleration <-> Top speed", min = 0, max = 1, step = 0.02,
		get = function() return profile().balance end,
		set = function(v) profile().balance = v end,
		stock = function() return 0.5 end,
		fmt = function(v)
			if v < 0.45 then return ("accel %d%%"):format(math.floor((0.5 - v) * 200)) end
			if v > 0.55 then return ("top end %d%%"):format(math.floor((v - 0.5) * 200)) end
			return "balanced"
		end,
		tradeoff = "Left = shorter gears, quicker off the line. Right = taller gears, slower pull.",
		live = function()
			local s = sess()
			local top = topGearMPH()
			if not (s and top) then return "" end
			return ("top gear at redline: %.0f MPH  |  now %.0f MPH"):format(top, liveMPH())
		end,
		commit = function() commitTune("balance") end,
	})
	slider(page, {
		label = "Launch", min = 0, max = 1, step = 0.05,
		get = function() return profile().launch end,
		set = function(v) profile().launch = v end,
		stock = function() return 0 end,
		fmt = function(v) return ("%d%%"):format(math.floor(v * 100)) end,
		tradeoff = "Shortens first gear for a harder start. More wheelspin off the line.",
		live = function(v) return ("first gear %+d%% shorter than stock"):format(math.floor(v * 30)) end,
		commit = function() commitTune("launch") end,
	})
	slider(page, {
		label = "Shift point", min = -1, max = 1, step = 0.05,
		get = function() return profile().shiftBias end,
		set = function(v) profile().shiftBias = v end,
		stock = function() return 0 end,
		fmt = function(v)
			if v < -0.02 then return "early" elseif v > 0.02 then return "late" else return "stock" end
		end,
		tradeoff = "Late holds each gear nearer the limiter; too late runs past the power peak.",
		live = function()
			local s = sess()
			if not s then return "" end
			local up = (s.tune.PeakRPM or 0) + (s.tune.AutoUpThresh or 0)
			return ("upshifts at %d rpm  |  power peak %d rpm"):format(math.floor(up), math.floor(s.tune.PeakRPM or 0))
		end,
		commit = function() commitTune("shift point") end,
	})

	section(page, "RESULT")
	statusRow(page, function()
		local s = sess()
		if not s then
			return "No car bound -- " .. tostring(Binder.why or "sit in a car")
		end
		local rpm = s.values and s.values:FindFirstChild("RPM")
		local gear = s.values and s.values:FindFirstChild("Gear")
		local ceil = speedCeiling()
		return ("%s  |  %.0f MPH  gear %s  %d rpm  |  tune %.0f HP @ %d%s")
			:format(s.type, liveMPH(),
				gear and tostring(gear.Value) or "?",
				rpm and math.floor(rpm.Value) or 0,
				s.tune.Horsepower or 0, s.tune.Redline or 0,
				ceil and ("  |  server ceiling ~%.0f MPH"):format(ceil) or "")
	end)
	statusRow(page, function()
		return ("state: %s  %s"):format(Tune.state, Tune.detail)
	end)
	button(page, "Apply now", nil, function() commitTune("manual apply") end)
	button(page, "Restore stock (this car)", "Clears only this car's saved profile.", function()
		local s = sess()
		if s then
			Tune.restore(s, false)
			UI.prof = nil
			UI.refreshAll()
		end
	end, true)
end

local function buildHandling(page)
	section(page, "GRIP AND STOPPING")
	slider(page, {
		label = "Traction (tire stage)", min = 1, max = 5, step = 1,
		get = function() return profile().tireStage end,
		set = function(v) profile().tireStage = math.floor(v) end,
		stock = function() return 1 end,
		fmt = function(v) return ("stage %d  (%.1fx grip)"):format(v, ({ 1, 1.2, 1.4, 1.6, 1.8 })[math.floor(v)] or 1) end,
		tradeoff = "More grip and less wheelspin. Very high grip makes the car turn in more sharply.",
		live = function()
			local s = sess()
			return s and ("live TireGripMult %.2f"):format(s.car:GetAttribute("TireGripMult") or 1) or ""
		end,
		commit = function() commitTune("traction") end,
	})
	slider(page, {
		label = "Braking (brake stage)", min = 1, max = 5, step = 1,
		get = function() return profile().brakeStage end,
		set = function(v) profile().brakeStage = math.floor(v) end,
		stock = function() return 1 end,
		fmt = function(v) return ("stage %d  (%d force)"):format(v, ({ 2500, 3500, 4500, 5500, 6500 })[math.floor(v)] or 2500) end,
		tradeoff = "Shorter stops. Easier to lock up if grip cannot cope.",
		live = function()
			local s = sess()
			return s and ("live BrakeForce %d"):format(s.tune.BrakeForce or 0) or ""
		end,
		commit = function() commitTune("brakes") end,
	})

	section(page, "DRIVETRAIN AND WEIGHT")
	slider(page, {
		label = "Drivetrain", min = 1, max = 4, step = 1,
		get = function() return profile().drivetrain end,
		set = function(v) profile().drivetrain = math.floor(v) end,
		stock = function() return 1 end,
		fmt = function(v) return ({ "STOCK", "FWD", "RWD", "AWD" })[math.floor(v)] or "STOCK" end,
		tradeoff = "AWD launches hardest, RWD rotates most, FWD understeers.",
		live = function()
			local s = sess()
			return s and ("live drive: %s"):format(tostring(s.tune.Config or "?")) or ""
		end,
		commit = function() commitTune("drivetrain") end,
	})
	slider(page, {
		label = "Weight reduction", min = 1, max = 5, step = 1,
		get = function() return profile().weightStage end,
		set = function(v) profile().weightStage = math.floor(v) end,
		stock = function() return 1 end,
		fmt = function(v) return ("stage %d  (-%d lb)"):format(v, (math.floor(v) - 1) * 100) end,
		tradeoff = "Quicker everywhere. Less stable over bumps and in fast direction changes.",
		live = function()
			local s = sess()
			return s and ("live weight %d"):format(s.tune.Weight or 0) or ""
		end,
		commit = function() commitTune("weight") end,
	})
	slider(page, {
		label = "Fuel stage", min = 1, max = 3, step = 1,
		get = function() return profile().fuelStage end,
		set = function(v) profile().fuelStage = math.floor(v) end,
		stock = function() return 1 end,
		fmt = function(v) return ("stage %d  (+%d psi, %.2fx)"):format(v, ({ 0, 2, 4 })[math.floor(v)] or 0, ({ 1, 1.03, 1.06 })[math.floor(v)] or 1) end,
		tradeoff = "A little more boost and power. No downside beyond the extra power itself.",
		live = function()
			local s = sess()
			return s and ("live boost %s psi"):format(tostring(s.car:GetAttribute("Boost") or "?")) or ""
		end,
		commit = function() commitTune("fuel") end,
	})

	section(page, "AERODYNAMICS")
	note(page, "This panel owns the chassis drag and downforce writes while it is loaded.")
	slider(page, {
		label = "Chassis drag", min = 0, max = 1.5, step = 0.05,
		get = function() return profile().dragPct end,
		set = function(v) profile().dragPct = v end,
		stock = function() return 1 end,
		fmt = function(v) return ("%d%%"):format(math.floor(v * 100)) end,
		tradeoff = "Less drag = higher terminal speed. It does not touch downforce.",
		live = function()
			return Aero.err and ("unavailable: " .. Aero.err) or ("live drag force x%.2f"):format(Aero.dragMult)
		end,
		commit = commitLocal,
	})
	slider(page, {
		label = "High-speed stability (downforce)", min = 0, max = 3, step = 0.05,
		get = function() return profile().downPct end,
		set = function(v) profile().downPct = v end,
		stock = function() return 1 end,
		fmt = function(v) return ("%d%%"):format(math.floor(v * 100)) end,
		tradeoff = "More downforce plants the car at speed. It loads the tires but does not add drag here.",
		live = function() return ("live downforce x%.2f"):format(Aero.downMult) end,
		commit = commitLocal,
	})
	toggle(page, {
		label = "Game speed brake (400 km/h)",
		desc = "The game's own AeroDrag removes speed above 400 km/h. ON leaves it alone.",
		get = function() return profile().limiter end,
		set = function(v)
			profile().limiter = v
			-- commitLocal moves Limits.limiterActive, which is the ceiling
			-- Trans.fit plans the gearbox against (0026.lua:913 upshifts on
			-- SPEED). Without the re-apply the box keeps the ratios it was
			-- given under the OLD ceiling: turning the brake off leaves the
			-- top gears short, turning it on leaves the last upshift above a
			-- speed the car can no longer reach and parks it in gear n-1.
			commitLocal()
			commitTune("speed brake")
		end,
	})
	toggle(page, {
		label = "Road prefetch",
		desc = "Asks the map to load ahead of the car. The game only streams around where you already are, so above ~200 MPH the road has not loaded yet, the wheels find nothing and the car falls out of the world. Leave this on.",
		get = function() return Config.data.streamAhead ~= false end,
		set = function(v)
			Config.data.streamAhead = v and true or false
			Config.save()
		end,
	})
	statusRow(page, function() return "road prefetch: " .. tostring(Stream.status or "idle") end)
	toggle(page, {
		label = "Crash guard",
		desc = "Leads your movement on every axis and makes traffic you are about to hit unqueryable, so the crash never registers. Anything that still gets through has its speed restored. Traffic you only pass close to is left alone, so near misses still count.",
		get = function() return Config.data.crashGuard end,
		set = function(v)
			Config.data.crashGuard = v
			Config.save()
			Guard.set(v)
		end,
	})
	statusRow(page, function() return "crash guard: " .. tostring(Guard.status or "off") end)
	toggle(page, {
		label = "Cash magnet",
		desc = "Session-only. Huge near-miss range for cash and cosmetic combo. Your car never teleports.",
		get = function() return CashMagnet.enabled end,
		set = function(v) CashMagnet.set(v) end,
	})
	toggle(page, {
		label = "Auto budget",
		desc = "ON pauses only when swerves stop paying, probes the measured server refill, and adapts. OFF never throttles cosmetic combo.",
		get = function() return CashMagnet.auto end,
		set = function(v) CashMagnet.setAuto(v) end,
	})
	slider(page, {
		label = "Hitbox visibility", min = 0, max = 1, step = 0.05,
		get = function() return Config.data.cashPreview end,
		set = function(v) CashMagnet.setVisibility(v) end,
		fmt = function(v) return ("%d%%"):format(math.floor(v * 100 + 0.5)) end,
		tradeoff = "0% hides the preview. Range and earnings stay unchanged.",
		commit = Config.save,
	})
	statusRow(page, function()
		local cash = LP:FindFirstChild("leaderstats") and LP.leaderstats:FindFirstChild("Cash")
		local gain = cash and CashMagnet.cashStart and (cash.Value - CashMagnet.cashStart) or 0
		local elapsed = CashMagnet.startedAt and math.max(1, os.clock() - CashMagnet.startedAt) or 1
		return ("cash: %s  |  combo events %d  |  paid %d  |  pending %d  |  cash %+d (%.0f/s)")
			:format(CashMagnet.status, CashMagnet.swerves, CashMagnet.paid,
				CashMagnet.pending, gain, gain / elapsed)
	end)
end

local function buildStance(page)
	section(page, "RIDE HEIGHT")
	note(page, "Suspension length in studs. Lower looks and handles tighter; too low bottoms out.")
	local function stance()
		return profile().stance
	end
	local function stanceCommit()
		commitTune("stance")
	end
	toggle(page, {
		label = "Link front and rear",
		desc = "Move one and the other follows.",
		get = function() return stance().link end,
		set = function(v) stance().link = v end,
	})
	slider(page, {
		label = "Front ride height (studs)", min = 0.3, max = 4, step = 0.05,
		get = function()
			local s = sess()
			return stance().fRide or (s and s.stock and s.stock.fRide) or 2
		end,
		set = function(v)
			stance().fRide = v
			if stance().link then stance().rRide = v end
		end,
		stock = function()
			local s = sess()
			return s and s.stock and s.stock.fRide or 2
		end,
		fmt = function(v) return ("%.2f"):format(v) end,
		live = function()
			local s = sess()
			return s and ("live FSusLength %.2f"):format(s.tune.FSusLength or 0) or ""
		end,
		commit = stanceCommit,
	})
	slider(page, {
		label = "Rear ride height (studs)", min = 0.3, max = 4, step = 0.05,
		get = function()
			local s = sess()
			return stance().rRide or (s and s.stock and s.stock.rRide) or 2
		end,
		set = function(v)
			stance().rRide = v
			if stance().link then stance().fRide = v end
		end,
		stock = function()
			local s = sess()
			return s and s.stock and s.stock.rRide or 2
		end,
		fmt = function(v) return ("%.2f"):format(v) end,
		live = function()
			local s = sess()
			return s and ("live RSusLength %.2f"):format(s.tune.RSusLength or 0) or ""
		end,
		commit = stanceCommit,
	})

	section(page, "CAMBER")
	slider(page, {
		label = "Front camber (deg)", min = -12, max = 12, step = 0.5,
		get = function()
			local s = sess()
			return stance().fCamber or (s and s.stock and s.stock.fCam) or 0
		end,
		set = function(v)
			stance().fCamber = v
			if stance().link then stance().rCamber = v end
		end,
		stock = function()
			local s = sess()
			return s and s.stock and s.stock.fCam or 0
		end,
		fmt = function(v) return ("%.1f"):format(v) end,
		tradeoff = "Negative camber holds the tire flatter in a corner and looks aggressive.",
		commit = stanceCommit,
	})
	slider(page, {
		label = "Rear camber (deg)", min = -12, max = 12, step = 0.5,
		get = function()
			local s = sess()
			return stance().rCamber or (s and s.stock and s.stock.rCam) or 0
		end,
		set = function(v)
			stance().rCamber = v
			if stance().link then stance().fCamber = v end
		end,
		stock = function()
			local s = sess()
			return s and s.stock and s.stock.rCam or 0
		end,
		fmt = function(v) return ("%.1f"):format(v) end,
		commit = stanceCommit,
	})

	section(page, "WHEEL OFFSET")
	slider(page, {
		label = "Front offset (studs)", min = -1.5, max = 1.5, step = 0.05,
		get = function() return stance().fOff or 0 end,
		set = function(v)
			stance().fOff = v
			if stance().link then stance().rOff = v end
		end,
		stock = function() return 0 end,
		fmt = function(v) return ("%.2f"):format(v) end,
		tradeoff = "Pushes the wheels outward. Cosmetic; the applier moves the axle welds.",
		commit = stanceCommit,
	})
	slider(page, {
		label = "Rear offset (studs)", min = -1.5, max = 1.5, step = 0.05,
		get = function() return stance().rOff or 0 end,
		set = function(v)
			stance().rOff = v
			if stance().link then stance().fOff = v end
		end,
		stock = function() return 0 end,
		fmt = function(v) return ("%.2f"):format(v) end,
		commit = stanceCommit,
	})
	statusRow(page, function()
		local s = sess()
		if not s then return "No car bound." end
		return ("live camber F %.1f / R %.1f, offset F %.2f / R %.2f"):format(
			s.car:GetAttribute("FrontCamber") or 0, s.car:GetAttribute("RearCamber") or 0,
			s.car:GetAttribute("FrontWheelOffset") or 0, s.car:GetAttribute("RearWheelOffset") or 0)
	end)
end

local function buildExhaust(page)
	local function ex() return profile().exhaust end
	local function exCommit() commitTune("exhaust") end
	local backfireNames = { "STOCK", "TWO-STEP A", "TWO-STEP B", "TWO-STEP C", "OFF" }
	section(page, "HARDWARE")
	slider(page, {
		label = "Backfire mode", min = 1, max = 5, step = 1,
		get = function() return ex().backfire end,
		set = function(v) ex().backfire = math.floor(v) end,
		stock = function() return 1 end,
		fmt = function(v) return backfireNames[math.floor(v)] or "STOCK" end,
		tradeoff = "Stock, three two-step sound modes, then OFF. OFF also clears any visible burst left behind.",
		commit = exCommit,
	})
	slider(page, {
		label = "Muffler", min = 1, max = 3, step = 1,
		get = function() return ex().muffler end,
		set = function(v) ex().muffler = math.floor(v) end,
		stock = function() return 1 end,
		fmt = function(v) return ({ "stock", "sport", "straight pipe" })[math.floor(v)] or "stock" end,
		tradeoff = "Louder exhaust and a broader EQ lift. Stage 3 is the loudest the game supports.",
		commit = exCommit,
	})
	section(page, "TONE")
	note(page, "EQ gain in dB on every exhaust sound the game finds on this car.")
	for _, band in ipairs({ { "low", "Low (rumble)" }, { "mid", "Mid (body)" }, { "high", "High (rasp)" } }) do
		slider(page, {
			label = band[2] .. " (dB)", min = -10, max = 10, step = 1,
			get = function() return ex()[band[1]] end,
			set = function(v) ex()[band[1]] = math.floor(v) end,
			stock = function() return 0 end,
			fmt = function(v) return ("%+d dB"):format(v) end,
			commit = exCommit,
		})
	end
	statusRow(page, function()
		local s = sess()
		if not s then return "No car bound." end
		return ("live EQ  L %s / M %s / H %s  muffler %s"):format(
			tostring(s.car:GetAttribute("ExhaustLow") or 0),
			tostring(s.car:GetAttribute("ExhaustMid") or 0),
			tostring(s.car:GetAttribute("ExhaustHigh") or 0),
			tostring(s.car:GetAttribute("ExhaustMuffler") or 1))
	end)
end

local function buildAudio(page)
	local cats = {
		{ "music", "Game music", "Menu music, showroom music and your own car radio. Never the engine." },
		{ "engine", "Your vehicle — master", "Lowers every sound from your car, including engine, exhaust, backfire, tires, brakes, horn and accessories." },
		{ "vehicleEngine", "Engine layers", "RPM-driven intake and engine layers. Multiplied by the vehicle master." },
		{ "vehicleExhaust", "Exhaust / backfire", "Exhaust notes, pops and backfire bursts. Multiplied by the vehicle master." },
		{ "vehicleTires", "Tires", "Skid, scrub and tire effects. Multiplied by the vehicle master." },
		{ "vehicleBrakes", "Brakes", "Brake whistle, heat and related brake sounds. Multiplied by the vehicle master." },
		{ "vehicleHorn", "Horn / sirens", "Horn and siren sounds from your car. Multiplied by the vehicle master." },
		{ "vehicleAccessories", "Vehicle accessories", "Remaining owned-car sounds not covered above. Multiplied by the vehicle master." },
		{ "whoosh", "Near-miss whoosh", "The pass-by sound when you thread traffic." },
		{ "impact", "Collision impact", "The crash hit sound and its sparks." },
		{ "ui", "Interface sounds", "Menu hover, click and pedal sounds." },
		{ "ambience", "Ambience and weather", "Rain, storm, day and night beds." },
		{ "otherCars", "Other players' cars", "Complete vehicle audio from everyone else's car: engine, tires, backfire, brakes and accessories." },
		{ "radios", "Other players' radios", "Everyone else's car radio, not yours." },
	}
	section(page, "MIXER")
	note(page, "Levels are multipliers over whatever the game last set. Master volume is never touched.")
	for _, c in ipairs(cats) do
		local key = c[1]
		slider(page, {
			label = c[2], min = 0, max = 1, step = 0.05,
			get = function() return Config.data.audio[key] or 1 end,
			set = function(v) Audio.setLevel(key, v) end,
			stock = function() return 1 end,
			fmt = function(v) return v <= 0 and "MUTED" or ("%d%%"):format(math.floor(v * 100)) end,
			tradeoff = c[3],
			live = function()
				if key == "engine" then
					local n = 0
					for _, rec in pairs(Audio.tracked) do
						if rec.cat:sub(1, 7) == "vehicle" then n = n + 1 end
					end
					return Audio.cfgErr or ("engine config bound + %d discrete sounds"):format(n)
				elseif key == "vehicleEngine" then
					return Audio.cfgErr or ("config-driven layers bound, rev-range factor %.2f"):format(Audio.rpmK)
				end
				local n = 0
				if key == "otherCars" then
					for sound in pairs(Audio.otherSounds) do if sound.Parent then n = n + 1 end end
				else
					for _, rec in pairs(Audio.tracked) do
						if rec.cat == key then n = n + 1 end
					end
				end
				return ("%d sound%s tracked"):format(n, n == 1 and "" or "s")
			end,
		})
	end
	button(page, "Mute everything", nil, function()
		for _, c in ipairs(cats) do
			Audio.setLevel(c[1], 0)
		end
		UI.refreshAll()
	end)
	button(page, "Reset all to 100%", nil, function()
		for _, c in ipairs(cats) do
			Audio.setLevel(c[1], 1)
		end
		UI.refreshAll()
	end)
end

local function buildESP(page)
	section(page, "PLAYER ESP")
	note(page, "Name and distance over other players. Nothing else is drawn and nothing is sent.")
	toggle(page, {
		label = "Enabled",
		get = function() return ESP.enabled end,
		set = function(v) ESP.set(v) end,
	})
	toggle(page, {
		label = "Show name",
		get = function() return Config.data.esp.name end,
		set = function(v) Config.data.esp.name = v; Config.save() end,
	})
	toggle(page, {
		label = "Show distance",
		get = function() return Config.data.esp.dist end,
		set = function(v) Config.data.esp.dist = v; Config.save() end,
	})
	note(page, "Labels draw at any range. The distance readout is still the real distance.")
	statusRow(page, function()
		local n = 0
		for _ in pairs(ESP.tags) do n = n + 1 end
		return ("%d label%s live"):format(n, n == 1 and "" or "s")
	end)
end

local function buildConfig(page)
	section(page, "THIS CAR")
	statusRow(page, function()
		local s = sess()
		if not s then
			return "No car bound. Sit in a car to see its profile."
		end
		local p = UI.prof or {}
		return ("%s  |  power %.1fx  revs %.2fx  balance %.2f  |  gen %d")
			:format(s.type, p.powerMult or 0, p.rpmMult or 0, p.balance or 0, s.gen)
	end)
	button(page, "Save this car's profile", nil, function()
		local s = sess()
		if s then
			Config.setProfile(s.type, UI.prof)
			Config.saveNow()
		end
	end)
	button(page, "Re-apply / resync", "Rebinds the car, re-reads stock and applies the saved profile once.", function()
		Binder.destroySession("manual resync")
		task.wait(0.2)
		UI.prof = nil
		commitTune("resync")
	end, true)

	section(page, "CLICK TELEPORT")
	toggle(page, {
		label = "RightAlt + left-click teleport",
		desc = "Moves you and your seated car to clicked collidable ground. Nearby players can see the jump.",
		get = function() return Config.data.clickTeleport == true end,
		set = function(v)
			Config.data.clickTeleport = v
			Config.save()
			log("clicktp: " .. (v and "enabled" or "disabled"))
		end,
	})
	statusRow(page, function()
		return Config.data.clickTeleport and "ARMED: hold RightAlt and left-click the road." or "OFF"
	end)

	section(page, "UNIVERSAL PRESETS")
	for _, p in ipairs(Config.PRESETS) do
		button(page, p.name, p.desc, function()
			Config.data.preset = p.name
			Config.save()
			local s = sess()
			if s then
				UI.prof = U.merge(Config.PROFILE_DEFAULT, p.profile)
				Config.setProfile(s.type, UI.prof)
				commitLocal()
				commitTune("preset " .. p.name)
				UI.refreshAll()
			end
		end, true)
	end
	-- Custom presets were write-only for three builds: this button saved them
	-- into the config and nothing ever read them back, so every one the user
	-- made was invisible from the moment it was written. The pages are built
	-- once at inject, so the list cannot be a row per preset -- it is a
	-- selector that reads Config.data.custom at click time instead.
	section(page, "CUSTOM PRESETS")
	local function customNames()
		local names = {}
		for n in pairs(Config.data.custom or {}) do
			names[#names + 1] = n
		end
		table.sort(names)
		return names
	end
	local function selectedCustom()
		local names = customNames()
		if #names == 0 then
			return nil, names
		end
		UI.customIdx = ((UI.customIdx or 1) - 1) % #names + 1
		return names[UI.customIdx], names
	end
	statusRow(page, function()
		local name, names = selectedCustom()
		if not name then
			return "No custom presets saved yet."
		end
		local p = Config.data.custom[name] or {}
		return ("selected: %s  (%d saved)  |  power %.1fx  revs %.2fx  balance %.2f")
			:format(name, #names, p.powerMult or 0, p.rpmMult or 0, p.balance or 0)
	end)
	button(page, "Save current settings as a custom preset", nil, function()
		local count = 0
		for _ in pairs(Config.data.custom) do count = count + 1 end
		local n = "Custom " .. tostring(count + 1)
		Config.data.custom[n] = U.copy(UI.prof or Config.PROFILE_DEFAULT)
		Config.saveNow()
		UI.customIdx = count + 1
		log("config: saved custom preset " .. n)
	end, true)
	button(page, "Next saved preset", nil, function()
		UI.customIdx = (UI.customIdx or 1) + 1
		selectedCustom()
	end)
	button(page, "Apply selected", nil, function()
		local name = selectedCustom()
		local prof = name and Config.data.custom[name]
		local s = sess()
		if not (prof and s) then
			return
		end
		UI.prof = U.merge(Config.PROFILE_DEFAULT, prof)
		Config.setProfile(s.type, UI.prof)
		commitLocal()
		commitTune("custom preset " .. name)
		UI.refreshAll()
	end)
	button(page, "Delete selected", "Removes the selected custom preset. The car keeps its current tune.", function()
		local name = selectedCustom()
		if not name then
			return
		end
		Config.data.custom[name] = nil
		Config.saveNow()
		log("config: deleted custom preset " .. name)
		UI.refreshAll()
	end, true)

	section(page, "ADVANCED (read only)")
	statusRow(page, function()
		local s = sess()
		if not s then
			return "No car bound."
		end
		local out = {}
		for i = 1, s.gears do
			out[#out + 1] = ("g%d %.3f"):format(i, s.tune.Ratios[i + 2] or 0)
		end
		return ("final drive %.3f x%.2f  |  %s"):format(
			s.tune.FinalDrive or 0, s.tune.FDMult or 1, table.concat(out, "  "))
	end)
	statusRow(page, function()
		local s = sess()
		if not (s and s.wheelDia) then
			return "Wheel size unknown; speed predictions are off."
		end
		local out = {}
		for i = 1, s.gears do
			out[#out + 1] = ("g%d %.0f"):format(i, DriveHook.speedAt(s, s.tune.Redline or 0, i))
		end
		return "MPH at redline:  " .. table.concat(out, "  ")
	end)
	statusRow(page, function()
		local s = sess()
		if not s then
			return ""
		end
		return ("stock capture: %.0f HP, %d redline, %d peak%s"):format(
			s.stock and s.stock.hp or 0, s.stock and s.stock.redline or 0,
			s.stock and s.stock.peak or 0,
			s.hpCorrected and "  |  horsepower set directly (engine swap)" or "")
	end)

	section(page, "HEALTH")
	statusRow(page, function()
		local s = sess()
		local drv = s and (s.drv and "power tables OK" or ("power rebuild off: " .. tostring(s.drvErr))) or "no car"
		return ("build %s  |  %s  |  tune %s %s"):format(BUILD_VERSION, drv, Tune.state, Tune.detail)
	end)
	statusRow(page, function()
		return ("aero: %s  |  audio: %s"):format(
			Aero.err or (Aero.conn and "owned" or "idle"),
			Audio.cfgErr or "ok")
	end)

	section(page, "DANGER")
	button(page, "Restore stock and unload", nil, function()
		UI.panic()
	end, true)
	button(page, "Factory reset (wipe all saved profiles)", "Cannot be undone. Restores stock first.", function()
		local s = sess()
		Nitro.release("factory reset")
		if s then
			Tune.restore(s, false)
		end
		Config.data = U.copy(Config.DEFAULT)
		Config.saveNow()
		Audio.levels = Config.data.audio -- the old table is gone; re-point
		Audio.applyCat("engine")
		for _, c in ipairs({ "music", "whoosh", "impact", "ui", "ambience", "otherCars", "radios" }) do
			Audio.applyCat(c)
		end
		ESP.set(false)
		Guard.set(false)
		CashMagnet.set(false)
		UI.prof = nil
		UI.refreshAll()
		log("config: factory reset")
	end, true)
end

--------------------------------------------------------------------------
-- shell
--------------------------------------------------------------------------
-- Every other subsystem edge reports through U.guard; this one used a bare
-- pcall, so a readout that threw every tick was invisible and "that row is
-- stuck" had no entry in the log to find it by. Bounded on purpose: this runs
-- 8 times a second over every live row, and an unbounded log would be its own
-- outage.
UI.liveErrs = 0
UI.LIVE_ERR_CAP = 8

function UI.refreshAll()
	for _, fn in ipairs(UI.live) do
		local ok, err = pcall(fn)
		if not ok and UI.liveErrs < UI.LIVE_ERR_CAP then
			UI.liveErrs = UI.liveErrs + 1
			log(("ERR ui.live (%d/%d): %s"):format(UI.liveErrs, UI.LIVE_ERR_CAP, tostring(err)))
			if UI.liveErrs == UI.LIVE_ERR_CAP then
				log("ui: further live-row errors suppressed this session")
			end
		end
	end
end

function UI.build()
	-- hub.lua publishes __R3ST_HOST immediately before running us. When it is
	-- there the hub owns the ScreenGui, the window chrome, the blur, the drag
	-- and the show/hide key, so we build the same 920x600 body scaled into its
	-- content host and grow none of those four. Standalone is unchanged.
	local GH = GENV.__R3ST_HOST
	local embed = (type(GH) == "table" and typeof(GH.host) == "Instance") and GH or nil
	UI.embed = embed

	local gui
	if embed then
		gui = embed.host
		log("ui: embedded in R3ST hub host " .. tostring(embed.build))
	else
		local host
		if type(gethui) == "function" then
			local ok, h = pcall(gethui)
			if ok and h then host = h end
		end
		log(("ui: gethui -> %s (%s)"):format(
			host and host.Name or "nil", host and host.ClassName or "-"))
		if host and host:IsA("LayerCollector") then
			-- gethui() already IS a ScreenGui on Potassium; nesting one renders
			-- nothing, so use it directly as the host.
			gui = host
		else
			gui = new("ScreenGui", {
				Name = "g" .. tostring(math.random(100000, 999999)),
				ResetOnSpawn = false,
				IgnoreGuiInset = true,
				ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
			}, host or LP:FindFirstChildOfClass("PlayerGui"))
			UI.ownGui = gui
		end
	end
	UI.gui = gui

	if not embed then
		local blur = new("BlurEffect", { Name = "R3ST_GD_Blur", Size = 4, Enabled = not Config.data.ui.hidden }, game:GetService("Lighting"))
		UI.blur = blur
	end
	local root = new("Frame", {
		Name = "r" .. tostring(math.random(100000, 999999)),
		BackgroundColor3 = COL.bg,
		BackgroundTransparency = embed and 1 or 0,
		BorderSizePixel = 0,
		Position = embed and UDim2.new() or UDim2.fromOffset(Config.data.ui.x, Config.data.ui.y),
		Size = UDim2.fromOffset(920, 600),
		-- when the host is RobloxGui we are a sibling of the core frames, so
		-- sit above them rather than behind
		ZIndex = 50,
		-- Embedded, the hub's tab decides what is on screen; a saved "hidden"
		-- must not leave the tab blank with no way to bring it back.
		Visible = embed and true or not Config.data.ui.hidden,
	}, gui)
	if not embed then
		corner(root, 10)
		stroke(root, COL.line)
	end
	UI.root = root
	if embed then
		-- The body is laid out in fixed offsets, so fit the whole thing rather
		-- than reflowing seven pages of controls.
		local uiScale = new("UIScale", { Scale = 1 }, root)
		local function refit()
			local hs = embed.host.AbsoluteSize
			if hs.X < 8 or hs.Y < 8 then return end
			uiScale.Scale = math.min(1, hs.X / 920, hs.Y / 600)
		end
		refit()
		UI.conns[#UI.conns + 1] = embed.host:GetPropertyChangedSignal("AbsoluteSize"):Connect(refit)
	end

	-- sparse decorative star detail
	for _, sp in ipairs({ { 890, 12 }, { 902, 32 }, { 20, 575 }, { 880, 574 } }) do
		local st = label(root, "*", 11, COL.white, sp[1], sp[2], 10, 10)
		st.TextTransparency = 0.72
	end

	local bar = new("Frame", {
		BackgroundColor3 = COL.panel,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 58),
	}, root)
	corner(bar, 10)
	new("Frame", { BackgroundColor3 = COL.panel, BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 46), Size = UDim2.new(1, 0, 0, 12) }, bar)
	local title = label(bar, "R3ST HUB", 18, COL.white, 20, 4, 120, 28)
	title.Font = Enum.Font.GothamBold
	local gameTitle = label(bar, "|   Ghost Driver", 15, COL.dim, 138, 4, 240, 28)
	gameTitle.Font = Enum.Font.GothamMedium
	label(bar, BUILD_VERSION, 10, COL.dim, 20, 29, 240, 20)

	local hideBtn = new("TextButton", {
		BackgroundTransparency = 1, Position = UDim2.fromOffset(872, 8),
		Size = UDim2.fromOffset(34, 34), Font = Enum.Font.GothamBold,
		TextSize = 14, TextColor3 = COL.dim, Text = "-", AutoButtonColor = false,
	}, bar)
	hideBtn.Visible = not embed
	hideBtn.MouseButton1Click:Connect(function() UI.toggle() end)

	-- drag (the hub drags its own window when we are embedded)
	local dragging, dragStart, startPos
	if not embed then
	bar.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging, dragStart, startPos = true, i.Position, root.Position
		end
	end)
	UI.conns[#UI.conns + 1] = UserInputService.InputChanged:Connect(function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
			local d = i.Position - dragStart
			root.Position = UDim2.fromOffset(startPos.X.Offset + d.X, startPos.Y.Offset + d.Y)
		end
	end)
	UI.conns[#UI.conns + 1] = UserInputService.InputEnded:Connect(function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch) then
			dragging = false
			Config.data.ui.x = root.Position.X.Offset
			Config.data.ui.y = root.Position.Y.Offset
			Config.save()
		end
	end)
	end

	-- R3ST Hub game navigation sidebar
	local strip = new("Frame", {
		BackgroundColor3 = COL.panel,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(10, 68),
		Size = UDim2.fromOffset(164, 500),
	}, root)
	corner(strip, 8)
	stroke(strip, COL.line)
	local builders = {
		SPEED = buildSpeed, HANDLING = buildHandling, STANCE = buildStance,
		EXHAUST = buildExhaust, AUDIO = buildAudio, ESP = buildESP, CONFIG = buildConfig,
	}
	local btns = {}
	for i, name in ipairs(UI.order) do
		local b = new("TextButton", {
			BackgroundColor3 = COL.panel,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(10, 14 + (i - 1) * 48),
			Size = UDim2.fromOffset(144, 38),
			Font = Enum.Font.GothamBold,
			TextSize = 11,
			TextColor3 = COL.dim,
			Text = name,
			AutoButtonColor = false,
		}, strip)
		corner(b, 5)
		local s = stroke(b, COL.line)
		btns[name] = { b = b, s = s }
		b.MouseButton1Click:Connect(function() UI.showTab(name) end)
	end
	local hubBtn = new("TextButton", {
		BackgroundColor3 = COL.panel, BorderSizePixel = 0,
		Position = UDim2.fromOffset(10, 446), Size = UDim2.fromOffset(144, 38),
		Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = COL.dim,
		Text = "‹  HUB", AutoButtonColor = false,
	}, strip)
	corner(hubBtn, 5)
	stroke(hubBtn, COL.line)
	-- Embedded we ARE in the hub; its sidebar is the navigation.
	hubBtn.Visible = not embed
	hubBtn.MouseButton1Click:Connect(function()
		local ok, chunk = pcall(loadfile, "hub.lua")
		if not ok or type(chunk) ~= "function" then return end
		local current = GENV[GKEY]
		if current and type(current.unload) == "function" then current.unload() end
		pcall(chunk)
	end)

	local body = new("Frame", {
		BackgroundColor3 = COL.panel,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(184, 68),
		Size = UDim2.fromOffset(726, 500),
	}, root)
	corner(body, 8)
	stroke(body, COL.line)

	for _, name in ipairs(UI.order) do
		local page = new("ScrollingFrame", {
			Name = name,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(10, 8),
			Size = UDim2.fromOffset(706, 484),
			CanvasSize = UDim2.new(),
			ScrollBarThickness = 3,
			ScrollBarImageColor3 = COL.line,
			Visible = false,
		}, body)
		-- Two columns of cards, template width. The page builders below never
		-- position anything themselves.
		W.page(page, { width = 700 })
		UI.tabs[name] = page
		local built = U.guard("ui.build." .. name, builders[name], page)
		page.CanvasSize = UDim2.fromOffset(0, nextY(page) + 12)
		log(("ui: page %s %s, %d children"):format(
			name, built and "ok" or "FAILED", #page:GetChildren()))
	end

	UI.btns = btns
	label(root, "RightShift hide  |  RightControl unload  |  Delete panic restore", 10, COL.dim, 20, 574, 700, 16)

	UI.showTab(Config.data.ui.tab)
	log(("ui: built root=%s parent=%s visible=%s pos=%d,%d size=%dx%d")
		:format(root.Name, tostring(root.Parent and root.Parent:GetFullName()),
			tostring(root.Visible), root.Position.X.Offset, root.Position.Y.Offset,
			root.Size.X.Offset, root.Size.Y.Offset))
	logflush()
end

function UI.showTab(name)
	if not UI.tabs[name] then
		name = "SPEED"
	end
	-- per-tab guard: this loop is the last thing UI.build runs, so an error
	-- here used to escape into main()'s pcall and unload the whole script.
	-- One broken tab must never cost the other six.
	for _, n in ipairs(UI.order) do
		U.guard("ui.showTab." .. n, function()
			local p = UI.tabs[n]
			if p then
				p.Visible = (n == name)
			end
			local b = UI.btns and UI.btns[n]
			if b then
				b.b.BackgroundColor3 = (n == name) and COL.white or COL.panel
				b.b.TextColor3 = (n == name) and COL.bg or COL.dim
				b.s.Color = (n == name) and COL.white or COL.line
			end
		end)
	end
	Config.data.ui.tab = name
	Config.save()
	UI.refreshAll()
end

function UI.toggle()
	if not UI.root then
		return
	end
	if UI.embed then
		-- The hub's RightShift hides the whole hub ScreenGui. Hiding our root as
		-- well would leave the tab blank when the hub comes back.
		return
	end
	UI.root.Visible = not UI.root.Visible
	if UI.blur then UI.blur.Enabled = UI.root.Visible end
	Config.data.ui.hidden = not UI.root.Visible
	Config.save()
end

--==========================================================================
-- Boot and teardown
--==========================================================================
local GD = {}
GD.conns = {}
GD.running = true

function GD.onBound(ev, s)
	if ev == "unbound" then
		Aero.unbind()
		Audio.unbindCar()
		-- The surge lived in the old car's Drive tables; they left with it.
		Nitro.forget()
		-- Guard is NOT released here: it owns its own 2 Hz poll and arms on
		-- cars this session never binds. Releasing it on unbind would also
		-- leave Guard.boundCar stale, so re-entering the same car never
		-- re-armed.
		if s and UI.prof then
			Config.setProfile(s.type, UI.prof)
		end
		UI.prof = nil
		Tune.setState("NEEDS CAR", "no car")
		return
	end
	-- bound
	U.guard("boot.bind", function()
		Tune.captureStock(s)
		DriveHook.measureWheels(s)
		-- Wait out Drive's WaitForChild + curve build. Without this, a fast
		-- re-seat binds with Drive Instance present but env incomplete, and
		-- every live apply fails until the next enter.
		if not DriveHook.attach(s, 3.0) then
			-- Keep watching this seat generation; Drive may still finish after
			-- our budget (heavy WaitForChild chain on a slow frame).
			task.spawn(function()
				U.guard("boot.drvWatch", function()
					local deadline = os.clock() + 5
					while Binder.session == s and not s.drv and os.clock() < deadline do
						task.wait(0.25)
						if DriveHook.ensure(s, 0) then
							log("drive: late attach recovered")
							local prof = UI.prof or Config.profileFor(s.type)
							if prof then
								Tune.apply(s, prof, "late drive attach")
							end
							return
						end
					end
				end)
			end)
		end
		-- stage multiplier measured, never assumed: Horsepower is exactly
		-- BaseHorsepower x the stage product (0562.lua:490)
		local baseHP = tonumber(s.car:GetAttribute("BaseHorsepower"))
		if baseHP and baseHP > 0 and s.tune.Horsepower then
			s.stageMult = s.tune.Horsepower / baseHP
		else
			s.stageMult = 1
		end
		UI.prof = Config.profileFor(s.type)
		Aero.dragMult = UI.prof.dragPct or 1
		Aero.downMult = UI.prof.downPct or 1
		Aero.bind(s)
		Aero.setLimiter(UI.prof.limiter)
		Audio.bindCar(s)
		-- "Inject once and immediately receive a saved speed boost."
		Tune.apply(s, UI.prof, "auto on bind")
		UI.refreshAll()
	end)
end

function GD.unload(silentRestore)
	if not GD.running then
		return
	end
	GD.running = false
	U.guard("unload.tune", function()
		local s = Binder.session
		if s and silentRestore ~= false then
			Tune.restore(s, true) -- put the car back, keep the saved profile
		end
	end)
	U.guard("unload.nitro", function() Nitro.release("unload") end)
	U.guard("unload.aero", Aero.restoreAll)
	U.guard("unload.guard", Guard.shutdown)
	U.guard("unload.cashMagnet", CashMagnet.shutdown)
	U.guard("unload.audio", Audio.stop)
	U.guard("unload.esp", ESP.clearAll)
	U.guard("unload.binder", Binder.stop)
	for _, c in ipairs(GD.conns) do
		pcall(function() c:Disconnect() end)
	end
	for _, c in ipairs(UI.conns) do
		pcall(function() c:Disconnect() end)
	end
	if GD.tickThread then
		pcall(task.cancel, GD.tickThread)
		GD.tickThread = nil
	end
	if UI.ownGui then
		pcall(function() UI.ownGui:Destroy() end)
	elseif UI.root then
		pcall(function() UI.root:Destroy() end)
	end
	if UI.blur then pcall(function() UI.blur:Destroy() end); UI.blur = nil end
	U.guard("unload.save", Config.saveNow)
	log("unload complete")
	logflush()
	if GENV[GKEY] then
		GENV[GKEY] = nil
	end
end

function UI.panic()
	log("PANIC restore requested")
	GD.unload(true)
end

local function main()
	Config.load()
	log(("boot build=%s place=%s"):format(BUILD_VERSION, tostring(game.PlaceId)))
	log("resumed: clicktp=" .. (Config.data.clickTeleport and "ON (RightAlt + left-click)" or "OFF"))

	Audio.start()
	ESP.enabled = Config.data.esp.enabled == true

	UI.build()
	local swerveBridge = ReplicatedStorage:FindFirstChild("SwerveUIBridge")
	if swerveBridge and swerveBridge:IsA("BindableEvent") then
		GD.conns[#GD.conns + 1] = swerveBridge.Event:Connect(function()
			CashMagnet.onSwerve()
		end)
	end
	local cash = LP:FindFirstChild("leaderstats") and LP.leaderstats:FindFirstChild("Cash")
	if cash then
		CashMagnet.cashValue = cash.Value
		GD.conns[#GD.conns + 1] = cash.Changed:Connect(CashMagnet.onCash)
	end
	Binder.onChange(GD.onBound)
	Binder.start()
	-- Independent of Binder on purpose: crash protection has to arm on cars
	-- that never produce a tune session.
	Guard.set(Config.data.crashGuard)

	GD.conns[#GD.conns + 1] = UserInputService.InputBegan:Connect(function(i, gpe)
		if gpe then
			return
		end
		-- Rebinding swallows the keystroke, so the new bind cannot also fire
		-- the panel shortcut it is replacing.
		if UI.bindCapture then
			if i.UserInputType == Enum.UserInputType.Keyboard
				and i.KeyCode ~= Enum.KeyCode.Unknown then
				UI.bindCapture = false
				Config.data.nitro.key = i.KeyCode.Name
				Config.save()
				log("nitro: bound to " .. i.KeyCode.Name)
				if UI.paintNitroBind then UI.paintNitroBind() end
			end
			return
		end
		if i.UserInputType == Enum.UserInputType.MouseButton1
			and Config.data.clickTeleport == true
			and UserInputService:IsKeyDown(Enum.KeyCode.RightAlt) then
			U.guard("clicktp.go", ClickTP.go)
			return
		end
		if i.KeyCode == Enum.KeyCode.RightShift then
			UI.toggle()
		elseif i.KeyCode == Enum.KeyCode.RightControl then
			GD.unload(true)
		elseif i.KeyCode == Enum.KeyCode.Delete then
			UI.panic()
		elseif i.KeyCode.Name == Config.data.nitro.key then
			U.guard("nitro.down", Nitro.keyDown)
		end
	end)

	GD.conns[#GD.conns + 1] = UserInputService.InputEnded:Connect(function(i)
		-- No gpe check on release: if the key went down for us it must come
		-- back up for us, whatever the game did with the event in between.
		if i.KeyCode.Name == Config.data.nitro.key then
			U.guard("nitro.up", Nitro.keyUp)
		end
	end)

	-- ONE tick, 8 Hz, drives every readout, the ESP, the four reconcilers and
	-- the log flush. Nothing in this file runs per frame except the aero force
	-- writer, which must, because it replaces a per-frame game handler.
	--
	-- These used to be five independent task.spawn loops (binder, guard, cash
	-- magnet, audio, tick), each with its own task.cancel in its own shutdown
	-- path. Five schedules that all had to be torn down separately is five
	-- chances to leak a thread through a re-inject, and nothing needed a phase
	-- of its own: everything here is 0.5 s or 2 s work. One counter now says
	-- when each runs, and GD.unload cancels one thread.
	GD.tickThread = task.spawn(function()
		local n = 0
		while GD.running do
			task.wait(0.125)
			n = n + 1
			U.guard("tick.ui", UI.refreshAll)
			U.guard("tick.esp", ESP.step)
			if n % 4 == 0 then -- 2 Hz reconcilers
				U.guard("tick.bind", Binder.tick)
				U.guard("tick.guard", Guard.poll)
				U.guard("tick.cash", CashMagnet.poll)
			end
			if n % 16 == 0 then -- sound census, self-throttling
				U.guard("tick.audio", Audio.tick)
			end
			-- Burn expiry and "the car went away mid-surge". Key release is
			-- handled directly by InputEnded, so 8 Hz is only the backstop.
			U.guard("tick.nitro", Nitro.tick)
			-- The road has to load ahead of the car whatever else this tick
			-- does; Stream.step throttles itself to 4 Hz.
			U.guard("tick.stream", Stream.step)
			if n % 16 == 0 then
				logflush()
			end
		end
	end)

	GENV[GKEY] = {
		unload = function() GD.unload(true) end,
		build = BUILD_VERSION,
	}
	log("ready")
	logflush()
end

local ok, err = pcall(main)
if not ok then
	log("FATAL " .. tostring(err))
	logflush()
	pcall(GD.unload, false)
end
