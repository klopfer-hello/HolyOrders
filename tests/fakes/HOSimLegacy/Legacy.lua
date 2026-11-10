-- Stands in for a client that runs the older third-party blessing addon: it
-- only listens on that addon's message prefix and records what arrives. The
-- tests send its messages by hand (sim.raw_send).
HO_LEGACY = { rx = {} } -- { sender, channel, message }
local frame = CreateFrame("Frame")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:SetScript("OnEvent", function(_, _, prefix, message, channel, sender)
	if prefix == "PLPWR" then
		HO_LEGACY.rx[#HO_LEGACY.rx + 1] = { sender, channel, message }
	end
end)
C_ChatInfo.RegisterAddonMessagePrefix("PLPWR")
