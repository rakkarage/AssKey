local Alpha = 0.0
AssKeyAlpha = AssKeyAlpha or Alpha

-- ---------------------------------------------------------------------
-- UTILITY FUNCTIONS (Add these at the top)
-- ---------------------------------------------------------------------
local function Clamp(Value, Min, Max)
    return math.min(math.max(Value, Min), Max)
end

local function Validate_Alpha()
    Alpha = Clamp(AssKeyAlpha or 0.0, 0, 1)
    AssKeyAlpha = Alpha
end

-- Initialize settings at the top (yes, move them here)
AssKeyShowKeybinds = AssKeyShowKeybinds or true
AssKeyFontSize = AssKeyFontSize or 12

-- ---------------------------------------------------------------------
-- KEYBIND SYSTEM
-- ---------------------------------------------------------------------
local KeybindFont = "GameFontHighlightSmall"
local KeybindTexts = {}
local LastKnownSpells = {}
local KeybindCache = {}
local KeybindUpdateTimer = nil

-- Get keybind for a spell ID
local function GetKeybindForSpell(spellID)
    if not spellID then return "" end
    
    -- Check cache first
    if KeybindCache[spellID] ~= nil then
        return KeybindCache[spellID]
    end
    
    local keybind = ""
    
    -- Check all action bar slots
    for slot = 1, 120 do  -- 1-12 per bar * 10 bars = 120 slots
        local actionType, id = GetActionInfo(slot)
        if actionType == "spell" and id == spellID then
            -- Calculate which button number this is (1-12)
            local buttonNum = ((slot - 1) % 12) + 1
            local binding = GetBindingKey("ACTIONBUTTON" .. buttonNum)
            
            if binding then
                keybind = GetBindingText(binding)
            end
            break
        end
    end
    
    KeybindCache[spellID] = keybind
    return keybind
end

-- Try to detect the current spell from the Single-Button Assistant
local function DetectCurrentSpellFromBlizzard()
    -- Method 1: Use C_AssistedCombat if available (modern approach)
    if C_AssistedCombat and C_AssistedCombat.GetNextSpell then
        return C_AssistedCombat.GetNextSpell()
    end
    
    -- Method 2: Scan tooltip of the main button (fallback)
    local mainButton = SingleButtonAssistFrame
    if mainButton and mainButton:IsVisible() then
        -- Temporarily show tooltip to get spell info
        local oldOwner = GameTooltip:GetOwner()
        GameTooltip:SetOwner(mainButton, "ANCHOR_NONE")
        
        -- Try to trigger tooltip update
        if mainButton:GetScript("OnEnter") then
            mainButton:GetScript("OnEnter")(mainButton)
        end
        
        -- Extract spell from tooltip
        local tooltipText = GameTooltipTextLeft1 and GameTooltipTextLeft1:GetText()
        if tooltipText then
            -- Clean color codes
            local spellName = tooltipText:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            local spellID = GetSpellInfo(spellName)
            GameTooltip:SetOwner(oldOwner) -- Restore original owner
            return spellID
        end
        GameTooltip:SetOwner(oldOwner) -- Restore original owner
    end
    
    return nil
end

-- Add keybind text to a frame
local function AddKeybindTextToFrame(frame, spellID)
    if not frame or not frame:IsVisible() then return end
    
    -- Don't add if keybinds are disabled
    if not AssKeyShowKeybinds then
        local existingText = KeybindTexts[frame]
        if existingText then
            existingText:Hide()
        end
        return
    end
    
    local keybindText = KeybindTexts[frame]
    if not keybindText then
        -- Create keybind text overlay
        keybindText = frame:CreateFontString(nil, "OVERLAY", KeybindFont)
        keybindText:SetPoint("BOTTOM", frame, "BOTTOM", 0, -15)
        keybindText:SetTextColor(1, 1, 1, 1)
        keybindText:SetShadowOffset(1, -1)
        keybindText:SetShadowColor(0, 0, 0, 1)
        keybindText:SetFont(keybindText:GetFont(), AssKeyFontSize or 12)
        keybindText:Hide()
        
        KeybindTexts[frame] = keybindText
    end
    
    -- Update font size if needed
    local fontPath, _, fontFlags = keybindText:GetFont()
    keybindText:SetFont(fontPath, AssKeyFontSize or 12, fontFlags)
    
    if spellID then
        local keybind = GetKeybindForSpell(spellID)
        if keybind ~= "" then
            keybindText:SetText(keybind)
            keybindText:SetAlpha(Alpha)
            keybindText:Show()
            LastKnownSpells[frame] = spellID
            return
        end
    end
    
    keybindText:Hide()
