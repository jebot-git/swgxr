#!/usr/bin/env python3
"""Prepare the pinned pilot source bundle from source scripts and supplied TREs.
Requires javalang==0.13.0. --fetch downloads missing pinned source text only;
client media must already be supplied locally by the user.
"""
import argparse
import hashlib
import json
import subprocess
import sys
import urllib.request
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--fetch',action='store_true');a=p.parse_args()
 source=ROOT/'runtime/reference/pilot-progression';lock=json.loads((ROOT/'server/jtl/pilot/sources.lock.json').read_text())
 for row in lock['files']:
  path=source/row['path']
  if not path.exists():
   if not a.fetch:raise SystemExit('Missing '+str(path)+'; rerun with --fetch to retrieve pinned source text.')
   raw=urllib.request.urlopen(row['url'],timeout=60).read()
   if hashlib.sha256(raw).hexdigest()!=row['sha256']:raise SystemExit('Source hash mismatch: '+row['path'])
   path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(raw)
  if hashlib.sha256(path.read_bytes()).hexdigest()!=row['sha256']:raise SystemExit('Source hash mismatch: '+row['path'])
 for script in ('compile_conversations.py','compile_quests.py','prepare_dialogue.py','install.py'):
  subprocess.run([sys.executable,str(Path(__file__).with_name(script))],check=True)
 print('Pinned pilot source bundle prepared and installed; native build and gameplay validation remain separate.')
if __name__=='__main__':main()
