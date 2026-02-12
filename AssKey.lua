local AssKey = CreateFrame("Frame", "AssKeyMainFrame", UIParent, "BackdropTemplate")
AssKey:SetSize(100, 40)
AssKey:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
AssKey:SetBackdrop({
	bgFile = "Interface/Tooltips/UI-Tooltip-Background",
	edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
	edgeSize = 16,
	insets = { left = 4, right = 4, top = 4, bottom = 4 }
})
AssKey:SetBackdropColor(0, 0, 0, 0.8)
AssKey:SetBackdropBorderColor(1, 1, 1, 0.5)
AssKey:EnableMouse(true)
AssKey:SetMovable(true)
AssKey:RegisterForDrag("LeftButton")
AssKey:SetScript("OnDragStart", AssKey.StartMoving)
AssKey:SetScript("OnDragStop", AssKey.StopMovingOrSizing)

-- Spell icon
AssKey.icon = AssKey:CreateTexture(nil, "ARTWORK")
AssKey.icon:SetSize(36, 36)
AssKey.icon:SetPoint("LEFT", 2, 0)
AssKey.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

-- Spell name
AssKey.name = AssKey:CreateFontString(nil, "OVERLAY", "GameFontNormal")
AssKey.name:SetPoint("LEFT", AssKey.icon, "RIGHT", 5, 0)
AssKey.name:SetPoint("RIGHT", AssKey, "RIGHT", -5, 0)
AssKey.name:SetJustifyH("LEFT")

-- Keybind text
AssKey.keybind = AssKey:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
AssKey.keybind:SetPoint("TOPLEFT", AssKey, "TOPRIGHT", 5, 0)
AssKey.keybind:SetTextColor(1, 0.8, 0)

function AssKey:Update()
	local spellID = AssKey_GetCurrentRecommendedSpell()
	if spellID and spellID > 0 then
		local spellInfo = C_Spell.GetSpellInfo(spellID)
		local name = spellInfo and spellInfo.name or "Unknown"
		local texture = C_Spell.GetSpellTexture(spellID)
		local keybind = AssKey_GetKeybindForSpell(spellID)

		self.icon:SetTexture(texture)
		self.name:SetText(name or "Unknown")
		self.keybind:SetText(keybind ~= "" and "[" .. keybind .. "]" or "")
		self:Show()
	else
		self:Hide()
	end
end

-- Update via ticker
local ticker = C_Timer.NewTicker(0.2, function()
	AssKey:Update()
end)

-- Slash command to toggle/show
SLASH_ASSKEY1 = "/asskey"
SLASH_ASSKEY2 = "/ak"
SlashCmdList["ASSKEY"] = function()
	if AssKey:IsShown() then
		AssKey:Hide()
	else
		AssKey:Show()
	end
end

-- Add your existing helper functions here (GetKeybindForSpell, GetCurrentRecommendedSpell, etc)

function AssKey_GetKeybindForSpell(spellID)
	for slot = 1, 120 do
		local actionType, id = GetActionInfo(slot)

		-- Direct spell on bar OR macro that casts this spell
		if (actionType == "spell" or actionType == "macro") and id == spellID then
			local bindingKey
			if slot <= 12 then
				bindingKey = GetBindingKey("ACTIONBUTTON" .. slot)
			elseif slot <= 24 then
				bindingKey = GetBindingKey("MULTIACTIONBAR3BUTTON" .. (slot - 12))
			elseif slot <= 36 then
				bindingKey = GetBindingKey("MULTIACTIONBAR4BUTTON" .. (slot - 24))
				-- add more bars as needed
			end

			if bindingKey then
				return GetBindingText(bindingKey)
			end
		end
	end
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
	-- if C_AssistedCombat.GetRotationSpells then
	-- 	local spells = C_AssistedCombat.GetRotationSpells()
	-- 	if spells and #spells > 0 then
	-- 		return spells[1] -- First spell is current recommendation
	-- 	end
	-- end

	return nil
end
