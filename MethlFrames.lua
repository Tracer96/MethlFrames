local ADDON_PREFIX = "|cff33ff99Methl Frames|r"

local ARC_SEGMENTS = 128
local SEGMENT_WIDTH = 4
local SEGMENT_HEIGHT = 14
local HIGHLIGHT_WIDTH = 1
local HEALTH_CENTER_ANGLE = 172.5
local POWER_CENTER_ANGLE = 7.5
local BASE_CURVE_SWEEP = 57
local MINIMAP_BUTTON_RADIUS = 78

local DEFAULTS = {
	x = 0,
	y = -70,
	scale = 1,
	locked = true,
	hideDefaultPlayerFrame = true,
	curveWidth = 128,
	curveHeight = 210,
	curveAmount = 1,
	minimapAngle = 220,
	showMinimapIcon = true,
}

local HEALTH_COLOR = { r = 0.15, g = 0.86, b = 0.24 }
local POWER_FALLBACK_COLOR = { r = 0.18, g = 0.46, b = 0.98 }
local POWER_FALLBACKS = {
	[0] = { r = 0.18, g = 0.46, b = 0.98 },
	[1] = { r = 0.89, g = 0.18, b = 0.18 },
	[2] = { r = 0.96, g = 0.55, b = 0.18 },
	[3] = { r = 0.96, g = 0.84, b = 0.22 },
}

local addon = CreateFrame("Frame", "MethlFramesEventFrame", UIParent)
local bars = {}
local optionControls = {}

local anchor = nil
local guide = nil
local healthText = nil
local powerText = nil
local optionsFrame = nil
local minimapButton = nil

local MethlFrames_RefreshOptionsPanel = nil
local MethlFrames_RefreshMinimapButton = nil
local MethlFrames_ToggleOptions = nil

local function MethlFrames_Print(message)
	if DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage(ADDON_PREFIX .. ": " .. message)
	end
end

local function MethlFrames_Clamp(value, low, high)
	if value < low then
		return low
	end
	if value > high then
		return high
	end
	return value
end

local function MethlFrames_Round(value)
	if value >= 0 then
		return math.floor(value + 0.5)
	end
	return math.ceil(value - 0.5)
end

local function MethlFrames_Trim(text)
	if not text then
		return ""
	end
	text = string.gsub(text, "^%s+", "")
	text = string.gsub(text, "%s+$", "")
	return text
end

local function MethlFrames_ApplyDefaults()
	if not MethlFramesDB then
		MethlFramesDB = {}
	end

	local key, value
	for key, value in pairs(DEFAULTS) do
		if MethlFramesDB[key] == nil then
			MethlFramesDB[key] = value
		end
	end
end

local function MethlFrames_GetScale()
	if not MethlFramesDB or not MethlFramesDB.scale then
		return DEFAULTS.scale
	end
	return MethlFrames_Clamp(MethlFramesDB.scale, 0.5, 2.5)
end

local function MethlFrames_GetCurveWidth()
	if not MethlFramesDB or not MethlFramesDB.curveWidth then
		return DEFAULTS.curveWidth
	end
	return MethlFrames_Clamp(MethlFramesDB.curveWidth, 80, 220)
end

local function MethlFrames_GetCurveHeight()
	if not MethlFramesDB or not MethlFramesDB.curveHeight then
		return DEFAULTS.curveHeight
	end
	return MethlFrames_Clamp(MethlFramesDB.curveHeight, 140, 320)
end

local function MethlFrames_GetCurveAmount()
	if not MethlFramesDB or not MethlFramesDB.curveAmount then
		return DEFAULTS.curveAmount
	end
	return MethlFrames_Clamp(MethlFramesDB.curveAmount, 0.60, 1.80)
end

local function MethlFrames_SaveAnchorPosition()
	if not anchor or not MethlFramesDB then
		return
	end

	local centerX, centerY = anchor:GetCenter()
	local parentX, parentY = UIParent:GetCenter()
	if not centerX or not centerY or not parentX or not parentY then
		return
	end

	MethlFramesDB.x = MethlFrames_Round(centerX - parentX)
	MethlFramesDB.y = MethlFrames_Round(centerY - parentY)
end

local function MethlFrames_GetPowerType()
	if UnitPowerType then
		return UnitPowerType("player") or 0
	end
	return 0
end

local function MethlFrames_GetPowerColor()
	local powerType = MethlFrames_GetPowerType()
	if ManaBarColor and ManaBarColor[powerType] then
		local color = ManaBarColor[powerType]
		return {
			r = color.r or (POWER_FALLBACKS[powerType] and POWER_FALLBACKS[powerType].r) or POWER_FALLBACK_COLOR.r,
			g = color.g or (POWER_FALLBACKS[powerType] and POWER_FALLBACKS[powerType].g) or POWER_FALLBACK_COLOR.g,
			b = color.b or (POWER_FALLBACKS[powerType] and POWER_FALLBACKS[powerType].b) or POWER_FALLBACK_COLOR.b,
		}
	end

	if POWER_FALLBACKS[powerType] then
		return POWER_FALLBACKS[powerType]
	end

	return POWER_FALLBACK_COLOR
