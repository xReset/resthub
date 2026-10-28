--------------------------------------------------------------------------
-- bloxstrike_esp.lua -- BloxStrike ESP + soft aim, drawn with the R3ST kit.
-- PlaceId 114234929420007  universe 7633926880  ([TRADEUPS] BloxStrike)
--
-- POSTURE (potassium-dev S5.6)
--   Rung 1-2 only. Every instance this creates is client-spawned and lives
--   under gethui(); nothing is parented into a character, no remote is fired,
--   no game module is required or hooked.
--   Server sees: nothing from the ESP. Soft aim fires no remote of its own --
--   it moves the mouse, so the only thing that reaches the server is the
--   Direction on a shot the player themselves took (0119.lua:1268 sends
--   `Direction = CurrentCamera.CFrame.LookVector`).
--
-- WHY mousemoverel AND NOT a CurrentCamera write (this is the whole design):
--   0124.lua CameraController.updateCamera reads the camera position, writes
--   its own CFrame, and if the position moved >= 0.5 studs it spams every
--   ReplicatedStorage RemoteEvent with junk, calls LocalPlayer:Remove() and
--   Kick("Skibidi Toilet?") -- 0124.lua:415-429. mousemoverel feeds the game's
--   own camera input instead: position never changes, the game's internal
--   angles genuinely update, and there is no snap-back when the aim releases.
--
-- THE 2026-08-09 DUMP IS STALE ON THE RIG LAYOUT. Live probe 2026-09-02
-- (logs/bx_probe.txt, logs/bx_probe2.txt) vs what characters.txt claims:
--   dump says                          live says
--   Workspace.Characters.<Team>.<Name>  Workspace.Characters.<Name>, flat --
--                                       the team folders exist and are EMPTY
--   Humanoid.Health                     NO Humanoid at all; model @Health /
--                                       @MaxHealth, AnimationController in its
--                                       place
--   (nothing)                           liveness is the model's @Dead; a dead
--                                       rig moves to Workspace.Debris and
--                                       Player.Character goes nil
-- Requiring a Humanoid is what made chams draw nothing: every rig failed the
-- target test silently. Re-dump this game before the next behaviour change.
--
-- Facts that DID hold:
--   * Teams service is EMPTY (teams.txt) -- team is the Player @Team attribute,
--     "Counter-Terrorists" / "Terrorists" (players.txt:18).
--   * R15 aim parts Head / UpperTorso / HumanoidRootPart, all present live.
--   * The game parents its own Highlight (named "Highlight", Enabled=false)
--     under some rigs. Never mutate it; ours lives in our own gethui folder.
--   * 0943.lua:224-228 and 0181.lua:225-231 walk the CALL STACK with getfenv
--     and blank their return if any caller env has getgenv/hookfunction. We
--     never call a game module, so we never enter those stacks.
--   * 0001.lua kicks on a hitbox-size probe -- we add no BasePart to any
--     character, ever. Highlight uses Adornee only, never reparenting.
--   * anticheat_profile.txt lists no Highlight/Billboard scanner and no
--     LogService.GetLogHistory reader; we still log to file only.
--------------------------------------------------------------------------

-- 2026-09-03 DUMP (2026-09-02T09-37-37Z) replaces the stale 2026-08-09 one and
-- confirms the live layout above. The game's OWN enemy test is now copied
-- exactly instead of approximated:
--   0073.lua:161 isPlayerCharacter  -> @CharacterType == "PlayerCustomCharacter"
--                                      AND FindFirstChild("HumanoidRootPart")
--   0073.lua:177 isAliveCharacter   -> IsDescendantOf(workspace) and @Dead==false
--                                      and @Health > 0
--   0125.lua:148 isEnemyValid       -> both @Team in {Terrorists,
--                                      Counter-Terrorists}; Deathmatch => all
--                                      enemies; otherwise teams differ
-- Why some rigs had no cham (all three are in the 2026-09-02 dump):
--   * A rig whose Player has no @Team yet -- joining, switching, spectating --
--     failed `not lt or not pt` and was dropped for good. The map config gives
--     each team a distinct rig model (0351.lua:18 Characters = {CT="IDF",
--     T="Anarchist"}), so @CharacterName differing from OUR rig's is a second,
--     map-independent enemy signal. Fail open on team, never closed.
--   * `__PreparedRagdoll_<name>` corpses sit in Workspace.Characters with
--     @Health=100 and @Dead=false (tree lines 5213+). They are not the live rig
--     and are excluded by @ClientRagdoll / @PreparedRagdoll.
--   * Chams were culled at `maxDist` (500) with the healthbars. A cham has no
--     screen cost at range; only the billboard does. maxDist is a healthbar
--     setting now.
-- Chams are also opaque and win outright: 8 of 9 rigs carry the game's own
-- Highlight (0043.lua CharacterHighlight, `Instance.new("Highlight", char)`),
-- and two Highlights on one adornee is undefined in Roblox -- ours is the one
-- that can lose. We disable theirs while ours is up and restore it on unload.
-- A client property write on a replicated instance does not replicate (rung 3).
-- 2026-09-03.2 -- why some players never drew at all. Evidence, not theory:
-- logs/bx_mismatch.txt ends with `player list not in Characters: shalavav9
-- team=nil charParent=Workspace` -- an alive, on-screen player whose rig is
-- parented to Workspace ROOT, not Workspace.Characters. The sweep only walked
-- the folder, so that player had no cham, no bar and could not be aimed at, for
-- the whole round. A mid-round joiner lands there before the game reparents it.
-- Three closed gates stacked on the same player, all now opened:
--   * the rig source is Players:GetPlayers().Character UNIONED with the folder
--     walk, deduped by model -- whichever finds them first wins;
--   * `isEnemy` failed CLOSED on an unknown @Team (`not lt or not pt` ->
--     false) while its own comment claimed it failed open. The first player on
--     a team nobody else occupies yet has no @Team and no CharacterName map
--     entry, so they were dropped. Unknown team is now an enemy;
--   * `@CharacterType == "PlayerCustomCharacter"` is a publish-order race on a
--     fresh model, and irrelevant for a rig we reached through a Player
--     object. It is skipped for player-sourced rigs and allowed to be nil.
-- Cost of failing open: a teammate may be outlined for the sweep or two before
-- @Team replicates. potassium-dev S5.4b -- widen the net, never narrow one.
local BUILD_VERSION = "2026-09-09.1"
local GKEY = "__BX_ESP"
local EXPECTED_PLACE = 114234929420007
local EXPECTED_GAME = 7633926880
if game.GameId ~= EXPECTED_GAME and game.PlaceId ~= EXPECTED_PLACE then return end

local G = (getgenv and getgenv()) or _G
if type(G) ~= "table" then G = _G end
if type(G[GKEY]) == "table" and type(G[GKEY].destroy) == "function" then
	pcall(G[GKEY].destroy)
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")
if type(cloneref) == "function" then
	local ok, copy = pcall(cloneref, CoreGui)
	if ok then CoreGui = copy end
end

local LP = Players.LocalPlayer
local RNG = Random.new()
local HOST = type(G.__R3ST_HOST) == "table" and G.__R3ST_HOST or nil
local CONFIG_FILE = "bloxstrike_esp_config.json"

local function fallbackLog(message)
	pcall(function()
		local path = "logs/bloxstrike_esp.log"
		local old = (isfile and isfile(path) and readfile(path)) or ""
		writefile(path, old .. os.date("[%Y-%m-%d %H:%M:%S] ") .. tostring(message) .. "\n")
	end)
end
local Log = { info = fallbackLog }
-- print = false is NOT cosmetic. log.lua defaults alsoPrint = true, so every
-- line also costs a print()/warn() -- a LogService entry and a console redraw
-- on the main thread. At the rate the soft-aim note used to write, that alone
-- visibly dropped the user's FPS. It is also the AGENTS.md rule: print/warn
-- reach LogService.MessageOut, which the game can read.
pcall(function() Log = loadfile("log.lua")()("bloxstrike_esp", { print = false }) end)

--------------------------------------------------------------------------
-- config
--------------------------------------------------------------------------

local defaults = {
	chams = true,
	healthbars = true,
	names = true,
	nameDist = true,
	espHz = 0.28,
	maxDist = 500,

	-- skins page
	wear = "Factory New",
	showAll = false,
	statTrak = false,
	preset = "Best",        -- the preset loaded on inject
	autoPreset = true,      -- reload it every inject / spawn

	softAim = false,
	aimFov = 8,
	aimStrength = 45,
	aimMaxStepPx = 22,
	aimPart = "Closest",   -- Closest | Head | Body
	aimWallCheck = true,
	aimRmbOnly = true,
	showAimFov = true,
}
local cfg = table.clone(defaults)
-- picks is a nested table, so it cannot ride the typeof() whitelist above.
cfg.picks = {}     -- the LIVE set: ["AK-47"] = { skin = } ; ["#melee"] = { name =, skin = }
cfg.presets = {}   -- name -> { wear = , picks = { ...same shape... } }
do
	local ok, raw = pcall(readfile, CONFIG_FILE)
	if ok then
		local ok2, saved = pcall(HttpService.JSONDecode, HttpService, raw)
		if ok2 and type(saved) == "table" then
			for key, fallback in next, defaults do
				if typeof(saved[key]) == typeof(fallback) then cfg[key] = saved[key] end
			end
			if type(saved.picks) == "table" then cfg.picks = saved.picks end
			if type(saved.presets) == "table" then cfg.presets = saved.presets end
		end
	end
end
if cfg.aimPart ~= "Closest" and cfg.aimPart ~= "Head" and cfg.aimPart ~= "Body" then
	cfg.aimPart = "Closest"
end

local savePending = false
local function saveConfig()
	if savePending then return end
	savePending = true
	task.delay(0.5, function()
		savePending = false
		local ok, raw = pcall(HttpService.JSONEncode, HttpService, cfg)
		if ok then pcall(writefile, CONFIG_FILE, raw) end
	end)
end

--------------------------------------------------------------------------
-- state
--------------------------------------------------------------------------

local S = {
	alive = true,
	conns = {},
	live = {},
	esp = {},          -- char -> { hl, bb, fill, conn }
	rivals = {},       -- the game's own Highlight -> its original Enabled
	folder = nil,
	folderName = nil,
	fovDraw = nil,
	stickyChar = nil,
	stickyUntil = 0,
	skips = {},        -- player-backed rigs this sweep refused, with the reason
	hlTotal = 0,       -- Highlights alive in Workspace; 31 is the render ceiling
	blindAt = nil,     -- when every alive rig started looking friendly
	blindLogAt = 0,
	missedLogAt = 0,
	schema = nil,      -- decoded AvaiableSkins catalog: [weapon][skin] = info
	originals = {},    -- item._id -> the four fields before we touched them
	applied = 0,
	page = "ESP",
	cat = "Knives",
	weapon = nil,
	sel = nil,
	skinNote = "idle",
	aimNote = "idle",
	aimNoteKey = nil,
	aimNoteAt = 0,
	targets = 0,
	moves = 0,
}

local COL = {
	-- Aggressive: a solid body fill and a hard white edge, readable through a
	-- wall at any range. Client-local render state -- nothing here replicates.
	enemyFill = Color3.fromRGB(255, 40, 40),
	enemyOut = Color3.fromRGB(255, 255, 255),
	hpHi = Color3.fromRGB(70, 210, 90),
	hpLo = Color3.fromRGB(210, 60, 60),
	nameText = Color3.fromRGB(255, 255, 255),
}
local CHAM_FILL_T = 0.15   -- near-solid; 0.65 was a tint you could lose in a wall
local CHAM_OUT_T = 0

