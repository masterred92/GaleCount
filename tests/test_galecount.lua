package.path = "./tests/?.lua;" .. package.path
local M = require("mock_wow")
M.install()
M.trees = { { 375, "Elemental", 0 }, { 373, "Enhancement", 31 }, { 374, "Restoration", 5 } }
local ns = M.loadAddon(".", "GaleCount")
local GC, UI = KennyGaleCount, ns.UI
local check = M.check
M.fire("PLAYER_LOGIN")
check(KennyGaleCountDB and KennyGaleCountDB.session, "saved variables set up")
check(UI.Frame() ~= nil, "window built")

-- theme: class first, then the tree with the most points
check(GC.theme.class == "SHAMAN" and GC.theme.tree == "Enhancement" and GC.theme.sound == 568049, "Enhancement storm theme")
M.trees = { { 375, "Elemental", 31 }, { 373, "Enhancement", 0 }, { 374, "Restoration", 20 } }
GC.UpdateTheme()
check(GC.theme.tree == "Elemental" and GC.theme.sound == 568516, "Elemental lightning theme")
M.trees = { { 9999, "Unknown", 0 }, { 9998, "Unknown2", 0 }, { 9997, "Water", 40 } }
GC.UpdateTheme()
check(GC.theme.sound == 569133, "unknown SkillLine IDs fall back to tree order (3rd = Restoration)")
M.trees = { { 375, "Elemental", 10 }, { 373, "Enhancement", 10 }, { 374, "Restoration", 0 } }
GC.UpdateTheme()
check(GC.theme.tree == nil and GC.theme.sound == 568049, "tie: class theme")
M.trees = nil
GC.UpdateTheme()
check(GC.theme.tree == nil and math.abs(GC.theme.frame[2] - 0x70 / 255) < 1e-6, "no talent data: Shaman class theme (0070DE)")
M.class = "MAGE"; M.trees = { { 237, "Arcane", 0 }, { 8, "Fire", 30 }, { 6, "Frost", 11 } }
GC.UpdateTheme()
check(GC.theme.class == "MAGE" and GC.theme.sound == 568461, "Mage Fire theme")
M.class = "WARLOCK"; M.trees = { { 355, "Affliction", 0 }, { 354, "Demonology", 0 }, { 593, "Destruction", 21 } }
GC.UpdateTheme()
check(GC.theme.sound == 568508 and GC.theme.accent[2] > GC.theme.accent[1], "Warlock Destruction fel fire (green)")
M.class = "NOTACLASS"; M.trees = nil
GC.UpdateTheme()
check(GC.theme.sound == 568049, "unknown class falls back to Shaman")
for class, th in pairs(ns.THEMES) do
  check(type(th.sound) == "number" and #th.frame == 6 and #th.accent == 6 and #th.order == 3, "theme data shape " .. class)
  for _, sl in ipairs(th.order) do check(th.trees[sl], class .. " tree " .. sl .. " has an entry") end
end
M.class = "SHAMAN"; M.trees = { { 375, "Elemental", 0 }, { 373, "Enhancement", 31 }, { 374, "Restoration", 0 } }
GC.UpdateTheme()

-- procs: weapon (2 swings) and totem (1), cast + aura deduped, unknown and secret spells ignored
M.fire("PLAYER_REGEN_DISABLED")
M.combat = true
M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 16361)
M.fire("UNIT_AURA", "player", { addedAuras = { { spellId = 16361 } } })
check(GC.fight.procs == 1 and GC.fight.extra == 2, "one weapon proc, cast and aura deduped")
M.advance(1)
M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-2", 10610)
check(GC.fight.procs == 2 and GC.fight.totem == 1 and GC.fight.extra == 3, "totem proc counts 1 extra swing")
M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-3", 403) -- Lightning Bolt
M.fire("UNIT_SPELLCAST_SUCCEEDED", "party1", "cast-4", 16361)
local secretID = {}; M.secret[secretID] = true
M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-5", secretID)
check(GC.fight.procs == 2, "other spells, other units and secret IDs ignored")
-- streak thunder: 2 procs within 4s played the theme sound once
check(#M.sounds == 1 and M.sounds[1][1] == 568049, "streak thunder with the theme sound")
M.advance(1)
M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-6", 16361)
check(#M.sounds == 1, "one rumble per streak")
-- live view with secret meter values: no maths, no error
local secretTotal = setmetatable({}, { __tostring = function() return "SECRET" end }); M.secret[secretTotal] = true
M.meter = { total = secretTotal, rows = { { 6603, secretTotal } } }
UI.RenderLive()
check(true, "live render with secret values")
-- fight ends: meter readable, Windfury rows present
M.combat = false
M.meter = { total = 10000, rows = { { 6603, 6000 }, { 16361, 2400 }, { 10610, 600 }, { 17364, 1000 } } }
M.fire("PLAYER_REGEN_ENABLED")
M.advance(1)
local f = GC.lastFight
check(f and f.procs == 3 and f.wf == 3000 and math.abs(f.share - 0.3) < 1e-9 and f.avg == 1000, "fight: Windfury damage, share, avg per proc")
local s = GC.SessionStats()
check(s.procs == 3 and s.wf == 3000 and s.total == 10000 and s.bestAvg == 1000, "session totals")
check(KennyGaleCountDB.meterSplits == true, "learned that the meter splits Windfury")
-- second fight, meter does NOT list Windfury: count only, no invented damage
M.fire("PLAYER_REGEN_DISABLED"); M.combat = true
M.advance(5)
M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c7", 16361)
M.combat = false
M.meter = { total = 5000, rows = { { 6603, 5000 } } }
M.fire("PLAYER_REGEN_ENABLED"); M.advance(1)
check(GC.lastFight.wf == nil and GC.lastFight.procs == 1, "no Windfury row: no damage number made up")
check(GC.SessionStats().wf == 3000 and GC.SessionStats().procs == 4, "session keeps only measured damage")
check(KennyGaleCountDB.meterSplits == false, "learned the meter doesn't split")
check(table.concat(UI.Lines(), "\n"):find("counting procs only", 1, true), "window says it is counting procs only")
-- meter still secret after combat: retries, then gives up without numbers
M.fire("PLAYER_REGEN_DISABLED"); M.combat = true; M.advance(5)
M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c8", 16361)
M.combat = false; M.meter = { total = secretTotal, rows = {} }
M.fire("PLAYER_REGEN_ENABLED"); M.advance(10)
check(GC.lastFight and GC.lastFight.total == nil and GC.lastFight.procs == 1, "secret meter: procs only, no numbers")

-- record thunder after a fight with a better average
GC.ResetSession()
GC.Settings().sound = "record"
M.sounds = {}
for i, wf in ipairs({ 2000, 3000 }) do
  M.fire("PLAYER_REGEN_DISABLED"); M.combat = true; M.advance(10)
  M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "r" .. i, 16361); M.advance(1)
  M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "s" .. i, 16361)
  M.combat = false; M.meter = { total = 10000, rows = { { 16361, wf } } }
  M.fire("PLAYER_REGEN_ENABLED"); M.advance(1)
