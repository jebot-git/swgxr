#include "server/jtl/TargetingPolicy.h"
#include <cassert>
#include <iostream>
int main(){
 using namespace swgxr::jtl;
 MissileLock lock;
 for(int i=0;i<=20;++i)lock.update(10+i*.1,true,1.9);
 assert(lock.acquired);
 lock.update(12.1,false,1.9);assert(!lock.acquired && lock.elapsed==0);
 lock.update(12.2,true,1.9);lock.update(13,true,1.9);assert(!lock.acquired && lock.elapsed==0);
 assert(withinAcquisition(500,600,1,10));
 assert(!withinAcquisition(601,600,1,10));assert(!withinAcquisition(500,600,.8,10));
 assert(!withinAcquisition(0,600,1,10));assert(NO_SUBSYSTEM!=0);
 std::cout<<"Missile acquisition, loss, stale-tick gap, cone and range checks passed\n";
}
