#!/usr/bin/env python3
"""Actual concurrent Core3 IPC/peer-lock proof on two existing local fixtures.

Calls the production native hub directly to exercise parallel commands without
HTTP's intentional global admission gate. No grants or remote host operations.
"""
import json
import math
import os
from pathlib import Path
import secrets
import statistics
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from server import adapter
from services_smoke import req


def main():
    fixtures=[json.loads((ROOT/'runtime/server'/name).read_text()) for name in ('services-fixture.json','gathering-fixture.json')]
    assert all(f['account'].startswith('invtest') for f in fixtures)
    states=[];checks=[];timings=[]
    evidence=ROOT/'runtime/evidence/multiplayer-native-concurrency.json'
    checkpoint=ROOT/'runtime/server/multiplayer-concurrency-recovery.json'
    report={'passed':False,'native_execution':True,'transport':'direct production native IPC hub; no HTTP gate','checks':checks,'cleanup':[]}
    def save():
        with open(os.open(checkpoint,os.O_WRONLY|os.O_CREAT|os.O_TRUNC,0o600),'w') as stream:json.dump(states,stream)
        checkpoint.chmod(0o600)
    def check(ok,label):
        checks.append({'passed':bool(ok),'label':label});assert ok,label
    pose=dict(position=[3527,5,-4810],building_id='0',cell_index=0,heading_radians=.5)
    def update(state,barrier=None):
        if barrier:barrier.wait(timeout=5)
        start=time.monotonic()
        result=adapter.gameplay_session(state['account'],dict(character_id=state['id'],session_id=state['session'],ready=True,**pose))
        timings.append(time.monotonic()-start)
        check(result.get('session_live') is True and result.get('session_id')==state['session'],'Original native owned session survives concurrent update')
        check(result['sequence']>state.get('sequence',0),'Native per-owner command sequence advances')
        state['sequence']=result['sequence']
        return result
    try:
        for f in fixtures:
            entry=req('/enter',dict(account=f['account'],character_id=f['id']))
            check(entry.get('core3_zone_verified') is True,'Existing fixture native location read')
            states.append(dict(account=f['account'],id=f['id'],saved=entry['source_location'],request_id='concurrency_'+secrets.token_hex(12),session=''))
            save()
        for state in states:
            response=adapter.gameplay_session(state['account'],dict(character_id=state['id'],**pose),start=True)
            state['session']=response['session_id'];save()
            capability=adapter.LIVE_COMBAT.request(state['account'],'snapshot',dict(character_id=state['id'],session_id=state['session']))
            check(capability.get('native_concurrency')=='engine_cross_lock_v1','Original native binary explicitly advertises Engine cross-lock support before concurrent work')
        with ThreadPoolExecutor(max_workers=2) as pool:
            for round_number in range(20):
                barrier=threading.Barrier(2)
                pending=[pool.submit(update,state,barrier) for state in states]
                replies=[future.result(timeout=20) for future in pending]
                if round_number:
                    for state,result in zip(states,replies):
                        peer=next(other['id'] for other in states if other is not state)
                        check(any(p['id']==peer for p in result['snapshot']['world']['players']),'Concurrent snapshot acquires the other player and reports original peer')
        check(max(timings)<3,'All forty concurrent native operations finish within three seconds')
        report['passed']=True
    except Exception as exc:
        report['failure_type']=type(exc).__name__
    finally:
        for state in states:
            if not state['session']:continue
            try:
                original=state['saved']
                out=adapter.logout_session(state['account'],state['id'],dict(live_session_id=state['session'],request_id=state['request_id'],**{k:original[k]for k in ('position','building_id','cell_index','heading_radians')}))
                state['restored']=out.get('saved') is True and out.get('session_closed') is True
                save()
                if state['restored']:
                    after=req('/enter',dict(account=state['account'],character_id=state['id']))['source_location']
                    state['restored']=(after['building_id']==original['building_id'] and after['cell_index']==original['cell_index'] and math.dist(after['position'],original['position'])<.02)
                report['cleanup'].append({'restored':state['restored']});report['passed'] &= state['restored']
            except Exception as exc:
                report['cleanup'].append({'restored':False,'failure_type':type(exc).__name__});report['passed']=False
        report['timings']={'count':len(timings),'median_seconds':round(statistics.median(timings),3)if timings else 0,'maximum_seconds':round(max(timings,default=0),3)}
        evidence.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({'passed':report['passed'],'checks':len(checks),'timings':report['timings']}))
    return 0 if report['passed']else 1

if __name__=='__main__':raise SystemExit(main())
