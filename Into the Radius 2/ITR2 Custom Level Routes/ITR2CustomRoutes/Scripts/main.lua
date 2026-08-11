--=====================================================================
-- ITR2 Custom Routes   -- experiment
--
--   Into the Radius 2 routes level transitions with data, not code.
--   Every Pyotr is a RadiusTransit carrying:
--
--     ToLevelTag         the destination level
--     ExitTag            which arrival marker to land on, over there
--     UnlockTriggerTag   the global trigger that gates him
--     bIsLocalTransit    same-map shuffle vs real level change
--
--   So a new route is a data change: point a Pyotr somewhere else and
--   the game does the rest -- the fog map, carrying your inventory
--   through PrepareReplicatorForTravel, and spawning you on the
--   matching arrival arrow.
--
--   Pyotrs are matched by their UnlockTriggerTag, which is stable,
--   rather than by instance name, which is not.
--
--   Nothing is written to disk and actors are rebuilt on every level
--   load, so removing the mod restores the game completely.
--
--   Config: config.txt in this mod's folder, re-read once a second.
--   Log:    UE4SS.log, plus log.txt here when debug = 1
--=====================================================================

local MOD_DIR = "../../Content/Paks/LuaMods/ITR2CustomRoutes/"
local CFG     = MOD_DIR .. "config.txt"
local OUT     = MOD_DIR .. "log.txt"
local debugOn = false

local DEFAULT_CFG = [[
# ITR2 Custom Level Routes - configuration
#
# Re-read once a second and re-applied on every level load. Edit while
# the game is running; the change takes effect before you reach the gate.
#
# ---------------------------------------------------------------------
#   retarget = <gate tag> | <destination level> | <arrival marker>
#
# Finds the transition whose UnlockTriggerTag matches the gate tag and
# points it somewhere else. Repeatable - one line per route.
#
#   debug = 1   logs which transition you are nearest to and where it
#               leads, which is how you discover tags for new routes
# ---------------------------------------------------------------------


# TOWN -> HUB
#
# Town has TWO routes to Forest, so retargeting one costs nothing: Town
# still reaches Forest through the other. This takes over the RGD one.
#
# You still travel it normally - shake the local Pyotr's hand, walk the
# route, step into the transition zone - you simply arrive at the Hub
# gate instead of Forest.

retarget = Level.Radius.Town.TownRGD | Level.Hub | Level.Hub.Gate.Exit


# FOREST -> TOWN, closer to the Hub gate        (OPTIONAL - off by default)
#
# Coming back from Hub you land in Forest at the Facility gate, and the
# nearest way onward to Town is about 870 m away across the map. This
# takes over the Peninsula gate instead, which sits about 350 m from
# where you land - the closest thing Forest has to spare.
#
# THE COST: you lose Forest -> Peninsula. Peninsula is still directly
# reachable from the Hub, so for most people that is a good trade, but
# it is your call - which is why this is off by default.
#
# Uncomment the line below to enable it.

# retarget = Level.Radius.Forest.Peninsula | Level.Radius.Town | Level.Radius.Forest.Railroad.Exit


debug = 0


# ---------------------------------------------------------------------
# REFERENCE, measured in game
#
# Destination levels:
#   Level.Hub                Level.Radius.Town
#   Level.Radius.Peninsula   Level.Radius.School
#   Level.Radius.Forest      Level.Radius.Unlock_School
#                            Level.Radius.Unlock_Town
#
# Arrival markers, and the map each one physically sits in:
#   Level.Hub.Gate.Exit                 Hub
#   Level.Hub.Gate.Forest.Exit          Hub
#   Level.Hub.Gate.Peninsula.Exit       Hub
#   Level.Radius.Peninsula.ToTown.Exit  Town
#   Level.Radius.Town.Village.Exit      Forest
#   Level.Radius.Town.TownRGD.Exit      Forest
#   Level.Radius.Forest.Railroad.Exit   Town
#   Level.Radius.Forest.TownRoad.Exit   Town
#   Level.Radius.Forest.Peninsula.Exit  Peninsula
#   Level.Radius.School.Town.Exit       Town
#
# The arrival marker MUST exist in the destination level, or you will
# travel and land somewhere unintended.
#
# Gate tags for the map-to-map routes, by origin:
#   Town     Level.Radius.Town.TownRGD      -> Forest
#            Level.Radius.Town.Village      -> Forest
#            Level.Radius.Town.School       -> School
#            Level.Radius.Town.ToLabyrinth  -> Peninsula
#            Level.Radius.Town.UnlockSchool -> Unlock_School
#   Forest   Level.Radius.Forest.Facility   -> Hub
#            Level.Radius.Forest.Railroad   -> Town
#            Level.Radius.Forest.TownRoad   -> Town
#            Level.Radius.Forest.Peninsula  -> Peninsula
#            Level.Radius.Forest.UnlockTown -> Unlock_Town
#   Hub      Level.Hub.Gate.Forest          -> Forest
#            Level.Hub.Gate.Peninsula       -> Peninsula
#
# Anything with GateLocal in the tag is a same-map shuttle, not a level
# change. Retargeting one of those is untested.
# ---------------------------------------------------------------------
]]

