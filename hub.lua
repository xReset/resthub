-- R3ST Hub v2026-10-29.3 (2026-10-29)
-- Client UI shell. Re-inject safe; RightShift show/hide; K unload.
-- Changelog:
-- 2026-10-29.3 Manual reports send bounded build metadata, never raw logs or player identity.
-- 2026-10-29.2 Reload once after teleports (no Admin autostart); black/purple notifications.
-- 2026-10-29.1 Register Vantage ESP, held softaim and normal grounded bhop.
-- 2026-10-27.2 Add RoChess local Stockfish module; keep its backend outside the Hub.
-- 2026-10-27.1 Stage shell before teardown; honest reload readiness and opt-in frame captures.
-- 2026-10-26.13-public Keep private report destinations out of public source.
-- 2026-10-26.12-quests Ship Clover profession trials, hymn solver and quest map assistance.
-- 2026-10-26.11-studio Short full-size motion; no row scaling or per-frame minimize reflow.
-- 2026-10-26.10-studio Port approved Studio UI; preserve current game registry and controllers.
-- 2026-10-26.6 Register Bike Universe tuning, stunts and local crash guards.
-- 2026-10-26.5 Register evidence-backed Clover RPG controls and gathering.
-- 2026-10-26.9-studio Sidebar slides at fixed width; clip viewport avoids per-frame page reflow.
-- 2026-10-26.7-studio Spring window/press motion, directional pages, sliding nav and toast.
-- 2026-10-26.6-studio Hideable sidebar, category chips, two-line rows, toast, hotkeys.
-- 2026-10-26.5-studio Iris accent shell, sectioned nav, primary actions, gold stars.
-- 2026-10-26.5 Register evidence-backed Clover RPG controls and gathering.
-- 2026-10-26.4 Suspend hidden settings polling; disable zero-strength blur.
-- 2026-10-26.3 Expand Rally power/grip/brake ranges; keep speed/stability caps.
-- 2026-10-26.2 Add Rally music volume and applied-tune readouts.
-- 2026-10-26.1 Register Backseat Rally tuning and pace-note mute.
-- 2026-10-24.3 Embed Critical Strike in the hub.
-- 2026-10-24.2 Embed Gakuran, Counter Blox, Flee the Facility; drop ten modules.
-- 2026-10-24.1 Unify page layouts, kit settings, navigation and interaction motion.
-- 2026-10-20.5 Remove Combat Warriors registration.
-- 2026-10-20.2 Register Banknote ESP and WideOpen.
-- 2026-10-19.1 Register A Bizarre Day : Classic.
-- 2026-09-23.1 Register Project Slayers 2.
-- .52 Register Twisted.
-- .51 Restore Auto-start Admin setting.
-- .50 Auto-start Admin except in Critical Strike.
-- HOST-MOUNT CONTRACT (hub skill S6, migration step)
local BUILD_VERSION = "2026-10-29.3"
local Runtime
for _, path in ipairs({ "../scripts/r3st_runtime.lua", "r3st_runtime.lua", "scripts/r3st_runtime.lua" }) do
	local found, source = pcall(readfile, path)
	if found and type(source) == "string" then
		local ok, value = pcall(function() return assert(loadstring(source, "=r3st_runtime.lua"))() end)
		if ok then Runtime = value end
		break -- never fall back from broken preferred bytes
	end
end
if type(Runtime) ~= "table" or type(Runtime.boot) ~= "function" then
	pcall(writefile, "logs/r3st_reload.log", "FAILED runtime dependency; resident Hub preserved\n")
	return
