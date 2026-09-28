local ADDON_NAME, ns = ...

local ROLE_ORDER = { TANK = 1, HEALER = 2, DAMAGER = 3, NONE = 4 }
local previewLayouts = {}
local previewFrames = { party = {}, boss = {} }
local partyUnits = { "party1", "party2", "party3", "party4" }
local partyOrdered = {}
local singleFrame = {}
local raidGroupCounts = {}

local PREVIEW_BG = "Interface\\Buttons\\WHITE8x8"
local PREVIEW_FONT = "Fonts\\FRIZQT__.TTF"

local function AnchorGroupFrames(ordered, layout, positionKey)
    if #ordered == 0 then return nil end

    local first = ordered[1]
    local position = ns.ConfigSessionGetPosition(positionKey)
    if position then
        first:ClearAllPoints()
        first:SetPoint(position.point, UIParent, position.relativePoint, position.x, position.y)
    end

    local previous = first
    local spacing = layout.spacing or 0
    for index = 2, #ordered do
        local frame = ordered[index]
        frame:ClearAllPoints()
        if layout.orientation == "HORIZONTAL" then
            if layout.direction == "LEFT" then
                frame:SetPoint("TOPRIGHT", previous, "TOPLEFT", -spacing, 0)
            else
                frame:SetPoint("TOPLEFT", previous, "TOPRIGHT", spacing, 0)
            end
        elseif layout.direction == "UP" then
            frame:SetPoint("BOTTOMLEFT", previous, "TOPLEFT", 0, spacing)
        else
            frame:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -spacing)
        end
        previous = frame
    end
    return first
end

local function GetRoleRank(frame)
    local unit = frame and frame.__unit
    if not unit then return ROLE_ORDER.NONE end
    return ROLE_ORDER[UnitGroupRolesAssigned(unit)] or ROLE_ORDER.NONE
end

local function GetUnitRank(frame)
    local unit = frame and frame.__unit or ""
    local partyIndex = unit:match("^party(%d+)$")
    if partyIndex then return tonumber(partyIndex) or 99 end
    if unit == "player" then return 5 end
    return 99
end

local function ComparePartyFrames(a, b)
    local roleA, roleB = GetRoleRank(a), GetRoleRank(b)
    if roleA ~= roleB then return roleA < roleB end
    return GetUnitRank(a) < GetUnitRank(b)
end

local function AnchorSingleFrame(frame, layout, positionKey)
    singleFrame[1] = frame
    local owner = AnchorGroupFrames(singleFrame, layout, positionKey)
    singleFrame[1] = nil
    return owner
end

local function CreatePreviewFrame(unitType, index)
    local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(40)
    frame:SetBackdrop({ bgFile = PREVIEW_BG, edgeFile = PREVIEW_BG, edgeSize = 1 })
    frame:SetBackdropColor(0.05, 0.35, 0.8, 0.14)
    frame:SetBackdropBorderColor(0.2, 0.65, 1, 0.75)
    frame:EnableMouse(false)

    local label = frame:CreateFontString(nil, "OVERLAY")
    label:SetFont(PREVIEW_FONT, 10, "OUTLINE")
    label:SetPoint("CENTER")
    label:SetText(unitType == "party" and ("Party " .. index) or ("Boss " .. index))
    label:SetTextColor(0.75, 0.9, 1, 0.9)
    frame.Label = label
    frame:Hide()
    return frame
end

local function EnsurePreviewFrames(unitType, count)
    local list = previewFrames[unitType]
    if not list then return nil end
    for index = 1, count do
        if not list[index] then list[index] = CreatePreviewFrame(unitType, index) end
    end
    return list
end

local function HideGroupPreview(unitType)
    local list = previewFrames[unitType]
    if not list then return end
    for _, frame in ipairs(list) do frame:Hide() end
end

local function PositionPreviewFrame(frame, previous, layout, spacing)
    frame:ClearAllPoints()
    if layout.orientation == "HORIZONTAL" then
        if layout.direction == "LEFT" then
            frame:SetPoint("TOPRIGHT", previous, "TOPLEFT", -spacing, 0)
        else
            frame:SetPoint("TOPLEFT", previous, "TOPRIGHT", spacing, 0)
        end
    elseif layout.direction == "UP" then
        frame:SetPoint("BOTTOMLEFT", previous, "TOPLEFT", 0, spacing)
    else
        frame:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -spacing)
    end
