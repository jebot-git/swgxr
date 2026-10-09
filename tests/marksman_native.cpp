#include "server/combat/MarksmanPolicy.h"
#include "server/combat/BountyHunterPolicy.h"
#include "server/combat/CoreCuPolicy.h"
#include <cassert>
#include <map>
#include <set>
#include <iostream>
constexpr unsigned hash(const char* p,unsigned h=0){return *p?hash(p+1,h*31+*p):h;}
#define STRING_HASHCODE(s) hash(s)
struct CommandEffect {enum{BLIND,NEXTATTACKDELAY};};
struct CreatureState {enum{BLEEDING};};
struct BuffType {enum{STATE};};
struct CreatureObject;
struct Buff {unsigned id;int seconds;std::map<std::string,int> mods;Buff(CreatureObject*,unsigned key,int duration,int):id(key),seconds(duration){}void setSkillModifier(const char* key,int value){mods[key]=value;}};
template<class T>using ManagedReference=T;
struct Locker {template<class A,class B>Locker(A,B){}};
struct CreatureObject {
 bool ai=true,pet=false,dead=false,incap=false,boss=false,droid=false,dotImmune=false,delay=false;
 CreatureObject* getPlayerObject(){return this;}bool hasAbility(const char* key){return skills.count(key);}
 bool carbine=false,brace=false,suppression=false;
 double resistance=0;int budget=0,dotSeconds=0,delaySeconds=0;unsigned dotKey=0;
 std::set<int> immunities;std::set<std::string> timers,skills;std::map<unsigned,Buff> buffs;
 bool isAiAgent(){return ai;}CreatureObject* asAiAgent(){return this;}bool isPet(){return pet;}bool isDead(){return dead;}bool isIncapacitated(){return incap;}bool isDroidObject(){return droid;}
 bool checkCooldownRecovery(const char* key){return !timers.count(key);}bool hasEffectImmunity(int key){return immunities.count(key);}bool hasDotImmunity(int){return dotImmune;}bool hasAttackDelay(){return delay;}bool hasBuff(unsigned key){return buffs.count(key);}bool hasSkill(const char* key){return skills.count(key);}int getSkillMod(const char*){return 0;}
 void addCooldown(const char* key,int millis){assert(millis==8000);timers.insert(key);}
 void addBuff(Buff* b){buffs.emplace(b->id,*b);delete b;}
 void addDotState(CreatureObject*,int type,unsigned key,int value,int pool,int seconds,int potency,int){assert(type==CreatureState::BLEEDING && pool==0 && potency==-1);budget=value;dotKey=key;dotSeconds=seconds;}
 void setNextAttackDelay(CreatureObject*,const char*,int,int seconds){delay=true;delaySeconds=seconds;}
};
struct CoreCuCombat {static bool boss(CreatureObject* c){return c->boss;}static double rating(CreatureObject* c,int,int){return c->resistance;}};
struct System {static int roll;static int random(int maximum){assert(maximum==99);return roll;}};int System::roll=0;
struct SwgxrCarbineer {static bool compatible(CreatureObject* c){return c->carbine;}static bool suppressionTrained(CreatureObject* c){return c->suppression;}static double chance(CreatureObject* c,double rating){return std::min(95.,corecu::statusChance(85,rating)+(c->brace && c->carbine?10:0));}};
struct SwgxrBountyHunter {static bool learned(CreatureObject* c,const std::string&){return c->skills.count("combat_bountyhunter_droidresponse_01");}static double chance(CreatureObject*,const std::string&,double rating){return corecu::bountyhunter::chance(rating,50);}};
#include "marksman_effects.inc"
int main(){
 CreatureObject c,a;int checks=0;
 for(auto id:{"suppression_fire","warning_shot","controlled_burst","bleeding_shot"}){
  for(int gate=0;gate<5;++gate){a=CreatureObject{};if(gate==0)a.ai=false;if(gate==1)a.pet=true;if(gate==2)a.dead=true;if(gate==3)a.incap=true;
   assert(SwgxrMarksman::targetReady(&a,id)==(gate==4));++checks;}
  a=CreatureObject{};SwgxrMarksman::effects(&c,&a,id,0);assert(a.buffs.empty() && a.budget==0 && !a.delay && a.timers.empty());++checks;
 }
 a=CreatureObject{};a.boss=true;assert(!SwgxrMarksman::targetReady(&a,"warning_shot"));assert(SwgxrMarksman::targetReady(&a,"suppression_fire"));++checks;
 a=CreatureObject{};a.timers.insert("nextAttackDelayRecovery");assert(!SwgxrMarksman::targetReady(&a,"warning_shot"));++checks;
 a=CreatureObject{};a.timers.insert("corecu_control_recovery");assert(!SwgxrMarksman::targetReady(&a,"suppression_fire") && !SwgxrMarksman::targetReady(&a,"warning_shot"));assert(SwgxrMarksman::targetReady(&a,"bleeding_shot"));++checks;
 for(bool improved:{false,true}){a=CreatureObject{};c.skills.clear();if(improved)c.skills.insert("combat_marksman_support_03");SwgxrMarksman::effects(&c,&a,"warning_shot",25);assert(a.delaySeconds==(improved?3:2) && a.timers.count("corecu_control_recovery"));++checks;}
 a=CreatureObject{};SwgxrMarksman::effects(&c,&a,"suppression_fire",50);auto& buff=a.buffs.at(STRING_HASHCODE("swgxr_suppression_fire"));assert(buff.seconds==6 && buff.mods.at("private_accuracy_bonus")==-20);assert(!SwgxrMarksman::targetReady(&a,"suppression_fire"));++checks;
 for(auto id:{"warning_shot","suppression_fire"}){a=CreatureObject{};System::roll=99;SwgxrMarksman::effects(&c,&a,id,50);assert(a.buffs.empty() && !a.delay && a.timers.count("corecu_control_recovery"));++checks;}System::roll=0;
 for(int immunity=0;immunity<2;++immunity){a=CreatureObject{};a.droid=immunity==0;a.dotImmune=immunity==1;SwgxrMarksman::effects(&c,&a,"bleeding_shot",1000);assert(a.budget==0);++checks;}
 a=CreatureObject{};SwgxrMarksman::effects(&c,&a,"bleeding_shot",1000);assert(a.budget==300 && a.dotSeconds==12 && a.dotKey==STRING_HASHCODE("swgxr_fencer_bleed"));++checks;
 a=CreatureObject{};SwgxrMarksman::effects(&c,&a,"controlled_burst",1000);assert(a.buffs.empty() && a.budget==0 && !a.delay && a.timers.empty());++checks;
 for(auto id:{"suppression_fire","warning_shot"}){a=CreatureObject{};a.immunities.insert(std::string(id)=="suppression_fire"?CommandEffect::BLIND:CommandEffect::NEXTATTACKDELAY);SwgxrMarksman::effects(&c,&a,id,100);assert(a.buffs.empty() && !a.delay && a.timers.empty());++checks;}
 c.skills={"combat_pistol_novice","healthShot2"};a=CreatureObject{};SwgxrMarksman::effects(&c,&a,"bleeding_shot",1000);assert(a.budget==400);++checks;
 c.skills.erase("combat_pistol_novice");a=CreatureObject{};SwgxrMarksman::effects(&c,&a,"bleeding_shot",1000);assert(a.budget==300);++checks;
 for(bool compatible:{false,true}){c.carbine=compatible;c.suppression=true;a=CreatureObject{};SwgxrMarksman::effects(&c,&a,"suppression_fire",50);assert(a.buffs.at(STRING_HASHCODE("swgxr_suppression_fire")).mods.at("private_accuracy_bonus")==-(compatible?25:20));++checks;}
 c.carbine=true;c.brace=true;a=CreatureObject{};System::roll=90;SwgxrMarksman::effects(&c,&a,"suppression_fire",50);assert(a.buffs.size()==1);++checks;
 a=CreatureObject{};c.brace=false;SwgxrMarksman::effects(&c,&a,"suppression_fire",50);assert(a.buffs.empty() && a.timers.count("corecu_control_recovery"));++checks;System::roll=0;
 c.skills.clear();c.suppression=true;c.carbine=false;assert(!SwgxrMarksman::learned(&c,"suppression_fire"));c.carbine=true;assert(SwgxrMarksman::learned(&c,"suppression_fire"));c.carbine=false;c.skills={"combat_marksman_novice","combat_marksman_support_04"};assert(SwgxrMarksman::learned(&c,"suppression_fire"));++checks;
 c.skills={"combat_bountyhunter_droidresponse_01"};a=CreatureObject{};SwgxrMarksman::effects(&c,&a,"bleeding_shot",1000);assert(a.budget==400 && SwgxrMarksman::damage(&c,"bleeding_shot")==.8 && SwgxrMarksman::actionCost(&c,"bleeding_shot")==55);++checks;
 c.skills.insert("torsoShot");a=CreatureObject{};SwgxrMarksman::effects(&c,&a,"bleeding_shot",1000);assert(a.budget==450 && SwgxrMarksman::bleedFraction(&c)==.45);++checks;
 c.skills.insert("combat_pistol_novice");c.skills.insert("healthShot2");a=CreatureObject{};SwgxrMarksman::effects(&c,&a,"bleeding_shot",1000);assert(a.budget==400 && SwgxrMarksman::damage(&c,"bleeding_shot")==1 && SwgxrMarksman::actionCost(&c,"bleeding_shot")==50 && !SwgxrMarksman::bountyBleed(&c));++checks;
 std::cout<<checks<<" actual Marksman effect/eligibility cases passed (isolated native dependencies)\n";
}
