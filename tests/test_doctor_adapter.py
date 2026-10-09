"""Exercise Doctor's HTTP route through the owned native session gate."""
import http.client
from http.server import ThreadingHTTPServer
import json
import threading
import unittest
from unittest.mock import Mock, patch

from server import adapter
from server.live_combat import LiveCombatHub
from server.request_gate import RequestGate


class DoctorAdapter(unittest.TestCase):
    def test_http_owned_native_route_and_focus_validation(self):
        hub = LiveCombatHub()
        active = dict(account='doctor', character_id='42', id='session_doctor', process=Mock())
        active['process'].poll.return_value = None
        hub.sessions['doctor'] = active
        mutation = dict(character_id='42', source_kind='core3_medic',
                        success=True, state=dict(character_id='42', inventory=dict(items=[])))
        hub._exchange = Mock(return_value=dict(session_live=True, mutation=mutation))
        server = ThreadingHTTPServer(('127.0.0.1', 0), adapter.Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()

        def post(payload):
            connection = http.client.HTTPConnection(*server.server_address, timeout=2)
            try:
                connection.request('POST', '/medic/doctor', json.dumps(payload),
                                   {'Content-Type': 'application/json'})
                response = connection.getresponse()
                return response.status, json.loads(response.read())
            finally:
                connection.close()

        payload = dict(account='doctor', character_id='42', session_id='session_doctor',
                       request_id='doctor-http-001', item_id='71', target_id='43',
                       focus_id='72', ability='healstate', state='blind', amount=9999,
                       pose=dict(tracked=True, crossed=False, grips=False,
                                 left=[0, 1, 0], right=[.3, 1, 0]))
        try:
            with patch.object(adapter, 'LIVE_COMBAT', hub), patch.object(adapter, 'LOCK', RequestGate(.02, 2)):
                self.assertEqual(post(payload)[0], 200)
                native = hub._exchange.call_args.args[1]
                self.assertEqual(native['action'], 'medic')
                self.assertEqual(native['medic']['action'], 'doctor')
                self.assertEqual(native['medic']['focus_id'], '72')
                for field in ('state', 'amount', 'account', 'character_id'):
                    self.assertNotIn(field, native['medic'])
                for extra, status in ((dict(character_id='99'), 409),
                                      (dict(session_id='foreign'), 409),
                                      (dict(focus_id=None), 400),
                                      (dict(ability='healdamage'), 400),
                                      (dict(item_id='0'), 400)):
                    with self.subTest(extra=extra):
                        self.assertEqual(post(dict(payload, **extra))[0], status)
                self.assertEqual(hub._exchange.call_count, 1)
        finally:
            server.shutdown()
            server.server_close()
            thread.join()
            hub.sessions.clear()


if __name__ == '__main__':
    unittest.main()
