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
local NONE_ICON = "Interface\\Buttons\\UI-GroupLoot-Pass-Up" -- "no aura" placeholder (matches the window)

local CLASS_ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

local bar, handle, ticker
local auraButton -- dedicated self-cast aura slot at the origin end (next to the handle)
local buttons = {}
local lastGrow
local pendingReset

-- arranges handle and buttons for the configured growth direction; must only
-- run out of combat (buttons are protected frames)
local function LayoutBar()
	local grow = HO.db.options.bar and HO.db.options.bar.grow or "right"
	local horizontal = (grow == "left" or grow == "right")
	-- +1 slot for the always-present aura button that sits at the origin end
	local length = HANDLE_WIDTH + GAP + (MAX_BUTTONS + 1) * (BUTTON_SIZE + GAP)
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
	-- anchor a frame at a linear distance from the origin end, for the current
	-- grow direction (the origin end is always where the handle sits)
	local function PlaceAtOffset(frame, offset)
		frame:ClearAllPoints()
		if grow == "right" then
			frame:SetPoint("LEFT", bar, "LEFT", offset, 0)
		elseif grow == "left" then
			frame:SetPoint("RIGHT", bar, "RIGHT", -offset, 0)
		elseif grow == "down" then
			frame:SetPoint("TOP", bar, "TOP", 0, -offset)
		else
			frame:SetPoint("BOTTOM", bar, "BOTTOM", 0, offset)
		end
	end
	-- the aura button takes the first slot (slot 0) right after the handle; the
	-- class buttons follow, shifted one slot along
	if auraButton then
		PlaceAtOffset(auraButton, HANDLE_WIDTH + GAP)
	end
	for i, btn in ipairs(buttons) do
		local offset = HANDLE_WIDTH + GAP + i * (BUTTON_SIZE + GAP)
		PlaceAtOffset(btn, offset)
		-- in vertical growth the buttons stack with only GAP between them, so
		-- a timer under the icon overlaps the neighbour; put it to the side
		-- (clear of the handle, which sits at the top/bottom origin)
		btn.timer:ClearAllPoints()
		if horizontal then
			btn.timer:SetPoint("TOP", btn, "BOTTOM", 0, -1)
		else
			btn.timer:SetPoint("LEFT", btn, "RIGHT", 1, 0)
		end
	end
	lastGrow = grow
end

local function BarOptions()
	HO.db.options.bar = HO.db.options.bar or {}
	return HO.db.options.bar
end

-- the client re-anchors a dragged frame to the nearest corner, so the full
-- anchor (point + relativePoint + offsets) must be saved, not just offsets
local function SavePosition()
	local opts = BarOptions()
	local point, _, relativePoint, x, y = bar:GetPoint()
	opts.point, opts.relPoint, opts.x, opts.y = point, relativePoint, x, y
end

function Bar.ResetPosition()
	-- the bar is a protected frame (secure buttons anchor to it); moving it in
	-- combat would taint, so defer to PLAYER_REGEN_ENABLED
	if InCombatLockdown() then
		pendingReset = true
		HO.Print(L["can't move the bar in combat — will reset it after combat"])
		return
	end
	local opts = BarOptions()
	opts.point, opts.relPoint, opts.x, opts.y = nil, nil, nil, nil
	bar:ClearAllPoints()
	bar:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
end

local function RestorePosition()
	local opts = BarOptions()
	bar:ClearAllPoints()
	if opts.point then
		bar:SetPoint(opts.point, UIParent, opts.relPoint or opts.point, opts.x or 0, opts.y or 0)
	else
		bar:SetPoint("CENTER", UIParent, "CENTER", opts.x or 0, opts.y or -180)
	end
end

-- frame strata is user-configurable: default "LOW" keeps the bar below standard
-- Blizzard windows (calendar, group finder) yet above the world; opt-in "HIGH"
-- lifts it over unit-frame addons (VuhDo etc.) that would otherwise cover it.
-- The bar is implicitly protected (secure buttons anchor to it), so SetFrameStrata
-- may only run out of combat; a combat-time toggle re-applies on the next
-- PLAYER_REGEN_ENABLED refresh.
function Bar.ApplyStrata()
	if not bar or InCombatLockdown() then
		return
	end
	bar:SetFrameStrata(BarOptions().front and "HIGH" or "LOW")
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

