--[[
	L'ura — quick /say buttons for raid marker callouts.
	Raid pulls are in combat: ChatEdit_SendText / prefilled chat will not submit. Clicks use SecureActionButton + /s macro.
]]

local ADDON_NAME = ...

BINDING_HEADER_LURA = "L'ura"
_G["BINDING_NAME_CLICK LuraButton1:LeftButton"] = "L'ura: Say Circle"
_G["BINDING_NAME_CLICK LuraButton2:LeftButton"] = "L'ura: Say Diamond"
_G["BINDING_NAME_CLICK LuraButton3:LeftButton"] = "L'ura: Say T"
_G["BINDING_NAME_CLICK LuraButton4:LeftButton"] = "L'ura: Say Triangle"
_G["BINDING_NAME_CLICK LuraButton5:LeftButton"] = "L'ura: Say X"

local defaults = {
	scale = 1,
	point = "CENTER",
	x = 0,
	y = 120,
	locked = true,
	hidden = false,
}

local POINTS = {
	"TOPLEFT", "TOP", "TOPRIGHT",
	"LEFT", "CENTER", "RIGHT",
	"BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT",
}

-- raidIcon: button art only (Interface\TargetingFrame\UI-RaidTargetingIcon_*)
-- brace: literal /say suffix after a space (e.g. {star})
local SYMBOLS = {
	{ name = "Circle",   raidIcon = 2, chat = "Circle",   brace = "{circle}" },
	{ name = "Diamond",  raidIcon = 3, chat = "Diamond",  brace = "{diamond}" },
	{ name = "T",        raidIcon = 1, chat = "T",        brace = "{star}" },
	{ name = "Triangle", raidIcon = 4, chat = "Triangle", brace = "{triangle}" },
	{ name = "X",        raidIcon = 7, chat = "X",        brace = "{x}" },
}

local function BuildSayMessage(sym)
	return sym.chat .. " " .. sym.brace
end

local bar, grip, settingsCategory
local createdUI = false

local function MergeDefaults()
	LuraDB = LuraDB or {}
	for k, v in pairs(defaults) do
		if LuraDB[k] == nil then
			LuraDB[k] = v
		end
	end
end

local function PointToIndex(p)
	for i, v in ipairs(POINTS) do
		if v == p then
			return i
		end
	end
	return 5
end

local function IndexToPoint(i)
	return POINTS[i] or "CENTER"
end

local function SaveBarPosition()
	if not bar then
		return
	end
	local point, _, rel, x, y = bar:GetPoint(1)
	if point and x and y then
		LuraDB.point = point
		LuraDB.x = x
		LuraDB.y = y
	end
end

local function ApplyLayout()
	if not bar then
		return
	end
	bar:ClearAllPoints()
	bar:SetPoint(LuraDB.point, UIParent, LuraDB.point, LuraDB.x, LuraDB.y)
	bar:SetScale(math.max(0.35, math.min(LuraDB.scale or 1, 3)))

	if LuraDB.hidden then
		bar:Hide()
	else
		bar:Show()
	end

	if LuraDB.locked then
		grip:Hide()
		bar:SetMovable(false)
		grip:RegisterForDrag()
	else
		grip:Show()
		bar:SetMovable(true)
		grip:RegisterForDrag("LeftButton")
	end
end

