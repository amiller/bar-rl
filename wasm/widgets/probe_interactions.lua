-- Per-frame interaction log: damage dealt, units created/destroyed, commands
-- issued. Run on both native and WASM builds of the same demo so the JSONLs
-- can be diffed line-by-line. Catches interaction-level divergence that the
-- coarse outcome.jsonl misses (e.g. "WASM lost the same battle 8 seconds
-- later, with 4 fewer units lost on each side").
--
-- Output: ./interactions.jsonl in engine write-dir.
-- Each line is one event with: frame, kind, plus event-specific fields.

function widget:GetInfo()
    return {
        name    = "Interactions Probe",
        desc    = "Logs damage/death/spawn/command events for native-vs-WASM diffing",
        author  = "claude",
        date    = "2026-04-25",
        layer   = 4,
        enabled = true,
    }
end

local fh
local sfmt = string.format
local spGetGameFrame = Spring.GetGameFrame
local spGetUnitDefID = Spring.GetUnitDefID

-- Throttle: damage events fire ~thousands/frame in late game. We bucket by
-- (attackerTeam, victimTeam) per frame and only write the bucket totals.
-- Set DAMAGE_FULL=1 to log every individual UnitDamaged call (much bigger).
local DAMAGE_FULL = false
local damageBuckets = {}  -- key "atkTeam:vicTeam" → {dmg, hits}
local damageFrame = -1

local function flushDamageBuckets(f)
    if next(damageBuckets) == nil then return end
    for k, v in pairs(damageBuckets) do
        local atk, vic = k:match("(-?%d+):(-?%d+)")
        fh:write(sfmt(
          '{"f":%d,"k":"dmg_bucket","atk_t":%s,"vic_t":%s,"dmg":%.2f,"hits":%d}\n',
          f, atk, vic, v.dmg, v.hits))
    end
    damageBuckets = {}
end

function widget:Initialize()
    fh = io.open("interactions.jsonl", "w")
    if not fh then
        Spring.Echo("[interactions] could not open interactions.jsonl")
        widgetHandler:RemoveWidget(self); return
    end
    fh:setvbuf("line")
    fh:write(sfmt('{"f":0,"k":"start","damage_full":%s}\n', tostring(DAMAGE_FULL)))
    Spring.Echo("[interactions] writing to interactions.jsonl")
end

function widget:UnitCreated(uid, defId, team, builderID)
    if not fh then return end
    fh:write(sfmt(
      '{"f":%d,"k":"create","uid":%d,"def":%d,"t":%d,"by":%d}\n',
      spGetGameFrame() or 0, uid, defId, team or -1, builderID or -1))
end

function widget:UnitFinished(uid, defId, team)
    if not fh then return end
    fh:write(sfmt(
      '{"f":%d,"k":"finish","uid":%d,"def":%d,"t":%d}\n',
      spGetGameFrame() or 0, uid, defId, team or -1))
end

function widget:UnitDestroyed(uid, defId, team, attackerID, attackerDefID, attackerTeam)
    if not fh then return end
    fh:write(sfmt(
      '{"f":%d,"k":"destroy","uid":%d,"def":%d,"t":%d,"atk_uid":%d,"atk_def":%d,"atk_t":%d}\n',
      spGetGameFrame() or 0, uid, defId, team or -1,
      attackerID or -1, attackerDefID or -1, attackerTeam or -1))
end

function widget:UnitDamaged(uid, defId, team, damage, paralyzer, weaponDefID, projectileID, attackerID, attackerDefID, attackerTeam)
    if not fh then return end
    local f = spGetGameFrame() or 0
    if DAMAGE_FULL then
        fh:write(sfmt(
          '{"f":%d,"k":"damage","uid":%d,"def":%d,"t":%d,"dmg":%.2f,"par":%s,"atk_t":%d,"atk_def":%d}\n',
          f, uid, defId, team or -1, damage, paralyzer ~= 0 and "true" or "false",
          attackerTeam or -1, attackerDefID or -1))
        return
    end
    if f ~= damageFrame then
        flushDamageBuckets(damageFrame)
        damageFrame = f
    end
    local k = (attackerTeam or -1) .. ":" .. (team or -1)
    local b = damageBuckets[k]
    if b then b.dmg = b.dmg + damage; b.hits = b.hits + 1
    else damageBuckets[k] = {dmg=damage, hits=1} end
end

function widget:GameFrame(f)
    if not fh then return end
    if not DAMAGE_FULL and damageFrame > 0 and f ~= damageFrame then
        flushDamageBuckets(damageFrame)
        damageFrame = f
    end
end

function widget:Shutdown()
    if fh then
        flushDamageBuckets(damageFrame)
        fh:write(sfmt('{"f":%d,"k":"shutdown"}\n', spGetGameFrame() or 0))
        fh:close()
    end
end
