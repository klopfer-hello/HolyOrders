-- HolyOrders — secure cast bar
-- One button per class duty; clicking casts the engine's chosen blessing on
-- its chosen target. Secure attributes and the icon that mirrors them only
-- change out of combat, so the display always matches the actual cast.

local HO = HolyOrders
local Bar = {}
HO.Bar = Bar
local L = HO.L

local BUTTON_SIZE = 34
local GAP = 5
local HANDLE_WIDTH = 12
local MAX_BUTTONS = 9
local UPDATE_INTERVAL = 1.0

local CLASS_ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

local bar, handle, ticker
local buttons = {}
local lastGrow

-- arranges handle and buttons for the configured growth direction; must only
-- run out of combat (buttons are protected frames)
local function LayoutBar()
	local grow = HO.db.options.bar and HO.db.options.bar.grow or "right"
	local horizontal = (grow == "left" or grow == "right")
	local length = HANDLE_WIDTH + GAP + MAX_BUTTONS * (BUTTON_SIZE + GAP)
	if horizontal then
		bar:SetSize(length, BUTTON_SIZE + 4)
		handle:SetSize(HANDLE_WIDTH, BUTTON_SIZE)
	else
		bar:SetSize(BUTTON_SIZE + 4, length)
		handle:SetSize(BUTTON_SIZE, HANDLE_WIDTH)
	end
	handle:ClearAllPoints()
	if grow == "right" then
		handle:SetPoint("LEFT", bar, "LEFT", 0, 0)
	elseif grow == "left" then
		handle:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
	elseif grow == "down" then
		handle:SetPoint("TOP", bar, "TOP", 0, 0)
	else -- up
		handle:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)
	end
	for i, btn in ipairs(buttons) do
		local offset = HANDLE_WIDTH + GAP + (i - 1) * (BUTTON_SIZE + GAP)
		btn:ClearAllPoints()
		if grow == "right" then
			btn:SetPoint("LEFT", bar, "LEFT", offset, 0)
		elseif grow == "left" then
			btn:SetPoint("RIGHT", bar, "RIGHT", -offset, 0)
		elseif grow == "down" then
			btn:SetPoint("TOP", bar, "TOP", 0, -offset)
		else
			btn:SetPoint("BOTTOM", bar, "BOTTOM", 0, offset)
		end
	end
	lastGrow = grow
end

local function BarOptions()
	HO.db.options.bar = HO.db.options.bar or {}
	return HO.db.options.bar
end

local function SavePosition()
	local opts = BarOptions()
	local _, _, _, x, y = bar:GetPoint()
	opts.x, opts.y = x, y
end

function Bar.ResetPosition()
	local opts = BarOptions()
	opts.x, opts.y = nil, nil
	bar:ClearAllPoints()
	bar:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
end

local function RestorePosition()
	local opts = BarOptions()
	bar:ClearAllPoints()
	bar:SetPoint("CENTER", UIParent, "CENTER", opts.x or 0, opts.y or -180)
end

local function FormatShort(seconds)
	if not seconds then
		return ""
	end
	if seconds >= 60 then
		return string.format("%dm", math.floor(seconds / 60))
	end
	return string.format("%ds", math.floor(seconds))
end

-- button visuals that are safe to update in combat
local function UpdateButtonTexts(btn, task)
	btn.count:SetText(task.missing > 0 and tostring(task.missing) or "")
	btn.timer:SetText(FormatShort(task.minRemaining))
	if task.missing > 0 then
		btn.bg:SetColorTexture(0.55, 0.10, 0.10, 0.85)
	elseif task.expiring > 0 then
		btn.bg:SetColorTexture(0.55, 0.45, 0.05, 0.85)
	else
		btn.bg:SetColorTexture(0, 0, 0, 0.65)
	end
end