end
local booted, bootError = Runtime.boot(getgenv(), "__R3ST_HUB", function(scope)
local SHELL_CONTRACT = "1"
local GKEY = "__R3ST_HUB"
local HOST_KEY = "__R3ST_HOST"
local CONFIG_FILE = "rbx_hub_template_config.json"
local UIS = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")
local Lighting = game:GetService("Lighting")
local MarketplaceService = game:GetService("MarketplaceService")
local G = getgenv()
local alive = true
local connections = {}
local screen
local destroy
local saveQueued, saveGeneration = false, 0
local favoritesMigrated = false
local rowRefresh = {} -- page name -> function, called when favorites change
local toggleShown -- show/hide the whole hub, with motion (RightShift)
local launchToast
local Log
local C
local state
local pages = {}
local navButtons = {}
local navLabels = {}
local navIcons = {}
local navOrder = {}
local setPage
local content
local sidebar
local blur
local root
scope.own(function()
	alive = false
	for _, conn in ipairs(connections) do pcall(function() conn:Disconnect() end) end
	if screen then screen:Destroy() end
	if blur then blur:Destroy() end
end)
local mountedModules = {}
local lastMounted -- the most recent one, for reload()/status() with no target
local hostMounts = {}
local hostEntries = {}
local hostAlias = {} -- lowercase id / file / name -> id
local hostPages = {} -- id -> { page, host, reload, entry }
local sessionId = HttpService:GenerateGUID(false)
local profiler = Runtime.profiler({ build = BUILD_VERSION, placeId = game.PlaceId, gameId = game.GameId,
	session = sessionId, signal = game:GetService("RunService").RenderStepped,
	write = function(sample)
		if makefolder and isfolder and not isfolder("logs") then makefolder("logs") end
		writefile("logs/r3st_perf_" .. sample.label .. ".json", HttpService:JSONEncode(sample))
	end })
scope.own(function() profiler.stop("startup failed") end)
pcall(function()
	local ok, factory = pcall(loadfile, "log.lua")
	if ok and type(factory) == "function" then
		local ok2, logger = pcall(factory, "rbx_hub")
		if ok2 and type(logger) == "table" then Log = logger end
	end
end)
local function hubLog(level, message)
	local line = ("[%s] %s %s"):format(os.date("%H:%M:%S"), BUILD_VERSION, tostring(message))
	if Log then
		if level == "warn" and Log.warn then
			Log.warn(message)
		elseif Log.info then
			Log.info(message)
		end
		return
	end
	pcall(function()
		if makefolder and isfolder and not isfolder("logs") then makefolder("logs") end
		if appendfile and isfile and isfile("logs/rbx_hub.log") then
			appendfile("logs/rbx_hub.log", line .. "\n")
		elseif writefile then
			writefile("logs/rbx_hub.log", line .. "\n")
		end
	end)
end
local function loadModule(file)
	local chunk, err, path, source = Runtime.resolve(file, readfile, loadstring)
	if chunk then hubLog("info", "resolved " .. file .. " -> " .. path .. " (" .. #source .. " bytes)") end
	return chunk, err
end
local UIKit
do
	local chunk = loadModule("r3st_ui.lua")
	if chunk then
		local ok, kit = pcall(chunk)
		if ok and type(kit) == "table" then UIKit = kit end
	end
	if UIKit then
		hubLog("info", "ui kit " .. tostring(UIKit.VERSION))
		if tostring(UIKit.SHELL_CONTRACT) ~= SHELL_CONTRACT then
			error("UI shell contract mismatch; resident Hub preserved")
		end
	else
		error("r3st_ui.lua failed to initialize; resident Hub preserved")
	end
end
UIKit.profile = profiler
C = (UIKit and UIKit.COL)
	or {
		bg = Color3.fromRGB(7, 7, 9), panel = Color3.fromRGB(13, 13, 16),
		raised = Color3.fromRGB(17, 17, 21), hover = Color3.fromRGB(24, 24, 29),
		line = Color3.fromRGB(42, 42, 50), text = Color3.fromRGB(240, 240, 245),
		dim = Color3.fromRGB(146, 146, 158), green = Color3.fromRGB(72, 205, 57),
		white = Color3.fromRGB(255, 255, 255), bad = Color3.fromRGB(255, 120, 120),
		faint = Color3.fromRGB(104, 104, 116), rowHover = Color3.fromRGB(31, 31, 37),
		card = Color3.fromRGB(17, 17, 21), row = Color3.fromRGB(24, 24, 29),
		lineSoft = Color3.fromRGB(30, 30, 36), lineStrong = Color3.fromRGB(80, 80, 96),
		good = Color3.fromRGB(72, 205, 57), warn = Color3.fromRGB(251, 191, 36),
		accent = Color3.fromRGB(84, 66, 196), accentHover = Color3.fromRGB(102, 84, 218),
		accentSoft = Color3.fromRGB(30, 24, 58), accentText = Color3.fromRGB(168, 152, 250),
	}
-- Older kits predate the accent tokens; derive them so the shell never indexes nil.
C.accent = C.accent or Color3.fromRGB(84, 66, 196)
C.accentHover = C.accentHover or Color3.fromRGB(102, 84, 218)
C.accentSoft = C.accentSoft or Color3.fromRGB(30, 24, 58)
C.accentText = C.accentText or Color3.fromRGB(168, 152, 250)
C.lineStrong = C.lineStrong or C.dim
C.warn = C.warn or Color3.fromRGB(251, 191, 36)
local FONT = (UIKit and UIKit.FONT) or {
	bold = Enum.Font.GothamBold, semi = Enum.Font.GothamMedium, body = Enum.Font.Gotham,
	heavy = Enum.Font.GothamBlack, mono = Enum.Font.Code,
}
local SPACE = (UIKit and UIKit.SPACE) or { xs = 4, sm = 8, md = 12, lg = 16, xl = 24, xxl = 32 }
local MOTION = (UIKit and UIKit.MOTION)
	or { fast = 0.18, base = 0.30, slow = 0.42, spring = 0.48, exit = 0.16 }
local function tween(obj, props, dur, style)
	if UIKit and UIKit.tween then return UIKit.tween(obj, props, dur, style) end
	for k, v in pairs(props) do
		pcall(function() obj[k] = v end)
	end
	return nil
end
-- Floating notification: one reused black card with a purple edge that fades up
-- at the bottom of the window. Runtime.notice owns its single replaceable timer.
local toastLabel, toastMark, toastEdge -- built with the window below
local function paintToast(shown, dur, text, isError)
	if text then
		local tone = isError and C.bad or C.accent
		toastLabel.Text, toastLabel.TextColor3 = text, isError and C.bad or C.text
		toastMark.BackgroundColor3, toastEdge.Color = tone, tone
	end
	if shown and not launchToast.Visible then -- enter from slightly below
		paintToast(false, 0)
		launchToast.Visible = true
	end
	local a = shown and 0 or 1
	tween(launchToast, { Position = UDim2.new(0.5, 0, 1, shown and -SPACE.xl or -SPACE.md),
		BackgroundTransparency = shown and 0.04 or 1 }, dur)
	tween(toastLabel, { TextTransparency = a }, dur)
	tween(toastMark, { BackgroundTransparency = a }, dur)
	tween(toastEdge, { Transparency = shown and 0.35 or 1 }, dur)
end
local toast = Runtime.notice({
	alive = function() return alive and launchToast ~= nil and launchToast.Parent ~= nil and toastLabel ~= nil end,
	still = function() return state.reduceMotion or (UIKit and UIKit.reduceMotion) end,
	delay = task.delay, cancel = task.cancel, enter = MOTION.fast, exit = MOTION.exit,
	paint = paintToast, done = function() launchToast.Visible = false end,
})
local setLaunchToast = toast.show
state = {
	favorites = {}, recent = {}, page = "Home", selectedGame = "Ghost Driver", windowX = 0,
	windowY = 0, windowW = 1180, windowH = 700, theme = "Midnight", blur = 5, autosave = true,
	autoOpen = true,
	autoAdmin = true, -- rejoin is automatic, so the ] bar comes back with the hub
	reduceMotion = false,
	teleportRecovery = true, -- queue one Hub reload for match/server transfers
	navHidden = false, -- Ctrl+B or the header menu button slides the sidebar away
}
local function connect(signal, fn)
	local c = signal:Connect(fn)
	connections[#connections + 1] = c
	return c
end
local function pruneConnections()
	-- Kit.bind retains this table; compact it without replacing its identity.
	local count = 0
	for _, connection in ipairs(connections) do
		local ok, live = pcall(function() return connection.Connected end)
		if not ok or live then
			count += 1
			connections[count] = connection
		end
	end
	for i = #connections, count + 1, -1 do connections[i] = nil end
end
local REGISTRY = {
	{ id = "rochess", moduleKey = "RoChess", name = "RoChess", cat = "Sports",
		placeId = 139717576471404, gameId = 10768845402, file = "rochess_hub.lua",
		embed = true, gkey = "__ROCHESS_HUB", desc = "Local Stockfish with live board recovery, Elo and move timing." },
	{ id = "bike-universe", moduleKey = "BikeUniverse", name = "Bike Universe", cat = "Vehicle",
		placeId = 98628861455414, gameId = 10768284407, file = "bike_universe_hub.lua", embed = true,
		gkey = "__BIKE_UNIVERSE_HUB",
		desc = "Saved per-bike speed, handling, suspension, wheelies, stunts and local crash guards; camera, audio and player tags.",
	},
	{ id = "backseat-rally", moduleKey = "BackseatRally", name = "Backseat Rally", cat = "Vehicle",
		placeId = 94278659624110, gameId = 10769543742, file = "backseat_rally_hub.lua", embed = true,
		gkey = "__BACKSEAT_RALLY_HUB",
		desc = "Saved per-car traction, handling, speed and pace-note narrator mute.",
	},
	{ id = "wideopen", moduleKey = "WideOpen", name = "WideOpen", cat = "Vehicle",
		placeId = 109959833715820, gameId = 10766812776, file = "wideopen_hub.lua", embed = true,
		gkey = "__WIDEOPEN_HUB",
		desc = "Saved bike tuning, wheelie limiter, vehicle contact "
			.. "guard, ECU and player-name ESP.",
	},
	{ id = "ghost-driver", moduleKey = "GhostDriver", name = "Ghost Driver", cat = "Vehicle",
		placeId = 137228775845999, gameId = 10173311467, file = "gd2.lua", embed = true,
		gkey = "__GD2",
		desc = "Vehicle tuning, handling, stance, exhaust, audio mixer and ESP.",
	},
	{ id = "blue-lock-rivals", moduleKey = "BlueLockRivals", name = "Blue Lock Rivals",
	cat = "Sports",
		placeId = 18668065416, gameId = 6325068386, file = "blr_hub.lua", embed = true,
		gkey = "__BLR_HUB",
		desc = "Cooldown bypass, shot power, ability tuning and client stamina.",
	},
	{ id = "volleyball-legends", moduleKey = "VolleyballLegends", name = "Volleyball Legends",
		cat = "Sports", placeId = 73956553001240, gameId = 6931042565, file = "vbl_hub.lua",
		embed = true,
		gkey = "__VBL_HUB",
		desc = "Directional hits, local hitbox tuning, air control and look ESP.",
	},
	{ id = "azure-latch", moduleKey = "AzureLatch", name = "Azure Latch", cat = "Sports",
		placeId = 94647229517154, gameId = 6945584306, file = "azure_latch_hub.lua", embed = true,
		gkey = "__AZURE_LATCH_HUB", desc = "Player and ball awareness from replicated match state.",
	},
	{ id = "critical-strike", moduleKey = "CriticalStrike", name = "Critical Strike",
	cat = "Fighting",
		placeId = 8246089782, gameId = 3163813433, file = "cs_admin.lua", embed = true,
		gkey = "__CS_ADMIN",
		desc = "cs_core engine: projectile guidance classes, ally assist, admin bar.",
	},
	{ id = "gakuran", moduleKey = "Gakuran", name = "Gakuran", cat = "Fighting",
		placeId = 128736949265057, gameId = 9199655655, file = "gakuran_autoparry.lua",
		embed = true, gkey = "__GAKURAN_AUTOPARRY", desc = "Windup-predictive perfect block.",
	},
	{ id = "build-a-base-rng", moduleKey = "BuildABaseRNG", name = "Build a Base RNG", cat = "RNG",
		placeId = 99108783264633, gameId = 10253235584, file = "bab_hub.lua", embed = true,
		gkey = "__BUILD_A_BASE_RNG_HUB",
		desc = "Wave combat, skill purchasing and paced roll utilities.",
	},
	{ id = "fisch", moduleKey = "Fisch", name = "Fisch", cat = "Simulator",
	placeId = 131716211654599,
		gameId = 5750914919, file = "fisch_hub.lua", embed = true, gkey = "__FISCH_HUB",
		desc = "Automatic casting, shaking and centered-bar reeling.",
	},
	{ id = "sell-ores", moduleKey = "SellOres", name = "Sell Ores", cat = "Simulator",
		placeId = 122572082932179, gameId = 10336278580, file = "sell_ores_hub.lua", embed = true,
		gkey = "__SELL_ORES_HUB",
		desc = "Auto roll with profit-aware ore buying, crate/furnace chains, upgrades and floors.",
	},
	{ id = "overhang", moduleKey = "Overhang", name = "Overhang", cat = "Adventure",
		placeId = 125633828844867, gameId = 9878210988, file = "overhang_hub.lua", embed = true,
		gkey = "__OVERHANG_HUB", desc = "Native grab assistance and client-local climbing rods.",
	},
	{ id = "illegal-soccer", moduleKey = "IllegalSoccer", name = "Illegal Soccer", cat = "Sports",
		placeId = 126987974021910, gameId = 10155360168, file = "illegal_soccer_hub.lua",
		embed = true,
		gkey = "__ILLEGALSOCCER", desc = "Client-side stamina, shot power and charge mobility.",
	},
	{ id = "runaways", moduleKey = "Runaways", name = "Runaways", cat = "Survival",
		placeId = 117311404196294, gameId = 7585140258, file = "runaways.lua", embed = true,
		gkey = "__RUNAWAYS_INTEL", desc = "Survival awareness toolkit.",
	},
	{ id = "mafia", moduleKey = "Mafia", name = "Mafia", cat = "Survival", placeId = 83705601973004,
		gameId = 7497471789, file = "mafia_hub.lua", embed = true, gkey = "__MAFIA_HUB",
		desc = "Disguise-to-username roster, life-state ESP, round and vote readout.",
	},
	{ id = "evade", moduleKey = "Evade", name = "Evade", cat = "Survival", placeId = 9872472334,
		gameId = 3647333358, file = "evade_kit.lua", embed = true, gkey = "__EVADE_KIT",
		desc = "Bhop, first-person body, revive and awareness kit.",
	},
	{ id = "vantage", moduleKey = "Vantage", name = "Vantage", cat = "Shooter",
		placeId = 9818227981, gameId = 3631977525, file = "vantage_hub.lua",
		embed = true, gkey = "__VANTAGE_HUB",
		desc = "Custom ESP, held softaim, grounded bhop and experimental spike marker.",
	},
	{ id = "counterblox", moduleKey = "Counterblox", name = "Counter Blox", cat = "Shooter",
		placeId = 301549746, gameId = 115797356, file = "counterblox_esp.lua",
		embed = true, gkey = "__CB_ESP", desc = "Player and bomb ESP.",
	},
	{ id = "cold-war", moduleKey = "ColdWar", name = "Cold War", cat = "Shooter",
		placeId = 13687899540,
		gameId = 4750561026, file = "coldwar_esp.lua", embed = true, gkey = "__COLDWAR_ESP",
		desc = "Player and mounted-MG ESP, chams, healthbars.",
	},
	{ id = "bloxstrike", moduleKey = "BloxStrike", name = "BloxStrike", cat = "Shooter",
		placeId = 114234929420007, gameId = 7633926880, file = "bloxstrike_esp.lua", embed = true,
		gkey = "__BX_ESP", desc = "Enemy ESP, soft aim, and a local skin/knife picker.",
	},
	{ id = "operation-one", moduleKey = "OperationOne", name = "Operation One", cat = "Shooter",
		placeId = 72920620366355, gameId = 8307114974, file = "operation_one_esp.lua", embed = true,
		gkey = "__OP1_ESP", desc = "Player ESP, gun duck and optional soft aim.",
	},
	{ id = "flee-facility", moduleKey = "FleeFacility", name = "Flee the Facility",
	cat = "Survival",
		placeId = 893973440, gameId = 372226183, file = "flee_facility_esp.lua",
		embed = true, gkey = "__FTF_ESP", desc = "Player and computer ESP.",
	},
	-- Lobby and level are separate places (games/dungeon-quest-reborn README:3,
	-- GameId 9931749389); the module is valid in both.
	{ id = "dungeon-quest-reborn", moduleKey = "DungeonQuestReborn", name = "Dungeon Quest Reborn",
		cat = "RPG", placeId = 77649408247578,
		placeIds = { 77649408247578, 85776757589518 }, gameId = 9931749389,
		file = "dqr_hub.lua", embed = true, gkey = "__DQR_HUB",
		desc = "Attack telegraphs, auto dodge, auto abilities, mob ESP and burst momentum dash.",
	},
	-- PlaceId from the dump named in games/other/RIVALS_SOFTAIM_SAFETY_2026-08-13.md:11.
	{ id = "rivals", moduleKey = "Rivals", name = "Rivals", cat = "Shooter",
	placeId = 117398147513099,
		gameId = 6035872082, file = "rivals_esp.lua", embed = true, gkey = "__RIVALS_ESP",
		desc = "Player ESP with guarded soft aim and backstab assist.",
	},
	{ id = "arsenal", moduleKey = "Arsenal", name = "Arsenal", cat = "Shooter", placeId = 286090429,
		gameId = 111958650, file = "arsenal_esp.lua", embed = true, gkey = "__ARSENAL_ESP",
		desc = "Player ESP, chams and healthbars.",
	},
	{ id = "project-slayers-2", moduleKey = "ProjectSlayers2", name = "Project Slayers 2",
	cat = "RPG",
		placeId = 136406881576517, gameId = 5595353122, file = "ps2_hub.lua", embed = true,
		gkey = "__PS2_HUB",
		desc = "Black Market prediction, quest item ESP, spawn alerts, "
			.. "teleports, free dash and auto block.",
	},
	{ id = "bizarre-day-classic", moduleKey = "BizarreDayClassic", name = "A Bizarre Day : Classic",
		cat = "RPG",
		placeId = 120318126233314, gameId = 969567031, file = "abd_item_esp.lua", embed = true,
		gkey = "__ABD_ITEM_ESP",
		desc = "Dropped-item ESP including Banknotes, arrows, fruits and "
			.. "masks; saved filters, music and collection sweep.",
	},
	{ id = "clover-rpg", moduleKey = "CloverRPG", name = "Clover RPG", cat = "RPG",
		placeId = 8248288152, placeIds = {8248288152, 8248164019}, gameId = 3164482049,
		file = "clover_hub.lua", embed = true, gkey = "__CLOVER_HUB",
		desc = "Mob/player/node ESP, fullbright, gathering assistants, opened-chest collection and local broom controls.",
	},
	{ id = "twisted", moduleKey = "Twisted", name = "Twisted", cat = "Survival",
	placeId = 14170731342,
		gameId = 2251388500, file = "twisted_hub.lua", embed = true, gkey = "__TWISTED_HUB",
		desc = "Tornado and storm ESP with EF ratings, chase vehicle "
			.. "readouts, sounding data and night visibility.",
	},
}
local GENERAL = {
	{ id = "anims", name = "Anims", file = "anims.lua", embed = true, gkey = "__ANIMS_GUI",
		desc = "M7-derived animation packs: 21 custom, 35 Roblox, 57 UGC, per-slot mixing.",
	},
	{ id = "admin", name = "Admin", file = "admin.lua", gkey = "Admin",
		desc = "The ] command bar backed by internal/admin_core.lua. Opens its own minimal bar.",
	},
}
local registryCount = #REGISTRY
local activeEntry
local function entryMatches(entry)
	if type(entry) ~= "table" then return false end
	if entry.gameId and entry.gameId == game.GameId then return true end
	if entry.placeId == game.PlaceId then return true end
	if type(entry.placeIds) == "table" then
		for _, id in ipairs(entry.placeIds) do
			if id == game.PlaceId then return true end
		end
	end
	return false
end
local function canLaunch(entry) return entryMatches(entry) end
for _, entry in ipairs(REGISTRY) do
	if entryMatches(entry) then
		activeEntry = entry
		break
	end
end
local function loadConfig()
	local ok, raw = pcall(readfile, CONFIG_FILE)
	if not ok then return end
	local decodedOk, saved = pcall(HttpService.JSONDecode, HttpService, raw)
	if not decodedOk or type(saved) ~= "table" then return end
	if type(saved.recent) == "table" then
		for _, id in ipairs(saved.recent) do
			if type(id) == "string" then state.recent[#state.recent + 1] = id end
		end
	end
	if type(saved.page) == "string" then state.page = saved.page end
	if type(saved.selectedGame) == "string" then state.selectedGame = saved.selectedGame end
	if type(saved.windowX) == "number" then state.windowX = saved.windowX end
	if type(saved.windowY) == "number" then state.windowY = saved.windowY end
	if saved.theme == "Midnight" or saved.theme == "Slate" or saved.theme == "Carbon" then
		state.theme = saved.theme
	end
	if type(saved.windowW) == "number" then state.windowW = math.clamp(saved.windowW, 900, 4000) end
	if type(saved.windowH) == "number" then state.windowH = math.clamp(saved.windowH, 540, 4000) end
	if type(saved.blur) == "number" then state.blur = math.clamp(saved.blur, 0, 12) end
	if type(saved.autosave) == "boolean" then state.autosave = saved.autosave end
	if type(saved.autoAdmin) == "boolean" then state.autoAdmin = saved.autoAdmin end
	if type(saved.reduceMotion) == "boolean" then state.reduceMotion = saved.reduceMotion end
	if type(saved.teleportRecovery) == "boolean" then state.teleportRecovery = saved.teleportRecovery end
	if type(saved.navHidden) == "boolean" then state.navHidden = saved.navHidden end
	if type(saved.favorites) == "table" then
		local migrated, changed = {}, false
		local byName = {}
		for _, e in ipairs(REGISTRY) do
			byName[e.name] = e.id
		end
		for key, value in pairs(saved.favorites) do
			if value then
				local id = byName[key]
				if id then
					migrated[id] = true
					changed = true
				else
					migrated[key] = true
				end
			end
		end
		state.favorites = migrated
		favoritesMigrated = changed
	end
end
local function saveConfig(force)
	if not alive or (not force and not state.autosave) then return end
	local function write()
		local ok, raw = pcall(HttpService.JSONEncode, HttpService, state)
		if not ok then return false, raw end
		return pcall(writefile, CONFIG_FILE, raw)
	end
	if force then
		local ok, reason = write()
		if ok then saveGeneration += 1; saveQueued = false end
		return ok, reason
	end
	if saveQueued then return end
	saveQueued = true
	local generation = saveGeneration
	task.delay(0.4, function()
		if not alive or generation ~= saveGeneration then return end
		saveQueued = false
		write()
	end)
end
loadConfig()
if favoritesMigrated then saveConfig(true) end
if UIKit then UIKit.reduceMotion = state.reduceMotion == true end
state.autoOpen = true
-- Set only by the queued teleport loader while it runs this file.
local handoffBoot = G.__R3ST_HANDOFF_BOOT ~= nil
local handoff = Runtime.handoff({
	globals = G, queue = Runtime.queueApi(G), write = writefile, jobId = game.JobId,
	owner = {}, token = function() return HttpService:GenerateGUID(false) end,
})
local function armHandoff()
	local ok, err = handoff.arm()
	hubLog(ok and "info" or "warn", "teleport handoff " .. (ok and "armed" or ("not armed: " .. tostring(err))))
	return ok, err
end
local entryById = {}
for _, entry in ipairs(REGISTRY) do
	entryById[entry.id] = entry
end
local function noteRecent(entry)
	local out = { entry.id }
	for _, id in ipairs(state.recent) do
		if id ~= entry.id and #out < 8 then out[#out + 1] = id end
	end
	state.recent = out
	saveConfig(true)
end
local function mk(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props or {}) do
		o[k] = v
	end
	if parent then o.Parent = parent end
	return o
end
local function round(o, px) mk("UICorner", { CornerRadius = UDim.new(0, px or 8) }, o) end
local function stroke(o, transparency)
	return mk("UIStroke", { Color = C.line, Thickness = 1, Transparency = transparency or 0 }, o)
end
local function label(parent, text, size, pos, fontSize, color, bold)
	return mk("TextLabel", {
		BackgroundTransparency = 1, Size = size, Position = pos or UDim2.new(), Text = text,
		TextColor3 = color or C.text,
		Font = bold and FONT.bold or FONT.semi,
		TextSize = fontSize or 14, TextXAlignment = Enum.TextXAlignment.Left,
	}, parent)
end
-- opts.hover / opts.edge return the hovered fill and resting edge, so primary
-- and selected surfaces keep their colour instead of falling back to grey.
local function interactive(hit, surface, base, opts)
	opts = opts or {}
	local edge = surface:FindFirstChildOfClass("UIStroke")
	local inside, down = false, false
	local function paint()
		local normal = type(base) == "function" and base() or C[base or "panel"]
		local lifted = opts.hover and opts.hover() or C.rowHover
		tween(
			surface,
			{ BackgroundColor3 = down and (opts.hover and normal or C.line)
				or (inside and lifted or normal) },
			MOTION.fast
		)
		if surface:GetAttribute("R3ST_Nav") then
			tween(surface, { BackgroundTransparency = (inside or down) and 0.3 or 1 }, MOTION.fast)
		end
		if edge then
			local rest = opts.edge and opts.edge() or C.line
			tween(edge, { Color = down and C.accent
				or (inside and (rest == C.line and C.lineStrong or rest) or rest) }, MOTION.fast)
		end
	end
	connect(hit.MouseEnter, function()
		inside = true
		paint()
	end)
	connect(hit.MouseLeave, function()
		inside = false
		down = false
		paint()
	end)
	-- Press sinks the surface; release springs it back.
	local function press(on)
		if surface.AbsoluteSize.X > 240 or surface.AbsoluteSize.Y > 80 then return end
		local s = surface:FindFirstChildOfClass("UIScale")
		if not s and not on then return end
		s = s or mk("UIScale", { Scale = 1 }, surface)
		if on then
			tween(s, { Scale = 0.98 }, 0.08)
		else
			tween(s, { Scale = 1 }, MOTION.spring, "spring")
		end
	end
	connect(hit.MouseButton1Down, function()
		down = true
		paint()
		press(true)
	end)
	connect(hit.MouseButton1Up, function()
		down = false
		paint()
		press(false)
	end)
	connect(hit.MouseLeave, function() press(false) end)
end
local function button(parent, text, size, pos)
	local b = mk("TextButton", {
		Size = size, Position = pos or UDim2.new(), BackgroundColor3 = C.panel, BorderSizePixel = 0,
		AutoButtonColor = false, Text = text, TextColor3 = C.text, Font = FONT.semi,
		TextSize = 14,
	}, parent)
	round(b, 8)
	stroke(b)
	interactive(b, b, "panel")
	return b
end
-- The one filled action per surface. Accent fill, white bold label.
local function primaryButton(parent, text, size, pos)
	local b = mk("TextButton", {
		Size = size, Position = pos or UDim2.new(), BackgroundColor3 = C.accent,
		BorderSizePixel = 0, AutoButtonColor = false, Text = text, TextColor3 = C.white,
		Font = FONT.bold, TextSize = 14,
	}, parent)
	round(b, 8)
	local edge = stroke(b)
	edge.Color = C.accent
	interactive(b, b, function() return C.accent end, {
		hover = function() return C.accentHover end,
		edge = function() return C.accent end,
	})
	return b
end
local function card(parent, size, pos, clickable, opts)
	local box = mk(clickable and "TextButton" or "Frame", {
		Size = size, Position = pos or UDim2.new(), BackgroundColor3 = C.raised,
		BorderSizePixel = 0,
		ClipsDescendants = true,
	}, parent)
	if clickable then
		box.Text = ""
		box.AutoButtonColor = false
	end
	round(box, 10)
	local edge = stroke(box)
	if opts and opts.edge then edge.Color = opts.edge() end
	if clickable then interactive(box, box, "raised", opts) end
	return box
end
local function pageHeader(parent, title, subtitle, compact)
	local inset = compact and SPACE.lg or SPACE.xl
	local top = compact and SPACE.sm or SPACE.xl
	local height = compact and 22 or 34
	label(
		parent, title, UDim2.new(1, -2 * inset, 0, height), UDim2.fromOffset(inset, top),
		compact and 17 or 27,
		C.text,
		true
	).Font = compact and FONT.bold or FONT.heavy
	local desc = label(
		parent,
		subtitle or "",
		UDim2.new(1, -2 * inset, 0, 20),
		UDim2.fromOffset(inset, top + height + (compact and 0 or SPACE.xs)), compact and 13 or 14,
		C.dim
	)
	desc.TextTruncate = Enum.TextTruncate.AtEnd
	return desc
end
local function icon(parent, name, size, col, pos, anchor)
	if not (UIKit and UIKit.icon) then return nil end
	return UIKit.icon(
		parent, name,
		{ size = size, color = col or C.dim, pos = pos, anchor = anchor }
	)
end
local function iconColor(box, col)
	if box and UIKit and UIKit.iconColor then UIKit.iconColor(box, col) end
end
local function iconSet(box, name, col)
	if box and UIKit and UIKit.iconSet then UIKit.iconSet(box, name, col) end
end
local function iconButton(parent, iconName, size, pos, col)
	local b = button(parent, "", size, pos)
	local px = math.max(12, math.min(size.X.Offset, size.Y.Offset) - 14)
	local ic = icon(b, iconName, px, col or C.dim, UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	b:SetAttribute("R3ST_Icon", iconName)
	return b, ic
end
local W_DEFAULT, H_DEFAULT = 1180, 700
local MIN_W, MIN_H = 560, 400
local SIDEBAR_W, HEADER_H = 170, 64
local W = math.max(MIN_W, math.floor(tonumber(state.windowW) or W_DEFAULT))
local H = math.max(MIN_H, math.floor(tonumber(state.windowH) or H_DEFAULT))
local CONTENT_W, BODY_H = W - SIDEBAR_W - 36, H - HEADER_H - 12
local core = CoreGui
if type(cloneref) == "function" then
	local ok, copy = pcall(cloneref, core)
	if ok and copy then core = copy end
end
screen = mk("ScreenGui", {
	Name = "RBXH_" .. tostring(math.random(1000, 9999)), ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Global, DisplayOrder = 2147483647,
}, core)
pcall(sethiddenproperty, screen, "OnTopOfCoreBlur", true)
blur = mk("BlurEffect", { Name = screen.Name .. "_Blur", Size = state.blur }, Lighting)
local shade = mk(
	"Frame",
	{ Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0 },
	screen
)
root = mk("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, state.windowX, 0.5, state.windowY),
	Size = UDim2.fromOffset(W, H), BackgroundColor3 = C.bg, BorderSizePixel = 0,
	ClipsDescendants = true,
}, shade)
round(root, 14)
stroke(root)
local function fit()
	local cam = workspace.CurrentCamera
	if not cam then return end
	local v = cam.ViewportSize
	local maxW, maxH = math.max(1, v.X - 24), math.max(1, v.Y - 24)
	local w = math.clamp(root.Size.X.Offset, math.min(MIN_W, maxW), maxW)
	local minH = root:GetAttribute("R3ST_Minimized") and HEADER_H or MIN_H
	local h = math.clamp(root.Size.Y.Offset, math.min(minH, maxH), maxH)
	root.Size = UDim2.fromOffset(w, h)
	local x = root.Position.X.Scale * v.X + root.Position.X.Offset
	local y = root.Position.Y.Scale * v.Y + root.Position.Y.Offset
	root.Position = UDim2.new(
		0.5,
		math.clamp(x, w / 2, v.X - w / 2) - v.X / 2,
		0.5,
		math.clamp(y, h / 2, v.Y - h / 2) - v.Y / 2
	)
end
fit()
if workspace.CurrentCamera then
	connect(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"), fit)
end
local header = mk("Frame", { Size = UDim2.new(1, 0, 0, 64), BackgroundTransparency = 1 }, root)
-- Mark: an accent tile with a white diamond, lit from the top-left.
local logo = mk("Frame", {
	Size = UDim2.fromOffset(32, 32), Position = UDim2.fromOffset(60, 16),
	BackgroundColor3 = C.accent, BorderSizePixel = 0,
}, header)
round(logo, 9)
mk("UIGradient", {
	Rotation = 45,
	Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(150, 150, 190)),
}, logo)
local logoGem = mk("Frame", {
	Size = UDim2.fromOffset(11, 11), AnchorPoint = Vector2.new(0.5, 0.5), Rotation = 45,
	Position = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = C.white, BorderSizePixel = 0,
}, logo)
round(logoGem, 2)
local brand = label(header, "R3ST <font transparency=\"0.45\">HUB</font>",
	UDim2.fromOffset(116, 34), UDim2.fromOffset(102, 15), 20, C.text, true)
brand.RichText = true
brand.Font = FONT.heavy
-- Session pill: which game this inject matched, with a live dot.
local experienceLabel = mk("Frame", {
	Name = "R3ST_SessionPill", AutomaticSize = Enum.AutomaticSize.X,
	Size = UDim2.fromOffset(0, 28), Position = UDim2.fromOffset(226, 18),
	BackgroundColor3 = activeEntry and C.accentSoft or C.card, BorderSizePixel = 0,
}, header)
round(experienceLabel, 13)
local pillEdge = stroke(experienceLabel)
pillEdge.Color = activeEntry and C.accent or C.line
pillEdge.Transparency = activeEntry and 0.55 or 0
mk("UIPadding", { PaddingLeft = UDim.new(0, 24), PaddingRight = UDim.new(0, 12) }, experienceLabel)
local pillDot = mk("Frame", {
	Size = UDim2.fromOffset(7, 7), AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, -13, 0.5, 0), BorderSizePixel = 0,
	BackgroundColor3 = activeEntry and C.good or C.faint,
}, experienceLabel)
round(pillDot, 4)
local pillText = label(experienceLabel,
	activeEntry and activeEntry.name or "Unsupported place",
	UDim2.fromOffset(0, 28), UDim2.new(), 13, activeEntry and C.text or C.dim, true)
pillText.AutomaticSize = Enum.AutomaticSize.X
mk("UISizeConstraint", { MaxSize = Vector2.new(320, 28) }, experienceLabel)
local minimize = iconButton(header, "minus", UDim2.fromOffset(36, 34), UDim2.new(1, -92, 0, 15))
local close, closeIcon =
	iconButton(header, "close", UDim2.fromOffset(36, 34), UDim2.new(1, -48, 0, 15))
-- Close is the only destructive header action; it warms on hover.
connect(close.MouseEnter, function() iconColor(closeIcon, C.bad) end)
connect(close.MouseLeave, function() iconColor(closeIcon, C.dim) end)
sidebar = mk("ScrollingFrame", {
	Position = UDim2.fromOffset(12, HEADER_H), Size = UDim2.new(0, SIDEBAR_W, 1, -(HEADER_H + 12)),
	BackgroundColor3 = C.panel, BorderSizePixel = 0, CanvasSize = UDim2.fromOffset(0, 510),
	Active = true, ScrollBarThickness = 2, ScrollingDirection = Enum.ScrollingDirection.Y,
	ScrollBarImageColor3 = C.lineStrong,
}, root)
round(sidebar, 12)
stroke(sidebar)
-- Animate a clipping viewport, never the width of the mounted UI itself.
-- Content uses pixel dimensions and stays right-aligned while the mask moves.
local contentViewport = mk("Frame", {
	Name = "R3ST_ContentViewport",
	Position = UDim2.fromOffset(SIDEBAR_W + 24, HEADER_H),
	Size = UDim2.new(1, -(SIDEBAR_W + 36), 1, -(HEADER_H + 12)),
	BackgroundTransparency = 1, BorderSizePixel = 0, ClipsDescendants = true,
}, root)
content = mk("Frame", {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0),
	Size = UDim2.fromOffset(CONTENT_W, BODY_H), BackgroundColor3 = C.panel,
	BorderSizePixel = 0, ClipsDescendants = true,
}, contentViewport)
round(content, 12)
stroke(content)
do
	local radius = (UIKit and UIKit.RADIUS) or { small = 6, card = 12 }
	local textSize = ((UIKit and UIKit.TYPE) or { body = 14 }).body
	launchToast = mk("Frame", {
		Name = "R3ST_Toast", AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -SPACE.md), Size = UDim2.fromOffset(0, 40),
		AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = C.bg,
		BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false, ZIndex = 60,
	}, root)
	round(launchToast, radius.card)
	toastEdge = stroke(launchToast, 1)
	toastEdge.Color = C.accent
	mk("UIPadding", {
		PaddingLeft = UDim.new(0, SPACE.md), PaddingRight = UDim.new(0, SPACE.lg),
	}, launchToast)
	mk("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, SPACE.md),
		VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder,
	}, launchToast)
	toastMark = mk("Frame", {
		Name = "Mark", Size = UDim2.fromOffset(3, 18), BackgroundColor3 = C.accent,
		BackgroundTransparency = 1, BorderSizePixel = 0, LayoutOrder = 1, ZIndex = 61,
	}, launchToast)
	round(toastMark, radius.small)
	toastLabel = mk("TextLabel", {
		Name = "Text", Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1, Text = "", TextColor3 = C.text, TextTransparency = 1,
		Font = FONT.semi, TextSize = textSize, TextTruncate = Enum.TextTruncate.AtEnd,
		LayoutOrder = 2, ZIndex = 61,
	}, launchToast)
	-- Keep the card (text + mark + padding) inside the narrowest window.
	mk("UISizeConstraint", { MaxSize = Vector2.new(MIN_W - 80, math.huge) }, toastLabel)
	scope.own(toast.cancel)
