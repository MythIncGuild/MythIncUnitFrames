-- Run from the repository root with Lua 5.1.
local created, bindings = 0, 0
local methods = {}
local function object(parent)
    created = created + 1
    return setmetatable({parent=parent, shown=true, scripts={}, points={}, events={}}, {__index=methods})
end
local function noop() end
for _, key in ipairs({"SetBackdrop", "SetBackdropColor", "SetBackdropBorderColor", "SetFrameLevel",
    "SetAllPoints", "SetColorTexture", "SetFont", "SetJustifyH", "SetWordWrap", "SetBlendMode",
    "SetVertexColor", "SetMinMaxValues", "SetValue"}) do
    methods[key] = noop
end
function methods:GetFrameLevel() return 1 end
function methods:SetHeight(h) self.height=h end
function methods:SetWidth(w) self.width=w end
function methods:GetWidth() return self.width or 200 end
function methods:SetColorTexture(...) self.rgba={...} end
function methods:GetParent() return self.parent end
function methods:SetParent(parent) self.parent=parent end
function methods:SetValue(value) self.value=value end
function methods:ClearAllPoints() self.points={} end
function methods:SetSize(w,h) self.width=w; self.height=h end
function methods:SetPoint(...) self.points[#self.points+1]={...} end
function methods:CreateTexture() return object(self) end
function methods:CreateFontString() return object(self) end
function methods:SetTexture(t) self.texture=t end
function methods:SetAtlas(a, useSize) self.atlas=a; self.useAtlasSize=useSize end
function methods:SetText(t) self.text=t end
function methods:SetAlpha(a) self.alpha=a end
function methods:SetAlphaFromBoolean(value, yes, no)
    self.alphaInput=value; self.alphaYes=yes; self.alphaNo=no
end
function methods:SetStatusBarTexture(t) self.fill=object(self); self.fill.texture=t end
function methods:GetStatusBarTexture() return self.fill end
function methods:SetStatusBarColor(...) self.color={...} end
function methods:SetTimerDuration(d, interpolation, direction)
    self.duration=d; self.interpolation=interpolation; self.direction=direction
end
function methods:SetScript(event, fn) self.scripts[event]=fn end
function methods:RegisterEvent(event) self.events[event]=true end
function methods:UnregisterEvent(event) self.events[event]=nil end
function methods:Hide()
    if self.shown then self.shown=false; if self.scripts.OnHide then self.scripts.OnHide(self) end end
end
function methods:Show()
    if not self.shown then self.shown=true; if self.scripts.OnShow then self.scripts.OnShow(self) end end
end
function methods:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function CreateFrame(_, _, parent) return object(parent) end
UIParent=object()
local combat=false
function InCombatLockdown() return combat end
Enum={SecondsFormatterAbbreviation={OneLetter=1}, SecondsFormatterInterval={Seconds=1},
    StatusBarInterpolation={Immediate=1}, StatusBarTimerDirection={ElapsedTime=1, RemainingTime=2}}
C_StringUtil={CreateSecondsFormatter=function()
    return {SetDefaultAbbreviation=noop, SetMinInterval=noop, SetMillisecondsThreshold=noop}
end}
C_DurationUtil={CreateDurationTextBinding=function()
    bindings=bindings+1
    return {
        SetEnabled=function(self, v) self.enabled=v end,
        SetToDefaults=function(self) self.duration=nil; self.fontString=nil; self.formatter=nil end,
        SetFontString=function(self, v) self.fontString=v end,
        SetFormatter=function(self, v) self.formatter=v end,
        SetDuration=function(self, v) assert(v, "SetDuration is not nullable"); self.duration=v end,
        UpdateFontString=function(self)
            assert(self.duration and self.formatter and self.fontString, "binding configured")
            self.fontString:SetText("native remaining time")
        end,
    }
end}
local secret=setmetatable({}, {__tostring=function() error("secret formatted") end,
    __add=function() error("secret arithmetic") end, __sub=function() error("secret arithmetic") end})
function canaccessvalue(v) return v~=secret end
local current, missing = {}, {}
local timers={}
C_Timer={After=function(_,callback) timers[#timers+1]=callback end}
function UnitExists(unit) return not missing[unit] end
function UnitCastingInfo(unit)
    local c=current[unit]
    if c and c.mode=="cast" then return c.name,c.display,c.texture,secret,secret,false,secret,c.lock,nil,c.id end
end
function UnitChannelInfo(unit)
    local c=current[unit]
    if c and c.mode~="cast" then return c.name,c.display,c.texture,secret,secret,false,c.lock,secret,c.mode=="empower" end
end
function UnitCastingDuration(unit) return current[unit].duration end
UnitChannelDuration=UnitCastingDuration
function UnitEmpoweredChannelDuration(unit, hold) assert(hold==true); return current[unit].duration end
local ns={frames={}}
assert(loadfile("Media.lua"))("MythIncUnitFrames", ns)
function ns.GetCastbarLayout()
    return {enabled=true,width=0,height=18,xOffset=0,yOffset=-3}
end
function ns.GetFrameDisplayUnit(frame) return frame and (frame.displayUnit or frame.MIUF_Unit) end
function ns.RegisterFrameUnitEvent(events, event) events:RegisterEvent(event) end
for _, unit in ipairs({"player","target","focus","boss1","boss2","boss3","boss4","boss5","pet"}) do
    local frame=object(); frame.MIUF_Unit=unit; frame.MIUF_UnitType=unit:match("boss") and "boss" or unit
    ns.frames[unit]=frame
end
assert(loadfile("Castbars.lua"))("MythIncUnitFrames", ns)
ns.SpawnAllFrames()
assert(not ns.frames.pet.Castbar and bindings==8)
local count=created
local function clear(frame)
    local bar=frame.Castbar
    assert(not frame.CastbarHolder.shown and not bar.Time.binding.enabled)
    assert(bar.Time.binding.duration==nil and bar.Time.text=="" and bar.Text.text=="")
    assert(bar.Icon.texture==nil and bar.Shield.alpha==0 and not bar.Spark.shown)
    if bar.SafeZone then assert(not bar.SafeZone.shown and bar.SafeZone.width==0) end
end
for unit, frame in pairs(ns.frames) do
    if frame.Castbar then
        clear(frame)
        local bar=frame.Castbar
        assert((bar.SafeZone~=nil)==(unit=="player"))
        assert(bar.fill.texture==ns.GetTexturePath("smooth"))
        assert(frame.CastbarHolder.height==18 and bar.Icon.width==16 and bar.Icon.height==16)
        assert(bar.Shield.atlas=="ui-castingbar-shield" and bar.Shield.useAtlasSize==false)
        assert(bar.LockText==nil and bar.Spark.points[1][2]==bar:GetStatusBarTexture())
        for _, mode in ipairs({"cast","channel","empower"}) do
            current[unit]={mode=mode,name="Spell",display="Display",texture=secret,lock=secret,duration=secret}
            ns.UpdateFrameCastbar(frame)
            assert(bar.Icon.texture==secret and bar.Text.text=="Display")
            assert(bar.Time.binding.duration==secret and bar.Time.binding.enabled)
            assert(bar.Time.text=="native remaining time" and bar.Spark.shown)
            assert(bar.Shield.alphaInput==secret and bar.Shield.alphaYes==1 and bar.Shield.alphaNo==0)
            assert(bar.color[1]==1.00 and bar.duration==secret)
            assert(bar.direction==(mode=="channel" and 2 or 1))
            current[unit].lock=true
            frame.MIUF_CastbarEvents.scripts.OnEvent(nil,"UNIT_SPELLCAST_NOT_INTERRUPTIBLE",unit)
            assert(bar.Shield.alphaInput==true and bar.color[1]==0.45)
            current[unit].lock=false; current[unit].display=nil
            frame.MIUF_CastbarEvents.scripts.OnEvent(nil,"UNIT_SPELLCAST_INTERRUPTIBLE",unit)
            assert(bar.Shield.alphaInput==false and bar.color[1]==1.00 and bar.Text.text=="Spell")
            frame.CastbarHolder:Hide(); assert(not bar.Time.binding.enabled)
            frame.CastbarHolder:Show(); assert(bar.Time.binding.enabled)
            current[unit]=nil
            local stop=mode=="cast" and "UNIT_SPELLCAST_STOP"
                or (mode=="channel" and "UNIT_SPELLCAST_CHANNEL_STOP" or "UNIT_SPELLCAST_EMPOWER_STOP")
            frame.MIUF_CastbarEvents.scripts.OnEvent(nil,stop,unit)
            clear(frame)
        end
        current[unit]={mode="cast",name="Spell",texture=123,lock=false,duration=secret}
        ns.UpdateFrameCastbar(frame)
        assert(frame.Castbar.Icon.texture==123)
        frame:Hide(); ns.UpdateFrameCastbar(frame)
        assert(not frame.Castbar.Time.binding.enabled, "hidden owner does not tick timer")
        frame:Show(); ns.UpdateFrameCastbar(frame)
        assert(frame.Castbar.Time.binding.enabled)
        missing[unit]=true; ns.UpdateFrameCastbar(frame); clear(frame); missing[unit]=nil
        current[unit].duration=nil; ns.UpdateFrameCastbar(frame); clear(frame)
        current[unit]=nil
    end
end
local player=ns.frames.player
player.displayUnit="vehicle"
current.vehicle={mode="cast",name="Vehicle",texture=456,lock=false,duration=secret}
ns.UpdateFrameCastbar(player)
assert(player.Castbar.Icon.texture==456 and player.Castbar.Text.text=="Vehicle")
player.displayUnit=nil; ns.UpdateFrameCastbar(player); clear(player)
ns.RefreshCastbars()
assert(created==count and bindings==8, "no allocations while refreshing")

-- Player latency uses world milliseconds / total seconds, never remaining time.
local bar=player.Castbar
local zone=bar.SafeZone
local total, latency=2,150
local duration={GetTotalDuration=function() return total end}
function GetNetStats() return 0,0,999,latency end
local function start()
    current.player={mode="cast",name="Latency",texture=123,lock=false,duration=duration,id=42}
    player.MIUF_CastbarEvents.scripts.OnEvent(nil,"UNIT_SPELLCAST_START","player")
end
local function hidden() assert(not zone.shown and zone.width==0) end
start()
assert(zone.shown and zone.width==15)
assert(zone.points[1][1]=="TOPRIGHT" and zone.points[2][1]=="BOTTOMRIGHT")
assert(zone.rgba[1]==0.85 and zone.rgba[2]==0.70 and zone.rgba[3]==1.00 and zone.rgba[4]==0.45)
assert(bar.color[1]==1 and bar.color[2]==0.82 and bar.color[3]==0.25)
bar:SetWidth(400); bar.scripts.OnSizeChanged(bar)
assert(zone.width==30)
total=4
player.MIUF_CastbarEvents.scripts.OnEvent(nil,"UNIT_SPELLCAST_DELAYED","player")
assert(zone.width==15)
latency=8000; ns.UpdateFrameCastbar(player); assert(zone.width==400)
for _, invalid in ipairs({0,-1,math.huge,-math.huge,0/0,"bad",false,secret}) do
    total=invalid; latency=150; ns.UpdateFrameCastbar(player); hidden()
    total=2; latency=invalid; ns.UpdateFrameCastbar(player); hidden()
end
total=nil; latency=150; ns.UpdateFrameCastbar(player); hidden()
total=2; latency=nil; ns.UpdateFrameCastbar(player); hidden()
latency=150
local netStats=GetNetStats
GetNetStats=nil; ns.UpdateFrameCastbar(player); hidden(); GetNetStats=netStats
current.player.duration={}; ns.UpdateFrameCastbar(player); hidden()
current.player.duration=nil; ns.UpdateFrameCastbar(player); hidden()
start(); assert(zone.shown)
player.CastbarHolder:Hide(); hidden()
player.CastbarHolder:Show(); assert(zone.shown and zone.width==30)
for _, mode in ipairs({"channel","empower"}) do
    current.player.mode=mode; ns.UpdateFrameCastbar(player); hidden()
    start(); assert(zone.shown)
end
player.displayUnit="vehicle"; current.vehicle=current.player
ns.UpdateFrameCastbar(player); hidden()
player.displayUnit=nil; current.vehicle=nil
for _, event in ipairs({"UNIT_SPELLCAST_STOP","UNIT_SPELLCAST_FAILED","UNIT_SPELLCAST_INTERRUPTED"}) do
    start(); assert(zone.shown)
    current.player=nil
    if event=="UNIT_SPELLCAST_INTERRUPTED" then
        player.MIUF_CastbarEvents.scripts.OnEvent(nil,event,"player",nil,nil,nil,42)
    else
        player.MIUF_CastbarEvents.scripts.OnEvent(nil,event,"player",nil,nil,42)
    end
    hidden()
    if event~="UNIT_SPELLCAST_STOP" then
        assert(bar.Text.text==(event=="UNIT_SPELLCAST_FAILED" and "Failed" or "Interrupted"))
        timers[#timers](); hidden()
    end
end
start(); missing.player=true; ns.UpdateFrameCastbar(player); hidden(); missing.player=nil
start(); ns.ApplyFrameCastbarSettings(player,{enabled=false,width=0,height=18,xOffset=0,yOffset=-3}); hidden()
current.player=nil
ns.ApplyFrameCastbarSettings(player,ns.GetCastbarLayout())
ns.SetCastbarPreview("player"); hidden(); ns.ClearCastbarPreview()
bar:SetWidth(200)
assert(created==count and bindings==8, "SafeZone must reuse its texture")
print("PASS: Player SafeZone ownership, latency, resize, clamp, invalid/secret inputs and lifecycle")

-- Static configuration presentation never invents a real cast or allocates a
-- parallel bar. Hidden/missing owners retain their existing geometry anchors.
local generation=player.Castbar.MIUF_CastState.generation
player:Hide(); missing.player=true
ns.SetCastbarPreview("player")
assert(player.CastbarHolder:IsVisible() and player.CastbarHolder:GetParent()==UIParent)
assert(player.Castbar.value==0.7 and player.Castbar.Text.text=="Cast Bar Preview")
assert(player.Castbar.Time.text=="1.5s" and not player.Castbar.Time.binding.enabled)
assert(player.Castbar.Icon.texture=="Interface\\Icons\\INV_Misc_QuestionMark")
assert(not player.Castbar.MIUF_CastState.active and not player.Castbar.MIUF_CastState.terminal)
assert(player.Castbar.MIUF_CastState.generation==generation)
assert(not ns.frames.target.MIUF_CastbarPreview)
ns.ApplyFrameCastbarSettings(player,{enabled=true,width=240,height=26,xOffset=12,yOffset=-20})
assert(player.CastbarHolder.width==240 and player.CastbarHolder.height==26)
local point=player.CastbarHolder.points[1]
assert(point[2]==player and point[4]==12 and point[5]==-20)

-- Real casts and terminal holds win; preview returns only after real cleanup.
player:Show(); missing.player=nil
current.player={mode="cast",name="Real",texture=123,lock=false,duration=secret,id=7}
player.MIUF_CastbarEvents.scripts.OnEvent(nil,"UNIT_SPELLCAST_START","player")
assert(not player.MIUF_CastbarPreview and player.CastbarHolder:GetParent()==player)
assert(player.Castbar.Text.text=="Real" and player.Castbar.Time.binding.enabled)
ns.ClearCastbarPreview()
assert(player.Castbar.Text.text=="Real" and player.CastbarHolder.shown)
ns.SetCastbarPreview("player")
assert(player.Castbar.Text.text=="Real")
current.player=nil
player.MIUF_CastbarEvents.scripts.OnEvent(nil,"UNIT_SPELLCAST_INTERRUPTED","player",nil,nil,nil,7)
assert(player.Castbar.Text.text=="Interrupted" and player.Castbar.MIUF_CastState.terminal)
ns.SetCastbarPreview("player")
assert(player.Castbar.Text.text=="Interrupted")
timers[#timers]()
assert(player.MIUF_CastbarPreview and player.Castbar.Text.text=="Cast Bar Preview")
ns.ClearCastbarPreview()
clear(player)
assert(player.CastbarHolder:GetParent()==player)

ns.SetCastbarPreview("target")
assert(ns.frames.target.MIUF_CastbarPreview)
ns.ApplyFrameCastbarSettings(ns.frames.target,{enabled=true,width=280,height=30,xOffset=-14,yOffset=8})
assert(ns.frames.target.CastbarHolder.width==280 and ns.frames.target.CastbarHolder.height==30)
assert(ns.frames.target.CastbarHolder.points[1][4]==-14 and ns.frames.target.CastbarHolder.points[1][5]==8)
ns.SetCastbarPreview("focus")
clear(ns.frames.target)
assert(not ns.frames.focus.MIUF_CastbarPreview)
ns.SetCastbarPreview("boss")
clear(ns.frames.focus)
for i=1,5 do assert(not ns.frames["boss"..i].MIUF_CastbarPreview) end
-- Old saved/customized geometry must not affect Focus or any Boss bar.
for _,unitType in ipairs({"focus","boss"}) do
    ns.ApplyCastbarLayout(unitType,{enabled=true,width=500,height=40,xOffset=100,yOffset=90})
    for _,frame in pairs(ns.frames) do
        if frame.MIUF_UnitType==unitType then
            local holder=frame.CastbarHolder
            assert(holder.height==18 and #holder.points==2)
            assert(holder.points[1][1]=="TOPLEFT" and holder.points[2][1]=="TOPRIGHT")
            for _,point in ipairs(holder.points) do
                assert(point[2]==frame and point[4]==0 and point[5]==-3)
            end
            assert(frame.Castbar.Icon.width==16 and frame.Castbar.Icon.height==16)
        end
    end
end
ns.ApplyCastbarLayout("boss",{enabled=false,width=0,height=18,xOffset=0,yOffset=-3})
for i=1,5 do clear(ns.frames["boss"..i]) end
ns.ClearCastbarPreview()
ns.ApplyCastbarLayout("boss",ns.GetCastbarLayout("boss"))
combat=true
ns.SetCastbarPreview("player")
assert(not player.MIUF_CastbarPreview)
combat=false
assert(created==count and bindings==8, "preview must reuse existing bars")
print("PASS: static castbar preview, geometry, real-cast/terminal priority, context and disable cleanup")

-- The same configuration application path serves staged previews, Apply and
-- Revert. Disabling must also block subsequent events and invalidate old cleanup.
for _, unitType in ipairs({"player","target","focus","boss"}) do
    for unit, frame in pairs(ns.frames) do
        if frame.MIUF_UnitType==unitType then
            current[unit]={mode="cast",name="Active",texture=123,lock=false,duration=secret}
            ns.UpdateFrameCastbar(frame)
        end
    end
    local layout={enabled=false,width=0,height=18,xOffset=0,yOffset=-3}
    ns.ApplyCastbarLayout(unitType,layout)
    for unit, frame in pairs(ns.frames) do
        if frame.MIUF_UnitType==unitType then
            clear(frame)
            frame.MIUF_CastbarEvents.scripts.OnEvent(nil,"UNIT_SPELLCAST_START",unit)
            ns.UpdateFrameCastbar(frame)
            clear(frame)
        end
    end
    layout.enabled=true
    ns.ApplyCastbarLayout(unitType,layout)
    for unit, frame in pairs(ns.frames) do
        if frame.MIUF_UnitType==unitType then
            assert(frame.CastbarHolder.shown and frame.Castbar.Text.text=="Active")
            local state=frame.Castbar.MIUF_CastState
            state.terminal=true
            local generation=state.generation
            ns.ApplyFrameCastbarSettings(frame,{enabled=false,width=0,height=18,xOffset=0,yOffset=-3})
            clear(frame)
            assert(not state.terminal and state.generation>generation)
            ns.ApplyFrameCastbarSettings(frame,layout)
            assert(frame.CastbarHolder.shown and frame.Castbar.Time.binding.enabled)
        end
    end
end
assert(created==count and bindings==8, "toggling must reuse existing bars")

-- Check the actual Blizzard ownership module, with only Player castbar present.
local hooks={}
function hooksecurefunc(target,key,fn)
    local original=target[key]
    target[key]=function(...)
        if original then original(...) end
        fn(...)
    end
end
function IsLoggedIn() return true end
local playerEnabled, castbarEnabled=true,true
function ns.IsFrameTypeEnabled(unitType) return unitType=="player" and playerEnabled end
function ns.GetCastbarLayout() return {enabled=castbarEnabled} end
function ns.SaveCastbarLayout(_,layout) castbarEnabled=layout.enabled end
PlayerCastingBarFrame=object(object())
local originalParent=PlayerCastingBarFrame:GetParent()
local originalCreateFrame=CreateFrame
function CreateFrame(...)
    local frame=originalCreateFrame(...)
    hooks[#hooks+1]=frame
    return frame
end
assert(loadfile("BlizzardFrames.lua"))("MythIncUnitFrames",ns)
assert(PlayerCastingBarFrame:GetParent()~=originalParent)
ns.SaveCastbarLayout("player",{enabled=false})
assert(PlayerCastingBarFrame:GetParent()==originalParent)
combat=true
ns.SaveCastbarLayout("player",{enabled=true})
assert(PlayerCastingBarFrame:GetParent()==originalParent, "ownership must defer in combat")
combat=false
for _, frame in ipairs(hooks) do
    if frame.events.PLAYER_REGEN_ENABLED then frame.scripts.OnEvent(frame,"PLAYER_REGEN_ENABLED") end
end
assert(PlayerCastingBarFrame:GetParent()~=originalParent)
playerEnabled=false
ns.SetFrameTypeEnabled("player",false)
assert(PlayerCastingBarFrame:GetParent()==originalParent)
print("PASS: castbar enable/disable, Boss family, resume/cleanup, Player ownership and combat deferral")
print("PASS: castbar presentation, eight frames, cast/channel/empower, restricted sinks, cleanup, vehicle routing")
