#include "server/jtl/JtlPolicy.h"
#include <iostream>
#include <limits>
using namespace swgxr::jtl;
int checks=0;
void check(bool ok){++checks;if(!ok)throw std::runtime_error("JtL policy check "+std::to_string(checks));}
template<class F> void rejects(F f){bool denied=false;try{f();}catch(const std::runtime_error&){denied=true;}check(denied);}
int main(){
 State s;Input in;in.throttle=1;in.sequence=1;s=step(s,in,.2,50,10,40,20,40);check(std::abs(s.speed-2)<1e-9);check(std::abs(s.position[2]-.25)<1e-9);check(s.position[0]==0 && s.position[1]==0);
 rejects([&]{step(s,in,.4,50,10,40,20,40);});in.sequence++;s=step(s,in,100,50,10,40,20,40);check(s.speed==0);check(s.position[2]>10 && s.position[2]<20);
 for(int n=0;n<100;++n){in.sequence++;s=step(s,in,100+(n+1)*.2,50,10,40,20,40);}check(std::abs(s.speed-50)<1e-8);
 in.throttle=0;in.sequence++;s=step(s,in,121,50,10,40,20,40);check(s.speed<50);
 in.throttle=std::numeric_limits<double>::quiet_NaN();rejects([&]{validate(in);});in.throttle=1;in.yaw=2;rejects([&]{validate(in);});in.yaw=1;
 State turn;for(int n=0;n<100;++n){in.sequence++;turn=step(turn,in,(n+1)*.2,50,10,40,20,40);}double norm=0;for(auto v:turn.orientation)norm+=v*v;check(std::abs(norm-1)<1e-10);check(std::abs(turn.position[0])>10);
 State edge;edge.position={{0,0,6999}};edge.speed=50;in.sequence++;edge=step(edge,in,.2,50,10,40,20,40);check(edge.position[2]<=7000);check(edge.speed==0);
 auto banks=shields(50,50,100,100,1);check(banks[0]==100 && banks[1]==0);banks=shields(100,50,100,100,1);check(banks[0]==100 && banks[1]==50);banks=shields(100,50,100,100,.5);check(banks[0]==75 && banks[1]==75);
 double credit=0;check(walkBudget({{0,0,0}},{{.75,0,0}},.25,credit));check(!walkBudget({{0,0,0}},{{1,0,0}},0,credit));credit=0;check(!walkBudget({{0,0,0}},{{10,0,0}},100,credit));check(std::abs(credit-6.6)<1e-8);check(!walkBudget({{0,0,0}},{{65,0,0}},.25,credit));check(!walkBudget({{0,0,0}},{{0,0,0}},-1,credit));
 // Same elapsed native flight at different packet cadences; requests merely
 // renew a held-input lease and cannot dilate time.
 auto fly=[](int packetTicks){State x;Input controls;controls.sequence=1;controls.throttle=1;double received=0;for(int n=1;n<=200;++n){double t=n*.05;x=advance(x,controls,received,t,50,10,40,20,40);if(n%packetTicks==0)received=t;}return x;};
 auto fast=fly(2),slow=fly(9),jitter=fly(20);check(std::abs(fast.position[2]-slow.position[2])<1e-6);check(std::abs(fast.position[2]-jitter.position[2])<1e-6);check(fast.position[2]>370);
 Input held;held.sequence=1;held.throttle=1;State lost;lost.speed=50;lost=advance(lost,held,0,100,50,10,40,20,40);check(lost.speed==0);check(std::abs(lost.position[2]-75)<1e-6);auto parked=advance(lost,held,0,101,50,10,40,20,40);check(parked.position==lost.position);
 credit=0;check(walkBudget({{0,0,0}},{{3.5,0,0}},.5,credit,7));check(!walkBudget({{0,0,0}},{{1,0,0}},0,credit,7));
 std::cout<<checks<<" native JtL navigation/conservation/anti-replay checks passed\n";
}
