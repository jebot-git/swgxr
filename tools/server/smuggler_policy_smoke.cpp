#include "../../server/smuggler/SwgxrSmugglerPolicy.h"
#include <cassert>
#include <cmath>
#include <iostream>
int main(){
 using P=SwgxrSmugglerPolicy;
 assert(std::abs(P::lastDitch(100,100,100,100,100,100)-2.0)<1e-9);
 assert(std::abs(P::lastDitch(30,100,10,100,3,100)-4.335)<1e-9);
 assert(std::abs(P::lastDitch(100,100,10,100,3,100)-2.935)<1e-9);
 assert(P::lastDitch(0,100,0,100,0,100)==5.0);
 assert(P::lastDitch(200,100,200,100,200,100)==2.0);
 assert(std::isfinite(P::lastDitch(0,0,0,0,0,0)));
 // Monotonic missing-Health scaling and weighted deficit formula.
 for(int remaining=1;remaining<100;++remaining){
  assert(P::lastDitch(remaining,100,50,100,50,100)>P::lastDitch(remaining+1,100,50,100,50,100));
  assert(std::abs(P::lastDitch(remaining,100,50,100,50,100)-(2.0+2.0*P::deficit(remaining,100)+.5))<1e-9);
 }
 assert(P::snarePercent==25 && P::snareSeconds==20 && P::concussionSeconds==40);
 std::cout<<"Smuggler policy: CU 293.5%/433.5% examples, bounds and 198 monotonic/formula cases passed\n";
}
