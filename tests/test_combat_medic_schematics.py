"""Original CM grants and native retirement policy retain meaningful recipe families."""
from pathlib import Path
import unittest
from tools.server.audit_combat_medic import audit, DRAFT


class CombatMedicSchematics(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.report = audit()
        cls.recipes = {row['recipe']: row for row in cls.report['recipes']}

    def test_original_counts_and_real_native_outputs(self):
        self.assertEqual((self.report['original_recipe_count'], self.report['already_retired_recipe_count'],
                          self.report['retained_recipe_count'], self.report['policy_checks']), (86, 60, 26, 344))
        self.assertEqual(self.report['family_counts'], {
            'poison': {'original': 18, 'retired': 12, 'retained': 6},
            'disease': {'original': 54, 'retired': 48, 'retained': 6},
            'ranged_stim': {'original': 5, 'retired': 0, 'retained': 5},
            'area_stim': {'original': 3, 'retired': 0, 'retained': 3},
            'component': {'original': 6, 'retired': 0, 'retained': 6}})
        self.assertTrue(all(row['output'] and len(row['output_sha256']) == 64 for row in self.recipes.values()))
        self.assertFalse(self.report['additional_retirements'])

    def test_exact_pool_retirement_includes_area_and_all_tiers(self):
        for family, attributes, keep in [('poison', ['health', 'action', 'mind'], 'health'),
                                         ('disease', ['health', 'action', 'mind', 'strength', 'constitution', 'quickness', 'stamina', 'focus', 'willpower'], 'action')]:
            for area in ['', 'area_']:
                for attribute in attributes:
                    for tier in 'abc':
                        key = DRAFT + f'medpack_{family}_{area}{attribute}_{tier}.iff'
                        row = self.recipes[key]
                        self.assertEqual(row['retired'], attribute != keep, key)
                        self.assertEqual(row['output_type'], 'DOTPACK')
                        self.assertEqual(row['output'], 'object/tangible/medicine/crafted/' + Path(key).name)

    def test_ranged_and_area_stims_have_distinct_registered_outputs(self):
        for prefix, output, tiers in [('range', 'damage', 'abcde'), ('area', 'area', 'abc')]:
            for tier in tiers:
                row = self.recipes[DRAFT + f'med_stimpack_{prefix}_{tier}.iff']
                self.assertFalse(row['retired'])
                self.assertEqual(row['output_type'], 'RANGEDSTIMPACK')
                self.assertEqual(row['output'], f'object/tangible/medicine/crafted/medpack_grenade_{output}_{tier}.iff')

    def test_component_and_group_progression_is_preserved(self):
        self.assertEqual(set(self.report['retained_components']), {
            'dispersal_mechanism', 'infection_amplifier', 'resilience_compound',
            'dispersal_mechanism_advanced', 'infection_amplifier_advanced', 'resilience_compound_advanced'})
        self.assertEqual(len(self.report['groups']), 19)
        self.assertTrue(all(group['retained_count'] > 0 for group in self.report['groups']))
        progression = {node['skill']: len(node['retained_recipes']) for node in self.report['progression']}
        self.assertEqual(progression, {
            'science_combatmedic_novice': 5, 'science_combatmedic_medicine_01': 3,
            'science_combatmedic_medicine_02': 7, 'science_combatmedic_medicine_03': 4,
            'science_combatmedic_medicine_04': 4, 'science_combatmedic_master': 3})
        self.assertEqual(self.report['cure_scope']['combat_medic_grants'], [])
        self.assertEqual(self.report['cure_scope']['grants'], {
            'science_doctor_novice': ['craftCurePoisonGroupA'],
            'science_doctor_support_01': ['craftCureDiseaseGroupA'],
            'science_doctor_support_02': ['craftCurePoisonGroupB'],
            'science_doctor_support_03': ['craftCureDiseaseGroupB'],
            'science_doctor_support_04': ['craftCurePoisonGroupC'],
            'science_doctor_master': ['craftCureDiseaseGroupC']})
        for source in ['datatables/skill/skills.iff', 'datatables/crafting/schematic_group.iff',
                       'server/combat/CoreCuMedicalPolicy.h', 'server/combat/DoctorPolicy.h']:
            self.assertRegex(self.report['sources_sha256'][source], r'^[0-9a-f]{64}$')
