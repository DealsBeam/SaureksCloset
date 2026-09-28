-- Build the real Body page with 1.12-shaped texture loading failures.
-- Build 5875 returns 1/nil from Texture:SetTexture. Button string setters
-- leave no region when their first file load fails; explicit regions survive.
table.getn=table.getn or function(t) return #t end
math.mod=math.mod or math.fmod
local custom="Interface\\AddOns\\SaureksCloset\\Textures\\BodyArrow.tga"
local mode="available"
local customLoads=0
local methods={}
local function node(kind,name,parent)
    local result=setmetatable({kind=kind,name=name,parent=parent,scripts={},states={},shown=true}, {__index=methods})
    if name then _G[name]=result end
    return result
end
function CreateFrame(kind,name,parent,template)
    local result=node(kind,name,parent)
    if template=="UIPanelButtonTemplate2" then
        node("FontString",name.."Text",result)
        for _,part in ipairs({"Left","Middle","Right"}) do node("Texture",name..part,result) end
    end
    return result
end
function getglobal(name) return _G[name] end
function methods:CreateTexture(name) return node("Texture",name,self) end
function methods:CreateFontString(name) return node("FontString",name,self) end
function methods:GetName() return self.name end
function methods:GetFrameLevel() return self.level or (self.parent and self.parent:GetFrameLevel()+1) or 1 end
function methods:SetFrameLevel(value) self.level=value end
function methods:SetWidth(value) self.width=value end
function methods:SetHeight(value) self.height=value end
function methods:SetPoint(...) self.anchor={...} end
function methods:ClearAllPoints() self.anchor=nil end
function methods:SetAllPoints(parent) self.allPoints=parent or self.parent end
function methods:SetText(value) self.text=value end
function methods:SetTexture(value)
    self.texture=value
    if value==custom then customLoads=customLoads+1 end
    self.loaded=mode~="missing_all" and not (mode=="missing_custom" and value==custom) and not (mode=="intermittent" and value==custom and math.mod(customLoads,2)==1)
    return self.loaded and 1 or nil
end
function methods:SetVertexColor(...) self.tint={...} end
function methods:SetTexCoord(...) self.texCoord={...} end
function methods:SetScript(event,callback) self.scripts[event]=callback end
function methods:GetScript(event) return self.scripts[event] end
function methods:Enable() self.disabled=false end
function methods:Disable() self.disabled=true end
function methods:Show() self.shown=true end
function methods:Hide() self.shown=false end
for _,state in ipairs({"Normal","Pushed","Disabled","Highlight"}) do
    local key=state
    methods["Set"..state.."Texture"]=function(self,value,blend)
        if type(value)=="string" then
            local region=node("Texture",nil,self)
            value=region:SetTexture(value) and region or nil
        else
            assert(value and value.kind=="Texture" and value.parent==self,"Button state requires a texture region owned by that button")
        end
        self.states[key]=value
        if value then value.blend=blend end
    end
    methods["Get"..state.."Texture"]=function(self) return self.states[key] end
end
for _,key in ipairs({"SetFont","SetJustifyH","SetJustifyV","SetTextColor","SetBackdrop","SetBackdropColor","SetBackdropBorderColor","SetAlpha","SetBlendMode","EnableMouse"}) do
    methods[key]=function() end
end
GameTooltip={SetOwner=function() end,SetText=function() end,Show=function() end,Hide=function() end}
CloseDropDownMenus=function() end
VanityStudioRaces={}
for race=1,8 do VanityStudioRaces[race]={"Race "..race} end
local checks=0
local function check(condition,message) assert(condition,message);checks=checks+1 end
local function click(button)
    if button.disabled then return end
    local old=this;this=button;button.scripts.OnClick();this=old
end
local function event(button,name)
    local old=this;this=button;button.scripts[name]();this=old
end
local function same(a,b)
    if table.getn(a)~=table.getn(b) then return false end
    for i,value in ipairs(a) do if b[i]~=value then return false end end
    return true
