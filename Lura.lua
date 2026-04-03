--[[
	L'ura — quick /raid buttons for raid marker callouts.
	Raid pulls are in combat: ChatEdit_SendText / prefilled chat will not submit. Clicks use SecureActionButton + macro.
	Macros always use /raid only so SetAttribute("macrotext") never swaps chat mode on roster changes (combat blocks SetAttribute; party↔raid would desync).
	Order sync uses addon messages on leader/assist PreClick (PARTY or RAID by group type). Not CHAT_MSG_RAID — self-echo is unreliable.
	Order strip is a separate frame (icons, own grip/position). /lura show|hide|toggle controls both; leader bar only shows if solo or raid/party lead or assist.
	Queue clears 30s after the last icon, or when you leave the group.
]]

local ADDON_NAME = ...

BINDING_HEADER_LURA = "L'ura"
_G["BINDING_NAME_CLICK LuraButton1:LeftButton"] = "L'ura: Raid Circle"
_G["BINDING_NAME_CLICK LuraButton2:LeftButton"] = "L'ura: Raid Diamond"
_G["BINDING_NAME_CLICK LuraButton3:LeftButton"] = "L'ura: Raid T"
_G["BINDING_NAME_CLICK LuraButton4:LeftButton"] = "L'ura: Raid Triangle"
_G["BINDING_NAME_CLICK LuraButton5:LeftButton"] = "L'ura: Raid X"

local defaults = {
	scale = 1,
	point = "CENTER",
	x = 0,
	y = 120,
	locked = true,
	hidden = false, -- both frames: user wants UI on (leader bar also needs solo or lead/assist in a group)
	orderPoint = "CENTER",
	orderX = 0,
	orderY = 60,
}

local POINTS = {
	"TOPLEFT", "TOP", "TOPRIGHT",
	"LEFT", "CENTER", "RIGHT",
	"BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT",
}

-- raidIcon: wire protocol + chat still uses Blizzard raid markers ({circle}, etc.)
-- iconFile: 48x48 art under lura/Icons (SetTexture only; macros unchanged)
local LURA_ICON_DIR = "Interface\\AddOns\\lura\\Icons\\"
local SYMBOLS = {
	{ name = "Circle",   raidIcon = 2, iconFile = "rune_circle.png",   chat = "Circle",   brace = "{circle}" },
	{ name = "Diamond",  raidIcon = 3, iconFile = "rune_diamond.png",  chat = "Diamond",  brace = "{diamond}" },
	{ name = "T",        raidIcon = 1, iconFile = "rune_t.png",        chat = "T",        brace = "{star}" },
	{ name = "Triangle", raidIcon = 4, iconFile = "rune_triangle.png", chat = "Triangle", brace = "{triangle}" },
	{ name = "X",        raidIcon = 7, iconFile = "rune_cross.png",    chat = "X",        brace = "{x}" },
}

local function SymbolTexturePath(sym)
	return LURA_ICON_DIR .. sym.iconFile
end

local function TexturePathForRaidIcon(raidIconIdx)
	for _, s in ipairs(SYMBOLS) do
		if s.raidIcon == raidIconIdx then
			return SymbolTexturePath(s)
		end
	end
	return "Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. tostring(raidIconIdx)
end

local function BuildSayMessage(sym)
	return sym.chat .. " " .. sym.brace
end

local bar, grip, orderGrip, settingsCategory
local createdUI = false
local luraButtons = {}

-- Raid order sync (addon channel): only raid leader/assist broadcasts; everyone shows icons only.
local ORDER_PREFIX = "LuraOrder"
local ORDER_IDLE_SEC = 30
local ORDER_QUEUE_CAP = 40
local orderBar
local orderIconPool = {}
local orderQueue = {} -- raid texture indices (e.g. 2 = circle), same as sym.raidIcon
local orderExpireTimer
local lastOrderSeqFrom = {} -- [normalizedSender] = last seq accepted
local broadcastSeq = 0 -- this client when lead/assist sends

local function NormalizeSenderKey(name)
	if not name or name == "" then
		return ""
	end
	return Ambiguate(name, "none")
end

local function PlayerSenderKey()
	local full = GetUnitName("player", true)
	if full and full ~= "" then
		return NormalizeSenderKey(full)
	end
	return NormalizeSenderKey(UnitName("player"))
