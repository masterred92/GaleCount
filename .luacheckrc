std = "lua51"
max_line_length = false
exclude_files = { "tests/**", "tools/**", ".release/**", ".lua/**", ".luarocks/**", "wow-ui/**", "index/**", "hosts/**" }
-- Our own globals.
globals = { "KennyGaleCount", "KennyGaleCountDB", "SLASH_KENNYGALECOUNT1", "SLASH_KENNYGALECOUNT2", "SLASH_KENNYGALECOUNT3", "SlashCmdList" }
-- WoW API (checked against Blizzard's UI source by tools/verify_api.py).
read_globals = { "AbbreviateNumbers", "C_ClassTalents", "C_DamageMeter", "C_Spell", "C_Timer", "C_Traits", "PlaySoundFile",
  "UnitClass", "UnitGUID",
  -- used by the shared KennyShared library (Libs/KennyShared)
  "C_AddOns", "C_AuctionHouse", "C_Container", "C_Item", "C_RestrictedActions", "CreateFrame", "Enum", "GameTooltip", "GetBuildInfo", "GetLocale", "GetMoney", "GetMoneyString", "GetRealZoneText", "GetRealmName", "GetSubZoneText", "GetTime", "ItemRefTooltip", "LibStub", "NUM_BAG_SLOTS", "NUM_TOTAL_EQUIPPED_BAG_SLOTS", "TooltipDataProcessor", "UIParent", "UnitAffectingCombat", "UnitFactionGroup", "date", "issecretvalue", "time" }
