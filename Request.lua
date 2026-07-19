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

-- one path for every set/clear: broadcast + persist through Comm, then repaint
local function SendRequest(id)
	if HO.Comm and HO.Comm.SendRequest then
		HO.Comm.SendRequest(id)
	end
	Request.Refresh()
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
	btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	btn:SetScript("OnClick", function(self)
		SendRequest(self.blessingID)
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
	frame:SetFrameStrata("HIGH")
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
	clear:SetScript("OnClick", function() SendRequest(0) end)

	statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	statusText:SetPoint("TOPLEFT", PAD, rowY - BTN_SIZE - 8)
	statusText:SetJustifyH("LEFT")

	local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("TOPLEFT", statusText, "BOTTOMLEFT", 0, -3)
	hint:SetJustifyH("LEFT")
	hint:SetText(L["click a blessing to request it for yourself"])

	local width = PAD * 2 + n * (BTN_SIZE + BTN_GAP) + CLEAR_W
	local height = 8 + TITLE_H + 6 + BTN_SIZE + 8 + 14 + 14 + PAD
	frame:SetSize(width, height)
end

-- repaint the icons, the active-request highlight and the status line from the
-- persisted own request (HO.db.myRequest). Safe to call any time.
function Request.Refresh()
	if not frame then
		return
	end
	local cur = HO.db and HO.db.myRequest
	for id, btn in ipairs(blessingButtons) do
		local b = HO.Data.blessings[id]
		btn.icon:SetTexture((b and b.icon) or QUESTION_ICON)
		if cur == id then
			btn.hl:Show()
		else
			btn.hl:Hide()
		end
	end
	if cur then
		statusText:SetText(string.format(L["requesting: %s"], BlessingName(cur)))
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
