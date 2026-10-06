#!/usr/bin/env python3
"""Fresh isolated VPS runtime bootstrap and supervised processes; never legacy init-db."""
import argparse
import json
import math
import os
import pwd
import re
import secrets
import signal
import stat
import subprocess
import sys
import time
import threading
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from server.planets import SUPPORTED_PLANETS, planet

def vehicle_catalog_status(root=ROOT):
    path = root/'runtime/assets/vehicles/catalog.json'
    result = {'path': 'runtime/assets/vehicles/catalog.json', 'passed': False, 'ready': [], 'errors': []}
    try:
        catalog = json.loads(path.read_text())
        def point(values):
            return isinstance(values, list) and len(values) == 3 and all(type(v) in (int, float) and math.isfinite(v) for v in values)
        for name in ('speederbike', 'speederbike_swoop', 'speederbike_flash', 'landspeeder_x34', 'landspeeder_x31', 'landspeeder_av21'):
            template = 'object/mobile/vehicle/'+name+'.iff'
            item = catalog.get('items', {}).get(template, {})
            seats, controls = item.get('seats', []), item.get('controls', [])
            valid = (item.get('status') == 'ready' and isinstance(seats, list) and bool(seats)
                     and all(isinstance(seat, dict) and seat.get('id') and point(seat.get('position')) for seat in seats)
                     and isinstance(controls, list) and len(controls) == 2 and all(point(v) for v in controls))
            for key in ('bounds_min', 'bounds_max'):
                values = item.get(key, [])
                valid = valid and point(values)
            if valid: result['ready'].append(template)
            else: result['errors'].append('Missing or invalid native vehicle descriptor: '+template)
    except (OSError, ValueError, TypeError, AttributeError) as exc:
        result['errors'].append('Vehicle metadata catalog unavailable or invalid: '+str(exc))
    result['passed'] = not result['errors']
    return result

REMOTE = ROOT/'runtime/remote'
STATE = ROOT/'runtime/server'
BIN = ROOT/'vendor/Core3/MMOCoreORB/bin'
CONTAINER = 'swgxr-core3-build'
IMAGE = 'localhost/swgxr-runtime:20261004'
MARKER = 'swgxr-isolated-remote-v1'
APPARMOR_PROFILE = 'swgxr-core3'
CONTAINER_ROOT = '/workspace'


