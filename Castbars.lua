local ADDON_NAME, ns = ...

local FLAT = "Interface\\Buttons\\WHITE8x8"
local FONT = "Fonts\\FRIZQT__.TTF"
local TERMINAL_HOLD = 0.5
local timeFormatter = C_StringUtil.CreateSecondsFormatter()
timeFormatter:SetDefaultAbbreviation(Enum.SecondsFormatterAbbreviation.OneLetter)
timeFormatter:SetMinInterval(Enum.SecondsFormatterInterval.Seconds)
timeFormatter:SetMillisecondsThreshold(60)

local CASTBAR_TYPES = {
    player = true,
    target = true,
    focus = true,
    boss = true,
}
local CONFIGURABLE_CASTBAR_TYPES = { player = true, target = true }

local function ClearSafeZone(bar)
    if not bar.SafeZone then return end
    bar.SafeZone:Hide()
    bar.SafeZone:SetWidth(0)
end

local function IsPositivePublicNumber(value)
    return (not canaccessvalue or canaccessvalue(value)) and type(value) == "number"
        and value > 0 and value < math.huge
end

local function UpdateSafeZone(frame)
    local bar = frame.Castbar
    if not bar or not bar.SafeZone then return end
    ClearSafeZone(bar)
    local state = bar.MIUF_CastState
    if not state.active or state.mode ~= "cast" or state.unit ~= "player"
        or ns.GetFrameDisplayUnit(frame) ~= "player" or not frame.CastbarHolder:IsVisible()
        or not GetNetStats or not UnitCastingDuration then return end
    local duration = UnitCastingDuration("player")
    if (canaccessvalue and not canaccessvalue(duration)) or not duration
        or not duration.GetTotalDuration then return end
    local total = duration:GetTotalDuration()
    local _, _, _, latency = GetNetStats()
    local width = bar:GetWidth()
    if not IsPositivePublicNumber(total) or not IsPositivePublicNumber(latency)
        or not IsPositivePublicNumber(width) then return end
    -- World latency is in milliseconds; duration objects report seconds.
    bar.SafeZone:SetWidth(width * math.min(1, (latency / 1000) / total))
    bar.SafeZone:Show()
end

local function HideStageSeparators(bar)
    for _, separator in ipairs(bar.StageSeparators) do
        separator.fraction = nil
        separator:Hide()
    end
end