end

local function MethlFrames_SetSegmentColor(segment, color)
	local r = color.r or 1
	local g = color.g or 1
	local b = color.b or 1

	segment.track:SetVertexColor(r, g, b, 0.18)
	segment.glow:SetVertexColor(r, g, b, 0.18)
	segment.fill:SetVertexColor(r, g, b, 0.96)
	segment.highlight:SetVertexColor(
		MethlFrames_Clamp(r + 0.12, 0, 1),
		MethlFrames_Clamp(g + 0.12, 0, 1),
		MethlFrames_Clamp(b + 0.12, 0, 1),
		0.9
	)
end

local function MethlFrames_SetSegmentFill(segment, percent)
	local fillPercent = MethlFrames_Clamp(percent or 0, 0, 1)
	local fillHeight = math.floor((segment.innerHeight * fillPercent) + 0.5)

	segment.glow:SetHeight(fillHeight + 2)
	segment.fill:SetHeight(fillHeight)
	segment.highlight:SetHeight(fillHeight)

	if fillHeight > 0 then
		segment.glow:Show()
		segment.fill:Show()
		segment.highlight:Show()
	else
		segment.glow:Hide()
		segment.fill:Hide()
		segment.highlight:Hide()
	end
end

local function MethlFrames_CreateSegment(parent, side)
	local segment = CreateFrame("Frame", nil, parent)
	segment:SetWidth(SEGMENT_WIDTH)
	segment:SetHeight(SEGMENT_HEIGHT)
	segment.innerHeight = SEGMENT_HEIGHT

	segment.track = segment:CreateTexture(nil, "BACKGROUND")
	segment.track:SetAllPoints(segment)
	segment.track:SetTexture("Interface\\Buttons\\WHITE8X8")

	segment.glow = segment:CreateTexture(nil, "ARTWORK")
	segment.glow:SetPoint("BOTTOMLEFT", segment, "BOTTOMLEFT", -1, -1)
	segment.glow:SetWidth(SEGMENT_WIDTH + 2)
	segment.glow:SetHeight(0)
	segment.glow:SetTexture("Interface\\Buttons\\WHITE8X8")

	segment.fill = segment:CreateTexture(nil, "OVERLAY")
	segment.fill:SetPoint("BOTTOMLEFT", segment, "BOTTOMLEFT", 0, 0)
	segment.fill:SetWidth(SEGMENT_WIDTH)
	segment.fill:SetHeight(0)
	segment.fill:SetTexture("Interface\\Buttons\\WHITE8X8")

	segment.highlight = segment:CreateTexture(nil, "OVERLAY")
	segment.highlight:SetWidth(HIGHLIGHT_WIDTH)
	segment.highlight:SetHeight(0)
	segment.highlight:SetTexture("Interface\\Buttons\\WHITE8X8")

	if side == "LEFT" then
		segment.highlight:SetPoint("BOTTOMRIGHT", segment.fill, "BOTTOMRIGHT", 0, 0)
	else
		segment.highlight:SetPoint("BOTTOMLEFT", segment.fill, "BOTTOMLEFT", 0, 0)
	end

	return segment
end

local function MethlFrames_CreateArc(side)
	local bar = {
		side = side,
		segments = {},
	}

	local i
	for i = 1, ARC_SEGMENTS do
		bar.segments[i] = MethlFrames_CreateSegment(anchor, side)
	end

	return bar
end

local function MethlFrames_GetArcAngles(side)
	local sweep = BASE_CURVE_SWEEP * MethlFrames_GetCurveAmount()
	if side == "LEFT" then
		return HEALTH_CENTER_ANGLE + (sweep / 2), HEALTH_CENTER_ANGLE - (sweep / 2)
	end
	return POWER_CENTER_ANGLE - (sweep / 2), POWER_CENTER_ANGLE + (sweep / 2)
end

local function MethlFrames_GetArcPoint(side, angle)
	local radians = angle * (math.pi / 180)
	return math.cos(radians) * MethlFrames_GetCurveWidth(), math.sin(radians) * MethlFrames_GetCurveHeight()
end

local function MethlFrames_LayoutArc(bar)
	local curveWidth = MethlFrames_GetCurveWidth()
	local curveHeight = MethlFrames_GetCurveHeight()
	local startAngle, endAngle = MethlFrames_GetArcAngles(bar.side)
	local i

	for i = 1, table.getn(bar.segments) do
		local segment = bar.segments[i]
		local progress = (i - 1) / (ARC_SEGMENTS - 1)
		local angle = startAngle + ((endAngle - startAngle) * progress)
		local radians = angle * (math.pi / 180)
		local x = math.cos(radians) * curveWidth
		local y = math.sin(radians) * curveHeight

		segment:ClearAllPoints()
		segment:SetPoint("CENTER", anchor, "CENTER", x, y)
	end
