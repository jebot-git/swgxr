#include "../../server/smuggler/SwgxrSmugglerPolicy.h"
#include <cassert>
#include <cmath>
#include <iostream>
int main(){
 using P=SwgxrSmugglerPolicy;
 assert(std::abs(P::lastDitch(100,100,100,100,100,100)-2.0)<1e-9);
 assert(std::abs(P::lastDitch(30,100,10,100,3,100)-4.57)<1e-9);
 assert(std::abs(P::lastDitch(100,100,10,100,3,100)-3.87)<1e-9);
 assert(P::lastDitch(0,100,0,100,0,100)==5.0);
 assert(P::lastDitch(200,100,200,100,200,100)==2.0);
 assert(std::isfinite(P::lastDitch(0,0,0,0,0,0)));
 // Monotonic inverse resource scaling and cross-pool equivalence.
 for(int remaining=1;remaining<100;++remaining){
  assert(P::lastDitch(remaining,100,50,100,50,100)>P::lastDitch(remaining+1,100,50,100,50,100));
  assert(std::abs(P::lastDitch(remaining,100,50,100,50,100)-P::lastDitch(50,100,remaining,100,50,100))<1e-9);
 }
 assert(P::snarePercent==25 && P::snareSeconds==20 && P::concussionSeconds==40);
 std::cout<<"Smuggler policy: user 387%/457% examples, bounds and 198 monotonic/symmetry cases passed\n";
}
