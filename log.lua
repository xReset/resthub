-- Shared workspace logger. Install: copy to Potassium workspace as log.lua
-- Usage:
--   local Log = loadfile("log.lua")()("admin")
--   Log.info("ready")
--   Log.err("boom", err)          -- appends traceback when err passed
-- Writes: logs/<tag>.log  (assistant reads workspace directly)

return function(tag, opts)
    tag = tostring(tag or "script")
    opts = opts or {}

    local dir = opts.dir or "logs"
    local file = opts.file or (dir .. "/" .. tag .. ".log")
    local alsoPrint = opts.print ~= false

    -- The directory and the file's existence are checked ONCE, not per line.
    --
    -- They used to be re-checked on every single write: isfolder(dir) plus
    -- isfile(file), two synchronous executor filesystem calls, before the
    -- appendfile that actually does the work. cs_core alone writes ~10 lines a
    -- second during a busy match (586 in the peak minute of the 16:23 build) and
    -- cs_pforge writes on top of that, all of it on the main thread. Neither
    -- answer can change while the process is running once the file exists, so
    -- both are latched.
    local dirReady, fileExists = false, false

    local function ensureDir()
        if dirReady then return end
        dirReady = true
        pcall(function()
            if isfolder and not isfolder(dir) then makefolder(dir) end
        end)
    end

    local function write(level, msg, err)
        ensureDir()
        local ts = os.date("%H:%M:%S")
        local line = string.format("[%s] [%s] %s", ts, level, tostring(msg))
        if err ~= nil then
            line = line .. " | " .. tostring(err)
            if debug and debug.traceback then
                line = line .. "\n" .. debug.traceback(tostring(err), 2)
            end
        end
        pcall(function()
            if not fileExists and isfile then fileExists = isfile(file) end
            if appendfile and fileExists then
                appendfile(file, line .. "\n")
            elseif writefile then
                writefile(file, line .. "\n")
                fileExists = true
            end
        end)
        if alsoPrint then
            -- ONE console write per line, not two. This wrote the same string to
            -- both warn() and print(), so every log line cost two LogService
            -- entries and two console redraws. Level now picks the channel, which
            -- is what a level is for.
            local out = "[" .. tag .. "] " .. line
            if level == "WARN" or level == "ERR" then warn(out) else print(out) end
        end
    end

    local function session(extra)
        ensureDir()
        local header = string.format(
            "========== %s %s ==========\nplace=%s job=%s%s\n",
            os.date("%Y-%m-%d %H:%M:%S"),
            tag,
            tostring(game and game.PlaceId or "?"),
            tostring(game and game.JobId or "?"),
            extra and ("\n" .. extra) or ""
        )
        pcall(function()
            if writefile then writefile(file, header) ; fileExists = true end
        end)
        if alsoPrint then
            warn("[" .. tag .. "] session -> " .. file)
        end
    end

    return {
        path = file,
        session = session,
        info = function(msg) write("INFO", msg) end,
        warn = function(msg) write("WARN", msg) end,
        err = function(msg, err) write("ERR", msg, err) end,
        step = function(msg) write("STEP", msg) end,
    }
end
