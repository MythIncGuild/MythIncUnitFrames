local ADDON_NAME, ns = ...

local pendingEnabled, pendingAuraLayouts = {}, {}
local pendingFrameSettings, pendingGroupLayouts = {}, {}
local pendingPositions = {}
local pendingTrackedBuffs
local hasPendingChanges = false
local sessionProfile
local sessionActive = false
local closeRestorePending = false

function ns.ConfigSessionIsActive() return sessionActive end
function ns.ConfigSessionBegin()
    if closeRestorePending and not InCombatLockdown() then ns.ConfigSessionFinishClose() end
    if closeRestorePending then return false end
    sessionActive = true
    return true
end

function ns.ConfigSessionClear()
    if ns.ClearEnabledPreviews then ns.ClearEnabledPreviews() end
    pendingEnabled={}; pendingAuraLayouts={}; pendingFrameSettings={}; pendingGroupLayouts={}
    pendingPositions={}; pendingTrackedBuffs=nil; hasPendingChanges=false; sessionProfile=nil
end

local function EnsureProfile()
    -- Core initializes the database. Table identity survives a profile rename,
    -- but changes on switching profiles or replacing the active profile.
    local name=ns.GetActiveProfileName()
    local profile=MythIncUnitFramesDB.profiles[name]
    if sessionProfile~=profile then
        ns.ConfigSessionClear()
        sessionProfile=profile
    end
end

local function CopyValues(source)
    local result={}
    for k,v in pairs(source or {}) do result[k]=type(v)=="table" and CopyValues(v) or v end
    return result
end

-- Compare only staged fields: aura edits are sparse, frame/group edits are snapshots.
local function MatchesSaved(values,saved)
    if type(values)~="table" then return values==saved end
    if type(saved)~="table" then return false end
    for key,value in pairs(values) do
        if not MatchesSaved(value,saved[key]) then return false end
    end
    return true
end

function ns.ConfigSessionIsDirty()
    EnsureProfile()
    for unitType,values in pairs(pendingFrameSettings) do
        if MatchesSaved(values.size,ns.GetSize(unitType))
            and values.powerPercent==ns.GetPowerPercent(unitType)
            and MatchesSaved(values.castbar,ns.GetCastbarLayout(unitType))
            and MatchesSaved(values.appearance,ns.GetAppearance(unitType)) then
            pendingFrameSettings[unitType]=nil
        end
    end
    for unitType,values in pairs(pendingGroupLayouts) do
        if MatchesSaved(values,ns.GetGroupLayout(unitType)) then pendingGroupLayouts[unitType]=nil end
    end
    for unitType,enabled in pairs(pendingEnabled) do
        if enabled==ns.IsFrameTypeEnabled(unitType) then pendingEnabled[unitType]=nil end
    end
    for unitType,auraTypes in pairs(pendingAuraLayouts) do
        for auraType,values in pairs(auraTypes) do
            if MatchesSaved(values,ns.GetAuraLayout(unitType,auraType)) then auraTypes[auraType]=nil end
        end
        if not next(auraTypes) then pendingAuraLayouts[unitType]=nil end
    end
    if pendingTrackedBuffs and MatchesSaved(pendingTrackedBuffs,ns.GetTrackedBuffs())
        and MatchesSaved(ns.GetTrackedBuffs(),pendingTrackedBuffs) then pendingTrackedBuffs=nil end
    for key,value in pairs(pendingPositions) do
        if MatchesSaved(value,ns.GetPosition(key)) then pendingPositions[key]=nil end
    end
    hasPendingChanges=next(pendingPositions)~=nil or next(pendingFrameSettings)~=nil or next(pendingGroupLayouts)~=nil
        or next(pendingEnabled)~=nil or next(pendingAuraLayouts)~=nil or pendingTrackedBuffs~=nil
    return hasPendingChanges
end

function ns.ConfigSessionGetEnabled(unitType)
    EnsureProfile()
    if pendingEnabled[unitType]~=nil then return pendingEnabled[unitType] end
    return ns.IsFrameTypeEnabled(unitType)
end

function ns.ConfigSessionGetAura(unitType,auraType)
    EnsureProfile()
    local base=ns.GetAuraLayout(unitType,auraType); if not base then return nil end
    local result={}; for k,v in pairs(base) do result[k]=v end
    local pending=pendingAuraLayouts[unitType] and pendingAuraLayouts[unitType][auraType]
    if pending then for k,v in pairs(pending) do result[k]=v end end
    return result
end

