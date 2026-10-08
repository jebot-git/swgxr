#!/usr/bin/env python3
"""Local native entry/readiness/save on each original ground planet.

Privileged disposable-character placement is setup only; every entry, ready
acknowledgment and persistence check uses the real adapter/native client.
"""
import json,re,secrets,time
from services_smoke import ROOT,req,redact
from equipment_smoke import console

def main():
 owner=dict(account='invtestzones'+secrets.token_hex(3),name='Ivtest'+''.join(secrets.choice('aeilnorst')for _ in range(9)))
 made=req('/characters',dict(owner,species='human',profession='combat_marksman'));owner['id']=made['character']['id'];base=dict(account=owner['account'],character_id=owner['id'])
 report=dict(passed=False,privileged_placement=True,native_execution=True,native_build_receipt=json.loads((ROOT/'runtime/server/native-build.json').read_text()),checks=[],responses=[]);session=''
 script=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/tests/tests.lua'
 added=f"\nfunction Tests:swgxrGroundZoneFixture(zone) local p=getSceneObject({owner['id']}); SceneObject(p):switchZone(zone,0,0,0,0); SceneObject(p):teleport(0,getTerrainHeight(p,0,0),0,0); return SceneObject(p):getZoneName() end\n"
 def call(path,**kw):
  out=req(path,dict(base,**kw));report['responses'].append(dict(path=path,response=redact(out)));return out
 def check(ok,label):
  report['checks'].append(dict(passed=bool(ok),label=label));print(label,bool(ok),flush=True);assert ok,label
 try:
  call('/enter');script.write_text(script.read_text()+added);console('reloadscreenplays');time.sleep(.5)
  for zone in ('corellia','dantooine','dathomir','endor','lok','naboo','rori','talus','tatooine','yavin4'):
   log=ROOT/'runtime/server/core3-console.log';offset=log.stat().st_size;console('runLuaFunction Tests:swgxrGroundZoneFixture:'+zone)
   for _ in range(100):
    with log.open()as f:f.seek(offset);text=f.read()
    if 'runLuaFunction Tests:swgxrGroundZoneFixture: result=['+zone+']' in text:break
    time.sleep(.1)
   else:raise AssertionError('Native zone fixture placement failed '+zone)
   entry=call('/enter');loc=entry['source_location'];check(loc['zone']==zone,'Native original '+zone+' entry')
   fields={k:loc[k]for k in ('zone','position','building_id','cell_index')}
   started=call('/session/start',**fields);session=started['session_id']
   ready=call('/session/update',session_id=session,ready=True,**fields);player=ready['snapshot']['player']
   check(not player['on_load_screen']and ready.get('mutation',{}).get('movement_accepted'),'Native '+zone+' ready and floor validation')
   saved=call('/session/logout',live_session_id=session,zone=zone,**{k:player[k]for k in ('position','building_id','cell_index')});session=''
   check(saved.get('saved')and saved['location']['zone']==zone,'Native '+zone+' save')
   check(call('/enter')['source_location']['zone']==zone,'Fresh '+zone+' saved-zone reentry')
  report['passed']=True
 finally:
  if session:call('/combat/session/stop',session_id=session)
  if added in script.read_text():script.write_text(script.read_text().replace(added,''));console('reloadscreenplays')
  (ROOT/'runtime/evidence/ground-planets-native.json').write_text(json.dumps(report,indent=2));print(json.dumps(dict(passed=report['passed'],checks=len(report['checks']))),flush=True)
if __name__=='__main__':main()
