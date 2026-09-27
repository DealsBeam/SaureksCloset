-- Build the real Body page with 1.12-shaped texture loading failures.
-- Build 5875 returns 1/nil from Texture:SetTexture. Button string setters
-- leave no region when their first file load fails; explicit regions survive.
table.getn=table.getn or function(t) return #t end
math.mod=math.mod or math.fmod
local custom="Interface\\AddOns\\SaureksCloset\\Textures\\BodyChevron.tga"
local mode="available"
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
    self.loaded=mode~="missing_all" and not (mode=="missing_custom" and value==custom)
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
for _,scenario in ipairs({"available","missing_custom","missing_all"}) do
    mode=scenario
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
    check(ok,"Body page must build when texture mode is "..scenario..": "..tostring(err))
    V.uiReady=true;V:RefreshBody()
    local count=0
    for key,row in pairs(V.bodyRows) do
        count=count+1
        for _,direction in ipairs({"previous","next"}) do
            local arrow=row[direction]
            local expected=direction=="previous" and -1 or 1
            check(arrow.width==24 and arrow.height==24,"Arrow keeps its full click target")
            local seen={}
            for _,state in ipairs({"Normal","Pushed","Disabled","Highlight"}) do
                local texture=arrow.states[state]
                check(texture and texture.kind=="Texture" and not seen[texture],"Each arrow keeps a distinct "..state.." region even if file loading fails")
                seen[texture]=true
                local size=scenario=="available" and 14 or 12
                check(texture.width==size and texture.height==size and texture.anchor,"Small glyph retains its own geometry independently of the 24px click target")
                local offset=state=="Pushed" and 1 or 0
                check(texture.anchor[1]=="CENTER" and texture.anchor[2]==arrow and texture.anchor[3]=="CENTER" and texture.anchor[4]==offset and texture.anchor[5]==-offset,"Both directions share the same centered baseline and one-pixel pressed offset")
                local tint=state=="Pushed" and .85 or state=="Disabled" and .5 or 1
                local alpha=state=="Disabled" and .45 or state=="Highlight" and .24 or 1
                check(texture.tint[1]==tint and texture.tint[2]==tint and texture.tint[3]==tint and texture.tint[4]==alpha,"State keeps the restrained chevron tint and opacity")
                if scenario=="available" then
                    local left=expected<0 and 1 or 0
                    check(texture.texture==custom and texture.loaded and table.getn(texture.texCoord)==4,"Available custom chevron uses the new asset with simple horizontal UVs")
                    check(texture.texCoord[1]==left and texture.texCoord[2]==1-left and texture.texCoord[3]==0 and texture.texCoord[4]==1,"Left chevron mirrors the right-facing source without rotating its baseline")
                elseif scenario=="missing_custom" then
                    local fallback="Interface\\MoneyFrame\\Arrow-"..(expected<0 and "Left" or "Right").."-Up"
                    check(texture.texture==fallback and texture.loaded,"Unavailable new art falls back to the correct native arrow")
                    check(table.getn(texture.texCoord)==4 and texture.texCoord[1]==0 and texture.texCoord[2]==1 and texture.texCoord[3]==0 and texture.texCoord[4]==1,"Native arrow is used without custom rotation")
                else
                    check(not texture.loaded,"Even total image failure keeps state regions without crashing construction")
                end
            end
            check(arrow.states.Highlight.blend=="ADD","Highlight retains additive blending")
            check(arrow.states.Disabled.tint[1]<arrow.states.Normal.tint[1],"Disabled arrow is visibly muted")
            local before=table.getn(cycles);click(arrow)
            check(table.getn(cycles)==before+1 and cycles[before+1][1]==key and cycles[before+1][2]==expected,"Arrow still cycles the intended body choice")
            arrow:Disable();click(arrow)
            check(table.getn(cycles)==before+1 and arrow.states.Disabled~=nil,"Disabled arrow retains its state and cannot cycle")
        end
    end
    check(count==7,"All seven Body rows survive texture loading failures")
    available=false;V:RefreshBody()
    for _,row in pairs(V.bodyRows) do
        check(row.previous.disabled and row.next.disabled,"Unavailable body renderer disables both arrows")
    end
end
print("PASS: "..checks.." Body arrow construction, texture fallback, callback and disabled-state checks")
