local ADDON_NAME, ns = ...

ns.UnitFramesLoaded = true

local FLAT = "Interface\\Buttons\\WHITE8x8"
local FONT = "Fonts\\FRIZQT__.TTF"
local RAID_TARGET_TEXTURE = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"
local RESURRECTION_ATLAS = "RaidFrame-Icon-Rez"
local SUMMON_ATLAS_PREFIX = "RaidFrame-Icon-Summon"
local STATUS_ICON_TYPES = { "ReadyCheckIndicator", "IncomingSummonIndicator", "IncomingResurrectionIndicator" }
local frames, previewEnabled, rangeFrames = {}, {}, {}
ns.frames = frames

-- Configuration-only rendering state; never used as unit/status data.
local temporaryStatusPreview
local readyCheckDisplayActive = false
local readyCheckFinishGeneration = 0

-- Match SecureButton_GetModifiedUnit's player/pet swap under toggleForVehicle.
-- Blizzard uses "vehicle" for the player's visual data (the secure click uses
-- the equivalent "pet" token). Keep logical identities/configuration unchanged.
local VEHICLE_DISPLAY_UNITS = { player = "vehicle", pet = "player" }
local VEHICLE_EVENTS = {
    UNIT_ENTERING_VEHICLE = true, UNIT_ENTERED_VEHICLE = true,
    UNIT_EXITING_VEHICLE = true, UNIT_EXITED_VEHICLE = true,
    UNIT_PET = true, VEHICLE_UPDATE = true,
}

function ns.GetFrameDisplayUnit(frame)
    local unit = frame and frame.MIUF_Unit
    if VEHICLE_DISPLAY_UNITS[unit] and UnitHasVehicleUI("player") then
        return VEHICLE_DISPLAY_UNITS[unit]
    end
    return unit
end

-- Subscribe to both identities at creation, including during combat transitions.
function ns.RegisterFrameUnitEvent(eventFrame, event, frame)
    local unit = frame.MIUF_Unit
    local vehicleUnit = VEHICLE_DISPLAY_UNITS[unit]
    if vehicleUnit then eventFrame:RegisterUnitEvent(event, unit, vehicleUnit)
    else eventFrame:RegisterUnitEvent(event, unit) end
end

local function CreateBackground(parent)
    local bg = parent:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(parent)
    bg:SetColorTexture(0.03, 0.03, 0.03, 0.92)
    return bg
end

local function CreateBorder(parent)
    local border = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetBackdrop({ edgeFile = FLAT, edgeSize = 1 })
    border:SetBackdropBorderColor(0.1, 0.1, 0.1, 1)
    border:SetFrameLevel(parent:GetFrameLevel() + 5)
    return border
end

local function ApplyPosition(positionKey, frame)
    local p = ns.GetPosition(positionKey)
    if not p then return end
    frame:ClearAllPoints()
    frame:SetPoint(p.point, UIParent, p.relativePoint, p.x, p.y)
end

local function StageMoverPosition(frame, positionKey)
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    ns.ConfigSessionStagePosition(positionKey,{point=point or "CENTER",relativePoint=relativePoint or point or "CENTER",x=x or 0,y=y or 0})
    if ns.RefreshConfig then ns.RefreshConfig() end
end

local function BuildFrameState(unitType, overrides)
    local savedSize = ns.GetSize(unitType) or {}
    local savedAppearance = ns.GetAppearance(unitType) or {}
    local state = { size = { width = savedSize.width, height = savedSize.height }, powerPercent = ns.GetPowerPercent(unitType), appearance = {} }
    state.castbar=ns.GetCastbarLayout(unitType)
    for key, value in pairs(savedAppearance) do state.appearance[key] = value end
    if overrides then
        if overrides.size then
            if overrides.size.width ~= nil then state.size.width = overrides.size.width end
            if overrides.size.height ~= nil then state.size.height = overrides.size.height end
        end
        if overrides.powerPercent ~= nil then state.powerPercent = overrides.powerPercent end
        if overrides.castbar then state.castbar=overrides.castbar end
        if overrides.appearance then for key, value in pairs(overrides.appearance) do state.appearance[key] = value end end
    end
    return state
end

-- UnitIsAFK can be secret during chat lockdown. Guard every flag before
-- comparing it; unknown flags fall back to the secret-capable health sink.
local function PublicFlag(api, unit)
    local value = api(unit)
    if not canaccessvalue(value) then return nil end
    return value
end

local function GetUnitStatus(unit)
    if PublicFlag(UnitExists, unit) ~= true then return nil end
    local isPlayer = PublicFlag(UnitIsPlayer, unit) == true
    if isPlayer and PublicFlag(UnitIsConnected, unit) == false then return "Offline" end
    if isPlayer and PublicFlag(UnitIsGhost, unit) == true then return "Ghost" end
    if PublicFlag(UnitIsDead, unit) == true then return "Dead" end
    if isPlayer and PublicFlag(UnitIsAFK, unit) == true then return "AFK" end
end

local function UpdateHealth(frame, refreshStatus)
    local unit = ns.GetFrameDisplayUnit(frame)
    if not unit then return end
    if refreshStatus ~= false then frame.MIUF_StatusText = GetUnitStatus(unit) end
    local value = UnitHealthPercent(unit, true, CurveConstants and CurveConstants.ScaleTo100)
    if value ~= nil then frame.Health:SetValue(value) end
    if frame.HealthText then
        -- SetFormattedText is a secret-capable display sink. Do not inspect or
        -- calculate with the percentage in Lua; let the FontString format it.
        local displayed = false
        if frame.MIUF_StatusText then
            frame.HealthText:SetText(frame.MIUF_StatusText)
            displayed = true
        elseif value ~= nil then
            displayed = pcall(frame.HealthText.SetFormattedText, frame.HealthText, "%.0f%%", value)
        end
        if not displayed then frame.HealthText:SetText("") end
    end
end

local function UpdatePowerVisibility(frame)
    if frame.MIUF_UnitType ~= "party" and frame.MIUF_UnitType ~= "raid" then return end
    if not frame.MIUF_PowerDisplayGate then return end
    -- Use the logical group member's assigned role, including in vehicles.
    -- The gate preserves the power bar's own shown state.
    local shown=not frame.MIUF_HealerPowerBarsOnly
        or (frame.MIUF_Unit and UnitGroupRolesAssigned(frame.MIUF_Unit) == "HEALER") or false
    frame.MIUF_PowerDisplayGate:SetShown(shown)
    -- Fill the reserved space without changing the outer frame or backdrop.
    -- Retain the applied (possibly previewed) height for live role changes.
    frame.Health:SetPoint("BOTTOM",frame,"BOTTOM",0,shown and frame.MIUF_PowerHeight or 2)
    local text=frame.MIUF_PowerTextLayout
    if text then
        -- Expansion lowers the health bar's center; keep text at its normal height.
        local offset=shown and 0 or (frame.MIUF_PowerHeight-2)/2
        frame.NameText:SetPoint("LEFT",frame.Health,"LEFT",text.nameX,text.nameY+offset)
        frame.NameText:SetPoint("RIGHT",frame.Health,"RIGHT",text.nameRightX,text.nameY+offset)
        frame.HealthText:SetPoint("RIGHT",frame.Health,"RIGHT",text.healthX,text.healthY+offset)
    end
end

local function UpdatePower(frame)
    UpdatePowerVisibility(frame)
    local unit = ns.GetFrameDisplayUnit(frame)
    if not unit then return end
    local value = UnitPowerPercent(unit, nil, false, CurveConstants and CurveConstants.ScaleTo100)
    if value ~= nil then frame.Power:SetValue(value) end
