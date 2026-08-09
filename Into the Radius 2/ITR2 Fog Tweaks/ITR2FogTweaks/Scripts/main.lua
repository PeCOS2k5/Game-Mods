--=====================================================================
-- ITR2 Fog Tweaks
--
--   Per-map control of Into the Radius 2's global exponential height
--   fog -- the distance haze.
--
--   Settings live in config.txt in this mod's folder and are re-read
--   once a second. Edit while the game is running; changes apply
--   in-world within about a second. No reload, no relaunch.
--
--   Does not touch fog splines, fog walls, swamp fog cards or the fog
--   anomaly -- those are meshes and particles, not this component.
--=====================================================================

local MOD_DIR = "../../Content/Paks/LuaMods/ITR2FogTweaks/"
local CFG     = MOD_DIR .. "config.txt"
local AUTH    = MOD_DIR .. "authored.txt"

local TICK_MS      = 1000
local SETTLE_TICKS = 5      -- quiet period after a map load
local RESCAN_TICKS = 10     -- how often to look for fog actors
local EPS          = 1e-7
local COMP         = "/Script/Engine.ExponentialHeightFogComponent:"

local function logf(fmt, ...)
    local ok, s = pcall(string.format, fmt, ...)
    print("[ITR2FogTweaks] " .. (ok and s or tostring(fmt)) .. "\n")
end

--------------------------------------------------------------------
-- default config, written on first run
--------------------------------------------------------------------
local DEFAULT_CFG = [[
# ITR2 Fog Tweaks - configuration
#
# Re-read once a second while the game runs. Save the file and the
# change applies in-world within about a second. No reload needed.
#
# ---------------------------------------------------------------------
# SECTIONS
#
#   [default]                 applies to every map
#   [Peninsula]               a map, overrides [default]
#   [L_Peninsula_Lighting1]   one lighting sublevel, overrides the map
#
# Valid section names are listed in authored.txt, which this mod writes
# as it meets each map. That file also records the values the game
# itself uses, so you can see what you are scaling.
#
# ---------------------------------------------------------------------
# KEYS      -1 always means "leave this alone"
#
#   enabled              0 = restore the game's own values, change nothing
#   density_mode         scale = multiplier on what the game asks for
#                        abs   = absolute value, ignores the game
#   density              see density_mode
#   density_max          hard ceiling on density, applied after the scale
#   second_density_mode  same, for the game's second fog layer
#   second_density       see second_density_mode
#   max_opacity          0..1 cap on fog opacity at infinite distance.
#                        0.7 keeps distant terrain 30% visible no matter
#                        how thick the fog gets. The most direct control.
#   start_distance_m     metres of clear air before fog starts building
#   volumetric           0 = off, 1 = on
#   vol_extinction       volumetric fog thickness (absolute)
#   extinction_max       hard ceiling on volumetric thickness
#   ab_seconds           >0 alternates the whole mod on and off every N
#                        seconds so you can see the difference in the
#                        headset. Set back to 0 when done. Global.
#
# ---------------------------------------------------------------------
# WHY BOTH A SCALE AND A CEILING
#
# Fog density is not static -- the game's sky controller drives it with
# the time of day and the weather, and during a fog event it multiplies
# by a lot. Measured on one save:
#
#     Peninsula   5.0 normally  ->  35.0 during an event
#     Forest      0.1 normally  ->  30.1
#     Town        0.1 normally  ->  16.2
#
# A multiplier alone cannot bound that: 0.6 x 30.1 is still 18. So
# density is a scale (which preserves the natural variation) and
# density_max is an absolute ceiling that clips only the spikes.
#
# What counts as "thick" is completely map-specific, which is why the
# ceiling belongs in a per-map section.
# ---------------------------------------------------------------------


[default]
enabled             = 1
density_mode        = scale
density             = 0.60
density_max         = 2.00
second_density_mode = scale
second_density      = 0.60
max_opacity         = 0.85
start_distance_m    = -1
volumetric          = -1
vol_extinction      = -1
extinction_max      = -1
ab_seconds          = 0


# Baseline 5.0, spikes to 35.0. The foggiest map in the game.
[Peninsula]
density             = 0.15
density_max         = 1.00
second_density      = 0.30
max_opacity         = 0.70
vol_extinction      = 1.50


# Baseline 0.1, spikes to 30.1. Its volumetric extinction of 9.98 is the
# highest in the game, so the volumetric layer is much of what you feel.
[Forest]
density             = 0.40
density_max         = 1.00
max_opacity         = 0.65
extinction_max      = 3.00


# Outskirts. Baseline 0.1, spikes to 16.2.
[Town]
density             = 0.40
density_max         = 1.00
max_opacity         = 0.65


[School]
density             = 0.30
density_max         = 1.00
max_opacity         = 0.65
extinction_max      = 2.50


# Already essentially fog-free at 0.01 density.
[Hub]
enabled = 0

[MainMenu]
enabled = 0
]]

