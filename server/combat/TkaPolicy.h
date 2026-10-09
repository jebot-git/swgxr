#pragma once
#include "WarcryPolicy.h"
#include <algorithm>
#include <string>
namespace corecu { namespace tka {
struct Attack { double range, cosine, multiplier, cooldown, interval; int targets, blows, action, mind; };
inline Attack attack(const std::string& id) {
 if(id=="tka_sweep")return {3,.5,.65,6,1.25,6,1,60,20};
 if(id=="tka_half_spin")return {4,0,.55,10,1.75,8,1,90,30};
 if(id=="tka_volley")return {3,.866025403784,.4,8,1.5,4,3,80,25};
 return {0,1,0,0,0,0,0,0,0};
}
inline bool inCone(const warcry::Vec& feet,const warcry::Vec& direction,const warcry::Vec& target,const Attack& a) {
 for(double x:target)if(!std::isfinite(x))return false;
 double x=target[0]-feet[0],y=target[1]-feet[1],z=target[2]-feet[2];
 double planar=std::hypot(x,z),forward=std::hypot(direction[0],direction[2]);
 return a.targets>0 && forward>.1 && x*x+y*y+z*z<=a.range*a.range && (planar<.001 || (x*direction[0]+z*direction[2])/(planar*forward)>=a.cosine);
}
inline int center(int current,int trained,bool focused) {return focused?std::max(current,std::min(100,int(std::ceil(std::max(current,trained)*1.5)))):current;}
inline double resistance(double base,bool focused) {return focused?base+std::min(20.,std::max(0.,100.-base)):base;}
inline int threat(int damage,bool challenge=false) {return damage>0?std::min(5000,(challenge?200:40)+damage*(challenge?4:2)):0;}
constexpr int FocusSeconds=12, FocusCooldown=120, FocusAction=120, FocusMind=100;
}}
