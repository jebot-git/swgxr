#!/usr/bin/env python3
"""Daily graceful game-service restart; never restart/reset the persistent DB.

The native save-and-exit completes before asking systemd to stop its supervisor.
On a native timeout, abort without kill/reboot and leave a journal failure.
"""
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import urllib.request

ROOT=Path(__file__).resolve().parents[2]
FRONTENDS=('swgxr-voice.service','swgxr-gateway.service','swgxr-adapter.service')
SERVICES=('swgxr-core3.service','swgxr-adapter.service','swgxr-gateway.service','swgxr-voice.service')


def command(args):
    return subprocess.run(args,check=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True).stdout.strip()


def health():
    # Adapter is bound to loopback; no credential or new player session required.
    with urllib.request.urlopen('http://127.0.0.1:18080/health',timeout=20) as response:
        value=json.load(response)
    return value.get('backend')=='core3' and value.get('core3',{}).get('ready') is True


def event(phase,**data):
    print(json.dumps(dict(phase=phase,utc=time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),**data)),flush=True)


def restart(root=ROOT,run=command,check_health=health,pause=time.sleep):
    """Dependency order is intentional. Failed native shutdown never advances."""
    if run(['systemctl','show','--property=ActiveState','--value','swgxr.target'])!='active':
        event('skipped',reason='Game target is not active');return
    event('begin',scope='Core3, adapter, HTTPS gateway and voice; database/container retained')
    run(['systemctl','stop',*FRONTENDS])
    event('saving_native_world')
    # Calling the graceful runtime directly avoids systemd's stop-timeout
    # escalation while Core3 is still saving. It writes only `exit` to its FIFO.
    run(['/usr/bin/python3',str(root/'tools/deploy/runtime.py'),'stop-core'])
    event('native_save_and_exit_confirmed')
    # Core3 is now gone. Clear/synchronize only the completed supervisor job.
    run(['systemctl','stop','swgxr-core3.service'])
    run(['systemctl','start',*SERVICES])
    for service in SERVICES:
        if run(['systemctl','is-active',service])!='active':
            raise RuntimeError('Restarted game service is not active: '+service)
    ready=False
    for attempt in range(6):
        try:ready=check_health()
        except (OSError,ValueError,TimeoutError):ready=False
        if ready:break
        if attempt<5:pause(5)
    if not ready:raise RuntimeError('Native login/zone readiness did not recover after scheduled restart')
    event('complete',native_login_zone_ready=True,services=list(SERVICES))


def main():
    if os.geteuid()!=0:raise RuntimeError('Scheduled restart requires systemd administrator execution')
    marker=ROOT/'runtime/remote/bootstrap.json'
    if json.loads(marker.read_text()).get('kind')!='swgxr-isolated-remote-v1':
        raise RuntimeError('Managed persistent remote bootstrap required')
    # systemd serializes this oneshot; a separate daily timer cannot overlap it.
    restart()


if __name__=='__main__':
    try:main()
    except Exception as error:
        # Never print subprocess output/command input that could contain secrets.
        event('failed',error_type=type(error).__name__,reason=str(error) if isinstance(error,RuntimeError) else 'Inspect managed service logs; no forced shutdown was requested')
        sys.exit(1)