end

local function MethlFrames_UpdateTextAnchors()
	if not healthText or not powerText then
		return
	end

	local healthBottomAngle = MethlFrames_GetArcAngles("LEFT")
	local powerBottomAngle = MethlFrames_GetArcAngles("RIGHT")
	local healthX, healthY = MethlFrames_GetArcPoint("LEFT", healthBottomAngle)
	local powerX, powerY = MethlFrames_GetArcPoint("RIGHT", powerBottomAngle)

	healthText:ClearAllPoints()
	healthText:SetPoint("TOP", anchor, "CENTER", healthX + 12, healthY - 10)

	powerText:ClearAllPoints()
	powerText:SetPoint("TOP", anchor, "CENTER", powerX - 12, powerY - 10)
end

local function MethlFrames_UpdateArc(bar, currentValue, maxValue, color)
	local maximum = maxValue or 0
	if maximum < 1 then
		maximum = 1
	end

	local normalized = MethlFrames_Clamp((currentValue or 0) / maximum, 0, 1)
	local count = table.getn(bar.segments)
	local i

	for i = 1, count do
		local segment = bar.segments[i]
		local segmentStart = (i - 1) / count
		local segmentEnd = i / count
		local segmentFill = (normalized - segmentStart) / (segmentEnd - segmentStart)

		MethlFrames_SetSegmentColor(segment, color)
		MethlFrames_SetSegmentFill(segment, segmentFill)
	end
end

local function MethlFrames_UpdateHealth()
	if not bars.health then
		return
	end

	local currentHealth = UnitHealth("player") or 0
	local maxHealth = UnitHealthMax("player") or 0
	MethlFrames_UpdateArc(bars.health, currentHealth, maxHealth, HEALTH_COLOR)

	if healthText then
		healthText:SetText(currentHealth .. " / " .. maxHealth)
		healthText:SetTextColor(HEALTH_COLOR.r, HEALTH_COLOR.g, HEALTH_COLOR.b)
	end
end

local function MethlFrames_UpdatePower()
	if not bars.power then
		return
	end

	local currentPower = UnitMana("player") or 0
	local maxPower = UnitManaMax("player") or 0
	local powerColor = MethlFrames_GetPowerColor()
	MethlFrames_UpdateArc(bars.power, currentPower, maxPower, powerColor)

	if powerText then
		powerText:SetText(currentPower .. " / " .. maxPower)
		powerText:SetTextColor(powerColor.r, powerColor.g, powerColor.b)
	end
end

local function MethlFrames_UpdateAll()
	MethlFrames_UpdateHealth()
	MethlFrames_UpdatePower()
end

local function MethlFrames_ApplyPlayerFrameState()
	if not PlayerFrame or not MethlFramesDB then
		return
	end

	if MethlFramesDB.hideDefaultPlayerFrame then
		PlayerFrame:SetAlpha(0)
		PlayerFrame:EnableMouse(false)
	else
		PlayerFrame:SetAlpha(1)
		PlayerFrame:EnableMouse(true)
	end
end

local function MethlFrames_ApplyPosition()
	if not anchor or not MethlFramesDB then
		return
	end

	anchor:ClearAllPoints()
	anchor:SetPoint("CENTER", UIParent, "CENTER", MethlFramesDB.x, MethlFramesDB.y)
end

local function MethlFrames_ApplyScale()
	if not anchor then
		return
	end

	anchor:SetScale(MethlFrames_GetScale())
end

local function MethlFrames_ApplyLockState()
	if not anchor or not guide or not MethlFramesDB then
		return
	end

	if MethlFramesDB.locked then
		guide:Hide()
		anchor:EnableMouse(false)
	else
		guide:Show()
		anchor:EnableMouse(true)
	end
end

local function MethlFrames_RefreshCurveLayout()
	if not anchor then
		return
	end

	if bars.health then
		MethlFrames_LayoutArc(bars.health)
	end
	if bars.power then
		MethlFrames_LayoutArc(bars.power)
	end

	MethlFrames_UpdateTextAnchors()
	MethlFrames_UpdateAll()
end

local function MethlFrames_RefreshLayout()
	MethlFrames_ApplyPosition()
	MethlFrames_ApplyScale()
	MethlFrames_ApplyLockState()
	MethlFrames_ApplyPlayerFrameState()
	MethlFrames_RefreshCurveLayout()
	if MethlFrames_RefreshMinimapButton then
		MethlFrames_RefreshMinimapButton()
	end
end

local function MethlFrames_SetLocked(locked)
	if not MethlFramesDB then
		return
	end

	MethlFramesDB.locked = locked and true or false
	MethlFrames_ApplyLockState()
	if MethlFrames_RefreshOptionsPanel then
		MethlFrames_RefreshOptionsPanel()
	end
