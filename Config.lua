local ADDON_NAME, ns = ...

local internalHide, collapsed, closing = false, false, false
local collapsedBar
local MEDIA = "Interface\\Buttons\\WHITE8x8"
local FONT = "Fonts\\FRIZQT__.TTF"
local Skin = {
    background={0.035,0.039,0.040,0.98}, surface={0.070,0.076,0.077,1},
    border={0.18,0.20,0.20,1}, text={0.86,0.85,0.81,1}, muted={0.56,0.58,0.57,1},
    accent={0.22,0.43,0.41,1}, selected={0.10,0.23,0.22,1}, hover={0.14,0.29,0.27,1},
    hoverBorder={0.32,0.54,0.50,1},
    disabled={0.36,0.38,0.37,1},
}
function Skin.Panel(frame, color)
    frame:SetBackdrop({bgFile=MEDIA,edgeFile=MEDIA,edgeSize=1})
    frame:SetBackdropColor(unpack(color or Skin.surface)); frame:SetBackdropBorderColor(unpack(Skin.border))
end
function Skin.Paint(button)
    local selected=button.MIUF_Selected
    local disabled=button.IsEnabled and not button:IsEnabled() and not selected
    button:SetBackdropColor(unpack(disabled and Skin.background or (button.MIUF_Hover and Skin.hover or (selected and Skin.selected or Skin.surface))))
    button:SetBackdropBorderColor(unpack(disabled and Skin.border or (button.MIUF_Hover and Skin.hoverBorder or (selected and Skin.accent or Skin.border))))
    local label=button.MIUF_SkinLabel or button:GetFontString()
    if label then label:SetTextColor(unpack(disabled and Skin.disabled or Skin.text)) end
    if button.MIUF_Accent then button.MIUF_Accent:SetShown(selected) end
end
function Skin.Button(button)
    Skin.Panel(button)
    button:HookScript("OnEnter",function(self) self.MIUF_Hover=true; Skin.Paint(self) end)
    button:HookScript("OnLeave",function(self) self.MIUF_Hover=nil; Skin.Paint(self) end)
    button:HookScript("OnEnable",Skin.Paint); button:HookScript("OnDisable",Skin.Paint)
    function button:SetSelected(selected) self.MIUF_Selected=selected; Skin.Paint(self) end
    Skin.Paint(button)
end
function Skin.Check(check)
    for _,method in ipairs({"GetNormalTexture","GetPushedTexture","GetDisabledTexture"}) do
        local texture=check[method] and check[method](check)
        if texture then texture:SetVertexColor(unpack(Skin.muted)) end
    end
    local checked=check.GetCheckedTexture and check:GetCheckedTexture()
    if checked then checked:SetVertexColor(unpack(Skin.accent)) end
    local hover=check.GetHighlightTexture and check:GetHighlightTexture()
    if hover then hover:SetVertexColor(unpack(Skin.accent)) end
    local disabled=check.GetDisabledCheckedTexture and check:GetDisabledCheckedTexture()
    if disabled then disabled:SetVertexColor(unpack(Skin.disabled)) end
end
function Skin.Edit(box)
    for _,key in ipairs({"Left","Middle","Right"}) do if box[key] then box[key]:SetVertexColor(unpack(Skin.muted)) end end
    box:SetTextColor(unpack(Skin.text))
end
local FRAME_TYPES = { "player", "target", "focus", "pet", "targettarget", "party", "boss", "raid" }
local DISPLAY_NAMES = { player="Player", target="Target", focus="Focus", pet="Pet", targettarget="Target of Target", party="Party", boss="Boss", raid="Raid" }
local AURA_TYPES = { "buffs", "debuffs", "defensives" }
local AURA_NAMES = { buffs="Buffs", debuffs="Debuffs", defensives="Defensives" }
local AURA_FIELDS = { buffs="PlayerBuffs", debuffs="CombatDebuffs", defensives="ExternalDefensives" }
local ANCHOR_NAMES = { TOP="Top", BOTTOM="Bottom" }
local GROWTH_NAMES = { RIGHT="Right", LEFT="Left" }
local ANCHOR_ORDER = { "TOP", "BOTTOM" }
local GROWTH_ORDER = { "RIGHT", "LEFT" }
local GROUP_ORIENTATION_NAMES = { VERTICAL="Vertical", HORIZONTAL="Horizontal" }
local GROUP_ORIENTATION_ORDER = { "VERTICAL", "HORIZONTAL" }

local selectedType, selectedAura, selectedPage = "player", "buffs", "frames"
local config, framesPage, aurasPage, profilesPage, trackedBuffWindow
local widthSlider, heightSlider, powerSlider, fontSlider, portraitSlider, bgSlider, borderSlider
local nameXSlider, nameYSlider, healthXSlider, healthYSlider
local roleXSlider, roleYSlider, roleSizeSlider, raidXSlider, raidYSlider, raidSizeSlider
local statusXSlider, statusYSlider, statusSizeSlider
local restingControls = {}
local castbarControls = {}
-- Presentation state only; configuration values stay in ConfigSession.
local frameUI = { category="Layout", categories={}, units={}, sections={} }
local FRAME_CATEGORIES = { "Layout", "Text", "Appearance", "Indicators", "Auras" }
local FRAME_SUPPORT = {
    castbar={player=true,target=true,focus=true,boss=true},
    castbarGeometry={player=true,target=true},
    portrait={player=true,target=true,focus=true,pet=true,targettarget=true,party=true,boss=true},
    group={party=true,boss=true,raid=true},
    role={party=true,raid=true},
    leader={party=true,raid=true},
    resting={player=true},
    status={player=true,target=true,focus=true,targettarget=true,party=true,raid=true},
    auras={player=true,target=true,focus=true,targettarget=true,party=true,raid=true},
}
local auraSizeSlider, auraCountSlider, auraSpacingSlider, auraXSlider, auraYSlider
local selectedLabel, statusText, applyChangesButton, frameLockButton, auraLockButton
local revertChangesButton
local nameButton, healthTextButton, portraitButton, sideButton
local textureButton, textureMenu, healthColorButton, powerColorButton, fontButton, fontMenu
local auraLabel, auraEnableButton, auraTextButton, auraAnchorButton, auraGrowthButton
local frameTab, profileTab
local partyLayoutPanel, partyOrientationButton, partyDirectionButton, partySpacingSlider, partyIncludePlayerButton
local auraButtons = {}
local auraUI = {}
local buffFilterPanel, seenBuffButtons, trackedBuffButtons = nil, {}, {}
local manageTrackedButton
local profileCurrentLabel, profileCharacterLabel, profileNameBox, profileActionStatus
local profileButtons = {}
local selectedProfileName
local refreshing = false
local working, auraWorking, groupWorking = {}, {}, {}
local raidPreviewControls
local raidLegacyButton
local MarkPending
local previewFrameType
local previewAuraUnitType, previewAuraType

