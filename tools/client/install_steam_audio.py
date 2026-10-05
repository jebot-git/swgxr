#!/usr/bin/env python3
"""Install the pinned FPSloppa Steam Audio dependency; no game media is copied."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import urllib.request

ROOT = Path(__file__).resolve().parents[2]

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-repo',type=Path,help='Use the pinned git objects from an existing FPSloppa checkout')
    args=parser.parse_args()
    lock=json.loads((ROOT/'client/steam-audio.lock.json').read_text())
    target=ROOT/'client/addons/godot-steam-audio'
    for relative,expected in lock['files'].items():
        output=target/relative
        if output.exists() and hashlib.sha256(output.read_bytes()).hexdigest()==expected: continue
        source='addons/godot-steam-audio/'+relative
        if args.source_repo:
            raw=subprocess.check_output(['git','-C',str(args.source_repo),'show',lock['commit']+':'+source])
        else:
            url='https://raw.githubusercontent.com/jebot-git/FPSloppa/'+lock['commit']+'/'+source
            with urllib.request.urlopen(url,timeout=60) as response: raw=response.read()
        if hashlib.sha256(raw).hexdigest()!=expected: raise SystemExit('Steam Audio source hash mismatch: '+relative)
        output.parent.mkdir(parents=True,exist_ok=True); output.write_bytes(raw)
    (target/'bin/libgodot-steam-audio.gdextension').write_text('''[configuration]
entry_symbol = "init_extension"
compatibility_minimum = "4.3"
[libraries]
linux.x86_64.debug = "res://addons/godot-steam-audio/bin/libgodot-steam-audio.linux.template_debug.x86_64.so"
linux.x86_64.release = "res://addons/godot-steam-audio/bin/libgodot-steam-audio.linux.template_release.x86_64.so"
[dependencies]
linux.x86_64.debug = {"res://addons/godot-steam-audio/bin/libphonon.so": ""}
linux.x86_64.release = {"res://addons/godot-steam-audio/bin/libphonon.so": ""}
''')
    print('Installed Steam Audio 0.3.1 + FPSloppa fixes at '+lock['commit'])

if __name__=='__main__':main()
