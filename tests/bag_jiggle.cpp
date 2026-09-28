// Time-based phase separation of secondary motion. The input comes from the
// actual attachment pose; a stationary attachment must never create a cycle.
#include <array>
#include <cassert>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <limits>
#include <set>
#include "../native/BagJiggle.h"
#include "../native/BagPlacement.h"

static const char* currentCase="";
static void near(float actual,float expected,float tolerance=.0001f){
    assert(std::isfinite(actual));
    if(std::fabs(actual-expected)>tolerance)
        std::cerr<<currentCase<<": expected "<<expected<<", received "<<actual<<"\n";
    assert(std::fabs(actual-expected)<=tolerance);
}

static void identityDelays(){
    assert(bagJiggleDelay(0)==0);
    assert(bagJiggleDelay(1)==0);
    assert(bagJiggleDelay(201)==0);
    std::set<unsigned> delays;
    for(unsigned id=201;id<=208;++id){
        const auto delay=bagJiggleDelay(id);
        assert(delay<=210);
        assert(delays.insert(delay).second);
        assert(bagJiggleDelay(id)==delay);
    }
    BagJiggleHistory<2> unchanged;
    for(unsigned time=0;time<100;++time){
        const std::array<float,2> driver{{time*.01f,-static_cast<float>(time)*.02f}};
        const auto result=delayedBagJiggle(unchanged,driver,time,201);
        near(result[0],driver[0]);near(result[1],driver[1]);
    }
}

static void phaseIsTimeNotAmplitude(){
    std::array<BagJiggleHistory<2>,8> histories{};
    constexpr float omega=2*3.14159265358979323846f/640;
    for(unsigned time=0;time<=2400;time+=5){
        const std::array<float,2> driver{{std::sin(time*omega),std::cos(time*omega)}};
        for(unsigned slot=0;slot<histories.size();++slot){
            const unsigned id=201+slot,delay=bagJiggleDelay(id);
            const auto result=delayedBagJiggle(histories[slot],driver,time,id);
            if(time<delay){near(result[0],0);near(result[1],0);}
            if(time<500)continue;
            near(result[0],std::sin((time-delay)*omega),.0015f);
            near(result[1],std::cos((time-delay)*omega),.0015f);
            // Both quadratures keep their amplitude, but their timing changes.
            near(std::hypot(result[0],result[1]),1,.0015f);
        }
    }
}

static void highAndIrregularFrameRates(){
    for(unsigned id=202;id<=208;++id){
        const unsigned delay=bagJiggleDelay(id);
        BagJiggleHistory<1> highRate;
        for(unsigned time=0;time<=800;++time){
            const auto result=delayedBagJiggle(highRate,std::array<float,1>{{time*.001f}},time,id);
            if(time>=300)near(result[0],(time-delay)*.001f);
        }
        BagJiggleHistory<1> irregular;
        constexpr unsigned steps[]={7,61,14,22,9,43};
        unsigned index=0;
        for(unsigned time=0;time<=2000;time+=steps[index++%6]){
            const auto result=delayedBagJiggle(irregular,std::array<float,1>{{time*.001f}},time,id);
            if(time>=300)near(result[0],(time-delay)*.001f);
        }
    }
}

static void duplicateRendersAndIndependentBags(){
    BagJiggleHistory<2> once,repeated,unrelated;
    for(unsigned time=0;time<=1000;time+=4){
        const std::array<float,2> driver{{std::sin(time*.01f),time*.001f}};
        const auto expected=delayedBagJiggle(once,driver,time,207);
        const auto actual=delayedBagJiggle(repeated,driver,time,207);
        for(unsigned repeat=0;repeat<20;++repeat){
            const auto duplicate=delayedBagJiggle(repeated,driver,time,207);
            for(unsigned channel=0;channel<2;++channel)near(duplicate[channel],actual[channel]);
        }
        // Other slots being added/removed must not renumber this bag's phase.
        if(time<300||time>600){
            if(time==604)unrelated={};
            delayedBagJiggle(unrelated,driver,time,203);
        }
        for(unsigned channel=0;channel<2;++channel)near(actual[channel],expected[channel]);
    }
}

