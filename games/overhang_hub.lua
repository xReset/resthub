-- Overhang Hub v2026-09-02.4 (2026-09-02)
-- Rungs 2-4. Grab assist resizes client grab sensors; local rods use the game's
-- own predicted WorldPipe path and send no remote. Server sees resulting player motion only.
-- Proof: dump 0087.lua:98-115,275-307; 0083.lua:75-135; 0082.lua:8-112.
-- Local rods boot from saved state because they never fire a remote. K = unload/panic.
-- Re-inject safe: self-teardown restores sensors and LocalPipe scripts.
-- Changelog: .4 allow zero local-rod throw cooldown.
--            .3 run shared-kit live painters so toggles animate after clicks.
--            .2 preserve settled rods beyond the stock 40-second Debris cap.

local BUILD_VERSION = "2026-09-02.4"
local EXPECTED_PLACE = 125633828844867
local EXPECTED_GAME = 9878210988
local GKEY = "__OVERHANG_HUB"
local CONFIG_FILE = "overhang_hub_config.json"

if game.GameId ~= EXPECTED_GAME and game.PlaceId ~= EXPECTED_PLACE then return end

local G = getgenv()
if G[GKEY] and G[GKEY].destroy then pcall(G[GKEY].destroy) end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")
local LP = Players.LocalPlayer
local HOST = type(G.__R3ST_HOST) == "table" and G.__R3ST_HOST or nil

local function fallbackLog(level, message)
	pcall(function()
		local path = "logs/overhang_hub.log"
		local old = isfile and isfile(path) and readfile(path) or ""
		writefile(path, old .. os.date("[%Y-%m-%d %H:%M:%S] ") .. level .. " " .. tostring(message) .. "\n")
	end)
end
local Log = { info = function(m) fallbackLog("INFO", m) end, warn = function(m) fallbackLog("WARN", m) end }
pcall(function() Log = loadfile("log.lua")()('overhang_hub') end)

