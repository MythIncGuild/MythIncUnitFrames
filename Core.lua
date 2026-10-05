local ADDON_NAME, ns = ...

ns.addonName = ADDON_NAME
do
    local getMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    ns.version = (getMetadata and getMetadata(ADDON_NAME, "Version")) or "unknown"
end

local defaultPositions = {
    player = { point = "CENTER", relativePoint = "CENTER", x = -285, y = -150 },
    target = { point = "CENTER", relativePoint = "CENTER", x = 285, y = -150 },
    targettarget = { point = "CENTER", relativePoint = "CENTER", x = 285, y = -205 },
    focus = { point = "CENTER", relativePoint = "CENTER", x = 285, y = 20 },
    pet = { point = "CENTER", relativePoint = "CENTER", x = -285, y = -205 },
}

for i = 1, 4 do
    defaultPositions["party" .. i] = { point = "TOPLEFT", relativePoint = "TOPLEFT", x = 35, y = -220 - ((i - 1) * 78) }
end
for i = 1, 5 do
    defaultPositions["boss" .. i] = { point = "RIGHT", relativePoint = "RIGHT", x = -45, y = 140 - ((i - 1) * 78) }
end

defaultPositions.raid = { point = "TOPLEFT", relativePoint = "TOPLEFT", x = 35, y = -220 }

local defaultSizes = {
    player = { width = 250, height = 54 }, target = { width = 250, height = 54 },
    focus = { width = 220, height = 48 }, pet = { width = 180, height = 38 },
    targettarget = { width = 180, height = 38 }, party = { width = 210, height = 46 },
    boss = { width = 220, height = 46 }, raid = { width = 120, height = 30 },
}

local defaultEnabled = {
    player = true, target = true, focus = true, pet = true,
    targettarget = true, party = true, boss = true, raid = false,
}

local defaultGroupLayout = {
    raid = { orientation = "VERTICAL", legacy40 = false },
    party = { orientation = "VERTICAL", direction = "DOWN", spacing = 32, includePlayer = false },
    boss = { orientation = "VERTICAL", direction = "DOWN", spacing = 32 },
}

local defaultBarLayout, defaultAppearance, defaultAuraLayout = {}, {}, {}
local CASTBAR_TYPES = {player=true,target=true,focus=true,boss=true}
for unitType in pairs(defaultSizes) do
    defaultBarLayout[unitType] = { powerPercent = 22 }
    if CASTBAR_TYPES[unitType] then
        defaultBarLayout[unitType].castbar = {enabled=true,width=0,height=18,xOffset=0,yOffset=-3}
    end
    defaultAppearance[unitType] = {
        fontSize = unitType == "party" and 11 or 12,
        fontFace = "friz",
        nameXOffset = 6,
        nameYOffset = 0,
        healthXOffset = -6,
        healthYOffset = 0,
        texture = "flat",
        healthColor = "automatic",
        powerColor = "automatic",
        backgroundOpacity = 92,
        borderOpacity = 100,
        showName = true,
        showHealthText = true,
        showPortrait = false,
        portraitSide = "LEFT",
        portraitPercent = 22,
        roleIconXOffset = 3,
        roleIconYOffset = -3,
        roleIconSize = 14,
        showRaidMarker = true,
        raidMarkerSize = 20,
        raidMarkerXOffset = 0,
        raidMarkerYOffset = 2,
        statusIconSize = 18,
        statusIconXOffset = -4,
        statusIconYOffset = -3,
    }
    defaultAuraLayout[unitType] = {
        buffs = { enabled = true, showText = true, iconSize = 22, maxCount = 6, spacing = 2, anchor = "TOP", growth = "RIGHT", xOffset = 0, yOffset = 5 },
        debuffs = { enabled = true, showText = true, iconSize = 22, maxCount = 6, spacing = 2, anchor = "BOTTOM", growth = "RIGHT", xOffset = 0, yOffset = -26 },
        defensives = { enabled = true, showText = true, iconSize = 20, maxCount = 3, spacing = 2, anchor = "TOP", growth = "LEFT", xOffset = 0, yOffset = 26 },
    }
    if unitType == "raid" then
        defaultAuraLayout[unitType] = {
            debuffs = { enabled = true, showText = true, iconSize = 18, maxCount = 2, spacing = 2, anchor = "TOP", growth = "RIGHT", xOffset = 0, yOffset = 2 },
        }
    end
