-- HolyOrders skin: elvui
-- Not a lookalike: reads the RUNNING ElvUI installation's profile — backdrop,
-- border and value colors plus the general font — so HolyOrders matches
-- whatever the user's ElvUI actually looks like. Buttons are restyled through
-- ElvUI's own public skin API when present. Only selectable while ElvUI is
-- loaded; everything degrades to the flat painter family if its internals
-- ever change shape.

local HO = HolyOrders
local Skin = HO.Skin

local function Elv()
	local lib = _G.ElvUI
	return type(lib) == "table" and lib[1] or nil
end

local function General()
	local E = Elv()
	return E and E.db and E.db.general or nil
end

local function Scaled(c, f)
	return { math.min(c.r * f, 1), math.min(c.g * f, 1), math.min(c.b * f, 1) }
end

Skin.Register("elvui", {
	available = function()
		if Elv() then
			return true
		end
		return false, "ElvUI is not loaded"
	end,
	palette = function()
		local g = General()
		local bd = (g and g.backdropcolor) or { r = 0.058, g = 0.058, b = 0.058 }
		local border = (g and g.bordercolor) or { r = 0.30, g = 0.30, b = 0.30 }
		local value = (g and g.valuecolor) or { r = 0.99, g = 0.81, b = 0.25 }
		return {
			panelBg = { bd.r, bd.g, bd.b },
			goldDeep = { border.r, border.g, border.b },
			borderNeutral = { border.r, border.g, border.b },
			gold = Scaled(value, 0.85),
			goldBright = { value.r, value.g, value.b },
			goldMuted = Scaled(value, 0.6),
			bodyText = { 0.9, 0.9, 0.9 },
			helpText = { 0.55, 0.55, 0.55 },
			btnNormal = Scaled(bd, 1.8),
			btnPushed = Scaled(bd, 2.6),
			btnHover = Scaled(value, 0.45),
			handleRest = Scaled(border, 1.6),
		}
	end,
	font = function()
		local E = Elv()
		return E and E.media and E.media.normFont or nil
	end,
	Panel = Skin.FlatPanel,
	Button = function(btn)
		local E = Elv()
		local S = E and E.GetModule and E:GetModule("Skins", true)
		if S and S.HandleButton and pcall(S.HandleButton, S, btn) then
			return -- pixel-identical ElvUI button
		end
		Skin.FlatButton(btn)
	end,
	CloseButton = function(btn)
		local E = Elv()
		local S = E and E.GetModule and E:GetModule("Skins", true)
		if S and S.HandleCloseButton then
			pcall(S.HandleCloseButton, S, btn)
		end
	end,
	handle = "strip",
})
