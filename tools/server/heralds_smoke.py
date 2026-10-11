#!/usr/bin/env python3
"""Real native herald dialogue and waypoint checks on the isolated local backend."""
import argparse,json,secrets,sys,urllib.parse,math,time
from pathlib import Path
import services_smoke as shared
ROOT=Path(__file__).resolve().parents[2]
def main():
 p=argparse.ArgumentParser();p.add_argument('--port',type=int,default=18086);args=p.parse_args()
 shared.BASE=f'http://127.0.0.1:{args.port}'
 fixture=ROOT/'runtime/server/heralds-fixture.json'
 if fixture.exists():f=json.loads(fixture.read_text())
 else:
  f={'account':'invtestherald'+secrets.token_hex(3),'name':'Hrtest'+''.join(secrets.choice('aeilnorstu') for _ in range(8))}
  result=shared.req('/characters',dict(f,species='human',profession='crafting_artisan'))
  assert 'character' in result,result
  f['id']=result['character']['id'];fixture.write_text(json.dumps(f))
 assert f['account'].startswith('invtestherald')
 base={'account':f['account'],'character_id':f['id']};position=[3376.1,5,-4785]
 checks=[];responses=[];session=''
 def check(ok,label):
  checks.append({'passed':bool(ok),'label':label});print(label,bool(ok),flush=True)
  if not ok:raise AssertionError(label)
 def service(action,**kwargs):
  payload=dict(base,session_id=session,position=position,building_id='0',cell_index=0,**kwargs)
  if action not in ('open','status'):payload.setdefault('request_id','herald_'+secrets.token_hex(10))
  result=shared.req('/services/'+action,payload);responses.append({'action':action,'response':shared.redact(result)});return result
 try:
  result=shared.req('/combat/session/start',dict(base,position=position))
  check(result.get('session_live'),'Persistent isolated native client connected');session=result['session_id']
  target=position[:];current=result['snapshot']['player']['position']
  for step in range(400):
   distance=math.dist(current,target)
   if distance<.1:break
   time.sleep(.3)
   fraction=min(1,1.2/distance);proposed=[a+(b-a)*fraction for a,b in zip(current,target)]
   moved=shared.req('/combat/session/update',dict(base,session_id=session,position=proposed,building_id='0',cell_index=0,ready=True))
   if not moved.get('session_live'):raise AssertionError(moved.get('error','Native walk disconnected'))
   current=moved.get('snapshot',{}).get('player',{}).get('position',current)
   if step%30==0:print('Native walk remaining metres',round(math.dist(current,target),1),flush=True)
  check(math.dist(current,target)<.1,'Native movement reaches herald without teleport bypass')
  position=current
  state=service('status');check(state.get('ok'),'Native services discovery responds')
  candidates=[t for t in state['state']['terminals'] if t['kind']=='herald' and t['name']=='Lorne Prestar']
  check(len(candidates)==1,'Lorne Prestar discovered as native herald')
  npc=candidates[0]
  for step in range(150):
   distance=math.dist(position,npc['position'])
   if distance<.6:break
   time.sleep(.3)
   fraction=min(1,1.8/distance);proposed=[a+(b-a)*fraction for a,b in zip(position,npc['position'])]
   moved=shared.req('/combat/session/update',dict(base,session_id=session,position=proposed,building_id='0',cell_index=0,ready=True))
   position=moved.get('snapshot',{}).get('player',{}).get('position',position)
   npc=next((a for a in moved.get('snapshot',{}).get('actors',[]) if a['id']==npc['id']),npc)
  check(math.dist(position,npc['position'])<.6,'Approach current wandering NPC position')
  check('herald_home_position' in npc and math.dist(npc['herald_home_position'],[3376.1,5,-4786])<.25,'Native stable home position identifies wandering herald')
  opened=service('open',terminal_id=npc['id'])
  check(opened.get('ok') and opened['state']['terminal']['options'][0].get('begin'),'Existing dialogue interface receives begin choice')
  begun=service('herald_begin',terminal_id=npc['id']);view=begun.get('state',{}).get('terminal',{})
  check(begun.get('ok') and len(view.get('options',[]))>0 and not view.get('dialogue','').startswith('@'),'Original Lua conversation screen resolves original text')
  bad=service('herald_choose',terminal_id=npc['id'],option=0,screen_token='expired_screen')
  check(not bad.get('ok'),'Stale screen token rejected before original handlers')
  # First option accepts the destination on a fresh herald; a repeat fixture may
  # first offer to clear its previous waypoint. Both choices remain native.
  key='herald_accept_'+secrets.token_hex(8)
  chosen=service('herald_choose',terminal_id=npc['id'],option=0,screen_token=view['screen_token'],request_id=key)
  check(chosen.get('ok'),'Native herald choice executes')
  replay=service('herald_choose',terminal_id=npc['id'],option=0,screen_token=view['screen_token'],request_id=key)
  check(replay.get('ok') and replay.get('mutation',{}).get('replayed'),'Repeated request reuses durable native receipt')
  check(replay.get('state',{}).get('terminal',{}).get('screen_token')==chosen.get('state',{}).get('terminal',{}).get('screen_token'),'Retry restores the current dialogue screen')
  datapad=shared.req('/datapad?'+urllib.parse.urlencode(base));responses.append({'action':'datapad','response':shared.redact(datapad)})
  entries=datapad.get('entries',datapad.get('datapad',{}).get('entries',[]))
  waypoints=[e for e in entries if e.get('category')=='waypoints']
  check(any(e.get('planet')=='tatooine' and abs(e.get('position',{}).get('x',0)+3976)<1 if isinstance(e.get('position'),dict) else e.get('planet')=='tatooine' and abs(e.get('position',[0])[0]+3976)<1 for e in waypoints),'Original Fort Tusken waypoint persists in native datapad')
 finally:
  if session:shared.req('/combat/session/stop',dict(base,session_id=session))
  report={'passed':bool(checks) and all(c['passed'] for c in checks),'checks':checks,'native_execution':True,'remote_server_changed':False,'headset_tested':False,'responses':responses}
  (ROOT/'runtime/evidence/herald-native-smoke.json').write_text(json.dumps(report,indent=2)+'\n')
if __name__=='__main__':main()
