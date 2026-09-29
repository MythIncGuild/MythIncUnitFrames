local ADDON_NAME, ns = ...

if not ns.UnitFramesLoaded then return end

-- WoW 12.1 aura data becomes secret in restricted combat contexts. MIUF never
-- enumerates UnitAura data here; AuraContainer owns filtering and assignment.
local FLAT = "Interface\\Buttons\\WHITE8x8"
local FONT = "Fonts\\FRIZQT__.TTF"
local AURA_LABELS = { buffs = "Buffs", debuffs = "Debuffs", defensives = "Defensives" }
local AURA_TYPES = {
    buffs = { groups = { { key = "buffs", filter = "HELPFUL|PLAYER" } } },
    debuffs = { groups = { { key = "debuffs", filter = "HARMFUL" } } },
    defensives = { groups = {
        { key = "defensivesBig", filter = "HELPFUL|BIG_DEFENSIVE" },
        { key = "defensivesExternal", filter = "HELPFUL|EXTERNAL_DEFENSIVE" },
    } },
}
local AURA_UNIT_TYPES = { player = true, target = true, focus = true, party = true, targettarget = true, raid = true }
local DISPEL_HIGHLIGHT_TYPES = { player = true, party = true, focus = true, raid = true }

local availabilityDeferred = CreateFrame("Frame")
local pendingAvailability = {}
local StyleAuraRegions
local moverPreviewUnit
local moverPreviewAuras, moverPreviewHosts = {}, {}

local function RetryAuraStyle(data)
    if not data.stylePending or InCombatLockdown() then return end
    data.stylePending = nil
    for _, regions in ipairs(data.styleRegions) do
        if regions.stylePending and not StyleAuraRegions(regions, data.style) then data.stylePending = true end
    end
end

local function IsAuraUnitAvailable(frame)
    if not ns.IsFrameTypeEnabled(frame.MIUF_UnitType) then return false end
    -- These checks prove disconnection/missing tokens only. Neither healing
    -- range nor world visibility reliably describes access to cached auras;
    -- leave connected, existing distant units to Blizzard's aura updates.
    if frame.MIUF_AuraLeavingWorld then return false end
    local unit = ns.GetFrameDisplayUnit(frame)
    if not unit then return false end
    local exists = UnitExists(unit)
    if not canaccessvalue(exists) or not exists then return false end
    local connected = UnitIsConnected(unit)
    return canaccessvalue(connected) and connected == true
end

local function IsAuraDisplayAvailable(frame, auraType, available)
    if not available then return false end
    if frame.MIUF_UnitType == "party" and auraType == "defensives" then
        -- Explicit display policy for nonvisible Party members, not a test
        -- of aura validity or healing range. Never branch on secret results.
        local visible = UnitIsVisible(ns.GetFrameDisplayUnit(frame))
        return canaccessvalue(visible) and visible == true
    end
    return true
end

local function RefreshDisplay(frame, container, gate, displayAvailable, displayRecovering)
    if not gate then return end
    -- IsShown checks the gate's own state, including under a hidden owner.
    -- Stable UNIT_AURA events need neither visibility writes nor deferral.
    if not displayRecovering and gate:IsShown() == displayAvailable then return end
    if InCombatLockdown() and gate:IsProtected() then
        pendingAvailability[frame] = true
        availabilityDeferred:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    -- UpdateAllAuras is Blizzard's public full-rebuild path. Keep group
    -- configuration and update subscriptions intact, even while hidden.
    if displayRecovering then container:UpdateAllAuras() end
    if gate:IsShown() ~= displayAvailable then gate:SetShown(displayAvailable) end
end

local EMPTY_AURAS = {}
function ns.RefreshFrameAuraAvailability(frame, forceRefresh)
    local available = IsAuraUnitAvailable(frame)
    local recovering = available and (frame.MIUF_AurasAvailable ~= true or forceRefresh)
    frame.MIUF_AurasAvailable = available
    for auraType, data in pairs(frame.MIUF_Auras or EMPTY_AURAS) do
        RetryAuraStyle(data)
        local displayAvailable = IsAuraDisplayAvailable(frame, auraType, available)
        local displayRecovering = displayAvailable and (data.available ~= true or forceRefresh)
        data.available = displayAvailable
        RefreshDisplay(frame, data.container, data.displayGate, displayAvailable, displayRecovering)
    end
    RefreshDisplay(frame, frame.MIUF_DispelHighlight, frame.MIUF_DispelDisplayGate, available, recovering)
