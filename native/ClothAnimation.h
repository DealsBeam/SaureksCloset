#pragma once
#include <algorithm>
#include <cstring>
// Exact build-5875 playback for exported cloth only. V1 remains Run-compatible;
// V2 adds finite takeoff/landing and settle-and-hold airborne deformation.
struct ClothAnimationClip { unsigned animation=0,index=0,duration=0;bool looping=false; };
struct ClothAnimationResource {
    unsigned duration=0,version=0,count=0;
    std::array<ClothAnimationClip,7> clips{};
};
static const ClothAnimationClip* clothAnimationClip(const ClothAnimationResource& resource,unsigned animation){
    for(unsigned i=0;i<resource.count&&i<resource.clips.size();++i)
        if(resource.clips[i].animation==animation)return &resource.clips[i];
    return nullptr;
}
static bool clothAnimationResource(std::uintptr_t model,unsigned id,ClothAnimationResource& out){
    // Leather/canvas catalog entries cannot opt in by sharing a marker alone.
    if(id!=12&&id!=13&&id!=14&&id!=16)return false;
    const auto* asset=bagAsset(id);
    if(!asset||!asset->material||std::strcmp(asset->material,"cloth"))return false;
    std::uintptr_t data=0,header=0,name=0,sequences=0,lookup=0;
    unsigned size=0,bones=0,count=0,lookupCount=0,version=0;
    static constexpr char marker[]="ClosetClothV1";
    if(!read(model+0x30,data)||!data||!read(data+0x130,header)||!header||
       !read(header+8,size)||size!=sizeof(marker)||!read(header+12,name)||!name||
       !read(header+0x34,bones)||bones<2||bones>256||
       !read(header+0x1c,count)||!read(header+0x20,sequences)||!sequences||
       !read(header+0x24,lookupCount)||!read(header+0x28,lookup)||!lookup)return false;
    for(unsigned i=0;i<sizeof(marker);++i){
        unsigned char value=0;if(!read(name+i,value))return false;
        if(i==sizeof(marker)-2){if(value!='1'&&value!='2')return false;version=value-'0';}
        else if(value!=static_cast<unsigned char>(marker[i]))return false;
    }
    if(count!=(version==1?2u:7u)||lookupCount!=(version==1?6u:188u))return false;
    static constexpr unsigned ids[]={0,5,37,38,39,40,187};
    ClothAnimationResource result;result.version=version;result.count=count;
    unsigned previousEnd=0;
    for(unsigned i=0;i<count;++i){
        std::uint16_t index=0,animation=0;unsigned start=0,end=0,flags=0,blend=0;
        const auto sequence=sequences+68*i;
        if(!read(lookup+ids[i]*2,index)||index!=i||!read(sequence,animation)||animation!=ids[i]||
           !read(sequence+4,start)||!read(sequence+8,end)||!read(sequence+16,flags)||!read(sequence+32,blend)||
           blend!=120||flags!=(i<2?0u:1u)||end<=start||end-start>(i==0?1u:i==1?2000u:10000u)||
           start!=(i==0?0u:(previousEnd/1000+1)*1000))return false;
        result.clips[i]={ids[i],i,end-start,i<2};previousEnd=end;
    }
    result.duration=result.clips[1].duration;out=result;return true;
}
struct ClothParentAnimation { unsigned animation=0,time=0,duration=0; };
[[maybe_unused]] static bool clothParentAnimation(std::uintptr_t parent,ClothParentAnimation& out){
    std::uintptr_t states=0,data=0,header=0,sequences=0;
    unsigned index=0,time=0,count=0,start=0,end=0;std::uint16_t animation=0;
    // 0x714633 commits the root's already-evaluated sequence/time before
    // recursive child updates at 0x71875C. No wall-clock gait is invented.
    if(!read(parent+0x90,states)||!states||!read(states+0x98,time)||!read(states+0x9c,index)||
       !read(parent+0x30,data)||!data||!read(data+0x130,header)||!header||
       !read(header+0x1c,count)||!count||count>4096||index>=count||
       !read(header+0x20,sequences)||!sequences)return false;
    const auto sequence=sequences+68*index;
    if(!read(sequence,animation)||!read(sequence+4,start)||!read(sequence+8,end)||
       end<=start||time<start||time>end)return false;
    out={animation,time-start,end-start};return true;
}
struct ClothPlayback { unsigned animation=0,offset=0; };
[[maybe_unused]] static ClothPlayback clothPlayback(const ClothAnimationResource& resource,const ClothParentAnimation* parent,
                                  bool running,bool airborne,bool flightReady,unsigned flightElapsed,bool launchedFlight){
    unsigned animation=0;bool flightClock=false;
    if(airborne&&resource.version>=2){
        if(parent&&parent->animation==37)animation=37;
        else if(flightReady){
            // Both caches begin at native flight time zero. Keep the launch
            // history when the body changes Jump to Fall; a walk-off uses the
            // direct-drop cache even if the body happens to display Jump.
            animation=launchedFlight?38:40;flightClock=true;
        }
    }else if(!airborne&&parent){
        if(resource.version>=2&&(parent->animation==39||parent->animation==187))animation=parent->animation;
        else if(running&&parent->animation==5)animation=5;
    }
    const auto* clip=clothAnimationClip(resource,animation);
    if(!clip||!animation)return {};
    if(flightClock)return {animation,std::min(flightElapsed,clip->duration)};
    if(!parent||!parent->duration)return {};
    const auto time=clip->looping?parent->time%parent->duration:std::min(parent->time,parent->duration);
    return {animation,static_cast<unsigned>(static_cast<std::uint64_t>(time)*clip->duration/parent->duration)};
}
static void clothSetPlayback(void* child,const ClothAnimationResource& resource,unsigned animation,unsigned offset,bool allowBlend){
    const auto* target=clothAnimationClip(resource,animation);
    if(!target)return;
    offset=target->looping?offset%target->duration:std::min(offset,target->duration);
    std::uintptr_t states=0;unsigned current=0,index=0;
    const auto model=reinterpret_cast<std::uintptr_t>(child);
    // Native GetSequence (0x712090) returns root state +0xF8. Validate its
    // scheduled sequence index too before preserving the current blend.
    const bool stateReady=read(model+0x90,states)&&states&&read(states+0xF8,current)&&read(states+0xA4,index);
    const auto* previous=stateReady?clothAnimationClip(resource,current):nullptr;
    const bool ready=previous&&index==previous->index;
    if(ready&&current==animation&&allowBlend){
        // Offset-only 0x7127F0 preserves secondary state and the blend deadline.
        modelSequenceOffset(child,-1,offset);
    }else{
        // Unsupported bodies/placements and previews clear a remaining tail.
        modelSequenceTime(child,-1,animation,0,offset,1.f,ready&&allowBlend?1u:0u,1);
    }
}
