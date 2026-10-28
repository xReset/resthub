------------------------------------------------------------------------
-- Evade Kit v1.7.0-2026-10-24.1 -- PlaceId 9872472334
--
-- Every feature below drives the GAME'S OWN client code down the GAME'S
-- OWN code path. We add no remote, no new payload shape, no new instance
-- in the character, and no motion the shipped client cannot already
-- produce. Dump: game_dumps/9872472334/2026-08-22T13-47-23Z_*/
--
-- ANTICHEAT GATE (anticheat_deep.txt SUMMARY, this dump):
--   ENFORCEMENT 3   -> all three are false positives: 3380:166/252 is the
--                      staff admin command module (BanAsync/Kick), 3538:822
--                      is the RelicsXYZ partnership session kick.
--   REPORTING 0, CLIENT INSPECTION 0  -> the game never examines the client.
--   LOG MONITORING 2 -> both are the React prod-error formatter
--                      (3154:33, 3187:7). Neither connects to MessageOut.
--   MOVEMENT CHECKS 182 / THRESHOLDS 10 -> every one is Roblox's stock
--                      PlayerModule CameraModule. Zero game-authored speed,
--                      fly or teleport validation exists client-side.
--   Last session ended DisconnectClientInitiated (Roblox log), not a kick.
--   Hyperion is engine-level and never appears in a dump. Server-side
--   passive logging is invisible from here -> dump-clean is not a licence
--   to be loud. See LOUD/REJECTED at the bottom of this header.
--
-- ARCHITECTURE (why this game is unusually client-owned):
--   Evade splits the visual rig (Workspace.Rigs.<name>) from the physics
--   body (Workspace.Players.<name>.HumanoidRootPart). The local HRP is
--   network-owned by us (network_ownership.txt) and ALL movement is client
--   physics via LinearVelocity/AlignPosition constraints written by
--   Objects.Game.Character.Client.Movement (2728/2729/2730/2731/2733).
--   The client uploads a WHITELISTED set of character terms to the server
--   at 10 Hz (DataRegistry:UpdateCycle, 2739:82 -> UpdateCharacterDataRegistry).
--   Shared.Networking.Terms (3434) says ClientSendable = true for exactly:
--     LookY, Equipped, RelativeMoveDirection, Speed, Gyro, State,
--     CanBeCarried, Steer.
--   Everything that matters for scoring -- Downed, Carried, Perks, Health --
--   is ClientSendable = false. Read that as: the server trusts our motion
--   and our reported Speed, and owns everything else.
--
-- FEATURES
--  1. AUTO-BHOP (hold Space) -- rung 3, byte-identical to a controller.
--     InputService (3298:135-136) sets, for gamepad ButtonA only:
--       Movement:JumpReact(true); Movement.XboxJumping = true
--     Movement.Update (2728:295) then runs AttemptJump(stats, true) EVERY
--     frame while XboxJumping is true, and Update is driven by
--     RenderStepped (3263:281). AttemptJump does not consult CanJump, so
--     it fires on the exact first frame Grounded flips true. That is the
--     fastest bhop the engine can express -- there is no earlier frame --
--     and it is a shipped feature, not an added one. We mirror the one
--     field on Space. The game's own InputEnded (3298:143) already clears
--     XboxJumping on Space release; we clear it too.
--     Speed gain is the game's own: Jump (2728:450) rescales velocity to
--     min(mag * JumpSpeedMultiplier, Sprint * Speed * v84) with
--     JumpSpeedMultiplier 1.45 (2734) -- a vanilla ceiling of about
--     1500 * 2 * 1.45 / 90 = 48.3 studs/s. We do NOT set BhopEnabled
--     (2734:20, false) because that is a non-vanilla state and the 1.45x
--     cap is already reached without it.
--     Server sees: normal jump physics. JumpingActive is absent from
--     Terms (3434), so it never leaves the client.
--
--  2. AUTO-REVIVE (Defibrillator) -- rung 3, no range extension.
--     Tools.Defibrillator (3640): keybind Primary, Requirements
--     { ReviveTarget = true }, Cooldown 1.2, consumes one charge.
--     Revive.UpdateClient (2790:109) runs the game's own acquisition at
--     10 Hz and parks the winner on the rig's Tool.Highlight (Adornee +
--     Enabled). RequirementFunctions.ReviveTarget (2780:84) reads exactly
--     that Highlight.Adornee and nothing else.
--     GEOMETRY (2790:53): a SPHERE of radius 7 centred on
--       camera.Position + camera.lookVector * 4
--     -- not a cone. Reach is ~11 studs dead ahead, ~3 studs behind you,
--     7 to either side. Nearest valid target wins. Filters: same Team,
--     Downed, not Ragdolling, Carried == 0, and v ~= own Character.
--     TIMING: the defib revive is INSTANT server-side -- ActivateServer
--     calls v40:Revive(v37) straight through (2790:178), no channel. The
--     only latency is ours: <=0.1 s for the game's own 10 Hz acquisition,
--     <=0.05 s for our 20 Hz reconcile, plus 0.12-0.26 s jitter, so about
--     0.17-0.41 s from "target valid" to "key pressed". Repeat presses are
--     gated at 1.35 s against the tool's own 1.2 s cooldown (3640).
--     The OTHER revive -- bare-hands hold E (InteractionService 3270:41) --
--     channels for DataRegistry ReviveLength (1.5 s default, 3268:37) and
--     is explicitly disabled while the defib is out
--     (Requirements.NotEquipped = { "Defibrillator" }). The two are
--     mutually exclusive; this kit automates only the instant one.
--     So: we watch the game's own highlight and, when it is lit, press the
--     game's own key. The press is the game's own synthetic press --
--     GameUIService.Types.Actions (3325:143) does literally
--       CharacterService:KeyUsed{Down=true,  Key=<bind>}; task.wait()
--       CharacterService:KeyUsed{Down=false, Key=<bind>}
--     for every mobile button. Character:KeyUsed (2711:177) fans out to
--     ToolProfile/Camera/Movement/Actions/Animations, so viewmodel, sound
--     and animation all run exactly as on a real click.
--     Reaction is jittered 120-260 ms after acquisition; cooldown is the
--     tool's own 1.2 s plus margin.
--     DELIBERATELY NOT EXPLOITED: Revive.ActivateServer (2790:138) checks
--     item ownership, Downed, Carried and Health <= 0 -- and NO distance.
--     A crafted ToolAction would revive any downed teammate map-wide. That
--     is the single most narratable thing in this game, so the 7-stud sphere
--     stays the game's. This script never sends a tag the game did not
--     already select.
--
--  3. SPEED -- rung 3, conservative, OFF by default.
--     MoveStats:SpeedChange (2733:146) is the game's own multiplier
--     channel; UpdateAttributes (2733:133) folds every entry onto
--     BaseSpeed, and SpeedChanges survives Reset(). It is the same channel
--     the server drives for speed pads and perks (3263:29 Movement task).
--     HONEST RISK: Speed IS ClientSendable (Terms ID 13) and Movement.Update
--     (2728:301) uploads floor(velocity.Magnitude/90*10)/10 every cycle.
--     Any multiplier is therefore self-reported telemetry. It is clamped to
--     1.25 because vanilla bhop already reports up to ~48 studs/s, so a
--     sprint of ~38 sits inside a band the server sees from ordinary
--     players. Above that it does not, and no clamp makes it safe.
--
--  4. MATCH TIMER -- rung 1, pure read.
--     ServerStateRegistryService (3308) mirrors server pushes. Time is
--     seconds remaining; RoundStatus == 2 is ROUND ACTIVE, anything else
--     is INTERMISSION -- exactly how Menu.Views.Spectate (2946:50-63)
--     renders it, same MM:SS format, same two labels. We mirror
--     ChangedEvent ourselves rather than trusting a require cache.
--
--  5. NEXTBOT RADAR + 6. DOWNED LIST -- rung 1, pure read, own GUI only.
--     Nextbots are Workspace.Players.<name> with @AI=true, @Team="Nextbot"
--     (trees/Workspace.txt:24742). Players carry @Team="PlayerTeam".
--     Downed comes off each character's own DataRegistry. These two reads
--     render only as text in our own ScreenGui.
--
--  7. PLAYER ESP -- rung 1 reads, rung 2 client-only visuals.
--     Character.Rig:GetRigModel() is the rendered Workspace.Rigs body used
--     by the game itself (2704:97, 2707:61). Workspace.Players contains the
--     split physics body, not the rendered avatar (characters.txt). One
--     outline-only Highlight and one name BillboardGui are parented under
--     our GUI host and point at each non-local PlayerReference rig. No bars,
--     boxes, tracers, distance, target-part writes, or enemy adornment parent.
--
--  8. NEXTBOT ESP -- rung 1 reads, rung 2 client-only visuals.
--     Workspace.Players holds each AI physics shell and its BillboardGui image
--     (trees/Workspace.txt:24742-25036). Live probe 2026-08-25 proved the
--     matching Workspace.Rigs body is only a Transparency=1 Hitbox, which a
--     Highlight cannot outline. A red always-on-top box marks the physics root.
--
--  9. FIRST-PERSON BODY HIDE -- local visual write, always automatic.
--     Camera.Update uses CameraMaxZoomDistance <= 0.6 as its exact first-person
--     branch (2724:82-89). While true, LocalTransparencyModifier=1 is applied
--     only to BaseParts in our rendered Rig:GetRigModel(). Third person,
--     respawn, and unload restore every captured value. The separate tool
--     viewmodel stays under the game's own ShowViewmodel path (2724:82-84).
--
-- POSTURE (potassium-dev 5.7)
--   1. Rung 3 for 1-3, rung 1 for 4-6, rung 1+2 for 7-8. Rung 6 is never
--      taken directly: the only FireServer that happens is the one the
--      game itself makes from its own Activate path.
--   2. No print/warn anywhere. File log only.
--   3. Movement writes go through MoveStats, the game's own tolerance
--      surface. No CFrame writes, no direct velocity writes.
--   4. Nothing here is narratable by another player except speed above
--      ~1.25x, which is why that is clamped and defaults OFF.
--   5. Toggles persist to evade_kit_cfg.json and are restored on load, so
--      "everything OFF on load" is traded for "nothing restored silently":
--      the panel shows a RESTORED ON banner naming each feature that came
--      back, for 8 s, and the same list goes to the log. The hazard in
--      potassium-dev 0.2 #2 is a feature going live in a lobby BEFORE you
--      meant it to -- that is a surprise problem, and the banner is what
--      removes the surprise. First-ever load has no file, so it is still
--      all-OFF. destroy() restores SpeedChange to nil, clears XboxJumping
--      and removes the GUI.
--   6. Backed by anticheat_deep.txt SUMMARY + 3434 Terms + 2728/2733/2790.
--
-- LOUD / REJECTED -- do not revive these without new evidence:
--   * VerifyRange lie. CharacterService (3263:306) answers a SERVER
--     InvokeClient asking "are you within N studs of tag T". Returning
--     false dodges nextbot attacks between NoVerifyRange 2 and
--     VerifyRange 4 (0552:80). Tasks.TestRange (2763:109) tolerates only
--     4 disagreements per rolling 3 s; the 5th forces damage through AND
--     the server prints
--       "<name> damage has been overriden due to too many failures of
--        range checks"   (2763:183)
--     A named line in the server console is the loudest thing available
--     in this game. Hard no.
--   * Map-wide revive. See feature 2.
--   * BhopEnabled = true. See feature 1.
--
-- CHANGELOG
--   v1.7.0-2026-10-24.1 -- remove undefined layerHost value from GUI startup log.
--   v1.3.0 -- match native ReviveTarget Adornee test; expose gated/error state.
--   v1.3.1 -- remove diagnostic state layer that Potassium rejected at load.
--   v1.4.0 -- clean player names + outline ESP on rendered Evade rigs.
--   v1.4.1 -- hide local rendered body while Evade is in first person.
--   v1.5.0 -- red outline ESP on tag-matched rendered nextbot rigs.
--   v1.5.1 -- pin first-person body hidden after camera on every render frame.
--   v1.6.0 -- draw nextbot ESP around its invisible physics root; rendered rigs
--             are transparent hitboxes and cannot produce a Highlight outline.
--   v1.7.0 -- keep panel visible and clickable above the Roblox Escape menu;
--             non-modal so shift-lock and normal mouse control still work.
--
-- Hotkeys: RightShift = hide panel, RightControl = unload.
-- Re-inject safe: self-teardown on load.
-- Settings: evade_kit_cfg.json (toggles, speed multiplier, panel position
-- and hidden state). Written at most 1 Hz, and once on unload before the
-- teardown zeroes the toggles. Type-checked and re-clamped on read, so a
-- corrupt or hand-edited file degrades to defaults instead of throwing.
------------------------------------------------------------------------

