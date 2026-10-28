--------------------------------------------------------------------------
-- Counter Blox ESP v2026-10-24.1 (2026-10-24) — PlaceId 301549746
-- Changelog:
--   2026-10-24.1  Embed existing controls in the kit shell; persist module settings.
-- Port of onetap_esp.lua (same UX/presets/Drawing stack) adapted to CB dump
-- 2026-08-11T13-56-30Z.
--
-- Re-inject safe: self-teardown on load; K = unload
-- UNLOADS_ON_INJECT: __CB_ESP
--
-- ESP only. No aim, movement, remotes, hooks, part Size, map unlock, noclip.
--
-- AC (dump Client 0006): map lock kick, StrafingNoPhysics kick, blood Size→Rem3.
--   No Highlight/Billboard scanners. No getfenv/hookfunction.
-- Policy: gethui + Adornee only; Drawing when available; never parent into enemy;
--   never touch BasePart.Size / CanCollide / map Descendants.
--
-- Targets (0042 / 0044 / Status folder):
--   Players.<P>.Status.Alive == true
--   Status.Team in {T, CT}, ~= LocalPlayer.Status.Team
--   deathmatch (RS.gametype) → all non-self alive
--   Char = Workspace.<Name> / Player.Character  (R15 + HeadHB)
--   HP = Humanoid.Health
--   Weapon = Gun @GunName or EquippedTool.Value
--
-- RightShift = toggle panel | K = unload
-- Execute: loadfile("counterblox_esp.lua")()  or run this file in Potassium
--------------------------------------------------------------------------

local BUILD_VERSION = "2026-10-24.1"
if game.GameId ~= 115797356 and game.PlaceId ~= 301549746 then
	error("[CB_ESP] wrong place " .. tostring(game.PlaceId) .. " (need 301549746)", 0)
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local LP = Players.LocalPlayer
local Camera = Workspace.CurrentCamera
local RNG = Random.new()
local PLACE_ID = 301549746

local GENV = (getgenv and getgenv()) or _G
if type(GENV) ~= "table" then
	GENV = _G
end

local GKEY = "__CB_ESP"
local HOST = GENV.__R3ST_HOST
if GENV[GKEY] and type(GENV[GKEY].destroy) == "function" then
	pcall(GENV[GKEY].destroy)
end

local Log
do
	local ok, mod = pcall(function()
		return loadfile("log.lua")()
	end)
	if ok and type(mod) == "function" then
		Log = mod("counterblox_esp")
	else
		local buf = {}
		Log = {
			session = function(m)
				table.insert(buf, "[session] " .. tostring(m))
				pcall(writefile, "logs/counterblox_esp.log", table.concat(buf, "\n") .. "\n")
			end,
			step = function(m)
				table.insert(buf, "[step] " .. tostring(m))
				pcall(writefile, "logs/counterblox_esp.log", table.concat(buf, "\n") .. "\n")
			end,
			info = function(m)
				table.insert(buf, "[info] " .. tostring(m))
				pcall(writefile, "logs/counterblox_esp.log", table.concat(buf, "\n") .. "\n")
			end,
			warn = function(m)
				table.insert(buf, "[warn] " .. tostring(m))
				pcall(writefile, "logs/counterblox_esp.log", table.concat(buf, "\n") .. "\n")
			end,
			err = function(m, e)
				table.insert(buf, "[err] " .. tostring(m) .. " " .. tostring(e))
				pcall(writefile, "logs/counterblox_esp.log", table.concat(buf, "\n") .. "\n")
			end,
		}
	end
end

Log.session(string.format("boot build=%s place=%s expect=%s",
	BUILD_VERSION, tostring(game.PlaceId), tostring(PLACE_ID)))

local CB = {}
GENV[GKEY] = CB

local DEFAULTS = {
	Chams = true,
	InfoHud = true,
	Skeleton = true,
	Box = true,
	Snaplines = true,
	Offscreen = true,
	CombatFlash = true,
	TeamColors = true,
	EspHz = 0.05,
	MaxDist = 900,
	UiVisible = true,
	Preset = "Radar",
}

