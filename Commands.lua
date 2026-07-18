-- HolyOrders — debug/utility slash commands

local HO = HolyOrders

local CLASS_TOKENS = {
	WARRIOR = true, ROGUE = true, PRIEST = true, MAGE = true, WARLOCK = true,
	HUNTER = true, SHAMAN = true, DRUID = true, PALADIN = true,
}

local function BlessingLabel(id)
	local blessing = HO.Data.blessings[id]
	return blessing and (blessing.name or blessing.key) or ("#" .. tostring(id))
end

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

-- plan management ------------------------------------------------------------

local storedList = {} -- last /ho plan list order, for delete by number

HO.commands["plan"] = function(rest)
	local sub, arg = rest:match("^(%S*)%s*(.*)$")
	sub = (sub or ""):lower()

	if sub == "show" then
		local plan = HO.Plan.Active()
		HO.Print("active plan — roster: " .. (HO.db.activeSignature or "?"))
		for paladin, classes in pairs(plan.class) do
			HO.PrintLine(paladin .. ":")
			for classToken, a in pairs(classes) do
				HO.PrintLine(string.format("   %s → %s (%s)", classToken, BlessingLabel(a.id), a.mode))
			end
		end
		for paladin, targets in pairs(plan.player) do
			for target, id in pairs(targets) do
				HO.PrintLine(string.format("   override: %s buffs %s on %s", paladin, BlessingLabel(id), target))
			end
		end
		local tanks = {}
		for name in pairs(plan.tanks) do
			table.insert(tanks, name)
		end
		if #tanks > 0 then
			table.sort(tanks)
			HO.PrintLine("tanks: " .. table.concat(tanks, ", "))
		end
	elseif sub == "save" then
		local sig = HO.Plan.Save(arg)
		if sig then
			HO.Print("plan saved for roster: " .. sig .. (arg ~= "" and (" ('" .. arg .. "')") or ""))
		else
			HO.Print("cannot save: no paladins in roster (scan pending?)")
		end
	elseif sub == "list" then
		wipe(storedList)
		for sig, plan in pairs(HO.db.plans) do
			table.insert(storedList, { sig = sig, plan = plan })
		end
		table.sort(storedList, function(a, b)
			return (a.plan.meta.lastUsed or 0) > (b.plan.meta.lastUsed or 0)
		end)
		HO.Print(#storedList .. " stored plan(s):")
		for i, item in ipairs(storedList) do
			HO.PrintLine(string.format("%d. %s%s", i, item.plan.meta.name and ("'" .. item.plan.meta.name .. "' — ") or "", item.sig))
		end
	elseif sub == "apply" then
		if HO.Plan.ApplySuggestion() then
			HO.Print("suggested plan applied")
		else
			HO.Print("no plan suggestion pending")
		end
	elseif sub == "delete" then
		local index = tonumber(arg)
		local item = index and storedList[index]
		if item and HO.db.plans[item.sig] then
			HO.db.plans[item.sig] = nil
			HO.Print("deleted plan " .. index .. " (" .. item.sig .. ")")
		else
			HO.Print("usage: /ho plan list, then /ho plan delete <number>")
		end
	else
		HO.Print("usage: /ho plan show | save [label] | list | apply | delete <number>")
	end
end

-- assignment editing (debug interface until the UI exists) --------------------

HO.commands["assign"] = function(rest)
	local classToken, id, mode = rest:match("^(%S+)%s+(%S+)%s*(%S*)$")
	classToken = classToken and classToken:upper()
	id = tonumber(id)
	if not classToken or not CLASS_TOKENS[classToken] or not id or not (id == 0 or HO.Data.blessings[id]) then
		HO.Print("usage: /ho assign <class> <blessing 0-" .. HO.Data.NUM_BLESSINGS .. "> [auto|greater|normal]")
		HO.Print("example: /ho assign WARRIOR 2  (0 clears)")
		return
	end
	local me = HO.FullName("player")
	HO.Plan.SetClassAssignment(me, classToken, id, mode ~= "" and mode:lower() or nil)
	if id == 0 then
		HO.Print("cleared " .. classToken)
	else
		HO.Print(classToken .. " → " .. BlessingLabel(id))
	end
end

HO.commands["override"] = function(rest)
	local target, id = rest:match("^(%S+)%s+(%S+)$")
	id = tonumber(id)
	if not target or not id or not (id == 0 or HO.Data.blessings[id]) then
		HO.Print("usage: /ho override <playerName> <blessing 0-" .. HO.Data.NUM_BLESSINGS .. ">  (0 clears)")
		return
	end
	local entry = HO.Roster.byName[target]
	if not entry then
		-- allow realm-less input by matching the name part
		for name, e in pairs(HO.Roster.byName) do
			if name:match("^([^%-]+)") == target then
				target, entry = name, e
				break
			end
		end
	end
	if not entry then
		HO.Print("'" .. target .. "' is not in the roster")
		return
	end
	HO.Plan.SetPlayerOverride(HO.FullName("player"), target, id)
	if id == 0 then
		HO.Print("override cleared for " .. target)
	else
		HO.Print("override: " .. BlessingLabel(id) .. " on " .. target)
	end
end

HO.commands["tank"] = function(rest)
	local target = rest:match("^(%S+)$")
	if not target then
		HO.Print("usage: /ho tank <playerName>  (toggles the tank flag)")
		return
	end
	for name in pairs(HO.Roster.byName) do
		if name == target or name:match("^([^%-]+)") == target then
			target = name
			break
		end
	end
	local isTank = HO.Plan.ToggleTank(target)
	HO.Print(target .. (isTank and " is now flagged as tank" or " is no longer flagged as tank"))
end
