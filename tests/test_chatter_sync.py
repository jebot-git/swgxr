"""NPC speech stays recipient-private and ages without inventing gameplay updates."""
import copy
import unittest
from server.multiplayer_sync import MultiplayerSync


class ChatterSyncTests(unittest.TestCase):
    def setUp(self):
        self.now = 100.0
        self.hub = MultiplayerSync(lambda: self.now)
        self.world = {'source_kind': 'core3_world', 'players': [], 'actors': []}
        self.speech = {'sequence': 4, 'languages': [{'id': 2, 'progress_basis_points': 250}],
                       'events': [{'id': 'native_event_4', 'actor_id': '55', 'text': 'Ee!',
                                   'zone': 'tatooine', 'position': [0, 1, 0],
                                   'building_id': '0', 'cell_index': 0,
                                   'age_ms': 1000, 'lifetime_ms': 6000}]}
        self.publish(1, self.speech)
        self.publish(2, dict(self.speech, events=[], languages=[]))

    def publish(self, owner, speech, revision=1, **context):
        player = dict(position=[0, 0, 0], zone='tatooine', building_id='0', cell_index=0)
        player.update(context)
        if speech is not None:
            player['npc_speech'] = speech
        self.hub.publish(str(owner), str(owner), 'session' + str(owner),
                         {'player': player, 'world': self.world}, revision)

    def sync(self, owner=1, sequence=1, **kwargs):
        return self.hub.sync(str(owner), dict(character_id=str(owner),
            session_id='session' + str(owner), sequence=sequence, position=[0, 0, 0],
            building_id='0', cell_index=0, **kwargs))

    def test_private_progress_and_no_client_grant_or_shared_event(self):
        response = self.sync(npc_speech={'languages': [{'id': 2, 'progress_basis_points': 10000}]})
        self.assertEqual(response['npc_speech']['languages'][0]['progress_basis_points'], 250)
        self.assertEqual(self.sync(2)['npc_speech']['events'], [])
        self.assertEqual(response['events'], [])
        response['npc_speech']['events'][0]['text'] = 'changed'
        response['npc_speech']['languages'][0]['progress_basis_points'] = 9000
        self.now += .1
        again = self.sync(sequence=2)['npc_speech']
        self.assertEqual(again['events'][0]['text'], 'Ee!')
        self.assertEqual(again['languages'][0]['progress_basis_points'], 250)

    def test_cached_time_expires_speech_without_progress_change(self):
        self.now += 2
        first = self.sync()['npc_speech']
        self.assertEqual(first['events'][0]['age_ms'], 3000)
        self.now += 3
        second = self.sync(sequence=2)['npc_speech']
        self.assertEqual(second['events'], [])
        self.assertEqual(second['languages'], first['languages'])

    def test_native_refresh_uses_original_age_and_old_revision_cannot_rewind(self):
        self.now += 3
        refreshed = copy.deepcopy(self.speech)
        refreshed['events'][0]['age_ms'] = 4000
        self.publish(1, refreshed, revision=2)
        self.publish(1, self.speech, revision=1)
        self.now += 2
        self.assertEqual(self.sync()['npc_speech']['events'], [])

    def test_wrong_zone_and_cell_are_filtered_and_old_backend_clears_cache(self):
        bad = copy.deepcopy(self.speech)
        bad['events'][0]['zone'] = 'naboo'
        self.publish(1, bad, revision=2)
        self.assertEqual(self.sync()['npc_speech']['events'], [])
        bad['events'][0].update(zone='tatooine', building_id='42', cell_index=1)
        self.publish(1, bad, revision=3)
        self.now += .1
        self.assertEqual(self.sync(sequence=2)['npc_speech']['events'], [])
        self.publish(1, None, revision=4)
        self.now += .1
        self.assertEqual(self.sync(sequence=3)['npc_speech'], {'sequence': 0, 'events': [], 'languages': []})

    def test_session_ownership_and_bounded_packet(self):
        with self.assertRaises(ValueError):
            self.hub.sync('2', {'character_id': '1', 'session_id': 'session1', 'sequence': 1})
        for field, value in [('events', self.speech['events'] * 33), ('languages', [{}] * 12), ('sequence', True)]:
            with self.assertRaises(ValueError):
                self.publish(1, dict(self.speech, **{field: value}), revision=2)
        invalid = copy.deepcopy(self.speech)
        invalid['events'][0]['age_ms'] = -1
        with self.assertRaises(ValueError):
            self.publish(1, invalid, revision=2)
        self.assertEqual(self.sync()['npc_speech']['events'][0]['id'], 'native_event_4')


if __name__ == '__main__':
    unittest.main()
