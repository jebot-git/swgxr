#!/usr/bin/env python3
"""Disposable local Core3 survey uniqueness, logout and capped-output proof.

The near-full case seeds controlled screenplay checkpoints; it is not a claim
that a real resource was sampled for days. No production or headset connection.
"""
import argparse
import json
import secrets
import subprocess
import time
from pathlib import Path
from equipment_smoke import console
from services_smoke import req, ROOT, redact


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--restart', action='store_true', help='Also gracefully restart the isolated local Core3 container')
    args = parser.parse_args()
    fixture = {'account': 'invtestsurvey' + secrets.token_hex(4),
               'name': 'Ivtest' + ''.join(secrets.choice('aeilnorstu') for _ in range(9))}
    created = req('/characters', dict(fixture, species='human', profession='crafting_artisan'))
    fixture['id'] = created['character']['id']
    base = dict(account=fixture['account'], character_id=fixture['id'])
    evidence = ROOT / 'runtime/evidence/survey-limits-native.json'
    report = dict(passed=False, fixture=fixture, checks=[], responses=[])
    screenplay = ROOT / 'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/tests/tests.lua'
    original = screenplay.read_bytes()
    session = ''
    pose = {}

    def check(ok, label):
        report['checks'].append(dict(passed=bool(ok), label=label))
        print(label, bool(ok), flush=True)
        assert ok, label

    def call(path, **values):
        response = req(path, dict(base, **values))
        report['responses'].append(dict(path=path, response=redact(response)))
        return response

    def gathering(action, **values):
        return call('/gathering/' + action, request_id='survey_' + secrets.token_hex(10), **values)

    def start():
        nonlocal session, pose
        location = call('/enter')['source_location']
        pose = {key: location[key] for key in ('position', 'building_id', 'cell_index')}
        started = call('/session/start', **pose)
        session = started['session_id']
        call('/session/update', session_id=session, ready=True, **pose)

    def logout():
        nonlocal session
        call('/session/logout', live_session_id=session, request_id='logout_' + secrets.token_hex(10),
             heading_radians=0, **pose)
        session = ''

    def lua(name):
        console('runLuaFunction Tests:swgxrSurveyLimit' + name)
        time.sleep(.5)

    try:
        start()
        added = f'''
function Tests:swgxrSurveyLimitGrant()
 local p=getSceneObject({fixture['id']})
 if p==nil or CreatureObject(p):getFirstName()~="{fixture['name']}" then return end
 awardSkill(p,"crafting_artisan_survey_04")
 local inv=SceneObject(p):getSlottedObject("inventory")
 giveItem(inv,"object/tangible/survey_tool/survey_tool_mineral.iff",-1)
 giveItem(inv,"object/tangible/survey_tool/survey_tool_mineral.iff",-1)
 giveItem(inv,"object/tangible/survey_tool/survey_tool_gas.iff",-1)
end
function Tests:swgxrSurveyLimitNearFull()
 local p=getSceneObject({fixture['id']})
 if p==nil or CreatureObject(p):getFirstName()~="{fixture['name']}" then return end
 local s=readScreenPlayData(p,"swgxr_gathering","state")
 s=string.gsub(s,'"quantity":%d+','"quantity":99999')
 s=string.gsub(s,'"density":[%d%.eE%+%-]+','"density":1.0')
 s=string.gsub(s,'"surveying_skill":%d+','"surveying_skill":100')
 s=string.gsub(s,'"next_sample_at_unix":%d+','"next_sample_at_unix":'..(os.time()-100))
 writeScreenPlayData(p,"swgxr_gathering","state",s)
end
'''
        screenplay.write_bytes(original + added.encode())
        console('reloadscreenplays'); time.sleep(.5); lua('Grant')
        inventory = call('/inventory/status')
        minerals = [i for i in inventory['items'] if i['template'].endswith('/survey_tool_mineral.iff')]
        gas = next(i for i in inventory['items'] if i['template'].endswith('/survey_tool_gas.iff'))
        def resource(tool):
            return gathering('status', tool_id=tool['id'])['resources'][0]['id']
        mineral_resource, gas_resource = resource(minerals[0]), resource(gas)
        def deploy(tool, resource_id):
            return gathering('deploy', tool_id=tool['id'], resource_id=resource_id, **pose)
        first = deploy(minerals[0], mineral_resource)
        check(first.get('mutation', {}).get('success'), 'First survey type deploys in real native escrow')
        denied = deploy(minerals[1], mineral_resource)
        check('already deployed' in denied.get('error', ''), 'Second owned item of same native type is rejected')
        inventory = call('/inventory/status')
        check(minerals[1]['id'] in {i['id'] for i in inventory['items']}, 'Rejected duplicate stays in inventory')
        other = deploy(gas, gas_resource)
        check(other.get('mutation', {}).get('success') and len(other['state']['deployments']) == 2,
              'Different survey types coexist')
        before = {d['id']: d for d in other['state']['deployments']}
        logout()
        if args.restart:
            print('Checking graceful local Core3 restart with deployed tools', flush=True)
            subprocess.run([str(ROOT / 'tools/server/stop-core3.sh')], check=True)
            # Native zone shutdown can finish before swapped-out BDB pages have
            # finished closing; wait for process exit before starting a new writer.
            deadline = time.monotonic() + 240
            while True:
                processes = subprocess.check_output(['podman', 'exec', 'swgxr-core3-build',
                                                      'ps', '-eo', 'stat,comm'], text=True)
                if not any(row.split()[-1] == 'core3' and not row.startswith('Z')
                           for row in processes.splitlines() if row.split()): break
                if time.monotonic() > deadline: raise RuntimeError('Graceful local shutdown timed out')
                time.sleep(.5)
            with (ROOT / 'runtime/server/survey-smoke-restart.log').open('w') as log:
                subprocess.run([str(ROOT / 'tools/server/start-core3.sh')], check=True, stdout=log, stderr=log)
            deadline = time.monotonic() + 90
            while req('/health').get('status') != 'ready':
                if time.monotonic() > deadline: raise RuntimeError('Local native readiness timed out')
                time.sleep(1)
        else:
            time.sleep(4)
        start()
        after = gathering('status')
        check({d['id'] for d in after['deployments']} == set(before),
              'Native deployments survive logout' + (' and graceful server restart' if args.restart else '') + ' and new login')
        check(all(d['position'] == before[d['id']]['position'] and d['resource_id'] == before[d['id']]['resource_id']
                  and d['tool_id'] == before[d['id']]['tool_id'] for d in after['deployments']),
              'Saved tool identities, resource anchors and placement coordinates are retained')
        check(all(d['cycles'] > before[d['id']]['cycles'] for d in after['deployments']),
              'Elapsed sampling cycles accrue while client session is offline')
        lua('NearFull')
        full = gathering('status')
        check(all(d['quantity'] == 100000 and d['state'] == 'full' and not d['settlement_pending']
                  and d['last_sample_units'] == 1 for d in full['deployments']),
              'Controlled near-full native buffers accept exactly one final unit')
        check(all(d['capacity'] == 100000 for d in full['deployments']) and
              full['limits']['max_deployments_per_tool_type'] == 1, 'Authoritative capacity and type limits advertised')
        check('already deployed' in deploy(minerals[1], mineral_resource).get('error', ''),
              'Full deployment continues reserving its type')
        again = gathering('status')
        check([(d['quantity'], d['cycles'], d['awarded_xp']) for d in again['deployments']] ==
              [(d['quantity'], d['cycles'], d['awarded_xp']) for d in full['deployments']],
              'Full tools grant no further output, cycles or XP')
        for dep in full['deployments']:
            recovered = gathering('collect', deployment_id=dep['id'], position=dep['position'])
            check(recovered.get('mutation', {}).get('quantity') == 100000,
                  'Full stack and original tool recover through native inventory transaction')
        replaced = deploy(minerals[1], mineral_resource)
        check(replaced.get('mutation', {}).get('success'), 'Recovery releases the type for a different owned tool')
        dep = replaced['state']['deployments'][0]
        check(gathering('collect', deployment_id=dep['id'], position=dep['position']).get('mutation', {}).get('success'),
              'Disposable test leaves no deployed tools')
        report['passed'] = True
    finally:
        screenplay.write_bytes(original)
        console('reloadscreenplays')
        if session: logout()
        evidence.parent.mkdir(parents=True, exist_ok=True)
        evidence.write_text(json.dumps(redact(report), indent=2) + '\n')
    print(json.dumps(dict(passed=report['passed'], checks=len(report['checks']))))


if __name__ == '__main__':
    main()