end

local function UpdateName(frame)
    local unit = ns.GetFrameDisplayUnit(frame)
    if not unit then return end
    local name = UnitName(unit)
    frame.NameText:SetText(name or "")
end

local function UpdatePortrait(frame)
    local unit = ns.GetFrameDisplayUnit(frame)
    if frame.Portrait and unit then SetPortraitTexture(frame.Portrait, unit) end
end

local function GetAutomaticHealthColor(unit)
    if not unit or not UnitExists(unit) then return 0.45, 0.45, 0.45 end
    if UnitIsPlayer(unit) then
        local _, class = UnitClass(unit)
        -- The native API accepts secret class tokens; pass its RGB values straight
        -- to SetStatusBarColor rather than indexing a Lua table with the token.
        local color = class and C_ClassColor.GetClassColor(class)
        if color then return color:GetRGB() end
    end
    local reaction = UnitReaction(unit, "player")
    if not canaccessvalue(reaction) then return 0.45, 0.45, 0.45 end
    if reaction then
        if reaction <= 3 then return 0.80, 0.18, 0.18 end
        if reaction == 4 then return 0.85, 0.75, 0.20 end
        return 0.20, 0.75, 0.25
    end
    return 0.20, 0.75, 0.25
end

local POWER_COLORS = {
    MANA={0.10,0.35,0.95}, RAGE={0.90,0.12,0.12}, FOCUS={0.95,0.45,0.10}, ENERGY={0.95,0.85,0.10},
    RUNIC_POWER={0.10,0.80,0.95}, LUNAR_POWER={0.25,0.50,1.00}, INSANITY={0.55,0.20,0.80}, FURY={0.75,0.20,1.00}, MAELSTROM={0.10,0.55,1.00},
}

local function GetAutomaticPowerColor(unit)
    if not unit or not UnitExists(unit) then return 0.20,0.40,0.90 end
    local _, token = UnitPowerType(unit)
    -- Preserve MIUF's palette for public tokens; never use a secret table key.
    if not canaccessvalue(token) then return 0.20,0.40,0.90 end
    local c = token and POWER_COLORS[token]
    if c then return c[1],c[2],c[3] end
    return 0.20,0.40,0.90
end

local function ApplyColors(frame, appearance)
    if appearance.healthColor == "automatic" then
        local r,g,b = GetAutomaticHealthColor(ns.GetFrameDisplayUnit(frame)); frame.Health:SetStatusBarColor(r,g,b,1)
    else
        local e = ns.Media.healthColors[appearance.healthColor] or ns.Media.healthColors.green; local c=e.rgb; frame.Health:SetStatusBarColor(c[1],c[2],c[3],1)
    end
    if appearance.powerColor == "automatic" then
        local r,g,b = GetAutomaticPowerColor(ns.GetFrameDisplayUnit(frame)); frame.Power:SetStatusBarColor(r,g,b,1)
    else
        local e = ns.Media.powerColors[appearance.powerColor] or ns.Media.powerColors.blue; local c=e.rgb; frame.Power:SetStatusBarColor(c[1],c[2],c[3],1)
    end
end

local function GetHealthBarRightInset(width, appearance, hasPortrait)
    if hasPortrait and appearance.showPortrait and appearance.portraitSide=="RIGHT" then
        return math.max(18,math.floor(width*(appearance.portraitPercent/100)))+4
    end
    return 2
end

local function ApplyStatusIndicatorLayout(frame, appearance)
    local size=math.max(8,math.min(48,tonumber(appearance.statusIconSize) or 18))
    local previous
    for _,field in ipairs(STATUS_ICON_TYPES) do
        local icon=frame[field]
        if icon then
            icon:SetSize(size,size); icon:ClearAllPoints()
            if previous then icon:SetPoint("RIGHT",previous,"LEFT",-2,0)
            else icon:SetPoint("TOPRIGHT",(frame.Health or frame.MIUF_StatusPreviewAnchor),"TOPRIGHT",appearance.statusIconXOffset or -4,appearance.statusIconYOffset or -3) end
            previous=icon
        end
    end
end

local partyLeaderAppearance
local function ApplyLeaderLayout(frame, appearance)
    if frame.LeaderIndicator then
        local size=math.max(8,math.min(48,tonumber(appearance.leaderIconSize) or 12))
        frame.LeaderIndicator:SetSize(size,size)
        frame.LeaderIndicator:ClearAllPoints()
        frame.LeaderIndicator:SetPoint("TOPLEFT",frame,"TOPLEFT",appearance.leaderIconXOffset or -16,appearance.leaderIconYOffset or -2)
        frame.MIUF_ShowLeaderIcon=appearance.showLeaderIcon==true
    end
end

local function ApplyIndicatorLayout(frame, appearance, skipResting)
    if frame.MIUF_UnitType=="party" then partyLeaderAppearance=appearance end
    ApplyLeaderLayout(frame,frame.MIUF_UnitType=="player" and (partyLeaderAppearance or ns.GetAppearance("party")) or appearance)
    if frame.RaidTargetIndicatorFrame then
        local size=math.max(8,tonumber(appearance.raidMarkerSize) or 20)
        frame.RaidTargetIndicatorFrame:SetSize(size,size); frame.RaidTargetIndicatorFrame:ClearAllPoints()
        frame.RaidTargetIndicatorFrame:SetPoint("CENTER",frame,"TOP",appearance.raidMarkerXOffset or 0,appearance.raidMarkerYOffset or 2)
    end
    if frame.GroupRoleIndicator then
        local size=math.max(8,math.min(48,tonumber(appearance.roleIconSize) or 14))
        frame.GroupRoleIndicator:SetSize(size,size)
        frame.GroupRoleIndicator:ClearAllPoints(); frame.GroupRoleIndicator:SetPoint("TOPLEFT",frame.Health,"TOPLEFT",appearance.roleIconXOffset or 3,appearance.roleIconYOffset or -3)
    end
    if frame.RestingIndicator and not skipResting then
        local size=math.max(8,math.min(48,tonumber(appearance.restingIconSize) or 16))
        frame.RestingIndicator:SetSize(size,size)
        frame.RestingIndicator:ClearAllPoints(); frame.RestingIndicator:SetPoint("TOPLEFT",frame.Health,"TOPLEFT",appearance.restingIconXOffset or 3,appearance.restingIconYOffset or -3)
    end
    ApplyStatusIndicatorLayout(frame,appearance)
end

local function SetIndicatorShown(icon, shown)
    -- Real event handlers still read/cache real status. Only the rendered Ready
    -- Check texture is overridden, and its cache is invalidated on cleanup.
    local preview=temporaryStatusPreview
    if preview and icon==preview.frame.ReadyCheckIndicator then
        local unit=not preview.ghost and ns.GetFrameDisplayUnit(preview.frame)
        shown=preview.frame:IsVisible() and (preview.ghost or (unit and UnitExists(unit)))
        if shown then icon:SetAtlas(READY_CHECK_READY_TEXTURE,false) end
    end
    if shown then if not icon:IsShown() then icon:Show() end
    elseif icon:IsShown() then icon:Hide() end
end

