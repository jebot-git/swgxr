#include "server/combat/ProjectileContactPolicy.h"
#include <cassert>
#include <cmath>
#include <iostream>
int main(){using namespace corecu::projectile;int checks=0;
 for(bool pistol:{false,true})for(bool twoHands:{false,true}){
  double scale=rangeScale(pistol,twoHands);assert(scale==(pistol?(twoHands?1.1:1.):(twoHands?1.:.3)));++checks;
  for(int pose=0;pose<3;++pose){
   assert(std::abs(damageScale(100*scale,0,50*scale,100*scale,-20,25,-60,pose)-(pose==0?.4:pose==1?.7:1.))<1e-8);
   assert(damageScale(50*scale,0,50*scale,100*scale,-20,25,-60,pose)==1.25);
   assert(damageScale(100*scale+.01,0,50*scale,100*scale,-20,25,-60,pose)==0);
   assert(damageScale(-1,0,50*scale,100*scale,-20,25,-60,pose)==0);checks+=4;
  }
 }
 std::cout<<checks<<" server projectile range/pose damage cases passed\n";
}