-- per-class fly-out ----------------------------------------------------------
-- A NON-secure panel (parented to UIParent, never into the secure bar) anchored
-- visually to a class button. It lists that class's roster members with the
-- blessing each is assigned and a coloured status border — green = has it,
-- red = assigned but missing, neutral = no assignment or out of range (status
-- unknowable). Wheeling a row re-assigns that member's blessing and right-click
-- clears it, exactly like the assignment window's member cell (same Plan calls,
-- so it stays synced). It never casts, so it may be shown/hidden freely.
local flyout
local flyoutRows = {}
local flyoutClass -- classToken currently displayed, nil when closed
local FLYOUT_ROW_H = 30
local FLYOUT_HEADER = 20
local FLYOUT_FOOTER = 5 -- bottom padding only (no hint line)
local FLYOUT_PAD = 6
local FLYOUT_WIDTH = 190
local FLYOUT_BORDER = 2
local FLYOUT_ICON = FLYOUT_ROW_H - 6

local function FindButtonForClass(classToken)
	for i = 1, MAX_BUTTONS do
		local btn = buttons[i]
		if btn:IsShown() and btn.task and btn.task.classToken == classToken then
			return btn
		end
	end
end

local function FlyoutBlessingName(id)
	local b = HO.Data.blessings[id]
	return b and (b.name or b.key) or tostring(id)
end

local function SetRowBorder(row, r, g, b)
	for _, tex in pairs(row.borders) do
		if r then
			tex:SetColorTexture(r, g, b, 0.9)
			tex:Show()
		else
			tex:Hide()
		end
	end
end

