#!/usr/bin/env python3
"""Read-only identity/membership smoke against normal and persistent Core3 sessions."""
import hashlib,json,time
from pathlib import Path
from services_smoke import ROOT,req
from live_combat_smoke import Test

def main():
 fixture=json.loads((ROOT/'runtime/server/pve-fixture.json').read_text())[0]
 account,oid=fixture['account'],fixture['id'];checks=[];evidence={}
 def check(ok,label):
  checks.append({'label':label,'passed':bool(ok)});assert ok,label
 normal=req('/voice/session',{'account':account,'character_id':oid})
 check(normal.get('backend')=='core3'and bool(normal.get('ticket')),'Native owned normal-world voice ticket issued')
 check(normal.get('needs_presence')is True and normal.get('presence_interval')==5,'Normal source refresh bounded to5seconds')
 check(normal.get('relay_port')==18084,'Local direct adapter selects loopbackdebug voiceport')
 state=json.loads((ROOT/'runtime/server/voice-state.json').read_text())[account]
 check(state['group_id']=='0'and state['faction']=='neutral','Original Core3 solo neutral membership is authoritative')
 check(state['zone']=='tatooine'and int(state['zone_id'])>0,'Native zone instance object identity published')
 check(state['ttl']==15 and not state['live'],'Normal native snapshot has bounded15second lifetime')
 evidence['normal']={key:value for key,value in normal.items()if key!='ticket'};evidence['normal_state']=state
 bad=req('/voice/session',{'account':account,'character_id':str(int(oid)+1)})
 check(bad.get('http_error')is not None,'Foreign or missing character cannot obtain voice ticket')
 presence=req('/voice/presence',{'account':account,'character_id':oid})
 check(presence.get('backend')=='core3','Fresh normal voice metadata reused without new login')
 fixture['position']=state['position'];test=Test(fixture,'http://127.0.0.1:18080')
 try:
  started=test.request('start',{'position':fixture['position']});test.request('update',{'position':fixture['position'],'ready':True})
  player=started['snapshot']['player'];check(player['voice']['group_id']=='0'and player['voice']['faction']=='neutral','Live native snapshot includes actual solo neutral membership')
  live=req('/voice/session',{'account':account,'character_id':oid,'session_id':test.session})
  check(live.get('needs_presence')is False and bool(live.get('ticket')),'Persistent native voice uses existing session without additional login')
  state=json.loads((ROOT/'runtime/server/voice-state.json').read_text())[account]
  check(state['live']and state['ttl']==4 and state['session_id']==test.session,'Live relay cache is bound to native session and4second freshness')
  evidence['live']={key:value for key,value in live.items()if key not in('ticket','native_session_id')};evidence['live_state']={key:value for key,value in state.items()if key!='session_id'}
 finally:
  if test.session:test.request('stop');test.session=''
 check(account not in json.loads((ROOT/'runtime/server/voice-state.json').read_text()),'Native stop removes voice route immediately')
 evidence.update(passed=True,native_execution=True,headset_tested=False,checks=checks,session_checks=len(test.checks),binary_sha256=hashlib.sha256((ROOT/'vendor/Core3/MMOCoreORB/bin/core3').read_bytes()).hexdigest())
 (ROOT/'runtime/evidence/voice-native.json').write_text(json.dumps(evidence,indent=2));print(json.dumps({'passed':True,'checks':len(checks),'session_checks':len(test.checks)}))
if __name__=='__main__':main()
