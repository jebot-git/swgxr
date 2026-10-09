// The entire production CombatManager::getArmorReduction body is supplied by
// the Python runner. Only its object/command dependencies are isolated fixtures.
#include "server/combat/ArmourModel.h"
#include "server/combat/SwordsmanPolicy.h"
#include <cassert>
#include <cmath>
#include <iostream>
#include <map>
#include <string>

struct CreatureObject;
struct TangibleObject {
 virtual ~TangibleObject()=default;
 void inflictDamage(CreatureObject*,int,float,bool,bool,bool){}
};
namespace ObserverEventType {enum {FORCEARMOR,FORCESHIELD,FORCEFEEDBACK,FORCEABSORB};}
namespace BuffCRC {enum {JEDI_FORCE_FEEDBACK_1,JEDI_FORCE_FEEDBACK_2};}
namespace CreatureAttribute {enum {HEALTH,ACTION,MIND};}
struct ArmorObject {
 std::map<int,double> resists;bool broken=false,vulnerable=false;double wear=0;
 bool isBroken()const{return broken;}bool isVulnerable(int)const{return vulnerable;}
 void inflictDamage(ArmorObject*,int,double amount,bool,bool){wear+=amount;}
};
struct CreatureObject:TangibleObject {
 bool ai=false,vehicle=false,player=false,pet=false,fractured=false;
 std::map<int,double> resists;std::map<std::string,int> skills;double unmitigated=0;
 bool isAiAgent()const{return ai;}bool isVehicleObject()const{return vehicle;}
 bool isPlayerCreature()const{return player;}bool isPet()const{return pet;}
 void addUnmitigatedDamage(double amount){unmitigated+=amount;}
 int getSkillMod(const std::string& key){return skills[key];}
 void notifyObservers(int,TangibleObject*,float){}bool hasBuff(int)const{return false;}
 void playEffect(const char*,const char*){}
};
struct AiAgent:CreatureObject {AiAgent(){ai=true;}};
struct VehicleObject:CreatureObject {VehicleObject(){vehicle=true;}};
template<class T,class U>T cast(U* value){return static_cast<T>(value);}
struct WeaponObject {int type=2,ap=0;bool broken=false;int getDamageType()const{return type;}int getArmorPiercing()const{return ap;}bool isBroken()const{return broken;}};
struct CombatQueueCommand {
 virtual ~CombatQueueCommand()=default;
 virtual double getBodyResistanceMultiplier(int)const{return 1.;}
};
struct PiercingCommand:CombatQueueCommand {
 double getBodyResistanceMultiplier(int type)const override{return type==1 || type==2?.5:1.;}
};
struct CreatureAttackData {
 const CombatQueueCommand* command=nullptr;bool force=false;int type=2;
 bool isForceAttack()const{return force;}int getDamageType()const{return type;}
 const CombatQueueCommand* getCommand()const{return command;}
};
struct DefenderHitList {
 double jedi=0,psg=0,armor=0;
 double getJediMitigation()const{return jedi;}void setJediMitigation(double v){jedi=v;}
 double getPsgMitigation()const{return psg;}void setPsgMitigation(double v){psg=v;}
 double getArmorMitigation()const{return armor;}void setArmorMitigation(double v){armor=v;}
 void setForceFeedback(double){}void setForceAbsorb(double){}
};
struct Locker {explicit Locker(ArmorObject*){}};
struct CoreCuCombat {
 static double bodyResistance(CreatureObject* c,int channel,double resistance){return corecu::swordsman::fracturedResistance(resistance,channel,c->fractured);}
};
struct CombatManager {
 ArmorObject* armor=nullptr;ArmorObject* psg=nullptr;
 int getArmorReduction(TangibleObject*,WeaponObject*,CreatureObject*,DefenderHitList*,float,int,const CreatureAttackData&)const;
 int getArmorNpcReduction(AiAgent* c,int type)const{return int(100*CoreCuCombat::bodyResistance(c,type,c->resists[type]));}
 int getArmorVehicleReduction(VehicleObject* c,int type)const{return int(100*c->resists[type]);}
 ArmorObject* getPSGArmor(CreatureObject*)const{return psg;}
 ArmorObject* getArmorObject(CreatureObject*,int)const{return armor;}
 double getArmorObjectReduction(ArmorObject* a,int type)const{return 100*a->resists[type];}
};
#include "rifleman_armour.inc"

