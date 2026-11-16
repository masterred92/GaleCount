-- Gale Count window: Reset button in combat (incl. /reload in combat), padlock, idle state.
package.path = "./tests/?.lua;" .. package.path
local M = require("mock_wow")
M.install()
M.combat = true -- loaded mid-fight, as after a /reload in combat: no PLAYER_REGEN_DISABLED will come
local ns = M.loadAddon(".", "GaleCount")
local GC, UI = KennyGaleCount, ns.UI
local check = M.check
M.fire("PLAYER_LOGIN")
local fr = UI.Frame()
check(fr.reset:IsShown() == false, "/reload in combat: Reset starts hidden")
M.combat = false; M.fire("PLAYER_REGEN_ENABLED"); M.advance(5)
check(fr.reset:IsShown() == true, "combat ends: Reset shown")
GC.ResetSession()
check(table.concat(UI.Lines(), "\n"):find("No fights yet", 1, true), "idle state says what to do")
M.slash("/gale", "lock")
check(fr.grip:IsShown() == false, "locked: resize grip hidden")
fr.lock:GetScript("OnClick")(fr.lock)
check(GC.Settings().locked == false and fr.grip:IsShown(), "padlock click unlocks")
M.fire("PLAYER_REGEN_DISABLED"); M.combat = true
check(fr.reset:IsShown() == false, "combat starts: Reset hidden")
-- this mock has no C_Secrets and no proc cast seen yet: "none" mode, so the headline promises meter damage, not procs
check(GC.mode == "none" and fr.proc:GetText() == "Windfury damage after the fight", "fresh headline each fight (none mode)")
M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c1", 16361)
M.combat = false; M.meter = { total = 10000, rows = { { 6603, 7000 }, { 16361, 3000 } } }
M.fire("PLAYER_REGEN_ENABLED"); M.advance(5)
check(fr.reset:IsShown() == true, "combat ends again: Reset shown")
check(UI.Lines()[1]:find("1 proc ", 1, true), "singular: 1 proc")
check(#ns.Core.errors == 0, "no Lua errors recorded")
M.done("GaleCount UI")
