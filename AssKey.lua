-- AssKey - Shows keybinds for Single Button Assistant recommendations
-- Attaches directly to the SBA button

-- Initialize saved variables
AssKeyDB = AssKeyDB or {
	enabled = true,
	fontSize = 24,
	offsetX = 0,
	offsetY = 0,
}

-- Create the keybind display frame
local AssKey = CreateFrame("Frame", "AssKeyMainFrame", UIParent, "BackdropTemplate")
AssKey:SetSize(200, 100)
AssKey:SetAlpha(1.0)
AssKey:Hide()

-- Add a bright background so we can SEE the frame
AssKey:SetBackdrop({
	bgFile = "Interface/Tooltips/UI-Tooltip-Background",
	edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
	edgeSize = 16,
	insets = { left = 4, right = 4, top = 4, bottom = 4 }
})
AssKey:SetBackdropColor(1, 0, 0, 0.9)     -- BRIGHT RED BACKGROUND
AssKey:SetBackdropBorderColor(1, 1, 0, 1) -- YELLOW BORDER

-- Keybind text - HUGE
AssKey.keybind = AssKey:CreateFontString(nil, "OVERLAY")
AssKey.keybind:SetFont("Fonts\\FRIZQT__.TTF", 72, "THICKOUTLINE") -- GIANT TEXT
AssKey.keybind:SetPoint("CENTER", 0, 0)
AssKey.keybind:SetTextColor(1, 1, 1)                              -- WHITE
AssKey.keybind:SetShadowOffset(0, 0)                              -- No shadow
AssKey.keybind:SetAlpha(1.0)
AssKey.keybind:SetDrawLayer("OVERLAY", 7)

-- Store the SBA overlay button
local SBA_Overlay_Button = nil

-- Function to find which button has the SBA overlay active
local function Find_SBA_Overlay_Button()
	-- Look for a button with active SpellActivationAlert or children with overlay textures
	local Frame = EnumerateFrames()
	while Frame do
		if Frame.UpdateAssistedCombatRotationFrame then
			-- Check if this button has active SBA children
			for _, child in ipairs({ Frame:GetChildren() }) do
				if child.ActiveFrame or child.InactiveTexture then
					-- This button has SBA overlay components
					if child:IsShown() or (child.ActiveFrame and child.ActiveFrame:IsShown()) then
						return Frame
					end
				end
			end
		end
		Frame = EnumerateFrames(Frame)
	end
	return nil
end

-- Get keybind for a spell (works with direct spells and macros)
function AssKey_GetKeybindForSpell(spellID)
	for slot = 1, 120 do
		local actionType, id = GetActionInfo(slot)

		-- Check if this slot has our spell (either direct or in a macro)
		if (actionType == "spell" or actionType == "macro") and id == spellID then
			local bindingKey

			-- Map slot numbers to action bar bindings
			if slot <= 12 then
				-- Main action bar (bottom bar)
				bindingKey = GetBindingKey("ACTIONBUTTON" .. slot)
			elseif slot <= 24 then
				-- Bottom right bar
				bindingKey = GetBindingKey("MULTIACTIONBAR3BUTTON" .. (slot - 12))
			elseif slot <= 36 then
				-- Bottom left bar
				bindingKey = GetBindingKey("MULTIACTIONBAR4BUTTON" .. (slot - 24))
			elseif slot <= 48 then
				-- Right bar 1
				bindingKey = GetBindingKey("MULTIACTIONBAR1BUTTON" .. (slot - 36))
			elseif slot <= 60 then
				-- Right bar 2
				bindingKey = GetBindingKey("MULTIACTIONBAR2BUTTON" .. (slot - 48))
			elseif slot <= 72 then
				-- Bar 6 (varies by class/spec)
				bindingKey = GetBindingKey("MULTIACTIONBAR5BUTTON" .. (slot - 60))
			elseif slot <= 84 then
				-- Bar 7
				bindingKey = GetBindingKey("MULTIACTIONBAR6BUTTON" .. (slot - 72))
			elseif slot <= 96 then
				-- Bar 8
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
function AssKey_GetCurrentRecommendedSpell()
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
	if not AssKeyDB.enabled then
		self:Hide()
		return
	end

	-- Find the button with SBA overlay
	SBA_Overlay_Button = Find_SBA_Overlay_Button()

	if not SBA_Overlay_Button then
		self:Hide()
		return
	end

	-- Attach to the SBA overlay button
	self:ClearAllPoints()
	self:SetPoint("CENTER", SBA_Overlay_Button, "CENTER", AssKeyDB.offsetX, AssKeyDB.offsetY)

	-- Get the recommended spell and find its keybind
	local spellID = AssKey_GetCurrentRecommendedSpell()
	if spellID and spellID > 0 then
		local keybind = AssKey_GetKeybindForSpell(spellID)

		if keybind and keybind ~= "" then
			self.keybind:SetText(keybind)
			self:Show()
		else
			self:Hide()
		end
	else
		self:Hide()
	end
end

-- Update loop
local ticker = C_Timer.NewTicker(0.1, function()
	AssKey:Update()
end)

-- Initial setup
AssKey:SetParent(UIParent)
AssKey:SetFrameStrata("TOOLTIP")
AssKey:SetFrameLevel(9999)

-- Event handling for when SBA button might appear/change
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
eventFrame:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
eventFrame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
eventFrame:RegisterEvent("UPDATE_BINDINGS")

eventFrame:SetScript("OnEvent", function(self, event)
	C_Timer.After(0.5, function()
		AssKey:Update()
	end)
end)

-- Slash commands
SLASH_ASSKEY1 = "/asskey"
SLASH_ASSKEY2 = "/ak"
SlashCmdList["ASSKEY"] = function(msg)
	msg = msg:lower():trim()

	if msg == "toggle" or msg == "" then
		AssKeyDB.enabled = not AssKeyDB.enabled
		if AssKeyDB.enabled then
			print("AssKey: Enabled")
			AssKey:Update()
		else
			print("AssKey: Disabled")
			AssKey:Hide()
		end
	elseif msg == "on" then
		AssKeyDB.enabled = true
		print("AssKey: Enabled")
		AssKey:Update()
	elseif msg == "off" then
		AssKeyDB.enabled = false
		print("AssKey: Disabled")
		AssKey:Hide()
	elseif msg:match("^size%s+(%d+)") then
		local size = tonumber(msg:match("^size%s+(%d+)"))
		if size and size >= 8 and size <= 72 then
			AssKeyDB.fontSize = size
			AssKey.keybind:SetFont(AssKey.keybind:GetFont(), size, "OUTLINE")
			print("AssKey: Font size set to", size)
			AssKey:Update()
		else
			print("AssKey: Invalid size. Use 8-72")
		end
	elseif msg:match("^offset%s+([-%d]+)%s+([-%d]+)") then
		local x, y = msg:match("^offset%s+([-%d]+)%s+([-%d]+)")
		AssKeyDB.offsetX = tonumber(x) or 0
		AssKeyDB.offsetY = tonumber(y) or 0
		SBA_Button = nil -- Force reattach
		print("AssKey: Offset set to", AssKeyDB.offsetX, AssKeyDB.offsetY)
		AssKey:Update()
	else
		print("AssKey commands:")
		print("  /ak - Toggle on/off")
		print("  /ak on|off - Enable/disable")
		print("  /ak size <8-72> - Set font size")
		print("  /ak offset <x> <y> - Adjust position")
	end
end

-- Initial load
print("AssKey loaded! Use /ak for commands")
