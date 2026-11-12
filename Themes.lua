-- Gale Count themes: class first, then talent tree. Plain data, easy to tweak.
--   frame  = border/title colour (hex RRGGBB), accent = bars, flash and highlights, sound = built-in FileDataID.
-- A talent tree entry overrides only what it lists (accent and/or sound); anything missing comes from the class.
-- Trees are keyed by the client's SkillLine ID (locale-free; IDs from the SkillLine table, build 1.60.1.70862).
-- `order` is the class's tree order, used when a tree's SkillLine ID isn't recognised.
-- Every sound and texture here was checked to exist in build 1.60.1.70862 (see tools/verify_media.sh).
local _, ns = ...

ns.THEMES = {
  WARRIOR = { frame = "C79C6E", accent = "E0B070", sound = 568028, order = { 26, 256, 257 }, -- battleshouttarget
    trees = { [26] = { accent = "C0392B", sound = 568003 },   -- Arms: rend
              [256] = { accent = "FF5A1F", sound = 568812 },  -- Fury: bloodlust cast
              [257] = { accent = "A0A8B8", sound = 569222 } } }, -- Protection: thunderclap
  PALADIN = { frame = "F58CBA", accent = "FFE38A", sound = 569402, order = { 594, 267, 184 }, -- holybolt
    trees = { [594] = { accent = "FFF4C2", sound = 569383 },  -- Holy: holy light
              [267] = { accent = "E8C060", sound = 568491 },  -- Protection: holy protection
              [184] = { accent = "FFB000", sound = 568169 } } }, -- Retribution: judgement
  HUNTER = { frame = "ABD473", accent = "C8E09A", sound = 568411, order = { 50, 163, 51 }, -- concussive shot
    trees = { [50] = { accent = "D08A3C", sound = 564210 },   -- Beast Mastery: wolf attack
              [163] = { accent = "E6E6B0", sound = 568411 },  -- Marksmanship: concussive shot
              [51] = { accent = "8FBF5A", sound = 568026 } } }, -- Survival: explosive impact
  ROGUE = { frame = "FFF569", accent = "FFE04D", sound = 569227, order = { 253, 38, 39 }, -- sinister strike
    trees = { [253] = { accent = "6FD34A", sound = 568950 },  -- Assassination: poison
              [38] = { accent = "FFD24D", sound = 569227 },   -- Combat: sinister strike
              [39] = { accent = "7A6FA8", sound = 569423 } } }, -- Subtlety: stealth
  PRIEST = { frame = "FFFFFF", accent = "FFF0B0", sound = 569211, order = { 613, 56, 78 }, -- holy impact
    trees = { [613] = { accent = "D8E8FF", sound = 569408 },  -- Discipline: holy ward
              [56] = { accent = "FFF4C2", sound = 569570 },   -- Holy: heal
              [78] = { accent = "8A4FD8", sound = 569040 } } }, -- Shadow: shadowform
  SHAMAN = { frame = "0070DE", accent = "3FA9FF", sound = 568049, order = { 375, 373, 374 }, -- shaman thunder
    trees = { [375] = { accent = "BFE6FF", sound = 568516 },  -- Elemental: lightning bolt impact
              [373] = { accent = "3FA9FF", sound = 568049 },  -- Enhancement: storm / Windfury thunder
              [374] = { accent = "2EC8C0", sound = 569133 } } }, -- Restoration: water shield
  MAGE = { frame = "69CCF0", accent = "B48CFF", sound = 568678, order = { 237, 8, 6 }, -- arcane explosion
    trees = { [237] = { accent = "D070FF", sound = 568678 },  -- Arcane: arcane explosion
              [8] = { accent = "FF7A1A", sound = 568461 },    -- Fire: fireball impact
              [6] = { accent = "9FE7FF", sound = 569378 } } }, -- Frost: frost nova
  WARLOCK = { frame = "9482C9", accent = "8A4FD8", sound = 568588, order = { 355, 354, 593 }, -- shadowflame
    trees = { [355] = { accent = "7B3FC4", sound = 569040 },  -- Affliction: shadow
              [354] = { accent = "9B59D0", sound = 569267 },  -- Demonology: fel armor
              [593] = { accent = "5CE65C", sound = 568508 } } }, -- Destruction: fel fire (chaos bolt)
  DRUID = { frame = "FF7D0A", accent = "7FD36A", sound = 569023, order = { 574, 134, 573 }, -- moonfire
    trees = { [574] = { accent = "8FB3FF", sound = 568008 },  -- Balance: starfire
              [134] = { accent = "FFB347", sound = 569315 },  -- Feral: mangle
              [573] = { accent = "6FE08A", sound = 569708 } } }, -- Restoration: nature
}
ns.THEME_FALLBACK = "SHAMAN"
