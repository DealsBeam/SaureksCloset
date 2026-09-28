-- Exercise the actual saved-look, bag instance, tuner and native dispatch paths.
table.getn=table.getn or function(t) return #t end
unpack=unpack or table.unpack
local function noop() end
function CreateFrame() return {RegisterEvent=noop,SetScript=noop} end
SlashCmdList={}
SaureksClosetWeaponAssets={};SaureksClosetQuivers={}
local version,fail=30800,false
function SaureksClosetRendererVersion() return version end
function GetInventoryItemLink(unit) assert(unit=="player");return nil end
function SetInventoryItem() error("Cosmetic bags must never change inventory") end
function EquipItemByName() error("Cosmetic bags must never equip real items") end
function time() return 12345 end
function date() return "2026-09-26" end
local contexts,weaponCalls,generations={},{},{}
local nextGeneration,fitCalls=0,0
local invalidPreview={}
function SaureksClosetPreviewStatus(token) return invalidPreview[token] and -1 or 1 end
function SaureksClosetSetWeapons(...)
    local args={...};assert(args[16]==0,"Multi-bags must not also create the legacy bag")
    weaponCalls[args[1]]=args;return 1
end
function SaureksClosetSetBags(token,...)
    local args={...};assert(table.getn(args)==16)
    if fail then return -1 end
    if not contexts[token] then contexts[token]={};nextGeneration=nextGeneration+1;generations[token]=nextGeneration end
    local c=contexts[token]
    for id=1,8 do
        local model,mount=args[id*2-1],args[id*2]
        assert(model>=0 and model<=16 and mount>=0 and mount<=2)
        if model==0 then
            if c[id] then c[id]=nil;nextGeneration=nextGeneration+1;generations[token]=nextGeneration end
        elseif not c[id] or c[id].model~=model or c[id].mount~=mount then
            c[id]={model=model,mount=mount,fits={}};nextGeneration=nextGeneration+1;generations[token]=nextGeneration
        end
    end
    return 1,generations[token]
end
function SaureksClosetSetBagInstanceFit(token,id,race,sex,enabled,left,inset,up,pitch,roll,yaw,scale,motion)
    fitCalls=fitCalls+1
    if fail then return -1 end
    local bag=assert(contexts[token][id]);local key=race..":"..sex
    bag.fits[key]=enabled==1 and {left=left,inset=inset,up=up,pitch=pitch,roll=roll,yaw=yaw,scale=scale,motion=motion} or nil
    return 1
end
function SaureksClosetSetBagFit() return 1 end
function SaureksClosetGetBagFitDefaults(target,race,sex,mount)
    assert(target==1 or (target>=101 and target<=107) or (target>=201 and target<=208))
    if target==1 then return 1,.126,0,-.06,0,0,0,85 end
    return 1,0,0,mount~=0 and -.15 or 0,0,0,(mount==1 and -90 or (mount==2 and 90 or 0)),target<=107 and 100 or (mount~=0 and 70 or 85)
end
dofile("addon/SaureksCloset/Core.lua")
dofile("addon/SaureksCloset/BagCatalog.lua")
dofile("addon/SaureksCloset/Weaponry.lua")
dofile("addon/SaureksCloset/Bags.lua")
dofile("addon/SaureksCloset/BagTuner.lua")
local V=VanityStudio
VanityStudioRaces={};for race=1,8 do VanityStudioRaces[race]={"Race "..race} end
VanityStudioDB={outfits={}}
VanityStudioCharacter={enabled=true,selected={},weapons={}}
for _,name in ipairs({"Refresh","InvalidatePreviewModel","RefreshPortraits"}) do V[name]=noop end
function V:CancelDraft() self.draft=nil end
function V:NativeBody() return {race=1,sex=0} end
function V:BodyAvailable() return true end
function V:SyncBody() return true end
function V:NormalizeBody(body) return self:Copy(body) end
function V:Sync() self:SyncWeapons() end
V:InitializeBagTuning()
local c=VanityStudioCharacter
-- Legacy fit and default migration preserves old looks without aliasing them.
local legacy={backBag=1}
local oldFit={left=.2,inset=.1,up=.15,pitch=10,roll=4,yaw=8,scale=90}
V:BagTunerStore().fits["1:1:0"]={schema=1,bag=1,race=1,sex=0,values=oldFit}
local migrated=V:NormalizeWeapons(legacy)
assert(not migrated.backBag and migrated.bags[1].slot==1 and migrated.bags[1].model==1 and migrated.bags[1].fits["1:0"].left==.2)
assert(migrated.bags[1].fits["2:0"].left==.126 and legacy.backBag==1 and not legacy.bags)
migrated.bags[1].fits["1:0"].left=.3;assert(oldFit.left==.2)
assert(table.getn(V:NormalizeBags({backBag=1,bags={}}))==0,"Explicit empty list must not resurrect old bags")
-- Retired bags disappear; the old olive pouch becomes Low without moving it.
local retiredWeapons={bags={}}
for id,model in ipairs({3,4,6,9,15,7,8}) do
    table.insert(retiredWeapons.bags,{id=id,model=model,mount="leftHip",fits={["1:0"]=V:Copy(oldFit)}})