if type(CB.CFG) ~= "table" then
	CB.CFG = {}
end
for k, v in pairs(DEFAULTS) do
	if CB.CFG[k] == nil then
		CB.CFG[k] = v
	end
end
local CFG = CB.CFG
local CONFIG_FILE = "counterblox_esp_config.json"
local HttpService = game:GetService("HttpService")
local Shell

local function saveConfig()
	-- Kit autosave may wake after unload/reinject; only the current owner may write.
	if GENV[GKEY] ~= CB or CB.closed then return end
	local data = {}
	for key in pairs(DEFAULTS) do data[key] = CFG[key] end
	local ok, err = pcall(function()
		writefile(CONFIG_FILE, HttpService:JSONEncode(data))
	end)
	if not ok then Log.warn("config save: " .. tostring(err)) end
end

local function loadConfig()
	local ok, data = pcall(function()
		return HttpService:JSONDecode(readfile(CONFIG_FILE))
	end)
	if not ok or type(data) ~= "table" then return end
	for key, default in pairs(DEFAULTS) do
		local value = data[key]
		local valid = type(value) == type(default)
		if type(default) == "number" then
			valid = valid and value > 0 and value < math.huge
		elseif key == "Preset" then
			valid = value == "Legit" or value == "Duel" or value == "Radar" or value == "Ghost"
		end
		if valid then CFG[key] = value end
	end
end

local S = {
	alive = true,
	gui = nil,
	root = nil,
	folder = nil,
	esp = {},
	draw = {},
	hb = nil,
	input = nil,
	playerAdded = nil,
	charConns = {},
	statusConns = {},
	acc = 0,
}

local COL = {
	bg = Color3.fromRGB(10, 10, 12),
	stroke = Color3.fromRGB(32, 32, 36),
	text = Color3.fromRGB(235, 235, 240),
	dim = Color3.fromRGB(140, 140, 148),
	on = Color3.fromRGB(60, 180, 90),
	off = Color3.fromRGB(48, 48, 54),
	fill = Color3.fromRGB(255, 1, 1),
	outline = Color3.fromRGB(255, 80, 80),
	tFill = Color3.fromRGB(230, 190, 40),
	tOut = Color3.fromRGB(255, 230, 120),
	ctFill = Color3.fromRGB(60, 120, 220),
	ctOut = Color3.fromRGB(160, 200, 255),
	hpHi = Color3.fromRGB(70, 210, 90),
	hpLo = Color3.fromRGB(210, 60, 60),
	box = Color3.fromRGB(255, 200, 200),
	skel = Color3.fromRGB(255, 230, 230),
	snap = Color3.fromRGB(255, 120, 120),
	arrow = Color3.fromRGB(255, 180, 60),
	flash = Color3.fromRGB(255, 220, 80),
}

-- R15 bone pairs (dump characters.txt: Head / UpperTorso / HRP + limbs)
local R15_BONES = {
	{ "Head", "UpperTorso" },
	{ "UpperTorso", "LowerTorso" },
	{ "LowerTorso", "HumanoidRootPart" },
	{ "UpperTorso", "LeftUpperArm" },
	{ "LeftUpperArm", "LeftLowerArm" },
	{ "LeftLowerArm", "LeftHand" },
	{ "UpperTorso", "RightUpperArm" },
	{ "RightUpperArm", "RightLowerArm" },
	{ "RightLowerArm", "RightHand" },
	{ "LowerTorso", "LeftUpperLeg" },
	{ "LeftUpperLeg", "LeftLowerLeg" },
	{ "LeftLowerLeg", "LeftFoot" },
	{ "LowerTorso", "RightUpperLeg" },
	{ "RightUpperLeg", "RightLowerLeg" },
	{ "RightLowerLeg", "RightFoot" },
}

local HAS_DRAWING = typeof(Drawing) == "table" or typeof(Drawing) == "userdata"

local function blandName(prefix)
	return prefix .. string.format("%04x", RNG:NextInteger(0, 65535))
end

