-- Stock-client integration contract for the native equipment UI isolation hook.
-- Run from renderer-source: lua tests/equipment_ui_isolation.lua
-- The real hook's caller/unit scoping is tested in C++. Here, run the original
-- 1.12 paper-doll handlers against its corrected native API outputs. Real item
-- objects and cosmetic visible fields are deliberately independent fixtures.
local stockPath=arg[1] or "research/client-data/PaperDollFrame.lua"
local real,visible,buttons={},{},{}
local hookActive,repairMode=true,false
local passed=0
local slotNames={[1]="HeadSlot",[3]="ShoulderSlot",[4]="ShirtSlot",[5]="ChestSlot",
    [6]="WaistSlot",[7]="LegsSlot",[8]="FeetSlot",[9]="WristSlot",[10]="HandsSlot",
    [12]="Finger1Slot",[13]="Trinket0Slot",[14]="Trinket1Slot",[15]="BackSlot",
    [16]="MainHandSlot",[17]="SecondaryHandSlot",[18]="RangedSlot",[19]="TabardSlot",[20]="Bag0Slot"}
local function icon(id) return "Interface\\Icons\\Item_"..id end
local function background(slot) return "Interface\\Paperdoll\\UI-PaperDoll-Slot-"..slotNames[slot] end
local function item(id,broken)
    return {id=id,name="Equipped item "..id,icon=icon(id),count=1,quality=3,
        enchant=7,durability=broken and 0 or 32,maxDurability=40,broken=broken,
        repairCost=broken and 120 or 17,cooldownStart=0,cooldownDuration=0}
end
local function equipment(unit,slot) return real[unit] and real[unit][slot] end
local function visibleItem(unit,slot)
    local cosmetic=visible[unit] and visible[unit][slot]
    if cosmetic~=nil then return cosmetic end
    local equipped=equipment(unit,slot)
    return equipped and equipped.id
end

-- These mocks model existing native inventory behavior, with the hook enabled
-- only for the local player's icon and the empty-slot tooltip fallback. They
-- do not call Lua wrappers or reconstruct inventory tooltips from item links.
function GetInventoryItemTexture(unit,slot)
    if not hookActive or unit~="player" then
        local id=visibleItem(unit,slot)
        if id~=nil and id~=0 then return icon(id) end
    end
    local equipped=equipment(unit,slot)
    return equipped and equipped.icon
end
function GetInventoryItemLink(unit,slot)
    local equipped=equipment(unit,slot)
    if equipped then return "item:"..equipped.id..":"..equipped.enchant..":0:0" end
end
function GetInventoryItemCount(unit,slot)
    local equipped=equipment(unit,slot);return equipped and equipped.count or 0
end
function GetInventoryItemQuality(unit,slot)
    local equipped=equipment(unit,slot);return equipped and equipped.quality
end
function GetInventoryItemBroken(unit,slot)
    local equipped=equipment(unit,slot);return equipped and equipped.broken
end
function GetInventoryItemCooldown(unit,slot)
    local equipped=equipment(unit,slot)
    return equipped and equipped.cooldownStart or 0,equipped and equipped.cooldownDuration or 0,1
end
GameTooltip={}
function GameTooltip:SetOwner(owner) self.owner=owner end
function GameTooltip:IsOwned(owner) return self.owner==owner end
function GameTooltip:SetInventoryItem(unit,slot)
    self.item=nil;self.link=nil;self.text=nil;self.money=nil;self.lines={};self.shown=true
    local equipped=equipment(unit,slot)
    if equipped then
        self.item=equipped;self.link=GetInventoryItemLink(unit,slot);self.text=equipped.name
        return true,equipped.cooldownDuration>0,equipped.repairCost
    end
    local cosmetic=visibleItem(unit,slot)
    if (not hookActive or unit~="player") and cosmetic and cosmetic~=0 then
        self.item=item(cosmetic);self.text="Cosmetic item "..cosmetic
        return true,nil,0
    end
    return nil,nil,0
end
function GameTooltip:SetText(text) self.text=text;self.shown=true end
function GameTooltip:AddLine(text) table.insert(self.lines,text) end
function GameTooltip:Show() self.shown=true end
function GameTooltip:Hide() self.shown=false end
function SetTooltipMoney(tooltip,cost) tooltip.money=cost end
function getglobal(name) return _G[name] end
function TEXT(value) return value end
strupper=string.upper;strsub=string.sub
REPAIR_COST="Repair cost"
function GetInventorySlotInfo(name)
    for slot,label in pairs(slotNames) do if name==label then return slot,background(slot),false end end
    error("Unknown fixture inventory slot "..tostring(name))
end
function SetItemButtonTexture(button,value) button.texture=value end
function SetItemButtonCount(button,value) button.count=value end
function SetItemButtonTextureVertexColor(button,r,g,b) button.tint={r,g,b} end
function SetItemButtonNormalTextureVertexColor(button,r,g,b) button.normalTint={r,g,b} end
function SetItemButtonDesaturated(button,value) button.desaturated=value end
function CooldownFrame_SetTimer(frame,start,duration,enabled)
    frame.start=start;frame.duration=duration;frame.enabled=enabled
