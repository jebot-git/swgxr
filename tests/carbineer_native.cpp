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
using JSONSerializationType=nlohmann::json;using Json=JSONSerializationType;using uint64=unsigned long long;using String=std::string;
constexpr unsigned hash(const char* p,unsigned h=0){return *p?hash(p+1,h*31+*p):h;}
#define STRING_HASHCODE(s) hash(s)
struct CommandEffect {enum{INTIMIDATE,KNOCKDOWN,STUN,NEXTATTACKDELAY};};struct BuffType {enum{STATE};};struct QueueCommand {enum{SUCCESS};};
struct CreatureObject;using AiAgent=CreatureObject;using SceneObject=CreatureObject;using TreeEntry=CreatureObject;
template<class T>using ManagedReference=T;
struct Locker {template<class A>Locker(A){}template<class A,class B>Locker(A,B){}};
struct CreaturePosture{enum{UPRIGHT,KNOCKEDDOWN};};
struct Vec {double x=0,z=0,y=0;double getX()const{return x;}double getY()const{return y;}double getZ()const{return z;}};
struct Buff {unsigned key;int seconds;std::map<std::string,int> mods;Buff(CreatureObject*,unsigned id,int duration,int):key(id),seconds(duration){}void setSkillModifier(const char* k,int v){mods[k]=v;}float getTimeLeft(){return seconds;}};
struct Timer {int ms=0;int miliDifference(){return -ms;}};
struct WeaponTemplate {std::string path="object/weapon/ranged/pistol/pistol_dl44.iff";struct Name {std::string value;const char* toCharArray(){return value.c_str();}};Name getFullTemplateString(){return {path};}};
struct Weapon {WeaponTemplate templ;WeaponTemplate* getObjectTemplate(){return &templ;}bool flame=false;bool isFlameThrower(){return flame;}bool pistol=false,carbine=true,cert=true,broken=false,owned=true;uint64 id=55;double damage=100,range=32;
 bool isCarbineWeapon(){return carbine;}bool isPistolWeapon(){return pistol;}bool isRangedWeapon(){return true;}bool isCertifiedFor(CreatureObject*){return cert;}bool isBroken(){return broken;}bool isASubChildOf(CreatureObject*){return owned;}uint64 getObjectID(){return id;}
 int getWeaponBitmask(){return 1;}double getMaxRange(){return range;}double getPointBlankRange(){return 0;}double getIdealRange(){return 16;}double getPointBlankAccuracy(){return 0;}double getIdealAccuracy(){return 0;}double getMaxRangeAccuracy(){return 0;}int getDamageType(){return 1;}int getArmorPiercing(){return 0;}double getMinDamage(){return damage;}double getMaxDamage(){return damage;}
};
using WeaponObject=Weapon;
struct ObjectRef {CreatureObject* value=nullptr;Weapon* weapon=nullptr;CreatureObject* operator->()const{return value;}CreatureObject* get(){return value;}bool operator!()const{return !value && !weapon;}bool operator==(std::nullptr_t)const{return !value && !weapon;}bool operator!=(std::nullptr_t)const{return value || weapon;}template<class T>T castTo(){return weapon;}};
struct CombatQueueCommand {virtual ~CombatQueueCommand(){}bool state=true;double hm=1,am=1,mm=1;bool checkStateMask(CreatureObject*)const{return state;}bool checkInvalidLocomotions(CreatureObject*)const{return state;}int getWeaponType()const{return 1;}double getDamageMultiplier()const{return 1;}double getHealthCostMultiplier()const{return hm;}double getActionCostMultiplier()const{return am;}double getMindCostMultiplier()const{return mm;}};
struct Controller {CombatQueueCommand command;const CombatQueueCommand* getQueueCommand(const char*){return &command;}};
template<class T>struct SortedVector:std::vector<T> {SortedVector(int,int){}T get(int i){return this->at(i);}};
struct Zone {uint64 getObjectID(){return 1;}std::vector<CreatureObject*> actors;void getInRangeObjects(double,double,double,double,SortedVector<TreeEntry*>* out,bool){for(auto a:actors)out->push_back(a);}};
struct Server {Controller controller;Zone zone;std::map<uint64,CreatureObject*> objects;Controller* getObjectController(){return &controller;}Weapon* weapon=nullptr;ObjectRef getObject(uint64 key){return {objects.count(key)?objects.at(key):nullptr,weapon && key==weapon->id?weapon:nullptr};}};
struct CreatureObject {Server* server=nullptr;Weapon* weapon=nullptr;uint64 id=77;Vec position;bool ai=true,pet=false,dead=false,incap=false,riding=false,attackable=true,los=true,immune=false,dodge=false;double resistance=0,height=1.;int ham[7]={10000,0,0,10000,0,0,10000};std::set<std::string> skills,grants;std::map<unsigned,Buff*> buffs;std::map<std::string,Timer> timers;int paid=0,strikes=0,posture=0,postureDelay=0,stunSeconds=0;
 bool checkCooldownRecovery(const char* key){return !timers.count(key);}bool checkKnockdownRecovery(){return checkCooldownRecovery("knockdownRecovery");}bool isKnockedDown(){return posture==CreaturePosture::KNOCKEDDOWN;}void setPosture(int value,bool,bool){posture=value;}void setPostureChangeDelay(int ms){postureDelay=ms;}bool hasPostureChangeDelay(){return postureDelay>0;}void setStunnedState(int seconds){stunSeconds=seconds;}
 Weapon* getWeapon(){return weapon;}CreatureObject* getPlayerObject(){return this;}Server* getZoneServer(){return server;}Zone* getZone(){return server?&server->zone:nullptr;}Vec getWorldPosition(){return position;}double getDistanceTo(CreatureObject* a){auto p=a->getWorldPosition();return std::sqrt(std::pow(position.x-p.x,2)+std::pow(position.y-p.y,2)+std::pow(position.z-p.z,2));}double getHeight(bool){return height;}uint64 getObjectID(){return id;}
 bool isCreatureObject(){return true;}CreatureObject* asCreatureObject(){return this;}bool isLairObject(){return false;}CreatureObject* asTangibleObject(){return this;}
 bool isAiAgent(){return ai;}CreatureObject* asAiAgent(){return this;}bool isPet(){return pet;}bool isDead(){return dead;}bool isIncapacitated(){return incap;}bool isRidingMount(){return riding;}bool isAttackableBy(CreatureObject*){return attackable;}bool hasEffectImmunity(int){return immune;}int getSkillMod(const char*){return 0;}
 bool hasSkill(const char* s){return skills.count(s);}bool hasAbility(const char* s){return grants.count(s);}bool hasBuff(unsigned key){return buffs.count(key);}void removeBuff(unsigned key){buffs.erase(key);}Buff* getBuff(unsigned key){return buffs.count(key)?buffs.at(key):nullptr;}void addBuff(Buff* b){buffs[b->key]=b;}
 Timer* getCooldownTime(const String& key){return timers.count(key)?&timers.at(key):nullptr;}void addCooldown(const String& key,int ms){timers[key]={ms};}
 int getHAM(int i){return ham[i];}int getMaxHAM(int){return 10000;}int getWounds(int){return 0;}void inflictDamage(CreatureObject*,int i,int damage,bool,bool,bool){ham[i]-=damage;paid+=damage;}void setHAM(int i,int value){ham[i]=value;}void setTargetID(uint64,bool){}
};
struct CollisionManager {static bool checkLineOfSight(CreatureObject*,CreatureObject* a){return a->los;}};
struct CoreCuCombat {static double rating(CreatureObject* c,int,int){return c->resistance;}};
struct System {static int roll,attempts;static int random(int bound){assert(bound==99);++attempts;return roll;}};int System::roll=0;int System::attempts=0;
struct CreatureAttackData {const CombatQueueCommand* source;CreatureAttackData(const char*,const CombatQueueCommand* p,int):source(p){}};
struct CombatManager {static CombatManager* instance(){static CombatManager c;return &c;}double calculateWeaponAttackSpeed(CreatureObject*,Weapon*,float){return 2;}bool applyProjectileLaunchCost(CreatureObject* c,Weapon*,const CreatureAttackData& data){int cost=int(20*data.source->am);if(c->ham[3]<=cost)return false;c->ham[3]-=cost;c->paid+=cost;return true;}};
struct SwgxrTkaStrike {double multiplier;SwgxrTkaStrike(const CombatQueueCommand&,double x):multiplier(x){}void setRange(int){}int doCombatAction(CreatureObject* c,uint64 id,const char*,Weapon* w){auto a=c->server->objects.at(id);++a->strikes;if(corecu::volley::claimHit(c->getObjectID(),a->getObjectID()) || !a->dodge)a->ham[0]-=int(w->damage*multiplier);return QueueCommand::SUCCESS;}};
struct TaskManager {std::vector<std::function<void()>> tasks;std::vector<int> times;template<class F>void scheduleTask(F call,const char*,int ms){tasks.push_back(call);times.push_back(ms);}};struct Core {static TaskManager* getTaskManager(){static TaskManager t;return &t;}};
#include "pistoleer_native.inc"
#include "carbineer_native.inc"
struct SwgxrPreparedRangedCommand:CombatQueueCommand {explicit SwgxrPreparedRangedCommand(const CombatQueueCommand& s):CombatQueueCommand(s){}void setHealthCostMultiplier(double x){hm=x;}void setActionCostMultiplier(double x){am=x;}void setMindCostMultiplier(double x){mm=x;}void setForceCostMultiplier(double){} };
struct SwgxrConfirmedProjectileCommand:SwgxrPreparedRangedCommand {double damage=1;explicit SwgxrConfirmedProjectileCommand(const CombatQueueCommand& s):SwgxrPreparedRangedCommand(s){}void normalizeDamage(double,double){}void setRiflemanPiercing(bool){}void setDamageMultiplier(double x){damage=x;}void setPoolsToDamage(int){}int doCombatAction(CreatureObject* c,uint64 id,const char*,Weapon* w){auto a=c->server->objects.at(id);if(!a->attackable)return 1;++a->strikes;if(corecu::volley::claimHit(c->getObjectID(),a->getObjectID()) || !a->dodge)a->ham[0]-=int(w->damage*damage);return 0;}};
struct SwgxrVehicles {static bool seated(CreatureObject* c){return c->riding;}static double launchReach(CreatureObject*){return 2.5;}};
struct SwgxrRifleman {static bool compatible(CreatureObject*){return false;}static bool headUpgrade(CreatureObject*){return false;}static bool targetReady(CreatureObject*){return false;}static double damage(CreatureObject*,const std::string&){return 0;}static double focusScale(CreatureObject*,const std::string&){return 1;}static double interval(CreatureObject*,const std::string&){return 2;}};
struct SwgxrMarksman {static int actionCost(CreatureObject*,const std::string& id){return corecu::marksman::ability(id).action;}static void effects(CreatureObject*,CreatureObject*,const std::string&,int){}static bool compatible(CreatureObject*,const std::string&){return true;}static bool targetReady(CreatureObject* a,const std::string&){return SwgxrPistoleer::targetReady(a);}static double damage(CreatureObject*,const std::string& id){return corecu::marksman::ability(id).damage;}static double interval(CreatureObject*,const std::string& id){return corecu::marksman::ability(id).cooldown;}};
struct SwgxrSmuggler {static void effects(CreatureObject*,CreatureObject*,const std::string&){}static const CombatQueueCommand* command(CreatureObject* c,const std::string&){return &c->server->controller.command;}static bool learned(CreatureObject* c,const std::string& id){return corecu::carbineer::contains(id)?SwgxrCarbineer::learned(c,id):!corecu::pistoleer::contains(id) || SwgxrPistoleer::learned(c,id);}static double cooldown(CreatureObject* c,const std::string& id){return SwgxrPistoleer::cooldown(c,id);}static double multiplier(CreatureObject*){return 2;}};
struct SwgxrSmugglerPolicy {static constexpr double concussionDamage=.5;};struct SwgxrSpice {static double cooldownScale(CreatureObject*){return 1;}};
struct SwgxrCombatLoadout {static uint64 revision;static bool equipped;static bool allows(CreatureObject*,const std::string& id){return id.empty() || equipped;}static Json saved(CreatureObject*){return {{"revision",revision}};}};uint64 SwgxrCombatLoadout::revision=1;bool SwgxrCombatLoadout::equipped=true;
// Native id accepts SceneObject; the isolated weapon also supplies that overload.
#include "tests/bounty_disabled_fixture.h"
#define private public
#include "carbineer_fire.inc"
#undef private

