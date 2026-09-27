-- Exercise Core handlers with actual VanillaHelpers Morph.cpp semantics:
-- ApplyField compares the CURRENT field; releases reload the model too.
-- Run with: lua tests/armor_recovery.lua path/to/Core.lua
local corePath=arg[1] or "addon/SaureksCloset/Core.lua"
table.getn=table.getn or function(t) return #t end
local now,dead,ghost,exists=0,false,false,true
local native,fields,visible,calls,missing,equipped={},{},{},{},{},{}
local reloads,queuedEvents=0,0
local repairCosts={}
local inspectorCalls,inspectorUnavailable,inspectorStatus={},{},{}
-- Catalog displays deliberately differ from item IDs. The renderer observes
-- the rendered appearance, independently of Lua's cache and helper fields.
local itemDisplays={[100]=1100,[200]=1200,[300]=1300,[400]=1400,[999]=1999,[6566]=2566}
local function inspectArmor(slot,expectedDisplay)
    inspectorCalls[slot]=(inspectorCalls[slot] or 0)+1
    assert(type(expectedDisplay)=="number","inspector needs a display ID")
    if inspectorStatus[slot]~=nil then return inspectorStatus[slot] end
    if (inspectorUnavailable[slot] or 0)>0 then
        inspectorUnavailable[slot]=inspectorUnavailable[slot]-1
        return -1
    end
    local appearance=visible[slot]
    local display=(appearance==0 or appearance==nil or appearance=="empty") and 0 or itemDisplays[appearance]
    return display==expectedDisplay and 1 or 0
end
local frames={}
function GetTime() return now end
function UnitIsDeadOrGhost() return dead end
function UnitIsGhost() return ghost end
function UnitExists() return exists end
function GetItemInfo(id) if not missing[id] then return "Item "..id end end
function GetInventoryItemLink(unit,slot) return equipped[slot] end
function CreateFrame()
    local frame={scripts={}}
    function frame:RegisterEvent() end
    function frame:SetOwner() end
    function frame:ClearLines() end
    function frame:Hide() end
    function frame:SetInventoryItem(unit,slot) return equipped[slot]~=nil,false,repairCosts[slot] end
    function frame:SetScript(name,handler) self.scripts[name]=handler end
    table.insert(frames,frame)
    return frame
end
SlashCmdList={}
dofile(corePath)
local V=VanityStudio
local function fire(name,unit)
    local oldEvent,oldArg=event,arg1
    event,arg1=name,unit
    V.events.scripts.OnEvent()
    event,arg1=oldEvent,oldArg
end
local emitSetterEvents=false
function SetUnitVisibleItemID(unit,slot,id)
    assert(unit=="player")
    table.insert(calls,{slot=slot,id=id})
    -- Match the helper's current-field comparison, not an override-ID cache.
    local value=id
    if value==nil then value=equipped[slot] or "empty" end
    native[slot]=id
    if fields[slot]==value then return end
    fields[slot]=value;reloads=reloads+1
    -- A field change rebuilds the WHOLE model. The rendered gear may be stale
    -- even when the helper's fields already contain the selected item IDs.
    for s,v in pairs(fields) do visible[s]=v end
    if emitSetterEvents=="sync" then
        fire("UNIT_MODEL_CHANGED","player")
        fire("UNIT_INVENTORY_CHANGED","player")
    elseif emitSetterEvents=="async" then
        queuedEvents=queuedEvents+1
    end
end
local function noop() end
for _,name in ipairs({"SyncBody","SyncWeapons","Refresh","RefreshTrueBody","RefreshBody",
    "RefreshPortraits","RefreshPreviewForModelEvent","InvalidatePreviewModel",
    "UpdateUpdates","UpdatePreviewLoading","CancelDraft","RequestItem"}) do V[name]=noop end
V.BodyAvailable=function() return false end
local function reset()
    now=0;dead=false;ghost=false;exists=true;native={};fields={};visible={};calls={};missing={};emitSetterEvents=false
    equipped={[1]="real head",[5]="real chest",[7]="real legs"}
    reloads=0;queuedEvents=0;V.armorEquipment=nil
    repairCosts={[1]=70,[5]=90,[7]=50};V.armorRepairCosts=nil;V.armorRepairCheckPending=nil
    V.ready=true;V.applied={};V.pending={};V.errors={};V.respawnRecovery=nil
    V.forceArmorSync=nil;V.needsSync=nil;V.bodyError=nil
    V.armorLifeState="alive";V.refreshArmorDisplay=nil
    V.armorCheckAt=nil;V.armorCheckRefreshDisplay=nil;V.armorCheckReason=nil;V.ignoreArmorModelEventsUntil=nil;V.armorHistory=nil;V.draft=nil;V.worldDraftActive=nil
    inspectorCalls={};inspectorUnavailable={};inspectorStatus={}
    V.armorVisualRetries=nil;V.armorVisualMismatch=nil
    SaureksClosetInspectArmor=inspectArmor
    ShowingHelm=nil;ShowingCloak=nil
    V.index={};V.slots={}
    for id,display in pairs(itemDisplays) do V.index[id]={[1]=id,[8]=display} end
    VanityStudioCharacter={enabled=true,selected={[5]=100,[7]=200,[1]=0,[3]=300},
        managed={},weapons={backBag=1},activeOutfit="Saved",outfitDirty=nil}
    V:Sync();V:CheckArmorRepairs();calls={};reloads=0;now=2
