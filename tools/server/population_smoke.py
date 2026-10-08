#!/usr/bin/env python3
"""Synthetic owned-session load using existing dedicated test accounts.

No account creation, skill grants or attacks. Fixtures must be private JSON with
purpose=corecu_population_test and players[{account:loadtest..., character_id,
token (HTTPS only)}]. Uses their saved positions and restores/saves on logout.
Choose clustered fixture positions before running to exercise crowded AOI.
"""
import argparse
import concurrent.futures
import json
import math
import secrets
import ssl
import statistics
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from server.planets import SUPPORTED_PLANETS
from tools.client.remote_connection import NoRedirect, safe_http_diagnostic

def fixtures(path,count):
    value=json.loads(path.read_text())
    players=value.get('players',[])
    if value.get('purpose')!='corecu_population_test' or count<1 or len(players)<count:
        raise ValueError('Supply enough existing dedicated population-test fixtures.')
    players=players[:count]
    if len({p['account'] for p in players})!=count or len({str(p['character_id']) for p in players})!=count:
        raise ValueError('Every fixture needs its own account and character.')
    if any(not p['account'].startswith('loadtest') or not str(p['character_id']).isdigit() for p in players):
        raise ValueError('Only dedicated loadtest accounts with native character IDs are accepted.')
    return players