local function UpdateReadyCheckIndicator(frame)
    local icon=frame.ReadyCheckIndicator; if not icon then return end
    local unit=ns.GetFrameDisplayUnit(frame)
    if not readyCheckDisplayActive or not unit or not UnitExists(unit) then
        frame.MIUF_ReadyCheckStatus=nil; SetIndicatorShown(icon,false); return
    end
    local status=GetReadyCheckStatus(unit)
    if not canaccessvalue(status) then frame.MIUF_ReadyCheckStatus=nil; SetIndicatorShown(icon,false); return end
    if readyCheckDisplayActive=="finished" and status=="waiting" then status="notready" end
    local atlas=status=="ready" and READY_CHECK_READY_TEXTURE
        or status=="notready" and READY_CHECK_NOT_READY_TEXTURE
        or status=="waiting" and READY_CHECK_WAITING_TEXTURE
    if atlas then
        if frame.MIUF_ReadyCheckStatus~=status then icon:SetAtlas(atlas,false); frame.MIUF_ReadyCheckStatus=status end
        SetIndicatorShown(icon,true)
    else
        frame.MIUF_ReadyCheckStatus=nil; SetIndicatorShown(icon,false)
    end
end

local function UpdateIncomingSummonIndicator(frame)
    local icon=frame.IncomingSummonIndicator; if not icon then return end
    local unit=ns.GetFrameDisplayUnit(frame)
    if not unit or not UnitExists(unit) then
        frame.MIUF_IncomingSummonStatus=nil; SetIndicatorShown(icon,false); return
    end
    local status=C_IncomingSummon.IncomingSummonStatus(unit)
    if not canaccessvalue(status) then frame.MIUF_IncomingSummonStatus=nil; SetIndicatorShown(icon,false); return end
    local suffix=status==Enum.SummonStatus.Pending and "Pending"
        or status==Enum.SummonStatus.Accepted and "Accepted"
        or status==Enum.SummonStatus.Declined and "Declined"
    if suffix then
        if frame.MIUF_IncomingSummonStatus~=status then icon:SetAtlas(SUMMON_ATLAS_PREFIX..suffix,false); frame.MIUF_IncomingSummonStatus=status end
        SetIndicatorShown(icon,true)
    else
        frame.MIUF_IncomingSummonStatus=nil; SetIndicatorShown(icon,false)
    end
end

local function UpdateIncomingResurrectionIndicator(frame)
    local icon=frame.IncomingResurrectionIndicator; if not icon then return end
    local unit=ns.GetFrameDisplayUnit(frame)
    local incoming=unit and UnitExists(unit) and UnitHasIncomingResurrection(unit)
    SetIndicatorShown(icon,canaccessvalue(incoming) and incoming==true)
end

local function UpdateStatusIndicators(frame)
    UpdateReadyCheckIndicator(frame)
    UpdateIncomingSummonIndicator(frame)
    UpdateIncomingResurrectionIndicator(frame)
end

function ns.ClearTemporaryStatusPreview()
    local preview=temporaryStatusPreview
    temporaryStatusPreview=nil
    if not preview then return end
    if preview.ghost then
        preview.frame.ReadyCheckIndicator:Hide()
    else
        preview.frame.MIUF_ReadyCheckStatus=nil
        UpdateStatusIndicators(preview.frame)
    end
end

local function IsStatusPreviewFrameAvailable(frame)
    if not frame or not frame.ReadyCheckIndicator or not frame:IsVisible() then return false end
    local unit=ns.GetFrameDisplayUnit(frame)
    return unit and UnitExists(unit)
end

local function GetLiveStatusPreviewFrame(unitType)
    if unitType=="party" then
        if IsStatusPreviewFrameAvailable(ns.partyFrameMoverOwner) then return ns.partyFrameMoverOwner end
        for index=1,4 do
            local frame=frames["party"..index]
            if IsStatusPreviewFrameAvailable(frame) then return frame end
        end
        if IsStatusPreviewFrameAvailable(frames.partyplayer) then return frames.partyplayer end
    elseif unitType=="raid" then
        for index=1,40 do
            local frame=frames["raid"..index]
            if IsStatusPreviewFrameAvailable(frame) then return frame end
        end
    elseif unitType~="pet" and unitType~="boss" then
        local frame=frames[unitType]
        if IsStatusPreviewFrameAvailable(frame) then return frame end
    end
end

function ns.UpdateTemporaryStatusPreview(unitType, appearance)
    local frame=ns.GetGroupStatusPreviewFrame and ns.GetGroupStatusPreviewFrame(unitType)
    local ghost=frame~=nil
    if not frame then frame=GetLiveStatusPreviewFrame(unitType) end
    if temporaryStatusPreview and temporaryStatusPreview.frame~=frame then ns.ClearTemporaryStatusPreview() end
    if not frame then return end
    if ghost then
        -- Extend the existing group ghost, not a separate mock-frame system.
        if not frame.ReadyCheckIndicator then
            frame.ReadyCheckIndicator=frame:CreateTexture(nil,"OVERLAY")
            frame.MIUF_StatusPreviewAnchor=frame:CreateTexture(nil,"BACKGROUND")
            frame.MIUF_StatusPreviewAnchor:SetSize(1,1); frame.MIUF_StatusPreviewAnchor:Hide()
        end
        local inset=GetHealthBarRightInset(frame:GetWidth(),appearance,unitType~="raid")
        frame.MIUF_StatusPreviewAnchor:ClearAllPoints()
        frame.MIUF_StatusPreviewAnchor:SetPoint("TOPRIGHT",frame,"TOPRIGHT",-inset,-2)
    end
    if not temporaryStatusPreview then temporaryStatusPreview={frame=frame,ghost=ghost} end
    ApplyStatusIndicatorLayout(frame,appearance)
    SetIndicatorShown(frame.ReadyCheckIndicator,true)
end

local function UpdateRestingIndicator(frame)
    local icon=frame.RestingIndicator; if not icon then return end
    local resting=IsResting()
    if frame.MIUF_ShowRestingIcon and canaccessvalue(resting) and resting then
        icon:Show()
        if not icon.Animation:IsPlaying() then icon.Animation:Play() end
    else
        icon.Animation:Stop(); icon:Hide()
    end
end

local function UpdateRaidTarget(frame, appearance)
    local holder,icon=frame.RaidTargetIndicatorFrame,frame.RaidTargetIndicator
    if not holder or not icon then return end
    appearance=appearance or ns.GetAppearance(frame.MIUF_UnitType) or {}
    local unit=ns.GetFrameDisplayUnit(frame)
    if appearance.showRaidMarker==false or not unit or not UnitExists(unit) then
        frame.MIUF_RaidTargetIndex=nil
        if holder:IsShown() then holder:Hide() end
        return
    end
    local index=GetRaidTargetIndex(unit)
    if not canaccessvalue(index) then
        -- Instance raid indices may be secret. Blizzard's texture helper is the
        -- supported display sink; do not inspect or calculate with the value.
        SetRaidTargetIconTexture(icon,index)
        frame.MIUF_RaidTargetIndex=nil
        if not holder:IsShown() then holder:Show() end
    elseif index then
        if frame.MIUF_RaidTargetIndex~=index then
            SetRaidTargetIconTexture(icon,index)
            frame.MIUF_RaidTargetIndex=index
        end
        if not holder:IsShown() then holder:Show() end
    else
        frame.MIUF_RaidTargetIndex=nil
        if holder:IsShown() then holder:Hide() end
    end
end

