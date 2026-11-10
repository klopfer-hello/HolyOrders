-- Test-only fakes for APIs the simulator does not provide (spells, spellbook,
-- party assignments). Loaded before HolyOrders by the tests.
local SPELLS = {
	[19740] = "Blessing of Might", [25782] = "Greater Blessing of Might",
	[19742] = "Blessing of Wisdom", [25894] = "Greater Blessing of Wisdom",
	[20217] = "Blessing of Kings", [25898] = "Greater Blessing of Kings",
	[1038] = "Blessing of Salvation", [25895] = "Greater Blessing of Salvation",
	[19977] = "Blessing of Light", [25890] = "Greater Blessing of Light",
	[465] = "Devotion Aura", [7294] = "Retribution Aura", [25780] = "Righteous Fury",
}
-- spells a paladin knows in these tests
local BOOK = { 19740, 25782, 19742, 25894, 20217, 25898, 1038, 25895, 465, 7294, 25780 }

local function isPaladin()
	return select(2, UnitClass("player")) == "PALADIN"
end

Enum = Enum or {}
Enum.SpellBookSpellBank = Enum.SpellBookSpellBank or { Player = 0, Pet = 1 }

C_SpellBook = C_SpellBook or {}
function C_SpellBook.GetNumSpellBookSkillLines() return 1 end
function C_SpellBook.GetSpellBookSkillLineInfo()
	return { itemIndexOffset = 0, numSpellBookItems = isPaladin() and #BOOK or 0 }
end
function C_SpellBook.GetSpellBookItemName(slot)
	local id = BOOK[slot]
	if id then return SPELLS[id], "Rank 1" end
end

C_Spell = C_Spell or {}
function C_Spell.GetSpellInfo(id)
	local name = SPELLS[id]
	if name then return { name = name, iconID = 136000 + id % 1000, spellID = id } end
end
function C_Spell.GetSpellName(id) return SPELLS[id] end
function C_Spell.GetSpellTexture(id) return SPELLS[id] and 136000 end
function C_Spell.IsSpellInRange() return true end

function GetPartyAssignment() return false end
MAX_PARTY_MEMBERS = MAX_PARTY_MEMBERS or 4
SecureHandlerSetFrameRef = SecureHandlerSetFrameRef or function() end
UnitGroupRolesAssigned = UnitGroupRolesAssigned or function() return "NONE" end
C_Item = C_Item or {}
C_Item.GetItemCount = C_Item.GetItemCount or function() return 20 end -- reagents
C_UnitAuras = C_UnitAuras or {}
C_UnitAuras.GetBuffDataByIndex = C_UnitAuras.GetBuffDataByIndex or function() return nil end
