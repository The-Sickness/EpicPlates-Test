-- Made by Sharpedge_Gaming
-- v1.2 - 11.0.2

local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local LSM = LibStub("LibSharedMedia-3.0")
local LDB = LibStub("LibDataBroker-1.1")
local LDBIcon = LibStub("LibDBIcon-1.0")
local LibButtonGlow = LibStub("LibButtonGlow-1.0") 

local INFO_POINT            = 'TOP'
local INFO_RELATIVE_POINT   = 'BOTTOM'
local INFO_X                = 0
local INFO_Y                = 0

local NAMEPLATE_ALPHA       = 0.7
local ICON_SIZE             = 20 
local MAX_BUFFS             = 10 
local MAX_DEBUFFS           = 10  
local BUFF_ICON_OFFSET_Y    = 20 
local DEBUFF_ICON_OFFSET_Y  = 10 
local BUFFS_PER_LINE        = 6  
local DEBUFFS_PER_LINE      = 6 
local MAX_ROWS              = 3  
local LINE_SPACING_Y        = 9 

if not EpicPlates then
    EpicPlates = LibStub('AceAddon-3.0'):NewAddon('EpicPlates', 'AceHook-3.0', 'AceEvent-3.0', 'AceTimer-3.0')
end

EpicPlates.defaults = {
    profile = {
        iconSize = 20,
        timerFontSize = 10,
        timerFont = "Friz Quadrata TT",
        timerFontColor = {1, 1, 1},
        buffIconPositions = {},
        debuffIconPositions = {},
        showHealthPercent = false,
        healthPercentFontColor = {1, 1, 1}, 
        timerPosition = "BELOW",	
        iconXOffset = 0,   
        iconYOffset = 0,
        iconGlowEnabled = true,		
    },
}

local GetNamePlateForUnit = C_NamePlate.GetNamePlateForUnit
local EpicPlatesTooltip = CreateFrame('GameTooltip', 'EpicPlatesTooltip', nil, 'GameTooltipTemplate')

function EpicPlates:OnEnable()
    C_CVar.SetCVar('nameplateShowAll', '1')
    C_CVar.SetCVar('nameplateShowFriends', '0') 
    C_CVar.SetCVar('nameplateShowFriendlyNPCs', '0') 
    C_CVar.SetCVar('showQuestTrackingTooltips', '1')

    self:RegisterEvent('NAME_PLATE_CREATED')
    self:RegisterEvent('NAME_PLATE_UNIT_ADDED')
    self:RegisterEvent('NAME_PLATE_UNIT_REMOVED')
    self:RegisterEvent('UNIT_THREAT_LIST_UPDATE')
    self:RegisterEvent("PLAYER_TARGET_CHANGED")
    self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", "OnCombatLogEventUnfiltered")

    if not self:IsHooked('CompactUnitFrame_UpdateName') then
        self:SecureHook('CompactUnitFrame_UpdateName')
    end

    self:ScheduleRepeatingTimer("UpdateAllAuras", 0.1)

    self:DisableDefaultBuffsDebuffs()

    C_Timer.After(1, function()
        self:InitializeAlwaysShow()
    end)
end

local EpicPlatesLDB = LibStub("LibDataBroker-1.1"):NewDataObject("EpicPlates", {
    type = "launcher",
    text = "EpicPlates",
    icon = 3565720,  
    OnClick = function(_, button)
        if button == "LeftButton" then
            if Settings and Settings.OpenToCategory then
                Settings.OpenToCategory("EpicPlates")
            else
                InterfaceOptionsFrame_OpenToCategory("EpicPlates")
                InterfaceOptionsFrame_OpenToCategory("EpicPlates")  
            end
        elseif button == "RightButton" then
            if Settings and Settings.OpenToCategory then
                Settings.OpenToCategory("InterfaceOptionsFrame")  
            else
                InterfaceOptionsFrame_OpenToCategory("InterfaceOptionsFrame")
            end
        end
    end,
    OnTooltipShow = function(tooltip)
        tooltip:AddLine("|cFF00FF00EpicPlates|r")  
        tooltip:AddLine("|cFF00CCFFLeft-click|r: Open EpicPlates settings")  
        tooltip:AddLine("|cFFFFA500Right-click|r: Open Interface Options")  
    end,
})

function EpicPlates:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("EpicPlatesDB", {
        profile = {
            iconSize = 20,
            timerFontSize = 12,
            timerFont = "Arial Narrow",
            timerFontColor = {1, 1, 1},
            healthBarTexture = LSM:GetDefault("statusbar"),  
            minimap = { hide = false },
            auraFilters = {
                spellIDs = {},
                spellNames = {},
                casterNames = {}
            },
            alwaysShow = {
                spellIDs = {},
                spellNames = {}
            }
        }
    }, true)

    if not _G.defaultSpells1 or not _G.defaultSpells2 then
    else
        importantSpells = importantSpells or _G.defaultSpells1
        semiImportantSpells = semiImportantSpells or _G.defaultSpells2
    end

    if not self.db.profile.minimap then
        self.db.profile.minimap = { hide = false }
    end

    self:SetupOptions()
    self:UpdateIconPositions()
    self:OnEnable()
    self:UpdateTimerFontSize()

    -- Register the minimap icon
    LDBIcon:Register("EpicPlates", EpicPlatesLDB, self.db.profile.minimap)
    
    self:UpdateIconSize()

    C_Timer.After(0.5, function() 
        self:UpdateIconSize() 
    end)

    self:ApplyTextureToAllNameplates()  
end

local racialAbilities = {
    [59752] = true, -- Human - Every Man for Himself
    [7744]  = true, -- Undead - Will of the Forsaken
    [20594] = true, -- Dwarf - Stoneform
	[58984] = true, --Shadowmeld
}

-- Racial categories to filter relevant races
local racialCategories = {
    ["Human"] = true,
    ["Scourge"] = true,
    ["Dwarf"] = true,
	["NightElf"] = true,
}

-- Racial data (for icons and shared cooldown logic)
local racialData = {
    ["Human"] = { texture = C_Spell.GetSpellTexture(59752), sharedCD = 90 },
    ["Scourge"] = { texture = C_Spell.GetSpellTexture(7744), sharedCD = 30 },
    ["Dwarf"] = { texture = C_Spell.GetSpellTexture(20594), sharedCD = 30 },
	["NightElf"] = {texture = C_Spell.GetSpellTexture(58984), sharedCD = 0 },
}

