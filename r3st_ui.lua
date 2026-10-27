-- R3ST UI kit v2026-10-26.6-studio
-- Changelog: 2026-10-26.6-studio Full-size panel motion; deduplicated, cancellable tweens.
-- Changelog: 2026-10-26.5-studio Promote approved motion and palette to the shared kit.
-- Changelog: 2026-10-26.5-studio Glide transitions, spring releases, staggered entrances.
-- Changelog: 2026-10-26.3-studio Deeper violet accent, one step larger type scale.
-- Changelog: 2026-10-26.2-studio Iris accent, Builder Sans type, softer graphite ladder.
-- Changelog: 2026-10-26.1-health Skip hidden panels; cache slider paints; status at 4 Hz.
-- Changelog: 2026-10-25.1 Coherent rounded Frame icons on a 24-unit grid.
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
--   W.search(parent, { placeholder=, text=, changed=, size=, position= })
--   W.chips(parent, { names=, counts=, get=, set=, position= })
--   W.card(parent, { title=, desc=, active=, activated=, size=, position=, index= })
--   W.empty(parent, { title=, desc=, size=, position= })
--   W.badge(parent, { text=, active=, size=, position= })
--   W.switch(parent, { get=, set=, size=, position= })
--   W.group(page)                                  -- titleless card
--   W.row(page, height)                             -- custom content slot
--   W.keybind(page, { label=, get=, set=, key=, default= })
--     Optional onCapture/capturing/onCancel delegate capture to an existing controller.
--   W.number(page, { label=, get=, set=, key=, default=, text=, min=, max=, commit= })
--     Returns TextBox; commit runs after validation, including invalid input.
--
--   `live` and `conns` are the CALLER's tables, so the caller's existing
--   refresh loop and teardown keep working unchanged. That is what let gd2.lua
--   adopt the template without touching a single page builder.
--
-- Signatures match the widgets gd2.lua already had, on purpose: adopting the
-- template must never mean rewriting a proven page of controls.

local Kit = {}
Kit.VERSION = "2026-10-26.6-studio"

-- The version of the module-shell contract this kit implements. hub.lua and
-- tools/check_hub.py assert on it; a module built against a different one is a
-- gate failure, not a runtime guess. Bump only when the shape of
-- Kit.moduleShell's return value or its stamped attributes changes.
Kit.SHELL_CONTRACT = "1"

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
-- ELEVATION LADDER -- each step must be a VISIBLE lift off the one below.
--   bg(9) window ground < panel(20) sidebar/content < card(30) < row(40)
--
-- The first attempt at this ladder was 7/13/17/24 and the user's verdict was
-- "UI changes don't seem very noticeable" -- correctly, because steps of 4-6
-- sRGB values are below the perceptual threshold on a dark surface. Dark UI
-- needs ~10 values per step to read as a separate plane. Anything tighter is a
-- ladder in the source and a flat black rectangle on screen.
--
-- `line` moved 42 -> 58 for the same reason: at 42 against a 30 card the border
-- was not defining an edge, so cards had no shape of their own.
--==========================================================================
--
-- STUDIO (2026-10-26.2): one chromatic accent joins the ladder. Pure-white
-- "on" states made every active control shout at the same volume as text, so
-- selection, focus and value now share the iris accent and white is left for
-- type and knobs. The ladder is cool graphite with ~10-value steps.
--==========================================================================
Kit.COL = {
	bg = Color3.fromRGB(9, 9, 13),
	panel = Color3.fromRGB(17, 17, 23),
	card = Color3.fromRGB(26, 26, 35),
	row = Color3.fromRGB(37, 37, 49),
	rowHover = Color3.fromRGB(49, 49, 64),
	line = Color3.fromRGB(50, 50, 66),
	lineSoft = Color3.fromRGB(36, 36, 48),
	lineStrong = Color3.fromRGB(86, 88, 112),
	text = Color3.fromRGB(238, 239, 246),
	dim = Color3.fromRGB(150, 152, 172),
	faint = Color3.fromRGB(104, 106, 126),
	white = Color3.fromRGB(255, 255, 255),
	good = Color3.fromRGB(74, 222, 128),
	bad = Color3.fromRGB(248, 113, 113),
	warn = Color3.fromRGB(251, 191, 36),
	knobOff = Color3.fromRGB(120, 122, 142),
	accent = Color3.fromRGB(84, 66, 196),
	accentHover = Color3.fromRGB(102, 84, 218),
	accentSoft = Color3.fromRGB(30, 24, 58),
	accentText = Color3.fromRGB(168, 152, 250),
}
-- Aliases so hub.lua's historic names resolve to the SAME colour instead of a
-- near-miss of it. Adding names is safe; renaming would break gd2/blr mid-port.
Kit.COL.raised = Kit.COL.card
Kit.COL.hover = Kit.COL.row
Kit.COL.green = Kit.COL.good
Kit.T = Kit.COL
Kit.RADIUS = { small = 6, control = 8, card = 12, window = 14, pill = 999 }
local COL = Kit.T

-- Five sizes, not ten. Screenshot audit found 10/11/12/13/14/15/18/19/22/24 in
-- use across hub.lua alone; a scale nobody can recite is a scale nobody applies.
Kit.TYPE = { micro = 11, small = 12, body = 14, head = 16, title = 24 }

-- 4px grid. Every offset in new layout code is one of these.
Kit.SPACE = { xs = 4, sm = 8, md = 12, lg = 16, xl = 24, xxl = 32 }

--==========================================================================
-- SEMANTIC TYPE -- a role, not a size-and-weight pair
--
-- Kit.TYPE shipped on 2026-09-01 and had ZERO consumers a full audit later:
-- every widget in this file still passed a raw literal, and across the registry
-- six font families (Gotham, GothamMedium, GothamSemibold, GothamBold,
-- GothamBlack, Code) and fourteen text sizes (9..26) were in use at once. A
-- scale nobody calls is not a scale.
--
-- So the widgets below ask for a ROLE and get both properties. There is no call
-- site left that picks a font and a size independently, which is the only way
-- this stays true after the next module lands.
--
-- Weight ladder is deliberate: everything a user reads as a LABEL is bold, and
-- only supporting prose is medium. The product read as flat because its
-- dominant weight was GothamMedium at 10-13px -- every toggle label, every
-- description, every note and status row. Bold is the default here, not the
-- exception.
--==========================================================================
-- Builder Sans is Roblox's own UI face and reads cleaner than Gotham at 11-13px.
-- Resolved through pcall so an older client without it falls back to Gotham
-- instead of erroring at load.
local function font(name, fallback)
	local ok, f = pcall(function() return Enum.Font[name] end)
	return ok and f or fallback
end
Kit.FONT = {
	bold = font("BuilderSansBold", Enum.Font.GothamBold),
	semi = font("BuilderSansMedium", Enum.Font.GothamMedium),
	body = font("BuilderSans", Enum.Font.Gotham),
	heavy = font("BuilderSansExtraBold", Enum.Font.GothamBlack),
	mono = font("RobotoMono", Enum.Font.Code),
}
Kit.ROLE = {
	title   = { size = Kit.TYPE.title, font = Kit.FONT.heavy }, -- module name
	heading = { size = Kit.TYPE.head,  font = Kit.FONT.bold },  -- card title
	control = { size = Kit.TYPE.body,  font = Kit.FONT.bold },  -- toggle/slider label
	value   = { size = Kit.TYPE.body,  font = Kit.FONT.bold },  -- the number a slider shows
	body    = { size = Kit.TYPE.body,  font = Kit.FONT.semi },  -- prose
	caption = { size = Kit.TYPE.small, font = Kit.FONT.semi },  -- desc / note / status
	micro   = { size = Kit.TYPE.micro, font = Kit.FONT.semi },  -- legal-print only
	tab     = { size = Kit.TYPE.small, font = Kit.FONT.bold },
	mono    = { size = Kit.TYPE.body,  font = Kit.FONT.mono },  -- command input
}

-- Apply a role to any TextLabel/TextButton after the fact.
function Kit.role(obj, name)
	local r = Kit.ROLE[name]
	if not (r and obj) then return obj end
	pcall(function()
		obj.TextSize = r.size
		obj.Font = r.font
	end)
	return obj
end

--==========================================================================
-- MOTION
--
-- Before 2026-09-01 the entire product -- hub, kit, gd2, blr, anims, admin --
-- contained zero TweenService calls. Everything snapped. That single fact was
-- most of the "not premium" feeling.
--
-- Short Quad curves keep motion continuous without overshoot or a long tail.
-- Move panels at their final size; never rescale text-heavy UI during a reveal.
-- The spring/glide names remain compatible aliases for existing module callers.
--
-- Kit.reduceMotion = true makes every helper below apply the final value
-- instantly, so the setting is honoured without a branch at each call site.
--==========================================================================
Kit.MOTION = { fast = 0.12, base = 0.20, slow = 0.24, spring = 0.22, exit = 0.14 }
Kit.reduceMotion = false

Kit.EASE = {
	out = { Enum.EasingStyle.Quad, Enum.EasingDirection.Out },
	spring = { Enum.EasingStyle.Quad, Enum.EasingDirection.Out },
	["in"] = { Enum.EasingStyle.Quad, Enum.EasingDirection.In },
	glide = { Enum.EasingStyle.Quad, Enum.EasingDirection.Out },
}

-- Returns the Tween so a caller can wait on Completed; nil when motion is off.
-- style: a Kit.EASE name (default "out") or an Enum.EasingStyle.
local activeMotion = setmetatable({}, { __mode = "k" })
function Kit.cancelMotion(obj, property)
	local active = activeMotion[obj]
	if not active then return end
	local pending = {}
	for key, rec in pairs(active) do
		if not property or key == property then pending[rec] = true end
	end
	for rec in pairs(pending) do rec.tween:Cancel() end