local function getParent()
	if typeof(gethui) == "function" then
		local ok, hui = pcall(gethui)
		if ok and hui then
			return hui
		end
	end
	return LP:FindFirstChildOfClass("PlayerGui")
		or LP:WaitForChild("PlayerGui", 5) or game:GetService("CoreGui")
end

local function ensureFolder()
	if S.folder and S.folder.Parent then
		return S.folder
	end
	local parent = getParent()
	if CB.folderName then
		local old = parent:FindFirstChild(CB.folderName)
		if old then
			old:Destroy()
		end
	end
	CB.folderName = blandName("UI")
	local f = Instance.new("Folder")
	f.Name = CB.folderName
	f.Parent = parent
	S.folder = f
	return f
end

local function mk(class, props, parent)
	local i = Instance.new(class)
	for k, v in pairs(props) do
		i[k] = v
	end
	if parent then
		i.Parent = parent
	end
	return i
end

local function newDraw(kind)
	if not HAS_DRAWING then
		return nil
	end
	local ok, obj = pcall(function()
		return Drawing.new(kind)
	end)
	if ok then
		return obj
	end
	return nil
end

local function destroyDraw(obj)
	if not obj then
		return
	end
	pcall(function()
		obj:Remove()
	end)
end

local function applyPreset(name)
	CFG.Preset = name
	if name == "Legit" then
		CFG.Chams = true
		CFG.InfoHud = true
		CFG.Skeleton = false
		CFG.Box = false
		CFG.Snaplines = false
		CFG.Offscreen = false
		CFG.CombatFlash = false
	elseif name == "Duel" then
		CFG.Chams = true
		CFG.InfoHud = false
		CFG.Skeleton = true
		CFG.Box = true
		CFG.Snaplines = true
		CFG.Offscreen = false
		CFG.CombatFlash = true
	elseif name == "Radar" then
		CFG.Chams = true
		CFG.InfoHud = true
		CFG.Skeleton = false
		CFG.Box = false
		CFG.Snaplines = false
		CFG.Offscreen = true
		CFG.CombatFlash = true
	elseif name == "Ghost" then
		CFG.Chams = false
		CFG.InfoHud = false
		CFG.Skeleton = true
		CFG.Box = true
		CFG.Snaplines = true
		CFG.Offscreen = true
		CFG.CombatFlash = false
	end
end

if CFG.Preset and CFG.Preset ~= "" and CB._booted ~= true then
	applyPreset(CFG.Preset)
	CB._booted = true
end
-- Preserve Radar's first-run defaults, then restore exact saved feature choices.
loadConfig()

local function statusFolder(plr)
	return plr and plr:FindFirstChild("Status")
end

local function teamCode(plr)
	local st = statusFolder(plr)
	local tv = st and st:FindFirstChild("Team")
	if tv and tv:IsA("StringValue") then
		return tv.Value
	end
	-- fallback Roblox Team names
	if plr and plr.Team then
		local n = plr.Team.Name
		if n == "Terrorists" then
			return "T"
		end
		if n == "Counter-Terrorists" then
			return "CT"
		end
	end
	return nil
end

local function isAliveStatus(plr)
	local st = statusFolder(plr)
	local a = st and st:FindFirstChild("Alive")
	if a and a:IsA("BoolValue") then
		return a.Value == true
	end
	return nil
end

local function isDeathmatch()
	local gt = ReplicatedStorage:FindFirstChild("gametype")
	return gt and gt:IsA("StringValue") and gt.Value == "deathmatch"
end

local function weaponName(char)
	if not char then
		return "?"
	end
	local gun = char:FindFirstChild("Gun")
	if gun then
		local gn = gun:GetAttribute("GunName")
		if gn and gn ~= "" then
			return tostring(gn)
		end
	end
	local eq = char:FindFirstChild("EquippedTool")
	if eq and eq:IsA("StringValue") and eq.Value ~= "" then
		return eq.Value
	end
	return "?"
end

