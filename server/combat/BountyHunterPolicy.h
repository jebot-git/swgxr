#pragma once
#include "CoreCuPolicy.h"
#include <array>
#include <algorithm>
#include <cmath>
#include <string>
namespace corecu { namespace bountyhunter {
using Vec=std::array<double,3>;
constexpr int PelletCount=8;
constexpr double PelletHalfAngle=4,ProjectileSpeed=160,AcquireDegrees=5,TurnDegreesPerSecond=20,MaxTurnDegrees=8,ArmSeconds=1.5,DuelistScale=.85,DuelistSeconds=8;
struct Ability {const char* label;const char* grant;const char* skill;const char* family;double damage;int action,mind,cooldown,duration;bool gesture,ultimate;};
inline Ability ability(const std::string& id){
 if(id=="eye_shot")return {"Eye Shot","eyeShot","combat_bountyhunter_droidresponse_02","pistol",.6,50,20,18,6,false,false};
 if(id=="bleeding_shot")return {"Torso Shot","bleedingShot","combat_bountyhunter_droidresponse_01","pistol",.8,55,20,16,12,false,false};
 if(id=="confusion_shot")return {"Confusion Shot","confusionShot","combat_bountyhunter_droidcontrol_04","carbine",.6,60,25,20,3,false,false};
 if(id=="underhand_shot")return {"Underhand Shot","underHandShot","combat_bountyhunter_droidcontrol_01","carbine",.65,70,30,24,2,true,false};
 if(id=="duelist_stance")return {"Duelist Stance","","combat_bountyhunter_investigation_04","compatible",0,60,30,60,8,true,false};
 if(id=="fast_blast")return {"Fast Blast","fastBlast","combat_bountyhunter_master","compatible",3,140,70,120,0,false,true};
 return {"","","","",0,0,0,0,0,false,false};
}
inline bool contains(const std::string& id){return *ability(id).skill && id!="bleeding_shot";}
inline int advancedSpeed(int branchRaw){return std::min(25,std::max(0,branchRaw)/2);}
inline int effectiveSpeed(int base,int strongestAdvanced,int bountyAdvanced){return base+std::max(strongestAdvanced,std::min(25,bountyAdvanced));}
inline double statusBonus(int branchRaw){return clamp(branchRaw/5.,0,10);}
inline double chance(double rating,int branchRaw){return learnedStatusChance(85,statusBonus(branchRaw),rating);}
inline double bleedFraction(bool pistolImproved,bool bountyLearned,bool torso){return pistolImproved?.4:bountyLearned?(torso?.45:.4):.3;}
inline double bleedDamage(bool pistolImproved){return pistolImproved?1.:.8;}
// Original crafted mean spans434..570; stock585 caps at crafted quality1.
// Calibrated bounded single-target output; no original heavy damage modifier.
inline double lightningQuality(double minimum,double maximum){return clamp(((minimum+maximum)*.5-434.)/136.,0,1);}
inline double lightningDamage(double minimum,double maximum,int branchRaw){return (416.+184.*lightningQuality(minimum,maximum))*(.8+.2*clamp(branchRaw/50.,0,1));}
inline double dot(const Vec& a,const Vec& b){return a[0]*b[0]+a[1]*b[1]+a[2]*b[2];}
inline Vec cross(const Vec& a,const Vec& b){return {{a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]}};}
inline Vec normalized(Vec v){double n=std::sqrt(dot(v,v));if(n<=0)return {{0,0,0}};for(auto& x:v)x/=n;return v;}
inline Vec pelletDirection(const Vec& forward,int index){auto d=normalized(forward);if(index==0)return d;auto ref=std::abs(d[1])>.99?Vec{{1,0,0}}:Vec{{0,1,0}};auto right=normalized(cross(d,ref)),up=cross(right,d);double a=PelletHalfAngle*3.141592653589793/180,az=2*3.141592653589793*(index-1)/7;for(int i=0;i<3;++i)d[i]=d[i]*std::cos(a)+(right[i]*std::cos(az)+up[i]*std::sin(az))*std::sin(a);return normalized(d);}
inline double angle(const Vec& a,const Vec& b){return std::acos(clamp(dot(normalized(a),normalized(b)),-1,1))*180/3.141592653589793;}
inline bool contact(const Vec& origin,const Vec& direction,const Vec& hit,double age,double range,double radius=.35){Vec offset{};for(int i=0;i<3;++i)offset[i]=hit[i]-origin[i];double travel=std::sqrt(dot(offset,offset)),along=dot(offset,direction);return std::isfinite(age) && age>=0 && age<=8 && travel<=range+2 && travel<=ProjectileSpeed*age+3 && along>=-.5 && travel*travel-along*along<=radius*radius;}
inline bool guidedContact(const Vec& origin,const Vec& direction,const Vec& hit,double age,double range){Vec offset{};for(int i=0;i<3;++i)offset[i]=hit[i]-origin[i];double travel=std::sqrt(dot(offset,offset));return std::isfinite(age) && age>=0 && age<=8 && travel<=range+2 && travel<=ProjectileSpeed*age+3 && angle(direction,offset)<=std::min(MaxTurnDegrees,TurnDegreesPerSecond*age)+.05;}
struct Arm {std::string item;double until=0;void clear(){item.clear();until=0;}bool ready(const std::string& held,double now)const{return !item.empty() && item==held && now<=until;}void set(const std::string& held,double now){item=held;until=now+ArmSeconds;}bool consume(const std::string& held,double now){bool accepted=ready(held,now);clear();return accepted;}};
}}
