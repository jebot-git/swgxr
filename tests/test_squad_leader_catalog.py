"""CU Squad Leader presentation retains original progression provenance."""
import unittest
from server.profession_catalog import catalog
from server.character_protocol import assets
from character_formats import datatable


class SquadLeaderCatalogTests(unittest.TestCase):
    def test_original_graph_and_modifiers_are_preserved_as_source(self):
        tree = next(p for p in catalog()['professions'] if p['id']=='outdoors_squadleader')
        originals = {r['NAME']:r for r in datatable(assets().read('datatables/skill/skills.iff'))}
        self.assertEqual(len(tree['nodes']),18)
        for node in tree['nodes']:
            source = originals[node['id']]
            mods = {k:int(v) for k,v in (entry.split('=') for entry in source['SKILL_MODS'].split(',') if entry)}
            self.assertEqual(node['source_modifiers'],mods)
            self.assertEqual(node['points'],source['POINTS_REQUIRED'])
            self.assertEqual(node['xp_cost'],source['XP_COST'])
            self.assertEqual(node['credits'],source['MONEY_REQUIRED'])
            self.assertEqual(node['requires'],list(filter(None,source['SKILLS_REQUIRED'].split(','))))
            self.assertTrue(set(node['modifiers']).isdisjoint(('group_slope_move','group_burst_run','steadyaim','volley')))

    def test_displayed_passives_reach_native_master_caps(self):
        tree = next(p for p in catalog()['professions'] if p['id']=='outdoors_squadleader')
        for key,expected in [('group_damage_percent',10),('group_action_mind_regen_percent',10),
                             ('group_melee_defense',15),('group_ranged_defense',15)]:
            self.assertEqual(sum(n['modifiers'].get(key,0) for n in tree['nodes']),expected)
        master = next(n for n in tree['nodes'] if n['id']=='outdoors_squadleader_master')
        self.assertIn('Each member gets one guaranteed',master['description'])
        self.assertIn('120-second',master['description'])
        for node in tree['nodes']:
            self.assertIn('same planet',node['description'])
            self.assertIn('no new standalone attack',node['description'])


if __name__ == '__main__':
    unittest.main()
