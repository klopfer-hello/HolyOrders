-- Test-only fakes for what the simulator does not provide (spells, spellbook,
-- items, auras, pets, party assignments), plus HO_TEST helpers the Python
-- tests call. Loaded before HolyOrders.
--
-- HO_FAKE.classic (set by the HOSimClassic addon, loaded first) switches the
-- fakes to the legacy global API, so HolyOrders takes its classic-client code
-- paths (spell tabs, UnitBuff, talent tabs) and Salvation and Light exist.

HO_FAKE = HO_FAKE or {}
HO_FAKE.buffs = {} -- [unit] = { { name =, duration =, expirationTime = }, ... }
HO_FAKE.pets = {} -- [petUnit] = { name =, class =, mana = }
HO_FAKE.symbols = 20 -- Symbol of Kings in the bags
HO_FAKE.outOfRange = {} -- [unit] = true

local CLASSIC = HO_FAKE.classic and true or false

-- id -> { name, level learned, classic only }
local SPELLS = {
	[19740] = { "Blessing of Might", 4 },
	[25782] = { "Greater Blessing of Might", 52 },
	[19742] = { "Blessing of Wisdom", 14 },
	[25894] = { "Greater Blessing of Wisdom", 54 },
	[20217] = { "Blessing of Kings", 20 },
	[25898] = { "Greater Blessing of Kings", 60 },
	[1038] = { "Blessing of Salvation", 26, true },
	[25895] = { "Greater Blessing of Salvation", 60, true },
	[19977] = { "Blessing of Light", 40, true },
	[25890] = { "Greater Blessing of Light", 60, true },
	[465] = { "Devotion Aura", 1 },
	[7294] = { "Retribution Aura", 16 },
	[19746] = { "Concentration Aura", 22 },
	[25780] = { "Righteous Fury", 16 },
}
local ORDER = { 19740, 25782, 19742, 25894, 20217, 25898, 1038, 25895, 19977, 25890, 465, 7294, 19746, 25780 }

local function SpellName(id)
	local s = SPELLS[id]
	-- a removed spell is unknown to the modern client altogether
	if s and (CLASSIC or not s[3]) then
		return s[1]
	end
end

local function Icon(id)
	return SPELLS[id] and (136000 + id % 1000) or nil
end