end

availabilityDeferred:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    local pending = pendingAvailability
    pendingAvailability = {}
    for frame in pairs(pending) do ns.RefreshFrameAuraAvailability(frame, true) end
end)

local FILTERED_DEBUFF_TYPES = { player = true, party = true, targettarget = true, raid = true }
local DEBUFF_EXCLUSIONS = {
    [26013] = true, [71041] = true, [206151] = true, [1313593] = true, -- Deserter / Challenger's Burden
    [57723] = true, [390435] = true, [57724] = true, [80354] = true, -- Exhaustion / Sated
    [95809] = true, [160455] = true, [264689] = true, -- Bloodlust exhaustion variants
    [124255] = true, -- Stagger
}

local function BuildCandidateFilters(auraType, unitType, layout)
    if auraType == "debuffs" and FILTERED_DEBUFF_TYPES[unitType] then
        local excluded = {}
        for spellID in pairs(DEBUFF_EXCLUSIONS) do excluded[spellID] = true end
        return { isFromPlayerOrPlayerPet = false, excludeSpellIDs = excluded }
    end
    if auraType ~= "buffs" then return {} end
    layout = layout or ns.GetAuraLayout(unitType, "buffs")
    if layout and layout.filteringEnabled == false then return {} end
    local includeSpellIDs = {}
    local tracked = ns.GetTrackedBuffs and ns.GetTrackedBuffs() or {}
    local count = 0
    for spellID in pairs(tracked) do
        local id = tonumber(spellID)
        if id then includeSpellIDs[id] = true; count = count + 1 end
    end
    if count == 0 then includeSpellIDs[0] = true end
    return { includeSpellIDs = includeSpellIDs }
end

local function ApplyBuffFiltering(frame, layout, refreshCandidates)
    local data = frame.MIUF_Auras and frame.MIUF_Auras.buffs
    if not data then return end
    layout = layout or ns.GetAuraLayout(frame.MIUF_UnitType, "buffs")
    local enabled = not layout or layout.filteringEnabled ~= false
    if data.buffFilteringEnabled == enabled and not refreshCandidates then return end
    -- Reconfigure the existing native group; keep its pool, unit and events.
    data.container:SetAuraGroupFilterString("buffs", enabled and "HELPFUL|PLAYER" or "HELPFUL")
    data.container:SetAuraGroupCandidateFilters("buffs", BuildCandidateFilters("buffs", frame.MIUF_UnitType, layout))
    data.buffFilteringEnabled = enabled
end

function ns.PreviewBuffFiltering(unitType, layout)
    if InCombatLockdown() then return end
    for _, frame in pairs(ns.frames or {}) do
        if frame.MIUF_UnitType == unitType then ApplyBuffFiltering(frame, layout) end
    end
end

local function RefreshTrackedBuffCandidates()
    -- Read the active saved list at execution time, never the staged list.
    -- Blizzard securely delegates this setter and schedules its own rebuild;
    -- it does not require changing protected visibility or unit attributes.
    for _, frame in pairs(ns.frames or {}) do
        ApplyBuffFiltering(frame, nil, true)
    end
end

hooksecurefunc(ns, "SetTrackedBuffs", RefreshTrackedBuffCandidates)
hooksecurefunc(ns, "SetActiveProfile", RefreshTrackedBuffCandidates)
hooksecurefunc(ns, "ResetAllSettings", RefreshTrackedBuffCandidates)

local function GetAnchor(layout)
    local anchor = layout.anchor == "BOTTOM" and "BOTTOM" or "TOP"
    local growth = layout.growth == "LEFT" and "LEFT" or "RIGHT"
    if anchor == "TOP" then
        if growth == "LEFT" then return "BOTTOMRIGHT", "TOPRIGHT", "TOPRIGHT", "LEFT", "DOWN" end
        return "BOTTOMLEFT", "TOPLEFT", "TOPLEFT", "RIGHT", "DOWN"
    end
    if growth == "LEFT" then return "TOPRIGHT", "BOTTOMRIGHT", "TOPRIGHT", "LEFT", "UP" end
    return "TOPLEFT", "BOTTOMLEFT", "TOPLEFT", "RIGHT", "UP"
end

