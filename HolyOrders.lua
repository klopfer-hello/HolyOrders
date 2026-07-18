-- HolyOrders — paladin blessing coordination
-- Core loader: addon table, saved variables, event wiring.

local ADDON_NAME = ...

HolyOrders = HolyOrders or {}
local HO = HolyOrders

HO.VERSION = "0.1.0"

local DB_DEFAULTS = {
	options = {},
	plans = {}, -- stored blessing plans, keyed by roster signature
}

local eventFrame = CreateFrame("Frame")

local function OnAddonLoaded()
	HolyOrdersDB = HolyOrdersDB or {}
	for key, value in pairs(DB_DEFAULTS) do
		if HolyOrdersDB[key] == nil then
			HolyOrdersDB[key] = value
		end
	end
	HO.db = HolyOrdersDB
end

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
		self:UnregisterEvent("ADDON_LOADED")
		OnAddonLoaded()
	end
end)
