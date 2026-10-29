-- R3ST runtime v2026-10-29.2 (2026-10-29)
-- Pure lifecycle and bounded profiling helpers; no hooks, remotes or auto-start.
-- 2026-10-29.2 Keep failed disarm visible even when recovery is requested OFF.
-- 2026-10-29.1 Teleport handoff helpers: one guarded Hub loader per server.
-- REINJECT_EXEMPT: dependency factory; owns resources only through returned handles.
local Runtime = {}
Runtime.VERSION = "2026-10-29.2"
local PATHS = { "../scripts/%s", "%s", "scripts/%s" }

function Runtime.resolve(file, read, compile)
	for _, pattern in ipairs(PATHS) do
		local path = pattern:format(file)
		local ok, source = pcall(read, path)
		if ok and type(source) == "string" then
			local ran, chunk, err = pcall(compile, source, "=" .. file)
			if not ran or type(chunk) ~= "function" then
				return nil, "compile error in " .. path .. ": " .. tostring(ran and err or chunk)
			end
			return chunk, nil, path, source
		end
	end
	return nil, "not found in the Potassium Explorer folder (" .. file .. ")"
end

-- Build the replacement first. Only its resources are cleaned on prepare failure.
-- A throwing legacy destroy may already have changed state: report, never promise rollback.
function Runtime.boot(globals, key, prepare)
	if globals.__R3ST_BOOT_BUSY or globals.__R3ST_MODULE_BUSY then return nil, "another lifecycle operation is in progress" end
	globals.__R3ST_BOOT_BUSY = true
	local prior, cleanup = globals[key], {}
	local scope = {}
	function scope.own(fn) cleanup[#cleanup + 1] = fn end
	local ok, handle = xpcall(function()
		if prior and type(prior.flush) == "function" then
			local saved, reason = prior.flush()
			if saved == false then error(reason or "resident save flush failed") end
		end
		return prepare(scope)
	end, tostring)
	if ok and (type(handle) ~= "table" or handle.ready ~= true) then
		ok, handle = false, "replacement did not become ready"
	end
	if ok and prior and type(prior.destroy) == "function" then
		local stopped, result, reason = pcall(prior.destroy)
		if not stopped or result == false then
			ok, handle = false, "old teardown failed (state may be partial): " .. tostring(reason or result)
		end
	end
	if not ok then
		for i = #cleanup, 1, -1 do pcall(cleanup[i]) end
		globals.__R3ST_BOOT_BUSY = nil
		return nil, tostring(handle)
	end
	globals[key] = handle
	globals.__R3ST_BOOT_BUSY = nil
	return handle
end

function Runtime.exclusive(globals, fn)
	if globals.__R3ST_MODULE_BUSY or globals.__R3ST_BOOT_BUSY then return false, "another module operation is in progress" end
	globals.__R3ST_MODULE_BUSY = true
	local result = table.pack(xpcall(fn, tostring))
	globals.__R3ST_MODULE_BUSY = nil
	if not result[1] then return false, result[2], true end
	return table.unpack(result, 2, result.n)
end

function Runtime.mounted(handle, host)
	if type(handle) ~= "table" then return false, "module returned without a lifecycle handle" end
	if handle.ready == false or handle._ready == false then return false, "module reports not ready" end
	if not handle.build then return false, "module has no build stamp; readiness unverified" end
	if host then
		if not host.Parent then return false, "module destroyed its Hub host" end
		local panel = false
		for _, child in ipairs(host:GetChildren()) do
			if child:IsA("GuiObject") then panel = true; break end
		end
		if not panel then return false, "module returned without a mounted panel" end
	end
	return true
end

function Runtime.runModule(o)
	return Runtime.exclusive(o.globals, function()
		local chunk, err = o.load(o.entry.file)
		if not chunk then return false, err end -- nothing torn down until compile passes
		local existing = o.globals[o.entry.gkey]
		-- Detach keeps Anims' controller. Explicit reload requires full unload.
		local fn = not (o.entry.deferred and not o.fresh) and existing
			and (o.fresh and (existing.unload or existing.destroy) or existing.detach or existing.destroy)
		if o.fresh and existing and type(fn) ~= "function" then return false, "resident has no supported teardown" end
		if type(fn) == "function" then
			local ok, result, reason = pcall(fn)
			if not ok or result == false then return false, "teardown failed: " .. tostring(reason or result), true end
		end
		if o.host then
			for _, child in ipairs(o.host:GetChildren()) do child:Destroy() end
		end
		local remount = not o.fresh and existing and type(existing.detach) == "function"
			and type(existing.mount) == "function"
		o.globals.__R3ST_HOST = o.transport
		local ok, result, reason = pcall(function()
			if remount then return existing.mount(o.transport) end
			return chunk()
		end)
		o.globals.__R3ST_HOST = nil -- also cleared for returned failures and thrown errors
		if not ok or result == false then return false, "module runtime failed: " .. tostring(reason or result), true end
		if o.entry.deferred then return true end -- loader started; caller owns readiness polling
		local handle = o.globals[o.entry.gkey]
		if o.fresh and existing and handle == existing then return false, "reload retained the old controller", true end
		local ready, reason = Runtime.mounted(handle, o.host)
		return ready, reason, true
	end)
end

-- Teleport handoff. The queued loader only runs hub.lua (never admin.lua), once,
-- after game and LocalPlayer readiness, and only while the token file still holds
-- its token: unload or disabling the setting voids queued work we cannot dequeue.
Runtime.HANDOFF_FILE = "r3st_handoff.txt"
function Runtime.queueApi(globals)
	local function pick(t, key) return type(t) == "table" and type(t[key]) == "function" and t[key] or nil end
	return pick(globals, "queue_on_teleport") or pick(globals, "queueonteleport")
		or pick(globals.syn, "queue_on_teleport") or pick(globals.fluxus, "queue_on_teleport")
end
function Runtime.handoffSource(token)
	local paths = {}
	for i, pattern in ipairs(PATHS) do paths[i] = ("%q"):format(pattern:format("hub.lua")) end
	return ([[
local TOKEN, FILE = %q, %q
local G = getgenv()
local function note(text)
	pcall(function()
		if makefolder and isfolder and not isfolder("logs") then makefolder("logs") end
		local line = os.date("[%%H:%%M:%%S] ") .. text .. "\n"
		if appendfile and isfile and isfile("logs/r3st_handoff.log") then appendfile("logs/r3st_handoff.log", line)
		else writefile("logs/r3st_handoff.log", line) end
	end)
end
if not game:IsLoaded() then game.Loaded:Wait() end
local Players = game:GetService("Players")
local deadline = os.clock() + 30
while not Players.LocalPlayer and os.clock() < deadline do task.wait(0.1) end
if not Players.LocalPlayer then return note("SKIP LocalPlayer never became ready") end
local armed, current = pcall(readfile, FILE)
if not armed or current ~= TOKEN then return note("SKIP stale or disarmed handoff") end
-- Stale queued copies must never claim the destination's one-run guard.
if G.__R3ST_HANDOFF_RUN then return end
G.__R3ST_HANDOFF_RUN = TOKEN
local hub = G.__R3ST_HUB
if (type(hub) == "table" and hub.ready) or G.__R3ST_BOOT_BUSY then return note("SKIP Hub already running") end
local source
for _, path in ipairs({ %s }) do
	local found, body = pcall(readfile, path)
	if found and type(body) == "string" then source = body; break end
end
if not source then return note("SKIP hub.lua missing") end
local chunk, err = loadstring(source, "=hub.lua")
if not chunk then return note("FAILED hub.lua compile: " .. tostring(err)) end
G.__R3ST_HANDOFF_BOOT = TOKEN
local ran, result = pcall(chunk)
G.__R3ST_HANDOFF_BOOT = nil
note((ran and type(result) == "table" and result.ready) and "OK Hub loaded after teleport"
	or ("FAILED Hub boot: " .. tostring(result)))
]]):format(token, Runtime.HANDOFF_FILE, table.concat(paths, ", "))
end

-- o: globals, queue, write, jobId, owner, token(). One queued loader per server
-- (JobId); reloads reuse it. Only the arming owner may void it on unload.
function Runtime.handoff(o)
	local H, globals, event, previous = {}, o.globals, nil, nil
	local function record()
		local rec = globals.__R3ST_HANDOFF_QUEUE
		if type(rec) == "table" and rec.job == o.jobId then return rec end
	end
	function H.available()
		if type(o.queue) ~= "function" then return false, "executor has no queue_on_teleport" end
		if type(o.write) ~= "function" then return false, "executor has no writefile" end
		return true
	end
	function H.arm()
		local ok, why = H.available()
		if not ok then return false, why end
		local rec = record()
		if not rec then
			local token = tostring(o.token())
			local queued, err = pcall(o.queue, Runtime.handoffSource(token))
			if not queued or err == false then event = "Queue failed: " .. tostring(err); return false, event end
			rec = { token = token, job = o.jobId }
			globals.__R3ST_HANDOFF_QUEUE = rec
		end
		local wrote, err = pcall(o.write, Runtime.HANDOFF_FILE, rec.token)
		if not wrote then event = "Token write failed: " .. tostring(err); return false, event end
		if rec.owner ~= o.owner then previous = rec.owner end
		rec.owner, event = o.owner, nil
		return true
	end
	function H.release() -- a failed replacement hands ownership back
		local rec = record()
		if rec and rec.owner == o.owner then rec.owner = previous end
	end
	function H.disarm(force)
		local rec = record()
		if not rec or (rec.owner ~= o.owner and not force) then return false end
		local wrote, err = pcall(o.write, Runtime.HANDOFF_FILE, "")
		if not wrote then event = "Could not disarm queued handoff: " .. tostring(err); return false, event end
		rec.owner, event = nil, nil
		return true
	end
	function H.armed()
		local rec = record()
		return rec ~= nil and rec.owner == o.owner
	end
	function H.event(text) event = text end
	-- Status only; a failed teleport leaves the loader queued for the next one.
	function H.watch(player, teleport, connect, notify)
		local function on(state)
			if not H.armed() then return end
			if state == Enum.TeleportState.Started then
				event = "Teleporting: the Hub reloads after arrival"
				notify(false)
			elseif state == Enum.TeleportState.Failed then
				event = "Teleport failed: still armed for the next transfer"
				notify(true)
			end
		end
		pcall(function() connect(player.OnTeleport, on) end)
		pcall(function()
			connect(teleport.TeleportInitFailed, function(who)
				if who == player then on(Enum.TeleportState.Failed) end
			end)
		end)
	end
	function H.status(enabled)
		local ok, why = H.available()
		if not ok then return false, "Unavailable: " .. why end
		if event then return true, event end
		if not enabled then return true, "Off: teleports leave the Hub unloaded" end
		if H.armed() then return true, "Armed: the Hub reloads once after the next teleport" end
		return true, "Not armed"
	end
	return H
end

-- One reusable notice with a single pending timer that each update replaces, so
-- nothing stacks. Reduced motion paints instantly and hides without an exit delay.
function Runtime.notice(o)
	local N, ticket, timer, up = {}, 0, nil, false
	function N.cancel()
		if timer then pcall(o.cancel, timer) end
		timer = nil
	end
	function N.show(text, isError)
		if not o.alive() then return end
		N.cancel()
		ticket += 1
		local mine, still = ticket, o.still()
		local function later(seconds, fn)
			timer = o.delay(seconds, function()
				timer = nil
				if o.alive() and ticket == mine then fn() end
			end)
		end
		-- One line only: newlines would spill out of a fixed-height card.
		text = (tostring(text or ""):gsub("%s+", " ")):match("^%s*(.-)%s*$")
		if text ~= "" then
			up = true
			o.paint(true, still and 0 or o.enter, text, isError)
			return later(isError and 5 or 3.5, function() N.show("") end)
		end
		if not up then return o.done() end
		up = false
		o.paint(false, still and 0 or o.exit)
		if still then return o.done() end
		later(o.exit, o.done)
	end
	return N
end

-- O(1) per frame, one connection, no per-frame files/sorting or heap inspection.
-- Frames are wall-frame intervals, not a measurement of this script's CPU cost.
function Runtime.profiler(o)
	local active, last, connection
	local P = {}
	local function percentile(values, fraction)
		return values[math.max(1, math.ceil(#values * fraction))] or 0
	end
	function P.stop(reason)
		if not active then return last end
		if connection then connection:Disconnect(); connection = nil end
		local sample = active
		active = nil
		table.sort(sample.frames)
		last = { schema = "r3st-perf/1", label = sample.label, build = o.build,
			placeId = o.placeId, gameId = o.gameId, session = o.session,
			count = #sample.frames, seconds = sample.elapsed, reason = reason or "stopped",
			p50Ms = percentile(sample.frames, 0.50) * 1000,
			p95Ms = percentile(sample.frames, 0.95) * 1000,
			p99Ms = percentile(sample.frames, 0.99) * 1000,
			maxMs = (sample.frames[#sample.frames] or 0) * 1000,
			context = sample.context, work = sample.work,
			measured = "wall-frame intervals; instrumented callback wall costs are not causal attribution" }
		if o.write then
			local ok, err = pcall(o.write, last)
			if not ok then last.writeError = tostring(err) end
		end
		return last
	end
	function P.start(label, seconds, context)
		if active then return false, "capture already active" end
		if type(label) ~= "string" or not label:match("^[%w_-]+$") or #label > 40 then
			return false, "label must be 1-40 letters/digits/_/-"
		end
		seconds = tonumber(seconds) or 30
		if seconds ~= seconds or seconds < 5 or seconds > 120 then return false, "duration must be 5-120 seconds" end
		active = { label = label, elapsed = 0, frames = {}, work = {}, context = context or {} }
		local ok, err = pcall(function()
			connection = o.signal:Connect(function(dt)
				if not active or type(dt) ~= "number" or dt <= 0 or dt ~= dt or dt == math.huge then return end
				active.elapsed += dt
				active.frames[#active.frames + 1] = dt
				if active.elapsed >= seconds then P.stop("complete")
				elseif #active.frames >= 36000 then P.stop("sample cap") end
			end)
		end)
		if not ok then active = nil; return false, tostring(err) end
		return true, "capture started: " .. label
	end
	function P.active() return active ~= nil end
	function P.record(name, seconds)
		if not active or type(seconds) ~= "number" or seconds < 0 or seconds ~= seconds or seconds == math.huge then return end
		local metric = active.work[name]
		if not metric then
			local count = 0
			for _ in pairs(active.work) do count += 1 end
			if count >= 16 then return end
			metric = { calls = 0, totalMs = 0, maxMs = 0 }
			active.work[name] = metric
		end
		metric.calls += 1
		metric.totalMs += seconds * 1000
		metric.maxMs = math.max(metric.maxMs, seconds * 1000)
	end
	function P.status()
		return active and (active.label .. " " .. string.format("%.1fs", active.elapsed))
			or (last and (last.label .. " " .. last.reason .. string.format(" p95 %.2fms", last.p95Ms))) or "idle"
	end
	function P.snapshot() return last end
	return P
end

return Runtime
