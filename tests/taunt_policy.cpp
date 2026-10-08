#include "server/combat/TauntPolicy.h"
#include <cassert>
#include <iostream>
#include <limits>
int main(){
 using namespace corecu::taunt;
 Vec eye{{0,1.7,0}},forward{{0,0,1}};
 double near=reticleEntry(eye,forward,{{.2,0,10}},.4,1.8,64);
 double far=reticleEntry(eye,forward,{{0,0,20}},.4,1.8,64);
 assert(near>=0 && near<far); // First intersected eligible target, not most centered.
 assert(reticleEntry(eye,forward,{{2,0,10}},.4,1.8,64)<0);
 assert(reticleEntry(eye,forward,{{0,0,-5}},.4,1.8,64)<0);
 assert(reticleEntry(eye,forward,{{0,0,66}},.4,1.8,64)<0);
 assert(reticleEntry(eye,forward,{{0,5,10}},.4,1.8,64)<0);
 assert(reticleEntry(eye,{{0,0,0}},{{0,0,10}},.4,1.8,64)<0);
 assert(reticleEntry(eye,forward,{{0,0,10}},std::numeric_limits<double>::quiet_NaN(),1.8,64)<0);
 int cases=0;
 for(int distance=1;distance<=64;++distance){
  assert(reticleEntry(eye,forward,{{0,0,double(distance)}},.4,1.8,64)>=0);
  assert(reticleEntry(eye,forward,{{.4+distance*.03+.01,0,double(distance)}},.4,1.8,64)<0);cases+=2;
 }
 std::cout<<"Taunt reticle: "<<cases<<" range/edge cases plus priority, invalid pose and bounds passed\n";
}
