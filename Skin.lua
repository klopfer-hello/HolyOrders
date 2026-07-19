-- HolyOrders — shared UI skin
-- The assignment window and the cast-bar fly-out share one look: a dark rounded
-- panel with a thin gold border, a gold seam under the title, and themed buttons.
-- Keeping the builders here (not copied per widget) means one tweak restyles every
-- panel at once. Colours come from HO.Colors.

local HO = HolyOrders
local Skin = {}
HO.Skin = Skin

local PATH = "Interface\\AddOns\\HolyOrders\\Icons\\"
Skin.tex = {
	bg = PATH .. "WindowBg",
	button = PATH .. "WindowButton",
	buttonHi = PATH .. "WindowButtonHi",
	buttonPush = PATH .. "WindowButtonPushed",
	close = PATH .. "WindowClose",
	closeHi = PATH .. "WindowCloseHi",
	gem = PATH .. "TitleGem",
	logo = PATH .. "Logo",
}

-- 9-slice geometry: the source corner (~24 px in the 1240x364 border texture)
-- drawn at CORNER px on screen
Skin.CORNER = 16
local TCX = 24 / 1240 -- source corner width as a texcoord fraction
local TCY = 24 / 364 -- source corner height as a texcoord fraction

-- paint the dark rounded panel + thin gold border onto `frame` as BACKGROUND
-- textures. Decorative only: fixed corners never distort, edges stretch on a
-- single axis, the flat interior stretches invisibly, and every piece anchors to
-- the frame's own corners — so the skin tracks whatever size the frame is given
-- and never drives that size.
function Skin.Panel(frame, corner)
	local C, tx, ty = corner or Skin.CORNER, TCX, TCY
	local function tex(l, r, t, b)
		local tg = frame:CreateTexture(nil, "BACKGROUND")
		tg:SetTexture(Skin.tex.bg)
		tg:SetTexCoord(l, r, t, b)
		return tg
	end
	local tl = tex(0, tx, 0, ty)
	tl:SetSize(C, C)
	tl:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	local tr = tex(1 - tx, 1, 0, ty)
	tr:SetSize(C, C)
	tr:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
	local bl = tex(0, tx, 1 - ty, 1)
	bl:SetSize(C, C)
	bl:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
	local br = tex(1 - tx, 1, 1 - ty, 1)
	br:SetSize(C, C)
	br:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
	local top = tex(tx, 1 - tx, 0, ty)
	top:SetPoint("TOPLEFT", tl, "TOPRIGHT")
	top:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT")
	local bottom = tex(tx, 1 - tx, 1 - ty, 1)
	bottom:SetPoint("TOPLEFT", bl, "TOPRIGHT")
	bottom:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
	local left = tex(0, tx, ty, 1 - ty)
	left:SetPoint("TOPLEFT", tl, "BOTTOMLEFT")
	left:SetPoint("BOTTOMRIGHT", bl, "TOPRIGHT")
	local right = tex(1 - tx, 1, ty, 1 - ty)
	right:SetPoint("TOPLEFT", tr, "BOTTOMLEFT")
	right:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
	local center = tex(tx, 1 - tx, ty, 1 - ty)
	center:SetPoint("TOPLEFT", tl, "BOTTOMRIGHT")
	center:SetPoint("BOTTOMRIGHT", br, "TOPLEFT")
end

-- a thin gold seam line across `frame` at vertical offset y (negative = below the
-- top edge), inset to clear the rounded corners
function Skin.Seam(frame, y)
	local seam = frame:CreateTexture(nil, "ARTWORK")
	seam:SetHeight(1)
	seam:SetPoint("TOPLEFT", frame, "TOPLEFT", Skin.CORNER, y)
	seam:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -Skin.CORNER, y)
	seam:SetColorTexture(HO.Colors.rgb("goldDeep", 0.8))
	return seam
end

-- template buttons carry their own SetTexCoord; reset it so our full-frame texture
-- fills the button instead of showing a sliced region
local function StripCoords(t)
	if t then
		t:SetTexCoord(0, 1, 0, 1)
	end
end
Skin.StripCoords = StripCoords

-- reskin a UIPanelButtonTemplate button: dark rounded frame + gold label
function Skin.Button(btn)
	btn:SetNormalTexture(Skin.tex.button)
	btn:SetPushedTexture(Skin.tex.buttonPush)
	btn:SetHighlightTexture(Skin.tex.buttonHi)
	StripCoords(btn:GetNormalTexture())
	StripCoords(btn:GetPushedTexture())
	StripCoords(btn:GetHighlightTexture())
	if btn:GetHighlightTexture() then
		btn:GetHighlightTexture():SetBlendMode("BLEND") -- our highlight is a full frame, not an additive glow
	end
	local fs = btn:GetFontString()
	if fs then
		fs:SetTextColor(HO.Colors.rgb("goldBright"))
	end
end

-- reskin a UIPanelCloseButton: gold X
function Skin.CloseButton(btn)
	btn:SetNormalTexture(Skin.tex.close)
	btn:SetPushedTexture(Skin.tex.close)
	btn:SetHighlightTexture(Skin.tex.closeHi)
	StripCoords(btn:GetNormalTexture())
	StripCoords(btn:GetPushedTexture())
	StripCoords(btn:GetHighlightTexture())
	if btn:GetHighlightTexture() then
		btn:GetHighlightTexture():SetBlendMode("BLEND")
	end
end