static void timerWrapAndReset(){
    constexpr unsigned id=208;
    const auto delay=bagJiggleDelay(id);
    BagJiggleHistory<1> wrap;
    const std::uint32_t start=std::numeric_limits<std::uint32_t>::max()-80;
    for(unsigned elapsed=0;elapsed<=800;elapsed+=5){
        const auto result=delayedBagJiggle(wrap,std::array<float,1>{{elapsed*.001f}},start+elapsed,id);
        if(elapsed>=300)near(result[0],(elapsed-delay)*.001f);
    }
    const auto afterPause=delayedBagJiggle(wrap,std::array<float,1>{{3}},start+1100,id);
    near(afterPause[0],0);
    for(unsigned elapsed=5;elapsed<=300;elapsed+=5){
        const auto result=delayedBagJiggle(wrap,std::array<float,1>{{3}},start+1100+elapsed,id);
        if(elapsed<delay)near(result[0],0);
        if(elapsed>=delay)near(result[0],3);
    }
    // Reusing a removed slot's history for a new identity starts clean.
    const auto newIdentity=delayedBagJiggle(wrap,std::array<float,1>{{8}},start+1405,202);
    near(newIdentity[0],0);
}

static void stationaryAndNonfiniteDrivers(){
    BagJiggleHistory<3> state;
    const std::array<float,3> stationary{{0,0,0}};
    for(unsigned time=0;time<=1000;time+=5){
        const auto result=delayedBagJiggle(state,stationary,time,206);
        for(float value:result)near(value,0);
    }
    const float badValues[]={std::numeric_limits<float>::quiet_NaN(),
                             std::numeric_limits<float>::infinity(),
                             -std::numeric_limits<float>::infinity()};
    unsigned time=1005;
    for(float bad:badValues){
        const auto invalid=delayedBagJiggle(state,std::array<float,3>{{1,bad,2}},time,206);
        for(float value:invalid)near(value,0);
        time+=5;
        const auto fresh=delayedBagJiggle(state,std::array<float,3>{{1,2,3}},time,206);
        for(float value:fresh)near(value,0);
        time+=5;
    }
    const unsigned restart=time;
    for(;time<=restart+400;time+=5){
        const auto result=delayedBagJiggle(state,std::array<float,3>{{1,2,3}},time,206);
        if(time>=restart+250)for(unsigned channel=0;channel<3;++channel)near(result[channel],channel+1);
    }
}

static void placementUsesIndependentPhases(){
    const BagMatrix identity{{1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1}};
    const auto anchor=bagFits[1].anchor;
    std::array<BagTuningEntry,16> fits{};
    fits[1].enabled=true;
    const auto profile=bagResponseProfile("cloth");
    // Five saved bags plus the original undelayed response for comparison.
    std::array<BagMotion,6> motion{};
    std::array<BagResponse,6> response{};
    std::array<std::array<float,5>,5> rigidDifference{},fabricDifference{};
    for(unsigned time=0;time<=4500;time+=5){
        BagMatrix mount=identity;
        for(unsigned axis=0;axis<3;++axis)mount[12+axis]=anchor[axis];
        mount[14]+=.025f*std::sin(time*(2*3.14159265358979323846f/640));
        const float jump=time>=3000&&time<3500?1.f:0.f;
        std::array<BagMatrix,6> output{};
        std::array<float,5> fabric{};
        for(unsigned slot=0;slot<motion.size();++slot){
            const unsigned id=slot<5?201+slot:0;
            assert(bagPlacement(mount,identity,identity,anchor,output[slot],12,
                &motion[slot],time,0x1000,true,nullptr,nullptr,jump,
                fits.data(),0,id,&response[slot],&profile,jump));
            if(slot<5){
                const auto controls=bagResponseMatrices(response[slot],identity);
                fabric[slot]=controls[1][14]; // Lower/front fabric control.
                near(controls[5][14],0);      // Top control stays pinned.
            }
        }
        near(motion[0].airborneWeight,motion[5].airborneWeight);
        if(time==3100)assert(motion[0].airborneWeight>motion[4].airborneWeight+.3f);
        if(time==3600)assert(motion[4].airborneWeight>motion[0].airborneWeight+.3f);
        // First saved bag preserves both original rigid motion and deformation.
        for(unsigned element=0;element<16;++element)near(output[0][element],output[5][element]);
        near(response[0].localOffset[2],response[5].localOffset[2]);
        if(time>=1000&&time<3000){
            for(unsigned first=0;first<5;++first)for(unsigned second=first+1;second<5;++second){
                rigidDifference[first][second]=std::fmax(rigidDifference[first][second],
                    std::fabs(output[first][14]-output[second][14]));
                fabricDifference[first][second]=std::fmax(fabricDifference[first][second],
                    std::fabs(fabric[first]-fabric[second]));
            }
        }
        if(time==3400)assert(motion[0].airborneWeight>.9f);
    }
    for(unsigned first=0;first<5;++first)for(unsigned second=first+1;second<5;++second){
        assert(rigidDifference[first][second]>.0001f);
        assert(fabricDifference[first][second]>.0001f);
    }
    for(const auto& state:motion)assert(state.airborneWeight<.0001f);
}