local function CreateMainUI()
	bar = CreateFrame("Frame", "LuraBar", UIParent, "BackdropTemplate")
	bar:SetFrameStrata("MEDIUM")
	bar:SetClampedToScreen(true)
	bar:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 8,
		edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	bar:SetBackdropColor(0.05, 0.05, 0.08, 0.82)
	bar:SetBackdropBorderColor(0.4, 0.4, 0.55, 0.9)

	grip = CreateFrame("Frame", nil, bar)
	grip:SetSize(10, 64)
	grip:SetPoint("LEFT", bar, "LEFT", 4, 0)
	grip:EnableMouse(true)
	local gripTex = grip:CreateTexture(nil, "ARTWORK")
	gripTex:SetAllPoints()
	gripTex:SetColorTexture(0.25, 0.25, 0.35, 0.65)
	grip:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("L'ura")
		if LuraDB.locked then
			GameTooltip:AddLine("Unlock in Options or |cffffffff/lura unlock|r to drag.", 1, 1, 1, true)
		else
			GameTooltip:AddLine("Drag to move this bar.", 0.9, 0.9, 0.9, true)
		end
		GameTooltip:Show()
	end)
	grip:SetScript("OnLeave", GameTooltip_Hide)
	grip:SetScript("OnDragStart", function()
		if not LuraDB.locked and bar then
			bar:StartMoving()
		end
	end)
	grip:SetScript("OnDragStop", function()
		if bar then
			bar:StopMovingOrSizing()
			SaveBarPosition()
		end
	end)

	local btnW, btnH, pad = 56, 72, 4
	local gripW = 10
	local totalW = gripW + 8 + (#SYMBOLS * btnW) + ((#SYMBOLS - 1) * pad) + 8
	bar:SetSize(totalW, btnH + 16)

	local prev = grip
	for i, sym in ipairs(SYMBOLS) do
		local btn = CreateFrame("Button", "LuraButton" .. i, bar, "SecureActionButtonTemplate,BackdropTemplate")
		btn:SetSize(btnW, btnH)
		if i == 1 then
			btn:SetPoint("LEFT", grip, "RIGHT", pad, 0)
		else
			btn:SetPoint("LEFT", prev, "RIGHT", pad, 0)
		end
		prev = btn
		btn:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8X8",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = false,
			edgeSize = 6,
			insets = { left = 2, right = 2, top = 2, bottom = 2 },
		})
		btn:SetBackdropColor(0.12, 0.12, 0.16, 0.55)
		btn:SetBackdropBorderColor(0.35, 0.35, 0.45, 0.5)

		local holder = CreateFrame("Frame", nil, btn)
		holder:SetSize(36, 36)
		holder:SetPoint("TOP", btn, "TOP", 0, -6)

		local tex = holder:CreateTexture(nil, "ARTWORK")
		tex:SetAllPoints()
		tex:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. sym.raidIcon)

		local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		fs:SetPoint("BOTTOM", btn, "BOTTOM", 0, 6)
		fs:SetText(sym.name)
		fs:SetTextColor(0.95, 0.95, 1)

		btn:SetScript("OnEnter", function(self)
			self:SetBackdropBorderColor(0.65, 0.75, 1, 0.95)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(sym.name, 1, 1, 1)
			GameTooltip:AddLine("Say: |cffffffff" .. BuildSayMessage(sym) .. "|r", 0.85, 0.85, 0.85, true)
			GameTooltip:Show()
		end)
		btn:SetScript("OnLeave", function(self)
			self:SetBackdropBorderColor(0.35, 0.35, 0.45, 0.5)
			GameTooltip_Hide()
		end)
		btn:RegisterForClicks("LeftButtonUp", "LeftButtonDown")
		btn:SetAttribute("type", "macro")
		local macroLine = "/s " .. BuildSayMessage(sym)
		if #macroLine > 255 then
			print("|cffff5555L'ura:|r line too long for macro (255 max).")
		else
			btn:SetAttribute("macrotext", macroLine)
		end
		btn:SetAttribute("useOnKeyDown", true)
	end

	createdUI = true
	ApplyLayout()
end

local function ResetToDefaults()
	for k, v in pairs(defaults) do
		LuraDB[k] = v
	end
	ApplyLayout()
	print("|cffaa88ffL'ura|r: position and scale reset.")
end