end
function Kit.tween(obj, props, dur, style)
	if typeof(obj) ~= "Instance" then return nil end
	local active = activeMotion[obj] or {}
	activeMotion[obj] = active
	if Kit.reduceMotion or dur == 0 then
		for k, v in pairs(props) do
			Kit.cancelMotion(obj, k)
			pcall(function() obj[k] = v end)
		end
		return nil
	end
	local changed, existing = {}, nil
	for k, v in pairs(props) do
		local rec = active[k]
		if rec and rec.goals[k] == v then
			existing = rec.tween
		elseif obj[k] ~= v or rec then
			changed[k] = v
		end
	end
	if not next(changed) then return existing end
	-- Restart the full requested group if one target changed, not a stranded subset.
	for k in pairs(props) do Kit.cancelMotion(obj, k) end
	changed = {}
	for k, v in pairs(props) do if obj[k] ~= v then changed[k] = v end end
	if not next(changed) then return nil end
	local ease = Kit.EASE[style or "out"]
	local info = typeof(style) == "EnumItem"
		and TweenInfo.new(dur or Kit.MOTION.base, style, Enum.EasingDirection.Out)
		or TweenInfo.new(dur or Kit.MOTION.base, (ease or Kit.EASE.out)[1], (ease or Kit.EASE.out)[2])
	local t = TweenService:Create(obj, info, changed)
	local rec = { tween = t, goals = changed }
	for k in pairs(changed) do active[k] = rec end
	t.Completed:Once(function()
		for k in pairs(changed) do
			if active[k] == rec then active[k] = nil end
		end
	end)
	t:Play()
	return t
end
local tween = Kit.tween

-- Panels move as a single surface; text and mounted widgets stay full-sized.
local panelMotion = setmetatable({}, { __mode = "k" })
function Kit.appear(frame, scaleObj, done)
	local previous = panelMotion[frame]
	local rec = { base = previous and previous.active and previous.base or frame.Position, active = true }
	panelMotion[frame] = rec
	if scaleObj then
		Kit.cancelMotion(scaleObj, "Scale")
		scaleObj.Scale = scaleObj:GetAttribute("R3ST_TargetScale") or scaleObj.Scale
	end
	local t = Kit.pageIn(frame, 1, rec.base)
	local function finish(status)
		if panelMotion[frame] ~= rec then return end
		rec.active = false
		if done and (not status or status == Enum.PlaybackState.Completed) then done() end
	end
	if t then t.Completed:Once(finish) else finish() end
end

-- Close is faster than open: getting out of the way should never feel slow.
function Kit.vanish(frame, scaleObj, done)
	local previous = panelMotion[frame]
	local rec = { base = previous and previous.active and previous.base or frame.Position, active = true }
	panelMotion[frame] = rec
	Kit.cancelMotion(frame)
	if scaleObj then
		Kit.cancelMotion(scaleObj, "Scale")
		scaleObj.Scale = scaleObj:GetAttribute("R3ST_TargetScale") or scaleObj.Scale
	end
	local props = { Position = rec.base + UDim2.fromOffset(0, 6) }
	if frame:IsA("CanvasGroup") then props.GroupTransparency = 1 end
	local t = tween(frame, props, Kit.MOTION.exit, "in")
	local function finish(status)
		if panelMotion[frame] ~= rec then return end
		rec.active = false
		if status and status ~= Enum.PlaybackState.Completed then return end
		frame.Visible = false
		frame.Position = rec.base
		if done then done() end
	end
	if t then t.Completed:Once(finish) else finish() end
end

-- Page transitions keep position and opacity on separate curves. Plain Frames
-- glide; CanvasGroups also fade as one object, without walking descendants.
-- Cancel old writers before replaying so rapid navigation cannot drift.
-- dir: 1 slides up from below, -1 down from above (follow the nav direction).
local pageMotion = setmetatable({}, { __mode = "k" })
function Kit.pageIn(frame, dir, origin)
	Kit.cancelMotion(frame)
	local previous = pageMotion[frame]
	local base = origin or (previous and previous.base) or frame.Position
	if previous then
		if previous.tween then previous.tween:Cancel() end
		if previous.fade then previous.fade:Cancel() end
	end
	frame.Visible = true
	frame.Position = base
	if frame:IsA("CanvasGroup") then frame.GroupTransparency = 0 end
	if Kit.reduceMotion then
		pageMotion[frame] = { base = base }
		return
	end
	frame.Position = base + UDim2.fromOffset(0, 10 * (dir or 1))
	local fade
	if frame:IsA("CanvasGroup") then
		frame.GroupTransparency = 1
		fade = tween(frame, { GroupTransparency = 0 }, Kit.MOTION.base)
	end
	local motion = tween(frame, { Position = base }, Kit.MOTION.base, "glide")
	pageMotion[frame] = { base = base, fade = fade, tween = motion }
	return motion
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
-- Kit.new is declared ~80 lines BELOW this point, so a call to `new(...)` from
-- here resolves to a nil GLOBAL: compiles clean, dies on the first press. That
-- exact class is in the AGENTS.md mistake ledger ("nil forward reference"), so
-- the two motion helpers use this instead of reaching forward.
local function attachScale(obj)
	local s = obj:FindFirstChildOfClass("UIScale")
	if not s then
		s = Instance.new("UIScale")
		s.Scale = 1
		s.Parent = obj
	end
	return s
end

function Kit.interactive(btn, strokeObj, baseColor, options)
	options = options or {}
	local base = baseColor or btn.BackgroundColor3
	local hoverCol = Kit.COL.rowHover
	local down = false
	local inside = false
	local focused = false
	-- Colour acknowledges focus; scale acknowledges a physical press. A quick
	-- sink and a longer spring release keep rapid clicks responsive.
	local scale = btn:FindFirstChildOfClass("UIScale")
	local wasDown = false
	local function paint()
		local d = Kit.MOTION.fast
		local resting = options.base and options.base() or base
		local edge = options.edge and options.edge() or Kit.COL.line
		local hovered = inside or focused
		local surface = options.hover and options.hover() or hoverCol
		if strokeObj then
			-- An active control keeps its own edge on hover; a resting one lifts.
			local lifted = (edge == Kit.COL.line) and Kit.COL.lineStrong or edge
			Kit.tween(strokeObj, { Color = down and Kit.COL.accent
				or (hovered and lifted or edge) }, d)
		end
		Kit.tween(btn, { BackgroundColor3 = down and surface
			or (hovered and surface or resting) }, d)
		-- Press sinks fast; release springs back past rest and settles.
		if scale then
			if down then
				Kit.tween(scale, { Scale = 0.98 }, 0.08)
			elseif wasDown then
				Kit.tween(scale, { Scale = 1 }, Kit.MOTION.spring, "spring")
			else
				Kit.tween(scale, { Scale = 1 }, d)
			end
		end
		wasDown = down
	end
	btn.SelectionGained:Connect(function() focused = true; paint() end)
	btn.SelectionLost:Connect(function() focused = false; down = false; paint() end)
	btn.MouseEnter:Connect(function() inside = true; paint() end)
	btn.MouseLeave:Connect(function() inside = false; down = false; paint() end)
	btn.MouseButton1Down:Connect(function()
		down = true
		-- Create the UIScale lazily: a button that is never pressed never pays for
		-- one, and adding it here keeps every existing call site working unchanged.
		if not scale and btn.AbsoluteSize.X <= 240 and btn.AbsoluteSize.Y <= 80 then
			scale = attachScale(btn)
		end
		paint()
	end)
	btn.MouseButton1Up:Connect(function() down = false; paint() end)
	return paint
end

-- Hover lift for a card / row: brighten the border and raise the surface a step.
-- Cards had no hover state at all, so a two-column grid of them read as wallpaper
-- rather than as things you can interact with.
function Kit.hoverable(frame, strokeObj, baseColor, hoverColor)
	local base = baseColor or frame.BackgroundColor3
	local hov = hoverColor or Kit.COL.rowHover
	local function paint(on)
		Kit.tween(frame, { BackgroundColor3 = on and hov or base }, Kit.MOTION.fast)
		if strokeObj then
			Kit.tween(strokeObj, { Color = on and Kit.COL.lineStrong or Kit.COL.line }, Kit.MOTION.fast)
		end
	end
	frame.MouseEnter:Connect(function() paint(true) end)
	frame.MouseLeave:Connect(function() paint(false) end)
	return paint
end

-- Cards share the page entrance: no delayed scale writers or text resampling.
function Kit.enter(frame, _index)
	-- Layout-owned cards reveal with their page, not ten independent size changes.
	-- Keep this compatibility entry point for existing modules and old UI scales.
	local scale = frame:FindFirstChildOfClass("UIScale")
	if scale then
		Kit.cancelMotion(scale, "Scale")
		scale.Scale = 1
	end
end

-- Real text width. W.tabstrip used to size tabs as `14 + #name * 8`, a
-- character-count guess that clips any tab whose name is wide (or wastes space
-- on a narrow one). TextService measures the actual font.
function Kit.textWidth(text, size, font)
	local ok, v = pcall(function()
		return game:GetService("TextService"):GetTextSize(
			text, size, font or Kit.FONT.bold, Vector2.new(4000, 100)).X
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
	new("UICorner", { CornerRadius = UDim.new(0, r or Kit.RADIUS.control) }, o)
	return o
end
local corner = Kit.corner

-- returns the UIStroke, not the parent: callers recolour it on hover and on
-- select, and returning the parent makes every one of those a runtime error.
function Kit.stroke(o, col, t)
	return new("UIStroke", { Color = col or COL.line, Thickness = 1, Transparency = t or 0 }, o)
end
local stroke = Kit.stroke

--==========================================================================
-- ICONS -- drawn, never a glyph (hub skill S9.3)
--
-- The sidebar shipped `⌂ ☆ ◷ ⚙ ⓘ ◇ >_` as its icons, and the row controls
-- shipped `★ ☆ ▶ — × ✓ − +`. Every one of them renders as a tofu box on the
-- user's machine -- confirmed in their 2026-09-01 screenshot, where Recent is an
-- empty rectangle. A font we do not ship is not a decision we get to make, so
-- these are built out of Frames: bars, rotated bars and circles. They inherit no
-- font, they cannot fall back, and they scale with their box.
--
--   local ic = Kit.icon(parent, "home", { size = 16, color = COL.dim })
--   Kit.iconColor(ic, COL.text)
--
-- `size` is the square box in pixels; every part is positioned in SCALE inside
-- it, so one definition serves a 12px row badge and a 20px header alike.
--==========================================================================
local ICON_STROKE = 2.25 -- 1.5px at 16px; every outline and bar shares this weight.
local function ipart(box, x, y, w, h, rot, opts)
	opts = opts or {}
	local f = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(x, y),
		Size = UDim2.fromScale(w, h),
		Rotation = rot or 0,
		BackgroundColor3 = opts.color or Color3.new(1, 1, 1),
		BackgroundTransparency = opts.hollow and 1 or 0,
		BorderSizePixel = 0,
	}, box)
	if opts.round then
		new("UICorner", { CornerRadius = UDim.new(opts.round, 0) }, f)
	end
	if opts.hollow then
		-- Marked so iconColor recolours the outline instead of the fill.
		f:SetAttribute("R3ST_IconHollow", true)
		new("UIStroke", {
			Color = opts.color or Color3.new(1, 1, 1),
			Thickness = box.Size.X.Offset * ICON_STROKE / 24,
			BorderStrokePosition = Enum.BorderStrokePosition.Center,
		}, f)
	end
	return f
