-- HolyOrders — blessing plan model and per-roster persistence
-- The active plan is what gets edited and cast from; it persists across
-- reloads. Stored plans are keyed by the sorted paladin roster: an exact
-- roster match re-applies automatically, a similar roster is suggested.

local HO = HolyOrders
local Plan = {}
HO.Plan = Plan

Plan.MAX_STORED = 20 -- unnamed plans beyond this are pruned (oldest first)
Plan.SUGGEST_THRESHOLD = 0.5 -- min paladin-set overlap for a suggestion

local VALID_MODES = { auto = true, greater = true, normal = true }

local function NewPlan()
	return {
		version = 1,
		class = {}, -- [paladinName][classToken] = { id, mode }
		player = {}, -- [paladinName][targetName] = blessingID
		tanks = {}, -- [characterName] = true (roster-scoped, per spec)
		meta = { created = time() },
	}
end

local function Copy(value)
	if type(value) ~= "table" then
		return value
	end
	local t = {}
	for k, v in pairs(value) do
		t[k] = Copy(v)
	end
	return t
end

-- signatures -----------------------------------------------------------------

function Plan.Signature(paladins)
	return table.concat(paladins, ";")
end

function Plan.CurrentSignature()
	return Plan.Signature(HO.Roster.Paladins())
end

local function SetFromSignature(sig)
	local set = {}
	for name in string.gmatch(sig, "[^;]+") do
		set[name] = true
	end
	return set
end

local function Jaccard(setA, setB)
	local inter, union = 0, 0
	for k in pairs(setA) do
		union = union + 1
		if setB[k] then
			inter = inter + 1
		end
	end
	for k in pairs(setB) do
		if not setA[k] then
			union = union + 1
		end
	end
	if union == 0 then
		return 0
	end
	return inter / union
end

-- active plan ----------------------------------------------------------------

function Plan.Active()
	if not HO.db.activePlan then
		HO.db.activePlan = NewPlan()
	end
	return HO.db.activePlan
end

function Plan.SetClassAssignment(paladin, classToken, blessingID, mode)
	local plan = Plan.Active()
	plan.class[paladin] = plan.class[paladin] or {}
	if blessingID == 0 then
		plan.class[paladin][classToken] = nil
	else
		if not VALID_MODES[mode or "auto"] then
			mode = "auto"
		end
		plan.class[paladin][classToken] = { id = blessingID, mode = mode or "auto" }
	end
	if HO.Comm then
		HO.Comm.OnClassEdited(paladin, classToken)
	end
end

function Plan.SetPlayerOverride(paladin, targetName, blessingID)
	local plan = Plan.Active()
	plan.player[paladin] = plan.player[paladin] or {}
	if blessingID == 0 then
		plan.player[paladin][targetName] = nil
	else
		plan.player[paladin][targetName] = blessingID
	end
	if HO.Comm then
		HO.Comm.OnOverrideEdited(paladin, targetName)
	end
end

function Plan.ToggleTank(name)
	local plan = Plan.Active()
	local flagged
	if plan.tanks[name] then
		plan.tanks[name] = nil
		flagged = false
	else
		plan.tanks[name] = true
		flagged = true
	end
	if HO.Comm then
		HO.Comm.OnTankToggled(name, flagged)
	end
	return flagged
end

-- storage --------------------------------------------------------------------

local function CountStored()
	local n = 0
	for _ in pairs(HO.db.plans) do
		n = n + 1
	end
	return n
end

local function Prune()
	while CountStored() > Plan.MAX_STORED do
		local oldestSig, oldestTime
		for sig, plan in pairs(HO.db.plans) do
			if not plan.meta.name then -- named plans are never pruned
				local used = plan.meta.lastUsed or plan.meta.created or 0
				if not oldestTime or used < oldestTime then
					oldestSig, oldestTime = sig, used
				end
			end
		end
		if not oldestSig then
			return -- everything is named; accept exceeding the cap
		end
		HO.db.plans[oldestSig] = nil
	end
end

function Plan.Save(label)
	local sig = Plan.CurrentSignature()
	if sig == "" then
		return nil
	end
	local stored = Copy(Plan.Active())
	stored.meta.lastUsed = time()
	if label and label ~= "" then
		stored.meta.name = label
	end
	HO.db.plans[sig] = stored
	HO.db.activeSignature = sig
	Prune()
	HO.Log("plan", "saved plan for " .. sig .. (label and label ~= "" and (" as '" .. label .. "'") or ""))
	return sig
end

-- auto-apply / suggestion ----------------------------------------------------

Plan.suggestion = nil -- signature of the suggested stored plan, if any
local lastHandledSig

local function OnRosterChanged()
	if not HO.db then
		return
	end
	local sig = Plan.CurrentSignature()
	if sig == "" or sig == lastHandledSig then
		return
	end
	lastHandledSig = sig
	if sig == HO.db.activeSignature then
		return -- same roster as the active plan; nothing to do
	end
	local stored = HO.db.plans[sig]
	if stored then
		HO.db.activePlan = Copy(stored)
		HO.db.activeSignature = sig
		stored.meta.lastUsed = time()
		Plan.suggestion = nil
		HO.Log("plan", "auto-applied stored plan for " .. sig)
		HO.Print("stored plan applied for this paladin roster" .. (stored.meta.name and (" ('" .. stored.meta.name .. "')") or ""))
		-- a lead broadcasts the restored plan so the raid converges on it
		if HO.Comm and HO.Comm.SendPlanApply() then
			HO.Print("plan broadcast to the group")
		end
		return
	end
	-- no exact match: keep the current active plan, look for a similar one
	HO.db.activeSignature = sig
	local mySet = SetFromSignature(sig)
	local bestSig, bestScore
	for storedSig in pairs(HO.db.plans) do
		local score = Jaccard(mySet, SetFromSignature(storedSig))
		if score >= Plan.SUGGEST_THRESHOLD and (not bestScore or score > bestScore) then
			bestSig, bestScore = storedSig, score
		end
	end
	Plan.suggestion = bestSig
	if bestSig then
		local named = HO.db.plans[bestSig].meta.name
		HO.Print(string.format(
			"similar stored plan found (%d%% paladin overlap)%s — '/ho plan apply' to use it",
			math.floor(bestScore * 100 + 0.5),
			named and (" '" .. named .. "'") or ""
		))
	end
end

function Plan.ApplySuggestion()
	local sig = Plan.suggestion
	local stored = sig and HO.db.plans[sig]
	if not stored then
		return false
	end
	HO.db.activePlan = Copy(stored)
	HO.db.activeSignature = Plan.CurrentSignature()
	stored.meta.lastUsed = time()
	Plan.suggestion = nil
	if HO.Comm and HO.Comm.SendPlanApply() then
		HO.Print("plan broadcast to the group")
	end
	return true
end

HO.Roster.OnChanged(OnRosterChanged)