end

local function CancelOrderExpire()
	if orderExpireTimer then
		orderExpireTimer:Cancel()
		orderExpireTimer = nil
	end
end

local function ScheduleOrderExpire()
	CancelOrderExpire()
	orderExpireTimer = C_Timer.NewTimer(ORDER_IDLE_SEC, function()
		orderExpireTimer = nil
		wipe(orderQueue)
		wipe(lastOrderSeqFrom)
		RefreshOrderQueueUI()
	end)
end

local function RaidIconIsOurs(raidIconIdx)
	for _, sym in ipairs(SYMBOLS) do
		if sym.raidIcon == raidIconIdx then
			return true
		end
	end
	return false
end

local function RefreshOrderQueueUI()
	if not orderBar then
		return
	end
	local size, pad = 32, 4
	local gripW = 8
	local innerPad = 4
	local n = #orderQueue

	if LuraDB and LuraDB.hidden then
		for i = 1, #orderIconPool do
			orderIconPool[i]:Hide()
		end
		orderBar:Hide()
		return
	end

	-- While unlocked and empty, show dimmed symbols so the strip is easy to grab and move.
	local showPlaceholders = (n == 0 and LuraDB and not LuraDB.locked)
	if n == 0 and not showPlaceholders then
		for i = 1, #orderIconPool do
			orderIconPool[i]:Hide()
		end
		orderBar:Hide()
		return
	end

	orderBar:Show()
	local count = showPlaceholders and #SYMBOLS or n
	local totalW = gripW + innerPad + count * size + (count - 1) * pad + 8
	orderBar:SetSize(math.max(totalW, 24), size + 8)
	local x = 4 + gripW + innerPad
	for i = 1, count do
		local f = orderIconPool[i]
		if not f then
			f = CreateFrame("Frame", nil, orderBar)
			f:SetSize(size, size)
			local t = f:CreateTexture(nil, "ARTWORK")
			t:SetAllPoints()
			f._tex = t
			orderIconPool[i] = f
		end
		local texPath = showPlaceholders and SymbolTexturePath(SYMBOLS[i]) or TexturePathForRaidIcon(orderQueue[i])
		f._tex:SetTexture(texPath)
		if showPlaceholders then
			f._tex:SetVertexColor(0.42, 0.45, 0.55)
			f:SetAlpha(0.42)
		else
			f._tex:SetVertexColor(1, 1, 1)
			f:SetAlpha(1)
		end
		f:ClearAllPoints()
		f:SetPoint("LEFT", orderBar, "LEFT", x, 0)
		f:Show()
		x = x + size + pad
	end
	for j = count + 1, #orderIconPool do
		orderIconPool[j]:Hide()
	end
end

local function AppendOrderIcon(raidIconIdx)
	if not RaidIconIsOurs(raidIconIdx) then
		return
	end
	table.insert(orderQueue, raidIconIdx)
	while #orderQueue > ORDER_QUEUE_CAP do
		table.remove(orderQueue, 1)
	end
	RefreshOrderQueueUI()
	ScheduleOrderExpire()
end

local function ClearOrderSyncState()
	CancelOrderExpire()
	wipe(orderQueue)
	wipe(lastOrderSeqFrom)
	broadcastSeq = 0
	RefreshOrderQueueUI()
end

local function FindGroupUnitForSender(sender)
	if not sender or sender == "" or not IsInGroup() then
		return nil
	end
	local want = NormalizeSenderKey(sender)
	if want == PlayerSenderKey() then
		return "player"
	end
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do
			local u = "raid" .. i
			if UnitExists(u) then
				local full = GetUnitName(u, true)
				if full and NormalizeSenderKey(full) == want then
					return u
				end
			end
		end
	else
		for _, u in ipairs({ "party1", "party2", "party3", "party4" }) do
			if UnitExists(u) then
				local full = GetUnitName(u, true)
				if full and NormalizeSenderKey(full) == want then
					return u
				end
			end
		end
	end
	return nil
end

local function UnitMayBroadcastOrder(unit)
	return unit and (UnitIsGroupLeader(unit) or UnitIsGroupAssistant(unit))
end

-- Party has no assistants; raid allows leader or promoted assist.
local function PlayerMayBroadcastOrderAddon()
	if not IsInGroup() then
		return false
	end
	if IsInRaid() then
		return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
	end
	return UnitIsGroupLeader("player")
