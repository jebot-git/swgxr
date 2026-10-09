#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <limits>
#include <vector>
#include "server/combat/CoreCuRegenPolicy.h"
#include "server/combat/CoreCuMedicalPolicy.h"
#include "server/combat/DoctorPolicy.h"
#include "server/combat/SquadLeaderPolicy.h"
using uint32=uint32_t;
namespace Math {template<class T>T max(T a,T b){return std::max(a,b);}}
namespace CreatureAttribute {enum {HEALTH=0,CONSTITUTION=2,ACTION=3,STAMINA=5,MIND=6,WILLPOWER=8};}
struct BuffCRC {static unsigned getMedicalBuff(int attribute){return 1000+attribute;}};
struct BuffAttribute {static const char* getProtectionString(int){return "protection";}};
struct Buff {
 int metabolic=0;
 int getSkillModifierValue(const char*){return metabolic;}
 int getAttributeModifierValue(int){return 0;}
};
#include "regen_strength.inc"
#include "regen_resources.inc"
class CreatureObjectImplementation;
struct SwgxrSpice {
 static bool pinnedHam(CreatureObjectImplementation*);
 static void pinHam(CreatureObjectImplementation*);
 static double regenScale(CreatureObjectImplementation*,int);
};
class CreatureObjectImplementation {
public:
 bool squadMorale=false; double squadPassive=0;
 bool player=true,pet=false,combat=true,dead=false,incapacitated=false,pinned=false,kneeling=false,sitting=false,metabolicActive=true;
 Buff activePreparation;
 int metabolic=0,passiveCalls=0,pinCalls=0;
 std::array<int,9> base{3000,300,300,1000,300,300,1000,300,300};
 std::array<int,9> current{1,300,300,1,300,300,1,300,300};
 std::array<int,9> maximum{3000,300,300,1000,300,300,1000,300,300};
 std::array<int,9> wounds{};
 std::array<int,9> healed{};
 std::array<double,3> spice{1,1,1};
 double corecuHealthRegenCarry=0,corecuActionRegenCarry=0,corecuMindRegenCarry=0;
 CreatureObjectImplementation* asCreatureObject(){return this;}
 bool isPlayerCreature(){return player;} bool isPet(){return pet;} bool isInCombat(){return combat;}
 bool isDead(){return dead;} bool isIncapacitated(){return incapacitated;}
 bool isKneeling(){return kneeling;} bool isSitting(){return sitting;}
 int getHAM(int a){return current[a];} int getBaseHAM(int a){return base[a];}
 int getMaxHAM(int a){return maximum[a];} int getWounds(int a){return wounds[a];}
 int getSkillMod(const char*){return std::min(125,metabolic);}
 Buff* getBuff(unsigned crc){activePreparation.metabolic=metabolic;return metabolicActive && crc==BuffCRC::getMedicalBuff(2)?&activePreparation:nullptr;}
 int healDamage(CreatureObjectImplementation*,int a,int value,bool,bool){int applied=std::min(value,std::max(0,maximum[a]-wounds[a]-current[a]));current[a]+=applied;healed[a]+=applied;return applied;}
 void activatePassiveWoundRegeneration(){++passiveCalls;}
 void activateHAMRegeneration(int latency);
};
bool SwgxrSpice::pinnedHam(CreatureObjectImplementation* c){return c->pinned;}
void SwgxrSpice::pinHam(CreatureObjectImplementation* c){++c->pinCalls;for(int a:{0,3,6})c->current[a]=1;}
double SwgxrSpice::regenScale(CreatureObjectImplementation* c,int a){return c->spice[a/3];}
struct SwgxrSquadLeader {static double regenerationScale(CreatureObjectImplementation* c,int a){return corecu::squadleader::regeneration(c->squadPassive,c->squadMorale,a);}};
#include "regen_native.inc"
static int checks=0,failures=0;
void check(bool value,const char* label){++checks;if(!value){++failures;std::cerr<<label<<'\n';}}
void advance(CreatureObjectImplementation& c,const std::vector<int>& times){for(int t:times)c.activateHAMRegeneration(t);}
int main(){
 {CreatureObjectImplementation c;c.squadPassive=.1;c.squadMorale=true;c.metabolic=1500;advance(c,std::vector<int>(100,100));check(c.healed[3]==184 && c.healed[6]==147,"SL regenerates existing resources after bounded Doctor preparation without tick-rounding inflation");check(c.healed[0]==0,"SL never adds combat Health regeneration");}

 {
  CreatureObjectImplementation c;c.metabolic=1500;
  check(c.getSkillMod("private_swgxr_metabolic_regen")==125,"Fixture models the real aggregate BUFF cap at 125");
  check(SwgxrDoctorPreparation::strength(c.getBuff(BuffCRC::getMedicalBuff(2)),2)==1500,"Actual preparation helper reads complete normalized basis points from the active buff");
  advance(c,std::vector<int>(10,1000));
  check(c.healed[3]==115 && c.healed[6]==92,"Production regeneration bypasses aggregate BUFF clamp without losing Metabolic potency");
  CreatureObjectImplementation missing;missing.metabolic=1500;missing.metabolicActive=false;advance(missing,std::vector<int>(10,1000));
  check(missing.healed[3]==100 && missing.healed[6]==80,"Absent preparation cannot grant an unrelated or stale aggregate Metabolic modifier");
  CreatureObjectImplementation capped;capped.metabolic=100000;advance(capped,std::vector<int>(10,1000));
  check(capped.healed[3]==115 && capped.healed[6]==92,"Direct buff strength still respects the 15 percent policy cap");
 }
 for(bool pet:{false,true})for(int boost:{0,1500})for(int cadence:{1,10,100}){
  CreatureObjectImplementation c;c.player=!pet;c.pet=pet;c.metabolic=boost;
  advance(c,std::vector<int>(cadence,10000/cadence));
  check(c.healed[3]==(boost?115:100),"Ten seconds Action matches exact percentage at every cadence/player/pet");
  check(c.healed[6]==(boost?92:80),"Ten seconds Mind matches exact percentage at every cadence/player/pet");
  check(c.healed[0]==0 && c.corecuHealthRegenCarry==0,"Combat Health never accumulates or regenerates");
 }
 for(int boost:{0,590,800,990,1200,1500}){
  CreatureObjectImplementation c;c.metabolic=boost;
  for(int i=0;i<10;++i)advance(c,{17,83,100,125,675});
  check(c.healed[3]==int(std::floor(100*(1+boost/10000.)+1e-9)),"Variable integer-millisecond ticks preserve Action quality progression");
  check(c.healed[6]==int(std::floor(80*(1+boost/10000.)+1e-9)),"Variable integer-millisecond ticks preserve Mind quality progression");
  check(c.corecuActionRegenCarry>=0 && c.corecuActionRegenCarry<1 && c.corecuMindRegenCarry>=0 && c.corecuMindRegenCarry<1,"Only fractional carry is retained");
 }
 for(bool sitting:{false,true}){
  CreatureObjectImplementation c;c.combat=false;c.metabolic=1500;c.kneeling=!sitting;c.sitting=sitting;c.spice={1.1,1.2,.9};
  c.maximum[0]=c.maximum[3]=c.maximum[6]=100000;c.current[2]=360;c.current[5]=240;c.current[8]=450;
  advance(c,std::vector<int>(100,100));const double posture=sitting?1.75:1.25;
  check(c.healed[0]==int(std::floor(600*1.2*posture*1.1*1.15+1e-9)),"Health posture, secondary attribute and spice multipliers retained");
  check(c.healed[3]==int(std::floor(400*.8*posture*1.2*1.15+1e-9)),"Action posture, secondary attribute and spice multipliers retained");
  check(c.healed[6]==int(std::floor(400*1.25*posture*.9*1.15+1e-9)),"Mind secondary multiplier keeps existing cap");
 }
 for(const char* state:{"dead","incapacitated","pinned"}){
  CreatureObjectImplementation c;c.metabolic=1500;c.combat=false;
  c.corecuHealthRegenCarry=c.corecuActionRegenCarry=c.corecuMindRegenCarry=.95;
  c.dead=state[0]=='d';c.incapacitated=state[0]=='i';c.pinned=state[0]=='p';
  c.activateHAMRegeneration(100000);
  check(c.healed[0]+c.healed[3]+c.healed[6]==0,"Inactive life states cannot accrue healing during a long frame");
  check(c.corecuHealthRegenCarry==0 && c.corecuActionRegenCarry==0 && c.corecuMindRegenCarry==0,"Inactive life states clear all residual fractions");
  c.dead=c.incapacitated=c.pinned=false;c.combat=true;c.activateHAMRegeneration(10);
  check(c.healed[3]==0 && c.healed[6]==0,"Resuming after inactive state does not release stored healing");
 }
 {
  CreatureObjectImplementation c;c.combat=true;c.corecuHealthRegenCarry=.99;c.activateHAMRegeneration(1000);
  check(c.corecuHealthRegenCarry==0,"Combat resets pre-combat Health fraction");
  c.combat=false;c.activateHAMRegeneration(1);check(c.healed[0]==0,"Leaving combat does not regain discarded Health fraction");
 }
 for(int time:{0,-10}){
  CreatureObjectImplementation c;c.corecuActionRegenCarry=c.corecuMindRegenCarry=.9;c.activateHAMRegeneration(time);
  check(c.healed[3]==0 && c.healed[6]==0 && c.corecuActionRegenCarry==0 && c.corecuMindRegenCarry==0,"No elapsed time cannot gain minimum points or bank fractions");
 }
 {
  CreatureObjectImplementation c;c.base[3]=1;c.metabolic=0;advance(c,std::vector<int>(100,100));
  check(c.healed[3]==0,"Small valid ticks are not rounded up to a minimum point");
  advance(c,std::vector<int>(900,100));check(c.healed[3]==1,"Sub-point rates eventually produce the correct point");
 }
 {
  CreatureObjectImplementation c;c.metabolic=1500;c.current[3]=c.maximum[3];c.corecuActionRegenCarry=.9;c.activateHAMRegeneration(100000);
  check(c.healed[3]==0 && c.corecuActionRegenCarry==0,"A full pool clears the residual and cannot bank a long frame");
  c.current[3]-=10;c.activateHAMRegeneration(10);check(c.healed[3]==0,"Damage after full pool does not release saved regeneration");
 }
 {
  CreatureObjectImplementation c;c.metabolic=1500;c.wounds[3]=50;c.current[3]=949;c.corecuActionRegenCarry=.9;c.activateHAMRegeneration(100000);
  check(c.healed[3]==1 && c.current[3]==950 && c.corecuActionRegenCarry==0,"Long frames stop exactly at wound-adjusted pool without excess carry");
  c.current[3]-=5;c.activateHAMRegeneration(10);check(c.healed[3]==1,"Capped excess never reappears as a later burst");
 }
 {
  CreatureObjectImplementation c;c.player=false;c.combat=false;advance(c,std::vector<int>(10,1000));
  check(c.healed[0]==20 && c.healed[3]==20 && c.healed[6]==20,"Legacy NPC per-tick ceil remains unchanged");
  c.combat=true;c.activateHAMRegeneration(10000);check(c.healed[3]==20,"Legacy NPC combat regeneration remains disabled");
 }
 for(double bad:{std::numeric_limits<double>::quiet_NaN(),std::numeric_limits<double>::infinity(),-1.,0.}){
  double carry=.7;check(corecu::regeneration::tick(bad,carry,10)==0 && carry==0,"Malformed or inactive amount clears fractional carry");
 }
 std::cout<<"Fractional native regeneration checks: "<<checks<<", failures: "<<failures<<"\n";
 return failures?1:0;
}
