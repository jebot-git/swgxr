#pragma once
#include <array>
#include <algorithm>
#include <cmath>
#include <cstdint>
namespace corecu { namespace guard {
using Vec=std::array<double,3>;
inline bool finite(const Vec& p){for(double v:p)if(!std::isfinite(v)||std::abs(v)>2)return false;return true;}
inline double length(const Vec& p){return std::sqrt(p[0]*p[0]+p[1]*p[1]+p[2]*p[2]);}
inline bool hand(const Vec& p,bool boxing){return finite(p)&&std::abs(p[0])<=.55&&p[1]>=(boxing?-.35:-.70)&&p[1]<=.20&&p[2]>=-.80&&p[2]<=-.10;}
inline bool boxing(const Vec& left,const Vec& right){return hand(left,true)&&hand(right,true)&&left[0]<-.04&&right[0]>.04&&right[0]-left[0]<=.85;}
inline bool parry(const Vec& main,const Vec& axis){return hand(main,false)&&finite(axis)&&std::abs(length(axis)-1)<.05&&std::abs(axis[2])<=.65;}
inline bool front(double fx,double fz,double dx,double dz){double a=std::hypot(fx,fz),b=std::hypot(dx,dz);return std::isfinite(a)&&std::isfinite(b)&&a>.9&&b>.01&&(fx*dx+fz*dz)/(a*b)>=.5;}
constexpr double LEASE=.85, ARM_TIME=.12, BREAK_TIME=1.2;
inline double multiplier(bool unarmed){return unarmed?.55:.35;}
inline int cost(int damage){return std::max(5,int(std::ceil(std::max(0,damage)*.10)));}
struct State {
 double at=0,armed=0,broken=0;
 std::uint64_t item=0,blocks=0;
 bool unarmed=false;
 double release(){double previous=at;at=0;return previous;}
 void refresh(double stamp,double previous,std::uint64_t weapon,bool boxing){
  if(stamp-previous>LEASE||item!=weapon)armed=stamp;
  at=stamp;item=weapon;unarmed=boxing;
 }
 bool active(double stamp,std::uint64_t weapon)const{return at>0&&stamp>=at&&stamp-at<=LEASE&&stamp-armed>=ARM_TIME&&stamp>=broken&&weapon==item;}
 int block(double stamp,int damage,int action){
  if(!active(stamp,item)||damage<=0)return 0;
  int charge=cost(damage);
  if(action<=charge){broken=stamp+BREAK_TIME;at=0;return 0;}
  ++blocks;return charge;
 }
};
}}
