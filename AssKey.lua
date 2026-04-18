-- 🔑 AssKey: Displays keybinds for Single Button Assistant spell suggestions.

local addonName = ...

local frame = CreateFrame("Frame")
frame:SetFrameStrata("MEDIUM")
frame:SetFrameLevel(9999)
frame:SetSize(50, 50)
frame:Hide()

local keybind = frame:CreateFontString(nil, "OVERLAY")
keybind:SetPoint("CENTER", 0, 0)
keybind:SetDrawLayer("OVERLAY", 7)

local defaults = {
	fontSize = 24,
	offsetX = 0,
	offsetY = 0,
	fontColor = "ffffffff",
	shadowEnabled = true,
	shadowColor = "ff000000",
	shadowOffsetX = 3,
	shadowOffsetY = -3,
	outline = "",
	justifyH = "CENTER",
	justifyV = "MIDDLE",
}

local category
local cachedSBAButton = nil
local lastScanTime = 0
local scanCooldown = 2.0
local lastSlotChangeTime = 0
local hideGrace = 0.2
local lastValidRecommendationTime = 0
local pendingUpdate = false
local spellToSlot = {}
local slotToBinding = {}
local mapsDirty = true
local hookedButtons = nil

-- { slotMin, slotMax, bindingFormat, slotOffset }
local ACTIONBAR_SLOT_MAPPING = {
	{ 1,   12,  "ACTIONBUTTON%d",          0 },
	{ 13,  24,  "ACTIONBUTTON%d",          -12 },
	{ 25,  36,  "MULTIACTIONBAR3BUTTON%d", -24 },
	{ 37,  48,  "MULTIACTIONBAR4BUTTON%d", -36 },
	{ 49,  60,  "MULTIACTIONBAR2BUTTON%d", -48 },
	{ 61,  72,  "MULTIACTIONBAR1BUTTON%d", -60 },
	{ 145, 156, "MULTIACTIONBAR5BUTTON%d", -144 },
	{ 157, 168, "MULTIACTIONBAR6BUTTON%d", -156 },
	{ 169, 180, "MULTIACTIONBAR7BUTTON%d", -168 },
}

local function AbbreviateBinding(binding)
	if not binding then return binding end
	binding = binding:gsub("Mouse Button (%d+)", "M%1")
	return binding
end

local function GetBindingKeyForSlot(slot)
	for _, mapping in ipairs(ACTIONBAR_SLOT_MAPPING) do
		if slot >= mapping[1] and slot <= mapping[2] then
			local buttonIndex = slot + mapping[4]
			return GetBindingKey(mapping[3]:format(buttonIndex))
		end
	end
	return nil
end

local function BuildSpellSlotMap()
	wipe(spellToSlot)
	wipe(slotToBinding)
	for slot = 1, 120 do
		local actionType, id = GetActionInfo(slot)
		if (actionType == "spell" or actionType == "macro") and id and id > 0 then
			local bindingKey = GetBindingKeyForSlot(slot)
			if bindingKey and not spellToSlot[id] then
				spellToSlot[id] = slot
				slotToBinding[slot] = AbbreviateBinding(GetBindingText(bindingKey, "KEY_", true))
			end
		end
	end
	mapsDirty = false
end

local function GetKeybindForSpell(spellID)
	if mapsDirty then BuildSpellSlotMap() end
	local slot = spellToSlot[spellID]
	if not slot then return "" end
	if not slotToBinding[slot] then
		local bindingKey = GetBindingKeyForSlot(slot)
		slotToBinding[slot] = bindingKey and AbbreviateBinding(GetBindingText(bindingKey, "KEY_", true)) or ""
	end
	return slotToBinding[slot]
end

local function GetAnchorPoint()
	local h = AssKeyDB.justifyH or defaults.justifyH
	local v = AssKeyDB.justifyV or defaults.justifyV
	if v == "MIDDLE" and h == "CENTER" then
		return "CENTER"
	elseif v == "MIDDLE" then
		return h
	elseif h == "CENTER" then
		return v
	else
		return v .. h
	end
end

local function GetCurrentRecommendedSpell()
	if not C_AssistedCombat then return nil end
	if C_AssistedCombat.GetNextCastSpell then
		local spellID = C_AssistedCombat.GetNextCastSpell()
		if spellID and spellID > 0 then
			return spellID
		end
	end
	return nil
end

