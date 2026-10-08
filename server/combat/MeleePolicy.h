#pragma once
#include <array>
#include <algorithm>
#include <cmath>
namespace corecu { namespace melee {
using Vec=std::array<double,3>;
constexpr double HALF_ANGLE_TAN=.26794919243; // 15 degrees; one victim, not cleave.
inline double reach(double nativeRange,bool unarmed){return std::max(0.,std::min(nativeRange,unarmed?2.:4.));}
inline double score(const Vec& origin,const Vec& direction,const Vec& feet,double radius,double height,double range){
 for(auto v:{origin,direction,feet})for(double x:v)if(!std::isfinite(x))return -1;
 double norm=0;for(double d:direction)norm+=d*d;if(std::abs(norm-1)>.05)return -1;
 radius=std::max(.1,std::min(radius,.6));height=std::max(.3,std::min(height,3.));
 Vec delta{{feet[0]-origin[0],feet[1]-origin[1],feet[2]-origin[2]}};
 double planar=std::hypot(delta[0],delta[2]);
 // Aim against a bounded vertical capsule, not only the creature's ground point.
 delta[1]=std::max(feet[1]+.15,std::min(feet[1]+height,origin[1]+direction[1]*planar))-origin[1];
 double along=0,squared=0;for(int i=0;i<3;++i){along+=delta[i]*direction[i];squared+=delta[i]*delta[i];}
 if(along<=0||std::sqrt(squared)>range+radius)return -1;
 double side=std::sqrt(std::max(0.,squared-along*along));
 if(side>radius+along*HALF_ANGLE_TAN)return -1;
 return side/std::max(.1,along)*10+std::sqrt(squared)*.1;
}
}}