local function CreateStageSeparator(bar)
    local separator = bar:CreateTexture(nil, "OVERLAY", nil, -1)
    separator:SetColorTexture(0.08, 0.08, 0.08, 0.7)
    separator:SetWidth(1)
    separator:Hide()
    bar.StageSeparators[#bar.StageSeparators + 1] = separator
    return separator
end

local function LayoutStageSeparators(bar)
    local width = bar:GetWidth()
    if (canaccessvalue and not canaccessvalue(width)) or width < 1 then
        for _, separator in ipairs(bar.StageSeparators) do separator:Hide() end
        return
    end
    for _, separator in ipairs(bar.StageSeparators) do
        local fraction = separator.fraction
        if fraction then
            local x = math.max(0.5, math.min(width - 0.5, width * fraction))
            separator:ClearAllPoints()
            separator:SetPoint("TOP", bar, "TOPLEFT", x, -1)
            separator:SetPoint("BOTTOM", bar, "BOTTOMLEFT", x, 1)
            separator:Show()
        end
    end
end

local function UpdateStageSeparators(frame)
    local bar = frame.Castbar
    HideStageSeparators(bar)
    local state = bar.MIUF_CastState
    if not state.active or state.mode ~= "empower" or not frame.CastbarHolder:IsVisible()
        or state.unit ~= ns.GetFrameDisplayUnit(frame) or not UnitEmpoweredStagePercentages then return end
    -- Retail returns non-secret, one-based per-stage fractions, including a
    -- final hold-at-max share. Match UnitEmpoweredChannelDuration(unit, true).
    local stages = UnitEmpoweredStagePercentages(state.unit, true)
    if (canaccessvalue and not canaccessvalue(stages)) or type(stages) ~= "table" then return end
    local total, count = 0, 0
    for i = 1, #stages do
        local fraction = stages[i]
        if (canaccessvalue and not canaccessvalue(fraction)) or type(fraction) ~= "number"
            or not (fraction >= 0 and fraction <= 1) then
            HideStageSeparators(bar)
            return
        end
        total = total + fraction
        -- The last share ends at the bar edge, not at an interior separator.
        if i < #stages and fraction > 0 and total > 0 and total < 1 then
            count = count + 1
            local separator = bar.StageSeparators[count] or CreateStageSeparator(bar)
            separator.fraction = total
        end
    end
    LayoutStageSeparators(bar)
end

local function SetInterruptibleVisual(bar, notInterruptible)
    if bar.Shield.SetAlphaFromBoolean then
        bar.Shield:SetAlphaFromBoolean(notInterruptible, 1, 0)
    elseif not canaccessvalue or canaccessvalue(notInterruptible) then
        bar.Shield:SetAlpha(notInterruptible and 1 or 0)
    end

    if not canaccessvalue or canaccessvalue(notInterruptible) then
        if notInterruptible then
            bar:SetStatusBarColor(0.45, 0.45, 0.45, 1)
        else
            bar:SetStatusBarColor(1.00, 0.82, 0.25, 1)
        end
    else
        bar:SetStatusBarColor(1.00, 0.82, 0.25, 1)
    end
end

local function ClearActiveVisuals(bar)
    ClearSafeZone(bar)
    HideStageSeparators(bar)
    bar.Time.binding:SetToDefaults()
    bar.Time.binding:SetEnabled(false)
    bar.Time:SetText("")
    bar.Shield:SetAlpha(0)
    bar.Spark:Hide()
end

local function ResetCastState(bar)
    local state = bar.MIUF_CastState
    state.generation = state.generation + 1
    state.active, state.terminal, state.castBarID, state.unit, state.mode = nil, nil, nil, nil, nil
end

-- Configuration presentation only; never populate MIUF_CastState for a preview.
local previewUnitType
local function RestorePreviewParent(frame)
    if not frame.MIUF_CastbarPreview then return end
    frame.MIUF_CastbarPreview = nil
    frame.CastbarHolder:SetParent(frame)
end

local function ShowCastbarPreview(frame)
    local bar, holder = frame.Castbar, frame.CastbarHolder
    if not bar or not holder or frame.MIUF_UnitType ~= previewUnitType
        or InCombatLockdown() or frame.MIUF_CastbarEnabled == false then return end
    if bar.MIUF_CastState.active or bar.MIUF_CastState.terminal then return end
    ClearActiveVisuals(bar)
    frame.MIUF_CastbarPreview = true
    -- Keep the real frame anchors/geometry, even when its unit does not exist.
    holder:SetParent(UIParent)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0.7)
    bar:SetStatusBarColor(1.00, 0.82, 0.25, 1)
    bar.Icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    bar.Text:SetText("Cast Bar Preview")
    bar.Time:SetText("1.5s")
    bar:Show()
    holder:Show()
end

local function ClearCastbar(frame)
    RestorePreviewParent(frame)
    local bar = frame.Castbar
    if bar then
        ResetCastState(bar)
        ClearActiveVisuals(bar)
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(0)
        bar.Text:SetText("")
        bar.Icon:SetTexture(nil)
    end
    if frame.CastbarHolder then frame.CastbarHolder:Hide() end
    ShowCastbarPreview(frame)
end

local function PublicCastID(value)
    if not canaccessvalue or canaccessvalue(value) then return value end
end

local function RefreshCastbar(frame)
    local holder = frame and frame.CastbarHolder
    local bar = frame and frame.Castbar
    local unit = ns.GetFrameDisplayUnit(frame)
    if not holder or not bar or frame.MIUF_CastbarEnabled == false or not unit or not UnitExists(unit) then
        if frame then ClearCastbar(frame) end
        return
    end

    local name, displayName, texture, _, _, _, _, notInterruptible, _, castBarID = UnitCastingInfo(unit)
    local duration, direction, mode

    if name then
        duration = UnitCastingDuration and UnitCastingDuration(unit)
        direction = Enum.StatusBarTimerDirection.ElapsedTime
        mode = "cast"
    else
        local isEmpowered
        name, displayName, texture, _, _, _, notInterruptible, _, isEmpowered, _, castBarID = UnitChannelInfo(unit)
        if name then
            if isEmpowered and UnitEmpoweredChannelDuration then
                duration = UnitEmpoweredChannelDuration(unit, true)
                direction = Enum.StatusBarTimerDirection.ElapsedTime
                mode = "empower"
            else
                duration = UnitChannelDuration and UnitChannelDuration(unit)
                direction = Enum.StatusBarTimerDirection.RemainingTime
                mode = "channel"
            end
        end
    end

    if not name or not duration then
        ClearCastbar(frame)
        return
    end

    RestorePreviewParent(frame)
    ResetCastState(bar)
    local state = bar.MIUF_CastState
    state.active, state.unit, state.castBarID = true, unit, PublicCastID(castBarID)
    state.mode = mode
    if displayName then
        bar.Text:SetText(displayName)
    else
        bar.Text:SetText(name)
    end

    bar:SetTimerDuration(duration, Enum.StatusBarInterpolation.Immediate, direction)
    bar.Icon:SetTexture(texture)
    local binding = bar.Time.binding
    binding:SetFontString(bar.Time)
    binding:SetFormatter(timeFormatter)
    binding:SetDuration(duration)
    binding:UpdateFontString()
    bar.Spark:Show()
    SetInterruptibleVisual(bar, notInterruptible)
    UpdateStageSeparators(frame)
    bar:Show()
    holder:Show()
    binding:SetEnabled(holder:IsVisible())
    UpdateSafeZone(frame)
