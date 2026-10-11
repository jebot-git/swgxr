#pragma once
#include "ActionCombatPolicy.h"
#include <string>
#include <limits>
namespace corecu { namespace ground {
constexpr int protocol=2;
constexpr double centerX=3528,centerZ=-4804,radius=1500;
inline bool inRegion(const action::Vec& p){return action::finite(p)&&std::hypot(p[0]-centerX,p[2]-centerZ)<=radius;}
// CL 1/31/91/151: 6/12/24/36 degrees/s, 1/2/4/6 m/s lateral cap.
inline double trackingScale(int level){return std::min(3.,.5+(std::max(1,level)-1)/60.);}
inline bool groundZone(const std::string& zone){
 for(const char* name:{"tatooine","corellia","naboo","rori","talus","dantooine","dathomir","endor","lok","yavin4"})if(zone==name)return true;
 return false;
}
inline bool inScope(const std::string& mode,const std::string& zone,const action::Vec& home,const action::Vec& current){
 return action::finite(home)&&action::finite(current)&&((mode=="global"&&groundZone(zone))||(mode=="mos_eisley"&&zone=="tatooine"&&inRegion(home)&&inRegion(current)));
}
// Brief boundary excursions do not cancel a warning or reset a group encounter.
struct Pressure {
 double unreachableSince=-1,escapedSince=-1;
 bool cancelPreparation(double now,double lockAt,bool locked,double nearest,double reach,bool ranged){
  if(locked||now>=lockAt){unreachableSince=-1;return false;}
  if(nearest<=reach+(ranged?4.:1.5)){unreachableSince=-1;return false;}
  if(unreachableSince<0)unreachableSince=now;
  return now-unreachableSince>=.2;
 }
 bool disengage(double now,double homeDistance,double nearest,double weaponRange,bool playerEncounter){
  const double escapeDistance=std::max(64.,std::min(128.,weaponRange+24.));
  if(!playerEncounter||(homeDistance<=160.&&nearest<=escapeDistance)){escapedSince=-1;return false;}
  if(escapedSince<0)escapedSince=now;
  return now-escapedSince>=3.;
 }
};
struct Victim {
 action::Attack attack;
 bool warned=false,acknowledged=false,waived=false;
 bool warning(double now){if(now>attack.lockAt()-.1)return false;warned=true;return true;}
 bool acknowledge(double now,uint64_t revision){if(!warned||!attack.aimLocked||attack.aimRevision!=revision||now>attack.deliveryAt()-.05)return false;acknowledged=true;return true;}
 bool receipt(double now,bool hit,double begin,double end,uint64_t revision){
  if(!acknowledged||waived)return false;
  if(attack.reported)return attack.aimRevision==revision&&attack.hit==hit;
  return attack.receipt(now,hit,begin,end,revision);
 }
 bool ready(double now) const {return now>=attack.endAt()&&(attack.reported||now>=attack.deadline());}
 // Missing/late warning or missing coverage never produces an unseen hit.
 // Record separately: a client-authority policy, not proof against a lying client.
 bool resolve(){if(!acknowledged||!attack.reported){waived=true;attack.cancelled=true;}return attack.resolve();}
};
// Costs are charged once at delivery; each defender receives one native outcome.
inline uint64_t& resolvingActor(){static thread_local uint64_t v=0;return v;}
inline bool resolving(uint64_t actor){return actor!=0&&actor==resolvingActor();}
struct ResolveScope {uint64_t previous;ResolveScope(uint64_t actor):previous(resolvingActor()){resolvingActor()=actor;}~ResolveScope(){resolvingActor()=previous;}};
}}
