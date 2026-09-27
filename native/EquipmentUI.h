#pragma once
#include <cstdint>

// Build 5875 GetInventoryItemTexture and GameTooltip:SetInventoryItem each
// consult the player's visible-item record, which can contain cosmetic armor.
// The texture API already has an actual-inventory fallback. The tooltip checks
// actual inventory first and only reaches this call when that slot is empty.
// Suppressing these two UI reads therefore restores the client's own equipped
// item/empty-slot behavior without changing any inventory or appearance data.
inline bool equipmentUICaller(std::uintptr_t caller,int slot){
    return slot>=0&&slot<19&&(caller==0x4C8428||caller==0x533319);
}

// The renderer, model previews, and other players must retain the original
// visible-item lookup, including its exact arguments and return value.
template<class Lookup> void* equipmentUIVisibleItem(void* unit,int slot,
        std::uintptr_t caller,std::uintptr_t localPlayer,Lookup original){
    if(localPlayer&&reinterpret_cast<std::uintptr_t>(unit)==localPlayer&&equipmentUICaller(caller,slot))
        return nullptr;
    return original(unit,slot);
}
