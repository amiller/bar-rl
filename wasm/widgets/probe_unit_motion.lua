-- Per-frame probe of selected unit IDs for divergence hunting.
-- Dumps full motion state to ./unit_probe.jsonl in the engine's write-dir.
-- Companion to state_dump.lua: does not interfere with that widget's output.

function widget:GetInfo()
    return {
        name    = "Unit Motion Probe",
        desc    = "Per-frame full-precision state dump for selected unit IDs",
        author  = "claude",
        date    = "2026-04-24",
        layer   = 1,
        enabled = true,
    }
end

-- Track these unit IDs every sim frame at full precision. Hand-picked ones
-- are tracked to MAX_FRAME; in WIDE mode we also track all units to WIDE_FRAME
-- to find the earliest divergent unit during the engine-checksum-desync window.
local TRACK = { [12910]=true, [27295]=true, [30611]=true }
local MAX_FRAME = 1500
local WIDE_FRAME = 200   -- track all units up to this frame
local WIDE = true        -- set false to disable wide-tracking

local fh
local sfmt = string.format
local spGetUnitPosition     = Spring.GetUnitPosition
local spGetUnitHeading      = Spring.GetUnitHeading
local spGetUnitVelocity     = Spring.GetUnitVelocity
local spGetUnitDirection    = Spring.GetUnitDirection
local spGetUnitMoveTypeData = Spring.GetUnitMoveTypeData
local spGetUnitCurrentCommand = Spring.GetUnitCurrentCommand
local spValidUnitID         = Spring.ValidUnitID

function widget:Initialize()
    fh = io.open("unit_probe.jsonl", "w")
    if not fh then
        Spring.Echo("[probe] could not open unit_probe.jsonl")
        widgetHandler:RemoveWidget(self); return
    end
    fh:setvbuf("line")
    Spring.Echo("[probe] tracking uids: 12910, 27295, 30611")
end

function widget:Shutdown()
    if fh then fh:close() end
end

local function dump_mt(uid)
    local mt = spGetUnitMoveTypeData(uid)
    if not mt then return '{}' end
    return sfmt(
      '{"gx":%.6f,"gz":%.6f,"gR":%.4f,"aG":%s,"aEoP":%s,"cs":%.6f,"ws":%.6f,"ms":%.4f,"tr":%d,"hdg":%d,"wH":%d}',
      mt.goalx or 0, mt.goalz or 0, mt.goalRadius or 0,
      tostring(mt.atGoal or false), tostring(mt.atEndOfPath or false),
      mt.currentSpeed or 0, mt.wantedSpeed or 0, mt.maxSpeed or 0,
      mt.turnRate or 0, mt.heading or 0, mt.wantedHeading or 0)
end

local spGetAllUnits = Spring.GetAllUnits
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitTeam = Spring.GetUnitTeam
local spGetTeamResources = Spring.GetTeamResources
local spGetUnitBuildParams = Spring.GetUnitIsBeingBuilt -- placeholder
local spGetUnitHealthFull = Spring.GetUnitHealth
local spGetGameRulesParam = Spring.GetGameRulesParam
local spGetTeamList = Spring.GetTeamList

local function dump_full(f, uid)
    local x, y, z = spGetUnitPosition(uid)
    if not x then return end
    local hdg = spGetUnitHeading(uid) or 0
    local vx, vy, vz = spGetUnitVelocity(uid)
    local fx, fy, fz = spGetUnitDirection(uid)
    local cmdID = spGetUnitCurrentCommand(uid)
    fh:write(sfmt(
      '{"f":%d,"u":%d,"p":[%.6f,%.6f,%.6f],"h":%d,"v":[%.6f,%.6f,%.6f],"d":[%.6f,%.6f,%.6f],"cmd":%s,"mt":%s}\n',
      f, uid, x, y, z, hdg, vx or 0, vy or 0, vz or 0,
      fx or 0, fy or 0, fz or 0,
      tostring(cmdID or "null"), dump_mt(uid)))
end

local function dump_compact(f, uid)
    -- Wide-coverage mode — pos/vel/heading + health/build for sync diagnosis.
    local x, y, z = spGetUnitPosition(uid)
    if not x then return end
    local hdg = spGetUnitHeading(uid) or 0
    local vx, _, vz = spGetUnitVelocity(uid)
    local hp, maxHp, paralyze, capture, build = spGetUnitHealthFull(uid)
    fh:write(sfmt(
      '{"f":%d,"u":%d,"def":%d,"t":%d,"p":[%.6f,%.6f,%.6f],"h":%d,"v":[%.6f,%.6f],"hp":%.3f,"mhp":%.3f,"par":%.3f,"cap":%.3f,"bld":%.6f}\n',
      f, uid, spGetUnitDefID(uid) or 0, spGetUnitTeam(uid) or -1,
      x, y, z, hdg, vx or 0, vz or 0,
      hp or 0, maxHp or 0, paralyze or 0, capture or 0, build or 0))
end

local function dump_resources(f)
    local teams = spGetTeamList()
    local parts = {}
    for i = 1, #teams do
        local t = teams[i]
        local m, ms, mp, mi, me, mr, ms2, mr2 = spGetTeamResources(t, "metal")
        local e, es, ep, ei, ee, er, es2, er2 = spGetTeamResources(t, "energy")
        parts[#parts+1] = sfmt('"%d":[%.4f,%.4f,%.4f,%.4f,%.4f,%.4f]',
            t, m or 0, e or 0, mi or 0, ei or 0, me or 0, ee or 0)
    end
    fh:write(sfmt('{"f":%d,"R":{%s}}\n', f, table.concat(parts, ",")))
end

function widget:GameFrame(f)
    if not fh then return end
    if f <= MAX_FRAME then
        for uid in pairs(TRACK) do
            if spValidUnitID(uid) then dump_full(f, uid) end
        end
    end
    if WIDE and f <= WIDE_FRAME then
        local units = spGetAllUnits()
        for i = 1, #units do
            local uid = units[i]
            if not TRACK[uid] then dump_compact(f, uid) end
        end
        dump_resources(f)
    end
end
