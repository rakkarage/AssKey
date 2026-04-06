-- AssKey: Displays keybinds for spell suggestions

local addonName, ns = ...

ns.AssKey = CreateFrame("Frame", "AssKeyFrame", UIParent)
local AssKey = ns.AssKey
AssKey.name = addonName

AssKey.defaults = {
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

AssKey.cachedSBAButton = nil
AssKey.lastScanTime = 0
AssKey.scanCooldown = 2.0
AssKey.pendingUpdate = false
AssKey.spellToSlot = {}
AssKey.slotToBinding = {}
AssKey.mapsDirty = true
AssKey.hookedButtons = nil
AssKey.needsImmediateRescan = false

AssKey:SetFrameStrata("MEDIUM")
AssKey:SetFrameLevel(9999)
AssKey:SetSize(50, 50)
AssKey:Hide()

AssKey.keybind = AssKey:CreateFontString(nil, "OVERLAY")
AssKey.keybind:SetPoint("CENTER", 0, 0)
AssKey.keybind:SetDrawLayer("OVERLAY", 7)

-- Table-driven action bar slot mapping: { slotMin, slotMax, bindingFormat, slotOffset }
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
	-- Resolve action slot to the correct keybinding using table lookup
	for _, mapping in ipairs(ACTIONBAR_SLOT_MAPPING) do
		if slot >= mapping[1] and slot <= mapping[2] then
			local buttonIndex = slot + mapping[4]
			return GetBindingKey(mapping[3]:format(buttonIndex))
		end
	end
	return nil
end

function AssKey:BuildSpellSlotMap()
	wipe(self.spellToSlot)
	wipe(self.slotToBinding)

	for slot = 1, 120 do
		local actionType, id = GetActionInfo(slot)
		if (actionType == "spell" or actionType == "macro") and id and id > 0 then
			local bindingKey = GetBindingKeyForSlot(slot)
			if bindingKey and not self.spellToSlot[id] then
				self.spellToSlot[id] = slot
				self.slotToBinding[slot] = AbbreviateBinding(GetBindingText(bindingKey, "KEY_", true))
			end
		end
	end

	self.mapsDirty = false
end

function AssKey:GetKeybindForSpell(spellID)
	if self.mapsDirty then self:BuildSpellSlotMap() end

	local slot = self.spellToSlot[spellID]
	if not slot then return "" end

	if not self.slotToBinding[slot] then
		local bindingKey = GetBindingKeyForSlot(slot)
		self.slotToBinding[slot] = bindingKey and AbbreviateBinding(GetBindingText(bindingKey, "KEY_", true)) or ""
	end

	return self.slotToBinding[slot]
end

function AssKey:FindSBAOverlayButton()
	if not C_AssistedCombat or not C_AssistedCombat.GetNextCastSpell then
		self.cachedSBAButton = nil
		return nil
	end

	local spellID = C_AssistedCombat.GetNextCastSpell()
	if not spellID or spellID <= 0 then
		return self.cachedSBAButton or nil
	end

	-- Button is still alive and visible — reference is valid, return it.
	-- Whether a spell is actively recommended is GetCurrentRecommendedSpell's job.
	if self.cachedSBAButton and self.cachedSBAButton:IsShown() then
		return self.cachedSBAButton
	end

	-- No valid cache, respect cooldown before scanning
	self.cachedSBAButton = nil

	local now = GetTime()
	if now - self.lastScanTime < self.scanCooldown then
		return nil
	end

	self.lastScanTime = now

	local frame = EnumerateFrames()
	while frame do
		if frame.UpdateAssistedCombatRotationFrame then
			for i = 1, frame:GetNumChildren() do
				local child = select(i, frame:GetChildren())
				if child.ActiveFrame or child.InactiveTexture then
					if child:IsShown() or (child.ActiveFrame and child.ActiveFrame:IsShown()) then
						self.cachedSBAButton = frame

						if not self.hookedButtons then self.hookedButtons = {} end
						if not self.hookedButtons[frame] then
							hooksecurefunc(frame, "UpdateAssistedCombatRotationFrame", function()
								self:ScheduleUpdate()
							end)
							self.hookedButtons[frame] = true
						end

						return frame
					end
				end
			end
		end
		frame = EnumerateFrames(frame)
	end
	return nil
end

function AssKey:GetCurrentRecommendedSpell()
	if not C_AssistedCombat then return nil end

	if C_AssistedCombat.GetNextCastSpell then
		local spellID = C_AssistedCombat.GetNextCastSpell()
		if spellID and spellID > 0 then
			return spellID
		end
	end

	return nil
end

function AssKey:GetAnchorPoint()
	-- Combine justifyH (LEFT/CENTER/RIGHT) and justifyV (TOP/MIDDLE/BOTTOM)
	-- into a WoW anchor point string e.g. "TOPLEFT", "CENTER", "BOTTOMRIGHT"
	local h = AssKeyDB.justifyH or self.defaults.justifyH
	local v = AssKeyDB.justifyV or self.defaults.justifyV
	if v == "MIDDLE" and h == "CENTER" then
		return "CENTER"
	elseif v == "MIDDLE" then
		return h
	elseif h == "CENTER" then
		return v
	else
		return v .. h -- e.g. "TOP" .. "LEFT" = "TOPLEFT"
	end
end

function AssKey:ScheduleUpdate()
	if self.pendingUpdate then return end
	self.pendingUpdate = true
	C_Timer.After(0.1, function()
		self.pendingUpdate = false
		self:Update()
	end)
end

function AssKey:Update()
	if not AssKeyDB then return end

	local button = self:FindSBAOverlayButton()
	if not button or not button:IsShown() then
		self:Hide()
		return
	end

	local spellID = self:GetCurrentRecommendedSpell()
	if not spellID or spellID <= 0 then
		self:Hide()
		return
	end

	local keybind = self:GetKeybindForSpell(spellID)
	if not keybind or keybind == "" then
		self:Hide()
		return
	end

	local anchor = self:GetAnchorPoint()
	self:ClearAllPoints()
	self:SetPoint(anchor, button, anchor, AssKeyDB.offsetX, AssKeyDB.offsetY)

	local fontPath = GameFontNormal:GetFont()
	local outline = AssKeyDB.outline or self.defaults.outline
	self.keybind:SetFont(fontPath, AssKeyDB.fontSize, outline)

	local h = AssKeyDB.justifyH or self.defaults.justifyH
	local v = AssKeyDB.justifyV or self.defaults.justifyV
	self.keybind:SetJustifyH(h)
	self.keybind:SetJustifyV(v)
	self.keybind:ClearAllPoints()
	self.keybind:SetPoint(anchor, self, anchor, 0, 0)

	local color = CreateColorFromHexString(AssKeyDB.fontColor)
	if color then
		self.keybind:SetTextColor(color:GetRGBA())
	else
		self.keybind:SetTextColor(1, 1, 1, 1)
	end

	if AssKeyDB.shadowEnabled then
		local shadowColor = CreateColorFromHexString(AssKeyDB.shadowColor)
		if shadowColor then
			self.keybind:SetShadowColor(shadowColor:GetRGBA())
		else
			self.keybind:SetShadowColor(0, 0, 0, 1)
		end
		self.keybind:SetShadowOffset(AssKeyDB.shadowOffsetX, AssKeyDB.shadowOffsetY)
	else
		self.keybind:SetShadowColor(0, 0, 0, 0)
	end

	-- forces update shadow by change text
	self.keybind:SetText("")
	self.keybind:SetText(keybind)
	self:Show()
end

function AssKey:OnEvent(event, ...)
	if self[event] then
		self[event](self, event, ...)
	else
		self.mapsDirty = true
		self:ScheduleUpdate()
	end
end

function AssKey:ADDON_LOADED(event, name)
	if name ~= self.name then return end

	AssKeyDB = AssKeyDB or {}
	for k, v in pairs(self.defaults) do
		if AssKeyDB[k] == nil then
			AssKeyDB[k] = v
		end
	end

	self:InitializeOptions()

	self:RegisterEvent("PLAYER_ENTERING_WORLD")
	self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
	self:RegisterEvent("PLAYER_TALENT_UPDATE")
	self:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
	self:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
	self:RegisterEvent("UPDATE_BINDINGS")

	-- Hook action bar slot changes to mark maps dirty and trigger rescan immediately
	-- instead of waiting for the 2-second cooldown on FindSBAOverlayButton()
	self:HookScript("ACTIONBAR_SLOT_CHANGED", function()
		if GetTime() - self.lastScanTime >= 0.2 then -- Debounce at 200ms
			self.lastScanTime = GetTime()
			self.mapsDirty = true
			self.cachedSBAButton = nil
			self:ScheduleUpdate()
		end
	end)

	self:UnregisterEvent(event)
end

AssKey:SetScript("OnEvent", AssKey.OnEvent)
AssKey:RegisterEvent("ADDON_LOADED")

function AssKey:InitializeOptions()
	local category = Settings.RegisterVerticalLayoutCategory(self.name)
	self.category = category

	local function OnSettingChanged()
		self:ScheduleUpdate()
	end

	local function CreateSliderWithValue(setting, min, max, step, tooltip)
		local options = Settings.CreateSliderOptions(min, max, step)
		options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
		Settings.CreateSlider(category, setting, options, tooltip)
	end

	local fontSizeSetting = Settings.RegisterAddOnSetting(category,
		"AssKey_FontSize", "fontSize", AssKeyDB, Settings.VarType.Number, "Font Size", self.defaults.fontSize)
	fontSizeSetting:SetValueChangedCallback(OnSettingChanged)
	CreateSliderWithValue(fontSizeSetting, 8, 72, 1, "Font size of the keybind text.")

	local offsetXSetting = Settings.RegisterAddOnSetting(category,
		"AssKey_OffsetX", "offsetX", AssKeyDB, Settings.VarType.Number, "Horizontal Offset", self.defaults.offsetX)
	offsetXSetting:SetValueChangedCallback(OnSettingChanged)
	CreateSliderWithValue(offsetXSetting, -200, 200, 5, "Horizontal position relative to the SBA button.")

	local offsetYSetting = Settings.RegisterAddOnSetting(category,
		"AssKey_OffsetY", "offsetY", AssKeyDB, Settings.VarType.Number, "Vertical Offset", self.defaults.offsetY)
	offsetYSetting:SetValueChangedCallback(OnSettingChanged)
	CreateSliderWithValue(offsetYSetting, -200, 200, 5, "Vertical position relative to the SBA button.")

	local justifyHSetting = Settings.RegisterAddOnSetting(category,
		"AssKey_JustifyH", "justifyH", AssKeyDB, Settings.VarType.String, "Horizontal Alignment", self.defaults.justifyH)
	justifyHSetting:SetValueChangedCallback(OnSettingChanged)
	Settings.CreateDropdown(category, justifyHSetting, function()
		local container = Settings.CreateControlTextContainer()
		container:Add("LEFT", "Left")
		container:Add("CENTER", "Center")
		container:Add("RIGHT", "Right")
		return container:GetData()
	end, "Horizontal anchor point on the SBA button.")

	local justifyVSetting = Settings.RegisterAddOnSetting(category,
		"AssKey_JustifyV", "justifyV", AssKeyDB, Settings.VarType.String, "Vertical Alignment", self.defaults.justifyV)
	justifyVSetting:SetValueChangedCallback(OnSettingChanged)
	Settings.CreateDropdown(category, justifyVSetting, function()
		local container = Settings.CreateControlTextContainer()
		container:Add("TOP", "Top")
		container:Add("MIDDLE", "Middle")
		container:Add("BOTTOM", "Bottom")
		return container:GetData()
	end, "Vertical anchor point on the SBA button.")

	local fontColorSetting = Settings.RegisterAddOnSetting(category,
		"AssKey_FontColor", "fontColor", AssKeyDB, Settings.VarType.Color, "Font Color", self.defaults.fontColor)
	fontColorSetting:SetValueChangedCallback(OnSettingChanged)
	Settings.CreateColorSwatch(category, fontColorSetting, "Color of the keybind text.")

	local outlineSetting = Settings.RegisterAddOnSetting(category,
		"AssKey_Outline", "outline", AssKeyDB, Settings.VarType.String, "Outline Style", self.defaults.outline)
	outlineSetting:SetValueChangedCallback(OnSettingChanged)
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
		"AssKey_ShadowEnabled", "shadowEnabled", AssKeyDB, Settings.VarType.Boolean, "Enable Shadow", self.defaults.shadowEnabled)
	shadowEnabledSetting:SetValueChangedCallback(OnSettingChanged)
	Settings.CreateCheckbox(category, shadowEnabledSetting, "Toggle display of shadow.")

	local shadowColorSetting = Settings.RegisterAddOnSetting(category,
		"AssKey_ShadowColor", "shadowColor", AssKeyDB, Settings.VarType.Color, "Shadow Color", self.defaults.shadowColor)
	shadowColorSetting:SetValueChangedCallback(OnSettingChanged)
	Settings.CreateColorSwatch(category, shadowColorSetting, "Color of the shadow behind the text.")

	local shadowOffsetXSetting = Settings.RegisterAddOnSetting(category,
		"AssKey_ShadowOffsetX", "shadowOffsetX", AssKeyDB, Settings.VarType.Number, "Shadow Offset X", self.defaults.shadowOffsetX)
	shadowOffsetXSetting:SetValueChangedCallback(OnSettingChanged)
	CreateSliderWithValue(shadowOffsetXSetting, -20, 20, 1, "Horizontal position of the shadow.")

	local shadowOffsetYSetting = Settings.RegisterAddOnSetting(category,
		"AssKey_ShadowOffsetY", "shadowOffsetY", AssKeyDB, Settings.VarType.Number, "Shadow Offset Y", self.defaults.shadowOffsetY)
	shadowOffsetYSetting:SetValueChangedCallback(OnSettingChanged)
	CreateSliderWithValue(shadowOffsetYSetting, -20, 20, 1, "Vertical position of the shadow.")

	Settings.RegisterAddOnCategory(category)
end

function AssKey_Settings()
	if not InCombatLockdown() then
		Settings.OpenToCategory(AssKey.category:GetID())
	end
end

SLASH_ASSKEY1 = "/ak"
SLASH_ASSKEY2 = "/asskey"
SlashCmdList["ASSKEY"] = AssKey_Settings
