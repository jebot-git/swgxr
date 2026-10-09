#include "server/combat/CoreCuPolicy.h"
#include "server/combat/CoreCuMedicalPolicy.h"
#include "server/combat/FencerPolicy.h"
#include "server/medic/CombatMedicPolicy.h"
#include <cassert>
#include <iostream>
#include <map>
#include <set>
#include <vector>
#include <sstream>
#include <functional>
using uint64=unsigned long long;using uint32=unsigned;using uint8=unsigned char;
constexpr unsigned hash(const char* p,unsigned h=0){return *p?hash(p+1,h*31+*p):h;}
#define STRING_HASHCODE(x) hash(x)
static long long now=0;
struct String:std::string{using std::string::string;String(){}String(const std::string&s):std::string(s){}const char*toCharArray()const{return c_str();}bool isEmpty()const{return empty();}String toString()const{return *this;}unsigned hashCode()const{return hash(c_str());}};
using UnicodeString=String;
struct StringBuffer{std::ostringstream out;StringBuffer&operator<<(const StringBuffer&x){out<<x.out.str();return *this;}template<class T>StringBuffer&operator<<(const T&x){out<<x;return *this;}String toString(){return out.str();}};
struct StringTokenizer{String text;bool read=false;StringTokenizer(String s):text(s){}void setDelimeter(const char*){}void getStringToken(String&out){out=text.substr(0,text.find('|'));read=true;}bool hasMoreTokens(){return text.find('|')!=std::string::npos;}uint64 getLongToken(){return std::stoull(text.substr(text.find('|')+1));}};
using Exception=std::exception;
template<class T>struct Ref{T value=nullptr;Ref(){}Ref(T p):value(p){}Ref&operator=(T p){value=p;return *this;}operator T()const{return value;}T get()const{return value;}T operator->()const{return value;}template<class U>Ref<U>castTo(){return {dynamic_cast<U>(value)};}};
template<class T>using ManagedReference=Ref<T>;
template<class T>using Reference=T;
template<class T,class U>T cast(U p){return dynamic_cast<T>(p);}
template<class T>struct SortedVector:std::vector<T>{using std::vector<T>::operator=;void removeAll(int,int){this->clear();}T get(int n){return this->at(n);}};
struct Vec{double x=0,y=0,z=0;double distanceTo(const Vec&o)const{return std::sqrt((x-o.x)*(x-o.x)+(y-o.y)*(y-o.y)+(z-o.z)*(z-o.z));}};
struct Time{long long value=now;void updateToCurrentTime(){value=now;}void addMiliTime(int n){value+=n;}bool isPast()const{return now>value;}int miliDifference()const{return int(now-value);}};
struct Math{template<class T>static T min(T a,T b){return std::min(a,b);}template<class T>static T max(T a,T b){return std::max(a,b);}};
struct CreatureAttribute{enum{HEALTH=0,ACTION=3,MIND=6,FOCUS=7,UNKNOWN=255};};
struct BuffAttribute{enum{UNKNOWN=255};static uint8 getAttribute(const String&s){return s=="health"?0:s=="action"?3:255;}};
struct CreatureState{enum:uint64{BLEEDING=1,POISONED=2,DISEASED=4,ONFIRE=8,SWIMMING=16};};
struct CommandEffect{enum{FORCECHOKE=32};};
struct ObjectFlag{enum{NODOT=1};};
struct ObserverEventType{enum{MEDPACKUSED};};
struct BuffCRC{enum{FOOD_HEAL_RECOVERY};};
struct Buff{int value=0;int getSkillModifierValue(const char*){return value;}};
struct CreatureObject;struct Zone;struct Server;
struct Template{String path="object/tangible/medicine/crafted/medpack_poison_health_c.iff";String getFullTemplateString(){return path;}};
struct SceneObject{virtual~SceneObject(){}uint64 id=0;SceneObject*parent=nullptr;Server*server=nullptr;Template objectTemplate;Vec pos;bool owned=true;std::vector<SceneObject*>contents;virtual bool isCreatureObject(){return false;}virtual bool isDotPackObject(){return false;}virtual CreatureObject*asCreatureObject(){return nullptr;}uint64 getObjectID(){return id;}Template*getObjectTemplate(){return &objectTemplate;}int getContainerObjectsSize(){return contents.size();}SceneObject*getContainerObject(int i){return contents.at(i);}Vec getWorldPosition(){return pos;}float getTemplateRadius(){return 0;}Server*getZoneServer(){return server;}};
using TreeEntry=SceneObject;
struct CloseObjectsVector{SortedVector<TreeEntry*>objects;int size(){return objects.size();}void safeCopyTo(SortedVector<TreeEntry*>&out){out=objects;}};
struct Zone{CloseObjectsVector close;void getInRangeObjects(float,float,float,int,SortedVector<TreeEntry*>*out,bool){*out=close.objects;}};
struct PlayerManager{void awardExperience(CreatureObject*,const String&,int,bool){}};
struct Server{std::map<uint64,SceneObject*>objects;Zone zone;PlayerManager players;Server*getZoneServer(){return this;}PlayerManager*getPlayerManager(){return &players;}Ref<SceneObject*>getObject(uint64 id){return {objects.count(id)?objects[id]:nullptr};}};
using ZoneProcessServer=Server;
struct ThreatMap{template<class...T>void addDamage(T...){}};
struct DotCall{uint64 type,key;int strength,pool,duration;float potency;int defense;};
struct CreatureObject:SceneObject{
 bool player=true,pet=false,ai=false,dead=false,incap=false,hostile=true,immune=false,los=true,entry=true,feign=false,delay=false,resistDot=false;uint64 states=0;int flags=0,shock=0,woundsApplied=0,damageApplied=0,defenders=0,observed=0;double rating=0;
 int base[9]={3000,300,300,1000,300,300,1000,300,300},ham[9]={3000,300,300,1000,300,300,1000,300,300};
 SceneObject inventory;std::map<std::string,int>mods;std::set<std::string>skills;std::map<std::string,Time>timers;std::vector<DotCall>calls;ThreatMap threat;Buff*food=nullptr;
 bool isCreatureObject()override{return true;}CreatureObject*asCreatureObject()override{return this;}CreatureObject*asAiAgent(){return this;}bool isPlayerCreature(){return player;}bool isPet(){return pet;}bool isAiAgent(){return ai;}bool isDead(){return dead;}bool isIncapacitated(){return incap;}bool isFeigningDeath(){return feign;}bool hasState(uint64 s){return states&s;}bool hasDotImmunity(uint64){return immune;}int getCreatureBitmask(){return flags;}Zone*getZone(){return &server->zone;}bool isAttackableBy(CreatureObject*){return hostile;}CreatureObject*getPlayerObject(){return this;}bool hasSkill(const char*s){return skills.count(s);}int getSkillMod(const char*s){return mods[s];}int getBaseHAM(int n){return base[n];}int getMaxHAM(int n){return base[n];}int getHAM(int n){return ham[n];}int getWounds(int){return 0;}SceneObject*getSlottedObject(const char*){return &inventory;}Time*getCooldownTime(const String&s){return timers.count(s)?&timers.at(s):nullptr;}void addCooldown(const String&s,int ms){timers[s].value=now+ms;}Buff*getBuff(int){return food;}float getPositionX(){return pos.x;}float getPositionY(){return pos.y;}float getPositionZ(){return pos.z;}CloseObjectsVector*getCloseObjects(){return &server->zone.close;}ThreatMap*getThreatMap(){return &threat;}void addDefender(CreatureObject*){++defenders;}template<class...T>void updateLastCombatActionTimestamp(T...){}template<class T>void sendSystemMessage(T){}template<class T>void broadcastMessage(T*p,bool){delete p;}void notifyObservers(int){++observed;}
 uint32 addDotState(CreatureObject*,uint64 type,uint64 key,int power,int pool,int duration,float potency,int defense){calls.push_back({type,key,power,pool,duration,potency,defense});return resistDot?0:power;}
 template<class...T>void inflictDamage(CreatureObject*,int pool,int amount,bool,T...){ham[pool]-=amount;damageApplied+=amount;}int getShockWounds(){return shock;}void addShockWounds(int n){shock+=n;}void addWounds(int,int n,bool,bool){woundsApplied+=n;}bool hasAttackDelay(){return delay;}void removeAttackDelay(){delay=false;}void playEffect(const char*,const char*){}template<class...T>void showFlyText(T...){}
};
using AiAgent=CreatureObject;using PlayerObject=CreatureObject;
struct DotPack:SceneObject{bool disease=false,areaFlag=false;int count=5,required=5,pool=0;float rawRange=30,area=0,potency=150,power=300;int rawDuration=240;bool isDotPackObject()override{return true;}bool isPoisonDeliveryUnit(){return !disease;}bool isDiseaseDeliveryUnit(){return disease;}int getUseCount(){return count;}int getMedicineUseRequired(){return required;}int getPool(){return pool;}uint64 getDotType(){return disease?CreatureState::DISEASED:CreatureState::POISONED;}float getRange(){return rawRange;}float getArea(){return area;}int getDuration(){return rawDuration;}float getPotency(){return potency;}float getEffectiveness(){return power;}bool isArea(){return areaFlag;}void decreaseUseCount(){--count;}};
struct SwgxrMedicalItem{static bool owned(CreatureObject*c,DotPack*p){return p && p->owned && p->parent==&c->inventory;}};
struct SwgxrSpice{struct HamAdjustment{};static double cooldownScale(CreatureObject*){return 1;}};
struct CollisionManager{static bool checkLineOfSight(CreatureObject*,CreatureObject*t){return t->los;}};
struct CoreCuCombat{static int rawModifier(CreatureObject*c,const char*n){return c->getSkillMod(n);}static int dotIndex(uint64){return 0;}static double rating(CreatureObject*c,int,int){return c->rating;}};
struct Locker{template<class...T>Locker(T...){}void release(){}};
struct StringIdChatParameter{StringIdChatParameter(const char*,const char*){}void setTT(uint64){}void setTU(uint64){}};
struct CombatAction{template<class...T>CombatAction(T...){}};
struct CombatManager{static CombatManager*instance(){static CombatManager c;return &c;}template<class...T>void checkForTefs(T...){} };
struct QueueCommand{enum{SUCCESS,GENERALERROR,INSUFFICIENTHAM,INVALIDTARGET,TOOFAR};Server*server;String name;float defaultTime=6;QueueCommand(const String&n,Server*s):server(s),name(n){}int doCommonMedicalCommandChecks(CreatureObject*c)const{return c->dead||c->incap?GENERALERROR:SUCCESS;}bool playerEntryCheck(CreatureObject*,CreatureObject*t)const{return t->entry;}bool checkDistance(CreatureObject*c,CreatureObject*t,double range)const{return c->pos.distanceTo(t->pos)<=range;}};
#include "cm_effects.inc"
#include "cm_command.inc"
struct Command:DotPackCommand{Command(const char*n,Server*s):DotPackCommand(n,s){skillName=n;}};
struct Tasks{template<class F>void executeTask(F f,const char*){f();}};
struct Core{static Tasks*getTaskManager(){static Tasks t;return &t;}};
struct System{static int roll;static int random(int){return roll;}};int System::roll=0;
class DamageOverTime{public:uint64 attackerID=1,type=CreatureState::POISONED;int strength=360,attribute=0,duration=21,secondaryStrength=0,intervalSeconds=0,remainingBudget=-1,medicalMode=0;Time nextTick,expires;
#include "cm_configure.inc"
 uint32 applyDot(CreatureObject*);uint32 initDot(CreatureObject*,CreatureObject*);uint32 doPoisonTick(CreatureObject*,CreatureObject*);uint32 doDiseaseTick(CreatureObject*,CreatureObject*);float reduceTick(float);void expireTick(){expires.value=now;}uint32 doBleedingTick(CreatureObject*,CreatureObject*){return 0;}uint32 doFireTick(CreatureObject*,CreatureObject*){return 0;}uint32 doForceChokeTick(CreatureObject*,CreatureObject*){return 0;}
};
#include "cm_ticks.inc"
#include "cm_entry.inc"