-- Utility function to get the remaining cooldown time
local function GetRemainingCD(frame)
    local startTime, duration = frame:GetCooldownTimes()
    if (startTime == 0) then return 0 end

    local currTime = GetTime()
    return (startTime + duration) / 1000 - currTime
end

local function GetRacialAbility(unit)
    local raceLocalized, race = UnitRace(unit)  
    race = race:gsub("%s", ""):lower()  
    
    if racialData[race] then
        return racialData[race]  
    end

    return nil  
end

-- Function to show racial ability icons for enemy players
function ShowPvPRacial(unit)
    if not UnitIsPlayer(unit) or not UnitIsEnemy("player", unit) then return end

    local nameplate = C_NamePlate.GetNamePlateForUnit(unit)
    if not nameplate then return end
    local UnitFrame = nameplate.UnitFrame

    if not UnitFrame then return end

    if not UnitFrame.PvPRacialFrame then
        UnitFrame.PvPRacialFrame = CreateFrame("Frame", nil, UnitFrame)
        UnitFrame.PvPRacialFrame:SetSize(22, 22) 
        UnitFrame.PvPRacialFrame:SetPoint("RIGHT", UnitFrame, "LEFT", -2, 0)

        UnitFrame.RacialCooldownOverlay = CreateFrame("Cooldown", nil, UnitFrame.PvPRacialFrame, "CooldownFrameTemplate")
        UnitFrame.RacialCooldownOverlay:SetAllPoints(UnitFrame.PvPRacialFrame)

        UnitFrame.RacialCooldownText = UnitFrame.PvPRacialFrame:CreateFontString(nil, "OVERLAY")
        UnitFrame.RacialCooldownText:SetFont("Fonts\\FRIZQT__.TTF", 12, "THICKOUTLINE")
        UnitFrame.RacialCooldownText:SetPoint("CENTER", UnitFrame.PvPRacialFrame, "CENTER", 0, 0)
        UnitFrame.RacialCooldownText:SetTextColor(1, 1, 1, 1)
        UnitFrame.RacialCooldownText:Hide()

        UnitFrame.PvPRacialFrame.texture = UnitFrame.PvPRacialFrame:CreateTexture(nil, "OVERLAY")
        UnitFrame.PvPRacialFrame.texture:SetAllPoints(UnitFrame.PvPRacialFrame)
    end

    local racialAbility = GetRacialAbility(unit)
    if racialAbility then
        UnitFrame.PvPRacialFrame.texture:SetTexture(racialAbility.texture)
        UnitFrame.PvPRacialFrame:Show()

        if not UnitFrame.PvPRacialFrame.glowApplied then
            ActionButton_ShowOverlayGlow(UnitFrame.PvPRacialFrame) 
            UnitFrame.PvPRacialFrame.glowApplied = true
        end
    end
end

local function HidePvPRacial(unit)
    local nameplate = C_NamePlate.GetNamePlateForUnit(unit)
    if nameplate and nameplate.UnitFrame and nameplate.UnitFrame.PvPRacialFrame then
        nameplate.UnitFrame.PvPRacialFrame:Hide()
    end
end

local gladiatorMedallionSpellID = 336126 
local adaptationSpellID = 214027 
local trinketCooldown = 120 

local function UpdateCooldownText(UnitFrame, cooldownText, endTime)
    if not endTime or endTime <= GetTime() then
        cooldownText:Hide()
        return
    end

    if UnitFrame.ticker then
        UnitFrame.ticker:Cancel() 
    end

    UnitFrame.ticker = C_Timer.NewTicker(0.1, function()
        local remainingTime = endTime - GetTime()

        if remainingTime > 0 then
            cooldownText:SetText(string.format("%d", math.ceil(remainingTime)))
            cooldownText:Show()
            cooldownText:SetTextColor(1, 1, 1, 1)  
        else
            cooldownText:Hide()
            UnitFrame.ticker:Cancel()
        end
    end)
end

-- Function to handle Gladiator trinket icons and ensure they always show
local function ShowPvPTrinket(unit)
    if not UnitIsPlayer(unit) or not UnitIsEnemy("player", unit) then return end

    local nameplate = C_NamePlate.GetNamePlateForUnit(unit)
    if not nameplate then return end
    local UnitFrame = nameplate.UnitFrame

    if not UnitFrame then return end

    if not UnitFrame.PvPTrinketFrame then
        UnitFrame.PvPTrinketFrame = CreateFrame("Frame", nil, UnitFrame)
        UnitFrame.PvPTrinketFrame:SetSize(22, 22)
        UnitFrame.PvPTrinketFrame:SetPoint("LEFT", UnitFrame, "RIGHT", -2, 0)

        UnitFrame.TrinketCooldownOverlay = CreateFrame("Cooldown", nil, UnitFrame.PvPTrinketFrame, "CooldownFrameTemplate")
        UnitFrame.TrinketCooldownOverlay:SetAllPoints(UnitFrame.PvPTrinketFrame)

        UnitFrame.TrinketCooldownText = UnitFrame.PvPTrinketFrame:CreateFontString(nil, "OVERLAY")
        UnitFrame.TrinketCooldownText:SetFont("Fonts\\FRIZQT__.TTF", 12, "THICKOUTLINE")
        UnitFrame.TrinketCooldownText:SetPoint("CENTER", UnitFrame.PvPTrinketFrame, "CENTER", 0, 0)
        UnitFrame.TrinketCooldownText:SetTextColor(1, 1, 1, 1)
        UnitFrame.TrinketCooldownText:Hide()
    end

    if not UnitFrame.PvPTrinketFrame.isSet then
        local trinketTexture = UnitFrame.PvPTrinketFrame:CreateTexture(nil, "OVERLAY")
        trinketTexture:SetAllPoints(UnitFrame.PvPTrinketFrame)
        trinketTexture:SetTexture(1322720) 
        UnitFrame.PvPTrinketFrame.isSet = true
    end

    UnitFrame.PvPTrinketFrame:Show()
end

-- Event handler for racial ability usage
function OnSpellCastSuccess(event, spellID)
    local duration = racialSpells[spellID]
    local currTime = GetTime()

    -- Check if it's a racial ability
    if duration then
        -- Update racial cooldown
        local nameplate = C_NamePlate.GetNamePlateForUnit(unit)
        if nameplate and nameplate.UnitFrame and nameplate.UnitFrame.RacialCooldownOverlay then
            nameplate.UnitFrame.RacialCooldownOverlay:SetCooldown(currTime, duration)
        end
    elseif spellID == 336126 or spellID == 336135 then
        -- Handle Gladiator's Medallion
        local nameplate = C_NamePlate.GetNamePlateForUnit(unit)
        if nameplate and nameplate.UnitFrame and nameplate.UnitFrame.TrinketCooldownOverlay then
            nameplate.UnitFrame.TrinketCooldownOverlay:SetCooldown(currTime, 120) -- Gladiator trinket is 120 seconds
        end
    end
