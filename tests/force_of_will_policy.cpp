#include "server/combat/ForceOfWillPolicy.h"
#include <cassert>
#include <iostream>
int main(){
 using namespace corecu::forceofwill;
 int cases=0;
 for(int max:{1,100,1000,3000,999999})for(int wounds:{0,1,99,500,3000})for(int current:{-100,0,1,200,9000}){
  int effective=std::max(1,max-wounds),next=recoveredHealth(current,max,wounds);
  assert(next>=1 && next<=effective);
  assert(next>=int((int64_t(effective)*15+99)/100));
  if(current>=1 && current<=effective)assert(next>=current);
  ++cases;
 }
 for(int bits=0;bits<256;++bits){
  bool fields[8];for(int i=0;i<8;++i)fields[i]=(bits>>i)&1;
  assert(eligible(fields[0],fields[1],fields[2],fields[3],fields[4],fields[5],fields[6],fields[7])==(bits==135));++cases;
 }
 assert(recoveredHealth(0,3000,1000)==300);
 assert(recoveredHealth(500,3000,1000)==500);
 assert(remaining(1000000,400000)==600);
 assert(remaining(1000000,999500)==.5);
 assert(remaining(1000000,1000000)==0 && remaining(1000000,1000001)==0);
 assert(CooldownSeconds==600);
 std::cout<<cases<<" Force of Will health and eligibility cases passed\n";
}
