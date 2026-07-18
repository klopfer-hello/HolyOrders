-- HolyOrders — own talent scanning
-- Improvement talents ("Improved Blessing of X") share their icon with the
-- blessing spell itself, so talents are located by icon match against the
-- resolved blessing icons — no localized talent names needed.

local HO = HolyOrders
local Talents = {}
HO.Talents = Talents

Talents.ranks = {} -- [blessingID] = invested talent rank
Talents.tabPoints = {} -- [tabIndex] = points spent

function Talents.Scan()
	wipe(Talents.ranks)
	wipe(Talents.tabPoints)

	local byIcon = {}
	for id, blessing in ipairs(HO.Data.blessings) do
		if blessing.icon then
			byIcon[blessing.icon] = id
		end
		if blessing.greaterIcon and not byIcon[blessing.greaterIcon] then
			byIcon[blessing.greaterIcon] = id
		end
	end

	for tab = 1, GetNumTalentTabs() do
		local points = 0
		for index = 1, GetNumTalents(tab) do
			local _, icon, _, _, rank = GetTalentInfo(tab, index)
			rank = rank or 0
			points = points + rank
			local blessingID = icon and byIcon[icon]
			if blessingID and rank > 0 then
				local current = Talents.ranks[blessingID] or 0
				if rank > current then
					Talents.ranks[blessingID] = rank
				end
			end
		end
		Talents.tabPoints[tab] = points
	end
end

-- "40/21/0"-style summary of own talent distribution
function Talents.SpecSummary()
	if #Talents.tabPoints == 0 then
		return "?"
	end
	return table.concat(Talents.tabPoints, "/")
end

HO.RegisterEvent("CHARACTER_POINTS_CHANGED", function()
	Talents.Scan()
end)
