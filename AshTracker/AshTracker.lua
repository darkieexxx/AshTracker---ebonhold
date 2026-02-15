--[[
    Ash Tracker - Tracks Soul Ash per hour for Project Ebonhold.
    Click the button to open the tracker menu.
]]

local addonName, _ = ...
local ADDON_TITLE = "Ash Tracker"
local ADDON_VERSION = "1.1.0"

-- SavedVariables defaults
if not AshTrackerDB then
    AshTrackerDB = {
        buttonPos = nil,   -- { point, relativePoint, x, y }
        windowPos = nil,  -- { point, relativePoint, x, y }
    }
end

-- Session state
local sessionStartTime = nil
local sessionStartAsh = nil
local currentAsh = 0
local peakAshPerHour = 0  -- best ash/hr this session
local currentIntensity = 0  -- intensity level from Project Ebonhold (0-5)
local currentSoulAshMultiplier = 0  -- decimal e.g. 0.35 = +35%, from UpdateData
local FormatLargeNumber = _G.FormatLargeNumber

local function GetAshPerHour()
    if sessionStartTime == nil then return 0, 0, 0 end
    local elapsed = GetTime() - sessionStartTime
    local hours = elapsed / 3600
    local gained = currentAsh - (sessionStartAsh or 0)
    local perHour = (hours > 0.0001) and (gained / hours) or 0
    return perHour, gained, elapsed
end

local function FormatTime(seconds)
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = math.floor(seconds % 60)
    if h > 0 then
        return ("%d:%02d:%02d"):format(h, m, s)
    end
    return ("%d:%02d"):format(m, s)
end

-- =====================
-- Menu frame
-- =====================
local menuFrame = nil

-- Theme colors (ash/fire: dark with amber accents)
local COLORS = {
    label = { 0.65, 0.6, 0.55 },   -- muted warm gray
    value = { 1, 0.85, 0.55 },     -- amber/gold for values
    title = { 1, 0.75, 0.35 },     -- warm gold for title (fits ash/fire theme)
    highlight = { 1, 0.6, 0.15 },  -- orange for peak
    section = { 0.5, 0.45, 0.35 }, -- section headers
    dim = { 0.4, 0.35, 0.3 },      -- dividers / subtle
}

local function UpdateMenuDisplay()
    if not menuFrame or not menuFrame:IsShown() then return end
    local perHour, gained, elapsed = GetAshPerHour()
    if perHour > (peakAshPerHour or 0) then
        peakAshPerHour = perHour
    end
    local fmt = function(n)
        return FormatLargeNumber and FormatLargeNumber(n) or ("%.0f"):format(n)
    end
    local V, H = COLORS.value, COLORS.highlight

    menuFrame.ashThisRunLabel:SetFormattedText("Ash this run: |cff%02x%02x%02x%s|r", V[1]*255, V[2]*255, V[3]*255, fmt(gained))
    menuFrame.currentTotalLabel:SetFormattedText("Current total: |cff%02x%02x%02x%s|r", V[1]*255, V[2]*255, V[3]*255, fmt(currentAsh))
    menuFrame.timeLabel:SetFormattedText("Time: |cff%02x%02x%02x%s|r", V[1]*255, V[2]*255, V[3]*255, FormatTime(elapsed))

    -- Hero stat: Ash/hr (larger)
    menuFrame.ashPerHourLabel:SetFormattedText("|cff%02x%02x%02x%s|r /hr", V[1]*255, V[2]*255, V[3]*255, fmt(perHour))
    menuFrame.peakLabel:SetFormattedText("Peak: |cff%02x%02x%02x%s|r", H[1]*255, H[2]*255, H[3]*255, fmt(peakAshPerHour or 0))

    -- Intensity level
    if menuFrame.intensityLabel then
        menuFrame.intensityLabel:SetFormattedText("Intensity: |cff%02x%02x%02x%d|r", V[1]*255, V[2]*255, V[3]*255, currentIntensity)
    end
    -- Soul Ash Multiplier (+35% etc.)
    if menuFrame.multiplierLabel then
        local pct = math.floor((currentSoulAshMultiplier or 0) * 100)
        menuFrame.multiplierLabel:SetFormattedText("Soul Ash Multiplier: |cff%02x%02x%02x+%d%%|r", V[1]*255, V[2]*255, V[3]*255, pct)
    end
