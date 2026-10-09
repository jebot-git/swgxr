#include <nlohmann/json.hpp>
#include <string>
#include <vector>
#include <map>
#include <iostream>
#include <algorithm>
#include <cstdlib>
#include <cmath>
using JSONSerializationType=nlohmann::json;using uint64=unsigned long long;
struct String:std::string{using std::string::string;String(const std::string& s):std::string(s){}const char* toCharArray()const{return c_str();}bool isEmpty()const{return empty();}static String valueOf(int n){return std::to_string(n);}};
template<class T>struct Ref{T p=nullptr;Ref(){}Ref(T v):p(v){}template<class U>Ref(const Ref<U>& v):p(v.get()){}T get()const{return p;}T operator->()const{return p;}operator T()const{return p;}Ref& operator=(T v){p=v;return *this;}template<class U>Ref& operator=(const Ref<U>& v){p=v.get();return *this;}template<class U>Ref<U> castTo(){return dynamic_cast<U>(p);}};
template<class T>using Reference=Ref<T>;template<class T>using ManagedReference=Ref<T>;template<class T,class U>T cast(U* p){return dynamic_cast<T>(p);}
struct Locker{template<class...T>Locker(T...t){}void release(){}};
struct Observable{virtual ~Observable()=default;};struct MissionObject;struct BountyMissionObjectiveImplementation;using BountyMissionObjective=BountyMissionObjectiveImplementation;
struct GroupObject{uint64 id=40;uint64 getObjectID(){return id;}};
struct ObjectTemplate{String name="mission_bounty_droid_seeker";String getTemplateFileName(){return name;}};
struct Permissions{uint64 owner=1;uint64 getOwnerID(){return owner;}};
struct SceneObject:Observable{bool player=false,inWorld=true,db=true;SceneObject* parent=nullptr;ObjectTemplate objectTemplate;Permissions permissions;uint64 id=1;virtual bool isPlayerCreature(){return player;}Ref<SceneObject*> getParent(){return parent;}void destroyObjectFromWorld(bool){inWorld=false;}void destroyObjectFromDatabase(bool=true){db=false;}Permissions* getContainerPermissions(){return &permissions;}ObjectTemplate* getObjectTemplate(){return &objectTemplate;}uint64 getObjectID(){return id;}virtual struct Zone* getZone(){return nullptr;}};
struct Vector3{float x=0,y=0,z=0;Vector3(){}Vector3(float a,float b,float c):x(a),y(b),z(c){}float getX(){return x;}float getY(){return y;}float getZ(){return z;}void setZ(float v){z=v;}float distanceTo(const Vector3& p){return std::sqrt((x-p.x)*(x-p.x)+(y-p.y)*(y-p.y)+(z-p.z)*(z-p.z));}bool operator==(const Vector3& p){return x==p.x && y==p.y && z==p.z;}};
struct PlanetTravelPoint{Vector3 getDeparturePosition(){return {1,2,0};}};
struct PlanetManager{PlanetTravelPoint port;bool hasPort=false;Ref<PlanetTravelPoint*> getRandomStarport(){return hasPort?&port:nullptr;}};
struct CreatureManager;struct Zone{PlanetManager manager;PlanetManager* getPlanetManager(){return &manager;}String name="naboo";String getZoneName(){return name;}CreatureManager* getCreatureManager();};
struct WaypointObject{bool active=false;double x=23,y=42;bool isActive(){return active;}void setActive(bool b){active=b;}double getPositionX(){return x;}double getPositionY(){return y;}};
struct CreatureObject;
struct MissionManager{int awards=0;void completePlayerBounty(uint64,uint64){++awards;}bool hasPlayerBountyTargetInList(uint64){return false;}Vector3 getRandomBountyTargetPosition(CreatureObject*,String){return {10,20,0};}};
struct PlayerManager{int xp=0;void awardExperience(SceneObject*,const char*,int n,bool,int){xp+=n;}};
struct ZoneServer{Zone location;Zone* getZone(const String&){return &location;}MissionManager missions;PlayerManager players;MissionManager* getMissionManager(){return &missions;}PlayerManager* getPlayerManager(){return &players;}Ref<SceneObject*> getObject(uint64){return nullptr;}};
template<class T>struct Vector:std::vector<T>{using std::vector<T>::vector;T get(int n){return this->at(n);}void removeAll(){this->clear();}};
template<class T>using SortedVector=Vector<T>;
struct ActiveArea{bool city=false;bool isCityRegion(){return city;}};
struct CreatureObject:SceneObject{Zone zone;ZoneServer server;bool dead=false,incap=false,combat=false,mounted=false;SortedVector<Ref<ActiveArea*>> areas;uint64 parentID=0;std::map<String,int> mods;std::vector<String> skills;std::vector<String> messages;SceneObject inv,datapad;GroupObject* group=nullptr;CreatureObject(){player=true;}Zone* getZone()override{return &server.location;}Vector3 getWorldPosition(){return {10,20,0};}template<class T>void sendMessage(T*){}ZoneServer* getZoneServer(){return &server;}bool isDead(){return dead;}bool isIncapacitated(){return incap;}bool isInCombat(){return combat;}bool isRidingMount(){return mounted;}auto getActiveAreas(){return &areas;}float getPositionX(){return 1;}float getPositionY(){return 2;}float getPositionZ(){return 0;}uint64 getParentID(){return parentID;}bool hasSkill(const String& s){return std::find(skills.begin(),skills.end(),s)!=skills.end();}SceneObject* getInventory(){return &inv;}SceneObject* getSlottedObject(const char* s){return std::string(s)=="datapad"?&datapad:&inv;}void sendSystemMessage(const String& s){messages.push_back(s);}template<class T>void sendSystemMessage(const T&){}String getFirstName(){return "Hunter";}String getLastName(){return "Test";}int getSkillMod(const String& s){return mods[s];}int getSkillModFromBuffs(const String&){return 0;}GroupObject* getGroup(){return group;}};
struct MissionObject:SceneObject{String target="bh_thug";uint64 targetID=0;int level=2,reward=5000,bonus=0;WaypointObject waypoint;BountyMissionObjective* objective=nullptr;int getMissionLevel(){return level;}String getTargetOptionalTemplate(){return target;}uint64 getTargetObjectId(){return targetID;}WaypointObject* getWaypointToMission(){return &waypoint;}BountyMissionObjective* getMissionObjective(){return objective;}void setEndPosition(float,float,const String&,bool){}int getRewardCredits(){return reward;}int getBonusCredits(){return bonus;}};
struct ObjectFlag{enum{STATIC};};
struct AiAgent:CreatureObject{AiAgent(){player=false;}void addObjectFlag(int){}void setAITemplate(){}};
struct CreatureManager{AiAgent spawned;bool fail=false;SceneObject* spawnCreature(unsigned,int,float,float,float,int){return fail?nullptr:&spawned;}};
CreatureManager creatures;CreatureManager* Zone::getCreatureManager(){return &creatures;}
#define STRING_HASHCODE(x) 1
struct TangibleObject:SceneObject{int uses=3;void decreaseUseCount(){--uses;if(uses<1){inWorld=false;parent=nullptr;db=false;}}};
struct Task{bool scheduled=true,canceled=false;virtual ~Task()=default;bool isScheduled(){return scheduled;}void cancel(){canceled=true;scheduled=false;}void schedule(int){scheduled=true;}void reschedule(int){scheduled=true;}};
struct FindTargetTask:Task{FindTargetTask(){}FindTargetTask(CreatureObject*,CreatureObject*,BountyMissionObjective*,bool t,bool):tracking(t){}bool completed=false,tracking=false,cleaned=false;bool isCompleted(){return completed;}bool swgxrTracking(){return tracking;}void swgxrCancel(){cancel();completed=true;cleaned=true;}};
struct CallArakydTask:Task{CallArakydTask(CreatureObject*,BountyMissionObjective*){}};
struct TaskManager{int accepted=0;void executeTask(Ref<CallArakydTask*>){++accepted;}};
struct Core{static TaskManager* getTaskManager(){static TaskManager t;return &t;}};

