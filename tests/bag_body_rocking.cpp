// Stronger rocking must be driven by a moving anatomical mount, while the
// actual attachment point stays pinned and the response settles at rest.
#include <array>
#include <cassert>
#include <cmath>
#include <iostream>
#include "../native/BagCoordinates.h"
#include "../native/BagMotion.h"

static constexpr float radians=.01745329252f;
static const BagMatrix identity{{1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1}};
static void near(float a,float b,float tolerance=.00005f){
    assert(std::isfinite(a)&&std::isfinite(b)&&std::fabs(a-b)<=tolerance);
}
static float difference(const BagMatrix& a,const BagMatrix& b,float scale){
    const float dot=std::fmin(1.f,std::fabs(bagRotationDot(bagRotation(a,scale),bagRotation(b,scale))));
    return 2*std::acos(dot);
}
struct RockingStats {float peak=0,rms=0,travel=0;};
static RockingStats exercise(float amplitude,float frequency,float percent,unsigned interval,unsigned id){
    constexpr float pivot=.47f;
    const float scale=.45f*percent/100;
    BagMotion state;RockingStats stats;unsigned samples=0;
    for(unsigned time=0;time<=8000;time+=interval){
        const float t=std::fmin(time,4000u)*.001f;
        const float angle=amplitude*std::sin(t*frequency),c=std::cos(angle),s=std::sin(angle);
        // Three-axis translation deliberately includes rapid vertical travel;
        // it may drive fabric, but cannot pull the attachment off the body.
        const BagMatrix fitted{{scale,0,0,0,0,scale*c,scale*s,0,0,-scale*s,scale*c,0,
            .18f*std::sin(t*8.f),.1f*std::cos(t*7.f),.24f+.12f*std::sin(t*11.f),1}};
        auto output=fitted;
        smoothBagMotion(state,output,scale,time,12,47,true,pivot,{{0,0,1}},nullptr,0,id,time<4000,true);
        for(float value:output)assert(std::isfinite(value));
        for(unsigned axis=0;axis<3;++axis)
            near(output[12+axis]+pivot*output[8+axis],fitted[12+axis]+pivot*fitted[8+axis],.000001f);
        const float delta=difference(output,fitted,scale);
        // A large reaction remains bounded rather than following frame rate
        // or producing a complete flip at an animation transition.
        assert(delta<30.01f*radians);
        if(time>=1000&&time<4000){
            stats.peak=std::fmax(stats.peak,delta);stats.rms+=delta*delta;++samples;
            stats.travel=std::fmax(stats.travel,std::fabs(output[13]-fitted[13]));
        }
        const auto first=output;output=fitted;
        smoothBagMotion(state,output,scale,time,12,47,true,pivot,{{0,0,1}},nullptr,0,id,time<4000,true);
        for(unsigned i=0;i<16;++i)near(output[i],first[i],.000001f);
        if(time>=7800)for(unsigned i=0;i<16;++i)near(output[i],fitted[i],.00001f);
    }
    assert(samples);stats.rms=std::sqrt(stats.rms/samples);return stats;
}

int main(){
    for(unsigned id:{201u,202u,205u}){
        const auto gentle=exercise(.07f,6.f,85,8,id);
        const auto strong=exercise(.5f,12.f,85,8,id);
        assert(strong.peak>gentle.peak*2.f);
        assert(strong.rms>gentle.rms*2.f);
        assert(strong.peak>3.2f*radians&&strong.travel>.001f);
        // Integration and phase history must remain smooth at lower FPS.
        for(unsigned interval:{16u,32u}){
            const auto slower=exercise(.5f,12.f,85,interval,id);
            assert(slower.rms>strong.rms*.7f&&slower.rms<strong.rms*1.3f);
            assert(slower.peak>strong.peak*.7f&&slower.peak<strong.peak*1.3f);
        }
    }
    // First slot isolates size-sensitive rocking from the inherited motion's
    // phase offset, whose timing intentionally remains independent of size.
    const auto small=exercise(.5f,12.f,35,8,201),large=exercise(.5f,12.f,85,8,201);
    assert(small.peak<large.peak*.75f&&small.rms<large.rms*.75f);
    assert(small.travel<large.travel*.5f);
    const auto stationary=exercise(0,12.f,85,8,205);
    near(stationary.peak,0,.001f);near(stationary.travel,0);
    std::cout<<"PASS: dramatic body movement drives stronger bounded rocking, upper contact remains pinned, small bags move less, idle settles and response remains stable across frame rates.\n";
}
