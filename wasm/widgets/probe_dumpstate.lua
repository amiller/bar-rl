-- Trigger Spring's built-in /DumpState at chosen frames.
-- DumpState writes a per-frame synced-state file ("ReplayGameState-N-[min-max].txt")
-- in the engine's write-dir; comparing those between native and WASM is the most
-- surgical way to find the exact synced field that first diverges.

function widget:GetInfo()
    return {
        name    = "Probe DumpState Trigger",
        desc    = "Calls /DumpState at f=60 and f=120 for native-vs-WASM diffing",
        author  = "claude",
        date    = "2026-04-24",
        layer   = 2,
        enabled = true,
    }
end

local DUMP_FRAMES = { [60]=true, [120]=true, [1800]=true, [5400]=true, [10800]=true }
-- Quit shortly after the last dump frame so test loops don't wait for the
-- whole replay to finish. Set 0 to disable (lets the replay play through
-- to GameOver — needed for outcome-comparison runs).
local QUIT_FRAME = 10810
-- Set true to enable cheats; gives DumpState access to sync history.
-- Required for the per-Sync history dump (engine has DumpHistory() guarded
-- on cheats||serverRequest).
local ENABLE_CHEATS = true

local fired = false
function widget:GameFrame(f)
    if ENABLE_CHEATS and not fired then
        Spring.SendCommands("cheat 1")
        fired = true
        Spring.Echo("[probe-dumpstate] cheats enabled (for sync history dump)")
    end
    if DUMP_FRAMES[f] then
        Spring.SendCommands("dumpstate " .. f .. " " .. f)
        Spring.Echo(string.format("[probe-dumpstate] /dumpstate %d %d issued", f, f))
    end
    if QUIT_FRAME > 0 and f >= QUIT_FRAME then
        Spring.Echo(string.format("[probe-dumpstate] reached QUIT_FRAME=%d, quitting", QUIT_FRAME))
        Spring.Quit()
    end
end
