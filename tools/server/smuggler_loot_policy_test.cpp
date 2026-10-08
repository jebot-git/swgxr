#include "../../server/smuggler/SwgxrSmugglerLootPolicy.h"
#include <cassert>
int main() {
 using P=SwgxrSmugglerLootPolicy;
 assert(P::chance(-1)==0 && P::chance(101)==100);
 for(int chance: {0,20,100}) {
  int wins=0;
  for(int roll=0;roll<100;++roll) {
   wins+=P::wins(true,true,true,false,false,chance,roll);
   assert(!P::wins(false,true,true,false,false,chance,roll));
   assert(!P::wins(true,false,true,false,false,chance,roll));
   assert(!P::wins(true,true,false,false,false,chance,roll));
   assert(!P::wins(true,true,true,true,false,chance,roll));
   assert(!P::wins(true,true,true,false,true,chance,roll));
  }
  assert(wins==chance);
 }
 assert(P::wins(true,true,true,false,false,20,19));
 assert(!P::wins(true,true,true,false,false,20,20));
 assert(!P::wins(true,true,true,false,false,100,-1));
 assert(!P::wins(true,true,true,false,false,100,100));
}