local function enemyColors(plr)
	if not CFG.TeamColors then
		return COL.fill, COL.outline
	end
	local t = teamCode(plr)
	if t == "T" then
		return COL.tFill, COL.tOut
	end
	if t == "CT" then
		return COL.ctFill, COL.ctOut
	end
	return COL.fill, COL.outline
end

local function isEnemyPlayer(plr)
	if not plr or plr == LP then
		return false
	end
	local alive = isAliveStatus(plr)
	if alive == false then
		return false
	end
	local their = teamCode(plr)
	if their == "Spectator" or their == nil then
		return false
	end
	if isDeathmatch() then
		return true
	end
	local mine = teamCode(LP)
	if not mine or mine == "Spectator" then
		-- still show both sides if we're spectating / pre-team
		return their == "T" or their == "CT"
	end
	return their ~= mine
end

local function isValidTarget(char)
	if not S.alive then
		return false
	end
	if not char or not char.Parent then
		return false
	end
	if char == LP.Character then
		return false
	end
	local plr = Players:GetPlayerFromCharacter(char) or Players:FindFirstChild(char.Name)
	if not isEnemyPlayer(plr) then
		return false
	end
	-- Status.Alive can lag; also gate Humanoid
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return false
	end
	-- if Status.Alive missing, rely on Health only
	local alive = isAliveStatus(plr)
	if alive == false then
		return false
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return false
	end
	local myHrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
	if myHrp then
		if (hrp.Position - myHrp.Position).Magnitude > CFG.MaxDist then
			return false
		end
	end
	return true
end

local function partOf(char, name)
	-- Prefer CB head hitbox for markers (0006 Head|HeadHB|FakeHead)
	if name == "Head" then
		return char:FindFirstChild("HeadHB")
			or char:FindFirstChild("FakeHead")
			or char:FindFirstChild("Head")
	end
	return char:FindFirstChild(name)
end

local function clearDrawBundle(bundle)
	if not bundle then
		return
	end
	for _, obj in pairs(bundle) do
		if type(obj) == "table" then
			for _, o in ipairs(obj) do
				destroyDraw(o)
			end
		else
			destroyDraw(obj)
		end
	end
end

local function clearEsp(char)
	local e = S.esp[char]
	if e then
		if e.conns then
			for _, c in ipairs(e.conns) do
				c:Disconnect()
			end
		end
		if e.hl then
			e.hl:Destroy()
		end
		if e.bb then
			e.bb:Destroy()
		end
		S.esp[char] = nil
	end
	if S.draw[char] then
		clearDrawBundle(S.draw[char])
		S.draw[char] = nil
	end
end

local function wipeAll()
	for char in pairs(S.esp) do
		clearEsp(char)
	end
	for char in pairs(S.draw) do
		clearEsp(char)
	end
	if S.folder then
		S.folder:Destroy()
		S.folder = nil
	end
	S.gui = nil
	S.root = nil
end

local function teardown()
	if not S.alive then return end
	saveConfig()
	CB.closed = true
	S.alive = false
	if Shell then
		Shell.destroy()
		Shell = nil
	end
	if S.hb then
		S.hb:Disconnect()
		S.hb = nil
	end
	if S.input then
		S.input:Disconnect()
		S.input = nil
	end
	if S.playerAdded then
		S.playerAdded:Disconnect()
		S.playerAdded = nil
	end
	for _, c in pairs(S.charConns) do
		c:Disconnect()
	end
	table.clear(S.charConns)
	for _, c in pairs(S.statusConns) do
		c:Disconnect()
	end
	table.clear(S.statusConns)
	wipeAll()
	Log.step("teardown")
end

local function destroy()
	teardown()
	if GENV[GKEY] == CB then
		GENV[GKEY] = nil
	end
end
CB.destroy = destroy
CB.teardown = teardown

