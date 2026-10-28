------------------------------------------------------------------------
-- Build a Base RNG Hub v1.8.0 (2026-09-02) -- PlaceId 99108783264633
--
-- v1.8.0 mounts inside R3ST Hub and draws every control with r3st_ui.lua.
-- Standalone injection keeps the same controls and lifecycle. RightShift is
-- owned by the hub while embedded; all action toggles still boot OFF.
--
-- v1.4.0 root-cause fix for BOTH broken features. Two executor facts,
-- both proved by live probe on this client, invalidated every v1.2-v1.3
-- resolver:
--   1. Potassium `getconnections(sig)[i].Function` is nil for game-owned
--      connections (probe: 58 of 59 nil) -> the InputBegan upvalue walk
--      could never see Attack.  attack_not_in_upvalues, every time.
--   2. Potassium `debug.getupvalue(fn, i)` returns the VALUE ONLY (not
--      name,value) and THROWS "index out of range" past the last upvalue.
--      Every `local name, val = debug.getupvalue(...)` loop here was
--      reading a value into `name`, `nil` into `val`, and erroring out of
--      the loop -- which also killed findResolveParamsSafe mid-probe, so
--      Instant never installed either (log: no resolveParams_scan line).
-- Both resolvers are now getgc(true) + debug.info(fn,"s"/"l") identity,
-- which is exact, ~3ms, and survives upvalue reordering:
--   Attack            = ClientWeaponModule:68   (0262:53)
--   GetWeaponCooldown = ClientWeaponModule:50   (0262:36)
--   resolveParams     = ClientRollModule:129    (0240:88)
--
-- Auto Swing: calls the game's own Attack(), so animation, sound and
-- Warp.Fire all run from a ReplicatedStorage stack -- Warp's traceback
-- guard (0149:42 Fire) accepts it, unlike a direct AttackWeapon:Fire.
-- Attack self-gates on WaveActive and on its own upvalue u4 (last swing
-- clock, upvalue #2). Overdrive clears u4 before each call, which lifts
-- the 0.14s client cap; probe measured 20/20 swings at 18.3/s accepted.
-- Rate <= 1/cooldown never touches u4 at all.
--
-- Fast: workspace AdminRollSpeed (0240:92) -- floor 0.25s.
-- Instant: hook resolveParams below floor + RollSpeed mult for stay.
-- Observe wraps always on. Game AutoRoll native. No print/warn. File log.
-- Re-inject safe: self-teardown on load; RightShift = hide; K = unload.
--
-- Posture (potassium-dev 5.7): rung 6, but only via the game's own client
-- function firing the game's own remote -- no new remote, no new payload.
-- CLIENT INSPECTION 0 / LOG MONITORING 0 / REPORTING 0 (anticheat_deep.txt).
-- Loud knob is swing rate: above ~7/s no legitimate client produces it, so
-- Overdrive defaults OFF and every toggle defaults OFF on load.
------------------------------------------------------------------------

local BUILD_VERSION = "BAB-1.8.0-2026-09-02"
local EXPECTED_PLACE = 99108783264633
local EXPECTED_GAME = 10253235584
local GKEY = "__BUILD_A_BASE_RNG_HUB"
local LOG_FILE = "logs/bab_hub.log"
local PROBE_FILE = "logs/bab_hub_probe.log"

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

local function correctExperience()
	return game.GameId == EXPECTED_GAME or game.PlaceId == EXPECTED_PLACE
end

if not correctExperience() then
	return
end

if type(G[GKEY]) == "table" and type(G[GKEY].destroy) == "function" then
	pcall(G[GKEY].destroy)
end

local CFG = {
	fast = false,
	instant = false,
	fastMult = 12,
	instantDuration = 0.05,
	autoSwing = false,
	turbo = false,
	turboRate = 4,
	obeyLimit = true,
	autoSkills = false,
	keepMoney = 0,
	spendRolls = false,
	swingRate = 12,
	overdrive = false,
	observe = true,
	probeOnBoot = true,
	panelX = 24,
	panelY = 90,
}

local S = {
	alive = true,
	status = "boot",
	connections = {},
	hooks = {},
	wraps = {},
	guiDestroy = nil,
	frame = nil,
	screenGui = nil,
	guiVisible = true,
	statusLabel = nil,
	statsLabel = nil,
	probeLabel = nil,
	prevAdminRollSpeed = nil,
	adminOwned = false,
	resolveParams = nil,
	instantReady = false,
	stayHooked = false,
	lastAdminMultLogged = nil,
	patchLogLeft = 8,
	applyToken = 0,
	lastProbeSummary = "none",
	rollSeq = 0,
	stats = {
		play = 0,
		update = 0,
		waitEnd = 0,
		waitMsSum = 0,
		waitMsMax = 0,
		lastWaitMs = 0,
		lastPlayMs = 0,
		autoToggle = 0,
		swings = 0,
		swingBlocked = 0,
		swingSkipWave = 0,
		errors = 0,
	},
	lastSwingAt = 0,
	nativeAttack = nil,
	nativeGetCooldown = nil,
	swingMethod = "none",
	swingRateLive = 0,
	swingWindow = {},
	u4Original = nil,
	performRoll = nil,
	turboInflight = 0,
	turboRateLive = 0,
	turboLastTotal = nil,
	rollLimit = nil,
	rollLimitCached = 4,
	skillRemotes = nil,
	skillShim = nil,
	skillsBought = 0,
	skillSpent = 0,
	lastSkill = "none",
	turboLastSample = 0,
	ClientBuildModule = nil,
	WeaponsConfig = nil,
}

-- Potassium debug.getupvalue returns the VALUE only and THROWS past the last
-- upvalue. Never call it bare. (probe 2026-08-21: ":5: index out of range")
local function upval(fn, i)
	if type(fn) ~= "function" or type(debug.getupvalue) ~= "function" then
		return nil, false
	end
	local ok, v = pcall(debug.getupvalue, fn, i)
	if not ok then
		return nil, false
	end
	return v, true
end

local function setupval(fn, i, v)
	if type(fn) ~= "function" or type(debug.setupvalue) ~= "function" then
		return false
	end
	return (pcall(debug.setupvalue, fn, i, v))
end

local LogRing = {}
local LOG_RING_MAX = 400

local function ensureLogDir()
	pcall(function()
		if isfolder and not isfolder("logs") and makefolder then
			makefolder("logs")
		end
	end)
end

local function appendPath(path, text)
	ensureLogDir()
	pcall(function()
		if isfile and isfile(path) then
			appendfile(path, text)
		else
			writefile(path, text)
		end
	end)
end

local function fmtKV(fields)
	if type(fields) ~= "table" then
		return tostring(fields)
	end
	local parts = {}
	for k, v in pairs(fields) do
		local tv = typeof(v)
		local s
		if tv == "string" or tv == "number" or tv == "boolean" or tv == "nil" then
			s = tostring(v)
		elseif tv == "table" then
			local ok, enc = pcall(HttpService.JSONEncode, HttpService, v)
			s = ok and enc or ("table:" .. tostring(v))
		else
			s = tv .. ":" .. tostring(v)
		end
		table.insert(parts, tostring(k) .. "=" .. s)
	end
	table.sort(parts)
	return table.concat(parts, " ")
end

local function log(level, event, fields)
	local line = string.format(
		"[%s] [%s] [%s] %s\n",
		os.date("!%Y-%m-%dT%H:%M:%SZ"),
		level,
		tostring(event),
		fields and fmtKV(fields) or ""
	)
	table.insert(LogRing, line)
	if #LogRing > LOG_RING_MAX then
		table.remove(LogRing, 1)
	end
	appendPath(LOG_FILE, line)
	if level == "PROBE" or level == "ERR" then
		appendPath(PROBE_FILE, line)
	end
end

-- A thread entered from an RBXScriptSignal callback (button click, InputBegan,
-- ContextAction) runs sandboxed on this executor: any Instance property write
-- throws "cannot access 'Instance' (lacking capability Plugin)" and kills the
-- rest of the handler. That is why every toggle looked dead -- the flag flipped,
-- then the badge repaint threw. So callbacks only ever mutate state; all
-- Instance writes happen in UI.pump, a thread we spawned ourselves.
local UI = {
	painters = {},
	dirty = true,
}

local function uiPaint(fn)
	table.insert(UI.painters, fn)
	return fn
end

local function uiMark()
	UI.dirty = true
end

-- Painters are cheap and self-debouncing, so the pump just runs them all at
-- 30 Hz rather than tracking dirt per widget.
local function startUiPump()
	task.spawn(function()
		while S.alive do
			for _, fn in ipairs(UI.painters) do
				pcall(fn)
			end
			task.wait(1 / 30)
		end
	end)
end

local function setStatus(msg)
	S.status = tostring(msg)
	uiMark()
	log("INFO", "status", { msg = S.status })
end

local function bind(sig, fn)
	local c = sig:Connect(fn)
	table.insert(S.connections, c)
	return c
end

local function mk(className, props, parent)
	local obj = Instance.new(className)
	for k, v in next, props or {} do
		obj[k] = v
	end
	obj.Parent = parent
	return obj
end

-- CRITICAL: use hookfunction RETURN value as old (v1.0 bug was calling pre-hook ref)
local function safeHook(fn, wrapperFactory)
	if type(fn) ~= "function" or not hookfunction then
		return nil, "no_hookfunction_or_fn"
	end
	local old
	local ok, err = pcall(function()
		old = hookfunction(fn, wrapperFactory(function(...)
			return old(...)
		end))
	end)
	if not ok then
		return nil, tostring(err)
	end
	table.insert(S.hooks, fn)
	return old, nil
end

local function wrapField(tbl, key, wrapperFactory)
	if type(tbl) ~= "table" or type(tbl[key]) ~= "function" then
		return false, "missing"
	end
	local old = tbl[key]
	tbl[key] = wrapperFactory(old)
	table.insert(S.wraps, { tbl = tbl, key = key, old = old })
	return true, nil
end

local function restoreAll()
	for i = #S.hooks, 1, -1 do
		local fn = S.hooks[i]
		pcall(function()
			if restorefunction then
				restorefunction(fn)
			end
		end)
	end
	table.clear(S.hooks)
	for i = #S.wraps, 1, -1 do
		local w = S.wraps[i]
		pcall(function()
			w.tbl[w.key] = w.old
		end)
	end
	table.clear(S.wraps)
end

local okReq, ClientRollModule = pcall(require, ReplicatedStorage.Modules.Gameplay.ClientRollModule)
if not okReq then
	log("ERR", "require_ClientRollModule", { err = tostring(ClientRollModule) })
	ClientRollModule = nil
end

local SignalModule = nil
pcall(function()
	SignalModule = require(ReplicatedStorage.Modules.Core.SignalModule)
end)

local DataService = nil
local client = nil
pcall(function()
	DataService = require(ReplicatedStorage.Modules.Core.DataService)
	client = DataService.client
end)

local SkillsUtility = nil
pcall(function()
	SkillsUtility = require(ReplicatedStorage.Modules.Features.Skills.Utility)
end)

local PaidUtility = nil
pcall(function()
	PaidUtility = require(ReplicatedStorage.Modules.Features.PaidProducts.Utility)
end)

local BoostUtility = nil
pcall(function()
	BoostUtility = require(ReplicatedStorage.Modules.Features.Boosts.Utility)
end)

pcall(function()
	S.ClientBuildModule = require(ReplicatedStorage.Modules.Gameplay.ClientBuildModule)
end)

pcall(function()
	S.WeaponsConfig = require(ReplicatedStorage.Modules.Features.Weapons.WeaponsConfig)
end)

-- Identity lookup by (source, definition line). getgc(true) is ~3ms here and
-- exact; upvalue-shape matching and getconnections are both dead ends on
-- Potassium (see header). Line numbers are the DECOMPILED `-- Line: N` values,
-- which is what debug.info(fn, "l") reports for the live closure.
local GC_TARGETS = {
	attack = { src = "ClientWeaponModule", line = 68 },
	weaponCooldown = { src = "ClientWeaponModule", line = 50 },
	resolveParams = { src = "ClientRollModule", line = 129 },
	performRoll = { src = "BottomFrameHandler", line = 180 },
}

local function gcFind(want)
	if type(getgc) ~= "function" or type(debug.info) ~= "function" then
		return nil, "no_getgc"
	end
	local okGc, gc = pcall(getgc, true)
	if not okGc or type(gc) ~= "table" then
		return nil, "getgc_fail"
	end
	for _, v in ipairs(gc) do
		if type(v) == "function" then
			local src = ""
			pcall(function()
				src = tostring(debug.info(v, "s"))
			end)
			if string.find(src, want.src, 1, true) then
				local line = -1
				pcall(function()
					line = tonumber(debug.info(v, "l")) or -1
				end)
				if line == want.line then
					return v, nil
				end
			end
		end
	end
	return nil, "not_in_gc"
end

-- ClientWeaponModule Attack (0262:53, `-- Line: 68`). Calling it directly keeps
-- the Warp.Fire traceback guard happy: the stack still contains the
-- ReplicatedStorage frame the guard greps for (0149:42).
local function resolveNativeAttack(reason)
	local fn, why = gcFind(GC_TARGETS.attack)
	if type(fn) ~= "function" then
		S.nativeAttack = nil
		S.swingMethod = "none"
		log("ERR", "attack_resolve", { reason = reason, err = tostring(why) })
		return false, tostring(why)
	end
	S.nativeAttack = fn
	S.swingMethod = "native_Attack"
	if S.u4Original == nil then
		S.u4Original = upval(fn, 2)
	end
	if type(S.nativeGetCooldown) ~= "function" then
		S.nativeGetCooldown = gcFind(GC_TARGETS.weaponCooldown)
	end
	log("INFO", "attack_resolve", {
		reason = reason,
		method = S.swingMethod,
		nativeCd = type(S.nativeGetCooldown) == "function",
		setupvalue = type(debug.setupvalue) == "function",
	})
	return true, nil
end

-- The game's own GetWeaponCooldown (0262:36) when we have it; the config walk
-- (WeaponsConfig.MeleeOrder x UnlockWeaponN, 0215) is the offline fallback.
local function getWeaponCooldown()
	if type(S.nativeGetCooldown) == "function" then
		local ok, cd = pcall(S.nativeGetCooldown)
		if ok and type(cd) == "number" and cd > 0 then
			return cd
		end
	end
	local tier = 1
	if SkillsUtility and LocalPlayer then
		local ok, owned = pcall(SkillsUtility.GetAllOwned, SkillsUtility, LocalPlayer)
		if ok and type(owned) == "table" then
			for _, name in pairs(owned) do
				local n = tonumber(tostring(name):match("^UnlockWeapon(%d+)$"))
				if n and tier < n then
					tier = n
				end
			end
		end
	end
	local cfg = S.WeaponsConfig
	if type(cfg) == "table" and type(cfg.MeleeOrder) == "table" and type(cfg.Melee) == "table" then
		local key = cfg.MeleeOrder[tier]
		local row = key and cfg.Melee[key]
		if type(row) == "table" and type(row.Stats) == "table" and type(row.Stats.Cooldown) == "number" then
			return row.Stats.Cooldown
		end
	end
	return 0.14
end

-- Ceiling the game itself allows without touching u4.
local function nativeRateCap()
	local cd = getWeaponCooldown()
	return 1 / math.max(0.01, cd)
end

-- Rolling 1s window of ACCEPTED swings only. trim() must never insert, or the
-- meter reports the loop's poll rate instead of the swing rate.
local function trimSwingWindow(now)
	local w = S.swingWindow
	while #w > 0 and now - w[1] > 1 do
		table.remove(w, 1)
	end
	S.swingRateLive = #w
end

local function noteSwingRate(now)
	table.insert(S.swingWindow, now)
	trimSwingWindow(now)
end

-- Returns fired, err. `fired` is proof, not optimism: Attack writes
-- LocalPlayer.LastMeleeSwing (0262:66) only on the swings it actually lets
-- through, so a changed attribute means the remote went out.
local function fireSwing(overdrive)
	local fn = S.nativeAttack
	if type(fn) ~= "function" then
		return false, "no_attack_path"
	end
	local before = LocalPlayer:GetAttribute("LastMeleeSwing")
	if overdrive then
		-- u4 = last-swing clock, Attack upvalue #2. Zeroing it drops the
		-- client-side cooldown gate for this call only.
		setupval(fn, 2, 0)
	end
	local ok, err = pcall(fn)
	S.lastSwingAt = os.clock()
	if not ok then
		S.stats.errors = S.stats.errors + 1
		return false, "native:" .. tostring(err)
	end
	if LocalPlayer:GetAttribute("LastMeleeSwing") ~= before then
		S.stats.swings = S.stats.swings + 1
		noteSwingRate(S.lastSwingAt)
		return true, nil
	end
	S.stats.swingBlocked = S.stats.swingBlocked + 1
	return false, nil
end

local function restoreSwingGate()
	if S.u4Original ~= nil and type(S.nativeAttack) == "function" then
		-- Hand the gate back armed, so the player's own clicks are capped again.
		setupval(S.nativeAttack, 2, os.clock())
	end
end

local function startAutoSwingLoop()
	task.spawn(function()
		local lastResolve = 0
		local lastHeartbeat = 0
		while S.alive do
			local now = os.clock()
			if not CFG.autoSwing then
				S.swingRateLive = 0
				task.wait(0.08)
			else
				if type(S.nativeAttack) ~= "function" and now - lastResolve > 1 then
					lastResolve = now
					resolveNativeAttack("loop")
				end
				local wave = (S.ClientBuildModule and S.ClientBuildModule.WaveActive) and true or false
				if not wave or type(S.nativeAttack) ~= "function" then
					if not wave then
						S.stats.swingSkipWave = S.stats.swingSkipWave + 1
					end
					trimSwingWindow(now)
					if now - lastHeartbeat > 2 then
						lastHeartbeat = now
						log("INFO", "auto_swing_hb", {
							wave = wave,
							method = S.swingMethod,
							swings = S.stats.swings,
						})
					end
					task.wait(wave and 0.2 or 0.05)
				else
					local cd = getWeaponCooldown()
					local target = math.clamp(CFG.swingRate, 1, 40)
					local overdrive = CFG.overdrive and type(debug.setupvalue) == "function"
					local interval = 1 / target
					if not overdrive then
						-- The game gate wins anyway; never spin faster than it allows.
						interval = math.max(interval, cd)
					end
					-- Wait exactly until Attack's own gate opens instead of guessing:
					-- u4 (upvalue 2) is the clock of the last swing it accepted, ours or
					-- the player's own clicks. Overshoot by 1ms so the compare passes.
					local wait = interval - (now - S.lastSwingAt)
					if not overdrive then
						local u4 = upval(S.nativeAttack, 2)
						if type(u4) == "number" then
							wait = math.max(wait, (u4 + cd + 0.001) - now)
						end
					end
					if wait > 0 then
						trimSwingWindow(now)
						task.wait(math.min(wait, 0.25))
					else
						local ok, err = fireSwing(overdrive)
						if err then
							log("ERR", "auto_swing_fire", { err = err, method = S.swingMethod })
							S.nativeAttack = nil
							resolveNativeAttack("after_fail")
							task.wait(0.2)
						elseif not ok then
							-- Refused by the game gate; the u4 read above re-times us.
							task.wait(0.005)
						else
							task.wait()
						end
						if now - lastHeartbeat > 2 then
							lastHeartbeat = now
							log("INFO", "auto_swing_hb", {
								wave = true,
								swings = S.stats.swings,
								blocked = S.stats.swingBlocked,
								target = target,
								live = S.swingRateLive,
								cd = cd,
								overdrive = overdrive,
							})
						end
					end
				end
			end
		end
	end)
end

local COL = {
	bg = Color3.fromRGB(6, 6, 6),
	panel = Color3.fromRGB(12, 12, 12),
	row = Color3.fromRGB(20, 20, 20),
	on = Color3.fromRGB(240, 240, 240),
	stroke = Color3.fromRGB(255, 255, 255),
	text = Color3.fromRGB(245, 245, 245),
	dim = Color3.fromRGB(150, 150, 150),
	ink = Color3.fromRGB(8, 8, 8),
}

local function applyAdminRollSpeed()
	local want = CFG.fast or CFG.instant
	if want then
		if not S.adminOwned then
			S.prevAdminRollSpeed = workspace:GetAttribute("AdminRollSpeed")
			S.adminOwned = true
			log("INFO", "admin_roll_capture", { prev = tostring(S.prevAdminRollSpeed) })
		end
		local mult = CFG.instant and math.max(CFG.fastMult, 40) or math.max(2, CFG.fastMult)
		workspace:SetAttribute("AdminRollSpeed", mult)
		if S.lastAdminMultLogged ~= mult then
			S.lastAdminMultLogged = mult
			log("INFO", "admin_roll_set", { mult = mult, mode = CFG.instant and "instant" or "fast" })
		end
	elseif S.adminOwned then
		workspace:SetAttribute("AdminRollSpeed", S.prevAdminRollSpeed)
		log("INFO", "admin_roll_restore", { prev = tostring(S.prevAdminRollSpeed) })
		S.adminOwned = false
		S.prevAdminRollSpeed = nil
		S.lastAdminMultLogged = nil
	end
end

local function inspectUpvalues(fn, maxN)
	local out = {}
	for i = 1, maxN or 24 do
		local val, ok = upval(fn, i)
		if not ok then
			break
		end
		local entry = { i = i, typeof = typeof(val) }
		if type(val) == "table" then
			entry.Duration = rawget(val, "Duration")
			entry.Cells = rawget(val, "Cells")
			entry.Overshoot = rawget(val, "Overshoot")
		elseif type(val) == "function" then
			entry.fn = true
		end
		table.insert(out, entry)
	end
	return out
end

-- resolveParams = ClientRollModule:129 (0240:88): clones the default reel table,
-- scales Cells/Duration by getRollSpeedScale, clamps Duration to >= 0.25. That
-- clamp is the floor Fast cannot beat, so Instant patches the return value.
-- v1.2/v1.3 walked upvalues to find it and could not -- getgc identity can.
local function findResolveParams()
	local fn, why = gcFind(GC_TARGETS.resolveParams)
	if type(fn) ~= "function" then
		log("PROBE", "resolveParams_miss", {
			why = tostring(why),
			PlayRoll_uv = ClientRollModule and inspectUpvalues(ClientRollModule.PlayRoll, 16) or {},
		})
		return nil, tostring(why)
	end
	local okShape, out = pcall(fn, {})
	if not okShape or type(out) ~= "table" or type(out.Duration) ~= "number" then
		log("PROBE", "resolveParams_shape_bad", { ok = okShape, got = typeof(out) })
		return nil, "shape_bad"
	end
	log("PROBE", "resolveParams_found", { Duration = out.Duration, Cells = out.Cells })
	return fn, "ok"
end

local function installStayHook()
	if S.stayHooked then
		return true, "already"
	end
	if not (BoostUtility and type(BoostUtility.GetMultiplier) == "function" and hookfunction) then
		return false, "no_GetMultiplier"
	end
	local target = BoostUtility.GetMultiplier
	local old, err = safeHook(target, function(callOld)
		return function(player, stat)
			local v = callOld(player, stat)
			if S.alive and CFG.instant and stat == "RollSpeed" then
				-- getRevealStayTime: 1.3 - skill/150 - mult/5 → floor 0.1 (0019.lua:302)
				if type(v) == "number" then
					return math.max(v, 40)
				end
				return 40
			end
			return v
		end
	end)
	if not old then
		return false, err
	end
	S.stayHooked = true
	log("PROBE", "stay_hook_installed", {})
	return true, "ok"
end

local function installInstantResolveHook()
	if S.resolveParams and S.instantReady then
		return true, "already"
	end
	local cand, why = findResolveParams()
	if type(cand) ~= "function" then
		log("ERR", "resolveParams_missing", { why = tostring(why) })
		return false, tostring(why)
	end
	-- Prove pre-hook floor, then hook, prove patch
	local beforeOk, before = pcall(cand, {})
	log("PROBE", "resolveParams_before", {
		ok = beforeOk,
		Duration = beforeOk and before.Duration or tostring(before),
		Cells = beforeOk and before.Cells or nil,
	})
	local old, err = safeHook(cand, function(callOld)
		return function(params)
			local out = callOld(params)
			if not (S.alive and CFG.instant and type(out) == "table") then
				return out
			end
			out.Cells = 3
			-- Same server ceiling applies here. The game's AutoRoll cycle is
			-- task.wait(0.1) + getRevealStayTime() (0.1 with the stay hook) +
			-- this reel, so a reel shorter than 1/limit - 0.2 makes AutoRoll
			-- outrun Roll_ent/Roll_int and the surplus rolls are discarded --
			-- which is exactly what puts "?" cells on screen. Shortening the
			-- reel below that point buys nothing and costs rolls.
			local floor = 0.02
			if CFG.obeyLimit then
				floor = math.max(floor, 1 / S.rollLimitCached - 0.2)
			end
			out.Duration = math.max(floor, CFG.instantDuration)
			out.Overshoot = 0
			out.ReturnFraction = 0
			out.StartSpeed = 1
			out.SpinFraction = 0.05
			if S.patchLogLeft > 0 then
				S.patchLogLeft = S.patchLogLeft - 1
				log("INFO", "resolveParams_patched", { Duration = out.Duration, Cells = out.Cells })
			end
			return out
		end
	end)
	if not old then
		log("ERR", "resolveParams_hook_fail", { err = tostring(err) })
		return false, err
	end
	S.resolveParams = cand
	local afterOk, after = pcall(cand, {})
	local patched = afterOk and type(after) == "table" and after.Duration and after.Duration < 0.25
	-- Force CFG.instant true briefly for probe call through hook
	local was = CFG.instant
	CFG.instant = true
	afterOk, after = pcall(cand, {})
	CFG.instant = was
	patched = afterOk and type(after) == "table" and tonumber(after.Duration) and after.Duration < 0.24
	log("PROBE", "resolveParams_after", {
		ok = afterOk,
		Duration = afterOk and after.Duration or tostring(after),
		Cells = afterOk and after.Cells or nil,
		belowFloor = patched and true or false,
	})
	if not patched then
		log("ERR", "resolveParams_hook_ineffective", {})
		pcall(function()
			if restorefunction then
				restorefunction(cand)
			end
		end)
		for i = #S.hooks, 1, -1 do
			if S.hooks[i] == cand then
				table.remove(S.hooks, i)
			end
		end
		S.resolveParams = nil
		S.instantReady = false
		return false, "hook_ineffective"
	end
	S.resolveParams = cand
	S.instantReady = true
	log("PROBE", "resolveParams_hooked", { Duration = after.Duration })
	return true, "ok"
end

local function installObserveWraps()
	if not CFG.observe or not ClientRollModule then
		return
	end

	wrapField(ClientRollModule, "PlayRoll", function(old)
		return function(container, columns)
			S.rollSeq = S.rollSeq + 1
			local id = S.rollSeq
			local t0 = os.clock()
			S.stats.play = S.stats.play + 1
			local admin = workspace:GetAttribute("AdminRollSpeed")
			local dur = nil
			pcall(function()
				dur = ClientRollModule.GetRollDuration()
			end)
			log("ROLL", "PlayRoll_enter", {
				id = id,
				columns = columns,
				container = container and container:GetFullName() or "nil",
				AdminRollSpeed = tostring(admin),
				GetRollDuration = dur,
				fast = CFG.fast,
				instant = CFG.instant,
				RollingEnabled = ClientRollModule.RollingEnabled,
			})
			local ok, a = pcall(old, container, columns)
			local ms = (os.clock() - t0) * 1000
			S.stats.lastPlayMs = ms
			if not ok then
				S.stats.errors = S.stats.errors + 1
				log("ERR", "PlayRoll_error", { id = id, err = tostring(a), ms = string.format("%.1f", ms) })
				error(a)
			end
			log("ROLL", "PlayRoll_exit", { id = id, uid = tostring(a), ms = string.format("%.1f", ms) })
			return a
		end
	end)

	wrapField(ClientRollModule, "UpdateRollResult", function(old)
		return function(uid, results, rollData)
			S.stats.update = S.stats.update + 1
			local n = type(results) == "table" and #results or -1
			log("ROLL", "UpdateRollResult", {
				uid = tostring(uid),
				nResults = n,
				RealOdds = rollData and rollData.RealOdds,
				IsMeteor = rollData and rollData.IsMeteor,
				IsPowerRoll = rollData and rollData.IsPowerRoll,
			})
			return old(uid, results, rollData)
		end
	end)

	wrapField(ClientRollModule, "WaitForRollEnd", function(old)
		return function(...)
			local t0 = os.clock()
			S.stats.waitEnd = S.stats.waitEnd + 1
			log("ROLL", "WaitForRollEnd_enter", {})
			local ok, err = pcall(old, ...)
			local ms = (os.clock() - t0) * 1000
			S.stats.lastWaitMs = ms
			S.stats.waitMsSum = S.stats.waitMsSum + ms
			if ms > S.stats.waitMsMax then
				S.stats.waitMsMax = ms
			end
			if not ok then
				S.stats.errors = S.stats.errors + 1
				log("ERR", "WaitForRollEnd_error", { err = tostring(err), ms = string.format("%.1f", ms) })
				error(err)
			end
			log("ROLL", "WaitForRollEnd_exit", {
				ms = string.format("%.1f", ms),
				avgMs = S.stats.waitEnd > 0 and string.format("%.1f", S.stats.waitMsSum / S.stats.waitEnd) or "0",
				maxMs = string.format("%.1f", S.stats.waitMsMax),
			})
		end
	end)

	log("PROBE", "observe_wraps_installed", {})
end

local function listenAutoRollSignal()
	if not SignalModule then
		log("PROBE", "SignalModule_missing", {})
		return
	end
	local ok, sig = pcall(function()
		return SignalModule.Get("AutoRollToggled")
	end)
	if not ok or not sig then
		log("PROBE", "AutoRollToggled_missing", { err = tostring(sig) })
		return
	end
	bind(sig, function(on)
		S.stats.autoToggle = S.stats.autoToggle + 1
		log("ROLL", "AutoRollToggled", {
			on = on and true or false,
			fast = CFG.fast,
			instant = CFG.instant,
			AdminRollSpeed = tostring(workspace:GetAttribute("AdminRollSpeed")),
		})
	end)
	log("PROBE", "AutoRollToggled_listening", {})
end

local function snapshotEnv()
	local snap = {
		build = BUILD_VERSION,
		placeId = game.PlaceId,
		hookfunction = hookfunction ~= nil,
		restorefunction = restorefunction ~= nil,
		getupvalue = debug.getupvalue ~= nil,
		ClientRollModule = ClientRollModule ~= nil,
		RollingEnabled = ClientRollModule and ClientRollModule.RollingEnabled,
		AdminRollSpeed = workspace:GetAttribute("AdminRollSpeed"),
	}
	pcall(function()
		snap.executor = identifyexecutor and identifyexecutor() or "?"
	end)
	pcall(function()
		if client then
			client:waitForData()
			snap.Rolls = client:get("Rolls")
			snap.Money = client:get("Money")
			snap.TotalRolls = client:get("TotalRolls")
			snap.SettingsAutoRoll = client:get({ "Settings", "AutoRoll" })
		end
	end)
	pcall(function()
		if SkillsUtility then
			snap.skillRollSpeed = SkillsUtility.GetPowerForSkillSubtype(LocalPlayer, "RollSpeed")
			snap.skillAutoRollOwned = SkillsUtility.IsOwned(LocalPlayer, "AutoRoll")
		end
	end)
	pcall(function()
		if PaidUtility then
			snap.passFastRolls = PaidUtility.IsOwned(LocalPlayer, "FastRolls")
			snap.passExtraRoll = PaidUtility.IsOwned(LocalPlayer, "ExtraRoll")
		end
	end)
	pcall(function()
		if BoostUtility then
			snap.boostRollSpeed = BoostUtility.GetMultiplier(LocalPlayer, "RollSpeed")
		end
	end)
	pcall(function()
		if ClientRollModule and ClientRollModule.GetRollDuration then
			snap.GetRollDuration = ClientRollModule.GetRollDuration()
		end
	end)
	local pg = LocalPlayer:FindFirstChild("PlayerGui")
	if pg then
		local big = pg:FindFirstChild("BigRoller")
		snap.BigRollerEnabled = big and big.Enabled
	end
	return snap
end

local function probeAdminRollCurve()
	local prev = workspace:GetAttribute("AdminRollSpeed")
	local owned = S.adminOwned
	local curve = {}
	if not (ClientRollModule and ClientRollModule.GetRollDuration) then
		log("ERR", "probe_curve_no_GetRollDuration", {})
		return curve
	end
	local samples = { "nil", 1, 2, 4, 8, 12, 20, 40, 50 }
	for _, m in ipairs(samples) do
		if m == "nil" then
			workspace:SetAttribute("AdminRollSpeed", nil)
		else
			workspace:SetAttribute("AdminRollSpeed", m)
		end
		local ok, dur = pcall(function()
			return ClientRollModule.GetRollDuration()
		end)
		local row = { mult = m, ok = ok, duration = ok and dur or tostring(dur) }
		table.insert(curve, row)
		log("PROBE", "duration_curve", row)
	end
	if owned then
		applyAdminRollSpeed()
	else
		workspace:SetAttribute("AdminRollSpeed", prev)
	end
	return curve
end

local function runProbeSuite(reason)
	log("PROBE", "suite_begin", { reason = reason, build = BUILD_VERSION })
	local snap = snapshotEnv()
	log("PROBE", "env", snap)
	local curve = probeAdminRollCurve()
	local floorHit = false
	local best = nil
	for _, row in ipairs(curve) do
		if type(row.duration) == "number" then
			if not best or row.duration < best then
				best = row.duration
			end
			if row.duration <= 0.26 then
				floorHit = true
			end
		end
	end
	local rp, rpWhy = findResolveParams()
	log("PROBE", "resolveParams_scan", {
		found = type(rp) == "function",
		why = type(rp) == "function" and "ok" or tostring(rpWhy),
	})

	if PaidUtility and PaidUtility.IsOwned then
		local t0 = os.clock()
		local ok1, a = pcall(PaidUtility.IsOwned, PaidUtility, LocalPlayer, "FastRolls")
		local ok2, b = pcall(SkillsUtility and SkillsUtility.IsOwned, SkillsUtility, LocalPlayer, "AutoRoll")
		local ms = (os.clock() - t0) * 1000
		log("PROBE", "IsOwned_sanity", {
			ok1 = ok1,
			FastRolls = tostring(a),
			ok2 = ok2,
			AutoRoll = tostring(b),
			ms = string.format("%.2f", ms),
			suspect_recurse = ms > 50,
		})
	end

	local summary = string.format(
		"durMin=%.2f floor=%s rp=%s",
		tonumber(best) or -1,
		tostring(floorHit),
		type(rp) == "function" and "yes" or "no"
	)
	S.lastProbeSummary = summary
	uiMark()
	log("PROBE", "suite_end", { summary = summary, bestDuration = best, hits025Floor = floorHit })
	setStatus("probe done · " .. summary)
	return snap, curve
end

-- Turbo Roll -----------------------------------------------------------
-- The game's own AutoRoll (BottomFrameHandler driveAutoRoll:265) spends about
-- 1.4s per roll and almost none of it is the reel: task.wait(0.1) every
-- iteration plus getRevealStayTime() (:247), 1.1s at baseline skill. That is
-- ~0.7 rolls/s. performRoll (:180) is the part that actually rolls -- it
-- spawns PlayRoll and Roll:Invoke, then blocks in WaitForRollEnd -- so calling
-- it ourselves skips both waits.
--
-- The ceiling is NOT the client. Warp publishes every remote's limit as
-- attributes on its Reliable RemoteEvent (RateLimit.create, 0162:22):
-- Roll_ent = 4 per Roll_int = 1s. Past that the limiter drops the call, the
-- Invoke never answers, and the reel lands on the game's Awaiting placeholder
-- -- the "?" cell. A "?" is a roll that was thrown away, not a rare item.
-- Measured: 20 rolls fired in 3.7s credited 9. So Turbo paces at the published
-- limit, where every roll it fires is a roll that counts.
local ROLL_LIMIT_FALLBACK = 4

local function readRollLimit()
	if S.rollLimit then
		return S.rollLimit
	end
	local ok, cap = pcall(function()
		local ev = ReplicatedStorage.Modules.Core.Warp.Index.Event
		for _, child in ipairs(ev:GetChildren()) do
			local ent = child:GetAttribute("Roll_ent")
			local int = child:GetAttribute("Roll_int")
			if tonumber(ent) and tonumber(int) and tonumber(int) > 0 then
				return tonumber(ent) / tonumber(int)
			end
		end
		return nil
	end)
	S.rollLimit = (ok and cap) or ROLL_LIMIT_FALLBACK
	S.rollLimitCached = S.rollLimit
	log("INFO", "roll_limit", { perSec = S.rollLimit, read = ok and cap ~= nil })
	return S.rollLimit
end

local function resolvePerformRoll(reason)
	local fn, why = gcFind(GC_TARGETS.performRoll)
	if type(fn) ~= "function" then
		S.performRoll = nil
		log("ERR", "turbo_resolve", { reason = reason, err = tostring(why) })
		return false, tostring(why)
	end
	S.performRoll = fn
	readRollLimit()
	log("INFO", "turbo_resolve", { reason = reason, ok = true, limit = S.rollLimit })
	return true, nil
end

local function rollBalance()
	if not client then
		return nil
	end
	local ok, v = pcall(function()
		return client:get("Rolls")
	end)
	return ok and tonumber(v) or nil
end

-- Credited rate, from the server's own TotalRolls rather than from how many
-- calls we made -- the two differ whenever the limiter drops one.
local function sampleTurboRate(now)
	if not client then
		return
	end
	local ok, total = pcall(function()
		return client:get("TotalRolls")
	end)
	total = ok and tonumber(total) or nil
	if not total then
		return
	end
	if not S.turboLastTotal then
		S.turboLastTotal = total
		S.turboLastSample = now
		return
	end
	local dt = now - S.turboLastSample
	if dt >= 1 then
		S.turboRateLive = (total - S.turboLastTotal) / dt
		S.turboLastTotal = total
		S.turboLastSample = now
	end
end

local function startTurboLoop()
	task.spawn(function()
		local lastResolve = 0
		local lastHeartbeat = 0
		while S.alive do
			local now = os.clock()
			if not CFG.turbo then
				S.turboRateLive = 0
				S.turboInflight = 0
				S.turboLastTotal = nil
				task.wait(0.1)
			else
				if type(S.performRoll) ~= "function" and now - lastResolve > 1 then
					lastResolve = now
					resolvePerformRoll("loop")
				end
				local balance = rollBalance()
				local blocked = type(S.performRoll) ~= "function"
					or (ClientRollModule and ClientRollModule.RollingEnabled == false)
					or (balance ~= nil and balance <= 0)
				sampleTurboRate(now)
				if blocked then
					if now - lastHeartbeat > 2 then
						lastHeartbeat = now
						log("INFO", "turbo_hb", {
							blocked = true,
							balance = balance,
							found = type(S.performRoll) == "function",
						})
					end
					task.wait(0.15)
				else
					local cap = readRollLimit()
					local rate = CFG.obeyLimit and math.min(CFG.turboRate, cap) or CFG.turboRate
					rate = math.clamp(rate, 0.5, 20)
					-- One thread per roll, evenly spaced. Firing a batch inside one
					-- frame is what the limiter eats; spacing is what it accepts.
					-- performRoll does not return while ANY roll is active --
					-- WaitForRollEnd watches a global counter -- so a thread still
					-- sitting there is not a roll in progress and must never gate
					-- the next spawn. Gating on it collapsed the rate to 1/s.
					if S.turboInflight < 60 then
						S.turboInflight = S.turboInflight + 1
						task.spawn(function()
							local okR, err = pcall(S.performRoll)
							S.turboInflight = math.max(0, S.turboInflight - 1)
							if not okR then
								S.stats.errors = S.stats.errors + 1
								log("ERR", "turbo_roll", { err = tostring(err) })
							end
						end)
					end
					if now - lastHeartbeat > 2 then
						lastHeartbeat = now
						log("INFO", "turbo_hb", {
							rate = rate,
							cap = cap,
							credited = string.format("%.1f", S.turboRateLive),
							inflight = S.turboInflight,
							balance = balance,
						})
					end
					task.wait(1 / rate)
				end
			end
		end
	end)
end

-- Auto Unlock Skills ---------------------------------------------------
-- A node is purchasable exactly when TreeModule.createNode (0056:213) would
-- draw it as "Available": not owned, and either IsStartNode / IsAlwaysUnlocked
-- or some node in the SAME section that is owned (or is a start node) lists it
-- in Connections. Connections are directional, so the owned node must point at
-- the candidate, not the other way round.
-- Price is MoneyPrice against Money, else RollsPrice against Rolls (0056:151).
-- Buying is BuySkill:Invoke(8, name) -> true on success (0053:104).
local function skillShim()
	if S.skillShim then
		return S.skillShim
	end
	if type(loadstring) ~= "function" then
		return nil
	end
	-- Warp.Invoke greps debug.traceback() for "Replicated" or the player name
	-- (0149:61) and rejects anything else, so the call has to come from a chunk
	-- whose name satisfies that grep.
	local ok, factory = pcall(loadstring, "return function(r, n) return r:Invoke(8, n) end", "ReplicatedStorage.BabHub.Skills")
	if not ok or type(factory) ~= "function" then
		return nil
	end
	local ok2, fn = pcall(factory)
	if not ok2 or type(fn) ~= "function" then
		return nil
	end
	S.skillShim = fn
	return fn
end

local function skillRemotes()
	if type(S.skillRemotes) == "table" then
		return S.skillRemotes
	end
	if type(getgc) ~= "function" then
		return nil
	end
	local okGc, gc = pcall(getgc, true)
	if not okGc or type(gc) ~= "table" then
		return nil
	end
	for _, v in ipairs(gc) do
		if type(v) == "table" then
			local hit = false
			pcall(function()
				hit = rawget(v, "BuySkill") ~= nil and rawget(v, "SkillPurchased") ~= nil
			end)
			if hit then
				S.skillRemotes = v
				return v
			end
		end
	end
	return nil
end

local function walletFor(cfg)
	if cfg.MoneyPrice then
		return "Money", cfg.MoneyPrice, CFG.keepMoney
	end
	if cfg.RollsPrice then
		return "Rolls", cfg.RollsPrice, 0
	end
	return nil, 0, 0
end

-- Returns the affordable frontier, cheapest first.
local function planSkills()
	if not (SkillsUtility and client) then
		return {}, "no_skills_module"
	end
	local okAll, all = pcall(SkillsUtility.GetAll)
	if not okAll or type(all) ~= "table" then
		return {}, "no_config"
	end
	local ownedSet = {}
	pcall(function()
		for _, name in ipairs(SkillsUtility.GetAllOwned(LocalPlayer)) do
			ownedSet[name] = true
		end
	end)
	local money = tonumber(client:get("Money")) or 0
	local rolls = tonumber(client:get("Rolls")) or 0
	local plan = {}
	for name in pairs(all) do
		if not ownedSet[name] then
			local cfg = SkillsUtility.GetConfig(name)
			if type(cfg) == "table" and not cfg.SectionLink then
				local reachable = cfg.IsStartNode or cfg.IsAlwaysUnlocked or false
				if not reachable then
					local section = SkillsUtility.GetAllFromSection(cfg.Section)
					if type(section) == "table" then
						for otherName, other in pairs(section) do
							if (ownedSet[otherName] or other.IsStartNode) and type(other.Connections) == "table" then
								for _, linked in pairs(other.Connections) do
									if linked == name then
										reachable = true
										break
									end
								end
							end
							if reachable then
								break
							end
						end
					end
				end
				if reachable then
					local wallet, price, reserve = walletFor(cfg)
					local have = wallet == "Rolls" and rolls or money
					local canPay = wallet == nil
						or (have - price >= reserve and (wallet ~= "Rolls" or CFG.spendRolls))
					if canPay then
						table.insert(plan, {
							name = name,
							price = price,
							wallet = wallet or "free",
							section = cfg.Section,
						})
					end
				end
			end
		end
	end
	table.sort(plan, function(a, b)
		return a.price < b.price
	end)
	return plan, "ok"
end

local function buySkill(name)
	local remotes = skillRemotes()
	local shim = skillShim()
	if not remotes or not shim then
		return false, "no_buy_path"
	end
	local ok, res = pcall(shim, remotes.BuySkill, name)
	if not ok then
		return false, tostring(res)
	end
	return res and true or false, nil
end

-- One pass over the affordable frontier. Buying a node opens its neighbours,
-- so re-plan after each success instead of trusting the first snapshot.
local function unlockAffordable(reason, maxBuys)
	local bought, spent = 0, 0
	local limit = maxBuys or 40
	for _ = 1, limit do
		local plan = planSkills()
		local pick = plan[1]
		if not pick then
			break
		end
		local ok, err = buySkill(pick.name)
		if not ok then
			log("ERR", "skill_buy", { skill = pick.name, err = tostring(err), price = pick.price })
			break
		end
		bought = bought + 1
		spent = spent + (pick.price or 0)
		S.skillsBought = S.skillsBought + 1
		S.skillSpent = S.skillSpent + (pick.price or 0)
		S.lastSkill = pick.name
		log("INFO", "skill_bought", {
			skill = pick.name,
			price = pick.price,
			wallet = pick.wallet,
			section = pick.section,
			reason = reason,
		})
		uiMark()
		task.wait(0.25)
	end
	if bought > 0 then
		setStatus(string.format("Unlocked %d skill%s (%s spent) - last %s", bought, bought == 1 and "" or "s", tostring(spent), S.lastSkill))
	elseif reason == "manual" then
		setStatus("No skill is both reachable and affordable right now")
	end
	return bought, spent
end

local function startSkillLoop()
	task.spawn(function()
		local lastHeartbeat = 0
		while S.alive do
			if not CFG.autoSkills then
				task.wait(0.5)
			else
				local bought = unlockAffordable("auto", 6)
				local now = os.clock()
				if bought == 0 and now - lastHeartbeat > 30 then
					lastHeartbeat = now
					log("INFO", "skill_hb", {
						bought = S.skillsBought,
						spent = S.skillSpent,
						keepMoney = CFG.keepMoney,
						spendRolls = CFG.spendRolls,
					})
				end
				task.wait(bought > 0 and 0.5 or 3)
			end
		end
	end)
end

local function applyMode()
	if not S.alive then
		return
	end
	if CFG.instant then
		CFG.fast = true
		applyAdminRollSpeed()
		S.patchLogLeft = 8
		local okResolve, whyResolve = installInstantResolveHook()
		local okStay, whyStay = installStayHook()
		if okResolve then
			S.instantReady = true
			setStatus(string.format(
				"INSTANT · dur %.2fs · stay=%s",
				CFG.instantDuration,
				okStay and "on" or tostring(whyStay)
			))
		else
			-- backup: Fast only
			CFG.instant = false
			S.instantReady = false
			applyAdminRollSpeed()
			setStatus("Instant failed (" .. tostring(whyResolve) .. ") · FAST backup")
			log("ERR", "instant_fallback_fast", { why = tostring(whyResolve) })
		end
	elseif CFG.fast then
		applyAdminRollSpeed()
		setStatus(string.format("FAST · AdminRoll x%d (floor~0.25s)", CFG.fastMult))
	else
		applyAdminRollSpeed()
		setStatus("native speed · observe on")
	end
	log("INFO", "mode", {
		fast = CFG.fast,
		instant = CFG.instant,
		instantReady = S.instantReady,
		autoSkills = CFG.autoSkills,
		skillsBought = S.skillsBought,
		skillSpent = S.skillSpent,
		lastSkill = S.lastSkill,
		mult = CFG.fastMult,
		AdminRollSpeed = tostring(workspace:GetAttribute("AdminRollSpeed")),
	})
end

local function applyModeDebounced()
	S.applyToken = S.applyToken + 1
	local token = S.applyToken
	task.delay(0.08, function()
		if S.alive and token == S.applyToken then
			applyMode()
		end
	end)
end

local function destroy()
	log("INFO", "destroy_begin", { build = BUILD_VERSION, stats = S.stats })
	S.alive = false
	CFG.fast = false
	CFG.instant = false
	CFG.autoSwing = false
	CFG.overdrive = false
	CFG.turbo = false
	CFG.autoSkills = false
	pcall(restoreSwingGate)
	pcall(applyAdminRollSpeed)
	pcall(restoreAll)
	for _, c in ipairs(S.connections) do
		pcall(function()
			c:Disconnect()
		end)
	end
	table.clear(S.connections)
	if S.guiDestroy then
		pcall(S.guiDestroy)
	end
	S.frame = nil
	G[GKEY] = nil
	log("INFO", "destroy_end", { build = BUILD_VERSION })
end

S.destroy = destroy
S.cfg = CFG
-- Scripted control, same path the GUI takes. Used to verify a build without
-- asking the user to click through it.
S.set = function(key, value)
	if CFG[key] == nil and value == nil then
		return false, "unknown key"
	end
	CFG[key] = value
	if key == "turbo" and value then
		resolvePerformRoll("api")
	elseif key == "autoSwing" and value then
		resolveNativeAttack("api")
	end
	uiMark()
	pcall(applyMode)
	log("INFO", "api_set", { key = tostring(key), value = tostring(value) })
	return true
end
S.stat = function()
	return {
		build = BUILD_VERSION,
		turbo = CFG.turbo,
		turboRate = CFG.turboRate,
		rollLimit = S.rollLimit,
		rollsPerSec = S.turboRateLive,
		inflight = S.turboInflight,
		autoSwing = CFG.autoSwing,
		swingsPerSec = S.swingRateLive,
		swings = S.stats.swings,
		instant = CFG.instant,
		instantReady = S.instantReady,
		autoSkills = CFG.autoSkills,
		skillsBought = S.skillsBought,
		skillSpent = S.skillSpent,
		lastSkill = S.lastSkill,
	}
end
S.runProbe = function()
	return runProbeSuite("manual")
end
S.dumpRing = function()
	ensureLogDir()
	pcall(function()
		writefile("logs/bab_hub_ring.txt", table.concat(LogRing))
	end)
	log("INFO", "ring_dumped", { n = #LogRing })
end
G[GKEY] = S

local HOST = (type(G.__R3ST_HOST) == "table" and typeof(G.__R3ST_HOST.host) == "Instance"
	and G.__R3ST_HOST.host.Parent ~= nil) and G.__R3ST_HOST or nil
local KIT_PATHS = { "../scripts/r3st_ui.lua", "r3st_ui.lua", "scripts/r3st_ui.lua" }

local function loadKit()
	if HOST and type(HOST.ui) == "table" then
		log("INFO", "ui_kit", { version = HOST.ui.VERSION, path = "host" })
		return HOST.ui
	end
	for _, path in ipairs(KIT_PATHS) do
		local ok, src = pcall(readfile, path)
		if ok and type(src) == "string" and #src > 0 then
			local chunk = loadstring(src, "=r3st_ui.lua")
			if type(chunk) == "function" then
				local ran, kit = pcall(chunk)
				if ran and type(kit) == "table" then
					log("INFO", "ui_kit", { version = kit.VERSION, path = path, bytes = #src })
					return kit
				end
			end
		end
	end
	return nil
end

local function buildGui()
	local Kit = loadKit()
	if not Kit then
		log("ERR", "ui_kit_missing", { paths = table.concat(KIT_PATHS, " | ") })
		return false
	end
	local COL = Kit.COL
	local screen
	local panel = Instance.new("Frame")
	panel.Name = "BuildABaseRNGPanel"
	panel.BackgroundColor3 = HOST and COL.bg or COL.panel
	panel.BackgroundTransparency = HOST and 1 or 0
	panel.BorderSizePixel = 0
	panel.Active = true
	panel.Visible = true
	if HOST then
		panel.Size = UDim2.fromScale(1, 1)
		panel.Parent = HOST.host
	else
		local parent = LocalPlayer:WaitForChild("PlayerGui")
		screen = Instance.new("ScreenGui")
		screen.Name = "R3ST_BAB_" .. tostring(math.random(1000, 9999))
		screen.ResetOnSpawn = false
		screen.IgnoreGuiInset = true
		screen.ZIndexBehavior = Enum.ZIndexBehavior.Global
		screen.DisplayOrder = 130
		screen.Parent = parent
		panel.Size = UDim2.fromOffset(780, 590)
		panel.Position = UDim2.new(0.5, -390, 0.5, -295)
		panel.Parent = screen
		Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 12)
		local border = Instance.new("UIStroke", panel)
		border.Color = COL.line
	end

	local hostState = Kit.host({ root = panel, screen = screen })
	local inner = Instance.new("Frame")
	inner.Name = "Content"
	inner.BackgroundTransparency = 1
	inner.BorderSizePixel = 0
	inner.Position = UDim2.fromOffset(HOST and 12 or 18, HOST and 8 or 14)
	inner.Size = UDim2.new(1, HOST and -24 or -36, 1, HOST and -16 or -28)
	inner.Parent = panel

	local W = Kit.bind({ live = UI.painters, conns = S.connections })
	local tabs = { "Combat", "Skills", "Rolls", "Diagnostics" }
	local pages = {}
	local activeTab = "Combat"
	local repaintTabs
	local function setTab(name)
		if not pages[name] then name = "Combat" end
		activeTab = name
		for tab, page in pairs(pages) do page.Visible = tab == name end
	end

	W.header(inner, {
		title = "Build a Base RNG",
		version = BUILD_VERSION,
		subtitle = "Wave combat, skill purchasing and paced roll utilities.",
		gameId = EXPECTED_GAME,
		placeId = EXPECTED_PLACE,
		onInfo = function() setTab("Diagnostics"); if repaintTabs then repaintTabs() end end,
	})
	local _tabstrip
	_tabstrip, repaintTabs = W.tabstrip(inner, {
		names = tabs,
		position = UDim2.fromOffset(0, 80),
		get = function() return activeTab end,
		set = setTab,
	})

	local BODY_Y = 122
	local function pageWidth()
		local width = inner.AbsoluteSize.X
		if width < 200 then width = 744 end
		return width - 10
	end
	for _, name in ipairs(tabs) do
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

	local combat = pages.Combat
	W.section(combat, "Auto swing")
	W.note(combat, "Uses the game's own Attack during a wave. Without Overdrive, the weapon cooldown remains authoritative (~7/s).")
	W.toggle(combat, {
		label = "Auto swing", desc = "Stock attack path; reach remains about 11 studs",
		get = function() return CFG.autoSwing end,
		set = function(v)
			CFG.autoSwing = v and true or false
			if CFG.autoSwing then resolveNativeAttack("toggle_on") else restoreSwingGate() end
			local cd = getWeaponCooldown()
			log("INFO", "auto_swing", { on = CFG.autoSwing, cd = cd, method = S.swingMethod,
				native = type(S.nativeAttack) == "function", rate = CFG.swingRate, overdrive = CFG.overdrive,
				wave = (S.ClientBuildModule and S.ClientBuildModule.WaveActive) and true or false })
			if not CFG.autoSwing then setStatus("Auto Swing OFF")
			elseif type(S.nativeAttack) ~= "function" then setStatus("Auto Swing ON · Attack NOT FOUND · run probe")
			else setStatus(string.format("Auto Swing ON · %.0f/s target · cap %.1f/s · od=%s",
				CFG.swingRate, 1 / cd, CFG.overdrive and "on" or "off")) end
		end,
	})
	W.slider(combat, { label = "Swing rate", min = 1, max = 40, step = 1,
		get = function() return CFG.swingRate end,
		set = function(v) CFG.swingRate = math.floor(v + 0.5) end,
		fmt = function(v) return string.format("%.0f/s", v) end,
		tradeoff = "Above the native cap requires Overdrive and is visible to nearby players." })
	W.toggle(combat, {
		label = "Overdrive", desc = "Ignore the weapon cooldown; intentionally boots OFF",
		get = function() return CFG.overdrive end,
		set = function(v)
			CFG.overdrive = v and true or false
			if not CFG.overdrive then restoreSwingGate() end
			log("INFO", "overdrive", { on = CFG.overdrive, setupvalue = type(debug.setupvalue) == "function", cap = nativeRateCap() })
			setStatus(CFG.overdrive and "Overdrive ON · client cooldown gate cleared per swing"
				or string.format("Overdrive OFF · capped at %.1f/s", nativeRateCap()))
		end,
	})
	W.section(combat, "Live combat")
	W.statusRow(combat, function()
		local wave = (S.ClientBuildModule and S.ClientBuildModule.WaveActive) and "wave active" or "no wave"
		return string.format("%s · swing %d/s · %d accepted", wave, S.swingRateLive, S.stats.swings)
	end)

	local skills = pages.Skills
	W.section(skills, "Auto unlock")
	W.note(skills, "Buys the cheapest reachable skill you can afford, then re-plans as each purchase opens neighbours.")
	W.toggle(skills, {
		label = "Auto unlock skills", desc = "Money skills only unless roll spending is enabled",
		get = function() return CFG.autoSkills end,
		set = function(v)
			CFG.autoSkills = v and true or false
			if CFG.autoSkills then local plan = planSkills(); setStatus(string.format("Auto Unlock ON - %d affordable now", #plan))
			else setStatus("Auto Unlock OFF") end
			log("INFO", "auto_skills", { on = CFG.autoSkills, keepMoney = CFG.keepMoney, spendRolls = CFG.spendRolls })
		end,
	})
	W.slider(skills, { label = "Keep money", min = 0, max = 2000000, step = 10000,
		get = function() return CFG.keepMoney end,
		set = function(v) CFG.keepMoney = math.floor(v / 10000 + 0.5) * 10000 end,
		fmt = function(v) return string.format("%.0fk reserve", v / 1000) end })
	W.toggle(skills, {
		label = "Spend rolls on skills", desc = "Allow roll-priced nodes in addition to money nodes",
		get = function() return CFG.spendRolls end,
		set = function(v) CFG.spendRolls = v and true or false; setStatus(CFG.spendRolls
			and "Rolls may be spent on skills" or "Rolls reserved for rolling") end,
	})
	W.button(skills, "Unlock affordable now", "One pass over the current affordable frontier", function()
		task.spawn(function() unlockAffordable("manual", 40) end)
	end, true)
	W.section(skills, "Session purchases")
	W.statusRow(skills, function()
		return string.format("%d bought · %s spent · last %s", S.skillsBought, tostring(S.skillSpent), S.lastSkill)
	end)

	local rolls = pages.Rolls
	W.section(rolls, "Turbo roll")
	W.note(rolls, "Skips the stock loop and reveal wait. The published server limit is 4 rolls/s; calls beyond it are discarded and show a ? cell.")
	W.toggle(rolls, {
		label = "Turbo roll", desc = "Turn the game's own AutoRoll OFF while using this",
		get = function() return CFG.turbo end,
		set = function(v)
			CFG.turbo = v and true or false
			if CFG.turbo then
				local okT, why = resolvePerformRoll("toggle_on")
				if not okT then CFG.turbo = false; setStatus("Turbo failed: " .. tostring(why)); return end
				if not CFG.instant then CFG.instant = true; CFG.fast = true; applyMode() end
				local cap = tonumber(readRollLimit()) or ROLL_LIMIT_FALLBACK
				setStatus(string.format("TURBO ON · %.1f/s · server cap %.0f/s", math.min(CFG.turboRate, cap), cap))
			else setStatus("Turbo OFF") end
			log("INFO", "turbo", { on = CFG.turbo, rate = CFG.turboRate, cap = S.rollLimit, instant = CFG.instant })
		end,
	})
	W.slider(rolls, { label = "Turbo rate", min = 1, max = 10, step = 0.5,
		get = function() return CFG.turboRate end,
		set = function(v) CFG.turboRate = math.floor(v * 2 + 0.5) / 2 end,
		fmt = function(v) return string.format("%.1f/s", v) end })
	W.toggle(rolls, {
		label = "Obey server roll limit", desc = "Recommended; excess rolls are discarded",
		get = function() return CFG.obeyLimit end,
		set = function(v)
			CFG.obeyLimit = v and true or false
			local cap = tonumber(readRollLimit()) or ROLL_LIMIT_FALLBACK
			setStatus(CFG.obeyLimit and string.format("Capped at the game's own limit (%.0f rolls/s)", cap)
				or "Uncapped - rolls past the limit are DISCARDED and land on ?")
		end,
	})
	W.section(rolls, "Reel speed")
	W.toggle(rolls, {
		label = "Fast roll", desc = "AdminRollSpeed path; keeps the game's 0.25s reel floor",
		get = function() return CFG.fast and not CFG.instant end,
		set = function(v)
			CFG.fast = v and true or false
			CFG.instant = false
			applyMode()
		end,
	})
	W.toggle(rolls, {
		label = "Instant roll", desc = "Patches below the 0.25s floor and minimizes reveal stay",
		get = function() return CFG.instant end,
		set = function(v)
			CFG.instant = v and true or false
			if v then CFG.fast = true end
			applyMode()
		end,
	})
	W.slider(rolls, { label = "Fast multiplier", min = 2, max = 50, step = 1,
		get = function() return CFG.fastMult end,
		set = function(v) CFG.fastMult = math.floor(v + 0.5); applyModeDebounced() end,
		fmt = function(v) return "x" .. tostring(math.floor(v + 0.5)) end })
	W.slider(rolls, { label = "Instant duration", min = 0.02, max = 0.25, step = 0.01,
		get = function() return CFG.instantDuration end,
		set = function(v) CFG.instantDuration = math.floor(v * 100 + 0.5) / 100; applyModeDebounced() end,
		fmt = function(v) return string.format("%.2fs", v) end })
	W.section(rolls, "Live rolls")
	W.statusRow(rolls, function()
		local balance = rollBalance()
		return string.format("Rolls %s · %.1f credited/s · %d waiting", tostring(balance or "?"), S.turboRateLive, S.turboInflight)
	end)

	local diagnostics = pages.Diagnostics
	W.section(diagnostics, "Runtime")
	W.statusRow(diagnostics, function() return S.status end)
	W.statusRow(diagnostics, function() return S.statsText or "Waiting for first stats sample" end)
	W.statusRow(diagnostics, function() return "Probe: " .. S.lastProbeSummary end)
	W.section(diagnostics, "Actions")
	W.button(diagnostics, "Run probe suite", "Re-check live resolver identities and roll timing", function()
		task.spawn(function() runProbeSuite("gui") end)
	end, true)
	W.button(diagnostics, "Dump log ring", "Write the in-memory diagnostic ring to logs/bab_hub_ring.txt", function()
		S.dumpRing(); setStatus("ring dumped (" .. tostring(#LogRing) .. " lines)")
	end, true)
	W.button(diagnostics, "Flush stats snapshot", "Append current counters to bab_hub.log", function()
		log("PROBE", "stats_snapshot", S.stats)
		setStatus(string.format("plays=%d waits=%d lastWait=%.0fms err=%d",
			S.stats.play, S.stats.waitEnd, S.stats.lastWaitMs, S.stats.errors))
	end, true)
	W.section(diagnostics, "Safety")
	W.note(diagnostics, "All action toggles boot OFF every session. Auto swing and skill/roll actions use the game's own client paths; server-visible calls remain rate-limited unless you explicitly disable the limit.")

	for _, page in pairs(pages) do
		page.CanvasSize = UDim2.fromOffset(0, W.height(page) + 12)
	end
	W.footer(inner, {
		onUnload = destroy,
		onSettings = function() setTab("Diagnostics"); if repaintTabs then repaintTabs() end end,
		hint = HOST and "K unload · the hub owns the window and RightShift" or "K unload · RightShift panel",
	})
	setTab(activeTab)

	bind(inner:GetPropertyChangedSignal("AbsoluteSize"), function()
		task.defer(function()
			if not S.alive then return end
			for _, page in pairs(pages) do
				page.CanvasSize = UDim2.fromOffset(0, W.relayout(page, pageWidth()) + 12)
			end
		end)
	end)

	S.frame = panel
	S.screenGui = screen
	S.guiVisible = true
	S.hosted = hostState.hosted
	S.guiDestroy = function()
		pcall(function()
			ContextActionService:UnbindAction("BabHub_ToggleGui")
			ContextActionService:UnbindAction("BabHub_Unload")
		end)
		if screen then screen:Destroy() elseif panel.Parent then panel:Destroy() end
	end
	return true
end

local function toggleGui(force)
	if not S.frame then
		return
	end
	local now = os.clock()
	if force == nil and S._lastToggleAt and (now - S._lastToggleAt) < 0.18 then
		return
	end
	S._lastToggleAt = now
	if force == nil then
		S.guiVisible = not S.guiVisible
	else
		S.guiVisible = force and true or false
	end
	uiMark()
	log("INFO", "gui_toggle", { visible = S.guiVisible })
end

local function refreshStats()
	local ok, text = pcall(function()
		local rolls = client and (client:get("Rolls") or "?") or "?"
		local dur = ClientRollModule and ClientRollModule.GetRollDuration and ClientRollModule.GetRollDuration() or -1
		local admin = workspace:GetAttribute("AdminRollSpeed")
		local wave = (S.ClientBuildModule and S.ClientBuildModule.WaveActive) and "wave" or "no wave"
		return string.format(
			"Rolls %s · reel~%.2fs · Admin %s\nroll %.1f/s (%d busy) · swing %d/s · %s\nskills +%d · last %s",
			tostring(rolls),
			tonumber(dur) or 0,
			tostring(admin or "nil"),
			S.turboRateLive,
			S.turboInflight,
			S.swingRateLive,
			wave,
			S.skillsBought,
			S.lastSkill
		)
	end)
	if ok then
		S.statsText = text
	end
end

log("INFO", "boot", {
	build = BUILD_VERSION,
	place = game.PlaceId,
	buildMod = S.ClientBuildModule ~= nil,
	weaponsCfg = S.WeaponsConfig ~= nil,
	getconnections = type(getconnections) == "function",
	getgc = type(getgc) == "function",
	setupvalue = type(debug.setupvalue) == "function",
})
startUiPump()
installObserveWraps()
listenAutoRollSignal()
resolveNativeAttack("boot")
startAutoSwingLoop()
startTurboLoop()
startSkillLoop()
readRollLimit()
buildGui()
setStatus("v1.8.0 ready · all action toggles OFF")

if CFG.probeOnBoot then
	task.defer(function()
		task.wait(0.4)
		if S.alive then
			runProbeSuite("boot")
		end
	end)
end

bind(UserInputService.InputBegan, function(input, gp)
	-- Embedded, RightShift belongs to the hub. Standalone keeps the old hide key.
	if input.KeyCode == Enum.KeyCode.RightShift then
		if not S.hosted then toggleGui() end
	elseif input.KeyCode == Enum.KeyCode.K and not gp then
		destroy()
	end
end)

-- High priority CAS is standalone-only; binding it while hosted would eat the
-- hub's own RightShift before the shell can hide.
if not S.hosted then
	pcall(function()
		ContextActionService:BindActionAtPriority("BabHub_ToggleGui", function(_, state)
			if state == Enum.UserInputState.Begin then
				toggleGui()
				return Enum.ContextActionResult.Sink
			end
			return Enum.ContextActionResult.Pass
		end, false, 4000, Enum.KeyCode.RightShift)

		ContextActionService:BindActionAtPriority("BabHub_Unload", function(_, state)
			if state == Enum.UserInputState.Begin then
				destroy()
				return Enum.ContextActionResult.Sink
			end
			return Enum.ContextActionResult.Pass
		end, false, 4000, Enum.KeyCode.K)
	end)
end

log("PROBE", "hotkeys_bound", { RightShift = not S.hosted, K = true, cas = not S.hosted, hosted = S.hosted })

task.spawn(function()
	pcall(function()
		if client then
			client:waitForData()
		end
	end)
	while S.alive do
		refreshStats()
		task.wait(0.8)
	end
end)
