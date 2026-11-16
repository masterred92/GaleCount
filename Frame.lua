-- Gale Count window: a small storm-themed box. Blizzard textures and fonts only.
-- In combat the damage numbers from Blizzard's meter are secret: they go straight into SetFormattedText and
-- StatusBar values (both accept secret values) and are never compared or added here.
local _, ns = ...
local C, Core = ns.Compat, ns.Core
local L = Core.L
local GC = ns.GC

local UI = {}
ns.UI = UI
local frame, db, settings, ticker
local ICON = "Interface\\Icons\\Spell_Nature_Cyclone"
local BAR = "Interface\\TargetingFrame\\UI-StatusBar"
local GRIP = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up"
local LOCKED, UNLOCKED = "Interface\\Buttons\\LockButton-Locked-Up", "Interface\\Buttons\\LockButton-Unlocked-Up" -- 525906, 525908
local GOLD = "|cffffd100" -- labels in the game's own gold, values in white
local MIN_W, MIN_H, MAX_W, MAX_H = 180, 120, 480, 300

local function fs(parent, font)
  local f = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
  f:SetJustifyH("LEFT")
  return f
end

-- "Fight: " in gold, so the numbers after it are easy to pick out
local function label(text) return GOLD .. text .. ":|r " end
local function procs(n) return n == 1 and L["proc"] or L["procs"] end

function UI.Place()
  local p = db.point or { "CENTER", 0, -180 }
  frame:ClearAllPoints()
  frame:SetPoint(p[1], UIParent, p[1], p[2], p[3])
end

function UI.ApplyTheme(th)
  if not frame or not th then return end
  local fr, fg, fb = unpack(th.frame)
  local ar, ag, ab = unpack(th.accent)
  frame:SetBackdropBorderColor(fr, fg, fb, 1)
  -- the title is the class colour lifted 40% toward white, so dark colours (Shaman blue) stay readable on navy
  frame.title:SetTextColor(fr + (1 - fr) * 0.4, fg + (1 - fg) * 0.4, fb + (1 - fb) * 0.4)
  frame.bar:SetStatusBarColor(ar, ag, ab)
  frame.flash:SetColorTexture(ar, ag, ab, 1)
  frame.proc:SetTextColor(ar, ag, ab)
  frame.spark:SetColorTexture(ar, ag, ab, 0.9)
  frame.tree:SetText(th.tree or "")
end

-- Padlock icon and resize grip follow the lock setting.
function UI.UpdateLock()
  if not frame then return end
  frame.lock.icon:SetTexture(settings.locked and LOCKED or UNLOCKED)
  frame.grip:SetShown(not settings.locked)
end

function UI.ApplyLayout()
  frame:SetSize(settings.width, settings.height)
  frame:SetScale(settings.scale)
end

