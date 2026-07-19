-- HolyOrders — options panel

local HO = HolyOrders
local Options = {}
HO.Options = Options
local L = HO.L

local PET_CYCLE = { 2, 1, 3 } -- Might > Wisdom > Kings
local GROW_CYCLE = { "right", "left", "down", "up" }

local frame
local checks = {}
local ITEMS

function Options.Ensure()
	local o = HO.db.options
	o.bar = o.bar or {}
	o.pets = o.pets or { hunter = true, warlock = false, blessing = 2 }
	o.minimap = o.minimap or { angle = 200 }
	return o
end

local function Refresh()
	if not frame or not frame:IsShown() then
		return
	end
	local o = Options.Ensure()
	for i, item in ipairs(ITEMS) do
		checks[i]:SetChecked(item.get(o) and true or false)
	end
	local blessing = HO.Data.blessings[o.pets.blessing or 2]
	frame.petBtn:SetText(string.format(L["Pet blessing: %s"], blessing and (blessing.name or blessing.key) or "?"))
	frame.growBtn:SetText(string.format(L["Bar grows: %s"], o.bar.grow or "right"))
end

ITEMS = {
	{ label = L["Show cast bar"], get = function(o) return not o.bar.hidden end, set = function(o, v) o.bar.hidden = not v; HO.Bar.Refresh() end },
	{ label = L["Lock cast bar position"], get = function(o) return o.bar.locked end, set = function(o, v) o.bar.locked = v end },
	{ label = L["Open edit: others may change my assignments"], get = function(o) return o.openEdit end, set = function(o, v) o.openEdit = v; HO.Comm.SendHello() end },
	{ label = L["Prefer greater blessings even for single members"], get = function(o) return o.greaterMin == 1 end, set = function(o, v) o.greaterMin = v and 1 or 2; HO.Bar.Refresh() end },
	{ label = L["Buff hunter pets"], get = function(o) return o.pets.hunter ~= false end, set = function(o, v) o.pets.hunter = v; HO.Bar.Refresh() end },
	{ label = L["Buff warlock pets"], get = function(o) return o.pets.warlock == true end, set = function(o, v) o.pets.warlock = v; HO.Bar.Refresh() end },
	{ label = L["Show minimap button"], get = function(o) return not o.minimap.hide end, set = function(o, v) o.minimap.hide = not v; HO.MinimapButton.UpdateShown() end },
	{ label = L["Log sync messages (debug)"], get = function(o) return o.trace end, set = function(o, v) o.trace = v end },
}

function Options.Create()
	if frame then
		return
	end
	frame = CreateFrame("Frame", "HolyOrdersOptions", UIParent)
	frame:SetFrameStrata("DIALOG")
	frame:SetSize(330, 60 + #ITEMS * 26 + 74)
	frame:SetPoint("CENTER")
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:Hide()
	table.insert(UISpecialFrames, "HolyOrdersOptions")

	frame.bg = frame:CreateTexture(nil, "BACKGROUND")
	frame.bg:SetAllPoints()
	frame.bg:SetColorTexture(0.05, 0.05, 0.08, 0.93)

	local header = CreateFrame("Frame", nil, frame)
	header:SetPoint("TOPLEFT")
	header:SetPoint("TOPRIGHT")
	header:SetHeight(28)
	header:EnableMouse(true)
	header:RegisterForDrag("LeftButton")
	header:SetScript("OnDragStart", function() frame:StartMoving() end)
	header:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
	header.bg = header:CreateTexture(nil, "BACKGROUND")
	header.bg:SetAllPoints()
	header.bg:SetColorTexture(0.94, 0.78, 0.09, 0.18)
	header.title = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	header.title:SetPoint("LEFT", 10, 0)
	header.title:SetText(L["HolyOrders — Options"])

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)
	close:SetFrameLevel(header:GetFrameLevel() + 1) -- above the drag header
	close:SetScript("OnClick", function()
		frame:Hide()
	end)

	for i, item in ipairs(ITEMS) do
		local check = CreateFrame("CheckButton", "HolyOrdersOptCheck" .. i, frame, "UICheckButtonTemplate")
		check:SetSize(24, 24)
		check:SetPoint("TOPLEFT", 12, -(34 + (i - 1) * 26))
		_G["HolyOrdersOptCheck" .. i .. "Text"]:SetText(item.label)
		check:SetScript("OnClick", function(self)
			item.set(Options.Ensure(), self:GetChecked() and true or false)
			Refresh()
		end)
		checks[i] = check
	end

	frame.growBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	frame.growBtn:SetSize(220, 22)
	frame.growBtn:SetPoint("BOTTOMLEFT", 12, 40)
	frame.growBtn:SetScript("OnClick", function()
		local o = Options.Ensure()
		local nextDir = GROW_CYCLE[1]
		for i, dir in ipairs(GROW_CYCLE) do
			if dir == (o.bar.grow or "right") then
				nextDir = GROW_CYCLE[i + 1] or GROW_CYCLE[1]
				break
			end
		end
		o.bar.grow = nextDir
		Refresh()
		HO.Bar.Refresh()
	end)

	frame.petBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	frame.petBtn:SetSize(220, 22)
	frame.petBtn:SetPoint("BOTTOMLEFT", 12, 12)
	frame.petBtn:SetScript("OnClick", function()
		local o = Options.Ensure()
		local nextID = PET_CYCLE[1]
		for i, id in ipairs(PET_CYCLE) do
			if id == o.pets.blessing then
				nextID = PET_CYCLE[i + 1] or PET_CYCLE[1]
				break
			end
		end
		o.pets.blessing = nextID
		Refresh()
		HO.Bar.Refresh()
	end)
end

function Options.Toggle()
	Options.Create()
	if frame:IsShown() then
		frame:Hide()
	else
		frame:Show()
		Refresh()
	end
end
