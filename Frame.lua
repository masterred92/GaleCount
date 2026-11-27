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
-- 1.1.0 state, declared up here because the theme, layout and proc code below all read it
local streak = nil     -- { ends, len, count }: the live Windfury proc window ("aura" or "cast" mode only, never "none")
local preview = nil    -- { ends, len } while the /gale test preview runs
local draining = false -- frame.bar is the proc/streak drain bar (not the Windfury share bar)
local hovering = false -- the mouse is over the box (or one of its buttons)
local flashLeft = 0    -- seconds left of the proc flash
local ICON = "Interface\\Icons\\Spell_Nature_Cyclone"
local BAR = "Interface\\TargetingFrame\\UI-StatusBar"
local GRIP = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up"
local LOCKED, UNLOCKED = "Interface\\Buttons\\LockButton-Locked-Up", "Interface\\Buttons\\LockButton-Unlocked-Up" -- 525906, 525908
local GOLD = "|cffffd100" -- labels in the game's own gold, values in white
local MIN_W, MIN_H, MAX_W, MAX_H = 180, 120, 480, 300
local FADE_ALPHA = 0.35 -- idle fade: out of combat the box rests at 35% alpha
local COMPACT_H = 60    -- compact mode: one strip (headline + proc count, then the bar)
local LIFT = 0.35       -- the drain bar is the theme accent lifted 35% toward white, so it reads as "live"

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

-- The drain bar's colour: the theme accent, brightened.
function UI.DrainColor(th)
  th = th or GC.theme
  local r, g, b = unpack(th and th.accent or { 0.25, 0.66, 1 })
  return r + (1 - r) * LIFT, g + (1 - g) * LIFT, b + (1 - b) * LIFT
end

function UI.ApplyTheme(th)
  if not frame or not th then return end
  local fr, fg, fb = unpack(th.frame)
  local ar, ag, ab = unpack(th.accent)
  frame:SetBackdropBorderColor(fr, fg, fb, 1)
  -- the title is the class colour lifted 40% toward white, so dark colours (Shaman blue) stay readable on navy
  frame.title:SetTextColor(fr + (1 - fr) * 0.4, fg + (1 - fg) * 0.4, fb + (1 - fb) * 0.4)
  if draining then frame.bar:SetStatusBarColor(UI.DrainColor(th)) else frame.bar:SetStatusBarColor(ar, ag, ab) end
  frame.flash:SetColorTexture(ar, ag, ab, 1)
  frame.proc:SetTextColor(ar, ag, ab)
  frame.spark:SetColorTexture(ar, ag, ab, 0.9)
  frame.tree:SetText(th.tree or "")
end

-- Padlock icon and resize grip follow the lock setting (no grip in compact mode: the strip keeps its fixed height).
function UI.UpdateLock()
  if not frame then return end
  frame.lock.icon:SetTexture(settings.locked and LOCKED or UNLOCKED)
  frame.grip:SetShown(not settings.locked and not settings.compact)
  UI.UpdateMouse()
end

-- Layout and mouse changes. The box is a plain (non-secure) frame, so they are safe at any time; if it were ever
-- protected (say a secure parent), they wait for the end of combat instead of tainting anything.
local function mustWait()
  if C.InCombat() and frame:IsProtected() then UI.layoutPending = true return true end
  return false
end

-- Click-through: only while the box is locked AND the setting is on. The padlock and Reset button stop taking clicks
-- too, so a click really lands on the world; /gale unlock or /gale clickthrough gives clicks back.
function UI.ClickThroughActive() return settings.locked == true and settings.clickThrough == true end
function UI.UpdateMouse()
  if not frame or mustWait() then return end
  local through = UI.ClickThroughActive()
  frame:EnableMouse(not through)
  frame.lock:EnableMouse(not through)
  frame.reset:EnableMouse(not through)
  if through then hovering = false; UI.UpdateAlpha() end
end

