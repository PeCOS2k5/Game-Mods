--=====================================================================
-- ITR2 NVG Field of View
--
--   Widens the visible circle of Into the Radius 2's night vision
--   goggles, per device, by a percentage you choose.
--
--   Each pair of goggles is a post process material instance on the
--   player camera, and the size of the visible area is its "Radius"
--   scalar parameter. PVS-7 and PVS-31 set it explicitly; GPNVG-18 does
--   not, and inherits the material's default, so for that one the mod
--   repurposes an inert parameter slot to create the override.
--
--   Settings live in config.txt in this mod's folder and are re-read
--   once a second. Changes apply as soon as the goggles are on.
--=====================================================================

local MOD_DIR = "../../Content/Paks/LuaMods/ITR2NVGFieldOfView/"
local CFG     = MOD_DIR .. "config.txt"
local STOCK   = MOD_DIR .. "stock.txt"

local TICK_MS      = 1000
local SETTLE_TICKS = 5
local RESCAN_TICKS = 10
local MATCH        = "nightvision"
local PARAM        = "Radius"
local DONOR        = "RefractionDepthBias"   -- inert on every instance

local function logf(fmt, ...)
    local ok, s = pcall(string.format, fmt, ...)
    print("[ITR2NVGFieldOfView] " .. (ok and s or tostring(fmt)) .. "\n")
end

--------------------------------------------------------------------
-- default config
--------------------------------------------------------------------
local DEFAULT_CFG = [[
# ITR2 NVG Field of View - configuration
#
# Re-read once a second while the game runs. Save the file and the
# change applies as soon as the goggles are on. No reload needed.
#
# ---------------------------------------------------------------------
#   extend    percent of the stock RADIUS PARAMETER. 100 = unchanged.
#   enabled   0 leaves that device completely stock
#   base      only needed where the game does not expose a stock value.
#             See the GPNVG note below.
#
# IMPORTANT - extend is not a percentage of what you see.
#
# It scales the material's radius parameter, and the visible area grows
# far more slowly than that number. 150 read as only about 15 percent
# more image, which is why the shipped values are in the 180-300 range
# rather than near 100.
#
# So move in big steps. Changing 260 to 275 will do almost nothing;
# 260 to 350 is a real difference. If an edit looks like it had no
# effect, it was probably too small rather than broken.
#
# Sections are per device. Stock values measured in game:
#
#     PVS-7    Radius 0.100
#     PVS-31   Radius 0.126
#     GPNVG    not exposed - the material uses its own internal default
#     PVS-14   not supported, see below
# ---------------------------------------------------------------------

[default]
enabled = 1
extend  = 300


# Single tube. Stock radius 0.100 -> 0.260 at 260.
[PVS7]
extend = 260


# Dual tube. Stock radius 0.126 -> 0.227 at 180.
[PVS31]
extend = 180


# Quad tube panoramic.
#
# This one never sets a radius of its own, so there is no stock value to
# take a percentage of - the mod creates the override from scratch, and
# "base" is what 100 refers to. 0.126 is borrowed from the dual tube, so
# the shipped 280 works out to a radius of 0.353.
#
# Because base is a stand-in rather than a measurement, GPNVG's
# percentage is not comparable to the other two. Judge it by eye.
[GPNVG]
base   = 0.126
extend = 280


# Single tube monocular. Its material ignores the radius parameter and
# no working control has been found, so it is left alone.
[PVS14]
enabled = 0
]]

--------------------------------------------------------------------
-- helpers
--------------------------------------------------------------------
local function isReal(o)
    if not o then return false end
    local ok, v = pcall(function() return o:IsValid() end)
    if not ok or not v then return false end
    local ok2, f = pcall(function() return o:GetFullName() end)
    return ok2 and f and not f:find("Default__", 1, true)
end

local function shortName(o)
    local n = "?"
    pcall(function() n = o:GetFullName():gsub(".*[%./]", "") end)
    return n
end

-- MI_PP_NightVision_GPNVG      -> GPNVG
-- MI_PP_NightVision_PVS31_Spec -> PVS31   (spectator twin shares settings)
-- MI_PP_NightVision            -> BASE
local function deviceOf(name)
    local d = name:match("^MI_PP_NightVision_(.+)$")
    if not d then return "BASE" end
    return (d:gsub("_[Ss]pec$", ""))
end

--------------------------------------------------------------------
-- config
--------------------------------------------------------------------
local DEFAULTS = { enabled = 1, extend = 100, base = -1 }

local function ensureCfg()
    local f = io.open(CFG, "r")
    if f then f:close() return end
    local w = io.open(CFG, "w")
    if w then w:write(DEFAULT_CFG) w:close() logf("created %s", CFG) return end
    CFG, STOCK = "ITR2NVGFieldOfView_config.txt", "ITR2NVGFieldOfView_stock.txt"
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
                if DEFAULTS[k] ~= nil then sections[cur][k] = tonumber(v) end
            end
        end
    end
    return sections
end

local function resolve(sections, device)
    local out = {}
    for k, v in pairs(DEFAULTS) do out[k] = v end
    for _, name in ipairs({ "default", device:lower() }) do
        local s = sections[name]
        if s then for k, v in pairs(s) do if v then out[k] = v end end end
    end
    return out
end

--------------------------------------------------------------------
-- stock values
--------------------------------------------------------------------
-- Remembered so that reloading the mod does not read our own widened
-- value back as the stock one and compound the percentage.
local stock, stockDirty = {}, false

