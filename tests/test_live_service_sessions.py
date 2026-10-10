import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch
from server.live_combat import LiveCombatHub, LiveConflict, native_session_capacity


class ServiceSessions(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.hub = LiveCombatHub()
        self.hub._exchange = Mock(side_effect=lambda active, command, **kw: {'session_live': True, 'account': active['account'], 'action': command['action']})
        for account in ('one', 'two'):
            folder = Path(self.directory.name) / account
            folder.mkdir()
            self.hub.sessions[account] = dict(id='session_' + account, account=account, character_id='1' if account == 'one' else '2', folder=folder, options=folder/'options', process=Mock())
            self.hub.sessions[account]['process'].poll.return_value = None

    def tearDown(self):
        self.hub.close()
        self.directory.cleanup()

    def test_account_and_character_isolation(self):
        self.assertEqual(self.hub.request('one', 'services', dict(character_id='1', session_id='session_one', service={'action': 'status'}))['account'], 'one')
        with self.assertRaises(LiveConflict):
            self.hub.request('one', 'services', dict(character_id='2', session_id='session_two', service={}))
        self.assertEqual(self.hub.request('two', 'crafting', dict(character_id='2', session_id='session_two', crafting={}))['action'], 'crafting')

    def test_movement_revision_reaches_direct_and_nested_native_pose(self):
        for action, key in [('update', None), ('services', 'service'), ('session', 'session'),
                            ('scout', 'scout'), ('medic', 'medic'), ('crafting', 'crafting'),
                            ('vehicles', 'vehicles'), ('entertainer', 'entertainer'),
                            ('gathering', 'gathering'), ('corpse', 'corpse')]:
            data = dict(character_id='1', session_id='session_one', movement_revision=7)
            pose = {'position': [1, 2, 3]}
            data.update({key: pose} if key else pose)
            self.hub.request('one', action, data)
            command = self.hub._exchange.call_args.args[1]
            self.assertEqual(command['movement_revision'], 7)
            if key:self.assertNotIn('movement_revision', command[key])
            self.assertNotIn('movement_revision', pose)
        for invalid in (True, -1, 2**53, 1.5, '7'):
            with self.assertRaises(ValueError):
                self.hub.request('one', 'update', dict(character_id='1', session_id='session_one',
                    position=[1, 2, 3], movement_revision=invalid))

    def test_closing_one_does_not_disconnect_the_other(self):
        self.hub.close('one')
        self.assertIsNone(self.hub.active_for('one'))
        self.assertIsNotNone(self.hub.active_for('two'))
        self.hub.active_for('two')['process'].terminate.assert_not_called()

    def test_failed_rpc_only_closes_its_account(self):
        self.hub._exchange.side_effect = RuntimeError('IPC lost')
        with self.assertRaises(RuntimeError):
            self.hub.request('one', 'snapshot', dict(character_id='1', session_id='session_one'))
        self.assertIsNone(self.hub.active_for('one'))
        self.assertIsNotNone(self.hub.active_for('two'))

    def test_uncertain_reply_keeps_owned_session_and_does_not_replay(self):
        self.hub._exchange.side_effect = [
            {'session_live': True, 'error_code': 'native_response_timeout'},
            {'session_live': True, 'snapshot': {'player': {'id': '1'}}},
        ]
        active = self.hub.active_for('one')
        identity = dict(character_id='1', session_id='session_one')
        result = self.hub.request('one', 'vehicles', dict(identity, vehicles={'action': 'activate'}))
        self.assertEqual(result['error_code'], 'native_response_timeout')
        self.assertIs(self.hub.active_for('one'), active)
        self.assertEqual(self.hub._exchange.call_count, 1)
        active['process'].terminate.assert_not_called()
        refreshed = self.hub.request('one', 'snapshot', identity)
        self.assertTrue(refreshed['session_live'])
        self.assertEqual([call.args[1]['action'] for call in self.hub._exchange.call_args_list], ['vehicles', 'snapshot'])
        self.hub._exchange.side_effect = lambda active, command, **kw: {'session_live': True}

    def test_guard_is_per_account(self):
        self.hub.guard('third')
        with self.assertRaises(LiveConflict): self.hub.guard('one')


class SessionCapacity(unittest.TestCase):
    def test_bounded_configuration(self):
        with patch.dict('os.environ', {}, clear=True):
            self.assertEqual(native_session_capacity(), 0)
        for value in ('0', '1', '10', '16', '32', '128', '10000'):
            with patch.dict('os.environ', {'SWGXR_MAX_NATIVE_SESSIONS': value}):
                self.assertEqual(native_session_capacity(), int(value))
        for value in ('-1', '1.5', '', '10 ', 'unlimited'):
            with self.subTest(value=value), patch.dict('os.environ', {'SWGXR_MAX_NATIVE_SESSIONS': value}):
                with self.assertRaisesRegex(ValueError, 'non-negative'):
                    LiveCombatHub()

    def test_ten_owned_sessions_reject_eleventh_without_eviction(self):
        # Exercise actual admission and ownership checks; only native launch/IPC
        # are mocked. These are transport tests, not native capacity evidence.
        with tempfile.TemporaryDirectory() as directory, \
                patch.dict('os.environ', {'SWGXR_MAX_NATIVE_SESSIONS': '10'}), \
                patch('server.live_combat.ROOT', Path(directory)), \
                patch('server.live_combat.subprocess.Popen') as launch, \
                patch('server.live_combat.VOICE_STATE.remove'):
            processes = []
            def process(*args, **kwargs):
                child = Mock()
                child.poll.return_value = None
                processes.append(child)
                for folder in (Path(directory)/'runtime/server/livecombat').iterdir():
                    (folder/'ready.json').write_text('{"zone_ready":true}')
                return child
            launch.side_effect = process
            hub = LiveCombatHub()
            hub._exchange = Mock(side_effect=lambda active, command, **kw: {
                'session_live': command['action'] != 'stop', 'account': active['account'],
                'session_id': active['id'], 'character_id': active['character_id']})
            characters = Mock(side_effect=lambda account: [{'id': str(int(account[6:]) + 1)}])
            try:
                for number in range(10):
                    reply = hub.start('player'+str(number), {'character_id': str(number+1), 'position': [1, 2, 3]}, b'secret', 'test', characters)
                    self.assertTrue(reply['session_live'])
                existing = {account: entry['id'] for account, entry in hub.sessions.items()}
                with self.assertRaisesRegex(LiveConflict, '10 concurrent sessions'):
                    hub.start('player10', {'character_id': '11', 'position': [1, 2, 3]}, b'secret', 'test', characters)
                self.assertEqual(launch.call_count, 10)
                self.assertEqual(existing, {account: entry['id'] for account, entry in hub.sessions.items()})
                for child in processes:
                    child.terminate.assert_not_called()
                # Reap an exited native process without disturbing nine peers.
                processes[0].poll.return_value = 0
                hub.start('player10', {'character_id': '11', 'position': [1, 2, 3]}, b'secret', 'test', characters)
                self.assertEqual(len(hub.sessions), 10)
                self.assertNotIn('player0', hub.sessions)
                for account, session in existing.items():
                    if account != 'player0':
                        self.assertEqual(hub.sessions[account]['id'], session)
            finally:
                hub.close()


class WorldResolution(unittest.TestCase):
    def test_owner_spice_outlines_resolve_without_becoming_targetable_actors(self):
        outline = {'id': '9', 'client_crc': 22, 'customization_hex': '',
                   'outline_only': True, 'attackable': False, 'aggressive': True, 'cell_id': '42'}
        result = {'snapshot': {'world': {'actors': [], 'players': [], 'spice_outlines': [outline]}}}
        hub = LiveCombatHub()
        try:
            with patch('server.live_combat.template_names', return_value={22: 'shared_npc.iff'}):
                world = hub._resolve(result)['snapshot']['world']
            self.assertEqual(world['spice_outlines'][0]['shared_template'], 'shared_npc.iff')
            self.assertEqual(world['spice_outlines'][0]['customization'], {})
            self.assertEqual(world['spice_outlines'][0]['cell_id'], '42')
            self.assertFalse(world['spice_outlines'][0]['attackable'])
            self.assertTrue(world['spice_outlines'][0]['outline_only'])
            self.assertEqual(world['actors'], [])
            self.assertEqual(world['players'], [])
        finally:
            hub.close()

    def test_public_visuals_resolve_without_private_vehicle_devices(self):
        appearance = {'client_crc': 11, 'customization_hex': '', 'hair_customization_hex': '',
                      'hair_template': 'object/tangible/hair/human/hair.iff',
                      'equipment': [{'id': '2', 'client_crc': 22, 'customization_hex': '', 'equipped_slots': ['chest']}]}
        peer = {'id': '1', 'client_crc': 11, 'customization_hex': '', 'appearance': appearance}
        vehicle = {'id': '3', 'position': [1, 2, 3]}
        result = {'snapshot': {'actors': [], 'world': {'players': [peer], 'actors': [],
                  'deployments': [{'id': '4', 'client_crc': 22, 'customization_hex': ''}]},
                  'player': {'vehicles': {'vehicles': [vehicle], 'datapad': [{'private': True}], 'seat': {'private': True}}}}}
        hub = LiveCombatHub()
        with patch('server.live_combat.template_names', return_value={11: 'shared_player.iff', 22: 'shared_item.iff'}):
            resolved = hub._resolve(result)
        world = resolved['snapshot']['world']
        self.assertEqual(world['players'][0]['appearance']['shared_template'], 'shared_player.iff')
        self.assertEqual(world['players'][0]['appearance']['equipment'][0]['shared_template'], 'shared_item.iff')
        self.assertEqual(world['players'][0]['appearance']['equipment'][0]['equipped_slots'], ['chest'])
        self.assertEqual(world['deployments'][0]['shared_template'], 'shared_item.iff')
        self.assertEqual(world['vehicles'], [vehicle])
        self.assertNotIn('datapad', world)
        self.assertNotIn('seat', world)
        hub.close()


if __name__ == '__main__': unittest.main()