local function ensureEsp(char)
	if not isValidTarget(char) then
		clearEsp(char)
		return
	end

	local folder = ensureFolder()
	local plr = Players:GetPlayerFromCharacter(char) or Players:FindFirstChild(char.Name)
	local e = S.esp[char]
	if not e then
		e = { conns = {} }
		S.esp[char] = e
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			table.insert(e.conns, hum.Died:Connect(function()
				clearEsp(char)
			end))
			table.insert(e.conns, hum.HealthChanged:Connect(function(h)
				local prev = e.lastHp or hum.MaxHealth
				if h < prev - 1 then
					e.flashUntil = tick() + 1.25
				end
				e.lastHp = h
			end))
			e.lastHp = hum.Health
		end
		table.insert(e.conns, char.Destroying:Connect(function()
			clearEsp(char)
		end))
	end

	local flashing = CFG.CombatFlash and e.flashUntil and tick() < e.flashUntil
	local fillC, outC = enemyColors(plr)

	if CFG.Chams then
		if not e.hl or not e.hl.Parent then
			local hl = Instance.new("Highlight")
			hl.Name = blandName("HL")
			hl.Adornee = char
			hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			hl.Parent = folder
			e.hl = hl
		end
		e.hl.Adornee = char
		e.hl.Enabled = true
		if flashing then
			e.hl.FillColor = COL.flash
			e.hl.OutlineColor = COL.flash
			e.hl.FillTransparency = 0.35
			e.hl.OutlineTransparency = 0.1
		else
			e.hl.FillColor = fillC
			e.hl.OutlineColor = outC
			e.hl.FillTransparency = 0.35
			e.hl.OutlineTransparency = 0.2
		end
	elseif e.hl then
		e.hl.Enabled = false
	end

	local head = partOf(char, "Head") or char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	if CFG.InfoHud and head and hum then
		if not e.bb or not e.bb.Parent then
			local bb = Instance.new("BillboardGui")
			bb.Name = blandName("NT")
			bb.Adornee = head
			bb.AlwaysOnTop = true
			bb.Size = UDim2.fromOffset(160, 46)
			bb.StudsOffset = Vector3.new(0, 2.6, 0)
			bb.MaxDistance = CFG.MaxDist
			bb.Parent = folder

			local nameL = mk("TextLabel", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 14),
				Position = UDim2.fromOffset(0, 0),
				Font = Enum.Font.GothamBold,
				TextSize = 12,
				TextColor3 = COL.text,
				TextStrokeTransparency = 0.4,
				Text = "",
			}, bb)

			local infoL = mk("TextLabel", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 12),
				Position = UDim2.fromOffset(0, 14),
				Font = Enum.Font.Gotham,
				TextSize = 11,
				TextColor3 = COL.dim,
				TextStrokeTransparency = 0.5,
				Text = "",
			}, bb)

			local track = mk("Frame", {
				BackgroundColor3 = Color3.fromRGB(12, 12, 14),
				BackgroundTransparency = 0.2,
				BorderSizePixel = 0,
				Size = UDim2.new(1, -20, 0, 4),
				Position = UDim2.new(0, 10, 0, 30),
			}, bb)
			mk("UICorner", { CornerRadius = UDim.new(0, 2) }, track)
			local fill = mk("Frame", {
				BackgroundColor3 = COL.hpHi,
				BorderSizePixel = 0,
				Size = UDim2.fromScale(1, 1),
			}, track)
			mk("UICorner", { CornerRadius = UDim.new(0, 2) }, fill)

			e.bb = bb
			e.nameL = nameL
			e.infoL = infoL
			e.fill = fill
		end

		local hrp = char:FindFirstChild("HumanoidRootPart")
		local dist = 0
		local myHrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
		if hrp and myHrp then
			dist = (hrp.Position - myHrp.Position).Magnitude
		end
		local pct = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
		local tcode = teamCode(plr) or "?"
		e.nameL.Text = string.format("%s [%s]", plr and plr.DisplayName or char.Name, tcode)
		e.infoL.Text = string.format("%dm  |  %s", math.floor(dist + 0.5), weaponName(char))
		e.fill.Size = UDim2.fromScale(pct, 1)
		e.fill.BackgroundColor3 = COL.hpLo:Lerp(COL.hpHi, pct)
		e.bb.Adornee = head
		e.bb.Enabled = true
	elseif e.bb then
		e.bb.Enabled = false
	end
end

