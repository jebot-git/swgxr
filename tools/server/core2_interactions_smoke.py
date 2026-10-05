#!/usr/bin/env python3
"""Actual original mission generation, survey objectives and durable waypoint removal.

Dedicated existing novice artisan; no skill/item/credit grants, no XR, loopback
only. Newly accepted missions and survey markers are cleaned up, pose restored.
"""
import json
import math
import sys
import time
from pathlib import Path
from delivery_mission_smoke import Probe, key, pose
from services_smoke import ROOT


class Core2Probe(Probe):
    def __init__(self):
        super().__init__('core2', ROOT/'runtime/evidence/core2/native-interactions.json')
        self.waypoints=set()

    def datapad(self):
        # Uses the active native replication command, never a second login.
        from services_smoke import req
        result=req('/datapad?account='+self.fixture['account']+'&character_id='+self.fixture['id'])
        self.report['responses'].append(dict(path='/datapad',response=result))
        self.check('entries' in result,'Read actual original player waypoint replication')
        return result

    def survey(self,tool,resource,where):
        ready=self.call('/session/update',**pose(where),ready=True)
        self.check(ready.get('session_live'),'Move dedicated native fixture to source survey position')
        result=self.call('/gathering/survey',tool_id=tool['id'],resource_id=resource['id'],position=where['position'],request_id=key())
        self.check(result.get('mutation',{}).get('success'),'Actual tool surveys current original resource spawn')
        waypoint=result['mutation']['survey'].get('waypoint')
        if waypoint:self.waypoints.add(waypoint['id'])
        return result['mutation']['survey']

    def execute(self):
        self.setup()
        candidates=json.loads((ROOT/'runtime/assets/services/catalog.json').read_text())['static_terminals']
        scout=min((t for t in candidates if t['template'].endswith('/terminal_mission_scout.iff')),key=lambda t:math.dist(t['position'],[3500,5,-4860]))
        artisan=self.terminals['crafting']
        # Switching profession terminal types used to expose 24 stale zero-CRC slots.
        for terminal,kind,types in [(artisan,'artisan',{'survey','crafting'}),(scout,'scout',{'recon','hunting'}),(artisan,'artisan',{'survey','crafting'})]:
            opened=self.service('open',terminal_id=terminal['id'],**pose(terminal))
            self.check(opened.get('ok'),'Original '+kind+' terminal opens for unchanged novice artisan')
            view=opened['state']['terminal'];offers=view['missions']
            self.check(view.get('terminal_type')==kind and 0<len(offers)<=12 and all(m['type'] in types for m in offers),'Only generated '+kind+' offers returned; stale cleared slots excluded')
            self.check(all(m['supported'] for m in offers),'Original '+kind+' objectives are selectable')
            if kind=='scout':
                for typ in ('recon','hunting'):
                    offer=next(m for m in offers if m['type']==typ)
                    accepted=self.service('mission_accept',terminal_id=terminal['id'],mission_id=offer['id'],**pose(terminal))
                    self.check(accepted.get('ok') and any(m['id']==offer['id'] for m in accepted['state']['missions']),'Original explorer '+typ+' objective accepted')
                    self.accepted.add(offer['id'])
                spare=next(m for m in offers if m['id'] not in self.accepted)
                rejected=self.service('mission_accept',terminal_id=terminal['id'],mission_id=spare['id'],**pose(terminal))
                self.check(rejected.get('http_error')==400 and 'Two missions' in rejected.get('error',''),'Original two-active-mission limit remains enforced with readable rejection')
                for oid in list(self.accepted):
                    result=self.service('mission_abort',mission_id=oid)
                    self.check(result.get('ok'),'Cancel only newly accepted explorer objective')
                    self.accepted.remove(oid)
            time.sleep(1.5)
        inventory=self.inventory()
        resources=[]
        for tool in inventory['items']:
            if tool.get('tool_kind')=='survey':
                state=self.call('/gathering/status',tool_id=tool['id'])
                self.check(state.get('source_kind')=='core3_gathering','Owned novice survey tool exposes original compatible planet resources')
                resources.extend((tool,r) for r in state['resources'])
        matched=None
        for offer in offers:
            if offer['type']=='survey':
                matched=next(((offer,t,r) for t,r in resources if r.get('mission_family')==offer['target']),None)
                if matched:break
        self.check(matched is not None,'Original artisan survey offer matches an owned tool and current spawn family')
        offer,tool,resource=matched
        accepted=self.service('mission_accept',terminal_id=artisan['id'],mission_id=offer['id'],**pose(artisan))
        self.check(accepted.get('ok'),'Accept original survey mission without profession or reward bypass')
        self.accepted.add(offer['id'])
        original_wallet=accepted['state']['wallet']
        self.check(not any(e.get('name')=='Resource Survey' for e in self.datapad()['entries']),'Dedicated fixture has no prior resource waypoint to disturb')
        near=self.survey(tool,resource,artisan)
        status=self.service('status')
        self.check(any(m['id']==offer['id'] for m in status['state']['missions']),'Original survey objective does not complete within1024m of issuing terminal')
        # Search bounded real density maps; no forced density, skills or reward.
        best=None
        positions=[[-5000,0,-5000],[0,0,0],[5000,0,5000],[-5000,0,5000],[5000,0,-5000],[0,0,5000],[-2500,0,0],[2500,0,0],[0,0,-5000]]
        for position in positions:
            result=self.survey(tool,resource,dict(position=position,building_id='0',cell_index=0))
            status=self.service('status')
            if int(result['highest']['density']*100)>=offer['difficulty']:
                best=result
                self.check(not any(m['id']==offer['id'] for m in status['state']['missions']),'Original resource family+density+distance observer completes actual survey mission')
                self.check(sum(status['state']['wallet'].values())-sum(original_wallet.values())==offer['reward'],'Original survey mission pays exact native reward once')
                self.accepted.discard(offer['id'])
                break
        self.check(best is not None,'Bounded real resource survey finds naturally sufficient concentration')
        marker=best['waypoint']['id']
        pad=self.datapad();entry=next((e for e in pad['entries'] if e['id']==marker),{})
        self.check(entry.get('deletable') is True and entry.get('source')=='core3_player_waypoint_list','Actual owned resource waypoint is marked removable')
        deleted=self.call('/datapad/delete',entry_id=marker)
        self.check(deleted.get('deleted_id')==marker and not any(e['id']==marker for e in deleted['datapad']['entries']),'Original owned waypoint destruction removes survey marker from fresh native replication')
        self.waypoints.discard(marker)
        self.check(not any(e['id']==marker for e in self.datapad()['entries']),'Independent live datapad read cannot resurrect removed survey marker')
        ended=self.call('/session/logout',**pose(self.initial_pose),request_id=key())
        self.check(ended.get('saved') and ended.get('session_closed'),'Persist character and close owned native session')
        self.session=''
        self.check(not any(e['id']==marker for e in self.datapad()['entries']),'Survey waypoint deletion survives fresh native login')
        self.start(self.initial_pose)
        again=self.survey(tool,resource,dict(position=best['position'],building_id='0',cell_index=0))
        self.check(again.get('waypoint',{}).get('id') not in ('',None,marker),'Subsequent original survey creates new persistent marker after deletion')
        self.report['passed']=True

    def cleanup(self):
        if self.fixture and self.initial_pose:
            try:
                pad=self.datapad()
                for entry in pad['entries']:
                    if entry['id'] in self.waypoints:
                        result=self.call('/datapad/delete',entry_id=entry['id'])
                        self.check(result.get('deleted_id')==entry['id'],'Remove only test-created resource waypoint')
            except Exception as error:
                self.report['waypoint_cleanup_error']=str(error)
        super().cleanup()

    def run(self):
        try:
            self.execute()
        except Exception as error:
            self.report['error']=str(error)
            raise
        finally:
            self.cleanup()
            if self.report.get('cleanup_errors') or self.report.get('waypoint_cleanup_error'):self.report['passed']=False
            self.output.parent.mkdir(parents=True,exist_ok=True)
            self.output.write_text(json.dumps(self.report,indent=2)+'\n')
            print(json.dumps(dict(passed=self.report['passed'],checks=len(self.report['checks']),cleanup_errors=self.report.get('cleanup_errors'),error=self.report.get('error'))))

if __name__=='__main__':Core2Probe().run()
