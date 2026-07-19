-- HolyOrders — minimap button (self-contained, no libraries)

local HO = HolyOrders
local MMB = {}
HO.MinimapButton = MMB

local RADIUS = 80
local btn

local function Opts()
	return HO.Options.Ensure().minimap
end

local function UpdatePosition()
	local angle = math.rad(Opts().angle or 200)
	btn:SetPoint("CENTER", _G.Minimap, "CENTER", math.cos(angle) * RADIUS, math.sin(angle) * RADIUS)
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
		else
			HO.Window.Toggle()
		end
	end)
	btn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText("HolyOrders")
		GameTooltip:AddLine("click: assignment window", 1, 1, 1)
		GameTooltip:AddLine("right-click: force rebuff", 1, 1, 1)
		GameTooltip:AddLine("shift-click: options", 1, 1, 1)
		GameTooltip:AddLine("drag: move this button", 0.8, 0.8, 0.8)
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	UpdatePosition()
	MMB.UpdateShown()
end

HO.RegisterEvent("PLAYER_LOGIN", MMB.Create)