-- ScheduleUpdate needs to be before FindSBAOverlayButton and after Update so needs to be predeclared here
local ScheduleUpdate
local function FindSBAOverlayButton()
	if not C_AssistedCombat or not C_AssistedCombat.GetNextCastSpell then
		cachedSBAButton = nil
		return nil
	end
	local spellID = C_AssistedCombat.GetNextCastSpell()
	if not spellID or spellID <= 0 then
		return cachedSBAButton or nil
	end
	if cachedSBAButton and cachedSBAButton:IsShown() then
		return cachedSBAButton
	end
	cachedSBAButton = nil
	local now = GetTime()
	if now - lastScanTime < scanCooldown then
		return nil
	end
	lastScanTime = now
	local f = EnumerateFrames()
	while f do
		if f.UpdateAssistedCombatRotationFrame then
			for i = 1, f:GetNumChildren() do
				local child = select(i, f:GetChildren())
				if child.ActiveFrame or child.InactiveTexture then
					if child:IsShown() or (child.ActiveFrame and child.ActiveFrame:IsShown()) then
						cachedSBAButton = f
						if not hookedButtons then hookedButtons = {} end
						if not hookedButtons[f] then
							hooksecurefunc(f, "UpdateAssistedCombatRotationFrame", function()
								ScheduleUpdate()
							end)
							hookedButtons[f] = true
						end
						return f
					end
				end
			end
		end
		f = EnumerateFrames(f)
	end
	return nil
end

local function Update()
	local now = GetTime()
	local button = FindSBAOverlayButton()
	if not button or not button:IsShown() then
		frame:Hide()
		return
	end
	local spellID = GetCurrentRecommendedSpell()
	if not spellID or spellID <= 0 then
		if frame:IsShown() and (now - lastValidRecommendationTime) < hideGrace then
			return
		end
		frame:Hide()
		return
	end
	local kb = GetKeybindForSpell(spellID)
	if not kb or kb == "" then
		if frame:IsShown() and (now - lastValidRecommendationTime) < hideGrace then
			return
		end
		frame:Hide()
		return
	end
	lastValidRecommendationTime = now
	local anchor = GetAnchorPoint()
	frame:ClearAllPoints()
	frame:SetPoint(anchor, button, anchor, AssKeyDB.offsetX, AssKeyDB.offsetY)
	local fontPath = GameFontNormal:GetFont()
	local outline = AssKeyDB.outline or defaults.outline
	keybind:SetFont(fontPath, AssKeyDB.fontSize, outline)
	local h = AssKeyDB.justifyH or defaults.justifyH
	local v = AssKeyDB.justifyV or defaults.justifyV
	keybind:SetJustifyH(h)
	keybind:SetJustifyV(v)
	keybind:ClearAllPoints()
	keybind:SetPoint(anchor, frame, anchor, 0, 0)
	local color = CreateColorFromHexString(AssKeyDB.fontColor)
	if color then
		keybind:SetTextColor(color:GetRGBA())
	else
		keybind:SetTextColor(1, 1, 1, 1)
	end
	if AssKeyDB.shadowEnabled then
		local shadowColor = CreateColorFromHexString(AssKeyDB.shadowColor)
		if shadowColor then
			keybind:SetShadowColor(shadowColor:GetRGBA())
		else
			keybind:SetShadowColor(0, 0, 0, 1)
		end
		keybind:SetShadowOffset(AssKeyDB.shadowOffsetX, AssKeyDB.shadowOffsetY)
	else
		keybind:SetShadowColor(0, 0, 0, 0)
	end
	if keybind:GetText() ~= kb then
		keybind:SetText(kb)
	end
	frame:Show()
end

ScheduleUpdate = function ()
	if pendingUpdate then return end
	pendingUpdate = true
	C_Timer.After(0.1, function()
		pendingUpdate = false
		Update()
	end)
end

