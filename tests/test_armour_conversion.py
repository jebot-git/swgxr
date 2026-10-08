import hashlib
import json
import unittest

from tools.combat.install_armour_profile import generate, ROOT
from tests import test_weapon_protocol as weapon_fixtures
from server.weapon_protocol import weapon_snapshots


class ArmourReferencesTests(unittest.TestCase):
    def test_crafting_ranges_include_required_segment_not_consumed_quantity(self):
        rows, fallbacks = generate()
        refs = {row['path']: row for row in rows}
        composite = refs['object/tangible/wearables/armor/composite/armor_composite_chest_plate.iff']
        self.assertEqual((composite['minimum'], composite['maximum']), (2, 50))
        # OVERRIDECOMBINE must not inherit a segment's special-effectiveness range.
        self.assertEqual((composite['specialMinimum'], composite['specialMaximum']), (2, 50))
        chitin = refs['object/tangible/wearables/armor/chitin/armor_chitin_s01_chest_plate.iff']
        self.assertEqual((chitin['minimum'], chitin['maximum']), (6, 35))
        self.assertEqual((chitin['specialMinimum'], chitin['specialMaximum']), (5, 40))
        self.assertGreater(len(rows), 150)
        self.assertTrue(fallbacks)
        self.assertEqual(len(rows), len(refs))
        self.assertTrue(all(row['maximum'] > row['minimum'] for row in rows))


class ArmourWeaponProtocolTests(unittest.TestCase):
    def setUp(self):
        weapon_fixtures.WeaponProtocolTests.setUp(self)

    def attrs(self):
        config = json.loads((ROOT/'server/combat/crafting_balance.json').read_text())
        revision = hashlib.sha256((ROOT/'client/combat/balance.json').read_bytes()
                                  +(ROOT/'server/combat/crafting_balance.json').read_bytes()).hexdigest()
        values = {'swgxr.version':str(config['version']), 'swgxr.balance':revision,
                  'swgxr.id':'pistol_cdef','swgxr.valid':'1','weapon_cert_status':'Yes',
                  'swgxr.damage_type':'2','swgxr.armor_piercing':'0',
                  'swgxr.combat_version':'1','swgxr.combat_revision':'a'*64,
                  'swgxr.base_type':'2','swgxr.element_type':'32',
                  'swgxr.element_fraction':'0','swgxr.penetration':'0','swgxr.damage_scale':'1',
                  'swgxr.armour_output_scale':'.9','swgxr.capacity_recovery_scale':'.9',
                  'Rate of fire (RPM)':'216','Capacity (shots)':'12'}
        for name, value in {'min_damage':10,'max_damage':20,'wounds':5,'near_range':0,
                            'near_accuracy':0,'ideal_range':20,'ideal_accuracy':0,
                            'max_range':40,'max_accuracy':0,'rpm_modifier':1,
                            'capacity_modifier':1,'attack_delay':3.5,'health_cost':10,
                            'action_cost':15,'mind_cost':10,'max_condition':1000,
                            'condition_damage':0}.items():
            values['swgxr.'+name] = str(value)
        self.result['variables']['weaponAttributes']['o3'] = values
        return values

    def test_native_profile_survives_adapter_without_reapplying_penalty(self):
        self.attrs()
        item = weapon_snapshots(self.result, '1')['weapons'][0]
        self.assertEqual(item['rpm'],216)
        self.assertEqual(item['core3']['damage_profile']['base_type'],'energy')
        self.assertEqual(item['armour_scales']['recovery_scale'],.9)

    def test_old_server_and_nonfinite_conversion_fail_closed(self):
        attrs = self.attrs()
        attrs.pop('swgxr.combat_version')
        with self.assertRaisesRegex(ValueError,'rebuild'): weapon_snapshots(self.result,'1')
        attrs = self.attrs()
        attrs['swgxr.penetration'] = 'nan'
        with self.assertRaisesRegex(ValueError,'Non-finite'): weapon_snapshots(self.result,'1')


if __name__ == '__main__': unittest.main()
