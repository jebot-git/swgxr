#include "vendor/Core3/MMOCoreORB/src/client/zone/NativeMotionStream.h"
#include <cassert>
#include <iostream>
int main(){
 auto& stream=swgxr::NativeMotionStream::instance();
 stream.scene("terrain/tatooine.trn");
 stream.push(7,0,-2,3,4,0xfffffffe,5,25);
 stream.push(7,0,-1,3,4,1,5,25);
 stream.push(7,0,99,3,4,0xffffffff,5,25);
 auto first=stream.snapshot(1);auto row=first["actors"][0];
 assert(first["zone"]=="tatooine" && row["movement_counter"]==1 && row["position"][0]==-1);
 assert(std::abs(row["heading_radians"].get<double>()-1.57075)<.00001);
 stream.push(7,9,2,3,4,0,0,0); // Cell change resets the counter fence.
 assert(stream.snapshot(1)["actors"][0]["cell_id"]=="9");
 stream.attack(7,80,123);assert(stream.snapshot(1)["events"].size()==1);
 stream.remove(7);assert(stream.snapshot(1)["events"].empty());assert(stream.snapshot(1)["actors"].empty());
 std::thread receive([&]{for(int i=0;i<10000;++i)stream.push(i%700,0,i,0,0,i,3,0);});
 for(int i=0;i<100;++i){auto rows=stream.snapshot(1)["actors"];assert(rows.size()<=512);for(auto& row:rows)assert(row["age_ms"].get<double>()>=0);}
 receive.join();assert(stream.snapshot(1)["actors"].size()==512);
 for(int i=0;i<300;++i)stream.attack(7,80,123);assert(stream.snapshot(1)["events"].size()==128);
 for(int i=1;i<=100;++i)stream.action({{"id","7"},{"encounter_id","10"},{"attack_id",std::to_string(i)},{"phase","windup"}});
 assert(stream.snapshot(1)["action_events"].size()==64);
 stream.action({{"id","7"},{"encounter_id","10"},{"attack_id","100"},{"phase","cancelled"}});
 auto actionSnapshot=stream.snapshot(1);
 int cancelled=0;for(auto& row:actionSnapshot["action_events"])if(row["attack_id"]=="100"){assert(row["phase"]=="cancelled");++cancelled;}
 assert(cancelled==1);
 stream.scene("terrain/naboo.trn");auto scene=stream.snapshot(1);
 assert(scene["zone"]=="naboo" && scene["epoch"]==2 && scene["actors"].empty() && scene["events"].empty() && scene["action_events"].empty());
 std::cout<<"Native counter wrap, reordering, cell transition, destruction, scene epoch and concurrent bounded cache passed\n";
}
