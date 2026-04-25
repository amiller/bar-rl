-- Outcome instrumentation: log GameOver winner + final per-team unit/resource
-- summary at the moment the game ends. Used to compare end-of-replay outcome
-- between native engine and our WASM port — even if mid-game state diverges,
-- we want the same WINNER and same overall trajectory.
--
-- Output: ./outcome.jsonl in the engine's write-dir.

function widget:GetInfo()
    return {
        name    = "Outcome Recorder",
        desc    = "Logs GameOver + final per-team summary for native-vs-WASM diffing",
        author  = "claude",
        date    = "2026-04-25",
        layer   = 3,
        enabled = true,
    }
end

local fh
local sfmt = string.format

local spGetTeamList     = Spring.GetTeamList
local spGetTeamUnits    = Spring.GetTeamUnits
local spGetTeamResources= Spring.GetTeamResources
local spIsGameOver      = Spring.IsGameOver
local spGetGameFrame    = Spring.GetGameFrame
local spGetTeamLuaAI    = Spring.GetTeamLuaAI
local spGetTeamInfo     = Spring.GetTeamInfo
local spGetUnitDefID    = Spring.GetUnitDefID

-- Commander defIds to watch for (BAR-specific). When one of these dies, we
-- log a commander_death event — that's the ctrl-K / killed-by-enemy moment
-- that actually decides the game in BAR.
local COMMANDER_DEFS = {
    armcom = true, corcom = true, legcom = true,
    armcomnew = true,
}
local commanderDefIds = nil  -- resolved at game start (UnitDefs is available there)

local function team_summary(t)
    local units = spGetTeamUnits(t) or {}
    local m, _, _, mi, me = spGetTeamResources(t, "metal")
    local e, _, _, ei, ee = spGetTeamResources(t, "energy")
    -- Bucket units by defID so we can see broad composition.
    local by_def = {}
    for i = 1, #units do
        local did = Spring.GetUnitDefID(units[i]) or 0
        by_def[did] = (by_def[did] or 0) + 1
    end
    local def_parts = {}
    for did, c in pairs(by_def) do
        def_parts[#def_parts+1] = sfmt('"%d":%d', did, c)
    end
    return sfmt(
      '{"t":%d,"units":%d,"m":%.2f,"e":%.2f,"mi":%.4f,"ei":%.4f,"me":%.4f,"ee":%.4f,"defs":{%s}}',
      t, #units, m or 0, e or 0, mi or 0, ei or 0, me or 0, ee or 0,
      table.concat(def_parts, ","))
end

local function dump(label, winners)
    local f = spGetGameFrame() or 0
    local teams = spGetTeamList() or {}
    local team_strs = {}
    for i = 1, #teams do
        team_strs[#team_strs+1] = team_summary(teams[i])
    end
    local winners_str = "[]"
    if winners then
        local parts = {}
        for i = 1, #winners do parts[#parts+1] = tostring(winners[i]) end
        winners_str = "[" .. table.concat(parts, ",") .. "]"
    end
    fh:write(sfmt('{"event":"%s","frame":%d,"winners":%s,"teams":[%s]}\n',
        label, f, winners_str, table.concat(team_strs, ",")))
end

function widget:Initialize()
    fh = io.open("outcome.jsonl", "w")
    if not fh then
        Spring.Echo("[outcome] could not open outcome.jsonl")
        widgetHandler:RemoveWidget(self); return
    end
    fh:setvbuf("line")
    -- Resolve commander defIds (UnitDefs is available now).
    commanderDefIds = {}
    for id, d in pairs(UnitDefs) do
        if COMMANDER_DEFS[d.name] then commanderDefIds[id] = d.name end
    end
    -- Also log a 'start' marker so post-mortem can see the run actually began
    -- even if it crashes before GameOver.
    fh:write(sfmt('{"event":"start","frame":0}\n'))
    Spring.Echo("[outcome] writing to outcome.jsonl")
end

function widget:UnitDestroyed(uid, defId, team, attackerID, attackerDefID, attackerTeam)
    if not fh then return end
    if commanderDefIds and commanderDefIds[defId] then
        local name = commanderDefIds[defId] or "?"
        local atk = (attackerDefID and commanderDefIds[attackerDefID])
                    and (commanderDefIds[attackerDefID] .. "/team" .. (attackerTeam or -1))
                    or  ("def" .. tostring(attackerDefID or -1) .. "/team" .. tostring(attackerTeam or -1))
        fh:write(sfmt(
          '{"event":"commander_death","frame":%d,"uid":%d,"def":%d,"name":"%s","team":%d,"attacker":"%s","selfd":%s}\n',
          spGetGameFrame() or 0, uid, defId, name, team or -1, atk,
          (attackerTeam == team) and "true" or "false"))
    end
end

-- Periodic team-summary snapshots so we can plot trajectory divergence
-- (unit-count curves, resource curves) — winner-match is a coarse metric;
-- the unfolding-shape matters too.
local SNAPSHOT_EVERY = 900  -- 30 sim-seconds at 30fps

function widget:GameFrame(f)
    if not fh then return end
    if f > 0 and f % SNAPSHOT_EVERY == 0 then
        local teams = spGetTeamList() or {}
        local team_strs = {}
        for i = 1, #teams do team_strs[#team_strs+1] = team_summary(teams[i]) end
        fh:write(sfmt('{"event":"snapshot","frame":%d,"teams":[%s]}\n',
            f, table.concat(team_strs, ",")))
    end
end

function widget:Shutdown()
    if fh then
        -- One last snapshot at shutdown (in case GameOver didn't fire — quit
        -- via stable-units detector or replay end without victory condition).
        dump("shutdown", nil)
        fh:close()
    end
end

function widget:GameOver(winners)
    Spring.Echo(sfmt("[outcome] GameOver, winners=%s", table.concat(winners or {}, ",")))
    dump("gameover", winners)
end
