local now,starts,enabled,remote=0,0,false,{1}
math.mod=math.mod or math.fmod
table.getn=table.getn or function(value) return #value end
unpack=unpack or table.unpack
local messages={}
GetTime=function() return now end
time=function() return 1700000000+math.floor(now) end
date=function(_,value) return "Test date "..value end
VanityStudioDB={}
VanityStudio={VERSION="3.6.8",Message=function(self,value) table.insert(messages,value) end}
SaureksClosetRendererVersion=function() return VanityStudio.REQUIRED_RENDERER end
SaureksClosetSetUpdateChecks=function(value) enabled=value==1;return 1 end
SaureksClosetStartUpdateCheck=function() assert(enabled);starts=starts+1;return 1 end
SaureksClosetPollUpdateCheck=function() return unpack(remote) end
local title={SetText=function(self,value) self.text=value end,SetFont=function() end}
VanityStudio.frame={title=title}
VanityStudio.updatesSummary={SetText=function(self,value) self.text=value end}
VanityStudio.updatesStatus={SetText=function(self,value) self.text=value end}
VanityStudio.addonVersionsHeading={SetText=function(self,value) self.text=value end}
VanityStudio.lastVersionCheckLabel={SetText=function(self,value) self.text=value end}
local function statusLabel()
    return {SetText=function(self,value) self.text=value end}
end
VanityStudio.versionStatusLabels={statusLabel(),statusLabel(),statusLabel()}
VanityStudio.availableVersionLabels={statusLabel(),statusLabel()}
local function statusIcon()
    return {Show=function(self) self.shown=true end,SetTexture=function(self,value) self.texture=value end}
end
VanityStudio.versionStatusIcons={statusIcon(),statusIcon(),statusIcon()}
dofile("addon/SaureksCloset/Updates.lua")
local V=VanityStudio
local function iconCount(path)
    local count=0;for _,icon in ipairs(V.versionStatusIcons) do if icon.texture==path then count=count+1 end end
    return count