local function PrintHelp()
	print("|cffaa88ffL'ura|r commands:")
	print("  |cffffffff/lura scale <0.35-3>|r — bar scale")
	print("  |cffffffff/lura x <number>|r  |cffffffff/lura y <number>|r — offset from anchor")
	print("  |cffffffff/lura anchor <TOPLEFT|CENTER|...>|r — anchor point")
	print("  |cffffffff/lura lock|r / |cffffffff/lura unlock|r")
	print("  |cffffffff/lura show|r / |cffffffff/lura hide|r")
	print("  |cffffffff/lura reset|r — default layout")
	print("  |cffffffff/lura config|r — open Options")
end

SLASH_LURA1 = "/lura"
SlashCmdList["LURA"] = function(msg)
	local cmd, rest = msg:match("^(%S*)%s*(.*)$")
	cmd = (cmd or ""):lower()
	rest = (rest or ""):gsub("^%s+", ""):gsub("%s+$", "")

	if cmd == "" or cmd == "help" then
		PrintHelp()
		return
	end

	if cmd == "config" or cmd == "options" then
		if SettingsPanel then
			Settings.OpenToCategory(settingsCategory)
		else
			print("|cffaa88ffL'ura|r: Open Esc > Options > AddOns.")
		end
		return
	end

	if cmd == "reset" then
		ResetToDefaults()
		return
	end

	if cmd == "lock" then
		LuraDB.locked = true
		ApplyLayout()
		print("|cffaa88ffL'ura|r: locked.")
		return
	end

	if cmd == "unlock" then
		LuraDB.locked = false
		ApplyLayout()
		print("|cffaa88ffL'ura|r: unlocked — drag the left grip to move.")
		return
	end

	if cmd == "show" then
		LuraDB.hidden = false
		ApplyLayout()
		return
	end

	if cmd == "hide" then
		LuraDB.hidden = true
		ApplyLayout()
		return
	end

	if cmd == "scale" then
		local n = tonumber(rest)
		if not n then
			print("|cffaa88ffL'ura|r: usage: /lura scale <number>")
			return
		end
		LuraDB.scale = math.max(0.35, math.min(n, 3))
		ApplyLayout()
		print("|cffaa88ffL'ura|r: scale = " .. LuraDB.scale)
		return
	end

	if cmd == "x" then
		local n = tonumber(rest)
		if not n then
			print("|cffaa88ffL'ura|r: usage: /lura x <number>")
			return
		end
		LuraDB.x = n
		ApplyLayout()
		return
	end

	if cmd == "y" then
		local n = tonumber(rest)
		if not n then
			print("|cffaa88ffL'ura|r: usage: /lura y <number>")
			return
		end
		LuraDB.y = n
		ApplyLayout()
		return
	end

	if cmd == "anchor" then
		local p = rest:upper()
		if p == "" then
			print("|cffaa88ffL'ura|r: usage: /lura anchor <TOPLEFT|TOP|CENTER|...>")
			return
		end
		local ok
		for _, v in ipairs(POINTS) do
			if v == p then
				ok = true
				break
			end
		end
		if not ok then
			print("|cffaa88ffL'ura|r: invalid anchor. Use TOPLEFT, TOP, CENTER, etc.")
			return
		end
		LuraDB.point = p
		ApplyLayout()
		print("|cffaa88ffL'ura|r: anchor = " .. p)
		return
	end

	PrintHelp()
end