int main(){int checks=0;auto check=[&](bool x){if(!x)std::cerr<<"CM check failed: "<<checks+1<<"\n";assert(x);++checks;};auto close=[](double a,double b){return std::abs(a-b)<1e-7;};using namespace corecu::combatmedic;
 Server s;CreatureObject c,t;c.id=1;t.id=2;c.server=t.server=&s;c.inventory.parent=&c;t.pos.z=20;s.objects[1]=&c;s.objects[2]=&t;c.skills={"science_combatmedic_novice","science_combatmedic_healing_range_02"};for(auto m:{"combat_healing_ability","combat_medic_effectiveness","healing_range","healing_range_speed"})c.mods[m]=100;
 DotPack p;p.id=3;p.parent=&c.inventory;p.server=&s;s.objects[3]=&p;c.inventory.contents={&p};Command poison("applypoison",&s),disease("applydisease",&s);
 auto reset=[&](){c.ham[3]=c.ham[6]=1000;c.timers.clear();p.count=5;t.calls.clear();c.observed=0;t.immune=false;t.flags=0;t.ai=false;t.dead=false;t.los=true;t.entry=true;t.hostile=true;t.resistDot=false;};
 check(close(rawPotency(100,1),125) && close(chance(125,125),125*150./275));check(chance(125,90)<chance(125,65));check(chance(125,125)<chance(125,100));
 for(double r:{0.,40.,65.,90.,100.,125.,150.})for(double raw:{95.,100.,110.,125.,500.})check(chance(raw,r)>=0 && chance(raw,r)<=95);
 check(duration(false,5,240)==16 && duration(false,100,240)==21 && duration(true,5,1000)==18 && duration(true,100,1000)==24);check(recovery(5)==8000 && recovery(100)==6000 && recovery(100,20)==4800);
 check(close(SwgxrCombatMedicEffects::range(&c,&p),44));c.mods["healing_range"]=50;check(close(SwgxrCombatMedicEffects::range(&c,&p),37));c.mods["healing_range"]=100;p.rawRange=1e9;check(SwgxrCombatMedicEffects::range(&c,&p)==54);p.rawRange=30;
 check(duration(false,100,30)==17 && duration(true,100,120)==19 && poisonBudget(3000,3000,100,300,false,30)==281);
 for(double raw:{-100.,0.,30.,120.,240.,1000.,1e9}){check(durationQuality(false,raw)>=.75 && durationQuality(false,raw)<=1);check(poisonBudget(3000,3000,100,300,false,raw)<=360);}
 check(poisonBudget(3000,3000,100,300,false)==360 && poisonBudget(999999,3000,100,300,false)==1440 && poisonBudget(3000,3000,100,300,true)==270);check(diseasePulse(1000,100,60,false)==50 && diseasePulse(1000,5,60,false)==30 && diseasePulse(1000,100,60,true)==37);
 check(poison.doQueueCommand(&c,2,"health|3")==QueueCommand::SUCCESS);check(p.count==4 && c.ham[3]==940 && c.ham[6]==920 && c.observed==1);check(t.calls.size()==1 && t.calls[0].key==STRING_HASHCODE("swgxr_cm_poison") && t.calls[0].strength==360 && t.calls[0].duration==21 && t.calls[0].potency==125);check(poison.doQueueCommand(&c,2,"health|3")!=QueueCommand::SUCCESS && p.count==4);
 reset();t.resistDot=true;check(poison.doQueueCommand(&c,2,"health|3")==QueueCommand::SUCCESS && p.count==4 && c.ham[3]==940 && c.ham[6]==920 && t.calls.size()==1);
 reset();check(disease.doQueueCommand(&c,2,"action|3")!=QueueCommand::SUCCESS && p.count==5 && c.ham[6]==1000);
 for(int scenario=0;scenario<12;++scenario){reset();p.owned=true;p.required=5;p.pool=0;p.disease=false;p.objectTemplate.path="object/tangible/medicine/crafted/medpack_poison_health_c.iff";switch(scenario){case 0:p.count=0;break;case 1:p.owned=false;break;case 2:p.required=101;break;case 3:p.pool=3;break;case 4:t.immune=true;break;case 5:t.ai=true;t.flags=ObjectFlag::NODOT;break;case 6:t.dead=true;break;case 7:t.los=false;break;case 8:t.entry=false;break;case 9:t.hostile=false;break;case 10:c.ham[3]=60;break;case 11:p.objectTemplate.path="object/tangible/medicine/crafted/medpack_poison_mind_a.iff";break;}int count=p.count;check(poison.doQueueCommand(&c,2,"health|3")!=QueueCommand::SUCCESS && p.count==count && t.calls.empty());}
 reset();p.owned=true;p.required=5;p.pool=0;p.objectTemplate.path="object/tangible/medicine/crafted/medpack_poison_health_c.iff";c.skills.clear();check(poison.doQueueCommand(&c,2,"health|3")!=QueueCommand::SUCCESS);c.skills.insert("science_combatmedic_novice");p.disease=true;p.pool=3;p.power=60;p.rawDuration=1000;p.objectTemplate.path="object/tangible/medicine/crafted/medpack_disease_action_c.iff";check(disease.doQueueCommand(&c,2,"action|3")!=QueueCommand::SUCCESS);c.skills.insert("science_combatmedic_healing_range_02");check(disease.doQueueCommand(&c,2,"action|3")==QueueCommand::SUCCESS && t.calls[0].key==STRING_HASHCODE("swgxr_cm_disease") && t.calls[0].strength==50);check(poison.doQueueCommand(&c,2,"health|3")!=QueueCommand::SUCCESS);
 // Production area loop counts primary plus five eligible attempts, regardless of tier/area radius.
 reset();p.disease=false;p.pool=0;p.power=300;p.rawDuration=240;p.objectTemplate.path="object/tangible/medicine/crafted/medpack_poison_area_health_c.iff";p.area=40;p.areaFlag=true;std::vector<CreatureObject> others(12);s.zone.close.objects={&c,&t};for(int i=0;i<12;++i){auto&v=others[i];v.server=&s;v.id=10+i;v.pos.z=21;s.zone.close.objects.push_back(&v);}others[0].immune=true;others[1].ai=true;others[1].flags=ObjectFlag::NODOT;
 check(SwgxrCombatMedicEffects::radius(&p)==8);check(poison.doQueueCommand(&c,2,"health|3")==QueueCommand::SUCCESS);int targets=t.calls.size();for(auto&v:others)targets+=v.calls.size();check(targets==6 && others[0].calls.empty() && others[1].calls.empty() && p.count==4 && c.ham[3]==940);p.areaFlag=false;check(SwgxrCombatMedicEffects::radius(&p)==0);
 // Actual shared entry preserves generic chance while CM applies its learned potency once.
 t.rating=125;System::roll=60;check(dotEntry(&t,CreatureState::POISONED,21,125,0,360,STRING_HASHCODE("swgxr_cm_poison"))==12);check(dotEntry(&t,CreatureState::POISONED,21,125,0,360,12345)==0);System::roll=69;check(dotEntry(&t,CreatureState::POISONED,21,125,0,360,STRING_HASHCODE("swgxr_cm_poison"))==0);System::roll=0;
 // Execute production configure/init/apply/tick/expiry with per-cast remaining budget.
 auto runPoison=[&](int authored,int budget,int shortened,int absorption){now=0;t.ham[0]=3000;t.damageApplied=0;t.states=CreatureState::POISONED;t.mods["absorption_poison"]=absorption;DamageOverTime d;d.strength=budget;d.duration=shortened;d.expires.value=shortened*1000;d.configureCombatMedic(false,authored);d.initDot(&t,&c);int pulses=0;for(now=0;now<=long(shortened+8)*1000;now+=100){int before=t.damageApplied;d.applyDot(&t);if(t.damageApplied>before)++pulses;}return std::pair<int,int>{t.damageApplied,pulses};};
 for(int budget:{1,2,3,7,239,240,359,360,361})for(int seconds:{16,21}){auto result=runPoison(seconds,budget,seconds,0);check(result.first==budget && result.second<=pulseCount(seconds,4));}
 auto full=runPoison(21,360,21,0);auto resisted=runPoison(21,360,12,0);auto absorbed=runPoison(21,360,12,10);check(full.first==360 && full.second==5 && resisted.first==216 && absorbed.first==192);
 now=0;t.states=CreatureState::POISONED;DamageOverTime reduced;reduced.strength=360;reduced.duration=21;reduced.expires.value=21000;reduced.configureCombatMedic(false,21);check(reduced.strength==72 && reduced.remainingBudget==360);reduced.reduceTick(36);check(reduced.strength==36 && reduced.remainingBudget==180);reduced.reduceTick(100);check(reduced.strength==0 && reduced.remainingBudget==0);
 // CM disease is temporary Action loss for NPCs too; generic NPC disease keeps legacy wounds.
 for(bool npc:{false,true}){now=0;t.player=!npc;t.ai=npc;t.pet=false;t.ham[3]=1000;t.damageApplied=t.woundsApplied=t.shock=0;t.mods["absorption_disease"]=10;t.states=CreatureState::DISEASED;DamageOverTime d;d.type=CreatureState::DISEASED;d.attribute=3;d.strength=50;d.duration=24;d.expires.value=24000;d.configureCombatMedic(true,24);d.initDot(&t,&c);for(now=0;now<=28000;now+=100)d.applyDot(&t);check(t.ham[3]==640 && t.woundsApplied==0 && t.shock==0);}
 t.player=false;t.ai=true;t.mods["absorption_disease"]=0;t.ham[3]=1000;t.woundsApplied=0;DamageOverTime generic;generic.type=CreatureState::DISEASED;generic.attribute=3;generic.strength=50;check(generic.doDiseaseTick(&t,&c)==10 && t.woundsApplied==10);generic.configureCombatMedic(true,24);t.ham[3]=20;t.woundsApplied=0;check(generic.doDiseaseTick(&t,&c)==19 && t.ham[3]==1 && t.woundsApplied==0);
 std::cout<<"Combat Medic production command and lifecycle: "<<checks<<" checks passed\n";
}