end
setPage = function(name)
	if not pages[name] then name = "Home" end
	local changed = state.page ~= name
	if name == "Home" and rowRefresh.Home then rowRefresh.Home() end
	-- Pages enter from the side of the nav they come from: down the list rises up.
	local from, to = navButtons[state.page], navButtons[name]
	local dir = (from and to and to.Position.Y.Offset < from.Position.Y.Offset) and -1 or 1
	state.page = name
	for k, p in pairs(pages) do
		local on = (k == name)
		if on and changed and UIKit and UIKit.pageIn then
			UIKit.pageIn(p, dir)
			-- One page motion keeps text sharp and avoids per-row layout callbacks.
		else
			p.Visible = on
		end
		if not on then p.Visible = false end
	end
	-- One highlight glides between nav items instead of each item blinking.
	local glide = sidebar and sidebar:FindFirstChild("R3ST_NavGlide")
	if glide and to then
		local fresh = not glide.Visible
		glide.Visible = true
		tween(glide, { Position = to.Position }, (changed and not fresh) and MOTION.spring or 0,
			"spring")
		local bar = glide:FindFirstChild("R3ST_GlideBar")
		if bar and changed then
			bar.Size = UDim2.new(0, 3, 0, 6)
			tween(bar, { Size = UDim2.new(0, 3, 0, 20) }, MOTION.spring, "spring")
		end
	end
	for k, b in pairs(navButtons) do
		local on = (k == name)
		tween(b, { BackgroundColor3 = on and C.accentSoft or C.panel,
			BackgroundTransparency = glide and 1 or 0 }, changed and MOTION.fast or 0)
		local lbl = navLabels[k]
		if lbl then
			tween(lbl, { TextColor3 = on and C.text or C.dim }, changed and MOTION.fast or 0)
			lbl.Font = on and FONT.bold or FONT.semi
		end
		iconColor(navIcons[k], on and C.accentText or C.dim)
		local mark = b:FindFirstChild("R3ST_Active")
		if mark then
			mark.Size = UDim2.new(0, 3, 0, (on and not glide) and 18 or 0)
		end
		-- The sliding highlight is enough; icons stay at their final pixel size.
	end
	saveConfig()
