"""Real loopback HTTP validates and binds bounty intent to its native owner."""
import http.client
from http.server import ThreadingHTTPServer
import json
import threading
import unittest
from unittest.mock import Mock, patch

from server import adapter
from server.bounty_protocol import FIELDS
from server.live_combat import LiveCombatHub
from server.request_gate import RequestGate


class BountyAdapterTests(unittest.TestCase):
    def test_owned_services_route_and_native_result(self):
        hub = LiveCombatHub()
        active = dict(account='hunter', character_id='42', id='hunter-session', process=Mock())
        active['process'].poll.return_value = None
        hub.sessions['hunter'] = active
        raw = dict(backend='core3', source_kind='core3_services', character_id='42',
                   player={}, terminal={}, missions=[],
                   mutation=dict(success=True, request_id='bounty-request-001'))
        hub._exchange = Mock(return_value={'session_live':True, 'mutation':raw})
        server = ThreadingHTTPServer(('127.0.0.1', 0), adapter.Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()

        def post(action, data):
            connection = http.client.HTTPConnection(*server.server_address, timeout=2)
            try:
                connection.request('POST', '/services/' + action, json.dumps(data),
                                   {'Content-Type':'application/json'})
                response = connection.getresponse()
                return response.status, json.loads(response.read())
            finally:
                connection.close()

        try:
            with patch.object(adapter, 'LIVE_COMBAT', hub), \
                 patch.object(adapter, 'LOCK', RequestGate(.02, 2)), \
                 patch.object(adapter.SERVICES_PRESENCE, 'register', return_value={}), \
                 patch.object(adapter.VOICE_STATE, 'publish'):
                for action, field in FIELDS.items():
                    payload = dict(account='hunter', character_id='42', session_id='hunter-session',
                                   request_id='bounty-request-001', **{field:'55'},
                                   success=True, reward=1000000, player_target=True,
                                   target_position=[123,456,789])
                    if action == 'bounty_probe':
                        payload['search_planet'] = 'naboo'
                    with self.subTest(action=action):
                        status, response = post(action, payload)
                        self.assertEqual(status, 200)
                        self.assertTrue(response['ok'])
                        self.assertEqual(response['source_kind'], 'core3_services')
                        command = hub._exchange.call_args.args[1]
                        self.assertEqual(command['action'], 'services')
                        expected_command = dict(action=action, request_id='bounty-request-001', **{field:'55'})
                        if action == 'bounty_probe':
                            expected_command['search_planet'] = 'naboo'
                        self.assertEqual(command['service'], expected_command)
                        admitted = hub._exchange.call_count
                        for changes, expected in (({'character_id':'43'},409),
                                                  ({'session_id':'foreign'},409),
                                                  ({field:'0'},400),
                                                  ({'request_id':'bad'},400)):
                            self.assertEqual(post(action, dict(payload, **changes))[0], expected)
                        self.assertEqual(hub._exchange.call_count, admitted)
        finally:
            server.shutdown()
            server.server_close()
            thread.join()
            hub.sessions.clear()


if __name__ == '__main__':
    unittest.main()