end

local function HidePvPTrinket(unit)
    local nameplate = C_NamePlate.GetNamePlateForUnit(unit)
    if nameplate and nameplate.UnitFrame and nameplate.UnitFrame.PvPTrinketFrame then
        nameplate.UnitFrame.PvPTrinketFrame:Hide()
    end
end

function EpicPlates:ApplyTextureToAllNameplates()
    local texture = LSM:Fetch("statusbar", self.db.profile.healthBarTexture)
    for _, nameplate in pairs(C_NamePlate.GetNamePlates()) do
        nameplate.UnitFrame.healthBar:SetStatusBarTexture(texture)
    end
end

importantSpells = importantSpells or defaultSpells1
semiImportantSpells = semiImportantSpells or defaultSpells2

function EpicPlates:IsImportantSpell(spellID)
    for _, id in ipairs(importantSpells) do
        if id == spellID then
            return true
        end
    end
    return false
end

function EpicPlates:IsSemiImportantSpell(spellID)
    for _, id in ipairs(semiImportantSpells) do
        if id == spellID then
            return true
        end
    end
    return false
end

function EpicPlates:CompactUnitFrame_UpdateName(frame)
    if frame.unit and strsub(frame.unit, 1, 9) == "nameplate" then
        self:NiceNameplateInfo_Update(frame.unit)
        self:NiceNameplateFrames_Update(frame.unit)
        self:UpdateHealthBarWithPercent(frame.unit)  
    end
end

function EpicPlates:NAME_PLATE_CREATED(_, frame)
    self:NiceNameplateInfo_Create(frame)
    if frame.UnitFrame then
        local texture = LSM:Fetch("statusbar", self.db.profile.healthBarTexture)
        frame.UnitFrame.healthBar:SetStatusBarTexture(texture)
        self:UpdateHealthBarWithPercent(frame.UnitFrame.unit)  
    end
end

function EpicPlates:NAME_PLATE_UNIT_ADDED(_, unit)
    local nameplate = C_NamePlate.GetNamePlateForUnit(unit)

    if not nameplate or not nameplate.UnitFrame then
        return 
    end

    if UnitIsPlayer(unit) and UnitIsEnemy("player", unit) then
        ShowPvPTrinket(unit)
        ShowPvPRacial(unit)
    else
        HidePvPTrinket(unit)
        HidePvPRacial(unit)
    end
end

function EpicPlates:NAME_PLATE_UNIT_REMOVED(_, unit)
    HidePvPTrinket(unit)
    HidePvPRacial(unit)
end

function EpicPlates:NAME_PLATE_UNIT_REMOVED(_, unit)
    local nameplate = C_NamePlate.GetNamePlateForUnit(unit)
    if nameplate and nameplate.UnitFrame then
        self:UpdateHealthBarWithPercent(unit) 
		HidePvPTrinket(unit)
		HidePvPRacial(unit)
    end
end

-- Utility functions to hide trinket and racial icons
local function HidePvPTrinket(unit)
    local nameplate = C_NamePlate.GetNamePlateForUnit(unit)
    if nameplate and nameplate.UnitFrame and nameplate.UnitFrame.PvPTrinketFrame then
        nameplate.UnitFrame.PvPTrinketFrame:Hide()
    end
end

local function HidePvPRacial(unit)
    local nameplate = C_NamePlate.GetNamePlateForUnit(unit)
    if nameplate and nameplate.UnitFrame and nameplate.UnitFrame.PvPRacialFrame then
        nameplate.UnitFrame.PvPRacialFrame:Hide()
    end
end

function EpicPlates:UNIT_THREAT_LIST_UPDATE(_, unit)
    if unit and unit:match('nameplate') then
        self:NiceNameplateInfo_Update(unit)
        self:NiceNameplateFrames_Update(unit)
        self:UpdateHealthBarWithPercent(unit)  
    end
end

function EpicPlates:UpdateAllAuras()
    for _, NamePlate in pairs(C_NamePlate.GetNamePlates()) do
        local UnitFrame = NamePlate.UnitFrame
        if UnitFrame and UnitFrame.unit then
            self:UpdateAuras(UnitFrame.unit)
            self:UpdateHealthBarWithPercent(UnitFrame.unit)  
        end
    end
end

function EpicPlates:UpdateHealthBarWithPercent(unit)
    local nameplate = C_NamePlate.GetNamePlateForUnit(unit)
    if nameplate and nameplate.UnitFrame then
        local healthBar = nameplate.UnitFrame.healthBar
        if UnitIsUnit(unit, "target") and self.db.profile.showHealthPercent then
            local healthPercent = (UnitHealth(unit) / UnitHealthMax(unit)) * 100
            if not healthBar.text then
                healthBar.text = healthBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                healthBar.text:SetPoint("CENTER", healthBar, "CENTER", 0, 0)
            end
            healthBar.text:SetText(string.format("%.1f%%", healthPercent))
            local color = self.db.profile.healthPercentFontColor or {1, 1, 1}  
            local r, g, b = unpack(color)
            healthBar.text:SetTextColor(r, g, b)  
            healthBar.text:Show()
        else
            if healthBar.text then
                healthBar.text:Hide()
            end
        end
    end
end

function EpicPlates:UpdateAllNameplates()
    for _, namePlate in pairs(C_NamePlate.GetNamePlates()) do
        local unit = namePlate.UnitFrame.unit
        if unit then
            self:UpdateAuras(unit)
            self:UpdateHealthBarWithPercent(unit)
        end
    end
end

function EpicPlates:PLAYER_TARGET_CHANGED()
    self:UpdateAllNameplates()
end

-- Disable default buffs/debuffs on the nameplate
function EpicPlates:DisableDefaultBuffsDebuffs()
    local f = CreateFrame("Frame")
    local events = {}

    function events:NAME_PLATE_UNIT_ADDED(plate)
        local unitId = plate
        local nameplate = C_NamePlate.GetNamePlateForUnit(unitId)
        local frame = nameplate.UnitFrame
        if not nameplate or frame:IsForbidden() then return end
        frame.BuffFrame:ClearAllPoints()
        frame.BuffFrame:SetAlpha(0)
    end

    for j, u in pairs(events) do
        f:RegisterEvent(j)
    end

    f:SetScript("OnEvent", function(self, event, ...) events[event](self, ...) end)
