-- R3ST UI kit v2026-08-31.1
-- The ONE control template every module in hub.lua renders with.
--
-- Rung 2 (client-created UI only). Server sees nothing: this file creates
-- Instances under a GUI the caller owns and never reads or writes game state.
--
-- WHY THIS FILE EXISTS
--   Every game module used to draw its own toggles and sliders, so the hub was
--   nine different-looking panels behind one shell. This is the shared layer:
--   header, tab strip, two-column card grid, pill toggle, track slider, button,
--   status row, footer. A module supplies content; it never supplies a look.
--
-- CONTRACT
--   local Kit = <loadfile "r3st_ui.lua">()          -- or HOST.ui from hub.lua
--   local H   = Kit.host({ screen = screen, root = panel, keep = { espFolder } })
--   local W   = Kit.bind({ live = {}, conns = {}, guard = f,
--                          cfg = CFG, save = saveConfig })
--   W.page(scrollingFrame, { width = 700 })
--   W.section(page, "Main")                          -- starts a card
--   W.toggle(page, { label=, desc=, get=, set= })    -- rows land in that card
--   W.toggle(page, { label=, key=, default=, set= }) -- ...key = autosaved to cfg
--   W.slider(page, { label=, min=, max=, step=, get=, set=, fmt=, stock=,
--                    tradeoff=, live=, commit= })
--   W.button(page, text, desc, fn, wide)
--   W.note(page, text) / W.statusRow(page, getText)
--   W.height(page)                                   -- canvas height so far
--   W.header(parent, { title=, version=, subtitle=, gameId=, placeId=, onInfo= })
--   W.tabstrip(parent, { names=, get=, set=, width= })
--   W.footer(parent, { onUnload=, onSettings=, hint= })
--
--   `live` and `conns` are the CALLER's tables, so the caller's existing
--   refresh loop and teardown keep working unchanged. That is what let gd2.lua
--   adopt the template without touching a single page builder.
--
-- Signatures match the widgets gd2.lua already had, on purpose: adopting the
-- template must never mean rewriting a proven page of controls.

local Kit = {}
Kit.VERSION = "2026-09-01.3"

local UserInputService = game:GetService("UserInputService")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")

--==========================================================================
-- TOKENS -- the one palette, type scale and spacing grid (hub skill S3)
--
-- WHY: on 2026-09-01 there were FOUR palettes on screen at once -- hub.lua's
-- own `C`, this table, gd2.lua:3425 and anims.lua:269 -- and two different
-- greys called `dim` (165,167,172 and 146,146,158) sat side by side in the same
-- window. Nobody could name why, which is exactly what makes a product read as
-- assembled rather than designed. Every surface consumes these now.
--
-- Monochrome on purpose. The accent is WHITE, and focus comes from elevation
-- and stroke brightness, not hue. `good` is the one chromatic token and it means
-- exactly one thing: this is live/ready/active.
--
-- ELEVATION LADDER -- each step is a real, visible lift off the one below:
--   bg(7)  window ground  <  panel(13)  sidebar/content  <  card(17)  <  row(24)
-- hub.lua used to paint panel with bg, so the sidebar and content had no edge
-- against the window at all. That flatness is most of why the shell looked unfinished.
--==========================================================================
Kit.COL = {
	bg = Color3.fromRGB(7, 7, 9),
	panel = Color3.fromRGB(13, 13, 16),
	card = Color3.fromRGB(17, 17, 21),
	row = Color3.fromRGB(24, 24, 29),
	rowHover = Color3.fromRGB(31, 31, 37),
	line = Color3.fromRGB(42, 42, 50),
	lineSoft = Color3.fromRGB(30, 30, 36),
	text = Color3.fromRGB(240, 240, 245),
	dim = Color3.fromRGB(146, 146, 158),
	faint = Color3.fromRGB(104, 104, 116),
	white = Color3.fromRGB(255, 255, 255),
	good = Color3.fromRGB(72, 205, 57),
	bad = Color3.fromRGB(255, 120, 120),
	knobOff = Color3.fromRGB(120, 120, 132),
}
-- Aliases so hub.lua's historic names resolve to the SAME colour instead of a
-- near-miss of it. Adding names is safe; renaming would break gd2/blr mid-port.
Kit.COL.raised = Kit.COL.card
Kit.COL.hover = Kit.COL.row
Kit.COL.green = Kit.COL.good
local COL = Kit.COL

-- Five sizes, not ten. Screenshot audit found 10/11/12/13/14/15/18/19/22/24 in
-- use across hub.lua alone; a scale nobody can recite is a scale nobody applies.
Kit.TYPE = { micro = 10, small = 11, body = 13, head = 15, title = 22 }

-- 4px grid. Every offset in new layout code is one of these.
Kit.SPACE = { xs = 4, sm = 8, md = 12, lg = 16, xl = 24, xxl = 32 }