end
function IsInventoryItemLocked() return false end
function UnitHasRelicSlot() return false end
function InRepairMode() return repairMode end
function CursorUpdate() end
function ResetCursor() end
function SetUnitVisibleItemID() error("Equipment UI changed the visible player appearance") end
local nativeAPIs={GetInventoryItemTexture=GetInventoryItemTexture,GetInventoryItemLink=GetInventoryItemLink,
    GetInventoryItemCount=GetInventoryItemCount,GetInventoryItemQuality=GetInventoryItemQuality,
    GetInventoryItemBroken=GetInventoryItemBroken,GetInventoryItemCooldown=GetInventoryItemCooldown}
local nativeTooltip=GameTooltip.SetInventoryItem
CharacterModelFrame={}
function CharacterModelFrame:SetUnit(unit)
    self.head=visibleItem(unit,1);self.shoulders=visibleItem(unit,3)
end
dofile(stockPath)

local function makeButton(slot)
    local button={slot=slot,name="Character"..slotNames[slot]}
    function button:GetName() return self.name end
    function button:GetID() return self.slot end
    function button:SetID(value) self.slot=value end
    function button:IsVisible() return true end
    function button:RegisterEvent() end
    function button:RegisterForDrag() end
    function button:RegisterForClicks() end
    _G[button.name.."Cooldown"]={Hide=function(self) self.hidden=true end}
    _G[button.name.."IconTexture"]={SetTexture=function(self,value) self.texture=value end}
    _G[string.upper(slotNames[slot])]=slotNames[slot]
    local prior=this;this=button;PaperDollItemSlotButton_OnLoad();this=prior
    return button
end
local function update(slot,eventName)
    this=buttons[slot];arg1="player"
    if eventName then PaperDollItemSlotButton_OnEvent(eventName)
    else PaperDollItemSlotButton_Update() end
end
local function hover(slot)
    this=buttons[slot];PaperDollItemSlotButton_OnEnter()
end
local function expect(slot,id)
    local button=buttons[slot]
    assert(button.texture==(id and icon(id) or background(slot)),"wrong stock icon in slot "..slot)
    assert(button.hasItem==(id and 1 or nil),"wrong stock occupancy in slot "..slot)
    assert(button.count==(id and equipment("player",slot).count or 0),"wrong real count")
end
local function reset()
    hookActive=true;repairMode=false
    real={player={},target={}};visible={player={},target={}};buttons={}
    GameTooltip.owner=nil;GameTooltip.item=nil;GameTooltip.text=nil;GameTooltip.shown=false
    CharacterModelFrame.head=nil;CharacterModelFrame.shoulders=nil
    for slot in pairs(slotNames) do buttons[slot]=makeButton(slot) end
end
local function test(name,run)
    reset();run()
    for name,original in pairs(nativeAPIs) do assert(_G[name]==original,"Lua replaced native API "..name) end
    assert(GameTooltip.SetInventoryItem==nativeTooltip,"Lua replaced the native equipment tooltip")
    passed=passed+1;print("PASS "..name)
end

test("fixture reproduces both original cosmetic leaks before native isolation",function()
    visible.player[1]=9001;hookActive=false
    update(1);hover(1)
    assert(buttons[1].texture==icon(9001) and buttons[1].hasItem==1)
    assert(GameTooltip.item.id==9001)
    hookActive=true;update(1);hover(1)
    expect(1,nil);assert(GameTooltip.item==nil and GameTooltip.text=="HeadSlot")
end)

test("cosmetic goggles leave an empty real head icon and slot-label tooltip",function()
    visible.player[1]=9001;update(1);hover(1)
    expect(1,nil)
    assert(GameTooltip.item==nil and GameTooltip.text=="HeadSlot")
    local hasItem,hasCooldown,repairCost=GameTooltip:SetInventoryItem("player",1)
    assert(hasItem==nil and hasCooldown==nil and repairCost==0)
    assert(GetInventoryItemLink("player",1)==nil and GetInventoryItemCount("player",1)==0)
    assert(visible.player[1]==9001)
end)

test("real helmet keeps its own icon and full native equipped-item tooltip",function()
    real.player[1]=item(101);visible.player[1]=9001;update(1);hover(1)
    expect(1,101)
    assert(GameTooltip.item==real.player[1],"tooltip lost the equipped item object")
    assert(GameTooltip.link=="item:101:7:0:0")
    assert(GameTooltip.item.durability==32 and GameTooltip.item.maxDurability==40)
    assert(GetInventoryItemQuality("player",1)==3 and not GetInventoryItemBroken("player",1))
end)

test("hidden cosmetic armor cannot hide real inventory equipment",function()
    real.player[1]=item(101);visible.player[1]=0;update(1);hover(1)
    expect(1,101);assert(GameTooltip.item==real.player[1])
    assert(visible.player[1]==0)
end)