function UI.Build(database, s)
  db, settings = database, s
  frame = CreateFrame("Frame", "KennyGaleCountFrame", UIParent, "BackdropTemplate")
  frame:SetFrameStrata("MEDIUM")
  frame:SetClampedToScreen(true)
  frame:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 } })
  frame:SetBackdropColor(0.02, 0.05, 0.12, 0.85) -- storm-night navy
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:SetResizable(true)
  frame:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self) if not settings.locked then self:StartMoving() end end)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, _, x, y = self:GetPoint()
    db.point = { p, x, y }
  end)

  local icon = frame:CreateTexture(nil, "ARTWORK")
  icon:SetTexture(ICON)
  icon:SetSize(18, 18)
  icon:SetPoint("TOPLEFT", 8, -7)
  frame.title = fs(frame, "GameFontNormal")
  frame.title:SetPoint("LEFT", icon, "RIGHT", 5, 0)
  frame.title:SetText("Gale Count")
  -- padlock, top right: click to lock or unlock the box (same as /gale lock and /gale unlock)
  local lock = CreateFrame("Button", nil, frame)
  lock:SetSize(16, 16)
  lock:SetPoint("TOPRIGHT", -7, -8)
  lock.icon = lock:CreateTexture(nil, "ARTWORK")
  lock.icon:SetAllPoints()
  lock.icon:SetTexCoord(6 / 32, 25 / 32, 7 / 32, 25 / 32) -- just the padlock, not the empty edge of the texture
  lock:SetScript("OnClick", function()
    settings.locked = not settings.locked
    UI.UpdateLock()
    Core.Print(settings.locked and L["frame locked."] or L["frame unlocked."])
  end)
  lock:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
    GameTooltip:SetText(settings.locked and L["Box locked"] or L["Box unlocked"])
    GameTooltip:AddLine(settings.locked and L["Click to unlock it."] or L["Drag the box to move it. Click to lock it."], 1, 1, 1, true)
    GameTooltip:Show()
  end)
  lock:SetScript("OnLeave", function() GameTooltip:Hide() end)
  frame.lock = lock
  frame.tree = fs(frame, "GameFontDisableSmall")
  frame.tree:SetPoint("RIGHT", lock, "LEFT", -2, 0)
  frame.tree:SetJustifyH("RIGHT")
  frame.title:SetPoint("RIGHT", frame.tree, "LEFT", -4, 0)
  frame.title:SetWordWrap(false)
  -- a thin lightning line under the title
  frame.spark = frame:CreateTexture(nil, "ARTWORK")
  frame.spark:SetHeight(1)
  frame.spark:SetPoint("TOPLEFT", 8, -28)
  frame.spark:SetPoint("TOPRIGHT", -8, -28)

  frame.proc = fs(frame, "GameFontNormalLarge")
  frame.proc:SetPoint("TOPLEFT", 10, -33)
  frame.proc:SetPoint("RIGHT", -10, 0)
  frame.proc:SetWordWrap(false)
  frame.lines = fs(frame, "GameFontHighlight") -- 12 pt (was 10 pt)
  frame.lines:SetPoint("TOPLEFT", frame.proc, "BOTTOMLEFT", 0, -4)
  frame.lines:SetPoint("RIGHT", -10, 0)
  frame.lines:SetJustifyV("TOP")
  frame.lines:SetSpacing(2)

  frame.bar = CreateFrame("StatusBar", nil, frame)
  frame.bar:SetStatusBarTexture(BAR)
  frame.bar:SetPoint("BOTTOMLEFT", 10, 29)
  frame.bar:SetPoint("BOTTOMRIGHT", -10, 29)
  frame.bar:SetHeight(12) -- was 10
  frame.lines:SetPoint("BOTTOM", frame.bar, "TOP", 0, 1) -- extra lines are cut off instead of running into the bar
  frame.bar:SetMinMaxValues(0, 1)
  frame.bar:SetValue(0)
  local barBg = frame.bar:CreateTexture(nil, "BACKGROUND")
  barBg:SetAllPoints()
  barBg:SetColorTexture(0, 0, 0, 0.5)
  frame.barText = fs(frame.bar, "GameFontHighlightSmall")
  frame.barText:SetPoint("CENTER")

  local reset = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  reset:SetSize(96, 18)
  reset:SetPoint("BOTTOMLEFT", 8, 7)
  reset:SetText(L["Reset session"])
  reset:SetScript("OnClick", function() GC.ResetSession(); Core.Print(L["session reset."]) end)
  frame.reset = reset
  reset:SetShown(not C.InCombat()) -- a /reload in combat gets no PLAYER_REGEN_DISABLED, so start hidden

  local grip = CreateFrame("Button", nil, frame)
  grip:SetSize(14, 14)
  grip:SetPoint("BOTTOMRIGHT", -4, 4)
  grip:SetNormalTexture(GRIP)
  grip:SetScript("OnMouseDown", function() if not settings.locked then frame:StartSizing("BOTTOMRIGHT") end end)
  grip:SetScript("OnMouseUp", function()
    frame:StopMovingOrSizing()
    settings.width = math.floor(frame:GetWidth() + 0.5)
    settings.height = math.floor(frame:GetHeight() + 0.5)
  end)
  frame.grip = grip

  -- proc flash: the whole box lights up in the accent colour and fades over half a second
  frame.flash = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
  frame.flash:SetPoint("TOPLEFT", 3, -3)
  frame.flash:SetPoint("BOTTOMRIGHT", -3, 3)
  frame.flash:SetBlendMode("ADD")
  frame.flash:SetAlpha(0)

  UI.ApplyLayout()
  UI.Place()
  UI.ApplyTheme(GC.theme)
  UI.UpdateLock()
  frame:SetShown(settings.shown)
  UI.Refresh()
  return frame