local function RegisterOptions()
	if not Settings or not Settings.RegisterVerticalLayoutCategory then
		return
	end

	local category, layout = Settings.RegisterVerticalLayoutCategory("L'ura")
	settingsCategory = category:GetID()
	local CreateDropdown = Settings.CreateDropdown or Settings.CreateDropDown

	do
		local function GetValue()
			return not LuraDB.hidden
		end
		local function SetValue(v)
			LuraDB.hidden = not v
			ApplyLayout()
		end
		local setting = Settings.RegisterProxySetting(
			category,
			"LURA_SHOW_BAR",
			Settings.VarType.Boolean,
			"Show bar",
			true,
			GetValue,
			SetValue
		)
		Settings.CreateCheckbox(category, setting, "Show or hide the symbol bar on screen.")
	end

	do
		local function GetValue()
			return LuraDB.locked
		end
		local function SetValue(v)
			LuraDB.locked = v
			ApplyLayout()
		end
		local setting = Settings.RegisterProxySetting(
			category,
			"LURA_LOCKED",
			Settings.VarType.Boolean,
			"Lock position",
			true,
			GetValue,
			SetValue
		)
		Settings.CreateCheckbox(category, setting, "When unlocked, drag the narrow strip on the left of the bar to move it.")
	end

	do
		local def = defaults.scale
		local setting = Settings.RegisterProxySetting(
			category,
			"LURA_SCALE",
			Settings.VarType.Number,
			"Scale",
			def,
			function()
				return LuraDB.scale
			end,
			function(v)
				LuraDB.scale = v
				ApplyLayout()
			end
		)
		local options = Settings.CreateSliderOptions(0.35, 3, 0.05)
		options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
			return string.format("%.2f", value)
		end)
		Settings.CreateSlider(category, setting, options, "Overall size of the bar.")
	end

	do
		local function GetAnchorOptions()
			local container = Settings.CreateControlTextContainer()
			for i, name in ipairs(POINTS) do
				container:Add(i, name)
			end
			return container:GetData()
		end
		local setting = Settings.RegisterProxySetting(
			category,
			"LURA_ANCHOR",
			Settings.VarType.Number,
			"Anchor point",
			PointToIndex(defaults.point),
			function()
				return PointToIndex(LuraDB.point)
			end,
			function(v)
				LuraDB.point = IndexToPoint(v)
				ApplyLayout()
			end
		)
		CreateDropdown(category, setting, GetAnchorOptions, "Which point of the bar is pinned to the screen.")
	end

	do
		local setting = Settings.RegisterProxySetting(
			category,
			"LURA_OFFX",
			Settings.VarType.Number,
			"Horizontal offset",
			defaults.x,
			function()
				return LuraDB.x
			end,
			function(v)
				LuraDB.x = v
				ApplyLayout()
			end
		)
		local options = Settings.CreateSliderOptions(-1200, 1200, 1)
		options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
			return tostring(math.floor(value + 0.5))
		end)
		Settings.CreateSlider(category, setting, options, "Pixels from anchor (after scale).")
	end

	do
		local setting = Settings.RegisterProxySetting(
			category,
			"LURA_OFFY",
			Settings.VarType.Number,
			"Vertical offset",
			defaults.y,
			function()
				return LuraDB.y
			end,
			function(v)
				LuraDB.y = v
				ApplyLayout()
			end
		)
		local options = Settings.CreateSliderOptions(-1200, 1200, 1)
		options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
			return tostring(math.floor(value + 0.5))
		end)
		Settings.CreateSlider(category, setting, options, "Pixels from anchor (after scale).")
	end

	local resetInit = CreateSettingsButtonInitializer(
		"Reset layout",
		"Reset layout",
		function()
			ResetToDefaults()
		end,
		"Restore default scale, anchor, and offsets.\n\nSlash: |cffaaaaaa/lura help|r, |cffaaaaaa/lura reset|r, |cffaaaaaa/lura config|r.",
		true
	)
	local settingsLayout = layout or (SettingsPanel and SettingsPanel.GetLayout and SettingsPanel:GetLayout(category))
	if settingsLayout and settingsLayout.AddInitializer then
		settingsLayout:AddInitializer(resetInit)
	end

	Settings.RegisterAddOnCategory(category)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(_, event, name)
	if name ~= ADDON_NAME then
		return
	end
	MergeDefaults()
	if not createdUI then
		CreateMainUI()
	end
	if Settings and Settings.RegisterVerticalLayoutCategory and not settingsCategory then
		RegisterOptions()
	end
end)
