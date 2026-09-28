-- Run from the repository root: lua5.1 tests/position-persistence.lua
local methods={}
local function object() return setmetatable({scripts={},shown=true},{__index=methods}) end
local function noop() end
for _,name in ipairs({"SetMovable","SetClampedToScreen","SetFrameStrata","SetAllPoints",
    "SetBackdrop","SetBackdropColor","SetBackdropBorderColor","EnableMouse","RegisterForDrag",
    "SetFont","SetText","SetPoint","SetSize","SetFrameLevel","ClearAllPoints",
    "RegisterEvent","UnregisterEvent"}) do methods[name]=noop end
function methods:SetDontSavePosition(value) self.dontSavePosition=value end
function methods:GetFrameLevel() return 1 end
function methods:CreateFontString() return object() end
function methods:SetScript(name,callback) self.scripts[name]=callback end
function methods:IsShown() return self.shown end
function methods:StopMovingOrSizing() self.started=false end
function methods:GetPoint() return "RIGHT",UIParent,"RIGHT",81,-42 end
function methods:Hide() self.shown=false end
function methods:StartMoving()
    assert(self.dontSavePosition==true,"drag target still uses client position persistence")
    self.started=true
end
function CreateFrame() return object() end
function InCombatLockdown() return false end
UIParent=object()
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
local createMover=assert(findUpvalue(ns.SpawnAllFrames,"CreateMover"))
local observedTarget,ended,stagedKey,stagedPosition,registered
function ns.RegisterPrecisionMover(mover,kind) registered={mover,kind} end
function ns.BeginPrecisionPositionDrag(_,_,target) observedTarget=target end
function ns.EndPrecisionPositionDrag(mover) ended=mover end
function ns.ConfigSessionStagePosition(key,p) stagedKey,stagedPosition=key,p end
for _,kind in ipairs({"player","target","focus","pet","targettarget","party","boss"}) do
    local frame=object(); frame.MIUF_UnitType=kind
    createMover(frame,kind,kind)
    assert(frame.dontSavePosition==true)
    local mover=frame.MIUF_Mover
    assert(registered[1]==mover and registered[2]==kind)
    assert(not mover.MIUF_ResizeHandle.dontSavePosition,"resize handle does not own a position")
    mover.scripts.OnDragStart()
    assert(frame.started and not mover.started)
    assert(observedTarget==frame)
    mover.scripts.OnDragStop()
    assert(ended==mover and stagedKey==kind and stagedPosition.x==81 and stagedPosition.y==-42)
    if kind=="party" or kind=="boss" then
        frame.started=false; frame.shown=false
        mover.scripts.OnDragStart()
        assert(mover.started and not frame.started,"hidden group must move its independent mover")
        assert(observedTarget==mover)
        mover.scripts.OnDragStop()
        assert(ended==mover and stagedKey==kind)
    else
        assert(not mover.dontSavePosition,"solo overlay is not the drag target")
    end
end

function ns.GetSize() return {width=120,height=30} end
function ns.ConfigSessionGetPosition() return {point="CENTER",relativePoint="CENTER",x=15,y=25} end
assert(loadfile("Groups.lua"))("MythIncUnitFrames",ns)
local anchor=ns.GetRaidAnchor()
assert(anchor.dontSavePosition==true and ns.raidFrameMoverOwner==anchor)
anchor:StartMoving()
assert(ns.GetRaidAnchor()==anchor)
print("position persistence tests passed")
