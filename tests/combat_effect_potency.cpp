#include "server/combat/CoreCuPolicy.h"
#include "server/combat/FencerPolicy.h"
#include "server/combat/CarbineerPolicy.h"
#include "server/combat/PikemanPolicy.h"
#include "server/medic/CombatMedicPolicy.h"
#include <cassert>
#include <cmath>
#include <limits>
#include <iostream>

int main(){
 using namespace corecu;
 int checks=0;
 const double ratings[]={65,90,100,125};
 const double cmExpected[]={87.2093023256,78.125,75,68.1818181818};
 const double fencerExpected[]={80.2325581395,71.875,69,62.7272727273};
 for(int i=0;i<4;++i){
  const double cm=combatmedic::chance(combatmedic::rawPotency(100,1),ratings[i]);
  assert(std::abs(cm-cmExpected[i])<1e-8);
  const double fencer=fencer::chance(ratings[i],1,true,true);
  assert(std::abs(fencer-fencerExpected[i])<1e-8);
  assert(cm>fencer && fencer>carbineer::chance(ratings[i],true,true));
  assert(cm>trapStatusChance(ratings[i],10) && cm>pikeman::chance(ratings[i],1));
  ++checks;
 }
 // Every realistic Doctor preparation strengthens resistance against the best
 // supplies and temporary specialist bonuses; neither side hits the chance cap.
 for(int baseline=65;baseline<=100;++baseline){
  const double prepared=preparedRating(baseline,25);
  assert(combatmedic::chance(125,prepared)<combatmedic::chance(125,baseline));
  assert(fencer::chance(prepared,1,true,true)<fencer::chance(baseline,1,true,true));
  assert(carbineer::chance(prepared,true,true)<carbineer::chance(baseline,true,true));
  assert(trapStatusChance(prepared,10)<trapStatusChance(baseline,10));
  ++checks;
 }
 // Training and active effects remain useful, but resistance also attenuates
 // their increment. Flawless replaces Precision, and never stacks with it.
 for(int rating=0;rating<=150;++rating){
  double previous=0;
  for(int step=0;step<=20;++step){
   const double progress=step/20.;
   const double chance=fencer::chance(rating,progress,false,false);
   assert(chance>=previous && chance<=95);previous=chance;
   assert(fencer::chance(rating,progress,true,true)==fencer::chance(rating,progress,false,true));
   assert(fencer::chance(rating,progress,true,false)>=chance);
   assert(fencer::chance(rating,progress,false,true)>=fencer::chance(rating,progress,true,false));
   ++checks;
  }
  assert(carbineer::chance(rating,true)-carbineer::chance(rating,false)<=10*(1-statusReduction(rating))+1e-8);
  assert(trapStatusChance(rating,10)-statusChance(95,rating)<=10*(1-statusReduction(rating))+1e-8);
  assert(learnedStatusChance(95,10000,rating)==combatmedic::chance(125,rating));
  assert(learnedStatusChance(95,-1,rating)==statusChance(95,rating));
  ++checks;
 }
 assert(std::isfinite(learnedStatusChance(95,std::numeric_limits<double>::quiet_NaN(),100)));
 // Hard-control duration, target caps and recovery remain authored separately.
 assert(carbineer::ability("charge_shot").duration==2);
 assert(carbineer::ability("charge_blast").duration==3 && carbineer::ability("charge_blast").targets==6);
 assert(pikeman::ability("polearm_stun").duration==4 && pikeman::ability("whirlwind").duration==3);
 assert(fencer::softDuration(8,1)==10 && fencer::BleedDuration==12);
 assert(statusDuration(10,100)==6 && statusDuration(10,125)==6);
 std::cout<<checks<<" cross-profession potency, preparation, progression and bounded-bonus checks passed\n";
}
