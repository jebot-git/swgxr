#include <string>
#include <sstream>
#include <map>
#include <vector>
#include <stdexcept>
#include <iostream>
using uint64=unsigned long long;
struct String:std::string {using std::string::string;String(const std::string& s):std::string(s){}const char* toCharArray()const{return c_str();}};
struct StringBuffer:std::ostringstream {};
struct Locker{template<class...T>Locker(T...){}};
template<class T>struct Ref {T* value=nullptr;Ref(){}Ref(T*p):value(p){}T*get()const{return value;}T*operator->()const{return value;}operator T*()const{return value;}};
template<class T>using UniqueReference=Ref<typename std::remove_pointer<T>::type>;
struct Template{String name;String getFullTemplateString(){return name;}};
struct ShipObject;
struct SceneObject {uint64 oid=0;Template templ;int persisted=0;virtual bool isPobShip(){return false;}virtual bool isShipControlDevice(){return false;}virtual ShipObject*asShipObject(){return nullptr;}Template*getObjectTemplate(){return &templ;}uint64 getObjectID(){return oid;}void updateToDatabaseAllObjects(bool){persisted++;}virtual ~SceneObject()=default;};
struct ShipObject:SceneObject {uint64 owner=0;bool isPobShip()override{return true;}ShipObject*asShipObject()override{return this;}uint64 getOwnerID(){return owner;}void setShipName(const char*){}};
struct ShipControlDevice:SceneObject {ShipObject*controlled=nullptr;bool isShipControlDevice()override{return true;}ShipObject*getControlledObject(){return controlled;}};
struct Pad {std::vector<Ref<SceneObject>> objects;int getContainerObjectsSize(){return objects.size();}Ref<SceneObject>getContainerObject(int i){return objects.at(i);}};
struct Account {uint64 character=0,ship=0;int writes=0;uint64 getSwgxrYachtCharacter(){return character;}uint64 getSwgxrYachtShip(){return ship;}void setSwgxrYachtCharacter(uint64 x){character=x;}void setSwgxrYachtShip(uint64 x){ship=x;}};
struct Ghost {Account* account=nullptr;unsigned id=1;Account*getAccount(){return account;}unsigned getAccountID(){return id;}};
struct ZoneServer{std::map<uint64,SceneObject*> objects;Ref<SceneObject>getObject(uint64 id){return objects.count(id)?objects.at(id):nullptr;}};
struct CreatureObject:SceneObject{Ghost ghost;Pad pad;ZoneServer server;Ghost*getPlayerObject(){return &ghost;}Pad*getDatapad(){return &pad;}ZoneServer*getZoneServer(){return &server;}};
struct ResultSet {bool valid=true,seen=false;uint64 first=100;bool next(){if(seen)return false;seen=true;return valid;}uint64 getUnsignedLong(int){return first;}};
struct ServerDatabase{uint64 first=100;bool valid=true;std::string query;static ServerDatabase*instance(){static ServerDatabase x;return &x;}ResultSet*executeQuery(StringBuffer& s){query=s.str();auto r=new ResultSet;r->first=first;r->valid=valid;return r;}};
struct ObjectManager{static ObjectManager*instance(){static ObjectManager x;return &x;}void updatePersistentObject(Account*a){a->writes++;}};
struct ShipManager{int creates=0;bool fail=false;static ShipManager*instance(){static ShipManager x;return &x;}ShipObject*createPlayerShip(CreatureObject*c,const char*t,const char*cert,bool components){if(fail)return nullptr;if(std::string(cert)!="" || !components)throw std::runtime_error("Wrong original factory options");creates++;auto s=new ShipObject;s->oid=1000+creates;s->owner=c->oid;s->templ.name=t;auto d=new ShipControlDevice;d->controlled=s;c->pad.objects.push_back(d);c->server.objects[s->oid]=s;return s;}};
bool feature=true;
#include "jtl_provision_native.inc"
int checks=0;void check(bool ok){++checks;if(!ok)throw std::runtime_error("provision case "+std::to_string(checks));}
template<class F>void rejects(F f){bool rejected=false;try{f();}catch(const std::runtime_error&){rejected=true;}check(rejected);}
int main(){
 Account account;CreatureObject first;first.oid=100;first.ghost.account=&account;CreatureObject alt;alt.oid=101;alt.ghost.account=&account;
 NativeJtlProvision::provision(&alt);check(account.character==0 && account.ship==0);check(ShipManager::instance()->creates==0);
 NativeJtlProvision::provision(&first);check(account.character==100 && account.ship!=0);check(account.writes==2);check(ShipManager::instance()->creates==1);auto s=NativeJtlProvision::entitled(&first);check(s && s->persisted==1 && first.persisted==1);check(!NativeJtlProvision::entitled(&alt));
 NativeJtlProvision::provision(&first);NativeJtlProvision::provision(&alt);check(ShipManager::instance()->creates==1);check(first.pad.objects.size()==1);
 // A newly loaded account with its persisted receipt must not mint another ship.
 Account loaded=account;first.ghost.account=&loaded;NativeJtlProvision::provision(&first);check(ShipManager::instance()->creates==1);
 first.server.objects.clear();first.pad.objects.clear();NativeJtlProvision::provision(&first);check(!NativeJtlProvision::entitled(&first));check(ShipManager::instance()->creates==1);
 // Resume a reserved grant whose native factory already put the PCD in datapad.
 Account partial;partial.character=100;first.ghost.account=&partial;auto existing=new ShipObject;existing->oid=9999;existing->owner=100;existing->templ.name="object/ship/player/player_sorosuub_space_yacht.iff";auto d=new ShipControlDevice;d->controlled=existing;first.pad.objects.push_back(d);first.server.objects[9999]=existing;NativeJtlProvision::provision(&first);check(partial.ship==9999);check(ShipManager::instance()->creates==1);
 Account disabled;first.ghost.account=&disabled;feature=false;NativeJtlProvision::provision(&first);check(disabled.character==0);feature=true;
 Account empty;first.ghost.account=&empty;first.pad.objects.clear();ShipManager::instance()->fail=true;rejects([&]{NativeJtlProvision::provision(&first);});check(empty.character==100 && empty.ship==0);ShipManager::instance()->fail=false;NativeJtlProvision::provision(&first);check(empty.ship!=0 && ShipManager::instance()->creates==2);
 auto query=ServerDatabase::instance()->query;check(query.find("UNION SELECT character_oid, creation_date FROM characters_dirty")!=std::string::npos);check(query.find("ORDER BY creation_date ASC, character_oid ASC LIMIT 1")!=std::string::npos);
 std::cout<<checks<<" actual native JtL grant/ownership/retry checks passed\n";
}
