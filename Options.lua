-- HolyOrders — options panel (mounted in Blizzard's Interface Options)

local HO = HolyOrders
local Options = {}
HO.Options = Options
local L = HO.L

local PET_CYCLE = { 2, 1, 3 } -- Might > Wisdom > Kings
local GROW_CYCLE = { "right", "left", "down", "up" }
local FLYOUT_CYCLE = { "left", "right", "up", "down" }
local REFRESH_INTERVAL = 1.0
local LABEL_WIDTH = 480 -- wrap long (German) labels instead of running off the panel

local panel
local category -- retail Settings category handle (nil on 2.5.6)
local checks = {}
local ITEMS

local SCALE_CYCLE = { 0.8, 0.9, 1.0, 1.1, 1.25, 1.5 }

function Options.Ensure()
	local o = HO.db.options
	o.bar = o.bar or {}
	o.bar.scale = o.bar.scale or 1.0
	o.window = o.window or {} -- o.window.scale defaults to nil (read as 1.0)
	o.pets = o.pets or { hunter = true, warlock = false, blessing = 2 }
	o.minimap = o.minimap or { angle = 200 }
	return o
end

-- advance a scale value to the next preset in SCALE_CYCLE (wraps)
local function NextScale(current)
	local nextScale = SCALE_CYCLE[1]
	for i, s in ipairs(SCALE_CYCLE) do
		if s == (current or 1.0) then
			nextScale = SCALE_CYCLE[i + 1] or SCALE_CYCLE[1]
			break
		end
	end
	return nextScale
end

local function Refresh()
	if not panel or not panel:IsShown() then
		return
	end
	local o = Options.Ensure()
	for i, item in ipairs(ITEMS) do
		checks[i]:SetChecked(item.get(o) and true or false)
	end
	local blessing = HO.Data.blessings[o.pets.blessing or 2]
	panel.petBtn:SetText(string.format(L["Pet blessing: %s"], blessing and (blessing.name or blessing.key) or "?"))
	panel.growBtn:SetText(string.format(L["Bar grows: %s"], o.bar.grow or "right"))
	panel.flyoutBtn:SetText(string.format(L["Fly-out opens: %s"], o.bar.flyout or "left"))
	panel.barScaleBtn:SetText(string.format(L["Cast bar scale: %d%%"], math.floor((o.bar.scale or 1) * 100 + 0.5)))
	panel.winScaleBtn:SetText(string.format(L["Window scale: %d%%"], math.floor(((o.window and o.window.scale) or 1) * 100 + 0.5)))
end

-- toggles that change plan/pet display must also update an open assignment
-- window, not just the cast bar (both are nil-safe: modules may not exist yet)
local function RefreshAll()
	if HO.Bar and HO.Bar.Refresh then
		HO.Bar.Refresh()
	end
	if HO.Window and HO.Window.Refresh then
		HO.Window.Refresh()
	end
end

ITEMS = {
	{ label = L["Show cast bar"], get = function(o) return not o.bar.hidden end, set = function(o, v) o.bar.hidden = not v; HO.Bar.Refresh() end },
	{ label = L["Keep cast bar above other windows"], get = function(o) return o.bar.front == true end, set = function(o, v) o.bar.front = v; if HO.Bar and HO.Bar.ApplyStrata then HO.Bar.ApplyStrata() end end },
	{ label = L["Open edit: others may change my assignments"], get = function(o) return o.openEdit end, set = function(o, v) o.openEdit = v; HO.Comm.SendHello() end },
	{ label = L["Prefer greater blessings even for single members"], get = function(o) return o.greaterMin == 1 end, set = function(o, v) o.greaterMin = v and 1 or 2; RefreshAll() end },
	{ label = L["Buff hunter pets"], get = function(o) return o.pets.hunter ~= false end, set = function(o, v) o.pets.hunter = v; RefreshAll() end },
	{ label = L["Buff warlock pets"], get = function(o) return o.pets.warlock == true end, set = function(o, v) o.pets.warlock = v; RefreshAll() end },
	{ label = L["Show minimap button"], get = function(o) return not o.minimap.hide end, set = function(o, v) o.minimap.hide = not v; HO.MinimapButton.UpdateShown() end },
	{ label = L["Show status messages in chat"], get = function(o) return o.verbose == true end, set = function(o, v) o.verbose = v end },
	{ label = L["Share assignments with legacy blessing addons"], get = function(o) return o.legacyBroadcast == true end, set = function(o, v) o.legacyBroadcast = v; if HO.Interop then HO.Interop.SetEnabled(v) end end },
	{ label = L["Log sync messages (debug)"], get = function(o) return o.trace end, set = function(o, v) o.trace = v end },
}

function Options.Create()
	if panel then
		return
	end
	-- a plain Frame is all a Blizzard options panel needs; the container reparents
	-- and sizes it (~600 px wide) once it is registered as a category
	panel = CreateFrame("Frame", "HolyOrdersOptionsPanel", UIParent)
	panel.name = "HolyOrders"
	panel:Hide()

	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText(L["HolyOrders — Options"])

	-- keep the panel in sync with /ho toggles made in chat while it is shown;
	-- panels stay mounted in the container, so OnShow/OnHide fire as the user
	-- navigates between categories
	panel:SetScript("OnShow", function(self)
		Refresh()
		if not self.ticker then
			self.ticker = C_Timer.NewTicker(REFRESH_INTERVAL, Refresh)
		end
	end)
	panel:SetScript("OnHide", function(self)
		if self.ticker then
			self.ticker:Cancel()
			self.ticker = nil
		end
	end)

	local topOffset = 48 -- clear the title
	for i, item in ipairs(ITEMS) do
		local check = CreateFrame("CheckButton", "HolyOrdersOptCheck" .. i, panel, "UICheckButtonTemplate")
		check:SetSize(24, 24)
		check:SetPoint("TOPLEFT", 16, -(topOffset + (i - 1) * 26))
		local labelText = _G["HolyOrdersOptCheck" .. i .. "Text"]
		labelText:SetText(item.label)
		-- cap width so long labels wrap onto a second line instead of spilling
		labelText:SetWidth(LABEL_WIDTH)
		labelText:SetWordWrap(true)
		labelText:SetJustifyH("LEFT")
		check:SetScript("OnClick", function(self)
			item.set(Options.Ensure(), self:GetChecked() and true or false)
			Refresh()
		end)
		checks[i] = check
	end

	local buttonsTop = topOffset + #ITEMS * 26 + 8

	panel.growBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	panel.growBtn:SetSize(240, 22)
	panel.growBtn:SetPoint("TOPLEFT", 16, -buttonsTop)
	panel.growBtn:SetScript("OnClick", function()
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

	panel.petBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	panel.petBtn:SetSize(240, 22)
	panel.petBtn:SetPoint("TOPLEFT", 16, -(buttonsTop + 28))
	panel.petBtn:SetScript("OnClick", function()
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
		RefreshAll()
	end)

	-- fly-out direction: which side of a class button the member panel opens on
	panel.flyoutBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	panel.flyoutBtn:SetSize(240, 22)
	panel.flyoutBtn:SetPoint("TOPLEFT", 16, -(buttonsTop + 112))
	panel.flyoutBtn:SetScript("OnClick", function()
		local o = Options.Ensure()
		local nextDir = FLYOUT_CYCLE[1]
		for i, dir in ipairs(FLYOUT_CYCLE) do
			if dir == (o.bar.flyout or "left") then
				nextDir = FLYOUT_CYCLE[i + 1] or FLYOUT_CYCLE[1]
				break
			end
		end
		o.bar.flyout = nextDir
		Refresh()
		if HO.Bar and HO.Bar.Refresh then
			HO.Bar.Refresh() -- re-anchors the panels out of combat
		end
	end)

	-- cast bar scale: cycles a preset list; the bar is a protected frame, so
	-- ApplyScale is combat-guarded and self-applies on PLAYER_REGEN_ENABLED
	panel.barScaleBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	panel.barScaleBtn:SetSize(240, 22)
	panel.barScaleBtn:SetPoint("TOPLEFT", 16, -(buttonsTop + 56))
	panel.barScaleBtn:SetScript("OnClick", function()
		local o = Options.Ensure()
		o.bar.scale = NextScale(o.bar.scale)
		if HO.Bar and HO.Bar.ApplyScale then
			HO.Bar.ApplyScale()
		end
		Refresh()
	end)

	-- window scale: applies to the assignment window and the buff-request window
	panel.winScaleBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	panel.winScaleBtn:SetSize(240, 22)
	panel.winScaleBtn:SetPoint("TOPLEFT", 16, -(buttonsTop + 84))
	panel.winScaleBtn:SetScript("OnClick", function()
		local o = Options.Ensure()
		o.window = o.window or {}
		o.window.scale = NextScale(o.window.scale)
		if HO.Window and HO.Window.ApplyScale then
			HO.Window.ApplyScale()
		end
		if HO.Request and HO.Request.ApplyScale then
			HO.Request.ApplyScale()
		end
		Refresh()
	end)

	-- register with whichever options system this client provides
	if InterfaceOptions_AddCategory then
		InterfaceOptions_AddCategory(panel)
	elseif Settings and Settings.RegisterCanvasLayoutCategory then
		category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
		Settings.RegisterAddOnCategory(category)
	end
end

-- opens the Blizzard options at our category (kept as the public entry point;
-- other modules and /ho opt call this)
function Options.Toggle()
	Options.Create()
	if InterfaceOptionsFrame_OpenToCategory then
		-- classic quirk: the first call may not navigate on a cold frame
		InterfaceOptionsFrame_OpenToCategory(panel)
		InterfaceOptionsFrame_OpenToCategory(panel)
	elseif Settings and Settings.OpenToCategory and category then
		Settings.OpenToCategory(category.ID or category:GetID())
	end
end

HO.RegisterEvent("PLAYER_LOGIN", Options.Create)
