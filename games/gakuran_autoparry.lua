-- ==========================================================
--  Gakuran autoparry v2026-10-24.2 (2026-10-24) — gen53 backend, Hub UI port.
--  Policy: M1/light → parry only; M2/heavy + grab/slam → Evasive dodge.
--  Never clears Blocking mid-Perfect for lights (standalone autododge race fixed).
--  Re-inject safe: self-teardown on load; K = unload
--  UNLOADS_ON_INJECT: __GAKURAN_AUTODODGE
--  gen52: Hold Stop→Start remount + drop lastParry pump freeze.
--  Logs: EXP_FLAGS, PRECISION_SCHED, EDGE, DODGE_*, RATE_SNAP, FX_CORRELATE.
--  Keep: HOLD, Deactivate on PERFECT/BLOCK FX, gen45 dodge CD.
--  PlaceId: 128736949265057
--  Changelog:
--    2026-10-24.2: kit shell, keyed ON/OFF autosave, owned UI teardown; backend unchanged.
-- ==========================================================

local BUILD_VERSION = "2026-10-24.2"
local PLACE_ID = 128736949265057
local GUI_NAME = "GakuranAutoparryHUD"
local LOG_FILE = "logs/gakuran_autoparry.log"
local EVENTS_FILE = "logs/gakuran_autoparry_events.jsonl"
local UI_CFG_FILE = "config/gakuran_autoparry_ui.json"
local TIMING_CFG_FILE = "config/gakuran_autoparry_timing.json"
local MIN_CONFIRM_INTERVAL = 0.04
local MIN_BLOCK_INTERVAL = 0.034
local NEAR_MARGIN = 1.75
-- AUTOPARRY_TRUTH R1: fire on ChildAdded, gate on ATTACKER proximity, not hitbox-part
-- geometry. Part position at spawn is unreliable; attacker HRP distance is the honest
-- "can this hit me" test. Recall beats precision — hitbox lives 0.15s, rarely overlaps
-- a bystander. gen6: only 3 opener_taps vs 80 SKIP=far — attacker sits just outside the
-- gate at hitbox spawn, so widen to catch the opener while still unstunned (→ BranchC).
local DEFAULT_FORCE_RESOLVE_DELAY = 0.055
local styleForceDelay = {}
local stylePerfectLead = {}
local styleLatencyEma = {} -- combo1 windup→hitbox only when PATH2 on
local styleGapEma = {} -- key → { [1]=gap, [2]=… [4]=… } inter-hitbox for combo≥2
local styleStats = {} -- key → { perfect=0, block=0, hit=0 }
local DEFAULT_PERFECT_LEAD = 0.045
local LEARN_ALPHA = 0.40
local LEARN_FORCE_STEP = 0.012
local LEARN_FORCE_MIN = 0.02
local LEARN_FORCE_MAX = 0.12
local LEARN_LEAD_MIN = 0.02
local LEARN_LEAD_MAX = 0.14
local LEARN_FRESH_MAX = 0.15 -- HIT learn window
local LEARN_BLOCK_FRESH_MAX = 0.35 -- precision BLOCK often dt=0.16–0.32; still trainable
local FORCE_REFRESH_GAP = 0.05 -- second Activate to refresh PerfectBlocking (PATH1 off only)
local DEFAULT_WINDUP_LATENCY = 0.12
local LATENCY_EMA_ALPHA = 0.30
local GAP_EMA_ALPHA = 0.30
local GAP_MIN = 0.25
local GAP_MAX = 0.90
local PERFECT_WINDOW = 0.125
-- gen6 log: OK swings had dt_activated_confirm≈0.047; every DMG≈0.017. Our Activated
-- leaves on time (dt_hitbox_activated 2-3ms) but the victim confirm fires ~17ms later —
-- before the Activated round-trips and the server sets PerfectBlocking. Hold our own
-- outgoing confirm so the Activated registers first, pushing dt_a2c into the win zone.
-- Budget = HitboxDuration 0.15s, so a ~50ms hold is safe.
local G = getgenv()
local HOST = G.__R3ST_HOST
local GKEY = "__GAKURAN_AUTOPARRY"
local GKEY_CRC = "__GAKURAN_CRC_ORIG_FIRE"
local GKEY_SRV = "__GAKURAN_SERVER_ORIG_FIRE"
local GKEY_NC = "__GAKURAN_AUTOPARRY_ORIG_NAMECALL"
local emitEvent

local function jsonEsc(s)
    s = tostring(s)
    s = s:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r")
    return s
end

local function jsonNum(n)
    if typeof(n) ~= "number" or n ~= n then return "null" end
    return string.format("%.3f", n)
end

-- ---------- file logger ----------
local Log do
    local function ensureDir()
        pcall(function()
            if isfolder and not isfolder("logs") then makefolder("logs") end
        end)
    end
    -- gen24: STEP/INFO/DEBUG go to LOG_FILE only — console (F9) stays clean for real problems.
    -- Only WARN/ERR still warn() to console. User explicitly asked for enhanced logging that
    -- lives in the .log, not spamming the on-screen console.
    local CONSOLE_LEVELS = { WARN = true, ERR = true }
    local function write(level, msg)
        ensureDir()
        local line = string.format("[%s] [%s] %s", os.date("%H:%M:%S"), level, tostring(msg))
        pcall(function()
            if appendfile and isfile and isfile(LOG_FILE) then
                appendfile(LOG_FILE, line .. "\n")
            elseif writefile then
                writefile(LOG_FILE, line .. "\n")
            end
        end)
        if CONSOLE_LEVELS[level] then
            warn("[autoparry] " .. line)
        end
    end
    Log = {
        session = function(extra)
            ensureDir()
            -- gen36: header used to hardcode gen=? (real gen only lived in `extra`). Keep both.
            local hdr = string.format(
                "========== %s place=%s job=%s ==========\n%s\n",
                os.date("%Y-%m-%d %H:%M:%S"),
                tostring(game and game.PlaceId or "?"),
                tostring(game and game.JobId or "?"),
                extra or ""
            )
            pcall(function()
                if appendfile and isfile and isfile(LOG_FILE) then
                    appendfile(LOG_FILE, "\n" .. hdr)
                elseif writefile then
                    writefile(LOG_FILE, hdr)
                end
            end)
            warn("[autoparry] log -> " .. LOG_FILE)
        end,
        info = function(m) write("INFO", m) end,
        warn = function(m) write("WARN", m) end,
        err = function(m) write("ERR", m) end,
        step = function(m) write("STEP", m) end,
        debug = function(m) write("DEBUG", m) end,
    }
end

-- ---------- UI persist ----------
local function ensureConfigDir()
    pcall(function()
        if isfolder and not isfolder("config") then makefolder("config") end
    end)
end

local KEY_LABELS = {
    RightShift = "RShift",
    LeftShift = "LShift",
    RightControl = "RCtrl",
    LeftControl = "LCtrl",
    RightAlt = "RAlt",
    LeftAlt = "LAlt",
}

local function keyLabel(kc)
    if typeof(kc) ~= "EnumItem" then return "?" end
    local mapped = KEY_LABELS[kc.Name]
    if mapped then return mapped end
    local n = kc.Name
    if #n > 7 then n = string.sub(n, 1, 7) end
    return n
end

local function keyFromName(name)
    if type(name) ~= "string" or name == "" then return nil end
    local ok, kc = pcall(function() return Enum.KeyCode[name] end)
    if ok and typeof(kc) == "EnumItem" then return kc end
    return nil
end

local function loadUiConfig(enabled)
    local cfg = { hideKey = "RightShift", hudVisible = true, enabled = enabled }
    pcall(function()
        if not isfile or not readfile or not isfile(UI_CFG_FILE) then return end
        local raw = readfile(UI_CFG_FILE)
        local saved = game:GetService("HttpService"):JSONDecode(raw)
        if type(saved) ~= "table" then return end
        if keyFromName(saved.hideKey) then cfg.hideKey = saved.hideKey end
        if type(saved.hudVisible) == "boolean" then cfg.hudVisible = saved.hudVisible end
        if type(saved.enabled) == "boolean" then cfg.enabled = saved.enabled end
    end)
    return cfg
end

local function saveUiConfig(hideKey, hudVisible, enabled)
    ensureConfigDir()
    local name = (typeof(hideKey) == "EnumItem" and hideKey.Name) or "RightShift"
    local body = string.format('{"hideKey":"%s","hudVisible":%s,"enabled":%s}\n',
        jsonEsc(name), hudVisible and "true" or "false", enabled and "true" or "false")
    pcall(function()
        if writefile then writefile(UI_CFG_FILE, body) end
    end)
end