test("all armor slots independently show real equipment under cosmetics",function()
    for _,slot in ipairs({1,3,4,5,6,7,8,9,10,15,19}) do
        real.player[slot]=item(100+slot);visible.player[slot]=9000+slot
        update(slot);hover(slot);expect(slot,100+slot)
        assert(GameTooltip.item==real.player[slot])
    end
end)

test("broken real gear retains its warning tint and repair cost",function()
    real.player[1]=item(101,true);visible.player[1]=9001;repairMode=true
    update(1);hover(1);expect(1,101)
    assert(buttons[1].tint[1]==.9 and buttons[1].tint[2]==0)
    assert(buttons[1].normalTint[1]==.9 and buttons[1].normalTint[2]==0)
    assert(GameTooltip.money==120 and GameTooltip.item.durability==0)
end)

test("empty real slots do not inherit cosmetic repair data",function()
    visible.player[1]=9001;repairMode=true;update(1);hover(1)
    expect(1,nil);assert(GameTooltip.money==nil and GameTooltip.item==nil)
end)

test("real equip then cosmetic redraw preserves real icon and tooltip",function()
    real.player[1]=item(101);update(1,"UNIT_INVENTORY_CHANGED");hover(1)
    visible.player[1]=9001;update(1,"UNIT_INVENTORY_CHANGED");expect(1,101)
    assert(GameTooltip.item==real.player[1])
end)

test("cosmetic draft then real equip resolves the latest real item",function()
    visible.player[1]=9001;update(1,"UNIT_INVENTORY_CHANGED");expect(1,nil)
    real.player[1]=item(101);update(1,"UNIT_INVENTORY_CHANGED");hover(1);expect(1,101)
    visible.player[1]=9002;update(1,"UNIT_INVENTORY_CHANGED");expect(1,101)
    assert(GameTooltip.item==real.player[1])
end)

test("unequipping while hovering removes the item and hides stale tooltip",function()
    real.player[1]=item(101);visible.player[1]=9001;update(1);hover(1)
    real.player[1]=nil;update(1,"UNIT_INVENTORY_CHANGED")
    expect(1,nil);assert(not GameTooltip.shown,"stock client left a stale item tooltip visible")
    hover(1);assert(GameTooltip.text=="HeadSlot" and GameTooltip.item==nil)
end)

test("cooldown redraw on empty cosmetic slot still has no real item tooltip",function()
    visible.player[1]=9001;update(1);hover(1)
    update(1,"BAG_UPDATE_COOLDOWN");expect(1,nil)
    assert(GameTooltip.item==nil and GameTooltip.text=="HeadSlot")
end)

test("equipment alerts redraw real durability without reading cosmetic gear",function()
    real.player[3]=item(103,true);visible.player[3]=9003
    update(3,"UPDATE_INVENTORY_ALERTS");expect(3,103);assert(buttons[3].tint[2]==0)
    real.player[3].broken=false;real.player[3].durability=40
    update(3,"UPDATE_INVENTORY_ALERTS");expect(3,103);assert(buttons[3].tint[2]==1)
end)

test("releasing a cosmetic override leaves real equipment identity unchanged",function()
    real.player[1]=item(101);visible.player[1]=9001;update(1);expect(1,101)
    visible.player[1]=nil;update(1,"UNIT_INVENTORY_CHANGED");hover(1);expect(1,101)
    assert(GameTooltip.item==real.player[1])
end)

test("untouched trinkets bags and weapons retain real counts and cooldowns",function()
    for _,slot in ipairs({12,13,14,16,17,18,20}) do
        real.player[slot]=item(100+slot);real.player[slot].count=slot
        real.player[slot].cooldownStart=12;real.player[slot].cooldownDuration=30
        update(slot);hover(slot);expect(slot,100+slot)
        local cooldown=_G[buttons[slot].name.."Cooldown"]
        assert(cooldown.start==12 and cooldown.duration==30)
        assert(GameTooltip.item==real.player[slot])
    end
end)

test("nonplayer inventory queries preserve the original visible-field behavior",function()
    real.target[1]=item(201);visible.target[1]=9201
    assert(GetInventoryItemTexture("target",1)==icon(9201))
    assert(GetInventoryItemLink("target",1)=="item:201:7:0:0")
    real.target[1]=nil
    assert(GameTooltip:SetInventoryItem("target",1))
    assert(GameTooltip.item.id==9201)
end)

test("stock Character preview keeps cosmetics during inventory and model refreshes",function()
    real.player[1]=item(101);visible.player[1]=9001;visible.player[3]=9003
    this=buttons[1];PaperDollFrame_OnEvent("PLAYER_ENTERING_WORLD")
    assert(CharacterModelFrame.head==9001 and CharacterModelFrame.shoulders==9003)
    update(1,"UNIT_INVENTORY_CHANGED");hover(1);expect(1,101)
    visible.player[1]=9002
    PaperDollFrame_OnEvent("UNIT_MODEL_CHANGED","player")
    assert(CharacterModelFrame.head==9002 and CharacterModelFrame.shoulders==9003)
    expect(1,101);assert(visible.player[1]==9002)
end)

print("Stock equipment UI isolation: "..passed.." scenarios passed")
