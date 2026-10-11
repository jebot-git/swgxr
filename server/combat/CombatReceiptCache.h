#pragma once
#include <map>
#include <string>
#include <stdexcept>
namespace corecu { namespace receipts {
// Per authenticated native session; never shared across player/session identity.
// Replay mutations with a fresh snapshot, without repeating costs or damage.
template<class Value> struct Cache {
 struct Entry {double at;std::string intent;Value result;};
 std::map<std::string,Entry> rows;
 void prune(double now){for(auto i=rows.begin();i!=rows.end();)if(now-i->second.at>30)i=rows.erase(i);else ++i;}
 const Value* find(const std::string& key,const std::string& intent,double now){
  prune(now);auto i=rows.find(key);if(i==rows.end())return nullptr;
  if(i->second.intent!=intent)throw std::runtime_error("combat_receipt_conflict");
  return &i->second.result;
 }
 void put(const std::string& key,const std::string& intent,const Value& result,double now){
  prune(now);if(rows.size()>=512){auto oldest=rows.begin();for(auto i=rows.begin();i!=rows.end();++i)if(i->second.at<oldest->second.at)oldest=i;rows.erase(oldest);}
  rows.emplace(key,Entry{now,intent,result});
 }
};
}}