local function loadStock()
    local f = io.open(STOCK, "r")
    if not f then return end
    for line in f:lines() do
        local k, v = line:match("^%s*([%w_]+)%s*=%s*([%d%.]+)")
        if k and v then stock[k] = tonumber(v) end
    end
    f:close()
end

local function saveStock()
    local f = io.open(STOCK, "w")
    if not f then return end
    f:write("# Stock view radius per device, remembered so percentages\n")
    f:write("# stay stable across reloads. Delete to re-learn.\n")
    local keys = {}
    for k in pairs(stock) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do f:write(string.format("%s = %s\n", k, tostring(stock[k]))) end
    f:close()
    stockDirty = false
end

--------------------------------------------------------------------
-- lifecycle
--------------------------------------------------------------------
local shuttingDown, ticks, resumeAt = false, 0, 0
local cams, lastScan = {}, -999
local applied = {}

local function pause()
    cams, lastScan = {}, -999
    resumeAt = ticks + SETTLE_TICKS
end

local function findCameras()
    local out = {}
    local ok, list = pcall(FindAllOf, "CameraComponent")
    if ok and list then
        for _, c in ipairs(list) do if isReal(c) then out[#out + 1] = c end end
    end
    return out
end

--------------------------------------------------------------------
-- applying
--------------------------------------------------------------------
-- Returns the array entry named `want`, or repurposes the inert donor
-- entry if `want` is not overridden on this instance. GPNVG needs this:
-- it inherits the material's default radius and has no entry of its own.
local function findOrCreateEntry(obj, want)
    local hit, donor = nil, nil
    pcall(function()
        obj.ScalarParameterValues:ForEach(function(_, pe)
            if hit then return end
            local n = tostring(pe:get().ParameterInfo.Name:ToString())
            if n:lower() == want:lower() then hit = pe
            elseif n:lower() == DONOR:lower() then donor = pe end
        end)
    end)
    if hit then return hit, false end
    if not donor then return nil, false end
    local ok = pcall(function() donor:get().ParameterInfo.Name = FName(want) end)
    if not ok then return nil, false end
    return donor, true
end

local function applyTo(obj, sections)
    local name   = shortName(obj)
    local device = deviceOf(name)
    if device == "BASE" then return end

    local cfg = resolve(sections, device)
    if cfg.enabled == 0 then return end

    local entry, created = findOrCreateEntry(obj, PARAM)
    if not entry then
        if not applied[name .. "fail"] then
            applied[name .. "fail"] = true
            logf("%s: no '%s' parameter and no '%s' slot to use", name, PARAM, DONOR)
        end
        return
    end

    -- establish the stock value once, then never re-read it
    if stock[device] == nil then
        if created then
            if cfg.base < 0 then
                if not applied[name .. "nobase"] then
                    applied[name .. "nobase"] = true
                    logf("%s: this device needs a 'base' value in config.txt", name)
                end
                return
            end
            stock[device] = cfg.base
        else
            local v = nil
            pcall(function() v = entry:get().ParameterValue end)
            if not v then return end
            stock[device] = v
        end
        stockDirty = true
        logf("%s: stock radius %s", device, tostring(stock[device]))
    end

    local target = stock[device] * (cfg.extend / 100.0)
    local cur = nil
    pcall(function() cur = entry:get().ParameterValue end)
    if cur and math.abs(cur - target) > 1e-5 then
        pcall(function() entry:get().ParameterValue = target end)
        local key = name .. string.format("%.4f", target)
        if not applied[key] then
            applied[key] = true
            logf("%s: %s %s -> %.4f  (%d%%)", device, PARAM,
                 tostring(stock[device]), target, math.floor(cfg.extend))
        end
    end
end

--------------------------------------------------------------------
-- loop
--------------------------------------------------------------------
local lastRaw, warned = nil, false
local sections = nil

local function tick()
    ticks = ticks + 1
    if shuttingDown then return end

    local f = io.open(CFG, "r")
    if not f then
        if not warned then warned = true logf("config.txt not found at %s", CFG) end
        return
    end
    local raw = f:read("a") or ""
    f:close()
    warned = false

    if raw ~= lastRaw then
        lastRaw  = raw
        sections = parseConfig(raw)
        applied  = {}
        logf("config reloaded")
    end
    if not sections then return end
    if ticks < resumeAt then return end

    if (ticks - lastScan) >= RESCAN_TICKS then
        lastScan = ticks
        cams = findCameras()
    end

    for _, cam in ipairs(cams) do
        if isReal(cam) then
            pcall(function()
                cam.PostProcessSettings.WeightedBlendables.Array:ForEach(function(_, elem)
                    local wb  = elem:get()
                    local obj = nil
                    pcall(function() obj = wb.Object end)
                    if not (obj and isReal(obj)) then return end
                    if not obj:GetFullName():lower():find(MATCH, 1, true) then return end
                    applyTo(obj, sections)
                end)
            end)
        end
    end

    if stockDirty then saveStock() end
end

local function loop()
    ExecuteWithDelay(TICK_MS, function()
        pcall(tick)
        if not shuttingDown then loop() end
    end)
end

ensureCfg()
loadStock()
logf("loaded")

pcall(RegisterHook, "/Script/Engine.KismetSystemLibrary:QuitGame",
      function() shuttingDown = true end)
if type(RegisterLoadMapPreHook)  == "function" then pcall(RegisterLoadMapPreHook,  pause) end
if type(RegisterLoadMapPostHook) == "function" then pcall(RegisterLoadMapPostHook, pause) end
RegisterHook("/Script/Engine.PlayerController:ClientRestart", pause)

resumeAt = SETTLE_TICKS
loop()
