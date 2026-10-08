#pragma once
#include <array>
#include <algorithm>
#include <cmath>
namespace corecu { namespace taunt {
using Vec=std::array<double,3>;
// The optical reticle spans 18 cm at 3 m, i.e. 3% either side of its axis.
inline double reticleEntry(const Vec& origin,const Vec& direction,const Vec& feet,double radius,double height,double range){
 for(auto v:{origin,direction,feet})for(double x:v)if(!std::isfinite(x))return -1;
 if(!std::isfinite(radius)||!std::isfinite(height)||!std::isfinite(range)||range<=0)return -1;
 double norm=0;for(double x:direction)norm+=x*x;if(std::abs(norm-1)>.05)return -1;
 radius=std::max(.1,std::min(radius,1.5));height=std::max(.3,std::min(height,4.));
 Vec delta{{feet[0]-origin[0],feet[1]-origin[1],feet[2]-origin[2]}};
 double planar=std::hypot(delta[0],delta[2]);
 delta[1]=std::max(feet[1]+.15,std::min(feet[1]+height,origin[1]+direction[1]*planar))-origin[1];
 double along=0,squared=0;for(int i=0;i<3;++i){along+=delta[i]*direction[i];squared+=delta[i]*delta[i];}
 if(along<=0||std::sqrt(squared)>range+radius)return -1;
 double side2=std::max(0.,squared-along*along),width=radius+along*.03;
 if(side2>width*width)return -1;
 return std::max(0.,along-std::sqrt(width*width-side2));
}
}}