struct MissionObjectiveImplementation{int completions=0,activations=0,deactivations=0,aborts=0;void activate(){++activations;}void deactivate(){++deactivations;}void abort(){++aborts;}void complete(){++completions;}};
struct BountyMissionObjectiveImplementation:MissionObjectiveImplementation{
 enum{INITSTATUS,HASBIOSIGNATURESTATUS,HASTALKED,TARGETELIMINATEDSTATUS};int syncMutex=0,objectiveStatus=0,saves=0,removed=0,started=0,npcObservers=0,playerObservers=0;bool completedMission=false;String swgxrKnownPlanet,swgxrDroidMessage,swgxrSearchPlanet;String currentPlanet="naboo";CreatureObject* owner=nullptr;Ref<MissionObject*> mission;Ref<SceneObject*> activeDroid,npcTarget;Ref<Task*> targetTask;Vector<Ref<Task*>> droidTasks;
 CreatureObject* getPlayerOwner(){return owner;}Ref<MissionObject*> getMissionObject(){return mission;}bool isPlayerTarget(){return mission && mission->target.empty();}void removeMissionFromPlayer(){++removed;owner=nullptr;}void startNpcTargetTask(){++started;if(!targetTask)targetTask=new Task;}int getObserverCount(){return npcObservers;}void removeNpcTargetObservers(){npcObservers=0;}void removePlayerTargetObservers(){playerObservers=0;}bool hasObservers(){return npcObservers || playerObservers;}void updateToDatabase(){++saves;}void updateWaypoint(){mission->waypoint.active=true;}String getTargetZoneName(){return currentPlanet;}String getSwgxrSearchPlanet(){return swgxrSearchPlanet;}SceneObject* getArakydDroid(){return activeDroid;}void setArakydDroid(SceneObject* d){activeDroid=d;}bool hasArakydFindTask(){return false;}void cancelCallArakydTask(){}int getObjectiveStatus(){return objectiveStatus;}int spawns=0;void spawnTarget(const String&){++spawns;}bool performDroidAction(int,SceneObject*,CreatureObject*);
 #include "bounty_objective.inc"
};
struct ConfigManager{static ConfigManager* instance(){static ConfigManager c;return &c;}bool getBool(const char*,bool){return false;}};
struct StringIdChatParameter{StringIdChatParameter(const char*){}void setDI(int){}void setTO(const char*,String){}};
struct System{static int randomValue;static int random(int n){return std::min(n,randomValue);}};int System::randomValue=0;
struct Search{bool arakyd=true,track=false;String zoneName="naboo";int targetLevel=30;int getDistanceToTarget(CreatureObject*,BountyMissionObjective*){return 5;}String getDirectionToTarget(CreatureObject*,BountyMissionObjective*){return "north";}int getTargetLevel(CreatureObject*,BountyMissionObjective*){return targetLevel;}
 #include "bounty_search.inc"
};
struct BountyHunterDroid{enum{CALLDROID,TRANSMITBIOLOGICALSIGNATURE,FINDTARGET,FINDANDTRACKTARGET};
 #include "bounty_dispatch.inc"
};
bool BountyMissionObjectiveImplementation::performDroidAction(int action,SceneObject* item,CreatureObject* player){BountyHunterDroid droid;auto task=droid.performAction(action,item,player,mission);if(task!=nullptr)droidTasks.push_back(task);return task!=nullptr;}
struct PlayClientEffectLoc{template<class...T>PlayClientEffectLoc(T...){}};
struct DeliveryRunner:Task{Ref<CreatureObject*> player;Ref<BountyMissionObjective*> objective;int time=0;Vector3 droidPosition;String launchZone="naboo";Ref<AiAgent*> droid;void error(const char*){}
 #include "bounty_delivery.inc"
};
struct TargetRunner:Task{Ref<BountyMissionObjective*> objective;Ref<CreatureObject*> player;Ref<MissionObject*> mission;String zoneName="naboo";Vector3 destination,currentPosition{10,20,0};bool move=false,targetSpawned=false,movingToStarport=false;void updatePosition(CreatureObject*){}void updateToSpawnableTargetPosition(){}
 #include "bounty_target.inc"
};
struct Runner{enum states{Init,DroidSent,Searching,Tracking,Completed};states state=Searching;Ref<CreatureObject*> weakDroid,weakPlayer;Ref<BountyMissionObjective*> weakObjective;bool arakyd=false,success=true;String zoneName="naboo";int reports=0;void init(CreatureObject*,CreatureObject*){++reports;}void droidSent(CreatureObject*){++reports;}void searching(CreatureObject*,BountyMissionObjective*){++reports;}void tracking(CreatureObject*,BountyMissionObjective*){++reports;}void error(const char*){}
 #include "bounty_runner.inc"
};
int checks=0;void check(bool b){++checks;if(!b){std::cerr<<"failed check "<<checks<<'\n';std::abort();}}
int main(){CreatureObject player;MissionObject mission;BountyMissionObjective o;o.owner=&player;o.mission=&mission;mission.objective=&o;mission.parent=&player.datapad;
 auto state=JSONSerializationType::parse(o.swgxrState());check(state["stage"]=="informant" && state["planet"]=="");check(state["waypoint"]["position"].empty());
 o.updateMissionStatus(2);check(o.objectiveStatus==o.HASBIOSIGNATURESTATUS && !mission.waypoint.active);check(o.started==1);
 Search search;o.swgxrSearchPlanet="tatooine";check(!search.findAndTrackSuccess(&player,&o));check(o.swgxrKnownPlanet.empty() && !mission.waypoint.active);check(o.swgxrDroidMessage.find("retry")!=std::string::npos);
 o.swgxrSearchPlanet="naboo";check(search.findAndTrackSuccess(&player,&o));check(o.swgxrKnownPlanet=="naboo" && !mission.waypoint.active);state=JSONSerializationType::parse(o.swgxrState());check(state["planet_known"]==true && state["waypoint"]["position"].empty());
 search.arakyd=false;search.zoneName="tatooine";check(!search.findAndTrackSuccess(&player,&o));check(!mission.waypoint.active);search.zoneName="naboo";check(search.findAndTrackSuccess(&player,&o));check(mission.waypoint.active && o.objectiveStatus==o.HASTALKED);state=JSONSerializationType::parse(o.swgxrState());check(state["stage"]=="target" && state["waypoint"]["planet"]=="naboo");check(state["waypoint"]["position"]==JSONSerializationType::array({23.,0,42.}));
 FindTargetTask seek;seek.tracking=true;o.droidTasks.push_back(&seek);state=JSONSerializationType::parse(o.swgxrState());check(state["stage"]=="tracking" && state["searching"]==true);seek.completed=true;check(JSONSerializationType::parse(o.swgxrState())["stage"]=="target");seek.completed=false;
 Task movement;o.targetTask=&movement;SceneObject deployed;o.activeDroid=&deployed;o.deactivate();check(movement.canceled && seek.canceled && seek.cleaned);check(o.droidTasks.empty() && !o.activeDroid);check(!deployed.inWorld && !deployed.db);check(o.swgxrDroidMessage.find("interrupted")!=std::string::npos);
 // Restart reactivation releases stale persistent probe reservation and resumes target.
 o.activeDroid=&player;o.activate();check(!o.activeDroid && o.started==2 && player.inWorld);check(o.objectiveStatus==o.HASTALKED && mission.waypoint.active);
 o.activeDroid=&deployed;deployed.inWorld=deployed.db=true;o.activate();check(!o.activeDroid && !deployed.inWorld && !deployed.db);check(JSONSerializationType::parse(o.swgxrState())["waypoint"]["active"]==true);
 // Native consumption dispatch never admits another owner's item, PvP or no skill.
 BountyHunterDroid dispatcher;TangibleObject item;item.parent=&player.inv;check(!dispatcher.performAction(BountyHunterDroid::FINDTARGET,&item,&player,&mission));player.skills.push_back("combat_bountyhunter_investigation_01");check(dispatcher.performAction(BountyHunterDroid::FINDTARGET,&item,&player,&mission)!=nullptr);check(item.uses==2);
 item.parent=nullptr;check(!dispatcher.performAction(BountyHunterDroid::FINDTARGET,&item,&player,&mission));item.parent=&player.inv;mission.target="";check(!dispatcher.performAction(BountyHunterDroid::FINDTARGET,&item,&player,&mission));mission.target="bh_thug";mission.targetID=99;check(!dispatcher.performAction(BountyHunterDroid::FINDTARGET,&item,&player,&mission));mission.targetID=0;
 check(!dispatcher.performAction(BountyHunterDroid::FINDANDTRACKTARGET,&item,&player,&mission));player.skills.push_back("combat_bountyhunter_investigation_03");mission.level=3;check(dispatcher.performAction(BountyHunterDroid::FINDANDTRACKTARGET,&item,&player,&mission)!=nullptr);player.combat=true;check(!dispatcher.performAction(BountyHunterDroid::FINDTARGET,&item,&player,&mission));player.combat=false;player.parentID=4;check(!dispatcher.performAction(BountyHunterDroid::FINDTARGET,&item,&player,&mission));player.parentID=0;
 item.objectTemplate.name="ordinary_item";check(!dispatcher.performAction(BountyHunterDroid::FINDTARGET,&item,&player,&mission));item.uses=3;item.objectTemplate.name="mission_bounty_droid_probot";check(dispatcher.performAction(BountyHunterDroid::CALLDROID,&item,&player,&mission)!=nullptr);check(!dispatcher.performAction(BountyHunterDroid::TRANSMITBIOLOGICALSIGNATURE,&item,&player,&mission));
 check(item.uses==2 && o.activeDroid==&player);check(!dispatcher.performAction(BountyHunterDroid::CALLDROID,&item,&player,&mission));check(item.uses==2);
 o.activeDroid=&creatures.spawned;o.swgxrSearchPlanet="naboo";player.combat=true;player.parentID=4;player.mounted=true;check(dispatcher.performAction(BountyHunterDroid::TRANSMITBIOLOGICALSIGNATURE,&creatures.spawned,&player,&mission)!=nullptr);check(item.uses==2);player.combat=false;player.parentID=0;player.mounted=false;o.activeDroid=nullptr;
 item.objectTemplate.name="mission_bounty_droid_seeker";creatures.fail=true;check(!dispatcher.performAction(BountyHunterDroid::FINDTARGET,&item,&player,&mission));check(item.uses==2);creatures.fail=false;
 o.activeDroid=&player;check(JSONSerializationType::parse(o.swgxrState())["searching"]==true);o.activeDroid=nullptr;
 o.swgxrDroidReport(true,true,"tatooine");check(!mission.waypoint.active && o.swgxrKnownPlanet=="tatooine");check(JSONSerializationType::parse(o.swgxrState())["waypoint"]["position"].empty());
 // Original bounded chance and timings remain skill driven.
 player.mods["droid_find_chance"]=500;System::randomValue=94;check(search.getSuccess(&player,&o));System::randomValue=95;check(!search.getSuccess(&player,&o));player.mods["droid_find_chance"]=-500;System::randomValue=4;check(search.getSuccess(&player,&o));System::randomValue=5;check(!search.getSuccess(&player,&o));player.mods["droid_find_speed"]=500;System::randomValue=0;check(search.calculateTime(&player)==35);player.mods["droid_find_speed"]=-5;check(search.calculateTime(&player)==150);search.track=true;player.mods["droid_track_speed"]=500;check(search.calculateTime(&player)==45);
 // Existing owner/group loot authority controls reward once only.
 CreatureObject victim;victim.player=false;victim.inv.permissions.owner=player.id;o.handleNpcTargetKilled(&victim);check(o.completions==1 && o.completedMission);check(player.server.players.xp==100 && player.server.missions.awards==1);o.complete();check(o.completions==1 && player.server.players.xp==100);
 BountyMissionObjective groupObjective;MissionObject gm;gm.objective=&groupObjective;groupObjective.mission=&gm;groupObjective.owner=&player;GroupObject group;player.group=&group;victim.inv.permissions.owner=group.id;groupObjective.handleNpcTargetKilled(&victim);check(groupObjective.completions==1);
 BountyMissionObjective stolen;MissionObject sm;stolen.mission=&sm;stolen.owner=&player;sm.waypoint.active=true;victim.inv.permissions.owner=999;stolen.handleNpcTargetKilled(&victim);check(stolen.completions==0 && stolen.aborts==1 && stolen.removed==1 && !sm.waypoint.active);
 BountyMissionObjective pvp;MissionObject pm;pm.target="";pvp.mission=&pm;pvp.owner=&player;pvp.activate();check(pvp.started==0 && pvp.aborts==1 && pvp.removed==1);
 BountyMissionObjective novice;MissionObject nm;nm.level=1;novice.mission=&nm;novice.owner=&player;novice.updateMissionStatus(1);check(nm.waypoint.active && novice.swgxrKnownPlanet=="naboo");
 Runner runner;runner.weakPlayer=&player;runner.weakObjective=&o;runner.run();check(runner.reports==1);o.owner=nullptr;runner.run();check(runner.reports==1 && runner.state==Runner::Completed);o.owner=&player;runner.state=Runner::Searching;mission.target="";runner.run();check(runner.reports==1 && runner.state==Runner::Completed);mission.target="bh_thug";runner.state=Runner::Searching;runner.zoneName="tatooine";runner.run();check(!runner.success);runner.state=Runner::Init;runner.weakDroid=nullptr;runner.arakyd=true;runner.run();check(runner.state==Runner::Completed && !o.activeDroid);
 TargetRunner target;target.objective=&o;target.player=&player;target.mission=&mission;o.objectiveStatus=o.HASBIOSIGNATURESTATUS;mission.level=3;target.run();check(o.spawns==1 && target.targetSpawned && !target.movingToStarport);check(target.destination==Vector3(10,20,0));target.run();check(o.spawns==1);target.targetSpawned=false;o.objectiveStatus=o.INITSTATUS;target.run();check(o.spawns==1);o.objectiveStatus=o.HASBIOSIGNATURESTATUS;
 // Accepted delivery automatically starts the real signature search once, even after posture/combat changes.
 DeliveryRunner delivery;delivery.player=&player;delivery.objective=&o;o.activeDroid=&player;o.swgxrSearchPlanet="naboo";player.combat=true;player.parentID=5;player.mounted=true;delivery.run();check(o.droidTasks.size()==1 && delivery.time==-1 && o.activeDroid==&creatures.spawned);check(item.uses==2);player.combat=false;player.parentID=0;player.mounted=false;
 o.owner=nullptr;DeliveryRunner late;late.player=&player;late.objective=&o;late.run();check(late.time==0 && o.droidTasks.size()==1);o.owner=&player;
 std::cout<<checks<<" bounty production lifecycle checks passed\n";
}
