import copy
import math
import unittest
from unittest.mock import patch
from server.action_combat import command, events
from server.live_combat import LiveCombatHub
from server.native_motion import project


class ActionCombatTests(unittest.TestCase):
    def setUp(self):
        self.row = dict(id='7', target_id='1', encounter_id='10', attack_id='11',
                        sequence=4, phase='windup', role='melee', cell_id='0',
                        server_now=10., start=10., active_at=11., end_at=11.25,
                        recover_at=12.65, range=3., radius=.35, cosine=.5,
                        origin=[0, 0, 0], direction=[0, 0, 1], age_ms=20.)
        self.visible = {'7': dict(cell_id='0', dead=False)}
        self.receipt = dict(action='contact', encounter_id='10', attack_id='11',
                            actor_id='7', aim_revision=1, contact=False, coverage_start=10.2, coverage_end=11.3)

    def test_contact_shape_and_no_damage_fields(self):
        self.assertEqual(command(self.receipt), self.receipt)
        for change in ({'victim_id': '2'}, {'aim_revision': True}, {'aim_revision': 0}, {'aim_revision': 1.2}, {'damage': 5}, {'contact': 0}, {'coverage_end': math.nan},
                       {'coverage_start': 12.}, {'actor_id': '0'}, {'attack_id': '9'*100}):
            with self.assertRaises(ValueError): command(dict(self.receipt, **change))
        for op in ('start', 'status', 'stop'):
            self.assertEqual(command(dict(action=op)), dict(action=op))

    def test_events_are_visibility_and_cell_fenced(self):
        stream = dict(action_events=[self.row])
        self.assertEqual(events(stream, self.visible, 50)[0]['age_ms'], 70)
        self.assertEqual(events(stream, {}, 0), [])
        self.assertEqual(events(stream, {'7': dict(cell_id='9')}, 0), [])
        self.assertEqual(events(stream, self.visible, 6000), [])
        dead = {'7': dict(cell_id='0', dead=True)}
        self.assertEqual(events(stream, dead, 0), [])
        self.row['phase'] = 'cancelled'
        self.assertEqual(len(events(stream, dead, 0)), 1)

    def test_invalid_native_events_cannot_reach_client(self):
        for change in ({'range': math.inf}, {'origin': [0, 0, math.nan]},
                       {'direction': [0, 0, 0]}, {'sequence': True},
                       {'end_at': 9}, {'attack_id': 'invalid'}):
            self.assertEqual(events(dict(action_events=[dict(self.row, **change)]), self.visible, 0), [])

    def test_animation_timeline_is_native_bounded(self):
        row = dict(self.row, animation='action_worrt', delivery_at=11., animation_end_at=11.5)
        self.assertEqual(events(dict(action_events=[row]), self.visible, 0)[0]['animation'], 'action_worrt')
        for change in ({'animation': 'arbitrary'}, {'delivery_at': math.nan}, {'animation_end_at': 20.}, {'delivery_at': 11.1}):
            self.assertEqual(events(dict(action_events=[dict(row, **change)]), self.visible, 0), [])

    def test_projection_preserves_rpg_freshness_and_filters_old_zone(self):
        stream = dict(source_kind='core3_motion_v1', character_id='1', epoch=2,
                      zone='tatooine', written_at=100., actors=[], action_events=[self.row])
        world = dict(zone='tatooine', actors=[dict(self.visible['7'], id='7', health=55)])
        before = copy.deepcopy(world)
        self.assertEqual(len(project(stream, world, '1', now=100.)['action_events']), 1)
        self.assertEqual(world, before)
        self.assertEqual(project(stream, world, '2', now=100.), {})
        self.assertEqual(project(dict(stream, zone='naboo'), world, '1', now=100.), {})

    def test_preparation_revision_contract(self):
        row = dict(self.row, aim_revision=2, aim_locked=False, lock_at=10.7)
        self.assertEqual(events(dict(action_events=[row]), self.visible, 0)[0]['aim_revision'], 2)
        for change in ({'aim_revision': True}, {'aim_revision': 0}, {'lock_at': math.nan},
                       {'lock_at': 11.1}, {'aim_locked': 1}, {'phase': 'active'}):
            self.assertEqual(events(dict(action_events=[dict(row, **change)]), self.visible, 0), [])
        row.update(aim_locked=True, phase='active')
        self.assertEqual(len(events(dict(action_events=[row]), self.visible, 0)), 1)

    def test_compact_reply_does_not_load_assets_or_replace_rpg_snapshot(self):
        hub = LiveCombatHub()
        reply = dict(compact=True, mutation=dict(success=True, accepted=True))
        with patch('server.live_combat.template_names', side_effect=AssertionError('No full snapshot work')):
            self.assertIs(hub._resolve(reply), reply)

    def test_multiplayer_roster_and_membership_commands(self):
        for op in ('join', 'leave', 'status'):
            self.assertEqual(command(dict(action=op, encounter_id='10')), dict(action=op, encounter_id='10'))
            with self.assertRaises(ValueError): command(dict(action=op, encounter_id='10', victim_id='2'))
        row = dict(self.row, eligible_victim_ids=['1', '2', '3'], hit_policy='cleave')
        self.assertEqual(events(dict(action_events=[row]), self.visible, 0), [row])
        for change in ({'eligible_victim_ids':['1','1']}, {'eligible_victim_ids':['0']}, {'eligible_victim_ids':list(map(str,range(1,10)))}, {'hit_policy':'single'}, {'role':'support'}):
            self.assertEqual(events(dict(action_events=[dict(row, **change)]), self.visible, 0), [])