-- Full layout, or compact: one strip with the headline, the proc count, the padlock and the bar. Compact never writes
-- settings.width / settings.height, so switching back restores the saved full size.
function UI.ApplyLayout()
  if not frame then return false end
  if mustWait() then return false end
  UI.layoutPending = false
  local compact = settings.compact == true
  frame:SetScale(settings.scale)
  frame:SetResizeBounds(MIN_W, compact and COMPACT_H or MIN_H, MAX_W, compact and COMPACT_H or MAX_H)
  frame:SetSize(settings.width, compact and COMPACT_H or settings.height)
  for _, w in ipairs({ frame.icon, frame.title, frame.tree, frame.spark, frame.lines }) do w:SetShown(not compact) end
  frame.count:SetShown(compact)
  frame.reset:SetShown(not compact and not C.InCombat())
  frame.proc:ClearAllPoints()
  frame.bar:ClearAllPoints()
  if compact then
    frame.proc:SetPoint("TOPLEFT", 10, -9)
    frame.proc:SetPoint("RIGHT", frame.count, "LEFT", -6, 0)
    frame.bar:SetPoint("BOTTOMLEFT", 10, 10)
    frame.bar:SetPoint("BOTTOMRIGHT", -10, 10)
  else
    frame.proc:SetPoint("TOPLEFT", 10, -33)
    frame.proc:SetPoint("RIGHT", -10, 0)
    frame.bar:SetPoint("BOTTOMLEFT", 10, 29)
    frame.bar:SetPoint("BOTTOMRIGHT", -10, 29)
  end
  UI.UpdateLock()
  return true
end

-- Idle fade: 35% out of combat; full in combat, under the mouse, during a proc flash or proc window and during the
-- test preview. SetAlpha on our own non-secure frame is fine in combat.
function UI.TargetAlpha()
  if not settings.fade then return 1 end
  if GC.fight.inCombat or C.InCombat() then return 1 end
  if hovering or draining or preview or flashLeft > 0 then return 1 end
  return FADE_ALPHA
end
function UI.UpdateAlpha()
  if frame then frame:SetAlpha(UI.TargetAlpha()) end
