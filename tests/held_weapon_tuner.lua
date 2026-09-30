VanityStudio={slotNames={}}
local V=VanityStudio
local shown,refreshes=false,0
V.bagTunerWindow={IsShown=function() return shown end,Show=function() shown=true end,Hide=function() shown=false end}
V.frame={};V.HeldWeaponTuningAvailable=function() return true end
V.RefreshBagTunerUI=function() end
V.RefreshPreview=function() refreshes=refreshes+1 end
V.tab="weaponry"
dofile('addon/SaureksCloset/Weaponry.lua')
dofile('addon/SaureksCloset/BagTunerUI.lua')
V.RefreshBagTunerUI=function() end
for _,mode in ipairs({false,true}) do
    VanityStudioCharacter={weapons={carriedEnabled=mode}}
    for slot=108,110 do
        V:OpenPlacementTuner(slot)
        assert(shown and V.placementTunerSlot==slot)
        assert(V:WeaponPreviewMode()==0)
        shown=false;assert(V:WeaponPreviewMode()==0)
    end
end
assert(refreshes==6)
V.HeldWeaponTuningAvailable=function() return false end
V:OpenPlacementTuner(108);assert(not shown and refreshes==6)
print('PASS: held tuner opens all roles in both modes, keeps the preview stowed and gates older renderers')
