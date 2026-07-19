-- HolyOrders — cast engine (what do I cast next, per class duty?)
-- Pure computation: scans buffs on my assigned targets and picks the next
-- target and spell per class. No secure frames here; the bar consumes tasks.

local HO = HolyOrders
local Engine = {}
HO.Engine = Engine

local EXPIRING_SOON = 120 -- seconds left that count as "needs a refresh"
local MAX_BUFFS = 40

Engine.tasks = {} -- [classToken] = task table, built in Update()

-- which blessing target `entry` should get from me: override wins, then the
-- class assignment
local function TargetBlessing(plan, me, entry)
	local overrides = plan.player[me]
	local override = overrides and entry.name and overrides[entry.name]
	if override then
		return override, true
	end
	local assigns = plan.class[me]
	local assign = assigns and entry.class and assigns[entry.class]
	if assign then
		return assign.id, false
	end
	return nil, false
end

local function HasBlessing(unit, blessingID)
	local blessing = HO.Data.blessings[blessingID]
	if not blessing then
		return false, nil
	end
	for i = 1, MAX_BUFFS do
		local name, _, _, _, _, expirationTime = UnitBuff(unit, i)
		if not name then
			break
		end
		if name == blessing.name or name == blessing.greaterName then
			if expirationTime and expirationTime > 0 then
				return true, expirationTime - GetTime()
			end
			return true, nil
		end
	end
	return false, nil
end

local function Castable(entry)
	return entry.online and not UnitIsDeadOrGhost(entry.unit) and UnitIsVisible(entry.unit)
end

local function UseGreater(assign, eligiblePlayers)
	local blessing = HO.Data.blessings[assign.id]
	if not blessing or not blessing.greaterKnown then
		return false
	end
	if assign.mode == "greater" then
		return true
	end
	if assign.mode == "normal" then
		return false
	end
	return eligiblePlayers >= 2 -- auto: singles for small groups
end

function Engine.Update()
	wipe(Engine.tasks)
	local plan = HO.Plan.Active()
	local me = HO.FullName("player")
	if not me then
		return
	end

	-- pool my targets by class
	local pools = {} -- [classToken] = { {entry, blessingID, isOverride}, ... }
	for _, entry in ipairs(HO.Roster.units) do
		if entry.name and entry.class and entry.unit then
			local blessingID, isOverride = TargetBlessing(plan, me, entry)
			if blessingID and blessingID > 0 then
				local isTank = (plan.tanks[entry.name] or entry.tankRole) and true or false
				-- overrides are explicit; class-wide targets pass eligibility
				if isOverride or HO.Data.IsEligible(entry.class, blessingID, isTank) then
					pools[entry.class] = pools[entry.class] or {}
					table.insert(pools[entry.class], { entry = entry, blessingID = blessingID, isOverride = isOverride })
				end
			end
		end
	end

	for classToken, pool in pairs(pools) do
		local assign = plan.class[me] and plan.class[me][classToken]
		local eligiblePlayers = 0
		for _, item in ipairs(pool) do
			if not item.isOverride and not item.entry.isPet then
				eligiblePlayers = eligiblePlayers + 1
			end
		end
		local greater = assign and UseGreater(assign, eligiblePlayers) or false

		local missing, expiring, minRemaining = {}, {}, nil
		for _, item in ipairs(pool) do
			local has, remaining = HasBlessing(item.entry.unit, item.blessingID)
			item.remaining = remaining
			if not has then
				if Castable(item.entry) then
					table.insert(missing, item)
				end
			elseif remaining then
				if not minRemaining or remaining < minRemaining then
					minRemaining = remaining
				end
				if remaining < EXPIRING_SOON and Castable(item.entry) then
					table.insert(expiring, item)
				end
			end
		end
		table.sort(expiring, function(a, b)
			return (a.remaining or 0) < (b.remaining or 0)
		end)

		local nextItem = missing[1] or expiring[1]
		if nextItem then
			local blessing = HO.Data.blessings[nextItem.blessingID]
			-- greater only for class-wide targets of the class blessing; pets
			-- and overrides always get singles
			local castGreater = greater and not nextItem.isOverride and not nextItem.entry.isPet
				and assign and nextItem.blessingID == assign.id
			Engine.tasks[classToken] = {
				classToken = classToken,
				blessingID = nextItem.blessingID,
				spellName = castGreater and blessing.greaterName or blessing.name,
				unit = nextItem.entry.unit,
				unitName = nextItem.entry.name,
				missing = #missing,
				expiring = #expiring,
				minRemaining = minRemaining,
				icon = blessing.icon,
			}
		else
			-- nothing castable right now; passive display task
			local displayID = assign and assign.id or pool[1].blessingID
			local blessing = HO.Data.blessings[displayID]
			Engine.tasks[classToken] = {
				classToken = classToken,
				blessingID = displayID,
				spellName = nil,
				unit = nil,
				unitName = nil,
				missing = 0,
				expiring = 0,
				minRemaining = minRemaining,
				icon = blessing and blessing.icon,
			}
		end
	end
end