-- Return independent GUI copies; callers stage changes explicitly.
function ns.ConfigSessionGetFrame(unitType)
    EnsureProfile()
    return CopyValues(pendingFrameSettings[unitType] or {
        size=ns.GetSize(unitType), powerPercent=ns.GetPowerPercent(unitType),
        appearance=ns.GetAppearance(unitType),
        castbar=ns.GetCastbarLayout(unitType),
    })
end

function ns.ConfigSessionGetGroup(unitType)
    EnsureProfile()
    return CopyValues(pendingGroupLayouts[unitType] or ns.GetGroupLayout(unitType))
end

function ns.ConfigSessionGetTrackedBuffs()
    EnsureProfile()
    return CopyValues(pendingTrackedBuffs or ns.GetTrackedBuffs())
end

function ns.ConfigSessionStageFrame(unitType,values)
    EnsureProfile()
    local snapshot=CopyValues(values)
    if snapshot.castbar==nil then
        local castbar=(pendingFrameSettings[unitType] or {}).castbar or ns.GetCastbarLayout(unitType)
        snapshot.castbar=castbar and CopyValues(castbar)
    end
    pendingFrameSettings[unitType]=snapshot
end

function ns.ConfigSessionStageGroup(unitType,values)
    EnsureProfile()
    pendingGroupLayouts[unitType]=CopyValues(values)
end

function ns.ConfigSessionStageEnabled(unitType,enabled)
    EnsureProfile()
    pendingEnabled[unitType]=enabled
end

function ns.ConfigSessionStageAura(unitType,auraType,values)
    EnsureProfile()
    pendingAuraLayouts[unitType]=pendingAuraLayouts[unitType] or {}
    local current=pendingAuraLayouts[unitType][auraType] or {}
    for key,value in pairs(values) do current[key]=value end
    pendingAuraLayouts[unitType][auraType]=current
end

function ns.ConfigSessionStageTrackedBuffs(values)
    EnsureProfile()
    local result={}
    for id,info in pairs(values or {}) do
        result[tonumber(id) or id]=type(info)=="table" and {name=info.name,icon=info.icon} or {}
    end
    pendingTrackedBuffs=result
end

function ns.ConfigSessionStageFrameReset(unitType)
    EnsureProfile()
    pendingFrameSettings[unitType]={
        size=CopyValues(ns.defaultSizes[unitType]),
        powerPercent=ns.defaultBarLayout[unitType].powerPercent,
        appearance=CopyValues(ns.defaultAppearance[unitType]),
        castbar=ns.defaultBarLayout[unitType].castbar and CopyValues(ns.defaultBarLayout[unitType].castbar),
    }
    if ns.defaultGroupLayout[unitType] then
        pendingGroupLayouts[unitType]=CopyValues(ns.defaultGroupLayout[unitType])
    end
end

function ns.ConfigSessionStageAuraReset(unitType,auraType)
    EnsureProfile()
    pendingAuraLayouts[unitType]=pendingAuraLayouts[unitType] or {}
    pendingAuraLayouts[unitType][auraType]=CopyValues(ns.defaultAuraLayout[unitType][auraType])
end

function ns.ConfigSessionStageResetAll()
    EnsureProfile()
    for unitType in pairs(ns.defaultSizes) do
        ns.ConfigSessionStageFrameReset(unitType)
        pendingEnabled[unitType]=ns.defaultEnabled[unitType]
        pendingAuraLayouts[unitType]=CopyValues(ns.defaultAuraLayout[unitType])
    end
    pendingPositions.raid=CopyValues(ns.defaultPositions.raid)
    pendingTrackedBuffs={}
end

-- Sparse field masks contain names only, never references to settings values.
local function ChangedFields(values, saved, includeRemoved)
    if type(values)~="table" or type(saved)~="table" then
        if values~=saved then return true end
        return nil
    end
    local fields={}
    for key,value in pairs(values) do
        local changed=ChangedFields(value,saved[key],includeRemoved)
        if changed then fields[key]=changed end
    end
    if includeRemoved then
        for key in pairs(saved) do if values[key]==nil then fields[key]=true end end
    end
    if next(fields) then return fields end
end

