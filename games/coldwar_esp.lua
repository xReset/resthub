--------------------------------------------------------------------------
-- coldwar_esp.lua — Cold War [MOUNTED MGs] PlaceId 13687899540  BUILD 2026-09-09.1
-- Dump: game_dumps/13687899540/2026-08-23T12-14-15Z_1787487255975_2E90B2DD-...
--
-- Re-inject safe: self-teardown on load; K = unload
-- UNLOADS_ON_INJECT: __COLDWAR_ESP
--
-- CHANGELOG
--   2026-08-24.9  Silent aim now ray-checks the predicted dragged/gravity path,
--                 not only the straight muzzle-to-current-head line. Pass-through
--                 telemetry names LOS/path/range/angle rejection and shot distance.
--   2026-08-24.8  Based on the live-confirmed .6 build; drops the never-injected
--                 .7 vehicle autocalibration. Shared soft/silent FOV is now a
--                 10-2400 px drag slider. Silent aim has no script range cap;
--                 only the game's projectile lifetime/physics can limit reach.
--   2026-08-24.6  State resumes as the user left it. Silent redirect and vehicle
--                 speed are no longer wiped on load: both are client-side (a
--                 packet the player already fired, a drive model this client
--                 simulates), so they restore armed, paint their restored state
--                 in the panel, and are named in the boot log line. K remains
--                 the panic key: one press unloads everything.
--   2026-08-24.5  Folded dump-backed wheeled/tracked vehicle speed into the
--                 main GUI as a 100-300% slider. Defaults OFF at 100%.
--   2026-08-24.4  Doubled configurable ESP max distance to 4096 studs.
--   2026-08-24.3  Downed enemies stay outlined and are valid soft/silent aim
--                 targets. Removed box/snapline rendering and render-budget
--                 controls; outlines use the fixed engine-safe pool. Max
--                 distance remains the sole render-range control.
--   2026-08-24.2  Per-volley/pellet silent telemetry: selected target, angle,
--                 weapon, seed, local impact victim/part, claim eligibility,
--                 and projectile finish reason. Uses ClientFire's existing
--                 OnImpact/OnFinish options after normal HitReporter runs.
--                 Shared soft/silent FOV expands to 1200 px. On-screen streamed
--                 characters get Highlight priority regardless of distance.
--   2026-08-24.1  Dump-backed silent redirection at ClientFire.fireVolley.
--                 Default OFF every inject. Normal packet passes through byte
--                 for byte when OFF, targetless, blocked, invalid, or errored.
--                 Preserves pellet spread shape, seeds, origin, fire time,
--                 ammo/cadence, local simulation, and normal HitClaim path.
--   2026-08-23.6  Autosave/autoload every control, including soft aim, recoil,
--                 speed, panel visibility, and dragged panel position.
--   2026-08-23.5  Raise the real gethui ScreenGui above Roblox's Esc menu and
--                 CoreBlur so one Esc press frees the mouse for this panel.
--                 Restore the shared host's prior priority on unload.
--   2026-08-23.4  Stance cycle folded in from the standalone coldwar_stance.lua
--                 (which was deployed but never injected, so it never ran —
--                 no log file at all). C now cycles Stand/Crouch/Prone/Stand
--                 from THIS script, one inject. ADS probe default OFF: the
--                 08:50 log showed ADS working, alpha reached 1.00; it only
--                 refused while stance=Run, which is the game's own rule
--                 (isAimingAvailable, 0350:94).
--   2026-08-23.3  Read-only ADS diagnostic (1 Hz while RMB held) — "cannot
--                 scope in" was reported and no existing log line covers the
--                 ADS gate, so this measures it instead of guessing. Adds the
--                 Head/Torso/Closest aim-part cycle.
--   2026-08-23.2  Highlight chams (true silhouette outline) for enemies AND
--                 allies, capped under the engine's 31-Highlight render limit.
--                 Recoil strength cut via RecoilController.getRecoilMult
--                 override. WalkSpeed boost after MovementTuning. Soft-aim
--                 strength/step sliders exposed. Fixed aim log writing a file
--                 line EVERY frame (488 lines in one 3-minute session — that
--                 was main-thread I/O in the render path). Dropped the health
--                 sampler: the 08:29 log proved remote Torso.Health replicates
--                 ("ZAIKER torso=57.00117978182705/150 head=18.83 down=true").
--   2026-08-23.1  First build: DrawingImmediate enemy ESP + ballistic soft aim.
--
-- Rung 1-3 plus vehicle rung 5 (potassium-dev §5.1): reads instances the client already owns,
-- draws with DrawingImmediate / client-owned Highlights, and writes only
-- client-local values. Soft aim emits local mouse deltas. Silent aim changes
-- only pellet Direction inside the game's normal Fire packet (0093:123-178);
-- no remote is forged, no damage claim is forged, and no hookfunction /
-- hookmetamethod is used. Server sees the redirected direction and normal claim.
-- Vehicle speed wraps WheelDrive.new / TrackDrive.new and retunes only the
-- client-owned per-seat drive object (0541:487, 0568:80-85, 0549:20-23).
-- Server and nearby players see the resulting vehicle motion.
--
-- === ANTICHEAT (anticheat_deep.txt, this dump) ===
--   ENFORCEMENT 4   — all Gamebeast infra (shutdown/updater kick, BanAsync).
--   REPORTING 0, CLIENT INSPECTION 0.
--   LOG MONITORING 7 — ReplicatedStorage.Client.ParticleBatch.Batcher (0305).
--     THIS IS A REAL DETECTOR wearing a particle-budget name. It runs in an
--     Actor, hooks LogService.MessageOut (0305:825), reads GetLogHistory
--     (0305:380/500/797) and FireServers every unrecognised console line
--     verbatim (240 chars) on Remotes.ParticleBudget (0305:397-410).
--     runIntegrity (0305:264) prints a canary token and checks it returns,
--     plus rawequal(LogService.GetLogHistory, GetLogHistory) (0305:274) and
--     debug.info "[C]" checks — i.e. it detects log suppression and hooks on
--     those two. On failure it plays a marker Animation on YOUR character
--     ~60-180s later (0305:241 playMarker, 0305:356).
--     => THIS SCRIPT NEVER CALLS print/warn, AND NEVER HOOKS LogService OR
--        debug.info. Log goes to file with {print=false}.
--   MOVEMENT CHECKS 129 — every hit is a game-owned WalkSpeed/PlatformStand
--     write (revive carry 0060/0063, control-panel fly 0070). There is no
--     client-side speed VALIDATION in this dump. See "Speed boost" below for
--     what the server can still see.
--
-- === DUMP FACTS THIS SCRIPT RELIES ON ===
--   Teams        = Neutral / PACT / NATO                       teams.txt
--   Characters   = Workspace.Characters.<PlayerName>           characters.txt
--   Rig          = R6: Head / Torso / HumanoidRootPart         characters.txt
--   Humanoid.Health is 1/1 for EVERY player (58/58) — useless. Real health is
--   per limb:      <Part>.Health [NumberValue] {MaxHealth=n}   trees/Workspace.txt
--                  Head 50, Torso 150, arms/legs 100 each
--                  CONFIRMED replicating for remote players — logs/coldwar_esp.log
--                  08:29:34 "ZAIKER torso=57.00117978182705/150 head=18.83896"
--   Downed       = <char>.CharacterValues.Unconscious [BoolValue]
--   Streaming    = StreamingEnabled true, Min 256 / Target 2048  properties.txt
--                  => never WaitForChild a character part
--   Ray groups   = RayNATO / RayPACT, CollisionGroups.teamRayGroup  0496.lua
--   Fire dir     = muzzle attachment WorldCFrame * CFrame.Angles(zeroAngle,0,0)
--                  + random spread; camera drives the viewmodel     0329:66-88
--   Ballistics   = t(d) = -(1/K)*ln(1 - d*K/v) ; drop = 0.5*g*t^2   0440.lua
--   Weapon data  = WeaponConfigManager:GetMuzzleConfig(toolName,1)
--                    .BulletSettings[1].MuzzleVelocity / .Drag  0586/0587.lua
--   Zeroing      = ZeroController.zeroAngle() already applied by the game 0357:205
--
--   RECOIL       RecoilController (0352). applyRecoil (0352:111) scales EVERY
--                spring shove — offset / rotation / handle / camera — by
--                u3.getRecoilMult() (0352:130), and that is a plain field on
--                the module table with exactly ONE caller. CameraController
--                then reads getSpring("camera") and rotates the camera by it
--                at RenderPriority.Camera+1 (0273:467-489). So scaling
--                getRecoilMult is the single source-level knob for recoil;
--                it needs no hookfunction, no metatable, and restores by
--                assigning the original function back.
--
--   SPEED        MovementTuning.update (0281:52) runs every frame from
--                StanceController's BindToRenderStep at
--                RenderPriority.Character (0282:338, 0282:392) and sets
--                humanoid.WalkSpeed = WALK_SPEED[stance] * inertia
--                * legHealthMult * SpeedMultiplier.Value * WadeFactor.
--                Base speeds (0283:23): Run 22, Walk 10, Crouch 8, Prone 4.
--                Two tempting knobs are DEAD:
--                  CharacterValues.SpeedMultiplier — AimController rewrites it
--                    every RenderStep, "u7.Value = u2 * -0.25 + 1" (0350:178).
--                  character:SetAttribute("WadeFactor") — SurfaceSwim._step
--                    resets it to 1 every step when out of water (0277:301).
--                So we scale the WalkSpeed the game just computed, one write
--                per frame at RenderPriority.Character + 1. That inherits
--                stance, leg damage, ADS and wading for free.
--
-- Allies: the game nameplates your own team via Head.Teammate [BillboardGui],
-- so ally boxes/names default OFF and ally chams default ON — chams are the
-- thing the game does not give you.
--
-- RightShift = toggle panel | K = unload | hold RMB = soft aim (when enabled)
-- C = cycle stance Stand -> Crouch -> Prone -> Stand (X never needed)
--------------------------------------------------------------------------

