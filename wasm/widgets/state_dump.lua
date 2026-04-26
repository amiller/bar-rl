-- Minimal state dump widget for Recoil/BAR headless replay playback.
-- Writes one JSONL record per frame (downsampled) to ./state_trace.jsonl
-- relative to the engine's write-dir (so the sandbox captures it).

function widget:GetInfo()
    return {
        name    = "State Dump",
        desc    = "Dump per-frame unit state to JSONL for offline viewers/diffing",
        author  = "claude",
        date    = "2026-04-24",
        layer   = 0,
        enabled = true,
    }
end

local SAMPLE_EVERY = 6   -- 30fps sim / 6 = 5 snapshots/sec
local OUT_PATH     = "state_trace.jsonl"

local fh
local spGetAllUnits     = Spring.GetAllUnits
local spGetUnitPosition = Spring.GetUnitPosition
local spGetUnitTeam     = Spring.GetUnitTeam
local spGetUnitHealth   = Spring.GetUnitHealth
local spGetUnitDefID    = Spring.GetUnitDefID
local spGetUnitHeading  = Spring.GetUnitHeading
-- Projectiles: in widget (unsynced) GetVisibleProjectiles needs an allyTeam
-- argument; -1 (or no arg) returns all visible. Replay/spectator mode sees
-- everything so this gives us the full set.
local spGetVisibleProjectiles = Spring.GetVisibleProjectiles
local spGetProjectilePosition = Spring.GetProjectilePosition
local spGetProjectileVelocity = Spring.GetProjectileVelocity
local spGetProjectileTeamID   = Spring.GetProjectileTeamID
local spGetProjectileType     = Spring.GetProjectileType
local sfmt              = string.format
local tconcat           = table.concat

local function w(line)
    if not fh then return end
    fh:write(line); fh:write("\n")
end

local function meta_record()
    local defs = {}
    for id, d in pairs(UnitDefs) do
        defs[tostring(id)] = sfmt('{"n":"%s","r":%d}', d.name or "?", math.floor((d.radius or 16) + 0.5))
    end
    local parts = {}
    for k, v in pairs(defs) do parts[#parts+1] = sfmt('"%s":%s', k, v) end
    -- mapName is the scriptName (e.g. "Great Divide V1"), keyed by the public
    -- maps-metadata CDN: viewers can fetch the minimap thumbnail from it directly.
    return sfmt('{"t":"meta","mapName":"%s","mapX":%d,"mapZ":%d,"defs":{%s}}',
        (Game.mapName or ""):gsub('"', "'"),
        Game.mapSizeX or 0, Game.mapSizeZ or 0, tconcat(parts, ","))
end

function widget:Initialize()
    fh = io.open(OUT_PATH, "w")
    if not fh then
        Spring.Echo("[state_dump] could not open " .. OUT_PATH)
        widgetHandler:RemoveWidget(self); return
    end
    fh:setvbuf("line")   -- critical: flush on every newline so the file is always consistent
    w(meta_record())
    Spring.Echo("[state_dump] writing to " .. OUT_PATH)
end

function widget:Shutdown()
    if fh then fh:close() end
end

-- Headless spring keeps simulating after the demo file runs out, so the
-- process never exits on its own. Quit on GameOver (normal end) and also
-- detect the "nothing happening anymore" case: if the unit count is stable
-- and no frames have been added for a while, we're past the demo.
local lastUnitCount, stableFrames = -1, 0
local STABLE_EXIT_FRAMES = 30 * 60 * 2   -- 2 sim-minutes of no change → quit

function widget:GameOver(winners)
    Spring.Echo("[state_dump] GameOver; quitting"); Spring.Quit()
end

function widget:GameFrame(f)
    if f % SAMPLE_EVERY ~= 0 then return end
    local units = spGetAllUnits()
    -- Detect stall past demo end: unit-count frozen for STABLE_EXIT_FRAMES frames.
    if #units == lastUnitCount then
        stableFrames = stableFrames + SAMPLE_EVERY
        if stableFrames > STABLE_EXIT_FRAMES and f > 30 * 30 then  -- min 30s of match
            Spring.Echo(sfmt("[state_dump] stalled at frame %d; quitting", f))
            Spring.Quit()
        end
    else
        stableFrames = 0; lastUnitCount = #units
    end
    local parts = {}
    for i = 1, #units do
        local uid = units[i]
        local x, y, z = spGetUnitPosition(uid)
        if x then
            local hp, maxHp = spGetUnitHealth(uid)
            local pct = (hp and maxHp and maxHp > 0) and math.floor(hp / maxHp * 100) or 0
            -- 7th = terrain-y so 3D viewers can lift the model off the plane.
            -- 8th = heading (signed short, -32768..32767, *(pi/32768) = radians).
            parts[#parts+1] = sfmt("[%d,%d,%d,%.1f,%.1f,%d,%.1f,%d]",
                uid, spGetUnitTeam(uid) or -1, spGetUnitDefID(uid) or 0,
                x, z, pct, y or 0, spGetUnitHeading(uid) or 0)
        end
    end
    w(sfmt('{"t":"f","f":%d,"u":[%s]}', f, tconcat(parts, ",")))

    -- Projectiles: separate "p" event per frame. Each entry is
    --   [pid, team, x, y, z, vx, vz, type_int]
    -- type_int compresses common Spring projectile-type strings to small ints
    -- so the trace stays compact (a frame with 200 projectiles is fine).
    local projs = spGetVisibleProjectiles and spGetVisibleProjectiles(-1)
    if projs and #projs > 0 then
        local pp = {}
        for i = 1, #projs do
            local pid = projs[i]
            local x, y, z = spGetProjectilePosition(pid)
            if x then
                local vx, vy, vz = spGetProjectileVelocity(pid)
                local pt = spGetProjectileType(pid) or ""
                local typeInt = (pt == "missile") and 1
                             or (pt == "weapon")  and 2
                             or (pt == "piece")   and 3
                             or 0
                pp[#pp+1] = sfmt("[%d,%d,%.1f,%.1f,%.1f,%.2f,%.2f,%d]",
                    pid, spGetProjectileTeamID(pid) or -1,
                    x, y or 0, z, vx or 0, vz or 0, typeInt)
            end
        end
        if #pp > 0 then
            w(sfmt('{"t":"p","f":%d,"p":[%s]}', f, tconcat(pp, ",")))
        end
    end
end

function widget:UnitCreated(uid, defId, team)
    if not fh then return end
    w(sfmt('{"t":"c","uid":%d,"def":%d,"team":%d}', uid, defId, team))
end

function widget:UnitDestroyed(uid, defId, team)
    if not fh then return end
    w(sfmt('{"t":"d","uid":%d}', uid))
end
