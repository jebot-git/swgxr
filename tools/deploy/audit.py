#!/usr/bin/env python3
"""Read-only runtime evidence. Run as VPS administrator; emits no credentials."""
import os
import hashlib
import json
import re
import subprocess
from datetime import datetime, timezone
from pathlib import Path
try:
    from .runtime import vehicle_catalog_status
except ImportError:
    from runtime import vehicle_catalog_status

ROOT = Path(__file__).resolve().parents[2]


def command(*args):
    return subprocess.check_output(args, text=True).strip()


def main():
    units = ['swgxr.target'] + ['swgxr-' + name + '.service' for name in
                              ('container', 'db', 'core3', 'adapter', 'gateway', 'voice')]
    states = {unit: subprocess.run(['systemctl', 'is-active', unit],
              capture_output=True, text=True).stdout.strip() for unit in units}
    data = json.loads(command('podman', 'inspect', 'swgxr-core3-build'))[0]
    memory = {}
    for line in Path('/proc/meminfo').read_text().splitlines():
        key, value = line.split(':', 1)
        if key in ('MemTotal', 'MemAvailable', 'SwapTotal', 'SwapFree'):
            memory[key + '_KiB'] = int(value.split()[0])
    processes = []
    for path in Path('/proc').glob('[0-9]*'):
        try:
            if (path/'comm').read_text().strip() not in ('core3','corecu'): continue
            with (path/'exe').open('rb') as stream:
                digest = hashlib.file_digest(stream, 'sha256').hexdigest()
            status = (path/'status').read_text()
            processes.append({'pid': int(path.name), 'sha256': digest,
                'memory_KiB': {key: int(re.search(r'^'+key+r':\s+(\d+)', status, re.M)[1])
                               for key in ('VmRSS', 'VmSwap')}})
        except (FileNotFoundError, ProcessLookupError): pass
    sql = command('podman', 'exec', 'swgxr-core3-build', 'mariadb',
                  '--socket=/workspace/runtime/server/mysql.sock', '-N', '-e',
                  'SELECT COUNT(*) FROM swgemu.accounts; SELECT COUNT(*) FROM swgemu.characters; '
                  'SELECT schema_version FROM swgemu.db_metadata;').splitlines()
    resources = (ROOT/'runtime/remote/resource_manager.lua').read_text()
    config = (ROOT/'runtime/remote/config-local.lua').read_text()
    report = {'captured_utc': datetime.now(timezone.utc).isoformat(), 'services': states,
              'enabled': command('systemctl', 'is-enabled', 'swgxr.target'),
              'image_id': data['Image'], 'network_mode': data['HostConfig']['NetworkMode'],
              'published_ports': data['HostConfig'].get('PortBindings'),
              'apparmor': data['AppArmorProfile'], 'container_command': data['Config']['Cmd'],
              'memory': memory, 'native_processes': processes,
              'database': dict(zip(('accounts', 'characters', 'schema_version'), map(int, sql))),
              'zones': re.search(r'Core3.ZonesEnabled\s*=\s*([^\n]+)', config)[1],
              'space_zones': re.search(r'Core3.SpaceZonesEnabled\s*=\s*([^\n]+)', config)[1],
              'resource_zones': re.search(r'^activeZones\s*=\s*([^\n]+)', resources, re.M)[1],
              'listeners': command('ss', '-lntu')}
    from tools.deploy.capacity import load as load_capacity, host_readiness, configuration_status
    capacity=load_capacity(ROOT/'runtime/remote')
    report['capacity_configuration']=configuration_status(ROOT/'runtime/remote')
    report['capacity_profile']=capacity
    report['host_capacity']=host_readiness(os.cpu_count() or 1,memory.get('MemTotal_KiB',0),capacity) if capacity else None
    report['container_pids_limit']=data['HostConfig'].get('PidsLimit')
    report['vehicle_catalog'] = vehicle_catalog_status(ROOT)
    report['passed'] = (report['vehicle_catalog']['passed'] and all(value == 'active' for value in states.values()) and len(processes) == 1
                        and report['network_mode'] == 'none' and not report['published_ports']
                        and report['apparmor'] == 'swgxr-core3'
                        and report['database']['schema_version'] == 1008)
    if capacity:report['passed'] &= report['capacity_configuration']['passed'] and report['host_capacity']['passed'] and report['container_pids_limit']>=capacity['container_pids']
    print(json.dumps(report, indent=2))
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