--==========================================================================
-- MOTION
--
-- Before 2026-09-01 the entire product -- hub, kit, gd2, blr, anims, admin --
-- contained zero TweenService calls. Everything snapped. That single fact was
-- most of the "not premium" feeling.
--
-- Restrained on purpose: opacity, position and scale only, ease-OUT only, and
-- no bounce/elastic/spring anywhere. Overshoot is the vibecoded tell -- real
-- tools decelerate into place and stop. Durations are short enough that daily
-- use never waits on them.
--
-- Kit.reduceMotion = true makes every helper below apply the final value
-- instantly, so the setting is honoured without a branch at each call site.
--==========================================================================
Kit.MOTION = { fast = 0.10, base = 0.14, slow = 0.20 }
Kit.reduceMotion = false

local EASE_OUT = Enum.EasingStyle.Quad
local EASE_DIR = Enum.EasingDirection.Out

-- Returns the Tween so a caller can wait on Completed; nil when motion is off.
function Kit.tween(obj, props, dur, style)
	if typeof(obj) ~= "Instance" then return nil end
	if Kit.reduceMotion or dur == 0 then
		for k, v in pairs(props) do
			pcall(function() obj[k] = v end)
		end
		return nil
	end
	local info = TweenInfo.new(dur or Kit.MOTION.base, style or EASE_OUT, EASE_DIR)
	local t = TweenService:Create(obj, info, props)
	t:Play()
	return t
end
local tween = Kit.tween

-- Window/panel open: fade + a small scale lift. 0.96 not 0.8 -- a big scale jump
-- reads as a cartoon, a small one reads as weight.
function Kit.appear(frame, scaleObj, done)
	if Kit.reduceMotion then
		frame.Visible = true
		if scaleObj then scaleObj.Scale = scaleObj:GetAttribute("R3ST_TargetScale") or scaleObj.Scale end
		if done then done() end
		return
	end
	local target = scaleObj and (scaleObj:GetAttribute("R3ST_TargetScale") or scaleObj.Scale) or 1
	frame.Visible = true
	if scaleObj then scaleObj.Scale = target * 0.96 end
	local t = tween(frame, { BackgroundTransparency = frame:GetAttribute("R3ST_BaseTransparency") or 0 }, Kit.MOTION.base)
	if scaleObj then tween(scaleObj, { Scale = target }, Kit.MOTION.base) end
	if done then
		if t then t.Completed:Once(done) else done() end
	end
end

-- Close is faster than open: getting out of the way should never feel slow.
function Kit.vanish(frame, scaleObj, done)
	if Kit.reduceMotion then
		frame.Visible = false
		if done then done() end
		return
	end
	local target = scaleObj and (scaleObj:GetAttribute("R3ST_TargetScale") or scaleObj.Scale) or 1
	if scaleObj then tween(scaleObj, { Scale = target * 0.97 }, Kit.MOTION.fast) end
	local t = tween(frame, { BackgroundTransparency = 1 }, Kit.MOTION.fast)
	local function finish()
		frame.Visible = false
		if scaleObj then scaleObj.Scale = target end
		if done then done() end
	end
	if t then t.Completed:Once(finish) else finish() end
end

-- Page switch: crossfade a CanvasGroup-less Frame by walking nothing -- we just
-- swap Visible and fade the incoming page's own transparency proxy. Kept at
-- 90ms because a page switch is navigation, not decoration.
function Kit.pageIn(frame)
	frame.Visible = true
	if Kit.reduceMotion then return end
	local group = frame:FindFirstChildOfClass("CanvasGroup")
	if group then
		group.GroupTransparency = 1
		tween(group, { GroupTransparency = 0 }, 0.09)
	end
end

