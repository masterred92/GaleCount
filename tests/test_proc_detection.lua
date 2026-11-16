-- Windfury proc detection under WoW: Forever's real secret-value rules (issue #1). tests/mock_secrets.lua applies
-- them: in combat aura reads return nothing unless a spell is flagged never-secret, UNIT_AURA payloads are secret,
-- and proc cast events only arrive when a test switches them on. Every mode and the moves between them are replayed.
package.path = "./tests/?.lua;" .. package.path
local M = require("mock_wow")
M.install()
local S = require("mock_secrets").install(M)
local check = M.check

local ns = M.loadAddon(".", "GaleCount")
local GC, UI = KennyGaleCount, ns.UI
M.fire("PLAYER_LOGIN")

local secretTotal = {}; M.secret[secretTotal] = true
local function startFight() M.meter = { total = secretTotal, rows = {} }; M.combat = true; M.fire("PLAYER_REGEN_DISABLED") end
local function endFight(rows, total) M.combat = false; M.meter = { total = total or 10000, rows = rows or { { 6603, 10000 } } }
  M.fire("PLAYER_REGEN_ENABLED"); M.advance(5) end
local function lines() return table.concat(UI.Lines(), "\n") end
local function weaponProc(id, apps) S.procCast(id); return S.gain(id, apps or 2, 1.5) end

-- 1. Strict client (restrictions on, nothing never-secret, no proc cast events): "none" mode, nothing counted.
check(GC.mode == "none", "strict client starts in none mode")
startFight()
weaponProc(16361); M.advance(1); S.drop(16361)
weaponProc(10484); M.advance(1); S.drop(10484)
check(GC.fight.procs == 0, "none mode: hidden procs are not counted or guessed")
check(UI.Frame().proc:GetText() == "Windfury damage after the fight", "none mode: headline promises meter damage, not procs")
endFight({ { 6603, 7000 }, { 16361, 2000 }, { 10484, 1000 } })
check(GC.lastFight.wf == 3000 and math.abs(GC.lastFight.share - 0.3) < 1e-9, "none mode: Windfury damage read from the meter by spell ID")
check(lines():find("Procs can't be counted on this client", 1, true) and lines():find("3000", 1, true), "none mode: honest note plus meter damage")
check(not lines():find("0 procs", 1, true), "none mode: no '0 procs' shown as if counted")
startFight(); weaponProc(16361); S.drop(16361)
endFight({ { 6603, 9000 } }, 9000)
check(GC.lastFight.wf == nil and lines():find("no separate Windfury row", 1, true), "no Windfury row: said plainly, Auto Attack not relabelled")

-- 2. Mode B: the client sends the player's cast event for proc spells.
S.castEvents = { [16361] = true, [10610] = true }
startFight()
check(GC.mode == "none", "before any proc cast is seen: still none")
weaponProc(16361)
check(GC.mode == "cast" and GC.fight.procs == 1 and GC.fight.extra == 2, "first plain proc cast switches to cast mode and counts")
M.advance(0.1); weaponProc(16361)
check(GC.fight.procs == 2, "two real procs 0.1s apart both count (no time-based dedupe)")
S.drop(16361)
M.fire("UNIT_SPELLCAST_SUCCEEDED", "party1", "Cast-3-1-1-1-16361-77", 16361)
M.fire("UNIT_SPELLCAST_SUCCEEDED", "pet", "Cast-3-1-1-1-16361-78", 16361)
check(GC.fight.procs == 2, "another player's or a pet's Windfury is ignored")
local sid = {}; M.secret[sid] = true
M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3-1-1-1-0-79", sid)
M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3-1-1-1-403-80", 403)
check(GC.fight.procs == 2, "secret spell ID and other spells ignored")
S.procCast(10610); S.gain(10610, 1, 1.5)
check(GC.fight.totem == 1 and GC.fight.extra == 5, "totem proc: 1 extra swing")
S.drop(10610)
endFight({ { 6603, 8000 }, { 16361, 2000 } })
check(GC.lastFight.procs == 3 and GC.lastFight.avg and math.abs(GC.lastFight.avg - 2000 / 3) < 1e-9, "cast mode: procs and average per proc after the fight")
check(KennyGaleCountDB.castSeen == true, "remembered that this client sends proc casts")
startFight()
check(GC.mode == "cast", "next fight starts in cast mode")
endFight()

