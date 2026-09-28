// The upper rear contact follows the live body even when the rest of the bag
// sways at another phase. Exercise final attachment matrices, not spring state.
#include <array>
#include <cassert>
#include <cmath>
#include <iostream>
#include "../native/BagPlacement.h"

static const BagMatrix identity{{1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1}};
static void near(float actual,float expected,float tolerance=.00005f){
    if(!std::isfinite(actual)||std::fabs(actual-expected)>tolerance)
        std::cerr<<"expected "<<expected<<", received "<<actual<<"\n";
    assert(std::isfinite(actual)&&std::fabs(actual-expected)<=tolerance);
}
static BagMatrix rotate(unsigned axis,float angle){
    auto out=identity;
    const unsigned a=(axis+1)%3,b=(axis+2)%3;
    out[a*4+a]=out[b*4+b]=std::cos(angle);
    out[a*4+b]=std::sin(angle);out[b*4+a]=-std::sin(angle);
    return out;
}
static std::array<float,3> point(const BagMatrix& matrix,const std::array<float,3>& local){
    std::array<float,3> out{};
    for(unsigned row=0;row<3;++row)
        out[row]=matrix[12+row]+matrix[row]*local[0]+matrix[4+row]*local[1]+matrix[8+row]*local[2];
    return out;
}
static BagMatrix translatedAnchor(const BagMatrix& parent,const std::array<float,3>& anchor){
    auto result=parent;const auto p=point(parent,anchor);
    for(unsigned i=0;i<3;++i)result[12+i]=p[i];
    return result;
}

static void liveHipContact(){
    const auto profile=bagResponseProfile("cloth",-.53f,.47f);
    const std::array<float,3> upper{{0,0,profile.top}},lower{{-.20f,.18f,profile.low[2]}};
    for(unsigned mount:{1u,2u})for(unsigned id=201;id<=205;++id)for(float percent:{35.f,85.f})for(bool transformed:{false,true}){
        std::array<BagTuningEntry,16> fits{};
        fits[1].enabled=true;
        auto& tuning=fits[1].values;
        assert(bagInstanceTuningDefaults(mount,1,1,tuning));
        tuning.left=.057f;tuning.inset=-.023f;tuning.up=-.12f;
        tuning.yaw+=(mount==1?13.f:-17.f);tuning.roll=21.f;tuning.pitch=-9.f;tuning.scale=percent;
        BagMotion state;
        auto childLocal=rotate(2,.31f);childLocal[12]=.025f;childLocal[14]=-.014f;
        float lowerTravel=0;
        for(unsigned time=0;time<=2400;time+=8){
            const float seconds=time*.001f;
            auto pelvis=bagMatrixProduct(bagMatrixProduct(rotate(0,.13f*std::sin(seconds*10.3f)),
                rotate(1,.11f*std::sin(seconds*7.7f))),rotate(2,.16f*std::sin(seconds*9.4f)));
            pelvis[12]=.035f*std::sin(seconds*12.f);pelvis[13]=.045f*std::sin(seconds*8.f);pelvis[14]=.025f*std::sin(seconds*16.f);
            // Audited Human Female32/33 rest coordinates, attached to pelvis21.
            const std::array<float,3> anchor{{.09722214f,mount==1?.16666667f:-.16666667f,1.24999988f}};
            const auto attachment=translatedAnchor(pelvis,anchor);
            auto modelToWorld=identity,worldToRender=identity;
            if(transformed){
                modelToWorld=bagMatrixProduct(rotate(2,.58f),rotate(0,.24f));
                for(unsigned row=0;row<3;++row){modelToWorld[row]*=.85f;modelToWorld[4+row]*=1.15f;modelToWorld[8+row]*=1.3f;}
                modelToWorld[12]=2.f+seconds*1.4f;modelToWorld[13]=-.8f+seconds*.5f;modelToWorld[14]=.1f;
                worldToRender=bagMatrixProduct(rotate(0,-.48f),rotate(2,.4f*std::sin(seconds*1.3f)));
                worldToRender[12]=4.f-seconds;worldToRender[13]=-2.f;worldToRender[14]=.3f*std::cos(seconds*1.7f);
            }
            const auto modelToRender=bagMatrixProduct(worldToRender,modelToWorld);
            const auto renderedAnchor=bagMatrixProduct(modelToRender,attachment),renderedPelvis=bagMatrixProduct(modelToRender,pelvis);
            BagMatrix fitted,moving,renderToWorld;
            assert(bagAffineInverse(worldToRender,renderToWorld));
            assert(bagPlacement(renderedAnchor,renderedPelvis,childLocal,bagFits[1].anchor,fitted,1,nullptr,time,17,true,
                &modelToRender,&worldToRender,0,fits.data(),mount,id,nullptr,&profile));
            assert(bagPlacement(renderedAnchor,renderedPelvis,childLocal,bagFits[1].anchor,moving,1,&state,time,17,true,
                &modelToRender,&worldToRender,0,fits.data(),mount,id,nullptr,&profile));
            if(time==0)for(unsigned i=0;i<16;++i)near(moving[i],fitted[i],.000001f);
            const auto fittedWorld=bagMatrixProduct(renderToWorld,bagMatrixProduct(fitted,childLocal));
            const auto movingWorld=bagMatrixProduct(renderToWorld,bagMatrixProduct(moving,childLocal));
            const auto fittedContact=point(fittedWorld,upper),movingContact=point(movingWorld,upper);
            near(movingContact[0],fittedContact[0]);near(movingContact[1],fittedContact[1]);
            const float size=bagModelScale*percent/100;
            const float verticalLimit=bagMotionHeight*size*.04f*(transformed?1.31f:1.f);
            assert(std::fabs(movingContact[2]-fittedContact[2])<=verticalLimit+.00005f);
            const auto fittedLower=point(fittedWorld,lower),movingLower=point(movingWorld,lower);
            lowerTravel=std::fmax(lowerTravel,std::hypot(movingLower[0]-fittedLower[0],movingLower[1]-fittedLower[1]));
        }
        // Pinning cannot be implemented by suppressing the visible sway.
        assert(lowerTravel>.0001f);
    }
}