end

function UI.Frame() return frame end

local flashLeft = 0
local function flashTick(_, elapsed)
  flashLeft = flashLeft - elapsed
  if flashLeft <= 0 then frame.flash:SetAlpha(0); frame:SetScript("OnUpdate", nil) return end
  frame.flash:SetAlpha(0.45 * flashLeft / 0.5)
end

function UI.OnProc(p)
  if not frame then return end
  frame.proc:SetText(("%s +%d"):format(p.kind == "totem" and L["TOTEM WINDFURY!"] or L["WINDFURY!"], p.extra))
  flashLeft = 0.5
  frame.flash:SetAlpha(0.45)
  frame:SetScript("OnUpdate", flashTick)
  UI.Refresh()
end

-- Headline before the first proc: in "none" mode no proc will ever show, so say what will.
function UI.IdleHeadline()
  return GC.mode == "none" and L["Windfury damage after the fight"] or L["Waiting for Windfury..."]
end

function UI.OnCombat(inCombat)
  if frame then
    frame.reset:SetShown(not inCombat) -- no Reset button in combat, so a stray click can't wipe the session
    if inCombat then frame.proc:SetText(UI.IdleHeadline()) end -- a fresh headline for each fight
  end
  if inCombat and not ticker then
    ticker = C_Timer.NewTicker(0.5, function() Core.SafeCall("live", UI.RenderLive) end)
  elseif not inCombat and ticker then
    ticker:Cancel(); ticker = nil
  end
  UI.Refresh()
end