local function SetFlowLayout(container, anchorPoint, growthX, growthY)
    local setAnchor = container.SetFlowLayoutAnchorPoint or container.SetAuraLayoutAnchorPoint
    if setAnchor then setAnchor(container, anchorPoint) end
    local setGrowth = container.SetFlowLayoutGrowthDirection or container.SetAuraLayoutGrowthDirection
    local directions = AnchorUtil and AnchorUtil.FlowDirection
    if setGrowth and directions then
        local x = growthX == "LEFT" and directions.Left or directions.Right
        local y = growthY == "UP" and directions.Up or directions.Down
        setGrowth(container, x, y)
    end
end

local function CanStyleAuraRegion(region)
    if not region.CanBeAccessedInContext then return true end
    local accessible = region:CanBeAccessedInContext()
    return canaccessvalue(accessible) and accessible == true
end

StyleAuraRegions = function(regions, layout)
    -- Native aura buttons restrict their descendants after initialization.
    -- Out of combat does not guarantee access (nor does IsForbidden alone).
    -- Keep the latest requested style and retry through existing unit events.
    if not CanStyleAuraRegion(regions.count) or not CanStyleAuraRegion(regions.cooldown) then
        regions.stylePending = true
        return false
    end
    local size = math.max(8, tonumber(layout.iconSize) or 22)
    regions.count:SetFont(FONT, math.max(8, math.floor(size * 0.45)), "OUTLINE")
    if regions.cooldown.SetHideCountdownNumbers then regions.cooldown:SetHideCountdownNumbers(layout.showText == false) end
    regions.stylePending = nil
    return true
end

local function InitializeAuraButton(button, layout)
    local size = math.max(8, tonumber(layout.iconSize) or 22)
    button:SetSize(size, size)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(button); icon:SetTexCoord(0.08, 0.92, 0.08, 0.92); button:SetIcon(icon)
    local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cooldown:SetAllPoints(button); cooldown:SetDrawEdge(false); cooldown:SetDrawBling(false)
    local count = button:CreateFontString(nil, "OVERLAY")
    count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
    local regions={count=count,cooldown=cooldown}
    StyleAuraRegions(regions,layout)
    button:SetDurationCooldown(cooldown)
    button:SetApplicationCount(count, {})
    return regions
end

local function PositionAuraAnchor(frame, auraType, previewLayout)
    local data = frame.MIUF_Auras and frame.MIUF_Auras[auraType]
    if not data or not data.anchor then return end
    local layout = previewLayout or ns.GetAuraLayout(frame.MIUF_UnitType, auraType)
    if not layout then return end
    local point, relativePoint = GetAnchor(layout)
    data.anchor:ClearAllPoints()
    data.anchor:SetPoint(point, frame, relativePoint, layout.xOffset or 0, layout.yOffset or 0)
end

local function ApplyContainerLayout(frame, auraType, previewLayout)
    local data = frame.MIUF_Auras and frame.MIUF_Auras[auraType]
    if not data then return end
    local layout = previewLayout or ns.GetAuraLayout(frame.MIUF_UnitType, auraType)
    if not layout then return end
    if auraType == "buffs" then ApplyBuffFiltering(frame, layout) end
    -- Every native allocation runs our initialization callback, including
    -- inactive preallocated buttons. These live descendants can later deny
    -- addon access; retain requested scalars and defer inaccessible styling.
    data.style.iconSize=layout.iconSize; data.style.showText=layout.showText
    data.stylePending = nil
    for _,regions in ipairs(data.styleRegions) do
        if not StyleAuraRegions(regions,data.style) then data.stylePending = true end
    end
    local size = math.max(8, tonumber(layout.iconSize) or 22)
    local spacing = math.max(0, tonumber(layout.spacing) or 2)
    local width = math.max(size, frame:GetWidth())
    local _, _, flowAnchor, growthX, growthY = GetAnchor(layout)
    data.anchor:SetSize(width, size)
    PositionAuraAnchor(frame, auraType, layout)
    SetFlowLayout(data.container, flowAnchor, growthX, growthY)
    for _, groupKey in ipairs(data.groupKeys or {}) do
        if data.container.SetAuraGroupLayout then
            data.container:SetAuraGroupLayout(groupKey, { elementWidth = size, elementHeight = size, elementSpacing = spacing, lineSpacing = spacing })
        end
        if data.container.SetAuraGroupMaxFrameCount then
            local defaultCount=frame.MIUF_UnitType == "raid" and ns.defaultAuraLayout.raid.debuffs.maxCount or 6
            data.container:SetAuraGroupMaxFrameCount(groupKey, math.max(1, tonumber(layout.maxCount) or defaultCount))
        end
        if data.container.SetAuraGroupEnabled then data.container:SetAuraGroupEnabled(groupKey, layout.enabled ~= false) end
    end
    if not data.container.SetAuraGroupEnabled then data.container:SetShown(layout.enabled ~= false) end
    ns.RefreshFrameAuraAvailability(frame)
