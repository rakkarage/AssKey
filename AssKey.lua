-- AssKey - Shows keybinds for Single Button Assistant recommendations
-- Attaches directly to the SBA button

AssKey = CreateFrame("Frame")
AssKey.name = "AssKey"
AssKey.defaults = {
	fontSize = 24,
	offsetX = 0,
	offsetY = 0,
}

-- Main frame for keybind display
AssKey.display = CreateFrame("Frame", "AssKeyMainFrame", UIParent)
AssKey.display:SetSize(200, 100)
AssKey.display:SetAlpha(1.0)
AssKey.display:Hide()

-- Keybind text
AssKey.display.keybind = AssKey.display:CreateFontString(nil, "OVERLAY")
AssKey.display.keybind:SetFont(GameFontNormal:GetFont(), 24, "THICKOUTLINE")
AssKey.display.keybind:SetPoint("CENTER", 0, 0)
AssKey.display.keybind:SetTextColor(1, 1, 1)
AssKey.display.keybind:SetShadowOffset(0, 0)
AssKey.display.keybind:SetAlpha(1.0)
AssKey.display.keybind:SetDrawLayer("OVERLAY", 7)

-- Cached references and state
AssKey.cachedSBAButton = nil
AssKey.lastScanTime = 0
AssKey.scanCooldown = 2.0 -- Only scan every 2 seconds max
AssKey.hooked = false
AssKey.pendingUpdate = false

-- Event handling
function AssKey:OnEvent(event, ...)
	self[event](self, event, ...)
end

AssKey:SetScript("OnEvent", AssKey.OnEvent)
AssKey:RegisterEvent("ADDON_LOADED")

function AssKey:ADDON_LOADED(event, name)
	if name == self.name then
		AssKeyDB = AssKeyDB or {}
		for key, value in pairs(self.defaults) do
			if AssKeyDB[key] == nil then
				AssKeyDB[key] = value
			end
		end

		self:InitializeOptions()
		self:InitializeEventHandlers()

		C_Timer.After(1, function()
			AssKey:Update()
		end)

		self:UnregisterEvent(event)
		print("AssKey loaded! Use /ak for commands or click addon compartment icon.")
	end
end

function AssKey:InitializeEventHandlers()
	-- Setup display frame
	self.display:SetParent(UIParent)
	self.display:SetFrameStrata("TOOLTIP")
	self.display:SetFrameLevel(9999)

	-- Event handling for action bar changes
	local eventFrame = CreateFrame("Frame")
	eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
	eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
	eventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
	eventFrame:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
	eventFrame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
	eventFrame:RegisterEvent("UPDATE_BINDINGS")

	eventFrame:SetScript("OnEvent", function(self, event)
		AssKey:ScheduleUpdate()
	end)
end

-- Schedule an update with debouncing
function AssKey:ScheduleUpdate()
	if not self.pendingUpdate then
		self.pendingUpdate = true
		C_Timer.After(0.1, function()
			self.pendingUpdate = false
			self:Update()
		end)
	end
end

-- Find which button has the SBA overlay active - OPTIMIZED with caching
function AssKey:FindSBAOverlayButton()
	-- Return cached button if it's still valid
	if self.cachedSBAButton and self.cachedSBAButton:IsShown() then
		-- Quick check if it still has active overlay
		for _, child in ipairs({ self.cachedSBAButton:GetChildren() }) do
			if child.ActiveFrame and child.ActiveFrame:IsShown() then
				return self.cachedSBAButton
			end
		end
	end

	-- Throttle full scans
	local now = GetTime()
	if now - self.lastScanTime < self.scanCooldown then
		return self.cachedSBAButton -- Return cached (might be nil)
	end

	self.lastScanTime = now

	-- Full scan only when cache is invalid and cooldown passed
	local Frame = EnumerateFrames()
	while Frame do
		if Frame.UpdateAssistedCombatRotationFrame then
			for _, child in ipairs({ Frame:GetChildren() }) do
				if child.ActiveFrame or child.InactiveTexture then
					if child:IsShown() or (child.ActiveFrame and child.ActiveFrame:IsShown()) then
						-- Cache the button we found
						self.cachedSBAButton = Frame

						-- Hook the button's update method to avoid constant polling
						if not self.hooked then
							hooksecurefunc(Frame, "UpdateAssistedCombatRotationFrame", function()
								-- When SBA updates its recommendation, update our display
								self:ScheduleUpdate()
							end)
							self.hooked = true
						end

						return Frame
					end
				end
			end
		end
		Frame = EnumerateFrames(Frame)
	end

	-- No button found, clear cache
	self.cachedSBAButton = nil
	return nil
end

