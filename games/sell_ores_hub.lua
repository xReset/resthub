--------------------------------------------------------------------------
-- Sell Ores Hub v2026-09-05.2 -- Automation
--
-- Rung 6 (fires remotes / prompts). Server sees the exact packets its own
-- clients send: RollerPurchaseEvent, BaseBuildPurchaseFloor,
-- BaseBuildPurchaseTunnel, BaseBuildTunnelAction, FuserAction, the three base
-- upgrade RemoteFunctions and the reward remotes, plus prompt fires the game's
-- own PromptTriggered handlers answer. Every automation toggle boots OFF every
-- session (potassium-dev S0.2b: rung 6). Delays persist; toggles do not.
--
-- Dump: 2026-09-05T13-36-46Z, PlaceId 122572082932179, universe 10336278580.
-- Script ids below are THIS dump's; they shifted from the 2026-09-03 archive
-- (old 0129 = RollerClient, now 0117), so cite by path when re-checking.
-- Proof:
--   roller purchase        0117.lua:1188 RollerPurchaseEvent:FireServer(
--                          pedestalName, finalOreName) [RollerClient]
--   roller prompt attrs    0117.lua:4452-4454 InteractionType=
--                          "RollerOrePurchase", PedestalName, OreName, gated on
--                          the display's PurchasePromptReady (0117.lua:1160)
--   lever                  0117.lua:554/933 Roller.Lever prompt
--   ore economics          0206.lua OreMetadata: GetBaseIncome(name, oreLevel,
--                          highestDiscovered) scales 1.1224620^(level-1)
--                          (0206.lua:691-730), GetGrowTimeSeconds (734),
--                          GetSeedCost (777), Mutations multiplier table (28+),
--                          RarityRank (15), GetHighestDiscoveredOreName (628)
--   discovered ores        0012.lua:967 RequestUnlockedOres:InvokeServer() ->
--                          { [oreName] = true } (applyUnlockedOres 0012.lua:940)
--   equipped per tunnel    0041.lua:164/418 key "Floor%d_Tunnel%s" on the
--                          LocalPlayer, suffixes _Unlocked/_OreType/_OreLevel/
--                          _OreMutation (attributes_catalog.txt @Floor10_*)
--   equip best / gems      0036.lua:136 BaseBuildTunnelAction:InvokeServer(base,
--                          1, "Tunnel1", "EquipBest"); :195 "ApplyBestGrowthGems"
--                          gated on @GrowthGemInventoryCount > 0
--   crate prompts          0052.lua:1166-1208 PickUpOresPrompt / SellOresPrompt
--                          [CrateClient]; carried stack 0052.lua:1641-1642
--                          CarriedOreCrateStack + @CarriedCrateType
--   crate remote fallback  0052.lua:3301 BaseCrateAction:InvokeServer(base,
--                          "CollectDroneOres", ids)
--   furnace                interactives.txt Furnace.PlaceCratesPromptPart.
--                          PlaceCratesPrompt / PurchasePromptPart.
--                          PurchaseFurnacePrompt / MetalCratePlacementPart.
--                          PickUpCratesPrompt; @FurnacePurchased on the Furnace
--                          model (0063.lua:260); rate upgrade 0062.lua:527
--                          BaseCrateAction:InvokeServer(base,"UpgradeFurnace")
--   fuser                  interactives.txt Fuser.PurchasePromptPart.
--                          PurchaseFuserPrompt ($100B), FuserModel.Nodes.Node_NN
--                          .OrePlaceholder.ProximityPrompt ("Place Ore"),
--                          FuserModel.CentralHub.MegaOrePlaceholder.
--                          ClaimMegaOrePrompt; 0065.lua:261-271 FuserAction:
--                          InvokeServer(base,"StartFusion") only while
--                          @FuserPhase == "Loading" (Fusing at 0065.lua:422)
--   floors                 0038.lua:29 InvokeServer("GetFloorPrice", floor);
--                          :337 InvokeServer(baseName, floor) [BaseBuildFloorClient]
--   tunnels                0039.lua:229 BaseBuildPurchaseTunnel:InvokeServer(
--                          base.Name, floor, tunnelName); floor/tunnel resolved
--                          from the PurchaseModel at 0039.lua:92-110
--   upgrades               0042.lua DrillSpeed, 0043.lua DrillYield,
--                          0044.lua OreRegenSpeed, RollerUpgradePedestal /
--                          RollerUpgradeOreLuck (remotes.txt)
--   daily reward           0007.lua:317-318 ClaimDailyReward:FireServer() when
--                          i == state.currentDay and now >= nextAvailableAt;
--                          state via GetDailyRewardsState:InvokeServer() (:223)
--   playtime rewards       0013.lua:515-521 PlaytimeRewardsClaim:FireServer(i)
--                          when rewards[i].claimed ~= true and elapsed >=
--                          unlockAt; PlaytimeRewardsGetState is a RemoteFunction
--   lucky spin             0072.lua:352 GetLuckySpinState:InvokeServer() ->
--                          { spins, remaining }; :686 RequestLuckySpin ->
--                          { ok, spinId, slice }; :697 CompleteLuckySpin(spinId)
--   money                  attributes_catalog @Money on Player
--   robux popups           0117.lua:221/315-324 DeveloperProductPrompt
--                          .OnClientEvent -> MarketplaceService:
--                          PromptProductPurchase. Server-driven and the only
--                          listener in the dump, so it is the single choke
--                          point for every popup our traffic can provoke.
-- Anticheat: ENFORCEMENT 0, REPORTING 0, CLIENT INSPECTION 0, LOG MONITORING 0
-- (anticheat_deep.txt). Zero is not proof of safety; no print/warn, file log only.
-- Re-inject safe: self-teardown on load; K = unload/panic.
--------------------------------------------------------------------------

