-- Illegal Soccer Hub v2026-09-10.18 (2026-09-09)
-- Rungs 3-5. Every feature edits a CLIENT-side table the game's own code reads;
-- none constructs or fires a remote. The action command shape on the wire is
-- unchanged -- only the values the client had already decided differ.
--   Stamina  : Sprint.SetUnlimitedStamina is the game's own API (0139.lua:702),
--              already used by the goalkeeper zone (0134.lua:406) and the lobby
--              (0077.lua:1849). The gate it feeds is client-side (0139.lua:636).
--   Mobility : ChargingWalkSpeedMultiplier (0284.lua:15) and the "TackleKick"
--              WalkSpeed multiplier (0067.lua:201) are applied by our own client
--              via Movement.SetMultiplier (0136.lua:1162). Live-measured
--              2026-09-09: ws 8.00 -> 3.60 for ~0.2s after every kick.
--   Boxes    : read-only. Item box CLAIMS ARE SERVER-SIDE -- ItemCommands.Kinds
--              (0411.lua:11) has no claim kind, so pickup range CANNOT be
--              extended. This draws them and calls them out instead.
-- Telemetry is always on and cannot be turned off: it logs every server
-- ExecuteRejected/StartRejected and every MovementCorrection to
-- logs/illegal_soccer_hub.log. Baseline measured on this account 2026-09-09 with
-- nothing armed: 0 corrections and 0 cooldown rejects in 75s of play.
-- NOT INCLUDED, and why (dump-proved, do not re-propose):
--   dribble/steal/flick cooldown removal -- the client ALREADY subtracts the
--     0.15s grace (GetEnforcedSeconds, 0062.lua:24 / 0068.lua:33 / 0061.lua:56),
--     the server holds the clock and re-quotes it on reject. Zero slack exists.
--   pass cooldown -- there already is none (UseCooldown=false, 0066.lua:1177).
--   dribble/steal cooldown BYPASS -- built, tested, DISPROVED 2026-09-09: the
--     client gate is bypassable but the server re-quotes its own clock and
--     rejected 30/30 early actions. Removed. Do not rebuild it.
--   auto-pickup range -- no client claim exists at all (see Boxes above).
--   shot power and charge timing -- max power, instant charge and instant
--     release were all built and all REMOVED in .18 at the user's call. Max
--     power did work (123.00 studs/s, the game's own Shot.MaximumSpeed, measured
--     41 times) but it bought nothing that mattered: the wait is StartCharge's
--     own task.delay(MaximumChargeSeconds) auto-release (0061.lua:1005), and
--     shrinking that constant is a trap -- the asserted ChargeSeconds is
--     Min + (Max-Min)*alpha (0303.lua:61), so it IS the 0.4 that earns the 123.
--     Cut it and the server returns the 70 floor instead. If this is ever
--     revisited, that is the fact to start from, and the answer is not the
--     constants table.
-- HUB-ONLY: refuses to build a standalone window. Mounts via hub.lua only.
-- Re-inject safe: self-teardown restores every patched field, ownership-checked.
-- K = panic unload (everything off, originals restored).
--   AutoDrib : reacts to an incoming steal inside its 270ms windup. Detection is
--              the game's own SlidingUntilChanged signal (0311.lua:154, written
--              when our client handles the TackleStarted effect at 0069.lua:1942)
--              plus the replicated SlidingUntil attribute. The hitbox time is
--              CharacterAuras' own arithmetic (0075.lua:465). Firing calls
--              Dodge.HandleInputBegan (0062.lua:258) with a synthetic input
--              table -- it reads only .KeyCode/.UserInputState/.UserInputType --
--              so the game sends its normal Dodge command. No hook, no remote.
--              BOOTS OFF AND OBSERVE-ONLY: the server's evade window is unproven.
--   AutoSprint: one toggle, one call. Sprint.ToggleSprintButton (0139.lua:612)
--              flips the on-screen sprint button's own boolean into
--              SetHeld(u6 or u7 or u8) -- the same latch the keyboard writes --
--              and nothing clears it except a settings change or PreferredInput
--              leaving Touch, both re-latched on the 0.5s tick. So sprint is
--              held forever through the game's own public API. You still only
--              sprint while moving and still pay stamina; that is the
--              controller's arithmetic and we do not touch it.
-- Changelog: .21 stop teardown from persisting its own stopped state. Every
--               remount was writing walkSpeed 1 / chargeSpeed 0.5 / dips off
--               over the real config, because stopFeatures neutralises cfg and
--               the 0.5s debounced save landed after it.
--            .20 auto-sprint rewritten onto ToggleSprintButton. The .19 build
--               guessed at SetSprinting / Start+Stop / HandleInputBegan and
--               found none of them -- the controller owns its own UIS
--               connections (0139.lua:462/475) and the key only ever writes a
--               boolean, so there was never an input to synthesise. Logged
--               "no sprint entry point" and did nothing.
--            .19 auto-sprint toggle (broken, see .20).
--            .18 remove the whole shot-power branch at the user's call -- max
--               power, instant charge and instant release, plus the shot-speed
--               readback, the press->launch timing and the ActionRemoteProtocol
--               leg timestamps that existed only to diagnose them. KickCore,
--               KickPowerups, Shoot and ActionRemoteProtocol are no longer
--               required at all; the only survivor of that code is the ball
--               ownership tracker, which auto-dribble needs. Nothing in the game
--               is patched by this module's shooting path any more.
--            .17 instant shot release.
--            .16 split that lag into legs. .15 measured the shot leaving ~0.45s
--               after the press REGARDLESS of hold (0.062 held -> 0.451; 0.432
--               held -> 0.461), which kills "you are holding the button" and
--               points at something fixed near MaximumChargeSeconds 0.4. But
--               that 0.45 is measured to the SERVER Ball.State, so it stacks
--               press->Start, Start->Release (ours) and Release->wire. Only the
--               middle leg is patchable. Pass-through timestamps on
--               ActionRemoteProtocol.Start/Release (0285.lua:168/279) -- plain
--               module functions, the same wrap already used on KickCore, no
--               __namecall, no remote touched, no argument changed.
--            .15 press->launch timing, because "max power works" and "I still
--               have to wait for the charge" were both true and no counter here
--               could tell them apart -- a shot held to full and a shot fired
--               instantly BOTH read exactly 123.00 studs/s. Now logged per shot:
--               hold (m1 down -> m1 up, yours), lag (m1 down -> the server's
--               launch), and the difference, which is what the game added after
--               you let go. Plus hooked= (are our two patches still the
--               functions the game calls) and powerup= next to them.
--               Also closes a real hole in both shot hooks: they matched the
--               constants table by identity against KickCore.Constants, which is
--               correct -- Shoot.Constants.Kick IS that table (0309.lua:21) --
--               until a kick powerup is live, at which point
--               KickPowerups.GetChargeConstants hands ChargedKick a CLONE
--               (0304.lua:186) and both patches silently stop applying for the
--               powerup's duration. Now resolved through the game's own accessor.
--            .14 knockback readback. Max power was never the problem -- the .13
--               log shows 6 of 7 shots leaving at exactly 123.00, the game's own
--               Shot.MaximumSpeed, and the knockback animation is already at full
--               strength by 75 (0138.lua:24). What was missing was any way to see
--               whether those shots put anyone on the floor. A knockdown is a
--               SERVER decision broadcast as the ViolenceKnockback effect
--               (0069.lua:1906) -- Remotes.Ball.ViolenceDash is receive-only on
--               our side (0141.lua:184 is its only use in 528 scripts) and
--               nothing in ReplicatedStorage computes it -- so this counts them
--               read-only: total, ours, ones landed on us, and forcefield blocks
--               next to them. Paired with the shot row it separates "the shot was
--               weak" from "the ball never hit anyone".
--            .13 movement pass. Walk speed slider (ActionMovement.Constants.
--               BaseWalkSpeed, 1.00-1.15x, boots at stock) -- the ONLY feature
--               in this module the server can see, gated on the correction
--               counter that was already running. The post-kick dip hook now
--               covers every move-applied WalkSpeed multiplier, not just
--               TackleKick: SlideTackle, GoalkeeperDive, ShotgunRecoil and
--               ItemZoom are the same u4 table and the same one-key drop.
--               Dribble is separate -- it is a STANDARD (0062.lua:123) and
--               getStandardValue takes the minimum, so it beats Sprint's own
--               entry -- and gets its own toggle. Ball-carrier penalty (0.9x
--               jog / 0.8x run) gets a third. Not touched, deliberately:
--               SetMinimum("SlideTackle", {WalkSpeed = 0.1}) is the slide lock,
--               not a recovery penalty.
--            .12 red ball chams. The visible ball is the skin MODEL parented to
--               the invisible ClientBall_ part (0072.lua:120/160), so the
--               Highlight adorns the model -- adorning the part outlines a cube.
--               Parented to the ball part like the game's own skin Highlight
--               (0322.lua:192); no CoreGui, no per-frame work.
--            .11 auto-dribble (F8), off and observe-only by default, with the
--               counters that decide whether it works: tackles seen, how many
--               while we held the ball, how many the hitbox predictor said would
--               connect, dodges fired vs accepted vs gate-refused, and ball
--               kept/lost after each hitbox window. Observe mode measures the
--               do-nothing baseline so "armed" has something to beat.
--            .10 the .9 readback over-counted CLAMPED. LastKickKind persists on
--               the ball, so every bounce re-emitted state tagged as our shot with
--               a decayed InitialVelocity; and Tackle/RainbowFlick launches were
--               being scored against the shot band they do not use. Now: shots
--               only, launches only (a bounce restate carries no ActionId).
--            .9 shot-speed readback. "No reject" never proved max power / instant
--               charge LANDED -- a silent server clamp looks identical from the
--               reject counter. Remotes.Ball.State carries InitialVelocity and
--               LastKickerUserId (0077.lua:1023 buildReceivedState, connected at
--               0077.lua:2183), so the server's own launch speed for OUR kick is
--               readable. Band: 70 min .. 123 max (0309.lua:23), speed =
--               GetChargedSpeed(alpha^1.6) (0303.lua:107). Also stops returning
--               alpha 1 for a nil constants table -- GetChargedSpeed defaults to
--               the shot constants for EVERY actor, so the old hook inflated the
--               predicted speed of other players' shots too and made their balls
--               rubber-band when the real state arrived.
--            .8 live stamina readback in the panel -- a torn-down module used to
--               be indistinguishable from a broken feature.
--            .7 remove the cooldown bypass -- server rejected 30/30. Measured.
--            .6 hub-only; never builds a standalone panel.
--            .5 add instant charge and an experimental dribble/steal cooldown
--               bypass; both boot OFF and are measured by the reject counter.
--            .4 box markers parent to the box, not CoreGui -- the hub mount
--               thread cannot touch CoreGui. Per-feature isolation on apply.
--            .3 arm features AFTER the panel exists; a mid-build failure no
--               longer leaves the backend patched with no control to undo it.
--            .2 resolve r3st_ui.lua from the workspace root; ".." is sandboxed.
--            .1 first build -- stamina, max power, charge mobility, box ESP.