local BUILD_VERSION = "EVADE-1.7.0-2026-10-24.1"
local EXPECTED_PLACE = 9872472334
local GKEY = "__EVADE_KIT"

-- hub.lua publishes __R3ST_HOST immediately before running us and clears it the
-- moment we return. When it is set, the hub owns the ScreenGui, the window
-- chrome, the drag and RightShift, so the CONTROL PANEL renders inside its
-- content host. The ESP/visual layer is deliberately left alone: it has to stay
-- a full-screen CoreGui layer, never a child of a hub panel.
local __HUBENV = (type(getgenv) == "function" and getgenv()) or _G
local HOST = (type(__HUBENV.__R3ST_HOST) == "table"
	and typeof(__HUBENV.__R3ST_HOST.host) == "Instance") and __HUBENV.__R3ST_HOST or nil

local FIRST_PERSON_BIND = "EK_FirstPersonBody"
local LOG_FILE = "logs/evade_kit.log"
local CFG_FILE = "evade_kit_cfg.json"

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer

local G = (getgenv and getgenv()) or _G
if type(G) ~= "table" then
	G = _G
end

if type(G[GKEY]) == "table" and type(G[GKEY].destroy) == "function" then
	pcall(G[GKEY].destroy)
end

------------------------------------------------------------------------
-- config -- every behaviour toggle starts OFF (potassium-dev 0.2 #2)
------------------------------------------------------------------------

local CFG = {
	bhop = false,
	autoRevive = false,
	playerEsp = false,
	nextbotEsp = false,
	speed = false,

	speedMult = 1.10,
	speedMax = 1.25, -- hard ceiling, see header feature 3

	reviveMinDelay = 0.12, -- human reaction floor after acquisition
	reviveMaxDelay = 0.26,
	reviveCooldown = 1.35, -- tool cooldown is 1.2 (3640), plus margin

	hud = true,
	panelX = 24,
	panelY = 190,
	panelHidden = false,
}

-- Persisted across injects and sessions. Every entry is type-checked and
-- range-clamped on load; a corrupt or hand-edited file degrades to defaults
-- rather than throwing.
local SAVE_KEYS = {
	bhop = "boolean",
	autoRevive = "boolean",
	playerEsp = "boolean",
	nextbotEsp = "boolean",
	speed = "boolean",
	speedMult = "number",
	hud = "boolean",
	panelX = "number",
	panelY = "number",
	panelHidden = "boolean",
}

local SPEED_KEY = "EKSpeed" -- our own SpeedChanges slot; never collides

local S = {
	stats = { revives = 0, jumpsArmed = 0 },
	esp = {},
	nextbotEsp = {},
	firstPersonParts = {},
	firstPersonScanAt = 0,
}

------------------------------------------------------------------------
-- file logger -- no print/warn, ever (see header posture 2)
------------------------------------------------------------------------

local logReady, logExists = false, false

local function log(level, msg, data)
	local line = string.format("[%s] [%s] %s", os.date("%H:%M:%S"), level, tostring(msg))
	if type(data) == "table" then
		local parts = {}
		for k, v in pairs(data) do
			parts[#parts + 1] = tostring(k) .. "=" .. tostring(v)
		end
		table.sort(parts)
		line = line .. " | " .. table.concat(parts, " ")
	elseif data ~= nil then
		line = line .. " | " .. tostring(data)
	end
	pcall(function()
		if not logReady then
			logReady = true
			if isfolder and makefolder and not isfolder("logs") then
				makefolder("logs")
			end
			-- appendfile needs the file to exist first, or it silently no-ops
			if isfile then
				logExists = isfile(LOG_FILE)
			end
		end
		if logExists and appendfile then
			appendfile(LOG_FILE, line .. "\n")
		elseif writefile then
			writefile(LOG_FILE, line .. "\n")
			logExists = true
		end
	end)
end

log("INFO", "load", { build = BUILD_VERSION, place = game.PlaceId })
if game.PlaceId ~= EXPECTED_PLACE then
	log("WARN", "place_mismatch", { expected = EXPECTED_PLACE, actual = game.PlaceId })
end

------------------------------------------------------------------------
-- settings persistence
--
-- potassium-dev 0.2 #2 says a feature left ON through an inject is a real
-- hazard -- it goes live in a lobby before you meant it to. The hazard
-- there is SURPRISE, not persistence, so restored state is logged and the
-- panel shows a restore banner naming exactly what came back on.
------------------------------------------------------------------------

local restored = {}

local function loadCfg()
	if type(isfile) ~= "function" or type(readfile) ~= "function" then
		return
	end
	local exists = false
	pcall(function()
		exists = isfile(CFG_FILE)
	end)
	if not exists then
		return
	end

	local ok, raw = pcall(readfile, CFG_FILE)
	if not ok or type(raw) ~= "string" or raw == "" then
		log("WARN", "cfg_unreadable")
		return
	end

	local ok2, data = pcall(function()
		return HttpService:JSONDecode(raw)
	end)
	if not ok2 or type(data) ~= "table" then
		log("WARN", "cfg_corrupt")
		return
	end

	local n = 0
	for key, wantType in pairs(SAVE_KEYS) do
		local v = data[key]
		if type(v) == wantType then
			CFG[key] = v
			n = n + 1
		end
	end

	-- re-clamp everything; the file is user-editable and may be stale
	CFG.speedMult = math.clamp(tonumber(CFG.speedMult) or 1, 1, CFG.speedMax)
	CFG.panelX = math.clamp(math.floor(CFG.panelX), 0, 6000)
	CFG.panelY = math.clamp(math.floor(CFG.panelY), 0, 6000)

	if CFG.bhop then
		restored[#restored + 1] = "bhop"
	end
	if CFG.autoRevive then
		restored[#restored + 1] = "revive"
	end
	if CFG.playerEsp then
		restored[#restored + 1] = "esp"
	end
	if CFG.nextbotEsp then
		restored[#restored + 1] = "nextbot esp"
	end
	if CFG.speed then
		restored[#restored + 1] = string.format("speed %.2fx", CFG.speedMult)
	end

	log("INFO", "cfg_loaded", {
		fields = n,
		restoredOn = #restored > 0 and table.concat(restored, ",") or "none",
	})
end

local saveDirty, lastSaveAt = false, 0

local function markDirty()
	saveDirty = true
end

local function saveCfg()
	saveDirty = false
	lastSaveAt = os.clock()
	if type(writefile) ~= "function" then
		return
	end
	local out = {}
	for key in pairs(SAVE_KEYS) do
		out[key] = CFG[key]
	end
	pcall(function()
		writefile(CFG_FILE, HttpService:JSONEncode(out))
	end)
end

loadCfg()

------------------------------------------------------------------------
-- CharacterService resolution
--
-- require() normally hands back the same cached module table the game's
-- own LocalScripts hold. If this executor keeps a separate module cache
-- the copy is inert (its .Characters stays empty forever), so we fall
-- back to finding the live table on the GC heap. Walk with next, not
-- pairs, and rawget everything -- 2711 characters carry metatables and
-- pairs()/__index would run game code (potassium-dev 4).
------------------------------------------------------------------------

local charService = nil
local lastServiceScan = 0

local function serviceLooksLive(svc)
	if type(svc) ~= "table" then
		return false
	end
	local chars = rawget(svc, "Characters")
	if type(chars) ~= "table" then
		return false
	end
	for _, c in next, chars do
		if type(c) == "table" and rawget(c, "Model") ~= nil and rawget(c, "DataRegistry") ~= nil then
			return true
		end
	end
	return false
end

local function findServiceOnHeap()
	if type(getgc) ~= "function" then
		return nil
	end
	local ok, heap = pcall(getgc, true)
	if not ok or type(heap) ~= "table" then
		return nil
	end
	for _, v in next, heap do
		if type(v) == "table" then
			local ok2, live = pcall(serviceLooksLive, v)
			if ok2 and live then
				return v
			end
		end
	end
	return nil
end

local function requireService()
	local ok, svc = pcall(function()
		local services = ReplicatedStorage:WaitForChild("Services", 5)
		if not services then
			return nil
		end
		local asset = services:WaitForChild("Asset", 5)
		if not asset then
			return nil
		end
		local mod = asset:WaitForChild("CharacterService", 5)
		if not mod then
			return nil
		end
		return require(mod)
	end)
	if ok then
		return svc
	end
	return nil
end

local function getService()
	if serviceLooksLive(charService) then
		return charService
	end
	local now = os.clock()
	if now - lastServiceScan < 2 then
		return charService
	end
	lastServiceScan = now

	local svc = requireService()
	if serviceLooksLive(svc) then
		charService = svc
		log("INFO", "service_resolved", { via = "require" })
		return charService
	end

	local heapSvc = findServiceOnHeap()
	if heapSvc then
		charService = heapSvc
		log("INFO", "service_resolved", { via = "getgc" })
		return charService
	end

	-- keep whatever we had; it may just be a between-rounds empty roster
	if svc ~= nil and charService == nil then
		charService = svc
	end
	return charService
end

local function getLocalChar()
	local svc = getService()
	if type(svc) ~= "table" then
		return nil
	end
	local chars = rawget(svc, "Characters")
	if type(chars) ~= "table" then
		return nil
	end
	for _, c in next, chars do
		if type(c) == "table" and rawget(c, "Local") == true then
			return c
		end
	end
	return nil
end

------------------------------------------------------------------------
-- 1. AUTO-BHOP -- mirror the shipped controller field (3298:136)
------------------------------------------------------------------------

local spaceHeld = false

local function applyBhop(ch)
	local movement = ch and rawget(ch, "Movement")
	if type(movement) ~= "table" then
		return
	end
	local want = (CFG.bhop and spaceHeld) or false
	if movement.XboxJumping ~= want then
		movement.XboxJumping = want
		if want then
			-- counted, not logged: this fires on every Space press and wrote
			-- ~12 KB of identical lines in 35 minutes. The 60 s alive line
			-- carries the running total instead.
			S.stats.jumpsArmed = S.stats.jumpsArmed + 1
		end
	end
end

local function clearBhop()
	local ch = getLocalChar()
	local movement = ch and rawget(ch, "Movement")
	if type(movement) == "table" and movement.XboxJumping == true then
		movement.XboxJumping = false
	end
end

------------------------------------------------------------------------
-- 3. SPEED -- the game's own SpeedChange channel (2733:146)
------------------------------------------------------------------------

local speedApplied = nil

local function applySpeed(ch)
	local movement = ch and rawget(ch, "Movement")
	local moveStats = movement and rawget(movement, "MoveStats")
	if type(moveStats) ~= "table" or type(moveStats.SpeedChange) ~= "function" then
		return
	end

	local want = nil
	if CFG.speed then
		want = math.clamp(CFG.speedMult, 1, CFG.speedMax)
	end

	-- SpeedChange early-returns when unchanged, but a respawn builds a new
	-- MoveStats whose SpeedChanges table is empty, so reconcile on identity
	-- of the table too, not just on the value we last asked for.
	local live = rawget(moveStats, "SpeedChanges")
	local current = type(live) == "table" and live[SPEED_KEY] or nil
	if current == want and speedApplied == want then
		return
	end

	pcall(function()
		moveStats:SpeedChange(SPEED_KEY, want)
	end)
	speedApplied = want
	log("INFO", "speed_set", { mult = want or "off" })
end

local function clearSpeed()
	local ch = getLocalChar()
	local movement = ch and rawget(ch, "Movement")
	local moveStats = movement and rawget(movement, "MoveStats")
	if type(moveStats) == "table" and type(moveStats.SpeedChange) == "function" then
		pcall(function()
			moveStats:SpeedChange(SPEED_KEY, nil)
		end)
	end
	speedApplied = nil
end

------------------------------------------------------------------------
-- 2. AUTO-REVIVE -- watch the game's highlight, press the game's key
------------------------------------------------------------------------

local reviveArmAt = nil
local reviveNextAt = 0

-- Mirrors Revive.GetHighlight (2790:72) exactly.
local function getReviveHighlight(ch)
	local rig = rawget(ch, "Rig")
	if type(rig) ~= "table" or type(rig.GetRigModel) ~= "function" then
		return nil
	end
	local ok, hl = pcall(function()
		local model = rig:GetRigModel()
		if not model then
			return nil
		end
		local tool = model:FindFirstChild("Tool")
		if not tool then
			return nil
		end
		return tool:FindFirstChild("Highlight")
	end)
	if not ok then
		return nil
	end
	return hl
end

-- The rig's Tool.Highlight belongs to whatever tool is currently held, so a
-- lit highlight is NOT by itself proof the defib is up -- pressing Primary
-- with a gun equipped would fire it. Confirm the equipped tool actually
-- owns a Revive method first. Structural, so skins and variants still pass:
-- Tool.Info is the required tool module (2775:19) and the framework resolves
-- methods through MethodReferences (2779), which for Tools.Defibrillator
-- (3640) is { Revive = { Type = "Revive" } }.
local function toolHasRevive(tool)
	local info = type(tool) == "table" and rawget(tool, "Info") or nil
	if type(info) ~= "table" or type(info.Tasks) ~= "table" then
		return false
	end
	for _, entry in next, info.Tasks do
		local refs = type(entry) == "table" and entry.MethodReferences or nil
		if type(refs) == "table" then
			for _, ref in next, refs do
				if type(ref) == "table" and ref.Type == "Revive" then
					return true
				end
			end
		end
	end
	return false
end

local function defibEquipped(ch)
	local tp = rawget(ch, "ToolProfile")
	if type(tp) ~= "table" or type(tp.GetCurrentTool) ~= "function" then
		return false
	end
	local ok, tool = pcall(function()
		return tp:GetCurrentTool()
	end)
	if not ok or type(tool) ~= "table" then
		return false
	end
	return toolHasRevive(tool)
end

-- RequirementFunctions.ReviveTarget (2780:84) tests exactly this.
local function hasReviveTarget(ch)
	if not defibEquipped(ch) then
		return false
	end
	local hl = getReviveHighlight(ch)
	if not hl then
		return false
	end
	local ok, valid = pcall(function()
		return hl.Adornee ~= nil and hl.Adornee.Parent ~= nil
	end)
	return ok and valid or false
end

-- The game's own synthetic press, verbatim from GameUIService.Types.Actions
-- (3325:143). Character:KeyUsed (2711:177) fans out to every subsystem.
local function pressPrimary(ch)
	if type(ch.KeyUsed) ~= "function" then
		return false
	end
	local ok = pcall(function()
		ch:KeyUsed({ Down = true, Key = "Primary" })
	end)
	if not ok then
		return false
	end
	task.wait()
	pcall(function()
		ch:KeyUsed({ Down = false, Key = "Primary" })
	end)
	return true
end

local function tickRevive(ch, now)
	if not CFG.autoRevive then
		reviveArmAt = nil
		return
	end

	if not hasReviveTarget(ch) then
		reviveArmAt = nil
		return
	end

	-- fresh acquisition: pay a human reaction cost before the first press
	if reviveArmAt == nil then
		reviveArmAt = now + CFG.reviveMinDelay
			+ math.random() * (CFG.reviveMaxDelay - CFG.reviveMinDelay)
		return
	end

	if now < reviveArmAt or now < reviveNextAt then
		return
	end

	if pressPrimary(ch) then
		S.stats.revives = S.stats.revives + 1
		reviveNextAt = now + CFG.reviveCooldown
		reviveArmAt = nil
		log("INFO", "revive_pressed", { n = S.stats.revives })
	end
end

------------------------------------------------------------------------
-- 4. MATCH TIMER -- mirror ServerStateRegistry pushes ourselves (3308)
------------------------------------------------------------------------

local stateMirror = {}
local stateConn = nil

local function bindStateRegistry()
	pcall(function()
		local services = ReplicatedStorage:WaitForChild("Services", 5)
		local data = services and services:WaitForChild("Data", 5)
		local mod = data and data:WaitForChild("ServerStateRegistryService", 5)
		local changed = mod and mod:WaitForChild("ChangedEvent", 5)
		if changed then
			stateConn = changed.Event:Connect(function(key, value)
				stateMirror[key] = value
			end)
			log("INFO", "state_registry_bound", { via = "ChangedEvent" })
		end
	end)

	-- seed from the module's own table when the require cache is shared
	pcall(function()
		local mod = ReplicatedStorage.Services.Data.ServerStateRegistryService
		local svc = require(mod)
		local reg = type(svc) == "table" and rawget(svc, "Registry") or nil
		if type(reg) == "table" then
			for k, v in next, reg do
				if stateMirror[k] == nil then
					stateMirror[k] = v
				end
			end
		end
	end)
end

-- Same format and the same two labels as Menu.Views.Spectate (2946:50-63).
local function roundText()
	local t = tonumber(stateMirror.Time) or 0
	t = math.max(0, t)
	local mm = math.floor(t / 60)
	local ss = math.floor(t) % 60
	local label = (stateMirror.RoundStatus == 2) and "ROUND ACTIVE" or "INTERMISSION"
	if stateMirror.MapLoading then
		label = "MAP LOADING"
	end
	return string.format("%d:%02d", mm, ss), label
end

------------------------------------------------------------------------
-- 5 + 6. RADAR / DOWNED -- read only (trees/Workspace.txt:24742)
------------------------------------------------------------------------

local function localRoot(ch)
	local model = ch and rawget(ch, "Model")
	if typeof(model) == "Instance" then
		return model.PrimaryPart
	end
	return nil
end

local function restoreFirstPersonBody()
	for part, original in pairs(S.firstPersonParts) do
		pcall(function()
			if part.Parent then
				part.LocalTransparencyModifier = original
			end
		end)
		S.firstPersonParts[part] = nil
	end
	S.firstPersonRig = nil
	S.firstPersonScanAt = 0
end

local function reconcileFirstPersonBody(ch)
	local rig = nil
	if ch and LocalPlayer.CameraMaxZoomDistance <= 0.6 then
		local rigApi = rawget(ch, "Rig")
		if type(rigApi) == "table" and type(rigApi.GetRigModel) == "function" then
			rig = rigApi:GetRigModel()
		end
	end
	if not rig or not rig.Parent then
		restoreFirstPersonBody()
		return
	end
	if S.firstPersonRig ~= rig then
		restoreFirstPersonBody()
		S.firstPersonRig = rig
	end
	local now = os.clock()
	if now >= S.firstPersonScanAt then
		S.firstPersonScanAt = now + 0.5
		for _, descendant in ipairs(rig:GetDescendants()) do
			if descendant:IsA("BasePart") and S.firstPersonParts[descendant] == nil then
				S.firstPersonParts[descendant] = descendant.LocalTransparencyModifier
			end
		end
	end
	for part in pairs(S.firstPersonParts) do
		if part.Parent then
			part.LocalTransparencyModifier = 1
		else
			S.firstPersonParts[part] = nil
		end
	end
end

local function nearestNextbot(root)
	if not root then
		return nil, nil
	end
	local folder = workspace:FindFirstChild("Players")
	if not folder then
		return nil, nil
	end
	local bestName, bestDist = nil, nil
	for _, model in ipairs(folder:GetChildren()) do
		if model:GetAttribute("AI") == true and model.PrimaryPart then
			local d = (model.PrimaryPart.Position - root.Position).Magnitude
			if bestDist == nil or d < bestDist then
				bestDist, bestName = d, model.Name
			end
		end
	end
	return bestName, bestDist
end

local function downedTeammates(ch, root)
	local svc = getService()
	local chars = type(svc) == "table" and rawget(svc, "Characters") or nil
	if type(chars) ~= "table" or not root or not ch then
		return {}
	end
	local myTeam = nil
	pcall(function()
		myTeam = rawget(ch, "Model"):GetAttribute("Team")
	end)

	local out = {}
	for _, c in next, chars do
		if type(c) == "table" and c ~= ch then
			local ok = pcall(function()
				local model = rawget(c, "Model")
				local reg = rawget(c, "DataRegistry")
				if not model or type(reg) ~= "table" or type(reg.Get) ~= "function" then
					return
				end
				if model:GetAttribute("Team") ~= myTeam then
					return
				end
				if reg:Get("Downed") ~= true then
					return
				end
				if not model.PrimaryPart then
					return
				end
				out[#out + 1] = {
					name = model.Name,
					dist = (model.PrimaryPart.Position - root.Position).Magnitude,
				}
			end)
			if not ok then
				-- a character teardown mid-walk; skip it
			end
		end
	end
	table.sort(out, function(a, b)
		return a.dist < b.dist
	end)
	return out
end

------------------------------------------------------------------------
-- GUI (our own ScreenGui only; nothing adorned to any game part)
------------------------------------------------------------------------

local COL = {
	bg = Color3.fromRGB(18, 20, 24),
	panel = Color3.fromRGB(26, 29, 35),
	stroke = Color3.fromRGB(60, 66, 78),
	text = Color3.fromRGB(226, 230, 238),
	dim = Color3.fromRGB(140, 148, 162),
	on = Color3.fromRGB(84, 200, 130),
	off = Color3.fromRGB(88, 94, 108),
	warn = Color3.fromRGB(226, 172, 84),
}

local function mk(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do
		inst[k] = v
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function coreGuiHost()
	local core = game:GetService("CoreGui")
	if type(cloneref) == "function" then
		local ok, cloned = pcall(cloneref, core)
		if ok and cloned then
			return cloned
		end
	end
	return core
end

local gui = { conns = {}, rows = {} }

local function clearPlayerEsp()
	for character, entry in pairs(S.esp) do
		if entry.hl then
			entry.hl:Destroy()
		end
		if entry.name then
			entry.name:Destroy()
		end
		S.esp[character] = nil
	end
end

local function playerEspEntry(character, rig, player)
	local entry = S.esp[character]
	if entry and entry.rig ~= rig then
		if entry.hl then entry.hl:Destroy() end
		if entry.name then entry.name:Destroy() end
		entry = nil
	end
	if not entry then
		local hl = Instance.new("Highlight")
		hl.Name = "EKOutline"
		hl.FillTransparency = 1
		hl.OutlineTransparency = 0
		hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		hl.Adornee = rig
		hl.Parent = gui.visuals

		local bb = Instance.new("BillboardGui")
		bb.Name = "EKName"
		bb.AlwaysOnTop = true
		bb.Size = UDim2.fromOffset(180, 22)
		bb.StudsOffset = Vector3.new(0, 2.8, 0)
		bb.MaxDistance = 600
		bb.Adornee = rig:FindFirstChild("Head") or rig.PrimaryPart
		bb.Parent = gui.visuals

		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.GothamBold
		label.Text = player.Name
		label.TextColor3 = Color3.fromRGB(235, 240, 248)
		label.TextSize = 13
		label.TextStrokeColor3 = Color3.fromRGB(10, 12, 16)
		label.TextStrokeTransparency = 0.2
		label.Parent = bb

		entry = { rig = rig, hl = hl, name = bb }
		S.esp[character] = entry
	end
	return entry
end

local function reconcilePlayerEsp(localCharacter)
	if not CFG.playerEsp or not gui.visuals then
		clearPlayerEsp()
		return
	end
	local svc = getService()
	local chars = type(svc) == "table" and rawget(svc, "Characters") or nil
	if type(chars) ~= "table" then
		clearPlayerEsp()
		return
	end

	local seen = {}
	for _, character in next, chars do
		if type(character) == "table" and character ~= localCharacter and rawget(character, "Local") ~= true then
			pcall(function()
				local player = rawget(character, "PlayerReference")
				local rigApi = rawget(character, "Rig")
				local rig = type(rigApi) == "table" and rigApi:GetRigModel() or nil
				if typeof(player) ~= "Instance" or not player:IsA("Player") or not rig or not rig.Parent then
					return
				end
				local anchor = rig:FindFirstChild("Head") or rig.PrimaryPart
				if not anchor then
					return
				end
				local entry = playerEspEntry(character, rig, player)
				entry.name.Adornee = anchor
				local reg = rawget(character, "DataRegistry")
				local down = type(reg) == "table" and type(reg.Get) == "function" and reg:Get("Downed") == true
				entry.hl.OutlineColor = down and Color3.fromRGB(255, 176, 76) or Color3.fromRGB(94, 196, 255)
				entry.hl.Enabled = true
				entry.name.Enabled = true
				seen[character] = true
			end)
		end
	end
	for character, entry in pairs(S.esp) do
		if not seen[character] then
			if entry.hl then entry.hl:Destroy() end
			if entry.name then entry.name:Destroy() end
			S.esp[character] = nil
		end
	end
end

local function clearNextbotEsp()
	for model, hl in pairs(S.nextbotEsp) do
		hl:Destroy()
		S.nextbotEsp[model] = nil
	end
end

local function reconcileNextbotEsp()
	if not CFG.nextbotEsp or not gui.visuals then
		clearNextbotEsp()
		return
	end
	local bodies = workspace:FindFirstChild("Players")
	if not bodies then
		clearNextbotEsp()
		return
	end

	local seen = {}
	for _, model in ipairs(bodies:GetChildren()) do
		if model:GetAttribute("AI") == true then
			local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				local box = S.nextbotEsp[model]
				if not box or box.Adornee ~= root then
					if box then box:Destroy() end
					box = Instance.new("BoxHandleAdornment")
					box.Name = "EKNextbotBox"
					box.AlwaysOnTop = true
					box.ZIndex = 10
					box.Color3 = Color3.fromRGB(255, 48, 48)
					box.Transparency = 0.55
					box.Size = Vector3.new(6, 8, 3)
					box.Adornee = root
					box.Parent = gui.visuals
					S.nextbotEsp[model] = box
				end
				box.Visible = true
				seen[model] = true
			end
		end
	end
	for model, hl in pairs(S.nextbotEsp) do
		if not seen[model] then
			hl:Destroy()
			S.nextbotEsp[model] = nil
		end
	end
end

local function toggleRow(parent, order, label, key, note)
	local row = mk("Frame", {
		BackgroundColor3 = COL.panel,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -16, 0, note and 40 or 30),
		LayoutOrder = order,
	}, parent)
	mk("UICorner", { CornerRadius = UDim.new(0, 4) }, row)

	mk("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, 0),
		Size = UDim2.new(1, -80, 0, 30),
		Font = Enum.Font.Gotham,
		Text = label,
		TextColor3 = COL.text,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, row)

	if note then
		mk("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(10, 24),
			Size = UDim2.new(1, -20, 0, 14),
			Font = Enum.Font.Gotham,
			Text = note,
			TextColor3 = COL.warn,
			TextSize = 10,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, row)
	end

	local btn = mk("TextButton", {
		BackgroundColor3 = CFG[key] and COL.on or COL.off,
		BorderSizePixel = 0,
		Position = UDim2.new(1, -62, 0, 5),
		Size = UDim2.fromOffset(52, 20),
		Font = Enum.Font.GothamBold,
		Text = CFG[key] and "ON" or "OFF",
		TextColor3 = COL.bg,
		TextSize = 11,
		AutoButtonColor = false,
	}, row)
	mk("UICorner", { CornerRadius = UDim.new(0, 4) }, btn)

	gui.conns[#gui.conns + 1] = btn.Activated:Connect(function()
		CFG[key] = not CFG[key]
		btn.BackgroundColor3 = CFG[key] and COL.on or COL.off
		btn.Text = CFG[key] and "ON" or "OFF"
		log("INFO", "toggle", { key = key, value = CFG[key] })
		if key == "speed" and not CFG.speed then
			clearSpeed()
		end
		if key == "bhop" and not CFG.bhop then
			clearBhop()
		end
		markDirty()
	end)

	return row
end

local function buildGui()
	local screen = mk("ScreenGui", {
		Name = "EK_" .. tostring(math.random(1000, 9999)),
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Global,
		DisplayOrder = 2147483647,
		IgnoreGuiInset = true,
	})
	-- OnTopOfCoreBlur keeps this layer above the Escape-menu compositor.
	-- Never use Modal=true here: it captures mouse and breaks shift-lock.
	pcall(sethiddenproperty, screen, "OnTopOfCoreBlur", true)
	screen.Parent = coreGuiHost()
	gui.ownScreen = screen
	gui.visuals = mk("Folder", { Name = "EKVisuals" }, screen)

	local frame = mk("Frame", {
		Name = "EKPanel",
		BackgroundColor3 = COL.bg,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(CFG.panelX, CFG.panelY),
		Size = UDim2.fromOffset(268, 312),
		Active = true,
		Draggable = true,
		Visible = not CFG.panelHidden,
	}, screen)
	mk("UICorner", { CornerRadius = UDim.new(0, 5) }, frame)
	mk("UIStroke", { Color = COL.stroke, Thickness = 1.5, Transparency = 0.2 }, frame)
	gui.frame = frame
	if HOST then
		frame.Position = UDim2.new()
		frame.Visible = true
		frame.Draggable = false
		frame.Parent = HOST.host
		-- Our own teardown destroys screen; ride that signal so a reparented panel
		-- can never outlive the module inside the hub.
		screen.Destroying:Connect(function() pcall(function() frame:Destroy() end) end)
	end

	-- Draggable has no drag-end event, so track Position and let the 1 Hz
	-- flush debounce the writes instead of saving on every drag frame.
	gui.conns[#gui.conns + 1] = frame:GetPropertyChangedSignal("Position"):Connect(function()
		local p = frame.Position
		if p.X.Offset ~= CFG.panelX or p.Y.Offset ~= CFG.panelY then
			CFG.panelX, CFG.panelY = p.X.Offset, p.Y.Offset
			markDirty()
		end
	end)

	local header = mk("Frame", {
		BackgroundColor3 = COL.panel,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 40),
	}, frame)
	mk("UICorner", { CornerRadius = UDim.new(0, 5) }, header)
	mk("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, 4),
		Size = UDim2.new(1, -24, 0, 18),
		Font = Enum.Font.GothamBold,
		Text = "EVADE KIT",
		TextColor3 = COL.text,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, header)
	local sub = mk("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, 21),
		Size = UDim2.new(1, -24, 0, 14),
		Font = Enum.Font.Gotham,
		Text = BUILD_VERSION .. "  ·  RShift hide  ·  RCtrl unload",
		TextColor3 = COL.dim,
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, header)

	-- Restored state is never allowed to be a surprise (see persistence note).
	if #restored > 0 then
		sub.Text = "RESTORED ON: " .. table.concat(restored, ", ")
		sub.TextColor3 = COL.warn
		task.delay(8, function()
			if sub and sub.Parent then
				sub.Text = BUILD_VERSION .. "  ·  RShift hide  ·  RCtrl unload"
				sub.TextColor3 = COL.dim
			end
		end)
	end

	-- live status block
	local status = mk("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 44),
		Size = UDim2.new(1, 0, 0, 66),
	}, frame)

	gui.rows.timer = mk("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.new(1, -24, 0, 26),
		Font = Enum.Font.GothamBold,
		Text = "--:--",
		TextColor3 = COL.text,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, status)

	gui.rows.phase = mk("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, 24),
		Size = UDim2.new(1, -24, 0, 14),
		Font = Enum.Font.Gotham,
		Text = "--",
		TextColor3 = COL.dim,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, status)

	gui.rows.bot = mk("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, 40),
		Size = UDim2.new(1, -24, 0, 13),
		Font = Enum.Font.Gotham,
		Text = "nextbot: --",
		TextColor3 = COL.dim,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, status)

	gui.rows.downed = mk("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, 53),
		Size = UDim2.new(1, -24, 0, 13),
		Font = Enum.Font.Gotham,
		Text = "downed: none",
		TextColor3 = COL.dim,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, status)

	local list = mk("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(8, 116),
		Size = UDim2.new(1, -16, 0, 188),
	}, frame)
	mk("UIListLayout", {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, list)

	toggleRow(list, 1, "Auto Bhop (hold Space)", "bhop")
	toggleRow(list, 2, "Auto Revive (teammates)", "autoRevive")
	toggleRow(list, 3, "Player ESP (names + outline)", "playerEsp")
	toggleRow(list, 4, "Nextbot ESP (red outline)", "nextbotEsp")

	local speedRow = toggleRow(list, 5, "Speed", "speed", "self-reported to server - capped 1.25")

	-- stepper for the multiplier; clamped to CFG.speedMax on every press
	local mult = mk("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(1, -138, 0, 5),
		Size = UDim2.fromOffset(40, 20),
		Font = Enum.Font.GothamBold,
		Text = string.format("%.2fx", CFG.speedMult),
		TextColor3 = COL.text,
		TextSize = 11,
	}, speedRow)

	local function stepBtn(xOff, label, delta)
		local b = mk("TextButton", {
			BackgroundColor3 = COL.off,
			BorderSizePixel = 0,
			Position = UDim2.new(1, xOff, 0, 5),
			Size = UDim2.fromOffset(18, 20),
			Font = Enum.Font.GothamBold,
			Text = label,
			TextColor3 = COL.text,
			TextSize = 12,
			AutoButtonColor = false,
		}, speedRow)
		mk("UICorner", { CornerRadius = UDim.new(0, 4) }, b)
		gui.conns[#gui.conns + 1] = b.Activated:Connect(function()
			CFG.speedMult = math.clamp(
				math.floor((CFG.speedMult + delta) * 100 + 0.5) / 100,
				1,
				CFG.speedMax
			)
			mult.Text = string.format("%.2fx", CFG.speedMult)
			log("INFO", "speed_mult", { mult = CFG.speedMult })
			markDirty()
		end)
	end

	stepBtn(-160, "-", -0.05)
	stepBtn(-96, "+", 0.05)

	log("INFO", "gui_built", {})
end

------------------------------------------------------------------------
-- main loop
------------------------------------------------------------------------

local running = true
local lastHud = 0
local lastEsp = 0
local lastReconcile = 0
local lastAlive = 0

-- ch/root may be nil (dead, downed, spectating, between rounds). The round
-- timer needs neither, so it keeps running; the rest degrades to a dash.
local function hudUpdate(ch, root)
	if not gui.rows.timer then
		return
	end

	local mmss, label = roundText()
	gui.rows.timer.Text = mmss
	gui.rows.phase.Text = label

	if not ch or not root then
		gui.rows.bot.Text = "nextbot: --"
		gui.rows.bot.TextColor3 = COL.dim
		gui.rows.downed.Text = "no character (dead / spectating)"
		gui.rows.downed.TextColor3 = COL.dim
		return
	end

	local name, dist = nearestNextbot(root)
	if name then
		gui.rows.bot.Text = string.format("nextbot: %s  %.0f studs", name, dist)
		gui.rows.bot.TextColor3 = dist < 25 and COL.warn or COL.dim
	else
		gui.rows.bot.Text = "nextbot: none"
		gui.rows.bot.TextColor3 = COL.dim
	end

	local downed = downedTeammates(ch, root)
	gui.rows.downed.TextColor3 = COL.dim
	if #downed == 0 then
		gui.rows.downed.Text = "downed: none"
	else
		local first = downed[1]
		gui.rows.downed.Text = string.format("downed: %d  nearest %s %.0f", #downed, first.name, first.dist)
	end
end

local heartbeat = RunService.Heartbeat:Connect(function()
	if not running then
		return
	end
	local now = os.clock()

	-- debounced settings flush: at most one write per second. Runs before the
	-- no-character bail so toggling in the menu or between rounds still saves.
	if saveDirty and now - lastSaveAt >= 1 then
		saveCfg()
	end

	local ch = getLocalChar()

	-- The HUD must NOT sit behind a no-character bail. You have no local
	-- character while dead, downed into a torn-down rig, spectating, or
	-- between rounds -- which is exactly when you most want the round timer,
	-- and exactly when a frozen panel reads as "the script crashed".
	-- hudUpdate handles ch == nil; only the per-character work below bails.
	if CFG.hud and now - lastHud >= 0.1 then
		lastHud = now
		pcall(function()
			hudUpdate(ch, ch and localRoot(ch) or nil)
		end)
	end
	if now - lastEsp >= 0.1 then
		lastEsp = now
		local espOk, espErr = pcall(reconcilePlayerEsp, ch)
		if not espOk then
			local err = tostring(espErr)
			if err ~= S.espError then
				S.espError = err
				log("ERROR", "esp_reconcile_failed", { error = err })
			end
		else
			S.espError = nil
		end
		local botOk, botErr = pcall(reconcileNextbotEsp)
		if not botOk then
			local err = tostring(botErr)
			if err ~= S.nextbotEspError then
				S.nextbotEspError = err
				log("ERROR", "nextbot_esp_reconcile_failed", { error = err })
			end
		else
			S.nextbotEspError = nil
		end
	end

	-- 60 s liveness line, so "is it still running" is answerable from the log
	-- instead of inferred from the absence of event lines.
	if now - lastAlive >= 60 then
		lastAlive = now
		log("INFO", "alive", {
			char = ch and "yes" or "no",
			bhop = CFG.bhop,
			revive = CFG.autoRevive,
			esp = CFG.playerEsp,
			nextbotEsp = CFG.nextbotEsp,
			speed = CFG.speed and CFG.speedMult or "off",
			jumps = S.stats.jumpsArmed,
			revives = S.stats.revives,
		})
	end

	if not ch then
		return
	end

	-- reconcile at 20 Hz: respawns build a fresh Movement/MoveStats, so
	-- both the bhop field and the SpeedChange slot have to be re-applied
	if now - lastReconcile >= 0.05 then
		lastReconcile = now
		pcall(applyBhop, ch)
		pcall(applySpeed, ch)
		local reviveOk, reviveErr = pcall(tickRevive, ch, now)
		if not reviveOk then
			reviveArmAt = nil
			local err = tostring(reviveErr)
			if err ~= S.reviveError then
				S.reviveError = err
				log("ERROR", "revive_tick_failed", { error = err })
			end
		else
			S.reviveError = nil
		end
	end
end)

-- Heartbeat's 10 Hz visual reconcile allowed the camera to expose the torso
-- for one rendered frame during jump bob. Pin after Roblox's camera step so
-- every frame is hidden before it reaches the screen. This must be per-frame;
-- a slower state loop cannot prevent a one-frame flash.
RunService:BindToRenderStep(FIRST_PERSON_BIND, Enum.RenderPriority.Camera.Value + 1, function()
	if not running then
		return
	end
	local ok, errValue = pcall(reconcileFirstPersonBody, getLocalChar())
	if not ok then
		restoreFirstPersonBody()
		local err = tostring(errValue)
		if err ~= S.firstPersonError then
			S.firstPersonError = err
			log("ERROR", "first_person_hide_failed", { error = err })
		end
	else
		S.firstPersonError = nil
	end
end)

------------------------------------------------------------------------
-- input
------------------------------------------------------------------------

local inputBegan = UserInputService.InputBegan:Connect(function(input, gp)
	if gp then
		return
	end
	if input.KeyCode == Enum.KeyCode.Space then
		spaceHeld = true
	end
end)

local inputEnded = UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.Space then
		spaceHeld = false
		clearBhop()
	end
end)

------------------------------------------------------------------------
-- teardown -- restores everything this script touched (posture 5)
------------------------------------------------------------------------

local function destroy()
	if not running then
		return
	end
	running = false
	log("INFO", "destroy_begin", { build = BUILD_VERSION })

	-- Persist BEFORE the teardown below zeroes the toggles, or unloading
	-- would silently save everything as OFF and lose the user's setup.
	saveCfg()

	CFG.bhop = false
	CFG.speed = false
	CFG.autoRevive = false
	CFG.playerEsp = false
	CFG.nextbotEsp = false

	pcall(clearBhop)
	pcall(clearSpeed)
	pcall(clearPlayerEsp)
	pcall(clearNextbotEsp)
	pcall(restoreFirstPersonBody)

	pcall(function()
		if heartbeat then
			heartbeat:Disconnect()
		end
	end)
	pcall(function()
		RunService:UnbindFromRenderStep(FIRST_PERSON_BIND)
	end)
	pcall(function()
		if inputBegan then
			inputBegan:Disconnect()
		end
	end)
	pcall(function()
		if inputEnded then
			inputEnded:Disconnect()
		end
	end)
	pcall(function()
		if stateConn then
			stateConn:Disconnect()
		end
	end)
	for _, c in ipairs(gui.conns) do
		pcall(function()
			c:Disconnect()
		end)
	end
	pcall(function()
		if gui.ownScreen then
			gui.ownScreen:Destroy()
		elseif gui.frame then
			gui.frame:Destroy()
		end
		if gui.visuals and gui.visuals.Parent then
			gui.visuals:Destroy()
		end
	end)
	pcall(function()
		ContextActionService:UnbindAction("EK_Hide")
		ContextActionService:UnbindAction("EK_Unload")
	end)

	G[GKEY] = nil
	log("INFO", "destroy_end", {
		revives = S.stats.revives,
		jumpsArmed = S.stats.jumpsArmed,
	})
end

S.destroy = destroy
S.cfg = CFG
S.build = BUILD_VERSION
G[GKEY] = S

------------------------------------------------------------------------
-- boot
------------------------------------------------------------------------

bindStateRegistry()
buildGui()

-- high-priority CAS so a game BindAction cannot eat the hotkeys first
ContextActionService:BindActionAtPriority("EK_Hide", function(_, state)
	if state == Enum.UserInputState.Begin and gui.frame and not HOST then
		gui.frame.Visible = not gui.frame.Visible
		CFG.panelHidden = not gui.frame.Visible
		markDirty()
	end
	return Enum.ContextActionResult.Sink
end, false, 4000, Enum.KeyCode.RightShift)

ContextActionService:BindActionAtPriority("EK_Unload", function(_, state)
	if state == Enum.UserInputState.Begin then
		destroy()
	end
	return Enum.ContextActionResult.Sink
end, false, 4000, Enum.KeyCode.RightControl)

log("INFO", "ready", {
	build = BUILD_VERSION,
	bhop = CFG.bhop,
	revive = CFG.autoRevive,
	esp = CFG.playerEsp,
	nextbotEsp = CFG.nextbotEsp,
	speed = CFG.speed,
})
