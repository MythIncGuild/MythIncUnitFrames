-- Run from the repository root: lua5.1 tests/config-session-lifecycle.lua
local combat=false
function InCombatLockdown() return combat end
local saved={size={width=200,height=40},appearance={fontSize=12},power=20,
    castbar={height=18},aura={xOffset=0},group={spacing=4},position={x=0},tracked={}}
local ns={defaultSizes={player=saved.size},defaultPositions={player=saved.position}}
MythIncUnitFramesDB={profiles={Default={}}}
function ns.GetActiveProfileName() return "Default" end
function ns.GetSize() return saved.size end
function ns.GetAppearance() return saved.appearance end
function ns.GetPowerPercent() return saved.power end
function ns.GetCastbarLayout() return saved.castbar end
function ns.GetGroupLayout() return saved.group end
function ns.GetAuraLayout() return saved.aura end
function ns.GetPosition() return saved.position end
function ns.GetTrackedBuffs() return saved.tracked end
function ns.IsFrameTypeEnabled() return true end
function ns.SaveSize(_,w,h) saved.size={width=w,height=h} end
function ns.SaveAppearance(_,v) saved.appearance=v end
function ns.SavePowerPercent(_,v) saved.power=v end
function ns.SaveCastbarLayout(_,v) saved.castbar=v end
function ns.SetFrameMoversLockedState(v) ns.frameLocked=v end
function ns.SetAuraMoversLockedState(v) ns.auraLocked=v end
function ns.AreFrameMoversLocked() return ns.frameLocked end
function ns.AreAuraMoversLocked() return ns.auraLocked end
function ns.SetFrameMoversLocked() end
function ns.SetAuraMoversLocked() end
assert(loadfile("ConfigSession.lua"))("MythIncUnitFrames",ns)
local restores=0
function ns.ApplySavedConfiguration()
    assert(not combat)
    restores=restores+1
    assert(ns.ConfigSessionGetFrame("player").size.width==saved.size.width)
    return true
end
local function edit(width)
    local frame=ns.ConfigSessionGetFrame("player")
    frame.size.width=width; frame.appearance.fontSize=22
    ns.ConfigSessionStageFrame("player",frame)
end
assert(ns.ConfigSessionBegin())
edit(300)
ns.ConfigSessionStageAura("player","buffs",{xOffset=15})
ns.ConfigSessionStageGroup("player",{spacing=10})
ns.ConfigSessionStagePosition("player",{x=30})
ns.ConfigSessionStageTrackedBuffs({[123]={name="Test"}})
ns.ConfigSessionStageEnabled("player",false)
assert(ns.ConfigSessionIsDirty())
assert(ns.ConfigSessionClose())
assert(not ns.ConfigSessionIsActive() and not ns.ConfigSessionIsDirty())
assert(restores==1 and ns.frameLocked and ns.auraLocked)
assert(ns.ConfigSessionBegin())
assert(ns.ConfigSessionGetFrame("player").size.width==200)
assert(ns.ConfigSessionGetFrame("player").appearance.fontSize==12)
assert(ns.ConfigSessionGetAura("player","buffs").xOffset==0)
assert(ns.ConfigSessionGetGroup("player").spacing==4)
assert(ns.ConfigSessionGetPosition("player").x==0)
assert(next(ns.ConfigSessionGetTrackedBuffs())==nil)
assert(ns.ConfigSessionGetEnabled("player"))
edit(310)
assert(ns.ConfigSessionCommit())
assert(ns.ConfigSessionIsActive() and saved.size.width==310)
edit(400)
assert(ns.ConfigSessionRevert())
assert(ns.ConfigSessionIsActive() and ns.ConfigSessionGetFrame("player").size.width==310)
assert(ns.ConfigSessionClose())
assert(saved.size.width==310)
assert(ns.ConfigSessionBegin())
edit(500)
combat=true
local before=restores
assert(not ns.ConfigSessionClose())
assert(not ns.ConfigSessionIsDirty() and not ns.ConfigSessionIsActive())
assert(not ns.ConfigSessionBegin() and restores==before)
combat=false
assert(ns.ConfigSessionFinishClose())
assert(restores==before+1)
assert(not ns.ConfigSessionFinishClose())
assert(ns.ConfigSessionBegin())
assert(ns.ConfigSessionGetFrame("player").size.width==310)
print("PASS: session Close, all pending stores, Apply, Revert, combat deferral")