local function UpdateRoleIndicator(frame, appearance)
    local icon=frame.GroupRoleIndicator; if not icon then return end
    if frame.MIUF_UnitType~="party" and frame.MIUF_UnitType~="raid" then icon:Hide(); return end
    appearance=appearance or ns.GetAppearance(frame.MIUF_UnitType) or {}
    local role=UnitGroupRolesAssigned(ns.GetFrameDisplayUnit(frame)); local texture
    if not canaccessvalue(role) then icon:Hide(); return end
    if role=="TANK" and appearance.showTankRoleIcon then texture="MIUF_Role_Tank"
    elseif role=="HEALER" and appearance.showHealerRoleIcon then texture="MIUF_Role_Healer"
    elseif role=="DAMAGER" and appearance.showDamageRoleIcon then texture="MIUF_Role_Damage" end
    if texture then icon:SetTexture("Interface\\AddOns\\"..ADDON_NAME.."\\Media\\Artwork\\"..texture..".tga"); icon:Show() else icon:Hide() end
end

local function UpdateLeaderIndicator(frame)
    local icon=frame.LeaderIndicator; if not icon then return end
    -- Leadership belongs to the logical group member, including in a vehicle.
    local unit=frame.MIUF_Unit
    local leader=frame.MIUF_ShowLeaderIcon and IsInGroup() and unit and UnitExists(unit) and UnitIsGroupLeader(unit)
    if frame.MIUF_UnitType=="player" or frame.MIUF_UnitType=="party" then
        local includePlayer=ns.GetGroupLayout("party").includePlayer
        local available=ns.IsFrameTypeEnabled("party") and not IsInRaid()
        if frame.MIUF_UnitType=="player" then
            available=available and not includePlayer and ns.IsFrameTypeEnabled("player")
        elseif unit=="player" then
            available=available and includePlayer
        end
        if not available then leader=false end
    end
    icon:SetShown(canaccessvalue(leader) and leader==true)
end

function ns.RefreshPartyLeaderIndicator()
    local player=frames.player
    if player then
        ApplyLeaderLayout(player,partyLeaderAppearance or ns.GetAppearance("party"))
        UpdateLeaderIndicator(player)
    end
    for _,frame in pairs(frames) do
        if frame.MIUF_UnitType=="party" then UpdateLeaderIndicator(frame) end
    end
end

local function UpdateConnectionState(frame)
    if frame.MIUF_StatusText=="Offline" then frame.Health:SetStatusBarColor(0.32,0.32,0.32,1); frame.Power:SetStatusBarColor(0.20,0.20,0.20,1) end
end

local function UpdateFrame(frame, refreshStatus)
    UpdateLeaderIndicator(frame)
    UpdateHealth(frame,refreshStatus); UpdatePower(frame); UpdateName(frame); UpdatePortrait(frame)
    local appearance=ns.GetAppearance(frame.MIUF_UnitType) or {}
    ApplyColors(frame,appearance)
    -- ApplyFrameState owns indicator geometry, including configuration previews.
    -- Unit events and target-of-target polling only need to refresh content.
    UpdateRaidTarget(frame,appearance); UpdateRoleIndicator(frame,appearance); UpdateStatusIndicators(frame); UpdateConnectionState(frame); UpdateRestingIndicator(frame)
end

local pendingFonts={}
local FONT_RETRY_LIMIT=120 -- Roughly 30 seconds of the existing 0.25s updater.
local function RecoverTextFont(text,request)
    request.attempts=request.attempts+1
    local success=text:SetFont(request.font,request.size,request.flags)
    if success then
        -- A cold-start failure can leave stale rendering state even after font
        -- assignment succeeds. Change size and restore it in the same callback.
        text:SetFont(request.font,request.size+1,request.flags)
        success=text:SetFont(request.font,request.size,request.flags)
        if not success then
            -- Never retain the temporary size; use the same built-in fallback
            -- used at frame creation while bounded recovery remains pending.
            text:SetFont(FONT,request.size,request.flags)
        end
    end
    if success then
        text.MIUF_FontRecovery=nil
        pendingFonts[text]=nil
    elseif request.attempts>=FONT_RETRY_LIMIT then
        -- Retain failure history/budget for explicit previews, but stop automatic
        -- attempts. Repeated configuration applications must not restart polling.
        pendingFonts[text]=nil
    else
        pendingFonts[text]=request
    end
end

local function ApplyTextFont(text,font,size)
    local flags="OUTLINE"
    local bundled=font:find("Interface\\AddOns\\MythIncUnitFrames\\Media\\Fonts\\",1,true)==1
    local request=text.MIUF_FontRecovery
    if bundled and request then
        -- Preserve the budget while replacing stale saved/preview parameters.
        request.font,request.size,request.flags=font,size,flags
        RecoverTextFont(text,request)
    else
        local success=text:SetFont(font,size,flags)
        if bundled and not success then
            request={font=font,size=size,flags=flags,attempts=0}
            text.MIUF_FontRecovery=request
            pendingFonts[text]=request
        else
            text.MIUF_FontRecovery=nil
            pendingFonts[text]=nil
        end
    end
end

local function ApplyFrameFonts(frame,appearance)
    local font=ns.GetFontPath(appearance.fontFace)
    ApplyTextFont(frame.NameText,font,appearance.fontSize)
    ApplyTextFont(frame.HealthText,font,math.max(9,appearance.fontSize-1))
end

local function RetryPendingFonts()
    for text,request in pairs(pendingFonts) do RecoverTextFont(text,request) end
end

local function ApplyFrameState(frame,state)
    local appearance=state.appearance; local width,height=state.size.width,state.size.height; frame:SetSize(width,height)
    frame.MIUF_HealerPowerBarsOnly=appearance.healerPowerBarsOnly==true
    if ns.ApplyFrameCastbarSettings then ns.ApplyFrameCastbarSettings(frame,state.castbar) end
    local texture=ns.GetTexturePath(appearance.texture); frame.Health:SetStatusBarTexture(texture); frame.Power:SetStatusBarTexture(texture)
    frame.Background:SetColorTexture(0.03,0.03,0.03,appearance.backgroundOpacity/100); frame.Border:SetBackdropBorderColor(0.1,0.1,0.1,appearance.borderOpacity/100)
    local showPortrait=frame.Portrait and appearance.showPortrait
    local portraitWidth=showPortrait and math.max(18,math.floor(width*(appearance.portraitPercent/100))) or 0
    if frame.Portrait then frame.Portrait:ClearAllPoints() end
    if showPortrait then
        frame.Portrait:SetWidth(portraitWidth); frame.Portrait:SetPoint("TOP",frame,"TOP",0,-2); frame.Portrait:SetPoint("BOTTOM",frame,"BOTTOM",0,2)
        if appearance.portraitSide=="RIGHT" then frame.Portrait:SetPoint("RIGHT",frame,"RIGHT",-2,0) else frame.Portrait:SetPoint("LEFT",frame,"LEFT",2,0) end
        frame.Portrait:Show()
    elseif frame.Portrait then frame.Portrait:Hide() end
    local leftInset,rightInset=2,GetHealthBarRightInset(width,appearance,frame.Portrait)
    if showPortrait and appearance.portraitSide~="RIGHT" then leftInset=portraitWidth+4 end
    local powerHeight=math.max(8,math.floor(height*(state.powerPercent/100)))
    frame.Health:ClearAllPoints(); frame.Health:SetPoint("TOPLEFT",frame,"TOPLEFT",leftInset,-2); frame.Health:SetPoint("TOPRIGHT",frame,"TOPRIGHT",-rightInset,-2); frame.Health:SetPoint("BOTTOM",frame,"BOTTOM",0,powerHeight)
    frame.Power:ClearAllPoints(); frame.Power:SetPoint("TOPLEFT",frame.Health,"BOTTOMLEFT",0,-1); frame.Power:SetPoint("TOPRIGHT",frame.Health,"BOTTOMRIGHT",0,-1); frame.Power:SetPoint("BOTTOM",frame,"BOTTOM",0,2)
    frame.MIUF_PowerHeight=powerHeight
    local nameX,nameY=appearance.nameXOffset or 6,appearance.nameYOffset or 0
    local healthTextWidth=frame.MIUF_UnitType=="raid" and math.min(42,math.floor(width*0.35)) or 42
    frame.NameText:ClearAllPoints(); frame.NameText:SetPoint("LEFT",frame.Health,"LEFT",nameX,nameY); frame.NameText:SetPoint("RIGHT",frame.Health,"RIGHT",nameX-healthTextWidth-6,nameY)
    local healthX,healthY=appearance.healthXOffset or -6,appearance.healthYOffset or 0
    frame.HealthText:ClearAllPoints(); frame.HealthText:SetPoint("RIGHT",frame.Health,"RIGHT",healthX,healthY); frame.HealthText:SetWidth(healthTextWidth)
    if frame.MIUF_UnitType=="party" or frame.MIUF_UnitType=="raid" then
        frame.MIUF_PowerTextLayout={nameX=nameX,nameRightX=nameX-healthTextWidth-6,nameY=nameY,healthX=healthX,healthY=healthY}
    end
    UpdatePowerVisibility(frame)
    ApplyFrameFonts(frame,appearance)
    frame.NameText:SetShown(appearance.showName); frame.HealthText:SetShown(appearance.showHealthText)
    frame.MIUF_ShowRestingIcon=appearance.showRestingIcon~=false
    UpdateHealth(frame); UpdateRestingIndicator(frame)
    ApplyColors(frame,appearance); ApplyIndicatorLayout(frame,appearance); UpdateLeaderIndicator(frame); UpdateRoleIndicator(frame,appearance); UpdateRaidTarget(frame,appearance); UpdateStatusIndicators(frame); UpdateConnectionState(frame)
    if frame.MIUF_UnitType=="party" then ns.RefreshPartyLeaderIndicator() end
