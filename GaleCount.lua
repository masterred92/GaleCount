-- Gale Count: a Windfury tracker for Shamans on WoW: Forever. Written from scratch (MIT).
--
-- How it knows a Windfury proc happened: every Windfury proc on this client is its own spell (checked in the
-- client's SpellEffect table for build 1.60.1.70862): "apply aura: +attack power" plus "add extra attacks".
-- The player's own UNIT_SPELLCAST_SUCCEEDED names that spell; UNIT_AURA is a second, deduplicated source.
--
-- Where the damage comes from: addons on this client get no combat log and every hit amount is a secret value,
-- so Gale Count never guesses a number. It reads Blizzard's own damage meter (C_DamageMeter). In combat those
-- numbers are secret: they are only handed to widgets (text, bar), never compared or added. After combat they
-- are plain numbers, and that is when fight and session totals, share and average per proc are worked out.
local ADDON, ns = ...
local C, Core = ns.Compat, ns.Core
local L = Core.L

local GC = {}
KennyGaleCount = GC
ns.GC = GC

local SCHEMA = 1
local DEDUPE = 0.25 -- seconds: the cast event and the aura event for one proc arrive together

-- Proc spell -> what it is. extra = extra swings granted. Source: SpellName + SpellEffect (effect 19 =
-- Add Extra Attacks, aura 99 = Mod Melee Attack Power), wago.tools db2, build 1.60.1.70862.
GC.PROCS = {
  [8233]  = { kind = "weapon", rank = 1, extra = 2 },
  [8236]  = { kind = "weapon", rank = 2, extra = 2 },
  [10484] = { kind = "weapon", rank = 3, extra = 2 },
  [16361] = { kind = "weapon", rank = 4, extra = 2 },
  [8516]  = { kind = "totem", rank = 1, extra = 1 },
  [10608] = { kind = "totem", rank = 2, extra = 1 },
  [10610] = { kind = "totem", rank = 3, extra = 1 },
}

-- Built-in sound files (FileDataIDs, from the community listfile): no bundled audio.
GC.SOUNDS = {
  thunder = 568049, -- sound/spells/shaman_thunder.ogg
  crack = 565712,   -- sound/doodad/fx_thundercrack01.ogg
  bolt = 568516,    -- sound/spells/lightningboltimpact.ogg
}
GC.SOUND_MODES = { streak = true, every = true, record = true, off = true }

GC.DEFAULTS = {
  shown = true, locked = false, scale = 1, width = 240, height = 150,
  sound = "streak", soundFile = "theme", streakProcs = 2, streakSeconds = 4,
}

local db, settings
local migrations = {} -- schema 1 is the first release

local function now() return C.Clock() end

local function newFight()
  return { procs = 0, weapon = 0, totem = 0, extra = 0, start = now(), times = {} }
end
local function newSession()
  return { procs = 0, extra = 0, wf = 0, total = 0, fights = 0, measuredProcs = 0, bestAvg = 0, since = C.Now() }
end

GC.fight = newFight()
GC.lastProc = nil   -- { spellID, kind, rank, extra, t }
GC.lastFight = nil  -- result of the newest finished fight (plain numbers only)

function GC.DB() return db end
function GC.Settings() return settings end
function GC.Session() return db and db.session end

-- ---------- proc detection ----------
local lastSeen = {} -- spellID -> time, for the cast/aura dedupe

-- Count one proc. Returns true when it counted (false for unknown spells and duplicates).
function GC.OnProc(spellID, t)
  if C.IsSecret(spellID) then return false end
  local info = GC.PROCS[spellID]
  if not info then return false end
  t = t or now()
  if lastSeen[spellID] and t - lastSeen[spellID] < DEDUPE then return false end
  lastSeen[spellID] = t
  local f = GC.fight
  f.procs = f.procs + 1
  f[info.kind] = f[info.kind] + 1
  f.extra = f.extra + info.extra
  f.times[#f.times + 1] = t
  if db then
    db.session.procs = db.session.procs + 1
    db.session.extra = db.session.extra + info.extra
  end
  GC.lastProc = { spellID = spellID, kind = info.kind, rank = info.rank, extra = info.extra, t = t }
  if GC.ShouldThunder(t) then GC.Thunder() end
  if ns.UI then ns.UI.OnProc(GC.lastProc) end
  return true
end

-- Thunder rules, all from things this client lets an addon read in combat (proc timing, not damage):
-- streak = N procs within S seconds (default 2 in 4), every = every proc, record handled after the fight.
function GC.ShouldThunder(t)
  local mode = settings and settings.sound or GC.DEFAULTS.sound
  if mode == "every" then return true end
  if mode ~= "streak" then return false end
  local need, window = settings.streakProcs, settings.streakSeconds
  local times, n = GC.fight.times, 0
  for i = #times, 1, -1 do
    if t - times[i] <= window then n = n + 1 else break end
  end
  if n >= need then
    if GC.fight.streakUntil and t < GC.fight.streakUntil then return false end -- one rumble per streak
    GC.fight.streakUntil = t + window
    return true
  end
  return false
end

function GC.Thunder()
  local pick = settings and settings.soundFile or "theme"
  local id = (pick == "theme" and GC.theme and GC.theme.sound) or GC.SOUNDS[pick] or GC.SOUNDS.thunder
  local ok, willPlay = pcall(PlaySoundFile, id, "Master")
  return ok and willPlay ~= false
end

function GC.OnSpellcast(unit, _, spellID)
  if unit ~= "player" then return end
  GC.OnProc(spellID)
end

-- UNIT_AURA: added auras can be secret in combat on this client; any read that fails is skipped quietly.
function GC.OnAura(unit, updateInfo)
  if unit ~= "player" or type(updateInfo) ~= "table" or C.IsSecret(updateInfo) then return end
  local ok, added = pcall(function() return updateInfo.addedAuras end)
  if not ok or type(added) ~= "table" or C.IsSecret(added) then return end
  for _, aura in ipairs(added) do
    local ok2, id = pcall(function() return aura.spellId end)
    if ok2 then GC.OnProc(id) end
  end
end

-- ---------- Blizzard's damage meter ----------
local function playerGUID() return UnitGUID and UnitGUID("player") end

function GC.MeterAvailable()
  if not (C_DamageMeter and C_DamageMeter.IsDamageMeterAvailable) then return false, "no C_DamageMeter" end
  local ok, avail, why = pcall(C_DamageMeter.IsDamageMeterAvailable)
  if not ok then return false, tostring(avail) end
  return avail == true, why
end

-- The player's row of the newest finished meter session (by session ID), or of the current one.
function GC.MeterSource()
  if not C_DamageMeter then return nil end
  local guid = playerGUID()
  local dmg = Enum and Enum.DamageMeterType and Enum.DamageMeterType.DamageDone or 0
  if C_DamageMeter.GetAvailableCombatSessions and C_DamageMeter.GetCombatSessionSourceFromID then
    local ok, list = pcall(C_DamageMeter.GetAvailableCombatSessions)
    local newest
    if ok and type(list) == "table" then
      for _, s in ipairs(list) do
        local id = C.SafeNumber(s.sessionID)
        if id and (not newest or id > newest) then newest = id end
      end
    end
    if newest then
      local ok2, src = pcall(C_DamageMeter.GetCombatSessionSourceFromID, newest, dmg, guid)
      if ok2 and type(src) == "table" then return src end
    end
  end
  if C_DamageMeter.GetCombatSessionSourceFromType then
    local cur = Enum and Enum.DamageMeterSessionType and Enum.DamageMeterSessionType.Current or 1
    local ok, src = pcall(C_DamageMeter.GetCombatSessionSourceFromType, cur, dmg, guid)
    if ok and type(src) == "table" then return src end
  end
  return nil
end

-- The player's row of the fight in progress (values are secret while in combat).
function GC.LiveSource()
  if not (C_DamageMeter and C_DamageMeter.GetCombatSessionSourceFromType) then return nil end
  local cur = Enum and Enum.DamageMeterSessionType and Enum.DamageMeterSessionType.Current or 1
  local dmg = Enum and Enum.DamageMeterType and Enum.DamageMeterType.DamageDone or 0
  local ok, src = pcall(C_DamageMeter.GetCombatSessionSourceFromType, cur, dmg, playerGUID())
  if ok and type(src) == "table" then return src end
  return nil
end

-- Plain-number summary of a meter row: { total, wf, rows = { {spellID, amount} } }, or nil while anything is
-- secret (in combat) or missing. split = true when the meter lists Windfury proc spells as their own rows.
function GC.ReadMeter(src)
  src = src or GC.MeterSource()
  if type(src) ~= "table" then return nil, "no meter data" end
  local total = C.SafeNumber(src.totalAmount)
  if not total then return nil, "secret" end
  local out = { total = total, wf = 0, rows = {}, split = false }
  for _, sp in ipairs(type(src.combatSpells) == "table" and src.combatSpells or {}) do
    local id, amount = C.SafeNumber(sp.spellID), C.SafeNumber(sp.totalAmount)
    if not (id and amount) then return nil, "secret" end
    out.rows[#out.rows + 1] = { spellID = id, amount = amount }
    if GC.PROCS[id] then out.wf = out.wf + amount; out.split = true end
  end
  table.sort(out.rows, function(a, b) return a.amount > b.amount end)
  return out
end

-- ---------- fights ----------
function GC.StartFight()
  GC.fight = newFight()
  GC.fight.inCombat = true
  if ns.UI then ns.UI.OnCombat(true) end
end

-- Combat ended: the meter's numbers turn plain a moment later. Try a few times, then give up honestly.
function GC.EndFight()
  local f = GC.fight
  f.inCombat = false
  f.duration = math.max(0, now() - f.start)
  if ns.UI then ns.UI.OnCombat(false) end
  local tries = 0
  local function attempt()
    tries = tries + 1
    if GC.fight ~= f or f.done then return end
    local r = GC.ReadMeter()
    if r or tries >= 4 then GC.FinishFight(f, r) return end
    C_Timer.After(1, attempt)
  end
  C_Timer.After(0.5, attempt)
end

-- Fold a finished fight into the session. Numbers only count when the meter gave plain values.
function GC.FinishFight(f, r)
  f.done = true
  local res = { procs = f.procs, extra = f.extra, weapon = f.weapon, totem = f.totem, duration = f.duration or 0 }
  if r then
    res.total, res.split = r.total, r.split
    if r.split then
      res.wf = r.wf
      res.share = r.total > 0 and r.wf / r.total or 0
      res.avg = f.procs > 0 and r.wf / f.procs or nil
    end
  end
  GC.lastFight = res
  if db and (f.procs > 0 or (r and r.total > 0)) then
    local s = db.session
    s.fights = s.fights + 1
    if r then
      if r.split ~= db.meterSplits and f.procs > 0 then db.meterSplits = r.split end
      s.total = s.total + r.total
      if r.split then
        s.wf = s.wf + r.wf
        s.measuredProcs = s.measuredProcs + f.procs
        local isRecord = res.avg and res.avg > s.bestAvg and f.procs >= 2
        if isRecord then
          local beaten = s.bestAvg > 0
          s.bestAvg = res.avg
          res.record = beaten
          if beaten and settings.sound == "record" then GC.Thunder() end
        end
      end
    end
  end
  if ns.UI then ns.UI.Refresh() end
  return res
end

function GC.ResetSession()
  if not db then return end
  db.session = newSession()
  GC.lastFight = nil
  if ns.UI then ns.UI.Refresh() end
end

-- Session numbers worked out from plain values only.
function GC.SessionStats()
  local s = db and db.session
  if not s then return nil end
  return {
    procs = s.procs, extra = s.extra, wf = s.wf, total = s.total, fights = s.fights, bestAvg = s.bestAvg,
    share = (s.total > 0 and s.wf > 0) and s.wf / s.total or nil,
    avg = s.measuredProcs > 0 and s.wf / s.measuredProcs or nil,
  }
end

-- ---------- theme: class first, then the talent tree with the most points ----------
-- Forever has one specialization per class and puts the three classic trees in one C_Traits tree as node
-- groups (see Blizzard_PlayerSpells/Camelot/ClassTalents: GetGroupDisplayInfoByTreeID + GetGroupCurrencyInfo).
-- The old GetTalentTabInfo is only a deprecation shim for the Classic/Standard game types, so it isn't used.
local function hex(h)
  h = tostring(h or "FFFFFF")
  return tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255
end
GC.Hex = hex

-- Points per tree: { { skillLine, order, name, spent } }, or nil when the client can't tell (secret or missing).
function GC.TreePoints()
  if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits and C_Traits.GetConfigInfo
    and C_Traits.GetGroupDisplayInfoByTreeID and C_Traits.GetGroupCurrencyInfo) then return nil end
  local ok, configID = pcall(C_ClassTalents.GetActiveConfigID)
  configID = ok and C.SafeNumber(configID)
  if not configID then return nil end
  local ok2, cfg = pcall(C_Traits.GetConfigInfo, configID)
  local treeID = ok2 and type(cfg) == "table" and type(cfg.treeIDs) == "table" and C.SafeNumber(cfg.treeIDs[1])
  if not treeID then return nil end
  local ok3, displays = pcall(C_Traits.GetGroupDisplayInfoByTreeID, treeID)
  if not ok3 or type(displays) ~= "table" or #displays == 0 then return nil end
  local ids = {}
  for i, d in ipairs(displays) do ids[i] = d.groupID end
  local ok4, groups = pcall(C_Traits.GetGroupCurrencyInfo, configID, ids)
  if not ok4 or type(groups) ~= "table" then return nil end
  local spentBy = {}
  for _, g in ipairs(groups) do
    local cur = type(g.currencyInfos) == "table" and g.currencyInfos[1]
    local id = C.SafeNumber(g.traitNodeGroupID)
    if id and cur then spentBy[id] = C.SafeNumber(cur.spent) end
  end
  local out = {}
  for _, d in ipairs(displays) do
    out[#out + 1] = { skillLine = C.SafeNumber(d.skillLineID), order = C.SafeNumber(d.orderIndex) or #out,
      name = C.Safe(d.displayName), spent = spentBy[C.SafeNumber(d.groupID) or -1] or 0 }
  end
  table.sort(out, function(a, b) return a.order < b.order end)
  return out
end

-- The tree with the most points (ties and 0 points: none). Returns the class's tree entry, or nil.
function GC.PickTree(classTheme, points)
  if type(points) ~= "table" or not classTheme then return nil end
  local best, bestPos, second = nil, nil, -1
  for pos, t in ipairs(points) do
    if not best or t.spent > best.spent then
      if best then second = best.spent end
      best, bestPos = t, pos
    elseif t.spent > second then second = t.spent end
  end
  if not best or best.spent <= 0 or best.spent == second then return nil end
  local trees = classTheme.trees or {}
  if best.skillLine and trees[best.skillLine] then return trees[best.skillLine], best end
  local byOrder = classTheme.order and classTheme.order[bestPos]
  if byOrder and trees[byOrder] then return trees[byOrder], best end
  return nil
end

-- Resolve the theme: class colours and sound, with the top tree's accent/sound on top. Always returns a theme.
function GC.ResolveTheme(classFile, points)
  local THEMES = ns.THEMES or {}
  local base = THEMES[classFile] or THEMES[ns.THEME_FALLBACK] or { frame = "0070DE", accent = "3FA9FF", sound = GC.SOUNDS.thunder }
  local tree, info = GC.PickTree(base, points)
  local accent = tree and tree.accent or base.accent
  local th = { class = classFile, tree = info and info.name, treeSkillLine = info and info.skillLine,
    sound = tree and tree.sound or base.sound }
  th.frame = { hex(base.frame) }
  th.accent = { hex(accent) }
  return th
end

function GC.UpdateTheme()
  local classFile = UnitClass and select(2, UnitClass("player"))
  classFile = C.Safe(classFile)
  GC.theme = GC.ResolveTheme(classFile, GC.TreePoints())
  if ns.UI and ns.UI.ApplyTheme then ns.UI.ApplyTheme(GC.theme) end
  return GC.theme
end
GC.theme = GC.ResolveTheme(nil, nil)

-- ---------- text helpers ----------
function GC.Short(n)
  n = C.SafeNumber(n)
  if not n then return "?" end
  if n >= 1e6 then return ("%.1fM"):format(n / 1e6) end
  if n >= 1e4 then return ("%.1fK"):format(n / 1e3) end
  return tostring(math.floor(n + 0.5))
end
function GC.Pct(x) return x and ("%d%%"):format(math.floor(x * 100 + 0.5)) or "-" end

function GC.ProcName(p)
  if not p then return "-" end
  local what = p.kind == "totem" and L["Windfury Totem"] or L["Windfury Weapon"]
  return ("%s %d (+%d %s)"):format(what, p.rank, p.extra, p.extra == 1 and L["swing"] or L["swings"])
end

function GC.StateLines()
  local s = GC.SessionStats() or {}
  local avail, why = GC.MeterAvailable()
  local f = GC.lastFight
  return {
    "settings: sound=" .. tostring(settings and settings.sound) .. " file=" .. tostring(settings and settings.soundFile)
      .. " streak=" .. tostring(settings and settings.streakProcs) .. "/" .. tostring(settings and settings.streakSeconds) .. "s",
    "damage meter available: " .. tostring(avail) .. (why and why ~= "" and (" (" .. tostring(why) .. ")") or ""),
    "theme: " .. tostring(GC.theme and GC.theme.class) .. " / " .. tostring(GC.theme and GC.theme.tree or "class default"),
    "meter lists Windfury separately: " .. tostring(db and db.meterSplits),
    ("session: %s procs, %s fights, wf %s of %s"):format(tostring(s.procs), tostring(s.fights), GC.Short(s.wf), GC.Short(s.total)),
    "last fight: " .. (f and ("%d procs, total %s, wf %s"):format(f.procs, GC.Short(f.total), f.wf and GC.Short(f.wf) or "n/a") or "none"),
  }
end

-- ---------- events ----------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
ev:RegisterUnitEvent("UNIT_AURA", "player")
for _, e in ipairs({ "PLAYER_LOGIN", "TRAIT_CONFIG_UPDATED", "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_TALENT_UPDATE" }) do ev:RegisterEvent(e) end

local handlers = {
  PLAYER_REGEN_DISABLED = function() GC.StartFight() end,
  PLAYER_REGEN_ENABLED = function()
    GC.EndFight()
    if GC.themeStale then GC.themeStale = false; GC.UpdateTheme() end
  end,
  UNIT_SPELLCAST_SUCCEEDED = GC.OnSpellcast,
  UNIT_AURA = GC.OnAura,
  PLAYER_LOGIN = function() GC.UpdateTheme() end,
}
-- Talent changes re-pick the theme; in combat the repick waits for the fight to end.
local function talentsChanged() if C.InCombat() then GC.themeStale = true else GC.UpdateTheme() end end
handlers.TRAIT_CONFIG_UPDATED, handlers.ACTIVE_TALENT_GROUP_CHANGED, handlers.PLAYER_TALENT_UPDATE = talentsChanged, talentsChanged, talentsChanged

ev:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    if ... ~= ADDON then return end
    db = Core.Migrate(KennyGaleCountDB, migrations, SCHEMA)
    db.session = db.session or newSession()
    KennyGaleCountDB = db
    settings = Core.Settings(db.settings, GC.DEFAULTS)
    if ns.UI then Core.SafeCall("build", ns.UI.Build, db, settings) end
    return
  end
  local h = handlers[event]
  if h and db then Core.SafeCall(event, h, ...) end
end)

Core.Setup({ cmd = "/galecount",
  required = { "C_DamageMeter.GetCombatSessionSourceFromType", "C_DamageMeter.GetAvailableCombatSessions",
    "C_DamageMeter.GetCombatSessionSourceFromID", "PlaySoundFile", "C_Timer.After", "UnitGUID" },
  optional = { "C_DamageMeter.IsDamageMeterAvailable", "AbbreviateNumbers", "C_ClassTalents.GetActiveConfigID",
    "C_Traits.GetGroupDisplayInfoByTreeID", "C_Traits.GetGroupCurrencyInfo" },
  db = function() return db end,
  firstRun = { L["Windfury tracker ready. Drag the box to move it; /gc for options."] },
  debugLines = function() return GC.StateLines() end })
