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
struct CommandEffect {enum{INTIMIDATE};};struct BuffType {enum{STATE};};struct QueueCommand {enum{SUCCESS};};
struct CreatureObject;using AiAgent=CreatureObject;using SceneObject=CreatureObject;using TreeEntry=CreatureObject;
template<class T>using ManagedReference=T;
struct Locker {template<class A,class B>Locker(A,B){}};
struct Vec {double x=0,z=0,y=0;double getX()const{return x;}double getY()const{return y;}double getZ()const{return z;}};
struct Buff {unsigned key;int seconds;std::map<std::string,int> mods;Buff(CreatureObject*,unsigned id,int duration,int):key(id),seconds(duration){}void setSkillModifier(const char* k,int v){mods[k]=v;}float getTimeLeft(){return seconds;}};
struct Timer {int ms=0;int miliDifference(){return -ms;}};
struct WeaponTemplate {std::string path="object/weapon/ranged/pistol/pistol_dl44.iff";struct Name {std::string value;const char* toCharArray(){return value.c_str();}};Name getFullTemplateString(){return {path};}};
struct Weapon {WeaponTemplate templ;WeaponTemplate* getObjectTemplate(){return &templ;}bool flame=false;bool isFlameThrower(){return flame;}bool pistol=true,cert=true,broken=false,owned=true;uint64 id=55;double damage=100,range=32;
 bool isPistolWeapon(){return pistol;}bool isRangedWeapon(){return true;}bool isCertifiedFor(CreatureObject*){return cert;}bool isBroken(){return broken;}bool isASubChildOf(CreatureObject*){return owned;}uint64 getObjectID(){return id;}
 int getWeaponBitmask(){return 1;}double getMaxRange(){return range;}double getPointBlankRange(){return 0;}double getIdealRange(){return 16;}double getPointBlankAccuracy(){return 0;}double getIdealAccuracy(){return 0;}double getMaxRangeAccuracy(){return 0;}int getDamageType(){return 1;}int getArmorPiercing(){return 0;}double getMinDamage(){return damage;}double getMaxDamage(){return damage;}
};
using WeaponObject=Weapon;
struct ObjectRef {CreatureObject* value=nullptr;Weapon* weapon=nullptr;CreatureObject* operator->()const{return value;}CreatureObject* get(){return value;}bool operator!()const{return !value && !weapon;}bool operator==(std::nullptr_t)const{return !value && !weapon;}bool operator!=(std::nullptr_t)const{return value || weapon;}template<class T>T castTo(){return weapon;}};
struct CombatQueueCommand {virtual ~CombatQueueCommand(){}bool state=true;double hm=1,am=1,mm=1;bool checkStateMask(CreatureObject*)const{return state;}bool checkInvalidLocomotions(CreatureObject*)const{return state;}int getWeaponType()const{return 1;}double getDamageMultiplier()const{return 1;}double getHealthCostMultiplier()const{return hm;}double getActionCostMultiplier()const{return am;}double getMindCostMultiplier()const{return mm;}};
struct Controller {CombatQueueCommand command;const CombatQueueCommand* getQueueCommand(const char*){return &command;}};
template<class T>struct SortedVector:std::vector<T> {SortedVector(int,int){}T get(int i){return this->at(i);}};
struct Zone {uint64 getObjectID(){return 1;}std::vector<CreatureObject*> actors;void getInRangeObjects(double,double,double,double,SortedVector<TreeEntry*>* out,bool){for(auto a:actors)out->push_back(a);}};
struct Server {Controller controller;Zone zone;std::map<uint64,CreatureObject*> objects;Controller* getObjectController(){return &controller;}Weapon* weapon=nullptr;ObjectRef getObject(uint64 key){return {objects.count(key)?objects.at(key):nullptr,weapon && key==weapon->id?weapon:nullptr};}};
struct CreatureObject {Server* server=nullptr;Weapon* weapon=nullptr;uint64 id=77;Vec position;bool ai=true,pet=false,dead=false,incap=false,riding=false,attackable=true,los=true,immune=false,dodge=false;double resistance=0,height=1.;int ham[7]={10000,0,0,10000,0,0,10000};std::set<std::string> skills,grants;std::map<unsigned,Buff*> buffs;std::map<std::string,Timer> timers;int paid=0,strikes=0;
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
#include "pistoleer_native.inc"
struct SwgxrPreparedRangedCommand:CombatQueueCommand {explicit SwgxrPreparedRangedCommand(const CombatQueueCommand& s):CombatQueueCommand(s){}void setHealthCostMultiplier(double x){hm=x;}void setActionCostMultiplier(double x){am=x;}void setMindCostMultiplier(double x){mm=x;}void setForceCostMultiplier(double){} };
struct SwgxrConfirmedProjectileCommand:SwgxrPreparedRangedCommand {double damage=1;explicit SwgxrConfirmedProjectileCommand(const CombatQueueCommand& s):SwgxrPreparedRangedCommand(s){}void normalizeDamage(double,double){}void setRiflemanPiercing(bool){}void setDamageMultiplier(double x){damage=x;}void setPoolsToDamage(int){}int doCombatAction(CreatureObject* c,uint64 id,const char*,Weapon* w){auto a=c->server->objects.at(id);if(!a->attackable)return 1;++a->strikes;if(corecu::volley::claimHit(c->getObjectID(),a->getObjectID()) || !a->dodge)a->ham[0]-=int(w->damage*damage);return 0;}};
struct SwgxrVehicles {static double launchReach(CreatureObject*){return 2.5;}};
struct SwgxrCarbineer {static bool compatible(CreatureObject*){return false;}static bool targetReady(CreatureObject*){return false;}static void effects(CreatureObject*,CreatureObject*,const std::string&,int){}};
struct SwgxrRifleman {static bool compatible(CreatureObject*){return false;}static bool headUpgrade(CreatureObject*){return false;}static bool targetReady(CreatureObject*){return false;}static double damage(CreatureObject*,const std::string&){return 0;}static double focusScale(CreatureObject*,const std::string&){return 1;}static double interval(CreatureObject*,const std::string&){return 2;}};
struct SwgxrMarksman {static int actionCost(CreatureObject*,const std::string& id){return corecu::marksman::ability(id).action;}static void effects(CreatureObject*,CreatureObject*,const std::string&,int){}static bool compatible(CreatureObject*,const std::string&){return true;}static bool targetReady(CreatureObject* a,const std::string&){return SwgxrPistoleer::targetReady(a);}static double damage(CreatureObject*,const std::string& id){return corecu::marksman::ability(id).damage;}static double interval(CreatureObject*,const std::string& id){return corecu::marksman::ability(id).cooldown;}};
struct SwgxrSmuggler {static void effects(CreatureObject*,CreatureObject*,const std::string&){}static const CombatQueueCommand* command(CreatureObject* c,const std::string&){return &c->server->controller.command;}static bool learned(CreatureObject* c,const std::string& id){return !corecu::pistoleer::contains(id) || SwgxrPistoleer::learned(c,id);}static double cooldown(CreatureObject* c,const std::string& id){return SwgxrPistoleer::cooldown(c,id);}static double multiplier(CreatureObject*){return 2;}};
struct SwgxrSmugglerPolicy {static constexpr double concussionDamage=.5;};struct SwgxrSpice {static double cooldownScale(CreatureObject*){return 1;}};
struct SwgxrCombatLoadout {static uint64 revision;static bool equipped;static bool allows(CreatureObject*,const std::string& id){return id.empty() || equipped;}static Json saved(CreatureObject*){return {{"revision",revision}};}};uint64 SwgxrCombatLoadout::revision=1;bool SwgxrCombatLoadout::equipped=true;
// Native id accepts SceneObject; the isolated weapon also supplies that overload.
#include "tests/bounty_disabled_fixture.h"
#define private public
#include "pistoleer_fire.inc"
#undef private

template<class F>void rejects(F action){bool failed=false;try{action();}catch(const std::exception&){failed=true;}assert(failed);}
int main(){Server server;Weapon weapon;server.weapon=&weapon;CreatureObject c,a;c.server=a.server=&server;c.weapon=&weapon;c.ai=false;c.id=42;a.id=77;a.position={0,0,5};server.zone.actors={&a};server.objects[77]=&a;
 c.skills={"combat_pistol_novice","combat_pistol_support_02","combat_pistol_master"};c.grants={"doubleTap","disarmingShot1","fanShot","healthShot2"};
 assert(SwgxrPistoleer::learned(&c,"double_tap") && SwgxrPistoleer::learned(&c,"fan_shot"));
 c.skills.erase("combat_pistol_novice");assert(!SwgxrPistoleer::learned(&c,"fan_shot"));c.skills.insert("combat_pistol_novice");
 for(int gate=0;gate<5;++gate){a.ai=gate!=0;a.pet=gate==1;a.dead=gate==2;a.incap=gate==3;assert(SwgxrPistoleer::targetReady(&a)==(gate==4));}a.ai=true;a.pet=a.dead=a.incap=false;
 for(auto id:{"disarming_shot","showdown"}){a.buffs.clear();SwgxrPistoleer::effects(&c,&a,id,0);assert(a.buffs.empty());a.immune=true;SwgxrPistoleer::effects(&c,&a,id,10);assert(a.buffs.empty());a.immune=false;System::roll=99;SwgxrPistoleer::effects(&c,&a,id,10);assert(a.buffs.empty());System::roll=0;SwgxrPistoleer::effects(&c,&a,id,10);auto buff=a.buffs.begin()->second;assert(buff->seconds==(std::string(id)=="showdown"?5:6));assert(buff->mods.begin()->second==(std::string(id)=="showdown"?30:20));}
 corecu::warcry::Vec origin{{0,.65,0}},direction{{0,0,1}};assert(SwgxrPistoleer::eligible(&c,&a,origin,direction,12));assert(!SwgxrPistoleer::eligible(&c,&a,origin,{{0,1,0}},12));a.los=false;assert(!SwgxrPistoleer::eligible(&c,&a,origin,direction,12));a.los=true;
 Json gesture={{"shot_id","gesture_one"},{"item_id","55"},{"ability_id","run_and_gun"},{"origin",{0,.65,0}},{"direction",{0,0,1}}};
 int prior=c.paid;auto out=SwgxrPistoleer::run(&c,gesture);assert(c.paid-prior==120 && out["interval_seconds"]==.25 && SwgxrPistoleer::active(&c));assert(SwgxrPistoleer::interval(&c,"")==1.6 && SwgxrPistoleer::interval(&c,"double_tap")==2);assert(SwgxrPistoleer::snapshot(&c)["run_and_gun"]["active_remaining_seconds"]==8);rejects([&]{SwgxrPistoleer::run(&c,gesture);});
 c.skills.erase("combat_pistol_support_02");SwgxrPistoleer::refresh(&c);c.skills.insert("combat_pistol_support_02");assert(!SwgxrPistoleer::active(&c));c.timers.clear();SwgxrPistoleer::run(&c,gesture);weapon.pistol=false;SwgxrPistoleer::refresh(&c);weapon.pistol=true;assert(!SwgxrPistoleer::active(&c));
 std::vector<CreatureObject> targets(9);server.zone.actors.clear();for(int i=0;i<9;++i){auto& t=targets[i];t.server=&server;t.id=100+i;t.position={0,0,double(3+(i%3))};server.zone.actors.push_back(&t);server.objects[t.id]=&t;}targets[0].pet=true;targets[1].los=false;targets[2].position.x=10;targets[3].dodge=true;
 gesture["ability_id"]="fan_shot";prior=c.paid;out=SwgxrPistoleer::run(&c,gesture);assert(c.paid-prior==105 && out["targets"].size()==5 && out["damage"]==400);assert(targets[0].strikes==0 && targets[1].strikes==0 && targets[2].strikes==0 && targets[3].strikes==1);
 const auto ids=out["targets"];assert(ids[0]["target_id"]=="103" && ids[1]["target_id"]=="106" && ids[2]["target_id"]=="104" && ids[3]["target_id"]=="107" && ids[4]["target_id"]=="105");
 NativeFireHarness::Session session;Json shot={{"action","fire"},{"shot_id","showdown_one"},{"volley_id","showdown_one"},{"volley_index",0},{"item_id","55"},{"ability_id","showdown"},{"target_id","77"},{"origin",{0,.65,0}},{"direction",{0,0,1}}};
 prior=c.paid;out=NativeFireHarness::fire(&c,session,shot,100);assert(c.paid-prior==225 && out["ham_cost_committed"]==true && out["interval_seconds"]==.25 && session.shots.size()==1);assert(session.shots.at("showdown_one").multiplier==.9);
 rejects([&]{NativeFireHarness::fire(&c,session,shot,100.25);});shot["shot_id"]="showdown_two";shot["volley_index"]=1;
 rejects([&]{NativeFireHarness::fire(&c,session,shot,100.249);});shot["target_id"]="100";rejects([&]{NativeFireHarness::fire(&c,session,shot,100.25);});shot["target_id"]="77";
 ++SwgxrCombatLoadout::revision;rejects([&]{NativeFireHarness::fire(&c,session,shot,100.25);});--SwgxrCombatLoadout::revision;
 weapon.damage=200;rejects([&]{NativeFireHarness::fire(&c,session,shot,100.25);});weapon.damage=100;
 a.pet=true;rejects([&]{NativeFireHarness::fire(&c,session,shot,100.25);});a.pet=false;
 prior=c.paid;shot["direction"]={1,0,0};out=NativeFireHarness::fire(&c,session,shot,100.25);assert(c.paid==prior && out["ham_cost_committed"]==false && session.shots.size()==2);assert(session.shots.at("showdown_two").direction[0]==1);
 rejects([&]{NativeFireHarness::fire(&c,session,shot,100.5);});shot["shot_id"]="showdown_three";shot["volley_index"]=2;shot["direction"]={0,0,-1};out=NativeFireHarness::fire(&c,session,shot,100.5);assert(c.paid==prior && session.shots.size()==3 && out["interval_seconds"]==2.);assert(session.shots.at("showdown_three").direction[2]==-1);
 shot["shot_id"]="showdown_four";rejects([&]{NativeFireHarness::fire(&c,session,shot,100.75);});
 assert(!session.volleys.at("showdown_one").effect(0));assert(session.volleys.at("showdown_one").effect(10));assert(!session.volleys.at("showdown_one").effect(20));
 // The actual impact branch consumes independent receipts and attempts suppression once,
 // even when the first damaging attempt is resisted. No future hit borrows another aim.
 auto& volley=session.volleys.at("showdown_one");volley.effectAttempted=false;System::attempts=0;System::roll=99;a.buffs.clear();int health=a.ham[0];
 Json impact={{"action","impact"},{"shot_id","showdown_one"},{"target_id","77"},{"hit_position",{0,.65,5}},{"projectile_age_seconds",.04}};
 out=NativeFireHarness::fire(&c,session,impact,100.6);assert(out["damage"]==90 && out["resolved_hits"]==1 && System::attempts==1 && a.buffs.empty());
 rejects([&]{NativeFireHarness::fire(&c,session,impact,100.7);});
 impact["shot_id"]="showdown_two";impact["hit_position"]={5,.65,0};out=NativeFireHarness::fire(&c,session,impact,100.7);assert(out["damage"]==90 && System::attempts==1);
 impact["shot_id"]="showdown_three";impact["target_id"]="100";impact["hit_position"]={0,.65,-5};rejects([&]{NativeFireHarness::fire(&c,session,impact,100.8);});impact["target_id"]="77";rejects([&]{NativeFireHarness::fire(&c,session,impact,100.9);});assert(a.ham[0]==health-180);System::roll=0;
 // Active buff discounts fixed and mixed-profession costs without changing special cadence.
 c.timers.clear();gesture["ability_id"]="run_and_gun";SwgxrPistoleer::run(&c,gesture);shot.erase("volley_id");shot.erase("volley_index");shot["shot_id"]="double_tap_one";shot["ability_id"]="double_tap";prior=c.paid;out=NativeFireHarness::fire(&c,session,shot,103);assert(c.paid-prior==60 && out["interval_seconds"]==2.);
 shot["shot_id"]="mixed_pistol_one";shot["ability_id"]="restraining_shot";prior=c.paid;out=NativeFireHarness::fire(&c,session,shot,105);assert(c.paid-prior==15 && out["interval_seconds"]==2.);
 shot["shot_id"]="ordinary_pistol";shot["ability_id"]="";shot.erase("target_id");prior=c.paid;out=NativeFireHarness::fire(&c,session,shot,107);assert(c.paid-prior==20 && out["interval_seconds"]==1.6);
 c.buffs.clear();c.timers.clear();a.dodge=true;a.los=false;shot["shot_id"]="double_tap_guaranteed";shot["ability_id"]="double_tap";shot["target_id"]="77";shot["direction"]={0,0,-1};health=a.ham[0];
 {corecu::volley::Scope scope(c.getObjectID(),a.getObjectID());NativeFireHarness::fire(&c,session,shot,200);impact["shot_id"]="double_tap_guaranteed";impact["hit_position"]={0,.65,5};impact["target_id"]="77";impact["projectile_age_seconds"]=0.;out=NativeFireHarness::fire(&c,session,impact,200.01);assert(out["resolved_hits"]==2 && a.ham[0]==health-80 && scope.resolved());}a.dodge=false;a.los=true;
 c.timers.clear();c.buffs.clear();targets[8].position={0,0,-4};targets[8].los=false;targets[8].dodge=true;gesture["ability_id"]="fan_shot";gesture["shot_id"]="fan_guaranteed_priority";gesture["direction"]={0,0,1};
 {corecu::volley::Scope scope(c.getObjectID(),targets[8].getObjectID());out=SwgxrPistoleer::run(&c,gesture);assert(out["targets"].size()==5 && out["targets"][0]["target_id"]=="108" && scope.resolved());}
 std::cout<<"Actual Pistoleer grants/effects/buff lifecycle/Fan cone+cap/order and native launch receipt cases passed\n";
}
