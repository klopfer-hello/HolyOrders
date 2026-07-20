-- HolyOrders — buff request window
-- A small, self-contained NON-secure panel any player can use to request a
-- blessing for THEMSELVES. Clicking a blessing broadcasts the request to the
-- group (Comm.SendRequest); the paladins who cover this player then see it in
-- their assignment / cast UI and fulfil it with the controls they already have.
-- Non-secure throughout (it only sends an addon message and draws textures), so
-- it is safe in combat and available to non-paladins too.

local HO = HolyOrders
local Request = {}
HO.Request = Request
local L = HO.L

local BTN_SIZE = 36
local BTN_GAP = 5
local PAD = 12
local TITLE_H = 18
local CLEAR_W = 52
local QUESTION_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

-- yellow, matching the paladin-side "unmet request" colour language
local ACTIVE_R, ACTIVE_G, ACTIVE_B = 0.95, 0.85, 0.15

local frame
local blessingButtons = {}
local statusText

local function BlessingName(id)
	local b = HO.Data.blessings[id]
	return b and (b.name or b.key) or tostring(id)
end

-- one path for every change: broadcast + persist the whole ordered list through
-- Comm, then repaint
local function Apply(list)
	if HO.Comm and HO.Comm.SendRequest then
		HO.Comm.SendRequest(list)
	end
	Request.Refresh()
end

local function CurrentList()
	local list = {}
	if HO.db and HO.db.myRequests then
		for i, id in ipairs(HO.db.myRequests) do
			list[i] = id
		end
	end
	return list
end

-- click toggles a blessing in/out of the priority list: absent → appended at the
-- lowest priority; present → removed and the rest re-ranked
local function ToggleBlessing(id)
	local list = CurrentList()
	for i, v in ipairs(list) do
		if v == id then
			table.remove(list, i)
			Apply(list)
			return
		end
	end
	list[#list + 1] = id
	Apply(list)
end

local function CreateBlessingButton(id)
	local btn = CreateFrame("Button", nil, frame)
	btn:SetSize(BTN_SIZE, BTN_SIZE)
	btn.blessingID = id
	-- yellow highlight shown behind the icon while this blessing is the active
	-- request; the icon is inset, so the highlight reads as a border
	btn.hl = btn:CreateTexture(nil, "BACKGROUND")
	btn.hl:SetAllPoints()
	btn.hl:SetColorTexture(ACTIVE_R, ACTIVE_G, ACTIVE_B, 1)
	btn.hl:Hide()
	btn.icon = btn:CreateTexture(nil, "ARTWORK")
	btn.icon:SetPoint("TOPLEFT", 2, -2)
	btn.icon:SetPoint("BOTTOMRIGHT", -2, 2)
	btn.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	-- priority rank badge (1 = highest), shown only while this blessing is chosen
	btn.rank = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	btn.rank:SetPoint("CENTER")
	btn.rank:SetTextColor(0.05, 0.05, 0.08, 1) -- dark digit reads on the yellow highlight
	local rf, rs = btn.rank:GetFont()
	btn.rank:SetFont(rf, (rs or 14) + 2, "THICKOUTLINE")
	btn.rank:Hide()
	btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	btn:SetScript("OnClick", function(self)
		ToggleBlessing(self.blessingID)
	end)
	btn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(BlessingName(self.blessingID))
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return btn
end

local function Create()
	if frame then
		return
	end
	frame = CreateFrame("Frame", "HolyOrdersRequest", UIParent)
	-- MEDIUM (standard panel strata) so higher-priority windows draw cleanly over
	-- us instead of bleeding through at HIGH
	frame:SetFrameStrata("MEDIUM")
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function() frame:StartMoving() end)
	frame:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
	frame:SetPoint("CENTER")
	frame:Hide()
	table.insert(UISpecialFrames, "HolyOrdersRequest") -- ESC closes it

	frame.bg = frame:CreateTexture(nil, "BACKGROUND")
	frame.bg:SetAllPoints()
	frame.bg:SetColorTexture(0.05, 0.05, 0.08, 0.93)

	frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	frame.title:SetPoint("TOPLEFT", PAD, -8)
	frame.title:SetText(L["Buff Request"])

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)
	close:SetScript("OnClick", function() frame:Hide() end)

	local n = HO.Data.NUM_BLESSINGS
	local rowY = -(8 + TITLE_H + 6)
	-- one button per blessing in id order (all six shown; a requester may want any)
	for id = 1, n do
		local btn = CreateBlessingButton(id)
		btn:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + (id - 1) * (BTN_SIZE + BTN_GAP), rowY)
		blessingButtons[id] = btn
	end

	local clear = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	clear:SetSize(CLEAR_W, BTN_SIZE)
	clear:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + n * (BTN_SIZE + BTN_GAP), rowY)
	clear:SetText(L["Clear"])
	clear:SetScript("OnClick", function() Apply({}) end)

	statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	statusText:SetPoint("TOPLEFT", PAD, rowY - BTN_SIZE - 8)
	statusText:SetJustifyH("LEFT")

	local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("TOPLEFT", statusText, "BOTTOMLEFT", 0, -3)
	hint:SetJustifyH("LEFT")
	hint:SetText(L["click blessings in priority order — click again to remove"])

	local width = PAD * 2 + n * (BTN_SIZE + BTN_GAP) + CLEAR_W
	local height = 8 + TITLE_H + 6 + BTN_SIZE + 8 + 14 + 14 + PAD
	frame:SetSize(width, height)

	Request.ApplyScale() -- apply the saved window scale on first open
end

-- the request window follows the WINDOW scale (it is a "window" too). Non-secure,
-- so it is safe to apply any time.
function Request.ApplyScale()
	if frame then
		frame:SetScale((HO.db.options.window and HO.db.options.window.scale) or 1)
	end
end

-- repaint the icons, the priority rank badges and the status line from the
-- persisted own request list (HO.db.myRequests). Safe to call any time.
function Request.Refresh()
	if not frame then
		return
	end
	local list = HO.db and HO.db.myRequests
	local rankOf = {}
	if list then
		for i, id in ipairs(list) do
			rankOf[id] = i
		end
	end
	for id, btn in ipairs(blessingButtons) do
		local b = HO.Data.blessings[id]
		btn.icon:SetTexture((b and b.icon) or QUESTION_ICON)
		local rank = rankOf[id]
		if rank then
			btn.hl:Show()
			btn.rank:SetText(tostring(rank))
			btn.rank:Show()
		else
			btn.hl:Hide()
			btn.rank:Hide()
		end
	end
	if list and #list > 0 then
		local names = {}
		for _, id in ipairs(list) do
			names[#names + 1] = BlessingName(id)
		end
		statusText:SetText(string.format(L["preferences: %s"], table.concat(names, " > ")))
	else
		statusText:SetText(L["no request"])
	end
end

function Request.Toggle()
	Create()
	if frame:IsShown() then
		frame:Hide()
	else
		frame:Show()
		Request.Refresh()
	end
end
