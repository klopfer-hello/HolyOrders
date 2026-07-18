-- HolyOrders — debug/utility slash commands

local HO = HolyOrders

HO.commands["spells"] = function()
	HO.Print("blessings:")
	for id, blessing in ipairs(HO.Data.blessings) do
		local normal
		if blessing.known then
			normal = (blessing.name or blessing.key) .. (blessing.rank and (" [" .. blessing.rank .. "]") or "")
		else
			normal = (blessing.name or blessing.key) .. " — NOT known"
		end
		local greater
		if blessing.greaterKnown then
			greater = "greater [" .. (blessing.greaterRank or "?") .. "]"
		else
			greater = "no greater"
		end
		local talent = HO.Talents.ranks[id]
		HO.PrintLine(string.format("%d. %s | %s | talent: %s", id, normal, greater, talent and tostring(talent) or "-"))
	end
	HO.Print("Symbol of Kings: " .. HO.Data.SymbolCount())
	HO.Print("talent distribution: " .. HO.Talents.SpecSummary())
end

HO.commands["roster"] = function()
	local units = HO.Roster.units
	if #units == 0 then
		HO.Print("roster is empty — scan pending or not grouped (try again in a second)")
		HO.Roster.Queue()
		return
	end
	HO.Print(string.format("roster: %d units, paladins: %s", #units, table.concat(HO.Roster.Paladins(), ", ")))
	for _, entry in ipairs(units) do
		local tags = {}
		if entry.isPet then
			table.insert(tags, "pet of " .. (entry.owner or "?"))
		end
		if entry.tankRole then
			table.insert(tags, "MAINTANK")
		end
		if not entry.online then
			table.insert(tags, "offline")
		end
		HO.PrintLine(string.format(
			"[%s] %s (L%s) g%s%s",
			entry.class or "?",
			entry.name or "?",
			tostring(entry.level or "?"),
			tostring(entry.subgroup or "?"),
			#tags > 0 and (" — " .. table.concat(tags, ", ")) or ""
		))
	end
end
