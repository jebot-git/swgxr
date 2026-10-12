#pragma once
#include "JtlPolicy.h"
#include <limits>
namespace swgxr { namespace jtl {
inline double dot(const Vec&a,const Vec&b){double v=0;for(int k=0;k<3;++k)v+=a[k]*b[k];return v;}
inline Vec sub(const Vec&a,const Vec&b){return {{a[0]-b[0],a[1]-b[1],a[2]-b[2]}};}
// Continuous sweep against an original asteroid extent, including a moving
// hull's radius. Already-overlapping launch placements may move outward.
inline double sphereSweep(const Vec& from,const Vec& to,const Vec& center,double radius){
 auto d=sub(to,from),m=sub(from,center);double a=dot(d,d),b=dot(m,d),c=dot(m,m)-radius*radius;
 if(a<1e-12)return 1;
 if(c<=0)return b>=0?1:0;
 double disc=b*b-a*c;if(b>=0 || disc<0)return 1;
 return clamp((-b-std::sqrt(disc))/a,0,1);
}
// Conservative swept sphere against original triangle/primitive volumes. Each
// inflated midpoint sphere encloses its entire subsegment: thin surfaces cannot
// be skipped at high speed. The maximum early stop is one quarter of hull radius.
template<class Overlap> double volumeSweep(const Vec& from,const Vec& to,double radius,Overlap overlap){
 auto d=sub(to,from);double distance=length(d);if(distance<1e-8)return 1;
 if(overlap(from,radius))return !overlap(to,radius)?1:0;
 int steps=std::max(1,int(std::ceil(distance/std::max(.1,radius*.25))));
 double step=distance/steps;
 for(int i=0;i<steps;++i){double t=(i+.5)/steps;Vec p=from;for(int k=0;k<3;++k)p[k]+=d[k]*t;
  if(overlap(p,radius+step*.5))return double(i)/steps;
 }
 return 1;
}
}}