end

local function GetUnitProperties(unit)
    local guid = UnitGUID(unit)
    if not guid then return end
    local unitType, _, _, _, _, ID = strsplit('-', guid)
    return unitType, ID
end

local function IsNPC(unit)
    local unitType, ID = GetUnitProperties(unit)
    return  not UnitIsBattlePet(unit) and
            not UnitIsPlayer(unit) and
            not UnitPlayerControlled(unit) and
            not UnitIsEnemy('player', unit) and
            not UnitCanAttack('player', unit) and
            (unitType == 'Creature')
end

local function RGBToHex(r, g, b)
    r = r <= 1 and r >= 0 and r or 0
    g = g <= 1 and r >= 0 and g or 0
    b = b <= 1 and b >= 0 and b or 0
    return string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
end

function EpicPlates:MakeInfoString(unit, item)
    EpicPlatesTooltip:SetOwner(WorldFrame, 'ANCHOR_NONE')
    EpicPlatesTooltip:SetUnit(unit)

    if item == 'name' then
        local name = UnitName(unit)
        return name
    elseif item == 'realm' then
        local _, realm = UnitName(unit)
        return realm
    elseif item == 'level' then
        local level = UnitLevel(unit)
        return (level == -1) and '??' or level
    elseif item == 'levelcolor' then
        local level = UnitLevel(unit)
        local levelcolor = GetCreatureDifficultyColor((level == -1) and 255 or level)
        return levelcolor
    elseif item == 'fullname' then
        local _, realm = UnitName(unit)
        local TooltipTextLeft1 = EpicPlatesTooltipTextLeft1:GetText()
        return (not realm and TooltipTextLeft1) or TooltipTextLeft1:gsub('-'..realm, '(*)')
    elseif item == 'guild' then
        local guild = GetGuildInfo(unit)
        return guild
    elseif item == 'profession' then
        if EpicPlatesTooltip:NumLines() > 2 then
            for i = 2, EpicPlatesTooltip:NumLines() do
                local TooltipTextLeft = _G['EpicPlatesTooltipTextLeft' .. i]:GetText()
                if not TooltipTextLeft:lower():match(LEVEL_GAINED:gsub('%%d', '[%%d?]+'):lower()) and
                   not TooltipTextLeft:lower():match(LEVEL:lower()..' ([%d?]+)%s?%(?([^)]*)%)?') then
                    return TooltipTextLeft
                end
            end
        end
    elseif item == 'localizedclass' then
        return UnitClassBase(unit)
    elseif item == 'englishclass' then
        local _, englishclass = UnitClass(unit)
        return englishclass
    elseif item == 'classcolor' then
        local _, englishclass = UnitClass(unit)
        return RAID_CLASS_COLORS[englishclass]
    elseif item == 'localizedrace' then
        return UnitRace(unit)
    elseif item == 'englishrace' then
        local _, englishrace = UnitRace(unit)
        return englishrace
    elseif item == 'creaturetype' then
        return UnitCreatureType(unit)
    elseif item == 'creaturefamily' then
        return UnitCreatureFamily(unit)
    elseif item == 'questinfo' then
        return self:GetQuestInfo(unit)
    elseif item == 'questcolorinfo' then
        return self:GetQuestColorInfo(unit)
    end
end

function EpicPlates:UpdateTimerFontSize()
    for _, namePlate in pairs(C_NamePlate.GetNamePlates()) do
        local unitFrame = namePlate.UnitFrame

        if unitFrame and unitFrame.buffIcons then
            for _, icon in ipairs(unitFrame.buffIcons) do
                icon.timer:SetFont(LSM:Fetch("font", self.db.profile.timerFont), self.db.profile.timerFontSize, "OUTLINE")
            end
        end

        if unitFrame and unitFrame.debuffIcons then
            for _, icon in ipairs(unitFrame.debuffIcons) do
                icon.timer:SetFont(LSM:Fetch("font", self.db.profile.timerFont), self.db.profile.timerFontSize, "OUTLINE")
            end
        end
    end
end

function EpicPlates:UpdateIconPositions()
    for _, namePlate in pairs(C_NamePlate.GetNamePlates()) do
        local UnitFrame = namePlate.UnitFrame
        if UnitFrame and UnitFrame.buffIcons and UnitFrame.debuffIcons then
            local iconXOffset = self.db.profile.iconXOffset or 0
            local iconYOffset = self.db.profile.iconYOffset or 0

            -- Adjust Buff Icons
            for i = 1, #UnitFrame.buffIcons do
                local icon = UnitFrame.buffIcons[i].icon
                local timer = UnitFrame.buffIcons[i].timer

                local availableWidth = UnitFrame:GetWidth()
                local maxIconsPerRow = math.floor((availableWidth + 2) / (ICON_SIZE + 2))

                local row = math.floor((i - 1) / maxIconsPerRow)
                local col = (i - 1) % maxIconsPerRow

                local xPos = col * (ICON_SIZE + 2) + iconXOffset
                local yPos = BUFF_ICON_OFFSET_Y + row * (ICON_SIZE + LINE_SPACING_Y) + iconYOffset

                icon:SetPoint("BOTTOMLEFT", UnitFrame, "TOPLEFT", xPos, yPos)
                icon:Show()
              
                timer:ClearAllPoints()
                if self.db.profile.timerPosition == "MIDDLE" then
                    timer:SetPoint("CENTER", icon, "CENTER", 0, 0)
                else
                    timer:SetPoint("TOP", icon, "BOTTOM", 0, -2)
                end
              
                local font, size, flags = timer:GetFont()
                timer:SetFont(font, size, flags)
                timer:Show()
            end

            -- Adjust Debuff Icons (same logic as above)
            for i = 1, #UnitFrame.debuffIcons do
                local icon = UnitFrame.debuffIcons[i].icon
                local timer = UnitFrame.debuffIcons[i].timer

                local availableWidth = UnitFrame:GetWidth()
                local maxIconsPerRow = math.floor((availableWidth + 2) / (ICON_SIZE + 2))

                local row = math.floor((i - 1) / maxIconsPerRow)
                local col = (i - 1) % maxIconsPerRow

                local xPos = col * (ICON_SIZE + 2) + iconXOffset
                local yPos = DEBUFF_ICON_OFFSET_Y + row * (ICON_SIZE + LINE_SPACING_Y) + iconYOffset

                icon:SetPoint("BOTTOMLEFT", UnitFrame, "TOPLEFT", xPos, yPos)
                icon:Show()

                timer:ClearAllPoints()
                if self.db.profile.timerPosition == "MIDDLE" then
                    timer:SetPoint("CENTER", icon, "CENTER", 0, 0)
                else
                    timer:SetPoint("TOP", icon, "BOTTOM", 0, -2)
                end

                local font, size, flags = timer:GetFont()
                timer:SetFont(font, size, flags)
                timer:Show()
            end
        end
    end