local function CreateButton(index)
	local btn = CreateFrame("Button", "HolyOrdersBarButton" .. index, bar, "SecureActionButtonTemplate")
	btn:SetSize(BUTTON_SIZE, BUTTON_SIZE)
	-- modern clients fire secure actions on the edge selected by the
	-- ActionButtonUseKeyDown cvar; register both so the click always lands
	btn:RegisterForClicks("AnyDown", "AnyUp")
	-- left: the planned cast (greater when planned); right: always a single
	btn:SetAttribute("type1", "spell")
	btn:SetAttribute("type2", "spell")
	-- wheel: cycle my class assignment (out of combat; syncs + updates window)
	btn:EnableMouseWheel(true)
	btn:SetScript("OnMouseWheel", function(self, delta)
		if InCombatLockdown() then
			return
		end
		local task = self.task
		if task then
			HO.Window.CycleMyClass(task.classToken, delta > 0 and 1 or -1)
		end
	end)

	btn.bg = btn:CreateTexture(nil, "BACKGROUND")
	btn.bg:SetAllPoints()
	btn.bg:SetColorTexture(0, 0, 0, 0.65)

	btn.icon = btn:CreateTexture(nil, "ARTWORK")
	btn.icon:SetPoint("TOPLEFT", 2, -2)
	btn.icon:SetPoint("BOTTOMRIGHT", -2, 2)
	btn.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	btn.classIcon = btn:CreateTexture(nil, "OVERLAY")
	btn.classIcon:SetSize(15, 15)
	btn.classIcon:SetPoint("TOPLEFT", -5, 5)
	btn.classIcon:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")

	btn.count = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	btn.count:SetPoint("BOTTOMRIGHT", -1, 1)

	btn.timer = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	btn.timer:SetPoint("TOP", btn, "BOTTOM", 0, -1)

	btn:SetScript("OnEnter", function(self)
		local task = self.task
		if not task then
			return
		end
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		local blessing = HO.Data.blessings[task.blessingID]
		GameTooltip:SetText(task.classToken)
		if task.spellName and task.unitName then
			GameTooltip:AddLine(string.format(L["left: %s on %s"], task.spellName, task.unitName), 1, 1, 1)
			if task.singleSpellName and task.singleSpellName ~= task.spellName then
				GameTooltip:AddLine(string.format(L["right: %s (single)"], task.singleSpellName), 1, 1, 1)
			end
		elseif task.missing > 0 then
			GameTooltip:AddLine(L["all remaining targets are out of range"], 1, 0.6, 0.3)
		else
			GameTooltip:AddLine(string.format(L["%s — all covered"], blessing and (blessing.name or blessing.key) or "?"), 0.6, 1, 0.6)
		end
		if task.outOfRange and task.outOfRange > 0 then
			GameTooltip:AddLine(string.format(L["%d out of range (skipped)"], task.outOfRange), 1, 0.6, 0.3)
		end
		if task.missing > 0 then
			GameTooltip:AddLine(string.format(L["%d missing"], task.missing), 1, 0.4, 0.4)
		end
		if task.expiring > 0 then
			GameTooltip:AddLine(string.format(L["%d expiring soon"], task.expiring), 1, 0.85, 0.3)
		end
		GameTooltip:AddLine(L["mouse wheel: change my assignment"], 0.8, 0.8, 0.8)
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	return btn
end

function Bar.Create()
	if bar then
		return
	end
	bar = CreateFrame("Frame", "HolyOrdersBar", UIParent)
	bar:SetMovable(true)
	bar:SetClampedToScreen(true)
	bar:SetFrameStrata("HIGH") -- above raid frames (VuhDo etc.)

	handle = CreateFrame("Frame", nil, bar)
	handle:SetPoint("TOPLEFT", 0, 0)
	handle:SetSize(HANDLE_WIDTH, BUTTON_SIZE)
	handle:EnableMouse(true)
	handle:RegisterForDrag("LeftButton")
	handle.tex = handle:CreateTexture(nil, "BACKGROUND")
	handle.tex:SetAllPoints()
	handle.tex:SetColorTexture(0.94, 0.78, 0.09, 0.55)
	handle:SetScript("OnDragStart", function()
		if not BarOptions().locked then
			bar:StartMoving()
		end
	end)
	handle:SetScript("OnDragStop", function()
		bar:StopMovingOrSizing()
		SavePosition()
	end)
	handle:SetScript("OnMouseUp", function(_, mouseButton)
		if mouseButton == "RightButton" then
			if IsShiftKeyDown() then
				HO.Window.Toggle()
			else
				Bar.ToggleForceRebuff()
			end
		end
	end)
	handle:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("HolyOrders")
		GameTooltip:AddLine(BarOptions().locked and L["locked — /ho bar unlock"] or L["drag to move — /ho bar lock"], 1, 1, 1)
		GameTooltip:AddLine(L["right-click: force rebuff (pre-pull refresh)"], 1, 1, 1)
		GameTooltip:AddLine(L["shift-right-click: assignment window"], 1, 1, 1)
		GameTooltip:Show()
	end)
	handle:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	for i = 1, MAX_BUTTONS do
		local btn = CreateButton(i)
		btn:Hide()
		buttons[i] = btn
	end
	LayoutBar()
	RestorePosition()
	bar:Hide()