end

-- Update keybind position for frames with arrow textures
local function UpdateKeybindPosition(frame)
    local keybindText = KeybindTexts[frame]
    if not keybindText then return end
    
    -- Try to find a good position relative to the arrow
    if frame.InactiveTexture and frame.InactiveTexture:IsVisible() then
        -- Position below the arrow texture
        keybindText:ClearAllPoints()
        keybindText:SetPoint("TOP", frame.InactiveTexture, "BOTTOM", 0, -5)
    elseif frame.ActiveFrame and frame.ActiveFrame:IsVisible() then
        -- Position below the active frame
        keybindText:ClearAllPoints()
        keybindText:SetPoint("TOP", frame.ActiveFrame, "BOTTOM", 0, -5)
    else
        -- Default position at bottom of frame
        keybindText:ClearAllPoints()
        keybindText:SetPoint("BOTTOM", frame, "BOTTOM", 0, -15)
    end
end

-- Schedule keybind updates
local function ScheduleKeybindUpdate()
    if KeybindUpdateTimer then return end
    
    KeybindUpdateTimer = C_Timer.After(0.1, function()
        KeybindUpdateTimer = nil
        
        -- Update keybinds for all hooked frames
        local currentSpell = DetectCurrentSpellFromBlizzard()
        
        for frame, _ in pairs(Hooked_Buttons) do
            if frame:IsVisible() then
                -- Update keybind text
                AddKeybindTextToFrame(frame, currentSpell)
                UpdateKeybindPosition(frame)
                
                -- Also update for child frames
                for _, child in ipairs({frame:GetChildren()}) do
                    if child:IsVisible() then
                        AddKeybindTextToFrame(child, currentSpell)
                        UpdateKeybindPosition(child)
                    end
                end
            end
        end
    end)
end

-- ---------------------------------------------------------------------
-- HOOK SYSTEM (Modified to integrate keybinds)
-- ---------------------------------------------------------------------
local Hooked_Textures = {}
local Hooked_Buttons = {}
local Applying = false

local function Apply_Alpha(Texture)
    if not Applying then
        Applying = true
        Texture:SetAlpha(Alpha)
        Applying = false
    end
end

local function Hook_Texture(Texture)
    if Hooked_Textures[Texture] then
        Apply_Alpha(Texture)
        return
    end
    Hooked_Textures[Texture] = true
    Apply_Alpha(Texture)

    hooksecurefunc(Texture, "SetAlpha", function(Self, A)
        if not Applying and A ~= Alpha then
            Apply_Alpha(Self)
        end
    end)

    hooksecurefunc(Texture, "Show", function(Self)
        Apply_Alpha(Self)
    end)
end

local function Hook_Rotation_Frame(Frame)
    if not Frame then return end
    
    -- Store original frame reference
    if not Hooked_Buttons[Frame] then
        Hooked_Buttons[Frame] = true
        
        -- Add keybind text to this frame
        AddKeybindTextToFrame(Frame, nil)
        
        -- Update keybind when frame is shown
        hooksecurefunc(Frame, "Show", function(self)
            ScheduleKeybindUpdate()
        end)
        
        -- Update keybind when frame updates
        hooksecurefunc(Frame, "UpdateAssistedCombatRotationFrame", function(self)
            ScheduleKeybindUpdate()
        end)
    end
    
    -- Original texture hooks
    if Frame.InactiveTexture then Hook_Texture(Frame.InactiveTexture) end
    if Frame.ActiveFrame then
        Hook_Texture(Frame.ActiveFrame)
        if Frame.ActiveFrame.GetRegions then
            for _, Region in ipairs({Frame.ActiveFrame:GetRegions()}) do
                if Region:IsObjectType("Texture") then
                    Hook_Texture(Region)
                end
            end
        end
    end
    if Frame.GetRegions then
        for _, Region in ipairs({Frame:GetRegions()}) do
            if Region:IsObjectType("Texture") then
                Hook_Texture(Region)
            end
        end
    end
    
    -- Schedule keybind update
    ScheduleKeybindUpdate()
end