-- Stamp uses one name segment ("sellores-"), which is what tools/ship.py's
-- header check strips before comparing it to the title line above.
local BUILD_VERSION = "sellores-2026-09-05.2"
local EXPECTED_PLACE = 122572082932179
local EXPECTED_GAME = 10336278580
local GKEY = "__SELL_ORES_HUB"
local CONFIG_PATH = "configs/sell_ores_hub.json"

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")
local RunService = game:GetService("RunService")
local VirtualUser = game:GetService("VirtualUser")

local LP = Players.LocalPlayer
local G = (getgenv and getgenv()) or _G
if type(G) ~= "table" then G = _G end

if game.GameId ~= EXPECTED_GAME and game.PlaceId ~= EXPECTED_PLACE then
	return
end

if type(G[GKEY]) == "table" and type(G[GKEY].destroy) == "function" then
	local ok = pcall(G[GKEY].destroy)
	if not ok then return end
end

local function makeLogger()
	local ok, factory = pcall(function() return loadfile("log.lua")() end)
	if ok and type(factory) == "function" then
		local ok2, logger = pcall(factory, "sell_ores_hub")
		if ok2 and logger then return logger end
	end
	local rows = {}
	local function add(level, msg)
		rows[#rows + 1] = string.format("[%s] %s", level, tostring(msg))
		pcall(function()
			if type(isfolder) == "function" and not isfolder("logs") and type(makefolder) == "function" then
				makefolder("logs")
			end
			writefile("logs/sell_ores_hub.log", table.concat(rows, "\n") .. "\n")
		end)
	end
	return {
		session = function(msg) rows = {}; add("session", msg) end,
		info = function(msg) add("info", msg) end,
		warn = function(msg) add("warn", msg) end,
		err = function(msg, err) add("err", tostring(msg) .. " " .. tostring(err)) end,
	}
end

local Log = makeLogger()
Log.session(string.format("armed build=%s place=%s universe=%s all-automation=OFF",
	BUILD_VERSION, tostring(game.PlaceId), tostring(game.GameId)))

-- ---------------------------------------------------------------- config
-- Toggles are rung 6 and never persist (S0.2b). Only pacing values persist.
local CFG = {
	rollDelay = 1.2,
	upgradeDelay = 3,
	floorDelay = 5,
	crateDelay = 2,
	fuserDelay = 3,
	rewardDelay = 30,
	minRarity = 1,
	panelX = -310,
	panelY = -240,
}

local LIMITS = {
	rollDelay = { 0.5, 10 },
	upgradeDelay = { 1, 30 },
	floorDelay = { 2, 60 },
	crateDelay = { 1, 30 },
	fuserDelay = { 1, 30 },
	rewardDelay = { 10, 300 },
	minRarity = { 1, 13 },
	panelX = { -2000, 2000 },
	panelY = { -2000, 2000 },
}

pcall(function()
	if not isfile(CONFIG_PATH) then return end
	local saved = HttpService:JSONDecode(readfile(CONFIG_PATH))
	if type(saved) ~= "table" then return end
	for key, default in next, CFG do
		local value = saved[key]
		if type(value) == type(default) then
			local lim = LIMITS[key]
			CFG[key] = lim and math.clamp(value, lim[1], lim[2]) or value
		end
	end
end)

local savePending = false
local function saveConfig()
	savePending = false
	local ok, err = pcall(function()
		if type(isfolder) == "function" and not isfolder("configs") and type(makefolder) == "function" then
			makefolder("configs")
		end
		writefile(CONFIG_PATH, HttpService:JSONEncode(CFG))
	end)
	if not ok then Log.err("config save", err) end
	return ok
end

local function queueSave()
	if savePending then return end
	savePending = true
	task.delay(0.5, saveConfig)
end

-- ---------------------------------------------------------------- state
local S = {
	alive = true,
	build = BUILD_VERSION,
	autoRoll = false,
	smartBuy = false,
	autoCrate = false,
	autoFurnace = false,
	autoFuser = false,
	autoUpgrade = false,
	autoFloor = false,
	autoTunnel = false,
	autoEquip = false,
	autoGems = false,
	autoRewards = false,
	antiAfk = false,
	-- Safety, not automation: it only suppresses a popup our own traffic
	-- provokes, and it is undone on unload. Boots ON.
	blockPrompts = true,
	blocked = 0,
	status = "Ready",
	rolls = 0,
	buys = 0,
	skips = 0,
	crates = 0,
	sells = 0,
	placed = 0,
	smelted = 0,
	upgrades = 0,
	floors = 0,
	tunnels = 0,
	equips = 0,
	fusions = 0,
	rewards = 0,
	spins = 0,
	conns = {},
	screen = nil,
	panel = nil,
	host = nil,
}

local function setStatus(msg)
	S.status = msg
end

-- ---------------------------------------------------------------- remotes
local Remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
local RollerPurchaseEvent = ReplicatedStorage:WaitForChild("RollerPurchaseEvent", 30)

local function remote(name)
	return Remotes and Remotes:FindFirstChild(name) or nil
end

-- ---------------------------------------------------------------- ore metadata
-- The game's own OreMetadata (0206.lua). Use its API, not the raw rows: income
-- scales with the tunnel's ore level and some ores reference the highest ore
-- you have discovered.
local OreMeta
local function meta()
	if OreMeta == nil then
		local ok, mod = pcall(function() return require(ReplicatedStorage:WaitForChild("OreMetadata", 10)) end)
		OreMeta = (ok and type(mod) == "table" and mod) or false
	end
	return OreMeta or nil
end

local Discovered = { at = 0, set = nil, highest = "Stone Ore" }

-- RequestUnlockedOres -> { [oreName] = true } (0012.lua:940-971). Cached; the
-- set only grows, and a stale entry costs one suboptimal comparison, not a bug.
local function discovered()
	local M = meta()
	if not M then return nil, "Stone Ore" end
	if Discovered.set and os.clock() - Discovered.at < 60 then
		return Discovered.set, Discovered.highest
	end
	local r = remote("RequestUnlockedOres")
	if r then
		local ok, res = pcall(function() return r:InvokeServer() end)
		if ok and type(res) == "table" then
			Discovered.set = res
			local ok2, name = pcall(function() return M.GetHighestDiscoveredOreName(res, res) end)
			Discovered.highest = (ok2 and type(name) == "string" and name) or "Stone Ore"
		end
	end
	Discovered.at = os.clock()
	return Discovered.set, Discovered.highest
end

local function rarityRank(name)
	local M = meta()
	if not M then return 0 end
	local ore = M.ByName and M.ByName[name]
	if not ore then
		local ok, res = pcall(function() return M.GetOre(name) end)
		ore = ok and res or nil
	end
	if type(ore) ~= "table" then return 0 end
	return (M.RarityRank and M.RarityRank[ore.rarity]) or 0
end

local function rarityName(index)
	local M = meta()
	local list = M and M.Rarities
	if type(list) == "table" and list[index] then return list[index] end
	return "Common"
end

-- Income per second for one ore at one level, mutation included.
-- GetBaseIncome / GetGrowTimeSeconds own the level curve and the
-- HighestDiscovered reference (0206.lua:691, :734).
local function incomePerSec(name, level, mutation)
	local M = meta()
	if not M or type(name) ~= "string" or name == "" then return nil end
	local _, highest = discovered()
	local okI, income = pcall(function() return M.GetBaseIncome(name, level or 1, highest) end)
	local okG, grow = pcall(function() return M.GetGrowTimeSeconds(name, highest) end)
	income, grow = okI and tonumber(income) or nil, okG and tonumber(grow) or nil
	if not income or not grow or grow <= 0 or income <= 0 then return nil end
	local mult = 1
	if type(mutation) == "string" and mutation ~= "" then
		local okM, m = pcall(function() return M.GetMutationMultiplier(mutation) end)
		mult = (okM and tonumber(m)) or 1
	end
	return (income * mult) / grow
end

local function seedCost(name)
	local M = meta()
	if not M then return math.huge end
	local ok, cost = pcall(function() return M.GetSeedCost(name) end)
	return (ok and tonumber(cost)) or math.huge
end

-- ---------------------------------------------------------------- world
local function getMoney()
	return tonumber(LP:GetAttribute("Money")) or 0
end

local function getBase()
	local attr = LP:GetAttribute("AssignedBaseName")
	if type(attr) ~= "string" or attr == "" then return nil end
	local Bases = workspace:FindFirstChild("Bases")
	if not Bases then return nil end
	local base = Bases:FindFirstChild(attr)
	return (base and base:IsA("Model")) and base or nil
end

local function maxFloor()
	return math.max(1, math.floor(tonumber(LP:GetAttribute("MaxFloorUnlocked")) or 1))
end

-- Tunnel state lives on the LocalPlayer under "Floor%d_Tunnel%s" (0041.lua:164).
local function tunnelKey(floor, tunnelName)
	return string.format("Floor%d_Tunnel%s", floor, tunnelName)
end

local function tunnelModels(base, floor)
	local out = {}
	local floors = base:FindFirstChild("Floors")
	local model = floors and floors:FindFirstChild("Floor" .. floor)
	if not model then return out end
	for _, child in ipairs(model:GetChildren()) do
		if child:IsA("Model") and child.Name:match("^Tunnel") then
			out[#out + 1] = child
		end
	end
	return out
end

-- Weakest income/sec among the tunnels that currently hold an ore. A rolled ore
-- that beats this is worth buying, because EquipBest will place it for us.
local function weakestEquipped(base)
	local worst, worstName = nil, nil
	for floor = 1, maxFloor() do
		for _, tunnel in ipairs(tunnelModels(base, floor)) do
			local key = tunnelKey(floor, tunnel.Name)
			if LP:GetAttribute(key .. "_Unlocked") == true then
				local ore = LP:GetAttribute(key .. "_OreType")
				if type(ore) == "string" and ore ~= "" then
					local rate = incomePerSec(ore,
						tonumber(LP:GetAttribute(key .. "_OreLevel")) or 1,
						LP:GetAttribute(key .. "_OreMutation"))
					if rate and (worst == nil or rate < worst) then
						worst, worstName = rate, ore
					end
				end
			end
		end
	end
	return worst, worstName
end

local function firePrompt(prompt)
	if not prompt or not prompt:IsA("ProximityPrompt") then return false end
	local ok, err = pcall(function() fireproximityprompt(prompt) end)
	if not ok then Log.err("fireproximityprompt", err) end
	return ok
end

-- Roller lever prompt: Bases/<base>.Roller.Lever.<prompt> (0117.lua:554).
local function getLeverPrompt(base)
	if not base then return nil end
	local roller = base:FindFirstChild("Roller", true)
	local lever = roller and roller:FindFirstChild("Lever")
	if not lever then return nil end
	return lever:FindFirstChildWhichIsA("ProximityPrompt")
		or lever:FindFirstChildWhichIsA("ProximityPrompt", true)
end

-- Pending rolled ore: LocalRollingOreDisplay with PurchasePromptReady and the
-- prompt's OreName/PedestalName attributes (0117.lua:1160, :4452-4454).
local function getPendingRoll(base)
	if not base then return nil, nil end
	local pedestals = base:FindFirstChild("OrePedestals")
	if not pedestals then return nil, nil end
	for _, display in ipairs(pedestals:GetDescendants()) do
		if display:IsA("Model") and display.Name == "LocalRollingOreDisplay"
			and display:GetAttribute("PurchasePromptReady") == true then
			local prompt = display:FindFirstChildWhichIsA("ProximityPrompt", true)
			if prompt and prompt:GetAttribute("InteractionType") == "RollerOrePurchase" then
				return prompt, {
					oreName = prompt:GetAttribute("OreName"),
					pedestalName = prompt:GetAttribute("PedestalName"),
				}
			end
		end
	end
	return nil, nil
end

-- Carried stack: the game's own CarriedOreCrateStack (0052.lua:1641). Its
-- CarriedCrateType attribute tells raw crates from smelted metal.
local function carriedStack()
	local char = LP.Character
	local stack = char and char:FindFirstChild("CarriedOreCrateStack")
	return (stack and stack:IsA("Model")) and stack or nil
end

local lastRun = {}

local function due(key, seconds)
	local now = os.clock()
	if (lastRun[key] or 0) + seconds > now then return false end
	lastRun[key] = now
	return true
end

local function invoke(name, ...)
	local r = remote(name)
	if not r then return false, nil end
	local ok, result = pcall(function(...) return r:InvokeServer(...) end, ...)
	if not ok then return false, nil end
	return type(result) == "table" and result.success == true, result
end

-- ------------------------------------------------------- purchase prompts
-- The Robux popup is server-driven: ReplicatedStorage.DeveloperProductPrompt
-- carries a product id and RollerClient answers it with
-- MarketplaceService:PromptProductPurchase (0117.lua:221, :315-324). It is the
-- only listener on that event in the dump, so every popup this module can
-- provoke arrives through it. We log the id and suspend the game's handler
-- while the module is loaded; the connections are re-enabled on unload.
local Guard = { suspended = {}, own = nil }

local function armPromptGuard()
	local event = ReplicatedStorage:FindFirstChild("DeveloperProductPrompt")
	if not event or not event:IsA("RemoteEvent") then return end

	if not Guard.own then
		Guard.own = event.OnClientEvent:Connect(function(productId)
			S.blocked = (S.blocked or 0) + 1
			setStatus("Blocked a Robux prompt (product " .. tostring(productId) .. ")")
			Log.info(string.format("developer product prompt id=%s blocked=%s",
				tostring(productId), tostring(S.blockPrompts)))
		end)
		table.insert(S.conns, Guard.own)
	end

	if not S.blockPrompts or type(getconnections) ~= "function" then return end
	local ok, conns = pcall(getconnections, event.OnClientEvent)
	if not ok or type(conns) ~= "table" then return end
	for _, conn in ipairs(conns) do
		-- Never suspend our own logger. Both the Enabled read and Disable can
		-- throw depending on the executor's connection wrapper.
		if conn ~= Guard.own and not Guard.suspended[conn] then
			local ok2, enabled = pcall(function() return conn.Enabled end)
			if not ok2 or enabled ~= false then
				if pcall(function() conn:Disable() end) then
					Guard.suspended[conn] = true
				end
			end
		end
	end
end

local function releasePromptGuard()
	for conn in next, Guard.suspended do
		pcall(function() conn:Enable() end)
	end
	Guard.suspended = {}
end

-- ---------------------------------------------------------------- roller
-- Buy a rolled ore when it beats the weakest ore currently equipped (or the
-- rarity floor), and we can afford the seed. Otherwise roll again.
local function smartRollTick()
	local base = getBase()
	if not base then setStatus("No base assigned") return end

	local prompt, pending = getPendingRoll(base)
	if prompt and pending and type(pending.oreName) == "string" then
		-- Every branch below touches the lever or the purchase prompt, so the
		-- whole decision is paced. Without this the skip branch re-pulled the
		-- lever on every 0.25s loop turn (four pulls a second in the 09-05
		-- session log), and the server answered that with DeveloperProductPrompt.
		if not due("roll", CFG.rollDelay) then return end
		local newRate = incomePerSec(pending.oreName, 1, nil)
		local curRate, curName = weakestEquipped(base)
		local money = getMoney()
		local cost = seedCost(pending.oreName)
		local rankOk = rarityRank(pending.oreName) >= math.floor(CFG.minRarity)
		local beats = newRate ~= nil and (curRate == nil or newRate > curRate)

		if rankOk and beats and money >= cost then
			-- The game's own prompt handler is identical to a player press;
			-- the remote fallback matches 0117.lua:1188 exactly.
			if not firePrompt(prompt) and RollerPurchaseEvent then
				pcall(function() RollerPurchaseEvent:FireServer(pending.pedestalName, pending.oreName) end)
			end
			S.buys = S.buys + 1
			setStatus(string.format("Bought %s (%.0f/s > %.0f/s)", pending.oreName, newRate or 0, curRate or 0))
			Log.info(string.format("buy ore=%s rate=%s worst=%s(%s) money=%d cost=%s",
				pending.oreName, tostring(newRate), tostring(curName), tostring(curRate), money, tostring(cost)))
		else
			S.skips = S.skips + 1
			setStatus(string.format("Skipped %s (%s)", pending.oreName,
				(not rankOk and "below rarity floor")
					or (not beats and "no profit gain")
					or "cannot afford"))
			Log.info(string.format("skip ore=%s rank=%s beats=%s afford=%s",
				pending.oreName, tostring(rankOk), tostring(beats), tostring(money >= cost)))
			-- Roll again: a fresh lever pull replaces the pending roll.
			local lever = getLeverPrompt(base)
			if lever then firePrompt(lever) end
			S.rolls = S.rolls + 1
		end
		return
	end

	if due("roll", CFG.rollDelay) then
		local lever = getLeverPrompt(base)
		if lever then
			firePrompt(lever)
			S.rolls = S.rolls + 1
			setStatus("Rolling...")
		end
	end
end

local function plainRollTick()
	local base = getBase()
	if not base then setStatus("No base assigned") return end
	if not due("roll", CFG.rollDelay) then return end
	local lever = getLeverPrompt(base)
	if lever then
		firePrompt(lever)
		S.rolls = S.rolls + 1
		setStatus("Rolling...")
	end
end

-- ---------------------------------------------------------------- crates
-- Collect via the game's own prompt (0052.lua:1166). With the furnace chain on,
-- raw crates feed the furnace instead of being sold raw.
local function crateTick()
	local base = getBase()
	if not base then return end
	if not due("crate", CFG.crateDelay) then return end
	if carriedStack() then return end -- hands full; furnace/sell tick drives next

	local stack = base:FindFirstChild("DroneCrateStack")
	if stack and #stack:GetChildren() > 0 then
		local prompt = base:FindFirstChild("PickUpOresPrompt", true)
		if prompt and prompt.Enabled and firePrompt(prompt) then
			S.crates = S.crates + 1
			setStatus("Collected crate")
		end
	end

	if not S.autoFurnace then
		local sell = base:FindFirstChild("SellOresPrompt", true)
		if sell and sell.Enabled and firePrompt(sell) then
			S.sells = S.sells + 1
			setStatus("Sold crate")
		end
	end
end

-- Furnace chain: buy -> place raw ores -> pick up smelted metal -> sell.
local function furnaceTick()
	local base = getBase()
	if not base then return end
	if not due("furnace", CFG.crateDelay) then return end

	local furnace = base:FindFirstChild("Furnace")
	if not furnace then return end

	local carrying = carriedStack()
	local isMetal = carrying and carrying:GetAttribute("CarriedCrateType") == "Metal"

	-- 1. purchase prompt (server validates money)
	if not furnace:GetAttribute("FurnacePurchased") then
		local buy = furnace:FindFirstChild("PurchasePromptPart")
		buy = buy and buy:FindFirstChild("PurchaseFurnacePrompt")
		if buy and buy.Enabled and getMoney() >= 150000 then
			firePrompt(buy)
			setStatus("Buying furnace")
		end
		return
	end

	-- 2. carrying raw ores -> place them
	if carrying and not isMetal then
		local place = furnace:FindFirstChild("PlaceCratesPromptPart")
		place = place and place:FindFirstChild("PlaceCratesPrompt")
		if place and place.Enabled and firePrompt(place) then
			S.placed = S.placed + 1
			setStatus("Placed ores in furnace")
		end
		return
	end

	-- 3. smelted metal ready -> pick up
	if not carrying then
		local metalStack = furnace:FindFirstChild("FurnaceMetalCrateStack")
		if metalStack and #metalStack:GetChildren() > 0 then
			local pick = furnace:FindFirstChild("MetalCratePlacementPart")
			pick = pick and pick:FindFirstChild("PickUpCratesPrompt")
			if pick and pick.Enabled and firePrompt(pick) then
				S.smelted = S.smelted + 1
				setStatus("Picked up metal crates")
			end
		end
		return
	end

	-- 4. carrying metal -> sell
	if isMetal then
		local sell = base:FindFirstChild("SellOresPrompt", true)
		if sell and sell.Enabled and firePrompt(sell) then
			S.sells = S.sells + 1
			setStatus("Sold metal crates")
			Log.info(string.format("metal sell money=%d", getMoney()))
		end
	end
end

-- ---------------------------------------------------------------- fuser
-- Buy the fuser, fill its nodes, start the fusion, claim the mega ore.
-- StartFusion is only legal while FuserPhase == "Loading" (0065.lua:261).
local function fuserTick()
	local base = getBase()
	if not base then return end
	if not due("fuser", CFG.fuserDelay) then return end

	local fuser = base:FindFirstChild("Fuser")
	if not fuser then return end

	if fuser:GetAttribute("FuserPurchased") ~= true then
		local buy = fuser:FindFirstChild("PurchasePromptPart")
		buy = buy and buy:FindFirstChild("PurchaseFuserPrompt")
		if buy and buy.Enabled then
			firePrompt(buy)
			setStatus("Buying fuser")
		end
		return
	end

	-- Claim first: a finished mega ore blocks the next cycle.
	local hub = fuser:FindFirstChild("CentralHub", true)
	local claim = hub and hub:FindFirstChild("ClaimMegaOrePrompt", true)
	if claim and claim:IsA("ProximityPrompt") and claim.Enabled then
		if firePrompt(claim) then
			setStatus("Claimed fused ore")
			Log.info("fuser claim")
		end
		return
	end

	local phase = fuser:GetAttribute("FuserPhase")
	if phase == "Fusing" then
		setStatus("Fusing...")
		return
	end

	-- Loading: fill every empty node, then start.
	local nodes = fuser:FindFirstChild("Nodes", true)
	local filled = true
	if nodes then
		for _, node in ipairs(nodes:GetChildren()) do
			local holder = node:FindFirstChild("OrePlaceholder")
			local prompt = holder and holder:FindFirstChildWhichIsA("ProximityPrompt")
			if prompt and prompt.Enabled and prompt.ActionText == "Place Ore" then
				filled = false
				firePrompt(prompt)
				setStatus("Loading fuser")
				break
			end
		end
	end

	if filled and phase == "Loading" then
		local ok = invoke("FuserAction", base.Name, "StartFusion")
		if ok then
			S.fusions = S.fusions + 1
			setStatus("Started fusion")
			Log.info("fuser StartFusion")
		end
	end
end

-- ---------------------------------------------------------------- upgrades
-- Server rejects what we cannot afford (0042-0044 flows), so the loop only
-- paces attempts and stops after the first accepted one.
local function upgradeTick()
	local base = getBase()
	if not base then return end
	if not due("upgrade", CFG.upgradeDelay) then return end

	local baseName = base.Name
	local top = maxFloor()

	local function level(prefix, floor)
		return math.floor(tonumber(LP:GetAttribute(string.format("%s_Floor%d", prefix, floor)))
			or tonumber(LP:GetAttribute(prefix)) or 1)
	end

	for floor = 1, top do
		if level("DrillSpeedLevel", floor) < 10
			and invoke("BaseUpgradeDrillSpeed", baseName, floor) then
			S.upgrades = S.upgrades + 1
			setStatus("Upgraded drill speed f" .. floor)
			return
		end
		if level("DrillYieldLevel", floor) < 10
			and invoke("BaseUpgradeDrillYield", baseName, floor) then
			S.upgrades = S.upgrades + 1
			setStatus("Upgraded drill yield f" .. floor)
			return
		end
		if level("OreRegenSpeedLevel", floor) < 100
			and invoke("BaseUpgradeOreRegenSpeed", baseName, floor) then
			S.upgrades = S.upgrades + 1
			setStatus("Upgraded ore regen f" .. floor)
			return
		end
	end

	if invoke("RollerUpgradeOreLuck", baseName) then
		S.upgrades = S.upgrades + 1
		setStatus("Upgraded roller luck")
		return
	end
	if invoke("RollerUpgradePedestal", baseName) then
		S.upgrades = S.upgrades + 1
		setStatus("Upgraded pedestal")
		return
	end

	local furnace = base:FindFirstChild("Furnace")
	if furnace and furnace:GetAttribute("FurnacePurchased") == true then
		if invoke("BaseCrateAction", baseName, "UpgradeFurnace") then
			S.upgrades = S.upgrades + 1
			setStatus("Upgraded furnace rate")
		end
	end
end

-- ---------------------------------------------------------------- floors
-- The server quotes the price ("GetFloorPrice", 0038.lua:29) and validates
-- money on purchase (0038.lua:337).
local function floorTick()
	local base = getBase()
	if not base then return end
	if not due("floor", CFG.floorDelay) then return end

	local purchase = remote("BaseBuildPurchaseFloor")
	if not purchase then return end
	local nextFloor = maxFloor() + 1

	local okPrice, price = pcall(function() return purchase:InvokeServer("GetFloorPrice", nextFloor) end)
	if okPrice and type(price) == "table" and price.success == true and type(price.price) == "number" then
		if getMoney() < price.price then
			setStatus(string.format("Next floor costs %d — waiting", price.price))
			return
		end
	end

	local ok, result = pcall(function() return purchase:InvokeServer(base.Name, nextFloor) end)
	if ok and type(result) == "table" and result.success == true then
		S.floors = S.floors + 1
		setStatus("Bought floor " .. nextFloor)
		Log.info(string.format("floor bought=%d money=%d", nextFloor, getMoney()))
	end
end

-- Tunnels: one locked tunnel per attempt, cheapest floor first. The unlocked
-- flag is the player attribute the tunnel GUI reads (0041.lua:164).
local function tunnelTick()
	local base = getBase()
	if not base then return end
	if not due("tunnel", CFG.floorDelay) then return end
	if not remote("BaseBuildPurchaseTunnel") then return end

	for floor = 1, maxFloor() do
		for _, tunnel in ipairs(tunnelModels(base, floor)) do
			local key = tunnelKey(floor, tunnel.Name)
			if LP:GetAttribute(key .. "_Unlocked") ~= true then
				if invoke("BaseBuildPurchaseTunnel", base.Name, floor, tunnel.Name) then
					S.tunnels = S.tunnels + 1
					setStatus(string.format("Bought %s on floor %d", tunnel.Name, floor))
					Log.info(string.format("tunnel bought floor=%d name=%s money=%d", floor, tunnel.Name, getMoney()))
				end
				return -- one attempt per tick either way
			end
		end
	end
end

-- Equip best / apply growth gems: the same two calls the game's own
-- "Equip Best" buttons make (0036.lua:136, :195).
local function equipTick()
	local base = getBase()
	if not base then return end
	if not due("equip", CFG.upgradeDelay) then return end

	if S.autoEquip and invoke("BaseBuildTunnelAction", base.Name, 1, "Tunnel1", "EquipBest") then
		S.equips = S.equips + 1
		setStatus("Equipped best ores")
	end

	if S.autoGems then
		local gems = math.floor(tonumber(LP:GetAttribute("GrowthGemInventoryCount")) or 0)
		if gems > 0 and invoke("BaseBuildTunnelAction", base.Name, 1, "Tunnel1", "ApplyBestGrowthGems") then
			setStatus(string.format("Applied growth gems (%d held)", gems))
			Log.info(string.format("gems applied held=%d", gems))
		end
	end
end

-- ---------------------------------------------------------------- rewards
-- Daily (0007.lua:317), playtime (0013.lua:515) and free lucky spins
-- (0072.lua:352/686/697). Each mirrors the client's own claim gate; nothing is
-- claimed that the game's own button would refuse.
local function rewardTick()
	if not due("reward", CFG.rewardDelay) then return end

	local daily = remote("GetDailyRewardsState")
	local claim = remote("ClaimDailyReward")
	if daily and claim then
		local ok, state = pcall(function() return daily:InvokeServer() end)
		if ok and type(state) == "table" and tonumber(state.nextAvailableAt) then
			local now = (tonumber(state.serverTime) or os.time())
			if now >= state.nextAvailableAt then
				pcall(function() claim:FireServer() end)
				S.rewards = S.rewards + 1
				setStatus("Claimed daily reward")
				Log.info("daily claim")
			end
		end
	end

	local ptState = remote("PlaytimeRewardsGetState")
	local ptClaim = remote("PlaytimeRewardsClaim")
	if ptState and ptClaim then
		local ok, state = pcall(function() return ptState:InvokeServer() end)
		if ok and type(state) == "table" and type(state.rewards) == "table" then
			local elapsed = math.max(0, math.floor(tonumber(state.elapsed) or 0))
			for index, reward in pairs(state.rewards) do
				if type(reward) == "table" and reward.claimed ~= true
					and elapsed >= (tonumber(reward.unlockAt) or math.huge) then
					pcall(function() ptClaim:FireServer(index) end)
					S.rewards = S.rewards + 1
					setStatus("Claimed playtime reward " .. tostring(index))
					Log.info(string.format("playtime claim index=%s elapsed=%d", tostring(index), elapsed))
				end
			end
		end
	end

	local spinState = remote("GetLuckySpinState")
	local spin = remote("RequestLuckySpin")
	local complete = remote("CompleteLuckySpin")
	if spinState and spin and complete then
		local ok, state = pcall(function() return spinState:InvokeServer() end)
		if ok and type(state) == "table" and (tonumber(state.spins) or 0) > 0 then
			local okSpin, result = pcall(function() return spin:InvokeServer() end)
			if okSpin and type(result) == "table" and result.ok == true then
				pcall(function() return complete:InvokeServer(result.spinId) end)
				S.spins = S.spins + 1
				setStatus("Used a free lucky spin")
				Log.info(string.format("lucky spin spins=%s", tostring(state.spins)))
			end
		end
	end
end

-- ---------------------------------------------------------------- master loop
task.spawn(function()
	while S.alive do
		local ok, err = pcall(function()
			-- Re-armed on a slow cadence: RollerClient reconnects its handler
			-- on respawn, and a suspended connection does not survive that.
			if due("promptguard", 5) then armPromptGuard() end
			if S.autoRoll then
				if S.smartBuy then smartRollTick() else plainRollTick() end
			end
			if S.autoCrate then crateTick() end
			if S.autoFurnace then furnaceTick() end
			if S.autoFuser then fuserTick() end
			if S.autoUpgrade then upgradeTick() end
			if S.autoFloor then floorTick() end
			if S.autoTunnel then tunnelTick() end
			if S.autoEquip or S.autoGems then equipTick() end
			if S.autoRewards then rewardTick() end
		end)
		if not ok then
			Log.err("loop", err)
			setStatus("Loop error (logged)")
		end
		task.wait(0.25)
	end
end)

-- Anti-AFK: fire the idle event the way the engine expects; client-local.
table.insert(S.conns, LP.Idled:Connect(function()
	if not S.alive or not S.antiAfk then return end
	pcall(function()
		VirtualUser:CaptureController()
		VirtualUser:ClickButton2(Vector2.new())
	end)
	Log.info("anti-afk idle bump")
end))

-- ---------------------------------------------------------------- teardown
local function destroy()
	if not S.alive then return end
	S.alive = false
	releasePromptGuard()
	for _, conn in ipairs(S.conns) do
		pcall(function() conn:Disconnect() end)
	end
	S.conns = {}
	if S.screen then pcall(function() S.screen:Destroy() end) end
	saveConfig()
	if G[GKEY] == S then G[GKEY] = nil end
end
S.destroy = destroy
G[GKEY] = S

table.insert(S.conns, UserInputService.InputBegan:Connect(function(input, processed)
	if processed or input.KeyCode ~= Enum.KeyCode.K then return end
	task.defer(destroy)
end))

-- ---------------------------------------------------------------- UI
local HOST = G.__R3ST_HOST
local Kit
local okKit, kitOrErr = pcall(function()
	return (HOST and HOST.ui) or loadfile("../scripts/r3st_ui.lua")()
end)
if not okKit or type(kitOrErr) ~= "table" then
	Log.err("UI kit unavailable", kitOrErr)
	destroy()
	return
end
Kit = kitOrErr

local screen = Instance.new("ScreenGui")
screen.Name = "R3ST_SellOres_" .. tostring(math.random(1000, 9999))
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.DisplayOrder = 2147483647
screen.ZIndexBehavior = Enum.ZIndexBehavior.Global

local panel = Instance.new("Frame")
panel.Name = "SellOresPanel"
panel.BackgroundColor3 = Kit.COL.bg
panel.BorderSizePixel = 0
panel.Size = UDim2.fromOffset(760, 560)
panel.Position = UDim2.new(0.5, CFG.panelX, 0.5, CFG.panelY)
panel.Parent = screen
screen.Parent = CoreGui
S.screen, S.panel = screen, panel

local H = Kit.host({ screen = screen, root = panel })
S.host = H
local inner = Instance.new("Frame")
inner.BackgroundTransparency = 1
inner.Position = UDim2.fromOffset(H.hosted and 12 or 18, H.hosted and 8 or 14)
inner.Size = UDim2.new(1, H.hosted and -24 or -36, 1, H.hosted and -16 or -28)
inner.Parent = panel

local live = {}
local W = Kit.bind({ live = live, conns = S.conns, cfg = CFG, save = queueSave })
table.insert(S.conns, RunService.RenderStepped:Connect(function()
	for _, paint in ipairs(live) do
		local ok, err = pcall(paint)
		if not ok then Log.err("ui paint", err) end
	end
end))
W.header(inner, {
	title = "Sell Ores",
	version = BUILD_VERSION,
	subtitle = "Roller, crates, furnace, fuser, upgrades, floors, tunnels and rewards — all through the game's own remotes and prompts.",
	gameId = EXPECTED_GAME,
	placeId = EXPECTED_PLACE,
})

local page = Instance.new("ScrollingFrame")
page.Name = "Main"
page.BackgroundTransparency = 1
page.BorderSizePixel = 0
page.Position = UDim2.fromOffset(0, 116)
page.Size = UDim2.new(1, 0, 1, -164)
page.ScrollBarThickness = 3
page.ScrollBarImageColor3 = Kit.COL.line
page.CanvasSize = UDim2.new()
page.Parent = inner
W.page(page, { width = 700 })

local function toggleT(key, label, desc)
	W.toggle(page, {
		label = label, desc = desc, fullRow = true, stateText = true,
		get = function() return S[key] end,
		set = function(value)
			S[key] = value
			Log.info(string.format("%s -> %s", key, tostring(value)))
			if value then setStatus(label .. " ON") end
		end,
	})
end

W.section(page, "Roller")
toggleT("autoRoll", "Auto roll", "Pulls the roller lever on repeat")
toggleT("smartBuy", "Smart ore buy", "Buys a rolled ore only when it beats your weakest equipped tunnel ore and clears the rarity floor; skips and re-rolls otherwise")
W.slider(page, {
	label = "Rarity floor", key = "minRarity", min = 1, max = 13, step = 1,
	desc = "Never buy below this rarity, however good the income looks",
	fmt = function(v) return rarityName(math.floor(v)) end,
})
W.slider(page, {
	label = "Roll delay", key = "rollDelay", min = 0.5, max = 10, step = 0.1,
	desc = "Pause between lever pulls when no rolled ore is waiting",
	fmt = function(v) return string.format("%.1fs", v) end,
})
W.statusRow(page, function() return "Status: " .. S.status end)
W.statusRow(page, function()
	return string.format("Rolls %d  •  Bought %d  •  Skipped %d", S.rolls, S.buys, S.skips)
end)
W.note(page, "Income uses OreMetadata's own curve: level scaling, mutation multiplier and the HighestDiscovered reference. The server sees a normal RollerPurchaseEvent.")

W.section(page, "Crates")
toggleT("autoCrate", "Auto collect crate", "Fires the PickUpOres prompt whenever the drone leaves a crate; sells raw ores when the furnace chain is off")
W.slider(page, {
	label = "Crate delay", key = "crateDelay", min = 1, max = 30, step = 0.5,
	desc = "Seconds between crate and furnace chain attempts",
	fmt = function(v) return string.format("%.1fs", v) end,
})
W.statusRow(page, function() return string.format("Collected %d  •  Sold %d", S.crates, S.sells) end)

W.section(page, "Furnace chain")
toggleT("autoFurnace", "Auto furnace", "Buys the furnace, places collected ores, picks up smelted metal, then sells it")
W.note(page, "While this is on, Auto collect crate stops selling raw ores and feeds the furnace instead. Smelting is server-side; we only drive its prompts.")
W.statusRow(page, function() return string.format("Placed %d  •  Smelted %d  •  Sold %d", S.placed, S.smelted, S.sells) end)

W.section(page, "Fuser")
toggleT("autoFuser", "Auto fuser", "Buys the fuser, loads every node, starts the fusion, then claims the mega ore")
W.slider(page, {
	label = "Fuser pacing", key = "fuserDelay", min = 1, max = 30, step = 0.5,
	desc = "Seconds between fuser chain steps",
	fmt = function(v) return string.format("%.1fs", v) end,
})
W.statusRow(page, function() return string.format("Fusions started %d", S.fusions) end)

W.section(page, "Auto upgrade")
toggleT("autoUpgrade", "Auto upgrades", "Drill speed, drill yield, ore regen per floor, roller pedestal + luck, furnace processing rate")
toggleT("autoEquip", "Auto equip best", "Runs the game's own Equip Best pass so newly bought ores actually get placed")
toggleT("autoGems", "Auto apply growth gems", "Spends held growth gems on the best tunnels; idle when you hold none")
W.slider(page, {
	label = "Upgrade pacing", key = "upgradeDelay", min = 1, max = 30, step = 0.5,
	desc = "Seconds between upgrade, equip and gem attempts",
	fmt = function(v) return string.format("%.1fs", v) end,
})
W.statusRow(page, function() return string.format("Upgrades %d  •  Equip passes %d", S.upgrades, S.equips) end)

W.section(page, "Expansion")
toggleT("autoFloor", "Auto buy next floor", "Buys the next floor whenever money covers its quoted price")
toggleT("autoTunnel", "Auto buy tunnels", "Buys locked tunnels on unlocked floors, lowest floor first")
W.slider(page, {
	label = "Expansion pacing", key = "floorDelay", min = 2, max = 60, step = 1,
	desc = "Seconds between floor and tunnel purchase attempts",
	fmt = function(v) return string.format("%.0fs", v) end,
})
W.statusRow(page, function() return string.format("Floors %d  •  Tunnels %d", S.floors, S.tunnels) end)

W.section(page, "Rewards")
toggleT("autoRewards", "Auto claim rewards", "Daily reward, playtime rewards and free lucky spins — each gated exactly like the game's own claim button")
W.slider(page, {
	label = "Reward check", key = "rewardDelay", min = 10, max = 300, step = 5,
	desc = "Seconds between reward state checks",
	fmt = function(v) return string.format("%.0fs", v) end,
})
W.statusRow(page, function() return string.format("Rewards %d  •  Spins %d", S.rewards, S.spins) end)
W.note(page, "Only free spins are used. Nothing here prompts a Robux purchase.")

W.section(page, "Session")
W.toggle(page, {
	label = "Block Robux prompts", fullRow = true, stateText = true,
	desc = "Suspends the game's DeveloperProductPrompt handler so server-offered purchase popups cannot open while automation runs; restored on unload",
	get = function() return S.blockPrompts end,
	set = function(v)
		S.blockPrompts = v
		if v then armPromptGuard() else releasePromptGuard() end
		Log.info("blockPrompts -> " .. tostring(v))
	end,
})
W.statusRow(page, function() return string.format("Prompts blocked %d", S.blocked or 0) end)
W.toggle(page, {
	label = "Anti-AFK", desc = "Bumps idle when the client is kicked to the menu",
	get = function() return S.antiAfk end,
	set = function(v) S.antiAfk = v end,
})
W.note(page, "All automation boots OFF every session by design. K = panic unload.")

W.section(page, "Module")
W.button(page, "Reload module", "Asks the live Hub to remount this module from disk", function()
	local hub = G.__R3ST_HUB
	if type(hub) ~= "table" or type(hub.reload) ~= "function" then setStatus("Hub reload unavailable") return end
	task.defer(function() hub.reload("sell-ores") end)
end, true)

page.CanvasSize = UDim2.fromOffset(0, Kit.height(page))
W.footer(inner, {
	onUnload = destroy,
	onSettings = function() end,
	hint = "K = panic unload",
})
H.hideBind(function() panel.Visible = not panel.Visible end)

saveConfig()
Log.info("UI ready hosted=" .. tostring(H.hosted))
