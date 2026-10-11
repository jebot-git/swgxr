#pragma once
#include "ActionCombatPolicy.h"
#include <string>
#include <limits>
#include <vector>
#include <algorithm>
#include <tuple>
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
 // Presentation time is client-authoritative, just like sampled contact. A
 // delayed HTTP acknowledgement must not erase a warning actually seen on time.
 // Bound clock skew/transport age and retain the original visibility deadlines.
 bool presentation(double now,double shown) const {return std::isfinite(shown)&&shown>=attack.start-.3&&shown<=now+.05&&now-shown<=1.0&&now<=attack.deadline()&&!attack.cancelled&&!attack.settled;}
 bool warning(double now,double shown){if(!presentation(now,shown)||shown>attack.lockAt()-.1)return false;warned=true;return true;}
 bool warning(double now){return warning(now,now);}
 bool acknowledge(double now,uint64_t revision,double shown){if(!warned||!attack.aimLocked||attack.aimRevision!=revision||!presentation(now,shown)||shown<attack.lockAt()-.05||shown>attack.deliveryAt()-.05)return false;acknowledged=true;return true;}
 bool acknowledge(double now,uint64_t revision){return acknowledge(now,revision,now);}
 bool receipt(double now,bool hit,double begin,double end,uint64_t revision,double contactAt=std::numeric_limits<double>::quiet_NaN()){
  if(!acknowledged||waived)return false;
  if(attack.reported)return attack.aimRevision==revision&&attack.hit==hit;
  if(!std::isnan(contactAt)){
   if(!hit||!std::isfinite(contactAt)||contactAt<attack.activeAt()||contactAt>attack.endAt()||contactAt>end||begin>contactAt||begin<attack.start)return false;
   // A positive observed sample needs no continuous proof of absence. Keep
   // the same acknowledgement, revision, settlement and receipt-age fences.
   return attack.receipt(now,true,attack.activeAt(),end,revision);
  }
  return attack.receipt(now,hit,begin,end,revision);
 }
 bool ready(double now) const {return now>=attack.endAt()&&(attack.reported||now>=attack.deadline());}
 // Missing/late warning or missing coverage never produces an unseen hit.
 // Record separately: a client-authority policy, not proof against a lying client.
 bool resolve(){if(!acknowledged||!attack.reported){waived=true;attack.cancelled=true;}return attack.resolve();}
};
// Cleaves settle independently. Single-interceptor lanes wait for all eligible
// reports (or the shared deadline), then choose nearest along the locked lane.
inline bool canSettle(bool firstContact,bool allReady,bool victimReady,bool settled){return !settled&&victimReady&&(!firstContact||allReady);}
struct Interceptor {double distance,contactAt;uint64_t id;};
inline void arbitrate(std::vector<Interceptor>& hits,bool firstContact){
 std::sort(hits.begin(),hits.end(),[](const Interceptor& a,const Interceptor& b){return std::tie(a.distance,a.contactAt,a.id)<std::tie(b.distance,b.contactAt,b.id);});
 if(firstContact&&hits.size()>1)hits.resize(1);
}
// Costs are charged once at delivery; each defender receives one native outcome.
inline uint64_t& resolvingActor(){static thread_local uint64_t v=0;return v;}
inline bool resolving(uint64_t actor){return actor!=0&&actor==resolvingActor();}
struct ResolveScope {uint64_t previous;ResolveScope(uint64_t actor):previous(resolvingActor()){resolvingActor()=actor;}~ResolveScope(){resolvingActor()=previous;}};
}}
