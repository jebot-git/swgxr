#include "server/jtl/JtlPolicy.h"
#include <iostream>
#include <limits>
using namespace swgxr::jtl;
int checks=0;
void check(bool ok){++checks;if(!ok)throw std::runtime_error("JtL policy check "+std::to_string(checks));}
template<class F> void rejects(F f){bool denied=false;try{f();}catch(const std::runtime_error&){denied=true;}check(denied);}
int main(){
 Dynamics d;d.maxSpeed=50;d.acceleration=10;d.deceleration=10;d.rates={{.7,.35,.7}};d.angularAcceleration={{1,1,1}};
 State s;Input in;in.throttle=1;in.sequence=1;s=step(s,in,.2,d);check(std::abs(s.speed-2)<1e-9);check(std::abs(s.position[2]-.25)<1e-9);check(s.position[0]==0 && s.position[1]==0);
 rejects([&]{step(s,in,.4,d);});in.sequence++;s=step(s,in,100,d);check(s.speed==0);check(s.position[2]>10 && s.position[2]<20);
 for(int n=0;n<100;++n){in.sequence++;s=step(s,in,100+(n+1)*.2,d);}check(std::abs(s.speed-50)<1e-8);
 in.throttle=0;in.sequence++;s=step(s,in,121,d);check(s.speed<50);
 in.throttle=std::numeric_limits<double>::quiet_NaN();rejects([&]{validate(in);});in.throttle=1;in.yaw=2;rejects([&]{validate(in);});in.yaw=1;
 State turn;for(int n=0;n<100;++n){in.sequence++;turn=step(turn,in,(n+1)*.2,d);}double norm=0;for(auto v:turn.orientation)norm+=v*v;check(std::abs(norm-1)<1e-10);check(std::abs(turn.position[0])>10);
 State edge;edge.position={{0,0,8159}};edge.speed=50;in.sequence++;edge=step(edge,in,.2,d);check(edge.position[2]<=8160);check(edge.speed>0);
 // Reference behavior: radians, rotational slew, separate braking, native speeds.
 Dynamics original;original.maxSpeed=250;original.acceleration=80;original.deceleration=20;original.rates={{1,1,1}};original.angularAcceleration={{2,2,2}};
 Input steer;steer.sequence=1;steer.yaw=1;State yawed;
 yawed=integrate(yawed,steer,.05,original);check(std::abs(yawed.angular[1]-.1)<1e-9);check(std::abs(yawed.orientation[1]-std::sin(.005/2))<1e-9);
 steer.yaw=0;yawed=integrate(yawed,steer,.10,original);check(std::abs(yawed.angular[1])<1e-9);
 State fastShip;fastShip.speed=200;steer.throttle=1;fastShip=integrate(fastShip,steer,.05,original);check(std::abs(fastShip.speed-204)<1e-9);
 steer.throttle=0;fastShip=integrate(fastShip,steer,.10,original);check(std::abs(fastShip.speed-203)<1e-9);
 // Zero engine acceleration cannot propel a disabled ship.
 original.acceleration=0;State disabled;steer.throttle=1;disabled=integrate(disabled,steer,.05,original);check(disabled.speed==0 && length(disabled.velocity)==0);
 // Slip preserves the prior direction during a turn, capped to current speed.
 original.slideDampener=1;State sliding;sliding.speed=100;sliding.velocity={{100,0,0}};steer.throttle=.4;sliding=integrate(sliding,steer,.05,original);check(sliding.velocity[0]>99 && sliding.velocity[2]>4.9 && sliding.velocity[2]<5.1);check(std::abs(length(sliding.velocity)-100)<1e-9);
 original.slideDampener=0;State noSlide;noSlide.speed=100;noSlide.velocity={{100,0,0}};noSlide=integrate(noSlide,steer,.05,original);check(noSlide.velocity[0]==0 && noSlide.velocity[2]==100);
 auto expired=advance(sliding,steer,0,2,original);check(length(expired.velocity)==0 && length(expired.angular)==0 && expired.speed==0);
 original.acceleration=std::numeric_limits<double>::quiet_NaN();rejects([&]{integrate(disabled,steer,.1,original);});
 auto banks=shields(50,50,100,100,1);check(banks[0]==100 && banks[1]==0);banks=shields(100,50,100,100,1);check(banks[0]==100 && banks[1]==50);banks=shields(100,50,100,100,.5);check(banks[0]==75 && banks[1]==75);
 double credit=0;check(walkBudget({{0,0,0}},{{.75,0,0}},.25,credit));check(!walkBudget({{0,0,0}},{{1,0,0}},0,credit));credit=0;check(!walkBudget({{0,0,0}},{{10,0,0}},100,credit));check(std::abs(credit-6.6)<1e-8);check(!walkBudget({{0,0,0}},{{65,0,0}},.25,credit));check(!walkBudget({{0,0,0}},{{0,0,0}},-1,credit));
 // Same elapsed native flight at different packet cadences; requests merely
 // renew a held-input lease and cannot dilate time.
 auto fly=[&](int packetTicks){State x;Input controls;controls.sequence=1;controls.throttle=1;double received=0;for(int n=1;n<=200;++n){double t=n*.05;x=advance(x,controls,received,t,d);if(n%packetTicks==0)received=t;}return x;};
 auto fast=fly(2),slow=fly(9),jitter=fly(20);check(std::abs(fast.position[2]-slow.position[2])<1e-6);check(std::abs(fast.position[2]-jitter.position[2])<1e-6);check(fast.position[2]>370);
 Input held;held.sequence=1;held.throttle=1;State lost;lost.speed=50;lost=advance(lost,held,0,100,d);check(lost.speed==0);check(std::abs(lost.position[2]-75)<1e-6);auto parked=advance(lost,held,0,101,d);check(parked.position==lost.position);
 credit=0;check(walkBudget({{0,0,0}},{{3.5,0,0}},.5,credit,7));check(!walkBudget({{0,0,0}},{{1,0,0}},0,credit,7));
 std::cout<<checks<<" native JtL navigation/conservation/anti-replay checks passed\n";
}
