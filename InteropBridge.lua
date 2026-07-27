-- HolyOrders — legacy blessing-addon bridge (EMIT ONLY)
-- Lets raiders still running an older, third-party blessing addon follow the
-- plan held here. Two emissions in that addon's addon-message wire format:
-- our own paladin row (SELF), and a PUSH of every other held paladin row
-- (PASSIGN + NASSIGN) so a coordinator on ANY class can drive legacy paladins.
-- Legacy clients apply a pushed foreign row only when we are raid lead/assist
-- or they enabled their free-assignment option; once applied, the target's own
-- client re-broadcasts the row natively. We never read legacy state (the only
-- inbound message we act on is a pull request, and only to re-emit). Off by
-- default, behind HO.db.options.legacyBroadcast.
--
-- Clean-room: the wire format is a functional interface reproduced from a written
-- protocol note only (kept locally in docs/, untracked). No third-party code,
-- structure or tables are copied — the mapping tables below are our own.

local HO = HolyOrders
local Interop = {}
HO.Interop = Interop

local WIRE_PREFIX = "PLPWR" -- the legacy addon's registered addon-message prefix
local BROADCAST_DELAY = 1.5 -- coalesce a burst of plan edits into one broadcast
local NASSIGN_MAX = 5 -- the legacy format packs at most 5 override entries per message
local LEGACY_NUM_CLASSES = 9 -- max classes on the BCC branch of the legacy addon

-- HolyOrders blessing id -> legacy blessing number
local HO_TO_LEGACY = { [1] = 1, [2] = 3, [3] = 2, [4] = 4, [5] = 5, [6] = 6 }
-- legacy caps slot (1..6, legacy blessing order) -> HolyOrders blessing id
local LEGACY_SLOT_TO_HO = { 1, 3, 2, 4, 5, 6 }
-- class token -> legacy class index (BCC order)
local LEGACY_CLASS_INDEX = { WARRIOR = 1, ROGUE = 2, PRIEST = 3, DRUID = 4, PALADIN = 5, HUNTER = 6, MAGE = 7, WARLOCK = 8, SHAMAN = 9 }
local LEGACY_INDEX_CLASS = {}
for token, idx in pairs(LEGACY_CLASS_INDEX) do
	LEGACY_INDEX_CLASS[idx] = token
end

local enabled = false
local prefixRegistered = false
local broadcastTimer = nil

-- helpers ---------------------------------------------------------------------

local function ShortName(name)
	return name and (name:match("^([^%-]+)") or name) or nil
end

local function IsPaladin()
	return select(2, UnitClass("player")) == "PALADIN"
end

local function GroupChannel()
	if IsInRaid() then
		return "RAID"
	elseif IsInGroup() then
		return "PARTY"
	end
	return nil
end

local function Emit(msg, channel, target)
	if not C_ChatInfo or not C_ChatInfo.SendAddonMessage then
		return
	end
	if HO.db and HO.db.options.trace then
		HO.Log("interop", (channel or "?") .. (target and ("/" .. target) or "") .. " " .. msg:sub(1, 120))
	end
	C_ChatInfo.SendAddonMessage(WIRE_PREFIX, msg, channel, target)
end

-- encoding --------------------------------------------------------------------

-- our capabilities as the legacy 12-char caps string: per blessing slot (legacy
-- order) either "nn" when unknown, or two hex digits (spell rank, improved-talent
-- rank). Each value is clamped to a single hex digit.
local function EncodeCaps()
	local caps = ""
	for slot = 1, 6 do
		local hoID = LEGACY_SLOT_TO_HO[slot]
		local blessing = HO.Data.blessings[hoID]
		if blessing and blessing.known then
			local rank = blessing.rankNum or 1
			local talent = (HO.Talents.ranks and HO.Talents.ranks[hoID]) or 0
			if rank > 15 then rank = 15 end
			if talent > 15 then talent = 15 end
			caps = caps .. string.format("%x%x", rank, talent)
		else
			caps = caps .. "nn"
		end
	end
	return caps
end

