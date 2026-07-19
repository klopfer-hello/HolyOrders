-- HolyOrders — deterministic auto-planner
-- Same roster + same tags + same talents → the same plan, every time.
-- Coverage model: each paladin is assigned one blessing to cover across all
-- eligible classes; per-member preference deviations and tank protection are
-- expressed as player overrides (cast as 10-min singles).

local HO = HolyOrders
local Planner = {}
HO.Planner = Planner

local WISDOM, MIGHT, KINGS, SALVATION, LIGHT, SANCTUARY = 1, 2, 3, 4, 5, 6

-- raid blessing coverage priority by paladin count position (parties use
-- per-class preference lists instead)
local RAID_COVERAGE = { KINGS, SALVATION, MIGHT, WISDOM, LIGHT, SANCTUARY }

-- shipped class/spec preference defaults; user copies in HO.db.prefs win
local DEFAULT_PREFS = {
	WARRIOR = { default = { KINGS, MIGHT, SALVATION }, protection = { KINGS } },
	ROGUE = { default = { MIGHT, SALVATION, KINGS } },
	PRIEST = { default = { WISDOM, SALVATION, KINGS } },
	MAGE = { default = { WISDOM, SALVATION, KINGS } },
	WARLOCK = { default = { WISDOM, SALVATION, KINGS } },
	HUNTER = { default = { MIGHT, SALVATION, KINGS, WISDOM } },
	SHAMAN = { default = { WISDOM, SALVATION, KINGS }, enhancement = { MIGHT, SALVATION, KINGS }, elemental = { WISDOM, SALVATION, KINGS }, restoration = { WISDOM, SALVATION, KINGS } },
	DRUID = { default = { WISDOM, SALVATION, KINGS }, feral = { MIGHT, SALVATION, KINGS }, balance = { WISDOM, SALVATION, KINGS }, restoration = { WISDOM, SALVATION, KINGS } },
	PALADIN = { default = { KINGS, WISDOM }, holy = { WISDOM, KINGS }, protection = { KINGS }, retribution = { MIGHT, KINGS, SALVATION } },
}
Planner.DEFAULT_PREFS = DEFAULT_PREFS

function Planner.ValidSpecs(classToken)
	local prefs = DEFAULT_PREFS[classToken]
	local specs = {}
	if prefs then
		for key in pairs(prefs) do
			if key ~= "default" then
				table.insert(specs, key)
			end
		end
		table.sort(specs)
	end
	return specs
end

-- preference chain (SPEC-planner §6b) minus the manual-override level, which
-- the planner respects separately
function Planner.ResolvePreference(name, classToken, isTank)
	if isTank then
		return { KINGS }
	end
	local prefs = HO.db.prefs[classToken] or DEFAULT_PREFS[classToken]
	if not prefs then
		return { KINGS }
	end
	local spec = HO.db.specCache[name]
	return (spec and prefs[spec]) or prefs.default or { KINGS }
end

-- capabilities ----------------------------------------------------------------

local function Available(pallyName, blessingID)
	if pallyName == HO.FullName("player") then
		local blessing = HO.Data.blessings[blessingID]
		return (blessing and blessing.known) or false
	end
	-- peers broadcast their capabilities via HELLO
	local peer = HO.Comm and HO.Comm.peers[pallyName]
	if peer and peer.caps and peer.caps[blessingID] then
		return peer.caps[blessingID].known
	end
	-- no HolyOrders on that paladin: assume everything but talent-gated Sanctuary
	return blessingID ~= SANCTUARY
end
Planner.IsAvailable = Available

-- buff strength: improvement talents dominate (a maxed talent beats one
-- spell rank), then spell rank, then greater-version knowledge as tiebreak
local function Score(pallyName, blessingID)
	local talent, rank, greater = 0, 0, false
	if pallyName == HO.FullName("player") then
		talent = HO.Talents.ranks[blessingID] or 0
		local blessing = HO.Data.blessings[blessingID]
		rank = (blessing and blessing.rankNum) or 0
		greater = (blessing and blessing.greaterKnown) or false
	else
		local peer = HO.Comm and HO.Comm.peers[pallyName]
		local caps = peer and peer.caps and peer.caps[blessingID]
		if caps then
			talent = caps.talent or 0
			rank = caps.rank or 0
			greater = caps.greater or false
		end
	end
	return talent * 12 + rank * 10 + (greater and 1 or 0)
