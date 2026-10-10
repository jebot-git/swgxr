#!/usr/bin/env python3
"""Measure original minor and ordinary worrt attacks against a CoreCU fixture; no balance overrides."""
import secrets,time,json
from services_smoke import req,ROOT
from seed_bazaar import Native

def main():
    n=Native('swgxr-core3-build');owner={'account':'invtestwort'+secrets.token_hex(3),'name':'Ivtest'+''.join(secrets.choice('aeilnorst') for _ in range(9))}
    for attempt in range(10):
     owner['name']='Ivtest'+''.join(secrets.choice('aeilnorst') for _ in range(9))
     r=req('/characters',dict(owner,species='human',profession='combat_marksman'))
     if 'character' in r:break
    assert 'character' in r,r
    owner['id']=r['character']['id'];base={'account':owner['account'],'character_id':owner['id']};entered=req('/enter',base);assert 'http_error' not in entered,entered
    source=f'''
    function Tests:swgxrWorrtAuditSetup(kind)
     local p=getSceneObject({owner['id']});CreatureObject(p):forcePeace();SceneObject(p):teleport(5010,getTerrainHeight(p,5010,-5500),-5500,0)
     local m=spawnMobile("tatooine",kind or "worrt",0,5010,getTerrainHeight(p,5010,-5498),-5498,0,0)
     writeData("swgxrWorrtAudit",SceneObject(m):getObjectID());
     return tostring(AiAgent(m):getDamageMin())..":"..tostring(AiAgent(m):getDamageMax())
    end
    function Tests:swgxrWorrtAuditBegin()
     local p=getSceneObject({owner['id']});local m=getSceneObject(readData("swgxrWorrtAudit"));AiAgent(m):setDefender(p);AiAgent(m):selectDefaultAttack();AiAgent(m):enqueueAttack();return "attacking"
    end
    function Tests:swgxrWorrtAuditRead()
     local p=getSceneObject({owner['id']});local c=CreatureObject(p)
     return tostring(c:getHAM(0))..":"..tostring(c:getMaxHAM(0))..":"..tostring(c:hasState(2))
    end
    function Tests:swgxrWorrtAuditClean()
     local m=getSceneObject(readData("swgxrWorrtAudit"));if m~=nil then SceneObject(m):destroyObjectFromWorld()end;deleteData("swgxrWorrtAudit");CreatureObject(getSceneObject({owner['id']})):forcePeace();return "clean"
    end
    '''
    report={'fixture':owner,'variants':{},'xr':False,'native_execution':True,'administrative_placement':True}
    with n.screenplay('swgxrWorrtAuditSetup',source):
     for kind in ['minor_worrt','worrt']:
      session=''
      try:
       damage=n.call('swgxrWorrtAuditSetup:'+kind)
       location=req('/services/status',base)['state']['player'];pose={k:location[k] for k in ('position','building_id','cell_index')}
       started=req('/session/start',dict(base,**pose));assert started.get('session_live'),started;session=started['session_id']
       ready=req('/session/update',dict(base,session_id=session,ready=True,**pose));assert ready.get('session_live'),ready
       samples=[];before=n.call('swgxrWorrtAuditRead');n.call('swgxrWorrtAuditBegin');begin=time.monotonic()
       for i in range(60):
        v=n.call('swgxrWorrtAuditRead');samples.append([round(time.monotonic()-begin,3),v]);print(kind,v,flush=True);time.sleep(.2)
       health=[float(before.split(':')[0])]+[float(v.split(':')[0]) for _,v in samples]
       hits=[a-b for a,b in zip(health,health[1:]) if a>b]
       report['variants'][kind]={'weapon_min_max':damage,'initial':before,'samples':samples,'observed_hits':hits,'health_lost':health[0]-health[-1]}
       assert float(before.split(':')[1])==3000 and hits and max(hits)>2
      finally:
       n.call('swgxrWorrtAuditClean')
       if session:req('/session/logout',dict(base,live_session_id=session,**pose))
    report['passed']=len(report['variants'])==2
    (ROOT/'runtime/evidence/mission-combat-20261010/worrt-native.json').write_text(json.dumps(report,indent=2))
    print(json.dumps({'passed':report['passed'],'variants':{k:{f:v[f] for f in ('weapon_min_max','initial','observed_hits','health_lost')} for k,v in report['variants'].items()}}),flush=True)

if __name__=='__main__':main()
