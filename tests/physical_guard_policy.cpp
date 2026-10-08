#include "server/combat/PhysicalGuardPolicy.h"
#include <cassert>
#include <iostream>
#include <limits>
int main(){
 using namespace corecu::guard;
 Vec left{{-.2,-.15,-.3}},right{{.2,-.15,-.3}},up{{0,1,0}},forward{{0,0,-1}};
 assert(boxing(left,right));assert(!boxing(right,left));assert(!boxing(left,left));
 assert(parry(right,up));assert(parry(left,Vec{{1,0,0}}));assert(!parry(right,forward));
 assert(!parry(Vec{{0,-1,-.3}},up));assert(!boxing(left,Vec{{.2,-.7,-.3}}));
 assert(!boxing(left,Vec{{.2,-.1,.3}}));assert(!parry(right,Vec{{0,0,0}}));
 assert(!parry(right,Vec{{0,std::numeric_limits<double>::quiet_NaN(),0}}));
 assert(front(0,1,0,2));assert(!front(0,1,0,-2));assert(!front(0,1,2,0));assert(!front(0,1,0,0));
 assert(!front(0,1,std::numeric_limits<double>::infinity(),0));
 assert(multiplier(false)==.35);assert(multiplier(true)==.55);assert(cost(0)==5);assert(cost(1000)==100);
 State state;state.refresh(10,0,123,false);
 assert(!state.active(10.1,123));assert(state.active(10.2,123));
 auto previous=state.release();assert(!state.active(10.2,123));
 state.refresh(10.35,previous,123,false);assert(state.active(10.35,123));
 assert(!state.active(11.3,123));assert(!state.active(10.5,456));
 assert(state.block(10.5,100,100)==10&&state.blocks==1);
 assert(state.block(10.6,1000,100)==0);assert(state.broken>11.7);
 previous=state.release();state.refresh(10.9,previous,123,false);
 assert(!state.active(11.1,123)); // Lowering/re-raising cannot reset guard break.
 previous=state.release();state.refresh(11.8,previous,123,false);
 assert(state.active(12,123));
 previous=state.release();state.refresh(12.1,previous,456,true);
 assert(!state.active(12.11,456));assert(state.active(12.3,456));
 int cases=0;
 for(int damage=1;damage<=10000;++damage){
  assert(cost(damage)>=5);assert(cost(damage)<=std::max(5,damage));
  for(bool unarmed:{false,true})for(double armour:{0.,.25,.5}){
   double after=damage*multiplier(unarmed)*(1-armour);
   assert(after>0&&after<damage);++cases;
  }
 }
 std::cout<<"Physical guard: "<<cases<<" damage/armour cases and pose boundaries passed\n";
}
