#pragma once
#include "BagCoordinates.h"
#include "BagMotion.h"

// Outward lift from vertical motion at the actual skin-bound contact.
// No preset or independent oscillator chooses it; the bag stays rigid.
static void flopBagAtContact(BagMatrix& pose,const BagMatrix& fitted,
                             const std::array<float,3>& up,float top,float height,float bob,float scale,
                             BagMotion& motion,std::uint32_t now){
    if(!std::isfinite(bob)||!std::isfinite(height)||height<.00001f||scale<.00001f)return;
    const std::array<float,3> outward{{-fitted[0]/scale,-fitted[1]/scale,-fitted[2]/scale}};
    std::array<float,3> axis{{outward[1]*up[2]-outward[2]*up[1],
        outward[2]*up[0]-outward[0]*up[2],outward[0]*up[1]-outward[1]*up[0]}};
    const float length=std::sqrt(axis[0]*axis[0]+axis[1]*axis[1]+axis[2]*axis[2]);
    if(!std::isfinite(length)||length<.00001f)return;
    for(float& value:axis)value/=length;
    // Small bags have a short lever arm: reducing their angle as well as their
    // dimensions makes the lower edge barely move. Compensate angular response
    // only, without enlarging translation, stretching geometry or speeding time.
    const float sizeGain=std::fmax(1.f,std::fmin(2.f,std::sqrt((.45f*.85f)/scale)));
    const float lift=std::fmax(0.f,bob)/(height*.035f)*sizeGain;
    // Ease away from the body and return to rest, never kick inward through the
    // hip. The quadratic start joins with zero slope at lift=0; tanh bounds big
    // impulses smoothly. A horizontal-facing rear panel defines the hinge.
    const float response=lift*lift/(lift+.1f);
    const float wanted=10.f*.01745329252f*std::tanh(response)*std::fmin(1.f,length/.15f);
    // Smooth the half-cycle lift so a small bag never snaps off its resting
    // stop. Each bag owns this state; repeated draws cannot advance it twice.
    const auto elapsed=now-motion.flopTime;
    if(elapsed){
        motion.flopAngle+=(wanted-motion.flopAngle)*(1-std::exp(-std::fmin(float(elapsed),250.f)*.001f/.045f));
        motion.flopTime=now;
    }
    const float angle=motion.flopAngle;
    if(std::fabs(angle)<.00000001f)return;
    const auto original=pose;
    const float c=std::cos(angle),s=std::sin(angle);
    for(unsigned col=0;col<3;++col){
        const std::array<float,3> v{{original[col*4],original[col*4+1],original[col*4+2]}};
        const float dot=axis[0]*v[0]+axis[1]*v[1]+axis[2]*v[2];
        for(unsigned row=0;row<3;++row){
            const unsigned a=(row+1)%3,b=(row+2)%3;
            pose[col*4+row]=v[row]*c+(axis[a]*v[b]-axis[b]*v[a])*s+axis[row]*dot*(1-c);
        }
    }
    for(unsigned row=0;row<3;++row)pose[12+row]+=top*(original[8+row]-pose[8+row]);
}