end

local function OrderAddonDistribution()
	if IsInRaid() then
		return "RAID"
	end
	if IsInGroup() then
		return "PARTY"
	end
	return nil
end

-- Do not rely on CHAT_MSG_RAID for our own /raid line: retail often omits or alters self-chat events.
-- PreClick runs once per click phase; RegisterForClicks had both Up+Down and doubled broadcasts — debounce same icon.
local lastOrderPreclickByIcon = {}
local ORDER_PRECLICK_DEBOUNCE = 0.22

local function BroadcastOrderFromLeaderClick(sym)
	if not sym or not PlayerMayBroadcastOrderAddon() then
		return
	end
	local dist = OrderAddonDistribution()
	if not dist then
		return
	end
	local now = GetTime()
	local iconIdx = sym.raidIcon
	local prev = lastOrderPreclickByIcon[iconIdx]
	if prev and (now - prev) < ORDER_PRECLICK_DEBOUNCE then
		return
	end
	lastOrderPreclickByIcon[iconIdx] = now
	broadcastSeq = broadcastSeq + 1
	local payload = "a:" .. tostring(broadcastSeq) .. ":" .. tostring(iconIdx)
	pcall(function()
		C_ChatInfo.SendAddonMessage(ORDER_PREFIX, payload, dist)
	end)
	AppendOrderIcon(iconIdx)
end

local function OnAddonOrderMessage(sender, msg)
	if not IsInGroup() or not sender or sender == "" then
		return
	end
	if NormalizeSenderKey(sender) == PlayerSenderKey() then
		return
	end
	local unit = FindGroupUnitForSender(sender)
	if not UnitMayBroadcastOrder(unit) then
		return
	end
	local seq, icon = strmatch(msg, "^a:(%d+):(%d+)$")
	seq = tonumber(seq)
	icon = tonumber(icon)
	if not seq or not icon or not RaidIconIsOurs(icon) then
		return
	end
	local key = NormalizeSenderKey(sender)
	local prev = lastOrderSeqFrom[key]
	if prev and seq <= prev then
		return
	end
	lastOrderSeqFrom[key] = seq
	AppendOrderIcon(icon)
end

-- Always /raid: changing macrotext when party↔raid would require SetAttribute during combat (blocked) or stale macros.
local RAID_MACRO_PREFIX = "/raid "

local function TooltipChannelLabel()
	return "Raid"
end

local function RefreshLuraButtonMacros()
	-- SecureActionButtonTemplate: SetAttribute is blocked during combat lockdown.
	if InCombatLockdown() then
		return
	end
	if not luraButtons[1] then
		return
	end
	for i, sym in ipairs(SYMBOLS) do
		local btn = luraButtons[i]
		if btn then
			local macroLine = RAID_MACRO_PREFIX .. BuildSayMessage(sym)
			if #macroLine > 255 then
				print("|cffff5555L'ura:|r line too long for macro (255 max).")
			else
				btn:SetAttribute("macrotext", macroLine)
			end
		end
	end
end

local function LeaderBarRoleAllowsShow()
	if not IsInGroup() then
		return true
	end
	return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
end

local function MergeDefaults()
	LuraDB = LuraDB or {}
	for k, v in pairs(defaults) do
		if LuraDB[k] == nil then
			LuraDB[k] = v
		end
	end
	LuraDB.orderStripHidden = nil
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

-- Chat slash + some Settings callbacks run in a protected path: defer layout to next frame.
-- Combat lockdown also blocks ClearAllPoints/SetPoint — flush on PLAYER_REGEN_ENABLED.
local luraLayoutPending = false
local luraApplyAfterScheduled = false

local function SaveLeaderBarPosition()
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

local function SaveFollowerBarPosition()
	if not orderBar then
		return
	end
	local point, _, rel, x, y = orderBar:GetPoint(1)
	if point and x and y then
		LuraDB.orderPoint = point
		LuraDB.orderX = x
		LuraDB.orderY = y
	end
end

