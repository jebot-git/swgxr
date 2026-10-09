#include "server/combat/CarbineerPolicy.h"
#include "server/combat/PikemanPolicy.h"
#include "server/combat/CoreCuLoadoutPolicy.h"
#include <cassert>
#include <iostream>
int main(){using namespace corecu::carbineer;int checks=0;
 for(double rating:{0.,10.,25.,50.,75.,100.})for(bool brace:{false,true})for(bool rank:{false,true}){auto actual=chance(rating,brace,rank);auto expected=corecu::learnedStatusChance(rank?90:85,brace?10:0,rating);assert(actual==expected);assert(actual<=95 && actual>=0);++checks;}
 assert(chance(0,false,false)==85 && chance(0,false,true)==90 && chance(0,true)==95);++checks;
 for(auto id:{"full_auto_sweep","charge_blast"}){auto a=ability(id);for(double supported:{0.,1.,10.,18.,20.,64.}){assert(range(a,supported)==std::min(a.range,supported));++checks;}assert(area(a));assert(a.targets==(std::string(id)=="charge_blast"?6:5));++checks;}
 for(int old:{0,30,40,100})for(int cripple:{0,40})for(int sweep:{0,35}){int mixed=strongestSlow(corecu::pikeman::strongestSlow(old,30,40,0),cripple,sweep);assert(mixed==std::max({old,30,40,cripple,sweep}));++checks;}
 assert(strongestSlow(-3,-5,-10)==0 && strongestSlow(200,40,35)==100);++checks;
 for(auto id:{"crippling_shot","wild_shot","charge_shot","full_auto_sweep","tactical_brace","charge_blast"}){assert(contains(id));auto a=ability(id);assert(a.cooldown>0 && a.action>0 && a.mind>0);assert(a.ultimate==(std::string(id)=="charge_blast"));++checks;}
 assert(!contains("forward_check") && !contains("fan_shot"));assert(corecu::ultimateProfession("charge_blast")=="combat_carbine_master");++checks;
 assert(corecu::pistoleer::validPose({{0,1,0}},{{0,1,0}},{{0,0,0}}));assert(!corecu::pistoleer::validPose({{0,3,0}},{{0,1,0}},{{0,0,0}}));++checks;
 std::cout<<checks<<" Carbineer policy chance/range/slow/registration checks passed\n";
}