end
local thumbCache = {}
local thumbInFlight = {}
local function applyThumbnail(imageObj, entry)
	if entry.gameId then
		imageObj.Image = "rbxthumb://type=GameIcon&id=" .. tostring(entry.gameId) .. "&w=150&h=150"
		return
	end
	local id = entry.placeId
	if not id then return end
	local cached = thumbCache[id]
	if cached then
		imageObj.Image = cached
		return
	end
	if cached == false then return end -- looked up already, nothing usable
	local waiters = thumbInFlight[id]
	if waiters then
		waiters[#waiters + 1] = imageObj
		return
	end
	thumbInFlight[id] = { imageObj }
	task.spawn(function()
		local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, id)
		local asset = ok and type(info) == "table" and tonumber(info.IconImageAssetId)
		local value = (asset and asset > 0) and ("rbxassetid://" .. tostring(asset)) or false
		thumbCache[id] = value
		local list = thumbInFlight[id]
		thumbInFlight[id] = nil
		if not value or not list then return end
		for _, obj in ipairs(list) do
			if obj.Parent then obj.Image = value end
		end
	end)
end
local function unmountModule(id)
	local record = mountedModules[id]
	if not record then return end
	local handle = G[record.gkey]
	if type(handle) == "table" then
		local fn = handle.detach or handle.destroy or handle.unload
		if type(fn) == "function" then pcall(fn) end
	end
	local persistent = type(handle) == "table" and type(handle.detach) == "function"
	hubLog("info", (persistent and "detached " or "unmounted ") .. record.name)
	mountedModules[id] = nil
	if lastMounted and lastMounted.id == id then lastMounted = nil end
end
local function unmountAll()
	for id in pairs(mountedModules) do
		unmountModule(id)
	end
end
local function runModule(entry, host, fresh)
	local ok, err, touched = Runtime.runModule({ globals = G, entry = entry, host = host,
		fresh = fresh, load = loadModule, transport = host and {
			host = host, width = host.AbsoluteSize.X > 0 and host.AbsoluteSize.X or CONTENT_W - 24,
			height = host.AbsoluteSize.Y > 0 and host.AbsoluteSize.Y or BODY_H - 24,
			build = BUILD_VERSION, hub = "R3ST", autosave = state.autosave,
			contract = SHELL_CONTRACT, ui = UIKit, back = function() setPage("Home") end,
		} or nil })
	if not ok then
		if touched and entry.id then mountedModules[entry.id] = nil end
		hubLog("warn", entry.file .. ": " .. tostring(err)); return false, err
	end
	if host and entry.gkey then
		lastMounted = { gkey = entry.gkey, name = entry.name, id = entry.id }
		mountedModules[entry.id] = lastMounted
	end
	hubLog("info", "module mounted " .. entry.file .. "; gameplay outcomes not verified")
	if entry.placeId then noteRecent(entry) end
	return true
end
local function openGame(entry)
	if not entryMatches(entry) then
		hubLog(
			"warn",
			"launch blocked wrong place want="
				.. tostring(entry.placeId)
				.. " have="
				.. tostring(game.PlaceId)
		)
		setLaunchToast(
			"Join " .. entry.name .. " first (PlaceId " .. tostring(entry.placeId) .. ")",
			true
		)
		return false
	end
	if entry.embed and pages[entry.name] then
		setPage(entry.name)
		return true
	end
	setLaunchToast("Loading " .. entry.name .. "...", false)
	local ok, err = runModule(entry, nil)
	if not ok then
		setLaunchToast(entry.name .. ": " .. tostring(err), true)
		return false
	end
	setLaunchToast(entry.name .. " opened in its own window — RightShift hides the hub", false)
	if rowRefresh.Recent then rowRefresh.Recent() end
	return true
end
local function tryLaunch(entry, feedbackBtn, feedbackIcon)
	state.selectedGame = entry.name
	saveConfig()
	if openGame(entry) then return end
	if feedbackIcon and feedbackIcon.Parent then
		iconColor(feedbackIcon, C.bad)
		task.delay(0.8, function()
			if alive and feedbackIcon.Parent then
				iconColor(feedbackIcon, entryMatches(entry) and C.accentText or C.dim)
			end
		end)
	elseif feedbackBtn and feedbackBtn:IsA("GuiButton") then
		local old = feedbackBtn.Text
		feedbackBtn.Text = "Unavailable"
		task.delay(0.8, function()
			if alive and feedbackBtn.Parent then feedbackBtn.Text = old end
		end)
	end
end
-- Rows read as two lines: name over what it does, so the list is scannable
-- without hovering. Category and state sit right, actions at the far edge.
local ROW_H, ROW_STEP = 60, 66
local function makeGameRow(parent, entry, y, width)
	local ready = canLaunch(entry)
	local row = card(parent, UDim2.new(1, width or 0, 0, ROW_H), UDim2.fromOffset(0, y))
	if ready then row:FindFirstChildOfClass("UIStroke").Color = C.accent end
	local icon = mk("ImageLabel", {
		Size = UDim2.fromOffset(44, 44), Position = UDim2.fromOffset(8, 8),
		BackgroundColor3 = C.panel,
		BorderSizePixel = 0, ScaleType = Enum.ScaleType.Crop,
		ImageTransparency = ready and 0 or 0.35,
	}, row)
	round(icon, 9)
	applyThumbnail(icon, entry)
	local title =
		label(row, entry.name, UDim2.new(1, -340, 0, 22), UDim2.fromOffset(64, 9), 16, C.text, true)
	title.TextTruncate = Enum.TextTruncate.AtEnd
	local description = label(
		row,
		entry.desc or "",
		UDim2.new(1, -340, 0, 18), UDim2.fromOffset(64, 32), 13,
		C.dim
	)
	description.TextTruncate = Enum.TextTruncate.AtEnd
	description.Font = FONT.body
	local status = label(
		row,
		ready and "Supported here" or "Join to use",
		UDim2.fromOffset(104, 24), UDim2.new(1, -96, 0.5, 0), 13,
		ready and C.good or C.faint, ready
	)
	status.AnchorPoint = Vector2.new(1, 0.5)
	status.TextXAlignment = Enum.TextXAlignment.Right
	local category = mk("TextLabel", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -212, 0.5, 0),
		Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.accentSoft, BorderSizePixel = 0, Text = entry.cat or "",
		TextColor3 = C.accentText, Font = FONT.bold, TextSize = 12,
	}, row)
	round(category, 13)
	mk("UIPadding", { PaddingLeft = UDim.new(0, 11), PaddingRight = UDim.new(0, 11) }, category)
	local function layoutRow()
		local w = row.AbsoluteSize.X
		category.Visible = w >= 640 and (entry.cat or "") ~= ""
		status.Visible = w >= 440
		local reserve = category.Visible and 336 or (status.Visible and 212 or 100)
		title.Size = UDim2.new(1, -(64 + reserve), 0, 22)
		description.Size = UDim2.new(1, -(64 + reserve), 0, 18)
	end
	connect(row:GetPropertyChangedSignal("AbsoluteSize"), layoutRow)
	layoutRow()
	local starred = state.favorites[entry.id] and true or false
	local fav, favIcon = iconButton(
		row,
		starred and "starOn" or "star",
		UDim2.fromOffset(38, 38), UDim2.new(1, -88, 0, 11),
		starred and C.warn or C.dim
	)
	fav.ZIndex = 3
	local play, playIcon = iconButton(
		row,
		ready and "play" or "dash",
		UDim2.fromOffset(38, 38), UDim2.new(1, -46, 0, 11),
		ready and C.accentText or C.dim
	)
	play.ZIndex = 3
	if not ready then play.TextColor3 = C.dim end
	local rowHit = mk("TextButton", {
		Size = UDim2.new(1, -96, 1, 0), BackgroundTransparency = 1, BorderSizePixel = 0, Text = "",
		AutoButtonColor = false, ZIndex = 1,
	}, row)
	local function toggleFav()
		state.favorites[entry.id] = (not state.favorites[entry.id]) or nil
		local on = state.favorites[entry.id] and true or false
		if favIcon then
			iconSet(favIcon, on and "starOn" or "star", on and C.warn or C.dim)
		else
			fav.Text = ""
		end
		saveConfig(true)
		if rowRefresh.Favorites then rowRefresh.Favorites() end
		if rowRefresh.Home then rowRefresh.Home() end
	end
	connect(fav.Activated, toggleFav)
	local function launchFromRow() tryLaunch(entry, play, playIcon) end
	connect(play.Activated, launchFromRow)
	interactive(rowHit, row, "raised",
		ready and { edge = function() return C.accent end } or nil)
	connect(rowHit.Activated, launchFromRow)
	return row
end
local function scrollList(parent, pos, size)
	local list = mk("ScrollingFrame", {
		Position = pos, Size = size, BackgroundTransparency = 1, BorderSizePixel = 0, Active = true,
		ScrollingDirection = Enum.ScrollingDirection.Y, ScrollBarThickness = 3,
		ScrollBarImageColor3 = C.lineStrong, CanvasSize = UDim2.new(),
	}, parent)
	return list
end
local function emptyState(parent, title, body, iconName)
	local card = card(parent, UDim2.new(1, -SPACE.sm, 0, 96))
	-- Icon tile on the left so an empty page reads as intentional, not broken.
	local tile = mk("Frame", {
		Size = UDim2.fromOffset(40, 40), Position = UDim2.fromOffset(16, 18),
		BackgroundColor3 = C.accentSoft, BorderSizePixel = 0,
	}, card)
	round(tile, 10)
	icon(tile, iconName or "info", 20, C.accentText, UDim2.fromScale(0.5, 0.5),
		Vector2.new(0.5, 0.5))
	label(card, title, UDim2.new(1, -88, 0, 24), UDim2.fromOffset(72, 14), 16, C.text, true)
	local b = label(card, body, UDim2.new(1, -88, 0, 48), UDim2.fromOffset(72, 40), 13, C.dim)
	b.TextWrapped = true
	b.TextYAlignment = Enum.TextYAlignment.Top
	return card
end
local function newPage(name)
	local ok, p = pcall(
		function()
			return mk(
				"CanvasGroup",
				{ Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false },
				content
			)
		end
	)
	if not ok or not p then
		p = mk(
			"Frame",
			{ Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false },
			content
		)
	end
	pages[name] = p
	return p
end
local home = newPage("Home")
pageHeader(home, "Home")
local search = mk("TextBox", {
	Size = UDim2.fromOffset(240, 40), Position = UDim2.new(1, -260, 0, 18), BackgroundColor3 = C.bg,
	BorderSizePixel = 0, PlaceholderText = "Search by name, category or feature   (Ctrl+F)",
	Text = "",
	TextColor3 = C.text, PlaceholderColor3 = C.faint, Font = FONT.semi, TextSize = 15,
	ClearTextOnFocus = false,
}, home)
search.TextXAlignment = Enum.TextXAlignment.Left
mk("UIPadding", {
	PaddingLeft = UDim.new(0, 38), PaddingRight = UDim.new(0, 40),
}, search)
local searchIcon = icon(home, "search", 17, C.dim, UDim2.fromOffset(37, 76))
if searchIcon and #searchIcon:GetChildren() == 0 then
	-- Keep the glyph inside the kit icon frame when older kits lack search.
	local lens = mk("Frame", {
		Size = UDim2.fromOffset(10, 10), BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 0), BorderSizePixel = 0,
	}, searchIcon)
	round(lens, 10)
	local edge = stroke(lens)
	edge.Color = C.dim
	mk("Frame", {
		Size = UDim2.fromOffset(7, 2), Position = UDim2.fromOffset(9, 10),
		Rotation = 45, BackgroundColor3 = C.dim, BorderSizePixel = 0,
	}, searchIcon)
end
round(search, 10)
local searchEdge = stroke(search)
local searchFocused, searchHover = false, false
local function paintSearch()
	tween(searchEdge, { Color = searchFocused and C.accent
		or (searchHover and C.lineStrong or C.line) }, MOTION.fast)
	iconColor(searchIcon, searchFocused and C.accentText or C.dim)
end
connect(search.Focused, function() searchFocused = true; paintSearch() end)
connect(search.FocusLost, function() searchFocused = false; paintSearch() end)
connect(search.MouseEnter, function() searchHover = true; paintSearch() end)
connect(search.MouseLeave, function() searchHover = false; paintSearch() end)
-- Clear: appears only with a query, one click restores the full list.
local searchClear = mk("TextButton", {
	Name = "R3ST_SearchClear", Size = UDim2.fromOffset(28, 28),
	Position = UDim2.new(1, -58, 0, 76), BackgroundColor3 = C.row, BorderSizePixel = 0,
	Text = "", AutoButtonColor = false, Visible = false, ZIndex = 3,
}, home)
round(searchClear, 7)
local clearIcon = icon(searchClear, "close", 12, C.dim, UDim2.fromScale(0.5, 0.5),
	Vector2.new(0.5, 0.5))