end

-- Only frame types with normal buffs expose the per-frame filtering switch.
for _, unitType in ipairs({ "player", "target", "focus", "targettarget", "party" }) do
    defaultAuraLayout[unitType].buffs.filteringEnabled = unitType ~= "target"
end

for _, unitType in ipairs({ "party", "raid" }) do
    local appearance = defaultAppearance[unitType]
    appearance.healerPowerBarsOnly = false
    appearance.showTankRoleIcon = unitType == "raid"
    appearance.showHealerRoleIcon = unitType == "raid"
    appearance.showDamageRoleIcon = unitType == "raid"
    appearance.showLeaderIcon = unitType == "party"
    -- Outside the left edge, clear of the role icon and frame text.
    appearance.leaderIconXOffset = -16
    appearance.leaderIconYOffset = -2
    appearance.leaderIconSize = 12
end

defaultAppearance.player.showRestingIcon = true
defaultAppearance.player.restingIconXOffset = 3
defaultAppearance.player.restingIconYOffset = -3
defaultAppearance.player.restingIconSize = 16

local function CopyTable(source)
    local result = {}
    for key, value in pairs(source or {}) do
        result[key] = type(value) == "table" and CopyTable(value) or value
    end
    return result
end

local function FillMissing(dest, defaults)
    if type(dest) ~= "table" then return CopyTable(defaults) end
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            dest[key] = FillMissing(dest[key], value)
        elseif dest[key] == nil or type(dest[key]) ~= type(value) then
            dest[key] = value
        end
    end
    return dest
end

local function NewDefaultProfile()
    return {
        positions = CopyTable(defaultPositions),
        sizes = CopyTable(defaultSizes),
        barLayout = CopyTable(defaultBarLayout),
        appearance = CopyTable(defaultAppearance),
        auraLayout = CopyTable(defaultAuraLayout),
        enabled = CopyTable(defaultEnabled),
        groupLayout = CopyTable(defaultGroupLayout),
        trackedBuffs = {},
        frameLocked = true,
        auraLocked = true,
    }
end

local function NormalizeProfile(profile)
    if type(profile) ~= "table" then profile = {} end
    profile.positions = FillMissing(profile.positions, defaultPositions)
    profile.sizes = FillMissing(profile.sizes, defaultSizes)
    profile.barLayout = FillMissing(profile.barLayout, defaultBarLayout)
    -- Convert role visibility before defaults fill the new per-role keys.
    if type(profile.appearance) ~= "table" then profile.appearance = {} end
    for _, unitType in ipairs({ "party", "raid" }) do
        local appearance = profile.appearance[unitType]
        if type(appearance) ~= "table" then appearance = {}; profile.appearance[unitType] = appearance end
        local legacy = appearance.showRoleIcon
        if unitType == "party" and type(profile.partyRoleIconsEnabled) == "boolean" then legacy = profile.partyRoleIconsEnabled end
        for _, key in ipairs({ "showTankRoleIcon", "showHealerRoleIcon", "showDamageRoleIcon" }) do
            if appearance[key] == nil and type(legacy) == "boolean" then appearance[key] = legacy end
        end
    end
    profile.partyRoleIconsEnabled = nil
    profile.appearance = FillMissing(profile.appearance, defaultAppearance)
    -- Temporary statuses are automatic; retire the short-lived opt-out keys.
    for unitType in pairs(defaultAppearance) do
        local appearance = profile.appearance[unitType]
        appearance.showReadyCheck = nil
        appearance.showIncomingSummon = nil
        appearance.showIncomingResurrection = nil
    end
    profile.auraLayout = FillMissing(profile.auraLayout, defaultAuraLayout)
    profile.enabled = FillMissing(profile.enabled, defaultEnabled)
    -- Normalize the branch's prototype before deep filling masks its old keys.
    local raid = type(profile.groupLayout) == "table" and profile.groupLayout.raid
    raid = type(raid) == "table" and raid or {}
    local orientation = raid.orientation or raid.memberOrientation
    local legacy40 = raid.legacy40 == true
    profile.groupLayout = FillMissing(profile.groupLayout, defaultGroupLayout)
    profile.groupLayout.raid = {
        orientation = orientation == "HORIZONTAL" and "HORIZONTAL" or "VERTICAL",
        legacy40 = legacy40,
    }
    if type(profile.trackedBuffs) ~= "table" then profile.trackedBuffs = {} end

    local legacyLocked = type(profile.locked) == "boolean" and profile.locked or true
    if type(profile.frameLocked) ~= "boolean" then profile.frameLocked = legacyLocked end
    if type(profile.auraLocked) ~= "boolean" then profile.auraLocked = legacyLocked end
    profile.locked = nil

    for _, appearance in pairs(profile.appearance) do
        if type(appearance) == "table" then
            appearance.showRoleIcon = nil
            appearance.nameVAlign = nil
            appearance.healthVAlign = nil
        end
    end

    return profile
