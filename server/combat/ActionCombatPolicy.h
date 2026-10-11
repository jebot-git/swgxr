#pragma once
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>

// Prototype action geometry uses source axes: X, elevation, Z.
// No health, equipment, rewards or client-owned damage values live here.
namespace corecu { namespace action {
using Vec = std::array<double,3>;
enum class Role { Melee, Ranged, Support };
struct Spec {
 double windup, active, recovery, range, radius, cosine, preferred;
};
inline Spec spec(Role role) {
 if (role==Role::Ranged) return {1.2,.2,1.8,24,.45,.995,12};
 if (role==Role::Support) return {1.5,.2,4.,18,0,0,9};
 return {1.,.25,1.4,3.,.35,.5,2.2};
}
inline const char* animation(Role role) {return role==Role::Melee?"action_worrt":role==Role::Ranged?"action_pistol":"action_heal";}
inline double animationDuration(Role role) {return role==Role::Melee?.5:role==Role::Ranged?1.:80./30.;}
// Worrt has no authored contact marker: retain its conservative active window.
inline double contactOffset(Role role) {return role==Role::Ranged?10./30.:role==Role::Support?80./30.:0.;}
inline double distance(Vec a,Vec b) {return std::hypot(a[0]-b[0],a[2]-b[2]);}
inline Vec direction(Vec a,Vec b) {double n=distance(a,b);return n>.0001?Vec{{(b[0]-a[0])/n,0,(b[2]-a[2])/n}}:Vec{{0,0,1}};}
inline bool finite(Vec v) {for(auto x:v)if(!std::isfinite(x)||std::abs(x)>20000)return false;return true;}
inline bool contactSpec(Role role,const Spec& s,Vec origin,Vec aim,Vec feet,double bodyRadius=.35,double heightTolerance=2.5) {
 if(!finite(origin)||!finite(aim)||!finite(feet)||std::abs(feet[1]-origin[1])>heightTolerance)return false;
 double x=feet[0]-origin[0],z=feet[2]-origin[2],d=std::hypot(x,z);
 if(d>s.range+bodyRadius)return false;
 double along=x*aim[0]+z*aim[2];
 if(role==Role::Ranged)return along>=-bodyRadius && std::abs(x*aim[2]-z*aim[0])<=s.radius+bodyRadius;
 return d<=bodyRadius || along>=s.cosine*std::max(0.,d-bodyRadius);
}
inline bool contact(Role role,Vec origin,Vec aim,Vec feet,double bodyRadius=.35){return contactSpec(role,spec(role),origin,aim,feet,bodyRadius);}
struct Attack {
 uint64_t id=0; Role role=Role::Melee; Vec origin{},aim{{0,0,1}};
 double start=0; bool sampled=false, fallback=false, reported=false, hit=false, settled=false, cancelled=false;
 double trackedAt=0; uint64_t aimRevision=1; bool aimLocked=false;
 bool customized=false;Spec profile{};double clipDuration=0,contactDelay=0,lockLead=.3;
 const Spec settings() const {return customized?profile:spec(role);}
 double deliveryAt() const {return start+settings().windup;}
 double lockAt() const {return deliveryAt()-lockLead;}
 // Server-only preparation steering. No pursuit, prediction or catch-up snap.
 // A stalled tick may consume at most 100 ms of preparation, never delivery time.
 bool prepare(double now,Vec target) {
  if(cancelled||settled||aimLocked||now<std::max(start,trackedAt))return false;
  double dt=std::min(.1,std::max(0.,std::min(now,lockAt())-std::max(start,trackedAt)));
  trackedAt=now;bool changed=false;
  const double d=distance(origin,target);
  if(role!=Role::Support && finite(target) && d>.0001 && dt>0){
   double current=std::atan2(aim[0],aim[2]),desired=std::atan2(target[0]-origin[0],target[2]-origin[2]);
   double error=std::atan2(std::sin(desired-current),std::cos(desired-current));
   double limit=std::min(12.*3.141592653589793/180.,2./d)*dt;
   double turn=std::max(-limit,std::min(limit,error));
   if(std::abs(turn)>1e-9){aim={{std::sin(current+turn),0,std::cos(current+turn)}};++aimRevision;changed=true;}
  }
  if(now>=lockAt()){aimLocked=true;changed=true;}
  return changed;
 }
 double animationEndAt() const {return deliveryAt()+(customized?clipDuration:animationDuration(role));}
 double activeAt() const {return deliveryAt()+(customized?contactDelay:contactOffset(role));}
 double endAt() const {return activeAt()+settings().active;}
 double deadline() const {return endAt()+.65;}
 double recoveredAt() const {return std::max(deadline(),std::max(endAt(),animationEndAt())+settings().recovery);}
 void sample(double now,Vec feet) {if(now>=activeAt() && now<=endAt()){sampled=true;fallback=fallback||contactSpec(role,settings(),origin,aim,feet,.35,customized?20000:2.5);}}
 // First receipt wins, including misses. Missing reports use native active-window
 // samples. Never decide contact using a target's later position at settlement.
 bool receipt(double now,bool value,double coverageStart,double coverageEnd,uint64_t revision) {
  if(!aimLocked||revision!=aimRevision||cancelled||settled||reported||now<endAt()||now>deadline() ||
     !std::isfinite(coverageStart)||!std::isfinite(coverageEnd)||
     coverageStart>activeAt()+.025||coverageStart<start || coverageEnd<endAt()||coverageEnd>deadline())return false;
  reported=true;hit=value;return true;
 }
 bool due(double now) const {return !settled&&!cancelled&&now>=endAt()&&(reported||now>=deadline());}
 bool resolve() {if(settled)return false;settled=true;return !cancelled&&(reported?hit:fallback);}
};
// Only a native committed prototype action can bypass the primary NPC hit roll.
// Secondary defenses and all RPG outcomes continue through CombatManager.
using ContactPair=std::array<uint64_t,2>;
inline ContactPair& contactPair() {static thread_local ContactPair value{{0,0}};return value;}
inline bool confirmedContact(uint64_t attacker,uint64_t defender) {return attacker!=0&&contactPair()==ContactPair{{attacker,defender}};}
struct ContactScope {ContactPair old;ContactScope(uint64_t a,uint64_t d):old(contactPair()){contactPair()={{a,d}};}~ContactScope(){contactPair()=old;}};
}}
