#include "server/combat/CoreCuMedicalPolicy.h"
#include "server/medic/CombatMedicPolicy.h"
#include <nlohmann/json.hpp>
#include <cassert>
#include <cmath>
#include <iostream>
#include <map>
#include <set>
#define STRING_HASHCODE(x) 1
template<class T>using ManagedReference=T;
using Json=nlohmann::json;using JSONSerializationType=Json;using uint64=unsigned long long;
struct String:std::string {using std::string::string;String(const std::string& s):std::string(s){}String(){}const char* toCharArray()const{return c_str();}bool isEmpty()const{return empty();}String toLowerCase()const{return *this;}template<class T>static String valueOf(T value){return std::to_string(value);}};
using UnicodeString=String;
template<class T>struct Ref {T value=nullptr;T get()const{return value;}T operator->()const{return value;}operator T()const{return value;}template<class U>Ref<U> castTo(){return {dynamic_cast<U>(value)};}};
struct Vector3 {double x,y,z;Vector3(double a=0,double b=0,double c=0):x(a),y(b),z(c){}double getX()const{return x;}double getY()const{return y;}double getZ()const{return z;}double distanceTo(const Vector3& o)const{return std::sqrt((x-o.x)*(x-o.x)+(y-o.y)*(y-o.y)+(z-o.z)*(z-o.z));}};
struct CreatureObject;struct PharmaceuticalObject;struct Server;
struct Template {String path;String getFullTemplateString(){return path;}};
struct SceneObject {virtual ~SceneObject(){}uint64 id=0;SceneObject* parent=nullptr;Template templ;bool wearable=false,crate=false,crafting=false,schematic=false;String name="Treatment";
 uint64 getObjectID(){return id;}Ref<SceneObject*> getParent(){return {parent};}Template* getObjectTemplate(){return &templ;}String getDisplayedName(){return name;}bool isFactoryCrate(){return crate;}bool isCraftingTool(){return crafting;}bool isManufactureSchematic(){return schematic;}bool isWearableContainerObject(){return wearable;}
};
struct CreatureState {enum: uint64 {STUNNED=1,DIZZY=2,BLINDED=4,INTIMIDATED=8,ONFIRE=16,POISONED=32,DISEASED=64};static CreatureState* instance(){static CreatureState s;return &s;}String getName(uint64 n){return n==STUNNED?"stunned":n==DIZZY?"dizzy":n==BLINDED?"blinded":"intimidated";}};
struct CreatureAttribute {enum {HEALTH=0,ACTION=3,MIND=6,ARRAYSIZE=9};static String getName(int){return "health";}};struct BuffAttribute {static String getName(int){return "health";}};
struct PharmaceuticalObject:SceneObject {String type="state";int count=3,required=0,attribute=0;uint64 state=1;float range=20;double effectiveness=300;double getEffectiveness(){return effectiveness;}int calculatePower(CreatureObject*,CreatureObject*,bool=true);
 bool isArea(){return areaFlag;}bool areaFlag=false;double area=5,potency=150;double getArea(){return area;}double getPotency(){return potency;}int getDuration(){return 240;}uint64 getDotType(){return type=="poison"?CreatureState::POISONED:CreatureState::DISEASED;}int getPool(){return attribute;}bool isPoisonDeliveryUnit(){return type=="poison";}bool isDiseaseDeliveryUnit(){return type=="disease";}bool isPetStimPack(){return type=="pet";}bool isDroidRepairKit(){return type=="repair";}bool isDroidReconstructionKit(){return type=="reconstruct";}bool isStimPack(){return type=="stim";}bool isRangedStimPack(){return type=="ranged";}bool isWoundPack(){return type=="wound";}bool isEnhancePack(){return type=="enhance";}bool isStatePack(){return type=="state";}bool isRevivePack(){return type=="revive";}bool isCurePack(){return type=="cure";}uint64 getState(){return state;}int getAttribute(){return attribute;}float getRange(){return range;}int getMedicineUseRequired(){return required;}int getUseCount(){return count;}
};
using DotPack=PharmaceuticalObject;
using StimPack=PharmaceuticalObject;using RangedStimPack=PharmaceuticalObject;using WoundPack=PharmaceuticalObject;using EnhancePack=PharmaceuticalObject;using CurePack=PharmaceuticalObject;using StatePack=PharmaceuticalObject;using RevivePack=PharmaceuticalObject;
struct Timer {int ms;int miliDifference(){return -ms;}};
struct BuffType {enum {JEDI};};
struct PrivateBuff {std::map<int,int> modifiers;int duration;PrivateBuff(CreatureObject*,int,int seconds,int):duration(seconds){}void setAttributeModifier(int i,int n){modifiers[i]=n;}};
struct Buff {int getSkillModifierValue(const char*){return 0;}};struct BuffCRC {enum{FOOD_HEAL_RECOVERY};};
struct Group {std::set<CreatureObject*> members;bool hasMember(CreatureObject* c){return members.count(c);}};
struct Command {String grant;int calls=0,result=0;String last;uint64 target=0;String getCharacterAbility(){return grant;}int doQueueCommand(CreatureObject*,uint64 t,const UnicodeString& q){calls++;last=q;target=t;return result;}};
struct Controller {std::map<std::string,Command> commands;Command* getQueueCommand(String name){return commands.count(name)?&commands.at(name):nullptr;}};
struct Server {Controller controller;int zone=0;std::map<uint64,SceneObject*> objects;Controller* getObjectController(){return &controller;}Ref<SceneObject*> getObject(uint64 id){return {objects.count(id)?objects.at(id):nullptr};}};
struct ObjectFlag {enum{NODOT=1};};
struct CreatureObject:SceneObject {bool ai=false,immune=false;int mask=0;bool isAiAgent(){return ai;}CreatureObject* asAiAgent(){return ai?this:nullptr;}int getCreatureBitmask(){return mask;}bool hasDotImmunity(uint64){return immune;}double getHeight(bool){return 1.8;}double getTemplateRadius(){return .4;}std::map<std::string,String> screens;PrivateBuff* debuff=nullptr;void addBuff(PrivateBuff* b){debuff=b;}String getScreenPlayData(const char* a,const char* b){return screens[std::string(a)+b];}void setScreenPlayData(const char* a,const char* b,const String& v){screens[std::string(a)+b]=v;}Server* server=nullptr;SceneObject inventory;Vector3 pos;bool player=true,pet=false,droid=false,dead=false,incap=false,riding=false,hostile=false,healable=true,resuscitable=true,consent=false,los=true;uint64 states=0;int ham[9]={1000,300,300,1000,300,300,1000,300,300};int base[9]={1000,300,300,1000,300,300,1000,300,300};int wounds=0;float bf=1;Group* group=nullptr;std::map<std::string,int> mods;std::set<std::string> skills,grants;std::map<std::string,Timer> timers;
 SceneObject* getSlottedObject(const char*){return &inventory;}bool isPlayerCreature(){return player;}bool isPet(){return pet;}bool isCreature(){return !droid;}bool isDroidObject(){return droid;}bool isDead(){return dead;}bool isIncapacitated(){return incap;}bool isRidingMount(){return riding;}bool isAttackableBy(CreatureObject*){return hostile;}bool isHealableBy(CreatureObject*){return healable;}bool isResuscitable(){return resuscitable;}Group* getGroup(){return group;}int* getZone(){return &server->zone;}Server* getZoneServer(){return server;}CreatureObject* getPlayerObject(){return this;}String getFirstName(){return "doctor";}bool hasInConsentList(const String&){return consent;}bool hasSkill(const char* s){return skills.count(s);}bool hasAbility(const String& s){return grants.count(s);}bool hasState(uint64 s){return states&s;}int getSkillMod(const char* s){return mods[s];}int getHAM(int i){return ham[i];}int getBaseHAM(int i){return base[i];}int getMaxHAM(int i){return base[i];}int getWounds(int){return wounds;}float calculateBFRatio(){return bf;}bool hasDamage(int i){return ham[i]<base[i]-wounds;}Vector3 getWorldPosition(){return pos;}bool isInRange(CreatureObject* c,float range){return pos.distanceTo(c->pos)<=range;}Timer* getCooldownTime(const String& s){return timers.count(s)?&timers.at(s):nullptr;}void addCooldown(const String& s,int ms){timers[s]={ms};}Buff* getBuff(int){return nullptr;}void sendSystemMessage(const char*){}void inflictDamage(CreatureObject*,int p,int amount,bool){ham[p]-=amount;}
};
int PharmaceuticalObject::calculatePower(CreatureObject* c,CreatureObject* p,bool battle){double scale=(isPetStimPack() || isDroidRepairKit())?1.:1.+c->getSkillMod(isRangedStimPack()?"combat_medic_effectiveness":"healing_injury_treatment")/100.;return effectiveness*scale*(battle?p->calculateBFRatio():1.);}
struct SwgxrSpice {struct HamAdjustment{};static double cooldownScale(CreatureObject*){return 1.;}};
struct Locker {template<class A>Locker(A){}template<class A,class B>Locker(A,B){}};
struct QueueCommand {enum{SUCCESS};};struct CollisionManager {static bool checkLineOfSight(CreatureObject*,CreatureObject* t){return t->los;}};
#include "cm_item.inc"
#include "cm_effects.inc"
#include "cm_bridge.inc"
#include "cm_receipt.inc"
int main(){
 int checks=0;auto check=[&](bool ok){if(!ok)std::cerr<<"failed check "<<checks+1<<"\n";assert(ok);++checks;};
 auto rejects=[&](auto call){bool rejected=false;try{call();}catch(const std::exception&){rejected=true;}check(rejected);};
 Server s;CreatureObject c,p;c.server=p.server=&s;c.id=1;p.id=2;c.inventory.parent=&c;
 c.skills={"science_medic_novice","science_combatmedic_novice","science_combatmedic_healing_range_02"};
 c.mods["combat_healing_ability"]=100;c.mods["combat_medic_effectiveness"]=100;c.mods["healing_range"]=100;
 p.pos={0,0,10};p.hostile=true;p.healable=false;s.objects[1]=&c;s.objects[2]=&p;
 for(auto name:{"applypoison","applydisease"}){s.controller.commands[name].grant=name;c.grants.insert(name);}
 PharmaceuticalObject pack;pack.type="poison";pack.attribute=0;pack.id=3;pack.parent=&c.inventory;pack.templ.path="object/tangible/medicine/crafted/medpack_poison_health_a.iff";s.objects[3]=&pack;
 SceneObject focus;focus.id=4;focus.parent=&c.inventory;focus.templ.path="object/tangible/medicine/medikit_tool_basic.iff";s.objects[4]=&focus;
 Json q={{"ability","applypoison"},{"focus_id","4"},{"item_id","3"},{"target_id","2"},{"request_id","combat_medic_001"},{"pose",{{"tracked",true},{"left",{0,1,0}},{"right",{0,1,0}}}}};
 auto query=q;auto out=SwgxrCombatMedic::run(&c,q);check(out["command"]=="applypoison" && out["item_id"]=="3" && out["focus_id"]=="4");check(s.controller.commands["applypoison"].last=="health|3");
 int before=s.controller.commands["applypoison"].calls;auto once=CombatMedicReceiptHarness::run(&c,q);auto replay=CombatMedicReceiptHarness::run(&c,q);check(replay["replayed"]==true && s.controller.commands["applypoison"].calls==before+1);query=q;query["item_id"]="4";rejects([&]{CombatMedicReceiptHarness::run(&c,query);});
 for(bool disease:{false,true})for(bool area:{false,true}){
  pack.type=disease?"disease":"poison";pack.attribute=disease?3:0;pack.areaFlag=area;pack.area=5;
  pack.templ.path=disease?"object/tangible/medicine/crafted/medpack_disease_action_a.iff":"object/tangible/medicine/crafted/medpack_poison_health_a.iff";
  q["ability"]=disease?"applydisease":"applypoison";
  check(SwgxrCombatMedic::run(&c,q)["success"]==true);
  check(s.controller.commands[q["ability"].get<std::string>()].last==(disease?"action|3":"health|3"));
  Json inventory={{"items",Json::array({{{"id","3"}},{{"id","4"}}})}};
  auto snap=SwgxrCombatMedic::snapshot(&c,inventory);check(snap["supplies"].size()==1 && snap["supplies"][0]["area_radius_m"]==(area?5.:0.));check(snap["supplies"][0]["target_cap"]==(area?6:1));
  check(snap["abilities"][0]["action_cost"]==60 && snap["abilities"][0]["mind_cost"]==80);
  auto target=SwgxrCombatMedic::target(&c,&p,snap);check(!target.is_null() && target["ability_available"][disease?"applydisease":"applypoison"]==true);
  p.immune=true;check(SwgxrCombatMedic::target(&c,&p,snap).is_null());rejects([&]{SwgxrCombatMedic::run(&c,q);});p.immune=false;
 }
 pack.type="poison";pack.attribute=0;pack.areaFlag=false;pack.templ.path="object/tangible/medicine/crafted/medpack_poison_health_a.iff";q["ability"]="applypoison";
 for(auto name:{"healmind","healstate","quickheal","kill",""}){query=q;query["ability"]=name;rejects([&]{SwgxrCombatMedic::run(&c,query);});}
 for(auto field:{"focus_id","item_id","target_id"}){
  query=q;query.erase(field);rejects([&]{SwgxrCombatMedic::run(&c,query);});
  for(auto value:{"0","","-1","3junk","184467440737095516166"}){query=q;query[field]=value;rejects([&]{SwgxrCombatMedic::run(&c,query);});}
 }
 query=q;query["focus_id"]="3";rejects([&]{SwgxrCombatMedic::run(&c,query);});focus.parent=nullptr;rejects([&]{SwgxrCombatMedic::run(&c,q);});focus.parent=&c.inventory;
 for(auto field:{"left","right"})for(auto value:{Json::array({0,3,0}),Json::array({0,0}),Json::array({0,"bad",0}),Json::array({0,10001,0})}){query=q;query["pose"][field]=value;rejects([&]{SwgxrCombatMedic::run(&c,query);});}
 query=q;query["pose"]["tracked"]=false;rejects([&]{SwgxrCombatMedic::run(&c,query);});
 for(auto flag:{&c.dead,&c.incap,&p.dead}){*flag=true;rejects([&]{SwgxrCombatMedic::run(&c,q);});*flag=false;}
 p.hostile=false;rejects([&]{SwgxrCombatMedic::run(&c,q);});p.hostile=true;p.los=false;rejects([&]{SwgxrCombatMedic::run(&c,q);});p.los=true;
 p.ai=true;p.mask=ObjectFlag::NODOT;rejects([&]{SwgxrCombatMedic::run(&c,q);});p.mask=0;p.ai=false;
 query=q;query["target_id"]="1";rejects([&]{SwgxrCombatMedic::run(&c,query);});
 p.pos={0,0,34.1};rejects([&]{SwgxrCombatMedic::run(&c,q);});p.pos={0,0,34};check(SwgxrCombatMedic::run(&c,q)["success"]==true);p.pos={0,0,10};
 pack.count=0;rejects([&]{SwgxrCombatMedic::run(&c,q);});pack.count=3;pack.required=101;rejects([&]{SwgxrCombatMedic::run(&c,q);});pack.required=0;
 pack.attribute=3;rejects([&]{SwgxrCombatMedic::run(&c,q);});pack.attribute=0;pack.templ.path="object/tangible/medicine/crafted/medpack_poison_action_a.iff";rejects([&]{SwgxrCombatMedic::run(&c,q);});pack.templ.path="object/tangible/medicine/crafted/medpack_poison_health_a.iff";
 pack.type="disease";pack.attribute=3;rejects([&]{SwgxrCombatMedic::run(&c,q);});q["ability"]="applydisease";pack.templ.path="object/tangible/medicine/crafted/medpack_disease_action_a.iff";
 c.skills.erase("science_combatmedic_healing_range_02");rejects([&]{SwgxrCombatMedic::run(&c,q);});c.skills.insert("science_combatmedic_healing_range_02");
 c.skills.erase("science_combatmedic_novice");rejects([&]{SwgxrCombatMedic::run(&c,q);});c.skills.insert("science_combatmedic_novice");
 c.grants.erase("applydisease");rejects([&]{SwgxrCombatMedic::run(&c,q);});c.grants.insert("applydisease");
 SceneObject bag;bag.parent=&c.inventory;pack.parent=&bag;check(SwgxrCombatMedic::run(&c,q)["success"]==true);
 bag.crate=true;rejects([&]{SwgxrCombatMedic::run(&c,q);});bag.crate=false;bag.parent=&c;bag.wearable=true;check(SwgxrCombatMedic::run(&c,q)["success"]==true);bag.wearable=false;rejects([&]{SwgxrCombatMedic::run(&c,q);});pack.parent=&c.inventory;
 c.timers["corecu_combat_medicine"]={1000};rejects([&]{SwgxrCombatMedic::run(&c,q);});c.timers.clear();
 c.ham[3]=60;rejects([&]{SwgxrCombatMedic::run(&c,q);});c.ham[3]=1000;c.ham[6]=80;rejects([&]{SwgxrCombatMedic::run(&c,q);});c.ham[6]=1000;
 s.controller.commands["applydisease"].result=1;rejects([&]{SwgxrCombatMedic::run(&c,q);});
 std::cout<<"Combat Medic native bridge: "<<checks<<" checks passed\n";
}
