-- Market Intel: minimap button. Left-click opens the window, right-click opens
-- Settings, drag to move it around the minimap. A number shows new alerts.
local _, ns = ...

local MM = {}
ns.Minimap = MM

local RADIUS = 80
local button

local function UpdatePosition()
	local angle = math.rad(ns.settings.minimapAngle or 200)
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * RADIUS, math.sin(angle) * RADIUS)
end

local function UpdateBadge()
	if not button then return end
	local n = ns.Alerts.unseen
	if n > 0 then
		button.badge:SetText(n > 99 and "99+" or tostring(n))
		button.badgeBg:Show()
	else
		button.badge:SetText("")
		button.badgeBg:Hide()
	end
end

local function OnDragUpdate()
	local mx, my = Minimap:GetCenter()
	local cx, cy = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	ns.settings.minimapAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx)) % 360
	UpdatePosition()
end

function MM.Create()
	if button or not Minimap then return end
	button = CreateFrame("Button", "MarketIntelMinimapButton", Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	local icon = button:CreateTexture(nil, "BACKGROUND")
	icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_02")
	icon:SetSize(20, 20)
	icon:SetPoint("TOPLEFT", 7, -5)
	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")
	button.badgeBg = button:CreateTexture(nil, "OVERLAY")
	button.badgeBg:SetColorTexture(0.8, 0.1, 0.1, 0.9)
	button.badgeBg:SetSize(16, 12)
	button.badgeBg:SetPoint("TOPRIGHT", 2, 2)
	button.badge = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	button.badge:SetPoint("CENTER", button.badgeBg, "CENTER", 0, 0)

	button:SetScript("OnClick", function(_, which)
		if which == "RightButton" then ns.UI.Show("settings") else ns.UI.Toggle() end
	end)
	button:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", OnDragUpdate) end)
	button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText("Market Intel")
		GameTooltip:AddDoubleLine("Deals", tostring(#ns.deals), 1, 1, 1, 1, 1, 1)
		GameTooltip:AddDoubleLine("BoE snipes", tostring(#ns.snipes), 1, 1, 1, 1, 1, 1)
		local today = ns.Ledger.Summary(1)
		GameTooltip:AddDoubleLine("Sales today (net)", ns.FormatMoney(today.net), 1, 1, 1, 1, 1, 1)
		GameTooltip:AddLine("Left-click: open. Right-click: settings. Drag: move.", 0.7, 0.7, 0.7)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	UpdatePosition()
	UpdateBadge()
	MM.Refresh()
end

function MM.Refresh()
	if not button then return end
	if ns.settings.minimapHide then button:Hide() else button:Show() end
end

function MM.GetButton() return button end

ns.On("MI_READY", MM.Create)
ns.On("MI_ALERT", UpdateBadge)