end

function ns.CreateMoverResizeHandle(mover)
    local resize=CreateFrame("Button",nil,mover,"BackdropTemplate"); resize:SetSize(14,14); resize:SetPoint("BOTTOMRIGHT"); resize:SetFrameLevel(mover:GetFrameLevel()+10)
    resize:SetBackdrop({bgFile=FLAT,edgeFile=FLAT,edgeSize=1}); resize:SetBackdropColor(0.12,0.12,0.12,0.95); resize:SetBackdropBorderColor(0.8,0.8,0.8,1); resize:EnableMouse(true)
    local grip=resize:CreateFontString(nil,"OVERLAY"); grip:SetFont(FONT,10,"OUTLINE"); grip:SetPoint("CENTER",0,1); grip:SetText("↘")
    mover.MIUF_ResizeHandle=resize
    return resize
end

function ns.GetMoverResizeDimensions(state)
    local scale=UIParent:GetEffectiveScale(); local cx,cy=GetCursorPosition(); cx,cy=cx/scale,cy/scale
    return math.max(state.minW,math.min(state.maxW,cx-state.left)),math.max(state.minH,math.min(state.maxH,state.top-cy))
end

local function CreateMover(frame,labelText,positionKey)
    -- MIUF profiles own these positions, not the client's per-character cache.
    frame:SetDontSavePosition(true)
    frame:SetMovable(true); frame:SetClampedToScreen(true)
    local mover=CreateFrame("Frame",nil,UIParent,"BackdropTemplate"); mover:SetFrameStrata("DIALOG"); mover:SetAllPoints(frame)
    mover:SetMovable(true); mover:SetClampedToScreen(true)
    if frame.MIUF_UnitType=="party" or frame.MIUF_UnitType=="boss" then mover:SetDontSavePosition(true) end
    mover:SetBackdrop({bgFile=FLAT,edgeFile=FLAT,edgeSize=1}); mover:SetBackdropColor(0.05,0.35,0.8,0.28); mover:SetBackdropBorderColor(0.2,0.65,1,1); mover:EnableMouse(true); mover:RegisterForDrag("LeftButton")
    local label=mover:CreateFontString(nil,"OVERLAY"); label:SetFont(FONT,11,"OUTLINE"); label:SetPoint("CENTER"); label:SetText(labelText)
    local dragTarget=frame
    mover:SetScript("OnDragStart",function()
        if InCombatLockdown() then return end
        mover.MIUF_RevertedDrag=nil
        -- Hidden group frames keep their secure visibility; move their independent mover instead.
        local group=frame.MIUF_UnitType=="party" or frame.MIUF_UnitType=="boss"
        dragTarget=group and not frame:IsShown() and mover or frame
        dragTarget:StartMoving()
        if ns.BeginPrecisionPositionDrag then ns.BeginPrecisionPositionDrag(frame.MIUF_UnitType,mover,dragTarget) end
    end)
    mover:SetScript("OnDragStop",function()
        dragTarget:StopMovingOrSizing()
        if mover.MIUF_RevertedDrag then dragTarget=frame; if ns.EndPrecisionPositionDrag then ns.EndPrecisionPositionDrag(mover) end; return end
        if not InCombatLockdown() then
            StageMoverPosition(dragTarget,positionKey)
            if ns.ApplyGroupLayout then ns.ApplyGroupLayout(frame.MIUF_UnitType) end
        end
        if dragTarget==mover then mover:ClearAllPoints(); mover:SetAllPoints(frame) end
        dragTarget=frame
        if ns.EndPrecisionPositionDrag then ns.EndPrecisionPositionDrag(mover) end
    end)
    local resize=ns.CreateMoverResizeHandle(mover)
    resize:SetScript("OnMouseDown",function(_,button)
        if button~="LeftButton" or InCombatLockdown() then return end
        local left,top=frame:GetLeft(),frame:GetTop(); if not left or not top then return end
        resize.MIUF_ResizeState={unitType=frame.MIUF_UnitType,left=left,top=top,minW=100,maxW=600,minH=24,maxH=150}; frame:ClearAllPoints(); frame:SetPoint("TOPLEFT",UIParent,"BOTTOMLEFT",left,top)
        resize:SetScript("OnUpdate",function(handle)
            local s=handle.MIUF_ResizeState; if not s or InCombatLockdown() then return end
            ns.PreviewFrameSize(s.unitType,ns.GetMoverResizeDimensions(s))
        end)
    end)
    resize:SetScript("OnMouseUp",function(handle,button)
        if button~="LeftButton" then return end
        local s=handle.MIUF_ResizeState; handle:SetScript("OnUpdate",nil); handle.MIUF_ResizeState=nil; if not s or InCombatLockdown() then return end
        local settings=ns.ConfigSessionGetFrame(s.unitType)
        settings.size={width=frame:GetWidth(),height=frame:GetHeight()}
        ns.ConfigSessionStageFrame(s.unitType,settings); StageMoverPosition(frame,positionKey)
        ns.PreviewFrameType(s.unitType,settings); if ns.RefreshConfig then ns.RefreshConfig() end
    end)
    mover.MIUF_ResizeHandle=resize; mover:Hide(); frame.MIUF_Mover=mover
    if ns.RegisterPrecisionMover then ns.RegisterPrecisionMover(mover,frame.MIUF_UnitType) end
end

