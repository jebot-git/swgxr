#!/usr/bin/env python3
"""Exercise production Godot login/store code across separate processes.

Only creates and clears one synthetic Secret Service entry under a unique .invalid
origin. Never enumerates keyring items or reads a user's login credentials.
"""
import json
from pathlib import Path
import subprocess
import uuid

ROOT=Path(__file__).resolve().parents[2]

def main():
    target=ROOT/'runtime/evidence/remember-system'
    target.mkdir(parents=True,exist_ok=True)
    nonce=uuid.uuid4().hex
    origin=f'https://swgxr-remember-probe-{nonce}.invalid:18443'
    prefs=target/f'preferences-{nonce}.cfg'
    phases=[]
    def run(phase):
        proc=subprocess.run(['godot','--headless','--xr-mode','off','--audio-driver','Dummy','--path',str(ROOT/'client'),
            '--script','res://tests/credential_store_system_probe.gd','--',f'--phase={phase}',f'--origin={origin}',f'--prefs={prefs}'],
            capture_output=True,text=True,timeout=45)
        rows=[]
        for line in proc.stdout.splitlines():
            try: row=json.loads(line)
            except (ValueError,TypeError): continue
            if isinstance(row,dict) and row.get('phase')==phase:rows.append(row)
        # Never retain raw stdout/stderr: helper diagnostics are untrusted.
        result=rows[-1] if rows else {'phase':phase,'passed':False,'error':'No structured probe result'}
        result['exit_code']=proc.returncode
        result['runtime_errors']=any(marker in proc.stderr for marker in ('SCRIPT ERROR:','Parse Error:'))
        phases.append(result)
        return result.get('passed',False) and proc.returncode==0 and not result['runtime_errors']
    try:
        for phase in ('store','load','isolation','forget','absent'):
            if not run(phase):break
    finally:
        try:run('cleanup')
        finally:prefs.unlink(missing_ok=True)
    report={'passed':len(phases)==6 and all(row.get('passed',False) and row.get('exit_code')==0 and not row.get('runtime_errors',False) for row in phases),
        'checks':sum(row.get('checks',0) for row in phases),'phases':phases,'real_os_keyring':True,
        'separate_processes':True,'actual_user_credentials_accessed':False,'secrets_logged':False}
    (target/'system-roundtrip.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report))
    return 0 if report['passed'] else 1
if __name__=='__main__':raise SystemExit(main())
