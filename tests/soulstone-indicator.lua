-- Run from the repository root: lua5.1 tests/soulstone-indicator.lua
local function noop() end
function CreateFrame() return {RegisterEvent=noop,SetScript=noop} end
local ns={}
assert(loadfile("UnitFrames.lua"))("MythIncUnitFrames",ns)
local function findUpvalue(fn,wanted,seen)
    seen=seen or {}; if seen[fn] then return end; seen[fn]=true
    for i=1,100 do
        local name,value=debug.getupvalue(fn,i); if not name then break end
        if name==wanted then return value end
        if type(value)=="function" then
            local found=findUpvalue(value,wanted,seen); if found then return found end
        end
    end
end
local update=assert(findUpvalue(ns.SpawnAllFrames,"UpdateSoulstoneIndicator"))
local layout=assert(findUpvalue(ns.PreviewFrameType,"ApplyStatusIndicatorLayout"))
local setShown=assert(findUpvalue(ns.SpawnAllFrames,"SetIndicatorShown"))
local secret={}
local exists,connected,visible,dead=true,true,true,false
local restricted,accessible,throws=false,true,false
local aura,queriedUnit,queries=nil,nil,0
function canaccessvalue(value) return value~=secret end
function canaccesstable(value) return accessible end
function UnitExists() return exists end
function UnitIsConnected() return connected end
function UnitIsVisible() return visible end
function UnitIsDeadOrGhost() return dead end
C_Secrets={ShouldSpellAuraBeSecret=function(id) assert(id==20707); return restricted end}
C_UnitAuras={GetUnitAuraBySpellID=function(unit,id)
    assert(id==20707); queriedUnit=unit; queries=queries+1
    if throws then error("restricted access") end
    return aura
end}
local function icon()
    local t={shown=false}
    function t:IsShown() return self.shown end
    function t:Show() self.shown=true end
    function t:Hide() self.shown=false end
    function t:SetSize(w,h) self.width=w; self.height=h end
    function t:ClearAllPoints() self.point=nil end
    function t:SetPoint(...) self.point={...} end
    return t
end
-- Any aura-field inspection would fail: the lookup itself establishes the match.
local positive=setmetatable({},{__index=function() error("aura field inspected") end})
for _,kind in ipairs({"party","raid"}) do
    local frame={MIUF_UnitType=kind,MIUF_Unit=kind.."1",SoulstoneIndicator=icon()}
    aura=positive; update(frame)
    assert(frame.SoulstoneIndicator.shown and queriedUnit==kind.."1")
    aura=nil; update(frame); assert(not frame.SoulstoneIndicator.shown)
    for _,failure in ipairs({"secret aura","invalid result","inaccessible table","secret predicate","restricted","error","dead","secret death","missing","offline","invisible"}) do
        aura=positive; update(frame); assert(frame.SoulstoneIndicator.shown)
        if failure=="secret aura" then aura=secret
        elseif failure=="invalid result" then aura=false
        elseif failure=="inaccessible table" then accessible=false
        elseif failure=="secret predicate" then restricted=secret
        elseif failure=="restricted" then restricted=true
        elseif failure=="error" then throws=true
        elseif failure=="dead" then dead=true
        elseif failure=="secret death" then dead=secret
        elseif failure=="missing" then exists=false
        elseif failure=="offline" then connected=false
        elseif failure=="invisible" then visible=false end
        update(frame); assert(not frame.SoulstoneIndicator.shown,failure)
        restricted,accessible,throws=false,true,false
        exists,connected,visible,dead=true,true,true,false
    end
    aura=positive
    local saved=C_UnitAuras.GetUnitAuraBySpellID
    C_UnitAuras.GetUnitAuraBySpellID=nil; update(frame); assert(not frame.SoulstoneIndicator.shown)
    C_UnitAuras.GetUnitAuraBySpellID=saved
    saved=C_Secrets.ShouldSpellAuraBeSecret
    C_Secrets.ShouldSpellAuraBeSecret=nil; update(frame); assert(not frame.SoulstoneIndicator.shown)
    C_Secrets.ShouldSpellAuraBeSecret=saved
end
for _,kind in ipairs({"player","target","focus","targettarget","pet","boss"}) do
    local t=icon(); t.shown=true; local before=queries
    update({MIUF_UnitType=kind,MIUF_Unit=kind,SoulstoneIndicator=t})
    assert(not t.shown and queries==before)
end
local fields={"ReadyCheckIndicator","IncomingSummonIndicator","IncomingResurrectionIndicator","SoulstoneIndicator"}
local frame={Health={}}
for _,field in ipairs(fields) do frame[field]=icon(); frame[field]:Show() end
layout(frame,{statusIconSize=23,statusIconXOffset=-7,statusIconYOffset=5})
for i,field in ipairs(fields) do
    local t=frame[field]; assert(t.width==23 and t.height==23)
    if i==1 then
        assert(t.point[1]=="TOPRIGHT" and t.point[2]==frame.Health and t.point[3]=="TOPRIGHT" and t.point[4]==-7 and t.point[5]==5)
    else
        assert(t.point[1]=="RIGHT" and t.point[2]==frame[fields[i-1]] and t.point[3]=="LEFT" and t.point[4]==-2 and t.point[5]==0)
    end
