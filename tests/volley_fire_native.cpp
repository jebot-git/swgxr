#include "server/combat/VolleyFirePolicy.h"
#include "server/combat/MeleePolicy.h"
#include "server/combat/ProjectileContactPolicy.h"
#include "server/combat/PistoleerPolicy.h"
#include "server/combat/CommandoPolicy.h"
#include "server/combat/TkaPolicy.h"
#include "server/combat/CarbineerPolicy.h"
#include <nlohmann/json.hpp>
#include <cassert>
#include <iostream>
#include <functional>
#include <thread>
#include <condition_variable>
using Json=nlohmann::json;using JSONSerializationType=Json;using uint64=uint64_t;
long long testNow=100000;int checks=0;void check(bool b,const char* message){++checks;if(!b)throw std::runtime_error(message);}
struct String:std::string {using std::string::string;String(std::string s):std::string(s){}bool isEmpty()const{return empty();}const char* toCharArray()const{return c_str();}};
struct CreatureObject;struct Zone{uint64 getObjectID(){return 1;}};struct Group;
struct Vec{double x=0,y=0,z=0;double getX(){return x;}double getY(){return y;}double getZ(){return z;}};
struct SceneObject {virtual ~SceneObject(){}uint64 oid=0,parent=0;Zone* zone=nullptr;Vec pos;bool player=false,ai=false,dead=false,incap=false,attackable=true,destroyed=false,lair=false,pet=false,los=true;
 uint64 getObjectID(){return oid;}uint64 getParentID(){return parent;}Zone* getZone(){return zone;}Vec getWorldPosition(){return pos;}bool isPlayerCreature(){return player;}bool isCreatureObject(){return player||ai;}bool isTangibleObject(){return true;}bool isAiAgent(){return ai;}bool isLairObject(){return lair;}bool isDestroyed(){return destroyed;}bool isAttackableBy(CreatureObject*){return attackable;}SceneObject* asTangibleObject(){return this;}CreatureObject* asAiAgent();CreatureObject* asCreatureObject();};