end
local function tick(seconds)
    for i=1,seconds*2 do
        now=now+.5
        local notifications=queuedEvents;queuedEvents=0
        for j=1,notifications do
            fire("UNIT_MODEL_CHANGED","player");fire("UNIT_INVENTORY_CHANGED","player")
        end
        arg1=.5;V.events.scripts.OnUpdate()
    end
end
local function rebuild()
    visible[5]="equipped";visible[7]="equipped";visible[1]="equipped";visible[3]="empty"
    for slot,value in pairs(visible) do fields[slot]=value end
end
local function rebuildTextures()
    visible[5]="equipped";visible[7]="equipped";visible[1]="equipped";visible[3]="empty"
end
local function restored()
    for slot,id in pairs(VanityStudioCharacter.selected) do
        assert(visible[slot]==id,"slot "..slot.." was not restored")
    end
    assert(visible[8]==nil,"unmanaged slot was changed")
    assert(VanityStudioCharacter.activeOutfit=="Saved")
    assert(VanityStudioCharacter.outfitDirty==nil)
    assert(VanityStudioCharacter.weapons.backBag==1)
end
local passed=0
local function noReleases()
    for _,call in ipairs(calls) do assert(call.id~=nil,"recovery released an override") end
end
local function noTemporaryArmorChanges()
    for _,call in ipairs(calls) do
        local selected=VanityStudioCharacter.selected[call.slot]
        assert(call.id==selected,"model notification temporarily cleared armor slot "..call.slot)
    end
end
local function quiet()
    -- Deferred setter notifications may cause one harmless field comparison.
    local settledReloads=reloads;tick(1)
    assert(reloads==settledReloads,"settled armor was rebuilt again")
    local count=table.getn(calls);local before=reloads;tick(20)
    assert(table.getn(calls)==count and reloads==before,"recovery continued applying armor")
end
local function test(name,run)
    if arg[2] and name~=arg[2] then return end
    reset();run();passed=passed+1;print("PASS "..name)
end
test("login applies once per slot without releasing armor",function()
    rebuild();fire("PLAYER_ENTERING_WORLD");tick(.5);restored();noReleases()
    assert(table.getn(calls)==4 and reloads==4,"login applied more than once per slot");quiet()
end)
test("correct fields on world entry cause zero model reloads",function()
    fire("PLAYER_ENTERING_WORLD");tick(.5);restored();assert(reloads==0);noReleases();quiet()
end)
test("death restores occupied, hidden, and empty-slot armor without toggling",function()
    rebuild();V:Sync()
    assert(visible[5]=="equipped","fixture must model the cached-ID failure")
    dead=true;fire("PLAYER_DEAD");tick(.5);restored()
end)
test("ghost release gets one new recovery application",function()
    dead=true;fire("PLAYER_DEAD");tick(7)
    ghost=true;rebuild();fire("PLAYER_ALIVE");tick(.5);restored()
    tick(7);local count=table.getn(calls);tick(20)
    assert(table.getn(calls)==count,"recovery continued indefinitely while dead")
end)
test("transition applies after the final model/inventory notification",function()
    dead=true;fire("PLAYER_DEAD");tick(7)
    calls={};dead=false;fire("PLAYER_UNGHOST");rebuild()
    now=now+.4;fire("UNIT_MODEL_CHANGED","player");fire("UNIT_INVENTORY_CHANGED","player")
    now=now+.1;arg1=.5;V.events.scripts.OnUpdate()
    assert(table.getn(calls)==0,"applied before notifications settled")
    tick(.5);restored();assert(table.getn(calls)==5);quiet()
end)
test("real equipment change applies only the changed slot",function()
    equipped[5]="new real chest";visible[5]=equipped[5];fields[5]=equipped[5]
    fire("UNIT_INVENTORY_CHANGED","player");tick(.5);restored()
    assert(table.getn(calls)==1 and calls[1].slot==5);noReleases();quiet()
end)
test("unchanged inventory notifications do not reload the model",function()
    for i=1,12 do fire("UNIT_INVENTORY_CHANGED","player");tick(.5) end
    assert(reloads==0);noReleases();quiet()
end)
test("drawing weapons with unchanged armor does not reload the player",function()
    fire("UNIT_MODEL_CHANGED","player");tick(.5)
    assert(reloads==0,"drawing weapons rebuilt the entire player "..reloads.." times")
    restored();noTemporaryArmorChanges();quiet()
end)
test("repeated sheathing outside the setter guard never blinks armor",function()
    for i=1,12 do
        fire("UNIT_MODEL_CHANGED","player");tick(2)
        assert(reloads==0,"sheathe cycle "..i.." rebuilt unchanged armor")
        restored();noTemporaryArmorChanges()
    end
    quiet()
end)
test("unrelated unit events do not schedule armor recovery",function()
    local count=table.getn(calls)
    fire("UNIT_INVENTORY_CHANGED","target");fire("UNIT_MODEL_CHANGED","target");tick(10)
    assert(table.getn(calls)==count)
end)
for _,mode in ipairs({"sync","async"}) do
    test(mode.." setter events cannot restart login recovery",function()
        emitSetterEvents=mode;rebuild();fire("PLAYER_ENTERING_WORLD");tick(2);restored()
        assert(table.getn(calls)<=(mode=="async" and 8 or 4) and reloads==4,"setter events fed back into recovery: "..table.getn(calls).." calls, "..reloads.." model reloads")
        noReleases();quiet();assert(not V.syncingAppearance)
    end)