end

local function SaveDraggedAuraPosition(frame, auraType, anchor)
    local layout = ns.ConfigSessionGetAura(frame.MIUF_UnitType, auraType)
    if not layout then return end
    local point, relativePoint = GetAnchor(layout)
    local x, y = 0, 0
    if point == "BOTTOMLEFT" and relativePoint == "TOPLEFT" then
        x = (anchor:GetLeft() or 0) - (frame:GetLeft() or 0); y = (anchor:GetBottom() or 0) - (frame:GetTop() or 0)
    elseif point == "BOTTOMRIGHT" and relativePoint == "TOPRIGHT" then
        x = (anchor:GetRight() or 0) - (frame:GetRight() or 0); y = (anchor:GetBottom() or 0) - (frame:GetTop() or 0)
    elseif point == "TOPLEFT" and relativePoint == "BOTTOMLEFT" then
        x = (anchor:GetLeft() or 0) - (frame:GetLeft() or 0); y = (anchor:GetTop() or 0) - (frame:GetBottom() or 0)
    elseif point == "TOPRIGHT" and relativePoint == "BOTTOMRIGHT" then
        x = (anchor:GetRight() or 0) - (frame:GetRight() or 0); y = (anchor:GetTop() or 0) - (frame:GetBottom() or 0)
    end
    local saveLayout = ns.ConfigSessionStageAura
    saveLayout(frame.MIUF_UnitType, auraType, {
        xOffset = x >= 0 and math.floor(x + 0.5) or math.ceil(x - 0.5),
        yOffset = y >= 0 and math.floor(y + 0.5) or math.ceil(y - 0.5),
    })
    if frame.MIUF_UnitType == "raid" then ns.PreviewRaidDebuffLayout(ns.ConfigSessionGetAura("raid", "debuffs"))
    else
        for _,owner in pairs(ns.frames) do
            if owner.MIUF_UnitType==frame.MIUF_UnitType then
                PositionAuraAnchor(owner,auraType,ns.ConfigSessionGetAura(frame.MIUF_UnitType,auraType))
            end
        end
    end
    if moverPreviewHosts[frame.MIUF_UnitType]==frame then
        PositionAuraAnchor(frame,auraType,ns.ConfigSessionGetAura(frame.MIUF_UnitType,auraType))
    end
    if ns.RefreshConfig then ns.RefreshConfig() end
end

local function CreateAuraMover(frame, auraType, anchor)
    anchor:SetMovable(true); anchor:SetClampedToScreen(true)
    -- Party and Raid movers inherit their owning cell's runtime visibility.
    local cellOwned = frame.MIUF_UnitType == "party" or frame.MIUF_UnitType == "raid"
    local mover = CreateFrame("Frame", nil, cellOwned and anchor or UIParent, "BackdropTemplate")
    mover:SetFrameStrata("DIALOG"); mover:SetAllPoints(anchor)
    mover:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
    mover:SetBackdropColor(0.35, 0.18, 0.65, 0.24); mover:SetBackdropBorderColor(0.75, 0.45, 1, 1)
    mover:EnableMouse(true); mover:RegisterForDrag("LeftButton")
    local label = mover:CreateFontString(nil, "OVERLAY")
    label:SetFont(FONT, 10, "OUTLINE"); label:SetPoint("CENTER")
    label:SetText((frame.MIUF_UnitType or frame.MIUF_Unit) .. " " .. AURA_LABELS[auraType])
    mover:SetScript("OnDragStart", function() if not InCombatLockdown() then mover.MIUF_RevertedDrag=nil; mover.MIUF_AuraDragging=true; anchor:StartMoving() end end)
    mover:SetScript("OnDragStop", function()
        mover.MIUF_AuraDragging=nil
        anchor:StopMovingOrSizing()
        if mover.MIUF_RevertedDrag then return end
        if not InCombatLockdown() then SaveDraggedAuraPosition(frame, auraType, anchor) end
    end)
    mover:SetScript("OnHide", function()
        if not mover.MIUF_AuraDragging then return end
        mover.MIUF_AuraDragging=nil; mover.MIUF_RevertedDrag=true
        anchor:StopMovingOrSizing()
        if not InCombatLockdown() then PositionAuraAnchor(frame,auraType,ns.ConfigSessionGetAura(frame.MIUF_UnitType,auraType)) end
    end)
    mover:Hide()
    frame.MIUF_AuraMovers = frame.MIUF_AuraMovers or {}; frame.MIUF_AuraMovers[auraType] = mover
