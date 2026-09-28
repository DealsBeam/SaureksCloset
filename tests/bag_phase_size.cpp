// Measure the actual rendered orientation against a fixed rest pose. Measuring
// only the correction against this frame's moving mount hid a size-dependent
// phase regression: small bags were blended almost entirely back into sync.
#include <array>
#include <cassert>
#include <cmath>
#include <iostream>
#include "../native/BagPlacement.h"

static constexpr float pi=3.14159265358979323846f;
static constexpr float omega=2*pi/640.f;
static const BagMatrix identity{{1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1}};
static void near(float actual,float expected,float tolerance){
    assert(std::isfinite(actual)&&std::isfinite(expected));
    if(std::fabs(actual-expected)>tolerance)
        std::cerr<<"Expected "<<expected<<", received "<<actual<<"\n";
    assert(std::fabs(actual-expected)<=tolerance);
}
struct Wave {
    double sine=0,cosine=0,tipSine=0,tipCosine=0;
    float bounce=0;
    unsigned samples=0;
    void add(float angle,float tip,float vertical,unsigned time){
        const double s=std::sin(time*omega),c=std::cos(time*omega);
        sine+=angle*s;cosine+=angle*c;tipSine+=tip*s;tipCosine+=tip*c;
        bounce=std::fmax(bounce,std::fabs(vertical));++samples;
    }
    float phase()const{return std::atan2(cosine,sine);}
    float amplitude()const{return 2*std::hypot(sine,cosine)/samples;}
    float tipTravel()const{return 2*std::hypot(tipSine,tipCosine)/samples;}
};
static std::array<Wave,2> renderedPair(unsigned mount,float size){
    const auto anchor=bagFits[1].anchor;
    std::array<BagTuningEntry,16> fits{};
    fits[1].enabled=true;
    assert(bagInstanceTuningDefaults(mount,1,1,fits[1].values));
    fits[1].values.scale=size;
    const float scale=.45f*size/100.f;
    BagMatrix rest{};
    assert(bagPlacement(identity,identity,identity,anchor,rest,12,nullptr,0,0,false,
        nullptr,nullptr,0,fits.data(),mount,201));
    const auto restRotation=bagRotation(rest,scale);
    const BagQuaternion inverseRest{{-restRotation[0],-restRotation[1],-restRotation[2],restRotation[3]}};
    std::array<BagMotion,2> motion{};
    std::array<Wave,2> wave{};
    constexpr unsigned stop=7680;
    for(unsigned time=0;time<=stop+2000;time+=8){
        const bool moving=time<stop;
        // A 640ms gait, then idle breathing. The latter must not keep driving
        // a delayed wobble after the existing stop fade has settled.
        const float roll=moving?.10472f*std::sin(time*omega):.018f*std::sin((time-stop)*.004f);
        const float c=std::cos(roll),s=std::sin(roll);
        BagMatrix torso{{1,0,0,0,0,c,s,0,0,-s,c,0,0,0,0,1}},attachment=torso;
        for(unsigned axis=0;axis<3;++axis)attachment[12+axis]=anchor[axis];
        attachment[13]+=mount?.18f:0;
        attachment[14]+=moving?.025f*std::sin(time*omega):.002f*std::sin((time-stop)*.004f);
        BagMatrix fitted{};
        assert(bagPlacement(attachment,torso,identity,anchor,fitted,12,nullptr,0,0,false,
            nullptr,nullptr,0,fits.data(),mount,201));
        for(unsigned slot=0;slot<2;++slot){
            BagMatrix output{};
            assert(bagPlacement(attachment,torso,identity,anchor,output,12,&motion[slot],time,123,moving,
                nullptr,nullptr,0,fits.data(),mount,201+slot,nullptr,nullptr,0,moving));
            if(time>=2560&&moving){
                const auto relative=bagRotationProduct(bagRotation(output,scale),inverseRest);
                const float angle=2*std::atan2(relative[0],relative[3]);
                // This is a real lower bag vertex's lateral travel relative
                // to its center, including the emitted orientation and size.
                const float tip=-.6f*output[9];
                // Hip sway now hinges at the upper contact. Measure vertical
                // give there: the center also moves as the bag rotates.
                const float pivot=mount?.6195f:0;
                wave[slot].add(angle,tip,output[14]+pivot*output[10]-fitted[14]-pivot*fitted[10],time);
            }
            if(time>=stop+1500)
                for(unsigned element=0;element<16;++element)near(output[element],fitted[element],.000002f);
            // Re-rendering cannot advance the phase or add spring energy.
            BagMatrix duplicate{};
            assert(bagPlacement(attachment,torso,identity,anchor,duplicate,12,&motion[slot],time,123,moving,
                nullptr,nullptr,0,fits.data(),mount,201+slot,nullptr,nullptr,0,moving));
            for(unsigned element=0;element<16;++element)near(duplicate[element],output[element],.000001f);
        }
    }
    return wave;
}
int main(){
    assert(bagJiggleDelay(201)==0&&bagJiggleDelay(202)==80);
    for(unsigned mount:{0u,1u}){
        std::array<Wave,2> previous{};
        for(float size:{25.f,35.f,56.f,85.f}){
            const auto wave=renderedPair(mount,size);
            // Use full emitted waveforms, not angularOffset or the difference
            // from the live mounting bone. A timing-only shift retains amplitude.
            const float delay=(wave[0].phase()-wave[1].phase())/omega;
            near(delay,80.f,1.5f);
            near(wave[1].amplitude()/wave[0].amplitude(),1.f,.005f);
            assert(wave[0].amplitude()>.05f);
            for(unsigned slot=0;slot<2;++slot){
                assert(wave[slot].bounce>0);
                if(previous[slot].samples){
                    assert(wave[slot].tipTravel()>previous[slot].tipTravel()*1.2f);
                    assert(wave[slot].bounce>previous[slot].bounce*1.2f);
                }
            }
            assert(wave[1].bounce<=wave[0].bounce*1.01f);
            previous=wave;
        }
    }
    std::cout<<"bag phase/size tests passed (emitted phase, unchanged amplitude, small displacement, idle fade, duplicate renders)\n";
}