local defaults = {
	grabAssist = false,
	grabExtra = 4,
	localRods = false,
	rodCooldown = 0.9,
	rodDuration = 40,
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
cfg.grabExtra = math.clamp(cfg.grabExtra, 0, 10)
cfg.rodCooldown = math.clamp(cfg.rodCooldown, 0, 2)
cfg.rodDuration = math.clamp(cfg.rodDuration, 15, 180)

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

local state = {
	alive = true, conns = {}, originals = {}, scripts = {}, localRods = {},
	lastThrow = 0, throws = 0, status = "Ready", screen = nil,
}
local function connect(signal, fn)
	local c = signal:Connect(fn)
	state.conns[#state.conns + 1] = c
	return c
end
local function setStatus(text)
	if state.status ~= text then state.status = text; Log.info("status=" .. text) end
end
local function character()
	local char = LP.Character
	return char, char and char:FindFirstChild("HumanoidRootPart")
end
local function pipeTool()
	local char = LP.Character
	local backpack = LP:FindFirstChildOfClass("Backpack")
	return (char and char:FindFirstChild("Pipe")) or (backpack and backpack:FindFirstChild("Pipe"))
end

local function restoreSensors()
	for part, size in next, state.originals do
		if part.Parent then pcall(function() part.Size = size end) end
	end
	table.clear(state.originals)
end
local function applyGrabAssist()
	local char = LP.Character
	if not char then return end
	for _, name in ipairs({ "GrabBox", "HangBox" }) do
		local part = char:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			if not state.originals[part] then state.originals[part] = part.Size end
			local base = state.originals[part]
			if cfg.grabAssist then
				part.Size = base + Vector3.new(0, 0, cfg.grabExtra)
			elseif part.Size == base + Vector3.new(0, 0, cfg.grabExtra) then
				part.Size = base
			end
		end
	end
end

local function setStockPipeEnabled(tool, enabled)
	if not tool then return end
	local scriptObject = tool:FindFirstChild("LocalPipe")
	if scriptObject and scriptObject:IsA("LocalScript") then
		if state.scripts[scriptObject] == nil then state.scripts[scriptObject] = scriptObject.Disabled end
		scriptObject.Disabled = not enabled
	end
end
local function restorePipeScripts()
	for scriptObject, disabled in next, state.scripts do
		if scriptObject.Parent then pcall(function() scriptObject.Disabled = disabled end) end
	end
	table.clear(state.scripts)
end
local function clearLocalRods()
	for rod in next, state.localRods do
		if rod.Parent then pcall(function() rod:Destroy() end) end
	end
	table.clear(state.localRods)
end

local okWorldPipe, WorldPipe = pcall(require, ReplicatedStorage:WaitForChild("Modules"):WaitForChild("WorldPipe"))
if not okWorldPipe or type(WorldPipe) ~= "table" or type(WorldPipe.worldPipe) ~= "function" then
	Log.warn("WorldPipe module unavailable")
	WorldPipe = nil
end

local function throwLocalRod(tool)
	if not state.alive or not cfg.localRods or not WorldPipe then return end
	local now = os.clock()
	if now - state.lastThrow < cfg.rodCooldown then return end
	local char, root = character()
	if not char or not root or tool.Parent ~= char then setStatus("Equip a rod") return end
	state.lastThrow = now
	local camera = workspace.CurrentCamera
	local mouse = LP:GetMouse()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }
	params.CollisionGroup = "Pipe"
	params.RespectCanCollide = true
	local delta = mouse.Hit.Position - camera.CFrame.Position
	local hit = delta.Magnitude > 0 and workspace:Raycast(camera.CFrame.Position, delta.Unit * 1000, params) or nil
	local target = hit and CFrame.new(hit.Position) or camera.CFrame * CFrame.new(0, 0, -1000)
	local before = {}
	local folder = workspace:FindFirstChild("ClientWorldPipes")
	if not folder then setStatus("Client rod folder unavailable") return end
	for _, child in ipairs(folder:GetChildren()) do before[child] = true end
	local remaining = tool:GetAttribute("Remaining")
	if type(remaining) ~= "number" or remaining <= 0 then tool:SetAttribute("Remaining", 1) end
	task.spawn(WorldPipe.worldPipe, LP, root.CFrame * CFrame.new(0, 1, 0), target,
		camera.CFrame.LookVector, camera.CFrame.Rotation, true)
	task.delay(0.1, function()
		if not state.alive then return end
		for _, child in ipairs(folder:GetChildren()) do
			if not before[child] then
				state.localRods[child] = true
				local bornAt = os.clock()
				task.spawn(function()
					-- WorldPipe finishes flight by creating HangDetection. Preserve a
					-- settled clone because its stock Debris timer always deletes the
					-- predicted instance at 40 seconds (0082.lua:37).
					local deadline = os.clock() + 8
					while state.alive and child.Parent and os.clock() < deadline
						and not child:FindFirstChild("HangDetection") do task.wait(0.1) end
					if not state.alive or not child.Parent or not child:FindFirstChild("HangDetection") then return end
					local clone = child:Clone()
					clone.Name = child.Name .. "_R3ST"
					clone:SetAttribute("Breaking", false)
					local breaking = clone:FindFirstChild("Breaking")
					if breaking then breaking:Destroy() end
					clone.Parent = folder
					state.localRods[clone] = true
					-- Leave the original alive so the game's yielding coroutine cannot
					-- error into LogService; remove only its local grab surfaces.
					for _, name in ipairs({ "HangPart", "HangDetection" }) do
						local surface = child:FindFirstChild(name)
						if surface then surface:Destroy() end
					end
					local remainingLife = math.max(0, cfg.rodDuration - (os.clock() - bornAt))
					task.delay(remainingLife, function()
						state.localRods[clone] = nil
						if clone.Parent then clone:Destroy() end
					end)
				end)
			end
		end
	end)
	state.throws += 1
	setStatus("Local rod placed")
	Log.info(string.format("local rod throw=%d cooldown=%.2f duration=%.0f", state.throws, cfg.rodCooldown, cfg.rodDuration))
end

local boundTool
local toolConn
local function bindTool()
	local tool = pipeTool()
	if tool == boundTool then
		if tool then setStockPipeEnabled(tool, not cfg.localRods) end
		return
	end
	if toolConn then toolConn:Disconnect(); toolConn = nil end
	if boundTool then setStockPipeEnabled(boundTool, true) end
	boundTool = tool
	if not tool then return end
	setStockPipeEnabled(tool, not cfg.localRods)
	toolConn = tool.Activated:Connect(function() throwLocalRod(tool) end)
end

local function stopFeatures()
	cfg.grabAssist = false
	cfg.localRods = false
	restoreSensors()
	restorePipeScripts()
	clearLocalRods()
	setStatus("Stopped")
end
local destroy
destroy = function()
	if not state.alive then return end
	state.alive = false
	stopFeatures()
	if toolConn then toolConn:Disconnect() end
	for _, c in ipairs(state.conns) do pcall(function() c:Disconnect() end) end
	if state.screen then
		state.screen:Destroy()
	elseif state.panel and state.panel.Parent then
		state.panel:Destroy()
	end
	if G[GKEY] == state then G[GKEY] = nil end
	Log.info("unloaded " .. BUILD_VERSION)
end
state.destroy, state.build = destroy, BUILD_VERSION
G[GKEY] = state

local tickAt = 0
connect(RunService.Heartbeat, function()
	if not state.alive or os.clock() - tickAt < 0.2 then return end
	tickAt = os.clock()
	applyGrabAssist()
	bindTool()
end)
connect(UserInputService.InputBegan, function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.K then destroy() end
end)

local Kit = (HOST and HOST.ui) or loadfile("../scripts/r3st_ui.lua")()
local screen
local panel = Instance.new("Frame")
panel.Name = "OverhangPanel"
panel.Size = UDim2.fromOffset(760, 560)
panel.Position = UDim2.new(0.5, -380, 0.5, -280)
panel.BackgroundColor3 = Kit.COL.bg
panel.BorderSizePixel = 0

-- Hosted modules create no LayerCollector: the panel is reparented directly
-- into hub.lua's identity-gated content host. ScreenGui exists only for the
-- required direct-injection fallback when __R3ST_HOST is absent.
if not HOST then
	screen = Instance.new("ScreenGui")
	screen.Name = "R3ST_Overhang_" .. tostring(math.random(1000, 9999))
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 2147483647
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Global
	screen.Parent = CoreGui
	panel.Parent = screen
	state.screen = screen
end
state.panel = panel
local H = Kit.host({ screen = screen, root = panel })
local inner = Instance.new("Frame")
inner.BackgroundTransparency = 1
inner.Position = UDim2.fromOffset(H.hosted and 12 or 18, H.hosted and 8 or 14)
inner.Size = UDim2.new(1, H.hosted and -24 or -36, 1, H.hosted and -16 or -28)
inner.Parent = panel
local live = {}
local W = Kit.bind({ live = live, conns = state.conns, cfg = cfg, save = saveConfig })
connect(RunService.RenderStepped, function()
	for _, paint in ipairs(live) do
		local ok, err = pcall(paint)
		if not ok then Log.warn("ui paint failed: " .. tostring(err)) end
	end
end)
W.header(inner, { title = "Overhang", version = BUILD_VERSION,
	subtitle = "Native grab assistance and client-local climbing rods.", gameId = EXPECTED_GAME, placeId = EXPECTED_PLACE })
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

W.section(page, "Climbing")
W.toggle(page, { label = "Grab assist", key = "grabAssist",
	desc = "Extends the same local GrabBox and HangBox sensors used by low-FPS compensation." })
W.slider(page, { label = "Grab reach", key = "grabExtra", min = 0, max = 10, step = 0.5,
	desc = "Additional forward sensor depth.", fmt = function(v) return string.format("+%.1f studs", v) end })
W.note(page, "Grab assist changes only client sensors. The server sees resulting movement, not the sensor resize.")

W.section(page, "Local rods")
W.toggle(page, { label = "Infinite local rods", key = "localRods",
	desc = "Uses Overhang's predicted WorldPipe path without firing ThrowPipe to the server.",
	set = function(value) cfg.localRods = value; bindTool(); if not value then clearLocalRods() end end })
W.slider(page, { label = "Throw cooldown", key = "rodCooldown", min = 0, max = 2, step = 0.05,
	fmt = function(v) return string.format("%.2fs", v) end })
W.slider(page, { label = "Rod duration", key = "rodDuration", min = 15, max = 180, step = 5,
	fmt = function(v) return string.format("%.0fs", v) end })
W.note(page, "Local rods are visible only to you and may be corrected by the server. Disabling this restores the stock rod script and removes local rods.")
W.statusRow(page, function() return string.format("Status: %s  •  Local throws: %d", state.status, state.throws) end)

page.CanvasSize = UDim2.fromOffset(0, W.height(page))
W.footer(inner, { onUnload = destroy, onSettings = function() end, hint = "K = panic unload" })
H.hideBind(function() panel.Visible = not panel.Visible end)
saveConfig()
Log.info(string.format("boot %s hosted=%s grab=%s localRods=%s", BUILD_VERSION, tostring(H.hosted), tostring(cfg.grabAssist), tostring(cfg.localRods)))