template<class F>void rejects(F action){bool failed=false;try{action();}catch(const std::exception&){failed=true;}assert(failed);}
int main(){Server server;Weapon weapon;server.weapon=&weapon;CreatureObject c,a;c.server=a.server=&server;c.weapon=&weapon;c.ai=false;c.id=42;a.id=77;a.position={0,0,5};server.zone.actors={&a};server.objects[77]=&a;
 c.skills={"combat_carbine_novice","combat_carbine_ability_02","combat_carbine_master"};c.grants={"cripplingShot","wildShot1","chargeShot1","fullAutoArea1","suppressionFire2"};int checks=0;
 for(auto id:{"crippling_shot","wild_shot","charge_shot","full_auto_sweep","tactical_brace","charge_blast"}){assert(SwgxrCarbineer::learned(&c,id));c.skills.erase("combat_carbine_novice");assert(!SwgxrCarbineer::learned(&c,id));c.skills.insert("combat_carbine_novice");++checks;}
 for(auto pair:{std::make_pair("wild_shot","wildShot2"),std::make_pair("charge_shot","chargeShot2"),std::make_pair("full_auto_sweep","fullAutoArea2")}){auto saved=c.grants;c.grants={pair.second};assert(SwgxrCarbineer::learned(&c,pair.first));c.grants=saved;++checks;}
 assert(SwgxrCarbineer::suppressionTrained(&c));++checks;
 for(int gate=0;gate<5;++gate){a.ai=gate!=0;a.pet=gate==1;a.dead=gate==2;a.incap=gate==3;assert(SwgxrCarbineer::targetReady(&a)==(gate==4));++checks;}a.ai=true;a.pet=a.dead=a.incap=false;
 auto resetTarget=[&](){a.buffs.clear();a.timers.clear();a.posture=a.postureDelay=a.stunSeconds=0;a.immune=a.dead=a.incap=a.dodge=false;a.ham[0]=10000;System::roll=0;System::attempts=0;};
 for(auto id:{"crippling_shot","wild_shot","charge_shot","full_auto_sweep","charge_blast"}){resetTarget();SwgxrCarbineer::effects(&c,&a,id,0);assert(a.buffs.empty() && a.stunSeconds==0 && !a.isKnockedDown() && System::attempts==0);a.immune=true;SwgxrCarbineer::effects(&c,&a,id,20);assert(System::attempts==0);a.immune=false;System::roll=99;SwgxrCarbineer::effects(&c,&a,id,20);assert(System::attempts==1);assert(a.timers.count("corecu_control_recovery")==size_t(corecu::carbineer::hard(corecu::carbineer::ability(id))));++checks;}
 resetTarget();SwgxrCarbineer::effects(&c,&a,"crippling_shot",100);auto slow=a.buffs.at(STRING_HASHCODE("swgxr_crippling_shot"));assert(slow->seconds==6 && slow->mods.at("private_carbineer_crippling")==40 && a.timers.empty());++checks;
 resetTarget();SwgxrCarbineer::effects(&c,&a,"full_auto_sweep",100);slow=a.buffs.at(STRING_HASHCODE("swgxr_full_auto_sweep"));assert(slow->seconds==4 && slow->mods.at("private_carbineer_sweep")==35);++checks;
 resetTarget();SwgxrCarbineer::effects(&c,&a,"wild_shot",100);assert(a.stunSeconds==3 && !a.isKnockedDown() && a.timers.count("corecu_control_recovery"));++checks;
 resetTarget();System::roll=87;SwgxrCarbineer::effects(&c,&a,"wild_shot",100);assert(a.stunSeconds==0);resetTarget();c.grants.insert("wildShot2");System::roll=87;SwgxrCarbineer::effects(&c,&a,"wild_shot",100);assert(a.stunSeconds==3);c.grants.erase("wildShot2");++checks;
 for(auto id:{"charge_shot","charge_blast"}){resetTarget();SwgxrCarbineer::effects(&c,&a,id,100);int seconds=std::string(id)=="charge_shot"?2:3;assert(a.isKnockedDown() && a.postureDelay==seconds*1000 && a.timers.count("corecu_control_recovery") && a.timers.count("knockdownRecovery"));auto tm=Core::getTaskManager();assert(tm->times.back()==seconds*1000+1);tm->tasks.back()();assert(a.isKnockedDown());a.postureDelay=0;tm->tasks.back()();assert(!a.isKnockedDown());++checks;}
 for(auto id:{"wild_shot","charge_shot","charge_blast"}){resetTarget();a.timers["corecu_control_recovery"]={8000};SwgxrCarbineer::effects(&c,&a,id,100);assert(System::attempts==0 && a.stunSeconds==0 && !a.isKnockedDown());assert(SwgxrCarbineer::targetReady(&a));++checks;}
 Json request={{"action","carbineer"},{"shot_id","brace_gesture_one"},{"item_id","55"},{"ability_id","tactical_brace"},{"origin",{0,.65,0}},{"direction",{0,0,1}},{"two_hands",true}};
 for(Json bad:{Json(false),Json("yes"),Json(1)}){auto q=request;q["two_hands"]=bad;int paid=c.paid;rejects([&]{SwgxrCarbineer::run(&c,q);});assert(c.paid==paid);++checks;}
 {auto q=request;q.erase("two_hands");rejects([&]{SwgxrCarbineer::run(&c,q);});q=request;q["origin"]={0,0,3};rejects([&]{SwgxrCarbineer::run(&c,q);});q=request;q["target_id"]="77";rejects([&]{SwgxrCarbineer::run(&c,q);});++checks;}
 NativeFireHarness::Session session;int paid=c.paid;auto out=NativeFireHarness::fire(&c,session,request,10);assert(out["interval_seconds"]==.25 && c.paid-paid==75 && SwgxrCarbineer::active(&c));assert(SwgxrCarbineer::snapshot(&c)["tactical_brace"]["active_remaining_seconds"]==8);assert(SwgxrCarbineer::chance(&c,0)==95);rejects([&]{NativeFireHarness::fire(&c,session,request,11);});++checks;
 for(int gate=0;gate<3;++gate){if(gate==0)c.skills.erase("combat_carbine_ability_02");if(gate==1)weapon.carbine=false;if(gate==2)c.dead=true;SwgxrCarbineer::refresh(&c);assert(!SwgxrCarbineer::active(&c));c.skills.insert("combat_carbine_ability_02");weapon.carbine=true;c.dead=false;c.timers.clear();SwgxrCarbineer::run(&c,request);++checks;}c.buffs.clear();c.timers.clear();
 std::vector<CreatureObject> targets(10);server.zone.actors.clear();for(int i=0;i<10;++i){auto& t=targets[i];t.server=&server;t.id=100+i;t.position={0,0,double(3+(i%3))};server.zone.actors.push_back(&t);server.objects[t.id]=&t;}targets[0].pet=true;targets[1].los=false;targets[2].position.x=10;targets[3].dodge=true;
 request["shot_id"]="full_auto_sweep_one";request["ability_id"]="full_auto_sweep";paid=c.paid;out=NativeFireHarness::fire(&c,session,request,20);assert(c.paid-paid==120 && out["targets"].size()==5 && out["damage"]==200);assert(targets[0].strikes==0 && targets[1].strikes==0 && targets[2].strikes==0 && targets[3].strikes==1);assert(targets[3].buffs.empty());assert(out["targets"][0]["target_id"]=="103" && out["targets"][1]["target_id"]=="106" && out["targets"][2]["target_id"]=="109");++checks;
 // Native ultimate admission consumes one receipt; selected-ultimate requirement remains server-owned.
 request["shot_id"]="charge_blast_one";request["ability_id"]="charge_blast";SwgxrCombatLoadout::equipped=false;paid=c.paid;rejects([&]{NativeFireHarness::fire(&c,session,request,25);});assert(c.paid==paid);SwgxrCombatLoadout::equipped=true;targets[4].immune=true;targets[6].timers["corecu_control_recovery"]={8000};out=NativeFireHarness::fire(&c,session,request,25);assert(out["targets"].size()==6 && out["damage"]==375 && c.paid-paid==230);assert(!targets[4].isKnockedDown() && !targets[6].isKnockedDown() && targets[7].isKnockedDown());++checks;
 // Empty cone is an accepted miss, charged once, with no target borrowing.
 c.timers.clear();request["shot_id"]="sweep_empty_cone";request["ability_id"]="full_auto_sweep";request["direction"]={0,0,-1};paid=c.paid;out=NativeFireHarness::fire(&c,session,request,30);assert(out["targets"].empty() && c.paid-paid==120);rejects([&]{NativeFireHarness::fire(&c,session,request,31);});++checks;
 // VATS has independent physical receipt and retains damage when hard control is protected.
 resetTarget();a.timers["corecu_control_recovery"]={8000};c.timers.clear();Json shot={{"action","fire"},{"shot_id","charge_shot_one"},{"item_id","55"},{"ability_id","charge_shot"},{"target_id","77"},{"origin",{0,.65,0}},{"direction",{0,0,1}},{"two_hands",true}};paid=c.paid;out=NativeFireHarness::fire(&c,session,shot,40);assert(out["damage_multiplier"]==.8 && c.paid-paid==105);Json impact={{"action","impact"},{"shot_id","charge_shot_one"},{"target_id","77"},{"hit_position",{0,.65,5}},{"projectile_age_seconds",.04}};out=NativeFireHarness::fire(&c,session,impact,40.1);assert(out["damage"]==80 && !a.isKnockedDown() && System::attempts==0);rejects([&]{NativeFireHarness::fire(&c,session,impact,40.2);});++checks;
 shot["shot_id"]="wrong_family_one";shot["ability_id"]="wild_shot";weapon.carbine=false;rejects([&]{NativeFireHarness::fire(&c,session,shot,50);});weapon.carbine=true;shot.erase("target_id");rejects([&]{NativeFireHarness::fire(&c,session,shot,50);});shot["ability_id"]="full_auto_sweep";rejects([&]{NativeFireHarness::fire(&c,session,shot,50);});++checks;
 c.timers.clear();request["shot_id"]="sweep_volley_priority";request["ability_id"]="full_auto_sweep";request["direction"]={0,0,1};targets[8].position={0,0,-4};targets[8].los=false;targets[8].dodge=true;
 {corecu::volley::Scope scope(c.getObjectID(),targets[8].getObjectID());out=SwgxrCarbineer::run(&c,request);assert(out["targets"].size()==5 && out["targets"][0]["target_id"]=="108" && scope.resolved());++checks;}
 std::cout<<checks<<" native Carbineer grant, effect, cone, buff, route and physical receipt groups passed\n";
}
