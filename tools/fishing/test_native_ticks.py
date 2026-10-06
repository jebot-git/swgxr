#!/usr/bin/env python3
"""Compile the actual native fishing tick bodies against deterministic test doubles.
This verifies control flow and native freshness thresholds, not the Core3 build/ABI.
"""
from pathlib import Path
import re,subprocess,tempfile,json
ROOT=Path(__file__).resolve().parents[2]
source=ROOT/'vendor/Core3/MMOCoreORB/src/server/zone/managers/minigames/FishingManagerImplementation.cpp'
s=source.read_text()
def body(name):
 start=s.index('void FishingManagerImplementation::'+name+'(')
 end=s.index('\n}\n',start)+3
 return s[start:end]
# Keep the stock 7-second scheduled clock and deterioration rules byte-for-byte.
original=subprocess.check_output(['git','-C',str(ROOT/'vendor/Core3'),'show','HEAD:MMOCoreORB/src/server/zone/managers/minigames/FishingManagerImplementation.cpp'],text=True)
for expression in [r'if \(state < CATCH && baitState > SOGGY.*?return; // NO BAIT\n\s*}',r'if \(bait != nullptr && System::random\(100\) < 5\).*?\n\s*}',r'player->addPendingTask\("fishing", fishingEvent, 7000\);']:
 assert re.search(expression,s,re.S).group()==re.search(expression,original,re.S).group(),expression
stub=r'''
#include <cassert>
#include <string>
#include <cmath>
using String=std::string;using uint32=unsigned;
template<class P> struct Ref {P p=nullptr;Ref(){}Ref(P v):p(v){}P operator->()const{return p;}operator P()const{return p;}};
template<class P>using ManagedReference=Ref<P>;
struct FishingEvent{};
struct SceneObject{void showFlyText(const char*,const char*,int,int,int){}float getPositionX(){return 0;}float getPositionY(){return 0;}float getPositionZ(){return 0;}};
struct FishingPoleObject{int getQuality(){return 0;}};
struct FishingBaitObject{int freshness=0;int getFreshness(){return freshness;}void lessFresh(){freshness++;}};
struct FishingSession{SceneObject marker;int action=0,fish=0,state=1;unsigned box=0;unsigned getFishBoxID(){return box;}SceneObject* getMarker(){return &marker;}int getNextAction(){return action;}int getFish(){return fish;}int getFishingState(){return state;}String getMoodString(){return "none";}void setNextAction(int n){action=n;}void setEvent(FishingEvent*){}void setFishBoxID(unsigned n){box=n;}void update(int a,SceneObject*,int f,unsigned b,int st){action=a;fish=f;box=b;state=st;}};
struct SessionHandle{FishingSession* s;template<class P> Ref<P> castTo(){return Ref<P>(static_cast<P>(s));}};
struct PlayerObject{bool vr=true;String getScreenPlayData(const char*,const char*){return vr?"1":"";}};
struct CreatureObject{FishingSession session;PlayerObject ghost;bool active=true,near=false;SessionHandle getActiveSession(int){return {active?&session:nullptr};}bool isInCombat(){return false;}bool isDead(){return false;}bool isIncapacitated(){return false;}bool isInRange(SceneObject*,float){return near;}PlayerObject* getPlayerObject(){return &ghost;}void sendSystemMessage(const char*){}void* getZone(){return nullptr;}};
struct SessionFacadeType{static constexpr int FISHING=1;};
struct System{static inline bool age=true;static int random(int n){return n==30?30:n==100?(age?0:100):0;}};
class FishingManagerImplementation {public:
 static constexpr int NOTFISHING=0,WAITING=1,SNAGGED=2,NIBBLE=3,BITE=4,CATCH=5,REELING=6,REELGAME=7;
 static constexpr int DONOTHING=0,TUGUP=1,TUGRIGHT=2,TUGLEFT=3,REEL=4,STOPFISHING=5,SOGGY=6,MISHAP=10,PROCEED=20;
 FishingPoleObject pole;FishingBaitObject bait;FishingEvent event;int scheduled=0,moves=0,catches=0,losses=0;String reason;
 FishingPoleObject* getPole(CreatureObject*){return &pole;}FishingBaitObject* getBait(CreatureObject*){return &bait;}
 int vegetation(SceneObject*){return 0;}int density(SceneObject*){return 0;}int getFish(CreatureObject*,SceneObject*){return 0;}void closeMenu(CreatureObject*,uint32){}void animate(CreatureObject*,int){}unsigned createWindow(CreatureObject*,unsigned){return 0;}
 int getFishingState(CreatureObject* c){return c->session.state;}void stopFishing(CreatureObject* c,uint32,bool){c->active=false;}
 FishingEvent* createFishingEvent(CreatureObject*,int){scheduled++;return &event;}
 SceneObject* updateMarker(CreatureObject*,SceneObject* m,uint32,bool){moves++;return m;}
 void createSplash(float,float,float,void*,CreatureObject*){}
 void success(CreatureObject* c,int,SceneObject*,uint32){catches++;c->active=false;}
 void mishapEvent(const String& text,CreatureObject* c,SceneObject*,uint32,bool lose,String&){reason=text;if(lose){losses++;c->active=false;}}
 void continueFishing(CreatureObject* player);
 void fishingProceed(CreatureObject* player,int nextAction,SceneObject* marker,int fish,uint32 boxID,int newstate,bool sendPlayerMessage,String& moodString);
};
'''
tests=r'''
int main(){
 {CreatureObject p;FishingManagerImplementation m;for(int tick=0;tick<7;tick++){m.continueFishing(&p);assert(p.active);}assert(m.bait.freshness==7);assert(m.scheduled==7);m.continueFishing(&p);assert(!p.active && m.losses==1 && m.reason=="@fishing:toss_bait");}
 {CreatureObject p;FishingManagerImplementation m;System::age=false;for(int i=0;i<100;i++)m.continueFishing(&p);assert(p.active && m.losses==0 && m.bait.freshness==0);System::age=true;}
 {CreatureObject p;FishingManagerImplementation m;p.session.state=7;for(int i=0;i<3;i++)m.continueFishing(&p);assert(m.moves==0 && m.scheduled==3);p.session.action=4;m.continueFishing(&p);assert(m.moves==1 && p.session.action==0);}
 {CreatureObject p;FishingManagerImplementation m;p.ghost.vr=false;p.session.state=7;m.continueFishing(&p);assert(m.moves==1 && p.session.action==4);}
 {CreatureObject p;FishingManagerImplementation m;p.session.state=7;p.session.action=4;p.near=true;m.continueFishing(&p);assert(m.catches==1);}
 {CreatureObject p;FishingManagerImplementation m;p.session.state=7;p.near=true;String mood="none";m.fishingProceed(&p,4,&p.session.marker,0,0,7,true,mood);assert(p.active && m.scheduled==1);}
}
'''
with tempfile.TemporaryDirectory(prefix='swgxr-fishing-ticks-') as directory:
 p=Path(directory);(p/'ticks.cpp').write_text(stub+body('continueFishing')+body('fishingProceed')+tests)
 subprocess.run(['g++','-std=c++17','-O0',str(p/'ticks.cpp'),'-o',str(p/'ticks')],check=True)
 subprocess.run([str(p/'ticks')],check=True)
result={'passed':True,'cases':6,'native_source_clock_and_freshness_unchanged':True,'compiled':'actual continueFishing/fishingProceed bodies with deterministic test doubles','full_core3_build':False,'running_server':False}
(ROOT/'runtime/evidence/fishing-native-ticks.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result))
