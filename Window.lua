-- HolyOrders — assignment window
-- Class grid: rows are classes (expandable to members), columns are paladins.
-- Left-click a cell cycles blessings, right-click clears, shift-click cycles
-- the cast mode. Member rows carry per-member overrides, tank flag and spec
-- tag. Everything edits the active plan; no secure frames involved.

local HO = HolyOrders
local Window = {}
HO.Window = Window

local NAME_W = 175
local COL_W = 34
local COL_GAP = 4
local HEADER_H = 30
local ROW_H = 26
local MEMBER_ROW_H = 22
local PAD = 8
local MAX_COLS = 8

local CLASS_ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local MODE_TAG = { auto = "|cff9d9d9da|r", greater = "|cffffd100G|r", normal = "|cffffffffn|r" }
local EMPTY_SLOT = "Interface\\PaperDoll\\UI-Backpack-EmptySlot"

local win
local expanded = {} -- [classToken] = true
local classRows, memberRows = {}, {}

-- helpers ---------------------------------------------------------------------

local function BlessingName(id)
	local blessing = HO.Data.blessings[id]
	return blessing and (blessing.name or blessing.key) or tostring(id)
end

-- next assignable blessing for a class cell (0 = none); eligibility filtered,
-- availability best-effort (exact for the player, permissive for remotes)
local function CycleClassBlessing(pally, classToken, current)
	local id = current or 0
	for _ = 1, HO.Data.NUM_BLESSINGS + 1 do
		id = (id + 1) % (HO.Data.NUM_BLESSINGS + 1)
		if id == 0 then
			return 0
		end
		if HO.Data.IsEligible(classToken, id, false) and HO.Planner.IsAvailable(pally, id) then
			return id
		end
	end
	return 0
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
		if cur then
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
	if mouseBtn == "RightButton" then
		HO.Plan.SetPlayerOverride(cell.pally, cell.memberName, 0)
	else
		HO.Plan.SetPlayerOverride(cell.pally, cell.memberName, CycleOverrideBlessing(cell.pally, cur))
	end
	RefreshAll()
end

local function CellTooltip(cell)
	GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
	if cell.memberName then
		GameTooltip:SetText(cell.memberName)
		local plan = HO.Plan.Active()
		local cur = plan.player[cell.pally] and plan.player[cell.pally][cell.memberName]
		GameTooltip:AddLine("override by " .. cell.pally .. ": " .. (cur and BlessingName(cur) or "none"), 1, 1, 1)
		GameTooltip:AddLine("click: next blessing — right-click: clear", 0.8, 0.8, 0.8)
	else
		GameTooltip:SetText(cell.classToken)
		local plan = HO.Plan.Active()
		local cur = plan.class[cell.pally] and plan.class[cell.pally][cell.classToken]
		if cur then
			GameTooltip:AddLine(cell.pally .. ": " .. BlessingName(cur.id), 1, 1, 1)
			local n = cell.memberCount or 0
			if cur.mode == "auto" then
				local effective = (n >= 2)
					and "greater (30 min, whole class, 1 Symbol of Kings)"
					or "10-min singles (too few members for greater)"
				GameTooltip:AddLine("mode: auto — greater from 2+ members, singles otherwise", 0.9, 0.9, 0.9, true)
				GameTooltip:AddLine("with " .. n .. " member" .. (n == 1 and "" or "s") .. " now: " .. effective, 0.6, 1, 0.6, true)
			elseif cur.mode == "greater" then
				GameTooltip:AddLine("mode: greater — always the Greater Blessing: 30 min, hits the whole class, costs a Symbol of Kings per cast", 0.9, 0.9, 0.9, true)
			else
				GameTooltip:AddLine("mode: normal — always 10-min single blessings on each member, no reagent", 0.9, 0.9, 0.9, true)
			end
		else
			GameTooltip:AddLine(cell.pally .. ": no assignment", 1, 1, 1)
		end
		GameTooltip:AddLine("click: next blessing — right-click: clear", 0.8, 0.8, 0.8)
		GameTooltip:AddLine("shift-click: change the cast mode", 0.8, 0.8, 0.8)
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
	cell.icon:SetSize(ROW_H - 8, ROW_H - 8)
	cell.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	cell.mode = cell:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	cell.mode:SetPoint("BOTTOMRIGHT", -1, 1)
	cell:SetScript("OnEnter", CellTooltip)
	cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return cell
