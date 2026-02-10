local ADDON_NAME = "AssKey"

AssKeyDB = AssKeyDB or {
	showKeybinds = true,
	fontSize = 12,
	position = "BOTTOM", -- "BOTTOM", "TOP", "LEFT", "RIGHT"
	offsetX = 0,
	offsetY = -15,
}

local hookedFrames = {}
local keybindTexts = {}
local keybindCache = {}

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

-- Event handling
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ASSISTED_COMBAT_ACTION_SPELL_CAST")
eventFrame:RegisterEvent("UPDATE_BINDINGS")
eventFrame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")

eventFrame:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_ENTERING_WORLD" then
		ScanAndHookFrames()
		C_Timer.After(1, ScanAndHookFrames) -- Second pass after UI loads
	elseif event == "ASSISTED_COMBAT_ACTION_SPELL_CAST" then
		UpdateAllKeybinds()
	elseif event == "UPDATE_BINDINGS" or event == "ACTIONBAR_SLOT_CHANGED" then
		wipe(keybindCache)
		UpdateAllKeybinds()
	elseif event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" then
		UpdateAllKeybinds()
	end
end)

-- Settings panel (optional - can remove if you don't want settings)
local function CreateSettingsPanel()
	local panel = CreateFrame("Frame")
	panel.name = "AssKey"

	-- Title
	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("Single-Button Assistant Keybinds")

	-- Show Keybinds checkbox
	local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
	cb:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -20)
	cb:SetChecked(AssKeyDB.showKeybinds)
	cb.text:SetText("Show Keybinds")
	cb:SetScript("OnClick", function(self)
		AssKeyDB.showKeybinds = self:GetChecked()
		UpdateAllKeybinds()
	end)

	-- Font Size slider
	local sizeText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	sizeText:SetPoint("TOPLEFT", cb, "BOTTOMLEFT", 0, -30)
	sizeText:SetText("Font Size:")

	local slider = CreateFrame("Slider", nil, panel, "UISliderTemplate")
	slider:SetPoint("TOPLEFT", sizeText, "BOTTOMLEFT", 0, -10)
	slider:SetSize(200, 20)
	slider:SetMinMaxValues(8, 20)
	slider:SetValueStep(1)
	slider:SetValue(AssKeyDB.fontSize or 12)
	slider:SetScript("OnValueChanged", function(self, value)
		AssKeyDB.fontSize = math.floor(value)
		UpdateAllKeybinds()
	end)

	InterfaceOptions_AddCategory(panel)
end

-- Slash command
SLASH_SINGLEBUTTONKEYBINDS1 = "/asskey"
SLASH_SINGLEBUTTONKEYBINDS2 = "/ak"
SlashCmdList["ASSKEYKEYBINDS"] = function()
	InterfaceOptionsFrame_OpenToCategory("AssKey")
end

-- Initialize
CreateSettingsPanel()
