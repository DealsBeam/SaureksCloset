// Size-sensitive motion must stay smooth on an animated hip, including the
// last saved slot's longer phase delay. Measure the emitted placement, not
// only spring state: a previous final-pose correction bypassed its limits.
#include <array>
#include <cassert>
#include <cmath>
#include <iostream>
#include "../native/BagPlacement.h"

static constexpr float pi=3.14159265358979323846f;
static const BagMatrix identity{{1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1}};
static constexpr std::array<float,4> sizes{{25,40,70,85}};
static void near(float a,float b,float tolerance=.00001f){
    assert(std::isfinite(a)&&std::isfinite(b)&&std::fabs(a-b)<=tolerance);
}
static std::array<BagTuningEntry,16> hipFit(unsigned hip,float size){
    std::array<BagTuningEntry,16> fits{};
    fits[1].enabled=true;
    assert(bagInstanceTuningDefaults(hip,1,1,fits[1].values));
    fits[1].values.scale=size;
    return fits;
}
struct MotionStats {float travel=0,speed=0,acceleration=0,angle=0,fabricTravel=0;};
static MotionStats runningHip(unsigned hip,float size,unsigned id,const char* material="cloth"){
    auto fits=hipFit(hip,size);
    const auto anchor=bagFits[1].anchor;
    const auto profile=bagResponseProfile(material);
    const float scale=.45f*size/100.f,height=1.239f*scale;
    BagMotion motion;BagResponse response;MotionStats stats;
    float previous=0,previousSpeed=0,lowFabric=1,highFabric=-1;
    for(unsigned time=0;time<=9000;time+=8){
        // Modest 2.8Hz gait with a small second harmonic. The hip is 18cm
        // off-axis, so a six-degree torso roll also moves its support point.
        const float t=std::fmin(time,6000u)*.001f;
        const float roll=.10472f*std::sin(2*pi*2.8f*t),c=std::cos(roll),s=std::sin(roll);
        BagMatrix torso{{1,0,0,0,0,c,s,0,0,-s,c,0,0,0,0,1}},mount=torso;
        for(unsigned axis=0;axis<3;++axis)mount[12+axis]=anchor[axis];
        mount[13]+=hip==1?.18f:-.18f;
        mount[14]+=.025f*std::sin(2*pi*2.8f*t)+.005f*std::sin(2*pi*5.6f*t)+.18f*s;
        BagMatrix fitted{},output{};
        assert(bagPlacement(mount,torso,identity,anchor,fitted,12,nullptr,0,0,false,
            nullptr,nullptr,0,fits.data(),hip,id));
        assert(bagPlacement(mount,torso,identity,anchor,output,12,&motion,time,123,true,
            nullptr,nullptr,0,fits.data(),hip,id,&response,&profile));
        // Rotation moves the bag center naturally; only the strap contact
        // may give vertically. Measure that contact when checking snap limits.
        const float offset=(output[14]+profile.top*output[10]-fitted[14]-profile.top*fitted[10])/height;
        const float speed=(offset-previous)/.008f,acceleration=(speed-previousSpeed)/.008f;
        if(time>=1000&&time<6000){
            stats.travel=std::fmax(stats.travel,std::fabs(offset));
            stats.speed=std::fmax(stats.speed,std::fabs(speed));
            stats.acceleration=std::fmax(stats.acceleration,std::fabs(acceleration));
            const float dot=std::fmin(1.f,std::fabs(bagRotationDot(bagRotation(fitted,scale),bagRotation(output,scale))));
            stats.angle=std::fmax(stats.angle,2*std::acos(dot));
            const auto controls=bagResponseMatrices(response,fitted);
            const float fabric=(controls[1][14]-fitted[14])/(profile.height*scale);
            near(controls[5][14],fitted[14]); // Upper fabric stays pinned.
            lowFabric=std::fmin(lowFabric,fabric);highFabric=std::fmax(highFabric,fabric);
            // The old delayed absolute hip position reached +/-10% height
            // and >11 heights/s for the size25 last-slot bag.
            assert(std::fabs(offset)<.041f);
            assert(std::fabs(speed)<1.f);
            assert(std::fabs(acceleration)<45.f);
        }
        if(time>=8500){
            // Rest must settle even when the movement flag remains set.
            for(unsigned element=0;element<16;++element)near(output[element],fitted[element]);
            near(response.offset[2]/(profile.height*scale),-profile.sag,.0001f);
        }
        previous=offset;previousSpeed=speed;
    }
    stats.fabricTravel=highFabric-lowFabric;
    return stats;
}
static void smallerBagsMoveLess(){
    for(unsigned hip:{1u,2u})for(const char* material:{"cloth","leather"}){
        std::array<std::array<MotionStats,5>,4> stats{};
        for(unsigned size=0;size<sizes.size();++size)for(unsigned slot=0;slot<5;++slot){
            auto& current=stats[size][slot]=runningHip(hip,sizes[size],201+slot,material);
            assert(current.travel>.0001f&&current.fabricTravel>.0001f);
            if(size){
                const auto& smaller=stats[size-1][slot];
                // Less absolute travel, not a second reduction in the
                // fraction of bag height that is allowed to move.
                assert(current.travel*sizes[size]>smaller.travel*sizes[size-1]*1.04f);
                assert(current.speed*sizes[size]>smaller.speed*sizes[size-1]*1.04f);
                assert(current.acceleration*sizes[size]>smaller.acceleration*sizes[size-1]);
                // Angular correction relative to the current body includes
                // phase difference, so it is not a measure of sway amplitude.
                // Preserve full timing on small bags; test their reduced
                // spring rotation on the undelayed slot instead.
                if(slot==0)assert(current.angle>smaller.angle*1.04f);
                assert(current.fabricTravel>=smaller.fabricTravel*.99f);
            }
            if(slot){
                // A phase delay can change timing, but cannot introduce a
                // faster catch-up stroke than the original smooth spring.
                const auto& first=stats[size][0];
                assert(current.travel<=first.travel*1.02f);
                assert(current.speed<=first.speed*1.05f);
                assert(current.acceleration<=first.acceleration*1.08f);
            }
        }
    }
}
static void jumpLiftSurvivesEverySize(){
    const auto anchor=bagFits[1].anchor;
    for(unsigned hip:{1u,2u})for(unsigned id=201;id<=205;++id){
        std::array<BagMotion,4> motion{};
        std::array<std::array<BagTuningEntry,16>,4> fits{};
        for(unsigned i=0;i<sizes.size();++i)fits[i]=hipFit(hip,sizes[i]);
        for(unsigned time=0;time<=3200;time+=8){
            const float jump=time>=512&&time<1600?1.f:0.f;
            BagMatrix reference{};float referenceScale=0;
            for(unsigned i=0;i<sizes.size();++i){
                const float scale=.45f*sizes[i]/100.f;
                BagMatrix output{},fitted{};
                assert(bagPlacement(identity,identity,identity,anchor,fitted,12,nullptr,0,0,false,
                    nullptr,nullptr,0,fits[i].data(),hip,id));
                assert(bagPlacement(identity,identity,identity,anchor,output,12,&motion[i],time,123,false,
                    nullptr,nullptr,jump,fits[i].data(),hip,id));
                near(motion[i].airborneWeight,motion[0].airborneWeight);
                if(i){
                    for(unsigned column=0;column<3;++column)for(unsigned row=0;row<3;++row)
                        near(output[column*4+row]/scale,reference[column*4+row]/referenceScale);
                    for(unsigned row=0;row<3;++row)
                        near((output[12+row]-fitted[12+row])/scale,reference[12+row]/referenceScale);
                }else{
                    reference=output;referenceScale=scale;
                    for(unsigned row=0;row<3;++row)reference[12+row]-=fitted[12+row];
                }
                if(time>=1400&&time<1600){
                    assert(motion[i].airborneWeight>.99f);
                    // Original 40-degree gravity-relative swing, including
                    // upward and outward travel, survives the size control.
                    const float angle=std::acos(std::fmin(1.f,output[10]/scale));
                    near(angle,40*pi/180*motion[i].airborneWeight,.00002f);
                    assert(output[14]>fitted[14]);
                    assert((output[13]-fitted[13])*(hip==1?1.f:-1.f)>0);
                }
                if(time>=3100){
                    near(motion[i].airborneWeight,0);
                    for(unsigned element=0;element<16;++element)near(output[element],fitted[element]);
                }
            }
        }
    }
}
int main(){
    smallerBagsMoveLess();
    jumpLiftSurvivesEverySize();
    std::cout<<"bag size motion tests passed (both hips, five slots, four sizes, cloth/leather, jump lift)\n";
}
