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
-- colour language for status borders: green = everyone has their assigned buff,
-- red = someone in range is missing it, amber = only expiring/out-of-range, and
-- YELLOW = a member requested a (different) buff that is not fulfilled yet.
-- Precedence on the class button: red missing > yellow request > amber > green
-- (a genuine missing buff is more urgent than a preference request).
local REQUEST_R, REQUEST_G, REQUEST_B = 0.95, 0.85, 0.15 -- yellow: an unmet buff request

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

-- colour the button's status border (nil = hide it): green all covered, red
-- someone in range missing, amber only-expiring or only-out-of-range
local function SetButtonBorder(btn, r, g, b)
	if not btn.borders then
		return
	end
	for _, tex in pairs(btn.borders) do
		if r then
			tex:SetColorTexture(r, g, b, 0.9)
			tex:Show()
		else
			tex:Hide()
		end
	end
end

-- does any member of this class have an UNMET request (a requested blessing that
-- differs from what this paladin assigns them)? Read-only over the display list.
local function ClassHasUnmetRequest(classToken)
	for _, m in ipairs(HO.Engine.ClassMembers(classToken)) do
		if m.requestID and m.blessingID ~= m.requestID then
			return true
		end
	end
	return false
end

-- button visuals that are safe to update in combat
local function UpdateButtonTexts(btn, task)
	btn.count:SetText(task.missing > 0 and tostring(task.missing) or "")
	btn.timer:SetText(FormatShort(task.minRemaining))
	-- in-range missing counts toward "red"; a purely out-of-range gap is amber,
	-- since it is not something you can act on right now
	local inRangeMissing = task.missing - (task.outOfRange or 0)
	-- yellow marker: any class member wants a buff this paladin isn't giving them
	local unmetRequest = ClassHasUnmetRequest(task.classToken)
	if task.noneAssigned then
		btn.bg:SetColorTexture(0, 0, 0, 0.65)
		-- even a none-assigned class can carry a request the paladin should notice
		if unmetRequest then
			SetButtonBorder(btn, REQUEST_R, REQUEST_G, REQUEST_B) -- yellow
		else
			SetButtonBorder(btn) -- no assignment: no status
		end
	elseif inRangeMissing > 0 then
		btn.bg:SetColorTexture(0.55, 0.10, 0.10, 0.85)
		SetButtonBorder(btn, 0.85, 0.15, 0.15) -- red (outranks a request)
	elseif unmetRequest then
		btn.bg:SetColorTexture(0, 0, 0, 0.65)
		SetButtonBorder(btn, REQUEST_R, REQUEST_G, REQUEST_B) -- yellow: unmet request
	elseif task.expiring > 0 or (task.outOfRange or 0) > 0 then
		btn.bg:SetColorTexture(0.55, 0.45, 0.05, 0.85)
		SetButtonBorder(btn, 0.90, 0.70, 0.10) -- amber
	else
		btn.bg:SetColorTexture(0, 0, 0, 0.65)
		SetButtonBorder(btn, 0.10, 0.80, 0.10) -- green: everyone covered
	end
end

-- per-class fly-out ----------------------------------------------------------
-- A NON-secure panel (parented to UIParent, never into the secure bar) anchored
-- visually to a class button. It lists that class's roster members with the
-- blessing each is assigned and a coloured status border — green = has it,
-- red = assigned but missing, neutral = no assignment or out of range (status
-- unknowable). Wheeling a row re-assigns that member's blessing and right-click
-- clears it, exactly like the assignment window's member cell (same Plan calls,
-- so it stays synced). Left-clicking a row casts that member's single blessing
-- (secure), so the rows are secure buttons configured only out of combat; the
-- whole fly-out is an OUT-OF-COMBAT tool and closes when combat starts.
local flyout
local flyoutRows = {}
local flyoutClass -- classToken currently displayed, nil when closed
local flyoutAnchor -- the class button the fly-out is currently anchored to

-- forward declarations so the hover-close timer and the class-button hover
-- handlers below can reference these before their definitions
local FlyoutHide, FlyoutRefresh, FlyoutShow

-- hover-close: the fly-out opens on mouseover of a class button and closes a
-- short moment after the cursor leaves BOTH the button and the fly-out, so you
-- can slide from the button into the fly-out without it vanishing
local flyoutCloseTimer
local function CancelClose()
	if flyoutCloseTimer then
		flyoutCloseTimer:Cancel()
		flyoutCloseTimer = nil
	end