local function connect(signal, fn)
	local c = signal:Connect(fn)
	S.conns[#S.conns + 1] = c
	return c
end

local function blandName(prefix)
	return prefix .. string.format("%04x", RNG:NextInteger(0, 65535))
end

-- THE CHAMS BUG, 2026-09-03.24. This used to return `gethui()`, and under
-- Potassium `gethui()` is Roblox's **RobloxGui, which is a ScreenGui**
-- (potassium-dev S5.4 says so, and the live probe confirmed
-- `parent=CoreGui.RobloxGui.UI5118`). A Highlight inside a ScreenGui does not
-- render. A BillboardGui inside one does -- which is exactly why the name tags
-- appeared over players who had no outline, from the same folder, on the same
-- adornee, with `Enabled = true` and the right `Adornee` on every probe.
--
-- Proven, not reasoned: three controls on one live enemy rig, 2026-09-03 --
-- a Highlight parented to Workspace (green), a Highlight parented into the rig
-- (blue) and a BoxHandleAdornment (magenta) ALL rendered, while ours in the
-- gethui() folder rendered nothing. The instance was never the problem; its
-- parent was.
--
-- So: the cloned CoreGui, which is where a dedicated HUD layer belongs
-- (potassium-dev S5.4, "beside it under cloned CoreGui"). Nothing is parented
-- into a rig -- 0001.lua kicks on a hitbox-size probe -- and this costs no
-- detection surface here: both CLIENT INSPECTION hits in anticheat_deep.txt are
-- Shared.Raycast caller-env tests (1047:408, 1047:513), not CoreGui walks.
local function espParent()
	return CoreGui
end

local function ensureFolder()
	if S.folder and S.folder.Parent then return S.folder end
	local parent = espParent()
	if S.folderName then
		local old = parent:FindFirstChild(S.folderName)
		if old then old:Destroy() end
	end
	S.folderName = blandName("UI")
	local f = Instance.new("Folder")
	f.Name = S.folderName
	f.Parent = parent
	S.folder = f
	return f
end

--------------------------------------------------------------------------
-- targeting -- shared by ESP and soft aim
--------------------------------------------------------------------------

local function myTeam()
	return LP:GetAttribute("Team")
end

-- LIVE-VERIFIED 2026-09-02, and it contradicts the 2026-08-09 dump on both
-- points that matter (logs/bx_probe.txt, logs/bx_probe2.txt):
--   * There is NO Humanoid on a player rig any more -- an AnticheatController
--     sits there instead, and health is `@Health` / `@MaxHealth` ON THE MODEL.
--     characters.txt still claims `hp=100 (Humanoid.Health)`; that is stale, and
--     requiring a Humanoid is what made every rig fail this test and drew
--     nothing at all.
--   * Liveness is the model's own `@Dead` boolean.
local function healthOf(char)
	local hp = char:GetAttribute("Health")
	local max = char:GetAttribute("MaxHealth")
	if type(hp) ~= "number" or type(max) ~= "number" or max <= 0 then return nil end
	return hp, max
end

-- 0073.lua:161 isPlayerCharacter, minus the ragdoll corpses that share every
-- attribute with a live rig. Debris and the __PreparedRagdoll_ clones are the
-- only Models in Characters that are not somebody's body.
-- `trusted` means we reached this model through a Player object, so it IS
-- somebody's body by definition and the CharacterType test only adds a race.
-- Returns false plus the REASON, so a rig this drops can be named in the log
-- instead of vanishing silently. Every "some people don't appear" report so far
-- has been one of these gates firing with nothing written down.
local function isLiveRig(char, trusted)
	if not char:IsA("Model") or not char.Parent then return false, "not a parented Model" end
	local ct = char:GetAttribute("CharacterType")
	-- nil = the model has not published its attributes yet (fresh spawn).
	if not trusted and ct ~= nil and ct ~= "PlayerCustomCharacter" then
		return false, "CharacterType=" .. tostring(ct)
	end
	if char:GetAttribute("ClientRagdoll") or char:GetAttribute("PreparedRagdoll") then
		return false, "ragdoll attribute"
	end
	if string.sub(char.Name, 1, 2) == "__" then return false, "__ corpse clone" end
	-- A HumanoidRootPart is the game's own test (0073.lua:161), but a rig that is
	-- still assembling has a Head first. Requiring HRP alone is a blind spot the
	-- 2026-09-03 telemetry pass shared with this function, so either part counts
	-- and the Highlight adorns the MODEL regardless (potassium-dev S5.4b).
	if char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Head") then
		return true
	end
	return false, "no HumanoidRootPart and no Head"
end

-- 0073.lua:177, widened by one step: the game requires @Dead == false, we only
-- reject @Dead == true. A rig that has not published the attribute yet is drawn
-- rather than dropped (potassium-dev S5.4b -- widen the net, never narrow one).
local function isAlive(char)
	if char:GetAttribute("Dead") == true then return false end
	local hp = healthOf(char)
	return hp == nil or hp > 0
end

-- 0125.lua:148 isEnemyValid, with the fallback that fixes the missing chams.
-- The @Team attribute answers first, because it is what the game itself trusts.
-- When a rig's player has no team yet -- joining, switching, spectating -- the
-- rig MODEL answers instead: the map config hands each team one @CharacterName
-- (0351.lua:18), so a name seen on a known-team rig identifies the team of every
-- other rig wearing it. `model` is that map, rebuilt per sweep from the rigs that
-- do have a team, which costs nothing and needs no per-map table.
-- 0125.lua:148 isEnemyValid, plus the two corrections a live session forced.
--
-- @Team ALONE IS NOT TRUSTWORTHY ACROSS A SIDE SWAP. Measured 2026-09-03: at
-- 15:18 Pricyscarf read @Team=Terrorists; at 15:19, after the halftime swap,
-- the same player read Counter-Terrorists -- as did every other alive rig AND
-- us. For that window every enemy classifies as a teammate and the ESP draws
-- nothing at all, while every per-rig diagnostic still reports correct values.
-- That is the "someone got through without chams" report, and no per-rig audit
-- can catch it because no per-rig fact is wrong.
--
-- So the RIG MODEL answers first where it can. The map config gives each side a
-- distinct model (0351.lua:18 Characters = {CT="IDF", T="Anarchist"}), and that
-- is replicated on the rig itself as @CharacterName, so it cannot skew relative
-- to a Player attribute the way two attributes can skew relative to each other.
--
-- 2026-09-03.23 -- THE INVERSION HOLE. `ourModel` used to fall back to "the
-- @CharacterName of any rig whose player shares our @Team" whenever our own rig
-- did not publish one -- which is exactly the window where @Team is skewed
-- (halftime swap, or our own rig gone while we are dead: LP.Character is nil,
-- so ourModel is nil EVERY time we die). Pick a rig off a skewed @Team and
-- ourModel becomes the ENEMY's model: every enemy then reads cn == ourModel, is
-- classified a friend, `reliable` comes back TRUE, the TEAM DATA BLIND failsafe
-- is suppressed, and the ESP silently outlines our own team instead. No per-rig
-- diagnostic is wrong in that state and no log line fires -- the exact shape of
-- "the chams do not apply to everyone".
--
-- A verdict is now only `reliable` when ourModel came from OUR OWN rig AND our
-- rig's model agrees with our @Team. Anything derived from another rig's @Team
-- is a guess, is labelled a guess, and lets the failsafe draw every body.
local function isEnemy(plr, char, model, ourModel, ourModelTrusted)
	if Workspace:GetAttribute("Gamemode") == "Deathmatch" then return true end

	local cn = char:GetAttribute("CharacterName")
	if ourModel and ourModel ~= "" and type(cn) == "string" and cn ~= "" then
		-- second return: reliable ONLY if we know which model is ours first-hand
		return cn ~= ourModel, ourModelTrusted == true
	end

	local lt = myTeam()
	local pt = plr and plr:GetAttribute("Team")
	if not pt then
		pt = cn and model[cn] or nil
	end
	-- Fail OPEN: a rig whose side we cannot name is drawn, never dropped.
	if not lt or not pt then return true, false end
	return lt ~= pt, false
end

-- Rigs are FLAT children of Workspace.Characters. The Terrorists /
-- Counter-Terrorists / Hostages subfolders the dump describes still exist but
-- are empty (children=0), and a dead player's model is moved to
-- Workspace.Debris -- so the Characters folder is itself the liveness filter.
-- Walking the folder beats Players:GetPlayers(), because Player.Character goes
-- nil the moment someone dies while their rig is still on screen.
local function enemyRigs()
	local out = {}
	local root = Workspace:FindFirstChild("Characters")

	-- Pass 1 collects every live rig and learns the CharacterName -> team map
	-- from the rigs whose player already carries a @Team.
	local rigs, model, seen = {}, {}, {}
	table.clear(S.skips)
	local function take(char, trusted, known)
		if not char or seen[char] then return end
		if char == LP.Character then return end
		local live, why = isLiveRig(char, trusted)
		if not live or not isAlive(char) then
			-- Only worth a line if a real Player is behind it. A map prop failing
			-- these gates is the gate working; a PLAYER failing them is the bug
			-- class this whole file keeps re-learning.
			local p = known or Players:GetPlayerFromCharacter(char) or Players:FindFirstChild(char.Name)
			if p and p ~= LP then
				S.skips[#S.skips + 1] = string.format("%s(%s)", char.Name,
					why or ("dead=" .. tostring(char:GetAttribute("Dead")) .. " hp=" .. tostring(char:GetAttribute("Health"))))
			end
			return
		end
		-- The game links by Players:GetPlayerFromCharacter (0073.lua:115); the name
		-- lookup is the same link and still resolves while Player.Character is nil.
		local plr = known or Players:GetPlayerFromCharacter(char) or Players:FindFirstChild(char.Name)
		if plr == LP then return end
		seen[char] = true
		rigs[#rigs + 1] = { player = plr, char = char }
		local cn, team = char:GetAttribute("CharacterName"), plr and plr:GetAttribute("Team")
		if cn and team then model[cn] = team end
	end

	-- Pass 1a: every Player's own Character, wherever it is parented. A rig sits
	-- under Workspace ROOT for the first moments of a mid-round spawn and the
	-- folder walk below never sees it (logs/bx_mismatch.txt).
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LP then take(plr.Character, true, plr) end
	end

	-- Pass 1b: the Characters folder, which still holds rigs whose
	-- Player.Character has gone nil.
	for _, child in ipairs(root and root:GetChildren() or {}) do
		if child:IsA("Folder") then
			-- kept for the layout the dump describes, in case it comes back
			if child.Name ~= "Hostages" then
				for _, char in ipairs(child:GetChildren()) do take(char) end
			end
		else
			take(child)
		end
	end

	-- OUR side, and how much we trust it.
	--
	-- First-hand: our own rig's @CharacterName. Trusted only when it does not
	-- contradict our own @Team -- `model` maps CharacterName -> the team its
	-- wearers carry, so if our rig says "Anarchist" while the rigs wearing
	-- Anarchist are on the other @Team, the two attributes have skewed and
	-- neither can name our side. That contradiction used to be invisible.
	--
	-- Second-hand: another rig sharing our @Team. Kept, because it is better
	-- than nothing while we are dead (LP.Character is nil then) -- but NEVER
	-- trusted, so a skewed @Team can no longer invert the whole ESP silently.
	local lt = myTeam()
	local ourModel = LP.Character and LP.Character:GetAttribute("CharacterName")
	local ourModelTrusted = false
	if type(ourModel) == "string" and ourModel ~= "" then
		local learned = model[ourModel]
		ourModelTrusted = (lt == nil) or (learned == nil) or (learned == lt)
	else
		ourModel = nil
		for _, rec in ipairs(rigs) do
			local pt = rec.player and rec.player:GetAttribute("Team")
			local cn = rec.char:GetAttribute("CharacterName")
			if lt and pt == lt and type(cn) == "string" and cn ~= "" then ourModel = cn; break end
		end
	end
	S.ourModel, S.ourModelTrusted = ourModel, ourModelTrusted

	local allReliable = true
	for _, rec in ipairs(rigs) do
		local enemy, reliable = isEnemy(rec.player, rec.char, model, ourModel, ourModelTrusted)
		if not reliable then allReliable = false end
		if enemy then out[#out + 1] = rec end
	end

	-- FAILSAFE. If bodies are on the field and we classified every one of them
	-- as a friend, the classification is wrong -- a real round always has an
	-- enemy alive somewhere. Drawing a teammate for a few seconds costs nothing;
	-- drawing nothing is the bug the user keeps reporting. Widen the net, never
	-- narrow a working one (potassium-dev S5.4b).
	-- FAILSAFE -- and note what it does NOT fire on.
	-- It used to trigger whenever we drew nothing while bodies were alive, on
	-- the assumption that a live round always has an enemy in it. That is false:
	-- a dead player's rig moves to Workspace.Debris, so once your side wipes
	-- theirs every remaining alive rig really is a teammate, and the failsafe
	-- then outlined them (measured 15:39, "all classified friendly ...
	-- ourModel=IDF" -- the report of a teammate being chammed).
	-- It now fires only when the classification was UNRELIABLE, i.e. at least
	-- one rig had to fall back to @Team because the rig model could not answer.
	-- Reliable-and-empty means the enemies are simply dead.
	if #out == 0 and #rigs > 0 and not allReliable then
		if not S.blindAt then S.blindAt = os.clock() end
		if os.clock() - S.blindAt > 1.5 then
			for _, rec in ipairs(rigs) do out[#out + 1] = rec end
			if os.clock() - (S.blindLogAt or 0) > 5 then
				S.blindLogAt = os.clock()
				Log.info(string.format("TEAM DATA BLIND: %d alive rig(s), all classified friendly (myTeam=%s ourModel=%s) -- drawing every body until it resolves",
					#rigs, tostring(myTeam()), tostring(ourModel)))
			end
		end
	else
		S.blindAt = nil
	end
	return out
end

--------------------------------------------------------------------------
-- ESP
--------------------------------------------------------------------------

-- 0043.lua CharacterHighlight parents a Highlight INTO each rig (8 of 9 live
-- rigs in the 2026-09-02 dump carry one). Two Highlights on one adornee is
-- undefined in Roblox and ours is the one that can lose, which is exactly the
-- "healthbar but no outline" asymmetry. Disabling theirs is a client property
-- write on a replicated instance: it does not replicate, and 0043's own
-- UpdateState only writes when ITS cached IsEnabled disagrees, so it does not
-- fight us frame by frame. Originals are restored on unload.
local function rivalHighlights(char, enabled)
	for _, d in ipairs(char:GetChildren()) do
		if d:IsA("Highlight") then
			if enabled == false then
				if S.rivals[d] == nil then S.rivals[d] = d.Enabled end
				d.Enabled = false
			elseif S.rivals[d] ~= nil then
				d.Enabled = S.rivals[d]
				S.rivals[d] = nil
			end
		end
	end
end

local function restoreRivals()
	for hl, was in pairs(S.rivals) do
		pcall(function() if hl.Parent then hl.Enabled = was end end)
	end
	table.clear(S.rivals)
end

local function clearEsp(char)
	local e = S.esp[char]
	if not e then return end
	pcall(rivalHighlights, char, true)
	if e.conn then pcall(function() e.conn:Disconnect() end) end
	if e.hl then pcall(function() e.hl:Destroy() end) end
	if e.bb then pcall(function() e.bb:Destroy() end) end
	if e.nb then pcall(function() e.nb:Destroy() end) end
	S.esp[char] = nil
end

local function wipeEsp()
	for char in pairs(S.esp) do clearEsp(char) end
	restoreRivals()
	if S.folder then pcall(function() S.folder:Destroy() end); S.folder = nil end
end

local function ensureEsp(char)
	local folder = ensureFolder()
	local e = S.esp[char]
	if not e then
		e = {}
		S.esp[char] = e
		-- No Humanoid means no Died signal; @Dead is the equivalent, and the
		-- sweep drops the rig anyway once it leaves Workspace.Characters.
		e.conn = char:GetAttributeChangedSignal("Dead"):Connect(function()
			if char:GetAttribute("Dead") == true then clearEsp(char) end
		end)
	end

	if cfg.chams then
		if not e.hl or not e.hl.Parent then
			-- Adornee only. Never parented into the character: 0001.lua kicks on
			-- a hitbox-size probe and a stray instance under a rig is what it reads.
			local hl = Instance.new("Highlight")
			hl.Name = blandName("HL")
			hl.FillColor = COL.enemyFill
			hl.OutlineColor = COL.enemyOut
			hl.FillTransparency = CHAM_FILL_T
			hl.OutlineTransparency = CHAM_OUT_T
			hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			hl.Parent = folder
			e.hl = hl
		end
		e.hl.Adornee = char
		e.hl.Enabled = true
		rivalHighlights(char, false)
	elseif e.hl then
		e.hl.Enabled = false
		rivalHighlights(char, true)
	end

	local head = char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
	local hp, maxHp = healthOf(char)
	if cfg.healthbars and head and hp then
		if not e.bb or not e.bb.Parent then
			local bb = Instance.new("BillboardGui")
			bb.Name = blandName("NT")
			bb.AlwaysOnTop = true
			bb.Size = UDim2.fromOffset(4, 36)
			bb.StudsOffset = Vector3.new(-2.0, 0.15, 0)
			bb.Parent = folder

			local track = Instance.new("Frame")
			track.BackgroundColor3 = Color3.fromRGB(12, 12, 14)
			track.BackgroundTransparency = 0.15
			track.BorderSizePixel = 0
			track.Size = UDim2.fromScale(1, 1)
			track.Parent = bb

			local fill = Instance.new("Frame")
			fill.AnchorPoint = Vector2.new(0, 1)
			fill.Position = UDim2.fromScale(0, 1)
			fill.BackgroundColor3 = COL.hpHi
			fill.BorderSizePixel = 0
			fill.Size = UDim2.fromScale(1, 1)
			fill.Parent = track

			e.bb, e.fill = bb, fill
		end
		local pct = math.clamp(hp / math.max(maxHp, 1), 0, 1)
		e.fill.Size = UDim2.fromScale(1, pct)
		e.fill.BackgroundColor3 = COL.hpLo:Lerp(COL.hpHi, pct)
		e.bb.Adornee = head
		e.bb.MaxDistance = cfg.maxDist
		e.bb.Enabled = true
	elseif e.bb then
		e.bb.Enabled = false
	end

	-- Name tag. Same BillboardGui contract as the healthbar: our own instance in
	-- our own gethui() folder, Adornee only, nothing parented into the rig
	-- (0001.lua kicks on a hitbox-size probe). The rig model IS the player name
	-- (probe 2026-09-03: every Model under Workspace.Characters is named for its
	-- player), so the Player object is only a fallback and a nil one is fine.
	if cfg.names and head then
		if not e.nb or not e.nb.Parent then
			local nb = Instance.new("BillboardGui")
			nb.Name = blandName("NB")
			nb.AlwaysOnTop = true
			nb.Size = UDim2.fromOffset(180, 16)
			nb.StudsOffset = Vector3.new(0, 2.4, 0)
			nb.Parent = folder

			local label = Instance.new("TextLabel")
			label.BackgroundTransparency = 1
			label.Size = UDim2.fromScale(1, 1)
			label.Font = Enum.Font.GothamMedium
			label.TextSize = 13
			label.TextColor3 = COL.nameText
			label.TextStrokeColor3 = Color3.new(0, 0, 0)
			label.TextStrokeTransparency = 0.35
			label.Parent = nb

			e.nb, e.nameLabel = nb, label
		end
		local plr = Players:GetPlayerFromCharacter(char) or Players:FindFirstChild(char.Name)
		local text = (plr and plr.Name) or char.Name
		if cfg.nameDist then
			local myRoot = LP.Character and (LP.Character:FindFirstChild("HumanoidRootPart") or LP.Character:FindFirstChild("Head"))
			if myRoot then
				text = string.format("%s  %dm", text, math.floor((head.Position - myRoot.Position).Magnitude))
			end
		end
		if hp and maxHp then
			e.nameLabel.TextColor3 = COL.hpLo:Lerp(COL.nameText, math.clamp(hp / math.max(maxHp, 1), 0, 1))
		end
		e.nameLabel.Text = text
		e.nb.Adornee = head
		e.nb.MaxDistance = cfg.maxDist
		e.nb.Enabled = true
	elseif e.nb then
		e.nb.Enabled = false
	end
end

-- Catches the "healthbar but no outline" case with evidence instead of theory.
-- Every rig carries the game's own Highlight (7 of 11 rigs, live 2026-09-02).
-- Two Highlights sharing an Adornee is undefined in Roblox -- ours is the one
-- that can lose -- and a BillboardGui healthbar is unaffected either way, which
-- is exactly the reported asymmetry. Roblox also stops rendering Highlights past
-- 31 in the whole DataModel, so the total is worth recording too.
-- Runs only when chams AND healthbars are on, logs at most once every 5 s, and
-- stays silent unless something is actually wrong.
-- Runs whenever chams are on. It used to require healthbars too, which is why
-- it was silent for the whole 2026-09-03 session -- the user runs with bars OFF,
-- so the one instrument that could have named a missing rig never executed.
-- Never gate a diagnostic on an unrelated feature toggle.
local lastAudit = 0
local function chamAudit(seen)
	if not cfg.chams then return end
	local now = os.clock()
	if now - lastAudit < 5 then return end
	lastAudit = now

	-- A player-backed rig the sweep refused. This is the line to read when
	-- somebody swings you with no outline.
	if #S.skips > 0 then
		Log.info("SKIPPED " .. #S.skips .. " player rig(s): " .. table.concat(S.skips, ", "))
	end

	-- An enemy we accepted but whose outline is not actually on it: our Highlight
	-- gone or disabled, or the game's own Highlight re-enabled on the same
	-- adornee, where two Highlights are undefined and ours can lose.
	local bad = {}
	for char in pairs(seen) do
		local e = S.esp[char]
		local rivalOn = 0
		for _, d in ipairs(char:GetChildren()) do
			if d:IsA("Highlight") and d.Enabled and d ~= (e and e.hl) then rivalOn += 1 end
		end
		if not (e and e.hl and e.hl.Parent and e.hl.Enabled and e.hl.Adornee == char) or rivalOn > 0 then
			bad[#bad + 1] = string.format("%s(ourHl=%s rivalOn=%d)", char.Name,
				e and e.hl and (e.hl.Parent and tostring(e.hl.Enabled) or "unparented") or "nil", rivalOn)
		end
	end
	-- THE AUDIT THAT MATTERS. The two checks above only look at rigs that already
	-- passed the enemy filter, so an enemy we classified as a TEAMMATE, or never
	-- enumerated at all, was invisible to both -- 222 SKIPPED lines and 0 NO
	-- OUTLINE while the user was still being killed by un-chammed players.
	-- This walks every container a body can be in and reports any live,
	-- player-linked rig we did not draw, with the verdict that excluded it.
	local myT = myTeam()
	local missed = {}
	local function checkContainer(root, where)
		if not root then return end
		for _, m in ipairs(root:GetChildren()) do
			if m:IsA("Model") and m ~= LP.Character and not seen[m]
				and (m:FindFirstChild("HumanoidRootPart") or m:FindFirstChild("Head")) then
				local plr = Players:GetPlayerFromCharacter(m) or Players:FindFirstChild(m.Name)
				if plr and plr ~= LP and m:GetAttribute("Dead") ~= true then
					local hp = m:GetAttribute("Health")
					if type(hp) ~= "number" or hp > 0 then
						-- cn is the RIG model (IDF / Anarchist), which is what the
						-- classifier actually decides on. The old line logged
						-- @CharacterType, which is "PlayerCustomCharacter" for every
						-- rig in the game and answered nothing -- 418 log lines of it
						-- and not one of them could name why a rig was excluded.
						missed[#missed + 1] = string.format("%s@%s(theirTeam=%s myTeam=%s hp=%s cn=%s ourModel=%s trusted=%s)",
							m.Name, where, tostring(plr:GetAttribute("Team")), tostring(myT),
							tostring(hp), tostring(m:GetAttribute("CharacterName")),
							tostring(S.ourModel), tostring(S.ourModelTrusted))
					end
				end
			end
		end
	end
	checkContainer(Workspace:FindFirstChild("Characters"), "Characters")
	checkContainer(Workspace, "WorkspaceRoot")
	if #missed > 0 and os.clock() - (S.missedLogAt or 0) > 20 then
		S.missedLogAt = os.clock()
		local text = table.concat(missed, ", ")
		if #text > 400 then text = string.sub(text, 1, 400) .. " ..." end
		Log.info(string.format("NOT DRAWN %d live player rig(s): %s", #missed, text))
	end

	-- The budget is the one failure mode where every per-rig fact reads correct
	-- and the screen is still wrong, so it is recorded whenever it gets close.
	local ours = 0
	for _, e in pairs(S.esp) do
		if e.hl and e.hl.Enabled then ours += 1 end
	end
	if (S.hlTotal or 0) > 24 then
		Log.info(string.format("HIGHLIGHT BUDGET: %d in Workspace (limit 31), ours=%d -- past the limit an enemy silently renders no outline",
			S.hlTotal or 0, ours))
	end

	if #bad > 0 then
		-- S.hlTotal is counted by the per-rig walk in sweepEsp; never re-walk the
		-- whole Workspace for a log line.
		Log.info(string.format("NO OUTLINE on %d enemy rig(s): %s | Highlights on rigs=%d/31",
			#bad, table.concat(bad, ", "), S.hlTotal or 0))
	end

end

local function sweepEsp()
	local rigs = enemyRigs()
	S.targets = #rigs
	if not (cfg.chams or cfg.healthbars or cfg.names) then
		for char in pairs(S.esp) do clearEsp(char) end
		return
	end
	-- EVERY enemy gets a cham, at any range. A Highlight costs nothing offscreen
	-- and the whole point is the one behind the wall across the map; `maxDist`
	-- culls the healthbar only, through BillboardGui.MaxDistance in ensureEsp.
	local seen = {}
	for _, rec in ipairs(rigs) do
		seen[rec.char] = true
		ensureEsp(rec.char)
	end
	for char in pairs(S.esp) do
		if not seen[char] then clearEsp(char) end
	end

	-- Roblox renders at most 31 Highlights in the whole DataModel, and the game
	-- parents one into every rig, so idle highlights on teammates and corpses can
	-- starve ours. We disable the ones we can reach -- but ONLY by walking the
	-- rig containers, never the whole Workspace.
	--
	-- The first version of this walked Workspace:GetDescendants() every sweep.
	-- Workspace holds ~161k instances (00_DUMP_STAMP.txt), so at espHz that is
	-- millions of comparisons a second and it visibly lagged the user's game.
	-- A per-rig GetChildren() is bounded by player count and costs nothing.
	local budget = 0
	local function tameRig(m)
		for _, d in ipairs(m:GetChildren()) do
			if d:IsA("Highlight") then
				budget += 1
				local mine = false
				for _, e in pairs(S.esp) do
					if e.hl == d then mine = true; break end
				end
				if not mine and d.Enabled then
					if S.rivals[d] == nil then S.rivals[d] = d.Enabled end
					d.Enabled = false
				end
			end
		end
	end
	for _, container in ipairs({ Workspace:FindFirstChild("Characters"), Workspace:FindFirstChild("Debris") }) do
		if container then
			for _, m in ipairs(container:GetChildren()) do
				if m:IsA("Model") then tameRig(m) end
			end
		end
	end
	S.hlTotal = budget

	chamAudit(seen)
end

--------------------------------------------------------------------------
-- damage census -- the only instrument that can answer "who killed me and did
-- they have a cham"
--------------------------------------------------------------------------
--
-- Every audit above this line reports on rigs the SWEEP already accepted, and
-- `checkContainer` re-uses the sweep's own gates (Head/HRP present, @Dead ~=
-- true, hp > 0). So a rig excluded by one of those gates is invisible to the
-- instrument for exactly the same reason it is invisible to the ESP, and three
-- sessions of clean telemetry have coexisted with the user being killed by
-- someone who had no outline.
--
-- This runs on OUR @Health dropping and censuses EVERY model in the three
-- containers a body can occupy -- no liveness gate, no player-link gate, no
-- team gate -- and records, per rig, whether our Highlight was on it and where
-- that Highlight was parented. That last field is the one that would have ended
-- the 2026-09-03 hunt in one line (a Highlight under gethui()'s ScreenGui never
-- renders; see BLOXSTRIKE.md S3).
--
-- Cost: bounded by player count, and only on a damage event, throttled to 3 s.
local lastCensus = 0
local function damageCensus(reason)
	local now = os.clock()
	if now - lastCensus < 3 then return end
	lastCensus = now

	local myRoot = LP.Character and (LP.Character:FindFirstChild("HumanoidRootPart") or LP.Character:FindFirstChild("Head"))
	local rows = {}
	local function census(root, where)
		if not root then return end
		for _, m in ipairs(root:GetChildren()) do
			if m:IsA("Model") and m ~= LP.Character then
				local part = m:FindFirstChild("HumanoidRootPart") or m:FindFirstChild("Head")
				local plr = Players:GetPlayerFromCharacter(m) or Players:FindFirstChild(m.Name)
				-- Non-player props are noise; a ragdoll clone is NOT, because a
				-- name-mangled corpse is one of the ways a live rig has hidden.
				if plr or string.find(m.Name, "Ragdoll", 1, true) then
					local e = S.esp[m]
					local hl = e and e.hl
					local dist = (part and myRoot) and math.floor((part.Position - myRoot.Position).Magnitude) or -1
					rows[#rows + 1] = string.format(
						"%s@%s{team=%s cn=%s dead=%s hp=%s parts=%s dist=%d cham=%s hlParent=%s}",
						m.Name, where,
						tostring(plr and plr:GetAttribute("Team")),
						tostring(m:GetAttribute("CharacterName")),
						tostring(m:GetAttribute("Dead")),
						tostring(m:GetAttribute("Health")),
						part and part.Name or "NONE",
						dist,
						hl and tostring(hl.Enabled) or "no",
						hl and hl.Parent and hl.Parent:GetFullName() or "-")
				end
			end
		end
	end
	census(Workspace:FindFirstChild("Characters"), "Chars")
	census(Workspace:FindFirstChild("Debris"), "Debris")
	census(Workspace, "WsRoot")

	Log.info(string.format("CENSUS (%s) myTeam=%s ourModel=%s trusted=%s chams=%s | %s",
		reason, tostring(myTeam()), tostring(S.ourModel), tostring(S.ourModelTrusted),
		tostring(cfg.chams), table.concat(rows, " ")))
end

--------------------------------------------------------------------------
-- soft aim
--------------------------------------------------------------------------

local AIM_PARTS = { "Head", "UpperTorso", "HumanoidRootPart" }

local function aimPoints(char)
	if cfg.aimPart == "Head" then
		local h = char:FindFirstChild("Head")
		return h and { h } or {}
	end
	if cfg.aimPart == "Body" then
		local t = char:FindFirstChild("UpperTorso") or char:FindFirstChild("HumanoidRootPart")
		return t and { t } or {}
	end
	local pts = {}
	for _, name in ipairs(AIM_PARTS) do
		local p = char:FindFirstChild(name)
		if p then pts[#pts + 1] = p end
	end
	return pts
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function visible(origin, part, char)
	if not cfg.aimWallCheck then return true end
	local camera = Workspace.CurrentCamera
	-- The viewmodel is parented under the Camera, so it must be excluded or every
	-- ray stops on our own gun.
	local ignore = {}
	if LP.Character then ignore[#ignore + 1] = LP.Character end
	if camera then ignore[#ignore + 1] = camera end
	rayParams.FilterDescendantsInstances = ignore
	local dir = part.Position - origin
	local hit = Workspace:Raycast(origin, dir, rayParams)
	if not hit then return true end
	return hit.Instance:IsDescendantOf(char)
end

local function pickTarget(camera, centre)
	local origin = camera.CFrame.Position
	local look = camera.CFrame.LookVector
	local best

	local function consider(char)
		if not char or not char.Parent then return end
		for _, part in ipairs(aimPoints(char)) do
			local offset = part.Position - origin
			if offset.Magnitude >= 0.01 and offset.Magnitude <= cfg.maxDist then
				local angle = math.deg(math.acos(math.clamp(look:Dot(offset.Unit), -1, 1)))
				if angle <= cfg.aimFov then
					local screen, onScreen = camera:WorldToViewportPoint(part.Position)
					if onScreen and screen.Z > 0 and visible(origin, part, char) then
						local delta = Vector2.new(screen.X, screen.Y) - centre
						if not best or delta.Magnitude < best.score then
							best = { char = char, part = part, delta = delta, score = delta.Magnitude }
						end
					end
				end
			end
		end
	end

	-- Sticky target: without it the aim flickers between two overlapping bodies
	-- and produces exactly the unnatural motion S0.2 rung 3 warns about.
	local now = os.clock()
	if S.stickyChar and now <= S.stickyUntil then
		consider(S.stickyChar)
		if best then return best end
	end
	for _, rec in ipairs(enemyRigs()) do
		consider(rec.char)
	end
	if best then
		S.stickyChar = best.char
		S.stickyUntil = now + 0.18
	end
	return best
end

-- The panel shows the live text every frame; the LOG only wants transitions.
-- The old throttle compared the whole string, and "moving: Name 7.9px" differs
-- from "moving: Name 8.2px", so it logged on every single frame of every aim --
-- one appendfile plus one console write per frame.
local function note(text, key)
	S.aimNote = text
	local now = os.clock()
	local k = key or text
	if k ~= S.aimNoteKey or now - S.aimNoteAt >= 10 then
		S.aimNoteKey = k
		S.aimNoteAt = now
		Log.info("soft aim " .. text)
	end
end

local function updateFovCircle(camera)
	local want = cfg.showAimFov and cfg.softAim and camera
		and type(Drawing) == "table" and type(Drawing.new) == "function"
	if not want then
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
	S.fovDraw.Radius = math.min(focal * math.tan(math.rad(cfg.aimFov)), vp.Magnitude)
	S.fovDraw.Visible = true
end

local function aimStep(dt)
	if not S.alive then return end
	local camera = Workspace.CurrentCamera
	updateFovCircle(camera)
	if not cfg.softAim or not camera then return end
	if type(mousemoverel) ~= "function" then
		note("blocked: mousemoverel unavailable")
		return
	end
	if UserInputService:GetFocusedTextBox()
		or UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
		S.stickyChar = nil
		note("waiting: mouse not locked")
		return
	end
	local rmb = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
	local lmb = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
	if not (rmb or (lmb and not cfg.aimRmbOnly)) then
		S.stickyChar = nil
		note(cfg.aimRmbOnly and "waiting: hold RMB" or "waiting: hold LMB/RMB")
		return
	end
	local target = pickTarget(camera, camera.ViewportSize * 0.5)
	if not target then
		note("searching: no target in cone")
		return
	end
	local scale = math.clamp(cfg.aimStrength, 1, 100) / 100
	local move = target.delta * scale
	local maxStep = cfg.aimMaxStepPx * math.clamp(dt * 60, 0.25, 2)
	if move.Magnitude > maxStep then
		move = move.Unit * maxStep
	end
	-- mousemoverel only: NEVER write CurrentCamera.CFrame (0124.lua:415-429).
	local ok, err = pcall(mousemoverel, move.X, move.Y)
	if ok then
		S.moves += 1
		note(string.format("moving: %s %.1fpx", target.char.Name, move.Magnitude),
			"moving:" .. tostring(target.char.Name))
	else
		note("FAILED: " .. tostring(err))
	end
end

--------------------------------------------------------------------------
-- panel -- R3ST shared kit only (hub S2b)
--------------------------------------------------------------------------

--------------------------------------------------------------------------
-- SKINS -- local cosmetics, same module, second page
--
-- Rung 1. This writes to ONE client-side Lua table and creates nothing in the
-- game's instance tree. The server never sent the skin in the first place, so
-- there is nothing for it to disagree with. Others see your stock loadout.
--
-- The four dump facts this rests on:
--   1. Skins never cross the wire. 0720.lua:650 CreateGameLoadout sends only
--      { Generation, Inventory[{ _items[{ Identifier }] }] } -- an item id and
--      nothing else. The CLIENT decides what that id looks like.
--   2. The client resolves it from a MUTABLE cache. DataController holds its
--      store in upvalue u2 (0139.lua:15); Get walks it and returns the nested
--      table BY REFERENCE with no copy (0139.lua:202-227). Verified live
--      2026-09-03: a marker written through Get survived a second Get
--      (logs/bx_skins_probe.log, "LIVE REFERENCE ... = true").
--   3. No ownership check exists in the render path. GetCameraModel
--      (0322.lua:1209) needs a schema entry and the assets, nothing else.
--      IsSkinAvailable is called by marketplace UI only, never by a builder.
--   4. The schema is the GLOBAL catalog, already on the client:
--      ReplicatedStorage:GetAttribute("AvaiableSkins") (0322.lua:1459) -- 517
--      entries over 54 weapons, independent of what we own.
--
-- WHY A DATA WRITE AND NOT A HOOK: anticheat_deep.txt CLIENT INSPECTION = 2
-- and both hits are Shared.Raycast (1047:408, 1047:513) testing a caller env
-- for `getgenv or hookfunction`. Hooking Skins.* would put our env on a stack
-- the game already walks. Editing a table it owns touches none of it.
--
-- KNIVES ARE FREE: CT Knife (0674.lua) and Butterfly Knife (0671.lua) are
-- identical on every gameplay field -- FireRate 0.36, Range 3, ArmorPenetration
-- 0.9, WalkSpeed 20.2, DamagePerPart {41/48/31/28}. Only Team, icons and the
-- animation folder differ, so swapping the NAME on our own melee item changes
-- the model and animations and cannot desync damage. Animations follow
-- automatically: each def points at Assets.WeaponAnimations[<its name>] and
-- WeaponComponent.new passes the name to both CharacterAnimator.new and
-- Viewmodel.new (0058.lua:39-43).
--------------------------------------------------------------------------

-- Wear bands copied from 0322.lua:22-36, not approximated: the float we write
-- must land inside the band or GetWearTextureFolder picks a different texture
-- set than the label promises.
local WEARS = {
	{ name = "Factory New", mid = 0.02 },
	{ name = "Minimal Wear", mid = 0.11 },
	{ name = "Field-Tested", mid = 0.26 },
	{ name = "Well-Worn", mid = 0.41 },
	{ name = "Battle-Scarred", mid = 0.70 },
}
local function floatForWear(name)
	for _, entry in ipairs(WEARS) do
		if entry.name == name then return entry.mid end
	end
	return 0.02
end

local RARITY_COL = {
	Forbidden = Color3.fromRGB(235, 75, 75),
	Red = Color3.fromRGB(212, 66, 66),
	Pink = Color3.fromRGB(211, 100, 233),
	Purple = Color3.fromRGB(136, 71, 255),
	Blue = Color3.fromRGB(75, 105, 255),
	Special = Color3.fromRGB(255, 200, 80),
	Stock = Color3.fromRGB(140, 140, 150),
}
local RARITY_RANK = { Forbidden = 6, Red = 5, Pink = 4, Special = 3, Purple = 2, Blue = 1, Stock = 0 }

-- High tier only, as asked. Blue is common (Mil-Spec) and Purple is epic
-- (Restricted), so both hide unless "Show every rarity" is on. Melee and Glove
-- have NO lower tier in this game -- every knife and glove finish in the
-- catalog is "Special" (183 and 40 of them) -- so for those types Special is
-- the high tier and always shows.
local function isHighTier(info)
	local r = info.rarity
	if r == "Stock" then return false end
	if info.type == "Melee" or info.type == "Glove" then
		return r == "Special" or r == "Forbidden"
	end
	return r == "Forbidden" or r == "Red" or r == "Pink"
end

local function loadSchema()
	local raw = ReplicatedStorage:GetAttribute("AvaiableSkins")
	if type(raw) ~= "string" or raw == "" then return nil end
	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
	if ok and type(decoded) == "table" then return decoded end
	return nil
end
S.schema = loadSchema()
connect(ReplicatedStorage:GetAttributeChangedSignal("AvaiableSkins"), function()
	local fresh = loadSchema()
	if fresh then S.schema = fresh end
end)

local DataController = nil
local function dataController()
	if DataController then return DataController end
	local ok, mod = pcall(function()
		return require(ReplicatedStorage.Controllers.DataController)
	end)
	if ok and type(mod) == "table" then DataController = mod end
	return DataController
end

-- The live cache, by reference. The reference IS the seam -- never copy it.
local function inventory()
	local dc = dataController()
	if not dc then return nil end
	local ok, inv = pcall(dc.Get, LP, "Inventory")
	if ok and type(inv) == "table" then return inv end
	return nil
end

local function findItem(pred)
	local inv = inventory()
	if not inv then return nil end
	for _, item in ipairs(inv) do
		if type(item) == "table" and pred(item) then return item end
	end
	return nil
end

local function rememberOriginal(item)
	local id = tostring(item._id)
	if S.originals[id] then return end
	S.originals[id] = { Name = item.Name, Skin = item.Skin, Float = item.Float, StatTrack = item.StatTrack }
end

-- The entire mutation surface of this feature: four fields on one cached table.
local function writeItem(item, name, skin, float, statTrak)
	rememberOriginal(item)
	if name then item.Name = name end
	item.Skin = skin
	item.Float = float
	item.StatTrack = statTrak and true or false
end

local function applyPicks()
	local inv = inventory()
	if not inv then return 0 end
	local n = 0
	local float = floatForWear(cfg.wear)

	local melee = cfg.picks["#melee"]
	if type(melee) == "table" and melee.name then
		local item = findItem(function(it) return it.Type == "Melee" end)
		if item then writeItem(item, melee.name, melee.skin or "Stock", float, cfg.statTrak); n += 1 end
	end

	local glove = cfg.picks["#glove"]
	if type(glove) == "table" and glove.skin then
		local item = findItem(function(it) return it.Type == "Glove" end)
		if item then writeItem(item, nil, glove.skin, float, false); n += 1 end
	end

	for key, pick in pairs(cfg.picks) do
		if string.sub(key, 1, 1) ~= "#" and type(pick) == "table" and pick.skin then
			local item = findItem(function(it) return it.Name == key and it.Type == "Weapon" end)
			if item then writeItem(item, nil, pick.skin, float, cfg.statTrak); n += 1 end
		end
	end

	S.applied = n
	return n
end

-- THE CACHE WRITE ABOVE IS NOT ENOUGH, AND HERE IS EXACTLY WHY.
-- Stock.CreateStockItem (0324.lua:117) returns a BRAND NEW table with
-- Skin = "Stock" and Float = 0 hardcoded, and InventoryController's
-- GetEquippedInventoryItem tests Stock.IsStockIdentifier FIRST -- every item we
-- own has the id "<Name>_Stock" (0324.lua:144), so the loadout is built from a
-- synthesised stock item and the inventory cache is never consulted for it.
-- Measured 2026-09-03 (logs/bx_render_probe.log): our write sat correctly in
-- the cache as Name=Butterfly Knife / Skin=Blackwidow while the live component
-- read Name=CT Knife / Skin=Stock. Only the one GUID-id item the user actually
-- owns (an MP9) carried a real skin, which is the same rule seen from the
-- other side.
--
-- So we write where the model is actually built from: the live WeaponComponent
-- and its Viewmodel, then call the game's own Viewmodel:construct(character,
-- weaponComponent) -- the exact call 0060.lua:983 makes. No hook, no remote:
-- these are field writes on client-owned tables plus one method the game calls
-- itself on every equip.
--
-- TWO THINGS THAT COST A ROUND EACH, both measured:
--   * construct takes (character, weaponComponent). Called with the wrong arity
--     it swaps the model and THEN throws at 0060.lua:780 on p59.Properties,
--     leaving the viewmodel half-built -- the arms never re-attach. That is a
--     visibly broken first-person view, so the call is pcall-ed and the
--     component is left alone if it throws.
--   * it requires game modules, which our thread cannot do at the executor's
--     default identity 8 ("Cannot require a non-RobloxScript module"). Identity
--     2 works and is restored immediately after. anticheat_deep.txt lists no
--     identity check in this game; the two CLIENT INSPECTION hits are the
--     Raycast getgenv/hookfunction stack tests, which we still never enter.
-- Declared above its call site on purpose: reskinLive() below reports through
-- it, and the panel replaces it once the Skins page is built.
local setSkinNoteRef = function() end

local GWP = nil
local function weaponProps(name)
	if not GWP then
		local ok, mod = pcall(function()
			return require(ReplicatedStorage.Components.Common.GetWeaponProperties)
		end)
		if ok then GWP = mod end
	end
	if not GWP then return nil end
	local ok, props = pcall(GWP, name)
	return ok and props or nil
end

-- Live, non-destroyed WeaponComponents. Identified structurally (a .Viewmodel
-- and a .Name) rather than by a class name we would be guessing at.
-- DISCOVERY COSTS NOTHING NOW, AND THAT WAS THE WHOLE PROBLEM.
--
-- This used to walk getgc(true) -- the entire Lua heap -- to find the live
-- WeaponComponents. Measured: one 4266 ms frozen frame per scan. Caching it did
-- not help, because a cache keyed on "are all my entries still alive"
-- invalidates constantly (weapons are created and destroyed on every equip), so
-- it simply scanned again every few seconds: 63 FPS with 34 hitches over 100 ms
-- in a 30 s sample.
--
-- InventoryController.getCurrentInventory() returns the same components through
-- the game's own accessor. Measured 2026-09-03: 200 calls in 0.01 ms total --
-- roughly 20 ns each, versus seconds. There is no cache and no invalidation
-- because there is nothing left to amortise.
--
-- Note it must be getCurrentInventory and NOT getCurrentEquipped: the latter
-- walks the caller stack with getfenv looking for getgenv/hookfunction (its own
-- constants list them) and blanks its return for an env like ours.
-- getCurrentInventory carries no such check.
local InvController = nil
local function inventoryController()
	if InvController then return InvController end
	if type(setthreadidentity) ~= "function" then return nil end
	local prev = (type(getthreadidentity) == "function") and getthreadidentity() or 8
	pcall(setthreadidentity, 2)
	local ok, mod = pcall(function()
		return require(ReplicatedStorage.Controllers.InventoryController)
	end)
	pcall(setthreadidentity, prev)
	if ok and type(mod) == "table" then InvController = mod end
	return InvController
end

local function liveComponents()
	local list = {}
	local ic = inventoryController()
	if not ic or type(ic.getCurrentInventory) ~= "function" then return list end
	local ok, inv = pcall(ic.getCurrentInventory)
	if not ok or type(inv) ~= "table" then return list end
	for _, container in pairs(inv) do
		if type(container) == "table" then
			local items = rawget(container, "_items")
			if type(items) == "table" then
				for _, wc in ipairs(items) do
					if type(wc) == "table" and rawget(wc, "Viewmodel") ~= nil
						and rawget(wc, "IsDestroyed") ~= true then
						list[#list + 1] = wc
					end
				end
			end
		end
	end
	return list
end

-- Which pick, if any, owns this component. Melee and Glove match on the CLASS
-- in the component's own Properties, because their Name is the thing we change.
local function wantedFor(wc)
	local props = rawget(wc, "Properties")
	local class = type(props) == "table" and props.Class or nil
	if class == "Melee" then
		local pick = cfg.picks["#melee"]
		if type(pick) == "table" and pick.name then return pick.name, pick.skin end
	elseif class == "Glove" then
		local pick = cfg.picks["#glove"]
		if type(pick) == "table" then return pick.name, pick.skin end
	else
		local pick = cfg.picks[tostring(rawget(wc, "Name"))]
		if type(pick) == "table" and pick.skin then return nil, pick.skin end
	end
	return nil, nil
end

-- Idempotent: a component already wearing the pick is left alone, so this can
-- run on a timer without rebuilding a model every tick.
local function reskinLive(force)
	if not next(cfg.picks) then return 0 end
	local char = LP.Character
	if not char then return 0 end
	if type(setthreadidentity) ~= "function" then return 0 end

	local prev = (type(getthreadidentity) == "function") and getthreadidentity() or 8
	pcall(setthreadidentity, 2)
	local n = 0
	for _, wc in ipairs(liveComponents()) do
		local name, skin = wantedFor(wc)
		local vm = rawget(wc, "Viewmodel")
		if skin and type(vm) == "table" then
			local needName = name and rawget(wc, "Name") ~= name
			local needSkin = rawget(wc, "Skin") ~= skin
			-- Deferred by design: a component that is not equipped is not on
			-- screen, so rebuilding it now buys nothing and costs a model clone.
			-- vm.IsEquipped is the game's own flag. At a round restart this turns
			-- a burst of five to seven constructs into exactly one.
			if not force and rawget(vm, "IsEquipped") == false then
				needSkin = false
				needName = false
			end
			if force or needName or needSkin then
				local float = floatForWear(cfg.wear)
				if name then
					local props = weaponProps(name)
					if props then
						wc.Name = name
						wc.Properties = props
						vm.Weapon = name
						if rawget(vm, "CameraModelWeapon") ~= nil then vm.CameraModelWeapon = name end
					end
				end
				wc.Skin = skin
				wc.Float = float
				vm.Skin = skin
				vm.Float = float
				-- 0060.lua:983 -- the game's own call, arity included.
				-- construct parents its Model into ReplicatedFirst, which is the
				-- very signal we listen to for "a new component exists". Without
				-- this guard our own rebuild invalidated the cache and bought a
				-- heap scan -- a feedback loop that fired on every reskin.
				local built = pcall(function() vm:construct(char, wc) end)
				if built then n += 1 else setSkinNoteRef("construct refused on " .. tostring(rawget(wc, "Name"))) end
			end
		end
	end
	pcall(setthreadidentity, prev)
	if n > 0 then S.applied = n end
	return n
end

--------------------------------------------------------------------------
-- Presets. A pick set is small and JSON-safe, so a preset is just a named
-- copy of it plus the wear. Every mutation calls saveConfig(), which is the
-- same debounced writer the ESP toggles use -- there is no separate "save"
-- step to forget (script-scaffold S0.1: persistence is not a follow-up task).
--------------------------------------------------------------------------

local function copyPicks(src)
	local out = {}
	for key, pick in pairs(src or {}) do
		if type(pick) == "table" then
			out[key] = { name = pick.name, skin = pick.skin }
		end
	end
	return out
end

local function presetSave(name)
	if type(name) ~= "string" or name == "" then return false end
	cfg.presets[name] = { wear = cfg.wear, picks = copyPicks(cfg.picks) }
	cfg.preset = name
	saveConfig()
	return true
end

local function presetLoad(name)
	local preset = cfg.presets[name]
	if type(preset) ~= "table" then return false end
	cfg.picks = copyPicks(preset.picks)
	if type(preset.wear) == "string" then cfg.wear = preset.wear end
	cfg.preset = name
	saveConfig()
	return true
end

local function presetNames()
	local out = {}
	for name in pairs(cfg.presets) do out[#out + 1] = name end
	table.sort(out)
	return out
end

-- The highest-rarity finish this weapon has, by the same ladder the grid sorts
-- on. Ties break alphabetically so the choice is deterministic across sessions
-- rather than whatever pairs() happened to yield first.
local function bestSkinFor(weapon)
	if not S.schema then return nil end
	local bestName, bestRank = nil, -1
	for skin, info in pairs(S.schema[weapon] or {}) do
		if info.rarity ~= "Stock" then
			local rank = RARITY_RANK[info.rarity] or 0
			if rank > bestRank or (rank == bestRank and bestName and skin < bestName) then
				bestName, bestRank = skin, rank
			end
		end
	end
	return bestName
end

-- Every gun we hold gets its top finish; melee is pinned to the knife MODEL the
-- user asked for and then given that model's best finish.
local function buildBestPicks(meleeModel)
	local picks = {}
	local inv = inventory()
	if inv then
		for _, item in ipairs(inv) do
			if item.Type == "Weapon" and type(item.Name) == "string" then
				local skin = bestSkinFor(item.Name)
				if skin then picks[item.Name] = { skin = skin } end
			elseif item.Type == "Glove" and type(item.Name) == "string" then
				local skin = bestSkinFor(item.Name)
				if skin then picks["#glove"] = { name = item.Name, skin = skin } end
			end
		end
	end
	local knife = meleeModel or "Butterfly Knife"
	local kSkin = bestSkinFor(knife)
	if kSkin then picks["#melee"] = { name = knife, skin = kSkin } end
	return picks
end

local SPAWN_WRITES = { 0, 0.15, 0.35, 0.6, 1, 1.5, 2.5, 4, 6 }
local function reapplyAcrossSpawn(tag)
	if not next(cfg.picks) then return end
	for _, delay in ipairs(SPAWN_WRITES) do
		task.delay(delay, function()
			if not S.alive then return end
			applyPicks()
		end)
	end
	-- One rebuild pass after the loadout has settled, not one per write.
	task.delay(2, function()
		if S.alive then reskinLive(false) end
	end)
	task.delay(SPAWN_WRITES[#SPAWN_WRITES] + 0.2, function()
		if not S.alive then return end
		reskinLive(false)
		setSkinNoteRef(string.format("%d pick(s) held across %s", S.applied, tag))
	end)
end


local function restoreOriginals()
	local inv = inventory()
	if inv then
		for _, item in ipairs(inv) do
			local was = S.originals[tostring(item._id)]
			if was then
				item.Name, item.Skin, item.Float, item.StatTrack = was.Name, was.Skin, was.Float, was.StatTrack
			end
		end
	end
	table.clear(S.originals)
	S.applied = 0
end

-- Knife and glove MODELS come from the catalog, so one added in an update
-- appears without a code change here.
local function modelsOfType(kind)
	local out = {}
	if not S.schema then return out end
	for weapon, skins in pairs(S.schema) do
		for _, info in pairs(skins) do
			if info.type == kind then out[#out + 1] = weapon; break end
		end
	end
	table.sort(out)
	return out
end

-- Guns come from the INVENTORY, not the catalog: a skin can only be written
-- onto an item we actually hold, so listing a gun we do not own would be a
-- control that maps to nothing (hub S3).
local CLASS_OF = {
	["AK-47"] = "Rifles", ["M4A1-S"] = "Rifles", ["M4A4"] = "Rifles", ["AUG"] = "Rifles",
	["SG 553"] = "Rifles", ["FAMAS"] = "Rifles", ["Galil AR"] = "Rifles",
	["AWP"] = "Rifles", ["SSG 08"] = "Rifles", ["SCAR-20"] = "Rifles", ["G3SG1"] = "Rifles",
	["USP-S"] = "Pistols", ["Glock-18"] = "Pistols", ["P250"] = "Pistols",
	["Desert Eagle"] = "Pistols", ["Tec-9"] = "Pistols", ["CZ75-Auto"] = "Pistols",
	["Five-SeveN"] = "Pistols", ["Dual Berettas"] = "Pistols", ["R8 Revolver"] = "Pistols",
}
local function weaponsFor(cat)
	if cat == "Knives" then return modelsOfType("Melee") end
	if cat == "Gloves" then return modelsOfType("Glove") end
	local out, seenName = {}, {}
	local inv = inventory()
	if not inv then return out end
	for _, item in ipairs(inv) do
		if item.Type == "Weapon" and type(item.Name) == "string"
			and (CLASS_OF[item.Name] or "Other") == cat and not seenName[item.Name] then
			seenName[item.Name] = true
			out[#out + 1] = item.Name
		end
	end
	table.sort(out)
	return out
end

local function skinsFor(weapon)
	local out = {}
	if not S.schema or not weapon then return out end
	for skin, info in pairs(S.schema[weapon] or {}) do
		if info.rarity ~= "Stock" and (cfg.showAll or isHighTier(info)) then
			out[#out + 1] = { skin = skin, info = info }
		end
	end
	table.sort(out, function(a, b)
		local ra, rb = RARITY_RANK[a.info.rarity] or 0, RARITY_RANK[b.info.rarity] or 0
		if ra ~= rb then return ra > rb end
		return a.skin < b.skin
	end)
	return out
end

-- "Random legendary": not a random skin, a random one from the TOP band that
-- weapon actually owns. Ranks step down only when a band is empty, so a gun
-- with Reds never rolls a Blue, and a gun whose best is Blue (MAG-7, Nova) still
-- rolls rather than being skipped.
local RANDOM_BANDS = { 5, 4, 2, 1 }   -- Red+ , Pink+ , Purple+ , anything
local function randomSkinFor(weapon)
	if not S.schema then return nil end
	local byRank = {}
	for skin, info in pairs(S.schema[weapon] or {}) do
		if info.rarity ~= "Stock" then
			local rank = RARITY_RANK[info.rarity] or 0
			byRank[rank] = byRank[rank] or {}
			table.insert(byRank[rank], skin)
		end
	end
	-- Melee and Glove live at Special/Forbidden, so band them on their own ladder.
	for _, floor in ipairs(RANDOM_BANDS) do
		local pool = {}
		for rank, skins in pairs(byRank) do
			if rank >= floor then
				for _, skin in ipairs(skins) do pool[#pool + 1] = skin end
			end
		end
		if #pool > 0 then
			table.sort(pool)   -- deterministic pool, random pick out of it
			return pool[RNG:NextInteger(1, #pool)]
		end
	end
	return nil
end

-- Everything gets rolled, including WHICH knife and glove model you carry --
-- the model is as cosmetic as the finish (see the header: knife stats are
-- identical across all nine), so there is no reason to pin it.
local function buildRandomPicks()
	local picks = {}
	local inv = inventory()
	if inv then
		for _, item in ipairs(inv) do
			if item.Type == "Weapon" and type(item.Name) == "string" then
				local skin = randomSkinFor(item.Name)
				if skin then picks[item.Name] = { skin = skin } end
			end
		end
	end
	local knives = modelsOfType("Melee")
	if #knives > 0 then
		local knife = knives[RNG:NextInteger(1, #knives)]
		local skin = randomSkinFor(knife)
		if skin then picks["#melee"] = { name = knife, skin = skin } end
	end
	local gloves = modelsOfType("Glove")
	if #gloves > 0 then
		local glove = gloves[RNG:NextInteger(1, #gloves)]
		local skin = randomSkinFor(glove)
		if skin then picks["#glove"] = { name = glove, skin = skin } end
	end
	return picks
end


local buildGridRef = nil

local screen = Instance.new("ScreenGui")
screen.Name = blandName("SG")
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.DisplayOrder = 2147483647
screen.Parent = espParent()

local panel = Instance.new("Frame")
panel.Size = UDim2.fromOffset(900, 640)
panel.Position = UDim2.new(0.5, -450, 0.5, -320)
panel.BackgroundColor3 = Color3.fromRGB(9, 9, 11)
panel.BorderSizePixel = 0
panel.Active = true
panel.Parent = screen

-- One module, one window, two pages. ESP and Skins are the same game and the
-- same panel; a second registry row would put two BloxStrike cards in the hub
-- and two panels on screen, which is the bug hub S6.1 exists to prevent.
local PAGE_TOP = 122
local body = Instance.new("ScrollingFrame")
body.Position = UDim2.fromOffset(18, PAGE_TOP)
body.Size = UDim2.new(1, -36, 1, -PAGE_TOP - 54)
body.BackgroundTransparency = 1
body.BorderSizePixel = 0
body.ScrollBarThickness = 4
body.Parent = panel

-- Standalone fallback. `loadfile` RETURNS NIL for a path it cannot resolve --
-- it does not error -- so `loadfile(p)() or loadfile(q)()` calls nil and dies
-- before the `or` is ever reached. Resolve first, call second, in the hub's own
-- Explorer-first order (hub S11).
local function loadKit()
	if HOST and HOST.ui then return HOST.ui end
	for _, path in ipairs({ "../scripts/r3st_ui.lua", "r3st_ui.lua", "scripts/r3st_ui.lua" }) do
		local ok, chunk = pcall(loadfile, path)
		if ok and type(chunk) == "function" then
			local ok2, kit = pcall(chunk)
			if ok2 and type(kit) == "table" then
				Log.info("kit resolved -> " .. path .. " " .. tostring(kit.VERSION))
				return kit
			end
		end
	end
	return nil
end
local Kit = loadKit()
if not Kit then
	Log.info("ABORT: r3st_ui.lua not found in any root")
	pcall(function() screen:Destroy() end)
	return
end
-- r8: the ESP folder is a full-screen gethui() layer and must NOT be reparented
-- into the hub host, or every billboard clips to the panel rectangle. Only the
-- control panel moves. Create it now so `keep` can actually assert on it.
local H = Kit.host({ screen = screen, root = panel, keep = { ensureFolder() } })
local W = Kit.bind({ live = S.live, conns = S.conns, cfg = cfg, save = saveConfig })

-- Standalone only: the hub owns drag, resize and the border when hosted (S6.1
-- r2), so this window chrome exists purely for injecting the file directly.
-- Without it the panel was a fixed rectangle nailed to the screen centre.
if not H.hosted then
	Kit.stroke(panel, Kit.COL.line, 0)
	Kit.corner(panel, 8)
	local dragging, startPos, startIn
	panel.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging, startIn, startPos = true, input.Position, panel.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then dragging = false end
			end)
		end
	end)
	connect(UserInputService.InputChanged, function(input)
		if not dragging then return end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input.UserInputType ~= Enum.UserInputType.Touch then return end
		local d = input.Position - startIn
		panel.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
			startPos.Y.Scale, startPos.Y.Offset + d.Y)
	end)
	pcall(Kit.resizeGrip, panel, { min = Vector2.new(520, 420) })
end

W.header(panel, {
	title = "BloxStrike",
	version = BUILD_VERSION,
	subtitle = "Enemy ESP and camera-input soft aim",
	gameId = EXPECTED_GAME,
	placeId = EXPECTED_PLACE,
})
W.page(body, { width = 720 })

W.section(body, "ESP")
W.toggle(body, { label = "Chams", desc = "Solid outline on every enemy, through walls, at any range. Adornee only, nothing parented into a rig.",
	key = "chams", set = function() task.defer(sweepEsp) end })
W.toggle(body, { label = "Healthbars", desc = "Vertical HP bar beside each enemy head, read from the rig's @Health.",
	key = "healthbars", set = function() task.defer(sweepEsp) end })
W.toggle(body, { label = "Names", desc = "Player name over each enemy head, tinted by HP. BillboardGui in our own folder, Adornee only.",
	key = "names", set = function() task.defer(sweepEsp) end })
W.toggle(body, { label = "Distance in name", desc = "Append the distance in studs to the name tag.",
	key = "nameDist", set = function() task.defer(sweepEsp) end })
W.slider(body, { label = "Healthbar distance", key = "maxDist", min = 50, max = 1000, step = 25,
	fmt = function(v) return string.format("%d studs", v) end,
	tradeoff = "Bars past this stop drawing. Chams ignore it -- every enemy is always outlined." })
W.slider(body, { label = "Refresh interval", key = "espHz", min = 0.1, max = 1, step = 0.02,
	fmt = function(v) return string.format("%.2f s", v) end,
	tradeoff = "Lower is more responsive; 0.28 s is the tested default." })

W.toggle(body, { label = "Show every rarity", key = "showAll",
	desc = "OFF: only high tier -- Covert, Classified, Contraband, and every knife/glove finish. ON: the common and epic ones too.",
	set = function() if buildGridRef then task.defer(buildGridRef) end end })

W.toggle(body, { label = "Autoload preset", key = "autoPreset",
	desc = "Re-apply the saved preset every inject and every spawn. Off: picks stay as you left them this session only." })

W.section(body, "Soft aim")
W.toggle(body, { label = "Soft aim", key = "softAim",
	desc = "Nudges the mouse toward the nearest enemy inside the cone. Fires no remote; the shot is still yours." })
W.toggle(body, { label = "Only while holding RMB", key = "aimRmbOnly",
	desc = "ON: assists only when you are aiming down sights. OFF: LMB counts too." })
W.toggle(body, { label = "Wall check", key = "aimWallCheck",
	desc = "Skip a target the camera cannot actually see." })
W.toggle(body, { label = "Show cone", key = "showAimFov",
	desc = "Draw the aim cone as a circle on the Drawing overlay." })
W.slider(body, { label = "Cone", key = "aimFov", min = 2, max = 30, step = 1,
	fmt = function(v) return string.format("%d deg", v) end,
	tradeoff = "Wide cones snap across the screen -- that is the motion a spectator narrates." })
W.slider(body, { label = "Strength", key = "aimStrength", min = 5, max = 100, step = 5,
	fmt = function(v) return string.format("%d%%", v) end,
	tradeoff = "Fraction of the remaining error closed per frame. 100% is a lock." })
W.slider(body, { label = "Max step", key = "aimMaxStepPx", min = 4, max = 80, step = 2,
	fmt = function(v) return string.format("%d px/frame", v) end,
	tradeoff = "Hard cap on per-frame turn rate; low keeps the motion human." })
local partBtn
partBtn = W.button(body, "Target part: " .. cfg.aimPart, "Cycles Closest / Head / Body", function()
	cfg.aimPart = (cfg.aimPart == "Closest" and "Head")
		or (cfg.aimPart == "Head" and "Body") or "Closest"
	partBtn.Text = "Target part: " .. cfg.aimPart
	saveConfig()
end)

W.section(body, "Live")
W.statusRow(body, function()
	return string.format("Team %s  ·  Enemies %d  ·  Drawn %d",
		tostring(myTeam() or "unknown"), S.targets, (function()
			local n = 0
			for _ in pairs(S.esp) do n += 1 end
			return n
		end)())
end)
W.statusRow(body, function()
	return string.format("Soft aim %s  ·  %s  ·  %d moves",
		cfg.softAim and "ON" or "OFF", S.aimNote, S.moves)
end)

W.section(body, "Safety")
W.note(body, "P disarms soft aim and hides every ESP instance. K unloads. Nothing here fires a remote or writes CurrentCamera -- soft aim moves the mouse, so the game's own camera controller stays the only writer (0124.lua:415).")

body.CanvasSize = UDim2.fromOffset(0, W.height(body))

--------------------------------------------------------------------------
-- Skins page -- kit tokens only. Every colour, radius, stroke and type size
-- below comes from Kit.COL / Kit.TYPE, and the cards are the same 10px radius
-- + COL.card + COL.line stroke that Kit.section draws, so this page reads as
-- the same product as the ESP page beside it (hub S2b, S9.3 "Sameness").
--------------------------------------------------------------------------

local KC = Kit.COL   -- kit palette; the module's own COL above is cham colours
local skinPage = Kit.new("Frame", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(18, PAGE_TOP),
	Size = UDim2.new(1, -36, 1, -PAGE_TOP - 54),
	Visible = false,
}, panel)

local function card(parent, x, y, w, h)
	local f = Kit.new("Frame", {
		BackgroundColor3 = KC.card,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.new(w.Scale, w.Offset, h.Scale, h.Offset),
	}, parent)
	Kit.corner(f, 10)
	Kit.stroke(f, KC.line)
	return f
end

local COLW = 186
local wepCard = card(skinPage, 0, 0, UDim.new(0, COLW), UDim.new(1, 0))
local wepTitle = Kit.label(wepCard, "Weapon", 15, KC.text, 14, 8, 0, 22)
wepTitle.Size = UDim2.new(1, -28, 0, 22)
wepTitle.Font = Enum.Font.GothamBold

local catRow = Kit.new("Frame", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(10, 36),
	Size = UDim2.new(1, -20, 0, 26),
}, wepCard)

local wepPane = Kit.new("ScrollingFrame", {
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Position = UDim2.fromOffset(8, 70),
	Size = UDim2.new(1, -16, 1, -80),
	ScrollBarThickness = 3,
	-- Active=true or the wheel never reaches it (check_hub R13).
	Active = true, ScrollingDirection = Enum.ScrollingDirection.Y,
	CanvasSize = UDim2.new(),
}, wepCard)

local right = Kit.new("Frame", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(COLW + 12, 0),
	Size = UDim2.new(1, -COLW - 12, 1, 0),
}, skinPage)

local PREVIEW_H = 156
local preview = card(right, 0, 0, UDim.new(1, 0), UDim.new(0, PREVIEW_H))

-- Every Melee entry in the catalog returns imageAssetId = nil (verified live,
-- logs/bx_skins_probe2.log), so knives -- the thing most people are here for --
-- have no icon at all. One rendered model is the honest preview; a grid of 38
-- ViewportFrames would not be.
local viewport = Kit.new("ViewportFrame", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(14, 14),
	Size = UDim2.fromOffset(190, PREVIEW_H - 28),
	Ambient = Color3.fromRGB(180, 180, 190),
	LightColor = Color3.fromRGB(255, 255, 255),
}, preview)
local vpCam = Instance.new("Camera")
vpCam.Parent = viewport
viewport.CurrentCamera = vpCam

local pvName = Kit.label(preview, "Pick a finish", 15, KC.text, 218, 16, 0, 22)
pvName.Size = UDim2.new(1, -232, 0, 22)
pvName.Font = Enum.Font.GothamBold
local pvRarity = Kit.label(preview, "", 11, KC.dim, 218, 40, 0, 16)
pvRarity.Size = UDim2.new(1, -232, 0, 16)
local pvDesc = Kit.label(preview, "", 11, KC.faint, 218, 62, 0, 54)
pvDesc.Size = UDim2.new(1, -232, 0, 54)
pvDesc.TextWrapped = true
pvDesc.TextYAlignment = Enum.TextYAlignment.Top

-- Preset bar. Lives in the preview card because that is where the eye already
-- is after picking a finish, and it keeps the action row from overflowing.
local presetLbl = Kit.label(preview, "", 11, KC.dim, 218, PREVIEW_H - 34, 0, 16)
presetLbl.Size = UDim2.new(0, 150, 0, 16)

local function refreshPresetLabel()
	local n = 0
	for _ in pairs(cfg.presets) do n += 1 end
	presetLbl.Text = string.format("Preset: %s  (%d saved)", tostring(cfg.preset or "none"), n)
end

local function smallButton(parent, text, x, y, w, fn)
	local b = Kit.new("TextButton", {
		BackgroundColor3 = KC.row,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(w, 24),
	}, parent)
	Kit.corner(b, 6)
	local st = Kit.stroke(b, KC.line, 0.5)
	Kit.interactive(b, st, KC.row)
	local l = Kit.label(b, text, 11, KC.text, 0, 4, 0, 16)
	l.Size = UDim2.new(1, 0, 0, 16)
	l.TextXAlignment = Enum.TextXAlignment.Center
	l.Font = Enum.Font.GothamBold
	b.MouseButton1Click:Connect(fn)
	return b, l
end

local rebuildSkinPage

smallButton(preview, "Next preset", 290, PREVIEW_H - 38, 84, function()
	local names = presetNames()
	if #names == 0 then setSkinNoteRef("no presets saved yet"); return end
	local idx = 1
	for i, name in ipairs(names) do
		if name == cfg.preset then idx = i; break end
	end
	local nextName = names[(idx % #names) + 1]
	presetLoad(nextName)
	local live = reskinLive(true)
	setSkinNoteRef(string.format("loaded preset \"%s\" (%d live)", nextName, live))
	refreshPresetLabel()
	rebuildSkinPage()
end)

smallButton(preview, "Save preset", 378, PREVIEW_H - 38, 84, function()
	presetSave(cfg.preset or "Best")
	setSkinNoteRef(string.format("saved preset \"%s\"", tostring(cfg.preset)))
	refreshPresetLabel()
end)

smallButton(preview, "Best for all", 466, PREVIEW_H - 38, 84, function()
	local knife = (S.cat == "Knives" and S.weapon) or "Butterfly Knife"
	cfg.picks = buildBestPicks(knife)
	presetSave("Best")
	local live = reskinLive(true)
	local n = 0
	for _ in pairs(cfg.picks) do n += 1 end
	setSkinNoteRef(string.format("top rarity on %d item(s), saved as \"Best\" (%d live)", n, live))
	refreshPresetLabel()
	rebuildSkinPage()
end)

smallButton(preview, "Randomize", 554, PREVIEW_H - 38, 84, function()
	cfg.picks = buildRandomPicks()
	presetSave("Random")
	local live = reskinLive(true)
	local n = 0
	for _ in pairs(cfg.picks) do n += 1 end
	local melee = cfg.picks["#melee"]
	setSkinNoteRef(string.format("rolled %d item(s) -- knife %s | %s (%d live)", n,
		tostring(melee and melee.name), tostring(melee and melee.skin), live))
	refreshPresetLabel()
	rebuildSkinPage()
end)

local gridCard = card(right, 0, PREVIEW_H + 12, UDim.new(1, 0), UDim.new(1, -PREVIEW_H - 12 - 42))
local gridTitle = Kit.label(gridCard, "Finishes", 15, KC.text, 14, 8, 0, 22)
gridTitle.Size = UDim2.new(1, -28, 0, 22)
gridTitle.Font = Enum.Font.GothamBold
local grid = Kit.new("ScrollingFrame", {
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Position = UDim2.fromOffset(12, 36),
	Size = UDim2.new(1, -24, 1, -46),
	ScrollBarThickness = 3,
	-- Active=true or the wheel never reaches it (check_hub R13).
	Active = true, ScrollingDirection = Enum.ScrollingDirection.Y,
	CanvasSize = UDim2.new(),
}, gridCard)

local actionRow = Kit.new("Frame", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 0, 1, -32),
	Size = UDim2.new(1, 0, 0, 30),
}, right)

local previewModel = nil
local function clearPreviewModel()
	if previewModel then pcall(function() previewModel:Destroy() end); previewModel = nil end
end

-- Renders through the game's OWN builder: a read of ReplicatedStorage assets
-- plus a Clone into our ViewportFrame. Nothing is parented into the world.
-- GetCameraModel first -- GetWorldModel returns nil for knives (measured).
local function renderPreview(weapon, skin)
	clearPreviewModel()
	if not weapon or not skin then return end
	local ok, Skins = pcall(function()
		return require(ReplicatedStorage.Database.Components.Libraries.Skins)
	end)
	if not ok or type(Skins) ~= "table" then return end
	local built
	pcall(function()
		built = Skins.GetCameraModel(weapon, skin, floatForWear(cfg.wear))
			or Skins.GetWorldModel(weapon, skin, floatForWear(cfg.wear))
			or Skins.GetBaseWeaponModel(weapon, "Character")
	end)
	if not built then return end
	built.Parent = viewport
	previewModel = built
	local cf, size
	pcall(function() cf, size = built:GetBoundingBox() end)
	if cf and size then
		local dist = math.max(size.Magnitude * 0.85, 3)
		vpCam.CFrame = CFrame.new(cf.Position + Vector3.new(dist * 0.55, dist * 0.4, dist * 0.75), cf.Position)
	end
end

local function pickKeyFor(weapon)
	if S.cat == "Knives" then return "#melee" end
	if S.cat == "Gloves" then return "#glove" end
	return weapon
end

local function currentPickSkin(weapon)
	local pick = cfg.picks[pickKeyFor(weapon)]
	if type(pick) ~= "table" then return nil end
	if (S.cat == "Knives" or S.cat == "Gloves") and pick.name ~= weapon then return nil end
	return pick.skin
end

local buildGrid, buildWeapons

local function selectSkin(weapon, skin, info)
	S.sel = { weapon = weapon, skin = skin, info = info }
	pvName.Text = weapon .. "  |  " .. skin
	pvRarity.Text = tostring(info.rarity) .. "  ·  " .. cfg.wear
	pvRarity.TextColor3 = RARITY_COL[info.rarity] or KC.dim
	pvDesc.Text = tostring(info.description or "")
	renderPreview(weapon, skin)
end

local CARDW, CARDH = 136, 112
function buildGrid()
	for _, child in ipairs(grid:GetChildren()) do child:Destroy() end
	local list = skinsFor(S.weapon)
	if #list == 0 then
		local msg = Kit.label(grid, S.weapon
			and "No high-tier finishes here. Turn on \"Show every rarity\" on the ESP page."
			or "Pick a weapon on the left.", 12, KC.faint, 4, 6, 0, 40)
		msg.Size = UDim2.new(1, -8, 0, 40)
		msg.TextWrapped = true
		grid.CanvasSize = UDim2.fromOffset(0, 52)
		return
	end
	local perRow = math.max(1, math.floor((grid.AbsoluteSize.X + 8) / (CARDW + 8)))
	local equipped = currentPickSkin(S.weapon)
	for i, entry in ipairs(list) do
		local cx = ((i - 1) % perRow) * (CARDW + 8)
		local cy = math.floor((i - 1) / perRow) * (CARDH + 8)
		local rc = RARITY_COL[entry.info.rarity] or KC.line
		local on = entry.skin == equipped
		local tile = Kit.new("TextButton", {
			BackgroundColor3 = on and KC.rowHover or KC.row,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
			Position = UDim2.fromOffset(cx, cy),
			Size = UDim2.fromOffset(CARDW, CARDH),
		}, grid)
		Kit.corner(tile, 8)
		local st = Kit.stroke(tile, on and KC.good or rc, on and 0.15 or 0.45)
		Kit.interactive(tile, st, on and KC.rowHover or KC.row)

		local img = entry.info.imageAssetId
		if type(img) == "string" and img ~= "" then
			Kit.new("ImageLabel", {
				BackgroundTransparency = 1,
				Image = img,
				ScaleType = Enum.ScaleType.Fit,
				Position = UDim2.fromOffset(8, 6),
				Size = UDim2.fromOffset(CARDW - 16, 60),
			}, tile)
		else
			local sw = Kit.new("Frame", {
				BackgroundColor3 = rc,
				BackgroundTransparency = 0.74,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(8, 6),
				Size = UDim2.fromOffset(CARDW - 16, 60),
			}, tile)
			Kit.corner(sw, 6)
			local hint = Kit.label(sw, "select to preview", 10, KC.dim, 0, 22, 0, 16)
			hint.Size = UDim2.new(1, 0, 0, 16)
			hint.TextXAlignment = Enum.TextXAlignment.Center
		end

		local nm = Kit.label(tile, entry.skin, 11, KC.text, 8, 70, 0, 15)
		nm.Size = UDim2.new(1, -16, 0, 15)
		nm.TextTruncate = Enum.TextTruncate.AtEnd
		local rr = Kit.label(tile, on and "equipped" or tostring(entry.info.rarity), 10,
			on and KC.good or rc, 8, 88, 0, 14)
		rr.Size = UDim2.new(1, -16, 0, 14)

		tile.MouseButton1Click:Connect(function()
			selectSkin(S.weapon, entry.skin, entry.info)
			buildGrid()
		end)
	end
	grid.CanvasSize = UDim2.fromOffset(0, math.ceil(#list / perRow) * (CARDH + 8) + 4)
end
buildGridRef = buildGrid

function rebuildSkinPage()
	buildWeapons()
	buildGrid()
	local keep = S.weapon and currentPickSkin(S.weapon)
	if keep and S.schema and S.schema[S.weapon] and S.schema[S.weapon][keep] then
		selectSkin(S.weapon, keep, S.schema[S.weapon][keep])
	end
end
refreshPresetLabel()

function buildWeapons()
	for _, child in ipairs(wepPane:GetChildren()) do child:Destroy() end
	local y = 0
	for _, weapon in ipairs(weaponsFor(S.cat)) do
		local on = weapon == S.weapon
		local btn = Kit.new("TextButton", {
			BackgroundColor3 = on and KC.rowHover or KC.row,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
			Position = UDim2.fromOffset(0, y),
			Size = UDim2.new(1, -4, 0, 28),
		}, wepPane)
		Kit.corner(btn, 6)
		local st = Kit.stroke(btn, on and KC.white or KC.lineSoft, on and 0.35 or 0.7)
		Kit.interactive(btn, st, on and KC.rowHover or KC.row)
		local lbl = Kit.label(btn, weapon, 12, on and KC.text or KC.dim, 10, 6, 0, 16)
		lbl.Size = UDim2.new(1, -34, 0, 16)
		lbl.TextTruncate = Enum.TextTruncate.AtEnd
		if currentPickSkin(weapon) then
			local dot = Kit.new("Frame", {
				BackgroundColor3 = KC.good,
				BorderSizePixel = 0,
				Position = UDim2.new(1, -20, 0, 11),
				Size = UDim2.fromOffset(6, 6),
			}, btn)
			Kit.corner(dot, 3)
		end
		btn.MouseButton1Click:Connect(function()
			S.weapon = weapon
			buildWeapons()
			buildGrid()
			local keep = currentPickSkin(weapon)
			local first = skinsFor(weapon)[1]
			if keep and S.schema[weapon] and S.schema[weapon][keep] then
				selectSkin(weapon, keep, S.schema[weapon][keep])
			elseif first then
				selectSkin(weapon, first.skin, first.info)
			end
		end)
		y += 32
	end
	wepPane.CanvasSize = UDim2.fromOffset(0, y + 4)
end

local function chooseCategory(cat)
	S.cat = cat
	S.weapon = weaponsFor(cat)[1]
	buildWeapons()
	buildGrid()
	local keep = S.weapon and currentPickSkin(S.weapon)
	local first = S.weapon and skinsFor(S.weapon)[1]
	if keep and S.schema[S.weapon] and S.schema[S.weapon][keep] then
		selectSkin(S.weapon, keep, S.schema[S.weapon][keep])
	elseif first then
		selectSkin(S.weapon, first.skin, first.info)
	end
end

do
	local x = 0
	local paints = {}
	for _, cat in ipairs({ "Knives", "Rifles", "Pistols", "Gloves" }) do
		local w = math.max(40, math.ceil(Kit.textWidth(cat, 11)) + 16)
		local b = Kit.new("TextButton", {
			BackgroundColor3 = KC.row,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
			Position = UDim2.fromOffset(x, 0),
			Size = UDim2.fromOffset(w, 24),
		}, catRow)
		Kit.corner(b, 6)
		local st = Kit.stroke(b, KC.lineSoft, 0.7)
		local lbl = Kit.label(b, cat, 11, KC.dim, 0, 4, 0, 16)
		lbl.Size = UDim2.new(1, 0, 0, 16)
		lbl.TextXAlignment = Enum.TextXAlignment.Center
		lbl.Font = Enum.Font.GothamBold
		paints[#paints + 1] = function()
			local on = S.cat == cat
			b.BackgroundColor3 = on and KC.white or KC.row
			lbl.TextColor3 = on and KC.bg or KC.dim
			st.Color = on and KC.white or KC.lineSoft
		end
		b.MouseButton1Click:Connect(function()
			chooseCategory(cat)
			for _, fn in ipairs(paints) do fn() end
		end)
		x += w + 5
	end
	for _, fn in ipairs(paints) do fn() end
end

local function skinButton(text, x, w, primary, fn)
	local btn = Kit.new("TextButton", {
		BackgroundColor3 = primary and KC.white or KC.row,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Position = UDim2.new(1, x, 0, 0),
		Size = UDim2.fromOffset(w, 30),
	}, actionRow)
	Kit.corner(btn, 6)
	local st = Kit.stroke(btn, primary and KC.white or KC.line, primary and 0.2 or 0.5)
	Kit.interactive(btn, st, primary and KC.white or KC.row)
	local lbl = Kit.label(btn, text, 11, primary and KC.bg or KC.text, 0, 7, 0, 16)
	lbl.Size = UDim2.new(1, 0, 0, 16)
	lbl.TextXAlignment = Enum.TextXAlignment.Center
	lbl.Font = Enum.Font.GothamBold
	btn.MouseButton1Click:Connect(fn)
	return btn, lbl
end

local skinStatus = Kit.label(actionRow, "", 11, KC.dim, 2, 8, 0, 16)
skinStatus.Size = UDim2.new(1, -420, 0, 16)

local function setSkinNote(text)
	S.skinNote = text
	Log.info("skins: " .. text)
end
setSkinNoteRef = setSkinNote

local _wearBtn, wearLbl
_wearBtn, wearLbl = skinButton("Wear: " .. cfg.wear, -414, 140, false, function()
	local idx = 1
	for i, entry in ipairs(WEARS) do
		if entry.name == cfg.wear then idx = i; break end
	end
	cfg.wear = WEARS[(idx % #WEARS) + 1].name
	saveConfig()
	wearLbl.Text = "Wear: " .. cfg.wear
	if S.sel then selectSkin(S.sel.weapon, S.sel.skin, S.sel.info) end
	if next(cfg.picks) then applyPicks() end
end)

skinButton("Reset all", -268, 84, false, function()
	table.clear(cfg.picks)
	saveConfig()
	restoreOriginals()
	setSkinNote("all picks cleared, originals restored")
	buildWeapons()
	buildGrid()
end)

skinButton("Clear", -180, 76, false, function()
	if not S.weapon then return end
	cfg.picks[pickKeyFor(S.weapon)] = nil
	saveConfig()
	restoreOriginals()
	applyPicks()
	setSkinNote("cleared " .. tostring(S.weapon))
	buildWeapons()
	buildGrid()
end)

skinButton("Apply", -98, 94, true, function()
	if not S.sel then setSkinNote("nothing selected"); return end
	local key = pickKeyFor(S.sel.weapon)
	if key == "#melee" or key == "#glove" then
		cfg.picks[key] = { name = S.sel.weapon, skin = S.sel.skin }
	else
		cfg.picks[key] = { skin = S.sel.skin }
	end
	saveConfig()
	local n = applyPicks()
	local live = reskinLive(true)
	reapplyAcrossSpawn("apply")
	setSkinNote(live > 0
		and string.format("%s | %s applied to %d live weapon(s) now", S.sel.weapon, S.sel.skin, live)
		or string.format("%s | %s saved -- lands when you next hold that weapon", S.sel.weapon, S.sel.skin))
	buildWeapons()
	buildGrid()
end)

S.live[#S.live + 1] = function()
	if not skinPage.Visible then return end
	local total = 0
	for _ in pairs(cfg.picks) do total += 1 end
	skinStatus.Text = string.format("%d pick(s) · %d live · %s", total, S.applied, S.skinNote)
end

--------------------------------------------------------------------------
-- page switching -- the kit's own tabstrip, so it matches every other module
--------------------------------------------------------------------------

W.tabstrip(panel, {
	position = UDim2.fromOffset(18, 84),
	names = { "ESP", "Skins" },
	get = function() return S.page end,
	set = function(name)
		S.page = name
		body.Visible = name == "ESP"
		skinPage.Visible = name == "Skins"
		if name == "Skins" and not S.weapon then chooseCategory(S.cat) end
	end,
})

--------------------------------------------------------------------------
-- lifecycle
--------------------------------------------------------------------------

local function panic()
	cfg.softAim = false
	for _, e in pairs(S.esp) do
		if e.hl then e.hl.Enabled = false end
		if e.bb then e.bb.Enabled = false end
		if e.nb then e.nb.Enabled = false end
	end
	restoreRivals()
	if S.fovDraw then S.fovDraw.Visible = false end
	saveConfig()
	Log.info("panic")
end

local function destroy()
	if not S.alive then return end
	S.alive = false
	for _, c in ipairs(S.conns) do pcall(function() c:Disconnect() end) end
	table.clear(S.conns)
	wipeEsp()
	restoreOriginals()
	clearPreviewModel()
	if S.fovDraw then pcall(function() S.fovDraw:Remove() end); S.fovDraw = nil end
	pcall(function() screen:Destroy() end)
	G[GKEY] = nil
	Log.info("unloaded " .. BUILD_VERSION)
end

W.footer(panel, {
	onUnload = destroy,
	onSettings = function() body.CanvasPosition = Vector2.new(0, 0) end,
	hint = "P panic  ·  K unload",
})

-- The polled sweep alone leaves a rig undrawn for up to one espHz after it
-- appears. logs/bx_tele2.log 14:22:44 caught three respawning enemies alive in
-- Workspace.Characters with no cham for exactly that window. A rig arriving is
-- an event, so listen for it instead of waiting: the handlers only raise a flag
-- and the Heartbeat below still does the work, so the sweep runs at most once
-- per frame no matter how noisy Workspace.ChildAdded is.
local wantSweep = false
local function nudge() wantSweep = true end
connect(Workspace.ChildAdded, nudge)
do
	local chars = Workspace:FindFirstChild("Characters")
	if chars then connect(chars.ChildAdded, nudge) end
	-- The folder itself is replaced between maps.
	connect(Workspace.ChildAdded, function(child)
		if child.Name == "Characters" then connect(child.ChildAdded, nudge) end
	end)
end
local function watchPlayer(plr)
	if plr == LP then return end
	connect(plr.CharacterAdded, nudge)
	connect(plr:GetAttributeChangedSignal("Team"), nudge)
end
for _, plr in ipairs(Players:GetPlayers()) do watchPlayer(plr) end
connect(Players.PlayerAdded, watchPlayer)

-- Census on OUR health dropping. There is no Humanoid on a rig in this game
-- (BLOXSTRIKE.md S1), so @Health on the model is the damage signal, and it must
-- be re-bound on every spawn because the rig is a new instance each time.
do
	local lastHp
	local function watchOwnHealth(char)
		if not char then return end
		lastHp = char:GetAttribute("Health")
		connect(char:GetAttributeChangedSignal("Health"), function()
			local hp = char:GetAttribute("Health")
			if type(hp) == "number" and type(lastHp) == "number" and hp < lastHp then
				damageCensus(hp <= 0 and "death" or string.format("hit -%d", lastHp - hp))
			end
			lastHp = hp
		end)
	end
	watchOwnHealth(LP.Character)
	connect(LP.CharacterAdded, watchOwnHealth)
end

-- A WeaponComponent is created and destroyed per equip, so a pick cannot be a
-- one-shot: the melee component simply did not exist a few seconds after the
-- last one was torn down (measured -- logs/bx_swap2.log found only the USP-S).
-- reskinLive is idempotent, so this only rebuilds a model when a component is
-- actually wearing the wrong thing, and only when a pick exists at all.
local reskinAcc = 0
connect(RunService.Heartbeat, function(dt)
	if not next(cfg.picks) then return end
	reskinAcc += dt
	if reskinAcc < 0.4 then return end
	reskinAcc = 0
	-- Cheap now: with the cache warm this is a loop over <=8 tables and no heap
	-- scan, so it can run often. It has to: a weapon deferred while holstered
	-- must swap the moment it is drawn, not two seconds later.
	reskinLive(false)
end)

local acc = 0
connect(RunService.Heartbeat, function(dt)
	acc += dt
	if wantSweep or acc >= cfg.espHz then
		wantSweep = false
		acc = 0
		sweepEsp()
	end
	for _, fn in ipairs(S.live) do pcall(fn) end
end)
-- The server rebuilds the client's inventory cache on spawn, so a saved pick
-- has to be re-written afterwards. This is a table write, not a re-arm: rung 1,
-- nothing replicates, so it resumes the user's last state (potassium-dev S0.2b).
-- TIMING IS THE WHOLE FEATURE, and one delayed write is not enough.
-- Loadout.grantPlayerInventoryItem builds a WeaponComponent ONCE per spawn and
-- passes the skin into WeaponComponent.new -> Viewmodel.new (0058.lua:39-43).
-- After that the component is reused, so switching weapons re-equips the model
-- that was already built and a later cache write changes nothing you can see.
-- Measured 2026-09-03: a pick written mid-round sat correctly in the cache
-- (logs/bx_apply_test.log, all three fields changed) while the viewmodel still
-- showed stock -- because the component predated the write.
-- So the write has to be in place BEFORE the server's CreateGameLoadout lands.
-- We cannot know that instant, so we blanket the spawn window: writes are free
-- (one table assignment, rung 1, nothing replicates), and being early is the
-- only state that matters.
connect(LP.CharacterAdded, function() reapplyAcrossSpawn("spawn") end)

connect(RunService.RenderStepped, aimStep)
connect(UserInputService.InputBegan, function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.P then panic()
	elseif input.KeyCode == Enum.KeyCode.K then destroy() end
end)
-- Hosted: the hub owns RightShift, so this is inert (hub S6.1 r4).
H.hideBind(function() panel.Visible = not panel.Visible end)

task.defer(function()
	-- Autoload: the saved preset is the state the user last chose, and this is
	-- rung 1 client-local, so it resumes ON rather than booting OFF
	-- (potassium-dev S0.2b).
	if cfg.autoPreset and cfg.preset and cfg.presets[cfg.preset] then
		presetLoad(cfg.preset)
	end
	reapplyAcrossSpawn("inject")
end)

G[GKEY] = { destroy = destroy, build = BUILD_VERSION, cfg = cfg, applySkins = applyPicks }
Log.info(string.format("boot %s hosted=%s chams=%s healthbars=%s softAim=%s cone=%ddeg strength=%d%% part=%s",
	BUILD_VERSION, tostring(H.hosted), tostring(cfg.chams), tostring(cfg.healthbars),
	tostring(cfg.softAim), cfg.aimFov, cfg.aimStrength, cfg.aimPart))
