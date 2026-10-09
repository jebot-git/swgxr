#include "server/combat/CoreCuMedicalPolicy.h"
#include "server/medic/DoctorCarePolicy.h"
#include "server/medic/CombatMedicHealingPolicy.h"
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
struct Vector3 {double x,y,z;Vector3(double a=0,double b=0,double c=0):x(a),y(b),z(c){}double distanceTo(const Vector3& o)const{return std::sqrt((x-o.x)*(x-o.x)+(y-o.y)*(y-o.y)+(z-o.z)*(z-o.z));}};
struct CreatureObject;struct PharmaceuticalObject;struct Server;
struct Template {String path;String getFullTemplateString(){return path;}};
struct SceneObject {virtual ~SceneObject(){}uint64 id=0;SceneObject* parent=nullptr;Template templ;bool wearable=false,crate=false,crafting=false,schematic=false;String name="Treatment";
 uint64 getObjectID(){return id;}Ref<SceneObject*> getParent(){return {parent};}Template* getObjectTemplate(){return &templ;}String getDisplayedName(){return name;}bool isFactoryCrate(){return crate;}bool isCraftingTool(){return crafting;}bool isManufactureSchematic(){return schematic;}bool isWearableContainerObject(){return wearable;}
};
struct CreatureState {enum: uint64 {STUNNED=1,DIZZY=2,BLINDED=4,INTIMIDATED=8,ONFIRE=16,POISONED=32,DISEASED=64};static CreatureState* instance(){static CreatureState s;return &s;}String getName(uint64 n){return n==STUNNED?"stunned":n==DIZZY?"dizzy":n==BLINDED?"blinded":"intimidated";}};
struct CreatureAttribute {enum {ARRAYSIZE=9};static String getName(int){return "health";}};struct BuffAttribute {static String getName(int){return "health";}};
struct PharmaceuticalObject:SceneObject {String type="state";int count=3,required=0,attribute=0;uint64 state=1;float range=20;double effectiveness=300;double getEffectiveness(){return effectiveness;}int calculatePower(CreatureObject*,CreatureObject*,bool=true);
 bool isPetStimPack(){return type=="pet";}bool isDroidRepairKit(){return type=="repair";}bool isDroidReconstructionKit(){return type=="reconstruct";}bool isStimPack(){return type=="stim";}bool isRangedStimPack(){return type=="ranged";}bool isWoundPack(){return type=="wound";}bool isEnhancePack(){return type=="enhance";}bool isStatePack(){return type=="state";}bool isRevivePack(){return type=="revive";}bool isCurePack(){return type=="cure";}uint64 getState(){return state;}int getAttribute(){return attribute;}float getRange(){return range;}int getMedicineUseRequired(){return required;}int getUseCount(){return count;}
};
using StimPack=PharmaceuticalObject;using RangedStimPack=PharmaceuticalObject;using WoundPack=PharmaceuticalObject;using EnhancePack=PharmaceuticalObject;using CurePack=PharmaceuticalObject;using StatePack=PharmaceuticalObject;using RevivePack=PharmaceuticalObject;
struct Timer {int ms;int miliDifference(){return -ms;}};
struct BuffType {enum {JEDI};};
struct PrivateBuff {std::map<int,int> modifiers;int duration;PrivateBuff(CreatureObject*,int,int seconds,int):duration(seconds){}void setAttributeModifier(int i,int n){modifiers[i]=n;}};
struct Buff {int getSkillModifierValue(const char*){return 0;}};struct BuffCRC {enum{FOOD_HEAL_RECOVERY};};
struct Group {std::set<CreatureObject*> members;bool hasMember(CreatureObject* c){return members.count(c);}};
struct Command {String grant;int calls=0,result=0;String last;uint64 target=0;String getCharacterAbility(){return grant;}int doQueueCommand(CreatureObject*,uint64 t,const UnicodeString& q){calls++;last=q;target=t;return result;}};
struct Controller {std::map<std::string,Command> commands;Command* getQueueCommand(String name){return commands.count(name)?&commands.at(name):nullptr;}};
struct Server {Controller controller;int zone=0;std::map<uint64,SceneObject*> objects;Controller* getObjectController(){return &controller;}Ref<SceneObject*> getObject(uint64 id){return {objects.count(id)?objects.at(id):nullptr};}};
struct CreatureObject:SceneObject {std::map<std::string,String> screens;PrivateBuff* debuff=nullptr;void addBuff(PrivateBuff* b){debuff=b;}String getScreenPlayData(const char* a,const char* b){return screens[std::string(a)+b];}void setScreenPlayData(const char* a,const char* b,const String& v){screens[std::string(a)+b]=v;}Server* server=nullptr;SceneObject inventory;Vector3 pos;bool player=true,pet=false,droid=false,dead=false,incap=false,riding=false,hostile=false,healable=true,resuscitable=true,consent=false,los=true;uint64 states=0;int ham[9]={1000,300,300,1000,300,300,1000,300,300};int base[9]={1000,300,300,1000,300,300,1000,300,300};int wounds=0;float bf=1;Group* group=nullptr;std::map<std::string,int> mods;std::set<std::string> skills,grants;std::map<std::string,Timer> timers;
 SceneObject* getSlottedObject(const char*){return &inventory;}bool isPlayerCreature(){return player;}bool isPet(){return pet;}bool isCreature(){return !droid;}bool isDroidObject(){return droid;}bool isDead(){return dead;}bool isIncapacitated(){return incap;}bool isRidingMount(){return riding;}bool isAttackableBy(CreatureObject*){return hostile;}bool isHealableBy(CreatureObject*){return healable;}bool isResuscitable(){return resuscitable;}Group* getGroup(){return group;}int* getZone(){return &server->zone;}Server* getZoneServer(){return server;}CreatureObject* getPlayerObject(){return this;}String getFirstName(){return "doctor";}bool hasInConsentList(const String&){return consent;}bool hasSkill(const char* s){return skills.count(s);}bool hasAbility(const String& s){return grants.count(s);}bool hasState(uint64 s){return states&s;}int getSkillMod(const char* s){return mods[s];}int getHAM(int i){return ham[i];}int getBaseHAM(int i){return base[i];}int getMaxHAM(int i){return base[i];}int getWounds(int){return wounds;}float calculateBFRatio(){return bf;}bool hasDamage(int i){return ham[i]<base[i]-wounds;}Vector3 getWorldPosition(){return pos;}bool isInRange(CreatureObject* c,float range){return pos.distanceTo(c->pos)<=range;}Timer* getCooldownTime(const String& s){return timers.count(s)?&timers.at(s):nullptr;}void addCooldown(const String& s,int ms){timers[s]={ms};}Buff* getBuff(int){return nullptr;}void sendSystemMessage(const char*){}void inflictDamage(CreatureObject*,int p,int amount,bool){ham[p]-=amount;}
};
int PharmaceuticalObject::calculatePower(CreatureObject* c,CreatureObject* p,bool battle){double scale=(isPetStimPack() || isDroidRepairKit())?1.:1.+c->getSkillMod(isRangedStimPack()?"combat_medic_effectiveness":"healing_injury_treatment")/100.;return effectiveness*scale*(battle?p->calculateBFRatio():1.);}
struct SwgxrSpice {struct HamAdjustment{};static double cooldownScale(CreatureObject*){return 1.;}static bool active(CreatureObject*,const char*){return false;}};
struct Locker {template<class A>Locker(A){}template<class A,class B>Locker(A,B){}};
struct QueueCommand {enum{SUCCESS};};struct CollisionManager {static bool checkLineOfSight(CreatureObject*,CreatureObject* t){return t->los;}};
#include "doctor_medicine.inc"
#include "doctor_item.inc"
#include "doctor_bridge.inc"
#include "doctor_receipt.inc"
#include "doctor_revive.inc"
struct Math {static float getPrecision(float value,int digits){double scale=std::pow(10.,digits);return std::round(value*scale)/scale;}};
struct AttributeListMessage {std::map<std::string,std::string> attrs;void insertAttribute(const char* key,const String& value){attrs[key]=value;}void insertAttribute(const char* key,int value){attrs[key]=std::to_string(value);}};
#include "doctor_stim_examine.inc"
int main(){int checks=0;auto check=[&](bool ok){if(!ok)std::cerr<<"failed check "<<checks+1<<"\n";assert(ok);++checks;};auto rejects=[&](auto call){bool rejected=false;try{call();}catch(const std::exception&){rejected=true;}check(rejected);};
 Server s;CreatureObject c,p;c.server=p.server=&s;c.id=1;p.id=2;c.inventory.parent=&c;c.skills.insert("science_medic_novice");c.mods["healing_ability"]=100;c.mods["healing_injury_treatment"]=100;c.mods["healing_wound_treatment"]=100;p.pos={0,0,1};s.objects[1]=&c;s.objects[2]=&p;
 for(auto name:{"healstate","reviveplayer","extinguishfire"}){s.controller.commands[name].grant=name;c.grants.insert(name);}
 PharmaceuticalObject pack;pack.id=3;pack.parent=&c.inventory;s.objects[3]=&pack;
 SceneObject focus;focus.id=4;focus.parent=&c.inventory;focus.templ.path="object/tangible/medicine/medikit_tool_basic.iff";s.objects[4]=&focus;
 Json q={{"ability","healstate"},{"focus_id","4"},{"item_id","3"},{"target_id","2"},{"pose",{{"tracked",true},{"left",{0,1,0}},{"right",{0,1,0}}}}};p.states=CreatureState::STUNNED;
 q["request_id"]="doctor_test_001";
 int before=s.controller.commands["healstate"].calls;auto once=DoctorReceiptHarness::run(&c,q);auto again=DoctorReceiptHarness::run(&c,q);check(again["replayed"]==true && s.controller.commands["healstate"].calls==before+1);auto changed=q;changed["item_id"]="4";rejects([&]{DoctorReceiptHarness::run(&c,changed);});
 DoctorReviveHarness revival;revival.applyDebuff(&p);check(p.debuff->duration==60 && p.debuff->modifiers.size()==9 && p.debuff->modifiers[0]==-50 && p.debuff->modifiers[1]==-15);delete p.debuff;p.debuff=nullptr;
 auto out=SwgxrDoctor::run(&c,q);check(out["command"]=="healstate" && out["target_id"]=="2" && out["item_id"]=="3");check(s.controller.commands["healstate"].last=="stunned|3");
 auto query=q;query.erase("focus_id");rejects([&]{SwgxrDoctor::run(&c,query);});query=q;query["focus_id"]="3";rejects([&]{SwgxrDoctor::run(&c,query);});query=q;query["ability"]="quickheal";rejects([&]{SwgxrDoctor::run(&c,query);});
 for(auto field:{"item_id","target_id","focus_id"})for(auto invalid:{"","3junk","184467440737095516166"}){query=q;query[field]=invalid;rejects([&]{SwgxrDoctor::run(&c,query);});}
 focus.parent=nullptr;rejects([&]{SwgxrDoctor::run(&c,q);});focus.parent=&c.inventory;
 for(auto field:{"left","right"}){query=q;query["pose"][field]={0,3,0};rejects([&]{SwgxrDoctor::run(&c,query);});query["pose"][field]={0,0};rejects([&]{SwgxrDoctor::run(&c,query);});query["pose"][field]={0,"bad",0};rejects([&]{SwgxrDoctor::run(&c,query);});}
 query=q;query["pose"]["tracked"]=false;rejects([&]{SwgxrDoctor::run(&c,query);});
 pack.count=0;rejects([&]{SwgxrDoctor::run(&c,q);});pack.count=3;pack.required=101;rejects([&]{SwgxrDoctor::run(&c,q);});pack.required=0;pack.parent=nullptr;rejects([&]{SwgxrDoctor::run(&c,q);});pack.parent=&c.inventory;
 SceneObject crate;crate.parent=&c.inventory;crate.crate=true;pack.parent=&crate;rejects([&]{SwgxrDoctor::run(&c,q);});pack.parent=&c.inventory;
 c.skills.erase("science_medic_novice");rejects([&]{SwgxrDoctor::run(&c,q);});c.skills.insert("science_medic_novice");c.grants.erase("healstate");rejects([&]{SwgxrDoctor::run(&c,q);});c.grants.insert("healstate");
 for(auto flag:{&c.dead,&c.incap,&p.dead,&p.hostile,&p.riding}){*flag=true;rejects([&]{SwgxrDoctor::run(&c,q);});*flag=false;}
 p.healable=false;rejects([&]{SwgxrDoctor::run(&c,q);});p.healable=true;p.los=false;rejects([&]{SwgxrDoctor::run(&c,q);});p.los=true;p.pos={0,0,6.1};rejects([&]{SwgxrDoctor::run(&c,q);});p.pos={0,0,6};check(SwgxrDoctor::run(&c,q)["success"]==true);p.pos={0,0,1};
 p.states=CreatureState::DIZZY;rejects([&]{SwgxrDoctor::run(&c,q);});pack.state=CreatureState::DIZZY;check(SwgxrDoctor::run(&c,q)["success"]==true);pack.state=CreatureState::ONFIRE;p.states=pack.state;rejects([&]{SwgxrDoctor::run(&c,q);});pack.state=CreatureState::STUNNED;p.states=pack.state;
 c.timers["corecu_medical_cure"]={1000};rejects([&]{SwgxrDoctor::run(&c,q);});c.timers.clear();c.ham[3]=20;rejects([&]{SwgxrDoctor::run(&c,q);});c.ham[3]=1000;c.ham[6]=30;rejects([&]{SwgxrDoctor::run(&c,q);});c.ham[6]=1000;
 s.controller.commands["healstate"].result=1;rejects([&]{SwgxrDoctor::run(&c,q);});s.controller.commands["healstate"].result=0;
 // Fire uses its exact charged cure, requires contact and stays on the shared cure timer.
 pack.type="cure";pack.state=CreatureState::ONFIRE;p.states=pack.state;q["ability"]="extinguishfire";q.erase("focus_id");check(SwgxrDoctor::run(&c,q)["success"]==true);check(s.controller.commands["extinguishfire"].last=="3");
 p.pos={0,0,2.4};query=q;query["pose"]["left"]={0,0,-2};query["pose"]["right"]={0,0,-2};rejects([&]{SwgxrDoctor::run(&c,query);});p.pos={0,0,1};
 // Revival retains actual-player, dead, resuscitable and consent/group requirements.
 pack.type="revive";q["ability"]="reviveplayer";rejects([&]{SwgxrDoctor::run(&c,q);});p.dead=true;rejects([&]{SwgxrDoctor::run(&c,q);});p.consent=true;check(SwgxrDoctor::run(&c,q)["success"]==true);p.resuscitable=false;rejects([&]{SwgxrDoctor::run(&c,q);});p.resuscitable=true;p.consent=false;Group group;group.members.insert(&p);c.group=&group;check(SwgxrDoctor::run(&c,q)["success"]==true);p.player=false;p.pet=true;rejects([&]{SwgxrDoctor::run(&c,q);});p.player=true;p.pet=false;
 c.timers["corecu_medical_revive"]={1000};rejects([&]{SwgxrDoctor::run(&c,q);});c.timers.clear();p.pos={0,0,2.4};query=q;query["pose"]["right"]={0,0,-2};rejects([&]{SwgxrDoctor::run(&c,query);});p.pos={0,0,1};p.dead=false;
 pack.type="state";pack.state=CreatureState::STUNNED;p.states=pack.state;
 Json inventory={{"items",Json::array({{{"id","3"}},{{"id","4"}}})}};auto snap=SwgxrDoctor::snapshot(&c,inventory);check(snap["healstate"]["requires_medical_focus"]==true && snap["healstate"]["supplies"][0]["item_id"]=="3" && snap["healstate"]["supplies"][0]["state"]=="stunned");check(snap["reviveplayer"]["range_m"]==2.5 && snap["healstate"]["range_m"]==6.);pack.count=0;check(SwgxrDoctor::snapshot(&c,inventory)["healstate"]["supplies"].empty());pack.count=3;
 // Real production normalization retains Medic baselines, explicit progression,
 // battle fatigue and excludes ranged/area stims from Doctor's direct-care bonus.
 int injury=CoreCuMedicine::injury(&c,&p,600),tend=CoreCuMedicine::tend(&c,&p,30),quick=CoreCuMedicine::emergency(&c,&p,450),wound=CoreCuMedicine::woundPack(&c,&p,0,1.);
 check(injury==220 && tend==70 && quick==400 && wound==80);c.mods["healing_wound_treatment"]=10000;check(CoreCuMedicine::doctorStage(&c)==0);c.skills.insert("science_doctor_novice");
 for(int stage=1;stage<=5;++stage){check(CoreCuMedicine::doctorStage(&c)==stage);check(CoreCuMedicine::injury(&c,&p,600)==int(std::round(injury*(1.+stage*.05))));check(CoreCuMedicine::tend(&c,&p,30)==int(std::round(tend*(1.+stage*.05))));check(CoreCuMedicine::emergency(&c,&p,450)==int(std::round(quick*(1.+stage*.025))));check(CoreCuMedicine::woundPack(&c,&p,0,1.)==int(std::round(wound*(1.+stage*.1))));check(CoreCuMedicine::injury(&c,&p,600,false)==injury);if(stage<5)c.skills.insert(String("science_doctor_wound_0")+std::to_string(stage));}
 c.skills.insert("science_doctor_master");check(CoreCuMedicine::doctorStage(&c)==6 && CoreCuMedicine::woundPack(&c,&p,0,100)==150);p.bf=.5;check(CoreCuMedicine::injury(&c,&p,300)==143 && CoreCuMedicine::woundPack(&c,&p,0,100)==75);p.bf=1;p.player=false;check(CoreCuMedicine::injury(&c,&p,333)==333 && CoreCuMedicine::tend(&c,&p,30)==30);p.player=true;
 check(corecu::doctorcare::grogginess(300)==-15 && corecu::doctorcare::grogginess(3000)==-150);c.skills.erase("science_doctor_novice");check(CoreCuMedicine::doctorStage(&c)==0);CoreCuMedicine::commit(&c,"quickheal");check(c.timers["corecu_medical_emergency"].ms==30000 && c.timers["corecu_medical_injury"].ms==6000);check(CoreCuMedicine::remaining(&c,"healdamage")==6. && CoreCuMedicine::remaining(&c,"quickheal")==30.);
 // Exact production supply normalization, including original crafted tier boundaries.
 c.timers.clear();p.base[0]=3000;p.wounds=0;p.bf=1;c.skills.clear();c.skills.insert("science_medic_novice");c.mods["healing_injury_treatment"]=100;pack.type="stim";
 const double low[]={75,75,100,150,200},high[]={100,200,400,700,1000};
 int previous=0;
 for(int tier=0;tier<5;++tier){
  pack.templ.path=String("object/tangible/medicine/crafted/crafted_stimpack_sm_s1_")+char('a'+tier)+".iff";
  pack.effectiveness=low[tier];int minimum=CoreCuMedicine::stim(&c,&p,&pack);pack.effectiveness=high[tier];int maximum=CoreCuMedicine::stim(&c,&p,&pack);
  check(minimum==300+90*tier && maximum==420+90*tier && maximum>previous);previous=maximum;
  pack.effectiveness=(low[tier]+high[tier])*.5;check(CoreCuMedicine::stim(&c,&p,&pack)==360+90*tier);
  pack.effectiveness=high[tier]*10;check(CoreCuMedicine::stim(&c,&p,&pack)==maximum);pack.effectiveness=-1;check(CoreCuMedicine::stim(&c,&p,&pack)==minimum);
  pack.effectiveness=high[tier];c.mods["healing_injury_treatment"]=0;check(CoreCuMedicine::stim(&c,&p,&pack)==int(std::round(maximum*.75)));c.mods["healing_injury_treatment"]=100;
 }
 c.skills.insert("science_doctor_novice");pack.effectiveness=1000;check(CoreCuMedicine::stim(&c,&p,&pack)==819);
 for(auto skill:{"science_doctor_wound_01","science_doctor_wound_02","science_doctor_wound_03","science_doctor_wound_04"})c.skills.insert(skill);
 check(CoreCuMedicine::stim(&c,&p,&pack)==975);c.skills.insert("science_doctor_master");check(CoreCuMedicine::stim(&c,&p,&pack)==1014);check(CoreCuMedicine::emergency(&c,&p,450)==1380 && CoreCuMedicine::tend(&c,&p,30)==273);
 p.bf=.5;check(CoreCuMedicine::stim(&c,&p,&pack)==507 && CoreCuMedicine::stim(&c,&p,&pack,false)==1014);p.bf=1;
 p.wounds=600;check(CoreCuMedicine::stim(&c,&p,&pack)==811);p.wounds=0;
 auto status=SwgxrDoctor::snapshot(&c,inventory);check(status["healing_multiplier"]==1.3 && status["emergency_healing_multiplier"]==1.15 && status["wound_healing_multiplier"]==1.5);
 // No basename guessing: foreign directories, prototype suffixes and shared templates use legacy fallback.
 for(auto path:{"object/tangible/medicine/stimpack_sm_s1.iff","forged/crafted_stimpack_sm_s1_e.iff","object/tangible/medicine/crafted/crafted_stimpack_sm_s1_e_extra.iff","object/tangible/medicine/crafted/shared_crafted_stimpack_sm_s1_e.iff"}){
  pack.templ.path=path;pack.effectiveness=300;check(corecu::doctorcare::stimTier(path)==-1 && CoreCuMedicine::stim(&c,&p,&pack)==858);
 }
 // Ranged and area descendants retain old CM normalization without Doctor multiplier.
 pack.templ.path="object/tangible/medicine/crafted/crafted_stimpack_sm_s1_e.iff";pack.type="ranged";pack.effectiveness=1000;c.mods["combat_medic_effectiveness"]=100;
 check(CoreCuMedicine::stim(&c,&p,&pack)==825);p.bf=.5;check(CoreCuMedicine::stim(&c,&p,&pack)==412);p.bf=1;
 for(auto kind:{"pet","repair"}){pack.type=kind;pack.effectiveness=200;check(CoreCuMedicine::stim(&c,&p,&pack)==200);}
 check(CoreCuMedicine::cost(&c,"healdamage",3)==60 && CoreCuMedicine::cost(&c,"healdamage",6)==80);
 for(auto command:{"healpet","healdroiddamage"})check(CoreCuMedicine::cost(&c,command,3)==20 && CoreCuMedicine::cost(&c,command,6)==30);
 c.ham[3]=60;c.ham[6]=1000;check(!CoreCuMedicine::check(&c,"healdamage"));c.ham[3]=1000;c.ham[6]=80;check(!CoreCuMedicine::check(&c,"healdamage"));c.ham[6]=1000;
 CoreCuMedicine::commit(&c,"healdamage");check(c.ham[3]==940 && c.timers["corecu_medical_injury"].ms==6000 && !CoreCuMedicine::check(&c,"tenddamage"));
 // Repeated ordinary healing must exhaust Mind under standing combat regeneration,
 // including maximal Metabolic preparation, while supplies remain skill-gated.
 c.timers.clear();c.ham[3]=c.ham[6]=1000;double action=1000,mind=1000;int casts=0;
 while(action>60 && mind>80 && casts<100){action-=60;mind-=80;action=std::min(1000.,action+11.5*4.875);mind=std::min(1000.,mind+9.2*4.875);++casts;}
 check(casts>10 && casts<30 && mind<=80);
 pack.type="stim";pack.required=101;check(!SwgxrMedicalItem::trained(&c,&pack));pack.required=100;check(SwgxrMedicalItem::trained(&c,&pack));
 DoctorStimExamineHarness examined;examined.templ.path="object/tangible/medicine/crafted/crafted_stimpack_sm_s1_e.iff";examined.type="stim";examined.effectiveness=1000;c.base[0]=3000;c.mods["healing_injury_treatment"]=100;AttributeListMessage attributes;examined.describe(&attributes,&c);
 check(std::abs(std::stod(attributes.attrs["Treatment"])-33.8)<.001 && attributes.attrs["Healing preview"].find("1014 Health")!=std::string::npos && attributes.attrs["Healing preview"].find("before patient battle fatigue and spice effects")!=std::string::npos);
 std::cout<<"Doctor production native care: "<<checks<<" checks passed\n";
}
