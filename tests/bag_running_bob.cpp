// Compare the emitted rig against the old vertical spring, not just its state.
#include <cassert>
#include <cmath>
#include <iostream>
#include "../native/BagPlacement.h"
static const BagMatrix identity{{1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1}};
static void near(float a,float b,float e=.000003f){assert(std::isfinite(a)&&std::fabs(a-b)<e);}
static float exercise(float percent,unsigned id,unsigned interval,const char* material,bool running=true){
    const auto profile=bagResponseProfile(material);
    const float scale=.45f*percent/100;
    std::array<BagTuningEntry,16> fits{};fits[1].enabled=true;fits[1].values.scale=percent;
    BagMotion motion,old;BagResponse response;float peak=0;
    for(unsigned time=0;time<=7200;time+=interval){
        const bool moving=time<4800;
        const float t=time*.001f;
        auto fitted=identity;
        for(unsigned i:{0u,5u,10u})fitted[i]=scale;
        fitted[12]=.2f;fitted[14]=1.1f+(moving?.025f*std::sin(t*17.6f):.002f*std::sin(t*4));
        BagMatrix output;
        assert(bagPlacement(identity,identity,identity,bagFits[1].anchor,output,1,&motion,time,3,moving&&running,
            nullptr,nullptr,0,fits.data(),0,id,&response,&profile,0,moving,&fitted));
        auto legacy=fitted;
        smoothBagMotion(old,legacy,scale,time,3,7,moving&&running,profile.top,{{0,0,1}},nullptr,0,id,moving,false);
        if(!response.ready)continue;
        const auto matrices=bagResponseMatrices(response,output);
        auto without=response;without.bobLocal={};
        const auto base=bagResponseMatrices(without,output);
        // Every lower grid control receives the amplified old bob, including the
        // rear panel. Leaving bob only on the front would lose the old motion.
        for(unsigned control=0;control<60;++control){
            const bool top=control%5==4;
            near(matrices[control+1][12],base[control+1][12]);
            near(matrices[control+1][13],base[control+1][13]);
            near(matrices[control+1][14]-base[control+1][14],top?0:(legacy[14]-fitted[14])*(1+.75f*old.runWeight));
            if(top)for(unsigned element=0;element<16;++element)near(matrices[control+1][element],output[element]);
        }
        if(time>1000&&moving)peak=std::fmax(peak,std::fabs(matrices[46][14]-base[46][14]));
        // Two rear controls at different heights translate by equal amounts:
        // the lower bag moves together instead of being uniformly stretched.
        near(matrices[46][14]-matrices[48][14],0);
        for(unsigned axis=0;axis<3;++axis)
            near(output[12+axis]+profile.top*output[8+axis],fitted[12+axis]+profile.top*fitted[8+axis]);
        const auto first=matrices;
        assert(bagPlacement(identity,identity,identity,bagFits[1].anchor,output,1,&motion,time,3,moving&&running,
            nullptr,nullptr,0,fits.data(),0,id,&response,&profile,0,moving,&fitted));
        const auto duplicate=bagResponseMatrices(response,output);
        for(unsigned i=0;i<61;++i)for(unsigned j=0;j<16;++j)near(duplicate[i][j],first[i][j]);
        if(time>6800)near(response.bobLocal[2],0,.00001f);
    }
    assert(peak>profile.height*scale*.004f);
    return peak;
}
static float rigidBob(float percent,unsigned id,unsigned interval){
    const auto profile=bagResponseProfile("leather");const float scale=.45f*percent/100;
    std::array<BagTuningEntry,16> fits{};fits[1].enabled=true;fits[1].values.scale=percent;
    BagMotion motion;BagResponse response;float peak=0;
    for(unsigned time=0;time<=4800;time+=interval){
        auto fitted=identity;for(unsigned i:{0u,5u,10u})fitted[i]=scale;
        fitted[13]=.2f;fitted[14]=1.1f+.025f*std::sin(time*.0176f);
        BagMatrix output;
        assert(bagPlacement(identity,identity,identity,bagFits[1].anchor,output,1,&motion,time,3,true,
            nullptr,nullptr,0,fits.data(),1,id,&response,&profile,0,true,&fitted,false));
        for(const auto& matrix:bagResponseMatrices(response,output,false))assert(matrix==output);
        const float bob=output[14]+profile.top*output[10]-fitted[14]-profile.top*fitted[10];
        if(time>1000)peak=std::fmax(peak,std::fabs(bob));
    }
    assert(peak>scale*profile.height*.01f);return peak;
}
int main(){
    for(const char* material:{"cloth","leather"})for(unsigned id:{201u,202u,205u}){
        const float large=exercise(85,id,8,material),small=exercise(35,id,8,material);
        const float walking=exercise(85,id,8,material,false);
        assert(large>walking*1.72f&&large<walking*1.78f);
        assert(small<large*.6f);
        for(float size:{25.f,35.f,56.f})near(exercise(size,id,8,material)/large,size/85.f,.006f);
        for(unsigned dt:{16u,32u}){
            const float lowerFPS=exercise(85,id,dt,material);
            assert(lowerFPS>large*.8f&&lowerFPS<large*1.2f);
        }
    }
    for(unsigned id:{201u,202u,205u})for(unsigned interval:{8u,16u,32u}){
        const float standard=rigidBob(85,id,interval);
        for(float size:{25.f,35.f,56.f})near(rigidBob(size,id,interval)/standard,size/85.f,.006f);
    }
    // Gravity stays world-up when the fitted bag has rotated sideways.
    BagResponse state;state.profile=bagResponseProfile("cloth");bagResponseCompile(state);
    const BagMatrix rotated{{0,0,-.3f,0,0,.3f,0,0,.3f,0,0,0,.2f,0,1,1}};
    bagResponseBob(state,rotated,{{0,0,1}},.01f);
    const auto palette=bagResponseMatrices(state,rotated);
    near(palette[1][12],rotated[12]);near(palette[1][13],rotated[13]);near(palette[1][14]-rotated[14],.01f);
    assert(palette[5]==rotated);
    std::cout<<"PASS: pinned bags emit 1.75x running bob with original timing, unchanged walking bob, lower-body shape, size restraint, gravity and quiet idle\n";
}
