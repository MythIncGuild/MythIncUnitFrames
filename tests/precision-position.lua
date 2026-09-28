-- Run from the repository root: lua5.1 tests/precision-position.lua
local methods={}
local objects={}
local function object(parent)
    local o=setmetatable({scripts={},shown=true,parent=parent,text=""},{__index=methods})
    objects[#objects+1]=o; return o
end
local function noop() end
for _,name in ipairs({"SetSize","SetFrameStrata","SetClampedToScreen","EnableMouse","SetBackdrop","SetBackdropColor",
    "SetBackdropBorderColor","SetFont","SetTextColor","SetAutoFocus","RegisterEvent","SetAllPoints"}) do methods[name]=noop end
function methods:SetScript(name,fn) self.scripts[name]=fn end
function methods:HookScript(name,fn)
    local old=self.scripts[name]
    self.scripts[name]=function(...) if old then old(...) end; fn(...) end
end
function methods:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
methods.IsShown=methods.IsVisible
function methods:Hide() local was=self.shown; self.shown=false; if was and self.scripts.OnHide then self.scripts.OnHide(self) end end
function methods:Show() self.shown=true end
function methods:CreateFontString() return object(self) end
function methods:SetText(text) self.text=text; if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self,false) end end
function methods:GetText() return self.text end
function methods:HasFocus() return self.focus end
function methods:ClearFocus() local had=self.focus; self.focus=false; if had and self.scripts.OnEditFocusLost then self.scripts.OnEditFocusLost(self) end end
function methods:SetPoint(...) self.point={...} end
function methods:GetPoint() return unpack(self.point or {}) end
function methods:ClearAllPoints() self.point=nil end
function methods:StopMovingOrSizing() end
function CreateFrame(_,name,parent) local o=object(parent); if name then _G[name]=o end; return o end
UIParent=object()
local combat,locked,context=false,false,true
function InCombatLockdown() return combat end
local saved={point="TOPLEFT",relativePoint="BOTTOMLEFT",x=10,y=20}
local ns={frames={},defaultSizes={player={}},defaultPositions={player=saved}}
MythIncUnitFramesDB={profiles={Default={}}}
function ns.GetActiveProfileName() return "Default" end
function ns.GetPosition() return saved end
function ns.AreFrameMoversLocked() return locked end
function ns.AreAuraMoversLocked() return true end
function ns.SetFrameMoversLockedState(v) locked=v end
function ns.SetAuraMoversLockedState() end
function ns.SetFrameMoversLocked() ns.RefreshPrecisionPosition() end
function ns.SetAuraMoversLocked() end
function ns.IsPrecisionPositionContext() return context end
function ns.GetSize() return {} end
function ns.GetAppearance() return {} end
function ns.GetPowerPercent() return 0 end
function ns.GetCastbarLayout() return {} end
local saves=0
function ns.SavePosition(_,p,r,x,y) saves=saves+1; saved={point=p,relativePoint=r,x=x,y=y} end
assert(loadfile("ConfigSession.lua"))("MIUF",ns)
assert(loadfile("PrecisionPosition.lua"))("MIUF",ns)
local function owner(kind)
    local f=object(); f.MIUF_UnitType=kind; f.MIUF_Mover=object(); f.MIUF_Mover.MIUF_ResizeHandle=object()
    ns.RegisterPrecisionMover(f.MIUF_Mover,kind); return f
end
ns.frames.player=owner("player"); ns.frames.boss1=owner("boss")
ns.partyFrameMoverOwner=owner("party"); ns.raidFrameMoverOwner=owner("raid")
function ns.ApplyGroupLayout(kind)
    local f=kind=="party" and ns.partyFrameMoverOwner or kind=="boss" and ns.frames.boss1 or ns.raidFrameMoverOwner
    local p=ns.ConfigSessionGetPosition(kind=="party" and "party1" or kind=="boss" and "boss1" or "raid")
    f:SetPoint(p.point,UIParent,p.relativePoint,p.x,p.y)