end

local function MethlFrames_SetScale(scale)
	if not MethlFramesDB then
		return
	end

	MethlFramesDB.scale = MethlFrames_Clamp(scale, 0.5, 2.5)
	MethlFrames_ApplyScale()
	if MethlFrames_RefreshOptionsPanel then
		MethlFrames_RefreshOptionsPanel()
	end
end

local function MethlFrames_SetCurveWidth(width)
	if not MethlFramesDB then
		return
	end

	MethlFramesDB.curveWidth = MethlFrames_Clamp(width, 80, 220)
	MethlFrames_RefreshCurveLayout()
	if MethlFrames_RefreshOptionsPanel then
		MethlFrames_RefreshOptionsPanel()
	end
end

local function MethlFrames_SetCurveHeight(height)
	if not MethlFramesDB then
		return
	end

	MethlFramesDB.curveHeight = MethlFrames_Clamp(height, 140, 320)
	MethlFrames_RefreshCurveLayout()
	if MethlFrames_RefreshOptionsPanel then
		MethlFrames_RefreshOptionsPanel()
	end
end

local function MethlFrames_SetCurveAmount(amount)
	if not MethlFramesDB then
		return
	end

	MethlFramesDB.curveAmount = MethlFrames_Clamp(amount, 0.60, 1.80)
	MethlFrames_RefreshCurveLayout()
	if MethlFrames_RefreshOptionsPanel then
		MethlFrames_RefreshOptionsPanel()
	end
end

local function MethlFrames_SetPlayerFrameHidden(hidden)
	if not MethlFramesDB then
		return
	end

	MethlFramesDB.hideDefaultPlayerFrame = hidden and true or false
	MethlFrames_ApplyPlayerFrameState()
	if MethlFrames_RefreshOptionsPanel then
		MethlFrames_RefreshOptionsPanel()
	end
end

local function MethlFrames_SetMinimapIconShown(shown)
	if not MethlFramesDB then
		return
	end

	MethlFramesDB.showMinimapIcon = shown and true or false
	if MethlFrames_RefreshMinimapButton then
		MethlFrames_RefreshMinimapButton()
	end
	if MethlFrames_RefreshOptionsPanel then
		MethlFrames_RefreshOptionsPanel()
	end
end

local function MethlFrames_Reset()
	local key, value
	for key, value in pairs(DEFAULTS) do
		MethlFramesDB[key] = value
	end

	MethlFrames_RefreshLayout()
	if MethlFrames_RefreshOptionsPanel then
		MethlFrames_RefreshOptionsPanel()
	end
end

local function MethlFrames_AnchorOnDragStart()
	if MethlFramesDB and not MethlFramesDB.locked then
		this:StartMoving()
	end
end

local function MethlFrames_AnchorOnDragStop()
	this:StopMovingOrSizing()
	MethlFrames_SaveAnchorPosition()
end

local function MethlFrames_CreateUI()
	if anchor then
		return
	end

	anchor = CreateFrame("Frame", "MethlFramesAnchor", UIParent)
	anchor:SetWidth(84)
	anchor:SetHeight(84)
	anchor:SetMovable(true)
	anchor:SetClampedToScreen(true)
	anchor:RegisterForDrag("LeftButton")
	anchor:SetScript("OnDragStart", MethlFrames_AnchorOnDragStart)
	anchor:SetScript("OnDragStop", MethlFrames_AnchorOnDragStop)

	guide = CreateFrame("Frame", nil, anchor)
	guide:SetAllPoints(anchor)
	guide:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 16,
		edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	guide:SetBackdropColor(0.02, 0.10, 0.02, 0.75)
	guide:SetBackdropBorderColor(0.25, 0.90, 0.25, 0.90)

	local guideText = guide:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	guideText:SetPoint("CENTER", guide, "CENTER", 0, 0)
	guideText:SetText("Drag")

	healthText = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	healthText:SetJustifyH("CENTER")

	powerText = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	powerText:SetJustifyH("CENTER")

	bars.health = MethlFrames_CreateArc("LEFT")
	bars.power = MethlFrames_CreateArc("RIGHT")
end

local function MethlFrames_CreateSlider(name, parent, label, minValue, maxValue, step, formatString, onValueChanged)
	local slider = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
	slider:SetWidth(220)
	slider:SetHeight(16)
	slider:SetMinMaxValues(minValue, maxValue)
	slider:SetValueStep(step)
	slider.label = label
	slider.formatString = formatString
	slider.onValueChanged = onValueChanged

	getglobal(name .. "Low"):SetText(tostring(minValue))
	getglobal(name .. "High"):SetText(tostring(maxValue))

	slider:SetScript("OnValueChanged", function()
		local value = this:GetValue()
		local displayValue
		if this.formatString == "%d" then
			displayValue = string.format(this.formatString, math.floor(value + 0.5))
		else
			displayValue = string.format(this.formatString, value)
		end

		getglobal(this:GetName() .. "Text"):SetText(this.label .. ": " .. displayValue)
		if not this.ignoreCallback and this.onValueChanged then
			this.onValueChanged(value)
		end
	end)

	return slider
