-- HolyOrders — sync protocol (SPEC-sync)
-- Revision-numbered per-paladin rows, capture-at-send debounced SETs,
-- explicit clears, atomic plan application, symmetric permissions.
-- No state is ever wiped on join/leave; convergence is by revision only.

local HO = HolyOrders
local Comm = {}
HO.Comm = Comm

local PREFIX = "HolyOrders"
local PROTO = "3" -- v3: caps carry spell ranks for buff-strength scoring
local SET_DELAY = 1.0
local HELLO_DELAY = 2.0
local MAX_MSG = 250 -- WoW addon messages cap at 255 bytes

-- compact wire encoding: class tokens and modes as single characters so a
-- full row stays far below the message size cap
local CLASS_CODE = { WARRIOR = "W", PALADIN = "P", HUNTER = "H", ROGUE = "R", PRIEST = "I", SHAMAN = "S", MAGE = "M", WARLOCK = "L", DRUID = "D" }
local CODE_CLASS = {}
for token, code in pairs(CLASS_CODE) do
	CODE_CLASS[code] = token
end
local MODE_CODE = { auto = "a", greater = "g", normal = "n" }
local CODE_MODE = { a = "auto", g = "greater", n = "normal" }

Comm.peers = {} -- [fullName] = { version, openEdit, caps = {[id]={known,greater,talent}}, greeted }
Comm.suspended = false -- true while the planner bulk-edits (PLANAPPLY follows)

local me -- own full name, set on login
local planBuffer = nil -- incoming PLANAPPLY rows, buffered until PE

-- transport -------------------------------------------------------------------

local function Channel()
	if IsInRaid() then
		return "RAID"
	elseif IsInGroup() then
		return "PARTY"
	end
	return nil
end

