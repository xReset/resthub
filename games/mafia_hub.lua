-- Mafia Hub v2026-10-28.1 (2026-10-28)
--
-- POSTURE (potassium-dev §5.6)
--   Rung 1 for every intel feature: it reads client state the server already
--   replicated to us. Rung 2 for the two visual features (ESP adornments we
--   create under a cloned CoreGui folder, and a local Lighting write for night
--   vision). NOTHING here fires a remote, hooks a metamethod, or writes to a
--   replicated instance, so the server sees exactly zero traffic from this file.
--
-- WHAT THE SERVER SEES: nothing. Every read below is a ClientRemoteProperty
--   :get(), which bubshayz_network serves from a locally cached value pushed by
--   the server (dump 0607.lua:37 get / :67 OnClientInvoke) -- it does NOT invoke
--   the server. Attribute reads and Workspace walks are client-local.
--
-- PROOF (dump 83705601973004 / 2026-09-03T23-44-13Z)
--   players.txt:5,41,73...   @DisguiseName is a PLAYER attribute, replicated for
--                            EVERY player. This is the identity leak the whole
--                            Roster tab is built on -- the game renames each
--                            character model to the disguise (characters.txt:
--                            a player's character path) so nobody can
--                            tell who is who, but the mapping ships to us anyway.
--   players.txt:36-66        @<Role>Boosters, @Level, @Tokens, @OwnsAdminPanel are
--                            per-player attributes too. Boosters weight the role
--                            draw server-side (no client code, so the weighting is
--                            NOT provable from the dump) -- shown as a PRIOR, never
--                            as a role.
--   trees/Workspace.txt:39110 @Dead / @Downed / @Ragdolled / @DeathPosed on the
--                            character model = alive state through walls.
--   0296.lua:26              roleService.role gives OUR role only.
--   0271.lua:350             highlightsService.highlights = userId -> {type,...},
--                            already filtered per-client by the server. Types are
--                            mafiaKill / reveal / mafiaTeam / vote (0507.lua:10-31).
--   0269.lua:931             gameService.talliedVotes = { votes = {userId -> count} }.
--   0210.lua:31              gameService.players = { {name=, alive=}, ... }.
--   0558.lua:85              serviceUtil.service(name) -- the client-side accessor.
--
-- WHAT IS NOT HERE, AND WHY
--   * No other player's ROLE. The server never sends it (0296 observes only our
--     own; the roster with a `role` field is the paid admin panel, 0409.lua:527,
--     gated by adminPanelService server-side). Do not add a fake "role ESP".
--   * No remote calls at all. gameService.votePlayer / mafia.onShoot etc. exist
--     but are rung 6 and are the one thing here that could be narrated by a victim.
--
-- ANTICHEAT (potassium-dev §0, anticheat_deep.txt)
--   CLIENT INSPECTION 0 · LOG MONITORING 0 (both hits are React noise)
--   ENFORCEMENT 2 -- 0555.lua:136 rateLimiter kicks on remote spam (we send none),
--   0485.lua:25 admin ban. REPORTING 2 -- both are role text, not a report channel.
--   A human watching you is still the real risk: ESP is invisible, but acting on
--   information you should not have is narratable. That is a play decision.
--
-- Resume rule (§0.2b): every toggle is client-only, so a saved ON comes back ON.
-- Re-inject safe: self-teardown on load. P = panic (all visuals off). K = unload.
--
-- Changelog: .1 roster intel, state/identity ESP, round readout, local night vision.

local BUILD_VERSION = "2026-10-28.1"
local GKEY = "__MAFIA_HUB"
local EXPECTED_PLACE = 83705601973004
local EXPECTED_GAME = 7497471789
if game.GameId ~= EXPECTED_GAME and game.PlaceId ~= EXPECTED_PLACE then return end

