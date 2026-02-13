AssKey = CreateFrame("Frame", "AssKeyFrame", UIParent)
AssKey.name = "AssKey"
AssKey.defaults = { fontSize = 24, offsetX = 0, offsetY = 0 }

AssKey:SetFrameStrata("TOOLTIP")
AssKey:SetFrameLevel(9999)
AssKey:SetSize(50, 50)
AssKey:Hide()

AssKey.keybind = AssKey:CreateFontString(nil, "OVERLAY")
AssKey.keybind:SetFont(GameFontNormal:GetFont(), 24, "THICKOUTLINE")
AssKey.keybind:SetPoint("CENTER", 0, 0)
AssKey.keybind:SetTextColor(1, 1, 1)
AssKey.keybind:SetShadowColor(0, 0, 0, 1)
AssKey.keybind:SetShadowOffset(1, -1)
AssKey.keybind:SetDrawLayer("OVERLAY", 7)
AssKey.keybind:SetAlpha(1.0)

AssKey.cachedSBAButton = nil
AssKey.lastScanTime = 0
AssKey.scanCooldown = 2.0
AssKey.hooked = false
AssKey.pendingUpdate = false

function AssKey:OnEvent(event, ...)
	if self[event] then
		self[event](self, event, ...)
	else
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

function AssKey:ScheduleUpdate()
	if self.pendingUpdate then return end
	self.pendingUpdate = true
	C_Timer.After(0.1, function()
		self.pendingUpdate = false
		self:Update()
	end)
end

function AssKey:FindSBAOverlayButton()
	if not C_AssistedCombat or not C_AssistedCombat.GetNextCastSpell or
		C_AssistedCombat.GetNextCastSpell() <= 0 then
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

						if not self.hooked then
							hooksecurefunc(frame, "UpdateAssistedCombatRotationFrame", function()
								self:ScheduleUpdate()
							end)
							self.hooked = true
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

function AssKey:GetKeybindForSpell(spellID)
	for slot = 1, 120 do
		local actionType, id = GetActionInfo(slot)

		if (actionType == "spell" or actionType == "macro") and id == spellID then
			local bindingKey

			if slot <= 12 then
				bindingKey = GetBindingKey("ACTIONBUTTON" .. slot)
			elseif slot <= 24 then
				bindingKey = GetBindingKey("MULTIACTIONBAR1BUTTON" .. (slot - 12))
			elseif slot <= 36 then
				bindingKey = GetBindingKey("MULTIACTIONBAR2BUTTON" .. (slot - 24))
			elseif slot <= 48 then
				bindingKey = GetBindingKey("MULTIACTIONBAR4BUTTON" .. (slot - 36))
			elseif slot <= 60 then
				bindingKey = GetBindingKey("MULTIACTIONBAR3BUTTON" .. (slot - 48))
			elseif slot <= 72 then
				bindingKey = GetBindingKey("MULTIACTIONBAR5BUTTON" .. (slot - 60))
			elseif slot <= 84 then
				bindingKey = GetBindingKey("MULTIACTIONBAR6BUTTON" .. (slot - 72))
			elseif slot <= 96 then
				bindingKey = GetBindingKey("MULTIACTIONBAR7BUTTON" .. (slot - 84))
			end

			if bindingKey then
				return GetBindingText(bindingKey)
			end
		end
	end
	return ""
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

	local font = self.keybind:GetFont()
	self.keybind:SetFont(font, AssKeyDB.fontSize, "THICKOUTLINE")
	self.keybind:SetText(keybind)
	self:Show()
end

function AssKey:InitializeOptions()
	local category = Settings.RegisterVerticalLayoutCategory(self.name)
	self.category = category
	Settings.RegisterAddOnCategory(category)

	local fontSizeOptions = Settings.CreateSliderOptions(8, 72, 1)
	fontSizeOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right,
		function(value) return string.format("%d pt", value) end)

	Settings.CreateSlider(category,
		Settings.RegisterAddOnSetting(category, "AssKey_FontSize", "fontSize",
			AssKeyDB, Settings.VarType.Number, "Font Size", self.defaults.fontSize),
		fontSizeOptions)

	local offsetXOptions = Settings.CreateSliderOptions(-200, 200, 5)
	offsetXOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right,
		function(value) return string.format("%d px", value) end)

	Settings.CreateSlider(category,
		Settings.RegisterAddOnSetting(category, "AssKey_OffsetX", "offsetX",
			AssKeyDB, Settings.VarType.Number, "Horizontal Offset", self.defaults.offsetX),
		offsetXOptions)

	local offsetYOptions = Settings.CreateSliderOptions(-200, 200, 5)
	offsetYOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right,
		function(value) return string.format("%d px", value) end)

	Settings.CreateSlider(category,
		Settings.RegisterAddOnSetting(category, "AssKey_OffsetY", "offsetY",
			AssKeyDB, Settings.VarType.Number, "Vertical Offset", self.defaults.offsetY),
		offsetYOptions)
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
	if addonName == "AssKey" then
		AssKey_Settings()
	end
end
