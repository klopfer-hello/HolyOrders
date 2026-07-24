-- HolyOrders skin: biker
-- Garage aesthetics: matte-black leather panels, chrome borders and titles,
-- signal-orange accents — and a motorcycle wheel as the bar handle that tints
-- with the overall status and spins while a force rebuff is running.

local HO = HolyOrders
local Skin = HO.Skin

Skin.Register("biker", {
	palette = {
		gold = { 0.62, 0.64, 0.67 }, -- chrome
		goldBright = { 1.00, 0.55, 0.15 }, -- signal orange: titles, button labels
		goldDeep = { 0.42, 0.44, 0.48 }, -- chrome borders / seams
		goldMuted = { 0.55, 0.55, 0.58 },
		panelBg = { 0.055, 0.05, 0.05 }, -- matte black leather
		bodyText = { 0.88, 0.88, 0.90 },
		helpText = { 0.52, 0.52, 0.55 },
		borderNeutral = { 0.42, 0.44, 0.48 },
		btnNormal = { 0.10, 0.095, 0.095 },
		btnPushed = { 0.16, 0.15, 0.15 },
		btnHover = { 0.45, 0.25, 0.08 }, -- warm orange glow
		handleRest = { 0.80, 0.82, 0.86 }, -- chrome wheel at rest
	},
	Panel = Skin.FlatPanel,
	Button = Skin.FlatButton,
	handle = "wheel",
})