local function CreateUnitFrame(unit,name,unitType,positionKey,registerWatch,storageKey)
    if frames[storageKey or unit] then return frames[storageKey or unit] end
    unitType=unitType or unit; positionKey=positionKey or unit
    local size=ns.GetSize(unitType); local frame=CreateFrame("Button",name,UIParent,"SecureUnitButtonTemplate")
    frame.MIUF_Unit=unit; frame.MIUF_UnitType=unitType; frame.MIUF_PositionKey=positionKey; frame.__unit=unit
    frame:SetAttribute("unit",unit); frame:SetAttribute("*type1","target"); frame:SetAttribute("*type2","togglemenu"); frame:RegisterForClicks("AnyUp"); frame:SetSize(size.width,size.height)
    if VEHICLE_DISPLAY_UNITS[unit] then frame:SetAttribute("toggleForVehicle",true) end
    frame.MIUF_DisplayUnit=ns.GetFrameDisplayUnit(frame)
    frame:SetScript("OnEnter",function(self) GameTooltip_SetDefaultAnchor(GameTooltip,self); GameTooltip:SetUnit(ns.GetFrameDisplayUnit(self)) end); frame:SetScript("OnLeave",function() GameTooltip:Hide() end)
    frame.Background=CreateBackground(frame); frame.Border=CreateBorder(frame)
    local health=CreateFrame("StatusBar",nil,frame); health:SetMinMaxValues(0,100); health:SetStatusBarTexture(FLAT); local hbg=health:CreateTexture(nil,"BACKGROUND"); hbg:SetAllPoints(health); hbg:SetColorTexture(0.08,0.08,0.08,1); frame.Health=health
    local powerParent=frame
    if unitType=="party" or unitType=="raid" then
        powerParent=CreateFrame("Frame",nil,frame); powerParent:SetAllPoints(frame); powerParent:SetFrameLevel(frame:GetFrameLevel())
        frame.MIUF_PowerDisplayGate=powerParent
    end
    local power=CreateFrame("StatusBar",nil,powerParent); power:SetMinMaxValues(0,100); power:SetStatusBarTexture(FLAT); local pbg=power:CreateTexture(nil,"BACKGROUND"); pbg:SetAllPoints(power); pbg:SetColorTexture(0.05,0.05,0.05,1); frame.Power=power
    local nameText=health:CreateFontString(nil,"OVERLAY"); nameText:SetFont(FONT,12,"OUTLINE"); nameText:SetJustifyH("LEFT"); nameText:SetWordWrap(false); frame.NameText=nameText
    local healthText=health:CreateFontString(nil,"OVERLAY"); healthText:SetFont(FONT,11,"OUTLINE"); healthText:SetJustifyH("RIGHT"); frame.HealthText=healthText
    if unitType~="raid" then local portrait=frame:CreateTexture(nil,"ARTWORK"); portrait:SetTexCoord(0.08,0.92,0.08,0.92); frame.Portrait=portrait end
    local markerFrame=CreateFrame("Frame",nil,frame); markerFrame:SetFrameLevel(frame.Border:GetFrameLevel()+5); markerFrame:SetSize(20,20); markerFrame:SetPoint("CENTER",frame,"TOP",0,2); markerFrame:Hide(); frame.RaidTargetIndicatorFrame=markerFrame
    local marker=markerFrame:CreateTexture(nil,"OVERLAY"); marker:SetAllPoints(markerFrame); marker:SetTexture(RAID_TARGET_TEXTURE); frame.RaidTargetIndicator=marker
    if unitType~="pet" and unitType~="boss" then
        local ready=health:CreateTexture(nil,"OVERLAY"); ready:Hide(); frame.ReadyCheckIndicator=ready
        local summon=health:CreateTexture(nil,"OVERLAY"); summon:Hide(); frame.IncomingSummonIndicator=summon
        local resurrection=health:CreateTexture(nil,"OVERLAY"); resurrection:SetAtlas(RESURRECTION_ATLAS,false); resurrection:Hide(); frame.IncomingResurrectionIndicator=resurrection
    end
    if unitType=="party" or unitType=="raid" then local role=health:CreateTexture(nil,"OVERLAY"); role:SetSize(14,14); role:SetPoint("TOPLEFT",health,"TOPLEFT",3,-3); role:Hide(); frame.GroupRoleIndicator=role end
    if unitType=="player" then
        -- Mainline PlayerFrame.xml uses this atlas and a 7x6, 42-frame loop.
        local resting=health:CreateTexture(nil,"OVERLAY"); resting:SetAtlas("UI-HUD-UnitFrame-Player-Rest-Flipbook"); resting:Hide()
        local animation=resting:CreateAnimationGroup(); animation:SetLooping("REPEAT")
        local flipbook=animation:CreateAnimation("FlipBook"); flipbook:SetDuration(1.5); flipbook:SetOrder(1)
        flipbook:SetFlipBookRows(7); flipbook:SetFlipBookColumns(6); flipbook:SetFlipBookFrames(42)
        flipbook:SetFlipBookFrameWidth(0); flipbook:SetFlipBookFrameHeight(0)
        resting.Animation=animation; frame.RestingIndicator=resting
        frame:RegisterEvent("PLAYER_UPDATE_RESTING")
    end

    ns.RegisterFrameUnitEvent(frame,"UNIT_HEALTH",frame); ns.RegisterFrameUnitEvent(frame,"UNIT_MAXHEALTH",frame); ns.RegisterFrameUnitEvent(frame,"UNIT_POWER_UPDATE",frame); ns.RegisterFrameUnitEvent(frame,"UNIT_MAXPOWER",frame); ns.RegisterFrameUnitEvent(frame,"UNIT_DISPLAYPOWER",frame); ns.RegisterFrameUnitEvent(frame,"UNIT_NAME_UPDATE",frame); ns.RegisterFrameUnitEvent(frame,"UNIT_FACTION",frame); ns.RegisterFrameUnitEvent(frame,"UNIT_CONNECTION",frame); ns.RegisterFrameUnitEvent(frame,"UNIT_PORTRAIT_UPDATE",frame); ns.RegisterFrameUnitEvent(frame,"UNIT_MODEL_CHANGED",frame)
    if unitType=="party" or unitType=="raid" or unitType=="player" then
        local leaderLayer=CreateFrame("Frame",nil,frame)
        leaderLayer:SetAllPoints(frame); leaderLayer:SetFrameLevel(frame.Border:GetFrameLevel()+5)
        local leader=leaderLayer:CreateTexture(nil,"OVERLAY")
        -- Match Blizzard's current Party frame artwork without overriding our size.
        leader:SetAtlas("UI-HUD-UnitFrame-Player-Group-LeaderIcon",false); leader:Hide()
        frame.LeaderIndicator=leader
        frame:RegisterEvent("PARTY_LEADER_CHANGED")
    end
    frame:RegisterEvent("PLAYER_ENTERING_WORLD"); frame:RegisterEvent("RAID_TARGET_UPDATE"); frame:RegisterEvent("PLAYER_ROLES_ASSIGNED"); frame:RegisterEvent("GROUP_ROSTER_UPDATE")
    if frame.IncomingSummonIndicator then ns.RegisterFrameUnitEvent(frame,"INCOMING_SUMMON_CHANGED",frame) end
    if frame.IncomingResurrectionIndicator then ns.RegisterFrameUnitEvent(frame,"INCOMING_RESURRECT_CHANGED",frame) end
    ns.RegisterFrameUnitEvent(frame,"UNIT_FLAGS",frame)
    -- Blizzard's compact frames route AFK/player-flag changes through this
    -- unit-filtered event as well as UNIT_FLAGS for other status changes.
    ns.RegisterFrameUnitEvent(frame,"PLAYER_FLAGS_CHANGED",frame)
    if VEHICLE_DISPLAY_UNITS[unit] then
        frame:RegisterEvent("PLAYER_DEAD"); frame:RegisterEvent("PLAYER_ALIVE"); frame:RegisterEvent("PLAYER_UNGHOST")
    end
    -- Boss tokens become available or change after initial creation. Unit watch
    -- handles visibility; this event takes the full UpdateFrame path below.
    if unitType=="boss" then frame:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT") end
    if unit=="target" then frame:RegisterEvent("PLAYER_TARGET_CHANGED") elseif unit=="focus" then frame:RegisterEvent("PLAYER_FOCUS_CHANGED") elseif unit=="pet" then frame:RegisterUnitEvent("UNIT_PET","player") elseif unit=="targettarget" then frame:RegisterUnitEvent("UNIT_TARGET","target") end

    if VEHICLE_DISPLAY_UNITS[unit] then
        for event in pairs(VEHICLE_EVENTS) do
            if event=="VEHICLE_UPDATE" then frame:RegisterEvent(event)
            else frame:RegisterUnitEvent(event,"player") end
        end
    end

    frame:SetScript("OnEvent",function(self,event)
        local displayUnit=ns.GetFrameDisplayUnit(self)
        if displayUnit~=self.MIUF_DisplayUnit or (VEHICLE_DISPLAY_UNITS[self.MIUF_Unit] and VEHICLE_EVENTS[event]) then
            self.MIUF_DisplayUnit=displayUnit
            UpdateFrame(self)
            if ns.UpdateFrameAuraUnit then ns.UpdateFrameAuraUnit(self) end
            if ns.UpdateFrameCastbar then ns.UpdateFrameCastbar(self) end
            if GameTooltip:IsOwned(self) then GameTooltip:SetUnit(displayUnit) end
            return
        end
        if event=="UNIT_HEALTH" or event=="UNIT_MAXHEALTH" or event=="UNIT_FLAGS" or event=="PLAYER_FLAGS_CHANGED" then
            UpdateHealth(self); ApplyColors(self,ns.GetAppearance(self.MIUF_UnitType) or {}); UpdateConnectionState(self)
        elseif event=="PARTY_LEADER_CHANGED" then UpdateLeaderIndicator(self)
        elseif event=="PLAYER_UPDATE_RESTING" then UpdateRestingIndicator(self)
        elseif event=="UNIT_POWER_UPDATE" or event=="UNIT_MAXPOWER" then UpdatePower(self)
        elseif event=="UNIT_DISPLAYPOWER" then UpdatePower(self); ApplyColors(self,ns.GetAppearance(self.MIUF_UnitType) or {}); UpdateConnectionState(self)
        elseif event=="UNIT_NAME_UPDATE" then UpdateName(self)
        elseif event=="UNIT_PORTRAIT_UPDATE" or event=="UNIT_MODEL_CHANGED" then UpdatePortrait(self)
        elseif event=="RAID_TARGET_UPDATE" then UpdateRaidTarget(self)
        elseif event=="INCOMING_SUMMON_CHANGED" then UpdateIncomingSummonIndicator(self)
        elseif event=="INCOMING_RESURRECT_CHANGED" then UpdateIncomingResurrectionIndicator(self)
        elseif event=="GROUP_ROSTER_UPDATE" and (self.MIUF_UnitType=="party" or self.MIUF_UnitType=="raid") then UpdateFrame(self)
        elseif event=="PLAYER_ROLES_ASSIGNED" or event=="GROUP_ROSTER_UPDATE" then UpdatePowerVisibility(self); UpdateLeaderIndicator(self); UpdateRoleIndicator(self); ApplyColors(self,ns.GetAppearance(self.MIUF_UnitType) or {}); UpdateConnectionState(self)
        elseif event=="UNIT_CONNECTION" then UpdateFrame(self)
        elseif event=="UNIT_FACTION" then ApplyColors(self,ns.GetAppearance(self.MIUF_UnitType) or {}); UpdateConnectionState(self)
        elseif event=="UNIT_TARGET" and self.MIUF_Unit=="targettarget" then UpdateFrame(self)
        else UpdateFrame(self) end
    end)

    -- Blizzard continuously reconciles target-of-target data instead of trusting
    -- UNIT_TARGET alone. RegisterUnitWatch remains responsible for secure visibility;
    -- this updater only keeps the displayed unit data synchronized.
    if unit=="targettarget" then
        local totElapsed=0
        frame:SetScript("OnUpdate",function(self,elapsed)
            totElapsed=totElapsed+elapsed
            if totElapsed<0.10 then return end
            totElapsed=0
            if UnitExists("target") and UnitExists("targettarget") then UpdateFrame(self,false) end
        end)
    end

    if unitType~="raid" then
        local moverLabel=(unitType=="party" or unitType=="boss") and unit or unitType; CreateMover(frame,moverLabel,positionKey); ApplyPosition(positionKey,frame)
    end
    ApplyFrameState(frame,BuildFrameState(unitType)); UpdateFrame(frame)
    if registerWatch~=false then
        if unitType=="party" and unit:match("^party%d+$") and RegisterStateDriver then RegisterStateDriver(frame,"visibility",string.format("[group:raid] hide; [group:party,@%s,exists] show; hide",unit)) else RegisterUnitWatch(frame) end
    else frame:Hide() end
    frames[storageKey or unit]=frame
    if (unitType=="party" or unitType=="raid") and unit~="player" then rangeFrames[#rangeFrames+1]=frame end
    return frame
end

-- On cold login, bundled fonts can still be unavailable at PLAYER_ENTERING_WORLD.
-- Retry failed regions when the initial loading screen closes, including hidden
-- frames. The existing updater continues if this lifecycle event is still early.
local fontStartupEvents=CreateFrame("Frame")
fontStartupEvents:RegisterEvent("LOADING_SCREEN_DISABLED")
fontStartupEvents:SetScript("OnEvent",function(self,event)
    self:UnregisterEvent(event)
    RetryPendingFonts()
end)

local readyCheckEvents=CreateFrame("Frame")
readyCheckEvents:RegisterEvent("READY_CHECK")
readyCheckEvents:RegisterEvent("READY_CHECK_CONFIRM")
readyCheckEvents:RegisterEvent("READY_CHECK_FINISHED")
readyCheckEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
readyCheckEvents:SetScript("OnEvent",function(_,event)
    if event=="READY_CHECK" then
        readyCheckFinishGeneration=readyCheckFinishGeneration+1
        readyCheckDisplayActive=true
    elseif event=="READY_CHECK_FINISHED" then
        readyCheckFinishGeneration=readyCheckFinishGeneration+1
        local generation=readyCheckFinishGeneration
        readyCheckDisplayActive="finished"
        C_Timer.After(11,function()
            if generation~=readyCheckFinishGeneration then return end
            readyCheckDisplayActive=false
            for _,frame in pairs(frames) do UpdateReadyCheckIndicator(frame) end
        end)
    elseif event=="PLAYER_ENTERING_WORLD" then
        local timeLeft=GetReadyCheckTimeLeft()
        readyCheckDisplayActive=canaccessvalue(timeLeft) and timeLeft>0
    elseif not readyCheckDisplayActive then
        return
    end
    for _,frame in pairs(frames) do UpdateReadyCheckIndicator(frame) end
end)

function ns.ApplySavedFrameSettings(unitType)
    if InCombatLockdown() then return false end
    local state=BuildFrameState(unitType)
    for _,frame in pairs(frames) do if frame.MIUF_UnitType==unitType then ApplyFrameState(frame,state) end end
    return true
end

function ns.ApplySavedFramePositions(positionChanges)
    if InCombatLockdown() then return false end
    for _,frame in pairs(frames) do
        local key=frame.MIUF_PositionKey or frame.MIUF_Unit
        if positionChanges[key] then ApplyPosition(key,frame) end
    end
    return true
end

function ns.ApplyFrameType(unitType)
    if unitType=="raid" and InCombatLockdown() then return end
    local overrides=ns.ConfigSessionIsActive and ns.ConfigSessionIsActive() and ns.ConfigSessionGetFrame(unitType)
    local state=BuildFrameState(unitType,overrides); for _,frame in pairs(frames) do if frame.MIUF_UnitType==unitType then ApplyFrameState(frame,state) end end
    if not InCombatLockdown() and ns.ApplyGroupLayout then ns.ApplyGroupLayout(unitType) end
end
ns.ApplySize=ns.ApplyFrameType

function ns.PreviewFrameType(unitType,overrides)
    if InCombatLockdown() then return end
    local state=BuildFrameState(unitType,overrides); for _,frame in pairs(frames) do if frame.MIUF_UnitType==unitType then ApplyFrameState(frame,state) end end
    if ns.ApplyGroupLayout then ns.ApplyGroupLayout(unitType) end
end
function ns.PreviewFrameSize(unitType,width,height)
    local settings=ns.ConfigSessionGetFrame(unitType)
    settings.size={width=width,height=height}
    ns.PreviewFrameType(unitType,settings)
end
function ns.IsUnitTypePreviewEnabled(unitType) return previewEnabled[unitType]~=false end
function ns.ClearEnabledPreviews() previewEnabled={} end

function ns.SetFrameMoversLocked(locked)
    for _,frame in pairs(frames) do
        local mover=frame.MIUF_Mover
        if mover then
            local unitType=frame.MIUF_UnitType; local groupOwnerMismatch=unitType=="party" and ns.partyFrameMoverOwner~=frame; local bossOwnerMismatch=unitType=="boss" and frame.MIUF_Unit~="boss1"
            if locked or previewEnabled[unitType]==false or not ns.IsFrameTypeEnabled(unitType) or groupOwnerMismatch or bossOwnerMismatch then mover:Hide() else mover:Show() end
        end
    end
    if ns.UpdateLockMoversButton then ns.UpdateLockMoversButton() end
end
function ns.PreviewUnitTypeMovers(unitType,enabled) previewEnabled[unitType]=enabled and true or false; ns.SetFrameMoversLocked(ns.AreFrameMoversLocked()) end
function ns.SetMoversLocked(locked) ns.SetFrameMoversLocked(locked); if ns.SetAuraMoversLocked then ns.SetAuraMoversLocked(locked) end end
function ns.ResetLayout() for _,frame in pairs(frames) do ApplyPosition(frame.MIUF_PositionKey or frame.MIUF_Unit,frame) end; for unitType in pairs(ns.defaultSizes) do ns.ApplyFrameType(unitType) end; ns.SetFrameMoversLocked(true) end

function ns.SpawnAllFrames()
    if InCombatLockdown() then return end
    if ns.IsFrameTypeEnabled("player") then CreateUnitFrame("player","MIUF_Player") end
    if ns.IsFrameTypeEnabled("target") then CreateUnitFrame("target","MIUF_Target") end
    if ns.IsFrameTypeEnabled("focus") then CreateUnitFrame("focus","MIUF_Focus") end
    if ns.IsFrameTypeEnabled("pet") then CreateUnitFrame("pet","MIUF_Pet") end
    if ns.IsFrameTypeEnabled("targettarget") then CreateUnitFrame("targettarget","MIUF_TargetTarget") end
    if ns.IsFrameTypeEnabled("party") then
        for i=1,4 do local unit="party"..i; CreateUnitFrame(unit,"MIUF_Party"..i,"party","party1") end
        CreateUnitFrame("player","MIUF_PartyPlayer","party","party1",false,"partyplayer")
    end
    if ns.IsFrameTypeEnabled("boss") then for i=1,5 do local unit="boss"..i; CreateUnitFrame(unit,"MIUF_Boss"..i,"boss","boss1") end end
    if ns.IsFrameTypeEnabled("raid") then
        local anchor=ns.GetRaidAnchor()
        local capacity=ns.GetGroupLayout("raid").legacy40 and 40 or 30
        for i=1,capacity do
            local frame=CreateUnitFrame("raid"..i,"MIUF_Raid"..i,"raid","raid")
            frame:SetParent(anchor)
        end
        ns.ApplyRaidLayout()
    end
    if ns.ApplyPartyLayout then ns.ApplyPartyLayout() end; if ns.ApplyBossLayout then ns.ApplyBossLayout() end; ns.SetFrameMoversLocked(ns.AreFrameMoversLocked())
end

-- Retain secure identities, event subscriptions and attachments across cycles.
-- Only visibility ownership changes; creation goes through the complete spawn
-- wrapper chain (click casting, castbars and auras) before activation.
function ns.ApplySavedEnabledStates()
    if InCombatLockdown() then return false end
    ns.SpawnAllFrames()
    for _,frame in pairs(frames) do
        local unitType,unit=frame.MIUF_UnitType,frame.MIUF_Unit
        local enabled=ns.IsFrameTypeEnabled(unitType)
        UnregisterUnitWatch(frame)
        if unitType=="party" and unit:match("^party%d+$") then
            UnregisterStateDriver(frame,"visibility")
        end
        if enabled then
            ApplyFrameState(frame,BuildFrameState(unitType))
            if unitType~="raid" then ApplyPosition(frame.MIUF_PositionKey,frame) end
            UpdateFrame(frame)
            if unitType=="party" then
                if unit~="player" then
                    RegisterStateDriver(frame,"visibility",string.format("[group:raid] hide; [group:party,@%s,exists] show; hide",unit))
                end
            else RegisterUnitWatch(frame) end
            if ns.UpdateFrameCastbar then ns.UpdateFrameCastbar(frame) end
        else
            frame:Hide()
        end
        if ns.UpdateFrameAuraUnit then ns.UpdateFrameAuraUnit(frame) end
    end
    ns.ApplyPartyLayout()
    ns.ApplyBossLayout()
    ns.ApplyRaidLayout(true)
    ns.SetMoversLocked(ns.AreFrameMoversLocked())
    return true
end

local rangeWatcher=CreateFrame("Frame"); local rangeElapsed=0
rangeWatcher:SetScript("OnUpdate",function(_,elapsed)
    rangeElapsed=rangeElapsed+elapsed; if rangeElapsed<0.25 then return end; rangeElapsed=0
    RetryPendingFonts()
    for index=1,#rangeFrames do
        local frame=rangeFrames[index]
        if frame:IsShown() and UnitExists(frame.MIUF_Unit) then
            local inRange=UnitInRange(frame.MIUF_Unit)
            if frame.SetAlphaFromBoolean then
                frame:SetAlphaFromBoolean(inRange,1,0.55)
            elseif not canaccessvalue or canaccessvalue(inRange) then
                local alpha=inRange and 1 or 0.55
                if frame.MIUF_RangeAlpha~=alpha then frame:SetAlpha(alpha); frame.MIUF_RangeAlpha=alpha end
            end
        end
    end
end)

local combatWatcher=CreateFrame("Frame"); combatWatcher:RegisterEvent("PLAYER_REGEN_DISABLED"); combatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
combatWatcher:SetScript("OnEvent",function(_,event)
    if event=="PLAYER_REGEN_DISABLED" then ns.SetFrameMoversLocked(true)
    else ns.SetFrameMoversLocked(ns.AreFrameMoversLocked()) end
end)
