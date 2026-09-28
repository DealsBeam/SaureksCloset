#pragma once
#include <array>
#include <cmath>
#include <cstdint>
#include <cstddef>

// 85% is the standard back-bag fit. Smaller fitted bags have less inertia,
// rather than the same angular response or a faster spring. Cap large bags
// at the established response; their greater physical size adds travel.
inline float bagJiggleSizeGain(float scale){
    return std::fmax(.1f,std::fmin(1.f,scale/(.45f*.85f)));
}

// Stable saved bag identities, not model/color, list order, or render order.
// Local sway and airborne response use these delays; world travel and horizontal
// attachment positions stay current. Legacy/single first-bag timing is unchanged.
inline unsigned bagJiggleDelay(unsigned identity){
    constexpr unsigned delays[]={0,80,135,175,210,35,110,155};
    return identity>=201&&identity<=208?delays[identity-201]:0;
}
template<std::size_t N> struct BagJiggleHistory {
    struct Sample { std::uint32_t time=0;std::array<float,N> value{}; };
    std::array<Sample,64> samples{};
    unsigned count=0,head=0,identity=0;
    std::uint32_t last=0,captured=0;
};
template<std::size_t N>
static std::array<float,N> delayedBagJiggle(BagJiggleHistory<N>& history,const std::array<float,N>& current,
                                         std::uint32_t now,unsigned identity){
    for(float value:current)if(!std::isfinite(value)){history={};return {};}
    const unsigned delay=bagJiggleDelay(identity);
    if(!delay){if(history.count)history={};return current;}
    if(history.identity!=identity||(history.count&&now-history.last>250))history={};
    if(!history.count){
        history.identity=identity;history.last=history.captured=now;
        history.samples[0]={now,current};history.count=1;
    }else if(now!=history.last){
        history.last=now;
        // Keep over half a second even at very high FPS. Every nonzero delay
        // exceeds this capture interval, so both interpolation endpoints are
        // already recorded; no mutable/current-pose sample is needed.
        if(now-history.captured>=8){
            history.captured=now;history.head=(history.head+1)%history.samples.size();
            if(history.count<history.samples.size())++history.count;
            history.samples[history.head]={now,current};
        }
    }
    auto newer=history.samples[history.head];
    for(unsigned i=1;i<history.count;++i){
        const auto& older=history.samples[(history.head+history.samples.size()-i)%history.samples.size()];
        const auto age=now-older.time;
        if(age>=delay){
            const auto newerAge=now-newer.time;
            const float fraction=float(delay-newerAge)/float(age-newerAge);
            std::array<float,N> result{};
            for(unsigned axis=0;axis<N;++axis)result[axis]=newer.value[axis]+fraction*(older.value[axis]-newer.value[axis]);
            return result;
        }
        newer=older;
    }
    // Do not invent a pre-spawn impulse or replay the current gait early.
    return {};
}
