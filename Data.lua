-- HolyOrders — blessing data
-- Only base spell IDs are stored (public game data); localized names, icons
-- and known ranks are resolved from the running client's spellbook, so the
-- addon is locale-safe and needs no per-rank tables.

local HO = HolyOrders
local Data = {}
HO.Data = Data

-- stable blessing IDs (used in SavedVariables and comm; never renumber)
Data.blessings = {
	[1] = { key = "WISDOM", normal = 19742, greater = 25894 },
	[2] = { key = "MIGHT", normal = 19740, greater = 25782 },
	[3] = { key = "KINGS", normal = 20217, greater = 25898 },
	[4] = { key = "SALVATION", normal = 1038, greater = 25895 },
	[5] = { key = "LIGHT", normal = 19977, greater = 25890 },
	[6] = { key = "SANCTUARY", normal = 20911, greater = 25899 },
}
Data.NUM_BLESSINGS = #Data.blessings

Data.SYMBOL_OF_KINGS = 21177 -- reagent for greater blessings

-- eligibility (SPEC-planner §2); manual per-member overrides may bypass this
local NO_WISDOM = { WARRIOR = true, ROGUE = true }
local NO_MIGHT = { MAGE = true, WARLOCK = true, PRIEST = true }

function Data.IsEligible(classToken, blessingID, isTank)
	local blessing = Data.blessings[blessingID]
	if not blessing then
		return false
	end
	if blessing.key == "WISDOM" and NO_WISDOM[classToken] then
		return false
	end
	if blessing.key == "MIGHT" and NO_MIGHT[classToken] then
		return false
	end
	if blessing.key == "SALVATION" and isTank then
		return false
	end
	return true
end

-- spellbook resolution -------------------------------------------------------

-- highest known entry per spell name (later book slots hold higher ranks)
local function ScanSpellbook()
	local known = {}
	for tab = 1, GetNumSpellTabs() do
		local _, _, offset, numSlots = GetSpellTabInfo(tab)
		for slot = offset + 1, offset + numSlots do
			local name, rank = GetSpellBookItemName(slot, BOOKTYPE_SPELL)
			if name then
				known[name] = { rank = rank, slot = slot }
			end
		end
	end
	return known
end

function Data.Refresh()
	local book = ScanSpellbook()
	for _, blessing in ipairs(Data.blessings) do
		local nName, _, nIcon = GetSpellInfo(blessing.normal)
		local gName, _, gIcon = GetSpellInfo(blessing.greater)
		blessing.name, blessing.icon = nName, nIcon
		blessing.greaterName, blessing.greaterIcon = gName, gIcon
		local nEntry = nName and book[nName]
		local gEntry = gName and book[gName]
		blessing.known = nEntry ~= nil
		blessing.rank = nEntry and nEntry.rank or nil
		blessing.greaterKnown = gEntry ~= nil
		blessing.greaterRank = gEntry and gEntry.rank or nil
	end
end

function Data.SymbolCount()
	return GetItemCount(Data.SYMBOL_OF_KINGS) or 0
end

HO.RegisterEvent("SPELLS_CHANGED", function()
	Data.Refresh()
end)
