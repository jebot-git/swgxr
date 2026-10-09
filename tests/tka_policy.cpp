#include "server/combat/TkaPolicy.h"
#include "server/combat/CoreCuLoadoutPolicy.h"
#include <cassert>
#include <iostream>
int main(){
 using namespace corecu::tka;
 const corecu::warcry::Vec feet{0,0,0},front{0,0,-1};
 auto sweep=attack("tka_sweep"),spin=attack("tka_half_spin"),volley=attack("tka_volley");
 assert(sweep.targets==6 && spin.targets==8 && volley.targets==4 && volley.blows==3);
 assert(inCone(feet,front,{0,0,-2},sweep));assert(!inCone(feet,front,{0,0,2},sweep));
 assert(inCone(feet,front,{2,0,-.1},spin));assert(!inCone(feet,front,{2,0,-.1},sweep));
 assert(!inCone(feet,front,{2,0,-2},volley));assert(inCone(feet,front,{.5,0,-2},volley));
 assert(!inCone(feet,front,{0,0,-3.01},sweep));assert(!inCone(feet,front,{0,4,-1},sweep));
 assert(!inCone(feet,front,{0,0,-1},attack("forged")));
 assert(center(40,70,false)==40);assert(center(40,70,true)==100);assert(center(0,30,true)==45);
 assert(center(95,70,true)==100);assert(resistance(60,true)==80);assert(resistance(95,true)==100);
 assert(center(140,70,true)==140);
 assert(resistance(120,true)==120);assert(resistance(60,false)==60);
 assert(threat(0)==0);assert(threat(50)==140);assert(threat(50,true)==400);assert(threat(100000,true)==5000);
 assert(!corecu::ultimateAllowed("indomitable_focus",[](const std::string& s){return s=="combat_brawler_master";}));
 assert(!corecu::ultimateAllowed("indomitable_focus",[](const std::string& s){return s=="combat_unarmed_novice";}));
 assert(corecu::ultimateAllowed("indomitable_focus",[](const std::string& s){return s=="combat_unarmed_master";}));
 std::cout<<"TKA cones, limits, threat, focus caps and profession policy passed\n";
}
