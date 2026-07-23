-- HolyOrders skin: default
-- The addon's own look — dark rounded panels with a thin gold 9-slice border,
-- gold-chrome buttons and close X, rounded icons, the gem handle and the
-- decorative title gem + corner crest.

local HO = HolyOrders
local Skin = HO.Skin

local TCX = 24 / 1240 -- source corner width as a texcoord fraction of the art
local TCY = 24 / 364 -- source corner height as a texcoord fraction

-- paint the dark rounded panel + thin gold border onto `frame` as BACKGROUND
-- textures. Decorative only: fixed corners never distort, edges stretch on a
-- single axis, the flat interior stretches invisibly, and every piece anchors
-- to the frame's own corners — so the skin tracks whatever size the frame is
-- given and never drives that size.
local function Panel(frame, corner)
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

-- dark rounded frame + gold label from the bundled button art
local function Button(btn)
	btn:SetNormalTexture(Skin.tex.button)
	btn:SetPushedTexture(Skin.tex.buttonPush)
	btn:SetHighlightTexture(Skin.tex.buttonHi)
	Skin.StripCoords(btn:GetNormalTexture())
	Skin.StripCoords(btn:GetPushedTexture())
	Skin.StripCoords(btn:GetHighlightTexture())
	if btn:GetHighlightTexture() then
		btn:GetHighlightTexture():SetBlendMode("BLEND") -- a full frame, not an additive glow
	end
	local fs = btn:GetFontString()
	if fs then
		fs:SetTextColor(HO.Colors.rgb("goldBright"))
	end
end

-- gold X close button
local function CloseButton(btn)
	btn:SetNormalTexture(Skin.tex.close)
	btn:SetPushedTexture(Skin.tex.close)
	btn:SetHighlightTexture(Skin.tex.closeHi)
	Skin.StripCoords(btn:GetNormalTexture())
	Skin.StripCoords(btn:GetPushedTexture())
	Skin.StripCoords(btn:GetHighlightTexture())
	if btn:GetHighlightTexture() then
		btn:GetHighlightTexture():SetBlendMode("BLEND")
	end
end

Skin.Register("default", {
	-- palette: none — Colors.lua IS the default palette
	Panel = Panel,
	Button = Button,
	CloseButton = CloseButton,
	roundIcons = true,
	decorated = true,
	handle = "gem",
})
