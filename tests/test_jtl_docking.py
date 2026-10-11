import subprocess
import tempfile
import unittest
from pathlib import Path
from tests.test_carbineer_native import method
ROOT=Path(__file__).resolve().parents[1]
class DockingTests(unittest.TestCase):
 def test_actual_mission_permission(self):
  source=(ROOT/'server/jtl/SwgxrDocking.h').read_text()
  methods=method(source,' static bool missionPermission(')+method(source,' static bool permission(')
  code=r"""
#include <string>
#include <cassert>
#include <cstdint>
struct String:std::string {
 using std::string::string;
 static String valueOf(uint64_t id){return String(std::to_string(id).c_str());}
 bool beginsWith(const char* p)const{return rfind(p,0)==0;}
 unsigned hashCode()const{return std::hash<std::string>{}(*this);}
};
struct Ghost {
 bool active=true,task=true,complete=false,admin=false;
 int taskNumber=2;String dockingTask="2";
 String quest="spacequest/inspect/corellia_privateer_15";
 String getScreenPlayData(const char* kind,String key){if(key!="42")return String();return std::string(kind)=="swgxr_docking_task"?dockingTask:quest;}
 bool isJournalQuestActive(unsigned crc){return crc==quest.hashCode() && active;}
 bool isJournalQuestTaskActive(unsigned,int n){return n==taskNumber && task;}
 bool isJournalQuestTaskComplete(unsigned,int n){return n==taskNumber && complete;}
 bool hasGodMode(){return admin;}
};
struct Pilot {Ghost ghost;bool player=true;bool isPlayerCreature(){return player;}
 Ghost* getPlayerObject(){return &ghost;}uint64_t getObjectID(){return 7;}};
struct ShipObject {
 bool launched=true,destroyed=false,disabled=false,jump=false,npc=true;int zone=1;
 uint64_t id=42,owner=0;Pilot* pilot=nullptr;
 int getZone(){return zone;}bool isShipLaunched(){return launched;}
 bool isShipDestroyed(){return destroyed;}bool isShipDisabled(){return disabled;}
 bool isHyperspacing(){return jump;}bool isShipAiAgent(){return npc;}
 ShipObject* asShipAiAgent(){return this;}uint64_t getMissionOwnerID(){return owner;}
 uint64_t getObjectID(){return id;}Pilot* getPilot(){return pilot;}
};
class Native {public:
""" + methods + r"""
};
int main(){
 Pilot p;ShipObject own,target;own.id=1;own.pilot=&p;
 assert(Native::missionPermission(&own,&target));
 p.ghost.task=false;assert(!Native::permission(&own,&target));p.ghost.task=true;
 p.ghost.complete=true;assert(!Native::permission(&own,&target));p.ghost.complete=false;
 p.ghost.active=false;assert(!Native::permission(&own,&target));p.ghost.active=true;
 target.id=43;assert(!Native::permission(&own,&target));target.id=42;
 target.owner=8;assert(!Native::permission(&own,&target));target.owner=7;
 target.npc=false;assert(!Native::permission(&own,&target));target.npc=true;
 target.zone=2;assert(!Native::permission(&own,&target));target.zone=1;
 target.jump=true;assert(!Native::permission(&own,&target));target.jump=false;
 own.destroyed=true;assert(!Native::missionPermission(&own,&target));own.destroyed=false;
 p.ghost.quest="spacequest/destroy/arbitrary";assert(!Native::permission(&own,&target));
 p.ghost.quest="spacequest/rescue/example";assert(Native::permission(&own,&target));
 p.ghost.quest="spacequest/rescue_duty/example";assert(Native::permission(&own,&target));
 p.ghost.quest="spacequest/delivery/example";assert(Native::permission(&own,&target));
 p.ghost.dockingTask="4";assert(!Native::permission(&own,&target));
 p.ghost.taskNumber=4;assert(Native::permission(&own,&target));
 p.ghost.dockingTask="3";assert(!Native::permission(&own,&target));
 p.ghost.quest="spacequest/delivery_no_pickup/example";p.ghost.dockingTask="2";p.ghost.taskNumber=2;assert(Native::permission(&own,&target));
 assert(!Native::permission(&own,&own));assert(!Native::permission(nullptr,&target));
 p.ghost.quest="";p.ghost.admin=true;assert(Native::permission(&own,&target));
}
"""
  with tempfile.TemporaryDirectory() as tmp:
   p=Path(tmp);(p/'test.cpp').write_text(code)
   subprocess.run(['c++','-std=c++14',str(p/'test.cpp'),'-o',str(p/'test')],check=True)
   subprocess.run([str(p/'test')],check=True)
