-- Run from the repository root: lua5.1 tests/profile-sharing.lua
-- Independent CBOR/Base64 test doubles exercise actual wire bytes. Retail must
-- still verify Blizzard's native codec and the dialog/clipboard behavior.
local function noop() end
function CreateFrame() return {RegisterEvent=noop,SetScript=noop} end
SlashCmdList={}
local combat,reloads=false,0
function InCombatLockdown() return combat end
function ReloadUI() reloads=reloads+1 end
local secret={}
local denied
function canaccessvalue(v) return v~=secret end
function canaccesstable(v) return v~=secret and v~=denied end
Enum={Base64Variant={StandardUrlSafe=1}}
local alphabet="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
local function base64(source)
    local out={}
    for i=1,#source,3 do
        local a,b,c=source:byte(i,i+2); local n=a*65536+(b or 0)*256+(c or 0)
        out[#out+1]=alphabet:sub(math.floor(n/262144)%64+1,math.floor(n/262144)%64+1)
            ..alphabet:sub(math.floor(n/4096)%64+1,math.floor(n/4096)%64+1)
            ..(b and alphabet:sub(math.floor(n/64)%64+1,math.floor(n/64)%64+1) or "=")
            ..(c and alphabet:sub(n%64+1,n%64+1) or "=")
    end
    return table.concat(out)
end
local function unbase64(source)
    local out={}
    for i=1,#source,4 do
        local n=0
        for j=i,i+3 do
            local c=source:sub(j,j); local at=alphabet:find(c,1,true)
            n=n*64+(at and at-1 or 0)
        end
        out[#out+1]=string.char(math.floor(n/65536)%256)
        if source:sub(i+2,i+2)~="=" then out[#out+1]=string.char(math.floor(n/256)%256) end
        if source:sub(i+3,i+3)~="=" then out[#out+1]=string.char(n%256) end
    end
    return table.concat(out)
end
local function header(major,n)
    if n<24 then return string.char(major*32+n) end
    if n<256 then return string.char(major*32+24,n) end
    if n<65536 then return string.char(major*32+25,math.floor(n/256),n%256) end
    return string.char(major*32+26,math.floor(n/16777216)%256,math.floor(n/65536)%256,math.floor(n/256)%256,n%256)
end
local encode
encode=function(v)
    if type(v)=="table" then
        local out={}; local count=0
        for k,item in pairs(v) do count=count+1; out[#out+1]=encode(k)..encode(item) end
        return header(5,count)..table.concat(out)
    elseif type(v)=="string" then return header(3,#v)..v
    elseif type(v)=="boolean" then return string.char(v and 245 or 244)
    elseif type(v)=="number" then
        if v~=v then return string.char(251,127,248,0,0,0,0,0,0) end
        if v==math.huge then return string.char(251,127,240,0,0,0,0,0,0) end
        if v==-math.huge then return string.char(251,255,240,0,0,0,0,0,0) end
        if v==math.floor(v) then return header(v>=0 and 0 or 1,v>=0 and v or -v-1) end
        local sign=v<0 and 128 or 0
        local mantissa,exponent=math.frexp(math.abs(v)); exponent=exponent+1022
        local fraction=(mantissa*2-1)*4503599627370496
        local first=sign+math.floor(exponent/16); local second=(exponent%16)*16+math.floor(fraction/281474976710656)
        local bytes={251,first,second}
        for power=5,0,-1 do bytes[#bytes+1]=math.floor(fraction/256^power)%256 end
        return string.char(unpack(bytes))
    end
    error("Unsupported test serialization type")
end
local function decode(source)
    local pos=1
    local function byte() local v=assert(source:byte(pos)); pos=pos+1; return v end
    local function length(info)
        if info<24 then return info end
        local count=assert(({[24]=1,[25]=2,[26]=4,[27]=8})[info]); local n=0
        for i=1,count do n=n*256+byte() end
        return n
    end
    local read
    read=function()
        local h=byte(); local major,info=math.floor(h/32),h%32
        if major==0 then return length(info)
        elseif major==1 then return -length(info)-1
        elseif major==3 or major==2 then local n=length(info); local s=source:sub(pos,pos+n-1); pos=pos+n; return s
        elseif major==5 then
            local t={}; for i=1,length(info) do local k=read(); t[k]=read() end; return t
        elseif major==7 then
            if info==20 then return false elseif info==21 then return true end
            assert(info==27); local first,second=byte(),byte()
            local sign=first>=128 and -1 or 1
            local exponent=(first%128)*16+math.floor(second/16); local fraction=second%16
            for i=1,6 do fraction=fraction*256+byte() end
            if exponent==2047 then return fraction~=0 and 0/0 or sign*math.huge end
            return sign*(1+fraction/4503599627370496)*2^(exponent-1023)
        end
        error("Invalid test CBOR")
    end
    local v=read(); assert(pos==#source+1); return v
end
local serialized,override
C_EncodingUtil={
    SerializeCBOR=function(v,options) assert(options.ignoreSerializationErrors==false); serialized=v; return encode(v) end,
    DeserializeCBOR=function(s) if override then return override(s) end; return decode(s) end,
    EncodeBase64=function(s,variant) assert(variant==1); return base64(s) end,
    DecodeBase64=function(s,variant) assert(variant==1); return unbase64(s) end,
}
local ns={}
assert(loadfile("Core.lua"))("MIUF",ns)
assert(loadfile("Media.lua"))("MIUF",ns)
assert(loadfile("ConfigSession.lua"))("MIUF",ns)
assert(loadfile("ProfileSharing.lua"))("MIUF",ns)
ns.InitializeDatabase()
local function current() return MythIncUnitFramesDB.profiles[ns.GetActiveProfileName()] end
local function copy(t) return ns.CopyTable(t) end
local function equal(a,b)
    if type(a)~=type(b) then return false end
    if type(a)~="table" then return a==b end
    for k,v in pairs(a) do if not equal(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end
    return true
end
local function adler(s)
    local a,b=1,0; for i=1,#s do a=(a+s:byte(i))%65521; b=(b+a)%65521 end
    return string.format("%08x",b*65536+a)
end
local function raw(s) return "MIUF:1:"..adler(s)..":"..base64(s) end
local function wire(v) return raw(encode(v)) end
local function envelope(settings) return {schema=1,settings=settings or {}} end
local function rejected(text)
    local before=copy(MythIncUnitFramesDB); local identity=current(); local calls=reloads
    local request,err=ns.PrepareProfileImport(text)
    assert(not request and type(err)=="string",err or "accepted bad input")
    assert(current()==identity and equal(before,MythIncUnitFramesDB) and reloads==calls,"invalid import mutated state")
end
local baseline=assert(ns.ExportProfile())
assert(not serialized.settings.trackedBuffs and not serialized.settings.locked)
assert(serialized.settings.sizes.raid.width==120)
local profile=current()
profile.positions.player={point="BOTTOMRIGHT",relativePoint="BOTTOMRIGHT",x=-1234,y=432}
profile.positions.raid.x=99; profile.sizes.party={width=333,height=66}
profile.sizes.raid={width=50,height=18}; profile.enabled.player=false; profile.enabled.raid=true
profile.appearance.player.fontFace="oxanium"; profile.appearance.party.texture="stone"
profile.appearance.target.healthColor="red"; profile.appearance.player.showHealthText=false
profile.groupLayout.party={orientation="HORIZONTAL",direction="LEFT",spacing=17,includePlayer=true}
profile.groupLayout.raid={orientation="HORIZONTAL",legacy40=true}
profile.groupLayout.boss.spacing=51
profile.barLayout.player.castbar={enabled=false,width=370,height=23,xOffset=-44,yOffset=88}
profile.auraLayout.party.buffs.filteringEnabled=false; profile.auraLayout.party.buffs.xOffset=1.5
profile.auraLayout.raid.debuffs.maxCount=9; profile.frameLocked=false; profile.auraLocked=false
profile.trackedBuffs={[20707]={name="Source Soulstone",icon=136210}}
profile.unrecognizedOldValue="not portable"
local exported,exportName=ns.ExportProfile(); assert(exported and exportName==ns.GetActiveProfileName())
local exportedSettings=copy(serialized.settings)
assert(exportedSettings.unrecognizedOldValue==nil and exportedSettings.trackedBuffs==nil)
assert(ns.CreateProfile("Destination")); assert(ns.SetActiveProfile("Destination"))
local destination=current(); destination.trackedBuffs={[17]={name="Destination only",icon=123}}
local tracked=destination.trackedBuffs; local trackedContents=copy(tracked)
local other=MythIncUnitFramesDB.profiles.Default; local otherContents=copy(other)
local keys=MythIncUnitFramesDB.profileKeys; local keyContents=copy(keys)
local seen=MythIncUnitFramesDB.seenBuffs; local seenContents=copy(seen); local version=MythIncUnitFramesDB.version
local request=assert(ns.PrepareProfileImport(exported)); assert(current()==destination) -- preparation/cancel is read-only
assert(request.confirm(function() return true end)); assert(reloads==1)
assert(current().trackedBuffs==tracked and equal(tracked,trackedContents))
assert(MythIncUnitFramesDB.profiles.Default==other and equal(other,otherContents))
assert(MythIncUnitFramesDB.profileKeys==keys and equal(keys,keyContents))
assert(MythIncUnitFramesDB.seenBuffs==seen and equal(seen,seenContents) and MythIncUnitFramesDB.version==version)
local result=copy(current()); result.trackedBuffs=nil; assert(equal(result,exportedSettings))
assert(not current().enabled.player and not current().frameLocked and not current().auraLocked)
assert(current().auraLayout.party.buffs.xOffset==1.5)
assert(not request.confirm())
assert(ns.PrepareProfileImport(exported:gsub("(.)(.)","%1 \n%2")))
assert(ns.PrepareProfileImport(exported:gsub("=+$","")))
local nativeEncode=C_EncodingUtil.EncodeBase64
C_EncodingUtil.EncodeBase64=function(s,variant) return nativeEncode(s,variant):gsub("=+$","") end
assert(ns.PrepareProfileImport(assert(ns.ExportProfile())))
C_EncodingUtil.EncodeBase64=nativeEncode
rejected("hello"); rejected(exported:gsub("MIUF:","MIUF!",1)); rejected(exported:gsub("MIUF:1:","MIUF:2:",1))
rejected(exported.."!"); rejected(exported:sub(1,-2)); rejected(exported:gsub(":%x%x%x%x%x%x%x%x:",":00000000:",1))
rejected("MIUF:1:00000000:AA=A"); rejected(raw(encode(envelope()).."garbage")); rejected(raw(string.char(255)))
rejected(wire({schema=2,settings={}})); rejected(wire({schema=1,settings={},extra=true}))
rejected(wire(envelope({trackedBuffs={}}))); rejected(wire(envelope({unknown=true})))
rejected(wire(envelope({enabled={player="false"}}))); rejected(wire(envelope({sizes={player={width=999999}}})))
rejected(wire(envelope({auraLayout={raid={debuffs={maxCount=1.5}}}})))
rejected(wire(envelope({appearance={player={fontFace="missing"}}})))
rejected(wire(envelope({positions={player={point="invalid"}}})))
rejected(wire(envelope({groupLayout={party={orientation="HORIZONTAL",direction="DOWN"}}})))
for _,value in ipairs({0/0,math.huge,-math.huge}) do rejected(wire(envelope({sizes={player={width=value}}}))) end
rejected(wire(envelope({appearance={player={fontFace=string.rep("a",257)}}})))
rejected(string.rep("a",98305)); rejected(raw(string.rep("a",65537)))
local deep={}; local t=deep; for i=1,10 do t.child={}; t=t.child end; rejected(wire(envelope(deep)))
local many={}; for i=1,4097 do many["key"..i]=true end; rejected(wire(envelope(many)))
-- Preflight rejects map duplicates and numeric keys before native decode.
rejected(raw(string.char(162)..encode("schema")..encode(1)..encode("schema")..encode(1)))
rejected(raw(string.char(161)..encode(1)..encode(true)))
for _,bad in ipairs({function() end,coroutine.create(noop),newproxy(true),setmetatable({},{})}) do
    override=function() return {schema=1,settings={appearance={player={fontFace=bad}}}} end
    rejected(wire(envelope()))
end
override=function() local cycle={}; cycle.self=cycle; return envelope(cycle) end; rejected(wire(envelope()))
override=function() error("native decoder failure") end; rejected(wire(envelope())); override=nil
local minimal=assert(ns.PrepareProfileImport(wire(envelope({enabled={raid=false}}))))
assert(minimal.confirm()); assert(current().enabled.raid==false and current().sizes.player.width==250)
assert(current().trackedBuffs==tracked)
assert(ns.ConfigSessionBegin()); ns.ConfigSessionStageEnabled("raid",true)
local text,err=ns.ExportProfile(); assert(not text and err:find("Apply or Revert"))
rejected(exported); assert(ns.ConfigSessionGetEnabled("raid")==true and ns.ConfigSessionIsDirty())
ns.ConfigSessionClear()
combat=true; rejected(exported); combat=false
local prepared=assert(ns.PrepareProfileImport(exported)); local identity=current(); local before=copy(MythIncUnitFramesDB)
combat=true; assert(not prepared.confirm()); assert(current()==identity and equal(before,MythIncUnitFramesDB)); combat=false
prepared=assert(ns.PrepareProfileImport(exported)); ns.ConfigSessionStageEnabled("raid",true)
assert(not prepared.confirm()); assert(current()==identity and ns.ConfigSessionGetEnabled("raid")); ns.ConfigSessionClear()
prepared=assert(ns.PrepareProfileImport(exported)); assert(ns.SetActiveProfile("Default")); before=copy(MythIncUnitFramesDB)
assert(not prepared.confirm()); assert(equal(before,MythIncUnitFramesDB))
prepared=assert(ns.PrepareProfileImport(exported)); local name=ns.GetActiveProfileName()
MythIncUnitFramesDB.profiles[name]=copy(current()); before=copy(MythIncUnitFramesDB)
assert(not prepared.confirm()); assert(equal(before,MythIncUnitFramesDB))
local font=current().appearance.player.fontFace; current().appearance.player.fontFace=secret
assert(not ns.ExportProfile()); current().appearance.player.fontFace=font
denied=current().appearance; assert(not ns.ExportProfile()); denied=nil
prepared=assert(ns.PrepareProfileImport(exported)); before=copy(MythIncUnitFramesDB)
assert(not prepared.confirm(function() return false end)); assert(equal(before,MythIncUnitFramesDB))
local codec=C_EncodingUtil; C_EncodingUtil=nil; assert(not ns.ExportProfile()); C_EncodingUtil=codec
local config=assert(io.open("Config.lua","r")); local configSource=config:read("*a"); config:close()
assert(configSource:find('OpenProfileSharing("export")',1,true))
assert(configSource:find('request.confirm(function() return ns.CloseConfig() end)',1,true))
print("PASS: profile sharing round trip, schema/resources, wire integrity, tracked table preservation, isolation, secrets and confirmation lifecycle")
print("Measured test-codec exports: defaults="..#baseline.." bytes; customized="..#exported.." bytes (Retail-native sizes require manual verification)")
