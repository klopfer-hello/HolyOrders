-- HolyOrders — assignment window
-- Class grid: rows are classes (expandable to members), columns are paladins.
-- Left-click a cell cycles blessings, right-click clears, shift-click cycles
-- the cast mode. Member rows carry per-member overrides, tank flag and spec
-- tag. Everything edits the active plan; no secure frames involved.

local HO = HolyOrders
local Window = {}
HO.Window = Window
local L = HO.L

local NAME_W = 175
local COL_W = 34
local COL_GAP = 4
local HEADER_H = 30
local ROW_H = 30
local MEMBER_ROW_H = 28
local PAD = 8
local MAX_COLS = 8
local LABEL_INDENT = 14 -- member-row label indent (rows themselves stay aligned)
local HEADER_MAX_CHARS = 5
local MAX_WIN_H = 700 -- height clamp; taller rosters scroll via the mouse wheel
local BOTTOM_PAD = 38 -- reserved space under the last row for the hint lines
local FIRST_ROW_OFFSET = 20 -- gap between the column headers and the first row
local ICON_SIZE = 24 -- cell icon size (rows grow with it so icons don't overflow)

local CLASS_ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
-- cast-mode tag shown on a cell: A auto, G great (greater), S small (10-min
-- single). Distinct bright colours + an outlined font read on any blessing icon.
local MODE_TAG = { auto = "|cff40c0ffA|r", greater = "|cffffd100G|r", normal = "|cff40ff40S|r" }
local EMPTY_SLOT = "Interface\\PaperDoll\\UI-Backpack-EmptySlot"
local NONE_ICON = "Interface\\Buttons\\UI-GroupLoot-Pass-Up" -- explicit-none marker (matches the bar)
-- rounded-cell textures (mirrors the cast bar): a corner mask and a tintable
-- frame ring (bundled TGA, referenced without extension)
local WIN_BTN_MASK = "Interface\\AddOns\\HolyOrders\\Icons\\ButtonMask"
local WIN_BTN_FRAME = "Interface\\AddOns\\HolyOrders\\Icons\\ButtonFrame"

-- window skin: a dark rounded panel with a thin gold border. The border texture is
-- 9-sliced (fixed corners, single-axis edge stretch, flat interior) so it never
-- distorts at any window size — and, crucially, the skin only READS the window's
-- corners; Window.Refresh's win:SetSize stays the sole authority on the size.
local SKIN_BG = "Interface\\AddOns\\HolyOrders\\Icons\\WindowBg"
local SKIN_BTN = "Interface\\AddOns\\HolyOrders\\Icons\\WindowButton"
local SKIN_BTN_HI = "Interface\\AddOns\\HolyOrders\\Icons\\WindowButtonHi"
local SKIN_BTN_PUSH = "Interface\\AddOns\\HolyOrders\\Icons\\WindowButtonPushed"
local SKIN_CLOSE = "Interface\\AddOns\\HolyOrders\\Icons\\WindowClose"
local SKIN_CLOSE_HI = "Interface\\AddOns\\HolyOrders\\Icons\\WindowCloseHi"
local SKIN_GEM = "Interface\\AddOns\\HolyOrders\\Icons\\TitleGem"
local SKIN_BRAND = "Interface\\AddOns\\HolyOrders\\Icons\\Logo"
local SKIN_CORNER = 16 -- corner piece drawn at this many pixels (never stretched)
local SKIN_TCX = 24 / 1240 -- source corner width as a texcoord fraction (1240 px wide)
local SKIN_TCY = 24 / 364 -- source corner height as a texcoord fraction (364 px tall)

local win
local expanded = {} -- [classToken] = true
local classRows, memberRows = {}, {}
local auraRow -- single "Aura" strip: each paladin column's assigned aura
local scrollOffset = 0 -- pixels scrolled down; clamped in Window.Refresh

-- helpers ---------------------------------------------------------------------

-- truncate to at most maxChars whole UTF-8 characters; :sub on a byte count
-- can split a multi-byte glyph (German names) and print garbage
local function Utf8Truncate(str, maxChars)
	local chars, i, n = 0, 1, #str
	while i <= n and chars < maxChars do
		local b = str:byte(i)
		local size = 1
		if b >= 0xF0 then
			size = 4
		elseif b >= 0xE0 then
			size = 3
		elseif b >= 0xC0 then
			size = 2
		end
		i = i + size
		chars = chars + 1
	end
	return str:sub(1, i - 1)
end

local function BlessingName(id)
	local blessing = HO.Data.blessings[id]
	return blessing and (blessing.name or blessing.key) or tostring(id)
end

-- next assignable blessing for a class cell (0 = none); eligibility filtered,
-- availability best-effort (exact for the player, permissive for remotes)
local function CycleClassBlessing(pally, classToken, current, delta)
	delta = delta or 1
	local id = current or 0
	for _ = 1, HO.Data.NUM_BLESSINGS + 1 do
		id = (id + delta) % (HO.Data.NUM_BLESSINGS + 1)
		if id == 0 then
			return 0
		end
		if HO.Data.IsEligible(classToken, id, false) and HO.Planner.IsAvailable(pally, id) then
			return id
		end
	end
	return 0
end

-- wheel-cycling from the cast bar: edits the player's own row, which syncs
-- to the group and refreshes the window like any other edit
function Window.CycleMyClass(classToken, delta)
	local me = HO.FullName("player")
	if not me then
		return
	end
	local plan = HO.Plan.Active()
	local cur = plan.class[me] and plan.class[me][classToken]
	-- ring: each castable blessing, then NONE (a visible, re-assignable placeholder),
	-- then back to the first blessing. A none marker starts the cycle at 0 (like an
	-- unassigned class), so wheel-up lands on the first blessing and wheel-down on
	-- the last. This ring NEVER produces the true-clear state — that stays a
	-- right-click in the assignment window.
	local nextID = CycleClassBlessing(me, classToken, cur and cur.id or 0, delta)
	if nextID == 0 then
		HO.Plan.SetClassNone(me, classToken)
	else
		HO.Plan.SetClassAssignment(me, classToken, nextID, cur and cur.mode or nil)
	end
	-- RefreshAll is declared later in this file and not in scope here
	Window.Refresh()
	HO.Bar.Refresh()
end

-- overrides may force anything castable (eligibility intentionally bypassed)
local function CycleOverrideBlessing(pally, current)
	local id = current or 0
	for _ = 1, HO.Data.NUM_BLESSINGS + 1 do
		id = (id + 1) % (HO.Data.NUM_BLESSINGS + 1)
		if id == 0 then
			return 0
		end
		if HO.Planner.IsAvailable(pally, id) then
			return id
		end
	end
	return 0
end

local function RefreshAll()
	Window.Refresh()
	HO.Bar.Refresh()
end

-- classes currently present in the roster (a class button/row is shown for each);
-- pets count under their owner's class, matching the class-row presence rule
local function PresentClasses()
	local set = {}
	for _, entry in ipairs(HO.Roster.units) do
		if entry.name then
			local class = entry.class
			if entry.isPet then
				local owner = entry.owner and HO.Roster.byName[entry.owner]
				class = (owner and owner.class) or class
			end
			if class then
				set[class] = true
			end
		end
	end
	return set
end

-- one button toggles every class open/closed: if any present class is collapsed,
-- expand them all; otherwise collapse everything
local function ToggleExpandAll()
	local present = PresentClasses()
	local anyCollapsed = false
	for class in pairs(present) do
		if not expanded[class] then
			anyCollapsed = true
			break
		end
	end
	if anyCollapsed then
		for class in pairs(present) do
			expanded[class] = true
		end
	else
		wipe(expanded)
	end
	Window.Refresh()
end

-- cell click handlers ---------------------------------------------------------

local function MayEdit(pally)
	local editor = HO.FullName("player")
	if HO.Comm and editor and not HO.Comm.CanEdit(editor, pally) then
		HO.Print("no permission to edit " .. pally .. "'s assignments (need lead/assist or their open-edit)")
		return false
	end
	return true
end

local function ClassCellClick(cell, mouseBtn)
	if not MayEdit(cell.pally) then
		return
	end
	local plan = HO.Plan.Active()
	local cur = plan.class[cell.pally] and plan.class[cell.pally][cell.classToken]
	if mouseBtn == "RightButton" then
		HO.Plan.SetClassAssignment(cell.pally, cell.classToken, 0)
	elseif IsShiftKeyDown() then
		-- a none marker has no id/mode to cycle; leave it (wheel or a left-click
		-- re-assigns it to a real blessing first)
		if cur and cur.id then
			local nextMode = (cur.mode == "auto" and "greater") or (cur.mode == "greater" and "normal") or "auto"
			HO.Plan.SetClassAssignment(cell.pally, cell.classToken, cur.id, nextMode)
		end
	else
		local nextID = CycleClassBlessing(cell.pally, cell.classToken, cur and cur.id or 0)
		HO.Plan.SetClassAssignment(cell.pally, cell.classToken, nextID, cur and cur.mode or nil)
	end
	RefreshAll()
end

local function MemberCellClick(cell, mouseBtn)
	if not MayEdit(cell.pally) then
		return
	end
	local plan = HO.Plan.Active()
	local cur = plan.player[cell.pally] and plan.player[cell.pally][cell.memberName]
	-- pets are excluded from likings: a pet blessing choice is an option, not a
	-- member wish, so it is never recorded as a persistent preference
	local rosterEntry = HO.Roster.byName[cell.memberName]
	local isPet = rosterEntry and rosterEntry.isPet
	if mouseBtn == "RightButton" then
		HO.Plan.SetPlayerOverride(cell.pally, cell.memberName, 0)
		if not isPet then
			HO.Plan.SetMemberPref(cell.memberName, nil) -- clearing the override forgets the liking
		end
	else
		local newID = CycleOverrideBlessing(cell.pally, cur)
		HO.Plan.SetPlayerOverride(cell.pally, cell.memberName, newID)
		if not isPet then
			-- a manual override records the member's liking (0 = cycled to none = forget)
			HO.Plan.SetMemberPref(cell.memberName, newID ~= 0 and newID or nil)
		end
	end
	RefreshAll()
end

local function CellTooltip(cell)
	GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
	if cell.memberName then
		GameTooltip:SetText(cell.memberName)
		local plan = HO.Plan.Active()
		local cur = plan.player[cell.pally] and plan.player[cell.pally][cell.memberName]
		GameTooltip:AddLine(string.format(L["override by %s: %s"], cell.pally, cur and BlessingName(cur) or L["none"]), 1, 1, 1)
		if not cur and cell.inheritedID then
			GameTooltip:AddLine(string.format(L["inherited from class assignment: %s"], BlessingName(cell.inheritedID)), 0.7, 0.7, 0.7)
		end
		-- remembered liking (pets never have one)
		local rosterEntry = HO.Roster.byName[cell.memberName]
		if not (rosterEntry and rosterEntry.isPet) then
			local pref = HO.Plan.MemberPref(cell.memberName)
			if pref then
				GameTooltip:AddLine(string.format(L["remembered preference: %s"], BlessingName(pref)), 0.6, 0.8, 1)
			end
		end
		-- a buff this member requested for themselves (yellow, like the cast bar)
		local req = HO.Comm and HO.Comm.requests[cell.memberName]
		if req then
			GameTooltip:AddLine(string.format(L["requested: %s"], BlessingName(req)), 0.95, 0.85, 0.15)
		end
		GameTooltip:AddLine(L["click: next blessing — right-click: clear"], 0.8, 0.8, 0.8)
	else
		GameTooltip:SetText(cell.classToken)
		local plan = HO.Plan.Active()
		local cur = plan.class[cell.pally] and plan.class[cell.pally][cell.classToken]
		if cur and cur.none then
			GameTooltip:AddLine(L["no blessing assigned"], 1, 1, 1)
		elseif cur then
			GameTooltip:AddLine(cell.pally .. ": " .. BlessingName(cur.id), 1, 1, 1)
			local n = cell.memberCount or 0
			local min = HO.db.options.greaterMin or 2
			if cur.mode == "auto" then
				-- the engine decides greater vs singles from eligible castable
				-- members, symbol count and greater-known; prefer its verdict
				-- when available, else fall back to the raw member-count heuristic
				local useGreater
				if HO.Engine and HO.Engine.WouldUseGreater then
					useGreater = HO.Engine.WouldUseGreater(cell.classToken)
				end
				if useGreater == nil then
					useGreater = (n >= min)
				end
				local effective = useGreater
					and L["greater (30 min, whole class, 1 Symbol of Kings)"]
					or L["10-min singles (too few members for greater)"]
				GameTooltip:AddLine(string.format(L["mode: auto — greater from %d+ members, singles otherwise"], min), 0.9, 0.9, 0.9, true)
				GameTooltip:AddLine(string.format(L["with %d member(s) now: %s"], n, effective), 0.6, 1, 0.6, true)
			elseif cur.mode == "greater" then
				GameTooltip:AddLine(L["mode: greater — always the Greater Blessing: 30 min, hits the whole class, costs a Symbol of Kings per cast"], 0.9, 0.9, 0.9, true)
			else
				GameTooltip:AddLine(L["mode: normal — always 10-min single blessings on each member, no reagent"], 0.9, 0.9, 0.9, true)
			end
		else
			GameTooltip:AddLine(cell.pally .. ": " .. L["no assignment"], 1, 1, 1)
		end
		GameTooltip:AddLine(L["click: next blessing — right-click: clear"], 0.8, 0.8, 0.8)
		GameTooltip:AddLine(L["shift-click: change the cast mode"], 0.8, 0.8, 0.8)
	end
	GameTooltip:Show()
end

-- widget construction ---------------------------------------------------------

local function CreateCell(parent)
	local cell = CreateFrame("Button", nil, parent)
	cell:SetSize(COL_W - COL_GAP, ROW_H - 4)
	cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	cell.bg = cell:CreateTexture(nil, "BACKGROUND")
	cell.bg:SetAllPoints()
	cell.bg:SetColorTexture(1, 1, 1, 0.06)
	cell.icon = cell:CreateTexture(nil, "ARTWORK")
	cell.icon:SetPoint("CENTER")
	cell.icon:SetSize(ICON_SIZE, ICON_SIZE)
	cell.icon:SetMask(WIN_BTN_MASK) -- rounded icon corners
	-- static neutral rounded frame around the icon; the window is an editor, so
	-- there is no green/red status colour on cells (mirrors the bar's neutral gold)
	cell.frame = cell:CreateTexture(nil, "OVERLAY", nil, 1)
	cell.frame:SetPoint("TOPLEFT", cell.icon, "TOPLEFT", -1, 1)
	cell.frame:SetPoint("BOTTOMRIGHT", cell.icon, "BOTTOMRIGHT", 1, -1)
	cell.frame:SetTexture(WIN_BTN_FRAME)
	cell.frame:SetVertexColor(0.5, 0.42, 0.22, 0.7)
	cell.mode = cell:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	-- nudged out toward the bottom-right corner so the big letter clears the icon
	cell.mode:SetPoint("BOTTOMRIGHT", 4, -4)
	cell.mode:SetDrawLayer("OVERLAY", 5) -- above the icon and frame
	local mf, ms = cell.mode:GetFont()
	cell.mode:SetFont(mf, (ms or 12) + 3, "THICKOUTLINE") -- larger, outlined for contrast
	cell:SetScript("OnEnter", CellTooltip)
	cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
	cell.hoCell = true -- marks our cells for the tooltip re-render check
	return cell
end

local function AcquireRow(pool, index, height, labelIndent)
	labelIndent = labelIndent or 0
	local row = pool[index]
	if not row then
		row = CreateFrame("Frame", nil, win)
		row:SetHeight(height)
		row.cells = {}
		row.label = CreateFrame("Button", nil, row)
		-- indent the label only (not the row), so cells stay aligned with the
		-- class-row cells and the column headers
		row.label:SetPoint("LEFT", 4 + labelIndent, 0)
		row.label:SetSize(NAME_W - 8 - labelIndent, height)
		row.label.text = row.label:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		row.label.text:SetPoint("LEFT", 2, 0)
		row.label.text:SetJustifyH("LEFT")
		pool[index] = row
	end
	row:SetHeight(height)
	return row
end

local function RowCell(row, colIndex, clickHandler)
	local cell = row.cells[colIndex]
	if not cell then
		cell = CreateCell(row)
		cell:SetPoint("LEFT", row, "LEFT", NAME_W + (colIndex - 1) * COL_W, 0)
		row.cells[colIndex] = cell
	end
	cell:SetScript("OnClick", clickHandler)
	return cell
end

-- aura strip ------------------------------------------------------------------

-- ring of aura choices for a paladin: my own column offers only auras I know
-- (matching the bar); assigning for another paladin offers every aura (their
-- known set is not synced). None (0) always closes the ring.
local function AuraRing(pally)
	local me = HO.FullName("player")
	local ring
	if pally == me then
		ring = HO.Data.KnownAuras()
	else
		ring = {}
		for id = 1, HO.Data.NUM_AURAS do
			ring[id] = id
		end
	end
	ring[#ring + 1] = 0
	return ring
end

local function NextAura(pally, delta)
	local ring = AuraRing(pally)
	local cur = HO.Plan.GetAura(pally) or 0
	local idx = #ring -- default to the none slot (also covers an unknown current aura)
	for i, id in ipairs(ring) do
		if id == cur then
			idx = i
			break
		end
	end
	local nextIdx = ((idx - 1 + (delta or 1)) % #ring) + 1
	return ring[nextIdx]
end

local function AuraCellClick(cell, mouseBtn)
	if not MayEdit(cell.pally) then
		return
	end
	if mouseBtn == "RightButton" then
		HO.Plan.SetAura(cell.pally, 0)
	else
		HO.Plan.SetAura(cell.pally, NextAura(cell.pally, 1))
	end
	RefreshAll()
end

local function AuraCellTooltip(cell)
	GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
	GameTooltip:SetText(cell.pally)
	local id = HO.Plan.GetAura(cell.pally)
	local name = id and HO.Data.AuraName(id)
	GameTooltip:AddLine(string.format(L["aura: %s"], name or L["none"]), 1, 1, 1)
	GameTooltip:AddLine(L["click: next aura — right-click: clear"], 0.8, 0.8, 0.8)
	GameTooltip:Show()
end

local function AuraRowCell(row, colIndex)
	local cell = row.cells[colIndex]
	if not cell then
		cell = CreateFrame("Button", nil, row)
		cell:SetSize(COL_W - COL_GAP, ROW_H - 4)
		cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		cell.bg = cell:CreateTexture(nil, "BACKGROUND")
		cell.bg:SetAllPoints()
		cell.bg:SetColorTexture(0.20, 0.20, 0.55, 0.20) -- blue tint marks the aura strip
		cell.icon = cell:CreateTexture(nil, "ARTWORK")
		cell.icon:SetPoint("CENTER")
		cell.icon:SetSize(ICON_SIZE, ICON_SIZE)
		cell.icon:SetMask(WIN_BTN_MASK) -- rounded icon corners
		-- static neutral rounded frame around the icon (editor: no status colour)
		cell.frame = cell:CreateTexture(nil, "OVERLAY", nil, 1)
		cell.frame:SetPoint("TOPLEFT", cell.icon, "TOPLEFT", -1, 1)
		cell.frame:SetPoint("BOTTOMRIGHT", cell.icon, "BOTTOMRIGHT", 1, -1)
		cell.frame:SetTexture(WIN_BTN_FRAME)
		cell.frame:SetVertexColor(0.5, 0.42, 0.22, 0.7)
		cell:SetScript("OnEnter", AuraCellTooltip)
		cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
		cell:SetScript("OnClick", AuraCellClick)
		cell.hoCell = true -- re-render an open tooltip after a refresh
		cell:SetPoint("LEFT", row, "LEFT", NAME_W + (colIndex - 1) * COL_W, 0)
		row.cells[colIndex] = cell
	end
	return cell
end

local function AcquireAuraRow()
	if not auraRow then
		local row = CreateFrame("Frame", nil, win)
		row:SetHeight(ROW_H)
		row.cells = {}
		row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		row.label:SetPoint("LEFT", 6, 0)
		row.label:SetJustifyH("LEFT")
		row.label:SetText(L["Aura"])
		auraRow = row
	end
	return auraRow
end

-- user-configurable UI scale for the assignment window. Non-secure, so it is
-- safe to apply any time (unlike the cast bar).
function Window.ApplyScale()
	if win then
		win:SetScale((HO.db.options.window and HO.db.options.window.scale) or 1)
	end
end

-- the window position persists in SavedVariables so it opens where the user left
-- it, not always re-centered. The client re-anchors a dragged frame to the
-- nearest corner, so the full anchor is saved (point + relPoint + offsets).
local function SaveWindowPos()
	if not win then
		return
	end
	local point, _, relPoint, x, y = win:GetPoint()
	HO.db.options.window = HO.db.options.window or {}
	HO.db.options.window.pos = { point = point, relPoint = relPoint, x = x, y = y }
end

local function RestoreWindowPos()
	local pos = HO.db.options.window and HO.db.options.window.pos
	win:ClearAllPoints()
	if pos and pos.point then
		win:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
	else
		win:SetPoint("CENTER")
	end
end

-- build the 9-sliced gold border + dark interior as BACKGROUND textures on the
-- window. Corners are a fixed SKIN_CORNER square (no stretch = no distortion);
-- edges stretch on one axis; the flat interior stretches invisibly. Every piece
-- anchors to the window's own corners, so it tracks the size Refresh sets without
-- ever driving it.
local function BuildWindowSkin(f)
	local C, tx, ty = SKIN_CORNER, SKIN_TCX, SKIN_TCY
	local function tex(l, r, t, b)
		local tg = f:CreateTexture(nil, "BACKGROUND")
		tg:SetTexture(SKIN_BG)
		tg:SetTexCoord(l, r, t, b)
		return tg
	end
	local tl = tex(0, tx, 0, ty)
	tl:SetSize(C, C)
	tl:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	local tr = tex(1 - tx, 1, 0, ty)
	tr:SetSize(C, C)
	tr:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
	local bl = tex(0, tx, 1 - ty, 1)
	bl:SetSize(C, C)
	bl:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
	local br = tex(1 - tx, 1, 1 - ty, 1)
	br:SetSize(C, C)
	br:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
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

-- template buttons carry their own SetTexCoord; reset it so our full-frame texture
-- fills the button instead of showing a sliced region
local function StripCoords(t)
	if t then
		t:SetTexCoord(0, 1, 0, 1)
	end
end

-- reskin a UIPanelButtonTemplate button: dark rounded frame + gold label
local function SkinButton(btn)
	btn:SetNormalTexture(SKIN_BTN)
	btn:SetPushedTexture(SKIN_BTN_PUSH)
	btn:SetHighlightTexture(SKIN_BTN_HI)
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

function Window.Create()
	if win then
		return
	end
	win = CreateFrame("Frame", "HolyOrdersWindow", UIParent)
	-- MEDIUM (standard panel strata) so higher-priority windows like the calendar
	-- draw cleanly OVER us instead of interleaving/bleeding through at HIGH
	win:SetFrameStrata("MEDIUM")
	win:SetMovable(true)
	win:SetClampedToScreen(true)
	win:EnableMouse(true)
	win:EnableMouseWheel(true)
	win:SetScript("OnMouseWheel", function(_, delta)
		-- wheel scrolls whole rows; cell/label child buttons don't register the
		-- wheel, so the event propagates up here. Refresh re-clamps the offset.
		scrollOffset = scrollOffset - delta * 3 * ROW_H
		if scrollOffset < 0 then
			scrollOffset = 0
		end
		Window.Refresh()
	end)
	RestoreWindowPos() -- open where the user left it (persisted), else centered
	win:Hide()
	table.insert(UISpecialFrames, "HolyOrdersWindow")

	BuildWindowSkin(win) -- dark rounded panel + thin gold border (decorative; tracks size)

	-- addon crest in the bottom-right, seated just above the hint line. It draws on
	-- ARTWORK, so every row/cell/header/hint renders over it: in a full roster the
	-- grid covers it, in a small one it shows as an emblem in the empty area.
	win.brand = win:CreateTexture(nil, "ARTWORK")
	win.brand:SetSize(64, 64)
	win.brand:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -12, BOTTOM_PAD + 2)
	win.brand:SetTexture(SKIN_BRAND)
	win.brand:SetAlpha(0.9)

	win.header = CreateFrame("Frame", nil, win)
	win.header:SetPoint("TOPLEFT")
	win.header:SetPoint("TOPRIGHT")
	win.header:SetHeight(HEADER_H)
	win.header:EnableMouse(true)
	win.header:RegisterForDrag("LeftButton")
	win.header:SetScript("OnDragStart", function() win:StartMoving() end)
	win.header:SetScript("OnDragStop", function()
		win:StopMovingOrSizing()
		SaveWindowPos()
	end)
	-- blue title gem, then the title text, then a gold seam under the header row
	win.header.gem = win.header:CreateTexture(nil, "ARTWORK")
	win.header.gem:SetSize(18, 18)
	win.header.gem:SetPoint("LEFT", 8, 0)
	win.header.gem:SetTexture(SKIN_GEM)
	win.header.title = win.header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	win.header.title:SetPoint("LEFT", win.header.gem, "RIGHT", 6, 0)
	win.header.title:SetText(L["HolyOrders — Assignments"])
	win.header.title:SetTextColor(HO.Colors.rgb("goldBright"))
	win.seam = win:CreateTexture(nil, "ARTWORK")
	win.seam:SetHeight(1)
	win.seam:SetPoint("TOPLEFT", win, "TOPLEFT", SKIN_CORNER, -HEADER_H)
	win.seam:SetPoint("TOPRIGHT", win, "TOPRIGHT", -SKIN_CORNER, -HEADER_H)
	win.seam:SetColorTexture(HO.Colors.rgb("goldDeep", 0.8))

	-- expand/collapse-all toggle: sits in the header row, just left of the
	-- No Salv button (anchored below, once that button exists)
	win.expandBtn = CreateFrame("Button", nil, win.header, "UIPanelButtonTemplate")
	win.expandBtn:SetSize(24, 20)
	win.expandBtn:SetText("+")
	SkinButton(win.expandBtn)
	win.expandBtn:SetScript("OnClick", ToggleExpandAll)
	win.expandBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(L["expand or collapse all classes"], 1, 1, 1)
		GameTooltip:Show()
	end)
	win.expandBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

	-- parent the close button to the window, not the header: the template's
	-- default OnClick hides its PARENT, which used to hide only the title bar
	local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", win, "TOPRIGHT", -4, -4)
	close:SetSize(22, 22)
	close:SetFrameLevel(win.header:GetFrameLevel() + 1)
	close:SetNormalTexture(SKIN_CLOSE)
	close:SetPushedTexture(SKIN_CLOSE)
	close:SetHighlightTexture(SKIN_CLOSE_HI)
	StripCoords(close:GetNormalTexture())
	StripCoords(close:GetPushedTexture())
	StripCoords(close:GetHighlightTexture())
	if close:GetHighlightTexture() then
		close:GetHighlightTexture():SetBlendMode("BLEND")
	end
	close:SetScript("OnClick", function()
		win:Hide()
	end)

	local function HeaderButton(text, offsetX, onClick, tooltip)
		local btn = CreateFrame("Button", nil, win.header, "UIPanelButtonTemplate")
		btn:SetSize(60, 20)
		btn:SetPoint("RIGHT", win.header, "RIGHT", offsetX, 0)
		btn:SetText(text)
		SkinButton(btn)
		btn:SetScript("OnClick", onClick)
		btn:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(tooltip, 1, 1, 1)
			GameTooltip:Show()
		end)
		btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
		return btn
	end

	HeaderButton("Auto", -30, function()
		local ok, msg = HO.Planner.Run()
		HO.Print(ok and ("auto-plan: " .. msg) or ("auto-plan failed: " .. msg))
		RefreshAll()
	end, L["Run the deterministic auto-planner"])
	HeaderButton("Rebuff", -94, function()
		HO.Bar.ToggleForceRebuff()
	end, L["Force rebuff: refresh everything before the pull"])
	HeaderButton(L["Save"], -158, function()
		local sig = HO.Plan.Save()
		HO.Print(sig and ("plan saved for roster: " .. sig) or "cannot save: no paladins in roster")
	end, L["Save the current plan for this paladin roster"])
	win.salvBtn = HeaderButton("No Salv", -222, function()
		HO.commands["nosalv"]("")
	end, L["Encounter toggle: swap Salvation for substitutes, click again to restore the previous plan (lead/assist)"])
	-- place the expand/collapse-all toggle just left of the No Salv button
	win.expandBtn:SetPoint("RIGHT", win.salvBtn, "LEFT", -6, 0)

	win.colHeader = {}
	win.hint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	win.hint:SetPoint("BOTTOMLEFT", 10, 6)
	win.hint:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -10, 6)
	win.hint:SetJustifyH("LEFT")

	Window.ApplyScale() -- apply the saved window scale on first open
