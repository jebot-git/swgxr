#!/usr/bin/env python3
"""Stage a reviewed target profile without changing or restarting the live realm.

Without --source, produces a public profile and the settings to review. On the
VPS, pass its private runtime/remote directory to stage complete overlays while
preserving the existing DB credential. Never use bootstrap to upgrade a realm.
"""
import argparse
import json
import re
from pathlib import Path
try:
    from .runtime import ROOT, private_write, render_config, render_resources
    from .capacity import PROFILE, PROFILES, validate
except ImportError:
    from runtime import ROOT, private_write, render_config, render_resources
    from capacity import PROFILE, PROFILES, validate


def prepare(destination, source=None, profile=PROFILE):
    profile=validate(profile)
    if destination.exists(): raise ValueError('Use a new staging directory.')
    config = resources = None
    if source is not None:
        config = (source/'config-local.lua').read_text()
        resources = (source/'resource_manager.lua').read_text()
        zones=re.search(r'^Core3\.ZonesEnabled\s*=\s*\{([^}]+)\}',config,re.M)
        if profile['planets']==['tatooine'] and (not zones or re.findall(r'"([^"]+)"',zones[1]) != ['tatooine']):
            raise ValueError('This live-test profile requires an already Tatooine-only realm.')
        password = re.search(r'^Core3\.DBPass\s*=\s*"([0-9a-f]{64})"\s*$',config,re.M)
        if not password: raise ValueError('Expected the existing generated realm DB credential.')
        config = render_config(config,password[1],profile['planets'],capacity=profile)
        resources = render_resources(resources,profile['planets'])
    destination.mkdir(parents=True, mode=0o700)
    destination.chmod(0o700)
    private_write(destination/'capacity.json',json.dumps(profile,indent=2)+'\n')
    private_write(destination/'capacity.env','SWGXR_MAX_NATIVE_SESSIONS=0\nSWGXR_MAX_VOICE_CLIENTS=0\nSWGXR_HTTP_CONNECTIONS='+str(profile['gateway_connections'])+'\n')
    settings = {'ZoneProcessingThreads':profile['zone_threads'],'MaxNavMeshJobs':profile['navmesh_jobs'],'LoginAllowedConnections':profile['native_connections'],'ZoneAllowedConnections':profile['native_connections']}
    private_write(destination/'review-settings.lua','-- Review only; apply through the private staged config.\n'+''.join(f'Core3.{key} = {value}\n' for key,value in settings.items()))
    if config is not None:
        private_write(destination/'config-local.lua',config)
        private_write(destination/'resource_manager.lua',resources)
    report = {'profile':profile['name'],'target_players':profile['target_players'],'session_limit':None,'planets':profile['planets'],
              'private_overlays_ready':config is not None,'credentials_preserved':config is not None,
              'live_configuration_changed':False,'database_changed':False,'deployed':False,
              'requires':['fresh native build receipt',f"{profile['minimum_vcpus']} vCPUs / at least {profile['minimum_ram_gib']} GiB actual RAM",'graceful stop and SQL/BDB/auth/config backup',
                          'stage with --source on VPS; copy capacity.json, capacity.env and private overlays',
                          'recreate stopped container for PID limit; preserve mounted databases',
                          'install updated units, start services, audit and 32-client load test']}
    private_write(destination/'preparation.json',json.dumps(report,indent=2)+'\n')
    return report


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('destination',type=Path)
    parser.add_argument('--source',type=Path,help='Existing private remote configuration directory')
    parser.add_argument('--profile',choices=PROFILES,default=PROFILE['name'])
    args=parser.parse_args()
    destination=args.destination.resolve()
    if not destination.is_relative_to(ROOT/'runtime/deploy'):raise SystemExit('Stage only under ignored runtime/deploy.')
    print(json.dumps(prepare(destination,args.source,PROFILES[args.profile])))

if __name__=='__main__':main()
