-- Trigger Spring's built-in /DumpState at chosen frames.
function widget:GetInfo()
    return { name="Probe DumpState Trigger", desc="dump @ key frames",
             author="claude", date="2026-04-25", layer=2, enabled=true }
end
local DUMP = {[60]=1, [120]=1, [1800]=1, [5400]=1, [10800]=1}
local QUIT = 0  -- run to GameOver
local fired = false
function widget:GameFrame(f)
    if not fired then Spring.SendCommands("cheat 1"); fired=true end
    if DUMP[f] then Spring.SendCommands("dumpstate "..f.." "..f) end
    if QUIT > 0 and f >= QUIT then Spring.Quit() end
end