end
local function hoverOn() hovering = not UI.ClickThroughActive(); UI.UpdateAlpha() end
local function hoverCheck()
  hovering = frame:IsMouseOver() == true and not UI.ClickThroughActive()
  UI.UpdateAlpha()
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
  frame:SetScript("OnEnter", hoverOn)
  frame:SetScript("OnLeave", hoverCheck)
  -- right-click: the quick menu (out of combat only; see UI.OpenMenu)
  frame:SetScript("OnMouseUp", function(self, button) if button == "RightButton" then UI.OpenMenu(self) end end)
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
  frame.icon = icon
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
  lock:SetScript("OnClick", function() UI.SetLocked(not settings.locked) end)
  lock:SetScript("OnEnter", function(self)
    hoverOn()
    GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
    GameTooltip:SetText(settings.locked and L["Box locked"] or L["Box unlocked"])
    GameTooltip:AddLine(settings.locked and L["Click to unlock it."] or L["Drag the box to move it. Click to lock it."], 1, 1, 1, true)
    GameTooltip:AddLine(L["Right-click the box for quick options."], 1, 1, 1, true)
    if settings.clickThrough then -- the padlock can't be clicked once click-through is active, so say how to undo it
      GameTooltip:AddLine(UI.ClickThroughNote(), 1, 0.82, 0, true)
    end
    GameTooltip:Show()
  end)
  lock:SetScript("OnLeave", function() GameTooltip:Hide(); hoverCheck() end)
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
  -- compact mode only: the proc count, right of the headline
  frame.count = fs(frame, "GameFontHighlight")
  frame.count:SetPoint("RIGHT", lock, "LEFT", -6, 0)
  frame.count:SetJustifyH("RIGHT")
  frame.count:Hide()

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
  reset:HookScript("OnEnter", hoverOn)
  reset:HookScript("OnLeave", hoverCheck)
  frame.reset = reset
  reset:SetShown(not C.InCombat()) -- a /reload in combat gets no PLAYER_REGEN_DISABLED, so start hidden

  local grip = CreateFrame("Button", nil, frame)
  grip:SetSize(14, 14)
  grip:SetPoint("BOTTOMRIGHT", -4, 4)
  grip:SetNormalTexture(GRIP)
  grip:SetScript("OnMouseDown", function() if not settings.locked then frame:StartSizing("BOTTOMRIGHT") end end)
  grip:SetScript("OnEnter", hoverOn)
  grip:SetScript("OnLeave", hoverCheck)
  grip:SetScript("OnMouseUp", function()
    frame:StopMovingOrSizing()
    if settings.compact then return end -- the saved full size only changes in the full layout
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

  UI.ApplyLayout() -- also sets the padlock, grip and click-through
  UI.Place()
  UI.ApplyTheme(GC.theme)
  frame:SetShown(settings.shown)
  UI.Refresh()
  UI.UpdateAlpha()
  return frame
end

function UI.Frame() return frame end

local function clock() return C.Clock() end
-- The proc window: the streak window from the settings (/gale streak <procs> <seconds>, default 4s).
local function windowSeconds()
  return math.max(1, math.min(30, tonumber(settings and settings.streakSeconds) or GC.DEFAULTS.streakSeconds))
end

-- ---------- the live Windfury proc/streak drain bar ----------
-- When a counted proc lands ("aura" or "cast" mode, never "none") or the /gale test preview runs, frame.bar drains
-- over the streak window in the brightened accent colour with "WINDFURY! 3.2s" on it ("WINDFURY! x3 3.2s" once
-- procs chain inside the window; each proc restarts the window). When the window runs out the Windfury share bar
-- and the theme colour come back. In "none" mode no proc is seen, so nothing is ever guessed.
local drainText
local function drainState()
  if streak then
    local left = GC.mode ~= "none" and streak.ends - clock() or 0
    if left > 0 then return true, left, streak.len, streak.count end
    streak = nil
  end
  if preview then
    local left = preview.ends - clock()
    if left > 0 then return true, left, preview.len, 1 end
  end
  return false
end

local function updateDrain()
  if not frame then return end
  local active, left, len, count = drainState()
  if active then
    if not draining then
      draining, drainText = true, nil
      frame.bar:SetStatusBarColor(UI.DrainColor())
    end
    frame.bar:SetMinMaxValues(0, len)
    frame.bar:SetValue(math.min(left, len))
    local text = count >= 2 and ("%s x%d %.1fs"):format(L["WINDFURY!"], count, left) or ("%s %.1fs"):format(L["WINDFURY!"], left)
    if text ~= drainText then drainText = text; frame.barText:SetText(text) end
  elseif draining then
    draining, drainText = false, nil
    UI.RenderShareBar()
    if GC.fight.inCombat then UI.RenderLive() end -- the live share comes back at once, not on the next tick
    UI.UpdateAlpha()
  end
end
function UI.Draining() return draining end
function UI.PreviewActive() return preview ~= nil end
function UI.StreakActive() return streak ~= nil end

-- The /gale test preview ends when its window runs out, when combat starts or when a real proc shows up.
function UI.StopPreview()
  if not preview then return end
  preview = nil
  if not streak then frame.proc:SetText(UI.IdleHeadline()) end
  updateDrain()
  UI.UpdateAlpha()
end

-- One OnUpdate for the flash, the drain bar and the preview; it removes itself once all three are done.
local function onUpdate(_, elapsed)
  if flashLeft > 0 then
    flashLeft = flashLeft - elapsed
    frame.flash:SetAlpha(flashLeft > 0 and 0.45 * flashLeft / 0.5 or 0)
  end
  if preview and clock() >= preview.ends then UI.StopPreview() end
  updateDrain() -- every frame, so the bar drains smoothly
  if flashLeft <= 0 and not draining and not preview then
    flashLeft = 0
    frame:SetScript("OnUpdate", nil)
    UI.UpdateAlpha()
  end
end

local function flash()
  flashLeft = 0.5
  frame.flash:SetAlpha(0.45)
  frame:SetScript("OnUpdate", onUpdate)
end

function UI.OnProc(p)
  if not frame then return end
  preview = nil -- a real proc replaces the preview
  if GC.mode ~= "none" then -- procs are only ever seen in "aura" or "cast" mode; this just makes sure
    local t, len = (p and p.t) or clock(), windowSeconds()
    if streak and t < streak.ends then streak.count = streak.count + 1 else streak = { count = 1 } end
    streak.ends, streak.len = t + len, len
  end
  frame.proc:SetText(("%s +%d"):format(p.kind == "totem" and L["TOTEM WINDFURY!"] or L["WINDFURY!"], p.extra))
  flash()
  updateDrain()
  UI.UpdateAlpha()
  UI.Refresh()
end

-- /gale test: the whole proc look for one streak window (flash, headline, drain bar, sound), out of combat only.
function UI.StartPreview()
  if not frame or C.InCombat() then return false end
  local len = windowSeconds()
  streak = nil
  preview = { ends = clock() + len, len = len }
  frame.proc:SetText(("%s +%d"):format(L["WINDFURY!"], 2))
  flash()
  updateDrain()
  UI.UpdateAlpha()
  GC.Thunder()
  return true
end

-- Headline before the first proc: in "none" mode no proc will ever show, so say what will.
function UI.IdleHeadline()
  return GC.mode == "none" and L["Windfury damage after the fight"] or L["Waiting for Windfury..."]
end

function UI.OnCombat(inCombat)
  if frame then
    if inCombat then UI.StopPreview() end -- the box goes live; the preview never runs in a fight
    frame.reset:SetShown(not inCombat and not settings.compact) -- no Reset button in combat (or in compact mode)
    if inCombat then frame.proc:SetText(UI.IdleHeadline()) end -- a fresh headline for each fight
  end
  if inCombat and not ticker then
    ticker = C_Timer.NewTicker(0.5, function() Core.SafeCall("live", UI.RenderLive) end)
  elseif not inCombat and ticker then
    ticker:Cancel(); ticker = nil
  end
  if not inCombat and UI.layoutPending then UI.ApplyLayout() end
  UI.UpdateAlpha()
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
  frame.count:SetText(UI.CountText())
  updateDrain()
  if not draining then UI.RenderShareBar() end
end

-- The normal bar: last fight's (else the session's) Windfury share, in the theme accent.
function UI.RenderShareBar()
  if not frame then return end
  local th = GC.theme
  if th then frame.bar:SetStatusBarColor(unpack(th.accent)) end
  local f = GC.lastFight
  local share = f and f.share or (GC.SessionStats() or {}).share
  frame.bar:SetMinMaxValues(0, 1)
  frame.bar:SetValue(share or 0)
  frame.barText:SetText(L["Windfury share"] .. " " .. GC.Pct(share))
