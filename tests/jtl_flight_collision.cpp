#include "server/jtl/FlightCollisionPolicy.h"
#include <cassert>
#include <iostream>
using namespace swgxr::jtl;
int main(){
 assert(std::abs(sphereSweep({{0,0,0}},{{100,0,0}},{{50,0,0}},5)-.45)<1e-9);
 assert(sphereSweep({{0,6,0}},{{100,6,0}},{{50,0,0}},5)==1);
 assert(sphereSweep({{48,0,0}},{{40,0,0}},{{50,0,0}},5)==1);
 assert(sphereSweep({{48,0,0}},{{49,0,0}},{{50,0,0}},5)==0);
 assert(sphereSweep({{0,0,0}},{{0,0,0}},{{0,0,0}},5)==1);
 // Exact triangle plane overlap models a surface thinner than one flight tick.
 auto wall=[](const Vec&p,double r){return std::abs(p[0]-50)<=r;};
 for(double distance:{60.,100.,1000.}){
  double t=volumeSweep(Vec{{0,0,0}},Vec{{distance,0,0}},2.,wall);
  assert(t*distance<=48. && t*distance>=47.5);
 }
 assert(volumeSweep(Vec{{0,0,0}},Vec{{0,500,0}},2.,wall)==1);
 assert(volumeSweep(Vec{{49,0,0}},Vec{{45,0,0}},2.,wall)==1);
 assert(volumeSweep(Vec{{49,0,0}},Vec{{50,0,0}},2.,wall)==0);
 std::cout<<"11 continuous/conservative flight collision checks passed\n";
}