end

local function MethlFrames_ToggleOptionsFrame()
	if not optionsFrame then
		return
	end

	if optionsFrame:IsVisible() then
		optionsFrame:Hide()
	else
		optionsFrame:Show()
	end
end

MethlFrames_ToggleOptions = MethlFrames_ToggleOptionsFrame

local function MethlFrames_CreateOptionsPanel()
	if optionsFrame then
		return
	end

	optionsFrame = CreateFrame("Frame", "MethlFramesOptionsFrame", UIParent)
	optionsFrame:SetWidth(360)
	optionsFrame:SetHeight(430)
	optionsFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
	optionsFrame:SetFrameStrata("HIGH")
	optionsFrame:SetToplevel(true)
	optionsFrame:SetMovable(true)
	optionsFrame:SetClampedToScreen(true)
	optionsFrame:EnableMouse(true)
	optionsFrame:RegisterForDrag("LeftButton")
	optionsFrame:SetScript("OnDragStart", function()
		this:StartMoving()
	end)
	optionsFrame:SetScript("OnDragStop", function()
		this:StopMovingOrSizing()
	end)
	optionsFrame:SetBackdrop({
		bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 16,
		edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	optionsFrame:SetBackdropColor(0, 0, 0, 0.88)
	optionsFrame:SetBackdropBorderColor(0.70, 0.70, 0.70, 1)
	optionsFrame:Hide()

	if UISpecialFrames then
		table.insert(UISpecialFrames, "MethlFramesOptionsFrame")
	end

	local title = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 16, -14)
	title:SetText("Methl Frames")

	local subtitle = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	subtitle:SetWidth(300)
	subtitle:SetJustifyH("LEFT")
	subtitle:SetText("Curved player bars and quick controls.")

	local closeButton = CreateFrame("Button", nil, optionsFrame, "UIPanelCloseButton")
	closeButton:SetPoint("TOPRIGHT", optionsFrame, "TOPRIGHT", -4, -4)

	local curveWidthSlider = MethlFrames_CreateSlider(
		"MethlFramesCurveWidthSlider",
		optionsFrame,
		"Curve Width",
		80,
		220,
		1,
		"%d",
		function(value)
			MethlFrames_SetCurveWidth(math.floor(value + 0.5))
		end
	)
	curveWidthSlider:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 18, -66)
	optionControls.curveWidthSlider = curveWidthSlider

	local curveHeightSlider = MethlFrames_CreateSlider(
		"MethlFramesCurveHeightSlider",
		optionsFrame,
		"Curve Height",
		140,
		320,
		1,
		"%d",
		function(value)
			MethlFrames_SetCurveHeight(math.floor(value + 0.5))
		end
	)
	curveHeightSlider:SetPoint("TOPLEFT", curveWidthSlider, "BOTTOMLEFT", 0, -26)
	optionControls.curveHeightSlider = curveHeightSlider

	local curveAmountSlider = MethlFrames_CreateSlider(
		"MethlFramesCurveAmountSlider",
		optionsFrame,
		"Curve Amount",
		60,
		180,
		1,
		"%d%%",
		function(value)
			MethlFrames_SetCurveAmount(value / 100)
		end
	)
	curveAmountSlider:SetPoint("TOPLEFT", curveHeightSlider, "BOTTOMLEFT", 0, -26)
	optionControls.curveAmountSlider = curveAmountSlider

	local scaleSlider = MethlFrames_CreateSlider(
		"MethlFramesScaleSlider",
		optionsFrame,
		"Scale",
		0.5,
		2.5,
		0.05,
		"%.2f",
		function(value)
			MethlFrames_SetScale(value)
		end
	)
	scaleSlider:SetPoint("TOPLEFT", curveAmountSlider, "BOTTOMLEFT", 0, -26)
	optionControls.scaleSlider = scaleSlider

	local unlockCheck = CreateFrame("CheckButton", "MethlFramesUnlockCheck", optionsFrame, "UICheckButtonTemplate")
	unlockCheck:SetPoint("TOPLEFT", scaleSlider, "BOTTOMLEFT", -2, -14)
	getglobal(unlockCheck:GetName() .. "Text"):SetText("Unlock frame drag")
	unlockCheck:SetScript("OnClick", function()
		MethlFrames_SetLocked(not this:GetChecked())
	end)
	optionControls.unlockCheck = unlockCheck

	local playerFrameCheck = CreateFrame("CheckButton", "MethlFramesPlayerFrameCheck", optionsFrame, "UICheckButtonTemplate")
	playerFrameCheck:SetPoint("TOPLEFT", unlockCheck, "BOTTOMLEFT", 0, -6)
	getglobal(playerFrameCheck:GetName() .. "Text"):SetText("Hide default player frame")
	playerFrameCheck:SetScript("OnClick", function()
		MethlFrames_SetPlayerFrameHidden(this:GetChecked() and true or false)
	end)
	optionControls.playerFrameCheck = playerFrameCheck

	local minimapCheck = CreateFrame("CheckButton", "MethlFramesMinimapCheck", optionsFrame, "UICheckButtonTemplate")
	minimapCheck:SetPoint("TOPLEFT", playerFrameCheck, "BOTTOMLEFT", 0, -6)
	getglobal(minimapCheck:GetName() .. "Text"):SetText("Show minimap button")
	minimapCheck:SetScript("OnClick", function()
		MethlFrames_SetMinimapIconShown(this:GetChecked() and true or false)
	end)
	optionControls.minimapCheck = minimapCheck

	local hint = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	hint:SetPoint("BOTTOMLEFT", optionsFrame, "BOTTOMLEFT", 20, 52)
	hint:SetWidth(320)
	hint:SetJustifyH("LEFT")
	hint:SetText("Left-click the minimap icon to open settings.\nRight-click the minimap icon to lock or unlock drag mode.")

	local lockButton = CreateFrame("Button", nil, optionsFrame, "UIPanelButtonTemplate")
	lockButton:SetWidth(88)
	lockButton:SetHeight(24)
	lockButton:SetPoint("BOTTOMLEFT", optionsFrame, "BOTTOMLEFT", 40, 18)
	lockButton:SetText("Lock")
	lockButton:SetScript("OnClick", function()
		MethlFrames_SetLocked(true)
	end)

	local unlockButton = CreateFrame("Button", nil, optionsFrame, "UIPanelButtonTemplate")
	unlockButton:SetWidth(88)
	unlockButton:SetHeight(24)
	unlockButton:SetPoint("LEFT", lockButton, "RIGHT", 8, 0)
	unlockButton:SetText("Unlock")
	unlockButton:SetScript("OnClick", function()
		MethlFrames_SetLocked(false)
	end)

	local resetButton = CreateFrame("Button", nil, optionsFrame, "UIPanelButtonTemplate")
	resetButton:SetWidth(88)
	resetButton:SetHeight(24)
	resetButton:SetPoint("LEFT", unlockButton, "RIGHT", 8, 0)
	resetButton:SetText("Reset")
	resetButton:SetScript("OnClick", function()
		MethlFrames_Reset()
	end)

	optionControls.lockButton = lockButton
	optionControls.unlockButton = unlockButton
	optionControls.resetButton = resetButton

	optionsFrame:SetScript("OnShow", function()
		if MethlFrames_RefreshOptionsPanel then
			MethlFrames_RefreshOptionsPanel()
		end
	end)