end

local function CreateAuraContainer(frame, auraType)
    local typeInfo = AURA_TYPES[auraType]
    local layout = ns.GetAuraLayout(frame.MIUF_UnitType, auraType)
    if not typeInfo or not layout then return end
    local size = math.max(8, tonumber(layout.iconSize) or 22)
    local spacing = math.max(0, tonumber(layout.spacing) or 2)
    local maxCount = math.max(1, tonumber(layout.maxCount) or 6)
    local width = math.max(size, frame:GetWidth())
    local point, relativePoint, flowAnchor, growthX, growthY = GetAnchor(layout)
    local anchor = CreateFrame("Frame", nil, frame)
    anchor:SetSize(width, size); anchor:SetPoint(point, frame, relativePoint, layout.xOffset or 0, layout.yOffset or 0)
    -- Gate the live display only; the anchor and its mover remain available
    -- for intentional previews and retain their owning cell's visibility.
    local displayGate = CreateFrame("Frame", nil, anchor)
    displayGate:SetAllPoints(anchor); displayGate:SetShown(IsAuraDisplayAvailable(frame, auraType, IsAuraUnitAvailable(frame)))
    local ok, container = pcall(CreateFrame, "AuraContainer", nil, displayGate, "CustomAuraContainerTemplate")
    if not ok or not container then print("|cffff5555MIUF: unable to create aura container.|r"); anchor:Hide(); return end
    container:SetPoint(flowAnchor, anchor, flowAnchor, 0, 0)
    local groupKeys = {}
    local style={iconSize=layout.iconSize,showText=layout.showText}
    local styleRegions={}
    for _, group in ipairs(typeInfo.groups or {}) do
        local groupOptions = {
            maxFrameCount = maxCount,
            candidateFilters = BuildCandidateFilters(auraType, frame.MIUF_UnitType, layout),
            layout = { elementWidth = size, elementHeight = size, elementSpacing = spacing, lineSpacing = spacing },
            initializeFrame = function(button)
                styleRegions[#styleRegions+1]=InitializeAuraButton(button,style)
            end,
        }
        local filter = auraType == "buffs" and layout.filteringEnabled == false and "HELPFUL" or group.filter
        local added, addError = pcall(container.AddAuraGroup, container, group.key, filter, groupOptions)
        if not added then print("|cffff5555MIUF: " .. auraType .. " group failed: " .. tostring(addError) .. "|r"); anchor:Hide(); return end
        groupKeys[#groupKeys + 1] = group.key
    end
    SetFlowLayout(container, flowAnchor, growthX, growthY)
    local unitSet, unitError = pcall(container.SetUnit, container, ns.GetFrameDisplayUnit(frame))
    if not unitSet then print("|cffff5555MIUF: aura unit assignment failed: " .. tostring(unitError) .. "|r"); anchor:Hide(); return end
    frame.MIUF_Auras = frame.MIUF_Auras or {}
    frame.MIUF_Auras[auraType] = { container = container, anchor = anchor, displayGate = displayGate, groupKeys = groupKeys, style=style, styleRegions=styleRegions }
    if auraType == "buffs" then frame.MIUF_Auras[auraType].buffFilteringEnabled = layout.filteringEnabled ~= false end
    local previewAnchor = {}
    function previewAnchor:SetHeight(_) end
    function previewAnchor:ClearAllPoints() anchor:ClearAllPoints() end
    function previewAnchor:SetPoint(...) anchor:SetPoint(...) end
    container.MIUF_Anchor = previewAnchor
    if auraType == "buffs" then frame.PlayerBuffs = container
    elseif auraType == "debuffs" then frame.CombatDebuffs = container
    elseif auraType == "defensives" then frame.ExternalDefensives = container end
    CreateAuraMover(frame, auraType, anchor)
    ApplyContainerLayout(frame, auraType)
end

-- Highlight the full unit frame with the aura's dispel-type color.
-- AuraButton owns all color assignment, so the addon never reads the
-- protected dispel type itself.
local function CreateDispelHighlight(frame)
    if not frame
        or not DISPEL_HIGHLIGHT_TYPES[frame.MIUF_UnitType]
        or frame.MIUF_DispelHighlight
    then
        return
    end

    local displayGate = CreateFrame("Frame", nil, frame)
    displayGate:SetAllPoints(frame)
    displayGate:SetShown(IsAuraUnitAvailable(frame))

    local ok, container = pcall(
        CreateFrame,
        "AuraContainer",
        nil,
        displayGate,
        "CustomAuraContainerTemplate"
    )

    if not ok or not container then
        print("|cffff5555MIUF: unable to create dispel highlight.|r")
        return
    end

    container:SetAllPoints(frame)
    container:SetFrameLevel(frame:GetFrameLevel() + 4)

    local slotOptions = {
        initializeFrame = function(button)
            button:SetSize(1, 1)
            button:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
            button:SetMouseMotionEnabled(false)

            local preserve =
                Enum
                and Enum.CustomAuraButtonDispelTypeTextureStyle
                and Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset
                or 3

            local highlightLayer = CreateFrame("Frame", nil, button)
            highlightLayer:SetAllPoints(frame)
            highlightLayer:SetAlpha(0.40)

            local highlight = highlightLayer:CreateTexture(nil, "OVERLAY")
            highlight:SetColorTexture(1, 1, 1, 1)
            highlight:SetAllPoints(highlightLayer)

            button:AddDispelTypeTexture(highlight, {
                style = preserve,
                showWhenHarmful = true,
            })

            -- Share the aura button's visibility without inheriting the tint's alpha.
            local border = CreateFrame("Frame", nil, button, "BackdropTemplate")
            border:SetPoint("TOPLEFT", frame, "TOPLEFT", -2, 2)
            border:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 2, -2)
            border:SetBackdrop({ edgeFile = FLAT, edgeSize = 2 })
            border:SetBackdropBorderColor(1, 1, 0, 1)

            button.DispelHighlight = {
                full = highlight,
                layer = highlightLayer,
                border = border,
            }
        end,
    }

    local added, slotOrError = pcall(
        container.AddAuraSlot,
        container,
        "miufDispel",
        "HARMFUL|RAID",
        slotOptions
    )

    if not added then
        print(
            "|cffff5555MIUF: dispel highlight failed: "
                .. tostring(slotOrError)
                .. "|r"
        )
        container:Hide()
        return
    end

    local unitSet, unitError = pcall(
        container.SetUnit,
        container,
        ns.GetFrameDisplayUnit(frame)
    )

    if not unitSet then
        print(
            "|cffff5555MIUF: dispel highlight unit assignment failed: "
                .. tostring(unitError)
                .. "|r"
        )
        container:Hide()
        return
    end

    frame.MIUF_DispelHighlight = container
    frame.MIUF_DispelDisplayGate = displayGate
end

function ns.UpdateFrameAuraUnit(frame)
    local unit = ns.GetFrameDisplayUnit(frame)
    for _, data in pairs(frame.MIUF_Auras or {}) do
        data.container:SetUnit(unit)
    end
    if frame.MIUF_DispelHighlight then frame.MIUF_DispelHighlight:SetUnit(unit) end
    ns.RefreshFrameAuraAvailability(frame, true)
    if moverPreviewUnit==frame.MIUF_UnitType then ns.RefreshAuraMoverPreview() end
end

local function AttachFrameAuras(frame)
    if not frame or not AURA_UNIT_TYPES[frame.MIUF_UnitType] or frame.MIUF_AurasAttached then return end
    frame.MIUF_AurasAttached = true
    if frame.MIUF_UnitType ~= "raid" then CreateAuraContainer(frame, "buffs") end
    CreateAuraContainer(frame, "debuffs")
    if frame.MIUF_UnitType == "player" or frame.MIUF_UnitType == "party" then CreateAuraContainer(frame, "defensives") end
    CreateDispelHighlight(frame)
    -- The owner already routes connection, roster and display-unit changes.
    -- A separate UNIT_AURA listener continues receiving recovery updates when
    -- a live display is hidden. Never replace Blizzard's container scripts.
    local watcher = CreateFrame("Frame", nil, frame)
    ns.RegisterFrameUnitEvent(watcher, "UNIT_AURA", frame)
    if frame.MIUF_UnitType == "party" then
        -- Additional opportunities to observe client visibility changes.
        -- These events are not a guarantee of every visibility transition.
        for _, event in ipairs({ "UNIT_PHASE", "UNIT_FLAGS", "UNIT_MODEL_CHANGED", "UNIT_PORTRAIT_UPDATE" }) do
            ns.RegisterFrameUnitEvent(watcher, event, frame)
        end
    end
    watcher:RegisterEvent("PLAYER_LEAVING_WORLD")
    watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    watcher:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_LEAVING_WORLD" then frame.MIUF_AuraLeavingWorld = true
        elseif event == "PLAYER_ENTERING_WORLD" then frame.MIUF_AuraLeavingWorld = nil end
        ns.RefreshFrameAuraAvailability(frame, event == "PLAYER_ENTERING_WORLD")
    end)
    frame:HookScript("OnEvent", function(self, event)
        if event == "UNIT_CONNECTION" then ns.RefreshFrameAuraAvailability(self)
        elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_FOCUS_CHANGED"
            or event == "UNIT_TARGET" or event == "PLAYER_ENTERING_WORLD" then ns.UpdateFrameAuraUnit(self) end
    end)
    frame:HookScript("OnShow", function(self) ns.UpdateFrameAuraUnit(self) end)
    ns.RefreshFrameAuraAvailability(frame, true)