local function ApplyLayout()
	if not bar then
		return
	end
	if InCombatLockdown() then
		luraLayoutPending = true
		return
	end
	luraLayoutPending = false
	local sc = math.max(0.35, math.min(LuraDB.scale or 1, 3))

	bar:ClearAllPoints()
	bar:SetPoint(LuraDB.point, UIParent, LuraDB.point, LuraDB.x, LuraDB.y)
	bar:SetScale(sc)

	local leaderShown = not LuraDB.hidden and LeaderBarRoleAllowsShow()
	if leaderShown then
		bar:Show()
	else
		bar:Hide()
	end

	if LuraDB.locked or not leaderShown then
		grip:Hide()
		bar:SetMovable(false)
		grip:RegisterForDrag()
	else
		grip:Show()
		bar:SetMovable(true)
		grip:RegisterForDrag("LeftButton")
	end

	if orderBar then
		orderBar:ClearAllPoints()
		orderBar:SetPoint(LuraDB.orderPoint or defaults.orderPoint, UIParent, LuraDB.orderPoint or defaults.orderPoint, LuraDB.orderX or 0, LuraDB.orderY or 60)
		orderBar:SetScale(sc)

		if orderGrip then
			if LuraDB.locked then
				orderGrip:Hide()
				orderBar:SetMovable(false)
				orderGrip:RegisterForDrag()
			else
				orderGrip:Show()
				orderBar:SetMovable(true)
				orderGrip:RegisterForDrag("LeftButton")
			end
		end
		RefreshOrderQueueUI()
	end
end

local function RequestApplyLayout()
	if luraApplyAfterScheduled then
		return
	end
	luraApplyAfterScheduled = true
	C_Timer.After(0, function()
		luraApplyAfterScheduled = false
		ApplyLayout()
	end)
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
		GameTooltip:AddLine("L'ura — leader bar", 1, 1, 1)
		if LuraDB.locked then
			GameTooltip:AddLine("Unlock in Options or |cffffffff/lura unlock|r to drag.", 1, 1, 1, true)
		else
			GameTooltip:AddLine("Drag to move the symbol bar (separate from the order strip).", 0.9, 0.9, 0.9, true)
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
			SaveLeaderBarPosition()
		end
	end)

	local btnW, btnH, pad = 56, 72, 4
	local gripW = 10
	local totalW = gripW + 8 + (#SYMBOLS * btnW) + ((#SYMBOLS - 1) * pad) + 8
	bar:SetSize(totalW, btnH + 16)

	-- Follower strip: display-only Frames (no SecureActionButton). Only the leader bar needs secure buttons for /raid in combat.
	orderBar = CreateFrame("Frame", "LuraOrderQueue", UIParent, "BackdropTemplate")
	orderBar:SetFrameStrata("MEDIUM")
	orderBar:SetClampedToScreen(true)
	orderBar:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 8,
		edgeSize = 8,
		insets = { left = 2, right = 2, top = 2, bottom = 2 },
	})
	orderBar:SetBackdropColor(0.06, 0.06, 0.1, 0.75)
	orderBar:SetBackdropBorderColor(0.35, 0.35, 0.5, 0.65)
	orderBar:Hide()

	orderGrip = CreateFrame("Frame", nil, orderBar)
	orderGrip:SetSize(8, 40)
	orderGrip:SetPoint("LEFT", orderBar, "LEFT", 2, 0)
	orderGrip:EnableMouse(true)
	local ogTex = orderGrip:CreateTexture(nil, "ARTWORK")
	ogTex:SetAllPoints()
	ogTex:SetColorTexture(0.2, 0.22, 0.32, 0.7)
	orderGrip:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("L'ura — raid order", 1, 1, 1)
		if LuraDB.locked then
			GameTooltip:AddLine("Unlock the bar (|cffffffff/lura unlock|r) to drag this strip.", 0.85, 0.85, 0.85, true)
		else
			GameTooltip:AddLine("Drag to move the order strip (separate from the leader bar).", 0.85, 0.85, 0.85, true)
			GameTooltip:AddLine("While the queue is empty, dim icons are placeholders so you can position the strip.", 0.65, 0.72, 0.78, true)
		end
		GameTooltip:Show()
	end)
	orderGrip:SetScript("OnLeave", GameTooltip_Hide)
	orderGrip:SetScript("OnDragStart", function()
		if not LuraDB.locked and orderBar then
			orderBar:StartMoving()
		end
	end)
	orderGrip:SetScript("OnDragStop", function()
		if orderBar then
			orderBar:StopMovingOrSizing()
			SaveFollowerBarPosition()
		end
	end)

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
		tex:SetTexture(SymbolTexturePath(sym))

		local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		fs:SetPoint("BOTTOM", btn, "BOTTOM", 0, 6)
		fs:SetText(sym.name)
		fs:SetTextColor(0.95, 0.95, 1)

		btn:SetScript("OnEnter", function(self)
			self:SetBackdropBorderColor(0.65, 0.75, 1, 0.95)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(sym.name, 1, 1, 1)
			GameTooltip:AddLine(TooltipChannelLabel() .. ": |cffffffff" .. BuildSayMessage(sym) .. "|r", 0.85, 0.85, 0.85, true)
			GameTooltip:Show()
		end)
		btn:SetScript("OnLeave", function(self)
			self:SetBackdropBorderColor(0.35, 0.35, 0.45, 0.5)
			GameTooltip_Hide()
		end)
		-- Up only: both Up+Down invoke PreClick twice per mouse press (double icons on the order strip).
		btn:RegisterForClicks("LeftButtonUp")
		btn:SetAttribute("type", "macro")
		btn:SetAttribute("useOnKeyDown", false)
		btn:SetScript("PreClick", function()
			BroadcastOrderFromLeaderClick(sym)
		end)
		luraButtons[i] = btn
	end

	RefreshLuraButtonMacros()

	createdUI = true
	ApplyLayout()
