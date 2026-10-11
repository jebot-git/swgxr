#pragma once
#include "ActionCombatPolicy.h"
namespace corecu { namespace ground {
constexpr int protocol=2;
constexpr double centerX=3528,centerZ=-4804,radius=1500;
inline bool inRegion(const action::Vec& p){return action::finite(p)&&std::hypot(p[0]-centerX,p[2]-centerZ)<=radius;}
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