end

function EpicPlates:PromptReloadUI()
    StaticPopupDialogs["EPICPLATES_RELOADUI"] = {
        text = "|cFFFF0000You have changed the icon offsets.|r\n\n|cFFFFFF00These changes require a UI reload to take effect.|r\n\n|cFF00FF00Would you like to reload the UI now?|r",
        button1 = "|cFF00FF00Reload UI|r",
        button2 = "|cFFFF0000Cancel|r",
        OnAccept = function()
            ReloadUI()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    StaticPopup_Show("EPICPLATES_RELOADUI")
end

function EpicPlates:UpdateIconSize()
    local iconSize = self.db.profile.iconSize
    local timerFontSize = self.db.profile.timerFontSize
    local timerFont = LSM:Fetch("font", self.db.profile.timerFont)  
    local timerFontColor = self.db.profile.timerFontColor or {1, 1, 1} 
    local timerPosition = self.db.profile.timerPosition  -- Get the timer position

    for _, namePlate in pairs(C_NamePlate.GetNamePlates()) do
        local UnitFrame = namePlate.UnitFrame
        if UnitFrame and UnitFrame.buffIcons and UnitFrame.debuffIcons then
            for i = 1, #UnitFrame.buffIcons do
                local icon = UnitFrame.buffIcons[i].icon
                local timer = UnitFrame.buffIcons[i].timer

                icon:SetSize(iconSize, iconSize)
                timer:SetFont(timerFont, timerFontSize, "OUTLINE")
                timer:SetTextColor(unpack(timerFontColor))
                timer:ClearAllPoints()
                if timerPosition == "MIDDLE" then
                    timer:SetPoint("CENTER", icon, "CENTER", 0, 0)
                else
                    timer:SetPoint("TOP", icon, "BOTTOM", 0, -2)
                end
            end

            for i = 1, #UnitFrame.debuffIcons do
                local icon = UnitFrame.debuffIcons[i].icon
                local timer = UnitFrame.debuffIcons[i].timer

                icon:SetSize(iconSize, iconSize)
                timer:SetFont(timerFont, timerFontSize, "OUTLINE")
                timer:SetTextColor(unpack(timerFontColor))
                timer:ClearAllPoints()
                if timerPosition == "MIDDLE" then
                    timer:SetPoint("CENTER", icon, "CENTER", 0, 0)
                else
                    timer:SetPoint("TOP", icon, "BOTTOM", 0, -2)
                end
            end
        end
    end
end

-- Setup options after ensuring the options table is defined
function EpicPlates:SetupOptions()
    if not options then
        return
    end

    AceConfig:RegisterOptionsTable("EpicPlates", options)
    self.optionsFrame = AceConfigDialog:AddToBlizOptions("EpicPlates", "EpicPlates")

    self.db.RegisterCallback(self, "OnProfileChanged", "UpdateIconSize")
    self.db.RegisterCallback(self, "OnProfileCopied", "UpdateIconSize")
    self.db.RegisterCallback(self, "OnProfileReset", "UpdateIconSize")
end

function EpicPlates:NiceNameplateFrames_Update(unit)
    if not UnitIsUnit('player', unit) then
        local NamePlate = GetNamePlateForUnit(unit)
        if not NamePlate then return end
        local UnitFrame = NamePlate.UnitFrame
        if not UnitFrame then return end

        if not UnitFrame.buffIcons or not UnitFrame.debuffIcons then
            self:CreateAuraIcons(UnitFrame)
        end

        local texture = LSM:Fetch("statusbar", self.db.profile.healthBarTexture)
        UnitFrame.healthBar:SetStatusBarTexture(texture)

        local healthBar = UnitFrame.healthBar
        local NiceNameplateInfo = UnitFrame.NiceNameplateInfo
        local classificationIndicator = UnitFrame.ClassificationFrame and UnitFrame.ClassificationFrame.classificationIndicator

        local isFriend = UnitIsFriend('player', unit)
        local isPlayer = UnitIsPlayer(unit)
        local isTarget = UnitIsUnit('target', unit)
        local isCombat = UnitThreatSituation('player', unit)
        local classification = UnitClassification(unit)
        local isBoss = (classification == 'elite' or classification == 'worldboss' or classification == 'rareelite')

        UnitFrame:SetAlpha((isTarget and 1) or NAMEPLATE_ALPHA)

        if healthBar and healthBar.border then
            healthBar.border:SetScale((isTarget and 1.2) or 1)
            healthBar:SetShown(isCombat or not (isFriend or not isTarget) or (isPlayer and isTarget) or (isPlayer and not isFriend))
        end

        if classificationIndicator then
            classificationIndicator:SetShown(isCombat and isBoss or (isBoss and not (isFriend or not isTarget)))
        end

        if NiceNameplateInfo then
            NiceNameplateInfo:SetShown(UnitFrame.name:GetText() and UnitFrame.name:IsVisible() and not healthBar:IsVisible())
        end

        self:UpdateAuras(unit)
    end
end

function EpicPlates:NiceNameplateInfo_Create(frame)
    local NamePlate = frame
    local UnitFrame = NamePlate and NamePlate.UnitFrame

    if not UnitFrame then return end

    if UnitFrame and not UnitFrame.NiceNameplateInfo then
        UnitFrame.NiceNameplateInfo = UnitFrame:CreateFontString(nil, 'OVERLAY')
        UnitFrame.NiceNameplateInfo:SetFontObject(SystemFont_NamePlate)
        UnitFrame.NiceNameplateInfo:SetPoint(INFO_POINT, UnitFrame.name, INFO_RELATIVE_POINT, INFO_X, INFO_Y)
        UnitFrame.NiceNameplateInfo:Hide()
    end

    self:CreateAuraIcons(UnitFrame)
end

function EpicPlates:NiceNameplateInfo_Update(unit)
    local NamePlate = GetNamePlateForUnit(unit)
    local UnitFrame = NamePlate and NamePlate.UnitFrame

    if not UnitFrame then return end

    if not UnitFrame.buffIcons or not UnitFrame.debuffIcons then
        self:CreateAuraIcons(UnitFrame)
    end

    local UnitName = UnitFrame.name
    local NiceNameplateInfo = UnitFrame.NiceNameplateInfo

    local isFriend = UnitIsFriend('player', unit)
    local isPlayer = UnitIsPlayer(unit)
    local isEnemy = UnitIsEnemy('player', unit) or UnitCanAttack('player', unit)
    local isNPC = IsNPC(unit)
    if NiceNameplateInfo then
        if isPlayer and not isEnemy then
            local classColor = self:MakeInfoString(unit, 'classcolor')
            NiceNameplateInfo:SetText(self:MakeInfoString(unit, 'guild'))
            UnitName:SetTextColor(classColor.r, classColor.g, classColor.b)
            UnitName:SetText(self:MakeInfoString(unit, 'fullname'))
        elseif isPlayer and isEnemy then
            NiceNameplateInfo:SetText(self:MakeInfoString(unit, 'guild'))
            UnitName:SetText(self:MakeInfoString(unit, 'fullname'))
        elseif isEnemy and not self:MakeInfoString(unit, 'questinfo') then
            local levelColor = self:MakeInfoString(unit, 'levelcolor') or {r = 1, g = 1, b = 1}
            local InfoString = format('%s, '..LEVEL_GAINED:gsub('%%d', '|cFF%%s%%s|r'), self:MakeInfoString(unit, 'creaturetype') or ENEMY, RGBToHex(levelColor.r, levelColor.g, levelColor.b), self:MakeInfoString(unit, 'level'))
            NiceNameplateInfo:SetText(InfoString)
        elseif isNPC and not self:MakeInfoString(unit, 'questinfo') then
            NiceNameplateInfo:SetText(self:MakeInfoString(unit, 'profession'))
        elseif self:MakeInfoString(unit, 'questinfo') then
            NiceNameplateInfo:SetText(self:MakeInfoString(unit, 'questcolorinfo'))
        else
            NiceNameplateInfo:SetText(nil)
        end
    end

    self:UpdateAuras(unit)
end

function EpicPlates:NiceNameplateInfo_Delete(unit)
    local NamePlate = GetNamePlateForUnit(unit)
    local UnitFrame = NamePlate and NamePlate.UnitFrame
    local NiceNameplateInfo = UnitFrame and UnitFrame.NiceNameplateInfo

    if NiceNameplateInfo then
        NiceNameplateInfo:SetText(nil)
        NiceNameplateInfo:Hide()
    end
end

function EpicPlates:ApplyHealthBarTexture(texture)
    for _, nameplate in pairs(C_NamePlate.GetNamePlates()) do
        nameplate.UnitFrame.healthBar:SetStatusBarTexture(texture)
    end
end

local function UpdateNameplateHealthBar(nameplate)
    local texture = LSM:Fetch("statusbar", EpicPlates.db.profile.healthBarTexture)
    nameplate.healthBar:SetStatusBarTexture(texture)
end

local function ApplyTextureToAllNameplates()
    local texture = LSM:Fetch("statusbar", EpicPlates.db.profile.healthBarTexture)
    for _, nameplate in pairs(C_NamePlate.GetNamePlates()) do
        nameplate.UnitFrame.healthBar:SetStatusBarTexture(texture)
    end
end

function EpicPlates:CreateAuraIcons(UnitFrame)
    if not UnitFrame then return end

    UnitFrame.buffIcons = {}
    UnitFrame.debuffIcons = {}

    local iconSize = self.db.profile.iconSize
    local rowSpacing = 14  -- Space between rows

    local iconXOffset = self.db.profile.iconXOffset or 0
    local iconYOffset = self.db.profile.iconYOffset or 0

    local buffIconPos = self.db.profile.buffIconPositions or { y = 0, x = 0 }
    local debuffIconPos = self.db.profile.debuffIconPositions or { y = 0, x = 0 }

    -- Create Buff Icons
    for i = 1, MAX_BUFFS do
        local icon = UnitFrame:CreateTexture(nil, "OVERLAY")
        icon:SetSize(iconSize, iconSize)

        local availableWidth = UnitFrame:GetWidth()
        local maxIconsPerRow = math.floor((availableWidth + 2) / (iconSize + 2))

        local row = math.floor((i - 1) / maxIconsPerRow)
        local col = (i - 1) % maxIconsPerRow
        local xPos = col * (iconSize + 2) + iconXOffset + buffIconPos.x
        local yPos = buffIconPos.y + row * (iconSize + rowSpacing) + iconYOffset

        icon:SetPoint("BOTTOMLEFT", UnitFrame, "TOPLEFT", xPos, yPos)
        icon:Hide()

        local timer = UnitFrame:CreateFontString(nil, "OVERLAY")
        timer:SetFontObject(SystemFont_Outline_Small)
        timer:SetPoint("TOP", icon, "BOTTOM", 0, -2)
        timer:Hide()

        icon:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetUnitAura(UnitFrame.unit, i, "HELPFUL")
            GameTooltip:Show()
        end)
        icon:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
        end)

        UnitFrame.buffIcons[i] = {
            icon = icon,
            timer = timer
        }

        icon:Show()
    end

    -- Create Debuff Icons
    for i = 1, MAX_DEBUFFS do
        local icon = UnitFrame:CreateTexture(nil, "OVERLAY")
        icon:SetSize(iconSize, iconSize)

        local availableWidth = UnitFrame:GetWidth()
        local maxIconsPerRow = math.floor((availableWidth + 2) / (iconSize + 2))

        local row = math.floor((i - 1) / maxIconsPerRow)
        local col = (i - 1) % maxIconsPerRow
        local xPos = col * (iconSize + 2) + iconXOffset + debuffIconPos.x
        local yPos = debuffIconPos.y + row * (iconSize + rowSpacing) + iconYOffset

        icon:SetPoint("BOTTOMLEFT", UnitFrame, "TOPLEFT", xPos, yPos)
        icon:Hide()

        local timer = UnitFrame:CreateFontString(nil, "OVERLAY")
        timer:SetFontObject(SystemFont_Outline_Small)
        timer:SetPoint("TOP", icon, "BOTTOM", 0, -2)
        timer:Hide()

        icon:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetUnitAura(UnitFrame.unit, i, "HARMFUL")
            GameTooltip:Show()
        end)
        icon:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
        end)

        UnitFrame.debuffIcons[i] = {
            icon = icon,
            timer = timer
        }

        icon:Show()
    end

    self:UpdateIconSize()