if clearIcon then clearIcon.ZIndex = 4 end
connect(searchClear.MouseEnter, function() iconColor(clearIcon, C.text) end)
connect(searchClear.MouseLeave, function() iconColor(clearIcon, C.dim) end)
connect(searchClear.Activated, function() search.Text = "" end)
-- Category chips: one tap narrows the list; they combine with the search text.
local chipStrip = mk("ScrollingFrame", {
	Name = "R3ST_CategoryChips", Position = UDim2.fromOffset(24, 118),
	Size = UDim2.new(1, -48, 0, 34), BackgroundTransparency = 1, BorderSizePixel = 0,
	ScrollBarThickness = 0, ScrollingDirection = Enum.ScrollingDirection.X, Active = true,
	CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.X,
}, home)
mk("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8),
	SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center,
}, chipStrip)
local featured = mk("Frame", {
	Size = UDim2.new(1, -48, 0, 190), Position = UDim2.fromOffset(24, 164), BackgroundColor3 = C.bg,
	BorderSizePixel = 0,
}, home)
round(featured, 12)
stroke(featured)
icon(featured, "bolt", 17, C.accentText, UDim2.fromOffset(16, 16))
label(
	featured, "Jump back in", UDim2.fromOffset(300, 26), UDim2.fromOffset(40, 12), 18, C.text,
	true
)
local sessionDesc = label(
	featured,
	activeEntry and (activeEntry.name .. " is ready here — open its tab in the sidebar")
		or "No module matches this PlaceId. Cards below stay browsable and inert.",
	UDim2.new(1, -28, 0, 18), UDim2.fromOffset(16, 40), 13,
	C.dim
)
if activeEntry then
	local open = primaryButton(
		featured, "Open " .. activeEntry.name,
		UDim2.fromOffset(230, 38), UDim2.new(1, -246, 0, 14)
	)
	open.TextSize = 15
	connect(open.Activated, function() openGame(activeEntry) end)
end
sessionDesc.Size = UDim2.new(1, activeEntry and -270 or -28, 0, 18)
sessionDesc.TextTruncate = Enum.TextTruncate.AtEnd
local featuredScroll = mk("ScrollingFrame", {
	Position = UDim2.fromOffset(8, 68), Size = UDim2.new(1, -16, 0, 116),
	BackgroundTransparency = 1,
	BorderSizePixel = 0, ScrollBarThickness = 3, ScrollBarImageColor3 = C.lineStrong,
	ScrollingDirection = Enum.ScrollingDirection.X, Active = true, CanvasSize = UDim2.new(),
}, featured)
local function makeFeaturedCard(parent, entry, index)
	local spotlight = activeEntry and entry.id == activeEntry.id
	local x = 6 + (index - 1) * 130 + ((activeEntry and index > 1) and 116 or 0)
	local ready = canLaunch(entry)
	local card = card(parent, UDim2.fromOffset(spotlight and 240 or 124, 110),
		UDim2.fromOffset(x, 0), true,
		spotlight and { edge = function() return C.accent end } or nil)
	local thumb = mk("ImageLabel", {
		Size = UDim2.new(1, 0, 0, 82), BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Crop,
		ImageTransparency = ready and 0 or 0.35,
	}, card)
	applyThumbnail(thumb, entry)
	-- Scrim: fades the art into the card so the title never sits on a hard seam.
	local scrim = mk("Frame", {
		Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 52),
		BackgroundColor3 = C.raised, BorderSizePixel = 0,
	}, card)
	mk("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new(1, 0),
	}, scrim)
	local name =
		label(card, entry.name, UDim2.new(1, -16, 0, 22), UDim2.new(0, 8, 1, -25), 14, C.text, true)
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Active = false
	local badge = mk("TextLabel", {
		Size = UDim2.fromOffset(26, 26), Position = UDim2.new(1, -32, 0, 6),
		BackgroundColor3 = ready and C.accent or Color3.new(),
		BackgroundTransparency = ready and 0 or 0.35, Text = "",
		TextColor3 = C.white,
		Font = FONT.bold, TextSize = 12,
	}, card)
	round(badge, 13)
	badge.Active = false
	local badgeIcon = icon(
		badge,
		ready and "play" or "dash",
		12, C.white, UDim2.fromScale(0.5, 0.5),
		Vector2.new(0.5, 0.5)
	)
	if badgeIcon then badgeIcon.ZIndex = 3 end
	connect(card.Activated, function() tryLaunch(entry, card, badgeIcon) end)
	return card