end

MethlFrames_RefreshOptionsPanel = function()
	if not optionsFrame or not MethlFramesDB then
		return
	end

	if optionControls.curveWidthSlider then
		optionControls.curveWidthSlider.ignoreCallback = true
		optionControls.curveWidthSlider:SetValue(MethlFrames_GetCurveWidth())
		optionControls.curveWidthSlider.ignoreCallback = nil
		getglobal(optionControls.curveWidthSlider:GetName() .. "Text"):SetText("Curve Width: " .. MethlFrames_GetCurveWidth())
	end

	if optionControls.curveHeightSlider then
		optionControls.curveHeightSlider.ignoreCallback = true
		optionControls.curveHeightSlider:SetValue(MethlFrames_GetCurveHeight())
		optionControls.curveHeightSlider.ignoreCallback = nil
		getglobal(optionControls.curveHeightSlider:GetName() .. "Text"):SetText("Curve Height: " .. MethlFrames_GetCurveHeight())
	end

	if optionControls.curveAmountSlider then
		optionControls.curveAmountSlider.ignoreCallback = true
		optionControls.curveAmountSlider:SetValue(math.floor((MethlFrames_GetCurveAmount() * 100) + 0.5))
		optionControls.curveAmountSlider.ignoreCallback = nil
		getglobal(optionControls.curveAmountSlider:GetName() .. "Text"):SetText("Curve Amount: " .. math.floor((MethlFrames_GetCurveAmount() * 100) + 0.5) .. "%")
	end

	if optionControls.scaleSlider then
		optionControls.scaleSlider.ignoreCallback = true
		optionControls.scaleSlider:SetValue(MethlFrames_GetScale())
		optionControls.scaleSlider.ignoreCallback = nil
		getglobal(optionControls.scaleSlider:GetName() .. "Text"):SetText("Scale: " .. string.format("%.2f", MethlFrames_GetScale()))
	end

	if optionControls.unlockCheck then
		optionControls.unlockCheck:SetChecked(not MethlFramesDB.locked)
	end

	if optionControls.playerFrameCheck then
		optionControls.playerFrameCheck:SetChecked(MethlFramesDB.hideDefaultPlayerFrame)
	end

	if optionControls.minimapCheck then
		optionControls.minimapCheck:SetChecked(MethlFramesDB.showMinimapIcon)
	end