end
local current=V:NormalizeBags(retiredWeapons)
assert(table.getn(current)==3 and current[1].id==5 and current[1].model==16 and current[1].mount=="leftHip")
assert(current[2].model==7 and current[3].model==8,"Smooth leather variants remain available")
assert(current[1].fits["1:0"].up==.15)
current[1].fits["1:0"].up=.7;assert(retiredWeapons.bags[5].fits["1:0"].up==.15)
assert(table.getn(retiredWeapons.bags)==7 and retiredWeapons.bags[5].model==15,"Normalization must not rewrite saved looks")
VanityStudioDB.outfits["Retired models"]={version=2,slots={},weapons=retiredWeapons}
assert(V:ApplyWeaponRenderer(95,retiredWeapons))
assert(not contexts[95][1] and not contexts[95][2] and not contexts[95][3] and not contexts[95][4])
assert(contexts[95][5].model==16 and contexts[95][5].fits["1:0"].up==.15)
c.weapons=V:Copy(retiredWeapons);V:InitializeWeapons()
assert(table.getn(V:GetBags())==3 and V:BagInstance(5).model==16,"Startup must retire existing character selections")
assert(V:LoadOutfit("Retired models",true) and contexts[0][5].model==16)
assert(VanityStudioDB.outfits["Retired models"].weapons.bags[5].model==15)
assert(V:SaveOutfit("Retired models",true))
assert(table.getn(VanityStudioDB.outfits["Retired models"].weapons.bags)==3)
assert(VanityStudioDB.outfits["Retired models"].weapons.bags[1].model==16)
V:ClearAll()
-- All catalog entries are selectable; capacity and independent IDs are enforced.
assert(table.getn(V.bagCatalog)==11)
assert(table.getn(V.bagModelChoices)==6)
local pouch=V:BagModelChoice(16)
assert(pouch.name=="Mageweave Bag" and pouch.id==16 and table.getn(pouch.colors)==4)
for i,id in ipairs({12,13,14,16}) do
    local color=V:BagModelColor(id)
    assert(V:BagModelChoice(id)==pouch and color==pouch.colors[i] and color.id==id)
    assert(color.name==({"Burgundy","Navy","Ochre","Olive"})[i])
end
local leather=V:BagModelChoice(5)
assert(leather.name=="Slim Leather Bag" and leather.id==5 and table.getn(leather.colors)==3)
for i,id in ipairs({5,7,8}) do
    local color=V:BagModelColor(id)
    assert(V:BagModelChoice(id)==leather and color==leather.colors[i] and color.id==id)
    assert(color.name==({"Brown","Dark Brown","Tan"})[i])
end
assert(not V:BagModelColor(1) and V:BagModelChoice(1)==V.bagCatalogByID[1])
assert(not V:BagModelChoice(15) and not V:BagModelColor(999))
for _,asset in ipairs(V.bagCatalog) do
    assert(V:AddBag(asset.id,"back"));assert(V:GetBags()[1].model==asset.id);assert(V:DeleteBag(1))
