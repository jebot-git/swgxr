#include <chrono>
#include <fstream>
#include "server/combat/BountyHunterPolicy.h"
#include "server/combat/VolleyFirePolicy.h"
#include "server/combat/CommandoPolicy.h"
#include "server/combat/PistoleerPolicy.h"
#include "server/combat/RiflemanPolicy.h"
#include "server/combat/CarbineerPolicy.h"
#include "server/combat/MarksmanPolicy.h"
#include "server/combat/CoreCuPolicy.h"
#include "server/combat/WarcryPolicy.h"
#include "server/combat/ProjectileContactPolicy.h"
#include <nlohmann/json.hpp>
#include <cassert>
#include <iostream>
#include <map>
#include <set>
#include <vector>
using JSONSerializationType=nlohmann::json;using Json=JSONSerializationType;using uint64=unsigned long long;struct String:std::string {using std::string::string;String()=default;String(const std::string& s):std::string(s){}bool isEmpty()const{return empty();}const char* toCharArray()const{return c_str();}};
constexpr unsigned hash(const char* p,unsigned h=0){return *p?hash(p+1,h*31+*p):h;}
#define STRING_HASHCODE(s) hash(s)
struct CommandEffect {enum{INTIMIDATE,KNOCKDOWN,STUN,NEXTATTACKDELAY,BLIND};};struct BuffType {enum{STATE};};struct QueueCommand {enum{SUCCESS};};
struct CreatureObject;using AiAgent=CreatureObject;using SceneObject=CreatureObject;using TreeEntry=CreatureObject;
template<class T>using ManagedReference=T;
struct Locker {template<class A>Locker(A){}template<class A,class B>Locker(A,B){}};
struct CreaturePosture{enum{UPRIGHT,KNOCKEDDOWN};};
struct Vec {double x=0,z=0,y=0;double getX()const{return x;}double getY()const{return y;}double getZ()const{return z;}};
struct Buff {unsigned key;int seconds;std::map<std::string,int> mods;Buff(CreatureObject*,unsigned id,int duration,int):key(id),seconds(duration){}void setSkillModifier(const char* k,int v){mods[k]=v;}float getTimeLeft(){return seconds;}int getSkillModifierValue(const char* key){return mods[key];}};
struct Timer {int ms=0;int miliDifference(){return -ms;}};
struct WeaponTemplate {std::string path="object/weapon/ranged/pistol/pistol_dl44.iff";struct Name {std::string value;const char* toCharArray(){return value.c_str();}};Name getFullTemplateString(){return {path};}};
struct Weapon {WeaponTemplate templ;WeaponTemplate* getObjectTemplate(){return &templ;}bool flame=false;bool isFlameThrower(){return flame;}bool pistol=false,carbine=true,cert=true,broken=false,owned=true;uint64 id=55;double damage=100,range=32;
 bool isCarbineWeapon(){return carbine;}bool lightning=false;bool isLightningRifle(){return lightning;}unsigned getServerObjectCRC(){return hash(templ.path.c_str());}bool isPistolWeapon(){return pistol;}bool isRangedWeapon(){return true;}bool isCertifiedFor(CreatureObject*){return cert;}bool isBroken(){return broken;}bool isASubChildOf(CreatureObject*){return owned;}uint64 getObjectID(){return id;}
 int getWeaponBitmask(){return 1;}double getMaxRange(){return range;}double getPointBlankRange(){return 0;}double getIdealRange(){return 16;}double getPointBlankAccuracy(){return 0;}double getIdealAccuracy(){return 0;}double getMaxRangeAccuracy(){return 0;}int getDamageType(){return 1;}int getArmorPiercing(){return 0;}double getMinDamage(){return damage;}double getMaxDamage(){return damage;}
};
using WeaponObject=Weapon;
struct ObjectRef {CreatureObject* value=nullptr;Weapon* weapon=nullptr;CreatureObject* operator->()const{return value;}CreatureObject* get(){return value;}bool operator!()const{return !value && !weapon;}bool operator==(std::nullptr_t)const{return !value && !weapon;}bool operator!=(std::nullptr_t)const{return value || weapon;}template<class T>T castTo(){return weapon;}};
struct CombatQueueCommand {virtual ~CombatQueueCommand(){}bool state=true;double hm=1,am=1,mm=1;bool checkStateMask(CreatureObject*)const{return state;}bool checkInvalidLocomotions(CreatureObject*)const{return state;}int getWeaponType()const{return 1;}double getDamageMultiplier()const{return 1;}double getHealthCostMultiplier()const{return hm;}double getActionCostMultiplier()const{return am;}double getMindCostMultiplier()const{return mm;}};
struct Controller {CombatQueueCommand command;const CombatQueueCommand* getQueueCommand(const char*){return &command;}};
template<class T>struct SortedVector:std::vector<T> {SortedVector(int,int){}T get(int i){return this->at(i);}};
struct Zone {uint64 getObjectID(){return 1;}std::vector<CreatureObject*> actors;void getInRangeObjects(double,double,double,double,SortedVector<TreeEntry*>* out,bool){for(auto a:actors)out->push_back(a);}};
struct Server {Controller controller;Zone zone;std::map<uint64,CreatureObject*> objects;Controller* getObjectController(){return &controller;}Weapon* weapon=nullptr;ObjectRef getObject(uint64 key){return {objects.count(key)?objects.at(key):nullptr,weapon && key==weapon->id?weapon:nullptr};}};
struct CreatureObject {bool boss=false;int branchRaw=50;std::map<std::string,String> saved;String getScreenPlayData(const char* ns,const String& key){return saved[std::string(ns)+key];}void setScreenPlayData(const char* ns,const String& key,const String& value){saved[std::string(ns)+key]=value;}Server* server=nullptr;Weapon* weapon=nullptr;uint64 id=77;Vec position;bool ai=true,pet=false,dead=false,incap=false,riding=false,attackable=true,los=true,immune=false,dodge=false;double resistance=0,height=1.;int ham[7]={10000,0,0,10000,0,0,10000};std::set<std::string> skills,grants;std::map<unsigned,Buff*> buffs;std::map<std::string,Timer> timers;int paid=0,strikes=0,posture=0,postureDelay=0,stunSeconds=0;
 bool checkCooldownRecovery(const char* key){return !timers.count(key);}bool checkKnockdownRecovery(){return checkCooldownRecovery("knockdownRecovery");}bool isKnockedDown(){return posture==CreaturePosture::KNOCKEDDOWN;}void setPosture(int value,bool,bool){posture=value;}void setPostureChangeDelay(int ms){postureDelay=ms;}bool hasPostureChangeDelay(){return postureDelay>0;}void setStunnedState(int seconds){stunSeconds=seconds;}
 Weapon* getWeapon(){return weapon;}CreatureObject* getPlayerObject(){return this;}Server* getZoneServer(){return server;}Zone* getZone(){return server?&server->zone:nullptr;}Vec getWorldPosition(){return position;}double getDistanceTo(CreatureObject* a){auto p=a->getWorldPosition();return std::sqrt(std::pow(position.x-p.x,2)+std::pow(position.y-p.y,2)+std::pow(position.z-p.z,2));}double getHeight(bool){return height;}uint64 getObjectID(){return id;}
 bool isCreatureObject(){return true;}CreatureObject* asCreatureObject(){return this;}bool isLairObject(){return false;}CreatureObject* asTangibleObject(){return this;}
 bool isAiAgent(){return ai;}CreatureObject* asAiAgent(){return this;}bool isPet(){return pet;}bool isDead(){return dead;}bool isIncapacitated(){return incap;}bool isRidingMount(){return riding;}bool isAttackableBy(CreatureObject*){return attackable;}bool hasEffectImmunity(int){return immune;}int getSkillMod(const char*){return 0;}
 bool hasSkill(const char* s){return skills.count(s);}bool hasAbility(const char* s){return grants.count(s);}bool hasBuff(unsigned key){return buffs.count(key);}void removeBuff(unsigned key){buffs.erase(key);}Buff* getBuff(unsigned key){return buffs.count(key)?buffs.at(key):nullptr;}void addBuff(Buff* b){buffs[b->key]=b;}
 Timer* getCooldownTime(const String& key){return timers.count(key)?&timers.at(key):nullptr;}void addCooldown(const String& key,int ms){timers[key]={ms};}
 int getHAM(int i){return ham[i];}int getMaxHAM(int){return 10000;}int getWounds(int){return 0;}void inflictDamage(CreatureObject*,int i,int damage,bool,bool,bool){ham[i]-=damage;paid+=damage;}void setHAM(int i,int value){ham[i]=value;}void setTargetID(uint64,bool){}
};
struct CollisionManager {static bool checkLineOfSight(CreatureObject*,CreatureObject* a){return a->los;}};
struct CoreCuCombat {static bool boss(CreatureObject* c){return c->boss;}static double rating(CreatureObject* c,int,int){return c->resistance;}};
struct System {static int roll,attempts;static int random(int bound){assert(bound==99);++attempts;return roll;}};int System::roll=0;int System::attempts=0;
struct CreatureAttackData {const CombatQueueCommand* source;CreatureAttackData(const char*,const CombatQueueCommand* p,int):source(p){}};
struct CombatManager {static CombatManager* instance(){static CombatManager c;return &c;}double calculateWeaponAttackSpeed(CreatureObject*,Weapon*,float){return 2;}bool applyProjectileLaunchCost(CreatureObject* c,Weapon*,const CreatureAttackData& data){int cost=int(20*data.source->am);if(c->ham[3]<=cost)return false;c->ham[3]-=cost;c->paid+=cost;return true;}};
struct SwgxrTkaStrike {double multiplier;SwgxrTkaStrike(const CombatQueueCommand&,double x):multiplier(x){}void setRange(int){}int doCombatAction(CreatureObject* c,uint64 id,const char*,Weapon* w){auto a=c->server->objects.at(id);++a->strikes;if(corecu::volley::claimHit(c->getObjectID(),a->getObjectID()) || !a->dodge)a->ham[0]-=int(w->damage*multiplier);return QueueCommand::SUCCESS;}};
struct TaskManager {std::vector<std::function<void()>> tasks;std::vector<int> times;template<class F>void scheduleTask(F call,const char*,int ms){tasks.push_back(call);times.push_back(ms);}};struct Core {static TaskManager* getTaskManager(){static TaskManager t;return &t;}};
#include "pistoleer_native.inc"
#include "carbineer_native.inc"
struct SwgxrBountyHunterModifiers {static int branch(CreatureObject* c,const String&){return c->branchRaw;}};
struct SwgxrBlastSight {static bool clear(CreatureObject*,CreatureObject* a,const corecu::bountyhunter::Vec&){return a->los;}};
#include "bountyhunter_native.inc"
struct SwgxrPreparedRangedCommand:CombatQueueCommand {explicit SwgxrPreparedRangedCommand(const CombatQueueCommand& s):CombatQueueCommand(s){}void setHealthCostMultiplier(double x){hm=x;}void setActionCostMultiplier(double x){am=x;}void setMindCostMultiplier(double x){mm=x;}void setForceCostMultiplier(double){} };
struct SwgxrConfirmedProjectileCommand:SwgxrPreparedRangedCommand {double damage=1,normalized=0;explicit SwgxrConfirmedProjectileCommand(const CombatQueueCommand& s):SwgxrPreparedRangedCommand(s){}void normalizeDamage(double d,double){normalized=d;}void setRiflemanPiercing(bool){}void setDamageMultiplier(double x){damage=x;}void setPoolsToDamage(int){}int doCombatAction(CreatureObject* c,uint64 id,const char*,Weapon* w){auto a=c->server->objects.at(id);if(!a->attackable)return 1;++a->strikes;if(corecu::volley::claimHit(c->getObjectID(),a->getObjectID()) || !a->dodge)a->ham[0]-=int((normalized>0?normalized:w->damage)*damage);return 0;}};
struct SwgxrVehicles {static bool seated(CreatureObject* c){return c->riding;}static double launchReach(CreatureObject*){return 2.5;}};
struct SwgxrRifleman {static bool compatible(CreatureObject*){return false;}static bool headUpgrade(CreatureObject*){return false;}static bool targetReady(CreatureObject*){return false;}static double damage(CreatureObject*,const std::string&){return 0;}static double focusScale(CreatureObject*,const std::string&){return 1;}static double interval(CreatureObject*,const std::string&){return 2;}};
struct SwgxrMarksman {static int actionCost(CreatureObject*,const std::string& id){return corecu::marksman::ability(id).action;}static void effects(CreatureObject*,CreatureObject*,const std::string&,int){}static bool compatible(CreatureObject*,const std::string&){return true;}static bool targetReady(CreatureObject* a,const std::string&){return SwgxrPistoleer::targetReady(a);}static double damage(CreatureObject*,const std::string& id){return corecu::marksman::ability(id).damage;}static double interval(CreatureObject*,const std::string& id){return corecu::marksman::ability(id).cooldown;}};
struct SwgxrSmuggler {static void effects(CreatureObject*,CreatureObject*,const std::string&){}static const CombatQueueCommand* command(CreatureObject* c,const std::string&){return &c->server->controller.command;}static bool learned(CreatureObject* c,const std::string& id){return corecu::bountyhunter::contains(id)?SwgxrBountyHunter::learned(c,id):corecu::carbineer::contains(id)?SwgxrCarbineer::learned(c,id):!corecu::pistoleer::contains(id) || SwgxrPistoleer::learned(c,id);}static double cooldown(CreatureObject* c,const std::string& id){return corecu::bountyhunter::contains(id)?SwgxrBountyHunter::cooldown(c,id):SwgxrPistoleer::cooldown(c,id);}static double multiplier(CreatureObject*){return 2;}};
struct SwgxrSmugglerPolicy {static constexpr double concussionDamage=.5;};struct SwgxrSpice {static double cooldownScale(CreatureObject*){return 1;}};
struct SwgxrCombatLoadout {static uint64 revision;static bool equipped;static bool allows(CreatureObject*,const std::string& id){return id.empty() || equipped;}static Json saved(CreatureObject*){return {{"revision",revision}};}};uint64 SwgxrCombatLoadout::revision=1;bool SwgxrCombatLoadout::equipped=true;
// Native id accepts SceneObject; the isolated weapon also supplies that overload.