end

-- Coordinates describe stroke centres on a 24-unit grid. Capsule endpoints
-- extend half a stroke beyond each joint, so connected segments cannot crack.
local function iline(b, c, x1, y1, x2, y2)
	local dx, dy = x2 - x1, y2 - y1
	return ipart(b, (x1 + x2) / 48, (y1 + y2) / 48,
		(math.sqrt(dx * dx + dy * dy) + ICON_STROKE) / 24, ICON_STROKE / 24,
		math.deg(math.atan2(dy, dx)), { color = c, round = .5 })
end

local function ipath(b, c, points, closed)
	for i = 1, #points - (closed and 0 or 1) do
		local a, z = points[i], points[i % #points + 1]
		iline(b, c, a[1], a[2], z[1], z[2])
	end
end

local function iring(b, c, x, y, diameter)
	return ipart(b, x / 24, y / 24, diameter / 24, diameter / 24, 0,
		{ color = c, hollow = true, round = .5 })
end

local ICONS = {}

ICONS.dot = function(b, c)
	ipart(b, .5, .5, 5 / 24, 5 / 24, 0, { color = c, round = .5 })
end

ICONS.search = function(b, c)
	iring(b, c, 10.5, 10.5, 13)
	iline(b, c, 15.2, 15.2, 21, 21)
end

ICONS.home = function(b, c)
	ipath(b, c, { { 3, 10 }, { 12, 3 }, { 21, 10 } })
	ipath(b, c, { { 5, 9 }, { 5, 21 }, { 9.5, 21 }, { 9.5, 14 },
		{ 14.5, 14 }, { 14.5, 21 }, { 19, 21 }, { 19, 9 } })
end

local STAR = { { 12, 3 }, { 14.8, 8.8 }, { 21.2, 9.7 }, { 16.6, 14.2 },
	{ 17.7, 20.7 }, { 12, 17.7 }, { 6.3, 20.7 }, { 7.4, 14.2 },
	{ 2.8, 9.7 }, { 9.2, 8.8 } }

ICONS.star = function(b, c) ipath(b, c, STAR, true) end
ICONS.starOn = function(b, c)
	-- Fill the concave interior with overlapping Frame bands; the same rounded
	-- outline covers their ends. No background-colour masks or image dependency.
	for y = 3.25, 20.5, .5 do
		local hits = {}
		for i, a in ipairs(STAR) do
			local z = STAR[i % #STAR + 1]
			if (a[2] <= y and z[2] > y) or (z[2] <= y and a[2] > y) then
				hits[#hits + 1] = a[1] + (y - a[2]) * (z[1] - a[1]) / (z[2] - a[2])
			end
		end
		table.sort(hits)
		for i = 1, #hits - 1, 2 do
			ipart(b, (hits[i] + hits[i + 1]) / 48, y / 24,
				(hits[i + 1] - hits[i]) / 24, .6 / 24, 0, { color = c })
		end
	end
	ipath(b, c, STAR, true)
end

ICONS.clock = function(b, c)
	iring(b, c, 12, 12, 17)
	ipath(b, c, { { 12, 7 }, { 12, 12 }, { 15.5, 14 } })
end

ICONS.terminal = function(b, c)
	ipart(b, .5, .5, 18 / 24, 16 / 24, 0,
		{ color = c, hollow = true, round = .125 })
	ipath(b, c, { { 7, 9 }, { 10, 12 }, { 7, 15 } })
	iline(b, c, 13.5, 15, 17, 15)
end

-- A continuous waveform reads as movement even at the smallest row size.
ICONS.anims = function(b, c)
	ipath(b, c, { { 3, 12 }, { 6, 12 }, { 9, 4 }, { 13, 20 },
		{ 17, 8 }, { 19, 12 }, { 21, 12 } })
end

ICONS.gear = function(b, c)
	local teeth = {}
	for i = 0, 5 do
		local a = math.rad(i * 60)
		for _, p in ipairs({ { 7, -3.5 }, { 7, -1.7 }, { 9.5, -1.7 },
			{ 9.5, 1.7 }, { 7, 1.7 }, { 7, 3.5 } }) do
			teeth[#teeth + 1] = { 12 + p[1] * math.cos(a) - p[2] * math.sin(a),
				12 + p[1] * math.sin(a) + p[2] * math.cos(a) }
		end
	end
	ipath(b, c, teeth, true)
	iring(b, c, 12, 12, 6)
end

ICONS.info = function(b, c)
	iring(b, c, 12, 12, 17)
	ipart(b, .5, 8 / 24, ICON_STROKE / 24, ICON_STROKE / 24, 0,
		{ color = c, round = .5 })
	iline(b, c, 12, 11.5, 12, 16.5)
end

ICONS.play = function(b, c)
	ipath(b, c, { { 7, 4 }, { 20, 12 }, { 7, 20 } }, true)
end

ICONS.menu = function(b, c)
	for _, y in ipairs({ 6, 12, 18 }) do iline(b, c, 4, y, 20, y) end
end

ICONS.dash = function(b, c) iline(b, c, 5, 12, 19, 12) end
ICONS.minus = ICONS.dash

ICONS.plus = function(b, c)
	iline(b, c, 5, 12, 19, 12)
	iline(b, c, 12, 5, 12, 19)
end

ICONS.close = function(b, c)
	iline(b, c, 6, 6, 18, 18)
	iline(b, c, 6, 18, 18, 6)
end

ICONS.check = function(b, c)
	ipath(b, c, { { 4, 12 }, { 9, 17 }, { 20, 6 } })
end

ICONS.chevron = function(b, c)
	ipath(b, c, { { 9, 5 }, { 16, 12 }, { 9, 19 } })
end

ICONS.grid = function(b, c)
	for _, p in ipairs({ { 7.5, 7.5 }, { 16.5, 7.5 }, { 7.5, 16.5 }, { 16.5, 16.5 } }) do
		ipart(b, p[1] / 24, p[2] / 24, 6.5 / 24, 6.5 / 24, 0,
			{ color = c, hollow = true, round = .25 })
	end
end

ICONS.shield = function(b, c)
	ipath(b, c, { { 12, 3 }, { 20, 6 }, { 20, 11 }, { 17.5, 17 }, { 12, 21 },
		{ 6.5, 17 }, { 4, 11 }, { 4, 6 } }, true)
end

ICONS.bolt = function(b, c)
	ipath(b, c, { { 13.5, 3 }, { 5.5, 13.5 }, { 12, 13.5 }, { 10.5, 21 },
		{ 18.5, 10.5 }, { 12, 10.5 } }, true)
end

ICONS.refresh = function(b, c)
	local pts = {}
	for i = 0, 10 do
		local a = math.rad(-60 + i * 27)
		pts[#pts + 1] = { 12 + 7.5 * math.cos(a), 12 + 7.5 * math.sin(a) }
	end
	ipath(b, c, pts)
	-- Arrowhead on the arc's open end (-60 degrees = 15.75, 5.5).
	iline(b, c, 15.75, 5.5, 15.25, 1.5)
	iline(b, c, 15.75, 5.5, 19.75, 6)
end

ICONS.keyboard = function(b, c)
	ipart(b, .5, .5, 20 / 24, 13 / 24, 0, { color = c, hollow = true, round = .2 })
	for _, x in ipairs({ 7, 10.3, 13.7, 17 }) do
		ipart(b, x / 24, 10 / 24, ICON_STROKE / 24, ICON_STROKE / 24, 0,
			{ color = c, round = .5 })
	end
	iline(b, c, 8.5, 14.5, 15.5, 14.5)
end

ICONS.eye = function(b, c)
	local top, bottom = {}, {}
	for i = 0, 8 do
		local x = 3 + i * 18 / 8
		local y = 5.5 * math.sin(math.pi * i / 8)
		top[#top + 1] = { x, 12 - y }
		bottom[#bottom + 1] = { x, 12 + y }
	end
	ipath(b, c, top)
	ipath(b, c, bottom)
	iring(b, c, 12, 12, 5.5)
end

function Kit.icon(parent, name, o)
	o = o or {}
	local size = o.size or 16
	local col = o.color or COL.dim
	local box = new("Frame", {
		Name = "R3ST_Icon",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(size, size),
		Position = o.pos or UDim2.fromOffset(0, 0),
		AnchorPoint = o.anchor or Vector2.new(0, 0),
		ZIndex = o.zIndex or 2,
	}, parent)
	local draw = ICONS[name]
	if draw then
		draw(box, col)
	end
	box:SetAttribute("R3ST_IconName", name)
	return box
end

-- Recolour in place. Used for hover, for the active nav row, and for the
-- favourite star, so a caller never has to rebuild the icon to change its state.
function Kit.iconColor(box, col)
	if not (box and box.Parent) then return end
	for _, p in ipairs(box:GetChildren()) do
		if p:IsA("Frame") then
			if p:GetAttribute("R3ST_IconHollow") then
				local s = p:FindFirstChildOfClass("UIStroke")
				if s then s.Color = col end
			else
				p.BackgroundColor3 = col
			end
		end
	end
end

-- Swap one icon for another inside the same box (star <-> starOn, play <-> dash)
-- without disturbing its position, size or parent.
function Kit.iconSet(box, name, col)
	if not (box and box.Parent) then return end
	for _, p in ipairs(box:GetChildren()) do
		if p:IsA("Frame") then p:Destroy() end
	end
	local draw = ICONS[name]
	if draw then draw(box, col or COL.dim) end
	box:SetAttribute("R3ST_IconName", name)
	return box
end

function Kit.label(parent, text, size, col, x, y, w, h, align)
	return new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(w, h),
		Font = Kit.FONT.semi,
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

	-- Register a callback for host resize. Returns immediately with the current
	-- size so a caller can lay out once and subscribe in the same breath.
	out.resizeCbs = {}
	function out.onResize(fn)
		if type(fn) ~= "function" then return end
		out.resizeCbs[#out.resizeCbs + 1] = fn
		if hosted and H.host then
			local sz = H.host.AbsoluteSize
			if sz.X > 0 then pcall(fn, sz.X, sz.Y) end
		end
	end

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
	out.standaloneSize = Vector2.new(w, h)

	root.Parent = host
	root.AnchorPoint = Vector2.new(0, 0)
	root.Position = UDim2.fromOffset(0, 0)
	root.Visible = true -- r5
	if root:IsA("GuiObject") then root.Active = true end

	--==================================================================
	-- FILL, don't shrink. (Was: one-shot UIScale, capped at 1.)
	--
	-- The old rule read "fit a fixed-offset layout with a UIScale; do not
	-- reflow a proven page of controls", and `math.min(hw/w, hh/h, 1)` is
	-- what it produced. Both halves of that were wrong in practice:
	--
	--   * The cap at 1 meant a module could only ever SHRINK. A 760x560
	--     panel in a ~1040x600 host stayed 760x560 in the top-left corner
	--     and painted 68% of the space it was given. Measured across the
	--     registry, exactly two of eighteen embedded modules filled their
	--     host, and four ESP panels painted under 15%.
	--   * Scaling is the wrong tool anyway. Kit.relayout reflows cards into
	--     1/2/3 columns by width, so a wider host should GAIN CONTENT, not
	--     magnify the same content. Scaling up would just produce a bigger
	--     blurry copy of a 700px column.
	--
	-- So the hosted root fills the host and the card grid reflows into it.
	-- Rows inside a card are already sized in SCALE, so nothing below the
	-- card level has to change -- which is why this fixes the eight
	-- Kit.host modules without editing one line of their source.
	--
	-- o.scale = "fit" keeps the old downscale for a module whose layout
	-- genuinely cannot reflow (a fixed diagram, a canvas). It is an opt-out,
	-- not the default, and it should stay rare enough to name the callers.
	--==================================================================
	if o.scale == "fit" then
		if w > 0 and h > 0 then
			local hw = host.AbsoluteSize.X > 0 and host.AbsoluteSize.X or (H.width or w)
			local hh = host.AbsoluteSize.Y > 0 and host.AbsoluteSize.Y or (H.height or h)
			local s = math.min(hw / w, hh / h, 1)
			if s < 0.999 then
				local us = root:FindFirstChildOfClass("UIScale") or new("UIScale", {}, root)
				us.Scale = s
				out.scale = s
			end
		end
	elseif o.scale ~= false then
		-- Any UIScale left over from a previous mount would multiply against a
		-- root that now fills, so clear it rather than compound it.
		local us = root:FindFirstChildOfClass("UIScale")
		if us then us.Scale = 1 end
		root.Size = UDim2.fromScale(1, 1)
		out.filled = true
	end

	-- Stay connected. The scale/size used to be computed once at mount, so the
	-- hub's drag-resize grip moved the window and the module never heard about
	-- it: "the resize module doesn't work for certain UI's". Pages re-measure
	-- themselves through Kit.page's own watcher; this reports the change to the
	-- module for anything the kit does not own.
	out.conns = {}
	out.conns[#out.conns + 1] = host:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		local sz = host.AbsoluteSize
		out.width, out.height = sz.X, sz.Y
		for _, fn in ipairs(out.resizeCbs or {}) do
			pcall(fn, sz.X, sz.Y)
		end
	end)

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
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType ==
			Enum.UserInputType.Touch then
			dragging = true
			startPos = i.Position
			startSize = Vector2.new(root.Size.X.Offset, root.Size.Y.Offset)
		end
	end)
	conns[#conns + 1] = UserInputService.InputChanged:Connect(function(i)
		if not dragging then return end
		if i.UserInputType ~= Enum.UserInputType.MouseMovement and i.UserInputType ~=
			Enum.UserInputType.Touch then return end
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
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType ==
			Enum.UserInputType.Touch then
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

--==========================================================================
-- CONTRACT STAMPS -- what tools/ui_assert.lua reads
--
-- A control is only provable from outside if it says what it is. Before this,
-- the only verifier walked CoreGui and counted GuiButtons, so any unrelated
-- button could produce a PASS -- our one automated check could not tell a bound
-- toggle from a decorative rectangle.
--
-- Stamped on the LOGICAL OUTER control (the row box), never on decorative
-- descendants. Nested hit targets are reached through their stamped ancestor.
--   R3ST_Control  "toggle" | "slider" | "button" | "note" | "status" | "tab"
--   R3ST_Key      the cfg key this control persists to, or "" when it has none
--   R3ST_Bound    true only when a real setter/callback exists behind it
--==========================================================================
local function stampControl(obj, kind, key, bound)
	if not obj then return obj end
	obj:SetAttribute("R3ST_Control", kind)
	obj:SetAttribute("R3ST_Key", tostring(key or ""))
	obj:SetAttribute("R3ST_Bound", bound and true or false)
	return obj
end
Kit.stampControl = stampControl

local CARD_PAD = Kit.SPACE.md
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

--==========================================================================
-- Kit.page -- a page measures ITSELF, and keeps measuring itself
--
-- Every caller passes a hardcoded `width` (fisch/sell-ores/overhang: 700, mafia:
-- PAGE_W) because that is what the contract used to show. The result: the card
-- grid was pinned to ~700px no matter how much room the host actually had, so a
-- module could not fill the hub even once its root did. And because the grid was
-- computed exactly once, nothing reflowed when the hub window was drag-resized
-- -- Kit.relayout existed from day one and only four modules ever called it.
--
-- Now the real AbsoluteSize wins whenever there is one, `o.width` degrades to a
-- fallback for a page not laid out yet, and the page watches its own size for
-- the rest of its life. One consequence worth stating plainly: the eight modules
-- that call Kit.host + Kit.page become host-fluid with ZERO edits to their
-- source, because both halves of what they were missing live here.
--
-- The kit also owns CanvasSize now. Modules set it once, immediately after
-- building their controls, which is correct exactly until the first reflow
-- changes the column count and the content gets taller than the canvas -- then
-- the bottom card is unreachable with no scrollbar to reveal it.
--==========================================================================
function Kit.page(page, o)
	o = o or {}
	local measured = page.AbsoluteSize.X
	local width = (measured > 0 and measured) or o.width or 700
	local n = o.columns or columnsFor(width)
	PAGE[page] = { cols = newCols(width, n), cards = {}, card = nil, width = width,
		fixedCols = o.columns, canvas = o.canvas ~= false }

	-- Reflow whenever the page's own width changes. This is a property signal on
	-- an Instance the caller owns, so it dies with the page and needs no entry in
	-- anyone's teardown list.
	local conn
	conn = page:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if not page.Parent then
			if conn then conn:Disconnect() end
			return
		end
		local w = page.AbsoluteSize.X
		if w < 200 then return end
		Kit.relayout(page, w)
	end)

	-- AbsoluteSize is 0 until Roblox has laid the frame out once, so a page built
	-- and measured in the same frame reads 0 and would keep the fallback width
	-- forever. Re-measure on the next frame.
	task.defer(function()
		if page.Parent and page.AbsoluteSize.X > 200 then
			Kit.relayout(page, page.AbsoluteSize.X)
		end
	end)
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

-- Rebuild catalog contents without replacing its scrolling/input surface.
function Kit.clearPage(page)
	local rec = pageRec(page)
	local position = page.CanvasPosition
	for _, child in ipairs(page:GetChildren()) do child:Destroy() end
	rec.cols = newCols(rec.width, rec.fixedCols or columnsFor(rec.width))
	rec.cards, rec.card = {}, nil
	return position
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
-- The canvas has to follow CONTENT, not just width. It used to be written only
-- at the bottom of Kit.relayout, which returns early whenever the width has not
-- moved -- so every control added after the first layout grew the columns past a
-- canvas nothing ever updated, and the page stopped scrolling with the last
-- cards unreachable. Called from grow() as well now, so it cannot go stale.
local function syncCanvas(page, rec)
	rec = rec or PAGE[page]
	if not rec or rec.canvas == false then return end
	if not (page and page.Parent and page:IsA("ScrollingFrame")) then return end
	local h = 0
	for _, c in ipairs(rec.cols) do
		if c.y > h then h = c.y end
	end
	local want = h + 12
	if math.abs(page.CanvasSize.Y.Offset - want) >= 1 then
		page.CanvasSize = UDim2.fromOffset(0, want)
	end
end

function Kit.relayout(page, width)
	local rec = PAGE[page]
	if not rec or width < 200 then
		return Kit.height(page)
	end
	if math.abs((rec.width or 0) - width) < 2 then
		-- Same width, but the content may have grown since the last pass.
		syncCanvas(page, rec)
		return Kit.height(page)
	end
	rec.width = width
	rec.cols = newCols(width, rec.fixedCols or columnsFor(width))
	for _, card in ipairs(rec.cards) do
		local col = shortestCol(rec)
		card.col = col
		local h = card.frame.Size.Y.Offset
		-- Ease the move: a column-count change (2 -> 3 as the window widens) is
		-- the single most visible thing a resize does, and it used to teleport.
		Kit.tween(card.frame, {
			Position = UDim2.fromOffset(col.x, col.y),
			Size = UDim2.fromOffset(col.w, h),
		}, Kit.MOTION.fast)
		col.y = col.y + h + GUTTER
	end
	local total = Kit.height(page)
	syncCanvas(page, rec)
	return total
end

local function grow(card, by)
	card.frame.Size = UDim2.fromOffset(card.col.w, card.y + by + CARD_PAD)
	card.y = card.y + by
	card.col.y = card.frame.Position.Y.Offset + card.frame.Size.Y.Offset + GUTTER
	-- Every row added after the first layout lands here. Without this the canvas
	-- keeps the height it had when the page was first measured.
	if card.page then syncCanvas(card.page) end
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
	corner(frame, Kit.RADIUS.card)
	local frameStroke = stroke(frame, COL.line)
	-- Top-lit surface: a 6% falloff gives the card a plane of its own without
	-- an image shadow. Multiplies BackgroundColor3, so callers may still recolour.
	new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(236, 236, 240)),
	}, frame)
	local t = label(frame, title, Kit.ROLE.heading.size, COL.text, CARD_PAD, 8, 0, 22)
	t.Size = UDim2.new(1, -CARD_PAD * 2, 0, 22)
	t.Font = Kit.ROLE.heading.font
	if title ~= "" then
		-- Accent tick: a child of the title, so W.group destroying the title takes
		-- the tick with it and no caller needs to know it exists.
		new("UIPadding", { PaddingLeft = UDim.new(0, 11) }, t)
		local tick = new("Frame", {
			Name = "R3ST_Tick",
			BackgroundColor3 = COL.accent,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, -11, 0.5, 0),
			Size = UDim2.fromOffset(3, 14),
		}, t)
		corner(tick, 2)
	end
	-- Cards animate IN (staggered), but they do not hover. A card contains
	-- buttons and toggles, and MouseLeave fires the moment the pointer crosses
	-- onto one of them -- so a hover tint here flickers on every control the user
	-- reaches for. Hover belongs on the things that are actually clickable, which
	-- now have a real pressed state as well (Kit.interactive). frameStroke stays
	-- named because W.statusRow and callers recolour it.
	local _ = frameStroke
	Kit.enter(frame, #rec.cards + 1)
	rec.card = { frame = frame, col = col, y = CARD_TOP, title = t, page = page }
	rec.cards[#rec.cards + 1] = rec.card
	col.y = col.y + frame.Size.Y.Offset + GUTTER
	syncCanvas(page, rec)
	return t
end

--==========================================================================
-- bind(): widgets wired to the CALLER's live/conns tables
--==========================================================================
-- VISIBILITY BEGIN
function Kit.isVisible(object)
	if not object or not object.Parent then return false end
	while object do
		if object:IsA("GuiObject") and not object.Visible then return false end
		if object:IsA("LayerCollector") and not object.Enabled then return false end
		object = object.Parent
	end
	return true
end
-- VISIBILITY END

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

	-- The kit drives its own live list. Every toggle repaint and statusRow
	-- refresh registers here; before 2026-09-23 nothing in the kit ran it, so
	-- any module that did not run `live` itself shipped switches that flipped
	-- the value but never moved, and status rows frozen at build time (only
	-- blr_hub and bloxstrike_esp ran it). Owned here so no module can forget.
	-- Registered in `conns`, which Shell.destroy / the module's teardown
	-- disconnects. A module that still runs `live` itself only repaints twice;
	-- every redraw is idempotent. `W.liveHz` caps the rate (default 30).
	W.liveHz = 30
	do
		local acc = 0
		local ok, conn = pcall(function()
			return game:GetService("RunService").RenderStepped:Connect(function(dt)
				acc += dt
				if acc < 1 / W.liveHz then return end
				acc %= 1 / W.liveHz
				-- One cheap ancestor check per panel, not one getter per hidden widget.
				if host.isVisible and not host.isVisible() then return end
				for i = 1, #live do
					local fn = live[i]
					if type(fn) == "function" then pcall(fn) end
				end
			end)
		end)
		if ok and conn then conns[#conns + 1] = conn end
	end

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
		if drag and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType ==
			Enum.UserInputType.Touch) then
			drag.setFromX(i.Position.X)
		end
	end))
	addConn(UserInputService.InputEnded:Connect(function(i)
		if drag and (i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType ==
			Enum.UserInputType.Touch) then
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
	function W.row(page, height)
		return rowBox(page, height)
	end

	function W.group(page)
		Kit.section(page, "")
		local card = currentCard(page)
		card.title:Destroy()
		card.y = CARD_PAD
		grow(card, 0)
		return card.frame
	end

	local keyCapture
	-- Compact keyboard binding; callers may retain their own capture dispatch.
	function W.keybind(page, o)
		local get, set = wire(o, false)
		local box = o.row or rowBox(page, 34)
		local name = label(box, o.label or "", Kit.TYPE.body, COL.text, 0, 0, 0, 34)
		name.Size = UDim2.new(1, -124, 0, 34)
		Kit.role(name, "control")
		local chip = new("TextButton", {
			Text = "", AutoButtonColor = false, BorderSizePixel = 0,
			BackgroundColor3 = COL.row, TextColor3 = COL.text,
			AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
			Size = UDim2.fromOffset(112, 28),
		}, box)
		Kit.role(chip, "value")
		corner(chip, Kit.RADIUS.control)
		local edge = stroke(chip)
		local last
		local function redraw()
			local active = o.capturing and o.capturing() or keyCapture == box
			local value = get and get()
			chip.Text = active and "..." or (value and value.Name or "—")
			chip.Size = UDim2.fromOffset(clamp(#chip.Text * 8 + 24, 40, 112), 28)
			if active ~= last then
				tween(edge, { Color = active and COL.accent or COL.line }, Kit.MOTION.fast)
				tween(chip, { TextColor3 = active and COL.accentText or COL.text }, Kit.MOTION.fast)
				last = active
			end
		end
		Kit.interactive(chip, edge, COL.row, {
			edge = function() return last and COL.accent or COL.line end,
		})
		chip.Activated:Connect(function()
			if o.onCapture then
				guard("ui.keybind.capture", o.onCapture)
			else
				keyCapture = box
			end
			redraw()
		end)
		local inputConn
		local function cancelCapture()
			if keyCapture == box then keyCapture = nil end
			if o.capturing and o.capturing() and o.onCancel then
				guard("ui.keybind.cancel", o.onCancel)
			end
			if box.Parent then redraw() end
		end
		local hasBlur, blurConn = pcall(function()
			return UserInputService.WindowFocusReleased:Connect(cancelCapture)
		end)
		if hasBlur then addConn(blurConn) end
		if not o.onCapture then
			inputConn = UserInputService.InputBegan:Connect(function(input)
				if keyCapture ~= box or not box.Parent then return end
				local kc = input.KeyCode
				if kc == Enum.KeyCode.Unknown then return end
				keyCapture = nil
				if kc ~= Enum.KeyCode.Escape then
					local clear = kc == Enum.KeyCode.Backspace or kc == Enum.KeyCode.Delete
					local value = kc
					if clear then value = false end
					guard("ui.keybind", set, value)
				end
				redraw()
			end)
			addConn(inputConn)
		end
		box.Destroying:Connect(function()
			cancelCapture()
			if hasBlur then blurConn:Disconnect() end
			if inputConn then inputConn:Disconnect() end
		end)
		addLive(function() if box.Parent then redraw() end end)
		stampControl(box, "keybind", o.key, type(set or o.onCapture) == "function")
		o.redraw = redraw
		redraw()
		return chip, box
	end

	-- Numeric row: validate once on blur, preserving the last valid value.
	function W.number(page, o)
		local get, set = wire(o, tonumber(o.text) or 0)
		local box = rowBox(page, 34)
		local name = label(box, o.label or "", Kit.TYPE.body, COL.text, 0, 0, 0, 34)
		name.Size = UDim2.new(1, -108, 0, 34)
		Kit.role(name, "control")
		local input = new("TextBox", {
			Text = tostring(get and get() or o.text or o.default or 0),
			ClearTextOnFocus = false, BackgroundColor3 = COL.row,
			TextColor3 = COL.text, BorderSizePixel = 0,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
			Size = UDim2.fromOffset(96, 28),
		}, box)
		new("UIPadding", { PaddingLeft = UDim.new(0, Kit.SPACE.sm),
			PaddingRight = UDim.new(0, Kit.SPACE.sm) }, input)
		Kit.role(input, "value")
		corner(input, Kit.RADIUS.control)
		local edge = stroke(input)
		local focused, hovering, previous = false, false, input.Text
		local function paint()
			tween(edge, { Color = focused and COL.accent
				or (hovering and COL.lineStrong or COL.line) }, Kit.MOTION.fast)
			tween(input, { BackgroundColor3 = (focused or hovering) and COL.rowHover
				or COL.row }, Kit.MOTION.fast)
		end
		input.MouseEnter:Connect(function() hovering = true; paint() end)
		input.MouseLeave:Connect(function() hovering = false; paint() end)
		input.Focused:Connect(function()
			previous, focused = input.Text, true
			paint()
		end)
		input.FocusLost:Connect(function()
			focused = false
			local n = tonumber(input.Text)
			if n and n == n then
				if o.min then n = math.max(o.min, n) end
				if o.max then n = math.min(o.max, n) end
				input.Text = tostring(n)
				guard("ui.number", set, n)
			else
				input.Text = get and tostring(get()) or previous
			end
			if o.commit then guard("ui.number.commit", o.commit) end
			previous = input.Text
			paint()
		end)
		stampControl(input, "number", o.key, type(set) == "function")
		return input, box
	end

	function W.toggle(page, o)
		local get, set = wire(o, false)
		local h = o.desc and 44 or 34
		local box = rowBox(page, h)
		local name = label(box, o.label, Kit.ROLE.control.size, COL.text, 0, o.desc and 2 or 0, 0,
			o.desc and 18 or h)
		name.Font = Kit.ROLE.control.font
		name.Size = UDim2.new(1, -60, 0, o.desc and 18 or h)
		if o.desc then
			local d = label(box, o.desc, Kit.ROLE.caption.size, COL.dim, 0, 22, 0, 16)
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
		local stateLabel
		if o.stateText then
			stateLabel = label(box, "", 11, COL.dim, 0, 0, 34, h, Enum.TextXAlignment.Right)
			stateLabel.AnchorPoint = Vector2.new(1, 0)
			stateLabel.Position = UDim2.new(1, -56, 0, 0)
			stateLabel.Font = Kit.FONT.bold
		end
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
			if stateLabel then
				stateLabel.Text = on and "ON" or "OFF"
				stateLabel.TextColor3 = on and COL.text or COL.dim
			end
			tween(knob, { Position = UDim2.new(0, on and 25 or 3, 0.5, 0) },
				d == 0 and 0 or Kit.MOTION.spring, "spring")
			tween(knob, { BackgroundColor3 = on and COL.white or COL.knobOff }, d)
			tween(track, { BackgroundColor3 = on and COL.accent or COL.row }, d)
			tween(st, { Color = on and COL.accent or COL.line }, d)
			tween(name, { TextColor3 = on and COL.text or COL.dim }, d)
			-- Commit the paint cache only after every property write succeeds. GUI
			-- signal threads can be capability-restricted; caching before a failed
			-- write permanently left the switch showing its previous state.
			lastOn = on
		end
		local clickTarget = track
		if o.fullRow then
			clickTarget = new("TextButton", {
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Size = UDim2.fromScale(1, 1),
				Text = "",
				AutoButtonColor = false,
				ZIndex = 10,
			}, box)
		end
		clickTarget.Activated:Connect(function()
			-- State changes here; painting belongs to the caller's safe live loop.
			-- Touching CoreGui from this signal thread can lack Plugin capability.
			guard("ui.toggle." .. tostring(o.label), function()
				local on = lastOn
				if not o.fromDisplay then on = get() end
				set(not on)
			end)
		end)
		redraw()
		o.redraw = redraw
		stampControl(box, "toggle", o.key, type(set) == "function")
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
		local name = label(box, o.label, Kit.ROLE.control.size, COL.text, 0, 0, 0, 18)
		name.Font = Kit.ROLE.control.font
		name.Size = UDim2.new(1, -130, 0, 18)
		local val = label(box, "", Kit.ROLE.value.size, COL.accentText, 0, 0, 130, 18,
			Enum.TextXAlignment.Right)
		val.AnchorPoint = Vector2.new(1, 0)
		val.Position = UDim2.new(1, 0, 0, 0)
		val.Font = Kit.ROLE.value.font

		local track = new("Frame", {
			BackgroundColor3 = COL.row,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(0, 26),
			Size = UDim2.new(1, 0, 0, 6),
		}, box)
		corner(track, 3)
		local fill = new("Frame", { BackgroundColor3 = COL.accent, BorderSizePixel = 0, Size =
			UDim2.fromScale(0, 1) }, track)
		corner(fill, 3)
		local knob = new("Frame", {
			BackgroundColor3 = COL.white,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0, 0, 0.5, 0),
			Size = UDim2.fromOffset(14, 14),
			ZIndex = 3,
		}, track)
		new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, knob)
		new("UIStroke", { Color = COL.accent, Thickness = 2 }, knob)
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
		local lastValue, lastStock, lastHeld
		local function redraw()
			-- The knob swells while held, so a drag has a visible owner.
			local held = drag == o
			if held ~= lastHeld then
				tween(knob, { Size = UDim2.fromOffset(held and 18 or 14, held and 18 or 14) },
					lastHeld == nil and 0 or Kit.MOTION.base, "spring")
				lastHeld = held
			end
			local v = get()
			if v ~= lastValue then
				local f = frac(v)
				fill.Size = UDim2.fromScale(f, 1)
				knob.Position = UDim2.new(f, 0, 0.5, 0)
				val.Text = o.fmt and o.fmt(v) or tostring(v)
				lastValue = v
			end
			if mark then
				local stock = o.stock()
				if stock ~= lastStock then
					mark.Position = UDim2.new(frac(stock), 0, 0.5, 0)
					lastStock = stock
				end
			end
			if liveLbl and o.live then
				local text = o.live(v) or ""
				if liveLbl.Text ~= text then liveLbl.Text = text end
			end
		end
		o.redraw = redraw
		o.setFromX = function(px)
			local f = clamp((px - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0,
				1)
			local v = o.min + f * (o.max - o.min)
			if o.step then
				v = math.floor(v / o.step + 0.5) * o.step
			end
			set(clamp(v, o.min, o.max))
			redraw()
		end
		local function grab(i)
			if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType ==
				Enum.UserInputType.Touch then
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
		stampControl(box, "slider", o.key, type(set) == "function")
		addLive(function()
			if box.Parent and page.Visible then redraw() end
		end)
		return box
	end

	function W.button(page, text, desc, fn, wide, interaction)
		local box = rowBox(page, desc and 48 or 32)
		local b = new("TextButton", {
			BackgroundColor3 = COL.row,
			BorderSizePixel = 0,
			Size = wide and UDim2.new(1, 0, 0, 30) or UDim2.fromOffset(200, 30),
			Font = Kit.ROLE.control.font,
			TextSize = Kit.ROLE.control.size,
			TextColor3 = COL.text,
			Text = text,
			AutoButtonColor = false,
		}, box)
		corner(b, Kit.RADIUS.control)
		local s = stroke(b, COL.line)
		-- Hover, and a real PRESSED state. Every button in the product had hover
		-- only, so nothing on screen ever acknowledged the click itself.
		local repaint = Kit.interactive(b, s, nil, interaction)
		if interaction then addLive(function() if box.Parent then repaint() end end) end
		b.MouseButton1Click:Connect(function() guard("ui.button." .. tostring(text), fn) end)
		stampControl(box, "button", nil, type(fn) == "function")
		if desc then
			local d = label(box, desc, 10, COL.dim, 0, 32, 0, 14)
			d.Size = UDim2.new(1, 0, 0, 14)
			d.TextTruncate = Enum.TextTruncate.AtEnd
		end
		return b
	end

	function W.note(page, text)
		local card = currentCard(page)
		local l = label(card.frame, text, Kit.ROLE.caption.size, COL.dim, CARD_PAD, card.y, 0, 26)
		l.Size = UDim2.new(1, -CARD_PAD * 2, 0, 26)
		l.TextWrapped = true
		l.TextYAlignment = Enum.TextYAlignment.Top
		grow(card, 30)
		stampControl(l, "note", nil, false)
		return l
	end

	function W.statusRow(page, getText)
		local card = currentCard(page)
		local l = label(card.frame, "", Kit.ROLE.caption.size, COL.dim, CARD_PAD, card.y, 0, 26)
		l.Size = UDim2.new(1, -CARD_PAD * 2, 0, 26)
		l.TextWrapped = true
		l.TextYAlignment = Enum.TextYAlignment.Top
		grow(card, 30)
		stampControl(l, "status", nil, type(getText) == "function")
		local nextRead = 0
		addLive(function()
			if not l.Parent or not page.Visible or os.clock() < nextRead then return end
			nextRead = os.clock() + 0.25
			local text = getText() or ""
			if l.Text ~= text then l.Text = text end
		end)
		return l
	end

	-- Parent-based primitives also work outside the automatic section grid.
	function W.search(parent, o)
		o = o or {}
		local box = new("TextBox", {
			Text = o.text or "", PlaceholderText = o.placeholder or "Search...",
			ClearTextOnFocus = false, BackgroundColor3 = COL.row,
			TextColor3 = COL.text, PlaceholderColor3 = COL.dim, BorderSizePixel = 0,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -40, 1, 0),
			Position = UDim2.fromOffset(36, 0),
		}, parent)
		local field = new("Frame", {
			BackgroundColor3 = COL.row, BorderSizePixel = 0,
			Size = o.size or UDim2.new(1, 0, 0, Kit.SPACE.xxl),
			Position = o.position or UDim2.new(),
		}, parent)
		box.Parent = field
		box.BackgroundTransparency = 1
		Kit.icon(field, "search", { size = 16, color = COL.dim,
			pos = UDim2.new(0, 12, 0.5, 0), anchor = Vector2.new(0, 0.5) })
		Kit.role(box, "body")
		corner(field, Kit.RADIUS.control)
		local edge = stroke(field)
		new("UIPadding", { PaddingLeft = UDim.new(0, 0),
			PaddingRight = UDim.new(0, Kit.SPACE.md) }, box)
		box:GetPropertyChangedSignal("Visible"):Connect(function()
			field.Visible = box.Visible
		end)
		local focused, hovering = false, false
		local glass = field:FindFirstChild("R3ST_Icon")
		local function paint()
			tween(edge, { Color = focused and COL.accent
				or (hovering and COL.lineStrong or COL.line) }, Kit.MOTION.fast)
			tween(field, { BackgroundColor3 = (focused or hovering) and COL.rowHover
				or COL.row }, Kit.MOTION.fast)
			if glass then Kit.iconColor(glass, focused and COL.accentText or COL.dim) end
		end
		box.MouseEnter:Connect(function() hovering = true; paint() end)
		box.MouseLeave:Connect(function() hovering = false; paint() end)
		box.Focused:Connect(function() focused = true; paint() end)
		box.FocusLost:Connect(function() focused = false; paint() end)
		if o.changed then
			box:GetPropertyChangedSignal("Text"):Connect(function()
				guard("ui.search", o.changed, box.Text)
			end)
		end
		stampControl(box, "search", nil, type(o.changed) == "function")
		return box, field
	end

	function W.badge(parent, o)
		o = o or {}
		local badge = new("TextLabel", {
			Text = o.text or "", BackgroundColor3 = o.active and COL.accent or COL.row,
			TextColor3 = o.active and COL.white or COL.text, BorderSizePixel = 0,
			Size = o.size or UDim2.fromOffset(72, Kit.SPACE.xl),
			Position = o.position or UDim2.new(),
		}, parent)
		Kit.role(badge, "tab")
		corner(badge, Kit.RADIUS.pill)
		return badge
	end

	function W.card(parent, o)
		o = o or {}
		local card = new("TextButton", {
			Text = "", AutoButtonColor = false, BorderSizePixel = 0,
			BackgroundColor3 = o.active and COL.accentSoft or COL.card,
			Size = o.size or UDim2.new(1, 0, 0, 80),
			Position = o.position or UDim2.new(),
		}, parent)
		corner(card, Kit.RADIUS.card)
		local edge = stroke(card, o.active and COL.accent or COL.line)
		local title = label(card, o.title or "", Kit.TYPE.body, COL.text,
			Kit.SPACE.lg, Kit.SPACE.md, 0, 22)
		title.Size = UDim2.new(1, -128, 0, 22)
		title.TextTruncate = Enum.TextTruncate.AtEnd
		Kit.role(title, "control")
		local desc = label(card, o.desc or "", Kit.TYPE.small, COL.dim,
			Kit.SPACE.lg, 38, 0, 18)
		desc.Size = UDim2.new(1, -128, 0, 18)
		desc.TextTruncate = Enum.TextTruncate.AtEnd
		Kit.role(desc, "caption")
		local action = W.badge(card, { text = o.active and "Selected" or "Apply",
			active = o.active,
			position = UDim2.new(1, -96, 0.5, -12) })
		card.MouseEnter:Connect(function()
			if not o.active then
				tween(action, { BackgroundColor3 = COL.line }, Kit.MOTION.fast)
			end
		end)
		card.MouseLeave:Connect(function()
			if not o.active then
				tween(action, { BackgroundColor3 = COL.row }, Kit.MOTION.fast)
			end
		end)
		Kit.interactive(card, edge, card.BackgroundColor3, {
			edge = function() return o.active and COL.accent or COL.line end,
		})
		if o.activated then
			card.Activated:Connect(function() guard("ui.card", o.activated) end)
		end
		stampControl(card, "button", nil, type(o.activated) == "function")
		Kit.enter(card, o.index)
		return card
	end

	function W.empty(parent, o)
		o = o or {}
		local frame = new("Frame", { BackgroundColor3 = COL.card, BorderSizePixel = 0,
			Size = o.size or UDim2.new(1, -16, 0, 88),
			Position = o.position or UDim2.fromOffset(8, 8) }, parent)
		corner(frame, Kit.RADIUS.card)
		stroke(frame, COL.lineSoft)
		local title = label(frame, o.title or "Nothing here", Kit.TYPE.body,
			COL.text, Kit.SPACE.lg, Kit.SPACE.lg, 0, 24)
		title.Size = UDim2.new(1, -32, 0, 24)
		Kit.role(title, "control")
		local desc = label(frame, o.desc or "", Kit.TYPE.small,
			COL.dim, Kit.SPACE.lg, 44, 0, 28)
		desc.Size = UDim2.new(1, -32, 0, 28)
		desc.TextWrapped = true
		Kit.role(desc, "caption")
		return frame
	end

	function W.switch(parent, o)
		local button = new("TextButton", { Text = "", AutoButtonColor = false,
			BackgroundColor3 = COL.row, BorderSizePixel = 0,
			Size = o.size or UDim2.fromOffset(112, 32),
			Position = o.position or UDim2.new() }, parent)
		corner(button, Kit.RADIUS.control)
		Kit.interactive(button, stroke(button))
		local caption = label(button, "", Kit.TYPE.small, COL.text, 10, 0, 44, 32)
		Kit.role(caption, "control")
		local track = new("Frame", { Size = UDim2.fromOffset(36, 20),
			Position = UDim2.new(1, -44, 0.5, -10), BorderSizePixel = 0 }, button)
		corner(track, Kit.RADIUS.pill)
		local knob = new("Frame", { Size = UDim2.fromOffset(14, 14),
			BackgroundColor3 = COL.white, BorderSizePixel = 0 }, track)
		corner(knob, Kit.RADIUS.pill)
		local last
		local function paint()
			if not button.Parent then return end
			local on = o.get() and true or false
			if on == last then return end
			local duration = last == nil and 0 or Kit.MOTION.fast
			last = on
			caption.Text = on and "ON" or "OFF"
			tween(track, { BackgroundColor3 = on and COL.accent or COL.line }, duration)
			tween(caption, { TextColor3 = on and COL.text or COL.dim }, duration)
			tween(knob, { Position = UDim2.fromOffset(on and 19 or 3, 3) },
				duration == 0 and 0 or Kit.MOTION.spring, "spring")
		end
		button.Activated:Connect(function()
			guard("ui.switch", o.set, not o.get())
			paint()
		end)
		addLive(paint)
		paint()
		stampControl(button, "toggle", nil, type(o.set) == "function")
		return button
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
		corner(icon, Kit.RADIUS.card)
		stroke(icon, COL.line)
		if o.gameId then
			icon.Image = "rbxthumb://type=GameIcon&id=" .. tostring(o.gameId) .. "&w=150&h=150"
		end
		if o.placeId then
			task.spawn(function()
				local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService,
					o.placeId)
				if ok and type(info) == "table" and tonumber(info.IconImageAssetId)
					and tonumber(info.IconImageAssetId) > 0 and icon.Parent then
					icon.Image = "rbxassetid://" .. tostring(info.IconImageAssetId)
				end
			end)
		end
		local title = label(h, o.title or "", Kit.ROLE.title.size, COL.text, 78, 8, 420, 28)
		title.Font = Kit.ROLE.title.font
		label(h, o.version or "", Kit.ROLE.caption.size, COL.dim, 78, 36, 300, 16)
		label(h, o.subtitle or "", Kit.ROLE.caption.size, COL.dim, 78, 52, 460, 16)
		local info
		if o.onInfo then
			-- Was `Text = "ⓘ  Script Info"`. S9.3 has banned glyph icons since
			-- 2026-09-01 because they render as tofu boxes on the user's machine --
			-- and the file that enforces the rule was breaking it in its own header
			-- and footer. Drawn icon + plain text label instead.
			info = new("TextButton", {
				BackgroundColor3 = COL.card,
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, 0, 0, 20),
				Size = UDim2.fromOffset(150, 38),
				Font = Kit.ROLE.body.font,
				TextSize = Kit.ROLE.body.size,
				TextColor3 = COL.text,
				Text = "",
				AutoButtonColor = false,
			}, h)
			corner(info, Kit.RADIUS.control)
			local s = stroke(info, COL.line)
			Kit.icon(info, "info", { size = 14, color = COL.dim,
				pos = UDim2.new(0, 14, 0.5, 0), anchor = Vector2.new(0, 0.5) })
			local il = label(info, "Script info", Kit.ROLE.body.size, COL.text, 36, 0, 100, 38)
			il.Font = Kit.ROLE.body.font
			il.Active = false
			Kit.interactive(info, s, COL.card)
			stampControl(info, "button", nil, type(o.onInfo) == "function")
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
					BackgroundColor3 = on and COL.accent or COL.card,
					TextColor3 = on and COL.white or COL.dim,
				}, d)
				tween(rec.s, { Color = on and COL.accent or COL.line }, d)
			end
		end
		for _, name in ipairs(o.names) do
			-- Measured, not guessed: `14 + #name * 8` clipped any wide tab name.
			local text = name .. (o.counts and ("  " .. tostring(o.counts[name] or 0)) or "")
			local w = math.max(72, math.ceil(Kit.textWidth(text, Kit.TYPE.small)) + 22)
			local b = new("TextButton", {
				BackgroundColor3 = COL.card,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(x, 0),
				Size = UDim2.fromOffset(w, 30),
				Font = Kit.ROLE.tab.font,
				TextSize = Kit.ROLE.tab.size,
				TextColor3 = COL.dim,
				Text = text,
				AutoButtonColor = false,
			}, strip)
			corner(b, Kit.RADIUS.control)
			local s = stroke(b, COL.line)
			btns[name] = { b = b, s = s }
			Kit.interactive(b, s, COL.card, {
				base = function() return o.get() == name and COL.accent or COL.card end,
				hover = function() return o.get() == name and COL.accentHover or COL.rowHover end,
				edge = function() return o.get() == name and COL.accent or COL.line end,
			})
			stampControl(b, "tab", nil, type(o.set) == "function")
			b.Activated:Connect(function()
				o.set(name)
				paint()
			end)
			x = x + w + 6
		end
		paint()
		return strip, paint
	end

	W.chips = W.tabstrip
	W.segmented = W.tabstrip

	-- Footer: the two controls the template puts at the bottom of every module.
	function W.footer(parent, o)
		local f = new("Frame", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 0, 1, 0),
			Size = UDim2.new(1, 0, 0, 44),
		}, parent)
		new("Frame", { BackgroundColor3 = COL.lineSoft, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0,
			1) }, f)
		-- Drawn icon + text, never a glyph: "☐  Unload Script" and "⚙  UI Settings"
		-- were tofu boxes on the user's machine, in the file that bans them.
		local function chip(iconName, text, anchorRight, width, fn)
			local b = new("TextButton", {
				BackgroundColor3 = COL.card,
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(anchorRight and 1 or 0, 0.5),
				Position = UDim2.new(anchorRight and 1 or 0, 0, 0.5, 4),
				Size = UDim2.fromOffset(width, 32),
				Font = Kit.ROLE.body.font,
				TextSize = Kit.ROLE.body.size,
				TextColor3 = COL.text,
				Text = "",
				AutoButtonColor = false,
			}, f)
			corner(b, Kit.RADIUS.control)
			local s = stroke(b, COL.line)
			Kit.icon(b, iconName, { size = 13, color = COL.dim,
				pos = UDim2.new(0, 12, 0.5, 0), anchor = Vector2.new(0, 0.5) })
			local l = label(b, text, Kit.ROLE.body.size, COL.text, 32, 0, width - 40, 32)
			l.Font = Kit.ROLE.body.font
			l.Active = false
			Kit.interactive(b, s, COL.card)
			stampControl(b, "button", nil, type(fn) == "function")
			b.MouseButton1Click:Connect(function() guard("ui.footer." .. text, fn) end)
			return b
		end
		local unload, settings
		if o.onUnload then
			unload = chip("close", "Unload script", false, 170, o.onUnload)
			-- Destructive action gets the one warm colour, on its icon only.
			local x = unload:FindFirstChild("R3ST_Icon")
			if x then Kit.iconColor(x, COL.bad) end
		end
		if o.onSettings then settings = chip("gear", "UI settings", true, 150, o.onSettings) end
		-- Standalone only: embedded, the hub owns reload on its own page strip and a
		-- second control for one action is the bug this contract exists to stop.
		local reload
		if o.onReload then
			reload = chip("clock", "Reload", true, 110, o.onReload)
			reload.Position = UDim2.new(1, -(o.onSettings and 158 or 0), 0.5, 4)
		end
		if o.hint then
			local l = label(f, o.hint, Kit.ROLE.micro.size, COL.dim, 184, 12, 420, 28)
			l.Font = Kit.ROLE.micro.font
			l.TextWrapped = true
		end
		return f, unload, settings, reload
	end

	return W
