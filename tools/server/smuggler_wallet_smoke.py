#!/usr/bin/env python3
"""Real Core3 wallet transfers on two disposable local characters."""
import json,re,secrets,time,threading
from services_smoke import ROOT,req,redact
from equipment_smoke import console

def main():
    fixtures=[];sessions={};states={};checks=[];responses=[];sequences={}
    marker='wallet'+secrets.token_hex(4)
    script=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/tests/tests.lua'
    added=''
    def check(value,label):
        checks.append(dict(passed=bool(value),label=label));print(label,bool(value),flush=True)
        if not value:raise AssertionError(label)
    def call(o,path,**kw):
        result=req(path,dict(account=o['account'],character_id=o['id'],**kw))
        responses.append(dict(path=path,response=redact(result)));return result
    def service(o,action='status',**kw):
        if action not in ('status','open'):kw.setdefault('request_id',marker+secrets.token_hex(4))
        if action=='pay':
            heartbeat(True);stop=threading.Event()
            def keep_tracking():
                while not stop.wait(.15):heartbeat(True,False)
            worker=threading.Thread(target=keep_tracking,daemon=True);worker.start()
            try:result=call(o,'/services/'+action,live_session_id=sessions[o['id']],**kw)
            finally:stop.set();worker.join(timeout=10)
        else:result=call(o,'/services/'+action,live_session_id=sessions[o['id']],**kw)
        if 'state' in result:states[o['id']]=result
        return result
    def lua(name):
        log=ROOT/'runtime/server/core3-console.log';offset=log.stat().st_size
        console('runLuaFunction Tests:'+name)
        for _ in range(100):
            with log.open() as f:f.seek(offset);text=f.read()
            if 'runLuaFunction Tests:'+name+': result=' in text:return
            time.sleep(.1)
        raise RuntimeError('Native fixture setup timed out')
    def heartbeat(grip,record=True):
        for o in fixtures:
            state=states[o['id']];p=state['state']['player']['position'];presence=state['presence']
            sequence=max(sequences.get(o['id'],0),presence.get('sequence_floor',0))+1;sequences[o['id']]=sequence
            payload=dict(token=presence['token'],sequence=sequence,position=p,hand=dict(position=[p[0],p[1]+1.2,p[2]],tracked=True,grip=grip),wallet_held=o is fixtures[0])
            out=call(o,'/services/presence',**payload) if record else req('/services/presence',dict(account=o['account'],character_id=o['id'],**payload))
            if record:check('error' not in out,'Tracked wallet handshake pose accepted')
    def handshake():
        heartbeat(False);heartbeat(True);time.sleep(.35);heartbeat(True)
    report=dict(passed=False,native_execution=True,headset_tested=False,remote_server_changed=False,checks=checks,responses=responses)
    try:
        for _ in range(2):
            o=dict(account='invtest'+marker+secrets.token_hex(1),name='Ivtest'+''.join(secrets.choice('aeilnorstu')for _ in range(9)))
            created=req('/characters',dict(o,species='human',profession='crafting_artisan'))
            assert 'character' in created,created
            o['id']=created['character']['id'];fixtures.append(o)
            entry=call(o,'/enter');location=entry['source_location']
            start=call(o,'/combat/session/start',**{k:location[k]for k in ('position','zone','building_id','cell_index')})
            sessions[o['id']]=start['session_id']
        a,b=fixtures
        setup=marker+'Setup';cap=marker+'Cap'
        added=f'''\n-- BEGIN {marker}
function Tests:{setup}()
 for _,id in ipairs({{{a['id']},{b['id']}}}) do
  local p=getSceneObject(id);SceneObject(p):teleport(3527,5,-4810,0);CreatureObject(p):addCashCredits(1000,true)
 end
 local p=getSceneObject({a['id']});awardSkill(p,"combat_smuggler_novice")
 local g=PlayerObject(CreatureObject(p):getPlayerObject());g:setFactionStanding("imperial",900);g:setFactionStanding("rebel",900)
 local r=PlayerObject(CreatureObject(getSceneObject({b['id']})):getPlayerObject());r:setFactionStanding("imperial",0);r:setFactionStanding("rebel",0)
 return 1
end
function Tests:{cap}() local p=getSceneObject({b['id']});PlayerObject(CreatureObject(p):getPlayerObject()):setFactionStanding("rebel",1000);return 1 end
-- END {marker}
'''
        script.write_text(script.read_text()+added);console('reloadscreenplays');lua(setup)
        before_a=service(a)['state']['wallet'];before_b=service(b)['state']['wallet']
        check(before_a['faction_delegation'],'Smuggler sees native faction wallet')
        handshake();key=marker+'transfer'
        paid=service(a,'pay',target_id=b['id'],amount=7,faction_points={'imperial':20,'rebel':30},request_id=key)
        check(paid.get('ok'),'Mixed credit and both faction transfer accepted')
        wallet=paid['state']['wallet'];recipient=service(b)['state']['gcw']['standings'];rate=before_a['delegation_ratio']
        import math
        check(wallet['cash']==before_a['cash']-7 and service(b)['state']['wallet']['cash']==before_b['cash']+7,'Native credits conserved')
        check(wallet['faction_points']['rebel']==900-math.ceil(30*rate) and recipient['rebel']==30 and recipient['imperial']==20,'Original rank ratio applied to both standing transfers')
        replay=service(a,'pay',target_id=b['id'],amount=7,faction_points={'imperial':20,'rebel':30},request_id=key)
        check(replay.get('mutation',{}).get('replayed') and replay['state']['wallet']==wallet,'Lost-response retry cannot double spend any currency')
        denied=service(a,'pay',target_id=b['id'],amount=7,faction_points={'imperial':20,'rebel':31},request_id=key)
        check(not denied.get('ok'),'Handshake forbids changed faction amount on retry')
        lua(cap);service(a);service(b);handshake();before=service(a)['state']['wallet']
        denied=service(a,'pay',target_id=b['id'],amount=7,faction_points={'imperial':20,'rebel':1})
        check(not denied.get('ok') and service(a)['state']['wallet']==before,'Recipient cap rejects entire bundle before credits or other faction debit')
        report['passed']=True
    finally:
        if added:script.write_text(script.read_text().replace(added,''));console('reloadscreenplays')
        for o in fixtures:
            if o['id'] in sessions:call(o,'/combat/session/stop',session_id=sessions[o['id']])
        report['fixtures']=fixtures
        path=ROOT/'runtime/evidence/smuggler-wallet-native.json';path.parent.mkdir(exist_ok=True,parents=True);path.write_text(json.dumps(report,indent=2))

if __name__=='__main__':main()