if game.PlaceId ~= 13687899540 then
	error("[COLDWAR_ESP] wrong place " .. tostring(game.PlaceId) .. " (need 13687899540)", 0)
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local LP = Players.LocalPlayer
local RNG = Random.new()

local GENV = (getgenv and getgenv()) or _G
if type(GENV) ~= "table" then
	GENV = _G
end

local GKEY = "__COLDWAR_ESP"

-- hub.lua publishes __R3ST_HOST immediately before running us and clears it the
-- moment we return. When it is set, the hub owns the ScreenGui, the window
-- chrome, the drag and RightShift, so the CONTROL PANEL renders inside its
-- content host. The ESP/visual layer is deliberately left alone: it has to stay
-- a full-screen CoreGui layer, never a child of a hub panel.
local __HUBENV = (type(getgenv) == "function" and getgenv()) or _G
local HOST = (type(__HUBENV.__R3ST_HOST) == "table"
	and typeof(__HUBENV.__R3ST_HOST.host) == "Instance") and __HUBENV.__R3ST_HOST or nil

local BUILD_VERSION = "2026-09-09.1"
local CONFIG_FILE = "coldwar_esp_config.json"

if GENV[GKEY] and type(GENV[GKEY].destroy) == "function" then
	pcall(GENV[GKEY].destroy)
end

-- The stance cycle used to live in a separate coldwar_stance.lua. It is folded
-- in here now; unload a stale copy so C never gets handled twice.
if GENV.__COLDWAR_STANCE and type(GENV.__COLDWAR_STANCE.destroy) == "function" then
	pcall(GENV.__COLDWAR_STANCE.destroy)
end
if GENV.__COLDWAR_VEHICLE and type(GENV.__COLDWAR_VEHICLE.destroy) == "function" then
	pcall(GENV.__COLDWAR_VEHICLE.destroy)
end

