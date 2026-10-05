import ast
import contextlib
import http.server
import io
import unittest
from pathlib import Path

class Tests(unittest.TestCase):
    def test_request_and_error_logs_do_not_leak_native_credentials(self):
        # Load only the actual handler override, avoiding adapter secret/bootstrap side effects.
        tree=ast.parse((Path(__file__).resolve().parents[1]/'server/adapter.py').read_text())
        handler=next(node for node in tree.body if isinstance(node,ast.ClassDef)and node.name=='Handler')
        method=next(node for node in handler.body if isinstance(node,ast.FunctionDef)and node.name=='log_message')
        namespace={}
        exec(compile(ast.Module(body=[method],type_ignores=[]),'adapter_logging','exec'),namespace)
        cls=type('ActualLogOverride',(http.server.BaseHTTPRequestHandler,),{'log_message':namespace['log_message']})
        instance=object.__new__(cls)
        instance.requestline='GET /combat/session?session_id=private-native-session&password=secret HTTP/1.1'
        captured=io.StringIO()
        with contextlib.redirect_stderr(captured):
            instance.log_request(200,123)
            instance.log_error('body=%s token=%s','secret','private-token')
        self.assertEqual(captured.getvalue(),'')