using TangibleObject=SceneObject;template<class T>using ManagedReference=T;
struct WeaponObject:SceneObject{bool certified=true,broken=false,owned=true,melee=false,unarmed=false,heavy=false;double range=64;bool isCertifiedFor(CreatureObject*){return certified;}bool isBroken(){return broken;}bool isASubChildOf(CreatureObject*){return owned;}bool isMeleeWeapon(){return melee;}bool isRangedWeapon(){return !melee;}bool isUnarmedWeapon(){return unarmed;}bool isPistolWeapon(){return !melee;}double getMaxRange(){return range;}};
struct Server{std::map<uint64,SceneObject*> objects;SceneObject* getObject(uint64 id){return objects.count(id)?objects.at(id):nullptr;}};
struct CreatureObject:SceneObject {bool online=true,mount=false,master=false,volleyGrant=true;Group* group=nullptr;Server* server=nullptr;WeaponObject* weapon=nullptr;int ham[7]={1000,0,0,1000,0,0,1000};std::map<std::string,String> saved;
 bool isOnline(){return online;}bool isDead(){return dead;}bool isIncapacitated(){return incap;}bool isPet(){return pet;}bool isRidingMount(){return mount;}bool isGrouped(){return group!=nullptr;}bool hasSkill(const char*){return master;}bool hasAbility(const char*){return volleyGrant;}CreatureObject* getPlayerObject(){return this;}WeaponObject* getWeapon(){return weapon;}Group* getGroup(){return group;}uint64 getGroupID();Server* getZoneServer(){return server;}double getHeight(bool){return 1.8;}int getHAM(int i){return ham[i];}void inflictDamage(CreatureObject*,int i,int d,bool,bool,bool){ham[i]-=d;}double getDistanceTo(SceneObject* a){return std::sqrt(std::pow(pos.x-a->pos.x,2)+std::pow(pos.y-a->pos.y,2)+std::pow(pos.z-a->pos.z,2));}String getScreenPlayData(const char* domain,const char* key){return saved[std::string(domain)+key];}void setScreenPlayData(const char* domain,const char* key,String value){saved[std::string(domain)+key]=value;}
};
CreatureObject* SceneObject::asAiAgent(){return static_cast<CreatureObject*>(this);}CreatureObject* SceneObject::asCreatureObject(){return static_cast<CreatureObject*>(this);}
struct Group{uint64 oid=30;std::vector<CreatureObject*> members;uint64 getObjectID(){return oid;}int getGroupSize(){return members.size();}CreatureObject* getGroupMember(int i){return members.at(i);}};
uint64 CreatureObject::getGroupID(){return group?group->oid:0;}
struct Mutex{std::mutex mutex;};struct Locker{std::unique_lock<std::mutex> lock;Locker(Mutex* m,CreatureObject*):lock(m->mutex){}template<class A,class B>Locker(A,B){} };
struct CollisionManager{static bool checkLineOfSight(CreatureObject*,SceneObject* a){return a->los;}};
#include "volley_native.inc"
using AiAgent=CreatureObject;
#include "volley_geometry.inc"
struct SwgxrCommando{static bool supported(WeaponObject* w){return w->heavy;}static corecu::commando::Family family(WeaponObject*){return corecu::commando::Rocket;}};
class NativeVolleyRoute {public:
 using Json=JSONSerializationType;struct Session{int launches=0,impacts=0;bool spent=false,reject=false;};
 static std::string id(SceneObject* o){return std::to_string(o->getObjectID());}static Json position(SceneObject* o){auto p=o->getWorldPosition();return Json::array({p.x,p.z,p.y});}
 static Json action(CreatureObject* c,Session& s,const Json& q){if(s.reject)throw std::runtime_error("insufficient_ham");if(q["action"]=="fire"){++s.launches;c->ham[3]-=10;return {{"success",true},{"interval_seconds",1.},{"ham_cost_committed",true}};}if(s.spent)throw std::runtime_error("spent_shot");s.spent=true;++s.impacts;auto target=std::stoull(q.at("target_id").get<std::string>());bool hit=corecu::volley::claimHit(c->oid,target);return {{"success",true},{"damage",hit?100:0},{"target_id",std::to_string(target)}};}
#include "volley_route.inc"
};
struct Fixture {Zone zone;Server server;Group group;WeaponObject w;CreatureObject leader,friend1,friend2,enemy;
 Fixture(uint64 serial){group.oid=serial+30;w.oid=serial+10;w.zone=&zone;leader.oid=serial+1;friend1.oid=serial+2;friend2.oid=serial+3;enemy.oid=serial+4;leader.master=true;for(auto c:{&leader,&friend1,&friend2}){c->player=true;c->server=&server;c->zone=&zone;c->group=&group;c->weapon=&w;group.members.push_back(c);server.objects[c->oid]=c;}enemy.ai=true;enemy.zone=&zone;enemy.server=&server;enemy.pos.x=10;server.objects[enemy.oid]=&enemy;}
 Json activate(){return SwgxrVolleyFire::activate(&leader,{{"item_id",std::to_string(w.oid)},{"target_id",std::to_string(enemy.oid)},{"shot_id","cast_123456"}});}
 Json intent(CreatureObject* c){auto mark=SwgxrVolleyFire::snapshot(c)["mark"];return {{"volley_mark_id",mark.at("id")},{"volley_target_id",mark.at("target_id")}};}
};
template<class F>void rejects(F fn,const char* message){bool rejected=false;try{fn();}catch(const std::exception&){rejected=true;}check(rejected,message);}
int main(){
 {corecu::volley::Scope a(1,2);check(corecu::volley::guaranteed(1,2),"exact target active");check(!corecu::volley::guaranteed(1,3),"splash cannot claim mark");check(corecu::volley::claimHit(1,2),"first packet guaranteed");check(!corecu::volley::claimHit(1,2),"later multi-hit packet ordinary");check(corecu::volley::guaranteed(1,2),"geometry binding retained for attack");{corecu::volley::Scope b(3,4);check(!corecu::volley::guaranteed(1,2),"nested scope isolated");}check(a.resolved(),"resolved flag retained");}
 check(!corecu::volley::guaranteed(1,2),"scope restored");
 Fixture geometry(1000);geometry.enemy.pos={3,0,0};geometry.enemy.los=false;corecu::warcry::Vec feet{{0,0,0}},backward{{0,0,-1}};corecu::tka::Attack shape{3,.5,1,1,1,1,1,1,1};
 check(!TkaGeometry::eligible(&geometry.friend1,&geometry.enemy,feet,backward,shape),"ordinary TKA keeps facing and LOS");
 {corecu::volley::Scope scope(geometry.friend1.oid,geometry.enemy.oid);check(TkaGeometry::eligible(&geometry.friend1,&geometry.enemy,feet,backward,shape),"TKA marked geometry skips aim and LOS within native range");
  for(auto rule:{SwordsmanGeometry::eligible,PikemanGeometry::eligible,FencerGeometry::eligible}){check(rule(&geometry.friend1,&geometry.enemy,feet,backward,3,.9),"melee profession guarantees geometry within native range");check(!rule(&geometry.friend1,&geometry.enemy,feet,backward,2,.9),"melee profession keeps native reach");geometry.enemy.pet=true;check(!rule(&geometry.friend1,&geometry.enemy,feet,backward,3,.9),"guarantee never bypasses legal target eligibility");geometry.enemy.pet=false;}}
 Fixture f(100);f.leader.volleyGrant=false;rejects([&]{f.activate();},"master alone cannot bypass original Volley Fire grant");f.leader.volleyGrant=true;auto grant=f.activate();check(grant["eligible_members"]==3,"one initial charge for each current member");check(f.leader.ham[3]==920&&f.leader.ham[6]==960,"caster pays one support action");check(SwgxrVolleyFire::cooldown(&f.leader)==120,"caster persistent cooldown");check(SwgxrVolleyFire::receivedCooldown(&f.friend1)==120,"recipient persistent cooldown");
 auto a=f.intent(&f.friend1),b=f.intent(&f.friend2);f.enemy.los=false;
 auto out=SwgxrVolleyFire::attack(&f.friend1,a,10,[&](TangibleObject* target){check(target==&f.enemy,"native target selected");check(corecu::volley::claimHit(f.friend1.oid,f.enemy.oid),"guaranteed through obstruction");check(!corecu::volley::claimHit(f.friend1.oid,f.enemy.oid),"one guarantee only");return Json{{"success",true},{"damage",0}};});
 check(out["volley_consumed"]==true,"fully absorbed valid hit consumes");check(SwgxrVolleyFire::snapshot(&f.friend1)["mark"].is_null(),"own reticle disappears");check(!SwgxrVolleyFire::snapshot(&f.friend2)["mark"].is_null(),"other member retains reticle");
 rejects([&]{SwgxrVolleyFire::attack(&f.friend1,a,10,[](TangibleObject*){return Json::object();});},"duplicate mark request rejected");
 rejects([&]{SwgxrVolleyFire::attack(&f.friend2,b,9,[](TangibleObject*){return Json::object();});},"strict native range no epsilon");check(!SwgxrVolleyFire::snapshot(&f.friend2)["mark"].is_null(),"out of range does not consume");
 rejects([&]{SwgxrVolleyFire::attack(&f.friend2,b,10,[](TangibleObject*)->Json{throw std::runtime_error("insufficient_ham");});},"resource rejection retained");check(!SwgxrVolleyFire::snapshot(&f.friend2)["mark"].is_null(),"rejected resources no consumption");
 SwgxrVolleyFire::attack(&f.friend2,b,10,[&](TangibleObject*){rejects([&]{SwgxrVolleyFire::attack(&f.friend2,b,10,[](TangibleObject*){return Json::object();});},"atomic in-flight reservation blocks duplicate");return Json{{"success",false}};});
 check(!SwgxrVolleyFire::snapshot(&f.friend2)["mark"].is_null(),"rejected native action releases reservation");
 auto wrong=b;wrong["volley_target_id"]="999999";rejects([&]{SwgxrVolleyFire::attack(&f.friend2,wrong,64,[](TangibleObject*){return Json::object();});},"client cannot substitute target");
 corecu::volley::leave(f.friend2.oid);check(SwgxrVolleyFire::snapshot(&f.friend2)["mark"].is_null(),"leave/rejoin same group invalidates captured charge");
 Fixture fresh(200);fresh.activate();auto r=fresh.intent(&fresh.friend1);r["action"]="fire";r["ability_id"]="";r["shot_id"]="shot_123456";r["session_id"]="session_123456";NativeVolleyRoute::Session session;
 auto routed=NativeVolleyRoute::volleyAction(&fresh.friend1,session,r);check(session.launches==1&&session.impacts==1&&session.spent,"registered launch resolves one receipt without physical impact");check(routed["damage"]==100&&routed["volley_consumed"]==true,"result reports one guaranteed attack");check(fresh.friend1.ham[3]==990,"launch resources only once");
 auto mark=fresh.intent(&fresh.friend2);corecu::volley::leave(fresh.leader.oid);check(SwgxrVolleyFire::snapshot(&fresh.friend2)["mark"].is_null(),"source leaving invalidates remaining group mark");
 Fixture pending(300);pending.activate();auto pendingIntent=pending.intent(&pending.friend1);out=SwgxrVolleyFire::attack(&pending.friend1,pendingIntent,32,[](TangibleObject*){return Json{{"volley_deferred",true},{"success",true}};});check(out["volley_consumed"]==true,"accepted delayed throw reserves own charge once");
 Fixture expired(400);expired.activate();auto expiredIntent=expired.intent(&expired.friend1);testNow+=12001;check(SwgxrVolleyFire::snapshot(&expired.friend1)["mark"].is_null(),"mark expires after twelve seconds");expired.friend1.master=true;rejects([&]{SwgxrVolleyFire::activate(&expired.friend1,{{"item_id",std::to_string(expired.w.oid)},{"target_id",std::to_string(expired.enemy.oid)},{"shot_id","cast_again"}});},"second Squad Leader cannot chain recipient ultimates");
 Fixture join(500);join.activate();CreatureObject newcomer;newcomer.oid=999;newcomer.player=true;newcomer.server=&join.server;newcomer.zone=&join.zone;newcomer.group=&join.group;join.group.members.push_back(&newcomer);check(SwgxrVolleyFire::snapshot(&newcomer)["mark"].is_null(),"late party join never mints charge");
 std::cout<<checks<<" production Volley Fire activation, reservations, membership, cooldown, launch and single-packet guarantee checks passed\n";
}