end

local function CreateMenuFrame()
    if menuFrame then return menuFrame end

    local f = CreateFrame("Frame", "AshTracker_MenuFrame", UIParent)
    f:SetSize(300, 360)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint(1)
        AshTrackerDB.windowPos = { point, relativePoint, x, y }
    end)

    -- Dark panel with amber-tinted border (ash theme)
    f:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0.08, 0.06, 0.05, 1)
    f:SetBackdropBorderColor(0.4, 0.25, 0.1, 1)

    -- Title bar strip
    local titleBar = f:CreateTexture(nil, "ARTWORK")
    titleBar:SetPoint("TOPLEFT", 4, -4)
    titleBar:SetPoint("TOPRIGHT", -4, -4)
    titleBar:SetHeight(36)
    titleBar:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
    titleBar:SetVertexColor(0.15, 0.1, 0.08, 1)

    -- Title (warm gold, theme-matched)
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -14)
    title:SetTextColor(COLORS.title[1], COLORS.title[2], COLORS.title[3])
    title:SetText(ADDON_TITLE)
    f.title = title

    local subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    subtitle:SetPoint("TOP", title, "BOTTOM", 0, -2)
    subtitle:SetTextColor(0.78, 0.72, 0.62)
    subtitle:SetText("Add-on version " .. ADDON_VERSION)
    f.subtitle = subtitle

    -- Divider under header (anchored to subtitle so header never overlaps)
    local div1 = f:CreateTexture(nil, "ARTWORK")
    div1:SetPoint("TOP", subtitle, "BOTTOM", 0, -14)
    div1:SetPoint("LEFT", f, "LEFT", 12, 0)
    div1:SetPoint("RIGHT", f, "RIGHT", -12, 0)
    div1:SetHeight(1)
    div1:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
    div1:SetVertexColor(COLORS.dim[1], COLORS.dim[2], COLORS.dim[3], 0.8)

    -- Section: Session
    local sessionHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sessionHeader:SetPoint("TOP", div1, "BOTTOM", 0, -10)
    sessionHeader:SetPoint("LEFT", f, "LEFT", 14, 0)
    sessionHeader:SetTextColor(COLORS.section[1], COLORS.section[2], COLORS.section[3])
    sessionHeader:SetText("SESSION")
    f.sessionHeader = sessionHeader

    local ashThisRunLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ashThisRunLabel:SetPoint("TOP", sessionHeader, "BOTTOM", 0, -6)
    ashThisRunLabel:SetPoint("LEFT", 14, 0)
    ashThisRunLabel:SetText("Ash this run: 0")
    f.ashThisRunLabel = ashThisRunLabel

    local currentTotalLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    currentTotalLabel:SetPoint("TOP", ashThisRunLabel, "BOTTOM", 0, -4)
    currentTotalLabel:SetPoint("LEFT", 14, 0)
    currentTotalLabel:SetText("Current total: 0")
    f.currentTotalLabel = currentTotalLabel

    local timeLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    timeLabel:SetPoint("TOP", currentTotalLabel, "BOTTOM", 0, -4)
    timeLabel:SetPoint("LEFT", 14, 0)
    timeLabel:SetText("Time: 0:00")
    f.timeLabel = timeLabel

    -- Divider before Rates (no y=0 anchor – use only TOP relative to timeLabel)
    local div2 = f:CreateTexture(nil, "ARTWORK")
    div2:SetPoint("TOP", timeLabel, "BOTTOM", 0, -14)
    div2:SetPoint("LEFT", f, "LEFT", 12, 0)
    div2:SetPoint("RIGHT", f, "RIGHT", -12, 0)
    div2:SetHeight(1)
    div2:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
    div2:SetVertexColor(COLORS.dim[1], COLORS.dim[2], COLORS.dim[3], 0.8)

    -- Section: Rates
    local ratesHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ratesHeader:SetPoint("TOP", div2, "BOTTOM", 0, -10)
    ratesHeader:SetPoint("LEFT", f, "LEFT", 14, 0)
    ratesHeader:SetTextColor(COLORS.section[1], COLORS.section[2], COLORS.section[3])
    ratesHeader:SetText("RATE")
    f.ratesHeader = ratesHeader

    -- Thin line inside RATE section (replaces progress bar)
    local rateDiv = f:CreateTexture(nil, "ARTWORK")
    rateDiv:SetPoint("TOP", ratesHeader, "BOTTOM", 0, -8)
    rateDiv:SetPoint("LEFT", f, "LEFT", 14, 0)
    rateDiv:SetPoint("RIGHT", f, "RIGHT", -14, 0)
    rateDiv:SetHeight(1)
    rateDiv:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
    rateDiv:SetVertexColor(COLORS.dim[1], COLORS.dim[2], COLORS.dim[3], 0.8)
    f.rateDiv = rateDiv

    -- Hero stat: Ash/hr (larger font)
    local ashLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    ashLabel:SetPoint("TOP", rateDiv, "BOTTOM", 0, -10)
    ashLabel:SetPoint("LEFT", f, "LEFT", 14, 0)
    ashLabel:SetText("0 /hr")
    f.ashPerHourLabel = ashLabel

    local peakLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    peakLabel:SetPoint("TOP", ashLabel, "BOTTOM", 0, -6)
    peakLabel:SetPoint("LEFT", f, "LEFT", 14, 0)
    peakLabel:SetText("Peak: --")
    f.peakLabel = peakLabel

    -- Line under peak, then intensity level
    local intensityDiv = f:CreateTexture(nil, "ARTWORK")
    intensityDiv:SetPoint("TOP", peakLabel, "BOTTOM", 0, -10)
    intensityDiv:SetPoint("LEFT", f, "LEFT", 14, 0)
    intensityDiv:SetPoint("RIGHT", f, "RIGHT", -14, 0)
    intensityDiv:SetHeight(1)
    intensityDiv:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
    intensityDiv:SetVertexColor(COLORS.dim[1], COLORS.dim[2], COLORS.dim[3], 0.8)
    f.intensityDiv = intensityDiv

    local intensityLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    intensityLabel:SetPoint("TOP", intensityDiv, "BOTTOM", 0, -8)
    intensityLabel:SetPoint("LEFT", f, "LEFT", 14, 0)
    intensityLabel:SetText("Intensity: 0")
    f.intensityLabel = intensityLabel

    local multiplierLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    multiplierLabel:SetPoint("TOP", intensityLabel, "BOTTOM", 0, -6)
    multiplierLabel:SetPoint("LEFT", f, "LEFT", 14, 0)
    multiplierLabel:SetText("Soul Ash Multiplier: +0%")
    f.multiplierLabel = multiplierLabel

    -- Drag hint (title bar)
    local dragHint = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dragHint:SetPoint("TOPRIGHT", closeBtn, "TOPLEFT", -8, 0)
    dragHint:SetTextColor(COLORS.dim[1], COLORS.dim[2], COLORS.dim[3], 0.8)
    dragHint:SetText("Drag to move")

    -- Reset button (theme-styled: dark + amber border)
    local resetBtn = CreateFrame("Button", nil, f)
    resetBtn:SetSize(110, 28)
    resetBtn:SetPoint("BOTTOM", 0, 14)
    resetBtn:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, tileSize = 0, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    resetBtn:SetBackdropColor(0.12, 0.08, 0.06, 0.95)
    resetBtn:SetBackdropBorderColor(0.45, 0.28, 0.12, 1)
    local resetLabel = resetBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    resetLabel:SetPoint("CENTER", 0, 0)
    resetLabel:SetTextColor(COLORS.value[1], COLORS.value[2], COLORS.value[3])
    resetLabel:SetText("Reset Session")
    resetBtn:SetScript("OnClick", function()
        sessionStartTime = nil
        sessionStartAsh = nil
        peakAshPerHour = 0
        UpdateMenuDisplay()
    end)
    resetBtn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0.65, 0.4, 0.18, 1)
        resetLabel:SetTextColor(1, 0.9, 0.6)
    end)
    resetBtn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.45, 0.28, 0.12, 1)
        resetLabel:SetTextColor(COLORS.value[1], COLORS.value[2], COLORS.value[3])
    end)

    -- Close button
    -- Close button (theme-styled: dark + amber, no red)
    local closeBtn = CreateFrame("Button", nil, f)
    closeBtn:SetSize(28, 28)
    closeBtn:SetPoint("TOPRIGHT", 2, 2)
    closeBtn:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, tileSize = 0, edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    closeBtn:SetBackdropColor(0.12, 0.08, 0.06, 0.95)
    closeBtn:SetBackdropBorderColor(0.45, 0.28, 0.12, 1)
    local closeX = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    closeX:SetPoint("CENTER", 0, 0)
    closeX:SetTextColor(COLORS.value[1], COLORS.value[2], COLORS.value[3])
    closeX:SetText("×")
    closeBtn:SetScript("OnClick", function()
        f:Hide()
    end)
    closeBtn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0.65, 0.4, 0.18, 1)
        closeX:SetTextColor(1, 0.9, 0.6)
    end)
    closeBtn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.45, 0.28, 0.12, 1)
        closeX:SetTextColor(COLORS.value[1], COLORS.value[2], COLORS.value[3])
    end)

    f:Hide()
    menuFrame = f
    return f
