#include "server/combat/SwordsmanPolicy.h"
#include "server/combat/CoreCuLoadoutPolicy.h"
#include "server/combat/ArmourModel.h"
#include <cassert>
#include <iostream>
int main(){
 using namespace corecu::swordsman;
 assert(namedBoss("tusken_king") && namedBoss("lord_nyax") && namedBoss("warren_agro_droid_boss"));
 assert(!namedBoss("minion_of_lord_nyax") && !namedBoss("kliknik_queen"));
 assert(!executeReady(30,100,1,false));assert(executeReady(29,100,1,false));
 assert(!executeReady(0,100,1,false));assert(!executeReady(1,0,1,false));
 assert(!executeReady(1,100,151,false));assert(!executeReady(1,100,10,true));
 assert(executionMultiplier(30,false)==3);assert(executionMultiplier(90,false)==2.125);
 assert(executionMultiplier(150,false)==1.25);assert(executionMultiplier(151,false)==0);assert(executionMultiplier(1,true)==0);
 double prior=4;for(int level=1;level<=150;++level){auto m=executionMultiplier(level,false);assert(m<=prior && m>=1.25);prior=m;}
 int cases=0;
 for(int score=0;score<=8000;score+=100)for(int channel:{1,2,32,64,128,256})for(int ap=0;ap<=3;++ap){
  double r=swgxr::armour::reduction(score),reduced=fracturedResistance(r,channel,true);
  assert(std::abs(reduced-((channel==1||channel==2)?swgxr::armour::reduction(score*.5):r))<1e-10);
  assert(fracturedResistance(r,channel,false)==r);
  auto p=swgxr::armour::weapon(channel,ap);swgxr::armour::Damage normal(100,p),broken(100,p);
  normal.mitigate(r,r);broken.mitigate(fracturedResistance(r,p.base,true),fracturedResistance(r,p.element,true));
  assert(broken.total()>=normal.total()-1e-9 && broken.total()<=normal.total()*4/3.+1e-9);++cases;
 }
 assert(std::abs(fracturedResistance(.5,1,true)-1./3)<1e-10);
 assert(ability("ground_slam").gesture && !ability("ground_slam").control);
 assert(ability("armour_break").ultimate && ability("armour_break").cooldown==120);
 assert(!corecu::ultimateAllowed("armour_break",[](const std::string& s){return s=="combat_brawler_master";}));
 assert(!corecu::ultimateAllowed("armour_break",[](const std::string& s){return s=="combat_2hsword_novice";}));
 assert(corecu::ultimateAllowed("armour_break",[](const std::string& s){return s=="combat_2hsword_master";}));
 std::cout<<cases<<" armour/AP cases, level taper, boss exclusion, Health threshold and ultimate ownership passed\n";
}
