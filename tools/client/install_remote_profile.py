#!/usr/bin/env python3
"""Install server trust for sign-in, or verify a legacy account profile before activation."""
import argparse
import json
import os
from pathlib import Path
import tempfile

if __package__:
    from .remote_connection import RemoteConnection
else:
    from remote_connection import RemoteConnection

ROOT = Path(__file__).resolve().parents[2]


def private_write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    descriptor, temporary = tempfile.mkstemp(prefix='.' + path.name + '.', dir=path.parent)
    try:
        with os.fdopen(descriptor, 'wb') as output:
            output.write(data)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def install(source, destination=None):
    connection = RemoteConnection.load(source)
    destination = Path(destination or ROOT/'runtime/client/connection.json').resolve()
    if not destination.is_relative_to((ROOT/'runtime').resolve()):
        raise ValueError('Private client profiles must remain in the ignored runtime directory.')
    if connection.authenticated:
        health = connection.request_json('/health', timeout=30)
        if health.get('backend') != 'core3' or not isinstance(health.get('core3'), dict) or health['core3'].get('ready') is not True:
            raise ValueError('Remote Core3 is not ready; the default client profile was not changed.')
    certificate = destination.parent/'server-ca.pem'
    private_write(certificate, connection.ca_certificate.read_bytes())
    value = {'base_url':connection.base_url, 'ca_certificate':str(certificate)}
    if connection.authenticated:
        value.update(account=connection.account, token=connection.token)
    private_write(destination, (json.dumps(value, indent=2)+'\n').encode())
    return destination


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True, help='Private per-account profile supplied by deployment.')
    parser.add_argument('--destination', type=Path, default=ROOT/'runtime/client/connection.json')
    args=parser.parse_args()
    try:
        destination=install(args.source,args.destination)
    except (ValueError,OSError) as exc:
        raise SystemExit(str(exc)) from exc
    print('Remote profile installed at '+str(destination)+'. Endpoint-only profiles verify server availability when you sign in. Use --local for the trusted local debug server.')


if __name__=='__main__':main()
