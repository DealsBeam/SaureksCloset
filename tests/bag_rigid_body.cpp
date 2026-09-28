#include <cassert>
#include <cmath>
#include <iostream>
#include "../native/BagBehavior.h"
#include "../native/BagCatalog.h"
#include "../native/BagPlacement.h"
static const BagMatrix identity{{1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1}};
static void near(float a,float b){assert(std::isfinite(a)&&std::fabs(a-b)<.00001f);}
int main(){
    for(const auto& asset:bagCatalog)for(float percent:{35.f,85.f}){
        const bool soft=asset.id==12||asset.id==13||asset.id==14||asset.id==15||asset.id==16;
        assert(bagSoftBody(asset.id)==soft);
        const auto profile=bagResponseProfile(asset.material);
        const float scale=.45f*percent/100;
        std::array<BagTuningEntry,16> fits{};fits[1].enabled=true;fits[1].values.scale=percent;
        BagMotion motion;BagResponse response;float largestBob=0;bool deformed=false;
        for(unsigned time=0;time<=7200;time+=16){
            const bool moving=time<4800;const float t=std::fmin(time,4800u)*.001f;
            const float angle=.25f*std::sin(t*11),c=std::cos(angle),s=std::sin(angle);
            BagMatrix fitted{{scale,0,0,0,0,scale*c,scale*s,0,0,-scale*s,scale*c,0,
                .02f*std::sin(t*8),.2f,1.1f+.04f*std::sin(t*17.6f),1}},output;
            const float flight=time>=3500&&time<4300?1.f:0;
            assert(bagPlacement(identity,identity,identity,bagFits[1].anchor,output,1,&motion,time,3,moving,
                nullptr,nullptr,flight,fits.data(),0,201+asset.id%5,&response,&profile,flight,moving,&fitted,soft));
            const auto palette=bagResponseMatrices(response,output,soft);
            for(unsigned bone=0;bone<61;++bone){
                if(!soft)assert(palette[bone]==output); // ANY skin weights yield the same rigid transform.
                else deformed=deformed||palette[bone]!=output;
            }
            // No stretch or shear in the final moving object: three equal
            // basis lengths and perpendicular axes preserve all pair distances.
            for(unsigned a=0;a<3;++a)for(unsigned b=0;b<3;++b){
                float dot=0;for(unsigned row=0;row<3;++row)dot+=output[a*4+row]*output[b*4+row];
                near(dot,a==b?scale*scale:0);
            }
            if(!soft){
                assert(!response.ready&&!response.tracking);
                largestBob=std::fmax(largestBob,std::fabs(motion.verticalBob*(1+.75f*motion.runWeight)));
                if(time>6800)for(unsigned element=0;element<16;++element)near(output[element],fitted[element]);
            }
        }
        if(soft)assert(deformed);else assert(largestBob>.001f);
    }
    // Even stale soft state cannot deform a newly selected rigid model.
    BagResponse stale;stale.profile=bagResponseProfile("cloth");bagResponseCompile(stale);
    stale.localOffset={{.1f,.05f,-.2f}};stale.bobLocal={{0,0,.1f}};
    for(const auto& matrix:bagResponseMatrices(stale,identity,false))assert(matrix==identity);
    assert(!bagSoftBody(0)&&!bagSoftBody(999));
    std::cout<<"PASS: all catalog bags preserve rigid geometry through run/jump/idle except the soft Mageweave family; rigid bags retain bob and reject stale deformation\n";
}