end
-- Exercise every visible combination, including Soulstone alone and each pair.
-- Use the production visibility setter: no explicit relayout after transitions.
for mask=0,15 do
    for i,field in ipairs(fields) do
        setShown(frame,frame[field],math.floor(mask/2^(i-1))%2==1)
    end
    local previous
    for _,field in ipairs(fields) do
        local t=frame[field]
        assert(t.width==23 and t.height==23)
        if t:IsShown() then
            if previous then
                assert(t.point[1]=="RIGHT" and t.point[2]==previous and t.point[3]=="LEFT" and t.point[4]==-2 and t.point[5]==0)
            else
                assert(t.point[1]=="TOPRIGHT" and t.point[2]==frame.Health and t.point[3]=="TOPRIGHT" and t.point[4]==-7 and t.point[5]==5)
            end
            previous=t
        else assert(t.point==nil) end
    end
end
-- Removing/adding the first icon repacks already-visible later icons.
setShown(frame,frame.ReadyCheckIndicator,false)
assert(frame.IncomingSummonIndicator.point[2]==frame.Health)
setShown(frame,frame.ReadyCheckIndicator,true)
assert(frame.IncomingSummonIndicator.point[2]==frame.ReadyCheckIndicator)
local file=assert(io.open("UnitFrames.lua","r")); local source=file:read("*a"); file:close()
local handler=assert(source:match('frame:SetScript%("OnEvent",(function%(self,event%).-)\n    end%)')).."\nend"
local factory=assert(loadstring([[
    local ns,UpdateSoulstoneIndicator=...
    local VEHICLE_EVENTS,VEHICLE_DISPLAY_UNITS={},{}
    local function noop() end
    local UpdateHealth,ApplyColors,UpdateConnectionState=noop,noop,noop
    local function UpdateFrame(frame) UpdateSoulstoneIndicator(frame) end
    return ]]..handler))
ns.GetAppearance=function() return {} end
local onEvent=factory(ns,update)
for _,kind in ipairs({"party","raid"}) do
    local f={MIUF_UnitType=kind,MIUF_Unit=kind.."1",MIUF_DisplayUnit=kind.."1",SoulstoneIndicator=icon()}
    aura=positive; onEvent(f,"UNIT_AURA"); assert(f.SoulstoneIndicator.shown)
    aura=nil; onEvent(f,"UNIT_AURA"); assert(not f.SoulstoneIndicator.shown)
    aura=positive; onEvent(f,"UNIT_AURA"); dead=true
    onEvent(f,"UNIT_HEALTH"); assert(not f.SoulstoneIndicator.shown); dead=false
    for _,event in ipairs({"GROUP_ROSTER_UPDATE","PLAYER_ENTERING_WORLD","UNIT_CONNECTION"}) do
        aura=positive; onEvent(f,"UNIT_AURA"); assert(f.SoulstoneIndicator.shown)
        aura=nil; onEvent(f,event); assert(not f.SoulstoneIndicator.shown,event)
    end
end
-- Exercise real creation/registration without unrelated health/mover rendering.
local create=assert(findUpvalue(ns.SpawnAllFrames,"CreateUnitFrame"))
for i=1,100 do
    local name=debug.getupvalue(create,i); if not name then break end
    if name=="ApplyFrameState" or name=="BuildFrameState" or name=="UpdateFrame"
        or name=="CreateMover" or name=="ApplyPosition" then debug.setupvalue(create,i,noop) end
end
local methods={}
setmetatable(methods,{__index=function(_,name)
    if name:match("Indicator$") then return nil end
    return noop
end})
local function object() return setmetatable({events={},scripts={},textures={}},{__index=methods}) end
function methods:CreateTexture() local t=object(); self.textures[#self.textures+1]=t; return t end
function methods:CreateFontString() return object() end
function methods:CreateAnimationGroup() return object() end
function methods:CreateAnimation() return object() end
function methods:GetFrameLevel() return 1 end
function methods:SetTexture(texture) self.texture=texture end
function methods:RegisterUnitEvent(event,unit) self.events[event]=unit end
function methods:SetScript(event,fn) self.scripts[event]=fn end
function CreateFrame() return object() end
function UnitHasVehicleUI() return false end
function RegisterUnitWatch() end
UIParent=object()
C_Spell={GetSpellTexture=function(id) assert(id==20707); return 136210 end}
ns.GetSize=function() return {width=100,height=40} end
for _,kind in ipairs({"party","raid","player","target","focus","targettarget","pet","boss"}) do
    local unit=(kind=="party" or kind=="raid" or kind=="boss") and kind.."1" or kind
    local f=create(unit,nil,kind)
    if kind=="party" or kind=="raid" then
        assert(f.SoulstoneIndicator and f.SoulstoneIndicator.texture==136210)
        assert(f.events.UNIT_AURA==unit)
    else assert(rawget(f,"SoulstoneIndicator")==nil and f.events.UNIT_AURA==nil) end
end
local partyPlayer=create("player",nil,"party","party1",false,"partyplayer")
assert(partyPlayer.SoulstoneIndicator.texture==136210 and partyPlayer.events.UNIT_AURA=="player")
-- No new persisted configuration keys or schema are introduced.
for _,path in ipairs({"Core.lua","ConfigSession.lua"}) do
    local f=assert(io.open(path,"r")); local contents=f:read("*a"); f:close()
    assert(not contents:lower():find("soulstone",1,true))
end
print("PASS: Soulstone scope, safe positive lookup, restricted/unavailable results, all 16 collapsed layouts, visibility transitions, events, creation and unchanged configuration schema")