end

local PROFILE_FIELDS = {
    "positions", "sizes", "barLayout", "appearance", "auraLayout",
    "enabled", "groupLayout", "trackedBuffs", "frameLocked", "auraLocked",
    "locked", "partyRoleIconsEnabled",
}

local function GetCharacterKey()
    local name, realm
    if UnitFullName then name, realm = UnitFullName("player") end
    name = name or (UnitName and UnitName("player")) or "Unknown"
    realm = realm or (GetRealmName and GetRealmName()) or "Unknown Realm"
    if realm == "" then realm = (GetRealmName and GetRealmName()) or "Unknown Realm" end
    return tostring(name) .. " - " .. tostring(realm)
end

local function MigrateLegacyDatabase(db)
    if type(db.profiles) == "table" and next(db.profiles) then return end

    local profile = {}
    local hadLegacy = false
    for _, field in ipairs(PROFILE_FIELDS) do
        if db[field] ~= nil then
            profile[field] = db[field]
            hadLegacy = true
        end
    end

    db.profiles = {}
    db.profiles.Default = NormalizeProfile(hadLegacy and profile or NewDefaultProfile())

    for _, field in ipairs(PROFILE_FIELDS) do db[field] = nil end
end

local initializedDatabase
local initializedCharacterKey
local function InitializeDatabase()
    if type(MythIncUnitFramesDB) ~= "table" then MythIncUnitFramesDB = {} end
    local db = MythIncUnitFramesDB

    MigrateLegacyDatabase(db)
    if type(db.profiles) ~= "table" then db.profiles = {} end
    if type(db.profiles.Default) ~= "table" then db.profiles.Default = NewDefaultProfile() end
    for name, profile in pairs(db.profiles) do db.profiles[name] = NormalizeProfile(profile) end

    if type(db.profileKeys) ~= "table" then db.profileKeys = {} end
    if type(db.seenBuffs) ~= "table" then db.seenBuffs = {} end

    local characterKey = GetCharacterKey()
    local active = db.profileKeys[characterKey]
    if type(active) ~= "string" or type(db.profiles[active]) ~= "table" then
        db.profileKeys[characterKey] = "Default"
    end

    db.version = 18
    initializedDatabase = db
    initializedCharacterKey = characterKey
end

local function ActiveProfile()
    -- Getters run for health/aura events on every unit. Normalize saved data at
    -- initialization, not on each read; explicit initialization still repairs it.
    if initializedDatabase == nil or initializedDatabase ~= MythIncUnitFramesDB then InitializeDatabase() end
    local db = MythIncUnitFramesDB
    local name = db.profileKeys[initializedCharacterKey] or "Default"
    local profile = db.profiles[name]
    if type(profile) ~= "table" then
        name = "Default"
        db.profileKeys[initializedCharacterKey] = name
        profile = db.profiles.Default
    end
    return profile, name
end

local function NormalizeProfileName(name)
    if type(name) ~= "string" then return nil end
    name = name:match("^%s*(.-)%s*$")
    if not name or name == "" then return nil end
    if #name > 40 then name = name:sub(1, 40) end
    return name
end

