#pragma once
#include <algorithm>
#include <cmath>
#include <string>

// CoreCU v1 tuning, not a claim of recovered SOE server formulas.
namespace corecu {
constexpr int VERSION=1;
enum Status { Stun, Blind, Dizzy, Intimidate, Knockdown, Snare, Bleed, Poison, Disease, Fire, StatusCount };
inline double clamp(double x,double a,double b){return std::isfinite(x)?std::max(a,std::min(b,x)):a;}
inline bool elemental(int type){return type==32 || type==64 || type==128 || type==256;}
inline double resistance(int level,int armor,double legacy){
    // Level supplies the common curve; species retain bounded weaknesses.
    const double bias=legacy<0?-1000:clamp((legacy-30)*20,-1000,1000);
    const double score=clamp(75*clamp(level,1,80)+400*clamp(armor,0,3)+bias,0,8000);
    return score/(8000+score);
}
inline double npcDamageScale(int level){return level<=30?.45:level<=80?.55:level<=150?.70:.85;}
inline double npcHamScale(int level){return level<=30?.65:level<=80?.80:1.;}
inline double npcMean(double low,double high,int level){return std::max(1.,(low+high)*.5*npcDamageScale(level));}
inline int specialCooldown(int level){return level>150?6000:level>80?8000:10000;}
inline double specialMultiplier(double value,int level){return clamp(value,0,level>150?2.5:level>80?2.:1.5);}
inline double statusReduction(double rating){return clamp(rating/(100+std::max(0.,rating)),0,.60);}
inline double statusChance(double chance,double rating){return clamp(chance,5,95)*(1-statusReduction(rating));}
inline int statusDuration(int seconds,double rating){return seconds<=0?0:std::max(1,int(std::ceil(seconds*(1-statusReduction(rating)))));}
inline double trapSuccessBonus(bool scoutNovice,int scoutBoxes,int rangerBoxes,bool rangerMaster){return (scoutNovice?1.:0.)+clamp(scoutBoxes,0,4)+clamp(rangerBoxes,0,4)+(rangerMaster?1.:0.);}
inline double trapStatusChance(double rating,double bonus){return clamp(statusChance(95,rating)+clamp(bonus,0,10),0,95);}
inline double weakenedRating(double existing,double derived,double debuff){return std::max(existing,std::max(0.,derived+std::min(0.,debuff)));}
inline double combinedRating(double strongest,double others){return clamp(strongest+.25*others,0,100);}
inline double progressWeight(const std::string& profession,const std::string& skill){
    const auto prefix=profession+"_";
    if(skill.compare(0,prefix.size(),prefix)!=0)return 0;
    const auto suffix=skill.substr(prefix.size());
    if(suffix=="novice" || suffix=="master")return .1;
    return suffix.size()>3 && suffix[suffix.size()-3]=='_' && suffix[suffix.size()-2]=='0' && suffix.back()>='1' && suffix.back()<='4'?.05:0.;
}
// One elemental budget: shields replace weaker body protection, never multiply it.
inline double equipmentResistance(int channel,double body,double shield){return clamp(elemental(channel)?std::max(body,shield):body,0,.5);}
inline double shieldResistance(int channel,double quality){return elemental(channel)?clamp(quality,0,80)/160.:0.;}
// Shortened effects still get a first tick before expiry.
inline int firstTickMillis(int duration,int interval){return int(std::max(1.,std::min(interval*1000.,duration*500.)));}
// Hit-derived DoTs have a bounded total budget, shared across each effect group.
inline double dotTickBudget(double mitigated,int effects,int duration,int interval,double requested){
    const int ticks=std::max(1,int(std::ceil(double(duration)/interval)));
    return std::max(0.,std::min(requested,mitigated*.5/std::max(1,effects)/ticks));
}
}
