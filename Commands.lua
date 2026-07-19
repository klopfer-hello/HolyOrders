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
			local rank = (blessing.rank and blessing.rank ~= "") and (" [" .. blessing.rank .. "]") or ""
			normal = (blessing.name or blessing.key) .. rank
		else
			normal = (blessing.name or blessing.key) .. " — NOT known"
		end
		local greater
		if blessing.greaterKnown then
			local grank = (blessing.greaterRank and blessing.greaterRank ~= "") and (" [" .. blessing.greaterRank .. "]") or ""
			greater = "greater" .. grank
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
				HO.PrintLine(string.format("   %s > %s (%s)", classToken, BlessingLabel(a.id), a.mode))
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
		HO.Print(classToken .. " > " .. BlessingLabel(id))
	end
end

HO.commands["override"] = function(rest)
	local target, id = rest:match("^(%S+)%s+(%S+)$")
	id = tonumber(id)
	if not target or not id or not (id == 0 or HO.Data.blessings[id]) then
		HO.Print("usage: /ho override <playerName> <blessing 0-" .. HO.Data.NUM_BLESSINGS .. ">  (0 clears)")
		return
	end
	local entry
	target, entry = HO.Roster.Resolve(target)
	if not entry then
		HO.Print("target is not in the roster")
		return
	end
	HO.Plan.SetPlayerOverride(HO.FullName("player"), target, id)
	if id == 0 then
		HO.Print("override cleared for " .. target)
	else
		HO.Print("override: " .. BlessingLabel(id) .. " on " .. target)
	end
end

-- debugging -------------------------------------------------------------------

HO.commands["log"] = function(rest)
	if rest == "clear" then
		wipe(HO.db.log)
		HO.Print("debug log cleared")
		return
	end
	local n = tonumber(rest) or 15
	local log = HO.db.log
	HO.Print(string.format("debug log (%d entries, showing last %d):", #log, math.min(n, #log)))
	for i = math.max(1, #log - n + 1), #log do
		HO.PrintLine(log[i])
	end
end

-- full state snapshot into SavedVariables; visible after /reload or logout
HO.commands["dump"] = function()
	local dump = {
		at = date("%Y-%m-%d %H:%M:%S"),
		version = HO.VERSION,
		signature = HO.db.activeSignature,
		talentSummary = HO.Talents.SpecSummary(),
		talentRanks = {},
		blessings = {},
		roster = {},
	}
	for id, rank in pairs(HO.Talents.ranks) do
		dump.talentRanks[id] = rank
	end
	for id, blessing in ipairs(HO.Data.blessings) do
		dump.blessings[id] = string.format(
			"%s known=%s rank=%s greater=%s grank=%s",
			blessing.key,
			tostring(blessing.known), tostring(blessing.rank),
			tostring(blessing.greaterKnown), tostring(blessing.greaterRank)
		)
	end
	for _, entry in ipairs(HO.Roster.units) do
		table.insert(dump.roster, string.format(
			"%s class=%s level=%s group=%s%s%s%s",
			entry.name or "?", entry.class or "?",
			tostring(entry.level), tostring(entry.subgroup),
			entry.isPet and (" pet-of=" .. (entry.owner or "?")) or "",
			entry.tankRole and " MAINTANK" or "",
			entry.online and "" or " offline"
		))
	end
	HO.db.dump = dump
	HO.Log("dump", "state snapshot stored")
	HO.Print("state snapshot stored in SavedVariables — do /reload (or log out) so it is written to disk")
end

-- cast bar --------------------------------------------------------------------

HO.commands["bar"] = function(rest)
	local opts = HO.db.options.bar or {}
	HO.db.options.bar = opts
	local sub = rest:lower()
	if sub == "lock" then
		opts.locked = true
		HO.Print("bar locked")
	elseif sub == "unlock" then
		opts.locked = false
		HO.Print("bar unlocked — drag it by the golden handle")
	elseif sub == "show" then
		opts.hidden = false
		HO.Bar.Refresh()
		HO.Print("bar shown (appears when you have duties)")
	elseif sub == "hide" then
		opts.hidden = true
		HO.Bar.Refresh()
		HO.Print("bar hidden")
	elseif sub == "reset" then
		HO.Bar.ResetPosition()
		HO.Print("bar position reset")
	else
		HO.Print("usage: /ho bar lock|unlock|show|hide|reset")
	end
end

HO.commands["rebuff"] = function()
	HO.Bar.ToggleForceRebuff()
end

HO.commands["win"] = function()
	HO.Window.Toggle()
end

-- auto-planner ----------------------------------------------------------------

HO.commands["auto"] = function()
	local ok, msg = HO.Planner.Run()
	if ok then
		HO.Print("auto-plan: " .. msg)
		HO.Print("'/ho plan show' for details, '/ho plan save [label]' to keep it")
	else
		HO.Print("auto-plan failed: " .. msg)
	end
end

HO.commands["spec"] = function(rest)
	local target, spec = rest:match("^(%S+)%s*(%S*)$")
	if not target then
		HO.Print("usage: /ho spec <playerName> [<spec>|clear] — tags a member's spec for the planner")
		return
	end
	local entry
	target, entry = HO.Roster.Resolve(target)
	if not entry then
		HO.Print("target is not in the roster")
		return
	end
	local valid = HO.Planner.ValidSpecs(entry.class)
	spec = (spec or ""):lower()
	if spec == "" then
		HO.Print(target .. " spec: " .. (HO.db.specCache[target] or "not set")
			.. (#valid > 0 and (" — valid: " .. table.concat(valid, ", ")) or ""))
	elseif spec == "clear" then
		HO.db.specCache[target] = nil
		HO.Print(target .. " spec tag cleared")
	else
		local ok = false
		for _, s in ipairs(valid) do
			if s == spec then
				ok = true
			end
		end
		if not ok then
			HO.Print("invalid spec for " .. entry.class
				.. (#valid > 0 and (" — valid: " .. table.concat(valid, ", ")) or " (no spec rules for this class)"))
			return
		end
		HO.db.specCache[target] = spec
		HO.Print(target .. " tagged as " .. spec)
	end
end

HO.commands["tank"] = function(rest)
	local target = rest:match("^(%S+)$")
	if not target then
		HO.Print("usage: /ho tank <playerName>  (toggles the tank flag)")
		return
	end
	local entry
	target, entry = HO.Roster.Resolve(target)
	if not entry then
		HO.Print("target is not in the roster")
		return
	end
	local isTank = HO.Plan.ToggleTank(target)
	HO.Print(target .. (isTank and " is now flagged as tank" or " is no longer flagged as tank"))
end
