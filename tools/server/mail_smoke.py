#!/usr/bin/env python3
"""Mail ownership, wire transfer and survey consumption on disposable native accounts."""
import argparse,json,re,secrets,time
from pathlib import Path
import services_smoke as shared
from equipment_smoke import console
ROOT=Path(__file__).resolve().parents[2]
def main():
 p=argparse.ArgumentParser();p.add_argument('--port',type=int,default=18086);args=p.parse_args();shared.BASE=f'http://127.0.0.1:{args.port}'
 a=json.loads((ROOT/'runtime/server/services-fixture.json').read_text());b=json.loads((ROOT/'runtime/server/services-recipient-fixture.json').read_text())
 assert all(f['account'].startswith('invtestservices') and re.fullmatch('Ivtest[a-z]+',f['name']) for f in (a,b))
 checks=[];evidence=[];mail_ids=[];passed=False
 def call(f,action,**kw):
  data=dict(account=f['account'],character_id=f['id'],**kw)
  if action not in ('mail_status','mail_list','probe_status','bank_quote'):data.setdefault('request_id','mailtest-'+secrets.token_hex(10))
  r=shared.req('/services/'+action,data);evidence.append(dict(action=action,response=r));return r
 def check(ok,label):checks.append(dict(passed=bool(ok),label=label));print(label,bool(ok),flush=True);assert ok,label
 script=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/tests/tests.lua';original=script.read_text()
 def lua(mode):
  log=ROOT/'runtime/server/core3-console.log';offset=log.stat().st_size;console('runLuaFunction Tests:corecuMailFixture:'+mode)
  for _ in range(100):
   with log.open() as h:h.seek(offset);text=h.read()
   found=re.search(r'runLuaFunction Tests:corecuMailFixture: result=\[(.*?)\]',text)
   if found:return found[1]
   time.sleep(.05)
  raise AssertionError(text[-1000:])
 try:
  for f in (a,b):check(call(f,'mail_status').get('ok'),'Native mailbox summary opens')
  key='mailtest-'+secrets.token_hex(10);subject='Native test '+key
  sent=call(a,'mail_send',recipient=b['name'],subject=subject,body='Original mail\nSecond line',request_id=key)
  check(sent.get('ok'),'Native mail sends');mid=sent['mutation']['sent_id'];mail_ids.append(mid)
  replay=call(a,'mail_send',recipient=b['name'],subject=subject,body='Original mail\nSecond line',request_id=key)
  check(replay.get('ok') and replay['mutation'].get('replayed') and replay['mutation']['sent_id']==mid,'Mail retry uses durable same-message receipt')
  time.sleep(.3);inbox=call(b,'mail_list');row=next((m for m in inbox['state']['mail']['messages'] if m['id']==mid),{})
  check(bool(row) and not row['read'],'Recipient sees original unread mail')
  check(not call(a,'mail_read',mail_id=mid).get('ok'),'Other character cannot read private mail')
  read=call(b,'mail_read',mail_id=mid);check(read.get('ok') and read['mutation']['message']['body']=='Original mail\nSecond line','Native read returns body and marks read')
  check(next(m for m in call(b,'mail_list')['state']['mail']['messages'] if m['id']==mid)['read'],'Read state persists across requests')
  check(not call(a,'mail_delete',mail_id=mid).get('ok'),'Other character cannot delete private mail')
  script.write_text(original+f'''
function Tests:corecuMailFixture(mode)
 local p=getSceneObject({a['id']})
 if p==nil or CreatureObject(p):getFirstName()~="{a['name']}" then return "bad_owner" end
 local key="corecu_mail_fixture"
 local function obj(k) return getSceneObject(tonumber(readScreenPlayData(p,key,k)) or 0) end
 local function save(k,o) if o~=nil then writeScreenPlayData(p,key,k,tostring(SceneObject(o):getObjectID())) end return o end
 if mode=="setup" then
  CreatureObject(p):clearCombatState(true) SceneObject(p):teleport(5900,getTerrainHeight(p,5900,-4804),-4804,0)
  CreatureObject(p):addBankCredits(1000,true)
  local bank=save("bank",spawnSceneObject("tatooine","object/tangible/terminal/terminal_bank.iff",5901,getTerrainHeight(p,5901,-4804),-4804,0,0))
  local inv=SceneObject(p):getSlottedObject("inventory")
  local probe=save("probe",giveItem(inv,"object/tangible/component/droid/droid_interplanetary_survey.iff",-1))
  local tool=save("tool",giveItem(inv,"object/tangible/survey_tool/survey_tool_mineral.iff",-1))
  if bank==nil or probe==nil or tool==nil then return "fixture_missing" end
  LuaComponent(probe):addProperty("mechanism_quality",100,0,"exp_quality",false)
  TangibleObject(probe):setUseCount(1)
  return tostring(SceneObject(bank):getObjectID())..","..tostring(SceneObject(probe):getObjectID())..","..tostring(SceneObject(tool):getObjectID())
 elseif mode=="pose" then return tostring(SceneObject(p):getWorldPositionX())..","..tostring(SceneObject(p):getWorldPositionZ())..","..tostring(SceneObject(p):getWorldPositionY())
 elseif mode=="cleanup" then
  for _,k in ipairs({{"bank","probe","tool"}}) do local o=obj(k) if o~=nil then SceneObject(o):destroyObjectFromWorld() SceneObject(o):destroyObjectFromDatabase() end end
 end
 return "ok"
end
''');console('reloadscreenplays');time.sleep(.2)
  bank,probe,tool=lua('setup').split(',');pose=dict(position=[float(v) for v in lua('pose').split(',')],zone='tatooine',building_id='0',cell_index=0)
  quote=call(a,'bank_quote',terminal_id=bank,recipient=b['name'],amount=100,**pose);check(quote.get('ok'),'Native bank reviews recipient and fee')
  q=quote['mutation']['quote'];check(q['fee']==5 and q['total']==105,'Native 5 percent wire fee retained')
  key='mailtest-'+secrets.token_hex(10);payload=dict(terminal_id=bank,recipient=b['name'],recipient_id=q['recipient_id'],amount=100,fee=q['fee'],request_id=key,**pose)
  paid=call(a,'bank_pay',**payload);check(paid.get('ok'),'Native bank confirmation transfers credits')
  again=call(a,'bank_pay',**payload);check(again.get('ok') and again['mutation'].get('replayed') and paid['state']['wallet']==again['state']['wallet'],'Wire retry does not transfer twice')
  probes=call(a,'probe_status',**pose);check(probes.get('ok') and any(p['id']==probe for p in probes['state']['survey_probes']['probes']),'Native inventory exposes usable probe')
  key='mailtest-'+secrets.token_hex(10);payload=dict(probe_id=probe,tool_id=tool,target_planet='naboo',request_id=key,**pose)
  launch=call(a,'probe_launch',**payload);check(launch.get('ok'),'Native survey task scheduled')
  check(900<=launch['mutation']['duration_seconds']<=3600,'Original quality-based survey delay retained')
  again=call(a,'probe_launch',**payload);check(again.get('ok') and again['mutation'].get('replayed') and again['mutation']['survey_id']==launch['mutation']['survey_id'],'Probe retry does not consume or schedule twice')
  after=call(a,'probe_status',**pose)['state']['survey_probes'];check(all(p['id']!=probe for p in after['probes']) and all(t['id']!=tool for t in after['tools']),'Native probe and selected survey tool consumed')
  passed=True
 finally:
  for mid in mail_ids:call(b,'mail_delete',mail_id=mid)
  if script.read_text()!=original:
   try:lua('cleanup')
   finally:script.write_text(original);console('reloadscreenplays')
  (ROOT/'runtime/evidence/mail-native-smoke.json').write_text(json.dumps(dict(passed=passed,checks=checks,evidence=evidence,native_execution=True,administrative_fixture=True,report_delivery_pending=True),indent=2))
if __name__=='__main__':main()
