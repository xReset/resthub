-- R3ST Hub v2026-09-01.19 (2026-09-01)
-- Rung 2 (client-created UI only). Server sees: nothing; no game state or remotes touched.
-- Re-inject safe: self-teardown on load; RightShift = show/hide; K = unload.
-- Changelog:
--   .19 Send report. A friend running the public loadstring had no way to get
--      their logs to us, so every outside bug report was "it doesn't work".
--      About -> Send report posts the build stamps, place/universe and the tail
--      of the hub + module logs to the receiver (LXC104, Tailscale Funnel) that
--      had been live and empty for a month. Consent only: a button, no timer,
--      and the line next to it says exactly what is sent. Also exposed as
--      __R3ST_HUB.report(who, note) so a module can offer the same button.
--      Read what arrives with: bash tools/pull_friend_logs.sh
--   .18 preserve any embedded controller that exposes detach/mount, allowing
--      Ghost Driver and Anims to remain active while their panels alternate.
--   .17 treat scripts/anims.lua and internal/admin_core.lua as the canonical
--      general-tool backends. Admin launch now waits for core readiness and
--      reports the actual backend build instead of claiming deferred success.
--   .16 handle RightShift before the gameProcessed gate so games that consume
--      Shift cannot block the Hub show/hide bind.
--   .15 Anims is a persistent controller, not the active game module. Route
--      changes and GD2 reloads detach only its panel; explicit Anims OFF owns
--      restore. Returning to Anims remounts the existing controller.
--   .14 remove the redundant Universal browser and unrelated tools; Admin and
--      Anims remain the general section. Matching modules always open on inject.
--      Hub surfaces now use one black instead of competing near-black layers.
--   .13 agent reload API on getgenv().__R3ST_HUB. An agent has a live Luau
--      channel through the Potassium MCP server but had no way to make the
--      client pick up a file it had just deployed, so every iteration ended in
--      "re-inject and paste the log". Now:
--        getgenv().__R3ST_HUB.reload()        remount whatever is mounted
--        getgenv().__R3ST_HUB.reload("blr")   ...by id, file or display name
--        getgenv().__R3ST_HUB.reload("hub")   reload hub.lua itself, in place
--        getgenv().__R3ST_HUB.status()        mounted target + live build stamps
--      Every call returns a string AND writes logs/r3st_reload.log, because
--      read_console came back empty on a plain print in live testing
--      (potassium-mcp S2). Reloading the hub compiles the replacement BEFORE
--      tearing the current one down: a hub that unloads itself and then fails
--      to load its successor strands the user mid-match with no UI. Targets are
--      only the modules that already have a host page, so the API inherits the
--      S2 identity gate instead of re-implementing it -- there is no target
--      string that loads another game's module. `mount` now returns ok, err so
--      a failed remount reports as failed instead of as done.
--   .12 identity matches on the UNIVERSE first (game.GameId), then the place.
--      A VIP / private server is the same experience on a different PlaceId, so
--      a PlaceId-only gate refused to arm in exactly the servers the user plays
--      in. Entries without a gameId still gate on PlaceId; the boot log now
--      prints the universe id of any unmatched place so the row can be fixed.
--   .11 ONE control template for every module. scripts/r3st_ui.lua is the shared
--      widget kit -- header, tab strip, two-column card grid, pill toggle, track
--      slider, footer -- and the hub hands it to each module on the host contract
--      as __R3ST_HOST.ui, so a module never loads its own copy when embedded.
--      A module that cannot find it still resolves it from disk and still runs
--      standalone. Different games keep different controls; they no longer keep
--      different looks.
--   .10 six more modules honour the host contract and render in the hub:
--      Evade, Dungeon Quest Reborn, Cold War, Rivals, Operation One, Arsenal.
--      Registry gains Rivals, Arsenal and DQR, and an optional `placeIds` list
--      for a game whose lobby and level are separate places.
--   .9 module paths resolve through ../scripts (the Explorer tab) first. Potassium
--      roots its file API at workspace\, so a bare loadfile read the WORKSPACE:
--      Ghost Driver reported "missing" while a stale v.9 anims.lua loaded and
--      opened its own window outside the hub. Settings lost the per-game
--      autoload/autosave pair -- one Autosave and one "open this place's module
--      on inject", both global.
--   .8 host-mount contract (getgenv().__R3ST_HOST): the module for THIS place
--      gets its own sidebar tab and renders inside the hub instead of opening a
--      second shell. Favorites / Recent / Universal / About are real pages built
--      from live state, not template cards. Registry grew to every game whose
--      PlaceId is proven in its own source. Fixed the nil forward reference on
--      `C` in setLaunchToast that made every failed launch throw instead of
--      showing the reason.
--   .7 featured cards + list rows fully clickable; launch toast + file log on failure
--   .6 registry lists every module; launch still PlaceId-gated
--   .5 Blue Lock Rivals registry + strict PlaceId isolation; module autoload policy
--   .4 fix game artwork with supported thumbnail size and Marketplace icon fallback
--   .3 replace fabricated game dashboard with the complete Ghost Driver module; Roblox game thumbnail
--   .2 R3ST branding, Games navigation, blur backdrop, stronger type, settings/config foundation
--   .1 initial reference-matched interactive template
--
-- HOST-MOUNT CONTRACT (hub skill S6, migration step)
--   Before running a module the hub publishes:
--     getgenv().__R3ST_HOST = { host = <Frame>, width = n, height = n,
--                               build = <hub build>, back = function() end }
--   A module that understands it parents its root into `host`, creates no
--   ScreenGui, no BlurEffect, no window drag and no "back to hub" button of its
--   own -- the hub owns all four. A module that does not understand it ignores
--   the global and opens standalone, exactly as before. The global is cleared
--   the moment the chunk returns, so nothing leaks into a later inject.
--   Embedded today: gd2.lua, blr_hub.lua, anims.lua.

local BUILD_VERSION = "2026-09-01.19"
local GKEY = "__R3ST_HUB"
local HOST_KEY = "__R3ST_HOST"
local CONFIG_FILE = "rbx_hub_template_config.json"
local UIS = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")
local Lighting = game:GetService("Lighting")
local MarketplaceService = game:GetService("MarketplaceService")

local G = getgenv()
if G[GKEY] and G[GKEY].destroy then pcall(G[GKEY].destroy) end
G[HOST_KEY] = nil

-- Every local that a closure below reads is declared here first. A function
-- that closes over a `local` declared *after* it silently reads a global
-- instead -- that is what broke setLaunchToast in .7.
local alive = true
local connections = {}
local screen
local destroy
local saveQueued = false
local launchToast
local Log
local C
local state
local pages = {}
local navButtons = {}
local navOrder = {}
local setPage
local content
local sidebar
local blur
local root
local mountedModule -- { gkey, name, id } while a module is embedded
-- id -> mount(force) and id -> registry entry, for the agent reload API (.13).
-- Only pages that were actually built get in here, and a page is only built for
-- a module that passed the identity gate -- so the API inherits S2 isolation
-- instead of re-implementing it.
local hostMounts = {}
local hostEntries = {}
local hostAlias = {} -- lowercase id / file / name -> id

pcall(function()
	local ok, factory = pcall(loadfile, "log.lua")
	if ok and type(factory) == "function" then
		local ok2, logger = pcall(factory, "rbx_hub")
		if ok2 and type(logger) == "table" then
			Log = logger
		end
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
		if makefolder and isfolder and not isfolder("logs") then
			makefolder("logs")
		end
		if appendfile and isfile and isfile("logs/rbx_hub.log") then
			appendfile("logs/rbx_hub.log", line .. "\n")
		elseif writefile then
			writefile("logs/rbx_hub.log", line .. "\n")
		end
	end)
end

C = {
	bg = Color3.fromRGB(7, 7, 9), panel = Color3.fromRGB(7, 7, 9), raised = Color3.fromRGB(17, 17, 21),
	hover = Color3.fromRGB(24, 24, 29), line = Color3.fromRGB(42, 42, 50), text = Color3.fromRGB(240, 240, 245),
	dim = Color3.fromRGB(165, 167, 172), green = Color3.fromRGB(72, 205, 57), white = Color3.fromRGB(250, 250, 250),
	bad = Color3.fromRGB(255, 120, 120),
}

local function setLaunchToast(text, isError)
	if not launchToast or not launchToast.Parent then return end
	launchToast.Text = text or ""
	launchToast.TextColor3 = isError and C.bad or C.dim
end