end
for _,model in ipairs({3,4,6,9,15}) do assert(not V.bagCatalogByID[model] and not V:AddBag(model,"back")) end
for id=1,5 do assert(V:AddBag(V.bagCatalog[id].id,id==2 and "leftHip" or (id==3 and "rightHip" or "back"))) end
assert(not V:AddBag(16,"back") and table.getn(V:GetBags())==5)
for _,model in ipairs({3,4,6,9,15}) do assert(not V:SetBagModel(1,model)) end
assert(contexts[0][2].mount==1 and contexts[0][3].mount==2)
assert(not V:SetBagModel(1,999) and not V:SetBagMount(1,"head"))
assert(not V:DeleteBag(9) and not V:AddBag(0/0,"back"))
local before=V:BagSignature(c.weapons)
assert(V:DeleteBag(3));assert(V:GetBags()[3].id==4 and contexts[0][3]==nil and contexts[0][4].model==7)
local ok,new=V:AddBag(2,"rightHip");assert(ok and new.id==3 and contexts[0][3].model==2)
assert(V:BagSignature(c.weapons)~=before)
-- Duplicate models have separate tuner drafts, saves, body profiles and mounts.
V:InitializeBagTuning();V.placementTunerBag=2
local state=V:GetBagTunerState();assert(state.bag==202 and state.values.yaw==-90)
assert(V:SetBagTunerValue("up",.23));assert(contexts[0][2].fits["1:0"].up==.23)
assert(not contexts[0][3].fits["1:0"] and not next(V:BagInstance(2).fits))
assert(V:SaveBagTunerFit());assert(V:BagInstance(2).fits["1:0"].up==.23)
assert(c.unsaved.weapons.bags[2].fits["1:0"].up==.23)
assert(not V:BagTunerStore().fits["202:1:0"],"Instance fits must not be account-global")
assert(V:SaveOutfit("Five bags"))
assert(V:SetBagTunerValue("up",.41));assert(V:BagInstance(2).fits["1:0"].up==.23)
assert(V:SetBagTunerPaused(true));assert(contexts[0][2].fits["1:0"].motion==0)
-- In-window appearance changes retain every race/gender draft and the paused
-- target. Switching back cannot resurrect a stale draft from the old model.
local oldModel=V:BagInstance(2).model
local oldKey=V:GetBagTunerState().key
c.body={race=2,sex=1};assert(V:SetBagTunerValue("left",.19));c.body=nil
assert(V:GetBagTunerState().key==oldKey)
local shown=true
V.bagTunerWindow={IsShown=function() return shown end,Hide=function() shown=false end}
assert(V:SetBagModel(2,16,true))
assert(shown and V.placementTunerBag==2 and V.bagTunerPaused)
assert(V:BagInstance(2).fits["1:0"].up==.23 and V:GetBagTunerState().values.up==.41)
assert(not V.bagTunerDrafts[oldKey] and contexts[0][2].model==16 and contexts[0][2].fits["1:0"].motion==0)
local variants={}
for _,group in ipairs({pouch,leather}) do for _,color in ipairs(group.colors) do table.insert(variants,color) end end
for _,color in ipairs(variants) do
    assert(V:SetBagModel(2,color.id,true))
    assert(V:GetBagTunerState().values.up==.41 and V:BagInstance(2).fits["1:0"].up==.23)
    assert(V:BagInstance(2).mount=="leftHip" and V.placementTunerBag==2 and V.bagTunerPaused)
    assert(contexts[0][2].model==color.id and V:BagModelColor(color.id).name==color.name)