end
test("disabled transmog stays disabled through all death transitions",function()
    V:SetEnabled(false);calls={}
    for _,name in ipairs({"PLAYER_DEAD","PLAYER_ALIVE","PLAYER_UNGHOST"}) do
        fire(name);tick(6)
    end
    for _,call in ipairs(calls) do assert(call.id==nil,"disabled armor was reapplied") end
    assert(not VanityStudioCharacter.enabled and VanityStudioCharacter.selected[5]==100)
end)
test("item cache miss recovers through the existing pending-item path",function()
    rebuild();missing[200]=true;fire("PLAYER_UNGHOST");tick(7)
    missing[200]=nil;tick(.5);restored()
end)
test("release and resurrection repair textures even when helper fields still match",function()
    dead=true;fire("PLAYER_DEAD");tick(.5)
    for _,name in ipairs({"PLAYER_ALIVE","PLAYER_UNGHOST"}) do
        ghost=name=="PLAYER_ALIVE";dead=ghost
        rebuildTextures();calls={};reloads=0
        for slot,id in pairs(VanityStudioCharacter.selected) do assert(fields[slot]==id) end
        fire(name);tick(.5);restored()
        assert(reloads==2,"expected one refresh pair, got "..reloads)
        quiet()
    end
end)
test("release waits for delayed ghost state before refreshing textures",function()
    dead=true;fire("PLAYER_DEAD");tick(.5);calls={}
    fire("PLAYER_ALIVE");tick(3)
    assert(table.getn(calls)==0,"recovered the corpse before release completed")
    ghost=true;rebuildTextures();tick(1);restored();quiet()
end)
test("resurrection waits for delayed alive state before refreshing textures",function()
    dead=true;ghost=true;fire("PLAYER_ALIVE");tick(.5);calls={}
    fire("PLAYER_UNGHOST");tick(3)
    assert(table.getn(calls)==0,"recovered before resurrection completed")
    dead=false;ghost=false;rebuildTextures();tick(1);restored();quiet()
end)
test("life state changes recover even without lifecycle notifications",function()
    dead=true;ghost=true;rebuildTextures();tick(1);restored();quiet()
    dead=false;ghost=false;rebuildTextures();tick(1);restored();quiet()
end)
test("world entry during release preserves the required texture refresh",function()
    dead=true;fire("PLAYER_DEAD");tick(.5)
    fire("PLAYER_ALIVE");exists=false;fire("PLAYER_ENTERING_WORLD");calls={};tick(3)
    assert(table.getn(calls)==0,"applied while the player was unavailable")
    exists=true;ghost=true;rebuildTextures();tick(1);restored();quiet()
end)
test("world entry detects a release whose lifecycle notification was missed",function()
    dead=true;ghost=true;rebuildTextures();fire("PLAYER_ENTERING_WORLD")
    tick(.5);restored();quiet()
end)
for _,mode in ipairs({"sync","async"}) do
    test(mode.." texture refresh events cannot cause a reload loop",function()
        dead=true;ghost=true;emitSetterEvents=mode;rebuildTextures();reloads=0
        fire("PLAYER_ALIVE");tick(2);restored()
        assert(reloads==2,"refresh caused extra model reloads: "..reloads);quiet()
    end)