end

ns.UpdateFrameCastbar = RefreshCastbar

function ns.ClearCastbarPreview()
    previewUnitType = nil
    for _, frame in pairs(ns.frames or {}) do
        if frame.MIUF_CastbarPreview then
            RestorePreviewParent(frame)
            ClearActiveVisuals(frame.Castbar)
            frame.Castbar.Text:SetText("")
            frame.Castbar.Icon:SetTexture(nil)
            frame.Castbar:SetValue(0)
            frame.CastbarHolder:Hide()
        end
    end
end

function ns.SetCastbarPreview(unitType)
    if InCombatLockdown() or not CONFIGURABLE_CASTBAR_TYPES[unitType] then ns.ClearCastbarPreview(); return end
    if previewUnitType ~= unitType then ns.ClearCastbarPreview() end
    previewUnitType = unitType
    for _, frame in pairs(ns.frames or {}) do ShowCastbarPreview(frame) end
end

local function ShowTerminal(frame, text)
    local bar = frame.Castbar
    local state = bar.MIUF_CastState
    state.generation = state.generation + 1
    state.active, state.terminal = nil, true
    local generation = state.generation
    ClearActiveVisuals(bar)
    -- Replace native timer progression with a static terminal bar. Never read
    -- or calculate with restricted progress/timestamps to freeze the display.
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    bar.Text:SetText(text)
    C_Timer.After(TERMINAL_HOLD, function()
        if state.generation == generation and state.terminal then ClearCastbar(frame) end
    end)
end

local START_EVENTS = {
    UNIT_SPELLCAST_START=true, UNIT_SPELLCAST_CHANNEL_START=true, UNIT_SPELLCAST_EMPOWER_START=true,
}
local STOP_EVENTS = {
    UNIT_SPELLCAST_STOP=true, UNIT_SPELLCAST_CHANNEL_STOP=true, UNIT_SPELLCAST_EMPOWER_STOP=true,
    UNIT_SPELLCAST_FAILED=true, UNIT_SPELLCAST_INTERRUPTED=true,
}

local function HandleCastEvent(frame, event, unit, _, _, arg4, arg5, arg6)
    if frame.MIUF_CastbarEnabled == false then ClearCastbar(frame); return end
    if not event:match("^UNIT_SPELLCAST_") then RefreshCastbar(frame); return end
    local displayUnit = ns.GetFrameDisplayUnit(frame)
    if unit ~= displayUnit then return end
    local state = frame.Castbar.MIUF_CastState
    if state.unit ~= unit or not UnitExists(unit) or START_EVENTS[event] then
        RefreshCastbar(frame)
        return
    end

    -- Retail UnitDocumentation.lua: payload positions include unit/GUID/spell.
    -- GUID and spell ID may be secret; only the public castBarID is compared.
    local castBarID, interruptedBy = arg4
    if event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        interruptedBy, castBarID = arg4, arg5
    elseif event == "UNIT_SPELLCAST_EMPOWER_STOP" then
        interruptedBy, castBarID = arg5, arg6
    end
    castBarID = PublicCastID(castBarID)
    if castBarID and state.castBarID and castBarID ~= state.castBarID then return end

    if STOP_EVENTS[event] then
        if (event == "UNIT_SPELLCAST_STOP" and state.mode ~= "cast")
            or (event == "UNIT_SPELLCAST_CHANNEL_STOP" and state.mode ~= "channel")
            or (event == "UNIT_SPELLCAST_EMPOWER_STOP" and state.mode ~= "empower") then return end
        local name, _, _, _, _, _, _, _, _, liveID = UnitCastingInfo(unit)
        if not name then name, _, _, _, _, _, _, _, _, _, liveID = UnitChannelInfo(unit) end
        liveID = PublicCastID(liveID)
        -- A newer cast can already be queryable before its START event arrives.
        -- Without IDs, resync live data instead of assigning failure to it.
        if name and (not castBarID or not liveID or liveID ~= castBarID) then
            RefreshCastbar(frame)
            return
        end
        if state.terminal then return end -- trailing STOP must not erase the hold
        if event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" or interruptedBy then
            if state.active and castBarID and castBarID == state.castBarID then
                ShowTerminal(frame, event == "UNIT_SPELLCAST_FAILED" and "Failed" or "Interrupted")
            else
                RefreshCastbar(frame)
            end
        else
            ClearCastbar(frame)
        end
    elseif not state.terminal then
        RefreshCastbar(frame)
    end