local function clamp(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

-- Hover + PRESSED on any button. Pass the button and its UIStroke. Every button
-- in the product had a hover colour and nothing else, so the click itself was
-- never acknowledged -- the cheapest thing that separates a real control from a
-- coloured rectangle.
function Kit.interactive(btn, strokeObj, baseColor)
	local base = baseColor or btn.BackgroundColor3
	local hoverCol = Kit.COL.rowHover
	local down = false
	local inside = false
	local function paint()
		local d = Kit.MOTION.fast
		if strokeObj then
			Kit.tween(strokeObj, { Color = (inside or down) and Kit.COL.white or Kit.COL.line }, d)
		end
		Kit.tween(btn, { BackgroundColor3 = down and Kit.COL.line or (inside and hoverCol or base) }, d)
	end
	btn.MouseEnter:Connect(function() inside = true; paint() end)
	btn.MouseLeave:Connect(function() inside = false; down = false; paint() end)
	btn.MouseButton1Down:Connect(function() down = true; paint() end)
	btn.MouseButton1Up:Connect(function() down = false; paint() end)
	return paint
end

-- Real text width. W.tabstrip used to size tabs as `14 + #name * 8`, a
-- character-count guess that clips any tab whose name is wide (or wastes space
-- on a narrow one). TextService measures the actual font.
function Kit.textWidth(text, size, font)
	local ok, v = pcall(function()
		return game:GetService("TextService"):GetTextSize(
			text, size, font or Enum.Font.GothamBold, Vector2.new(4000, 100)).X
	end)
	return ok and v or (#tostring(text) * size * 0.6)
end

function Kit.new(cls, props, parent)
	local o = Instance.new(cls)
	for k, v in pairs(props or {}) do
		o[k] = v
	end
	if parent then
		o.Parent = parent
	end
	return o
end
local new = Kit.new

function Kit.corner(o, r)
	new("UICorner", { CornerRadius = UDim.new(0, r or 8) }, o)
	return o
end
local corner = Kit.corner

-- returns the UIStroke, not the parent: callers recolour it on hover and on
-- select, and returning the parent makes every one of those a runtime error.
function Kit.stroke(o, col, t)
	return new("UIStroke", { Color = col or COL.line, Thickness = 1, Transparency = t or 0 }, o)
end
local stroke = Kit.stroke

function Kit.label(parent, text, size, col, x, y, w, h, align)
	return new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(w, h),
		Font = Enum.Font.GothamMedium,
		TextSize = size,
		TextColor3 = col or COL.text,
		Text = text,
		TextXAlignment = align or Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
	}, parent)
end
local label = Kit.label