--------------------------------------------------------------------------
-- Logging — file only. print/warn are read by 0305 Batcher and shipped to
-- the server verbatim, so {print = false} is mandatory in this game.
--------------------------------------------------------------------------
local Log
do
	local ok, mod = pcall(function()
		return loadfile("log.lua")()
	end)
	if ok and type(mod) == "function" then
		Log = mod("coldwar_esp", { print = false })
	else
		local buf = {}
		local function flush(tag, m)
			buf[#buf + 1] = string.format("[%s] %s", tag, tostring(m))
			pcall(writefile, "logs/coldwar_esp.log", table.concat(buf, "\n") .. "\n")
		end
		Log = {
			path = "logs/coldwar_esp.log",
			session = function(m) flush("session", m) end,
			step = function(m) flush("step", m) end,
			info = function(m) flush("info", m) end,
			warn = function(m) flush("warn", m) end,
			err = function(m, e) flush("err", tostring(m) .. " " .. tostring(e)) end,
		}
	end
end

GENV[GKEY] = GENV[GKEY] or {}
local ESP = GENV[GKEY]

--------------------------------------------------------------------------
-- Config
--------------------------------------------------------------------------
local DEFAULTS = {
	-- enemies
	EnemyNames = true,
	EnemyDistance = true,
	EnemyHealth = true,
	EnemyChams = true,
	-- allies (game already nameplates them — chams are the gap worth filling)
	AllyNames = false,
	AllyHealth = false,
	AllyChams = true,
	-- shared draw
	MaxDist = 4096,       -- doubled cap; streamed rigs may still stop near 2048
	RosterHz = 0.5,
	-- soft aim (loud; persisted by explicit user request)
	SoftAim = false,
	SilentAim = false,       -- forced OFF after config load on every inject
	Ballistics = true,
	AimFov = 70,          -- pixels of screen radius
	AimStrength = 45,     -- percent of residual error applied per frame
	AimMaxStepPx = 22,
	SilentMaxAngle = 12,     -- hard camera-to-shot cap; victim-visible above this
	AimPart = "Head",
	ShowAimFov = true,
	-- recoil / speed (loud; persisted by explicit user request)
	RecoilCut = 0,        -- percent of recoil removed
	SpeedBoost = 100,     -- percent of the game's own computed WalkSpeed
	VehicleSpeed = 100,   -- 100=OFF; scales client-owned drive speed + force
	AdsProbe = false,     -- 1 Hz read-only ADS diagnostic while RMB is held
	StanceCycle = true,   -- C cycles Stand -> Crouch -> Prone -> Stand
	UiVisible = true,
	UiXScale = 0,
	UiXOffset = 14,
	UiYScale = 0.14,
	UiYOffset = 0,
}

local VALIDATORS = {
	EnemyNames = function(v) return type(v) == "boolean" end,
	EnemyDistance = function(v) return type(v) == "boolean" end,
	EnemyHealth = function(v) return type(v) == "boolean" end,
	EnemyChams = function(v) return type(v) == "boolean" end,
	AllyNames = function(v) return type(v) == "boolean" end,
	AllyHealth = function(v) return type(v) == "boolean" end,
	AllyChams = function(v) return type(v) == "boolean" end,
	MaxDist = function(v) return type(v) == "number" and v >= 50 and v <= 4096 end,
	RosterHz = function(v) return type(v) == "number" and v >= 0.1 and v <= 3 end,
	SoftAim = function(v) return type(v) == "boolean" end,
	SilentAim = function(v) return type(v) == "boolean" end,
	Ballistics = function(v) return type(v) == "boolean" end,
	AimFov = function(v) return type(v) == "number" and v >= 10 and v <= 2400 end,
	AimStrength = function(v) return type(v) == "number" and v >= 1 and v <= 100 end,
	AimMaxStepPx = function(v) return type(v) == "number" and v >= 1 and v <= 200 end,
	SilentMaxAngle = function(v) return type(v) == "number" and v >= 1 and v <= 20 end,
	AimPart = function(v) return v == "Head" or v == "Torso" or v == "Closest" end,
	ShowAimFov = function(v) return type(v) == "boolean" end,
	RecoilCut = function(v) return type(v) == "number" and v >= 0 and v <= 100 end,
	SpeedBoost = function(v) return type(v) == "number" and v >= 100 and v <= 160 end,
	VehicleSpeed = function(v) return type(v) == "number" and v >= 100 and v <= 300 end,
	AdsProbe = function(v) return type(v) == "boolean" end,
	StanceCycle = function(v) return type(v) == "boolean" end,
	UiVisible = function(v) return type(v) == "boolean" end,
	UiXScale = function(v) return type(v) == "number" and v >= -2 and v <= 2 end,
	UiXOffset = function(v) return type(v) == "number" and v >= -10000 and v <= 10000 end,
	UiYScale = function(v) return type(v) == "number" and v >= -2 and v <= 2 end,
	UiYOffset = function(v) return type(v) == "number" and v >= -10000 and v <= 10000 end,
}

local CFG = {}
for k, v in pairs(DEFAULTS) do
	CFG[k] = v
end

local function readConfig()
	local ok, raw = pcall(readfile, CONFIG_FILE)
	if not ok or type(raw) ~= "string" then
		return
	end
	local decoded, data = pcall(HttpService.JSONDecode, HttpService, raw)
	if not decoded or type(data) ~= "table" then
		Log.warn("config unreadable; defaults")
		return
	end
	for k, v in pairs(data) do
		local check = VALIDATORS[k]
		if check and check(v) then
			CFG[k] = v
		end
	end
end

local function saveConfig()
	local snapshot = {}
	for k in pairs(DEFAULTS) do
		snapshot[k] = CFG[k]
	end
	local ok, encoded = pcall(HttpService.JSONEncode, HttpService, snapshot)
	if ok then
		pcall(writefile, CONFIG_FILE, encoded)
	end
end

readConfig()
-- Everything here is client-side: silent redirection edits a packet the player
-- already fired, and vehicle speed retunes a drive model this client simulates.
-- Neither initiates a server call, so both resume exactly as the user left them
-- (potassium-dev §0.2b). The armed state is shown in the panel and named in the
-- boot log line at the bottom of this file.

--------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------
local S = {
	alive = true,
	roster = {},
	entryOf = {},
	conns = {},
	charConns = {},
	chams = {},         -- pool of Highlight instances
	rosterAcc = 0,
	stickyPlayer = nil,
	silentCat = nil,
	silentAt = 0,
	silentShotSeq = 0,
	aimCat = nil,
	aimAt = 0,
	adsAt = 0,
	stanceSeq = 0,
	errAt = 0,
	weaponCache = {},
	partScratch = {},   -- reused per frame so aim candidates allocate nothing
	recoilModule = nil,
	recoilOrig = nil,
	clientFire = nil,
	clientFireOrig = nil,
	clientFireWrapper = nil,
	speedBind = nil,
	vehicleDrives = {},
	vehicleWrapped = {},
	vehicleEngine = nil,
	uiHost = nil,
	uiHostDisplayOrder = nil,
	uiHostOnTop = nil,
	uiHostOnTopKnown = false,
}

local COL = {
	bg = Color3.fromRGB(16, 18, 20),
	stroke = Color3.fromRGB(58, 64, 70),
	text = Color3.fromRGB(226, 230, 234),
	dim = Color3.fromRGB(126, 134, 142),
	on = Color3.fromRGB(180, 46, 46),
	off = Color3.fromRGB(42, 46, 50),
}

local C_FOE = Color3.fromRGB(255, 74, 62)
local C_ALLY = Color3.fromRGB(78, 158, 255)
local C_DOWN = Color3.fromRGB(150, 150, 150)
local C_TEXT = Color3.fromRGB(240, 240, 240)
local C_LINE = Color3.fromRGB(0, 0, 0)
local C_HP_OK = Color3.fromRGB(90, 220, 90)
local C_HP_LOW = Color3.fromRGB(230, 180, 40)
local FONT = 1 -- Drawing.Fonts.System

--------------------------------------------------------------------------
-- Dump-backed adapters
--------------------------------------------------------------------------
local RAY_BY_TEAM = { NATO = "RayNATO", PACT = "RayPACT" } -- 0496.lua
local RAY_NEUTRAL = "RayNeutral"

local function teamName(plr)
	local t = plr and plr.Team
	return t and t.Name or nil
end

-- Returns nil (skip), true (enemy) or false (ally). Neutral is the deploying /
-- spectating pool — those players have no live body worth tracking.
local function sideOf(plr)
	if plr == LP then
		return nil
	end
	local mine, theirs = teamName(LP), teamName(plr)
	if not mine or not theirs or mine == "Neutral" or theirs == "Neutral" then
		return nil
	end
	return mine ~= theirs
end

-- Characters are reparented to Workspace.Characters.<PlayerName> (characters.txt).
-- Streaming can leave Player.Character stale, so check both, never WaitForChild.
local function getCharacter(plr)
	local char = plr and plr.Character
	if char and char.Parent then
		return char
	end
	local folder = Workspace:FindFirstChild("Characters")
	return folder and folder:FindFirstChild(plr.Name) or nil
end

-- Humanoid.Health is 1/1 for every player here. Real health is per limb:
-- <Part>.Health [NumberValue] + MaxHealth attribute (trees/Workspace.txt).
local function limbHealth(part)
	if not part then
		return nil, nil
	end
	local hv = part:FindFirstChild("Health")
	if not (hv and hv:IsA("NumberValue")) then
		return nil, nil
	end
	local maxHp = hv:GetAttribute("MaxHealth")
	if type(maxHp) ~= "number" or maxHp <= 0 then
		return nil, nil
	end
	return hv.Value, maxHp
end

local function isDowned(char)
	local cv = char and char:FindFirstChild("CharacterValues")
	local unc = cv and cv:FindFirstChild("Unconscious")
	return (unc and unc:IsA("BoolValue") and unc.Value) or false
end

local function isAlive(char)
	if not (char and char.Parent) then
		return false
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health <= 0 then
		return false
	end
	local hp = select(1, limbHealth(char:FindFirstChild("Torso")))
	if hp ~= nil and hp <= 0 then
		return false
	end
	return true
end

-- WeaponConfigManager preloads every weapon module at require time (0586:11).
local function weaponBallistics(muzzleIndex, bulletIndex, weaponRef)
	local char = LP.Character
	local tool = weaponRef or (char and char:FindFirstChildOfClass("Tool"))
	local weaponName = typeof(tool) == "Instance" and tool.Name or (type(tool) == "string" and tool or nil)
	if not weaponName then
		return nil
	end
	muzzleIndex = muzzleIndex or 1
	bulletIndex = bulletIndex or 1
	local cacheKey = string.format("%s:%d:%d", weaponName, muzzleIndex, bulletIndex)
	local cached = S.weaponCache[cacheKey]
	if cached ~= nil then
		return cached or nil
	end
	local ok, cfg = pcall(function()
		local wcm = require(ReplicatedStorage.Shared:WaitForChild("WeaponConfigManager", 5))
		return wcm:GetMuzzleConfig(weaponName, muzzleIndex)
	end)
	local bullet = ok and cfg and cfg.BulletSettings and cfg.BulletSettings[bulletIndex]
	if not (bullet and type(bullet.MuzzleVelocity) == "number" and bullet.MuzzleVelocity > 0) then
		S.weaponCache[cacheKey] = false
		return nil
	end
	local data = { v = bullet.MuzzleVelocity, k = math.max(bullet.Drag or 0, 0) }
	S.weaponCache[cacheKey] = data
	return data
end

-- 0440.lua Trajectory.GetTimeForDistance, inlined so we hold no game upvalue.
local function flightTime(ball, dist)
	if dist <= 0 then
		return 0
	end
	if ball.k > 1e-6 then
		if ball.v / ball.k <= dist then
			return nil -- drag eats the bullet before it arrives
		end
		return -(1 / ball.k) * math.log(1 - dist * ball.k / ball.v)
	end
	return dist / ball.v
end

-- The game already tilts the shot up by ZeroController.zeroAngle() (0329:82).
local function currentZeroAngle()
	local ok, angle = pcall(function()
		local controllers = ReplicatedStorage.Client.Tools.Weapon.controllers
		return require(controllers.ZeroController).zeroAngle()
	end)
	return (ok and type(angle) == "number") and angle or 0
end

--------------------------------------------------------------------------
-- Recoil — scale RecoilController.getRecoilMult (0352:74).
-- applyRecoil (0352:130) is its only caller and multiplies all four springs
-- by it, so one plain field assignment on a client-local module table is the
-- whole feature. No hookfunction, no metatable, exactly reversible.
--------------------------------------------------------------------------
local function installRecoil()
	if S.recoilModule then
		return true
	end
	local ok, rc = pcall(function()
		return require(ReplicatedStorage.Client.Tools.Weapon.controllers.RecoilController)
	end)
	if not ok or type(rc) ~= "table" or type(rc.getRecoilMult) ~= "function" then
		Log.warn("recoil: RecoilController.getRecoilMult not reachable")
		return false
	end
	S.recoilModule = rc
	S.recoilOrig = rc.getRecoilMult
	rc.getRecoilMult = function()
		local base = 1
		local okBase, v = pcall(S.recoilOrig)
		if okBase and type(v) == "number" then
			base = v
		end
		return base * (1 - math.clamp(CFG.RecoilCut, 0, 100) / 100)
	end
	Log.info("recoil override installed")
	return true
end

local function restoreRecoil()
	if S.recoilModule and S.recoilOrig then
		pcall(function()
			S.recoilModule.getRecoilMult = S.recoilOrig
		end)
		Log.info("recoil override restored")
	end
	S.recoilModule, S.recoilOrig = nil, nil
end

--------------------------------------------------------------------------
-- Speed — scale the WalkSpeed MovementTuning just computed (0281:150), one
-- write per frame at RenderPriority.Character + 1. Inherits stance, leg
-- damage, ADS and wading. Server sees the replicated WalkSpeed and the
-- resulting motion: this is the one feature here another player can narrate.
--------------------------------------------------------------------------
local function speedStep()
	if CFG.SpeedBoost <= 100 then
		return
	end
	local char = LP.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	-- WalkSpeed 0 means carried / reviving / unconscious (0060:276) — leave it.
	if hum.WalkSpeed > 0 then
		hum.WalkSpeed = hum.WalkSpeed * (CFG.SpeedBoost / 100)
	end
end

--------------------------------------------------------------------------
-- Vehicle speed — DriverController creates one client drive object per seat
-- (0541:487). WheelDrive.new / TrackDrive.new are plain module fields. Scale
-- only that returned object; never shared config, velocity, CFrame, or remotes.
--------------------------------------------------------------------------
local function vehicleMultiplier()
	return math.clamp(CFG.VehicleSpeed, 100, 300) / 100
end

local function applyVehicleDrive(d, rec)
	local mult = vehicleMultiplier()
	local o = rec.orig
	if rec.kind == "Tracked" then
		d.maxSpeed = o.maxSpeed * mult
		if o.driveGain then d.driveGain = o.driveGain * mult end
		return
	end
	d.topSpeed = o.topSpeed * mult
	if d.engine and o.torqueScale then
		d.engine.torqueScale = o.torqueScale * mult
	end
	local cfgDrag = type(d.config) == "table" and d.config.DragCoefficient or nil
	if cfgDrag then
		d.dragK = cfgDrag / mult
	elseif d.engine and S.vehicleEngine and type(S.vehicleEngine.MaxForceAtSpeed) == "function" then
		local ok, force = pcall(S.vehicleEngine.MaxForceAtSpeed, d.engine, d.topSpeed)
		if ok and type(force) == "number" and force > 0 and d.topSpeed > 0 then
			d.dragK = force / (d.topSpeed * d.topSpeed)
		else
			d.dragK = o.dragK
		end
	else
		d.dragK = o.dragK
	end
end

local function restoreVehicleDrive(d, rec)
	pcall(function()
		local o = rec.orig
		if rec.kind == "Tracked" then
			d.maxSpeed = o.maxSpeed
			if o.driveGain then d.driveGain = o.driveGain end
		else
			d.topSpeed = o.topSpeed
			d.dragK = o.dragK
			if d.engine and o.torqueScale then d.engine.torqueScale = o.torqueScale end
		end
	end)
end

local function applyVehicleSpeed()
	local applied = 0
	for d, rec in pairs(S.vehicleDrives) do
		local ok, live = pcall(function() return d.root and d.root.Parent end)
		if not ok or not live then
			S.vehicleDrives[d] = nil
		else
			local okApply, err = pcall(applyVehicleDrive, d, rec)
			if okApply then
				applied += 1
			else
				Log.err("vehicle apply", err)
			end
		end
	end
	Log.info(string.format("vehicle speed=%d%% applied=%d", CFG.VehicleSpeed, applied))
end

local function wrapVehicleModule(module, kind)
	if type(module) ~= "table" or type(module.new) ~= "function" or S.vehicleWrapped[module] then
		return
	end
	local original = module.new
	local wrapper
	wrapper = function(vehicle, config, inputs)
		local d = original(vehicle, config, inputs)
		-- inputs=nil is the game's undriven/spectated path (0568:81).
		if not S.alive or type(d) ~= "table" or inputs == nil then return d end
		local ok, err = pcall(function()
			local orig
			if kind == "Tracked" then
				orig = { maxSpeed = d.maxSpeed, driveGain = d.driveGain }
			else
				orig = {
					topSpeed = d.topSpeed,
					dragK = d.dragK,
					torqueScale = d.engine and d.engine.torqueScale or nil,
				}
			end
			local rec = { kind = kind, orig = orig }
			S.vehicleDrives[d] = rec
			applyVehicleDrive(d, rec)
		end)
		if not ok then Log.err("vehicle wrapper", err) end
		return d
	end
	module.new = wrapper
	S.vehicleWrapped[module] = { original = original, wrapper = wrapper }
	Log.info("vehicle " .. kind .. " wrapper installed")
end

local function installVehicleSpeed()
	local ok, err = pcall(function()
		local vehicle = ReplicatedStorage:WaitForChild("Shared", 10):WaitForChild("Vehicle", 10)
		local engine = vehicle:FindFirstChild("Engine")
		if engine then S.vehicleEngine = require(engine) end
		local wheel = vehicle:FindFirstChild("WheelDrive")
		local track = vehicle:FindFirstChild("TrackDrive")
		if wheel then wrapVehicleModule(require(wheel), "Wheeled") end
		if track then wrapVehicleModule(require(track), "Tracked") end
	end)
	if not ok then Log.err("vehicle install", err) end
end

local function restoreVehicleSpeed()
	for d, rec in pairs(S.vehicleDrives) do restoreVehicleDrive(d, rec) end
	S.vehicleDrives = {}
	for module, rec in pairs(S.vehicleWrapped) do
		pcall(function()
			if module.new == rec.wrapper then module.new = rec.original end
		end)
	end
	S.vehicleWrapped = {}
	S.vehicleEngine = nil
end

--------------------------------------------------------------------------
-- Chams — client-owned Highlight instances, Adornee'd to the model.
-- Never parented to another player's parts (potassium-dev §5.4); the engine
-- renders at most 31 Highlights. On-screen streamed rigs take priority at any
-- distance; remaining budget fills nearest-first.
--------------------------------------------------------------------------
local function chamsWanted(entry)
	if entry.foe then
		return CFG.EnemyChams
	end
	return CFG.AllyChams
end

local function updateChams()
	local want, deferred, chosen = {}, {}, {}
	local camera = Workspace.CurrentCamera
	for _, entry in ipairs(S.roster) do
		if chamsWanted(entry) then
			local onScreen = false
			if camera then
				local _, visible = camera:WorldToViewportPoint(entry.hrp.Position)
				onScreen = visible
			end
			if onScreen and #want < 30 then
				want[#want + 1] = entry
				chosen[entry] = true
			else
				deferred[#deferred + 1] = entry
			end
		end
	end
	local budget = math.max(30, #want)
	for _, entry in ipairs(deferred) do
		if #want >= math.min(budget, 30) then
			break
		end
		if not chosen[entry] then
			want[#want + 1] = entry
		end
	end
	for i = 1, math.max(#want, #S.chams) do
		local hl = S.chams[i]
		local entry = want[i]
		if entry then
			if not (hl and hl.Parent) then
				hl = Instance.new("Highlight")
				hl.Name = "H" .. string.format("%04x", RNG:NextInteger(0, 65535))
				hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
				hl.Parent = S.folder
				S.chams[i] = hl
			end
			local col = entry.downed and C_DOWN or (entry.foe and C_FOE or C_ALLY)
			hl.Adornee = entry.char
			hl.OutlineColor = col
			hl.OutlineTransparency = 0
			hl.FillColor = col
			hl.FillTransparency = 1
			hl.Enabled = true
		elseif hl then
			hl.Adornee = nil
			hl.Enabled = false
		end
	end
end

local function wipeChams()
	for _, hl in ipairs(S.chams) do
		pcall(function() hl:Destroy() end)
	end
	S.chams = {}
end

--------------------------------------------------------------------------
-- Roster — rebuilt at RosterHz, never per frame. Sorted nearest-first so the
-- chams budget always lands on the targets that matter.
--------------------------------------------------------------------------
local function rebuildRoster()
	local camera = Workspace.CurrentCamera
	local camPos = camera and camera.CFrame.Position or Vector3.zero
	local list, seen = {}, {}
	for _, plr in ipairs(Players:GetPlayers()) do
		local foe = sideOf(plr)
		if foe ~= nil then
			local char = getCharacter(plr)
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp and hrp:IsA("BasePart") and isAlive(char) then
				local entry = S.entryOf[plr]
				if not entry then
					entry = {}
					S.entryOf[plr] = entry
				end
				entry.plr = plr
				entry.foe = foe
				entry.char = char
				entry.hrp = hrp
				entry.head = char:FindFirstChild("Head")
				entry.torso = char:FindFirstChild("Torso")
				entry.downed = isDowned(char)
				entry.rank = (hrp.Position - camPos).Magnitude
				entry.name = plr.DisplayName ~= "" and plr.DisplayName or plr.Name
				list[#list + 1] = entry
				seen[plr] = true
			end
		end
	end
	for plr in pairs(S.entryOf) do
		if not seen[plr] then
			S.entryOf[plr] = nil
		end
	end
	table.sort(list, function(a, b)
		return a.rank < b.rank
	end)
	S.roster = list
	updateChams()
end

--------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------
local DI = rawget(GENV, "DrawingImmediate") or DrawingImmediate

local function drawText(cx, y, text, color)
	DI.OutlinedText(Vector2.new(cx, y), FONT, 13, color, 1, C_LINE, 1, text, true)
end

local function drawHealth(x, y, h, frac)
	local fill = math.clamp(frac, 0, 1)
	DI.FilledRectangle(Vector2.new(x - 7, y - 1), Vector2.new(5, h + 2), C_LINE, 0.55, 0)
	DI.FilledRectangle(
		Vector2.new(x - 6, y + h * (1 - fill)),
		Vector2.new(3, h * fill),
		fill > 0.4 and C_HP_OK or C_HP_LOW, 1, 0
	)
end

--------------------------------------------------------------------------
-- Soft aim
--------------------------------------------------------------------------
-- v.1 logged the pixel error every frame, so the note string changed every
-- frame and appendfile ran inside the render step — 488 file writes in one
-- 3-minute session. Category drives the line; detail is rate limited to 1 Hz.
local function aimNote(cat, detail)
	local now = os.clock()
	if cat ~= S.aimCat then
		S.aimCat = cat
		S.aimAt = 0
	end
	if now - S.aimAt < 1 then
		return
	end
	S.aimAt = now
	Log.step("aim " .. cat .. (detail and (" " .. detail) or ""))
end

-- R6 only has three usable aim anchors (characters.txt). "Closest" evaluates
-- head and torso and takes whichever lands nearer the crosshair this frame,
-- which is what you want when a target is prone or half behind cover.
local function aimCandidates(entry, out)
	table.clear(out)
	local mode = CFG.AimPart
	if mode ~= "Torso" and entry.head then
		out[#out + 1] = entry.head
	end
	if mode ~= "Head" and entry.torso then
		out[#out + 1] = entry.torso
	end
	if #out == 0 then
		out[1] = entry.head or entry.torso or entry.hrp
	end
	return out
end

local function visibleFrom(origin, part, char)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { LP.Character, Workspace:FindFirstChild("Ignore") }
	params.IgnoreWater = false
	-- Match the game's own bullet ray group (0439:88) so team barriers behave
	-- for us exactly as they do for the round we are about to fire.
	local ok = pcall(function()
		params.CollisionGroup = RAY_BY_TEAM[teamName(LP)] or RAY_NEUTRAL
	end)
	if not ok then
		params.CollisionGroup = "Default"
	end
	local hit = Workspace:Raycast(origin, part.Position - origin, params)
	return (not hit) or hit.Instance:IsDescendantOf(char)
end

local function visibleTo(camera, part, char)
	return visibleFrom(camera.CFrame.Position, part, char)
end

-- Where to point so a dragged, dropping bullet meets a moving target.
local function ballisticSolution(origin, part, muzzleIndex, bulletIndex, weaponRef)
	local target = part.Position
	if not CFG.Ballistics then
		return target
	end
	local ball = weaponBallistics(muzzleIndex, bulletIndex, weaponRef)
	if not ball then
		return nil
	end
	local vel = part.AssemblyLinearVelocity
	local g = Workspace.Gravity
	local aim = target
	for _ = 1, 3 do
		local t = flightTime(ball, (aim - origin).Magnitude)
		if not t or t > 5 then
			return nil -- ProjectileTypes defaults MaxTime to 5 (0435:10)
		end
		aim = target + vel * t + Vector3.new(0, 0.5 * g * t * t, 0)
	end
	local t = flightTime(ball, (aim - origin).Magnitude)
	if not t or t > 5 then
		return nil
	end
	return aim, t, ball
end

-- Mirror Trajectory.GetPositionAtTime (0440:92-128) and ray each segment.
-- Straight LOS to the current head can miss cover crossed by the elevated/led path.
local function ballisticPathClear(origin, aim, flight, ball, char)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { LP.Character, Workspace:FindFirstChild("Ignore") }
	params.IgnoreWater = false
	local ok = pcall(function()
		params.CollisionGroup = RAY_BY_TEAM[teamName(LP)] or RAY_NEUTRAL
	end)
	if not ok then
		params.CollisionGroup = "Default"
	end
	local dir = (aim - origin).Unit
	local prior = origin
	for i = 1, 12 do
		local t = flight * (i / 12)
		local forward
		if ball.k > 1e-6 then
			forward = ball.v / ball.k * (1 - math.exp(-ball.k * t))
		else
			forward = ball.v * t
		end
		local pos = origin + dir * forward - Vector3.new(0, 0.5 * Workspace.Gravity * t * t, 0)
		local hit = Workspace:Raycast(prior, pos - prior, params)
		if hit then
			if hit.Instance:IsDescendantOf(char) then
				return true
			end
			return false, hit.Instance.Name
		end
		prior = pos
	end
	return true
end

local function ballisticAimPoint(origin, part)
	return ballisticSolution(origin, part, 1, 1) or part.Position
end

local function softAimStep(camera, center)
	if not CFG.SoftAim then
		return
	end
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
	if not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
		S.stickyPlayer = nil
		aimNote("waiting: hold RMB")
		return
	end
	local myChar = LP.Character
	if not (myChar and isAlive(myChar)) or isDowned(myChar) then
		S.stickyPlayer = nil
		aimNote("waiting: local dead/downed")
		return
	end

	local origin = camera.CFrame.Position
	local best, bestScore, bestPoint, bestPart
	local stickyRadius = CFG.AimFov * 1.35
	local parts = S.partScratch

	for _, entry in ipairs(S.roster) do
		if entry.foe and entry.screen then
			local radius = (entry.plr == S.stickyPlayer) and stickyRadius or CFG.AimFov
			for _, part in ipairs(aimCandidates(entry, parts)) do
				if part and part.Parent then
					local sp, onScreen = camera:WorldToViewportPoint(ballisticAimPoint(origin, part))
					if onScreen and sp.Z > 0 then
						local d = (Vector2.new(sp.X, sp.Y) - center).Magnitude
						if d <= radius then
							local score = (entry.plr == S.stickyPlayer) and d * 0.55 or d
							if not bestScore or score < bestScore then
								best, bestScore = entry, score
								bestPoint, bestPart = Vector2.new(sp.X, sp.Y), part
							end
						end
					end
				end
			end
		end
	end

	if not best then
		S.stickyPlayer = nil
		aimNote("searching: no candidate in fov")
		return
	end

	local part = bestPart
	if not (part and visibleTo(camera, part, best.char)) then
		if best.plr == S.stickyPlayer then
			S.stickyPlayer = nil
		end
		aimNote("holding: occluded", best.name)
		return
	end
	S.stickyPlayer = best.plr

	-- Undo the elevation the game itself will add on top of our aim (0329:82).
	local zero = currentZeroAngle()
	if zero ~= 0 then
		local pxPerRad = camera.ViewportSize.Y / (2 * math.tan(math.rad(camera.FieldOfView) * 0.5))
		bestPoint = bestPoint + Vector2.new(0, zero * pxPerRad)
	end

	local delta = bestPoint - center
	local move = delta * (math.clamp(CFG.AimStrength, 1, 100) / 100)
	if move.Magnitude > CFG.AimMaxStepPx then
		move = move.Unit * CFG.AimMaxStepPx
	end
	local ok, err = pcall(mousemoverel, move.X, move.Y)
	if ok then
		aimNote("moving", string.format("%s err=%.0fpx", best.name, delta.Magnitude))
	else
		aimNote("FAILED", tostring(err))
	end
end

--------------------------------------------------------------------------
-- Silent redirection
--
-- Shooter builds spread directions, then calls ClientFire.fireVolley with the
-- weapon, exact muzzle/bullet indices, origin, and volley (0329:81-110).
-- ClientFire adds seeds and feeds the same encoded directions to BOTH Net.Fire
-- and local ProjectileCaster (0093:123-178), preserving HitReporter's seed/path.
--------------------------------------------------------------------------
local function silentNote(cat, detail)
	local now = os.clock()
	if cat ~= S.silentCat then
		S.silentCat = cat
		S.silentAt = 0
	end
	if now - S.silentAt < 1 then
		return
	end
	S.silentAt = now
	Log.step("silent " .. cat .. (detail and (" " .. detail) or ""))
end

local function silentTarget(weaponRef, muzzleIndex, bulletIndex, origin, directions)
	if not CFG.SilentAim or typeof(origin) ~= "Vector3"
		or type(directions) ~= "table" or #directions == 0 then
		return nil
	end
	local myChar = LP.Character
	if not (myChar and isAlive(myChar)) or isDowned(myChar) then
		return nil
	end

	local camera = Workspace.CurrentCamera
	if not camera then
		return nil
	end
	local center = camera.ViewportSize * 0.5
	local best, bestPart, bestAim, bestScore, bestFlight, bestDistance
	local sawFov, sawLos, sawBallistic, pathBlock = false, false, false, nil
	local parts = S.partScratch
	for _, entry in ipairs(S.roster) do
		if entry.foe and entry.char and isAlive(entry.char) then
			for _, part in ipairs(aimCandidates(entry, parts)) do
				if part and part.Parent then
					local sp, onScreen = camera:WorldToViewportPoint(part.Position)
					if onScreen and sp.Z > 0 then
						local dist = (Vector2.new(sp.X, sp.Y) - center).Magnitude
						if dist <= CFG.AimFov and (not bestScore or dist < bestScore) then
							sawFov = true
							if visibleFrom(origin, part, entry.char) then
								sawLos = true
								local aim, flight, ball = ballisticSolution(origin, part, muzzleIndex, bulletIndex, weaponRef)
								if aim then
									sawBallistic = true
									local clear, blocker = ballisticPathClear(origin, aim, flight, ball, entry.char)
									if clear then
										best, bestPart, bestAim, bestScore = entry, part, aim, dist
										bestFlight, bestDistance = flight, (part.Position - origin).Magnitude
									else
										pathBlock = blocker
									end
								end
							end
						end
					end
				end
			end
		end
	end
	if not (best and bestPart) then
		if pathBlock then return nil, "path-blocked:" .. pathBlock end
		if sawBallistic then return nil, "path-blocked" end
		if sawLos then return nil, "range/flight" end
		if sawFov then return nil, "raw-los" end
		return nil, "no-candidate"
	end
	-- Selection used muzzle origin, not camera origin. This rejects a target
	-- visible around camera cover when the actual shot ray is blocked (0439:86-101).
	if not bestAim or (bestAim - origin).Magnitude <= 0.001 then
		return nil
	end

	local sum = Vector3.zero
	for _, direction in ipairs(directions) do
		if typeof(direction) ~= "Vector3" or direction.Magnitude <= 0.001 then
			return nil
		end
		sum += direction.Unit
	end
	local base = sum.Magnitude > 0.001 and sum.Unit or directions[1].Unit
	local desired = (bestAim - origin).Unit
	local angle = math.deg(math.acos(math.clamp(base:Dot(desired), -1, 1)))
	if angle > CFG.SilentMaxAngle then
		return nil, string.format("angle:%.1f", angle)
	end

	-- Rotate the whole volley instead of collapsing it. Shotgun/pellet spread
	-- shape and every seed remain unchanged; only the volley centre is redirected.
	local from = CFrame.lookAt(Vector3.zero, base)
	local to = CFrame.lookAt(Vector3.zero, desired)
	local redirected = table.create(#directions)
	for i, direction in ipairs(directions) do
		redirected[i] = to:VectorToWorldSpace(from:VectorToObjectSpace(direction.Unit)).Unit
	end
	return redirected, best.name, angle, best.plr, bestPart.Name, bestDistance, bestFlight
end

local function restoreSilentAim()
	if S.clientFire and S.clientFireOrig and S.clientFire.fireVolley == S.clientFireWrapper then
		S.clientFire.fireVolley = S.clientFireOrig
	end
	S.clientFire, S.clientFireOrig, S.clientFireWrapper = nil, nil, nil
end

local function installSilentAim()
	if S.clientFireWrapper then
		return true
	end
	local ok, clientFire = pcall(function()
		local scripts = LP:WaitForChild("PlayerScripts", 5)
		local bc = scripts and scripts:WaitForChild("BallisticsClient", 5)
		local module = bc and bc:WaitForChild("ClientFire", 5)
		return module and require(module)
	end)
	if not ok or type(clientFire) ~= "table" or type(clientFire.fireVolley) ~= "function" then
		Log.warn("silent: ClientFire.fireVolley unavailable")
		return false
	end
	S.clientFire = clientFire
	S.clientFireOrig = clientFire.fireVolley
	S.clientFireWrapper = function(weaponRef, muzzleIndex, bulletIndex, origin, directions, options)
		local okRedirect, redirected, targetName, angle, targetPlayer, targetPart, targetDistance, flight = pcall(
			silentTarget, weaponRef, muzzleIndex, bulletIndex, origin, directions
		)
		if okRedirect and redirected then
			S.silentShotSeq += 1
			local shotId = S.silentShotSeq
			local weaponName = typeof(weaponRef) == "Instance" and weaponRef.Name or tostring(weaponRef)
			local traced = options and table.clone(options) or {}
			local priorImpact, priorFinish = traced.OnImpact, traced.OnFinish
			local pelletOf = {}
			traced.OnImpact = function(impact)
				local okTrace, traceErr = pcall(function()
					local meta = impact and pelletOf[impact.Projectile]
					local inst = impact and impact.Instance
					local model = inst and inst:FindFirstAncestorOfClass("Model")
					local victim = model and Players:GetPlayerFromCharacter(model)
					local victimName = victim and victim.Name or "world"
					local hitTarget = victim == targetPlayer
					Log.step(string.format(
						"silent impact id=%d pellet=%s seed=%s wanted=%s/%s hit=%s/%s target=%s outcome=%s",
						shotId, meta and meta.index or "?", meta and meta.seed or "?",
						targetName, targetPart, victimName, inst and inst.Name or "nil",
						tostring(hitTarget), tostring(impact and impact.Outcome)
					))
				end)
				if not okTrace then
					silentNote("telemetry error", tostring(traceErr))
				end
				if priorImpact then
					return priorImpact(impact)
				end
			end
			traced.OnFinish = function(projectile, reason)
				local okTrace, traceErr = pcall(function()
					local meta = pelletOf[projectile]
					Log.step(string.format(
						"silent finish id=%d pellet=%s seed=%s reason=%s",
						shotId, meta and meta.index or "?", meta and meta.seed or "?", tostring(reason)
					))
				end)
				if not okTrace then
					silentNote("telemetry error", tostring(traceErr))
				end
				if priorFinish then
					return priorFinish(projectile, reason)
				end
			end
			Log.step(string.format(
				"silent shot id=%d target=%s/%s weapon=%s muzzle=%d bullet=%d pellets=%d angle=%.1f dist=%.0f flight=%.3f",
				shotId, targetName, targetPart, weaponName, muzzleIndex, bulletIndex, #redirected, angle,
				targetDistance or -1, flight or -1
			))
			local results = S.clientFireOrig(
				weaponRef, muzzleIndex, bulletIndex, origin, redirected, traced
			)
			if type(results) == "table" then
				for i, result in ipairs(results) do
					if result and result.proj then
						pelletOf[result.proj] = { index = i, seed = result.seed }
					end
				end
			end
			return results
		end
		if not okRedirect then
			silentNote("fallback", tostring(redirected))
		elseif targetName then
			silentNote("pass-through", tostring(targetName))
		end
		-- Exact original arguments: OFF/no target/error cannot alter normal fire.
		return S.clientFireOrig(weaponRef, muzzleIndex, bulletIndex, origin, directions, options)
	end
	clientFire.fireVolley = S.clientFireWrapper
	Log.info("silent ClientFire.fireVolley wrapper installed")
	return true
end

--------------------------------------------------------------------------
-- Stance cycle — make C go Stand -> Crouch -> Prone -> Stand, so X is unused.
--
-- Keybinds are Roblox InputActions, not UserInputService:
--   Inputs.StanceContext.PositionDown = KeyCode.C   (properties.txt)
--   Inputs.StanceContext.PositionUp   = KeyCode.X
-- StanceController wires them straight through (0282:103-118):
--   PositionUp.Pressed -> StanceState.raise(), PositionDown -> .lower(),
--   both guarded by character:GetAttribute("Swimming") ~= true.
--
-- StanceState (0283) is a one-step machine with a 0.25 s cooldown (0283:73):
--   lower() 0283:129  { Walk->Crouch, Crouch->Prone }  refuses at Run/Prone
--   raise() 0283:113  { Prone->Crouch, Crouch->Walk }  refuses at Run/Walk,
--                     and refuses Prone->Crouch only when BOTH legs are dead
--                     (0283:236-274)
--
-- So at Prone the game's own C is ALREADY a no-op. We fill exactly that hole:
-- at Walk and Crouch we do nothing and let the game handle C normally (no
-- double-step, no race with its handler); at Prone we call raise() twice,
-- spaced past the cooldown. Rung 1-3: we listen to the game's own signal and
-- call the game's own public function, so every guard it applies still
-- applies and what replicates is identical to pressing X twice.
--------------------------------------------------------------------------
local function stanceState()
	local ok, mod = pcall(function()
		return require(ReplicatedStorage.Client.Character.stance.StanceState)
	end)
	if ok and type(mod) == "table" and type(mod.raise) == "function" then
		return mod
	end
	return nil
end

local function currentStance(state)
	if state and type(state.current) == "function" then
		local ok, v = pcall(state.current)
		if ok and type(v) == "string" then
			return v
		end
	end
	local char = LP.Character
	local cv = char and char:FindFirstChild("CharacterValues")
	local stance = cv and cv:FindFirstChild("Stance")
	return (stance and stance.Value) or "Walk"
end

-- StanceState's cooldown is task.delay(0.25, ...) (0283:73); leave slack.
local RAISE_GAP = 0.32

local function standUpFromProne()
	local state = stanceState()
	if not state then
		Log.warn("stance: StanceState unreachable")
		return
	end
	S.stanceSeq += 1
	local mySeq = S.stanceSeq

	local ok, err = pcall(state.raise)
	if not ok then
		Log.err("stance raise#1", err)
		return
	end
	Log.info("stance: prone -> " .. currentStance(state))

	task.delay(RAISE_GAP, function()
		if not S.alive or S.stanceSeq ~= mySeq then
			return
		end
		-- Only finish the cycle if step one actually landed. If the game
		-- refused (both legs dead, bandaging, carrying) stop, do not fight it.
		local now = currentStance(state)
		if now ~= "Crouch" then
			Log.info("stance: cycle stopped at " .. now)
			return
		end
		local ok2, err2 = pcall(state.raise)
		if ok2 then
			Log.info("stance: crouch -> " .. currentStance(state))
		else
			Log.err("stance raise#2", err2)
		end
	end)
end

local function onPositionDown()
	if not (S.alive and CFG.StanceCycle) then
		return
	end
	local char = LP.Character
	if not char then
		return
	end
	-- Mirrors StanceController's own guard at 0282:104.
	if char:GetAttribute("Swimming") == true then
		return
	end
	local stance = currentStance(stanceState())
	-- Walk and Crouch: the game's own C already steps down. Stay out of it.
	if stance ~= "Prone" then
		return
	end
	standUpFromProne()
end

--------------------------------------------------------------------------
-- ADS diagnostic (read-only). "Cannot scope in" was reported against
-- 2026-08-23.2 and nothing in the log covers it, so instead of guessing this
-- captures every value that gates ADS, once a second, only while RMB is held.
-- Aim = ReplicatedStorage.Inputs.WeaponContext.Aim, KeyCode.MouseRightButton
-- (properties.txt) -- the same button soft aim gates on, which is exactly why
-- this needs measuring rather than theorising.
--------------------------------------------------------------------------
local function adsProbe()
	if not CFG.AdsProbe then
		return
	end
	if not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
		return
	end
	local now = os.clock()
	if now - S.adsAt < 1 then
		return
	end
	S.adsAt = now

	local char = LP.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local cv = char and char:FindFirstChild("CharacterValues")
	local function val(name)
		local v = cv and cv:FindFirstChild(name)
		return v and tostring(v.Value) or "?"
	end

	local alpha, avail = "?", "?"
	pcall(function()
		local ac = require(ReplicatedStorage.Client.Tools.Weapon.controllers.AimController)
		alpha = string.format("%.2f", ac.getAlpha() or 0)
		avail = tostring(ac.isAimingAvailable())
	end)

	local ctxEnabled = "?"
	pcall(function()
		ctxEnabled = tostring(ReplicatedStorage.Inputs.WeaponContext.Enabled)
	end)

	local sel = "nil"
	pcall(function()
		local so = game:GetService("GuiService").SelectedObject
		sel = so and so:GetFullName() or "nil"
	end)

	Log.info(string.format(
		"ads | alpha=%s avail=%s ctx=%s stance=%s weaponAction=%s unconscious=%s "
			.. "move=%.2f ws=%.1f tool=%s behavior=%s guiSel=%s softaim=%s",
		alpha, avail, ctxEnabled, val("Stance"), val("WeaponAction"), val("Unconscious"),
		hum and hum.MoveDirection.Magnitude or -1,
		hum and hum.WalkSpeed or -1,
		tostring(char and char:FindFirstChildOfClass("Tool") and char:FindFirstChildOfClass("Tool").Name),
		tostring(UserInputService.MouseBehavior),
		sel, tostring(CFG.SoftAim)
	))
end

--------------------------------------------------------------------------
-- Paint — the only per-frame draw work. One WorldToViewportPoint per target.
--------------------------------------------------------------------------
local function paint()
	if not S.alive then
		return
	end
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local viewport = camera.ViewportSize
	local center = viewport * 0.5
	local camPos = camera.CFrame.Position
	-- Roblox FieldOfView is vertical; this converts world studs to pixels.
	local pxPerStudAt1 = viewport.Y / (2 * math.tan(math.rad(camera.FieldOfView) * 0.5))
	local maxDist = CFG.MaxDist

	for _, entry in ipairs(S.roster) do
		entry.screen = nil
		local hrp = entry.hrp
		if hrp and hrp.Parent then
			local pos = hrp.Position
			local dist = (pos - camPos).Magnitude
			if dist <= maxDist then
				local sp, onScreen = camera:WorldToViewportPoint(pos)
				if onScreen and sp.Z > 0.5 then
					entry.screen = Vector2.new(sp.X, sp.Y)
					local foe = entry.foe
					local names = foe and CFG.EnemyNames or CFG.AllyNames
					local bars = foe and CFG.EnemyHealth or CFG.AllyHealth
					local dists = foe and CFG.EnemyDistance or false
					local show = names or bars or dists
					if show then
						local h = (5.6 * pxPerStudAt1) / sp.Z
						local w = h * 0.5
						local x, y = sp.X - w * 0.5, sp.Y - h * 0.5
						local color = entry.downed and C_DOWN or (foe and C_FOE or C_ALLY)

						if bars then
							local hp, maxHp = limbHealth(entry.torso)
							if hp then
								drawHealth(x, y, h, hp / maxHp)
							end
						end
						if names then
							drawText(sp.X, y - 15, entry.downed and (entry.name .. " [DOWN]") or entry.name, C_TEXT)
						end
						if dists then
							drawText(sp.X, y + h + 2, string.format("%dm", math.floor(dist / 3.57)), color)
						end
					end
				end
			end
		end
	end

	if (CFG.SoftAim or CFG.SilentAim) and CFG.ShowAimFov then
		DI.Circle(center, CFG.AimFov, C_FOE, 0.45, 48, 1)
	end

	adsProbe()
	softAimStep(camera, center)
end

--------------------------------------------------------------------------
-- UI
--------------------------------------------------------------------------
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

local ROW_H = 22
local function header(parent, y, text)
	mk("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 10, 0, y + 4),
		Size = UDim2.new(1, -20, 0, 14),
		Font = Enum.Font.GothamBold, TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = COL.dim, Text = string.upper(text),
	}, parent)
	return y + 20
end

local function addRow(parent, y, label, key, extra)
	mk("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 10, 0, y),
		Size = UDim2.new(1, -78, 0, 18),
		Font = Enum.Font.GothamMedium, TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = COL.text, Text = label,
	}, parent)
	local btn = mk("TextButton", {
		Position = UDim2.new(1, -66, 0, y),
		Size = UDim2.fromOffset(52, 18),
		BorderSizePixel = 0, Font = Enum.Font.GothamBold, TextSize = 11,
		AutoButtonColor = false, Text = "",
	}, parent)
	mk("UICorner", { CornerRadius = UDim.new(0, 3) }, btn)
	paintToggle(btn, CFG[key])
	btn.MouseButton1Click:Connect(function()
		CFG[key] = not CFG[key]
		paintToggle(btn, CFG[key])
		if extra then
			local adjusted = extra(CFG[key])
			if type(adjusted) == "boolean" then
				CFG[key] = adjusted
				paintToggle(btn, adjusted)
			end
		end
		saveConfig()
	end)
	return y + ROW_H
end

local function addCycleRow(parent, y, label, key, options, extra)
	mk("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 10, 0, y),
		Size = UDim2.new(1, -90, 0, 18),
		Font = Enum.Font.GothamMedium, TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = COL.text, Text = label,
	}, parent)
	local btn = mk("TextButton", {
		Position = UDim2.new(1, -78, 0, y), Size = UDim2.fromOffset(64, 18),
		BorderSizePixel = 0, BackgroundColor3 = COL.off, TextColor3 = COL.text,
		Font = Enum.Font.GothamBold, TextSize = 11,
		AutoButtonColor = false, Text = tostring(CFG[key]),
	}, parent)
	mk("UICorner", { CornerRadius = UDim.new(0, 3) }, btn)
	btn.MouseButton1Click:Connect(function()
		local at = 1
		for i, opt in ipairs(options) do
			if opt == CFG[key] then
				at = i
				break
			end
		end
		CFG[key] = options[at % #options + 1]
		btn.Text = CFG[key]
		if extra then
			extra(CFG[key])
		end
		saveConfig()
	end)
	return y + ROW_H
end

local function addStepRow(parent, y, label, key, step, fmt, extra)
	mk("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 10, 0, y),
		Size = UDim2.fromOffset(104, 18),
		Font = Enum.Font.GothamMedium, TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = COL.text, Text = label,
	}, parent)
	local value = mk("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(1, -96, 0, y),
		Size = UDim2.fromOffset(44, 18),
		Font = Enum.Font.GothamBold, TextSize = 11,
		TextColor3 = COL.dim, Text = string.format(fmt, CFG[key]),
	}, parent)
	local function bump(delta)
		local nv = CFG[key] + delta
		if VALIDATORS[key](nv) then
			CFG[key] = nv
			value.Text = string.format(fmt, nv)
			if extra then
				extra(nv)
			end
			saveConfig()
		end
	end
	local minus = mk("TextButton", {
		Position = UDim2.new(1, -50, 0, y), Size = UDim2.fromOffset(20, 18),
		BorderSizePixel = 0, BackgroundColor3 = COL.off, TextColor3 = COL.text,
		Font = Enum.Font.GothamBold, TextSize = 12, AutoButtonColor = false, Text = "-",
	}, parent)
	local plus = mk("TextButton", {
		Position = UDim2.new(1, -26, 0, y), Size = UDim2.fromOffset(20, 18),
		BorderSizePixel = 0, BackgroundColor3 = COL.off, TextColor3 = COL.text,
		Font = Enum.Font.GothamBold, TextSize = 12, AutoButtonColor = false, Text = "+",
	}, parent)
	mk("UICorner", { CornerRadius = UDim.new(0, 3) }, minus)
	mk("UICorner", { CornerRadius = UDim.new(0, 3) }, plus)
	minus.MouseButton1Click:Connect(function() bump(-step) end)
	plus.MouseButton1Click:Connect(function() bump(step) end)
	return y + ROW_H
end

local function addSliderRow(parent, y, label, key, minValue, maxValue, step, fmt, extra)
	mk("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 10, 0, y), Size = UDim2.fromOffset(94, 18),
		Font = Enum.Font.GothamMedium, TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = COL.text, Text = label,
	}, parent)
	local bar = mk("TextButton", {
		Position = UDim2.new(0, 106, 0, y + 5), Size = UDim2.fromOffset(72, 8),
		BackgroundColor3 = COL.off, BorderSizePixel = 0,
		AutoButtonColor = false, Text = "", Active = true,
	}, parent)
	mk("UICorner", { CornerRadius = UDim.new(1, 0) }, bar)
	local fill = mk("Frame", {
		Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = COL.on,
		BorderSizePixel = 0,
	}, bar)
	mk("UICorner", { CornerRadius = UDim.new(1, 0) }, fill)
	local value = mk("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(1, -48, 0, y), Size = UDim2.fromOffset(42, 18),
		Font = Enum.Font.GothamBold, TextSize = 11,
		TextColor3 = COL.dim, Text = "",
	}, parent)
	local pending = CFG[key]
	local function preview(v)
		pending = math.clamp(math.floor((v / step) + 0.5) * step, minValue, maxValue)
		fill.Size = UDim2.new((pending - minValue) / (maxValue - minValue), 0, 1, 0)
		value.Text = string.format(fmt, pending)
	end
	local function fromX(x)
		local alpha = math.clamp((x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
		preview(minValue + (maxValue - minValue) * alpha)
	end
	local function commit()
		if CFG[key] == pending then return end
		CFG[key] = pending
		if extra then extra(pending) end
		saveConfig()
	end
	preview(CFG[key])
	local dragging = false
	bar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			fromX(input.Position.X)
		end
	end)
	S.conns["sliderMove_" .. key] = UserInputService.InputChanged:Connect(function(input)
		if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			fromX(input.Position.X)
		end
	end)
	S.conns["sliderEnd_" .. key] = UserInputService.InputEnded:Connect(function(input)
		if dragging and input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = false
			commit()
		end
	end)
	return y + ROW_H
end

local function buildUI()
	local parent = getParent()
	local hostIsLayer = typeof(parent) == "Instance" and parent:IsA("LayerCollector")
	if hostIsLayer and parent:IsA("ScreenGui") then
		S.uiHost = parent
		S.uiHostDisplayOrder = parent.DisplayOrder
		parent.DisplayOrder = 2147483647
		if typeof(gethiddenproperty) == "function" and typeof(sethiddenproperty) == "function" then
			local ok, oldValue = pcall(gethiddenproperty, parent, "OnTopOfCoreBlur")
			if ok then
				S.uiHostOnTop = oldValue
				S.uiHostOnTopKnown = true
				pcall(sethiddenproperty, parent, "OnTopOfCoreBlur", true)
			end
		end
	end
	if ESP.folderName then
		local old = parent:FindFirstChild(ESP.folderName)
		if old then
			old:Destroy()
		end
	end
	ESP.folderName = blandName("UI")
	S.folder = mk("Folder", { Name = ESP.folderName }, parent)

	local guiParent = S.folder
	-- Potassium gethui() returns a ScreenGui — never nest another one under it.
	if not hostIsLayer then
		guiParent = mk("ScreenGui", {
			Name = blandName("SG"), ResetOnSpawn = false,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 55,
		}, S.folder)
	end

	local root = mk("Frame", {
		Size = UDim2.fromOffset(230, 400),
		Position = UDim2.new(CFG.UiXScale, CFG.UiXOffset, CFG.UiYScale, CFG.UiYOffset),
		BackgroundColor3 = COL.bg, BackgroundTransparency = 0.04,
		BorderSizePixel = 0, Active = true, Visible = CFG.UiVisible,
	}, guiParent)
	S.root = root
	mk("UICorner", { CornerRadius = UDim.new(0, 6) }, root)
	mk("UIStroke", { Color = COL.stroke, Thickness = 1 }, root)
	if HOST then
		root.Position = UDim2.new()
		root.Visible = true
		root.Parent = HOST.host
		-- Our own teardown destroys S.folder; ride that signal so a reparented panel
		-- can never outlive the module inside the hub.
		S.folder.Destroying:Connect(function() pcall(function() root:Destroy() end) end)
	end

	if not HOST then
		local dragging, start, startPos
		root.InputBegan:Connect(function(input)
			-- Header-only drag keeps slider gestures from moving the whole panel.
			if input.UserInputType == Enum.UserInputType.MouseButton1
				and input.Position.Y <= root.AbsolutePosition.Y + 42 then
				dragging = true
				start = input.Position
				startPos = root.Position
				input.Changed:Connect(function()
					if input.UserInputState == Enum.UserInputState.End then
						dragging = false
						CFG.UiXScale = root.Position.X.Scale
						CFG.UiXOffset = root.Position.X.Offset
						CFG.UiYScale = root.Position.Y.Scale
						CFG.UiYOffset = root.Position.Y.Offset
						saveConfig()
					end
				end)
			end
		end)
		S.conns.drag = UserInputService.InputChanged:Connect(function(input)
			if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
				local d = input.Position - start
				root.Position = UDim2.new(
					startPos.X.Scale, startPos.X.Offset + d.X,
					startPos.Y.Scale, startPos.Y.Offset + d.Y
				)
			end
		end)
	end

	mk("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 10, 0, 8), Size = UDim2.new(1, -20, 0, 16),
		Font = Enum.Font.GothamBold, TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = COL.text, Text = "COLD WAR  " .. BUILD_VERSION,
	}, root)
	mk("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 10, 0, 25), Size = UDim2.new(1, -20, 0, 12),
		Font = Enum.Font.Gotham, TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = COL.dim, Text = "RShift hide | K unload | RMB soft aim",
	}, root)

	local scroll = mk("ScrollingFrame", {
		Position = UDim2.new(0, 0, 0, 42),
		Size = UDim2.new(1, 0, 1, -48),
		BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = COL.stroke,
		-- Active=true or the wheel never reaches it (check_hub R13).
		Active = true, ScrollingDirection = Enum.ScrollingDirection.Y,
		CanvasSize = UDim2.fromOffset(0, 0),
	}, root)

	local y = 4
	y = header(scroll, y, "Enemies")
	y = addRow(scroll, y, "Chams (outline)", "EnemyChams", updateChams)
	y = addRow(scroll, y, "Names", "EnemyNames")
	y = addRow(scroll, y, "Health bars", "EnemyHealth")
	y = addRow(scroll, y, "Distance", "EnemyDistance")

	y = header(scroll, y, "Allies")
	y = addRow(scroll, y, "Chams (outline)", "AllyChams", updateChams)
	y = addRow(scroll, y, "Names", "AllyNames")
	y = addRow(scroll, y, "Health bars", "AllyHealth")

	y = header(scroll, y, "Render distance")
	y = addStepRow(scroll, y, "Max dist", "MaxDist", 128, "%d")

	y = header(scroll, y, "Soft aim")
	y = addRow(scroll, y, "Enable (hold RMB)", "SoftAim", function(on)
		Log.info("soft aim toggle=" .. tostring(on))
		if not on then
			S.stickyPlayer = nil
		end
	end)
	y = addCycleRow(scroll, y, "Aim part", "AimPart", { "Head", "Torso", "Closest" }, function(v)
		S.stickyPlayer = nil
		Log.info("aim part=" .. v)
	end)
	y = addRow(scroll, y, "Drop + lead comp", "Ballistics")
	y = addRow(scroll, y, "Show FOV ring", "ShowAimFov")
	y = addSliderRow(scroll, y, "Shared FOV (px)", "AimFov", 10, 2400, 10, "%d")
	y = addStepRow(scroll, y, "Strength %", "AimStrength", 5, "%d")
	y = addStepRow(scroll, y, "Max step px", "AimMaxStepPx", 2, "%d")
	y = addRow(scroll, y, "Silent redirect", "SilentAim", function(on)
		if on then
			if not installSilentAim() then
				Log.info("silent aim toggle=false")
				return false
			end
		else
			restoreSilentAim()
		end
		Log.info("silent aim toggle=" .. tostring(CFG.SilentAim))
		return on
	end)
	y = addStepRow(scroll, y, "Silent max angle", "SilentMaxAngle", 1, "%d°")

	y = header(scroll, y, "Recoil / speed")
	y = addStepRow(scroll, y, "Recoil cut %", "RecoilCut", 10, "%d", function(nv)
		if nv > 0 then
			installRecoil()
		end
		Log.info("recoil cut=" .. tostring(nv) .. "%")
	end)
	y = addStepRow(scroll, y, "Speed %", "SpeedBoost", 5, "%d", function(nv)
		Log.info("speed boost=" .. tostring(nv) .. "%")
	end)
	y = addSliderRow(scroll, y, "Vehicle speed", "VehicleSpeed", 100, 300, 10, "%d%%", function()
		applyVehicleSpeed()
	end)
	y = addRow(scroll, y, "ADS diagnostic", "AdsProbe")

	y = header(scroll, y, "Movement")
	y = addRow(scroll, y, "C cycles stance", "StanceCycle", function(on)
		Log.info("stance cycle=" .. tostring(on))
	end)

	scroll.CanvasSize = UDim2.fromOffset(0, y + 8)

	mk("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 10, 1, -16), Size = UDim2.new(1, -20, 0, 12),
		Font = Enum.Font.Gotham, TextSize = 9,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = COL.dim, Text = "speed, vehicles + recoil are visible to others",
	}, root)
end

--------------------------------------------------------------------------
-- Teardown — every touched thing restored (potassium-dev §5.5)
--------------------------------------------------------------------------
local function teardown()
	S.alive = false
	restoreSilentAim()
	restoreVehicleSpeed()
	if S.speedBind then
		pcall(function() RunService:UnbindFromRenderStep(S.speedBind) end)
		S.speedBind = nil
	end
	restoreRecoil()
	for _, c in pairs(S.conns) do
		pcall(function() c:Disconnect() end)
	end
	S.conns = {}
	for _, c in pairs(S.charConns) do
		pcall(function() c:Disconnect() end)
	end
	S.charConns = {}
	wipeChams()
	S.roster = {}
	S.entryOf = {}
	S.stickyPlayer = nil
	if S.folder then
		pcall(function() S.folder:Destroy() end)
		S.folder = nil
	end
	if S.uiHost and S.uiHost.Parent then
		pcall(function() S.uiHost.DisplayOrder = S.uiHostDisplayOrder end)
		if S.uiHostOnTopKnown and typeof(sethiddenproperty) == "function" then
			pcall(sethiddenproperty, S.uiHost, "OnTopOfCoreBlur", S.uiHostOnTop)
		end
	end
	S.uiHost = nil
	S.root = nil
	GENV[GKEY] = nil
	Log.info("unloaded build=" .. BUILD_VERSION)
end

--------------------------------------------------------------------------
-- Boot
--------------------------------------------------------------------------
local okMain, errMain = xpcall(function()
	if type(DI) ~= "table" or type(DI.Rectangle) ~= "function" then
		error("DrawingImmediate unavailable on this executor build", 0)
	end

	installVehicleSpeed()

	-- Resume the saved arm state BEFORE the panel is built, so every toggle
	-- paints the state it actually resumed into. The vehicle wrapper re-applies
	-- the saved multiplier as each drive object is built, so only silent
	-- redirection needs arming here.
	if CFG.SilentAim then
		if installSilentAim() then
			Log.info("resumed silent redirect ON from saved config")
		else
			CFG.SilentAim = false
			Log.warn("resume: silent adapter unavailable, silent left OFF")
		end
	end

	buildUI()
	rebuildRoster()

	S.conns.paint = DI.GetPaint(1):Connect(function()
		local ok, err = pcall(paint)
		if not ok and os.clock() - S.errAt > 5 then
			S.errAt = os.clock()
			Log.err("paint", err)
		end
	end)

	-- MovementTuning writes WalkSpeed at RenderPriority.Character (0282:338);
	-- +1 puts our scale strictly after it, so we never fight for the value.
	S.speedBind = "CW_" .. blandName("S")
	RunService:BindToRenderStep(S.speedBind, Enum.RenderPriority.Character.Value + 1, function()
		if not S.alive then
			return
		end
		local ok, err = pcall(speedStep)
		if not ok and os.clock() - S.errAt > 5 then
			S.errAt = os.clock()
			Log.err("speed", err)
		end
	end)

	S.conns.hb = RunService.Heartbeat:Connect(function(dt)
		if not S.alive then
			return
		end
		S.rosterAcc += dt
		if S.rosterAcc >= CFG.RosterHz then
			S.rosterAcc = 0
			local ok, err = pcall(rebuildRoster)
			if not ok then
				Log.err("roster", err)
			end
		end
	end)

	S.conns.input = UserInputService.InputBegan:Connect(function(input, gp)
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

	local function bindTeam(plr)
		if S.charConns[plr] then
			S.charConns[plr]:Disconnect()
		end
		S.charConns[plr] = plr:GetPropertyChangedSignal("Team"):Connect(function()
			task.defer(function()
				if S.alive then
					pcall(rebuildRoster)
				end
			end)
		end)
	end

	-- Bind the stance cycle off the main path: Inputs is a WaitForChild away
	-- and must never delay the ESP arming.
	task.spawn(function()
		local ok, err = pcall(function()
			local inputs = ReplicatedStorage:WaitForChild("Inputs", 30)
			local ctx = inputs and inputs:WaitForChild("StanceContext", 30)
			local down = ctx and ctx:WaitForChild("PositionDown", 30)
			if not down then
				error("Inputs.StanceContext.PositionDown not found", 0)
			end
			if not S.alive then
				return
			end
			-- Bound to the InputAction, not KeyCode.C, so a rebind in the
			-- game's own settings keeps working.
			S.conns.stance = down.Pressed:Connect(function()
				local okDown, errDown = pcall(onPositionDown)
				if not okDown then
					Log.err("onPositionDown", errDown)
				end
			end)
			Log.info("stance cycle bound (C cycles, X unused)")
		end)
		if not ok then
			Log.err("stance bind", err)
		end
	end)

	S.conns.playerAdded = Players.PlayerAdded:Connect(bindTeam)
	S.conns.playerRemoving = Players.PlayerRemoving:Connect(function(plr)
		if S.charConns[plr] then
			S.charConns[plr]:Disconnect()
			S.charConns[plr] = nil
		end
		S.entryOf[plr] = nil
		if S.stickyPlayer == plr then
			S.stickyPlayer = nil
		end
	end)
	for _, plr in ipairs(Players:GetPlayers()) do
		bindTeam(plr)
	end

	ESP.destroy = teardown
	ESP.rebuild = rebuildRoster
	ESP.saveConfig = saveConfig

	local foes = 0
	for _, e in ipairs(S.roster) do
		if e.foe then
			foes += 1
		end
	end

	Log.session(string.format(
		"armed build=%s place=%s myTeam=%s roster=%d foes=%d players=%d softaim=%s silent=%s recoilCut=%d speed=%d vehicle=%d",
		BUILD_VERSION, tostring(game.PlaceId), tostring(teamName(LP)),
		#S.roster, foes, #Players:GetPlayers(),
		tostring(CFG.SoftAim), tostring(CFG.SilentAim), CFG.RecoilCut, CFG.SpeedBoost, CFG.VehicleSpeed
	))
end, debug.traceback)

if not okMain then
	Log.err("boot failed", errMain)
	pcall(teardown)
end
