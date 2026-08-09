--=====================================================================
-- ITR2 Distortion Zone Visibility
--
--   Removes the thick red screen haze inside distortion zones.
--
--   The haze is not drawn by the zone actor. It is DistortionZonePP, a
--   weighted blendable on the player's camera, switched from weight 0
--   to 1 the moment you cross into a zone. This mod holds it at 0.
--
--   The zone's dome, particles and light are left completely alone, so
--   you can still see a zone coming before you walk into it.
--
--   Settings live in config.txt in this mod's folder and are re-read
--   once a second. Edit while the game is running.
--=====================================================================

local MOD_DIR = "../../Content/Paks/LuaMods/ITR2DistortionZoneVisibility/"
local CFG     = MOD_DIR .. "config.txt"

local TICK_MS      = 1000   -- config read and camera rescan
local FAST_MS      = 200    -- the clamp itself
local SETTLE_TICKS = 5
local RESCAN_TICKS = 10

local function logf(fmt, ...)
    local ok, s = pcall(string.format, fmt, ...)
    print("[ITR2DistortionZoneVisibility] " .. (ok and s or tostring(fmt)) .. "\n")
end

--------------------------------------------------------------------
-- default config, written on first run
--------------------------------------------------------------------
local DEFAULT_CFG = [[
# ITR2 Distortion Zone Visibility - configuration
#
# Re-read once a second while the game runs. Save and the change applies
# in-world within about a second. No reload needed.
#
# ---------------------------------------------------------------------
#   enabled         1 = mod active, 0 = game left completely stock
#
#   blendable_off   a camera post process effect to suppress. Repeatable
#                   -- add one line per effect. Matching is a
#                   case-insensitive substring of the asset name.
#                   Comment a line out to restore that effect.
#
# These are ON/OFF, not dials. A weight of 0.01 looks identical to 1.0;
# only exactly 0 removes the effect. Unreal applies a post process
# material of this kind at full strength for any weight above zero, so
# no in-between exists whatever value you write.
#
# ---------------------------------------------------------------------
# The six post process effects on the player's gameplay camera:
#
#   DistortionZonePP           the thick red distortion zone haze
#   VisionPP_DistorsionHelmet  anti-distortion helmet mask overlay
#   VisionPP                   base vision effect
#   M_LowHealth                low health vignette
#   MI_PP_NightVision          night vision
#   M_FogAnomalyPostProcess    fog anomaly
#
# CAREFUL: matching is a substring, and "VisionPP" is contained inside
# "VisionPP_DistorsionHelmet". Listing the short name suppresses both.
# Use the full names exactly as written above.
#
# A ":weight" suffix is accepted, e.g. DistortionZonePP:0.5, in case some
# other effect does respond to weight. Neither of the first two do.
# ---------------------------------------------------------------------

[default]
enabled       = 1

blendable_off = DistortionZonePP

# Uncomment to also remove the anti-distortion helmet's mask overlay:
# blendable_off = VisionPP_DistorsionHelmet
]]

--------------------------------------------------------------------
-- helpers
--------------------------------------------------------------------
local function isReal(obj)
    if not obj then return false end
    local ok, valid = pcall(function() return obj:IsValid() end)
    if not ok or not valid then return false end
    local ok2, full = pcall(function() return obj:GetFullName() end)
    if not ok2 or not full then return false end
    return not full:find("Default__", 1, true)
end

local function ensureConfig()
    local f = io.open(CFG, "r")
    if f then f:close() return end
    local w = io.open(CFG, "w")
    if w then
        w:write(DEFAULT_CFG)
        w:close()
        logf("created %s", CFG)
        return
    end
    CFG = "ITR2DistortionZoneVisibility_config.txt"
    local f2 = io.open(CFG, "r")
    if f2 then f2:close() else
        local w2 = io.open(CFG, "w")
        if w2 then w2:write(DEFAULT_CFG) w2:close() end
    end
    logf("mod folder not writable, using Binaries/Win64/%s", CFG)
end

--------------------------------------------------------------------
-- config
--------------------------------------------------------------------
-- "Name" or "Name:0.5". Weight defaults to 0, the only value that
-- matters for these materials.
local function parseConfig(raw)
    local enabled, list = 1, {}
    for line in raw:gmatch("[^\r\n]+") do
        local k, v = line:match("^%s*([%a_][%w_]*)%s*=%s*(.-)%s*$")
        if k then
            v = v:gsub("%s*[;#].*$", "")
            k = k:lower()
            if k == "enabled" then
                enabled = tonumber(v) or 1
            elseif k == "blendable_off" and v ~= "" then
                local name, w = v:match("^(.-)%s*:%s*([%d%.]+)$")
                list[#list + 1] = {
                    match  = (name or v):lower(),
                    weight = tonumber(w) or 0,
                }
            end
        end
    end
    return enabled, list