end

local function AttachAuras()
    if not ns.frames then return end
    for _, frame in pairs(ns.frames) do
        AttachFrameAuras(frame)
        if frame.MIUF_AurasAttached then ns.RefreshFrameAuraAvailability(frame) end
    end
    ns.SetAuraMoversLocked(ns.AreAuraMoversLocked())
end

-- Raid configuration previews use the same Blizzard layout path as saved state.
function ns.PreviewRaidDebuffLayout(layout)
    if InCombatLockdown() then return end
    for _, frame in pairs(ns.frames or {}) do
        if frame.MIUF_UnitType == "raid" then ApplyContainerLayout(frame, "debuffs", layout) end
    end
end

function ns.ApplyAuraPositions(unitType, auraType)
    if InCombatLockdown() or not ns.frames then return end
    for _, frame in pairs(ns.frames) do
        if frame.MIUF_UnitType == unitType then
            if auraType then ApplyContainerLayout(frame, auraType)
            else ApplyContainerLayout(frame, "buffs"); ApplyContainerLayout(frame, "debuffs"); ApplyContainerLayout(frame, "defensives") end
        end
    end
end

function ns.ResizeAuraContainers(frame, width)
    if not frame or not frame.MIUF_Auras then return end
    for auraType, data in pairs(frame.MIUF_Auras) do
        if data.anchor then data.anchor:SetWidth(width or frame:GetWidth()) end
        ApplyContainerLayout(frame, auraType)
    end