end

local function ResetToDefaults()
	for k, v in pairs(defaults) do
		LuraDB[k] = v
	end
	RequestApplyLayout()
	print("|cffaa88ffL'ura|r: position and scale reset.")
end

local function PrintHelp()
	print("|cffaa88ffL'ura|r commands:")
	print("  |cffffffff/lura scale <0.35-3>|r — bar scale")
	print("  |cffffffff/lura x <number>|r  |cffffffff/lura y <number>|r — offset from anchor")
	print("  |cffffffff/lura anchor <TOPLEFT|CENTER|...>|r — anchor point")
	print("  |cffffffff/lura lock|r / |cffffffff/lura unlock|r")
	print("  |cffffffff/lura|r (no args) — toggle UI on/off (same as |cfffffffftoggle|r)")
	print("  |cffffffff/lura show|r / |cffffffff/lura on|r / |cffffffff/lura hide|r / |cffffffff/lura off|r — set UI shown or hidden")
	print("  |cffffffff/lura reset|r — default layout")
	print("  |cffffffff/lura config|r — open Options")
	print("  |cffffffffSync:|r lead/assist clicks broadcast the order strip (addon: PARTY or RAID; 30s idle clear). Macros stay /raid.")
end

SLASH_LURA1 = "/lura"
SlashCmdList["LURA"] = function(msg)
	local cmd, rest = msg:match("^(%S*)%s*(.*)$")
	cmd = (cmd or ""):lower()
	rest = (rest or ""):gsub("^%s+", ""):gsub("%s+$", "")

	if cmd == "help" or cmd == "?" then
		PrintHelp()
		return
	end

	if cmd == "" or cmd == "toggle" then
		LuraDB.hidden = not LuraDB.hidden
		RequestApplyLayout()
		print(
			"|cffaa88ffL'ura|r:",
			LuraDB.hidden and "Hidden (order strip + leader intent)." or "Shown — order strip when active; leader bar only if solo or lead/assist."
		)
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
		RequestApplyLayout()
		print("|cffaa88ffL'ura|r: locked.")
		return
	end

	if cmd == "unlock" then
		LuraDB.locked = false
		RequestApplyLayout()
		print("|cffaa88ffL'ura|r: unlocked — drag the left grip to move.")
		return
	end

	if cmd == "show" or cmd == "on" then
		LuraDB.hidden = false
		RequestApplyLayout()
		print("|cffaa88ffL'ura|r: UI on — order strip when active; leader bar if solo or lead/assist.")
		return
	end

	if cmd == "hide" or cmd == "off" then
		LuraDB.hidden = true
		RequestApplyLayout()
		print("|cffaa88ffL'ura|r: UI hidden (order strip + leader).")
		return
	end

	if cmd == "scale" then
		local n = tonumber(rest)
		if not n then
			print("|cffaa88ffL'ura|r: usage: /lura scale <number>")
			return
		end
		LuraDB.scale = math.max(0.35, math.min(n, 3))
		RequestApplyLayout()
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
		RequestApplyLayout()
		return
	end

	if cmd == "y" then
		local n = tonumber(rest)
		if not n then
			print("|cffaa88ffL'ura|r: usage: /lura y <number>")
			return
		end
		LuraDB.y = n
		RequestApplyLayout()
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
		RequestApplyLayout()
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
			RequestApplyLayout()
		end
		local setting = Settings.RegisterProxySetting(
			category,
			"LURA_SHOW_UI",
			Settings.VarType.Boolean,
			"Show L'ura",
			true,
			GetValue,
			SetValue
		)
		Settings.CreateCheckbox(
			category,
			setting,
			"Order strip (synced icons) and leader bar. Leader bar appears only when you are solo or party/raid leader or assistant. |cffaaaaaa/lura|r toggles; |cffaaaaaa/lura help|r for commands."
		)
	end

	do
		local function GetValue()
			return LuraDB.locked
		end
		local function SetValue(v)
			LuraDB.locked = v
			RequestApplyLayout()
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
		Settings.CreateCheckbox(category, setting, "When unlocked, drag the left grip on the leader bar or order strip to move each frame.")
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
				RequestApplyLayout()
			end
		)
		local options = Settings.CreateSliderOptions(0.35, 3, 0.05)
		options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
			return string.format("%.2f", value)
		end)
		Settings.CreateSlider(category, setting, options, "Scale for both the leader bar and the order strip.")
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
				RequestApplyLayout()
			end
		)
		CreateDropdown(category, setting, GetAnchorOptions, "Anchor for the leader bar only (order strip has its own saved position).")
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
				RequestApplyLayout()
			end
		)
		local options = Settings.CreateSliderOptions(-1200, 1200, 1)
		options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
			return tostring(math.floor(value + 0.5))
		end)
		Settings.CreateSlider(category, setting, options, "Horizontal offset for the leader bar.")
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
				RequestApplyLayout()
			end
		)
		local options = Settings.CreateSliderOptions(-1200, 1200, 1)
		options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
			return tostring(math.floor(value + 0.5))
		end)
		Settings.CreateSlider(category, setting, options, "Vertical offset for the leader bar.")
	end

	local resetInit = CreateSettingsButtonInitializer(
		"Reset layout",
		"Reset layout",
		function()
			ResetToDefaults()
		end,
		"Restore default scale, anchors, and offsets.\n\n|cffaaaaaa/lura|r toggles UI; leader bar only if solo or lead/assist. Order strip: synced icons (30s idle clear).\n\nSlash: |cffaaaaaa/lura help|r, |cffaaaaaa/lura reset|r, |cffaaaaaa/lura config|r.",
		true
	)
	local settingsLayout = layout or (SettingsPanel and SettingsPanel.GetLayout and SettingsPanel:GetLayout(category))
	if settingsLayout and settingsLayout.AddInitializer then
		settingsLayout:AddInitializer(resetInit)
	end

	Settings.RegisterAddOnCategory(category)
