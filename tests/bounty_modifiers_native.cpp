#include "server/combat/BountyHunterPolicy.h"
#include <cassert>
#include <map>
#include <set>
#include <string>
#include <vector>
#include <iostream>
using uint64=unsigned long long;
struct String:std::string {using std::string::string;String()=default;String(const std::string& s):std::string(s){}const char* toCharArray()const{return c_str();}static String valueOf(uint64 value){return std::to_string(value);}};
constexpr unsigned hash(const char* p,unsigned h=0){return *p?hash(p+1,h*31+*p):h;}
#define STRING_HASHCODE(s) hash(s)
struct Mods:std::map<String,int>{using std::map<String,int>::map;bool contains(const String& key)const{return count(key);}int get(const String& key)const{return at(key);}};
struct Abilities:std::set<String>{using std::set<String>::set;bool contains(const String& key)const{return count(key);}};
struct Skill {String name;Mods mods;Abilities abilities;const String& getSkillName(){return name;}const Mods* getSkillModifiers(){return &mods;}const Abilities* getAbilities(){return &abilities;}};
struct SkillList:std::vector<Skill*>{using std::vector<Skill*>::operator=;Skill* get(int i)const{return at(i);}};
struct SkillModManager {enum{SKILLBOX};static SkillModManager* instance(){static SkillModManager m;return &m;}int getMinSkill(int){return -125;}int getMaxSkill(int){return 125;}};
struct TangibleObject {uint64 id=7;uint64 getObjectID(){return id;}};
struct CreatureObject:TangibleObject {
 SkillList list;int gear=0;bool duelist=false;String bound="7";SkillList* getSkillList(){return &list;}
 int getSkillModOfType(const String& key,int){int sum=0;for(auto skill:list)if(skill->mods.count(key))sum+=skill->mods.at(key);return sum;}
 int getSkillMod(const String& key){return std::max(-125,std::min(125,getSkillModOfType(key,0)))+gear;}
 bool hasSkill(const char* name){for(auto skill:list)if(skill->name==name)return true;return false;}
 CreatureObject* getPlayerObject(){return this;}bool hasAbility(const String& ability){for(auto skill:list)if(skill->abilities.count(ability))return true;return false;}
 bool hasBuff(unsigned){return duelist;}String getScreenPlayData(const char*,const char*){return bound;}
};
#include "bounty_modifiers.inc"
int main(){int checks=0;auto check=[&](bool ok){++checks;assert(ok);};CreatureObject c;
 Skill novice{"combat_bountyhunter_novice",{{"heavy_rifle_lightning_speed",10},{"heavy_rifle_lightning_accuracy",10}},{}};
 Skill marksman{"combat_marksman_master",{{"pistol_speed",30},{"pistol_accuracy",60},{"carbine_speed",30}},{}};
 Skill pistolBH{"combat_bountyhunter_droidresponse_04",{{"pistol_speed",50},{"pistol_accuracy",60}},{}};
 Skill carbineBH{"combat_bountyhunter_droidcontrol_04",{{"carbine_speed",50}},{}};
 Skill lightBH{"combat_bountyhunter_support_04",{{"heavy_rifle_lightning_speed",50},{"heavy_rifle_lightning_accuracy",60}},{}};
 Skill pistol{"combat_pistol_master",{{"pistol_speed",49},{"pistol_accuracy",45}},{}};
 Skill carbine{"combat_carbine_master",{{"carbine_speed",35}},{}};
 c.list={&marksman,&pistol};check(SwgxrBountyHunterModifiers::modifier(&c,"pistol_speed",true)==79);
 c.list={&novice,&marksman,&pistolBH};check(SwgxrBountyHunterModifiers::modifier(&c,"pistol_speed",true)==55);check(SwgxrBountyHunterModifiers::modifier(&c,"pistol_accuracy",false)==60);
 c.list.push_back(&pistol);check(c.getSkillMod("pistol_speed")==125);check(SwgxrBountyHunterModifiers::modifier(&c,"pistol_speed",true)==79);check(SwgxrBountyHunterModifiers::modifier(&c,"pistol_accuracy",false)==105);
 c.gear=15;check(SwgxrBountyHunterModifiers::modifier(&c,"pistol_speed",true)==94);check(SwgxrBountyHunterModifiers::modifier(&c,"pistol_accuracy",false)==120);c.gear=0;
 c.list={&novice,&marksman,&carbineBH,&carbine};check(SwgxrBountyHunterModifiers::modifier(&c,"carbine_speed",true)==65);
 c.list={&novice,&lightBH};check(SwgxrBountyHunterModifiers::modifier(&c,"heavy_rifle_lightning_speed",true)==25);check(SwgxrBountyHunterModifiers::modifier(&c,"heavy_rifle_lightning_accuracy",false)==0);check(SwgxrBountyHunterModifiers::branch(&c,"heavy_rifle_lightning_speed")==50);
 c.list={&novice};check(SwgxrBountyHunterModifiers::modifier(&c,"heavy_rifle_lightning_speed",true)==0);check(SwgxrBountyHunterModifiers::modifier(&c,"heavy_rifle_lightning_accuracy",false)==0);
 for(int raw:{10,20,40,50,100}){pistolBH.mods["pistol_speed"]=raw;c.list={&novice,&marksman,&pistolBH};check(SwgxrBountyHunterModifiers::modifier(&c,"pistol_speed",true)==30+std::min(25,raw/2));}pistolBH.mods["pistol_speed"]=50;
 pistolBH.abilities.insert("ranged_damage_mitigation_3");c.list={&novice,&pistolBH};check(!SwgxrBountyHunterModifiers::nonBountyAbility(&c,"ranged_damage_mitigation_3"));pistol.abilities.insert("ranged_damage_mitigation_3");c.list.push_back(&pistol);check(SwgxrBountyHunterModifiers::nonBountyAbility(&c,"ranged_damage_mitigation_3"));c.list={&pistol};check(SwgxrBountyHunterModifiers::nonBountyAbility(&c,"ranged_damage_mitigation_3"));
 TangibleObject a,b;b.id=8;check(SwgxrBountyHunterModifiers::incoming(&c,&a)==1);c.duelist=true;check(SwgxrBountyHunterModifiers::incoming(&c,&a)==.85);check(SwgxrBountyHunterModifiers::incoming(&c,&b)==1);check(std::min(.8,SwgxrBountyHunterModifiers::incoming(&c,&a))==.8);
 std::cout<<checks<<" production BH strongest-speed, source accuracy/mitigation retirement and bound Duelist checks passed\n";
}
