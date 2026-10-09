#include "server/combat/CoreCuPolicy.h"
#include "server/combat/SquadLeaderPolicy.h"
#include "server/medic/CombatMedicPolicy.h"
#include "server/combat/DoctorPolicy.h"
#include "server/combat/TkaPolicy.h"
#include "server/combat/SwordsmanPolicy.h"
#include "server/combat/FencerPolicy.h"
#include "corecu_profiles.inc"
#include <nlohmann/json.hpp>
#include <cassert>
#include <iostream>
#include <map>
#include <set>
#include <vector>
using JSONSerializationType=nlohmann::json;
using uint64=unsigned long long;using uint32=unsigned;
struct String:std::string {using std::string::string;String(const std::string& s):std::string(s){}const char* toCharArray()const{return c_str();}};
constexpr unsigned hash(const char* p,unsigned h=0){return *p?hash(p+1,h*31+*p):h;}
#define STRING_HASHCODE(s) hash(s)
template<class T>using Reference=T;
template<class T>struct Vector:std::vector<T>{T get(int i)const{return this->at(i);}};
struct SkillList {std::set<std::string> skills;void getStringList(Vector<String>& out){for(const auto& s:skills)out.push_back(s);}};
struct BuffType {enum {MEDICAL};};struct BuffCRC {static unsigned getMedicalBuff(int a){return 100+a;}};
struct CommandEffect {enum {STUN,BLIND,DIZZY,INTIMIDATE,KNOCKDOWN,POSTUREUP,POSTUREDOWN,NEXTATTACKDELAY};};
struct CreatureState {enum{BLEEDING,POISONED,DISEASED,ONFIRE,SWIMMING};};
struct BuffAttribute {static String getProtectionString(int a){return a==9?"resistance_poison":"resistance_disease";}static String getAbsorptionString(int a){return a==9?"absorption_poison":"absorption_disease";}};
struct SkillModManager {enum{BUFF};static SkillModManager* instance(){static SkillModManager m;return &m;}int getMinSkill(int){return -125;}int getMaxSkill(int){return 125;}};
struct CreatureObject;
struct Buff {CreatureObject* owner;unsigned id;float seconds;std::map<int,int> attrs;std::map<std::string,int> mods;bool fill=true;Buff(CreatureObject* c,unsigned i,float s,int):owner(c),id(i),seconds(s){}void setFillAttributesOnBuff(bool value){fill=value;}void setAttributeModifier(int a,int v){attrs[a]=v;}void setSkillModifier(const String& s,int v){mods[s]=v;}int getAttributeModifierValue(int a){return attrs[a];}int getSkillModifierValue(const String& s){return mods[s];}float getTimeLeft(){return seconds;}};
struct Weapon {bool valid=true;bool isUnarmedWeapon(){return valid;}bool isCertifiedFor(CreatureObject*){return valid;}};
struct Template {String getTemplateName(){return "ordinary";}};
struct CreatureObject {int base[9]={3000,300,300,1000,300,300,1000,300,300},maximum[9]={3000,300,300,1000,300,300,1000,300,300},ham[9]={2450,300,300,600,300,300,750,300,300};std::map<unsigned,Buff*> buffs;std::map<std::string,int> mods;SkillList list;Weapon weapon;Template creatureTemplate;bool squadFormup=false,player=true,pet=false,ai=false,dead=false,incap=false,swimming=false,feigning=false,attackDelay=false;int level=50,shock=0,damageApplied=0,woundsApplied=0;bool isPlayerCreature(){return player;}bool isPet(){return pet;}bool isAiAgent(){return ai;}CreatureObject* asAiAgent(){return this;}int getLevel(){return level;}Template* getCreatureTemplate(){return &creatureTemplate;}int getBaseHAM(int a){return base[a];}int getHAM(int a){return ham[a];}int getMaxHAM(int a){return maximum[a];}int getWounds(int){return 0;}void setHAM(int a,int v){ham[a]=v;}Buff* getBuff(unsigned crc){return buffs.count(crc)?buffs[crc]:nullptr;}void addBuff(Buff* b){buffs[b->id]=b;for(auto [a,v]:b->attrs){maximum[a]+=v;if(b->fill)ham[a]=maximum[a];}}void removeBuff(unsigned crc){auto b=getBuff(crc);if(!b)return;for(auto [a,v]:b->attrs){maximum[a]-=v;ham[a]=std::min(ham[a],maximum[a]);}buffs.erase(crc);}int getSkillModOfType(const String& s,int){int value=0;for(auto [id,b]:buffs)value+=b->getSkillModifierValue(s);return value;}int getSkillMod(const String& s){return mods[s]+std::max(-125,std::min(125,getSkillModOfType(s,0)));}bool hasSkill(const String& s){return list.skills.count(s);}bool hasBuff(unsigned crc){return getBuff(crc);}SkillList* getSkillList(){return &list;}Weapon* getWeapon(){return &weapon;}bool isDead(){return dead;}bool isIncapacitated(){return incap;}bool isFeigningDeath(){return feigning;}bool hasState(int state){return state==CreatureState::SWIMMING && swimming;}int getShockWounds(){return shock;}void inflictDamage(CreatureObject*,int a,int value,bool,const char*,bool,bool){ham[a]-=value;damageApplied+=value;}bool hasAttackDelay(){return attackDelay;}void removeAttackDelay(){attackDelay=false;}void playEffect(const char*,const char*){}void addWounds(int,int value,bool,bool){woundsApplied+=value;}void addShockWounds(int value){shock+=value;}};
struct SwgxrSquadLeader {static double statusRating(CreatureObject* c,double base){return corecu::squadleader::status(base,c->squadFormup);}};
#include "corecu_combat_native.inc"
#include "doctor_preparation_native.inc"
struct CreatureAttribute {enum{ACTION=3};};
struct Math {template<class T>static T min(T a,T b){return std::min(a,b);}template<class T>static T max(T a,T b){return std::max(a,b);}};
struct Locker {template<class...T>Locker(T...){}};
struct Tasks {template<class F>void executeTask(F f,const char*){f();}};struct Core {static Tasks* getTaskManager(){static Tasks t;return &t;}};
struct System {static int roll,calls;static int random(int){++calls;return roll;}};int System::roll=0;int System::calls=0;
#include "doctor_dot_entry.inc"
#include "doctor_disease_tick.inc"
void train(CreatureObject& c,const std::string& name){c.list.skills.insert(name+"_novice");c.list.skills.insert(name+"_master");for(auto branch:{"a","b","c","d"})for(int i=1;i<=4;++i)c.list.skills.insert(name+"_"+branch+"_0"+std::to_string(i));}
int main(){using namespace corecu;int checks=0;auto check=[&](bool x){assert(x);++checks;};auto close=[](double a,double b){return std::abs(a-b)<1e-8;};
 check(close(statusReduction(60),60./210) && statusReduction(100)==.4 && close(statusReduction(125),125./275));
 for(double r:{-500.,0.,20.,40.,60.,65.,90.,100.,125.,150.,1e9}){check(statusReduction(r)>=0 && statusReduction(r)<=.5);check(statusChance(95,r)>=47.5 && statusChance(95,r)<=95);check(statusDuration(60,r)>=30 && statusDuration(60,r)<=60);}
 check(preparedRating(999,25)==125 && preparedRating(65,999)==90 && preparedRating(-1,-5)==0);
 {CreatureObject group;train(group,"science_doctor");train(group,"science_medic");group.squadFormup=true;SwgxrDoctorPreparation::apply(&group,9,25,500,10);check(close(CoreCuCombat::rating(&group,Poison),110));group.mods["resistance_poison"]=95;check(CoreCuCombat::rating(&group,Poison)==125);group.squadFormup=false;check(close(CoreCuCombat::rating(&group,Poison),120));}
 CreatureObject c;train(c,"science_doctor");train(c,"science_medic");check(close(CoreCuCombat::rating(&c,Poison),65));check(close(CoreCuCombat::rating(&c,Disease),65));
 SwgxrDoctorPreparation::apply(&c,9,25,500,10);check(close(CoreCuCombat::rating(&c,Poison),90));check(CoreCuCombat::rawModifier(&c,"resistance_poison")==0);check(close(CoreCuCombat::rating(&c,Disease),65));
 c.mods["resistance_poison"]=80;check(CoreCuCombat::rawModifier(&c,"resistance_poison")==80 && c.getSkillMod("resistance_poison")==105);check(CoreCuCombat::rating(&c,Poison)==105);check(CoreCuCombat::rating(&c,Poison,CoreCuCombat::rawModifier(&c,"resistance_poison"))==105);
 c.mods["poison_disease_resist"]=30;check(CoreCuCombat::rating(&c,Poison)==125 && CoreCuCombat::rating(&c,Poison,110)==125);c.mods["resistance_poison"]=500;check(CoreCuCombat::rating(&c,Poison)==125);c.mods.clear();
 auto snap=CoreCuCombat::snapshot(&c);auto p=snap["effective_resistance"]["poison"];check(close(p["profession_rating"],65) && close(p["baseline_rating"],65) && p["native_rating"]==0 && p["preparation_rating"]==25 && close(p["rating"],90));check(close(p["chance_reduction"],.375) && p["defense_context"]=="standard_native_modifiers");
 c.list.skills.clear();check(CoreCuCombat::rating(&c,Poison)==25);c.removeBuff(109);check(CoreCuCombat::rating(&c,Poison)==0);train(c,"science_doctor");train(c,"science_medic");
 SwgxrDoctorPreparation::apply(&c,9,25,100,10);SwgxrDoctorPreparation::apply(&c,10,20,100,10);check(close(CoreCuCombat::rating(&c,Poison),65) && close(CoreCuCombat::rating(&c,Disease),85));
 c.removeBuff(110);auto legacy=new Buff(&c,109,77,0);legacy->setSkillModifier("resistance_poison",500);legacy->setSkillModifier("absorption_poison",50);c.addBuff(legacy);check(CoreCuCombat::rawModifier(&c,"resistance_poison")==0 && close(CoreCuCombat::rating(&c,Poison),90));c.mods["resistance_poison"]=100;check(c.getSkillMod("resistance_poison")==225 && CoreCuCombat::rawModifier(&c,"resistance_poison")==100 && CoreCuCombat::rating(&c,Poison)==125);c.mods.clear();SwgxrDoctorPreparation::normalize(&c);check(c.getBuff(109)->seconds==77 && c.getBuff(109)->getSkillModifierValue("resistance_poison")==25 && close(CoreCuCombat::rating(&c,Poison),90));check(c.ham[0]==2450 && c.ham[3]==600);
 // Focus remains +20 to the selected ordinary baseline, never above100 or twice.
 c.list.skills.clear();train(c,"combat_unarmed");auto focus=new Buff(&c,STRING_HASHCODE("swgxr_indomitable_focus"),12,0);c.addBuff(focus);check(close(CoreCuCombat::rating(&c,Stun),80));check(CoreCuCombat::rating(&c,Stun,95)==100);check(CoreCuCombat::rating(&c,Poison)==65);c.mods["resistance_poison"]=80;check(CoreCuCombat::rating(&c,Poison)==125);c.mods.clear();
 auto trap=new Buff(&c,STRING_HASHCODE("throw_trap_state_def_1"),10,0);trap->setSkillModifier("stun_defense",-40);c.addBuff(trap);check(close(CoreCuCombat::rating(&c,Stun,-40),40));c.removeBuff(trap->id);
 auto exposed=new Buff(&c,STRING_HASHCODE("swgxr_exposed_thrust"),10,0);c.addBuff(exposed);check(CoreCuCombat::rating(&c,Blind)==40);check(CoreCuCombat::rating(&c,Poison)==65);
 CreatureObject ai;ai.player=false;ai.ai=true;ai.level=500;check(CoreCuCombat::rating(&ai,Poison)==100);check(statusReduction(CoreCuCombat::rating(&ai,Poison))==.4);
 for(int base:{100,1000,10000})for(double raw:{0.,1.,40.,50.,100.,1e9})for(double absorption:{0.,10.,25.,50.,100.}){int value=diseaseTick(base,raw,absorption);check(value>=0 && value<=base/20);check(value<=diseaseTick(base,raw,0));}
 check(diseaseTick(1000,100,10)==45 && diseaseTick(1000,40,10)==36 && diseaseTick(1000,1e9,10)==45 && diseaseTick(1000,100,100)==25);
 // Execute the production shared DoT entry predicate, including negative potency and swimming.
 CreatureObject dotTarget;train(dotTarget,"science_doctor");train(dotTarget,"science_medic");SwgxrDoctorPreparation::apply(&dotTarget,9,25,100,10);
 System::roll=59;check(doctorDotEntry(&dotTarget,CreatureState::POISONED,60,95,0,100)==38);System::roll=60;check(doctorDotEntry(&dotTarget,CreatureState::POISONED,60,95,0,100)==0);
 int calls=System::calls;System::roll=100;check(doctorDotEntry(&dotTarget,CreatureState::POISONED,60,-1,0,100)==38 && System::calls==calls);check(doctorDotEntry(&dotTarget,CreatureState::POISONED,60,-1,0,0)==0 && System::calls==calls);
 dotTarget.swimming=true;check(doctorDotEntry(&dotTarget,CreatureState::ONFIRE,60,-1,0,100)==0);
 // Execute the complete production disease-tick function with immediate task dependencies.
 DamageOverTime tick;CreatureObject patient,attacker;patient.mods["absorption_disease"]=10;patient.attackDelay=true;tick.strength=100;check(tick.doDiseaseTick(&patient,&attacker)==45 && patient.ham[3]==555 && patient.ham[0]==2450 && patient.woundsApplied==0 && !patient.attackDelay);
 patient.ham[3]=20;check(tick.doDiseaseTick(&patient,&attacker)==19 && patient.ham[3]==1);check(tick.doDiseaseTick(&patient,&attacker)==0 && patient.ham[3]==1);
 patient.ham[3]=600;patient.shock=1000;check(tick.doDiseaseTick(&patient,&attacker)==45);patient.incap=true;check(tick.doDiseaseTick(&patient,&attacker)==0);patient.incap=false;patient.mods["absorption_disease"]=0;check(tick.doDiseaseTick(&patient,&attacker)==50);
 patient.player=false;patient.pet=true;patient.mods["absorption_disease"]=10;check(tick.doDiseaseTick(&patient,&attacker)==45 && patient.woundsApplied==0);patient.pet=false;patient.shock=0;check(tick.doDiseaseTick(&patient,&attacker)==10 && patient.woundsApplied==10);
 std::cout<<"Doctor resistance native: "<<checks<<" checks passed\n";
}
