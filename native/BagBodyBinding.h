#pragma once
#include <cstdint>
#include <limits>
#include "BagCoordinates.h"

// Bind the chosen rest-space contact to the same skin weights as the nearby
// body. Keep this per bag; never cache a live bone-palette address or pose.
struct BagBodyBinding {
    bool ready=false,requested=false;
    std::uintptr_t header=0;
    BagMatrix rest{},pending{};
    float top=0,pendingTop=0;
    std::uint32_t changed=0;
    unsigned boneCount=0,builds=0;
    std::array<std::uint8_t,4> bones{},weights{};
};

static bool bagBodyRigidFrame(const BagMatrix& skin,BagMatrix& rigid){
    BagMatrix inverse;
    if(!bagAffineInverse(skin,inverse))return false;
    std::array<float,3> x{{skin[0],skin[1],skin[2]}},y{{skin[4],skin[5],skin[6]}},z{};
    const auto dot=[](const auto& a,const auto& b){return a[0]*b[0]+a[1]*b[1]+a[2]*b[2];};
    const float lx=std::sqrt(dot(x,x));
    if(!std::isfinite(lx)||lx<.00001f)return false;
    for(auto& v:x)v/=lx;
    const float projection=dot(x,y);
    for(unsigned i=0;i<3;++i)y[i]-=projection*x[i];
    const float ly=std::sqrt(dot(y,y));
    if(!std::isfinite(ly)||ly<.00001f)return false;
    for(auto& v:y)v/=ly;
    z={{x[1]*y[2]-x[2]*y[1],x[2]*y[0]-x[0]*y[2],x[0]*y[1]-x[1]*y[0]}};
    const float handedness=z[0]*skin[8]+z[1]*skin[9]+z[2]*skin[10];
    if(!std::isfinite(handedness)||handedness<.00001f)return false;
    rigid={{x[0],x[1],x[2],0,y[0],y[1],y[2],0,z[0],z[1],z[2],0,0,0,0,1}};
    return true;
}

static bool bagBindBodyPoint(BagBodyBinding& cache,std::uintptr_t parent,const BagMatrix& restBag,
                            float top,const BagMatrix& modelToRender,std::uint32_t now,BagMatrix& fittedModel){
    BagMatrix renderToModel,validation;
    if(!std::isfinite(top)||!bagAffineInverse(restBag,validation)||!bagAffineInverse(modelToRender,renderToModel))return false;
    std::array<float,3> contact{};
    for(unsigned axis=0;axis<3;++axis){
        contact[axis]=restBag[12+axis]+top*restBag[8+axis];
        if(!std::isfinite(contact[axis]))return false;
    }
    std::uintptr_t resource=0,header=0,palette=0;
    if(!read(parent+0x30,resource)||!resource||!read(resource+0x130,header)||!header||
       !read(parent+0x94,palette)||!palette)return false;
    if(cache.header!=header){
        const auto builds=cache.builds;cache={};cache.header=header;cache.builds=builds;
    }
    if(!cache.requested||cache.pending!=restBag||cache.pendingTop!=top){
        cache.pending=restBag;cache.pendingTop=top;cache.changed=now;cache.requested=true;
    }
    const bool changed=cache.rest!=restBag||cache.top!=top;
    if(!cache.ready||(changed&&static_cast<std::uint32_t>(now-cache.changed)>=150)){
        unsigned magic=0,version=0,vertexCount=0,boneCount=0,viewCount=0,indexCount=0,sectionCount=0;
        std::uintptr_t vertices=0,views=0,indices=0,sections=0;
        // Loaded MD20 arrays contain fixed-up pointers. Vertex bone bytes are
        // GLOBAL bone indices; only the separate draw-view properties remap.
        if(!read(header,magic)||magic!=0x3032444Du||!read(header+4,version)||version!=256||
           !read(header+0x34,boneCount)||!boneCount||boneCount>2048||
           !read(header+0x44,vertexCount)||!vertexCount||vertexCount>65536||
           !read(header+0x48,vertices)||!vertices||
           !read(header+0x4C,viewCount)||!viewCount||viewCount>16||!read(header+0x50,views)||!views||
           !read(views,indexCount)||!indexCount||indexCount>65536||!read(views+4,indices)||!indices||
           !read(views+24,sectionCount)||!sectionCount||sectionCount>512||!read(views+28,sections)||!sections)return false;
        float nearest=std::numeric_limits<float>::max();
        std::array<std::uint8_t,4> bestBones{},bestWeights{};
        bool found=false;
        for(unsigned section=0;section<sectionCount;++section){
            std::uint16_t geoset=0,first=0,count=0;
            const auto record=sections+32*section;
            if(!read(record,geoset))return false;
            // Geoset zero is the neutral body on every supported race/sex.
            // Hair, capes and hidden clothing variants must not win proximity.
            if(geoset!=0)continue;
            if(!read(record+4,first)||!read(record+6,count)||static_cast<unsigned>(first)+count>indexCount)return false;
            for(unsigned at=first;at<static_cast<unsigned>(first)+count;++at){
                std::uint16_t vertex=0;std::array<float,3> position{};
                if(!read(indices+2*at,vertex)||vertex>=vertexCount||!read(vertices+48*vertex,position))return false;
                float distance=0;
                for(unsigned axis=0;axis<3;++axis){const float d=position[axis]-contact[axis];distance+=d*d;}
                if(!std::isfinite(distance)||distance>=nearest)continue;
                std::array<std::uint8_t,4> bones{},weights{};unsigned total=0;
                for(unsigned i=0;i<4;++i){
                    if(!read(vertices+48*vertex+12+i,weights[i])||!read(vertices+48*vertex+16+i,bones[i]))return false;
                    total+=weights[i];
                    if(weights[i]&&bones[i]>=boneCount)return false;
                }
                if(total!=255)return false;
                nearest=distance;bestBones=bones;bestWeights=weights;found=true;
            }
        }
        if(!found)return false;
        cache.bones=bestBones;cache.weights=bestWeights;cache.boneCount=boneCount;
        cache.rest=restBag;cache.top=top;cache.ready=true;++cache.builds;
    }
    BagMatrix blended{};
    for(unsigned i=0;i<4;++i)if(cache.weights[i]){
        BagMatrix bone;
        if(cache.bones[i]>=cache.boneCount||!read(palette+64*cache.bones[i],bone)||!bagAffineInverse(bone,validation))return false;
        const float weight=cache.weights[i]/255.f;
        for(unsigned element=0;element<16;++element)blended[element]+=weight*bone[element];
    }
    const auto skin=bagMatrixProduct(renderToModel,blended);
    BagMatrix rigid;
    if(!bagBodyRigidFrame(skin,rigid))return false;
    auto result=bagMatrixProduct(rigid,restBag);
    for(unsigned axis=0;axis<3;++axis){
        const float liveContact=skin[12+axis]+skin[axis]*contact[0]+skin[4+axis]*contact[1]+skin[8+axis]*contact[2];
        result[12+axis]=liveContact-top*result[8+axis];
    }
    if(!bagAffineInverse(result,validation))return false;
    fittedModel=result;
    return true;
}
