// Runs the actual extracted JtL boarding and ownership methods; only native
// object storage, transforms and session lookup are isolated dependencies.
#include <cmath>
#include <cstdint>
#include <functional>
#include <iostream>
#include <limits>
#include <map>
#include <stdexcept>
#include <string>
#include <vector>
#include "engine/util/json.hpp"
using uint64=uint64_t;
using Json=nlohmann::json;
struct String:std::string {
 using std::string::string;
 String(std::string value):std::string(std::move(value)){}
 bool contains(const char* value)const{return find(value)!=npos;}
 bool isEmpty()const{return empty();}
 const char* toCharArray()const{return c_str();}
};
template<class T> struct Vector:std::vector<T> {using std::vector<T>::vector;T get(int i)const{return this->at(i);}};
template<class T> struct Ref {T* value=nullptr;T* get()const{return value;}T* operator->()const{return value;}operator bool()const{return value!=nullptr;}operator T*()const{return value;}};
struct CreatureObject;struct ShipObject;
namespace PlayerArrangement {enum {SHIP_GUNNER0=10,SHIP_GUNNER7=17};}
struct ObjectTemplate {String path;const String& getFullTemplateString()const{return path;}};
struct SceneObject {
 virtual ~SceneObject()=default;
 uint64 id=0;ObjectTemplate objectTemplate;SceneObject* parent=nullptr;int containment=-1;
 virtual bool isPobShip()const{return false;}
 virtual bool isShipControlDevice()const{return false;}
 virtual bool isPlayerCreature()const{return false;}
 virtual bool isCreatureObject()const{return false;}
 virtual bool isShipObject()const{return false;}
 bool isASubChildOf(CreatureObject* c)const{return parent==reinterpret_cast<SceneObject*>(c);}
 uint64 getObjectID()const{return id;}
 int getContainmentType()const{return containment;}
 ObjectTemplate* getObjectTemplate(){return &objectTemplate;}
};
struct ZoneServer {std::map<uint64,SceneObject*> objects;Ref<SceneObject> getObject(uint64 id){return {objects[id]};}};
struct PlayerObject {bool ability=false;bool hasAbility(const String&){return ability;}};
struct CreatureObject:SceneObject {
 ZoneServer* server=nullptr;PlayerObject ghost;bool skill=false,piloting=true,online=true;ShipObject* root=nullptr;Json state=Json::object();
 bool isPlayerCreature()const override{return true;}
 bool isCreatureObject()const override{return true;}
 bool isPilotingShip()const{return piloting;}
 ZoneServer* getZoneServer(){return server;}
 PlayerObject* getPlayerObject(){return &ghost;}
 bool hasSkill(const String&){return skill;}
};
struct Npc:SceneObject {bool isCreatureObject()const override{return true;}};
struct ShipControlDevice:SceneObject {bool isShipControlDevice()const override{return true;}};
struct ShipObject:SceneObject {
 bool pob=false,multi=false;uint64 owner=0,pcd=0;String chassis,certificationRequired;
 CreatureObject* pilot=nullptr;Vector<uint64> occupants;Vector<SceneObject*> slots;int zone=1;double x=0,speed=0;
 bool isPobShip()const override{return pob;}
 bool isShipObject()const override{return true;}
 bool isMultiPassengerShip()const{return multi;}
 const String& getShipChassisName(){return chassis;}
 uint64 getOwnerID()const{return owner;}
 uint64 getControlDeviceID()const{return pcd;}
 CreatureObject* getPilot(){return pilot;}
 Vector<uint64> getPlayersOnBoard(){return occupants;}
 int getTotalPlayersOnBoard()const{return occupants.size();}
 int getSlottedObjectsSize()const{return slots.size();}
 SceneObject* getSlottedObject(int i){return slots.get(i);}
 int getZone()const{return zone;}
 bool isInRange(ShipObject* other,double range)const{return std::abs(x-other->x)<=range;}
 double getCurrentSpeed()const{return speed;}
 bool canBePilotedBy(CreatureObject* player);
};
struct ConfigManager {
 Vector<String> templates={"object/ship/player/player_xwing.iff","object/ship/player/player_ywing.iff"};
 static ConfigManager* instance(){static ConfigManager value;return &value;}
 const Vector<String>& getStringVector(const char*){return templates;}
};
#include "original_certification.inc"
struct SwgxrJtl {
 static bool aboard(CreatureObject* c){return c && c->root;}
 static ShipObject* current(CreatureObject* c){return c->root;}
 static bool connected(CreatureObject* c){return c && c->online;}
 static CreatureObject* player(CreatureObject* c,const std::string& id){auto o=c->server->getObject(std::stoull(id));return o && o->isPlayerCreature()?static_cast<CreatureObject*>(o.get()):nullptr;}
 static ShipObject* ship(CreatureObject* c,const std::string& id){auto o=c->server->getObject(std::stoull(id));return o && o->isShipObject()?static_cast<ShipObject*>(o.get()):nullptr;}
 static uint64 oid(const Json& r,const char* key){return std::stoull(r.at(key).get<std::string>());}
 static Json data(CreatureObject* c,const char* key){return c->state.value(key,Json::object());}
 static ShipObject* entitled(CreatureObject*){return nullptr;}
 #include "jtl_crew_methods.inc"
};
static int checks=0;
static void check(bool condition,const char* label){++checks;if(!condition)throw std::runtime_error(label);}
template<class F>static void rejected(F fn,const char* error){++checks;try{fn();}catch(const std::runtime_error& e){if(std::string(e.what())==error)return;throw;}throw std::runtime_error(std::string("accepted: ")+error);}
struct Fixture {
 ZoneServer world;CreatureObject guest,captain,other;ShipObject own,host;ShipControlDevice pcd;SceneObject cargo;Npc gunner;
 Fixture(){guest.id=1;captain.id=2;other.id=3;own.id=10;host.id=20;pcd.id=30;
  guest.server=captain.server=other.server=&world;guest.root=&own;captain.root=&host;
  own.owner=guest.id;host.owner=captain.id;own.pcd=pcd.id;pcd.parent=&guest;
  own.pilot=&guest;host.pilot=&captain;host.pob=true;own.occupants={guest.id};host.occupants={captain.id};
  own.objectTemplate.path="object/ship/player/player_xwing.iff";host.objectTemplate.path="object/ship/player/player_sorosuub_space_yacht.iff";
  for(auto o:std::vector<SceneObject*>{&guest,&captain,&other,&own,&host,&pcd})world.objects[o->id]=o;
 }
 void eligible(){SwgxrJtl::boardingEligible(&guest,&own,&host);}
};
int main(){try{
 Fixture f;f.eligible();check(true,"empty fighter may request boarding");
 check(SwgxrJtl::capacity(&f.own)==1,"fighter pilot capacity");f.own.multi=true;check(SwgxrJtl::capacity(&f.own)==2,"original one gunner capacity");check(SwgxrJtl::capacity(&f.host)==20,"original group capacity source");
 f.own.occupants.push_back(f.other.id);rejected([&]{f.eligible();},"jtl_boarding_seat_occupied");f.own.occupants.pop_back();
 f.own.slots={&f.other};rejected([&]{f.eligible();},"jtl_boarding_seat_occupied");f.own.slots={&f.cargo,&f.guest};f.eligible();check(true,"cargo and own pilot are not extra crew");
 for(int slot=PlayerArrangement::SHIP_GUNNER0;slot<=PlayerArrangement::SHIP_GUNNER7;++slot){f.gunner.containment=slot;f.own.slots={&f.gunner};rejected([&]{f.eligible();},"jtl_boarding_seat_occupied");}f.own.slots.clear();
 f.own.pob=true;rejected([&]{f.eligible();},"jtl_boarding_ship_class_rejected");f.own.pob=false;
 f.own.chassis="player_gunship";rejected([&]{f.eligible();},"jtl_boarding_ship_class_rejected");f.own.chassis="";
 f.own.objectTemplate.path="object/ship/player/player_gunship.iff";check(SwgxrJtl::gunship(&f.own),"gunship template classification");rejected([&]{f.eligible();},"jtl_boarding_ship_class_rejected");f.own.objectTemplate.path="object/ship/player/player_xwing.iff";
 f.host.pob=false;rejected([&]{f.eligible();},"jtl_boarding_ship_class_rejected");f.host.pob=true;
 rejected([&]{SwgxrJtl::boardingEligible(&f.guest,nullptr,&f.host);},"jtl_boarding_ship_class_rejected");
 rejected([&]{SwgxrJtl::boardingEligible(&f.guest,&f.own,&f.own);},"jtl_boarding_ship_class_rejected");
 f.own.objectTemplate.path="object/ship/player/unpublished.iff";rejected([&]{f.eligible();},"jtl_boarding_ship_class_rejected");f.own.objectTemplate.path="object/ship/player/player_ywing.iff";
 f.own.pilot=&f.other;rejected([&]{f.eligible();},"jtl_pilot_required");f.own.pilot=&f.guest;
 f.guest.piloting=false;rejected([&]{f.eligible();},"jtl_pilot_required");f.guest.piloting=true;
 f.guest.root=&f.host;rejected([&]{f.eligible();},"jtl_pilot_required");f.guest.root=&f.own;
 f.own.owner=f.other.id;rejected([&]{f.eligible();},"jtl_pilot_required");f.own.owner=f.guest.id;
 f.pcd.parent=&f.other;rejected([&]{f.eligible();},"jtl_owned_control_device_required");f.pcd.parent=&f.guest;
 f.world.objects.erase(f.pcd.id);rejected([&]{f.eligible();},"jtl_owned_control_device_required");f.world.objects[f.pcd.id]=&f.pcd;
 f.own.x=256;f.own.speed=1;f.host.speed=-1;f.eligible();check(true,"inclusive range and holding speed boundaries");
 f.own.x=256.001;rejected([&]{f.eligible();},"jtl_boarding_hold_nearby");f.own.x=0;
 f.own.speed=-1.001;rejected([&]{f.eligible();},"jtl_boarding_hold_nearby");f.own.speed=0;
 f.host.speed=1.001;rejected([&]{f.eligible();},"jtl_boarding_hold_nearby");f.host.speed=0;
 f.own.speed=std::numeric_limits<double>::quiet_NaN();rejected([&]{f.eligible();},"jtl_boarding_hold_nearby");f.own.speed=0;
 f.host.speed=std::numeric_limits<double>::quiet_NaN();rejected([&]{f.eligible();},"jtl_boarding_hold_nearby");f.host.speed=0;
 f.own.zone=2;rejected([&]{f.eligible();},"jtl_boarding_hold_nearby");f.own.zone=1;
 f.captain.online=false;rejected([&]{f.eligible();},"jtl_boarding_hold_nearby");f.captain.online=true;
 f.guest.online=false;rejected([&]{f.eligible();},"jtl_boarding_hold_nearby");f.guest.online=true;
 f.host.pilot=nullptr;rejected([&]{f.eligible();},"jtl_boarding_hold_nearby");f.host.pilot=&f.captain;
 f.captain.root=&f.own;rejected([&]{f.eligible();},"jtl_boarding_hold_nearby");f.captain.root=&f.host;
 f.captain.piloting=false;rejected([&]{f.eligible();},"jtl_boarding_hold_nearby");f.captain.piloting=true;
 f.host.occupants.resize(19,99);f.eligible();check(true,"last free host capacity");f.host.occupants.push_back(98);rejected([&]{f.eligible();},"jtl_crew_full");f.host.occupants={f.captain.id};
 // Actual original certificate gate, reached through actual owned() wrapper.
 Json selection={{"ship_id","10"}};check(SwgxrJtl::owned(&f.guest,selection)==&f.own,"owned certified empty restriction");
 f.own.certificationRequired="cert_test";rejected([&]{SwgxrJtl::owned(&f.guest,selection);},"jtl_ship_certification_required");
 f.guest.ghost.ability=true;check(SwgxrJtl::owned(&f.guest,selection)==&f.own,"original ability certificate accepted");f.guest.ghost.ability=false;
 f.guest.skill=true;check(SwgxrJtl::owned(&f.guest,selection)==&f.own,"original skill certificate accepted");
 f.own.owner=f.other.id;rejected([&]{SwgxrJtl::owned(&f.guest,selection);},"jtl_supported_owned_ship_required");
 std::cout<<"JTL actual boarding/ownership methods: "<<checks<<" checks passed\n";return 0;
 }catch(const std::exception& e){std::cerr<<e.what()<<"\n";return 1;}}