local BUILD_VERSION = "2026-09-10.21"
local EXPECTED_PLACE = 126987974021910
local EXPECTED_GAME = 10155360168
local GKEY = "__ILLEGALSOCCER"
local CONFIG_FILE = "illegal_soccer_hub_config.json"

if game.GameId ~= EXPECTED_GAME and game.PlaceId ~= EXPECTED_PLACE then return end

local G = getgenv()
if G[GKEY] and G[GKEY].destroy then pcall(G[GKEY].destroy) end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")
local CoreGui = game:GetService("CoreGui")
local LP = Players.LocalPlayer
local HOST = type(G.__R3ST_HOST) == "table" and G.__R3ST_HOST or nil

local function fallbackLog(level, message)
	pcall(function()
		local path = "logs/illegal_soccer_hub.log"
		local old = isfile and isfile(path) and readfile(path) or ""
		writefile(path, old .. os.date("[%Y-%m-%d %H:%M:%S] ") .. level .. " " .. tostring(message) .. "\n")
	end)
end
local Log = { info = function(m) fallbackLog("INFO", m) end, warn = function(m) fallbackLog("WARN", m) end }
pcall(function() Log = loadfile("log.lua")()("illegal_soccer_hub") end)

--=====================================================================
-- config
--=====================================================================
local defaults = {
	infStamina = false,
	chargeSpeed = 0.5,   -- 0.5 = stock ChargingWalkSpeedMultiplier
	noKickDip = false,
	walkSpeed = 1,       -- 1.00 = stock ActionMovement BaseWalkSpeed (16)
	noCarrierDip = false,
	noDribbleDip = false,
	autoSprint = false,
	boxEsp = false,
	ballCham = false,
	-- auto-dribble (F8). Boots OFF and OBSERVE, so the first session only
	-- measures: how often we see a tackle, how much lead we get, and whether the
	-- predictor agrees with what actually happened.
	autoDribble = false,
	adObserve = true,
	adOnlyIfHit = true,
	adOffset = 0.08,   -- fire this many seconds BEFORE the hitbox goes live
	adJitter = 0.03,   -- +/- randomisation so the timing is not machine-perfect
}
local cfg = table.clone(defaults)
do
	local ok, raw = pcall(readfile, CONFIG_FILE)
	if ok then
		local ok2, saved = pcall(HttpService.JSONDecode, HttpService, raw)
		if ok2 and type(saved) == "table" then
			for key, fallback in next, defaults do
				if typeof(saved[key]) == typeof(fallback) then cfg[key] = saved[key] end
			end
		end
	end
end
cfg.chargeSpeed = math.clamp(cfg.chargeSpeed, 0.5, 1)
cfg.walkSpeed = math.clamp(cfg.walkSpeed, 1, 1.15)
cfg.adOffset = math.clamp(cfg.adOffset, 0, 0.25)
cfg.adJitter = math.clamp(cfg.adJitter, 0, 0.08)

-- teardownSaveLock: stopFeatures() neutralises cfg -- every toggle off, every
-- slider back to stock -- so ANY save after it writes those stopped values over
-- the user's real settings. A save is debounced 0.5s, and an unmount lands
-- inside that window, so this happened on every remount: measured 2026-09-10,
-- config on disk came back walkSpeed 1 / chargeSpeed 0.5 / every dip false
-- while the boot line 33 seconds earlier read ws=1.08 dip=true drib=true.
-- Once teardown starts, nothing more is persisted.
local savePending = false
local teardownSaveLock = false
local function saveConfig()
	if savePending or teardownSaveLock then return end
	savePending = true
	task.delay(0.5, function()
		savePending = false
		if teardownSaveLock then return end
		local ok, raw = pcall(HttpService.JSONEncode, HttpService, cfg)
		if ok then pcall(writefile, CONFIG_FILE, raw) end
	end)
end

