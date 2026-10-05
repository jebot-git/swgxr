#!/usr/bin/env python3
"""Create one waypoint on a dedicated test character and verify fresh Core3 readback."""
import argparse,json,secrets,time,urllib.request,urllib.parse,urllib.error
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def request(method,path,data=None):
    req=urllib.request.Request('http://127.0.0.1:18080'+path,data=None if data is None else json.dumps(data).encode(),headers={'Content-Type':'application/json'},method=method)
    with urllib.request.urlopen(req,timeout=65) as stream:return json.load(stream)
def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--fixture',type=Path);args=parser.parse_args()
    if args.fixture:
        fixture=json.loads(args.fixture.read_text())
    else:
        account='map'+secrets.token_hex(4);name='Nav'+''.join(chr(97+secrets.randbelow(26)) for _ in range(8))
        created=request('POST','/characters',{'account':account,'name':name,'species':'human','profession':'crafting_artisan'})
        fixture={'account':account,'id':created['character']['id'],'name':name}
    query=urllib.parse.urlencode({'account':fixture['account'],'character_id':fixture['id']})
    started=time.monotonic();before=request('GET','/datapad?'+query)
    body={'account':fixture['account'],'character_id':fixture['id'],'name':'Survey '+secrets.token_hex(3),'planet':'tatooine','position':{'x':3541.3884,'y':5.63942,'z':-4802.7585}}
    bad=dict(body,position={'x':9000,'y':0,'z':0})
    try:request('POST','/waypoints',bad)
    except urllib.error.HTTPError as exc:assert exc.code==400
    else:raise AssertionError('Out-of-range waypoint accepted')
    created=request('POST','/waypoints',body);after=request('GET','/datapad?'+query)
    entry=request('POST','/enter',{'account':fixture['account'],'character_id':fixture['id']})
    waypoint=created['waypoint'];assert waypoint in after['waypoints'] and waypoint in entry['datapad']['waypoints']
    assert len(after['waypoints'])==len(before['waypoints'])+1
    assert before['physical_entries']==after['physical_entries']
    assert before['schematics']==after['schematics']
    assert entry['character_id']==fixture['id'] and waypoint['active']
    report={'passed':True,'fixture':fixture,'waypoint':waypoint,'physical_entries':len(after['physical_entries']),'learned_schematics':len(after['schematics']),'waypoint_count_before':len(before['waypoints']),'waypoint_count_after':len(after['waypoints']),'fresh_login_and_entry_verified':True,'invalid_coordinates_rejected':True,'seconds':time.monotonic()-started,'server_restarted':False}
    path=ROOT/'runtime/evidence/datapad-http-smoke.json';path.write_text(json.dumps(report,indent=2));print(json.dumps(report,indent=2))
if __name__=='__main__':main()
