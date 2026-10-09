#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <ctime>
#include <iostream>
#include <map>
#include <set>
#include <string>
#include <vector>
using uint64=uint64_t;using uint32=uint32_t;
static int checks=0;
void require(bool value,const char* message){++checks;if(!value){std::cerr<<"FAIL: "<<message<<"\n";std::exit(1);}}
struct Exception{};
namespace Math {template<class T> T min(T a,T b){return std::min(a,b);}template<class T>T max(T a,T b){return std::max(a,b);}}
namespace PerformanceType {constexpr int DANCE=1,MUSIC=2;}
namespace PerformanceBuffType {constexpr int DANCE_MIND=1,MUSIC_FOCUS=2,MUSIC_WILLPOWER=3;}
namespace SessionFacadeType {constexpr int ENTERTAINING=1;}
namespace BuffType {constexpr int FOOD=1,MEDICAL=2,PERFORMANCE=3,OTHER=4;}
uint32 hashcode(const char* s){uint32 hash=2166136261u;while(*s)hash=(hash^uint32(*s++))*16777619u;return hash;}
#define STRING_HASHCODE(s) hashcode(s)
template<class T>class ManagedReference {T pointer{};public:ManagedReference()=default;ManagedReference(T p):pointer(p){}operator T()const{return pointer;}T operator->()const{return pointer;}T get()const{return pointer;}template<class U>ManagedReference<U> castTo()const{return dynamic_cast<U>(pointer);}};
template<class T,class U>T cast(U* p){return dynamic_cast<T>(p);}template<class T,class U>T cast(ManagedReference<U> p){return dynamic_cast<T>(p.get());}
template<class T>class SortedVector {std::vector<T> rows;public:SortedVector(int=0,int=0){}int size()const{return rows.size();}T get(int n)const{return rows.at(n);}void add(T x){rows.push_back(x);}bool contains(T x)const{return std::find(rows.begin(),rows.end(),x)!=rows.end();}};
struct Locker {template<class T>Locker(T){}template<class T,class U>Locker(T,U){}void release(){}};
class CreatureObject;class EntertainingSessionImplementation;using EntertainingSession=EntertainingSessionImplementation;class PlayerManager;class ZoneServer;
struct TreeEntry {virtual ~TreeEntry()=default;};
struct SceneObject:TreeEntry {virtual bool isPlayerCreature(){return false;}virtual CreatureObject* asCreatureObject(){return nullptr;}};
struct Position {float x=0,y=0,z=0;float getX()const{return x;}float getY()const{return y;}float getZ()const{return z;}};
class Zone {public:std::vector<SceneObject*> objects;void getInRangeObjects(float,float,float,float,SortedVector<TreeEntry*>* result,bool){for(auto object:objects)result->add(object);}};
struct PlayerObject{};struct Instrument{};
struct Performance {int kind=1;int getType(){return kind;}int getHealShockWound(){return 10;}};
struct PerformanceManager {Performance dance{1},music{2};Performance* getPerformanceFromIndex(int i){return i==1?&dance:i==2?&music:nullptr;}};
struct SkillManager {PerformanceManager performances;static SkillManager* instance(){static SkillManager one;return &one;}PerformanceManager* getPerformanceManager(){return &performances;}};
struct Buff {virtual ~Buff()=default;};
struct PerformanceBuff:Buff {CreatureObject* owner;uint32 crc;float strength;int duration,type;PerformanceBuff(CreatureObject* c,uint32 h,float s,int d,int t):owner(c),crc(h),strength(s),duration(d),type(t){}float getBuffStrength(){return strength;}};
class CreatureObject:public SceneObject {
public:
 uint64 oid,watch=0,listen=0,parent=0;Zone* zone;ZoneServer* server=nullptr;Position pos;
 bool online=true,dead=false,incap=false,combat=false,invisible=false,hostile=false,healable=true,los=true,pet=false;
 int skill=0,adds=0,renews=0,throwOnAdd=0;std::array<int,9> ham{},maximum{},wounds{},base{};
 EntertainingSession* performance=nullptr;std::map<uint32,PerformanceBuff*> buffs;Instrument instrument;
 CreatureObject(uint64 id,Zone* z):oid(id),zone(z){ham.fill(400);maximum.fill(1000);base=maximum;}
 bool isPlayerCreature()override{return true;}CreatureObject* asCreatureObject()override{return this;}
 bool isOnline(){return online;}bool isDead(){return dead;}bool isIncapacitated(){return incap;}bool isInCombat(){return combat;}bool isInvisible(){return invisible;}bool isPet(){return pet;}
 bool isAttackableBy(CreatureObject*){return hostile;}bool isHealableBy(CreatureObject*){return healable;}
 bool isDancing();bool isPlayingMusic();Zone* getZone(){return zone;}uint64 getParentID(){return parent;}uint64 getObjectID(){return oid;}
 uint64 getWatchToID(){return watch;}uint64 getListenID(){return listen;}ZoneServer* getZoneServer(){return server;}Position getWorldPosition(){return pos;}
 bool isInRange(CreatureObject* other,float radius){return std::sqrt(std::pow(pos.x-other->pos.x,2)+std::pow(pos.y-other->pos.y,2)+std::pow(pos.z-other->pos.z,2))<=radius;}
 ManagedReference<EntertainingSession*> getActiveSession(int){return performance;}
 int getSkillMod(const char*){return skill;}Instrument* getPlayableInstrument(){return &instrument;}
 int getHAM(int i){return ham[i];}int getMaxHAM(int i){return maximum[i];}int getWounds(int i){return wounds[i];}void setHAM(int i,int v){ham[i]=v;}
 Buff* getBuff(uint32 crc){return buffs.count(crc)?buffs[crc]:nullptr;}
 void addBuff(PerformanceBuff* buff);void renewBuff(uint32 crc,int duration,bool){++renews;buffs.at(crc)->duration=std::max(duration,buffs.at(crc)->duration);}
 void sendSystemMessage(const char*){}
 void removeBuff(uint32 crc){if(!buffs.count(crc))return;auto buff=buffs.at(crc);int pool=buff->type==1?6:buff->type==2?7:8;maximum[pool]-=std::lround(base[pool]*buff->strength);ham[pool]=std::min(ham[pool],maximum[pool]-wounds[pool]);buffs.erase(crc);}
};
struct CollisionManager {static bool checkLineOfSight(CreatureObject* a,CreatureObject* b){return a->los && b->los;}};
struct Data {int started=int(time(0)),strength=0,duration=0;};
struct PatronMap {std::map<CreatureObject*,Data> rows;bool contains(CreatureObject* c){return rows.count(c);}};
class EntertainingSessionImplementation {
public:
 ManagedReference<CreatureObject*> entertainer;PatronMap patronDataMap;int performanceIndex;bool permitted=true;std::set<CreatureObject*> denied;
 struct Self {EntertainingSession* ptr;EntertainingSession* getReferenceUnsafeStaticCast(){return ptr;}}_this;
 EntertainingSessionImplementation(CreatureObject* c,int type):entertainer(c),performanceIndex(type),_this{this}{c->performance=this;}
 bool isDancing(){return performanceIndex==1;}bool isPlayingMusic(){return performanceIndex==2;}bool canGiveEntertainBuff(){return permitted;}bool isInDenyServiceList(CreatureObject* c){return denied.count(c);}
 void addPatron(CreatureObject* c){patronDataMap.rows[c]=Data();}void removePatron(CreatureObject* c){patronDataMap.rows.erase(c);}
 SortedVector<ManagedReference<CreatureObject*>> getPatrons(){SortedVector<ManagedReference<CreatureObject*>> out;for(auto& row:patronDataMap.rows)out.add(row.first);return out;}
 int getEntertainerBuffStartTime(CreatureObject* c,int){return patronDataMap.contains(c)?patronDataMap.rows[c].started:0;}
 int getEntertainerBuffDuration(CreatureObject* c,int){return patronDataMap.contains(c)?patronDataMap.rows[c].duration:0;}
 int getEntertainerBuffStrength(CreatureObject* c,int){return patronDataMap.contains(c)?patronDataMap.rows[c].strength:0;}
 void addEntertainerBuffDuration(CreatureObject* c,int,float amount){if(patronDataMap.contains(c))patronDataMap.rows[c].duration=std::min(120,patronDataMap.rows[c].duration+int(amount));}
 void addEntertainerBuffStrength(CreatureObject* c,int,float amount){if(patronDataMap.contains(c))patronDataMap.rows[c].strength=std::min(125,patronDataMap.rows[c].strength+int(amount));}
 void cancelSession(){performanceIndex=0;}
 void activateEntertainerBuff(CreatureObject*,int);void increaseEntertainerBuff(CreatureObject*);
};
bool CreatureObject::isDancing(){return performance && performance->isDancing();}bool CreatureObject::isPlayingMusic(){return performance && performance->isPlayingMusic();}
class ZoneServer {public:std::map<uint64,SceneObject*> objects;PlayerManager* manager;ManagedReference<SceneObject*> getObject(uint64 id){return objects.count(id)?objects[id]:nullptr;}PlayerManager* getPlayerManager(){return manager;}};
class PlayerManager {
public:ZoneServer* server;int joins=0,leaves=0;
 void stop(CreatureObject* c,uint64 id,bool dance){++leaves;auto source=server->getObject(id);if(source){auto session=source->asCreatureObject()->performance;if(session){session->activateEntertainerBuff(c,dance?1:2);session->removePatron(c);}}if(dance)c->watch=0;else c->listen=0;}
 void stopWatch(CreatureObject* c,uint64 id,bool=true,bool=false,bool=false,bool=false){stop(c,id,true);}void stopListen(CreatureObject* c,uint64 id,bool=true,bool=false,bool=false,bool=false){stop(c,id,false);}
 void start(CreatureObject* c,uint64 id,bool dance){auto old=dance?c->watch:c->listen;if(old==id)return;if(old)stop(c,old,dance);++joins;auto source=server->getObject(id);source->asCreatureObject()->performance->addPatron(c);if(dance)c->watch=id;else c->listen=id;}
 void startWatch(CreatureObject* c,uint64 id){start(c,id,true);}void startListen(CreatureObject* c,uint64 id){start(c,id,false);}
};
#include "fill.inc"
void CreatureObject::addBuff(PerformanceBuff* buff){++adds;removeBuff(buff->crc);int pool=buff->type==1?6:buff->type==2?7:8;int amount=std::lround(base[pool]*buff->strength);maximum[pool]+=amount;if(nativeFills(this,BuffType::PERFORMANCE))ham[pool]=std::min(ham[pool]+amount,maximum[pool]-wounds[pool]);buffs[buff->crc]=buff;if(throwOnAdd==adds)throw Exception();}
#include "audience.inc"
#include "effects.inc"
struct Fixture {
 Zone zone,otherZone;ZoneServer server;PlayerManager manager;CreatureObject dancer{1,&zone},otherDancer{2,&zone},musician{3,&zone},a{11,&zone},b{12,&zone},c{13,&zone};
 EntertainingSession dance{&dancer,1},otherDance{&otherDancer,1},music{&musician,2};
 Fixture(){server.manager=&manager;manager.server=&server;for(auto actor:{&dancer,&otherDancer,&musician,&a,&b,&c}){actor->server=&server;server.objects[actor->oid]=actor;zone.objects.push_back(actor);}a.pos.x=2;b.pos.x=4;c.pos.x=8;}
 void sync(){SwgxrEntertainerAudience::synchronize(&dancer,&dance);}
 void ready(EntertainingSession& s,CreatureObject& p,int strength=50,int duration=30){auto& data=s.patronDataMap.rows.at(&p);data.started=int(time(0))-65;data.strength=strength;data.duration=duration;}
};
int main(){
 {
  Fixture f;f.sync();require(f.dance.getPatrons().size()==3,"all nongroup patrons join radius without selected buff target");require(f.manager.joins==3,"one native join per eligible patron");f.sync();require(f.manager.joins==3,"repeated tick does not reset attendance or duplicate join");
  auto began=f.dance.getEntertainerBuffStartTime(&f.a,1);f.sync();require(began==f.dance.getEntertainerBuffStartTime(&f.a,1),"attendance preserved across scans");
  SwgxrEntertainerAudience::synchronize(&f.otherDancer,&f.otherDance);require(f.otherDance.getPatrons().size()==0,"overlapping same-kind performers cannot stack patron effects");
  SwgxrEntertainerAudience::synchronize(&f.musician,&f.music);require(f.music.getPatrons().size()==3,"independent music and dance channels coexist");
  f.a.pos.x=8.01;f.b.pos.z=20;f.c.parent=10;f.sync();require(f.dance.getPatrons().size()==0,"snapshot cleanup removes multiple simultaneous invalid patrons");require(f.a.watch==0 && f.b.watch==0 && f.c.watch==0,"range and cell transitions clear native channel");require(f.a.listen==3,"dance cleanup does not disturb music channel");
  SwgxrEntertainerAudience::synchronize(&f.musician,&f.music);require(f.music.getPatrons().size()==0,"music independently cleans invalid members");
 }
 {
  Fixture f;
  for(auto flag:{&CreatureObject::online,&CreatureObject::dead,&CreatureObject::incap,&CreatureObject::combat,&CreatureObject::invisible,&CreatureObject::hostile,&CreatureObject::healable,&CreatureObject::los}){
   bool original=f.a.*flag;f.a.*flag=!original;require(!SwgxrEntertainerAudience::eligible(&f.dancer,&f.a,&f.dance),"native availability/friendliness/LOS gates reject patron");f.a.*flag=original;
  }
  f.a.zone=&f.otherZone;require(!SwgxrEntertainerAudience::eligible(&f.dancer,&f.a,&f.dance),"different planet rejected");f.a.zone=&f.zone;
  f.dance.denied.insert(&f.a);f.sync();require(!f.dance.patronDataMap.contains(&f.a),"deny-service target is excluded");f.dance.denied.clear();f.dance.permitted=false;f.sync();require(f.dance.getPatrons().size()==0,"native location/skill gate removes recipients");f.dance.permitted=true;f.sync();require(f.dance.getPatrons().size()==3,"location eligibility recovers automatically");
  f.a.combat=true;f.b.online=false;f.c.dead=true;f.sync();require(f.dance.getPatrons().size()==0,"combat logout death clean all affected patrons");
 }
 {
  Fixture f;f.sync();f.dancer.online=false;f.sync();require(f.dance.getPatrons().size()==0,"offline source drops all native audience members");require(f.a.watch==0 && f.b.watch==0 && f.c.watch==0,"offline source leaves no stale channel");
  SwgxrEntertainerAudience::synchronize(&f.otherDancer,&f.otherDance);require(f.otherDance.getPatrons().size()==3,"remaining performer takes released source channel");
  // A stale former-source map must not stop a patron's newer source.
  f.dance.addPatron(&f.a);f.sync();require(f.a.watch==2 && f.otherDance.patronDataMap.contains(&f.a),"stale-map cleanup cannot redirect stopWatch to new source");
 }
 {
  Fixture f;f.sync();auto before=f.a.ham;f.dance.increaseEntertainerBuff(&f.a);require(f.a.adds==0,"flourish accrual never activates inspiration");SwgxrEntertainerAudience::deliver(&f.dancer,&f.a,&f.dance,1);require(f.a.adds==0,"under-one-minute attendance has no inspiration");
  f.ready(f.dance,f.a);SwgxrEntertainerAudience::deliver(&f.dancer,&f.a,&f.dance,1);require(f.a.adds==1,"eligible patron automatically gains earned inspiration without stopping");require(f.a.ham==before,"first native inspiration changes maximum without resource refill");require(f.a.maximum[6]==1500,"original strength scales native Mind maximum");
  f.a.ham[6]=1400;before=f.a.ham;f.dance.patronDataMap.rows[&f.a].duration=40;SwgxrEntertainerAudience::deliver(&f.dancer,&f.a,&f.dance,1);require(f.a.adds==1 && f.a.renews==1,"equal-strength inspiration renews existing native buff");require(f.a.ham==before,"equal-strength renewal preserves current resources above base cap");
  f.dance.patronDataMap.rows[&f.a].strength=75;SwgxrEntertainerAudience::deliver(&f.dancer,&f.a,&f.dance,1);require(f.a.ham==before,"stronger replacement restores transient removal clamp without minting HAM");require(f.a.maximum[6]==1750,"stronger inspiration uses original native modifier");
  f.dance.patronDataMap.rows[&f.a].strength=25;SwgxrEntertainerAudience::deliver(&f.dancer,&f.a,&f.dance,1);require(f.a.adds==2 && f.a.ham==before && f.a.maximum[6]==1750,"weaker source cannot replace stronger earned buff");
  f.a.pos.x=12;f.sync();require(f.a.buffs.size()==1,"leaving radius retains already-earned native buff");require(f.a.adds==2 && f.a.renews==1,"leaving does not retroactively grant or refresh inspiration");
  f.a.removeBuff(STRING_HASHCODE("performance_enhance_dance_mind"));require(f.a.ham[6]==1000,"native expiration only clamps resources to remaining maximum");f.a.pos.x=2;f.sync();before=f.a.ham;f.ready(f.dance,f.a,75);SwgxrEntertainerAudience::deliver(&f.dancer,&f.a,&f.dance,1);require(f.a.ham==before,"re-earning expired inspiration does not refill Mind");
 }
 {
  Fixture f;f.sync();SwgxrEntertainerAudience::synchronize(&f.musician,&f.music);f.ready(f.music,f.a);auto before=f.a.ham;SwgxrEntertainerAudience::deliver(&f.musician,&f.a,&f.music,2);require(f.a.adds==2 && f.a.buffs.size()==2,"music automatically applies original Focus and Willpower pair");require(f.a.ham==before,"music pair does not refill HAM");
  f.a.ham[7]=1400;f.a.ham[8]=1450;before=f.a.ham;f.ready(f.music,f.a,75);f.a.throwOnAdd=4;SwgxrEntertainerAudience::deliver(&f.musician,&f.a,&f.music,2);require(f.a.ham==before,"native exception during pair replacement preserves each actual resource");
  f.ready(f.dance,f.a);f.a.watch=2;f.dance.activateEntertainerBuff(&f.a,1);require(f.a.buffs.size()==2,"stale former-source map cannot directly activate buff");
  f.a.watch=1;f.a.combat=true;f.dance.activateEntertainerBuff(&f.a,1);require(f.a.buffs.size()==2,"combat transition prevents direct activation");f.a.combat=false;f.dance.denied.insert(&f.a);f.dance.activateEntertainerBuff(&f.a,1);require(f.a.buffs.size()==2,"deny-service prevents direct activation");
 }
 {
  Fixture f;require(!nativeFills(&f.a,BuffType::PERFORMANCE),"production generic buff policy forbids performance refill");require(!nativeFills(&f.a,BuffType::MEDICAL),"Doctor no-refill remains");require(!nativeFills(&f.a,BuffType::FOOD),"food no-refill remains");require(nativeFills(&f.a,BuffType::OTHER),"unrelated native buff behavior preserved");
 }
 std::cout<<"Entertainer audience native: "<<checks<<" checks passed\n";
}