-- ring of override blessings for the player: every castable blessing in id order,
-- then none (0). Mirrors the assignment window's member-cell cycle (same id set
-- and order, overrides bypass eligibility); wheel-up advances, wheel-down retreats.
local function CycleMemberOverride(me, current, delta)
	local ring = {}
	for id = 1, HO.Data.NUM_BLESSINGS do
		if HO.Planner.IsAvailable(me, id) then
			ring[#ring + 1] = id
		end
	end
	ring[#ring + 1] = 0 -- none closes the ring
	local cur = current or 0
	local idx = #ring -- default to the none slot (also covers an unknown current)
	for i, id in ipairs(ring) do
		if id == cur then
			idx = i
			break
		end
	end
	local nextIdx = ((idx - 1 + delta) % #ring) + 1
	return ring[nextIdx]
end

-- apply an override change through the SAME public path the assignment window's
-- member cell uses, so the edit syncs and the member "liking" stays consistent.
-- Pets never record a liking (a pet blessing is an option, not a member wish).
local function ApplyMemberOverride(memberName, isPet, newID)
	local me = HO.FullName("player")
	if not me then
		return
	end
	HO.Plan.SetPlayerOverride(me, memberName, newID)
	if not isPet then
		HO.Plan.SetMemberPref(memberName, (newID and newID ~= 0) and newID or nil)
	end
	-- Bar.Refresh recomputes the engine and re-renders the fly-out (via its hook);
	-- refresh the window too so an open assignment grid stays in sync
	Bar.Refresh()
	if HO.Window and HO.Window.Refresh then
		HO.Window.Refresh()
	end
end

local function AcquireFlyoutRow(index)
	local row = flyoutRows[index]
	if row then
		return row
	end
	row = CreateFrame("Button", nil, flyout)
	row:SetSize(FLYOUT_WIDTH - 2 * FLYOUT_PAD, FLYOUT_ROW_H)
	row:RegisterForClicks("RightButtonUp")
	row:EnableMouseWheel(true)
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints()
	row.bg:SetColorTexture(1, 1, 1, 0.05)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(FLYOUT_ICON, FLYOUT_ICON)
	row.icon:SetPoint("LEFT", 3, 0)
	row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
	row.name:SetPoint("RIGHT", -3, 0)
	row.name:SetJustifyH("LEFT")
	-- four thin edge textures form the status border (recoloured per refresh)
	row.borders = {}
	local top = row:CreateTexture(nil, "OVERLAY")
	top:SetPoint("TOPLEFT")
	top:SetPoint("TOPRIGHT")
	top:SetHeight(FLYOUT_BORDER)
	local bottom = row:CreateTexture(nil, "OVERLAY")
	bottom:SetPoint("BOTTOMLEFT")
	bottom:SetPoint("BOTTOMRIGHT")
	bottom:SetHeight(FLYOUT_BORDER)
	local left = row:CreateTexture(nil, "OVERLAY")
	left:SetPoint("TOPLEFT")
	left:SetPoint("BOTTOMLEFT")
	left:SetWidth(FLYOUT_BORDER)
	local right = row:CreateTexture(nil, "OVERLAY")
	right:SetPoint("TOPRIGHT")
	right:SetPoint("BOTTOMRIGHT")
	right:SetWidth(FLYOUT_BORDER)
	row.borders.top, row.borders.bottom, row.borders.left, row.borders.right = top, bottom, left, right
	row:SetScript("OnMouseWheel", function(self, delta)
		if not self.memberName then
			return
		end
		if InCombatLockdown() then
			-- mirror the class wheel's combat guard: the resulting secure-attribute
			-- update on the bar must wait for combat end anyway
			HO.Print(L["assignment changes apply after combat"])
			return
		end
		local me = HO.FullName("player")
		if not me then
			return
		end
		local plan = HO.Plan.Active()
		local cur = plan.player[me] and plan.player[me][self.memberName]
		local newID = CycleMemberOverride(me, cur, delta > 0 and 1 or -1)
		ApplyMemberOverride(self.memberName, self.isPet, newID)
	end)
	row:SetScript("OnClick", function(self, mouseBtn)
		if mouseBtn ~= "RightButton" or not self.memberName then
			return
		end
		if InCombatLockdown() then
			HO.Print(L["assignment changes apply after combat"])
			return
		end
		ApplyMemberOverride(self.memberName, self.isPet, 0) -- clear the override (and liking)
	end)
	row:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(self.memberName or "?")
		if self.blessingID then
			GameTooltip:AddLine(FlyoutBlessingName(self.blessingID), 1, 1, 1)
			if self.inRange == false then
				GameTooltip:AddLine(L["out of range"], 0.7, 0.7, 0.7)
			elseif self.hasBuff == true then
				GameTooltip:AddLine(L["has the blessing"], 0.6, 1, 0.6)
			elseif self.hasBuff == false then
				GameTooltip:AddLine(L["missing the blessing"], 1, 0.4, 0.4)
			end
		else
			GameTooltip:AddLine(L["no buff assigned"], 0.8, 0.8, 0.8)
		end
		GameTooltip:AddLine(L["wheel: change blessing — right-click: clear"], 0.8, 0.8, 0.8)
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	flyoutRows[index] = row
	return row
end

local function CreateFlyout()
	if flyout then
		return
	end
	-- parented to UIParent (NOT the secure bar) so it can never taint the cast
	-- buttons; it is a plain frame that only edits assignments and shows status
	flyout = CreateFrame("Frame", "HolyOrdersFlyout", UIParent)
	flyout:SetWidth(FLYOUT_WIDTH)
	flyout:SetHeight(FLYOUT_HEADER + FLYOUT_ROW_H + FLYOUT_FOOTER)
	flyout:EnableMouse(true) -- swallow clicks so they don't fall through to the world
	flyout:SetClampedToScreen(true)
	flyout.bg = flyout:CreateTexture(nil, "BACKGROUND")
	flyout.bg:SetAllPoints()
	flyout.bg:SetColorTexture(0.05, 0.05, 0.08, 0.94)
	flyout.title = flyout:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	flyout.title:SetPoint("TOPLEFT", FLYOUT_PAD, -4)
	flyout.title:SetPoint("TOPRIGHT", -FLYOUT_PAD, -4)
	flyout.title:SetJustifyH("LEFT")
	flyout:Hide()
end

local function FlyoutHide()
	flyoutClass = nil
	if flyout then
		flyout:Hide()
	end
end

-- rebuild the fly-out's rows from the engine's live per-member status; called on
-- every bar refresh while it is open so the green/red borders update in place
local function FlyoutRefresh()
	if not flyoutClass or not flyout or not flyout:IsShown() then
		return
	end
	-- re-find the button that currently represents this class; if the class left
	-- the bar (or the bar hid), close the fly-out
	local anchor = FindButtonForClass(flyoutClass)
	if not anchor then
		FlyoutHide()
		return
	end
	flyout:ClearAllPoints()
	-- fly out to the LEFT of the class button (top-aligned), like the classic
	-- paladin buff addons; SetClampedToScreen keeps it on-screen near an edge
	flyout:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -4, 0)
	flyout.title:SetText(flyoutClass)

	local members = HO.Engine.ClassMembers(flyoutClass)
	local count = 0
	for i, m in ipairs(members) do
		count = i
		local row = AcquireFlyoutRow(i)
		row.memberName = m.name
		row.isPet = m.isPet
		row.blessingID = m.blessingID
		row.hasBuff = m.hasBuff
		row.inRange = m.inRange
		local blessing = m.blessingID and HO.Data.blessings[m.blessingID]
		row.icon:SetTexture((blessing and blessing.icon) or NONE_ICON)
		local short = m.name:match("^([^%-]+)") or m.name
		if m.isPet then
			local ownerShort = m.owner and (m.owner:match("^([^%-]+)") or m.owner) or "?"
			row.name:SetText(short .. " |cff9d9d9d" .. string.format(L["(pet of %s)"], ownerShort) .. "|r")
		else
			row.name:SetText(short)
		end
		-- status border: out-of-range is unknowable, so neutral/dim rather than red
		if not m.blessingID then
			SetRowBorder(row) -- no assignment → neutral
			row.icon:SetDesaturated(true)
			row.icon:SetAlpha(0.8)
		elseif m.inRange == false then
			SetRowBorder(row) -- can't know the buff at range → neutral, dimmed
			row.icon:SetDesaturated(false)
			row.icon:SetAlpha(0.35)
		elseif m.hasBuff == true then
			SetRowBorder(row, 0.10, 0.80, 0.10) -- green: has it
			row.icon:SetDesaturated(false)
			row.icon:SetAlpha(1)
		elseif m.hasBuff == false then
			SetRowBorder(row, 0.85, 0.15, 0.15) -- red: assigned but missing
			row.icon:SetDesaturated(false)
			row.icon:SetAlpha(1)
		else
			SetRowBorder(row) -- status unknown → neutral
			row.icon:SetDesaturated(false)
			row.icon:SetAlpha(1)
		end
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", flyout, "TOPLEFT", FLYOUT_PAD, -(FLYOUT_HEADER + (i - 1) * FLYOUT_ROW_H))
		row:Show()
	end
	for i = count + 1, #flyoutRows do
		flyoutRows[i]:Hide()
	end

	local rows = count > 0 and count or 1 -- keep a minimum height when empty
	flyout:SetHeight(FLYOUT_HEADER + rows * FLYOUT_ROW_H + FLYOUT_FOOTER)
	-- strata just above the bar so the fly-out always reads over it
	local barStrata = bar and bar:GetFrameStrata() or "LOW"
	flyout:SetFrameStrata(barStrata == "HIGH" and "DIALOG" or "MEDIUM")
	flyout:SetToplevel(true)
end

local function FlyoutOpen(classToken)
	if not classToken then
		return
	end
	CreateFlyout()
	flyoutClass = classToken
	flyout:Show()
	FlyoutRefresh()
end

local function FlyoutToggle(classToken)
	if not classToken then
		return
	end
	if flyoutClass == classToken and flyout and flyout:IsShown() then
		FlyoutHide()
	else
		FlyoutOpen(classToken)
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
	-- shift-left opens the per-class fly-out instead of casting: an empty
	-- shift-type1 (looked up before type1 when Shift is held) suppresses the
	-- cast, and PreClick opens the NON-secure fly-out. Set once here, out of
	-- combat; it is static and never touched again, so it never taints the bar.
	btn:SetAttribute("shift-type1", "")
	btn:SetScript("PreClick", function(self, mouseBtn, down)
		if down and mouseBtn == "LeftButton" and IsShiftKeyDown() and self.task then
			FlyoutToggle(self.task.classToken)
		end
	end)
	-- wheel: cycle my class assignment (out of combat; syncs + updates window)
	btn:EnableMouseWheel(true)
	btn:SetScript("OnMouseWheel", function(self, delta)
		if InCombatLockdown() then
			return
		end
		local task = self.task
		if task then
			-- a duty that exists only as a single-member override has no
			-- class-wide assignment to cycle; wheeling would fabricate one
			if task.overrideOnly then
				HO.Print(L["this duty is a single-member override — change it in the assignment window"])
				return
			end
			HO.Window.CycleMyClass(task.classToken, delta > 0 and 1 or -1)
		end
	end)
	btn.hoBarButton = true -- marks our buttons for the tooltip re-render check

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
		if task.noneAssigned then
			GameTooltip:AddLine(L["no blessing assigned — wheel to assign"], 0.8, 0.8, 0.8)
			GameTooltip:Show()
			return
		end
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

-- wheel-cycle MY aura through the known auras then none (out of combat only,
-- like the class wheel); edits my own assignment, which syncs and refreshes.
local function CycleMyAura(delta)
	local me = HO.FullName("player")
	if not me then
		return
	end
	-- ring: known auras in id order, then none (0). Wheel-up advances, down retreats.
	local ring = HO.Data.KnownAuras()
	ring[#ring + 1] = 0
	local cur = HO.Plan.GetAura(me) or 0
	local idx = #ring -- default to the none slot (also covers an unknown assigned aura)
	for i, id in ipairs(ring) do
		if id == cur then
			idx = i
			break
		end
	end
	local nextIdx = ((idx - 1 + delta) % #ring) + 1
	HO.Plan.SetAura(me, ring[nextIdx])
	Bar.Refresh()
	HO.Window.Refresh()
end

-- the always-present self-cast aura slot; sits at the origin end so it reads as
-- "my aura", separate from the class-duty buttons
local function CreateAuraButton()
	local btn = CreateFrame("Button", "HolyOrdersBarAura", bar, "SecureActionButtonTemplate")
	btn:SetSize(BUTTON_SIZE, BUTTON_SIZE)
	btn:RegisterForClicks("AnyDown", "AnyUp")
	-- auras are self-cast; unit1 never changes, so it is safe to set once here.
	-- spell1 (the aura name) is set from RefreshAuraButton, out of combat only.
	btn:SetAttribute("type1", "spell")
	btn:SetAttribute("unit1", "player")
	btn:EnableMouseWheel(true)
	btn:SetScript("OnMouseWheel", function(_, delta)
		if InCombatLockdown() then
			return -- changing the secure spell attribute is forbidden in combat
		end
		CycleMyAura(delta > 0 and 1 or -1)
	end)
	btn.hoAuraButton = true -- marks the aura button for the tooltip re-render check

	btn.bg = btn:CreateTexture(nil, "BACKGROUND")
	btn.bg:SetAllPoints()
	btn.bg:SetColorTexture(0.10, 0.10, 0.32, 0.80) -- blue tint distinguishes it from duty buttons

	btn.icon = btn:CreateTexture(nil, "ARTWORK")
	btn.icon:SetPoint("TOPLEFT", 2, -2)
	btn.icon:SetPoint("BOTTOMRIGHT", -2, 2)
	btn.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	btn.label:SetPoint("BOTTOM", btn, "BOTTOM", 0, 1)
	btn.label:SetText(L["Aura"])

	btn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(L["My Aura"])
		local me = HO.FullName("player")
		local id = me and HO.Plan.GetAura(me)
		local name = id and HO.Data.AuraName(id)
		if name then
			GameTooltip:AddLine(name, 1, 1, 1)
		else
			GameTooltip:AddLine(L["no aura assigned"], 0.8, 0.8, 0.8)
		end
		GameTooltip:AddLine(L["mouse wheel: change your aura"], 0.8, 0.8, 0.8)
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	return btn
end

-- aura-button visuals + secure self-cast attribute. The attribute is written
-- only out of combat; the combat branch refreshes the icon alone.
local function RefreshAuraButton()
	if not auraButton then
		return
	end
	local me = HO.FullName("player")
	local id = me and HO.Plan.GetAura(me)
	local aura = id and HO.Data.auras[id]
	local castable = aura and aura.known and aura.name
	if InCombatLockdown() then
		auraButton.icon:SetTexture((castable and aura.icon) or NONE_ICON)
		auraButton.icon:SetDesaturated(false)
		return
	end
	if castable then
		auraButton:SetAttribute("spell1", aura.name)
		auraButton.icon:SetTexture(aura.icon)
	else
		-- none, or an assigned aura this paladin does not know: clear the cast and
		-- show the placeholder icon (same as the class-duty none marker)
		auraButton:SetAttribute("spell1", nil)
		auraButton.icon:SetTexture(NONE_ICON)
	end
	auraButton.icon:SetDesaturated(false)
end

function Bar.Create()
	if bar then
		return
	end
	bar = CreateFrame("Frame", "HolyOrdersBar", UIParent)
	bar:SetMovable(true)
	bar:SetClampedToScreen(true)
	bar:SetFrameStrata(BarOptions().front and "HIGH" or "LOW") -- see Bar.ApplyStrata

	handle = CreateFrame("Frame", nil, bar)
	handle:SetPoint("TOPLEFT", 0, 0)
	handle:SetSize(HANDLE_WIDTH, BUTTON_SIZE)
	handle:EnableMouse(true)
	handle:RegisterForDrag("LeftButton")
	handle.tex = handle:CreateTexture(nil, "BACKGROUND")
	handle.tex:SetAllPoints()
	handle.tex:SetColorTexture(0.94, 0.78, 0.09, 0.55)
	handle:SetScript("OnDragStart", function()
		if InCombatLockdown() then
			return -- moving the protected bar in combat would taint it
		end
		if not BarOptions().locked then
			bar:StartMoving()
		end
	end)
	handle:SetScript("OnDragStop", function()
		if InCombatLockdown() then
			return
		end
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
	auraButton = CreateAuraButton() -- always present; follows the bar's visibility
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
		RefreshAuraButton() -- icon only in combat; never touches attributes
		FlyoutRefresh() -- live green/red status is safe (and useful) in combat
		return
	end

	if (BarOptions().grow or "right") ~= lastGrow then
		-- the frame changes shape (long ↔ tall) while keeping its corner anchor,
		-- which would fling the whole bar ~320 px; record the handle's screen
		-- position (the handle is the origin end in every mode, so users read it
		-- as "the" location) and shift the bar so the handle stays put
		local hLeft, hTop = handle:GetLeft(), handle:GetTop()
		LayoutBar()
		local nhLeft, nhTop = handle:GetLeft(), handle:GetTop()
		if hLeft and hTop and nhLeft and nhTop then
			local point, _, relPoint, x, y = bar:GetPoint()
			if point then
				bar:ClearAllPoints()
				bar:SetPoint(point, UIParent, relPoint or point,
					(x or 0) + (hLeft - nhLeft), (y or 0) + (hTop - nhTop))
				SavePosition()
			end
		end
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
			-- placeholder (none) buttons show their icon at full colour; ordinary
			-- passive tasks (nothing to cast right now) stay desaturated
			btn.icon:SetDesaturated(task.spellName == nil and not task.noneAssigned)
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

	RefreshAuraButton()
	local isPally = select(2, UnitClass("player")) == "PALADIN"
	-- the aura slot is always relevant to a paladin, so the bar shows when there
	-- are duties OR an aura is assigned (so the aura button is reachable to wheel)
	local me = HO.FullName("player")
	local hasAura = me and HO.Plan.GetAura(me)
	if isPally and not BarOptions().hidden and (index > 0 or hasAura) then
		bar:Show()
		auraButton:Show()
		FlyoutRefresh() -- keep an open fly-out live and re-anchored
	else
		bar:Hide()
		FlyoutHide() -- the bar (and its buttons) went away; close the fly-out
	end

	-- a tooltip open over a button now describes freshly-reassigned data; a
	-- single owner check re-renders it (or hides it if the button went away)
	local owner = GameTooltip:GetOwner()
	if owner and owner.hoAuraButton then
		if owner:IsShown() then
			local onEnter = owner:GetScript("OnEnter")
			if onEnter then
				onEnter(owner)
			end
		else
			GameTooltip:Hide()
		end
	elseif owner and owner.hoBarButton then
		if owner:IsShown() and owner.task then
			local onEnter = owner:GetScript("OnEnter")
			if onEnter then
				onEnter(owner)
			end
		else
			GameTooltip:Hide()
		end
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
	if pendingReset then
		pendingReset = nil
		Bar.ResetPosition()
	end
	Bar.ApplyStrata() -- apply any strata change made during combat
	Bar.Refresh()
end)
