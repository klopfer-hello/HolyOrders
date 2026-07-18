-- HolyOrders — paladin blessing coordination
-- Core: addon namespace, saved variables, event dispatch, slash commands.

local ADDON_NAME = ...

HolyOrders = HolyOrders or {}
local HO = HolyOrders

HO.VERSION = "0.1.0"

local DB_DEFAULTS = {
	options = {},
	plans = {},     -- stored blessing plans, keyed by roster signature
	prefs = {},     -- class/spec blessing preferences
	specCache = {}, -- per-character spec tags
}

-- event dispatch -------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local eventHandlers = {}

function HO.RegisterEvent(event, handler)
	if not eventHandlers[event] then
		eventHandlers[event] = {}
		eventFrame:RegisterEvent(event)
	end
	table.insert(eventHandlers[event], handler)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
	for _, handler in ipairs(eventHandlers[event]) do
		handler(...)
	end
end)

-- lifecycle ------------------------------------------------------------------

HO.RegisterEvent("ADDON_LOADED", function(name)
	if name ~= ADDON_NAME then
		return
	end
	HolyOrdersDB = HolyOrdersDB or {}
	for key, value in pairs(DB_DEFAULTS) do
		if HolyOrdersDB[key] == nil then
			HolyOrdersDB[key] = value
		end
	end
	HO.db = HolyOrdersDB
end)

HO.RegisterEvent("PLAYER_LOGIN", function()
	HO.Data.Refresh()
	HO.Talents.Scan()
	HO.Roster.Queue()
end)

-- output ---------------------------------------------------------------------

function HO.Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cfff0c817HolyOrders|r: " .. tostring(msg))
end

function HO.PrintLine(msg)
	DEFAULT_CHAT_FRAME:AddMessage("  " .. tostring(msg))
end

-- helpers --------------------------------------------------------------------

-- realm-qualified unit name ("Name-Realm"), used for roster signatures
function HO.FullName(unit)
	local name, realm = UnitName(unit)
	if not name then
		return nil
	end
	if realm and realm ~= "" then
		return name .. "-" .. realm
	end
	return name .. "-" .. (GetNormalizedRealmName() or "")
end

-- slash commands -------------------------------------------------------------

local commands = {}
HO.commands = commands

SLASH_HOLYORDERS1 = "/holyorders"
SLASH_HOLYORDERS2 = "/ho"
SlashCmdList["HOLYORDERS"] = function(input)
	input = (input or ""):gsub("^%s+", ""):gsub("%s+$", "")
	local cmd, rest = input:match("^(%S+)%s*(.*)$")
	cmd = cmd and cmd:lower() or ""
	if commands[cmd] then
		commands[cmd](rest)
	else
		HO.Print("v" .. HO.VERSION .. " — commands:")
		local names = {}
		for name in pairs(commands) do
			table.insert(names, name)
		end
		table.sort(names)
		for _, name in ipairs(names) do
			HO.PrintLine("/ho " .. name)
		end
	end
end
