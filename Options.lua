-- HolyOrders — options panel

local HO = HolyOrders
local Options = {}
HO.Options = Options

local PET_CYCLE = { 2, 1, 3 } -- Might > Wisdom > Kings

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
	frame.petBtn:SetText("Pet blessing: " .. (blessing and (blessing.name or blessing.key) or "?"))
end

ITEMS = {
	{ label = "Show cast bar", get = function(o) return not o.bar.hidden end, set = function(o, v) o.bar.hidden = not v; HO.Bar.Refresh() end },
	{ label = "Lock cast bar position", get = function(o) return o.bar.locked end, set = function(o, v) o.bar.locked = v end },
	{ label = "Open edit: others may change my assignments", get = function(o) return o.openEdit end, set = function(o, v) o.openEdit = v; HO.Comm.SendHello() end },
	{ label = "Buff hunter pets", get = function(o) return o.pets.hunter ~= false end, set = function(o, v) o.pets.hunter = v; HO.Bar.Refresh() end },
	{ label = "Buff warlock pets", get = function(o) return o.pets.warlock == true end, set = function(o, v) o.pets.warlock = v; HO.Bar.Refresh() end },
	{ label = "Show minimap button", get = function(o) return not o.minimap.hide end, set = function(o, v) o.minimap.hide = not v; HO.MinimapButton.UpdateShown() end },
	{ label = "Log sync messages (debug)", get = function(o) return o.trace end, set = function(o, v) o.trace = v end },
}

function Options.Create()
	if frame then
		return
	end
	frame = CreateFrame("Frame", "HolyOrdersOptions", UIParent)
	frame:SetFrameStrata("DIALOG")
	frame:SetSize(330, 60 + #ITEMS * 26 + 46)
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
	header.title:SetText("HolyOrders — Options")

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)
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
