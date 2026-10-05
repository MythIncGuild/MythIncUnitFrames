local ADDON_NAME, ns = ...

local RAW_LIMIT, BINARY_LIMIT, DEPTH_LIMIT, ENTRY_LIMIT, STRING_LIMIT = 98304, 65536, 8, 4096, 256
local function Fail(message) error(message,0) end
local function Accessible(value)
    if not canaccessvalue or not canaccessvalue(value) then Fail("A profile value is secret or inaccessible.") end
end
local function PlainTable(value)
    Accessible(value)
    if type(value)~="table" or not canaccesstable or not canaccesstable(value) then Fail("Expected an accessible settings table.") end
    if getmetatable(value)~=nil then Fail("Settings tables cannot have metatables.") end
end
local function CheckResources(value,depth,state)
    Accessible(value)
    local kind=type(value)
    if kind=="table" then
        PlainTable(value)
        if depth>DEPTH_LIMIT then Fail("Settings are nested too deeply.") end
        if state.seen[value] then Fail("Settings cannot contain cycles or shared tables.") end
        state.seen[value]=true
        for key,item in pairs(value) do
            Accessible(key)
            if type(key)~="string" or #key>64 then Fail("Invalid settings key.") end
            state.entries=state.entries+1
            if state.entries>ENTRY_LIMIT then Fail("Too many settings entries.") end
            CheckResources(item,depth+1,state)
        end
    elseif kind=="number" then
        if value~=value or value==math.huge or value==-math.huge then Fail("Settings numbers must be finite.") end
    elseif kind=="string" then
        if #value>STRING_LIMIT then Fail("A settings string is too long.") end
    elseif kind~="boolean" then Fail("Unsupported settings value type.") end
end
local function Resources(value) CheckResources(value,1,{seen={},entries=0}) end

local function Schema()
    local defaults=ns.GetProfileSharingDefaults()
    defaults.trackedBuffs=nil
    return defaults
end
local function OneOf(value,values,path)
    for _,item in ipairs(values) do if value==item then return end end
    Fail("Unsupported value for "..path..".")
end
local function Bounds(value,minimum,maximum,path)
    if value<minimum or value>maximum then Fail("Value outside supported bounds: "..path..".") end
end
local function Leaf(value,path,key)
    if type(value)=="string" then
        if key=="point" or key=="relativePoint" then
            OneOf(value,{"TOPLEFT","TOP","TOPRIGHT","LEFT","CENTER","RIGHT","BOTTOMLEFT","BOTTOM","BOTTOMRIGHT"},path)
        elseif key=="orientation" then OneOf(value,{"VERTICAL","HORIZONTAL"},path)
        elseif key=="direction" then OneOf(value,{"UP","DOWN","LEFT","RIGHT"},path)
        elseif key=="anchor" then OneOf(value,{"TOP","BOTTOM"},path)
        elseif key=="growth" or key=="portraitSide" then OneOf(value,{"LEFT","RIGHT"},path)
        else
            local catalog=key=="fontFace" and ns.Media.fonts or key=="texture" and ns.Media.textures
                or key=="healthColor" and ns.Media.healthColors or key=="powerColor" and ns.Media.powerColors
            if not catalog or not catalog[value] then Fail("Unsupported media selection: "..path..".") end
        end
    elseif type(value)=="number" then
        local coordinate=path:match("^positions%.") or (path:match("^auraLayout%.") and (key=="xOffset" or key=="yOffset"))
        if not coordinate and value~=math.floor(value) then Fail("Expected a whole number for "..path..".") end
        if path:match("^positions%.") then Bounds(value,-1000000,1000000,path)
        elseif path:match("^sizes%.") then
            local raid=path:match("^sizes%.raid%.")
            Bounds(value,key=="width" and (raid and 50 or 100) or (raid and 18 or 24),key=="width" and 600 or 150,path)
        elseif path:find(".castbar.",1,true) then
            if key=="width" then if value~=0 then Bounds(value,100,600,path) end
            elseif key=="height" then Bounds(value,18,40,path)
            else Bounds(value,-1000,1000,path) end
        elseif key=="powerPercent" then Bounds(value,10,40,path)
        elseif path:match("^groupLayout%.") then Bounds(value,0,80,path)
        elseif path:match("^auraLayout%.") then
            if key=="iconSize" then Bounds(value,12,40,path)
            elseif key=="maxCount" then Bounds(value,1,12,path)
            elseif key=="spacing" then Bounds(value,0,10,path)
            else Bounds(value,-1000000,1000000,path) end
        elseif key=="fontSize" then Bounds(value,8,24,path)
        elseif key=="portraitPercent" then Bounds(value,12,40,path)
        elseif key=="backgroundOpacity" or key=="borderOpacity" then Bounds(value,0,100,path)
        elseif key:match("Size$") then Bounds(value,8,48,path)
        elseif key=="nameXOffset" or key=="healthXOffset" then Bounds(value,-200,200,path)
        elseif key=="nameYOffset" or key=="healthYOffset" then Bounds(value,-100,100,path)
        elseif key:match("Offset$") then
            local limit=(key:match("^raidMarker") or key:match("^statusIcon") or key:match("^leaderIcon")) and 150 or 100
            Bounds(value,-limit,limit,path)
        else Fail("Unrecognized numeric setting: "..path..".") end
    end