local function Scan_And_Hook()
    local Frame = EnumerateFrames()
    while Frame do
        if Frame.UpdateAssistedCombatRotationFrame and not Hooked_Buttons[Frame] then
            Hooked_Buttons[Frame] = true
            hooksecurefunc(Frame, "UpdateAssistedCombatRotationFrame", function(Self)
                ScheduleKeybindUpdate()
                for _, Child in ipairs({Self:GetChildren()}) do
                    if Child.ActiveFrame or Child.InactiveTexture then
                        Hook_Rotation_Frame(Child)
                    end
                end
            end)
            for _, Child in ipairs({Frame:GetChildren()}) do
                if Child.ActiveFrame or Child.InactiveTexture then
                    Hook_Rotation_Frame(Child)
                end
            end
        end
        Frame = EnumerateFrames(Frame)
    end
end

local function Reapply_All()
    for Texture in pairs(Hooked_Textures) do
        Apply_Alpha(Texture)
    end
    Scan_And_Hook()
    ScheduleKeybindUpdate() -- Update keybinds too
end

-- ---------------------------------------------------------------------
-- EVENT HANDLING
-- ---------------------------------------------------------------------
local Event_Frame = CreateFrame("Frame")

-- Add events for keybind updates
local Rescan_Events = {
    "PLAYER_ENTERING_WORLD",
    "PLAYER_SPECIALIZATION_CHANGED",
    "PLAYER_TALENT_UPDATE",
    "ACTIVE_TALENT_GROUP_CHANGED",
    "UPDATE_BONUS_ACTIONBAR",
    "UPDATE_EXTRA_ACTIONBAR",
    "UPDATE_OVERRIDE_ACTIONBAR",
    "ASSISTED_COMBAT_ACTION_SPELL_CAST", -- Important: When assistant suggests new spell
    "UPDATE_BINDINGS",
    "ACTIONBAR_SLOT_CHANGED",
    "SPELLS_CHANGED",
    "PLAYER_REGEN_ENABLED",
    "PLAYER_REGEN_DISABLED",
}

for _, Event in ipairs(Rescan_Events) do
    Event_Frame:RegisterEvent(Event)
end

local Pending_Scan = false
local function Schedule_Scan()
    if Pending_Scan then return end
    Pending_Scan = true
    C_Timer.After(0.1, function()
        Pending_Scan = false
        Validate_Alpha()
        Scan_And_Hook()
        ScheduleKeybindUpdate() -- Update keybinds
    end)
end

Event_Frame:SetScript("OnEvent", function(_, Event)
    if Event == "PLAYER_ENTERING_WORLD" then
        Validate_Alpha()
        Scan_And_Hook()
        C_Timer.After(0.5, function()
            Scan_And_Hook()
            ScheduleKeybindUpdate()
        end)
    elseif Event == "ASSISTED_COMBAT_ACTION_SPELL_CAST" then
        -- Immediately update keybind when new spell is suggested
        ScheduleKeybindUpdate()
    elseif Event == "UPDATE_BINDINGS" or Event == "ACTIONBAR_SLOT_CHANGED" or Event == "SPELLS_CHANGED" then
        -- Clear cache when bindings or spells change
        wipe(KeybindCache)
        ScheduleKeybindUpdate()
    elseif Event == "PLAYER_REGEN_ENABLED" or Event == "PLAYER_REGEN_DISABLED" then
        -- Update keybinds when entering/exiting combat
        ScheduleKeybindUpdate()
    else
        Schedule_Scan()
    end
end)