end

-- If UI was created during combat lockdown, macrotext was skipped; apply when lockdown ends.
local macroRefreshFrame = CreateFrame("Frame")
macroRefreshFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
macroRefreshFrame:SetScript("OnEvent", function()
	RefreshLuraButtonMacros()
	if luraLayoutPending then
		ApplyLayout()
	end
end)

local commsFrame = CreateFrame("Frame")
commsFrame:RegisterEvent("CHAT_MSG_ADDON")
commsFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
commsFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
commsFrame:SetScript("OnEvent", function(_, event, ...)
	if event == "CHAT_MSG_ADDON" then
		local prefix, message, _, sender = ...
		if prefix ~= ORDER_PREFIX or not IsInGroup() then
			return
		end
		OnAddonOrderMessage(sender, message)
	elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
		if not IsInGroup() then
			ClearOrderSyncState()
		end
		if bar then
			RequestApplyLayout()
		end
	end
end)

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(_, event, name)
	if name ~= ADDON_NAME then
		return
	end
	C_ChatInfo.RegisterAddonMessagePrefix(ORDER_PREFIX)
	MergeDefaults()
	if not createdUI then
		CreateMainUI()
	end
	if Settings and Settings.RegisterVerticalLayoutCategory and not settingsCategory then
		RegisterOptions()
	end
end)
