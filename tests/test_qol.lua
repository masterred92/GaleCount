-- Gale Count 1.1.0 quality-of-life features: idle fade, the live Windfury proc/streak drain bar, the right-click quick
-- menu, compact mode and click-through when locked. Replays "none", "cast" and "aura" detection with the secret-value
-- rules from tests/mock_secrets.lua.
package.path = "./tests/?.lua;" .. package.path
local M = require("mock_wow")
M.install()
local S = require("mock_secrets").install(M)
M.trees = { { 375, "Elemental", 0 }, { 373, "Enhancement", 31 }, { 374, "Restoration", 0 } }

-- Blizzard's context menu (MenuUtil.CreateContextMenu + element descriptions), recorded so entries can be clicked
local menus = {}
local function desc(kind, text, a, b)
  local d = { kind = kind, text = text, a = a, b = b, kids = {} }
  for _, m in ipairs({ "CreateTitle", "CreateButton", "CreateCheckbox", "CreateRadio", "CreateDivider" }) do
    d[m] = function(self, t, x, y) local c = desc(m, t, x, y); self.kids[#self.kids + 1] = c; return c end
  end
  return d
end
local realMenu = { CreateContextMenu = function(owner, gen)
  local root = desc("root"); gen(owner, root); menus[#menus + 1] = root; return {} end }
MenuUtil = realMenu
GameTooltip = M.frameObj("GameTooltip")

local ns = M.loadAddon(".", "GaleCount")
local GC, UI = KennyGaleCount, ns.UI
local check = M.check
M.fire("PLAYER_LOGIN")
local fr = UI.Frame()
local set = GC.Settings()
local function near(a, b) return type(a) == "number" and math.abs(a - b) < 1e-6 end
local function tick(sec) M.advance(sec); local fn = fr:GetScript("OnUpdate"); if fn then fn(fr, sec) end end
local function errors() return #ns.Core.errors end
local base = errors()
local function barText() return fr.barText:GetText() or "" end
local function accentBar() local c = fr.bar.color or {}
  return near(c[1], GC.theme.accent[1]) and near(c[2], GC.theme.accent[2]) and near(c[3], GC.theme.accent[3]) end
local function shareBar() return fr.bar.maxV == 1 and barText():find("Windfury share", 1, true) ~= nil and accentBar() end
local function drainColour() local c, r, g, b = fr.bar.color or {}, UI.DrainColor()
  return near(c[1], r) and near(c[2], g) and near(c[3], b) end
local function startFight() M.meter = { total = 0, rows = {} }; M.combat = true; M.fire("PLAYER_REGEN_DISABLED") end
local function endFight() M.combat = false; M.meter = { total = 10000, rows = { { 6603, 8000 }, { 16361, 2000 } } }
  M.fire("PLAYER_REGEN_ENABLED"); M.advance(5) end

-- ---------- defaults ----------
check(set.fade == true and set.compact == false and set.clickThrough == false, "1.1.0 defaults: fade on, compact off, click-through off")
check(KennyGaleCountDB.schema == 2 and GC.SCHEMA == 2, "SavedVariables schema 2")
check(KennyGaleCountDB.settings.fade == nil and KennyGaleCountDB.settings.compact == nil, "defaults are not written into SavedVariables")
check(set.sound == "streak" and set.soundFile == "theme" and set.streakSeconds == 4 and set.streakProcs == 2, "1.0.x sound and streak defaults kept")
check(GC.mode == "none", "strict client: none mode")
local r, g, b = UI.DrainColor()
check(r > GC.theme.accent[1] and g > GC.theme.accent[2] and b >= GC.theme.accent[3] and r <= 1 and b <= 1, "drain colour: the accent, brightened")

-- ---------- 1. idle fade ----------
check(near(fr:GetAlpha(), 0.35) and near(UI.FADE_ALPHA, 0.35), "idle out of combat: 35% alpha")
fr:GetScript("OnEnter")(fr)
check(near(fr:GetAlpha(), 1), "hover: full alpha")
M.mouseOver = fr; fr:GetScript("OnLeave")(fr)
check(near(fr:GetAlpha(), 1), "mouse moved onto the padlock (still over the box): stays full")
M.mouseOver = nil; fr.lock:GetScript("OnLeave")(fr.lock)
check(near(fr:GetAlpha(), 0.35), "mouse left the box from the padlock: fades again")
fr.lock:GetScript("OnEnter")(fr.lock)
check(near(fr:GetAlpha(), 1), "hovering the padlock: full alpha")
fr.lock:GetScript("OnLeave")(fr.lock)
fr.grip:GetScript("OnEnter")(fr.grip)
check(near(fr:GetAlpha(), 1), "hovering the resize grip: full alpha")
fr.grip:GetScript("OnLeave")(fr.grip)
check(near(fr:GetAlpha(), 0.35), "grip left: fades")
fr.reset:GetScript("OnEnter")(fr.reset)
check(near(fr:GetAlpha(), 1), "hovering Reset: full alpha")
fr.reset:GetScript("OnLeave")(fr.reset)
check(near(fr:GetAlpha(), 0.35), "Reset left: fades")
startFight()
check(near(fr:GetAlpha(), 1), "in combat: full alpha")
endFight()
check(near(fr:GetAlpha(), 0.35), "combat over: back to 35%")
M.combat = true; UI.UpdateAlpha()
check(near(fr:GetAlpha(), 1), "combat lockdown without a fight start (/reload in combat): full alpha")
M.combat = false; UI.UpdateAlpha()
M.prints = {}
M.slash("/gale", "fade")
check(set.fade == false and near(fr:GetAlpha(), 1) and M.printed("idle fade: off"), "/gale fade off: full alpha at once")
check(KennyGaleCountDB.settings.fade == false, "fade off saved")
fr:GetScript("OnEnter")(fr); fr:GetScript("OnLeave")(fr)
check(near(fr:GetAlpha(), 1), "fade off: hover ending keeps full alpha")
M.slash("/gale", "fade")
check(set.fade == true and near(fr:GetAlpha(), 0.35) and M.printed("idle fade: on"), "/gale fade on: fades at once")

-- ---------- 2. the drain bar never runs in "none" mode ----------
check(not UI.Draining() and shareBar(), "no proc: Windfury share bar in the accent")
startFight()
S.gain(16361, 2, 1.5); tick(0.2); S.drop(16361)
check(GC.mode == "none" and GC.fight.procs == 0 and not UI.Draining() and not UI.StreakActive(), "none mode: a hidden proc never starts the drain bar")
-- even a proc pushed straight at the window in none mode gets no countdown
UI.OnProc({ kind = "weapon", rank = 4, extra = 2 }); tick(0.1)
check(not UI.Draining() and not UI.StreakActive() and not barText():find("WINDFURY!", 1, true), "none mode, proc forced: still no drain bar")
endFight()

-- ---------- 2b. cast mode ----------
S.castEvents = { [16361] = true, [10610] = true }
startFight()
S.procCast(16361)
check(GC.mode == "cast" and GC.fight.procs == 1, "cast mode: proc counted")
check(UI.Draining() and UI.StreakActive() and drainColour(), "cast mode proc: drain bar on, bright accent")
check(fr.bar.minV == 0 and fr.bar.maxV == 4 and near(fr.bar.value, 4) and barText() == "WINDFURY! 4.0s", "drain bar: 0-4s (streakSeconds), full, WINDFURY! 4.0s")
tick(0.8)
check(near(fr.bar.value, 3.2) and barText() == "WINDFURY! 3.2s", "drains with time: WINDFURY! 3.2s")
tick(0.05)
check(near(fr.bar.value, 3.15), "drains smoothly between tenths")
UI.RenderLive()
check(barText() == "WINDFURY! 3.2s" or barText() == "WINDFURY! 3.1s", "the live ticker leaves the drain bar alone")
S.procCast(16361)
check(near(fr.bar.value, 4) and barText() == "WINDFURY! x2 4.0s", "second proc inside the window: window restarts, streak x2")
S.procCast(10610)
check(barText() == "WINDFURY! x3 4.0s" and fr.proc:GetText() == "TOTEM WINDFURY! +1", "totem proc chains too: x3")
GC.UpdateTheme()
check(drainColour(), "a theme change mid-window keeps the drain colour")
tick(3.9)
check(UI.Draining() and barText() == "WINDFURY! x3 0.1s", "near the end of the window")
tick(0.2)
check(not UI.Draining() and not UI.StreakActive() and accentBar(), "window over in combat: theme accent back")
check(not barText():find("WINDFURY!", 1, true), "window over: no stale countdown text")
check(fr:GetScript("OnUpdate") == nil, "nothing left to animate: OnUpdate removed")
S.procCast(16361)
check(barText() == "WINDFURY! 4.0s", "a proc after the window: a fresh window, count back to 1")
endFight()
-- the window can outlast combat: when it ends out of combat the share bar is restored and the box fades again
check(UI.Draining() and near(fr:GetAlpha(), 1), "proc window still running after combat: full alpha")
tick(4)
check(not UI.Draining() and shareBar() and near(fr:GetAlpha(), 0.35), "window over out of combat: share bar restored, fades")
-- a longer window from /gale streak
M.slash("/gale", "streak 3 6")
startFight(); S.procCast(16361)
check(fr.bar.maxV == 6 and barText() == "WINDFURY! 6.0s", "/gale streak 3 6: the drain bar follows the 6s window")
tick(6.1)
check(not UI.Draining(), "6s window over")
endFight()
M.slash("/gale", "streak 2 4")

-- ---------- 2c. aura mode ----------
for id in pairs(GC.PROCS) do S.never[id] = true end
check(GC.EvaluateMode() == "aura", "never-secret auras: aura mode")
startFight()
S.gain(16361, 2, 1.5)
check(GC.fight.procs == 1 and UI.Draining() and barText() == "WINDFURY! 4.0s", "aura mode proc: drain bar on")
tick(1); S.drop(16361)
check(UI.Draining() and barText() == "WINDFURY! 3.0s", "buff gone, window still runs (it is the streak window, not the buff)")
tick(3.1)
check(not UI.Draining() and accentBar(), "aura mode: window over, accent back")
-- the client turns strict mid-window: the next evaluation is none mode and the window stops at once (no guessing)
S.gain(10484, 2, 1.5)
check(UI.Draining(), "aura mode: another proc window")
for id in pairs(GC.PROCS) do S.never[id] = nil end
KennyGaleCountDB.castSeen = nil
GC.EvaluateMode(); tick(0.1)
check(GC.mode == "none" and not UI.Draining() and not UI.StreakActive(), "mode drops to none: drain bar stops at once")
S.drop(10484)
endFight()
S.castEvents = {}

-- ---------- 2d. /gale test preview ----------
check(GC.mode == "none", "back to the strict client (none mode)")
M.sounds = {}
M.slash("/gale", "test")
check(UI.PreviewActive() and UI.Draining() and #M.sounds == 1, "test preview (even in none mode): drain bar and one sound")
check(near(fr:GetAlpha(), 1) and fr.proc:GetText() == "WINDFURY! +2" and barText() == "WINDFURY! 4.0s", "test preview: full alpha, headline, countdown")
tick(1.5)
check(near(fr.bar.value, 2.5) and barText() == "WINDFURY! 2.5s", "test preview drains")
tick(2.6)
check(not UI.PreviewActive() and not UI.Draining() and shareBar(), "test preview over: share bar back")
check(near(fr:GetAlpha(), 0.35) and fr.proc:GetText() == UI.IdleHeadline(), "test preview over: fades, idle headline")
M.slash("/gale", "test")
startFight()
check(not UI.PreviewActive() and not UI.Draining() and accentBar(), "combat starts: test preview stops")
M.prints = {}
M.slash("/gale", "test")
check(not UI.PreviewActive() and M.printed("not in combat"), "no test preview in combat")
endFight()
S.castEvents = { [16361] = true }
KennyGaleCountDB.castSeen = true; GC.EvaluateMode()
M.slash("/gale", "test")
tick(1)
S.procCast(16361)
check(not UI.PreviewActive() and UI.StreakActive() and barText() == "WINDFURY! 4.0s", "a real proc replaces the preview")
tick(4.1)
check(not UI.Draining() and shareBar(), "real window over: share bar")
S.castEvents = {}; KennyGaleCountDB.castSeen = nil; GC.EvaluateMode()

-- ---------- 3. right-click quick menu ----------
local function find(root, kind, text)
  for _, k in ipairs(root.kids) do
    if k.kind == kind and k.text == text then return k end
    local hit = find(k, kind, text); if hit then return hit end
  end
end
fr:GetScript("OnMouseUp")(fr, "LeftButton")
check(#menus == 0, "left click: no menu")
fr:GetScript("OnMouseUp")(fr, "RightButton")
local menu = menus[1]
check(menu and menu.kids[1].kind == "CreateTitle" and menu.kids[1].text == "Gale Count", "right-click out of combat: the quick menu opens")
local soundBtn, fileBtn = find(menu, "CreateButton", "Sound"), find(menu, "CreateButton", "Sound file")
check(soundBtn and #soundBtn.kids == 4 and fileBtn and #fileBtn.kids == 4, "sound mode and sound file submenus (4 each)")
for _, label in ipairs({ "Streaks", "Every proc", "New best average only", "Off" }) do check(find(soundBtn, "CreateRadio", label), "sound mode entry " .. label) end
for _, label in ipairs({ "Theme", "Thunder", "Thundercrack", "Lightning bolt" }) do check(find(fileBtn, "CreateRadio", label), "sound file entry " .. label) end
for _, label in ipairs({ "Idle fade out of combat", "Compact mode", "Locked", "Click-through when locked" }) do
  check(find(menu, "CreateCheckbox", label), "checkbox " .. label)
end
for _, label in ipairs({ "Test preview", "Reset session", "Reset position" }) do check(find(menu, "CreateButton", label), "button " .. label) end
local every = find(soundBtn, "CreateRadio", "Every proc")
check(find(soundBtn, "CreateRadio", "Streaks").a() == true and every.a() == false, "radio shows the current sound mode (streak)")
every.b()
check(set.sound == "every" and every.a() == true, "menu: sound mode every")
find(soundBtn, "CreateRadio", "Streaks").b()
check(set.sound == "streak", "menu: sound mode back to streak")
M.sounds = {}
local crack = find(fileBtn, "CreateRadio", "Thundercrack")
crack.b()
check(set.soundFile == "crack" and crack.a() and #M.sounds == 1 and M.sounds[1][1] == GC.SOUNDS.crack, "menu: sound file crack (plays once)")
find(fileBtn, "CreateRadio", "Theme").b()
check(set.soundFile == "theme", "menu: sound file back to theme")
local fadeBox = find(menu, "CreateCheckbox", "Idle fade out of combat")
fadeBox.b()
check(set.fade == false and fadeBox.a() == false, "menu: idle fade off")
fadeBox.b()
check(set.fade == true, "menu: idle fade on")
local lockBox = find(menu, "CreateCheckbox", "Locked")
lockBox.b()
check(set.locked == true and lockBox.a() == true, "menu: lock")
lockBox.b()
check(set.locked == false, "menu: unlock")
-- an entry clicked after combat started does nothing
M.combat = true
fadeBox.b(); lockBox.b(); find(menu, "CreateButton", "Reset session").a()
check(set.fade == true and set.locked == false, "menu left open into combat: entries do nothing")
check(UI.OpenMenu(fr) == false and #menus == 1, "no menu opens in combat")
fr:GetScript("OnMouseUp")(fr, "RightButton")
check(#menus == 1, "right-click in combat: no menu")
M.prints = {}
M.slash("/gale", "menu")
check(#menus == 1 and M.printed("not in combat"), "/gale menu in combat: says why")
M.combat = false
M.slash("/gale", "menu")
check(#menus == 2, "/gale menu out of combat: opens")
find(menus[2], "CreateButton", "Test preview").a()
check(UI.PreviewActive(), "menu: test preview")
tick(5)
GC.OnProc(16361) -- straight into the counter: a session with a proc to reset
check(KennyGaleCountDB.session.procs > 0 and not UI.StreakActive(), "session has procs (none mode: still no drain window)")
M.prints = {}
find(menus[2], "CreateButton", "Reset session").a()
check(KennyGaleCountDB.session.procs == 0 and M.printed("session reset."), "menu: reset session")
KennyGaleCountDB.point = { "TOPLEFT", 50, -50 }
find(menus[2], "CreateButton", "Reset position").a()
check(KennyGaleCountDB.point == nil, "menu: reset position")
-- no MenuUtil on this client: a clear message, no error
MenuUtil = nil
M.prints = {}
check(UI.OpenMenu(fr) == false and M.printed("no quick menu on this client"), "no MenuUtil: safe fallback message")
-- a menu that errors is caught
MenuUtil = { CreateContextMenu = function() error("menu broke") end }
local before = errors()
check(UI.OpenMenu(fr) == false and errors() == before + 1, "a menu error is caught and recorded, not thrown")
table.remove(ns.Core.errors)
MenuUtil = realMenu
tick(1)

-- ---------- 4. compact mode ----------
M.slash("/gale", "size 300 200")
check(fr.width == 300 and fr.height == 200, "full size 300x200")
M.prints = {}
M.slash("/gale", "compact")
check(set.compact == true and M.printed("compact mode: on"), "/gale compact on")
check(fr.height == UI.COMPACT_H and UI.COMPACT_H == 60 and fr.width == 300, "compact: 60px tall strip, width kept")
check(not fr.title:IsShown() and not fr.spark:IsShown() and not fr.lines:IsShown() and not fr.reset:IsShown() and not fr.grip:IsShown(),
  "compact: title, divider, breakdown, Reset and grip hidden")
check(fr.proc:IsShown() and fr.count:IsShown() and fr.lock:IsShown() and fr.bar:IsShown(), "compact: headline, proc count, padlock, bar shown")
check(fr.bounds[2] == 60 and fr.bounds[4] == 60, "compact: height locked to the strip")
check(set.width == 300 and set.height == 200, "compact: saved full size untouched")
check(fr.count:GetText() == "0 procs" or fr.count:GetText():find("proc", 1, true), "compact count text")
M.slash("/gale", "size 320 220")
check(fr.height == 60 and fr.width == 320 and set.height == 220, "/gale size while compact: saved full size changes, strip stays 60")
fr.grip:GetScript("OnMouseUp")(fr.grip)
check(set.height == 220, "grip release in compact mode never saves the strip height")
startFight()
S.castEvents = { [16361] = true }; S.procCast(16361)
check(fr.count:GetText() == "1 proc" and not fr.reset:IsShown(), "compact in combat: live proc count, no Reset")
endFight()
check(not fr.reset:IsShown(), "compact after combat: Reset stays hidden")
check(fr.count:GetText() == "1 proc", "compact out of combat: last fight's procs")
tick(5)
M.slash("/gale", "compact")
check(set.compact == false and fr.height == 220 and fr.width == 320, "compact off: saved full size back")
check(fr.title:IsShown() and fr.lines:IsShown() and fr.reset:IsShown() and fr.grip:IsShown() and not fr.count:IsShown(), "full layout restored")
S.castEvents = {}; KennyGaleCountDB.castSeen = nil; GC.EvaluateMode()
-- a protected box (it never is) would wait for the end of combat instead of re-laying out in combat
fr.protected = true; M.combat = true
set.compact = true
check(UI.ApplyLayout() == false and UI.layoutPending and fr.height == 220, "protected in combat: layout waits")
M.combat = false; M.fire("PLAYER_REGEN_ENABLED"); M.advance(5)
check(not UI.layoutPending and fr.height == 60, "after combat: pending layout applied")
fr.protected = nil
M.slash("/gale", "compact")
check(set.compact == false and fr.height == 220, "compact off again")

-- ---------- 5. click-through when locked ----------
check(fr:IsMouseEnabled() and fr.lock:IsMouseEnabled() and fr.reset:IsMouseEnabled(), "default: box takes clicks")
M.prints = {}
M.slash("/gale", "clickthrough")
check(set.clickThrough == true and fr:IsMouseEnabled(), "click-through on but unlocked: still clickable")
check(M.printed("click-through when locked: on") and M.printed("/gale unlock or /gale clickthrough"), "click-through on: says how to undo it")
M.prints = {}
M.slash("/gale", "lock")
check(not fr:IsMouseEnabled() and not fr.lock:IsMouseEnabled() and not fr.reset:IsMouseEnabled(), "locked + click-through: box, padlock and Reset pass clicks")
check(M.printed("frame locked.") and M.printed("/gale unlock or /gale clickthrough"), "lock message notes how to click it again")
fr:GetScript("OnEnter")(fr)
check(near(fr:GetAlpha(), 0.35), "click-through: hovering doesn't pop the faded box")
GameTooltip.lines = {}
GameTooltip.AddLine = function(_, t) GameTooltip.lines[#GameTooltip.lines + 1] = t end
fr.lock:GetScript("OnEnter")(fr.lock)
local tip = table.concat(GameTooltip.lines, "\n")
check(tip:find("/gale unlock or /gale clickthrough", 1, true) and tip:find("Right-click", 1, true), "padlock tooltip notes the right-click menu and how to undo click-through")
fr.lock:GetScript("OnLeave")(fr.lock)
M.slash("/gale", "unlock")
check(fr:IsMouseEnabled() and fr.lock:IsMouseEnabled() and fr.reset:IsMouseEnabled(), "/gale unlock: clicks restored")
M.slash("/gale", "lock")
check(not fr:IsMouseEnabled(), "locked again: click-through")
M.slash("/gale", "clickthrough")
check(set.clickThrough == false and fr:IsMouseEnabled() and set.locked == true, "/gale clickthrough off while locked: clicks restored, still locked")
M.slash("/gale", "clickthrough")
local ctBox = find(menus[2], "CreateCheckbox", "Click-through when locked")
check(ctBox.a() == true and not fr:IsMouseEnabled(), "menu checkbox reflects click-through")
ctBox.b()
check(set.clickThrough == false and fr:IsMouseEnabled(), "menu: click-through off")
local compactBox = find(menus[2], "CreateCheckbox", "Compact mode")
compactBox.b()
check(set.compact == true and compactBox.a() and fr.height == 60, "menu: compact on")
compactBox.b()
check(set.compact == false and fr.height == 220, "menu: compact off")
M.slash("/gale", "unlock")

-- ---------- help and debug ----------
M.prints = {}
M.slash("/gale", "help")
check(M.printed("fade | compact | clickthrough | menu") and M.printed("/gale unlock or /gale clickthrough"), "help lists the new commands and the click-through note")
check(table.concat(GC.StateLines(), "\n"):find("fade=true compact=false clickthrough=false", 1, true), "debug report shows the new settings")
check(errors() == base, "no Lua errors recorded")
M.done("GaleCount QoL")
