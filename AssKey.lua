local AssKey = CreateFrame("Frame")
AssKey.name = "AssKey"
AssKey.defaults = {
	showKeybinds = true,
	fontSize = 12,
	position = "BOTTOM",
	offsetX = 0,
	offsetY = -15,
}

AssKeyDB = AssKeyDB or {}
for key, value in pairs(AssKey.defaults) do
	if AssKeyDB[key] == nil then
		AssKeyDB[key] = value
	end
end

-- Runtime storage in AssKey table
AssKey.hookedFrames = {}
AssKey.keybindTexts = {}
AssKey.keybindCache = {}

-- ========================
-- ASSKEY METHODS
-- ========================
function AssKey:OnEvent(event, addonName, ...)
	if event == "ADDON_LOADED" and addonName == self.name then
		self:InitializeOptions()
		self:RegisterEvent("PLAYER_ENTERING_WORLD")
		self:RegisterEvent("UPDATE_BINDINGS")
		self:RegisterEvent("ACTIONBAR_SLOT_CHANGED")

		-- AssKey:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED") -- For spell casts
		-- AssKey:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED") -- When you cast something
		-- AssKey:RegisterEvent("SPELL_UPDATE_COOLDOWN") -- When cooldowns update
		-- AssKey:RegisterEvent("SPELL_UPDATE_CHARGES") -- When charges update
	elseif event == "PLAYER_ENTERING_WORLD" then
		self:ScanAndHookFrames()
		C_Timer.After(1, function() self:ScanAndHookFrames() end)
	elseif event == "UPDATE_BINDINGS" or event == "ACTIONBAR_SLOT_CHANGED" then
		wipe(AssKey.keybindCache)
		self:UpdateAllKeybinds()
		-- elseif event == "COMBAT_LOG_EVENT_UNFILTERED" or
		-- 	event == "UNIT_SPELLCAST_SUCCEEDED" or
		-- 	event == "SPELL_UPDATE_COOLDOWN" or
		-- 	event == "SPELL_UPDATE_CHARGES" then
		-- 	self:UpdateAllKeybinds()
	end
end

function AssKey:ScanAndHookFrames()
	local frame = EnumerateFrames()
	while frame do
		if frame.UpdateAssistedCombatRotationFrame and not self.hookedFrames[frame] then
			self:HookSingleButtonFrame(frame)
		end
		frame = EnumerateFrames(frame)
	end
end

function AssKey:HookSingleButtonFrame(frame)
	if self.hookedFrames[frame] then return end
	self.hookedFrames[frame] = true

	-- Update keybind when frame updates
	if frame.UpdateAssistedCombatRotationFrame then
		hooksecurefunc(frame, "UpdateAssistedCombatRotationFrame", function(self)
			local spellID = AssKey_GetCurrentRecommendedSpell()
			AssKey_UpdateKeybindOnFrame(self, spellID)
		end)
	end

	-- Also update on show
	hooksecurefunc(frame, "Show", function(self)
		local spellID = AssKey_GetCurrentRecommendedSpell()
		AssKey_UpdateKeybindOnFrame(self, spellID)
	end)

	-- Initial update
	local spellID = AssKey_GetCurrentRecommendedSpell()
	AssKey_UpdateKeybindOnFrame(frame, spellID)
end

function AssKey:UpdateAllKeybinds()
	local spellID = AssKey_GetCurrentRecommendedSpell()
	for frame, _ in pairs(self.hookedFrames) do
		if frame:IsVisible() then
			AssKey_UpdateKeybindOnFrame(frame, spellID)
		end
	end
end

-- ========================
-- HELPER FUNCTIONS (local)
-- ========================
function AssKey_GetKeybindForSpell(spellID)
	if not spellID or AssKey.keybindCache[spellID] == false then
		print("[AssKey] No spellID provided:", spellID)
		return ""
	end

	--	print("[AssKey] Looking for keybind for spell:", spellID)

	-- Check cache first
	if AssKey.keybindCache[spellID] then
		return AssKey.keybindCache[spellID]
	end

	-- Find which action bar slot has this spell
	for slot = 1, 120 do
		local actionType, id = GetActionInfo(slot)
		if actionType == "spell" and id == spellID then
			local buttonNum = ((slot - 1) % 12) + 1
			local bindingKey = GetBindingKey("ACTIONBUTTON" .. buttonNum)
			local bindingText = bindingKey and GetBindingText(bindingKey) or "NO BINDING"
			print(string.format("[AssKey] FOUND! Slot:%d, Bar:%d, Button:%d, Binding:%s, Text:%s",
				slot, math.floor((slot - 1) / 12) + 1, buttonNum, bindingKey or "nil", bindingText))
			if bindingKey then
				AssKey.keybindCache[spellID] = bindingText
				return bindingText
			end
			break
		end
	end

	-- Cache negative result
	AssKey.keybindCache[spellID] = false
	return ""
end

function AssKey_GetCurrentRecommendedSpell()
	if not C_AssistedCombat then return nil end

	-- -- Method 1: GetActionSpell() - Most likely for the current recommendation
	-- if C_AssistedCombat.GetActionSpell then
	-- 	local spellID = C_AssistedCombat.GetActionSpell()
	-- 	if spellID and spellID > 0 then
	-- 		return spellID
	-- 	end
	-- end

	-- Method 2: GetNextCastSpell() - For what you're about to cast
	if C_AssistedCombat.GetNextCastSpell then
		local spellID = C_AssistedCombat.GetNextCastSpell()
		if spellID and spellID > 0 then
			return spellID
		end
	end

	-- Method 3: GetRotationSpells() - Returns multiple spells, first is current
	if C_AssistedCombat.GetRotationSpells then
		local spells = C_AssistedCombat.GetRotationSpells()
		if spells and #spells > 0 then
			return spells[1] -- First spell is current recommendation
		end
	end

	return nil
