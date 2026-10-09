#include "server/combat/DoctorPolicy.h"
#include "server/combat/CoreCuMedicalPolicy.h"
#include <cassert>
#include <iostream>
#include <map>
#include <string>
#include <memory>
using String=std::string;
struct CreatureObject;
template<class T>using Reference=T;
struct BuffType {enum {MEDICAL};};
struct BuffCRC {static unsigned getMedicalBuff(int a){return 100+a;}};
struct BuffAttribute {static std::string getProtectionString(int a){return a==9?"resistance_poison":"resistance_disease";}static std::string getAbsorptionString(int a){return a==9?"absorption_poison":"absorption_disease";}};
struct Buff {CreatureObject* owner;unsigned id;float seconds;std::map<int,int> attrs;std::map<std::string,int> mods;bool fill=true;Buff(CreatureObject* c,unsigned i,float s,int):owner(c),id(i),seconds(s){}void setFillAttributesOnBuff(bool value){fill=value;}void setAttributeModifier(int a,int v){attrs[a]=v;}void setSkillModifier(const std::string& s,int v){mods[s]=v;}int getAttributeModifierValue(int a){return attrs[a];}int getSkillModifierValue(const std::string& s){return mods[s];}float getTimeLeft(){return seconds;}};
struct CreatureObject {int base[9]={3000,300,300,1000,300,300,1000,300,300},maximum[9]={3000,300,300,1000,300,300,1000,300,300},ham[9]={2450,300,300,600,300,300,750,300,300};std::map<unsigned,Buff*> buffs;bool player=true,pet=false;bool isPlayerCreature(){return player;}bool isPet(){return pet;}int getBaseHAM(int a){return base[a];}int getHAM(int a){return ham[a];}int getMaxHAM(int a){return maximum[a];}int getWounds(int){return 0;}void setHAM(int a,int v){ham[a]=v;}Buff* getBuff(unsigned crc){return buffs.count(crc)?buffs[crc]:nullptr;}void addBuff(Buff* b){buffs[b->id]=b;for(auto [a,v]:b->attrs){maximum[a]+=v;if(b->fill)ham[a]=maximum[a];}}void removeBuff(unsigned crc){auto b=getBuff(crc);if(!b)return;for(auto [a,v]:b->attrs){maximum[a]-=v;ham[a]=std::min(ham[a],maximum[a]);}buffs.erase(crc);}};
#include "doctor_preparation_native.inc"
int main(){using namespace corecu::doctor;int checks=0;auto check=[&](bool condition){assert(condition);++checks;};
 for(int a:{0,1,2,3,4,5,9,10})for(int t=0;t<(protection(a)?3:4);++t){
  double lo=protection(a)?(t?17:12):10.*(t+1),hi=protection(a)?(t?160:60):(t==0?100:t==1?200:t==2?400:800);
  check(quality(a,t,lo)==0 && quality(a,t,hi)==1 && quality(a,t,-100)==0 && quality(a,t,1e9)==1);
  check(percent(a,t,0)<percent(a,t,.5) && percent(a,t,.5)<percent(a,t,1));
  check(percent(a,t,1,1e9,1e9)<= (protection(a)?25:15));
  check(percent(a,t,1,100,100,.5)==percent(a,t,1,100,100)*.5);
  check(tier(std::string("medpack_enhance_health_")+char('a'+t)+".iff")==t);
 }
 check(percent(0,0,1)==8 && percent(0,1,1)==10 && percent(0,2,1)==12 && percent(0,3,1)==15);
 check(amount(0,3000,15)==450 && amount(3,1000,15)==150 && amount(2,300,15)==1500);
 check(regen(1500)==1.15 && regen(-50)==1 && regen(5000)==1.15);
 check(absorption(9,2,25)==10 && absorption(9,1,25)==0 && absorption(9,2,1e9)==10);
 for(auto name:{"strength","quickness","stamina"})for(char t='a';t<='d';++t){auto suffix=std::string("medpack_enhance_")+name+"_"+t+".iff";check(corecu::medicine::retiredMedicalTemplate("object/draft_schematic/chemistry/"+suffix));check(!corecu::medicine::retiredMedicalTemplate("object/tangible/medicine/crafted/"+suffix));}
 for(auto a:{0,3,2,9,10}){CreatureObject c;int before[9];for(int i=0;i<9;++i)before[i]=c.ham[i];SwgxrDoctorPreparation::apply(&c,a,amount(a,c.base[a<9?a:0],15),120,20);check(c.buffs.size()==1);for(int i=0;i<9;++i)check(c.ham[i]==before[i]);check(c.getBuff(BuffCRC::getMedicalBuff(a))->seconds==120);}
 CreatureObject c;SwgxrDoctorPreparation::apply(&c,0,450,500);c.ham[0]=3200;SwgxrDoctorPreparation::apply(&c,0,450,600);check(c.ham[0]==3200 && c.maximum[0]==3450);SwgxrDoctorPreparation::apply(&c,3,150,200);check(c.buffs.size()==1 && c.maximum[0]==3000 && c.ham[0]==3000 && c.ham[3]==600);SwgxrDoctorPreparation::apply(&c,9,500,100,50);check(c.buffs.size()==2 && SwgxrDoctorPreparation::strength(c.getBuff(109),9)==25 && c.getBuff(109)->mods["absorption_poison"]==10);SwgxrDoctorPreparation::apply(&c,10,10,75);check(c.buffs.size()==2 && !c.getBuff(109) && c.getBuff(110));SwgxrDoctorPreparation::apply(&c,1,1000,80);check(c.buffs.size()==2 && c.getBuff(102) && c.maximum[3]==1000 && c.ham[3]==600);SwgxrDoctorPreparation::normalize(&c);check(c.getBuff(102)->seconds==80 && c.getBuff(110)->seconds==75);
 CreatureObject old;auto health=new Buff(&old,100,90,0);health->setAttributeModifier(0,2000);health->fill=false;old.addBuff(health);auto action=new Buff(&old,103,120,0);action->setAttributeModifier(3,150);action->fill=false;old.addBuff(action);auto poison=new Buff(&old,109,55,0);poison->setSkillModifier("resistance_poison",500);old.addBuff(poison);auto disease=new Buff(&old,110,40,0);disease->setSkillModifier("resistance_disease",300);old.addBuff(disease);SwgxrDoctorPreparation::normalize(&old);check(old.buffs.size()==2 && old.getBuff(103) && old.getBuff(109));check(old.getBuff(103)->seconds==120 && old.getBuff(109)->seconds==55);check(old.ham[0]==2450 && old.ham[3]==600 && old.getBuff(109)->mods["resistance_poison"]==25);
 CreatureObject secondary;auto stamina=new Buff(&secondary,105,80,0);stamina->fill=false;stamina->setAttributeModifier(5,300);secondary.addBuff(stamina);SwgxrDoctorPreparation::normalize(&secondary);check(secondary.getBuff(102) && !secondary.getBuff(105));check(secondary.getBuff(102)->mods["private_swgxr_metabolic_regen"]==1500 && secondary.ham[5]==300);
 std::cout<<"Doctor preparation policy/native replacement: "<<checks<<" checks passed\n";
}
