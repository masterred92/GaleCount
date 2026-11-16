-- Secret-value rules of the WoW: Forever client for offline tests (not Blizzard code). Mirrors Blizzard's API docs
-- for builds 1.60.1.70532 and 70862:
--   * UNIT_AURA payload is secret while combat restrictions are on (SecretWhenAurasRestricted).
--   * C_UnitAuras.GetPlayerAuraBySpellID returns NOTHING for an aura that is secret (RequiresNonSecretAura), and
--     auras are secret in combat unless the spell is flagged never-secret (SecretWhenUnitAuraRestricted).
--   * C_Secrets.GetSpellAuraSecrecy: 0 never, 1 always, 2 contextually secret (Enum.SecrecyLevel).
--   * The player's UNIT_SPELLCAST_SUCCEEDED is not secret (SecretWhenUnitSpellCastRestricted only hides other units),
--     but whether the client fires it for a triggered proc spell is unknown, so tests switch it on or off.
-- Defaults are the strict case: restrictions on, nothing never-secret, no proc cast events.
local S = {}

function S.install(M)
  S.M = M
  S.restrictions = true -- C_Secrets.HasSecretRestrictions()
  S.never = {}          -- spellID -> true: flagged never-secret
  S.always = {}         -- spellID -> true: flagged always-secret
  S.castEvents = {}     -- spellID -> true: the client fires the player's UNIT_SPELLCAST_SUCCEEDED for this proc
  S.auras = {}          -- spellID -> AuraData currently on the player
  S.reads = 0
  S.nextInstance = 1000
  local function secretNow(id)
    if not S.restrictions or S.never[id] then return false end
    return S.always[id] or M.combat
  end
  S.secretNow = secretNow
  C_Secrets = {
    HasSecretRestrictions = function() return S.restrictions end,
    ShouldAurasBeSecret = function() return S.restrictions and M.combat or false end,
    GetSpellAuraSecrecy = function(id)
      if not S.restrictions or S.never[id] then return 0 end
      return S.always[id] and 1 or 2
    end,
    ShouldSpellAuraBeSecret = function(id) return secretNow(id) and true or false end,
  }
  C_UnitAuras = {
    GetPlayerAuraBySpellID = function(id)
      S.reads = S.reads + 1
      if secretNow(id) then return end -- RequiresNonSecretAura: no values at all
      return S.auras[id]
    end,
  }
  return S
end

-- A secret UNIT_AURA payload (in combat) or a plain one with the given added auras.
function S.payload(added)
  local M = S.M
  if S.restrictions and M.combat then local p = {}; M.secret[p] = true; return p end
  return { addedAuras = added or {} }
end

-- The aura appears (or is refreshed by a re-proc) on the player, then UNIT_AURA fires.
function S.gain(id, apps, duration)
  local M = S.M
  S.nextInstance = S.nextInstance + 1
  local a = { spellId = id, auraInstanceID = S.nextInstance, applications = apps or 0,
    expirationTime = M.clock + (duration or 10), duration = duration or 10 }
  S.auras[id] = a
  M.fire("UNIT_AURA", "player", S.payload({ a }))
  return a
end
-- Same aura instance, changed in place (charges used, or refreshed with more charges / a later expiry).
function S.update(id, apps, expirationTime)
  local a = S.auras[id]
  if apps then a.applications = apps end
  if expirationTime then a.expirationTime = expirationTime end
  S.M.fire("UNIT_AURA", "player", S.payload())
end
function S.drop(id)
  S.auras[id] = nil
  S.M.fire("UNIT_AURA", "player", S.payload())
end
-- A proc spell goes off: its cast event fires only if the client sends it for this spell.
local castN = 0
function S.procCast(id, unit)
  if not S.castEvents[id] then return false end
  castN = castN + 1
  S.M.fire("UNIT_SPELLCAST_SUCCEEDED", unit or "player", "Cast-3-1-1-1-" .. id .. "-" .. castN, id)
  return true
end
-- A cast the player made on purpose (always sent for the player), e.g. Shadow Bolt.
function S.cast(id, unit, castGUID)
  castN = castN + 1
  S.M.fire("UNIT_SPELLCAST_SUCCEEDED", unit or "player", castGUID or ("Cast-3-1-1-1-" .. id .. "-" .. castN), id)
end

return S
