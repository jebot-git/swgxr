#include "../server/combat/SwgxrPveRewardPolicy.h"
#include <cassert>
#include <iostream>
using namespace SwgxrPveRewardPolicy;
int main(){
 int checks=0;auto check=[&](bool condition){assert(condition);++checks;};
 // Equal-modifier players split a kill according to actual health removed.
 auto first=hamDamage(100,70,true,true,false,false);
 auto last=hamDamage(30,100000,true,true,false,false);
 check(first==70);check(last==30);auto total=accumulate(first,last);
 check(cappedShare(1000,3000,first,total)==700);check(cappedShare(1000,3000,last,total)==300);
 // Preserve proportionality when native per-player full-kill levelcap applies.
 check(cappedShare(100000,300,70,100)==210);check(cappedShare(100000,300,30,100)==90);
 // A NPC/environmental or no-XP source did half the work; no redistribution.
 check(cappedShare(1000,3000,70,200)==350);check(cappedShare(1000,3000,30,200)==150);
 // Dropping a dead/offline contributor does not alter the encounter denominator.
 std::uint64_t recorded=100;check(cappedShare(1000,3000,30,recorded)==300);
 check(cappedShare(1000,3000,0,recorded)==0);check(fraction(10,0)==0);
 // Actual DOT ticks contribute only applied damage, with native nonlethal floor.
 check(hamDamage(10,100,true,false,false,false)==9);
 check(hamDamage(1,100,true,false,false,false)==0);
 check(hamDamage(10,100,true,true,false,false)==10);
 check(hamDamage(10,100,true,true,true,false)==9);
 check(hamDamage(10,100,true,true,false,true)==10);
 check(hamDamage(100,10,false,true,false,false)==0); // dead/incap/invulnerable
 check(hamDamage(100,-10,true,true,false,false)==0); // healing
 check(hamDamage(100,.8,true,true,false,false)==0); // no actual integer HAM removed
 check(hamDamage(100,std::numeric_limits<double>::infinity(),true,true,false,false)==0);
 check(hamDamage(100,std::numeric_limits<double>::quiet_NaN(),true,true,false,false)==0);
 check(hamDamage(0,100,true,true,false,false)==0); // duplicate/postmortem
 check(conditionDamage(70,100,100000,true)==30); // lair overkill
 check(conditionDamage(100,100,100000,true)==0); // duplicate death
 check(conditionDamage(70,100,100000,false)==29);
 check(conditionDamage(99,100,100000,false)==0);
 // Pet-owner contribution uses the same proportion of native CH full-kill XP.
 check(500*fraction(25,100)==125);check(500*fraction(0,100)==0);
 // Corpse/credits/organics: explicit final blower only, never top-damage/group.
 check(lootOwner(22,0,99)==22);check(lootOwner(0,22,99)==22);
 check(lootOwner(0,0,99)==99);check(lootOwner(22,33,99)==22);
 check(accumulate(std::numeric_limits<std::uint64_t>::max()-3,7)==std::numeric_limits<std::uint64_t>::max());
 std::cout<<"{\"passed\":true,\"policy_checks\":"<<checks<<",\"native_core3_execution\":false}"<<std::endl;
}