end

-- Compact mode's count: procs this fight (in combat), else last fight's.
function UI.CountText()
  local f = GC.fight.inCombat and GC.fight or GC.lastFight or GC.fight
  return ("%d %s"):format(f.procs or 0, procs(f.procs or 0))
end

-- Live view (in combat). Proc counts are plain; damage values may be secret and are only handed to widgets.
-- While the drain bar runs it keeps the bar; the live share comes back when the window ends.
function UI.RenderLive()
  if not frame then return end
  local f = GC.fight
  frame.count:SetText(UI.CountText())
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
      if not draining then
        frame.bar:SetMinMaxValues(0, total)
        frame.bar:SetValue(wfAmount)
        frame.barText:SetText(L["Windfury share (live)"])
      end
    else
      frame.lines:SetFormattedText("%s\n%s%s\n|cffaaaaaa%s|r", head, label(L["You"]), AbbreviateNumbers(total), L["Windfury damage after combat"])
    end
  else
    frame.lines:SetText(head)
  end
end

UI.MIN_W, UI.MIN_H, UI.MAX_W, UI.MAX_H = MIN_W, MIN_H, MAX_W, MAX_H
UI.FADE_ALPHA, UI.COMPACT_H = FADE_ALPHA, COMPACT_H

function UI.ClickThroughNote()
  return L["Click-through: while the box is locked, clicks pass through it. Type /gale unlock or /gale clickthrough to click it again."]
end

function UI.SetLocked(v)
  settings.locked = v and true or false
  UI.UpdateLock()
  Core.Print(settings.locked and L["frame locked."] or L["frame unlocked."])
  if UI.ClickThroughActive() then Core.Print(UI.ClickThroughNote()) end
end

local function onOff(v) return v and L["on"] or L["off"] end

-- ---------- slash command ----------
local function help()
  Core.Print("/gale show | hide | lock | unlock | resetpos | scale 0.5-2 | size <w> <h> | reset | test")
  Core.Print("/gale sound streak|every|record|off  |  soundfile theme|thunder|crack|bolt  |  streak <procs> <seconds>")
  Core.Print("/gale fade | compact | clickthrough | menu  (" .. L["right-click the box for the same quick menu"] .. ")")
  Core.Print(UI.ClickThroughNote())
  Core.Print("/gale meter (last fight's damage-meter rows) | theme | debug | report")