ns.defaultPositions = defaultPositions
ns.defaultSizes = defaultSizes
ns.defaultBarLayout = defaultBarLayout
ns.defaultAppearance = defaultAppearance
ns.defaultAuraLayout = defaultAuraLayout
ns.defaultEnabled = defaultEnabled
ns.defaultGroupLayout = defaultGroupLayout
ns.CopyTable = CopyTable
ns.InitializeDatabase = InitializeDatabase

-- Sharing works on detached data; these helpers never initialize or normalize
-- the live database as part of an import transaction.
function ns.GetProfileSharingDefaults() return NewDefaultProfile() end
function ns.NormalizeSharedProfile(candidate)
    local normalized=NormalizeProfile(candidate)
    for unitType in pairs(CASTBAR_TYPES) do
        normalized.barLayout[unitType].castbar=ns.NormalizeCastbarLayout(normalized.barLayout[unitType].castbar)
    end
    normalized.trackedBuffs=nil
    return normalized
end
function ns.ReplaceSharedProfile(name,expected,candidate)
    if ns.GetActiveProfileName()~=name or MythIncUnitFramesDB.profiles[name]~=expected then
        return false,"The current profile changed. Validate the import again."
    end
    candidate.trackedBuffs=expected.trackedBuffs
    MythIncUnitFramesDB.profiles[name]=candidate
    return true
end

