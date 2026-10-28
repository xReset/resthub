--------------------------------------------------------------------------
-- Project Slayers 2 (Ouwland) hub module
-- PlaceId 136406881576517 / GameId 5595353122. Dump 2026-09-23T06:03:40Z.
-- Candidates and citations: docs/feature-candidates/project-slayers-2.md
--
-- Rung 1 (reads only)
--   Quest ESP: Pickup TaskSpecs in NPC dialogue modules (1817.lua:28-32 Lost
--     Pages), gameSettings.UnderwaterRockSpots (0809.lua:101), and the part
--     PickupState spawns as <ObjectText><i> (0737.lua:50-92).
--   Black Market: the game's own TimedVendor.GetState/GetSpotIndex/GetStock
--     (0760.lua:52-150) on the Black Marketer config (1739.lua: 11 spawns,
--     every 7200s, active 1800s). The server placement call is not in the
--     dump (1969.lua:715), so the live NPC is matched and the result logged.
--   Timers: TimedEvents (0759.lua) cycles from GetServerTimeNow.
--   ESP: tag "Humanoids" (0012.lua:131) + Player "Level" attribute
--     (0557.lua:174); chests "Chest"/"LootDrop" (0809.lua:308); shrines and
--     spawn crystals via their prompt tags; world-event tags (0098-0102).
--   HUD: SHC cooldown NumberValues (0763.lua:75-100), Stamina (0193.lua:15).
-- Rung 3-4 (local state the game re-applies)
--   Speed: WalkSpeed child with top Priority (0007.lua:512-532,592-597).
--   Instant prompts: ProximityPrompt.HoldDuration is a client hold
--     (0439.lua:104-118).
--   No drowning: the Swimming LocalScript owns Breath and reports
--     DrownDamage itself (2560.lua:171,322-325); Breath is pinned to 1.
--   Walk on water: SwimParts (0007.lua:191) collide locally.
-- Rung 5 (own physics, visible)
--   Free dash: game's client Dash.Hold (2196.lua:21) when Perform is on
--     cooldown. Teleports: HRP CFrame. Move while stunned (SESSION).
-- Session only, boot OFF
--   Auto block: nearby "<x>_Swings" effect -> real F press (2194.lua:192-199,
--     0462.lua:569). Auto grab: TP to a new chest/event and fire its prompt.
--   Low-HP kill (EXPERIMENTAL): combat mobs are unanchored with no explicit
--     owner (1969.lua:469 vs 634), so a nearby client can own them. Only acts
--     on mobs isnetworkowner() confirms; logs owned/not-owned counts.
-- Server-owned, not attempted: skill cooldowns, stamina, spins, block regen.
--
-- Hub-only: without __R3ST_HOST it logs and exits. K = unload.
--------------------------------------------------------------------------

local BUILD_VERSION = "2026-09-23.11"
local GKEY = "__PS2_HUB"
local EXPECTED_PLACE = 136406881576517
local EXPECTED_GAME = 5595353122
if game.GameId ~= EXPECTED_GAME and game.PlaceId ~= EXPECTED_PLACE then return end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")
local StarterGui = game:GetService("StarterGui")

local LP = Players.LocalPlayer
local GENV = (type(getgenv) == "function" and getgenv()) or _G
if GENV[GKEY] and GENV[GKEY].destroy then pcall(GENV[GKEY].destroy) end

local function fallbackLog(msg)
	pcall(function()
		local path = "logs/ps2_hub.log"
		local old = (isfile and isfile(path) and readfile(path)) or ""
		writefile(path, old .. os.date("[%Y-%m-%d %H:%M:%S] ") .. tostring(msg) .. "\n")
	end)
end
local Log = { info = fallbackLog, warn = fallbackLog }
pcall(function() Log = loadfile("log.lua")()("ps2_hub") end)

local HOST = (type(GENV.__R3ST_HOST) == "table"
	and typeof(GENV.__R3ST_HOST.host) == "Instance") and GENV.__R3ST_HOST or nil
if not HOST then
	Log.warn("no R3ST host; ps2_hub is hub-only, load it from hub.lua")
	return
end

local CoreGui = game:GetService("CoreGui")
if type(cloneref) == "function" then
	local ok, copy = pcall(cloneref, CoreGui)
	if ok and copy then CoreGui = copy end
end

--------------------------------------------------------------------------
-- config
--------------------------------------------------------------------------
local CONFIG_FILE = "ps2_hub_config.json"
local defaults = {
	pickupEsp = true,
	pickupMaxStuds = 6000,
	marketEsp = true,
	marketNext = true,
	notify = true,
	eventEsp = true,
	chestEsp = true,
	shrineEsp = false,
	crystalEsp = false,
	muzanMarker = true,
	mobEsp = false,
	bossOnly = false,
	playerEsp = false,
	espMaxStuds = 600,
	hud = true,
	freeDash = false,
	freeDashGap = 0.35,
	speedOn = false,
	speedValue = 30,
	instantPrompts = false,
	noDrown = false,
	walkOnWater = false,
	blockRange = 14,
	blockHold = 0.35,
	grabRange = 1500,
	grabReturn = true,
	killThreshold = 0.2,
	killRange = 40,
}
local CFG = table.clone(defaults)
do
	local ok, raw = pcall(readfile, CONFIG_FILE)
	if ok then
		local ok2, saved = pcall(HttpService.JSONDecode, HttpService, raw)
		if ok2 and type(saved) == "table" then
			for k, fallback in next, defaults do
				if typeof(saved[k]) == typeof(fallback) then CFG[k] = saved[k] end
			end
		end
	end
end
local savePending = false
local function saveConfig()
	if savePending then return end
	savePending = true
	task.delay(0.6, function()
		savePending = false
		local ok, raw = pcall(HttpService.JSONEncode, HttpService, CFG)
		if ok then pcall(writefile, CONFIG_FILE, raw) end
	end)
end

