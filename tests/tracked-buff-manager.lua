-- Run from repository root with Lua 5.1.
local function noop() end
local combat=false
function InCombatLockdown() return combat end
SlashCmdList={}
function CreateFrame() return {RegisterEvent=noop,SetScript=noop} end
local secret,denied={},{}
function canaccessvalue(v) return v~=secret end
function canaccesstable(v) return v~=denied and v~=secret end
local ns={}
GameTooltip={shown=false}
function GameTooltip:SetOwner(owner) self.owner=owner end
function GameTooltip:IsOwned(owner) return self.owner==owner end
function GameTooltip:SetText(text) self.text=text end
function GameTooltip:AddLine() end
function GameTooltip:Show() self.shown=true end
function GameTooltip:Hide() self.shown=false end
function GameTooltip_Hide() GameTooltip:Hide() end
assert(loadfile("Core.lua"))("MIUF",ns)
assert(loadfile("ConfigSession.lua"))("MIUF",ns)
ns.InitializeDatabase()
assert(type(MythIncUnitFramesDB.dismissedSeenBuffs)=="table")
local version=MythIncUnitFramesDB.version
local function read(path) local f=assert(io.open(path)); local s=f:read("*a"); f:close(); return s end
local source=read("Config.lua")
-- Stop after RefreshTrackedWindow; the next local function can vary independently.
local block=assert(source:match("(local function BuffPickerUnits%(%).-)\nlocal function RefreshProfilesControls"))
-- SetProfileStatus lies between these functions and is harmless to define.
local methods={}
setmetatable(methods,{__index=function(_,key) if key:match("^[A-Z]") then return noop end end})
local function obj() return setmetatable({scripts={},clicks={"LeftButtonUp"}}, {__index=methods}) end
function methods:SetScript(event,fn) self.scripts[event]=fn end
function methods:SetText(text) self.text=text; if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self,false) end end
function methods:GetText() return self.text end
function methods:SetSize(w,h) self.width,self.height=w,h end
function methods:SetPoint(...) self.point={...} end
function methods:CreateFontString() return obj() end
function methods:CreateTexture() return obj() end
function methods:SetTexture(t) self.texture=t end
function methods:Show() self.shown=true end
function methods:Hide() self.shown=false end
function methods:RegisterForClicks(...) self.clicks={...} end
function methods:MouseClick(button)
    for _,registered in ipairs(self.clicks) do
        if registered==button.."Up" or registered=="AnyUp" then
            if self.scripts.OnClick then self.scripts.OnClick(self,button,false); return true end
        end
    end
    return false
