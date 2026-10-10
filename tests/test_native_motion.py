import copy
import math
import tempfile
import unittest
from pathlib import Path
from server.native_motion import project, read
from server.multiplayer_sync import MultiplayerSync


class NativeMotionTests(unittest.TestCase):
    def setUp(self):
        self.row = dict(id='7', cell_id='0', position=[3, 1, 5], movement_counter=12,
                        speed=4, heading_radians=.2, sequence=42, age_ms=25)
        self.stream = dict(source_kind='core3_motion_v1', character_id='1', zone='tatooine',
                           epoch=2, written_at=100, actors=[self.row])
        self.actor = dict(id='7', cell_id='0', movement_counter=10, position=[1, 1, 1],
                          dead=False, health=25)
        self.world = dict(source_kind='core3_world', zone='tatooine', actors=[self.actor], players=[])

    def projected(self):
        return project(self.stream, self.world, '1', now=100.05)

    def test_compact_native_goal_preserves_health_and_baseline(self):
        before = copy.deepcopy(self.world)
        row = self.projected()['actors'][0]
        self.assertEqual(row['position'], [3, 1, 5])
        self.assertAlmostEqual(row['age_ms'], 75)
        self.assertNotIn('health', row)
        self.assertEqual(before, self.world)

    def test_visibility_cell_counter_and_life_fences(self):
        for change in (dict(id='8'), dict(cell_id='9'), dict(movement_counter=9), dict(age_ms=2001), dict(position=[math.nan, 0, 0])):
            self.stream['actors'] = [dict(self.row, **change)]
            self.assertEqual(self.projected()['actors'], [])
        self.stream['actors'] = [self.row]
        for key in ('dead', 'incapacitated'):
            self.actor[key] = True
            self.assertEqual(self.projected()['actors'], [])
            self.actor[key] = False
        del self.actor['movement_counter']
        self.assertEqual(self.projected()['actors'], [])

    def test_wrap_and_equal_counter_next_step(self):
        self.actor['movement_counter'] = 0xfffffffe
        self.row['movement_counter'] = 1
        self.assertEqual(len(self.projected()['actors']), 1)
        self.actor['movement_counter'] = 1
        self.assertEqual(len(self.projected()['actors']), 1)
        self.row['movement_counter'] = 0xfffffffe
        self.assertEqual(self.projected()['actors'], [])

    def test_original_ground_parent_transform(self):
        self.actor.update(cell_id='9', position=[100, 3, 200], local_position=[1, 2, 3], cell_heading_radians=math.pi/2)
        self.row.update(cell_id='9', position=[3, 4, 6])
        out = self.projected()['actors'][0]
        for a, b in zip(out['position'], [103, 5, 198]):
            self.assertAlmostEqual(a, b)
        self.assertAlmostEqual(out['heading_radians'], .2+math.pi/2)

    def test_session_zone_and_file_freshness(self):
        for change in (dict(character_id='2'), dict(zone='naboo'), dict(written_at=99), dict(written_at=101)):
            self.assertEqual(project(dict(self.stream, **change), self.world, '1', now=100), {})
        with tempfile.TemporaryDirectory() as d:
            path = Path(d)
            self.assertEqual(read(path), {})
            (path/'motion.json').write_text('{')
            self.assertEqual(read(path), {})
            (path/'motion.json').write_text(' '*300000)
            self.assertEqual(read(path), {})

    def test_sync_adds_goals_without_refreshing_rpg_or_world_revision(self):
        from unittest.mock import patch
        now = [50.]
        hub = MultiplayerSync(lambda: now[0])
        hub.publish('test', '1', 'owned', {'player': dict(position=[0, 0, 0], zone='tatooine'), 'world': self.world}, 7)
        now[0] += .3
        payload = dict(character_id='1', session_id='owned', position=[0, 0, 0], sequence=1, world_revision=7)
        with patch('server.native_motion.time.time', return_value=100.05):
            out = hub.sync('test', payload, self.stream)
        self.assertIsNone(out['world'])
        self.assertEqual(out['world_age_ms'], 300)
        self.assertEqual(len(out['motion']['actors']), 1)
        self.assertEqual(hub.sessions['test']['native_at'], 50)

    def test_combat_events_are_bounded_visible_fresh_and_weapon_bound(self):
        self.actor.update(weapon_id='80', weapon_template='object/weapon/test.iff')
        row = dict(id='7', event='attack', sequence=8, age_ms=20, weapon_id='80')
        self.stream['events'] = [row]
        self.assertEqual(self.projected()['events'][0]['weapon_template'], 'object/weapon/test.iff')
        row['weapon_id'] = '81'
        self.assertEqual(self.projected()['events'][0]['weapon_template'], '')
        for change in (dict(id='8'), dict(age_ms=1100), dict(sequence=-1), dict(event='invented')):
            self.stream['events'] = [dict(row, **change)]
            self.assertEqual(self.projected()['events'], [])
        self.stream['events'] = [row]
        self.actor['dead'] = True
        self.assertEqual(self.projected()['events'], [])