--==========================================================================
-- Kit.host() -- the host-mount contract as ONE call
--
-- WHY: hub skill S6.1 states nine rules a module must obey to render inside
-- hub.lua. They were prose for ~25 modules and the same three broke every time
-- (measured across the CLI transcripts, 2026-09-01): RightShift not no-opped
-- (blank tab), a saved "hidden" blanking the tab, and an ESP folder reparented
-- into the panel (billboards clipped to a rectangle). Boilerplate the agent
-- retypes per port is boilerplate the agent gets wrong per port, so the rules
-- live here instead, where nobody has to remember them.
--
--   local H = Kit.host({ screen = screen, root = panel, keep = { S.folder } })
--   if not H.hosted then  -- standalone only: your own window chrome
--       makeDraggable(panel)
--   end
--   H.hideBind(function() panel.Visible = not panel.Visible end)  -- no-op hosted
--
-- Fields: H.hosted, H.frame (hub content host or nil), H.build, H.back,
--         H.ui (the hub's already-loaded kit), H.width, H.height, H.misparented.
--
-- What it does when hosted (S6.1 r2,3,4,5,8,9):
--   * parents `root` into the hub's host frame at 0,0
--   * fits a fixed-offset layout with a UIScale instead of reflowing it
--   * forces the root visible, so a saved "hidden" cannot blank the tab
--   * makes hideBind() inert -- the hub owns RightShift
--   * leaves every instance in `keep` where it is, and reports any that are
--     already inside the host in H.misparented
--   * takes the reparented root down with the module's own ScreenGui, so the
--     existing teardown does not have to be rewritten
--==========================================================================
function Kit.host(o)
	o = o or {}
	local H = o.hostGlobal
	if H == nil and getgenv then
		local ok, g = pcall(getgenv)
		if ok and type(g) == "table" then H = g.__R3ST_HOST end
	end
	local hosted = type(H) == "table" and typeof(H.host) == "Instance" and H.host.Parent ~= nil
	local out = {
		hosted = hosted,
		frame = hosted and H.host or nil,
		build = hosted and H.build or nil,
		back = hosted and H.back or nil,
		ui = hosted and H.ui or nil,
		width = hosted and H.width or nil,
		height = hosted and H.height or nil,
		misparented = {},
	}

	-- Inert when standalone: the module keeps its own hide key. Inert when
	-- hosted: the hub hides its own ScreenGui, and a module that also hides its
	-- root comes back to a blank tab (S6.1 r4).
	function out.hideBind(fn, keyCode)
		if hosted or type(fn) ~= "function" then return nil end
		local key = keyCode or Enum.KeyCode.RightShift
		return UserInputService.InputBegan:Connect(function(i, gpe)
			if gpe then return end
			if i.KeyCode == key then fn() end
		end)
	end

	if not hosted or not o.root then
		return out
	end

	local root, host = o.root, H.host

	-- r8: an ESP / adornment layer must stay a full-screen CoreGui layer. Report
	-- rather than move: silently reparenting someone's folder is the bug.
	for _, inst in ipairs(o.keep or {}) do
		if typeof(inst) == "Instance" and inst:IsDescendantOf(host) then
			out.misparented[#out.misparented + 1] = inst:GetFullName()
		end
	end

	local w = root.AbsoluteSize.X > 0 and root.AbsoluteSize.X or root.Size.X.Offset
	local h = root.AbsoluteSize.Y > 0 and root.AbsoluteSize.Y or root.Size.Y.Offset

	root.Parent = host
	root.AnchorPoint = Vector2.new(0, 0)
	root.Position = UDim2.fromOffset(0, 0)
	root.Visible = true -- r5
	if root:IsA("GuiObject") then root.Active = true end

	-- r3: fit by scaling, never by reflowing a proven page of controls.
	if o.scale ~= false and w > 0 and h > 0 then
		local hw = host.AbsoluteSize.X > 0 and host.AbsoluteSize.X or (H.width or w)
		local hh = host.AbsoluteSize.Y > 0 and host.AbsoluteSize.Y or (H.height or h)
		local s = math.min(hw / w, hh / h, 1)
		if s < 0.999 then
			local us = root:FindFirstChildOfClass("UIScale") or new("UIScale", {}, root)
			us.Scale = s
			out.scale = s
		end
	end

	-- r9: ride the module's existing teardown instead of editing six paths.
	if o.screen and o.screen ~= root then
		out.conn = o.screen.Destroying:Connect(function()
			if root and root.Parent then root:Destroy() end
		end)
	end

	return out
end

--==========================================================================
-- Kit.resizeGrip() -- bottom-right drag handle for a fixed-offset window
--
-- The hub was a hard 1180x700 with no way to change it, and the only sizing
-- control that existed (`uiScale`) had no UI at all. A grip is the consistent
-- answer because Kit.relayout already reflows cards into 1/2/3 columns by
-- width, so a wider window genuinely gains content instead of stretching.
--
--   Kit.resizeGrip(root, { min = Vector2.new(880, 520), onResize = fn,
--                          onCommit = fn })
--
-- Clamps to the viewport so a window can never be dragged bigger than the
-- screen and lost. onResize fires live (relayout); onCommit fires once on
-- release (save the size).
--==========================================================================
function Kit.resizeGrip(root, o)
	o = o or {}
	local minS = o.min or Vector2.new(880, 520)
	local grip = Kit.new("TextButton", {
		Name = "R3ST_Resize",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -2, 1, -2),
		Size = UDim2.fromOffset(18, 18),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 50,
	}, root)
	-- Three stacked ticks: the conventional grip read, drawn rather than glyphed
	-- so it cannot land on a font that has no such character.
	for i = 1, 3 do
		Kit.new("Frame", {
			BackgroundColor3 = COL.faint,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -2, 1, -2 - (i - 1) * 4),
			Size = UDim2.fromOffset(2 + (3 - i) * 5, 2),
			ZIndex = 51,
		}, grip)
	end

	local dragging, startPos, startSize = false, nil, nil
	local conns = {}
	conns[#conns + 1] = grip.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			startPos = i.Position
			startSize = Vector2.new(root.Size.X.Offset, root.Size.Y.Offset)
		end
	end)
	conns[#conns + 1] = UserInputService.InputChanged:Connect(function(i)
		if not dragging then return end
		if i.UserInputType ~= Enum.UserInputType.MouseMovement and i.UserInputType ~= Enum.UserInputType.Touch then return end
		local d = i.Position - startPos
		local w = startSize.X + d.X
		local h = startSize.Y + d.Y
		local cam = workspace.CurrentCamera
		local maxW, maxH = 4000, 4000
		if cam then
			maxW = math.max(minS.X, cam.ViewportSize.X - 24)
			maxH = math.max(minS.Y, cam.ViewportSize.Y - 24)
		end
		w = clamp(w, minS.X, maxW)
		h = clamp(h, minS.Y, maxH)
		root.Size = UDim2.fromOffset(w, h)
		if o.onResize then pcall(o.onResize, w, h) end
	end)
	conns[#conns + 1] = UserInputService.InputEnded:Connect(function(i)
		if not dragging then return end
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging = false
			if o.onCommit then pcall(o.onCommit, root.Size.X.Offset, root.Size.Y.Offset) end
		end
	end)
	return grip, conns
end

--==========================================================================
-- Layout state
--   One record per page: two columns of cards, the card each row goes into,
--   and how tall each column is. Cards are placed in the SHORTER column, so a
--   long section never leaves the other side empty.
--==========================================================================
local PAGE = setmetatable({}, { __mode = "k" })

local CARD_PAD = 12
local CARD_TOP = 34 -- title band inside a card
local GUTTER = 14

local function newCols(width, n)
	local colW = math.floor((width - GUTTER * (n - 1)) / n)
	local cols = {}
	for i = 1, n do
		cols[i] = { x = (i - 1) * (colW + GUTTER), y = 0, w = colW }
	end
	return cols
end

local function pageRec(page)
	local rec = PAGE[page]
	if not rec then
		-- A page used without W.page(): fall back to one full-width column.
		rec = { cols = newCols(math.max(page.AbsoluteSize.X - 8, 320), 1), cards = {}, card = nil,
			width = math.max(page.AbsoluteSize.X - 8, 320) }
		PAGE[page] = rec
	end
	return rec
end

