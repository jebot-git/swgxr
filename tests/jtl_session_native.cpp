#include <nlohmann/json.hpp>
#include <string>
#include <map>
#include <cmath>
#include <iostream>
#include <stdexcept>
using Json=nlohmann::json;using JSONSerializationType=Json;using uint64=unsigned long long;
struct String:std::string{using std::string::string;String(const std::string&s):std::string(s){}const char*toCharArray()const{return c_str();}bool isEmpty()const{return empty();}};
#define STRING_HASHCODE(x) 0
struct Direction{double value=0;double getRadians(){return value;}};
struct Object{Direction direction;Direction*getDirection(){return &direction;}bool isCellObject(){return false;}uint64 getObjectID(){return 1;}};
struct Parent{Object*get(){return nullptr;}};
struct Zone:Object{String name="tatooine";String getZoneName(){return name;}};
struct Ghost{std::map<std::string,String>saved;int writes=0;String getScreenPlayData(const char*a,const char*b){return saved[std::string(a)+":"+b];}void setScreenPlayData(const char*a,const char*b,const String&v){saved[std::string(a)+":"+b]=v;}void updateToDatabase(){++writes;}};
struct CreatureObject:Object{Zone zone;Ghost ghost;Json position={3528,5,-4804};int writes=0,moves=0,posture=0;bool feign=false;Zone*getZone(){return &zone;}Ghost*getPlayerObject(){return &ghost;}Parent getParent(){return {};}Object*getRootParent(){return nullptr;}bool isDead(){return posture==14;}bool isIncapacitated(){return posture==13;}bool isFeigningDeath(){return feign;}bool isRebel(){return false;}bool isImperial(){return false;}bool hasBuff(unsigned){return false;}void setDirection(float v){direction.value=v;}void updateToDatabase(){++writes;}String getFirstName(){return "Tester";}int getHAM(int i){return i==0?-10:50;}int getMaxHAM(int){return 100;}int getWounds(int i){return i+1;}int getPosture(){return posture;}int getShockWounds(){return 2;}uint64 getGroupID(){return 0;}};
std::string id(Object*o){return o?std::to_string(o->getObjectID()):"0";}
struct SwgxrPlanets{static void require(CreatureObject*c,const Json&r=Json::object()){if(c->zone.name!="tatooine")throw std::runtime_error("supported_ground_zone_required");for(auto field:{"zone","planet"})if(r.contains(field)&&r.at(field)!=c->zone.name.c_str())throw std::runtime_error("native_source_zone_mismatch");}};
struct SwgxrPlayerSummary{static Json snapshot(CreatureObject*){return Json::object();}};
struct SwgxrTrainers{static Json experience(CreatureObject*){return Json::object();}};
struct SwgxrJtl{static bool spaceZoneName(const std::string& zone){return zone=="space_tatooine" || zone=="space_naboo";}static int recoveries;static void recoverGround(CreatureObject*c){++recoveries;c->zone.name="tatooine";c->position={3528,5,-4804};}static bool aboard(CreatureObject*c){return c->zone.name=="space_tatooine";}static Json snapshot(CreatureObject*){return {{"space_active",true},{"ship",{{"player_position",{0,.4,20}},{"cell_index",1},{"cell_id","43"},{"id","42"}}}};}};int SwgxrJtl::recoveries=0;
struct Session{bool ready=true;};
#include "jtl_session_native.inc"
int checks=0;void check(bool value){++checks;if(!value)throw std::runtime_error("session case "+std::to_string(checks));}
template<class F>void rejects(F f,const std::string&code){bool rejected=false;try{f();}catch(const std::runtime_error&e){rejected=e.what()==code;}check(rejected);}
int main(){
 CreatureObject c;c.zone.name="space_tatooine";
 Json logout={{"action","logout"},{"zone","space_tatooine"},{"position",{0,.4,20}},{"building_id","42"},{"cell_index",1},{"heading_radians",.8},{"request_id","logout_yacht_01"}};
 auto saved=NativeServices::sessionState(&c,logout);check(saved.at("saved")==true&&saved.at("location").at("zone")=="tatooine");check(c.position==Json({3528,5,-4804})&&c.moves==1&&c.writes==1&&SwgxrJtl::recoveries==1);
 auto receipts=Json::parse(c.ghost.saved.at("swgxr_session:logout_receipts"));check(receipts.at(0).at("request")==logout);
 auto again=NativeServices::sessionState(&c,logout);check(again.at("replayed")==true);check(c.moves==1&&c.writes==1&&SwgxrJtl::recoveries==1);
 auto changed=logout;changed["position"]={1,.4,20};rejects([&]{NativeServices::sessionState(&c,changed);},"logout_request_id_reused");
 changed=logout;changed["request_id"]="logout_yacht_02";rejects([&]{NativeServices::sessionState(&c,changed);},"native_source_zone_mismatch");check(c.moves==1&&c.writes==1);
 rejects([&]{NativeServices::sessionState(&c,Json{{"zone","space_tatooine"}});},"native_source_zone_mismatch");
 c.zone.name="space_tatooine";auto status=NativeServices::sessionState(&c,Json::object());check(status.at("source_kind")=="core3_session_status"&&status.at("location").at("zone")=="tatooine");check(c.moves==1&&c.writes==1&&SwgxrJtl::recoveries==2);
 c.zone.name="space_tatooine";Session session;for(int posture:{0,8,13,14}){c.posture=posture;auto snapshot=NativeLive::snapshot(&c,session);const auto&p=snapshot.at("player");check(p.at("voice").at("scope")=="sector"&&p.at("voice").at("ship_id")=="42"&&p.at("cell_id")=="43");check(p.at("space_active")==true&&p.at("wounds")==Json({1,4,7})&&p.at("shock_wounds")==2);check(p.at("ham")==Json({0,50,50})&&p.at("raw_ham")==Json({-10,50,50})&&p.at("max_ham")==Json({100,100,100}));check(p.at("posture")==posture&&p.at("dead")==bool(posture==14)&&p.at("incapacitated")==bool(posture==13));}
 c.posture=13;c.feign=true;auto feign=NativeLive::snapshot(&c,session).at("player");check(feign.at("feigning_death")==true&&feign.at("incapacitated")==false);
 std::cout<<checks<<" native onboard snapshot/logout recovery/replay checks passed\n";
}