end
local stages=0
local stage=ns.ConfigSessionStagePosition
function ns.ConfigSessionStagePosition(...) stages=stages+1; stage(...) end
ns.frames.player.MIUF_Mover.scripts.OnMouseDown(nil,"LeftButton")
local panel=assert(MIUF_PrecisionPosition)
local fields={}
for _,o in ipairs(objects) do if o.MIUF_Axis then fields[o.MIUF_Axis]=o end end
assert(panel:IsVisible() and stages==0 and not ns.frames.player.point)
assert(fields.x:GetText()=="10" and fields.y:GetText()=="20")
local function edit(axis,text)
    local box=fields[axis]; box.focus=true; box:SetText(text); box.scripts.OnTextChanged(box,true); box.scripts.OnEnterPressed(box)
end
edit("x","42.4")
local p=ns.ConfigSessionGetPosition("player")
assert(p.x==42 and p.y==20 and p.point==saved.point and p.relativePoint==saved.relativePoint)
assert(saved.x==10 and saves==0 and ns.frames.player.point[4]==42)
local before=stages
for _,value in ipairs({"-","","hello","1e999"}) do edit("x",value) end
assert(stages==before)
ns.RefreshPrecisionPosition(); assert(stages==before)
local mover=ns.frames.player.MIUF_Mover
local target=object(); target:SetPoint("RIGHT",UIParent,"RIGHT",77,-33)
ns.BeginPrecisionPositionDrag("player",mover,target)
assert(panel.scripts.OnUpdate); panel.scripts.OnUpdate()
assert(fields.x:GetText()=="77" and fields.y:GetText()=="-33" and stages==before)
ns.ConfigSessionStagePosition("player",{point="RIGHT",relativePoint="RIGHT",x=78,y=-34})
ns.EndPrecisionPositionDrag(mover)
assert(not panel.scripts.OnUpdate and fields.x:GetText()=="78")
assert(ns.ConfigSessionCommit() and saves==1 and saved.x==78)
-- Real session discard paths, with protected restoration mocked.
function ns.ApplySavedConfiguration()
    assert(not combat); return true
end
edit("y","99"); assert(ns.ConfigSessionRevert()); ns.RefreshPrecisionPosition()
assert(ns.ConfigSessionGetPosition("player").y==-34 and fields.y:GetText()=="-34")
for _,kind in ipairs({"party","boss","raid"}) do
    ns.SelectPrecisionPosition(kind); edit("x","123")
    local key=kind=="party" and "party1" or kind=="boss" and "boss1" or "raid"
    assert(ns.ConfigSessionGetPosition(key).x==123)
end
ns.SelectPrecisionPosition("party")
local old=ns.partyFrameMoverOwner
ns.partyFrameMoverOwner=owner("party"); ns.RefreshPrecisionPosition(); edit("y","56")
assert(ns.partyFrameMoverOwner.point[5]==56 and old.point[5]~=56)
-- Main Config and subwindow contexts suppress; collapse preserves pending data.
context=false; ns.RefreshPrecisionPosition(); assert(not panel:IsVisible())
context=true; ns.RefreshPrecisionPosition(); assert(panel:IsVisible() and ns.ConfigSessionGetPosition("party1").y==56)
locked=true; ns.RefreshPrecisionPosition(); assert(not panel:IsVisible() and saves==1)
locked=false; ns.RefreshPrecisionPosition()
local pm=ns.partyFrameMoverOwner.MIUF_Mover
ns.BeginPrecisionPositionDrag("party",pm,target); assert(panel.scripts.OnUpdate)
context=false; ns.RefreshPrecisionPosition(); assert(not panel.scripts.OnUpdate)
context=true; ns.RefreshPrecisionPosition(); assert(panel.scripts.OnUpdate)
combat=true; ns.RefreshPrecisionPosition(); assert(not panel:IsVisible() and not panel.scripts.OnUpdate)
before=stages; edit("x","777"); assert(stages==before)
combat=false; ns.RefreshPrecisionPosition(); assert(not panel.scripts.OnUpdate)
ns.BeginPrecisionPositionDrag("party",pm,target); pm:Hide(); assert(not panel.scripts.OnUpdate and not panel:IsVisible())
pm:Show(); ns.RefreshPrecisionPosition()
assert(ns.ConfigSessionClose()); ns.RefreshPrecisionPosition()
assert(locked and not panel:IsVisible() and ns.ConfigSessionGetPosition("party1").y==saved.y)
assert(saves==1)
print("PASS: precision selection, edits, logical owners, session lifecycle, visibility, drag observation")