end
test("all hidden armor gets one texture refresh pair",function()
    for slot in pairs(VanityStudioCharacter.selected) do VanityStudioCharacter.selected[slot]=0 end
    V:Sync();calls={};reloads=0;rebuildTextures()
    dead=true;ghost=true;fire("PLAYER_ALIVE");tick(.5);restored()
    assert(reloads==2);quiet()
end)
test("hidden unequipped shoulders use a cached compatible refresh item",function()
    equipped={};VanityStudioCharacter.selected={[3]=0}
    V.slots[3]={V.index[300]}
    V:Sync();calls={};reloads=0
    visible[3]=6566
    assert(fields[3]==0 and not equipped[3])
    fire("UNIT_MODEL_CHANGED","player");tick(1)
    restored();assert(reloads==2,"an all-hidden unequipped appearance had no usable refresh pulse")
    local pulsed=false
    for _,call in ipairs(calls) do
        assert(call.slot==3 and (call.id==0 or call.id==300),
            "refresh pulse used an incompatible item or released an empty slot")
        if call.id==300 then pulsed=true end
    end
    assert(pulsed and calls[#calls].id==0 and fields[3]==0,
        "the compatible refresh item was not restored to hidden before the update completed")
    quiet()
end)
test("hidden unequipped shoulders wait for a cached refresh item before manual Retry",function()
    equipped={};VanityStudioCharacter.selected={[3]=0}
    V.slots[3]={V.index[300]};missing[300]=true
    V:Sync();calls={};reloads=0;visible[3]=6566
    fire("UNIT_MODEL_CHANGED","player");tick(3)
    assert(reloads==0 and visible[3]==6566 and fields[3]==0,
        "missing refresh item data caused an invalid or ineffective model pulse")
    for _,call in ipairs(calls) do assert(call.slot==3 and call.id==0,"an uncached item reached the armor setter") end
    quiet()
    missing[300]=nil;calls={}
    V:Retry();tick(1);restored()
    assert(reloads==2,"manual Retry did not recover after the compatible item became cached")
    local pulsed=false
    for _,call in ipairs(calls) do if call.slot==3 and call.id==300 then pulsed=true end end
    assert(pulsed and fields[3]==0 and VanityStudioCharacter.selected[3]==0)
    quiet()
end)
test("resurrecting without releasing repairs textures",function()
    dead=true;fire("PLAYER_DEAD");tick(.5)
    dead=false;rebuildTextures();fire("PLAYER_ALIVE");tick(.5);restored();quiet()
end)
test("temporary item info loss does not remove an applied chest",function()
    missing[100]=true;V:Sync();restored();noReleases()
    assert(reloads==0 and not V.pending[5]);quiet()
end)
test("combat inventory update repairs chest with unchanged equipment",function()
    visible[5]="real chest";fields[5]="real chest"
    fire("UNIT_INVENTORY_CHANGED","player");tick(.5);restored()
    assert(reloads==1,"only the incorrect chest field should cause a reload")
    noReleases();quiet()
end)
test("combat model event repairs armor with unchanged equipment",function()
    visible[5]="real chest";fields[5]="real chest"
    fire("UNIT_MODEL_CHANGED","player");tick(.5);restored()
    assert(reloads==1,"a model event must repair only the incorrect armor field")
    noTemporaryArmorChanges();quiet()
end)
test("combat event bursts coalesce into one comparison pass",function()
    visible[5]="real chest";fields[5]="real chest"
    for i=1,20 do fire("UNIT_INVENTORY_CHANGED","player") end
    tick(.5);restored();assert(table.getn(calls)==4 and reloads==1);quiet()
end)
test("combat repair leaves an item browser draft in place",function()
    V.draft={slot=5,id=999};SetUnitVisibleItemID("player",5,999)
    calls={};fire("UNIT_INVENTORY_CHANGED","player");tick(.5)
    assert(visible[5]==999 and VanityStudioCharacter.selected[5]==100)
    for _,call in ipairs(calls) do assert(call.slot~=5) end
    quiet()
end)
test("disabled addon does not reapply armor on combat events",function()
    V:SetEnabled(false);calls={};reloads=0
    fire("UNIT_INVENTORY_CHANGED","player");fire("UNIT_MODEL_CHANGED","player");tick(2)
    assert(table.getn(calls)==0 and reloads==0);quiet()
end)
test("combat repair works when tooltip data is temporarily missing",function()
    missing[100]=true;visible[5]="real chest";fields[5]="real chest"
    fire("UNIT_INVENTORY_CHANGED","player");tick(.5);restored();noReleases();quiet()
end)
for _,mode in ipairs({"sync","async"}) do
    test(mode.." combat repair events do not cause blinking",function()
        emitSetterEvents=mode;visible[5]="real chest";fields[5]="real chest"
        fire("UNIT_INVENTORY_CHANGED","player");tick(2);restored()
        assert(reloads==1);assert(table.getn(calls)<=(mode=="async" and 8 or 4));quiet()
    end)
    test(mode.." mixed combat notifications preserve unchanged armor",function()
        emitSetterEvents=mode
        for cycle=1,6 do
            for i=1,10 do
                fire("UNIT_MODEL_CHANGED","player")
                fire("UNIT_INVENTORY_CHANGED","player")
            end
            tick(2)
            assert(reloads==0,"mixed combat notifications rebuilt unchanged armor")
            restored();noTemporaryArmorChanges()
        end
        quiet()
    end)
    test(mode.." mixed combat notifications repair only changed fields",function()
        emitSetterEvents=mode;visible[5]="real chest";fields[5]="real chest"
        for i=1,10 do
            fire("UNIT_MODEL_CHANGED","player")
            fire("UNIT_INVENTORY_CHANGED","player")
        end
        tick(2);restored()
        assert(reloads==1,"mixed combat repair rebuilt the player unnecessarily")
        noTemporaryArmorChanges();quiet()
    end)
end
-- Render-only failures leave the helper field correct. Reasserting its same
-- value cannot repair them; only a positive native mismatch may request the
-- existing single refresh pair.
for _,fixture in ipairs({
    {name="hidden head",slot=1,id=0},
    {name="hidden shoulders",slot=3,id=0},
    {name="custom shoulders",slot=3,id=300},
    {name="custom chest",slot=5,id=100},
    {name="hidden cloak",slot=15,id=0},
    {name="custom cloak",slot=15,id=400},
}) do
    test("combat repairs rendered-only "..fixture.name,function()
        equipped[fixture.slot]=6566
        VanityStudioCharacter.selected[fixture.slot]=fixture.id
        V:Sync();calls={};reloads=0
        visible[fixture.slot]=6566
        assert(fields[fixture.slot]==fixture.id and V.applied[fixture.slot]==fixture.id,
            "fixture must retain the requested helper field and Lua cache")
        fire("UNIT_MODEL_CHANGED","player");tick(1)
        restored()
        assert((inspectorCalls[fixture.slot] or 0)>0,"renderer did not inspect the affected slot")
        assert(reloads==2,"a rendered-only mismatch needs exactly one refresh pair")
        quiet()
    end)
end
for _,mode in ipairs({"sync","async"}) do
    test(mode.." rendered-only combat bursts refresh all stale slots once",function()
        emitSetterEvents=mode
        visible[1]=6566;visible[3]=6566;visible[5]=6566
        for slot,id in pairs(VanityStudioCharacter.selected) do assert(fields[slot]==id) end
        for i=1,20 do fire("UNIT_MODEL_CHANGED","player");fire("UNIT_INVENTORY_CHANGED","player") end
        tick(2);restored()
        assert(reloads==2,"multiple stale slots or setter echoes caused more than one refresh pair")
        calls={}
        for cycle=1,8 do
            fire("UNIT_MODEL_CHANGED","player");fire("UNIT_INVENTORY_CHANGED","player");tick(1.5)
        end
        assert(reloads==2,"drawing weapons after recovery rebuilt healthy armor")
        noTemporaryArmorChanges();quiet()
    end)
end
test("render inspection uses catalog display IDs rather than item IDs",function()
    fire("UNIT_MODEL_CHANGED","player");tick(1)
    assert((inspectorCalls[3] or 0)>0,"the healthy shoulder was not inspected")
    assert(reloads==0,"item/display ID confusion caused a false mismatch")
    restored();noTemporaryArmorChanges();quiet()
end)
test("stock hidden helm and cloak do not falsely repair positive selections",function()
    VanityStudioCharacter.selected[1]=100;VanityStudioCharacter.selected[15]=400
    V:Sync();calls={};reloads=0;inspectorCalls={}
    ShowingHelm=function() return false end
    ShowingCloak=function() return false end
    visible[1]=0;visible[15]=0
    assert(fields[1]==100 and fields[15]==400)
    fire("UNIT_MODEL_CHANGED","player");fire("UNIT_INVENTORY_CHANGED","player");tick(1)
    assert(not inspectorCalls[1] and not inspectorCalls[15],
        "intentionally omitted positive helm or cloak was treated as a render failure")
    assert(reloads==0 and visible[1]==0 and visible[15]==0,
        "stock hide flags caused a blind refresh or revealed hidden armor")
    assert(VanityStudioCharacter.selected[1]==100 and VanityStudioCharacter.selected[15]==400)
    noTemporaryArmorChanges();quiet()
end)
test("explicit hidden helm and cloak still repair while stock toggles are false",function()
    VanityStudioCharacter.selected[1]=0;VanityStudioCharacter.selected[15]=0
    V:Sync();calls={};reloads=0;inspectorCalls={}
    ShowingHelm=function() return false end
    ShowingCloak=function() return false end
    visible[1]=6566;visible[15]=6566
    assert(fields[1]==0 and fields[15]==0)
    fire("UNIT_MODEL_CHANGED","player");tick(1)
    assert((inspectorCalls[1] or 0)>0 and (inspectorCalls[15] or 0)>0,
        "stock hide flags suppressed verification of an explicit hidden appearance")
    restored();assert(reloads==2,"explicit hidden appearances were not repaired in one refresh pair")
    quiet()
end)
test("equipment changes repair rendered-only shoulders after scheduled sync",function()
    equipped[3]=6566;VanityStudioCharacter.selected[3]=0
    V:Sync();calls={};reloads=0
    visible[3]=6566
    equipped[5]="replacement chest"
    assert(fields[3]==0 and fields[5]==100)
    fire("UNIT_INVENTORY_CHANGED","player");tick(1)
    restored()
    assert(equipped[5]=="replacement chest" and VanityStudioCharacter.selected[5]==100)
    assert((inspectorCalls[3] or 0)>0 and reloads==2,
        "equipment-driven sync did not repair the separately stale shoulder appearance")
    quiet()
end)
test("world entry repairs rendered-only shoulders after applied caches reset",function()
    equipped[3]=6566;VanityStudioCharacter.selected[3]=0
    V:Sync();calls={};reloads=0
    visible[3]=6566;V.applied={};V.armorEquipment=nil
    assert(fields[3]==0)
    fire("PLAYER_ENTERING_WORLD");tick(1)
    restored()
    assert((inspectorCalls[3] or 0)>0 and reloads==2,
        "world-entry cache reset hid the rendered-only shoulder failure")
    quiet()
end)
test("missing renderer armor API retains legacy field repair",function()
    SaureksClosetInspectArmor=nil
    visible[3]=6566
    fire("UNIT_MODEL_CHANGED","player");tick(1)
    assert(visible[3]==6566 and fields[3]==300 and reloads==0,
        "an absent inspection API must not cause a blind model refresh")
    visible[5]=6566;fields[5]=6566
    fire("UNIT_INVENTORY_CHANGED","player");tick(1)
    restored();assert(reloads==1,"legacy field repair stopped working")
    quiet()
end)
test("unknown catalog appearances do not trigger blind render repair",function()
    VanityStudioCharacter.selected[3]=7000;V:Sync();calls={};reloads=0
    visible[3]=6566
    fire("UNIT_MODEL_CHANGED","player");tick(3)
    assert(not inspectorCalls[3],"unknown item has no verified display ID to inspect")
    assert(reloads==0 and visible[3]==6566)
    quiet()
end)
test("temporary render unavailability retries and repairs without another event",function()
    inspectorUnavailable[3]=2;visible[3]=6566
    fire("UNIT_MODEL_CHANGED","player");tick(.5)
    assert(reloads==0 and visible[3]==6566,"unavailable rendering was treated as a mismatch")
    tick(2);restored()
    assert(inspectorCalls[3]>=3 and reloads==2,"a ready renderer did not repair the delayed mismatch")
    quiet()
end)
test("persistent render unavailability stops after bounded retries",function()
    inspectorStatus[3]=-1;visible[3]=6566
    fire("UNIT_MODEL_CHANGED","player");tick(5)
    local attempts=inspectorCalls[3] or 0
    assert(attempts>1 and attempts<=5,"renderer unavailability did not use a bounded retry window: "..attempts)
    assert(reloads==0 and visible[3]==6566,"unavailability forced an unverified refresh")
    tick(20)
    assert(inspectorCalls[3]==attempts,"render inspection continued polling indefinitely")
    inspectorStatus[3]=nil
    fire("UNIT_MODEL_CHANGED","player");tick(1);restored()
    assert(reloads==2,"a new event did not re-arm inspection after the previous timeout")
    quiet()
end)
test("invalid renderer inspection does not loop or rebuild",function()
    inspectorStatus[3]=-2;visible[3]=6566
    fire("UNIT_MODEL_CHANGED","player");tick(5)
    local attempts=inspectorCalls[3] or 0
    assert(attempts==1 and reloads==0,"invalid inspection caused retries or a blind refresh")
    tick(20);assert(inspectorCalls[3]==attempts)
    quiet()
end)
for _,mode in ipairs({"sync","async"}) do
    test(mode.." persistent render mismatch receives only one refresh attempt",function()
        emitSetterEvents=mode;inspectorStatus[3]=0
        fire("UNIT_MODEL_CHANGED","player");tick(5)
        assert(reloads==2,"an uncorrected render mismatch retriggered its own repair")
        for cycle=1,6 do fire("UNIT_MODEL_CHANGED","player");tick(1) end
        assert(reloads==2,"external events repeatedly rebuilt the same persistent mismatch")
        local attempts=inspectorCalls[3]
        quiet();assert(inspectorCalls[3]==attempts,"persistent mismatch kept a background worker alive")
        inspectorStatus[3]=nil
        fire("UNIT_MODEL_CHANGED","player");tick(1);restored()
        visible[3]=6566
        fire("UNIT_MODEL_CHANGED","player");tick(1);restored()
        assert(reloads==4,"a later independent failure was suppressed after healthy rendering returned")
        quiet()
    end)
end
test("manual Retry rearms a suppressed persistent render failure",function()
    inspectorStatus[3]=0
    fire("UNIT_MODEL_CHANGED","player");tick(3)
    assert(reloads==2);quiet()
    inspectorStatus[3]=nil;visible[3]=6566
    fire("UNIT_MODEL_CHANGED","player");tick(1)
    assert(reloads==2 and visible[3]==6566,
        "the persistent failure should remain suppressed until healthy or explicitly retried")
    V:Retry();tick(1);restored()
    assert(reloads==4,"manual Retry did not authorize one new render-recovery attempt")
    quiet()
end)
test("disabled appearance ignores rendered-only combat failures",function()
    V:SetEnabled(false);calls={};reloads=0;inspectorCalls={}
    visible[3]=6566
    fire("UNIT_MODEL_CHANGED","player");fire("UNIT_INVENTORY_CHANGED","player");tick(5)
    assert(next(inspectorCalls)==nil and #calls==0 and reloads==0)
    assert(visible[3]==6566 and not VanityStudioCharacter.enabled)
    quiet()
end)
test("disabling appearance cancels deferred inspection through sync and manual Retry",function()
    inspectorStatus[3]=-1;visible[3]=6566
    fire("UNIT_MODEL_CHANGED","player");tick(.5)
    assert((inspectorCalls[3] or 0)>0 and V.armorCheckAt,
        "fixture did not schedule a deferred render check")
    V:SetEnabled(false);calls={};reloads=0;inspectorCalls={}
    tick(3)
    V:CheckArmorVisuals("disabled direct check")
    V.needsSync=true;tick(1)
    fire("PLAYER_ENTERING_WORLD");tick(1)
    equipped[5]="disabled replacement chest"
    fire("UNIT_INVENTORY_CHANGED","player");tick(1)
    V:Retry();tick(1)
    assert(next(inspectorCalls)==nil and #calls==0 and reloads==0,
        "disabled appearance inspected or reapplied armor through a deferred or scheduled path")
    assert(not VanityStudioCharacter.enabled and VanityStudioCharacter.selected[3]==300)
    quiet()
end)
-- Use the real browser transaction methods with Core's timed refresh handler.
dofile(string.gsub(corePath,"Core.lua$","Preview.lua"))
V.UpdatePreviewLoading=noop
V.InvalidatePreviewModel=noop
V.RefreshPreviewForModelEvent=noop
V.Compatible=function() return true end
V.IsWeaponPosition=function(_,slot) return slot>=101 end
for _,choice in ipairs({999,0,"passthrough"}) do
    test("rendered-only repair preserves armor browser choice "..tostring(choice),function()
        local id=choice;if choice=="passthrough" then id=nil end
        assert(V:DraftSlot(5,id));local draft=V.draft
        calls={};reloads=0;visible[3]=6566
        fire("UNIT_MODEL_CHANGED","player");tick(1)
        assert(visible[3]==300 and visible[5]==(id or equipped[5]))
        assert(V.draft==draft and V.worldDraftActive==5 and VanityStudioCharacter.selected[5]==100)
        for _,call in ipairs(calls) do
            assert(call.slot~=5 or call.id~=100,"render repair flashed the saved item through a live draft")
        end
        assert(reloads==2,"draft preservation introduced extra full-model rebuilds")
        quiet();V:CancelDraft();assert(visible[5]==100)
    end)
end
for _,choice in ipairs({999,0}) do
    test("render inspection recovers effective armor draft "..choice,function()
        assert(V:DraftSlot(3,choice));local draft=V.draft
        calls={};reloads=0;visible[3]=6566
        assert(fields[3]==choice and VanityStudioCharacter.selected[3]==300)
        fire("UNIT_MODEL_CHANGED","player");tick(1)
        assert(visible[3]==choice and V.draft==draft and VanityStudioCharacter.selected[3]==300,
            "inspection ignored or replaced the browser's effective appearance")
        for _,call in ipairs(calls) do assert(call.slot~=3 or call.id~=300,"saved shoulders flashed during draft recovery") end
        assert(reloads==2);quiet();V:CancelDraft();assert(visible[3]==300)
    end)
end
for _,choice in ipairs({999,0,"passthrough"}) do
    test("model and inventory events preserve armor browser choice "..tostring(choice),function()
        local id=choice
        if choice=="passthrough" then id=nil end
        assert(V:DraftSlot(5,id));local draft=V.draft
        local expected=id or equipped[5]
        calls={};reloads=0
        for cycle=1,6 do
            fire("UNIT_MODEL_CHANGED","player")
            fire("UNIT_INVENTORY_CHANGED","player")
            tick(2)
            assert(reloads==0,"a background notification rebuilt a live armor draft")
            assert(visible[5]==expected and V.draft==draft and V.worldDraftActive==5)
            assert(VanityStudioCharacter.selected[5]==100)
            for _,call in ipairs(calls) do assert(call.slot~=5,"background check touched the browser-owned slot") end
            noTemporaryArmorChanges()
        end
        quiet();V:CancelDraft();assert(visible[5]==100)
    end)
    test("scheduled sync preserves browser choice "..tostring(choice),function()
        local id=choice
        if choice=="passthrough" then id=nil end
        V:DraftSlot(5,id)
        local expected=id or equipped[5]
        calls={};V.needsSync=true;tick(2)
        assert(visible[5]==expected,"scheduled sync overwrote the draft")
        for _,call in ipairs(calls) do assert(call.slot~=5 or call.id==id,"saved item flashed during preview") end
        assert(VanityStudioCharacter.selected[5]==100)
        V:CancelDraft();assert(visible[5]==100)
    end)
end
test("model and inventory events preserve a weapon browser transaction",function()
    local previousPreview,previousApply=V.PreviewWeapons,V.ApplyWeaponRenderer
    local oldName=V.slotNames[101];V.slotNames[101]="Left waist"
    VanityStudioCharacter.weapons[101]=400
    local displayedWeapon
    V.PreviewWeapons=function(self)
        return {[101]=self.draft and self.draft.id or VanityStudioCharacter.weapons[101]}
    end
    V.ApplyWeaponRenderer=function(_,token,weapons)
        assert(token==0);displayedWeapon=weapons[101];return true
    end
    assert(V:DraftSlot(101,999));local draft=V.draft
    calls={};reloads=0
    for cycle=1,6 do
        fire("UNIT_MODEL_CHANGED","player")
        fire("UNIT_INVENTORY_CHANGED","player")
        tick(2)
        assert(reloads==0,"a background notification rebuilt the player during a weapon draft")
        assert(V.draft==draft and V.worldDraftActive==101 and displayedWeapon==999)
        assert(VanityStudioCharacter.weapons[101]==400)
        restored();noTemporaryArmorChanges()
    end
    quiet();V:CancelDraft()
    V.PreviewWeapons=previousPreview;V.ApplyWeaponRenderer=previousApply;V.slotNames[101]=oldName
end)
test("disabled appearance keeps a draft through scheduled sync",function()
    V:SetEnabled(false);V:DraftSlot(5,999)
    V.needsSync=true;tick(2);assert(visible[5]==999)
    V:CancelDraft();assert(visible[5]==equipped[5])
end)
test("pending item retry in another slot preserves the draft",function()
    missing[200]=true;V.applied[7]=nil;V:Sync()
    V:DraftSlot(5,999);tick(2);assert(visible[5]==999)
    missing[200]=nil;tick(1);assert(visible[5]==999 and visible[7]==200)
end)
for _,notification in ipairs({"UPDATE_INVENTORY_ALERTS","UNIT_INVENTORY_CHANGED","MERCHANT_UPDATE","MERCHANT_CLOSED"}) do
    test(notification.." detects equipped armor repair with stale textures",function()
        repairCosts[5]=0;rebuildTextures();fire(notification,"player");tick(1);restored()
        assert(reloads==2,"repair must refresh only once");quiet()
    end)
end
for _,mode in ipairs({"sync","async"}) do
    test(mode.." repair all coalesces notifications and preserves weapon draw behavior",function()
        V:Sync();emitSetterEvents=mode;reloads=0 -- still inside the model echo guard
        repairCosts={[1]=0,[5]=0,[7]=0};rebuildTextures()
        for i=1,20 do fire("UPDATE_INVENTORY_ALERTS");fire("UNIT_INVENTORY_CHANGED","player") end
        tick(2);restored();assert(reloads==2);quiet()
        for i=1,6 do fire("UNIT_MODEL_CHANGED","player");tick(2) end
        assert(reloads==2,"drawing after repair restarted full-model refreshes")
    end)
end
test("damage, discounts and vendor visits never force a model refresh",function()
    fire("MERCHANT_SHOW");fire("MERCHANT_UPDATE");tick(1)
    repairCosts[5]=100;fire("UPDATE_INVENTORY_ALERTS");tick(1)
    repairCosts[5]=80;fire("MERCHANT_UPDATE");tick(1)
    assert(reloads==0);restored();quiet()
end)
test("swapping or removing damaged equipment is not a repair",function()
    equipped[5]="replacement chest";repairCosts[5]=0
    fire("UNIT_INVENTORY_CHANGED","player");tick(1)
    equipped[7]=nil;repairCosts[7]=nil
    fire("UNIT_INVENTORY_CHANGED","player");tick(1)
    assert(reloads==0);restored();quiet()
end)
test("missing repair data does not fake a repair or lose its baseline",function()
    repairCosts[5]=nil;fire("UPDATE_INVENTORY_ALERTS");tick(1);assert(reloads==0)
    repairCosts[5]=0;rebuildTextures();fire("UPDATE_INVENTORY_ALERTS");tick(1)
    restored();assert(reloads==2);quiet()
end)
test("repair retains cached appearances while item data is missing",function()
    VanityStudioCharacter.selected={[5]=100};V:Sync();calls={};reloads=0
    missing[100]=true;repairCosts[5]=0;rebuildTextures()
    fire("UPDATE_INVENTORY_ALERTS");tick(1)
    assert(visible[5]==100 and not V.pending[5]);assert(reloads==2);quiet()
end)
test("disabled appearance stays disabled after repairs",function()
    V:SetEnabled(false);calls={};reloads=0;repairCosts[5]=0
    fire("UPDATE_INVENTORY_ALERTS");tick(2);assert(reloads==0 and #calls==0);quiet()
end)
for _,choice in ipairs({999,0,"passthrough"}) do
    test("repair preserves active armor draft "..tostring(choice),function()
        local id=choice;if choice=="passthrough" then id=nil end
        V:DraftSlot(5,id);local draft=V.draft
        repairCosts[5]=0;rebuildTextures();fire("UPDATE_INVENTORY_ALERTS");tick(1)
        assert(visible[5]==(id or equipped[5]) and V.draft==draft)
        assert(VanityStudioCharacter.selected[5]==100);quiet()
        V:CancelDraft();assert(visible[5]==100)
    end)
end
print(passed.." armor recovery scenarios passed")