-- the player's spellbook: every paladin spell of their level
local function Book()
	local book = {}
	if select(2, UnitClass("player")) ~= "PALADIN" then
		return book
	end
	local level = UnitLevel("player") or 60
	for _, id in ipairs(ORDER) do
		local s = SPELLS[id]
		if level >= s[2] and (CLASSIC or not s[3]) then
			book[#book + 1] = id
		end
	end
	return book
end

local function Buffs(unit)
	return HO_FAKE.buffs[unit] or {}
end

if CLASSIC then
	BOOKTYPE_SPELL = "spell"
	function GetSpellInfo(id)
		local name = SpellName(id)
		if name then
			return name, nil, Icon(id)
		end
	end
	function GetNumSpellTabs() return 1 end
	function GetSpellTabInfo() return "Holy", nil, 0, #Book() end
	function GetSpellBookItemName(slot)
		local id = Book()[slot]
		if id then
			return SpellName(id), "Rank 1"
		end
	end
	function UnitBuff(unit, i)
		local b = Buffs(unit)[i]
		if b then
			return b.name, nil, nil, nil, b.duration, b.expirationTime
		end
	end
	function IsSpellInRange(_, unit) return HO_FAKE.outOfRange[unit] and 0 or 1 end
	function GetItemCount() return HO_FAKE.symbols end
	function GetNumTalentTabs() return 3 end
	function GetNumTalents() return 0 end
	function GetTalentInfo() return nil end
	-- inspecting: nobody is ever close enough, so no spec is inferred
	function CheckInteractDistance() return false end
	function CanInspect() return false end
else
	Enum = Enum or {}
	Enum.SpellBookSpellBank = Enum.SpellBookSpellBank or { Player = 0, Pet = 1 }
	C_SpellBook = C_SpellBook or {}
	function C_SpellBook.GetNumSpellBookSkillLines() return 1 end
	function C_SpellBook.GetSpellBookSkillLineInfo()
		return { itemIndexOffset = 0, numSpellBookItems = #Book() }
	end
	function C_SpellBook.GetSpellBookItemName(slot)
		local id = Book()[slot]
		if id then
			return SpellName(id), "Rank 1"
		end
	end
	C_Spell = C_Spell or {}
	function C_Spell.GetSpellInfo(id)
		local name = SpellName(id)
		if name then
			return { name = name, iconID = Icon(id), spellID = id }
		end
	end
	function C_Spell.GetSpellName(id) return SpellName(id) end
	function C_Spell.GetSpellTexture(id) return SpellName(id) and Icon(id) end
	function C_Spell.IsSpellInRange(_, unit) return not HO_FAKE.outOfRange[unit] end
	C_Item = C_Item or {}
	function C_Item.GetItemCount() return HO_FAKE.symbols end
	C_UnitAuras = C_UnitAuras or {}
	function C_UnitAuras.GetBuffDataByIndex(unit, i) return Buffs(unit)[i] end
end

MAX_PARTY_MEMBERS = MAX_PARTY_MEMBERS or 4
MAX_RAID_MEMBERS = MAX_RAID_MEMBERS or 40
SecureHandlerSetFrameRef = SecureHandlerSetFrameRef or function() end
UnitGroupRolesAssigned = UnitGroupRolesAssigned or function() return "NONE" end
function GetPartyAssignment() return false end

-- pets: the simulator has no pet units, so the unit functions the roster scan
-- uses answer for the units listed in HO_FAKE.pets
local function WrapUnit(fname, petValue)
	local orig = _G[fname]
	_G[fname] = function(unit, ...)
		local pet = type(unit) == "string" and HO_FAKE.pets[unit]
		if pet then
			return petValue(pet)
		end
		if orig then
			return orig(unit, ...)
		end
	end
end
WrapUnit("UnitExists", function() return true end)
WrapUnit("UnitName", function(pet) return pet.name end)
WrapUnit("UnitClass", function(pet) return pet.class, pet.class end)
WrapUnit("UnitLevel", function() return 60 end)
WrapUnit("UnitIsConnected", function() return true end)
WrapUnit("UnitIsDeadOrGhost", function() return false end)
WrapUnit("UnitIsVisible", function() return true end)
WrapUnit("UnitPowerType", function(pet) return pet.mana and 0 or 2 end)

-- helpers for the Python tests ---------------------------------------------------

HO_TEST = { chat = {}, sys = {} }

do
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("CHAT_MSG_SYSTEM")
	frame:SetScript("OnEvent", function(_, _, text) HO_TEST.sys[#HO_TEST.sys + 1] = text end)
	local orig = DEFAULT_CHAT_FRAME.AddMessage
	DEFAULT_CHAT_FRAME.AddMessage = function(self, msg, ...)
		HO_TEST.chat[#HO_TEST.chat + 1] = tostring(msg)
		if orig then
			return orig(self, msg, ...)
		end
	end
end

local function SortedKeys(t)
	local keys = {}
	for k in pairs(t or {}) do
		keys[#keys + 1] = k
	end
	table.sort(keys)
	return keys
end

-- the whole active plan as one canonical string (no revisions): equal strings
-- on two clients mean they show the same assignments
function HO_TEST.State()
	local plan = HolyOrders.Plan.Active()
	local out = {}
	for _, owner in ipairs(SortedKeys(plan.class)) do
		for _, class in ipairs(SortedKeys(plan.class[owner])) do
			local a = plan.class[owner][class]
			if a.id then -- explicit-none markers are local-only
				out[#out + 1] = "C " .. owner .. " " .. class .. " " .. a.id .. " " .. (a.mode or "auto")
			end
		end
	end
	for _, owner in ipairs(SortedKeys(plan.player)) do
		for _, target in ipairs(SortedKeys(plan.player[owner])) do
			out[#out + 1] = "P " .. owner .. " " .. target .. " " .. plan.player[owner][target]
		end
	end
	for _, name in ipairs(SortedKeys(plan.tanks)) do
		out[#out + 1] = "T " .. name .. " " .. tostring(plan.tanks[name])
	end
	for _, owner in ipairs(SortedKeys(plan.aura)) do
		out[#out + 1] = "A " .. owner .. " " .. plan.aura[owner]
	end
	return table.concat(out, "\n")
end

function HO_TEST.Peers()
	return SortedKeys(HolyOrders.Comm.peers)
end

function HO_TEST.Roster()
	local names = {}
	for _, entry in ipairs(HolyOrders.Roster.units) do
		names[#names + 1] = (entry.isPet and "pet:" or "") .. entry.name
	end
	table.sort(names)
	return names
end

-- cast tasks of the engine: [classToken] = "spell>target" ("-" = nothing to cast)
function HO_TEST.Tasks()
	HolyOrders.Engine.Update()
	local out = {}
	for class, task in pairs(HolyOrders.Engine.tasks) do
		out[class] = (task.spellName or "-") .. ">" .. (task.unitName or "-")
	end
	return out
end
