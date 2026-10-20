-- R3ST UI kit v2026-09-23.1
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
Kit.VERSION = "2026-09-23.1"

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
Kit.COL = {
	bg = Color3.fromRGB(9, 9, 11),
	panel = Color3.fromRGB(20, 20, 24),
	card = Color3.fromRGB(30, 30, 36),
	row = Color3.fromRGB(40, 40, 48),
	rowHover = Color3.fromRGB(52, 52, 62),
	line = Color3.fromRGB(58, 58, 70),
	lineSoft = Color3.fromRGB(40, 40, 48),
	text = Color3.fromRGB(242, 242, 247),
	dim = Color3.fromRGB(152, 152, 164),
	faint = Color3.fromRGB(110, 110, 122),
	white = Color3.fromRGB(255, 255, 255),
	good = Color3.fromRGB(72, 205, 57),
	bad = Color3.fromRGB(255, 120, 120),
	knobOff = Color3.fromRGB(126, 126, 138),
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
Kit.ROLE = {
	title   = { size = Kit.TYPE.title, font = Enum.Font.GothamBold },   -- module name
	heading = { size = Kit.TYPE.head,  font = Enum.Font.GothamBold },   -- card title
	control = { size = Kit.TYPE.body,  font = Enum.Font.GothamBold },   -- toggle/slider label
	value   = { size = Kit.TYPE.body,  font = Enum.Font.GothamBold },   -- the number a slider shows
	body    = { size = Kit.TYPE.body,  font = Enum.Font.GothamMedium }, -- prose
	caption = { size = Kit.TYPE.small, font = Enum.Font.GothamMedium }, -- desc / note / status
	micro   = { size = Kit.TYPE.micro, font = Enum.Font.GothamMedium }, -- legal-print only
	tab     = { size = Kit.TYPE.small, font = Enum.Font.GothamBold },
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
	-- Only a CanvasGroup can fade a whole panel; fading a plain Frame's
	-- BackgroundTransparency makes the ground vanish while every child stays
	-- fully opaque, which looks worse than not fading at all. So: fade when the
	-- caller gave us something that can, scale-lift always.
	local t
	if frame:IsA("CanvasGroup") then
		frame.GroupTransparency = 1
		t = tween(frame, { GroupTransparency = 0 }, Kit.MOTION.base)
	end
	local st = scaleObj and tween(scaleObj, { Scale = target }, Kit.MOTION.base) or nil
	t = t or st
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
	local t = scaleObj and tween(scaleObj, { Scale = target * 0.97 }, Kit.MOTION.fast) or nil
	if frame:IsA("CanvasGroup") then
		t = tween(frame, { GroupTransparency = 1 }, Kit.MOTION.fast) or t
	end
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
-- Page switch. A CanvasGroup fades as one object, which is the whole reason
-- newPage builds pages as CanvasGroups: the first version looked for a
-- CanvasGroup CHILD, pages were plain Frames, so every page switch silently did
-- nothing at all. If a caller still hands us a Frame, slide it instead of
-- pretending -- a dead animation path is worse than an honest one.
function Kit.pageIn(frame)
	frame.Visible = true
	if Kit.reduceMotion then return end
	if frame:IsA("CanvasGroup") then
		frame.GroupTransparency = 1
		frame.Position = UDim2.new(frame.Position.X.Scale, frame.Position.X.Offset, 0, 6)
		tween(frame, { GroupTransparency = 0, Position = UDim2.new(frame.Position.X.Scale, frame.Position.X.Offset, 0, 0) }, 0.12)
		return
	end
	local base = frame.Position
	frame.Position = UDim2.new(base.X.Scale, base.X.Offset, base.Y.Scale, base.Y.Offset + 6)
	tween(frame, { Position = base }, 0.12)
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

function Kit.interactive(btn, strokeObj, baseColor)
	local base = baseColor or btn.BackgroundColor3
	local hoverCol = Kit.COL.rowHover
	local down = false
	local inside = false
	-- A press must MOVE something. Colour alone is what made every button in the
	-- product feel like a coloured rectangle: hover tinted, click did nothing the
	-- eye could catch. 0.97 is a press, not a bounce -- it eases down and eases
	-- back with no overshoot (hub S9.3: no bounce/elastic/spring, ever).
	local scale = btn:FindFirstChildOfClass("UIScale")
	local function paint()
		local d = Kit.MOTION.fast
		if strokeObj then
			Kit.tween(strokeObj, { Color = (inside or down) and Kit.COL.white or Kit.COL.line }, d)
		end
		Kit.tween(btn, { BackgroundColor3 = down and Kit.COL.line or (inside and hoverCol or base) }, d)
		if scale then Kit.tween(scale, { Scale = down and 0.97 or 1 }, d) end
	end
	btn.MouseEnter:Connect(function() inside = true; paint() end)
	btn.MouseLeave:Connect(function() inside = false; down = false; paint() end)
	btn.MouseButton1Down:Connect(function()
		down = true
		-- Create the UIScale lazily: a button that is never pressed never pays for
		-- one, and adding it here keeps every existing call site working unchanged.
		if not scale then scale = attachScale(btn) end
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
			Kit.tween(strokeObj, { Color = on and Kit.COL.white or Kit.COL.line }, Kit.MOTION.fast)
		end
	end
	frame.MouseEnter:Connect(function() paint(true) end)
	frame.MouseLeave:Connect(function() paint(false) end)
	return paint
end

-- Card entrance, staggered. A page of cards that all appear on the same frame
-- reads as a screenshot; 25ms apart reads as the page building itself. Capped at
-- 6 steps so a long page never makes the user wait on choreography.
-- SCALE ONLY -- deliberately does NOT touch Position.
--
-- The first version captured frame.Position, offset it by 8px and tweened back
-- after the stagger delay. That is a latent misplacement bug: Kit.page defers a
-- relayout to the next frame and Kit.relayout owns Position, so a reflow landing
-- inside the 0-150ms stagger window would move the card while this tween was
-- still flying it back to a Position captured BEFORE the move. The card would
-- settle at a stale coordinate and nothing would correct it.
--
-- Two writers for one property is the bug; the fix is one writer. Position
-- belongs to relayout, scale belongs to the entrance.
function Kit.enter(frame, index)
	if Kit.reduceMotion then return end
	local scale = attachScale(frame)
	scale.Scale = 0.97
	task.delay(math.min((index or 1) - 1, 6) * 0.025, function()
		if not frame.Parent then return end
		Kit.tween(scale, { Scale = 1 }, Kit.MOTION.base)
	end)
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
		new("UIStroke", { Color = opts.color or Color3.new(1, 1, 1), Thickness = opts.thickness or 1.5 }, f)
	end
	return f
end

-- Each entry draws itself into a unit box. Keep them to bars, rotated bars and
-- circles: anything that needs a real path belongs in an image asset, not here.
local ICONS = {}

ICONS.dot = function(b, c) ipart(b, .5, .5, .42, .42, 0, { color = c, round = .5 }) end

ICONS.home = function(b, c)
	ipart(b, .33, .30, .55, .13, -42, { color = c, round = .5 })
	ipart(b, .67, .30, .55, .13, 42, { color = c, round = .5 })
	ipart(b, .5, .70, .58, .46, 0, { color = c, hollow = true, round = .12 })
end

ICONS.star = function(b, c) ipart(b, .5, .5, .58, .58, 45, { color = c, hollow = true, round = .12 }) end
ICONS.starOn = function(b, c) ipart(b, .5, .5, .58, .58, 45, { color = c, round = .12 }) end

ICONS.clock = function(b, c)
	ipart(b, .5, .5, .84, .84, 0, { color = c, hollow = true, round = .5 })
	ipart(b, .5, .36, .09, .30, 0, { color = c, round = .5 })   -- hand, up
	ipart(b, .63, .55, .30, .09, 0, { color = c, round = .5 })  -- hand, right
end

ICONS.terminal = function(b, c)
	ipart(b, .5, .5, .92, .78, 0, { color = c, hollow = true, round = .12 })
	ipart(b, .36, .40, .26, .10, 45, { color = c, round = .5 })
	ipart(b, .36, .58, .26, .10, -45, { color = c, round = .5 })
	ipart(b, .64, .66, .26, .10, 0, { color = c, round = .5 })
end

-- Three bars at different heights: motion, which is what Anims is.
ICONS.anims = function(b, c)
	ipart(b, .22, .5, .16, .50, 0, { color = c, round = .5 })
	ipart(b, .5, .5, .16, .88, 0, { color = c, round = .5 })
	ipart(b, .78, .5, .16, .64, 0, { color = c, round = .5 })
end

ICONS.gear = function(b, c)
	ipart(b, .5, .5, .62, .62, 0, { color = c, hollow = true, round = .5 })
	ipart(b, .5, .06, .20, .18, 0, { color = c, round = .3 })
	ipart(b, .5, .94, .20, .18, 0, { color = c, round = .3 })
	ipart(b, .06, .5, .18, .20, 0, { color = c, round = .3 })
	ipart(b, .94, .5, .18, .20, 0, { color = c, round = .3 })
end

ICONS.info = function(b, c)
	ipart(b, .5, .5, .92, .92, 0, { color = c, hollow = true, round = .5 })
	ipart(b, .5, .28, .13, .13, 0, { color = c, round = .5 })
	ipart(b, .5, .62, .13, .38, 0, { color = c, round = .5 })
end

-- A right chevron, not a triangle: two bars need no clipping trick and read the
-- same at 12px.
ICONS.play = function(b, c)
	ipart(b, .44, .32, .52, .13, 48, { color = c, round = .5 })
	ipart(b, .44, .68, .52, .13, -48, { color = c, round = .5 })
end

ICONS.dash = function(b, c) ipart(b, .5, .5, .62, .12, 0, { color = c, round = .5 }) end
ICONS.minus = ICONS.dash

ICONS.plus = function(b, c)
	ipart(b, .5, .5, .62, .12, 0, { color = c, round = .5 })
	ipart(b, .5, .5, .12, .62, 0, { color = c, round = .5 })
end

ICONS.close = function(b, c)
	ipart(b, .5, .5, .74, .12, 45, { color = c, round = .5 })
	ipart(b, .5, .5, .74, .12, -45, { color = c, round = .5 })
end

ICONS.check = function(b, c)
	ipart(b, .32, .64, .34, .12, 45, { color = c, round = .5 })
	ipart(b, .60, .48, .70, .12, -45, { color = c, round = .5 })
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
	corner(frame, 10)
	local frameStroke = stroke(frame, COL.line)
	local t = label(frame, title, Kit.ROLE.heading.size, COL.text, CARD_PAD, 8, 0, 22)
	t.Size = UDim2.new(1, -CARD_PAD * 2, 0, 22)
	t.Font = Kit.ROLE.heading.font
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
				acc = 0
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
		local name = label(box, o.label, Kit.ROLE.control.size, COL.text, 0, o.desc and 2 or 0, 0, o.desc and 18 or h)
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
			stateLabel.Font = Enum.Font.GothamBold
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
			tween(knob, {
				Position = UDim2.new(0, on and 25 or 3, 0.5, 0),
				BackgroundColor3 = on and COL.white or COL.knobOff,
			}, d)
			tween(track, { BackgroundColor3 = on and Color3.fromRGB(70, 72, 78) or COL.row }, d)
			tween(st, { Color = on and COL.white or COL.line }, d)
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
				set(not get())
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
		local val = label(box, "", Kit.ROLE.value.size, COL.white, 0, 0, 130, 18, Enum.TextXAlignment.Right)
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
		stampControl(box, "slider", o.key, type(set) == "function")
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
			Font = Kit.ROLE.control.font,
			TextSize = Kit.ROLE.control.size,
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
			corner(info, 8)
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
				Font = Kit.ROLE.tab.font,
				TextSize = Kit.ROLE.tab.size,
				TextColor3 = COL.dim,
				Text = name,
				AutoButtonColor = false,
			}, strip)
			corner(b, 7)
			local s = stroke(b, COL.line)
			btns[name] = { b = b, s = s }
			stampControl(b, "tab", nil, type(o.set) == "function")
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
			corner(b, 8)
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
		if o.onUnload then unload = chip("close", "Unload script", false, 170, o.onUnload) end
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
			DisplayOrder = 2147483647,
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
		corner(root, 12)
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
		cfg = o.cfg, save = o.save, saveDelay = o.saveDelay,
	})
	S.W = W

	W.header(inner, {
		title = o.title or o.id,
		version = o.version,
		subtitle = o.subtitle,
		gameId = o.gameId,
		placeId = o.placeId,
		onInfo = o.onInfo,
	})

	local HEADER_H, FOOTER_H = 84, 52
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
			ScrollBarImageColor3 = COL.line,
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
		currentTab = name
		for n, p in pairs(pages) do
			if n == name then
				Kit.pageIn(p)
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
	local _, unload, settings, reload = W.footer(inner, {
		onUnload = o.onUnload,
		onSettings = o.onSettings,
		onReload = (not H.hosted) and o.onReload or nil,
		hint = o.hint or (H.hosted
			and "The hub owns the window and the hide key"
			or "RightShift hides this panel"),
	})
	S.unloadBtn, S.settingsBtn, S.reloadBtn = unload, settings, reload

	-- ---- standalone-only chrome ----------------------------------------
	if not H.hosted then
		-- Drag by the header band.
		local dragging, dragStart, startPos
		S.conns[#S.conns + 1] = root.InputBegan:Connect(function(i)
			if i.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
			if i.Position.Y - root.AbsolutePosition.Y > 76 then return end
			dragging, dragStart, startPos = true, i.Position, root.Position
		end)
		S.conns[#S.conns + 1] = UserInputService.InputChanged:Connect(function(i)
			if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then
				local d = i.Position - dragStart
				root.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
					startPos.Y.Scale, startPos.Y.Offset + d.Y)
			end
		end)
		S.conns[#S.conns + 1] = UserInputService.InputEnded:Connect(function(i)
			if dragging and i.UserInputType == Enum.UserInputType.MouseButton1 then
				dragging = false
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
