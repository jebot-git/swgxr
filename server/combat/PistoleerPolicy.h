#pragma once
#include <algorithm>
#include <array>
#include <cmath>
#include <string>
namespace corecu { namespace pistoleer {
struct Ability {const char* label;const char* grant;double damage;int action,mind,cooldown,blows;bool gesture,ultimate;};
inline Ability ability(const std::string& id){
 if(id=="double_tap")return {"Double Tap","doubleTap",.8,60,20,12,2,false,false};
 if(id=="disarming_shot")return {"Disarming Shot","disarmingShot1",.5,45,20,18,1,false,false};
 if(id=="fan_shot")return {"Fan Shot","fanShot",1.,80,25,16,1,true,false};
 if(id=="run_and_gun")return {"Run and Gun","",0,80,40,60,0,true,false};
 if(id=="showdown")return {"Showdown","",.9,150,75,120,1,false,true};
 return {"","",0,0,0,0,0,false,false};
}
inline bool contains(const std::string& id){return *ability(id).label;}
inline bool regular(const std::string& id){return !id.empty() && id!="fan_shot" && id!="run_and_gun" && id!="showdown" && id!="last_ditch" && id!="fast_blast";}
inline double costScale(bool active,const std::string& id){return active && regular(id)?.75:1.;}
inline int cost(int value,bool active,const std::string& id){return int(std::ceil(value*costScale(active,id)));}
inline double fireInterval(double native,bool active,const std::string& id){return active && id.empty()?native/1.25:native;}
inline bool validPose(const std::array<double,3>& origin,const std::array<double,3>& direction,const std::array<double,3>& feet){
 double distance=0,norm=0;for(int i=0;i<3;++i){if(!std::isfinite(origin[i]) || !std::isfinite(direction[i]) || !std::isfinite(feet[i]))return false;distance+=(origin[i]-feet[i])*(origin[i]-feet[i]);norm+=direction[i]*direction[i];}return distance<=6.25 && std::abs(norm-1)<=.05;
}
inline double fanRange(double range){return std::max(0.,std::min(12.,range));}
inline float suppressionGap(float intimidate,float stun,float fencer,float disarming,float showdown){return std::max(intimidate,std::max({fencer,disarming,showdown})-std::max(0.f,stun));}
constexpr int BuffSeconds=8, FanTargets=5;
constexpr double VolleySpacing=.25, VolleyLaunchSeconds=2., ProjectileSeconds=8.;
struct Volley {
 std::string item,target,ability="showdown";unsigned long long revision=0;double started=0,lastLaunch=0,reservation=0;int nextIndex=1;bool effectAttempted=false,invalidated=false;
 bool accepts(const std::string& weapon,const std::string& victim,unsigned long long loadout,int index,double now,double nextFire)const{
  return !invalidated && weapon==item && victim==target && loadout==revision && index==nextIndex && index>=1 && index<=2 && now>=lastLaunch+VolleySpacing && now<=started+VolleyLaunchSeconds && nextFire==reservation;
 }
 bool effect(int damage){if(damage<=0 || effectAttempted)return false;effectAttempted=true;return true;}
};
}}