static void emittedPhaseSafety(){
    constexpr float scale=.45f,pivot=.2f;
    for(unsigned interval:{1u,8u,40u,100u,250u})for(unsigned id=202;id<=208;++id){
        BagMotion state;
        BagMatrix input{},output{};
        for(unsigned time=0;time<=4000;time+=interval){
            // Cross quaternion branch seams and animation cuts. Current
            // horizontal mounting must never inherit the delayed position.
            const float angle=3.14f+.25f*std::sin(time*.015f),c=std::cos(angle),s=std::sin(angle);
            input={{scale,0,0,0,0,scale*c,scale*s,0,0,-scale*s,scale*c,0,
                    .1f*std::sin(time*.01f),.07f*std::cos(time*.01f),.06f*std::sin(time*.02f),1}};
            output=input;smoothBagMotion(state,output,scale,time,1,1,true,pivot,{{0,0,1}},nullptr,0,id);
            for(float value:output)assert(std::isfinite(value));
            for(unsigned column=0;column<3;++column)for(unsigned other=0;other<3;++other){
                float dot=0;for(unsigned axis=0;axis<3;++axis)dot+=output[4*column+axis]*output[4*other+axis];
                near(dot,column==other?scale*scale:0,.000001f);
            }
            for(unsigned axis=0;axis<2;++axis)
                near(output[12+axis]+pivot*output[8+axis],input[12+axis]+pivot*input[8+axis],.000001f);
            const float vertical=output[14]+pivot*output[10]-input[14]-pivot*input[10];
            assert(std::fabs(vertical)<=bagMotionHeight*scale*.04001f);
            const auto original=bagRotation(input,scale),actual=bagRotation(output,scale);
            const float dot=std::fmin(1.f,std::fabs(bagRotationDot(original,actual)));
            assert(2*std::acos(dot)<12.001f*.01745329252f);
            const auto once=output;output=input;
            smoothBagMotion(state,output,scale,time,1,1,true,pivot,{{0,0,1}},nullptr,0,id);
            for(unsigned i=0;i<16;++i)near(output[i],once[i],.000001f);
        }
        // A paused frame clears queued movement; resuming a static mount
        // cannot invent a periodic cycle, even while the run flag stays set.
        for(unsigned time=4500;time<=6500;time+=interval){
            output=input;smoothBagMotion(state,output,scale,time,1,1,true,pivot,{{0,0,1}},nullptr,0,id);
            for(unsigned i=0;i<16;++i)near(output[i],input[i],.000001f);
        }
    }
}

int main(){
    currentCase="identity delays";
    identityDelays();
    currentCase="phase is time not amplitude";
    phaseIsTimeNotAmplitude();
    currentCase="high and irregular frame rates";
    highAndIrregularFrameRates();
    currentCase="duplicate renders and independent bags";
    duplicateRendersAndIndependentBags();
    currentCase="timer wrap and reset";
    timerWrapAndReset();
    currentCase="stationary and nonfinite drivers";
    stationaryAndNonfiniteDrivers();
    currentCase="placement uses independent phases";
    placementUsesIndependentPhases();
    currentCase="emitted phase safety";
    emittedPhaseSafety();
    std::cout<<"bag jiggle timing tests passed\n";
}
