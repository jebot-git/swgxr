#include "server/combat/CoreCuMedicalPolicy.h"
#include "server/medic/DoctorCarePolicy.h"
#include "server/medic/CombatMedicHealingPolicy.h"
#include <cassert>
#include <cmath>
#include <iostream>
#include <map>
#include <set>
#include <vector>
#include <sstream>
using uint64=unsigned long long;
struct String:std::string {using std::string::string;String(const std::string& v):std::string(v){}String(){}const char* toCharArray()const{return c_str();}template<class T>static String valueOf(T v){return std::to_string(v);}};
using UnicodeString=String;
struct StringBuffer:std::ostringstream {String toString(){return str();}};
struct StringIdChatParameter {StringIdChatParameter(const char*,const char*){}void setTT(uint64){}};
template<class T>struct ManagedReference {T value=nullptr;ManagedReference(){}ManagedReference(T v):value(v){}T get()const{return value;}T operator->()const{return value;}operator T()const{return value;}ManagedReference& operator=(T v){value=v;return *this;}};
template<class T,class U>T cast(U value){return dynamic_cast<T>(value);}
template<class T>struct SortedVector:std::vector<T> {T get(int i){return this->at(i);}};
struct CreatureObject;struct CloseObjectsVector;
struct Vector3 {double x=0,y=0,z=0;double distanceTo(const Vector3& o)const{return std::hypot(std::hypot(x-o.x,y-o.y),z-o.z);}};
struct SceneObject {virtual ~SceneObject(){}uint64 id=0;virtual bool isCreatureObject(){return false;}virtual bool isAttackableBy(CreatureObject*){return false;}virtual CreatureObject* asCreatureObject(){return nullptr;}uint64 getObjectID(){return id;}};
using TangibleObject=SceneObject;using TreeEntry=SceneObject;
struct CloseObjectsVector {enum{CREOTYPE};std::vector<SceneObject*> objects;void safeCopyReceiversTo(SortedVector<TreeEntry*>& out,int){out.assign(objects.begin(),objects.end());}};
struct PlayerManager {void sendBattleFatigueMessage(CreatureObject*,CreatureObject*){}};
struct Server {std::map<uint64,SceneObject*> objects;int zone;PlayerManager manager;Server* getZoneServer(){return this;}ManagedReference<SceneObject*> getObject(uint64 id){return objects.count(id)?objects.at(id):nullptr;}PlayerManager* getPlayerManager(){return &manager;}};
struct CreatureAttribute {enum {HEALTH=0,ACTION=3,MIND=6};};
struct Timer {int ms;int miliDifference(){return -ms;}};
struct Buff {int getSkillModifierValue(const char*){return 0;}};
struct BuffCRC {enum{FOOD_HEAL_RECOVERY};};
struct CreatureObject:SceneObject {
 Server* server=nullptr;CloseObjectsVector nearby;Vector3 pos;int zone=0,ham[9]={3000,0,0,1000,0,0,1000},max[9]={3000,0,0,1000,0,0,1000};
 int wounds=0;float bf=1;bool player=true,pet=false,droid=false,dead=false,riding=false,hostile=false,healable=true,los=true,entry=true,duel=false,boost=false,withdraw=false,pinned=false;
 std::map<std::string,int> mods;std::set<std::string> skills;std::map<std::string,Timer> timers;
 bool isCreatureObject(){return true;}CreatureObject* asCreatureObject(){return this;}bool isPlayerCreature(){return player;}bool isPet(){return pet;}bool isAiAgent(){return !player;}bool isDroidObject(){return droid;}bool isDead(){return dead;}bool isRidingMount(){return riding;}
 bool isAttackableBy(CreatureObject*){return hostile;}bool isHealableBy(CreatureObject*){return healable && !hostile;}bool hasSkill(const char* key){return skills.count(key);}int getSkillMod(const char* key){return mods[key];}int getHAM(int pool){return ham[pool];}int getMaxHAM(int pool){return max[pool];}int getBaseHAM(int pool){return max[pool];}int getWounds(int){return wounds;}float calculateBFRatio(){return bf;}
 bool hasDamage(int pool){return ham[pool]<max[pool]-wounds;}void setHAM(int pool,int value,bool){ham[pool]=pinned?1:value;}void inflictDamage(CreatureObject*,int pool,int amount,bool){ham[pool]=std::max(1,ham[pool]-amount);}void sendSystemMessage(const String&){}void sendSystemMessage(const StringIdChatParameter&){}String getDisplayedName(){return "patient";}
 Timer* getCooldownTime(const String& name){return timers.count(name)?&timers.at(name):nullptr;}void addCooldown(const String& name,int ms){timers[name]={ms};}Buff* getBuff(int){return nullptr;}
 int* getZone(){return zone<0?nullptr:&server->zone;}Vector3 getWorldPosition(){return pos;}double getDistanceTo(CreatureObject* other){return pos.distanceTo(other->pos);}double getTemplateRadius(){return 0;}CloseObjectsVector* getCloseObjects(){return &nearby;}
 int healDamage(CreatureObject* healer,int pool,int input){
  if(pinned){ham[pool]=1;return 0;}int amount=healer->boost?corecu::medicine::spiceHealing(input):input;int actual=std::max(0,std::min(amount,max[pool]-wounds-ham[pool]));
  if(healer->withdraw){ham[0]-=actual;return actual;}ham[pool]+=actual;return actual;
 }
};
struct Template {String path;String getFullTemplateString(){return path;}};
struct StimPack {Template templ;double effectiveness=100,range=20;bool ranged=true;Template* getObjectTemplate(){return &templ;}bool isPetStimPack(){return false;}bool isDroidRepairKit(){return false;}bool isRangedStimPack(){return ranged;}double getEffectiveness(){return effectiveness;}double getRange(){return range;}int calculatePower(CreatureObject* healer,CreatureObject* patient,bool fatigue=true){return int(effectiveness*(1+healer->getSkillMod("combat_medic_effectiveness")/100.)*(fatigue?patient->bf:1.));}};
struct SwgxrSpice {struct HamAdjustment{};static double cooldownScale(CreatureObject*){return 1.;}static bool active(CreatureObject* c,const char*){return c->boost;}};
struct SwgxrVitalFeedback {struct MedicalAction{};};
struct Locker {template<class A,class B>Locker(A,B){}};
struct CollisionManager {static bool checkLineOfSight(CreatureObject*,CreatureObject* target){return target->los;}};
struct QueueCommand {
 enum{SUCCESS,GENERALERROR,TOOFAR};Server* server;String name="healmind";float range=5;
 int doCommonMedicalCommandChecks(CreatureObject*)const{return SUCCESS;}bool checkForArenaDuel(CreatureObject* target)const{return target->duel;}
 bool checkDistance(CreatureObject* a,CreatureObject* b,float limit)const{return a->getDistanceTo(b)<=limit;}bool playerEntryCheck(CreatureObject*,CreatureObject* target)const{return target->entry;}
 void sendHealMessage(CreatureObject*,CreatureObject*,int)const{}void doAnimations(CreatureObject*,CreatureObject*)const{}void checkForTef(CreatureObject*,CreatureObject*)const{}
};
#include "cm_medicine.inc"
#include "cm_mind.inc"
#include "cm_area.inc"

