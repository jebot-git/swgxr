#include "../server/combat/ActionCombatPolicy.h"
#include <cassert>
#include <iostream>
#include <random>
#include <queue>
using namespace corecu::action;
int main(){
 // One shared strike, three independent victim ledgers. A miss cannot consume
 // another victim's hit; missing receipts fall back separately.
 { Attack shared;shared.start=10;shared.id=50;shared.aimLocked=true;
   Attack target=shared,crossing=shared,avoiding=shared;
   target.sample(11.1,{{0,0,2}});crossing.sample(11.1,{{0,0,2}});avoiding.sample(11.1,{{5,0,2}});
   assert(avoiding.receipt(11.3,false,10.2,11.3,1));
   assert(crossing.receipt(11.3,true,10.2,11.3,1));
   assert(!crossing.receipt(11.31,false,10.2,11.3,1));
   assert(!avoiding.resolve());assert(crossing.resolve());assert(target.due(12));assert(target.resolve());
   assert(!crossing.resolve());Attack left=shared;left.cancelled=true;assert(!left.receipt(11.3,true,10.2,11.3,1));assert(!left.resolve());
 }

 // Bounded steering, wraparound, planted origin, final immutable aim and stale
 // receipt rejection. The far target exercises the 2 m/s lane speed cap.
 for(double distanceToTarget:{2.,24.}){
  Attack tracked;tracked.start=10;tracked.role=Role::Ranged;
  auto origin=tracked.origin;
  for(int i=1;i<=18;++i)tracked.prepare(10+i*.05,{{distanceToTarget,0,0}});
  assert(tracked.aimLocked && tracked.origin==origin);
  double angle=std::atan2(tracked.aim[0],tracked.aim[2]);
  double limit=std::min(12.*3.141592653589793/180.,2./distanceToTarget);
  assert(std::abs(angle-limit*.9)<1e-7);
  auto aim=tracked.aim;auto revision=tracked.aimRevision;
  assert(!tracked.prepare(11.5,{{-24,0,0}}) && tracked.aim==aim && tracked.aimRevision==revision);
  assert(!tracked.receipt(tracked.endAt()+.1,true,10.1,tracked.endAt()+.05,revision-1));
  assert(tracked.receipt(tracked.endAt()+.1,false,10.1,tracked.endAt()+.05,revision));
 }
 Attack wrap;wrap.aim=direction({{0,0,0}},{{.001,0,-2}});
 auto before=std::atan2(wrap.aim[0],wrap.aim[2]);wrap.prepare(.05,{{-.001,0,-2}});
 auto after=std::atan2(wrap.aim[0],wrap.aim[2]);assert(std::abs(std::atan2(std::sin(after-before),std::cos(after-before)))<.002);
 Attack stalled;stalled.prepare(5,{{2,0,0}});assert(stalled.aimLocked && std::atan2(stalled.aim[0],stalled.aim[2])<.022);
 Attack support;support.role=Role::Support;support.prepare(2,{{2,0,0}});assert(support.aimLocked && support.aimRevision==1 && support.aim[0]==0);
 Attack cancelled;cancelled.cancelled=true;assert(!cancelled.prepare(.2,{{2,0,0}}));
 Attack ranged;ranged.role=Role::Ranged;ranged.start=10;
 assert(std::abs(ranged.activeAt()-ranged.deliveryAt()-1./3.)<.00001);
 assert(ranged.animationEndAt()>=ranged.endAt() && ranged.recoveredAt()>ranged.animationEndAt());
 Attack a;a.id=1;a.start=10;a.origin={{0,0,0}};a.aim={{0,0,1}};
 assert(!a.receipt(10.8,true,10,11.3,1));
 a.prepare(10.7,{{0,0,2}});a.sample(11.1,{{0,0,2}});assert(a.fallback);
 assert(!a.due(11.3));assert(a.receipt(11.4,false,10.4,11.3,1));
 assert(!a.receipt(11.5,true,10.4,11.3,1));assert(a.due(11.5));assert(!a.resolve());
 assert(!a.receipt(11.6,true,10.4,11.3,1));
 a={};a.start=10;a.sample(11.1,{{0,0,2}});a.sample(11.4,{{9,0,2}});assert(a.due(12)&&a.resolve());
 a={};a.start=10;assert(!a.receipt(11.5,false,11.1,11.3,1));a.cancelled=true;assert(!a.due(12));assert(!a.resolve());
 assert(contact(Role::Melee,{{0,0,0}},{{0,0,1}},{{0,0,2}}));
 assert(!contact(Role::Melee,{{0,0,0}},{{0,0,1}},{{0,0,-2}}));
 assert(!contact(Role::Melee,{{0,0,0}},{{0,0,1}},{{2,0,0}}));
 assert(contact(Role::Ranged,{{0,0,0}},{{0,0,1}},{{.7,0,20}}));
 assert(!contact(Role::Ranged,{{0,0,0}},{{0,0,1}},{{.9,0,20}}));
 assert(!confirmedContact(7,9));{ContactScope scope(7,9);assert(confirmedContact(7,9));assert(!confirmedContact(9,7));{ContactScope nested(8,9);assert(confirmedContact(8,9));assert(!confirmedContact(7,9));}assert(confirmedContact(7,9));}assert(!confirmedContact(7,9));
 // Deterministic network scenarios: 50/100/200ms RTT, jitter, lost messages,
 // 1/50/100/200 independent encounters. CPU execution != native server load.
 std::mt19937 rng(73);std::uniform_real_distribution<double> jitter(-.02,.06);
 for(int groups:{1,50,100,200})for(double rtt:{.05,.1,.2}){
  int missed=0,hits=0,reports=0,fallback=0;double maxLate=0;
  for(int n=0;n<groups*100;++n){
   Attack attack;attack.start=0;attack.role=n%2?Role::Melee:Role::Ranged;
   bool dodge=n%2==0,loss=n%10==0;double arrival=rtt*.5+std::max(0.,jitter(rng));
   double receiptAt=attack.endAt()+.03+rtt*.5+std::max(0.,jitter(rng));
   for(double t=0;t<=attack.deadline()+.02;t+=.01){
    Vec feet=dodge&&t>.5?Vec{{4,0,2}}:Vec{{0,0,2}};
    attack.prepare(t,feet);attack.sample(t,feet);
    if(!loss && t>=receiptAt && !attack.reported && !attack.settled){assert(attack.receipt(t,!dodge,arrival,attack.endAt()+.03,attack.aimRevision));++reports;}
    if(attack.due(t)){if(!attack.reported)++fallback;bool hit=attack.resolve();assert(hit!=dodge);hit?++hits:++missed;maxLate=std::max(maxLate,t-attack.endAt());}
   }
   assert(attack.settled);
  }
  std::cout<<"{\"groups\":"<<groups<<",\"rtt_ms\":"<<rtt*1000<<",\"trials\":"<<groups*100<<",\"hits\":"<<hits<<",\"avoided\":"<<missed<<",\"accepted\":"<<reports<<",\"fallback\":"<<fallback<<",\"max_settlement_ms\":"<<maxLate*1000<<"}\n";
 }
}
