#!/usr/bin/env python3
"""Real image design consent/payment proof on fresh, explicitly provisioned fixtures."""
import json,secrets,time
from services_smoke import ROOT,req,redact
from equipment_smoke import console


def main():
    checks=[];records=[];owners=[];sessions={};injected=''
    script=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/tests/tests.lua'
    report=dict(passed=False,native_execution=True,headset_tested=False,remote_server_changed=False,fixtures=owners,checks=checks,responses=records,
                fixture_setup='Fresh isolated original entertainer accounts. Only designer is administrator-provisioned with original Image Designer master prerequisites; this does not claim earned progression. Original group invite/join, revision consent, customization, XP and payments are exercised.')
    def check(value,label):
        checks.append(dict(passed=bool(value),label=label));print(label,bool(value),flush=True)
        if not value:raise AssertionError(label)
    def call(owner,path,**kw):
        result=req(path,dict(account=owner['account'],character_id=owner['id'],**kw));records.append(dict(path=path,owner=owner['id'],response=redact(result)));return result
    def ent(owner,action,**kw):
        if action!='status':kw.setdefault('request_id','image_'+secrets.token_hex(12))
        return call(owner,'/entertainer/'+action,live_session_id=sessions[owner['id']],zone='tatooine',**kw)
    def status(owner):return ent(owner,'status')
    def design(result):return result['state']['image_design']
    def token(value):return dict(session_id=value['session_id'],revision=value['revision'])
    def wallet(owner):return call(owner,'/services/status',session_id=sessions[owner['id']])['state']['wallet']
    def total(value):return value['cash']+value['bank']
    def denied(value):return value.get('http_error')==400 or value.get('ok')is False
    try:
        for _ in range(2):
            owner=dict(account='invtestimage'+secrets.token_hex(4),name='Ivtest'+''.join(secrets.choice('aeilnorstu')for _ in range(6)))
            result=req('/characters',dict(owner,species='human',profession='social_entertainer'));assert 'character'in result,result
            owner['id']=result['character']['id'];owners.append(owner)
            entry=call(owner,'/enter');loc=entry['source_location'];context={k:loc[k]for k in ('position','building_id','cell_index','zone')}
            opened=call(owner,'/combat/session/start',**context);sessions[owner['id']]=opened['session_id']
            call(owner,'/session/update',session_id=opened['session_id'],ready=True,**context)
            ent(owner,'status',position=[3527,5,-4810],building_id='0',cell_index=0)
        designer,recipient=owners
        (ROOT/'runtime/server/image-design-fixtures.json').write_text(json.dumps(owners))
        check(denied(ent(designer,'image_open',target_id=recipient['id'])),'Native image design rejects players outside same group')
        injected='\n-- BEGIN SWGXR IMAGE DESIGN ISOLATED FIXTURE\nfunction Tests:swgxrImageFixture()\n local p=getSceneObject('+designer['id']+') if p~=nil then awardSkill(p,"social_imagedesigner_master") end\nend\n-- END SWGXR IMAGE DESIGN ISOLATED FIXTURE\n'
        script.write_text(script.read_text()+injected);console('reloadscreenplays');console('runLuaFunction Tests:swgxrImageFixture');time.sleep(.5)
        advanced=status(designer);check('social_imagedesigner_master'in advanced['state']['skills'],'Explicit fixture original Image Designer mastery observed')
        own=ent(designer,'image_open',target_id=designer['id']);check(own.get('ok')and design(own)['role']=='designer','Original native self-design session opens')
        ctrl=next(c for c in design(own)['options']['controls']if c['height']);draft={'attributes':{ctrl['id']:.31},'price':0}
        proposed=ent(designer,'image_propose',**token(design(own)),draft=draft);check(proposed.get('ok')and design(proposed)['revision']==1,'Source-gated height proposal has normalized native preview')
        expected=design(proposed)['preview']['height'];accepted=ent(designer,'image_accept',**token(design(proposed)))
        check(accepted.get('mutation',{}).get('committed')and not design(accepted).get('active'),'Self consent commits through original ImageDesignSession')
        check(abs(accepted['state']['appearance']['height']-expected)<1e-5,'Original native height equals preview after self commit')
        invited=ent(designer,'group_invite',target_id=recipient['id']);check(invited.get('ok'),'Original group invite issued')
        pending=status(recipient);check(pending['state']['group_inviter_id']==designer['id'],'Recipient sees actual native group invitation')
        joined=ent(recipient,'group_join');check(joined.get('ok'),'Original group join accepted')
        for _ in range(10):
            a,b=status(designer),status(recipient)
            if a['state']['group_id']!='0'and a['state']['group_id']==b['state']['group_id']:break
            time.sleep(.2)
        check(a['state']['group_id']!='0'and a['state']['group_id']==b['state']['group_id'],'Original GroupManager establishes shared membership')
        opened=ent(designer,'image_open',target_id=recipient['id']);check(opened.get('ok'),'Original two-player image session opens in actual group')
        offer=status(recipient);check(design(offer)['role']=='recipient'and design(offer)['designer_id']==designer['id'],'Recipient polling exposes native offer with correct role')
        denied_proposal=ent(recipient,'image_propose',**token(design(offer)),draft=draft)
        check(denied(denied_proposal),'Recipient cannot replace designer proposal')
        ctrl=next(c for c in design(opened)['options']['controls']if c['height'])
        proposed=ent(designer,'image_propose',**token(design(opened)),draft={'attributes':{ctrl['id']:.68},'price':7})
        before_d,before_r=wallet(designer),wallet(recipient);original=status(recipient)['state']['appearance']
        first=ent(designer,'image_accept',**token(design(proposed)),recipient_accepted=True)
        check(first.get('ok')and design(first)['designer_accepted']and not design(first)['recipient_accepted'],'Designer cannot forge recipient consent')
        check(wallet(designer)==before_d and wallet(recipient)==before_r and status(recipient)['state']['appearance']==original,'No payment or appearance change occurs with one-sided consent')
        revised=ent(designer,'image_propose',**token(design(first)),draft={'attributes':{ctrl['id']:.72},'price':9})
        check(not design(revised)['designer_accepted']and not design(revised)['recipient_accepted'],'Draft revision clears both consents')
        check(denied(ent(recipient,'image_accept',**token(design(first)))),'Stale revision acceptance rejected')
        recipient_accept=ent(recipient,'image_accept',**token(design(revised)));check(design(recipient_accept)['recipient_accepted']and not design(recipient_accept)['designer_accepted'],'Recipient consent alone remains pending')
        key='image_commit_'+secrets.token_hex(12);commit=ent(designer,'image_accept',**token(design(revised)),request_id=key)
        check(commit.get('mutation',{}).get('committed'),'Two authenticated consents commit original native design')
        after_d,after_r=wallet(designer),wallet(recipient)
        check(total(after_d)-total(before_d)==9 and total(before_r)-total(after_r)==9,'Original native payment conserves credits at accepted price')
        rendered=status(recipient)['state']['appearance'];expected=design(revised)['preview']['height']
        check(abs(rendered['height']-expected)<1e-5,'Recipient native appearance changes to accepted preview')
        replay=ent(designer,'image_accept',**token(design(revised)),request_id=key)
        check(replay.get('mutation',{}).get('replayed')and wallet(designer)==after_d and wallet(recipient)==after_r,'Duplicate commit receipt does not charge twice')
        check(status(designer)['state']['experience'].get('imagedesigner',0)>0,'Original image session awards native image-design XP')
        reopened=ent(designer,'image_open',target_id=recipient['id']);cancel=ent(recipient,'image_cancel',**token(design(reopened)))
        check(cancel.get('mutation',{}).get('cancelled')and not design(status(designer)).get('active'),'Recipient cancellation clears original session for both actors')
        for owner in owners:
            call(owner,'/combat/session/stop',session_id=sessions.pop(owner['id']))
        saved=call(recipient,'/enter')['character']['appearance']
        check(abs(saved['height']-expected)<1e-5,'Accepted appearance persists across independent native login')
        report['passed']=True
    finally:
        for owner in owners:
            if owner['id']in sessions:call(owner,'/combat/session/stop',session_id=sessions[owner['id']])
        if injected:script.write_text(script.read_text().replace(injected,''));console('reloadscreenplays')
        (ROOT/'runtime/evidence/image-design-native.json').write_text(json.dumps(redact(report),indent=2));print(json.dumps({'passed':report['passed'],'checks':len(checks)}),flush=True)

if __name__=='__main__':main()