--=====================================================================
-- state
--=====================================================================
local state = {
	alive = true, conns = {}, screen = nil, panel = nil,
	rejects = 0, corrections = 0, maxSnap = 0, lastReject = "none",
	boxes = 0, status = "Ready", armed = false, chamOn = false,
	-- auto-dribble telemetry
	adSeen = 0,          -- tackles detected at all
	adOnUs = 0,          -- ...while we owned the ball
	adPredHit = 0,       -- ...and the predictor said it would connect
	adFired = 0,         -- dodges we actually triggered
	adStarted = 0,       -- ...that the game accepted (Dribbling went true)
	adBlocked = 0,       -- ...that a gate refused (cooldown, airborne, stamina)
	adSaved = 0, adLost = 0,   -- kept / lost the ball after the hitbox window
	adLastLead = -1,     -- seconds of warning on the last detection
	adMinLead = 99, adLastWhy = "none", adKeyOk = false, adKey = "?",
	-- auto-sprint
	sprintPath = "unresolved", sprintHeld = false,
	ballOwner = nil,
	-- knockback readback (see armKnockbackReadback). "Did my 123 studs/s shot
	-- actually put anyone on the floor" is a SERVER answer and this is where it
	-- arrives -- the ViolenceKnockback effect is broadcast, never claimed.
	knockTotal = 0, knockByUs = 0, knockOnUs = 0, knockShielded = 0,
	lastKnockMag = -1, lastKnock = "none", knockNames = {},
}
local function connect(signal, fn)
	local c = signal:Connect(fn)
	state.conns[#state.conns + 1] = c
	return c
end
local function setStatus(text)
	if state.status ~= text then state.status = text; Log.info("status=" .. text) end
end

--=====================================================================
-- game modules -- plain require, no hooks. Same cached tables the game uses.
--=====================================================================
local function tryreq(path)
	local node = ReplicatedStorage
	for seg in string.gmatch(path, "[^%.]+") do
		node = node and node:FindFirstChild(seg)
	end
	if not node then Log.warn("missing module " .. path) return nil end
	local ok, mod = pcall(require, node)
	if not ok then Log.warn("require failed " .. path .. ": " .. tostring(mod)) return nil end
	return mod
end

local CSprint = tryreq("Client.Gameplay.Player.Sprint")
local ActionMovement = tryreq("Modules.Actions.ActionMovement")
local Movement = tryreq("Client.Gameplay.Player.Movement")
local ItemBoxes = tryreq("Modules.Items.ItemBoxes")
local SlideTackle = tryreq("Modules.Actions.SlideTackle")
local DodgeMod = tryreq("Modules.Actions.Dodge")
local CDodge = tryreq("Client.Gameplay.Actions.Dodge")
local Controls = tryreq("Modules.Gameplay.Controls")
local Keybinds = tryreq("Modules.Gameplay.Keybinds")

--=====================================================================
-- F1 infinite stamina -- the game's own unlimited-stamina source registry
--=====================================================================
local STAMINA_SOURCE = "R3ST"
-- Read the registration back out of the controller's own table rather than
-- trusting that our write landed. u21 is SetUnlimitedStamina's first upvalue
-- (0139.lua:703) and is never cleared by the game, so this is a true readback.
local function staminaSourceRegistered()
	if not (CSprint and CSprint.SetUnlimitedStamina) then return false end
	local ok, set = pcall(debug.getupvalue, CSprint.SetUnlimitedStamina, 1)
	if ok and type(set) == "table" then return set[STAMINA_SOURCE] == true end
	return false
end
local function applyStamina()
	if not (CSprint and CSprint.SetUnlimitedStamina) then return end
	pcall(CSprint.SetUnlimitedStamina, STAMINA_SOURCE, cfg.infStamina and true or nil)
end

--=====================================================================
-- F3 charge mobility -- ChargingWalkSpeedMultiplier + the post-kick dip
--=====================================================================
local origChargingMult = nil
local origSetMultiplier = nil
local ourSetMultiplier = nil
-- Every named source that multiplies WalkSpeed down after a move, from
-- Movement.SetMultiplier's own call sites. All are applied by OUR client into
-- the u4 multiplier table (0136.lua:498) and are recomputed per frame by
-- updateSprint (0139.lua:349), so dropping the WalkSpeed key is enough.
--   TackleKick     0067.lua:201  0.45x for 0.2s after every kick
--   SlideTackle    0068.lua:113  the recovery ramp after a steal
--   GoalkeeperDive 0134.lua:309  the ramp after a dive
--   ShotgunRecoil  0102.lua:28   item recoil lock
--   ItemZoom       0104.lua:94   while aiming an item
-- NOT here on purpose: Movement.SetMinimum("SlideTackle", {WalkSpeed = 0.1})
-- (0068.lua:414). That is the slide lock itself, not a recovery penalty --
-- walking during your own slide animation is a visible desync against the
-- server position authority (CharacterReplication, 0259.lua:715).
local DIP_SOURCES = {
	TackleKick = true, SlideTackle = true, GoalkeeperDive = true,
	ShotgunRecoil = true, ItemZoom = true,
}

local function applyChargeSpeed()
	if not ActionMovement then return end
	if origChargingMult == nil then
		origChargingMult = ActionMovement.Constants.ChargingWalkSpeedMultiplier
	end
	ActionMovement.Constants.ChargingWalkSpeedMultiplier = math.clamp(cfg.chargeSpeed, 0.5, 1)
end

local function applyKickDip()
	if not (Movement and Movement.SetMultiplier) then return end
	if cfg.noKickDip then
		if origSetMultiplier then return end
		origSetMultiplier = Movement.SetMultiplier
		ourSetMultiplier = function(name, values)
			if DIP_SOURCES[name] and type(values) == "table" and values.WalkSpeed ~= nil then
				-- Keep every other component (JumpHeight = 0 still lands), drop
				-- only the WalkSpeed cut. The action itself is unchanged.
				local copy = table.clone(values)
				copy.WalkSpeed = nil
				return origSetMultiplier(name, copy)
			end
			return origSetMultiplier(name, values)
		end
		Movement.SetMultiplier = ourSetMultiplier
		-- Drop whatever is already live, otherwise a dip applied before the
		-- toggle went on stays until the game next clears it.
		for name in next, DIP_SOURCES do pcall(Movement.ClearMultiplier, name) end
		Log.info("noKickDip ON")
	else
		if origSetMultiplier and Movement.SetMultiplier == ourSetMultiplier then
			Movement.SetMultiplier = origSetMultiplier
		end
		origSetMultiplier, ourSetMultiplier = nil, nil
	end
end

--=====================================================================
-- F6 walk speed -- ActionMovement.Constants.BaseWalkSpeed
--=====================================================================
-- GetBaseWalkSpeed() (0284.lua:27) is Constants.BaseWalkSpeed * the module's
-- speed multiplier, and every downstream speed -- jog, run, goalkeeper,
-- charging, recovery -- is derived from it (0284.lua:35/39/46). updateSprint
-- reads it every frame (0139.lua:387) and writes the result back through
-- Movement.SetStandard("Sprint", ...), so this needs no loop and no property
-- write of our own.
--
-- The constant, NOT SetSpeedMultiplier: the multiplier is a live game feature
-- (PrivateServerSettings.MovementSpeed drives it at 0437.lua:405) with no
-- getter, so its original cannot be captured for restore, and applyTuning
-- overwrites ours whenever a match setting changes. The constant is ours alone
-- and composes with the multiplier instead of fighting it.
--
-- This is the one feature here the server can see. Movement is server-checked:
-- CharacterReplication streams our root CFrame and the server answers with
-- Characters.MovementCorrection when it disagrees (0259.lua:715). The
-- correction counter in Live proof is the instrument -- clamped to 1.15x and
-- booting at stock for that reason.
local origBaseWs = nil

local function applyWalkSpeed()
	if not ActionMovement then return end
	if origBaseWs == nil then origBaseWs = ActionMovement.Constants.BaseWalkSpeed end
	ActionMovement.Constants.BaseWalkSpeed = origBaseWs * math.clamp(cfg.walkSpeed, 1, 1.15)
end

--=====================================================================
-- F6b ball-carrier speed penalty
--=====================================================================
-- Carrying the ball costs 0.9x jogging and 0.8x running (0284.lua:12/13),
-- applied in GetJogWalkSpeed / GetRunWalkSpeed. The game already has a legit
-- way to skip it -- Sprint's IgnoreBallCarrierSpeedPenalty input, fed by a
-- server-replicated boost record (0312.lua:908) -- but that path is not ours to
-- write, so this raises the two constants instead. Same class of edit as the
-- charge multiplier above, and read back the same way.
local origCarrierJog, origCarrierRun = nil, nil

local function applyCarrierDip()
	if not ActionMovement then return end
	local C = ActionMovement.Constants
	if origCarrierJog == nil then
		origCarrierJog, origCarrierRun = C.BallCarrierJogSpeedMultiplier, C.BallCarrierRunSpeedMultiplier
	end
	if cfg.noCarrierDip then
		C.BallCarrierJogSpeedMultiplier, C.BallCarrierRunSpeedMultiplier = 1, 1
	else
		C.BallCarrierJogSpeedMultiplier, C.BallCarrierRunSpeedMultiplier = origCarrierJog, origCarrierRun
	end
end

--=====================================================================
-- F6c dribble slowdown -- Movement.SetStandard("Dribble")
--=====================================================================
-- Dribbling is the one move whose slowdown is NOT a multiplier: startDribble
-- installs a STANDARD of WalkSpeed = Dodge.Constants.WalkSpeed = 12
-- (0062.lua:123, 0295.lua:19), and getStandardValue takes the MINIMUM across
-- standards (0136.lua:93), so it beats Sprint's own entry for the whole 1s
-- active window. Dropping just the WalkSpeed key leaves the entry in place --
-- the game still clears it, still fires DribblingChanged, still blocks the
-- other controls -- and Sprint's standard becomes the lowest again, i.e. jog
-- speed, because dribbling also blocks sprint (Sprint.SetBlocked, 0062.lua:104).
-- So this is 12 -> ~14.4 with the carrier penalty, ~16 without. Not a dash.
local origSetStandard = nil
local ourSetStandard = nil

local function applyDribbleDip()
	if not (Movement and Movement.SetStandard) then return end
	if cfg.noDribbleDip then
		if origSetStandard then return end
		origSetStandard = Movement.SetStandard
		ourSetStandard = function(name, values)
			if name == "Dribble" and type(values) == "table" and values.WalkSpeed ~= nil then
				local copy = table.clone(values)
				copy.WalkSpeed = nil
				return origSetStandard(name, copy)
			end
			return origSetStandard(name, values)
		end
		Movement.SetStandard = ourSetStandard
		Log.info("noDribbleDip ON")
	else
		if origSetStandard and Movement.SetStandard == ourSetStandard then
			Movement.SetStandard = origSetStandard
		end
		origSetStandard, ourSetStandard = nil, nil
	end
end

--=====================================================================
-- F7 auto-sprint -- latch the game's own sprint button ON and leave it there
--=====================================================================
-- The client sprint controller has NO setter and NO input entry point: it
-- connects to UserInputService itself (0139.lua:462/475) and the key only ever
-- writes a boolean, u6, into SetHeld(u6 or u7 or u8) (0139.lua:536). Three
-- booleans OR together into "the sprint input is down" -- u6 is the keyboard,
-- u7 the gamepad, u8 the on-screen sprint BUTTON. Only u8 has a public mutator:
--
--     Sprint.ToggleSprintButton()   0139.lua:612   u8 = not u8; SetHeld(...)
--
-- and nothing in the game clears u8 on its own except two events -- the player
-- turning the SprintButton setting off (0139.lua:484) and PreferredInput
-- leaving Touch (0139.lua:492). So flipping u8 true IS holding shift forever,
-- through the game's own public API, with no key simulated and no field patched.
-- The 0.5s tick below re-latches it if either of those two events drops it.
--
-- Sprinting still only happens while you are actually moving and still spends
-- stamina: u4/IsSprinting is the controller's own computation from held +
-- movement + CanStartSprinting (0139.lua:292), and we do not touch it. Pair
-- this with F1 if you want the sprint to last.
local function sprintLatched()
	if not (CSprint and CSprint.IsSprintButtonToggled) then return nil end
	local ok, v = pcall(CSprint.IsSprintButtonToggled)
	if ok and type(v) == "boolean" then return v end
	return nil
end

local function setSprintLatch(on)
	if not (CSprint and CSprint.ToggleSprintButton) then
		if state.sprintPath ~= "none" then
			state.sprintPath = "none"
			Log.warn("autoSprint: Sprint.ToggleSprintButton missing -- feature unavailable")
		end
		return
	end
	state.sprintPath = "ToggleSprintButton"
	local now = sprintLatched()
	if now == on then
		state.sprintHeld = on
		return
	end
	local ok, err = pcall(CSprint.ToggleSprintButton)
	if not ok then
		Log.warn("autoSprint toggle failed: " .. tostring(err))
		return
	end
	state.sprintHeld = sprintLatched() == true
	Log.info("autoSprint latch=" .. tostring(state.sprintHeld))
end

-- Cheap and idempotent: reads a boolean and only calls the toggle when the game
-- has dropped it. Safe to run on the existing 0.5s tick.
local function autoSprintTick()
	if not cfg.autoSprint then return end
	if sprintLatched() == false then setSprintLatch(true) end
end

local function applyAutoSprint()
	setSprintLatch(cfg.autoSprint and true or false)
end


--=====================================================================
-- F4 item box ESP -- read-only. Claims are server-side; range is not ours.
--=====================================================================
-- BillboardGuis are parented to the box part itself. The hub mounts modules on a
-- thread that cannot touch CoreGui ("lacking capability Plugin", hit 2026-09-09),
-- so this deliberately uses no CoreGui folder and no gethui().
local boxTags = {}
local function clearBoxEsp()
	for box, bb in next, boxTags do
		if bb then pcall(function() bb:Destroy() end) end
		boxTags[box] = nil
	end
	state.boxes = 0
end
local function refreshBoxEsp()
	if not (cfg.boxEsp and ItemBoxes) then return end
	local seen = {}
	local tagged = CollectionService:GetTagged(ItemBoxes.TagName)
	state.boxes = #tagged
	for _, box in ipairs(tagged) do
		seen[box] = true
		if not boxTags[box] then
			local part = box:IsA("BasePart") and box or box:FindFirstChildWhichIsA("BasePart", true)
			if part then
				local bb = Instance.new("BillboardGui")
				bb.Name = "R3ST_ISBox"
				bb.Adornee = part
				bb.Size = UDim2.fromOffset(120, 22)
				bb.StudsOffset = Vector3.new(0, 3, 0)
				bb.AlwaysOnTop = true
				bb.MaxDistance = 1000
				local label = Instance.new("TextLabel")
				label.BackgroundTransparency = 1
				label.Size = UDim2.fromScale(1, 1)
				label.Font = Enum.Font.GothamBold
				label.TextSize = 13
				label.TextColor3 = Color3.fromRGB(120, 235, 150)
				label.TextStrokeTransparency = 0.4
				label.Text = "ITEM BOX"
				label.Parent = bb
				bb.Parent = part
				boxTags[box] = bb
			end
		end
	end
	for box, bb in next, boxTags do
		if not seen[box] then
			if bb then pcall(function() bb:Destroy() end) end
			boxTags[box] = nil
		end
	end
end
local function applyBoxEsp()
	if cfg.boxEsp then refreshBoxEsp() else clearBoxEsp() end
end

--=====================================================================
-- Ball chams -- one Highlight on the ball's own skin model
--=====================================================================
-- The ball is an INVISIBLE anchored Part named "ClientBall_<id>" under
-- workspace.Misc.Visuals (Renderer.createBall, 0072.lua:110-129, Transparency=1);
-- everything you actually see is the skin model cloned by Skins.CreateVisual
-- (0322.lua:106) and parented to that part (0072.lua:160). So the Adornee must be
-- the MODEL -- adorning the part would outline a cube the size of the ball's
-- bounding box instead of the sphere.
-- Parented to the ball part, not to CoreGui: the hub mounts modules on a thread
-- that cannot access CoreGui (this cost the whole mount in .4), and a Highlight
-- under a ScreenGui does not render at all. The game does exactly this itself --
-- Skins.EnsureHighlight (0322.lua:192) already keeps a Highlight on the model for
-- its skin-change flash, which is why one more costs nothing.
-- Cost: one instance, no per-frame work. The 0.5s tick only re-points it when the
-- skin model is swapped or the ball respawns.
local Renderer = tryreq("Client.Gameplay.Ball.Renderer")
local chamHl = nil
local function findBallPart()
	if Renderer and Renderer.GetBall then
		local ok, part = pcall(Renderer.GetBall)
		if ok and typeof(part) == "Instance" and part.Parent then return part end
	end
	local visuals = workspace:FindFirstChild("Misc")
	visuals = visuals and visuals:FindFirstChild("Visuals")
	if not visuals then return nil end
	for _, child in ipairs(visuals:GetChildren()) do
		if child:IsA("BasePart") and string.sub(child.Name, 1, 11) == "ClientBall_" then return child end
	end
	return nil
end
local function clearCham()
	if chamHl then pcall(function() chamHl:Destroy() end) end
	chamHl = nil
	state.chamOn = false
end
local function refreshCham()
	if not cfg.ballCham then return end
	local part = findBallPart()
	if not part then clearCham() return end
	local adornee = part:FindFirstChildWhichIsA("Model") or part
	if chamHl and chamHl.Parent == part and chamHl.Adornee == adornee then
		state.chamOn = true
		return
	end
	if chamHl then pcall(function() chamHl:Destroy() end) end
	local hl = Instance.new("Highlight")
	hl.Name = "R3ST_BallCham"
	hl.Adornee = adornee
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.FillColor = Color3.fromRGB(255, 40, 40)
	hl.FillTransparency = 0.55
	hl.OutlineColor = Color3.fromRGB(255, 90, 90)
	hl.OutlineTransparency = 0
	hl.Parent = part
	chamHl = hl
	state.chamOn = true
end
local function applyBallCham()
	if cfg.ballCham then refreshCham() else clearCham() end
end

--=====================================================================
-- shot-speed readback -- the ONLY thing that proves max power landed
--=====================================================================
-- The reject counter cannot answer this: a server that silently recomputes the
-- shot from the real Start->Release elapsed produces zero rejects and a slow
-- ball, which is indistinguishable from success on that counter alone.
--
-- Remotes.Ball.State (remotes.txt:9) is the server's authoritative ball state.
-- buildReceivedState (0077.lua:1023) names the fields; the game connects it at
-- 0077.lua:2183 with a single table argument. On a launch it carries
-- InitialVelocity, ActionId, LastKickerUserId and LastKickKind. Read-only: we
-- add one more listener to a remote the game already listens to.
--
-- The band is the game's own: speed = Min + (Max-Min) * alpha^PowerCurve
-- (KickCore.GetChargedSpeed, 0303.lua:107) over Shot.MinimumSpeed 70 ..
-- MaximumSpeed 123 (0309.lua:23). Read live so a game update moves the band too.
--
-- Ball ownership tracker. This used to be the shot-speed readback that proved
-- max power; those features are gone, but the auto-dribble outcome counters
-- still need to know who is holding the ball. "Owned" carries OwnerUserId; any
-- other Kind means it is loose (0077.lua:1194).
local function armBallOwner()
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local ball = remotes and remotes:FindFirstChild("Ball")
	local stateRemote = ball and ball:FindFirstChild("State")
	if not (stateRemote and stateRemote:IsA("RemoteEvent")) then
		Log.warn("Ball.State missing -- ball ownership unavailable")
		return
	end
	connect(stateRemote.OnClientEvent, function(st)
		if typeof(st) ~= "table" then return end
		if st.Kind == "Owned" then
			state.ballOwner = st.OwnerUserId
		elseif st.Kind == "Movement" or st.Kind == "Removed" then
			state.ballOwner = nil
		end
	end)
end

--=====================================================================
-- F5 auto-dribble -- react to an incoming steal inside its 270ms windup
--=====================================================================
-- Full derivation and citations: ILLEGAL_SOCCER.md F8. The short version:
--
--  * A slide tackle cannot touch you for HitboxDelaySeconds = 0.27 of its 1.9s
--    animation (SlideTackle.Constants, 0311.lua:18). That is the whole budget.
--  * The server broadcasts a TackleStarted effect; OUR OWN client handles it at
--    0069.lua:1940 and calls SlideTackle.SetSlidingUntil, which fires the shared
--    SlidingUntilChanged BindableEvent (0311.lua:154). We just connect. The
--    server also sets a replicated SlidingUntil attribute, so we watch that too;
--    GetSlidingUntil (0311.lua:205) reads whichever exists.
--  * The hitbox arithmetic is the game's own, from CharacterAuras.watchSlide
--    (0075.lua:465-469), in GetServerTimeNow() units -- a shared clock, so no
--    latency estimation is involved:
--        hitboxLiveAt = SlidingUntil - TotalMotionSeconds + HitboxDelaySeconds
--  * Firing needs no hook: Dodge.HandleInputBegan (0062.lua:258) reads only
--    .KeyCode, .UserInputState and .UserInputType off the input object, so a
--    plain table drives the game's own handler and it sends the normal command.
--
-- WHY THIS IS SELECTIVE AND NOT A REFLEX: the dodge costs 4 seconds
-- (RepeatDelaySeconds = ActiveSeconds 1 + CooldownSeconds 3, 0295.lua:26) on a
-- clock the server holds -- see the Cooldowns note, 30/30 early actions were
-- rejected. startDribble also blocks your other gameplay controls
-- (0062.lua:112). So a dodge spent on a tackle that would have missed costs the
-- ball AND leaves you defenceless. We only spend it when SlideTackle's own
-- hitbox test says the tackle connects.
--
-- UNPROVEN: whether the server's evade test is "was Dribbling true when the
-- hitbox resolved" or a tighter window around contact. The tutorial copy implies
-- tighter ("Too early! Wait until they're right next to you", 0396.lua:183).
-- The outcome is server-decided (DodgeSucceeded is a server effect the client
-- only presents, 0069.lua:2034), so only the counters below answer it. That is
-- why this boots OFF and OBSERVE-ONLY.

local TACKLE_TOTAL = 1.915       -- fallbacks only; live constants are read below
local TACKLE_HITDELAY = 0.27
local TACKLE_HITSECONDS = 0.3

local function tackleConst(name, fallback)
	local c = SlideTackle and SlideTackle.Constants
	local v = c and c[name]
	return type(v) == "number" and v or fallback
end

-- Build a synthetic input the game's own keybind check accepts. The Dribble bind
-- is rebindable (Keybinds u3, 0377.lua:21), so guessing Space is wrong for any
-- player who changed it. Read the effective binding out of Keybinds.Matches'
-- upvalues -- u8 is the user override table, u3 the defaults (0377.lua:180) --
-- and then VERIFY through Controls.IsInput before ever arming.
local synthInput = nil
local function buildSynthInput()
	if not (Controls and Controls.IsInput and Keybinds) then return nil end
	local candidates = {}
	if Keybinds.Matches then
		for slot = 1, 6 do
			local ok, tbl = pcall(debug.getupvalue, Keybinds.Matches, slot)
			if ok and type(tbl) == "table" then
				local entry = tbl.Dribble
				if type(entry) == "table" and type(entry.KeyCodes) == "table" then
					for _, kc in ipairs(entry.KeyCodes) do
						candidates[#candidates + 1] = kc
					end
				end
			end
		end
	end
	candidates[#candidates + 1] = Enum.KeyCode.Space
	for _, kc in ipairs(candidates) do
		local probe = {
			KeyCode = kc,
			UserInputState = Enum.UserInputState.Begin,
			UserInputType = Enum.UserInputType.Keyboard,
		}
		local ok, matched = pcall(Controls.IsInput, "Dribble", probe)
		if ok and matched then
			state.adKey = tostring(kc):gsub("Enum%.KeyCode%.", "")
			state.adKeyOk = true
			return probe
		end
	end
	state.adKey = "unresolved"
	state.adKeyOk = false
	return nil
end

-- Would this tackle actually reach us? SlideTackle.GetTravel (0311.lua:50) gives
-- the distance slid at any point in the motion and IsInsideHitbox (0311.lua:134)
-- is the real 5x5x5 test against HitboxSettings.SlideTackle (0374.lua:35). Both
-- are shared and read-only, so this is the server's own geometry, not a guess.
local function tacklePredictsHit(tacklerChar, elapsed, atTime)
	if not (SlideTackle and SlideTackle.GetTravel and SlideTackle.IsInsideHitbox) then
		return true, "no predictor"
	end
	local root = tacklerChar and tacklerChar:FindFirstChild("HumanoidRootPart")
	local ourChar = LP.Character
	local ourRoot = ourChar and ourChar:FindFirstChild("HumanoidRootPart")
	if not (root and ourRoot) then return true, "no roots" end
	local okA, travelNow = pcall(SlideTackle.GetTravel, math.max(0, elapsed))
	local okB, travelHit = pcall(SlideTackle.GetTravel, math.max(0, atTime))
	if not (okA and okB and type(travelNow) == "number" and type(travelHit) == "number") then
		return true, "travel failed"
	end
	local cf = root.CFrame
	local predicted = cf + cf.LookVector * (travelHit - travelNow)
	-- Our own position is taken as-is: predicting our movement too would compound
	-- two guesses, and the hitbox is 5 studs wide against a ~0.27s horizon.
	local okC, inside = pcall(SlideTackle.IsInsideHitbox, { CFrame = predicted }, ourRoot.Position)
	if not okC then return true, "hitbox test failed" end
	return inside and true or false, inside and "predicted hit" or "predicted miss"
end

local function weOwnBall()
	return state.ballOwner ~= nil and state.ballOwner == LP.UserId
end

local function fireDodge(tag)
	if not (CDodge and CDodge.HandleInputBegan and synthInput) then
		state.adLastWhy = "no dodge handler"
		return
	end
	local before = false
	if CDodge.IsDribbling then
		local ok, v = pcall(CDodge.IsDribbling)
		before = ok and v or false
	end
	state.adFired = state.adFired + 1
	-- The game's own input path. It re-checks every gate itself (ownership,
	-- landed, ragdoll, stamina, cooldown) and sends the normal Dodge command.
	local ok, err = pcall(CDodge.HandleInputBegan, synthInput, false)
	if not ok then
		state.adLastWhy = "handler error"
		Log.warn("autoDribble handler error: " .. tostring(err))
		return
	end
	-- Did the game accept it? Dribbling flips synchronously inside startDribble
	-- (0062.lua:121), so this is a real accept/refuse readback, not a guess.
	local after = before
	if CDodge.IsDribbling then
		local ok2, v = pcall(CDodge.IsDribbling)
		after = ok2 and v or false
	end
	if after and not before then
		state.adStarted = state.adStarted + 1
		state.adLastWhy = "fired: " .. tag
	else
		state.adBlocked = state.adBlocked + 1
		state.adLastWhy = "gate refused (cooldown/airborne/stamina)"
	end
	Log.info(string.format("AUTODRIBBLE fire tag=%s accepted=%s owner=%s",
		tag, tostring(after and not before), tostring(weOwnBall())))
end

-- One tackle -> one decision. Re-entry is guarded per SlidingUntil value so the
-- attribute signal and the BindableEvent cannot double-handle the same tackle.
local handledTackles = setmetatable({}, { __mode = "k" })

local function onTackleDetected(tacklerChar)
	if not (state.alive and SlideTackle and tacklerChar) then return end
	if tacklerChar == LP.Character then return end
	local okS, slidingUntil = pcall(SlideTackle.GetSlidingUntil, tacklerChar)
	if not (okS and type(slidingUntil) == "number") then return end
	if handledTackles[tacklerChar] == slidingUntil then return end
	handledTackles[tacklerChar] = slidingUntil

	local total = tackleConst("TotalMotionSeconds", TACKLE_TOTAL)
	local delay = tackleConst("HitboxDelaySeconds", TACKLE_HITDELAY)
	local active = tackleConst("HitboxSeconds", TACKLE_HITSECONDS)
	local now = workspace:GetServerTimeNow()
	local startedAt = slidingUntil - total
	local hitboxLiveAt = startedAt + delay
	local lead = hitboxLiveAt - now
	local elapsed = now - startedAt

	state.adSeen = state.adSeen + 1
	state.adLastLead = lead
	if lead < state.adMinLead then state.adMinLead = lead end

	local owned = weOwnBall()
	if owned then state.adOnUs = state.adOnUs + 1 end

	local willHit, why = tacklePredictsHit(tacklerChar, elapsed, delay)
	if willHit then state.adPredHit = state.adPredHit + 1 end

	Log.info(string.format(
		"AUTODRIBBLE detect lead=%.3f elapsed=%.3f owned=%s predict=%s (%s) mode=%s",
		lead, elapsed, tostring(owned), tostring(willHit), why,
		(not cfg.autoDribble) and "off" or (cfg.adObserve and "observe" or "armed")))

	-- Measure the outcome regardless of mode. In observe mode this is the
	-- baseline: how often a detected tackle takes the ball when we do nothing.
	if owned then
		local hitboxEndsAt = hitboxLiveAt + active
		task.delay(math.max(0, hitboxEndsAt - now) + 0.3, function()
			if not state.alive then return end
			if weOwnBall() then
				state.adSaved = state.adSaved + 1
			else
				state.adLost = state.adLost + 1
			end
			Log.info(string.format("AUTODRIBBLE outcome kept=%s mode=%s",
				tostring(weOwnBall()),
				(not cfg.autoDribble) and "off" or (cfg.adObserve and "observe" or "armed")))
		end)
	end

	if not cfg.autoDribble then state.adLastWhy = "disabled" return end
	if cfg.adObserve then state.adLastWhy = "observe only" return end
	if not owned then state.adLastWhy = "not our ball" return end
	if cfg.adOnlyIfHit and not willHit then state.adLastWhy = why return end

	-- Jitter keeps the trigger off a fixed offset. Frame-perfect every time is
	-- the most narratable thing this feature could do.
	local jitter = (math.random() * 2 - 1) * cfg.adJitter
	local fireAt = hitboxLiveAt - cfg.adOffset + jitter
	local wait = fireAt - workspace:GetServerTimeNow()
	if wait <= 0 then
		fireDodge("late")
	else
		task.delay(wait, function()
			if state.alive and cfg.autoDribble and not cfg.adObserve then fireDodge("timed") end
		end)
	end
end

--=====================================================================
-- press -> launch timing -- "do I still have to hold m1"
--=====================================================================
-- Every counter in this panel measured the shot's SPEED. None measured its
-- TIME, so "max power works" and "I still have to wait for the charge" were
-- both true at once and nothing here could tell them apart. A shot held to full
-- and a shot fired instantly BOTH read 123.00 studs/s.
--
-- Three numbers separate them, and they need no hook on any remote:
--   hold = m1 down -> m1 up. How long YOU held the button.
--   lag  = m1 down -> the server's launch state for that shot.
--   lag - hold = what the game added after you let go.
-- If hold is ~0.25 s the charge gate is not the problem, your finger is -- the
-- shot goes out when you RELEASE m1 (releaseCharge is the m1-up path,
-- 0067.lua:1025), and instant charge removes the forced wait AFTER release, not
-- the release itself. If hold is ~0.05 s and lag is ~0.3 s, something is still
-- delaying us and DelayReleaseUntilMinimum (0061.lua:1049) is not the only gate.
-- Either way this is the reading that decides it instead of us guessing.
--=====================================================================
-- knockback readback -- "did that shot knock anyone over"
--=====================================================================
-- Knocking a player over is NOT something the client can ask for. There is no
-- claim: Remotes.Ball.ViolenceDash is receive-only on our side (its ONLY use in
-- 528 scripts is `Remote.OnClientEvent:Connect(runDash)`, 0141.lua:184), and the
-- knockback itself arrives as the broadcast effect "ViolenceKnockback" through
-- Ball.TackleEffect / Ball.ActionPresentationUpdate (0069.lua:2072-2073, handled
-- at 0069.lua:1906). Nothing in ReplicatedStorage computes it, so the decision
-- lives in ServerScriptService, which is not in the dump.
--
-- What that leaves us is a clean read: the server tells us every time anyone is
-- knocked over, who did it, who caught it and how hard. Paired with the shot
-- readback above, that is the whole causal chain we can see --
--   shot speed 123.00  ->  ViolenceKnockback by us  ->  they are on the floor
-- and the missing middle row is the answer to "why is this not working".
--
-- presentEffect's signature (0069.lua:1645): p235 = effect name, p236 = the
-- VICTIM (u254 is resolved from it at 0069.lua:1647, and it is the character the
-- ragdoll animation plays on), p238 = the other actor, p239 = the knockback
-- velocity whose .Magnitude drives the screen shake (0069.lua:1931).
-- ForcefieldBlocked (0069.lua:1896) is counted next to it because it is the
-- other outcome of a ball meeting a player and it looks identical from here.
local function armKnockbackReadback()
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local ball = remotes and remotes:FindFirstChild("Ball")
	if not ball then
		Log.warn("Remotes.Ball missing -- knockback readback unavailable")
		return
	end
	local function nameOf(userId)
		if userId == LP.UserId then return "you" end
		if type(userId) ~= "number" then return "?" end
		local cached = state.knockNames[userId]
		if cached then return cached end
		local player = Players:GetPlayerByUserId(userId)
		local nm = player and player.Name or ("uid:" .. tostring(userId))
		state.knockNames[userId] = nm
		return nm
	end
	local seen = 0
	for _, remoteName in ipairs({ "TackleEffect", "ActionPresentationUpdate" }) do
		local r = ball:FindFirstChild(remoteName)
		if r and r:IsA("RemoteEvent") then
			seen = seen + 1
			connect(r.OnClientEvent, function(effect, victim, _a, source, velocity)
				if effect == "ForcefieldBlocked" then
					state.knockShielded = state.knockShielded + 1
					Log.info(string.format("SHIELDED %s blocked a hit", nameOf(victim)))
					return
				end
				if effect ~= "ViolenceKnockback" then return end
				local mag = typeof(velocity) == "Vector3" and velocity.Magnitude or -1
				state.knockTotal = state.knockTotal + 1
				if source == LP.UserId then state.knockByUs = state.knockByUs + 1 end
				if victim == LP.UserId then state.knockOnUs = state.knockOnUs + 1 end
				state.lastKnockMag = mag
				state.lastKnock = nameOf(source) .. " -> " .. nameOf(victim)
				Log.info(string.format(
					"KNOCKBACK %s mag=%.1f byUs=%s onUs=%s (%s)",
					state.lastKnock, mag, tostring(source == LP.UserId),
					tostring(victim == LP.UserId), tostring(effect)))
			end)
		end
	end
	if seen == 0 then
		Log.warn("no effect remote found -- knockback readback unavailable")
	else
		Log.info("knockback readback armed on " .. seen .. " remote(s)")
	end
end

local function armAutoDribble()
	if not SlideTackle then
		Log.warn("SlideTackle missing -- auto-dribble unavailable")
		return
	end
	synthInput = buildSynthInput()
	if not synthInput then
		Log.warn("could not resolve the Dribble keybind -- auto-dribble can detect but not fire")
	end
	-- Path 1: the module's own signal, fired when our client handles the
	-- TackleStarted effect for a remote player (0069.lua:1942 -> 0311.lua:177).
	if SlideTackle.SlidingUntilChanged and SlideTackle.SlidingUntilChanged.Event then
		connect(SlideTackle.SlidingUntilChanged.Event, function(char)
			onTackleDetected(char)
		end)
	end
	-- Path 2: the replicated attribute the server sets directly. Watch it on
	-- every character present and on every one that appears.
	local function watchChar(char)
		if not (char and char.GetAttributeChangedSignal) then return end
		local okC, sig = pcall(char.GetAttributeChangedSignal, char, SlideTackle.SlidingUntilAttributeName)
		if okC and sig then
			connect(sig, function() onTackleDetected(char) end)
		end
	end
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LP then
			if plr.Character then watchChar(plr.Character) end
			connect(plr.CharacterAdded, watchChar)
		end
	end
	connect(Players.PlayerAdded, function(plr)
		if plr == LP then return end
		connect(plr.CharacterAdded, watchChar)
	end)
	Log.info("autoDribble detector armed key=" .. tostring(state.adKey))
end

--=====================================================================
-- telemetry -- always on. This is how we learn what the server refused.
--=====================================================================
local function armTelemetry()
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local ball = remotes and remotes:FindFirstChild("Ball")
	if ball then
		for _, name in ipairs({ "Kick", "Tackle", "RainbowFlick", "CallForPass" }) do
			local r = ball:FindFirstChild(name)
			if r and r:IsA("RemoteEvent") then
				connect(r.OnClientEvent, function(msg)
					if typeof(msg) ~= "table" then return end
					local phase = tostring(msg.Phase)
					-- VolleyRefused is ordinary gameplay, not enforcement.
					if phase == "VolleyRefused" then return end
					state.rejects = state.rejects + 1
					local cmd = msg.Command
					state.lastReject = name .. "/" .. phase
					Log.warn(string.format(
						"REJECT %s phase=%s cdRemain=%s kind=%s charge=%s armed[stam=%s dip=%s spd=%.2f ws=%.2f]",
						name, phase, tostring(msg.CooldownRemainingSeconds),
						tostring(cmd and cmd.Kind), tostring(cmd and cmd.ChargeSeconds),
						tostring(cfg.infStamina),
						tostring(cfg.noKickDip), cfg.chargeSpeed, cfg.walkSpeed))
				end)
			end
		end
	end
	local chars = remotes and remotes:FindFirstChild("Characters")
	local mc = chars and chars:FindFirstChild("MovementCorrection")
	if mc and mc:IsA("RemoteEvent") then
		connect(mc.OnClientEvent, function(char, data)
			if char ~= LP.Character then return end
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			local mag = (hrp and data and data.Position) and (hrp.Position - data.Position).Magnitude or -1
			state.corrections = state.corrections + 1
			if mag > state.maxSnap then state.maxSnap = mag end
			Log.warn(string.format(
				"CORRECTION mag=%.2f armed[stam=%s dip=%s spd=%.2f ws=%.2f carrier=%s drib=%s]",
				mag, tostring(cfg.infStamina),
				tostring(cfg.noKickDip), cfg.chargeSpeed, cfg.walkSpeed,
				tostring(cfg.noCarrierDip), tostring(cfg.noDribbleDip)))
		end)
	end
end

--=====================================================================
-- lifecycle
--=====================================================================
-- One feature failing must not strand the others. Each is applied on its own;
-- a failure is logged and disables just that toggle.
local function applyAll()
	for _, f in ipairs({
		{ "infStamina", applyStamina },
		{ "chargeSpeed", applyChargeSpeed }, { "noKickDip", applyKickDip },
		{ "walkSpeed", applyWalkSpeed }, { "noCarrierDip", applyCarrierDip },
		{ "noDribbleDip", applyDribbleDip }, { "autoSprint", applyAutoSprint },
		{ "boxEsp", applyBoxEsp }, { "ballCham", applyBallCham },
	}) do
		local ok, err = pcall(f[2])
		if not ok then
			Log.warn("feature " .. f[1] .. " failed, disabling it: " .. tostring(err))
			if typeof(cfg[f[1]]) == "boolean" then cfg[f[1]] = false end
			setStatus(f[1] .. " unavailable")
		end
	end
end

local function stopFeatures()
	cfg.infStamina = false
	cfg.noKickDip = false
	cfg.noCarrierDip = false
	cfg.noDribbleDip = false
	cfg.autoSprint = false
	cfg.walkSpeed = 1
	cfg.boxEsp = false
	cfg.ballCham = false
	-- Auto-dribble has nothing to restore (it patches no game field), but it must
	-- stop being able to fire. Back to OFF and observe, the boot state.
	cfg.autoDribble = false
	cfg.adObserve = true
	cfg.chargeSpeed = origChargingMult or 0.5
	applyStamina()
	applyKickDip()
	applyCarrierDip()
	applyDribbleDip()
	applyAutoSprint()
	applyWalkSpeed()
	applyBoxEsp()
	applyBallCham()
	if ActionMovement then
		if origChargingMult ~= nil then
			ActionMovement.Constants.ChargingWalkSpeedMultiplier = origChargingMult
		end
		if origBaseWs ~= nil then
			ActionMovement.Constants.BaseWalkSpeed = origBaseWs
		end
		if origCarrierJog ~= nil then
			ActionMovement.Constants.BallCarrierJogSpeedMultiplier = origCarrierJog
			ActionMovement.Constants.BallCarrierRunSpeedMultiplier = origCarrierRun
		end
	end
	setStatus("Stopped")
end

local destroy
destroy = function()
	if not state.alive then return end
	state.alive = false
	state.armed = false
	teardownSaveLock = true   -- before stopFeatures, never after
	stopFeatures()
	for _, c in ipairs(state.conns) do pcall(function() c:Disconnect() end) end
	table.clear(state.conns)
	clearBoxEsp()
	clearCham()
	if state.screen then
		state.screen:Destroy()
	elseif state.panel and state.panel.Parent then
		state.panel:Destroy()
	end
	if G[GKEY] == state then G[GKEY] = nil end
	Log.info("unloaded " .. BUILD_VERSION)
end
state.destroy, state.build = destroy, BUILD_VERSION
G[GKEY] = state

-- Telemetry is safe to arm early -- it only listens. The FEATURES are armed
-- after the panel exists (see the end of this file): arming first meant a UI
-- failure left the backend patched with no panel to turn it off, which is
-- exactly what happened on 2026-09-09 when a remount threw mid-build.
armTelemetry()
armBallOwner()
armKnockbackReadback()
-- The detector is read-only and boots in observe mode, so it is safe to arm with
-- the other listeners. Nothing fires a dodge until the panel toggle says so.
armAutoDribble()

-- Stamina and the box list need re-asserting across respawns and spawns.
connect(LP.CharacterAdded, function()
	task.delay(1, function()
		if state.alive then applyStamina(); applyKickDip() end
	end)
end)
local tickAt = 0
connect(RunService.Heartbeat, function()
	if not state.alive or os.clock() - tickAt < 0.5 then return end
	tickAt = os.clock()
	if cfg.boxEsp then refreshBoxEsp() end
	if cfg.ballCham then refreshCham() end
	if cfg.infStamina then applyStamina() end
	-- Re-latch if the game dropped the sprint button (a settings change or a
	-- PreferredInput switch are its only two ways to clear it).
	autoSprintTick()
end)
-- The cooldown clocks are re-stamped by the game on every use, so the bypass has
-- to keep pushing them. Every frame, not throttled: a 0.5s tick would let the
-- gate close between presses.
connect(UserInputService.InputBegan, function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.K then destroy() end
end)

--=====================================================================
-- UI
--=====================================================================
-- HUB-ONLY MODULE. This never builds its own window: it is mounted by hub.lua
-- into __R3ST_HOST and nowhere else. Loading the file directly used to spawn a
-- second floating panel next to the hub, which is not what this is for.
if not (HOST and HOST.ui) then
	Log.warn("not hosted -- this module only mounts inside hub.lua; nothing was armed")
	destroy()
	return
end
local Kit = HOST.ui
assert(Kit.SHELL_CONTRACT == "1", "R3ST shell contract mismatch")

local live = {}
local Shell
Shell = Kit.moduleShell({
	id = "illegal-soccer", title = "Illegal Soccer", version = BUILD_VERSION,
	subtitle = "Client-side stamina, shot power and charge mobility.",
	gameId = EXPECTED_GAME, placeId = EXPECTED_PLACE,
	live = live, conns = state.conns, cfg = cfg, save = saveConfig,
	onUnload = destroy,
})
state.screen, state.panel = Shell.screen, Shell.root

connect(RunService.RenderStepped, function()
	for _, paint in ipairs(live) do
		local ok, err = pcall(paint)
		if not ok then Log.warn("ui paint failed: " .. tostring(err)) end
	end
end)

local page = Shell.page("Main")
local W = Shell.W

W.section(page, "Stamina")
W.toggle(page, { label = "Infinite stamina", key = "infStamina",
	desc = "Registers an unlimited-stamina source through the game's own Sprint API -- the same one its goalkeeper zone uses.",
	set = function(v) cfg.infStamina = v; applyStamina() end })

W.section(page, "Knockdowns")
-- Read-only. A knockdown is broadcast by the server as the ViolenceKnockback
-- effect (0069.lua:1906); the client has no way to ask for one, so counting the
-- broadcasts is the only honest measure available.
W.statusRow(page, function()
	if state.knockTotal == 0 and state.knockShielded == 0 then
		return "Knockdowns: none seen yet  |  shoot at a player's body and watch this row"
	end
	return string.format(
		"Knockdowns %d (yours %d, on you %d)  |  last %s at %.0f  |  forcefield blocks %d",
		state.knockTotal, state.knockByUs, state.knockOnUs,
		state.lastKnock, state.lastKnockMag, state.knockShielded)
end)
W.note(page, "This is a read-only counter, not a feature. Knocking a player over is decided entirely by the server -- nothing in ReplicatedStorage computes it, and Remotes.Ball.ViolenceDash is receive-only on our side (0141.lua:184 is its only use in 528 scripts). The one input we ever had was shot speed, and that branch was removed in .18. 'Forcefield blocks' climbing means the target was protected and no shot would have worked.")

W.section(page, "Defense -- auto-dribble")
W.note(page, "A slide tackle cannot touch you for the first 0.27s of its 1.9s animation, and the game tells us exactly when its hitbox goes live (SlideTackle.Constants 0311.lua:18; the arithmetic is the game's own, CharacterAuras 0075.lua:465). That is the entire budget and it is a big one.")
W.toggle(page, { label = "Auto-dribble", key = "autoDribble",
	desc = "Dodge an incoming steal inside its windup. Costs 4s on a server-held clock, so it only spends the dodge on a tackle it predicts will connect.",
	set = function(v) cfg.autoDribble = v end })
W.toggle(page, { label = "Observe only (do not fire)", key = "adObserve",
	desc = "Detect, predict and count -- but never actually dodge. Leave this ON for a session first: it measures the lead time and the predictor against reality at zero risk.",
	set = function(v) cfg.adObserve = v end })
W.toggle(page, { label = "Only if it would connect", key = "adOnlyIfHit",
	desc = "Run SlideTackle's own hitbox test before spending the dodge. OFF dodges every tackle it sees and will waste the 4s cooldown on misses.",
	set = function(v) cfg.adOnlyIfHit = v end })
W.slider(page, { label = "Fire before hitbox", key = "adOffset", min = 0, max = 0.25, step = 0.01,
	desc = "Seconds before the hitbox goes live. The tutorial says dodging too early fails, so this is the number to sweep.",
	fmt = function(v) return string.format("%.2fs", v) end,
	set = function(v) cfg.adOffset = v end })
W.slider(page, { label = "Timing jitter", key = "adJitter", min = 0, max = 0.08, step = 0.01,
	desc = "Randomises the trigger. Never-mistimed dodges are the most narratable thing this panel can produce.",
	fmt = function(v) return string.format("+/-%.2fs", v) end,
	set = function(v) cfg.adJitter = v end })
W.statusRow(page, function()
	return string.format("Seen %d  |  on us %d  |  predicted hit %d  |  fired %d (accepted %d, refused %d)",
		state.adSeen, state.adOnUs, state.adPredHit, state.adFired, state.adStarted, state.adBlocked)
end)
W.statusRow(page, function()
	local total = state.adSaved + state.adLost
	local pct = total > 0 and (state.adSaved / total * 100) or 0
	return string.format("Ball kept %d / lost %d (%.0f%% kept)  |  last lead %.3fs  |  worst lead %.3fs  |  key %s",
		state.adSaved, state.adLost, pct, state.adLastLead,
		state.adMinLead < 99 and state.adMinLead or -1, state.adKey)
end)
W.statusRow(page, function()
	return "Last decision: " .. tostring(state.adLastWhy)
end)
W.note(page, "UNPROVEN and this is how you settle it. Run a session in observe mode and read 'ball kept' -- that is your baseline for doing nothing. Then arm it and compare at the same offset. If 'fired' climbs but 'accepted' does not, a gate is refusing (cooldown, airborne, or stamina). If 'accepted' climbs but 'kept' does not move, the server's evade window is tighter than the dodge's 1s active time and the offset slider is the thing to sweep. Rejected dodges also show in the reject counter below as Tackle/ExecuteRejected.")

W.section(page, "Cooldowns")
W.note(page, "DISPROVED 2026-09-09 on this account. The client gate IS bypassable (the game skips it during its own tutorial, 0062.lua:276 / 0068.lua:709) but the server keeps its own clock: 30 of 30 early dribbles and steals came back Tackle/ExecuteRejected with a cooldown quote (cdRemain 2.749, 1.499, 0.199...). The toggle was removed rather than left on, because 30 rejected actions in 10 seconds is the loudest thing this script could emit. Shot and flick have no tutorial escape either.")
W.note(page, "UNPROVEN, and self-calibrating: the first dribble/steal after enabling still uses the stock cooldown, because the clock is only written once it has been seen behaving like one. Flick and shot cooldowns are NOT bypassable this way and are not offered. Turn this on, spam dribble, then check the reject counter: if it climbs, the server is enforcing and this cannot work.")

W.section(page, "Mobility")
W.toggle(page, { label = "Auto-sprint", key = "autoSprint",
	desc = "Latches the game's own sprint button ON and leaves it there, so sprint is held for you permanently -- you still only sprint while actually moving, because that is the controller's own rule. Sprint.ToggleSprintButton (0139.lua:612) is the game's public API for exactly this; no key is simulated, no field is patched, no remote is touched. Stamina is still spent -- pair it with Infinite stamina to make it last.",
	set = function(v) cfg.autoSprint = v; applyAutoSprint() end })
W.statusRow(page, function()
	local latched = sprintLatched()
	local sprinting = nil
	if CSprint and CSprint.IsSprinting then
		local ok, v = pcall(CSprint.IsSprinting)
		if ok and type(v) == "boolean" then sprinting = v end
	end
	return string.format("Auto-sprint: %s  |  sprint held: %s  |  sprinting right now: %s",
		cfg.autoSprint and "ON" or "off",
		latched == nil and "?" or (latched and "YES" or "no"),
		sprinting == nil and "?" or (sprinting and "YES" or "no"))
end)
W.note(page, "'Sprint held YES' with 'sprinting no' while you stand still is correct -- the button is down, you are just not moving. Held YES while RUNNING and sprinting no means a gate is refusing, and stamina is the usual one.")
W.slider(page, { label = "Charge move speed", key = "chargeSpeed", min = 0.5, max = 1, step = 0.05,
	desc = "Stock is 0.50 (walk 8 instead of 16 while charging). Higher moves you faster mid-charge.",
	fmt = function(v) return string.format("x%.2f%s", v, v <= 0.5 and " (stock)" or "") end,
	set = function(v) cfg.chargeSpeed = v; applyChargeSpeed() end })
W.toggle(page, { label = "No move slowdowns", key = "noKickDip",
	desc = "Drops the WalkSpeed cut your client applies after a move: kick (0.45x for 0.2s, measured 8.00 -> 3.60), the steal and goalkeeper-dive recovery ramps, shotgun recoil, and item aiming. Jump blocks are left alone. The slide lock itself is NOT touched -- walking during your own slide animation is a visible desync.",
	set = function(v) cfg.noKickDip = v; applyKickDip() end })
W.toggle(page, { label = "No dribble slowdown", key = "noDribbleDip",
	desc = "Dribbling pins you to WalkSpeed 12 for its full 1s (0062.lua:123). This drops that one field, so you fall back to jog speed instead. Sprint is still blocked while dribbling, so it is ~14.4 (or 16 with the carrier penalty off), not a dash.",
	set = function(v) cfg.noDribbleDip = v; applyDribbleDip() end })
W.toggle(page, { label = "No ball-carrier penalty", key = "noCarrierDip",
	desc = "Carrying the ball costs 0.9x jogging and 0.8x running (0284.lua:12). Raises both to 1.0, so you move with the ball at the same speed you move without it. The game has its own version of this flag on speed boosts.",
	set = function(v) cfg.noCarrierDip = v; applyCarrierDip() end })
W.note(page, "All of the above are applied by your own client and change no remote. Base and sprint speed are unchanged, so they read as normal movement rather than a speed hack.")

W.slider(page, { label = "Walk speed", key = "walkSpeed", min = 1, max = 1.15, step = 0.01,
	desc = "Scales ActionMovement BaseWalkSpeed (stock 16), which every other speed in the game is derived from -- jog, sprint, goalkeeper, charging. 1.15x is walk 18.4 / sprint 29.4.",
	fmt = function(v) return string.format("x%.2f (ws %.1f)%s", v, 16 * v, v <= 1 and " -- stock" or "") end,
	set = function(v) cfg.walkSpeed = v; applyWalkSpeed() end })
W.note(page, "THIS ONE THE SERVER CAN SEE, and it is the only feature here that can. The server holds a position authority: your client streams its root CFrame every tick and the server answers with Characters.MovementCorrection when it disagrees (0259.lua:715) -- under 15 studs it lerps you back, over 15 it hard-snaps you. The tolerance is not in the dump. Boots at stock and is capped at 1.15x for that reason. Step it up 0.02 at a time and watch the correction counter in Live proof: a baseline of 0 corrections was measured on this account on 2026-09-09. The first value that makes corrections appear is your ceiling, and it is one you can measure instead of guess.")

W.section(page, "Visuals")
W.toggle(page, { label = "Ball chams (red)", key = "ballCham",
	desc = "Red outline + fill on the match ball, visible through players and the goal net. Read-only: one Highlight on the ball's own skin model, no per-frame work.",
	set = function(v) cfg.ballCham = v; applyBallCham() end })

W.section(page, "Items")
W.toggle(page, { label = "Item box markers", key = "boxEsp",
	desc = "Draws every GameplayItemBox. Read-only.",
	set = function(v) cfg.boxEsp = v; applyBoxEsp() end })
W.note(page, "Pickup range cannot be extended: the claim is server-side and the client has no claim command (ItemCommands.Kinds, 0411.lua:11). Walking into the box is the only path.")

W.section(page, "Live proof")
-- Reads the game's own stamina back every paint. If "Infinite stamina" is ON and
-- this does not sit at 1.000 while you sprint, the feature is NOT armed -- which
-- is exactly the failure that looked like a lobby/match dependency on 2026-09-09
-- (the module had been torn down; nobody could tell from the panel).
W.statusRow(page, function()
	local st, armed = -1, false
	if CSprint and CSprint.GetStamina then
		local ok, v = pcall(CSprint.GetStamina)
		if ok and type(v) == "number" then st = v end
	end
	armed = staminaSourceRegistered()
	return string.format("Stamina %.3f  |  our source registered: %s  |  features live: %s",
		st, armed and "YES" or "NO", state.armed and "YES" or "NO")
end)

-- The real Humanoid.WalkSpeed, next to what the base constant currently says.
-- Same reason as the stamina row: every slowdown in this game lands as a number
-- on the humanoid, so the dip toggles are checkable by watching this while you
-- kick, steal or dribble instead of by trusting the label.
W.statusRow(page, function()
	local char = LP.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local live = hum and hum.WalkSpeed or -1
	local base = ActionMovement and ActionMovement.Constants.BaseWalkSpeed or -1
	local sources = "?"
	if Movement and Movement.GetZeroWalkSpeedSources then
		local ok, list = pcall(Movement.GetZeroWalkSpeedSources)
		if ok and type(list) == "table" then
			sources = #list == 0 and "none" or table.concat(list, ",")
		end
	end
	return string.format("WalkSpeed now %.2f  |  base constant %.2f (stock %s)  |  zeroing you: %s",
		live, base, origBaseWs and string.format("%.0f", origBaseWs) or "16", sources)
end)

W.section(page, "Server telemetry (always on)")
W.statusRow(page, function()
	return string.format("Rejects: %d (last %s)  |  Corrections: %d  |  Max snap: %.1f studs  |  Boxes: %d  |  Cham: %s",
		state.rejects, state.lastReject, state.corrections, state.maxSnap, state.boxes,
		state.chamOn and "attached" or (cfg.ballCham and "no ball" or "off"))
end)
W.note(page, "Baseline with nothing armed was 0 rejects and 0 corrections in 75s. Anything above zero here is caused by what is switched on above.")

Shell.ready()

-- The panel exists, so a saved-ON feature now has a visible control that can
-- turn it off again. Only now do we touch the game's tables.
applyAll()
state.armed = true

Log.info(string.format("boot %s stam=%s dip=%s chargeSpeed=%.2f boxEsp=%s ws=%.2f carrier=%s drib=%s",
	BUILD_VERSION, tostring(cfg.infStamina),
	tostring(cfg.noKickDip), cfg.chargeSpeed, tostring(cfg.boxEsp),
	cfg.walkSpeed, tostring(cfg.noCarrierDip), tostring(cfg.noDribbleDip)))