-- gen41/46: persist per-style learner (+ optional gap1..gap4 for PATH2)
local function saveTimingLearn()
    ensureConfigDir()
    local parts = { '{"styles":{' }
    local first = true
    local keys = {}
    for k in pairs(styleForceDelay) do keys[#keys + 1] = k end
    for k in pairs(stylePerfectLead) do keys[#keys + 1] = k end
    for k in pairs(styleLatencyEma) do keys[#keys + 1] = k end
    for k in pairs(styleGapEma) do keys[#keys + 1] = k end
    table.sort(keys)
    local seen = {}
    for _, k in ipairs(keys) do
        if not seen[k] and k ~= "styles" then
            seen[k] = true
            if not first then parts[#parts + 1] = "," end
            first = false
            local st = styleStats[k] or {}
            local fd = styleForceDelay[k] or DEFAULT_FORCE_RESOLVE_DELAY
            local pl = stylePerfectLead[k] or DEFAULT_PERFECT_LEAD
            local lat = styleLatencyEma[k] or DEFAULT_WINDUP_LATENCY
            local gaps = styleGapEma[k] or {}
            parts[#parts + 1] = string.format(
                '"%s":{"forceDelay":%.4f,"precisionLead":%.4f,"latency":%.4f' ..
                    ',"perfect":%d,"block":%d,"hit":%d,"gap1":%.4f,"gap2":%.4f,"' ..
                    'gap3":%.4f,"gap4":%.4f}',
                jsonEsc(k), fd, pl, lat, st.perfect or 0, st.block or 0, st.hit or 0,
                gaps[1] or 0, gaps[2] or 0, gaps[3] or 0, gaps[4] or 0
            )
        end
    end
    parts[#parts + 1] = "}}\n"
    pcall(function()
        if writefile then writefile(TIMING_CFG_FILE, table.concat(parts)) end
    end)
end

local function loadTimingLearn()
    pcall(function()
        if not isfile or not readfile or not isfile(TIMING_CFG_FILE) then return end
        local raw = readfile(TIMING_CFG_FILE)
        for style, body in string.gmatch(raw, '"([%w_]+)"%s*:%s*{([^}]+)}') do
            -- outer JSON key "styles" must not become a fake style row (gen43 poison)
            if style ~= "styles" then
                local fd = tonumber(string.match(body, '"forceDelay"%s*:%s*([%d%.]+)'))
                local pl = tonumber(string.match(body, '"precisionLead"%s*:%s*([%d%.]+)'))
                local lat = tonumber(string.match(body, '"latency"%s*:%s*([%d%.]+)'))
                local pf = tonumber(string.match(body, '"perfect"%s*:%s*(%d+)'))
                local bl = tonumber(string.match(body, '"block"%s*:%s*(%d+)'))
                local ht = tonumber(string.match(body, '"hit"%s*:%s*(%d+)'))
                if fd then styleForceDelay[style] = math.clamp(fd, LEARN_FORCE_MIN, LEARN_FORCE_MAX)
                    end
                if pl then stylePerfectLead[style] = math.clamp(pl, LEARN_LEAD_MIN, LEARN_LEAD_MAX)
                    end
                if lat then styleLatencyEma[style] = math.clamp(lat, 0, 0.45) end
                styleStats[style] = { perfect = pf or 0, block = bl or 0, hit = ht or 0 }
                local gtab = {}
                for i = 1, 4 do
                    local g = tonumber(string.match(body, '"gap' .. i .. '"%s*:%s*([%d%.]+)'))
                    if g and g >= GAP_MIN and g <= GAP_MAX then
                        gtab[i] = g
                    end
                end
                if next(gtab) then styleGapEma[style] = gtab end
                Log.step(string.format(
                    "TIMING_LOAD style=%s forceDelay=%.3f lead=%.3f " ..
                        "latency=%.3f P/B/H=%d/%d/%d gaps=%.3f/%.3f/%.3f/%.3f",
                    style,
                    styleForceDelay[style] or DEFAULT_FORCE_RESOLVE_DELAY,
                    stylePerfectLead[style] or DEFAULT_PERFECT_LEAD,
                    styleLatencyEma[style] or DEFAULT_WINDUP_LATENCY,
                    styleStats[style].perfect, styleStats[style].block, styleStats[style].hit,
                    gtab[1] or 0, gtab[2] or 0, gtab[3] or 0, gtab[4] or 0
                ))
            end
        end
    end)
end

local function sweepGui(player)
    if not player then return end
    local pg = player:FindFirstChild("PlayerGui")
    if not pg then return end
    for _, child in ipairs(pg:GetChildren()) do
        if child.Name == GUI_NAME then
            pcall(function() child:Destroy() end)
        end
    end
end

local function restoreHooks()
    pcall(function()
        local RS = game:GetService("ReplicatedStorage")
        local crc = require(RS.Shared.Network.CombatRemoteClient)
        local origCrc = G[GKEY_CRC]
        if origCrc and hookfunction then
            hookfunction(crc.Fire, origCrc)
        elseif origCrc then
            crc.Fire = origCrc
        end
        local srv = RS:WaitForChild("Remotes"):WaitForChild("Server")
        local origSrv = G[GKEY_SRV]
        if origSrv and hookfunction then
            hookfunction(srv.FireServer, origSrv)
        end
        local origNc = G[GKEY_NC]
        if origNc and hookmetamethod then
            hookmetamethod(game, "__namecall", origNc)
        end
    end)
end

local function teardownStale()
    local prevEnabled = true
    local old = G[GKEY]
    local oldGen = "none"
    if type(old) == "table" then
        oldGen = tostring(old.gen or "?")
        if type(old.enabled) == "function" then
            prevEnabled = old.enabled() == true
        end
        if type(old.destroy) == "function" then
            pcall(old.destroy)
        end
    end
    -- gen53: mutual exclusion — standalone autododge races Blocking clear vs Perfect
    local sib = G.__GAKURAN_AUTODODGE
    if type(sib) == "table" and type(sib.destroy) == "function" then
        pcall(sib.destroy)
        warn("[autoparry] unloaded sibling __GAKURAN_AUTODODGE (merged gen53)")
    end
    G.__GAKURAN_AUTODODGE = nil
    -- v2 rewrite mutual exclusion (scripts/gakuran_autoparry_v2.lua)
    local sibV2 = G.__GAKURAN_AUTOPARRY_V2
    if type(sibV2) == "table" and type(sibV2.destroy) == "function" then
        pcall(sibV2.destroy)
        warn("[autoparry] unloaded sibling __GAKURAN_AUTOPARRY_V2")
    end
    G.__GAKURAN_AUTOPARRY_V2 = nil
    restoreHooks()
    sweepGui(game:GetService("Players").LocalPlayer)
    G[GKEY] = nil
    Log.step("TEARDOWN killed old gen=" .. oldGen .. " prevEnabled=" .. tostring(prevEnabled))
    if emitEvent then
        emitEvent("TEARDOWN", { gen = oldGen, prevEnabled = prevEnabled })
    end
    return prevEnabled
end

local PREV_ENABLED = teardownStale()
local UI_CFG = loadUiConfig(PREV_ENABLED)

local CONFIG = {
    -- gen24: diagnostic overrides reverted. Root cause of the T/equip-fists regression found —
    -- pinDodgeCd/BlockCooldown-pin now gated behind CONFIG.ENABLED at their call sites (see
    -- main()) instead of only their own flags, so OFF is truly inert. ENABLED restored to
    -- previous toggle state (or saved UI choice); NO_DODGE_CD restored to true.
    ENABLED = UI_CFG.enabled,
    HUD_VISIBLE = UI_CFG.hudVisible,
    HIDE_KEY = keyFromName(UI_CFG.hideKey),
    PROACTIVE = true,
    NO_COOLDOWN = true,      -- pin BlockCooldown=nil (parry-every-hit) — ENABLED-gated, see main()
    -- gen45: Grant pin + mult nerf + UV clear (see pinDodgeCd) — ENABLED-gated
    NO_DODGE_CD = true,
    -- gen53 merged dodge (M2/heavy only — M1 stays parry):
    AUTO_DODGE = true,
    DODGE_M1 = false,            -- hard policy: lights → parry
    DODGE_M2 = true,             -- heavies → Evasive
    DODGE_GRAB_M2 = true,        -- kure/wrestling grab/slam
    DODGE_MAX_RANGE = 14,
    DODGE_FOV_DEG = 100,
    DODGE_REQUIRE_FACING = true,
    DODGE_IFRAME_LEAD = 0.25,
    DODGE_MIN_INTERVAL = 0.18,
    -- gen46 experiments (set false to A/B-remove one path without code delete):
    PATH1_PRECISION_ONLY = true, -- kill forceResolve + hitboxLive; precision taps only
    PATH2_GAP_EMA = true,        -- mid-combo from inter-hitbox gap EMA; latency=combo1 only
    -- one extra edge tap only for confirmed local hitbox overlap + M1 hold
    OVERLAP_EDGE_COVER = true,
    USE_BLOCK_MODULE = true,
    VERBOSE_SCAN = false,
    CONFIRM_HOLD = false,    -- gen7 proved dead; windup-prediction is the real path
    LOG_TAPS = true,         -- per-tap WINDUP_TAP lines (tuning)
    -- global __namecall hook = crash vector with admin.lua; vestigial, keep OFF
    NAMECALL_HOOK = false,
    REACTIVE_PARRY = false,  -- OFF: legacy hitbox/scan parry floods the server rate limit on a
                             -- SEPARATE gate from the windup ticker → server drops in-window taps →
                             -- HIT. Windup prediction is the parry now; reactive only sabotages it.
    DIAGNOSTICS = false,     -- high-volume scheduler/decision/NET STEP + JSON; outcomes stay logged
}

if game.PlaceId ~= PLACE_ID then
    Log.session("WRONG PLACE " .. tostring(game.PlaceId))
    Log.err("wrong PlaceId — expected " .. tostring(PLACE_ID))
    return
end

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local lp = Players.LocalPlayer

local Server = RS:WaitForChild("Remotes"):WaitForChild("Server")
local CRC = require(RS.Shared.Network.CombatRemoteClient)

local BlockMod = nil
pcall(function()
    BlockMod = require(RS.CombatSystemClient.Combat.Base.Block)
end)

-- gen28 M1-chain resume: dump decompile (scripts/0436.lua, ReplicatedStorage.CombatSystemClient.
-- Combat.Base.M1) confirms tryM1() hard-refuses whenever Character:GetAttribute("Blocking")==true
-- (also BlockAttackLockout) — nothing in that module auto-retries once Blocking clears, so a
-- parry mid-M1-hold silently stalls the chain until the player releases+re-presses M1. Same
-- require+pcall pattern already trusted for BlockMod. v1.OnM1Activated() just calls tryM1(); it's
-- internally reentrancy-guarded and gated on a dozen of its own attribute checks, so calling it
-- defensively (when it's not actually appropriate) is a safe no-op, not a forced action.
local M1Mod = nil
pcall(function()
    M1Mod = require(RS.CombatSystemClient.Combat.Base.M1)
end)

-- gen35: Evasive module for no-dodge-cd via upvalue clear (see pinDodgeCd)
local EvasiveMod = nil
pcall(function()
    EvasiveMod = require(RS.CombatSystemClient.Combat.Base.Evasive)
end)
local getuv = (debug and debug.getupvalue) or getupvalue
local setuv = (debug and debug.setupvalue) or setupvalue

-- gen15: style-aware logging. Per-attacker FX breakdown showed the miss rate is style-dependent
-- (different M1/M2HitboxDelay per CombatStyle), not a flat timing constant. styleOf() resolves via
-- the PlayerData.CombatStyle attribute (dump: values.txt, Workspace.Players.<name>.PlayerData) —
-- read-only, pre-existing, never implicated in any regression. gen20-22 tried adding a second,
-- LIVE resolve path (require(CombatAnimationUtils) + CombatConfig.GetStyleConfig calls) and that
-- coincided with the T/equip-fists regression; gen24 found the REAL cause elsewhere (pinDodgeCd
-- running unconditionally in main(), see there) and removed the live-API surface entirely in favor
-- of the static table below — no runtime require/call guessing left in the style-resolve path.
-- gen25 fix: PlayerData is NOT parented under the Players-service Player instance — dump
-- (attributes_catalog.txt) confirms the real path is Workspace.Players.<name>.PlayerData.
-- plr:FindFirstChild("PlayerData") was looking in the wrong place and silently failing ~2/3
-- of the time (style=? dominated the log: 3425 vs ~1729 resolved), which meant P0/P1 precision
-- timing rarely engaged and most swings fell back to the flat 70ms spray — the "inconsistent"
-- parry behavior. Read from Workspace.Players instead; cache per-name to avoid repeat lookups.
local styleCache = {}
local wsPlayersFolder = Workspace:FindFirstChild("Players")
local function styleOf(atkChar)
    local plr = Players:GetPlayerFromCharacter(atkChar)
    local name = plr and plr.Name
    if not name then return "?" end
    local cached = styleCache[name]
    if cached then return cached end
    wsPlayersFolder = wsPlayersFolder or Workspace:FindFirstChild("Players")
    local pd = wsPlayersFolder and wsPlayersFolder:FindFirstChild(name)
    pd = pd and pd:FindFirstChild("PlayerData")
    if pd then
        local s = pd:GetAttribute("CombatStyle")
        if type(s) == "string" and s ~= "" then
            styleCache[name] = s
            return s
        end
    end
    return "?"
end

-- gen31: rebuilt against the CombatConfig SOURCE directly (full_dump/scripts/0594.lua,
-- ReplicatedStorage.Shared.Config.CombatConfig, decompiled — not a guess, the real ModuleScript).
-- Every M1HitboxDelay/M2HitboxDelay/M1HitboxDelayOffsets value below is a byte-accurate
-- transcription
-- of that file's `Styles` table. This caught one real bug: karate's m1Offsets was previously
-- {0.0375, 0.1125, 0.1688, 0.225} (linearly interpolated guess from an earlier, incomplete dump
-- extract) — source actually gives {0.0375, 0.075, 0.15, 0.225}, fixed here.
-- `(def)` cells in the source inherit Shared M1.DefaultHitboxDelay=0.32 / M2.DefaultHitboxDelay=0.3
-- — encoded here as nil, resolved against DEFAULT_STYLE below.
--
-- gen29/gen30 found something the raw config numbers alone can't capture: live WINDUP_LEAD
-- measurement (our own windup-attribute-observed to hitbox-live timing, recorded during real
-- fights) ran ~0.17-0.22s HIGHER than the raw M1HitboxDelay for Wrestling/Hakari historically.
-- gen37: MuayThai live openers cluster ~0.30–0.42 with base 0.30 → latency ≈0.05–0.12, NOT 0.20.
-- per-style EMA adapts from WINDUP_LEAD (observeWindupLatency). Timing tables above (gen41).
local DEFAULT_STYLE = { m1 = 0.32, m2 = 0.30 }
local STYLE_DELAY_TABLE = {
    default    = { m1 = 0.32, m2 = 0.30 },
    basic      = { m2 = 0.525, m1Offsets = { 0.02, 0.02, 0.02, 0.02 } },
    boxing     = { m2 = 0.43, m1Offsets = { 0.02, 0.02, 0.02, 0.06 } },
    bulky      = { m2 = 0.43 },
    dirty      = {},  -- (def)/(def) — DirtyRevenge is a grapple-hit-count proc, not an M1/M2 clock
    hakari     = { m1 = 0.28, m2 = 0.59, m1Offsets = { 0.16, 0.18, 0.16, 0.21 } },
    -- gen31 fix
    karate = { m1 = 0.24, m2 = 0.4875, m1Offsets = { 0.0375, 0.075, 0.15, 0.225 } },
    -- Legendary; M2=grab/slam → ParryWindowDisabled 2s, dodge not Activated
    kure = { m1 = 0.32, dodgeM2 = true },
    muaythai   = { m1 = 0.30, m2 = 0.60 },
    skygaolang = { m2 = 0.35 },
    variant    = { m2 = 0.35 },
    taekwondo  = { m2 = 0.46 },
    wild       = { m2 = 0.525 },
    wingchun   = { m1 = 0.28, m2 = 0.525 },
    -- Legendary; M2=grab/slam, prefer dodge over spam
    wrestling = { m1 = 0.32, m2 = 0.525, dodgeM2 = true },
    capoeira   = { m1 = 0.33, m2 = 0.45, m1Offsets = { 0.02, 0.1, 0.02, -0.05 } },
    slugger    = { m1 = 0.20, m2 = 0.82, m1Offsets = { 0.30, 0.25, 0.25, 0.17 } },
}

local function normalizeStyleKey(style)
    if type(style) ~= "string" then return nil end
    return string.lower(style)
end

-- resolveStyleDelayBase: dump source only (0587 Styles), no latency pad.
-- resolveStyleDelay: base + per-style adaptive latency (gen37).
local function resolveStyleDelayBase(style, attackKind, comboIndex)
    local key = normalizeStyleKey(style)
    local row = key and STYLE_DELAY_TABLE[key]
    if not row then return false end
    attackKind = (attackKind == "M2") and "M2" or "M1"
    local base = (attackKind == "M2") and (row.m2 or DEFAULT_STYLE.m2) or (row.m1 or DEFAULT_STYLE.
        m1)
    if attackKind == "M1" and row.m1Offsets and type(comboIndex) == "number" then
        -- source has exactly 4 offset slots — wrap, don't clamp (gen33 Boxing flurry fix)
        local idx = ((math.floor(comboIndex) - 1) % 4) + 1
        base = base + (row.m1Offsets[idx] or 0)
    end
    return base
end

local function comboSlot(comboIndex)
    if type(comboIndex) ~= "number" then return 1 end
    return ((math.floor(comboIndex) - 1) % 4) + 1
end

local function latencyFor(style)
    local key = normalizeStyleKey(style)
    if key and styleLatencyEma[key] ~= nil then
        return styleLatencyEma[key]
    end
    return DEFAULT_WINDUP_LATENCY
end

local function gapEmaFor(style, comboIndex)
    local key = normalizeStyleKey(style)
    local slot = comboSlot(comboIndex)
    local gtab = key and styleGapEma[key]
    if gtab and typeof(gtab[slot]) == "number" and gtab[slot] > 0 then
        return gtab[slot], slot
    end
    return nil, slot
end

-- PATH2: only combo1 (windup→first hitbox) trains style latency. Mid-combo gaps go to gap EMA.
local function observeWindupLatency(style, lead, attackKind, comboIndex)
    local ci = tonumber(comboIndex) or 1
    if CONFIG.PATH2_GAP_EMA and ci >= 2 then
        Log.step(string.format(
            "LATENCY_SKIP style=%s combo=%d lead=%.3f why=path2_combo1_only (use GAP_ADAPT)",
            tostring(normalizeStyleKey(style) or style), ci, lead or -1
        ))
        return
    end
    local base = resolveStyleDelayBase(style, attackKind, comboIndex)
    if not base or type(lead) ~= "number" then return end
    local sample = lead - base
    -- reject absurd samples (wrong swing / idle gap / teleport)
    if sample < -0.05 or sample > 0.50 then
        Log.step(string.format(
            "LATENCY_REJECT style=%s sample=%.3f lead=%.3f base=%.3f combo=%s",
            tostring(normalizeStyleKey(style) or style), sample, lead, base, tostring(comboIndex)
        ))
        return
    end
    local key = normalizeStyleKey(style) or "?"
    local prev = styleLatencyEma[key]
    local ema = prev and (prev * (1 - LATENCY_EMA_ALPHA) + sample * LATENCY_EMA_ALPHA) or sample
    styleLatencyEma[key] = ema
    Log.step(string.format(
        "LATENCY_ADAPT style=%s sample=%.3f ema=%.3f lead=%.3f base=%.3f combo=%s path2=%s",
        key, sample, ema, lead, base, tostring(comboIndex), tostring(CONFIG.PATH2_GAP_EMA)
    ))
end

local function observeGapEma(style, gapSec, comboIndex)
    if not CONFIG.PATH2_GAP_EMA then return end
    if type(gapSec) ~= "number" then return end
    local ci = tonumber(comboIndex) or 1
    if ci < 2 then return end -- gap is inter-hit; combo1 is windup lead
    if gapSec < GAP_MIN or gapSec > GAP_MAX then
        Log.step(string.format(
            "GAP_REJECT style=%s gap=%.3f combo=%d slot=%d why=out_of_range[%.2f,%.2f]",
            tostring(normalizeStyleKey(style) or style), gapSec, ci, comboSlot(ci), GAP_MIN, GAP_MAX
        ))
        return
    end
    local key = normalizeStyleKey(style) or "?"
    local slot = comboSlot(ci)
    styleGapEma[key] = styleGapEma[key] or {}
    local prev = styleGapEma[key][slot]
    local ema = prev and (prev * (1 - GAP_EMA_ALPHA) + gapSec * GAP_EMA_ALPHA) or gapSec
    styleGapEma[key][slot] = ema
    Log.step(string.format(
        "GAP_ADAPT [P2] style=%s slot=%d combo=%d sample=%.3f ema=%.3f prev=%s",
        key, slot, ci, gapSec, ema, prev and string.format("%.3f", prev) or "nil"
    ))
    saveTimingLearn()
end

local function resolveStyleDelay(style, attackKind, comboIndex)
    local base = resolveStyleDelayBase(style, attackKind, comboIndex)
    if not base then return false end
    return base + latencyFor(style)
end

local function forceDelayFor(style)
    local key = normalizeStyleKey(style)
    if key and styleForceDelay[key] ~= nil then return styleForceDelay[key] end
    return DEFAULT_FORCE_RESOLVE_DELAY
end

local function perfectLeadFor(style)
    local key = normalizeStyleKey(style)
    if key and stylePerfectLead[key] ~= nil then return stylePerfectLead[key] end
    if key == "boxing" then return 0.075 end
    return DEFAULT_PERFECT_LEAD
end

local function expPathTag()
    return string.format("path1=%s path2=%s",
        CONFIG.PATH1_PRECISION_ONLY and "ON" or "OFF",
        CONFIG.PATH2_GAP_EMA and "ON" or "OFF")
end

-- rateSnap defined after S (needs stats)

-- gen42: learn + persist. Only fresh correlates (dt ≤ LEARN_FRESH_MAX).
-- gen41 poison: HIT_STALE / BLOCK@dt=0.7 pushed forceDelay → 0.12 MAX; lateMicro BLOCKs
-- wrongly shrunk precisionLead. Stale = wrong swing, do not train.
local function learnFromOutcome(outcome, style, reason, dtTap)
    local key = normalizeStyleKey(style) or "?"
    reason = tostring(reason or "?")
    styleStats[key] = styleStats[key] or { perfect = 0, block = 0, hit = 0 }
    if outcome == "PERFECT" then
        styleStats[key].perfect = styleStats[key].perfect + 1
    elseif outcome == "BLOCK" then
        styleStats[key].block = styleStats[key].block + 1
    elseif outcome == "HIT" then
        styleStats[key].hit = styleStats[key].hit + 1
    end

    local freshHit = typeof(dtTap) == "number" and dtTap >= 0 and dtTap <= LEARN_FRESH_MAX
    local freshBlock = typeof(dtTap) == "number" and dtTap >= 0 and dtTap <= LEARN_BLOCK_FRESH_MAX
    if outcome == "BLOCK" and not freshBlock then
        Log.step(string.format(
            "TIMING_LEARN style=%s %s SKIP_STALE dt=%.3f reason=%s",
            key, outcome, dtTap or -1, reason
        ))
        saveTimingLearn()
        return
    end
    if outcome == "HIT" and not freshHit then
        Log.step(string.format(
            "TIMING_LEARN style=%s %s SKIP_STALE dt=%.3f reason=%s",
            key, outcome, dtTap or -1, reason
        ))
        saveTimingLearn() -- still persist counts
        return
    end

    if outcome == "PERFECT" then
        if reason == "forceResolve" or reason == "forceNow" or reason == "forceRefresh" or reason ==
            "hitboxLive" then
            Log.step(string.format(
                "TIMING_LEARN style=%s PERFECT forceDelay=%.3f dt=%.3f KEEP stats=P%d/B%d/H%d",
                key, forceDelayFor(style), dtTap or -1,
                styleStats[key].perfect, styleStats[key].block, styleStats[key].hit
            ))
        elseif typeof(dtTap) == "number" and dtTap > 0.01 and dtTap <= LEARN_BLOCK_FRESH_MAX then
            local prev = perfectLeadFor(style)
            local sample = math.clamp(dtTap * 0.35, LEARN_LEAD_MIN, LEARN_LEAD_MAX)
            local nxt = prev * (1 - LEARN_ALPHA) + sample * LEARN_ALPHA
            stylePerfectLead[key] = nxt
            Log.step(string.format(
                "TIMING_LEARN style=%s PERFECT precisionLead %.3f→%.3f dt=%.3f",
                key, prev, nxt, dtTap
            ))
        end
        saveTimingLearn()
    elseif outcome == "BLOCK" then
        -- early Activate relative to hit → fire later next time (precision lead shrink)
        if reason == "forceResolve" or reason == "forceNow" or reason == "forceRefresh" or reason ==
            "hitboxLive" then
            local prev = forceDelayFor(style)
            local nxt = math.clamp(prev + LEARN_FORCE_STEP, LEARN_FORCE_MIN, LEARN_FORCE_MAX)
            styleForceDelay[key] = nxt
            Log.step(string.format(
                "TIMING_LEARN style=%s BLOCK forceDelay %.3f→%.3f dt=%.3f",
                key, prev, nxt, dtTap or -1
            ))
        else
            local prev = perfectLeadFor(style)
            local nxt = math.clamp(prev - 0.008, LEARN_LEAD_MIN, LEARN_LEAD_MAX)
            stylePerfectLead[key] = nxt
            Log.step(string.format(
                "TIMING_LEARN style=%s BLOCK precisionLead %.3f→%.3f reason=%s dt=%.3f",
                key, prev, nxt, reason, dtTap or -1
            ))
        end
        saveTimingLearn()
    elseif outcome == "HIT" then
        -- in-window HIT: timing OK-ish; PerfectBlocking missing. Nudge slightly later.
        if reason == "forceResolve" or reason == "forceNow" or reason == "forceRefresh" or reason ==
            "hitboxLive" then
            local prev = forceDelayFor(style)
            local nxt = math.clamp(prev + LEARN_FORCE_STEP * 0.5, LEARN_FORCE_MIN, LEARN_FORCE_MAX)
            styleForceDelay[key] = nxt
            Log.step(string.format(
                "TIMING_LEARN style=%s HIT_INWINDOW forceDelay %.3f→%.3f dt=%.3f",
                key, prev, nxt, dtTap
            ))
        elseif typeof(dtTap) == "number" then
            if dtTap <= 0.060 then
                local prev = perfectLeadFor(style)
                local nxt = math.clamp(prev + 0.018, LEARN_LEAD_MIN, LEARN_LEAD_MAX)
                stylePerfectLead[key] = nxt
                Log.step(string.format(
                    "HIT_LATE_RACE style=%s precisionLead %.3f→%.3f dt=%.3f",
                    key, prev, nxt, dtTap
                ))
            elseif dtTap > 0.060 and dtTap <= LEARN_FRESH_MAX then
                local prev = perfectLeadFor(style)
                local nxt = math.clamp(prev - 0.005, LEARN_LEAD_MIN, LEARN_LEAD_MAX)
                stylePerfectLead[key] = nxt
                Log.step(string.format(
                    "HIT_EARLY_PAD style=%s precisionLead %.3f→%.3f dt=%.3f",
                    key, prev, nxt, dtTap
                ))
            end
        end
        saveTimingLearn()
    end
end

local function styleDodgeM2(style)
    local key = normalizeStyleKey(style)
    local row = key and STYLE_DELAY_TABLE[key]
    return row ~= nil and row.dodgeM2 == true
end

-- gen21/22: still OFF by default — Boxing's "0% parry, identical timing to styles that DO parry"
-- investigation is parked, not resolved. Kept as a flag (not deleted) since the underlying question
-- (does Blocking/PerfectBlocking ever engage for Boxing at all) is still open; do not re-enable
-- without rebuilding watchBlockEngage as a single shared watcher per the gen22 note at its
-- definition — one-connection-pair-per-windup-burst was the suspected (never proven) churn source.
local BLOCK_ENGAGE_PROBE = false

local PARRY_ATTACKS = { M1 = true, M2 = true }
local SOFT_BLOCK = {
    [Enum.KeyCode.F] = true,
    [Enum.KeyCode.Q] = true,
    [Enum.KeyCode.R] = true,
}

local S = {
    alive = true,
    gen = (G.__GAKURAN_AUTOPARRY_GEN or 0) + 1,
    attackerMeleeRange = 18,
    heartbeatSec = 15,
    tapReleaseSec = 0.12,
    hitboxDuration = 0.15,
    lateSpraySec = 0.10,
    hitboxLiveSpray = false,
    swingTtl = 5,
    resultTtl = 8,
    tapPruneSec = 1,
    rebindTimeout = 5,
    resultMax = 16,
    confirmHoldTarget = 0.05,
    confirmHoldMax = 0.06,
    conns = {},
    delays = {},
    reported = {},
    swings = {},
    fired = {},
    scanTried = {},
    scanLogged = {},
    threatSkipLogged = {},
    swingFinalized = {},
    confirmHeld = {},
    pending = {},
    timing = {},
    unblockGen = 0,
    lastParry = 0,
    lastConfirm = {},
    lastResult = "idle",
    lastResultKind = "idle",
    lastHp = nil,
    activatedSeen = false,
    blockAsserted = false,
    windupActive = {},
    epochSeq = 0,
    windupBurstId = 0,
    lastTapAt = 0,
    lastTapAttacker = "?",
    lastTapStyle = "?",
    lastTapDtStart = 0,
    lastTapReason = "?",       -- gen36: spray | precision | forceNow | opener
    lastTapComboIndex = 0,     -- gen36: predicted combo slot at tap time
    lastTapPredicted = -1,     -- gen36: resolveStyleDelay result used for that tap (-1 = none)
    lastTapForceNow = false,
    lastRawTapAt = 0,        -- operational global rate gate; legacy lastTap* remains HUD only
    lastRawTapReason = "?",
    tapSeq = 0,
    tapsByKey = {},            -- immutable sent-tap records keyed attacker + attack
    lastActivatedAt = 0,
    blockAbortUntil = 0, -- gen39: pause taps after normal BLOCK FX
    threatSkipAgg = { n = 0, lastLog = 0 },
    hitboxParseDebounce = {},
    overlap = nil,
    origFire = nil,
    origFireServer = nil,
    origNamecall = nil,
    origEvasive = nil,
    dodgeHbConn = nil,
    dodgePinChar = nil, -- gen45: avoid stacking Grant/attr listeners per CharacterAdded
    localCharConns = {},
    enemyCharConns = {},
    enemyPlayerChars = {},
    transientConns = {},
    crcHooked = false,
    srvHooked = false,
    ncHooked = false,
    evasiveCdHooked = false,
    hooksInstalled = false,
    hitboxes = nil,
    stats = {
        confirms_seen = 0,
        confirms_patched = 0,
        parry_fires = 0,
        parry_once = 0,
        perfect_fx = 0,
        parry_ok = 0, -- ok_fx alias: FX local (M1|M2PerfectBlocked), not confirm-patch
        ok_fx = 0,
        parry_fail = 0,
        damage_taken = 0,
        dmg = 0,
        scan_near = 0,
        scan_overlap = 0,
        world_ignored = 0,
        activated_sent = 0,
        activated_dup_suppressed = 0,
        branch_a = 0,
        branch_c = 0,
        opener_taps = 0,
        scan_taps = 0,
        belt_suppressed = 0,
        windup_bursts = 0,
        windup_taps = 0,
        tap_precision = 0,
        tap_force = 0,
        tap_hitboxLive = 0,
        sched_gap = 0,
        sched_legacy = 0,
        path1_force_skipped = 0,
        path1_live_skipped = 0,
        fx_perfect_m1 = 0,
        fx_perfect_m2 = 0,
        fx_block = 0,
        fx_hit = 0,
        m1_resume_ok = 0,
        m1_resume_fail = 0,
        dodge_repin = 0, -- legacy (gen34 Grant re-pin); unused after gen35
        dodge_uv_clear = 0,
        dodge_uv_ok = false,
        hook_crc = false,
        hook_srv = false,
        hook_nc = false,
        overlap_held_m1_taps = 0,
        overlap_buffer_rise_taps = 0,
        overlap_edges = 0,
        outcomes_matched = 0,
        outcomes_unmatched = 0,
        learner_rejects_unmatched = 0,
        epoch_expired = 0,
        pair_closest = 0,
        pair_swingid = 0,
        unmatched_by_reason = {},
        dodge_attempts = 0,
        dodge_accept = 0,
        dodge_skip = 0,
        dodge_iframe_ok = 0,
        dodge_hit_through = 0,
        dodge_grab_m2 = 0,
        dodge_m2 = 0,
        dodge_skip_by_gate = {},
    },
    lastHb = 0,
    lastTapPrune = 0,
    perf = {
        since = os.clock(),
        preDt = 0,
        overlapQueries = 0,
        fallbackScans = 0,
        dodgeSafetyPolls = 0,
        dodgeDebugWrites = 0,
        diagSuppressed = 0,
    },
    hitboxFallbackAt = {},
    m1HoldWanted = false,
    -- gen53 merged dodge state (no extra chunk locals)
    pendingDodges = {},
    lastDodgeAt = 0,
    dodgeSeq = 0,
    defenseLock = nil, -- { attacker, mode, untilClock }
    iframeConfirmWindow = 0.4,
    dodgeOutcomeWindow = 0.45,
}

G.__GAKURAN_AUTOPARRY_GEN = S.gen

-- local function emitEvent is assigned after S so diagnostics can use CONFIG/S.
emitEvent = function(kind, fields)
    local routine = kind == "DECISION" or kind == "NET"
        or kind == "WINDUP_END" or kind == "WINDUP_LEAD" or kind == "OVERLAP_EDGE"
    if routine and not CONFIG.DIAGNOSTICS then
        S.perf.diagSuppressed = S.perf.diagSuppressed + 1
        return
    end
    local stepParts = { "EVENT kind=" .. tostring(kind) }
    if type(fields) == "table" then
        for k, v in pairs(fields) do
            if typeof(v) == "number" then
                stepParts[#stepParts + 1] = tostring(k) .. "=" .. string.format("%.3f", v)
            elseif typeof(v) == "boolean" then
                stepParts[#stepParts + 1] = tostring(k) .. "=" .. (v and "true" or "false")
            else
                stepParts[#stepParts + 1] = tostring(k) .. "=" .. tostring(v)
            end
        end
    end
    Log.step(table.concat(stepParts, " "))
    pcall(function()
        if not isfolder or not writefile then return end
        if isfolder and not isfolder("logs") then makefolder("logs") end
        local parts = {
            '"t":"' .. jsonEsc(os.date("%Y-%m-%d %H:%M:%S")) .. '"',
            '"kind":"' .. jsonEsc(kind) .. '"',
        }
        if type(fields) == "table" then
            for k, v in pairs(fields) do
                if typeof(v) == "number" then
                    parts[#parts + 1] = '"' .. jsonEsc(k) .. '":' .. jsonNum(v)
                elseif typeof(v) == "boolean" then
                    parts[#parts + 1] = '"' .. jsonEsc(k) .. '":' .. (v and "true" or "false")
                else
                    parts[#parts + 1] = '"' .. jsonEsc(k) .. '":"' .. jsonEsc(v) .. '"'
                end
            end
        end
        local line = "{" .. table.concat(parts, ",") .. "}"
        if appendfile and isfile and isfile(EVENTS_FILE) then
            appendfile(EVENTS_FILE, line .. "\n")
        else
            writefile(EVENTS_FILE, line .. "\n")
        end
    end)
end

S.bumpEpoch = function(rec, edgeKind, attackerName, attackClass, comboSlot, swingId, mutateRec)
    if mutateRec == nil then mutateRec = true end
    S.epochSeq = (S.epochSeq or 0) + 1
    local ep = S.epochSeq
    if rec and mutateRec then rec.epoch = ep end
    local now = os.clock()
    local fields = {
        gen = S.gen, epoch = ep, attacker = tostring(attackerName or "?"),
        style = rec and tostring(rec.style or "?") or "?",
        attack_class = tostring(attackClass or "M1"),
        combo_slot = comboSlot or (rec and rec.comboIndex) or 1,
        edge_kind = tostring(edgeKind or "?"),
        clock = now,
    }
    if swingId then fields.swingId = tostring(swingId) end
    Log.step(string.format(
        "EDGE epoch=%d kind=%s from=%s attack=%s style=%s combo=%d clock=%.3f swing=%s",
        ep, fields.edge_kind, fields.attacker, fields.attack_class, fields.style,
        fields.combo_slot, now, tostring(swingId or "?")
    ))
    emitEvent("EDGE", fields)
    return ep
end

local function pruneTapResults(now)
    for key, taps in pairs(S.tapsByKey) do
        local i = 1
        while i <= #taps do
            local tap = taps[i]
            if tap.consumed or now - tap.sentLocal > S.resultTtl then
                table.remove(taps, i)
            else
                i = i + 1
            end
        end
        if #taps == 0 then S.tapsByKey[key] = nil end
    end
end

local function rateSnap(tag)
    local p = S.stats.fx_perfect_m1 + S.stats.fx_perfect_m2
    local b = S.stats.fx_block
    local h = S.stats.fx_hit
    local tot = p + b + h
    local rate = tot > 0 and (p / tot) or 0
    local guard = tot > 0 and ((p + b) / tot) or 0
    local ubr = S.stats.unmatched_by_reason or {}
    local topReason, topCount = "none", 0
    for r, n in pairs(ubr) do
        if n > topCount then topReason = r; topCount = n end
    end
    local dsg = S.stats.dodge_skip_by_gate or {}
    local topDodgeGate, topDodgeCount = "none", 0
    for g, n in pairs(dsg) do
        if n > topDodgeCount then topDodgeGate = g; topDodgeCount = n end
    end
    Log.info(string.format(
        "RATE_SNAP [%s] mark=gen53 %s | P=%d B=%d H=%d tot=%d " ..
            "perfectRate=%.1f%% guardRate=%.1f%% | taps=%d prec=%d force=%d " ..
            "live=%d edge=%d hold=%d buffer=%d match=%d unmatch=%d reject=%d " ..
            "pairSwing=%d pairClosest=%d epochExpired=%d topUnmatch=%s:%d " ..
            "gapSched=%d legacySched=%d | p1_forceSkip=%d p1_liveSkip=%d | " ..
            "dodgeAcc=%d dodgeSkip=%d iframeOk=%d topDodgeSkip=%s:%d",
        tostring(tag or "tick"), expPathTag(),
        p, b, h, tot, rate * 100, guard * 100,
        S.stats.windup_taps,
        S.stats.tap_precision or 0,
        S.stats.tap_force or 0,
        S.stats.tap_hitboxLive or 0,
        S.stats.overlap_edges or 0,
        S.stats.overlap_held_m1_taps or 0,
        S.stats.overlap_buffer_rise_taps or 0,
        S.stats.outcomes_matched or 0,
        S.stats.outcomes_unmatched or 0,
        S.stats.learner_rejects_unmatched or 0,
        S.stats.pair_swingid or 0,
        S.stats.pair_closest or 0,
        S.stats.epoch_expired or 0,
        topReason, topCount,
        S.stats.sched_gap or 0,
        S.stats.sched_legacy or 0,
        S.stats.path1_force_skipped or 0,
        S.stats.path1_live_skipped or 0,
        S.stats.dodge_accept or 0,
        S.stats.dodge_skip or 0,
        S.stats.dodge_iframe_ok or 0,
        topDodgeGate, topDodgeCount
    ))
    emitEvent("RATE_SNAP", {
        gen = S.gen, mark = "gen53", tag = tostring(tag or "tick"),
        path1 = CONFIG.PATH1_PRECISION_ONLY, path2 = CONFIG.PATH2_GAP_EMA,
        perfect = p, block = b, hit = h, perfectRate = rate, guardRate = guard,
        taps = S.stats.windup_taps,
        tap_precision = S.stats.tap_precision or 0,
        tap_force = S.stats.tap_force or 0,
        tap_hitboxLive = S.stats.tap_hitboxLive or 0,
        overlap_edges = S.stats.overlap_edges or 0,
        overlap_held_m1_taps = S.stats.overlap_held_m1_taps or 0,
        overlap_buffer_rise_taps = S.stats.overlap_buffer_rise_taps or 0,
        outcomes_matched = S.stats.outcomes_matched or 0,
        outcomes_unmatched = S.stats.outcomes_unmatched or 0,
        learner_rejects_unmatched = S.stats.learner_rejects_unmatched or 0,
        pair_swingid = S.stats.pair_swingid or 0,
        pair_closest = S.stats.pair_closest or 0,
        epoch_expired = S.stats.epoch_expired or 0,
        top_unmatched_reason = topReason,
        top_unmatched_count = topCount,
        sched_gap = S.stats.sched_gap or 0,
        sched_legacy = S.stats.sched_legacy or 0,
        dodge_accept = S.stats.dodge_accept or 0,
        dodge_skip = S.stats.dodge_skip or 0,
        dodge_iframe_ok = S.stats.dodge_iframe_ok or 0,
        top_dodge_skip = topDodgeGate,
        top_dodge_skip_count = topDodgeCount,
    })
end

do
    local dump_stamp, roblox_updated = "2026-07-16T21:49Z", "2026-07-16T20:56Z"
    pcall(function()
        if readfile and isfile and isfile("full_dump/00_DUMP_STAMP.txt") then
            local raw = readfile("full_dump/00_DUMP_STAMP.txt")
            local cap = string.match(raw, "Capture:%s*([^\n\r]+)")
            if cap then dump_stamp = cap end
            local rob = string.match(raw, "RobloxUpdated:%s*([^\n\r]+)")
            if rob then roblox_updated = rob end
        end
    end)
    Log.session("gen=" .. tostring(S.gen) .. " mark=gen53 phase=1_log logSchema=phase1"
        .. " dump_stamp=" .. dump_stamp .. " roblox_updated=" .. roblox_updated
        .. " src=0412,0414,0418,0419,0420,0587,0595,0596,0731"
        .. " enabled=" .. tostring(CONFIG.ENABLED)
        .. " autoDodge=" .. tostring(CONFIG.AUTO_DODGE)
        .. " dodgeM1=" .. tostring(CONFIG.DODGE_M1)
        .. " dodgeM2=" .. tostring(CONFIG.DODGE_M2)
        .. " " .. expPathTag()
        .. " tapHold=" .. tostring(S.tapReleaseSec)
        .. " forceDelay0=" .. tostring(DEFAULT_FORCE_RESOLVE_DELAY)
        .. " latency0=" .. tostring(DEFAULT_WINDUP_LATENCY)
        .. " timingFile=" .. TIMING_CFG_FILE
        .. " hide=" .. keyLabel(CONFIG.HIDE_KEY)
        .. "\n-- gen53: M1 parry / M2 dodge arbiter; UNLOADS __GAKURAN_AUTODODGE --")
end
Log.step("EXP_FLAGS [P1] PATH1_PRECISION_ONLY=" .. tostring(CONFIG.PATH1_PRECISION_ONLY)
    .. " → forceResolve/hitboxLive " .. (CONFIG.PATH1_PRECISION_ONLY and "DISABLED" or "ENABLED"))
Log.step("EXP_FLAGS [P2] PATH2_GAP_EMA=" .. tostring(CONFIG.PATH2_GAP_EMA)
    .. " → mid-combo gap EMA " .. (CONFIG.PATH2_GAP_EMA and "ON (latency=combo1 only)" or
        "OFF (legacy styleDelay)"))
Log.step("EXP_FLAGS [D] AUTO_DODGE=" .. tostring(CONFIG.AUTO_DODGE)
    .. " DODGE_M1=" .. tostring(CONFIG.DODGE_M1)
    .. " DODGE_M2=" .. tostring(CONFIG.DODGE_M2)
    .. " DODGE_GRAB_M2=" .. tostring(CONFIG.DODGE_GRAB_M2)
    .. " range=" .. tostring(CONFIG.DODGE_MAX_RANGE)
    .. " fov=" .. tostring(CONFIG.DODGE_FOV_DEG))
emitEvent("EXP_FLAGS", {
    gen = S.gen, path1 = CONFIG.PATH1_PRECISION_ONLY, path2 = CONFIG.PATH2_GAP_EMA, mark = "gen53",
    autoDodge = CONFIG.AUTO_DODGE, dodgeM1 = CONFIG.DODGE_M1, dodgeM2 = CONFIG.DODGE_M2,
})
loadTimingLearn()
do
    local b = stylePerfectLead["boxing"]
    if b == nil or b < 0.075 then
        stylePerfectLead["boxing"] = 0.075
        Log.step(string.format("LEAD_FLOOR style=boxing precisionLead %s→0.075", tostring(b)))
    end
    local cur = stylePerfectLead["boxing"]
    if typeof(cur) == "number" and cur >= 0.089 and cur <= 0.091 then
        stylePerfectLead["boxing"] = 0.105
        Log.step(string.format("LEAD_UNSTICK style=boxing precisionLead %.3f→0.105", cur))
    end
end
-- scrub poisoned "styles" key from older broken loads
if styleForceDelay["styles"] then styleForceDelay["styles"] = nil end
if stylePerfectLead["styles"] then stylePerfectLead["styles"] = nil end
if styleLatencyEma["styles"] then styleLatencyEma["styles"] = nil end
if styleGapEma["styles"] then styleGapEma["styles"] = nil end
if styleStats["styles"] then styleStats["styles"] = nil end
saveTimingLearn()
rateSnap("boot")

local function track(c)
    S.conns[#S.conns + 1] = c
    return c
end

local function disconnectConnections(conns)
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    table.clear(conns)
end

local function trackLocalChar(c)
    S.localCharConns[#S.localCharConns + 1] = c
    return c
end

local function clearLocalCharConnections()
    disconnectConnections(S.localCharConns)
    S.dodgeHbConn = nil
    S.dodgePinChar = nil
end

local function trackEnemyChar(ch, c)
    local conns = S.enemyCharConns[ch]
    if not conns then
        conns = {}
        S.enemyCharConns[ch] = conns
    end
    conns[#conns + 1] = c
    return c
end

local function clearEnemyCharConnections(ch)
    local conns = S.enemyCharConns[ch]
    if conns then
        disconnectConnections(conns)
        S.enemyCharConns[ch] = nil
    end
end

local function trackTransient(c)
    S.transientConns[c] = true
    return c
end

local function releaseTransient(c)
    if c then
        S.transientConns[c] = nil
        pcall(function() c:Disconnect() end)
    end
end

local function stale()
    return not S.alive or G.__GAKURAN_AUTOPARRY_GEN ~= S.gen
end

local function trackDelay(sec, fn, epochOpt, atkCharOpt)
    local token = {}
    S.delays[token] = true
    task.delay(sec, function()
        S.delays[token] = nil
        if stale() then return end
        if epochOpt and atkCharOpt then
            local rec = S.windupActive[atkCharOpt]
            local atkName = typeof(atkCharOpt) == "Instance" and atkCharOpt.Name or tostring(
                atkCharOpt)
            if not rec then
                Log.step(string.format("WINDUP_ENDED epoch=%d attacker=%s", epochOpt, atkName))
                emitEvent("WINDUP_ENDED", { gen = S.gen, epoch = epochOpt, attacker = atkName })
            elseif rec.epoch ~= epochOpt then
                S.stats.epoch_expired = (S.stats.epoch_expired or 0) + 1
                Log.step(string.format("EPOCH_EXPIRED epoch=%d attacker=%s why=expired_epoch",
                    epochOpt, atkName))
                emitEvent("EPOCH_EXPIRED", { gen = S.gen, epoch = epochOpt, attacker = atkName, why
                    = "expired_epoch" })
                return
            end
        end
        fn()
    end)
    return token
end

local function cancelDelays()
    table.clear(S.delays)
end

local function swingKey(attacker, attack, swingId)
    return tostring(attacker) .. "\1" .. tostring(attack) .. "\1" .. tostring(swingId)
end

local function truncateResult(text)
    text = tostring(text)
    if #text > S.resultMax then
        return string.sub(text, 1, S.resultMax)
    end
    return text
end

-- forward Hud
local Hud = {}

local function setLastResult(text, kind)
    S.lastResult = truncateResult(text)
    S.lastResultKind = kind or "idle"
    if Hud.setResult then Hud.setResult(S.lastResult, S.lastResultKind) end
end

local function notePending(attacker, attack, swingId, reason)
    local key = swingKey(attacker, attack, swingId)
    local now = os.clock()
    S.pending[key] = {
        attacker = attacker,
        attack = attack,
        swingId = swingId,
        scheduledAt = now,
        reason = reason,
    }
    S.swings[key] = now
    if not S.timing[key] then
        S.timing[key] = { hitbox_t = now }
    elseif not S.timing[key].hitbox_t then
        S.timing[key].hitbox_t = now
    end
    return key
end

local function timingFields(key)
    local t = S.timing[key]
    if not t then return {} end
    local out = {}
    if t.hitbox_t then out.hitbox_t = t.hitbox_t end
    if t.activated_t then out.activated_t = t.activated_t end
    if t.confirm_t then out.confirm_t = t.confirm_t end
    if t.hitbox_t and t.activated_t then
        out.dt_hitbox_activated = t.activated_t - t.hitbox_t
    end
    if t.activated_t and t.confirm_t then
        out.dt_activated_confirm = t.confirm_t - t.activated_t
    end
    if t.hitbox_t and t.confirm_t then
        out.dt_hitbox_confirm = t.confirm_t - t.hitbox_t
    end
    return out
end

local function logDecision(attacker, attack, swingId, src, act, why)
    if not CONFIG.DIAGNOSTICS then
        S.perf.diagSuppressed = S.perf.diagSuppressed + 1
        return
    end
    local ch = lp.Character
    local line = string.format(
        "DECISION swing=%s atk=%s attack=%s src=%s act=%s why=%s stun=%s buf=%s blocking=%s pb=%s",
        tostring(swingId), tostring(attacker), tostring(attack),
        tostring(src), tostring(act), tostring(why),
        tostring(ch and ch:GetAttribute("Stunned")),
        tostring(ch and ch:GetAttribute("ParryBuffered")),
        tostring(ch and ch:GetAttribute("Blocking")),
        tostring(ch and ch:GetAttribute("PerfectBlocking"))
    )
    Log.step(line)
    emitEvent("DECISION", {
        gen = S.gen,
        swing = tostring(swingId),
        atk = tostring(attacker),
        attack = tostring(attack),
        src = tostring(src),
        act = tostring(act),
        why = tostring(why),
    })
end

local function logNet(dir, kind, fields)
    if not CONFIG.DIAGNOSTICS then
        S.perf.diagSuppressed = S.perf.diagSuppressed + 1
        return
    end
    fields = type(fields) == "table" and fields or {}
    local parts = { string.format("NET dir=%s kind=%s", tostring(dir), tostring(kind)) }
    for k, v in pairs(fields) do
        if typeof(v) == "number" then
            parts[#parts + 1] = tostring(k) .. "=" .. string.format("%.3f", v)
        elseif typeof(v) == "boolean" then
            parts[#parts + 1] = tostring(k) .. "=" .. (v and "true" or "false")
        else
            parts[#parts + 1] = tostring(k) .. "=" .. tostring(v)
        end
    end
    Log.step(table.concat(parts, " "))
    local ev = { gen = S.gen, dir = tostring(dir), kind = tostring(kind) }
    for k, v in pairs(fields) do
        ev[k] = v
    end
    emitEvent("NET", ev)
end

local function noteActivatedOut(transport, fields)
    S.activatedSeen = true
    S.lastActivatedAt = os.clock()
    S.stats.activated_sent = S.stats.activated_sent + 1
    fields = type(fields) == "table" and fields or {}
    fields.transport = tostring(transport)
    fields.serverTime = fields.serverTime or Workspace:GetServerTimeNow()
    fields.clock = S.lastActivatedAt
    logNet("OUT", "Block.Activated", fields)
end

local function finalizeSwing(key, result)
    if not key or S.swingFinalized[key] then return end
    S.swingFinalized[key] = true
    local info = S.pending[key] or {}
    local t = S.timing[key] or {}
    local tf = timingFields(key)
    Log.step(string.format(
        "SWING swing=%s atk=%s attack=%s t_hitbox=%s t_act=%s t_confirm=%s " ..
            "dt_h2a=%s dt_a2c=%s dt_h2c=%s result=%s via_act=%s fires=%s fx=%s " .. "patched=%s",
        tostring(info.swingId or "?"),
        tostring(info.attacker or "?"),
        tostring(info.attack or "?"),
        t.hitbox_t and string.format("%.3f", t.hitbox_t) or "?",
        t.activated_t and string.format("%.3f", t.activated_t) or "?",
        t.confirm_t and string.format("%.3f", t.confirm_t) or "?",
        typeof(tf.dt_hitbox_activated) == "number" and string.format("%.3f", tf.dt_hitbox_activated)
            or "?",
        typeof(tf.dt_activated_confirm) == "number" and string.format("%.3f", tf.
            dt_activated_confirm) or "?",
        typeof(tf.dt_hitbox_confirm) == "number" and string.format("%.3f", tf.dt_hitbox_confirm) or
            "?",
        tostring(result),
        tostring(t.via_act or "none"),
        tostring(t.fires or (S.fired[key] and 1 or 0)),
        tostring(t.fx or 0),
        tostring(t.patched or 0)
    ))
    emitEvent("SWING", {
        gen = S.gen,
        swing = tostring(info.swingId or "?"),
        atk = tostring(info.attacker or "?"),
        attack = tostring(info.attack or "?"),
        result = tostring(result),
        via_act = tostring(t.via_act or "none"),
        hitbox_t = tf.hitbox_t,
        activated_t = tf.activated_t,
        confirm_t = tf.confirm_t,
        dt_hitbox_activated = tf.dt_hitbox_activated,
        dt_activated_confirm = tf.dt_activated_confirm,
        dt_hitbox_confirm = tf.dt_hitbox_confirm,
        fx = t.fx or 0,
        patched = t.patched or 0,
    })
end

local function resolveSwingResult(kind, attacker, victim, attack)
    if victim ~= lp.Name then return end
    local now = os.clock()
    local bestKey, bestDt = nil, S.resultTtl + 1
    for key, info in pairs(S.pending) do
        if info.attacker == attacker and (not attack or info.attack == attack) then
            local dt = now - (info.scheduledAt or now)
            if dt < bestDt then
                bestDt = dt
                bestKey = key
            end
        end
    end
    if not bestKey then return end
    local info = S.pending[bestKey]
    local tf = timingFields(bestKey)
    tf.gen = S.gen
    tf.attack = info.attack
    tf.attacker = info.attacker
    tf.swing = info.swingId
    tf.dt = bestDt
    S.timing[bestKey] = S.timing[bestKey] or {}
    if kind == "PARRY_OK" then
        -- ok_fx = CombatBroadcast PerfectBlocked FX (local defender); not confirm-patch
        S.stats.parry_ok = S.stats.parry_ok + 1
        S.stats.ok_fx = S.stats.ok_fx + 1
        S.timing[bestKey].fx = 1
        setLastResult(string.format("OK %s %s", info.attack, info.attacker), "success")
        emitEvent("PARRY_OK", tf)
        finalizeSwing(bestKey, "PARRY_OK")
    elseif kind == "PARRY_FAIL" then
        S.stats.parry_fail = S.stats.parry_fail + 1
        setLastResult(string.format("FAIL %s %s", info.attack, info.attacker), "fail")
        emitEvent("PARRY_FAIL", tf)
        finalizeSwing(bestKey, "PARRY_FAIL")
    elseif kind == "DAMAGE_TAKEN" then
        S.stats.damage_taken = S.stats.damage_taken + 1
        S.stats.dmg = S.stats.dmg + 1
        setLastResult(string.format("DMG %s %s", info.attack, info.attacker), "damage")
        emitEvent("DAMAGE_TAKEN", tf)
        finalizeSwing(bestKey, "DMG")
    end
    S.pending[bestKey] = nil
end

local function canScan(ch)
    if not ch then return false, "no_char" end
    if ch:GetAttribute("IFRAMES") == true then return false, "iframes" end
    if ch:GetAttribute("Ragdoll") == true then return false, "ragdoll" end
    if ch:GetAttribute("Downed") == true then return false, "downed" end
    if ch:GetAttribute("UltraInstinct") == true then return false, "ultra" end
    if ch:GetAttribute("ParryWindowDisabled") == true then return false, "parry_disabled" end
    -- gen15: the old (now-removed) reactive fireBlockTap path used to check this separately —
    -- that check never made it into canScan, so windupTick (the only live fire path) has been
    -- blindly sending Block.Activated while guard-broken. A guard-break makes the server ignore
    -- block attempts entirely regardless of timing — this was the real cause of perfectly-timed
    -- (11-22ms) taps still landing as raw HIT (log: gen2 16:41 session, dt_since_tap fully
    -- overlapping across PERFECT/BLOCK/HIT with no clean timing boundary — a "the tap didn't
    -- register at all" signature, not a mistiming signature).
    if ch:GetAttribute("GuardBroken") == true then return false, "guardbroken" end
    local hum = ch:FindFirstChildOfClass("Humanoid")
    local hrp = ch:FindFirstChild("HumanoidRootPart")
    if not hum or hum.Health <= 0 then return false, "dead" end
    if not hrp then return false, "no_hrp" end
    return true, "ok"
end

local function attrSnap(ch)
    if not ch then return "Equip=? Blocking=? PerfectBlocking=? BlockCooldown=? CantAnything=? " ..
        "GuardBroken=? ParryWindowDisabled=? Greenzone=? RpCombatLocked=? " ..
        "IFRAMES=? Stunned=? ParryBuffered=? OutnumberedEvasiveGrant=? " ..
        "EvasiveCooldownRemaining=? IFRAMECD=?" end
    local names = { "Equip", "Blocking", "PerfectBlocking", "BlockCooldown", "CantAnything",
        "GuardBroken", "ParryWindowDisabled", "Greenzone", "RpCombatLocked", "IFRAMES", "Stunned",
        "ParryBuffered", "OutnumberedEvasiveGrant", "EvasiveCooldownRemaining", "IFRAMECD" }
    local parts = {}
    for i = 1, #names do
        local n = names[i]
        local v = ch:GetAttribute(n)
        if v == nil then
            parts[i] = n .. "=nil"
        else
            parts[i] = n .. "=" .. tostring(v)
        end
    end
    return table.concat(parts, " ")
end

local function clearBlockCooldown(ch)
    if not CONFIG.NO_COOLDOWN or not ch then return false end
    if ch:GetAttribute("BlockCooldown") == true then
        pcall(function() ch:SetAttribute("BlockCooldown", nil) end)
        Log.step("cleared BlockCooldown")
        return true
    end
    return false
end

-- No-dodge-cooldown (gen45).
-- History: gen9 attr-clear failed (real CD is Evasive upvalue u6). gen25–34 pinned
-- OutnumberedEvasiveGrant=true → forces u51 → bypasses CD + stun/CantAnything/IFRAMECD gates
-- AND applies OutnumberedDashSpeed/Duration multipliers (0414:693-705 → ~3.375× distance) and
-- skips mid-dash u7 gate (spam glitches). gen35 dropped Grant for UV-only clear — logs showed
-- uv_ok/uv_clear but dodge still felt CD'd (Grant also clears combat locks; UV alone does not).
-- gen45: restore Grant pin + nerf dash mults to 1.0 + keep UV/attr belt + enforce IsDashActive
-- in our Evasive hook so u7 skip cannot stack LinearVelocity. setupvalue always targets orig.
local DODGE_CD_ATTRS = { "EvasiveCooldownRemaining", "IFRAMECD" }
local DODGE_POLL_INTERVAL = 0.5
local dodgeUv = {
    resolved = false,
    fn = nil,
    idx = { u5 = nil, u6 = nil, u7 = nil, u8 = nil, u4 = nil },
    failReason = nil,
    multNerfed = false,
    multOriginals = {},
}

local function findSharedUpvalueIndex(srcFn, srcIdx, dstFn)
    if not (getuv and setuv and srcFn and dstFn) then return nil end
    local sentinel = 880022.11009 + (os.clock() % 1) * 0.001
    local oldOk, old = pcall(getuv, srcFn, srcIdx)
    if not oldOk then return nil end
    if not pcall(setuv, srcFn, srcIdx, sentinel) then return nil end
    local found = nil
    for i = 1, 48 do
        local ok, v = pcall(getuv, dstFn, i)
        if not ok then break end
        if v == sentinel then
            found = i
            break
        end
    end
    pcall(setuv, srcFn, srcIdx, old)
    return found
end

local function dodgeOrigFn()
    return S.origEvasive or dodgeUv.fn
end

local function resolveDodgeUpvalues()
    if dodgeUv.resolved then
        return dodgeUv.idx.u5 ~= nil and dodgeUv.idx.u6 ~= nil
    end
    dodgeUv.resolved = true
    if not EvasiveMod or type(EvasiveMod.Evasive) ~= "function" then
        dodgeUv.failReason = "no_EvasiveMod"
        Log.warn("dodge UV resolve FAIL reason=no_EvasiveMod")
        return false
    end
    if not getuv or not setuv then
        dodgeUv.failReason = "no_getupvalue"
        Log.warn("dodge UV resolve FAIL reason=no_getupvalue/setupvalue")
        return false
    end
    -- Prefer true original after hookfunction (wrapper UV layout ≠ Evasive timers).
    local evasive = dodgeOrigFn() or EvasiveMod.Evasive
    dodgeUv.fn = evasive
    local u7 = EvasiveMod.IsDashActive and findSharedUpvalueIndex(EvasiveMod.IsDashActive, 1,
        evasive) or nil
    local u4 = EvasiveMod.CancelDash and findSharedUpvalueIndex(EvasiveMod.CancelDash, 1, evasive)
        or nil
    local u8 = EvasiveMod.NotifyAttackStarted and findSharedUpvalueIndex(EvasiveMod.
        NotifyAttackStarted, 1, evasive) or nil
    local known = {}
    if u4 then known[u4] = true end
    if u7 then known[u7] = true end
    if u8 then known[u8] = true end
    local excludeExact = {
        [0.2] = true, [0.3] = true, [0.5] = true, [1.2] = true, [1.5] = true,
        [2.25] = true, [30] = true, [1] = true,
    }
    pcall(function()
        local cc = require(RS.Shared.Config.CombatConfig)
        local e = cc.Evasive
        if e then
            excludeExact[e.DashSpeed] = true
            excludeExact[e.DashDuration] = true
            excludeExact[e.Cooldown] = true
            excludeExact[e.IFrameDuration] = true
            excludeExact[e.OutnumberedDashSpeedMultiplier] = true
            excludeExact[e.OutnumberedDashDurationMultiplier] = true
        end
        local cp = cc.ClientPredict and cc.ClientPredict.Evasive
        if cp and cp.ServerConfirmTimeout then
            excludeExact[cp.ServerConfirmTimeout] = true
        end
    end)
    local candidates = {}
    for i = 1, 48 do
        local ok, v = pcall(getuv, evasive, i)
        if not ok then break end
        if type(v) == "number" and not known[i] and not excludeExact[v] then
            if v == 0 or v > 5 then
                candidates[#candidates + 1] = i
            end
        end
    end
    local u5, u6 = candidates[1], candidates[2]
    dodgeUv.idx = { u4 = u4, u5 = u5, u6 = u6, u7 = u7, u8 = u8 }
    if #candidates ~= 2 or not u5 or not u6 then
        dodgeUv.failReason = "u5_u6_bad nCand=" .. tostring(#candidates)
        dodgeUv.idx.u5, dodgeUv.idx.u6 = nil, nil
        Log.warn(string.format(
            "dodge UV resolve FAIL %s | u4=%s u7=%s u8=%s candidates=%s",
            dodgeUv.failReason, tostring(u4), tostring(u7), tostring(u8), table.concat(candidates,
                ",")))
        S.stats.dodge_uv_ok = false
        return false
    end
    S.stats.dodge_uv_ok = true
    Log.step(string.format(
        "dodge UV resolved u5@%d u6@%d u8@%s u7@%s(hook-gate) u4@%s — clear " ..
            "u5/u6/u8; Grant pin separate",
        u5, u6, tostring(u8), tostring(u7), tostring(u4)))
    return true
end

-- Force OutnumberedDash* multipliers (and Cooldown copy at 1.5) to 1.0 so Grant pin
-- does not stretch dash ~3.375×. 2.25 is unique; 1.5 may also hit Cooldown copy (harmless).
local function nerfOutnumberedDashMultipliers(fn)
    if not fn or not getuv or not setuv then return end
    local originals = dodgeUv.multOriginals[fn]
    if not originals then
        originals = {}
        dodgeUv.multOriginals[fn] = originals
    end
    local n = 0
    for i = 1, 48 do
        local ok, v = pcall(getuv, fn, i)
        if not ok then break end
        if v == 2.25 or v == 1.5 then
            if originals[i] == nil then originals[i] = v end
            if pcall(setuv, fn, i, 1) then n = n + 1 end
        end
    end
    if n > 0 and not dodgeUv.multNerfed then
        dodgeUv.multNerfed = true
        Log.step("dodge mult nerf n=" .. tostring(n) ..
            " (2.25/1.5→1.0 for normal dash under Grant)")
    end
end

local function restoreOutnumberedDashMultipliers()
    if not setuv then return end
    for fn, originals in pairs(dodgeUv.multOriginals) do
        for i, value in pairs(originals) do
            pcall(setuv, fn, i, value)
        end
    end
    table.clear(dodgeUv.multOriginals)
    dodgeUv.multNerfed = false
end

local function clearDodgeUpvalues()
    local fn = dodgeOrigFn()
    if not fn or not setuv then return 0 end
    local n = 0
    local idx = dodgeUv.idx
    for _, key in ipairs({ "u5", "u6", "u8" }) do
        local i = idx[key]
        if i then
            if pcall(setuv, fn, i, 0) then n = n + 1 end
        end
    end
    if n > 0 then
        S.stats.dodge_uv_clear = S.stats.dodge_uv_clear + 1
        S.perf.dodgeDebugWrites = S.perf.dodgeDebugWrites + n
    end
    return n
end

local function clearDodgeCdAttrs(ch)
    for _, a in ipairs(DODGE_CD_ATTRS) do
        local v = ch:GetAttribute(a)
        if v ~= nil and v ~= false then
            pcall(function() ch:SetAttribute(a, a == "IFRAMECD" and nil or 0) end)
        end
    end
end

local function pinOutnumberedGrant(ch)
    if not ch then return end
    if ch:GetAttribute("OutnumberedEvasiveGrant") ~= true then
        pcall(function() ch:SetAttribute("OutnumberedEvasiveGrant", true) end)
        S.stats.dodge_repin = S.stats.dodge_repin + 1
    end
end

local function pinDodgeCd(ch)
    if not CONFIG.NO_DODGE_CD or not ch then return end

    -- gen45: re-resolve against orig after hook; allow one refresh if fn identity changed.
    local wantFn = dodgeOrigFn() or (EvasiveMod and EvasiveMod.Evasive)
    if dodgeUv.resolved and dodgeUv.fn ~= nil and wantFn ~= nil and dodgeUv.fn ~= wantFn then
        restoreOutnumberedDashMultipliers()
        dodgeUv.resolved = false
        dodgeUv.multNerfed = false
    end

    local okUv = resolveDodgeUpvalues()
    nerfOutnumberedDashMultipliers(dodgeOrigFn())
    pinOutnumberedGrant(ch)
    clearDodgeUpvalues()
    clearDodgeCdAttrs(ch)

    -- Already wired for this character — refresh only (avoid stacking attr listeners).
    if S.dodgePinChar == ch and S.dodgeHbConn then
        Log.step("pinDodgeCd refresh gen45 uv_ok=" .. tostring(okUv) .. " grant=true mult_nerf="
            .. tostring(dodgeUv.multNerfed))
        return
    end
    S.dodgePinChar = ch

    for _, a in ipairs(DODGE_CD_ATTRS) do
        trackLocalChar(ch:GetAttributeChangedSignal(a):Connect(function()
            if stale() or not CONFIG.ENABLED or not CONFIG.NO_DODGE_CD then return end
            local v = ch:GetAttribute(a)
            if v ~= nil and v ~= false then
                pcall(function() ch:SetAttribute(a, a == "IFRAMECD" and nil or 0) end)
                Log.step("re-cleared " .. a .. " mid-session")
            end
        end))
    end
    trackLocalChar(ch:GetAttributeChangedSignal("OutnumberedEvasiveGrant"):Connect(function()
        if stale() or not CONFIG.ENABLED or not CONFIG.NO_DODGE_CD then return end
        if ch:GetAttribute("OutnumberedEvasiveGrant") ~= true then
            pinOutnumberedGrant(ch)
            Log.step("re-pinned OutnumberedEvasiveGrant after server reset")
        end
    end))

    local lastPoll = 0
    if S.dodgeHbConn then
        pcall(function() S.dodgeHbConn:Disconnect() end)
        S.dodgeHbConn = nil
    end
    S.dodgeHbConn = RunService.Heartbeat:Connect(function()
        if stale() or not CONFIG.ENABLED or not CONFIG.NO_DODGE_CD then return end
        local now = os.clock()
        if now - lastPoll < DODGE_POLL_INTERVAL then return end
        lastPoll = now
        S.perf.dodgeSafetyPolls = S.perf.dodgeSafetyPolls + 1
        pinOutnumberedGrant(ch)
        clearDodgeCdAttrs(ch)
    end)
    trackLocalChar(S.dodgeHbConn)

    -- Entry hook: keep mid-dash gate (Grant would skip u7); clear timers; call orig.
    if EvasiveMod and not S.evasiveCdHooked and hookfunction then
        local okHook, errHook = pcall(function()
            local wrap = newcclosure and newcclosure(function(...)
                if S.alive and CONFIG.ENABLED and CONFIG.NO_DODGE_CD then
                    if EvasiveMod.IsDashActive and EvasiveMod.IsDashActive() then
                        return
                    end
                    clearDodgeUpvalues()
                    local c = lp.Character
                    if c then
                        pinOutnumberedGrant(c)
                        clearDodgeCdAttrs(c)
                    end
                end
                local orig = S.origEvasive
                if orig then return orig(...) end
            end) or function(...)
                if S.alive and CONFIG.ENABLED and CONFIG.NO_DODGE_CD then
                    if EvasiveMod.IsDashActive and EvasiveMod.IsDashActive() then
                        return
                    end
                    clearDodgeUpvalues()
                    local c = lp.Character
                    if c then
                        pinOutnumberedGrant(c)
                        clearDodgeCdAttrs(c)
                    end
                end
                local orig = S.origEvasive
                if orig then return orig(...) end
            end
            S.origEvasive = hookfunction(EvasiveMod.Evasive, wrap)
            dodgeUv.fn = S.origEvasive
            dodgeUv.resolved = false
            dodgeUv.multNerfed = false
            resolveDodgeUpvalues()
            nerfOutnumberedDashMultipliers(S.origEvasive)
            S.evasiveCdHooked = true
        end)
        Log.step("Evasive() CD-clear hook ok=" .. tostring(okHook)
            .. (errHook and (" err=" .. tostring(errHook)) or ""))
    elseif not okUv then
        Log.warn("pinDodgeCd: UV resolve failed — Grant+attr path only")
    end
    Log.step("pinDodgeCd wired gen45 uv_ok=" .. tostring(okUv)
        .. " grant=true mult_nerf=" .. tostring(dodgeUv.multNerfed)
        .. " poll=" .. DODGE_POLL_INTERVAL .. "s")
end

-- gen52: after Blocking release, remount Hold Stop→Start if wanted/mouse down,
-- then pump OnM1Activated. No-ops if gates refuse (CombatAttacking/M2/GuardBroken/etc).
local function restartM1Hold(ch)
    if not ch or not M1Mod or not M1Mod.Hold then return false end
    if ch:GetAttribute("M1Hold") == true then return true end
    -- desync: module think holding (u23) but attr cleared — Stop remounts then Start
    pcall(M1Mod.Hold, "Stop")
    pcall(M1Mod.Hold, "Start")
    return ch:GetAttribute("M1Hold") == true
end

local function resumeM1IfHeld(ch)
    if not ch then return end
    if not M1Mod then
        if S.m1HoldWanted then Log.step("M1_RESUME skip reason=no_module") end
        return
    end
    if S.blockAsserted == true then return end
    local mouseDown = false
    pcall(function()
        mouseDown = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
    end)
    if ch:GetAttribute("M1Hold") ~= true
        and (S.m1HoldWanted or mouseDown)
        and M1Mod.Hold then
        restartM1Hold(ch)
        Log.step(string.format(
            "M1_HOLD_RESTART want=%s mouse=%s M1Hold=%s remount=true",
            tostring(S.m1HoldWanted), tostring(mouseDown), tostring(ch:GetAttribute("M1Hold"))
        ))
        if ch:GetAttribute("M1Hold") ~= true then
            Log.step("M1_RESUME skip reason=hold_remount_failed")
            return
        end
    end
    if ch:GetAttribute("PerfectBlocking") == true then return end
    if ch:GetAttribute("M1Hold") ~= true then return end
    if not M1Mod.OnM1Activated then
        Log.step("M1_RESUME skip reason=no_module")
        return
    end
    local ok, err = pcall(M1Mod.OnM1Activated)
    if ok then
        S.stats.m1_resume_ok = S.stats.m1_resume_ok + 1
    else
        S.stats.m1_resume_fail = S.stats.m1_resume_fail + 1
    end
    Log.step(string.format("M1_RESUME ok=%s err=%s M1Hold=true %s", tostring(ok), tostring(err),
        attrSnap(ch)))
    emitEvent("M1_RESUME", { gen = S.gen, ok = ok == true })
end

-- gen52: M1Hold watch + InputEnded clears m1HoldWanted. No lastParry pump freeze.
local function wireM1HoldWatch(ch)
    if not ch then return end
    trackLocalChar(ch:GetAttributeChangedSignal("M1Hold"):Connect(function()
        if ch:GetAttribute("M1Hold") == true then S.m1HoldWanted = true end
        Log.step("M1HOLD=" .. tostring(ch:GetAttribute("M1Hold")) .. " " .. attrSnap(ch))
    end))
    trackLocalChar(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            S.m1HoldWanted = false
        end
    end))
    trackLocalChar(RunService.Heartbeat:Connect(function()
        if stale() or not CONFIG.ENABLED then return end
        local c = lp.Character
        if not c or c ~= ch then return end
        if c:GetAttribute("Blocking") == true then return end
        if c:GetAttribute("GuardBroken") == true or c:GetAttribute("CantAnything") == true
            or c:GetAttribute("Stunned") == true then return end
        if S.blockAsserted == true then return end
        if c:GetAttribute("PerfectBlocking") == true then return end
        if c:GetAttribute("M1Hold") ~= true then
            local mouseDown = false
            pcall(function()
                mouseDown = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
            end)
            local nowRestart = os.clock()
            if (S.m1HoldWanted or mouseDown) and M1Mod and M1Mod.Hold
                and nowRestart - (S.lastM1HoldRestartAt or 0) >= 0.1 then
                S.lastM1HoldRestartAt = nowRestart
                restartM1Hold(c)
                if nowRestart - (S.lastM1HoldRestartLog or 0) >= 1 then
                    S.lastM1HoldRestartLog = nowRestart
                    Log.step(string.format(
                        "M1_HOLD_RESTART want=%s mouse=%s M1Hold=%s remount=true",
                        tostring(S.m1HoldWanted), tostring(mouseDown), tostring(c:GetAttribute(
                            "M1Hold"))
                    ))
                end
            end
            if c:GetAttribute("M1Hold") ~= true then return end
        end
        local now = os.clock()
        if now - (S.lastM1Pump or 0) < 0.05 then return end
        S.lastM1Pump = now
        if not M1Mod or not M1Mod.OnM1Activated then return end
        pcall(M1Mod.OnM1Activated)
        S.stats.m1_pump = (S.stats.m1_pump or 0) + 1
        if now - (S.lastM1PumpLog or 0) >= 1 then
            S.lastM1PumpLog = now
            Log.step("M1_PUMP n=" .. tostring(S.stats.m1_pump))
        end
    end))
end

local function doUnblock(swingKeyStr)
    local c = lp.Character
    if BlockMod and BlockMod.Unblock then
        pcall(BlockMod.Unblock)
    else
        pcall(function()
            CRC.Fire("Block", "Deactivated")
        end)
        pcall(function()
            Server:FireServer({
                Type = "Combat",
                Action = "Block",
                Func = "Deactivated",
            })
        end)
    end
    if c then
        pcall(function() c:SetAttribute("Blocking", nil) end)
    end
    local now = os.clock()
    local dtStr = "?"
    if swingKeyStr and S.timing[swingKeyStr] then
        local t = S.timing[swingKeyStr]
        if t.activated_t then
            dtStr = string.format("%.3f", now - t.activated_t)
        elseif t.hitbox_t then
            dtStr = string.format("%.3f", now - t.hitbox_t)
        end
    end
    Log.step(string.format("UNBLOCK dt=%s key=%s clock=%.3f %s",
        dtStr, tostring(swingKeyStr or "?"), now, attrSnap(c)))
    S.blockAsserted = false
    resumeM1IfHeld(c)
end

-- Path A: Block.Block primary; CRC belt ONLY if no Activated observed (~8ms)
local function watchPerfectAttr(ch, swingKeyStr)
    if not ch then return end
    local deadline = os.clock() + 0.35
    local function notePerfect()
        if ch:GetAttribute("PerfectBlocking") ~= true then return false end
        Log.step(string.format(
            "PERFECT_ATTR PerfectBlocking=true key=%s %s",
            tostring(swingKeyStr or "?"), attrSnap(ch)
        ))
        emitEvent("PERFECT_ATTR", { gen = S.gen, key = tostring(swingKeyStr or "?") })
        return true
    end
    if notePerfect() then return end
    local conn
    conn = ch:GetAttributeChangedSignal("PerfectBlocking"):Connect(function()
        if stale() or os.clock() >= deadline then
            releaseTransient(conn)
            return
        end
        if notePerfect() then releaseTransient(conn) end
    end)
    trackTransient(conn)
    trackDelay(0.35, function()
        releaseTransient(conn)
        notePerfect()
    end)
end

-- gen21: does Blocking/PerfectBlocking EVER engage on us at all against this style, within a
-- windup burst? Called once per burst (not per tap — would spam otherwise). Answers whether
-- Boxing's 0% parry rate is a mistiming problem or Boxing simply doesn't respond to a normal
-- Block.Activated the way other styles do (dump: CombatConfig has BoxingCounter/
-- BoxingCounterHighlight keys, suggesting a separate counter mechanic).
local styleBlockEngageLogged = {}
local function watchBlockEngage(ch, style, atkName)
    if not ch then return end
    local logKey = tostring(style)
    local deadline = os.clock() + 0.4
    local function check(via)
        local blocking = ch:GetAttribute("Blocking")
        local perfect = ch:GetAttribute("PerfectBlocking")
        if blocking == true or perfect == true then
            Log.step(string.format("BLOCK_ENGAGE style=%s atk=%s blocking=%s perfect=%s via=%s",
                tostring(style), tostring(atkName), tostring(blocking), tostring(perfect), via))
            emitEvent("BLOCK_ENGAGE", {
                gen = S.gen, style = tostring(style), attacker = tostring(atkName),
                blocking = blocking == true, perfect = perfect == true,
            })
            styleBlockEngageLogged[logKey] = "engaged"
            return true
        end
        return false
    end
    if check("immediate") then return end
    local c1, c2
    local function cleanup()
        releaseTransient(c1)
        releaseTransient(c2)
    end
    c1 = trackTransient(ch:GetAttributeChangedSignal("Blocking"):Connect(function()
        if stale() or os.clock() >= deadline then cleanup() return end
        if check("Blocking_signal") then cleanup() end
    end))
    c2 = trackTransient(ch:GetAttributeChangedSignal("PerfectBlocking"):Connect(function()
        if stale() or os.clock() >= deadline then cleanup() return end
        if check("PerfectBlocking_signal") then cleanup() end
    end))
    trackDelay(0.4, function()
        cleanup()
        if styleBlockEngageLogged[logKey] ~= "engaged" and styleBlockEngageLogged[logKey] ~=
            "never_logged" then
            styleBlockEngageLogged[logKey] = "never_logged"
            Log.step("BLOCK_ENGAGE_NEVER style=" .. tostring(style) .. " atk=" .. tostring(atkName)
                .. " " .. attrSnap(ch))
            emitEvent("BLOCK_ENGAGE_NEVER", { gen = S.gen, style = tostring(style), attacker =
                tostring(atkName) })
        end
    end)
end

local function fireBlockTap(reason, swingKeyStr)
    local ch = lp.Character
    local function fail(why)
        Log.err("fireBlockTap fail why=" .. tostring(why) .. " " .. attrSnap(ch))
        return false, why
    end
    if not ch then return fail("no_char") end
    local scanOk, scanWhy = canScan(ch)
    if not scanOk then return fail(scanWhy) end
    if ch:GetAttribute("Greenzone") == true then return fail("greenzone") end
    -- gen34: RpCombatLocked (+ StaffModPeaceMode) — new zone/state flags, checked identically
    -- alongside Greenzone in Block/M1/Evasive (full_dump 0412/0413/0414/0418/0419.lua as of the
    -- 2026-07-16 dump). Same category as Greenzone: a real no-combat state, not a cooldown to
    -- bypass — bail the same way.
    if ch:GetAttribute("RpCombatLocked") == true then return fail("rpcombatlocked") end
    if ch:GetAttribute("GuardBroken") == true then return fail("guardbroken") end

    local now = os.clock()
    if now - S.lastParry < MIN_BLOCK_INTERVAL then
        S.stats.activated_dup_suppressed = S.stats.activated_dup_suppressed + 1
        local info = swingKeyStr and S.pending[swingKeyStr]
        logDecision(
            info and info.attacker or "?",
            info and info.attack or "?",
            info and info.swingId or "?",
            tostring(reason or "?"),
            "SKIP",
            "rate"
        )
        return false, "rate"
    end

    local cdcleared = clearBlockCooldown(ch) and 1 or 0

    local activatedAt = now
    if swingKeyStr then
        S.timing[swingKeyStr] = S.timing[swingKeyStr] or {}
        S.timing[swingKeyStr].activated_t = activatedAt
    end

    Log.step(string.format(
        "STRING_CTX Stunned=%s ParryBuffered=%s Parried=%s",
        tostring(ch:GetAttribute("Stunned")),
        tostring(ch:GetAttribute("ParryBuffered")),
        tostring(ch:GetAttribute("Parried"))
    ))

    local via = "none"
    local fired = false
    S.activatedSeen = false
    local ok, err = pcall(function()
        if CONFIG.USE_BLOCK_MODULE and BlockMod and BlockMod.Block then
            BlockMod.Block()
            via = "Block"
            fired = true
            local deadline = os.clock() + 0.008
            while not S.activatedSeen and os.clock() < deadline do
                task.wait(0)
            end
            local blocking = ch:GetAttribute("Blocking")
            local stunned = ch:GetAttribute("Stunned") == true
            local buf = ch:GetAttribute("ParryBuffered") == true
            if blocking == true then
                S.stats.branch_c = S.stats.branch_c + 1
                via = "BranchC"
            elseif (stunned or buf) and blocking ~= true then
                S.stats.branch_a = S.stats.branch_a + 1
                via = "BranchA"
            end
            if not S.activatedSeen and CRC and CRC.Fire then
                CRC.Fire("Block", "Activated", Workspace:GetServerTimeNow())
                via = "Block+CRC"
            elseif S.activatedSeen then
                S.stats.belt_suppressed = S.stats.belt_suppressed + 1
            end
        elseif CRC and CRC.Fire then
            CRC.Fire("Block", "Activated", Workspace:GetServerTimeNow())
            via = "CRC"
            fired = true
        end
    end)

    if fired and ok then
        S.stats.parry_fires = S.stats.parry_fires + 1
        if reason == "scan" then
            S.stats.scan_taps = S.stats.scan_taps + 1
        elseif reason == "opener" or reason == "child_added" then
            S.stats.opener_taps = S.stats.opener_taps + 1
        end
        local info = swingKeyStr and S.pending[swingKeyStr]
        if swingKeyStr then
            S.timing[swingKeyStr] = S.timing[swingKeyStr] or {}
            S.timing[swingKeyStr].via_act = via
            S.timing[swingKeyStr].fires = (S.timing[swingKeyStr].fires or 0) + 1
        end
        local tf = swingKeyStr and timingFields(swingKeyStr) or {}
        local dtHa = ""
        if typeof(tf.dt_hitbox_activated) == "number" then
            dtHa = string.format(" dt_hitbox_activated=%.3f", tf.dt_hitbox_activated)
        end
        Log.step(string.format(
            "TAP via=%s cdcleared=%d stunned=%s reason=%s delay=0%s %s",
            via, cdcleared, tostring(ch:GetAttribute("Stunned")), tostring(reason),
            dtHa, attrSnap(ch)
        ))
        logDecision(
            info and info.attacker or "?",
            info and info.attack or "?",
            info and info.swingId or "?",
            tostring(reason or "?"),
            "TAP",
            tostring(via)
        )
        watchPerfectAttr(ch, swingKeyStr)
        tf.gen = S.gen
        tf.reason = tostring(reason)
        tf.via = via
        tf.cdcleared = cdcleared
        emitEvent("BLOCK_ACTIVATED", tf)
        S.unblockGen = S.unblockGen + 1
        local myUnblock = S.unblockGen
        trackDelay(S.tapReleaseSec, function()
            if S.unblockGen ~= myUnblock then return end
            doUnblock(swingKeyStr)
        end)
        S.lastParry = os.clock()
        return true, nil
    end
    return fail(err or "no_fire")
end

local parryOnce

parryOnce = function(key, ch, reason, force)
    if not key then
        Log.step("SKIP reason=no_key")
        return false, "no_key"
    end
    local info = S.pending[key]
    local atk = info and info.attacker or "?"
    local attack = info and info.attack or "?"
    local swingId = info and info.swingId or "?"
    if S.fired[key] then
        logDecision(atk, attack, swingId, tostring(reason or "?"), "SKIP", "already_fired")
        return false, "already_fired"
    end
    if not ch then
        Log.step("SKIP reason=no_char")
        return false, "no_char"
    end
    if not CONFIG.ENABLED then
        Log.step("SKIP reason=enabled_false")
        return false, "enabled_false"
    end
    local now = os.clock()
    if not force and now - S.lastParry < MIN_BLOCK_INTERVAL then
        S.stats.activated_dup_suppressed = S.stats.activated_dup_suppressed + 1
        logDecision(atk, attack, swingId, tostring(reason or "?"), "SKIP", "rate")
        return false, "rate_limit"
    end
    local ok, why = fireBlockTap(reason or "tap", key)
    if ok then
        S.fired[key] = true
        S.stats.parry_once = S.stats.parry_once + 1
        return true, "ok"
    end
    if why == "rate" then
        return false, why
    end
    Log.warn(string.format("parryOnce fail key=%s ctx=%s why=%s", tostring(key), tostring(reason),
        tostring(why)))
    return false, why
end

-- gen13: patchConfirmPayload + the forced "last-chance Activate" it fed are REMOVED.
-- Evidence (16:04-16:22 log): confirms=11 patched=8 the whole session while activated_sent kept
-- climbing in lockstep with windup_taps — those 8 patched confirms were 8 genuine EXTRA
-- CRC.Fire("Block","Activated") sends, on a local rate gate (0.034s) looser than the server's real
-- floor (0.06s), landing on top of whatever the windup ticker had already timed for that swing and
-- risking the accept slot. The payload mutation itself (block=0/perfect=1) was independently proven
-- cosmetic/ignored by the server in gen7's confirm-hold test. windupTick is the sole Activated
-- source now; do not reintroduce a second one without a rate gate SHARED with S.lastTapAt.
local function handleVictimConfirm(extra, via)
    if #extra < 5 then return extra, false end
    S.stats.confirms_seen = S.stats.confirms_seen + 1
    local ch = lp.Character
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    local hp = hum and hum.Health or -1
    local key = swingKey(extra[1], extra[2], extra[3])
    S.timing[key] = S.timing[key] or {}
    if not S.timing[key].confirm_t then
        S.timing[key].confirm_t = os.clock()
    end
    local tf = timingFields(key)
    local block_before = extra[4]
    local perfect_before = extra[5]
    logNet("IN", "VictimHitConfirm", {
        swing = tostring(extra[3]),
        atk = tostring(extra[1]),
        attack = tostring(extra[2]),
        block_before = block_before,
        perfect_before = perfect_before,
        block_flag = block_before,
        perfect_flag = perfect_before,
        patched = 0,
        via = tostring(via),
        hp = hp,
        serverTime = Workspace:GetServerTimeNow(),
        clock = os.clock(),
        dt_hitbox_activated = tf.dt_hitbox_activated,
        dt_activated_confirm = tf.dt_activated_confirm,
    })
    -- combo-lockout check: if this confirm resolved as anything but PERFECT while we were
    -- Stunned/ParryWindowDisabled, log it explicitly — this is the suspected reason a windup
    -- tap can be firing on schedule yet a mid-string swing still lands as a raw HIT (server
    -- disables the parry window for the rest of a string once you take one non-perfect hit).
    if ch and (ch:GetAttribute("Stunned") == true or ch:GetAttribute("ParryWindowDisabled") == true)
        then
        Log.step(string.format(
            "COMBO_LOCK swing=%s atk=%s Stunned=%s ParryWindowDisabled=%s " ..
                "block_before=%s perfect_before=%s",
            tostring(extra[3]), tostring(extra[1]),
            tostring(ch:GetAttribute("Stunned")), tostring(ch:GetAttribute("ParryWindowDisabled")),
            tostring(block_before), tostring(perfect_before)
        ))
        emitEvent("COMBO_LOCK", {
            gen = S.gen, swing = tostring(extra[3]), atk = tostring(extra[1]),
            stunned = ch:GetAttribute("Stunned") == true,
            parryWindowDisabled = ch:GetAttribute("ParryWindowDisabled") == true,
        })
    end
    return extra, false
end

-- Confirm-hold: if we fired an Activated for this swing <CONFIRM_HOLD_TARGET ago, DROP the
-- victim confirm here and re-send it after a short delay so the Activated registers server-side
-- (PerfectBlocking) BEFORE the confirm arrives. Refire uses the UNhooked original CRC.Fire,
-- so it does not re-enter this CRC hook; its internal Server:FireServer re-enters the egress
-- hook, which passes held keys through untouched (see processCombatFireServer guard).
-- Returns "drop" if held (caller must NOT forward), else "forward".
local function maybeHoldConfirm(extra)
    -- DISABLED gen8: gen7 proved holding the confirm to ~64ms after Activated still = DMG.
    -- Confirm timing does not drive PerfectBlocking; the server resolves on its own hitbox
    -- tick. Kept for reference; windup-prediction replaces it. Flip to re-enable.
    if not CONFIG.CONFIRM_HOLD then return "forward" end
    if #extra < 5 then return "forward" end
    if not PARRY_ATTACKS[tostring(extra[2])] then return "forward" end
    local key = swingKey(extra[1], extra[2], extra[3])
    if S.confirmHeld[key] then return "forward" end
    local t = S.timing[key]
    local act = t and t.activated_t
    if not act then return "forward" end
    local elapsed = os.clock() - act
    if elapsed >= S.confirmHoldTarget then return "forward" end
    S.confirmHeld[key] = true
    local wait = math.min(S.confirmHoldTarget - elapsed, S.confirmHoldMax)
    local snap = { table.unpack(extra) }
    Log.step(string.format(
        "CONFIRM_HOLD swing=%s wait=%.3f elapsed=%.3f",
        tostring(extra[3]), wait, elapsed
    ))
    trackDelay(wait, function()
        local fn = S.origFire or G[GKEY_CRC]
        if not fn then return end
        pcall(function() fn("VictimHitConfirm", "Confirm", table.unpack(snap)) end)
        logNet("OUT", "VictimHitConfirm.refire", {
            swing = tostring(snap[3]),
            atk = tostring(snap[1]),
            attack = tostring(snap[2]),
            perfect_after = snap[5],
            wait = wait,
            clock = os.clock(),
        })
    end)
    return "drop"
end

local function guardAnticheatCrash()
    local ok, remote = pcall(function()
        return RS:WaitForChild("Remotes"):WaitForChild("AnticheatClientCrash")
    end)
    if not ok or not remote or not getconnections then return end
    local n = 0
    for _, conn in ipairs(getconnections(remote.OnClientEvent)) do
        pcall(function() conn:Disable() end)
        n = n + 1
    end
    if n > 0 then Log.step("AnticheatClientCrash disconnected n=" .. n) end
end

local function processCombatFireServer(args)
    local payload = args[1]
    if type(payload) == "table" and payload.Type == "Combat"
        and payload.Action == "Block" and payload.Func == "Activated" then
        noteActivatedOut("ServerFS", {
            serverTime = typeof(args[2]) == "number" and args[2] or Workspace:GetServerTimeNow(),
        })
    end
    if not CONFIG.ENABLED or type(payload) ~= "table" or payload.Type ~= "Combat" then
        return nil
    end
    if payload.Action == "VictimHitConfirm" and payload.Func == "Confirm" then
        local extra = { select(2, table.unpack(args)) }
        -- held/refired by the CRC layer → forward as-is (already patched perfect=1)
        if #extra >= 3 and S.confirmHeld[swingKey(extra[1], extra[2], extra[3])] then
            return nil
        end
        local patchedExtra, patched = handleVictimConfirm(extra, "FireServer")
        if patched then
            return { payload, table.unpack(patchedExtra) }
        end
    end
    return nil
end

local function onCombatFire(action, func, ...)
    if stale() then
        return (G[GKEY_CRC] or S.origFire or CRC.Fire)(action, func, ...)
    end
    local args = { ... }
    if action == "__AUTOPARRY_TEST__" and func == "SelfTest" then
        Log.step("hook self-test CRC.Fire captured gen=" .. tostring(args[1]))
        return (S.origFire or G[GKEY_CRC])(action, func, table.unpack(args))
    end
    if action == "Block" and func == "Activated" then
        noteActivatedOut("CRC", {
            serverTime = typeof(args[1]) == "number" and args[1] or Workspace:GetServerTimeNow(),
        })
    end
    if CONFIG.ENABLED and action == "VictimHitConfirm" and func == "Confirm" and #args >= 5 then
        local patched
        args, patched = handleVictimConfirm(args, "CRC")
        if patched and maybeHoldConfirm(args) == "drop" then
            return  -- confirm held; re-sent after our Activated registers server-side
        end
        if not patched then
            -- gen13: patching is intentionally always off (see handleVictimConfirm) — this is
            -- expected on every confirm, not an anomaly. WARN spammed F9 every M1 exchange;
            -- file-only.
            Log.step("CRC confirm not patched atk=" .. tostring(args[2]))
        end
    end
    return (S.origFire or G[GKEY_CRC])(action, func, table.unpack(args))
end

local function onFireServer(self, ...)
    if stale() then
        return (G[GKEY_SRV] or S.origFireServer)(self, ...)
    end
    local args = { ... }
    local routed = processCombatFireServer(args)
    if routed then
        return (S.origFireServer or G[GKEY_SRV])(self, table.unpack(routed))
    end
    return (S.origFireServer or G[GKEY_SRV])(self, ...)
end

local function onNamecall(self, ...)
    if stale() then
        return (G[GKEY_NC] or S.origNamecall)(self, ...)
    end
    local method = getnamecallmethod and getnamecallmethod() or ""
    if method == "FireServer" and self == Server and CONFIG.ENABLED then
        local args = { ... }
        local routed = processCombatFireServer(args)
        if routed then
            return (G[GKEY_NC] or S.origNamecall)(self, table.unpack(routed))
        end
    end
    return (G[GKEY_NC] or S.origNamecall)(self, ...)
end

local function installHooks()
    if S.hooksInstalled then return end
    if not S.crcHooked then
        local ok, err = pcall(function()
            if hookfunction then
                local wrap = newcclosure and newcclosure(onCombatFire) or onCombatFire
                S.origFire = hookfunction(CRC.Fire, wrap)
            else
                S.origFire = CRC.Fire
                CRC.Fire = onCombatFire
            end
            G[GKEY_CRC] = S.origFire
            S.crcHooked = true
            S.stats.hook_crc = true
        end)
        Log.step("CRC hook ok=" .. tostring(ok) .. " hookfunction=" .. tostring(hookfunction ~= nil)
            .. (err and (" err=" .. tostring(err)) or ""))
    end
    if not S.srvHooked then
        local ok, err = pcall(function()
            if hookfunction then
                local wrap = newcclosure and newcclosure(onFireServer) or onFireServer
                S.origFireServer = hookfunction(Server.FireServer, wrap)
            else
                Log.warn("no hookfunction — Server.FireServer hook skipped")
                return
            end
            G[GKEY_SRV] = S.origFireServer
            S.srvHooked = true
            S.stats.hook_srv = true
        end)
        Log.step("Server.FireServer hook ok=" .. tostring(ok)
            .. (err and (" err=" .. tostring(err)) or ""))
    end
    -- __namecall metamethod hook is DISABLED by default: it routes EVERY game method call through
    -- our closure, which is the top executor-crash vector and lags/crashes when a second heavy
    -- script (admin.lua ESP/WaitForChild volume) is also injected. It is now vestigial anyway —
    -- confirm-patching is dead (gen7), and our Activated is detected at the stable CRC-function
    -- layer. CRC.Fire + Server.FireServer function hooks cover everything we need.
    if CONFIG.NAMECALL_HOOK and not S.ncHooked and hookmetamethod and getnamecallmethod then
        local ok, err = pcall(function()
            local wrap = newcclosure and newcclosure(onNamecall) or onNamecall
            S.origNamecall = hookmetamethod(game, "__namecall", wrap)
            G[GKEY_NC] = S.origNamecall
            S.ncHooked = true
            S.stats.hook_nc = true
        end)
        Log.step("__namecall hook ok=" .. tostring(ok)
            .. (err and (" err=" .. tostring(err)) or ""))
    end
    S.hooksInstalled = S.crcHooked
end

local function hookSelfTest()
    if not S.crcHooked then
        Log.warn("hook self-test skip — CRC not hooked")
        return
    end
    local ok, err = pcall(function()
        CRC.Fire("__AUTOPARRY_TEST__", "SelfTest", S.gen)
    end)
    Log.step("hook self-test fire ok=" .. tostring(ok)
        .. (err and (" err=" .. tostring(err)) or ""))
end

local function removeHooks()
    restoreOutnumberedDashMultipliers()
    pcall(function()
        if S.crcHooked and (S.origFire or G[GKEY_CRC]) then
            local orig = S.origFire or G[GKEY_CRC]
            if hookfunction then hookfunction(CRC.Fire, orig) else CRC.Fire = orig end
        end
        if S.srvHooked and (S.origFireServer or G[GKEY_SRV]) then
            hookfunction(Server.FireServer, S.origFireServer or G[GKEY_SRV])
        end
        if S.ncHooked and (S.origNamecall or G[GKEY_NC]) then
            hookmetamethod(game, "__namecall", S.origNamecall or G[GKEY_NC])
        end
        if S.evasiveCdHooked and S.origEvasive and EvasiveMod then
            if hookfunction then
                hookfunction(EvasiveMod.Evasive, S.origEvasive)
            else
                EvasiveMod.Evasive = S.origEvasive
            end
        end
    end)
    S.crcHooked = false
    S.srvHooked = false
    S.ncHooked = false
    S.evasiveCdHooked = false
    S.origEvasive = nil
    S.dodgePinChar = nil
    if S.dodgeHbConn then
        pcall(function() S.dodgeHbConn:Disconnect() end)
        S.dodgeHbConn = nil
    end
    S.hooksInstalled = false
end

local function applyCombatSideEffects(enabled)
    if enabled then
        guardAnticheatCrash()
        installHooks()
        hookSelfTest()
    end
end

local function setEnabled(on)
    CONFIG.ENABLED = on == true
    applyCombatSideEffects(CONFIG.ENABLED)
    -- gen24: pinDodgeCd/BlockCooldown-pin are now ENABLED-gated at spawn time only (main()'s
    -- CharacterAdded handler) — toggling ON mid-session for an ALREADY-spawned character needs
    -- its own call here, or NO_DODGE_CD/NO_COOLDOWN silently wouldn't apply until next respawn.
    if CONFIG.ENABLED and lp.Character then
        pinDodgeCd(lp.Character)
    end
    Log.step("setEnabled " .. (CONFIG.ENABLED and "ON" or "OFF"))
    emitEvent("SET_ENABLED", { gen = S.gen, enabled = CONFIG.ENABLED })
    Hud.refresh()
end

local function setHudVisible(vis)
    CONFIG.HUD_VISIBLE = vis == true
    saveUiConfig(CONFIG.HIDE_KEY, CONFIG.HUD_VISIBLE, CONFIG.ENABLED)
    Hud.refresh()
end

local function parseIncomingHitbox(child, ch)
    if not child:IsA("BasePart") then return end
    local owner = child:FindFirstChild("Owner")
    local atk = child:FindFirstChild("AttackName")
    if not owner or not owner:IsA("StringValue") then return end
    if not atk or not atk:IsA("StringValue") then return end
    local attacker = owner.Value
    local attack = atk.Value
    if attacker == ch.Name or not PARRY_ATTACKS[attack] then return end
    local swingId = child:GetAttribute("VictimSwingId")
    if typeof(swingId) ~= "string" or swingId == "" then return end
    return attacker, attack, swingId
end

local function nearingHitbox(part, ch)
    local hrp = ch:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    local rel = part.CFrame:PointToObjectSpace(hrp.Position)
    local half = part.Size * 0.5
    return math.abs(rel.X) <= half.X + NEAR_MARGIN
        and math.abs(rel.Y) <= half.Y + NEAR_MARGIN
        and math.abs(rel.Z) <= half.Z + NEAR_MARGIN
end

local function attackerInMeleeRange(attackerName, ch)
    if not attackerName or not ch then return false end
    local hrp = ch:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    local plr = Players:FindFirstChild(attackerName)
    local atkChar = (plr and plr.Character) or Workspace:FindFirstChild(attackerName)
    if not atkChar then return false end
    local atkHrp = atkChar:FindFirstChild("HumanoidRootPart")
    if not atkHrp then return false end
    return (hrp.Position - atkHrp.Position).Magnitude <= S.attackerMeleeRange
end

local function isThreatToLocal(child, ch, attackerName)
    if not child or not ch then return false end
    local melee = attackerName and attackerInMeleeRange(attackerName, ch)
    if not child:IsA("BasePart") then
        return melee == true
    end
    S.overlap.FilterDescendantsInstances = { ch }
    local near = nearingHitbox(child, ch)
    if near then return true end
    local overlap = #Workspace:GetPartBoundsInBox(child.CFrame, child.Size, S.overlap) > 0
    if overlap then return true end
    return melee == true
end

local function logThreatSkip(attacker, attack, swingId, reason)
    local key = swingKey(attacker, attack, swingId)
    if S.threatSkipLogged[key] then return end
    S.threatSkipLogged[key] = true
    S.stats.world_ignored = S.stats.world_ignored + 1
    logDecision(attacker, attack, swingId, tostring(reason or "?"), "SKIP", "far")
    if CONFIG.VERBOSE_SCAN then
        Log.step(string.format(
            "THREAT_SKIP far %s from=%s swing=%s reason=%s",
            attack, attacker, tostring(swingId), tostring(reason)
        ))
        return
    end
    S.threatSkipAgg.n = S.threatSkipAgg.n + 1
    local now = os.clock()
    if now - (S.threatSkipAgg.lastLog or 0) >= 1 then
        Log.step(string.format("THREAT_SKIP n=%d", S.threatSkipAgg.n))
        S.threatSkipAgg.n = 0
        S.threatSkipAgg.lastLog = now
    end
end

local function logHitboxParse(kind, name)
    local now = os.clock()
    local dk = tostring(kind) .. "\1" .. tostring(name)
    local last = S.hitboxParseDebounce[dk] or 0
    if now - last < 0.5 then return end
    S.hitboxParseDebounce[dk] = now
    Log.step(string.format("%s name=%s", tostring(kind), tostring(name)))
end

local THREAT_WAIT_SEC = 0.10
local tryImmediateParry

-- child_added: not threat yet → Heartbeat poll ≤0.25s; become threat → IMMEDIATE
local function threatWaitThenImmediate(child, attacker, attack, swingId, reason)
    local ch = lp.Character
    if not ch then return end
    if isThreatToLocal(child, ch, attacker) then
        local near = child:IsA("BasePart") and nearingHitbox(child, ch)
        local melee = attackerInMeleeRange(attacker, ch)
        if melee and not near then
            Log.step(string.format("THREAT_MELEE from=%s swing=%s", attacker, tostring(swingId)))
        end
        if ch:GetAttribute("Stunned") ~= true and melee then
            Log.step(string.format(
                "OPENER %s from=%s swing=%s reason=%s",
                attack, attacker, tostring(swingId), tostring(reason)
            ))
            tryImmediateParry(attacker, attack, swingId, "opener")
        else
            tryImmediateParry(attacker, attack, swingId, reason)
        end
        return
    end
    local key = swingKey(attacker, attack, swingId)
    if S.threatSkipLogged[key] then return end
    Log.step(string.format(
        "THREAT_WAIT %s from=%s swing=%s window=%.2f reason=%s",
        attack, attacker, tostring(swingId), THREAT_WAIT_SEC, tostring(reason)
    ))
    local deadline = os.clock() + THREAT_WAIT_SEC
    local conn
    conn = RunService.Heartbeat:Connect(function()
        if stale() or not child.Parent then
            releaseTransient(conn)
            return
        end
        local ch2 = lp.Character
        if not ch2 then return end
        if isThreatToLocal(child, ch2, attacker) then
            releaseTransient(conn)
            local near = child:IsA("BasePart") and nearingHitbox(child, ch2)
            local melee = attackerInMeleeRange(attacker, ch2)
            if melee and not near then
                Log.step(string.format("THREAT_MELEE from=%s swing=%s", attacker, tostring(swingId))
                    )
            end
            Log.step(string.format(
                "THREAT_WAIT→IMMEDIATE %s from=%s swing=%s reason=%s",
                attack, attacker, tostring(swingId), tostring(reason)
            ))
            if ch2:GetAttribute("Stunned") ~= true and melee then
                Log.step(string.format(
                    "OPENER %s from=%s swing=%s reason=%s",
                    attack, attacker, tostring(swingId), tostring(reason)
                ))
                tryImmediateParry(attacker, attack, swingId, "opener")
            else
                tryImmediateParry(attacker, attack, swingId, reason)
            end
            return
        end
        if os.clock() >= deadline then
            releaseTransient(conn)
            -- last-chance: became threat on final frame after poll miss
            if isThreatToLocal(child, ch2, attacker) then
                Log.step(string.format(
                    "THREAT_WAIT→IMMEDIATE %s from=%s swing=%s reason=%s",
                    attack, attacker, tostring(swingId), tostring(reason)
                ))
                tryImmediateParry(attacker, attack, swingId, reason)
            else
                logThreatSkip(attacker, attack, swingId, reason)
            end
        end
    end)
    trackTransient(conn)
end

local function scanHitboxes()
    if not CONFIG.ENABLED or not CONFIG.PROACTIVE then return end
    local ch = lp.Character
    local folder = S.hitboxes
    if not ch or not folder then return end
    local ok, why = canScan(ch)
    if not ok then
        if CONFIG.VERBOSE_SCAN then Log.info("scan skip: " .. why) end
        return
    end

    S.overlap.FilterDescendantsInstances = { ch }

    for _, child in ipairs(folder:GetChildren()) do
        local attacker, attack, swingId = parseIncomingHitbox(child, ch)
        if attacker and isThreatToLocal(child, ch, attacker) then
            local key = swingKey(attacker, attack, swingId)
            if not S.fired[key] then
                local near = nearingHitbox(child, ch)
                local overlap = #Workspace:GetPartBoundsInBox(child.CFrame, child.Size, S.overlap) >
                    0
                if near then S.stats.scan_near = S.stats.scan_near + 1 end
                if overlap then S.stats.scan_overlap = S.stats.scan_overlap + 1 end
                if not S.scanLogged[key] then
                    S.scanLogged[key] = true
                    Log.step(string.format(
                        "SCAN %s from=%s swing=%s near=%s overlap=%s backup=1",
                        attack, attacker, tostring(swingId), tostring(near), tostring(overlap)
                    ))
                end
                S.reported[child] = true
                tryImmediateParry(attacker, attack, swingId, "scan")
            end
        end
    end

    for part in pairs(S.reported) do
        if part.Parent == nil then S.reported[part] = nil end
    end
    local cutoff = os.clock() - S.swingTtl
    for k, t in pairs(S.swings) do
        if t < cutoff then
            if S.pending[k] and not S.swingFinalized[k] then
                finalizeSwing(k, "TIMEOUT")
            end
            S.swings[k] = nil
            S.fired[k] = nil
            S.scanTried[k] = nil
            S.scanLogged[k] = nil
            S.threatSkipLogged[k] = nil
            S.swingFinalized[k] = nil
            S.confirmHeld[k] = nil
            S.lastConfirm[k] = nil
            S.pending[k] = nil
            S.timing[k] = nil
        end
    end
end

-- Path A: immediate Block on hitbox — no windup delay
tryImmediateParry = function(attacker, attack, swingId, reason)
    if not CONFIG.ENABLED then
        Log.step("SKIP reason=enabled_false")
        return
    end
    local ch = lp.Character
    if not ch then
        Log.step("SKIP reason=no_char")
        return
    end
    local key = notePending(attacker, attack, swingId, reason)
    if S.fired[key] then
        logDecision(attacker, attack, swingId, tostring(reason or "?"), "SKIP", "already_fired")
        return
    end
    if reason == "scan" and S.scanTried[key] then
        return
    end
    Log.step(string.format(
        "IMMEDIATE %s from=%s swing=%s delay=0 reason=%s %s",
        attack, attacker, swingId, tostring(reason), attrSnap(ch)
    ))
    emitEvent("HITBOX", {
        gen = S.gen,
        attack = attack,
        attacker = attacker,
        swing = swingId,
        hitbox_t = S.timing[key] and S.timing[key].hitbox_t,
        reason = tostring(reason),
    })
    local ok, why = parryOnce(key, ch, reason or "hitbox", true)
    -- one scan attempt per swing; allow retry while greenzone (leave zone → rescan)
    if reason == "scan" and (ok or why ~= "greenzone") then
        S.scanTried[key] = true
    end
end

local function onHitboxAdded(child)
    if stale() then return end
    local ch = lp.Character
    if not ch then return end
    local attacker, attack, swingId = parseIncomingHitbox(child, ch)
    if attacker then
        Log.step(string.format("HITBOX new %s from=%s swing=%s", attack, attacker, tostring(swingId)
            ))
        threatWaitThenImmediate(child, attacker, attack, swingId, "child_added")
        return
    end
    if not child:IsA("BasePart") then return end
    logHitboxParse("HITBOX_PARSE_WAIT", child.Name)
    task.defer(function()
        if stale() or not child.Parent then return end
        local deadline = os.clock() + 0.15
        local conn
        conn = RunService.Heartbeat:Connect(function()
            if stale() or not child.Parent then
                releaseTransient(conn)
                return
            end
            local ch2 = lp.Character
            if not ch2 then return end
            local a, atk, sid = parseIncomingHitbox(child, ch2)
            if a then
                releaseTransient(conn)
                Log.step(string.format("HITBOX new %s from=%s swing=%s", atk, a, tostring(sid)))
                threatWaitThenImmediate(child, a, atk, sid, "child_added")
                return
            end
            if os.clock() >= deadline then
                releaseTransient(conn)
                logHitboxParse("HITBOX_PARSE_FAIL", child.Name)
            end
        end)
        trackTransient(conn)
    end)
end

local function seedExistingHitboxes(folder)
    local ch = lp.Character
    if not ch or not folder then return end
    local n = 0
    for _, child in ipairs(folder:GetChildren()) do
        local attacker, attack, swingId = parseIncomingHitbox(child, ch)
        if attacker then
            if isThreatToLocal(child, ch, attacker) then
                n = n + 1
                tryImmediateParry(attacker, attack, swingId, "seed")
            else
                logThreatSkip(attacker, attack, swingId, "seed")
            end
        end
    end
    if n > 0 then
        Log.step("seed hitboxes existing=" .. tostring(n))
    end
end

local function heartbeat()
    local now = os.clock()
    if now - S.lastHb < S.heartbeatSec then return end
    S.lastHb = now
    if now - S.lastTapPrune >= S.tapPruneSec then
        S.lastTapPrune = now
        pruneTapResults(now)
    end
    local folder = S.hitboxes
    local nBox = folder and #folder:GetChildren() or -1
    local ch = lp.Character
    Log.info(string.format(
        "HB enabled=%s gen=%s mark=gen53 %s hooks=%s/%s/%s hitboxes=%s | " ..
            "windup bursts=%d taps=%d prec=%d force=%d live=%d edge=%d hold=%d " ..
            "buffer=%d match=%d unmatch=%d reject=%d | FX P1=%d P2=%d B=%d H=%d " ..
            "| perfectRate=%.1f%% | ok_fx=%d dmg=%d | confirms=%d | DODGE " ..
            "acc=%d skip=%d iframe=%d uv_ok=%s uv_clear=%d grant=%s | last=%s",
        tostring(CONFIG.ENABLED), tostring(S.gen), expPathTag(),
        tostring(S.stats.hook_crc), tostring(S.stats.hook_srv), tostring(S.stats.hook_nc),
        tostring(nBox),
        S.stats.windup_bursts, S.stats.windup_taps,
        S.stats.tap_precision or 0, S.stats.tap_force or 0, S.stats.tap_hitboxLive or 0,
        S.stats.overlap_edges or 0, S.stats.overlap_held_m1_taps or 0, S.stats.
            overlap_buffer_rise_taps or 0,
        S.stats.outcomes_matched or 0, S.stats.outcomes_unmatched or 0, S.stats.
            learner_rejects_unmatched or 0,
        S.stats.fx_perfect_m1, S.stats.fx_perfect_m2, S.stats.fx_block, S.stats.fx_hit,
        (function()
            local p = S.stats.fx_perfect_m1 + S.stats.fx_perfect_m2
            local t = p + S.stats.fx_block + S.stats.fx_hit
            return t > 0 and (p / t * 100) or 0
        end)(),
        S.stats.ok_fx, S.stats.dmg,
        S.stats.confirms_seen,
        S.stats.dodge_accept or 0, S.stats.dodge_skip or 0, S.stats.dodge_iframe_ok or 0,
        tostring(S.stats.dodge_uv_ok), S.stats.dodge_uv_clear,
        tostring(ch and ch:GetAttribute("OutnumberedEvasiveGrant")),
        S.lastResult
    ))
    rateSnap("hb")
end

S.perfSnapshot = function(dt)
    local now = os.clock()
    local perf = S.perf
    perf.preDt = tonumber(dt) or 0
    if now - perf.since < 1 then return end
    local active = 0
    for _ in pairs(S.windupActive) do active = active + 1 end
    Log.info(string.format(
        "PERF_SNAPSHOT pre_dt=%.4f windups=%d overlap_queries=%d " ..
            "fallback_scans=%d dodge_polls=%d dodge_writes=%d diag_suppressed=%d",
        perf.preDt, active, perf.overlapQueries, perf.fallbackScans, perf.dodgeSafetyPolls,
        perf.dodgeDebugWrites, perf.diagSuppressed
    ))
    emitEvent("PERF_SNAPSHOT", {
        gen = S.gen, pre_dt = perf.preDt, windups = active, overlap_queries = perf.overlapQueries,
        fallback_scans = perf.fallbackScans, dodge_polls = perf.dodgeSafetyPolls,
        dodge_writes = perf.dodgeDebugWrites, diag_suppressed = perf.diagSuppressed,
    })
    perf.since = now
    perf.overlapQueries = 0
    perf.fallbackScans = 0
    perf.dodgeSafetyPolls = 0
    perf.dodgeDebugWrites = 0
    perf.diagSuppressed = 0
end

-- ---------- Hud (paint ≠ hooks) ----------
do
    local shell, result, chip, chipStroke, hideConn
    local listening = false
    local listenToken = 0
    local COLORS = {
        idle = Color3.fromRGB(120, 120, 120),
        success = Color3.fromRGB(80, 200, 120),
        fail = Color3.fromRGB(220, 160, 60),
        damage = Color3.fromRGB(220, 80, 80),
        chipIdle = Color3.fromRGB(100, 100, 100),
        chipListen = Color3.fromRGB(150, 200, 220),
        chipWarn = Color3.fromRGB(220, 80, 80),
        strokeIdle = Color3.fromRGB(40, 40, 40),
        strokeListen = Color3.fromRGB(150, 200, 220),
    }

    local function cancelListening()
        listening = false
        listenToken = listenToken + 1
        if chip then
            chip.Text = keyLabel(CONFIG.HIDE_KEY)
            chip.TextColor3 = COLORS.chipIdle
        end
        if chipStroke then chipStroke.Color = COLORS.strokeIdle end
    end

    function Hud.setListening(b)
        if b then
            listening = true
            listenToken = listenToken + 1
            local tok = listenToken
            if chip then
                chip.Text = "..."
                chip.TextColor3 = COLORS.chipListen
            end
            if chipStroke then chipStroke.Color = COLORS.strokeListen end
            trackDelay(S.rebindTimeout, function()
                if tok ~= listenToken then return end
                if listening then
                    cancelListening()
                    Log.step("rebind timeout")
                end
            end)
        else
            cancelListening()
        end
    end

    function Hud.setResult(text, kind)
        if not result then return end
        result.Text = truncateResult(text)
        if kind == "success" then
            result.TextColor3 = COLORS.success
        elseif kind == "dodge" then
            result.TextColor3 = Color3.fromRGB(120, 210, 140)
        elseif kind == "fail" then
            result.TextColor3 = COLORS.fail
        elseif kind == "damage" then
            result.TextColor3 = COLORS.damage
        else
            result.TextColor3 = COLORS.idle
        end
    end

    function Hud.save()
        -- Kit debounce callbacks can outlive unload; never let an old inject write.
        if stale() then return end
        UI_CFG.enabled = CONFIG.ENABLED
        UI_CFG.hideKey = CONFIG.HIDE_KEY.Name
        UI_CFG.hudVisible = CONFIG.HUD_VISIBLE
        saveUiConfig(CONFIG.HIDE_KEY, CONFIG.HUD_VISIBLE, CONFIG.ENABLED)
    end

    -- paint ONLY — never installHooks / hookSelfTest
    function Hud.refresh()
        if not shell then return end
        if not shell.hosted then shell.root.Visible = CONFIG.HUD_VISIBLE == true end
        if chip and not listening then
            chip.Text = keyLabel(CONFIG.HIDE_KEY)
            chip.TextColor3 = COLORS.chipIdle
        end
        if result then Hud.setResult(S.lastResult, S.lastResultKind) end
    end

    local function bindHide()
        if hideConn then hideConn:Disconnect() end
        hideConn = shell.host.hideBind(function()
            if stale() or listening then return end
            setHudVisible(not CONFIG.HUD_VISIBLE)
        end, CONFIG.HIDE_KEY)
        if hideConn then track(hideConn) end
    end

    local function unload()
        if not stale() then G[GKEY].destroy() end
    end

    local function onInputBegan(input, _gameProcessed)
        if stale() then return end
        if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
        local kc = input.KeyCode
        if listening then
            if kc == Enum.KeyCode.Escape then
                cancelListening()
                Log.step("rebind cancel Esc")
                return
            end
            if SOFT_BLOCK[kc] then
                if chip then
                    chip.Text = keyLabel(kc)
                    chip.TextColor3 = COLORS.chipWarn
                end
                if chipStroke then chipStroke.Color = COLORS.chipWarn end
                local tok = listenToken
                trackDelay(1.5, function()
                    if tok ~= listenToken or not listening then return end
                    if chip then
                        chip.Text = "..."
                        chip.TextColor3 = COLORS.chipListen
                    end
                    if chipStroke then chipStroke.Color = COLORS.strokeListen end
                end)
                Log.step("rebind soft-block " .. tostring(kc.Name))
                return
            end
            CONFIG.HIDE_KEY = kc
            saveUiConfig(CONFIG.HIDE_KEY, CONFIG.HUD_VISIBLE, CONFIG.ENABLED)
            cancelListening()
            bindHide()
            Hud.refresh()
            Log.step("rebind hideKey=" .. tostring(kc.Name))
            emitEvent("REBIND", { gen = S.gen, hideKey = kc.Name })
            return
        end
        -- Preserve a standalone K hide binding; otherwise honor the advertised unload key.
        if kc == Enum.KeyCode.K and (shell.hosted or CONFIG.HIDE_KEY ~= kc) then unload() end
    end

    function Hud.build()
        local Kit = HOST and HOST.ui
        if not Kit then
            for _, path in ipairs({ "../scripts/r3st_ui.lua", "r3st_ui.lua",
                "scripts/r3st_ui.lua" }) do
                local ok, value = pcall(function() return loadfile(path)() end)
                if ok and type(value) == "table" then Kit = value; break end
            end
        end
        assert(Kit and Kit.SHELL_CONTRACT == "1", "R3ST shell contract mismatch")
        shell = Kit.moduleShell({
            id = "gakuran", title = "Gakuran", version = BUILD_VERSION,
            subtitle = "autoparry+dodge", placeId = PLACE_ID,
            hostGlobal = HOST or false,
            cfg = UI_CFG, save = Hud.save, live = {}, conns = S.conns,
            onUnload = unload,
        })
        local W = shell.W
        local page = shell.page("Main")
        W.section(page, "autoparry+dodge g" .. tostring(S.gen))
        chip = W.button(page, keyLabel(CONFIG.HIDE_KEY), nil, function()
            Hud.setListening(true)
        end)
        chipStroke = chip:FindFirstChildOfClass("UIStroke")
        W.toggle(page, {
            label = "", key = "enabled", stateText = true,
            get = function() return CONFIG.ENABLED end, set = setEnabled,
        })
        result = W.statusRow(page, function() return S.lastResult end)
        track(UserInputService.InputBegan:Connect(onInputBegan))
        bindHide()
        shell.ready()
        Hud.refresh()
        G[GKEY].build = BUILD_VERSION
        G[GKEY].embedded = shell.hosted
        G[GKEY].gui = shell.screen
        G[GKEY].root = shell.root
        Log.step("UI build=" .. BUILD_VERSION .. " embedded=" .. tostring(shell.hosted)
            .. " resumed enabled=" .. tostring(CONFIG.ENABLED))
        return shell.screen
    end

    function Hud.destroy()
        -- Flush before dropping the root. Delayed kit writers are gated by stale().
        saveUiConfig(CONFIG.HIDE_KEY, CONFIG.HUD_VISIBLE, CONFIG.ENABLED)
        cancelListening()
        if hideConn then hideConn:Disconnect(); hideConn = nil end
        if shell then shell.destroy(); shell = nil end
        result, chip, chipStroke = nil, nil, nil
    end
end

local function wireHealthWatch(ch)
    if not ch then return end
    local hum = ch:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    S.lastHp = hum.Health
    trackLocalChar(hum.HealthChanged:Connect(function(hp)
        if stale() or not CONFIG.ENABLED then return end
        local prev = S.lastHp
        S.lastHp = hp
        if prev and hp < prev - 0.5 then
            Log.step(string.format("DAMAGE hp %.1f -> %.1f", prev, hp))
            setLastResult(string.format("DMG hp %.0f", hp), "damage")
            emitEvent("DAMAGE_TAKEN", { gen = S.gen, hp = hp, prev = prev })
            S.stats.damage_taken = S.stats.damage_taken + 1
            S.stats.dmg = S.stats.dmg + 1
        end
    end))
end

local function tapKey(attacker, attack)
    return tostring(attacker or "?") .. "\1" .. tostring(attack or "M1")
end

local function bindCombatBroadcast()
    local ok, CB = pcall(function()
        return require(RS.Shared.Network.CombatBroadcast)
    end)
    if not ok or not CB or not CB.On then
        Log.warn("CombatBroadcast unavailable")
        return
    end

    local function bind(evt, fn)
        local conn = CB.On(evt, fn)
        if conn then track(conn) end
    end

    -- FX_CORRELATE: link server outcome to our last windup tap timing. This is the tuning
    -- signal — perfect vs block vs hit as a function of dt-since-last-Activated.
    local function correlate(outcome, attack, attacker)
        local now = os.clock()
        local key = tapKey(attacker, attack)
        local taps = S.tapsByKey[key]
        local fresh = {}
        local hadAnyUnconsumed = false
        if taps then
            for i = 1, #taps do
                local candidate = taps[i]
                if not candidate.consumed then
                    hadAnyUnconsumed = true
                    local age = now - candidate.sentLocal
                    if age >= 0 and age <= LEARN_BLOCK_FRESH_MAX then
                        fresh[#fresh + 1] = candidate
                    end
                end
            end
            local i = 1
            while i <= #taps do
                local candidate = taps[i]
                if candidate.consumed or now - candidate.sentLocal > LEARN_BLOCK_FRESH_MAX then
                    table.remove(taps, i)
                else
                    i = i + 1
                end
            end
            if #taps == 0 then S.tapsByKey[key] = nil end
        end
        local pendingSwingIds = {}
        for _, info in pairs(S.pending) do
            if info.attacker == attacker and info.attack == attack and info.swingId then
                pendingSwingIds[#pendingSwingIds + 1] = info.swingId
            end
        end
        local tap = nil
        local pairRule = "none"
        local unmatchedReason = "no_candidate_tap"
        if #fresh == 0 then
            if hadAnyUnconsumed then
                unmatchedReason = "late_outcome"
            end
        else
            for fi = 1, #fresh do
                local c = fresh[fi]
                if c.swingId then
                    for _, sid in ipairs(pendingSwingIds) do
                        if c.swingId == sid then
                            tap = c
                            pairRule = "swingId"
                            S.stats.pair_swingid = (S.stats.pair_swingid or 0) + 1
                            break
                        end
                    end
                end
                if tap then break end
            end
            if not tap then
                local bestAge = math.huge
                local classOkCount = 0
                for fi = 1, #fresh do
                    local c = fresh[fi]
                    if c.attack and c.attack ~= attack then
                        -- skip class mismatch candidate
                    else
                        classOkCount = classOkCount + 1
                        local age = now - c.sentLocal
                        if age < bestAge then
                            bestAge = age
                            tap = c
                        end
                    end
                end
                if tap then
                    pairRule = "closest"
                    S.stats.pair_closest = (S.stats.pair_closest or 0) + 1
                    unmatchedReason = ""
                elseif classOkCount == 0 then
                    unmatchedReason = "class_mismatch"
                else
                    unmatchedReason = "unknown"
                end
            else
                unmatchedReason = ""
            end
            if tap then
                tap.consumed = true
                local tlist = S.tapsByKey[key]
                if tlist then
                    for ti = 1, #tlist do
                        if tlist[ti] == tap then
                            table.remove(tlist, ti)
                            break
                        end
                    end
                    if #tlist == 0 then S.tapsByKey[key] = nil end
                end
            end
        end
        local pairStatus = tap and "matched" or "unmatched"
        if pairStatus == "unmatched" then
            S.stats.unmatched_by_reason = S.stats.unmatched_by_reason or {}
            S.stats.unmatched_by_reason[unmatchedReason] = (S.stats.unmatched_by_reason[
                unmatchedReason] or 0) + 1
        end
        local dtTap = tap and (now - tap.sentLocal) or -1
        -- dt_since_tap is os.clock()-based (our local send time only) — it can't see one-way ping,
        -- so two swings with the same dt_since_tap can resolve differently purely from network
        -- jitter (gen14 log: dt=0.074 produced both a PERFECT and a BLOCK). dt_since_tap_server
        -- uses Workspace:GetServerTimeNow() at both ends instead, which removes OUR frame jitter
        -- and gives a truer read of how close the tap landed to the server's own resolution clock.
        local dtTapServer = -1
        local okSt, nowSt = pcall(function() return Workspace:GetServerTimeNow() end)
        if okSt and typeof(nowSt) == "number" and tap and typeof(tap.sentServer) == "number" then
            dtTapServer = nowSt - tap.sentServer
        end
        local ch = lp.Character
        local scanOk, scanWhy = canScan(ch)
        local outcomeFresh = dtTap >= 0 and ((outcome == "HIT" and dtTap <= LEARN_FRESH_MAX)
            or (outcome ~= "HIT" and dtTap <= LEARN_BLOCK_FRESH_MAX))
        local trainable = tap ~= nil and outcomeFresh and scanOk and not (ch and (ch:GetAttribute(
            "GuardBroken") == true
            or ch:GetAttribute("ParryWindowDisabled") == true))
        if tap then
            S.stats.outcomes_matched = S.stats.outcomes_matched + 1
            Log.step(string.format(
                "OUTCOME_MATCH id=%d outcome=%s from=%s attack=%s dt=%.3f " ..
                    "epoch=%d swing=%s pair_rule=%s",
                tap.id, outcome, tostring(attacker), tostring(attack), dtTap,
                tap.epoch or 0, tostring(tap.swingId or "?"), pairRule
            ))
            emitEvent("OUTCOME_MATCH", { gen = S.gen, id = tap.id, outcome = outcome, attacker =
                tostring(attacker),
                attack = tostring(attack), dt = dtTap, overlap = tap.overlap, reason = tap.reason,
                epoch = tap.epoch or 0, swingId = tostring(tap.swingId or ""), pair_rule = pairRule,
                pair_status = pairStatus, unmatched_reason = "", tap_id = tap.id,
                outcome_source = "broadcast_fx", state = attrSnap(ch) })
        else
            S.stats.outcomes_unmatched = S.stats.outcomes_unmatched + 1
            S.stats.learner_rejects_unmatched = S.stats.learner_rejects_unmatched + 1
            Log.step(string.format(
                "OUTCOME_UNMATCHED outcome=%s from=%s attack=%s why=%s pair_rule=%s %s",
                outcome, tostring(attacker), tostring(attack), unmatchedReason, pairRule, attrSnap(
                    ch)
            ))
            emitEvent("OUTCOME_UNMATCHED", { gen = S.gen, outcome = outcome, attacker = tostring(
                attacker),
                attack = tostring(attack), pair_rule = pairRule, pair_status = pairStatus,
                unmatched_reason = unmatchedReason, epoch = 0, swingId = "",
                outcome_source = "broadcast_fx", state = attrSnap(ch) })
        end
        local tapStyle = tap and tap.style or "?"
        local tapReason = tap and tap.reason or "?"
        Log.step(string.format(
            "FX_CORRELATE outcome=%s attack=%s from=%s style=%s " ..
                "dt_since_tap=%.3f dt_since_tap_server=%.3f tap_from=%s " ..
                "tap_dt_start=%.3f reason=%s combo=%s predicted=%.3f force=%s " ..
                "scan=%s epoch=%d swing=%s pair_rule=%s pair_status=%s %s",
            outcome, tostring(attack), tostring(attacker), tostring(tapStyle), dtTap, dtTapServer,
            tostring(tap and tap.attacker or "?"), tap and tap.sentLocal or -1,
            tostring(tapReason), tostring(tap and tap.combo or 0),
            tap and tap.predicted or -1, tostring(tap and tap.source),
            scanOk and "ok" or tostring(scanWhy),
            tap and (tap.epoch or 0) or 0, tostring(tap and tap.swingId or "?"),
            pairRule, pairStatus, expPathTag()
        ))
        emitEvent("FX_CORRELATE", {
            gen = S.gen, outcome = outcome, attack = tostring(attack),
            attacker = tostring(attacker), style = tostring(tapStyle),
            dt_since_tap = dtTap, dt_since_tap_server = dtTapServer,
            tap_dt_start = tap and tap.sentLocal or -1,
            reason = tostring(tapReason),
            combo = tap and tap.combo or 0,
            predicted = tap and tap.predicted or -1,
            force = tap and tap.source == "force",
            scan = scanOk and "ok" or tostring(scanWhy),
            path1 = CONFIG.PATH1_PRECISION_ONLY,
            path2 = CONFIG.PATH2_GAP_EMA,
            epoch = tap and (tap.epoch or 0) or 0,
            swingId = tostring(tap and tap.swingId or ""),
            pair_rule = pairRule,
            pair_status = pairStatus,
            unmatched_reason = unmatchedReason,
            tap_id = tap and tap.id or 0,
            outcome_source = "broadcast_fx",
            state = attrSnap(ch),
        })
        -- Immutable event correlation prevents unrelated/stale FX from poisoning timing.
        if trainable then
            learnFromOutcome(outcome, tapStyle, tapReason, dtTap)
        elseif tap then
            Log.step("TIMING_LEARN SKIP outcome_gate=" .. (scanOk and "guardbroken_or_unparryable"
                or ("scan_" .. tostring(scanWhy))))
        end
        -- gen36: plain-English miss/block diagnosis so post-fight log read is instant.
        if outcome == "HIT" or outcome == "BLOCK" then
            local why = "?"
            if not tap then
                why = (unmatchedReason ~= "" and unmatchedReason) or "no_fresh_matching_tap"
            elseif unmatchedReason == "late_outcome" then
                why = "late_outcome"
            elseif unmatchedReason == "class_mismatch" then
                why = "class_mismatch"
            elseif dtTap < 0 then
                why = "no_tap_clock"
            elseif dtTap > 0.20 then
                why = "stale_tap_too_early_or_wrong_swing"
            elseif dtTap <= 0.06 and outcome == "HIT" then
                why = "in_window_but_HIT_rate_drop_or_unparryable_or_gate"
            elseif outcome == "BLOCK" and dtTap > 0.06 then
                why = "early_tap_normal_block"
            elseif not scanOk then
                why = "canScan_" .. tostring(scanWhy)
            elseif not trainable then
                why = "outcome_not_trainable"
            else
                why = "timing_or_server"
            end
            Log.step(string.format(
                "MISS_DIAG outcome=%s why=%s from=%s style=%s dt_tap=%.3f " ..
                    "reason=%s combo=%s predicted=%.3f epoch=%d swing=%s " ..
                    "pair_rule=%s pair_status=%s %s %s",
                outcome, why, tostring(attacker), tostring(tapStyle), dtTap,
                tostring(tapReason), tostring(tap and tap.combo or 0),
                tap and tap.predicted or -1,
                tap and (tap.epoch or 0) or 0, tostring(tap and tap.swingId or "?"),
                pairRule, pairStatus, attrSnap(ch), expPathTag()
            ))
            emitEvent("MISS_DIAG", {
                gen = S.gen, outcome = outcome, why = why,
                attacker = tostring(attacker), style = tostring(tapStyle),
                dt_tap = dtTap, reason = tostring(tapReason),
                combo = tap and tap.combo or 0, predicted = tap and tap.predicted or -1,
                path1 = CONFIG.PATH1_PRECISION_ONLY, path2 = CONFIG.PATH2_GAP_EMA,
                epoch = tap and (tap.epoch or 0) or 0,
                swingId = tostring(tap and tap.swingId or ""),
                pair_rule = pairRule, pair_status = pairStatus,
                unmatched_reason = unmatchedReason, tap_id = tap and tap.id or 0,
                outcome_source = "broadcast_fx", state = attrSnap(ch),
            })
        else
            Log.step(string.format(
                "PERFECT_DIAG from=%s style=%s dt_tap=%.3f reason=%s combo=%s predicted=%.3f %s %s",
                tostring(attacker), tostring(tapStyle), dtTap,
                tostring(tapReason), tostring(tap and tap.combo or 0),
                tap and tap.predicted or -1, attrSnap(ch), expPathTag()
            ))
        end
        rateSnap("after_" .. tostring(outcome))
    end

    bind("M1PerfectBlocked", function(attacker, victim)
        if victim == lp.Name then
            S.stats.perfect_fx = S.stats.perfect_fx + 1
            S.stats.fx_perfect_m1 = S.stats.fx_perfect_m1 + 1
            Log.step("SERVER FX M1PerfectBlocked")
            correlate("PERFECT", "M1", attacker)
            -- gen42: drop Blocking so next swing starts clean (no ride→BLOCK)
            S.blockAsserted = false
            pcall(function() if CRC and CRC.Fire then CRC.Fire("Block", "Deactivated") end end)
            local chp = lp.Character
            if chp then pcall(function() chp:SetAttribute("Blocking", nil) end) end
            resumeM1IfHeld(lp.Character)
        end
        resolveSwingResult("PARRY_OK", attacker, victim, "M1")
    end)
    bind("M2PerfectBlocked", function(attacker, victim)
        if victim == lp.Name then
            S.stats.perfect_fx = S.stats.perfect_fx + 1
            S.stats.fx_perfect_m2 = S.stats.fx_perfect_m2 + 1
            Log.step("SERVER FX M2PerfectBlocked")
            correlate("PERFECT", "M2", attacker)
            S.blockAsserted = false
            pcall(function() if CRC and CRC.Fire then CRC.Fire("Block", "Deactivated") end end)
            local chp = lp.Character
            if chp then pcall(function() chp:SetAttribute("Blocking", nil) end) end
            resumeM1IfHeld(lp.Character)
        end
        resolveSwingResult("PARRY_OK", attacker, victim, "M2")
    end)
    bind("M1Blocked", function(attacker, victim)
        if victim == lp.Name then
            S.stats.fx_block = S.stats.fx_block + 1
            Log.step("SERVER FX M1Blocked (NORMAL block — guard-break risk)")
            -- gen39: abort hold immediately — riding guard after BLOCK drains stamina → GuardBroken
            S.blockAsserted = false
            S.blockAbortUntil = os.clock() + 0.08
            pcall(function() if CRC and CRC.Fire then CRC.Fire("Block", "Deactivated") end end)
            local chb = lp.Character
            if chb then pcall(function() chb:SetAttribute("Blocking", nil) end) end
            Log.step("BLOCK_ABORT released hold after M1Blocked")
            resumeM1IfHeld(lp.Character)
            correlate("BLOCK", "M1", attacker)
            if S.pending and next(S.pending) then
                resolveSwingResult("PARRY_FAIL", attacker, victim, "M1")
            end
        end
    end)
    bind("M2Blocked", function(attacker, victim)
        if victim == lp.Name then
            S.stats.fx_block = S.stats.fx_block + 1
            Log.step("SERVER FX M2Blocked (NORMAL block — guard-break risk)")
            S.blockAsserted = false
            S.blockAbortUntil = os.clock() + 0.08
            pcall(function() if CRC and CRC.Fire then CRC.Fire("Block", "Deactivated") end end)
            local chb = lp.Character
            if chb then pcall(function() chb:SetAttribute("Blocking", nil) end) end
            Log.step("BLOCK_ABORT released hold after M2Blocked")
            resumeM1IfHeld(lp.Character)
            correlate("BLOCK", "M2", attacker)
            if S.pending and next(S.pending) then
                resolveSwingResult("PARRY_FAIL", attacker, victim, "M2")
            end
        end
    end)
    bind("M1Hit", function(attacker, victim)
        if victim == lp.Name then
            S.stats.fx_hit = S.stats.fx_hit + 1
            Log.step("SERVER FX M1Hit victim=" .. tostring(victim))
            correlate("HIT", "M1", attacker)
            if S.onDodgeVictimHit and next(S.pendingDodges) then S.onDodgeVictimHit(attacker) end
            S.blockAsserted = false
            resumeM1IfHeld(lp.Character)
        end
        resolveSwingResult("DAMAGE_TAKEN", attacker, victim, "M1")
    end)
    bind("M2Hit", function(attacker, victim)
        if victim == lp.Name then
            S.stats.fx_hit = S.stats.fx_hit + 1
            Log.step("SERVER FX M2Hit victim=" .. tostring(victim))
            correlate("HIT", "M2", attacker)
            if S.onDodgeVictimHit then S.onDodgeVictimHit(attacker) end
            S.blockAsserted = false
            resumeM1IfHeld(lp.Character)
        end
        resolveSwingResult("DAMAGE_TAKEN", attacker, victim, "M2")
    end)
    Log.step("CombatBroadcast listeners ok")
end

local function destroy()
    if not S.alive then return end
    S.alive = false
    cancelDelays()
    Log.step("destroy gen=" .. tostring(S.gen))
    emitEvent("TEARDOWN", { gen = S.gen, reason = "destroy" })
    Hud.destroy()
    for _, c in ipairs(S.conns) do pcall(function() c:Disconnect() end) end
    table.clear(S.conns)
    clearLocalCharConnections()
    local enemyChars = {}
    for ch in pairs(S.enemyCharConns) do
        enemyChars[#enemyChars + 1] = ch
    end
    for _, ch in ipairs(enemyChars) do
        clearEnemyCharConnections(ch)
    end
    table.clear(S.enemyPlayerChars)
    local transient = {}
    for c in pairs(S.transientConns) do
        transient[#transient + 1] = c
    end
    for _, c in ipairs(transient) do
        releaseTransient(c)
    end
    removeHooks()
    dodgeUv.resolved = false
    dodgeUv.fn = nil
    dodgeUv.failReason = nil
    dodgeUv.idx = { u5 = nil, u6 = nil, u7 = nil, u8 = nil, u4 = nil }
    if G[GKEY] == G.__GAKURAN_AUTOPARRY_EXPORT then G[GKEY] = nil end
end

G.__GAKURAN_AUTOPARRY_EXPORT = {
    destroy = destroy,
    enabled = function() return CONFIG.ENABLED end,
    gen = S.gen,
    stats = function() return S.stats end,
}
G[GKEY] = G.__GAKURAN_AUTOPARRY_EXPORT

-- ================= windup-predictive parry (all styles + parryable heavies) =================
-- Reactive-at-hitbox is too late for PerfectBlocking (gen7: even a BranchC block at
-- ChildAdded = DMG; ChildAdded ≈ hit landing, only ~19ms of lead < ping). Attacker chars
-- carry SERVER-SET, replicated attack-state attrs DURING the swing: CombatAttacking /
-- PendingM1 / PendingM2 / M1 / M2 (read-only client-side, 0180:11 / 0409). "Pending" = windup
-- = ~0.2-0.82s lead (style-dependent — slugger→muaythai→hakari all differ, 0567 tables).
-- We cover that windup with rate-safe Block.Activated taps (one per WINDUP_TICK) so one lands
-- inside the 0.125s perfect window before the hit, WHATEVER the style. Raw CRC.Fire Activated ==
-- same server message as Block.Block (0403/0575) but skips Branch-B "already blocking" no-op and
-- the u14 suppression gate. Covers parryable heavies (they send the M2 string → scanner accepts).
-- Style-AGNOSTIC: these attacker attrs are set by every combat style (server-side, replicated),
-- so any new/fast style is auto-covered without a style name list. CombatAttacking is the
-- umbrella; M1Hold catches hold/fast-M1 startup earliest. Re-dump for a new style's exact
-- M1HitboxDelay only to TUNE, not to detect.
local WINDUP_ATTRS = { "CombatAttacking", "M1Hold", "PendingM1", "PendingM2", "M1", "M2" }
-- gen9 fix: fire ONE Activated per WINDUP_TICK globally (not per-attacker). Must be ≥ server
-- 60ms Block.Activated min so every Activated is ACCEPTED, not rate-dropped. 0.07 < perfect
-- window 0.125 so an accepted tap still covers the window before each hit.
-- gen14 tried pinning this to the server floor exactly (0.06, = WINDUP_MIN_ACT) on the theory
-- that less slack = tighter average phase-alignment. MEASURED WORSE: perfect-rate dropped from
-- 31% (4/13 confirms @ 0.07) to 6% (1/16 confirms @ 0.06), with dt_since_tap outlier gaps up to
-- 0.69s appearing that never showed at 0.07. PreSimulation frame timing isn't perfectly even, and
-- pinning exactly to the server's own accept floor leaves no slack to absorb that jitter — some
-- ticks land close enough together that the server intermittently drops one, producing bigger
-- gaps than the deliberate 0.07 cadence ever had. Reverted. Do not re-tighten below 0.07 without
-- a controlled A/B — this constant is empirically sensitive, not a "smaller is safer" knob.
local WINDUP_TICK = 0.07
-- hard floor = server 60ms min (forced hit-imminent taps use this)
local WINDUP_MIN_ACT = 0.06
local WINDUP_GRACE_SEC = 0.32       -- keep ticking past attr-clear to cover the active hit frame
local WINDUP_RANGE = 24             -- windup starts before the lunge → wider than melee gate

local function attackerHasWindup(atkChar)
    for _, a in ipairs(WINDUP_ATTRS) do
        if atkChar:GetAttribute(a) == true then return true end
    end
    return false
end

-- Hitbox owner cache for forceNow. ChildAdded often fires BEFORE Owner/AttackName exist —
-- gen37 missed every live hitbox (forceNow=0, WINDUP_LEAD=0). Defer until values appear.
local hitboxOwnerCache = {} -- attackerName → { part = Instance, attack = string }

local function cacheHitboxPart(child)
    if not child or not child:IsA("BasePart") then return end
    local owner = child:FindFirstChild("Owner")
    local atkVal = child:FindFirstChild("AttackName")
    local function swingFromPart(part)
        local sid = part:GetAttribute("VictimSwingId")
        return typeof(sid) == "string" and sid ~= "" and sid or nil
    end
    if owner and owner:IsA("StringValue") and atkVal and atkVal:IsA("StringValue") then
        local attack = atkVal.Value
        if PARRY_ATTACKS[attack] then
            hitboxOwnerCache[owner.Value] = {
                part = child, attack = attack, swingId = swingFromPart(child),
            }
        end
        return
    end
    -- Values not ready yet — bounded poll; never yield a zero-delay busy loop.
    task.defer(function()
        local deadline = os.clock() + 0.2
        while child.Parent and os.clock() < deadline do
            local o = child:FindFirstChild("Owner")
            local a = child:FindFirstChild("AttackName")
            if o and o:IsA("StringValue") and a and a:IsA("StringValue") and o.Value ~= "" then
                local attack = a.Value
                if PARRY_ATTACKS[attack] then
                    hitboxOwnerCache[o.Value] = { part = child, attack = attack, swingId =
                        swingFromPart(child) }
                end
                return
            end
            task.wait(0.03)
        end
    end)
end

local function uncacheHitboxPart(child)
    if not child then return end
    for name, rec in pairs(hitboxOwnerCache) do
        if rec.part == child then
            hitboxOwnerCache[name] = nil
            return
        end
    end
end

local function attackerHasLiveHitbox(atkChar, style)
    local name = atkChar.Name
    local rec = hitboxOwnerCache[name]
    if rec and rec.part and rec.part.Parent then
        local attack = rec.attack
        if attack and PARRY_ATTACKS[attack] and not (attack == "M2" and styleDodgeM2(style)) then
            return true
        end
    elseif rec then
        hitboxOwnerCache[name] = nil
    end
    -- Cache can be cold while Owner/AttackName replicate. Throttle fallback per attacker
    -- so PreSimulation cannot repeatedly walk every hitbox in one frame burst.
    local folder = S.hitboxes
    if not folder then return false end
    local now = os.clock()
    if now - (S.hitboxFallbackAt[name] or 0) < 0.04 then return false end
    S.hitboxFallbackAt[name] = now
    S.perf.fallbackScans = S.perf.fallbackScans + 1
    for _, child in ipairs(folder:GetChildren()) do
        local owner = child:FindFirstChild("Owner")
        if owner and owner:IsA("StringValue") and owner.Value == name then
            local atkVal = child:FindFirstChild("AttackName")
            local attack = atkVal and atkVal:IsA("StringValue") and atkVal.Value
            if attack and PARRY_ATTACKS[attack] and not (attack == "M2" and styleDodgeM2(style))
                then
                hitboxOwnerCache[name] = { part = child, attack = attack,
                    swingId = (function()
                        local sid = child:GetAttribute("VictimSwingId")
                        return typeof(sid) == "string" and sid ~= "" and sid or nil
                    end)() }
                return true
            end
        end
    end
    return false
end

-- Exact victim-scanner equivalent, scoped to the requested owner + attack. Proximity alone
-- never qualifies: only the local character overlapping that attacker's live M1/M2 part does.
local function confirmedLocalOverlap(attackerName, attack, style)
    local ch = lp.Character
    local overlapParams = S.overlap
    if not ch or not overlapParams or not PARRY_ATTACKS[attack] then return false end
    if attack == "M2" and styleDodgeM2(style) then return false end
    overlapParams.FilterDescendantsInstances = { ch }
    local rec = hitboxOwnerCache[attackerName]
    local now = os.clock()
    if rec and rec.part and rec.part.Parent and rec.attack == attack then
        if now - (rec.overlapAt or 0) < 0.04 then
            return rec.overlap == true, rec.part
        end
        rec.overlapAt = now
        S.perf.overlapQueries = S.perf.overlapQueries + 1
        rec.overlap = #Workspace:GetPartBoundsInBox(rec.part.CFrame, rec.part.Size, overlapParams) >
            0
        return rec.overlap, rec.part
    end
    local folder = S.hitboxes
    if not folder then return false end
    if now - (S.hitboxFallbackAt[attackerName] or 0) < 0.04 then return false end
    S.hitboxFallbackAt[attackerName] = now
    S.perf.fallbackScans = S.perf.fallbackScans + 1
    for _, part in ipairs(folder:GetChildren()) do
        local owner = part:IsA("BasePart") and part:FindFirstChild("Owner")
        local attackName = part:IsA("BasePart") and part:FindFirstChild("AttackName")
        if owner and owner:IsA("StringValue") and owner.Value == attackerName
            and attackName and attackName:IsA("StringValue") and attackName.Value == attack then
            local sid = part:GetAttribute("VictimSwingId")
            hitboxOwnerCache[attackerName] = {
                part = part, attack = attack, overlapAt = now,
                swingId = typeof(sid) == "string" and sid ~= "" and sid or nil,
            }
            S.perf.overlapQueries = S.perf.overlapQueries + 1
            hitboxOwnerCache[attackerName].overlap =
                #Workspace:GetPartBoundsInBox(part.CFrame, part.Size, overlapParams) > 0
            return hitboxOwnerCache[attackerName].overlap, part
        end
    end
    return false
end

local function enemyInWindupRange(atkChar)
    local ch = lp.Character
    if not ch then return false end
    local hrp = ch:FindFirstChild("HumanoidRootPart")
    local ahrp = atkChar:FindFirstChild("HumanoidRootPart")
    if not hrp or not ahrp then return false end
    return (hrp.Position - ahrp.Position).Magnitude <= WINDUP_RANGE
end

local function windupAttrSnap(atkChar)
    local parts = {}
    for _, a in ipairs(WINDUP_ATTRS) do
        parts[#parts + 1] = a .. "=" .. tostring(atkChar:GetAttribute(a))
    end
    return table.concat(parts, " ")
end

-- one fresh Activated, no Blocking/anim state — pure timing signal to the server
-- Are WE mid-attack? Autoparry must yield to our own offense — firing Block.Activated while we
-- hold LMB blocks our M1 (that was the "LMB won't combat" bug).
local function weAreAttacking(ch)
    return ch:GetAttribute("CombatAttacking") == true
        or ch:GetAttribute("M1Hold") == true
        or ch:GetAttribute("M1") == true
        or ch:GetAttribute("PendingM1") == true
        or ch:GetAttribute("M2") == true
        or ch:GetAttribute("PendingM2") == true
end

-- release the block we asserted (parry = tap, not a held block) so M1 input is freed between
-- parries and no block state lingers after combat.
local function sendBlockDeactivated()
    if not S.blockAsserted then return end
    S.blockAsserted = false
    pcall(function() if CRC and CRC.Fire then CRC.Fire("Block", "Deactivated") end end)
    local ch = lp.Character
    if ch then pcall(function() ch:SetAttribute("Blocking", nil) end) end
    resumeM1IfHeld(ch)
end

-- ================= gen53 defense arbiter + M2 dodge =================
-- Functions hang on S to avoid burning main-chunk locals (200 cap).

S.defenseDecide = function(attackKind, style)
    attackKind = (attackKind == "M2") and "M2" or "M1"
    if attackKind == "M1" then
        return "parry" -- DODGE_M1 hard-off
    end
    if not CONFIG.AUTO_DODGE then
        if styleDodgeM2(style) then return "none" end
        return "parry"
    end
    local grab = styleDodgeM2(style)
    if grab then
        if CONFIG.DODGE_GRAB_M2 then return "dodge" end
        return "none"
    end
    if CONFIG.DODGE_M2 then return "dodge" end
    return "parry"
end

S.cancelPendingParry = function(atkChar)
    if atkChar and S.windupActive[atkChar] then
        local rec = S.windupActive[atkChar]
        S.bumpEpoch(rec, "dodge_cancel_parry", atkChar.Name, rec.attackKind or "M2", rec.comboIndex
            or 1, nil, true)
        rec.defenseMode = "dodge"
        rec.edgeScheduled = false
    end
    if S.blockAsserted then
        sendBlockDeactivated()
        Log.step("DODGE_CANCEL_PARRY blockAsserted cleared")
    end
end

S.logDodgeSkip = function(gate, atkName, attack, style, dist, fov)
    local d = (typeof(dist) == "number") and dist or -1
    local fovStr = (typeof(fov) == "number") and string.format(" fov=%.2f", fov) or ""
    Log.step(string.format(
        "DODGE_SKIP gate=%s from=%s attack=%s style=%s dist=%.1f%s",
        tostring(gate), tostring(atkName), tostring(attack), tostring(style), d, fovStr
    ))
    local fields = {
        gen = S.gen, gate = tostring(gate), attacker = tostring(atkName),
        attack = tostring(attack), style = tostring(style), dist = d,
    }
    if typeof(fov) == "number" then fields.fov = fov end
    emitEvent("DODGE_SKIP", fields)
    S.stats.dodge_skip = (S.stats.dodge_skip or 0) + 1
    local by = S.stats.dodge_skip_by_gate
    by[gate] = (by[gate] or 0) + 1
end

S.inFrontFov = function(atkChar)
    if not CONFIG.DODGE_REQUIRE_FACING then return true, 1 end
    local ch = lp.Character
    local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
    local ahrp = atkChar and atkChar:FindFirstChild("HumanoidRootPart")
    if not hrp or not ahrp then return false, -2 end
    local look = hrp.CFrame.LookVector
    local flatLook = Vector3.new(look.X, 0, look.Z)
    if flatLook.Magnitude < 1e-4 then return false, -2 end
    flatLook = flatLook.Unit
    local to = ahrp.Position - hrp.Position
    local flatTo = Vector3.new(to.X, 0, to.Z)
    local dot = (flatTo.Magnitude < 1e-4) and 1 or flatLook:Dot(flatTo.Unit)
    local need = math.cos(math.rad(CONFIG.DODGE_FOV_DEG * 0.5))
    return dot >= need, dot
end

S.attemptDodge = function(atkChar, attack, style, epoch, grabM2, reason)
    S.stats.dodge_attempts = (S.stats.dodge_attempts or 0) + 1
    local atkName = atkChar and atkChar.Name or "?"
    if stale() then return end
    if not CONFIG.ENABLED or not CONFIG.AUTO_DODGE then
        S.logDodgeSkip("disabled", atkName, attack, style); return
    end
    if attack == "M1" then
        S.logDodgeSkip("policy_m1_off", atkName, attack, style); return
    end
    if attack == "M2" then
        if grabM2 then
            if not CONFIG.DODGE_GRAB_M2 then S.logDodgeSkip("policy_m2_off", atkName, attack, style)
                ; return end
        elseif not CONFIG.DODGE_M2 then
            S.logDodgeSkip("policy_m2_off", atkName, attack, style); return
        end
    end

    local rec = S.windupActive[atkChar]
    if not rec then S.logDodgeSkip("windup_gone", atkName, attack, style); return end
    if rec.epoch ~= epoch then S.logDodgeSkip("epoch_expired", atkName, attack, style); return end

    local ch = lp.Character
    if not ch then S.logDodgeSkip("no_char", atkName, attack, style); return end
    local hrp = ch:FindFirstChild("HumanoidRootPart")
    local ahrp = atkChar:FindFirstChild("HumanoidRootPart")
    local dist = (hrp and ahrp) and (hrp.Position - ahrp.Position).Magnitude or nil
    if not hrp or not ahrp or dist == nil or dist > CONFIG.DODGE_MAX_RANGE then
        S.logDodgeSkip("far", atkName, attack, style, dist); return
    end
    local okFov, fovDot = S.inFrontFov(atkChar)
    if not okFov then
        S.logDodgeSkip("off_fov", atkName, attack, style, dist, fovDot); return
    end
    local now = os.clock()
    if now - (S.lastDodgeAt or 0) < CONFIG.DODGE_MIN_INTERVAL then
        S.logDodgeSkip("rate", atkName, attack, style, dist, fovDot); return
    end
    if not EvasiveMod or type(EvasiveMod.Evasive) ~= "function" then
        S.logDodgeSkip("no_module", atkName, attack, style, dist, fovDot); return
    end
    if ch:GetAttribute("Greenzone") == true then
        S.logDodgeSkip("greenzone", atkName, attack, style, dist, fovDot); return
    end
    if ch:GetAttribute("Ragdoll") == true or ch:GetAttribute("Dead") == true then
        S.logDodgeSkip("ragdoll", atkName, attack, style, dist, fovDot); return
    end
    local dashActive = false
    pcall(function() dashActive = EvasiveMod.IsDashActive and EvasiveMod.IsDashActive() == true end)
    if dashActive then S.logDodgeSkip("dash_active", atkName, attack, style, dist, fovDot); return
        end

    if ch:GetAttribute("CombatAttacking") == true
        or ch:GetAttribute("M1") == true
        or ch:GetAttribute("PendingM1") == true then
        pcall(function()
            ch:SetAttribute("CombatAttacking", nil)
            ch:SetAttribute("M1", nil)
            ch:SetAttribute("PendingM1", nil)
        end)
        Log.step(string.format("DODGE_CLEAR_ATTACKING from=%s attack=%s dist=%.1f", atkName, attack,
            dist))
        if ch:GetAttribute("CombatAttacking") == true then
            S.logDodgeSkip("combat_attacking", atkName, attack, style, dist, fovDot); return
        end
    end
    if ch:GetAttribute("RpCombatLocked") == true then
        S.logDodgeSkip("combat_locked_zone", atkName, attack, style, dist, fovDot); return
    end
    if ch:GetAttribute("Downed") == true then
        S.logDodgeSkip("downed", atkName, attack, style, dist, fovDot); return
    end

    -- Only clear Blocking after we cancelled our own parry for this dodge swing.
    S.cancelPendingParry(atkChar)
    if ch:GetAttribute("Blocking") == true then
        pcall(function() ch:SetAttribute("Blocking", nil) end)
        Log.step("DODGE_CLEAR_BLOCKING from=" .. atkName .. " attack=" .. tostring(attack))
        if ch:GetAttribute("Blocking") == true then
            S.logDodgeSkip("blocking", atkName, attack, style, dist, fovDot); return
        end
    end

    local grant = ch:GetAttribute("OutnumberedEvasiveGrant") == true
    local iframesBefore = ch:GetAttribute("IFRAMES") == true
    local sendOk = pcall(function() EvasiveMod.Evasive() end)
    if not sendOk then
        S.logDodgeSkip("send_failed", atkName, attack, style, dist, fovDot); return
    end

    S.lastDodgeAt = now
    S.stats.dodge_accept = (S.stats.dodge_accept or 0) + 1
    S.stats.dodge_m2 = (S.stats.dodge_m2 or 0) + 1
    if grabM2 then S.stats.dodge_grab_m2 = (S.stats.dodge_grab_m2 or 0) + 1 end
    S.defenseLock = { attacker = atkName, mode = "dodge", untilClock = now + (S.iframeConfirmWindow
        or 0.4) }

    S.dodgeSeq = (S.dodgeSeq or 0) + 1
    local id = S.dodgeSeq
    S.pendingDodges[id] = {
        id = id, attacker = atkName, attack = attack, style = style,
        sentAt = now, iframeConfirmed = false, hitThrough = false,
    }
    local acceptReason = reason or "windup"
    Log.step(string.format(
        "DODGE_ACCEPT id=%d from=%s attack=%s style=%s reason=%s epoch=%d " ..
            "grabM2=%s grant=%s iframes_before=%s dist=%.1f fov=%.2f clock=%.3f",
        id, atkName, attack, tostring(style), acceptReason, epoch, tostring(grabM2 == true),
        tostring(grant), tostring(iframesBefore), dist, fovDot or -1, now
    ))
    emitEvent("DODGE_ACCEPT", {
        gen = S.gen, id = id, attacker = atkName, attack = attack, style = tostring(style),
        reason = acceptReason, epoch = epoch, grabM2 = grabM2 == true,
        grant = grant, iframes_before = iframesBefore, dist = dist, fov = fovDot, clock = now,
    })
    setLastResult(string.format("DODGE %s %s", attack, atkName), "dodge")

    trackDelay(S.dodgeOutcomeWindow or 0.45, function()
        local dodge = S.pendingDodges[id]
        if not dodge or dodge.hitThrough then return end
        if dodge.iframeConfirmed then
            local dt = os.clock() - dodge.sentAt
            Log.step(string.format("OUTCOME_CLEAN id=%d dt=%.3f", id, dt))
            emitEvent("OUTCOME_CLEAN", { gen = S.gen, id = id, dt = dt })
        end
    end)
end

S.scheduleDodge = function(atkChar, rec, attackKind, style, epoch)
    local grabM2 = attackKind == "M2" and styleDodgeM2(style)
    local expected = resolveStyleDelay(style, attackKind, rec.comboIndex or 1) or 0.30
    local ch = lp.Character
    local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
    local ahrp = atkChar:FindFirstChild("HumanoidRootPart")
    local dist = (hrp and ahrp) and (hrp.Position - ahrp.Position).Magnitude or nil
    local lead = CONFIG.DODGE_IFRAME_LEAD
    local fireAt = math.max(expected - lead, 0.01)
    Log.step(string.format(
        "DODGE_SCHED from=%s style=%s attack=%s expected=%.3f fire_at=%.3f " ..
            "lead=%.3f dist=%.1f epoch=%d",
        atkChar.Name, tostring(style), attackKind, expected, fireAt, lead,
        (typeof(dist) == "number") and dist or -1, epoch
    ))
    emitEvent("DODGE_SCHED", {
        gen = S.gen, attacker = atkChar.Name, style = tostring(style), attack = attackKind,
        expected = expected, fire_at = fireAt, lead = lead,
        dist = (typeof(dist) == "number") and dist or -1,
        epoch = epoch, grabM2 = grabM2 == true,
    })
    trackDelay(fireAt, function()
        S.attemptDodge(atkChar, attackKind, style, epoch, grabM2, "windup")
    end, epoch, atkChar)
end

S.tryM2HitboxEmergency = function(atkChar, attackKind, style)
    if not CONFIG.AUTO_DODGE or not CONFIG.ENABLED then return end
    if attackKind ~= "M2" then return end -- never emergency-dodge M1
    if S.defenseDecide(attackKind, style) ~= "dodge" then return end
    local ch = lp.Character
    if not ch or not atkChar then return end
    local hrp = ch:FindFirstChild("HumanoidRootPart")
    local ahrp = atkChar:FindFirstChild("HumanoidRootPart")
    if not hrp or not ahrp then return end
    local dist = (hrp.Position - ahrp.Position).Magnitude
    if dist > CONFIG.DODGE_MAX_RANGE then return end
    local okFov = S.inFrontFov(atkChar)
    if not okFov then return end
    local now = os.clock()
    local atkName = atkChar.Name
    for _, dodge in pairs(S.pendingDodges) do
        if dodge.attacker == atkName and (now - dodge.sentAt) < 0.15 then return end
    end
    if now - (S.lastDodgeAt or 0) < CONFIG.DODGE_MIN_INTERVAL then return end
    local dashActive = false
    pcall(function()
        dashActive = EvasiveMod and EvasiveMod.IsDashActive and EvasiveMod.IsDashActive() == true
    end)
    if dashActive then return end

    local rec = S.windupActive[atkChar]
    local fireEpoch
    if not rec then
        rec = {
            start = now, expire = now + WINDUP_GRACE_SEC, style = style,
            comboIndex = 1, epoch = nil, attackKind = attackKind, defenseMode = "dodge",
        }
        S.windupActive[atkChar] = rec
        fireEpoch = S.bumpEpoch(rec, "hitbox_emergency", atkName, attackKind, 1, nil, true)
    elseif rec.epoch then
        fireEpoch = rec.epoch
        -- cancel pending parry first so a failed dodge can't leave dodge mode stuck without fire
        if rec.defenseMode ~= "dodge" then
            S.cancelPendingParry(atkChar)
        end
        rec.defenseMode = "dodge"
    else
        rec.defenseMode = "dodge"
        fireEpoch = S.bumpEpoch(rec, "hitbox_emergency", atkName, attackKind, rec.comboIndex or 1,
            nil, true)
    end
    Log.step(string.format("HITBOX_EMERGENCY dist=%.1f from=%s attack=%s epoch=%d", dist, atkName,
        attackKind, fireEpoch))
    S.attemptDodge(atkChar, attackKind, style, fireEpoch, styleDodgeM2(style), "hitbox_emergency")
end

S.onDodgeIframes = function(ch)
    if stale() or not CONFIG.ENABLED then return end
    if not ch or ch:GetAttribute("IFRAMES") ~= true then return end
    local now = os.clock()
    local bestId, bestDt = nil, math.huge
    local win = S.iframeConfirmWindow or 0.4
    for id, dodge in pairs(S.pendingDodges) do
        if not dodge.iframeConfirmed then
            local dt = now - dodge.sentAt
            if dt >= 0 and dt <= win and dt < bestDt then
                bestDt, bestId = dt, id
            end
        end
    end
    if bestId then
        S.pendingDodges[bestId].iframeConfirmed = true
        S.stats.dodge_iframe_ok = (S.stats.dodge_iframe_ok or 0) + 1
        Log.step(string.format("IFRAME_CONFIRM id=%d dt_since_dodge=%.3f", bestId, bestDt))
        emitEvent("IFRAME_CONFIRM", { gen = S.gen, id = bestId, dt_since_dodge = bestDt })
    end
end

S.onDodgeVictimHit = function(attacker)
    if stale() or not CONFIG.ENABLED then return end
    local now = os.clock()
    local bestId, bestDt = nil, math.huge
    local win = S.dodgeOutcomeWindow or 0.45
    for id, dodge in pairs(S.pendingDodges) do
        if not dodge.hitThrough then
            local dt = now - dodge.sentAt
            if dt >= 0 and dt <= win and dt < bestDt then
                bestDt, bestId = dt, id
            end
        end
    end
    if bestId then
        S.pendingDodges[bestId].hitThrough = true
        S.stats.dodge_hit_through = (S.stats.dodge_hit_through or 0) + 1
        Log.step(string.format("OUTCOME_HIT_THROUGH id=%d from=%s dt_since_dodge=%.3f", bestId,
            tostring(attacker), bestDt))
        emitEvent("OUTCOME_HIT_THROUGH", { gen = S.gen, id = bestId, attacker = tostring(attacker),
            dt_since_dodge = bestDt })
    else
        Log.step(string.format("OUTCOME_HIT_NO_DODGE id=none from=%s", tostring(attacker)))
        emitEvent("OUTCOME_HIT_NO_DODGE", { gen = S.gen, id = "none", attacker = tostring(attacker),
            dt_since_dodge = -1 })
    end
end

-- gen38: stun gate softened. Skip ONLY when locked without ParryBuffered (Activated useless).
-- Always CRC.Fire (gen36 path that landed PERECTs). Do NOT use Block.Block as send proof —
-- gen37 marked sent=true on silent u14/PerfectBlocking no-ops → only 2 taps / fight.
local function isCombatLocked(ch)
    return ch
        and (ch:GetAttribute("Stunned") == true or ch:GetAttribute("CantAnything") == true)
end

S.enemyHitLandsFirst = function(atkName, style, meta)
    meta = type(meta) == "table" and meta or {}
    if meta.overlap == true then return true, "overlap" end
    local ch = lp.Character
    local attack = tostring(meta.attack or "M1")
    local combo = tonumber(meta.combo) or 1
    local plr = Players:FindFirstChild(atkName)
    local atkChar = plr and plr.Character or Workspace:FindFirstChild(atkName)
    if atkChar and attackerHasLiveHitbox(atkChar, style) then
        return true, "enemy_hitbox"
    end
    if ch then
        local holdOnly = ch:GetAttribute("M1Hold") == true
            and ch:GetAttribute("CombatAttacking") ~= true
            and ch:GetAttribute("M1") ~= true
            and ch:GetAttribute("PendingM1") ~= true
            and ch:GetAttribute("M2") ~= true
            and ch:GetAttribute("PendingM2") ~= true
        if holdOnly then return true, "hold_only" end
    end
    local weLive = false
    local folder = S.hitboxes
    if folder and ch then
        local myName = lp.Name
        for _, child in ipairs(folder:GetChildren()) do
            local owner = child:FindFirstChild("Owner")
            local atkVal = child:FindFirstChild("AttackName")
            if owner and owner:IsA("StringValue") and owner.Value == myName then
                local atk = atkVal and atkVal:IsA("StringValue") and atkVal.Value
                if atk == "M1" or atk == "M2" then
                    weLive = true
                    break
                end
            end
        end
    end
    if weLive and not (atkChar and attackerHasLiveHitbox(atkChar, style)) then
        local r = tostring(meta.reason or "")
        if r == "precision" or r == "overlapEdge" or r == "bufferRiseOverlap" then
            return true, "prefer_parry"
        end
        return false, "our_hitbox_first"
    end
    local enemyEta = nil
    if atkChar then
        local rec = S.windupActive[atkChar]
        if rec then
            local delay = resolveStyleDelay(style, attack, combo)
                or resolveStyleDelay(style, attack, rec.comboIndex or 1) or 0.32
            enemyEta = rec.start + delay - os.clock()
            if enemyEta <= 0.12 then return true, "enemy_eta" end
        end
        -- Enemy still in windup, our hitbox not out → prefer parry (stay defensive in race).
        if S.windupActive[atkChar] and not weLive then
            return true, "prefer_parry"
        end
    end
    return false, "ours_first"
end

local function logTapSkip(gate, atkName, style, meta)
    meta = type(meta) == "table" and meta or {}
    local ch = lp.Character
    Log.step(string.format(
        "TAP_SKIP gate=%s from=%s attack=%s style=%s reason=%s overlap=%s " ..
            "M1Hold=%s ParryBuffered=%s lock=%s epoch=%s edge=%s clock=%.3f",
        tostring(gate), tostring(atkName), tostring(meta.attack or "M1"), tostring(style),
        tostring(meta.reason or "?"), tostring(meta.overlap == true),
        tostring(ch and ch:GetAttribute("M1Hold")), tostring(ch and ch:GetAttribute("ParryBuffered")
            ),
        tostring(isCombatLocked(ch)), tostring(meta.epoch or "?"), tostring(meta.edgeKind or "?"),
        os.clock()
    ))
    emitEvent("TAP_SKIP", { gen = S.gen, gate = tostring(gate), attacker = tostring(atkName),
        attack = tostring(meta.attack or "M1"), style = tostring(style), reason = tostring(meta.
            reason or "?"),
        overlap = meta.overlap == true, m1hold = ch and ch:GetAttribute("M1Hold") == true,
        parryBuffered = ch and ch:GetAttribute("ParryBuffered") == true, locked = isCombatLocked(ch)
            == true,
        epoch = meta.epoch or 0, edgeKind = tostring(meta.edgeKind or "?") })
end

local function fireActivatedRaw(atkName, dtStart, style, bypassAttacking, meta)
    meta = type(meta) == "table" and meta or {}
    local ch = lp.Character
    if not ch then logTapSkip("no_char", atkName, style, meta); return false end
    local scanOk, scanWhy = canScan(ch)
    if not scanOk then logTapSkip("scan_" .. tostring(scanWhy), atkName, style, meta); return false
        end
    if ch:GetAttribute("Greenzone") == true then logTapSkip("greenzone", atkName, style, meta);
        return false end
    if ch:GetAttribute("RpCombatLocked") == true then logTapSkip("combat_locked_zone", atkName,
        style, meta); return false end
    if not bypassAttacking and weAreAttacking(ch) then
        local tradeOk, tradeWhy = S.enemyHitLandsFirst(atkName, style, meta)
        if not tradeOk then
            logTapSkip("attacking_ours_first", atkName, style, meta)
            return false
        end
        meta.tradeParry = tradeWhy
        Log.step(string.format("TRADE_PARRY why=%s from=%s attack=%s style=%s",
            tostring(tradeWhy), tostring(atkName), tostring(meta.attack or "M1"), tostring(style)))
    end
    local now = os.clock()
    local defMode = S.defenseDecide(meta.attack or "M1", style)
    if defMode == "dodge" then
        logTapSkip("defense_dodge", atkName, style, meta); return false
    end
    if defMode == "none" or (meta.attack == "M2" and styleDodgeM2(style)) then
        logTapSkip("unparryable_dodge_m2", atkName, style, meta); return false
    end
    local lock = S.defenseLock
    if lock and lock.mode == "dodge" and now < (lock.untilClock or 0) then
        -- only suppress Activated for the M2 we already dodged — never block follow-up M1 parry
        if tostring(atkName) == tostring(lock.attacker) and tostring(meta.attack or "M1") == "M2"
            then
            logTapSkip("defense_lock_dodge", atkName, style, meta); return false
        end
    end
    if now - S.lastRawTapAt < WINDUP_MIN_ACT then logTapSkip("global_rate", atkName, style, meta);
        return false end
    -- gen39: brief pause after normal BLOCK FX so we don't re-assert and re-chip stamina
    if not bypassAttacking and typeof(S.blockAbortUntil) == "number" and now < S.blockAbortUntil
        then
        logTapSkip("block_abort", atkName, style, meta); return false
    end

    local locked = isCombatLocked(ch)
    if locked then
        if ch:GetAttribute("ParryWindowDisabled") == true or ch:GetAttribute("GuardBroken") == true
            then
            logTapSkip("unparryable_or_guardbroken", atkName, style, meta); return false
        end
        if ch:GetAttribute("ParryBuffered") ~= true then
            local t = os.clock()
            if t - (S.lastStunSkipLog or 0) > 0.4 then
                S.lastStunSkipLog = t
                Log.step(string.format(
                    "STUN_SKIP from=%s style=%s Stunned=%s CantAnything=%s ParryBuffered=%s",
                    tostring(atkName), tostring(style),
                    tostring(ch:GetAttribute("Stunned")),
                    tostring(ch:GetAttribute("CantAnything")),
                    tostring(ch:GetAttribute("ParryBuffered"))
                ))
            end
            logTapSkip("stunned_unbuffered", atkName, style, meta); return false
        end
    end

    clearBlockCooldown(ch)
    local sent = false
    local tapServerTime = nil
    pcall(function()
        if CRC and CRC.Fire then
            tapServerTime = Workspace:GetServerTimeNow()
            CRC.Fire("Block", "Activated", tapServerTime)
            sent = true
        end
    end)
    if sent then
        local attack = tostring(meta.attack or "M1")
        local overlap = meta.overlap == true
        S.lastTapAt = now
        S.lastRawTapAt = now
        S.lastTapServerTime = tapServerTime
        S.lastParry = now
        S.blockAsserted = true
        S.lastTapAttacker = atkName or "?"
        S.lastTapStyle = style or "?"
        S.lastTapDtStart = dtStart or 0
        S.lastTapReason = tostring(meta.reason or (bypassAttacking and "forceNow" or "spray"))
        S.lastRawTapReason = S.lastTapReason
        S.lastTapComboIndex = tonumber(meta.combo) or 0
        S.lastTapPredicted = tonumber(meta.predicted) or -1
        S.lastTapForceNow = bypassAttacking == true
        S.tapSeq = S.tapSeq + 1
        local tap = {
            id = S.tapSeq, attacker = tostring(atkName or "?"), attack = attack, style = tostring(
                style or "?"),
            reason = S.lastTapReason, combo = S.lastTapComboIndex, predicted = S.lastTapPredicted,
            sentLocal = now, sentServer = tapServerTime, overlap = overlap, source = tostring(meta.
                source or "windup"),
            m1hold = ch:GetAttribute("M1Hold") == true, parryBuffered = ch:GetAttribute(
                "ParryBuffered") == true,
            locked = locked == true, consumed = false,
            epoch = meta.epoch or 0, swingId = meta.swingId, edgeKind = meta.edgeKind or "?",
            guardBroken = ch:GetAttribute("GuardBroken") == true,
            parryWindowDisabled = ch:GetAttribute("ParryWindowDisabled") == true,
            cantAnything = ch:GetAttribute("CantAnything") == true,
            perfectBlocking = ch:GetAttribute("PerfectBlocking") == true,
            blockCooldown = ch:GetAttribute("BlockCooldown") == true,
            tradeParry = meta.tradeParry,
        }
        local key = tapKey(tap.attacker, tap.attack)
        S.tapsByKey[key] = S.tapsByKey[key] or {}
        table.insert(S.tapsByKey[key], tap)
        pruneTapResults(now)
        S.stats.windup_taps = S.stats.windup_taps + 1
        S.stats.opener_taps = S.stats.opener_taps + 1
        if S.lastTapReason == "precision" then
            S.stats.tap_precision = (S.stats.tap_precision or 0) + 1
        elseif S.lastTapReason == "forceResolve" or S.lastTapReason == "forceRefresh" or S.
            lastTapReason == "forceNow" then
            S.stats.tap_force = (S.stats.tap_force or 0) + 1
        elseif S.lastTapReason == "hitboxLive" then
            S.stats.tap_hitboxLive = (S.stats.tap_hitboxLive or 0) + 1
        elseif S.lastTapReason == "overlapEdge" then
            S.stats.overlap_held_m1_taps = S.stats.overlap_held_m1_taps + 1
        elseif S.lastTapReason == "bufferRiseOverlap" then
            S.stats.overlap_buffer_rise_taps = S.stats.overlap_buffer_rise_taps + 1
        end
        Log.step(string.format(
            "TAP_ACCEPT id=%d from=%s attack=%s style=%s reason=%s " ..
                "tradeParry=%s overlap=%s M1Hold=%s ParryBuffered=%s lock=%s " ..
                "epoch=%d swing=%s edge=%s combo=%s predicted=%.3f GB=%s PWD=%s " ..
                "CA=%s PB=%s BC=%s clock=%.3f server=%s",
            tap.id, tap.attacker, tap.attack, tap.style, tap.reason, tostring(tap.tradeParry or ""),
            tostring(tap.overlap), tostring(tap.m1hold),
            tostring(tap.parryBuffered), tostring(tap.locked), tap.epoch, tostring(tap.swingId or
                "?"),
            tap.edgeKind, tostring(tap.combo), tap.predicted,
            tostring(tap.guardBroken), tostring(tap.parryWindowDisabled), tostring(tap.cantAnything)
                ,
            tostring(tap.perfectBlocking), tostring(tap.blockCooldown),
            tap.sentLocal, tostring(tap.sentServer)
        ))
        emitEvent("TAP_ACCEPT", { gen = S.gen, id = tap.id, attacker = tap.attacker, attack = tap.
            attack,
            style = tap.style, reason = tap.reason, tradeParry = tap.tradeParry, overlap = tap.
                overlap, m1hold = tap.m1hold,
            parryBuffered = tap.parryBuffered, locked = tap.locked, clock = tap.sentLocal, server =
                tap.sentServer,
            source = tap.source, epoch = tap.epoch, swingId = tostring(tap.swingId or ""), edgeKind
                = tap.edgeKind,
            combo = tap.combo, predicted = tap.predicted,
            guardBroken = tap.guardBroken, parryWindowDisabled = tap.parryWindowDisabled,
            cantAnything = tap.cantAnything, perfectBlocking = tap.perfectBlocking, blockCooldown =
                tap.blockCooldown })
        if CONFIG.LOG_TAPS then
            Log.step(string.format(
                "WINDUP_TAP from=%s style=%s dt_start=%.3f n=%d reason=%s " ..
                    "combo=%s predicted=%.3f force=%s locked=%s %s",
                tostring(atkName), tostring(style or "?"), dtStart or 0, S.stats.windup_taps,
                S.lastTapReason, tostring(S.lastTapComboIndex), S.lastTapPredicted,
                tostring(S.lastTapForceNow), tostring(locked), expPathTag()
            ))
        end
        -- gen51: do NOT resume M1 or clear Blocking inside Perfect window — OnM1Activated
        -- cancels PerfectBlocking mid-resolve. Resume only after FX/doUnblock/sendBlockDeactivated.
        -- Local Blocking clear after PERFECT_WINDOW so pump can re-enter; remote Deactivated still
        -- FX-only.
        trackDelay(PERFECT_WINDOW, function()
            local ch2 = lp.Character
            if ch2 then pcall(function() ch2:SetAttribute("Blocking", nil) end) end
            -- only Hold("Start") restart here if needed — NOT OnM1Activated while blockAsserted
            if ch2 and S.blockAsserted ~= true then
                resumeM1IfHeld(ch2)
            end
        end)
    else
        logTapSkip("send_failed", atkName, style, meta)
    end
    return sent
end

local function wireParryBufferedWatch(ch)
    if not ch then return end
    local wasBuffered = ch:GetAttribute("ParryBuffered") == true
    trackLocalChar(ch:GetAttributeChangedSignal("ParryBuffered"):Connect(function()
        if stale() then return end
        local buffered = ch:GetAttribute("ParryBuffered") == true
        local rose = buffered and not wasBuffered
        wasBuffered = buffered
        if not rose or not CONFIG.ENABLED then return end
        local folder = S.hitboxes
        if not folder then return end
        for _, part in ipairs(folder:GetChildren()) do
            if part:IsA("BasePart") then
                local owner = part:FindFirstChild("Owner")
                local attackName = part:FindFirstChild("AttackName")
                local attacker = owner and owner:IsA("StringValue") and owner.Value
                local attack = attackName and attackName:IsA("StringValue") and attackName.Value
                if attacker and attack and PARRY_ATTACKS[attack] then
                    local plr = Players:FindFirstChild(attacker)
                    local atkChar = plr and plr.Character or Workspace:FindFirstChild(attacker)
                    local style = atkChar and styleOf(atkChar) or "?"
                    if confirmedLocalOverlap(attacker, attack, style) then
                        fireActivatedRaw(attacker, 0, style, true, {
                            reason = "bufferRiseOverlap", attack = attack, overlap = true, source =
                                "buffer_rise",
                        })
                        return
                    end
                end
            end
        end
    end))
end

-- Register an attacker as winding up. A SINGLE global ticker (windupTick) fires the Activateds
-- so total rate stays under the server 60ms Block.Activated minimum — gen9 proved N concurrent
-- per-attacker bursts flooded that limit and the server DROPPED in-window taps → HIT.
local PERFECT_LEAD_BIAS = 0.035 -- unused legacy; gen40 uses perfectLeadFor(style)

S.fireStylePrecisionTap = function(ctx)
    local atkChar = ctx.atkChar
    local rec = ctx.rec
    if not CONFIG.ENABLED then return end
    if not S.windupActive[atkChar] then return end
    if CONFIG.DIAGNOSTICS then
        Log.step(string.format(
            "STYLE_PRECISION_TAP from=%s style=%s hit=%d " ..
                "expected_delay=%.3f fire_at=%.3f lead=%.3f mode=%s %s",
            atkChar.Name, rec.style, ctx.comboIndex, ctx.expectedDelay, ctx.fireAt, ctx.lead, ctx.
                schedMode, expPathTag()
        ))
    else
        S.perf.diagSuppressed = S.perf.diagSuppressed + 1
    end
    fireActivatedRaw(atkChar.Name, ctx.fireAt, rec.style, false, {
        reason = "precision", combo = ctx.comboIndex, predicted = ctx.expectedDelay,
        attack = ctx.attackKind, source = "precision",
        epoch = ctx.epoch or rec.epoch or 0, edgeKind = ctx.edgeKind or "precision",
        swingId = ctx.swingId,
    })
end

S.scheduleStylePrecisionTap = function(atkChar, rec, attackKind, comboIndex, baseTime, edgeKind)
    local lead = perfectLeadFor(rec.style)
    local expectedDelay = nil
    local schedMode = "legacy"
    local slot = comboSlot(comboIndex)
    local gapUsed = nil

    -- PATH2: combo≥2 fire from inter-hitbox gap EMA (anchor = hitbox edge = baseTime)
    if CONFIG.PATH2_GAP_EMA and (tonumber(comboIndex) or 1) >= 2 then
        local gapEma = select(1, gapEmaFor(rec.style, comboIndex))
        if gapEma then
            expectedDelay = gapEma
            gapUsed = gapEma
            schedMode = "gap_ema"
        else
            -- cold start: fall back to styleDelay until first GAP_ADAPT for this slot
            expectedDelay = resolveStyleDelay(rec.style, attackKind, comboIndex)
            schedMode = "gap_cold_fallback"
        end
    else
        expectedDelay = resolveStyleDelay(rec.style, attackKind, comboIndex)
        schedMode = "legacy"
    end

    if not expectedDelay then
        rec.nextExpectedAt = nil
        Log.step(string.format(
            "STYLE_PRECISION_SKIP from=%s style=%s hit=%d reason=unknown_style %s",
            atkChar.Name, tostring(rec.style), comboIndex, expPathTag()
        ))
        return
    end
    local fireAt = math.max(0, expectedDelay - lead)
    rec.nextExpectedAt = baseTime + fireAt
    if schedMode == "gap_ema" or schedMode == "gap_cold_fallback" then
        S.stats.sched_gap = (S.stats.sched_gap or 0) + 1
    else
        S.stats.sched_legacy = (S.stats.sched_legacy or 0) + 1
    end
    if CONFIG.DIAGNOSTICS then
        Log.step(string.format(
            "PRECISION_SCHED [%s] from=%s style=%s hit=%d slot=%d " ..
                "expected=%.3f fire_at=%.3f lead=%.3f gapEma=%s latency=%.3f %s",
            schedMode, atkChar.Name, tostring(rec.style), comboIndex, slot,
            expectedDelay, fireAt, lead,
            gapUsed and string.format("%.3f", gapUsed) or "nil",
            latencyFor(rec.style), expPathTag()
        ))
    else
        S.perf.diagSuppressed = S.perf.diagSuppressed + 1
    end
    emitEvent("PRECISION_SCHED", {
        gen = S.gen, mode = schedMode, attacker = atkChar.Name, style = tostring(rec.style),
        hit = comboIndex, slot = slot, expected = expectedDelay, fire_at = fireAt, lead = lead,
        gapEma = gapUsed or -1, path1 = CONFIG.PATH1_PRECISION_ONLY, path2 = CONFIG.PATH2_GAP_EMA,
        epoch = rec.epoch or 0, edge_kind = edgeKind or "precision",
        swingId = tostring((hitboxOwnerCache[atkChar.Name] or {}).swingId or ""),
    })
    local cached = hitboxOwnerCache[atkChar.Name]
    local ctx = {
        atkChar = atkChar, rec = rec, attackKind = attackKind, comboIndex = comboIndex,
        expectedDelay = expectedDelay, fireAt = fireAt, lead = lead, schedMode = schedMode,
        epoch = rec.epoch, edgeKind = edgeKind or "precision",
        swingId = cached and cached.swingId or nil,
    }
    trackDelay(fireAt - (os.clock() - baseTime), function() S.fireStylePrecisionTap(ctx) end, rec.
        epoch, atkChar)
end

-- gen41 force path — gen46 PATH1 disables (rate-burn, 0 Perfect in gen43)
S.scheduleForceResolveTap = function(atkChar, rec, attackKind)
    if CONFIG.PATH1_PRECISION_ONLY then
        S.stats.path1_force_skipped = (S.stats.path1_force_skipped or 0) + 1
        Log.step(string.format(
            "FORCE_RESOLVE_SKIP [P1] from=%s style=%s combo=%s why=path1_precision_only %s",
            atkChar.Name, tostring(rec.style), tostring(rec.comboIndex), expPathTag()
        ))
        return
    end
    local delay = forceDelayFor(rec.style)
    local pred = resolveStyleDelay(rec.style, attackKind, rec.comboIndex or 1)
    Log.step(string.format(
        "FORCE_RESOLVE_SCHED from=%s style=%s delay=%.3f refresh=+%.3f combo=%s %s",
        atkChar.Name, tostring(rec.style), delay, FORCE_REFRESH_GAP, tostring(rec.comboIndex),
            expPathTag()
    ))
    local function sched(reason, waitSec)
        local cached = hitboxOwnerCache[atkChar.Name]
        trackDelay(waitSec, function()
            if not CONFIG.ENABLED then return end
            if not S.windupActive[atkChar] then return end
            if not attackerHasLiveHitbox(atkChar, rec.style) and not attackerHasWindup(atkChar) then
                Log.step("FORCE_RESOLVE_SKIP from=" .. atkChar.Name .. " reason=hitbox_gone via=" ..
                    reason)
                return
            end
            fireActivatedRaw(atkChar.Name, waitSec, rec.style, true, {
                reason = reason, combo = rec.comboIndex or 0, predicted = pred or -1, attack =
                    attackKind,
                source = "force", epoch = rec.epoch or 0, edgeKind = "force_resolve",
                swingId = cached and cached.swingId or nil,
            })
        end, rec.epoch, atkChar)
    end
    sched("forceResolve", delay)
    sched("forceRefresh", delay + FORCE_REFRESH_GAP)
end

S.windupRegister = function(atkChar, attr)
    local now = os.clock()
    local style = styleOf(atkChar)
    local attackKind = (attr == "M2" or attr == "PendingM2") and "M2" or "M1"
    local mode = S.defenseDecide(attackKind, style)
    local rec = S.windupActive[atkChar]
    if rec then
        rec.expire = now + WINDUP_GRACE_SEC
        rec.style = style
        local prevKind = rec.attackKind or "M1"
        local prevMode = rec.defenseMode or "parry"
        rec.attackKind = attackKind
        -- M1→M2 / parry→dodge upgrade: cancel pending Activated, schedule Evasive
        if mode == "dodge" and (prevMode ~= "dodge" or (attackKind == "M2" and prevKind ~= "M2"))
            then
            S.cancelPendingParry(atkChar)
            local ep = S.bumpEpoch(rec, "windup_dodge", atkChar.Name, attackKind, rec.comboIndex or
                1, nil, true)
            rec.defenseMode = "dodge"
            S.scheduleDodge(atkChar, rec, attackKind, style, ep)
            Log.step(string.format(
                "DEFENSE_UPGRADE from=%s %s/%s → dodge attack=%s epoch=%d",
                atkChar.Name, prevMode, prevKind, attackKind, ep
            ))
            return
        end
        -- M2→M1 (or dodge→parry): restore parry path so follow-up lights aren't stuck
        if mode == "parry" and prevMode == "dodge" then
            local ep = S.bumpEpoch(rec, "windup_parry", atkChar.Name, attackKind, rec.comboIndex or
                1, nil, true)
            rec.defenseMode = "parry"
            S.defenseLock = nil
            S.scheduleStylePrecisionTap(atkChar, rec, attackKind, rec.comboIndex or 1, now, "windup"
                )
            Log.step(string.format(
                "DEFENSE_DOWNGRADE from=%s dodge → parry attack=%s epoch=%d",
                atkChar.Name, attackKind, ep
            ))
            return
        end
        if mode == "none" then
            rec.defenseMode = "none"
        end
        return
    end
    rec = {
        start = now, expire = now + WINDUP_GRACE_SEC, style = style,
        edgeScheduled = false, hitboxLeadLogged = false, lastEdgeAt = now, comboIndex = 1,
            nextExpectedAt = nil,
        epoch = nil, attackKind = attackKind,
        defenseMode = (mode == "dodge" and "dodge") or (mode == "none" and "none") or "parry",
    }
    S.windupActive[atkChar] = rec
    S.stats.windup_bursts = S.stats.windup_bursts + 1
    S.bumpEpoch(rec, "windup", atkChar.Name, attackKind, 1, nil)
    Log.step(string.format(
        "WINDUP_START from=%s style=%s attr=%s epoch=%d attack=%s " ..
            "defense=%s combo=1 edge=windup clock=%.3f %s",
        atkChar.Name, style, tostring(attr), rec.epoch or 0, attackKind, tostring(rec.defenseMode),
            now, windupAttrSnap(atkChar)
    ))
    emitEvent("WINDUP_START", {
        gen = S.gen, attacker = atkChar.Name, style = style, attr = tostring(attr),
        epoch = rec.epoch or 0, attack_class = attackKind, defense = rec.defenseMode,
        combo_slot = 1, edge_kind = "windup", clock = now,
    })
    if mode == "dodge" then
        S.scheduleDodge(atkChar, rec, attackKind, style, rec.epoch)
        return
    end
    if mode == "none" then
        Log.debug(string.format(
            "DODGE_ADVISORY from=%s style=%s attr=%s reason=grab_slam_no_autododge",
            atkChar.Name, style, tostring(attr)))
        emitEvent("DODGE_ADVISORY", { gen = S.gen, attacker = atkChar.Name, style = style, attr =
            tostring(attr) })
        return
    end
    -- gen40: no opener spray — precision + delayed forceResolve only (anti-BLOCK / anti-GB)
    if BLOCK_ENGAGE_PROBE then
        watchBlockEngage(lp.Character, style, atkChar.Name)
    end
    S.scheduleStylePrecisionTap(atkChar, rec, attackKind, 1, now, "windup")
end

-- one accepted Activated per WINDUP_TICK while ANY tracked attacker is live (rate-safe)
S.windupTick = function()
    if stale() or not CONFIG.ENABLED then return end
    local now = os.clock()
    -- gen24 P4: prefer whichever attacker currently has a LIVE hitbox against us — that's the one
    -- actually about to land, not just the closest. Nearest-by-distance is only the tiebreak/
    -- fallback when nobody has a live hitbox this frame.
    local nearestName, nearestDist, nearestStart, nearestStyle, nearestRec = nil, math.huge, now,
        "?", nil
    local nearestHasHitbox = false
    local ch = lp.Character
    local myHrp = ch and ch:FindFirstChild("HumanoidRootPart")
    local forceNow = false
    for atkChar, rec in pairs(S.windupActive) do
        local live = atkChar.Parent and enemyInWindupRange(atkChar)
        local hasHitbox = live and attackerHasLiveHitbox(atkChar, rec.style)
        if live and (attackerHasWindup(atkChar) or hasHitbox) then
            rec.expire = now + WINDUP_GRACE_SEC
        end
        -- gen40: hitbox-live → schedule DELAYED resolve tap (not immediate forceNow).
        -- Immediate @spawn was BLOCK in gen39 (PerfectWindow 0.125 < HitboxDuration 0.15).
        local cached = hitboxOwnerCache[atkChar.Name]
        local edgeAttack = cached and cached.attack
        if hasHitbox and edgeAttack and not rec.edgeScheduled then
            rec.edgeScheduled = true
            rec.hitboxLeadCombo = rec.comboIndex or 1
            local swingId = cached and cached.swingId
            -- Phase1: hitbox EDGE is log-only (mutateRec=false). Mutating rec.epoch here
            -- cancelled the pending opener precision delay before PATH1 could fire it.
            S.bumpEpoch(rec, "hitbox", atkChar.Name, edgeAttack, rec.hitboxLeadCombo, swingId, false
                )
            if rec.defenseMode == "dodge" then
                -- gen53: M2 dodge path — no Activated race; emergency if still in range
                S.tryM2HitboxEmergency(atkChar, edgeAttack, rec.style)
            elseif rec.defenseMode == "none" then
                -- unparryable + autododge off — advisory only
            else
                if live and attackerHasWindup(atkChar) then
                    rec.comboIndex = (rec.comboIndex or 1) + 1
                    S.scheduleStylePrecisionTap(atkChar, rec, edgeAttack, rec.comboIndex, now,
                        "hitbox")
                end
                S.scheduleForceResolveTap(atkChar, rec, edgeAttack)
            end
            rec.hitboxLiveUsed = false
        end
        local overlap = hasHitbox and edgeAttack and confirmedLocalOverlap(atkChar.Name, edgeAttack,
            rec.style)
        if hasHitbox and overlap and not rec.hitboxLeadLogged then
            rec.hitboxLeadLogged = true
            local lead = now - (rec.lastEdgeAt or rec.start)
            rec.lastEdgeAt = now
            local ci = rec.hitboxLeadCombo or rec.comboIndex or 1
            local pred = resolveStyleDelay(rec.style, edgeAttack, ci)
            local err = pred and (lead - pred) or nil
            observeWindupLatency(rec.style, lead, edgeAttack, ci)
            if CONFIG.PATH2_GAP_EMA and ci >= 2 then
                observeGapEma(rec.style, lead, ci)
            end
            if CONFIG.DIAGNOSTICS then
                Log.step(string.format(
                    "WINDUP_LEAD from=%s style=%s lead=%.3f predicted=%.3f " ..
                        "err=%s combo=%d slot=%d latency=%.3f gapEma=%s %s",
                    atkChar.Name, tostring(rec.style), lead,
                    pred or -1, err and string.format("%.3f", err) or "n/a",
                    ci, comboSlot(ci), latencyFor(rec.style),
                    (function()
                        local g = select(1, gapEmaFor(rec.style, ci))
                        return g and string.format("%.3f", g) or "nil"
                    end)(),
                    expPathTag()
                ))
                emitEvent("WINDUP_LEAD", {
                    gen = S.gen, attacker = atkChar.Name, style = tostring(rec.style),
                    lead = lead, predicted = pred or -1, err = err,
                    combo = ci, slot = comboSlot(ci), latency = latencyFor(rec.style),
                    path1 = CONFIG.PATH1_PRECISION_ONLY, path2 = CONFIG.PATH2_GAP_EMA,
                })
            else
                S.perf.diagSuppressed = S.perf.diagSuppressed + 1
            end
        elseif hasHitbox and edgeAttack and not overlap and not rec.nonOverlapSkipLogged then
            rec.nonOverlapSkipLogged = true
            if CONFIG.DIAGNOSTICS then
                Log.step(string.format("WINDUP_OVERLAP_SKIP from=%s attack=%s style=%s " ..
                    "reason=local_non_overlap",
                    atkChar.Name, edgeAttack, tostring(rec.style)))
            else
                S.perf.diagSuppressed = S.perf.diagSuppressed + 1
            end
        elseif not hasHitbox then
            rec.edgeScheduled = false
            rec.hitboxLeadLogged = false
            rec.hitboxLeadCombo = nil
            rec.hitboxLiveUsed = false
            rec.overlapEdgeUsed = false
            rec.nonOverlapSkipLogged = false
        end
        -- PATH1 edge cover: one extra raw Activate only when this exact attacker's live
        -- hitbox overlaps our character while player is holding M1. fireActivatedRaw retains
        -- all global rate, scan, zone, guard-break, and lock gates.
        if CONFIG.PATH1_PRECISION_ONLY and CONFIG.OVERLAP_EDGE_COVER and hasHitbox
            and not rec.overlapEdgeUsed and edgeAttack
            and rec.defenseMode ~= "dodge" and rec.defenseMode ~= "none"
            and ch and ch:GetAttribute("M1Hold") == true then
            if overlap then
                rec.overlapEdgeUsed = true
                S.stats.overlap_edges = S.stats.overlap_edges + 1
                Log.step(string.format(
                    "OVERLAP_EDGE from=%s attack=%s style=%s M1Hold=true clock=%.3f",
                    atkChar.Name, edgeAttack, tostring(rec.style), now))
                emitEvent("OVERLAP_EDGE", { gen = S.gen, attacker = atkChar.Name, attack =
                    edgeAttack,
                    style = tostring(rec.style), m1hold = true, clock = now })
                fireActivatedRaw(atkChar.Name, now - rec.start, rec.style, true, {
                    reason = "overlapEdge", combo = rec.comboIndex or 0,
                    predicted = resolveStyleDelay(rec.style, edgeAttack, rec.comboIndex or 1) or -1,
                    attack = edgeAttack, overlap = true, source = "overlap_edge",
                    epoch = rec.epoch or 0, edgeKind = "overlap",
                    swingId = cached and cached.swingId or nil,
                })
            end
        end
        if live and now < rec.expire then
            local d = 0
            if myHrp then
                local ahrp = atkChar:FindFirstChild("HumanoidRootPart")
                d = ahrp and (myHrp.Position - ahrp.Position).Magnitude or 0
            end
            local better = false
            if hasHitbox and not nearestHasHitbox then
                better = true
            elseif hasHitbox == nearestHasHitbox and d < nearestDist then
                better = true
            end
            if better then
                nearestDist = d
                nearestName = atkChar.Name
                nearestStart = rec.start
                nearestStyle = rec.style
                nearestRec = rec
                nearestHasHitbox = hasHitbox
            end
        else
            S.windupActive[atkChar] = nil
            Log.step("WINDUP_END from=" .. tostring(atkChar.Name))
            emitEvent("WINDUP_END", { gen = S.gen, attacker = atkChar.Name })
        end
    end
    -- PATH1: no hitboxLive spray. Idle → release Blocking.
    if not nearestName or not ch then
        sendBlockDeactivated()
        return
    end
    forceNow = nearestHasHitbox
    if weAreAttacking(ch) and not forceNow
        and not S.enemyHitLandsFirst(nearestName, nearestStyle, { attack = "M1" }) then
        return
    end
    local scanOk, scanWhy = canScan(ch)
    if not scanOk then
        local now2 = os.clock()
        if now2 - (S.lastWindupScanSkipLog or 0) > 0.5 then
            S.lastWindupScanSkipLog = now2
            Log.step("WINDUP_SCAN_SKIP why=" .. tostring(scanWhy) .. " vs=" .. tostring(nearestName)
                .. " style=" .. tostring(nearestStyle) .. " " .. expPathTag())
            emitEvent("WINDUP_SCAN_SKIP", { gen = S.gen, why = tostring(scanWhy), attacker =
                tostring(nearestName), style = tostring(nearestStyle) })
        end
        return
    end
    local allowLive = S.hitboxLiveSpray and not CONFIG.PATH1_PRECISION_ONLY
    if not allowLive or not nearestHasHitbox or not nearestRec then
        if CONFIG.PATH1_PRECISION_ONLY and nearestHasHitbox and not nearestRec.hitboxLiveUsed then
            -- log once per edge that P1 suppressed live spray
            nearestRec.hitboxLiveUsed = true -- reuse flag as "logged skip"
            S.stats.path1_live_skipped = (S.stats.path1_live_skipped or 0) + 1
            Log.step(string.format(
                "HITBOX_LIVE_SKIP [P1] from=%s style=%s combo=%s why=path1_precision_only %s",
                tostring(nearestName), tostring(nearestStyle), tostring(nearestRec.comboIndex),
                    expPathTag()
            ))
        end
        return
    end
    if nearestRec.hitboxLiveUsed then
        return
    end
    if nearestRec.defenseMode == "dodge" or nearestRec.defenseMode == "none" then
        return
    end
    if now - S.lastRawTapAt < WINDUP_TICK then return end
    if S.lastRawTapReason == "precision" and (now - S.lastRawTapAt) < PERFECT_WINDOW then
        return
    end
    local pred = resolveStyleDelay(nearestStyle, "M1", nearestRec.comboIndex or 1)
    if fireActivatedRaw(nearestName, now - nearestStart, nearestStyle, true, {
        reason = "hitboxLive", combo = nearestRec.comboIndex or 0, predicted = pred or -1, attack =
            "M1", source = "hitboxLive",
        epoch = nearestRec.epoch or 0, edgeKind = "hitboxLive",
        swingId = (hitboxOwnerCache[nearestName] or {}).swingId,
    }) then
        nearestRec.hitboxLiveUsed = true
    end
end

S.onEnemyAttrChanged = function(atkChar, attr)
    if stale() or not CONFIG.ENABLED then return end
    local ch = lp.Character
    if not ch or atkChar == ch then return end
    if atkChar:GetAttribute(attr) ~= true then return end
    if not enemyInWindupRange(atkChar) then return end
    if not canScan(ch) then return end
    S.windupRegister(atkChar, attr)
end

S.wireEnemyChar = function(atkChar)
    if not atkChar then return end
    clearEnemyCharConnections(atkChar)
    for _, a in ipairs(WINDUP_ATTRS) do
        trackEnemyChar(atkChar, atkChar:GetAttributeChangedSignal(a):Connect(function()
            S.onEnemyAttrChanged(atkChar, a)
        end))
    end
end

local function wirePlayer(plr)
    if plr == lp then return end
    local function wireChar(c)
        local oldChar = S.enemyPlayerChars[plr]
        if oldChar and oldChar ~= c then
            clearEnemyCharConnections(oldChar)
        end
        S.enemyPlayerChars[plr] = c
        if c then S.wireEnemyChar(c) end
    end
    wireChar(plr.Character)
    track(plr.CharacterAdded:Connect(function(c)
        if stale() then return end
        wireChar(c)
    end))
end

-- AUTORHYTHM moved to standalone gakuran_autorhythm.lua (getconnections-based, no
-- getloadedmodules/getgc/getnilinstances). This script no longer touches the rhythm engine —
-- run the standalone script alongside this one for rhythm perfects.

local function main()
    Log.info(string.format(
        "GEN47_BOOT gen=%d enabled=%s proactive=%s path1=%s path2=%s overlapEdge=%s reactive=%s",
        S.gen, tostring(CONFIG.ENABLED), tostring(CONFIG.PROACTIVE),
        tostring(CONFIG.PATH1_PRECISION_ONLY), tostring(CONFIG.PATH2_GAP_EMA),
        tostring(CONFIG.OVERLAP_EDGE_COVER), tostring(CONFIG.REACTIVE_PARRY)
    ))
    S.overlap = OverlapParams.new()
    S.overlap.FilterType = Enum.RaycastFilterType.Include
    S.overlap.MaxParts = 50
    if CONFIG.ENABLED then
        applyCombatSideEffects(true)
    end
    bindCombatBroadcast()

    local folder = Workspace:WaitForChild("Hitboxes", 30)
    if folder then
        S.hitboxes = folder
        table.clear(hitboxOwnerCache)
        for _, child in ipairs(folder:GetChildren()) do
            cacheHitboxPart(child)
        end
        Log.step("Hitboxes folder ok children=" .. tostring(#folder:GetChildren())
            .. " cache=" .. tostring((function()
                local n = 0
                for _ in pairs(hitboxOwnerCache) do n = n + 1 end
                return n
            end)()))
        -- gen37: always maintain owner cache for forceNow (independent of REACTIVE_PARRY)
        track(folder.ChildAdded:Connect(function(child)
            cacheHitboxPart(child)
            if CONFIG.REACTIVE_PARRY then onHitboxAdded(child) end
        end))
        track(folder.ChildRemoved:Connect(uncacheHitboxPart))
        if CONFIG.REACTIVE_PARRY then
            seedExistingHitboxes(folder)
        end
    else
        Log.err("workspace.Hitboxes missing after 30s")
    end

    Hud.build()

    track(lp.CharacterAdded:Connect(function(ch)
        if stale() then return end
        Log.step("CharacterAdded " .. tostring(ch and ch.Name))
        clearLocalCharConnections()
        table.clear(S.reported)
        table.clear(S.swings)
        table.clear(S.fired)
        table.clear(S.scanTried)
        table.clear(S.scanLogged)
        table.clear(S.threatSkipLogged)
        table.clear(S.swingFinalized)
        table.clear(S.confirmHeld)
        table.clear(S.lastConfirm)
        table.clear(S.pending)
        table.clear(S.timing)
        table.clear(S.windupActive)
        table.clear(S.pendingDodges)
        S.threatSkipAgg = { n = 0, lastLog = 0 }
        table.clear(S.hitboxParseDebounce)
        S.overlap.FilterDescendantsInstances = {}
        wireHealthWatch(ch)
        -- gen24 ROOT-CAUSE FIX: both pins used to run unconditionally here, gated only by their
        -- own CONFIG flags (NO_COOLDOWN/NO_DODGE_CD default true) — NOT by CONFIG.ENABLED. That
        -- meant OFF still force-set OutnumberedEvasiveGrant=true and cleared BlockCooldown on
        -- every character spawn, contradicting the HUD toggle's "OFF = inert" contract. This is
        -- the real cause of the T/equip-fists regression: two prior isolation attempts
        -- (STYLE_TIMING_PROBE=false, BLOCK_ENGAGE_PROBE=false) both gated ENABLED-conditional
        -- code and never touched this path. Gate both behind CONFIG.ENABLED now.
        -- gen45: Grant pin restored (+ mult nerf); still ENABLED-gate pinDodgeCd.
        if CONFIG.ENABLED and CONFIG.NO_COOLDOWN and ch then
            trackLocalChar(ch:GetAttributeChangedSignal("BlockCooldown"):Connect(function()
                if stale() or not CONFIG.ENABLED then return end
                if ch:GetAttribute("BlockCooldown") == true then
                    pcall(function() ch:SetAttribute("BlockCooldown", nil) end)
                    Log.step("pinned BlockCooldown cleared")
                end
            end))
        end
        if CONFIG.ENABLED then pinDodgeCd(ch) end
        wireM1HoldWatch(ch)
        wireParryBufferedWatch(ch)
        if ch then
            trackLocalChar(ch:GetAttributeChangedSignal("IFRAMES"):Connect(function()
                if S.onDodgeIframes then S.onDodgeIframes(ch) end
            end))
        end
    end))

    clearLocalCharConnections()
    wireHealthWatch(lp.Character)
    if CONFIG.ENABLED then pinDodgeCd(lp.Character) end
    wireM1HoldWatch(lp.Character)
    wireParryBufferedWatch(lp.Character)
    if lp.Character then
        trackLocalChar(lp.Character:GetAttributeChangedSignal("IFRAMES"):Connect(function()
            if S.onDodgeIframes then S.onDodgeIframes(lp.Character) end
        end))
    end

    -- windup-predictive: watch every other player's attack-state attrs
    for _, plr in ipairs(Players:GetPlayers()) do wirePlayer(plr) end
    track(Players.PlayerAdded:Connect(function(plr)
        if stale() then return end
        wirePlayer(plr)
    end))
    track(Players.PlayerRemoving:Connect(function(plr)
        local ch = S.enemyPlayerChars[plr]
        if ch then clearEnemyCharConnections(ch) end
        S.enemyPlayerChars[plr] = nil
    end))

    track(RunService.PreSimulation:Connect(function(dt)
        if stale() then return end
        S.windupTick()
        if CONFIG.REACTIVE_PARRY then scanHitboxes() end
        heartbeat()
        S.perfSnapshot(dt)
    end))

    Log.info("main ready pathA — ON/OFF toggle, RShift hide≠OFF")
end

task.defer(function()
    local ok, err = xpcall(main, debug.traceback)
    if not ok then
        Log.err("crash " .. tostring(err))
        destroy()
    end
end)