local function logf(fmt, ...)
    local ok, s = pcall(string.format, fmt, ...)
    s = ok and s or tostring(fmt)
    print("[CustomRoutes] " .. s .. "\n")
    -- only spill a file when the user asked for it
    if debugOn then
        local f = io.open(OUT, "a")
        if f then f:write(s .. "\n") f:close() end
    end
end

local function isReal(o)
    if not o then return false end
    local ok, v = pcall(function() return o:IsValid() end)
    if not ok or not v then return false end
    local ok2, f = pcall(function() return o:GetFullName() end)
    return ok2 and f and not f:find("Default__", 1, true)
end

local function shortName(o)
    local n = "?" pcall(function() n = o:GetFullName():gsub(".*[%.:]", "") end) return n
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
local routes = {}

local function ensureCfg()
    local f = io.open(CFG, "r")
    if f then f:close() return end
    local w = io.open(CFG, "w")
    if w then w:write(DEFAULT_CFG) w:close() logf("created %s", CFG) end
end

local function readCfg()
    local f = io.open(CFG, "r")
    if not f then return nil end
    local raw = f:read("a") or ""
    f:close()
    local list, dbg = {}, false
    for line in raw:gmatch("[^\r\n]+") do
        local k, v = line:match("^%s*([%a_][%w_]*)%s*=%s*(.-)%s*$")
        if k then
            k = k:lower()
            if k == "retarget" and v ~= "" then
                v = v:gsub("%s*#.*$", "")
                local gate, to, exit = v:match("^%s*(.-)%s*|%s*(.-)%s*|%s*(.-)%s*$")
                if gate and to and exit and gate ~= "" then
                    list[#list + 1] = { gate = gate, to = to, exit = exit }
                end
            elseif k == "debug" then
                dbg = (tonumber(v) or 0) == 1
            end
        end
    end
    return raw, list, dbg
end

--------------------------------------------------------------------
-- apply
--------------------------------------------------------------------
local reported = {}

local function apply()
    if #routes == 0 then return end
    local ok, list = pcall(FindAllOf, "BP_LvlTransitionLocal_C")
    if not ok or not list then return end

    for _, a in ipairs(list) do
        if isReal(a) then
            local gate = tagOf(a, "UnlockTriggerTag")
            for _, r in ipairs(routes) do
                if gate == r.gate then
                    local curTo   = tagOf(a, "ToLevelTag")
                    local curExit = tagOf(a, "ExitTag")
                    if curTo ~= r.to or curExit ~= r.exit then
                        local okTo   = setTag(a, "ToLevelTag", r.to)
                        local okExit = setTag(a, "ExitTag", r.exit)
                        -- a real level change, never a local shuffle
                        pcall(function() a.bIsLocalTransit = false end)
                        local key = shortName(a) .. r.to
                        if not reported[key] then
                            reported[key] = true
                            logf("retargeted %s (gate %s)", shortName(a), gate)
                            logf("    to   %s -> %s   %s", curTo, tagOf(a, "ToLevelTag"),
                                 okTo and "" or "WRITE FAILED")
                            logf("    exit %s -> %s   %s", curExit, tagOf(a, "ExitTag"),
                                 okExit and "" or "WRITE FAILED")
                        end
                    end
                end
            end
        end
    end
end

--------------------------------------------------------------------
-- "which one am I standing at?"
--------------------------------------------------------------------
local lastNearest = nil

local function playerPawn()
    local ok, helpers = pcall(require, "UEHelpers")
    if ok and helpers and helpers.GetPlayer then
        local p
        pcall(function() p = helpers.GetPlayer() end)
        if isReal(p) then return p end
    end
    local ok2, list = pcall(FindAllOf, "BP_RadiusPlayerCharacter_Gameplay_C")
    if ok2 and list then
        for _, p in ipairs(list) do if isReal(p) then return p end end
    end
    return nil
end

local function reportNearest()
    local pawn = playerPawn()
    if not pawn then return end
    local px, py, pz
    pcall(function()
        local v = pawn:K2_GetActorLocation()
        px, py, pz = v.X, v.Y, v.Z
    end)
    if not px then return end

    local ok, list = pcall(FindAllOf, "BP_LvlTransitionLocal_C")
    if not ok or not list then return end

    local best, bestD = nil, 1e18
    for _, a in ipairs(list) do
        if isReal(a) then
            local ax, ay, az
            pcall(function()
                local v = a:K2_GetActorLocation()
                ax, ay, az = v.X, v.Y, v.Z
            end)
            if ax then
                local d = math.sqrt((ax-px)^2 + (ay-py)^2 + (az-pz)^2)
                if d < bestD then best, bestD = a, d end
            end
        end
    end
    if not best then return end

    -- metres, and only when the answer actually changes
    local m = math.floor(bestD / 100 + 0.5)
    local line = string.format("NEAREST %s  %dm  gate=%s  to=%s  exit=%s  local=%s",
        shortName(best), m, tagOf(best, "UnlockTriggerTag"),
        tagOf(best, "ToLevelTag"), tagOf(best, "ExitTag"),
        tostring((function() local b pcall(function() b = best.bIsLocalTransit end) return b end)()))
    if line ~= lastNearest then
        lastNearest = line
        logf("%s   you at %.0f,%.0f,%.0f", line, px, py, pz)
    end
end

--------------------------------------------------------------------
-- loop
--------------------------------------------------------------------
local shuttingDown, lastRaw = false, nil

local function tick()
    if shuttingDown then return end
    local raw, list, dbg = readCfg()
    if raw and raw ~= lastRaw then
        lastRaw, routes, reported, debugOn = raw, list, {}, dbg
        logf("config reloaded: %d route(s)%s", #routes, dbg and ", debug on" or "")
        for _, r in ipairs(routes) do
            logf("    %s  ->  %s  @ %s", r.gate, r.to, r.exit)
        end
    end
    pcall(apply)
    if debugOn then pcall(reportNearest) end
end

local function loop()
    ExecuteWithDelay(1000, function()
        pcall(tick)
        if not shuttingDown then loop() end
    end)
end

ensureCfg()
logf("")
logf("############ ITR2 Custom Routes ############")

pcall(RegisterHook, "/Script/Engine.KismetSystemLibrary:QuitGame",
      function() shuttingDown = true end)
RegisterHook("/Script/Engine.PlayerController:ClientRestart", function()
    reported, lastNearest = {}, nil
    logf("== new level, re-applying routes")
end)

loop()
