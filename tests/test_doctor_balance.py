"""Cross-policy resource pressure and sustained preparation benefit, without a game server."""
import unittest
from tools.server.audit_doctor_balance import audit


class DoctorBalance(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.balance = audit()

    def test_stims_spend_resources_and_metabolic_extends_finite_sustain(self):
        rows = self.balance['sustained_stims']
        old = rows['old_cost_no_metabolic']
        current = rows['current_no_metabolic']
        metabolic = rows['current_max_metabolic']
        self.assertIsNone(old['first_resource_delayed_cast_seconds'])
        self.assertGreater(current['first_resource_delayed_cast_seconds'], 90)
        self.assertLess(current['first_resource_delayed_cast_seconds'], 120)
        self.assertGreater(metabolic['first_resource_delayed_cast_seconds'], current['first_resource_delayed_cast_seconds'])
        self.assertLess(metabolic['first_resource_delayed_cast_seconds'], 150)
        self.assertLess(current['casts_in_180_seconds'], metabolic['casts_in_180_seconds'])
        self.assertLess(metabolic['casts_in_180_seconds'], old['casts_in_180_seconds'])
        for row in (current, metabolic):
            self.assertGreater(row['remaining_action'], 0)
            self.assertGreater(row['remaining_mind'], 0)

    def test_quality_master_reward_and_emergency_ceiling(self):
        profiles = self.balance['profiles']
        medic, branch, master = (profiles[key] for key in ('master_medic', 'doctor_wound_iv', 'master_doctor'))
        previous = 0
        for tier, row in sorted(master['crafted_stims'].items()):
            self.assertGreater(row['high_quality_hp'], row['low_quality_hp'])
            self.assertGreater(row['high_quality_hp'], previous)
            self.assertGreater(row['high_quality_hp'], branch['crafted_stims'][tier]['high_quality_hp'])
            previous = row['high_quality_hp']
        self.assertEqual(master['crafted_stims']['E']['high_quality_hp'], 1014)
        self.assertEqual(master['quick_hp'], 1380)
        self.assertLess(master['quick_hp'] * 1.5, 3000 * .75)
        self.assertGreater(master['wound_multiplier'] - 1, master['direct_multiplier'] - 1)
        self.assertGreater(master['direct_multiplier'] - 1, master['quick_multiplier'] - 1)
        self.assertGreater(master['quick_hp'], medic['quick_hp'])


if __name__ == '__main__':
    unittest.main()