local function ensureDraw(char)
	if not HAS_DRAWING then
		return
	end
	if not isValidTarget(char) then
		if S.draw[char] then
			clearDrawBundle(S.draw[char])
			S.draw[char] = nil
		end
		return
	end

	local d = S.draw[char]
	if not d then
		d = {
			bones = {},
			box = {},
			snap = nil,
			arrow = nil,
		}
		if CFG.Skeleton then
			for i = 1, #R15_BONES do
				local line = newDraw("Line")
				if line then
					line.Thickness = 1.4
					line.Color = COL.skel
					line.Transparency = 0.15
					line.Visible = false
					d.bones[i] = line
				end
			end
		end
		if CFG.Box then
			for i = 1, 4 do
				local line = newDraw("Line")
				if line then
					line.Thickness = 1.5
					line.Color = COL.box
					line.Transparency = 0.1
					line.Visible = false
					d.box[i] = line
				end
			end
		end
		if CFG.Snaplines then
			local line = newDraw("Line")
			if line then
				line.Thickness = 1
				line.Color = COL.snap
				line.Transparency = 0.35
				line.Visible = false
				d.snap = line
			end
		end
		if CFG.Offscreen then
			local tri = newDraw("Triangle")
			if tri then
				tri.Filled = true
				tri.Color = COL.arrow
				tri.Transparency = 0.15
				tri.Visible = false
				d.arrow = tri
			end
		end
		S.draw[char] = d
	end
end

local function worldToView(pos)
	local v, onScreen = Camera:WorldToViewportPoint(pos)
	return Vector2.new(v.X, v.Y), onScreen, v.Z
end

local function updateDraw(char)
	if not HAS_DRAWING then
		return
	end
	local d = S.draw[char]
	if not d then
		return
	end
	if not isValidTarget(char) then
		clearDrawBundle(d)
		S.draw[char] = nil
		return
	end

	local hrp = char:FindFirstChild("HumanoidRootPart")
	local head = partOf(char, "Head")
	if not hrp then
		return
	end

	local plr = Players:GetPlayerFromCharacter(char) or Players:FindFirstChild(char.Name)
	local hum = char:FindFirstChildOfClass("Humanoid")
	local pct = hum and math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1) or 1
	local fillC = enemyColors(plr)
	local col = COL.hpLo:Lerp(fillC, pct)
	local e = S.esp[char]
	local flashing = CFG.CombatFlash and e and e.flashUntil and tick() < e.flashUntil
	if flashing then
		col = COL.flash
	end

	local vp = Camera.ViewportSize
	local centerBottom = Vector2.new(vp.X * 0.5, vp.Y - 2)
	local hrp2, onScreen, z = worldToView(hrp.Position)

	if CFG.Skeleton and d.bones then
		for i, pair in ipairs(R15_BONES) do
			local line = d.bones[i]
			if line then
				local a = partOf(char, pair[1])
				local b = partOf(char, pair[2])
				if a and b then
					local p1, o1 = worldToView(a.Position)
					local p2, o2 = worldToView(b.Position)
					if o1 and o2 then
						line.From = p1
						line.To = p2
						line.Color = col
						line.Visible = true
					else
						line.Visible = false
					end
				else
					line.Visible = false
				end
			end
		end
	elseif d.bones then
		for _, line in pairs(d.bones) do
			line.Visible = false
		end
	end

	if CFG.Box and d.box and head and onScreen and z > 0 then
		local top = worldToView((head.CFrame * CFrame.new(0, 0.85, 0)).Position)
		local bot = worldToView((hrp.CFrame * CFrame.new(0, -3.1, 0)).Position)
		local h = math.abs(bot.Y - top.Y)
		local w = h * 0.5
		local cx = (top.X + bot.X) * 0.5
		local y1, y2 = math.min(top.Y, bot.Y), math.max(top.Y, bot.Y)
		local x1, x2 = cx - w * 0.5, cx + w * 0.5
		local edges = {
			{ Vector2.new(x1, y1), Vector2.new(x2, y1) },
			{ Vector2.new(x2, y1), Vector2.new(x2, y2) },
			{ Vector2.new(x2, y2), Vector2.new(x1, y2) },
			{ Vector2.new(x1, y2), Vector2.new(x1, y1) },
		}
		for i = 1, 4 do
			local line = d.box[i]
			if line then
				line.From = edges[i][1]
				line.To = edges[i][2]
				line.Color = col
				line.Visible = true
			end
		end
	elseif d.box then
		for _, line in pairs(d.box) do
			line.Visible = false
		end
	end

	if CFG.Snaplines and d.snap and onScreen and z > 0 then
		d.snap.From = centerBottom
		d.snap.To = hrp2
		d.snap.Color = COL.snap
		d.snap.Visible = true
	elseif d.snap then
		d.snap.Visible = false
	end

	if CFG.Offscreen and d.arrow then
		if not onScreen or z <= 0 then
			local dir = Vector2.new(hrp2.X - vp.X * 0.5, hrp2.Y - vp.Y * 0.5)
			if dir.Magnitude < 1e-3 then
				dir = Vector2.new(0, -1)
			else
				dir = dir.Unit
			end
			local margin = 28
			local edge = Vector2.new(
				math.clamp(vp.X * 0.5 + dir.X * (vp.X * 0.45), margin, vp.X - margin),
				math.clamp(vp.Y * 0.5 + dir.Y * (vp.Y * 0.45), margin, vp.Y - margin)
			)
			local ang = math.atan2(dir.Y, dir.X)
			local tip = edge
			local left = tip - Vector2.new(math.cos(ang - 0.5) * 14, math.sin(ang - 0.5) * 14)
			local right = tip - Vector2.new(math.cos(ang + 0.5) * 14, math.sin(ang + 0.5) * 14)
			d.arrow.PointA = tip
			d.arrow.PointB = left
			d.arrow.PointC = right
			d.arrow.Color = fillC
			d.arrow.Visible = true
		else
			d.arrow.Visible = false
		end
	elseif d.arrow then
		d.arrow.Visible = false
	end