end
local geometryPath=os.getenv("CLOSET_BODY_GEOMETRY")
local geometry=geometryPath and assert(io.open(geometryPath,"w"))
for _,scenario in ipairs({"available","missing_custom","intermittent","missing_all"}) do
    mode=scenario;customLoads=0
    VanityStudio={};dofile("addon/SaureksCloset/UI.lua")
    local V=VanityStudio
    V.frame=CreateFrame("Frame","BodyArrowRegressionMain")
    local page=CreateFrame("Frame",nil,V.frame)
    local available=true
    local cycles={}
    function V:CycleBody(key,direction) table.insert(cycles,{key,direction}) end
    function V:BodyDraft() return {race=1,sex=0,skin=0,face=0,hairStyle=0,hairColor=0,facial=0} end
    function V:BodyAvailable() return available end
    function V:UsingTrueModel() return false end
    function V:BodyValues() return {0,1,2} end
    local ok,err=pcall(V.CreateBodyPage,V,page)
    check(ok,"Body page must build in "..scenario..": "..tostring(err))
    V.uiReady=true;V:RefreshBody()
    local count=0
    for key,row in pairs(V.bodyRows) do
        count=count+1
        local left,right=row.previous,row.next
        local resting=left.bodyGlyph or left.states.Normal
        local held=left.bodyGlyph or left.states.Pushed
        check(resting.anchor[5]==held.anchor[5],"Holding an arrow must not shift its visible baseline relative to the other arrow")
        check(left.anchor[1]=="CENTER" and right.anchor[1]=="CENTER" and left.anchor[2]==row.button and right.anchor[2]==row.button,"Both arrows use the exact same center reference")
        check(left.anchor[4]==-right.anchor[4] and left.anchor[5]==right.anchor[5],"Arrows share one vertical coordinate and symmetric horizontal spacing")
        check(left.bodyGlyph.texture==right.bodyGlyph.texture and left.bodyGlyph.width==right.bodyGlyph.width and left.bodyGlyph.height==right.bodyGlyph.height,"A pair never mixes custom and fallback art or dimensions")
        for _,direction in ipairs({"previous","next"}) do
            local arrow=row[direction];local expected=direction=="previous" and -1 or 1
            local t=arrow.bodyGlyph;local size=scenario=="available" and 14 or 12
            check(arrow.width==24 and arrow.height==24,"Click area remains large")
            check(t and t.kind=="Texture" and t.parent==arrow,"Missing images cannot remove the retained glyph region")
            check(not next(arrow.states),"No native button state texture can apply another layout or pressed offset")
            check(t.width==size and t.height==size,"Visible glyph stays small")
            check(t.anchor[1]=="CENTER" and t.anchor[2]==arrow and t.anchor[3]=="CENTER" and t.anchor[4]==0 and t.anchor[5]==0,"Glyph shares the button center without a state offset")
            local u=expected<0 and 1 or 0
            local expectedUV={u,1-u,0,1}
            if scenario=="available" then
                expectedUV=expected<0 and {1,1,0,1,1,0,0,0} or {1,0,0,0,1,1,0,1}
            end
            check(same(t.texCoord,expectedUV),"Both gold arrows use the same rotation, mirrored only horizontally")
            check(t.texture==(scenario=="available" and custom or "Interface\\MoneyFrame\\Arrow-Right-Up"),"Every fallback uses the same right-facing native source")
            check(t.loaded==(scenario~="missing_all"),"All-missing textures remain safe")
            local anchor=t.anchor;local uv=t.texCoord
            local function unchanged(state)
                check(t.anchor==anchor and t.texCoord==uv and t.width==size and t.height==size,"State "..state.." changes no visible geometry")
                if geometry and scenario=="available" then
                    geometry:write(key,"\t",direction,"\t",state,"\t",arrow.anchor[4],"\t",arrow.anchor[5],"\t",size,"\t",size)
                    for _,coordinate in ipairs(uv) do geometry:write("\t",coordinate) end
                    geometry:write("\n")
                end
            end
            unchanged("normal");check(t.tint[1]==.9 and t.tint[4]==1,"Normal glyph is gold")
            event(arrow,"OnEnter");unchanged("hover");check(t.tint[1]==1,"Hover brightens without moving")
            event(arrow,"OnMouseDown");unchanged("pressed");check(t.tint[1]==.7,"Press changes tint rather than baseline")
            event(arrow,"OnMouseUp");unchanged("release")
            event(arrow,"OnLeave");unchanged("normal-again");check(t.tint[1]==.9,"Leaving restores the normal tint")
            local before=table.getn(cycles);click(arrow)
            check(table.getn(cycles)==before+1 and cycles[before+1][1]==key and cycles[before+1][2]==expected,"Click changes the intended option")
            arrow:Disable();arrow.closetEnabled=false;arrow:UpdateBodyGlyph();unchanged("disabled")
            check(t.tint[1]==.5 and t.tint[4]==.45,"Disabled state is dimmed without moving")
            click(arrow);check(table.getn(cycles)==before+1,"Disabled arrow cannot change appearance")
            arrow:Enable();arrow.closetEnabled=true;arrow:UpdateBodyGlyph()
            event(arrow,"OnMouseDown");event(arrow,"OnHide");unchanged("hidden-reset")
            check(not arrow.bodyPressed and not arrow.bodyHovered,"Hide cannot leave an arrow pressed")
        end
    end
    check(count==7,"All seven Body rows build")
    available=false;V:RefreshBody()
    for _,row in pairs(V.bodyRows) do
        check(row.previous.disabled and row.next.disabled,"Unavailable renderer disables both arrows")
        check(row.previous.bodyGlyph.tint[4]==.45 and row.next.bodyGlyph.tint[4]==.45,"Real RefreshBody updates both disabled glyphs")
    end
end
if geometry then geometry:close() end
print("PASS: "..checks.." Body arrow loading, cross-state alignment, callbacks and disabled checks")
