-- Exercise minimap controls and refresh preservation with the real look/tuner code.
table.getn=table.getn or function(t) return #t end
math.mod=math.mod or math.fmod
VanityStudio={}
VanityStudioDB={minimapAngle=225}
VanityStudioCharacter={enabled=true}
local frames={}
local methods={}
local function frame(name,parent)
    local result=setmetatable({name=name,parent=parent,scripts={}}, {__index=methods})
    if name then frames[name]=result end
    return result
end
function CreateFrame(kind,name,parent) return frame(name,parent) end
function methods:CreateTexture() return frame(nil,self) end
function methods:SetScript(event,callback) self.scripts[event]=callback end
function methods:RegisterForClicks(...) self.clicks={...} end
function methods:RegisterForDrag(...) self.drags={...} end
function methods:GetName() return self.name end
function methods:GetParent() return self.parent end
function methods:SetPoint(...) self.point={...} end
function methods:GetCenter() return 100,100 end
function methods:GetEffectiveScale() return 1 end
function methods:Hide() self.hidden=true end
function methods:GetText() return self.text or "" end
function methods:SetText(text) self.text=text end
function methods:ClearFocus() self.focused=false end
for _,key in ipairs({"RegisterEvent","SetWidth","SetHeight","SetFrameStrata","SetHighlightTexture","SetTexture","ClearAllPoints"}) do
    methods[key]=function() end
end
Minimap=frame("Minimap")
GameTooltip={lines={}}
function GameTooltip:SetOwner(owner) self.owner=owner end
function GameTooltip:SetText(text) self.title=text;self.lines={} end
function GameTooltip:AddLine(text) table.insert(self.lines,text) end
function GameTooltip:Show() self.shown=true end
function GameTooltip:Hide() self.shown=false end
local menuEntries={}
function UIDropDownMenu_AddButton(info) table.insert(menuEntries,info) end
local menuOpens=0
function ToggleDropDownMenu(level,value,menu,anchor,x,y)
    assert(level==1 and value==nil and x==0 and y==0)
    assert(anchor==VanityStudio.launcher:GetName())
    menuOpens=menuOpens+1;menuEntries={};menu.initialize()
end
SlashCmdList={}
dofile("addon/SaureksCloset/Core.lua")
dofile("addon/SaureksCloset/BagCatalog.lua")
dofile("addon/SaureksCloset/Bags.lua")
dofile("addon/SaureksCloset/BagTuner.lua")
dofile("addon/SaureksCloset/Preview.lua")
dofile("addon/SaureksCloset/UI.lua")
dofile("addon/SaureksCloset/BagTunerUI.lua")
local V=VanityStudio
local wardrobeOpens,toggles=0,0
function V:Toggle() wardrobeOpens=wardrobeOpens+1 end
function V:SetEnabled(value) toggles=toggles+1;VanityStudioCharacter.enabled=value end
local checks=0
local function check(value,message) assert(value,message);checks=checks+1 end
local function event(widget,name,argument)
    local oldThis,oldArg=this,arg1;this=widget;arg1=argument
    widget.scripts[name]()
    this=oldThis;arg1=oldArg