int main(){
 CombatManager manager;CreatureObject attacker,player;AiAgent npc;VehicleObject vehicle;
 WeaponObject weapon;CombatQueueCommand ordinary;PiercingCommand piercing;
 CreatureAttackData normal{&ordinary},special{&piercing},missing;
 ArmorObject armor,shield;manager.armor=&armor;manager.psg=&shield;player.player=true;
 int checks=0;
 auto hit=[&](CreatureObject* target,const CreatureAttackData& data,DefenderHitList* details=nullptr){DefenderHitList local;return manager.getArmorReduction(&attacker,&weapon,target,details?details:&local,1000,0,data);};
 // Piercing affects both base channels only for its own resolution, and never
 // leaves a debuff or changes weapon armour-piercing statistics.
 for(int channel:{1,2}){
  weapon.type=channel;npc.resists[channel]=.4;armor.resists[channel]=.4;
  for(auto* target:{static_cast<CreatureObject*>(&npc),&player}){
   assert(hit(target,normal)==600);assert(hit(target,special)==800);
   assert(hit(target,normal)==600);assert(hit(target,missing)==600);++checks;
  }
  assert(npc.resists[channel]==.4 && armor.resists[channel]==.4 && weapon.ap==0);
 }
 // Fracture is already folded into NPC/body resistance. Halve that result once.
 weapon.type=2;npc.fractured=player.fractured=true;
 for(auto* target:{static_cast<CreatureObject*>(&npc),&player}){
  assert(hit(target,normal)==750);assert(hit(target,special)==875);++checks;
 }
 npc.fractured=player.fractured=false;
 // Elemental component and strongest shield mitigation remain untouched.
 weapon.type=32;armor.resists[2]=.4;armor.resists[32]=.1;shield.resists[32]=.5;
 const double elementalScale=swgxr::armour::weapon(32,0).damageScale;
 DefenderHitList normalDetails,pierceDetails;
 assert(std::abs(hit(&player,normal,&normalDetails)-580*elementalScale)<1.01);
 assert(std::abs(hit(&player,special,&pierceDetails)-740*elementalScale)<1.01);
 assert(std::abs(normalDetails.psg-100*elementalScale)<.0001 && normalDetails.psg==pierceDetails.psg);
 assert(std::abs(normalDetails.armor-320*elementalScale)<.0001 && std::abs(pierceDetails.armor-160*elementalScale)<.0001);++checks;
 npc.resists[2]=.4;npc.resists[32]=.5;
 assert(std::abs(hit(&npc,normal)-580*elementalScale)<1.01 && std::abs(hit(&npc,special)-740*elementalScale)<1.01);++checks;
 // With no body armour there is no penetration benefit, even behind a shield.
 armor.resists[2]=0;armor.resists[32]=0;
 assert(std::abs(hit(&player,normal)-900*elementalScale)<1.01 && hit(&player,special)==hit(&player,normal));++checks;
 // Native AP profile remains intact: compare with the shared armour model
 // across every grade and source damage channel, including elemental splits.
 for(int type:{1,2,4,8,16,32,64,128,256})for(int ap=0;ap<4;++ap){
  weapon.type=type;weapon.ap=ap;
  for(int channel:{1,2,4,8,16,32,64,128,256})npc.resists[channel]=.4;
  auto profile=swgxr::armour::weapon(type,ap);
  swgxr::armour::Damage expected(1000,profile);
  expected.mitigate(.2,.4);
  assert(std::abs(hit(&npc,special)-expected.total())<1.01);
  assert(weapon.ap==ap && weapon.type==type);++checks;
 }
 // Broken equipment and force mitigation remain in the normal native pipeline.
 weapon.type=2;weapon.ap=3;weapon.broken=true;
 assert(hit(&npc,special)==800);++checks;
 weapon.broken=false;weapon.ap=0;armor.resists[2]=.4;armor.broken=true;
 assert(hit(&player,special)==1000);armor.broken=false;++checks;
 player.skills["force_armor"]=25;
 assert(hit(&player,normal)==450 && hit(&player,special)==600);++checks;
 assert(manager.getArmorReduction(&attacker,&weapon,&npc,nullptr,1000,0,special)==0);++checks;
 std::cout<<checks<<" production rifle penetration/armour cases passed (isolated dependencies)\n";
}
