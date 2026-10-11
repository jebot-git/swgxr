#!/usr/bin/env python3
"""Harvest through an owned live CoreCU session; disposable local fixture only."""
import argparse
import json
import secrets
import time
from pathlib import Path
import services_smoke as shared
from seed_bazaar import Native

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=18088)
    parser.add_argument('--fixture', type=Path, default=ROOT/'runtime/server/corpse-fixture.json')
    args = parser.parse_args()
    shared.BASE = f'http://127.0.0.1:{args.port}'
    fixture = json.loads(args.fixture.read_text())
    assert fixture['account'].startswith('invtest') and fixture['name'].startswith('Ivtest')
    base = dict(account=fixture['account'], character_id=fixture['id'])
    native = Native('swgxr-core3-build')
    checks = []
    report = dict(passed=False, native=True, headset_tested=False,
                  fixture_kind='controlled_native_dead_creature_live_owned_session', checks=checks)
    sid = ''

    def call(path, **fields):
        start = time.monotonic()
        result = shared.req(path, dict(base, **fields))
        assert not result.get('http_error'), result
        checks.append(dict(path=path, elapsed_ms=round((time.monotonic()-start)*1000),
                           mutation=result.get('mutation', {})))
        return result

    original = call('/enter')['source_location']['position']
    source = (ROOT/'tools/server/gathering_fixture.lua').read_text().replace('__FIXTURE_ID__',fixture['id'])
    source += f'''
function Tests:swgxrCorpsePlacement(mode)
 local p=getSceneObject({fixture['id']})
 if p==nil or CreatureObject(p):getFirstName()~="{fixture['name']}" then return "wrong_fixture" end
 CreatureObject(p):forcePeace()
 if mode=="restore" then SceneObject(p):teleport({original[0]},{original[1]},{original[2]},0)
 else SceneObject(p):teleport(3600,5,-4780,0) end
 return "placed"
end
'''
    try:
        with native.screenplay('swgxrGatheringFixture',source):
            try:
                native.call('swgxrCorpsePlacement:place')
                native.call('swgxrGatheringFixture:'+fixture['id']+':skills')
                pos = [3600,5,-4780]
                sid = call('/session/start',position=pos)['session_id']
                call('/session/update',session_id=sid,position=pos,ready=True)
                for kind in ('meat','hide','bone'):
                    native.call('swgxrGatheringFixture:'+fixture['id']+':corpse')
                    query = '?account='+fixture['account']+'&character_id='+fixture['id']+'&position=3600,5,-4780'
                    listing = shared.req('/gathering/corpses'+query)
                    assert not listing.get('http_error'),listing
                    corpse = max((row for row in listing['corpses'] if row['harvest_available']),key=lambda row:int(row['id']))
                    choice = next(row for row in corpse['resources'] if row['kind']==kind)
                    assert choice['available'],choice
                    fields = dict(position=pos,corpse_id=corpse['id'],request_id=secrets.token_hex(12),kind=kind)
                    result = call('/gathering/corpse/harvest',**fields)
                    assert result['mutation']['success'] and result['mutation']['quantity']==choice['quantity'],result
                    assert result['inventory']['source_kind']=='core3_inventory'
                    assert not result['corpse']['harvest_available']
                    replay = call('/gathering/corpse/harvest',**fields)
                    assert replay['mutation']['replayed']
                    result = call('/gathering/corpse/loot',**dict({k:v for k,v in fields.items() if k!='kind'},request_id=secrets.token_hex(12)))
                    # A request ID belongs to exactly one operation.
                    assert result['mutation']['success']
                    result = call('/session/update',session_id=sid,position=pos,ready=True)
                    assert result['session_live'],result
                    native.call('swgxrGatheringFixture:'+fixture['id']+':cleanup_corpse')
                report['passed'] = True
            finally:
                if sid:
                    call('/combat/session/stop',session_id=sid)
                native.call('swgxrGatheringFixture:'+fixture['id']+':cleanup_corpse')
                native.call('swgxrCorpsePlacement:restore')
    finally:
        output=ROOT/'runtime/evidence/harvest-junk-forage/corpse-live.json'
        output.parent.mkdir(parents=True,exist_ok=True)
        output.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report))


if __name__=='__main__':
    main()