-- 3. Mode A: proc auras flagged never-secret are read in combat.
S.never = { [8233] = true, [8236] = true, [10484] = true, [16361] = true }
startFight()
check(GC.mode == "aura" and GC.auraReadable[16361] and not GC.auraReadable[10610], "never-secret weapon auras: aura mode")
local before = GC.fight.procs
local a = weaponProc(16361, 2)
check(GC.fight.procs == before + 1, "aura mode: new aura instance counts once even with its cast event")
S.update(16361, 1)
check(GC.fight.procs == before + 1, "a charge used (applications down): no proc")
M.advance(0.3); S.update(16361, 2, M.clock + 1.5)
check(GC.fight.procs == before + 2, "re-proc while the buff is up (charges back up, later expiry) counts")
M.advance(0.3); S.update(16361, nil, M.clock + 1.5)
check(GC.fight.procs == before + 3, "re-proc seen only as a later expirationTime counts")
M.fire("UNIT_AURA", "player", S.payload())
check(GC.fight.procs == before + 3, "unrelated aura update: nothing new")
S.drop(16361); M.advance(0.5); a = S.gain(16361, 2, 1.5)
check(GC.fight.procs == before + 4, "buff gone, then a new instance: counts")
S.drop(16361)
M.fire("UNIT_AURA", "party1", { addedAuras = { { spellId = 16361 } } })
check(GC.fight.procs == before + 4, "party member's aura update ignored")
S.procCast(10610); S.gain(10610, 1, 1.5)
check(GC.fight.totem == 1, "totem aura still secret: counted from its cast event instead")
S.drop(10610)
S.castEvents = {}
S.gain(10610, 1, 1.5)
check(GC.fight.totem == 1, "totem aura secret and no cast event: not counted, not guessed")
S.drop(10610)
endFight()
local _ = a

-- 4. Moves between modes, decided again at each fight start.
S.never = {}
startFight()
check(GC.mode == "cast", "flags gone: back to cast mode (casts were seen before)")
endFight()
KennyGaleCountDB.castSeen = nil; GC.castsSeen = 0
startFight()
check(GC.mode == "none", "no flags, no casts: none mode")
endFight()
S.restrictions = false
startFight()
check(GC.mode == "aura" and GC.auraReadable[10610], "client without secret restrictions: every proc aura read")
local n = GC.fight.procs
S.gain(10608, 1, 1.5)
check(GC.fight.procs == n + 1 and GC.fight.totem == 1, "restrictions off: totem aura counted")
S.drop(10608)
endFight()
S.restrictions = true

-- 5. /gale debug: one command, full diagnostic.
M.prints = {}
M.slash("/gale", "debug")
local out = table.concat(M.prints, "\n")
check(out:find("detection mode: none", 1, true), "debug shows the mode")
check(out:find("secret restrictions: true", 1, true), "debug shows the restriction state")
check(out:find("16361 weapon 4: secrecy 2", 1, true) and out:find("10610 totem 3: secrecy 2", 1, true), "debug lists each proc spell's secrecy")
check(out:find("proc cast events seen", 1, true), "debug says whether proc casts were seen")

-- 6. A client without C_Secrets or C_UnitAuras: no errors anywhere.
local keepS, keepU = C_Secrets, C_UnitAuras
C_Secrets, C_UnitAuras = nil, nil
local ok = pcall(GC.EvaluateMode)
local ok2, dl = pcall(GC.DetectionLines)
check(ok and ok2 and type(dl) == "table" and GC.mode == "none", "missing APIs: none mode, no error")
startFight(); M.fire("UNIT_AURA", "player", {}); endFight()
C_Secrets, C_UnitAuras = keepS, keepU
check(#ns.Core.errors == 0, "no Lua errors recorded")
M.done("GaleCount proc detection")
