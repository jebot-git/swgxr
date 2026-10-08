#include "server/combat/CoreCuPolicy.h"
#include "server/combat/ArmourModel.h"
#include <cassert>
#include <iostream>
int main(){
 using namespace corecu;
 int cases=0;
 // Shields cannot affect primary/legacy channels, even with extreme quality.
 for(int channel:{1,2,4,8,16})for(double q:{0.,40.,80.,1000.}){
  assert(shieldResistance(channel,q)==0);
  assert(equipmentResistance(channel,.25,.5)==.25);++cases;
 }
 for(int channel:{32,64,128,256}){
  assert(shieldResistance(channel,0)==0);assert(shieldResistance(channel,80)==.5);
  assert(equipmentResistance(channel,.4,.3)==.4);assert(equipmentResistance(channel,.3,.4)==.4);++cases;
 }
 // Exhaustively test the original penetration budget with equipped shield/body combinations.
 for(int ap=0;ap<4;++ap)for(int base=0;base<=10;++base)for(int element=0;element<=10;++element)for(int shield=0;shield<=10;++shield){
  const double rb=base*.05,re=equipmentResistance(32,element*.05,shield*.05);
  const auto p=swgxr::armour::weapon(swgxr::armour::Energy,ap);
  swgxr::armour::Damage hit(1,p);hit.mitigate(rb,re);
  const double budget[]={0,.05,.10,.20};
  assert(hit.total()/(1-rb)<=1+budget[ap]+1e-9);
  assert(hit.total()>=.5*p.damageScale);++cases;
 }
 for(int level=1;level<=350;++level)for(double legacy:{-1.,0.,15.,50.,95.}){
  double r=resistance(level,3,legacy);assert(r>=0 && r<=.5);
  if(level>1)assert(r>=resistance(level-1,3,legacy));++cases;
 }
 assert(resistance(40,1,-1)<resistance(40,1,95));
 assert(npcHamScale(336)==1);assert(npcDamageScale(336)>npcDamageScale(25));
 assert(specialCooldown(336)<specialCooldown(25));
 for(double rating:{0.,20.,60.,100.,200.,1000.}){
  assert(statusChance(175,rating)>0 && statusChance(175,rating)<=95);
  assert(statusDuration(10,rating)>=4 && statusDuration(10,rating)<=10);
  assert(statusDuration(0,rating)==0);++cases;
 }
 assert(statusChance(75,60)<statusChance(75,20));
 assert(statusDuration(10,60)<statusDuration(10,20));
 assert(combinedRating(60,60)==75);assert(combinedRating(60,500)==100);
 double progress=progressWeight("combat_polearm","combat_polearm_novice");
 for(auto branch:{"accuracy","speed","ability","support"})for(int tier=1;tier<=4;++tier)
  progress+=progressWeight("combat_polearm",std::string("combat_polearm_")+branch+"_0"+std::to_string(tier));
 progress+=progressWeight("combat_polearm","combat_polearm_master");
 assert(std::abs(progress-1)<1e-9);
 assert(progressWeight("combat_polearm","combat_polearm")==0);
 assert(progressWeight("combat_polearm","combat_polearm_support_05")==0);
 assert(progressWeight("combat_polearm","combat_rifleman_master")==0);
 for(int seconds:{1,10,20,30,40,60})for(int interval:{5,10,20,40})for(int effects:{1,2,4}){
  const double tick=dotTickBudget(1000,effects,seconds,interval,10000);
  const int first=firstTickMillis(seconds,interval);
  assert(first>0 && first<seconds*1000);
  int actualTicks=0;
  for(int millis=first;millis<seconds*1000;millis+=interval*1000)++actualTicks;
  assert(actualTicks>=1);
  assert(tick*actualTicks*effects<=500+1e-9);
  assert(tick*std::ceil(double(seconds)/interval)*effects<=500+1e-9);++cases;
 }
 assert(dotTickBudget(0,1,60,10,1000)==0);
 std::cout<<"CoreCU policy: "<<cases<<" combinations passed\n";
}