local function Send(msg, channel, target)
	channel = channel or Channel()
	if not channel then
		return
	end
	if HO.db and HO.db.options.trace then
		HO.Log("tx", channel .. (target and ("/" .. target) or "") .. " " .. msg:sub(1, 120))
	end
	local wire = PROTO .. ":" .. msg
	if #wire > MAX_MSG then
		HO.Log("comm", "OVERSIZED message dropped (" .. #wire .. "b): " .. wire:sub(1, 60))
		return
	end
	C_ChatInfo.SendAddonMessage(PREFIX, wire, channel, target)
end

-- debounced sends: one pending timer per key, payload captured at queue time
local sendTimers = {}
local function QueueSend(key, msg)
	if sendTimers[key] then
		sendTimers[key]:Cancel()
	end
	sendTimers[key] = C_Timer.NewTimer(SET_DELAY, function()
		sendTimers[key] = nil
		Send(msg)
	end)
end

-- permissions (one shared rule for sender and receiver) -----------------------

function Comm.CanEdit(editor, owner)
	if editor == owner then
		return true
	end
	local entry = HO.Roster.byName[editor]
	if entry and (entry.rank or 0) > 0 then
		return true -- raid leader or assist
	end
	if owner == me then
		return HO.db.options.openEdit or false
	end
	local peer = Comm.peers[owner]
	return (peer and peer.openEdit) or false
end

function Comm.CanBulk(editor)
	local entry = HO.Roster.byName[editor]
	return (entry and (entry.rank or 0) > 0) or not IsInGroup()
end

-- revisions -------------------------------------------------------------------

local function Revs(plan)
	plan.rev = plan.rev or {}
	return plan.rev
end

local function BumpRev(owner)
	local revs = Revs(HO.Plan.Active())
	revs[owner] = (revs[owner] or 0) + 1
	return revs[owner]
end

-- serialization ---------------------------------------------------------------

local function Caps()
	local parts = {}
	for id, blessing in ipairs(HO.Data.blessings) do
		parts[id] = (blessing.known and "1" or "0")
			.. (blessing.greaterKnown and "1" or "0")
			.. tostring(math.min(HO.Talents.ranks[id] or 0, 9))
			.. string.format("%02d", math.min(blessing.rankNum or 0, 99))
	end
	return table.concat(parts, ",")
end

local function SerializeRow(owner)
	local plan = HO.Plan.Active()
	local classParts = {}
	for classToken, a in pairs(plan.class[owner] or {}) do
		local code = CLASS_CODE[classToken]
		if code then
			table.insert(classParts, code .. a.id .. (MODE_CODE[a.mode] or "a"))
		end
	end
	table.sort(classParts)
	local ovParts = {}
	for target, id in pairs(plan.player[owner] or {}) do
		table.insert(ovParts, target .. "=" .. id)
	end
	table.sort(ovParts)
	return owner .. ";" .. (Revs(plan)[owner] or 0) .. ";"
		.. table.concat(classParts, "|") .. ";" .. table.concat(ovParts, "|")
end

-- applies a serialized row if permitted and newer; direct table writes only
-- (never through Plan.Set*, which would echo back into Comm)
local function ApplyRow(payload, sender)
	local owner, rev, classCsv, ovCsv = strsplit(";", payload)
	rev = tonumber(rev)
	if not owner or not rev then
		return
	end
	if not Comm.CanEdit(sender, owner) then
		HO.Log("comm", "rejected row for " .. owner .. " from " .. sender)
		return
	end
	local plan = HO.Plan.Active()
	local localRev = Revs(plan)[owner] or 0
	-- the owner's own state wins ties (authoritative for their row);
	-- everyone else needs a strictly newer revision
	if sender == owner then
		if rev < localRev then
			return
		end
	elseif rev <= localRev then
		return
	end
	local class = {}
	if classCsv and classCsv ~= "" then
		for pair in string.gmatch(classCsv, "[^|]+") do
			local code, id, modeCode = pair:match("^(%u)(%d)(%a)$")
			local token = code and CODE_CLASS[code]
			if token and HO.Data.blessings[tonumber(id)] then
				class[token] = { id = tonumber(id), mode = CODE_MODE[modeCode] or "auto" }
			end
		end
	end
	local player = {}
	if ovCsv and ovCsv ~= "" then
		for pair in string.gmatch(ovCsv, "[^|]+") do
			local target, id = pair:match("^(.+)=(%d+)$")
			if target and HO.Data.blessings[tonumber(id)] then
				player[target] = tonumber(id)
			end
		end
	end
	plan.class[owner] = class
	plan.player[owner] = player
	Revs(plan)[owner] = rev
	return true
end

-- outgoing --------------------------------------------------------------------

function Comm.SendHello(channel, target)
	Send("H:" .. HO.VERSION .. ";" .. (HO.db.options.openEdit and "1" or "0") .. ";" .. Caps(), channel, target)
end

function Comm.SendFull(target)
	Send("F:" .. SerializeRow(me), target and "WHISPER" or nil, target)
end

-- called by Plan.Set* after every local edit (unless suspended for a bulk op)
function Comm.OnClassEdited(owner, classToken)
	if Comm.suspended or not me then
		return
	end
	local plan = HO.Plan.Active()
	local rev = BumpRev(owner)
	local a = plan.class[owner] and plan.class[owner][classToken]
	local msg = "SC:" .. owner .. ";" .. rev .. ";" .. (CLASS_CODE[classToken] or "?") .. ";"
		.. (a and a.id or 0) .. ";" .. (a and MODE_CODE[a.mode] or "a")
	QueueSend("SC:" .. owner .. ":" .. classToken, msg)
end

function Comm.OnOverrideEdited(owner, target)
	if Comm.suspended or not me then
		return
	end
	local plan = HO.Plan.Active()
	local rev = BumpRev(owner)
	local id = plan.player[owner] and plan.player[owner][target] or 0
	QueueSend("SP:" .. owner .. ":" .. target, "SP:" .. owner .. ";" .. rev .. ";" .. target .. ";" .. id)
end

function Comm.OnTankToggled(name, flagged)
	if Comm.suspended or not me then
		return
	end
	QueueSend("T:" .. name, "T:" .. name .. ";" .. (flagged and "1" or "0"))
end

-- atomic plan broadcast: every row re-revisioned and sent, then tanks
function Comm.SendPlanApply()
	if not me or not Channel() then
		return false
	end
	if not Comm.CanBulk(me) then
		return false
	end
	local plan = HO.Plan.Active()
	local owners, seen = {}, {}
	for owner in pairs(plan.class) do
		if not seen[owner] then
			seen[owner] = true
			table.insert(owners, owner)
		end
	end
	for owner in pairs(plan.player) do
		if not seen[owner] then
			seen[owner] = true
			table.insert(owners, owner)
		end
	end
	table.sort(owners)
	Send("PS:" .. #owners)
	for _, owner in ipairs(owners) do
		BumpRev(owner)
		Send("PR:" .. SerializeRow(owner))
	end
	local tanks = {}
	for name in pairs(plan.tanks) do
		table.insert(tanks, name)
	end
	table.sort(tanks)
	Send("PE:" .. table.concat(tanks, "|"))
	HO.Log("comm", "plan apply sent: " .. #owners .. " rows")
	return true
end

-- incoming --------------------------------------------------------------------

local function RefreshUI()
	HO.Window.Refresh()
	HO.Bar.Refresh()
end

local handlers = {}

handlers["H"] = function(sender, payload)
	local version, openEdit, caps = strsplit(";", payload)
	local peer = Comm.peers[sender] or {}
	peer.version = version
	peer.openEdit = (openEdit == "1")
	peer.caps = {}
	if caps then
		local id = 0
		for triplet in string.gmatch(caps, "[^,]+") do
			id = id + 1
			peer.caps[id] = {
				known = triplet:sub(1, 1) == "1",
				greater = triplet:sub(2, 2) == "1",
				talent = tonumber(triplet:sub(3, 3)) or 0,
				rank = tonumber(triplet:sub(4, 5)) or 0,
			}
		end
	end
	Comm.peers[sender] = peer
	HO.Log("comm", "hello from " .. sender .. " v" .. tostring(version))
	-- greet back once and share our state directly with the newcomer
	if not peer.greeted then
		peer.greeted = true
		C_Timer.After(math.random() * HELLO_DELAY, function()
			Comm.SendHello("WHISPER", sender)
			Comm.SendFull(sender)
		end)
	end
end

handlers["R"] = function(sender)
	C_Timer.After(math.random() * HELLO_DELAY, function()
		Comm.SendFull(sender)
	end)
end

handlers["F"] = function(sender, payload)
	if ApplyRow(payload, sender) then
		RefreshUI()
	end
end

handlers["SC"] = function(sender, payload)
	local owner, rev, classCode, id, modeCode = strsplit(";", payload)
	local classToken = classCode and CODE_CLASS[classCode]
	local mode = modeCode and CODE_MODE[modeCode] or "auto"
	rev, id = tonumber(rev), tonumber(id)
	if not owner or not rev or not id or not classToken then
		return
	end
	if not Comm.CanEdit(sender, owner) then
		return
	end
	local plan = HO.Plan.Active()
	if rev <= (Revs(plan)[owner] or 0) and sender ~= owner then
		return
	end
	plan.class[owner] = plan.class[owner] or {}
	if id == 0 then
		plan.class[owner][classToken] = nil
	else
		plan.class[owner][classToken] = { id = id, mode = mode or "auto" }
	end
	Revs(plan)[owner] = rev
	RefreshUI()
end

handlers["SP"] = function(sender, payload)
	local owner, rev, target, id = strsplit(";", payload)
	rev, id = tonumber(rev), tonumber(id)
	if not owner or not rev or not id then
		return
	end
	if not Comm.CanEdit(sender, owner) then
		return
	end
	local plan = HO.Plan.Active()
	if rev <= (Revs(plan)[owner] or 0) and sender ~= owner then
		return
	end
	plan.player[owner] = plan.player[owner] or {}
	plan.player[owner][target] = (id ~= 0) and id or nil
	Revs(plan)[owner] = rev
	RefreshUI()
end

handlers["T"] = function(sender, payload)
	local name, flag = strsplit(";", payload)
	if not name then
		return
	end
	local entry = HO.Roster.byName[sender]
	local allowed = (sender == name) or (entry and (entry.rank or 0) > 0)
	if not allowed then
		return
	end
	local plan = HO.Plan.Active()
	plan.tanks[name] = (flag == "1") and true or nil
	RefreshUI()
end

handlers["PS"] = function(sender)
	if Comm.CanBulk(sender) then
		planBuffer = { sender = sender, rows = {} }
	end
end

handlers["PR"] = function(sender, payload)
	if planBuffer and planBuffer.sender == sender then
		table.insert(planBuffer.rows, payload)
	end
end

handlers["PE"] = function(sender, payload)
	if not planBuffer or planBuffer.sender ~= sender then
		return
	end
	local rows = planBuffer.rows
	planBuffer = nil
	local applied = 0
	for _, row in ipairs(rows) do
		if ApplyRow(row, sender) then
			applied = applied + 1
		end
	end
	local plan = HO.Plan.Active()
	wipe(plan.tanks)
	if payload and payload ~= "" then
		for name in string.gmatch(payload, "[^|]+") do
			plan.tanks[name] = true
		end
	end
	HO.Log("comm", "plan apply from " .. sender .. ": " .. applied .. "/" .. #rows .. " rows")
	HO.Print("blessing plan received from " .. sender)
	RefreshUI()
end

handlers["PING"] = function(sender)
	HO.Print("comm loopback OK (from " .. sender .. ")")
end

-- remote log pull: a group member requests our recent log; we whisper it
-- back in chunks so it ends up in THEIR SavedVariables for offline analysis
local LOG_SHARE_MAX = 25

handlers["LR"] = function(sender)
	if not HO.Roster.byName[sender] then
		return -- group members only
	end
	local log = HO.db.log
	local from = math.max(1, #log - LOG_SHARE_MAX + 1)
	local total = #log - from + 1
	if total <= 0 then
		Send("LL:1;1;<empty log>", "WHISPER", sender)
		return
	end
	local idx = 0
	for i = from, #log do
		idx = idx + 1
		local entry, myIdx = log[i], idx
		C_Timer.After(myIdx * 0.1, function()
			Send("LL:" .. myIdx .. ";" .. total .. ";" .. tostring(entry):sub(1, 180), "WHISPER", sender)
		end)
	end
	HO.Print("sent " .. total .. " log entries to " .. sender)
end

handlers["LL"] = function(sender, payload)
	local idx, total, entry = payload:match("^(%d+);(%d+);(.*)$")
	idx, total = tonumber(idx), tonumber(total)
	if not idx then
		return
	end
	HO.db.remoteLogs = HO.db.remoteLogs or {}
	if idx <= 1 then
		HO.db.remoteLogs[sender] = {}
	end
	local list = HO.db.remoteLogs[sender]
	if list then
		table.insert(list, entry)
		if idx == total then
			HO.Print("received " .. #list .. " log entries from " .. sender .. " — /reload writes them to SavedVariables")
		end
	end
end

function Comm.RequestLog(target)
	Send("LR:", "WHISPER", target)
end

-- no-Salvation mode state sync ------------------------------------------------

function Comm.SendNoSalv(active)
	Send("NS:" .. (active and "1" or "0"))
end

handlers["NS"] = function(sender, payload)
	local entry = HO.Roster.byName[sender]
	if not (entry and (entry.rank or 0) > 0) then
		return -- lead/assist only, like the feature itself
	end
	if payload == "1" then
		HO.db.noSalvBy = sender
		HO.Print("no-Salvation mode enabled by " .. sender)
	else
		HO.db.noSalvBy = nil
		if HO.Plan.NoSalvationActive() then
			-- we hold the snapshot; a lead asked for the revert — restore
			-- exactly and share both the plan and the ended state
			HO.Plan.SetNoSalvation(false)
			Comm.SendPlanApply()
			Comm.SendNoSalv(false)
			HO.Print("no-Salvation mode reverted (requested by " .. sender .. ")")
		else
			HO.Print("no-Salvation mode ended by " .. sender)
		end
	end
	RefreshUI()
end

local protoWarned = {}

HO.RegisterEvent("CHAT_MSG_ADDON", function(prefix, message, _, senderFull)
	if prefix ~= PREFIX then
		return
	end
	local sender = senderFull and senderFull:match("^[^%-]+%-[^%-]+") or senderFull
	local proto, msgType, payload = message:match("^(%d+):(%u+):?(.*)$")
	if proto ~= PROTO then
		-- incompatible protocol: warn once per sender instead of silence
		if proto and sender and sender ~= me and not protoWarned[sender] then
			protoWarned[sender] = true
			HO.Log("comm", "protocol mismatch from " .. sender .. " (theirs " .. proto .. ", ours " .. PROTO .. ")")
			HO.Print(sender .. " runs an incompatible HolyOrders version — sync with them is DISABLED until both run the same version")
		end
		return
	end
	if sender == me and msgType ~= "PING" then
		return -- own broadcasts echo back; PING is the deliberate loopback
	end
	if HO.db and HO.db.options.trace and msgType ~= "LL" then
		HO.Log("rx", sender .. " " .. msgType .. ":" .. tostring(payload):sub(1, 100))
	end
	local handler = handlers[msgType]
	if handler then
		local ok, err = pcall(handler, sender, payload)
		if not ok then
			HO.Log("error", "comm " .. tostring(msgType) .. ": " .. tostring(err))
		end
	end
end)

-- session wiring --------------------------------------------------------------

local lastPallySig

HO.RegisterEvent("PLAYER_LOGIN", function()
	me = HO.FullName("player")
	C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
	HO.Roster.OnChanged(function()
		-- greet whenever the paladin composition changes
		local sig = table.concat(HO.Roster.Paladins(), ";")
		if sig ~= lastPallySig then
			lastPallySig = sig
			if Channel() then
				Comm.SendHello()
				Comm.SendFull()
			end
		end
	end)
end)

function Comm.Ping()
	if not me then
		return
	end
	C_ChatInfo.SendAddonMessage(PREFIX, PROTO .. ":PING:", "WHISPER", me)
end

function Comm.RequestSync()
	Send("R:")
end
