-- HolyOrders — cast engine (what do I cast next, per class duty?)
-- Pure computation: scans buffs on my assigned targets and picks the next
-- target and spell per class. No secure frames here; the bar consumes tasks.

local HO = HolyOrders
local Engine = {}
HO.Engine = Engine

local EXPIRING_SOON = 120 -- seconds left that count as "needs a refresh"
local MAX_BUFFS = 40
local SALVATION = 4
local FRESH_AGE = 120 -- force mode: buffs older than this are re-cast
local FORCE_DURATION = 300 -- force mode safety timeout

Engine.tasks = {} -- [classToken] = task table, built in Update()
Engine.forceUntil = nil

-- force-rebuff sweep: pre-pull refresh of everything that is not fresh;
-- ends automatically when all assigned buffs are fresh, or after timeout
function Engine.StartForceRebuff()
	Engine.forceUntil = GetTime() + FORCE_DURATION
	HO.Log("engine", "force rebuff started")
end

function Engine.StopForceRebuff()
	Engine.forceUntil = nil
	HO.Log("engine", "force rebuff stopped")
end

function Engine.ForceActive()
	if Engine.forceUntil then
		if GetTime() < Engine.forceUntil then
			return true
		end
		Engine.forceUntil = nil
	end
	return false
end

-- which blessing target `entry` should get from me: override wins, then the
-- class assignment
-- is this pet buffed at all, per the owner-class settings?
local function PetIncluded(entry)
	local petOpts = HO.db.options.pets or {}
	local ownerEntry = entry.owner and HO.Roster.byName[entry.owner]
	local ownerClass = ownerEntry and ownerEntry.class
	if ownerClass == "HUNTER" then
		return petOpts.hunter ~= false
	end
	if ownerClass == "WARLOCK" then
		return petOpts.warlock == true
	end
	return true
end

local function TargetBlessing(plan, me, entry)
	local overrides = plan.player[me]
	local override = overrides and entry.name and overrides[entry.name]
	if override then
		-- an override identical to the class assignment is redundant: treat
		-- the member as a class-wide target so greater blessings stay possible
		local assigns = plan.class[me]
		local assign = assigns and entry.class and assigns[entry.class]
		if assign and not entry.isPet and assign.id == override then
			return assign.id, false
		end
		return override, true
	end
	if entry.isPet then
		-- pets get the configured pet blessing, cast by whoever covers
		-- the pet's base class
		if not PetIncluded(entry) then
			return nil, false
		end
		local assigns = plan.class[me]
		if assigns and entry.class and assigns[entry.class] then
			local petOpts = HO.db.options.pets
			return (petOpts and petOpts.blessing) or 2, false
		end
		return nil, false
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
		local name, _, _, _, duration, expirationTime = UnitBuff(unit, i)
		if not name then
			break
		end
		if name == blessing.name or name == blessing.greaterName then
			if expirationTime and expirationTime > 0 then
				return true, expirationTime - GetTime(), duration
			end
			return true, nil, nil
		end
	end
	return false, nil, nil
end

local function Castable(entry)
	return entry.online and not UnitIsDeadOrGhost(entry.unit) and UnitIsVisible(entry.unit)
end

local function InCastRange(blessing, unit)
	local result = IsSpellInRange(blessing.name, unit)
	if result == nil then
		return true -- indeterminate: do not block the rotation
	end
	return result == 1
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
	-- auto: greater from N members; N=1 when the user prefers the 30-min
	-- duration over saving symbols
	return eligiblePlayers >= (HO.db.options.greaterMin or 2)
end

