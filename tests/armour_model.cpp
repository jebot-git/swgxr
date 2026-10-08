#include "../server/combat/ArmourModel.h"
#include <cassert>
#include <iostream>
#include <iomanip>
using namespace swgxr::armour;
bool close(double a,double b){return std::abs(a-b)<1e-8;}
int main(){
    assert(close(reduction(2000),.2));
    assert(close(reduction(4000),1.0/3));
    assert(close(reduction(6000),3.0/7));
    assert(close(reduction(8000),.5));
    assert(close(reduction(90000),.5));
    ArmourReference bone{"bone",0,6,25,6,40,20,80};
    ArmourReference composite{"composite",2,2,50,2,50,100,350};
    assert(close(baseScore(bone,15.5,0),baseScore(composite,26,0)));
    assert(close(baseScore(bone,25,0),6000));
    assert(baseScore(bone,30,0)>6000); // exceptional-component value retained
    assert(close(score(composite,Kinetic,6000,0,0,1),7000));
    assert(close(score(composite,Energy,6000,0,0,1),5000));
    assert(score(composite,Kinetic,7000,1000,80,1.35)<=8000);
    auto untrained=penalties(2,6000,0,0),trained=penalties(2,6000,1,1);
    assert(trained.movement>untrained.movement && trained.movement<1);
    auto split=weapon(Energy,3);
    assert(split.fraction>0 && split.bypass>0);
    Damage zero(1000,split);zero.mitigate(0,0);
    assert(close(zero.total(),1000)); // AP cannot increase naked-target damage
    // Native/client differential fixture, including every legacy channel/grade.
    const int types[]={Kinetic,Energy,Blast,Stun,Saber,Heat,Cold,Acid,Electricity};
    std::cout<<std::setprecision(15)<<"[";bool first=true;
    for(int type:types)for(int ap=0;ap<4;++ap)for(int rb=0;rb<=50;rb+=10)for(int re=0;re<=50;re+=10){
        auto p=weapon(type,ap);Damage d(1000,p);d.mitigate(rb/100.,re/100.);
        assert(d.total()>=500*p.damageScale-1e-8 && d.total()<=1000*p.damageScale+1e-8);
        const double budgets[]={0,.05,.1,.2};
        assert(d.total()/(1000*(1-rb/100.))<=1+budgets[ap]+1e-8);
        if(!first)std::cout<<",";first=false;
        std::cout<<"["<<type<<","<<ap<<","<<rb<<","<<re<<","<<d.total()<<"]";
    }
    std::cout<<"]\n";
}