end
local function CopyRecognized(source,schema,path,export)
    PlainTable(source)
    if not export then
        for key in pairs(source) do if schema[key]==nil then Fail("Unknown setting: "..path..key..".") end end
    end
    local result={}
    for key,default in pairs(schema) do
        local value=source[key]
        Accessible(value)
        if value==nil then value=default end
        local itemPath=path..key
        if type(value)~=type(default) then Fail("Wrong type for "..itemPath..".") end
        if type(default)=="table" then result[key]=CopyRecognized(value,default,itemPath..".",export)
        else Leaf(value,itemPath,key); result[key]=value end
    end
    return result
end
local function Candidate(settings)
    Resources(settings)
    local result=CopyRecognized(settings,Schema(),"",false)
    -- Direction must agree with the group's orientation.
    for _,kind in ipairs({"party","boss"}) do
        local group=result.groupLayout[kind]
        OneOf(group.direction,group.orientation=="VERTICAL" and {"UP","DOWN"} or {"LEFT","RIGHT"},"groupLayout."..kind..".direction")
    end
    result=ns.NormalizeSharedProfile(result)
    Resources(result)
    return CopyRecognized(result,Schema(),"",false)
end
local function Adler32(source)
    local a,b=1,0
    for i=1,#source do a=(a+source:byte(i))%65521; b=(b+a)%65521 end
    return string.format("%08x",b*65536+a)
end

-- Bound and consume one entire CBOR value before calling the native decoder.
-- This prevents ignored trailing bytes, duplicate map keys, and oversized/deep
-- containers from being hidden by native deserialization. No Lua is executed.
local function CheckCBOR(source)
    local pos,entries=1,0
    local function Byte()
        local byte=source:byte(pos); if not byte then Fail("Truncated CBOR payload.") end
        pos=pos+1; return byte
    end
    local function Length(info)
        if info<24 then return info end
        local bytes=info==24 and 1 or info==25 and 2 or info==26 and 4 or info==27 and 8
        if not bytes then Fail("Invalid CBOR length.") end
        local length=0
        for i=1,bytes do length=length*256+Byte(); if length>BINARY_LIMIT then Fail("CBOR length exceeds the limit.") end end
        return length
    end
    local function Skip(bytes)
        if pos+bytes-1>#source then Fail("Truncated CBOR payload.") end
        pos=pos+bytes
    end
    local function String(info)
        local length=Length(info)
        if length>STRING_LIMIT then Fail("A CBOR string is too long.") end
        local start=pos; Skip(length); return source:sub(start,pos-1)
    end
    local Walk
    Walk=function(depth)
        if depth>DEPTH_LIMIT then Fail("CBOR payload is nested too deeply.") end
        local header=Byte(); local major,info=math.floor(header/32),header%32
        if major==0 or major==1 then
            if info<24 then return end
            local bytes=info==24 and 1 or info==25 and 2 or info==26 and 4 or info==27 and 8
            if not bytes then Fail("Invalid CBOR number.") end
            Skip(bytes)
        elseif major==2 or major==3 then String(info)
        elseif major==5 then
            local count=info~=31 and Length(info) or nil
            local keys={}; local index=0
            while not count or index<count do
                if not count and source:byte(pos)==255 then pos=pos+1; break end
                entries=entries+1; if entries>ENTRY_LIMIT then Fail("Too many CBOR entries.") end
                local keyHeader=Byte(); local keyMajor=math.floor(keyHeader/32)
                if keyMajor~=2 and keyMajor~=3 then Fail("CBOR settings keys must be strings.") end
                local key=String(keyHeader%32)
                if #key>64 or keys[key] then Fail("Invalid or duplicate CBOR key.") end
                keys[key]=true; Walk(depth+1); index=index+1
            end
        elseif major==7 then
            if info==20 or info==21 then return end
            local bytes=info==25 and 2 or info==26 and 4 or info==27 and 8
            if not bytes then Fail("Unsupported CBOR value.") end
            Skip(bytes)
        else Fail("Unsupported CBOR container or value.") end
    end
    Walk(1)
    if pos~=#source+1 then Fail("Trailing data after the CBOR payload.") end
