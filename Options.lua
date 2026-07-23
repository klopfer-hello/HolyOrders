-- HolyOrders — options panel (mounted in Blizzard's Interface Options)

local HO = HolyOrders
local Options = {}
HO.Options = Options
local L = HO.L

local PET_CYCLE = { 2, 1, 3 } -- Might > Wisdom > Kings
local GROW_CYCLE = { "right", "left", "down", "up" }
local FLYOUT_CYCLE = { "left", "right", "up", "down" }

-- switching the skin rebuilds every frame's chrome, which only happens at UI
-- load — so offer the reload right away (or let the user do it later)
StaticPopupDialogs["HOLYORDERS_SKIN_RELOAD"] = {
	text = "HolyOrders: %s",
	button1 = _G.RELOADUI or "Reload UI",
	button2 = _G.CANCEL or "Cancel",
	OnAccept = function()
		ReloadUI()
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3, -- avoid tainting the default popup slots
}

function Options.PromptSkinReload()
	local HOL = HO.L
	StaticPopup_Show("HOLYORDERS_SKIN_RELOAD", HOL["the new skin applies after a UI reload — reload now?"])
end
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

local function Refresh()
	if not panel or not panel:IsShown() then
		return
	end
	local o = Options.Ensure()
	for i, item in ipairs(ITEMS) do
		checks[i]:SetChecked(item.get(o) and true or false)
	end
	local blessing = HO.Data.blessings[o.pets.blessing or 2]
	panel.petBtn.value:SetText(blessing and (blessing.name or blessing.key) or "?")
	panel.growBtn.value:SetText(o.bar.grow or "right")
	panel.flyoutBtn.value:SetText(o.bar.flyout or "left")
	panel.skinBtn.value:SetText(o.skin or "default")
	panel.barScaleBtn.value:SetText(string.format("%d%%", math.floor((o.bar.scale or 1) * 100 + 0.5)))
	panel.winScaleBtn.value:SetText(string.format("%d%%", math.floor(((o.window and o.window.scale) or 1) * 100 + 0.5)))
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

	-- drop-down selects -----------------------------------------------------
	-- own lightweight widget instead of the Blizzard dropdown: the shared
	-- dropdown implementation is a classic taint vector (risky next to our
	-- secure cast frames), and this one is a plain button + choice list
	local openList -- the currently open choice list, if any
	local function CloseOpenList()
		if openList then
			openList:Hide()
			openList = nil
		end
	end
	panel:HookScript("OnHide", CloseOpenList)

	local SELECT_ROW_H = 20
	local WHITE = "Interface\\Buttons\\WHITE8x8"
	-- a dropdown select in the familiar options style: a small label above a
	-- dark value box with an arrow; clicking the box opens the choice list
	-- below it. choicesFn returns {value, text, current} rows; the current
	-- value text in the box is maintained by Refresh via btn.value.
	local function CreateSelect(yOffset, labelKey, choicesFn, onSelect)
		local label = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		label:SetPoint("TOPLEFT", 16, -yOffset)
		label:SetText(L[labelKey])
		local btn = CreateFrame("Button", nil, panel, "BackdropTemplate")
		btn:SetSize(240, 24)
		btn:SetPoint("TOPLEFT", 16, -(yOffset + 14))
		if btn.SetBackdrop then
			btn:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
			btn:SetBackdropColor(0.08, 0.08, 0.10, 0.95)
			btn:SetBackdropBorderColor(0.35, 0.35, 0.40, 1)
		end
		btn.value = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		btn.value:SetPoint("LEFT", 8, 0)
		btn.arrow = btn:CreateTexture(nil, "ARTWORK")
		btn.arrow:SetSize(18, 18)
		btn.arrow:SetPoint("RIGHT", -3, 0)
		btn.arrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
		btn.hl = btn:CreateTexture(nil, "HIGHLIGHT")
		btn.hl:SetAllPoints()
		btn.hl:SetColorTexture(1, 1, 1, 0.05)
		local list = CreateFrame("Frame", nil, panel, "BackdropTemplate")
		list:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -1)
		list:SetWidth(240)
		list:SetFrameStrata("DIALOG")
		list:Hide()
		list.bg = list:CreateTexture(nil, "BACKGROUND")
		list.bg:SetAllPoints()
		list.bg:SetColorTexture(0.06, 0.06, 0.08, 0.97)
		if list.SetBackdrop then
			list:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
			list:SetBackdropBorderColor(HO.Colors.rgb("goldDeep", 1))
		end
		list.rows = {}
		btn:SetScript("OnClick", function()
			if list:IsShown() then
				CloseOpenList()
				return
			end
			CloseOpenList()
			local choices = choicesFn()
			for i, choice in ipairs(choices) do
				local row = list.rows[i]
				if not row then
					row = CreateFrame("Button", nil, list)
					row:SetSize(238, SELECT_ROW_H)
					row:SetPoint("TOPLEFT", 1, -(1 + (i - 1) * SELECT_ROW_H))
					row.hl = row:CreateTexture(nil, "HIGHLIGHT")
					row.hl:SetAllPoints()
					row.hl:SetColorTexture(1, 1, 1, 0.08)
					row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
					row.text:SetPoint("LEFT", 8, 0)
					row:SetScript("OnClick", function(self)
						CloseOpenList()
						onSelect(self.value)
						Refresh()
					end)
					list.rows[i] = row
				end
				row.value = choice.value
				row.text:SetText(choice.text)
				if choice.current then
					row.text:SetTextColor(HO.Colors.rgb("goldBright"))
				else
					row.text:SetTextColor(0.9, 0.9, 0.9)
				end
				row:Show()
			end
			for i = #choices + 1, #list.rows do
				list.rows[i]:Hide()
			end
			list:SetHeight(2 + #choices * SELECT_ROW_H)
			list:Show()
			openList = list
		end)
		return btn
	end

	-- growth direction of the cast bar
	panel.growBtn = CreateSelect(buttonsTop, "Bar grows", function()
		local o = Options.Ensure()
		local choices = {}
		for _, dir in ipairs(GROW_CYCLE) do
			choices[#choices + 1] = { value = dir, text = dir, current = (o.bar.grow or "right") == dir }
		end
		return choices
	end, function(value)
		Options.Ensure().bar.grow = value
		HO.Bar.Refresh()
	end)

	-- pet blessing choice (localized blessing names)
	panel.petBtn = CreateSelect(buttonsTop + 40, "Pet blessing", function()
		local o = Options.Ensure()
		local choices = {}
		for _, id in ipairs(PET_CYCLE) do
			local blessing = HO.Data.blessings[id]
			choices[#choices + 1] = {
				value = id,
				text = blessing and (blessing.name or blessing.key) or tostring(id),
				current = (o.pets.blessing or 2) == id,
			}
		end
		return choices
	end, function(value)
		Options.Ensure().pets.blessing = value
		RefreshAll()
	end)

	-- cast bar scale: the bar is a protected frame, so ApplyScale is
	-- combat-guarded and self-applies on PLAYER_REGEN_ENABLED
	panel.barScaleBtn = CreateSelect(buttonsTop + 80, "Cast bar scale", function()
		local o = Options.Ensure()
		local choices = {}
		for _, s in ipairs(SCALE_CYCLE) do
			choices[#choices + 1] = {
				value = s,
				text = string.format("%d%%", math.floor(s * 100 + 0.5)),
				current = (o.bar.scale or 1.0) == s,
			}
		end
		return choices
	end, function(value)
		Options.Ensure().bar.scale = value
		if HO.Bar and HO.Bar.ApplyScale then
			HO.Bar.ApplyScale()
		end
	end)

	-- window scale: applies to the assignment window and the buff-request window
	panel.winScaleBtn = CreateSelect(buttonsTop + 120, "Window scale", function()
		local o = Options.Ensure()
		local choices = {}
		for _, s in ipairs(SCALE_CYCLE) do
			choices[#choices + 1] = {
				value = s,
				text = string.format("%d%%", math.floor(s * 100 + 0.5)),
				current = ((o.window and o.window.scale) or 1.0) == s,
			}
		end
		return choices
	end, function(value)
		local o = Options.Ensure()
		o.window = o.window or {}
		o.window.scale = value
		if HO.Window and HO.Window.ApplyScale then
			HO.Window.ApplyScale()
		end
		if HO.Request and HO.Request.ApplyScale then
			HO.Request.ApplyScale()
		end
	end)

	-- fly-out direction: which side of a class button the member panel opens on
	panel.flyoutBtn = CreateSelect(buttonsTop + 160, "Fly-out opens", function()
		local o = Options.Ensure()
		local choices = {}
		for _, dir in ipairs(FLYOUT_CYCLE) do
			choices[#choices + 1] = { value = dir, text = dir, current = (o.bar.flyout or "left") == dir }
		end
		return choices
	end, function(value)
		Options.Ensure().bar.flyout = value
		if HO.Bar and HO.Bar.Refresh then
			HO.Bar.Refresh() -- re-anchors the panels out of combat
		end
	end)

	-- UI skin: chrome is built at load, so a change prompts for a reload
	panel.skinBtn = CreateSelect(buttonsTop + 200, "Skin", function()
		local o = Options.Ensure()
		local choices = {}
		for _, s in ipairs(HO.Skin.SKINS) do
			choices[#choices + 1] = { value = s, text = s, current = (o.skin or "default") == s }
		end
		return choices
	end, function(value)
		Options.Ensure().skin = value
		Options.PromptSkinReload()
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