end

local function MethlFrames_UpdateMinimapButtonPosition()
	if not minimapButton or not MethlFramesDB then
		return
	end

	local angle = math.rad(MethlFramesDB.minimapAngle or DEFAULTS.minimapAngle)
	minimapButton:ClearAllPoints()
	minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * MINIMAP_BUTTON_RADIUS, math.sin(angle) * MINIMAP_BUTTON_RADIUS)
end

local function MethlFrames_MinimapButton_BeingDragged()
	if not MethlFramesDB then
		return
	end

	local mx, my = Minimap:GetCenter()
	if not mx or not my then
		return
	end

	local scale = Minimap:GetEffectiveScale()
	local xpos, ypos = GetCursorPosition()
	xpos = xpos / scale
	ypos = ypos / scale

	local angle = math.deg(math.atan2(ypos - my, xpos - mx))
	if angle < 0 then
		angle = angle + 360
	end

	MethlFramesDB.minimapAngle = angle
	if this then
		this.dragged = true
	end
	MethlFrames_UpdateMinimapButtonPosition()
end

local function MethlFrames_MinimapButton_OnClick(button)
	if this.dragged then
		this.dragged = nil
		return
	end

	if button == "RightButton" then
		MethlFrames_SetLocked(not MethlFramesDB.locked)
		if MethlFramesDB.locked then
			MethlFrames_Print("Locked.")
		else
			MethlFrames_Print("Unlocked. Drag the green square to move the bars.")
		end
		return
	end

	if MethlFrames_ToggleOptions then
		MethlFrames_ToggleOptions()
	end
end

local function MethlFrames_CreateMinimapButton()
	if minimapButton then
		return
	end

	minimapButton = CreateFrame("Button", "MethlFramesMinimapButton", Minimap)
	minimapButton:SetWidth(31)
	minimapButton:SetHeight(31)
	minimapButton:SetFrameStrata("MEDIUM")
	minimapButton:SetFrameLevel(8)
	minimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	minimapButton:RegisterForDrag("LeftButton")
	minimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local backdrop = minimapButton:CreateTexture(nil, "BACKGROUND")
	backdrop:SetTexture("Interface\\Buttons\\WHITE8X8")
	backdrop:SetWidth(18)
	backdrop:SetHeight(18)
	backdrop:SetPoint("CENTER", minimapButton, "CENTER", 0, 1)
	backdrop:SetVertexColor(0, 0, 0, 0.55)
	minimapButton.backdrop = backdrop

	local icon = minimapButton:CreateTexture(nil, "ARTWORK")
	icon:SetWidth(20)
	icon:SetHeight(20)
	icon:SetPoint("CENTER", minimapButton, "CENTER", 0, 1)
	icon:SetTexture("Interface\\Icons\\Spell_Nature_HealingWaveGreater")
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	minimapButton.icon = icon

	local overlay = minimapButton:CreateTexture(nil, "OVERLAY")
	overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	overlay:SetWidth(53)
	overlay:SetHeight(53)
	overlay:SetPoint("TOPLEFT", minimapButton, "TOPLEFT", 0, 0)
	minimapButton.overlay = overlay

	minimapButton:SetScript("OnClick", MethlFrames_MinimapButton_OnClick)
	minimapButton:SetScript("OnDragStart", function()
		this.dragged = nil
		this:LockHighlight()
		this:SetScript("OnUpdate", MethlFrames_MinimapButton_BeingDragged)
	end)
	minimapButton:SetScript("OnDragStop", function()
		this:UnlockHighlight()
		this:SetScript("OnUpdate", nil)
	end)
	minimapButton:SetScript("OnEnter", function()
		GameTooltip:SetOwner(this, "ANCHOR_LEFT")
		GameTooltip:SetText("Methl Frames")
		GameTooltip:AddLine("Left-click: open settings", 1, 1, 1)
		GameTooltip:AddLine("Right-click: lock or unlock drag", 1, 1, 1)
		GameTooltip:AddLine("Drag: move icon around minimap", 1, 1, 1)
		GameTooltip:Show()
	end)
	minimapButton:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
end

MethlFrames_RefreshMinimapButton = function()
	if not minimapButton or not MethlFramesDB then
		return
	end

	MethlFrames_UpdateMinimapButtonPosition()
	if MethlFramesDB.showMinimapIcon then
		minimapButton:Show()
	else
		minimapButton:Hide()
	end
end

local function MethlFrames_ShowHelp()
	MethlFrames_Print("Commands: /mf, /mf unlock, /mf lock, /mf reset, /mf scale 1.0, /mf playerframe on|off")
