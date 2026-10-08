#ifndef SWGXR_MOVEMENT_BUDGET_H
#define SWGXR_MOVEMENT_BUDGET_H
#include <algorithm>
#include <cmath>
#include <cstdint>
namespace swgxr { namespace movement {
// One shared distance allowance, not a fresh tolerance for each packet. The
// bounded two-second window accommodates the measured 0.5–1s HTTP round trip.
struct Budget {
 static constexpr double WINDOW_SECONDS=2.0;
 static constexpr double SPEED_TOLERANCE=1.10;
 static constexpr double INITIAL_METRES=0.25;
 double stamp=0,credit=INITIAL_METRES,x=0,y=0,rate=0;
 uint64_t parent=0,revision=0;
 static double speed(double value){return std::isfinite(value)?std::max(0.0,value)*SPEED_TOLERANCE:0;}
 void rebase(double now,double px,double py,uint64_t cell,double maxSpeed){
  stamp=now;credit=INITIAL_METRES;x=px;y=py;parent=cell;rate=speed(maxSpeed);++revision;
 }
 void accrue(double now,double maxSpeed){
  if(!std::isfinite(now) || now<stamp)return;
  const double next=speed(maxSpeed),elapsed=std::min(WINDOW_SECONDS,now-stamp);
  // Native speed changes can occur between arrivals. Allow that last bounded
  // interval at the higher observed speed; subsequent intervals use the new one.
  credit=std::min(WINDOW_SECONDS*std::max(rate,next)+INITIAL_METRES,
                  credit+elapsed*std::max(rate,next));
  stamp=now;rate=next;
 }
 bool accept(double px,double py,uint64_t cell){
  if(!std::isfinite(px) || !std::isfinite(py))return false;
  const double distance=std::hypot(px-x,py-y);
  if(distance>credit+1e-6)return false;
  credit=std::max(0.0,credit-distance);
  if(distance>1e-6 || parent!=cell)++revision;
  x=px;y=py;parent=cell;return true;
 }
};
}}
#endif