end

--==========================================================================
-- Kit.moduleShell() -- the whole module layout as ONE call
--
-- WHY THIS EXISTS
--   An audit of all 31 registry rows on 2026-09-04 found FIVE different ways a
--   module lands in the hub: Kit.host + UIScale (8 modules), a hand-rolled
--   __R3ST_HOST reparent (gd2, blr, fisch, evade), an ESP-family reparent that
--   moves a 210px strip and nothing else (rivals, arsenal, operation-one,
--   cold-war), fromScale(1,1) (runaways, blr), and none at all (14 rows). Each
--   one re-implements the nine host rules of hub S6.1 by hand, so each one gets
--   a different subset of them wrong. Measured: exactly TWO of eighteen embedded
--   modules filled their host; four painted under 15% of it; fourteen games had
--   no reload control at all.
--
--   Every one of those is boilerplate the porting agent retypes and therefore
--   gets wrong. hub S9.0 already proved prose does not fix this: the three
--   regressions were stated as rules across ~25 modules and repeated every time.
--   So the layout is not a thing an agent remembers any more. It is a thing an
--   agent CALLS, and there is nothing left to hand-roll.
--
-- USE
--   local Shell = Kit.moduleShell({
--       id = "fisch", title = "Fisch", version = BUILD_VERSION,
--       subtitle = "...", gameId = EXPECTED_GAME, placeId = EXPECTED_PLACE,
--       tabs = { "Main", "Settings" },        -- omit for a single-page module
--       standaloneSize = Vector2.new(760, 560),
--       keep = { S.folder },                  -- ESP layers stay in CoreGui
--       live = live, conns = S.conns, cfg = CFG, save = queueSave, guard = guard,
--       onUnload = destroy, onReload = reloadSelf,
--   })
--   local W    = Shell.W                      -- the bound widget table
--   local page = Shell.page("Main")           -- ScrollingFrame, auto-reflowing
--   W.section(page, "Autofish"); W.toggle(page, { ... })
--   Shell.ready()                             -- after the last control
--
-- WHAT IT OWNS, so a module never can
--   * host detection, and the two mounting modes:
--       hosted     -> root FILLS the hub host, no ScreenGui, no drag, no blur,
--                     no reload chip (the hub's page strip owns reload)
--       standalone -> own ScreenGui under cloned CoreGui, own drag, own resize
--                     grip, own reload chip, size persisted by the caller's cfg
--   * header (icon/title/version/subtitle), tab strip, content area, footer
--   * resize: every page re-measures and reflows; the kit owns CanvasSize
--   * RightShift: inert when hosted (S6.1 r4 -- the blank-tab bug)
--   * forced-visible root, so a saved "hidden" cannot blank a hub tab (r5)
--   * teardown that rides the module's own screen (r9)
--   * contract attributes, so tools/ui_assert.lua can prove ancestry, fill and
--     binding instead of guessing at CoreGui
--
-- The module supplies content and behaviour. It does not supply geometry,
-- colour, font or chrome, and there is no argument here that lets it.
--==========================================================================
local SHELL_MIN = Vector2.new(560, 420)

function Kit.moduleShell(o)
	o = o or {}
	assert(type(o.id) == "string" and o.id ~= "", "moduleShell: id is required")

	local S = { contract = Kit.SHELL_CONTRACT, id = o.id, conns = o.conns or {} }
	local pages, pageOrder = {}, {}
	local currentTab

	-- ---- mount ---------------------------------------------------------
	local H = Kit.host({ hostGlobal = o.hostGlobal, keep = o.keep })
	S.hosted = H.hosted
	S.host = H

	local size = o.standaloneSize or Vector2.new(760, 560)
	local screen, root

	if H.hosted then
		-- No ScreenGui, no blur, no drag, no border: the hub owns all four, and a
		-- second one of any of them is the bug this contract replaced.
		root = new("Frame", {
			Name = "R3ST_" .. o.id,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			Position = UDim2.fromOffset(0, 0),
			Active = true,
			Visible = true,
		}, H.frame)
		screen = root -- teardown target; the hub owns the real ScreenGui
	else
		local core = game:GetService("CoreGui")
		if type(cloneref) == "function" then
			local ok, copy = pcall(cloneref, core)
			if ok and copy then core = copy end
		end
		screen = new("ScreenGui", {
			Name = "R3ST_" .. o.id .. "_" .. tostring(math.random(1000, 9999)),
			ResetOnSpawn = false,
			IgnoreGuiInset = true,
			ZIndexBehavior = Enum.ZIndexBehavior.Global,
			DisplayOrder = o.displayOrder or 2147483647,
		}, core)
		pcall(sethiddenproperty, screen, "OnTopOfCoreBlur", true)
		root = new("Frame", {
			Name = "R3ST_" .. o.id,
			BackgroundColor3 = COL.bg,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, o.x or 0, 0.5, o.y or 0),
			Size = UDim2.fromOffset(size.X, size.Y),
			Active = true,
			Visible = true,
		}, screen)
		corner(root, Kit.RADIUS.window)
		stroke(root, COL.line)
	end
	S.screen, S.root = screen, root

	-- Contract metadata. tools/ui_assert.lua and hub inspection read these, so
	-- "is exactly one root mounted, under the right host, filling it, with bound
	-- controls" is answerable without walking CoreGui and guessing.
	root:SetAttribute("R3ST_ModuleRoot", o.id)
	root:SetAttribute("R3ST_Contract", Kit.SHELL_CONTRACT)
	root:SetAttribute("R3ST_Hosted", H.hosted and true or false)
	root:SetAttribute("R3ST_Build", tostring(o.version or "?"))

	-- ---- chrome --------------------------------------------------------
	local inner = new("Frame", {
		Name = "Inner",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(H.hosted and 12 or 18, H.hosted and 8 or 14),
		Size = UDim2.new(1, H.hosted and -24 or -36, 1, H.hosted and -16 or -28),
	}, root)
	S.inner = inner

	local W = Kit.bind({
		live = o.live, conns = S.conns, guard = o.guard,
		isVisible = function() return Kit.isVisible(root) end,
		cfg = o.cfg, save = o.save, saveDelay = o.saveDelay,
	})
	S.W = W

	local compact = H.hosted and o.compactHosted
	if not compact then
		W.header(inner, {
			title = o.title or o.id,
			version = o.version,
			subtitle = o.subtitle,
			gameId = o.gameId,
			placeId = o.placeId,
			onInfo = o.onInfo,
		})
	end
	local HEADER_H, FOOTER_H = compact and 0 or 84, compact and 0 or 52
	local top = HEADER_H
	if o.tabs and #o.tabs > 0 then
		currentTab = o.tabs[1]
		local _, repaint = W.tabstrip(inner, {
			names = o.tabs,
			position = UDim2.fromOffset(0, HEADER_H),
			get = function() return currentTab end,
			set = function(name) S.show(name) end,
		})
		S.repaintTabs = repaint
		top = HEADER_H + 40
	end

	local body = new("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, top),
		Size = UDim2.new(1, 0, 1, -(top + FOOTER_H)),
	}, inner)
	S.body = body

	-- ---- pages ---------------------------------------------------------
	-- One ScrollingFrame per tab, registered with Kit.page so it measures itself,
	-- reflows on resize and owns its own CanvasSize.
	function S.page(name, opts)
		name = name or "Main"
		if pages[name] then return pages[name] end
		local p = new("ScrollingFrame", {
			Name = name,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			ScrollBarThickness = 3,
			ScrollBarImageColor3 = COL.lineStrong,
			CanvasSize = UDim2.new(),
			-- A ScrollingFrame defaults to Active = false, and then it never
			-- captures the wheel or a drag -- the canvas is the right height, the
			-- scrollbar is there, and the page simply will not move. It stayed
			-- invisible for as long as every page fit its viewport; the first page
			-- to outgrow one (illegal-soccer, canvas 834 vs view 466) could not be
			-- scrolled at all. Measured live on PID 18392, 2026-09-09.
			Active = true,
			ScrollingEnabled = true,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			Visible = (currentTab == nil or currentTab == name),
		}, body)
		Kit.page(p, opts)
		pages[name] = p
		pageOrder[#pageOrder + 1] = name
		if currentTab == nil then currentTab = name end
		return p
	end

	function S.show(name)
		if not pages[name] then return false end
		local changed = currentTab ~= name
		currentTab = name
		for n, p in pairs(pages) do
			if n == name then
				if changed then Kit.pageIn(p) else p.Visible = true end
			else
				p.Visible = false
			end
		end
		if S.repaintTabs then S.repaintTabs() end
		return true
	end

	-- ---- footer --------------------------------------------------------
	-- Reload is CONTEXTUAL and this is the whole rule: embedded, the hub's page
	-- strip already draws one and a second control for one action is exactly the
	-- drift this contract exists to stop; standalone, there is no hub strip, so
	-- the shell draws it. Neither branch is the module's decision.
	if not compact then
		local _, unload, settings, reload = W.footer(inner, {
			onUnload = o.onUnload,
			onSettings = o.onSettings,
			onReload = (not H.hosted) and o.onReload or nil,
			hint = o.hint or (H.hosted
				and "The hub owns the window and the hide key"
				or "RightShift hides this panel"),
		})
		S.unloadBtn, S.settingsBtn, S.reloadBtn = unload, settings, reload
	end

	-- ---- standalone-only chrome ----------------------------------------
	if not H.hosted then
		-- Drag by the header band.
		local dragging, dragStart, startPos, touch
		S.conns[#S.conns + 1] = root.InputBegan:Connect(function(i)
			if i.UserInputType ~= Enum.UserInputType.MouseButton1
				and i.UserInputType ~= Enum.UserInputType.Touch then return end
			if i.Position.Y - root.AbsolutePosition.Y > 76 then return end
			dragging, dragStart, startPos = true, i.Position, root.Position
			touch = i.UserInputType == Enum.UserInputType.Touch and i or nil
		end)
		S.conns[#S.conns + 1] = UserInputService.InputChanged:Connect(function(i)
			if dragging and ((touch and i == touch) or (not touch
				and i.UserInputType == Enum.UserInputType.MouseMovement)) then
				local d = i.Position - dragStart
				root.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
					startPos.Y.Scale, startPos.Y.Offset + d.Y)
			end
		end)
		S.conns[#S.conns + 1] = UserInputService.InputEnded:Connect(function(i)
			if dragging and ((touch and i == touch) or (not touch
				and i.UserInputType == Enum.UserInputType.MouseButton1)) then
				dragging, touch = false, nil
				if o.onMove then pcall(o.onMove, root.Position.X.Offset, root.Position.Y.Offset) end
			end
		end)
		-- The same grip the hub has, for the same reason: a wider window gains
		-- content because the pages reflow into it.
		local _, gripConns = Kit.resizeGrip(root, {
			min = o.minSize or SHELL_MIN,
			onCommit = o.onResizeCommit,
		})
		for _, c in ipairs(gripConns or {}) do S.conns[#S.conns + 1] = c end
	end

	-- RightShift: real when standalone, inert when hosted. hideBind enforces both
	-- sides, so a module physically cannot blank its own hub tab.
	function S.hideBind(fn)
		local c = H.hideBind(fn or function() root.Visible = not root.Visible end)
		if c then S.conns[#S.conns + 1] = c end
		return c
	end

	-- ---- lifecycle -----------------------------------------------------
	-- Call after the last control is built. Lays every page out once against its
	-- real measured width, which is also what sets the initial CanvasSize.
	function S.ready()
		task.defer(function()
			for _, name in ipairs(pageOrder) do
				local p = pages[name]
				if p and p.Parent and p.AbsoluteSize.X > 200 then
					Kit.relayout(p, p.AbsoluteSize.X)
				end
			end
		end)
		return S
	end

	function S.destroy()
		for _, c in ipairs(S.conns) do pcall(function() c:Disconnect() end) end
		for _, c in ipairs(H.conns or {}) do pcall(function() c:Disconnect() end) end
		if screen and screen.Parent then screen:Destroy() end
	end

	S.pages = pages
	return S
end

return Kit