-- Get keybind for a spell (works with direct spells and macros)
function AssKey:GetKeybindForSpell(spellID)
	for slot = 1, 120 do
		local actionType, id = GetActionInfo(slot)

		-- Check if this slot has our spell (either direct or in a macro)
		if (actionType == "spell" or actionType == "macro") and id == spellID then
			local bindingKey

			-- Map slot numbers to action bar bindings
			if slot <= 12 then
				bindingKey = GetBindingKey("ACTIONBUTTON" .. slot)
			elseif slot <= 24 then
				bindingKey = GetBindingKey("MULTIACTIONBAR3BUTTON" .. (slot - 12))
			elseif slot <= 36 then
				bindingKey = GetBindingKey("MULTIACTIONBAR4BUTTON" .. (slot - 24))
			elseif slot <= 48 then
				bindingKey = GetBindingKey("MULTIACTIONBAR1BUTTON" .. (slot - 36))
			elseif slot <= 60 then
				bindingKey = GetBindingKey("MULTIACTIONBAR2BUTTON" .. (slot - 48))
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

-- Get the currently recommended spell from SBA
function AssKey:GetCurrentRecommendedSpell()
	if not C_AssistedCombat then return nil end

	-- Try GetNextCastSpell - this is what shows the current recommendation
	if C_AssistedCombat.GetNextCastSpell then
		local spellID = C_AssistedCombat.GetNextCastSpell()
		if spellID and spellID > 0 then
			return spellID
		end
	end

	-- Fallback to GetRotationSpells
	if C_AssistedCombat.GetRotationSpells then
		local spells = C_AssistedCombat.GetRotationSpells()
		if spells and #spells > 0 then
			return spells[1]
		end
	end

	return nil
end

-- Update the keybind display
function AssKey:Update()
	-- Find the button with SBA overlay (uses cache now!)
	local button = self:FindSBAOverlayButton()

	if not button then
		self.display:Hide()
		return
	end

	-- Attach to the SBA overlay button
	self.display:ClearAllPoints()
	self.display:SetPoint("CENTER", button, "CENTER", AssKeyDB.offsetX, AssKeyDB.offsetY)

	-- Get the recommended spell and find its keybind
	local spellID = self:GetCurrentRecommendedSpell()
	if spellID and spellID > 0 then
		local keybind = self:GetKeybindForSpell(spellID)

		if keybind and keybind ~= "" then
			-- Update font size from settings
			local currentFont = self.display.keybind:GetFont()
			self.display.keybind:SetFont(currentFont, AssKeyDB.fontSize, "THICKOUTLINE")

			self.display.keybind:SetText(keybind)
			self.display:Show()
		else
			self.display:Hide()
		end
	else
		self.display:Hide()
	end
end

-- Addon compartment click handler
function AssKey_OnAddonCompartmentClick(addonName, buttonName)
	if addonName == "AssKey" then
		AssKey_Settings()
	end
end

-- Settings panel opener
function AssKey_Settings()
	if not InCombatLockdown() then
		Settings.OpenToCategory(AssKey.category:GetID())
	else
		print("AssKey: Cannot open settings while in combat!")
	end
end

-- Initialize settings panel using modern Settings API
function AssKey:InitializeOptions()
	local category, layout = Settings.RegisterVerticalLayoutCategory(self.name)
	self.category = category
	Settings.RegisterAddOnCategory(category)

	-- Font size slider
	local fontSizeOptions = Settings.CreateSliderOptions(8, 72, 1)
	fontSizeOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
		return string.format("%d pt", value)
	end)
	Settings.CreateSlider(category,
		Settings.RegisterAddOnSetting(category, "AssKey_FontSize", "fontSize", AssKeyDB, Settings.VarType.Number,
			"Font Size", self.defaults.fontSize),
		fontSizeOptions, "Size of the keybind text")

	-- X Offset slider
	local offsetXOptions = Settings.CreateSliderOptions(-200, 200, 5)
	offsetXOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
		return string.format("%d px", value)
	end)
	Settings.CreateSlider(category,
		Settings.RegisterAddOnSetting(category, "AssKey_OffsetX", "offsetX", AssKeyDB, Settings.VarType.Number,
			"Horizontal Offset", self.defaults.offsetX),
		offsetXOptions, "Move keybind left/right")

	-- Y Offset slider
	local offsetYOptions = Settings.CreateSliderOptions(-200, 200, 5)
	offsetYOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
		return string.format("%d px", value)
	end)
	Settings.CreateSlider(category,
		Settings.RegisterAddOnSetting(category, "AssKey_OffsetY", "offsetY", AssKeyDB, Settings.VarType.Number,
			"Vertical Offset", self.defaults.offsetY),
		offsetYOptions, "Move keybind up/down")
end

-- Slash commands
SLASH_ASSKEY1 = "/ak"
SLASH_ASSKEY2 = "/asskey"
SlashCmdList["ASSKEY"] = function(msg, editFrame, noOutput)
	AssKey_Settings()
end
