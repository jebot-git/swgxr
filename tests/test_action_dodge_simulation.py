import math
from pathlib import Path
import random
import subprocess
import tempfile
import unittest
from tools.server.simulate_action_dodging import hit, trial

ROOT = Path(__file__).resolve().parents[1]


class DodgeSimulationTests(unittest.TestCase):
    def test_assessment_geometry_matches_native_policy(self):
        source = '''#include "server/combat/ActionCombatPolicy.h"
#include <iostream>
using namespace corecu::action;
int main(){int r;double x,z,a;while(std::cin>>r>>x>>z>>a)
std::cout<<contact(r?Role::Ranged:Role::Melee,{{0,0,0}},{{std::sin(a),0,std::cos(a)}},{{x,0,z}})<<"\\n";}
'''
        rng = random.Random(43)
        rows = [(rng.randrange(2), rng.uniform(-5,5), rng.uniform(-4,25), rng.uniform(-math.pi,math.pi)) for _ in range(1500)]
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'geometry.cpp'; path.write_text(source)
            binary = Path(directory)/'geometry'
            subprocess.run(['c++','-std=c++17','-I',str(ROOT),str(path),'-o',str(binary)],check=True,capture_output=True)
            output = subprocess.check_output([str(binary)],input=''.join(f'{r} {x:.17g} {z:.17g} {a:.17g}\n' for r,x,z,a in rows),text=True)
        self.assertEqual([bool(int(v)) for v in output.split()], [hit('ranged' if r else 'melee',x,z,a) for r,x,z,a in rows])

    def test_stationary_is_exposed_and_dodging_preserves_shot_opportunity(self):
        for seed in range(20):
            self.assertTrue(trial('ranged',12,.3,'stationary',.1,seed)['hit'])
            result = trial('ranged',12,.3,'dodge_then_shoot',.1,seed)
            self.assertFalse(result['hit'])
            self.assertTrue(result['shot_before_recovery'])