end

function Bar.ToggleForceRebuff()
	if HO.Engine.ForceActive() then
		HO.Engine.StopForceRebuff()
		HO.Print(L["force rebuff cancelled"])
	else
		HO.Engine.StartForceRebuff()
		HO.Print(L["force rebuff: refreshing everything older than 2 minutes (ends when all fresh)"])
	end
	Bar.Refresh()
end

function Bar.Refresh()
	if not bar or not HO.db then
		return
	end
	HO.Engine.Update()
	if handle then
		if HO.Engine.ForceActive() then
			handle.tex:SetColorTexture(0.85, 0.20, 0.10, 0.80)
		else
			handle.tex:SetColorTexture(0.94, 0.78, 0.09, 0.55)
		end
	end

	if InCombatLockdown() then
		-- attributes and shown-state are frozen; only refresh texts of the
		-- buttons that are already visible, matched by their frozen class
		for i = 1, MAX_BUTTONS do
			local btn = buttons[i]
			if btn:IsShown() and btn.task then
				local task = HO.Engine.tasks[btn.task.classToken]
				if task then
					UpdateButtonTexts(btn, task)
				end
			end
		end
		return
	end

	if (BarOptions().grow or "right") ~= lastGrow then
		LayoutBar()
	end

	local index = 0
	for _, classToken in ipairs(CLASS_ORDER) do
		local task = HO.Engine.tasks[classToken]
		if task and index < MAX_BUTTONS then
			index = index + 1
			local btn = buttons[index]
			btn.task = task
			btn:SetAttribute("spell1", task.spellName)
			btn:SetAttribute("unit1", task.unit)
			btn:SetAttribute("spell2", task.singleSpellName)
			btn:SetAttribute("unit2", task.unit)
			btn.icon:SetTexture(task.icon)
			btn.icon:SetDesaturated(task.spellName == nil)
			local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classToken]
			if coords then
				btn.classIcon:SetTexCoord(unpack(coords))
				btn.classIcon:Show()
			else
				btn.classIcon:Hide()
			end
			UpdateButtonTexts(btn, task)
			btn:Show()
		end
	end
	for i = index + 1, MAX_BUTTONS do
		buttons[i]:Hide()
		buttons[i].task = nil
		buttons[i]:SetAttribute("spell1", nil)
		buttons[i]:SetAttribute("unit1", nil)
		buttons[i]:SetAttribute("spell2", nil)
		buttons[i]:SetAttribute("unit2", nil)
	end

	local isPally = select(2, UnitClass("player")) == "PALADIN"
	if isPally and not BarOptions().hidden and index > 0 then
		bar:Show()
	else
		bar:Hide()
	end
end

function Bar.Init()
	Bar.Create()
	if not ticker then
		ticker = C_Timer.NewTicker(UPDATE_INTERVAL, Bar.Refresh)
	end
	HO.Roster.OnChanged(Bar.Refresh)
end

HO.RegisterEvent("PLAYER_LOGIN", Bar.Init)
HO.RegisterEvent("PLAYER_REGEN_ENABLED", function()
	Bar.Refresh()
end)
