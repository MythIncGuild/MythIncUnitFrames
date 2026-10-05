-- Run from the repository root: lua5.1 tests/profile-sharing-ui.lua
local file=assert(io.open("Config.lua","r")); local source=file:read("*a"); file:close()
local sharing=assert(source:match("(local function OpenProfileSharing%(mode%).-)\nlocal function CreateProfilesPage"))
local objects={}
local methods={}
local function noop() end
for _,name in ipairs({"SetFont","SetBackdrop","SetClampedToScreen","SetFrameLevel","SetJustifyH","SetMultiLine","SetAutoFocus","SetWordWrap","SetNonSpaceWrap"}) do methods[name]=noop end
local function object(parent)
    local value=setmetatable({parent=parent,scripts={},shown=true,vertical=0},{__index=methods})
    objects[#objects+1]=value; return value
end
function methods:SetScript(event,fn) self.scripts[event]=fn end
function methods:SetText(text) self.text=text; if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self,false) end end
function methods:GetText() return self.text end
function methods:SetMaxLetters(n) self.maxLetters=n end
function methods:SetWidth(n) self.width=n end
function methods:SetHeight(n) self.height=n end
function methods:SetSize(width,height) self.width,self.height=width,height end
function methods:GetWidth() return self.width or 590 end
function methods:GetHeight() return self.height or 260 end

function methods:EnableMouse(enabled) self.mouseEnabled=enabled end
function methods:SetPoint(...)
    local point={...}; self.points=self.points or {}; self.points[point[1]]=point; self.point=point
    if point[1]=="BOTTOMLEFT" and point[3]=="TOPLEFT" then self.height=-point[5] end
end
function methods:GetFrameLevel() return 1 end
function methods:SetScrollChild(box) self.box=box end
function methods:GetVerticalScroll() return self.vertical end
function methods:SetVerticalScroll(value) self.vertical=value end
function methods:HighlightText() self.selected=true end
function methods:SetFocus() self.focus=true end
function methods:ClearFocus() self.focus=false end
function methods:Show() self.shown=true end
function methods:Hide() self.shown=false; if self.scripts.OnHide then self.scripts.OnHide(self) end end
function methods:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function methods:CreateFontString()
    local font=object(self); font.GetStringHeight=function(self) return self.stringHeight or 11 end
    self.lastFontString=font; return font
end
function CreateFrame(_,_,parent) return object(parent) end
local config=object()
local statuses={}; local cleanup,confirmed,prepared,exports=0,0,0,0
local active="Active"; local exportString="MIUF:1:00000000:"..string.rep("A",12000)
local exportError,importError
local ns={}
function ns.GetActiveProfileName() return active end
function ns.ExportProfile()
    exports=exports+1
    if exportError then return nil,exportError end
    return exportString,active
end
function ns.CloseConfig() cleanup=cleanup+1; return true end
function ns.PrepareProfileImport(text)
    prepared=prepared+1; assert(text=="pasted string")
    if importError then return nil,importError end
    return {profileName=active,confirm=function(close) confirmed=confirmed+1; assert(close()); return true end}
end
local factory=assert(loadstring([[
    local ns,config,statuses=...
    local sharingDialog
    local MEDIA,FONT="media","font"
    local Skin={Panel=function() end,background={}}
    local function SetProfileStatus(text) statuses[#statuses+1]=text end
    local function MakeButton(parent,text) local b=CreateFrame("Button",nil,parent); b:SetText(text); return b end
]]..sharing..[[
    return OpenProfileSharing,function() return sharingDialog end
]]))
local open,get=factory(ns,config,statuses)
open("export"); local dialog=get()
assert(config.shown and cleanup==0 and dialog.title.text=="Export current profile: Active")
assert(dialog.box.text:gsub("%s","")==exportString and dialog.box.maxLetters==98305)
for line in dialog.box.text:gmatch("[^\n]+") do assert(#line<=96) end
dialog.action.scripts.OnClick(); assert(dialog.box.selected and dialog.box.focus)
dialog.box.text="accidental edit"; dialog.box.scripts.OnTextChanged(dialog.box,true)
assert(dialog.box.text:gsub("%s","")==exportString)
dialog:Hide(); assert(cleanup==0 and dialog.request==nil)
exportError="Apply or Revert first"; open("export"); assert(statuses[#statuses]==exportError); exportError=nil
open("import"); assert(get()==dialog and config.shown and cleanup==0)
assert(dialog.title.text=="Import into current profile: Active" and dialog.action.text=="Import")
assert(dialog.box.text=="" and dialog.box.width==dialog.scroll:GetWidth())
assert(dialog.box.height>=dialog.scroll:GetHeight() and dialog.scroll.box==dialog.box)
assert(dialog.box.points.TOPLEFT[2]==dialog.scroll and dialog.box.points.BOTTOMLEFT[2]==dialog.scroll)
assert(dialog.box.mouseEnabled and dialog.scroll.mouseEnabled)
assert(dialog.box.GetStringHeight==nil and dialog.box.UnknownWidgetMethod==nil)
assert(dialog.scroll.lastFontString.shown==false)
dialog.box:ClearFocus(); dialog.scroll.scripts.OnMouseDown(dialog.scroll,"LeftButton")
assert(dialog.box.focus) -- blank viewport click focuses on the first click
dialog.box:ClearFocus(); dialog.scroll.scripts.OnMouseDown(dialog.scroll,"RightButton")
assert(not dialog.box.focus)
dialog.scroll:SetSize(600,280); dialog.scroll.scripts.OnSizeChanged(dialog.scroll)
assert(dialog.box.width==600 and dialog.box.height==280)
dialog.scroll.lastFontString.stringHeight=800; dialog.box:SetText("long text")
assert(dialog.box.height==800) -- long content remains scrollable
dialog.scroll.lastFontString.stringHeight=11; dialog.box:SetText("")
assert(dialog.box.height==280) -- clearing text preserves the viewport hit area
dialog.box:SetText("pasted string"); importError="Malformed MIUF string"
dialog.action.scripts.OnClick(); assert(dialog.feedback.text==importError and confirmed==0 and cleanup==0)
importError=nil; dialog.action.scripts.OnClick()
assert(dialog.action.text=="Confirm Import" and dialog.feedback.text:find("Your tracked buffs will be kept.",1,true))
assert(confirmed==0 and cleanup==0)
dialog:Hide(); assert(dialog.request==nil and cleanup==0) -- cancel validation
open("import"); dialog.box:SetText("pasted string"); dialog.action.scripts.OnClick()
dialog.box.scripts.OnTextChanged(dialog.box,true)
assert(dialog.request==nil and dialog.action.text=="Import")
dialog.action.scripts.OnClick(); dialog.action.scripts.OnClick()
assert(confirmed==1 and cleanup==1)
assert(source:find('local export=MakeButton(section,"Export"',1,true))
assert(source:find('local import=MakeButton(section,"Import"',1,true))
print("PASS: reusable sharing dialog, active-profile labels, wrapping, Select All, errors, confirmation, cancellation and session-safe opening")