function ns.GetCharacterProfileKey() InitializeDatabase(); return initializedCharacterKey end
function ns.GetActiveProfileName() local _, name = ActiveProfile(); return name end
function ns.GetProfileNames()
    InitializeDatabase()
    local names = {}
    for name in pairs(MythIncUnitFramesDB.profiles) do names[#names + 1] = name end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    return names
end
function ns.ProfileExists(name)
    InitializeDatabase(); name = NormalizeProfileName(name)
    return name ~= nil and type(MythIncUnitFramesDB.profiles[name]) == "table"
end
function ns.CreateProfile(name)
    InitializeDatabase(); name = NormalizeProfileName(name)
    if not name then return false, "Enter a profile name." end
    if MythIncUnitFramesDB.profiles[name] then return false, "A profile with that name already exists." end
    MythIncUnitFramesDB.profiles[name] = NewDefaultProfile()
    return true, name
end
function ns.CopyProfile(sourceName, newName)
    InitializeDatabase(); sourceName = NormalizeProfileName(sourceName); newName = NormalizeProfileName(newName)
    if not sourceName or not MythIncUnitFramesDB.profiles[sourceName] then return false, "Source profile was not found." end
    if not newName then return false, "Enter a profile name." end
    if MythIncUnitFramesDB.profiles[newName] then return false, "A profile with that name already exists." end
    MythIncUnitFramesDB.profiles[newName] = NormalizeProfile(CopyTable(MythIncUnitFramesDB.profiles[sourceName]))
    return true, newName
end
function ns.RenameProfile(oldName, newName)
    InitializeDatabase(); oldName = NormalizeProfileName(oldName); newName = NormalizeProfileName(newName)
    if not oldName or not MythIncUnitFramesDB.profiles[oldName] then return false, "Profile was not found." end
    if oldName == "Default" then return false, "The Default profile cannot be renamed." end
    if not newName then return false, "Enter a new profile name." end
    if MythIncUnitFramesDB.profiles[newName] then return false, "A profile with that name already exists." end

    MythIncUnitFramesDB.profiles[newName] = MythIncUnitFramesDB.profiles[oldName]
    MythIncUnitFramesDB.profiles[oldName] = nil
    for characterKey, profileName in pairs(MythIncUnitFramesDB.profileKeys) do
        if profileName == oldName then MythIncUnitFramesDB.profileKeys[characterKey] = newName end
    end
    return true, newName
end
function ns.DeleteProfile(name)
    InitializeDatabase(); name = NormalizeProfileName(name)
    if not name or not MythIncUnitFramesDB.profiles[name] then return false, "Profile was not found." end
    if name == "Default" then return false, "The Default profile cannot be deleted." end
    if name == ns.GetActiveProfileName() then return false, "Switch away from this profile before deleting it." end

    MythIncUnitFramesDB.profiles[name] = nil
    for characterKey, profileName in pairs(MythIncUnitFramesDB.profileKeys) do
        if profileName == name then MythIncUnitFramesDB.profileKeys[characterKey] = "Default" end
    end
    return true
end
function ns.SetActiveProfile(name)
    InitializeDatabase(); name = NormalizeProfileName(name)
    if not name or not MythIncUnitFramesDB.profiles[name] then return false, "Profile was not found." end
    MythIncUnitFramesDB.profileKeys[GetCharacterKey()] = name
    return true, name
end

function ns.GetPosition(unit) local profile = ActiveProfile(); return profile.positions[unit] or defaultPositions[unit] end
function ns.SavePosition(unit, point, relativePoint, x, y)
    local profile = ActiveProfile()
    profile.positions[unit] = {
        point = point, relativePoint = relativePoint,
        x = math.floor((x or 0) + 0.5), y = math.floor((y or 0) + 0.5),
    }
end

function ns.GetSize(unitType) local profile = ActiveProfile(); return profile.sizes[unitType] or defaultSizes[unitType] end
function ns.SaveSize(unitType, width, height)
    local profile = ActiveProfile()
    profile.sizes[unitType] = { width = math.floor(width + 0.5), height = math.floor(height + 0.5) }
end

function ns.GetPowerPercent(unitType) local profile = ActiveProfile(); return profile.barLayout[unitType].powerPercent end
local function CastbarNumber(value, fallback, minimum, maximum)
    value=tonumber(value)
    if not value or value~=value then return fallback end
    return math.floor(math.max(minimum,math.min(maximum,value))+0.5)
end

function ns.NormalizeCastbarLayout(values)
    values=type(values)=="table" and values or {}
    local width=tonumber(values.width)
    return {
        enabled=values.enabled~=false,
        -- Zero means inherited width; it is never used as a pixel dimension.
        width=width and width~=0 and CastbarNumber(width,0,100,600) or 0,
        height=CastbarNumber(values.height,18,18,40),
        xOffset=CastbarNumber(values.xOffset,0,-1000,1000),
        yOffset=CastbarNumber(values.yOffset,-3,-1000,1000),
    }
end

function ns.GetCastbarLayout(unitType)
    if not CASTBAR_TYPES[unitType] then return nil end
    return ns.NormalizeCastbarLayout(ActiveProfile().barLayout[unitType].castbar)
end

function ns.SaveCastbarLayout(unitType, values)
    if CASTBAR_TYPES[unitType] then
        ActiveProfile().barLayout[unitType].castbar=ns.NormalizeCastbarLayout(values)
    end
end

function ns.SavePowerPercent(unitType, percent)
    local profile = ActiveProfile(); profile.barLayout[unitType].powerPercent = math.floor(percent + 0.5)
end

function ns.GetAppearance(unitType) local profile = ActiveProfile(); return profile.appearance[unitType] end
function ns.SaveAppearance(unitType, values)
    local profile = ActiveProfile()
    local current = profile.appearance[unitType]
    for key, value in pairs(values) do current[key] = value end
end

function ns.IsFrameTypeEnabled(unitType) local profile = ActiveProfile(); return profile.enabled[unitType] ~= false end
function ns.SetFrameTypeEnabled(unitType, enabled)
    local profile = ActiveProfile(); profile.enabled[unitType] = enabled and true or false
end

function ns.GetGroupLayout(unitType) local profile = ActiveProfile(); return profile.groupLayout[unitType] end
function ns.SaveGroupLayout(unitType, values)
    local profile = ActiveProfile()
    local current = profile.groupLayout[unitType]
    if type(current) ~= "table" then
        local defaults = defaultGroupLayout[unitType]
        current = defaults and CopyTable(defaults) or {}
        profile.groupLayout[unitType] = current
    end
    for key, value in pairs(values) do current[key] = value end
end

function ns.GetAuraLayout(unitType, auraType)
    local profile = ActiveProfile()
    local frameAuras = profile.auraLayout[unitType]
    return frameAuras and frameAuras[auraType] or nil
end
function ns.SaveAuraLayout(unitType, auraType, values)
    local profile = ActiveProfile()
    if not profile.auraLayout[unitType] then profile.auraLayout[unitType] = {} end
    local current = profile.auraLayout[unitType][auraType]
    if type(current) ~= "table" then
        local defaults = defaultAuraLayout[unitType] and defaultAuraLayout[unitType][auraType]
        current = defaults and CopyTable(defaults) or {}
        profile.auraLayout[unitType][auraType] = current
    end
    for key, value in pairs(values) do current[key] = value end
end

function ns.GetTrackedBuffs() local profile = ActiveProfile(); return profile.trackedBuffs end
function ns.SetTrackedBuffs(values)
    local profile = ActiveProfile(); profile.trackedBuffs = type(values) == "table" and CopyTable(values) or {}
end
function ns.GetTrackedBuffSpellIDs()
    local profile = ActiveProfile()
    local ids = {}
    for spellID in pairs(profile.trackedBuffs) do
        local id = tonumber(spellID)
        if id then ids[id] = true end
    end
    return ids
end
function ns.GetSeenBuffs() InitializeDatabase(); return MythIncUnitFramesDB.seenBuffs end
function ns.RecordSeenBuff(spellID, name, icon)
    InitializeDatabase()
    local id = tonumber(spellID)
    if not id then return end
    local current = MythIncUnitFramesDB.seenBuffs[id]
    if type(current) ~= "table" then current = {}; MythIncUnitFramesDB.seenBuffs[id] = current end
    if name then current.name = name end
    if icon then current.icon = icon end
    current.lastSeen = time and time() or 0
end
function ns.ClearSeenBuffs() InitializeDatabase(); MythIncUnitFramesDB.seenBuffs = {} end

function ns.AreFrameMoversLocked() local profile = ActiveProfile(); return profile.frameLocked end
function ns.SetFrameMoversLockedState(locked) local profile = ActiveProfile(); profile.frameLocked = locked and true or false end
function ns.AreAuraMoversLocked() local profile = ActiveProfile(); return profile.auraLocked end
function ns.SetAuraMoversLockedState(locked) local profile = ActiveProfile(); profile.auraLocked = locked and true or false end
function ns.IsLocked() return ns.AreFrameMoversLocked() end
function ns.SetLocked(locked) ns.SetFrameMoversLockedState(locked) end

function ns.ResetAllSettings()
    InitializeDatabase()
    local name = ns.GetActiveProfileName()
    MythIncUnitFramesDB.profiles[name] = NewDefaultProfile()
    MythIncUnitFramesDB.seenBuffs = {}
end

function ns.ResetFrameType(unitType)
    local profile = ActiveProfile()
    if defaultSizes[unitType] then
        profile.sizes[unitType] = CopyTable(defaultSizes[unitType])
        profile.barLayout[unitType] = CopyTable(defaultBarLayout[unitType])
        profile.appearance[unitType] = CopyTable(defaultAppearance[unitType])
        profile.auraLayout[unitType] = CopyTable(defaultAuraLayout[unitType])
    end
end

function ns.ResetFrameAppearance(unitType)
    local profile = ActiveProfile()
    if defaultSizes[unitType] then
        profile.sizes[unitType] = CopyTable(defaultSizes[unitType])
        profile.barLayout[unitType] = CopyTable(defaultBarLayout[unitType])
        profile.appearance[unitType] = CopyTable(defaultAppearance[unitType])
        if defaultGroupLayout[unitType] then profile.groupLayout[unitType] = CopyTable(defaultGroupLayout[unitType]) end
    end
end

function ns.ResetAuraLayout(unitType, auraType)
    local profile = ActiveProfile()
    local defaults = defaultAuraLayout[unitType] and defaultAuraLayout[unitType][auraType]
    if defaults then profile.auraLayout[unitType][auraType] = CopyTable(defaults) end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(self, event, addon)
    if event ~= "ADDON_LOADED" or addon ~= ADDON_NAME then return end
    self:UnregisterEvent("ADDON_LOADED")
    InitializeDatabase()
    if ns.SpawnAllFrames then ns.SpawnAllFrames() end
    print("|cff66ccffMythInc Unit Frames|r " .. ns.version .. " loaded. Profile: " .. ns.GetActiveProfileName())
end)

