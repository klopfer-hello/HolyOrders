-- HolyOrders — blessing plan model and per-roster persistence
-- The active plan is what gets edited and cast from; it persists across
-- reloads. Stored plans are keyed by the sorted paladin roster: an exact
-- roster match re-applies automatically, a similar roster is suggested.

local HO = HolyOrders
local Plan = {}
HO.Plan = Plan
local function L(key)
	return (HO.L or {})[key] or key
end

Plan.MAX_STORED = 20 -- unnamed plans beyond this are pruned (oldest first)
Plan.SUGGEST_THRESHOLD = 0.5 -- min paladin-set overlap for a suggestion

local VALID_MODES = { auto = true, greater = true, normal = true }

local function NewPlan()
	return {
		version = 1,
		class = {}, -- [paladinName][classToken] = { id, mode }
		player = {}, -- [paladinName][targetName] = blessingID
		aura = {}, -- [paladinName] = auraID (which aura that paladin runs)
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
	-- normalize: plans written by other addon versions must never nil-error
	local plan = HO.db.activePlan
	plan.class = plan.class or {}
	plan.player = plan.player or {}
	plan.aura = plan.aura or {}
	plan.tanks = plan.tanks or {}
	plan.meta = plan.meta or { created = time() }
	return plan
end

local function MarkDirty(plan)
	plan.meta = plan.meta or {}
	plan.meta.dirty = true
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
	MarkDirty(plan)
	if HO.Comm then
		HO.Comm.OnClassEdited(paladin, classToken)
	end
end

-- explicit "none" for a class: a placeholder marker (no id) that keeps a visible,
-- re-assignable slot instead of removing the duty. Local-only — it serializes as
-- absence (unassigned) on the wire, so peers treat the class as cleared.
function Plan.SetClassNone(paladin, classToken)
	local plan = Plan.Active()
	plan.class[paladin] = plan.class[paladin] or {}
	plan.class[paladin][classToken] = { none = true }
	MarkDirty(plan)
	if HO.Comm then
		HO.Comm.OnClassEdited(paladin, classToken)
	end
end

-- which aura a paladin runs (0/nil clears). Mirrors SetClassAssignment: writes
-- the plan, marks it dirty and notifies Comm (nil-safe) for a live broadcast.
function Plan.SetAura(paladin, auraID)
	local plan = Plan.Active()
	if not auraID or auraID == 0 then
		plan.aura[paladin] = nil
	else
		plan.aura[paladin] = auraID
	end
	MarkDirty(plan)
	if HO.Comm then
		HO.Comm.OnAuraEdited(paladin)
	end
end

function Plan.GetAura(paladin)
	if not paladin then
		return nil
	end
	local plan = Plan.Active()
	return plan.aura and plan.aura[paladin] or nil
end

function Plan.SetPlayerOverride(paladin, targetName, blessingID)
	local plan = Plan.Active()
	plan.player[paladin] = plan.player[paladin] or {}
	if blessingID == 0 then
		plan.player[paladin][targetName] = nil
	else
		plan.player[paladin][targetName] = blessingID
	end
	MarkDirty(plan)
	if HO.Comm then
		HO.Comm.OnOverrideEdited(paladin, targetName)
	end
end

-- persistent per-member blessing liking, remembered by character name and
-- independent of any paladin pairing. This is NOT plan state (never marks the
-- plan dirty); it feeds the auto-planner's preference chain and syncs on its own.
function Plan.SetMemberPref(name, blessingID)
	if not name or not HO.db then
		return
	end
	HO.db.memberPrefs = HO.db.memberPrefs or {}
	local newID = (blessingID and blessingID ~= 0) and blessingID or nil
	if HO.db.memberPrefs[name] == newID then
		return -- unchanged: nothing to store or announce
	end
	HO.db.memberPrefs[name] = newID
	if HO.Comm and HO.Comm.OnMemberPrefChanged then
		HO.Comm.OnMemberPrefChanged(name, newID)
	end
end

function Plan.MemberPref(name)
	if not name or not HO.db or not HO.db.memberPrefs then
		return nil
	end
	return HO.db.memberPrefs[name]
end

function Plan.ToggleTank(name)
	-- gate here too so no future caller can bypass the tank-flag permission
	-- (nil-safe when Comm is not loaded)
	if HO.Comm and HO.Comm.CanFlagTank and not HO.Comm.CanFlagTank(name) then
		return nil
	end
	local plan = Plan.Active()
	local flagged
	if plan.tanks[name] then
		plan.tanks[name] = nil
		flagged = false
	else
		plan.tanks[name] = true
		flagged = true
	end
	MarkDirty(plan)
	if HO.Comm then
		HO.Comm.OnTankToggled(name, flagged)
	end
	return flagged
end

-- is this character a tank for planning purposes? Manual flag, raid MAINTANK
-- role, local protection spec tag, or the synced spec overlay (so every client
-- computes the same tank set even when their inspect results diverge).
function Plan.IsTank(name, tankRole)
	if name and Plan.Active().tanks[name] then
		return true -- manual tank flag
	end
	if tankRole then
		return true -- raid MAINTANK role
	end
	if name and HO.db.specCache[name] == "protection" then
		return true -- local spec tag (manual or inspect-inferred)
	end
	if name and HO.Comm and HO.Comm.specSync[name] == "protection" then
		return true -- synced overlay from another client
	end
	return false
end

-- temporary no-Salvation mode -------------------------------------------------
-- For encounters with random aggro: swaps every Salvation assignment for a
-- substitute and remembers the previous plan; disabling restores it exactly.

local SALVATION = 4

function Plan.NoSalvationActive()
	return HO.db.salvSnapshot ~= nil
end

function Plan.SetNoSalvation(enable)
	if enable then
		-- never overwrite an existing snapshot (F2): two leads racing must not
		-- snapshot each other's already-swapped plan
		if HO.db.salvSnapshot then
			return false, "already active"
		end
		local plan = Plan.Active()
		-- nothing to swap → do nothing, so a race cannot snapshot an already
		-- Salvation-free plan and then be unable to restore Salvation (F1)
		local hasSalv = false
		for _, rows in pairs(plan.class) do
			for _, a in pairs(rows) do
				if a.id == SALVATION then
					hasSalv = true
					break
				end
			end
			if hasSalv then
				break
			end
		end
		if not hasSalv then
			for _, targets in pairs(plan.player) do
				for _, id in pairs(targets) do
					if id == SALVATION then
						hasSalv = true
						break
					end
				end
				if hasSalv then
					break
				end
			end
		end
		if not hasSalv then
			return false, "no Salvation assignments to swap"
		end
		HO.db.salvSnapshot = Copy(plan)
		local changed = 0
		for pally, rows in pairs(plan.class) do
			for classToken, a in pairs(rows) do
				if a.id == SALVATION then
					local sub = HO.Planner.SalvSubstitute(pally, classToken, plan)
					if sub then
						a.id = sub
					else
						rows[classToken] = nil
					end
					changed = changed + 1
				end
			end
		end
		for _, targets in pairs(plan.player) do
			for target, id in pairs(targets) do
				if id == SALVATION then
					targets[target] = nil
					changed = changed + 1
				end
			end
		end
		HO.Log("plan", "no-salvation enabled, " .. changed .. " swapped")
		return true, changed
	end
	if not HO.db.salvSnapshot then
		return false, "not active"
	end
	local restored = HO.db.salvSnapshot
	-- keep revisions monotonic so the restore propagates over the swap
	restored.rev = Copy(Plan.Active().rev or {})
	HO.db.activePlan = restored
	HO.db.salvSnapshot = nil
	HO.Log("plan", "no-salvation reverted")
	return true
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
	stored.rev = nil -- stored plans never carry revision state
	stored.meta.lastUsed = time()
	stored.meta.dirty = nil
	if label and label ~= "" then
		stored.meta.name = label
	end
	HO.db.plans[sig] = stored
	HO.db.activeSignature = sig
	Plan.Active().meta.dirty = nil -- saved: no unsaved edits anymore
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
		if Plan.suggestion ~= sig then
			Plan.suggestion = nil -- a suggestion from a different roster is stale
		end
		return
	end
	lastHandledSig = sig
	if sig == HO.db.activeSignature then
		if Plan.suggestion ~= sig then
			Plan.suggestion = nil -- stale suggestion from a different roster
		end
		return -- same roster as the active plan; nothing to do
	end
	local stored = HO.db.plans[sig]
	if stored then
		local active = Plan.Active()
		local dirty = active.meta and active.meta.dirty
		-- no-Salvation mode must survive a roster change: auto-applying a stored
		-- plan would resurrect the swapped-out Salvation mid-encounter
		local noSalv = Plan.NoSalvationActive() or HO.db.noSalvBy
		if dirty or noSalv then
			-- offer instead of applying; do NOT stamp activeSignature (nothing
			-- was applied)
			Plan.suggestion = sig
			HO.Log("plan", "stored plan for " .. sig .. " offered (auto-apply suppressed)")
			if dirty then
				HO.Print(L("stored plan for this roster available — '/ho plan apply' loads it (your unsaved edits are kept until then)")
					.. (noSalv and " (no-Salvation mode active)" or ""))
			else
				HO.Print("stored plan for this roster available — '/ho plan apply' loads it (no-Salvation mode active)")
			end
			return
		end
		-- adopt the stored plan; carry the CURRENT rev table forward so peers
		-- accept the restored rows (stored plans hold no rev of their own)
		local prevRev = Copy(Plan.Active().rev or {})
		HO.db.activePlan = Copy(stored)
		HO.db.activePlan.rev = prevRev
		HO.db.activePlan.meta.dirty = nil
		HO.db.activeSignature = sig
		stored.meta.lastUsed = time()
		Plan.suggestion = nil
		HO.Log("plan", "auto-applied stored plan for " .. sig)
		HO.Announce(L("stored plan applied for this paladin roster") .. (stored.meta.name and (" ('" .. stored.meta.name .. "')") or ""))
		-- the automatic broadcast fires on every privileged client at once;
		-- gate it to the actual group leader. Other privileged clients apply
		-- locally and only re-sync their own row.
		if HO.Comm then
			if UnitIsGroupLeader("player") then
				if HO.Comm.SendPlanApply() then
					-- PLANAPPLY carries no auras; the lead teaches them here
					HO.Comm.BroadcastAuras()
					HO.Announce(L("plan broadcast to the group"))
				end
			else
				HO.Comm.BroadcastOwnRow()
			end
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
	-- carry the current rev table forward so peers accept the loaded rows
	-- (stored plans hold no rev of their own)
	local prevRev = Copy(Plan.Active().rev or {})
	HO.db.activePlan = Copy(stored)
	HO.db.activePlan.rev = prevRev
	HO.db.activePlan.meta.dirty = nil
	HO.db.activeSignature = Plan.CurrentSignature()
	stored.meta.lastUsed = time()
	Plan.suggestion = nil
	if HO.Comm and HO.Comm.SendPlanApply() then
		HO.Comm.BroadcastAuras() -- PLANAPPLY carries no auras; teach them here
		HO.Print(L("plan broadcast to the group"))
	end
	return true
end

HO.Roster.OnChanged(OnRosterChanged)
