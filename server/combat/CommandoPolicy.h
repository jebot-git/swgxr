#pragma once
#include "CoreCuPolicy.h"
#if __has_include("server/zone/objects/tangible/wearables/ArmourModel.h")
#include "server/zone/objects/tangible/wearables/ArmourModel.h"
#else
#include "ArmourModel.h"
#endif
#include <array>
#include <vector>
#include <numeric>
namespace corecu { namespace commando {
using Vec=std::array<double,3>;
enum Family {None,Flame,AcidRifle,Particle,AcidBeam,Lightning,Rocket,PistolLauncher};
struct Weapon {Family family;const char* name;const char* delivery;double interval,range,cone,radius,blast,qualityLow,qualityHigh;bool charged;};
inline Weapon weapon(Family f){
 switch(f){
 case Flame:return {f,"flame","cone",.75,12,40,0,0,465,651,false};
 case AcidRifle:return {f,"acid_rifle","beam",1.5,24,0,.45,0,335,550,false};
 case Particle:return {f,"particle","beam",2.5,32,0,.65,0,1980,2850,true};
 case AcidBeam:return {f,"acid_beam","beam",3,24,0,1.,0,1166.5,2378.5,true};
 case Lightning:return {f,"lightning","beam",2,24,0,1.2,0,1243,2370,true};
 case Rocket:return {f,"rocket","rocket",4,48,0,0,5,1225,2925,true};
 case PistolLauncher:return {f,"pistol_launcher","rocket",3,36,0,0,4,54,101,false};
 default:return {None,"","",0,0,0,0,0,0,1,false};
 }
}
inline Family classify(const std::string& path){
 if(path=="object/weapon/ranged/rifle/rifle_flame_thrower.iff")return Flame;
 if(path=="object/weapon/ranged/rifle/rifle_acid_beam.iff")return AcidRifle;
 if(path=="object/weapon/ranged/heavy/heavy_particle_beam.iff")return Particle;
 if(path=="object/weapon/ranged/heavy/heavy_acid_beam.iff")return AcidBeam;
 if(path=="object/weapon/ranged/heavy/heavy_lightning_beam.iff")return Lightning;
 if(path=="object/weapon/ranged/heavy/heavy_rocket_launcher.iff")return Rocket;
 if(path=="object/weapon/ranged/pistol/pistol_launcher.iff")return PistolLauncher;
 return None;
}
constexpr int TargetCap=6,OverdriveSeconds=6,OverdriveCooldown=120,FocusCooldown=12,SprayCooldown=6;
constexpr double AggregateBudget=2.5,ProjectileSpeed=45,ReferenceRifleMean=245,DirectRate=.9*ReferenceRifleMean;
constexpr double MinimumQuality=140./245.;
inline swgxr::armour::WeaponProfile referenceProfile(Family f){using namespace swgxr::armour;return weapon(f==Flame?Heat:f==AcidRifle || f==AcidBeam?Acid:f==Lightning?Electricity:f==Rocket || f==PistolLauncher?Blast:Energy,f==Particle || f==Rocket?3:f==AcidBeam?2:f==Lightning?1:0);}
constexpr double OverdriveDamage=1.25,OverdriveAction=1.5,FocusedDamage=1.15,SprayDamage=.70;
inline double quality(Family f,double low,double high){auto s=weapon(f);return MinimumQuality+(1.-MinimumQuality)*corecu::clamp(((low+high)*.5-s.qualityLow)/(s.qualityHigh-s.qualityLow),0,1);}
inline double cadence(Family f,double training){return weapon(f).interval*(1.25-.25*corecu::clamp(training,0,1));}
// Equivalent T21 development benchmark: Master Marksman plus Novice Rifleman
// has 35 rifle speed; Master Rifleman reaches95. Damage quality retains the
// source T21 140..245 mean band; its source speed band is10.5..6.5 seconds.
inline double referenceCadence(double training,double quality){double progress=corecu::clamp((training-.1)/.9,0,1),q=corecu::clamp((quality-MinimumQuality)/(1.-MinimumQuality),0,1);return std::max(1.,(1.-(35.+60.*progress)/100.)*(10.5-4.*q));}
// A bounded training allowance accounts for the targeted-attack unlock window
// in the Rifleman benchmark. Clamp to mastered output so the intermediate bonus
// can never make later training lower damage or exceed the mastery envelope.
inline double proficiency(double training,double quality){double p=corecu::clamp((training-.1)/.9,0,1);return std::min(1.,(1.+.33*4*p*(1-p))/referenceCadence(training,quality));}
inline double handling(Family f){return f==Flame?1.06:f==AcidRifle?1.01:.977;}
inline double damage(Family f,double quality,bool focused=false,bool spray=false,double training=1){
 // Author the packet against the ORIGINAL family's conversion tax. Native
 // conversion remains unchanged, including current damage channel/AP/shields.
 return DirectRate*weapon(f).interval*corecu::clamp(quality,MinimumQuality,1)*(focused?FocusedDamage:spray?SprayDamage:1)*proficiency(training,quality)*handling(f)/referenceProfile(f).damageScale;
}
inline int action(Family f,double training,bool overdrive=false,bool focused=false,bool spray=false){return int(std::ceil((weapon(f).interval*(14.-5.*corecu::clamp(training,0,1))+(focused?20:spray?10:0))*(overdrive?OverdriveAction:1)));}
inline int mind(Family f,bool focused=false,bool spray=false){return int(std::ceil(weapon(f).interval*4))+(focused?10:spray?5:0);}
inline bool contains(const std::string& id){return id=="focused_discharge" || id=="acid_spray" || id=="overdrive";}
inline double magnitude(const Vec& p){return std::sqrt(p[0]*p[0]+p[1]*p[1]+p[2]*p[2]);}
inline Vec delta(const Vec& a,const Vec& b){return {{a[0]-b[0],a[1]-b[1],a[2]-b[2]}};}
// Target centre geometry is independent of accuracy ratings. A physical contact
// uses native secondary defenses, armour and damage states without another miss roll.
inline double weight(const Vec& origin,const Vec& direction,const Vec& target,double range,double cone,double radius,double targetRadius=0){
 auto v=delta(target,origin);double distance=magnitude(v);if(!std::isfinite(distance) || distance>range+targetRadius || distance<.001)return 0;
 double along=std::inner_product(v.begin(),v.end(),direction.begin(),0.);if(along<0)return 0;
 double lateral=std::sqrt(std::max(0.,distance*distance-along*along));
 if(cone>0){double boundary=std::tan(cone*3.141592653589793/360.)*along+targetRadius;if(lateral>boundary)return 0;return corecu::clamp(1.-.3*distance/range-.2*lateral/std::max(.01,boundary),.5,1);}
 if(lateral>radius+targetRadius)return 0;return corecu::clamp(1.-.25*along/range-.25*lateral/std::max(.01,radius+targetRadius),.5,1);
}
inline double blastWeight(double distance,double radius){return distance<0 || distance>radius?0:1.-.5*distance/std::max(.01,radius);}
inline std::vector<double> weights(const std::vector<double>& requested){
 std::vector<double> out;for(double w:requested){if(out.size()>=TargetCap)break;out.push_back(corecu::clamp(w,0,1));}
 double total=std::accumulate(out.begin(),out.end(),0.);if(total>AggregateBudget)for(auto& w:out)w*=AggregateBudget/total;return out;
}
inline int burnBudget(int landed){return std::max(0,int(std::floor(landed*.10)));}
inline bool validImpact(const Vec& origin,const Vec& direction,const Vec& hit,double range,double age,double elapsed){
 if(!std::isfinite(age) || age<0 || age>8 || age>elapsed+.4)return false;auto v=delta(hit,origin);double distance=magnitude(v),along=std::inner_product(v.begin(),v.end(),direction.begin(),0.);
 return std::isfinite(distance) && distance<=range+2 && distance<=ProjectileSpeed*age+3 && along>=-.5 && distance*distance-along*along<=9;
}
}}
