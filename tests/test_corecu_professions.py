import json
import unittest
from pathlib import Path
from server.corecu_professions import contribution, policy, trap_bonus_contribution

ROOT=Path(__file__).resolve().parents[1]

class CoreCuProgressionTests(unittest.TestCase):
    def test_each_role_has_valid_progression_and_no_new_abilities(self):
        data=policy()
        self.assertEqual(len(data['statuses']),10)
        for profession, values in data['professions'].items():
            self.assertEqual(len(values),10)
            self.assertTrue(all(0<=v<=100 for v in values))
            for node, weight in [('novice',.1),('support_01',.05),('master',.1)]:
                actual=contribution(profession,profession+'_'+node)
                for status,v in zip(data['statuses'],values):
                    self.assertAlmostEqual(actual.get(status,0),v*weight)
            self.assertEqual(contribution(profession,profession+'_support_05'),{})
            self.assertEqual(contribution(profession,'combat_fake_master'),{})

    def test_original_tree_boxes_reach_master_budget(self):
        path=ROOT/'runtime/assets/professions/catalog.json'
        if not path.exists(): self.skipTest('supplied-media catalogue unavailable')
        catalog=json.loads(path.read_text())
        trees={p['id']:p for p in catalog['professions']}
        for profession, expected in policy()['professions'].items():
            self.assertIn(profession,trees)
            totals={s:0 for s in policy()['statuses']}
            for node in trees[profession]['nodes']:
                for key,value in contribution(profession,node['id']).items():totals[key]+=value
            for key,value in zip(policy()['statuses'],expected):self.assertAlmostEqual(totals[key],value, msg=profession+'/'+key)

    def test_trap_bonus_preserves_tree_progression(self):
        scout=['outdoors_scout_novice']+[f'outdoors_scout_tools_0{i}' for i in range(1,5)]
        ranger=[f'outdoors_ranger_support_0{i}' for i in range(1,5)]+['outdoors_ranger_master']
        self.assertEqual(sum(map(trap_bonus_contribution,scout)),5)
        self.assertEqual(sum(map(trap_bonus_contribution,scout+ranger)),10)
        for skill in ('outdoors_scout_master','outdoors_ranger_novice','outdoors_ranger_support_05','outdoors_scout_movement_01'):
            self.assertEqual(trap_bonus_contribution(skill),0)

    def test_respec_presentation_is_stateless(self):
        p='combat_polearm'
        novice=contribution(p,p+'_novice')
        self.assertEqual(novice,contribution(p,p+'_novice'))
        self.assertEqual(contribution(p,'combat_rifleman_master'),{})

if __name__=='__main__':unittest.main()