end
check(#M.sounds == 1 and GC.SessionStats().bestAvg == 1500, "record thunder only when a best is beaten")
GC.Settings().sound = "streak"

-- slash commands
M.slash("/galecount", "reset")
check(GC.SessionStats().procs == 0 and GC.SessionStats().wf == 0, "/galecount reset clears the session")
M.slash("/gale", "size 300 200")
check(GC.Settings().width == 300 and GC.Settings().height == 200, "/gale size")
M.slash("/galecount", "size 9999 1")
check(GC.Settings().width == UI.MAX_W and GC.Settings().height == UI.MIN_H, "size is clamped")
M.slash("/galecount", "scale 5")
check(GC.Settings().scale == 2, "scale is clamped")
M.slash("/galecount", "lock")
check(GC.Settings().locked == true, "lock")
M.slash("/galecount", "streak 3 6")
check(GC.Settings().streakProcs == 3 and GC.Settings().streakSeconds == 6, "streak settings")
M.sounds = {}
M.slash("/galecount", "soundfile crack")
check(GC.Settings().soundFile == "crack" and M.sounds[1][1] == 565712, "sound file preview")
M.slash("/galecount", "sound bogus")
check(GC.Settings().sound == "streak", "unknown sound mode refused")
M.prints = {}
M.slash("/galecount", "meter")
check(M.printed("Windfury") , "/galecount meter lists rows")
M.combat = true; local before = GC.fight.procs
M.slash("/galecount", "test")
check(GC.fight.procs == before and M.printed("not in combat"), "no test preview in combat")
M.combat = false
M.slash("/galecount", "resetpos")
check(KennyGaleCountDB.point == nil and GC.Settings().scale == 1, "resetpos")
M.done("GaleCount")