end

function ns.ResetAuraPositionsForFrame(frame)
    if not frame then return end
    PositionAuraAnchor(frame, "buffs"); PositionAuraAnchor(frame, "debuffs"); PositionAuraAnchor(frame, "defensives")
end

function ns.RefreshAuraMoverPreview()
    local selected = {}
    if moverPreviewUnit and not InCombatLockdown() then
        local enabled=ns.IsFrameTypeEnabled(moverPreviewUnit)
        if ns.ConfigSessionGetEnabled then enabled=ns.ConfigSessionGetEnabled(moverPreviewUnit) end
        for auraType in pairs(moverPreviewAuras) do
            local layout=ns.ConfigSessionGetAura(moverPreviewUnit,auraType)
            local chosen, chosenKey
            if not layout or layout.enabled==false or not enabled then
                moverPreviewAuras[auraType]=nil
            else
                for key,frame in pairs(ns.frames or {}) do
                    local mover=frame.MIUF_AuraMovers and frame.MIUF_AuraMovers[auraType]
                    if frame.MIUF_UnitType==moverPreviewUnit and mover
                        and ((moverPreviewUnit~="party" and moverPreviewUnit~="raid")
                            or (UnitExists(frame.MIUF_Unit) and frame:IsVisible())) then
                        local rank=frame==ns.partyAuraMoverOwner and "" or tostring(key)
                        if not chosenKey or rank<chosenKey then chosen,chosenKey=mover,rank end
                    end
                end
                if not chosen and (moverPreviewUnit=="party" or moverPreviewUnit=="raid") then
                    local host=ns.GetGroupStatusPreviewFrame and ns.GetGroupStatusPreviewFrame(moverPreviewUnit)
                    if host then
                        moverPreviewHosts[moverPreviewUnit]=host
                        host.MIUF_UnitType=moverPreviewUnit
                        host.MIUF_Auras=host.MIUF_Auras or {}
                        if not host.MIUF_Auras[auraType] then
                            -- Reuse the mover constructor on the existing ghost;
                            -- this creates no aura container, icons, or unit data.
                            local anchor=CreateFrame("Frame",nil,host)
                            host.MIUF_Auras[auraType]={anchor=anchor}
                            CreateAuraMover(host,auraType,anchor)
                        end
                        chosen=host.MIUF_AuraMovers[auraType]
                        if not chosen.MIUF_AuraDragging then
                            host.MIUF_Auras[auraType].anchor:SetSize(host:GetWidth(),math.max(8,tonumber(layout.iconSize) or 22))
                            PositionAuraAnchor(host,auraType,layout)
                        end
                    end
                end
                if chosen then selected[chosen]=true end
            end
        end
    end
    for _,frames in ipairs({ns.frames or {},moverPreviewHosts}) do
        for _,frame in pairs(frames) do
            for _,mover in pairs(frame.MIUF_AuraMovers or {}) do
                if not selected[mover] then mover:Hide() end
            end
        end
    end
    for mover in pairs(selected) do mover:Show() end
