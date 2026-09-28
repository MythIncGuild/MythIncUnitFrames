local ADDON_NAME, ns = ...

local names = {player="Player",target="Target",focus="Focus",pet="Pet",targettarget="Target of Target",party="Party",boss="Boss",raid="Raid"}
local keys = {party="party1",boss="boss1",raid="raid"}
local selected, panel, title, drag
local fields = {}
local FONT = "Fonts\\FRIZQT__.TTF"
local MEDIA = "Interface\\Buttons\\WHITE8x8"

local function Resolve()
    if not selected then return end
    local owner
    if selected=="party" then owner=ns.partyFrameMoverOwner
    elseif selected=="raid" then owner=ns.raidFrameMoverOwner
    else owner=ns.frames and ns.frames[keys[selected] or selected] end
    return owner,owner and owner.MIUF_Mover,keys[selected] or selected
end

local function Eligible()
    local owner,mover=Resolve()
    return owner and mover and mover:IsVisible() and not InCombatLockdown()
        and not ns.AreFrameMoversLocked()
        and (not ns.IsPrecisionPositionContext or ns.IsPrecisionPositionContext())
end

local function StopObserver()
    if panel then panel:SetScript("OnUpdate",nil) end
end

function ns.CancelPrecisionPositionDrag()
    drag=nil
    StopObserver()
end

local function DisplayPosition()
    if not panel or not selected then return end
    local _,mover,key=Resolve()
    local position
    if drag and drag.mover==mover then
        local point,_,relativePoint,x,y=drag.target:GetPoint(1)
        if point then position={point=point,relativePoint=relativePoint,x=x,y=y} end
    end
    position=position or ns.ConfigSessionGetPosition(key)
    for axis,box in pairs(fields) do
        if not box:HasFocus() then
            local value=tostring(math.floor((position[axis] or 0)+0.5))
            if box:GetText()~=value then box:SetText(value) end
        end
    end
end

local function Commit(box)
    if not box.MIUF_Edited then return end
    box.MIUF_Edited=nil
    if not Eligible() or drag then return end
    local value=tonumber(box:GetText())
    if not value or value~=value or value==math.huge or value==-math.huge then return end
    local owner,_,key=Resolve()
    local position=ns.ConfigSessionGetPosition(key)
    position[box.MIUF_Axis]=math.floor(value+0.5)
    ns.ConfigSessionStagePosition(key,position)
    if keys[selected] then ns.ApplyGroupLayout(selected)
    else
        owner:ClearAllPoints()
        owner:SetPoint(position.point,UIParent,position.relativePoint,position.x,position.y)
    end
    if ns.RefreshConfig then ns.RefreshConfig() end
end

local function CreatePanel()
    panel=CreateFrame("Frame","MIUF_PrecisionPosition",UIParent,"BackdropTemplate")
    panel:SetSize(238,82); panel:SetPoint("TOP",UIParent,"TOP",0,-140)
    panel:SetFrameStrata("DIALOG"); panel:SetClampedToScreen(true); panel:EnableMouse(true)
    panel:SetBackdrop({bgFile=MEDIA,edgeFile=MEDIA,edgeSize=1})
    panel:SetBackdropColor(0.035,0.039,0.040,0.98); panel:SetBackdropBorderColor(0.18,0.20,0.20,1)
    title=panel:CreateFontString(nil,"OVERLAY"); title:SetFont(FONT,12,"OUTLINE")
    title:SetPoint("TOPLEFT",12,-12); title:SetTextColor(0.86,0.85,0.81,1)
    for index,axis in ipairs({"x","y"}) do
        local label=panel:CreateFontString(nil,"OVERLAY"); label:SetFont(FONT,11,"OUTLINE")
        label:SetPoint("TOPLEFT",12+(index-1)*114,-45); label:SetText(axis:upper())
        label:SetTextColor(0.56,0.58,0.57,1)
        local box=CreateFrame("EditBox",nil,panel,"InputBoxTemplate")
        box:SetSize(78,24); box:SetPoint("TOPLEFT",32+(index-1)*114,-37)
        box:SetAutoFocus(false); box:SetFont(FONT,12,""); box:SetTextColor(0.86,0.85,0.81,1)
        box.MIUF_Axis=axis; fields[axis]=box
        box:SetScript("OnTextChanged",function(self,user) if user then self.MIUF_Edited=true end end)
        box:SetScript("OnEnterPressed",function(self) Commit(self); self:ClearFocus(); DisplayPosition() end)
        box:SetScript("OnEditFocusLost",function(self) Commit(self); DisplayPosition() end)
        box:SetScript("OnEscapePressed",function(self) self.MIUF_Edited=nil; self:ClearFocus(); DisplayPosition() end)
    end
    panel:SetScript("OnHide",function()
        StopObserver()
        for _,box in pairs(fields) do box.MIUF_Edited=nil; box:ClearFocus() end
    end)
end

function ns.RefreshPrecisionPosition()
    local _,mover=Resolve()
    if drag and (drag.mover~=mover or not mover:IsVisible() or ns.AreFrameMoversLocked() or InCombatLockdown()) then
        ns.CancelPrecisionPositionDrag()
    end
    if not Eligible() then
        StopObserver()
        if panel then panel:Hide() end
        return
    end
    if not panel then CreatePanel() end
    title:SetText(names[selected].." Position")
    panel:Show(); DisplayPosition()
    panel:SetScript("OnUpdate",drag and function() DisplayPosition() end or nil)
end

function ns.SelectPrecisionPosition(unitType)
    if not names[unitType] or InCombatLockdown() or ns.AreFrameMoversLocked() then return end
    if selected~=unitType then
        -- An unfinished field belongs to the old selection, never the new one.
        for _,box in pairs(fields) do box.MIUF_Edited=nil; box:ClearFocus() end
        ns.CancelPrecisionPositionDrag()
    end
    selected=unitType
    ns.RefreshPrecisionPosition()
end

function ns.BeginPrecisionPositionDrag(unitType,mover,target)
    ns.SelectPrecisionPosition(unitType)
    if InCombatLockdown() or ns.AreFrameMoversLocked() then return end
    for _,box in pairs(fields) do box.MIUF_Edited=nil; box:ClearFocus() end
    drag={mover=mover,target=target}
    ns.RefreshPrecisionPosition()
end

function ns.EndPrecisionPositionDrag(mover)
    if drag and drag.mover==mover then ns.CancelPrecisionPositionDrag() end
    ns.RefreshPrecisionPosition()
end

function ns.RegisterPrecisionMover(mover,unitType)
    local function Select(_,button) if button=="LeftButton" then ns.SelectPrecisionPosition(unitType) end end
    mover:HookScript("OnMouseDown",Select)
    if mover.MIUF_ResizeHandle then mover.MIUF_ResizeHandle:HookScript("OnMouseDown",Select) end
    mover:HookScript("OnHide",function()
        if drag and drag.mover==mover then ns.CancelPrecisionPositionDrag() end
        ns.RefreshPrecisionPosition()
    end)
end

local watcher=CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_REGEN_DISABLED"); watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
watcher:SetScript("OnEvent",function() ns.RefreshPrecisionPosition() end)