#define private public
#include "bountyhunter_fire.inc"
#undef private

template<class F>void rejects(F action){bool failed=false;try{action();}catch(const std::exception&){failed=true;}assert(failed);}
int main(int argc,char** argv){
 using namespace corecu::bountyhunter;int checks=0;auto check=[&](bool ok){++checks;if(!ok){std::cerr<<"BH check "<<checks<<" failed\n";std::abort();}};
 Server server;Weapon weapon;server.weapon=&weapon;CreatureObject c,a,b;c.server=a.server=b.server=&server;c.weapon=&weapon;c.ai=false;c.id=42;a.id=77;b.id=78;a.position={0,0,10};b.position={2,0,10};server.objects={{77,&a},{78,&b}};
 c.skills={"combat_bountyhunter_novice","combat_bountyhunter_droidresponse_01","combat_bountyhunter_droidresponse_02","combat_bountyhunter_droidresponse_04","combat_bountyhunter_droidcontrol_01","combat_bountyhunter_droidcontrol_03","combat_bountyhunter_droidcontrol_04","combat_bountyhunter_investigation_04","combat_bountyhunter_master"};c.grants={"eyeShot","bleedingShot","torsoShot","confusionShot","underHandShot","knockdownFire","fastBlast"};
 auto reset=[&](){c.timers.clear();c.saved.clear();c.buffs.clear();c.ham[3]=c.ham[6]=10000;c.paid=0;server.controller.command.state=true;weapon.cert=weapon.owned=true;weapon.broken=false;c.riding=c.dead=c.incap=false;c.branchRaw=50;a.timers.clear();a.buffs.clear();a.ham[0]=10000;a.strikes=0;a.position={0,0,10};a.dead=a.incap=a.pet=a.boss=a.dodge=a.immune=false;a.los=a.attackable=true;a.posture=a.postureDelay=a.stunSeconds=0;a.resistance=0;b.ham[0]=10000;System::roll=0;SwgxrCombatLoadout::equipped=true;};
 auto request=[&](const char* ability,const char* action="fire",const char* id="shot"){return Json{{"action",action},{"shot_id",id},{"item_id","55"},{"ability_id",ability},{"origin",{0,1,0}},{"direction",{0,0,1}},{"two_hands",true}};};
 auto impact=[&](const char* id="shot"){return Json{{"action","impact"},{"shot_id",id},{"target_id","77"},{"hit_position",{0,1,10}},{"projectile_age_seconds",.0625}};};
 for(auto id:{"eye_shot","bleeding_shot","confusion_shot","underhand_shot","duelist_stance","fast_blast"}){check(SwgxrBountyHunter::learned(&c,id));auto skill=ability(id).skill;c.skills.erase(skill);check(!SwgxrBountyHunter::learned(&c,id));c.skills.insert(skill);}
 for(auto id:{"eye_shot","confusion_shot","underhand_shot"}){reset();for(int gate=0;gate<5;++gate){a.ai=gate!=0;a.pet=gate==1;a.dead=gate==2;a.incap=gate==3;check(SwgxrBountyHunter::targetReady(&a,id)==(gate==4));}a.ai=true;a.pet=a.dead=a.incap=false;SwgxrBountyHunter::effects(&c,&a,id,0);check(a.timers.empty());a.immune=true;SwgxrBountyHunter::effects(&c,&a,id,100);check(a.timers.empty());}
 reset();SwgxrBountyHunter::effects(&c,&a,"eye_shot",100);check(a.buffs.at(STRING_HASHCODE("swgxr_suppression_fire"))->mods.at("private_accuracy_bonus")==-25);check(a.buffs.size()==1 && a.timers.count("corecu_control_recovery"));
 reset();auto weak=new Buff(&a,STRING_HASHCODE("swgxr_suppression_fire"),4,0);weak->setSkillModifier("private_accuracy_bonus",-20);a.addBuff(weak);SwgxrBountyHunter::effects(&c,&a,"eye_shot",100);check(a.buffs.size()==1 && a.getBuff(weak->key)->getSkillModifierValue("private_accuracy_bonus")==-25);a.timers.clear();auto same=a.getBuff(weak->key);SwgxrBountyHunter::effects(&c,&a,"eye_shot",100);check(a.getBuff(weak->key)==same && a.timers.empty());
 reset();SwgxrBountyHunter::effects(&c,&a,"confusion_shot",100);check(a.stunSeconds==3 && a.timers.size()==1);SwgxrBountyHunter::effects(&c,&a,"underhand_shot",100);check(!a.isKnockedDown());
 reset();a.boss=true;SwgxrBountyHunter::effects(&c,&a,"underhand_shot",100);check(!a.isKnockedDown() && a.timers.empty());a.boss=false;SwgxrBountyHunter::effects(&c,&a,"underhand_shot",100);check(a.isKnockedDown() && a.postureDelay==2000 && a.timers.count("knockdownRecovery"));a.postureDelay=0;Core::getTaskManager()->tasks.back()();check(!a.isKnockedDown());
 reset();a.resistance=100;System::roll=58;SwgxrBountyHunter::effects(&c,&a,"confusion_shot",100);check(a.stunSeconds==0 && a.timers.count("corecu_control_recovery"));a.timers.clear();System::roll=56;SwgxrBountyHunter::effects(&c,&a,"confusion_shot",100);check(a.stunSeconds==2);check(chance(125,50)<corecu::learnedStatusChance(85,40,125));
 // Underhand requires an actual native arm, accepts an untargeted physical shot,
 // commits costs/cooldown on launch, consumes on miss and cannot be replayed.
 reset();NativeFireHarness::Session session;auto q=request("underhand_shot");rejects([&](){NativeFireHarness::fire(&c,session,q,0);});check(c.paid==0);auto arm=request("underhand_shot","bountyhunter","arm");auto out=NativeFireHarness::fire(&c,session,arm,0);check(out["armed"]==true && c.paid==0);SwgxrCombatLoadout::equipped=false;out=NativeFireHarness::fire(&c,session,q,.3);check(c.ham[3]==9930 && c.ham[6]==9970 && session.bountyArm.item.empty());check(session.shots.at("shot").target.empty());c.timers.clear();check(SwgxrBountyHunter::cooldown(&c,"underhand_shot")>23);rejects([&](){NativeFireHarness::fire(&c,session,request("underhand_shot","fire","replay"),3);});check(a.ham[0]==10000);out=NativeFireHarness::fire(&c,session,impact(),.4);check(out["damage"]==65 && a.isKnockedDown());rejects([&](){NativeFireHarness::fire(&c,session,impact(),.5);});++checks;
 reset();session={};NativeFireHarness::fire(&c,session,arm,0);rejects([&](){NativeFireHarness::fire(&c,session,q,1.51);});check(c.paid==0);session={};NativeFireHarness::fire(&c,session,arm,0);weapon.id=56;auto swapped=q;swapped["item_id"]="56";rejects([&](){NativeFireHarness::fire(&c,session,swapped,.4);});weapon.id=55;check(c.paid==0);session={};rejects([&](){NativeFireHarness::fire(&c,session,q,.4);});++checks;
 // Background read-only snapshots/replication must not eat the gesture window.
 for(auto poll:std::vector<Json>{{{"action","snapshot"}},{{"action","replication"}},{{"action","inventory"}},{{"action","services"},{"service",{{"action","status"}}}},{{"action","session"},{"session",{{"action","status"}}}}}){Arm armed;armed.set("55",0);if(SwgxrBountyHunter::clearsArm(poll))armed.clear();check(armed.ready("55",.5));}
 for(auto mutation:std::vector<Json>{{{"action","loadout"}},{{"action","inventory"},{"inventory_command","swgxr_inventory_v1 equip 56"}},{{"action","services"},{"service",{{"action","travel_board"}}}},{{"action","session"},{"session",{{"action","logout"}}}}}){Arm armed;armed.set("55",0);if(SwgxrBountyHunter::clearsArm(mutation))armed.clear();check(!armed.ready("55",.5));}
 // Duelist target remains bound, and resource/cooldown writes survive timer reset.
 reset();weapon.carbine=false;weapon.pistol=true;q=request("duelist_stance","bountyhunter");q["target_id"]="77";session={};out=NativeFireHarness::fire(&c,session,q,0);check(c.ham[3]==9940 && c.ham[6]==9970 && c.hasBuff(STRING_HASHCODE("swgxr_duelist_stance")));check(c.getScreenPlayData("swgxr_bountyhunter","duelist_target")=="77");c.timers.clear();check(SwgxrBountyHunter::cooldown(&c,"duelist_stance")>59);q["shot_id"]="other";q["target_id"]="78";rejects([&](){NativeFireHarness::fire(&c,session,q,1);});check(c.getScreenPlayData("swgxr_bountyhunter","duelist_target")=="77");
 for(int failure=0;failure<4;++failure){reset();session={};q=request("duelist_stance","bountyhunter");q["target_id"]="77";if(failure==0)a.los=false;if(failure==1)a.position.x=10;if(failure==2)a.pet=true;if(failure==3)c.ham[3]=60;rejects([&](){NativeFireHarness::fire(&c,session,q,0);});check(!c.hasBuff(STRING_HASHCODE("swgxr_duelist_stance")));}
 // One deterministic scatter discharge, bounded aggregate damage and one victim.
 reset();weapon.templ.path="object/weapon/ranged/pistol/pistol_scatter.iff";session={};q=request("");out=NativeFireHarness::fire(&c,session,q,0);check(out["projectile_profile"]["pellet_count"]==8);auto pellets=[&](int count){Json hit=impact();hit["pellet_contacts"]=Json::array();for(int i=0;i<count;++i){auto d=pelletDirection({{0,0,1}},i);hit["pellet_contacts"].push_back({{"pellet_index",i},{"hit_position",{d[0]*10,1+d[1]*10,d[2]*10}},{"projectile_age_seconds",.0625}});}return hit;};out=NativeFireHarness::fire(&c,session,pellets(8),.2);check(out["damage"]==100 && a.strikes==1 && b.ham[0]==10000 && out["pellet_hits"]==8);rejects([&](){NativeFireHarness::fire(&c,session,pellets(8),.3);});++checks;
 reset();session={};NativeFireHarness::fire(&c,session,q,0);out=NativeFireHarness::fire(&c,session,pellets(1),.2);check(out["damage"]==12 && a.strikes==1);
 for(int failure=0;failure<8;++failure){reset();session={};NativeFireHarness::fire(&c,session,q,0);auto bad=pellets(2);if(failure==0)bad["pellet_contacts"][1]["pellet_index"]=0;if(failure==1)bad["pellet_contacts"][1]["pellet_index"]=8;if(failure==2)bad["pellet_contacts"][1]["hit_position"]={3,1,10};if(failure==3)bad["hit_position"]={.1,1,10};if(failure==4)bad["pellet_contacts"][1]["projectile_age_seconds"]=.9;if(failure==5)a.los=false;if(failure==6)bad.erase("pellet_contacts");if(failure==7)bad["pellet_contacts"]=Json::array();rejects([&](){NativeFireHarness::fire(&c,session,bad,.2);});check(a.ham[0]==10000 && session.shots.at("shot").spent);}
 // SL marks use the same single receipt and one full shot budget, not eight packets.
 reset();session={};a.dodge=true;{corecu::volley::Scope guarantee(c.id,a.id);q=request("");q["target_id"]="77";NativeFireHarness::fire(&c,session,q,0);auto hit=impact();hit["projectile_age_seconds"]=0;out=NativeFireHarness::fire(&c,session,hit,0);check(out["damage"]==100 && a.strikes==1 && guarantee.resolved());}rejects([&](){NativeFireHarness::fire(&c,session,impact(),.2);});++checks;
 // Consume actual source-coordinate Godot output, including two swept physics contacts.
 if(argc>1){std::ifstream file(argv[1]);Json fixture;file>>fixture;for(const auto& row:fixture.at("source_space_pellet_directions")){corecu::bountyhunter::Vec launch{},expected{};for(int i=0;i<3;++i){launch[i]=row["launch_direction"][i].get<double>();expected[i]=row["pellet_direction"][i].get<double>();}auto actual=pelletDirection(launch,row["pellet_index"].get<int>());for(int i=0;i<3;++i)check(std::abs(actual[i]-expected[i])<.000001);}
  reset();session={};a.position={1.2,0,20};q=request("");auto physical=fixture.at("source_space_scatter_fixture");q["origin"]=physical["origin"];q["direction"]=physical["direction"];NativeFireHarness::fire(&c,session,q,0);auto hit=impact();hit["pellet_contacts"]=physical["pellet_contacts"];hit["hit_position"]=physical["pellet_contacts"][0]["hit_position"];hit["projectile_age_seconds"]=physical["pellet_contacts"][0]["projectile_age_seconds"];out=NativeFireHarness::fire(&c,session,hit,.2);check(out["damage"]==25 && out["pellet_hits"]==2 && a.strikes==1);
 }
 // Guidance is accepted once, bound to that target and limited by elapsed turn,
 // range, muzzle LOS and contact. Normalization remains one Health damage packet.
 reset();weapon.templ.path="object/weapon/ranged/rifle/rifle_lightning.iff";weapon.pistol=false;weapon.lightning=true;weapon.range=64;weapon.damage=502;a.position={1,0,40};session={};q=request("");q["guided_target_id"]="77";out=NativeFireHarness::fire(&c,session,q,0);check(out["guided_target_id"]=="77" && out["projectile_profile"]["kind"]=="lightning");auto hit=impact();hit["hit_position"]={1,1,40};hit["projectile_age_seconds"]=.26;out=NativeFireHarness::fire(&c,session,hit,.3);check(out["damage"]==508 && a.strikes==1);
 for(int failure=0;failure<4;++failure){reset();weapon.damage=502;a.position={1,0,40};session={};q=request("");q["guided_target_id"]="77";if(failure==0)a.position.x=6;if(failure==1)a.los=false;if(failure==2)a.position.y=70;if(failure==3)a.pet=true;rejects([&](){NativeFireHarness::fire(&c,session,q,0);});check(c.paid==0);}
 for(int failure=0;failure<4;++failure){reset();a.position={1,0,40};session={};NativeFireHarness::fire(&c,session,q,0);hit=impact();hit["hit_position"]={1,1,40};hit["projectile_age_seconds"]=.26;if(failure==0){hit["target_id"]="78";b.position=a.position;}if(failure==1){a.position.x=10;hit["hit_position"]={10,1,40};}if(failure==2)a.los=false;if(failure==3)hit["projectile_age_seconds"]=.01;rejects([&](){NativeFireHarness::fire(&c,session,hit,.3);});check(a.ham[0]==10000 && b.ham[0]==10000 && session.shots.at("shot").spent);}
 reset();weapon.damage=502;session={};q=request("fast_blast");q["target_id"]="77";out=NativeFireHarness::fire(&c,session,q,0);check(c.ham[3]==9860 && c.ham[6]==9930);out=NativeFireHarness::fire(&c,session,impact(),.2);check(out["damage"]==1524 && a.strikes==1);c.timers.clear();check(SwgxrBountyHunter::cooldown(&c,"fast_blast")>119);
 check(lightningDamage(276,592,50)==416 && lightningDamage(410,730,50)==600 && lightningDamage(10000,10000,50)==600);check(!corecu::pistoleer::regular("fast_blast"));
 // Ordinary arrival compensation uses a native rate reservation, independent
 // of client launch age. A rejected or replayed request never pays twice.
 reset();weapon=Weapon();session={};q=request("");q["launch_age_seconds"]=.2;
 out=NativeFireHarness::fire(&c,session,q,100);
 check(out["latency_compensated"]==true && out["accepted_launch_age_seconds"]==.2);
 check(std::abs(session.shots.at("shot").time-99.8)<1.e-8 && session.nextFire==102);
 check(out["cooldown_remaining_seconds"]==1.75);
 int launchPaid=c.paid;rejects([&]{NativeFireHarness::fire(&c,session,q,103);});check(c.paid==launchPaid && session.nextFire==102);
 q["shot_id"]="timing_jitter_second";NativeFireHarness::fire(&c,session,q,101.8);check(session.nextFire==104);
 q["shot_id"]="timing_jitter_third";NativeFireHarness::fire(&c,session,q,103.75);check(session.nextFire==106);
 q["shot_id"]="timing_too_early";q["launch_age_seconds"]=999;launchPaid=c.paid;
 rejects([&]{NativeFireHarness::fire(&c,session,q,105.5);});check(c.paid==launchPaid && session.nextFire==106);
 out=NativeFireHarness::fire(&c,session,q,106);check(out["accepted_launch_age_seconds"]==.25 && session.nextFire==108);
 // No credit after idling, no allowance on a first shot or weapon switch.
 q["shot_id"]="timing_after_idle";NativeFireHarness::fire(&c,session,q,200);check(session.nextFire==202);
 q["shot_id"]="timing_no_idle_burst";launchPaid=c.paid;rejects([&]{NativeFireHarness::fire(&c,session,q,200.1);});check(c.paid==launchPaid);
 session={};session.nextFire=300;rejects([&]{NativeFireHarness::fire(&c,session,q,299.9);});
 session.ordinaryCadence=true;session.ordinaryItem="different_weapon";rejects([&]{NativeFireHarness::fire(&c,session,q,299.9);});
 // Legacy and special fire retain strict cadence; malformed ages fail free.
 for(auto bad:std::vector<Json>{-.1,"0.2",true,nullptr}){session={};q["launch_age_seconds"]=bad;launchPaid=c.paid;rejects([&]{NativeFireHarness::fire(&c,session,q,400);});check(c.paid==launchPaid && session.shots.empty());}
 reset();session={};q=request("");out=NativeFireHarness::fire(&c,session,q,500);check(!out.contains("latency_compensated") && !session.ordinaryCadence);
 q["shot_id"]="timing_legacy_strict";q["launch_age_seconds"]=.1;rejects([&]{NativeFireHarness::fire(&c,session,q,501.9);});
 for(auto path:{"object/weapon/ranged/pistol/pistol_scatter.iff","object/weapon/ranged/rifle/rifle_lightning.iff"}){reset();session={};weapon.templ.path=path;weapon.lightning=std::string(path).find("lightning")!=std::string::npos;q=request("");q["launch_age_seconds"]=.25;out=NativeFireHarness::fire(&c,session,q,600);check(!out.contains("latency_compensated") && !session.ordinaryCadence);q["shot_id"]="timing_profile_strict";rejects([&]{NativeFireHarness::fire(&c,session,q,601.9);});}
 reset();weapon=Weapon();session={};q=request("last_ditch");q["launch_age_seconds"]=.25;out=NativeFireHarness::fire(&c,session,q,700);check(!out.contains("latency_compensated") && !session.ordinaryCadence);
 q=request("");q["shot_id"]="timing_after_special";q["launch_age_seconds"]=.25;rejects([&]{NativeFireHarness::fire(&c,session,q,701.9);});
 // A deterministic 100-shot jitter stream stays smooth. A forged fast stream
 // cannot accumulate more than one bounded advance or exceed sustained rate.
 double reserved=0;for(int i=0;i<100;++i){double receipt=800+i*2+(i%3)*.1;check(corecu::projectile::arrivalReady(receipt,reserved,2,i>0));reserved=corecu::projectile::reserveArrival(receipt,reserved,2);}
 reserved=0;int accepted=0;for(int i=0;i<1000;++i){double receipt=1000+i*.01;if(corecu::projectile::arrivalReady(receipt,reserved,1,accepted>0)){++accepted;reserved=corecu::projectile::reserveArrival(receipt,reserved,1);}}check(accepted==11);
 std::cout<<checks<<" actual BH grant, gesture reservation, resource, control, cooldown, scatter, guidance and one-packet receipt cases passed (isolated engine dependencies)\n";
}
