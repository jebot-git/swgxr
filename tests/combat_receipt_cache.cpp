#include "../server/combat/CombatReceiptCache.h"
#include <cassert>
int main(){
 corecu::receipts::Cache<int> a,b;
 assert(!a.find("melee:1","intent",1));a.put("melee:1","intent",83,1);
 assert(*a.find("melee:1","intent",2)==83);assert(!b.find("melee:1","intent",2));
 bool conflict=false;try{a.find("melee:1","changed",2);}catch(const std::runtime_error&){conflict=true;}assert(conflict);
 assert(!a.find("impact:1","intent",2));assert(!a.find("melee:1","intent",32));
 for(int i=0;i<600;++i)a.put(std::to_string(i),"intent",i,40+i*.001);
 assert(a.rows.size()==512);assert(!a.find("0","intent",41));assert(*a.find("599","intent",41)==599);
}
