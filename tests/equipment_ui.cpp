#include "../native/EquipmentUI.h"
#include <array>
#include <cassert>
#include <iostream>
#include <limits>
#include <string>

struct Item {
    std::string icon,link;
    unsigned quality=0,count=0,durability=0,repairCost=0;
    bool cooldown=false;
    bool operator==(const Item& other) const {
        return icon==other.icon&&link==other.link&&quality==other.quality&&count==other.count&&
            durability==other.durability&&repairCost==other.repairCost&&cooldown==other.cooldown;
    }
};
struct Unit {
    std::array<Item*,19> equipped{},visible{};
};
// Fixtures follow the verified native control flow: icon prefers visible,
// tooltip prefers equipped and otherwise falls back to visible. The production
// dispatcher must send only the local inventory UI onto the existing fallback.
struct Client {
    Unit player,other;
    unsigned originalCalls=0;
    void* lastUnit=nullptr;
    int lastSlot=0;
    Item* lookup(Unit* unit,int slot,std::uintptr_t caller,bool ownerAvailable=true){
        auto original=[&](void* raw,int argument)->void*{
            ++originalCalls;lastUnit=raw;lastSlot=argument;
            if(!raw||argument<0||argument>=19)return nullptr;
            return static_cast<Unit*>(raw)->visible[argument];
        };
        return static_cast<Item*>(equipmentUIVisibleItem(unit,slot,caller,
            ownerAvailable?reinterpret_cast<std::uintptr_t>(&player):0,original));
    }
    const Item* texture(Unit& unit,int slot){
        const auto* visible=lookup(&unit,slot,0x4C8428);
        return visible?visible:unit.equipped[slot];
    }
    const Item* tooltip(Unit& unit,int slot){
        if(unit.equipped[slot])return unit.equipped[slot];
        return lookup(&unit,slot,0x533319);
    }
};
int main(){
    Client client;
    Item goggles{"goggles","item:10500:0:0:0",2,1,0,0,false};
    Item real{"helmet","item:7934:1505:0:0",3,1,21,123,true};
    const Item before=real;
    for(int slot=0;slot<19;++slot){
        client.player.visible[slot]=&goggles;
        client.other.visible[slot]=&goggles;
        // The reported case: cosmetic goggles over an empty equipment slot.
        assert(client.texture(client.player,slot)==nullptr);
        assert(client.tooltip(client.player,slot)==nullptr);
        assert(client.originalCalls==static_cast<unsigned>(slot)*5);

        // Real equipment wins, including its enchanted link and complete item
        // metadata. Hidden armor must not turn an equipped slot into an empty UI.
        client.player.equipped[slot]=&real;
        assert(client.texture(client.player,slot)==&real);
        assert(client.tooltip(client.player,slot)==&real);
        client.player.visible[slot]=nullptr;
        assert(client.texture(client.player,slot)==&real);
        assert(client.tooltip(client.player,slot)==&real);
        assert(real==before);

        // Equipment changes while a cosmetic selection stays active are read
        // fresh; no icon/tooltip cache can retain the previously equipped item.
        client.player.equipped[slot]=nullptr;
        client.player.visible[slot]=&goggles;
        assert(client.texture(client.player,slot)==nullptr);
        assert(client.tooltip(client.player,slot)==nullptr);

        // World/character/Closet models still use the cosmetic visible record.
        // Component composition and its delayed item-load callback call the
        // same getter at 5FB54C and 5ED8B3. These must retain cosmetic records.
        for(std::uintptr_t caller:{0x5FB551u,0x5ED8B8u,0x4C8427u}){
            assert(client.lookup(&client.player,slot,caller)==&goggles);
            assert(client.lastUnit==&client.player&&client.lastSlot==slot);
        }
        // Other players remain on the native inspection path.
        assert(client.texture(client.other,slot)==&goggles);
        assert(client.tooltip(client.other,slot)==&goggles);
        assert(client.lastUnit==&client.other&&client.lastSlot==slot);
        assert(client.player.visible[slot]==&goggles);
    }
    // Unknown owner and invalid slots are delegated unchanged rather than
    // pretending that a valid local equipment query was made.
    unsigned calls=client.originalCalls;
    for(std::uintptr_t caller:{0x4C8428u,0x533319u}){
        assert(client.lookup(&client.player,0,caller,false)==&goggles);
        assert(++calls==client.originalCalls);
        assert(client.lookup(nullptr,0,caller)==nullptr);
        assert(++calls==client.originalCalls&&client.lastUnit==nullptr);
        for(int slot:{-1,19,20,23,std::numeric_limits<int>::min(),std::numeric_limits<int>::max()}){
            assert(client.lookup(&client.player,slot,caller)==nullptr);
            assert(++calls==client.originalCalls&&client.lastUnit==&client.player&&client.lastSlot==slot);
        }
    }
    for(std::uintptr_t caller:{0u,0x4C8429u,0x533318u,0x53331Au}){
        assert(client.lookup(&client.player,0,caller)==&goggles);
        assert(++calls==client.originalCalls);
    }
    std::cout<<"Equipment UI: all 19 slots, empty/custom/hidden gear, equipped metadata, equipment changes, model/other-player isolation and exact passthrough passed\n";
}
