-- Exercise the real drag handlers with the 1.12 global this/arg1 convention.
-- The mouse frame stays fixed while loading replaces either preview model.
math.mod=math.mod or math.fmod
VanityStudio={}
local V=VanityStudio
local cursorX,cursorY=0,0
GetCursorPosition=function() return cursorX,cursorY end
local frame={}
frame.__index=frame
function CreateFrame(kind,name,parent)
    return setmetatable({kind=kind,name=name,parent=parent,scripts={},scale=1},frame)
end
function frame:SetAllPoints(target) self.bounds=target end
function frame:SetFrameLevel(value) self.level=value end
function frame:GetFrameLevel() return self.level or 2 end
function frame:EnableMouse(value) self.mouse=value end
function frame:RegisterForDrag(value) self.dragButton=value end
function frame:SetScript(event,callback) self.scripts[event]=callback end
function frame:GetEffectiveScale() return self.scale end
function frame:SetRotation(value) self.renderedRotation=value end
local function model(level,rotation)
    local result=CreateFrame("DressUpModel")
    result.level=level;result.rotation=rotation
    return result
end
local function event(target,name,value)
    local oldThis,oldArg=this,arg1
    this=target;arg1=value
    if target.scripts[name] then target.scripts[name]() end
    this=oldThis;arg1=oldArg
end
local checks=0
local function near(actual,expected,message)
    assert(math.abs(actual-expected)<.000001,message or "rotation differs")
    checks=checks+1
end
local function begin(surface,x,y,button)
    cursorX=x;cursorY=y or 0;event(surface,"OnMouseDown",button or "LeftButton")
end
local function move(surface,x,y)
    cursorX=x;cursorY=y or cursorY;event(surface,"OnUpdate",.016)
end
dofile("addon/SaureksCloset/Preview.lua")
V.model=model(4,.61);V.previewBuffer=model(4,.61)
V.outfitModel=model(7,1.2);V.outfitBuffer=model(7,1.2)
local main=V:CreatePreviewDragSurface({},"model","previewBuffer")
local detail=V:CreatePreviewDragSurface({},"outfitModel","outfitBuffer")
assert(main.bounds==V.model and detail.bounds==V.outfitModel)
assert(main.level==5 and detail.level==8)
assert(main.mouse and detail.mouse and main.dragButton=="LeftButton")
assert(not V.model.mouse and not V.previewBuffer.mouse and not V.outfitModel.mouse and not V.outfitBuffer.mouse)
assert(not main.scripts.OnMouseWheel and not main.scripts.OnKeyDown and not main.scripts.OnLeave)

-- Right/middle clicks do not spin or make a drag follow subsequent movement.
for _,button in ipairs({"RightButton","MiddleButton"}) do
    begin(main,10,20,button);move(main,110,200)
    near(V.model.rotation,.61)
end
-- Physical cursor coordinates are converted to the surface's UI scale.
main.scale=2
begin(main,100,20);event(main,"OnDragStart");move(main,140,400)
near(V.model.rotation,.81);near(V.model.renderedRotation,.81)
near(V.previewBuffer.rotation,.81);near(V.previewBuffer.renderedRotation,.81)
near(V.outfitModel.rotation,1.2,"wardrobe drag changed the saved-look model")
move(main,140,1000);near(V.model.rotation,.81,"vertical movement rotated the model")
move(main,100);near(V.model.rotation,.61)
event(main,"OnMouseUp","RightButton");move(main,120);near(V.model.rotation,.71)
event(main,"OnMouseUp","LeftButton");move(main,220);near(V.model.rotation,.71)
assert(not main.cursorX)

-- A hidden buffer may become the visible model while the same mouse capture
-- remains active. The following frame must update the new visible model.
main.scale=1
begin(main,0);move(main,20);near(V.model.rotation,.91)
local first=V.model
V.model,V.previewBuffer=V.previewBuffer,V.model
move(main,50)
near(V.model.rotation,1.21);near(V.model.renderedRotation,1.21)
near(first.rotation,1.21);near(first.renderedRotation,1.21)
event(main,"OnDragStop");move(main,100);near(V.model.rotation,1.21)

-- Hiding/closing a page cancels the capture, without a stale drag on reopen.
begin(main,100);move(main,110);near(V.model.rotation,1.31)
event(main,"OnHide");move(main,200);near(V.model.rotation,1.31)
assert(not main.cursorX)

-- Saved-look drag has independent state and follows its own buffer swaps.
detail.scale=.5
begin(detail,50);move(detail,100)
near(V.outfitModel.rotation,2.2);near(V.outfitBuffer.rotation,2.2)
near(V.model.rotation,1.31)
V.outfitModel,V.outfitBuffer=V.outfitBuffer,V.outfitModel
move(detail,125);near(V.outfitModel.rotation,2.7);near(V.outfitBuffer.rotation,2.7)
event(detail,"OnHide");move(detail,500);near(V.outfitModel.rotation,2.7)

-- Repeated turns remain bounded, and rotation arrows can change the starting
-- angle between gestures without the next drag jumping back to an old angle.
V.model.rotation=0
begin(main,0);move(main,-20);near(V.model.rotation,2*math.pi-.2)
move(main,2*math.pi*100+.3*100);near(V.model.rotation,.3)
event(main,"OnMouseUp","LeftButton")
V.model.rotation=1.5
begin(main,10);move(main,40);near(V.model.rotation,1.8)
event(main,"OnMouseUp","LeftButton")
V.model.rotation=nil
begin(main,0);move(main,10);near(V.model.rotation,.71)
event(main,"OnMouseUp","LeftButton")
-- Placement changes only the selected bag. Right-drag remains a view gesture.
local moves,ended=0,0
V.bagPlacementEditing=true
function V:BeginBagPlacementDrag() return true end
function V:EndBagPlacementDrag() ended=ended+1 end
function V:MoveBagPlacement(dx,dy,height,rotation)
    near(dx,10);near(dy,-5);assert(height==272 and rotation==.71);moves=moves+1;return true
end
function frame:GetHeight() return 272 end
main.scale=2
begin(main,100,100);move(main,120,90);assert(moves==1);near(V.model.rotation,.71)
event(main,"OnMouseUp","LeftButton");assert(ended==1 and not main.placing)
begin(main,100,100,"RightButton");move(main,120,0);near(V.model.rotation,.81);assert(moves==1)
event(main,"OnMouseUp","RightButton");assert(not main.cursorX)
begin(main,0,0);event(main,"OnHide");assert(not main.placing and not main.cursorX)
print("PASS: preview drag mouse capture, scaled movement, both previews, buffer swaps, release/hide and rotation wrap ("..checks.." checks)")