-- Exercise the real GUI transition functions without building the WoW widget
-- tree. The existing window and compact bar stand in for already-built widgets.
local file=assert(io.open("Config.lua","r"))
local source=file:read("*a"); file:close()
local transitions=assert(source:match("(function ns.RestoreConfig%(%)%s.-)\nfunction ns.ToggleConfig"))
local precisionContext=assert(source:match("(function ns.IsPrecisionPositionContext%(%)%s.-)\nend")).."\nend\n"
local factory=assert(loadstring([[
    local ns,config,collapsedBar,trackedBuffWindow=...
    local collapsed,internalHide=false,false
    config.onHide=function() assert(internalHide,"Collapse entered Close") end
]]..precisionContext..transitions..[[
    return function() return collapsed end
]]))
local window={shown=true,unit="player",tab="frames",category="Auras",scroll=73}
function window:Hide() self.shown=false; self.onHide() end
function window:Show() self.shown=true end
function window:IsShown() return self.shown end
local tracked={shown=false}
function tracked:IsShown() return self.shown end
function tracked:Hide() self.shown=false end
local bar={}
function bar:Show() self.shown=true end
function bar:Hide() self.shown=false end
local isCollapsed=factory(ns,window,bar,tracked)
assert(not ns.IsPrecisionPositionContext())
-- Internal transition to the tracked-buff window is not positioning context,
-- including the interval after main Hide but before subwindow Show.
window.shown=false
assert(not ns.IsPrecisionPositionContext())
tracked.shown=true
assert(not ns.IsPrecisionPositionContext())
tracked.shown=false; window.shown=true
local castbarActive,auraActive=true,true
function ns.ClearCastbarPreview() castbarActive=false end
function ns.ClearAuraMoverPreview() auraActive=false end
edit(620)
ns.ConfigSessionStageAura("party","buffs",{xOffset=71,yOffset=-29})
ns.ConfigSessionStageAura("raid","debuffs",{xOffset=-43,yOffset=82})
ns.CollapseConfig()
assert(isCollapsed() and not window.shown and bar.shown)
assert(ns.IsPrecisionPositionContext())
assert(ns.ConfigSessionIsActive() and ns.ConfigSessionIsDirty())
assert(ns.ConfigSessionGetFrame("player").size.width==620)
assert(castbarActive and auraActive)
assert(ns.ConfigSessionGetAura("party","buffs").xOffset==71)
assert(ns.ConfigSessionGetAura("raid","debuffs").yOffset==82)
ns.RestoreConfig()
assert(not isCollapsed() and window.shown and not bar.shown)
assert(not ns.IsPrecisionPositionContext())
assert(window.unit=="player" and window.tab=="frames" and window.category=="Auras" and window.scroll==73)
assert(ns.ConfigSessionGetFrame("player").size.width==620)
assert(castbarActive and auraActive)
assert(ns.ConfigSessionGetAura("party","buffs").yOffset==-29)
assert(ns.ConfigSessionGetAura("raid","debuffs").xOffset==-43)
assert(ns.ConfigSessionClose())
assert(ns.ConfigSessionGetAura("party","buffs").xOffset==saved.aura.xOffset)
assert(ns.ConfigSessionGetAura("raid","debuffs").xOffset==saved.aura.xOffset)
print("PASS: Collapse/Restore retain session, geometry, context and preview ownership")

-- Exercise the actual group-event handler with a staged Raid anchor. The
-- geometry sink records which state the handler asks ApplyRaidLayout to use.
local groupFile=assert(io.open("Groups.lua","r"))
local groupSource=groupFile:read("*a"); groupFile:close()
local watcherSource=assert(groupSource:match("(local watcher = CreateFrame%(\"Frame\"%).-)\n%-%- Pure geometry"))
local watcher={events={}}
function watcher:RegisterEvent(event) self.events[event]=true end
function watcher:UnregisterEvent(event) self.events[event]=nil end
function watcher:SetScript(_,callback) self.callback=callback end
local layoutCalls,liveSize,livePosition=0
local eventNS={ConfigSessionIsActive=ns.ConfigSessionIsActive}
function eventNS.ApplyPartyLayout() end
function eventNS.AreFrameMoversLocked() return false end
function eventNS.UpdateGroupPreviews() end
function eventNS.ApplyRaidLayout(savedState)
    layoutCalls=layoutCalls+1
    liveSize=savedState and ns.GetSize("raid") or ns.ConfigSessionGetFrame("raid").size
    livePosition=savedState and ns.GetPosition("raid") or ns.ConfigSessionGetPosition("raid")
end
assert(loadstring("local ns,CreateFrame=...\n"..watcherSource))(eventNS,function() return watcher end)
assert(ns.ConfigSessionBegin())
local raidSettings=ns.ConfigSessionGetFrame("raid")
raidSettings.size={width=444,height=55}
ns.ConfigSessionStageFrame("raid",raidSettings)
ns.ConfigSessionStagePosition("raid",{x=81,y=-42})
for _,event in ipairs({"GROUP_ROSTER_UPDATE","PLAYER_ROLES_ASSIGNED","PLAYER_ENTERING_WORLD"}) do
    watcher.callback(watcher,event)
    assert(liveSize.width==444 and livePosition.x==81 and livePosition.y==-42)
end
ns.CollapseConfig()
watcher.callback(watcher,"GROUP_ROSTER_UPDATE")
assert(liveSize.width==444 and livePosition.x==81)
local beforeCombat=layoutCalls
combat=true
watcher.callback(watcher,"GROUP_ROSTER_UPDATE")
assert(layoutCalls==beforeCombat and watcher.events.PLAYER_REGEN_ENABLED)
combat=false
watcher.callback(watcher,"PLAYER_REGEN_ENABLED")
assert(liveSize.width==444 and livePosition.x==81)
assert(not watcher.events.PLAYER_REGEN_ENABLED)
ns.RestoreConfig()
assert(ns.ConfigSessionClose())
watcher.callback(watcher,"GROUP_ROSTER_UPDATE")
assert(liveSize.width==saved.size.width and livePosition.x==saved.position.x)
assert(not ns.ConfigSessionIsDirty())
print("PASS: group events preserve active/collapsed Raid geometry and use saved state after Close")
