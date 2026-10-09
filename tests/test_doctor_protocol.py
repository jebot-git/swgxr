"""Doctor mutations preserve exact native supplies and the held-focus contract."""
import copy
import unittest
from unittest.mock import patch

from server.medic_protocol import command, snapshot


class DoctorProtocol(unittest.TestCase):
    def payload(self, ability='healstate'):
        return dict(request_id='doctor-test-001', ability=ability, item_id='71',
                    target_id='42', focus_id='72',
                    pose=dict(tracked=True, crossed=False, grips=False,
                              left=[0, 1, 0], right=[.3, 1, 0]))

    def test_exact_supply_and_focus_without_client_effect_authority(self):
        data = dict(self.payload(), state='blind', state_mask=999, amount=999,
                    command='kill', cooldown_seconds=0, range_m=999)
        result = command('doctor', data)
        self.assertEqual(result, dict(action='doctor', **self.payload()))

    def test_healstate_requires_explicit_valid_tool_identity(self):
        for value in (None, '', '0', '-1', 72, True, 'weapon', str(2**64)):
            with self.subTest(value=value), self.assertRaises(ValueError):
                command('doctor', dict(self.payload(), focus_id=value))

    def test_all_doctor_actions_require_target_supply_tracking_and_receipt(self):
        for ability in ('reviveplayer', 'extinguishfire', 'healstate'):
            data = self.payload(ability)
            for field in ('item_id', 'target_id', 'pose', 'request_id'):
                invalid = data.copy()
                invalid.pop(field)
                with self.subTest(ability=ability, field=field), self.assertRaises(ValueError):
                    command('doctor', invalid)
            result = command('doctor', data)
            self.assertEqual(result['ability'], ability)
            if ability != 'healstate':
                self.assertNotIn('focus_id', result)

    def test_doctor_channel_cannot_cast_other_commands(self):
        for ability in ('healdamage', 'healwound', 'quickheal', 'sniper_shot', '', None):
            with self.subTest(ability=ability), self.assertRaises(ValueError):
                command('doctor', self.payload(ability))

    def test_lost_tracking_is_preserved_for_native_rejection(self):
        data = self.payload()
        data['pose']['tracked'] = False
        self.assertFalse(command('doctor', data)['pose']['tracked'])
        data['pose']['left'][0] = float('nan')
        with self.assertRaises(ValueError):
            command('doctor', data)

    def test_snapshot_preserves_native_doctor_supplies_and_preparation_label(self):
        item = dict(id='71', template='object/tangible/medicine/medpack_enhance_health_a.iff',
                    display_name='Vitality Preparation A', medical_preparation_percent=8)
        doctor = dict(healstate=dict(learned=True, requires_medical_focus=True,
                      supplies=[dict(item_id='73', state='blind', state_mask=8, charges=2)]))
        native = dict(character_id='42', source_kind='core3_medic',
                      state=dict(character_id='42', inventory=dict(items=[item]), doctor=doctor))
        original = copy.deepcopy(native)
        with patch('server.medic_protocol.template_label', return_value=('Old Health Pack', '')):
            result = snapshot(native, '42')
        self.assertEqual(native, original)
        self.assertEqual(result['state']['doctor'], doctor)
        self.assertEqual(result['state']['inventory']['items'][0]['name'], 'Vitality Preparation A')
        with self.assertRaises(ValueError):
            snapshot(native, '99')


if __name__ == '__main__':
    unittest.main()