end

function AssKey_UpdateKeybindOnFrame(frame, spellID)
	if not frame or not frame:IsVisible() then return end

	local text = AssKey.keybindTexts[frame]
	local showKeybinds = AssKeyDB.showKeybinds

	-- Hide if disabled
	if not showKeybinds then
		if text then
			text:Hide()
		end
		return
	end

	-- Create text if needed
	if not text then
		text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		text:SetTextColor(1, 1, 1)
		text:SetShadowOffset(1, -1)
		text:SetShadowColor(0, 0, 0, 1)
		AssKey.keybindTexts[frame] = text
	end

	-- Update font size
	local fontPath, _, fontFlags = text:GetFont()
	text:SetFont(fontPath, AssKeyDB.fontSize or 12, fontFlags)

	-- Position
	text:ClearAllPoints()
	local position = AssKeyDB.position or "BOTTOM"
	local offsetX = AssKeyDB.offsetX or 0
	local offsetY = AssKeyDB.offsetY or -15

	if position == "TOP" then
		text:SetPoint("TOP", frame, "BOTTOM", offsetX, -offsetY)
	elseif position == "LEFT" then
		text:SetPoint("RIGHT", frame, "LEFT", -offsetX, offsetY)
	elseif position == "RIGHT" then
		text:SetPoint("LEFT", frame, "RIGHT", offsetX, offsetY)
	else -- BOTTOM (default)
		text:SetPoint("BOTTOM", frame, "TOP", offsetX, offsetY)
	end

	-- Set text if we have a spell and keybind
	if spellID then
		local keybind = AssKey_GetKeybindForSpell(spellID)
		if keybind ~= "" then
			text:SetText(keybind)
			text:Show()
			-- text:SetTextColor(1, 0, 0, 1)
			-- text:SetDrawLayer("OVERLAY", 10)
			-- text:SetFrameStrata("TOOLTIP")

			-- ADD THESE DEBUG LINES:
			print("[AssKey] TEXT SET:", keybind, "on frame:", tostring(frame))
			print("  - Text color:", text:GetTextColor())
			print("  - Text alpha:", text:GetAlpha())
			print("  - Text shown:", text:IsShown())
			print("  - Frame level:", text:GetFrameLevel())
			print("  - Draw layer:", text:GetDrawLayer())

			return
		end
	end

	text:Hide()
end

-- ========================
-- SETTINGS & UI
-- ========================
function AssKey:InitializeOptions()
	local category = Settings.RegisterVerticalLayoutCategory(self.name)

	-- Show Keybinds checkbox
	Settings.CreateCheckbox(category,
		Settings.RegisterAddOnSetting(category, "AssKey_ShowKeybinds", "showKeybinds",
			AssKeyDB, Settings.VarType.Boolean, "Show Keybinds", true),
		"Display keybinds on Single-Button Assistant frames")

	-- Font Size slider
	local fontSizeOptions = Settings.CreateSliderOptions(8, 20, 1)
	fontSizeOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
		return string.format("%d px", value)
	end)

	Settings.CreateSlider(category,
		Settings.RegisterAddOnSetting(category, "AssKey_FontSize", "fontSize",
			AssKeyDB, Settings.VarType.Number, "Font Size", 12),
		fontSizeOptions, "Keybind text font size")

	Settings.RegisterAddOnCategory(category)
	self.category = category
end

-- Addon Compartment Function (referenced in TOC)
function AssKey_AddonCompartmentClick(addonName, buttonName, menuButtonFrame)
	if addonName == "AssKey" then
		AssKey_Settings()
	end
end

function AssKey_Settings()
	if not InCombatLockdown() then
		if AssKey.category then
			Settings.OpenToCategory(AssKey.category:GetID())
		end
	else
		print("AssKey: Cannot open settings while in combat!")
	end
end

-- ========================
-- SLASH COMMANDS
-- ========================
SLASH_ASSKEY1 = "/asskey"
SLASH_ASSKEY2 = "/ak"
SlashCmdList["ASSKEY"] = function()
	AssKey_Settings()
end

SLASH_ASSKEYDEBUG1 = "/asskeydebug"
SlashCmdList["ASSKEYDEBUG"] = function()
	print("=== AssKey Debug ===")
	print("C_AssistedCombat exists:", C_AssistedCombat ~= nil)
	if C_AssistedCombat then
		print("C_AssistedCombat.GetNextSpell exists:", C_AssistedCombat.GetNextSpell ~= nil)
	end

	local spellID = AssKey_GetCurrentRecommendedSpell()
	print("GetNextSpell() returned:", spellID or "nil")

	print("Assist frames found:", #AssKey.hookedFrames)
	for frame, _ in pairs(AssKey.hookedFrames) do
		print(" - Frame:", tostring(frame))
	end
end

SLASH_ASSKEYAPI1 = "/asskeyapi"
SlashCmdList["ASSKEYAPI"] = function()
	print("=== C_AssistedCombat API ===")
	for key, value in pairs(C_AssistedCombat) do
		if type(value) == "function" then
			print("  function: C_AssistedCombat." .. key)
		else
			print("  property: C_AssistedCombat." .. key .. " = " .. tostring(value))
		end
	end
end

-- ========================
-- INITIALIZATION
-- ========================
AssKey:SetScript("OnEvent", AssKey.OnEvent)
AssKey:RegisterEvent("ADDON_LOADED")
