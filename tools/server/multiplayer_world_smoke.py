#!/usr/bin/env python3
"""Actual native peer visibility/appearance/cells, using existing local fixtures.

No skill/item grants; restore saved source locations on exit. No headset test.
"""
import json, math, secrets
from services_smoke import ROOT, req, redact


def main():
    fixtures = [json.loads((ROOT/'runtime/server'/name).read_text()) for name in
                ('services-fixture.json', 'gathering-fixture.json')]
    assert all(f['account'].startswith('invtest') for f in fixtures)
    checks, sessions, saved, responses, pending_tools = [], {}, {}, [], []
    report = {'passed': False, 'native_execution': True, 'checks': checks, 'responses': responses}
    def check(value, label):
        checks.append({'passed': bool(value), 'label': label})
        print(label, bool(value), flush=True)
        assert value, label
    def call(f, path, **fields):
        out = req(path, dict(account=f['account'], character_id=f['id'], **fields))
        responses.append({'path': path, 'response': redact(out)})
        assert not out.get('http_error'), out
        return out
    def update(f, **pose):
        return call(f, '/session/update', session_id=sessions[f['id']], ready=True, **pose)
    outside = dict(position=[3527, 5, -4810], building_id='0', cell_index=0, heading_radians=.5)
    def sync(f, sequence, **pose):
        return call(f, '/session/sync', session_id=sessions[f['id']], sequence=sequence,
                    tracking={}, **pose)
    try:
        for f in fixtures:
            saved[f['id']] = call(f, '/enter')['source_location']
            started = call(f, '/session/start', **outside)
            sessions[f['id']] = started['session_id']
            update(f, **outside)
        a, b = fixtures
        first = update(a, **outside)['snapshot']['world']
        second = update(b, **outside)['snapshot']['world']
        check(any(p['id'] == b['id'] for p in first['players']) and any(p['id'] == a['id'] for p in second['players']), 'Two real native characters mutually visible outdoors')
        peer = next(p for p in first['players'] if p['id'] == b['id'])
        check(peer['kind'] == 'player' and peer['appearance']['template'].startswith('object/creature/player/') and isinstance(peer['appearance']['customization'], dict), 'Original peer body template/customization resolved')
        check(peer['appearance']['equipment_complete'] and bool(peer['appearance']['equipment']) and all('equipped_slots' in i and 'shared_template' in i for i in peer['appearance']['equipment']), 'Original equipped visual items resolved without inventory contents')
        check(all(k not in peer for k in ('inventory', 'credits', 'skills', 'account', 'session_id')), 'Public native peers exclude private gameplay/account fields')
        check(peer['posture'] in range(15) and isinstance(peer['dead'], bool) and isinstance(peer['in_combat'], bool) and len(peer['ham']) == 3, 'Native posture/life/combat/HAM supplied')
        check(all(math.isfinite(x) for x in peer['position']) and math.isfinite(peer['heading_radians']) and peer['cell_index'] == 0, 'Source world transform and exact source cell supplied')
        sync(b, 1, **outside)
        view = sync(a, 1, **outside)
        check(any(p['id'] == b['id'] for p in view['poses']) and view['world']['source_kind'] == 'core3_world', 'Cheap sync binds peer presentation to native visible IDs')
        inventory = call(b, '/inventory/status', live_session_id=sessions[b['id']])
        tool = next(i for i in inventory['items'] if i.get('tool_kind') == 'survey')
        state = call(b, '/gathering/status', tool_id=tool['id'], **outside)
        resource = state['resources'][0]
        survey = call(b, '/gathering/survey', tool_id=tool['id'], resource_id=resource['id'], request_id='world_'+secrets.token_hex(8), **outside)
        check(survey['mutation']['success'], 'Actual native survey operation committed')
        view = sync(a, 2, **outside)
        check(any(e['actor_id'] == b['id'] and e['kind'] == 'survey' for e in view['events']), 'Nearby peer receives authoritative native survey cue')
        deployment = call(b, '/gathering/deploy', tool_id=tool['id'], resource_id=resource['id'], request_id='deploy_'+secrets.token_hex(8), **outside)
        deployment_id = deployment['mutation']['deployment_id']
        pending_tools.append((b, deployment_id))
        world = update(a, **outside)['snapshot']['world']
        public_tool = next(d for d in world['deployments'] if d['id'] == deployment_id)
        check(public_tool['owner_id'] == b['id'] and public_tool['tool_id'] == tool['id'] and public_tool['template'] == tool['template'] and public_tool['position'] == outside['position'], 'Peer sees original native escrowed sampling tool and ground anchor')
        check(all(k not in public_tool for k in ('quantity', 'escrow_id', 'inventory', 'buffer')), 'Public sampling anchor excludes private resource buffers and escrow')
        call(b, '/gathering/collect', deployment_id=deployment_id, request_id='collect_'+secrets.token_hex(8), **outside)
        pending_tools.clear()
        world = update(a, **outside)['snapshot']['world']
        check(all(d['id'] != deployment_id for d in world['deployments']), 'Native tool pickup removes public anchor from next full world')
        terminal = next(t for t in json.loads((ROOT/'runtime/assets/services/catalog.json').read_text())['static_terminals'] if t['building_id'] != '0' and t['cell_index'] > 0)
        inside = {k: terminal[k] for k in ('position', 'building_id', 'cell_index')}
        inside['heading_radians'] = 1.25
        update(b, **inside)
        isolated = update(a, **outside)['snapshot']['world']
        check(all(p['id'] != b['id'] for p in isolated['players']), 'Different original cell excludes peer')
        update(a, **inside)
        room = update(b, **inside)['snapshot']['world']
        check(any(p['id'] == a['id'] and p['cell_index'] == inside['cell_index'] for p in room['players']), 'Same original interior cell restores native visibility')
        report['passed'] = True
    finally:
        for f, deployment_id in pending_tools:
            try:
                call(f, '/gathering/collect', deployment_id=deployment_id, request_id='cleanup_'+secrets.token_hex(8), **outside)
            except Exception as error:
                report.setdefault('cleanup_errors', []).append(str(error))
                report['passed'] = False
        for f in fixtures:
            if f['id'] not in sessions:
                continue
            loc = saved[f['id']]
            try:
                call(f, '/session/logout', live_session_id=sessions[f['id']], request_id='restore_'+secrets.token_hex(8), **{k: loc[k] for k in ('position', 'building_id', 'cell_index', 'heading_radians')})
            except Exception as error:
                report.setdefault('cleanup_errors', []).append(str(error))
                report['passed'] = False
        (ROOT/'runtime/evidence/multiplayer-native-world.json').write_text(json.dumps(report, indent=2))
    print(json.dumps({'passed': report['passed'], 'checks': len(checks)}), flush=True)
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