end
V:InitializeUpdates()
assert(VanityStudioDB.autoCheckUpdates==true and enabled and starts==0)
assert(not V.updateMismatch and table.getn(messages)==0)
assert(V.addonVersionsHeading.text=="This PC's Version")
assert(V.lastVersionCheckLabel.text=="Last checked: Never")
for _,line in ipairs(V.versionStatusLabels) do assert(not string.find(line.text,"|T",1,true),"1.12 FontStrings must not receive inline texture markup") end
assert(iconCount("Interface\\Buttons\\UI-CheckBox-Check")==3,"all three matching local version lines need golden checks")
assert(iconCount("Interface\\Buttons\\UI-GroupLoot-Pass-Up")==0)
now=3;V:UpdateUpdates();assert(starts==1 and V.updatePolling)
remote={2,3,6,8,V.REQUIRED_RENDERER+1,0};now=3.3;V:UpdateUpdates()
assert(V.remoteUpdateAvailable and title.text=="Saurek's Closet (Outdated)")
assert(V.addonVersionsHeading.text=="This PC's Version (Out of date)")
assert(VanityStudioDB.lastVersionCheck==1700000003 and V.lastVersionCheckLabel.text=="Last checked: Test date 1700000003")
assert(iconCount("Interface\\Buttons\\UI-CheckBox-Check")==1 and iconCount("Interface\\Buttons\\UI-GroupLoot-Pass-Up")==2)
assert(V.availableVersionLabels[1].text=="Addon: 3.6.8")
assert(V.availableVersionLabels[2].text=="DLL: "..V:RendererVersionText(V.REQUIRED_RENDERER+1))
assert(table.getn(messages)==1)
V:CheckForUpdates(true);now=4;V:UpdateUpdates();assert(table.getn(messages)==1)
V:CheckForUpdates(true);local before=starts
V:SetAutoUpdates(false);remote={2,9,9,9,90909,0};now=50;V:UpdateUpdates()
assert(not enabled and not V.updatePolling and starts==before and V.remoteRelease.addon=="3.6.8")
assert(V.availableVersionLabels[1].text=="Addon: Unknown")
assert(V.availableVersionLabels[2].text=="DLL: Unknown")
assert(V:CheckForUpdates(true)==false and starts==before)
V:InitializeUpdates();now=100;V:UpdateUpdates();assert(not enabled and starts==before)
-- Local mismatch detection stays enabled even when networking is disabled.
SaureksClosetRendererVersion=function() return V.REQUIRED_RENDERER-1 end
V:CheckLocalRenderer();assert(V.updateMismatch and table.getn(messages)==2)
assert(iconCount("Interface\\Buttons\\UI-GroupLoot-Pass-Up")>=1)
V:CheckLocalRenderer();assert(table.getn(messages)==2)
SaureksClosetRendererVersion=nil;V:CheckLocalRenderer();assert(V.updateMismatch and table.getn(messages)==3)
SaureksClosetRendererVersion=function() return V.REQUIRED_RENDERER end
V:CheckLocalRenderer();assert(not V.updateMismatch)
V:SetAutoUpdates(true);now=104;remote={2,3,4,15,30400,0};V:UpdateUpdates()
assert(not V.remoteUpdateAvailable and title.text=="Saurek's Closet")
assert(V.addonVersionsHeading.text=="This PC's Version" and V.updatesStatus.text=="")
assert(V:VersionIsNewer("3.4.10","3.4.9"))
assert(V:VersionIsNewer("3.4.100","3.4.99") and not V:VersionIsNewer("3.4.100","3.5.0"))
V:CheckForUpdates(true);remote={-1,0,0,0,0,12007};now=105;V:UpdateUpdates()
assert(string.find(V.updateStatus,"Could not",1,true) and table.getn(messages)==3)
V:CheckForUpdates(true);remote={2,3,4,"invalid",30433,0};now=106;V:UpdateUpdates()
assert(string.find(V.updateStatus,"Could not",1,true))
V:CheckForUpdates(true);remote={1};now=137;V:UpdateUpdates()
assert(not V.updatePolling and enabled and string.find(V.updateStatus,"timed out",1,true))
local opened={}
local expectedURLs={"https://github.com/mu-arch/SaureksCloset","https://github.com/mu-arch/SaureksCloset/releases","https://discord.gg/6mfxCdNbM6",
    "https://ko-fi.com/comfysystems","https://cash.app/$saurek"}
V.websiteAddress=statusLabel()
SaureksClosetOpenWebsite=function(page) table.insert(opened,page);return 1 end
for page,url in ipairs(expectedURLs) do
    assert(V.websiteURLs[page]==url,"Website mapping changed unexpectedly")
    assert(V:OpenWebsite(page) and opened[page]==page and V.websiteAddress.text==url,"Explicit website action must retain the requested destination")
end
for _,page in ipairs({0,-1,6,9,4.5,"4","https://example.com",false,{}}) do
    assert(not V:OpenWebsite(page),"Arbitrary website inputs must be rejected")
end
assert(not V:OpenWebsite(nil) and table.getn(opened)==5,"Invalid IDs never reach the native browser opener")
for page,url in ipairs(expectedURLs) do
    SaureksClosetOpenWebsite=nil
    assert(not V:OpenWebsite(page) and V.websiteAddress.text==url and messages[table.getn(messages)]=="Open this address in your browser: "..url,"Missing DLL provides the exact copyable address")
    SaureksClosetOpenWebsite=function() return 0 end
    assert(not V:OpenWebsite(page) and V.websiteAddress.text==url,"Native failure preserves the selected address")
    SaureksClosetOpenWebsite=function() error("Browser unavailable") end
    assert(not V:OpenWebsite(page) and V.websiteAddress.text==url,"Native errors are contained and preserve the address")
end
print("PASS: default-on/persisted-off checks, cancellation, mismatch/missing DLL alerts, numeric versions, deduplication, errors, timeout and website actions")

assert(V:VersionIsNewer("3.6.8","3.6.7"))
assert(not V:VersionIsNewer("3.6.7","3.6.8"))
assert(not V:VersionIsNewer("3.6.8","3.6.8"))
assert(V:RendererVersionText(30608)=="3.6.8")
