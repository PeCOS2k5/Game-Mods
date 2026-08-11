--=====================================================================
-- ITR2 Extra Routes
--
--   Adds two level transitions Into the Radius 2 does not have:
--
--     Outskirts -> Facility
--     Forest    -> Outskirts       (takes over Forest -> Peninsula)
--
--   Level transitions in this game are data. Each one carries the
--   destination level, the arrival marker to land on, and the trigger
--   that gates it. This mod rewrites the destination on two specific
--   transitions and does nothing else.
--
--   You travel them normally -- shake the Pyotr's hand, walk the route,
--   step into the transition zone. The game performs the transition
--   itself: the fog stage, the inventory handoff, and placing you on
--   the correct arrival marker. Nothing is reimplemented.
--
--   Nothing is written to your save. Transition actors are rebuilt on
--   every level load, so deleting this folder restores the game.
--=====================================================================

local MOD_DIR = "../../Content/Paks/LuaMods/ITR2ExtraRoutes/"
local CFG     = MOD_DIR .. "config.txt"

-- The two routes, fixed. These are not user-editable on purpose: a
-- wrong destination or a missing arrival marker drops you somewhere
-- unintended, and there is no way for the mod to check that for you.
local ROUTES = {
    {
        key  = "outskirts_to_facility",
        desc = "Outskirts -> Facility",
        gate = "Level.Radius.Town.TownRGD",
        to   = "Level.Hub",
        exit = "Level.Hub.Gate.Exit",
        default = true,
    },
    {
        key  = "forest_to_outskirts",
        desc = "Forest -> Outskirts",
        gate = "Level.Radius.Forest.Peninsula",
        to   = "Level.Radius.Town",
        exit = "Level.Radius.Forest.Railroad.Exit",
        default = true,
    },
}

local DEFAULT_CFG = [[
# ITR2 Extra Routes - configuration
#
# Two switches. 1 = on, 0 = off. Re-read once a second, so you can
# change these while the game is running.
#
# ---------------------------------------------------------------------
# OUTSKIRTS -> FACILITY
#
# Gives Outskirts a direct way back to the Facility, which the game does
# not have. It takes over one of the two routes Outskirts already has to
# Forest, and Outskirts keeps the other one, so nothing is lost.
#
# Travel it the normal way: the Pyotr on the RGD road.

outskirts_to_facility = 1


# ---------------------------------------------------------------------
# FOREST -> OUTSKIRTS
#
# Coming back from the Facility you land in Forest, and the nearest way
# onward to Outskirts is right across the map. This puts one near where
# you land instead.
#
# NOTE WHAT IT REPLACES. Forest has no spare route near that gate, so
# this takes over Forest -> Peninsula. Peninsula is still directly
# reachable from the Facility, so you keep access to it - you lose only
# the direct Forest link.
#
# Set this to 0 if you would rather keep Forest -> Peninsula.
#
# Travel it the normal way: the Pyotr at the Peninsula gate.

forest_to_outskirts = 1
]]

--------------------------------------------------------------------
-- helpers
--------------------------------------------------------------------
local function logf(fmt, ...)
    local ok, s = pcall(string.format, fmt, ...)
    print("[ITR2ExtraRoutes] " .. (ok and s or tostring(fmt)) .. "\n")
end

local function isReal(o)
    if not o then return false end
    local ok, v = pcall(function() return o:IsValid() end)
    if not ok or not v then return false end
    local ok2, f = pcall(function() return o:GetFullName() end)
    return ok2 and f and not f:find("Default__", 1, true)
end

local function shortName(o)
    local n = "?"
    pcall(function() n = o:GetFullName():gsub(".*[%.:]", "") end)
    return n
end

local function tagOf(obj, field)
    local s = nil
    pcall(function() s = obj[field].TagName:ToString() end)
    if s == nil or s == "" then return "None" end
    return tostring(s)
end

local function setTag(obj, field, value)
    return pcall(function() obj[field].TagName = FName(value) end)
end

--------------------------------------------------------------------
-- config
--------------------------------------------------------------------
local enabled = {}

local function ensureCfg()
    local f = io.open(CFG, "r")
    if f then f:close() return end
    local w = io.open(CFG, "w")
    if w then w:write(DEFAULT_CFG) w:close() logf("created config.txt") end
end

local function readCfg()
    local f = io.open(CFG, "r")
    if not f then return nil end
    local raw = f:read("a") or ""
    f:close()

    local out = {}
    for _, r in ipairs(ROUTES) do out[r.key] = r.default end
    for line in raw:gmatch("[^\r\n]+") do
        local k, v = line:match("^%s*([%a_][%w_]*)%s*=%s*(.-)%s*$")
        if k then
            k = k:lower()
            v = v:gsub("%s*[;#].*$", "")
            for _, r in ipairs(ROUTES) do
                if k == r.key then out[r.key] = (tonumber(v) or 0) == 1 end
            end
        end
    end
    return raw, out
end

--------------------------------------------------------------------
-- apply
--------------------------------------------------------------------
local reported = {}

local function apply()
    local ok, list = pcall(FindAllOf, "BP_LvlTransitionLocal_C")
    if not ok or not list then return end

    for _, a in ipairs(list) do
        if isReal(a) then
            local gate = tagOf(a, "UnlockTriggerTag")
            for _, r in ipairs(ROUTES) do
                if enabled[r.key] and gate == r.gate then
                    local curTo   = tagOf(a, "ToLevelTag")
                    local curExit = tagOf(a, "ExitTag")
                    if curTo ~= r.to or curExit ~= r.exit then
                        setTag(a, "ToLevelTag", r.to)
                        setTag(a, "ExitTag", r.exit)
                        -- a real level change, never a same-map shuffle
                        pcall(function() a.bIsLocalTransit = false end)
                        local key = r.key .. shortName(a)
                        if not reported[key] then
                            reported[key] = true
                            logf("%s enabled (%s -> %s)", r.desc,
                                 curTo, tagOf(a, "ToLevelTag"))
                        end
                    end
                end
            end
        end
    end
end

--------------------------------------------------------------------
-- lifecycle
--------------------------------------------------------------------
-- Touching UObjects while a world is being torn down reads freed
-- memory, which pcall cannot catch. Hold still through transitions and
-- stop for good once the game is closing.
local shuttingDown, ticks, resumeAt = false, 0, 3
local lastRaw = nil

local function tick()
    ticks = ticks + 1
    if shuttingDown or ticks < resumeAt then return end

    local raw, flags = readCfg()
    if raw and raw ~= lastRaw then
        lastRaw, enabled, reported = raw, flags, {}
        local on = {}
        for _, r in ipairs(ROUTES) do
            if enabled[r.key] then on[#on + 1] = r.desc end
        end
        logf("config: %s", #on > 0 and table.concat(on, ", ") or "no routes enabled")
    end
    if not raw then return end

    pcall(apply)
end

local function loop()
    ExecuteWithDelay(1000, function()
        pcall(tick)
        if not shuttingDown then loop() end
    end)
end

ensureCfg()
logf("loaded")

pcall(RegisterHook, "/Script/Engine.KismetSystemLibrary:QuitGame",
      function() shuttingDown = true end)
if type(RegisterLoadMapPreHook) == "function" then
    pcall(RegisterLoadMapPreHook, function() resumeAt = ticks + 3 end)
end
RegisterHook("/Script/Engine.PlayerController:ClientRestart", function()
    reported = {}
    resumeAt = ticks + 3
end)

loop()