--------------------------------------------------------------------
-- small helpers
--------------------------------------------------------------------
local function get(obj, name)
    local ok, v = pcall(function() return obj[name] end)
    if ok then return v end
    return nil
end

local function call(obj, fn, ...)
    local args = { ... }
    return pcall(function() return obj[fn](obj, table.unpack(args)) end)
end

local function isReal(obj)
    if not obj then return false end
    local ok, valid = pcall(function() return obj:IsValid() end)
    if not ok or not valid then return false end
    local ok2, full = pcall(function() return obj:GetFullName() end)
    if not ok2 or not full then return false end
    return not full:find("Default__", 1, true)
end

local function mapKeyOf(full)
    return full:match("Levels/_GameplayLevels/([^/]+)/")
        or full:match("Levels/([^/]+)/") or "Unknown"
end

local function subKeyOf(full)
    return full:match("/([^/%.]+)%.[^/%.]+:PersistentLevel") or "Unknown"
end

local function secondDensity(c)
    local ok, v = pcall(function() return c.SecondFogData.FogDensity end)
    if ok then return v end
    return nil
end

--------------------------------------------------------------------
-- the fields this mod controls
--------------------------------------------------------------------
local ORDER = { "density", "second", "maxOpacity", "startDist", "volumetric", "extinction" }

local FIELD = {
    density = {
        read = function(c) return get(c, "FogDensity") end,
        setter = "SetFogDensity",
        target = function(cfg, v)
            local out = v
            if cfg.density >= 0 then
                out = (cfg.density_mode == "abs") and cfg.density or (v * cfg.density)
            end
            if cfg.density_max >= 0 and out > cfg.density_max then out = cfg.density_max end
            if math.abs(out - v) <= EPS then return nil end
            return out
        end,
    },
    second = {
        read = secondDensity,
        setter = "SetSecondFogDensity",
        target = function(cfg, v)
            if cfg.second_density < 0 then return nil end
            local out = (cfg.second_density_mode == "abs")
                        and cfg.second_density or (v * cfg.second_density)
            if math.abs(out - v) <= EPS then return nil end
            return out
        end,
    },
    maxOpacity = {
        read = function(c) return get(c, "FogMaxOpacity") end,
        setter = "SetFogMaxOpacity",
        target = function(cfg, v)
            if cfg.max_opacity < 0 then return nil end
            local out = math.min(v, cfg.max_opacity)
            if math.abs(out - v) <= EPS then return nil end
            return out
        end,
    },
    startDist = {
        read = function(c) return get(c, "StartDistance") end,
        setter = "SetStartDistance",
        target = function(cfg)
            if cfg.start_distance_m < 0 then return nil end
            return cfg.start_distance_m * 100.0        -- UE units are cm
        end,
    },
    volumetric = {
        read = function(c) return get(c, "bEnableVolumetricFog") end,
        setter = "SetVolumetricFog",
        bool = true,
        target = function(cfg)
            if cfg.volumetric < 0 then return nil end
            return cfg.volumetric == 1
        end,
    },
    extinction = {
        read = function(c) return get(c, "VolumetricFogExtinctionScale") end,
        setter = "SetVolumetricFogExtinctionScale",
        target = function(cfg, v)
            local out = v
            if cfg.vol_extinction >= 0 then out = cfg.vol_extinction end
            if cfg.extinction_max >= 0 and out > cfg.extinction_max then
                out = cfg.extinction_max
            end
            if math.abs(out - v) <= EPS then return nil end
            return out
        end,
    },
}

