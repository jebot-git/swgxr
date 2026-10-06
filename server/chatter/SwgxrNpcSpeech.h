#ifndef SWGXR_NPC_SPEECH_H
#define SWGXR_NPC_SPEECH_H
#include "server/zone/Zone.h"
#include "server/zone/objects/creature/ai/AiAgent.h"
#include "server/chat/ChatManager.h"
#include "server/chat/StringIdChatParameter.h"
#include "server/zone/objects/player/PlayerObject.h"
#include "server/zone/objects/cell/CellObject.h"
#include "server/zone/managers/collision/CollisionManager.h"
#include "server/zone/managers/skill/SkillManager.h"
#include <atomic>
#include <chrono>
#include <fstream>
#include <cstdlib>

// Only actual native spatial delivery calls receive(). Snapshot/replay cannot
// generate speech or change a player's persistent comprehension progress.
class SwgxrNpcSpeech {
 using Json=JSONSerializationType;
 static uint64 now(){return std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::system_clock::now().time_since_epoch()).count();}
 static const Json& catalog(){static const Json value=[](){for(const char* path:std::initializer_list<const char*>{std::getenv("SWGXR_CHATTER_CATALOG_PATH"),"../../../../runtime/assets/chatter/catalog.json","runtime/assets/chatter/catalog.json"}){if(!path)continue;std::ifstream file(path);if(!file)continue;try{Json value;file>>value;if(value.value("schema",0)==1 && value.contains("languages") && value["languages"].is_array() && value["languages"].size()<=32)return value;}catch(...) {}}Logger::console.warning("SWGXR NPC speech catalog missing or invalid; passive language learning and ambient chatter disabled. Prepare runtime/assets/chatter/catalog.json or set SWGXR_CHATTER_CATALOG_PATH.");return Json::object();}();return value;}
 static Json language(int id){auto& data=catalog();if(!data.contains("languages"))return Json::object();for(auto& row:data["languages"])if(row.value("id",0)==id && row.contains("comprehend_skill") && row.contains("speak_skill"))return row;return Json::object();}
 static Json load(CreatureObject* c){auto text=c->getPlayerObject()->getScreenPlayData("swgxr_languages","state");if(!text.isEmpty()){try{auto row=Json::parse(text.toCharArray());if(row.is_object())return row;}catch(...) {}}return {{"sequence",0},{"progress",Json::object()},{"seen",Json::array()},{"events",Json::array()}};}
 static int progress(CreatureObject* c,const Json& ledger,const Json& lang){String skill(lang.at("comprehend_skill").get<std::string>().c_str());if(c->hasSkill(skill))return 10000;return std::max(0,std::min(10000,ledger.value("progress",Json::object()).value(std::to_string(lang.at("id").get<int>()),0)));}
 class AmbientTask:public Task {
  ManagedWeakReference<CreatureObject*> owner;
 public:
  AmbientTask(CreatureObject* c):owner(c){}
  void run(){auto c=owner.get();if(!c)return;Locker lock(c);c->removePendingTask("swgxr_npc_ambient");ambient(c);ensureAmbient(c);}
 };
 static void ambient(CreatureObject* c){
  auto ghost=c->getPlayerObject();if(!ghost || !c->isOnline() || ghost->isOnLoadScreen() || c->isDead() || c->isIncapacitated() || c->isInCombat() || !c->getZone())return;
  auto& data=catalog();if(!data.contains("ambient_reactions"))return;
  SortedVector<TreeEntry*> objects(64,64);auto p=c->getWorldPosition();c->getZone()->getInRangeObjects(p.getX(),p.getZ(),p.getY(),32,&objects,true);int examined=0;
  for(int i=0;i<objects.size() && examined<64;++i){auto object=static_cast<SceneObject*>(objects.get(i));if(!object || !object->isAiAgent())continue;++examined;auto npc=object->asAiAgent();Locker lock(npc,c);
   if(!npc->isNpc() || npc->isPet() || npc->isDead() || npc->isIncapacitated() || npc->isInCombat() || npc->isAttackableBy(c) || npc->getParentID()!=c->getParentID() || !npc->checkCooldownRecovery("swgxr_ambient_speech") || !npc->checkCooldownRecovery("reaction_chat") || !CollisionManager::checkLineOfSight(npc,c))continue;
   std::string table=npc->getReactionStf().toCharArray();if(!table.empty() && table[0]=='@')table.erase(0,1);if(table.empty() && npc->getSocialGroup()=="townsperson" && npc->getConvoTemplateCRC()==0)table="npc_reaction/townperson";if(!data["ambient_reactions"].contains(table))continue;auto& keys=data["ambient_reactions"][table];if(!keys.is_array() || keys.empty())continue;
   auto key=keys[System::random(int(keys.size())-1)].get<std::string>();if(key.rfind("hi_mid_",0)!=0)continue;StringIdChatParameter message(String(table.c_str()),String(key.c_str()));npc->updateCooldownTimer("swgxr_ambient_speech",90000);npc->updateCooldownTimer("reaction_chat",90000);ManagedReference<AiAgent*> speaker=npc;String originalZone=npc->getZone()->getZoneName();uint64 originalCell=npc->getParentID();Reference<StringIdChatParameter*> chat=new StringIdChatParameter(message);
   Core::getTaskManager()->executeTask([speaker,originalZone,originalCell,chat](){Locker lock(speaker);if(!speaker->getZone() || speaker->getZone()->getZoneName()!=originalZone || speaker->getParentID()!=originalCell || speaker->isDead() || speaker->isIncapacitated() || speaker->isInCombat())return;speaker->getZoneServer()->getChatManager()->broadcastChatMessage(speaker,*chat.get(),0,0,speaker->getMoodID(),0,speciesLanguage(speaker));},"SwgxrAmbientSpeech");break;
  }
 }