static void fittedJumpDirection(){
    // The user can rotate a nominal back bag onto either side. Its actual rear
    // panel normal, rather than the selected back slot, determines lift outward.
    for(float yaw:{-90.f,90.f}){
        std::array<BagTuningEntry,16> fits{};fits[1].enabled=true;
        auto& tuning=fits[1].values;tuning.yaw=yaw;tuning.motion=true;
        auto anchor=identity;anchor[12]=-.22f;anchor[14]=1.36f;
        BagMotion motion;BagMatrix fitted,moving;
        assert(bagPlacement(anchor,identity,identity,bagFits[1].anchor,fitted,1,nullptr,0,8,false,
            nullptr,nullptr,0,fits.data(),0,201));
        for(unsigned time=0;time<=1200;time+=8)
            assert(bagPlacement(anchor,identity,identity,bagFits[1].anchor,moving,1,&motion,time,8,false,
                nullptr,nullptr,1,fits.data(),0,201));
        const auto before=point(fitted,{{0,0,-.5f}}),after=point(moving,{{0,0,-.5f}});
        const float dx=after[0]-before[0],dy=after[1]-before[1];
        const float scale=bagModelScale*tuning.scale/100;
        const float outward=dx*(-fitted[0]/scale)+dy*(-fitted[1]/scale);
        const float tangent=dx*(-fitted[1]/scale)-dy*(-fitted[0]/scale);
        assert(outward>.05f);near(tangent,0,.00001f);
        assert(after[2]>before[2]+.01f);
    }
}

static void anatomicalMountContact(){
    const auto profile=bagResponseProfile("cloth",-.53f,.47f);
    for(unsigned id:{201u,202u,205u})for(float percent:{35.f,85.f}){
        std::array<BagTuningEntry,16> fits{};fits[1].enabled=true;
        auto& tuning=fits[1].values;tuning.scale=percent;tuning.roll=16;tuning.yaw=90;
        const float scale=bagModelScale*percent/100;
        auto local=rotate(2,.2f);local[12]=.04f;
        BagMotion motion;
        for(unsigned time=0;time<=4400;time+=8){
            const float t=std::fmin(time,3600u)*.001f;
            // A foot frame follows a separate, much stronger cycle than the
            // default torso; the fitted override must retain that exact frame.
            auto foot=bagMatrixProduct(rotate(0,.52f*std::sin(t*11.f)),rotate(1,.38f*std::sin(t*9.f)));
            foot=bagMatrixProduct(foot,rotate(2,.48f*std::sin(t*7.f)));
            for(unsigned c=0;c<3;++c)for(unsigned r=0;r<3;++r)foot[c*4+r]*=scale;
            foot[12]=.12f+.18f*std::sin(t*11.f);foot[13]=-.16f;foot[14]=.18f+.15f*std::sin(t*11.f);
            auto torso=rotate(2,.05f*std::sin(t*5.f));torso[14]=1.3f;
            auto world=bagMatrixProduct(rotate(2,.4f),rotate(0,.16f));
            world[12]=2+t;world[13]=-.7f;world[14]=.13f;
            auto view=bagMatrixProduct(rotate(0,-.42f),rotate(2,t*.1f));view[12]=1;view[14]=-.8f;
            const auto modelToRender=bagMatrixProduct(view,world);
            const auto rendered=bagMatrixProduct(modelToRender,torso);
            const float jump=time>=2200&&time<2800?1.f:0.f;
            BagMatrix output,renderToWorld;assert(bagAffineInverse(view,renderToWorld));
            assert(bagPlacement(rendered,rendered,local,bagFits[1].anchor,output,1,&motion,time,29,true,
                &modelToRender,&view,jump,fits.data(),2,id,nullptr,&profile,0,time<3600,&foot));
            const auto actual=bagMatrixProduct(renderToWorld,bagMatrixProduct(output,local));
            const auto expected=bagMatrixProduct(world,foot);
            const auto a=point(actual,{{0,0,profile.top}}),b=point(expected,{{0,0,profile.top}});
            for(unsigned axis=0;axis<3;++axis)near(a[axis],b[axis]);
            if(time==0||time>=4300)for(unsigned i=0;i<16;++i)near(actual[i],expected[i],.0001f);
        }
    }
}

int main(){
    liveHipContact();fittedJumpDirection();anatomicalMountContact();
    std::cout<<"PASS: hip upper contact stays on the moving body through phased sway, tuned fits, scale and camera/root transforms; jump lift follows the fitted bag normal.\n";
}
