-- HolyOrders skin: biker
-- Adventure-rally aesthetics: deep blue-black panels, rally-red titles, blue
-- seams and white body text — the classic tricolor livery of a big rally
-- travel enduro — plus a gold-rimmed spoked wheel as the bar handle that tints
-- with the overall status and spins while a force rebuff is running.

local HO = HolyOrders
local Skin = HO.Skin

Skin.Register("biker", {
	palette = {
		gold = { 0.92, 0.93, 0.95 }, -- rally white
		goldBright = { 0.90, 0.13, 0.18 }, -- rally red: titles, button labels
		goldDeep = { 0.22, 0.30, 0.54 }, -- rally blue: borders / seams
		goldMuted = { 0.62, 0.66, 0.74 },
		panelBg = { 0.045, 0.055, 0.095 }, -- blue-black fairing
		bodyText = { 0.92, 0.93, 0.95 },
		helpText = { 0.52, 0.56, 0.64 },
		borderNeutral = { 0.22, 0.30, 0.54 },
		btnNormal = { 0.08, 0.09, 0.14 },
		btnPushed = { 0.13, 0.15, 0.22 },
		btnHover = { 0.48, 0.10, 0.13 }, -- red glow
		handleRest = { 0.85, 0.66, 0.24 }, -- gold anodized rim at rest
	},
	Panel = Skin.FlatPanel,
	Button = Skin.FlatButton,
	handle = "wheel",
})