public:
 static void ensureAmbient(CreatureObject* c){auto ghost=c->getPlayerObject();if(ghost && c->isOnline() && !ghost->isOnLoadScreen() && c->getPendingTask("swgxr_npc_ambient")==nullptr)c->addPendingTask("swgxr_npc_ambient",new AmbientTask(c),20000);}
 static int speciesLanguage(CreatureObject* npc){auto& data=catalog();if(!data.contains("species_languages"))return 1;return data["species_languages"].value(std::to_string(npc->getSpecies()),1);}
 static uint64 eventID(){static std::atomic<uint64> next{uint64(std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::system_clock::now().time_since_epoch()).count())};return ++next;}
 static void receive(CreatureObject* source,CreatureObject* receiver,uint64 event,int languageID,const Json& message,float nativeRange){
  if(!source || !source->isAiAgent() || !receiver || !receiver->isPlayerCreature())return;
  ManagedReference<CreatureObject*> speaker=source,listener=receiver;uint64 emitted=now();
  Core::getTaskManager()->executeTask([speaker,listener,event,languageID,message,nativeRange,emitted](){Locker lock(speaker);record(speaker,listener,event,languageID,message,nativeRange,emitted);},"SwgxrNpcSpeechReceipt");
 }
 static void record(CreatureObject* source,CreatureObject* receiver,uint64 event,int languageID,const Json& message,float nativeRange,uint64 emitted){
  uint64 timestamp=now();if(timestamp<emitted || timestamp-emitted>=6000)return;
  if(!source || !source->isAiAgent() || source->isPlayerCreature() || source->isDead() || source->isIncapacitated() || !receiver || !receiver->isPlayerCreature())return;
  Locker lock(receiver,source);timestamp=now();if(timestamp<emitted || timestamp-emitted>=6000)return;auto ghost=receiver->getPlayerObject();
  if(!ghost || !receiver->isOnline() || ghost->isOnLoadScreen() || receiver->isDead() || receiver->isIncapacitated() || !source->getZone() || source->getZone()!=receiver->getZone() || source->getParentID()!=receiver->getParentID() || !source->isInRange(receiver,std::min(32.f,nativeRange)) || !CollisionManager::checkLineOfSight(source,receiver))return;
  auto lang=language(languageID);if(lang.empty())return;auto ledger=load(receiver);std::string eid=std::to_string(event);auto seen=ledger.value("seen",Json::array());for(auto& prior:seen)if(prior==eid)return;
  int before=progress(receiver,ledger,lang),after=before;bool audible=lang.value("audible",false);
  if(audible && before<10000){after=std::min(10000,before+250);ledger["progress"][std::to_string(languageID)]=after;if(after==10000){String skill(lang.at("comprehend_skill").get<std::string>().c_str());if(!SkillManager::instance()->awardSkill(skill,receiver,true,false,true))after=before;ledger["progress"][std::to_string(languageID)]=after;}}
  seen.push_back(eid);while(seen.size()>128)seen.erase(seen.begin());ledger["seen"]=seen;ledger["sequence"]=ledger.value("sequence",uint64(0))+1;
  auto p=source->getWorldPosition();auto parent=source->getParent().get();auto root=source->getRootParent();int cell=parent && parent->isCellObject()?static_cast<CellObject*>(parent.get())->getCellNumber():0;
  Json row={{"id",eid},{"actor_id",std::to_string(source->getObjectID())},{"name",std::string(source->getDisplayedName().toCharArray())},{"position",Json::array({p.getX(),p.getZ(),p.getY()})},{"zone",std::string(source->getZone()->getZoneName().toCharArray())},{"building_id",cell && root?std::to_string(root->getObjectID()):"0"},{"cell_index",cell},{"language_id",languageID},{"language_key",lang.value("key",std::string())},{"message",message},{"comprehension_before",before*.01},{"comprehension_after",after*.01},{"emitted_ms",emitted},{"lifetime_ms",6000}};
  Json events=Json::array();for(auto& old:ledger.value("events",Json::array()))if(timestamp>=old.value("emitted_ms",uint64(0)) && timestamp-old.value("emitted_ms",uint64(0))<6000)events.push_back(old);events.push_back(row);while(events.size()>32)events.erase(events.begin());ledger["events"]=events;
  ghost->setScreenPlayData("swgxr_languages","state",String(ledger.dump().c_str()));
 }
 static Json snapshot(CreatureObject* c){
  auto ledger=load(c);uint64 timestamp=now();Json result={{"sequence",ledger.value("sequence",uint64(0))},{"events",Json::array()},{"languages",Json::array()}};
  for(auto row:ledger.value("events",Json::array())){auto time=row.value("emitted_ms",uint64(0));if(timestamp<time || timestamp-time>=6000)continue;row["age_ms"]=timestamp-time;row.erase("emitted_ms");result["events"].push_back(row);}
  auto& data=catalog();if(data.contains("languages"))for(auto& lang:data["languages"]){auto skill=lang.at("speak_skill").get<std::string>();int value=progress(c,ledger,lang);result["languages"].push_back({{"id",lang.at("id")},{"key",lang.value("key",std::string())},{"name",lang.value("name",std::string())},{"comprehend_skill",lang.at("comprehend_skill")},{"speak_skill",skill},{"progress_basis_points",value},{"understood",value==10000},{"can_speak",c->hasSkill(String(skill.c_str()))},{"audible",lang.value("audible",false)}});}
  return result;
 }
};
#endif
