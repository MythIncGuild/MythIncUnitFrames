-- Run from the repository root: lua5.1 tests/castbar-layout.lua
function CreateFrame()
    return {RegisterEvent=function() end,SetScript=function() end}
end
SlashCmdList={}
local ns={}
assert(loadfile("Core.lua"))("MythIncUnitFrames",ns)

local defaults=ns.NormalizeCastbarLayout({})
assert(defaults.xOffset==0 and defaults.yOffset==-3)
assert(defaults.enabled and defaults.width==0 and defaults.height==18)

for _,case in ipairs({
    {500,500}, {-500,-500},
    {1000,1000}, {-1000,-1000},
    {1001,1000}, {-1001,-1000},
    {734.4,734}, {734.5,735},
    {-734.4,-734}, {-734.5,-734},
}) do
    local layout=ns.NormalizeCastbarLayout({xOffset=case[1],yOffset=case[1]})
    assert(layout.xOffset==case[2] and layout.yOffset==case[2],tostring(case[1]))
end

for _,unitType in ipairs({"player","target"}) do
    ns.SaveCastbarLayout(unitType,{xOffset=750,yOffset=-750})
    local saved=MythIncUnitFramesDB.profiles[ns.GetActiveProfileName()].barLayout[unitType].castbar
    assert(saved.xOffset==750 and saved.yOffset==-750)
    local layout=ns.GetCastbarLayout(unitType)
    assert(layout.xOffset==750 and layout.yOffset==-750)
    ns.SaveCastbarLayout(unitType,{xOffset=-2500,yOffset=2500})
    layout=ns.GetCastbarLayout(unitType)
    assert(layout.xOffset==-1000 and layout.yOffset==1000)
end
print("PASS: castbar expanded bounds, integer rounding, defaults, Player/Target save and read")
