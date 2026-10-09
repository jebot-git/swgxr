"""Combat medicine routes exact supplies through an owned native session."""
import copy
import http.client
from http.server import ThreadingHTTPServer
import json
import threading
import unittest
from unittest.mock import Mock, patch

from server import adapter
from server.live_combat import LiveCombatHub
from server.medic_protocol import command, snapshot
from server.request_gate import RequestGate


class CombatMedicProtocol(unittest.TestCase):
    def payload(self, ability='applypoison'):
        return dict(request_id='combat-medic-001', ability=ability, focus_id='70',
                    item_id='71', target_id='42',
                    pose=dict(tracked=True, crossed=False, grips=False,
                              left=[0, 1, 0], right=[.3, 1, 0]))

    def test_exact_supply_without_client_effect_authority(self):
        for ability in ('applypoison', 'applydisease'):
            data = self.payload(ability)
            result = command('combat_medic', dict(data, potency=999, duration=999,
                             radius=999, amount=999, pool='mind', command='kill'))
            self.assertEqual(result, dict(action='combat_medic', **data))
            with self.assertRaises(ValueError):
                command('doctor', data)

    def test_focus_pack_target_and_tracking_are_required(self):
        for field in ('item_id', 'target_id', 'focus_id', 'request_id', 'pose'):
            data = self.payload()
            data.pop(field)
            with self.subTest(field=field), self.assertRaises(ValueError):
                command('combat_medic', data)
        for field in ('item_id', 'target_id', 'focus_id'):
            for value in (None, '', '0', '-1', 71, True, 'weapon', str(2**64)):
                with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                    command('combat_medic', dict(self.payload(), **{field: value}))

    def test_other_commands_and_invalid_poses_are_rejected(self):
        for ability in ('healstate', 'healmind', 'quickheal', 'sniper_shot', None):
            with self.subTest(ability=ability), self.assertRaises(ValueError):
                command('combat_medic', self.payload(ability))
        for value in (float('nan'), float('inf'), 10001, 'zero'):
            data = self.payload()
            data['pose']['right'][0] = value
            with self.subTest(value=value), self.assertRaises(ValueError):
                command('combat_medic', data)
        data = self.payload()
        data['pose']['tracked'] = False
        self.assertFalse(command('combat_medic', data)['pose']['tracked'])

    def test_heal_mind_uses_direct_healing_selection_and_tracked_cast(self):
        data = self.payload('healmind')
        self.assertEqual(command('select', data)['ability'], 'healmind')
        result = command('heal', data)
        self.assertEqual(result['ability'], 'healmind')
        self.assertNotIn('focus_id', result)  # item_id is the tool for direct care.
        data.pop('pose')
        with self.assertRaises(ValueError):
            command('heal', data)

    def test_snapshot_preserves_native_choices_with_bounds(self):
        combat = dict(abilities=[dict(id='applypoison', learned=True)],
                      supplies=[dict(item_id='71', ability='applypoison', charges=2)],
                      targets=[dict(id='43', eligible=True, relation='hostile')])
        raw = dict(character_id='42', source_kind='core3_medic',
                   state=dict(character_id='42', inventory=dict(items=[]), combat_medic=combat))
        original = copy.deepcopy(raw)
        self.assertEqual(snapshot(raw, '42')['state']['combat_medic'], combat)
        self.assertEqual(raw, original)
        for key, count in (('targets', 33), ('supplies', 257), ('abilities', 3)):
            invalid = copy.deepcopy(raw)
            invalid['state']['combat_medic'][key] = [{}] * count
            with self.subTest(key=key), self.assertRaises(ValueError):
                snapshot(invalid, '42')

    def test_supply_label_uses_exact_localized_inventory_item(self):
        raw = dict(character_id='42', source_kind='core3_medic', state=dict(
            character_id='42', inventory=dict(items=[dict(id='71', template='object/tangible/medicine/crafted/medpack_poison_health_a.iff', display_name='Health Poison A')]),
            combat_medic=dict(supplies=[dict(item_id='71', label='@medicine:poison')])))
        with patch('server.medic_protocol.template_label', return_value=('Old label', '')):
            result = snapshot(raw, '42')
        self.assertEqual(result['state']['combat_medic']['supplies'][0]['label'], 'Health Poison A')
        self.assertEqual(raw['state']['combat_medic']['supplies'][0]['label'], '@medicine:poison')

    def test_http_owned_native_route_and_invalid_inputs(self):
        hub = LiveCombatHub()
        active = dict(account='combatmedic', character_id='42', id='session_cm', process=Mock())
        active['process'].poll.return_value = None
        hub.sessions['combatmedic'] = active
        mutation = dict(character_id='42', source_kind='core3_medic', success=True,
                        state=dict(character_id='42', inventory=dict(items=[])))
        hub._exchange = Mock(return_value=dict(session_live=True, mutation=mutation))
        server = ThreadingHTTPServer(('127.0.0.1', 0), adapter.Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        def post(payload):
            connection = http.client.HTTPConnection(*server.server_address, timeout=2)
            try:
                connection.request('POST', '/medic/combat_medic', json.dumps(payload),
                                   {'Content-Type': 'application/json'})
                response = connection.getresponse()
                return response.status, json.loads(response.read())
            finally:
                connection.close()
        data = dict(self.payload(), account='combatmedic', character_id='42', session_id='session_cm', amount=999)
        try:
            with patch.object(adapter, 'LIVE_COMBAT', hub), patch.object(adapter, 'LOCK', RequestGate(.02, 2)):
                self.assertEqual(post(data)[0], 200)
                native = hub._exchange.call_args.args[1]
                self.assertEqual(native['action'], 'medic')
                self.assertEqual(native['medic'], dict(action='combat_medic', **self.payload()))
                for extra, status in ((dict(character_id='99'), 409), (dict(session_id='foreign'), 409),
                                      (dict(focus_id=None), 400), (dict(ability='healstate'), 400),
                                      (dict(item_id='0'), 400)):
                    with self.subTest(extra=extra):
                        self.assertEqual(post(dict(data, **extra))[0], status)
                self.assertEqual(hub._exchange.call_count, 1)
        finally:
            server.shutdown()
            server.server_close()
            thread.join()
            hub.sessions.clear()


if __name__ == '__main__':
    unittest.main()
