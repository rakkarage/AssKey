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

local hookedFrames = {}
local keybindTexts = {}
local keybindCache = {}

function AssKey:OnEvent(event, addonName, ...)
	if event == "ADDON_LOADED" and addonName == AssKey.name then
		self:InitializeOptions()
	elseif event == "PLAYER_ENTERING_WORLD" then
		self:ScanAndHookFrames()
		C_Timer.After(1, function() self:ScanAndHookFrames() end)
	elseif event == "ASSISTED_COMBAT_ACTION_SPELL_CAST" then
		self:UpdateAllKeybinds()
	elseif event == "UPDATE_BINDINGS" or event == "ACTIONBAR_SLOT_CHANGED" then
		wipe(self.keybindCache)
		self:UpdateAllKeybinds()
	elseif event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" then
		self:UpdateAllKeybinds()
	end
end

AssKey:SetScript("OnEvent", AssKey.OnEvent)
AssKey:RegisterEvent("ADDON_LOADED")
AssKey:RegisterEvent("PLAYER_ENTERING_WORLD")
AssKey:RegisterEvent("ASSISTED_COMBAT_ACTION_SPELL_CAST")
AssKey:RegisterEvent("UPDATE_BINDINGS")
AssKey:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
AssKey:RegisterEvent("PLAYER_REGEN_ENABLED")
AssKey:RegisterEvent("PLAYER_REGEN_DISABLED")

-- Get keybind for a spell ID
local function GetKeybindForSpell(spellID)
	if not spellID or keybindCache[spellID] == false then
		return ""
	end

	-- Check cache first
	if keybindCache[spellID] then
		return keybindCache[spellID]
	end

	-- Find which action bar slot has this spell
	for slot = 1, 120 do
		local actionType, id = GetActionInfo(slot)
		if actionType == "spell" and id == spellID then
			local buttonNum = ((slot - 1) % 12) + 1
			local binding = GetBindingKey("ACTIONBUTTON" .. buttonNum)
			if binding then
				keybindCache[spellID] = GetBindingText(binding)
				return keybindCache[spellID]
			end
			break
		end
	end

	-- Cache negative result
	keybindCache[spellID] = false
	return ""
end

-- Get current recommended spell
local function GetCurrentRecommendedSpell()
	-- Modern method (10.1.7+)
	if C_AssistedCombat and C_AssistedCombat.GetNextSpell then
		return C_AssistedCombat.GetNextSpell()
	end

	-- Legacy fallback: Look for SingleButtonAssistFrame
	local frame = _G["SingleButtonAssistFrame"]
	if frame and frame:IsVisible() then
		-- Try to get spell from tooltip
		local oldOwner = GameTooltip:GetOwner()
		GameTooltip:SetOwner(frame, "ANCHOR_NONE")

		if frame:GetScript("OnEnter") then
			frame:GetScript("OnEnter")(frame)
		end

		local tooltipText = GameTooltipTextLeft1 and GameTooltipTextLeft1:GetText()
		if tooltipText then
			local spellName = tooltipText:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
			local spellID = GetSpellInfo(spellName)
			GameTooltip:SetOwner(oldOwner)
			return spellID
		end
		GameTooltip:SetOwner(oldOwner)
	end

	return nil
end

-- Create or update keybind text on a frame
local function UpdateKeybindOnFrame(frame, spellID)
	if not frame or not frame:IsVisible() then return end

	local text = keybindTexts[frame]
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
		keybindTexts[frame] = text
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
		local keybind = GetKeybindForSpell(spellID)
		if keybind ~= "" then
			text:SetText(keybind)
			text:Show()
			return
		end
	end

	text:Hide()
end

-- Hook into Blizzard's frames
local function HookSingleButtonFrame(frame)
	if hookedFrames[frame] then return end
	hookedFrames[frame] = true

	-- Update keybind when frame updates
	if frame.UpdateAssistedCombatRotationFrame then
		hooksecurefunc(frame, "UpdateAssistedCombatRotationFrame", function(self)
			local spellID = GetCurrentRecommendedSpell()
			UpdateKeybindOnFrame(self, spellID)
		end)
	end

	-- Also update on show
	hooksecurefunc(frame, "Show", function(self)
		local spellID = GetCurrentRecommendedSpell()
		UpdateKeybindOnFrame(self, spellID)
	end)

	-- Initial update
	local spellID = GetCurrentRecommendedSpell()
	UpdateKeybindOnFrame(frame, spellID)
end

-- Scan for Single-Button Assistant frames
local function ScanAndHookFrames()
	local frame = EnumerateFrames()
	while frame do
		if frame.UpdateAssistedCombatRotationFrame and not hookedFrames[frame] then
			HookSingleButtonFrame(frame)
		end
		frame = EnumerateFrames(frame)
	end
end

-- Update all keybinds
local function UpdateAllKeybinds()
	local spellID = GetCurrentRecommendedSpell()
	for frame, _ in pairs(hookedFrames) do
		if frame:IsVisible() then
			UpdateKeybindOnFrame(frame, spellID)
		end
	end
end

-- Slash command
SLASH_SINGLEBUTTONKEYBINDS1 = "/asskey"
SLASH_SINGLEBUTTONKEYBINDS2 = "/ak"
SlashCmdList["ASSKEYKEYBINDS"] = function()
	AssKey_Settings()
end

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
		print("MinimapAutoZoom: Cannot open settings while in combat!")
	end
end

-- Settings panel (optional - can remove if you don't want settings)
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
