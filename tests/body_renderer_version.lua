-- Exercise the Body gate against the real release requirement, not a stale mock.
VanityStudio={}
VanityStudioCharacter={enabled=true}
dofile("addon/SaureksCloset/Updates.lua")
dofile("addon/SaureksCloset/Body.lua")
local V=VanityStudio
local version=V.REQUIRED_RENDERER
SaureksClosetRendererVersion=function() return version end
SaureksClosetSetAppearance=function() return 1 end
SaureksClosetClearAppearance=function() return 1 end
SaureksClosetRealBody=function() return 1,0,2,3,4,5,6 end
VanityStudioRaces={[1]={"Human"}}
function V:Copy(source) local result={};for k,v in pairs(source) do result[k]=v end;return result end
assert(V:BodyAvailable(),"The current release DLL must enable the Body page")
local body=V:NativeBody()
assert(body and body.race==1 and body.skin==2 and body.facial==6,"Current DLL must supply Body page values")
assert(V:BodyDraft().hairColor==5,"Unmodified characters must populate the Body controls")
for _,old in ipairs({30001,30400,30515,30711,30712,30713,30800,30901,40001}) do
    version=old;assert(V:BodyAvailable(),"Previously audited renderers stay compatible")
end
for _,unsupported in ipairs({0,30701,30607,V.REQUIRED_RENDERER+1,"30901",false}) do
    version=unsupported;assert(not V:BodyAvailable(),"Unknown or malformed versions must stay rejected")
end
version=V.REQUIRED_RENDERER
for _,name in ipairs({"SaureksClosetSetAppearance","SaureksClosetClearAppearance","SaureksClosetRealBody"}) do
    local original=_G[name];_G[name]=nil
    assert(not V:BodyAvailable(),"Matching version cannot replace a missing native API")
    _G[name]=original
end
SaureksClosetRendererVersion=function() error("Unavailable") end
assert(not V:BodyAvailable(),"Native errors must disable safely")
SaureksClosetRendererVersion=function() return nil end
local required=V.REQUIRED_RENDERER;V.REQUIRED_RENDERER=nil
assert(not V:BodyAvailable(),"Missing version and requirement must not compare as compatible")
V.REQUIRED_RENDERER=required
print("PASS: current release Body availability and real-body controls; historical, unsupported and missing-API cases")
