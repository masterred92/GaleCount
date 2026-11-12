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
local MIN_W, MIN_H, MAX_W, MAX_H = 180, 120, 480, 300

local function fs(parent, font)
  local f = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
  f:SetJustifyH("LEFT")
  return f
end

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
  frame.title:SetTextColor(fr, fg, fb)
  frame.bar:SetStatusBarColor(ar, ag, ab)
  frame.flash:SetColorTexture(ar, ag, ab, 1)
  frame.proc:SetTextColor(ar, ag, ab)
  frame.spark:SetColorTexture(ar, ag, ab, 0.9)
  frame.tree:SetText(th.tree or "")
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
  frame.tree = fs(frame, "GameFontDisableSmall")
  frame.tree:SetPoint("TOPRIGHT", -9, -11)
  frame.tree:SetJustifyH("RIGHT")
  -- a thin lightning line under the title
  frame.spark = frame:CreateTexture(nil, "ARTWORK")
  frame.spark:SetHeight(1)
  frame.spark:SetPoint("TOPLEFT", 8, -28)
  frame.spark:SetPoint("TOPRIGHT", -8, -28)

  frame.proc = fs(frame, "GameFontNormalLarge")
  frame.proc:SetPoint("TOPLEFT", 10, -33)
  frame.proc:SetPoint("RIGHT", -10, 0)
  frame.proc:SetWordWrap(false)
  frame.lines = fs(frame)
  frame.lines:SetPoint("TOPLEFT", frame.proc, "BOTTOMLEFT", 0, -4)
  frame.lines:SetPoint("RIGHT", -10, 0)
  frame.lines:SetJustifyV("TOP")
  frame.lines:SetSpacing(2)

  frame.bar = CreateFrame("StatusBar", nil, frame)
  frame.bar:SetStatusBarTexture(BAR)
  frame.bar:SetPoint("BOTTOMLEFT", 10, 30)
  frame.bar:SetPoint("BOTTOMRIGHT", -10, 30)
  frame.bar:SetHeight(10)
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

function UI.OnCombat(inCombat)
  if inCombat and not ticker then
    ticker = C_Timer.NewTicker(0.5, function() Core.SafeCall("live", UI.RenderLive) end)
  elseif not inCombat and ticker then
    ticker:Cancel(); ticker = nil
  end
  UI.Refresh()
end

-- Plain-number view (out of combat): last fight + session.
function UI.Lines()
  local f, s = GC.lastFight, GC.SessionStats() or {}
  local out = {}
  if f then
    if f.wf then
      out[#out + 1] = ("%s: %d %s, %s %s (%s)"):format(L["Fight"], f.procs, L["procs"], GC.Short(f.wf), L["damage"], GC.Pct(f.share))
      out[#out + 1] = ("%s: %s%s"):format(L["Avg per proc"], f.avg and GC.Short(f.avg) or "-", f.record and ("  |cffffd200" .. L["new best!"] .. "|r") or "")
    else
      out[#out + 1] = ("%s: %d %s (+%d %s)"):format(L["Fight"], f.procs, L["procs"], f.extra, L["swings"])
    end
  else
    out[#out + 1] = ("%s: %d %s"):format(L["Fight"], GC.fight.procs, L["procs"])
  end
  out[#out + 1] = ("%s: %d %s, %s %s (%s)"):format(L["Session"], s.procs or 0, L["procs"], GC.Short(s.wf or 0), L["damage"], GC.Pct(s.share))
  out[#out + 1] = ("%s: %s   %s: %s"):format(L["Avg"], s.avg and GC.Short(s.avg) or "-", L["Best avg"], (s.bestAvg or 0) > 0 and GC.Short(s.bestAvg) or "-")
  if db and db.meterSplits == false then out[#out + 1] = "|cffaaaaaa" .. L["Game's meter has no separate Windfury row: counting procs only."] .. "|r" end
  return out
end

function UI.Refresh()
  if not frame then return end
  if GC.fight.inCombat then UI.RenderLive() return end
  if not frame.proc:GetText() or frame.proc:GetText() == "" then frame.proc:SetText(L["Waiting for Windfury..."]) end
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
  local head = ("%s: %d %s (+%d %s)"):format(L["Fight"], f.procs, L["procs"], f.extra, L["swings"])
  if total ~= nil and AbbreviateNumbers then
    if wfRows == 1 then
      frame.lines:SetFormattedText("%s\n%s: %s   %s: %s", head, L["Windfury"], AbbreviateNumbers(wfAmount), L["You"], AbbreviateNumbers(total))
      frame.bar:SetMinMaxValues(0, total)
      frame.bar:SetValue(wfAmount)
      frame.barText:SetText(L["Windfury share (live)"])
    else
      frame.lines:SetFormattedText("%s\n%s: %s\n%s", head, L["You"], AbbreviateNumbers(total), L["Windfury damage after combat"])
    end
  else
    frame.lines:SetText(head)
  end
end

UI.MIN_W, UI.MIN_H, UI.MAX_W, UI.MAX_H = MIN_W, MIN_H, MAX_W, MAX_H

-- ---------- slash command ----------
local function help()
  Core.Print("/galecount show | hide | lock | unlock | resetpos | scale 0.5-2 | size <w> <h> | reset | test")
  Core.Print("/galecount sound streak|every|record|off  |  soundfile theme|thunder|crack|bolt  |  streak <procs> <seconds>")
  Core.Print("/galecount meter (last fight's damage-meter rows) | theme | debug | report")
end

SLASH_KENNYGALECOUNT1 = "/galecount"
SLASH_KENNYGALECOUNT2 = "/gale"
SlashCmdList.KENNYGALECOUNT = function(msg)
  if not (db and frame) then return end
  local cmd, a, b = (msg or ""):lower():match("^(%S*)%s*(%S*)%s*(%S*)")
  if cmd == "show" then settings.shown = true; frame:Show(); UI.Refresh()
  elseif cmd == "hide" then settings.shown = false; frame:Hide()
  elseif cmd == "lock" then settings.locked = true; Core.Print(L["frame locked."])
  elseif cmd == "unlock" then settings.locked = false; Core.Print(L["frame unlocked."])
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
