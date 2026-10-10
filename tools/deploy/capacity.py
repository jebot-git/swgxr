"""Reviewed deployment budgets; target populations are not admission limits."""
import json
import re
from pathlib import Path
from server.planets import SUPPORTED_PLANETS
from server.jtl_catalog import SHIP_TEMPLATES
from server.jtl_protocol import SPACE_ZONES

PROFILE = {
    'name': 'corecu-tatooine-32', 'target_players': 32, 'session_limit': 0,
    'planets': ['tatooine'], 'space_enabled': False,
    'zone_threads': 4, 'navmesh_jobs': 1, 'native_connections': 64,
    'container_pids': 2048, 'db_buffer_pool_mib': 512, 'db_connections': 64,
    'gateway_connections': 128, 'minimum_vcpus': 8,
    'minimum_ram_gib': 14, 'capacity_load_validated': False,
}
ALL_PLANETS_PROFILE = dict(PROFILE, name='corecu-all-planets-12cpu-24gb',
    planets=list(SUPPORTED_PLANETS), zone_threads=6, navmesh_jobs=2,
    db_buffer_pool_mib=1024, minimum_vcpus=12, minimum_ram_gib=22)
JTL_TEST_PROFILE = dict(ALL_PLANETS_PROFILE, name='corecu-all-planets-jtl-test-12cpu-24gb',
    space_enabled=True, space_zones=['space_tatooine'], tester_yachts=True,
    ship_templates=list(SHIP_TEMPLATES),
    space_combat_spawns=False, registration_enabled=True,
    registration_invites_required=False, registration_grants_client_access=True)
JTL_SECTORS_PROFILE = dict(JTL_TEST_PROFILE,
    name='corecu-original-jtl-sectors-12cpu-24gb',
    space_zones=list(SPACE_ZONES), space_combat_spawns=True)
PROFILES = {p['name']:p for p in (PROFILE, ALL_PLANETS_PROFILE, JTL_TEST_PROFILE, JTL_SECTORS_PROFILE)}


def validate(value):
    if not isinstance(value,dict) or value != PROFILES.get(value.get('name')):
        raise ValueError('Expected a reviewed CoreCU deployment profile.')
    return dict(value,planets=list(value['planets']))


def load(remote):
    path = Path(remote)/'capacity.json'
    return validate(json.loads(path.read_text())) if path.exists() else None


def host_readiness(cpus, memory_kib, profile=PROFILE):
    profile=validate(profile)
    # Allow advertised decimal RAM sizes; never count swap toward the floor.
    issues = []
    if cpus < profile['minimum_vcpus']: issues.append(f"At least {profile['minimum_vcpus']} vCPUs required by this profile.")
    if memory_kib < profile['minimum_ram_gib']*1024*1024: issues.append(f"At least {profile['minimum_ram_gib']} GiB actual RAM required; swap does not satisfy the RAM budget.")
    return {'passed': not issues, 'issues': issues, 'load_validated': False}


def configuration_status(remote):
    remote=Path(remote);profile=load(remote)
    if profile is None:return {'enabled':False,'passed':True,'issues':[]}
    issues=[]
    try:
        config=(remote/'config-local.lua').read_text()
        resources=(remote/'resource_manager.lua').read_text()
        env=(remote/'capacity.env').read_text()
        expected={'ZoneProcessingThreads':profile['zone_threads'],'MaxNavMeshJobs':profile['navmesh_jobs'],'LoginAllowedConnections':profile['native_connections'],'ZoneAllowedConnections':profile['native_connections']}
        for key,value in expected.items():
            if not re.search(r'^Core3\.'+key+r'\s*=\s*'+str(value)+r'\s*$',config,re.M):issues.append('Capacity overlay missing '+key)
        zones=re.findall(r'^Core3\.ZonesEnabled\s*=\s*\{([^}\n]*)\}\s*$',config,re.M)
        if len(zones)!=1 or re.findall(r'"([a-z0-9]+)"',zones[0])!=profile['planets']:issues.append('Enabled planets do not match the deployment profile.')
        space=re.findall(r'^Core3\.SpaceZonesEnabled\s*=\s*\{([^}\n]*)\}\s*$',config,re.M)
        if len(space)!=1 or re.findall(r'"([a-z0-9_]+)"',space[0])!=profile.get('space_zones',[]):issues.append('Space zones do not match the deployment profile.')
        if profile['space_enabled']:
            ships=re.findall(r'^Core3\.JTL\.SwgxrShipTemplates\s*=\s*\{([^}\n]*)\}\s*$',config,re.M)
            if len(ships)!=1 or re.findall(r'"([^"]+)"',ships[0])!=profile['ship_templates']:issues.append('Enabled ship templates do not match converted tester assets.')
            if not re.search(r'^Core3\.SWGXR\.RetailGroundOnly\s*=\s*false\s*$',config,re.M):issues.append('ShipManager initialization is still disabled by RetailGroundOnly.')
            for key in ('JTLEnabled','SwgxrTesterYachts','SwgxrDisableCombatSpawns'):
                value='false' if key=='SwgxrDisableCombatSpawns' and profile['space_combat_spawns'] else 'true'
                if not re.search(r'^Core3\.JTL\.'+key+r'\s*=\s*'+value+r'\s*$',config,re.M):issues.append('JtL tester configuration missing '+key)
        zones=re.findall(r'^activeZones\s*=\s*"([^"]*)"\s*$',resources,re.M)
        if zones!=[','.join(profile['planets'])]:issues.append('Resource planets do not match the deployment profile.')
        for name in ('SWGXR_MAX_NATIVE_SESSIONS','SWGXR_MAX_VOICE_CLIENTS'):
            if not re.search(r'^'+name+r'=0\s*$',env,re.M):issues.append('Uncapped test profile requires '+name+'=0.')
        if not re.search(r'^SWGXR_HTTP_CONNECTIONS='+str(profile['gateway_connections'])+r'\s*$',env,re.M):issues.append('Gateway request budget does not match the deployment profile.')
    except OSError:issues.append('Capacity profile overlays are incomplete.')
    return {'enabled':True,'passed':not issues,'issues':issues,'target_players':profile['target_players'],'session_limit':None,'planets':profile['planets']}
