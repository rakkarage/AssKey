-- 🔑 AssKey: Displays keybinds for Single Button Assistant spell suggestions.

local _addonName = ...

local _frame = CreateFrame("Frame")
_frame:SetFrameStrata("MEDIUM")
_frame:SetFrameLevel(9999)
_frame:SetSize(50, 50)
_frame:Hide()

local _keybind = _frame:CreateFontString(nil, "OVERLAY")
_keybind:SetPoint("CENTER", 0, 0)
_keybind:SetDrawLayer("OVERLAY", 7)

local _defaults = {
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

local _category
local _cachedSBAButton
local _lastScanTime = 0
local _scanCooldown = 2.0
local _hideGrace = 0.2
local _lastValidRecommendationTime = 0
local _pendingUpdate = false
local _spellToSlot = {}
local _slotToBinding = {}
local _slotCache = {}
local _mapsDirty = true
local _hookedButtons

-- { slotMin, slotMax, bindingFormat, slotOffset }
local ACTIONBAR_SLOT_MAPPING = {
	{ 121, 132, "ACTIONBUTTON%d",          -120 }, -- Override action bar
	{ 133, 144, "ACTIONBUTTON%d",          -132 }, -- Vehicle/possess bar
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

local function IsBonusBarSlot(slot)
	return slot >= 121 and slot <= 144
end

local function IsSlotActiveForCurrentBar(slot)
	if HasBonusActionBar() then
		return IsBonusBarSlot(slot)
	end
	return not IsBonusBarSlot(slot)
end

local function BuildSpellSlotMap()
	wipe(_spellToSlot)
	wipe(_slotToBinding)
	for _, mapping in ipairs(ACTIONBAR_SLOT_MAPPING) do
		local isBonusRange = IsBonusBarSlot(mapping[1]) and IsBonusBarSlot(mapping[2])
		if isBonusRange and not HasBonusActionBar() then
			-- Skip override/vehicle slots when not mounted/in vehicle
		else
			for slot = mapping[1], mapping[2] do
				local actionType, id = GetActionInfo(slot)
				if (actionType == "spell" or actionType == "macro") and id and id > 0 then
					if not _spellToSlot[id] then
						local bindingKey = GetBindingKeyForSlot(slot)
						if bindingKey then
							_spellToSlot[id] = slot
							_slotToBinding[slot] = AbbreviateBinding(
								GetBindingText(bindingKey, "KEY_", true))
						end
					end
				end
			end
		end
	end
	_mapsDirty = false
end

local function GetKeybindForSpell(spellID)
	if _mapsDirty then
		BuildSpellSlotMap()
	end

	local slot = _spellToSlot[spellID]
	if not slot then return "" end

	-- If a mounted/override bar is active, only show bindings from active slots.
	if not IsSlotActiveForCurrentBar(slot) then
		return ""
	end

	if not _slotToBinding[slot] then
		local bindingKey = GetBindingKeyForSlot(slot)
		_slotToBinding[slot] = bindingKey and AbbreviateBinding(GetBindingText(bindingKey, "KEY_", true)) or ""
	end

	return _slotToBinding[slot]
end

local function GetAnchorPoint()
	local h = AssKeyDB.justifyH or _defaults.justifyH
	local v = AssKeyDB.justifyV or _defaults.justifyV
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
		_cachedSBAButton = nil
		return nil
	end

	local spellID = C_AssistedCombat.GetNextCastSpell()
	if not spellID or spellID <= 0 then
		return _cachedSBAButton
	end

	if _cachedSBAButton and _cachedSBAButton:IsShown() then
		return _cachedSBAButton
	end

	_cachedSBAButton = nil
	local now = GetTime()
	if now - _lastScanTime < _scanCooldown then
		return nil
	end

	_lastScanTime = now
	local f = EnumerateFrames()
	while f do
		if f.UpdateAssistedCombatRotationFrame then
			for i = 1, f:GetNumChildren() do
				local child = select(i, f:GetChildren())
				if child.ActiveFrame or child.InactiveTexture then
					if child:IsShown() or (child.ActiveFrame and child.ActiveFrame:IsShown()) then
						_cachedSBAButton = f
						if not _hookedButtons then _hookedButtons = {} end
						if not _hookedButtons[f] then
							hooksecurefunc(f, "UpdateAssistedCombatRotationFrame", function()
								ScheduleUpdate()
							end)
							_hookedButtons[f] = true
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
		_frame:Hide()
		return
	end
	local spellID = GetCurrentRecommendedSpell()
	if not spellID or spellID <= 0 then
		if _frame:IsShown() and (now - _lastValidRecommendationTime) < _hideGrace then
			return
		end
		_frame:Hide()
		return
	end
	local kb = GetKeybindForSpell(spellID)
	if not kb or kb == "" then
		if _frame:IsShown() and (now - _lastValidRecommendationTime) < _hideGrace then
			return
		end
		_frame:Hide()
		return
	end
	_lastValidRecommendationTime = now
	local anchor = GetAnchorPoint()
	_frame:ClearAllPoints()
	_frame:SetPoint(anchor, button, anchor, AssKeyDB.offsetX, AssKeyDB.offsetY)
	local fontPath = GameFontNormal:GetFont()
	local outline = AssKeyDB.outline or _defaults.outline
	_keybind:SetFont(fontPath, AssKeyDB.fontSize, outline)
	local h = AssKeyDB.justifyH or _defaults.justifyH
	local v = AssKeyDB.justifyV or _defaults.justifyV
	_keybind:SetJustifyH(h)
	_keybind:SetJustifyV(v)
	_keybind:ClearAllPoints()
	_keybind:SetPoint(anchor, _frame, anchor, 0, 0)
	local color = CreateColorFromHexString(AssKeyDB.fontColor)
	if color then
		_keybind:SetTextColor(color:GetRGBA())
	else
		_keybind:SetTextColor(1, 1, 1, 1)
	end
	if AssKeyDB.shadowEnabled then
		local shadowColor = CreateColorFromHexString(AssKeyDB.shadowColor)
		if shadowColor then
			_keybind:SetShadowColor(shadowColor:GetRGBA())
		else
			_keybind:SetShadowColor(0, 0, 0, 1)
		end
		_keybind:SetShadowOffset(AssKeyDB.shadowOffsetX, AssKeyDB.shadowOffsetY)
	else
		_keybind:SetShadowColor(0, 0, 0, 0)
	end
	if _keybind:GetText() ~= kb then
		_keybind:SetText(kb)
	end
	_frame:Show()
end

ScheduleUpdate = function()
	if _pendingUpdate then return end
	_pendingUpdate = true
	C_Timer.After(0.1, function()
		_pendingUpdate = false
		Update()
	end)
end

local function InitializeOptions()
	_category = Settings.RegisterVerticalLayoutCategory(_addonName)

	local function CreateSliderWithValue(setting, min, max, step, tooltip)
		local options = Settings.CreateSliderOptions(min, max, step)
		options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
		Settings.CreateSlider(_category, setting, options, tooltip)
	end

	local fontSizeSetting = Settings.RegisterAddOnSetting(_category,
		"AssKey_FontSize", "fontSize", AssKeyDB, Settings.VarType.Number, "Font Size", _defaults.fontSize)
	fontSizeSetting:SetValueChangedCallback(ScheduleUpdate)
	CreateSliderWithValue(fontSizeSetting, 8, 72, 1, "Font size of the keybind text.")

	local offsetXSetting = Settings.RegisterAddOnSetting(_category,
		"AssKey_OffsetX", "offsetX", AssKeyDB, Settings.VarType.Number, "Horizontal Offset", _defaults.offsetX)
	offsetXSetting:SetValueChangedCallback(ScheduleUpdate)
	CreateSliderWithValue(offsetXSetting, -200, 200, 5, "Horizontal position relative to the SBA button.")

	local offsetYSetting = Settings.RegisterAddOnSetting(_category,
		"AssKey_OffsetY", "offsetY", AssKeyDB, Settings.VarType.Number, "Vertical Offset", _defaults.offsetY)
	offsetYSetting:SetValueChangedCallback(ScheduleUpdate)
	CreateSliderWithValue(offsetYSetting, -200, 200, 5, "Vertical position relative to the SBA button.")

	local justifyHSetting = Settings.RegisterAddOnSetting(_category,
		"AssKey_JustifyH", "justifyH", AssKeyDB, Settings.VarType.String, "Horizontal Alignment", _defaults.justifyH)
	justifyHSetting:SetValueChangedCallback(ScheduleUpdate)
	Settings.CreateDropdown(_category, justifyHSetting, function()
		local container = Settings.CreateControlTextContainer()
		container:Add("LEFT", "Left")
		container:Add("CENTER", "Center")
		container:Add("RIGHT", "Right")
		return container:GetData()
	end, "Horizontal anchor point on the SBA button.")

	local justifyVSetting = Settings.RegisterAddOnSetting(_category,
		"AssKey_JustifyV", "justifyV", AssKeyDB, Settings.VarType.String, "Vertical Alignment", _defaults.justifyV)
	justifyVSetting:SetValueChangedCallback(ScheduleUpdate)
	Settings.CreateDropdown(_category, justifyVSetting, function()
		local container = Settings.CreateControlTextContainer()
		container:Add("TOP", "Top")
		container:Add("MIDDLE", "Middle")
		container:Add("BOTTOM", "Bottom")
		return container:GetData()
	end, "Vertical anchor point on the SBA button.")

	local fontColorSetting = Settings.RegisterAddOnSetting(_category,
		"AssKey_FontColor", "fontColor", AssKeyDB, Settings.VarType.Color, "Font Color", _defaults.fontColor)
	fontColorSetting:SetValueChangedCallback(ScheduleUpdate)
	Settings.CreateColorSwatch(_category, fontColorSetting, "Color of the keybind text.")

	local outlineSetting = Settings.RegisterAddOnSetting(_category,
		"AssKey_Outline", "outline", AssKeyDB, Settings.VarType.String, "Outline Style", _defaults.outline)
	outlineSetting:SetValueChangedCallback(ScheduleUpdate)
	Settings.CreateDropdown(_category, outlineSetting, function()
		local container = Settings.CreateControlTextContainer()
		container:Add("", "None")
		container:Add("OUTLINE", "Outline")
		container:Add("THICKOUTLINE", "Thick Outline")
		container:Add("MONOCHROME", "Monochrome")
		container:Add("OUTLINE,MONOCHROME", "Outline + Monochrome")
		return container:GetData()
	end, "Outline drawn around the keybind text.")

	local shadowEnabledSetting = Settings.RegisterAddOnSetting(_category,
		"AssKey_ShadowEnabled", "shadowEnabled", AssKeyDB, Settings.VarType.Boolean, "Enable Shadow", _defaults.shadowEnabled)
	shadowEnabledSetting:SetValueChangedCallback(ScheduleUpdate)
	Settings.CreateCheckbox(_category, shadowEnabledSetting, "Toggle display of shadow.")

	local shadowColorSetting = Settings.RegisterAddOnSetting(_category,
		"AssKey_ShadowColor", "shadowColor", AssKeyDB, Settings.VarType.Color, "Shadow Color", _defaults.shadowColor)
	shadowColorSetting:SetValueChangedCallback(ScheduleUpdate)
	Settings.CreateColorSwatch(_category, shadowColorSetting, "Color of the shadow behind the text.")

	local shadowOffsetXSetting = Settings.RegisterAddOnSetting(_category,
		"AssKey_ShadowOffsetX", "shadowOffsetX", AssKeyDB, Settings.VarType.Number, "Shadow Offset X", _defaults.shadowOffsetX)
	shadowOffsetXSetting:SetValueChangedCallback(ScheduleUpdate)
	CreateSliderWithValue(shadowOffsetXSetting, -20, 20, 1, "Horizontal position of the shadow.")

	local shadowOffsetYSetting = Settings.RegisterAddOnSetting(_category,
		"AssKey_ShadowOffsetY", "shadowOffsetY", AssKeyDB, Settings.VarType.Number, "Shadow Offset Y", _defaults.shadowOffsetY)
	shadowOffsetYSetting:SetValueChangedCallback(ScheduleUpdate)
	CreateSliderWithValue(shadowOffsetYSetting, -20, 20, 1, "Vertical position of the shadow.")

	Settings.RegisterAddOnCategory(_category)
end

_frame:RegisterEvent("ADDON_LOADED")
_frame:SetScript("OnEvent", function(self, event, ...)
	if event == "ADDON_LOADED" then
		local name = ...
		if name ~= _addonName then return end

		AssKeyDB = AssKeyDB or {}
		for key, value in pairs(_defaults) do
			if AssKeyDB[key] == nil then
				AssKeyDB[key] = value
			end
		end

		InitializeOptions()
		self:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
		self:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
		self:RegisterEvent("PLAYER_ENTERING_WORLD")
		self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
		self:RegisterEvent("PLAYER_TALENT_UPDATE")
		self:RegisterEvent("UPDATE_BINDINGS")
		self:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
		self:RegisterEvent("UPDATE_OVERRIDE_ACTIONBAR")
		self:RegisterEvent("UPDATE_POSSESS_BAR")
		self:UnregisterEvent(event)
	elseif event == "ACTIONBAR_SLOT_CHANGED" then
		local slot = ...
		if not slot then return end
		local actionType, id = GetActionInfo(slot)
		local old = _slotCache[slot]
		local changed = (old == nil) ~= (actionType == nil)
			or (old and (old.t ~= actionType or old.id ~= id))
		if not changed then return end
		_slotCache[slot] = actionType and { t = actionType, id = id } or nil
		_mapsDirty = true
		ScheduleUpdate()
	else
		_mapsDirty = true
		ScheduleUpdate()
	end
end)

function AssKey_Settings()
	if not InCombatLockdown() then
		Settings.OpenToCategory(_category:GetID())
	end
end

SLASH_ASSKEY1 = "/ak"
SLASH_ASSKEY2 = "/asskey"
SlashCmdList["ASSKEY"] = AssKey_Settings