end

local function handle(msg)
  if not (db and frame) then return end
  local cmd, a, b = (msg or ""):lower():match("^(%S*)%s*(%S*)%s*(%S*)")
  if cmd == "show" then settings.shown = true; frame:Show(); UI.Refresh()
  elseif cmd == "hide" then settings.shown = false; frame:Hide()
  elseif cmd == "lock" then UI.SetLocked(true)
  elseif cmd == "unlock" then UI.SetLocked(false)
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
  elseif cmd == "fade" then
    settings.fade = not settings.fade; UI.UpdateAlpha()
    Core.Print(L["idle fade:"] .. " " .. onOff(settings.fade))
  elseif cmd == "compact" then
    settings.compact = not settings.compact; UI.ApplyLayout(); UI.Refresh()
    Core.Print(L["compact mode:"] .. " " .. onOff(settings.compact))
  elseif cmd == "clickthrough" then
    settings.clickThrough = not settings.clickThrough; UI.UpdateMouse()
    Core.Print(L["click-through when locked:"] .. " " .. onOff(settings.clickThrough))
    if settings.clickThrough then Core.Print(UI.ClickThroughNote()) end
  elseif cmd == "menu" then
    if not UI.OpenMenu(frame) and C.InCombat() then Core.Print(L["not in combat."]) end
  elseif cmd == "test" then
    if not UI.StartPreview() then Core.Print(L["not in combat."]) end
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

-- /gale first, /galecount as a backup. Not /gc: that is the game's own guild chat command and runs before any addon's.
SLASH_KENNYGALECOUNT1 = "/gale"
SLASH_KENNYGALECOUNT2 = "/galecount"
SlashCmdList.KENNYGALECOUNT = handle

-- ---------- right-click quick menu ----------
-- Blizzard's own context menu (MenuUtil, Blizzard_Menu). It only opens out of combat, and every entry checks again
-- when clicked, so a menu left open into a fight does nothing. Each entry runs the matching slash command.
local function act(msg) return function() if not C.InCombat() then handle(msg) end end end

function UI.BuildMenu(_, root)
  root:CreateTitle("Gale Count")
  local sound = root:CreateButton(L["Sound"])
  for _, m in ipairs({ { "streak", L["Streaks"] }, { "every", L["Every proc"] }, { "record", L["New best average only"] }, { "off", L["Off"] } }) do
    sound:CreateRadio(m[2], function() return settings.sound == m[1] end, act("sound " .. m[1]))
  end
  local file = root:CreateButton(L["Sound file"])
  for _, m in ipairs({ { "theme", L["Theme"] }, { "thunder", L["Thunder"] }, { "crack", L["Thundercrack"] }, { "bolt", L["Lightning bolt"] } }) do
    file:CreateRadio(m[2], function() return settings.soundFile == m[1] end, act("soundfile " .. m[1]))
  end
  root:CreateDivider()
  root:CreateCheckbox(L["Idle fade out of combat"], function() return settings.fade == true end, act("fade"))
  root:CreateCheckbox(L["Compact mode"], function() return settings.compact == true end, act("compact"))
  root:CreateCheckbox(L["Locked"], function() return settings.locked == true end,
    function() if not C.InCombat() then handle(settings.locked and "unlock" or "lock") end end)
  root:CreateCheckbox(L["Click-through when locked"], function() return settings.clickThrough == true end, act("clickthrough"))
  root:CreateDivider()
  root:CreateButton(L["Test preview"], act("test"))
  root:CreateButton(L["Reset session"], act("reset"))
  root:CreateButton(L["Reset position"], act("resetpos"))
end

-- Returns true when the menu opened. In combat, or without Blizzard's menu, nothing happens (no error, no taint).
function UI.OpenMenu(owner)
  if not frame or C.InCombat() then return false end
  if not (MenuUtil and MenuUtil.CreateContextMenu) then
    Core.Print(L["no quick menu on this client; type /gale for the commands."])
    return false
  end
  return (Core.SafeCall("menu", MenuUtil.CreateContextMenu, owner or frame, UI.BuildMenu))
end