function Engine.Update()
	wipe(Engine.tasks)
	local plan = HO.Plan.Active()
	local me = HO.FullName("player")
	if not me then
		return
	end

	-- pool my targets by class; also note which classes contain tanks
	local pools = {} -- [classToken] = { {entry, blessingID, isOverride}, ... }
	local classTanks = {} -- [classToken] = true when a tank is present
	for _, entry in ipairs(HO.Roster.units) do
		if entry.name and entry.class and entry.unit then
			local isTank = HO.Plan.IsTank(entry.name, entry.tankRole)
			if isTank and not entry.isPet then
				classTanks[entry.class] = true
			end
			local blessingID, isOverride = TargetBlessing(plan, me, entry)
			if blessingID and blessingID > 0 then
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
		-- hard guard: never resolve to greater Salvation over a class that
		-- contains a tank (the greater hits the whole class) — unless the
		-- mode was explicitly forced to greater by the user
		if greater and assign and assign.id == SALVATION and classTanks[classToken] and assign.mode ~= "greater" then
			greater = false
		end

		local force = Engine.ForceActive()
		-- class-wide targets before override/pet singles: a greater cast
		-- replaces this paladin's own singles on the whole class ("one
		-- blessing per paladin"), so it must always happen first
		local missingClass, missingSingles, expiring, minRemaining = {}, {}, {}, nil
		local outOfRange = 0
		for _, item in ipairs(pool) do
			local has, remaining, duration = HasBlessing(item.entry.unit, item.blessingID)
			item.remaining = remaining
			local blessing = HO.Data.blessings[item.blessingID]
			item.inRange = blessing and InCastRange(blessing, item.entry.unit)
			if not has then
				if Castable(item.entry) then
					if not item.inRange then
						outOfRange = outOfRange + 1
					end
					if item.isOverride or item.entry.isPet then
						table.insert(missingSingles, item)
					else
						table.insert(missingClass, item)
					end
				end
			elseif remaining then
				if not minRemaining or remaining < minRemaining then
					minRemaining = remaining
				end
				local stale = force and duration and duration > 0 and (duration - remaining) > FRESH_AGE
				if (remaining < EXPIRING_SOON or stale) and Castable(item.entry) then
					table.insert(expiring, item)
				end
			end
		end
		table.sort(expiring, function(a, b)
			return (a.remaining or 0) < (b.remaining or 0)
		end)

		-- unreachable members never block the rotation; for greater casts a
		-- nearby anchor covers out-of-range class members anyway
		local function FirstInRange(list)
			for _, item in ipairs(list) do
				if item.inRange then
					return item
				end
			end
		end

		local missingCount = #missingClass + #missingSingles
		local nextItem = FirstInRange(missingClass) or FirstInRange(missingSingles) or FirstInRange(expiring)
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
				-- right-click alternative: always the 10-min single
				singleSpellName = blessing.name,
				unit = nextItem.entry.unit,
				unitName = nextItem.entry.name,
				missing = missingCount,
				expiring = #expiring,
				outOfRange = outOfRange,
				minRemaining = minRemaining,
				icon = blessing.icon,
			}
		else
			-- nothing castable right now (all covered, or the needy ones are
			-- out of range); passive display task keeps the counts honest
			local displayID = assign and assign.id or pool[1].blessingID
			local blessing = HO.Data.blessings[displayID]
			Engine.tasks[classToken] = {
				classToken = classToken,
				blessingID = displayID,
				spellName = nil,
				unit = nil,
				unitName = nil,
				missing = missingCount,
				expiring = #expiring,
				outOfRange = outOfRange,
				minRemaining = minRemaining,
				icon = blessing and blessing.icon,
			}
		end
	end

	-- force-rebuff sweep ends itself once every assigned buff is fresh
	if Engine.forceUntil and Engine.ForceActive() then
		local pending = false
		for _, task in pairs(Engine.tasks) do
			if task.missing > 0 or task.expiring > 0 then
				pending = true
				break
			end
		end
		if not pending then
			Engine.forceUntil = nil
			HO.Log("engine", "force rebuff complete")
			HO.Print(HO.L["force rebuff complete — all assigned buffs are fresh"])
		end
	end
end
