#pragma once
#include <array>
#include <cmath>
namespace corecu { namespace warcry {
constexpr double Range=24, Cooldown=30;
constexpr int ActionCost=80, MindCost=40, Reduction=20, MaxTargets=8;
using Vec=std::array<double,3>;
inline bool validPose(const Vec& origin,const Vec& direction,const Vec& feet){
 double distance=0,norm=0;
 for(int i=0;i<3;++i){if(!std::isfinite(origin[i])||!std::isfinite(direction[i])||!std::isfinite(feet[i]))return false;distance+=(origin[i]-feet[i])*(origin[i]-feet[i]);norm+=direction[i]*direction[i];}
 return distance<=6.25 && std::abs(norm-1)<=.05 && std::hypot(direction[0],direction[2])>.1;
}
inline bool inCone(const Vec& feet,const Vec& direction,const Vec& target){
 double dx=target[0]-feet[0],dy=target[1]-feet[1],dz=target[2]-feet[2];
 for(double x:target)if(!std::isfinite(x))return false;
 double planar=std::hypot(dx,dz),forward=std::hypot(direction[0],direction[2]);
 return forward>.1 && planar>.001 && dx*dx+dy*dy+dz*dz<=Range*Range && (dx*direction[0]+dz*direction[2])/(planar*forward)>=.866025403784;
}
inline int duration(bool master){return master?8:6;}
inline int delay(bool master){return master?3:2;}
}}