local function Round(v) return math.floor((v or 0) + 0.5) end
local function Cycle(current, order)
    for i,v in ipairs(order) do if v==current then return order[(i % #order)+1] end end
    return order[1]
end
local function DisplayName(catalog,key,fallback)
    local entry=catalog and catalog[key]
    return (entry and entry.name) or fallback or key
end

local function MakeButton(parent,text,width,height)
    local b=CreateFrame("Button",nil,parent,"BackdropTemplate")
    b:SetSize(width,height)

    local label=b:CreateFontString(nil,"OVERLAY")
    label:SetFont(FONT,11,"OUTLINE")
    label:SetTextColor(unpack(Skin.text))
    label:SetPoint("CENTER")

    b.MIUF_SkinLabel=label

    function b:SetText(value)
        label:SetText(value)
    end

    function b:GetText()
        return label:GetText()
    end

    function b:GetFontString()
        return label
    end

    b:SetText(text)
    Skin.Button(b)
    return b
end

local function MakeSlider(parent,name,label,minValue,maxValue,step,width)
    local slider=CreateFrame("Slider","MIUF_"..name.."Slider",parent,"OptionsSliderTemplate")
    slider:SetMinMaxValues(minValue,maxValue); slider:SetValueStep(step); slider:SetObeyStepOnDrag(true); slider:SetWidth(width or 235)
    local text,low,high=_G[slider:GetName().."Text"],_G[slider:GetName().."Low"],_G[slider:GetName().."High"]
    if text then text:SetText(label) end; if low then low:SetText(tostring(minValue)) end; if high then high:SetText(tostring(maxValue)) end
    if text then text:SetTextColor(unpack(Skin.text)) end
    if low then low:SetTextColor(unpack(Skin.muted)) end; if high then high:SetTextColor(unpack(Skin.muted)) end
    if slider.SetBackdropColor then slider:SetBackdropColor(unpack(Skin.surface)); slider:SetBackdropBorderColor(unpack(Skin.border)) end
    local thumb=slider.GetThumbTexture and slider:GetThumbTexture()
    if thumb then thumb:SetVertexColor(unpack(Skin.accent)) end
    function slider:SetLimits(minimum, maximum)
        minValue, maxValue = minimum, maximum
        self:SetMinMaxValues(minValue,maxValue)
        if low then low:SetText(tostring(minValue)) end
        if high then high:SetText(tostring(maxValue)) end
    end
    local box=CreateFrame("EditBox",nil,parent,"InputBoxTemplate"); box:SetSize(52,20); box:SetAutoFocus(false); box:SetJustifyH("CENTER"); box:SetPoint("TOP",slider,"BOTTOM",0,-1); slider.ValueBox=box
    Skin.Edit(box)
    local function Format(v) return step and step<1 and string.format("%.2f",v) or tostring(Round(v)) end
    local function Clamp(v)
        v=math.max(minValue,math.min(maxValue,v)); if step and step>0 then v=minValue+math.floor(((v-minValue)/step)+0.5)*step end
        return math.max(minValue,math.min(maxValue,v))
    end
    slider:SetScript("OnValueChanged",function(self,v) if not box:HasFocus() then box:SetText(Format(v)) end end)
    local function Commit()
        local v=tonumber(box:GetText()); if v then slider:SetValue(Clamp(v)) end; box:SetText(Format(slider:GetValue())); box:ClearFocus()
    end
    box:SetScript("OnEnterPressed",Commit); box:SetScript("OnEscapePressed",function() box:SetText(Format(slider:GetValue())); box:ClearFocus() end)
    box:SetScript("OnEditFocusGained",function(self) self:HighlightText() end); box:SetScript("OnEditFocusLost",Commit)
    return slider
end

local function MakeSection(parent,title,width,height)
    local section=CreateFrame("Frame",nil,parent,"BackdropTemplate"); section:SetSize(width,height)
    Skin.Panel(section)
    local label=section:CreateFontString(nil,"OVERLAY"); label:SetFont(FONT,12,"OUTLINE"); label:SetTextColor(unpack(Skin.text)); label:SetPoint("TOPLEFT",10,-8); label:SetText(title); section.Title=label
    return section
end

local function ClearStatusIconPreview()
    local check=frameUI.statusPreview
    if check then check:SetChecked(false); check:SetScript("OnUpdate",nil) end
    if ns.ClearTemporaryStatusPreview then ns.ClearTemporaryStatusPreview() end
end

local function RefreshStatusIconPreview()
    local check=frameUI.statusPreview
    if not check or not check:GetChecked() then return end
    if not config:IsShown() or selectedPage~="frames" or frameUI.category~="Indicators"
        or not FRAME_SUPPORT.status[selectedType] then
        ClearStatusIconPreview(); return
    end
    ns.UpdateTemporaryStatusPreview(selectedType,working)
end

local function ClearCastbarPreview()
    if castbarControls.preview then castbarControls.preview:SetChecked(false) end
    if ns.ClearCastbarPreview then ns.ClearCastbarPreview() end
end

local function RefreshCastbarPreview()
    local check=castbarControls.preview
    if not check then return end
    local settings=ns.ConfigSessionGetFrame(selectedType).castbar
    local available=ns.ConfigSessionIsActive() and selectedPage=="frames"
        and FRAME_SUPPORT.castbarGeometry[selectedType]
        and not InCombatLockdown() and settings and settings.enabled~=false
        and ns.ConfigSessionGetEnabled(selectedType)
    check:SetEnabled(available and true or false)
    if not available then ClearCastbarPreview()
    elseif check:GetChecked() then ns.SetCastbarPreview(selectedType) end
end

local function RestoreFramePreview(unitType)
    ClearCastbarPreview()
    if InCombatLockdown() then return end
    unitType=unitType or previewFrameType
    if unitType and ns.ResetGroupPreview then ns.ResetGroupPreview(unitType) end
    if unitType and ns.ApplyFrameType then ns.ApplyFrameType(unitType) end
    if previewFrameType==unitType then previewFrameType=nil end
end

local function PreviewGroupControls(sizeOverride)
    if refreshing or InCombatLockdown() or (selectedType~="party" and selectedType~="boss") then return end
    if ns.PreviewGroupLayout then ns.PreviewGroupLayout(selectedType,groupWorking,sizeOverride) end
    previewFrameType=selectedType
end

local function PreviewFrameSliders()
    if refreshing then return end
    local width,height=Round(widthSlider:GetValue()),Round(heightSlider:GetValue())
    local powerPercent=Round(powerSlider:GetValue())
    local portraitPercent=Round(portraitSlider:GetValue())
    local fontSize=Round(fontSlider:GetValue())
    local backgroundOpacity=Round(bgSlider:GetValue())
    local borderOpacity=Round(borderSlider:GetValue())
    local nameX,nameY=Round(nameXSlider:GetValue()),Round(nameYSlider:GetValue())
    local healthX,healthY=Round(healthXSlider:GetValue()),Round(healthYSlider:GetValue())
    local roleX,roleY=Round(roleXSlider:GetValue()),Round(roleYSlider:GetValue())
    local raidX,raidY=Round(raidXSlider:GetValue()),Round(raidYSlider:GetValue())
    local raidSize=Round(raidSizeSlider:GetValue())
    local statusX,statusY=Round(statusXSlider:GetValue()),Round(statusYSlider:GetValue())

    working.fontSize=fontSize; working.portraitPercent=portraitPercent
    working.backgroundOpacity=backgroundOpacity; working.borderOpacity=borderOpacity
    working.nameXOffset=nameX; working.nameYOffset=nameY
    working.healthXOffset=healthX; working.healthYOffset=healthY
    working.roleIconXOffset=roleX; working.roleIconYOffset=roleY
    working.roleIconSize=Round(roleSizeSlider:GetValue())
    if selectedType=="party" or selectedType=="raid" then
        local leader=frameUI.sections.leader
        working.leaderIconXOffset=Round(leader.X:GetValue()); working.leaderIconYOffset=Round(leader.Y:GetValue())
        working.leaderIconSize=Round(leader.Size:GetValue())
    end
    working.raidMarkerXOffset=raidX; working.raidMarkerYOffset=raidY; working.raidMarkerSize=raidSize
    working.statusIconXOffset=statusX; working.statusIconYOffset=statusY; working.statusIconSize=Round(statusSizeSlider:GetValue())
    if selectedType=="player" then
        working.restingIconXOffset=Round(restingControls.X:GetValue()); working.restingIconYOffset=Round(restingControls.Y:GetValue())
        working.restingIconSize=Round(restingControls.Size:GetValue())
    end
    if selectedType=="party" or selectedType=="boss" then groupWorking.spacing=Round(partySpacingSlider:GetValue()) end

    local castbar=ns.ConfigSessionGetFrame(selectedType).castbar
    if castbar and castbar.width==0 then
        refreshing=true; castbarControls.width:SetValue(width); refreshing=false
    end
    ns.ConfigSessionStageFrame(selectedType,{size={width=width,height=height},powerPercent=powerPercent,appearance=working,castbar=castbar})
    MarkPending("Configuration changes are pending.")
    if selectedType=="raid" then ns.UpdateRaidPreview() end
    if InCombatLockdown() or not ns.PreviewFrameType then return end
    ns.PreviewFrameType(selectedType,{
        -- Raid ghosts preview structural sizing; keep live button dimensions
        -- aligned with their saved geometry until Apply/reload.
        size=selectedType=="raid" and ns.GetSize("raid") or {width=width,height=height},
        powerPercent=powerPercent,
        appearance=working,
        castbar=castbar,
    })
    PreviewGroupControls({width=width,height=height})
    if selectedType=="raid" then ns.UpdateRaidPreview() end
    previewFrameType=selectedType
    RefreshStatusIconPreview()
end

local function IsAurasSelected()
    return selectedPage=="frames" and frameUI.category=="Auras"
end

local function GetAuraAnchor(layout)
    local anchor=layout.anchor=="BOTTOM" and "BOTTOM" or "TOP"
    local growth=layout.growth=="LEFT" and "LEFT" or "RIGHT"
    if anchor=="TOP" then
        if growth=="LEFT" then return "BOTTOMRIGHT","TOPRIGHT" end
        return "BOTTOMLEFT","TOPLEFT"
    end
    if growth=="LEFT" then return "TOPRIGHT","BOTTOMRIGHT" end
    return "TOPLEFT","BOTTOMLEFT"
end

local function ApplyAuraVisual(unitType,auraType,layout)
    if InCombatLockdown() or not ns.frames or not layout then return end
    if auraType=="buffs" then ns.PreviewBuffFiltering(unitType,layout) end
    if unitType=="raid" and auraType=="debuffs" and ns.PreviewRaidDebuffLayout then ns.PreviewRaidDebuffLayout(layout); return end
    local field=AURA_FIELDS[auraType]; if not field then return end
    local point,relativePoint=GetAuraAnchor(layout)
    local savedLayout=ns.GetAuraLayout(unitType,auraType)
    local iconSize=math.max(1,tonumber(savedLayout and savedLayout.iconSize) or 16)
    local spacing=math.max(0,tonumber(layout.spacing) or 0)
    local maxCount=math.max(1,tonumber(layout.maxCount) or 1)
    for _,frame in pairs(ns.frames) do
        if frame.MIUF_UnitType==unitType then
            local container=frame[field]
            if container then
                container.size=iconSize; container.elementSpacing=spacing; container.lineSpacing=spacing; container.maxFrameCount=maxCount
                if container.MIUF_GroupKey and container.SetAuraGroupLayout then
                    container:SetAuraGroupLayout(container.MIUF_GroupKey,{elementWidth=iconSize,elementHeight=iconSize,elementSpacing=spacing,lineSpacing=spacing,maxFrameCount=maxCount})
                end
                if container.MIUF_Anchor then
                    container.MIUF_Anchor:SetHeight((iconSize*2)+spacing+4)
                    container.MIUF_Anchor:ClearAllPoints(); container.MIUF_Anchor:SetPoint(point,frame,relativePoint,layout.xOffset or 0,layout.yOffset or 0)
                end
                if container.ForceUpdate then container:ForceUpdate() end
            end
        end
    end
end

local function ClearAuraPositionPreview()
    if ns.ClearAuraMoverPreview then ns.ClearAuraMoverPreview() end
    if auraLockButton then auraLockButton:SetText("Preview Position") end
end

local function RefreshAuraPositionPreview()
    local context=config and ns.ConfigSessionIsActive() and selectedPage=="frames" and not InCombatLockdown()
        and ns.ConfigSessionGetEnabled(selectedType)
    if not context then ClearAuraPositionPreview()
    else ns.RefreshAuraMoverPreview() end
    local layout=IsAurasSelected() and ns.ConfigSessionGetAura(selectedType,selectedAura)
    local available=context and layout and layout.enabled~=false
    if auraLockButton then
        auraLockButton:SetEnabled(available and true or false)
        auraLockButton:SetText(ns.IsAuraMoverPreviewEnabled(selectedType,selectedAura) and "End Preview" or "Preview Position")
    end
end

hooksecurefunc(ns,"SetAuraMoversLockedState",function(locked) if locked then ClearAuraPositionPreview() end end)
hooksecurefunc(ns,"SetActiveProfile",function() ClearAuraPositionPreview(); ClearCastbarPreview() end)
hooksecurefunc(ns,"ResetAllSettings",function() ClearAuraPositionPreview(); ClearCastbarPreview() end)

local function RestoreAuraPreview(keepMovers)
    if not keepMovers then ClearAuraPositionPreview() end
    if InCombatLockdown() then return end
    if previewAuraUnitType and previewAuraType then
        local layout=keepMovers and ns.IsAuraMoverPreviewEnabled(previewAuraUnitType,previewAuraType)
            and ns.ConfigSessionGetAura(previewAuraUnitType,previewAuraType) or ns.GetAuraLayout(previewAuraUnitType,previewAuraType)
        ApplyAuraVisual(previewAuraUnitType,previewAuraType,layout)
    end
    previewAuraUnitType,previewAuraType=nil,nil
end

local function AuraAvailable(unitType,auraType)
    if unitType=="boss" then return false end
    if unitType=="raid" then return auraType=="debuffs" end
    if auraType=="buffs" then return unitType=="player" or unitType=="target" or unitType=="focus" or unitType=="party" or unitType=="targettarget" end
    if auraType=="debuffs" then return unitType~="pet" end
    if auraType=="defensives" then return unitType=="player" or unitType=="party" end
    return false
end

local function PreviewAuraSliders()
    if refreshing or InCombatLockdown() or not AuraAvailable(selectedType,selectedAura) then return end
    auraWorking.maxCount=Round(auraCountSlider:GetValue()); auraWorking.spacing=Round(auraSpacingSlider:GetValue())
    auraWorking.xOffset=Round(auraXSlider:GetValue()); auraWorking.yOffset=Round(auraYSlider:GetValue())
    ApplyAuraVisual(selectedType,selectedAura,auraWorking)
    -- Group previews can own aura anchors on ghosts outside ns.frames.
    -- Reposition those existing anchors from the staged layout as well.
    if selectedType=="party" or selectedType=="raid" then ns.RefreshAuraMoverPreview() end
    previewAuraUnitType,previewAuraType=selectedType,selectedAura
end

local function ChooseAvailableAura()
    if AuraAvailable(selectedType,selectedAura) then return end
    for _,auraType in ipairs(AURA_TYPES) do if AuraAvailable(selectedType,auraType) then selectedAura=auraType; return end end
end

MarkPending=function(message)
    local dirty=ns.ConfigSessionIsDirty()
    if applyChangesButton then applyChangesButton:SetEnabled(dirty and not InCombatLockdown()) end
    if revertChangesButton then revertChangesButton:SetEnabled(dirty and not InCombatLockdown()) end
    if statusText then
        statusText:SetText(InCombatLockdown() and "Apply and Revert are unavailable during combat."
            or (dirty and ((message or "Changes are pending.").."  Click Apply Changes when ready.")
            or "No pending changes."))
    end
end

local function CopyWorking()
    working=ns.ConfigSessionGetFrame(selectedType).appearance
    ChooseAvailableAura(); auraWorking=ns.ConfigSessionGetAura(selectedType,selectedAura) or {}
    groupWorking=ns.ConfigSessionGetGroup(selectedType)
end

local function StageGroupControls()
    if refreshing or (selectedType~="party" and selectedType~="boss" and selectedType~="raid") then return end
    ns.ConfigSessionStageGroup(selectedType,groupWorking)
    MarkPending("Group layout changes are pending.")
end

local function StageAuraValue(key,value)
    if refreshing or not AuraAvailable(selectedType,selectedAura) then return end
    ns.ConfigSessionStageAura(selectedType,selectedAura,{[key]=value})
    auraWorking[key]=value; MarkPending(DISPLAY_NAMES[selectedType].." "..AURA_NAMES[selectedAura].." change staged.")
end

local function SupportsFrameSection(section)
    return FRAME_SUPPORT[section] and FRAME_SUPPORT[section][selectedType] == true
end

local function SetControlEnabled(control, enabled)
    enabled=not not enabled
    control:SetEnabled(enabled); control:SetAlpha(enabled and 1 or 0.45)
    if control.ValueBox then
        control.ValueBox:SetEnabled(enabled); control.ValueBox:SetAlpha(enabled and 1 or 0.45)
    end
end

local function MakeNavigationButton(parent, label, width)
    local button=CreateFrame("Button",nil,parent,"BackdropTemplate")
    button:SetSize(width,30)
    button:SetBackdrop({bgFile=MEDIA,edgeFile=MEDIA,edgeSize=1})
    local text=button:CreateFontString(nil,"OVERLAY"); text:SetFont(FONT,11,"OUTLINE"); text:SetTextColor(unpack(Skin.text)); text:SetPoint("CENTER")
    text:SetText(label)
    local accent=button:CreateTexture(nil,"OVERLAY"); accent:SetColorTexture(unpack(Skin.accent))
    accent:SetPoint("BOTTOMLEFT",2,2); accent:SetPoint("BOTTOMRIGHT",-2,2); accent:SetHeight(3)
    button.MIUF_SkinLabel=text; button.MIUF_Accent=accent; Skin.Button(button)
    button:SetSelected(false)
    return button
end

local function MakeFrameSection(parent, title, x, y, width, height)
    local section=MakeSection(parent,title,width or 426,height or 186)
    section:SetPoint("TOPLEFT",x,y)
    return section
end

local function FrameSlider(parent, name, label, minimum, maximum, width, x, y)
    local slider=MakeSlider(parent,name,label,minimum,maximum,1,width)
    slider:SetPoint("TOPLEFT",x,y); slider:HookScript("OnValueChanged",PreviewFrameSliders)
    return slider
end

local function RefreshIndicatorControls()
    local items={
        {frameUI.sections.role,SupportsFrameSection("role"),working.showTankRoleIcon or working.showHealerRoleIcon or working.showDamageRoleIcon},
        {frameUI.sections.marker,true,working.showRaidMarker~=false},
        {restingControls.Panel,SupportsFrameSection("resting"),working.showRestingIcon~=false},
        {frameUI.sections.status,SupportsFrameSection("status"),true},
        {frameUI.sections.leader,SupportsFrameSection("leader"),working.showLeaderIcon},
    }
    local index=0
    for _,item in ipairs(items) do
        local panel,available,enabled=unpack(item)
        panel:SetShown(available)
        if available then
            panel:ClearAllPoints(); panel:SetPoint("TOPLEFT",(index%2)*442,-math.floor(index/2)*202)
            index=index+1
        end
        if panel.Toggle then panel.Toggle:SetText(enabled and "On" or "Off") end
        for key,check in pairs(panel.RoleChecks or {}) do check:SetChecked(working[key]==true) end
        for _,slider in ipairs(panel.Sliders) do SetControlEnabled(slider,enabled) end
    end
end

local function RefreshFrameControls()
    frameUI.healerPowerBarsOnly:SetShown(selectedType=="party" or selectedType=="raid")
    frameUI.healerPowerBarsOnly:SetChecked(working.healerPowerBarsOnly==true)
    frameUI.sections.portrait:SetShown(SupportsFrameSection("portrait"))
    nameButton:SetText("Name: "..(working.showName and "On" or "Off"))
    healthTextButton:SetText("Health Text: "..(working.showHealthText and "On" or "Off"))
    portraitButton:SetText("Portrait: "..(working.showPortrait and "On" or "Off"))
    sideButton:SetText("Side: "..(working.portraitSide=="RIGHT" and "Right" or "Left"))
    SetControlEnabled(portraitSlider,working.showPortrait); SetControlEnabled(sideButton,working.showPortrait)
    SetControlEnabled(nameXSlider,working.showName); SetControlEnabled(nameYSlider,working.showName)
    SetControlEnabled(healthXSlider,working.showHealthText); SetControlEnabled(healthYSlider,working.showHealthText)
    RefreshIndicatorControls()
    textureButton:SetText("Bar Texture: "..DisplayName(ns.Media.textures,working.texture,"Flat").."  v")
    healthColorButton:SetText("Health Bar Color: "..DisplayName(ns.Media.healthColors,working.healthColor,"Automatic"))
    powerColorButton:SetText("Power Bar Color: "..DisplayName(ns.Media.powerColors,working.powerColor,"Automatic"))
    fontButton:SetText("Font: "..DisplayName(ns.Media.fonts,working.fontFace,"Friz Quadrata").."  v")
end

local function RefreshGroupControls()
    local isRaid=selectedType=="raid"
    raidPreviewControls:SetShown(isRaid)
    raidLegacyButton:SetShown(isRaid)
    local show=SupportsFrameSection("group"); partyLayoutPanel:SetShown(show); if not show then return end
    partyLayoutPanel.Title:SetText(DISPLAY_NAMES[selectedType].." group layout"); partyIncludePlayerButton:SetShown(selectedType=="party")
    partyLayoutPanel:ClearAllPoints(); partyLayoutPanel:SetPoint("TOPLEFT",442,isRaid and 0 or -196)
    partySpacingSlider:SetShown(not isRaid); partySpacingSlider.ValueBox:SetShown(not isRaid)
    partyOrientationButton:SetWidth(isRaid and 386 or 190)
    partyOrientationButton:SetText((isRaid and "Group Orientation: " or "Orientation: ")..(GROUP_ORIENTATION_NAMES[groupWorking.orientation] or "Vertical"))
    frameUI.raidLayoutNote:SetShown(isRaid)
    partyDirectionButton:SetShown(not isRaid)
    if isRaid then
        raidLegacyButton:SetText("Legacy 40-player groups: "..(groupWorking.legacy40 and "On" or "Off"))
    else
        local dir=groupWorking.direction or "DOWN"
        partyDirectionButton:SetText("Growth Direction: "..dir:sub(1,1)..dir:sub(2):lower()); partySpacingSlider:SetValue(groupWorking.spacing or 32)
    end
    partyIncludePlayerButton:SetText("Include Player: "..(groupWorking.includePlayer and "On" or "Off"))
end

local function RefreshAuraControls()
    local wasRefreshing=refreshing; refreshing=true
    local available=AuraAvailable(selectedType,selectedAura) and auraWorking.iconSize~=nil
    auraLabel:SetText("Aura layout: "..(AURA_NAMES[selectedAura] or selectedAura))
    for _,slider in ipairs({auraSizeSlider,auraCountSlider,auraSpacingSlider,auraXSlider,auraYSlider}) do if available then slider:Enable() else slider:Disable() end end
    auraEnableButton:SetEnabled(available); auraTextButton:SetEnabled(available and auraWorking.enabled~=false); auraAnchorButton:SetEnabled(available and auraWorking.enabled~=false); auraGrowthButton:SetEnabled(available and auraWorking.enabled~=false)
    if available then
        auraEnableButton:SetText("Enabled: "..(auraWorking.enabled~=false and "On" or "Off")); auraTextButton:SetText("Cooldown Text: "..(auraWorking.showText~=false and "On" or "Off"))
        auraSizeSlider:SetValue(auraWorking.iconSize); auraCountSlider:SetValue(auraWorking.maxCount); auraSpacingSlider:SetValue(auraWorking.spacing); auraXSlider:SetValue(auraWorking.xOffset); auraYSlider:SetValue(auraWorking.yOffset)
        auraAnchorButton:SetText("Anchor: "..(ANCHOR_NAMES[auraWorking.anchor] or auraWorking.anchor)); auraGrowthButton:SetText("Growth: "..(GROWTH_NAMES[auraWorking.growth] or auraWorking.growth))
    else
        auraEnableButton:SetText("Enabled: N/A"); auraTextButton:SetText("Cooldown Text: N/A"); auraAnchorButton:SetText("Anchor: N/A"); auraGrowthButton:SetText("Growth: N/A")
    end
    auraUI.filtering:SetChecked(auraWorking.filteringEnabled~=false)
    auraUI.filtering:SetEnabled(available and selectedAura=="buffs")
    auraUI.reset:SetText("Reset "..DISPLAY_NAMES[selectedType].." "..(AURA_NAMES[selectedAura] or "Aura"))
    refreshing=wasRefreshing
end

local function BuffPickerUnits()
    if selectedType=="party" then local u={"party1","party2","party3","party4"}; if groupWorking.includePlayer then u[#u+1]="player" end; return u end
    if selectedType=="player" or selectedType=="target" or selectedType=="focus" or selectedType=="targettarget" then return {selectedType} end
    return {}
end
local function ObserveCurrentBuffs()
    if InCombatLockdown() or not C_UnitAuras or not C_UnitAuras.GetUnitAuras then return end
    for _,unit in ipairs(BuffPickerUnits()) do
        local ok,auras=pcall(C_UnitAuras.GetUnitAuras,unit,"HELPFUL|PLAYER",40)
        if ok and type(auras)=="table" then for _,aura in ipairs(auras) do
            local id=aura and tonumber(aura.spellId); if id then ns.RecordSeenBuff(id,aura.name,aura.icon) end
        end end
    end
end

local function RefreshTrackedWindow()
    if not buffFilterPanel then return end
    local show=IsAurasSelected() and selectedAura=="buffs"; buffFilterPanel:SetShown(show); if not show then return end
    ObserveCurrentBuffs(); local tracked=ns.ConfigSessionGetTrackedBuffs(); local trackedList,seenList={},{}
    for id,meta in pairs(tracked or {}) do local n=tonumber(id); if n then trackedList[#trackedList+1]={spellID=n,name=meta.name or ("Spell "..n),icon=meta.icon} end end
    for id,meta in pairs(ns.GetSeenBuffs() or {}) do local n=tonumber(id); if n and not tracked[n] then seenList[#seenList+1]={spellID=n,name=meta.name or ("Spell "..n),icon=meta.icon,lastSeen=meta.lastSeen or 0} end end
    table.sort(trackedList,function(a,b) return a.name<b.name end); table.sort(seenList,function(a,b) if a.lastSeen~=b.lastSeen then return a.lastSeen>b.lastSeen end return a.name<b.name end)
    manageTrackedButton:SetText(#trackedList>0 and ("Manage Tracked Buffs ("..#trackedList..")") or "Manage Tracked Buffs")
    if not trackedBuffWindow then return end
    local function Configure(button,info,isTracked)
        if not info then button:Hide(); return end
        button.icon:SetTexture(info.icon or 134400); button:SetScript("OnEnter",function(self) GameTooltip:SetOwner(self,"ANCHOR_RIGHT"); GameTooltip:SetText(info.name); GameTooltip:AddLine(isTracked and "Click to stop tracking." or "Click to track.",0.8,0.8,0.8); GameTooltip:Show() end); button:SetScript("OnLeave",GameTooltip_Hide)
        button:SetScript("OnClick",function()
            if InCombatLockdown() then return end; local values=ns.ConfigSessionGetTrackedBuffs()
            if isTracked then values[info.spellID]=nil else values[info.spellID]={name=info.name,icon=info.icon} end
            ns.ConfigSessionStageTrackedBuffs(values)
            MarkPending(info.name..(isTracked and " will no longer be tracked." or " will be tracked.")); RefreshTrackedWindow()
        end); button:Show()
    end
    for i,b in ipairs(seenBuffButtons) do Configure(b,seenList[i],false) end; for i,b in ipairs(trackedBuffButtons) do Configure(b,trackedList[i],true) end
end

local function SetProfileStatus(text, errorState)
    if not profileActionStatus then return end
    profileActionStatus:SetText(text or "")
    profileActionStatus:SetTextColor(errorState and 0.72 or Skin.muted[1], errorState and 0.43 or Skin.muted[2], errorState and 0.40 or Skin.muted[3])
end

local function RefreshProfilesControls()
    if not profilesPage then return end
    local active = ns.GetActiveProfileName()
    local names = ns.GetProfileNames()
    if not selectedProfileName or not ns.ProfileExists(selectedProfileName) then selectedProfileName = active end
    profileCurrentLabel:SetText("Current profile: |cff66ccff"..active.."|r")
    profileCharacterLabel:SetText("Character: "..ns.GetCharacterProfileKey())
    for i,button in ipairs(profileButtons) do
        local name=names[i]
        if name then
            button.ProfileName=name
            button:SetText((name==active and "* " or "")..name)
            button:SetEnabled(name~=selectedProfileName)
            button:Show()
        else
            button.ProfileName=nil
            button:Hide()
        end
    end
end

local function RefreshAurasCategory()
    local previous
    for _,auraType in ipairs(AURA_TYPES) do
        local button=auraButtons[auraType]
        local available=AuraAvailable(selectedType,auraType)
        button:SetShown(available); button:SetSelected(auraType==selectedAura)
        if available then
            button:ClearAllPoints()
            if previous then button:SetPoint("LEFT",previous,"RIGHT",8,0)
            else button:SetPoint("TOPLEFT",0,-36) end
            previous=button
        end
    end
    RefreshAuraControls(); RefreshTrackedWindow()
    RefreshAuraPositionPreview()
end

local function RefreshFramesNavigation()
    if frameUI.category=="Auras" and not SupportsFrameSection("auras") then frameUI.category="Layout" end
    for unitType,button in pairs(frameUI.units) do button:SetSelected(unitType==selectedType) end
    for name,entry in pairs(frameUI.categories) do
        entry.Button:SetShown(name~="Auras" or SupportsFrameSection("auras"))
        entry.Button:SetSelected(name==frameUI.category); entry.Panel:SetShown(name==frameUI.category)
    end
    frameUI.header.Title:SetText(string.upper(DISPLAY_NAMES[selectedType])..((selectedType=="party" or selectedType=="raid" or selectedType=="boss") and " FRAMES" or " FRAME"))
    frameUI.enabled:SetChecked(ns.ConfigSessionGetEnabled(selectedType))
    frameUI.reset:SetText("Reset "..DISPLAY_NAMES[selectedType])
end

local function RefreshPageSelection()
    selectedLabel:SetText("Profiles"); selectedLabel:SetShown(selectedPage=="profiles")
    config:SetHeight(selectedPage=="frames" and 760 or 840); frameUI.FitToScreen()
    framesPage:SetShown(selectedPage=="frames"); profilesPage:SetShown(selectedPage=="profiles")
    frameTab:SetSelected(selectedPage=="frames"); profileTab:SetSelected(selectedPage=="profiles")
    frameTab:SetEnabled(selectedPage~="frames"); profileTab:SetEnabled(selectedPage~="profiles")
end

local function RefreshFramesPage()
    widthSlider:SetLimits(selectedType=="raid" and 50 or 100,600)
    heightSlider:SetLimits(selectedType=="raid" and 18 or 24,150)
    local frameSettings=ns.ConfigSessionGetFrame(selectedType); local size=frameSettings.size; widthSlider:SetValue(size.width); heightSlider:SetValue(size.height); powerSlider:SetValue(frameSettings.powerPercent); fontSlider:SetValue(working.fontSize); portraitSlider:SetValue(working.portraitPercent); bgSlider:SetValue(working.backgroundOpacity); borderSlider:SetValue(working.borderOpacity)
    castbarControls.Panel:SetShown(frameSettings.castbar~=nil)
    local configurable=FRAME_SUPPORT.castbarGeometry[selectedType]==true
    castbarControls.Panel:SetHeight(configurable and 186 or 36)
    castbarControls.preview:SetShown(configurable)
    for _,key in ipairs({"width","height","xOffset","yOffset"}) do
        castbarControls[key]:SetShown(configurable)
        castbarControls[key].ValueBox:SetShown(configurable)
    end
    if frameSettings.castbar then
        local c=frameSettings.castbar
        castbarControls.enabled:SetChecked(c.enabled~=false)
        castbarControls.width:SetValue(c.width==0 and size.width or c.width)
        castbarControls.height:SetValue(c.height)
        castbarControls.xOffset:SetValue(c.xOffset)
        castbarControls.yOffset:SetValue(c.yOffset)
        _G[castbarControls.width:GetName().."Text"]:SetText(c.width==0 and "Width (Frame Default)" or "Width")
    end
    nameXSlider:SetValue(working.nameXOffset or 6); nameYSlider:SetValue(working.nameYOffset or 0); healthXSlider:SetValue(working.healthXOffset or -6); healthYSlider:SetValue(working.healthYOffset or 0)
    roleXSlider:SetValue(working.roleIconXOffset or 3); roleYSlider:SetValue(working.roleIconYOffset or -3)
    roleSizeSlider:SetValue(working.roleIconSize or 14)
    local leader=frameUI.sections.leader
    leader.X:SetValue(working.leaderIconXOffset or -16); leader.Y:SetValue(working.leaderIconYOffset or -2)
    leader.Size:SetValue(working.leaderIconSize or 12)
    if selectedType=="player" then
        restingControls.X:SetValue(working.restingIconXOffset or 3); restingControls.Y:SetValue(working.restingIconYOffset or -3)
        restingControls.Size:SetValue(working.restingIconSize or 16)
    end
    raidXSlider:SetValue(working.raidMarkerXOffset or 0); raidYSlider:SetValue(working.raidMarkerYOffset or 2); raidSizeSlider:SetValue(working.raidMarkerSize or 20)
    statusXSlider:SetValue(working.statusIconXOffset or -4); statusYSlider:SetValue(working.statusIconYOffset or -3); statusSizeSlider:SetValue(working.statusIconSize or 18)
    RefreshFrameControls(); RefreshGroupControls(); frameLockButton:SetText(ns.AreFrameMoversLocked() and "Unlock Frames" or "Lock Frames")
end

function ns.RefreshConfig()
    if not config or not config:IsShown() then return end
    refreshing=true; MarkPending(); CopyWorking()
    RefreshFramesNavigation()
    RefreshPageSelection()
    if selectedPage=="frames" then
        RefreshFramesPage()
        if IsAurasSelected() then RefreshAurasCategory() end
    else
        RefreshProfilesControls()
    end
    statusText:SetText(InCombatLockdown() and "Apply and Revert are unavailable during combat." or (ns.ConfigSessionIsDirty() and "Pending changes are waiting. Click Apply Changes when ready." or (selectedPage=="profiles" and "Profile switches reload the UI so protected frames rebuild cleanly." or "Edit settings, then click Apply Changes.")))
    applyChangesButton:SetEnabled(ns.ConfigSessionIsDirty() and not InCombatLockdown())
    refreshing=false
    if not InCombatLockdown() and selectedPage=="frames" and frameUI.category~="Auras"
        and FRAME_SUPPORT.castbar[selectedType] then
        ns.PreviewFrameType(selectedType,ns.ConfigSessionGetFrame(selectedType))
        previewFrameType=selectedType
    end
    ns.UpdateRaidPreview()
    RefreshStatusIconPreview()
    RefreshCastbarPreview()
    RefreshAuraPositionPreview()
    if not InCombatLockdown() and IsAurasSelected() and AuraAvailable(selectedType,selectedAura) and auraWorking.iconSize then
        ApplyAuraVisual(selectedType,selectedAura,auraWorking); previewAuraUnitType,previewAuraType=selectedType,selectedAura
    end
end

local function ApplyChanges()
    ClearAuraPositionPreview()
    ClearCastbarPreview()
    ClearStatusIconPreview()
    local committed,summary=ns.ConfigSessionCommit()
    if not committed then return end
    previewAuraUnitType,previewAuraType=nil,nil
    previewFrameType=nil; applyChangesButton:SetEnabled(false); revertChangesButton:SetEnabled(false)
    ns.SetFrameMoversLockedState(true); ns.SetAuraMoversLockedState(true)
    local ok,liveApplied=pcall(function()
        local applied=false
        if not summary.requiresReloadFallback then applied=ns.ApplySavedConfiguration(summary)==true end
        ns.SetMoversLocked(true)
        if applied then
            ns.RefreshConfig()
            -- RefreshConfig may record a saved-state aura preview; no rollback
            -- reference should survive successful application.
            previewAuraUnitType,previewAuraType=nil,nil
            previewFrameType=nil
        end
        return applied
    end)
    if not ok then
        print("|cffff5555MIUF: configuration refresh failed; saved changes will be applied by reloading. "..tostring(liveApplied).."|r")
    elseif not liveApplied and not summary.requiresReloadFallback then
        print("|cffff5555MIUF: configuration refresh did not complete; saved changes will be applied by reloading.|r")
    end
    if not ok or not liveApplied then ReloadUI() end
end

local function RevertChanges()
    ClearAuraPositionPreview()
    ClearCastbarPreview()
    ClearStatusIconPreview()
    if InCombatLockdown() or not ns.ConfigSessionIsDirty() then return end
    previewFrameType=nil; previewAuraUnitType,previewAuraType=nil,nil
    local reverted,err=ns.ConfigSessionRevert()
    ns.RefreshConfig()
    if reverted then
        -- RefreshConfig can record a saved aura preview; discard rollback refs.
        previewFrameType=nil; previewAuraUnitType,previewAuraType=nil,nil
    elseif err then
        print("|cffff5555MIUF: Revert did not complete; pending changes retained. "..tostring(err).."|r")
    end
end

local function SelectPage(page)
    if page~="frames" then ClearStatusIconPreview() end
    if fontMenu then fontMenu:Hide() end
    if textureMenu then textureMenu:Hide() end
    if page~="frames" then RestoreFramePreview(); RestoreAuraPreview() end
    selectedPage=page
    ns.RefreshConfig()
end

local function CreateShell()
    config=CreateFrame("Frame","MIUF_ConfigFrame",UIParent,"BackdropTemplate"); config:SetSize(900,840); config:SetPoint("CENTER"); config:SetFrameStrata("DIALOG"); config:SetClampedToScreen(true); config:SetMovable(true); config:EnableMouse(true); config:RegisterForDrag("LeftButton")
    local function FitConfigToScreen()
        config:SetScale(math.min(1,(UIParent:GetWidth()-32)/config:GetWidth(),(UIParent:GetHeight()-32)/config:GetHeight()))
    end
    frameUI.FitToScreen=FitConfigToScreen
    config:SetScript("OnShow",FitConfigToScreen)
    config:RegisterEvent("UI_SCALE_CHANGED"); config:RegisterEvent("DISPLAY_SIZE_CHANGED")
    config:SetScript("OnEvent",FitConfigToScreen)
    FitConfigToScreen()
    config:SetScript("OnDragStart",config.StartMoving); config:SetScript("OnDragStop",config.StopMovingOrSizing); config:SetBackdrop({bgFile=MEDIA,edgeFile=MEDIA,edgeSize=1}); Skin.Panel(config,Skin.background)
    config:SetScript("OnHide",function() if not internalHide then ns.CloseConfig() end end)
    local icon=config:CreateTexture(nil,"ARTWORK"); icon:SetSize(96,96); icon:SetPoint("TOPLEFT",18,-10)
    icon:SetTexture("Interface\\AddOns\\"..ADDON_NAME.."\\Media\\Artwork\\MIUF_Icon_128.png")
    local title=config:CreateFontString(nil,"OVERLAY"); title:SetFont(FONT,17,"OUTLINE"); title:SetTextColor(unpack(Skin.text)); title:SetPoint("TOPLEFT",120,-16); title:SetText("M Y T H Inc Unit Frames")
    local ver=config:CreateFontString(nil,"OVERLAY"); ver:SetFont(FONT,10,"OUTLINE"); ver:SetTextColor(unpack(Skin.text)); ver:SetPoint("LEFT",title,"RIGHT",10,-1); ver:SetText(ns.version); ver:SetTextColor(unpack(Skin.muted))
    local close=MakeButton(config,"X",28,24); close:SetPoint("TOPRIGHT",-10,-10); close:SetScript("OnClick",function() ns.CloseConfig() end)
    local collapse=MakeButton(config,"Minimize",86,24); collapse:SetPoint("RIGHT",close,"LEFT",-6,0); collapse:SetScript("OnClick",function() ns.CollapseConfig() end)
    frameTab=MakeButton(config,"Frames",110,28); frameTab:SetPoint("TOPLEFT",180,-48); frameTab:SetScript("OnClick",function() SelectPage("frames") end)
    profileTab=MakeButton(config,"Profiles",110,28); profileTab:SetPoint("LEFT",frameTab,"RIGHT",8,0); profileTab:SetScript("OnClick",function() SelectPage("profiles") end)
    applyChangesButton=MakeButton(config,"Apply Changes",120,28); applyChangesButton:SetPoint("BOTTOMLEFT",16,18); applyChangesButton:SetEnabled(false); applyChangesButton:SetScript("OnClick",ApplyChanges)
    revertChangesButton=MakeButton(config,"Revert Changes",120,28); revertChangesButton:SetPoint("LEFT",applyChangesButton,"RIGHT",8,0); revertChangesButton:SetEnabled(false); revertChangesButton:SetScript("OnClick",RevertChanges)
    local resetAll=MakeButton(config,"Reset All",90,26); resetAll:SetPoint("BOTTOMRIGHT",-16,19); resetAll:SetScript("OnClick",function() if not InCombatLockdown() then RestoreFramePreview(); RestoreAuraPreview()
        ns.ConfigSessionStageResetAll(); MarkPending("Reset of all configuration settings is pending."); ns.RefreshConfig() end end)
    selectedLabel=config:CreateFontString(nil,"OVERLAY"); selectedLabel:SetFont(FONT,14,"OUTLINE"); selectedLabel:SetTextColor(unpack(Skin.text)); selectedLabel:SetPoint("TOPLEFT",180,-94)
    statusText=config:CreateFontString(nil,"OVERLAY"); statusText:SetFont(FONT,9,"OUTLINE"); statusText:SetTextColor(unpack(Skin.text)); statusText:SetPoint("LEFT",config,"BOTTOMLEFT",280,32); statusText:SetWidth(270); statusText:SetJustifyH("LEFT")
end

local function CreateIndicatorSection(parent,title,prefix,offsetLimit,toggleKey)
    local panel=MakeFrameSection(parent,title,0,0)
    if toggleKey then
        panel.Toggle=MakeButton(panel,"On",90,26); panel.Toggle:SetPoint("TOPLEFT",18,-34)
        panel.Toggle:SetScript("OnClick",function()
            if toggleKey=="showLeaderIcon" then working[toggleKey]=not working[toggleKey]
            else working[toggleKey]=working[toggleKey]==false end
            RefreshFrameControls(); PreviewFrameSliders()
        end)
    elseif prefix=="StatusIcon" then
        local note=panel:CreateFontString(nil,"OVERLAY"); note:SetFont(FONT,10,"OUTLINE"); note:SetTextColor(unpack(Skin.text))
        note:SetPoint("TOPLEFT",18,-40); note:SetText("Ready Check • Summon • Incoming Resurrection")
    end
    panel.X=FrameSlider(panel,prefix.."XOffset","X",-offsetLimit,offsetLimit,110,18,-94)
    panel.Y=FrameSlider(panel,prefix.."YOffset","Y",-offsetLimit,offsetLimit,110,158,-94)
    panel.Size=FrameSlider(panel,prefix.."Size","Size",8,48,110,298,-94)
    panel.Sliders={panel.X,panel.Y,panel.Size}
    return panel
end

local function CreateStatusIconPreviewControl(panel)
    local check=CreateFrame("CheckButton",nil,panel,"UICheckButtonTemplate"); Skin.Check(check)
    check:SetSize(24,24); check:SetPoint("TOPRIGHT",-76,-4); check:SetChecked(false)
    local label=check:CreateFontString(nil,"OVERLAY"); label:SetFont(FONT,11,"OUTLINE"); label:SetTextColor(unpack(Skin.text))
    label:SetPoint("LEFT",check,"RIGHT",2,0); label:SetText("Preview")
    frameUI.statusPreview=check
    check:SetScript("OnClick",function(self)
        if not self:GetChecked() then ClearStatusIconPreview(); return end
        -- Record only visual ownership so the existing close/unit-change path
        -- restores saved geometry even when no setting was edited.
        previewFrameType=selectedType
        RefreshStatusIconPreview()
        local elapsed=0
        self:SetScript("OnUpdate",function(_,delta)
            elapsed=elapsed+delta; if elapsed<0.1 then return end; elapsed=0
            RefreshStatusIconPreview()
        end)
    end)
    panel:HookScript("OnHide",function() if not internalHide then ClearStatusIconPreview() end end)
end

local function CreateIndicatorControls(parent)
    frameUI.sections.leader=CreateIndicatorSection(parent,"Leader Icon","LeaderIcon",150,"showLeaderIcon")
    local role=CreateIndicatorSection(parent,"Role Icon","RoleIcon",100)
    role.RoleChecks={}
    for index,entry in ipairs({{"Tank","showTankRoleIcon"},{"Healer","showHealerRoleIcon"},{"Damage","showDamageRoleIcon"}}) do
        local key=entry[2]
        local check=CreateFrame("CheckButton",nil,role,"UICheckButtonTemplate"); Skin.Check(check)
        check:SetSize(24,24); check:SetPoint("TOPLEFT",18+(index-1)*140,-34)
        local label=check:CreateFontString(nil,"OVERLAY"); label:SetFont(FONT,11,"OUTLINE"); label:SetTextColor(unpack(Skin.text))
        label:SetPoint("LEFT",check,"RIGHT",2,0); label:SetText(entry[1])
        role.RoleChecks[key]=check
        check:SetScript("OnClick",function(self)
            if refreshing or not SupportsFrameSection("role") then return end
            working[key]=self:GetChecked()==true
            RefreshFrameControls(); PreviewFrameSliders()
        end)
    end
    frameUI.sections.role=role
    roleXSlider,roleYSlider,roleSizeSlider=role.X,role.Y,role.Size
    local marker=CreateIndicatorSection(parent,"Raid Marker","RaidMarker",150,"showRaidMarker")
    frameUI.sections.marker=marker
    raidXSlider,raidYSlider,raidSizeSlider=marker.X,marker.Y,marker.Size
    local resting=CreateIndicatorSection(parent,"Resting Indicator","RestingIcon",100,"showRestingIcon")
    restingControls.Panel=resting; restingControls.Button=resting.Toggle
    restingControls.X,restingControls.Y,restingControls.Size=resting.X,resting.Y,resting.Size
    local status=CreateIndicatorSection(parent,"Temporary Status Icons","StatusIcon",150)
    frameUI.sections.status=status
    CreateStatusIconPreviewControl(status)
    statusXSlider,statusYSlider,statusSizeSlider=status.X,status.Y,status.Size
end

local function CreateFrameLayoutControls(parent)
    local size=MakeFrameSection(parent,"Frame Size",0,0,426,112)
    widthSlider=FrameSlider(size,"Width","Frame Width",100,600,174,18,-54)
    heightSlider=FrameSlider(size,"Height","Frame Height",24,150,174,234,-54)
    local power=MakeFrameSection(parent,"Power Bar",0,-128,426,100)
    powerSlider=FrameSlider(power,"PowerPercent","Power Bar Height (%)",10,40,360,28,-52)
    local healerOnly=CreateFrame("CheckButton",nil,power,"UICheckButtonTemplate"); Skin.Check(healerOnly)
    healerOnly:SetSize(24,24); healerOnly:SetPoint("TOPRIGHT",-170,-3)
    local healerLabel=healerOnly:CreateFontString(nil,"OVERLAY"); healerLabel:SetFont(FONT,11,"OUTLINE"); healerLabel:SetTextColor(unpack(Skin.text))
    healerLabel:SetPoint("LEFT",healerOnly,"RIGHT",2,0); healerLabel:SetText("Healer Power Bars Only")
    frameUI.healerPowerBarsOnly=healerOnly
    healerOnly:SetScript("OnClick",function(self)
        if refreshing or (selectedType~="party" and selectedType~="raid") then return end
        working.healerPowerBarsOnly=self:GetChecked()==true
        PreviewFrameSliders()
    end)
    local portrait=MakeFrameSection(parent,"Portrait",442,0,426,180); frameUI.sections.portrait=portrait
    portraitButton=MakeButton(portrait,"Portrait: Off",170,26); portraitButton:SetPoint("TOPLEFT",18,-34)
    portraitButton:SetScript("OnClick",function() working.showPortrait=not working.showPortrait; RefreshFrameControls(); PreviewFrameSliders() end)
    sideButton=MakeButton(portrait,"Side: Left",170,26); sideButton:SetPoint("TOPLEFT",234,-34)
    sideButton:SetScript("OnClick",function() working.portraitSide=working.portraitSide=="LEFT" and "RIGHT" or "LEFT"; RefreshFrameControls(); PreviewFrameSliders() end)
    portraitSlider=FrameSlider(portrait,"PortraitPercent","Portrait Width (%)",12,40,360,28,-96)
    local castbar=MakeFrameSection(parent,"Cast Bar",0,-244,426,186)
    castbarControls.Panel=castbar
    local enabled=CreateFrame("CheckButton",nil,castbar,"UICheckButtonTemplate"); Skin.Check(enabled)
    enabled:SetSize(24,24); enabled:SetPoint("TOPRIGHT",-164,-3)
    local label=enabled:CreateFontString(nil,"OVERLAY"); label:SetFont(FONT,11,"OUTLINE"); label:SetTextColor(unpack(Skin.text))
    label:SetPoint("LEFT",enabled,"RIGHT",2,0); label:SetText("Enable Cast Bar")
    castbarControls.enabled=enabled
    enabled:SetScript("OnClick",function(self)
        if refreshing then return end
        local settings=ns.ConfigSessionGetFrame(selectedType)
        if not settings.castbar then return end
        settings.castbar.enabled=self:GetChecked()==true
        ns.ConfigSessionStageFrame(selectedType,settings)
        MarkPending("Cast bar changes are pending.")
        if not InCombatLockdown() then
            ns.PreviewFrameType(selectedType,settings)
            previewFrameType=selectedType
        end
        RefreshCastbarPreview()
    end)
    local preview=CreateFrame("CheckButton",nil,castbar,"UICheckButtonTemplate"); Skin.Check(preview)
    preview:SetSize(24,24); preview:SetPoint("BOTTOMLEFT",18,0)
    local previewLabel=preview:CreateFontString(nil,"OVERLAY"); previewLabel:SetFont(FONT,11,"OUTLINE"); previewLabel:SetTextColor(unpack(Skin.text))
    previewLabel:SetPoint("LEFT",preview,"RIGHT",2,0); previewLabel:SetText("Preview Cast Bar")
    castbarControls.preview=preview
    preview:SetScript("OnClick",function(self)
        if not self:GetChecked() then ClearCastbarPreview(); return end
        RefreshCastbarPreview()
    end)
    local specs={
        {"width","Width",100,600,18,-46}, {"height","Height",18,40,234,-46},
        {"xOffset","X Offset",-1000,1000,18,-112}, {"yOffset","Y Offset",-1000,1000,234,-112},
    }
    for _, spec in ipairs(specs) do
        local key=spec[1]
        local slider=MakeSlider(castbar,"Castbar"..key,spec[2],spec[3],spec[4],1,174)
        slider:SetPoint("TOPLEFT",spec[5],spec[6]); castbarControls[key]=slider
        slider:HookScript("OnValueChanged",function(_,value)
            if refreshing then return end
            local settings=ns.ConfigSessionGetFrame(selectedType)
            if not settings.castbar then return end
            settings.castbar[key]=Round(value)
            ns.ConfigSessionStageFrame(selectedType,settings)
            MarkPending("Cast bar geometry changes are pending.")
            if not InCombatLockdown() then
                ns.PreviewFrameType(selectedType,settings)
                previewFrameType=selectedType
            end
            if key=="width" then _G[slider:GetName().."Text"]:SetText("Width") end
        end)
    end
end

local function CreateGroupLayoutControls(layout)
    partyLayoutPanel=MakeFrameSection(layout,"Group Layout",442,-196,426,208)
    frameUI.raidLayoutNote=partyLayoutPanel:CreateFontString(nil,"OVERLAY"); frameUI.raidLayoutNote:SetFont(FONT,11,"OUTLINE"); frameUI.raidLayoutNote:SetTextColor(unpack(Skin.text)); frameUI.raidLayoutNote:SetPoint("TOPLEFT",18,-118); frameUI.raidLayoutNote:SetWidth(386); frameUI.raidLayoutNote:SetJustifyH("LEFT")
    frameUI.raidLayoutNote:SetText("Controls whether raid groups are arranged vertically or horizontally.")
    partyOrientationButton=MakeButton(partyLayoutPanel,"Orientation: Vertical",190,26); partyOrientationButton:SetPoint("TOPLEFT",18,-38); partyOrientationButton:SetScript("OnClick",function() groupWorking.orientation=Cycle(groupWorking.orientation or "VERTICAL",GROUP_ORIENTATION_ORDER); if selectedType~="raid" then groupWorking.direction=groupWorking.orientation=="HORIZONTAL" and "RIGHT" or "DOWN" end; StageGroupControls(); RefreshGroupControls(); PreviewFrameSliders() end)
    partyDirectionButton=MakeButton(partyLayoutPanel,"Growth Direction: Down",190,26); partyDirectionButton:SetPoint("LEFT",partyOrientationButton,"RIGHT",7,0); partyDirectionButton:SetScript("OnClick",function() if groupWorking.orientation=="HORIZONTAL" then groupWorking.direction=groupWorking.direction=="LEFT" and "RIGHT" or "LEFT" else groupWorking.direction=groupWorking.direction=="UP" and "DOWN" or "UP" end; StageGroupControls(); RefreshGroupControls(); PreviewFrameSliders() end)
    partyIncludePlayerButton=MakeButton(partyLayoutPanel,"Include Player: Off",140,24); partyIncludePlayerButton:SetPoint("TOPLEFT",18,-166); partyIncludePlayerButton:SetScript("OnClick",function() groupWorking.includePlayer=not groupWorking.includePlayer; StageGroupControls(); RefreshGroupControls(); PreviewFrameSliders() end)
    partySpacingSlider=MakeSlider(partyLayoutPanel,"PartySpacing","Frame Spacing",0,80,1,360); partySpacingSlider:SetPoint("TOPLEFT",28,-101); partySpacingSlider:HookScript("OnValueChanged",function(_,v) if not refreshing and selectedType~="raid" then groupWorking.spacing=Round(v); StageGroupControls(); PreviewFrameSliders() end end)
    raidLegacyButton=MakeButton(partyLayoutPanel,"",245,24); raidLegacyButton:SetPoint("TOPLEFT",18,-78)
    raidLegacyButton:SetScript("OnClick",function()
        groupWorking.legacy40=not groupWorking.legacy40
        StageGroupControls(); RefreshGroupControls(); PreviewFrameSliders()
    end)
end

local function CreateRaidPreviewControls(parent)
    raidPreviewControls=CreateFrame("Frame",nil,parent); raidPreviewControls:SetSize(180,28); raidPreviewControls:SetPoint("BOTTOMLEFT",240,0)
    local revertRaid=MakeButton(raidPreviewControls,"Revert Raid Changes",155,24); revertRaid:SetPoint("TOPLEFT")
    revertRaid:SetScript("OnClick",function()
        if InCombatLockdown() then return end
        ClearAuraPositionPreview(); ClearCastbarPreview()
        ClearStatusIconPreview()
        ns.StopConfigurationMovers("raid")
        ns.ConfigSessionStageFrame("raid",{size=ns.GetSize("raid"),powerPercent=ns.GetPowerPercent("raid"),appearance=ns.GetAppearance("raid")})
        ns.ConfigSessionStageEnabled("raid",ns.IsFrameTypeEnabled("raid"))
        ns.PreviewUnitTypeMovers("raid",ns.IsFrameTypeEnabled("raid"))
        ns.ConfigSessionStageGroup("raid",ns.GetGroupLayout("raid"))
        ns.ConfigSessionStagePosition("raid",ns.GetPosition("raid"))
        ns.ConfigSessionStageAura("raid","debuffs",ns.GetAuraLayout("raid","debuffs"))
        if ns.PreviewRaidDebuffLayout then ns.PreviewRaidDebuffLayout(ns.GetAuraLayout("raid","debuffs")) end
        RestoreFramePreview("raid")
        ns.ApplyAuraPositions("raid")
        ns.RefreshConfig()
        ns.UpdateRaidPreview()
    end)
end

local function CreateTextControls(parent)
    local text=MakeFrameSection(parent,"Typography",0,0,868,130)
    fontButton=MakeButton(text,"Font",350,26); fontButton:SetPoint("TOPLEFT",18,-44)
    fontMenu=CreateFrame("Frame",nil,text,"BackdropTemplate"); fontMenu:SetWidth(190); fontMenu:SetHeight((#ns.Media.fontOrder*24)+8); fontMenu:SetPoint("TOPLEFT",fontButton,"BOTTOMLEFT",0,-2); fontMenu:SetFrameLevel(text:GetFrameLevel()+20)
    fontMenu:SetBackdrop({bgFile=MEDIA,edgeFile=MEDIA,edgeSize=1}); Skin.Panel(fontMenu,Skin.background); fontMenu:Hide()
    for i,key in ipairs(ns.Media.fontOrder) do
        local entry=ns.Media.fonts[key]; local choice=MakeButton(fontMenu,entry.name,180,22); choice:SetPoint("TOPLEFT",5,-4-((i-1)*24))
        local label=choice:GetFontString(); if label then label:SetFont(entry.path,12,"OUTLINE") end
        choice:SetScript("OnClick",function() working.fontFace=key; fontMenu:Hide(); RefreshFrameControls(); PreviewFrameSliders() end)
    end
    fontButton:SetScript("OnClick",function() if textureMenu then textureMenu:Hide() end; if fontMenu:IsShown() then fontMenu:Hide() else fontMenu:Show() end end)
    fontSlider=MakeSlider(text,"FontSize","Font size",8,24,1,285); fontSlider:SetPoint("TOPLEFT",470,-52); fontSlider:HookScript("OnValueChanged",PreviewFrameSliders)
    local name=MakeFrameSection(parent,"Name",0,-146,426,200)
    local health=MakeFrameSection(parent,"Health Text",442,-146,426,200)
    nameButton=MakeButton(name,"Name: On",105,26); nameButton:SetPoint("TOPLEFT",18,-34); nameButton:SetScript("OnClick",function() working.showName=not working.showName; RefreshFrameControls(); PreviewFrameSliders() end)
    nameXSlider=MakeSlider(name,"NameXOffset","X",-200,200,1,174); nameXSlider:SetPoint("TOPLEFT",18,-100); nameXSlider:HookScript("OnValueChanged",PreviewFrameSliders)
    nameYSlider=MakeSlider(name,"NameYOffset","Y",-100,100,1,174); nameYSlider:SetPoint("TOPLEFT",234,-100); nameYSlider:HookScript("OnValueChanged",PreviewFrameSliders)
    healthTextButton=MakeButton(health,"Health Text: On",150,26); healthTextButton:SetPoint("TOPLEFT",18,-34); healthTextButton:SetScript("OnClick",function() working.showHealthText=not working.showHealthText; RefreshFrameControls(); PreviewFrameSliders() end)
    healthXSlider=MakeSlider(health,"HealthXOffset","X",-200,200,1,174); healthXSlider:SetPoint("TOPLEFT",18,-100); healthXSlider:HookScript("OnValueChanged",PreviewFrameSliders)
    healthYSlider=MakeSlider(health,"HealthYOffset","Y",-100,100,1,174); healthYSlider:SetPoint("TOPLEFT",234,-100); healthYSlider:HookScript("OnValueChanged",PreviewFrameSliders)
end

local function CreateAppearanceControls(parent)
    local appearance=MakeFrameSection(parent,"Bars",0,0,426,226)
    local opacity=MakeFrameSection(parent,"Opacity",442,0,426,226)
    textureButton=MakeButton(appearance,"Bar Texture",386,26); textureButton:SetPoint("TOPLEFT",18,-38)
    textureMenu=CreateFrame("Frame",nil,appearance,"BackdropTemplate"); textureMenu:SetWidth(155); textureMenu:SetHeight((#ns.Media.textureOrder*28)+8); textureMenu:SetPoint("TOPLEFT",textureButton,"BOTTOMLEFT",0,-2); textureMenu:SetFrameLevel(appearance:GetFrameLevel()+20)
    textureMenu:SetBackdrop({bgFile=MEDIA,edgeFile=MEDIA,edgeSize=1}); Skin.Panel(textureMenu,Skin.background); textureMenu:Hide()
    for i,key in ipairs(ns.Media.textureOrder) do
        local entry=ns.Media.textures[key]; local choice=MakeButton(textureMenu,entry.name,145,26); choice:SetPoint("TOPLEFT",5,-4-((i-1)*28))
        local sample=choice:CreateTexture(nil,"OVERLAY"); sample:SetSize(38,8); sample:SetPoint("LEFT",8,0); sample:SetTexture(entry.path)
        local label=choice:GetFontString(); if label then label:SetJustifyH("RIGHT"); label:SetWidth(88); label:ClearAllPoints(); label:SetPoint("RIGHT",-8,0) end
        choice:SetScript("OnClick",function() working.texture=key; textureMenu:Hide(); RefreshFrameControls(); PreviewFrameSliders() end)
    end
    textureButton:SetScript("OnClick",function() if fontMenu then fontMenu:Hide() end; if textureMenu:IsShown() then textureMenu:Hide() else textureMenu:Show() end end)
    healthColorButton=MakeButton(appearance,"Health Bar Color",386,26); healthColorButton:SetPoint("TOPLEFT",18,-88); healthColorButton:SetScript("OnClick",function() working.healthColor=Cycle(working.healthColor,ns.Media.healthColorOrder); RefreshFrameControls(); PreviewFrameSliders() end)
    powerColorButton=MakeButton(appearance,"Power Bar Color",386,26); powerColorButton:SetPoint("TOPLEFT",18,-138); powerColorButton:SetScript("OnClick",function() working.powerColor=Cycle(working.powerColor,ns.Media.powerColorOrder); RefreshFrameControls(); PreviewFrameSliders() end)
    bgSlider=MakeSlider(opacity,"BackgroundOpacity","Background Opacity (%)",0,100,1,360); bgSlider:SetPoint("TOPLEFT",28,-52); bgSlider:HookScript("OnValueChanged",PreviewFrameSliders)
    borderSlider=MakeSlider(opacity,"BorderOpacity","Border Opacity (%)",0,100,1,360); borderSlider:SetPoint("TOPLEFT",28,-138); borderSlider:HookScript("OnValueChanged",PreviewFrameSliders)
end

local function CreateFramesNavigation()
    local previous
    for _,unitType in ipairs(FRAME_TYPES) do
        local button=MakeNavigationButton(framesPage,DISPLAY_NAMES[unitType],unitType=="targettarget" and 154 or 96)
        if previous then button:SetPoint("LEFT",previous,"RIGHT",6,0) else button:SetPoint("TOPLEFT",0,0) end
        button:SetScript("OnClick",function()
            if selectedType==unitType then return end
            ClearAuraPositionPreview()
            ClearCastbarPreview()
            ClearStatusIconPreview()
            if fontMenu then fontMenu:Hide() end; if textureMenu then textureMenu:Hide() end
            if previewFrameType and previewFrameType~=unitType then RestoreFramePreview(previewFrameType) end
            if previewAuraUnitType then RestoreAuraPreview() end
            selectedType=unitType; ns.RefreshConfig()
        end)
        frameUI.units[unitType]=button; previous=button
    end
    for index,name in ipairs(FRAME_CATEGORIES) do
        local button=MakeNavigationButton(framesPage,name,150); button:SetPoint("TOPLEFT",(index-1)*158,-112)
        local panel=CreateFrame("Frame",nil,framesPage); panel:SetPoint("TOPLEFT",0,-158); panel:SetPoint("BOTTOMRIGHT",0,48)
        frameUI.categories[name]={Button=button,Panel=panel}
        button:SetScript("OnClick",function()
            if fontMenu then fontMenu:Hide() end; if textureMenu then textureMenu:Hide() end
            if name==frameUI.category then return end
            if name~="Indicators" then ClearStatusIconPreview() end
            if frameUI.category=="Auras" then RestoreAuraPreview(true) end
            frameUI.category=name
            ns.RefreshConfig()
        end)
    end
end

local function CreateFramesHeader()
    local header=MakeFrameSection(framesPage,"",0,-44,868,54); frameUI.header=header
    header.Title:ClearAllPoints(); header.Title:SetPoint("LEFT",16,0); header.Title:SetFont(FONT,14,"OUTLINE"); header.Title:SetTextColor(unpack(Skin.text))
    local check=CreateFrame("CheckButton",nil,header,"UICheckButtonTemplate"); Skin.Check(check); check:SetSize(24,24); check:SetPoint("RIGHT",-260,0)
    local label=check:CreateFontString(nil,"OVERLAY"); label:SetFont(FONT,12,"OUTLINE"); label:SetTextColor(unpack(Skin.text)); label:SetPoint("LEFT",check,"RIGHT",4,0); label:SetText("Enabled")
    check:SetScript("OnClick",function(self)
        if InCombatLockdown() then self:SetChecked(ns.ConfigSessionGetEnabled(selectedType)); return end
        ns.ConfigSessionStageEnabled(selectedType,self:GetChecked() and true or false)
        MarkPending(DISPLAY_NAMES[selectedType].." enable state staged.")
        if ns.PreviewUnitTypeMovers then ns.PreviewUnitTypeMovers(selectedType,self:GetChecked()) end
        RefreshAuraPositionPreview()
        RefreshCastbarPreview()
    end)
    frameUI.enabled=check
    frameLockButton=MakeButton(header,"Unlock Frames",170,28); frameLockButton:SetPoint("RIGHT",-16,0)
    frameLockButton:SetScript("OnEnter",function(self)
        GameTooltip:SetOwner(self,"ANCHOR_RIGHT"); GameTooltip:SetText("Lock or unlock all MIUF frame movers."); GameTooltip:Show()
    end)
    frameLockButton:SetScript("OnLeave",function() GameTooltip:Hide() end)
    frameLockButton:SetScript("OnClick",function()
        if not InCombatLockdown() then
            local locked=not ns.AreFrameMoversLocked()
            ns.SetFrameMoversLockedState(locked); ns.SetFrameMoversLocked(locked)
            if locked then ns.ShowConfigForPendingFrameChanges() end
            ns.RefreshConfig()
        end
    end)
end

local function CreateFramesActions()
    local reset=MakeButton(framesPage,"Reset Player",220,28); reset:SetPoint("BOTTOMRIGHT",config,"BOTTOMRIGHT",-114,18); frameUI.reset=reset
    reset:SetScript("OnClick",function()
        if not InCombatLockdown() then
            ClearAuraPositionPreview(); RestoreFramePreview(); ns.ConfigSessionStageFrameReset(selectedType)
            MarkPending("Frame reset is pending."); ns.RefreshConfig()
        end
    end)
    CreateRaidPreviewControls(framesPage)
end

local function CreateFramesPage()
    framesPage=CreateFrame("Frame",nil,config); framesPage:SetPoint("TOPLEFT",16,-106); framesPage:SetPoint("BOTTOMRIGHT",-16,64)
    CreateFramesNavigation()
    CreateFramesHeader()
    CreateFrameLayoutControls(frameUI.categories.Layout.Panel)
    CreateGroupLayoutControls(frameUI.categories.Layout.Panel)
    CreateTextControls(frameUI.categories.Text.Panel)
    CreateAppearanceControls(frameUI.categories.Appearance.Panel)
    CreateIndicatorControls(frameUI.categories.Indicators.Panel)
    CreateFramesActions()
end

local function CreateAuraDisplayControls(parent)
    local panel=MakeFrameSection(parent,"Display",0,-82,426,112)
    auraEnableButton=MakeButton(panel,"Enabled: On",150,26); auraEnableButton:SetPoint("TOPLEFT",18,-36)
    auraEnableButton:SetScript("OnClick",function()
        auraWorking.enabled=auraWorking.enabled==false; StageAuraValue("enabled",auraWorking.enabled)
        if selectedType=="raid" then PreviewAuraSliders() end
        RefreshAuraControls()
        RefreshAuraPositionPreview()
    end)
    auraTextButton=MakeButton(panel,"Cooldown Text: On",190,26); auraTextButton:SetPoint("TOPLEFT",198,-36)
    auraTextButton:SetScript("OnClick",function()
        auraWorking.showText=auraWorking.showText==false; StageAuraValue("showText",auraWorking.showText); RefreshAuraControls()
    end)
end

local function CreateAuraSizeControls(parent)
    local panel=MakeFrameSection(parent,"Size & Spacing",442,-82,426,112)
    auraSizeSlider=MakeSlider(panel,"AuraIconSize","Icon Size",12,40,1,110); auraSizeSlider:SetPoint("TOPLEFT",18,-44)
    auraSizeSlider:HookScript("OnValueChanged",function(_,v)
        if not refreshing then StageAuraValue("iconSize",Round(v)); if selectedType=="raid" then PreviewAuraSliders() end end
    end)
    auraCountSlider=MakeSlider(panel,"AuraCount","Max Icons",1,12,1,110); auraCountSlider:SetPoint("TOPLEFT",158,-44)
    auraCountSlider:HookScript("OnValueChanged",function(_,v)
        if not refreshing then StageAuraValue("maxCount",Round(v)); PreviewAuraSliders() end
    end)
    auraSpacingSlider=MakeSlider(panel,"AuraSpacing","Spacing",0,10,1,110); auraSpacingSlider:SetPoint("TOPLEFT",298,-44)
    auraSpacingSlider:HookScript("OnValueChanged",function(_,v)
        if not refreshing then StageAuraValue("spacing",Round(v)); PreviewAuraSliders() end
    end)
end

local function CreateAuraPositionControls(parent)
    local panel=MakeFrameSection(parent,"Position",0,-210,426,100)
    local function StageAuraPosition()
        if refreshing or not AuraAvailable(selectedType,selectedAura) then return end
        StageAuraValue("xOffset",Round(auraXSlider:GetValue())); StageAuraValue("yOffset",Round(auraYSlider:GetValue()))
        PreviewAuraSliders()
    end
    auraXSlider=MakeSlider(panel,"AuraXOffset","X Offset",-400,400,1,174); auraXSlider:SetPoint("TOPLEFT",18,-44); auraXSlider:HookScript("OnValueChanged",StageAuraPosition)
    auraYSlider=MakeSlider(panel,"AuraYOffset","Y Offset",-400,400,1,174); auraYSlider:SetPoint("TOPLEFT",234,-44); auraYSlider:HookScript("OnValueChanged",StageAuraPosition)
end

local function CreateAuraLayoutControls(parent)
    local panel=MakeFrameSection(parent,"Layout",442,-210,426,100)
    auraAnchorButton=MakeButton(panel,"Anchor: Top",180,26); auraAnchorButton:SetPoint("TOPLEFT",18,-30)
    auraAnchorButton:SetScript("OnClick",function()
        auraWorking.anchor=Cycle(auraWorking.anchor,ANCHOR_ORDER); StageAuraValue("anchor",auraWorking.anchor); PreviewAuraSliders(); RefreshAuraControls()
    end)
    auraGrowthButton=MakeButton(panel,"Growth: Right",180,26); auraGrowthButton:SetPoint("LEFT",auraAnchorButton,"RIGHT",8,0)
    auraGrowthButton:SetScript("OnClick",function()
        auraWorking.growth=Cycle(auraWorking.growth,GROWTH_ORDER); StageAuraValue("growth",auraWorking.growth)
        if selectedType=="raid" then PreviewAuraSliders() end; RefreshAuraControls()
    end)
    local note=panel:CreateFontString(nil,"OVERLAY"); note:SetFont(FONT,9,"OUTLINE"); note:SetTextColor(unpack(Skin.text))
    note:SetPoint("TOPLEFT",18,-66); note:SetWidth(390); note:SetJustifyH("LEFT")
    note:SetText("X/Y offsets are measured from this frame's Top or Bottom anchor edge."); note:SetTextColor(unpack(Skin.muted))
end

local function CreateBuffFilteringControls(parent)
    buffFilterPanel=CreateFrame("Frame",nil,parent); buffFilterPanel:SetPoint("TOPLEFT",0,-322); buffFilterPanel:SetSize(868,42)
    local check=CreateFrame("CheckButton",nil,buffFilterPanel,"UICheckButtonTemplate"); Skin.Check(check)
    check:SetSize(24,24); check:SetPoint("TOPLEFT",10,-4); auraUI.filtering=check
    local label=check:CreateFontString(nil,"OVERLAY"); label:SetFont(FONT,12,"OUTLINE"); label:SetTextColor(unpack(Skin.text)); label:SetPoint("LEFT",check,"RIGHT",2,0)
    label:SetText("Enable Buff Filtering")
    check:SetScript("OnClick",function(self)
        if refreshing or selectedAura~="buffs" or not AuraAvailable(selectedType,"buffs") then return end
        StageAuraValue("filteringEnabled",self:GetChecked() and true or false)
        PreviewAuraSliders()
    end)
    check:SetScript("OnEnter",function(self)
        GameTooltip:SetOwner(self,"ANCHOR_RIGHT"); GameTooltip:SetText("Enable Buff Filtering")
        GameTooltip:AddLine("On: your buffs from the profile-wide tracked list. Off: all helpful buffs on this frame.",0.8,0.8,0.8,true); GameTooltip:Show()
    end)
    check:SetScript("OnLeave",GameTooltip_Hide)
    manageTrackedButton=MakeButton(buffFilterPanel,"Manage Tracked Buffs",180,24); manageTrackedButton:SetPoint("TOPLEFT",442,-4)
    local scope=buffFilterPanel:CreateFontString(nil,"OVERLAY"); scope:SetFont(FONT,10,"OUTLINE"); scope:SetTextColor(unpack(Skin.text))
    scope:SetPoint("TOPLEFT",634,-11); scope:SetText("Tracked list: profile-wide"); scope:SetTextColor(unpack(Skin.muted))
end

local function CreateTrackedBuffManager()
    trackedBuffWindow=CreateFrame("Frame","MIUF_TrackedBuffWindow",UIParent,"BackdropTemplate"); trackedBuffWindow:SetSize(620,300); trackedBuffWindow:SetPoint("CENTER"); trackedBuffWindow:SetFrameStrata("DIALOG"); trackedBuffWindow:SetBackdrop({bgFile=MEDIA,edgeFile=MEDIA,edgeSize=1}); Skin.Panel(trackedBuffWindow,Skin.background); trackedBuffWindow:Hide()
    local function Choice(x,y)
        local b=CreateFrame("Button",nil,trackedBuffWindow,"BackdropTemplate"); b:SetSize(34,34); b:SetPoint("TOPLEFT",x,y); b:SetBackdrop({bgFile=MEDIA,edgeFile=MEDIA,edgeSize=1}); Skin.Button(b); b.icon=b:CreateTexture(nil,"ARTWORK"); b.icon:SetPoint("TOPLEFT",2,-2); b.icon:SetPoint("BOTTOMRIGHT",-2,2); return b
    end
    for i=1,24 do local col=(i-1)%12; local row=math.floor((i-1)/12); seenBuffButtons[i]=Choice(14+col*40,-60-row*40); trackedBuffButtons[i]=Choice(14+col*40,-168-row*40) end
    local seenTitle=trackedBuffWindow:CreateFontString(nil,"OVERLAY"); seenTitle:SetFont(FONT,11,"OUTLINE"); seenTitle:SetTextColor(unpack(Skin.text)); seenTitle:SetPoint("TOPLEFT",14,-42); seenTitle:SetText("Seen Buffs - click to track")
    local trackedTitle=trackedBuffWindow:CreateFontString(nil,"OVERLAY"); trackedTitle:SetFont(FONT,11,"OUTLINE"); trackedTitle:SetTextColor(unpack(Skin.text)); trackedTitle:SetPoint("TOPLEFT",14,-150); trackedTitle:SetText("Tracked Buffs - click to stop tracking")
    local close=MakeButton(trackedBuffWindow,"Back to Auras",120,24); close:SetPoint("BOTTOMLEFT",14,12); close:SetScript("OnClick",function() trackedBuffWindow:Hide(); config:Show() end)
    local clear=MakeButton(trackedBuffWindow,"Clear Seen History",130,24); clear:SetPoint("LEFT",close,"RIGHT",8,0); clear:SetScript("OnClick",function() if not InCombatLockdown() then ns.ClearSeenBuffs(); RefreshTrackedWindow() end end)
    manageTrackedButton:SetScript("OnClick",function() RefreshTrackedWindow(); internalHide=true; config:Hide(); internalHide=false; trackedBuffWindow:Show() end)
end

local function CreateAuraActions(parent)
    auraLockButton=MakeButton(parent,"Preview Position",180,26); auraLockButton:SetPoint("TOPRIGHT",0,0)
    auraLockButton:SetScript("OnClick",function()
        if not InCombatLockdown() then
            ns.PreviewAuraMover(selectedType,selectedAura,not ns.IsAuraMoverPreviewEnabled(selectedType,selectedAura))
            RefreshAuraPositionPreview()
        end
    end)
    local reset=MakeButton(parent,"Reset Player Buffs",240,28); reset:SetPoint("BOTTOMLEFT",0,0); auraUI.reset=reset
    reset:SetScript("OnClick",function()
        if not InCombatLockdown() then
            ClearCastbarPreview(); RestoreAuraPreview(); if not AuraAvailable(selectedType,selectedAura) then return end
            ns.ConfigSessionStageAuraReset(selectedType,selectedAura); MarkPending("Aura reset is pending."); ns.RefreshConfig()
        end
    end)
end

local function CreateAurasPage()
    aurasPage=frameUI.categories.Auras.Panel
    auraLabel=aurasPage:CreateFontString(nil,"OVERLAY"); auraLabel:SetFont(FONT,13,"OUTLINE"); auraLabel:SetTextColor(unpack(Skin.text)); auraLabel:SetPoint("TOPLEFT",0,-6)
    for _,auraType in ipairs(AURA_TYPES) do
        local button=MakeNavigationButton(aurasPage,AURA_NAMES[auraType],140)
        button:SetScript("OnClick",function() RestoreAuraPreview(true); selectedAura=auraType; ns.RefreshConfig() end)
        auraButtons[auraType]=button
    end
    CreateAuraDisplayControls(aurasPage)
    CreateAuraSizeControls(aurasPage)
    CreateAuraPositionControls(aurasPage)
    CreateAuraLayoutControls(aurasPage)
    CreateBuffFilteringControls(aurasPage)
    CreateTrackedBuffManager()
    CreateAuraActions(aurasPage)
end

local function CreateProfilesPage()
    profilesPage=CreateFrame("Frame",nil,config); profilesPage:SetPoint("TOPLEFT",160,-80); profilesPage:SetPoint("BOTTOMRIGHT",-10,50)
    local section=MakeSection(profilesPage,"Profile Management",690,430); section:SetPoint("TOPLEFT",20,-62)

    profileCurrentLabel=section:CreateFontString(nil,"OVERLAY"); profileCurrentLabel:SetFont(FONT,14,"OUTLINE"); profileCurrentLabel:SetTextColor(unpack(Skin.text)); profileCurrentLabel:SetPoint("TOPLEFT",18,-38)
    profileCharacterLabel=section:CreateFontString(nil,"OVERLAY"); profileCharacterLabel:SetFont(FONT,10,"OUTLINE"); profileCharacterLabel:SetTextColor(unpack(Skin.text)); profileCharacterLabel:SetPoint("TOPLEFT",18,-62); profileCharacterLabel:SetTextColor(unpack(Skin.muted))

    local listTitle=section:CreateFontString(nil,"OVERLAY"); listTitle:SetFont(FONT,11,"OUTLINE"); listTitle:SetTextColor(unpack(Skin.text)); listTitle:SetPoint("TOPLEFT",18,-96); listTitle:SetText("Profiles")
    for i=1,10 do
        local b=MakeButton(section,"",220,26); b:SetPoint("TOPLEFT",18,-118-((i-1)*29)); b:SetScript("OnClick",function(self)
            selectedProfileName=self.ProfileName
            SetProfileStatus("Selected "..selectedProfileName..". Use Profile will switch this character and reload the UI.",false)
            RefreshProfilesControls()
        end); profileButtons[i]=b
    end

    local nameLabel=section:CreateFontString(nil,"OVERLAY"); nameLabel:SetFont(FONT,11,"OUTLINE"); nameLabel:SetTextColor(unpack(Skin.text)); nameLabel:SetPoint("TOPLEFT",275,-96); nameLabel:SetText("Profile name")
    profileNameBox=CreateFrame("EditBox",nil,section,"InputBoxTemplate"); profileNameBox:SetSize(250,24); profileNameBox:SetPoint("TOPLEFT",275,-118); profileNameBox:SetAutoFocus(false); profileNameBox:SetMaxLetters(40); Skin.Edit(profileNameBox)
    profileNameBox:SetScript("OnEnterPressed",function(self) self:ClearFocus() end)
    profileNameBox:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)

    local use=MakeButton(section,"Use Profile",120,28); use:SetPoint("TOPLEFT",275,-158); use:SetScript("OnClick",function()
        if InCombatLockdown() then SetProfileStatus("Profiles cannot be switched during combat.",true); return end
        if ns.ConfigSessionIsDirty() then SetProfileStatus("Apply pending changes before switching profiles.",true); return end
        local target=selectedProfileName or ns.GetActiveProfileName()
        if target==ns.GetActiveProfileName() then SetProfileStatus(target.." is already active.",false); return end
        local ok,msg=ns.SetActiveProfile(target)
        if not ok then SetProfileStatus(msg,true); return end
        ReloadUI()
    end)

    local create=MakeButton(section,"Create New",120,28); create:SetPoint("LEFT",use,"RIGHT",8,0); create:SetScript("OnClick",function()
        if InCombatLockdown() then SetProfileStatus("Profiles cannot be changed during combat.",true); return end
        local ok,msg=ns.CreateProfile(profileNameBox:GetText())
        if not ok then SetProfileStatus(msg,true); return end
        selectedProfileName=msg; profileNameBox:SetText(""); SetProfileStatus("Created "..msg.." from defaults.",false); RefreshProfilesControls()
    end)

    local copy=MakeButton(section,"Copy Current",120,28); copy:SetPoint("TOPLEFT",275,-198); copy:SetScript("OnClick",function()
        if InCombatLockdown() then SetProfileStatus("Profiles cannot be changed during combat.",true); return end
        local ok,msg=ns.CopyProfile(ns.GetActiveProfileName(),profileNameBox:GetText())
        if not ok then SetProfileStatus(msg,true); return end
        selectedProfileName=msg; profileNameBox:SetText(""); SetProfileStatus("Copied current profile to "..msg..".",false); RefreshProfilesControls()
    end)

    local rename=MakeButton(section,"Rename Selected",120,28); rename:SetPoint("LEFT",copy,"RIGHT",8,0); rename:SetScript("OnClick",function()
        if InCombatLockdown() then SetProfileStatus("Profiles cannot be changed during combat.",true); return end
        local source=selectedProfileName or ns.GetActiveProfileName()
        local ok,msg=ns.RenameProfile(source,profileNameBox:GetText())
        if not ok then SetProfileStatus(msg,true); return end
        selectedProfileName=msg; profileNameBox:SetText(""); SetProfileStatus("Profile renamed to "..msg..".",false); RefreshProfilesControls()
    end)

    local delete=MakeButton(section,"Delete Selected",120,28); delete:SetPoint("TOPLEFT",275,-238); delete:SetScript("OnClick",function()
        if InCombatLockdown() then SetProfileStatus("Profiles cannot be changed during combat.",true); return end
        local source=selectedProfileName
        if not source then SetProfileStatus("Select a profile first.",true); return end
        local ok,msg=ns.DeleteProfile(source)
        if not ok then SetProfileStatus(msg,true); return end
        selectedProfileName=ns.GetActiveProfileName(); SetProfileStatus("Deleted "..source..".",false); RefreshProfilesControls()
    end)

    local note=section:CreateFontString(nil,"OVERLAY"); note:SetFont(FONT,10,"OUTLINE"); note:SetTextColor(unpack(Skin.text)); note:SetPoint("TOPLEFT",275,-292); note:SetWidth(380); note:SetJustifyH("LEFT")
    note:SetText("Create New starts from defaults. Copy Current duplicates every setting in the active profile. Each character remembers which profile it uses. Switching profiles reloads the UI so secure frames and aura containers rebuild from one consistent settings set.")
    note:SetTextColor(unpack(Skin.muted))

    profileActionStatus=section:CreateFontString(nil,"OVERLAY"); profileActionStatus:SetFont(FONT,10,"OUTLINE"); profileActionStatus:SetTextColor(unpack(Skin.text)); profileActionStatus:SetPoint("TOPLEFT",275,-365); profileActionStatus:SetWidth(380); profileActionStatus:SetJustifyH("LEFT")
end

local function CreateConfig()
    if config then return end; CreateShell(); CreateFramesPage(); CreateAurasPage(); CreateProfilesPage()
    local watcher=CreateFrame("Frame",nil,config); watcher:RegisterEvent("UNIT_AURA"); watcher:SetScript("OnEvent",function() if (config:IsShown() or trackedBuffWindow:IsShown()) and IsAurasSelected() and selectedAura=="buffs" then RefreshTrackedWindow() end end)
    config:HookScript("OnShow",function()
        if not ns.ConfigSessionBegin() then internalHide=true; config:Hide(); internalHide=false; return end
        ns.RefreshConfig()
    end); internalHide=true; config:Hide(); internalHide=false
end

function ns.CloseConfig()
    if closing then return end
    closing=true
    ns.StopConfigurationMovers()
    ClearStatusIconPreview(); ClearCastbarPreview(); ClearAuraPositionPreview()
    previewFrameType=nil; previewAuraUnitType,previewAuraType=nil,nil
    if fontMenu then fontMenu:Hide() end
    if textureMenu then textureMenu:Hide() end
    internalHide=true
    config:Hide()
    if trackedBuffWindow then trackedBuffWindow:Hide() end
    if collapsedBar then collapsedBar:Hide() end
    internalHide=false; collapsed=false
    local restored,err=ns.ConfigSessionClose()
    if err then print("|cffff5555MIUF: Close restoration will be retried. "..tostring(err).."|r") end
    ns.UpdateLockMoversButton()
    closing=false
end

function ns.RestoreConfig()
    if not ns.ConfigSessionBegin() then return end
    collapsed=false
    if collapsedBar then collapsedBar:Hide() end
    if trackedBuffWindow then trackedBuffWindow:Hide() end
    config:Show()
end

function ns.CollapseConfig()
    if not collapsedBar then
        collapsedBar=CreateFrame("Frame","MIUF_CollapsedConfig",UIParent,"BackdropTemplate")
        collapsedBar:SetSize(300,38); collapsedBar:SetPoint("TOP",UIParent,"TOP",0,-40)
        collapsedBar:SetFrameStrata("DIALOG"); collapsedBar:SetClampedToScreen(true)
        collapsedBar:SetMovable(true); collapsedBar:EnableMouse(true); collapsedBar:RegisterForDrag("LeftButton")
        collapsedBar:SetScript("OnDragStart",collapsedBar.StartMoving)
        collapsedBar:SetScript("OnDragStop",collapsedBar.StopMovingOrSizing)
        Skin.Panel(collapsedBar,Skin.background)
        local restore=MakeButton(collapsedBar,"MIUF Config - Restore",246,24)
        restore:SetPoint("LEFT",6,0); restore:SetScript("OnClick",ns.RestoreConfig)
        local close=MakeButton(collapsedBar,"X",28,24)
        close:SetPoint("RIGHT",-6,0); close:SetScript("OnClick",ns.CloseConfig)
    end
    collapsed=true; internalHide=true; config:Hide(); internalHide=false
    collapsedBar:Show()
end

function ns.ToggleConfig()
    CreateConfig()
    if collapsed then ns.RestoreConfig()
    elseif config:IsShown() or trackedBuffWindow:IsShown() then ns.CloseConfig()
    else ns.RestoreConfig() end
end

-- User frame-lock actions reveal pending work; internal mover refreshes do not.
function ns.ShowConfigForPendingFrameChanges()
    if InCombatLockdown() or not ns.ConfigSessionIsDirty() then return end
    CreateConfig()
    if collapsed then return end
    if not config:IsShown() then ns.RestoreConfig() end
    ns.RefreshConfig()
end

local lockMoversButton=MakeButton(UIParent,"Lock Movers",120,28)
lockMoversButton:SetPoint("TOP",UIParent,"TOP",0,-100)
lockMoversButton:SetFrameStrata("DIALOG")
lockMoversButton:SetClampedToScreen(true)
lockMoversButton:Hide()

function ns.UpdateLockMoversButton()
    local frameLocked,auraLocked=ns.AreFrameMoversLocked(),ns.AreAuraMoversLocked()
    lockMoversButton:SetShown(not InCombatLockdown() and (not frameLocked or not auraLocked))
    if frameLockButton then frameLockButton:SetText(frameLocked and "Unlock Frames" or "Lock Frames") end
    if auraLockButton then auraLockButton:SetText(ns.IsAuraMoverPreviewEnabled(selectedType,selectedAura) and "End Preview" or "Preview Position") end
end

lockMoversButton:SetScript("OnClick",function()
    if InCombatLockdown() then return end
    local lockingFrames=not ns.AreFrameMoversLocked()
    ns.SetFrameMoversLockedState(true); ns.SetAuraMoversLockedState(true)
    ns.SetMoversLocked(true)
    if lockingFrames then ns.ShowConfigForPendingFrameChanges() end
end)

local combatWatcher=CreateFrame("Frame")
combatWatcher:RegisterEvent("PLAYER_REGEN_DISABLED"); combatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED"); combatWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
combatWatcher:SetScript("OnEvent",function(_,event)
    ClearAuraPositionPreview()
    ClearCastbarPreview()
    if event~="PLAYER_ENTERING_WORLD" then
        if not InCombatLockdown() then
            ns.ConfigSessionFinishClose()
            RestoreFramePreview(); RestoreAuraPreview()
        end
        ns.SetAuraMoversLocked(InCombatLockdown() or ns.AreAuraMoversLocked())
        if config and config:IsShown() then ns.RefreshConfig() end
    end
    ns.UpdateLockMoversButton()
end)