def summary(samples):
    values=sorted(samples)
    return {'count':len(values),'p50_seconds':statistics.median(values) if values else None,
            'p95_seconds':values[min(len(values)-1,math.ceil(len(values)*.95)-1)] if values else None,
            'max_seconds':max(values) if values else None}

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fixtures',type=Path,required=True)
    parser.add_argument('--clients',type=int,default=32)
    parser.add_argument('--seconds',type=float,default=120)
    parser.add_argument('--interval',type=float,default=.5,help='Stationary native update period per player')
    parser.add_argument('--pose-hz',type=float,default=10,help='Separate tracked-presentation requests per second (up to 25)')
    parser.add_argument('--url',default='http://127.0.0.1:18080')
    parser.add_argument('--ca',type=Path)
    parser.add_argument('--report',type=Path,required=True)
    args=parser.parse_args()
    players=fixtures(args.fixtures,args.clients)
    parsed=urllib.parse.urlparse(args.url)
    if parsed.scheme not in ('http','https') or parsed.username or parsed.password or parsed.query or parsed.fragment:raise ValueError('Expected a plain adapter/gateway URL.')
    if parsed.scheme=='http' and parsed.hostname!='127.0.0.1':raise ValueError('Plain HTTP is loopback-only.')
    if parsed.scheme=='https' and any(not p.get('token') for p in players):raise ValueError('HTTPS fixtures require their own account bearer tokens.')
    if not math.isfinite(args.seconds) or args.seconds<=0 or not math.isfinite(args.interval) or args.interval<.275:raise ValueError('Use a positive duration and an interval of at least 275 ms.')
    if not math.isfinite(args.pose_hz) or not 0<args.pose_hz<=25:raise ValueError('Pose rate must be positive and no higher than the 25 Hz protocol budget.')
    context=ssl.create_default_context(cafile=str(args.ca) if args.ca else None)
    states=[];times=[];pose_times=[];errors=[];cleanup=[];peer_counts=[]
    report={'native_execution':True,'headset_tested':False,'target_population':32,'requested_clients':args.clients,
            'started_at':time.time(),'endpoint':args.url,
            'combat_load_tested':False,'voice_load_tested':False,'passed':False}
    diagnostics=[]
    def failure(exc,kind):
        record={'kind':kind,'failure_type':type(exc).__name__}
        if isinstance(exc,urllib.error.HTTPError):record.update(safe_http_diagnostic(exc))
        if type(exc) is ValueError and str(exc) in (
                'Ramp-up session lost.','Native player did not enter the visible scene.',
                'Ramp-up refresh failed.','Fixture must be on a supported original ground planet.',
                'Native session did not start.','Owned native session/sequence lost.',
                'Native player left the visible scene.','Native update rejected.','Presentation ownership lost.'):
            record['validation_error']=str(exc)
        diagnostics.append(record)
        return kind+'_'+type(exc).__name__
    def request(player,path,data):
        data=dict(data,account=player['account'],character_id=str(player['character_id']))
        headers={'Content-Type':'application/json'}
        if player.get('token'):headers['Authorization']='Bearer '+player['token']
        req=urllib.request.Request(args.url.rstrip('/')+path,data=json.dumps(data).encode(),headers=headers)
        opener=urllib.request.build_opener(urllib.request.HTTPSHandler(context=context),NoRedirect())
        with opener.open(req,timeout=40) as response:return json.load(response)
    warm_stop=threading.Event();warm_errors=[]
    def refresh(state,ready=False):
        out=request(state['player'],'/session/update',dict(state['pose'],zone=state['zone'],session_id=state['session_id'],ready=ready))
        if not out.get('session_live') or out.get('session_id')!=state['session_id'] or out.get('mutation',{}).get('success') is False:raise ValueError('Ramp-up session lost.')
        if ready and out.get('player',{}).get('on_load_screen') is not False:raise ValueError('Native player did not enter the visible scene.')
        state['sequence']=int(out['sequence'])
    def maintain():
        # Early logins must keep their native leases while later clients connect.
        with concurrent.futures.ThreadPoolExecutor(max_workers=min(32,args.clients)) as pool:
            while not warm_stop.wait(2):
                try:list(pool.map(refresh,list(states)))
                except Exception as exc:warm_errors.append(failure(exc,'warm'));return
    warm=threading.Thread(target=maintain,daemon=True);warm.start()
    try:
        # Serialize cold logins; the measured phase begins with all clients connected.
        for player in players:
            if warm_errors:raise ValueError('Ramp-up refresh failed.')
            before=request(player,'/enter',{})['source_location']
            zone=before.get('zone')
            if zone not in SUPPORTED_PLANETS:raise ValueError('Fixture must be on a supported original ground planet.')
            pose={k:before[k] for k in ('position','building_id','cell_index','heading_radians')}
            start=request(player,'/session/start',dict(pose,zone=zone))
            if not start.get('session_live') or not start.get('session_id'):raise ValueError('Native session did not start.')
            states.append(dict(player=player,pose=pose,zone=zone,session_id=start['session_id'],sequence=int(start['sequence'])))
            report['admitted_clients']=len(states)
            print(json.dumps({'phase':'ramp_up','admitted_clients':len(states)}),flush=True)
        warm_stop.set();warm.join()
        if warm_errors:raise ValueError('Ramp-up refresh failed.')
        with concurrent.futures.ThreadPoolExecutor(max_workers=args.clients) as pool:list(pool.map(lambda state:refresh(state,ready=True),states))
        report['connected_clients']=len(states)
        report['planets']=sorted({state['zone'] for state in states})
        begin=time.monotonic();end=begin+args.seconds
        report['measured_started_at']=time.time()
        print(json.dumps({'phase':'measurement','clients':len(states),'seconds':args.seconds}),flush=True)
        client_rates=[]
        def worker(state,kind):
            samples=[];peers=[];failures=[];cursor=-1;revision=-1;visible=0;pose_sequence=int(time.time()*1000000)
            interval=args.interval if kind=='native' else 1/args.pose_hz
            while time.monotonic()<end:
                started=time.monotonic()
                try:
                    if kind=='native':
                        out=request(state['player'],'/session/update',dict(state['pose'],zone=state['zone'],session_id=state['session_id'],ready=True))
                        if not out.get('session_live') or out.get('session_id')!=state['session_id'] or int(out.get('sequence',0))<=state['sequence']:raise ValueError('Owned native session/sequence lost.')
                        if out.get('player',{}).get('on_load_screen') is not False:raise ValueError('Native player left the visible scene.')
                        if out.get('mutation',{}).get('success') is False:raise ValueError('Native update rejected.')
                        state['sequence']=int(out['sequence'])
                    else:
                        pose_sequence+=1
                        view=request(state['player'],'/session/sync',dict(state['pose'],zone=state['zone'],session_id=state['session_id'],sequence=pose_sequence,world_revision=revision,event_sequence=cursor,tracking={}))
                        if view.get('session_id')!=state['session_id']:raise ValueError('Presentation ownership lost.')
                        cursor=int(view.get('event_sequence',cursor));revision=int(view['world_revision'])
                        if view.get('world') is not None:visible=len(view['world'].get('players',[]))
                        peers.append(visible)
                    samples.append(time.monotonic()-started)
                except Exception as exc:
                    # Never retain URL, auth headers, fixture tokens or raw error bodies.
                    failures.append(failure(exc,kind));break
                time.sleep(max(0,interval-(time.monotonic()-started)))
            return kind,samples,peers,failures,{
                'client':states.index(state)+1,'kind':kind,'responses':len(samples),
                'achieved_hz':len(samples)/max(time.monotonic()-begin,.001),
                'max_visible_peers':max(peers,default=0)}
        with concurrent.futures.ThreadPoolExecutor(max_workers=args.clients*2) as pool:
            pending=[pool.submit(worker,state,kind) for state in states for kind in ('native','pose')]
            for future in pending:
                kind,samples,peers,failures,rate=future.result()
                (times if kind=='native' else pose_times).extend(samples);peer_counts.extend(peers);errors.extend(failures)
                client_rates.append(rate)
        report['per_client_rates']=client_rates
        report['elapsed_seconds']=time.monotonic()-begin
        report['measured_finished_at']=time.time()
    except Exception as exc:errors.append(failure(exc,'setup'))
    finally:
        warm_stop.set();warm.join()
        for state in states:
            try:
                out=request(state['player'],'/session/logout',dict(state['pose'],zone=state['zone'],live_session_id=state['session_id'],request_id='load_'+secrets.token_hex(12)))
                cleanup.append(bool(out.get('saved') and out.get('session_closed')))
            except Exception as exc:cleanup.append(False);errors.append(failure(exc,'cleanup'))
        elapsed=report.get('elapsed_seconds',0)
        sustained=bool(elapsed) and len(times)>=.9*args.clients*elapsed/args.interval and len(pose_times)>=.9*args.clients*elapsed*args.pose_hz
        report.update(errors=errors,diagnostics=diagnostics,finished_at=time.time(),native_updates=summary(times),presentation_updates=summary(pose_times),max_visible_peers=max(peer_counts,default=0),cleanup=cleanup,sustained_requested_rates=sustained,requested_native_hz=1/args.interval,requested_pose_hz=args.pose_hz)
        report['passed']=len(states)==args.clients and bool(times) and bool(pose_times) and not errors and all(cleanup) and sustained
        args.report.parent.mkdir(parents=True,exist_ok=True);args.report.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report));return 0 if report['passed'] else 1

if __name__=='__main__':raise SystemExit(main())