end

--------------------------------------------------------------------
-- lifecycle
--------------------------------------------------------------------
-- Touching UObjects while a world is being torn down reads freed memory,
-- which pcall cannot catch. Hold still during transitions, stop dead on
-- shutdown.
local shuttingDown, ticks, resumeAtTick = false, 0, 0
local cams, lastScanTick = {}, -999
local rules, lastLog = {}, {}

local function pause()
    cams = {}
    lastScanTick = -999
    resumeAtTick = ticks + SETTLE_TICKS
end

local function markShutdown(why)
    if shuttingDown then return end
    shuttingDown = true
    cams, rules = {}, {}
    logf("shutting down (%s)", why)
end

--------------------------------------------------------------------
-- the work
--------------------------------------------------------------------
local function findCameras()
    local out = {}
    local ok, list = pcall(FindAllOf, "CameraComponent")
    if ok and list then
        for _, c in ipairs(list) do
            if isReal(c) then out[#out + 1] = c end
        end
    end
    return out
end

-- A ceiling, never an absolute set. These effects sit at weight 0 when
-- inactive, so forcing a value would switch them ON everywhere instead
-- of only suppressing them where the game turns them on.
local function applyRules()
    if #rules == 0 then return end
    for _, cam in ipairs(cams) do
        if isReal(cam) then
            pcall(function()
                cam.PostProcessSettings.WeightedBlendables.Array:ForEach(function(_, elem)
                    local wb  = elem:get()
                    local obj = nil
                    pcall(function() obj = wb.Object:GetFullName() end)
                    if not obj then return end
                    local low = obj:lower()

                    for _, rule in ipairs(rules) do
                        if low:find(rule.match, 1, true) then
                            local cur = nil
                            pcall(function() cur = wb.Weight end)
                            if cur and cur > rule.weight + 1e-4 then
                                pcall(function() wb.Weight = rule.weight end)
                                local short = obj:gsub(".*[%./]", "")
                                if (ticks - (lastLog[short] or -999)) > 30 then
                                    lastLog[short] = ticks
                                    logf("suppressing %s", short)
                                end
                            end
                            break
                        end
                    end
                end)
            end)
        end
    end
end

--------------------------------------------------------------------
-- loops
--------------------------------------------------------------------
local lastRaw, warnedNoCfg = nil, false

local function tick()
    ticks = ticks + 1
    if shuttingDown then return end

    local f = io.open(CFG, "r")
    if not f then
        if not warnedNoCfg then
            warnedNoCfg = true
            logf("config.txt not found at %s", CFG)
        end
        return
    end
    local raw = f:read("a") or ""
    f:close()
    warnedNoCfg = false

    if raw ~= lastRaw then
        lastRaw = raw
        local enabled, list = parseConfig(raw)
        rules = (enabled == 0) and {} or list
        lastLog = {}
        logf("config reloaded, %d effect(s) suppressed", #rules)
    end

    if ticks < resumeAtTick then return end

    if (ticks - lastScanTick) >= RESCAN_TICKS then
        lastScanTick = ticks
        cams = findCameras()
    end
end

-- The weight snaps to 1.0 the instant you cross into a zone, so a 1 Hz
-- clamp would let a flash of full red through. This walks a cached list
-- and never searches.
local function fastTick()
    if shuttingDown or ticks < resumeAtTick then return end
    applyRules()
end

local function loop()
    ExecuteWithDelay(TICK_MS, function()
        pcall(tick)
        if not shuttingDown then loop() end
    end)
end

local function fastLoop()
    ExecuteWithDelay(FAST_MS, function()
        pcall(fastTick)
        if not shuttingDown then fastLoop() end
    end)
end

--------------------------------------------------------------------
-- run
--------------------------------------------------------------------
ensureConfig()
logf("loaded")

pcall(RegisterHook, "/Script/Engine.KismetSystemLibrary:QuitGame",
      function() markShutdown("quit") end)
if type(RegisterLoadMapPreHook)  == "function" then pcall(RegisterLoadMapPreHook,  pause) end
if type(RegisterLoadMapPostHook) == "function" then pcall(RegisterLoadMapPostHook, pause) end
RegisterHook("/Script/Engine.PlayerController:ClientRestart", pause)

resumeAtTick = SETTLE_TICKS
loop()
fastLoop()
