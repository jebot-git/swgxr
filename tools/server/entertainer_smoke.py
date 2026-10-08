#!/usr/bin/env python3
"""Local native entertainer regression; advanced prerequisites explicitly admin-provisioned.
No user accounts, VR, remote deployment, or claimed earned advanced progression.
"""
import json, secrets, time
from services_smoke import ROOT, req, redact
from equipment_smoke import console


def main():
    checks=[];records=[];sessions={};fixtures=[];script=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/tests/tests.lua';injected=''
    def check(value,label):
        checks.append(dict(passed=bool(value),label=label));print(label,bool(value),flush=True)
        if not value:raise AssertionError(label)
    def make():
        owner=dict(account='invtestentertainer'+secrets.token_hex(3),name='Ivtest'+''.join(secrets.choice('aeilnorstu')for _ in range(8)))
        result=req('/characters',dict(owner,species='human',profession='social_entertainer'));assert 'character'in result,result
        owner['id']=result['character']['id'];fixtures.append(owner);return owner
    def call(owner,path,**kw):
        for attempt in range(12):
            before=time.monotonic();out=req(path,dict(account=owner['account'],character_id=owner['id'],**kw));records.append(dict(path=path,owner=owner['id'],seconds=time.monotonic()-before,response=redact(out)))
            if out.get('error_code')!='backend_busy' or out.get('mutation_started')is not False:return out
            time.sleep(min(2,max(.1,out.get('retry_after',1))))
        return out
    def ent(owner,action,**kw):
        if action!='status':kw.setdefault('request_id','entertainer_'+secrets.token_hex(8))
        return call(owner,'/entertainer/'+action,live_session_id=sessions[owner['id']],zone='tatooine',**kw)
    def start(owner):
        entry=call(owner,'/enter');loc=entry['source_location'];opened=call(owner,'/combat/session/start',**{k:loc[k]for k in ('position','building_id','cell_index','zone')});sessions[owner['id']]=opened['session_id']
        call(owner,'/session/update',session_id=opened['session_id'],ready=True,**{k:loc[k]for k in ('position','building_id','cell_index','zone')})
    def denied(out):return out.get('http_error')==400 or out.get('ok')is False
    report=dict(passed=False,native_execution=True,headset_tested=False,remote_server_changed=False,checks=checks,responses=records,fixtures=fixtures,
                fixture_setup='Fresh original novice entertainer and observer. Dance XP first earned through original native flourish/tick. Later only primary receives explicitly administrator-provisioned original social_dancer_master prerequisites for advanced effects and registration; this is not earned progression.')
    try:
        actor=make();observer=make();start(actor);start(observer)
        (ROOT/'runtime/server/entertainer-fixtures.json').write_text(json.dumps(fixtures))
        outside=dict(position=[3527,5,-4810],building_id='0',cell_index=0)
        baseline=ent(actor,'status',**outside);check(baseline.get('ok'),'Owned retained native entertainer state available')
        check('social_entertainer_novice'in baseline['state']['skills']and 'social_dancer_novice'not in baseline['state']['skills'],'Original starter profession has no advanced diagnostic grants initially')
        check(denied(ent(actor,'register_location',**outside)),'Outdoor registration rejected by original venue rules')
        check(denied(ent(actor,'perform',kind='dance',name='exotic4')),'Unlearned original advanced dance rejected')
        played=ent(actor,'perform',kind='dance',name='basic');check(played.get('ok')and played['state']['performing']and played['state']['kind']=='dance','Original StartDance creates active native session')
        prior=played['state']['experience'].get('dance',0);key='entertainer_once_'+secrets.token_hex(8)
        flourished=ent(actor,'flourish',request_id=key);check(flourished.get('ok')and flourished['mutation'].get('index')in flourished['state']['flourishes'],'Native random flourish selects only learned number')
        replay=ent(actor,'flourish',request_id=key);check(replay.get('mutation',{}).get('replayed')and replay['mutation']['index']==flourished['mutation']['index'],'Durable replay retains exact flourish without repeated cost or reroll')
        check(denied(ent(actor,'flourish')),'Original flourish cadence enforced against rapid trigger')
        deadline=time.monotonic()+20
        while time.monotonic()<deadline:
            state=ent(actor,'status')
            if state['state']['experience'].get('dance',0)>prior:break
            time.sleep(1)
        check(state['state']['experience'].get('dance',0)>prior,'Original EntertainingSession tick awards earned dance XP')
        stopped=ent(actor,'stop');check(stopped.get('ok')and not stopped['state']['performing'],'Original StopDance ends native session')
        inventory=call(actor,'/inventory/status',live_session_id=sessions[actor['id']]);instrument=next(i for i in inventory['items']if i['template'].endswith('/slitherhorn.iff'))
        held=call(actor,'/inventory/equip',live_session_id=sessions[actor['id']],item_id=instrument['id'],arrangement=0);check(held.get('mutation',{}).get('success'),'Explicitly equip owned original portable instrument')
        music=ent(actor,'perform',kind='music',name='starwars1',item_id=instrument['id']);check(music.get('ok')and music['state']['kind']=='music'and music['state']['item_id']==instrument['id'],'Held portable instrument and original StartMusic accept learned song')
        stopped_music=ent(actor,'stop')
        deadline=time.monotonic()+20
        while time.monotonic()<deadline:
            stopped_music=ent(actor,'status')
            if not stopped_music['state']['performing']:break
            time.sleep(1)
        check(not stopped_music['state']['performing'],'Original15second music outro completes before changing performance kind')
        source=json.loads((ROOT/'runtime/assets/ambient_npcs/placements.json').read_text());row=next(x for x in source['instances']if x['source_cell_id']=='1082877')
        inside=dict(position=row['source_world_xyz'],building_id=row['building_object_id'],cell_index=int(row['cell_id'].split(':')[1]))
        check(not any(r['id']==inside['building_id']for r in baseline['state']['registrations']),'Isolated registration venue has no pre-existing registered professionals')
        check(denied(ent(actor,'register_location',**inside)),'Novice entertainer alone cannot register original cantina')
        injected='\n-- BEGIN SWGXR ENTERTAINER ISOLATED ADMIN FIXTURE\nfunction Tests:swgxrEntertainerFixture(phase)\n local p=getSceneObject('+actor['id']+') if p==nil then return end\n awardSkill(p,"social_dancer_master")\nend\n-- END SWGXR ENTERTAINER ISOLATED ADMIN FIXTURE\n'
        assert actor['account'].startswith('invtestentertainer')
        script.write_text(script.read_text()+injected);console('reloadscreenplays');console('runLuaFunction Tests:swgxrEntertainerFixture:advanced');time.sleep(.5)
        state=ent(actor,'status');check('social_dancer_master'in state['state']['skills'],'Explicitly labelled isolated fixture receives original advanced prerequisite skills')
        registered=ent(actor,'register_location',**inside);check(registered.get('ok')and registered['state']['registration']['registered'],'Original registerWithLocation confirms registered performer')
        venue=registered['state']['registration']['building_id'];seen=ent(observer,'status',**outside)
        check(any(r['id']==venue and r['native_icon']==2 for r in seen['state']['registrations']),'Other authenticated player sees original active venue on planetary map')
        repeated=ent(actor,'register_location',**inside);check(repeated.get('ok')and repeated['state']['registration']['registered'],'Repeated native registration remains idempotently registered')
        advanced=ent(actor,'perform',kind='dance',name='basic');choices=advanced['state']['flourish_choices']
        changed=ent(actor,'perform',kind='dance',name='exotic4');check(changed.get('ok')and changed['state']['performance_index']!=advanced['state']['performance_index'],'Original ChangeDance changes learned dance without stopping session')
        effects=[x for x in choices if x['command']!='flourish'];check({x['command']for x in effects}=={'spotlight','colorlights','dazzle','distract','smokebomb'},'Learned dance effect families enter random pool using original source grants')
        check(all(x['level']==3 for x in effects),'Original ability skill modifiers unlock highest source effect tier')
        effect=None
        for _ in range(16):
            state=ent(actor,'flourish')
            if state.get('ok'):
                if state['mutation'].get('effect_file'):effect=state;break
                time.sleep(max(.2,state['mutation'].get('cooldown_seconds',5)+.1))
            else:time.sleep(2)
        check(effect is not None and len(effect['mutation']['effect_position'])==3,'Native learned effect accepted with confirmed cooldown and source effect position')
        before=effect['live_response']['snapshot']['player']['ham'][1];same=ent(actor,'flourish',request_id=effect['mutation']['request_id']);check(same.get('mutation',{}).get('replayed')and same['mutation']['effect_file']==effect['mutation']['effect_file'],'Accepted effect retry does not replay native effect or reroll')
        ent(actor,'stop');ent(actor,'status',**outside)
        seen=ent(observer,'status');check(not any(r['id']==venue for r in seen['state']['registrations']),'Leaving original building removes active map registration for other players')
        report['passed']=True
    finally:
        for owner in fixtures:
            if owner['id']in sessions:
                ent(owner,'stop');ent(owner,'status',**outside)
                call(owner,'/combat/session/stop',session_id=sessions[owner['id']])
        if injected:
            script.write_text(script.read_text().replace(injected,''));console('reloadscreenplays')
        (ROOT/'runtime/evidence/entertainer-native.json').write_text(json.dumps(redact(report),indent=2));print(json.dumps(dict(passed=report['passed'],checks=len(checks))),flush=True)

if __name__=='__main__':
    import sys
    if '--instruments-only' in sys.argv:
        from instrument_native_smoke import main as instruments
        instruments()
    else:main()
