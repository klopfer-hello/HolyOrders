-- HolyOrders — deterministic auto-planner
-- Same roster + same tags + same talents → the same plan, every time.
-- Coverage model: each paladin is assigned one blessing to cover across all
-- eligible classes; per-member preference deviations and tank protection are
-- expressed as player overrides (cast as 10-min singles).

local HO = HolyOrders
local Planner = {}
HO.Planner = Planner

local WISDOM, MIGHT, KINGS, SALVATION, LIGHT, SANCTUARY = 1, 2, 3, 4, 5, 6

-- blessing coverage priority by paladin count position
local RAID_COVERAGE = { KINGS, SALVATION, MIGHT, WISDOM, LIGHT, SANCTUARY }
local PARTY_COVERAGE = { KINGS, MIGHT, WISDOM, LIGHT, SANCTUARY, SALVATION }

-- shipped class/spec preference defaults; user copies in HO.db.prefs win
local DEFAULT_PREFS = {
	WARRIOR = { default = { KINGS, MIGHT }, protection = { KINGS } },
	ROGUE = { default = { MIGHT, KINGS } },
	PRIEST = { default = { WISDOM, KINGS } },
	MAGE = { default = { WISDOM, KINGS } },
	WARLOCK = { default = { WISDOM, KINGS } },
	HUNTER = { default = { MIGHT, KINGS, WISDOM } },
	SHAMAN = { default = { WISDOM, KINGS }, enhancement = { MIGHT, KINGS }, elemental = { WISDOM, KINGS }, restoration = { WISDOM, KINGS } },
	DRUID = { default = { WISDOM, KINGS }, feral = { MIGHT, KINGS }, balance = { WISDOM, KINGS }, restoration = { WISDOM, KINGS } },
	PALADIN = { default = { KINGS, WISDOM }, holy = { WISDOM, KINGS }, protection = { KINGS }, retribution = { MIGHT, KINGS } },
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
	-- remote capabilities arrive with the sync milestone; until then assume
	-- everything except talent-gated Sanctuary
	return blessingID ~= SANCTUARY
end

local function Score(pallyName, blessingID)
	if pallyName == HO.FullName("player") then
		return HO.Talents.ranks[blessingID] or 0
	end
	return 0
end

-- helpers ---------------------------------------------------------------------

local function IsTankEntry(plan, entry)
	return (entry.name and plan.tanks[entry.name]) or entry.tankRole or false
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

function Planner.Run()
	local pallys = HO.Roster.Paladins()
	if #pallys == 0 then
		return false, "no paladins in the roster"
	end
	local plan = HO.Plan.Active()
	local units = HO.Roster.units
	local isRaid = IsInRaid()
	local solo = (#pallys == 1)

	ClearAutoOverrides(plan)
	wipe(plan.class)

	-- class composition (players only; pets are cast-engine targets)
	local classes = {} -- [classToken] = { members, tanks }
	for _, entry in ipairs(units) do
		if not entry.isPet and entry.class and entry.name then
			local info = classes[entry.class]
			if not info then
				info = { members = 0, tanks = 0 }
				classes[entry.class] = info
			end
			info.members = info.members + 1
			if IsTankEntry(plan, entry) then
				info.tanks = info.tanks + 1
			end
		end
	end

	-- 1) blessing coverage: one blessing per paladin, deterministic
	local assigned = {} -- [pallyName] = blessingID
	if solo and isRaid then
		assigned[pallys[1]] = SALVATION -- solo raid mode: Salvation except tanks
	elseif not solo then
		local coverage = isRaid and RAID_COVERAGE or PARTY_COVERAGE
		local used = {}
		for i = 1, math.min(#pallys, #coverage) do
			local blessing = coverage[i]
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
	end
	-- solo party: no class-wide coverage; per-member singles below

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

	-- 3) tanks: if no greater Kings covers them, give them Kings singles
	local kingsCovered = false
	for _, blessing in pairs(assigned) do
		if blessing == KINGS then
			kingsCovered = true
		end
	end
	for _, entry in ipairs(units) do
		if not entry.isPet and entry.name and IsTankEntry(plan, entry) then
			if not kingsCovered and not HasOverrideFor(plan, entry.name) then
				for _, pally in ipairs(pallys) do
					if Available(pally, KINGS) then
						AddAutoOverride(plan, pally, entry.name, KINGS)
						break
					end
				end
			end
		end
	end

	-- 4) per-member preference singles for what the coverage doesn't provide
	for _, entry in ipairs(units) do
		if not entry.isPet and entry.name and not IsTankEntry(plan, entry) then
			local pref = Planner.ResolvePreference(entry.name, entry.class, false)[1]
			if pref and HO.Data.IsEligible(entry.class, pref, false) then
				local receives = false
				for _, blessing in pairs(assigned) do
					if blessing == pref then
						receives = true
						break
					end
				end
				if solo and isRaid then
					receives = true -- the Salvation plan stays intact for non-tanks
				end
				if not receives and not HasOverrideFor(plan, entry.name) then
					for _, pally in ipairs(pallys) do
						if Available(pally, pref) then
							AddAutoOverride(plan, pally, entry.name, pref)
							break
						end
					end
				end
			end
		end
	end

	-- summary
	local parts = {}
	for _, pally in ipairs(pallys) do
		local blessing = assigned[pally]
		local label = blessing and (HO.Data.blessings[blessing].name or HO.Data.blessings[blessing].key) or "singles only"
		table.insert(parts, pally .. " > " .. label)
	end
	return true, table.concat(parts, "; ")
end