-- Column count from the space we actually have, not from a legacy panel size.
local function columnsFor(width)
	if width >= 1000 then return 3 end
	if width >= 560 then return 2 end
	return 1
end

function Kit.page(page, o)
	o = o or {}
	local width = o.width or (page.AbsoluteSize.X > 0 and page.AbsoluteSize.X or 700)
	local n = o.columns or columnsFor(width)
	PAGE[page] = { cols = newCols(width, n), cards = {}, card = nil, width = width, fixedCols = o.columns }
	return page
end

function Kit.height(page)
	local rec = pageRec(page)
	local h = 0
	for _, c in ipairs(rec.cols) do
		if c.y > h then h = c.y end
	end
	return h
end

-- Shortest column wins the next card.
local function shortestCol(rec)
	local best = rec.cols[1]
	for _, c in ipairs(rec.cols) do
		if c.y < best.y then best = c end
	end
	return best
end

-- Re-flow every card for a new page width. Rows inside a card are sized in
-- SCALE, so only the cards themselves have to move: a resized hub tab fills its
-- width instead of scaling one fixed-width layout down and leaving a third of
-- the panel empty.
function Kit.relayout(page, width)
	local rec = PAGE[page]
	if not rec or width < 200 then
		return Kit.height(page)
	end
	if math.abs((rec.width or 0) - width) < 2 then
		return Kit.height(page)
	end
	rec.width = width
	rec.cols = newCols(width, rec.fixedCols or columnsFor(width))
	for _, card in ipairs(rec.cards) do
		local col = shortestCol(rec)
		card.col = col
		local h = card.frame.Size.Y.Offset
		card.frame.Position = UDim2.fromOffset(col.x, col.y)
		card.frame.Size = UDim2.fromOffset(col.w, h)
		col.y = col.y + h + GUTTER
	end
	return Kit.height(page)
end

local function grow(card, by)
	card.frame.Size = UDim2.fromOffset(card.col.w, card.y + by + CARD_PAD)
	card.y = card.y + by
	card.col.y = card.frame.Position.Y.Offset + card.frame.Size.Y.Offset + GUTTER
end

-- Rows before the first section() still need somewhere to live.
local function currentCard(page)
	local rec = pageRec(page)
	if not rec.card then
		Kit.section(page, "General")
	end
	return rec.card
end

