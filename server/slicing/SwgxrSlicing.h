#ifndef SWGXR_SLICING_H
#define SWGXR_SLICING_H
#include "SwgxrSlicingData.h"
#include "SwgxrSlicingPuzzle.h"
#include "SwgxrSlicingRewards.h"
#include "SwgxrGathering.h"
#include "server/zone/objects/tangible/weapon/WeaponObject.h"
#include "server/zone/managers/skill/SkillModManager.h"
#include "server/zone/objects/tangible/terminal/mission/MissionTerminal.h"
#include "server/zone/objects/tangible/tool/smuggler/PrecisionLaserKnife.h"
#include "server/zone/objects/tangible/Container.h"
#include "server/zone/managers/loot/LootManager.h"
#include "server/zone/objects/transaction/TransactionLog.h"
#include "server/zone/managers/collision/CollisionManager.h"
#include <random>
class SwgxrSlicing {
 using Json=JSONSerializationType;
 using Puzzle=SwgxrSlicingPuzzle::Board;
 static double now(){return SwgxrSlicingData::now();}
 static uint64 incarnation(){static uint64 value=System::getMiliTime();return value;}
 static Json load(CreatureObject* c){auto raw=c->getPlayerObject()->getScreenPlayData("swgxr_slicing","state");return raw.isEmpty()?Json::object():Json::parse(raw.toCharArray());}
 static void save(CreatureObject* c,const Json& s){c->getPlayerObject()->setScreenPlayData("swgxr_slicing","state",String(s.dump().c_str()));c->getPlayerObject()->updateToDatabase();}
 static Vector3 point(const Json& a){if(!a.is_array() || a.size()!=3)throw std::runtime_error("slicing_invalid_position");for(auto& v:a)if(!v.is_number() || !std::isfinite(v.get<double>()) || std::abs(v.get<double>())>10000)throw std::runtime_error("slicing_invalid_position");return Vector3(a[0].get<float>(),a[2].get<float>(),a[1].get<float>());}
 static Json wire(const Vector3& p){return Json::array({p.getX(),p.getZ(),p.getY()});}
 static void setData(TangibleObject* t,const Json& d){t->setLuaStringData("swgxr_slice",String(d.dump().c_str()));t->updateToDatabase();}
 static ManagedReference<TangibleObject*> target(CreatureObject* c,const Json& s){auto id=s.value("target_id",std::string());return id.empty()?nullptr:c->getZoneServer()->getObject(std::stoull(id)).castTo<TangibleObject*>();}
 static bool ownedKnife(CreatureObject* c,SceneObject* tool){if(!tool || !SwgxrSlicingData::tool(tool))return false;try{auto state=SwgxrGathering::load(c);return SwgxrGathering::ownedTool(c,state,std::to_string(tool->getObjectID())).get()==tool;}catch(const std::exception&){return false;}}
 static void settleCharge(CreatureObject* c,const Json& s){
  auto toolId=s.value("tool_id",std::string());if(toolId.empty())return;auto tool=c->getZoneServer()->getObject(std::stoull(toolId)).castTo<PrecisionLaserKnife*>();if(!tool)return;
  Locker toolLock(tool,c);auto d=SwgxrSlicingData::data(tool);if(d.value("reservation",std::string())!=s.value("attempt_id",std::string()))return;
  int desired=d.value("charge_after",std::max(0,int(tool->getUseCount())-1));desired=std::min(desired,int(tool->getUseCount()));
  // Persist the absolute reserved outcome before forgetting the reservation.
  // Repeating this after a restart cannot spend an additional charge.
  tool->setUseCount(desired);tool->updateCharges(desired);tool->updateToDatabase();
  if(desired==0){SwgxrSlicingData::Settlement settlement(tool);tool->destroyObjectFromWorld(true);tool->destroyObjectFromDatabase(true);return;}
  d["lease_until"]=0;d.erase("reservation");d.erase("charge_before");d.erase("charge_after");setData(tool,d);
 }
 static void finish(CreatureObject* c,Json& s,const char* status){
  settleCharge(c,s);auto t=target(c,s);if(t && s.value("target_kind",std::string())=="item"){Locker targetLock(t,c);auto d=SwgxrSlicingData::data(t);d["lease_until"]=0;d["status"]=status;setData(t,d);}s["active"]=false;s["status"]=status;save(c,s);
 }
 class Watch:public Task {ManagedWeakReference<CreatureObject*> owner;public:Watch(CreatureObject* c):owner(c){}void run(){auto c=owner.get();if(!c)return;Locker lock(c);c->removePendingTask("swgxr_slicing");reconcile(c);ensure(c);}};
 static void ensure(CreatureObject* c){if(load(c).value("active",false) && c->getPendingTask("swgxr_slicing")==nullptr)c->addPendingTask("swgxr_slicing",new Watch(c),500);}
 static void reconcile(CreatureObject* c){auto s=load(c);if(!s.value("active",false)){settleCharge(c,s);return;}const char* reason=nullptr;
  if(s.value("incarnation",uint64(0))!=incarnation())reason="interrupted";
  else if(now()>=s.value("deadline",0.0))reason="expired";
  else if(!c->isOnline() || c->getPlayerObject()->isOffline())reason="disconnected";
  else if(c->isDead() || c->isIncapacitated() || c->isInCombat() || c->hasBuff(STRING_HASHCODE("private_feign_buff")))reason="interrupted";
  else if(!c->getZone() || s.value("zone",std::string())!=std::string(c->getZone()->getZoneName().toCharArray()) || s.value("cell_id",uint64(0))!=c->getParentID() || point(s.at("origin")).distanceTo(c->getWorldPosition())>ABANDON_DISTANCE)reason="walked_away";
  else {auto t=target(c,s);auto knife=c->getZoneServer()->getObject(std::stoull(s.at("tool_id").get<std::string>()));if(!ownedKnife(c,knife) || !t || (s.value("target_kind",std::string())=="item" && !t->isASubChildOf(c->getInventory())))reason="ownership_changed";}
  if(reason)finish(c,s,reason);
 }
 static Json challenge(const Puzzle& b){Json out={{"size",b.size},{"pairs",Json::array()},{"preconnected",Json::array()}};for(auto& p:b.pairs)out["pairs"].push_back({{"color",p.color},{"ends",Json::array({Json{{"cell",p.a.cell},{"face",p.a.face}},Json{{"cell",p.b.cell},{"face",p.b.face}}})}});for(auto& w:b.preconnected)out["preconnected"].push_back({{"color",w.color},{"cells",w.cells}});return out;}
 static Puzzle board(const Json& s){Puzzle b;b.size=s.at("challenge").at("size").get<int>();for(auto& p:s.at("challenge").at("pairs"))b.pairs.push_back({p.at("color").get<int>(),{p.at("ends")[0].at("cell").get<SwgxrSlicingPuzzle::Cell>(),p.at("ends")[0].at("face").get<SwgxrSlicingPuzzle::Cell>()},{p.at("ends")[1].at("cell").get<SwgxrSlicingPuzzle::Cell>(),p.at("ends")[1].at("face").get<SwgxrSlicingPuzzle::Cell>()}});return b;}
 static int roll(int lo,int hi){return lo+System::random(hi-lo);}
 static Json rewards(const std::string& kind,int tier,bool ranged){
  static const int mods[6][2]={{1,5},{4,8},{8,12},{12,16},{16,20},{20,25}};
  static const int pct[6][2]={{5,10},{8,15},{10,20},{12,25},{15,30},{20,35}};
  Json out={{"bonuses",Json::object()},{"skill_mods",Json::array()}};auto& b=out["bonuses"];
  if(kind=="weapon"){static const char* choices[]={"capacity_pct","rof_pct","power_pct","stance_recovery_pct"};b[choices[(ranged?0:2)+System::random(1)]]=roll(pct[tier][0],pct[tier][1]);b["range_pct"]=roll(pct[tier][0],pct[tier][1]);int lo=tier==5?20:tier==4?15:10,hi=tier==5?35:tier==4?30:25,which=System::random(2);if(which!=1)b["min_damage_pct"]=roll(lo,hi);if(which!=0)b["max_damage_pct"]=roll(lo,hi);}
  else {std::vector<std::string> pool;if(kind=="clothing")pool={"healing_injury_treatment","healing_wound_treatment","healing_injury_speed","healing_wound_speed","foraging","surveying","slope_move","general_assembly","general_experimentation","weapon_assembly","weapon_experimentation","armor_assembly","armor_experimentation","clothing_assembly","clothing_experimentation","medicine_assembly","medicine_experimentation","food_assembly","food_experimentation","healing_music_wound","healing_dance_wound"};else pool={"unarmed_damage","onehandmelee_damage","twohandmelee_damage","unarmed_accuracy","onehandmelee_accuracy","twohandmelee_accuracy","polearm_accuracy","pistol_accuracy","carbine_accuracy","rifle_accuracy","ranged_defense","melee_defense","dodge","block","counterattack","blind_defense","dizzy_defense","stun_defense","intimidate_defense"};
   pool.erase(std::remove_if(pool.begin(),pool.end(),[](const std::string& mod){return SkillModManager::instance()->isWearableModDisabled(String(mod.c_str()));}),pool.end());
   int count=kind=="clothing"?(tier==5?6:tier):(tier==5?2:1);for(int i=0;i<count && !pool.empty();++i){int at=System::random(pool.size()-1);out["skill_mods"].push_back({{"id",pool[at]},{"value",roll(mods[tier][0],mods[tier][1])}});pool.erase(pool.begin()+at);}
   if(kind!="clothing"){static const char* costs[]={"sac_health_pct","sac_action_pct","sac_mind_pct"};b[costs[System::random(2)]]=roll(pct[tier][0],pct[tier][1]);b["protection_pct"]=roll(tier==5?11:5,tier==5?35:tier==4?30:20);}
  }return out;
 }
 static void reward(CreatureObject* c,Json& s){auto t=target(c,s);if(!t)throw std::runtime_error("slicing_target_missing");if(s.at("target_kind")=="terminal"){SwgxrSlicingRewards::terminalSuccess(c);c->getPlayerObject()->setScreenPlayData("swgxr_slicing","terminal_"+String::valueOf(t->getObjectID()),"success");c->getZoneServer()->getPlayerManager()->awardExperience(c,"slicing",100,true);return;}
  auto kind=s.at("slice_kind").get<std::string>();if(kind=="container"){
   auto created=c->getZoneServer()->createObject(STRING_HASHCODE("object/tangible/container/loot/loot_crate.iff"),1).castTo<Container*>();if(!created)throw std::runtime_error("native_loot_container_unavailable");Locker lock(created,c);TransactionLog trx(TrxCode::SLICECONTAINER,c,created);if(System::random(10)!=4)c->getZoneServer()->getLootManager()->createLoot(trx,created,"looted_container");auto parent=t->getParent().get();auto d=SwgxrSlicingData::data(t);d["lease_until"]=0;setData(t,d);t->destroyObjectFromWorld(true);t->destroyObjectFromDatabase(true);if(!parent->transferObject(created,-1,true))throw std::runtime_error("native_loot_transfer_failed");created->sendTo(c,true);trx.commit();s["result_item_id"]=std::to_string(created->getObjectID());
  }else{auto d=SwgxrSlicingData::data(t);auto rolled=rewards(kind,s.at("tier").get<int>(),t->isWeaponObject() && static_cast<WeaponObject*>(t.get())->isRangedWeapon());d["bonuses"]=rolled["bonuses"];d["skill_mods"]=rolled["skill_mods"];setData(t,d);s["result"]=rolled;t->sendAttributeListTo(c);}
  c->getZoneServer()->getPlayerManager()->awardExperience(c,"slicing",250,true);
 }
public:
 static constexpr int DURATION_SECONDS=180;
 static constexpr double ABANDON_DISTANCE=2.5;
 static bool terminalBlocked(CreatureObject* c,SceneObject* t){auto v=c->getPlayerObject()->getScreenPlayData("swgxr_slicing","terminal_"+String::valueOf(t->getObjectID()));return !v.isEmpty() && v!="success";}
 static void describeTerminal(CreatureObject* c,SceneObject* object,Json& out){if(!object || !object->isMissionTerminal())return;auto term=static_cast<MissionTerminal*>(object);std::string reason=SwgxrSlicingData::tier(c)<1?"slicing_skill_required":term->isBountyTerminal() || term->isStatueTerminal() || term->isNewbieTerminal()?"unsupported_terminal":terminalBlocked(c,object)?"terminal_slice_permanently_failed":!c->checkCooldownRecovery("slicing.terminal")?"slicing_terminal_cooldown":"";out["sliceable"]=reason.empty();out["slice_block_reason"]=reason;out["slice_required_tier"]=1;}
 static Json snapshot(CreatureObject* c){reconcile(c);auto s=load(c);if(s.empty())return {{"active",false},{"status","idle"}};s.erase("_witness");s.erase("incarnation");s.erase("origin");s.erase("zone");s.erase("cell_id");s["remaining_seconds"]=s.value("active",false)?std::max(0.0,s.value("deadline",0.0)-now()):0.0;ensure(c);return s;}
 static Json run(CreatureObject* c,const Json& r){reconcile(c);auto s=load(c);auto action=r.at("action").get<std::string>();auto token=r.value("attempt_id",std::string());
  if(action=="slicing_status"){if(!token.empty() && token!=s.value("attempt_id",std::string()))throw std::runtime_error("slicing_attempt_mismatch");return {{"success",true}};}
  if(action=="slicing_begin"){
   if(s.value("active",false))throw std::runtime_error("slicing_already_active");int tier=SwgxrSlicingData::tier(c);if(tier<0)throw std::runtime_error("novice_smuggler_required");if(c->isDead() || c->isIncapacitated() || c->isInCombat())throw std::runtime_error("native_player_unavailable");
   auto tool=c->getZoneServer()->getObject(std::stoull(r.at("tool_id").get<std::string>())).castTo<PrecisionLaserKnife*>();if(!tool || !SwgxrSlicingData::tool(tool) || !ownedKnife(c,tool) || tool->getUseCount()<1)throw std::runtime_error("owned_charged_slicing_tool_required");
   auto t=c->getZoneServer()->getObject(std::stoull(r.at("target_id").get<std::string>())).castTo<TangibleObject*>();if(!t)throw std::runtime_error("slicing_target_missing");Locker targetLock(t,c);auto targetKind=r.at("target_kind").get<std::string>();std::string kind;
   if(targetKind=="terminal"){auto term=t.castTo<MissionTerminal*>();if(tier<1 || !term || term->isBountyTerminal() || term->isStatueTerminal() || term->isNewbieTerminal() || term->getZone()!=c->getZone() || term->getParentID()!=c->getParentID() || !c->isInRange(term,3) || !CollisionManager::checkLineOfSight(c,term))throw std::runtime_error("sliceable_nearby_mission_terminal_required");if(terminalBlocked(c,t))throw std::runtime_error("terminal_slice_permanently_failed");if(!c->checkCooldownRecovery("slicing.terminal"))throw std::runtime_error("slicing_terminal_cooldown");auto city=c->getCityRegion().get();if(city && !city->isClientRegion() && city->isBanned(c->getObjectID()))throw std::runtime_error("city_banned_services");kind="terminal";
   }else if(targetKind=="item"){if(!c->getInventory() || !t->isASubChildOf(c->getInventory()))throw std::runtime_error("unequipped_owned_inventory_target_required");auto reason=SwgxrSlicingData::reason(t,c);if(!reason.empty())throw std::runtime_error(reason);kind=SwgxrSlicingData::kind(t);}else throw std::runtime_error("invalid_slice_target_kind");
   auto tip=point(r.at("tool_position")),anchor=point(r.at("anchor_position")),contact=targetKind=="terminal"?t->getWorldPosition():point(r.at("target_position"));if(tip.distanceTo(c->getWorldPosition())>3 || contact.distanceTo(c->getWorldPosition())>3 || anchor.distanceTo(c->getWorldPosition())>2.5 || tip.distanceTo(contact)>(targetKind=="terminal"?1.5:.65))throw std::runtime_error("slicing_tool_contact_or_reach");
   double heading=r.at("heading_radians").get<double>();if(!std::isfinite(heading))throw std::runtime_error("invalid_slicing_heading");auto puzzle=SwgxrSlicingPuzzle::generate(3+System::random(2),2+System::random(2),System::random(0x7ffffffe));std::string id="slice_"+std::to_string(c->getObjectID())+"_"+std::to_string(System::getMiliTime())+"_"+std::to_string(System::random(999999));
   s={{"active",true},{"status","active"},{"attempt_id",id},{"target_kind",targetKind},{"slice_kind",kind},{"target_id",r.at("target_id")},{"tool_id",r.at("tool_id")},{"anchor_position",wire(anchor)},{"heading_radians",heading},{"cell_size",.1},{"abandon_distance",ABANDON_DISTANCE},{"deadline",now()+DURATION_SECONDS},{"origin",wire(c->getWorldPosition())},{"zone",std::string(c->getZone()->getZoneName().toCharArray())},{"cell_id",c->getParentID()},{"incarnation",incarnation()},{"tier",tier},{"challenge",challenge(puzzle)},{"_witness",Json::array()}};for(auto& w:puzzle.witness)s["_witness"].push_back({{"color",w.color},{"cells",w.cells}});
   if(targetKind=="item"){auto d=SwgxrSlicingData::data(t);d["burned"]=true;d["kind"]=kind;d["status"]="active";d["attempt_id"]=id;d["lease_until"]=s["deadline"];setData(t,d);t->setSliced(true);t->updateToDatabase();}else{c->getPlayerObject()->setScreenPlayData("swgxr_slicing","terminal_"+String::valueOf(t->getObjectID()),String(id.c_str()));c->addCooldown("slicing.terminal",120000);}
   auto toolData=SwgxrSlicingData::data(tool);toolData["lease_until"]=s["deadline"];toolData["reservation"]=id;toolData["charge_before"]=tool->getUseCount();toolData["charge_after"]=int(tool->getUseCount())-1;setData(tool,toolData);save(c,s);ensure(c);return {{"success",true},{"attempt_id",id}};
  }
  if(token.empty() || token!=s.value("attempt_id",std::string()))throw std::runtime_error("slicing_attempt_mismatch");if(!s.value("active",false))return {{"success",s.value("status",std::string())=="succeeded"},{"status",s.value("status",std::string())},{"already_finished",true}};
  if(action=="slicing_cancel"){finish(c,s,"cancelled");return {{"success",true},{"status","cancelled"}};}
  if(action=="slicing_complete"){std::vector<SwgxrSlicingPuzzle::Wire> paths;for(auto& w:r.at("paths"))paths.push_back({w.at("color").get<int>(),w.at("cells").get<std::vector<SwgxrSlicingPuzzle::Cell>>()});std::string reason;if(!SwgxrSlicingPuzzle::validate(board(s),paths,&reason))return {{"success",false},{"status","active"},{"error",reason}};reward(c,s);finish(c,s,"succeeded");return {{"success",true},{"status","succeeded"}};}
  throw std::runtime_error("invalid_slicing_action");
 }
};
#endif
