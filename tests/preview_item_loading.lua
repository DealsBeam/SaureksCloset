-- Real preview controllers: missing item information stays silent, retries,
-- remains available to diagnostics, and does not hide whole-preview failures.
local addon=arg[1] or "addon/SaureksCloset/"
local now,cached,requests,ready=0,false,0,true
GetTime=function() return now end
GetItemInfo=function() return cached and "Loaded item" or nil end
SaureksClosetPreviewStatus=function() return ready and 1 or 0 end
local function note()
    return {text="",SetText=function(self,text)
        assert(not string.find(text,"item data",1,true),"Item loading flashed a warning: "..text)
        self.text=text
    end}
end
local function model(token)
    return {weaponToken=token,tries=0,undresses=0,rotation=.61,
        IsVisible=function() return true end,
        SetAlpha=function() end,SetRotation=function() end,
        Undress=function(self) self.undresses=self.undresses+1 end,
        TryOn=function(self) self.tries=self.tries+1 end}
end
VanityStudio={}
local V=VanityStudio
-- Load production paths, then isolate dependencies unrelated to item loading.
dofile(addon.."Preview.lua")
dofile(addon.."OutfitPreview.lua")
V.PreviewBodyKey=function() return "body" end
V.PreviewItems=function() return {[1]=101} end
V.PreviewWeapons=function() return {} end
V.PreviewWeaponRoutes=function() return {} end
V.WeaponSignature=function() return "" end
V.WeaponDisplaySignature=V.WeaponSignature
V.WeaponPreviewMode=function() return 0 end
V.DressWeaponPlacements=function() return true end
V.RefreshPortraits=function() end
V.RequestItem=function() requests=requests+1 end
V.OutfitPreviewItems=V.PreviewItems
V.slotOrder={1}

-- Native and fallback wardrobe paths, for late and never-returned item data.
for _,native in ipairs({false,true}) do
    now=0;cached=false;requests=0;ready=true
    V.model=model(native and 7 or nil);V.previewBuffer=model(native and 8 or nil)
    V.previewNote=note();V.previewRequests={};V.previewRequestedBodyKey="body"
    V.previewSignature=nil;V.previewDressSignature=nil;V.previewReveal=nil
    V:RefreshPreview()
    if native then now=.02;V:RefreshPreview() end
    assert(V.previewNote.text=="" and V.previewWaiting[101] and requests==1)
    local undresses=V.model.undresses;local tries=V.model.tries
    now=.5;cached=true;V:UpdatePreviewLoading()
    assert(V.previewNote.text=="" and not V.previewWaiting[101])
    assert(V.model.tries==tries+1 and V.model.undresses==undresses)
    cached=false;V.previewSignature=nil;V:RefreshPreview()
    if native then now=.52;V:RefreshPreview() end
    for i=1,4 do now=now+2;V:UpdatePreviewLoading() end
    assert(V.previewNote.text=="" and V.previewWaiting[101])
    assert(requests==3 and V.previewRequests[101].attempts==3)
end

-- Saved-look dressing/reveal, late arrival, and exhausted retries.
V.outfitDetails={IsVisible=function() return true end}
V.outfitModel=model(9);V.outfitBuffer=model(10);V.detailPreviewNote=note()
now=0;cached=false;requests=0
V.detailPending={phase="dress",target=V.outfitModel,look={weapons={}},deadline=8}
V:UpdateOutfitPreview();now=.02;V:UpdateOutfitPreview()
assert(not V.detailPending and V.detailMissing[101] and V.detailPreviewNote.text=="")
local undresses=V.outfitModel.undresses;local tries=V.outfitModel.tries
now=.03;V:UpdateOutfitPreview() -- Formerly replaced "still loading" with "unavailable".
now=.5;cached=true;V:UpdateOutfitPreview()
assert(not V.detailMissing[101] and V.detailPreviewNote.text=="")
assert(V.outfitModel.tries==tries+1 and V.outfitModel.undresses==undresses)
cached=false;V.detailMissing={[101]=true}
for i=1,4 do now=now+2;V:UpdateOutfitPreview() end
assert(V.detailMissing[101] and V.detailItemRetries==3 and requests==4)
assert(V.detailPreviewNote.text=="")

-- Whole-preview initialization failures must still report their timeout.
V.detailPending={phase="copy",deadline=now-1}
V:UpdateOutfitPreview()
assert(string.find(V.detailPreviewNote.text,"Preview could not finish loading",1,true))
V.previewSignature=nil;V.previewReveal=nil;V.model=model(7);V.previewNote=note()
ready=false;V.previewDeadline=now-1;V:RefreshPreview()
assert(string.find(V.previewNote.text,"Preview could not finish loading",1,true))
print("PASS: silent item loading in both previews, late arrival, bounded retries, diagnostic IDs and whole-preview timeouts")