function Kit.section(page, title)
	local rec = pageRec(page)
	local col = shortestCol(rec)
	local frame = new("Frame", {
		BackgroundColor3 = COL.card,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(col.x, col.y),
		Size = UDim2.fromOffset(col.w, CARD_TOP + CARD_PAD),
	}, page)
	corner(frame, 10)
	stroke(frame, COL.line)
	local t = label(frame, title, 15, COL.text, CARD_PAD, 8, 0, 22)
	t.Size = UDim2.new(1, -CARD_PAD * 2, 0, 22)
	t.Font = Enum.Font.GothamBold
	rec.card = { frame = frame, col = col, y = CARD_TOP, title = t }
	rec.cards[#rec.cards + 1] = rec.card
	col.y = col.y + frame.Size.Y.Offset + GUTTER
	return t
end

--==========================================================================
-- bind(): widgets wired to the CALLER's live/conns tables
--==========================================================================
function Kit.bind(host)
	host = host or {}
	local live = host.live or {}
	local conns = host.conns or {}
	local guard = host.guard or function(_, fn, ...)
		if type(fn) == "function" then
			local ok = pcall(fn, ...)
			return ok
		end
		return false
	end
	local W = { live = live, conns = conns, COL = COL }
	local drag = nil

	--======================================================================
	-- Autosave, owned by the kit
	--
	-- WHY: "my config is not saving" is the second of the three regressions
	-- every port hits (hub S9.0) -- 2614 mentions across the Cursor chats. It
	-- happens because persistence is a separate wire the porting agent has to
	-- remember for every control. Pass `cfg` (the module's own config table) and
	-- `save` (its own writer) to bind(), then give a widget a `key`: the kit
	-- reads the stored value on build, writes it on change, and coalesces the
	-- save. No control can be ported without its persistence again.
	--
	--   local W = Kit.bind({ live=..., conns=..., cfg = CFG, save = saveConfig })
	--   W.toggle(page, { label = "ESP", key = "esp", set = applyEsp })
	--
	-- `get`/`set` still win when supplied, so an existing proven wiring is never
	-- overridden -- `set` is called AFTER the store is updated, so the module's
	-- apply function sees the new value.
	--======================================================================
	local cfg, saveFn = host.cfg, host.save
	local savePending = false
	local function scheduleSave()
		if not saveFn or savePending then return end
		savePending = true
		task.delay(host.saveDelay or 0.75, function()
			savePending = false
			guard("ui.autosave", saveFn)
		end)
	end
	W.cfg = cfg
	W.saveNow = function()
		if saveFn then guard("ui.autosave", saveFn) end
	end

	-- Returns the get/set pair a widget should actually use.
	local function wire(o, default)
		if not (o.key and cfg) then
			return o.get, o.set
		end
		if cfg[o.key] == nil then
			cfg[o.key] = (o.default ~= nil) and o.default or default
		end
		local get = o.get or function() return cfg[o.key] end
		local set = function(v)
			cfg[o.key] = v
			if o.set then o.set(v) end
			scheduleSave()
		end
		return get, set
	end

	local function addLive(fn)
		live[#live + 1] = fn
	end
	local function addConn(c)
		conns[#conns + 1] = c
	end

	W.page = Kit.page
	W.height = Kit.height
	W.relayout = Kit.relayout
	W.section = Kit.section
	W.new, W.corner, W.stroke, W.label = Kit.new, Kit.corner, Kit.stroke, Kit.label

	-- one shared drag owner for every slider on the page
	addConn(UserInputService.InputChanged:Connect(function(i)
		if drag and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
			drag.setFromX(i.Position.X)
		end
	end))
	addConn(UserInputService.InputEnded:Connect(function(i)
		if drag and (i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch) then
			local d = drag
			drag = nil
			if d.commit then
				guard("ui.slider.commit", d.commit)
			end
		end
	end))

	local function rowBox(page, h)
		local card = currentCard(page)
		-- Scale width: the card owns the pixels, the row just fills it, so a
		-- relayout never has to touch a single row.
		local box = new("Frame", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(CARD_PAD, card.y),
			Size = UDim2.new(1, -CARD_PAD * 2, 0, h),
		}, card.frame)
		grow(card, h + 6)
		return box, card
	end

	-- Template toggle: label left, pill switch hard right.
	function W.toggle(page, o)
		local get, set = wire(o, false)
		local h = o.desc and 44 or 34
		local box = rowBox(page, h)
		local name = label(box, o.label, 13, COL.text, 0, o.desc and 2 or 0, 0, o.desc and 18 or h)
		name.Size = UDim2.new(1, -60, 0, o.desc and 18 or h)
		if o.desc then
			local d = label(box, o.desc, 10, COL.dim, 0, 22, 0, 16)
			d.Size = UDim2.new(1, -60, 0, 16)
			d.TextTruncate = Enum.TextTruncate.AtEnd
		end
		local track = new("TextButton", {
			BackgroundColor3 = COL.row,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, 0, 0.5, 0),
			Size = UDim2.fromOffset(46, 24),
			Text = "",
			AutoButtonColor = false,
		}, box)
		corner(track, 12)
		local st = stroke(track, COL.line)
		local knob = new("Frame", {
			BackgroundColor3 = COL.knobOff,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 3, 0.5, 0),
			Size = UDim2.fromOffset(18, 18),
		}, track)
		corner(knob, 9)
		-- redraw() is also called every frame by addLive, so it must not restart a
		-- tween on a value that did not change: `lastOn` is what makes the knob
		-- animate on a click and stay still otherwise. nil means "first paint" --
		-- a page opening shows its switches already in position rather than
		-- playing twenty of them at once.
		local lastOn = nil
		local function redraw()
			local on = get() and true or false
			if on == lastOn then return end
			local d = (lastOn == nil) and 0 or Kit.MOTION.fast
			lastOn = on
			tween(knob, {
				Position = UDim2.new(0, on and 25 or 3, 0.5, 0),
				BackgroundColor3 = on and COL.white or COL.knobOff,
			}, d)
			tween(track, { BackgroundColor3 = on and Color3.fromRGB(70, 72, 78) or COL.row }, d)
			tween(st, { Color = on and COL.white or COL.line }, d)
			tween(name, { TextColor3 = on and COL.text or COL.dim }, d)
		end
		track.MouseButton1Click:Connect(function()
			set(not get())
			redraw()
		end)
		redraw()
		o.redraw = redraw
		addLive(function()
			if box.Parent and page.Visible then redraw() end
		end)
		return box
	end

	-- Template slider: label left, value right, full-width track underneath.
	-- `tradeoff` / `live` add the two explanation lines gd2 relies on.
	function W.slider(page, o)
		local get, set = wire(o, o.min)
		local h = 40 + (o.tradeoff and 12 or 0) + (o.live and 12 or 0)
		local box = rowBox(page, h)
		local name = label(box, o.label, 13, COL.text, 0, 0, 0, 18)
		name.Size = UDim2.new(1, -130, 0, 18)
		local val = label(box, "", 13, COL.white, 0, 0, 130, 18, Enum.TextXAlignment.Right)
		val.AnchorPoint = Vector2.new(1, 0)
		val.Position = UDim2.new(1, 0, 0, 0)
		val.Font = Enum.Font.GothamBold

		local track = new("Frame", {
			BackgroundColor3 = COL.row,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(0, 26),
			Size = UDim2.new(1, 0, 0, 6),
		}, box)
		corner(track, 3)
		local fill = new("Frame", { BackgroundColor3 = COL.white, BorderSizePixel = 0, Size = UDim2.fromScale(0, 1) }, track)
		corner(fill, 3)
		local knob = new("Frame", {
			BackgroundColor3 = COL.white,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0, 0, 0.5, 0),
			Size = UDim2.fromOffset(12, 12),
		}, track)
		corner(knob, 6)
		local mark
		if o.stock then
			mark = new("Frame", {
				BackgroundColor3 = COL.dim, BorderSizePixel = 0, ZIndex = 2,
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 0, 0.5, 0),
				Size = UDim2.fromOffset(2, 12),
			}, track)
		end
		local y2 = 38
		if o.tradeoff then
			local tl = label(box, o.tradeoff, 10, COL.dim, 0, y2, 0, 12)
			tl.Size = UDim2.new(1, 0, 0, 12)
			tl.TextTruncate = Enum.TextTruncate.AtEnd
			y2 = y2 + 12
		end
		local liveLbl
		if o.live then
			liveLbl = label(box, "", 10, COL.dim, 0, y2, 0, 12)
			liveLbl.Size = UDim2.new(1, 0, 0, 12)
		end

		local function frac(v)
			return clamp((v - o.min) / math.max(o.max - o.min, 1e-6), 0, 1)
		end
		local function redraw()
			local v = get()
			local f = frac(v)
			fill.Size = UDim2.fromScale(f, 1)
			knob.Position = UDim2.new(f, 0, 0.5, 0)
			val.Text = o.fmt and o.fmt(v) or tostring(v)
			if mark then mark.Position = UDim2.new(frac(o.stock()), 0, 0.5, 0) end
			if liveLbl and o.live then liveLbl.Text = o.live(v) or "" end
		end
		o.redraw = redraw
		o.setFromX = function(px)
			local f = clamp((px - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
			local v = o.min + f * (o.max - o.min)
			if o.step then
				v = math.floor(v / o.step + 0.5) * o.step
			end
			set(clamp(v, o.min, o.max))
			redraw()
		end
		local function grab(i)
			if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
				drag = o
				o.setFromX(i.Position.X)
			end
		end
		track.InputBegan:Connect(grab)
		box.InputBegan:Connect(function(i)
			if math.abs(i.Position.Y - (track.AbsolutePosition.Y + 3)) < 12 then grab(i) end
		end)
		if o.stock then
			-- double-click the value to go back to stock
			val.Active = true
		end
		redraw()
		addLive(function()
			if box.Parent and page.Visible then redraw() end
		end)
		return box
	end

	function W.button(page, text, desc, fn, wide)
		local box = rowBox(page, desc and 48 or 32)
		local b = new("TextButton", {
			BackgroundColor3 = COL.row,
			BorderSizePixel = 0,
			Size = wide and UDim2.new(1, 0, 0, 30) or UDim2.fromOffset(200, 30),
			Font = Enum.Font.GothamMedium,
			TextSize = 12,
			TextColor3 = COL.text,
			Text = text,
			AutoButtonColor = false,
		}, box)
		corner(b, 7)
		local s = stroke(b, COL.line)
		-- Hover, and a real PRESSED state. Every button in the product had hover
		-- only, so nothing on screen ever acknowledged the click itself.
		Kit.interactive(b, s)
		b.MouseButton1Click:Connect(function() guard("ui.button." .. tostring(text), fn) end)
		if desc then
			local d = label(box, desc, 10, COL.dim, 0, 32, 0, 14)
			d.Size = UDim2.new(1, 0, 0, 14)
			d.TextTruncate = Enum.TextTruncate.AtEnd
		end
		return b
	end

	function W.note(page, text)
		local card = currentCard(page)
		local l = label(card.frame, text, 10, COL.dim, CARD_PAD, card.y, 0, 26)
		l.Size = UDim2.new(1, -CARD_PAD * 2, 0, 26)
		l.TextWrapped = true
		l.TextYAlignment = Enum.TextYAlignment.Top
		grow(card, 30)
		return l
	end

	function W.statusRow(page, getText)
		local card = currentCard(page)
		local l = label(card.frame, "", 11, COL.dim, CARD_PAD, card.y, 0, 26)
		l.Size = UDim2.new(1, -CARD_PAD * 2, 0, 26)
		l.TextWrapped = true
		l.TextYAlignment = Enum.TextYAlignment.Top
		grow(card, 30)
		addLive(function()
			if l.Parent and page.Visible then l.Text = getText() or "" end
		end)
		return l
	end

	--======================================================================
	-- Chrome: header, tab strip, footer
	--======================================================================

	-- Game identity comes from Roblox, never a hardcoded third-party image
	-- (hub skill S4): GameIcon thumbnail first, Marketplace icon as fallback.
	function W.header(parent, o)
		local h = new("Frame", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 76),
		}, parent)
		local icon = new("ImageLabel", {
			BackgroundColor3 = COL.card,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(0, 6),
			Size = UDim2.fromOffset(64, 64),
			ScaleType = Enum.ScaleType.Crop,
		}, h)
		corner(icon, 10)
		if o.gameId then
			icon.Image = "rbxthumb://type=GameIcon&id=" .. tostring(o.gameId) .. "&w=150&h=150"
		end
		if o.placeId then
			task.spawn(function()
				local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, o.placeId)
				if ok and type(info) == "table" and tonumber(info.IconImageAssetId)
					and tonumber(info.IconImageAssetId) > 0 and icon.Parent then
					icon.Image = "rbxassetid://" .. tostring(info.IconImageAssetId)
				end
			end)
		end
		local title = label(h, o.title or "", 22, COL.text, 78, 8, 420, 28)
		title.Font = Enum.Font.GothamBold
		label(h, o.version or "", 11, COL.dim, 78, 36, 300, 16)
		label(h, o.subtitle or "", 11, COL.dim, 78, 52, 460, 16)
		local info
		if o.onInfo then
			info = new("TextButton", {
				BackgroundColor3 = COL.card,
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, 0, 0, 20),
				Size = UDim2.fromOffset(150, 38),
				Font = Enum.Font.GothamMedium,
				TextSize = 12,
				TextColor3 = COL.text,
				Text = "ⓘ  Script Info",
				AutoButtonColor = false,
			}, h)
			corner(info, 8)
			local s = stroke(info, COL.line)
			info.MouseEnter:Connect(function() s.Color = COL.white end)
			info.MouseLeave:Connect(function() s.Color = COL.line end)
			info.MouseButton1Click:Connect(function() guard("ui.header.info", o.onInfo) end)
		end
		return h, title, info
	end

	-- Horizontal tab strip: how a module with more controls than one screen
	-- (gd2) splits itself while staying one template.
	function W.tabstrip(parent, o)
		local strip = new("Frame", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = o.position or UDim2.fromOffset(0, 0),
			Size = UDim2.new(1, 0, 0, 34),
		}, parent)
		local btns = {}
		local x = 0
		local painted = false
		local function paint()
			local cur = o.get()
			local d = painted and Kit.MOTION.fast or 0
			painted = true
			for name, rec in pairs(btns) do
				local on = (name == cur)
				tween(rec.b, {
					BackgroundColor3 = on and COL.white or COL.card,
					TextColor3 = on and COL.bg or COL.dim,
				}, d)
				tween(rec.s, { Color = on and COL.white or COL.line }, d)
			end
		end
		for _, name in ipairs(o.names) do
			-- Measured, not guessed: `14 + #name * 8` clipped any wide tab name.
			local w = math.max(72, math.ceil(Kit.textWidth(name, 11)) + 22)
			local b = new("TextButton", {
				BackgroundColor3 = COL.card,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(x, 0),
				Size = UDim2.fromOffset(w, 30),
				Font = Enum.Font.GothamBold,
				TextSize = 11,
				TextColor3 = COL.dim,
				Text = name,
				AutoButtonColor = false,
			}, strip)
			corner(b, 7)
			local s = stroke(b, COL.line)
			btns[name] = { b = b, s = s }
			b.MouseButton1Click:Connect(function()
				o.set(name)
				paint()
			end)
			x = x + w + 6
		end
		paint()
		return strip, paint
	end

	-- Footer: the two controls the template puts at the bottom of every module.
	function W.footer(parent, o)
		local f = new("Frame", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 0, 1, 0),
			Size = UDim2.new(1, 0, 0, 44),
		}, parent)
		new("Frame", { BackgroundColor3 = COL.line, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 1) }, f)
		local function chip(text, anchorRight, width, fn)
			local b = new("TextButton", {
				BackgroundColor3 = COL.card,
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(anchorRight and 1 or 0, 0.5),
				Position = UDim2.new(anchorRight and 1 or 0, 0, 0.5, 4),
				Size = UDim2.fromOffset(width, 32),
				Font = Enum.Font.GothamMedium,
				TextSize = 12,
				TextColor3 = COL.text,
				Text = text,
				AutoButtonColor = false,
			}, f)
			corner(b, 8)
			local s = stroke(b, COL.line)
			b.MouseEnter:Connect(function() s.Color = COL.white end)
			b.MouseLeave:Connect(function() s.Color = COL.line end)
			b.MouseButton1Click:Connect(function() guard("ui.footer." .. text, fn) end)
			return b
		end
		local unload, settings
		if o.onUnload then unload = chip("☐  Unload Script", false, 170, o.onUnload) end
		if o.onSettings then settings = chip("⚙  UI Settings", true, 150, o.onSettings) end
		if o.hint then
			local l = label(f, o.hint, 10, COL.dim, 184, 12, 420, 28)
			l.TextWrapped = true
		end
		return f, unload, settings
	end

	return W
end

return Kit
