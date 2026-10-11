"""Keep the droid basic-attack correction bounded to verified original mappings."""
import sys
import unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parent))
from character_animations import ground_action_bindings
from prepare_ground_actions import reviewed_catalog
import hashlib,json


class DroidBindings(unittest.TestCase):
    def test_negotiation_revision_is_independent_of_optional_prepared_models(self):
        profiles={'one':{'profiles':{'unarmed':{'duration':2}}},'two':{'profiles':{'pistol':{'duration':1}}}}
        lock={'templates':profiles,'revision':hashlib.sha256(json.dumps(profiles,sort_keys=True,separators=(',',':')).encode()).hexdigest()}
        self.assertEqual(reviewed_catalog({'one':profiles['one']},lock),profiles)
        with self.assertRaises(ValueError):reviewed_catalog({'one':{'profiles':{'unarmed':{'duration':3}}}},lock)
        with self.assertRaises(ValueError):reviewed_catalog({},lock)
    def select(self, heavy, light=None):
        table = {'unarmed_standing_ready_jab_double': [{'source': heavy, 'speed_scale': 1.0}]}
        if light is not None:
            table['attack_light_standing'] = light
        with patch('character_animations.resolve', side_effect=lambda node, selectors: node):
            return list(ground_action_bindings(table, {}))[0]

    def test_authored_light_clip_preserves_speed(self):
        for prefix, suffix in [('protocol_droid', 'melee_'), ('astromech', '')]:
            heavy = f'appearance/animation/{prefix}_cbt_attack_{suffix}heavy.ans'
            light = f'appearance/animation/{prefix}_cbt_attack_{suffix}light.ans'
            slot, logical, leaf = self.select(heavy, [{'source': light, 'speed_scale': 1.0}])
            self.assertEqual((slot, logical, leaf['source'], leaf['speed_scale']),
                             ('unarmed', 'attack_light_standing', light, 1.0))

    def test_canine_reference_and_gorax_basic_clip(self):
        from unittest.mock import patch
        table={'cbt_stand_combat_attack_light':[{'source':'appearance/animation/canine_cbt_stand_attack_light.ans','speed_scale':1.0}]}
        with patch('character_animations.resolve', side_effect=lambda node, selectors: node):
            slot,logical,leaf=list(ground_action_bindings(table,{}))[0]
        self.assertEqual(leaf['source'],'appearance/animation/canine_cbt_stand_combat_attack_light.ans')
        self.assertIn('selection_basis',leaf)
        _,logical,leaf=self.select('appearance/animation/gorax_cbt_attack_melee.ans',[{'source':'appearance/animation/gorax_cbt_attack.ans','speed_scale':1.0}])
        self.assertEqual(logical,'attack_light_standing')
        self.assertEqual(leaf['speed_scale'],1.0)

    def test_missing_native_command_definitions_fail_preparation(self):
        import tempfile
        from ground_specials import compile_specials
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaisesRegex(ValueError,'command definitions'):
                compile_specials(Path(folder),None,[])

    def test_unmapped_droid_attack_and_explicit_visual_fallback(self):
        for family in ('cll8','eg6','mouse_droid'):
            table={'loop_standing':[{'source':'appearance/animation/'+family+'_idl_stand.ans','speed_scale':1.}]}
            with patch('character_animations.resolve', side_effect=lambda node, selectors: node):
                slot,logical,leaf=list(ground_action_bindings(table,{}))[0]
            self.assertEqual(slot,'unarmed')
            self.assertEqual(leaf['visual_fallback'],family!='cll8')
            self.assertEqual(leaf['speed_scale'],1.)
            self.assertTrue(leaf['source'].endswith('cll8_cbt_stand_combat_fire1.ans' if family=='cll8' else family+'_idl_stand.ans'))

    def test_absent_ambiguous_or_unrelated_light_is_not_substituted(self):
        heavy = 'appearance/animation/astromech_cbt_attack_heavy.ans'
        light = {'source': 'appearance/animation/astromech_cbt_attack_light.ans', 'speed_scale': 1.0}
        other = {'source': 'appearance/animation/other.ans', 'speed_scale': 1.0}
        for choice in (None, [other], [light, other]):
            self.assertEqual(self.select(heavy, choice)[2]['source'], heavy)
        self.assertEqual(self.select(other['source'], [light])[2]['source'], other['source'])
