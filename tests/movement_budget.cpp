#include "../server/movement/MovementBudget.h"
#include <cassert>
#include <cmath>
#include <iostream>
using swgxr::movement::Budget;
int main(){
 Budget b;b.rebase(100,0,0,0,5);auto original=b;
 b.accrue(100.5,5);assert(!b.accept(500,0,0));assert(b.x==0 && b.revision==original.revision);
 const double rejectedCredit=b.credit;b.accrue(100.5,5);assert(b.credit==rejectedCredit);assert(!b.accept(500,0,0));
 b.accrue(100.7,5);assert(!b.accept(500,0,0));assert(b.accept(3,0,0));
 // Rapid individually-small steps spend a cumulative allowance, including reversals.
 Budget rapid;rapid.rebase(0,0,0,0,5);rapid.accrue(1,5);int accepted=0;
 for(int i=0;i<100;++i){if(!rapid.accept(i+1,0,0))break;++accepted;}assert(accepted==5);
 const auto rev=rapid.revision;assert(rapid.accept(rapid.x,rapid.y,rapid.parent));assert(rapid.revision==rev);
 assert(!rapid.accept(rapid.x-1,rapid.y,0));
 // Long idle is bounded; repeated rejected or duplicate calls cannot bank distance.
 Budget idle;idle.rebase(0,0,0,0,5);idle.accrue(86400,5);assert(idle.credit<=11.25);assert(!idle.accept(500,0,0));
 for(int i=0;i<100;++i){idle.accrue(86400,5);assert(!idle.accept(500,0,0));}assert(idle.x==0);
 // Real-time 1Hz walking and jittered updates at run speed remain accepted.
 Budget walk;walk.rebase(0,0,0,0,5);for(int i=1;i<=60;++i){walk.accrue(i,5);assert(walk.accept(i*5,0,0));}
 Budget jitter;jitter.rebase(0,0,0,0,5);double t=0,x=0;
 for(int i=0;i<120;++i){double dt=i%3==0?1.2:i%3==1?.1:.7;t+=dt;x+=dt*5;jitter.accrue(t,5);assert(jitter.accept(x,0,0));}
 // Faster pose/guard updates do not receive a repeated packet-size tolerance.
 Budget fast;fast.rebase(0,0,0,0,5);for(int i=1;i<=1000;++i){fast.accrue(i*.01,5);assert(fast.accept(i*.05,0,0));}
 // Parent identifiers change, but distances stay in one world frame.
 Budget cell;cell.rebase(0,1000,2000,1,5);cell.accrue(.5,5);assert(cell.accept(1001,2000,2));assert(!cell.accept(1,2,2));
 // Burst change bounded to one observed interval; expiry cannot retain high credit forever.
 Budget burst;burst.rebase(0,0,0,0,5);burst.accrue(1,10);assert(burst.accept(10,0,0));
 burst.accrue(2,5);assert(burst.accept(15,0,0));burst.accrue(3,5);assert(burst.credit<=11.25);assert(!burst.accept(40,0,0));
 // Backwards clock input never refills or subtracts allowance.
 const auto credit=burst.credit;burst.accrue(2,500);assert(burst.credit==credit && burst.rate==5.5);
 Budget reset;reset.rebase(0,0,0,0,5);reset.accrue(1,5);assert(!reset.accept(500,0,0));
 reset.rebase(1,500,0,7,5);assert(reset.credit==Budget::INITIAL_METRES && reset.parent==7);reset.accrue(2,5);assert(reset.accept(505,0,7));
 assert(!reset.accept(NAN,0,7));assert(!reset.accept(INFINITY,0,7));
 std::cout<<"PASS cumulative movement budget: rejection, replay, idle cap, cadence, jitter, burst, parent frame and native rebase\n";
}
