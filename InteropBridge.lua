-- HolyOrders — legacy blessing-addon bridge (EMIT ONLY)
-- Lets raiders still running an older, third-party blessing addon see this
-- paladin's plan. We broadcast our own assignments in that addon's addon-message
-- wire format; we never read its state (the only inbound message we act on is a
-- pull request, and only to re-emit). Off by default, behind
-- HO.db.options.legacyBroadcast.
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

-- our class grid as the legacy 9-char string: per class index (BCC order) either
-- "n" (no assignment / explicit-none) or the legacy blessing number
local function EncodeGrid()
	local me = HO.FullName("player")
	local myClass = (me and HO.Plan.Active().class[me]) or {}
	local grid = ""
	for i = 1, LEGACY_NUM_CLASSES do
		local token = LEGACY_INDEX_CLASS[i]
		local assign = token and myClass[token]
		if assign and assign.id and HO_TO_LEGACY[assign.id] then
			grid = grid .. tostring(HO_TO_LEGACY[assign.id])
		else
			grid = grid .. "n" -- unassigned or explicit-none both read as "no assignment"
		end
	end
	return grid
end

-- per-target overrides as legacy override entries: "<player> <class_id> <target>
-- <blessing_id>", sorted by target for a deterministic wire
local function OverrideEntries()
	local me = HO.FullName("player")
	local mine = (me and HO.Plan.Active().player[me]) or {}
	local names = {}
	for targetName in pairs(mine) do
		names[#names + 1] = targetName
	end
	table.sort(names)
	local player = ShortName(me) or "?"
	local entries = {}
	for _, targetName in ipairs(names) do
		local legacyNum = HO_TO_LEGACY[mine[targetName]] or 0
		local rosterEntry = HO.Roster.byName and HO.Roster.byName[targetName]
		local classIdx = (rosterEntry and rosterEntry.class and LEGACY_CLASS_INDEX[rosterEntry.class]) or 0
		entries[#entries + 1] = player .. " " .. classIdx .. " " .. (ShortName(targetName) or "?") .. " " .. legacyNum
	end
	return entries
end

-- broadcast -------------------------------------------------------------------

-- send SELF (+ NASSIGN chunks) on the group channel, or whispered to `target`
-- when answering a direct pull request. Paladins only — SELF describes the
-- sender's own paladin row.
local function Broadcast(target)
	if not enabled or not IsPaladin() then
		return
	end
	local channel = target and "WHISPER" or GroupChannel()
	if not channel then
		return -- solo: nobody to tell
	end
	Emit("SELF " .. EncodeCaps() .. "@" .. EncodeGrid(), channel, target)
	local entries = OverrideEntries()
	for i = 1, #entries, NASSIGN_MAX do
		local last = math.min(i + NASSIGN_MAX - 1, #entries)
		Emit("NASSIGN " .. table.concat(entries, "@", i, last), channel, target)
	end
end

local function ScheduleBroadcast()
	if not enabled then
		return
	end
	if broadcastTimer then
		broadcastTimer:Cancel()
	end
	broadcastTimer = C_Timer.NewTimer(BROADCAST_DELAY, function()
		broadcastTimer = nil
		Broadcast()
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
	if message:match("^(%S+)") == "REQ" then
		-- answer a whispered request privately, a broadcast request to the group
		if channel == "WHISPER" and senderFull then
			Broadcast(senderFull)
		else
			ScheduleBroadcast()
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

-- a local plan edit changed a row: rebroadcast (debounced) if it was ours
function Interop.OnLocalPlanChanged(paladin)
	if enabled and paladin == HO.FullName("player") then
		ScheduleBroadcast()
	end
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