end
local function Codec()
    if not C_EncodingUtil or not C_EncodingUtil.SerializeCBOR or not C_EncodingUtil.DeserializeCBOR
        or not C_EncodingUtil.EncodeBase64 or not C_EncodingUtil.DecodeBase64 then
        Fail("This Retail client does not provide the required profile encoding APIs.")
    end
    return C_EncodingUtil
end
local function SafeString(value)
    Accessible(value)
    if type(value)~="string" then Fail("The profile encoding operation failed.") end
    return value
end
local function Decode(text)
    Accessible(text)
    if type(text)~="string" or #text>RAW_LIMIT then Fail("Paste an MIUF string of at most 96 KiB.") end
    text=text:gsub("[ \t\r\n]","")
    local version,checksum,payload=text:match("^MIUF:(%d+):(%x%x%x%x%x%x%x%x):([A-Za-z0-9_%-=]+)$")
    if not version then Fail("Malformed MIUF export string.") end
    if version~="1" then Fail("Unsupported MIUF export version.") end
    if #payload>87384 then Fail("Invalid Base64 payload length.") end
    local body,padding=payload:match("^([A-Za-z0-9_%-]*)(=*)$")
    if not body or #padding>2 or #body%4==1
        or (#padding>0 and #padding~=(4-#body%4)%4) then Fail("Malformed Base64 payload.") end
    local padded=body..string.rep("=",(4-#body%4)%4)
    local codec=Codec(); local variant=Enum.Base64Variant.StandardUrlSafe
    local binary=SafeString(codec.DecodeBase64(padded,variant))
    if #binary>BINARY_LIMIT then Fail("Decoded profile exceeds 64 KiB.") end
    -- Canonical re-encoding rejects invalid padding bits and decoder leniency.
    if SafeString(codec.EncodeBase64(binary,variant)):gsub("=+$","")~=body then Fail("Malformed Base64 payload.") end
    if Adler32(binary)~=checksum:lower() then Fail("Profile checksum mismatch. Copy the complete export again.") end
    CheckCBOR(binary)
    local envelope=codec.DeserializeCBOR(binary)
    Resources(envelope); PlainTable(envelope)
    for key in pairs(envelope) do if key~="schema" and key~="settings" then Fail("Unknown export envelope field.") end end
    if envelope.schema~=1 then Fail("Unsupported MIUF profile schema.") end
    return Candidate(envelope.settings)
end
local function CleanSession()
    if ns.ConfigSessionIsDirty() then Fail("Apply or Revert pending changes before sharing a profile.") end
end
local function Export()
    CleanSession()
    local name=ns.GetActiveProfileName()
    local profile=MythIncUnitFramesDB.profiles[name]
    local settings=CopyRecognized(profile,Schema(),"",true)
    settings=Candidate(settings)
    local codec=Codec()
    local binary=SafeString(codec.SerializeCBOR({schema=1,settings=settings},{ignoreSerializationErrors=false}))
    if #binary>BINARY_LIMIT then Fail("Profile exceeds the 64 KiB export limit.") end
    CheckCBOR(binary)
    local payload=SafeString(codec.EncodeBase64(binary,Enum.Base64Variant.StandardUrlSafe))
    -- Emit padded RFC 4648 text even if the native URL-safe encoder omits it.
    payload=payload..string.rep("=",(4-#payload%4)%4)
    return "MIUF:1:"..Adler32(binary)..":"..payload,name
end
function ns.ExportProfile()
    local ok,text,name=pcall(Export)
    if not ok then return nil,text end
    return text,name
end
function ns.PrepareProfileImport(text)
    local ok,request=pcall(function()
        -- Validate first; invalid strings must not touch even session bookkeeping.
        local candidate=Decode(text)
        if InCombatLockdown() then Fail("Profiles cannot be imported during combat.") end
        CleanSession()
        local name=ns.GetActiveProfileName()
        local destination=MythIncUnitFramesDB.profiles[name]
        local used=false
        return {profileName=name,confirm=function(cleanup)
            local installed,err=pcall(function()
                if used then Fail("Validate the import again.") end
                if InCombatLockdown() then Fail("Profiles cannot be imported during combat.") end
                CleanSession()
                if ns.GetActiveProfileName()~=name or MythIncUnitFramesDB.profiles[name]~=destination then
                    Fail("The current profile changed. Validate the import again.")
                end
                if cleanup and cleanup()==false then Fail("Configuration cleanup did not complete.") end
                local replaced,message=ns.ReplaceSharedProfile(name,destination,candidate)
                if not replaced then Fail(message) end
                used=true
                ns.ConfigSessionClear()
                ReloadUI()
            end)
            return installed,installed and nil or err
        end}
    end)
    if not ok then return nil,request end
    return request
end
