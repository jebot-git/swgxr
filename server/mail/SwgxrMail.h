#ifndef SWGXR_MAIL_H
#define SWGXR_MAIL_H
#include "server/chat/ChatManager.h"
#include "server/chat/PersistentMessage.h"
#include "server/zone/objects/tangible/component/Component.h"
#include "server/zone/objects/tangible/tool/SurveyTool.h"
#include "server/zone/managers/resource/InterplanetarySurvey.h"
#include "server/zone/managers/resource/InterplanetarySurveyTask.h"
#include "server/zone/objects/player/sui/callbacks/TipCommandSuiCallback.h"
class SwgxrMail {
 using Json=JSONSerializationType;
 static std::string text(const String& s){return s.toCharArray();}
 static uint64 oid(const Json& r,const char* key){return std::stoull(r.at(key).get<std::string>());}
 static ManagedReference<PersistentMessage*> owned(CreatureObject* c,const Json& r){
  auto id=oid(r,"mail_id");auto ghost=c->getPlayerObject();ghost->checkPendingMessages();
  if(!ghost->getPersistentMessages()->contains(id))throw std::runtime_error("owned_mail_required");
  auto mail=Core::getObjectBroker()->lookUp(id).castTo<PersistentMessage*>();
  if(mail==nullptr || mail->getReceiverObjectID()!=c->getObjectID())throw std::runtime_error("owned_mail_required");return mail;
 }
 static bool carried(CreatureObject* c,SceneObject* o){
  if(o==nullptr)return false;auto inv=c->getInventory();auto p=o->getParent().get();
  for(int depth=0;p!=nullptr && depth<10;++depth){if(p==inv)return true;if(p->getParentID()==c->getObjectID() && p->isContainerObject())return true;p=p->getParent().get();}return false;
 }
 static void scan(CreatureObject* c,SceneObject* bag,Json& probes,Json& tools,int depth=0){
  if(bag==nullptr || depth>8)return;
  for(int i=0;i<bag->getContainerObjectsSize();++i){auto o=bag->getContainerObject(i);auto survey=o.castTo<SurveyTool*>();
   if(survey!=nullptr && tools.size()<128)tools.push_back({{"id",std::to_string(o->getObjectID())},{"name",text(o->getDisplayedName())},{"type",text(survey->getSurveyType())}});
   if(probe(o) && probes.size()<128){auto component=cast<Component*>(o.get());float q=component->getAttributeValue("mechanism_quality");probes.push_back({{"id",std::to_string(o->getObjectID())},{"name",text(o->getDisplayedName())},{"duration_seconds",duration(q)}});}
   if(o->isContainerObject())scan(c,o,probes,tools,depth+1);
  }
 }
 static int duration(float quality){if(!std::isfinite(quality))throw std::runtime_error("invalid_probe_quality");return std::max(1,int(3600-27*std::max(0.f,std::min(100.f,quality))));}
public:
 static bool probe(SceneObject* o){return o!=nullptr && o->getObjectTemplate()!=nullptr && o->getObjectTemplate()->getFullTemplateString()=="object/tangible/component/droid/droid_interplanetary_survey.iff" && dynamic_cast<Component*>(o)!=nullptr;}
 static Json snapshot(CreatureObject* c,const Json& r){
  auto ghost=c->getPlayerObject();ghost->checkPendingMessages();auto messages=ghost->getPersistentMessages();auto action=r.value("action",std::string());
  bool full=action.rfind("mail_",0)==0 && action!="mail_status";int unread=0,total=0,offset=r.value("page",0)*50;Json rows=Json::array();
  for(int i=messages->size()-1;i>=0;--i){auto mail=Core::getObjectBroker()->lookUp(messages->get(i)).castTo<PersistentMessage*>();if(mail==nullptr || mail->getReceiverObjectID()!=c->getObjectID())continue;Locker lock(mail,c);if(!mail->isRead())++unread;if(full && total>=offset && rows.size()<50)rows.push_back({{"id",std::to_string(mail->getObjectID())},{"sender",text(mail->getSenderName())},{"subject",text(mail->getSubject().toString())},{"timestamp",mail->getTimeStamp()},{"read",mail->isRead()}});++total;}
  Json out={{"unread",unread},{"total",total}};if(full){out["messages"]=rows;out["page"]=r.value("page",0);out["has_more"]=total>offset+50;}return out;
 }
 static Json read(CreatureObject* c,const Json& r){
  auto mail=owned(c,r);Locker lock(mail,c);mail->setStatus(PersistentMessage::READ);mail->updateToDatabase();
  Json out={{"id",std::to_string(mail->getObjectID())},{"sender",text(mail->getSenderName())},{"subject",text(mail->getSubject().toString())},{"body",text(mail->getBody().toString())},{"timestamp",mail->getTimeStamp()},{"read",true},{"parameters",Json::array()},{"waypoints",Json::array()}};
  auto params=mail->getStringIdParameters();for(int i=0;i<params->size();++i){Json p=params->get(i);for(auto key:{"TT","TU","TO"}){auto id=p[key].value("pointerParameter",uint64(0));if(id){auto o=c->getZoneServer()->getObject(id);if(o!=nullptr)p[key]["customName"]=text(o->getDisplayedName());}}out["parameters"].push_back(p);}
  auto waypoints=mail->getWaypointParameters();for(int i=0;i<waypoints->size();++i){Json p=waypoints->get(i);p["index"]=i;out["waypoints"].push_back(p);}return out;
 }
 static Json run(CreatureObject* c,const Json& r){
  auto action=r.at("action").get<std::string>();auto ghost=c->getPlayerObject();
  if(action=="mail_status" || action=="mail_list")return Json::object();
  if(action=="mail_read")return {{"message",read(c,r)}};
  if(action=="mail_delete"){auto mail=owned(c,r);ghost->getPersistentMessages()->drop(mail->getObjectID());ObjectManager::instance()->destroyObjectFromDatabase(mail->getObjectID());ghost->updateToDatabase();return Json::object();}
  if(action=="mail_waypoint"){
   auto mail=owned(c,r);Locker lock(mail,c);int index=r.at("index").get<int>();auto points=mail->getWaypointParameters();if(index<0 || index>=points->size())throw std::runtime_error("mail_waypoint_missing");auto p=points->get(index);
   auto point=c->getZoneServer()->createObject(0xc456e788,1).castTo<WaypointObject*>();if(point==nullptr)throw std::runtime_error("waypoint_creation_failed");point->setCustomObjectName(p.getWaypointName(),false);point->setPlanetCRC(p.getPlanetCRC());point->setPosition(p.getPositionX(),p.getPositionZ(),p.getPositionY());point->setColor(p.getColor());point->setActive(false);ghost->addWaypoint(point,false,true);return {{"waypoint_id",std::to_string(point->getObjectID())}};
  }
  if(action=="mail_send"){
   if(ghost->isMuted())throw std::runtime_error("mail_sending_muted");auto recipient=r.at("recipient").get<std::string>();auto subject=r.at("subject").get<std::string>(),body=r.at("body").get<std::string>();
   if(recipient.empty() || recipient.size()>40 || subject.empty() || subject.size()>512 || body.empty() || body.size()>16000)throw std::runtime_error("invalid_mail_fields");
   StringIdChatParameterVector parameters;WaypointChatParameterVector waypoints;Reference<PersistentMessage*> sent;
   auto code=c->getZoneServer()->getChatManager()->sendMail(c->getFirstName(),UnicodeString(String(subject.c_str())),UnicodeString(String(body.c_str())),String(recipient.c_str()),&parameters,&waypoints,&sent);
   if(code!=ChatManager::IM_SUCCESS || sent==nullptr)throw std::runtime_error("native_mail_send_rejected_"+std::to_string(code));return {{"sent_id",std::to_string(sent->getObjectID())}};
  }
  throw std::runtime_error("unsupported_mail_action");
 }
 static Json probeState(CreatureObject* c){Json out={{"probes",Json::array()},{"tools",Json::array()},{"planets",Json::array()},{"eligible",c->getPlayerObject()->hasAbility("survey")}};scan(c,c->getInventory(),out["probes"],out["tools"]);auto bag=c->getSlottedObject("back");if(bag!=nullptr && bag!=c->getInventory())scan(c,bag,out["probes"],out["tools"]);for(auto planet:{"tatooine","naboo","corellia","rori","talus","dantooine","dathomir","endor","lok","yavin4"})if(c->getZoneServer()->getZone(planet)!=nullptr)out["planets"].push_back(planet);return out;}
 static Json launch(CreatureObject* c,const Json& r){
  auto droid=c->getZoneServer()->getObject(oid(r,"probe_id"));auto tool=c->getZoneServer()->getObject(oid(r,"tool_id")).castTo<SurveyTool*>();auto planet=r.at("target_planet").get<std::string>();
  if(!c->getPlayerObject()->hasAbility("survey"))throw std::runtime_error("survey_ability_required");
  if(!carried(c,droid) || !probe(droid) || !carried(c,tool) || tool==nullptr)throw std::runtime_error("owned_probe_and_survey_tool_required");
  if(!SwgxrPlanets::supported(String(planet.c_str())) || c->getZoneServer()->getZone(String(planet.c_str()))==nullptr)throw std::runtime_error("survey_planet_unavailable");
  Locker probeLock(droid,c);Locker toolLock(tool,c);auto component=cast<Component*>(droid.get());int seconds=duration(component->getAttributeValue("mechanism_quality"));
  ManagedReference<InterplanetarySurvey*> data=new InterplanetarySurvey();Time now;data->setPlanet(String(planet.c_str()));data->setSurveyToolType(tool->getToolType());data->setSurveyType(tool->getSurveyType());data->setRequestor(c->getFirstName());data->setCurTime(now.getMiliTime());data->setRequestedAt(now.getMiliTime());data->setTimeStamp(seconds*1000);
  ObjectManager::instance()->persistObject(data,1,"surveys");tool->destroyObjectFromWorld(true);tool->destroyObjectFromDatabase(true);component->decreaseUseCount();Reference<InterplanetarySurveyTask*> task=new InterplanetarySurveyTask(data);task->schedule(seconds*1000);
  return {{"survey_id",std::to_string(data->_getObjectID())},{"duration_seconds",seconds},{"report_due",now.getMiliTime()/1000+seconds},{"target_planet",planet}};
 }
 static Json bank(CreatureObject* c,const Json& r){
  auto recipient=r.at("recipient").get<std::string>();auto target=c->getZoneServer()->getPlayerManager()->getPlayer(String(recipient.c_str()));
  if(target==nullptr || target==c || target->getPlayerObject()==nullptr)throw std::runtime_error("valid_other_player_required");Locker lock(target,c);
  if(target->getPlayerObject()->isIgnoring(c->getFirstName()))throw std::runtime_error("bank_transfer_unavailable");
  int64 amount=r.at("amount").get<int64>();if(amount<=0 || amount>2000000000)throw std::runtime_error("invalid_amount");
  int fee=amount<21?1:int(std::round(amount*.05));if(ConfigManager::instance()->getBool("Core3.SameAccountTipsAreFree",false) && c->getPlayerObject()->getAccountID()==target->getPlayerObject()->getAccountID())fee=0;
  if(amount+fee>c->getBankCredits() || int64(target->getBankCredits())+amount>2147483647)throw std::runtime_error("insufficient_funds_or_balance_limit");
  Json quote={{"recipient",text(target->getFirstName())},{"recipient_id",std::to_string(target->getObjectID())},{"amount",amount},{"fee",fee},{"total",amount+fee}};
  if(r.at("action")=="bank_quote")return {{"quote",quote}};
  if(r.at("recipient_id")!=quote["recipient_id"] || r.at("fee")!=quote["fee"])throw std::runtime_error("bank_quote_changed");
  auto command=c->getZoneServer()->getObjectController()->getQueueCommand("tip");if(command==nullptr)throw std::runtime_error("native_tip_missing");
  int64 before=c->getBankCredits(),targetBefore=target->getBankCredits();std::string args=std::to_string(amount)+" bank";
  if(command->doQueueCommand(c,target->getObjectID(),UnicodeString(String(args.c_str())))!=QueueCommand::SUCCESS)throw std::runtime_error("native_bank_tip_rejected");
  auto ghost=c->getPlayerObject();auto box=ghost->getSuiBoxFromWindowType(SuiWindowType::BANK_TIP_CONFIRM);auto callback=box!=nullptr?dynamic_cast<TipCommandSuiCallback*>(box->getCallback()):nullptr;if(callback==nullptr)throw std::runtime_error("native_bank_confirmation_missing");Vector<UnicodeString> answers;callback->run(c,box,0,&answers);ghost->closeSuiWindowType(SuiWindowType::BANK_TIP_CONFIRM);
  if(c->getBankCredits()!=before-amount-fee || target->getBankCredits()!=targetBefore+amount)throw std::runtime_error("native_bank_transfer_not_completed");target->updateToDatabase();return {{"transfer",quote}};
 }
};
#endif
