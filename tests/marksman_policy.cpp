#include "server/combat/MarksmanPolicy.h"
#include "server/combat/FencerPolicy.h"
#include "server/combat/CoreCuLoadoutPolicy.h"
#include <cassert>
#include <iostream>
int main(){
 using namespace corecu::marksman;
 int checks=0;
 for(auto id:{"suppression_fire","warning_shot","controlled_burst","bleeding_shot"}){
  auto a=ability(id);assert(a.action>0 && a.mind>0 && a.cooldown>=12 && a.blows>=1 && a.blows<=3);
  for(int family=0;family<5;++family){bool ranged=family<4,pistol=family==0,carbine=family==1;
   bool expected=ranged && (std::string(id)=="controlled_burst"?carbine:std::string(id)=="bleeding_shot"?pistol:true);
   assert(compatible(id,ranged,pistol,carbine)==expected);++checks;
  }
  assert(!corecu::ultimateAllowed(id,[](const std::string&){return true;}));++checks;
 }
 assert(!contains("aim") && !contains("threaten_shot") && !compatible("unknown",true,true,true));
 assert(hesitationSeconds(false)==2 && hesitationSeconds(true)==3);
 assert(ability("controlled_burst").blows*ability("controlled_burst").damage<2);
 for(int damage=-10;damage<=2000;damage+=7){
  int budget=bleedBudget(damage);assert(budget>=0 && budget<=std::max(0,damage)*.3);
  assert(budget<=std::max(0,damage)*corecu::fencer::bleedScale(0,false));
  int remaining=budget,paid=0;for(int tick=0;tick<12;++tick){paid+=corecu::fencer::spendTick(remaining,(budget+3)/4);assert(paid<=budget);}
  assert(paid==budget && remaining==0);
  assert(corecu::fencer::refreshBudget(500,budget)==std::max(500,budget));++checks;
 }
 corecu::CombatLoadout slots;slots.slots={"lethal_shot","suppression_fire","warning_shot","bleeding_shot"};
 assert(slots.valid({"lethal_shot","suppression_fire","warning_shot","bleeding_shot"},{}));
 slots.slots[3]="controlled_burst";assert(!slots.valid({"lethal_shot","suppression_fire","warning_shot","bleeding_shot"},{}));
 std::cout<<checks<<" Marksman family, bounded bleed, no-ultimate and loadout checks passed\n";
}
