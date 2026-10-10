#pragma once
#include <algorithm>
#include <cmath>
namespace corecu { namespace projectile {
// Ordinary bolts may borrow a small arrival-time window, never future rate.
// Advancing from the previous reservation repays jitter on subsequent shots;
// max(receipt, reservation) discards idle credit. Client age cannot alter it.
constexpr double MaxLaunchAgeSeconds=.250;
inline double arrivalAllowance(double interval){return std::min(MaxLaunchAgeSeconds,std::max(0.,interval*.5));}
inline bool arrivalReady(double receipt,double next,double interval,bool consecutive){return receipt+(consecutive?arrivalAllowance(interval):0.)+1.e-9>=next;}
inline double reserveArrival(double receipt,double next,double interval){return std::max(receipt,next)+interval;}
inline double arrivalCooldown(double receipt,double next,double interval){return std::max(0.,next-receipt-arrivalAllowance(interval));}
inline double rangeScale(bool pistol,bool twoHands){return pistol?(twoHands?1.1:1.):(twoHands?1.:.3);}
inline double damageScale(double distance,double nearRange,double idealRange,double maxRange,double nearModifier,double idealModifier,double farModifier,int posture){
 if(!std::isfinite(distance) || distance<0 || distance>maxRange)return 0;
 double begin=distance<=idealRange?nearRange:idealRange,end=distance<=idealRange?idealRange:maxRange;
 double a=distance<=idealRange?nearModifier:idealModifier,b=distance<=idealRange?idealModifier:farModifier;
 double mix=std::max(0.,std::min(1.,(distance-begin)/std::max(.0001,end-begin)));
 double modifier=a+(b-a)*mix;if(modifier<0){if(posture==1)modifier*=.5;else if(posture==2)modifier=0;}
 return std::max(0.,1+modifier/100.);
}
}}
