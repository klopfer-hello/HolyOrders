-- HolyOrders — group/raid roster scanning
-- Builds a flat unit list (players and pets, with owner mapping, subgroups
-- and MAINTANK roles), rebuilt debounced on roster events.

local HO = HolyOrders
local Roster = {}
HO.Roster = Roster

local REBUILD_DELAY = 0.5 -- seconds; coalesces event bursts

Roster.units = {} -- array of entries (players first, then pets)
Roster.byName = {} -- [fullName] = entry
local listeners = {}

function Roster.OnChanged(fn)
	table.insert(listeners, fn)
end

local function Notify()
	for _, fn in ipairs(listeners) do
		fn()
	end
end

local function AddEntry(unit, ownerEntry)
	if not UnitExists(unit) then
		return nil
	end
	local entry = {
		unit = unit,
		name = HO.FullName(unit),
		class = (select(2, UnitClass(unit))),
		level = UnitLevel(unit),
		online = UnitIsConnected(unit) and true or false,
		isPet = ownerEntry ~= nil,
		owner = ownerEntry and ownerEntry.name or nil,
		subgroup = ownerEntry and ownerEntry.subgroup or 1,
		tankRole = false,
	}
	if entry.name then
		table.insert(Roster.units, entry)
		if not entry.isPet then
			Roster.byName[entry.name] = entry
		end
	end
	return entry
end

function Roster.Rebuild()
	wipe(Roster.units)
	wipe(Roster.byName)

	local pets = {} -- { petUnit = ownerEntry } collected, appended after players

	if IsInRaid() then
		for i = 1, MAX_RAID_MEMBERS do
			local entry = AddEntry("raid" .. i)
			if entry then
				local _, _, subgroup, _, _, _, _, _, _, role = GetRaidRosterInfo(i)
				entry.subgroup = subgroup or 1
				entry.tankRole = (role == "MAINTANK")
				pets["raidpet" .. i] = entry
			end
		end
	else
		local playerEntry = AddEntry("player")
		if playerEntry then
			playerEntry.tankRole = GetPartyAssignment("MAINTANK", "player") and true or false
			pets["pet"] = playerEntry
		end
		for i = 1, MAX_PARTY_MEMBERS do
			local unit = "party" .. i
			local entry = AddEntry(unit)
			if entry then
				entry.tankRole = GetPartyAssignment("MAINTANK", unit) and true or false
				pets["partypet" .. i] = entry
			end
		end
	end

	for petUnit, ownerEntry in pairs(pets) do
		AddEntry(petUnit, ownerEntry)
	end

	Notify()
end

-- sorted realm-qualified names of all paladins (roster signature input)
function Roster.Paladins()
	local names = {}
	for _, entry in ipairs(Roster.units) do
		if not entry.isPet and entry.class == "PALADIN" and entry.name then
			table.insert(names, entry.name)
		end
	end
	table.sort(names)
	return names
end

-- debounced rebuild ----------------------------------------------------------

local rebuildPending = false

function Roster.Queue()
	if rebuildPending then
		return
	end
	rebuildPending = true
	C_Timer.After(REBUILD_DELAY, function()
		rebuildPending = false
		Roster.Rebuild()
	end)
end

HO.RegisterEvent("GROUP_ROSTER_UPDATE", Roster.Queue)
HO.RegisterEvent("UNIT_PET", Roster.Queue)
HO.RegisterEvent("PLAYER_ENTERING_WORLD", Roster.Queue)