end

local function MethlFrames_SlashCommand(message)
	local trimmed = MethlFrames_Trim(message)
	if trimmed == "" then
		if MethlFrames_ToggleOptions then
			MethlFrames_ToggleOptions()
		end
		return
	end

	local _, _, command, rest = string.find(trimmed, "^(%S+)%s*(.-)$")
	command = string.lower(command or "")
	rest = MethlFrames_Trim(rest or "")

	if command == "settings" or command == "config" or command == "options" then
		if MethlFrames_ToggleOptions then
			MethlFrames_ToggleOptions()
		end
		return
	end

	if command == "unlock" then
		MethlFrames_SetLocked(false)
		MethlFrames_Print("Unlocked. Drag the green square to place the arc bars.")
		return
	end

	if command == "lock" then
		MethlFrames_SetLocked(true)
		MethlFrames_Print("Locked.")
		return
	end

	if command == "reset" then
		MethlFrames_Reset()
		MethlFrames_Print("Position, curve, scale, and icon settings reset to defaults.")
		return
	end

	if command == "scale" then
		local newScale = tonumber(rest)
		if not newScale then
			MethlFrames_Print("Usage: /mframes scale 0.5 to 2.5")
			return
		end

		MethlFrames_SetScale(newScale)
		MethlFrames_Print("Scale set to " .. string.format("%.2f", MethlFrames_GetScale()))
		return
	end

	if command == "playerframe" then
		local state = string.lower(rest)
		if state == "on" then
			MethlFrames_SetPlayerFrameHidden(false)
			MethlFrames_Print("Default player frame shown.")
			return
		end
		if state == "off" then
			MethlFrames_SetPlayerFrameHidden(true)
			MethlFrames_Print("Default player frame hidden.")
			return
		end

		MethlFrames_Print("Usage: /mframes playerframe on|off")
		return
	end

	MethlFrames_ShowHelp()
end

local function MethlFrames_OnEvent()
	if event == "VARIABLES_LOADED" then
		MethlFrames_ApplyDefaults()
		MethlFrames_CreateUI()
		MethlFrames_CreateOptionsPanel()
		MethlFrames_CreateMinimapButton()
		MethlFrames_RefreshLayout()
		if MethlFrames_RefreshOptionsPanel then
			MethlFrames_RefreshOptionsPanel()
		end
		MethlFrames_Print("Loaded. Click the minimap button or use /mframes settings.")
		return
	end

	if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" or event == "PLAYER_DEAD" then
		MethlFrames_RefreshLayout()
		return
	end

	if event == "PLAYER_LOGOUT" then
		MethlFrames_SaveAnchorPosition()
		return
	end

	if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
		if arg1 == "player" then
			MethlFrames_UpdateHealth()
		end
		return
	end

	if event == "UNIT_MANA" or event == "UNIT_MAXMANA" or event == "UNIT_RAGE" or event == "UNIT_MAXRAGE" or event == "UNIT_ENERGY" or event == "UNIT_MAXENERGY" or event == "UNIT_FOCUS" or event == "UNIT_MAXFOCUS" then
		if arg1 == "player" then
			MethlFrames_UpdatePower()
		end
		return
	end

	if event == "UPDATE_SHAPESHIFT_FORM" or event == "UPDATE_SHAPESHIFT_FORMS" or event == "UNIT_DISPLAYPOWER" then
		MethlFrames_UpdatePower()
		return
	end
end

addon:SetScript("OnEvent", MethlFrames_OnEvent)
addon:RegisterEvent("VARIABLES_LOADED")
addon:RegisterEvent("PLAYER_ENTERING_WORLD")
addon:RegisterEvent("PLAYER_ALIVE")
addon:RegisterEvent("PLAYER_DEAD")
addon:RegisterEvent("PLAYER_UNGHOST")
addon:RegisterEvent("PLAYER_LOGOUT")
addon:RegisterEvent("UNIT_HEALTH")
addon:RegisterEvent("UNIT_MAXHEALTH")
addon:RegisterEvent("UNIT_MANA")
addon:RegisterEvent("UNIT_MAXMANA")
addon:RegisterEvent("UNIT_RAGE")
addon:RegisterEvent("UNIT_MAXRAGE")
addon:RegisterEvent("UNIT_ENERGY")
addon:RegisterEvent("UNIT_MAXENERGY")
addon:RegisterEvent("UNIT_FOCUS")
addon:RegisterEvent("UNIT_MAXFOCUS")
addon:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
addon:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
addon:RegisterEvent("UNIT_DISPLAYPOWER")

SLASH_METHLFRAMES1 = "/mf"
SLASH_METHLFRAMES2 = "/mframes"
SLASH_METHLFRAMES3 = "/methlframes"
SlashCmdList["METHLFRAMES"] = MethlFrames_SlashCommand
