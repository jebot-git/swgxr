#!/usr/bin/python3
"""Synthetic secret-tool protocol only; never touches a real keyring or files."""
import sys
import time
PASSWORD = ' synthetic 🔑\nfixture password \n'
args=sys.argv[1:]
operation=args.pop(0)
if operation=='store':
    assert args.pop(0)=='--label=SWGXR account password'
attributes=dict(zip(args[::2],args[1::2]))
assert attributes['application']=='swgxr'
assert attributes['origin']=='https://example.invalid:18443'
assert PASSWORD not in sys.argv
account=attributes['account']
if account=='hang':time.sleep(30)
if account=='error':
    sys.stderr.write(PASSWORD)
    sys.exit(1)
if account=='overflow':
    sys.stdout.write('x'*513)
    sys.exit(0)
if account=='badutf':
    sys.stdout.buffer.write(b'\xff'*16)
    sys.exit(0)
if account=='missing':sys.exit(1)
if operation=='store':
    # Exact whitespace/non-ASCII must survive; read completes only on pipe EOF.
    value=sys.stdin.buffer.read(1024)
    sys.exit(0 if value==PASSWORD.encode('utf-8') else 2)
if operation=='lookup':sys.stdout.buffer.write(PASSWORD.encode('utf-8'))
elif operation!='clear':sys.exit(2)
