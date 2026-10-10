import http.client
from http.server import ThreadingHTTPServer
import json
import socket
import threading
import unittest
from unittest.mock import Mock, patch
from server import adapter

class PersistentAdapterTest(unittest.TestCase):
    def test_owned_sync_reuses_socket_without_native_lane_or_nagle(self):
        observations = []
        class Handler(adapter.Handler):
            def do_POST(self):
                observations.append((self.connection, self.connection.getsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY)))
                super().do_POST()
        server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        connection = http.client.HTTPConnection(*server.server_address, timeout=2)
        try:
            with patch.object(adapter, 'WORLD_SYNC') as sync, patch.object(adapter, 'LIVE_COMBAT') as native:
                sync.sync.return_value = {'ok': True, 'motion': {'actors': []}}
                native.motion.return_value = {'source_kind': 'core3_motion_v1'}
                for i in range(3):
                    connection.request('POST', '/session/sync', json.dumps({'account': 'motiontest', 'sequence': i}))
                    result = connection.getresponse()
                    self.assertEqual(result.status, 200)
                    self.assertFalse(result.will_close)
                    self.assertTrue(json.loads(result.read())['ok'])
                self.assertEqual(sync.sync.call_count, 3)
                native.request.assert_not_called()
                self.assertTrue(all(s is observations[0][0] and n == 1 for s, n in observations))
                connection.request('POST', '/session/sync', 'bad', {'Content-Length': 'invalid'})
                result = connection.getresponse()
                self.assertEqual(result.status, 400)
                result.read()
        finally:
            connection.close();server.shutdown();server.server_close();thread.join()
