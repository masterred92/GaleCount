-- SavedVariables schema 1 (Gale Count 1.0.x) -> 2 (1.1.0): every saved setting survives, the three new switches
-- start at their defaults, and non-boolean junk on the boolean switches is dropped.
package.path = "./tests/?.lua;" .. package.path
local M = require("mock_wow")
M.install()
KennyGaleCountDB = { schema = 1, point = { "TOPLEFT", 40, -60 }, castSeen = true, meterSplits = true,
  session = { procs = 12, extra = 24, wf = 5000, total = 20000, fights = 3, measuredProcs = 12, bestAvg = 400, since = 1 },
  settings = { locked = true, scale = 1.25, width = 300, height = 180, sound = "every", soundFile = "crack",
    streakProcs = 3, streakSeconds = 6, shown = "yes", fade = 1, compact = "true", clickThrough = {} } }
local ns = M.loadAddon(".", "GaleCount")
local GC, UI = KennyGaleCount, ns.UI
local check = M.check
M.fire("PLAYER_LOGIN")
local db, s = KennyGaleCountDB, GC.Settings()
check(db.schema == 2, "migrated to schema 2")
check(s.locked == true and s.scale == 1.25 and s.width == 300 and s.height == 180, "lock, scale and size kept")
check(s.sound == "every" and s.soundFile == "crack" and s.streakProcs == 3 and s.streakSeconds == 6, "sound and streak settings kept")
check(db.point[1] == "TOPLEFT" and db.point[2] == 40 and db.castSeen == true and db.meterSplits == true, "position and detection memory kept")
check(db.session.procs == 12 and db.session.bestAvg == 400, "session kept")
check(db.settings.shown == nil and s.shown == true, "junk 'shown' dropped: default true")
check(db.settings.fade == nil and s.fade == true, "junk 'fade' dropped: default on")
check(db.settings.compact == nil and s.compact == false, "junk 'compact' dropped: default off")
check(db.settings.clickThrough == nil and s.clickThrough == false, "junk 'clickThrough' dropped: default off")
check(UI.Frame().height == 180 and UI.Frame().width == 300, "box built at the saved size")
-- migration on its own: a schema 1 db with no settings table, and real booleans kept
local d = GC.migrations[2]({ schema = 1 })
check(type(d.settings) == "table", "no settings table: one is made")
d = GC.migrations[2]({ settings = { fade = false, compact = true, clickThrough = true, locked = false } })
check(d.settings.fade == false and d.settings.compact == true and d.settings.clickThrough == true and d.settings.locked == false, "real booleans kept")
-- a fresh install starts at schema 2 with the defaults
check(#ns.Core.errors == 0, "no Lua errors recorded")
M.done("GaleCount migration")