end
c.body={race=2,sex=1};assert(V:GetBagTunerState().values.left==.19);c.body=nil
assert(V:SetBagTunerValue("up",.43));assert(V:SetBagModel(2,oldModel,true))
assert(V:GetBagTunerState().values.up==.43 and V:BagInstance(2).fits["1:0"].up==.23)
assert(V:SetBagTunerValue("up",.41));V.bagTunerWindow=nil
V.placementTunerBag=3;assert(V:GetBagTunerState().values.yaw==90)
assert(contexts[0][2].fits["1:0"].motion==1)
assert(V:SetBagTunerValue("up",-.2));assert(V:SaveBagTunerFit())
assert(V:BagInstance(2).fits["1:0"].up==.23 and V:BagInstance(3).fits["1:0"].up==-.2)
c.body={race=2,sex=1};assert(V:GetBagTunerState().race==2)
assert(V:SetBagTunerValue("yaw",45));assert(V:SaveBagTunerFit())
assert(V:BagInstance(3).fits["2:1"].yaw==45 and V:BagInstance(3).fits["1:0"].yaw==90)
c.body=nil
-- Saved look preview has saved values even while world/main preview use drafts.
V.model={weaponToken=7};V.previewBuffer={weaponToken=8};V.tab="outfit"
V.placementTunerBag=2;assert(V:SetBagTunerValue("up",.51))
assert(contexts[7][2].fits["1:0"].up==.51 and contexts[8][2].fits["1:0"].up==.51)
assert(V:ApplyWeaponRenderer(99,VanityStudioDB.outfits["Five bags"].weapons))
assert(contexts[99][2].fits["1:0"].up==.23 and contexts[0][2].fits["1:0"].up==.51)
local beforeCalls=fitCalls;V:SyncBagTuning();V:SyncWeapons()
assert(fitCalls==beforeCalls,"Unchanged fits should not be resent on periodic sync")
invalidPreview[8]=true;V:SyncBagTuning();assert(not V.bagTunerError)
invalidPreview[8]=nil
-- Rebuilt contexts must receive every fit despite unchanged Lua selections.
for _,bag in pairs(contexts[0]) do bag.fits={} end
nextGeneration=nextGeneration+1;generations[0]=nextGeneration
V:SyncBagTuning();assert(contexts[0][2].fits["1:0"].up==.51 and fitCalls>beforeCalls)
V.tab="body";V:SyncBagTuning();assert(not next(contexts[7]) and not next(contexts[8]) and contexts[0][2])
V.tab="outfit";assert(V:ApplyWeaponRenderer(7,c.weapons));assert(contexts[7][2].fits["1:0"].up==.51)
-- Loading a look drops previous drafts, including same-ID/model/mount collisions.
assert(V:LoadOutfit("Five bags"));assert(contexts[0][2].fits["1:0"].up==.23)
assert(not contexts[0][3].fits["1:0"] and not V.placementTunerBag)
V.placementTunerBag=2;V:GetBagTunerState();assert(V:SetBagMount(2,"rightHip"))
assert(not next(V:BagInstance(2).fits) and not V.placementTunerBag)
V.placementTunerBag=2;assert(V:GetBagTunerState().values.yaw==90)
assert(V:SetBagTunerPaused(true));assert(V:SetBagTunerValue("up",.31))
assert(V:SaveBagTunerFit());assert(V:SetBagMount(2,"leftHip",true))
assert(V.placementTunerBag==2 and V.bagTunerPaused and not next(V:BagInstance(2).fits))
assert(V:GetBagTunerState().values.up==-.15 and V:GetBagTunerState().values.yaw==-90)
assert(contexts[0][2].fits["1:0"].motion==0,"Mount changes preserve pause while resetting the fit")
assert(V:SetBagMount(2,"rightHip",true));V:SetBagTunerPaused(false)
assert(V:SetBagTunerValue("scale",115));assert(V:DeleteBag(2));assert(V:AddBag(2,"rightHip"))
V.placementTunerBag=2;assert(V:GetBagTunerState().values.scale==70,"Reused ID must not inherit a deleted bag's draft")
-- Renderer errors retain user values and retry; switching off retains the look.
fail=true;assert(V:SetBagTunerValue("roll",17));assert(V.bagTunerError)
fail=false;V:SyncBagTuning();assert(not V.bagTunerError and contexts[0][2].fits["1:0"].roll==17)
V:SetEnabled(false);assert(not next(contexts[0]) and table.getn(c.weapons.bags)==5)
V:SetEnabled(true);assert(contexts[0][2])
V:SetBagTunerEnabled(false);assert(not next(contexts[0][2].fits))
V:SetBagTunerEnabled(true);assert(contexts[0][2].fits["1:0"].roll==17)
assert(not V:SetBagTunerValue("scale",0/0) and not V:SetBagTunerValue("yaw",181))
local saved=V:Copy(c.weapons);version=30713
assert(not V:AddBag(1,"back") and not V:LoadOutfit("Five bags"))
assert(V:BagSignature(c.weapons)==V:BagSignature(saved));version=30800
V:ClearAll();assert(not next(contexts[0]) and table.getn(V:GetBags())==0)
-- The five visible positions are independent of native IDs and insertion order.
for _,slot in ipairs({0,6,1.5,"4",false,0/0}) do assert(not V:AddBag(2,"back",slot)) end
local addedFourth,fourth=V:AddBag(2,"back",4)
assert(addedFourth and fourth.id==1 and fourth.slot==4 and V:BagInSlot(4)==fourth)
assert(not V:BagInSlot(1) and not V:BagInSlot(0) and not V:BagInSlot(6) and not V:BagInSlot(0/0))
assert(not V:AddBag(7,"back",4) and table.getn(V:GetBags())==1,"Occupied visible slots must reject additional bags")
local firstAdded,first=V:AddBag(7,"leftHip")
assert(firstAdded and first.id==2 and first.slot==1 and V:BagInSlot(1)==first)
local secondAdded,second=V:AddBag(8,"rightHip",2)
assert(secondAdded and second.id==3 and second.slot==2)
fourth.fits["1:0"]=V:Copy(oldFit)
V.placementTunerBag=fourth.id
assert(V:GetBagTunerState().bag==201 and V:GetBagTunerState().values.up==oldFit.up,"Tuner identity follows native ID, not visible slot")
assert(V:SaveOutfit("Fixed positions"))
local savedPositions=VanityStudioDB.outfits["Fixed positions"].weapons
assert(savedPositions.bags[1].slot==4 and savedPositions.bags[2].slot==1 and savedPositions.bags[3].slot==2)
local moved=V:Copy(savedPositions);moved.bags[1].slot=5
assert(V:BagSignature(savedPositions)~=V:BagSignature(moved),"Layout positions belong to the saved look signature")
assert(V:DeleteBag(first.id))
assert(not V:BagInSlot(1) and V:BagInSlot(4)==fourth and V:BagInSlot(2)==second,"Deleting a bag must leave other visible positions fixed")
local reused,replacement=V:AddBag(1,"back")
assert(reused and replacement.id==first.id and replacement.slot==1)
assert(V:LoadOutfit("Fixed positions",true))
assert(V:BagInSlot(4).id==1 and V:BagInSlot(1).id==2 and V:BagInSlot(2).id==3)
assert(contexts[0][1].fits["1:0"].up==oldFit.up and not contexts[0][4],"Renderer attachments continue to use native IDs")
V:ClearAll()
-- Reserve explicit slots first so legacy entries cannot displace later ones.
local mixed={bags={
    {id=8,model=2,mount="back",fits={["1:0"]=V:Copy(oldFit)}},
    {id=7,slot=1,model=7,mount="back",fits={}},
    {id=6,slot=4,model=8,mount="back",fits={}},
    {id=5,slot=4,model=10,mount="back",fits={}},
    {id=4,slot=9,model=11,mount="back",fits={}},
    {id=3,slot=2,model=16,mount="back",fits={}},
}}
local positioned=V:NormalizeBags(mixed)
for i,slot in ipairs({2,1,4,3,5}) do assert(positioned[i].slot==slot) end
assert(table.getn(positioned)==5 and positioned[1].id==8 and positioned[1].fits["1:0"].up==oldFit.up)
assert(not mixed.bags[1].slot and mixed.bags[4].slot==4 and mixed.bags[5].slot==9,"Normalizing layout must preserve source saved data")
local direct={mixed.bags[1],mixed.bags[2]};c.weapons={bags=direct}
local fitReference=direct[1].fits
assert(V:BagInSlot(2)==direct[1] and V:BagInSlot(1)==direct[2])
assert(V:GetBags()==direct and direct[1].fits==fitReference,"Direct legacy callers retain instance and fit references")
assert(V:DeleteBag(7) and not V:BagInSlot(1) and V:BagInSlot(2)==direct[1])
V:ClearAll()
-- Older looks retain their first five valid bags and stable high IDs. The
-- renderer still receives all eight slots so omitted attachments are cleared.
local legacyEight={bags={}}
for i,id in ipairs({8,7,6,5,4,3,2,1}) do
    legacyEight.bags[i]={id=id,model=2,mount="back",fits={["1:0"]=V:Copy(oldFit)}}