end

local function IsAuraFiltered(spellName, spellID, casterName, remainingTime)
    local filters = EpicPlates.db.profile.auraFilters
    local alwaysShow = EpicPlates.db.profile.alwaysShow
    local thresholdMore = EpicPlates.db.profile.auraThresholdMore or 0
    local thresholdLess = EpicPlates.db.profile.auraThresholdLess or 60

    if spellID then
        local spellInfo = C_Spell.GetSpellInfo(spellID)
        if spellInfo and (alwaysShow.spellIDs[spellID] or alwaysShow.spellNames[spellInfo.name]) then
            return false
        end
    end

    if remainingTime and (remainingTime < thresholdMore or remainingTime > thresholdLess) then
        return true
    end

    if spellID then
        local spellInfo = C_Spell.GetSpellInfo(spellID)
        if spellInfo and filters.spellIDs[spellID] then
            return true
        end
    end

    if spellName then
        local spellInfo = C_Spell.GetSpellInfo(spellName)
        if spellInfo and filters.spellNames[spellInfo.name] then
            return true
        end
    end

    if casterName and filters.casterNames[casterName] then
        return true
    end

    return false
end

function EpicPlates:UpdateAuras(unit)
    local NamePlate = C_NamePlate.GetNamePlateForUnit(unit)
    local UnitFrame = NamePlate and NamePlate.UnitFrame

    if not UnitFrame then return end

    -- Hide buffs and debuffs if the unit is not the target or mouseover
    if not UnitIsUnit(unit, "target") and not UnitIsUnit(unit, "mouseover") then
        for i = 1, MAX_BUFFS do
            if UnitFrame.buffIcons[i] then
                UnitFrame.buffIcons[i].icon:Hide()
                UnitFrame.buffIcons[i].timer:Hide()
                if UnitFrame.buffIcons[i].stackCount then
                    UnitFrame.buffIcons[i].stackCount:Hide()
                end
                -- Ensure glow is removed, but only if updateFrame exists
                if UnitFrame.buffIcons[i].updateFrame then
                    ActionButton_HideOverlayGlow(UnitFrame.buffIcons[i].updateFrame)
                end
            end
        end
        for i = 1, MAX_DEBUFFS do
            if UnitFrame.debuffIcons[i] then
                UnitFrame.debuffIcons[i].icon:Hide()
                UnitFrame.debuffIcons[i].timer:Hide()
                if UnitFrame.debuffIcons[i].stackCount then
                    UnitFrame.debuffIcons[i].stackCount:Hide()
                end
                -- Ensure glow is removed, but only if updateFrame exists
                if UnitFrame.debuffIcons[i].updateFrame then
                    ActionButton_HideOverlayGlow(UnitFrame.debuffIcons[i].updateFrame)
                end
            end
        end
        return
    end

    local buffIndex = 1
    local debuffIndex = 1
    local currentTime = GetTime()

    -- Buffs processing
    for i = 1, 40 do
        local aura = C_UnitAuras.GetAuraDataByIndex(unit, i, AuraUtil.AuraFilters.Helpful)
        if not aura or buffIndex > MAX_BUFFS then break end

        -- Filtering logic to skip certain spells
        if not self:IsAuraFiltered(aura.name, aura.spellId, aura.sourceName, aura.expirationTime - currentTime) then
            local auraUpdateType = AuraUtil.ProcessAura(aura, false, false, true, true)
            if auraUpdateType == AuraUtil.AuraUpdateChangedType.Buff then
                self:HandleAuraDisplay(UnitFrame.buffIcons[buffIndex], aura, currentTime, UnitFrame)
                buffIndex = buffIndex + 1
            end
        end
    end

    -- Debuffs processing
    for i = 1, 40 do
        local aura = C_UnitAuras.GetAuraDataByIndex(unit, i, AuraUtil.AuraFilters.Harmful)
        if not aura or debuffIndex > MAX_DEBUFFS then break end

        -- Filtering logic to skip certain spells
        if not self:IsAuraFiltered(aura.name, aura.spellId, aura.sourceName, aura.expirationTime - currentTime) then
            local auraUpdateType = AuraUtil.ProcessAura(aura, false, true, false, false)
            if auraUpdateType == AuraUtil.AuraUpdateChangedType.Debuff then
                self:HandleAuraDisplay(UnitFrame.debuffIcons[debuffIndex], aura, currentTime, UnitFrame)
                debuffIndex = debuffIndex + 1
            end
        end
    end

    -- Hide extra icons and stack counts
    for i = buffIndex, MAX_BUFFS do
        if UnitFrame.buffIcons[i] then
            UnitFrame.buffIcons[i].icon:Hide()
            UnitFrame.buffIcons[i].timer:Hide()
            if UnitFrame.buffIcons[i].stackCount then
                UnitFrame.buffIcons[i].stackCount:Hide()
            end
            if UnitFrame.buffIcons[i].updateFrame then
                ActionButton_HideOverlayGlow(UnitFrame.buffIcons[i].updateFrame)
            end
        end
    end
    for i = debuffIndex, MAX_DEBUFFS do
        if UnitFrame.debuffIcons[i] then
            UnitFrame.debuffIcons[i].icon:Hide()
            UnitFrame.debuffIcons[i].timer:Hide()
            if UnitFrame.debuffIcons[i].stackCount then
                UnitFrame.debuffIcons[i].stackCount:Hide()
            end
            if UnitFrame.debuffIcons[i].updateFrame then
                ActionButton_HideOverlayGlow(UnitFrame.debuffIcons[i].updateFrame)
            end
        end
    end