local S = {
	alive = true, conns = {},
	marks = {}, usedMarks = {},
	pickups = {}, muzan = nil, liveCount = 0,
	-- session only, boot OFF
	stunMove = false, autoBlock = false, autoGrab = false, lowKill = false,
	freeDashes = 0, lastFreeDash = 0,
	swingsSeen = 0, blocks = 0, blockUntil = 0, fHeld = false,
	speedValue = nil, dashOrig = nil,
	promptOrig = setmetatable({}, { __mode = "k" }),
	waterOrig = {}, swimState = nil, swimChar = nil,
	market = nil, marketLive = nil, marketNotified = -1, marketChecked = -1,
	events = {}, eventLog = {}, grabbing = false, grabs = 0,
	teleTargets = {}, teleIndex = 1,
	kills = 0, ownedSeen = 0, unownedSeen = 0,
	errors = 0,
}
local function connect(signal, fn)
	local c = signal:Connect(fn)
	S.conns[#S.conns + 1] = c
	return c
end

--------------------------------------------------------------------------
-- game modules (all client-side, already loaded by the game)
--------------------------------------------------------------------------
local function find(root, path)
	local node = root
	for part in string.gmatch(path, "[^/]+") do
		node = node and node:FindFirstChild(part)
	end
	return node
end
-- Requiring a game ModuleScript drops the calling thread to the game's
-- identity, after which the hub's own frames throw "lacking capability
-- Plugin" (build .3 died in moduleShell on it). Require on a throwaway
-- coroutine so the drop stays there.
local function safeRequire(mod)
	local co = coroutine.create(function() return require(mod) end)
	local ok, okReq, result = pcall(coroutine.resume, co)
	if ok and okReq then return result end
	return nil
end
local function req(path)
	local node = find(ReplicatedStorage, path)
	if not node then return nil end
	return safeRequire(node)
end

local DashHandler = req("CAM/Client/Modules/GamePlay/Dash_Handler")
local DashSkill = req("Skills/Misc/Dashes/Dash")
local MuzanSettings = req("CAM/Global/MuzanSettings")
local GameSettings = req("CAM/Global/gameSettings")
local TimedVendor = req("CAM/Global/Subsets/Gameplay/TimedVendor")
local TimedEvents = req("CAM/Global/Subsets/Gameplay/TimedEvents")
local MarketCfg = req("Ouwland/Content/Misc/Npcs/Black Marketer")

local function valuesFolder()
	return find(ReplicatedStorage, "Player_Service/Values/" .. LP.Name)
end
local function myRoot()
	local c = LP.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end
local function isStunned(vf)
	return vf ~= nil and (vf:FindFirstChild("Stun") or vf:FindFirstChild("CombatStun")
		or vf:FindFirstChild("Strict_Stun")) ~= nil
end
local function posOf(inst)
	if not inst then return nil end
	if inst:IsA("BasePart") then return inst.Position end
	if inst:IsA("Model") then
		local ok, cf = pcall(inst.GetPivot, inst)
		return ok and cf.Position or nil
	end
	if inst:IsA("Attachment") then return inst.WorldPosition end
	local p = inst:FindFirstAncestorWhichIsA("BasePart") or inst:FindFirstAncestorWhichIsA("Model")
	return p and posOf(p) or nil
end
local function notify(title, text)
	Log.info("notify " .. title .. ": " .. text)
	if not CFG.notify then return end
	pcall(StarterGui.SetCore, StarterGui, "SendNotification", { Title = title, Text = text, Duration = 8 })
end
local function fmtTime(sec)
	sec = math.max(0, math.floor(sec))
	if sec >= 3600 then return string.format("%dh%02dm", sec // 3600, (sec % 3600) // 60) end
	return string.format("%dm%02ds", sec // 60, sec % 60)
end

--------------------------------------------------------------------------
-- teleport
--------------------------------------------------------------------------
local function teleport(pos)
	local root = myRoot()
	if not root or not pos then return false end
	root.AssemblyLinearVelocity = Vector3.zero
	root.CFrame = CFrame.new(pos + Vector3.new(0, 4, 0))
	return true
end

--------------------------------------------------------------------------
-- quest pickups: static spots
--------------------------------------------------------------------------
-- ObjectText of every PickupState quest (QuestStates 1946-1965, 0739.lua:12).
local PICKUP_TEXTS = {
	["Lost Page"] = true, ["Gemstone"] = true, ["Lucky Penny"] = true, ["Coin"] = true,
	["Nichirin Blade"] = true, ["Permit Stamp"] = true, ["Jewelry Box"] = true,
	["Reaper Scroll"] = true, ["Soryu Scroll"] = true, ["Tai Chi Scroll"] = true,
	["Sea Crystal"] = true,
}

local function addPickup(key, label, npc, pos)
	S.pickups[#S.pickups + 1] = { key = key, label = label, npc = npc, pos = pos }
end

local function collectStaticPickups()
	local content = find(ReplicatedStorage, "Ouwland/Content")
	if content then
		for _, mod in ipairs(content:GetDescendants()) do
			if mod:IsA("ModuleScript") and string.find(mod:GetFullName(), "Dialogues.Quests", 1, true) then
				local data = safeRequire(mod)
				if type(data) == "table" then
					for _, option in next, data do
						local specs = type(option) == "table" and option.TaskSpecs
						if type(specs) == "table" then
							for taskName, spec in next, specs do
								if type(spec) == "table" and spec.Type == "Pickup" and type(spec.Positions) == "table" then
									for i, pos in ipairs(spec.Positions) do
										if typeof(pos) == "Vector3" then
											addPickup(mod.Name .. "|" .. tostring(taskName) .. "|" .. i, tostring(taskName), mod.Name, pos)
										end
									end
								end
							end
						end
					end
				end
			end
		end
	end
	local rocks = GameSettings and GameSettings.UnderwaterRockSpots and GameSettings.UnderwaterRockSpots[EXPECTED_PLACE]
	if type(rocks) == "table" then
		for i, pos in ipairs(rocks) do
			if typeof(pos) == "Vector3" then addPickup("rock|" .. i, "Sea Crystal", "breathing trainer", pos) end
		end
	end
	return #S.pickups
end

-- Tracked on ChildAdded/Removed: scanning every workspace child each frame
-- was the ESP's main fps cost (build .7).
S.liveSet = {}
local function trackLive(child)
	local prefix = string.match(child.Name, "^(.-)%d+$")
	if prefix and PICKUP_TEXTS[prefix] then S.liveSet[child] = prefix end
end
local function livePickups()
	local out = {}
	for child, label in next, S.liveSet do
		if child.Parent then
			local p = posOf(child)
			if p then out[#out + 1] = { inst = child, label = label, pos = p } end
		else
			S.liveSet[child] = nil
		end
	end
	return out
end

--------------------------------------------------------------------------
-- Black Market prediction (the game's own deterministic picker)
--------------------------------------------------------------------------
local function marketFor(cycleOffset)
	local tv = MarketCfg and MarketCfg.TimedVendor
	local spawns = MarketCfg and MarketCfg.Spawns
	if not (TimedVendor and tv and type(spawns) == "table" and #spawns > 0) then return nil end
	local state = TimedVendor.GetState(tv)
	local cycle = state.Cycle + (cycleOffset or 0)
	local idx = TimedVendor.GetSpotIndex(tv, cycle, #spawns)
	local stock = {}
	local ok, list = pcall(TimedVendor.GetStock, tv, cycle)
	if ok and type(list) == "table" then
		for _, item in ipairs(list) do stock[#stock + 1] = type(item) == "table" and tostring(item.Name) or tostring(item) end
	end
	return {
		cycle = cycle, index = idx, pos = spawns[idx].Position, stock = stock,
		active = (cycleOffset or 0) == 0 and state.Active, edgeIn = state.NextEdgeIn,
	}
end

local function findLiveMarketer()
	-- Workspace only: the Black Marketer template in ReplicatedStorage carries
	-- the same tag and would read as a false LIVE position.
	for _, model in ipairs(CollectionService:GetTagged("Humanoids")) do
		if model.Name == "Black Marketer" and model:IsA("Model") and model:IsDescendantOf(workspace) then return model end
	end
	local root = workspace:FindFirstChild("Humanoids")
	return root and root:FindFirstChild("Black Marketer", true) or nil
end

local function tickMarket()
	local m = marketFor(0)
	S.market = m
	S.marketNextInfo = marketFor(1)
	if not m then return end
	local live = findLiveMarketer()
	S.marketLive = live and posOf(live) or nil
	if m.active and S.marketNotified ~= m.cycle then
		S.marketNotified = m.cycle
		notify("Black Market", string.format("Active for %s at spot #%d (%dm away)", fmtTime(m.edgeIn), m.index,
			myRoot() and (m.pos - myRoot().Position).Magnitude or 0))
	end
	if S.marketLive and S.marketChecked ~= m.cycle then
		S.marketChecked = m.cycle
		local off = (S.marketLive - m.pos).Magnitude
		Log.info(string.format("market live cycle=%d predicted=#%d off=%.1f %s", m.cycle, m.index, off,
			off < 20 and "MATCH" or "MISMATCH"))
	end
end

--------------------------------------------------------------------------
-- world events / chests: tag watch, notify, auto grab
--------------------------------------------------------------------------
local EVENT_TAGS = {
	Chest = "Chest", LootDrop = "Loot", ChestMound = "Chest mound",
	Foxfire = "Foxfire", FoxfireField = "Foxfire field", FoxfireLantern = "Foxfire lantern",
	SerpentKey = "Serpent key", SerpentBox = "Serpent box", StudyProp = "Study prop",
	IceveilFootprint = "Iceveil footprint",
}
local GRAB_TAGS = { Chest = true, LootDrop = true, ChestMound = true, SerpentKey = true, FoxfireLantern = true }

local function promptIn(inst)
	return inst and inst:FindFirstChildWhichIsA("ProximityPrompt", true)
end

local function grab(inst, tag)
	if not S.autoGrab or S.grabbing or not inst.Parent then return end
	local root = myRoot()
	local p = posOf(inst)
	if not root or not p or (p - root.Position).Magnitude > CFG.grabRange then return end
	S.grabbing = true
	task.spawn(function()
		local back = root.CFrame
		task.wait(0.3)
		if S.alive and inst.Parent then
			teleport(p)
			task.wait(0.35)
			local prompt = promptIn(inst)
			if prompt and fireproximityprompt then
				pcall(fireproximityprompt, prompt)
				S.grabs += 1
				Log.info("grab " .. tag .. " " .. inst:GetFullName())
			end
			task.wait(0.6)
			if CFG.grabReturn and myRoot() then myRoot().CFrame = back end
		end
		S.grabbing = false
	end)
end

local function onEventAdded(tag, inst)
	S.events[inst] = tag
	local p = posOf(inst)
	local root = myRoot()
	local d = (p and root) and (p - root.Position).Magnitude or 0
	table.insert(S.eventLog, 1, string.format("%s %s  %dm", os.date("%H:%M"), EVENT_TAGS[tag], d))
	if #S.eventLog > 6 then S.eventLog[7] = nil end
	if GRAB_TAGS[tag] then grab(inst, tag) end
end

for tag in next, EVENT_TAGS do
	for _, inst in ipairs(CollectionService:GetTagged(tag)) do S.events[inst] = tag end
	connect(CollectionService:GetInstanceAddedSignal(tag), function(inst)
		if S.alive then pcall(onEventAdded, tag, inst) end
	end)
	connect(CollectionService:GetInstanceRemovedSignal(tag), function(inst) S.events[inst] = nil end)
end

--------------------------------------------------------------------------
-- teleport targets: shrines, spawn crystals, NPCs, Black Market
--------------------------------------------------------------------------
local function rebuildTargets()
	local list = {}
	for _, prompt in ipairs(CollectionService:GetTagged("ShrineProximityPrompt")) do
		local p = posOf(prompt.Parent)
		if p then list[#list + 1] = { name = "Shrine: " .. prompt.Name, pos = p } end
	end
	for _, prompt in ipairs(CollectionService:GetTagged("SpawnCrystalProximityPrompt")) do
		local p = posOf(prompt.Parent)
		if p then list[#list + 1] = { name = "Crystal: " .. prompt.Name, pos = p } end
	end
	local regions = find(workspace, "Humanoids/Regions")
	if regions then
		for _, region in ipairs(regions:GetChildren()) do
			local holder = region:FindFirstChild("StationaryNpcs")
			for _, npc in ipairs(holder and holder:GetChildren() or {}) do
				local p = posOf(npc)
				if p then list[#list + 1] = { name = "NPC: " .. npc.Name, pos = p } end
			end
		end
	end
	table.sort(list, function(a, b) return a.name < b.name end)
	S.teleTargets = list
	if S.teleIndex > #list then S.teleIndex = 1 end
end

--------------------------------------------------------------------------
-- ESP layer (full-screen, kept outside the module root)
--------------------------------------------------------------------------
for _, child in ipairs(workspace:GetChildren()) do trackLive(child) end
connect(workspace.ChildAdded, trackLive)
connect(workspace.ChildRemoved, function(child) S.liveSet[child] = nil end)

local layer = Instance.new("ScreenGui")
layer.Name = "PS_" .. tostring(math.random(1000, 9999))
layer.ResetOnSpawn = false
layer.IgnoreGuiInset = true
layer.DisplayOrder = 2147483646
layer.Parent = CoreGui

local hudLabel = Instance.new("TextLabel")
hudLabel.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
hudLabel.BackgroundTransparency = 0.35
hudLabel.BorderSizePixel = 0
hudLabel.AnchorPoint = Vector2.new(1, 0.5)
hudLabel.Position = UDim2.new(1, -16, 0.5, 0)
hudLabel.Size = UDim2.fromOffset(300, 48)
hudLabel.AutomaticSize = Enum.AutomaticSize.Y
hudLabel.Font = Enum.Font.Code
hudLabel.TextSize = 17
hudLabel.TextColor3 = Color3.fromRGB(230, 235, 245)
hudLabel.TextXAlignment = Enum.TextXAlignment.Left
hudLabel.TextYAlignment = Enum.TextYAlignment.Top
hudLabel.RichText = true
hudLabel.Text = ""
hudLabel.Visible = false
hudLabel.Parent = layer
local hudPad = Instance.new("UIPadding")
hudPad.PaddingLeft, hudPad.PaddingTop, hudPad.PaddingBottom = UDim.new(0, 8), UDim.new(0, 6), UDim.new(0, 6)
hudPad.Parent = hudLabel

local function markFor(key)
	local m = S.marks[key]
	if not m then
		local text = Instance.new("TextLabel")
		text.BackgroundTransparency = 1
		text.AnchorPoint = Vector2.new(0.5, 1)
		text.Size = UDim2.fromOffset(0, 0)
		text.AutomaticSize = Enum.AutomaticSize.XY
		text.Font = Enum.Font.Code
		text.TextSize = 15
		text.TextStrokeTransparency = 0.25
		text.Visible = false
		text.Parent = layer
		m = { text = text }
		S.marks[key] = m
	end
	S.usedMarks[key] = true
	return m
end

-- Content refreshes at 10 Hz (renderFrame); placement runs every frame
-- (placeMarks) from the cached world point, so labels track the camera.
local function draw(key, worldPos, str, color)
	local m = markFor(key)
	m.world = worldPos
	if m.text.Text ~= str then m.text.Text = str end
	if m.text.TextColor3 ~= color then m.text.TextColor3 = color end
end

local function placeMarks()
	local camera = workspace.CurrentCamera
	if not camera then return end
	for _, m in next, S.marks do
		if m.world then
			local point, onScreen = camera:WorldToViewportPoint(m.world)
			if onScreen then
				m.text.Position = UDim2.fromOffset(point.X, point.Y)
				if not m.text.Visible then m.text.Visible = true end
			elseif m.text.Visible then
				m.text.Visible = false
			end
		end
	end
end

local COL_PICK = Color3.fromRGB(255, 215, 90)
local COL_LIVE = Color3.fromRGB(90, 255, 140)
local COL_MOB = Color3.fromRGB(255, 120, 110)
local COL_BOSS = Color3.fromRGB(255, 70, 220)
local COL_PLAYER = Color3.fromRGB(60, 140, 255)
local COL_MUZAN = Color3.fromRGB(200, 30, 40)
local COL_MARKET = Color3.fromRGB(190, 150, 255)
local COL_EVENT = Color3.fromRGB(255, 170, 60)
local COL_WORLD = Color3.fromRGB(150, 230, 255)

local function renderPickups(camera, origin)
	local live = livePickups()
	S.liveCount = #live
	for _, p in ipairs(live) do
		local d = (p.pos - origin).Magnitude
		if d <= CFG.pickupMaxStuds then
			draw("live|" .. p.inst:GetDebugId(), p.pos, string.format("● %s  %dm", p.label, d), COL_LIVE, camera)
		end
	end
	for _, p in ipairs(S.pickups) do
		local d = (p.pos - origin).Magnitude
		if d <= CFG.pickupMaxStuds then
			local near = false
			for _, l in ipairs(live) do
				if (l.pos - p.pos).Magnitude < 8 then near = true break end
			end
			if not near then
				draw("s|" .. p.key, p.pos, string.format("%s  %dm\n%s", p.label, d, p.npc), COL_PICK, camera)
			end
		end
	end
end

local function renderMarket(camera, origin)
	local m = S.market
	if not m then return end
	local pos = S.marketLive or m.pos
	local tag = S.marketLive and "LIVE" or (m.active and "active" or ("in " .. fmtTime(m.edgeIn)))
	draw("market", pos + Vector3.new(0, 4, 0),
		string.format("Black Market #%d  %s  %dm", m.index, tag, (pos - origin).Magnitude), COL_MARKET, camera)
	local n = S.marketNextInfo
	if CFG.marketNext and n and n.index ~= m.index then
		draw("market_next", n.pos + Vector3.new(0, 4, 0),
			string.format("next Black Market #%d  %dm", n.index, (n.pos - origin).Magnitude), COL_MARKET, camera)
	end
end

local function renderWorld(camera, origin)
	if CFG.eventEsp or CFG.chestEsp then
		for inst, tag in next, S.events do
			local isChest = tag == "Chest" or tag == "LootDrop" or tag == "ChestMound"
			if inst.Parent and ((isChest and CFG.chestEsp) or (not isChest and CFG.eventEsp)) then
				local p = posOf(inst)
				if p then
					draw("e|" .. inst:GetDebugId(), p + Vector3.new(0, 2, 0),
						string.format("%s  %dm", EVENT_TAGS[tag], (p - origin).Magnitude), COL_EVENT, camera)
				end
			end
		end
	end
	if CFG.shrineEsp or CFG.crystalEsp then
		for _, t in ipairs(S.teleTargets) do
			local isShrine = string.sub(t.name, 1, 6) == "Shrine"
			local isCrystal = string.sub(t.name, 1, 7) == "Crystal"
			if (isShrine and CFG.shrineEsp) or (isCrystal and CFG.crystalEsp) then
				draw("t|" .. t.name, t.pos + Vector3.new(0, 3, 0),
					string.format("%s  %dm", t.name, (t.pos - origin).Magnitude), COL_WORLD, camera)
			end
		end
	end
end

-- Chams, no text. Live census 2026-09-23: 83 of 99 "Humanoids"-tagged models
-- are templates in ReplicatedStorage (the old ESP drew them as phantom
-- enemies); real enemies are workspace models with IsMob=true. Bosses carry
-- SkillBrain=1 (Akazo, Datai, Gyutai, Reaper); BossInfo marks only trainee
-- bosses. The horse mount is IsMob with NoOverhead and is skipped.
-- Highlights live under cloned CoreGui (a ScreenGui parent never renders them,
-- potassium-dev 5.4); Roblox renders at most 31, so the nearest 30 get one.
local chamFolder = Instance.new("Folder")
chamFolder.Name = "PS_Chams"
chamFolder.Parent = CoreGui
S.chams = {}
local MAX_CHAMS = 30

local function chamFor(model, color)
	local h = S.chams[model]
	if not h or not h.Parent then
		h = Instance.new("Highlight")
		h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		h.FillTransparency = 0.55
		h.OutlineColor = Color3.new(1, 1, 1)
		h.OutlineTransparency = 0
		h.Adornee = model
		h.Parent = chamFolder
		S.chams[model] = h
	end
	if h.FillColor ~= color then h.FillColor = color end
	return h
end

local function isBoss(model)
	return model:GetAttribute("SkillBrain") == 1 or model:FindFirstChild("BossInfo") ~= nil
end

local function renderHumanoids(origin)
	local list = {}
	local humRoot = workspace:FindFirstChild("Humanoids")
	if CFG.mobEsp or CFG.playerEsp then
		for _, model in ipairs(CollectionService:GetTagged("Humanoids")) do
			if model:IsA("Model") and model ~= LP.Character and humRoot and model:IsDescendantOf(humRoot) then
				local hum = model:FindFirstChildOfClass("Humanoid")
				local root = model:FindFirstChild("HumanoidRootPart")
				if hum and root and hum.Health > 0 then
					local player = Players:GetPlayerFromCharacter(model)
					local color
					if player then
						if CFG.playerEsp then color = COL_PLAYER end
					elseif CFG.mobEsp and model:GetAttribute("IsMob") == true and not model:GetAttribute("NoOverhead") then
						local boss = isBoss(model)
						if boss or not CFG.bossOnly then color = boss and COL_BOSS or COL_MOB end
					end
					local d = (root.Position - origin).Magnitude
					if color and d <= CFG.espMaxStuds then list[#list + 1] = { model = model, d = d, color = color } end
				end
			end
		end
	end
	table.sort(list, function(a, b) return a.d < b.d end)
	local used = {}
	for i = 1, math.min(#list, MAX_CHAMS) do
		chamFor(list[i].model, list[i].color)
		used[list[i].model] = true
	end
	S.chamCount = math.min(#list, MAX_CHAMS)
	for model, h in next, S.chams do
		if not used[model] then
			h:Destroy()
			S.chams[model] = nil
		end
	end
end

local function hudText()
	local lines = {}
	local vf = valuesFolder()
	local st = vf and vf:FindFirstChild("Stamina")
	if st and st:IsA("ValueBase") then
		local okMax, max = pcall(function() return st.MaxValue end)
		lines[#lines + 1] = string.format("Stamina  %d / %d", st.Value, okMax and tonumber(max) or 0)
	end
	local shc = LP.Character and LP.Character:FindFirstChild("SHC")
	if shc then
		local now = os.clock()
		local rows = {}
		for _, cd in ipairs(shc:GetChildren()) do
			if cd:IsA("NumberValue") then
				local started = cd:GetAttribute("Started")
				local left = typeof(started) == "number" and (cd.Value - (now - started)) or cd.Value
				if left > 0 and left < 9000 then rows[#rows + 1] = { cd.Name, left } end
			end
		end
		table.sort(rows, function(a, b) return a[2] < b[2] end)
		for _, r in ipairs(rows) do
			lines[#lines + 1] = string.format("<font color=\"#ffb86b\">%-14s %5.1fs</font>", string.sub(r[1], 1, 14), r[2])
		end
	end
	local m = S.market
	if m then
		lines[#lines + 1] = string.format("<font color=\"#be96ff\">Black Market %s %s</font>",
			m.active and "closes" or "opens", fmtTime(m.edgeIn))
	end
	return table.concat(lines, "\n")
end

local function renderFrame()
	local camera = workspace.CurrentCamera
	local root = myRoot()
	if not camera or not root then return end
	local origin = root.Position
	table.clear(S.usedMarks)

	if CFG.pickupEsp then renderPickups(camera, origin) end
	if CFG.marketEsp then renderMarket(camera, origin) end
	renderWorld(camera, origin)
	renderHumanoids(origin)
	if CFG.muzanMarker and S.muzan then
		draw("muzan", S.muzan, string.format("Muzan lair  %dm", (S.muzan - origin).Magnitude), COL_MUZAN, camera)
	end

	for key, m in next, S.marks do
		if not S.usedMarks[key] then
			m.text:Destroy()
			S.marks[key] = nil
		end
	end

	hudLabel.Visible = CFG.hud
	if CFG.hud then hudLabel.Text = hudText() end
end

local acc = 0
connect(RunService.RenderStepped, function(dt)
	if not S.alive then return end
	pcall(placeMarks)
	acc += dt
	if acc < 0.1 then return end
	acc = 0
	local ok, err = pcall(renderFrame)
	if not ok then
		S.errors += 1
		if S.errors == 1 or S.errors % 120 == 0 then Log.warn("render error #" .. S.errors .. ": " .. tostring(err)) end
	end
end)

--------------------------------------------------------------------------
-- free dash: fall back to the game's own client dash when Perform is on cooldown
--------------------------------------------------------------------------
local function freeDash(dir)
	local char = LP.Character
	local shc = char and char:FindFirstChild("SHC")
	local vf = valuesFolder()
	if not (shc and DashSkill and type(DashSkill.Hold) == "function") then return false end
	if isStunned(vf) or (vf and vf:FindFirstChild("RagDoll")) then return false end
	if os.clock() - S.lastFreeDash < CFG.freeDashGap then return false end
	S.lastFreeDash = os.clock()
	-- Hold reads the direction from SHC[LastCkType or "CK"] before it yields (2196.lua:38).
	local oldType, oldCk = shc:GetAttribute("LastCkType"), shc:GetAttribute("CK")
	shc:SetAttribute("LastCkType", "CK")
	shc:SetAttribute("CK", dir or "W")
	local ok, err = pcall(DashSkill.Hold, LP)
	shc:SetAttribute("CK", oldCk)
	shc:SetAttribute("LastCkType", oldType)
	if not ok then Log.warn("free dash failed: " .. tostring(err)) return false end
	S.freeDashes += 1
	return true
end

if DashHandler and type(DashHandler.Perform) == "function" then
	S.dashOrig = DashHandler.Perform
	local orig = S.dashOrig
	S.dashWrapper = function(dir, ...)
		local done = orig(dir, ...)
		if done or not CFG.freeDash or not S.alive then return done end
		return freeDash(dir)
	end
	DashHandler.Perform = S.dashWrapper
end

--------------------------------------------------------------------------
-- speed: a WalkSpeed override the game's own Humanoid_handler applies
--------------------------------------------------------------------------
local function applySpeed()
	local vf = valuesFolder()
	if not CFG.speedOn then
		if S.speedValue then pcall(function() S.speedValue:Destroy() end) S.speedValue = nil end
		return
	end
	if not vf then return end
	if not S.speedValue or S.speedValue.Parent ~= vf then
		if S.speedValue then pcall(function() S.speedValue:Destroy() end) end
		local v = Instance.new("NumberValue")
		v.Name = "WalkSpeed"
		v:SetAttribute("Priority", 1e6)
		v.Parent = vf
		S.speedValue = v
	end
	S.speedValue.Value = CFG.speedValue
end

--------------------------------------------------------------------------
-- instant prompts / walk on water / no drowning
--------------------------------------------------------------------------
local function applyPrompt(prompt)
	if not CFG.instantPrompts or not prompt:IsA("ProximityPrompt") then return end
	if S.promptOrig[prompt] == nil then S.promptOrig[prompt] = prompt.HoldDuration end
	prompt.HoldDuration = 0
end
local function restorePrompts()
	for prompt, dur in next, S.promptOrig do pcall(function() prompt.HoldDuration = dur end) end
	table.clear(S.promptOrig)
end
connect(ProximityPromptService.PromptShown, function(prompt) pcall(applyPrompt, prompt) end)

local function applyWater()
	if CFG.walkOnWater then
		for _, part in ipairs(CollectionService:GetTagged("SwimParts")) do
			if part:IsA("BasePart") and S.waterOrig[part] == nil then
				S.waterOrig[part] = part.CanCollide
				part.CanCollide = true
			end
		end
	else
		for part, was in next, S.waterOrig do pcall(function() part.CanCollide = was end) end
		table.clear(S.waterOrig)
	end
end

-- The Swimming LocalScript's local state table (2560.lua:171).
local function findSwimState()
	if not getgc then return nil end
	for _, t in ipairs(getgc(true)) do
		if type(t) == "table" and type(rawget(t, "Breath")) == "number"
			and type(rawget(t, "Drowning")) == "boolean" then
			return t
		end
	end
end

--------------------------------------------------------------------------
-- move while stunned (session only)
--------------------------------------------------------------------------
connect(RunService.Stepped, function()
	if not S.stunMove then return end
	local char = LP.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end
	if isStunned(valuesFolder()) and hum.WalkSpeed < 1 then
		hum.WalkSpeed = CFG.speedOn and CFG.speedValue or 16
	end
end)

--------------------------------------------------------------------------
-- auto block (session only): enemy swing effect near us -> real F press
--------------------------------------------------------------------------
-- VirtualInputManager needs Plugin capability at GetService time on some
-- threads (build .2 died on it at load), so resolve it lazily and guarded.
local function sendF(down)
	pcall(function()
		local vim = game:GetService("VirtualInputManager")
		vim:SendKeyEvent(down, Enum.KeyCode.F, false, game)
	end)
end

local function releaseF()
	if not S.fHeld then return end
	S.fHeld = false
	sendF(false)
end

local function pressBlock()
	S.blockUntil = os.clock() + CFG.blockHold
	if S.fHeld then return end
	if UserInputService:GetFocusedTextBox() then return end
	S.fHeld = true
	S.blocks += 1
	sendF(true)
	task.spawn(function()
		while S.alive and S.fHeld and os.clock() < S.blockUntil do task.wait() end
		releaseF()
	end)
end

local function onEffect(name, attacker)
	if not S.alive or type(name) ~= "string" or string.sub(name, -7) ~= "_Swings" then return end
	if typeof(attacker) ~= "Instance" or not attacker:IsA("Model") or attacker == LP.Character then return end
	S.swingsSeen += 1
	if not S.autoBlock then return end
	local root = myRoot()
	local aRoot = attacker:FindFirstChild("HumanoidRootPart")
	if not root or not aRoot then return end
	local offset = root.Position - aRoot.Position
	if offset.Magnitude > CFG.blockRange then return end
	if offset.Magnitude > 3 and aRoot.CFrame.LookVector:Dot(offset.Unit) < 0.2 then return end
	if isStunned(valuesFolder()) then return end
	pressBlock()
end

-- Connect the RemoteEvent EffectsEvent wraps (0813.lua:9 -> 1973.lua:51-62)
-- directly. Calling a game-module function on this loading thread cost it
-- access to the hub's own frames (build .4 died in moduleShell on it).
do
	local remote = find(ReplicatedStorage, "Communication/ServerAndClient/Effects/EffectsEvent/Event")
	if remote and remote:IsA("RemoteEvent") then S.effectConn = connect(remote.OnClientEvent, onEffect) end
end
-- Second cue: attack animations on nearby mobs. The server plays NPC
-- animations and they replicate to every client, so AnimationPlayed fires for
-- an NPC swing whether or not an effect is sent. Names are logged once each
-- so the attack filter can be tuned from real fights.
local ATTACK_PATTERNS = { "swing", "attack", "slash", "punch", "strike", "combo", "m1", "hit", "kick", "slam", "stab", "bite", "claw" }
S.animConns, S.animNames, S.animSeen = {}, {}, 0
local function isAttackAnim(name)
	local lower = string.lower(name)
	if string.find(lower, "idle") or string.find(lower, "walk") or string.find(lower, "run") or string.find(lower, "stun") then
		return false
	end
	for _, pat in ipairs(ATTACK_PATTERNS) do
		if string.find(lower, pat, 1, true) then return true end
	end
	return false
end
local function onAnim(model, track)
	if not S.alive then return end
	local anim = track and track.Animation
	local name = anim and (anim.Name ~= "Animation" and anim.Name or anim.AnimationId) or "?"
	if not S.animNames[name] then
		S.animNames[name] = true
		Log.info(string.format("anim seen %s on %s attack=%s", tostring(name), model.Name, tostring(isAttackAnim(name))))
	end
	if not isAttackAnim(name) then return end
	S.animSeen += 1
	if not S.autoBlock then return end
	local root = myRoot()
	local aRoot = model:FindFirstChild("HumanoidRootPart")
	if not root or not aRoot then return end
	local offset = root.Position - aRoot.Position
	if offset.Magnitude > CFG.blockRange then return end
	if offset.Magnitude > 3 and aRoot.CFrame.LookVector:Dot(offset.Unit) < 0.2 then return end
	if isStunned(valuesFolder()) then return end
	pressBlock()
end
local function watchAnims()
	local root = myRoot()
	if not root then return end
	local reach = CFG.blockRange * 3
	for _, model in ipairs(CollectionService:GetTagged("Humanoids")) do
		if model:IsA("Model") and model ~= LP.Character and not S.animConns[model] and model:IsDescendantOf(workspace) then
			local mRoot = model:FindFirstChild("HumanoidRootPart")
			local hum = model:FindFirstChildOfClass("Humanoid")
			local animator = hum and hum:FindFirstChildOfClass("Animator")
			if mRoot and animator and (mRoot.Position - root.Position).Magnitude <= reach then
				S.animConns[model] = animator.AnimationPlayed:Connect(function(track) onAnim(model, track) end)
			end
		end
	end
	for model, c in next, S.animConns do
		local mRoot = model.Parent and model:FindFirstChild("HumanoidRootPart")
		if not mRoot or (mRoot.Position - root.Position).Magnitude > reach * 1.5 then
			pcall(function() c:Disconnect() end)
			S.animConns[model] = nil
		end
	end
end

do
	local ce = find(ReplicatedStorage, "Communication/CnC/ClientEffects")
	if ce and ce:IsA("BindableEvent") then connect(ce.Event, onEffect) end
end

--------------------------------------------------------------------------
-- low-HP kill (session only, experimental): only mobs this client owns
--------------------------------------------------------------------------
local function tickLowKill()
	local root = myRoot()
	if not root or not isnetworkowner then return end
	for _, model in ipairs(CollectionService:GetTagged("Humanoids")) do
		if model:IsA("Model") and model ~= LP.Character and model:GetAttribute("IsMob") == true
			and model:IsDescendantOf(workspace) and not Players:GetPlayerFromCharacter(model) then
			local hum = model:FindFirstChildOfClass("Humanoid")
			local mRoot = model:FindFirstChild("HumanoidRootPart")
			if hum and mRoot and hum.Health > 0 and hum.MaxHealth > 0
				and (mRoot.Position - root.Position).Magnitude <= CFG.killRange then
				local owned = false
				pcall(function() owned = isnetworkowner(mRoot) end)
				if owned then S.ownedSeen += 1 else S.unownedSeen += 1 end
				if owned and hum.Health / hum.MaxHealth <= CFG.killThreshold then
					pcall(hum.ChangeState, hum, Enum.HumanoidStateType.Dead)
					pcall(function()
						mRoot.CFrame = CFrame.new(mRoot.Position.X, workspace.FallenPartsDestroyHeight - 50, mRoot.Position.Z)
					end)
					S.kills += 1
					Log.info(string.format("lowkill %s hp=%d/%d", model.Name, hum.Health, hum.MaxHealth))
				end
			end
		end
	end
end

--------------------------------------------------------------------------
-- slow tick: speed, drowning, water, market, low kill, targets
--------------------------------------------------------------------------
local slowAcc, marketAcc, targetAcc, ownLogAcc = 0, 0, 0, 0
connect(RunService.Heartbeat, function(dt)
	if not S.alive then return end
	if CFG.noDrown then
		if S.swimChar ~= LP.Character then S.swimState, S.swimChar = nil, LP.Character end
		if S.swimState then
			S.swimState.Breath = 1
			S.swimState.Drowning = false
		end
	end
	if S.lowKill then pcall(tickLowKill) end
	slowAcc += dt
	marketAcc += dt
	targetAcc += dt
	ownLogAcc += dt
	if slowAcc >= 1 then
		slowAcc = 0
		if CFG.speedOn then pcall(applySpeed) end
		if CFG.walkOnWater then pcall(applyWater) end
		if CFG.noDrown and not S.swimState and LP.Character then
			local ok, t = pcall(findSwimState)
			if ok then S.swimState = t end
		end
	end
	if slowAcc == 0 and S.autoBlock then pcall(watchAnims) end
	if marketAcc >= 2 then
		marketAcc = 0
		local ok, err = pcall(tickMarket)
		if not ok and S.errors < 3 then S.errors += 1 Log.warn("market: " .. tostring(err)) end
	end
	if targetAcc >= 15 then
		targetAcc = 0
		pcall(rebuildTargets)
	end
	if S.lowKill and ownLogAcc >= 30 then
		ownLogAcc = 0
		Log.info(string.format("lowkill ownership owned=%d unowned=%d kills=%d", S.ownedSeen, S.unownedSeen, S.kills))
	end
end)

--------------------------------------------------------------------------
-- UI
--------------------------------------------------------------------------
local Kit = HOST.ui
assert(Kit.SHELL_CONTRACT == "1", "R3ST shell contract mismatch")

local teardown

local Shell = Kit.moduleShell({
	id = "project-slayers-2",
	title = "Project Slayers 2",
	version = BUILD_VERSION,
	subtitle = "Black Market, quest ESP, spawns, free dash and auto block",
	gameId = EXPECTED_GAME,
	placeId = EXPECTED_PLACE,
	standaloneSize = Vector2.new(780, 600),
	keep = { layer, chamFolder },
	cfg = CFG,
	save = saveConfig,
	tabs = { "Spawns", "Quests", "ESP", "World", "Movement", "Combat" },
	onUnload = function() teardown() end,
	onReload = function()
		task.defer(function()
			teardown()
			local chunk, err = loadfile("ps2_hub.lua")
			if chunk then chunk() else Log.warn("reload failed: " .. tostring(err)) end
		end)
	end,
})
local W = Shell.W

------------------------------ Spawns ------------------------------------
local spawns = Shell.page("Spawns")
W.section(spawns, "Black Market")
W.toggle(spawns, { label = "Black Market ESP", desc = "Predicted spot from the game's own seed, LIVE once the NPC is loaded.", key = "marketEsp" })
W.toggle(spawns, { label = "Show next spot", desc = "Where it will appear next cycle, so you can wait there.", key = "marketNext" })
W.statusRow(spawns, function()
	local m = S.market
	if not m then return "Black Market data MISSING" end
	return string.format("%s  ·  spot #%d  ·  %s %s", m.active and "OPEN" or "closed", m.index,
		m.active and "closes in" or "opens in", fmtTime(m.edgeIn))
end)
W.statusRow(spawns, function()
	local m = S.market
	if not m or #m.stock == 0 then return "stock: -" end
	return "stock: " .. table.concat(m.stock, ", ")
end)
W.statusRow(spawns, function()
	local n = S.marketNextInfo
	if not n or #n.stock == 0 then return "next stock: -" end
	return string.format("next (#%d): %s", n.index, table.concat(n.stock, ", "))
end)
W.button(spawns, "Teleport to Black Market", "Live NPC if loaded, otherwise the predicted spot.", function()
	local m = S.market
	teleport(S.marketLive or (m and m.pos))
end)
W.section(spawns, "Spawn alerts")
W.toggle(spawns, { label = "Black Market notification", desc = "One popup when the Black Market opens.", key = "notify" })
W.toggle(spawns, { label = "Event ESP", key = "eventEsp" })
W.toggle(spawns, { label = "Chest + loot ESP", key = "chestEsp" })
W.statusRow(spawns, function()
	return #S.eventLog > 0 and table.concat(S.eventLog, "\n") or "no spawns seen yet"
end)
W.section(spawns, "Auto grab")
W.toggle(spawns, {
	label = "Auto grab", desc = "Session only. Teleports to a new chest, loot or key and presses its prompt.",
	get = function() return S.autoGrab end,
	set = function(v) S.autoGrab = v and true or false end,
})
W.slider(spawns, {
	label = "Grab range", key = "grabRange", min = 100, max = 10000, step = 100,
	fmt = function(v) return string.format("%d studs", v) end,
})
W.toggle(spawns, { label = "Teleport back after", key = "grabReturn" })
W.statusRow(spawns, function() return string.format("grabs %d", S.grabs) end)
W.section(spawns, "Timers")
W.statusRow(spawns, function()
	if not TimedEvents then return "timers MISSING" end
	local now = workspace:GetServerTimeNow()
	local rows = {}
	for key, ev in next, TimedEvents do
		if type(ev) == "table" and type(ev.Every) == "number" and ev.Every > 0 then
			rows[#rows + 1] = string.format("%s in %s", tostring(ev.Title or key), fmtTime(ev.Every - (now % ev.Every)))
		end
	end
	table.sort(rows)
	return table.concat(rows, "  ·  ")
end)

------------------------------ Quests ------------------------------------
local quests = Shell.page("Quests")
W.section(quests, "Pickup quests")
W.toggle(quests, { label = "Quest item ESP", desc = "Every pickup spot from the quest data, live ones in green.", key = "pickupEsp" })
W.slider(quests, {
	label = "Draw distance", key = "pickupMaxStuds", min = 250, max = 10000, step = 250,
	fmt = function(v) return string.format("%d studs", v) end,
})
W.statusRow(quests, function()
	return string.format("%d known spots  ·  %d spawned right now", #S.pickups, S.liveCount)
end)
W.note(quests, "Yellow = a spot the quest can use (Lost Pages, gemstone, penny, coins, blade, stamp, jewelry box, scrolls, sea crystals). Green = spawned for your active quest. The server checks the 25-stud pick-up range.")
W.section(quests, "World")
W.toggle(quests, { label = "Muzan lair marker", key = "muzanMarker" })

------------------------------ ESP ---------------------------------------
local esp = Shell.page("ESP")
W.section(esp, "Humanoids")
W.toggle(esp, { label = "Mob chams", desc = "Red on mobs, magenta on bosses (Akazo, Gyutai, Datai, Reaper...).", key = "mobEsp" })
W.toggle(esp, { label = "Bosses only", key = "bossOnly" })
W.toggle(esp, { label = "Player chams", desc = "Blue on other players.", key = "playerEsp" })
W.slider(esp, {
	label = "Draw distance", key = "espMaxStuds", min = 50, max = 5000, step = 50,
	fmt = function(v) return string.format("%d studs", v) end,
})
W.section(esp, "Places")
W.toggle(esp, { label = "Shrine ESP", key = "shrineEsp" })
W.toggle(esp, { label = "Spawn crystal ESP", key = "crystalEsp" })
W.section(esp, "HUD")
W.toggle(esp, { label = "Cooldown + stamina HUD", desc = "Seconds left on every skill, stamina, Black Market timer.", key = "hud" })

------------------------------ World -------------------------------------
local world = Shell.page("World")
W.section(world, "Teleport")
W.statusRow(world, function()
	local t = S.teleTargets[S.teleIndex]
	if not t then return "no targets loaded yet (shrines, crystals, NPCs load as you explore)" end
	local root = myRoot()
	return string.format("%d/%d  %s  %dm", S.teleIndex, #S.teleTargets, t.name,
		root and (t.pos - root.Position).Magnitude or 0)
end)
W.button(world, "Previous", nil, function()
	if #S.teleTargets == 0 then return end
	S.teleIndex = S.teleIndex <= 1 and #S.teleTargets or S.teleIndex - 1
end)
W.button(world, "Next", nil, function()
	if #S.teleTargets == 0 then return end
	S.teleIndex = S.teleIndex >= #S.teleTargets and 1 or S.teleIndex + 1
end)
W.button(world, "Teleport", "Stand at a spawn crystal and press its prompt to set your spawn.", function()
	local t = S.teleTargets[S.teleIndex]
	if t then teleport(t.pos) end
end)
W.button(world, "Refresh list", nil, function() pcall(rebuildTargets) end)
W.section(world, "Utility")
W.toggle(world, {
	label = "Instant prompts", desc = "Hold-to-interact prompts fire on press.", key = "instantPrompts",
	set = function(v) if not v then restorePrompts() end end,
})
W.toggle(world, {
	label = "No drowning", desc = "Keeps breath full underwater.", key = "noDrown",
	set = function(v) if not v then S.swimState = nil end end,
})
W.statusRow(world, function()
	if not CFG.noDrown then return "drowning: game default" end
	return S.swimState and "drowning: breath pinned" or "drowning: looking for swim state"
end)
W.toggle(world, { label = "Walk on water", key = "walkOnWater", set = function() applyWater() end })

------------------------------ Movement ----------------------------------
local move = Shell.page("Movement")
W.section(move, "Dash")
W.toggle(move, { label = "No dash cooldown", desc = "Dash on Q even when the game says it is on cooldown.", key = "freeDash" })
W.slider(move, {
	label = "Minimum gap", key = "freeDashGap", min = 0.1, max = 1.5, step = 0.05,
	fmt = function(v) return string.format("%.2fs", v) end,
})
W.statusRow(move, function()
	return string.format("free dashes %d  ·  %s", S.freeDashes, DashSkill and "dash module ok" or "dash module MISSING")
end)
W.note(move, "Extra dashes move you for real but give no block-escape iframe, and other players see no dash effect.")
W.section(move, "Speed")
W.toggle(move, { label = "Speed", key = "speedOn", set = function() applySpeed() end })
W.slider(move, {
	label = "Walk speed", key = "speedValue", min = 16, max = 60, step = 1,
	fmt = function(v) return string.format("%d", v) end,
	set = function() if CFG.speedOn then applySpeed() end end,
})
W.section(move, "Stun")
W.toggle(move, {
	label = "Move while stunned", desc = "Session only. Other players can see you walk out of a stun.",
	get = function() return S.stunMove end,
	set = function(v) S.stunMove = v and true or false end,
})

------------------------------ Combat ------------------------------------
local combat = Shell.page("Combat")
W.section(combat, "Auto perfect block")
W.toggle(combat, {
	label = "Auto block", desc = "Session only. Presses F when a nearby enemy swings at you.",
	get = function() return S.autoBlock end,
	set = function(v) S.autoBlock = v and true or false if not S.autoBlock then releaseF() end end,
})
W.slider(combat, {
	label = "Trigger range", key = "blockRange", min = 6, max = 30, step = 1,
	fmt = function(v) return string.format("%d studs", v) end,
})
W.slider(combat, {
	label = "Hold time", key = "blockHold", min = 0.15, max = 1, step = 0.05,
	fmt = function(v) return string.format("%.2fs", v) end,
})
W.statusRow(combat, function()
	return string.format("effect swings %d  ·  attack anims %d  ·  watching %d  ·  blocks %d  ·  %s", S.swingsSeen, S.animSeen,
		(function() local n = 0 for _ in next, S.animConns do n += 1 end return n end)(), S.blocks,
		S.effectConn and "listening" or "effect listener MISSING")
end)
W.note(combat, "Perfect needs the block to start within 0.25s of an NPC hit (0.1s vs players) and no hit taken in the last second. Block key is assumed to be F.")
W.section(combat, "Low-HP kill (experimental)")
W.toggle(combat, {
	label = "Kill owned mobs under threshold", desc = "Session only. Works only on mobs your client physically owns.",
	get = function() return S.lowKill end,
	set = function(v) S.lowKill = v and true or false end,
})
W.slider(combat, {
	label = "HP threshold", key = "killThreshold", min = 0.05, max = 0.9, step = 0.05,
	fmt = function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end,
})
W.slider(combat, {
	label = "Range", key = "killRange", min = 10, max = 150, step = 5,
	fmt = function(v) return string.format("%d studs", v) end,
})
W.statusRow(combat, function()
	return string.format("owned checks %d  ·  not owned %d  ·  kills %d", S.ownedSeen, S.unownedSeen, S.kills)
end)

Shell.ready()

--------------------------------------------------------------------------
-- lifecycle
--------------------------------------------------------------------------
function teardown()
	if not S.alive then return end
	S.alive = false
	releaseF()
	if DashHandler and S.dashOrig and DashHandler.Perform == S.dashWrapper then
		DashHandler.Perform = S.dashOrig
	end
	if S.speedValue then pcall(function() S.speedValue:Destroy() end) end
	restorePrompts()
	for part, was in next, S.waterOrig do pcall(function() part.CanCollide = was end) end
	if S.effectConn then pcall(function() S.effectConn:Disconnect() end) end
	for _, c in next, S.animConns do pcall(function() c:Disconnect() end) end
	for _, c in ipairs(S.conns) do pcall(function() c:Disconnect() end) end
	pcall(function() layer:Destroy() end)
	pcall(function() chamFolder:Destroy() end)
	pcall(function() Shell.destroy() end)
	GENV[GKEY] = nil
	Log.info("unloaded " .. BUILD_VERSION)
end

Shell.hideBind()
connect(UserInputService.InputBegan, function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.K then teardown() end
end)

GENV[GKEY] = { destroy = teardown, build = BUILD_VERSION, state = S, cfg = CFG }

local ok, err = xpcall(function()
	local n = collectStaticPickups()
	local mp = MuzanSettings and MuzanSettings.muzanPositions
	if mp and typeof(mp.IsNotDemon) == "CFrame" then S.muzan = mp.IsNotDemon.Position end
	if CFG.speedOn then applySpeed() end
	if CFG.walkOnWater then applyWater() end
	pcall(rebuildTargets)
	Log.info(string.format("boot %s pickups=%d market=%s targets=%d dash=%s effects=%s",
		BUILD_VERSION, n, tostring(MarketCfg ~= nil and TimedVendor ~= nil),
		#S.teleTargets, tostring(DashSkill ~= nil), tostring(S.effectConn ~= nil)))
end, debug.traceback)
if not ok then Log.warn("boot error: " .. tostring(err)) end