end

-- Configuration-only geometry. Never refresh cast state, visibility or bindings.
function ns.ApplyCastbarGeometry(frame, settings)
    if InCombatLockdown and InCombatLockdown() then return end
    local holder, bar = frame.CastbarHolder, frame.Castbar
    if not holder or not bar or not settings then return end
    local width, height, x, y = settings.width, settings.height, settings.xOffset, settings.yOffset
    if not CONFIGURABLE_CASTBAR_TYPES[frame.MIUF_UnitType] then
        -- Ignore legacy Focus/Boss profile geometry without deleting saved data.
        width, height, x, y = 0, 18, 0, -3
    end
    holder:ClearAllPoints()
    holder:SetHeight(height)
    holder:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", x, y)
    if width == 0 then
        holder:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", x, y)
    else
        holder:SetWidth(width)
    end
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", height + 1, -1)
    bar:SetPoint("BOTTOMRIGHT", -1, 1)
    bar.Icon:SetSize(height - 2, height - 2)
    bar.Time:SetHeight(height - 2)
    bar.Spark:SetHeight(height - 2)
end

function ns.ApplyFrameCastbarSettings(frame, settings)
    if InCombatLockdown() or not frame.Castbar or not settings then return end
    ns.ApplyCastbarGeometry(frame, settings)
    local wasEnabled = frame.MIUF_CastbarEnabled
    frame.MIUF_CastbarEnabled = settings.enabled ~= false
    if not frame.MIUF_CastbarEnabled then
        ClearCastbar(frame)
    elseif wasEnabled == false then
        RefreshCastbar(frame)
    end
end

function ns.ApplyCastbarLayout(unitType, settings)
    for _, frame in pairs(ns.frames or {}) do
        if frame.MIUF_UnitType == unitType then ns.ApplyFrameCastbarSettings(frame, settings) end
    end
end