end

function EpicPlates:IsAuraFiltered(spellName, spellID, casterName, remainingTime)
    local filters = self.db.profile.auraFilters
    local alwaysShow = self.db.profile.alwaysShow
    local thresholdMore = self.db.profile.auraThresholdMore or 0
    local thresholdLess = self.db.profile.auraThresholdLess or 60

    -- Check if the aura should always be shown
    if alwaysShow then
        if alwaysShow.spellIDs[spellID] or alwaysShow.spellNames[spellName] then
            return false
        end
    end

    -- Filter based on remaining time
    if remainingTime and (remainingTime < thresholdMore or remainingTime > thresholdLess) then
        return true
    end

    -- Filter based on spell ID
    if filters.spellIDs[spellID] then
        return true
    end

    -- Filter based on spell name
    if filters.spellNames[spellName] then
        return true
    end

    -- Filter based on caster name
    if filters.casterNames[casterName] then
        return true
    end

    -- If none of the filters apply, do not filter the aura
    return false
end

function EpicPlates:HandleAuraDisplay(iconTable, aura, currentTime, UnitFrame)
    local icon = iconTable.icon
    if not icon then
        icon = UnitFrame:CreateTexture(nil, "OVERLAY")
        icon:SetSize(self.db.profile.iconSize, self.db.profile.iconSize)
        iconTable.icon = icon
    end

    icon:SetTexture(aura.icon)
    icon:Show()

    local timer = iconTable.timer
    if not timer then
        timer = UnitFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        iconTable.timer = timer
    end

    timer:ClearAllPoints()
    timer:SetPoint("TOP", icon, "BOTTOM", 0, -2)
    timer:SetFont(LSM:Fetch("font", self.db.profile.timerFont), self.db.profile.timerFontSize, "OUTLINE")
    timer:Show()

    if not iconTable.updateFrame then
        iconTable.updateFrame = CreateFrame("Frame", nil, UnitFrame)
        iconTable.updateFrame:SetAllPoints(icon) 
    end

    iconTable.updateFrame:SetScript("OnUpdate", nil)

    iconTable.updateFrame:SetScript("OnUpdate", function(self, elapsed)
        local remainingTime = aura.expirationTime - GetTime()

        if remainingTime > 0 then
            timer:SetText(string.format("%.1f", remainingTime))

            if remainingTime > 5 then
                timer:SetTextColor(0, 1, 0)  
            else
                timer:SetTextColor(1, 0, 0)  
            end

            if EpicPlates.db.profile.iconGlowEnabled and remainingTime <= 5 and not iconTable.updateFrame.glowApplied and icon:IsShown() then
                ActionButton_ShowOverlayGlow(iconTable.updateFrame)
                iconTable.updateFrame.glowApplied = true
            end

            if remainingTime <= 1 and iconTable.updateFrame.glowApplied then
                ActionButton_HideOverlayGlow(iconTable.updateFrame)
                iconTable.updateFrame.glowApplied = false
            end
        else
            
            timer:Hide()
            icon:Hide()
            if iconTable.updateFrame.glowApplied then
                ActionButton_HideOverlayGlow(iconTable.updateFrame)
                iconTable.updateFrame.glowApplied = false
            end
           
            self:SetScript("OnUpdate", nil)
        end
    end)

    if not EpicPlates.db.profile.iconGlowEnabled and iconTable.updateFrame.glowApplied then
        ActionButton_HideOverlayGlow(iconTable.updateFrame)
        iconTable.updateFrame.glowApplied = false
    end

    icon:SetScript("OnEnter", function(self)
        if aura and aura.index and aura.index > 0 then
            local filter = aura.isHarmful and "HARMFUL" or "HELPFUL"
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetUnitAura(UnitFrame.unit, aura.index, filter)
            GameTooltip:Show()
        else
            GameTooltip:Hide()
        end
    end)

    icon:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