end
local function MaybeClose()
	flyoutCloseTimer = nil
	if not flyout or not flyout:IsShown() then
		return
	end
	if flyout:IsMouseOver() or (flyoutAnchor and flyoutAnchor:IsMouseOver()) then
		return -- cursor is still over the fly-out or its class button
	end
	FlyoutHide()
end
local function ScheduleClose()
	CancelClose()
	flyoutCloseTimer = C_Timer.NewTimer(0.3, MaybeClose)
end
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

-- paint a row's member data, icon and green/red status border. All non-secure
-- (textures/fontstrings), so it is safe any time; also stores the fields the row
-- tooltip and right-click/wheel handlers read.
local function UpdateRowStatus(row, m)
	row.memberName = m.name
	row.isPet = m.isPet
	row.blessingID = m.blessingID
	row.hasBuff = m.hasBuff
	row.inRange = m.inRange
	row.requestID = m.requestID
	local blessing = m.blessingID and HO.Data.blessings[m.blessingID]
	row.icon:SetTexture((blessing and blessing.icon) or NONE_ICON)
	local short = m.name:match("^([^%-]+)") or m.name
	if m.isPet then
		local ownerShort = m.owner and (m.owner:match("^([^%-]+)") or m.owner) or "?"
		row.name:SetText(short .. " |cff9d9d9d" .. string.format(L["(pet of %s)"], ownerShort) .. "|r")
	else
		row.name:SetText(short)
	end
	-- out-of-range is unknowable, so neutral/dim rather than a false red
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
	-- request badge (right side): the requested blessing's icon. Dimmed/greenish
	-- once honoured (assigned == requested), full colour while still unmet. An
	-- unmet request also paints a YELLOW row border, overriding the green/red
	-- status border above so the paladin notices which member wants a buff.
	if m.requestID then
		local reqBlessing = HO.Data.blessings[m.requestID]
		row.reqBadge:SetTexture((reqBlessing and reqBlessing.icon) or NONE_ICON)
		if m.blessingID == m.requestID then
			row.reqBadge:SetVertexColor(0.4, 1, 0.4) -- satisfied: greenish
			row.reqBadge:SetAlpha(0.7)
		else
			row.reqBadge:SetVertexColor(1, 1, 1)
			row.reqBadge:SetAlpha(1)
			SetRowBorder(row, REQUEST_R, REQUEST_G, REQUEST_B) -- yellow: unmet request
		end
		row.reqBadge:Show()
	else
		row.reqBadge:Hide()
	end
end

-- clicking a row casts the member's assigned SINGLE blessing on them. Secure
-- attributes may only change out of combat; the caller guarantees that.
local function ConfigureRowSecure(row, m)
	local blessing = m.blessingID and HO.Data.blessings[m.blessingID]
	if blessing and blessing.name and m.unit then
		row:SetAttribute("type1", "spell")
		row:SetAttribute("spell1", blessing.name) -- the 10-min single
		row:SetAttribute("unit1", m.unit)
	else
		-- no assignment (or no unit): nothing to cast
		row:SetAttribute("type1", nil)
		row:SetAttribute("spell1", nil)
		row:SetAttribute("unit1", nil)
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
	-- keep the window in sync too. A fly-out edit is a per-member OVERRIDE, which
	-- only shows in the window's expanded member row — so expand that class so the
	-- change is actually visible, not silently hidden under a collapsed row.
	Bar.Refresh()
	if HO.Window then
		if HO.Window.Expand and flyoutClass then
			HO.Window.Expand(flyoutClass)
		elseif HO.Window.Refresh then
			HO.Window.Refresh()
		end
	end
end