state = {
	favorites = {},
	recent = {},
	page = "Home",
	selectedGame = "Ghost Driver",
	windowX = 0,
	windowY = 0,
	theme = "Midnight",
	uiScale = 100,
	blur = 5,
	autosave = true,
	autoOpen = true,
}

local function connect(signal, fn)
	local c = signal:Connect(fn)
	connections[#connections + 1] = c
	return c
end

--==========================================================================
-- Registry
--   Every entry's placeId is quoted from that script's own source, not guessed.
--   `embed = true` means the module honours the host-mount contract above.
--   `gkey` is the module's getgenv lifecycle key, so the hub can unload it.
--   gameId is the UNIVERSE id and is what makes a row work inside a VIP /
--   private server, where the PlaceId can differ from the public one. Treat it
--   as required for any game the user actually plays; without it the row still
--   gates on PlaceId and will refuse to arm in a private server. Artwork also
--   resolves faster from it.
--==========================================================================
local REGISTRY = {
	{ id = "ghost-driver", moduleKey = "GhostDriver", name = "Ghost Driver", cat = "Vehicle",
		placeId = 137228775845999, gameId = 10173311467, file = "gd2.lua", embed = true, gkey = "__GD2",
		desc = "Vehicle tuning, handling, stance, exhaust, audio mixer and ESP." },
	{ id = "blue-lock-rivals", moduleKey = "BlueLockRivals", name = "Blue Lock Rivals", cat = "Sports",
		placeId = 18668065416, gameId = 6325068386, file = "blr_hub.lua", embed = true, gkey = "__BLR_HUB",
		desc = "Cooldown bypass, shot power, ability tuning and client stamina." },
	{ id = "critical-strike", moduleKey = "CriticalStrike", name = "Critical Strike", cat = "Fighting",
		placeId = 8246089782, file = "cs_admin.lua", gkey = "__CS_ADMIN",
		desc = "cs_core engine: projectile guidance classes, ally assist, admin bar." },
	{ id = "gakuran", moduleKey = "Gakuran", name = "Gakuran", cat = "Fighting",
		placeId = 128736949265057, file = "gakuran_autoparry.lua", gkey = "__GAKURAN_AUTOPARRY",
		desc = "Windup-predictive perfect block." },
	{ id = "build-a-base-rng", moduleKey = "BuildABaseRNG", name = "Build a Base RNG", cat = "RNG",
		placeId = 99108783264633, file = "bab_hub.lua", desc = "Base and roll utilities." },
	{ id = "clean-all-leaves", moduleKey = "CleanAllLeaves", name = "Clean All Leaves", cat = "Simulator",
		placeId = 100068273119174, file = "leaves_hub.lua", desc = "Collection and pacing tools." },
	{ id = "sols-rng", moduleKey = "SolsRNG", name = "Sol's RNG", cat = "RNG",
		placeId = 15532962292, file = "sols_hub.lua", desc = "Aura roll readouts and timers." },
	{ id = "soulrift", moduleKey = "Soulrift", name = "Soulrift", cat = "RPG",
		placeId = 92186908729708, file = "soulrift_hub.lua", desc = "Combat and progression tools." },
	{ id = "storage-hunters", moduleKey = "StorageHunters", name = "Storage Hunters", cat = "Simulator",
		placeId = 98800969324557, file = "sh_hub.lua", desc = "Unit value readouts and bidding help." },
	{ id = "tbod-squared", moduleKey = "TbodSquared", name = "TBOD Squared", cat = "Fighting",
		placeId = 139063887391814, file = "tbod_hub.lua", desc = "Combat assist toolkit." },
	{ id = "unscathed-rng", moduleKey = "UnscathedRNG", name = "Unscathed RNG", cat = "RNG",
		placeId = 122951224417794, file = "unscathed_hub.lua", desc = "Roll tracking and combat advisor." },
	{ id = "runaways", moduleKey = "Runaways", name = "Runaways", cat = "Survival",
		placeId = 117311404196294, file = "runaways.lua", desc = "Survival awareness toolkit." },
	{ id = "evade", moduleKey = "Evade", name = "Evade", cat = "Survival",
		placeId = 9872472334, file = "evade_kit.lua", embed = true, gkey = "__EVADE_KIT",
		desc = "Bhop, first-person body, revive and awareness kit." },
	{ id = "hypershot", moduleKey = "Hypershot", name = "Hypershot", cat = "Shooter",
		placeId = 100040622766961, file = "hypershot_esp.lua", desc = "Player ESP." },
	{ id = "counterblox", moduleKey = "Counterblox", name = "Counter Blox", cat = "Shooter",
		placeId = 301549746, file = "counterblox_esp.lua", desc = "Player and bomb ESP." },
	{ id = "cold-war", moduleKey = "ColdWar", name = "Cold War", cat = "Shooter",
		placeId = 13687899540, file = "coldwar_esp.lua", embed = true, gkey = "__COLDWAR_ESP",
		desc = "Player and mounted-MG ESP, chams, healthbars." },
	{ id = "bloxstrike", moduleKey = "BloxStrike", name = "BloxStrike", cat = "Shooter",
		placeId = 114234929420007, file = "bloxstrike_esp.lua", desc = "Player ESP." },
	{ id = "onetap", moduleKey = "OneTap", name = "One Tap", cat = "Shooter",
		placeId = 85207102870777, file = "onetap_esp.lua", desc = "Player ESP." },
	{ id = "operation-one", moduleKey = "OperationOne", name = "Operation One", cat = "Shooter",
		placeId = 72920620366355, file = "operation_one_esp.lua", embed = true, gkey = "__OP1_ESP",
		desc = "Player ESP, gun duck and optional soft aim." },
	{ id = "overkill", moduleKey = "Overkill", name = "Overkill", cat = "Shooter",
		placeId = 74996816424339, file = "overkill_aim.lua", desc = "Aim assist and telemetry." },
	{ id = "apoc-rising-2", moduleKey = "ApocRising2", name = "Apocalypse Rising 2", cat = "Survival",
		placeId = 863266079, file = "apoc_rising_2_esp.lua", desc = "Loot and player ESP." },
	{ id = "flee-facility", moduleKey = "FleeFacility", name = "Flee the Facility", cat = "Survival",
		placeId = 893973440, file = "flee_facility_esp.lua", desc = "Player and computer ESP." },
	-- Lobby and level are separate places (games/dungeon-quest-reborn README:3,
	-- GameId 9931749389); the module is valid in both.
	{ id = "dungeon-quest-reborn", moduleKey = "DungeonQuestReborn", name = "Dungeon Quest Reborn", cat = "RPG",
		placeId = 77649408247578, placeIds = { 77649408247578, 85776757589518 }, gameId = 9931749389,
		file = "dqr_hub.lua", embed = true, gkey = "__DQR_HUB",
		desc = "Attack telegraphs, auto dodge, auto abilities, mob ESP." },
	-- PlaceId from the dump named in games/other/RIVALS_SOFTAIM_SAFETY_2026-08-13.md:11.
	{ id = "rivals", moduleKey = "Rivals", name = "Rivals", cat = "Shooter",
		placeId = 117398147513099, file = "rivals_esp.lua", embed = true, gkey = "__RIVALS_ESP",
		desc = "Player ESP with guarded soft aim and backstab assist." },
	{ id = "arsenal", moduleKey = "Arsenal", name = "Arsenal", cat = "Shooter",
		placeId = 286090429, file = "arsenal_esp.lua", embed = true, gkey = "__ARSENAL_ESP",
		desc = "Player ESP, chams and healthbars." },
}

-- General tools keep dedicated sidebar entries; there is no redundant
-- Universal browser. Neither is automatically executed.
local GENERAL = {
	{ id = "anims", name = "Anims", file = "anims.lua", embed = true, gkey = "__ANIMS_GUI",
		desc = "M7-derived animation packs: 21 custom, 35 Roblox, 24 UGC, per-slot mixing." },
	{ id = "admin", name = "Admin", file = "admin.lua", gkey = "Admin",
		desc = "The ] command bar backed by internal/admin_core.lua. Opens its own minimal bar." },
}

local registryCount = #REGISTRY

local activeEntry

-- Some games split lobby and level across separate places. `placeIds` lists
-- every place the module is valid in; `placeId` stays the canonical one used for
-- artwork and for the "join this first" message.
-- IDENTITY IS THE UNIVERSE, NOT THE PLACE.
-- A VIP / private server is the same experience, but the client can land on a
-- different PlaceId inside it, so a PlaceId-only gate fails closed in exactly
-- the servers people play in most. game.GameId is the universe id and is stable
-- across every place and every private server of one experience, so it is
-- checked FIRST. PlaceId stays as the fallback for the entries that have no
-- gameId yet, and it is still what artwork and the "join this first" message
-- use.
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

local function canLaunch(entry)
	return entryMatches(entry)
end

for _, entry in ipairs(REGISTRY) do
	if entryMatches(entry) then
		activeEntry = entry
		break
	end
end

--==========================================================================
-- Config
--==========================================================================
local function loadConfig()
	local ok, raw = pcall(readfile, CONFIG_FILE)
	if not ok then return end
	local decodedOk, saved = pcall(HttpService.JSONDecode, HttpService, raw)
	if not decodedOk or type(saved) ~= "table" then return end
	if type(saved.favorites) == "table" then state.favorites = saved.favorites end
	if type(saved.recent) == "table" then
		for _, id in ipairs(saved.recent) do
			if type(id) == "string" then state.recent[#state.recent + 1] = id end
		end
	end
	if type(saved.page) == "string" then state.page = saved.page end
	if type(saved.selectedGame) == "string" then state.selectedGame = saved.selectedGame end
	if type(saved.windowX) == "number" then state.windowX = saved.windowX end
	if type(saved.windowY) == "number" then state.windowY = saved.windowY end
	if saved.theme == "Midnight" or saved.theme == "Slate" or saved.theme == "Carbon" then state.theme = saved.theme end
	if type(saved.uiScale) == "number" then state.uiScale = math.clamp(saved.uiScale, 75, 115) end
	if type(saved.blur) == "number" then state.blur = math.clamp(saved.blur, 0, 12) end
	if type(saved.autosave) == "boolean" then state.autosave = saved.autosave end
end

local function saveConfig(force)
	if not force and not state.autosave then return end
	if saveQueued then return end
	saveQueued = true
	task.delay(0.4, function()
		saveQueued = false
		if not alive then return end
		local ok, raw = pcall(HttpService.JSONEncode, HttpService, state)
		if ok then pcall(writefile, CONFIG_FILE, raw) end
	end)
end

loadConfig()
-- The identity-matched module is the product entry point, not a second click.
-- Foreign modules still fail closed before this policy is evaluated.
state.autoOpen = true

local entryById = {}
for _, entry in ipairs(REGISTRY) do entryById[entry.id] = entry end

local function noteRecent(entry)
	local out = { entry.id }
	for _, id in ipairs(state.recent) do
		if id ~= entry.id and #out < 8 then out[#out + 1] = id end
	end
	state.recent = out
	saveConfig(true)
end

--==========================================================================
-- Widgets
--==========================================================================
local function mk(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props or {}) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end
local function round(o, px) mk("UICorner", { CornerRadius = UDim.new(0, px or 8) }, o) end
local function stroke(o, transparency) mk("UIStroke", { Color = C.line, Thickness = 1, Transparency = transparency or 0 }, o) end
local function pad(o, n) mk("UIPadding", { PaddingTop=UDim.new(0,n), PaddingBottom=UDim.new(0,n), PaddingLeft=UDim.new(0,n), PaddingRight=UDim.new(0,n) }, o) end
local function label(parent, text, size, pos, fontSize, color, bold)
	return mk("TextLabel", { BackgroundTransparency=1, Size=size, Position=pos or UDim2.new(), Text=text, TextColor3=color or C.text,
		Font=bold and Enum.Font.GothamBold or Enum.Font.GothamMedium, TextSize=fontSize or 13, TextXAlignment=Enum.TextXAlignment.Left }, parent)
end
local function button(parent, text, size, pos)
	local b = mk("TextButton", { Size=size, Position=pos or UDim2.new(), BackgroundColor3=C.panel, BorderSizePixel=0, AutoButtonColor=false,
		Text=text, TextColor3=C.text, Font=Enum.Font.GothamMedium, TextSize=13 }, parent)
	round(b, 7); stroke(b)
	connect(b.MouseEnter, function() b.BackgroundColor3 = C.hover end)
	connect(b.MouseLeave, function() b.BackgroundColor3 = C.panel end)
	return b
end
local function divider(parent, y) mk("Frame", { Size=UDim2.new(1,-24,0,1), Position=UDim2.fromOffset(12,y), BackgroundColor3=C.line, BorderSizePixel=0 }, parent) end

--==========================================================================
-- Shell
--==========================================================================
local W, H = 1180, 700
local SIDEBAR_W, CONTENT_W, BODY_H = 170, 974, 624

local core = CoreGui
if type(cloneref) == "function" then local ok, copy = pcall(cloneref, core); if ok and copy then core = copy end end
screen = mk("ScreenGui", { Name="RBXH_"..tostring(math.random(1000,9999)), ResetOnSpawn=false, IgnoreGuiInset=true,
	ZIndexBehavior=Enum.ZIndexBehavior.Global, DisplayOrder=2147483647 }, core)
pcall(sethiddenproperty, screen, "OnTopOfCoreBlur", true)

blur = mk("BlurEffect", { Name=screen.Name.."_Blur", Size=state.blur }, Lighting)
local shade = mk("Frame", { Size=UDim2.fromScale(1,1), BackgroundTransparency=1, BorderSizePixel=0 }, screen)
root = mk("Frame", { AnchorPoint=Vector2.new(.5,.5), Position=UDim2.new(.5,state.windowX,.5,state.windowY), Size=UDim2.fromOffset(W,H),
	BackgroundColor3=C.bg, BorderSizePixel=0, ClipsDescendants=true }, shade)
round(root, 12); stroke(root)
local scale = mk("UIScale", { Scale=state.uiScale/100 }, root)
local function fit()
	local cam = workspace.CurrentCamera
	if not cam then return end
	local v = cam.ViewportSize
	scale.Scale = math.min(state.uiScale/100, (v.X-24)/W, (v.Y-24)/H)
end
fit()
if workspace.CurrentCamera then connect(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"), fit) end

local header = mk("Frame", { Size=UDim2.new(1,0,0,64), BackgroundTransparency=1 }, root)
local logo = mk("Frame", { Size=UDim2.fromOffset(28,28), Position=UDim2.fromOffset(24,18), BackgroundColor3=C.white, BorderSizePixel=0, Rotation=14 }, header); round(logo,2)
mk("Frame", { Size=UDim2.fromOffset(9,9), AnchorPoint=Vector2.new(.5,.5), Position=UDim2.fromScale(.5,.5), BackgroundColor3=C.bg, BorderSizePixel=0 }, logo)
label(header,"R3ST HUB",UDim2.fromOffset(180,34),UDim2.fromOffset(66,15),19,C.text,true)
label(header, activeEntry and ("|   " .. activeEntry.name) or "|   unsupported place",
	UDim2.fromOffset(340,34), UDim2.fromOffset(190,16), 14, C.dim)
local minimize = button(header,"—",UDim2.fromOffset(38,34),UDim2.new(1,-94,0,15))
local close = button(header,"×",UDim2.fromOffset(38,34),UDim2.new(1,-48,0,15)); close.TextSize=26

sidebar = mk("Frame", { Position=UDim2.fromOffset(12,64), Size=UDim2.fromOffset(SIDEBAR_W,BODY_H), BackgroundColor3=C.panel, BorderSizePixel=0 }, root); round(sidebar,10); stroke(sidebar)
content = mk("Frame", { Position=UDim2.fromOffset(12+SIDEBAR_W+12,64), Size=UDim2.fromOffset(CONTENT_W,BODY_H), BackgroundColor3=C.panel, BorderSizePixel=0, ClipsDescendants=true }, root); round(content,10); stroke(content)

setPage = function(name)
	if not pages[name] then name = "Home" end
	state.page = name
	for k,p in pairs(pages) do p.Visible = (k == name) end
	for k,b in pairs(navButtons) do
		b.BackgroundColor3 = k == name and C.hover or C.panel
		b.TextColor3 = k == name and C.text or C.dim
	end
	saveConfig()
end

--==========================================================================
-- Artwork
--==========================================================================
local function applyThumbnail(imageObj, entry)
	if entry.gameId then
		imageObj.Image = "rbxthumb://type=GameIcon&id=" .. tostring(entry.gameId) .. "&w=150&h=150"
	end
	task.spawn(function()
		local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, entry.placeId)
		if ok and type(info) == "table" and tonumber(info.IconImageAssetId) and tonumber(info.IconImageAssetId) > 0 and imageObj.Parent then
			imageObj.Image = "rbxassetid://" .. tostring(info.IconImageAssetId)
		end
	end)
end

--==========================================================================
-- Module loading
--   `host` non-nil => publish the host-mount contract for the duration of the
--   chunk. Modules that do not know the contract simply never read the global.
--==========================================================================
-- Potassium's file API is rooted at %LOCALAPPDATA%\Potassium\workspace\, but the
-- user injects from the Explorer tab = %LOCALAPPDATA%\Potassium\scripts\. A bare
-- loadfile("gd2.lua") therefore reads the WORKSPACE, where most modules do not
-- exist at all -- and where the ones that do are stale leftovers. That is what
-- made Ghost Driver report "missing" while a v.9 anims.lua loaded and opened its
-- own window. The Explorer folder is checked first, every time.
local MODULE_PATHS = { "../scripts/%s", "%s", "scripts/%s" }

local function loadModule(file)
	local lastErr
	for _, pattern in ipairs(MODULE_PATHS) do
		local path = pattern:format(file)
		local readOk, src = pcall(readfile, path)
		if readOk and type(src) == "string" and #src > 0 then
			local chunk, err = loadstring(src, "=" .. file)
			if type(chunk) == "function" then
				hubLog("info", "resolved " .. file .. " -> " .. path .. " (" .. tostring(#src) .. " bytes)")
				return chunk
			end
			lastErr = "compile error in " .. path .. ": " .. tostring(err)
		end
	end
	if lastErr then return nil, lastErr end
	return nil, "not found in the Potassium Explorer folder (" .. file .. ")"
end

-- The shared control template. Loaded once here and handed to every module on
-- the host contract, so an embedded module never reads the file itself and the
-- whole hub is guaranteed to be running ONE version of the widgets.
local UIKit
do
	local chunk = loadModule("r3st_ui.lua")
	if chunk then
		local ok, kit = pcall(chunk)
		if ok and type(kit) == "table" then
			UIKit = kit
		end
	end
	if UIKit then
		hubLog("info", "ui kit " .. tostring(UIKit.VERSION))
	else
		hubLog("warn", "r3st_ui.lua not loadable - modules fall back to their own widgets")
	end
end

local function unmountActive()
	if not mountedModule then return end
	local handle = G[mountedModule.gkey]
	if type(handle) == "table" then
		-- A controller that exposes detach/mount explicitly separates its panel
		-- from its live state. Route changes own the panel only.
		local fn = handle.detach or handle.destroy or handle.unload
		if type(fn) == "function" then pcall(fn) end
	end
	local persistent = type(handle) == "table" and type(handle.detach) == "function"
	hubLog("info", (persistent and "detached " or "unmounted ") .. mountedModule.name)
	mountedModule = nil
end

local function runModule(entry, host)
	local chunk, err = loadModule(entry.file)
	if not chunk then
		hubLog("warn", "load failed file=" .. entry.file .. " err=" .. tostring(err))
		return false, err
	end
	if host then
		unmountActive()
		for _, child in ipairs(host:GetChildren()) do child:Destroy() end
		G[HOST_KEY] = {
			host = host,
			width = host.AbsoluteSize.X > 0 and host.AbsoluteSize.X or (CONTENT_W - 24),
			height = host.AbsoluteSize.Y > 0 and host.AbsoluteSize.Y or (BODY_H - 24),
			build = BUILD_VERSION,
			hub = "R3ST",
			autosave = state.autosave,
			ui = UIKit, -- the shared control template (scripts/r3st_ui.lua)
			back = function() setPage("Home") end,
		}
	end
	-- Re-enter any persistent controller by mounting a fresh panel without
	-- restarting its live state. Anims and Ghost Driver both use this path.
	local existing = G[entry.gkey]
	if host and type(existing) == "table" and type(existing.mount) == "function" then
		local mounted, mountErr = pcall(existing.mount, G[HOST_KEY])
		G[HOST_KEY] = nil
		if not mounted then
			hubLog("warn", "Anims panel remount failed: " .. tostring(mountErr))
			return false, tostring(mountErr)
		end
		mountedModule = { gkey = entry.gkey, name = entry.name, id = entry.id }
		hubLog("info", "module remounted " .. entry.file .. " (controller preserved)")
		return true
	end
	local ran, runErr = pcall(chunk)
	G[HOST_KEY] = nil
	if not ran then
		hubLog("warn", "module runtime failed file=" .. entry.file .. " err=" .. tostring(runErr))
		return false, tostring(runErr)
	end
	hubLog("info", "module loaded " .. entry.file .. (host and " (embedded)" or " (standalone)"))
	if host and entry.gkey then
		mountedModule = { gkey = entry.gkey, name = entry.name, id = entry.id }
	end
	if entry.placeId then noteRecent(entry) end
	return true
end

-- Standalone launch from a browser card/row: fail closed on the wrong place,
-- then hand the screen over to the module exactly as .7 did.
local function openGame(entry)
	if not entryMatches(entry) then
		hubLog("warn", "launch blocked wrong place want=" .. tostring(entry.placeId) .. " have=" .. tostring(game.PlaceId))
		setLaunchToast("Join " .. entry.name .. " first (PlaceId " .. tostring(entry.placeId) .. ")", true)
		return false
	end
	-- An embeddable module for this place has its own tab; send the user there
	-- rather than opening a second shell.
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
	destroy()
	return true
end

local function tryLaunch(entry, feedbackBtn)
	state.selectedGame = entry.name
	saveConfig()
	if openGame(entry) then return end
	if feedbackBtn and feedbackBtn:IsA("GuiButton") then
		local old = feedbackBtn.Text
		feedbackBtn.Text = entryMatches(entry) and "!" or "—"
		task.delay(0.8, function()
			if alive and feedbackBtn.Parent then feedbackBtn.Text = old end
		end)
	end
end

--==========================================================================
-- Shared row / card builders
--==========================================================================
local rowRefresh = {}   -- page name -> function, called when favorites change

local function makeGameRow(parent, entry, y, width)
	local ready = canLaunch(entry)
	local row = mk("Frame", { Size=UDim2.new(1,width or 0,0,40), Position=UDim2.fromOffset(0,y), BackgroundColor3=C.raised, BorderSizePixel=0 }, parent)
	round(row,7); stroke(row)
	local icon = mk("ImageLabel", { Size=UDim2.fromOffset(30,30), Position=UDim2.fromOffset(6,5), BackgroundColor3=C.panel,
		BorderSizePixel=0, ScaleType=Enum.ScaleType.Crop, ImageTransparency = ready and 0 or 0.35 }, row)
	round(icon,6)
	applyThumbnail(icon, entry)
	label(row, entry.name, UDim2.fromOffset(210,30), UDim2.fromOffset(44,5), 12, C.text).Active = false
	label(row, entry.cat or "", UDim2.fromOffset(90,24), UDim2.fromOffset(268,8), 11, C.dim).Active = false
	label(row, ready and "Ready here" or "Visit game", UDim2.fromOffset(110,24), UDim2.fromOffset(380,8), 11,
		ready and C.green or C.dim).Active = false
	label(row, entry.desc or "", UDim2.fromOffset(300,24), UDim2.fromOffset(500,8), 11, C.dim).Active = false

	local fav = button(row, state.favorites[entry.name] and "★" or "☆", UDim2.fromOffset(34,30), UDim2.new(1,-78,0,5))
	fav.TextSize = 18; fav.ZIndex = 3
	local play = button(row, ready and "▶" or "—", UDim2.fromOffset(52,30), UDim2.new(1,-46,0,5))
	play.ZIndex = 3
	if not ready then play.TextColor3 = C.dim end
	local rowHit = mk("TextButton", { Size=UDim2.new(1,-120,1,0), BackgroundTransparency=1, BorderSizePixel=0, Text="",
		AutoButtonColor=false, ZIndex=1 }, row)

	local function toggleFav()
		state.favorites[entry.name] = (not state.favorites[entry.name]) or nil
		fav.Text = state.favorites[entry.name] and "★" or "☆"
		saveConfig(true)
		if rowRefresh.Favorites then rowRefresh.Favorites() end
	end
	connect(fav.Activated, toggleFav)
	local function launchFromRow() tryLaunch(entry, play) end
	connect(play.Activated, launchFromRow)
	connect(rowHit.Activated, launchFromRow)
	return row
end

local function scrollList(parent, pos, size)
	local list = mk("ScrollingFrame", { Position=pos, Size=size, BackgroundTransparency=1, BorderSizePixel=0,
		ScrollBarThickness=3, ScrollBarImageColor3=C.line, CanvasSize=UDim2.new() }, parent)
	return list
end

local function emptyState(parent, title, body)
	local card = mk("Frame", { Size=UDim2.new(1,-8,0,96), BackgroundColor3=C.raised, BorderSizePixel=0 }, parent)
	round(card,8); stroke(card)
	label(card, title, UDim2.new(1,-32,0,24), UDim2.fromOffset(16,16), 14, C.text, true)
	local b = label(card, body, UDim2.new(1,-32,0,48), UDim2.fromOffset(16,44), 12, C.dim)
	b.TextWrapped = true
	return card
end

local function newPage(name)
	local p = mk("Frame", { Size=UDim2.fromScale(1,1), BackgroundTransparency=1, Visible=false }, content)
	pages[name] = p
	return p
end

--==========================================================================
-- Home / games browser
--==========================================================================
local home = newPage("Home")
local search = mk("TextBox", { Size=UDim2.fromOffset(240,34), Position=UDim2.new(1,-260,0,18), BackgroundColor3=C.bg, BorderSizePixel=0,
	PlaceholderText="  Search games...", Text="", TextColor3=C.text, PlaceholderColor3=C.dim, Font=Enum.Font.Gotham, TextSize=12,
	ClearTextOnFocus=false }, home)
round(search,7); stroke(search)
launchToast = label(home, "", UDim2.new(1,-40,0,18), UDim2.fromOffset(20,54), 11, C.dim)

local featured = mk("Frame", { Size=UDim2.new(1,-40,0,180), Position=UDim2.fromOffset(20,74), BackgroundColor3=C.bg, BorderSizePixel=0 }, home)
round(featured,8); stroke(featured)
label(featured, "Featured Games · " .. tostring(registryCount), UDim2.fromOffset(300,24), UDim2.fromOffset(14,12), 15, C.text, true)
label(featured, activeEntry and (activeEntry.name .. " is ready here — open its tab in the sidebar")
	or "No module matches this PlaceId. Cards below stay browsable and inert.",
	UDim2.new(1,-28,0,18), UDim2.fromOffset(14,32), 11, C.dim)

local featuredScroll = mk("ScrollingFrame", { Position=UDim2.fromOffset(8,56), Size=UDim2.new(1,-16,0,116), BackgroundTransparency=1,
	BorderSizePixel=0, ScrollBarThickness=3, ScrollBarImageColor3=C.line, ScrollingDirection=Enum.ScrollingDirection.X,
	CanvasSize=UDim2.new() }, featured)

-- The place we are actually in comes first, then favorites, then the rest.
local featuredOrder = {}
do
	local seen = {}
	local function push(entry) if entry and not seen[entry.id] then seen[entry.id] = true; featuredOrder[#featuredOrder+1] = entry end end
	push(activeEntry)
	for _, e in ipairs(REGISTRY) do if state.favorites[e.name] then push(e) end end
	for _, e in ipairs(REGISTRY) do push(e) end
end

local function makeFeaturedCard(parent, entry, index)
	local x = 6 + (index - 1) * 130
	local ready = canLaunch(entry)
	local card = mk("TextButton", { Size=UDim2.fromOffset(124,110), Position=UDim2.fromOffset(x,0), BackgroundColor3=C.raised,
		BorderSizePixel=0, Text="", AutoButtonColor=false, ClipsDescendants=true }, parent)
	round(card,8); stroke(card)
	local thumb = mk("ImageLabel", { Size=UDim2.new(1,0,0,82), BackgroundTransparency=1, ScaleType=Enum.ScaleType.Crop,
		ImageTransparency = ready and 0 or 0.35 }, card)
	applyThumbnail(thumb, entry)
	local name = label(card, entry.name, UDim2.new(1,-8,0,22), UDim2.new(0,4,1,-24), 11, C.text)
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Active = false
	local badge = mk("TextLabel", { Size=UDim2.fromOffset(26,26), Position=UDim2.new(1,-32,0,6), BackgroundColor3=Color3.new(),
		BackgroundTransparency=0.35, Text = ready and "▶" or "—", TextColor3=C.white, Font=Enum.Font.GothamBold,
		TextSize = ready and 14 or 12 }, card)
	round(badge,6)
	badge.Active = false
	connect(card.Activated, function() tryLaunch(entry, card) end)
	return card
end

for i, entry in ipairs(featuredOrder) do makeFeaturedCard(featuredScroll, entry, i) end
featuredScroll.CanvasSize = UDim2.fromOffset(6 + #featuredOrder * 130, 0)

label(home, "All Games (" .. tostring(registryCount) .. ")", UDim2.fromOffset(220,24), UDim2.fromOffset(20,264), 13, C.dim, true)
local allList = scrollList(home, UDim2.fromOffset(20,292), UDim2.new(1,-40,0,308))
local gameRows = {}
do
	local y = 0
	for _, entry in ipairs(REGISTRY) do
		gameRows[entry.name] = makeGameRow(allList, entry, y, -8)
		y += 44
	end
	allList.CanvasSize = UDim2.fromOffset(0, y)
end
connect(search:GetPropertyChangedSignal("Text"), function()
	local q = string.lower(search.Text)
	local y = 0
	for _, entry in ipairs(REGISTRY) do
		local row = gameRows[entry.name]
		local hit = q == "" or string.find(string.lower(entry.name), q, 1, true) ~= nil
			or string.find(string.lower(entry.cat or ""), q, 1, true) ~= nil
		row.Visible = hit
		if hit then row.Position = UDim2.fromOffset(0, y); y += 44 end
	end
	allList.CanvasSize = UDim2.fromOffset(0, y)
end)

--==========================================================================
-- Favorites (real: rebuilt from state.favorites)
--==========================================================================
local favPage = newPage("Favorites")
label(favPage, "Favorites", UDim2.fromOffset(400,36), UDim2.fromOffset(24,24), 24, C.text, true)
label(favPage, "Starred from the Home browser. The star persists in the hub config.",
	UDim2.new(1,-48,0,20), UDim2.fromOffset(24,62), 12, C.dim)
local favList = scrollList(favPage, UDim2.fromOffset(24,96), UDim2.new(1,-48,1,-120))
rowRefresh.Favorites = function()
	for _, child in ipairs(favList:GetChildren()) do child:Destroy() end
	local y = 0
	for _, entry in ipairs(REGISTRY) do
		if state.favorites[entry.name] then
			makeGameRow(favList, entry, y, -8)
			y += 44
		end
	end
	if y == 0 then
		emptyState(favList, "Nothing starred yet", "Open Home and click the ☆ on any row. Favorites also jump to the front of the Featured strip.")
		y = 100
	end
	favList.CanvasSize = UDim2.fromOffset(0, y)
end
rowRefresh.Favorites()

--==========================================================================
-- Recent (real: persisted launch history)
--==========================================================================
local recentPage = newPage("Recent")
label(recentPage, "Recent", UDim2.fromOffset(400,36), UDim2.fromOffset(24,24), 24, C.text, true)
label(recentPage, "The last 8 modules this hub actually loaded, newest first.",
	UDim2.new(1,-48,0,20), UDim2.fromOffset(24,62), 12, C.dim)
local recentList = scrollList(recentPage, UDim2.fromOffset(24,96), UDim2.new(1,-48,1,-160))
local function refreshRecent()
	for _, child in ipairs(recentList:GetChildren()) do child:Destroy() end
	local y = 0
	for _, id in ipairs(state.recent) do
		local entry = entryById[id]
		if entry then
			makeGameRow(recentList, entry, y, -8)
			y += 44
		end
	end
	if y == 0 then
		emptyState(recentList, "No launches recorded", "A module is added here the moment the hub successfully loads it — embedded or standalone.")
		y = 100
	end
	recentList.CanvasSize = UDim2.fromOffset(0, y)
end
refreshRecent()
rowRefresh.Recent = refreshRecent
local clearRecent = button(recentPage, "Clear history", UDim2.fromOffset(160,34), UDim2.new(0,24,1,-52))
connect(clearRecent.Activated, function()
	state.recent = {}
	saveConfig(true)
	refreshRecent()
end)

--==========================================================================
-- Embedded module pages
--   One per embeddable target: the game for THIS place, plus Anims.
--   The host frame is what the module parents itself into.
--==========================================================================
local function makeHostPage(name, entry, subtitle)
	local p = newPage(name)
	label(p, name, UDim2.fromOffset(400,30), UDim2.fromOffset(20,12), 18, C.text, true)
	local status = label(p, subtitle or "", UDim2.new(1,-320,0,18), UDim2.fromOffset(20,40), 11, C.dim)
	local reload = button(p, "Reload module", UDim2.fromOffset(140,28), UDim2.new(1,-160,0,16))
	local host = mk("Frame", { Position=UDim2.fromOffset(12,66), Size=UDim2.new(1,-24,1,-78), BackgroundTransparency=1,
		BorderSizePixel=0, ClipsDescendants=true }, p)

	-- Returns ok, err. The button ignores both; the reload API (.13) does not --
	-- an agent that cannot tell a remount from a compile error will report a
	-- broken build as shipped.
	local function mount(force)
		if mountedModule and mountedModule.gkey == entry.gkey and not force then return true end
		status.Text = "loading " .. entry.file .. "..."
		status.TextColor3 = C.dim
		local ok, err = runModule(entry, host)
		if ok then
			status.Text = entry.file .. " embedded · " .. (entry.desc or "")
			status.TextColor3 = C.green
			if rowRefresh.Recent then rowRefresh.Recent() end
		else
			status.Text = tostring(err)
			status.TextColor3 = C.bad
			emptyState(host, "Could not load " .. entry.file, tostring(err) ..
				"\nDeploy it to the Potassium Explorer folder, then press Reload module.")
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
	local _, mount = makeHostPage(activeEntry.name, activeEntry,
		"This place matches " .. activeEntry.name .. " — its controls render inside the hub.")
	mountActiveGame = mount
elseif activeEntry then
	-- Identity matches but the module still owns its own shell. Say so plainly
	-- rather than pretending it is embedded (hub skill S6).
	local p = newPage(activeEntry.name)
	label(p, activeEntry.name, UDim2.fromOffset(500,36), UDim2.fromOffset(24,24), 24, C.text, true)
	label(p, activeEntry.desc or "", UDim2.new(1,-48,0,20), UDim2.fromOffset(24,62), 12, C.dim)
	local note = label(p, "Not yet ported to the hub host — " .. activeEntry.file ..
		" opens its own window. Closing the hub does not close it.", UDim2.new(1,-48,0,40), UDim2.fromOffset(24,92), 12, C.dim)
	note.TextWrapped = true
	local st = label(p, "", UDim2.new(1,-48,0,20), UDim2.fromOffset(24,190), 12, C.dim)
	local go = button(p, "Open " .. activeEntry.name, UDim2.fromOffset(200,38), UDim2.fromOffset(24,142))
	connect(go.Activated, function()
		local ok, err = runModule(activeEntry, nil)
		st.Text = ok and (activeEntry.file .. " loaded") or tostring(err)
		st.TextColor3 = ok and C.green or C.bad
		if ok and rowRefresh.Recent then rowRefresh.Recent() end
	end)
end

local animsEntry = GENERAL[1]
local _, mountAnims = makeHostPage("Anims", animsEntry, "Animation packs from the M7 capture. Backend unchanged; frontend is the hub's.")

-- Admin keeps its own command bar by contract (hub skill S7) -- a launcher page,
-- not a fake panel.
do
	local p = newPage("Admin")
	label(p, "Admin", UDim2.fromOffset(400,36), UDim2.fromOffset(24,24), 24, C.text, true)
	local d = label(p, "The ] command bar with inline completion. It is a bar, not a panel — the hub does not wrap it.",
		UDim2.new(1,-48,0,40), UDim2.fromOffset(24,62), 12, C.dim)
	d.TextWrapped = true
	local st = label(p, "", UDim2.new(1,-48,0,20), UDim2.fromOffset(24,168), 12, C.dim)
	local go = button(p, "Open command bar", UDim2.fromOffset(200,38), UDim2.fromOffset(24,120))
	connect(go.Activated, function()
		local ok, err = runModule({ name = "Admin", file = "admin.lua" }, nil)
		if not ok then
			st.Text = tostring(err)
			st.TextColor3 = C.bad
			return
		end
		st.Text = "admin loader started — waiting for canonical core..."
		st.TextColor3 = C.dim
		task.spawn(function()
			local deadline = os.clock() + 18
			repeat
				local admin = G.Admin
				if type(admin) == "table" and admin._ready == true then
					st.Text = "Admin " .. tostring(admin.build or "unknown build") .. " ready — press ]"
					st.TextColor3 = C.green
					return
				end
				task.wait(0.25)
			until not alive or os.clock() >= deadline
			if alive then
				st.Text = "Admin core did not become ready — check logs/admin.log"
				st.TextColor3 = C.bad
			end
		end)
	end)
	label(p, "Backend is internal/admin_core.lua. Never autoexec it in Critical Strike.",
		UDim2.new(1,-48,0,20), UDim2.fromOffset(24,204), 11, C.dim)
end

--==========================================================================
-- Settings
--==========================================================================
local settings = newPage("Settings")
label(settings,"Settings",UDim2.fromOffset(400,36),UDim2.fromOffset(24,20),24,C.text,true)
local settingsScroll = scrollList(settings, UDim2.fromOffset(24,68), UDim2.new(1,-48,1,-92))
local settingsCard = mk("Frame",{Size=UDim2.new(1,-8,0,10),BackgroundColor3=C.raised,BorderSizePixel=0},settingsScroll)
round(settingsCard,8); stroke(settingsCard)
local function settingToggle(text,get,set,y)
	label(settingsCard,text,UDim2.fromOffset(560,30),UDim2.fromOffset(16,y),13,C.text,true)
	local b=button(settingsCard,get() and "ON" or "OFF",UDim2.fromOffset(70,28),UDim2.new(1,-86,0,y+1))
	connect(b.Activated,function() set(not get()); b.Text=get() and "ON" or "OFF"; saveConfig(true) end)
end
label(settingsCard,"APPEARANCE",UDim2.fromOffset(300,22),UDim2.fromOffset(16,14),11,C.dim,true)
local themeBtn=button(settingsCard,"Theme: "..state.theme,UDim2.fromOffset(180,32),UDim2.fromOffset(16,42))
connect(themeBtn.Activated,function()
	local order={"Midnight","Slate","Carbon"}
	local n=table.find(order,state.theme) or 1
	state.theme=order[n%#order+1]
	themeBtn.Text="Theme: "..state.theme
	saveConfig(true)
end)
label(settingsCard,"Theme is stored but not yet wired to live tokens (hub skill S5).",UDim2.fromOffset(520,20),UDim2.fromOffset(206,48),11,C.dim)
label(settingsCard,"Blur strength",UDim2.fromOffset(200,24),UDim2.fromOffset(16,84),13,C.text,true)
local blurDown=button(settingsCard,"−",UDim2.fromOffset(36,28),UDim2.fromOffset(180,82))
local blurValue=label(settingsCard,tostring(state.blur),UDim2.fromOffset(40,28),UDim2.fromOffset(224,82),13,C.text,true)
blurValue.TextXAlignment=Enum.TextXAlignment.Center
local blurUp=button(settingsCard,"+",UDim2.fromOffset(36,28),UDim2.fromOffset(270,82))
local function alterBlur(d)
	state.blur=math.clamp(state.blur+d,0,12)
	blur.Size=state.blur
	blurValue.Text=tostring(state.blur)
	saveConfig(true)
end
connect(blurDown.Activated,function()alterBlur(-1)end)
connect(blurUp.Activated,function()alterBlur(1)end)
label(settingsCard,"CONFIGURATION",UDim2.fromOffset(300,22),UDim2.fromOffset(16,132),11,C.dim,true)
settingToggle("Autosave", function() return state.autosave end, function(v) state.autosave = v end, 160)
label(settingsCard, "Applies to the hub and to every module it loads — each keeps its own config file.",
	UDim2.fromOffset(700,20), UDim2.fromOffset(16,190), 11, C.dim)
label(settingsCard, "Matching game modules open automatically on every inject.",
	UDim2.fromOffset(700,20), UDim2.fromOffset(16,222), 11, C.dim)

local settingY = 262
local saveNow=button(settingsCard,"Save configuration",UDim2.fromOffset(180,34),UDim2.fromOffset(16,settingY))
connect(saveNow.Activated,function()
	saveConfig(true)
	saveNow.Text="Saved ✓"
	task.delay(1,function() if alive then saveNow.Text="Save configuration" end end)
end)
local resetUi=button(settingsCard,"Reset hub layout",UDim2.fromOffset(180,34),UDim2.fromOffset(208,settingY))
connect(resetUi.Activated,function()
	state.windowX=0; state.windowY=0
	root.Position=UDim2.fromScale(.5,.5)
	saveConfig(true)
end)
label(settingsCard,"Reset only moves the hub window; it never touches a module's own config file.",
	UDim2.new(1,-32,0,36),UDim2.fromOffset(16,settingY+44),11,C.dim)
settingsCard.Size = UDim2.new(1,-8,0,settingY+92)
settingsScroll.CanvasSize = UDim2.fromOffset(0, settingY+100)

--==========================================================================
-- About
--==========================================================================
local about = newPage("About")
label(about,"About",UDim2.fromOffset(400,36),UDim2.fromOffset(24,24),24,C.text,true)
do
	local facts = {
		{ "Hub build", BUILD_VERSION },
		{ "This PlaceId", tostring(game.PlaceId) },
		{ "Matched module", activeEntry and (activeEntry.name .. "  ·  " .. activeEntry.file) or "none — browser is inert here" },
		{ "Registry", tostring(registryCount) .. " games · Admin + Anims general tools" },
		{ "Embedded here", (activeEntry and activeEntry.embed) and "yes (renders in this window)" or "no (module opens standalone)" },
		{ "Config", CONFIG_FILE },
		{ "Log", "logs/rbx_hub.log" },
		{ "Keys", "RightShift show/hide  ·  K unload hub and any embedded module" },
		{ "Posture", "Rung 2 — client-created UI only. No remotes, no game state." },
	}
	local y = 72
	for _, f in ipairs(facts) do
		label(about, f[1], UDim2.fromOffset(180,22), UDim2.fromOffset(24,y), 12, C.dim, true)
		local v = label(about, f[2], UDim2.new(1,-240,0,22), UDim2.fromOffset(200,y), 12, C.text)
		v.TextTruncate = Enum.TextTruncate.AtEnd
		y += 28
	end
	label(about, "Modules stay separate files in git; the hub is one entry point, not one implementation file.",
		UDim2.new(1,-48,0,20), UDim2.fromOffset(24,y+12), 11, C.dim)

	-- Send report (.19). Consent only: nothing leaves this machine unless the
	-- person here presses this, and the line below says exactly what goes.
	local send = button(about, "Send report to the developer", UDim2.fromOffset(260,30), UDim2.fromOffset(24, y+42))
	local result = label(about, "Sends the build stamps, this PlaceId and the tail of your hub/module logs. Nothing else.",
		UDim2.new(1,-320,0,30), UDim2.fromOffset(296, y+42), 11, C.dim)
	result.TextWrapped = true
	connect(send.Activated, function()
		result.Text = "sending..."
		task.spawn(function()
			local api = G[GKEY]
			if not api or not api.report then
				result.Text = "report unavailable in this build"
				return
			end
			local ok, msg = api.report(tostring(game.Players.LocalPlayer and game.Players.LocalPlayer.UserId or "friend"))
			result.Text = (ok and "sent — thank you. " or "could not send — ") .. tostring(msg)
		end)
	end)
end

--==========================================================================
-- Sidebar navigation (built last: the game tab only exists if it matched)
--==========================================================================
do
	if activeEntry then
		navOrder[#navOrder+1] = { "●", activeEntry.name }
		navOrder[#navOrder+1] = { "", "-" }
	end
	navOrder[#navOrder+1] = { "⌂", "Home" }
	navOrder[#navOrder+1] = { "☆", "Favorites" }
	navOrder[#navOrder+1] = { "◷", "Recent" }
	navOrder[#navOrder+1] = { "", "-" }
	navOrder[#navOrder+1] = { ">_", "Admin" }
	navOrder[#navOrder+1] = { "◇", "Anims" }
	navOrder[#navOrder+1] = { "", "-" }
	navOrder[#navOrder+1] = { "⚙", "Settings" }
	navOrder[#navOrder+1] = { "ⓘ", "About" }

	local y = 12
	for _, item in ipairs(navOrder) do
		if item[2] == "-" then
			divider(sidebar, y + 5)
			y += 12
		else
			local b = mk("TextButton", { Size=UDim2.new(1,-18,0,34), Position=UDim2.fromOffset(9,y), BackgroundColor3=C.panel,
				BorderSizePixel=0, Text=item[1].."   "..item[2], TextColor3=C.dim, Font=Enum.Font.GothamMedium, TextSize=13,
				TextXAlignment=Enum.TextXAlignment.Left, AutoButtonColor=false }, sidebar)
			pad(b,10); round(b,7)
			b.TextTruncate = Enum.TextTruncate.AtEnd
			navButtons[item[2]] = b
			connect(b.Activated, function() setPage(item[2]) end)
			y += 38
		end
	end
	divider(sidebar, BODY_H - 66)
	mk("Frame", { Size=UDim2.fromOffset(8,8), Position=UDim2.fromOffset(20,BODY_H-44), BackgroundColor3 = activeEntry and C.green or C.dim,
		BorderSizePixel=0 }, sidebar)
	label(sidebar, activeEntry and "Module ready" or "No module here", UDim2.fromOffset(120,16), UDim2.fromOffset(36,BODY_H-48), 11,
		activeEntry and C.green or C.dim)
	label(sidebar, "build " .. BUILD_VERSION, UDim2.fromOffset(140,16), UDim2.fromOffset(20,BODY_H-26), 10, C.dim)
end

--==========================================================================
-- Lifecycle
--==========================================================================
destroy = function()
	if not alive then return end
	alive = false
	unmountActive()
	for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
	if screen then screen:Destroy() end
	if blur then blur:Destroy() end
	if G[GKEY] and G[GKEY].destroy == destroy then G[GKEY] = nil end
	G[HOST_KEY] = nil
end
--==========================================================================
-- Agent reload API (.13)
--
-- An agent already has a live Luau channel (the Potassium MCP server), but no
-- way to make the client pick up a file it just deployed -- so every iteration
-- ended with "re-inject and tell me what the log says". This closes that loop:
--
--   local H = getgenv().__R3ST_HUB
--   H.reload()          -- remount the module mounted right now
--   H.reload("blr")     -- ...or by id / file / display name
--   H.reload("hub")     -- reload hub.lua itself, in place
--   H.status()          -- what is mounted, and every live build stamp
--   H.targets()         -- what reload() will accept
--
-- Every call returns its result as a string AND writes it to
-- logs/r3st_reload.log, because read_console came back empty on a plain print
-- in live testing (potassium-mcp S2) and a reload you cannot confirm is worse
-- than no reload at all.
--
-- Reload reads from disk through loadModule, so it inherits the Explorer-first
-- path order (S11) -- the same resolution the user's own inject uses, not a
-- second one that could disagree.
--==========================================================================
local RELOAD_LOG = "logs/r3st_reload.log"

local function reloadResult(text)
	pcall(writefile, RELOAD_LOG, ("[%s] %s\n"):format(os.date("%H:%M:%S"), text))
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
	-- Compile the replacement BEFORE tearing anything down. A hub that unloads
	-- itself and then fails to load its successor leaves the user with no UI and
	-- no way back except a manual re-inject -- during a match, on the machine we
	-- cannot reach. The new chunk's own header runs destroy() on us, so the
	-- teardown happens only once the replacement is known to compile.
	local chunk, err = loadModule("hub.lua")
	if not chunk then
		return reloadResult("FAILED hub: " .. tostring(err) .. " (still running " .. BUILD_VERSION .. ")")
	end
	task.defer(function()
		local ok, runErr = pcall(chunk)
		if not ok then
			pcall(writefile, RELOAD_LOG,
				("[%s] FAILED hub runtime: %s\n"):format(os.date("%H:%M:%S"), tostring(runErr)))
		end
	end)
	return reloadResult("OK hub reloading from disk (was " .. BUILD_VERSION .. "; read this file again for the new build)")
end

local function reloadModule(target)
	local id = hostAlias[tostring(target):lower()]
	local mount = id and hostMounts[id]
	if not mount then
		return reloadResult(("FAILED unknown target '%s' -- have: %s")
			:format(tostring(target), table.concat(reloadTargets(), ", ")))
	end
	local ran, ok, err = pcall(mount, true)
	if not ran then
		return reloadResult("FAILED " .. id .. " remount threw: " .. tostring(ok))
	end
	if not ok then
		return reloadResult("FAILED " .. id .. ": " .. tostring(err))
	end
	local entry = hostEntries[id]
	local handle = entry and G[entry.gkey]
	return reloadResult(("OK %s remounted from disk, build %s")
		:format(id, (type(handle) == "table" and tostring(handle.build)) or "unreported"))
end

local function hubStatus()
	local lines = {
		"hub build " .. BUILD_VERSION,
		"mounted: " .. (mountedModule and (tostring(mountedModule.id) .. " / " .. mountedModule.name) or "none"),
		"place " .. tostring(game.PlaceId) .. " universe " .. tostring(game.GameId),
		"targets: " .. table.concat(reloadTargets(), ", "),
	}
	for _, id in ipairs(reloadTargets()) do
		local entry = hostEntries[id]
		if entry then
			local handle = G[entry.gkey]
			lines[#lines + 1] = ("  %s (%s) build %s")
				:format(id, entry.file, (type(handle) == "table" and tostring(handle.build)) or "not loaded")
		end
	end
	local text = table.concat(lines, "\n")
	pcall(writefile, RELOAD_LOG, text .. "\n")
	return text
end

local function reload(target)
	if not alive then
		return reloadResult("FAILED hub is unloaded - re-inject hub.lua")
	end
	local want = tostring(target or ""):lower()
	if want == "hub" then
		return reloadHub()
	end
	if want == "" or want == "active" then
		if not (mountedModule and mountedModule.id) then
			return reloadResult("FAILED nothing mounted -- pass a target: " .. table.concat(reloadTargets(), ", "))
		end
		return reloadModule(mountedModule.id)
	end
	return reloadModule(want)
end

--==========================================================================
-- Report -- how a friend's broken session reaches us (.19)
--
-- When someone else runs the public loadstring, their logs are on THEIR disk
-- and every bug report is "it doesn't work" plus a guess. The receiver for this
-- has existed and been publicly reachable for a month (LXC104, Tailscale
-- Funnel) and had never received one line, because nothing on the client side
-- ever sent one. This is that half.
--
-- Consent, not telemetry: it sends only when a person presses the button, it
-- says exactly what it sends, and there is no timer and no automatic path.
-- Body = build stamps + place/universe + the tail of the hub log and the
-- mounted module's log. No account name is read, no token, no file outside
-- workspace/logs.
--
-- Read what came in with: bash tools/pull_friend_logs.sh
--==========================================================================
local REPORT_URL = "https://discord-bot.tail380340.ts.net/ingest"
local REPORT_TAIL = 24000 -- bytes per log; the receiver caps a post at 2 MB

local function tailFile(path, n)
	local ok, body = pcall(readfile, path)
	if not ok or type(body) ~= "string" then
		return ("(%s unreadable)"):format(path)
	end
	if #body > n then
		body = "...(truncated)...\n" .. body:sub(#body - n)
	end
	return body
end

local function buildReport(note)
	local parts = {
		("== r3st report %s =="):format(os.date("%Y-%m-%d %H:%M:%S")),
		("hub build : %s"):format(BUILD_VERSION),
		("place     : %s   universe: %s"):format(tostring(game.PlaceId), tostring(game.GameId)),
		("module    : %s"):format(activeEntry and (activeEntry.name .. " / " .. activeEntry.file) or "none"),
		("executor  : %s"):format((identifyexecutor and select(1, pcall(identifyexecutor))) and identifyexecutor() or "unknown"),
		("note      : %s"):format(note and note ~= "" and note or "(none given)"),
		("status    : %s"):format(tostring(hubStatus())),
		"", "---- logs/rbx_hub.log ----", tailFile("logs/rbx_hub.log", REPORT_TAIL),
	}
	if activeEntry then
		local name = activeEntry.file:gsub("%.lua$", "")
		parts[#parts + 1] = ("---- logs/%s.log ----"):format(name)
		parts[#parts + 1] = tailFile(("logs/%s.log"):format(name), REPORT_TAIL)
	end
	return table.concat(parts, "\n")
end

-- Returns ok, message. Never raises: a failed report must not take the UI with
-- it, and the user is entitled to a reason rather than a silent no-op.
local function sendReport(who, note)
	local body = buildReport(note)
	pcall(writefile, "logs/r3st_report_last.txt", body) -- always keep a local copy
	local req = (syn and syn.request) or (http and http.request) or http_request or request
	if type(req) ~= "function" then
		return false, "this executor exposes no HTTP request function; logs/r3st_report_last.txt was written instead"
	end
	who = (tostring(who or "friend"):gsub("[^%w%-_]", "")):sub(1, 24)
	if who == "" then who = "friend" end
	local ok, res = pcall(req, {
		Url = REPORT_URL .. "?who=" .. who,
		Method = "POST",
		Headers = { ["Content-Type"] = "text/plain" },
		Body = body,
	})
	if not ok then
		return false, "send failed: " .. tostring(res)
	end
	local code = type(res) == "table" and (res.StatusCode or res.Status or 0) or 0
	if code >= 200 and code < 300 then
		hubLog("info", "report sent as " .. who .. " (" .. #body .. " bytes)")
		return true, ("sent %d bytes as %s"):format(#body, who)
	end
	return false, "receiver returned " .. tostring(code)
end

G[GKEY] = {
	destroy = destroy,
	build = BUILD_VERSION,
	reload = reload,
	status = hubStatus,
	targets = reloadTargets,
	logFile = RELOAD_LOG,
	report = sendReport,
	reportPreview = buildReport,
}
connect(close.Activated, destroy)
connect(minimize.Activated, function()
	content.Visible = not content.Visible
	sidebar.Visible = content.Visible
	blur.Enabled = content.Visible
	root.Size = content.Visible and UDim2.fromOffset(W,H) or UDim2.fromOffset(W,64)
end)

local dragging, dragStart, startPos = false, nil, nil
connect(header.InputBegan, function(i)
	if i.UserInputType == Enum.UserInputType.MouseButton1 then
		dragging = true; dragStart = i.Position; startPos = root.Position
	end
end)
connect(UIS.InputChanged, function(i)
	if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then
		local d = i.Position - dragStart
		root.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset+d.X, startPos.Y.Scale, startPos.Y.Offset+d.Y)
	end
end)
connect(UIS.InputEnded, function(i)
	if i.UserInputType == Enum.UserInputType.MouseButton1 and dragging then
		dragging = false
		state.windowX = root.Position.X.Offset
		state.windowY = root.Position.Y.Offset
		saveConfig()
	end
end)
connect(UIS.InputBegan, function(i, gp)
	if i.KeyCode == Enum.KeyCode.RightShift then
		screen.Enabled = not screen.Enabled
		blur.Enabled = screen.Enabled
		return
	end
	if gp then return end
	if i.KeyCode == Enum.KeyCode.K then destroy() end
end)

setPage(state.page)
hubLog("info", "boot place=" .. tostring(game.PlaceId) .. " universe=" .. tostring(game.GameId)
	.. " registry=" .. tostring(registryCount)
	.. " matched=" .. (activeEntry and activeEntry.name or "none"))
if not activeEntry then
	-- The universe id is what a private-server row needs, so print it rather than
	-- making the next session re-derive it.
	hubLog("warn", "no registry row for universe " .. tostring(game.GameId)
		.. " (place " .. tostring(game.PlaceId) .. "). If this is a VIP server of a supported game,"
		.. " that entry is missing its gameId.")
end

-- Autoload is evaluated only after identity matching (hub skill S2.6).
if activeEntry and state.autoOpen then
	task.defer(function()
		if not alive then return end
		if activeEntry.embed and mountActiveGame then
			setPage(activeEntry.name)
			mountActiveGame(false)
		else
			runModule(activeEntry, nil)
		end
	end)
end

-- Mount whichever host page the user is already on, so reopening the hub on the
-- game tab shows the controls instead of an empty frame.
task.defer(function()
	if not alive then return end
	if activeEntry and activeEntry.embed and state.page == activeEntry.name and mountActiveGame then
		mountActiveGame(false)
	elseif state.page == "Anims" then
		mountAnims(false)
	end
end)

-- Mount on first visit to a host page rather than at boot: nothing loads a
-- module the user has not asked for.
if navButtons[ "Anims" ] then
	connect(navButtons["Anims"].Activated, function() mountAnims(false) end)
end
if activeEntry and activeEntry.embed and navButtons[activeEntry.name] and mountActiveGame then
	connect(navButtons[activeEntry.name].Activated, function() mountActiveGame(false) end)
end
