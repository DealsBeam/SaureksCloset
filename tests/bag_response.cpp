#include <cassert>
#include <cmath>
#include <iostream>
#include "../native/BagResponse.h"
static const BagMatrix identity{{1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1}};
static std::array<float,3> point(const BagMatrix& pose,float z){
    return {{pose[12]+z*pose[8],pose[13]+z*pose[9],pose[14]+z*pose[10]}};
}
static BagMatrix step(BagResponse& state,unsigned time,const BagResponseProfile& profile,
                      float flight=0,BagMatrix pose=identity,std::array<float,3> up={{0,0,1}},unsigned fit=1){
    updateBagResponse(state,pose,1,time,1,fit,profile,up,flight);return pose;
}
int main(){
    const auto cloth=bagResponseProfile("cloth"),leather=bagResponseProfile("leather");
    BagResponse soft,stiff;
    auto pose=step(soft,0,cloth);
    for(unsigned time=16;time<200;time+=16){pose=step(soft,time,cloth);assert(!soft.ready&&soft.builds==0&&pose==identity);}
    for(unsigned time=208;time<=2000;time+=16){
        pose=step(soft,time,cloth);step(stiff,time,leather);
        assert(pose==identity); // Whole-bag placement is never stretched or sheared.
    }
    assert(soft.ready&&soft.builds==1&&stiff.ready&&stiff.builds==1);
    assert(soft.offset[2]<-.09f*cloth.height&&stiff.offset[2]>-.03f*leather.height);
    assert(std::fabs(soft.offset[0])<1e-6&&std::fabs(soft.offset[1])<1e-6);
    const auto palette=bagResponseMatrices(soft,identity);
    assert(palette[0]==identity&&palette[1][14]<-.08f); // Front/bottom fabric sags.
    for(unsigned x=0;x<3;++x)for(unsigned y=0;y<4;++y){
        assert(palette[1+(x*4+y)*5+4]==identity); // Top plane is pinned.
        if(x==2)for(unsigned z=0;z<5;++z)assert(palette[1+(x*4+y)*5+z]==identity); // Rear panel is pinned.
    }
    assert(std::fabs(palette[3][14]-.5f*palette[1][14])>.01f); // A global affine stretch cannot reproduce this field.
    // Flap and body share the same spatial field, with no independent phase or
    // motion multiplier that could pull overlapping layers through one another.
    const std::array<float,3> flapPoint{{-.45f,0,-.2f}},bodyPoint=flapPoint;
    assert(bagResponseField(cloth,flapPoint)==bagResponseField(cloth,bodyPoint));
    pose=step(soft,2000,cloth);const auto again=step(soft,2000,cloth);
    assert(pose==again); // Duplicate draws cannot advance or accumulate deformation.

    // World gravity follows a sideways player without becoming bag-local down.
    BagResponse sideways;
    for(unsigned time=0;time<=2000;time+=16)pose=step(sideways,time,cloth,0,identity,{{1,0,0}});
    assert(sideways.offset[0]<-.09f*cloth.height&&std::fabs(sideways.offset[2])<1e-6);
    const auto sidewaysPin=point(pose,cloth.top);
    assert(std::fabs(sidewaysPin[0])<1e-6&&std::fabs(sidewaysPin[2]-cloth.top)<1e-6);

    // Fit edits invalidate only this instance and build once after editing stops.
    for(unsigned time=2100;time<2400;time+=16){
        pose=step(soft,time,cloth,0,identity,{{0,0,1}},time);
        assert(!soft.ready&&soft.builds==1&&pose==identity);
    }
    step(soft,2400,cloth,0,identity,{{0,0,1}},99);
    step(soft,2500,cloth,0,identity,{{0,0,1}},99);assert(!soft.ready);
    step(soft,2600,cloth,0,identity,{{0,0,1}},99);assert(soft.ready&&soft.builds==2&&stiff.builds==1);

    // Same bone rotation, distinct fitted mounting points: the remote point
    // has different velocity/acceleration and thus a different response.
    BagResponse near,far;float difference=0;
    for(unsigned time=0;time<=3000;time+=16){
        const float angle=.12f*std::sin(time*.01f);
        auto a=identity;a[0]=a[5]=std::cos(angle);a[1]=std::sin(angle);a[4]=-a[1];
        auto b=a;b[12]=.8f*std::cos(angle);b[13]=.8f*std::sin(angle);
        step(near,time,cloth,0,a);step(far,time,cloth,0,b);
        difference=std::fmax(difference,std::fabs(near.offset[1]-far.offset[1]));
    }
    assert(difference>.002f&&near.builds==1&&far.builds==1);

    // A continuous falling driver settles once, regardless of body clip loops.
    BagResponse flight;float previous=0,largestStep=0;
    for(unsigned time=0;time<=6000;time+=16){
        const float falling=time<1000?0:time<2000?-.9f+1.9f*(time-1000)/1000.f:time<4000?1:0;
        pose=step(flight,time,cloth,falling);
        largestStep=std::fmax(largestStep,std::fabs(flight.offset[2]-previous));previous=flight.offset[2];
        assert(pose==identity&&std::isfinite(flight.localOffset[2]));
        if(time>=3200&&time<4000)assert(flight.offset[2]>.059f*cloth.height);
    }
    assert(largestStep<.018f&&flight.offset[2]<-.099f*cloth.height&&flight.builds==1);
    BagResponse terminalFall;
    for(unsigned time=0;time<=4000;time+=16){
        auto world=identity;world[14]=-60.f*time*.001f;
        step(terminalFall,time,cloth,1,world);
    }
    assert(terminalFall.ready&&terminalFall.builds==1&&terminalFall.offset[2]>.059f*cloth.height);
    // Exact damping remains bounded at low FPS and independent of frame rate
    // for a stationary load after cache creation.
    BagResponse fast,slow;
    for(unsigned time=0;time<=4000;time+=10)step(fast,time,cloth,1);
    for(unsigned time=0;time<=4000;time+=50)step(slow,time,cloth,1);
    assert(std::fabs(fast.offset[2]-slow.offset[2])<.00001f);
    pose=step(fast,8000,cloth,1);assert(pose==identity&&fast.builds==1); // Pause resets momentum.
    std::cout<<"PASS: local response pins top/rear, sags nonuniformly, respects material/gravity, caches fits, and settles jumps/falls without clips\n";
}
