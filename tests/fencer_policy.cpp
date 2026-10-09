#include "server/combat/FencerPolicy.h"
#include "server/combat/CoreCuLoadoutPolicy.h"
#include <cassert>
#include <iostream>
int main(){
 using namespace corecu::fencer;
 assert(progression(.1)==0 && progression(1)==1);
 assert(bleedScale(0,false)==.5 && bleedScale(1,false)==.8 && bleedScale(0,true)==1);
 assert(chance(100,0,false,false)==60);assert(chance(100,1,false,false)==63);
 assert(chance(100,1,true,false)==66);assert(chance(100,1,true,true)==69);
 assert(chance(0,1,true,true)==95);assert(softDuration(8,1)==10);
 for(int state=0;state<corecu::StatusCount;++state){bool soft=state==corecu::Bleed || state==corecu::Blind || state==corecu::Intimidate || state==corecu::Snare;assert(exposed(70,state,true)==(soft?50:70));assert(exposed(70,state,false)==70);assert(exposed(10,state,true)==(soft?0:10));}
 int count=0;
 for(int budget=0;budget<=1000;budget+=5){
  int remaining=budget,paid=0;
  for(int i=0;i<8;++i){paid+=spendTick(remaining,(budget+3)/4);assert(paid<=budget && remaining>=0);}
  assert(remaining==0 && paid==budget);
  remaining=budget;paid=spendTick(remaining,(budget+3)/4);
  int incoming=budget/3,old=remaining;remaining=refreshBudget(remaining,incoming);assert(remaining==std::max(old,incoming));assert(remaining+paid<=budget+incoming);
  for(int i=0;i<10;++i){int before=remaining;int spent=spendTick(remaining,(budget+3)/4);assert(spent<=before);}
  assert(remaining==0);++count;
 }
 assert(!corecu::ultimateAllowed("flawless_assault",[](const std::string& s){return s=="combat_brawler_master" || s=="combat_1hsword_novice";}));
 assert(corecu::ultimateAllowed("flawless_assault",[](const std::string& s){return s=="combat_1hsword_master";}));
 assert(ability("probing_jabs").blows==2 && ability("guard_bash").control && !ability("nerve_strike").control);
 std::cout<<count<<" bleed budget/refresh cases; progression, status caps, exposure exclusions and ultimate ownership passed\n";
}