local function AcquireFlyoutRow(index)
	local row = flyoutRows[index]
	if row then
		return row
	end
	-- secure so a left-click can cast the member's blessing; attributes are only
	-- ever set out of combat (the fly-out is an out-of-combat tool)
	row = CreateFrame("Button", nil, flyout, "SecureActionButtonTemplate")
	row:SetSize(FLYOUT_WIDTH - 2 * FLYOUT_PAD, FLYOUT_ROW_H)
	row:RegisterForClicks("AnyDown", "AnyUp")
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
	-- reserve room on the right for the request badge (shown only when requested)
	row.name:SetPoint("RIGHT", -(FLYOUT_ICON + 4), 0)
	row.name:SetJustifyH("LEFT")
	-- request badge: the requested blessing's icon on the row's right side, kept
	-- distinct from the assigned-blessing icon on the left. Non-secure texture.
	row.reqBadge = row:CreateTexture(nil, "OVERLAY")
	row.reqBadge:SetSize(FLYOUT_ICON, FLYOUT_ICON)
	row.reqBadge:SetPoint("RIGHT", -2, 0)
	row.reqBadge:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	row.reqBadge:Hide()
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
	-- left-click casts the secure blessing; right-click clears the assignment.
	-- PostClick runs after the (suppressed for right) secure action, so editing
	-- here never taints. Guard to fire the clear once, on the down edge.
	row:SetScript("PostClick", function(self, mouseBtn, down)
		if mouseBtn == "RightButton" and down and self.memberName then
			if InCombatLockdown() then
				HO.Print(L["assignment changes apply after combat"])
				return
			end
			ApplyMemberOverride(self.memberName, self.isPet, 0) -- clear the override (and liking)
		end
	end)
	-- no tooltip: the row already shows the blessing icon, the member name and a
	-- colour-coded border (green has / red missing / yellow requested). The enter
	-- and leave scripts only drive the fly-out's hover-open/close.
	row:SetScript("OnEnter", function()
		CancelClose() -- keep the fly-out open while the cursor is over a row
	end)
	row:SetScript("OnLeave", function()
		ScheduleClose()
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
	flyout:SetScript("OnEnter", CancelClose) -- cursor entered the fly-out: stay open
	flyout:SetScript("OnLeave", ScheduleClose)
	flyout.bg = flyout:CreateTexture(nil, "BACKGROUND")
	flyout.bg:SetAllPoints()
	flyout.bg:SetColorTexture(0.05, 0.05, 0.08, 0.94)
	flyout.title = flyout:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	flyout.title:SetPoint("TOPLEFT", FLYOUT_PAD, -4)
	flyout.title:SetPoint("TOPRIGHT", -FLYOUT_PAD, -4)
	flyout.title:SetJustifyH("LEFT")
	-- the fly-out is parented to UIParent, so it does NOT inherit the bar's scale;
	-- match it to the configured cast-bar scale here and in Bar.ApplyScale
	flyout:SetScale(HO.db.options.bar and HO.db.options.bar.scale or 1)
	flyout:Hide()
end

function FlyoutHide()
	flyoutClass = nil
	flyoutAnchor = nil
	CancelClose()
	if flyout then
		flyout:Hide()
	end
end

-- rebuild the fly-out from the engine's per-member status. The rows are secure,
-- so this may only run out of combat; the whole fly-out is closed in combat.
function FlyoutRefresh()
	if not flyoutClass or not flyout or not flyout:IsShown() then
		return
	end
	if InCombatLockdown() then
		return -- out-of-combat tool: never touch secure rows in combat
	end
	-- re-find the button that currently represents this class; if the class left
	-- the bar (or the bar hid), close the fly-out
	local anchor = FindButtonForClass(flyoutClass)
	if not anchor then
		FlyoutHide()
		return
	end
	flyoutAnchor = anchor
	flyout:ClearAllPoints()
	-- fly out to the LEFT of the class button (top-aligned), like the classic
	-- paladin buff addons; SetClampedToScreen keeps it on-screen near an edge
	flyout:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -4, 0)
	-- header = class name + a compact coverage summary (folded in from the old
	-- class tooltip, which is now suppressed while the fly-out is open)
	local task = HO.Engine.tasks[flyoutClass]
	local status = ""
	if task and not task.noneAssigned then
		if (task.missing or 0) > 0 then
			status = "  |cffff6060" .. string.format(L["%d missing"], task.missing) .. "|r"
		elseif (task.outOfRange or 0) > 0 then
			status = "  |cffffcc55" .. string.format("%d %s", task.outOfRange, L["out of range"]) .. "|r"
		else
			status = "  |cff60ff60" .. L["all covered"] .. "|r"
		end
	end
	flyout.title:SetText(flyoutClass .. status)

	local members = HO.Engine.ClassMembers(flyoutClass)
	local count = #members
	for i, m in ipairs(members) do
		local row = AcquireFlyoutRow(i)
		UpdateRowStatus(row, m)     -- non-secure visuals
		ConfigureRowSecure(row, m)  -- secure cast attributes (out of combat only)
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

