"""Compile the real legacy BH command bodies and prove player bypasses close."""
from pathlib import Path
import subprocess
import tempfile
import unittest
from tests.test_pistoleer_native import method

ROOT = Path(__file__).resolve().parents[1]
COMMANDS = ('FastBlast', 'SprayShot', 'EyeShot', 'TorsoShot', 'BleedingShot',
            'ConfusionShot', 'UnderHandShot', 'KnockdownFire', 'FireLightningSingle1',
            'FireLightningSingle2', 'FireLightningCone1', 'FireLightningCone2')


class BountyRawCommands(unittest.TestCase):
    def test_player_rejection_preserves_npc_paths(self):
        source = '''#include <string>
#include <cassert>
#include <iostream>
using uint64=unsigned long long; using UnicodeString=std::string;
template<class T>using ManagedReference=T;
enum {GENERALERROR=1,INVALIDSTATE=2,INVALIDLOCOMOTION=3,INVALIDWEAPON=4};
struct WeaponObject{bool isLightningRifle(){return true;}};
struct CreatureObject{bool player=true,state=true,locomotion=true;int calls=0,messages=0;
WeaponObject weapon;bool isPlayerCreature(){return player;}void sendSystemMessage(const char*){++messages;}
WeaponObject* getWeapon(){return &weapon;}};
struct Base{bool checkStateMask(CreatureObject* c)const{return c->state;}
bool checkInvalidLocomotions(CreatureObject* c)const{return c->locomotion;}
int doCombatAction(CreatureObject* c,const uint64&,const UnicodeString& = "")const{++c->calls;return 777;}};
'''
        for name in COMMANDS:
            text = (ROOT / 'vendor/Core3/MMOCoreORB/src/server/zone/objects/creature/commands'
                    / (name + 'Command.h')).read_text()
            body = method(text, 'int doQueueCommand(')
            source += 'struct ' + name + ':Base{' + body + '};\n'
        source += 'int main(){int checks=0;uint64 target=7;\n'
        for name in COMMANDS:
            source += ('{'+name+' command;CreatureObject c;'
                       'assert(command.doQueueCommand(&c,target,"")==GENERALERROR && c.calls==0 && c.messages==1);++checks;'
                       'c.player=false;assert(command.doQueueCommand(&c,target,"")==777 && c.calls==1);++checks;'
                       'c.state=false;assert(command.doQueueCommand(&c,target,"")==INVALIDSTATE && c.calls==1);++checks;}\n')
        source += 'std::cout<<checks<<" original BH player retirement/NPC preservation checks passed\\n";}\n'
        with tempfile.TemporaryDirectory(prefix='swgxr-bh-retirement-') as directory:
            path = Path(directory)
            (path/'check.cpp').write_text(source)
            subprocess.run(['c++', '-std=c++17', str(path/'check.cpp'), '-o', str(path/'check')], check=True)
            result = subprocess.run([str(path/'check')], capture_output=True, text=True, check=True)
            print(result.stdout.strip())


if __name__ == '__main__':
    unittest.main()