local function differs(field, a, b)
    if a == nil or b == nil then return a ~= b end
    if FIELD[field].bool then return a ~= b end
    return math.abs(a - b) > EPS
end

--------------------------------------------------------------------
-- config
--------------------------------------------------------------------
local DEFAULTS = {
    enabled             = 1,
    density_mode        = "scale",
    density             = -1,
    density_max         = -1,
    second_density_mode = "scale",
    second_density      = -1,
    max_opacity         = -1,
    start_distance_m    = -1,
    volumetric          = -1,
    vol_extinction      = -1,
    extinction_max      = -1,
    ab_seconds          = 0,
}

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
    -- mod folder not writable: fall back to the game's Win64 directory
    CFG, AUTH = "ITR2FogTweaks_config.txt", "ITR2FogTweaks_authored.txt"
    local f2 = io.open(CFG, "r")
    if f2 then f2:close() else
        local w2 = io.open(CFG, "w")
        if w2 then w2:write(DEFAULT_CFG) w2:close() end
    end
    logf("mod folder not writable, using Binaries/Win64/%s", CFG)
end

local function parseConfig(raw)
    local sections, cur = { default = {} }, "default"
    for line in raw:gmatch("[^\r\n]+") do
        local sec = line:match("^%s*%[%s*(.-)%s*%]%s*$")
        if sec then
            cur = sec:lower()
            sections[cur] = sections[cur] or {}
        else
            local k, v = line:match("^%s*([%a_][%w_]*)%s*=%s*(.-)%s*$")
            if k then
                v = v:gsub("%s*[;#].*$", "")
                k = k:lower()
                if DEFAULTS[k] ~= nil then sections[cur][k] = v end
            end
        end
    end
    return sections
end

local function resolve(sections, mapKey, subKey)
    local out = {}
    for k, v in pairs(DEFAULTS) do out[k] = v end
    local function apply(name)
        if not name then return end
        local s = sections[name:lower()]
        if not s then return end
        for k, v in pairs(s) do
            if type(DEFAULTS[k]) == "number" then
                out[k] = tonumber(v) or out[k]
            else
                out[k] = v
            end
        end
    end
    apply("default"); apply(mapKey); apply(subKey)
    return out
end

--------------------------------------------------------------------
-- the game's own values, keyed by lighting sublevel
--------------------------------------------------------------------
-- Persisted so that reloading the mod while fog is already modified does
-- not mistake our own output for the game's intent and compound scaling.
local authored, saveQueued = {}, false