local function BuildChangeSummary()
    local summary={profileName=ns.GetActiveProfileName(),frameTypes={},categories={},requiresReloadFallback=false,reloadFallbackReasons={}}
    local function Record(unitType,category,fields)
        if not fields then return end
        summary.categories[category]=true
        local frame=summary.frameTypes[unitType] or {}
        summary.frameTypes[unitType]=frame
        frame[category]=fields
    end
    local function Fallback(reason,unitType,auraType)
        summary.requiresReloadFallback=true
        summary.reloadFallbackReasons[#summary.reloadFallbackReasons+1]={reason=reason,frameType=unitType,auraType=auraType}
    end
    for unitType,values in pairs(pendingFrameSettings) do
        Record(unitType,"size",ChangedFields(values.size,ns.GetSize(unitType)))
        if values.powerPercent~=ns.GetPowerPercent(unitType) then Record(unitType,"powerBar",{powerPercent=true}) end
        Record(unitType,"appearance",ChangedFields(values.appearance,ns.GetAppearance(unitType)))
        Record(unitType,"castbar",ChangedFields(values.castbar,ns.GetCastbarLayout(unitType)))
    end
    for unitType,values in pairs(pendingGroupLayouts) do
        local fields=ChangedFields(values,ns.GetGroupLayout(unitType))
        Record(unitType,"groupLayout",fields)
        if unitType=="raid" and fields and fields.legacy40 then Fallback("raidCapacityChanged",unitType) end
    end
    for unitType,enabled in pairs(pendingEnabled) do
        if enabled~=ns.IsFrameTypeEnabled(unitType) then
            Record(unitType,"enabled",{enabled=true})
        end
    end
    for unitType,auraTypes in pairs(pendingAuraLayouts) do
        local auras={}
        for auraType,values in pairs(auraTypes) do
            local fields=ChangedFields(values,ns.GetAuraLayout(unitType,auraType))
            if fields then
                auras[auraType]=fields
            end
        end
        if next(auras) then Record(unitType,"auras",auras) end
    end
    for key,value in pairs(pendingPositions) do
        local fields=ChangedFields(value,ns.GetPosition(key))
        if fields then
            local unitType=key:match("^party%d+$") and "party" or (key:match("^boss%d+$") and "boss" or key)
            local frame=summary.frameTypes[unitType]
            local positions=frame and frame.positions or {}
            positions[key]=fields
            Record(unitType,"positions",positions)
        end
    end
    if pendingTrackedBuffs then
        summary.trackedBuffs=ChangedFields(pendingTrackedBuffs,ns.GetTrackedBuffs(),true)
        if summary.trackedBuffs then
            for _,unitType in ipairs({"player","target","focus","targettarget","party"}) do Record(unitType,"trackedBuffs",true) end
        end
    end
    return summary
end

function ns.ConfigSessionCommit()
    EnsureProfile()
    if InCombatLockdown() or not ns.ConfigSessionIsDirty() then return false end
    local summary=BuildChangeSummary()
    for unitType,values in pairs(pendingFrameSettings) do
        ns.SaveSize(unitType,values.size.width,values.size.height)
        ns.SavePowerPercent(unitType,values.powerPercent)
        ns.SaveAppearance(unitType,values.appearance)
        if values.castbar then ns.SaveCastbarLayout(unitType,values.castbar) end
    end
    for key,value in pairs(pendingPositions) do ns.SavePosition(key,value.point,value.relativePoint,value.x,value.y) end
    for unitType,values in pairs(pendingGroupLayouts) do ns.SaveGroupLayout(unitType,values) end
    for unitType,enabled in pairs(pendingEnabled) do ns.SetFrameTypeEnabled(unitType,enabled) end
    for unitType,auraTypes in pairs(pendingAuraLayouts) do for auraType,values in pairs(auraTypes) do ns.SaveAuraLayout(unitType,auraType,values) end end
    if pendingTrackedBuffs then ns.SetTrackedBuffs(pendingTrackedBuffs) end
    ns.ConfigSessionClear()

    return true,summary
end

function ns.ApplySavedConfiguration(summary)
    if InCombatLockdown() or not summary or summary.requiresReloadFallback then return false end
    if summary.profileName~=ns.GetActiveProfileName() then return false end
    ns.ClearGroupPreviewOverrides()
    if summary.categories and summary.categories.enabled and ns.ApplySavedEnabledStates()~=true then return false end
    -- Frame state first, then positions/geometry, then attached aura layouts.
    -- Saved-list and suppression hooks already ran during commit.
    for unitType,changes in pairs(summary.frameTypes) do
        if changes.size or changes.powerBar or changes.appearance then ns.ApplySavedFrameSettings(unitType) end
        if changes.castbar and ns.ApplyCastbarLayout then ns.ApplyCastbarLayout(unitType,ns.GetCastbarLayout(unitType)) end
    end
    for unitType,changes in pairs(summary.frameTypes) do
        if changes.positions and unitType~="raid" then ns.ApplySavedFramePositions(changes.positions) end
        if unitType=="party" or unitType=="boss" or unitType=="raid" then
            if changes.size or changes.positions or changes.groupLayout then
                if unitType=="raid" then ns.ApplyRaidLayout(true) else ns.ApplyGroupLayout(unitType) end
            end
        end
    end
    for unitType,changes in pairs(summary.frameTypes) do
        if changes.enabled or changes.size or changes.powerBar or changes.appearance or changes.positions or changes.groupLayout then
            ns.ApplyAuraPositions(unitType)
        elseif changes.auras then
            for auraType in pairs(changes.auras) do ns.ApplyAuraPositions(unitType,auraType) end
        end
    end
    return true
end

function ns.ConfigSessionGetPosition(key)
    EnsureProfile()
    return CopyValues(pendingPositions[key] or ns.GetPosition(key))
end

-- Stop only the requested scope for the Raid-only control, or all movers for
-- general Revert. Late mouse releases must not stage discarded coordinates.
function ns.StopConfigurationMovers(unitType)
    if ns.CancelPrecisionPositionDrag then ns.CancelPrecisionPositionDrag() end
    local combat=InCombatLockdown()
    local function StopMover(owner,mover)
        if not mover then return end
        mover.MIUF_RevertedDrag=true
        local resize=mover.MIUF_ResizeHandle
        if resize then resize:SetScript("OnUpdate",nil); resize.MIUF_ResizeState=nil end
        if combat then return end
        owner:StopMovingOrSizing(); mover:StopMovingOrSizing()
        mover:ClearAllPoints(); mover:SetAllPoints(owner)
    end
    for _,frame in pairs(ns.frames or {}) do
        if not unitType or frame.MIUF_UnitType==unitType then
            StopMover(frame,frame.MIUF_Mover)
            for auraType,mover in pairs(frame.MIUF_AuraMovers or {}) do
                StopMover(frame.MIUF_Auras[auraType].anchor,mover)
            end
        end
    end
    if (not unitType or unitType=="raid") and ns.raidFrameMoverOwner then
        StopMover(ns.raidFrameMoverOwner,ns.raidFrameMoverOwner.MIUF_Mover)
    end
    if ns.GetGroupStatusPreviewFrame then
        for _,kind in ipairs({"party","raid"}) do
            local host=ns.GetGroupStatusPreviewFrame(kind)
            if host and (not unitType or unitType==kind) then
                for auraType,mover in pairs(host.MIUF_AuraMovers or {}) do
                    StopMover(host.MIUF_Auras[auraType].anchor,mover)
                end
            end
        end
    end
    return not combat
end

function ns.ConfigSessionRevert(force)
    if InCombatLockdown() or (not force and not ns.ConfigSessionIsDirty()) then return false end
    -- Keep the session recoverable if a saved-state restoration fails. No
    -- setters, enabled lifecycle, capacity rebuild or reload belong to Revert.
    local pending={pendingEnabled,pendingAuraLayouts,pendingFrameSettings,pendingGroupLayouts,
        pendingPositions,pendingTrackedBuffs,hasPendingChanges,sessionProfile}
    local summary={profileName=ns.GetActiveProfileName(),frameTypes={}}
    for unitType in pairs(ns.defaultSizes) do
        summary.frameTypes[unitType]={size=true,appearance=true,powerBar=true,castbar=true,groupLayout=true,positions={}}
    end
    for key in pairs(ns.defaultPositions) do
        local unitType=key:match("^party%d+$") and "party" or (key:match("^boss%d+$") and "boss" or key)
        summary.frameTypes[unitType].positions[key]=true
    end
    local ok,result=pcall(function()
        if not ns.StopConfigurationMovers() then return false end
        ns.ConfigSessionClear()
        if ns.ApplySavedConfiguration(summary)~=true then return false end
        ns.SetFrameMoversLocked(ns.AreFrameMoversLocked())
        ns.SetAuraMoversLocked(ns.AreAuraMoversLocked())
        return true
    end)
    if not ok or not result then
        pendingEnabled,pendingAuraLayouts,pendingFrameSettings,pendingGroupLayouts,
            pendingPositions,pendingTrackedBuffs,hasPendingChanges,sessionProfile=unpack(pending,1,8)
        return false,ok and "Saved-state restoration did not complete." or result
    end
    return true
end

-- Close clears the same pending store used by Apply/Revert. Protected visual
-- restoration waits for combat to end; discarded values never survive it.
function ns.ConfigSessionFinishClose()
    if not closeRestorePending or InCombatLockdown() then return false end
    local restored,err=ns.ConfigSessionRevert(true)
    if restored then closeRestorePending=false end
    return restored,err
end

function ns.ConfigSessionClose()
    sessionActive=false
    ns.ConfigSessionClear()
    ns.SetFrameMoversLockedState(true)
    ns.SetAuraMoversLockedState(true)
    closeRestorePending=true
    return ns.ConfigSessionFinishClose()
end

function ns.ConfigSessionStagePosition(key, value)
    EnsureProfile()
    pendingPositions[key] = CopyValues(value)
end
