#include "server/combat/PistoleerPolicy.h"
#include "server/combat/CoreCuLoadoutPolicy.h"
#include <cassert>
#include <iostream>
int main(){using namespace corecu::pistoleer;
 assert(ability("double_tap").damage*ability("double_tap").blows==1.6);
 assert(ability("showdown").blows==1 && ability("showdown").ultimate && ability("showdown").cooldown==120);
 for(auto id:{"double_tap","disarming_shot","bleeding_shot","warning_shot","lethal_shot","restraining_shot","low_blow","concussion_shot_improved"})assert(costScale(true,id)==.75);
 for(auto id:{"","fan_shot","run_and_gun","showdown","last_ditch"})assert(costScale(true,id)==1.);
 assert(cost(45,true,"disarming_shot")==34 && cost(150,true,"showdown")==150);
 assert(fireInterval(2,true,"")==1.6 && fireInterval(2,true,"double_tap")==2 && fireInterval(2,false,"")==2);
 assert(validPose({{0,1,0}},{{0,1,0}},{{0,0,0}}));assert(!validPose({{0,3,0}},{{0,1,0}},{{0,0,0}}));
 assert(fanRange(60)==12 && fanRange(8)==8);
 for(int native:{0,10,20,40})for(int stun:{0,10,50})for(int fencer:{0,15})for(int disarming:{0,20})for(int showdown:{0,30}){
  auto result=suppressionGap(native,stun,fencer,disarming,showdown)+stun;
  assert(result==std::max({native+stun,fencer,disarming,showdown}));
 }
 Volley v;v.item="pistol";v.target="enemy";v.started=v.lastLaunch=10;v.revision=3;v.reservation=12;
 assert(v.accepts("pistol","enemy",3,1,10.25,12));
 assert(!v.accepts("pistol","enemy",3,1,10.249,12));
 assert(!v.accepts("pistol","enemy",3,1,12.001,12));
 assert(!v.accepts("other","enemy",3,1,10.25,12));
 assert(!v.accepts("pistol","other",3,1,10.25,12));
 assert(!v.accepts("pistol","enemy",4,1,10.25,12));
 assert(!v.accepts("pistol","enemy",3,2,10.25,12));
 assert(!v.accepts("pistol","enemy",3,1,10.25,13));
 assert(!v.effect(0) && v.effect(1) && !v.effect(100));
 v.nextIndex=2;v.lastLaunch=10.25;assert(v.accepts("pistol","enemy",3,2,10.5,12));
 v.invalidated=true;assert(!v.accepts("pistol","enemy",3,2,10.5,12));
 assert(corecu::ultimateProfession("showdown")=="combat_pistol_master");
 std::cout<<"Pistoleer cost/cadence, strongest suppression and volley receipt checks passed\n";
}