local function PrintHelp()
    print("|cff66ccffMythInc Unit Frames|r " .. ns.version)
    print("/miuf or /miuf config - open configuration")
    print("/miuf unlock          - show unit-frame movers")
    print("/miuf lock            - hide unit-frame movers")
    print("/miuf auraunlock      - show aura movers")
    print("/miuf auralock        - hide aura movers")
    print("/miuf size <frame> <width> <height>")
    print("/miuf reset           - restore current profile defaults")
    print("/miuf version         - show addon version")
end

SLASH_MYTHINCUNITFRAMES1 = "/miuf"
SlashCmdList.MYTHINCUNITFRAMES = function(msg)
    InitializeDatabase()
    local input = (msg or ""):match("^%s*(.-)%s*$")
    local command, rest = input:match("^(%S+)%s*(.-)$")
    command = command and command:lower() or ""

    if command == "" or command == "config" or command == "options" then
        if ns.ToggleConfig then ns.ToggleConfig() else PrintHelp() end
        return
    end
    if command == "help" then PrintHelp(); return end
    if command == "version" then print("|cff66ccffMythInc Unit Frames|r version " .. ns.version); return end

    if command == "unlock" then
        if InCombatLockdown() then print("|cff66ccffMythInc Unit Frames|r cannot unlock frames during combat."); return end
        ns.SetFrameMoversLockedState(false)
        if ns.SetFrameMoversLocked then ns.SetFrameMoversLocked(false) end
        if ns.RefreshConfig then ns.RefreshConfig() end
        print("|cff66ccffMythInc Unit Frames|r frames unlocked.")
        return
    end
    if command == "lock" then
        ns.SetFrameMoversLockedState(true)
        if ns.SetFrameMoversLocked then ns.SetFrameMoversLocked(true) end
        if ns.ShowConfigForPendingFrameChanges then ns.ShowConfigForPendingFrameChanges() end
        if ns.RefreshConfig then ns.RefreshConfig() end
        print("|cff66ccffMythInc Unit Frames|r frames locked.")
        return
    end
    if command == "auraunlock" then
        if InCombatLockdown() then print("|cff66ccffMythInc Unit Frames|r cannot unlock aura movers during combat."); return end
        ns.SetAuraMoversLockedState(false)
        if ns.SetAuraMoversLocked then ns.SetAuraMoversLocked(false) end
        if ns.RefreshConfig then ns.RefreshConfig() end
        print("|cff66ccffMythInc Unit Frames|r aura movers unlocked.")
        return
    end
    if command == "auralock" then
        ns.SetAuraMoversLockedState(true)
        if ns.SetAuraMoversLocked then ns.SetAuraMoversLocked(true) end
        if ns.RefreshConfig then ns.RefreshConfig() end
        print("|cff66ccffMythInc Unit Frames|r aura movers locked.")
        return
    end
    if command == "size" then
        local unitType, widthText, heightText = rest:match("^(%S+)%s+(%d+)%s+(%d+)$")
        unitType = unitType and unitType:lower() or nil
        local width, height = tonumber(widthText), tonumber(heightText)
        if not unitType or not defaultSizes[unitType] then print("|cff66ccffMythInc Unit Frames|r unknown frame type."); return end
        if not width or not height or width < 100 or width > 600 or height < 24 or height > 150 then
            print("|cff66ccffMythInc Unit Frames|r size limits: width 100-600, height 24-150."); return
        end
        if InCombatLockdown() then print("|cff66ccffMythInc Unit Frames|r cannot resize during combat."); return end
        ns.SaveSize(unitType, width, height)
        if ns.ApplyFrameType then ns.ApplyFrameType(unitType) elseif ns.ApplySize then ns.ApplySize(unitType) end
        if ns.RefreshConfig then ns.RefreshConfig() end
        print(string.format("|cff66ccffMythInc Unit Frames|r %s size set to %dx%d.", unitType, width, height))
        return
    end
    if command == "reset" then
        if InCombatLockdown() then print("|cff66ccffMythInc Unit Frames|r cannot reset during combat."); return end
        ns.ResetAllSettings()
        if ns.ResetLayout then ns.ResetLayout() end
        if ns.RefreshConfig then ns.RefreshConfig() end
        print("|cff66ccffMythInc Unit Frames|r current profile reset to defaults.")
        return
    end
    PrintHelp()
end