end

local function AcquireRow(pool, index, height)
	local row = pool[index]
	if not row then
		row = CreateFrame("Frame", nil, win)
		row:SetHeight(height)
		row.cells = {}
		row.label = CreateFrame("Button", nil, row)
		row.label:SetPoint("LEFT", 4, 0)
		row.label:SetSize(NAME_W - 8, height)
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

function Window.Create()
	if win then
		return
	end
	win = CreateFrame("Frame", "HolyOrdersWindow", UIParent)
	win:SetFrameStrata("HIGH")
	win:SetMovable(true)
	win:SetClampedToScreen(true)
	win:EnableMouse(true)
	win:SetPoint("CENTER")
	win:Hide()
	table.insert(UISpecialFrames, "HolyOrdersWindow")

	win.bg = win:CreateTexture(nil, "BACKGROUND")
	win.bg:SetAllPoints()
	win.bg:SetColorTexture(0.05, 0.05, 0.08, 0.93)

	win.header = CreateFrame("Frame", nil, win)
	win.header:SetPoint("TOPLEFT")
	win.header:SetPoint("TOPRIGHT")
	win.header:SetHeight(HEADER_H)
	win.header:EnableMouse(true)
	win.header:RegisterForDrag("LeftButton")
	win.header:SetScript("OnDragStart", function() win:StartMoving() end)
	win.header:SetScript("OnDragStop", function() win:StopMovingOrSizing() end)
	win.header.bg = win.header:CreateTexture(nil, "BACKGROUND")
	win.header.bg:SetAllPoints()
	win.header.bg:SetColorTexture(0.94, 0.78, 0.09, 0.18)
	win.header.title = win.header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	win.header.title:SetPoint("LEFT", 10, 0)
	win.header.title:SetText("HolyOrders — Assignments")

	-- parent the close button to the window, not the header: the template's
	-- default OnClick hides its PARENT, which used to hide only the title bar
	local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", win, "TOPRIGHT", 2, 2)
	close:SetFrameLevel(win.header:GetFrameLevel() + 1)
	close:SetScript("OnClick", function()
		win:Hide()
	end)

	local function HeaderButton(text, offsetX, onClick, tooltip)
		local btn = CreateFrame("Button", nil, win.header, "UIPanelButtonTemplate")
		btn:SetSize(60, 20)
		btn:SetPoint("RIGHT", win.header, "RIGHT", offsetX, 0)
		btn:SetText(text)
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
	end, "Run the deterministic auto-planner")
	HeaderButton("Rebuff", -94, function()
		HO.Bar.ToggleForceRebuff()
	end, "Force rebuff: refresh everything before the pull")
	HeaderButton("Save", -158, function()
		local sig = HO.Plan.Save()
		HO.Print(sig and ("plan saved for roster: " .. sig) or "cannot save: no paladins in roster")
	end, "Save the current plan for this paladin roster")
	win.salvBtn = HeaderButton("No Salv", -222, function()
		HO.commands["nosalv"]("")
	end, "Encounter toggle: swap Salvation for substitutes, click again to restore the previous plan (lead/assist)")

	win.colHeader = {}
	win.hint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	win.hint:SetPoint("BOTTOMLEFT", 10, 6)
	win.hint:SetJustifyH("LEFT")
	win.hint:SetText("click: blessing — right-click: clear — shift-click: mode — click class: members\n"
		.. "mode: |cff9d9d9da|r auto (greater from 2+ members) — |cffffd100G|r always greater (symbol) — |cffffffffn|r always 10-min singles")
end

-- layout ----------------------------------------------------------------------

