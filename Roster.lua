-- HolyOrders — group/raid roster scanning
-- Builds a flat unit list (players and pets, with owner mapping, subgroups
-- and MAINTANK roles), rebuilt debounced on roster events.

local HO = HolyOrders
local Roster = {}
HO.Roster = Roster

local REBUILD_DELAY = 0.5 -- seconds; coalesces event bursts
local RESCAN_DELAY = 2 -- seconds until a scan with missing data is repeated
local UNREADABLE_DELAY = 5 -- seconds until a scan the client refused is repeated

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

local needsRescan = false

-- the modern client hides unit data from addons in restricted situations
-- ("secret" values: usable for display only, any other use throws)
local function Unreadable(value)
	return issecretvalue ~= nil and value ~= nil and issecretvalue(value)
end

local function AddEntry(unit, ownerEntry)
	if not UnitExists(unit) then
		return nil
	end
	-- during zoning UnitExists can be true while the name is still the
	-- "Unknown" placeholder; such names must never reach plan signatures
	local rawName = UnitName(unit)
	local class = select(2, UnitClass(unit))
	if Unreadable(rawName) or Unreadable(class) then
		error("unit data is secret")
	end
	if not rawName or rawName == (UNKNOWNOBJECT or "Unknown") then
		needsRescan = true
		return nil
	end
	local entry = {
		unit = unit,
		name = HO.FullName(unit),
		class = class,
		level = UnitLevel(unit),
		online = UnitIsConnected(unit) and true or false,
		isPet = ownerEntry ~= nil,
		owner = ownerEntry and ownerEntry.name or nil,
		subgroup = ownerEntry and ownerEntry.subgroup or 1,
		tankRole = false,
	}
	-- a pet out of visibility range reports no class; it is kept (display and
	-- casting group it under its OWNER's class) and a rescan fills the class
	-- in once the pet is visible — dropping it here made pets vanish from the
	-- lists whenever the owner was far away during a rebuild
	if entry.isPet and not entry.class then
		needsRescan = true
	end
	if entry.name then
		table.insert(Roster.units, entry)
		if not entry.isPet then
			Roster.byName[entry.name] = entry
		end
	end
	return entry
end

-- the group-frame role marker (shield icon from the role check); distinct from
-- the raid-only MAINTANK assignment and available in plain parties, so it is the
-- way a 5-man tank is usually marked. Defensive: the API exists on 2.5.6, but
-- guard anyway per project rule.
local function HasTankRoleIcon(unit)
	return UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit) == "TANK" or false
end

local function Scan()
	local pets = {} -- { petUnit = ownerEntry } collected, appended after players

	if IsInRaid() then
		for i = 1, MAX_RAID_MEMBERS do
			local entry = AddEntry("raid" .. i)
			if entry then
				local _, rank, subgroup, _, _, _, _, _, _, role = GetRaidRosterInfo(i)
				entry.subgroup = subgroup or 1
				entry.rank = rank or 0 -- 2 = leader, 1 = assist
				entry.tankRole = (role == "MAINTANK") or HasTankRoleIcon("raid" .. i)
				pets["raidpet" .. i] = entry
			end
		end
	else
		local playerEntry = AddEntry("player")
		if playerEntry then
			playerEntry.rank = UnitIsGroupLeader("player") and 2 or 0
			playerEntry.tankRole = (GetPartyAssignment("MAINTANK", "player") and true or false) or HasTankRoleIcon("player")
			pets["pet"] = playerEntry
		end
		for i = 1, MAX_PARTY_MEMBERS do
			local unit = "party" .. i
			local entry = AddEntry(unit)
			if entry then
				entry.rank = UnitIsGroupLeader(unit) and 2 or 0
				entry.tankRole = (GetPartyAssignment("MAINTANK", unit) and true or false) or HasTankRoleIcon(unit)
				pets["partypet" .. i] = entry
			end
		end
	end

	-- pets are listed only where blessings can be cast on them
	if HO.Compat.PETS_BUFFABLE then
		for petUnit, ownerEntry in pairs(pets) do
			AddEntry(petUnit, ownerEntry)
		end
	end
end

local unreadableLogged = false

function Roster.Rebuild()
	-- scan into fresh tables: when the client will not let us read the units
	-- right now, the roster we have stays as it is (a half-built or emptied one
	-- would make every sync message look like it came from a stranger) and the
	-- scan is repeated later
	local oldUnits, oldByName = Roster.units, Roster.byName
	Roster.units, Roster.byName = {}, {}
	needsRescan = false
	local ok, err = pcall(Scan)
	if not ok then
		Roster.units, Roster.byName = oldUnits, oldByName
		if not unreadableLogged then
			unreadableLogged = true
			HO.Log("roster", "scan not possible right now, keeping the roster: " .. tostring(err))
		end
		C_Timer.After(UNREADABLE_DELAY, Roster.Queue)
		return
	end
	unreadableLogged = false

	HO.Log("roster", string.format("rebuild: %d units, paladins: %s", #Roster.units, table.concat(Roster.Paladins(), ";")))
	Notify()
	if needsRescan then
		needsRescan = false
		C_Timer.After(RESCAN_DELAY, Roster.Queue)
	end
end

-- case-insensitive lookup of what a user typed: the full name ("Name-Realm",
-- or first name and surname, with a dash or a space), or the first part alone
-- when exactly one member has it (first names are not unique where characters
-- have surnames). Returns fullName, entry.
function Roster.Resolve(input)
	if not input or input == "" then
		return nil
	end
	local needle = (input:lower():gsub("%s+", "-"))
	local found, foundEntry, ambiguous
	for name, entry in pairs(Roster.byName) do
		local lower = name:lower()
		if lower == needle then
			return name, entry
		end
		if lower:match("^([^%-]+)") == needle then
			ambiguous = found ~= nil
			found, foundEntry = name, entry
		end
	end
	if ambiguous then
		return nil
	end
	return found, foundEntry
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
-- role-check results (the tank/healer/damage markers) feed tank detection
HO.RegisterEvent("PLAYER_ROLES_ASSIGNED", Roster.Queue)
