#include "../server/combat/GroundActionPolicy.h"
#include <cassert>
#include <iostream>
using namespace corecu;
int main(){
 assert(ground::trackingScale(1)==.5 && ground::trackingScale(31)==1 && ground::trackingScale(91)==2 && ground::trackingScale(151)==3 && ground::trackingScale(999)==3);
 action::Attack low,high;low.trackingScale=ground::trackingScale(1);high.trackingScale=ground::trackingScale(151);
 low.prepare(.1,{{10,0,0}});high.prepare(.1,{{10,0,0}});
 assert(high.aim[0]>low.aim[0]*5.9);assert(low.lockAt()==high.lockAt());
 high.prepare(high.lockAt(),{{10,0,0}});auto locked=high.aim;high.prepare(high.deliveryAt(),{{-10,0,0}});assert(high.aim==locked);
 assert(ground::inRegion({{3528,0,-4804}}));assert(ground::inRegion({{5028,0,-4804}}));assert(!ground::inRegion({{5028.01,0,-4804}}));
 ground::Victim v;v.attack.start=10;v.attack.id=10;v.attack.aimLocked=true;
 assert(!v.acknowledge(10.96,1));assert(!v.receipt(11.3,true,10.2,11.3,1));assert(!v.resolve()&&v.waived);
 v={};v.attack.start=10;v.attack.aimLocked=true;assert(!v.acknowledge(10.5,1));assert(v.warning(10.5));assert(v.acknowledge(10.8,1));assert(!v.acknowledge(10.8,2));
 assert(v.receipt(11.3,true,10.2,11.3,1));assert(v.receipt(11.4,true,10.2,11.3,1));assert(!v.receipt(11.4,false,10.2,11.3,1));assert(v.ready(11.3));assert(v.resolve());assert(!v.resolve());
 ground::Victim missing;missing.attack.start=10;missing.attack.aimLocked=true;missing.warning(10.5);missing.acknowledge(10.8,1);missing.attack.sample(11.1,{{0,0,1}});assert(missing.ready(12));assert(!missing.resolve()&&missing.waived);
 action::Attack custom;custom.customized=true;custom.profile={1.4,.15,1.4,20,.45,.5,0};custom.clipDuration=1;custom.contactDelay=1./3;custom.lockLead=.5;custom.start=10;
 assert(std::abs(custom.deliveryAt()-11.4)<1e-9);assert(std::abs(custom.lockAt()-10.9)<1e-9);assert(std::abs(custom.recoveredAt()-13.8)<1e-9);
 assert(!ground::resolving(5));{ground::ResolveScope first(5);assert(ground::resolving(5));assert(!ground::resolving(6));{ground::ResolveScope second(6);assert(ground::resolving(6));}assert(ground::resolving(5));}assert(!ground::resolving(5));
 std::cout<<"Ground region, profile timing, warning acknowledgement, idempotent receipts, missing-coverage waiver and nested settlement scopes passed\n";
}
