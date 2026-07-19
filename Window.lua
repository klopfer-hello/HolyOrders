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
	local nextID = CycleClassBlessing(me, classToken, cur and cur.id or 0, delta)
	HO.Plan.SetClassAssignment(me, classToken, nextID, cur and cur.mode or nil)
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
		GameTooltip:AddLine(string.format(L["override by %s: %s"], cell.pally, cur and BlessingName(cur) or L["none"]), 1, 1, 1)
		if not cur and cell.inheritedID then
			GameTooltip:AddLine(string.format(L["inherited from class assignment: %s"], BlessingName(cell.inheritedID)), 0.7, 0.7, 0.7)
		end
		GameTooltip:AddLine(L["click: next blessing — right-click: clear"], 0.8, 0.8, 0.8)
	else
		GameTooltip:SetText(cell.classToken)
		local plan = HO.Plan.Active()
		local cur = plan.class[cell.pally] and plan.class[cell.pally][cell.classToken]
		if cur then
			GameTooltip:AddLine(cell.pally .. ": " .. BlessingName(cur.id), 1, 1, 1)
			local n = cell.memberCount or 0
			local min = HO.db.options.greaterMin or 2
			if cur.mode == "auto" then
				local effective = (n >= min)
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
	win.header.title:SetText(L["HolyOrders — Assignments"])

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

	win.colHeader = {}
	win.hint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	win.hint:SetPoint("BOTTOMLEFT", 10, 6)
	win.hint:SetJustifyH("LEFT")
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
		local active = HO.Plan.NoSalvationActive() or HO.db.noSalvBy
		win.salvBtn:SetText(active and "|cffff4040Salv OFF|r" or "No Salv")
	end
	win.hint:SetText(L["click: blessing — right-click: clear — shift-click: mode — click class: members"] .. "\n"
		.. string.format(L["mode: |cff9d9d9da|r auto (greater from %d+ members) — |cffffd100G|r always greater (symbol) — |cffffffffn|r always 10-min singles"], HO.db.options.greaterMin or 2))

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

	local y = HEADER_H + 20
	local classIndex, memberIndex = 0, 0

	for _, classToken in ipairs(CLASS_ORDER) do
		local list = members[classToken]
		local petList = petsByClass[classToken]
		if list or petList then
			local playerCount = list and #list or 0
			local petCount = petList and #petList or 0
			classIndex = classIndex + 1
			local row = AcquireRow(classRows, classIndex, ROW_H)
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", win, "TOPLEFT", 0, -y)
			row:SetPoint("TOPRIGHT", win, "TOPRIGHT", 0, -y)
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
					local mrow = AcquireRow(memberRows, memberIndex, MEMBER_ROW_H)
					mrow:ClearAllPoints()
					mrow:SetPoint("TOPLEFT", win, "TOPLEFT", 14, -y)
					mrow:SetPoint("TOPRIGHT", win, "TOPRIGHT", 0, -y)
					local short = entry.name:match("^([^%-]+)") or entry.name
					if entry.isPet then
						local ownerShort = entry.owner and (entry.owner:match("^([^%-]+)") or entry.owner) or "?"
						mrow.label.text:SetText(short .. " |cff9d9d9d" .. string.format(L["(pet of %s)"], ownerShort) .. "|r")
						mrow.label:SetScript("OnClick", nil)
					else
						local isTank = HO.Plan.IsTank(entry.name, entry.tankRole)
						local spec = HO.db.specCache[entry.name]
						mrow.label.text:SetText(short
							.. (spec and (" |cff9d9d9d(" .. spec .. ")|r") or "")
							.. (isTank and (" |cffff6060" .. L["[tank]"] .. "|r") or ""))
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
					mrow.memberName = entry.name
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
									if ownerClass and plan.class[pallys[c]] and plan.class[pallys[c]][ownerClass] then
										inheritedID = (HO.db.options.pets and HO.db.options.pets.blessing) or 2
									end
								end
							else
								local classAssign = plan.class[pallys[c]] and plan.class[pallys[c]][entry.class]
								if classAssign and HO.Data.IsEligible(entry.class, classAssign.id, HO.Plan.IsTank(entry.name, entry.tankRole)) then
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
