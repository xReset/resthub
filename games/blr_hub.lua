-- Blue Lock Rivals Hub v2026-09-01.25 (2026-09-01)
-- PlaceId 18668065416. Dump 2026-08-28T07-29-39Z.
-- Client limiters, all module-level locals in ReplicatedStorage.Controllers:
--   BallController (0870) Slide gate `u10 > tick()` :443, set :461-467;
--     Dribble gate `u11 > tick()` :574, set :645. Both are shared upvalues.
--   AbilityController.interface (0818) AbilityOne/Two/Three/AbilityUsed tick
--     deadlines, read as `> tick()` by every ability module (0376:89, 0378:30,
--     0384:26, 0404:19, 0417:27...). Default -1, so pinning 0 is open.
--   AbilityController.LegacyFunctions.AbilityCooldown (0815:89) writes those
--     deadlines; its `seconds` arg is what we shrink.
--   StatesController (1138) ShotPowerMultiplier, reset to 1 each Heartbeat
--     (:129 -> :244), read at the shot at 0870:1284.
--   Stamina gates read LocalPlayer.PlayerStats.Stamina (NumberValue) <= 10
--     (0870:447, 0870:578); drain is StaminaService.DecreaseStamina:Fire(10).
-- Posture: rung 3/4 (local module state, suppressed local remote fire). Nothing
-- new is sent. The server DOES see a higher Dribble/Slide/Ability call rate when
-- those toggles are ON, so they boot OFF per potassium-dev 0.2b.
-- Dump has no anticheat_deep.txt; grepped this dump's 3094 client scripts for
-- GetLogHistory / MessageOut / getgenv / hookfunction / checkcaller: zero hits.
-- Every :Kick( is Cmdr admin (0312, 0341, 0366, 2216). Server bans stay invisible.
-- Note 0870:587 `print("Dribbled at", tick())` - the GAME prints per dribble, so
-- spamming NoDribbleCD floods the client console. No game code reads it back.
-- Re-inject safe; K unload; P panic; RShift panel.
-- Settings persist to blr_hub_config.json and EVERY toggle resumes as saved (.9,
-- user instruction). The ones that fire a real remote -- NoDribbleCD, NoSlideCD,
-- NoAbilityCD, CFLocker -- are named in the boot log on the "ARMED" line so an
-- armed feature is never a surprise. P panic clears them all.
-- Changelog:
--  .25  CF Locker now treats Select:Fire as pending and stops only after the
--       CF ObjectValue confirms LocalPlayer. Previously `claimSeat` returned
--       true on send, so one refused/contested packet ended all retries while
--       the log misleadingly showed only `fired Select Home CF`.
--  .24  Per-style tuning profiles, and every power slider now reaches x2.00.
--       `getCurrentStyle` (0111) is one cached read of
--       LocalPlayer.PlayerStats.Style.Value, updated from Style.Changed and
--       defaulting to "Isagi". That is the same value the game's own code keys
--       on for the dribble animation (0870:591), the slide distance (0870:487)
--       and the ball trail (0870:1383), so it is the honest key for tuning that
--       is meant to follow the character, and Style.Changed is the honest
--       signal for "the user picked a style". Style is a child of the PLAYER,
--       not the character, so one connection covers respawns and the whole
--       session.
--       Saved per style: ShotPowerMult, HeaderPowerMult, HeaderArcTrim,
--       AbilityPowerMult, AbilityArcTrim. Toggles are NOT: which features are
--       armed is a safety decision (potassium-dev 0.2b), and having a style
--       change arm something would defeat the ARMED boot line.
--       A style seen for the first time adopts the numbers currently on screen
--       instead of snapping to defaults -- the user has just been tuning, and
--       discarding that is the worse surprise. Capture happens inside
--       saveConfig, so every path that already saved now profiles too and no
--       slider needed changing. Ability power is re-applied on the swap because
--       it mutates AbilityBalancing once rather than being read per frame.
--       Slider ceilings: Shot power 1.6 -> 2.00, Header speed 1.4 -> 2.00,
--       Ability power 1.6 -> 2.00. The tradeoff lines are unchanged and still
--       true -- past roughly x1.3 the ball outruns every keeper and reads as
--       fake, and the header ceiling was 1.4 because the loft rides the same
--       product. The ceiling is now the user's call, not the script's, but the
--       warning stays on screen. Touch power (50-90) is deliberately NOT
--       doubled: it is a raw charge value on the game's own 50-110 scale
--       (0870:171), not a multiplier, and 180 is not a number the charge can
--       hold.
--  .23  Diagnostics for the .20 claim test, which came back inconclusive -- NOT
--       negative. The .22 log shows the claim write landing exactly once
--       (`0.25s instead of the game's 3.00s`) and ZERO echo lines, which proves
--       nothing either way, because .20's own filter (`character ~= LP.Character
--       -> return`) discarded every broadcast silently. A test that cannot
--       distinguish "the server sent nothing" from "my filter ate it" is not a
--       test. Every UpdateDribbleCooldown is now logged with who it was for and
--       what type that `who` is, so a Player-instead-of-character argument or a
--       stale LP.Character shows up instead of hiding.
--       Second, unrelated and more serious: the same log shows
--       `Dribble call #2: cleared 0 future deadline(s)` less than a second after
--       call #1, and call #1 ran 0870:645 `u11 = tick() + v73`. A future number
--       must have been in that closure and the scan did not see it. The .12
--       read-back warning cannot catch this -- it only runs inside the
--       `val > now` branch that never executed. So a one-shot upvalue census
--       now dumps what the scan actually reads on the second call. If that
--       census shows no future number, NoDribbleCD has never done anything and
--       the claim test was riding on a bypass that was not running.
--       Diagnostics only: no gate, no argument and no game state changed.
--  .20  Dribble CD claim. 0870:647 fires BallService.Dribble:Fire(jobId, v73)
--       where v73 is the cooldown the CLIENT just computed for itself
--       (0870:614-644). The server has a matching broadcast,
--       BallService.UpdateDribbleCooldown(character, seconds) (0430:58-64),
--       which carries a duration back out to every client -- including the
--       firer's own character, since 0430:59 has to explicitly skip itself.
--       If that echoed number is the one we sent, the server is storing the
--       client's own claim as its dribble cooldown and shrinking the argument
--       shortens the SERVER's gate, not just ours -- which is the only thing
--       that makes a dribble actually register (VFX, Values.Dribbling, evade).
--       This build sends the smaller number AND logs both halves of that
--       comparison, so the question is answered from the log instead of by
--       reasoning: `claim` lines say what we sent, `echo` lines say what came
--       back. Unproven until those two lines agree in a real match -- the
--       toggle exists to run the test, and the header does not claim it works.
--       Clamped to 0.25s at the low end: BallController's own shortest real
--       cooldown is 1.0 (0870:637-643 divides 3 by up to 1.25 and 1.15, and
--       Bachira-in-awakening starts at 2), so 0.25 is already below anything
--       the game itself can produce and going lower buys nothing but a number
--       no legitimate client would ever send.
--       Nothing else changed: the local gate clear (NoDribbleCD) is a separate
--       toggle and is untouched, and the argument is only rewritten when it is
--       already a number and our claim is SMALLER than the game's own.
--   .1  no dribble CD, no slide/steal CD, no ability CD, shot power, client stamina pin
--   .2  upvalue scan no longer clobbers the u4/u5 dribble+slide charge counters
--       and no longer truncates on a nil upvalue (getupvalue is value-only);
--       ability cooldown 0 -> 0.05 to avoid 0/0 in the 0815:110 UIGradient;
--       ShotPower moved off BindToRenderStep onto a late Heartbeat so the
--       game's own reset cannot land after it; panel no longer nests a
--       ScreenGui inside gethui(); stamina Fire restore honours own-vs-inherited
--   .3  unload no longer saves all-OFF over the user's config (panic(persist));
--       panel position clamped to the viewport on load, on drag-end and on
--       RShift-show, so it can never be stranded off-screen; ShotPower /
--       AbilityPower / InfiniteStamina now resume as saved per 0.2b and the
--       boot log names them; AbilityPower narrowed to ShotPower/ShotPowerMax
--       only -- the blanket Cooldown and ActivationRange* rewrites were
--       unproven guesses and are the prime suspect for abilities dying
--   .4  R3ST Hub shell, CoreGui host, PlaceId fail-closed, ‹ HUB return to hub.lua
--   .6  honours hub.lua's __R3ST_HOST contract: when the hub mounts us we render
--       into its content host and create no ScreenGui, border, drag or RightShift
--       handler of our own. Standalone injection is unchanged. Backend untouched.
--   .7  NoAbilityCD no longer freezes the character (Kaiser Volley). The slot
--       deadlines are no longer pinned while StatesController.States.Ability is
--       true, so an ability module cannot be re-entered mid-cast and orphan its
--       own "start" handler, which is what left WalkSpeed pinned to 0 at
--       1138:281. A 6s watchdog clears an already-orphaned States.Ability.
--   .8  closes the same freeze in the other five modules that clear States.Ability
--       only from a server reply -- HeelCenter (0399), EasterTikiTaka (0465),
--       TikiTaka (0597) and both TrueDirectShot copies (0528/0638). The slot that
--       was cast is now held shut for 2.5s, which also covers TrueDirectShot's
--       1.5s take-phase where the flag is still false and the .7 guard did not
--       apply. Only the cast slot is held; the other two stay instant.
--  .18  Header power. A jump/freefall touch is its own branch of the game's own
--       shoot handler (0870:1303-1327): velocity is
--       (LookVector + Vector3(0, arc, 0)) * power * StatesController.ShotPowerMultiplier,
--       arc defaulting to 0.3 (0870:1263) and an extra x1.2/x1.4 already applied
--       for Demon Wings flow. So headers ALWAYS rode the Shot power multiplier --
--       nothing new is needed to make one faster. What was missing is a separate
--       knob: the header shares one multiplier with every ground shot, so
--       "1.2x headers only" was not expressible. HeaderPower raises the
--       multiplier for exactly the frames the humanoid is Jumping or Freefall,
--       which is the same condition the header branch tests. Ability headers
--       (DragonHeader 175, DemonHeader 170, CrushingHeader 145,
--       UnstoppableDemonHeader 220 -- 0061:26,618,1220,239) are AbilityBalancing
--       rows and were already covered by Ability shot power.
--       Note the arc: the loft term sits INSIDE the same product, so a header at
--       x1.2 flies 20% faster and 20% higher. Fixed in .21.
--  .21  Header power, reshaped instead of scaled. .18 was the wrong lever: the
--       loft sits inside the game's own product, so raising ShotPowerMultiplier
--       bought speed and floatiness together and the header hung in the air
--       longer, not less. We do not own that vector -- but we DO own the ball the
--       instant after the game writes it, from the same client, same property.
--       So HeaderPower now reshapes the finished velocity on the airborne branch
--       only: horizontal * HeaderPowerMult, vertical * HeaderArcTrim. A lower
--       apex is a shorter fall, so the ball is faster to the net AND comes down
--       sooner -- the same arc shape, compressed. The write is deferred one
--       resumption so it never depends on which handler the Knit signal calls
--       first, and it is gated on Before.Value being our own character
--       (0870:1270) so another player's shot is never touched.
--  .19  THE actual reason Loki's V and C did nothing, from the client log:
--         blr_hub.lua: attempt to call a nil value
--         <- AbilityController AbilityCooldown
--         <- Loki VelocityDash:92 / ExplosiveAcceleration:39
--       Our AbilityCooldown wrapper called `S.origAbilityCooldown` at call time
--       instead of a local upvalue. Unload nils that field, and the old
--       restore only recognised its own wrapper by scanning upvalues -- which
--       could never match, because the original was a table FIELD. So the stale
--       wrapper stayed installed, forwarded to nil, and every ability routed
--       through AbilityCooldown threw. Re-injecting made it worse: the new hook
--       wrapped the broken wrapper. Now every wrapper closes over a local orig,
--       the true original is stashed on the game's own table under a __blr_orig_
--       key so a fresh inject REBUILDS from it and heals a stale chain without a
--       rejoin, restore is by closure identity, and S.orig* is never cleared.
--       Same treatment applied to the Dribble / Slide / Shoot wrappers.
--  .17  Loki's V, broken by .12, restored. .12 decided a cast the server had
--       "refused" from States.Ability still being true 1.5s after the cast, then
--       cleared that flag and parked the slot on the move's real cooldown.
--       VelocityShot (0614) holds States.Ability until its reply and self-cleans
--       at task.delay(2, ...) -- so a healthy Loki V was declared refused at
--       1.5s, had its state yanked mid-cast and lost slot 2 for 35s. Inference
--       removed: resolveCast now only releases OUR hold, never writes game state
--       and never takes a slot away, and the stuck-ability watchdog went from 2s
--       back to 5s, past every legitimate cast window in the dump. The .12 fix
--       that mattered -- AbilityUsed is never held on another slot's behalf --
--       is unchanged, so Yukimiya stays fixed.
--  .16  The real cause of "my dribble became a rocket": 0870:341. A charge that
--       STARTS while HasBall is false and then sees the ball arrive is forced to
--       u3 = 110 -- maximum power -- and fired immediately as a Volley
--       (0870:244). No hold, no release, so no tap guard could ever catch it.
--       HasBall drops for a few frames on every dribble touch, so a spam-click
--       through that gap volleys your own dribble downfield. VolleyGuard wraps
--       BallController.Shoot and refuses to start a charge when we held the ball
--       within the last VolleyGapMs. Real volleys are untouched.
--  .15  Tap guard, event-driven. .14 polled the physical mouse button once per
--       Heartbeat and skipped whenever it was down -- but while you spam-click
--       the button is down for most samples, because the next click has already
--       begun. The release was never seen and the charge still reached the
--       0870:365 auto-fire. Now we take UserInputService.InputEnded ourselves and
--       ignore its gameProcessed flag, which is the exact filter that makes the
--       game miss these (0870:1004). Polling stays as a backstop. Both the guard
--       releases and any failed charge write are logged.
--  .14  Tap guard for the "my dribble turned into a shot" bug. Left click is a
--       CHARGE (0870:171): u3 runs 50 -> 110, and two things fire it without you
--       asking -- u6 >= 50 auto-fires at ~1.11s of holding (0870:365), and the
--       release handler bails on gameProcessedEvent (0870:1004), so a mouse-up
--       over any GUI (this panel included) never clears HoldingShoot and the
--       charge keeps climbing into that auto-fire. The guard watches the PHYSICAL
--       button, hands the release back to the game's own path, and writes the
--       charge down to a touch value if the click was shorter than the tap
--       window. Longer holds are untouched, so charged shots still charge.
--  .13  VIP / private servers. Identity now matches the UNIVERSE first
--       (game.GameId 6325068386) and the PlaceId second, because a private
--       server of the same experience can report a different PlaceId and the
--       old gate refused to arm there. Same rule went into hub.lua and into the
--       hub skill, for every module.
--  .12  NoAbilityCD, properly. Three separate bugs, all of them mine:
--       (a) the cast hold was also applied to iface.AbilityUsed, and AbilityUsed
--           is the SHARED gate every slot reads (0379:31, 0378:34, 0607:33), so
--           casting slot 1 silently shut all three for the whole hold. It is now
--           only left alone mid-cast and never held for another slot.
--       (b) the hold ran a flat 2.5s even after the cast had resolved. It now
--           ends as soon as the cast completes, floor 1.5s (TrueDirectShot's
--           take-phase, 0528:125).
--       (c) a cast the server REFUSES never replies, so States.Ability stayed
--           true and you stood frozen until a 6s watchdog. Refusal is now
--           detected at 1.5s, and that one slot goes back on its real cooldown
--           instead of us re-offering a cast the server will refuse again.
--       Dribble/Slide gained a read-back check on debug.setupvalue and a
--       first-three-calls log line, so "the toggle is ON" and "the bypass
--       actually ran" stop being the same claim.
--  .11  Fluid layout. .10 scaled one 684-wide page into the hub's ~950-wide
--       content host, so a third of the tab sat empty and the longer captions
--       clipped. Rows are now sized in scale, cards re-flow on every width
--       change, and the grid goes to THREE columns past 1000px. Nothing about
--       the backend, the cooldown hooks or the CF locker changed in .11.
--  .10  The whole panel is now the shared R3ST control template
--       (scripts/r3st_ui.lua): header with the game icon, a tab strip, two
--       columns of cards, pill toggles, track sliders and the Unload / UI
--       Settings footer. Same backend, same toggles, one look across the hub.
--       Embedded, the kit arrives on __R3ST_HOST.ui so the hub and the module
--       can never run two versions of the widgets.
--       "Auto lock Blue CF" is renamed "CF Locker". The Home (blue) path from .9
--       is UNCHANGED -- same state gate, same settle, same retry cadence, same
--       remote -- because it works. All that is added is a fallback: once Home CF
--       is proven taken by someone else, Away (white) CF is claimed on the next
--       poll instead of giving up. The game's own 3s wait (1145:212, local `u2`)
--       is client-side inside its own GUI handler and our direct
--       TeamService.Select:Fire never passes through it, so the fallback is
--       immediate. Blue is always tried first, every attempt.
--       Shot tuning gained the arc knob the power multiplier was missing:
--       ability velocity is (LookVector + ShotTiltVector) * ShotPower (0547:210,
--       0375:74), so scaling ShotPower alone scales the LOFT with it and the ball
--       hangs. ArcTrim scales ShotTiltVector.Y back down, turning the extra power
--       into range on a flatter, normal-looking trajectory.
--   .9  Auto lock Blue CF: claims ReplicatedStorage.Teams.HomeTeam.CF via
--       TeamService.Select:Fire("Home", "CF") the moment GameValues.State turns
--       Intermission, in or out of the match. Fires only in that state -- see the
--       block above tryLockCF for why Ending is the state that bugs the character.
--       Also, on the user's explicit instruction, EVERY toggle now autosaves and
--       resumes; the remote-firing ones are named in the boot log instead of
--       being forced OFF (deliberate override of potassium-dev 0.2b).

local BUILD_VERSION = "2026-09-01.25"
local EXPECTED_PLACE = 18668065416
-- Universe id. A VIP / private server is the SAME experience but the client can
-- land on a different PlaceId inside it, so a PlaceId-only gate fails closed in
-- exactly the servers the user plays in most. GameId is stable across every
-- place and every private server of one experience -- match on it FIRST.
local EXPECTED_GAME = 6325068386
local GKEY = "__BLR_HUB"
local CONFIG_FILE = "blr_hub_config.json"
local LOG_FILE = "logs/blr_hub.log"

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")

local LP = Players.LocalPlayer
local G = (getgenv and getgenv()) or _G
if type(G) ~= "table" then
	G = _G
end
if type(G[GKEY]) == "table" and type(G[GKEY].destroy) == "function" then
	pcall(G[GKEY].destroy)
end

local logLines = {}
local function log(message)
	logLines[#logLines + 1] = os.date("[%H:%M:%S] ") .. tostring(message)
	if #logLines > 160 then
		table.remove(logLines, 1)
	end
	pcall(writefile, LOG_FILE, table.concat(logLines, "\n") .. "\n")
end

-- Every toggle now resumes as saved, on the user's explicit instruction (.9).
-- potassium-dev 0.2b would boot the four below OFF because they raise the rate of
-- a real server call, so the standing rule is deliberately overridden here. The
-- tradeoff is named, not hidden: they are listed by name in the boot log every
-- inject, so an armed remote-firing feature is never a surprise.
local FIRES_REMOTE = {
	NoDribbleCD = "BallService.Dribble:Fire (0870:647)",
	DribbleCDClaim = "BallService.Dribble:Fire arg 2 rewritten (0870:647)",
	NoSlideCD = "BallService.Slide (0870:443-530)",
	NoAbilityCD = "ability remotes + replicateCooldowns (0815:106)",
	CFLocker = "TeamService.Select:Fire (1145:213)",
	-- ShotPower, AbilityPower and InfiniteStamina send nothing: they are local
	-- module fields and a suppressed local Fire.
}

local DEFAULTS = {
	NoDribbleCD = false,
	-- rung 6, UNPROVEN: rewrites the cooldown the client reports to the server in
	-- BallService.Dribble:Fire(jobId, seconds) (0870:647). Whether the server
	-- keeps that number is what the claim/echo log lines answer.
	DribbleCDClaim = false,
	DribbleCDClaimSeconds = 1.0,
	NoSlideCD = false,
	NoAbilityCD = false,
	ShotPower = false, -- rung 5: StatesController.ShotPowerMultiplier -> ball velocity
	ShotPowerMult = 1.20,
	-- rung 5: reshapes the ball velocity the game itself just wrote, and only on
	-- the airborne (header) branch of BallService.Shoot (0870:1303). Independent
	-- of ShotPower -- that one scales every shot, this one only headers.
	HeaderPower = false,
	HeaderPowerMult = 1.20,
	-- Scales the vertical component of the header AFTER the game's own write, so
	-- extra speed does not also become extra loft. Lower = flatter and it drops
	-- sooner, because a lower apex is a shorter fall.
	HeaderArcTrim = 0.70,
	InfiniteStamina = false, -- rung 3: suppresses DecreaseStamina, pins local Value
	-- rung 3: forces the game's OWN release path when the mouse is physically up,
	-- and softens a tap so it stays a dribble touch instead of a shot.
	TapGuard = false,
	TapWindowMs = 220,
	TapPower = 55,
	-- rung 3: refuses to START a charge during a dribble's own no-ball gap, which
	-- is the branch that forces u3 = 110 and volleys the ball away (0870:341).
	VolleyGuard = false,
	VolleyGapMs = 700,
	AbilityPower = false, -- rung 3: AbilityBalancing ShotPower (0375:81, 0388:60)
	AbilityPowerMult = 1.20,
	-- Multiplies AbilityBalancing.<move>.ShotTiltVector.Y. Power alone scales the
	-- loft too (velocity = (LookVector + Tilt) * Power), which is the floaty,
	-- obvious shot; trimming the arc turns the same extra power into range.
	AbilityArcTrim = 0.75,
	-- style name -> { ShotPowerMult = n, HeaderPowerMult = n, ... }. Every tuning
	-- NUMBER is per style, because a Loki arc is not a Kaiser arc. The on/off
	-- toggles stay global: which features are armed is a safety decision
	-- (potassium-dev 0.2b), not a tuning preference, and having it change under
	-- you because the match assigned a different style is exactly the surprise
	-- the ARMED boot line exists to prevent.
	Styles = {},
	CFLocker = false, -- rung 6: TeamService.Select:Fire("Home"/"Away", "CF")
	CFFallbackWhite = true, -- blue first, ALWAYS; white only once blue is taken
	Tab = "Controls",
	PanelX = 24,
	PanelY = 160,
	PanelVisible = true,
}

local CFG = {}
for k, v in pairs(DEFAULTS) do
	CFG[k] = v
end
-- A shallow copy would hand CFG the SAME table DEFAULTS holds, so the first
-- per-style write would edit the defaults too and every later "reset" would
-- return the edited values.
CFG.Styles = {}
do
	local ok, raw = pcall(readfile, CONFIG_FILE)
	if ok and type(raw) == "string" then
		local decoded, data = pcall(HttpService.JSONDecode, HttpService, raw)
		if decoded and type(data) == "table" then
			for k, default in pairs(DEFAULTS) do
				if type(data[k]) == type(default) then
					CFG[k] = data[k]
				end
			end
			-- .9 called it AutoLockCF. Carry a saved ON across the rename rather
			-- than silently disarming a feature the user left armed.
			if type(data.AutoLockCF) == "boolean" and type(data.CFLocker) ~= "boolean" then
				CFG.CFLocker = data.AutoLockCF
			end
		end
	end
end
local armedRemoteNames = {}
for k in pairs(FIRES_REMOTE) do
	if CFG[k] then
		armedRemoteNames[#armedRemoteNames + 1] = k
	end
end
table.sort(armedRemoteNames)

-- A panel saved hidden AND dragged off-screen is unrecoverable, because the only
-- way back is a keybind aimed at something the user cannot see. Clamp the stored
-- position into the current viewport before the panel is ever built.
local function clampPanel()
	local cam = workspace.CurrentCamera
	local vx, vy = 1280, 720
	if cam then
		local vp = cam.ViewportSize
		if vp.X > 0 and vp.Y > 0 then
			vx, vy = vp.X, vp.Y
		end
	end
	-- Keep at least the title bar reachable by the mouse.
	CFG.PanelX = math.clamp(tonumber(CFG.PanelX) or 24, 0, math.max(0, vx - 360))
	CFG.PanelY = math.clamp(tonumber(CFG.PanelY) or 160, 0, math.max(0, vy - 100))
end
clampPanel()

--======================================================================
-- Per-style tuning profiles (.24)
--
-- `getCurrentStyle` (0111) is a one-line module: it caches
-- LocalPlayer.PlayerStats.Style.Value, defaults to "Isagi", and updates from
-- Style.Changed. Every piece of game code that cares about your character reads
-- it -- the dribble animation picker (0870:591), the slide distance (0870:487),
-- the ball trail colour (0870:1383). So it is the honest key for tuning that is
-- supposed to follow the character, and Style.Changed is the honest signal for
-- "the user selected a style". The Player attribute EquippedStyle is the menu's
-- copy and is only a fallback for the frames before PlayerStats exists.
--
-- Numbers are per style; toggles are not. See DEFAULTS.Styles for why.
local PROFILE_KEYS = {
	"ShotPowerMult",
	"HeaderPowerMult",
	"HeaderArcTrim",
	"AbilityPowerMult",
	"AbilityArcTrim",
}

local function currentStyle()
	local stats = LP:FindFirstChild("PlayerStats")
	local style = stats and stats:FindFirstChild("Style")
	if style and type(style.Value) == "string" and style.Value ~= "" then
		return style.Value
	end
	local equipped = LP:GetAttribute("EquippedStyle")
	if type(equipped) == "string" and equipped ~= "" then
		return equipped
	end
	return "Isagi" -- 0111's own default
end

-- Forward declaration: saveConfig captures the live numbers into the active
-- style before writing, so every path that already saves is a path that already
-- profiles -- no slider needs to know profiles exist.
local captureProfile

local saveQueued = false
local function saveConfig()
	if saveQueued then
		return
	end
	saveQueued = true
	task.delay(0.5, function()
		saveQueued = false
		if captureProfile then
			captureProfile()
		end
		local ok, payload = pcall(HttpService.JSONEncode, HttpService, CFG)
		if ok then
			pcall(writefile, CONFIG_FILE, payload)
		end
	end)
end

local S = {
	alive = true,
	conns = {},
	screen = nil,
	ball = nil,
	iface = nil,
	legacyCD = nil,
	origAbilityCooldown = nil,
	cdWrapper = nil,   -- the exact closure we installed, for identity restore
	cdChainBroken = false, -- an older inject's wrapper threw; bypass it
	wrappers = {},     -- methodName -> the closure we installed on BallController
	origDribble = nil,
	origSlide = nil,
	origDribbleFire = nil,     -- BallService.Dribble.Fire before the .20 claim wrap
	dribbleFireOwn = nil,      -- was Fire an own field, or inherited from Knit's class
	dribbleFireWrapper = nil,  -- the exact closure we installed, for identity restore
	dribbleSignal = nil,
	claimCount = 0,            -- dribble CDs we rewrote, for the first-calls log
	echoCount = 0,             -- UpdateDribbleCooldown broadcasts seen, from anyone
	census = {},               -- methodName -> the one-shot upvalue census already ran
	lastClaim = nil,           -- the last seconds value we actually sent
	staminaHook = nil,
	balancingOrig = {},
	balancing = nil,
	states = nil,
	abilityTrueAt = nil,
	slotHold = {},
	holdStart = nil,  -- os.clock() when the current shoot-charge began
	guardCount = 0,   -- tap-guard releases logged (first six only)
	lastHadBall = nil,
	volleyBlocked = 0,
	origShoot = nil,  -- BallController.Shoot, whose upvalues carry the charge
	callCount = {},   -- Dribble/Slide invocation counter, for the first-calls log
	upvalWarned = false,
	pending = {},      -- field -> { at, name, real, sawActive } while a cast is in flight
	teamService = nil,
	stateConn = nil,
	lockRunning = false,
	style = nil,          -- the style whose profile the live CFG numbers belong to
	sliderRedraw = {},    -- key -> the kit's redraw for that slider, for a live refresh
}

-- Write the live numbers back into the style they belong to. Called from
-- saveConfig, so it runs on every slider commit without the sliders knowing.
captureProfile = function(style)
	style = style or S.style
	if type(style) ~= "string" or style == "" then
		return
	end
	if type(CFG.Styles) ~= "table" then
		CFG.Styles = {}
	end
	local profile = CFG.Styles[style]
	if type(profile) ~= "table" then
		profile = {}
		CFG.Styles[style] = profile
	end
	for _, key in ipairs(PROFILE_KEYS) do
		local v = tonumber(CFG[key])
		if v then
			profile[key] = v
		end
	end
end

-- Load a style's saved numbers into CFG. A style seen for the first time ADOPTS
-- the numbers currently on screen rather than snapping to defaults: the user has
-- just been tuning, and throwing that away on a style change is a worse surprise
-- than carrying it over as the new style's starting point.
local function applyProfile(style)
	if type(style) ~= "string" or style == "" then
		return false
	end
	local profile = type(CFG.Styles) == "table" and CFG.Styles[style] or nil
	if type(profile) ~= "table" then
		captureProfile(style)
		return false
	end
	local applied = 0
	for _, key in ipairs(PROFILE_KEYS) do
		local v = tonumber(profile[key])
		if v and v ~= CFG[key] then
			CFG[key] = v
			applied = applied + 1
		end
	end
	return true, applied
end

local function refreshSliders()
	for _, redraw in pairs(S.sliderRedraw) do
		pcall(redraw)
	end
end

-- Declared above hookAbilityCooldown because the hook writes S.slotHold through
-- them; a local defined further down would be a nil global inside the wrapper.
local CAST_GUARD_SECONDS = 1.5
local SLOT_FIELD = { ["1"] = "AbilityOne", ["2"] = "AbilityTwo", ["3"] = "AbilityThree" } -- 0815:28

local function connect(signal, fn)
	local c = signal:Connect(fn)
	S.conns[#S.conns + 1] = c
	return c
end

local function clearFutureTickUpvalues(fn)
	if type(fn) ~= "function" or type(debug) ~= "table" or type(debug.getupvalue) ~= "function" then
		return 0
	end
	local cleared = 0
	local now = tick()
	-- Potassium debug.getupvalue returns the VALUE only (API docs, one return).
	-- Out-of-range throws, which is the loop's terminator; a nil-valued upvalue
	-- in the middle must not truncate the scan.
	-- Only future tick() deadlines are touched: 0870:441 (u10, Slide) and
	-- 0870:575 (u11, Dribble). The dribble/slide CHARGE counters (u4/u5,
	-- 0870:40-41) are also numbers in range and must be left alone -- rewriting
	-- them corrupts the game's own charge accounting for no gain, because the
	-- post-call clear already re-opens the gate.
	for i = 1, 48 do
		local ok, val = pcall(debug.getupvalue, fn, i)
		if not ok then
			break
		end
		if type(val) == "number" and val > now then
			pcall(debug.setupvalue, fn, i, 0)
			-- Read it back. `setupvalue` failing silently would make this whole
			-- toggle a no-op that still logs as if it worked, and "is the write
			-- landing" was the first question asked when dribble felt dead.
			local okBack, back = pcall(debug.getupvalue, fn, i)
			if okBack and type(back) == "number" and back > now and not S.upvalWarned then
				S.upvalWarned = true
				log("WARNING debug.setupvalue did not take on upvalue #" .. i
					.. " - the dribble/slide gate cannot be cleared on this executor")
			end
			cleared = cleared + 1
		end
	end
	return cleared
end

-- Declared here, defined further down: the Shoot wrapper calls it, and a local
-- defined AFTER its call site would be read as a nil global (AGENTS.md ledger).
local inDribbleGap

-- Same lifecycle contract as the ability hook below: the original is stashed on
-- the controller under our own key so a re-inject rebuilds from the TRUE
-- original instead of chaining onto a stale wrapper, `orig` is a local upvalue
-- so a stale wrapper still forwards, and restore is by identity.
-- One-shot upvalue census (.23). `cleared 0 future deadline(s)` on a SECOND
-- dribble inside the same second should be impossible: the first call ran
-- 0870:645 `u11 = tick() + v73`, so a future number must be sitting in the
-- closure. Seeing 0 anyway means the scan is not reading the closure we think
-- it is, or this executor's debug.getupvalue refuses the very first index and
-- the loop terminates before it starts -- and the existing read-back warning
-- cannot tell those apart, because it only runs INSIDE the `val > now` branch
-- that never executes. So dump what the scan actually sees, once per method.
local function censusUpvalues(fn, label)
	if S.census[label] then
		return
	end
	S.census[label] = true
	if type(fn) ~= "function" then
		log("census " .. label .. ": not a function")
		return
	end
	if type(debug) ~= "table" or type(debug.getupvalue) ~= "function" then
		log("census " .. label .. ": debug.getupvalue unavailable on this executor")
		return
	end
	local now = tick()
	local parts, n = {}, 0
	for i = 1, 48 do
		local ok, val = pcall(debug.getupvalue, fn, i)
		if not ok then
			parts[#parts + 1] = ("#%d THREW(%s)"):format(i, tostring(val):sub(1, 40))
			break
		end
		n = i
		local t = type(val)
		if t == "number" then
			parts[#parts + 1] = ("#%d num %+.2fs"):format(i, val - now)
		else
			parts[#parts + 1] = ("#%d %s"):format(i, t)
		end
	end
	log(("census %s: %d upvalue(s) readable -- %s"):format(label, n, table.concat(parts, " ")))
end

local function wrapBallAction(ctrl, methodName, cfgKey)
	if type(ctrl) ~= "table" then
		return
	end
	local key = "__blr_orig_" .. methodName
	local orig = rawget(ctrl, key)
	if type(orig) ~= "function" then
		orig = ctrl[methodName]
		if type(orig) ~= "function" then
			return
		end
	else
		log("healed a stale " .. methodName .. " wrapper from an earlier inject")
	end
	ctrl[key] = orig
	if methodName == "Dribble" then
		S.origDribble = orig
	elseif methodName == "Slide" then
		S.origSlide = orig
	elseif methodName == "Shoot" then
		S.origShoot = orig
	end
	local wrapper
	wrapper = function(self, ...)
		-- Shoot carries the volley guard; Dribble/Slide carry the cooldown clear.
		if methodName == "Shoot" then
			if S.alive and CFG.VolleyGuard and inDribbleGap() then
				S.volleyBlocked = (S.volleyBlocked or 0) + 1
				if S.volleyBlocked <= 6 then
					log(("volley guard #%d: click ignored, no ball but held it %.0fms ago (0870:341 would have forced power 110)")
						:format(S.volleyBlocked, (os.clock() - (S.lastHadBall or os.clock())) * 1000))
				end
				return
			end
			return orig(self, ...)
		end
		local on = S.alive and CFG[cfgKey]
		local cleared = 0
		if on then
			-- Census FIRST, on the second call: by then 0870:645 has definitely
			-- written a future deadline, so an all-past census is the answer.
			if (S.callCount[methodName] or 0) == 1 then
				censusUpvalues(orig, methodName)
			end
			cleared = clearFutureTickUpvalues(orig)
		end
		local results = table.pack(orig(self, ...))
		if on then
			clearFutureTickUpvalues(orig)
			-- First three calls only: proof in the log that the keypress reaches
			-- our wrapper at all and that a live deadline was found to clear.
			-- "The toggle is ON" and "the bypass ran" are different claims.
			S.callCount[methodName] = (S.callCount[methodName] or 0) + 1
			if S.callCount[methodName] <= 8 then
				log(("%s call #%d: cleared %d future deadline(s) before the call")
					:format(methodName, S.callCount[methodName], cleared))
			end
		end
		return table.unpack(results, 1, results.n)
	end
	S.wrappers[methodName] = wrapper
	ctrl[methodName] = wrapper
end

local function restoreBallAction(ctrl, methodName, orig)
	if type(ctrl) ~= "table" or type(orig) ~= "function" then
		return
	end
	-- Identity only: never clobber a wrapper a LATER inject installed.
	if rawequal(ctrl[methodName], S.wrappers[methodName]) then
		ctrl[methodName] = orig
	end
	S.wrappers[methodName] = nil
end

--======================================================================
-- Dribble cooldown claim (.20) -- rung 6, UNPROVEN until the log says so
--
-- 0870:614-644 computes v73, the client's own next dribble cooldown, writes it
-- into the local gate (`u11 = tick() + v73`, :645) and then SENDS THE SAME
-- NUMBER to the server at :647:
--     p70.BallService.Dribble:Fire(jobId, v73)
-- The server does something with it and broadcasts a duration back on
-- BallService.UpdateDribbleCooldown(character, seconds), which 0430:58-64 draws
-- as a cooldown bar over every OTHER player -- 0430:59 skips the local character
-- explicitly, which is what proves the broadcast includes our own.
--
-- So: if the echoed seconds equal the seconds we sent, the server is trusting
-- the client's claim, and shrinking it shortens the SERVER's dribble gate. That
-- is the only gate that matters, because the server one is what decides whether
-- a dribble registers -- Values.Dribbling, the VFX and the evade all come from
-- the accepted call, never from the local animation.
--
-- We do not assert that outcome here. We send the smaller number and log both
-- halves; the log answers it. Never rewrite upward, and never rewrite a
-- non-number: an argument shape we do not recognise is one the dump did not
-- describe, and guessing at it is how a working dribble dies.
local CLAIM_FLOOR = 0.25
local ECHO_LOG_LIMIT = 24

local function hookDribbleFire()
	if S.origDribbleFire then
		return
	end
	local svc = S.ball and S.ball.BallService
	local sig = type(svc) == "table" and svc.Dribble or nil
	if type(sig) ~= "table" or type(sig.Fire) ~= "function" then
		log("BallService.Dribble signal not found - CD claim unavailable")
		return
	end
	local orig = sig.Fire
	-- Knit puts Fire on the class metatable, so our assignment is an OWN field
	-- shadowing it. Remember which it was: restoring an inherited method by
	-- assignment would leave a permanent own copy behind.
	local wasOwn = rawget(sig, "Fire") ~= nil
	local wrapper
	wrapper = function(self, jobId, seconds, ...)
		if S.alive and CFG.DribbleCDClaim and type(seconds) == "number" then
			local claim = math.max(tonumber(CFG.DribbleCDClaimSeconds) or 1, CLAIM_FLOOR)
			if claim < seconds then
				S.claimCount = (S.claimCount or 0) + 1
				S.lastClaim = claim
				if S.claimCount <= ECHO_LOG_LIMIT then
					log(("claim #%d: dribble CD sent as %.2fs instead of the game's %.2fs")
						:format(S.claimCount, claim, seconds))
				end
				seconds = claim
			end
		end
		return orig(self, jobId, seconds, ...)
	end
	local ok = pcall(function()
		sig.Fire = wrapper
	end)
	if not ok or not rawequal(rawget(sig, "Fire"), wrapper) then
		log("BallService.Dribble.Fire is not writable - CD claim unavailable")
		return
	end
	S.origDribbleFire = orig
	S.dribbleFireOwn = wasOwn
	S.dribbleFireWrapper = wrapper
	S.dribbleSignal = sig

	-- The other half of the test. Only our own character is interesting: the
	-- bars over everyone else are 0430's business.
	if type(svc.UpdateDribbleCooldown) == "table" and type(svc.UpdateDribbleCooldown.Connect) == "function" then
		local okConn = pcall(function()
			-- .23: log EVERY broadcast, not only our own character. The .20 filter
			-- was `character ~= LP.Character -> return`, which is silent in the
			-- two cases that matter most: the server sending a Player instead of
			-- a character, and LP.Character being a stale reference after a
			-- respawn. A test that cannot tell "no broadcast happened" from "the
			-- broadcast was filtered out by my own code" answers nothing.
			connect(svc.UpdateDribbleCooldown, function(who, seconds)
				S.echoCount = (S.echoCount or 0) + 1
				if S.echoCount > ECHO_LOG_LIMIT then
					return
				end
				local mine = (who == LP.Character) or (who == LP)
				local claimed = S.lastClaim
				log(("echo #%d: %s <- %s (%s) | last claim %s")
					:format(S.echoCount,
						type(seconds) == "number" and string.format("%.2fs", seconds) or ("non-number " .. type(seconds)),
						mine and "US" or tostring(who),
						typeof(who),
						claimed and string.format("%.2fs", claimed) or "none - claim OFF"))
			end)
		end)
		if not okConn then
			log("UpdateDribbleCooldown connect failed - claim cannot be verified from the log")
		end
	else
		log("UpdateDribbleCooldown missing - claim cannot be verified from the log")
	end
	log("BallService.Dribble.Fire wrapped for CD claim")
end

local function unhookDribbleFire()
	local sig, orig = S.dribbleSignal, S.origDribbleFire
	if type(sig) == "table" and type(orig) == "function" then
		-- Identity only, same rule as restoreBallAction: never clobber a wrapper
		-- a later inject installed.
		if rawequal(rawget(sig, "Fire"), S.dribbleFireWrapper) then
			if S.dribbleFireOwn then
				sig.Fire = orig
			else
				pcall(function()
					sig.Fire = nil
				end)
			end
		end
	end
	S.origDribbleFire, S.dribbleFireWrapper, S.dribbleSignal, S.dribbleFireOwn = nil, nil, nil, nil
end

local function applyAbilityBalancing(enable)
	local bal = S.balancing
	if type(bal) ~= "table" then
		return
	end
	-- ShotPower / ShotPowerMax ONLY. The dump proves those two are read straight
	-- into the football's AssemblyLinearVelocity (0375:81, 0377:127, 0379:72,
	-- 0382:113, 0385:64, 0388:60) -- pure client physics, and scaling them can
	-- only change how hard the ball leaves.
	--
	-- Cooldown and ActivationRange* are deliberately NOT touched any more:
	--   * Cooldown was redundant. The dump-proven cooldown seam is the writer,
	--     LegacyFunctions.AbilityCooldown (0815:89), which NoAbilityCD already
	--     hooks. Rewriting the source table as well was a second, blinder path
	--     to the same result.
	--   * ActivationRange* is compared in BOTH directions across the ability
	--     modules -- `Magnitude < range` in some (0384:83, DragonicVolley), but
	--     `range < Magnitude` in others (OffBalance) -- and some modules copy it
	--     into a local and reassign it while picking a target (0378:61-63).
	--     One blanket multiplier cannot be correct for all of them, and nothing
	--     in the dump says which way each one wants. Guessing here is what the
	--     dump-first rule exists to stop.
	--
	-- ShotTiltVector IS touched, and it is the whole point of the arc trim.
	-- Every ability that shoots builds its velocity the same way:
	--   AssemblyLinearVelocity = (LookVector + <move>.ShotTiltVector [+ curve])
	--                            * <move>.ShotPower          (0547:210, 0375:74)
	-- so multiplying ShotPower multiplies the vertical component too: the ball
	-- leaves faster AND steeper, hangs, and reads as obviously wrong from the
	-- stands. Scaling Tilt.Y down by ArcTrim at the same time keeps the flight
	-- flat, so the extra power lands as distance instead of altitude. Only .Y is
	-- scaled -- X/Z carry the sideways lean some moves ship with (LeftyShot).
	-- Reference tilts in the dump (0061): KaiserImpact 0.05, KaiserCRShot 0.05,
	-- Beinschuss 0.1, Magnus 0.13, KaiserVolley 0.2. 0.05 is what a flat, fast
	-- shot already looks like in this game, so ArcTrim never goes below it.
	local FIELDS = { "ShotPower", "ShotPowerMax" }
	local MIN_TILT_Y = 0.05
	if enable then
		local mult = tonumber(CFG.AbilityPowerMult) or 1.20
		local trim = tonumber(CFG.AbilityArcTrim) or 0.75
		for name, row in pairs(bal) do
			if type(row) == "table" then
				if S.balancingOrig[name] == nil then
					local snap = {}
					for _, f in ipairs(FIELDS) do
						snap[f] = row[f]
					end
					snap.ShotTiltVector = row.ShotTiltVector
					S.balancingOrig[name] = snap
				end
				local orig = S.balancingOrig[name]
				for _, f in ipairs(FIELDS) do
					if type(orig[f]) == "number" then
						row[f] = orig[f] * mult
					end
				end
				local tilt = orig.ShotTiltVector
				if typeof(tilt) == "Vector3" then
					row.ShotTiltVector = Vector3.new(tilt.X, math.max(tilt.Y * trim, MIN_TILT_Y), tilt.Z)
				end
			end
		end
	else
		for name, orig in pairs(S.balancingOrig) do
			local row = bal[name]
			if type(row) == "table" and type(orig) == "table" then
				for _, f in ipairs(FIELDS) do
					if orig[f] ~= nil then
						row[f] = orig[f]
					end
				end
				if orig.ShotTiltVector ~= nil then
					row.ShotTiltVector = orig.ShotTiltVector
				end
			end
		end
	end
end

-- Swap tuning profiles when the style changes. Ability power is a one-shot
-- mutation of the AbilityBalancing table, not a per-frame read, so a new
-- multiplier only takes effect if it is re-applied here -- the sliders' own
-- commit already knows that, and a style change is the same event.
local function onStyleChanged(newStyle)
	if type(newStyle) ~= "string" or newStyle == "" or newStyle == S.style then
		return
	end
	if S.style then
		captureProfile(S.style)
	end
	S.style = newStyle
	local hadProfile, applied = applyProfile(newStyle)
	refreshSliders()
	if CFG.AbilityPower then
		applyAbilityBalancing(true)
	end
	saveConfig()
	local how = "first time seen - adopted the numbers currently on screen"
	if hadProfile then
		how = "profile loaded, " .. tostring(applied or 0) .. " value(s) changed"
	end
	log(("style -> %s (%s)"):format(newStyle, how))
end

local function watchStyle()
	task.spawn(function()
		local stats = LP:FindFirstChild("PlayerStats") or LP:WaitForChild("PlayerStats", 30)
		local style = stats and (stats:FindFirstChild("Style") or stats:WaitForChild("Style", 30))
		if not style then
			-- No signal to watch. Still load a profile for whatever the fallback
			-- says, so the feature degrades to "right at boot" instead of "off".
			S.style = S.style or currentStyle()
			applyProfile(S.style)
			refreshSliders()
			log("PlayerStats.Style missing - per-style profiles pinned to " .. tostring(S.style))
			return
		end
		onStyleChanged(currentStyle())
		-- Style is a child of the PLAYER, not the character, so it survives every
		-- respawn and one connection covers the whole session (0111:8).
		connect(style.Changed, function(value)
			if S.alive then
				onStyleChanged(value)
			end
		end)
	end)
end

-- HOOK LIFECYCLE -- read this before touching any wrapper in this file.
--
-- A wrapper we install can outlive us. If the user re-injects, or an unload
-- fails to restore, the GAME still holds a reference to the old closure. So a
-- wrapper must satisfy two rules or it becomes a landmine:
--
--   1. It closes over the original as a LOCAL upvalue and calls that. Reading
--      `S.something` at call time is fatal: unload nils the field, the stale
--      wrapper calls nil, and every ability that routes through it dies with
--      "attempt to call a nil value" until the player rejoins. That is exactly
--      what killed Loki's V and C -- the stack was
--        AbilityCooldown -> blr_hub wrapper -> nil
--      for VelocityDash:92 and ExplosiveAcceleration:39, and re-injecting did
--      not help because the new inject just chained a second wrapper onto the
--      broken one.
--   2. The true original is stashed on the game's own table under our own key.
--      A fresh inject rebuilds from THAT, which heals a stale chain instead of
--      extending it -- no rejoin needed.
--
-- Restore is by identity (`current == the wrapper we installed`), never by
-- guessing from upvalues, and `S.orig*` is never cleared.
local ORIG_KEY = "__blr_orig_AbilityCooldown"

-- The minimum AbilityCooldown does for its caller: stamp the slot deadline on
-- the table it was given (0815:105). Used only when the real function cannot be
-- reached any more; every module reads that field and nothing else from it.
local function fallbackCooldown(slot, tableRef, seconds)
	local field = SLOT_FIELD[tostring(slot)]
	if field and type(tableRef) == "table" then
		tableRef[field] = tick() + (tonumber(seconds) or 0)
	end
end

local function hookAbilityCooldown()
	local ok, legacy = pcall(require, ReplicatedStorage.Controllers.AbilityController.LegacyFunctions)
	if not ok or type(legacy) ~= "table" then
		log("LegacyFunctions missing")
		return
	end
	-- Prefer a previous inject's stash: if one exists, whatever is in
	-- AbilityCooldown right now is a stale wrapper of ours and must be replaced,
	-- not wrapped again.
	local orig = rawget(legacy, ORIG_KEY)
	if type(orig) ~= "function" then
		orig = legacy.AbilityCooldown
		if type(orig) ~= "function" then
			log("LegacyFunctions.AbilityCooldown missing")
			return
		end
	else
		log("healed a stale AbilityCooldown wrapper from an earlier inject")
	end
	legacy[ORIG_KEY] = orig
	S.legacyCD = legacy
	S.origAbilityCooldown = orig

	local wrapper
	wrapper = function(slot, abilityName, tableRef, seconds, flag)
		-- `orig` is a local upvalue: valid for the life of this closure, even if
		-- this script is long gone.
		if S.alive and CFG.NoAbilityCD then
			-- Every cast routes through here, so this is the one place that knows a
			-- cast just started and which slot it used. The hold stops a re-press
			-- from orphaning the cast; nothing is inferred from it beyond that.
			local field = SLOT_FIELD[tostring(slot)]
			if field then
				S.slotHold[field] = os.clock() + CAST_GUARD_SECONDS
				S.pending[field] = { at = os.clock(), name = tostring(abilityName) }
			end
			-- Not 0: 0815:110 computes `1 - v21 / (p17 or v21)`, so a 0 second
			-- cooldown makes that 0/0 = nan and the UIGradient offset garbage.
			-- Also keep it <= 1 so 0815:94 does not swap in the
			-- ReplicatedStorage.AbilityCooldowns attribute (that branch is
			-- `p16 > 1` only).
			seconds = 0.05
		end
		-- SURVIVING A POISONED CHAIN.
		-- `orig` here can be a wrapper left behind by an OLDER inject of this
		-- script (before .19 stashed the true original), and those forward to a
		-- field their dead state already nil'd. Calling one throws
		-- "attempt to call a nil value" out of AbilityCooldown, which aborts the
		-- ability module that called it -- Loki's C died at
		-- ExplosiveAcceleration:39 for exactly this reason, and no re-inject could
		-- fix it because the true original was already unreachable.
		-- So the call is guarded, and on failure we do the ONE thing
		-- AbilityCooldown owes its caller: write the slot deadline on the table it
		-- was handed (0815:105, `u15[u2[u18]] = tick() + v21`). The cooldown UI
		-- tween is lost until the next rejoin; the ability itself runs.
		if S.cdChainBroken then
			return fallbackCooldown(slot, tableRef, seconds)
		end
		local okCall, err = pcall(orig, slot, abilityName, tableRef, seconds, flag)
		if okCall then
			return
		end
		S.cdChainBroken = true
		log("AbilityCooldown chain is poisoned by an older inject (" .. tostring(err)
			.. ") - writing the slot deadline directly from here on. Rejoin to restore the cooldown UI.")
		return fallbackCooldown(slot, tableRef, seconds)
	end
	S.cdWrapper = wrapper
	legacy.AbilityCooldown = wrapper
end

local function unhookAbilityCooldown()
	local legacy = S.legacyCD
	if legacy and S.cdWrapper and rawequal(legacy.AbilityCooldown, S.cdWrapper) then
		legacy.AbilityCooldown = S.origAbilityCooldown
	end
	S.cdWrapper = nil
	-- S.origAbilityCooldown is deliberately NOT cleared: a wrapper that is still
	-- installed somewhere must keep working.
end

-- Auto-lock Blue CF -------------------------------------------------------
-- "Blue" is the Home team: teams.txt gives Home color=Electric blue, Away
-- color=Institutional white. The seat is ReplicatedStorage.Teams.HomeTeam.CF
-- [ObjectValue] (tree 213440); nil Value = free, otherwise it holds the player.
-- The claim is one remote: TeamService.Select:Fire(teamName, roleName), which is
-- exactly what the game's own button does (1145:213, `Service.Select:Fire(
-- p33.Parent.Name, p33.Name)` where Parent is Home/Away and Name is the role).
-- Opening the PickTeam GUI is pure client presentation (1147:766) and is NOT a
-- prerequisite, so we never have to fake a click.
--
-- WHEN, and why not earlier. GameValues.State runs
--   Playing -> Ending -> Ended -> Intermission -> StartingCutscene -> Playing.
-- "Ending" is the end-of-match cutscene: CameraController takes the camera
-- Scriptable, blacks the screen out and holds for GameValues.EndingDuration
-- (0878:174-190), and 1138:281 pins WalkSpeed to 0 for the whole of it (the same
-- line the Kaiser Volley freeze went through, via PostMatch.Enabled). Claiming a
-- seat inside that window is what leaves the character needing a reset: the
-- game's own Select response handler assumes it is either in Intermission -- where
-- it plays the blackout teleport (1145:605) -- or holding a live character it can
-- tween the camera onto (1145:542), and during Ending neither is true.
-- Intermission is the first state where the game's own path is correct, so that
-- is the trigger, plus a short settle so the state's own handlers run first.
--
-- PRIORITY, and it is not negotiable: Home (blue) CF is tried on every single
-- pass. teams.txt: Home color=Electric blue, Away color=Institutional white, and
-- blue kicks off with the ball, which is the entire reason for the feature.
-- Away CF is a FALLBACK only -- it is fired in the same pass, on the next frame,
-- but only after Home CF is observed holding another player. If Home CF frees up
-- again the next pass goes straight back to it.
local LOCK_TEAM = "Home"
local FALLBACK_TEAM = "Away"
local LOCK_ROLE = "CF"
local LOCK_STATES = { Intermission = true } -- the only safe window; see above
local LOCK_SETTLE = 0.35 -- matches the game's own post-Select delay (1145:527)
local LOCK_RETRY = 3.1 -- the game's own SelectPos debounce is 3s (1145:212)
local LOCK_MAX_TRIES = 6

local function teamFolder(teamName)
	local teams = ReplicatedStorage:FindFirstChild("Teams")
	if not teams then
		return nil
	end
	return teams:FindFirstChild(teamName) or teams:FindFirstChild(teamName .. "Team")
end

local function cfSeat(teamName)
	local folder = teamFolder(teamName or LOCK_TEAM)
	return folder and folder:FindFirstChild(LOCK_ROLE) or nil
end

local function gameState()
	local values = ReplicatedStorage:FindFirstChild("GameValues")
	local state = values and values:FindFirstChild("State")
	return state and state.Value or nil
end

-- Fires only when every gate the game's own SelectPos would apply is already
-- satisfied, so a refusal costs us nothing and the server sees no wasted call.
-- Per-team fire spacing, so a retry loop cannot machine-gun the same Select.
-- 1145:212 spaces the game's own button by 3s; we keep that per team.
local lastFireAt = {}

local function claimSeat(teamName, reason)
	local seat = cfSeat(teamName)
	if not seat then
		return nil -- team folder not there yet
	end
	if seat.Value == LP then
		log("lock confirmed: " .. teamName .. " " .. LOCK_ROLE .. " belongs to LocalPlayer")
		return true
	end
	if seat.Value ~= nil then
		return false, "taken by " .. tostring(seat.Value)
	end
	local svc = S.teamService
	if type(svc) ~= "table" or type(svc.Select) ~= "table" then
		log("lock skipped: TeamService.Select missing")
		return nil
	end
	local now = os.clock()
	if (lastFireAt[teamName] or -math.huge) + LOCK_RETRY > now then
		return nil -- fired recently; give the server its window to answer
	end
	lastFireAt[teamName] = now
	local ok, err = pcall(function()
		svc.Select:Fire(teamName, LOCK_ROLE)
	end)
	if not ok then
		log("lock fire failed: " .. tostring(err))
		return nil
	end
	log("fired Select " .. teamName .. " " .. LOCK_ROLE .. " (" .. reason .. "); awaiting seat confirmation")
	return nil -- sent is not success; only seat.Value == LP confirms ownership
end

local function tryLockCF(reason)
	if not (S.alive and CFG.CFLocker) then
		return false
	end
	-- The two gates that are about US, not about a seat: unchanged from .9, and
	-- they are what keeps the end-of-match freeze away.
	if not LOCK_STATES[gameState() or ""] then
		return false
	end
	if LP:GetAttribute("PackBusy") then
		log("lock skipped: PackBusy (1145:208 refuses too)")
		return false
	end
	-- BLUE FIRST, every pass, no exceptions.
	local blue, blueWhy = claimSeat(LOCK_TEAM, reason)
	if blue then
		return true
	end
	if blue == nil then
		return false -- nothing to fall back from: we have not been refused yet
	end
	-- Blue is held by another player. Only now does white exist.
	if not CFG.CFFallbackWhite then
		log("lock: " .. LOCK_TEAM .. " CF " .. tostring(blueWhy) .. ", white fallback off")
		return false
	end
	local white = claimSeat(FALLBACK_TEAM, reason .. " / blue " .. tostring(blueWhy))
	return white == true
end

-- One attempt run per match end. Retries on the game's own 3s cadence, because a
-- seat can be contested and the server can refuse while the state is still
-- settling, and stops the moment the seat is ours or the window closes.
local function runLockAttempt(reason)
	if S.lockRunning then
		return
	end
	S.lockRunning = true
	task.spawn(function()
		task.wait(LOCK_SETTLE)
		-- Polls fast, FIRES slow. claimSeat keeps each team on the game's own 3s
		-- spacing, so the extra polls cost the server nothing -- they exist so
		-- that the frame blue is proven taken is the frame white gets claimed,
		-- instead of losing white during a 3s sleep as well.
		local deadline = os.clock() + LOCK_MAX_TRIES * LOCK_RETRY
		local confirmed = false
		while os.clock() < deadline do
			if not (S.alive and CFG.CFLocker) then
				break
			end
			if not LOCK_STATES[gameState() or ""] then
				break -- window closed; do not fire into StartingCutscene
			end
			if tryLockCF(reason) then
				confirmed = true
				break
			end
			task.wait(0.2)
		end
		if not confirmed and S.alive and CFG.CFLocker then
			log("lock ended without confirmed CF ownership (state=" .. tostring(gameState()) .. ")")
		end
		S.lockRunning = false
	end)
end

local function watchMatchEnd()
	if S.stateConn then
		return
	end
	local values = ReplicatedStorage:FindFirstChild("GameValues")
	local state = values and values:FindFirstChild("State")
	if not state then
		log("GameValues.State missing - auto lock cannot arm")
		return
	end
	S.stateConn = connect(state:GetPropertyChangedSignal("Value"), function()
		if not (S.alive and CFG.CFLocker) then
			return
		end
		if LOCK_STATES[state.Value or ""] then
			runLockAttempt("state -> " .. tostring(state.Value))
		end
	end)
	log("auto lock watching GameValues.State (now " .. tostring(state.Value) .. ")")
end

local function hookStamina()
	if S.staminaHook then
		return
	end
	local ok, knit = pcall(require, ReplicatedStorage.Packages.Knit.KnitClient)
	if not ok or type(knit) ~= "table" then
		return
	end
	local svc
	pcall(function()
		svc = knit.GetService("StaminaService")
	end)
	if type(svc) ~= "table" or type(svc.DecreaseStamina) ~= "table" then
		return
	end
	local remote = svc.DecreaseStamina
	if type(remote.Fire) ~= "function" then
		return
	end
	local origFire = remote.Fire
	-- Was Fire an own field, or inherited from the ClientRemoteSignal class via
	-- __index? Restore must reproduce whichever it was.
	S.staminaHook = { remote = remote, origFire = origFire, wasOwn = rawget(remote, "Fire") ~= nil }
	remote.Fire = function(self, ...)
		if S.alive and CFG.InfiniteStamina then
			return
		end
		return origFire(self, ...)
	end
end

local function unhookStamina()
	local h = S.staminaHook
	if not h then
		return
	end
	if h.remote and h.origFire then
		h.remote.Fire = h.wasOwn and h.origFire or nil
	end
	S.staminaHook = nil
end

-- Kaiser Volley freeze (fixed in .7): an ability module sets
-- StatesController.States.Ability = true BEFORE it fires AbilityService.Ability,
-- and only clears it inside the "start" reply handler (0547:100-133). While it is
-- true, 1138:281 pins Humanoid.WalkSpeed = 0 and JumpHeight = 0 -- that is the
-- "stand still".
-- Pinning AbilityThree to 0 every frame kept the module's own re-entry gate
-- (`if u1.AbilityThree > tick() then return end`, 0547:80) permanently open, so a
-- second B press re-entered the module and ran `u1.ABC:Clean()` (0547:83), which
-- disconnects the FIRST cast's pending "start" listener. The server still owns a
-- 10s global cooldown on this move (`KaiserVolley_LastUsage`, 0547:76), so the
-- second cast is refused, no "start" ever arrives, nobody clears States.Ability,
-- and WalkSpeed stays 0 for good.
-- Fix: never open the cooldown gate while an ability is actually executing, plus
-- a watchdog for a cast that was already orphaned. Both are local writes (rung 3).
-- The States.Ability flag is not up for the WHOLE vulnerable window. NEL Isagi's
-- TrueDirectShot (0528/0638) casts, then waits `repeat task.wait() until tick() >
-- u9 + 1.5 or HasBall` (0528:125) with the flag still FALSE, and only raises it at
-- :133 to fire the second half. A re-press inside that 1.5s runs `ABC:Clean()`
-- (0528:32) on the pending listener, so the "Shoot" reply lands on nothing and the
-- flag it just raised is never lowered.
-- So the slot that was cast is held closed for a short window after the cast. We
-- hold it ourselves rather than passing a bigger `seconds` to AbilityCooldown,
-- because 0815:93 replaces any value > 1 with the ReplicatedStorage.AbilityCooldowns
-- attribute -- the real cooldown -- which would defeat the toggle entirely.
-- Cost: an ability cannot be recast for CAST_GUARD_SECONDS. Only the slot that was
-- cast is held; the other two stay instant.
-- WHAT .12 CHANGED, and why the toggle felt dead
--   1. The hold was applied to iface.AbilityUsed as well, and AbilityUsed is the
--      SHARED gate every slot reads (0379:31, 0378:34, 0607:33). So casting slot 1
--      shut all three slots for the whole hold -- "the other two stay instant" was
--      simply wrong. AbilityUsed is now only left alone mid-cast; it is never held
--      on behalf of another slot.
--   2. The hold ran a flat 2.5s even when the cast had already resolved. It now
--      ends the moment the cast completes (States.Ability came up and went back
--      down), with 1.5s as the floor -- the length of TrueDirectShot's take-phase
--      (0528:125), which is the window a re-press actually breaks.
--   3. A cast the SERVER refuses never replies, so States.Ability stays true and
--      you stand frozen until a watchdog fires. That watchdog was 6s. It is now
--      2s, and a refused cast additionally puts that ONE slot back on its real
--      cooldown (captured in the hook) instead of us re-offering a cast the server
--      will refuse again. Client cooldown bypass cannot beat a server check -- what
--      it can do is stop walking into it repeatedly.
-- 5s, not 2s. The longest legitimate cast window in the dump is VelocityShot's
-- own `task.delay(2, ABC:Clean)` (0614:83), so anything under ~3s can and did
-- fire during a healthy ability. 5s still ends a real freeze quickly enough to
-- keep playing, and cannot land inside a working cast.
local ABILITY_STUCK_SECONDS = 5
local CAST_RESOLVE_FLOOR = 1.5 -- 0528:125 take-phase

local function abilityActive()
	local states = S.states and S.states.States
	return type(states) == "table" and states.Ability == true
end

-- Decide what happened to the cast we are holding a slot for.
--
-- .17 RULE, learned the hard way: this function may release OUR OWN hold and
-- nothing else. It must never write the game's state and never take a slot away.
-- .12 inferred "the server refused" from States.Ability still being true at
-- 1.5s, then cleared that flag and parked the slot on its real cooldown. Loki's
-- V (VelocityShot, 0614) legitimately keeps States.Ability true until its reply
-- and self-cleans at `task.delay(2, ABC:Clean)` -- 2 full seconds. So a perfectly
-- healthy cast was declared refused at 1.5s, had its state flag yanked
-- mid-flight, and lost slot 2 for the move's real 35s cooldown. That is how
-- fixing Yukimiya broke Loki.
-- A wrong guess here silently disables a character's ability. A missing guess
-- costs nothing that was not already broken, so this side of the trade is the
-- only acceptable one: infer LESS. Orphan recovery is left to the watchdog
-- below, which waits long enough that no legitimate cast can be inside it.
local function resolveCast()
	local now = os.clock()
	for field, p in pairs(S.pending) do
		local age = now - p.at
		if abilityActive() then
			p.sawActive = true
		end
		if p.sawActive and not abilityActive() and age >= 0.15 then
			-- Reply landed and the module cleaned up: the slot is free NOW.
			S.pending[field] = nil
			S.slotHold[field] = nil
		elseif age >= CAST_RESOLVE_FLOOR and not abilityActive() then
			-- Nothing is executing, so the hold has done its job.
			S.pending[field] = nil
			S.slotHold[field] = nil
		elseif age >= ABILITY_STUCK_SECONDS then
			-- Still executing long past any real cast. Stop tracking it; the
			-- watchdog owns recovery from here and it is the only thing allowed
			-- to touch States.Ability.
			S.pending[field] = nil
		end
	end
end

local function pinAbilitySlots()
	local iface = S.iface
	if type(iface) ~= "table" then
		return
	end
	if abilityActive() then
		-- Mid-cast. Leave every deadline alone, AbilityUsed included, so the module
		-- cannot be re-entered and orphan its own "start" handler.
		S.abilityTrueAt = S.abilityTrueAt or os.clock()
		return
	end
	S.abilityTrueAt = nil
	local now = os.clock()
	for _, field in pairs(SLOT_FIELD) do
		local until_ = S.slotHold[field]
		if until_ and now >= until_ then
			S.slotHold[field] = nil
			until_ = nil
		end
		if until_ then
			-- Keep this ONE slot's `iface.<slot> > tick()` gate shut. 0.1 is enough
			-- to stay in the future until the next Heartbeat renews it.
			iface[field] = tick() + 0.1
		else
			iface[field] = 0
		end
	end
	-- AbilityUsed is the SHARED gate (0379:31). Holding it on behalf of one slot
	-- silently disabled the other two, which is what made the toggle look broken.
	-- Out of a cast it is always open.
	iface.AbilityUsed = 0
end

-- Backstop for a cast that was orphaned without a pending record (re-inject
-- mid-cast, a module we never saw call AbilityCooldown). Every cutscene ability
-- also sets Camera.Cutscene, a separate term in the same 1138:281 condition, so
-- clearing Ability here cannot free movement during a cutscene.
local function clearStuckAbility()
	if not abilityActive() then
		S.abilityTrueAt = nil
		return
	end
	if not S.abilityTrueAt then
		S.abilityTrueAt = os.clock()
		return
	end
	if os.clock() - S.abilityTrueAt < ABILITY_STUCK_SECONDS then
		return
	end
	S.abilityTrueAt = nil
	pcall(function()
		S.states.States.Ability = false
	end)
	log("cleared stuck States.Ability after " .. ABILITY_STUCK_SECONDS .. "s (WalkSpeed was pinned to 0)")
end

-- Tap guard -------------------------------------------------------------
-- THE BUG THIS FIXES, from 0870:
--   Left click starts BallController.Shoot (0870:171). It is a CHARGE: u3 runs
--   from 50 to 110 at ~125/s, and u6 runs at 45/s. Release sets HoldingShoot =
--   false and the next Heartbeat fires BallService.Shoot with whatever u3 has
--   reached (0870:286). Two things then bite a spam-clicking dribbler:
--     1. `if u6 >= 50 then u48() end` (0870:365) -- holding ~1.11s AUTO-FIRES,
--        no release needed. That is "it thought I was shooting".
--     2. The release handler starts `if p95 then return end` (0870:1004), and
--        p95 is gameProcessedEvent. If the mouse-UP lands on ANY GUI -- our own
--        panel included -- the game never clears HoldingShoot, the charge keeps
--        climbing, and rule 1 fires a near-full-power shot. The ball leaves your
--        feet and the nearest defender takes it.
-- What the guard does, both rung 3 (local field / local upvalue writes, no new
-- remote, and the shot itself is one the player already started):
--   * Every frame, if the physical mouse button is UP but HoldingShoot is still
--     true, set HoldingShoot = false. That hands the release to the GAME's own
--     u48 path on its next Heartbeat -- we do not fire anything ourselves.
--   * If the click lasted less than TapWindowMs, the charge upvalue is written
--     down to TapPower first, so a dribble tap leaves as a soft touch instead of
--     a 70-90 power shot. Holds longer than the window are left completely
--     alone, so real charged shots are unchanged.
local TAP_MIN_POWER, TAP_MAX_POWER = 50, 110 -- 0870:39 start, 0870:376 clamp

-- u3 is a shared "(ref)" upvalue of Shoot and of its Heartbeat closure, so the
-- write lands for both. It is identified by value, not by index: while a hold is
-- running the only number in (50,110] is the charge (u6 stays under 50 until the
-- auto-fire boundary, u49 under 2.1, u38 is a tick() deadline).
local function setChargePower(fn, want)
	if type(fn) ~= "function" or type(debug) ~= "table" or type(debug.setupvalue) ~= "function" then
		return false
	end
	local bestIdx, bestVal
	for i = 1, 48 do
		local ok, val = pcall(debug.getupvalue, fn, i)
		if not ok then
			break
		end
		if type(val) == "number" and val > TAP_MIN_POWER and val <= TAP_MAX_POWER then
			if not bestVal or val > bestVal then
				bestIdx, bestVal = i, val
			end
		end
	end
	if not bestIdx or bestVal <= want then
		return false
	end
	pcall(debug.setupvalue, fn, bestIdx, want)
	local okBack, back = pcall(debug.getupvalue, fn, bestIdx)
	if okBack and type(back) == "number" and back > want + 0.5 then
		if not S.chargeWarned then
			S.chargeWarned = true
			log("WARNING debug.setupvalue did not take on the charge upvalue - tap power cannot be clamped")
		end
		return false
	end
	return true
end

-- WHY .14's VERSION STILL LET IT THROUGH
-- It sampled the physical button once per Heartbeat and returned whenever the
-- button was down. While you spam-click, the button IS down for most samples --
-- the next click has already started before we look. So the release we were
-- waiting for never got seen, the charge kept running, and 0870:365 auto-fired
-- it at ~1.11s exactly as before. Sampling cannot win a race against mashing.
-- .15 is event-driven instead: we take UserInputService.InputEnded ourselves and
-- IGNORE its gameProcessed flag -- the flag is the whole reason the game's own
-- handler misses these (0870:1004). Every button-up releases the charge, even
-- the ones that land on a GUI, and even if the next click follows 20ms later.
-- The Heartbeat check stays as a backstop for an event we never receive at all
-- (alt-tab, focus loss).
-- Accidental volley -----------------------------------------------------
-- THIS is the one that sends the ball 40 studs in front of you.
-- Shoot() captures `local Value = u2.Values.HasBall.Value` at the moment the
-- charge STARTS (0870:175). Its Heartbeat then runs (0870:341):
--     if Value == false and u2.Values.HasBall.Value then
--         u3 = 110            -- maximum charge, not the ~55 a tap deserves
--         u48()               -- and fire, immediately
--     end
-- and u48's `Value == false` branch plays the Volley animation and sends the
-- shot as "Volley" (0870:244-281). So: a click that lands in a frame where you
-- do NOT have the ball, followed by the ball arriving, is a guaranteed
-- full-power volley -- no hold, no charge time, nothing the tap guard can catch,
-- because the game never waits for a release at all.
-- While you dribble, HasBall drops for a few frames on every touch. Spam-click
-- through that gap and you volley your own dribble downfield. That is the bug.
-- The guard: if a click arrives while HasBall is false but we HELD the ball
-- within the last VolleyGapMs, that is a dribble gap, not a volley setup, so the
-- charge is never started -- our wrapper returns without calling the game's
-- Shoot. A real volley (receiving a pass, no ball for seconds) is untouched.
function inDribbleGap()
	local char = LP.Character
	local values = char and char:FindFirstChild("Values")
	local hasBall = values and values:FindFirstChild("HasBall")
	if not hasBall then
		return false
	end
	if hasBall.Value then
		S.lastHadBall = os.clock()
		return false
	end
	local last = S.lastHadBall
	if not last then
		return false
	end
	return (os.clock() - last) * 1000 < (tonumber(CFG.VolleyGapMs) or 700)
end

-- The header branch of BallService.Shoot runs only when
-- Humanoid:GetState() is Jumping or Freefall (0870:1303). Testing the same two
-- states one frame ahead is what makes HeaderPower a header-only multiplier
-- instead of a second global one: a grounded shot never sees it.
local function airborne()
	local char = LP.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then
		return false
	end
	local st = hum:GetState()
	return st == Enum.HumanoidStateType.Jumping or st == Enum.HumanoidStateType.Freefall
end

-- Header shaping ---------------------------------------------------------
-- The game's own handler for the BallService.Shoot signal writes the header
-- velocity as (LookVector + Vector3(0, arc, 0)) * power * ShotPowerMultiplier
-- (0870:1303-1327, arc default 0.3 at :1263). Raising ShotPowerMultiplier -- the
-- .18 approach -- scales that whole vector, so the ball got faster AND floatier,
-- which is the opposite of what a header wants.
-- The arc lives inside the game's product and we do not own that vector, so the
-- only place to separate speed from loft is AFTER the write: scale the
-- horizontal component up and the vertical one down, on the ball we already own
-- (rung 5 -- the game just wrote this same property from this same client).
--   horizontal * HeaderPowerMult   -> reaches the net sooner
--   vertical   * HeaderArcTrim     -> lower apex, and gravity brings it down
--                                     sooner because the apex is lower
-- Connection order on a Knit ClientRemoteSignal is not something to rely on, so
-- the write is deferred: task.defer runs after every handler of this fire has
-- finished, still inside the same frame, before physics steps.
local function shapeHeader(ball)
	if not (S.alive and CFG.HeaderPower) then
		return
	end
	if typeof(ball) ~= "Instance" or not ball:IsA("BasePart") then
		return
	end
	if not airborne() then
		return -- ground shot: the game took a different branch entirely
	end
	-- 0870:1270 reads Before.Value as the character that just had the ball. If it
	-- names someone else, this fire is not our header.
	local before = ball:FindFirstChild("Before")
	if before and before.Value and before.Value ~= LP.Character then
		return
	end
	task.defer(function()
		if not (S.alive and CFG.HeaderPower and ball.Parent) then
			return
		end
		local v = ball.AssemblyLinearVelocity
		local speed = v.Magnitude
		if speed < 1 then
			return -- the game's handler bailed; nothing was kicked
		end
		local k = tonumber(CFG.HeaderPowerMult) or 1.20
		local t = tonumber(CFG.HeaderArcTrim) or 0.70
		local nv = Vector3.new(v.X * k, v.Y * t, v.Z * k)
		ball.AssemblyLinearVelocity = nv
		S.headerShaped = (S.headerShaped or 0) + 1
		if S.headerShaped <= 3 then
			log(("header shaped #%d: %.0f -> %.0f studs/s, Y %.0f -> %.0f (x%.2f flat, %.0f%% arc)")
				:format(S.headerShaped, speed, nv.Magnitude, v.Y, nv.Y, k, t * 100))
		end
	end)
end

-- Connect once, whenever the BallController turns up. BallService.Shoot is a
-- Knit ClientRemoteSignal the SERVER fires back at the shooter; connecting is a
-- read, it sends nothing.
local function hookShootSignal(ctrl)
	if S.shootConn or type(ctrl) ~= "table" then
		return
	end
	local svc = rawget(ctrl, "BallService") or ctrl.BallService
	local sig = type(svc) == "table" and svc.Shoot or nil
	if type(sig) ~= "table" or type(sig.Connect) ~= "function" then
		log("BallService.Shoot signal not found - header shaping unavailable")
		return
	end
	S.shootConn = connect(sig, function(ball)
		shapeHeader(ball)
	end)
	log("BallService.Shoot signal connected (header shaping)")
end

local function releaseCharge(reason)
	local ball = S.ball
	if not (ball and ball.HoldingShoot) then
		S.holdStart = nil
		return false
	end
	local held = ((os.clock() - (S.holdStart or os.clock())) * 1000)
	local powered = false
	if held < (tonumber(CFG.TapWindowMs) or 220) then
		powered = setChargePower(S.origShoot or ball.Shoot, tonumber(CFG.TapPower) or 55)
	end
	-- Hand the release to the GAME's own path (0870:388) on its next Heartbeat.
	ball.HoldingShoot = false
	S.holdStart = nil
	S.guardCount = (S.guardCount or 0) + 1
	if S.guardCount <= 6 then
		log(("tap guard #%d: %s after %.0fms, charge %s")
			:format(S.guardCount, reason, held, powered and ("clamped to " .. tostring(CFG.TapPower)) or "left alone"))
	end
	return true
end

local function tapGuard()
	local ball = S.ball
	if not (ball and ball.HoldingShoot) then
		S.holdStart = nil
		return
	end
	S.holdStart = S.holdStart or os.clock()
	local down = false
	pcall(function()
		down = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
	end)
	if down then
		return -- genuinely still held; the charge is the player's business
	end
	releaseCharge("backstop poll")
end

local function pinStaminaValue()
	local stats = LP:FindFirstChild("PlayerStats")
	local stamina = stats and stats:FindFirstChild("Stamina")
	if stamina and stamina:IsA("NumberValue") and stamina.Value < 100 then
		pcall(function()
			stamina.Value = 100
		end)
	end
end

local function resolveControllers()
	local okIface, iface = pcall(require, ReplicatedStorage.Controllers.AbilityController.interface)
	if okIface and type(iface) == "table" then
		S.iface = iface
	end
	local okBal, bal = pcall(require, ReplicatedStorage.AbilityBalancing)
	if okBal and type(bal) == "table" then
		S.balancing = bal
	end
	local okStates, states = pcall(require, ReplicatedStorage.Controllers.StatesController)
	if okStates and type(states) == "table" then
		S.states = states
	end
	hookAbilityCooldown()
	local okKnit, knit = pcall(require, ReplicatedStorage.Packages.Knit.KnitClient)
	if not okKnit or type(knit) ~= "table" then
		log("KnitClient missing")
		return
	end
	pcall(function()
		S.teamService = knit.GetService("TeamService")
	end)
	if type(S.teamService) ~= "table" then
		log("TeamService missing - auto lock unavailable")
	end
	watchMatchEnd()
	local function grab()
		local ball
		pcall(function()
			ball = knit.GetController("BallController")
		end)
		if type(ball) == "table" and type(ball.Dribble) == "function" then
			S.ball = ball
			wrapBallAction(ball, "Shoot", nil)
			if not S.origDribble then
				wrapBallAction(ball, "Dribble", "NoDribbleCD")
			end
			if not S.origSlide then
				wrapBallAction(ball, "Slide", "NoSlideCD")
			end
			hookStamina()
			hookDribbleFire()
			hookShootSignal(ball)
			log("BallController wrapped")
			return true
		end
		return false
	end
	if not grab() then
		task.spawn(function()
			for _ = 1, 40 do
				if not S.alive then
					return
				end
				if grab() then
					return
				end
				task.wait(0.25)
			end
			log("BallController not found")
		end)
	end
end

-- GUI -- the shared R3ST control template. Every widget on this panel comes
-- from scripts/r3st_ui.lua, so Blue Lock Rivals looks like every other module
-- in the hub and differs only in which controls exist.
local COL

-- hub.lua publishes this immediately before running us. When it is present the
-- hub owns the ScreenGui, the window frame, the drag and the show/hide key, so
-- we render into its content host and grow no shell of our own. It also hands
-- us the loaded UI kit, so hub and module can never run two copies.
local HOST = (type(G.__R3ST_HOST) == "table" and typeof(G.__R3ST_HOST.host) == "Instance") and G.__R3ST_HOST or nil

local KIT_PATHS = { "../scripts/r3st_ui.lua", "r3st_ui.lua", "scripts/r3st_ui.lua" }

-- Standalone we resolve it ourselves. Explorer folder first: Potassium roots the
-- file API at workspace\, so a bare readfile reads the wrong folder (hub skill
-- S11).
local function loadKit()
	if HOST and type(HOST.ui) == "table" then
		return HOST.ui
	end
	for _, path in ipairs(KIT_PATHS) do
		local ok, src = pcall(readfile, path)
		if ok and type(src) == "string" and #src > 0 then
			local chunk = loadstring(src, "=r3st_ui.lua")
			if type(chunk) == "function" then
				local ran, kit = pcall(chunk)
				if ran and type(kit) == "table" then
					log("ui kit " .. tostring(kit.VERSION) .. " <- " .. path)
					return kit
				end
			end
		end
	end
	return nil
end

local UILive = {} -- refresh functions the kit registers; driven off Heartbeat
local lastRefresh = 0

local function refreshUI()
	for _, fn in ipairs(UILive) do
		pcall(fn)
	end
end

local function ensureGui()
	local Kit = loadKit()
	if not Kit then
		log("r3st_ui.lua not found in " .. table.concat(KIT_PATHS, " | ") .. " - panel not built")
		return function() end, function() end
	end
	COL = Kit.COL

	local parent
	if HOST then
		parent = HOST.host
	else
		local core = CoreGui
		if type(cloneref) == "function" then
			local ok, copy = pcall(cloneref, core)
			if ok and copy then
				core = copy
			end
		end
		local screen = Instance.new("ScreenGui")
		screen.Name = "R3ST_BLR_" .. tostring(math.random(1000, 9999))
		screen.ResetOnSpawn = false
		screen.IgnoreGuiInset = true
		screen.ZIndexBehavior = Enum.ZIndexBehavior.Global
		screen.DisplayOrder = 2147483647
		pcall(sethiddenproperty, screen, "OnTopOfCoreBlur", true)
		screen.Parent = core
		S.screen = screen
		parent = screen
	end

	local PANEL_W, PANEL_H = 720, 560
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Size = HOST and UDim2.fromScale(1, 1) or UDim2.fromOffset(PANEL_W, PANEL_H)
	panel.Position = HOST and UDim2.new() or UDim2.fromOffset(CFG.PanelX, CFG.PanelY)
	panel.BackgroundColor3 = COL.bg
	panel.BackgroundTransparency = HOST and 1 or 0
	panel.BorderSizePixel = 0
	panel.Active = true
	panel.ZIndex = 10
	panel.Visible = HOST and true or CFG.PanelVisible
	panel.Parent = parent
	if HOST then
		-- The hub already draws the window; a second border inside it is noise.
		-- S.screen is what destroy() tears down, so point it at the panel.
		S.screen = panel
	else
		Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 12)
		Instance.new("UIStroke", panel).Color = COL.line
	end

	-- FLUID, not scaled. Scaling one fixed-width layout into a wider host is what
	-- left a third of the hub tab empty: the cards must use the width, not shrink
	-- to keep a legacy aspect ratio. Everything below is sized in scale and the
	-- card grid re-flows (and gains a third column past 1000px) on every resize.
	local inner = Instance.new("Frame")
	inner.BackgroundTransparency = 1
	inner.BorderSizePixel = 0
	inner.Position = UDim2.fromOffset(HOST and 12 or 18, HOST and 8 or 14)
	inner.Size = UDim2.new(1, HOST and -24 or -36, 1, HOST and -16 or -28)
	inner.Parent = panel

	local W = Kit.bind({
		live = UILive,
		conns = S.conns,
		guard = function(what, fn, ...)
			local ok, err = pcall(fn, ...)
			if not ok then
				log("ERR " .. tostring(what) .. ": " .. tostring(err))
			end
			return ok
		end,
	})

	local TABS = { "Controls", "Settings" }
	local pages = {}
	local repaintTabs

	local function setTab(name)
		if not pages[name] then
			name = "Controls"
		end
		CFG.Tab = name
		for k, p in pairs(pages) do
			p.Visible = (k == name)
		end
		saveConfig()
		refreshUI()
	end

	W.header(inner, {
		title = "Blue Lock Rivals",
		version = "v" .. BUILD_VERSION,
		subtitle = "Client cooldowns, shot tuning and the CF locker. PlaceId " .. tostring(EXPECTED_PLACE) .. ".",
		gameId = 6325068386,
		placeId = EXPECTED_PLACE,
		onInfo = function()
			setTab("Settings")
			repaintTabs()
		end,
	})

	local strip
	strip, repaintTabs = W.tabstrip(inner, {
		names = TABS,
		position = UDim2.fromOffset(0, 80),
		get = function() return CFG.Tab end,
		set = setTab,
	})

	local BODY_Y = 122
	local function pageWidth()
		local w = inner.AbsoluteSize.X
		if w < 200 then
			w = PANEL_W - 36
		end
		return w - 10 -- scrollbar gutter
	end
	for _, name in ipairs(TABS) do
		local page = Instance.new("ScrollingFrame")
		page.Name = name
		page.BackgroundTransparency = 1
		page.BorderSizePixel = 0
		page.Position = UDim2.fromOffset(0, BODY_Y)
		page.Size = UDim2.new(1, 0, 1, -(BODY_Y + 52))
		page.ScrollBarThickness = 3
		page.ScrollBarImageColor3 = COL.line
		page.CanvasSize = UDim2.new()
		page.Visible = false
		page.Parent = inner
		pages[name] = page
		W.page(page, { width = pageWidth() })
	end

	local toggleButtons = {}
	local function toggle(page, key, text, desc, onChange)
		local o
		o = {
			label = text,
			desc = desc,
			get = function() return CFG[key] end,
			set = function(v)
				CFG[key] = v and true or false
				saveConfig()
				log(key .. "=" .. tostring(CFG[key]))
				if onChange then
					onChange(CFG[key])
				end
			end,
		}
		W.toggle(page, o)
		toggleButtons[key] = function()
			if o.redraw then o.redraw() end
		end
		return o
	end

	local function slider(page, key, text, opts)
		local o = {
			label = text,
			min = opts.min,
			max = opts.max,
			step = opts.step,
			tradeoff = opts.tradeoff,
			get = function() return tonumber(CFG[key]) or opts.min end,
			set = function(v) CFG[key] = v end,
			fmt = opts.fmt or function(v) return string.format("%.2f", v) end,
			commit = function()
				saveConfig()
				log(key .. "=" .. string.format("%.2f", tonumber(CFG[key]) or 0))
				if opts.commit then
					opts.commit()
				end
			end,
		}
		W.slider(page, o)
		-- The kit hands back its own redraw on the options table. Keeping it lets
		-- a style change move the knob, instead of changing CFG behind a slider
		-- that still shows the old number.
		if type(o.redraw) == "function" then
			S.sliderRedraw[key] = o.redraw
		end
		return o
	end

	--======================================================================
	-- Controls
	--======================================================================
	local controls = pages.Controls

	W.section(controls, "Main")
	toggle(controls, "CFLocker", "CF Locker", "Claims CF the moment a match ends", function(on)
		if on and LOCK_STATES[gameState() or ""] then
			-- Armed inside the window it waits for: claim now rather than making
			-- the user sit out a whole match.
			runLockAttempt("toggled on during " .. tostring(gameState()))
		end
	end)
	toggle(controls, "CFFallbackWhite", "White CF fallback", "Only after blue CF is taken; blue always wins")
	W.statusRow(controls, function()
		local blue = cfSeat(LOCK_TEAM)
		local white = cfSeat(FALLBACK_TEAM)
		local function who(seat)
			if not seat then return "?" end
			if seat.Value == LP then return "YOU" end
			return seat.Value and tostring(seat.Value) or "free"
		end
		return ("state %s  ·  blue CF %s  ·  white CF %s"):format(
			tostring(gameState()), who(blue), who(white))
	end)

	W.section(controls, "Shooting")
	W.statusRow(controls, function()
		local style = S.style or currentStyle()
		local saved = 0
		if type(CFG.Styles) == "table" then
			for _ in pairs(CFG.Styles) do
				saved = saved + 1
			end
		end
		return ("style %s · powers and arcs below are saved per style (%d stored)"):format(tostring(style), saved)
	end)
	toggle(controls, "ShotPower", "Shot power", "StatesController.ShotPowerMultiplier on normal shots")
	slider(controls, "ShotPowerMult", "Shot power multiplier", {
		min = 1.0, max = 2.0, step = 0.05,
		tradeoff = "Scales the whole kick. Above ~1.3 the ball outruns every keeper and reads as fake.",
		fmt = function(v) return string.format("x%.2f", v) end,
	})
	toggle(controls, "HeaderPower", "Header power", "Flatter, faster headers only (0870:1303)")
	slider(controls, "HeaderPowerMult", "Header speed", {
		min = 1.0, max = 2.0, step = 0.05,
		tradeoff = "Horizontal speed only. Past ~1.3 the ball beats every keeper and reads as fake.",
		fmt = function(v) return string.format("x%.2f", v) end,
	})
	slider(controls, "HeaderArcTrim", "Header arc trim", {
		min = 0.4, max = 1.0, step = 0.05,
		tradeoff = "Lower = flatter and it drops sooner. Too low and the header buries into the turf.",
		fmt = function(v) return string.format("%.0f%% arc", v * 100) end,
	})
	toggle(controls, "AbilityPower", "Ability shot power", "AbilityBalancing ShotPower / ShotPowerMax", function(on)
		applyAbilityBalancing(on)
	end)
	slider(controls, "AbilityPowerMult", "Ability power multiplier", {
		min = 1.0, max = 2.0, step = 0.05,
		tradeoff = "Range and speed for Kaiser Impact, Loki, Magnus and every other ability shot.",
		fmt = function(v) return string.format("x%.2f", v) end,
		commit = function()
			if CFG.AbilityPower then
				applyAbilityBalancing(true)
			end
		end,
	})
	slider(controls, "AbilityArcTrim", "Ability arc trim", {
		min = 0.4, max = 1.0, step = 0.05,
		tradeoff = "Lower = flatter. Power alone also raises the loft, and that is the shot that floats.",
		fmt = function(v) return string.format("%.0f%% arc", v * 100) end,
		commit = function()
			if CFG.AbilityPower then
				applyAbilityBalancing(true)
			end
		end,
	})
	W.note(controls, "Ability velocity is (LookVector + ShotTiltVector) * ShotPower (0547:210). Raise power, trim the arc, and the extra speed becomes midfield range instead of hang time.")

	W.section(controls, "Dribbling")
	toggle(controls, "TapGuard", "Tap guard", "Stops a spam-click turning into a charged shot")
	slider(controls, "TapWindowMs", "Tap window", {
		min = 100, max = 400, step = 10,
		tradeoff = "Clicks shorter than this are treated as a dribble touch. Longer holds charge normally.",
		fmt = function(v) return string.format("%.0f ms", v) end,
	})
	slider(controls, "TapPower", "Touch power", {
		min = 50, max = 90, step = 1,
		tradeoff = "Charge floor is 50 and a full charge is 110. Lower keeps the ball at your feet.",
		fmt = function(v) return string.format("%.0f", v) end,
	})
	toggle(controls, "VolleyGuard", "No accidental volley", "Ignores a click fired during a dribble's no-ball gap")
	slider(controls, "VolleyGapMs", "Dribble gap window", {
		min = 200, max = 1200, step = 50,
		tradeoff = "How long after losing the ball a click still counts as dribbling. Higher blocks more real volleys.",
		fmt = function(v) return string.format("%.0f ms", v) end,
	})
	W.note(controls, "0870:341: a charge STARTED without the ball, that then gains the ball, is forced to power 110 and fired as a Volley instantly -- no hold needed. HasBall drops for a few frames on every dribble touch, so a spam-click in that gap volleys your own dribble downfield.")
	W.note(controls, "Holding left click for ~1.11s auto-fires the shot (0870:365, u6 >= 50), and a mouse-up over ANY GUI is swallowed by the gameProcessed check at 0870:1004 -- including this panel -- so the charge keeps running. The guard releases on the physical button instead.")

	W.section(controls, "Cooldowns")
	toggle(controls, "NoDribbleCD", "No dribble CD", "Clears the BallController dribble gate")
	toggle(controls, "DribbleCDClaim", "Dribble CD claim (test)", "Sends a smaller cooldown to the server in Dribble:Fire")
	slider(controls, "DribbleCDClaimSeconds", "Claimed dribble CD", {
		min = 0.25, max = 3.0, step = 0.25,
		tradeoff = "Only used when it is SMALLER than the cooldown the game just computed. The game's own floor is 1.0s, so below that is a number no legitimate client sends.",
		fmt = function(v) return string.format("%.2f s", v) end,
	})
	W.note(controls, "0870:647 sends the client's own dribble cooldown to the server, and 0430:58 shows the server broadcasting a duration back. If they match, the server trusts the client's number and this shortens the SERVER gate -- which is the gate that decides whether a dribble registers at all. UNPROVEN: turn it on, dribble a few times, then read blr_hub.log for the `claim` and `echo` lines and see whether they agree.")
	toggle(controls, "NoSlideCD", "No slide / steal CD", "Clears the slide gate")
	toggle(controls, "NoAbilityCD", "No ability CD", "Cast slot held 2.5s so a re-press cannot freeze you", function(on)
		if on then
			pinAbilitySlots()
		end
	end)
	W.note(controls, "These three raise the rate of a real server call. They are named in the boot log every inject.")

	W.section(controls, "Player")
	toggle(controls, "InfiniteStamina", "Infinite stamina", "Local pin; the drain remote is suppressed")
	W.statusRow(controls, function()
		local stats = LP:FindFirstChild("PlayerStats")
		local stamina = stats and stats:FindFirstChild("Stamina")
		return "stamina " .. (stamina and string.format("%.0f", stamina.Value) or "?")
	end)

	--======================================================================
	-- Settings
	--======================================================================
	local settings = pages.Settings

	W.section(settings, "Panel")
	W.button(settings, "Reset panel position", "Standalone only; the hub owns the window when embedded.", function()
		CFG.PanelX, CFG.PanelY = 24, 160
		clampPanel()
		if not HOST then
			panel.Position = UDim2.fromOffset(CFG.PanelX, CFG.PanelY)
		end
		saveConfig()
	end)
	W.note(settings, "RightShift panel  ·  P panic  ·  K unload. Every toggle autosaves and resumes on the next inject.")

	W.section(settings, "Safety")
	W.statusRow(settings, function()
		local armed = {}
		for k in pairs(FIRES_REMOTE) do
			if CFG[k] then
				armed[#armed + 1] = k
			end
		end
		table.sort(armed)
		return "fires a real remote right now: " .. (#armed > 0 and table.concat(armed, ", ") or "none")
	end)

	W.section(settings, "About")
	W.note(settings, "build " .. BUILD_VERSION .. "\nplace " .. tostring(game.PlaceId) .. "\nconfig " .. CONFIG_FILE .. "\nlog " .. LOG_FILE)
	W.note(settings, "Rung 3/4: local module state and one suppressed local Fire. The CF locker is rung 6 -- it fires TeamService.Select, the same call the game's own team button makes.")

	-- Re-flow on every width change: docked in the hub, resized, or standalone.
	local function relayoutAll()
		local w = pageWidth()
		for _, name in ipairs(TABS) do
			local h = W.relayout(pages[name], w)
			pages[name].CanvasSize = UDim2.fromOffset(0, h + 12)
		end
	end
	for _, name in ipairs(TABS) do
		pages[name].CanvasSize = UDim2.fromOffset(0, W.height(pages[name]) + 12)
	end
	connect(inner:GetPropertyChangedSignal("AbsoluteSize"), relayoutAll)
	-- AbsoluteSize is 0 until the frame has been laid out once, so the first
	-- real width arrives a frame later, not now.
	task.defer(relayoutAll)

	--======================================================================
	-- Chrome
	--======================================================================
	local panic, destroy -- forward: the footer binds them before they exist

	W.footer(inner, {
		onUnload = function() destroy() end,
		onSettings = function()
			setTab("Settings")
			repaintTabs()
		end,
		hint = "P panic  ·  K unload  ·  RightShift panel",
	})

	-- Standalone drag: an invisible strip over the header. Embedded, the hub
	-- drags its own window and we must not add a second handler.
	if not HOST then
		local grip = Instance.new("TextButton")
		grip.BackgroundTransparency = 1
		grip.Text = ""
		grip.AutoButtonColor = false
		grip.Size = UDim2.new(1, 0, 0, 76)
		grip.ZIndex = 0
		grip.Parent = inner
		local dragging, dragStart, panelStart
		connect(grip.InputBegan, function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				dragging = true
				dragStart = input.Position
				panelStart = panel.Position
			end
		end)
		connect(UserInputService.InputChanged, function(input)
			if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
				local delta = input.Position - dragStart
				panel.Position = UDim2.fromOffset(panelStart.X.Offset + delta.X, panelStart.Y.Offset + delta.Y)
			end
		end)
		connect(UserInputService.InputEnded, function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 and dragging then
				dragging = false
				CFG.PanelX = panel.Position.X.Offset
				CFG.PanelY = panel.Position.Y.Offset
				-- Clamp before saving, so a drag off the edge cannot persist a
				-- position the panel can never be reached at again.
				clampPanel()
				panel.Position = UDim2.fromOffset(CFG.PanelX, CFG.PanelY)
				saveConfig()
			end
		end)
	end

	-- persist=true only when the USER hit panic. destroy() disarms with
	-- persist=false: an unload must not overwrite the saved toggles with all-OFF,
	-- or every re-inject comes back blank and autosave looks broken.
	panic = function(persist)
		CFG.NoDribbleCD = false
		CFG.DribbleCDClaim = false
		CFG.NoSlideCD = false
		CFG.NoAbilityCD = false
		CFG.ShotPower = false
		CFG.InfiniteStamina = false
		CFG.TapGuard = false
		CFG.VolleyGuard = false
		CFG.CFLocker = false
		if CFG.AbilityPower then
			CFG.AbilityPower = false
			applyAbilityBalancing(false)
		end
		for _, render in pairs(toggleButtons) do
			pcall(render)
		end
		if persist then
			saveConfig()
		end
		log("panic persist=" .. tostring(persist and true or false))
	end

	destroy = function()
		if not S.alive then
			return
		end
		S.alive = false
		panic(false)
		if S.ball then
			restoreBallAction(S.ball, "Dribble", S.origDribble)
			restoreBallAction(S.ball, "Slide", S.origSlide)
			restoreBallAction(S.ball, "Shoot", S.origShoot)
		end
		unhookDribbleFire()
		unhookAbilityCooldown()
		unhookStamina()
		applyAbilityBalancing(false)
		for _, c in ipairs(S.conns) do
			pcall(function()
				c:Disconnect()
			end)
		end
		if S.screen then
			S.screen:Destroy()
		end
		if G[GKEY] and G[GKEY].destroy == destroy then
			G[GKEY] = nil
		end
		log("unloaded build=" .. BUILD_VERSION)
	end

	G[GKEY] = { destroy = destroy, build = BUILD_VERSION, cfg = CFG }

	-- Tap guard input pair. These deliberately run BEFORE the `processed` bail
	-- below: a mouse-up the game refuses to look at (0870:1004) is exactly the
	-- one that strands a charge, so our copy must not apply the same filter.
	connect(UserInputService.InputBegan, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			S.holdStart = os.clock()
		end
	end)
	connect(UserInputService.InputEnded, function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		if S.alive and CFG.TapGuard then
			releaseCharge("button up")
		end
	end)

	connect(UserInputService.InputBegan, function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.K then
			destroy()
			return
		end
		if input.KeyCode == Enum.KeyCode.P then
			panic(true)
			return
		end
		if input.KeyCode == Enum.KeyCode.RightShift then
			if HOST then
				-- The hub hides its own ScreenGui on RightShift; hiding the
				-- panel too would leave it hidden when the hub comes back.
				return
			end
			CFG.PanelVisible = not CFG.PanelVisible
			if CFG.PanelVisible then
				-- Showing it always re-clamps: if the viewport changed or the
				-- saved spot is off-screen, RShift is the way back.
				clampPanel()
				panel.Position = UDim2.fromOffset(CFG.PanelX, CFG.PanelY)
			end
			panel.Visible = CFG.PanelVisible
			saveConfig()
			log("panel visible=" .. tostring(CFG.PanelVisible) .. " at " .. CFG.PanelX .. "," .. CFG.PanelY)
		end
	end)

	setTab(CFG.Tab)
	repaintTabs()
	return panic, destroy
end

local function correctExperience()
	if game.GameId == EXPECTED_GAME then
		return true
	end
	return game.PlaceId == EXPECTED_PLACE
end

if not correctExperience() then
	log(("blocked: wrong experience place=%s universe=%s (want place %s / universe %s)")
		:format(tostring(game.PlaceId), tostring(game.GameId), tostring(EXPECTED_PLACE), tostring(EXPECTED_GAME)))
	return function() end
end
if game.PlaceId ~= EXPECTED_PLACE then
	log(("private/alternate place %s inside universe %s - identity accepted on GameId")
		:format(tostring(game.PlaceId), tostring(game.GameId)))
end

local _, destroy = ensureGui()
resolveControllers()
-- After the GUI, never before: the profile swap redraws sliders, and a slider
-- that does not exist yet cannot be redrawn.
watchStyle()

-- ShotPower and InfiniteStamina are polled by the Heartbeat below, so a resumed
-- ON needs nothing extra. AbilityPower is a one-shot table mutation, so a
-- resumed ON has to be applied here or the panel would lie about it.
if CFG.AbilityPower then
	applyAbilityBalancing(true)
end

-- One Heartbeat, connected AFTER the game's. StatesController resets
-- ShotPowerMultiplier to 1 at the top of its own Heartbeat (1138:129 -> :244)
-- and may raise it to 1.2/1.3 later in the same callback (1138:313,346).
-- Connecting later means we run after that callback in the same frame, so the
-- amplified value survives the whole next frame -- including the input handler
-- that reads it at 0870:1284. A BindToRenderStep would be clobbered by the
-- Heartbeat that follows it.
connect(RunService.Heartbeat, function()
	if not S.alive then
		return
	end
	if CFG.NoAbilityCD then
		resolveCast()
		pinAbilitySlots()
		clearStuckAbility()
	end
	if CFG.InfiniteStamina then
		pinStaminaValue()
	end
	if CFG.TapGuard then
		tapGuard()
	end
	if CFG.VolleyGuard then
		inDribbleGap() -- keeps S.lastHadBall fresh even between clicks
	end
	if CFG.ShotPower and S.states and type(S.states.ShotPowerMultiplier) == "number" then
		local mult = tonumber(CFG.ShotPowerMult) or 1.20
		-- max(x,1) keeps the game's own 1.2/1.3 buffs and stops compounding.
		S.states.ShotPowerMultiplier = math.max(S.states.ShotPowerMultiplier, 1) * mult
	end
	-- Panel refresh at ~8 Hz, not per frame: the readouts are status text, and a
	-- 60 Hz redraw of a dozen labels is cost for nothing (potassium-dev 5.4).
	local now = os.clock()
	if now - lastRefresh >= 0.12 then
		lastRefresh = now
		refreshUI()
	end
end)

log("boot build=" .. BUILD_VERSION .. " place=" .. tostring(game.PlaceId))
do
	-- script-scaffold 3: the resumed state must be impossible to miss.
	local resumed = {}
	for _, k in ipairs({
		"NoDribbleCD",
		"DribbleCDClaim",
		"NoSlideCD",
		"NoAbilityCD",
		"ShotPower",
		"HeaderPower",
		"AbilityPower",
		"InfiniteStamina",
		"TapGuard",
		"VolleyGuard",
		"CFLocker",
	}) do
		if CFG[k] then
			resumed[#resumed + 1] = k
		end
	end
	log("resumed: " .. (#resumed > 0 and table.concat(resumed, " ") or "nothing"))
	log("ARMED, fires a real remote: " .. (#armedRemoteNames > 0 and table.concat(armedRemoteNames, " ") or "none"))
	log("panel visible=" .. tostring(CFG.PanelVisible) .. " at " .. CFG.PanelX .. "," .. CFG.PanelY .. " (RightShift toggles)")
end

return destroy
