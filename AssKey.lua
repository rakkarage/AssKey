AssKey = CreateFrame("Frame", "AssKeyFrame", UIParent)
AssKey.name = "AssKey"
AssKey.defaults = {
	fontSize = 24,
	offsetX = 0,
	offsetY = 0,
	fontColor = "ffffffff",
	shadowEnabled = true,
	shadowColor = "ff000000",
	shadowOffsetX = 1,
	shadowOffsetY = -1,
	outline = "THICKOUTLINE",
}

AssKey:SetFrameStrata("TOOLTIP")
AssKey:SetFrameLevel(9999)
AssKey:SetSize(50, 50)
AssKey:Hide()

AssKey.keybind = AssKey:CreateFontString(nil, "OVERLAY")
AssKey.keybind:SetPoint("CENTER", 0, 0)
AssKey.keybind:SetDrawLayer("OVERLAY", 7)

AssKey.cachedSBAButton = nil
AssKey.lastScanTime = 0
AssKey.scanCooldown = 2.0
AssKey.pendingUpdate = false

AssKey.spellToSlot = {}
AssKey.slotToBinding = {}
AssKey.mapsDirty = true

function AssKey:OnEvent(event, ...)
	if self[event] then
		self[event](self, event, ...)
	else
		self.mapsDirty = true
		self:ScheduleUpdate()
	end
end

AssKey:SetScript("OnEvent", AssKey.OnEvent)
AssKey:RegisterEvent("ADDON_LOADED")

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

	self:UnregisterEvent("ADDON_LOADED")
end

function AssKey:BuildSpellSlotMap()
	wipe(self.spellToSlot)
	wipe(self.slotToBinding)

	for slot = 1, 120 do
		local actionType, id = GetActionInfo(slot)
		if (actionType == "spell" or actionType == "macro") and id and id > 0 then
			local bindingKey = self:GetBindingKeyForSlot(slot)
			if bindingKey and not self.spellToSlot[id] then
				self.spellToSlot[id] = slot
				self.slotToBinding[slot] = GetBindingText(bindingKey)
			end
		end
	end

	self.mapsDirty = false
end

function AssKey:GetBindingKeyForSlot(slot)
	if slot <= 12 then
		return GetBindingKey("ACTIONBUTTON" .. slot)
	elseif slot <= 24 then
		return GetBindingKey("ACTIONBUTTON" .. (slot - 12))
	elseif slot <= 36 then
		return GetBindingKey("MULTIACTIONBAR3BUTTON" .. (slot - 24))
	elseif slot <= 48 then
		return GetBindingKey("MULTIACTIONBAR4BUTTON" .. (slot - 36))
	elseif slot <= 60 then
		return GetBindingKey("MULTIACTIONBAR2BUTTON" .. (slot - 48))
	elseif slot <= 72 then
		return GetBindingKey("MULTIACTIONBAR1BUTTON" .. (slot - 60))
	elseif slot >= 145 and slot <= 156 then
		return GetBindingKey("MULTIACTIONBAR5BUTTON" .. (slot - 144))
	elseif slot >= 157 and slot <= 168 then
		return GetBindingKey("MULTIACTIONBAR6BUTTON" .. (slot - 156))
	elseif slot >= 169 and slot <= 180 then
		return GetBindingKey("MULTIACTIONBAR7BUTTON" .. (slot - 168))
	end
	return nil
end

function AssKey:GetKeybindForSpell(spellID)
	if self.mapsDirty then self:BuildSpellSlotMap() end

	local slot = self.spellToSlot[spellID]
	if not slot then return "" end

	if not self.slotToBinding[slot] then
		local bindingKey = self:GetBindingKeyForSlot(slot)
		self.slotToBinding[slot] = bindingKey and GetBindingText(bindingKey) or ""
	end

	return self.slotToBinding[slot]
end

function AssKey:ScheduleUpdate()
	if self.pendingUpdate then return end
	self.pendingUpdate = true
	C_Timer.After(0.1, function()
		self.pendingUpdate = false
		self:Update()
	end)
end

function AssKey:FindSBAOverlayButton()
	if not C_AssistedCombat or not C_AssistedCombat.GetNextCastSpell then
		self.cachedSBAButton = nil
		return nil
	end

	local spellID = C_AssistedCombat.GetNextCastSpell()
	if not spellID or spellID <= 0 then
		self.cachedSBAButton = nil
		return nil
	end

	if self.cachedSBAButton and self.cachedSBAButton:IsShown() then
		for i = 1, self.cachedSBAButton:GetNumChildren() do
			local child = select(i, self.cachedSBAButton:GetChildren())
			if child.ActiveFrame and child.ActiveFrame:IsShown() then
				return self.cachedSBAButton
			end
		end
	end

	local now = GetTime()
	if now - self.lastScanTime < self.scanCooldown then
		return self.cachedSBAButton
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

	self.cachedSBAButton = nil
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

	if C_AssistedCombat.GetRotationSpells then
		local spells = C_AssistedCombat.GetRotationSpells()
		if spells and #spells > 0 then
			return spells[1]
		end
	end

	return nil
end

