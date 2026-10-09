#include <nlohmann/json.hpp>
#include <algorithm>
#include <cmath>
#include <iostream>
#include <map>
#include <set>
#include <string>
#include <vector>
using JSONSerializationType=nlohmann::json;using Json=nlohmann::json;using uint64=unsigned long long;
struct String:std::string{using std::string::string;String(const std::string& s):std::string(s){}const char* toCharArray()const{return c_str();}};
template<class T>struct Ref{T p=nullptr;Ref(){}Ref(T v):p(v){}T get()const{return p;}T operator->()const{return p;}operator T()const{return p;}Ref& operator=(T v){p=v;return *this;}template<class U>Ref<U> castTo(){return Ref<U>(dynamic_cast<U>(p));}};
template<class T>using ManagedReference=Ref<T>;
struct Lockable{};struct SceneObject:Lockable{virtual ~SceneObject()=default;};struct CreatureObject;struct GroupObject;struct Zone{};
struct ZoneServer{std::map<uint64,SceneObject*> objects;Ref<SceneObject*> getObject(uint64 id){return objects[id];}};
struct Ghost{std::set<String> ignored;bool isIgnoring(const String& n){return ignored.count(n);}};
struct CreatureObject:SceneObject{uint64 id=1,parent=0,inviter=0;int level=1;bool player=true,dead=false,incap=false,combat=false,los=true,callerLocked=true;double x=0;Zone* zone=nullptr;ZoneServer* server=nullptr;GroupObject* group=nullptr;Ghost ghost;std::set<String> skills;String name="member";
 bool isPlayerCreature(){return player;}bool isDead(){return dead;}bool isIncapacitated(){return incap;}bool isInCombat(){return combat;}bool hasSkill(const String& s){return skills.count(s);}int getLevel(){return level;}uint64 getObjectID(){return id;}uint64 getParentID(){return parent;}Zone* getZone(){return zone;}ZoneServer* getZoneServer(){return server;}Ghost* getPlayerObject(){return &ghost;}bool isGrouped(){return group!=nullptr;}GroupObject* getGroup(){return group;}uint64 getGroupID();uint64 getGroupInviterID(){return inviter;}String getFirstName(){return name;}bool isInRange(CreatureObject* c,int r){return std::abs(x-c->x)<=r;}void unlock(){if(!callerLocked)throw std::runtime_error("double_unlock");callerLocked=false;}void wlock(){if(callerLocked)throw std::runtime_error("double_lock");callerLocked=true;}
};
struct GroupObject:SceneObject{uint64 id=90;CreatureObject* leader=nullptr;std::vector<CreatureObject*> members;int getGroupSize(){return members.size();}CreatureObject* getGroupMember(int i){return members.at(i);}CreatureObject* getLeader(){return leader;}uint64 getLeaderID(){return leader?leader->id:0;}uint64 getObjectID(){return id;}void makeLeader(CreatureObject* c){leader=c;}};
uint64 CreatureObject::getGroupID(){return group?group->id:0;}
struct Locker{template<class T>Locker(T){}template<class T,class U>Locker(T,U){}};
struct CollisionManager{static bool checkLineOfSight(CreatureObject*,CreatureObject* peer){return peer->los;}};
#include "party_policy.inc"
struct GroupManager{int invitations=0,joins=0;bool denyInvite=false,denyJoin=false;std::vector<GroupObject*> allocated;static GroupManager* instance(){static GroupManager m;return &m;}
 void inviteToGroup(CreatureObject* inviter,CreatureObject* peer){++invitations;if(denyInvite || peer->group || (peer->inviter && peer->inviter!=inviter->id))return;peer->inviter=inviter->id;}
 void joinGroup(CreatureObject* joiner){++joins;if(denyJoin)return;auto leader=dynamic_cast<CreatureObject*>(joiner->server->getObject(joiner->inviter).get());if(!leader)return;auto group=leader->group;if(!group){group=new GroupObject;allocated.push_back(group);group->leader=leader;group->members.push_back(leader);leader->group=group;}group->members.push_back(joiner);joiner->group=group;joiner->inviter=0;SwgxrPartyPolicy::reconcile(group);}
};
#include "party_formation.inc"
int checks=0;void check(bool b){++checks;if(!b){std::cerr<<"failed "<<checks<<'\n';std::abort();}}
template<class F>void reject(F f,const char* expected){try{f();check(false);}catch(const std::exception& e){if(std::string(e.what())!=expected)std::cerr<<e.what()<<'\n';check(std::string(e.what())==expected);}}
int main(){Zone planet,other;ZoneServer server;CreatureObject actor,peer,leader;actor.id=1;actor.name="actor";peer.id=2;peer.name="peer";leader.id=3;leader.name="leader";for(auto c:{&actor,&peer,&leader}){c->zone=&planet;c->server=&server;server.objects[c->id]=c;}auto gm=GroupManager::instance();Json q={{"group_bump_authorized",true},{"target_id","2"}};
 auto bad=[&](const char* error){reject([&](){SwgxrParty::bump(&actor,q);},error);check(actor.callerLocked);};auto reset=[&](){actor.group=peer.group=leader.group=nullptr;actor.inviter=peer.inviter=leader.inviter=0;actor.skills.clear();peer.skills.clear();leader.skills.clear();gm->invitations=gm->joins=0;};
 q["group_bump_authorized"]=false;bad("mutual_fist_bump_required");q["group_bump_authorized"]=true;q["target_id"]="1";bad("nearby_group_player_required");q["target_id"]="999";bad("nearby_group_player_required");q["target_id"]="2";peer.player=false;bad("nearby_group_player_required");peer.player=true;
 for(auto c:{&actor,&peer}){c->dead=true;bad("native_player_unavailable");c->dead=false;c->incap=true;bad("native_player_unavailable");c->incap=false;c->combat=true;bad("native_player_unavailable");c->combat=false;}
 peer.zone=&other;bad("nearby_group_player_required");peer.zone=&planet;peer.parent=10;bad("nearby_group_player_required");peer.parent=0;peer.x=3.001;bad("nearby_group_player_required");peer.x=0;peer.los=false;bad("nearby_group_player_required");peer.los=true;peer.ghost.ignored.insert(actor.name);bad("group_player_ignored");peer.ghost.ignored.clear();actor.ghost.ignored.insert(peer.name);bad("group_player_ignored");actor.ghost.ignored.clear();check(gm->invitations==0 && gm->joins==0);
 actor.level=1;peer.level=3;SwgxrParty::bump(&actor,q);check(actor.callerLocked && actor.isGrouped() && actor.getGroupID()==peer.getGroupID());check(actor.group->leader==&peer && gm->invitations==1 && gm->joins==1);auto snap=SwgxrParty::snapshot(&actor);check(snap["members"].size()==2 && snap["leader_id"]=="2");SwgxrParty::bump(&actor,q);check(actor.callerLocked && gm->invitations==1 && gm->joins==1);
 reset();actor.skills.insert("outdoors_squadleader_novice");SwgxrParty::bump(&actor,q);check(actor.group->leader==&actor && actor.callerLocked);reset();GroupObject existing;existing.leader=&leader;existing.members={&leader,&peer};leader.group=peer.group=&existing;SwgxrParty::bump(&actor,q);check(actor.group==&existing && actor.group->leader==&leader && existing.members.size()==3 && actor.callerLocked);
 reset();existing.members={&leader,&actor};existing.leader=&leader;leader.group=actor.group=&existing;peer.skills.insert("outdoors_squadleader_novice");SwgxrParty::bump(&actor,q);check(actor.group==peer.group && actor.group->leader==&peer && actor.callerLocked);
 reset();GroupObject full;full.leader=&leader;full.members.assign(20,&leader);leader.group=peer.group=&full;bad("native_group_full");check(!actor.group && gm->invitations==0);reset();GroupObject a,b;b.id=91;a.leader=&actor;b.leader=&peer;a.members={&actor};b.members={&peer};actor.group=&a;peer.group=&b;bad("cannot_merge_existing_parties");check(actor.group==&a && peer.group==&b && gm->invitations==0);
 reset();gm->denyInvite=true;bad("native_group_invitation_rejected");check(!actor.group && !peer.group && gm->joins==0);gm->denyInvite=false;reset();gm->denyJoin=true;bad("native_group_join_rejected");check(!actor.group && !peer.group);gm->denyJoin=false;
 std::cout<<checks<<" production party formation and actor-lock restoration checks passed\n";
}
