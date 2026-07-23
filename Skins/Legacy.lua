-- HolyOrders skin: legacy
-- The classic look: dark tooltip backdrops with the stock grey border, stock
-- Blizzard buttons and close X, square icons, a wide class-coloured row bar
-- with a little round status ball, and a bare wide-row fly-out.

local HO = HolyOrders
local Skin = HO.Skin

local function Panel(frame)
	if not frame.SetBackdrop then
		return
	end
	frame:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 8, edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	frame:SetBackdropColor(0, 0, 0, 0.9)
	frame:SetBackdropBorderColor(1, 1, 1, 1)
end

Skin.Register("legacy", {
	palette = {
		gold = { 1.0, 0.82, 0.0 },
		goldBright = { 1.0, 0.82, 0.0 },
		goldDeep = { 0.4, 0.4, 0.4 },
		goldMuted = { 0.6, 0.6, 0.6 },
		panelBg = { 0.05, 0.05, 0.05 },
		bodyText = { 0.9, 0.9, 0.9 },
		helpText = { 0.6, 0.6, 0.6 },
		borderNeutral = { 0.55, 0.55, 0.55 },
		timerIdle = { 0.35, 0.95, 0.35 }, -- classic green countdown
	},
	Panel = Panel,
	-- Button/CloseButton nil: the stock Blizzard widgets ARE the look
	handle = "dot",
	wideBar = true,
	bareFlyout = true,
})
