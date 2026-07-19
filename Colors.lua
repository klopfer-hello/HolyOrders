-- HolyOrders — shared colour palette
-- One source of truth for the addon's theme (WoW RGB floats, 0..1). UI modules
-- reference HO.Colors instead of hard-coding magic RGB triples, so a palette
-- tweak lands everywhere at once.

local HO = HolyOrders

HO.Colors = {
	-- gold family: border, button text, seams
	gold = { 0.788, 0.635, 0.290 }, -- C9A24A  border / body accent
	goldBright = { 0.941, 0.831, 0.533 }, -- F0D488  hover / active highlight
	goldDeep = { 0.541, 0.435, 0.180 }, -- 8A6F2E  pushed / seam line
	goldMuted = { 0.561, 0.478, 0.306 }, -- 8F7A4E  subdued title text

	-- panel + text
	panelBg = { 0.078, 0.075, 0.067 }, -- 141311  window interior (use ~0.96 alpha)
	bodyText = { 0.867, 0.792, 0.627 }, -- DDCAA0  primary label text
	helpText = { 0.529, 0.463, 0.310 }, -- 87764F  hint / footnote text

	-- blue title gem
	gemHighlight = { 0.741, 0.933, 1.000 }, -- BDEEFF  specular
	gemLight = { 0.498, 0.831, 0.969 }, -- 7FD4F7  body
	gemDeep = { 0.122, 0.361, 0.588 }, -- 1F5C96  shadow

	-- live status (cast bar / requests)
	green = { 0.435, 0.878, 0.275 }, -- 6FE046  active / covered
	yellow = { 0.949, 0.788, 0.298 }, -- F2C94C  expiring / request
	red = { 0.910, 0.353, 0.243 }, -- E85A3E  missing
}

-- unpack a palette entry (+ optional alpha) for the SetVertexColor/SetTextColor
-- family: local r, g, b = HO.Colors.rgb("gold")
function HO.Colors.rgb(key, alpha)
	alpha = alpha or 1
	local c = HO.Colors[key]
	if not c then
		return 1, 1, 1, alpha
	end
	return c[1], c[2], c[3], alpha
end

-- palette entry as a 6-digit hex string for inline chat/fontstring colour escapes
-- (|cffRRGGBB...|r): HO.Colors.hex("green") -> "6fe046"
function HO.Colors.hex(key)
	local c = HO.Colors[key]
	if not c then
		return "ffffff"
	end
	return string.format("%02x%02x%02x", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end