end
local limited=V:NormalizeBags(legacyEight)
assert(table.getn(limited)==5 and limited[1].id==8 and limited[5].id==4 and limited[1].slot==1 and limited[5].slot==5)
assert(limited[1].fits["1:0"].up==oldFit.up and table.getn(legacyEight.bags)==8)
assert(V:ApplyBagRenderer(0,legacyEight,false))
assert(contexts[0][8] and contexts[0][6] and contexts[0][4] and not contexts[0][3] and not contexts[0][1])
c.weapons=V:Copy(legacyEight);V:InitializeWeapons()
assert(table.getn(V:GetBags())==5 and V:BagInstance(8) and not V:AddBag(1,"back"))
assert(V:DeleteBag(7));local added,bag=V:AddBag(1,"back")
assert(added and bag.id==1 and bag.slot==2 and table.getn(V:GetBags())==5 and not contexts[0][7])
V:ClearAll()
local bad={bags={{id=1,model=2,mount="bad",fits={["1:0"]={scale=0/0}}},{id=1,model=5},{id=9,model=7},{id=2,model=999}}}
local clean=V:NormalizeBags(bad);assert(table.getn(clean)==1 and clean[1].mount=="back" and not next(clean[1].fits))
print("PASS: 11 active models, retired model migration, 5 stable visible bag slots, legacy/high-ID migration, fit isolation, saved looks, body profiles, preview/world separation, deletion/reuse, capacity, validation and retry")