-- Plain-number view (out of combat): last fight + session, one short line each. Labels gold, numbers white.
-- "none" mode: no proc counts, only what the game's meter says after the fight. No Windfury row = say so.
local NOTE_NONE = "|cffaaaaaa" .. L["Procs can't be counted on this client: the game hides them from addons. Windfury damage shows after each fight when the game's meter lists it."] .. "|r"
function UI.MeterOnlyLines(f, s)
  local out = {}
  if f and f.wf then
    out[#out + 1] = label(L["Fight"]) .. ("%s %s · %s"):format(GC.Short(f.wf), L["damage"], GC.Pct(f.share))
  elseif f and f.total then
    out[#out + 1] = label(L["Fight"]) .. L["the game's meter has no separate Windfury row"]
  elseif f then
    out[#out + 1] = label(L["Fight"]) .. L["no meter data"]
  end
  if (s.wf or 0) > 0 then
    out[#out + 1] = label(L["Session"]) .. ("%s %s · %s"):format(GC.Short(s.wf), L["damage"], GC.Pct(s.share))
  end
  out[#out + 1] = NOTE_NONE
  return out
end

function UI.Lines()
  local f, s = GC.lastFight, GC.SessionStats() or {}
  local countOnly = db and db.meterSplits == false
  if not f and (s.procs or 0) == 0 and (s.fights or 0) == 0 and GC.fight.procs == 0 then
    if GC.mode == "none" then return { L["No fights yet."], NOTE_NONE } end
    return { L["No fights yet."], "|cffaaaaaa" .. L["Fight with Windfury on and the procs show up here."] .. "|r" }
  end
  if GC.mode == "none" then return UI.MeterOnlyLines(f, s) end
  local out = {}
  if f and f.wf then
    out[#out + 1] = label(L["Fight"]) .. ("%d %s · %s %s · %s"):format(f.procs, procs(f.procs), GC.Short(f.wf), L["damage"], GC.Pct(f.share))
  elseif f then
    out[#out + 1] = label(L["Fight"]) .. ("%d %s · +%d %s"):format(f.procs, procs(f.procs), f.extra, f.extra == 1 and L["swing"] or L["swings"])
  else
    out[#out + 1] = label(L["Fight"]) .. ("%d %s"):format(GC.fight.procs, procs(GC.fight.procs))
  end
  if countOnly then
    out[#out + 1] = label(L["Session"]) .. ("%d %s"):format(s.procs or 0, procs(s.procs or 0))
  else
    out[#out + 1] = label(L["Session"]) .. ("%d %s · %s · %s"):format(s.procs or 0, procs(s.procs or 0), GC.Short(s.wf or 0), GC.Pct(s.share))
    -- last fight's average, the session's, then the best; a record shows "new best!" (the fight's average is the best)
    local tail = (f and f.record) and ("  |cffffd200" .. L["new best!"] .. "|r")
      or (" · %s %s"):format(L["best"], (s.bestAvg or 0) > 0 and GC.Short(s.bestAvg) or "-")
    out[#out + 1] = label(L["Per proc"]) .. ("%s · %s %s"):format(f and f.avg and GC.Short(f.avg) or "-", L["avg"], s.avg and GC.Short(s.avg) or "-") .. tail
  end
  if countOnly then out[#out + 1] = "|cffaaaaaa" .. L["Game's meter has no separate Windfury row: counting procs only."] .. "|r" end
  return out
end

function UI.Refresh()
  if not frame then return end
  if GC.fight.inCombat then UI.RenderLive() return end
  if not frame.proc:GetText() or frame.proc:GetText() == "" then frame.proc:SetText(UI.IdleHeadline()) end
  frame.lines:SetText(table.concat(UI.Lines(), "\n"))
  local f = GC.lastFight
  local share = f and f.share or (GC.SessionStats() or {}).share
  frame.bar:SetMinMaxValues(0, 1)
  frame.bar:SetValue(share or 0)
  frame.barText:SetText(L["Windfury share"] .. " " .. GC.Pct(share))
end

-- Live view (in combat). Proc counts are plain; damage values may be secret and are only handed to widgets.
function UI.RenderLive()
  if not frame then return end
  local f = GC.fight
  local src = GC.LiveSource and GC.LiveSource()
  local total = src and src.totalAmount
  local wfAmount, wfRows = nil, 0
  if src and type(src.combatSpells) == "table" and not C.IsSecret(src.combatSpells) then
    for _, sp in ipairs(src.combatSpells) do
      local id = sp.spellID
      if not C.IsSecret(id) and GC.PROCS[id] then wfRows = wfRows + 1; wfAmount = sp.totalAmount end
    end
  end
  local head = GC.mode == "none" and ("|cffaaaaaa" .. L["Procs can't be counted on this client."] .. "|r")
    or label(L["Fight"]) .. ("%d %s · +%d %s"):format(f.procs, procs(f.procs), f.extra, f.extra == 1 and L["swing"] or L["swings"])
  if total ~= nil and AbbreviateNumbers then
    if wfRows == 1 then
      frame.lines:SetFormattedText("%s\n%s%s   %s%s", head, label(L["Windfury"]), AbbreviateNumbers(wfAmount), label(L["You"]), AbbreviateNumbers(total))
      frame.bar:SetMinMaxValues(0, total)
      frame.bar:SetValue(wfAmount)
      frame.barText:SetText(L["Windfury share (live)"])
    else
      frame.lines:SetFormattedText("%s\n%s%s\n|cffaaaaaa%s|r", head, label(L["You"]), AbbreviateNumbers(total), L["Windfury damage after combat"])
    end
  else
    frame.lines:SetText(head)
  end
end

UI.MIN_W, UI.MIN_H, UI.MAX_W, UI.MAX_H = MIN_W, MIN_H, MAX_W, MAX_H

-- ---------- slash command ----------
local function help()
  Core.Print("/gale show | hide | lock | unlock | resetpos | scale 0.5-2 | size <w> <h> | reset | test")
  Core.Print("/gale sound streak|every|record|off  |  soundfile theme|thunder|crack|bolt  |  streak <procs> <seconds>")
  Core.Print("/gale meter (last fight's damage-meter rows) | theme | debug | report")
end

-- /gale first, /galecount as a backup. Not /gc: that is the game's own guild chat command and runs before any addon's.
SLASH_KENNYGALECOUNT1 = "/gale"
SLASH_KENNYGALECOUNT2 = "/galecount"
SlashCmdList.KENNYGALECOUNT = function(msg)
  if not (db and frame) then return end
  local cmd, a, b = (msg or ""):lower():match("^(%S*)%s*(%S*)%s*(%S*)")
  if cmd == "show" then settings.shown = true; frame:Show(); UI.Refresh()
  elseif cmd == "hide" then settings.shown = false; frame:Hide()
  elseif cmd == "lock" then settings.locked = true; UI.UpdateLock(); Core.Print(L["frame locked."])
  elseif cmd == "unlock" then settings.locked = false; UI.UpdateLock(); Core.Print(L["frame unlocked."])
  elseif cmd == "resetpos" then
    db.point = nil; settings.width, settings.height, settings.scale = GC.DEFAULTS.width, GC.DEFAULTS.height, 1
    UI.ApplyLayout(); UI.Place(); Core.Print(L["frame moved back to its default spot and size."])
  elseif cmd == "scale" and tonumber(a) then
    settings.scale = math.max(0.5, math.min(2, tonumber(a))); UI.ApplyLayout()
  elseif cmd == "size" and tonumber(a) and tonumber(b) then
    settings.width = math.max(MIN_W, math.min(MAX_W, math.floor(tonumber(a))))
    settings.height = math.max(MIN_H, math.min(MAX_H, math.floor(tonumber(b))))
    UI.ApplyLayout()
  elseif cmd == "reset" then GC.ResetSession(); Core.Print(L["session reset."])
  elseif cmd == "sound" and GC.SOUND_MODES[a] then settings.sound = a; Core.Print(L["thunder:"] .. " " .. a)
  elseif cmd == "soundfile" and (a == "theme" or GC.SOUNDS[a]) then settings.soundFile = a; GC.Thunder()
  elseif cmd == "streak" and tonumber(a) and tonumber(b) then
    settings.streakProcs = math.max(2, math.min(10, math.floor(tonumber(a))))
    settings.streakSeconds = math.max(1, math.min(30, tonumber(b)))
    Core.Print(("%s %d %s %s %ss"):format(L["thunder on"], settings.streakProcs, L["procs"], L["within"], settings.streakSeconds))
  elseif cmd == "test" then
    if C.InCombat() then Core.Print(L["not in combat."]) return end
    UI.OnProc({ kind = "weapon", rank = 4, extra = 2 }); GC.Thunder()
  elseif cmd == "theme" then
    local th = GC.UpdateTheme()
    Core.Print(L["theme"] .. ": " .. tostring(th.class) .. " / " .. tostring(th.tree or L["class default"]))
  elseif cmd == "meter" then
    if C.InCombat() then Core.Print(L["not in combat."]) return end
    local r, why = GC.ReadMeter()
    if not r then Core.Print(L["no readable meter data"] .. " (" .. tostring(why) .. ")") return end
    Core.Print(("%s %s"):format(L["your damage:"], GC.Short(r.total)))
    for i = 1, math.min(8, #r.rows) do
      local row = r.rows[i]
      local name = C_Spell and C_Spell.GetSpellName and C.Safe(C_Spell.GetSpellName(row.spellID)) or "?"
      Core.Print(("  %d  %s  %s%s"):format(row.spellID, tostring(name), GC.Short(row.amount), GC.PROCS[row.spellID] and "  <- Windfury" or ""))
    end
  elseif cmd == "debug" then Core.PrintDebug()
  elseif cmd == "report" then Core.ShowReport(GC.StateLines())
  else help() end
end