local function InitializeOptions()
	category = Settings.RegisterVerticalLayoutCategory(addonName)
	local function CreateSliderWithValue(setting, min, max, step, tooltip)
		local options = Settings.CreateSliderOptions(min, max, step)
		options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
		Settings.CreateSlider(category, setting, options, tooltip)
	end
	local fontSizeSetting = Settings.RegisterAddOnSetting(category,
		"AssKey_FontSize", "fontSize", AssKeyDB, Settings.VarType.Number, "Font Size", defaults.fontSize)
	fontSizeSetting:SetValueChangedCallback(ScheduleUpdate)
	CreateSliderWithValue(fontSizeSetting, 8, 72, 1, "Font size of the keybind text.")
	local offsetXSetting = Settings.RegisterAddOnSetting(category,
		"AssKey_OffsetX", "offsetX", AssKeyDB, Settings.VarType.Number, "Horizontal Offset", defaults.offsetX)
	offsetXSetting:SetValueChangedCallback(ScheduleUpdate)
	CreateSliderWithValue(offsetXSetting, -200, 200, 5, "Horizontal position relative to the SBA button.")
	local offsetYSetting = Settings.RegisterAddOnSetting(category,
		"AssKey_OffsetY", "offsetY", AssKeyDB, Settings.VarType.Number, "Vertical Offset", defaults.offsetY)
	offsetYSetting:SetValueChangedCallback(ScheduleUpdate)
	CreateSliderWithValue(offsetYSetting, -200, 200, 5, "Vertical position relative to the SBA button.")
	local justifyHSetting = Settings.RegisterAddOnSetting(category,
		"AssKey_JustifyH", "justifyH", AssKeyDB, Settings.VarType.String, "Horizontal Alignment", defaults.justifyH)
	justifyHSetting:SetValueChangedCallback(ScheduleUpdate)
	Settings.CreateDropdown(category, justifyHSetting, function()
		local container = Settings.CreateControlTextContainer()
		container:Add("LEFT", "Left")
		container:Add("CENTER", "Center")
		container:Add("RIGHT", "Right")
		return container:GetData()
	end, "Horizontal anchor point on the SBA button.")
	local justifyVSetting = Settings.RegisterAddOnSetting(category,
		"AssKey_JustifyV", "justifyV", AssKeyDB, Settings.VarType.String, "Vertical Alignment", defaults.justifyV)
	justifyVSetting:SetValueChangedCallback(ScheduleUpdate)
	Settings.CreateDropdown(category, justifyVSetting, function()
		local container = Settings.CreateControlTextContainer()
		container:Add("TOP", "Top")
		container:Add("MIDDLE", "Middle")
		container:Add("BOTTOM", "Bottom")
		return container:GetData()
	end, "Vertical anchor point on the SBA button.")
	local fontColorSetting = Settings.RegisterAddOnSetting(category,
		"AssKey_FontColor", "fontColor", AssKeyDB, Settings.VarType.Color, "Font Color", defaults.fontColor)
	fontColorSetting:SetValueChangedCallback(ScheduleUpdate)
	Settings.CreateColorSwatch(category, fontColorSetting, "Color of the keybind text.")
	local outlineSetting = Settings.RegisterAddOnSetting(category,
		"AssKey_Outline", "outline", AssKeyDB, Settings.VarType.String, "Outline Style", defaults.outline)
	outlineSetting:SetValueChangedCallback(ScheduleUpdate)
	Settings.CreateDropdown(category, outlineSetting, function()
		local container = Settings.CreateControlTextContainer()
		container:Add("", "None")
		container:Add("OUTLINE", "Outline")
		container:Add("THICKOUTLINE", "Thick Outline")
		container:Add("MONOCHROME", "Monochrome")
		container:Add("OUTLINE,MONOCHROME", "Outline + Monochrome")
		return container:GetData()
	end, "Outline drawn around the keybind text.")
	local shadowEnabledSetting = Settings.RegisterAddOnSetting(category,
		"AssKey_ShadowEnabled", "shadowEnabled", AssKeyDB, Settings.VarType.Boolean, "Enable Shadow", defaults.shadowEnabled)
	shadowEnabledSetting:SetValueChangedCallback(ScheduleUpdate)
	Settings.CreateCheckbox(category, shadowEnabledSetting, "Toggle display of shadow.")
	local shadowColorSetting = Settings.RegisterAddOnSetting(category,
		"AssKey_ShadowColor", "shadowColor", AssKeyDB, Settings.VarType.Color, "Shadow Color", defaults.shadowColor)
	shadowColorSetting:SetValueChangedCallback(ScheduleUpdate)
	Settings.CreateColorSwatch(category, shadowColorSetting, "Color of the shadow behind the text.")
	local shadowOffsetXSetting = Settings.RegisterAddOnSetting(category,
		"AssKey_ShadowOffsetX", "shadowOffsetX", AssKeyDB, Settings.VarType.Number, "Shadow Offset X", defaults.shadowOffsetX)
	shadowOffsetXSetting:SetValueChangedCallback(ScheduleUpdate)
	CreateSliderWithValue(shadowOffsetXSetting, -20, 20, 1, "Horizontal position of the shadow.")
	local shadowOffsetYSetting = Settings.RegisterAddOnSetting(category,
		"AssKey_ShadowOffsetY", "shadowOffsetY", AssKeyDB, Settings.VarType.Number, "Shadow Offset Y", defaults.shadowOffsetY)
	shadowOffsetYSetting:SetValueChangedCallback(ScheduleUpdate)
	CreateSliderWithValue(shadowOffsetYSetting, -20, 20, 1, "Vertical position of the shadow.")
	Settings.RegisterAddOnCategory(category)
end

function AssKey_Settings()
	if not InCombatLockdown() and category then
		Settings.OpenToCategory(category:GetID())
	end
end

frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, ...)
	if event == "ADDON_LOADED" then
		local name = ...
		if name ~= addonName then return end
		AssKeyDB = AssKeyDB or {}
		for key, value in pairs(defaults) do
			if AssKeyDB[key] == nil then
				AssKeyDB[key] = value
			end
		end
		InitializeOptions()
		self:RegisterEvent("PLAYER_ENTERING_WORLD")
		self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
		self:RegisterEvent("PLAYER_TALENT_UPDATE")
		self:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
		self:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
		self:RegisterEvent("UPDATE_BINDINGS")
		self:UnregisterEvent(event)
	elseif event == "ACTIONBAR_SLOT_CHANGED" then
		if GetTime() - lastSlotChangeTime >= 0.2 then
			lastSlotChangeTime = GetTime()
			lastScanTime = 0
			mapsDirty = true
			cachedSBAButton = nil
			ScheduleUpdate()
		end
	else
		mapsDirty = true
		ScheduleUpdate()
	end
end)

SLASH_ASSKEY1 = "/ak"
SLASH_ASSKEY2 = "/asskey"
SlashCmdList["ASSKEY"] = AssKey_Settings