end
V:CreateLauncher()
local button=V.launcher
check(button.clicks[1]=="LeftButtonUp" and button.clicks[2]=="RightButtonUp","Both click actions are registered")
check(button.drags[1]=="LeftButton","Minimap dragging still uses the left button")
check(V.launcherMenu.hidden and V.launcherMenu.displayMode=="MENU","Options use the native dropdown menu")
check(not V.frame,"Minimap options work before the wardrobe has been created")
event(button,"OnEnter")
check(GameTooltip.shown and GameTooltip.lines[2]=="Right-click: addon options","Hover discovers the right-click options")
event(button,"OnClick","RightButton")
check(menuOpens==1 and not GameTooltip.shown,"Right-click opens options and dismisses the launcher tooltip")
check(toggles==0 and wardrobeOpens==0,"Opening options does not alter appearances or open the wardrobe")
check(table.getn(menuEntries)==2 and menuEntries[1].text=="Toggle Addon","Options retain Toggle Addon")
check(menuEntries[2].text=="Refresh Addon" and not menuEntries[2].checked and not menuEntries[2].keepShownOnClick,"Refresh Addon is an unchecked action that closes after use")
check(not menuEntries[1].notCheckable and not menuEntries[2].notCheckable,"Both labels reserve the same native check gutter and align horizontally")
check(string.find(menuEntries[2].tooltipText,"Reload the interface",1,true),"Refresh explains that it reloads the interface")
check(menuEntries[1].checked==1,"A check indicates the addon is currently enabled")
check(menuEntries[1].tooltipText=="Turn your local cosmetic appearances on or off.","Option describes its effect")
menuEntries[1].func()
check(toggles==1 and VanityStudioCharacter.enabled==false,"Selecting the option disables through SetEnabled")
event(button,"OnClick","RightButton")
check(menuEntries[1].checked==nil,"Reopening reflects the latest disabled state")
menuEntries[1].func()
check(toggles==2 and VanityStudioCharacter.enabled==true,"Selecting again enables appearances")
event(button,"OnClick","LeftButton")
check(wardrobeOpens==1 and menuOpens==2 and toggles==2,"Left-click still opens the wardrobe without toggling appearances")
event(button,"OnDragStart")
check(button.dragging==true,"Dragging still starts")
function GetCursorPosition() return 180,100 end
event(button,"OnUpdate")
check(VanityStudioDB.minimapAngle==0 and button.point[4]==80,"Dragging updates the saved minimap angle and launcher position")
event(button,"OnDragStop")
check(button.dragging==nil,"Dragging stops cleanly")
V:CreateLauncher()
check(V.launcher==button and V.launcherMenu==frames.SaureksClosetMinimapMenu,"Repeated setup preserves the launcher and options menu")

-- Render only the data side here: the real save preparation, draft commit,
-- bag fitting and text validation run, while WoW's reload is captured.
local function noop() end
V.Refresh=noop;V.Sync=noop;V.SyncBagTuning=noop;V.RefreshBagTunerUI=noop
V.Message=function(self,message) self.lastMessage=message end
V.NativeBody=function() return {race=1,sex=0} end
V.IsWeaponPosition=function(self,slot) return slot>=101 and slot<=110 end
V.WeaponChoiceCompatible=function() return false end
V.index[10500]={10500,"Goggles",1};V.index[10501]={10501,"Helmet",1}
SaureksClosetRendererVersion=function() return 30805 end
SaureksClosetSetBagFit=function() return 1 end
SaureksClosetSetBags=function() return 1 end
SaureksClosetSetBagInstanceFit=function() return 1 end
SaureksClosetGetBagFitDefaults=function() return 1,0,0,0,0,0,0,85 end
VanityStudioRaces={{"Human"}}
local function same(a,b)
    if type(a)~=type(b) then return false end
    if type(a)~="table" then return a==b end
    for key,value in pairs(a) do if not same(value,b[key]) then return false end end
    for key in pairs(b) do if a[key]==nil then return false end end
    return true
end
local function resetRefresh()
    VanityStudioDB={outfits={}}
    VanityStudioCharacter={enabled=true,selected={[1]=10500},managed={},weapons={bags={{id=1,model=1,mount="back",fits={}}}},activeOutfit="Traveler"}
    VanityStudioDB.outfits.Traveler=V:CurrentLook()
    V.bagTunerWindow=nil;V.bagTunerDrafts={};V.bagTunerDefaults={};V.draft=nil;V.placementTunerBag=1;V.placementTunerSlot=nil
    V.lastMessage=nil;V.applied={};V.pending={};V.errors={}
    return VanityStudioCharacter,VanityStudioCharacter.weapons.bags[1],V:Copy(VanityStudioDB.outfits)
end
local reloads,snapshot=0,nil
local function reload()
    reloads=reloads+1;snapshot={character=V:Copy(VanityStudioCharacter),outfits=V:Copy(VanityStudioDB.outfits)}
end
local c,bag,saved=resetRefresh()
check(not V:RefreshAddon() and reloads==0 and V.lastMessage=="The interface refresh is unavailable.","Missing reload support fails without changing the look")
ReloadUI=reload
menuEntries[2].func()
check(reloads==1 and c.activeOutfit=="Traveler" and not c.activeUnsaved,"Refreshing an unchanged look keeps it active and clean")
check(same(snapshot.outfits,saved),"Refresh never overwrites a named saved look")

