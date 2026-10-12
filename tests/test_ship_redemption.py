"""Exercise the original deed's capacity decisions, including mixed Yacht/POB ownership."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ShipRedemption(unittest.TestCase):
    def test_native_capacity_decisions(self):
        source = (ROOT / 'vendor/Core3/MMOCoreORB/src/server/zone/objects/tangible/deed/ship/ShipDeedImplementation.cpp').read_text()
        start = source.index('\t\tint totalShips = 0;')
        end = source.index('\t\t// Sorosuub Luxury Yacht veteran reward should come with components', start)
        # Run the real capacity block with small stand-ins for inventory objects.
        program = r'''
#include <vector>
#include <string>
#include <cassert>
#include <iostream>
template<class T> struct Reference {
 T p; Reference(T v=nullptr):p(v){} T operator->()const{return p;}
 bool operator==(decltype(nullptr))const{return p==nullptr;}
 template<class U> Reference<U> castTo()const{return Reference<U>(static_cast<U>(p));}
 operator T()const{return p;}
};
struct SceneObject {
 bool device=false; unsigned crc=0;
 bool isShipControlDevice(){return device;}
 unsigned getServerObjectCRC(){return crc;}
};
struct ShipManager {enum {POBSHIP=1};};
struct ShipControlDevice:SceneObject {
 SceneObject hull; int type;
 ShipControlDevice(int t,unsigned c):type(t){device=true;hull.crc=c;}
 SceneObject* getControlledObject(){return &hull;}
 int getShipType(){return type;}
};
struct Datapad {
 std::vector<SceneObject*> ships;
 int getContainerObjectsSize(){return ships.size();}
 Reference<SceneObject*> getContainerObject(int i){return ships[i];}
};
struct PlayerManager {int getBaseStoredShips(){return 5;}};
struct Player {std::string message;void sendSystemMessage(const char*s){message=s;}};
struct Deed {
 int type;int getShipType(){return type;}
 int redeem(Datapad*datapad,PlayerManager*playerManager,Player*player,bool isYachtDeed){
''' + source[start:end] + r'''
 return 0;
 }
};
int main(){
 ShipControlDevice yacht(1,388127163),pob(1,42),fighter(0,99);
 SceneObject unrelated;
 PlayerManager manager;Player player;Datapad pad;Deed regular{1},small{0};
 pad.ships={&yacht,&fighter,&unrelated};
 assert(regular.redeem(&pad,&manager,&player,false)==0);
 pad.ships={&pob};
 assert(regular.redeem(&pad,&manager,&player,true)==0);
 assert(regular.redeem(&pad,&manager,&player,false)==1);
 assert(player.message=="@space/space_interaction:too_many_pobs");
 pad.ships={&yacht,&pob};
 assert(regular.redeem(&pad,&manager,&player,false)==1);
 assert(small.redeem(&pad,&manager,&player,false)==0);
 pad.ships={&yacht,&pob,&fighter,&fighter,&fighter};
 assert(regular.redeem(&pad,&manager,&player,true)==1);
 assert(player.message=="@space/space_interaction:toomanyships");
 assert(small.redeem(&pad,&manager,&player,false)==1);
 std::cout<<"9 original deed capacity checks passed\n";
}
'''
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            (path / 'test.cpp').write_text(program)
            result = subprocess.run(['c++', '-std=c++14', str(path / 'test.cpp'), '-o', str(path / 'test')], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            result = subprocess.run([str(path / 'test')], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            print(result.stdout.strip())


if __name__ == '__main__':
    unittest.main()
