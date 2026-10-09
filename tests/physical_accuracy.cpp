// Isolated native resolver harness. The runner supplies getHitChance verbatim
// from the patched Core3 source; dependencies and RNG are deterministic fixtures.
#include "server/combat/VolleyFirePolicy.h"
#include <cassert>
#include <iostream>
#include <string>
namespace HitStatus {enum {MISS,HIT,BLOCK,DODGE,COUNTER,RICOCHET};}
namespace WeaponType {enum {GRENADEWEAPON=8,HEAVYWEAPON=16};}
struct SharedWeaponObjectTemplate {enum {UNARMEDWEAPON=1,RANGEDATTACK=2};};
struct Vector3 {float distanceTo(const Vector3&)const{return 20;}};
struct WeaponObject {int mask=1,type=2;bool isRangedWeapon()const{return type==SharedWeaponObjectTemplate::RANGEDATTACK;}int getWeaponBitmask()const{return mask;}int getAttackType()const{return type;}};
struct CreatureObject;
struct TangibleObject {
 uint64_t oid=0;uint64_t getObjectID()const{return oid;}bool player=false;virtual ~TangibleObject()=default;
 bool isPlayerCreature()const{return player;}bool isCreatureObject()const{return true;}bool isTurret()const{return false;}
 CreatureObject* asCreatureObject();Vector3 getWorldPosition()const{return {};}float getTemplateRadius()const{return 0;}
};
struct CreatureObject:TangibleObject {
 int skill=0,squadMelee=0,squadRanged=0;WeaponObject weapon;
 int getSkillMod(const std::string&)const{return skill;}
 bool isCreature()const{return false;}
 struct Reference {WeaponObject* value;WeaponObject* get()const{return value;}};
 Reference getWeapon(){return {&weapon};}
};
CreatureObject* TangibleObject::asCreatureObject(){return static_cast<CreatureObject*>(this);}
struct CombatQueueCommand {bool physical=false;bool usesPhysicalContactAccuracy()const{return physical;}std::string getAccuracySkillMod()const{return "accuracy";}};
struct CreatureAttackData {
 CombatQueueCommand command;bool force=false,state=false;
 const CombatQueueCommand* getCommand()const{return &command;}
 bool isForceAttack()const{return force;}bool isStateOnlyAttack()const{return state;}
};
struct System {static int rolls;static int random(int){++rolls;return 50;}};int System::rolls=0;
struct CoreCuCombat {static int centerDefense(CreatureObject* c){return c->skill;}};
struct SwgxrSquadLeader {
 static int calls;static bool ranged;
 static int defenseBonus(CreatureObject* c,bool isRanged){++calls;ranged=isRanged;return isRanged?c->squadRanged:c->squadMelee;}
};int SwgxrSquadLeader::calls=0;bool SwgxrSquadLeader::ranged=false;
struct CombatManager {
 int chance=0,secondary=0,result=HitStatus::DODGE;mutable float observedDefense=0;
 int getHitChance(TangibleObject*,CreatureObject*,WeaponObject*,const CreatureAttackData&,int,int)const;
 float getWeaponRangeModifier(float,WeaponObject*)const{return -1000;}
 int getAttackerAccuracyModifier(TangibleObject*,CreatureObject*,WeaponObject*)const{return -1000;}
 int getAttackerAccuracyBonus(CreatureObject*,WeaponObject*)const{return -1000;}
 int calculatePostureModifier(CreatureObject*,WeaponObject*)const{return -1000;}
 int getDefenderDefenseModifier(CreatureObject*,WeaponObject*,TangibleObject*)const{return 1000;}
 int calculateTargetPostureModifier(WeaponObject*,CreatureObject*)const{return 1000;}
 float hitChanceEquation(float,float defense)const{observedDefense=defense;return chance;}
 int getWeaponDefendResult(int)const{return result;}
 int getDefenderSecondaryDefenseModifier(CreatureObject*)const{return secondary;}
};
#include "physical_accuracy_resolver.inc"
int main(){
 CombatManager manager;CreatureObject player,npc,target;player.player=true;player.oid=1;npc.oid=2;target.oid=3;
 CreatureAttackData physical,ordinary;physical.command.physical=true;
 int checks=0;
 // Player accuracy cannot cause a miss or bypass ordinary secondary defenses.
 // Changing accuracy or the primary hit chance leaves the defense result intact.
 target.skill=1000;
 for(int skill:{-1000,0,1000})for(int defense:{HitStatus::DODGE,HitStatus::BLOCK,HitStatus::COUNTER,HitStatus::RICOCHET})for(int type:{1,2})for(int chance:{0,100}){
  player.skill=skill;player.weapon.type=type;manager.chance=chance;manager.secondary=1000;manager.result=defense;System::rolls=0;
  int expected=(defense==HitStatus::RICOCHET && type!=2)?HitStatus::HIT:defense;
  assert(manager.getHitChance(&player,&target,&player.weapon,physical,100,-999)==expected);
  assert(System::rolls==(defense==HitStatus::RICOCHET?(type==2?1:0):2));++checks;
 }
 // With no secondary defense, a confirmed contact hits even at zero native
 // accuracy chance, consumes no RNG and ignores the player's accuracy modifiers.
 manager.chance=0;manager.secondary=0;manager.result=HitStatus::DODGE;
 for(int skill:{-1000,0,1000}){player.skill=skill;System::rolls=0;assert(manager.getHitChance(&player,&target,&player.weapon,physical,100,skill)==HitStatus::HIT);assert(System::rolls==0);++checks;}
 manager.secondary=1000;
 manager.chance=0;
 for(auto* actor:{&player,&npc}){System::rolls=0;assert(manager.getHitChance(actor,&target,&actor->weapon,ordinary,100,0)==HitStatus::MISS);assert(System::rolls>0);++checks;}
 assert(manager.getHitChance(&npc,&target,&npc.weapon,physical,100,0)==HitStatus::MISS);++checks;
 physical.force=true;assert(manager.getHitChance(&player,&target,&player.weapon,physical,100,0)==HitStatus::MISS);++checks;
 physical.force=false;physical.state=true;assert(manager.getHitChance(&player,&target,&player.weapon,physical,100,0)==HitStatus::MISS);++checks;
 // NPC/ordinary-command defenses still run, including their passive mitigation.
 manager.chance=100;target.skill=1000;npc.weapon.type=2;
 for(int defense:{HitStatus::DODGE,HitStatus::BLOCK,HitStatus::COUNTER,HitStatus::RICOCHET}){
  manager.result=defense;assert(manager.getHitChance(&npc,&target,&npc.weapon,ordinary,100,0)==defense);++checks;
 }
 // The native resolver consumes one packet guarantee; a second packet in the
 // same Double Tap/combo immediately returns to normal secondary defenses.
 physical.force=false;physical.state=false;manager.chance=0;manager.secondary=1000;manager.result=HitStatus::DODGE;
 {corecu::volley::Scope volley(player.oid,target.oid);System::rolls=0;
  assert(manager.getHitChance(&player,&target,&player.weapon,physical,100,0)==HitStatus::HIT);assert(System::rolls==0 && volley.resolved());++checks;
  assert(manager.getHitChance(&player,&target,&player.weapon,physical,100,0)==HitStatus::DODGE);assert(System::rolls==2);++checks;
 }
 assert(manager.getHitChance(&player,&target,&player.weapon,physical,100,0)==HitStatus::DODGE);++checks;
 CreatureObject other;other.oid=4;other.skill=1000;
 {corecu::volley::Scope volley(player.oid,target.oid);
  assert(manager.getHitChance(&player,&other,&player.weapon,physical,100,0)==HitStatus::DODGE);assert(!volley.resolved());++checks;
  assert(manager.getHitChance(&player,&target,&player.weapon,physical,0,0)==HitStatus::HIT);assert(volley.resolved());++checks;
 }
 // SL defense is a current party-derived NPC accuracy adjustment. It is not
 // added again to player physical-contact defense or the secondary contest.
 target.squadRanged=15;target.squadMelee=7;manager.secondary=0;manager.chance=0;
 SwgxrSquadLeader::calls=0;npc.weapon.type=2;assert(manager.getHitChance(&npc,&target,&npc.weapon,ordinary,100,0)==HitStatus::MISS);assert(manager.observedDefense==2015 && SwgxrSquadLeader::calls==1 && SwgxrSquadLeader::ranged);++checks;
 SwgxrSquadLeader::calls=0;npc.weapon.type=1;assert(manager.getHitChance(&npc,&target,&npc.weapon,ordinary,100,0)==HitStatus::MISS);assert(manager.observedDefense==2007 && SwgxrSquadLeader::calls==1 && !SwgxrSquadLeader::ranged);++checks;
 SwgxrSquadLeader::calls=0;manager.secondary=1000;assert(manager.getHitChance(&player,&target,&player.weapon,physical,100,0)==HitStatus::DODGE);assert(SwgxrSquadLeader::calls==0);++checks;
 std::cout<<checks<<" native physical-accuracy resolver cases passed (isolated dependencies)\n";
}
