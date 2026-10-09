#include "server/combat/PikemanPolicy.h"
#include "server/combat/CoreCuLoadoutPolicy.h"
#include <cassert>
#include <iostream>
int main(){
 using namespace corecu::pikeman;
 const corecu::warcry::Vec feet{0,0,0},forward{0,0,-1};
 auto in=[&](const Ability& a,corecu::warcry::Vec p){return corecu::tka::inCone(feet,forward,p,{4,a.cosine,a.damage,a.cooldown,a.recovery,a.targets,a.blows,a.action,a.mind});};
 auto whirl=ability("overhead_whirl"),sweep=ability("sweeping_trip"),jabs=ability("driving_jabs"),ultimate=ability("whirlwind");
 assert(whirl.targets==4 && sweep.targets==3 && jabs.targets==2 && jabs.blows==2 && ultimate.targets==6);
 assert(in(whirl,{0,0,3}) && in(ultimate,{0,0,3}));
 assert(in(sweep,{3,0,-.1}) && !in(sweep,{3,0,.1}));
 assert(in(jabs,{.2,0,-3}) && !in(jabs,{2,0,-2}));
 for(auto a:{whirl,sweep,jabs,ultimate}){assert(!in(a,{0,0,-4.01}));assert(!in(a,{0,4,1}));assert(ready(a,false));}
 assert(!ready(ability("knockdown_strike"),false));assert(!ready(ability("polearm_stun"),false));assert(!ready(ability("disrupting_jab"),false));assert(ready(ability("pinning_strike"),false));
 assert(ability("knockdown_strike").duration==2 && ultimate.duration==3 && ability("polearm_stun").duration==4);
 assert(cooldownKey("knockdown_strike")=="corecu_brawler_knockdown_strike");assert(cooldownKey("polearm_stun")=="corecu_brawler_polearm_stun");
 assert(chance(100,.1)==57 && chance(100,1)==60 && chance(0,1)==95);
 int cases=0;for(int a=0;a<=100;a+=10)for(int b=0;b<=100;b+=10)for(int c=0;c<=100;c+=10){int value=strongestSlow(a,b,c,30);assert(value==std::max(30,std::max(a,std::max(b,c))));++cases;}
 assert(strongestSlow(-5,-1,0,0)==0 && strongestSlow(500,0,0,0)==100);
 assert(!corecu::ultimateAllowed("whirlwind",[](const std::string& s){return s=="combat_brawler_master" || s=="combat_polearm_novice";}));
 assert(corecu::ultimateAllowed("whirlwind",[](const std::string& s){return s=="combat_polearm_master";}));
 assert(ability("forged").targets==0);
 std::cout<<cases<<" strongest-slow combinations; AoE shapes/caps, recovery, progression and master ownership passed\n";
}
