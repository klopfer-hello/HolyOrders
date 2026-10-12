-- luacheck config (run: scripts/lint.ps1, or `luacheck .` in the repo root)
std = "lua51"
max_line_length = false
codes = true
exclude_files = { "Libs/", "dist/", ".git/" }

ignore = {
	"212",   -- unused arguments: event/comm callbacks keep their full signature
}

-- Globals this addon defines or writes into.
globals = {
	"HolyOrders", "HolyOrdersDB",
	"SLASH_HOLYORDERS1", "SLASH_HOLYORDERS2",
	"SlashCmdList", "StaticPopupDialogs", "UISpecialFrames",
}

-- WoW API used by the addon (TBC Anniversary 2.5.6 and WoW Forever 1.60.1).
-- Legacy names (GetSpellInfo, UnitBuff, GetTalentInfo, ...) must only be reached
-- through Compat.lua. An unknown global is usually a typo or a missing API.
read_globals = {
	-- namespaces and libraries
	"C_ChatInfo", "C_ClassTalents", "C_EventUtils", "C_Item", "C_Secrets",
	"C_SpecializationInfo", "C_Spell", "C_SpellBook", "C_Timer", "C_Traits", "C_UnitAuras",
	"Enum", "LibStub", "Settings",
	-- functions
	"AutoCompleteEditBox_OnEnterPressed", "AutoCompleteEditBox_OnTabPressed", "CanInspect",
	"CheckInteractDistance", "ClearInspectPlayer", "CreateFont", "CreateFrame", "date",
	"GetAutoCompleteResults", "GetCVarBool", "GetCursorPosition", "GetItemCount", "GetLocale",
	"GetMinimapShape", "GetNormalizedRealmName", "GetNumSpellTabs", "GetNumTalentTabs",
	"GetNumTalents", "GetPartyAssignment", "GetRaidRosterInfo", "GetSpellBookItemName",
	"GetSpellInfo", "GetSpellTabInfo", "GetTalentInfo", "GetTime", "InCombatLockdown",
	"InterfaceOptionsFrame_OpenToCategory", "IsControlKeyDown", "IsInGroup", "IsInRaid",
	"IsShiftKeyDown", "IsSpellInRange", "issecretvalue", "NotifyInspect", "ReloadUI",
	"SecureHandlerSetFrameRef", "SendChatMessage", "StaticPopup_Show", "strsplit", "time",
	"UnitBuff", "UnitClass", "UnitExists", "UnitGroupRolesAssigned", "UnitGUID",
	"UnitIsConnected", "UnitIsDeadOrGhost", "UnitIsGroupLeader", "UnitIsVisible", "UnitLevel",
	"UnitName", "UnitPowerType", "wipe",
	-- frames, tables and strings
	"AUTOCOMPLETE_LIST", "BOOKTYPE_SPELL", "CLASS_ICON_TCOORDS", "DEFAULT_CHAT_FRAME",
	"GameTooltip", "InspectFrame", "MAX_PARTY_MEMBERS", "MAX_RAID_MEMBERS", "RAID_CLASS_COLORS",
	"UIParent", "UNKNOWNOBJECT",
}
