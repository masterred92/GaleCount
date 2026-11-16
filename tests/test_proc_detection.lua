-- Windfury procs as the WoW: Forever client delivers them in a real fight (issue #1).
-- In combat the UNIT_AURA payload is secret (UNIT_AURA: SecretWhenAurasRestricted, i.e. secret whenever combat
-- restrictions are on), so a proc has to be found by asking C_UnitAuras.GetPlayerAuraBySpellID for each proc
-- spell, which stays readable unless that one spell is flagged secret (SecretWhenUnitAuraRestricted).
-- Addons get no combat log on this client, so these replays use the events and APIs an addon can actually see.
package.path = "./tests/?.lua;" .. package.path
local M = require("mock_wow")
M.install()
local check = M.check

-- The player's auras as the client would report them. A secret entry stands for a spell flagged secret:
-- GetPlayerAuraBySpellID then returns no values (RequiresNonSecretAura).
local auras, nextInstance, secretSpell, auraCalls = {}, 100, {}, 0
C_UnitAuras = { GetPlayerAuraBySpellID = function(id)
  auraCalls = auraCalls + 1
  if secretSpell[id] then return end
  return auras[id]
end }
local function gain(id)
  nextInstance = nextInstance + 1
  auras[id] = { spellId = id, auraInstanceID = nextInstance, name = "Windfury Weapon" }
  return auras[id]
end
local function drop(id) auras[id] = nil end

-- A combat-time UNIT_AURA: the client hands over a payload whose contents are secret.
local function secretPayload(aura)
  local id = {}; M.secret[id] = true
  return { addedAuras = { { spellId = id, auraInstanceID = aura and aura.auraInstanceID } } }
end
local function fullySecretPayload() local p = {}; M.secret[p] = true; return p end

local ns = M.loadAddon(".", "GaleCount")
local GC = KennyGaleCount
M.fire("PLAYER_LOGIN")
local _ = ns

local function startFight() M.fire("PLAYER_REGEN_DISABLED"); M.combat = true end
local function endFight() M.combat = false; M.fire("PLAYER_REGEN_ENABLED"); M.advance(10) end

-- 1. Weapon proc in combat, no cast event: the aura appears (secret payload), the swing lands, the aura goes.
startFight()
local a = gain(16361)
M.fire("UNIT_AURA", "player", secretPayload(a))
check(GC.fight.procs == 1 and GC.fight.weapon == 1 and GC.fight.extra == 2, "weapon proc counted from a secret UNIT_AURA")
M.fire("UNIT_AURA", "player", { updatedAuraInstanceIDs = { a.auraInstanceID } })
check(GC.fight.procs == 1, "same aura updated: not counted again")
drop(16361)
M.fire("UNIT_AURA", "player", { removedAuraInstanceIDs = { a.auraInstanceID } })
check(GC.fight.procs == 1, "aura removed: nothing counted")

-- 2. Two procs from the same rank in a row: each new aura instance is a new proc.
M.advance(1)
a = gain(16361)
M.fire("UNIT_AURA", "player", fullySecretPayload())
check(GC.fight.procs == 2, "second weapon proc counted (whole payload secret)")
M.advance(0.4)
drop(16361); a = gain(16361) -- next proc replaced the aura before a removal update arrived
M.fire("UNIT_AURA", "player", secretPayload(a))
check(GC.fight.procs == 3, "back-to-back proc with a new aura instance counted")
drop(16361); M.fire("UNIT_AURA", "player", fullySecretPayload())

-- 3. Totem proc (Windfury Totem rank 3 gives 10610 to the player): one extra swing, counted as totem.
M.advance(1)
a = gain(10610)
M.fire("UNIT_AURA", "player", secretPayload(a))
check(GC.fight.procs == 4 and GC.fight.totem == 1 and GC.fight.extra == 7, "totem proc counted with 1 extra swing")
drop(10610); M.fire("UNIT_AURA", "player", fullySecretPayload())

-- 4. Every rank of both kinds is known (SpellEffect: effect 19 Add Extra Attacks).
for id, want in pairs({ [8233] = "weapon", [8236] = "weapon", [10484] = "weapon", [16361] = "weapon",
  [8516] = "totem", [10608] = "totem", [10610] = "totem" }) do
  M.advance(1)
  local before = GC.fight[want]
  a = gain(id)
  M.fire("UNIT_AURA", "player", secretPayload(a))
  check(GC.fight[want] == before + 1, "rank spell " .. id .. " counted as " .. want)
  drop(id); M.fire("UNIT_AURA", "player", fullySecretPayload())
end
local afterRanks = GC.fight.procs

-- 5. The cast event and the aura for one proc count once, whichever comes first.
M.advance(1)
M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3-1-1-1-16361-1", 16361)
a = gain(16361)
M.fire("UNIT_AURA", "player", secretPayload(a))
check(GC.fight.procs == afterRanks + 1, "cast then aura: one proc")
drop(16361); M.fire("UNIT_AURA", "player", fullySecretPayload())
M.advance(1)
a = gain(8236)
M.fire("UNIT_AURA", "player", secretPayload(a))
M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3-1-1-1-8236-2", 8236)
check(GC.fight.procs == afterRanks + 2, "aura then cast: one proc")
drop(8236); M.fire("UNIT_AURA", "player", fullySecretPayload())

-- 6. Things that must not count: other units' auras and casts, unrelated buffs, a spell the client keeps secret.
local n = GC.fight.procs
M.advance(1)
M.fire("UNIT_AURA", "party1", { addedAuras = { { spellId = 16361 } } })
M.fire("UNIT_SPELLCAST_SUCCEEDED", "party1", "Cast-3-1-1-1-16361-3", 16361)
M.fire("UNIT_SPELLCAST_SUCCEEDED", "pet", "Cast-3-1-1-1-16361-4", 16361)
check(GC.fight.procs == n, "another player's or a pet's Windfury is ignored")
gain(25289) -- Battle Shout, not a proc
M.fire("UNIT_AURA", "player", fullySecretPayload())
check(GC.fight.procs == n, "unrelated buff ignored")
drop(25289)
secretSpell[16361] = true; gain(16361)
local ok = pcall(M.fire, "UNIT_AURA", "player", fullySecretPayload())
check(ok and GC.fight.procs == n, "aura the client keeps secret: no count, no error")
secretSpell[16361] = nil; drop(16361); M.fire("UNIT_AURA", "player", fullySecretPayload())

-- 7. Spell names are never used, so a non-English client counts the same.
GetLocale = function() return "deDE" end
M.advance(1)
a = gain(10484); a.name = "Windfury-Waffe"
M.fire("UNIT_AURA", "player", secretPayload(a))
check(GC.fight.procs == n + 1, "German client: proc counted by spell ID")
drop(10484); M.fire("UNIT_AURA", "player", fullySecretPayload())

-- 8. The fight ends with the procs that were seen.
local procs = GC.fight.procs
endFight()
check(GC.lastFight and GC.lastFight.procs == procs and KennyGaleCountDB.session.procs == procs, "fight and session keep the procs")

-- 9. Out of combat the payload is readable: still one count per proc.
M.advance(5)
local before = KennyGaleCountDB.session.procs
a = gain(16361)
M.fire("UNIT_AURA", "player", { addedAuras = { a } })
M.fire("UNIT_AURA", "player", { updatedAuraInstanceIDs = { a.auraInstanceID } })
check(KennyGaleCountDB.session.procs == before + 1, "readable payload out of combat: one proc")
check(auraCalls > 0, "proc auras read through C_UnitAuras.GetPlayerAuraBySpellID")
M.done("GaleCount proc detection")