end

function EpicPlates:OnCombatLogEventUnfiltered()
    local timestamp, eventType, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags,
          destGUID, destName, destFlags, destRaidFlags, spellId, spellName, spellSchool, auraType = CombatLogGetCurrentEventInfo()

    if eventType == "SPELL_CAST_SUCCESS" then
        local unit = self:GetUnitByGUID(sourceGUID)

        if unit and UnitIsPlayer(unit) and UnitIsEnemy("player", unit) then
            local nameplate = C_NamePlate.GetNamePlateForUnit(unit)

            if nameplate and nameplate.UnitFrame then
                -- Handle Gladiator's Medallion and Adaptation
                if spellId == gladiatorMedallionSpellID or spellId == adaptationSpellID then
                    local cooldownDuration = trinketCooldown
                    local endTime = GetTime() + cooldownDuration
                    nameplate.UnitFrame.TrinketCooldownOverlay:SetCooldown(GetTime(), cooldownDuration)
                    UpdateCooldownText(nameplate.UnitFrame, nameplate.UnitFrame.TrinketCooldownText, endTime)
                elseif racialAbilities[spellId] then
                    -- Handle racials
                    local cooldownDuration = 90 
                    local endTime = GetTime() + cooldownDuration
                    nameplate.UnitFrame.RacialCooldownOverlay:SetCooldown(GetTime(), cooldownDuration)
                    UpdateCooldownText(nameplate.UnitFrame, nameplate.UnitFrame.RacialCooldownText, endTime)
                end
            end
        end
    end
end

function EpicPlates:GetUnitByGUID(guid)
    local knownUnits = {"target", "focus", "mouseover", "nameplate1", "nameplate2", "nameplate3", "nameplate4", "nameplate5"}

    for _, unit in ipairs(knownUnits) do
        if UnitGUID(unit) == guid then
            return unit
        end
    end
    return nil
end

function EpicPlates:HandleAuraApplied(unit, spellId, auraType)
    self:UpdateAuras(unit)
end

function EpicPlates:HandleAuraRemoved(unit, spellId, auraType)
    self:UpdateAuras(unit)
end

function EpicPlates:InitializeAlwaysShow()
   
    if not self.db.profile.alwaysShow then
        self.db.profile.alwaysShow = {
            spellIDs = {},
            spellNames = {}
        }
    end

    if _G.defaultSpells1 then
        for _, spellID in ipairs(_G.defaultSpells1) do
            self.db.profile.alwaysShow.spellIDs[spellID] = true
        end
    end

    if _G.defaultSpells2 then
        for _, spellID in ipairs(_G.defaultSpells2) do
            self.db.profile.alwaysShow.spellIDs[spellID] = true
        end
    end
end

-- Script to handle various events and apply updates accordingly
EpicPlates.Events = CreateFrame("Frame")
EpicPlates.Events:RegisterEvent("ADDON_LOADED")
EpicPlates.Events:RegisterEvent("PLAYER_LOGIN")

EpicPlates.Events:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" and (...) == "EpicPlates" then
        EpicPlates:OnEnable()
    elseif event == "PLAYER_LOGIN" then
        EpicPlates:OnEnable()
        EpicPlates.Events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
        EpicPlates.Events:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
        EpicPlates.Events:RegisterEvent("UNIT_AURA")
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        local unit = ...
        EpicPlates:NAME_PLATE_UNIT_ADDED(nil, unit)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        local unit = ...
        EpicPlates:NAME_PLATE_UNIT_REMOVED(nil, unit)
    elseif event == "UNIT_AURA" then
        local unit = ...
        if strmatch(unit, "nameplate%d+") then
            EpicPlates:UpdateAuras(unit)
        end
     end
end)