end

local function GetLiveGroupSize(unitType)
    if not ns.frames then return nil end
    local frame = unitType == "party" and ns.frames.party1 or ns.frames.boss1
    if not frame then return nil end
    local width, height = frame:GetWidth(), frame:GetHeight()
    if not width or not height or width <= 0 or height <= 0 then return nil end
    return width, height
end

function ns.PreviewGroupLayout(unitType, layoutOverride, sizeOverride)
    if InCombatLockdown() or (unitType ~= "party" and unitType ~= "boss") then return end
    if ns.AreFrameMoversLocked and ns.AreFrameMoversLocked() then
        HideGroupPreview(unitType)
        return
    end
    if ns.IsUnitTypePreviewEnabled and not ns.IsUnitTypePreviewEnabled(unitType) then
        HideGroupPreview(unitType)
        return
    end
    if ns.IsFrameTypeEnabled and not ns.IsFrameTypeEnabled(unitType) then
        HideGroupPreview(unitType)
        return
    end

    local active = ns.ConfigSessionIsActive and ns.ConfigSessionIsActive()
    local savedLayout = (active and ns.ConfigSessionGetGroup(unitType) or ns.GetGroupLayout(unitType)) or {}
    local layout = {}
    for key, value in pairs(savedLayout) do layout[key] = value end
    if layoutOverride then
        for key, value in pairs(layoutOverride) do layout[key] = value end
    end
    previewLayouts[unitType] = layout

    local savedSize = ns.GetSize(unitType) or { width = 200, height = 40 }
    sizeOverride = sizeOverride or (active and ns.ConfigSessionGetFrame(unitType).size)
    local liveWidth, liveHeight = GetLiveGroupSize(unitType)
    local width = tonumber(sizeOverride and sizeOverride.width) or tonumber(liveWidth) or tonumber(savedSize.width) or 200
    local height = tonumber(sizeOverride and sizeOverride.height) or tonumber(liveHeight) or tonumber(savedSize.height) or 40
    local count = unitType == "party" and (layout.includePlayer and 5 or 4) or 5
    local list = EnsurePreviewFrames(unitType, count)
    if not list then return end

    local positionKey = unitType == "party" and "party1" or "boss1"
    local position = active and ns.ConfigSessionGetPosition(positionKey) or ns.GetPosition(positionKey)
    if not position then
        HideGroupPreview(unitType)
        return
    end

    local spacing = tonumber(layout.spacing) or 0
    local previous
    for index = 1, count do
        local frame = list[index]
        frame:SetSize(width, height)
        if index == 1 then
            frame:ClearAllPoints()
            local owner
            if unitType == "party" then owner = ns.partyFrameMoverOwner or (ns.frames and ns.frames.party1)
            else owner = ns.frames and ns.frames.boss1 end
            local mover = owner and owner.MIUF_Mover
            if mover then frame:SetPoint("TOPLEFT", mover, "TOPLEFT")
            else frame:SetPoint(position.point, UIParent, position.relativePoint, position.x, position.y) end
        else
            PositionPreviewFrame(frame, previous, layout, spacing)
        end
        frame:Show()
        previous = frame
    end
    for index = count + 1, #list do list[index]:Hide() end
end

function ns.ResetGroupPreview(unitType)
    previewLayouts[unitType] = nil
    ns.PreviewGroupLayout(unitType)
end

function ns.ClearGroupPreviewOverrides()
    previewLayouts.party=nil; previewLayouts.boss=nil
    HideGroupPreview("party"); HideGroupPreview("boss")
end

function ns.UpdateGroupPreviews(locked)
    if locked or InCombatLockdown() then
        HideGroupPreview("party")
        HideGroupPreview("boss")
        return
    end
    ns.PreviewGroupLayout("party", previewLayouts.party)
    ns.PreviewGroupLayout("boss", previewLayouts.boss)
end