end

function ns.ClearAuraMoverPreview()
    moverPreviewUnit,moverPreviewAuras=nil,{}
    ns.RefreshAuraMoverPreview()
end

function ns.IsAuraMoverPreviewEnabled(unitType,auraType)
    return moverPreviewUnit==unitType and moverPreviewAuras[auraType]==true
end

-- Compatibility with existing refresh/lock callers; never globally show movers.
function ns.SetAuraMoversLocked(locked)
    ns.RefreshAuraMoverPreview()
    if ns.UpdateLockMoversButton then ns.UpdateLockMoversButton() end
end

function ns.PreviewAuraMover(unitType, auraType, enabled)
    if InCombatLockdown() then ns.ClearAuraMoverPreview(); return end
    if moverPreviewUnit~=unitType then ns.ClearAuraMoverPreview() end
    moverPreviewUnit=unitType
    moverPreviewAuras[auraType]=enabled and true or nil
    ns.RefreshAuraMoverPreview()
end

hooksecurefunc(ns,"SetActiveProfile",ns.ClearAuraMoverPreview)
hooksecurefunc(ns,"ResetAllSettings",ns.ClearAuraMoverPreview)

local deferred = CreateFrame("Frame")
deferred:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    AttachAuras()
end)

local originalSpawnAllFrames = ns.SpawnAllFrames
function ns.SpawnAllFrames(...)
    if originalSpawnAllFrames then originalSpawnAllFrames(...) end
    if InCombatLockdown() then deferred:RegisterEvent("PLAYER_REGEN_ENABLED") else AttachAuras() end
end

function ns.RefreshAuras()
    if InCombatLockdown() then deferred:RegisterEvent("PLAYER_REGEN_ENABLED") else AttachAuras() end
end

local groupMoverCombatWatcher = CreateFrame("Frame")
groupMoverCombatWatcher:RegisterEvent("PLAYER_REGEN_DISABLED")
groupMoverCombatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
groupMoverCombatWatcher:SetScript("OnEvent", function()
    if InCombatLockdown() then ns.ClearAuraMoverPreview() end
    for _, frame in pairs(ns.frames or {}) do
        if (frame.MIUF_UnitType == "party" or frame.MIUF_UnitType == "raid") and frame.MIUF_AuraMovers then
            for _, mover in pairs(frame.MIUF_AuraMovers) do mover:Hide() end
        end
    end
    if not InCombatLockdown() then
        if ns.ConfigSessionGetAura then ns.PreviewRaidDebuffLayout(ns.ConfigSessionGetAura("raid", "debuffs")) end
        for _, frame in pairs(ns.frames or {}) do
            for _, data in pairs(frame.MIUF_Auras or EMPTY_AURAS) do RetryAuraStyle(data) end
        end
        ns.SetAuraMoversLocked(ns.AreAuraMoversLocked())
    end
end)