int main(){
 using namespace corecu::combatmedichealing;
 int checks=0;auto check=[&](bool ok){if(!ok)std::cerr<<"failed check "<<checks+1<<"\n";assert(ok);++checks;};
 Server server;CreatureObject healer,patient;healer.server=patient.server=&server;healer.id=1;patient.id=2;patient.pos.z=1;server.objects[1]=&healer;server.objects[2]=&patient;
 healer.mods["combat_medic_effectiveness"]=100;healer.mods["healing_injury_treatment"]=0;
 StimPack pack;
 const double low[]={75,75,100,150,200},high[]={150,300,500,700,1000};
 for(bool area:{false,true})for(int tier=0;tier<(area?3:5);++tier){
  pack.templ.path=String("object/tangible/medicine/crafted/medpack_grenade_")+(area?"area_":"damage_")+char('a'+tier)+".iff";
  auto spec=stim(pack.templ.path);check(spec.tier==tier && spec.area==area);
  double lo=area?100:low[tier],hi=area?300+200*tier:high[tier];int minimum=area?180+60*tier:300+90*tier,maximum=area?240+60*tier:420+90*tier;
  for(double q:{0.,.25,.5,.75,1.}){
   pack.effectiveness=lo+(hi-lo)*q;int expected=int(std::round(minimum+(maximum-minimum)*q));
   check(CoreCuMedicine::stim(&healer,&patient,&pack)==expected);
   patient.bf=.5;check(CoreCuMedicine::stim(&healer,&patient,&pack)==int(expected*.5));check(CoreCuMedicine::stim(&healer,&patient,&pack,false)==expected);patient.bf=1;
   healer.skills={"science_doctor_novice","science_doctor_master"};healer.mods["healing_injury_treatment"]=100;check(CoreCuMedicine::stim(&healer,&patient,&pack)==expected);
   healer.skills.clear();healer.mods["combat_medic_effectiveness"]=0;check(CoreCuMedicine::stim(&healer,&patient,&pack)==int(std::round(expected*.75)));healer.mods["combat_medic_effectiveness"]=100;
  }
  pack.effectiveness=hi*100;check(CoreCuMedicine::stim(&healer,&patient,&pack)==maximum);pack.effectiveness=-1;check(CoreCuMedicine::stim(&healer,&patient,&pack)==minimum);
 }
 check(stim("forged/medpack_grenade_area_a.iff").tier==-1 && stim("object/tangible/medicine/crafted/medpack_grenade_area_d.iff").tier==-1);
 check(CoreCuMedicine::cost(&healer,"healmind",6)==0 && CoreCuMedicine::cost(&healer,"healmind",3)==60);
 // Execute the full native HealMind command: actual gains equal actual costs,
 // including overdose boost, misleading withdrawal return values and overheal.
 MindHarness mind;mind.server=&server;
 for(bool boost:{false,true})for(bool withdrawal:{false,true})for(int reserve:{1,2,3,100,1000})for(int missing:{1,2,50,999}){
  healer.boost=boost;healer.withdraw=withdrawal;healer.ham[6]=reserve;healer.ham[3]=1000;healer.timers.clear();patient.ham[6]=1000-missing;patient.ham[0]=3000;
  int before=patient.ham[6],total=before+reserve;int result=mind.doQueueCommand(&healer,2,"");
  int gained=patient.ham[6]-before;check(gained>=0 && gained<=220 && healer.ham[6]>=1 && healer.ham[6]+patient.ham[6]==total);
  if(result==QueueCommand::SUCCESS)check(healer.ham[3]==940 && healer.timers["corecu_medical_resource"].ms==15000);
  if(withdrawal)check(gained==0);
 }
 healer.boost=healer.withdraw=false;healer.ham[6]=1000;healer.ham[3]=1000;healer.timers.clear();patient.ham[6]=100;patient.bf=.5;
 check(mind.doQueueCommand(&healer,2,"")==QueueCommand::SUCCESS && patient.ham[6]==210 && healer.ham[6]==890);patient.bf=1;
 for(auto flag:{&patient.dead,&patient.droid,&patient.hostile,&patient.duel}){healer.timers.clear();healer.ham[3]=1000;*flag=true;check(mind.doQueueCommand(&healer,2,"")==QueueCommand::GENERALERROR);*flag=false;}
 for(auto flag:{&patient.los,&patient.healable,&patient.entry}){healer.timers.clear();*flag=false;check(mind.doQueueCommand(&healer,2,"")==QueueCommand::GENERALERROR);*flag=true;}
 healer.timers.clear();patient.pos.z=5.01;check(mind.doQueueCommand(&healer,2,"")==QueueCommand::TOOFAR);patient.pos.z=1;
 check(mind.doQueueCommand(&healer,1,"")==QueueCommand::GENERALERROR);
 patient.pinned=true;patient.ham[6]=1;healer.ham[6]=1000;healer.ham[3]=1000;healer.timers.clear();check(mind.doQueueCommand(&healer,2,"")==QueueCommand::SUCCESS && healer.ham[6]==1000 && patient.ham[6]==1);patient.pinned=false;
 // Execute actual area selection against an intentionally scrambled candidate
 // set. The primary occupies one slot; blocked/healthy/hostile targets do not.
 AreaHarness area;area.server=&server;std::vector<CreatureObject> actors(10);patient.nearby.objects.clear();patient.pos={0,0,0};
 for(int i=9;i>=0;--i){auto& p=actors[i];p.server=&server;p.id=10+i;p.pos.z=1+(i/2);p.ham[0]=1000;patient.nearby.objects.push_back(&p);}
 actors[0].los=false;actors[1].hostile=true;actors[2].ham[0]=3000;actors[3].dead=true;actors[4].healable=false;
 pack.templ.path="object/tangible/medicine/crafted/medpack_grenade_area_c.iff";pack.effectiveness=700;area.handleArea(&healer,&patient,&pack,20);
 check(area.treated==std::vector<uint64>({15,16,17,18}));check(actors[5].ham[0]==1360 && actors[9].ham[0]==1000);
 area.treated.clear();area.handleArea(&healer,&patient,&pack,2);check(area.treated.empty());
 check(corecu::medicine::ability("healdamage").action==.06 && corecu::medicine::ability("healdamage").mind==.08);
 std::cout<<checks<<" CM tier/proficiency/BF/Doctor isolation, native Mind conservation and area selection checks passed\n";
}