function ns.ApplyPartyLayout()
    if InCombatLockdown() or not ns.frames then return end
    local layout = ns.GetGroupLayout("party")
    if not layout then return end

    local partyPlayer = ns.frames.partyplayer
    if not ns.IsFrameTypeEnabled("party") or not IsInGroup() or IsInRaid() then
        if partyPlayer then partyPlayer:Hide() end
        ns.partyFrameMoverOwner = AnchorSingleFrame(ns.frames.party1, layout, "party1")
        ns.partyAuraMoverOwner = nil
        if ns.SetFrameMoversLocked and ns.AreFrameMoversLocked then
            ns.SetFrameMoversLocked(ns.AreFrameMoversLocked())
        end
        if ns.RefreshPartyLeaderIndicator then ns.RefreshPartyLeaderIndicator() end
        return
    end

    local ordered = partyOrdered
    for index = #ordered, 1, -1 do ordered[index] = nil end
    for i = 1, 4 do
        local unit = partyUnits[i]
        local frame = ns.frames[unit]
        if frame and UnitExists(unit) then ordered[#ordered + 1] = frame end
    end

    if partyPlayer then
        if layout.includePlayer then
            partyPlayer:Show()
            ordered[#ordered + 1] = partyPlayer
        else
            partyPlayer:Hide()
        end
    end

    table.sort(ordered, ComparePartyFrames)

    local owner = AnchorGroupFrames(ordered, layout, "party1")
    if ns.RefreshPartyLeaderIndicator then ns.RefreshPartyLeaderIndicator() end
    ns.partyFrameMoverOwner = owner or AnchorSingleFrame(ns.frames.party1, layout, "party1")
    ns.partyAuraMoverOwner = owner
    if ns.partyAuraMoverOwner and ns.SetAuraMoversLocked and ns.AreAuraMoversLocked then
        ns.SetAuraMoversLocked(ns.AreAuraMoversLocked())
    end
    if ns.SetFrameMoversLocked and ns.AreFrameMoversLocked then
        ns.SetFrameMoversLocked(ns.AreFrameMoversLocked())
    end
end

function ns.ApplyBossLayout()
    if InCombatLockdown() or not ns.frames then return end
    local layout = ns.GetGroupLayout("boss")
    if not layout then return end

    local ordered = {}
    for i = 1, 5 do
        local frame = ns.frames["boss" .. i]
        if frame then ordered[#ordered + 1] = frame end
    end
    AnchorGroupFrames(ordered, layout, "boss1")
end

function ns.ApplyGroupLayout(unitType)
    if unitType == "party" then ns.ApplyPartyLayout()
    elseif unitType == "boss" then ns.ApplyBossLayout()
    elseif unitType == "raid" then ns.ApplyRaidLayout()
    else return end

    if ns.AreFrameMoversLocked and not ns.AreFrameMoversLocked() then
        ns.PreviewGroupLayout(unitType, previewLayouts[unitType])
    end
end

local originalSetFrameMoversLocked = ns.SetFrameMoversLocked
if originalSetFrameMoversLocked then
    ns.SetFrameMoversLocked = function(locked)
        originalSetFrameMoversLocked(locked)
        ns.UpdateGroupPreviews(locked)
    end
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("GROUP_ROSTER_UPDATE")
watcher:RegisterEvent("PLAYER_ROLES_ASSIGNED")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:SetScript("OnEvent", function(_, event)
    if InCombatLockdown() then
        watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
        ns.UpdateGroupPreviews(true)
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then watcher:UnregisterEvent("PLAYER_REGEN_ENABLED") end
    ns.ApplyPartyLayout()
    -- Roster/role events must not replace an active session's staged anchor
    -- and dimensions, including while its configuration window is collapsed.
    ns.ApplyRaidLayout(not ns.ConfigSessionIsActive())
    if ns.AreFrameMoversLocked then ns.UpdateGroupPreviews(ns.AreFrameMoversLocked()) end
end)
-- Pure geometry: offsets are frame TOPLEFT coordinates relative to the raid anchor.
-- Subgroups and members touch. Vertical subgroup tops align; horizontal lefts align.
function ns.CalculateRaidGeometry(layout, width, height)
    local memberHorizontal = layout.orientation == "HORIZONTAL"
    local totalGroups = layout.legacy40 == true and 8 or 6
    local groupWidth = memberHorizontal and 5 * width or width
    local groupHeight = memberHorizontal and height or 5 * height
    local positions, bounds = {}, { left = math.huge, right = -math.huge, top = -math.huge, bottom = math.huge }
    for index = 1, totalGroups * 5 do
        local group = math.floor((index - 1) / 5)
        local member = (index - 1) % 5
        local column = memberHorizontal and 0 or group
        local row = memberHorizontal and group or 0
        local gx = column * groupWidth
        local gy = -row * groupHeight
        local mx = memberHorizontal and member * width or 0
        local my = memberHorizontal and 0 or -member * height
        local x, y = gx + mx, gy + my
        positions[index] = { x = x, y = y, group = group + 1, member = member + 1 }
        bounds.left = math.min(bounds.left, x); bounds.right = math.max(bounds.right, x + width)
        bounds.top = math.max(bounds.top, y); bounds.bottom = math.min(bounds.bottom, y - height)
    end
    bounds.width = bounds.right - bounds.left; bounds.height = bounds.top - bounds.bottom
    return positions, bounds
end

local raidAnchor, raidPreview, raidGhosts = nil, nil, {}

-- Read-only access to one of the existing configuration ghosts.
function ns.GetGroupStatusPreviewFrame(unitType)
    local frame
    if unitType=="party" then frame=previewFrames.party[1]
    elseif unitType=="raid" then frame=raidGhosts[1] end
    if frame and frame:IsVisible() then return frame end
end

local function PositionRaidAnchor(savedState)
    -- ConfigSession supplies the staged position, or the saved position when
    -- none is staged. Locking visuals must not abandon or commit that position.
    local position = savedState and ns.GetPosition("raid") or ns.ConfigSessionGetPosition("raid")
    raidAnchor:ClearAllPoints()
    raidAnchor:SetPoint(position.point,UIParent,position.relativePoint,position.x,position.y)
end

function ns.GetRaidAnchor()
    if not raidAnchor then
        if InCombatLockdown() then return nil end
        raidAnchor = CreateFrame("Frame", nil, UIParent)
        raidAnchor:SetDontSavePosition(true) -- Position is persisted by the MIUF profile.
        raidAnchor:SetMovable(true)
        local size = ns.GetSize("raid")
        raidAnchor:SetSize(size.width,size.height)
        PositionRaidAnchor()
        ns.raidFrameMoverOwner = raidAnchor
    end
    return raidAnchor
end

function ns.ApplyRaidLayout(savedState)
    if InCombatLockdown() or not raidAnchor then return end
    local size = savedState and ns.GetSize("raid") or ns.ConfigSessionGetFrame("raid").size
    raidAnchor:SetSize(size.width,size.height)
    PositionRaidAnchor(savedState)
    local layout = savedState and ns.GetGroupLayout("raid") or ns.ConfigSessionGetGroup("raid")
    local positions = ns.CalculateRaidGeometry(layout,size.width,size.height)
    for group = 1, 8 do raidGroupCounts[group] = 0 end
    for index, defaultOffset in ipairs(positions) do
        local frame = ns.frames and ns.frames["raid"..index]
        if frame then
            -- raidN is a roster index, not a subgroup slot. Place each token in
            -- its real raid subgroup while preserving roster order within it.
            local offset = defaultOffset
            if IsInRaid() and index <= GetNumGroupMembers() then
                local _, _, subgroup = GetRaidRosterInfo(index)
                if canaccessvalue(subgroup) and subgroup and subgroup >= 1 and subgroup <= 8 then
                    raidGroupCounts[subgroup] = raidGroupCounts[subgroup] + 1
                    local slot = (subgroup - 1) * 5 + raidGroupCounts[subgroup]
                    offset = positions[slot] or defaultOffset
                end
            end
            frame:SetSize(size.width,size.height)
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT",raidAnchor,"TOPLEFT",offset.x,offset.y)
        end
    end
end

function ns.UpdateRaidPreview(locked)
    if locked == nil then locked = ns.AreFrameMoversLocked() end
    if locked or InCombatLockdown() or not ns.ConfigSessionGetEnabled("raid") then
        if raidPreview then raidPreview:Hide() end
        -- Hide only non-secure configuration visuals, never the shared anchor.
        if not InCombatLockdown() then ns.ApplyRaidLayout() end
        return
    end
    local size = ns.ConfigSessionGetFrame("raid").size
    local layout = ns.ConfigSessionGetGroup("raid")
    ns.GetRaidAnchor()
    if not raidPreview then
        raidPreview = CreateFrame("Frame", nil, raidAnchor)
        raidPreview:SetAllPoints(raidAnchor)
        raidPreview:SetFrameStrata("DIALOG")
        -- One non-secure mover owns the eventual group anchor, never a unit frame.
        local mover = CreateFrame("Button", nil, raidPreview, "BackdropTemplate")
        mover:SetAllPoints(raidAnchor); mover:SetFrameLevel(45)
        mover:SetBackdrop({ bgFile = PREVIEW_BG, edgeFile = PREVIEW_BG, edgeSize = 1 })
        mover:SetBackdropColor(0.05, 0.35, 0.8, 0.2)
        mover:SetBackdropBorderColor(0.2, 0.65, 1, 1)
        mover:RegisterForDrag("LeftButton")
        mover:SetScript("OnDragStart", function()
            if not InCombatLockdown() then
                mover.MIUF_RevertedDrag=nil; raidAnchor:StartMoving()
                if ns.BeginPrecisionPositionDrag then ns.BeginPrecisionPositionDrag("raid",mover,raidAnchor) end
            end
        end)
        mover:SetScript("OnDragStop", function()
            if InCombatLockdown() then if ns.EndPrecisionPositionDrag then ns.EndPrecisionPositionDrag(mover) end; return end
            raidAnchor:StopMovingOrSizing()
            if mover.MIUF_RevertedDrag then if ns.EndPrecisionPositionDrag then ns.EndPrecisionPositionDrag(mover) end; return end
            local point, _, relativePoint, x, y = raidAnchor:GetPoint(1)
            ns.ConfigSessionStagePosition("raid", { point = point, relativePoint = relativePoint, x = x, y = y })
            if ns.RefreshConfig then ns.RefreshConfig() end
            if ns.EndPrecisionPositionDrag then ns.EndPrecisionPositionDrag(mover) end
        end)
        raidAnchor.MIUF_Mover = mover
        local resize=ns.CreateMoverResizeHandle(mover)
        mover.MIUF_ResizeHandle=resize
        resize:SetScript("OnMouseDown",function(handle,button)
            if button~="LeftButton" or InCombatLockdown() or ns.AreFrameMoversLocked() then return end
            local left,top=raidAnchor:GetLeft(),raidAnchor:GetTop()
            if not left or not top then return end
            handle.MIUF_ResizeState={left=left,top=top,minW=50,maxW=600,minH=18,maxH=150}
            handle:SetScript("OnUpdate",function(self)
                local state=self.MIUF_ResizeState
                if not state or InCombatLockdown() or ns.AreFrameMoversLocked() then return end
                local width,height=ns.GetMoverResizeDimensions(state)
                local settings=ns.ConfigSessionGetFrame("raid")
                settings.size={width=math.floor(width+0.5),height=math.floor(height+0.5)}
                ns.ConfigSessionStageFrame("raid",settings)
                ns.UpdateRaidPreview()
                if ns.RefreshConfig then ns.RefreshConfig() end
            end)
        end)
        local function StopResize(handle)
            handle:SetScript("OnUpdate",nil); handle.MIUF_ResizeState=nil
        end
        resize:SetScript("OnMouseUp",function(handle,button) if button=="LeftButton" then StopResize(handle) end end)
        resize:SetScript("OnHide",StopResize)
        if ns.RegisterPrecisionMover then ns.RegisterPrecisionMover(mover,"raid") end
        ns.raidFrameMoverOwner = raidAnchor
        for index = 1, 40 do
            local ghost = CreatePreviewFrame("raid", index)
            ghost:SetParent(raidPreview)
            ghost.Label:SetText("Raid " .. index .. " (G" .. math.ceil(index / 5) .. ")")
            raidGhosts[index] = ghost
        end
    end
    raidAnchor:SetSize(size.width, size.height)
    PositionRaidAnchor()
    local positions = ns.CalculateRaidGeometry(layout, size.width, size.height)
    for index, ghost in ipairs(raidGhosts) do
        local position = positions[index]
        if position then
            ghost:SetSize(size.width, size.height); ghost:ClearAllPoints()
            ghost:SetPoint("TOPLEFT", raidAnchor, "TOPLEFT", position.x, position.y)
            ghost:Show()
        else
            ghost:Hide()
        end
    end
    raidPreview:Show()
end

local setMoversLocked = ns.SetFrameMoversLocked
ns.SetFrameMoversLocked = function(locked)
    setMoversLocked(locked)
    ns.UpdateRaidPreview(locked)
    if ns.RefreshPrecisionPosition then ns.RefreshPrecisionPosition() end
end
