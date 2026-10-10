#pragma once
#include "server/zone/objects/creature/conversation/LuaConversationObserver.h"
#include "server/zone/objects/player/sessions/ConversationSession.h"
// Original station conversation handlers own landing destinations and repairs.
class SwgxrStationComms {
 using Json=JSONSerializationType;
 static std::string text(const String& s){return s.toCharArray();}
 static std::string id(SceneObject* s){return std::to_string(s->getObjectID());}
public:
 static Json run(CreatureObject* c,ShipObject* ship,SceneObject* npc,const Json& request){
  if(!npc || !npc->isSpaceStation() || npc->getZone()!=ship->getZone() || !ship->checkInConversationRange(npc))throw std::runtime_error("station_communications_out_of_range");
  auto crc=npc->asShipAiAgent()->getConversationTemplate();
  if(!crc)throw std::runtime_error("station_conversation_unavailable");
  auto ghost=c->getPlayerObject();
  Reference<ConversationSession*> session=c->getActiveSession(SessionFacadeType::CONVERSATION).castTo<ConversationSession*>();
  bool begin=request.at("action")=="comm_begin";int selected=-1;
  if(begin){if(session)session->cancelSession();c->dropActiveSession(SessionFacadeType::CONVERSATION);session=new ConversationSession(npc);c->addActiveSession(SessionFacadeType::CONVERSATION,session);ghost->setConversatingObject(npc);}
  else{
   auto saved=ghost->getScreenPlayData("swgxr_station","view");auto view=saved.isEmpty()?Json::object():Json::parse(saved.toCharArray());
   if(!session || session->getNPC().get()!=npc || view.value("npc_id",std::string())!=id(npc) || view.value("screen_token",std::string())!=request.value("screen_token",std::string()))throw std::runtime_error("station_conversation_changed");
   auto screen=session->getLastConversationScreen();selected=request.at("option").get<int>();
   if(!screen || selected<0 || selected>=screen->getOptionCount())throw std::runtime_error("station_conversation_option_unavailable");
  }
  Reference<LuaConversationObserver*> observer=new LuaConversationObserver(crc);
  Reference<ConversationScreen*> screen=observer->getNextConversationScreen(c,selected,npc);
  if(screen)screen=observer->runScreenHandlers(c,npc,selected,screen);
  Json view={{"npc_id",id(npc)},{"screen_token",request.at("request_id")},{"options",Json::array()},{"dialogue","Conversation finished."}};
  if(screen){
   view["dialogue"]=text(screen->getDialogText()->getFullPath());view["screen_id"]=text(screen->getScreenID());
   for(int i=0;i<screen->getOptionCount();++i)view["options"].push_back({{"name",text(screen->getOptionText(i))},{"option",i}});
   screen->sendTo(c,npc);
  }else{if(session)session->cancelSession();c->dropActiveSession(SessionFacadeType::CONVERSATION);}
  if(view["options"].empty())view["options"].push_back({{"name","Speak again"},{"begin",true}});
  ghost->setScreenPlayData("swgxr_station","view",String(view.dump().c_str()));c->updateToDatabaseAllObjects(false);
  return view;
 }
};
