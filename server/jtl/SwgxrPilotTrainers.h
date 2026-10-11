#pragma once
#include "server/zone/objects/creature/conversation/LuaConversationObserver.h"
#include "server/zone/objects/player/sessions/ConversationSession.h"
#include <set>
// Existing pilot screenplays own enlistment, skill gates, missions and rewards.
// This bridge presents their actual conversation screens; it creates no quests.
class SwgxrPilotTrainers {
 using Json=JSONSerializationType;
 static std::string text(const String& s){return s.toCharArray();}
 static std::string id(SceneObject* s){return std::to_string(s->getObjectID());}
 static ConversationTemplate* conversation(SceneObject* npc){
  if(!npc || !npc->isAiAgent())return nullptr;
  return CreatureTemplateManager::instance()->getConversationTemplate(npc->asAiAgent()->getConvoTemplateCRC());
 }
public:
 static bool supports(SceneObject* npc){
  auto t=conversation(npc);if(!t)return false;
  static const std::set<std::string> handlers={"fernYarrowConvoHandler","guilloParootchieConvoHandler","ioTsomcrenConvoHandler","j1p0ConvoHandler","kessYarrowConvoHandler","kultonWoodleConvoHandler","moochDavoneyConvoHandler","ralMundiConvoHandler","raneYarrowConvoHandler","tarthJaxxConvoHandler","vincieKalhoonConvoHandler","imperialBrokerConvoHandler","ramnaConvoHandler","rheaConvoHandler","rikkhConvoHandler","turoldineConvoHandler","gilBurtinConvoHandler","dingeConvoHandler","duliosConvoHandler","kaydineConvoHandler","aqzowConvoHandler","kreezoConvoHandler","viopaConvoHandler","vrakConvoHandler","jPaiBrekConvoHandler"};
  return handlers.count(text(t->getLuaClassHandler()))!=0 || t->getLuaClassHandler().beginsWith("swgxrPilotSource_");
 }
 static void describe(CreatureObject* c,SceneObject* npc,Json& out){
  auto stored=c->getPlayerObject()->getScreenPlayData("swgxr_pilot","view");
  Reference<ConversationSession*> session=c->getActiveSession(SessionFacadeType::CONVERSATION).castTo<ConversationSession*>();
  if(!stored.isEmpty() && session && session->getNPC().get()==npc){
   auto view=Json::parse(stored.toCharArray());if(view.value("npc_id",std::string())==id(npc)){out.update(view);return;}
  }
  out["dialogue"]="Speak to this pilot trainer about enlistment, training and missions.";
  out["options"]=Json::array({{{"name","Speak to pilot trainer"},{"begin",true}}});
 }
 static Json run(CreatureObject* c,SceneObject* npc,const Json& request){
  if(!supports(npc) || !c->isInRange(npc,5) || c->getParentID()!=npc->getParentID() || !CollisionManager::checkLineOfSight(c,npc))throw std::runtime_error("pilot_trainer_out_of_reach");
  auto ghost=c->getPlayerObject();auto t=conversation(npc);
  Reference<ConversationSession*> session=c->getActiveSession(SessionFacadeType::CONVERSATION).castTo<ConversationSession*>();
  bool begin=request.at("action")=="pilot_begin";int selected=-1;
  if(begin){if(session)session->cancelSession();c->dropActiveSession(SessionFacadeType::CONVERSATION);session=new ConversationSession(npc);c->addActiveSession(SessionFacadeType::CONVERSATION,session);ghost->setConversatingObject(npc);}
  else{
   auto saved=ghost->getScreenPlayData("swgxr_pilot","view");auto view=saved.isEmpty()?Json::object():Json::parse(saved.toCharArray());
   if(!session || session->getNPC().get()!=npc || view.value("npc_id",std::string())!=id(npc) || view.value("screen_token",std::string())!=request.value("screen_token",std::string()))throw std::runtime_error("pilot_conversation_changed");
   auto screen=session->getLastConversationScreen();selected=request.at("option").get<int>();
   if(!screen || selected<0 || selected>=screen->getOptionCount())throw std::runtime_error("pilot_conversation_option_unavailable");
  }
  Reference<LuaConversationObserver*> observer=new LuaConversationObserver(npc->asAiAgent()->getConvoTemplateCRC());
  Reference<ConversationScreen*> screen=observer->getNextConversationScreen(c,selected,npc);
  if(screen)screen=observer->runScreenHandlers(c,npc,selected,screen);
  Json view={{"npc_id",id(npc)},{"screen_token",request.at("request_id")},{"options",Json::array()},{"dialogue","Conversation finished."}};
  if(screen){
   view["dialogue"]=screen->getCustomDialogText().isEmpty()?text(screen->getDialogText()->getFullPath()):text(screen->getCustomDialogText().toString());view["screen_id"]=text(screen->getScreenID());
   for(int i=0;i<screen->getOptionCount();++i)view["options"].push_back({{"name",(screen->getOption(i)->getCustomOption().isEmpty()?text(screen->getOptionText(i)):text(screen->getOption(i)->getCustomOption().toString()))},{"option",i}});
   screen->sendTo(c,npc);
  }else{if(session)session->cancelSession();c->dropActiveSession(SessionFacadeType::CONVERSATION);}
  if(view["options"].empty())view["options"].push_back({{"name","Speak again"},{"begin",true}});
  ghost->setScreenPlayData("swgxr_pilot","view",String(view.dump().c_str()));c->updateToDatabaseAllObjects(false);
  return view;
 }
};
