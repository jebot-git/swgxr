#ifndef SWGXR_SMUGGLER_WALLET_H
#define SWGXR_SMUGGLER_WALLET_H
#include "server/zone/managers/faction/FactionManager.h"
#include "server/zone/objects/transaction/TransactionLog.h"

// Same authenticated handshake and durable service receipt as cash payments.
// All currencies are validated under both player locks before any balance moves.
class SwgxrSmugglerWallet {
 using Json=JSONSerializationType;
 static int reserve(){return 200;}
 static double ratio(CreatureObject* c){
  auto manager=FactionManager::instance();
  int from=manager->getRankDelegateRatioFrom(c->getFactionRank());
  int to=manager->getRankDelegateRatioTo(c->getFactionRank());
  if(from<=0 || to<=0)throw std::runtime_error("native_delegation_ratio_unavailable");
  return double(from)/to;
 }
 static int cap(CreatureObject* c,const String& faction){
  return c->getFaction()==faction.hashCode()?FactionManager::instance()->getFactionPointsCap(c->getFactionRank()):1000;
 }
 public:
 static void snapshot(CreatureObject* c,Json& wallet){
  if(!c->hasSkill("combat_smuggler_novice"))return;
  auto ghost=c->getPlayerObject();double rate=ratio(c);
  wallet["faction_delegation"]=true;wallet["delegation_ratio"]=rate;
  wallet["delegation_reserve"]=reserve();
  for(auto name:{"imperial","rebel"}){
   int standing=int(ghost->getFactionStanding(String(name)));
   wallet["faction_points"][name]=standing;
   wallet["faction_limits"][name]=int(std::floor(std::max(0,standing-reserve())/rate));
  }
 }
 static Json pay(CreatureObject* c,CreatureObject* target,const Json& request){
  if(target==nullptr || target==c || !target->isPlayerCreature())throw std::runtime_error("payment_target_unavailable");
  Locker guard(target,c);
  auto sender=c->getPlayerObject();auto recipient=target->getPlayerObject();
  if(sender==nullptr || recipient==nullptr || !target->isOnline() || target->getZone()!=c->getZone() || target->getParentID()!=c->getParentID() || !c->isInRange(target,3) || recipient->isIgnoring(c->getFirstName()))throw std::runtime_error("payment_target_unavailable");
  if(!request.at("amount").is_number_integer())throw std::runtime_error("invalid_payment_amount");
  int64 cash=request.at("amount").get<int64>();
  if(cash<0 || cash>2000000000 || cash>c->getCashCredits() || int64(target->getCashCredits())+cash>2147483647)throw std::runtime_error("insufficient_funds_or_balance_limit");
  auto points=request.value("faction_points",Json::object());
  if(!points.is_object())throw std::runtime_error("invalid_faction_amounts");
  for(auto& entry:points.items())if(entry.key()!="imperial" && entry.key()!="rebel")throw std::runtime_error("invalid_faction_currency");
  Json transfers=Json::object();bool any=cash>0;
  for(auto name:{"imperial","rebel"}){
   auto value=points.value(name,Json(0));
   if(!value.is_number_integer())throw std::runtime_error("invalid_faction_amount");
   int64 count=value.get<int64>();
   if(count<0 || count>2000000000)throw std::runtime_error("invalid_faction_amount");
   if(!count)continue;
   if(!c->hasSkill("combat_smuggler_novice"))throw std::runtime_error("novice_smuggler_required");
   String faction(name);double charge=std::ceil(count*ratio(c));
   double before=sender->getFactionStanding(faction),targetBefore=recipient->getFactionStanding(faction);
   if(charge>before-reserve())throw std::runtime_error("insufficient_faction_points_with_reserve");
   if(targetBefore+count>cap(target,faction))throw std::runtime_error("recipient_faction_cap");
   transfers[name]={{"received",count},{"charged",int(charge)},{"sender_before",before},{"recipient_before",targetBefore}};any=true;
  }
  if(!any)throw std::runtime_error("empty_payment");
  if(cash){TransactionLog transaction(c,target,TrxCode::PLAYERTIP,int(cash),true);c->subtractCashCredits(int(cash));target->addCashCredits(int(cash),true);}
  for(auto& entry:transfers.items()){
   String faction(entry.key().c_str());auto& t=entry.value();
   // Delegation is a transfer, not an earned award: no CoA reward bonus.
   sender->setFactionStanding(faction,t["sender_before"].get<double>()-t["charged"].get<int>());
   recipient->setFactionStanding(faction,t["recipient_before"].get<double>()+t["received"].get<int>());
  }
  target->updateToDatabaseAllObjects(false);
  return {{"credits_sent",cash},{"faction_transfers",transfers}};
 }
};
#endif