-- open (or re-target) the fly-out for a class on hover. Out of combat only: the
-- secure rows cannot be reconfigured in combat, so the fly-out stays closed then.
function FlyoutShow(classToken)
	if InCombatLockdown() or not classToken then
		return
	end
	CancelClose()
	CreateFlyout()
	flyoutClass = classToken
	flyout:Show()
	FlyoutRefresh()
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
	-- draw above the status border (both are OVERLAY) so the corner class icon
	-- is not clipped by the green/red/yellow edge
	btn.classIcon:SetDrawLayer("OVERLAY", 2)
	btn.classIcon:SetSize(15, 15)
	btn.classIcon:SetPoint("TOPLEFT", -5, 5)
	btn.classIcon:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")

	-- status border: green = everyone covered, red = someone missing, amber =
	-- expiring/out of range. Four thin edges, recoloured per refresh (texture
	-- ops only, so it is safe to update in combat)
	btn.borders = {}
	local bt = btn:CreateTexture(nil, "OVERLAY")
	bt:SetPoint("TOPLEFT", -1, 1)
	bt:SetPoint("TOPRIGHT", 1, 1)
	bt:SetHeight(2)
	local bb = btn:CreateTexture(nil, "OVERLAY")
	bb:SetPoint("BOTTOMLEFT", -1, -1)
	bb:SetPoint("BOTTOMRIGHT", 1, -1)
	bb:SetHeight(2)
	local bl = btn:CreateTexture(nil, "OVERLAY")
	bl:SetPoint("TOPLEFT", -1, 1)
	bl:SetPoint("BOTTOMLEFT", -1, -1)
	bl:SetWidth(2)
	local br = btn:CreateTexture(nil, "OVERLAY")
	br:SetPoint("TOPRIGHT", 1, 1)
	br:SetPoint("BOTTOMRIGHT", 1, -1)
	br:SetWidth(2)
	btn.borders.top, btn.borders.bottom, btn.borders.left, btn.borders.right = bt, bb, bl, br

	btn.count = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	btn.count:SetPoint("BOTTOMRIGHT", -1, 1)

	btn.timer = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	btn.timer:SetPoint("TOP", btn, "BOTTOM", 0, -1)

	btn:SetScript("OnEnter", function(self)
		local task = self.task
		if not task then
			return
		end
		-- hover opens the per-class fly-out (out of combat); keep it open while
		-- the cursor is on the button
		CancelClose()
		FlyoutShow(task.classToken)
		if flyout and flyout:IsShown() then
			-- the fly-out already shows the class, its members and coverage, so
			-- the big class tooltip would just be redundant noise on top of it
			return
		end
		-- in combat the fly-out stays closed, so the tooltip is the info source
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
		ScheduleClose() -- close the fly-out shortly unless the cursor reaches it
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

-- user-configurable UI scale for the cast bar. The bar is implicitly protected
-- (secure buttons anchor to it), so SetScale may only run out of combat — a
-- combat-time change self-applies on the next PLAYER_REGEN_ENABLED, exactly like
-- Bar.ApplyStrata. The class/aura buttons are children of the bar, so they scale
-- with it automatically; only the fly-out (parented to UIParent) needs its own
-- SetScale to match.
function Bar.ApplyScale()
	if not bar or InCombatLockdown() then
		return
	end
	local scale = HO.db.options.bar and HO.db.options.bar.scale or 1
	bar:SetScale(scale)
	if flyout then
		flyout:SetScale(scale)
	end
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
	-- ARTWORK (not BACKGROUND) so the golden grip is not the first thing occluded
	-- when the bar is raised above other windows
	handle.tex = handle:CreateTexture(nil, "ARTWORK")
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
	-- keep the golden handle as the topmost element of the bar (above the buttons)
	-- so it stays visible and grabbable when the bar is raised over other windows
	handle:SetFrameLevel((bar:GetFrameLevel() or 1) + 10)
	LayoutBar()
	RestorePosition()
	Bar.ApplyScale() -- apply the saved cast-bar scale (out of combat at login)
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
		-- the fly-out is closed on combat start (PLAYER_REGEN_DISABLED) and its
		-- secure rows can't be touched in combat, so nothing to refresh here
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
	Bar.ApplyScale() -- apply any scale change attempted during combat
	Bar.Refresh()
end)
HO.RegisterEvent("PLAYER_REGEN_DISABLED", function()
	FlyoutHide() -- the fly-out is an out-of-combat tool; close it when combat starts
end)
