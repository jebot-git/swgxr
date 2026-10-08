#include "server/combat/MeleePolicy.h"
#include "server/combat/CoreCuPolicy.h"
#include <cassert>
#include <limits>
#include <iostream>
int main(){
 using namespace corecu::melee;
 Vec eye{{0,1.7,0}},direction{{0,0,1}};
 assert(score(eye,direction,{{0,0,1}},.4,1.8,2)>=0);
 assert(score(eye,direction,{{.6,0,2}},.4,1.8,2)>=0);
 assert(score(eye,direction,{{2,0,1}},.4,1.8,2)<0);
 assert(score(eye,direction,{{0,0,-1}},.4,1.8,2)<0);
 assert(score(eye,direction,{{0,0,3}},.4,1.8,2)<0);
 assert(score(eye,direction,{{0,4,1}},.4,1.8,2)<0);
 assert(score(eye,{{0,0,0}},{{0,0,1}},.4,1.8,2)<0);
 assert(score(eye,{{0,0,std::numeric_limits<double>::quiet_NaN()}},{{0,0,1}},.4,1.8,2)<0);
 assert(reach(5,true)==2 && reach(5,false)==4 && reach(1,false)==1);
 assert(corecu::trapSuccessBonus(true,4,0,false)==5);
 assert(corecu::trapSuccessBonus(true,4,4,true)==10);
 for(int level=1;level<=350;++level){
  double rating=std::min(100.,level*.5),base=corecu::statusChance(95,rating);
  double scout=corecu::trapStatusChance(rating,5),ranger=corecu::trapStatusChance(rating,10);
  assert(scout>=base && ranger>=scout && ranger<=95);
  assert(ranger-base<=10.000001);
 }
 assert(corecu::weakenedRating(0,40,-40)==0);
 assert(corecu::weakenedRating(60,40,-40)==60); // Existing defence is already modified.
 assert(corecu::weakenedRating(0,100,-40)==60);
 std::cout<<"Melee cone boundaries, reach, and 350 trap progression cases passed\n";
}