local function loadAuthored()
    local f = io.open(AUTH, "r")
    if not f then return end
    for line in f:lines() do
        if not line:match("^%s*#") then
            local c = {}
            for field in line:gmatch("[^|]+") do c[#c + 1] = field:match("^%s*(.-)%s*$") end
            if #c >= 8 then
                authored[c[2]] = {
                    map = c[1], density = tonumber(c[3]), second = tonumber(c[4]),
                    maxOpacity = tonumber(c[5]), startDist = tonumber(c[6]),
                    volumetric = (c[7] == "1"), extinction = tonumber(c[8]),
                }
            end
        end
    end
    f:close()
end

local function saveAuthored()
    local f = io.open(AUTH, "w")
    if not f then return end
    f:write("# Fog sources this mod has met, with the values the game itself uses.\n")
    f:write("# Columns 1 and 2 are both valid [section] names for config.txt.\n")
    f:write("# map | sublevel | density | second | maxOpacity | startDist | volumetric | extinction\n")
    local keys = {}
    for k in pairs(authored) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local a = authored[k]
        f:write(string.format("%s | %s | %s | %s | %s | %s | %s | %s\n",
            tostring(a.map), k, tostring(a.density), tostring(a.second),
            tostring(a.maxOpacity), tostring(a.startDist),
            a.volumetric and "1" or "0", tostring(a.extinction)))
    end
    f:close()
    saveQueued = false
end

local function rememberAuthored(c, subKey, mapKey)
    if authored[subKey] then
        authored[subKey].map = authored[subKey].map or mapKey
        return
    end
    local a = { map = mapKey }
    for _, n in ipairs(ORDER) do a[n] = FIELD[n].read(c) end
    authored[subKey] = a
    logf("found fog in [%s] / [%s]: density=%s volumetric=%s extinction=%s",
         mapKey, subKey, tostring(a.density), tostring(a.volumetric), tostring(a.extinction))
    saveAuthored()
end

--------------------------------------------------------------------
-- lifecycle
--------------------------------------------------------------------
-- Touching UObjects while a world is being torn down reads freed memory,
-- which pcall cannot catch. So the timer holds still during transitions
-- and stops permanently once the game starts closing.
local shuttingDown, ticks, resumeAtTick = false, 0, 0
local needRescan, lastScanTick, comps = true, -999, {}
local forceOff, abOff, abFlipAt = false, false, 0
local state = {}

local function pause()
    comps, needRescan = {}, true
    resumeAtTick = ticks + SETTLE_TICKS
end

local function markShutdown(why)
    if shuttingDown then return end
    shuttingDown = true
    comps = {}
    logf("shutting down (%s)", why)
end

local function fieldState(subKey, field)
    state[subKey] = state[subKey] or {}
    state[subKey][field] = state[subKey][field] or { wrote = nil, contested = false }
    return state[subKey][field]
end

--------------------------------------------------------------------
-- setter hooks
--------------------------------------------------------------------
-- The sky controller drives FogDensity continuously. Writing it from a
-- timer just produces a flicker at the timer's period: we set it, the
-- controller sets it back. Instead we hook the component's setters and
-- transform the value in flight, so the controller's own write arrives
-- already scaled and the time-of-day variation survives intact.
local cachedCfg, inOurWrite = {}, false

local function installHook(field)
    local spec = FIELD[field]
    local ok = pcall(RegisterHook, COMP .. spec.setter, function(Context, Param)
        if inOurWrite or shuttingDown then return end
        pcall(function()
            local c = Context:get()
            if not isReal(c) then return end
            local subKey = subKeyOf(c:GetFullName())
            local cfg = cachedCfg[subKey]
            if not cfg or cfg.enabled == 0 then return end

            local incoming = Param:get()
            if incoming == nil then return end

            if authored[subKey] and differs(field, authored[subKey][field], incoming) then
                authored[subKey][field] = incoming
                saveQueued = true
            end

            local out = spec.target(cfg, incoming)
            if out ~= nil and differs(field, out, incoming) then
                Param:set(out)
                fieldState(subKey, field).wrote = out
            end
        end)
    end)
    if not ok then logf("could not hook %s", spec.setter) end
end

--------------------------------------------------------------------
-- apply
--------------------------------------------------------------------
local function applyTo(c, sections)
    local full   = c:GetFullName()
    local mapKey = mapKeyOf(full)
    local subKey = subKeyOf(full)

    rememberAuthored(c, subKey, mapKey)

    local cfg = resolve(sections, mapKey, subKey)
    if forceOff or abOff then cfg.enabled = 0 end
    cachedCfg[subKey] = cfg

    inOurWrite = true

    if cfg.enabled == 0 then
        local a, st, n = authored[subKey], state[subKey], 0
        if a and st then
            for _, field in ipairs(ORDER) do
                if st[field] and st[field].wrote ~= nil then
                    if a[field] ~= nil then call(c, FIELD[field].setter, a[field]) end
                    st[field].wrote, st[field].contested = nil, false
                    n = n + 1
                end
            end
        end
        if n > 0 then logf("[%s] off, restored %d field(s)", subKey, n) end
        inOurWrite = false
        return
    end

    for _, field in ipairs(ORDER) do
        local spec, fs = FIELD[field], fieldState(subKey, field)
        local live = spec.read(c)
        if live ~= nil then
            -- did the game overwrite us since last tick?
            if fs.wrote ~= nil and differs(field, live, fs.wrote) then
                fs.contested = true       -- leave it to the setter hook
                if authored[subKey] then
                    authored[subKey][field] = live
                    saveQueued = true
                end
            end
            if not fs.contested then
                local base   = (authored[subKey] and authored[subKey][field]) or live
                local target = spec.target(cfg, base)
                if target ~= nil and differs(field, live, target) then
                    if call(c, spec.setter, target) then
                        fs.wrote = target
                    elseif field == "second" then
                        pcall(function() c.SecondFogData.FogDensity = target end)
                        pcall(function() c:MarkRenderStateDirty() end)
                        fs.wrote = target
                    end
                end
            end
        end
    end

    inOurWrite = false
end

--------------------------------------------------------------------
-- tick
--------------------------------------------------------------------
local lastRaw, warnedNoCfg = nil, false

local function findFog()
    local out = {}
    local ok, list = pcall(FindAllOf, "ExponentialHeightFogComponent")
    if ok and list then
        for _, c in ipairs(list) do
            if isReal(c) then out[#out + 1] = c end
        end
    end
    if #out == 0 then
        local ok2, actors = pcall(FindAllOf, "BP_ITRExponentialHeightFog_C")
        if ok2 and actors then
            for _, a in ipairs(actors) do
                if isReal(a) then
                    local c = get(a, "Component")
                    if isReal(c) then out[#out + 1] = c end
                end
            end
        end
    end
    return out
end

-- Cached rather than searched every second: FindAllOf walks the whole
-- object array, which is wasteful at 1 Hz and unsafe during teardown.
local function refreshComps()
    local alive = {}
    for _, c in ipairs(comps) do
        if isReal(c) then alive[#alive + 1] = c else needRescan = true end
    end
    comps = alive
    if needRescan or (ticks - lastScanTick) >= RESCAN_TICKS then
        lastScanTick, needRescan = ticks, false
        comps = findFog()
    end
end

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
        lastRaw, state = raw, {}
        logf("config reloaded")
    end

    if ticks < resumeAtTick then return end

    local sections = parseConfig(raw)

    local ab = tonumber((sections.default or {}).ab_seconds or 0) or 0
    if ab > 0 then
        if (ticks - abFlipAt) >= ab then
            abFlipAt, abOff, state = ticks, not abOff, {}
            logf("A/B: fog mod is now %s", abOff and "OFF" or "ON")
        end
    elseif abOff then
        abOff, state = false, {}
    end

    refreshComps()
    for _, c in ipairs(comps) do
        if not isReal(c) then needRescan = true break end
        applyTo(c, sections)
    end

    if saveQueued then saveAuthored() end
end

--------------------------------------------------------------------
-- run
--------------------------------------------------------------------
local function loop()
    ExecuteWithDelay(TICK_MS, function()
        pcall(tick)
        if not shuttingDown then loop() end
    end)
end

ensureConfig()
loadAuthored()
logf("loaded")

for _, field in ipairs(ORDER) do installHook(field) end

-- Manual A/B toggle. UE4SS keybinds only register when the game's
-- desktop window has focus, so ab_seconds is the practical one in VR.
if type(RegisterKeyBind) == "function" and type(Key) == "table" and Key.F8 then
    pcall(RegisterKeyBind, Key.F8, function()
        forceOff, state = not forceOff, {}
        logf("F8: fog mod is now %s", forceOff and "OFF" or "ON")
    end)
end

pcall(RegisterHook, "/Script/Engine.KismetSystemLibrary:QuitGame",
      function() markShutdown("quit") end)
if type(RegisterLoadMapPreHook)  == "function" then pcall(RegisterLoadMapPreHook,  pause) end
if type(RegisterLoadMapPostHook) == "function" then pcall(RegisterLoadMapPostHook, pause) end
RegisterHook("/Script/Engine.PlayerController:ClientRestart", function()
    state = {}
    pause()
end)

resumeAtTick = SETTLE_TICKS
loop()
