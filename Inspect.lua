-- HolyOrders — inspect-based spec inference
-- Fills EMPTY spec tags only (manual tags always win). Queued, throttled,
-- range-checked, out of combat only; best effort by design.

local HO = HolyOrders
local Inspect = {}
HO.Inspect = Inspect

-- talent tab -> spec tag (only classes with spec-dependent preferences)
local TAB_SPECS = {
	SHAMAN = { "elemental", "enhancement", "restoration" },
	DRUID = { "balance", "feral", "restoration" },
	PALADIN = { "holy", "protection", "retribution" },
	WARRIOR = { nil, nil, "protection" },
}
local RETRY_AFTER = 600 -- seconds before re-trying a member
local TIMEOUT = 5
local MIN_POINTS = 5 -- below this the spec is too ambiguous to infer

local queue, queued, attempts = {}, {}, {}
local current

local function Enqueue()
	for _, entry in ipairs(HO.Roster.units) do
		local name = entry.name
		if name and not entry.isPet and TAB_SPECS[entry.class]
			and not HO.db.specCache[name] and not queued[name]
			and name ~= HO.FullName("player")
			and (not attempts[name] or (GetTime() - attempts[name]) > RETRY_AFTER) then
			queued[name] = true
			table.insert(queue, name)
		end
	end
end

local function Pump()
	if current or InCombatLockdown() then
		return
	end
	while #queue > 0 do
		local name = table.remove(queue, 1)
		queued[name] = nil
		local entry = HO.Roster.byName[name]
		local unit = entry and entry.unit
		if unit and UnitIsConnected(unit) and CheckInteractDistance(unit, 1) and CanInspect(unit) then
			attempts[name] = GetTime()
			current = { name = name, unit = unit, class = entry.class }
			current.timeoutTimer = C_Timer.NewTimer(TIMEOUT, function()
				current = nil
			end)
			NotifyInspect(unit)
			return
		end
	end
end

HO.RegisterEvent("INSPECT_READY", function(guid)
	if not current or UnitGUID(current.unit) ~= guid then
		return
	end
	local best, bestPoints = nil, 0
	for tab = 1, GetNumTalentTabs(true) do
		local points = 0
		for index = 1, GetNumTalents(tab, true) do
			local _, _, _, _, rank = GetTalentInfo(tab, index, true)
			points = points + (rank or 0)
		end
		if points > bestPoints then
			best, bestPoints = tab, points
		end
	end
	local spec = best and TAB_SPECS[current.class] and TAB_SPECS[current.class][best]
	if spec and bestPoints >= MIN_POINTS and not HO.db.specCache[current.name] then
		HO.db.specCache[current.name] = spec
		HO.Log("inspect", current.name .. " inferred as " .. spec .. " (" .. bestPoints .. "p)")
	end
	ClearInspectPlayer()
	if current.timeoutTimer then
		current.timeoutTimer:Cancel()
	end
	current = nil
end)

HO.RegisterEvent("PLAYER_LOGIN", function()
	HO.Roster.OnChanged(Enqueue)
	C_Timer.NewTicker(3, Pump)
end)
