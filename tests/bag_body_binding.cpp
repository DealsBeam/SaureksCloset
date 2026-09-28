#include <cassert>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <limits>
#include <map>
#include <vector>
#include "../native/BagCoordinates.h"
static std::map<std::uintptr_t,std::vector<unsigned char>> memory;
static unsigned meshReads=0;
template<typename T> static void put(std::uintptr_t address,const T& value){
    auto& bytes=memory[address];bytes.resize(sizeof(T));std::memcpy(bytes.data(),&value,sizeof(T));
}
template<typename T> static bool read(std::uintptr_t address,T& value){
    if(address>=0x4000&&address<0x8000)++meshReads;
    const auto found=memory.find(address);
    if(found==memory.end()||found->second.size()!=sizeof(T))return false;
    std::memcpy(&value,found->second.data(),sizeof(T));return true;
}
#include "../native/BagBodyBinding.h"
static const BagMatrix identity{{1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1}};
static const std::array<float,3> hip{{-.1f,.2f,1.f}},foot{{.2f,-.2f,.05f}},joint{{0,0,.5f}};
static BagMatrix rotation(float angle){
    auto result=identity;result[0]=result[10]=std::cos(angle);result[2]=-std::sin(angle);result[8]=std::sin(angle);return result;
}
static std::array<float,3> transform(const BagMatrix& pose,const std::array<float,3>& point){
    std::array<float,3> result{};
    for(unsigned axis=0;axis<3;++axis)result[axis]=pose[12+axis]+pose[axis]*point[0]+pose[4+axis]*point[1]+pose[8+axis]*point[2];
    return result;
}
template<std::size_t N> static void close(const std::array<float,N>& a,const std::array<float,N>& b,float tolerance=.00001f){
    for(unsigned i=0;i<N;++i)assert(std::fabs(a[i]-b[i])<tolerance);
}
static BagMatrix fittedAt(const std::array<float,3>& contact,float top=.2f){
    auto result=rotation(.3f);
    for(unsigned i=0;i<3;++i){for(unsigned col=0;col<3;++col)result[col*4+i]*=.6f;result[12+i]=contact[i]-top*result[8+i];}
    return result;
}
static void vertex(unsigned index,const std::array<float,3>& position,std::array<std::uint8_t,4> bones,std::array<std::uint8_t,4> weights){
    put(0x4000+48*index,position);
    for(unsigned i=0;i<4;++i){put(0x4000+48*index+12+i,weights[i]);put(0x4000+48*index+16+i,bones[i]);}
}
static void fixture(){
    memory.clear();meshReads=0;
    put(0x1030,std::uintptr_t(0x2000));put(0x2130,std::uintptr_t(0x3000));put(0x1094,std::uintptr_t(0x8000));
    put(0x3000,0x3032444Du);put(0x3004,256u);put(0x3034,4u);
    put(0x3044,4u);put(0x3048,std::uintptr_t(0x4000));put(0x304c,1u);put(0x3050,std::uintptr_t(0x5000));
    put(0x5000,4u);put(0x5004,std::uintptr_t(0x6000));put(0x5018,2u);put(0x501c,std::uintptr_t(0x7000));
    for(unsigned i=0;i<4;++i)put(0x6000+2*i,std::uint16_t(i));
    put(0x7000,std::uint16_t(0));put(0x7004,std::uint16_t(0));put(0x7006,std::uint16_t(3));
    put(0x7020,std::uint16_t(1501));put(0x7024,std::uint16_t(3));put(0x7026,std::uint16_t(1));
    vertex(0,hip,{{1,0,0,0}},{{255,0,0,0}});
    auto nearFoot=foot;nearFoot[0]+=.005f;vertex(1,nearFoot,{{2,0,0,0}},{{255,0,0,0}});
    vertex(2,joint,{{1,2,0,0}},{{128,127,0,0}});
    vertex(3,foot,{{3,0,0,0}},{{255,0,0,0}}); // Hidden cape is closer but ineligible.
    for(unsigned i=0;i<4;++i)put(0x8000+64*i,identity);
}
static bool bind(BagBodyBinding& cache,const BagMatrix& rest,unsigned time,BagMatrix& result,const BagMatrix& render=identity,float top=.2f){
    return bagBindBodyPoint(cache,0x1000,rest,top,render,time,result);
}
int main(){
    fixture();BagBodyBinding cache;BagMatrix result;
    auto footBone=rotation(1.2f);footBone[12]=.3f;footBone[14]=.1f;put(0x8080,footBone);
    const auto footRest=fittedAt(foot);
    assert(bind(cache,footRest,0,result)&&cache.builds==1&&cache.bones[0]==2);
    close(result,bagMatrixProduct(footBone,footRest));
    close(transform(result,{{0,0,.2f}}),transform(footBone,foot)); // Contact never slides while foot swings.
    const auto meshAtBuild=meshReads;
    for(unsigned time=16;time<1000;time+=16){
        footBone=rotation(std::sin(time*.01f)*1.4f);put(0x8080,footBone);
        assert(bind(cache,footRest,time,result));close(result,bagMatrixProduct(footBone,footRest));
    }
    assert(meshReads==meshAtBuild&&cache.builds==1); // No repeated body scans during animation.

    const auto hipRest=fittedAt(hip);
    auto hipBone=rotation(-.8f);hipBone[13]=.2f;put(0x8040,hipBone);
    assert(bind(cache,hipRest,1000,result)&&cache.builds==1); // Drag uses previous support until fit settles.
    assert(bind(cache,hipRest,1149,result)&&cache.builds==1);
    assert(bind(cache,hipRest,1150,result)&&cache.builds==2&&cache.bones[0]==1);
    close(result,bagMatrixProduct(hipBone,hipRest));
    const auto hipPose=result;
    auto camera=rotation(.9f);camera[12]=80;camera[13]=-40;camera[14]=3;
    camera[0]*=-2;camera[1]*=-2;camera[2]*=-2; // Mirrored/scaled render basis cancels too.
    put(0x8040,bagMatrixProduct(camera,hipBone));
    assert(bind(cache,hipRest,1200,result,camera));close(result,hipPose);assert(cache.builds==2);

    fixture();cache={};
    const auto jointRest=fittedAt(joint);auto a=rotation(.7f),b=rotation(-.5f);a[13]=.1f;b[14]=-.2f;
    put(0x8040,a);put(0x8080,b);
    assert(bind(cache,jointRest,0,result));
    auto expectedContact=transform(a,joint),otherContact=transform(b,joint);
    for(unsigned i=0;i<3;++i)expectedContact[i]=(128*expectedContact[i]+127*otherContact[i])/255.f;
    close(transform(result,{{0,0,.2f}}),expectedContact); // Blended joint follows native skin, not dominant bone.
    for(unsigned column=0;column<3;++column){
        float length=0;for(unsigned i=0;i<3;++i)length+=result[column*4+i]*result[column*4+i];
        assert(std::fabs(length-.36f)<.00001f); // Skin blend cannot shrink the bag.
        for(unsigned other=column+1;other<3;++other){
            float dot=0;for(unsigned i=0;i<3;++i)dot+=result[column*4+i]*result[other*4+i];assert(std::fabs(dot)<.00001f);
        }
    }
    const auto saved=result;auto singular=identity;singular[0]=0;put(0x8040,singular);
    assert(!bind(cache,jointRest,16,result)&&result==saved);put(0x8040,a);
    memory.erase(0x8080);assert(!bind(cache,jointRest,32,result)&&result==saved);put(0x8080,b);
    assert(bind(cache,jointRest,48,result)&&cache.builds==1); // Transient palette readiness retries without mesh rebuild.
    a[0]=std::numeric_limits<float>::quiet_NaN();put(0x8040,a);assert(!bind(cache,jointRest,64,result));

    fixture();cache={};put(0x3044,65537u);assert(!bind(cache,footRest,0,result)&&!cache.ready);
    put(0x3044,4u);assert(bind(cache,footRest,1,result)&&cache.builds==1);
    fixture();cache={};put(0x6002,std::uint16_t(99));assert(!bind(cache,footRest,0,result));
    fixture();cache={};put(0x7006,std::uint16_t(5));assert(!bind(cache,footRest,0,result));
    fixture();cache={};put(0x3004,999u);assert(!bind(cache,footRest,0,result));
    fixture();cache={};put(0x4000+48+16,std::uint8_t(8));assert(!bind(cache,footRest,0,result));
    fixture();cache={};put(0x4000+48+12,std::uint8_t(200));assert(!bind(cache,footRest,0,result));
    fixture();cache={};put(0x7000,std::uint16_t(1501));assert(!bind(cache,footRest,0,result));
    fixture();cache={};assert(!bind(cache,footRest,0,result,identity,std::numeric_limits<float>::infinity()));
    fixture();cache={};assert(bind(cache,footRest,0,result));
    put(0x2130,std::uintptr_t(0x9000));assert(!bind(cache,footRest,16,result)&&!cache.ready); // Race/resource change invalidates support.
    put(0x2130,std::uintptr_t(0x3000));assert(bind(cache,footRest,32,result)&&cache.builds==2);
    fixture();cache={};assert(bind(cache,footRest,0xfffffff0u,result));
    assert(bind(cache,hipRest,0xfffffff1u,result)&&cache.builds==1);
    assert(bind(cache,hipRest,134u,result)&&cache.builds==1);
    assert(bind(cache,hipRest,135u,result)&&cache.builds==2); // Debounce survives clock wrap.
    const auto beforeDrag=meshReads;
    for(unsigned time=150;time<650;time+=16){
        auto moving=footRest;moving[12]+=.001f*time;
        assert(bind(cache,moving,time,result)&&cache.builds==2);
    }
    assert(meshReads==beforeDrag); // Long dragging does not repeatedly scan the body.
    assert(bind(cache,footRest,700,result)&&cache.builds==2);
    assert(bind(cache,footRest,850,result)&&cache.builds==3);
    const float changedTop=.6f;
    assert(bind(cache,footRest,900,result,identity,changedTop)&&cache.builds==3);
    assert(bind(cache,footRest,1050,result,identity,changedTop)&&cache.builds==4);
    fixture();cache={};put(0x1094,std::uintptr_t(0));assert(!bind(cache,footRest,0,result)&&!cache.ready);
    put(0x1094,std::uintptr_t(0x8000));assert(bind(cache,footRest,16,result)&&cache.builds==1);
    std::cout<<"PASS: body binding follows foot/hip skin, pins the exact contact, preserves bag size, cancels render transforms, caches fits and rejects invalid data\n";
}