end
local frames={}
function CreateFrame(kind,name) local o=obj(); frames[#frames+1]=o; return o end
local manager=assert(source:match("(local function CreateTrackedBuffManager%(%).-)\nlocal function CreateAuraActions"))
local factory=assert(loadstring([[
local ns=...
local selectedType,selectedAura="player","buffs"
local groupWorking={includePlayer=true}
local buffFilterPanel,manageTrackedButton,config=CreateFrame(),CreateFrame(),CreateFrame()
local trackedBuffWindow,profileActionStatus
local seenBuffButtons,trackedBuffButtons={},{}
local MEDIA,FONT="media","font"
local Skin={Panel=function() end,Button=function() end,Edit=function() end,background={},text={1,1,1},muted={.7,.7,.7}}
local function IsAurasSelected() return true end
local function MarkPending() end
local function MakeButton(parent,text,w,h) local b=CreateFrame(); b:SetText(text); b:SetSize(w,h); return b end
]]..block..manager..[[
CreateTrackedBuffManager()
return ObserveCurrentBuffs,AddTrackedSpellID,RefreshTrackedWindow,seenBuffButtons,trackedBuffButtons
]]))
local observe,add,refresh,seen,tracked=factory(ns)
function UnitIsPlayer(source) return source=="player" end
function UnitIsUnit(source,other) return source==other end
function UnitInParty() return false end
function UnitInRaid() return nil end
local auras={{spellId=123,name="First",icon=1,sourceUnit="player"},{spellId=456,name="Other",icon=2,sourceUnit="player"}}
C_UnitAuras={GetUnitAuras=function(unit,filter,count) assert(unit=="player" and filter=="HELPFUL" and count==40); return auras end}
C_Spell={GetSpellInfo=function(id) if id==10060 then return {name="Power Infusion",iconID=135939} end end}
refresh(); assert(ns.GetSeenBuffs()[123] and ns.GetSeenBuffs()[456])
local selected=seen[1].icon.texture==1 and seen[1] or seen[2]
selected.scripts.OnEnter(selected); assert(GameTooltip.shown and GameTooltip.text=="First")
assert(selected:MouseClick("LeftButton"))
assert(not GameTooltip.shown)
assert(ns.ConfigSessionGetTrackedBuffs()[123] and not ns.GetTrackedBuffs()[123])
tracked[1].scripts.OnEnter(tracked[1]); assert(GameTooltip.shown)
assert(tracked[1]:MouseClick("LeftButton")); assert(not GameTooltip.shown)
ns.ConfigSessionClear(); refresh()
selected=seen[1].icon.texture==1 and seen[1] or seen[2]
selected.scripts.OnEnter(selected); assert(GameTooltip.shown and GameTooltip.text=="First")
assert(selected:MouseClick("RightButton"))
assert(not GameTooltip.shown)
seen[1].scripts.OnEnter(seen[1]); assert(GameTooltip.shown and GameTooltip.text=="Other")
local unrelated=obj(); GameTooltip:SetOwner(unrelated); GameTooltip:SetText("Unrelated"); GameTooltip:Show()
refresh(); assert(GameTooltip.shown and GameTooltip.owner==unrelated and GameTooltip.text=="Unrelated")
assert(not ns.GetSeenBuffs()[123] and MythIncUnitFramesDB.dismissedSeenBuffs[123])
assert(ns.GetSeenBuffs()[456]); observe(); assert(not ns.GetSeenBuffs()[123])
assert(not ns.ConfigSessionIsDirty()) -- dismissal never stages tracking
local unregistered=obj(); local dispatched=false
unregistered:SetScript("OnClick",function() dispatched=true end)
assert(not unregistered:MouseClick("RightButton") and not dispatched)
-- Retail history may contain string IDs: the picker converts them to numbers.
MythIncUnitFramesDB.seenBuffs["123"]={name="Legacy",icon=1,lastSeen=0}
refresh()
selected=seen[1].icon.texture==1 and seen[1] or seen[2]
assert(selected:MouseClick("RightButton"))
assert(not ns.GetSeenBuffs()["123"] and not ns.GetSeenBuffs()[123])
assert(MythIncUnitFramesDB.dismissedSeenBuffs[123] and not ns.ConfigSessionIsDirty())
for _,button in ipairs(seen) do assert(not button.shown or button.icon.texture~=1) end
ns.ClearSeenBuffs(); assert(MythIncUnitFramesDB.dismissedSeenBuffs[123]); observe(); assert(not ns.GetSeenBuffs()[123])
ns.ResetDismissedSeenBuffs(); observe(); assert(ns.GetSeenBuffs()[123])
ns.DismissSeenBuff(10060)
assert(add(" 10060 \n")); assert(ns.ConfigSessionGetTrackedBuffs()[10060].name=="Power Infusion")
assert(not ns.GetSeenBuffs()[10060] and MythIncUnitFramesDB.dismissedSeenBuffs[10060])
assert(not add("10060")); assert(ns.ConfigSessionIsDirty())
ns.StopConfigurationMovers=function() return true end
ns.ApplySavedConfiguration=function() return true end
ns.SetFrameMoversLocked=noop; ns.SetAuraMoversLocked=noop
assert(ns.ConfigSessionRevert()); assert(not ns.ConfigSessionGetTrackedBuffs()[10060])
assert(add("10060")); assert(ns.ConfigSessionCommit()); assert(ns.GetTrackedBuffs()[10060])
for _,text in ipairs({"","abc","0","-1","1.5","1e4","999999999999999999999","9999"}) do assert(not add(text)) end
combat=true; assert(not add("10060")); combat=false
local savedInfo=C_Spell.GetSpellInfo
C_Spell.GetSpellInfo=function() return {name=secret,iconID=1} end; assert(not add("101")); C_Spell.GetSpellInfo=savedInfo
ns.ClearSeenBuffs()
auras={secret,denied,{spellId=secret,name="Bad",icon=1},{spellId=1,name=secret,icon=1},{spellId=2,name="Bad",icon=secret},setmetatable({},{__index=function() error("denied") end}),{spellId=789,name="Safe",icon=3,sourceUnit="player"}}
observe(); assert(ns.GetSeenBuffs()[789]); assert(not ns.GetSeenBuffs()[1] and not ns.GetSeenBuffs()[2])
auras=denied; observe(); auras=secret; observe()
assert(MythIncUnitFramesDB.version==version)
local resetButton,clearButton,manualInput,addButton
for _,frame in ipairs(frames) do
    if frame.text=="Reset Dismissed" then resetButton=frame end
    if frame.text=="Clear Seen History" then clearButton=frame end
    if frame.text=="Add" then addButton=frame end
    if frame.width==130 and frame.height==24 and frame.scripts.OnEnterPressed then manualInput=frame end
end
assert(resetButton and clearButton and manualInput and addButton)
ns.DismissSeenBuff(789); clearButton.scripts.OnClick(); assert(MythIncUnitFramesDB.dismissedSeenBuffs[789])
resetButton.scripts.OnClick(); assert(next(MythIncUnitFramesDB.dismissedSeenBuffs)==nil)
manualInput:SetText("bad"); addButton.scripts.OnClick(); assert(not ns.ConfigSessionIsDirty())
local runtime=read("Auras.lua")
assert(not runtime:find("HELPFUL|PLAYER",1,true))
assert(runtime:find('key = "buffs", filter = "HELPFUL"',1,true))
local filters=assert(runtime:match("(local function BuildCandidateFilters.-)\nfunction ns.PreviewBuffFiltering"))
local getFilters,update=assert(loadstring("local ns=...\n"..filters.."\nreturn BuildCandidateFilters,ApplyBuffFiltering"))(ns)
local layout={filteringEnabled=true}
local rules=getFilters("buffs","player",layout)
assert(rules.includeSpellIDs[10060] and not rules.includeSpellIDs[999])
assert(rules.isFromPlayerOrPlayerPet==nil) -- external-cast PI is eligible
local frame={MIUF_UnitType="player",MIUF_Auras={buffs={container={
 SetAuraGroupFilterString=function(_,key,filter) assert(key=="buffs" and filter=="HELPFUL") end,
 SetAuraGroupCandidateFilters=function(_,key,value) rules=value end,
}}}}
update(frame,layout,true); assert(rules.includeSpellIDs[10060] and not rules.includeSpellIDs[999])
update(frame,{filteringEnabled=false},true); assert(next(rules)==nil)
assert(source:find('RegisterEvent("UNIT_AURA")',1,true) and not block:find("OnUpdate",1,true))
-- Group source classification, including a deceptive token and every secret predicate.
ns.ClearSeenBuffs()
local class={self={player=true,self=true},party={player=true,party=true},raid={player=true,raid=7},
 outsider={player=true},npc={},pet={},vehicle={},party1={player=false},
 secretPlayer={player=secret},secretSelf={player=true,self=secret},
 secretParty={player=true,party=secret},secretRaid={player=true,raid=secret}}
function UnitIsPlayer(token) return class[token] and class[token].player or false end
function UnitIsUnit(token) local c=class[token]; return c and c.self or false end
function UnitInParty(token) local c=class[token]; return c and c.party or false end
function UnitInRaid(token) local c=class[token]; return c and c.raid or nil end
auras={}
local expected={}
local index=2000
for token in pairs(class) do
 index=index+1; auras[#auras+1]={spellId=index,name=token,icon=1,sourceUnit=token}
 if token=="self" or token=="party" or token=="raid" then expected[index]=true end
end
auras[#auras+1]={spellId=3000,name="Nil",icon=1}
auras[#auras+1]={spellId=3001,name="Secret",icon=1,sourceUnit=secret}
auras[#auras+1]={spellId=3002,name="Invalid",icon=1,sourceUnit=42}
auras[#auras+1]={spellId=3003,name="Empty",icon=1,sourceUnit=""}
auras[#auras+1]={spellId=10060,name="Power Infusion",icon=135939,sourceUnit="party"}
auras[#auras+1]={spellId=secret,name="Secret ID",icon=1,sourceUnit="party"}
auras[#auras+1]={spellId=3004,name=secret,icon=1,sourceUnit="party"}
auras[#auras+1]={spellId=3005,name="Secret icon",icon=secret,sourceUnit="party"}
ns.DismissSeenBuff(10060); observe()
for id,meta in pairs(ns.GetSeenBuffs()) do
 assert(expected[id] and meta.sourceUnit==nil and meta.spellId==nil)
 for _,aura in ipairs(auras) do assert(meta~=aura) end
end
for id in pairs(expected) do assert(ns.GetSeenBuffs()[id]) end
assert(not ns.GetSeenBuffs()[10060] and not ns.GetSeenBuffs()[3004] and not ns.GetSeenBuffs()[3005])
ns.ResetDismissedSeenBuffs(); observe(); assert(ns.GetSeenBuffs()[10060])
ns.ClearSeenBuffs(); combat=true; observe(); assert(next(ns.GetSeenBuffs())==nil); combat=false
UnitIsPlayer=function() error("unavailable source") end; observe(); assert(next(ns.GetSeenBuffs())==nil)
print("PASS: seen dismissal/reset, curated safe discovery, manual IDs/staging, caster-independent tracked runtime and unfiltered behavior")
