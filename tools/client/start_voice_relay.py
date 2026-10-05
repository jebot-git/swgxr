"""Start only the explicitly local, loopback-bound voice development relay."""
import json
import os
from pathlib import Path
import secrets
import socket
import subprocess
import sys
import time


def ensure_local_voice(root):
    root=Path(root).resolve()
    folder=root/'runtime/server';folder.mkdir(parents=True,exist_ok=True)
    script=root/'server/voice_relay.py'
    if not script.is_file():raise ValueError('Voice relay code is unavailable.')
    pidfile=folder/'voice.pid'
    try:
        pid=int(pidfile.read_text().strip())
        command=Path('/proc',str(pid),'cmdline').read_bytes().split(b'\0')
        if str(script).encode() in command and b'--loopback-debug' in command:
            return
    except (OSError,ValueError):pass
    with socket.socket() as probe:
        probe.settimeout(.25)
        if probe.connect_ex(('127.0.0.1',18084))==0:
            raise ValueError('Local voice port18084 is occupied by an unrecognized process.')
    secret=folder/'voice.secret'
    try:
        descriptor=os.open(secret,os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600)
        with os.fdopen(descriptor,'wb') as output:output.write(secrets.token_bytes(32))
    except FileExistsError:pass
    if secret.stat().st_size<32:raise ValueError('Existing local voice signing secret is invalid.')
    secret.chmod(0o600)
    config=folder/'voice-local.json'
    value={'voice_secret':str(secret),'voice_state':str(folder/'voice-state.json'),'accounts':{}}
    descriptor=os.open(config,os.O_CREAT|os.O_TRUNC|os.O_WRONLY,0o600)
    with os.fdopen(descriptor,'w') as output:json.dump(value,output)
    config.chmod(0o600)
    logpath=folder/'voice.log'
    with logpath.open('ab') as log:
        logpath.chmod(0o600)
        process=subprocess.Popen([sys.executable,str(script),'--config',str(config),
            '--loopback-debug','--bind','127.0.0.1','--port','18084'],cwd=root,
            stdin=subprocess.DEVNULL,stdout=log,stderr=log,start_new_session=True)
    pidfile.write_text(str(process.pid)+'\n')
    deadline=time.monotonic()+3
    while time.monotonic()<deadline:
        if process.poll() is not None:raise ValueError('Local voice relay exited; inspect runtime/server/voice.log.')
        with socket.socket() as probe:
            probe.settimeout(.1)
            if probe.connect_ex(('127.0.0.1',18084))==0:return
        time.sleep(.05)
    raise ValueError('Local voice relay did not become ready.')