end

local function collectChars()
	local set = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LP and isEnemyPlayer(plr) and plr.Character then
			set[plr.Character] = true
		end
	end
	return set
end

local function sweep()
	if not S.alive then
		return
	end
	Camera = Workspace.CurrentCamera
	local live = collectChars()
	for char in pairs(live) do
		ensureEsp(char)
		ensureDraw(char)
		updateDraw(char)
	end
	for char in pairs(S.esp) do
		if not live[char] then
			clearEsp(char)
		end
	end
	for char in pairs(S.draw) do
		if not live[char] then
			clearEsp(char)
		end
	end
end
CB.sweep = sweep
CB.applyPreset = applyPreset

local function refreshEsp()
	for char in pairs(S.draw) do
		clearDrawBundle(S.draw[char])
		S.draw[char] = nil
	end
	sweep()
end

local function buildUI()
	local Kit = HOST and HOST.ui
	if not Kit then Kit = loadfile("r3st_ui.lua")() end
	assert(Kit.SHELL_CONTRACT == "1", "R3ST shell contract mismatch")
	Shell = Kit.moduleShell({
		id = "counterblox", title = "Counter Blox ESP", version = BUILD_VERSION,
		gameId = 115797356, placeId = PLACE_ID,
		live = {}, conns = {}, cfg = CFG, save = saveConfig,
		keep = { ensureFolder() }, onUnload = destroy,
	})
	S.gui, S.root = Shell.screen, Shell.root
	CB.build, CB.embedded = BUILD_VERSION, Shell.hosted
	local W = Shell.W
	local page = Shell.page("Main")
	W.section(page, "Counter Blox ESP")
	W.statusRow(page, function()
		return "RShift hide | K unload | Draw=" .. (HAS_DRAWING and "yes" or "no")
	end)
	local rows = {
		{ "Chams", "Chams" },
		{ "Info HUD", "InfoHud" },
		{ "Skeleton", "Skeleton" },
		{ "Box", "Box" },
		{ "Snaplines", "Snaplines" },
		{ "Offscreen", "Offscreen" },
		{ "Combat flash", "CombatFlash" },
		{ "Team colors", "TeamColors" },
	}
	for _, row in ipairs(rows) do
		W.toggle(page, { label = row[1], key = row[2], set = refreshEsp })
	end
	W.section(page, "Presets")
	for _, name in ipairs({ "Legit", "Duel", "Radar", "Ghost" }) do
		local button = W.button(page, name, nil, function()
			applyPreset(name)
			saveConfig()
			refreshEsp()
		end)
		-- Preserve the selected-preset cue without rebuilding or reparenting the shell.
		local function paint()
			button.BackgroundColor3 = CFG.Preset == name and COL.on or COL.off
		end
		paint()
		table.insert(W.live, paint)
	end
	Shell.hideBind(function()
		CFG.UiVisible = not CFG.UiVisible
		S.root.Visible = CFG.UiVisible
		saveConfig()
	end)
	if not Shell.hosted then S.root.Visible = CFG.UiVisible end
	Shell.ready()