-- a paladin's class grid as the legacy 9-char string: per class index (BCC
-- order) either "n" (no assignment / explicit-none) or the legacy blessing number
local function EncodeGrid(owner)
	local rows = (owner and HO.Plan.Active().class[owner]) or {}
	local grid = ""
	for i = 1, LEGACY_NUM_CLASSES do
		local token = LEGACY_INDEX_CLASS[i]
		local assign = token and rows[token]
		if assign and assign.id and HO_TO_LEGACY[assign.id] then
			grid = grid .. tostring(HO_TO_LEGACY[assign.id])
		else
			grid = grid .. "n" -- unassigned or explicit-none both read as "no assignment"
		end
	end
	return grid
end

-- a paladin's per-target overrides as legacy override entries: "<player>
-- <class_id> <target> <blessing_id>", sorted by target for a deterministic wire
local function OverrideEntries(owner)
	local theirs = (owner and HO.Plan.Active().player[owner]) or {}
	local names = {}
	for targetName in pairs(theirs) do
		names[#names + 1] = targetName
	end
	table.sort(names)
	local player = ShortName(owner) or "?"
	local entries = {}
	for _, targetName in ipairs(names) do
		local legacyNum = HO_TO_LEGACY[theirs[targetName]] or 0
		local rosterEntry = HO.Roster.byName and HO.Roster.byName[targetName]
		local classIdx = (rosterEntry and rosterEntry.class and LEGACY_CLASS_INDEX[rosterEntry.class]) or 0
		entries[#entries + 1] = player .. " " .. classIdx .. " " .. (ShortName(targetName) or "?") .. " " .. legacyNum
	end
	return entries
end

-- every paladin whose row we hold and who is still in the roster, sorted; the
-- own row is listed too (SELF carries it for paladin senders, the push covers
-- the coordinator-on-another-class case where there is no own row anyway)
local function HeldOwners()
	local owners = {}
	for owner in pairs(HO.Plan.Active().class) do
		if HO.Roster.byName and HO.Roster.byName[owner] then
			owners[#owners + 1] = owner
		end
	end
	table.sort(owners)
	return owners
end

-- broadcast -------------------------------------------------------------------

-- send our own row as SELF (paladins only — SELF describes the sender's own
-- paladin row), then PUSH every other held paladin row as PASSIGN, plus all
-- per-target overrides as NASSIGN chunks. Receiving legacy clients apply a
-- pushed foreign row only when we are raid lead/assist or they have their
-- free-assignment option enabled; pushing works from any class, so a
-- non-paladin coordinator can drive legacy paladins too. Once applied, the
-- target's own legacy client re-broadcasts the row natively as its SELF.
-- the last group-channel emission, for content dedup: every received message
-- makes a legacy client rebuild its whole layout, so re-sending an unchanged
-- plan on roster churn turns their UI into a strobe. Whispered replies and
-- explicit pull requests bypass the dedup (the requester may hold nothing).
local lastGroupWire = nil

local function Broadcast(target, force)
	if not enabled then
		return
	end
	local channel = target and "WHISPER" or GroupChannel()
	if not channel then
		lastGroupWire = nil -- solo: nobody to tell; a future group starts fresh
		return
	end
	local me = HO.FullName("player")
	local parts = {}
	if IsPaladin() then
		parts[#parts + 1] = "SELF " .. EncodeCaps() .. "@" .. EncodeGrid(me)
	end
	local entries = {}
	for _, owner in ipairs(HeldOwners()) do
		if owner ~= me then
			parts[#parts + 1] = "PASSIGN " .. (ShortName(owner) or "?") .. "@" .. EncodeGrid(owner)
		end
		for _, e in ipairs(OverrideEntries(owner)) do
			entries[#entries + 1] = e
		end
	end
	for i = 1, #entries, NASSIGN_MAX do
		local last = math.min(i + NASSIGN_MAX - 1, #entries)
		parts[#parts + 1] = "NASSIGN " .. table.concat(entries, "@", i, last)
	end
	if not target then
		local wire = channel .. "\n" .. table.concat(parts, "\n")
		if not force and wire == lastGroupWire then
			return -- nothing changed: spare every legacy client a layout rebuild
		end
		lastGroupWire = wire
	end
	for _, msg in ipairs(parts) do
		Emit(msg, channel, target)
	end
end

local pendingForce = false

local function ScheduleBroadcast(force)
	if not enabled then
		return
	end
	pendingForce = pendingForce or force or false
	if broadcastTimer then
		broadcastTimer:Cancel()
	end
	broadcastTimer = C_Timer.NewTimer(BROADCAST_DELAY, function()
		broadcastTimer = nil
		local f = pendingForce
		pendingForce = false
		Broadcast(nil, f)
	end)
end

-- inbound: react ONLY to a pull request (re-emit); never parse legacy state ------

local function OnAddonMessage(prefix, message, channel, senderFull)
	if prefix ~= WIRE_PREFIX or not enabled then
		return
	end
	-- ignore our own echoes
	if ShortName(senderFull) == ShortName(HO.FullName("player") or "") then
		return
	end
	-- with debug logging on, record what legacy clients actually send on the wire,
	-- so the emitted format can be verified against a real one (observation only)
	if HO.db and HO.db.options.trace then
		HO.Log("interop", "rx " .. (ShortName(senderFull) or "?") .. " " .. tostring(message):sub(1, 200))
	end
	if message:match("^(%S+)") == "REQ" then
		-- answer a whispered request privately, a broadcast request to the
		-- group; a pull always re-emits (the requester may hold nothing yet)
		if channel == "WHISPER" and senderFull then
			Broadcast(senderFull)
		else
			ScheduleBroadcast(true)
		end
	end
end

-- public API ------------------------------------------------------------------

local function RegisterPrefix()
	if prefixRegistered then
		return
	end
	if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
		C_ChatInfo.RegisterAddonMessagePrefix(WIRE_PREFIX)
	end
	prefixRegistered = true -- a prefix cannot be unregistered; the handler gates on `enabled`
end

function Interop.IsEnabled()
	return enabled
end

-- toggle the bridge. Enabling registers the wire prefix (once) and broadcasts our
-- current plan; disabling just stops emitting (inbound is gated on `enabled`).
function Interop.SetEnabled(on)
	on = on and true or false
	if on == enabled then
		return
	end
	enabled = on
	if enabled then
		RegisterPrefix()
		Broadcast()
	end
end

-- a local plan edit changed any held row: rebroadcast (debounced) — foreign
-- rows are pushed to legacy clients too, so every change is wire-relevant
function Interop.OnLocalPlanChanged(paladin)
	if enabled and paladin then
		ScheduleBroadcast()
	end
end

-- diagnostics: status flags plus the exact strings we would emit. For verifying
-- the bridge against a live legacy client without reading its code.
function Interop.Status()
	local me = HO.FullName("player")
	local pushes, overrides = {}, {}
	for _, owner in ipairs(HeldOwners()) do
		if owner ~= me then
			pushes[#pushes + 1] = "PASSIGN " .. (ShortName(owner) or "?") .. "@" .. EncodeGrid(owner)
		end
		for _, e in ipairs(OverrideEntries(owner)) do
			overrides[#overrides + 1] = e
		end
	end
	return {
		enabled = enabled,
		paladin = IsPaladin(),
		channel = GroupChannel(),
		selfMsg = IsPaladin() and ("SELF " .. EncodeCaps() .. "@" .. EncodeGrid(me)) or nil,
		pushes = pushes,
		overrides = overrides,
	}
end

-- force an immediate broadcast (bypasses the debounce). Returns false if it
-- could not send: disabled or solo.
function Interop.ForceBroadcast()
	if not enabled or not GroupChannel() then
		return false
	end
	Broadcast(nil, true) -- diagnostics: always send, bypassing the dedup
	return true
end

HO.RegisterEvent("CHAT_MSG_ADDON", OnAddonMessage)

HO.RegisterEvent("PLAYER_LOGIN", function()
	if HO.db and HO.db.options.legacyBroadcast then
		Interop.SetEnabled(true)
	end
	-- present-paladins changed → refresh what legacy clients see (debounced)
	if HO.Roster and HO.Roster.OnChanged then
		HO.Roster.OnChanged(function()
			ScheduleBroadcast()
		end)
	end
end)