function AssKey:Update()
	local button = self:FindSBAOverlayButton()
	if not button then
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

	self:ClearAllPoints()
	self:SetPoint("CENTER", button, "CENTER", AssKeyDB.offsetX, AssKeyDB.offsetY)

	local fontPath = GameFontNormal:GetFont()
	local outline = AssKeyDB.outline or self.defaults.outline
	self.keybind:SetFont(fontPath, AssKeyDB.fontSize, outline)

	local color = CreateColorFromHexString(AssKeyDB.fontColor)
	if color then
		self.keybind:SetTextColor(color:GetRGBA())
	else
		self.keybind:SetTextColor(1, 1, 1, 1)
	end

	if AssKeyDB.shadowEnabled then
		local color = CreateColorFromHexString(AssKeyDB.shadowColor)
		if color then
			self.keybind:SetShadowColor(color:GetRGBA())
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

function AssKey:InitializeOptions()
	local category = Settings.RegisterVerticalLayoutCategory(self.name)
	self.category = category

	local function OnSettingChanged()
		self:ScheduleUpdate()
	end

	local fontSizeSetting = Settings.RegisterAddOnSetting(category, "AssKey_FontSize", "fontSize", AssKeyDB,
		Settings.VarType.Number, "Font Size", self.defaults.fontSize)
	fontSizeSetting:SetValueChangedCallback(OnSettingChanged)
	Settings.CreateSlider(category, fontSizeSetting, Settings.CreateSliderOptions(8, 72, 1))

	local offsetXSetting = Settings.RegisterAddOnSetting(category, "AssKey_OffsetX", "offsetX", AssKeyDB,
		Settings.VarType.Number, "Horizontal Offset", self.defaults.offsetX)
	offsetXSetting:SetValueChangedCallback(OnSettingChanged)
	Settings.CreateSlider(category, offsetXSetting, Settings.CreateSliderOptions(-200, 200, 5))

	local offsetYSetting = Settings.RegisterAddOnSetting(category, "AssKey_OffsetY", "offsetY", AssKeyDB,
		Settings.VarType.Number, "Vertical Offset", self.defaults.offsetY)
	offsetYSetting:SetValueChangedCallback(OnSettingChanged)
	Settings.CreateSlider(category, offsetYSetting, Settings.CreateSliderOptions(-200, 200, 5))

	local fontColorSetting = Settings.RegisterAddOnSetting(category, "AssKey_FontColor", "fontColor", AssKeyDB,
		Settings.VarType.Color, "Font Color", self.defaults.fontColor)
	fontColorSetting:SetValueChangedCallback(OnSettingChanged)
	Settings.CreateColorSwatch(category, fontColorSetting)

	local outlineSetting = Settings.RegisterAddOnSetting(category, "AssKey_Outline", "outline", AssKeyDB,
		Settings.VarType.String, "Outline Style", self.defaults.outline)
	outlineSetting:SetValueChangedCallback(OnSettingChanged)
	Settings.CreateDropdown(category, outlineSetting, function()
		local container = Settings.CreateControlTextContainer()
		container:Add("", "None")
		container:Add("OUTLINE", "Outline")
		container:Add("THICKOUTLINE", "Thick Outline")
		container:Add("MONOCHROME", "Monochrome")
		container:Add("OUTLINE,MONOCHROME", "Outline + Monochrome")
		return container:GetData()
	end)

	local shadowEnabledSetting = Settings.RegisterAddOnSetting(category, "AssKey_ShadowEnabled", "shadowEnabled",
		AssKeyDB, Settings.VarType.Boolean, "Enable Shadow", self.defaults.shadowEnabled)
	shadowEnabledSetting:SetValueChangedCallback(OnSettingChanged)
	Settings.CreateCheckbox(category, shadowEnabledSetting)

	local shadowColorSetting = Settings.RegisterAddOnSetting(category, "AssKey_ShadowColor", "shadowColor", AssKeyDB,
		Settings.VarType.Color, "Shadow Color", self.defaults.shadowColor)
	shadowColorSetting:SetValueChangedCallback(OnSettingChanged)
	Settings.CreateColorSwatch(category, shadowColorSetting)

	local shadowOffsetXSetting = Settings.RegisterAddOnSetting(category, "AssKey_ShadowOffsetX", "shadowOffsetX",
		AssKeyDB, Settings.VarType.Number, "Shadow Offset X", self.defaults.shadowOffsetX)
	shadowOffsetXSetting:SetValueChangedCallback(OnSettingChanged)
	Settings.CreateSlider(category, shadowOffsetXSetting, Settings.CreateSliderOptions(-20, 20, 1))

	local shadowOffsetYSetting = Settings.RegisterAddOnSetting(category, "AssKey_ShadowOffsetY", "shadowOffsetY",
		AssKeyDB, Settings.VarType.Number, "Shadow Offset Y", self.defaults.shadowOffsetY)
	shadowOffsetYSetting:SetValueChangedCallback(OnSettingChanged)
	Settings.CreateSlider(category, shadowOffsetYSetting, Settings.CreateSliderOptions(-20, 20, 1))

	Settings.RegisterAddOnCategory(category)
end

SLASH_ASSKEY1 = "/ak"
SLASH_ASSKEY2 = "/asskey"

SlashCmdList["ASSKEY"] = function()
	AssKey_Settings()
end

function AssKey_Settings()
	if not InCombatLockdown() then
		Settings.OpenToCategory(AssKey.category:GetID())
	end
end

function AssKey_OnAddonCompartmentClick(addonName)
	if addonName == AssKey.name then
		AssKey_Settings()
	end
end