end

-- layout ----------------------------------------------------------------------

-- expand a class row (so its member rows and their override cells are shown) and
-- refresh. Called when an edit elsewhere — the cast-bar fly-out — changes a
-- member override, so the change is visible instead of hidden under a collapsed
-- class row (a per-member override only appears in the expanded member row).
function Window.Expand(classToken)
	if not classToken then
		return
	end
	expanded[classToken] = true
	if win and win:IsShown() then
		Window.Refresh()
	end
end

function Window.Refresh()
	if not win or not win:IsShown() then
		return
	end
	local plan = HO.Plan.Active()
	local pallys = HO.Roster.Paladins()
	local numCols = math.min(#pallys, MAX_COLS)

	-- reflect the expand/collapse-all state on its toggle ("-" = all open)
	if win.expandBtn then
		local present, allExpanded, hasAny = PresentClasses(), true, false
		for class in pairs(present) do
			hasAny = true
			if not expanded[class] then
				allExpanded = false
				break
			end
		end
		win.expandBtn:SetText((hasAny and allExpanded) and "-" or "+")
	end

	if win.salvBtn then
		local active = HO.Plan.NoSalvationActive() or HO.db.noSalvBy
		win.salvBtn:SetText(active and "|cffff4040Salv OFF|r" or "No Salv")
	end
	win.hint:SetText(L["click: blessing — right-click: clear — shift-click: mode — click class: members"] .. "\n"
		.. string.format(L["mode: |cff40c0ffA|r auto (greater from %d+ members) — |cffffd100G|r always greater (symbol) — |cff40ff40S|r always 10-min singles"], HO.db.options.greaterMin or 2))

	-- column headers (paladin short names, vertical position under header)
	for c = 1, numCols do
		local fs = win.colHeader[c]
		if not fs then
			fs = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
			win.colHeader[c] = fs
		end
		fs:ClearAllPoints()
		fs:SetPoint("TOPLEFT", win, "TOPLEFT", NAME_W + (c - 1) * COL_W, -(HEADER_H + 4))
		fs:SetWidth(COL_W - COL_GAP)
		local short = pallys[c]:match("^([^%-]+)") or pallys[c]
		fs:SetText(Utf8Truncate(short, HEADER_MAX_CHARS))
		fs:Show()
	end
	for c = numCols + 1, #win.colHeader do
		win.colHeader[c]:Hide()
	end

	-- group roster members and pets by class
	local members = {} -- [classToken] = { playerEntry, ... }
	local petsByClass = {} -- [classToken] = { petEntry, ... }
	for _, entry in ipairs(HO.Roster.units) do
		if entry.class and entry.name then
			local bucket = entry.isPet and petsByClass or members
			local key = entry.class
			if entry.isPet then
				-- pets are listed under their OWNER's class
				local ownerEntry = entry.owner and HO.Roster.byName[entry.owner]
				key = (ownerEntry and ownerEntry.class) or entry.class
			end
			bucket[key] = bucket[key] or {}
			table.insert(bucket[key], entry)
		end
	end
	local function SortByName(a, b)
		return (a.name or "") < (b.name or "")
	end
	for _, list in pairs(members) do
		table.sort(list, SortByName)
	end
	for _, list in pairs(petsByClass) do
		table.sort(list, SortByName)
	end

	local y = HEADER_H + FIRST_ROW_OFFSET
	local classIndex, memberIndex = 0, 0
	local placed = {} -- { {frame, y, h}, ... } positioned after contentHeight is known

	-- aura strip: one row above the class grid, a cell per paladin column showing
	-- that paladin's assigned aura (left-click cycles, right-click clears)
	do
		local row = AcquireAuraRow()
		placed[#placed + 1] = { frame = row, y = y, h = ROW_H }
		for c = 1, numCols do
			local cell = AuraRowCell(row, c)
			cell.pally = pallys[c]
			local id = HO.Plan.GetAura(pallys[c])
			local aura = id and HO.Data.auras[id]
			cell.icon:SetTexture((aura and aura.icon) or NONE_ICON)
			cell.icon:SetDesaturated(false)
			cell:Show()
		end
		for c = numCols + 1, #row.cells do
			row.cells[c]:Hide()
		end
		y = y + ROW_H
	end

	for _, classToken in ipairs(CLASS_ORDER) do
		local list = members[classToken]
		local petList = petsByClass[classToken]
		if list or petList then
			local playerCount = list and #list or 0
			local petCount = petList and #petList or 0
			classIndex = classIndex + 1
			local row = AcquireRow(classRows, classIndex, ROW_H)
			placed[#placed + 1] = { frame = row, y = y, h = ROW_H }
			row.label.text:SetText((expanded[classToken] and "- " or "+ ") .. classToken
				.. " (" .. playerCount .. (petCount > 0 and ("+" .. petCount .. " pets") or "") .. ")")
			row.label:SetScript("OnClick", function()
				expanded[classToken] = not expanded[classToken] or nil
				Window.Refresh()
			end)
			for c = 1, numCols do
				local cell = RowCell(row, c, ClassCellClick)
				cell.pally, cell.classToken, cell.memberName = pallys[c], classToken, nil
				cell.memberCount = playerCount
				local cur = plan.class[pallys[c]] and plan.class[pallys[c]][classToken]
				if cur and cur.none then
					-- explicit-none: a visible placeholder (no mode tag) the user can
					-- wheel/click back to a real blessing
					cell.icon:SetTexture(NONE_ICON)
					cell.icon:SetDesaturated(false)
					cell.mode:SetText("")
				elseif cur then
					cell.icon:SetTexture(HO.Data.blessings[cur.id] and HO.Data.blessings[cur.id].icon or EMPTY_SLOT)
					cell.icon:SetDesaturated(false)
					cell.mode:SetText(MODE_TAG[cur.mode] or "")
				else
					cell.icon:SetTexture(EMPTY_SLOT)
					cell.icon:SetDesaturated(true)
					cell.mode:SetText("")
				end
				cell:Show()
			end
			for c = numCols + 1, #row.cells do
				row.cells[c]:Hide()
			end
			y = y + ROW_H

			if expanded[classToken] then
				local rows = {}
				if list then
					for _, e in ipairs(list) do
						table.insert(rows, e)
					end
				end
				if petList then
					for _, e in ipairs(petList) do
						table.insert(rows, e)
					end
				end
				for _, entry in ipairs(rows) do
					memberIndex = memberIndex + 1
					local mrow = AcquireRow(memberRows, memberIndex, MEMBER_ROW_H, LABEL_INDENT)
					placed[#placed + 1] = { frame = mrow, y = y, h = MEMBER_ROW_H }
					local short = entry.name:match("^([^%-]+)") or entry.name
					if entry.isPet then
						local ownerShort = entry.owner and (entry.owner:match("^([^%-]+)") or entry.owner) or "?"
						mrow.label.text:SetText(short .. " |cff9d9d9d" .. string.format(L["(pet of %s)"], ownerShort) .. "|r")
						mrow.label:SetScript("OnClick", nil)
					else
						local isTank = HO.Plan.IsTank(entry.name, entry.tankRole)
						local spec = HO.db.specCache[entry.name]
						-- a buff this member requested for themselves: a short yellow
						-- tag (f2d926 ≈ the cast-bar request colour), matching the theme
						local req = HO.Comm and HO.Comm.requests[entry.name]
						mrow.label.text:SetText(short
							.. (spec and (" |cff9d9d9d(" .. spec .. ")|r") or "")
							.. (isTank and (" |cffff6060" .. L["[tank]"] .. "|r") or "")
							.. (req and (" |cfff2d926" .. string.format(L["requested: %s"], BlessingName(req)) .. "|r") or ""))
						mrow.label:SetScript("OnClick", function(_, mouseBtn)
							if mouseBtn == "RightButton" then
								if HO.Comm and not HO.Comm.CanFlagTank(entry.name) then
									HO.Print(L["only lead/assist may flag others as tank"])
									return
								end
								local flagged = HO.Plan.ToggleTank(entry.name)
								HO.Print(entry.name .. (flagged and " flagged as tank" or " unflagged as tank"))
							else
								-- cycle spec tag: none -> spec1 -> spec2 -> none
								local specs = HO.Planner.ValidSpecs(entry.class)
								if #specs > 0 then
									local cur = HO.db.specCache[entry.name]
									local nextSpec = specs[1]
									for i, s in ipairs(specs) do
										if s == cur then
											nextSpec = specs[i + 1]
											break
										end
									end
									HO.db.specCache[entry.name] = nextSpec
								end
							end
							RefreshAll()
						end)
					end
					mrow.label:RegisterForClicks("LeftButtonUp", "RightButtonUp")
					for c = 1, numCols do
						local cell = RowCell(mrow, c, MemberCellClick)
						cell.pally, cell.classToken, cell.memberName = pallys[c], nil, entry.name
						local cur = plan.player[pallys[c]] and plan.player[pallys[c]][entry.name]
						-- no override: show what this member effectively gets
						-- from that paladin's class assignment (dimmed)
						local inheritedID
						if not cur then
							if entry.isPet then
								if HO.Engine.PetIncluded(entry) then
									local ownerEntry = entry.owner and HO.Roster.byName[entry.owner]
									local ownerClass = ownerEntry and ownerEntry.class
									local ownerAssign = ownerClass and plan.class[pallys[c]] and plan.class[pallys[c]][ownerClass]
									-- a none-marked owner class inherits nothing to its pets
									if ownerAssign and ownerAssign.id then
										inheritedID = (HO.db.options.pets and HO.db.options.pets.blessing) or 2
									end
								end
							else
								local classAssign = plan.class[pallys[c]] and plan.class[pallys[c]][entry.class]
								-- a none-marked class assignment (no id) inherits NOTHING: the
								-- member cell shows empty, not a none icon
								if classAssign and classAssign.id and HO.Data.IsEligible(entry.class, classAssign.id, HO.Plan.IsTank(entry.name, entry.tankRole)) then
									inheritedID = classAssign.id
								end
							end
						end
						cell.inheritedID = inheritedID
						if cur then
							cell.icon:SetTexture(HO.Data.blessings[cur] and HO.Data.blessings[cur].icon or EMPTY_SLOT)
							cell.icon:SetDesaturated(false)
							cell.icon:SetAlpha(1)
						elseif inheritedID then
							cell.icon:SetTexture(HO.Data.blessings[inheritedID] and HO.Data.blessings[inheritedID].icon or EMPTY_SLOT)
							cell.icon:SetDesaturated(false)
							cell.icon:SetAlpha(0.45)
						else
							cell.icon:SetTexture(EMPTY_SLOT)
							cell.icon:SetDesaturated(true)
							cell.icon:SetAlpha(1)
						end
						cell.mode:SetText("")
						cell:Show()
					end
					for c = numCols + 1, #mrow.cells do
						mrow.cells[c]:Hide()
					end
					y = y + MEMBER_ROW_H
				end
			end
		end
	end
	for i = classIndex + 1, #classRows do
		classRows[i]:Hide()
	end
	for i = memberIndex + 1, #memberRows do
		memberRows[i]:Hide()
	end

	-- virtual scroll: clamp the window to MAX_WIN_H and shift every row by
	-- scrollOffset, hiding any that would fall into the fixed header area or past
	-- the visible bottom. Headers and the top button bar are not in `placed`, so
	-- they stay fixed. When the content fits, offset is forced to 0 (show all).
	local contentHeight = y
	local viewHeight = math.min(contentHeight, MAX_WIN_H)
	local scrolling = contentHeight > viewHeight
	if scrolling then
		local maxOffset = contentHeight - viewHeight
		if scrollOffset < 0 then
			scrollOffset = 0
		elseif scrollOffset > maxOffset then
			scrollOffset = maxOffset
		end
	else
		scrollOffset = 0
	end
	local firstRowY = HEADER_H + FIRST_ROW_OFFSET
	for _, p in ipairs(placed) do
		local top = p.y - scrollOffset
		p.frame:ClearAllPoints()
		p.frame:SetPoint("TOPLEFT", win, "TOPLEFT", 0, -top)
		p.frame:SetPoint("TOPRIGHT", win, "TOPRIGHT", 0, -top)
		if scrolling and (top < firstRowY or top + p.h > viewHeight) then
			p.frame:Hide()
		else
			p.frame:Show()
		end
	end

	win:SetSize(math.max(NAME_W + numCols * COL_W + PAD, 520), viewHeight + BOTTOM_PAD)

	-- a tooltip open over a cell now describes a repurposed cell; a single
	-- owner check re-renders it (or hides it if the cell went away)
	local owner = GameTooltip:GetOwner()
	if owner and owner.hoCell then
		if owner:IsShown() then
			local onEnter = owner:GetScript("OnEnter")
			if onEnter then
				onEnter(owner)
			end
		else
			GameTooltip:Hide()
		end
	end
end

function Window.Toggle()
	Window.Create()
	if win:IsShown() then
		win:Hide()
	else
		win.header:Show() -- defensive: never present a headless window
		win:Show()
		Window.Refresh()
	end
end

HO.RegisterEvent("PLAYER_LOGIN", function()
	HO.Roster.OnChanged(function()
		Window.Refresh()
	end)
end)
