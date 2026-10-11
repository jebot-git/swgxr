#include "../server/combat/CombatMovementHistory.h"
#include <cassert>
int main(){
 corecu::history::History h;
 h.observe(10,{{0,0,0}},1,0);h.observe(10.5,{{6,0,0}},1,0);
 assert(h.matches({{0,0,0}},10,10.6,1,0));
 assert(!h.matches({{20,0,0}},10,10.6,1,0));
 assert(!h.matches({{0,0,0}},10,12.1,1,0));assert(!h.nearest(11,10.5,1,0));
 assert(!h.nearest(10,10.5,2,0));assert(!h.nearest(10,10.5,1,1));
 h.observe(10.6,{{6,0,0}},1,1);assert(!h.nearest(10,10.6,1,0));
 h.observe(10.7,{{60,0,0}},1,1);assert(h.samples.size()==1);
 for(int i=0;i<200;++i)h.observe(11+i*.01,{{60,0,0}},1,1);
 assert(h.samples.size()==64);
 corecu::history::History geometry;
 geometry.observe(20,{{0,5,0}},1,0,false);
 geometry.observe(20.2,{{0,5,0}},1,0,true);
 assert(!geometry.contact({{0,5,0}},20,20.4,1,0)); // Wall at the actual contact, clear later.
 assert(geometry.contact({{0,5,0}},20.2,20.4,1,0));
 assert(!geometry.contact({{0,8,0}},20.2,20.4,1,0)); // Different floor in same exterior cell.
 assert(!geometry.contact({{0,5,0}},20.2,20.4,1,4));
 assert(!geometry.contact({{0,5,0}},20.4,20.5,1,0)); // Missing contact-time geometry.

}