end

-- substitute for a Salvation class assignment while no-Salvation mode is on:
-- class preference first, then Light/Kings/Wisdom/Might, skipping blessings
-- the class already receives from another paladin
function Planner.SalvSubstitute(pally, classToken, plan)
	local received = {}
	for otherPally, rows in pairs(plan.class) do
		if otherPally ~= pally then
			local a = rows[classToken]
			if a then
				received[a.id] = true
			end
		end
	end
	local prefs = HO.db.prefs[classToken] or DEFAULT_PREFS[classToken]
	local candidates = {}
	if prefs and prefs.default then
		for _, id in ipairs(prefs.default) do
			table.insert(candidates, id)
		end
	end
	table.insert(candidates, LIGHT)
	table.insert(candidates, KINGS)
	table.insert(candidates, WISDOM)
	table.insert(candidates, MIGHT)
	for _, id in ipairs(candidates) do
		if id ~= SALVATION and not received[id]
			and HO.Data.IsEligible(classToken, id, false) and Available(pally, id) then
			return id
		end
	end
	return nil
end

-- helpers ---------------------------------------------------------------------

local function IsTankEntry(plan, entry)
	return HO.Plan.IsTank(entry.name, entry.tankRole)
end

local function HasOverrideFor(plan, target)
	for _, targets in pairs(plan.player) do
		if targets[target] then
			return true
		end
	end
	return false
end

-- planner-generated overrides are tracked so a re-run can replace them while
-- manual overrides are never touched
local function ClearAutoOverrides(plan)
	if not plan.autoPlayer then
		return
	end
	for pally, targets in pairs(plan.autoPlayer) do
		for target in pairs(targets) do
			if plan.player[pally] then
				plan.player[pally][target] = nil
			end
		end
	end
	plan.autoPlayer = nil
end

local function AddAutoOverride(plan, pally, target, blessingID)
	HO.Plan.SetPlayerOverride(pally, target, blessingID)
	plan.autoPlayer = plan.autoPlayer or {}
	plan.autoPlayer[pally] = plan.autoPlayer[pally] or {}
	plan.autoPlayer[pally][target] = true
end

-- main -------------------------------------------------------------------------