def run(args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def private_write(path, text):
    tmp = path.with_suffix(path.suffix+'.tmp')
    fd = os.open(tmp, os.O_WRONLY|os.O_CREAT|os.O_TRUNC, 0o600)
    os.fchmod(fd, 0o600)
    with os.fdopen(fd, 'w') as handle: handle.write(text)
    tmp.replace(path)


def assignment(source, key, value):
    pattern = r'(?m)^'+re.escape(key)+r'\s*=\s*[^\n]*$'
    source, count = re.subn(pattern, key+' = '+value, source)
    if count != 1: raise ValueError('Expected one source setting: '+key)
    return source


def validate_planets(planets):
    values = tuple(planets)
    if not values or len(set(values)) != len(values):
        raise ValueError("Enabled ground planets must be nonempty and unique")
    return tuple(planet(value) for value in values)


def render_config(source, password, planets=("tatooine",)):
    planets = validate_planets(planets)
    if not re.fullmatch(r'[0-9a-f]{64}', password): raise ValueError('Invalid generated DB credential')
    changes = {'Core3.DBHost':'"127.0.0.1"','Core3.DBName':'"swgemu"','Core3.DBUser':'"swgemu"',
        'Core3.DBPass':json.dumps(password),'Core3.ZonesEnabled':'{'+','.join(json.dumps(p) for p in planets)+'}','Core3.SpaceZonesEnabled':'{}',
        'Core3.ZoneProcessingThreads':'2','Core3.MaxNavMeshJobs':'1','Core3.AutoReg':'1'}
    for key,value in changes.items(): source=assignment(source,key,value)
    # The optional bug-tracker database is outside this prototype's scope.
    if re.search(r'(?m)^Core3\.MantisHost\s*=',source):
        source=assignment(source,'Core3.MantisHost','""')
    else:
        source+='\nCore3.MantisHost = ""\n'
    return '-- Remote profile; private generated credential; source files remain unchanged.\n'+source


def render_resources(source, planets=("tatooine",)):
    planets = validate_planets(planets)
    for key,value in {'buildInitialResourcesFromScript':'0','activeZones':json.dumps(','.join(planets)),
                      'fixedpoolincludes':'{{"iron",14}}'}.items(): source=assignment(source,key,value)
    return source


def validate_schema(source):
    # Fresh schema export may seed only realm identity and schema version.
    targets = re.findall(r'(?im)^\s*(?:INSERT\s+INTO|REPLACE\s+INTO)\s+(?:`?swgemu`?\.)?`?([a-z_]+)`?', source)
    if sorted(targets) != ['db_metadata','galaxy']:
        raise ValueError('Expected schema-only SQL with galaxy and db_metadata seeds only')
    if not re.search(r'(?im)^USE\s+`?swgemu`?\s*;',source): raise ValueError('Missing swgemu schema selection')


def require_bootstrap():
    if (REMOTE/'bootstrap.json').exists():
        if json.loads((REMOTE/'bootstrap.json').read_text()).get('kind') == MARKER: return
    raise RuntimeError('Fresh remote bootstrap marker required')


def bootstrap(confirmed):
    if not confirmed: raise RuntimeError('bootstrap requires --confirm-fresh-remote')
    source = (BIN/'conf/config-local.lua').read_text()
    resource = (BIN/'scripts/managers/resource_manager.lua').read_text()
    validate_schema((REMOTE/'schema.sql').read_text())
    if (REMOTE/'bootstrap.json').exists():
        require_bootstrap()
        for name in ('db-password','config-local.lua','resource_manager.lua'):
            if not (REMOTE/name).is_file(): raise RuntimeError('Incomplete prior bootstrap; inspect before repair')
        print('Existing isolated bootstrap retained; no database/configuration reset')
        return
    for path in (REMOTE/'mysql', REMOTE/'databases'):
        if path.exists() and any(path.iterdir()): raise RuntimeError('Refusing to adopt existing database state')
    if (REMOTE/'db-password').exists():
        raise RuntimeError('Unmarked generated configuration exists; inspect interrupted bootstrap')
    password=secrets.token_hex(32)
    config=render_config(source,password); resource=render_resources(resource)
    REMOTE.mkdir(parents=True,exist_ok=True); STATE.mkdir(parents=True,exist_ok=True)
    for path in (REMOTE/'mysql',REMOTE/'databases',REMOTE/'logs'):
        path.mkdir(exist_ok=True);path.chmod(0o700)
    private_write(REMOTE/'db-password',password+'\n')
    private_write(REMOTE/'config-local.lua',config)
    private_write(REMOTE/'resource_manager.lua',resource)
    private_write(REMOTE/'bootstrap.json',json.dumps({'kind':MARKER,'image':IMAGE,'created':int(time.time())}))
    print('Fresh private DB credential and Tatooine-only overlays prepared')


def podman(*args): return run(['podman',*args],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True).stdout


def inspect_container():
    value=podman('inspect',CONTAINER)
    data=json.loads(value)[0]
    if data['Config'].get('Labels',{}).get('swgxr.remote') != MARKER or data['HostConfig']['NetworkMode'] != 'none':
        raise RuntimeError('Refusing unmanaged or network-connected container name collision')
    if data['Config']['Image'] != IMAGE: raise RuntimeError('Container image does not match pinned runtime')
    if data.get('AppArmorProfile') != APPARMOR_PROFILE: raise RuntimeError('Container requires dedicated AppArmor profile; recreate only after native processes stop')
    mounts={entry['Destination']:entry['Source'] for entry in data.get('Mounts',[])}
    for target,source in expected_mounts().items():
        if mounts.get(target) != str(source): raise RuntimeError('Container mounts do not match isolated runtime')
    if data['HostConfig'].get('PortBindings'): raise RuntimeError('Native container must not publish ports')
    return data


def expected_mounts():
    return {'/workspace':ROOT,
        '/workspace/vendor/Core3/MMOCoreORB/bin/conf/config-local.lua':REMOTE/'config-local.lua',
        '/workspace/vendor/Core3/MMOCoreORB/bin/scripts/managers/resource_manager.lua':REMOTE/'resource_manager.lua',
        '/workspace/vendor/Core3/MMOCoreORB/bin/databases':REMOTE/'databases',
        '/workspace/vendor/Core3/MMOCoreORB/bin/log':REMOTE/'logs'}


def load_apparmor():
    if ROOT == Path('/workspace'):raise RuntimeError('AppArmor loading is a host-only operation')
    enabled=Path('/sys/module/apparmor/parameters/enabled')
    if not enabled.exists() or enabled.read_text().strip()!='Y':raise RuntimeError('Enforced AppArmor required for this remote profile')
    source=ROOT/'tools/deploy/apparmor'/APPARMOR_PROFILE
    target=Path('/etc/apparmor.d')/APPARMOR_PROFILE
    target.write_text(source.read_text());target.chmod(0o644)
    run(['apparmor_parser','-r','-W',str(target)],stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    profiles=Path('/sys/kernel/security/apparmor/profiles').read_text().splitlines()
    if APPARMOR_PROFILE+' (enforce)' not in profiles:raise RuntimeError('Dedicated AppArmor profile is not enforcing')


def container_start():
    require_bootstrap()
    load_apparmor()
    exists=subprocess.run(['podman','container','exists',CONTAINER]).returncode==0
    if not exists:
        command=['podman','create','--name',CONTAINER,'--network','none','--label','swgxr.remote='+MARKER,
            '--security-opt','no-new-privileges','--security-opt','apparmor='+APPARMOR_PROFILE,'--pids-limit','512']
        for target,source in expected_mounts().items():
            command += ['--volume',str(source)+':'+target+(':ro' if source.is_file() else ':rw')]
        command += [IMAGE,'python3','/workspace/tools/deploy/runtime.py','idle'];run(command,stdout=subprocess.DEVNULL)
    data=inspect_container()
    if data['State']['Running']: raise RuntimeError('Container already active outside this supervisor')
    os.execvp('podman',['podman','start','--attach','--sig-proxy=false',CONTAINER])


def inside(action):
    require_bootstrap();inspect_container()
    os.execvp('podman',['podman','exec',CONTAINER,'python3','/workspace/tools/deploy/runtime.py',action])


def mysql(sql):
    return run(['mariadb','--socket='+str(STATE/'mysql.sock'),'--batch','--skip-column-names'],input=sql,text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE).stdout


def mysql_ready():
    return subprocess.run(['mariadb-admin','--socket='+str(STATE/'mysql.sock'),'ping'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode==0


def child_db():
    require_bootstrap()
    datadir=REMOTE/'mysql'
    if not (datadir/'mysql').is_dir():
        with (REMOTE/'mysql-init.log').open('ab') as log:
            run(['mariadb-install-db','--user=root','--auth-root-authentication-method=socket','--datadir='+str(datadir)],stdout=log,stderr=log)
    if mysql_ready(): raise RuntimeError('MariaDB already running outside this supervisor')
    stopping=False
    def stop(*_):
        nonlocal stopping
        stopping=True
        subprocess.run(['mariadb-admin','--socket='+str(STATE/'mysql.sock'),'shutdown'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=120)
    signal.signal(signal.SIGTERM,stop);signal.signal(signal.SIGINT,stop)
    with (REMOTE/'mysql-console.log').open('ab') as log:
        process=subprocess.Popen(['mariadbd','--user=root','--datadir='+str(datadir),'--socket='+str(STATE/'mysql.sock'),
            '--pid-file='+str(REMOTE/'mysql.pid'),'--bind-address=127.0.0.1','--log-error='+str(REMOTE/'mysql.log')],stdout=log,stderr=log)
        try:
            end=time.monotonic()+180
            while not mysql_ready():
                if process.poll() is not None or time.monotonic()>end: raise RuntimeError('MariaDB startup failed; inspect private runtime log')
                time.sleep(.5)
            if not (REMOTE/'schema-ready').exists():
                schema=(REMOTE/'schema.sql').read_text();validate_schema(schema)
                # No Core3 can run until this marker is written; interrupted first import may retry.
                mysql(schema)
                password=(REMOTE/'db-password').read_text().strip()
                if not re.fullmatch(r'[0-9a-f]{64}',password): raise RuntimeError('Invalid DB credential')
                for host in ('localhost','127.0.0.1'):
                    mysql("CREATE USER IF NOT EXISTS 'swgemu'@'"+host+"' IDENTIFIED BY '"+password+"';\nALTER USER 'swgemu'@'"+host+"' IDENTIFIED BY '"+password+"';\nGRANT ALL PRIVILEGES ON swgemu.* TO 'swgemu'@'"+host+"';\n")
                if mysql('SELECT schema_version FROM swgemu.db_metadata;').strip()!='1008': raise RuntimeError('Unexpected schema version')
                private_write(REMOTE/'schema-ready','1008\n')
            print('Private MariaDB schema ready',flush=True)
            result=process.wait()
            # ExecStop uses a separate mariadb-admin process; its clean shutdown
            # returns zero without invoking this supervisor's signal handler.
            return result
        finally:
            if process.poll() is None:
                stop();process.wait(timeout=120)


def core_pid():
    try:
        pid=int((STATE/'core3.pid').read_text())
        if Path('/proc',str(pid),'comm').read_text().strip()=='core3': return pid
    except (OSError,ValueError): pass
    return None


def child_stop_core():
    pid=core_pid()
    if pid is None: return
    fifo=STATE/'core3-console'
    if not stat.S_ISFIFO(fifo.stat().st_mode): raise RuntimeError('Core3 console is not a FIFO')
    fd=os.open(fifo,os.O_WRONLY|os.O_NONBLOCK)
    try: os.write(fd,b'exit\n')
    finally: os.close(fd)
    end=time.monotonic()+210
    while core_pid()==pid:
        if time.monotonic()>end: raise RuntimeError('Core3 graceful save timeout; refusing silent forced shutdown')
        time.sleep(.5)


LOG_LIMIT = 32*1024*1024

def rotate_path(path, limit=LOG_LIMIT):
    if not path.is_file() or path.is_symlink() or path.stat().st_size<=limit:return
    old=path.with_name(path.name+'.1')
    # Preserve bounded recent evidence, never copy a potentially multi-GB log.
    with path.open('rb') as source:
        source.seek(max(0,path.stat().st_size-limit))
        data=source.read(limit)
    with old.open('wb') as output:output.write(data)
    old.chmod(0o600)
    with path.open('r+b') as output:output.truncate(0)


def rotate_logs():
    require_bootstrap()
    for path in (REMOTE/'logs').rglob('*.log'):
        if 'zArchive' not in path.parts:rotate_path(path)
    for path in REMOTE.glob('*.log'):rotate_path(path)
    archives=sorted((REMOTE/'logs/zArchive').glob('*.log'),key=lambda p:p.stat().st_mtime,reverse=True)
    retained=0
    for index,path in enumerate(archives):
        if path.is_symlink():continue
        size=path.stat().st_size
        if index>=64 or retained+size>128*1024*1024:path.unlink()
        else:retained+=size


def pump_console(pipe, path):
    with path.open('ab',buffering=0) as output:
        while True:
            chunk=pipe.read1(65536)
            if not chunk:break
            output.write(chunk)
            if output.tell()>LOG_LIMIT:rotate_path(path)
    pipe.close()


def child_core():
    require_bootstrap()
    if not (REMOTE/'schema-ready').exists() or not mysql_ready(): raise RuntimeError('Private database not ready')
    if core_pid() is not None: raise RuntimeError('Core3 already running outside this supervisor')
    fifo=STATE/'core3-console'
    if not fifo.exists(): os.mkfifo(fifo,0o600)
    if not stat.S_ISFIFO(fifo.stat().st_mode): raise RuntimeError('Core3 console is not a FIFO')
    fd=os.open(fifo,os.O_RDWR)
    stopped=False
    def stop(*_):
        nonlocal stopped
        if not stopped: os.write(fd,b'exit\n');stopped=True
    signal.signal(signal.SIGTERM,stop);signal.signal(signal.SIGINT,stop)
    log=STATE/'core3-console.log'
    if log.exists():
        with log.open('rb') as previous:
            previous.seek(max(0,log.stat().st_size-LOG_LIMIT))
            (STATE/'core3-console.previous.log').write_bytes(previous.read(LOG_LIMIT))
    log.write_bytes(b'')
    try:
        process=subprocess.Popen(['./core3'],cwd=BIN,stdin=fd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
        pump=threading.Thread(target=pump_console,args=(process.stdout,log),daemon=True);pump.start()
        private_write(STATE/'core3.pid',str(process.pid)+'\n')
        result=process.wait();pump.join(timeout=10)
        return result
    finally:
        os.close(fd)
        (STATE/'core3.pid').unlink(missing_ok=True)


def wait_ready(kind):
    end=time.monotonic()+600
    while time.monotonic()<end:
        if kind=='container':
            try:
                if inspect_container()['State']['Running']: return
            except (subprocess.CalledProcessError,RuntimeError): pass
        elif kind=='db':
            if (REMOTE/'schema-ready').exists() and subprocess.run(['podman','exec',CONTAINER,'mariadb-admin','--socket=/workspace/runtime/server/mysql.sock','ping'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode==0:return
        elif kind=='core':
            try:
                if (STATE/'core3-console.log').stat().st_mtime_ns>=int((REMOTE/'core-start-requested').read_text()) and '[Core] initialized' in (STATE/'core3-console.log').read_text(errors='replace'):return
            except OSError:pass
        time.sleep(1)
    raise RuntimeError(kind+' readiness timeout; inspect runtime logs')


def install_units():
    require_bootstrap()
    if any(c in str(ROOT) for c in '\n %'):raise RuntimeError('Unsupported systemd workspace path')
    auth_directory=ROOT/'runtime/auth'
    auth_directory.mkdir(parents=True,exist_ok=True,mode=0o700)
    gateway_user=pwd.getpwnam('blux')
    os.chown(auth_directory,gateway_user.pw_uid,gateway_user.pw_gid)
    auth_directory.chmod(0o700)
    voice_directory=ROOT/'runtime/voice'
    voice_directory.mkdir(parents=True,exist_ok=True,mode=0o2750)
    # Root adapter publishes0640 files; inherited blux group gives relay read access.
    os.chown(voice_directory,0,gateway_user.pw_gid)
    voice_directory.chmod(0o2750)
    voice_secret=REMOTE/'voice.secret'
    if not voice_secret.exists():
        descriptor=os.open(voice_secret,os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600)
        with os.fdopen(descriptor,'wb') as output:output.write(secrets.token_bytes(32))
    os.chown(voice_secret,gateway_user.pw_uid,gateway_user.pw_gid)
    voice_secret.chmod(0o600)
    gateway_config=REMOTE/'gateway.json'
    if gateway_config.exists():
        config=json.loads(gateway_config.read_text())
        config.setdefault('voice_secret',str(voice_secret))
        config.setdefault('voice_state',str(voice_directory/'state.json'))
        private_write(gateway_config,json.dumps(config,indent=2)+'\n')
        os.chown(gateway_config,gateway_user.pw_uid,gateway_user.pw_gid)
    source=ROOT/'tools/deploy/systemd'
    for path in source.glob('*.in'):
        target=Path('/etc/systemd/system')/path.stem
        target.write_text(path.read_text().replace('@ROOT@',str(ROOT)))
        target.chmod(0o644)
    run(['systemctl','daemon-reload'])
    print('Units installed. Explicit start: systemctl enable --now swgxr.target')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action',choices=['bootstrap','install-units','container-start','container-stop','run-db','run-core','stop-core','stop-db','child-db','child-core','child-stop-core','ready-container','ready-db','ready-core','rotate-logs','child-stop-db','child-check-stopped','idle','prepare-core'])
    parser.add_argument('--confirm-fresh-remote',action='store_true')
    args=parser.parse_args()
    if os.geteuid()!=0:raise RuntimeError('Rootful remote runtime requires administrator execution')
    os.umask(0o077)
    action=args.action
    if action=='idle':
        # Namespace PID 1 ignores default TERM; explicitly exit after services stop.
        signal.signal(signal.SIGTERM,lambda *_: sys.exit(0))
        signal.signal(signal.SIGINT,lambda *_: sys.exit(0))
        signal.signal(signal.SIGCHLD,signal.SIG_IGN)
        while True:signal.pause()
    if action=='bootstrap':bootstrap(args.confirm_fresh_remote)
    elif action=='prepare-core':
        require_bootstrap()
        catalogs = vehicle_catalog_status(ROOT)
        if not catalogs['passed']: raise RuntimeError('; '.join(catalogs['errors']))
        private_write(REMOTE/'core-start-requested',str(time.time_ns()))
    elif action=='install-units':install_units()
    elif action=='container-start':container_start()
    elif action=='container-stop':
        inspect_container();podman('exec',CONTAINER,'python3','/workspace/tools/deploy/runtime.py','child-check-stopped');podman('stop','--time','30',CONTAINER)
    elif action in ('run-db','run-core','stop-core'):inside({'run-db':'child-db','run-core':'child-core','stop-core':'child-stop-core'}[action])
    elif action=='stop-db':inside('child-stop-db')
    elif action.startswith('ready-'):wait_ready(action[6:])
    elif action=='child-db':return child_db()
    elif action=='child-core':return child_core()
    elif action=='child-stop-core':child_stop_core()
    elif action=='child-stop-db':
        if core_pid() is not None:raise RuntimeError('Core3 has not exited; refusing database shutdown')
        run(['mariadb-admin','--socket='+str(STATE/'mysql.sock'),'shutdown'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    elif action=='child-check-stopped':
        if core_pid() is not None or mysql_ready():raise RuntimeError('Native services still active; refusing container shutdown')
    elif action=='rotate-logs':rotate_logs()
    return 0

if __name__=='__main__':
    try:sys.exit(main())
    except (RuntimeError,ValueError,OSError,subprocess.SubprocessError) as error:
        # Subprocess diagnostics may contain SQL credentials; never print their command/input.
        print('Remote runtime action failed: '+(str(error) if isinstance(error,(RuntimeError,ValueError)) else type(error).__name__),file=sys.stderr)
        sys.exit(1)