end
local function refreshSession()
	for _, child in ipairs(featuredScroll:GetChildren()) do
		child:Destroy()
	end
	pruneConnections()
	local order, seen = {}, {}
	local function push(entry)
		if entry and not seen[entry.id] and #order < 6 then
			seen[entry.id] = true
			order[#order + 1] = entry
		end
	end
	push(activeEntry)
	for _, entry in ipairs(REGISTRY) do
		if state.favorites[entry.id] then push(entry) end
	end
	for _, id in ipairs(state.recent) do
		push(entryById[id])
	end
	for i, entry in ipairs(order) do
		makeFeaturedCard(featuredScroll, entry, i)
	end
	if #order == 0 then
		label(
			featuredScroll, "Star games below to pin them here.", UDim2.new(1, -24, 1, 0),
			UDim2.fromOffset(12, 0), 13,
			C.dim
		).TextWrapped =
			true
	end
	featuredScroll.CanvasSize = UDim2.fromOffset(6 + #order * 130 + (activeEntry and 116 or 0), 0)
end
rowRefresh.Home = refreshSession
refreshSession()
local resultCount = label(
	home,
	"All games · " .. tostring(registryCount),
	UDim2.fromOffset(320, 24), UDim2.fromOffset(24, 366), 15, C.text,
	true
)
local allList = scrollList(home, UDim2.fromOffset(24, 396), UDim2.new(1, -48, 1, -420))
local gameRows = {}
-- Games playable in this server float to the top; the rest keep registry order.
local homeOrder = {}
for _, entry in ipairs(REGISTRY) do
	if canLaunch(entry) then homeOrder[#homeOrder + 1] = entry end
end
for _, entry in ipairs(REGISTRY) do
	if not canLaunch(entry) then homeOrder[#homeOrder + 1] = entry end
end
for _, entry in ipairs(homeOrder) do
	gameRows[entry.name] = makeGameRow(allList, entry, 0, -8)
end
local noResults = emptyState(allList, "No matching games",
	"Try a shorter name, another category, or clear the search.", "search")
noResults.Visible = false
local homeFilter = { cat = "All", first = nil, chips = {} }
local function refreshHomeList()
	local q = string.lower(search.Text):match("^%s*(.-)%s*$")
	searchClear.Visible = search.Text ~= ""
	local y, shown = 0, 0
	homeFilter.first = nil
	for _, entry in ipairs(homeOrder) do
		local row = gameRows[entry.name]
		local hit = (homeFilter.cat == "All" or entry.cat == homeFilter.cat) and (q == ""
			or string.find(string.lower(entry.name), q, 1, true) ~= nil
			or string.find(string.lower(entry.cat or ""), q, 1, true) ~= nil
			or string.find(string.lower(entry.desc or ""), q, 1, true) ~= nil)
		row.Visible = hit
		if hit then
			homeFilter.first = homeFilter.first or entry
			row.Position = UDim2.fromOffset(0, y)
			y += ROW_STEP
			shown += 1
		end
	end
	noResults.Visible = shown == 0
	allList.CanvasSize = UDim2.fromOffset(0, shown == 0 and 100 or y)
	local scope = homeFilter.cat == "All" and "All games" or homeFilter.cat
	resultCount.Text = (shown == registryCount) and (scope .. " · " .. tostring(shown))
		or (scope .. " · " .. tostring(shown) .. " of " .. tostring(registryCount))
end
do
	local cats, counts = { "All" }, { All = registryCount }
	for _, entry in ipairs(REGISTRY) do
		local c = entry.cat or "Other"
		if not counts[c] then cats[#cats + 1] = c end
		counts[c] = (counts[c] or 0) + 1
	end
	local function paintChips()
		for name, chip in pairs(homeFilter.chips) do
			local on = name == homeFilter.cat
			tween(chip, { BackgroundColor3 = on and C.accent or C.card,
				TextColor3 = on and C.white or C.dim }, MOTION.fast)
			chip:FindFirstChildOfClass("UIStroke").Color = on and C.accent or C.line
		end
	end
	for i, name in ipairs(cats) do
		local chip = mk("TextButton", {
			Name = "R3ST_Chip_" .. name, LayoutOrder = i, Size = UDim2.fromOffset(0, 32),
			AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = C.card, BorderSizePixel = 0,
			AutoButtonColor = false, Font = FONT.bold, TextSize = 13, TextColor3 = C.dim,
			RichText = true,
			Text = name .. "  <font transparency=\"0.45\">" .. tostring(counts[name]) .. "</font>",
		}, chipStrip)
		round(chip, 16)
		stroke(chip)
		mk("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }, chip)
		homeFilter.chips[name] = chip
		connect(chip.MouseEnter, function()
			if homeFilter.cat ~= name then tween(chip, { TextColor3 = C.text }, MOTION.fast) end
		end)
		connect(chip.MouseLeave, paintChips)
		connect(chip.Activated, function()
			homeFilter.cat = (homeFilter.cat == name and name ~= "All") and "All" or name
			paintChips()
			refreshHomeList()
			allList.CanvasPosition = Vector2.new()
		end)
	end
	paintChips()
end
refreshHomeList()
connect(search:GetPropertyChangedSignal("Text"), refreshHomeList)
-- Enter launches the top match, so search works as a quick launcher.
connect(search.FocusLost, function(enter)
	if enter and search.Text ~= "" and homeFilter.first then
		tryLaunch(homeFilter.first)
	end
end)
local favPage = newPage("Favorites")
pageHeader(favPage, "Favorites", "Starred games, saved in the hub config.")
local favList = scrollList(favPage, UDim2.fromOffset(24, 96), UDim2.new(1, -48, 1, -120))
rowRefresh.Favorites = function()
	for _, child in ipairs(favList:GetChildren()) do
		child:Destroy()
	end
	pruneConnections()
	local y = 0
	for _, entry in ipairs(REGISTRY) do
		if state.favorites[entry.id] then
			makeGameRow(favList, entry, y, -8)
			y += ROW_STEP
		end
	end
	if y == 0 then
		emptyState(
			favList, "Nothing starred yet",
			"Star any game on Home. Up to six session shortcuts keep "
				.. "your current game, favorites and recent launches close.",
			"starOn"
		)
		y = 100
	end
	favList.CanvasSize = UDim2.fromOffset(0, y)
end
rowRefresh.Favorites()
local recentPage = newPage("Recent")
pageHeader(recentPage, "Recent", "Last 8 successfully loaded modules, newest first.")
local recentList = scrollList(recentPage, UDim2.fromOffset(24, 96), UDim2.new(1, -48, 1, -160))
local function refreshRecent()
	for _, child in ipairs(recentList:GetChildren()) do
		child:Destroy()
	end
	pruneConnections()
	local y = 0
	for _, id in ipairs(state.recent) do
		local entry = entryById[id]
		if entry then
			makeGameRow(recentList, entry, y, -8)
			y += ROW_STEP
		end
	end
	if y == 0 then
		emptyState(
			recentList, "No launches recorded",
			"A module is added here the moment the hub successfully "
				.. "loads it — embedded or standalone.",
			"clock"
		)
		y = 100
	end
	recentList.CanvasSize = UDim2.fromOffset(0, y)
end
refreshRecent()
rowRefresh.Recent = refreshRecent
local clearRecent =
	button(recentPage, "Clear history", UDim2.fromOffset(160, 34), UDim2.new(0, 24, 1, -52))
connect(clearRecent.Activated, function()
	state.recent = {}
	saveConfig(true)
	refreshRecent()
end)
local function makeHostPage(name, entry, subtitle)
	local p = newPage(name)
	local status = pageHeader(p, name, subtitle, true)
	status.Size = UDim2.new(1, -180, 0, 16)
	local reload = button(p, "Reload module", UDim2.fromOffset(130, 26), UDim2.new(1, -146, 0, 9))
	reload.TextSize = 13
	reload.Name = "R3ST_Reload_" .. tostring(entry.id)
	reload:SetAttribute("R3ST_Reload", tostring(entry.id))
	local host, ancestryConnection
	local function ensureHost()
		if host and host.Parent == p then return host end
		local rebuild = host ~= nil
		host = mk("Frame", {
			Name = "R3ST_Host_" .. tostring(entry.id), Position = UDim2.fromOffset(8, 46),
			Size = UDim2.new(1, -16, 1, -54), BackgroundTransparency = 1, BorderSizePixel = 0,
			ClipsDescendants = true,
		}, p)
		host:SetAttribute("R3ST_Host", tostring(entry.id))
		if ancestryConnection then ancestryConnection:Disconnect() end
		local ownedHost = host
		ancestryConnection = connect(host.AncestryChanged, function()
			if not ownedHost:IsDescendantOf(game) and mountedModules[entry.id] then
				hubLog("warn", "HOST ORPHANED for " .. tostring(entry.id))
			end
		end)
		if hostPages[entry.id] then hostPages[entry.id].host = host end
		if rebuild then
			hubLog("info", "host rebuilt for " .. tostring(entry.id) .. " (a module destroyed it)")
		end
		return host
	end
	ensureHost()
	p:SetAttribute("R3ST_HostPage", tostring(entry.id))
	hostPages[entry.id] = { page = p, host = host, reload = reload, entry = entry }
	local function mount(force)
		if mountedModules[entry.id] and not force then return true end
		status.Text = "loading " .. entry.file .. "..."
		status.TextColor3 = C.dim
		local live = ensureHost()
		local ok, err = runModule(entry, live, force and true or false)
		if ok then
			status.Text = "●  " .. entry.file .. " embedded · " .. (entry.desc or "")
			status.TextColor3 = C.good
			if rowRefresh.Recent then rowRefresh.Recent() end
		else
			status.Text = tostring(err)
			status.TextColor3 = C.bad
			-- Preserve a working panel after a compile/preflight failure.
			if #ensureHost():GetChildren() == 0 then
				emptyState(ensureHost(), "Could not load " .. entry.file, tostring(err))
			end
		end
		return ok, err
	end
	connect(reload.Activated, function() mount(true) end)
	if entry.id then
		hostMounts[entry.id] = mount
		hostEntries[entry.id] = entry
		hostAlias[tostring(entry.id):lower()] = entry.id
		hostAlias[tostring(entry.file):lower()] = entry.id
		hostAlias[tostring(entry.file):lower():gsub("%.lua$", "")] = entry.id
		hostAlias[tostring(entry.name):lower()] = entry.id
	end
	return p, mount, host
end
local mountActiveGame
if activeEntry and activeEntry.embed then
	local _, mount = makeHostPage(
		activeEntry.name, activeEntry,
		"This place matches " .. activeEntry.name .. " — its controls render inside the hub."
	)
	mountActiveGame = mount
elseif activeEntry then
	local p = newPage(activeEntry.name)
	pageHeader(p, activeEntry.name, activeEntry.desc)
	local note = label(
		p,
		"Not yet ported to the hub host — "
			.. activeEntry.file
			.. " opens its own window. Closing the hub does not close it.",
		UDim2.new(1, -48, 0, 40), UDim2.fromOffset(24, 92), 13,
		C.dim
	)
	note.TextWrapped = true
	local st = label(p, "", UDim2.new(1, -48, 0, 20), UDim2.fromOffset(24, 190), 13, C.dim)
	local go =
		button(p, "Open " .. activeEntry.name, UDim2.fromOffset(200, 38), UDim2.fromOffset(24, 142))
	local reload = button(p, "Reload module", UDim2.fromOffset(130, 24), UDim2.new(1, -146, 0, 10))
	reload.Name = "R3ST_Reload_" .. tostring(activeEntry.id)
	reload:SetAttribute("R3ST_Reload", tostring(activeEntry.id))
	local function launch()
		local ok, err = runModule(activeEntry, nil)
		st.Text = ok and (activeEntry.file .. " loaded") or tostring(err)
		st.TextColor3 = ok and C.good or C.bad
		if ok and rowRefresh.Recent then rowRefresh.Recent() end
	end
	connect(go.Activated, launch)
	connect(reload.Activated, launch)
end
local animsEntry = GENERAL[1]
local _, mountAnims = makeHostPage(
	"Anims", animsEntry,
	"Animation packs from the M7 capture. Backend unchanged; frontend is the hub's."
)
local launchAdmin
do
	local p = newPage("Admin")
	pageHeader(p, "Admin", "The ] command bar with inline completion.")
	local body = scrollList(p, UDim2.fromOffset(24, 96), UDim2.new(1, -48, 1, -120))
	local panel = card(body, UDim2.new(1, -8, 0, 226))
	local tile = mk("Frame", {
		Size = UDim2.fromOffset(44, 44), Position = UDim2.fromOffset(16, 16),
		BackgroundColor3 = C.accentSoft, BorderSizePixel = 0,
	}, panel)
	round(tile, 11)
	icon(tile, "terminal", 22, C.accentText, UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	label(panel, "Command bar", UDim2.new(1, -150, 0, 22),
		UDim2.fromOffset(74, 16), 15, C.text, true)
	local desc = label(panel, "Run commands with inline completion. Press ] to open the bar.",
		UDim2.new(1, -150, 0, 20), UDim2.fromOffset(74, 38), 13, C.dim)
	desc.TextTruncate = Enum.TextTruncate.AtEnd
	-- Keycap: the one shortcut this page exists to teach.
	local cap = mk("TextLabel", {
		Size = UDim2.fromOffset(30, 30), Position = UDim2.new(1, -46, 0, 22),
		BackgroundColor3 = C.row, BorderSizePixel = 0, Text = "]", TextColor3 = C.text,
		Font = FONT.mono, TextSize = 15,
	}, panel)
	round(cap, 7)
	local capEdge = stroke(cap)
	capEdge.Color = C.lineStrong
	local go = primaryButton(panel, "Open command bar",
		UDim2.new(0.6, -22, 0, 36), UDim2.fromOffset(16, 80))
	local reload = button(panel, "Reload Admin",
		UDim2.new(0.4, -18, 0, 36), UDim2.new(0.6, 2, 0, 80))
	local st = label(panel, "Ready to open. Admin starts only when requested.",
		UDim2.new(1, -32, 0, 34), UDim2.fromOffset(16, 128), 13, C.dim)
	st.TextWrapped = true
	body.CanvasSize = UDim2.fromOffset(0, 238)
	reload.Name = "R3ST_Reload_admin"
	reload:SetAttribute("R3ST_Reload", "admin")
	function launchAdmin(force)
		local ok, err = runModule({ name = "Admin", file = "admin.lua", gkey = "Admin", deferred = true }, nil, force)
		if not ok then
			st.Text = tostring(err)
			st.TextColor3 = C.bad
			return false
		end
		st.Text = "admin loader started — waiting for canonical core..."
		st.TextColor3 = C.dim
		task.spawn(function()
			local deadline = os.clock() + 18
			repeat
				local admin = G.Admin
				if type(admin) == "table" and admin._ready == true then
					st.Text = "Admin "
						.. tostring(admin.build or "unknown build")
						.. " ready — press ]"
					st.TextColor3 = C.good
					return
				end
				task.wait(0.25)
			until not alive or os.clock() >= deadline
			if alive then
				st.Text = "Admin core did not become ready — check logs/admin.log"
				st.TextColor3 = C.bad
			end
		end)
		return true
	end
	connect(go.Activated, function() launchAdmin(false) end)
	connect(reload.Activated, function() launchAdmin(true) end)
	-- Safety note in its own warm strip so it is read, not skimmed past.
	local warnStrip = mk("Frame", {
		Size = UDim2.new(1, -32, 0, 30), Position = UDim2.fromOffset(16, 178),
		BackgroundColor3 = C.row, BorderSizePixel = 0,
	}, panel)
	round(warnStrip, 8)
	mk("Frame", {
		Size = UDim2.new(0, 3, 1, -12), Position = UDim2.fromOffset(6, 6),
		BackgroundColor3 = C.warn, BorderSizePixel = 0,
	}, warnStrip)
	label(
		warnStrip, "Critical Strike: open manually; never autoexec Admin.",
		UDim2.new(1, -24, 1, 0), UDim2.fromOffset(18, 0), 13,
		C.text
	)
end
local settings = newPage("Settings")
pageHeader(settings, "Settings", "Appearance and shared configuration policy.")
local settingsScroll =
	scrollList(settings, UDim2.fromOffset(SPACE.xl, 96), UDim2.new(1, -2 * SPACE.xl, 1, -120))
local function applyTheme(name)
	-- RGB ladders: bg, panel, raised, row, line, rowHover, lineSoft, lineStrong.
	-- Midnight is the kit's own cool graphite; Slate leans blue; Carbon is neutral.
	local LADDERS = {
		Midnight = { { 9, 9, 13 }, { 17, 17, 23 }, { 26, 26, 35 }, { 37, 37, 49 }, { 50, 50, 66 },
			{ 49, 49, 64 }, { 36, 36, 48 }, { 86, 88, 112 } },
		Slate = { { 16, 19, 26 }, { 24, 28, 38 }, { 33, 38, 51 }, { 44, 50, 66 }, { 60, 68, 88 },
			{ 56, 64, 83 }, { 42, 48, 63 }, { 98, 108, 136 } },
		Carbon = { { 10, 10, 10 }, { 19, 19, 19 }, { 28, 28, 28 }, { 39, 39, 39 }, { 54, 54, 54 },
			{ 51, 51, 51 }, { 37, 37, 37 }, { 92, 92, 92 } },
	}
	local ladder = LADDERS[name]
	if not ladder then
		name = "Midnight"
		ladder = LADDERS.Midnight
	end
	local function rgb(t) return Color3.fromRGB(t[1], t[2], t[3]) end
	local old, nextPalette = {}, {}
	for k, v in pairs(C) do
		old[k] = v
		nextPalette[k] = v
	end
	for i, k in ipairs({ "bg", "panel", "raised", "row", "line", "rowHover", "lineSoft",
		"lineStrong" }) do
		nextPalette[k] = rgb(ladder[i])
	end
	nextPalette.card = nextPalette.raised
	nextPalette.hover = nextPalette.row
	for _, obj in ipairs(root:GetDescendants()) do
		for _, prop in ipairs({
			"BackgroundColor3", "TextColor3", "PlaceholderColor3", "ImageColor3",
			"ScrollBarImageColor3",
			"Color",
		}) do
			local ok, value = pcall(function() return obj[prop] end)
			if ok and typeof(value) == "Color3" then
				for _, key in ipairs({
					"bg", "panel", "raised", "card", "row", "line", "lineSoft", "hover", "rowHover",
					"lineStrong",
				}) do
					if old[key] == value then
						obj[prop] = nextPalette[key]
						break
					end
				end
			end
		end
	end
	for k, v in pairs(nextPalette) do
		C[k] = v
	end
	root.BackgroundColor3 = C.bg
	state.theme = name
end
if UIKit then
	local widgets = UIKit.bind({
		conns = connections, live = {}, cfg = state,
		isVisible = function() return UIKit.isVisible(settingsScroll) end,
		save = function()
			if alive then saveConfig(true) end
		end,
	})
	widgets.page(settingsScroll, { width = CONTENT_W - 2 * SPACE.xl, columns = 1 })
	widgets.section(settingsScroll, "Appearance")
	local themeRow = widgets.note(settingsScroll, "")
	local segments = widgets.segmented(themeRow, {
		names = { "Midnight", "Slate", "Carbon" },
		get = function() return state.theme end,
		set = function(name)
			applyTheme(name)
			saveConfig(true)
		end,
	})
	local index = 0
	for _, child in ipairs(segments:GetChildren()) do
		if child:IsA("TextButton") then
			child.Position = UDim2.new(index / 3, 2, 0, 0)
			child.Size = UDim2.new(1 / 3, -4, 0, 26)
			index += 1
		end
	end
	widgets.slider(settingsScroll, {
		label = "Blur strength", key = "blur", min = 0, max = 12, step = 1,
		get = function() return state.blur end,
		set = function(value)
			state.blur = value
			blur.Size = value
			blur.Enabled = value > 0 and root.Visible and not root:GetAttribute("R3ST_Minimized")
		end,
	})
	local rows = {
		{
			section = "Appearance", label = "Reduce motion", key = "reduceMotion",
			desc = "Apply panels and switches instantly.",
			apply = function(value) UIKit.reduceMotion = value end,
		},
		{
			section = "Appearance", label = "Hide sidebar", key = "navHidden",
			desc = "Give pages the full width. Ctrl+B or the menu button flips it.",
			apply = function()
				local toggle = header:FindFirstChild("ToggleNavigation")
				if toggle then
					toggle:SetAttribute("R3ST_Layout", (toggle:GetAttribute("R3ST_Layout") or 0) + 1)
				end
			end,
		},
		{
			section = "Configuration", label = "Autosave", key = "autosave",
			desc = "Hub and modules keep separate config files.",
		},
		{
			section = "Configuration", label = "Auto-start Admin", key = "autoAdmin",
			desc = "Start the command bar on inject. Critical Strike stays manual.",
		},
		{
			section = "Configuration", label = "Reload after teleport", key = "teleportRecovery",
			desc = "Match and server transfers reopen the Hub and this game's module once.",
			apply = function(value)
				if value then return armHandoff() end
				handoff.disarm(true)
			end,
			ready = function() return handoff.status(state.teleportRecovery) end,
		},
	}
	local section = "Appearance"
	for _, row in ipairs(rows) do
		if row.section ~= section then
			section = row.section
			widgets.section(settingsScroll, section)
		end
		local box = widgets.toggle(
			settingsScroll,
			{ label = row.label, desc = row.desc, key = row.key, set = row.apply, ready = row.ready }
		)
		for _, child in ipairs(box:GetChildren()) do
			if child:IsA("TextLabel") and child.Text == row.label then
				child.TextColor3 = C.text
				connect(child:GetPropertyChangedSignal("TextColor3"), function()
					if child.TextColor3 ~= C.text then child.TextColor3 = C.text end
				end)
			end
		end
	end
	widgets.note(settingsScroll, "Matching game modules open automatically on every inject.")
	widgets.button(
		settingsScroll, "Save configuration", "Save hub settings now.",
		function() saveConfig(true) end,
		true
	)
	widgets.button(settingsScroll, "Reset hub layout", "Reset window size and position.", function()
		state.windowX, state.windowY = 0, 0
		root.Position = UDim2.fromScale(0.5, 0.5)
		root.Size = UDim2.fromOffset(W_DEFAULT, H_DEFAULT)
		fit()
		state.windowW, state.windowH = root.Size.X.Offset, root.Size.Y.Offset
		saveConfig(true)
	end, true)
else
	emptyState(settingsScroll, "UI kit unavailable", "Restore r3st_ui.lua to edit hub settings.")
	settingsScroll.CanvasSize = UDim2.fromOffset(0, 100)
end
local about = newPage("About")
pageHeader(about, "About")
local aboutBody =
	scrollList(about, UDim2.fromOffset(SPACE.xl, 72), UDim2.new(1, -2 * SPACE.xl, 1, -96))
do
	local facts = {
		{ "Hub build", BUILD_VERSION },
		{ "This PlaceId", tostring(game.PlaceId) },
		{
			"Matched module",
			activeEntry and (activeEntry.name .. "  ·  " .. activeEntry.file)
				or "none — browser is inert here",
		},
		{ "Registry", tostring(registryCount) .. " games · Admin + Anims general tools" },
		{
			"Embedded here",
			(activeEntry and activeEntry.embed) and "yes (renders in this window)"
				or "no (module opens standalone)",
		},
		{ "Config", CONFIG_FILE },
		{ "Log", "logs/rbx_hub.log" },
		{ "Keys", "RightShift show/hide  ·  K unload hub and any embedded module" },
		{ "Posture", "Rung 2 — client-created UI only. No remotes, no game state." },
	}
	local y = 0
	for _, f in ipairs(facts) do
		label(aboutBody, f[1], UDim2.fromOffset(180, 22), UDim2.fromOffset(0, y), 14, C.dim, true)
		local v =
			label(aboutBody, f[2], UDim2.new(1, -176, 0, 22), UDim2.fromOffset(176, y), 14, C.text)
		v.TextTruncate = Enum.TextTruncate.AtEnd
		y += 28
	end
	label(
		aboutBody,
		"Modules stay separate files in git; the hub is one "
			.. "entry point, not one implementation file.",
		UDim2.new(1, -8, 0, 20), UDim2.fromOffset(0, y + 12), 12,
		C.dim
	)
	local statusPanel = mk("Frame", {
		BackgroundColor3 = C.bg, BorderSizePixel = 0, Position = UDim2.fromOffset(0, y + 40),
		Size = UDim2.new(1, -8, 0, 108),
	}, aboutBody)
	round(statusPanel, 10)
	stroke(statusPanel)
	local statusBox = label(statusPanel, "", UDim2.new(1, -24, 1, -24),
		UDim2.fromOffset(12, 12), 13, C.dim)
	statusBox.Font = FONT.mono
	statusBox.TextYAlignment = Enum.TextYAlignment.Top
	local function refreshStatus()
		local api = G[GKEY]
		if not (api and type(api.status) == "function") then
			statusBox.Text = "status unavailable"
			return
		end
		local ok, text = pcall(api.status)
		statusBox.Text = (ok and tostring(text)) or "status unavailable"
	end
	local refreshBtn =
		button(aboutBody, "Refresh status", UDim2.fromOffset(150, 30), UDim2.fromOffset(0, y + 156))
	connect(refreshBtn.Activated, refreshStatus)
	local copyBtn =
		button(aboutBody, "Copy status", UDim2.fromOffset(140, 30), UDim2.fromOffset(160, y + 156))
	connect(copyBtn.Activated, function()
		if type(setclipboard) == "function" then
			pcall(setclipboard, statusBox.Text)
			copyBtn.Text = "Copied"
			task.delay(1, function()
				if alive then copyBtn.Text = "Copy status" end
			end)
		else
			copyBtn.Text = "No clipboard"
		end
	end)
	task.defer(function()
		if alive then refreshStatus() end
	end)
	y = y + 196
	local send = primaryButton(
		aboutBody, "Send report to the developer", UDim2.fromOffset(260, 32),
		UDim2.fromOffset(0, y + 8)
	)
	local result = label(
		aboutBody,
		"Sends build stamps and game/place IDs only. No player identity, notes or logs. "
			.. "Only sends when you click and a private HTTPS destination is configured.",
		UDim2.new(1, -8, 0, 30), UDim2.fromOffset(0, y + 46), 12,
		C.dim
	)
	result.TextWrapped = true
	connect(send.Activated, function()
		result.Text = "sending..."
		task.spawn(function()
			local api = G[GKEY]
			if not api or not api.report then
				result.Text = "report unavailable in this build"
				return
			end
			local ok, msg = api.report()
			result.Text = (ok and "sent — thank you. " or "could not send — ") .. tostring(msg)
		end)
	end)
	local capture = button(aboutBody, "Capture frames (30s)", UDim2.fromOffset(200, 30), UDim2.fromOffset(0, y + 100))
	local stop = button(aboutBody, "Stop capture", UDim2.fromOffset(140, 30), UDim2.fromOffset(210, y + 100))
	connect(capture.Activated, function()
		local ok, message = profiler.start("manual", 30, { page = state.page, shown = screen.Enabled })
		result.Text = (ok and "" or "Blocked: ") .. message .. "; logs/r3st_perf_manual.json"
	end)
	connect(stop.Activated, function() profiler.stop(); result.Text = profiler.status() end)
	label(aboutBody, "Opt-in frame timing only. No game actions; compare the same scene and settings.",
		UDim2.new(1, -8, 0, 30), UDim2.fromOffset(0, y + 138), 12, C.dim)
	aboutBody.CanvasSize = UDim2.fromOffset(0, y + 184)
end
do
	-- Each group opens with a small-caps heading instead of a bare rule, so the
	-- sidebar reads as Playing / Library / Tools / Hub at a glance.
	if activeEntry then
		navOrder[#navOrder + 1] = { "", "-", "PLAYING" }
		navOrder[#navOrder + 1] = { "dot", activeEntry.name }
	end
	for _, group in ipairs({
		{ "LIBRARY", { "home", "Home" }, { "starOn", "Favorites" }, { "clock", "Recent" } },
		{ "TOOLS", { "terminal", "Admin" }, { "anims", "Anims" } },
		{ "HUB", { "gear", "Settings" }, { "info", "About" } },
	}) do
		navOrder[#navOrder + 1] = { "", "-", group[1] }
		for i = 2, #group do
			navOrder[#navOrder + 1] = group[i]
		end
	end
	local y = 6
	local glide = mk("Frame", {
		Name = "R3ST_NavGlide", Size = UDim2.new(1, -18, 0, 40), Position = UDim2.fromOffset(9, 0),
		BackgroundColor3 = C.accentSoft, BorderSizePixel = 0, Visible = false, ZIndex = 1,
	}, sidebar)
	round(glide, 9)
	round(mk("Frame", {
		Name = "R3ST_GlideBar", BackgroundColor3 = C.accent, BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.new(0, 3, 0, 20), ZIndex = 1,
	}, glide), 2)
	for _, item in ipairs(navOrder) do
		if item[2] == "-" then
			local heading = label(sidebar, item[3] or "", UDim2.new(1, -40, 0, 16),
				UDim2.fromOffset(20, y + 12), 11, C.faint, true)
			heading.Name = "R3ST_NavHeading"
			y += 34
		else
			local b = mk("TextButton", {
				Size = UDim2.new(1, -18, 0, 40), Position = UDim2.fromOffset(9, y),
				BackgroundColor3 = C.panel,
				BorderSizePixel = 0, Text = "", TextColor3 = C.dim, Font = FONT.semi,
				TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left, AutoButtonColor = false,
			}, sidebar)
			round(b, 9)
			local navIcon =
				icon(b, item[1], 17, C.dim, UDim2.new(0, 12, 0.5, 0), Vector2.new(0, 0.5))
			local navText =
				label(b, item[2], UDim2.new(1, -46, 1, 0), UDim2.fromOffset(38, 0), 15, C.dim)
			navText.TextYAlignment = Enum.TextYAlignment.Center
			navText.TextTruncate = Enum.TextTruncate.AtEnd
			navText.Active = false
			if not navIcon then navText.Position = UDim2.fromOffset(11, 0) end
			b:SetAttribute("R3ST_Nav", item[2])
			navLabels[item[2]] = navText
			navIcons[item[2]] = navIcon
			mk("Frame", {
				Name = "R3ST_Active", BackgroundColor3 = C.accent, BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, -6, 0.5, 0),
				Size = UDim2.new(0, 3, 0, 0),
			}, b)
			round(b:FindFirstChild("R3ST_Active"), 2)
			interactive(b, b, function() return state.page == item[2] and C.accentSoft or C.panel end, {
				hover = function() return state.page == item[2] and C.accentSoft or C.row end,
				edge = function() return C.line end,
			})
			navButtons[item[2]] = b
			connect(b.Activated, function() setPage(item[2]) end)
			y += 44
		end
	end
	mk("Frame", {
		Size = UDim2.new(1, -24, 0, 1), Position = UDim2.fromOffset(SPACE.md, y + SPACE.md),
		BackgroundColor3 = C.lineSoft, BorderSizePixel = 0,
	}, sidebar)
	local dot = mk("Frame", {
		Size = UDim2.fromOffset(8, 8), Position = UDim2.fromOffset(20, y + 34),
		BackgroundColor3 = activeEntry and C.good or C.faint, BorderSizePixel = 0,
	}, sidebar)
	round(dot, 4)
	label(
		sidebar,
		activeEntry and "Module available" or "No module here",
		UDim2.fromOffset(130, 18), UDim2.fromOffset(36, y + 29), 13,
		activeEntry and C.good or C.dim, true
	)
	-- Shortcut legend: the hub's hotkeys are otherwise invisible.
	local keys = label(
		sidebar,
		"Ctrl+B  sidebar\nCtrl+F  search\nRShift  hide hub",
		UDim2.fromOffset(140, 50), UDim2.fromOffset(20, y + 54), 12,
		C.dim
	)
	keys.TextYAlignment = Enum.TextYAlignment.Top
	keys.LineHeight = 1.15
	label(
		sidebar,
		"build " .. BUILD_VERSION,
		UDim2.fromOffset(140, 16), UDim2.fromOffset(20, y + 110), 11,
		C.faint or C.dim
	).Font = FONT.mono
	sidebar.CanvasSize = UDim2.fromOffset(0, y + 136)
end
do
	local VirtualUser = game:GetService("VirtualUser")
	local function pulse(reason)
		pcall(function()
			VirtualUser:CaptureController()
			VirtualUser:ClickButton2(Vector2.new())
			hubLog("info", "anti-idle " .. reason)
		end)
	end
	local LP = game:GetService("Players").LocalPlayer
	if LP then connect(LP.Idled, function() pulse("idled") end) end
	task.spawn(function()
		while alive do
			task.wait(300 + math.random(0, 180)) -- 5-8 min, uneven
			if not alive then break end
			pulse("periodic")
		end
	end)
	hubLog("info", "anti-idle armed (always-on, no toggle)")
end
destroy = function()
	if not alive then return end
	if saveQueued then saveConfig(true) end
	profiler.stop("Hub unloaded")
	alive = false
	toast.cancel()
	if handoff.disarm() then hubLog("info", "teleport handoff voided by unload") end -- no-op if a replacement owns it
	unmountAll()
	for _, c in ipairs(connections) do
		pcall(function() c:Disconnect() end)
	end
	if screen then screen:Destroy() end
	if blur then blur:Destroy() end
	if G[GKEY] and G[GKEY].destroy == destroy then G[GKEY] = nil end
	G[HOST_KEY] = nil
end
local RELOAD_LOG = "logs/r3st_reload.log"
local function reloadWrite(text)
	pcall(function()
		if makefolder and isfolder and not isfolder("logs") then makefolder("logs") end
		if appendfile and isfile and isfile(RELOAD_LOG) then
			appendfile(RELOAD_LOG, text)
		else
			writefile(RELOAD_LOG, text)
		end
	end)
end
local function reloadResult(text)
	reloadWrite(("[%s] %s\n"):format(os.date("%H:%M:%S"), text))
	hubLog("info", "reload: " .. text)
	return text
end
local function reloadTargets()
	local out = { "hub" }
	for id in pairs(hostMounts) do
		out[#out + 1] = id
	end
	table.sort(out)
	return out
end
local function reloadHub()
	local chunk, err = loadModule("hub.lua")
	if not chunk then
		return reloadResult(
			"FAILED hub: " .. tostring(err) .. " (still running " .. BUILD_VERSION .. ")"
		)
	end
	local ok, successor = pcall(chunk)
	if not ok or type(successor) ~= "table" or successor == G[GKEY] and successor.destroy == destroy
		or successor.ready ~= true then
		return reloadResult("FAILED hub startup: " .. tostring(successor))
	end
	return reloadResult("OK hub ready build " .. tostring(successor.build))
end
local function reloadModule(target)
	local id = hostAlias[tostring(target):lower()]
	local mount = id and hostMounts[id]
	if not mount then
		return reloadResult(
			("FAILED unknown target '%s' -- have: %s"):format(
				tostring(target),
				table.concat(reloadTargets(), ", ")
			)
		)
	end
	local ran, ok, err = pcall(mount, true)
	if not ran then return reloadResult("FAILED " .. id .. " remount threw: " .. tostring(ok)) end
	if not ok then return reloadResult("FAILED " .. id .. ": " .. tostring(err)) end
	local entry = hostEntries[id]
	local handle = entry and G[entry.gkey]
	return reloadResult(
		("OK %s remounted from disk, build %s"):format(
			id,
			(type(handle) == "table" and tostring(handle.build)) or "unreported"
		)
	)
end
local function hubStatus()
	local lines = {
		"hub build " .. BUILD_VERSION,
		"mounted: " .. (function()
			local names = {}
			for id, rec in pairs(mountedModules) do
				names[#names + 1] = tostring(id) .. " / " .. rec.name
			end
			table.sort(names)
			return #names > 0 and table.concat(names, ", ") or "none"
		end)(),
		"place " .. tostring(game.PlaceId) .. " universe " .. tostring(game.GameId),
		"targets: " .. table.concat(reloadTargets(), ", "),
		"teleport: " .. select(2, handoff.status(state.teleportRecovery)) .. (handoffBoot and " (this Hub came from a handoff)" or ""),
	}
	for _, id in ipairs(reloadTargets()) do
		local entry = hostEntries[id]
		if entry then
			local handle = G[entry.gkey]
			lines[#lines + 1] = ("  %s (%s) build %s"):format(
				id, entry.file,
				(type(handle) == "table" and tostring(handle.build)) or "not loaded"
			)
		end
	end
	local text = table.concat(lines, "\n")
	reloadWrite(("[%s] status\n%s\n"):format(os.date("%H:%M:%S"), text))
	return text
end
local function hubInspect()
	local targets = {}
	for id, rec in pairs(hostPages) do
		local roots = {}
		local handle = rec.entry and G[rec.entry.gkey]
		if rec.host and rec.host.Parent then
			for _, child in ipairs(rec.host:GetChildren()) do
				if child:IsA("GuiObject") and child:GetAttribute("R3ST_ModuleRoot") ~= nil then
					roots[#roots + 1] = child
				end
			end
		end
		targets[id] = {
			id = id, name = rec.entry and rec.entry.name or id,
			file = rec.entry and rec.entry.file or nil,
			page = rec.page, host = rec.host, reload = rec.reload, roots = roots,
			mounted = mountedModules[id] ~= nil,
			build = type(handle) == "table" and handle.build or nil,
			ready = mountedModules[id] ~= nil and Runtime.mounted(handle, rec.host) == true,
			visible = rec.page and rec.page.Visible == true or false,
		}
	end
	return {
		contract = SHELL_CONTRACT, kitContract = UIKit and tostring(UIKit.SHELL_CONTRACT) or nil,
		kitVersion = UIKit and tostring(UIKit.VERSION) or nil, build = BUILD_VERSION, alive = alive, session = sessionId,
		page = state.page, screen = screen, root = root, targets = targets,
	}
end
local function reload(target)
	if not alive then return reloadResult("FAILED hub is unloaded - re-inject hub.lua") end
	local want = tostring(target or ""):lower()
	if want == "hub" then return reloadHub() end
	if want == "" or want == "active" then
		if not (lastMounted and lastMounted.id) then
			return reloadResult(
				"FAILED nothing mounted -- pass a target: " .. table.concat(reloadTargets(), ", ")
			)
		end
		return reloadModule(lastMounted.id)
	end
	return reloadModule(want)
end
-- An optional private destination is supplied locally through G.__R3ST_REPORT_URL.
-- Never embed a private endpoint in the publicly mirrored source.
-- Positive allowlist: raw logs, notes, executor strings and status text stay local.
-- Legacy report(who, note) arguments are intentionally ignored for privacy.
local function buildReport()
	local function stamp(value)
		return type(value) == "string" and #value <= 80 and value:match("^[%w%._%-]+$") and value or "unknown"
	end
	local function gameId(value)
		return type(value) == "number" and value >= 0 and value < math.huge and value == math.floor(value) and tostring(value) or "unknown"
	end
	local parts = {
		"r3st-report-schema: 2",
		"hub-build: " .. stamp(BUILD_VERSION),
		"place-id: " .. gameId(game.PlaceId),
		"game-id: " .. gameId(game.GameId),
	}
	-- Only registered module IDs and their build constants; no player-derived text.
	local ids = {}
	for id in pairs(mountedModules) do
		if hostEntries[id] then ids[#ids + 1] = id end
	end
	table.sort(ids)
	for _, id in ipairs(ids) do
		if #parts >= 36 then break end
		local entry = hostEntries[id]
		local handle = G[entry.gkey]
		parts[#parts + 1] = "module: " .. stamp(id) .. " build=" .. stamp(type(handle) == "table" and handle.build)
	end
	return table.concat(parts, "\n")
end
local function sendReport()
	local body = buildReport()
	pcall(writefile, "logs/r3st_report_last.txt", body) -- always keep a local copy
	local reportUrl = G.__R3ST_REPORT_URL
	if type(reportUrl) ~= "string" or #reportUrl > 2048
		or not (reportUrl:match("^https://[%w%.%-]+/[^%s?#@\\]*$") or reportUrl:match("^https://[%w%.%-]+$"))
		or reportUrl:find("[%c]") then
		return false, "no private HTTPS report destination configured; "
			.. "logs/r3st_report_last.txt was written instead"
	end
	local req = (syn and syn.request) or (http and http.request) or http_request or request
	if type(req) ~= "function" then
		return false,
			"this executor exposes no HTTP request function; "
				.. "logs/r3st_report_last.txt was written instead"
	end
	local ok, res = pcall(req, {
		Url = reportUrl, Method = "POST",
		Headers = { ["Content-Type"] = "text/plain" }, Body = body,
	})
	if not ok then return false, "send failed; private destination details omitted" end
	local code = type(res) == "table" and tonumber(res.StatusCode or res.Status) or 0
	if type(code) ~= "number" or code ~= math.floor(code) or code < 100 or code > 599 then code = 0 end
	if code >= 200 and code < 300 then
		hubLog("info", "metadata report sent (" .. #body .. " bytes)")
		return true, ("sent %d bytes of build metadata"):format(#body)
	end
	return false, "receiver returned " .. tostring(code)
end
local api = {
	flush = function() if saveQueued then return saveConfig(true) end end,
	destroy = destroy, build = BUILD_VERSION, reload = reload, status = hubStatus,
	targets = reloadTargets, inspect = hubInspect, contract = SHELL_CONTRACT, logFile = RELOAD_LOG,
	report = sendReport, reportPreview = buildReport, profile = profiler,
	notify = setLaunchToast, handoff = function() return handoff.status(state.teleportRecovery) end,
}
if UIKit and UIKit.resizeGrip then
	UIKit.resizeGrip(root, {
		min = Vector2.new(MIN_W, MIN_H),
		onCommit = function()
			fit()
			state.windowW, state.windowH = root.Size.X.Offset, root.Size.Y.Offset
			saveConfig(true)
		end,
	})
end
local shown = true
do
	local revision, motionTween, blurTween = 0, nil, nil
	local rest = root.Position
	toggleShown = function(force)
		local want = force
		if want == nil then want = not shown end
		if want == shown then return end
		if shown and (not motionTween or motionTween.PlaybackState ~= Enum.PlaybackState.Playing) then
			rest = root.Position
		end
		shown = want
		revision += 1
		local ticket = revision
		if motionTween then motionTween:Cancel() end
		if blurTween then blurTween:Cancel() end
		if want and not root.Visible then root.Position = rest + UDim2.fromOffset(0, 10) end
		screen.Enabled = true
		root.Visible = true
		blur.Enabled = state.blur > 0
		local duration = (state.reduceMotion or (UIKit and UIKit.reduceMotion)) and 0
			or (want and MOTION.base or MOTION.exit)
		local targetBlur = (want and not root:GetAttribute("R3ST_Minimized")) and state.blur or 0
		motionTween = tween(root, { Position = want and rest or rest + UDim2.fromOffset(0, 10) }, duration,
			want and "out" or "in")
		blurTween = tween(blur, { Size = targetBlur }, duration)
		local function finish()
			if not alive or revision ~= ticket then return end
			screen.Enabled = want
			root.Visible = want
			blur.Enabled = want and state.blur > 0 and not root:GetAttribute("R3ST_Minimized")
		end
		if duration == 0 then
			finish()
		else
			task.delay(duration, finish)
		end
	end
	shown = false
	root.Visible = false
	toggleShown(true)
end
connect(close.Activated, destroy)
local minimized, restoreH = false, H
connect(minimize.Activated, function()
	minimized = not minimized
	root:SetAttribute("R3ST_Minimized", minimized)
	if minimized then
		restoreH = root.Size.Y.Offset -- the size the user actually left it at
	end
	content.Visible = not minimized
	sidebar.Visible = not minimized and not state.navHidden
	blur.Enabled = not minimized and state.blur > 0
	-- Commit geometry once; resizing the root per frame reflows every game page.
	root.Size = UDim2.fromOffset(root.Size.X.Offset, minimized and HEADER_H or restoreH)
	if not minimized and UIKit then UIKit.pageIn(content, 1, UDim2.fromScale(1, 0)) end
end)
local dragging, dragStart, startPos = false, nil, nil
connect(header.InputBegan, function(i)
	if i.UserInputType == Enum.UserInputType.MouseButton1 then
		if UIKit then UIKit.cancelMotion(root, "Position") end
		dragging = true
		dragStart = i.Position
		startPos = root.Position
	end
end)
connect(UIS.InputChanged, function(i)
	if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then
		local d = i.Position - dragStart
		root.Position = UDim2.new(
			startPos.X.Scale,
			startPos.X.Offset + d.X,
			startPos.Y.Scale,
			startPos.Y.Offset + d.Y
		)
	end
end)
connect(UIS.InputEnded, function(i)
	if i.UserInputType == Enum.UserInputType.MouseButton1 and dragging then
		dragging = false
		fit()
		state.windowX = root.Position.X.Offset
		state.windowY = root.Position.Y.Offset
		saveConfig()
	end
end)
connect(UIS.InputBegan, function(i, gp)
	if i.KeyCode == Enum.KeyCode.RightShift then
		toggleShown()
		return
	end
	if gp then return end
	local ctrl = UIS:IsKeyDown(Enum.KeyCode.LeftControl) or UIS:IsKeyDown(Enum.KeyCode.RightControl)
	if ctrl and shown and i.KeyCode == Enum.KeyCode.F then
		setPage("Home")
		task.defer(function() if alive then search:CaptureFocus() end end)
		return
	end
	if ctrl and shown and i.KeyCode == Enum.KeyCode.B then
		local toggle = header:FindFirstChild("ToggleNavigation")
		if toggle then toggle:SetAttribute("R3ST_Flip", (toggle:GetAttribute("R3ST_Flip") or 0) + 1) end
		return
	end
	if ctrl then return end
	if i.KeyCode == Enum.KeyCode.K then destroy() end
end)
do
	local navToggle =
		iconButton(header, "menu", UDim2.fromOffset(36, 34), UDim2.fromOffset(14, 15))
	navToggle.Name = "ToggleNavigation"
	local menuIcon = navToggle:FindFirstChild("R3ST_Icon")
	if menuIcon and #menuIcon:GetChildren() == 0 then
		for _, offset in ipairs({ -5, 0, 5 }) do
			icon(navToggle, "minus", 20, C.dim,
				UDim2.new(0.5, 0, 0.5, offset), Vector2.new(0.5, 0.5))
		end
	end
	-- Reflow once per destination, then slide a fixed-width sidebar and clip mask.
	-- The old width tweens resized every mounted page on every animation frame.
	local navTicket = 0
	local lastW, lastH, lastHidden, lastMinimized
	local function layout(animate)
		-- Logical dimensions ignore the window's opening UIScale animation.
		local w, h = root.Size.X.Offset, root.Size.Y.Offset
		local hidden = state.navHidden == true or w < 720
		local mini = root:GetAttribute("R3ST_Minimized") == true
		if w == lastW and h == lastH and hidden == lastHidden and mini == lastMinimized then return end
		lastW, lastH, lastHidden, lastMinimized = w, h, hidden, mini
		local d = (animate and not state.reduceMotion and not mini) and 0.24 or 0
		navTicket += 1
		local ticket = navTicket
		sidebar.Visible = not mini and (not hidden or d > 0)
		sidebar.Size = UDim2.new(0, SIDEBAR_W, 1, -(HEADER_H + 12))
		tween(sidebar, { Position = UDim2.fromOffset(hidden and -SIDEBAR_W - 4 or 12, HEADER_H) }, d)
		local left = hidden and 12 or (SIDEBAR_W + 24)
		local targetSize = UDim2.fromOffset(math.max(0, w - left - 12), math.max(0, h - HEADER_H - 12))
		if content.Size ~= targetSize then content.Size = targetSize end
		tween(contentViewport, { Position = UDim2.fromOffset(left, HEADER_H),
			Size = UDim2.new(1, -(left + 12), 1, -(HEADER_H + 12)) }, d)
		if hidden and d > 0 then
			task.delay(d, function()
				if alive and navTicket == ticket then sidebar.Visible = false end
			end)
		end
		iconColor(navToggle:FindFirstChild("R3ST_Icon"), hidden and C.accentText or C.dim)
		experienceLabel.Visible = w >= 700
		local short = h < 620
		featured.Visible = not short
		resultCount.Position = UDim2.fromOffset(24, short and 164 or 366)
		allList.Position = UDim2.fromOffset(24, short and 194 or 396)
		allList.Size = UDim2.new(1, -48, 1, -(short and 218 or 420))
		search.Size = UDim2.new(1, -48, 0, 40)
		search.Position = UDim2.fromOffset(24, 64)
	end
	local function flip()
		state.navHidden = not (state.navHidden == true or root.Size.X.Offset < 720)
		saveConfig(true)
		layout(true)
	end
	connect(navToggle.Activated, flip)
	connect(navToggle:GetAttributeChangedSignal("R3ST_Flip"), flip)
	connect(navToggle:GetAttributeChangedSignal("R3ST_Layout"), function() layout(true) end)
	connect(root:GetPropertyChangedSignal("Size"), function() layout(false) end)
	layout(false)
end
applyTheme(state.theme)
setPage(state.page)
hubLog(
	"info",
	"boot place="
		.. tostring(game.PlaceId)
		.. " universe="
		.. tostring(game.GameId)
		.. " registry="
		.. tostring(registryCount)
		.. " matched="
		.. (activeEntry and activeEntry.name or "none")
)
if not activeEntry then
	hubLog(
		"warn",
		"no registry row for universe "
			.. tostring(game.GameId)
			.. " (place "
			.. tostring(game.PlaceId)
			.. "). If this is a VIP server of a supported game,"
			.. " that entry is missing its gameId."
	)
end
if state.autoOpen or handoffBoot then
	task.defer(function()
		if not alive then return end
		if activeEntry and activeEntry.embed and mountActiveGame then setPage(activeEntry.name) end
		for id, mount in pairs(hostMounts) do
			local ok, err = mount(false)
			if not ok then
				hubLog("warn", "autoload " .. tostring(id) .. " failed: " .. tostring(err))
			end
		end
		if activeEntry and not activeEntry.embed then runModule(activeEntry, nil) end
	end)
end
if handoffBoot then
	if activeEntry then state.selectedGame = activeEntry.name end
	hubLog("info", "teleport handoff to " .. (activeEntry and activeEntry.id or "no registry row")
		.. "; admin autostart skipped: a handoff never starts admin.lua")
elseif state.autoAdmin ~= false and launchAdmin then
	if game.PlaceId == 8246089782 or game.GameId == 3163813433 then
		hubLog("info", "admin autostart skipped: Critical Strike kicks for admin.lua")
	else
		task.defer(function()
			local resident = G.Admin
			if not alive or (type(resident) == "table" and resident._ready == true) then return end
			local ok, err = pcall(launchAdmin, false)
			if not ok then hubLog("warn", "admin autostart failed: " .. tostring(err)) end
		end)
	end
end
if navButtons["Anims"] then
	connect(navButtons["Anims"].Activated, function() mountAnims(false) end)
end
if activeEntry and activeEntry.embed and navButtons[activeEntry.name] and mountActiveGame then
	connect(navButtons[activeEntry.name].Activated, function() mountActiveGame(false) end)
end
handoff.watch(game:GetService("Players").LocalPlayer, game:GetService("TeleportService"), connect, function(failed)
	if failed then setLaunchToast("Teleport failed — Hub reload stays armed", true)
	elseif saveQueued then saveConfig(true) end
end)
api.ready = true
-- If the swap still fails, release gives the queued loader back to the resident Hub.
if state.teleportRecovery and armHandoff() then scope.own(handoff.release) end
if handoffBoot then setLaunchToast("Reloaded after teleport", false) end
return api
end)
if not booted then
	pcall(writefile, "logs/r3st_reload.log", "FAILED Hub startup: " .. tostring(bootError) .. "\n")
end
return booted