-- ---------------------------------------------------------------------
-- SETTINGS PANEL
-- ---------------------------------------------------------------------
local Settings_Category
do
    local Settings_Frame = CreateFrame("Frame")
    Settings_Frame:Hide()

    local Title = Settings_Frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    Title:SetPoint("TOPLEFT", 16, -16)
    Title:SetText("Enhanced Single-Button Assistant")

    -- Arrow Transparency Section
    local ArrowSection = Settings_Frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ArrowSection:SetPoint("TOPLEFT", Title, "BOTTOMLEFT", 0, -20)
    ArrowSection:SetText("Arrow Transparency:")

    local Slider = CreateFrame("Slider", "AssKeySlider", Settings_Frame, "UISliderTemplate")
    Slider:SetSize(300, 20)
    Slider:SetPoint("TOPLEFT", ArrowSection, "BOTTOMLEFT", 0, -10)
    Slider:SetMinMaxValues(0, 1)
    Slider:SetValueStep(0.01)
    Slider:SetObeyStepOnDrag(true)

    local Low_Text = Slider:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    Low_Text:SetPoint("TOPLEFT", Slider, "BOTTOMLEFT", 0, -2)
    Low_Text:SetText("0%")

    local High_Text = Slider:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    High_Text:SetPoint("TOPRIGHT", Slider, "BOTTOMRIGHT", 0, -2)
    High_Text:SetText("100%")

    local Percent_Text = Slider:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    Percent_Text:SetPoint("TOP", Slider, "BOTTOM", 0, -2)

    -- Keybind Options Section
    local KeybindSection = Settings_Frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    KeybindSection:SetPoint("TOPLEFT", Slider, "BOTTOMLEFT", 0, -40)
    KeybindSection:SetText("Keybind Display:")

    -- Show Keybinds Checkbox
    local ShowKeybindsCheckbox = CreateFrame("CheckButton", "AssKeyShowKeybinds", Settings_Frame, "UICheckButtonTemplate")
    ShowKeybindsCheckbox:SetPoint("TOPLEFT", KeybindSection, "BOTTOMLEFT", 10, -5)
    ShowKeybindsCheckbox:SetSize(26, 26)
    ShowKeybindsCheckbox.text:SetText("Show Keybinds")
    ShowKeybindsCheckbox.text:SetTextColor(1, 1, 1)
    ShowKeybindsCheckbox:SetChecked(AssKeyShowKeybinds or true)

    ShowKeybindsCheckbox:SetScript("OnClick", function(self)
        AssKeyShowKeybinds = self:GetChecked()
        ScheduleKeybindUpdate()
    end)

    -- Keybind Font Size
    local FontSizeSection = Settings_Frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    FontSizeSection:SetPoint("TOPLEFT", ShowKeybindsCheckbox, "BOTTOMLEFT", 0, -15)
    FontSizeSection:SetText("Keybind Font Size:")

    local FontSizeSlider = CreateFrame("Slider", "AssKeyFontSize", Settings_Frame, "UISliderTemplate")
    FontSizeSlider:SetSize(200, 20)
    FontSizeSlider:SetPoint("TOPLEFT", FontSizeSection, "BOTTOMLEFT", 0, -5)
    FontSizeSlider:SetMinMaxValues(8, 20)
    FontSizeSlider:SetValueStep(1)
    FontSizeSlider:SetObeyStepOnDrag(true)
    FontSizeSlider:SetValue(AssKeyFontSize or 12)

    local FontSizeText = FontSizeSlider:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    FontSizeText:SetPoint("TOP", FontSizeSlider, "BOTTOM", 0, -2)

    FontSizeSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value)
        AssKeyFontSize = value
        FontSizeText:SetText(string.format("%d px", value))
        
        -- Update all keybind texts
        for frame, text in pairs(KeybindTexts) do
            if text then
                local fontPath, _, fontFlags = text:GetFont()
                text:SetFont(fontPath, value, fontFlags)
            end
        end
    end)

    local function Update_Slider_Display(Value)
        Percent_Text:SetText(string.format("%d%%", math.floor(Value * 100 + 0.5)))
        FontSizeText:SetText(string.format("%d px", AssKeyFontSize or 12))
    end

    Slider:SetScript("OnValueChanged", function(Self, Value)
        Value = Clamp(math.floor(Value * 100 + 0.5) / 100, 0, 1)
        Alpha = Value
        AssKeyAlpha = Value
        
        -- Update arrow textures
        Reapply_All()
        
        -- Update keybind text alpha
        for _, text in pairs(KeybindTexts) do
            if text then
                text:SetAlpha(Value)
            end
        end
        
        Update_Slider_Display(Value)
    end)

    Settings_Frame:SetScript("OnShow", function()
        Validate_Alpha()
        Slider:SetValue(Alpha)
        FontSizeSlider:SetValue(AssKeyFontSize or 12)
        ShowKeybindsCheckbox:SetChecked(AssKeyShowKeybinds ~= false) -- Default to true
        Update_Slider_Display(Alpha)
    end)

    Settings_Category = Settings.RegisterCanvasLayoutCategory(Settings_Frame, "Enhanced Single-Button Assistant")
    Settings.RegisterAddOnCategory(Settings_Category)
end

SLASH_ASSKEY1 = "/asskey"
SlashCmdList["ASSKEY"] = function()
    Settings.OpenToCategory(Settings_Category:GetID())
end

-- ---------------------------------------------------------------------
-- INITIALIZATION
-- ---------------------------------------------------------------------
-- Trigger initial scan
C_Timer.After(1, function()
    Validate_Alpha()
    Scan_And_Hook()
    ScheduleKeybindUpdate()
end)