local function CreateCastbar(frame)
    if not frame or frame.Castbar or not CASTBAR_TYPES[frame.MIUF_UnitType] then return end

    local holder = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    holder:SetHeight(18)
    holder:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -3)
    holder:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, -3)
    holder:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
    holder:SetBackdropColor(0.03, 0.03, 0.03, 0.95)
    holder:SetBackdropBorderColor(0.12, 0.12, 0.12, 1)
    holder:SetFrameLevel(frame:GetFrameLevel() + 6)
    holder:Hide()

    local bar = CreateFrame("StatusBar", nil, holder)
    bar.MIUF_CastState = {generation=0}
    bar:SetPoint("TOPLEFT", 19, -1)
    bar:SetPoint("BOTTOMRIGHT", -1, 1)
    bar:SetStatusBarTexture(ns.GetTexturePath and ns.GetTexturePath("smooth") or FLAT)
    bar:SetStatusBarColor(1.00, 0.82, 0.25, 1)
    bar.StageSeparators = {}
    -- Reserve the common case; grow once and reuse if Retail reports more.
    for i = 1, 4 do CreateStageSeparator(bar) end
    bar:SetScript("OnSizeChanged", LayoutStageSeparators)

    if frame.MIUF_UnitType == "player" then
        local safeZone = bar:CreateTexture(nil, "OVERLAY", nil, -2)
        safeZone:SetColorTexture(0.85, 0.70, 1.00, 0.45)
        safeZone:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
        safeZone:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
        bar.SafeZone = safeZone
        ClearSafeZone(bar)
        bar:SetScript("OnSizeChanged", function(self)
            LayoutStageSeparators(self)
            UpdateSafeZone(frame)
        end)
    end

    local background = bar:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(bar)
    background:SetColorTexture(0.08, 0.08, 0.08, 1)

    local icon = holder:CreateTexture(nil, "ARTWORK")
    icon:SetSize(16, 16)
    icon:SetPoint("LEFT", holder, "LEFT", 1, 0)
    bar.Icon = icon

    local shield = bar:CreateTexture(nil, "OVERLAY")
    shield:SetAtlas("ui-castingbar-shield", false)
    shield:SetVertexColor(1, 0, 0, 1)
    shield:SetSize(18, 20)
    shield:SetPoint("RIGHT", -1, 0)
    shield:SetAlpha(0)
    bar.Shield = shield

    local timer = bar:CreateFontString(nil, "OVERLAY")
    timer:SetFont(FONT, 9, "OUTLINE")
    timer:SetSize(40, 16)
    timer:SetPoint("RIGHT", shield, "LEFT", -2, 0)
    timer:SetJustifyH("RIGHT")
    timer:SetWordWrap(false)
    timer.binding = C_DurationUtil.CreateDurationTextBinding()
    timer.binding:SetEnabled(false)
    bar.Time = timer

    -- Follow the native fill edge without inspecting restricted progress values.
    local spark = bar:CreateTexture(nil, "ARTWORK")
    spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    spark:SetBlendMode("ADD")
    spark:SetSize(6, 16)
    spark:SetPoint("CENTER", bar:GetStatusBarTexture(), "RIGHT", 0, 0)
    spark:Hide()
    bar.Spark = spark

    local text = bar:CreateFontString(nil, "OVERLAY")
    text:SetFont(FONT, 10, "OUTLINE")
    text:SetPoint("LEFT", 5, 0)
    text:SetPoint("RIGHT", timer, "LEFT", -4, 0)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    bar.Text = text

    holder:SetScript("OnHide", function()
        ClearSafeZone(bar)
        HideStageSeparators(bar)
        timer.binding:SetEnabled(false)
        if bar.MIUF_CastState.terminal then ClearCastbar(frame) end
    end)
    holder:SetScript("OnShow", function()
        if bar.MIUF_CastState.active then
            timer.binding:SetEnabled(true)
            timer.binding:UpdateFontString()
            UpdateStageSeparators(frame)
            UpdateSafeZone(frame)
        end
    end)

    frame.CastbarHolder = holder
    frame.Castbar = bar
    if ns.GetCastbarLayout then ns.ApplyFrameCastbarSettings(frame, ns.GetCastbarLayout(frame.MIUF_UnitType)) end

    local events = CreateFrame("Frame")
    ns.RegisterFrameUnitEvent(events, "UNIT_SPELLCAST_START", frame)
    ns.RegisterFrameUnitEvent(events, "UNIT_SPELLCAST_STOP", frame)
    ns.RegisterFrameUnitEvent(events, "UNIT_SPELLCAST_FAILED", frame)
    ns.RegisterFrameUnitEvent(events, "UNIT_SPELLCAST_INTERRUPTED", frame)
    ns.RegisterFrameUnitEvent(events, "UNIT_SPELLCAST_DELAYED", frame)
    ns.RegisterFrameUnitEvent(events, "UNIT_SPELLCAST_CHANNEL_START", frame)
    ns.RegisterFrameUnitEvent(events, "UNIT_SPELLCAST_CHANNEL_UPDATE", frame)
    ns.RegisterFrameUnitEvent(events, "UNIT_SPELLCAST_CHANNEL_STOP", frame)
    ns.RegisterFrameUnitEvent(events, "UNIT_SPELLCAST_EMPOWER_START", frame)
    ns.RegisterFrameUnitEvent(events, "UNIT_SPELLCAST_EMPOWER_UPDATE", frame)
    ns.RegisterFrameUnitEvent(events, "UNIT_SPELLCAST_EMPOWER_STOP", frame)
    ns.RegisterFrameUnitEvent(events, "UNIT_SPELLCAST_INTERRUPTIBLE", frame)
    ns.RegisterFrameUnitEvent(events, "UNIT_SPELLCAST_NOT_INTERRUPTIBLE", frame)
    events:RegisterEvent("PLAYER_ENTERING_WORLD")

    if frame.MIUF_Unit == "target" then
        events:RegisterEvent("PLAYER_TARGET_CHANGED")
    elseif frame.MIUF_Unit == "focus" then
        events:RegisterEvent("PLAYER_FOCUS_CHANGED")
    elseif frame.MIUF_UnitType == "boss" then
        events:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
        ns.RegisterFrameUnitEvent(events, "UNIT_TARGETABLE_CHANGED", frame)
    end

    events:SetScript("OnEvent", function(_, event, ...)
        HandleCastEvent(frame, event, ...)
    end)

    frame.MIUF_CastbarEvents = events
    RefreshCastbar(frame)
end

local function AttachCastbars()
    if not ns.frames then return end
    for _, frame in pairs(ns.frames) do
        CreateCastbar(frame)
    end
end

local originalSpawnAllFrames = ns.SpawnAllFrames
function ns.SpawnAllFrames(...)
    if originalSpawnAllFrames then originalSpawnAllFrames(...) end
    AttachCastbars()
end

ns.RefreshCastbars = AttachCastbars