end

local function RestoreMenuPosition()
    if not menuFrame then return end
    if AshTrackerDB.windowPos and AshTrackerDB.windowPos[1] then
        local p = AshTrackerDB.windowPos
        menuFrame:ClearAllPoints()
        menuFrame:SetPoint(p[1], UIParent, p[2], p[3] or 0, p[4] or 0)
    end
end

local function ToggleMenu()
    local f = CreateMenuFrame()
    RestoreMenuPosition()
    if f:IsShown() then
        f:Hide()
    else
        f:Show()
        UpdateMenuDisplay()
    end
end

-- =====================
-- Open menu (global)
-- =====================
_G.AshTracker_OpenMenu = ToggleMenu

-- =====================
-- Button (opens menu)
-- =====================
local mainButton = nil

local function CreateMainButton()
    if mainButton then return mainButton end

    local btn = CreateFrame("Button", "AshTracker_Button", UIParent)
    btn:SetSize(40, 40)
    btn:SetPoint("CENTER", UIParent, "CENTER", -200, 0)
    btn:SetFrameStrata("MEDIUM")
    btn:SetClampedToScreen(true)
    btn:EnableMouse(true)
    btn:SetMovable(true)
    btn:RegisterForDrag("LeftButton")
    btn:RegisterForClicks("LeftButtonUp")

    -- Backdrop: dark panel with amber border (matches menu)
    btn:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, tileSize = 0, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    btn:SetBackdropColor(0.1, 0.07, 0.05, 0.92)
    btn:SetBackdropBorderColor(0.45, 0.28, 0.12, 1)

    -- Hover glow (amber tint)
    local hoverBg = btn:CreateTexture(nil, "BACKGROUND")
    hoverBg:SetAllPoints()
    hoverBg:SetTexture("Interface\\Buttons\\UI-SquareButton-Up")
    hoverBg:SetTexCoord(0.2, 0.8, 0.2, 0.8)
    hoverBg:SetVertexColor(0.5, 0.3, 0.1, 0.4)
    hoverBg:Hide()
    btn.hoverBg = hoverBg

    local pushed = btn:CreateTexture(nil, "ARTWORK")
    pushed:SetAllPoints()
    pushed:SetTexture("Interface\\Buttons\\UI-SquareButton-Down")
    pushed:SetTexCoord(0.2, 0.8, 0.2, 0.8)
    pushed:SetVertexColor(0.6, 0.35, 0.15, 0.5)
    pushed:Hide()
    btn.pushed = pushed

    -- Icon (soul)
    local icon = btn:CreateTexture(nil, "OVERLAY")
    icon:SetPoint("CENTER", 0, 0)
    icon:SetSize(26, 26)
    icon:SetTexture("Interface\\Icons\\inv_misc_soulshard")
    icon:SetVertexColor(1, 0.92, 0.85)
    btn.icon = icon

    btn:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    btn:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint(1)
        AshTrackerDB.buttonPos = { point, relativePoint, x, y }
    end)
    btn:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "LeftButton" then
            ToggleMenu()
        end
    end)
    btn:SetScript("OnEnter", function(self)
        self.hoverBg:Show()
        self:SetBackdropBorderColor(0.7, 0.45, 0.2, 1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(ADDON_TITLE, 1, 1, 1)
        local perHour, gained, elapsed = GetAshPerHour()
        if sessionStartTime and (gained > 0 or elapsed > 0) then
            local fmt = function(n) return FormatLargeNumber and FormatLargeNumber(n) or ("%.0f"):format(n) end
            GameTooltip:AddLine(("Session: %s /hr · %s"):format(fmt(perHour), FormatTime(elapsed)), 0.85, 0.75, 0.5, true)
        else
            GameTooltip:AddLine("Click to open Ash per hour tracker", 0.7, 0.7, 0.7, true)
        end
        GameTooltip:AddLine("Drag to move", 0.5, 0.5, 0.5, true)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function(self)
        self.hoverBg:Hide()
        self.pushed:Hide()
        self:SetBackdropBorderColor(0.45, 0.28, 0.12, 1)
        GameTooltip:Hide()
    end)
    btn:SetScript("OnMouseDown", function(self)
        self.pushed:Show()
    end)
    btn:SetScript("OnMouseUp", function(self)
        self.pushed:Hide()
    end)

    -- Restore saved position
    if AshTrackerDB.buttonPos and AshTrackerDB.buttonPos[1] then
        local p = AshTrackerDB.buttonPos
        btn:ClearAllPoints()
        btn:SetPoint(p[1], UIParent, p[2], p[3] or 0, p[4] or 0)
    end

    btn:Show()
    mainButton = btn
    return btn
end

-- =====================
-- Hook Project Ebonhold for soul points
-- =====================
local function HookProjectEbonhold(attempts)
    attempts = attempts or 0
    if attempts > 40 then return end -- ~20 sec

    if not ProjectEbonhold or not ProjectEbonhold.PlayerRunUI or not ProjectEbonhold.PlayerRunUI.UpdateData then
        C_Timer.After(0.5, function() HookProjectEbonhold(attempts + 1) end)
        return
    end

    hooksecurefunc(ProjectEbonhold.PlayerRunUI, "UpdateData", function(data)
        if not data then return end
        if data.soulPoints ~= nil then
            currentAsh = data.soulPoints
            if sessionStartTime == nil then
                sessionStartTime = GetTime()
                sessionStartAsh = currentAsh
            end
            local perHour = select(1, GetAshPerHour())
            if perHour > (peakAshPerHour or 0) then
                peakAshPerHour = perHour
            end
        end
        if data.soulPointsMultiplier ~= nil then
            currentSoulAshMultiplier = tonumber(data.soulPointsMultiplier) or 0
        end
        UpdateMenuDisplay()
    end)

    -- Intensity comes from UpdateIntensity, not UpdateData (same API as EHTweaks)
    if ProjectEbonhold.PlayerRunUI.UpdateIntensity then
        hooksecurefunc(ProjectEbonhold.PlayerRunUI, "UpdateIntensity", function(data)
            if data and data.intensity ~= nil then
                currentIntensity = tonumber(data.intensity) or 0
                UpdateMenuDisplay()
            end
        end)
    end
end

-- =====================
-- Ticker to refresh menu when open
-- =====================
local ticker = nil
local function StartTicker()
    if ticker then return end
    ticker = C_Timer.NewTicker(1, function()
        if menuFrame and menuFrame:IsShown() then
            UpdateMenuDisplay()
        end
    end)
end

-- =====================
-- Init
-- =====================
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        -- Reset session on new login
        sessionStartTime = nil
        sessionStartAsh = nil
        peakAshPerHour = 0
        CreateMainButton()
        HookProjectEbonhold(0)
        StartTicker()
    elseif event == "PLAYER_ENTERING_WORLD" then
        sessionStartTime = nil
        sessionStartAsh = nil
        peakAshPerHour = 0
    end
end)

-- Slash command
SLASH_ASHTRACKER1 = "/ashtracker"
SLASH_ASHTRACKER2 = "/ash"
SlashCmdList["ASHTRACKER"] = function()
    ToggleMenu()
end