end

local function bindStatus(plr)
	local key = plr.UserId
	if S.statusConns[key] then
		S.statusConns[key]:Disconnect()
		S.statusConns[key] = nil
	end
	local st = statusFolder(plr)
	if not st then
		return
	end
	local alive = st:FindFirstChild("Alive")
	local team = st:FindFirstChild("Team")
	local bag = {}
	if alive then
		table.insert(bag, alive:GetPropertyChangedSignal("Value"):Connect(function()
			task.defer(sweep)
		end))
	end
	if team then
		table.insert(bag, team:GetPropertyChangedSignal("Value"):Connect(function()
			task.defer(sweep)
		end))
	end
	-- store as one disconnect wrapper
	S.statusConns[key] = {
		Disconnect = function()
			for _, c in ipairs(bag) do
				c:Disconnect()
			end
		end,
	}
end

local function bindPlayer(plr)
	if S.charConns[plr] then
		S.charConns[plr]:Disconnect()
	end
	S.charConns[plr] = plr.CharacterAdded:Connect(function()
		task.defer(sweep)
	end)
	bindStatus(plr)
	plr.ChildAdded:Connect(function(ch)
		if ch.Name == "Status" then
			bindStatus(plr)
			task.defer(sweep)
		end
	end)
end

-- boot
S.alive = true
local uiOk, uiErr = xpcall(buildUI, debug.traceback)
if not uiOk then
	Log.err("ui", uiErr)
	destroy()
	return
end

S.hb = RunService.Heartbeat:Connect(function(dt)
	S.acc += dt
	if S.acc >= CFG.EspHz then
		S.acc = 0
		sweep()
	end
end)

S.input = UserInputService.InputBegan:Connect(function(input, gp)
	if gp then
		return
	end
	if input.KeyCode == Enum.KeyCode.K then
		destroy()
		Log.info("unloaded via K")
	end
end)

S.playerAdded = Players.PlayerAdded:Connect(bindPlayer)
for _, plr in ipairs(Players:GetPlayers()) do
	bindPlayer(plr)
end

sweep()

local enemyN = 0
for _ in pairs(collectChars()) do
	enemyN += 1
end

Log.info(string.format(
	"armed preset=%s drawing=%s enemies=%d dm=%s myTeam=%s",
	tostring(CFG.Preset),
	tostring(HAS_DRAWING),
	enemyN,
	tostring(isDeathmatch()),
	tostring(teamCode(LP))
))

pcall(writefile, "cb_esp_status.txt", string.format(
	"OK place=%s preset=%s drawing=%s enemies=%d team=%s t=%s",
	tostring(game.PlaceId),
	tostring(CFG.Preset),
	tostring(HAS_DRAWING),
	enemyN,
	tostring(teamCode(LP)),
	tostring(os.time())
))

print(string.format(
	"[CB_ESP] armed preset=%s drawing=%s enemies=%d place=%s",
	tostring(CFG.Preset),
	tostring(HAS_DRAWING),
	enemyN,
	tostring(game.PlaceId)
))