local function RunCore(pallys)
	local plan = HO.Plan.Active()
	local units = HO.Roster.units
	local isRaid = IsInRaid()
	local solo = (#pallys == 1)

	ClearAutoOverrides(plan)
	wipe(plan.class)

	-- class composition (players only; pets are cast-engine targets)
	local classes = {} -- [classToken] = { members, tanks, list }
	for _, entry in ipairs(units) do
		if not entry.isPet and entry.class and entry.name then
			local info = classes[entry.class]
			if not info then
				info = { members = 0, tanks = 0, list = {} }
				classes[entry.class] = info
			end
			info.members = info.members + 1
			table.insert(info.list, entry)
			if IsTankEntry(plan, entry) then
				info.tanks = info.tanks + 1
			end
		end
	end

	-- 1) blessing coverage: one blessing per paladin, deterministic
	local assigned = {} -- [pallyName] = blessingID
	if solo and isRaid then
		assigned[pallys[1]] = SALVATION -- solo raid mode: Salvation except tanks
	elseif solo then
		-- solo party: one class assignment per class (majority preference of
		-- its members; game rule allows different blessings per target), with
		-- overrides only for members who deviate (added in step 4)
		for classToken, info in pairs(classes) do
			local counts = {}
			for _, entry in ipairs(info.list) do
				local pref = Planner.ResolvePreference(entry.name, classToken, IsTankEntry(plan, entry))[1]
				if pref and Available(pallys[1], pref) and HO.Data.IsEligible(classToken, pref, false) then
					counts[pref] = (counts[pref] or 0) + 1
				end
			end
			local best, bestCount
			for id, count in pairs(counts) do
				if not bestCount or count > bestCount or (count == bestCount and id < best) then
					best, bestCount = id, count
				end
			end
			if best then
				HO.Plan.SetClassAssignment(pallys[1], classToken, best, "auto")
			end
		end
	elseif isRaid then
		local used = {}
		for i = 1, math.min(#pallys, #RAID_COVERAGE) do
			local blessing = RAID_COVERAGE[i]
			local best, bestScore
			for _, pally in ipairs(pallys) do -- sorted; strict > keeps ties alphabetical
				if not used[pally] and Available(pally, blessing) then
					local score = Score(pally, blessing)
					if not bestScore or score > bestScore then
						best, bestScore = pally, score
					end
				end
			end
			if best then
				used[best] = true
				assigned[best] = blessing
			end
		end
	else
		-- multi-paladin party: singles economics — each class gets its top
		-- preferences, one per paladin (different blessings per class are
		-- fine; one-blessing-per-paladin is a per-target rule)
		for classToken in pairs(classes) do
			local prefs = HO.db.prefs[classToken] or DEFAULT_PREFS[classToken]
			local list = (prefs and prefs.default) or {}
			local usedPally = {}
			local slots = 0
			local info = classes[classToken]
			for _, blessingID in ipairs(list) do
				if slots >= #pallys then
					break
				end
				-- same tank rules as the raid branch: skip Salvation for
				-- all-tank classes, singles when a tank is present
				local mode = "auto"
				local skip = false
				if blessingID == SALVATION and info.tanks > 0 then
					if info.tanks >= info.members then
						skip = true
					else
						mode = "normal"
					end
				end
				if not skip and HO.Data.IsEligible(classToken, blessingID, false) then
					local best, bestScore
					for _, pally in ipairs(pallys) do
						if not usedPally[pally] and Available(pally, blessingID) then
							local score = Score(pally, blessingID)
							if not bestScore or score > bestScore then
								best, bestScore = pally, score
							end
						end
					end
					if best then
						usedPally[best] = true
						slots = slots + 1
						HO.Plan.SetClassAssignment(best, classToken, blessingID, mode)
					end
				end
			end
		end
	end

	-- 2) class assignments from the coverage
	for classToken, info in pairs(classes) do
		for pally, blessing in pairs(assigned) do
			if HO.Data.IsEligible(classToken, blessing, false) then
				local mode = "auto"
				if blessing == SALVATION and info.tanks > 0 then
					if info.tanks >= info.members then
						blessing = KINGS -- class consists only of tanks
					else
						mode = "normal" -- singles; the cast engine skips tanks
					end
				end
				HO.Plan.SetClassAssignment(pally, classToken, blessing, mode)
			end
		end
	end

	-- which blessings actually reach each class (from ALL paladins' rows)
	local receivedByClass = {}
	for _, pally in ipairs(pallys) do
		local rows = plan.class[pally]
		if rows then
			for classToken, a in pairs(rows) do
				receivedByClass[classToken] = receivedByClass[classToken] or {}
				receivedByClass[classToken][a.id] = true
			end
		end
	end
	local function ClassReceives(classToken, blessingID)
		return receivedByClass[classToken] and receivedByClass[classToken][blessingID] or false
	end

	-- spread auto-overrides across paladins (round-robin) so no single row
	-- grows past the addon-message size cap; deterministic via sorted pally order
	local rrCursor = 0
	local function NextCaster(blessingID, classToken)
		-- first pass: prefer a caster who has NO class-row on the target's own
		-- class that could go greater — a greater re-cast on that class would
		-- wipe the single we are about to place ("normal" mode casts singles and
		-- is safe; auto/greater may cast the class-wide greater)
		for step = 1, #pallys do
			local idx = ((rrCursor + step - 1) % #pallys) + 1
			local pally = pallys[idx]
			if Available(pally, blessingID) then
				local rows = plan.class[pally]
				local a = classToken and rows and rows[classToken]
				if not (a and a.mode ~= "normal") then
					rrCursor = idx
					return pally
				end
			end
		end
		-- fallback: any available caster
		for step = 1, #pallys do
			local idx = ((rrCursor + step - 1) % #pallys) + 1
			if Available(pallys[idx], blessingID) then
				rrCursor = idx
				return pallys[idx]
			end
		end
	end

	-- iterate a name-sorted copy so the round-robin cursor advances in the same
	-- order on every client (party units are player/party1..4, whose order
	-- differs per client and would otherwise diverge the caster selection)
	local sortedUnits = {}
	for _, entry in ipairs(units) do
		sortedUnits[#sortedUnits + 1] = entry
	end
	table.sort(sortedUnits, function(a, b)
		return (a.name or "") < (b.name or "")
	end)

	-- 3) tanks: if no Kings reaches their class, give them Kings singles
	for _, entry in ipairs(sortedUnits) do
		if not entry.isPet and entry.name and IsTankEntry(plan, entry) then
			if not ClassReceives(entry.class, KINGS) and not HasOverrideFor(plan, entry.name) then
				local caster = NextCaster(KINGS, entry.class)
				if caster then
					AddAutoOverride(plan, caster, entry.name, KINGS)
				end
			end
		end
	end

	-- 4) per-member preference singles for what the coverage doesn't provide
	for _, entry in ipairs(sortedUnits) do
		if not entry.isPet and entry.name and not IsTankEntry(plan, entry) then
			local pref = Planner.ResolvePreference(entry.name, entry.class, false)[1]
			if pref and HO.Data.IsEligible(entry.class, pref, false) then
				local receives = ClassReceives(entry.class, pref)
				if solo and isRaid then
					receives = true -- the Salvation plan stays intact for non-tanks
				end
				if not receives and not HasOverrideFor(plan, entry.name) then
					local caster = NextCaster(pref, entry.class)
					if caster then
						AddAutoOverride(plan, caster, entry.name, pref)
					end
				end
			end
		end
	end

	-- drop overrides that merely duplicate the class assignment — they would
	-- force needless singles where a greater blessing covers the member
	for pally, targets in pairs(plan.player) do
		local rows = plan.class[pally]
		if rows then
			for target, id in pairs(targets) do
				local entry = HO.Roster.byName[target]
				local a = entry and not entry.isPet and rows[entry.class]
				if a and a.id == id then
					targets[target] = nil
					if plan.autoPlayer and plan.autoPlayer[pally] then
						plan.autoPlayer[pally][target] = nil
					end
				end
			end
		end
	end

	-- summary
	local overrideCount = 0
	if plan.autoPlayer then
		for _, targets in pairs(plan.autoPlayer) do
			for _ in pairs(targets) do
				overrideCount = overrideCount + 1
			end
		end
	end
	local parts = {}
	for _, pally in ipairs(pallys) do
		local blessing = assigned[pally]
		local label
		if blessing then
			label = HO.Data.blessings[blessing].name or HO.Data.blessings[blessing].key
		else
			local n = 0
			if plan.class[pally] then
				for _ in pairs(plan.class[pally]) do
					n = n + 1
				end
			end
			label = n > 0 and (n .. " class singles") or "nothing"
		end
		table.insert(parts, pally .. " > " .. label)
	end
	local summary = table.concat(parts, "; ")
	HO.Log("planner", string.format("run: raid=%s pallys=%d autoOverrides=%d | %s", tostring(isRaid), #pallys, overrideCount, summary))
	return summary
end

function Planner.Run()
	local pallys = HO.Roster.Paladins()
	if #pallys == 0 then
		return false, "no paladins in the roster"
	end
	-- bulk edit: individual SETs are suppressed while the plan is computed;
	-- the suspension is error-safe (a stuck flag would silently kill ALL
	-- outgoing sync), and the finished plan broadcasts atomically
	if HO.Comm then
		HO.Comm.suspended = true
	end
	local ok, summary = pcall(RunCore, pallys)
	if HO.Comm then
		HO.Comm.suspended = false
	end
	if not ok then
		HO.Log("error", "planner: " .. tostring(summary))
		return false, "internal error (logged)"
	end
	if HO.Comm then
		if HO.Comm.SendPlanApply() then
			HO.Print(HO.L["plan broadcast to the group"])
		elseif IsInGroup() then
			-- non-leads cannot broadcast the whole plan; their own row is
			-- still authoritative and syncs
			HO.Comm.BroadcastOwnRow()
			HO.Print(HO.L["plan is local — only your own assignments sync (lead/assist can broadcast all)"])
		end
	end
	return true, summary
end