local G = getgenv()
if G[GKEY] and G[GKEY].destroy then pcall(G[GKEY].destroy) end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local CoreGui = game:GetService("CoreGui")
if type(cloneref) == "function" then local ok, copy = pcall(cloneref, CoreGui); if ok then CoreGui = copy end end
local LocalPlayer = Players.LocalPlayer
local HOST = type(G.__R3ST_HOST) == "table" and G.__R3ST_HOST or nil
local CONFIG_FILE = "mafia_hub_config.json"

local function fallbackLog(message)
	pcall(function()
		local path = "logs/mafia_hub.log"
		local old = isfile and isfile(path) and readfile(path) or ""
		writefile(path, old .. os.date("[%Y-%m-%d %H:%M:%S] ") .. tostring(message) .. "\n")
	end)
end
local Log = { info = fallbackLog }
pcall(function() Log = loadfile("log.lua")()("mafia_hub") end)

--========================================================================
-- config
--========================================================================
local defaults = {
	espChams = true, espTags = true, espDead = true, espDistance = true,
	nightVision = false, nvBrightness = 1.6,
	rosterSort = "Distance",
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

local state = { alive = true, conns = {}, live = {}, marks = {}, tags = {}, topbar = "", roster = {} }
local function connect(signal, fn)
	local c = signal:Connect(fn)
	state.conns[#state.conns + 1] = c
	return c
end

--========================================================================
-- game state readers -- all local, all pcall'd (a game update must degrade
-- the panel to "unavailable", never break the inject)
--========================================================================
local serviceUtil, rolesCfg
pcall(function() serviceUtil = require(ReplicatedStorage.shared.utilities.serviceUtil) end)
pcall(function() rolesCfg = require(ReplicatedStorage.shared.configurations.roles) end)

local function svc(name)
	if not serviceUtil then return nil end
	local ok, s = pcall(serviceUtil.service, name)
	return ok and s or nil
end
-- ClientRemoteProperty:get() is a cached local read (0607.lua:37). No traffic.
local function propGet(serviceName, propName)
	local s = svc(serviceName)
	local p = s and s[propName]
	if not p or type(p.get) ~= "function" then return nil end
	local ok, v = pcall(p.get, p)
	return ok and v or nil
end

local BOOSTER_SUFFIX = "Boosters"
-- Boosters are the only per-player signal that correlates with role. The
-- weighting is server-side and absent from the dump, so this is a PRIOR.
local function boosterPrior(player)
	local best, bestN, total = nil, 0, 0
	local ok, attrs = pcall(player.GetAttributes, player)
	if not ok or type(attrs) ~= "table" then return nil, 0, 0 end
	for key, value in next, attrs do
		if type(value) == "number" and value > 0 and #key > #BOOSTER_SUFFIX
			and string.sub(key, -#BOOSTER_SUFFIX) == BOOSTER_SUFFIX then
			total = total + value
			if value > bestN then
				bestN = value
				best = string.sub(key, 1, #key - #BOOSTER_SUFFIX)
			end
		end
	end
	return best, bestN, total
end

local function characterOf(player)
	local c = player.Character
	if c and c.Parent then return c end
	local name = player:GetAttribute("DisguiseName")
	if type(name) == "string" then
		local m = workspace:FindFirstChild(name)
		if m and m:IsA("Model") and m:FindFirstChild("Humanoid") then return m end
	end
	return nil
end

-- @Dead / @Downed live on the character model (trees/Workspace.txt:39110).
local function lifeState(character)
	if not character then return "no body" end
	if character:GetAttribute("Dead") then return "dead" end
	if character:GetAttribute("Downed") then return "downed" end
	local hum = character:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health <= 0 then return "dead" end
	return "alive"
end

local function myRole()
	local r = propGet("roleService", "role")
	if type(r) ~= "string" then return nil end
	local pretty = rolesCfg and rolesCfg[string.lower(r)] and rolesCfg[string.lower(r)].name
	return r, pretty or r
end

local function voteCounts()
	local t = propGet("gameService", "talliedVotes")
	if type(t) == "table" and type(t.votes) == "table" then return t.votes end
	return {}
end

local function highlightTags()
	local h = propGet("highlightsService", "highlights")
	return type(h) == "table" and h or {}
end

local function teamMemberSet()
	local out = {}
	for _, source in ipairs({ propGet("teamService", "teamMembers"), propGet("mafia", "teamMembers") }) do
		if type(source) == "table" then
			for _, v in next, source do
				if typeof(v) == "Instance" and v:IsA("Player") then out[v.UserId] = true
				elseif type(v) == "number" then out[v] = true
				elseif type(v) == "string" then
					local p = Players:FindFirstChild(v)
					if p then out[p.UserId] = true end
				end
			end
		end
	end
	return out
end

-- One pass, reused by the roster list, the ESP and the status rows.
local function buildRoster()
	local votes, tags, mates = voteCounts(), highlightTags(), teamMemberSet()
	local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	local out = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local character = characterOf(player)
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local best, bestN, total = boosterPrior(player)
		local tagList = tags[player.UserId] or tags[tostring(player.UserId)]
		out[#out + 1] = {
			player = player,
			me = player == LocalPlayer,
			disguise = player:GetAttribute("DisguiseName") or (character and character.Name) or "?",
			user = player.Name,
			display = player.DisplayName,
			life = lifeState(character),
			level = tonumber(player:GetAttribute("Level")) or 0,
			tokens = tonumber(player:GetAttribute("Tokens")) or 0,
			admin = player:GetAttribute("OwnsAdminPanel") == true,
			prior = best, priorN = bestN, priorTotal = total,
			tags = type(tagList) == "table" and table.concat(tagList, ",") or "",
			mate = mates[player.UserId] == true,
			votes = tonumber(votes[player.UserId]) or tonumber(votes[tostring(player.UserId)]) or 0,
			character = character,
			dist = (myRoot and root) and (myRoot.Position - root.Position).Magnitude or nil,
		}
	end
	local sort = cfg.rosterSort
	table.sort(out, function(a, b)
		if a.me ~= b.me then return a.me end
		if sort == "Name" then return a.disguise < b.disguise end
		if sort == "Votes" then return a.votes > b.votes end
		if sort == "Boosters" then return a.priorTotal > b.priorTotal end
		return (a.dist or 1e9) < (b.dist or 1e9)
	end)
	state.roster = out
	return out
end

--========================================================================
-- visuals: a plain Folder under cloned CoreGui. NEVER a ScreenGui --
-- a Highlight parented under one does not render (potassium-dev §5.4).
--========================================================================
local visuals = Instance.new("Folder")
visuals.Name = "MafiaIntel"
visuals.Parent = CoreGui

local LIFE_COLOR = {
	alive = Color3.fromRGB(235, 235, 235),
	downed = Color3.fromRGB(240, 175, 60),
	dead = Color3.fromRGB(220, 70, 70),
	["no body"] = Color3.fromRGB(120, 120, 120),
}

local function markFor(player)
	local m = state.marks[player]
	if not m then
		m = Instance.new("Highlight")
		m.Name = "MafiaCham"
		m.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		m.FillTransparency = 0.72
		m.OutlineTransparency = 0
		m.Parent = visuals
		state.marks[player] = m
	end
	return m
end

local function tagFor(player, character)
	local t = state.tags[player]
	if not t then
		t = Instance.new("BillboardGui")
		t.Name = "MafiaTag"
		t.AlwaysOnTop = true
		t.Size = UDim2.fromOffset(220, 34)
		t.StudsOffset = Vector3.new(0, 2.6, 0)
		t.Parent = visuals
		local l = Instance.new("TextLabel")
		l.Name = "L"
		l.BackgroundTransparency = 1
		l.Size = UDim2.fromScale(1, 1)
		l.Font = Enum.Font.GothamBold
		l.TextSize = 13
		l.TextStrokeTransparency = 0.4
		l.RichText = false
		l.Parent = t
		state.tags[player] = t
	end
	t.Adornee = character and character:FindFirstChild("Head") or character
	return t
end

local function refreshVisuals(roster)
	for _, row in ipairs(roster) do
		if not row.me then
			local m = markFor(row.player)
			local show = cfg.espChams and row.character ~= nil and (cfg.espDead or row.life ~= "dead")
			m.Adornee = row.character
			m.FillColor = LIFE_COLOR[row.life] or LIFE_COLOR.alive
			m.OutlineColor = row.mate and Color3.fromRGB(120, 220, 255) or Color3.new(1, 1, 1)
			m.Enabled = show

			local t = tagFor(row.player, row.character)
			local visible = cfg.espTags and row.character ~= nil and (cfg.espDead or row.life ~= "dead")
			t.Enabled = visible
			if visible then
				local line = row.disguise .. "  =  " .. row.user
				if cfg.espDistance and row.dist then line = line .. string.format("  (%.0fm)", row.dist) end
				if row.life ~= "alive" then line = line .. "  [" .. row.life .. "]" end
				if row.votes > 0 then line = line .. "  " .. row.votes .. "v" end
				t.L.Text = line
				t.L.TextColor3 = LIFE_COLOR[row.life] or LIFE_COLOR.alive
			end
		end
	end
	for player, m in next, state.marks do
		if player.Parent ~= Players then m:Destroy(); state.marks[player] = nil end
	end
	for player, t in next, state.tags do
		if player.Parent ~= Players then t:Destroy(); state.tags[player] = nil end
	end
end

--========================================================================
-- night vision: a local Lighting write. Rung 2, restored on panic/unload.
--========================================================================
local nvSaved = nil
local function applyNightVision()
	if cfg.nightVision then
		if not nvSaved then
			nvSaved = {
				Brightness = Lighting.Brightness,
				Ambient = Lighting.Ambient,
				OutdoorAmbient = Lighting.OutdoorAmbient,
				FogEnd = Lighting.FogEnd,
				ExposureCompensation = Lighting.ExposureCompensation,
			}
		end
		local lift = math.clamp(cfg.nvBrightness, 1, 3)
		local grey = math.floor(math.clamp(60 * lift, 40, 190))
		Lighting.Brightness = nvSaved.Brightness + lift
		Lighting.Ambient = Color3.fromRGB(grey, grey, grey)
		Lighting.OutdoorAmbient = Color3.fromRGB(grey, grey, grey)
		Lighting.FogEnd = math.max(nvSaved.FogEnd, 4000)
		Lighting.ExposureCompensation = nvSaved.ExposureCompensation + (lift - 1) * 0.5
	elseif nvSaved then
		for prop, value in next, nvSaved do pcall(function() Lighting[prop] = value end) end
		nvSaved = nil
	end
end

--========================================================================
-- shell
--========================================================================
local screen = Instance.new("ScreenGui")
screen.Name = "MafiaHub_" .. tostring(math.random(1000, 9999))
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.DisplayOrder = 2147483647
screen.Parent = CoreGui

local panel = Instance.new("Frame")
panel.Size = UDim2.fromOffset(780, 620)
panel.Position = UDim2.new(0.5, -390, 0.5, -310)
panel.BackgroundColor3 = Color3.fromRGB(9, 9, 11)
panel.BorderSizePixel = 0
panel.Parent = screen

local Kit = (HOST and HOST.ui) or loadfile("../scripts/r3st_ui.lua")() or loadfile("r3st_ui.lua")()
local H = Kit.host({ screen = screen, root = panel, keep = { visuals } })
local W = Kit.bind({ live = state.live, conns = state.conns, cfg = cfg, save = saveConfig })
local COL = Kit.COL

W.header(panel, {
	title = "Mafia",
	version = BUILD_VERSION,
	subtitle = "Identity, state and round intel from replicated client state",
	gameId = EXPECTED_GAME, placeId = EXPECTED_PLACE,
})

local TABS = { "Roster", "Awareness", "Round", "Settings" }
local currentTab = "Roster"
local pages, repaintTabs = {}, nil
local strip = W.tabstrip(panel, {
	position = UDim2.fromOffset(0, 80),
	names = TABS,
	get = function() return currentTab end,
	set = function(name)
		currentTab = name
		for tabName, frame in next, pages do frame.Visible = (tabName == name) end
	end,
})
strip.Parent = panel

local PAGE_W = 740
local function makePage()
	local f = Instance.new("ScrollingFrame")
	f.Position = UDim2.fromOffset(18, 122)
	f.Size = UDim2.new(1, -36, 1, -140)
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.ScrollBarThickness = 4
	f.Visible = false
	f.Parent = panel
	return f
end
for _, name in ipairs(TABS) do pages[name] = makePage() end
pages.Roster.Visible = true

--------------------------------------------------------------------------
-- Roster: the reason this module exists. One row per player, and the row
-- says who is actually behind the disguise.
--------------------------------------------------------------------------
local ROW_H, MAX_ROWS = 22, 24
local rosterRows = {}
do
	local page = pages.Roster
	W.page(page, { width = PAGE_W, columns = 1 })
	local title = W.section(page, "Who is who")
	local card = title.Parent
	local COLS = {
		{ "DISGUISE", 0, 116 }, { "USER", 118, 138 }, { "DISPLAY", 258, 108 },
		{ "STATE", 368, 56 }, { "LVL", 426, 34 }, { "PRIOR", 462, 116 },
		{ "TAGS", 580, 74 }, { "DIST", 656, 48 },
	}
	local head = Instance.new("Frame")
	head.BackgroundTransparency = 1
	head.BorderSizePixel = 0
	head.Position = UDim2.fromOffset(12, 34)
	head.Size = UDim2.new(1, -24, 0, 18)
	head.Parent = card
	for _, spec in ipairs(COLS) do
		Kit.label(head, spec[1], 9, COL.dim, spec[2], 0, spec[3], 18)
	end
	for i = 1, MAX_ROWS do
		local row = Instance.new("Frame")
		row.BackgroundTransparency = 1
		row.BorderSizePixel = 0
		row.Position = UDim2.fromOffset(12, 34 + 18 + (i - 1) * ROW_H)
		row.Size = UDim2.new(1, -24, 0, ROW_H)
		row.Visible = false
		row.Parent = card
		local cells = {}
		for c, spec in ipairs(COLS) do
			cells[c] = Kit.label(row, "", 11, COL.text, spec[2], 0, spec[3], ROW_H)
			cells[c].TextTruncate = Enum.TextTruncate.AtEnd
		end
		rosterRows[i] = { frame = row, cells = cells }
	end
	card.Size = UDim2.fromOffset(card.Size.X.Offset, 34 + 18 + MAX_ROWS * ROW_H + 12)
	page.CanvasSize = UDim2.fromOffset(0, card.Size.Y.Offset + 20)
end

local function paintRoster()
	local roster = state.roster
	for i, rec in ipairs(rosterRows) do
		local row = roster[i]
		rec.frame.Visible = row ~= nil
		if row then
			local col = LIFE_COLOR[row.life] or LIFE_COLOR.alive
			if row.me then col = Color3.fromRGB(120, 220, 255) end
			local prior = row.prior and string.format("%s x%d", row.prior, row.priorN) or "-"
			local vals = {
				row.disguise, row.user .. (row.admin and " *" or ""), row.display,
				row.life, tostring(row.level), prior,
				(row.tags ~= "" and row.tags or (row.mate and "team" or "-")),
				row.dist and string.format("%.0f", row.dist) or "-",
			}
			for c, cell in ipairs(rec.cells) do
				cell.Text = tostring(vals[c] or "")
				cell.TextColor3 = col
			end
			if row.votes > 0 then
				rec.cells[4].Text = row.life .. " " .. row.votes .. "v"
			end
		end
	end
end

--------------------------------------------------------------------------
-- Awareness
--------------------------------------------------------------------------
do
	local page = pages.Awareness
	W.page(page, { width = PAGE_W })
	W.section(page, "Through-wall")
	W.toggle(page, { label = "Chams", desc = "Outlines every character by life state: white alive, amber downed, red dead. Cyan outline = the server told us they are on your team.", key = "espChams" })
	W.toggle(page, { label = "Identity tags", desc = "Floats \"<disguise> = <username>\" over each body. The disguise is what everyone else sees; the username is who it actually is.", key = "espTags" })
	W.toggle(page, { label = "Show distance", desc = "Appends metres to the tag.", key = "espDistance" })
	W.toggle(page, { label = "Include dead bodies", desc = "Keeps corpses marked so you can find and report them.", key = "espDead" })
	W.note(page, "All of this is drawn from state the server already sent this client. Nothing is requested and nothing is sent back.")

	W.section(page, "Vision")
	W.toggle(page, { label = "Night vision", desc = "Local Lighting only: raises brightness, ambient and fog distance. Reverted exactly on unload or panic.", key = "nightVision", set = function(v) cfg.nightVision = v; applyNightVision() end })
	W.slider(page, { label = "Night vision lift", min = 1, max = 3, step = 0.1, key = "nvBrightness",
		fmt = function(v) return string.format("%.1fx", v) end,
		set = function(v) cfg.nvBrightness = v; applyNightVision() end })
	W.note(page, "A brightly lit client in a night round is invisible to the server but obvious in a clip you record. Consider it before streaming.")
	page.CanvasSize = UDim2.fromOffset(0, W.height(page) + 20)
end

--------------------------------------------------------------------------
-- Round
--------------------------------------------------------------------------
do
	local page = pages.Round
	W.page(page, { width = PAGE_W })
	W.section(page, "You")
	W.statusRow(page, function()
		local raw, pretty = myRole()
		local disguise = LocalPlayer:GetAttribute("DisguiseName") or "?"
		return string.format("Role %s  ·  Disguise %s  ·  Level %s",
			pretty or "unknown", tostring(disguise), tostring(LocalPlayer:GetAttribute("Level") or "?"))
	end)
	W.statusRow(page, function()
		local mates = teamMemberSet()
		local names = {}
		for uid in next, mates do
			local p = Players:GetPlayerByUserId(uid)
			if p and p ~= LocalPlayer then
				names[#names + 1] = (p:GetAttribute("DisguiseName") or p.Name) .. " (" .. p.Name .. ")"
			end
		end
		return "Team: " .. (#names > 0 and table.concat(names, ", ") or "none sent to this client")
	end)

	W.section(page, "Round")
	W.statusRow(page, function()
		local phase = propGet("gameService", "gamePhase")
		local started = propGet("gameService", "gameStarted")
		local alive, total = 0, 0
		for _, row in ipairs(state.roster) do
			total = total + 1
			if row.life == "alive" then alive = alive + 1 end
		end
		return string.format("Phase %s  ·  started %s  ·  alive %d/%d",
			tostring(phase or "?"), tostring(started), alive, total)
	end)
	W.statusRow(page, function() return "Topbar: " .. (state.topbar ~= "" and state.topbar or "-") end)
	W.statusRow(page, function()
		local out = {}
		for _, row in ipairs(state.roster) do
			if row.votes > 0 then out[#out + 1] = row.disguise .. " " .. row.votes end
		end
		table.sort(out)
		return "Votes: " .. (#out > 0 and table.concat(out, "  ·  ") or "none")
	end)
	W.statusRow(page, function()
		local terror = propGet("terrorService", "terror")
		local lights = propGet("gameService", "lightsToggled")
		local flashOff = propGet("flashlightService", "flashlightsDisabled")
		return string.format("Terror %s  ·  Lights %s  ·  Flashlights disabled %s",
			tostring(terror), tostring(lights), tostring(flashOff))
	end)

	W.section(page, "What the server will not tell us")
	W.note(page, "Other players' ROLES are never sent to this client -- roleService.role carries only yours. Any script claiming role ESP here is guessing.")
	W.note(page, "The PRIOR column is role boosters, a purchasable weight on the role draw. High MafiaBoosters means more likely, never confirmed.")
	page.CanvasSize = UDim2.fromOffset(0, W.height(page) + 20)
end

--------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------
do
	local page = pages.Settings
	W.page(page, { width = PAGE_W })
	W.section(page, "Roster")
	for _, mode in ipairs({ "Distance", "Name", "Votes", "Boosters" }) do
		W.button(page, "Sort by " .. mode, nil, function()
			cfg.rosterSort = mode
			saveConfig()
		end)
	end
	W.section(page, "Safety")
	W.note(page, "P disables every visual and restores Lighting. K unloads the module completely.")
	W.note(page, "This module fires no remotes. Everything it shows was already on your client; the only risk is acting on it visibly.")
	W.statusRow(page, function()
		return string.format("Build %s  ·  services %s  ·  night vision %s",
			BUILD_VERSION, serviceUtil and "bound" or "UNAVAILABLE", cfg.nightVision and "on" or "off")
	end)
	page.CanvasSize = UDim2.fromOffset(0, W.height(page) + 20)
end

--========================================================================
-- refresh loop -- ~6 Hz, well under the 10 Hz UI ceiling of §5.4
--========================================================================
local elapsed = 0
connect(RunService.Heartbeat, function(dt)
	elapsed = elapsed + dt
	if elapsed < 0.16 then return end
	elapsed = 0
	local ok, err = pcall(function()
		local roster = buildRoster()
		refreshVisuals(roster)
		if currentTab == "Roster" then paintRoster() end
		for _, fn in ipairs(state.live) do fn() end
	end)
	if not ok then Log.info("refresh error " .. tostring(err)) end
end)

pcall(function()
	local s = svc("gameService")
	if s and s.setTopbarText and type(s.setTopbarText.connect) == "function" then
		state.conns[#state.conns + 1] = s.setTopbarText:connect(function(text)
			state.topbar = tostring(text or "")
		end)
	end
end)

--========================================================================
-- lifecycle
--========================================================================
local function panic()
	cfg.espChams, cfg.espTags, cfg.nightVision = false, false, false
	applyNightVision()
	for _, m in next, state.marks do m.Enabled = false end
	for _, t in next, state.tags do t.Enabled = false end
	saveConfig()
	Log.info("panic")
end

local function destroy()
	if not state.alive then return end
	state.alive = false
	cfg.nightVision = false
	applyNightVision()
	for _, c in ipairs(state.conns) do pcall(function() c:Disconnect() end) end
	for _, m in next, state.marks do pcall(function() m:Destroy() end) end
	for _, t in next, state.tags do pcall(function() t:Destroy() end) end
	pcall(function() visuals:Destroy() end)
	pcall(function() screen:Destroy() end)
	G[GKEY] = nil
	Log.info("unloaded " .. BUILD_VERSION)
end

H.hideBind(function() panel.Visible = not panel.Visible end)
connect(UserInputService.InputBegan, function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.P then panic()
	elseif input.KeyCode == Enum.KeyCode.K then destroy() end
end)

applyNightVision()
G[GKEY] = { destroy = destroy, build = BUILD_VERSION }
Log.info(string.format("boot %s services=%s chams=%s tags=%s nv=%s",
	BUILD_VERSION, tostring(serviceUtil ~= nil), tostring(cfg.espChams), tostring(cfg.espTags), tostring(cfg.nightVision)))