function Window.Refresh()
	if not win or not win:IsShown() then
		return
	end
	local plan = HO.Plan.Active()
	local pallys = HO.Roster.Paladins()
	local numCols = math.min(#pallys, MAX_COLS)

	if win.salvBtn then
		win.salvBtn:SetText(HO.Plan.NoSalvationActive() and "|cffff4040Salv OFF|r" or "No Salv")
	end

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
		fs:SetText(short:sub(1, 5))
		fs:Show()
	end
	for c = numCols + 1, #win.colHeader do
		win.colHeader[c]:Hide()
	end

	-- group roster members by class
	local members = {} -- [classToken] = { entry, ... } (players only)
	for _, entry in ipairs(HO.Roster.units) do
		if not entry.isPet and entry.class and entry.name then
			members[entry.class] = members[entry.class] or {}
			table.insert(members[entry.class], entry)
		end
	end
	for _, list in pairs(members) do
		table.sort(list, function(a, b)
			return (a.name or "") < (b.name or "")
		end)
	end

	local y = HEADER_H + 20
	local classIndex, memberIndex = 0, 0

	for _, classToken in ipairs(CLASS_ORDER) do
		local list = members[classToken]
		if list then
			classIndex = classIndex + 1
			local row = AcquireRow(classRows, classIndex, ROW_H)
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", win, "TOPLEFT", 0, -y)
			row:SetPoint("TOPRIGHT", win, "TOPRIGHT", 0, -y)
			row.label.text:SetText((expanded[classToken] and "- " or "+ ") .. classToken .. " (" .. #list .. ")")
			row.label:SetScript("OnClick", function()
				expanded[classToken] = not expanded[classToken] or nil
				Window.Refresh()
			end)
			for c = 1, numCols do
				local cell = RowCell(row, c, ClassCellClick)
				cell.pally, cell.classToken, cell.memberName = pallys[c], classToken, nil
				cell.memberCount = #list
				local cur = plan.class[pallys[c]] and plan.class[pallys[c]][classToken]
				if cur then
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
			row:Show()
			y = y + ROW_H

			if expanded[classToken] then
				for _, entry in ipairs(list) do
					memberIndex = memberIndex + 1
					local mrow = AcquireRow(memberRows, memberIndex, MEMBER_ROW_H)
					mrow:ClearAllPoints()
					mrow:SetPoint("TOPLEFT", win, "TOPLEFT", 14, -y)
					mrow:SetPoint("TOPRIGHT", win, "TOPRIGHT", 0, -y)
					local isTank = plan.tanks[entry.name] or entry.tankRole
					local spec = HO.db.specCache[entry.name]
					local short = entry.name:match("^([^%-]+)") or entry.name
					mrow.label.text:SetText(short
						.. (spec and (" |cff9d9d9d(" .. spec .. ")|r") or "")
						.. (isTank and " |cffff6060[tank]|r" or ""))
					mrow.memberName = entry.name
					mrow.label:SetScript("OnClick", function(_, mouseBtn)
						if mouseBtn == "RightButton" then
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
					mrow.label:RegisterForClicks("LeftButtonUp", "RightButtonUp")
					for c = 1, numCols do
						local cell = RowCell(mrow, c, MemberCellClick)
						cell.pally, cell.classToken, cell.memberName = pallys[c], nil, entry.name
						local cur = plan.player[pallys[c]] and plan.player[pallys[c]][entry.name]
						if cur then
							cell.icon:SetTexture(HO.Data.blessings[cur] and HO.Data.blessings[cur].icon or EMPTY_SLOT)
							cell.icon:SetDesaturated(false)
						else
							cell.icon:SetTexture(EMPTY_SLOT)
							cell.icon:SetDesaturated(true)
						end
						cell.mode:SetText("")
						cell:Show()
					end
					for c = numCols + 1, #mrow.cells do
						mrow.cells[c]:Hide()
					end
					mrow:Show()
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

	win:SetSize(math.max(NAME_W + numCols * COL_W + PAD, 520), y + 38)
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
