#!/usr/bin/env python3
"""Bounded local Core3 snapshot timing using header-only packet metadata.

Runs a real dedicated fixture session, without spawning targets or firing.
Requires podman exec --privileged for AF_PACKET in the existing container.
Never records payloads, native login files, credentials or player names.
"""
import argparse
import json
from pathlib import Path
import statistics
import subprocess
import time
from live_combat_smoke import ROOT, Test

CAPTURE = '''import socket,time,json,struct
s=socket.socket(socket.AF_PACKET,socket.SOCK_RAW,socket.htons(0x0800))
s.bind(('lo',0));s.settimeout(.2)
end=time.time()+8;rows=[]
while time.time()<end:
 try:p,a=s.recvfrom(65535)
 except socket.timeout:continue
 if len(p)<44 or p[23]!=17 or a[2]==4:continue
 h=14+(p[14]&15)*4
 src,dst,length=struct.unpack('!HHH',p[h:h+6])
 if 44463 in (src,dst):
  rows.append({'at':time.time(),'src':src,'dst':dst,'length':length,'opcode':p[h+8:h+10].hex()})
 if len(rows)>100000:raise RuntimeError('Packet metadata bound exceeded')
print(json.dumps(rows))
'''


def analyze(calls, packets):
    samples = []
    port = None
    for call in calls:
        rows = [r for r in packets if call['start'] <= r['at'] <= call['end']]
        requests = [r for r in rows if r['dst'] == 44463 and r['opcode'] == '0009' and r['length'] > 50]
        if len(requests) != 1:
            raise ValueError('Ambiguous capture: expected one native request per measured call')
        sent = requests[0]
        if port is not None and sent['src'] != port:
            raise ValueError('Capture mixed native sessions')
        port = sent['src']
        fragments = [r for r in rows if r['src'] == 44463 and r['dst'] == port and r['opcode'] == '000d']
        if not fragments:
            raise ValueError('No fragmented response in measured window')
        batches = []
        for row in fragments:
            if not batches or row['at']-batches[-1][-1]['at'] > .002:
                batches.append([])
            batches[-1].append(row)
        samples.append({'api_ms': (call['end']-call['start'])*1000,
                        'dispatch_ms': (sent['at']-call['start'])*1000,
                        'first_fragment_ms': (fragments[0]['at']-sent['at'])*1000,
                        'fragment_delivery_ms': (fragments[-1]['at']-fragments[0]['at'])*1000,
                        'post_delivery_ms': (call['end']-fragments[-1]['at'])*1000,
                        'fragments': len(fragments), 'batch_sizes': [len(b) for b in batches]})
    return {'samples': samples, 'medians': {k: statistics.median(r[k] for r in samples)
            for k in samples[0] if k != 'batch_sizes'}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--container', default='swgxr-core3-build')
    args = parser.parse_args()
    fixture = json.loads((ROOT/'runtime/server/ranged-test-fixture.json').read_text())
    if fixture.get('account') != 'rangetest1a142':
        raise ValueError('Dedicated ranged fixture required')
    test = Test(fixture, 'http://127.0.0.1:18080')
    capture = None
    report = {'cleanup_completed': False}
    try:
        test.request('start', {'position': fixture['position'], 'spawn_test_lair': False})
        capture = subprocess.Popen(['podman', 'exec', '--privileged', args.container,
                                    'python3', '-c', CAPTURE], stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, text=True)
        time.sleep(1)
        calls = []
        for _ in range(6):
            start = time.time()
            test.poll()
            calls.append({'start': start, 'end': time.time()})
            time.sleep(.3)
        stdout, stderr = capture.communicate(timeout=10)
        if capture.returncode:
            raise RuntimeError('Header-only capture failed: '+stderr[:200])
        packets = json.loads(stdout)
        report.update(analyze(calls, packets))
        report.update(calls=calls, packet_headers=packets, native_execution=True)
    finally:
        if capture and capture.poll() is None:
            capture.communicate(timeout=10)
        if test.session:
            test.request('stop')
            report['cleanup_completed'] = True
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps(report['medians']))


if __name__ == '__main__':
    main()