c,bag,saved=resetRefresh()
V.draft={slot=1,id=10501}
local state=V:GetBagTunerState()
V.bagTunerDrafts[state.key].left=.25
local editor=frame(nil);editor.field=V.bagTunerFields[3];editor.text="0.42";editor.editing=true;editor.targetKey=state.key;editor.focused=true
V.bagTunerWindow={rows={{editor=editor}}}
check(V:RefreshAddon() and reloads==2,"Refresh accepts a valid unfinished fit value before reloading")
check(not editor.editing and not editor.focused and not V.draft,"Pending fit input and appearance preview are committed before reload")
check(snapshot.character.selected[1]==10501 and snapshot.character.weapons.bags[1].fits["1:0"].left==.25 and snapshot.character.weapons.bags[1].fits["1:0"].up==.42,"Reload captures the current item preview and latest bag fit")
check(snapshot.character.activeUnsaved and snapshot.character.unsaved.baseName=="Traveler" and not snapshot.character.activeOutfit,"Refresh preserves changes as an edited character look")
check(snapshot.character.unsaved.slots[1]==10501 and snapshot.character.unsaved.weapons.bags[1].fits["1:0"].up==.42,"The unsaved snapshot includes the latest values")
check(same(snapshot.outfits,saved),"The saved Traveler remains unchanged after retaining edits")

c,bag,saved=resetRefresh();c.enabled=false
V.draft={slot=1,id=10501}
check(V:RefreshAddon() and snapshot.character.enabled==false,"Refresh retains a disabled addon without enabling it")

c,bag,saved=resetRefresh()
V.draft={slot=1,id=10501};state=V:GetBagTunerState()
editor=frame(nil);editor.field=V.bagTunerFields[3];editor.text="invalid";editor.editing=true;editor.targetKey=state.key
V.bagTunerWindow={rows={{editor=editor}}}
local before=reloads
check(not V:RefreshAddon() and reloads==before and V.lastMessage=="Enter a number for Vertical shift.","Invalid unfinished text blocks refresh with the validation message")
check(V.draft and c.selected[1]==10500 and not next(bag.fits) and same(VanityStudioDB.outfits,saved),"Rejected text leaves the current look, pending preview and saved looks intact")
check(not V:RefreshAddon() and reloads==before,"A value rejected on prior focus loss still blocks refresh")
editor.text="0.5";editor.editing=true
check(V:RefreshAddon() and reloads==before+1 and snapshot.character.weapons.bags[1].fits["1:0"].up==.5,"Correcting the rejected field permits refresh and preserves its value")

c,bag,saved=resetRefresh();V.draft={slot=108,id=12345};before=reloads
check(not V:RefreshAddon() and reloads==before and V.draft~=nil,"An incompatible equipment preview blocks refresh instead of losing the draft")
check(same(VanityStudioDB.outfits,saved),"A failed preview commit cannot replace saved looks")

c,bag=resetRefresh();c.activeOutfit=nil;VanityStudioDB.outfits={};V.draft={slot=1,id=10501}
check(V:RefreshAddon() and snapshot.character.activeUnsaved and not snapshot.character.unsaved.baseName and snapshot.character.unsaved.slots[1]==10501,"A first unsaved appearance survives refresh without inventing a saved name")
check(not next(snapshot.outfits),"Refreshing a new appearance does not create a named saved look")
-- The 1.12 click handler only toggles a check for keepShownOnClick entries.
-- Exercise that real handler to ensure retaining the gutter adds no toggle.
local nativeFile=assert(io.open("research/client-data/UIDropDownMenu.lua","r"))
local nativeSource=nativeFile:read("*a");nativeFile:close()
local clickStart=assert(string.find(nativeSource,"function UIDropDownMenuButton_OnClick()",1,true))
local clickEnd=assert(string.find(nativeSource,"function HideDropDownMenu",clickStart,true))
assert(loadstring(string.sub(nativeSource,clickStart,clickEnd-1)))()
PlaySound=function() end
local nativeMenu=frame(nil)
local nativeButton=frame("RefreshAddonNativeMenuButton",nativeMenu)
for key,value in pairs(menuEntries[2]) do nativeButton[key]=value end
before=reloads
local oldThis=this;this=nativeButton;UIDropDownMenuButton_OnClick();this=oldThis
check(reloads==before+1 and nativeMenu.hidden and not nativeButton.checked,"Native click refreshes, closes the menu and never checks the action")
event(button,"OnClick","RightButton")
check(not menuEntries[2].checked and not menuEntries[2].notCheckable,"Reopening keeps Refresh Addon unchecked and aligned")
print(checks.." minimap toggle and refresh checks passed")
