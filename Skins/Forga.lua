-- HolyOrders skin: forga
-- Flat modern dark-slate with thin muted borders and a slim status strip as
-- the bar handle. Colours only — no borrowed assets; built with the blessing
-- of the style's original author.

local HO = HolyOrders
local Skin = HO.Skin

Skin.Register("forga", {
	palette = {
		gold = { 0.55, 0.58, 0.62 },
		goldBright = { 0.85, 0.87, 0.90 },
		goldDeep = { 0.20, 0.22, 0.26 },
		goldMuted = { 0.45, 0.48, 0.52 },
		panelBg = { 0.08, 0.09, 0.11 },
		bodyText = { 0.82, 0.84, 0.86 },
		helpText = { 0.45, 0.48, 0.52 },
		borderNeutral = { 0.45, 0.45, 0.45 },
		btnNormal = { 0.11, 0.12, 0.15 },
		btnPushed = { 0.16, 0.18, 0.22 },
		btnHover = { 0.22, 0.26, 0.32 },
		handleRest = { 0.35, 0.40, 0.48 },
	},
	Panel = Skin.FlatPanel,
	Button = Skin.FlatButton,
	handle = "strip",
})
