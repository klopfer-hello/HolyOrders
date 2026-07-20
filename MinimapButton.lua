-- HolyOrders — minimap button (self-contained, no libraries)

local HO = HolyOrders
local MMB = {}
HO.MinimapButton = MMB
local L = HO.L

local EDGE_MARGIN = 5 -- button centre offset beyond the minimap ring
local btn

local function Opts()
	return HO.Options.Ensure().minimap
end

-- place the button on the minimap ring. The radius is taken from the minimap's
-- actual half-width/height, so it hugs the edge on a resized (larger/smaller)
-- minimap instead of a fixed radius that only fit the default 140 px map (and fell
-- inside a bigger one). Square minimaps (some UI addons expose GetMinimapShape)
-- clamp to the square edge instead of floating inside on the diagonals. This is
-- the standard minimap-button positioning math, authored in our own style.
local function UpdatePosition()
	local mm = _G.Minimap
	local angle = math.rad(Opts().angle or 200)
	local x, y = math.cos(angle), math.sin(angle)
	local w = (mm:GetWidth() / 2) + EDGE_MARGIN
	local h = (mm:GetHeight() / 2) + EDGE_MARGIN
	local shape = (GetMinimapShape and GetMinimapShape()) or "ROUND"
	if shape == "ROUND" then
		x, y = x * w, y * h -- ellipse (a circle when the map is square-framed)
	else
		-- non-round: project onto the square edge, clamped to the half-extents
		local dw = math.sqrt(2 * w * w) - 10
		local dh = math.sqrt(2 * h * h) - 10
		x = math.max(-w, math.min(x * dw, w))
		y = math.max(-h, math.min(y * dh, h))
	end
	btn:SetPoint("CENTER", mm, "CENTER", x, y)
end

function MMB.UpdateShown()
	if not btn then
		return
	end
	if Opts().hide then
		btn:Hide()
	else
		btn:Show()
	end
end

function MMB.Create()
	if btn then
		return
	end
	btn = CreateFrame("Button", "HolyOrdersMinimapButton", _G.Minimap)
	btn:SetSize(31, 31)
	btn:SetFrameStrata("MEDIUM")
	btn:SetFrameLevel(8)
	btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	btn:RegisterForDrag("LeftButton")
	btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local overlay = btn:CreateTexture(nil, "OVERLAY")
	overlay:SetSize(53, 53)
	overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	overlay:SetPoint("TOPLEFT")

	local icon = btn:CreateTexture(nil, "BACKGROUND")
	icon:SetSize(20, 20)
	icon:SetTexture("Interface\\AddOns\\HolyOrders\\Icons\\HolyOrders")
	icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
	icon:SetPoint("TOPLEFT", 7, -6)

	btn:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", function()
			local mx, my = _G.Minimap:GetCenter()
			local cx, cy = GetCursorPosition()
			local scale = _G.Minimap:GetEffectiveScale()
			Opts().angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
			UpdatePosition()
		end)
	end)
	btn:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
	end)
	btn:SetScript("OnClick", function(_, mouseButton)
		if mouseButton == "RightButton" then
			HO.Bar.ToggleForceRebuff()
		elseif IsShiftKeyDown() then
			HO.Options.Toggle()
		elseif select(2, UnitClass("player")) == "PALADIN" then
			HO.Window.Toggle() -- paladins: the assignment window
		else
			HO.Request.Toggle() -- everyone else: request a buff for themselves
		end
	end)
	btn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText("HolyOrders")
		local isPally = select(2, UnitClass("player")) == "PALADIN"
		GameTooltip:AddLine(isPally and L["click: assignment window"] or L["click: buff request"], 1, 1, 1)
		GameTooltip:AddLine(L["right-click: force rebuff"], 1, 1, 1)
		GameTooltip:AddLine(L["shift-click: options"], 1, 1, 1)
		GameTooltip:AddLine(L["drag: move this button"], 0.8, 0.8, 0.8)
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	UpdatePosition()
	-- re-place shortly after login: minimap-shape / resizer addons may finish
	-- loading after us and change the map's size, which moves the ring
	if C_Timer and C_Timer.After then
		C_Timer.After(2, UpdatePosition)
	end
	MMB.UpdateShown()
end

HO.RegisterEvent("PLAYER_LOGIN", MMB.Create)
