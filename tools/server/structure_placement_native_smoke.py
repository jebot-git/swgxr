#!/usr/bin/env python3
"""Disposable local Core3 structure/camp placement through production endpoints.

Fixture Lua grants original items/skills, positions the test actor, reads native
terrain, and destroys only structures observed as owned by this fixture. It never
bypasses production preview/place/camp/disband behavior. Do not run concurrently
with another tests.lua fixture. Requires running local adapter + Core3 console.
"""
import json
import math
import re
import secrets
import time
from urllib.parse import urlencode
from services_smoke import ROOT, req, redact
from equipment_smoke import console

OUT = ROOT / 'runtime/evidence/structure-placement'
DEEDS = {
    'house': 'object/tangible/deed/player_house_deed/tatooine_house_small_deed.iff',
    'harvester': 'object/tangible/deed/harvester_deed/harvester_ore_s1_deed.iff',
    'factory': 'object/tangible/deed/factory_deed/factory_item_deed.iff',
}
CAMPS = ('basic', 'improved', 'multi', 'quality', 'elite', 'luxury')


def main():
    fixture = {'account': 'invtestplace' + secrets.token_hex(3),
               'name': 'Ivtest' + ''.join(secrets.choice('aeilnorstu') for _ in range(8))}
    report = {'passed': False, 'native_execution': True, 'remote_changed': False,
              'vr_launched': False, 'fixture': fixture, 'checks': [], 'responses': [],
              'limitations': ['Native placement/metadata only; client terrain rendering and collision are validated separately. Factory production and harvester extraction are outside this placement test.']}
    world = {'housing': {'structures': []}, 'scout': {'camps': []}}
    script = ROOT / 'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/tests/tests.lua'
    helper = ''; session = ''; location = {}; owned = set(); camp_terminal = ''

    def write():
        OUT.mkdir(parents=True, exist_ok=True)
        (OUT/'native.json').write_text(json.dumps(redact(report), indent=2)+'\n')
        (OUT/'native-world.json').write_text(json.dumps(world, indent=2)+'\n')

    def check(ok, label):
        report['checks'].append({'passed': bool(ok), 'label': label}); write()
        print(label, bool(ok), flush=True)
        assert ok, label

    def player(out):
        return out.get('snapshot', {}).get('player', out.get('live_response', {}).get('snapshot', {}).get('player', {}))

    def call(path, **kwargs):
        nonlocal location
        out = req(path, dict(account=fixture['account'], character_id=fixture.get('id', ''), **kwargs))
        report['responses'].append({'path': path, 'response': redact(out)})
        if path=='/scout/camp' and out.get('error') and session:
            native_log=ROOT/'runtime/server/livecombat'/session/'client.log'
            if native_log.exists():
                report.setdefault('camp_native_rejection_messages',[]).extend(re.findall(r'@camp:[a-z_]+',native_log.read_text()[-8192:]))
        if player(out): location = player(out)
        write(); return out

    def refresh():
        nonlocal location
        out = req('/combat/session?' + urlencode(dict(account=fixture['account'], character_id=fixture['id'], session_id=session)))
        location = player(out); assert location, out
        return location

    def pose():
        return {k: location[k] for k in ('position', 'zone', 'building_id', 'cell_index')}

    def act(route, **kwargs):
        return call(route, live_session_id=session, request_id='place_'+secrets.token_hex(8), **pose(), **kwargs)

    def housing():
        return act('/services/house_status')['state']['housing']

    def lua(arg):
        log = ROOT/'runtime/server/core3-console.log'; offset = log.stat().st_size
        console('runLuaFunction Tests:swgxrPlacementFixture:'+arg)
        for _ in range(150):
            with log.open() as stream:
                stream.seek(offset)
                match = re.search(r'runLuaFunction Tests:swgxrPlacementFixture: result=([^\n]+)', stream.read())
            if match: return match.group(1).strip().strip('[]')
            time.sleep(.1)
        raise AssertionError('Placement fixture Lua timed out: '+arg)

    def at(x, z):
        check(lua('move,'+str(x)+','+str(z)) == 'done', 'Fixture moves to native terrain '+str((x,z)))
        refresh()
        out=call('/session/update',session_id=session,ready=True,**pose())
        check(not out.get('error'), 'Trusted placement fixture acknowledges native scene readiness')

    try:
        made=call('/characters',name=fixture['name'],species='human',profession='crafting_artisan')
        check('character' in made, 'Create disposable native placement character')
        fixture['id']=made['character']['id'];location=call('/enter')['source_location']
        opened=call('/session/start',**pose());session=opened['session_id'];location=player(opened)
        call('/session/update',session_id=session,ready=True,**pose())
        # No forced structure spawn: all world structures below come from ordinary endpoints.
        helper=f'''\n-- BEGIN SWGXR PLACEMENT FIXTURE
function Tests:swgxrPlacementFixture(arg)
 local p=getSceneObject({fixture['id']});if p==nil then return "missing_player" end
 local fields={{}};for v in string.gmatch(arg,"[^,]+") do table.insert(fields,v) end
 local op=fields[1]
 if op=="setup" then
  awardSkill(p,"outdoors_scout_novice")
  for _,branch in ipairs({{"movement","tools","harvest","camp"}}) do for tier=1,4 do awardSkill(p,"outdoors_scout_"..branch.."_0"..tier) end end
  awardSkill(p,"outdoors_scout_master");awardSkill(p,"outdoors_ranger_novice")
  for _,branch in ipairs({{"movement","tracking","harvest","support"}}) do for tier=1,4 do awardSkill(p,"outdoors_ranger_"..branch.."_0"..tier) end end
  awardSkill(p,"outdoors_ranger_master");return "done"
 end
 if op=="give" then local o=giveItem(SceneObject(p):getSlottedObject("inventory"),fields[2],-1);if o==nil then return "missing_item" end;return tostring(SceneObject(o):getObjectID()) end
 if op=="move" then local x=tonumber(fields[2]);local z=tonumber(fields[3]);CreatureObject(p):forcePeace();CreatureObject(p):setPosture(0);SceneObject(p):teleport(x,getTerrainHeight(p,x,z),z,0);return "done" end
 if op=="skill" then return tostring(CreatureObject(p):getSkillMod("camp")) end
 if op=="terrain" then return tostring(getTerrainHeight(p,tonumber(fields[2]),tonumber(fields[3]))) end
 if op=="maximum" then
  local maximum=-16000;local minimum=16000
  for z=tonumber(fields[3]),tonumber(fields[5])-1 do for x=tonumber(fields[2]),tonumber(fields[4])-1 do local h=getTerrainHeight(p,x,z);maximum=math.max(maximum,h);minimum=math.min(minimum,h) end end
  return tostring(maximum)..","..tostring(minimum)
 end
 if op=="cleanup" then destroyBuilding(tonumber(fields[2]));return "done" end
 if op=="exists" then local o=getSceneObject(tonumber(fields[2]));if o==nil or SceneObject(o):getZoneName()=="" then return "gone" else return "present" end end
 return "unknown_operation"
end
-- END SWGXR PLACEMENT FIXTURE
'''
        script.write_text(script.read_text()+helper);console('reloadscreenplays')
        check(lua('setup')=='done','Fixture grants original camp skills')
        report['native_camp_skill']=float(lua('skill'));check(report['native_camp_skill']>=85,'Original awarded camp skill satisfies all6 camp tiers')
        for index,(kind,template) in enumerate(DEEDS.items()):
            item=lua('give,'+template);check(item.isdigit(),'Original '+kind+' deed granted')
            # Separate rural sites keep native no-build overlap checks independent.
            at(5010+index*250,-5500)
            base=list(location['position']);candidate=None
            before=housing();before_ids={r['id'] for r in before['structures']}
            for dx,dz in ((16,0),(-16,0),(0,24),(0,-24),(40,0),(-40,0)):
                point=[base[0]+dx,base[1],base[2]+dz]
                out=act('/services/house_preview',deed_id=item,placement_position=point,rotation=0)
                if out.get('mutation',{}).get('valid'):
                    candidate=point;break
            check(candidate is not None,'Original '+kind+' preview accepts rural placement')
            preview=housing()
            check(not preview['construction_active'] and {r['id'] for r in preview['structures']}==before_ids,'Preview creates no native '+kind+' structure or construction session')
            far=list(base);far[0]+=150
            rejected=act('/services/house_preview',deed_id=item,placement_position=far,rotation=0)
            check(rejected.get('mutation',{}).get('valid') is False,'Original '+kind+' placement range rejects150m')
            out=act('/services/house_place',deed_id=item,placement_position=candidate,rotation=0)
            check(out.get('mutation',{}).get('valid') is True,'Normal '+kind+' placement begins native construction')
            row=None
            for _ in range(45):
                snapshot=housing()
                new=[r for r in snapshot['structures'] if r['id'] not in before_ids and r.get('owner_id')==fixture['id']]
                for r in new: owned.add(r['id'])
                if new and not snapshot['construction_active']:
                    row=new[0];break
                time.sleep(1)
            check(row is not None,'Original '+kind+' construction produces owned native structure')
            world['housing']['structures'].append(row);write()
            check(all(k in row for k in ('terrain_modification_file','snap_to_terrain','clear_flora_radius','footprint','heading_radians')),'Native '+kind+' row carries original terrain policy and pose')
            check(math.hypot(row['position'][0]-candidate[0],row['position'][2]-candidate[2])<.01,'Native '+kind+' placement retains requested horizontal coordinates')
            f=row['footprint'];x,_,z=row['position']
            if f and row['clear_flora_radius']>0 and not row['snap_to_terrain']:
                # StructureManager::getStructureFootprint uses original 8m cells,
                # TerrainManager::getHighestHeight truncates origin/delta to int.
                x0=-(f['center_x']*8+4);z0=-(f['center_z']*8+4)
                x1=8*f['columns']-(f['center_x']*8+4);z1=8*f['rows']-(f['center_z']*8+4)
                ix=int(x+x0);iz=int(z+z0)
                maximum,minimum=map(float,lua('maximum,'+','.join(map(str,(ix,iz,ix+int(abs(x1-x0)),iz+int(abs(z1-z0)))))).split(','))
                report.setdefault('terrain_samples',[]).append({'id':row['id'],'maximum':maximum,'minimum':minimum,'bounds':[ix,iz,ix+int(abs(x1-x0)),iz+int(abs(z1-z0))]})
                check(abs(row['position'][1]-maximum)<.02,'Original '+kind+' foundation equals native highest footprint terrain')
            else:
                center=float(lua('terrain,'+str(x)+','+str(z)))
                report.setdefault('terrain_samples',[]).append({'id':row['id'],'center':center})
                check(abs(row['position'][1]-center)<.02,'Original '+kind+' ground-snap equals native center terrain')
            if kind=='house':
                check(row['template']=='object/building/player/player_house_tatooine_small_style_01.iff','House uses original deed-generated building template')
            check(row['terrain_modification_file']=='','Original '+kind+' has no invented flattening layer')
        # Camp tests use another site far enough from all three permanent structures.
        at(5010,-5750)
        for kind in CAMPS:
            item=lua('give,object/tangible/scout/camp/camp_'+kind+'.iff')
            check(item.isdigit(),'Original '+kind+' camp kit granted')
            deployed=act('/scout/camp',item_id=item)
            if not deployed.get('mutation',{}).get('success'):
                # Original lairs/static structures can occupy any rural coordinate.
                # Retry only an unconsumed kit at distinct bounded fixture sites;
                # original camping validation remains authoritative on every try.
                for x,z in ((5400,-5750),(5800,-6000),(5000,-6500),(4000,-6000)):
                    report.setdefault('camp_location_rejections',[]).append({'position':list(location['position']),'error':deployed.get('error')})
                    at(x,z);deployed=act('/scout/camp',item_id=item)
                    if deployed.get('mutation',{}).get('success'):break
            check(deployed.get('mutation',{}).get('success'),'Normal '+kind+' camp deployment succeeds')
            camps=deployed.get('state',{}).get('camps',[])
            camp=next((r for r in camps if r.get('owner_id')==fixture['id']),None)
            check(camp is not None,'Native '+kind+' camp appears in original scout state')
            owned.add(camp['id']);camp_terminal=camp['terminal_id']
            world['scout']['camps'].append(camp);write()
            check(camp['terrain_modification_file'] in ('terrain/poi_small.lay','terrain/poi_medium.lay'),'Camp projects original authored terrain layer '+kind)
            x,y,z=camp['position']
            check(abs(y-float(lua('terrain,'+str(x)+','+str(z))))<.02,'Native '+kind+' camp origin equals center terrain height')
            # Position fixture at native terminal if its source offset exceeds reach.
            t=camp.get('terminal_position',camp['position'])
            if math.dist(t,location['position'])>14: at(t[0],t[2])
            disbanded=act('/scout/disband',terminal_id=camp_terminal)
            check(disbanded.get('mutation',{}).get('success'),'Normal '+kind+' camp disband succeeds')
            for _ in range(15):
                remaining=act('/scout/status').get('state',{}).get('camps',[])
                if not any(r['id']==camp['id'] for r in remaining):break
                time.sleep(1)
            check(not any(r['id']==camp['id'] for r in remaining),'Disband removes '+kind+' camp and terrain-layer source')
            for _ in range(25):
                if lua('exists,'+camp['id'])=='gone':break
                time.sleep(.2)
            check(lua('exists,'+camp['id'])=='gone','Native asynchronous '+kind+' camp destruction completes before next placement')
            owned.discard(camp['id']);camp_terminal=''
        report['passed']=True
    finally:
        if helper:
            try:
                # Production disband first for any unfinished camp, then original
                # native DestroyStructureTask for this fixture's tracked structures.
                if camp_terminal:
                    try: act('/scout/disband',terminal_id=camp_terminal)
                    except Exception as error: report['camp_cleanup_error']=str(error)
                for oid in sorted(owned):
                    check(lua('cleanup,'+oid)=='done','Native cleanup requested for fixture-owned structure '+oid)
                    for _ in range(15):
                        if lua('exists,'+oid)=='gone': break
                        time.sleep(.2)
                    check(lua('exists,'+oid)=='gone','Fixture-owned structure removed from native world '+oid)
            finally:
                script.write_text(script.read_text().replace(helper,''));console('reloadscreenplays')
                report['helper_removed']=helper not in script.read_text()
        if session:
            native_log=ROOT/'runtime/server/livecombat'/session/'client.log'
            if native_log.exists(): report['camp_native_messages']=re.findall(r'@camp:[a-z_]+',native_log.read_text())
            refresh();out=call('/session/logout',live_session_id=session,request_id='placelogout_'+secrets.token_hex(8),**pose())
            check(out.get('saved') and out.get('session_closed'),'Disposable fixture saved and session closed')
        write();print(json.dumps({'passed':report['passed'],'checks':len(report['checks']),'evidence':str(OUT)}),flush=True)

if __name__=='__main__': main()
