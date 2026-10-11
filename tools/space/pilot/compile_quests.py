#!/usr/bin/env python3
"""Compile supplied, pinned pilot mission tables into Core3 quest definitions.

Generated content stays in runtime/. Missing references fail closed and are
reported, never replaced by an instantly completed or invented mission.
"""
import argparse
import collections
import csv
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CLASSES = dict(patrol='SpacePatrolScreenplay', assassinate='SpaceAssassinateScreenplay',
 destroy='SpaceDestroyScreenplay', destroy_duty='SpaceDutyDestroyScreenplay',
 destroy_surpriseattack='SpaceSurpriseAttackScreenplay', escort='SpaceEscortScreenplay',
 escort_duty='SpaceDutyEscortScreenplay', inspect='SpaceInspectScreenplay',
 recovery='SpaceRecoveryScreenplay', recovery_duty='SpaceDutyRecoveryScreenplay',
 rescue='SpaceRescueScreenplay', rescue_duty='SpaceDutyRescueScreenplay',
 space_battle='PilotObjectiveQuest', survival='PilotObjectiveQuest',
 delivery='PilotObjectiveQuest', delivery_no_pickup='PilotObjectiveQuest', patrol_duty='SpaceDutyPatrolScreenplay')

def rows(path):
    with path.open(newline='') as stream:
        data=list(csv.reader(stream,delimiter='\t'))
    return [dict(zip(data[0], row)) for row in data[2:] if any(row)]

def lua(value):
    if isinstance(value,dict): return '{'+','.join('['+json.dumps(k)+']='+lua(v) for k,v in value.items())+'}'
    if isinstance(value,list): return '{'+','.join(map(lua,value))+'}'
    if isinstance(value,bool):return 'true' if value else 'false'
    return json.dumps(value,ensure_ascii=True)

class QuestCompiler:
    def __init__(self,source):
        self.source=source; self.points={};self.provenance=[];self.repairs=[];self.spawns={}
        self.ship_types={p.stem for p in (ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/ship_mobile/ships').glob('*.lua')}
        for file in sorted((source/'buildout').glob('*.tab')):
            self.provenance.append({'path':str(file.relative_to(source)), 'sha256':hashlib.sha256(file.read_bytes()).hexdigest()})
            for row in rows(file):
                vars=row.get('strObjVars','')
                spawn_names=re.findall(r'strSpawns_mangled.segment.\d+\|\d+\|([^|]+)',vars)
                for names in spawn_names:
                    for name in names.split(':'):
                        if name:self.spawns.setdefault((file.stem,name),[]).append({'patrolPointName':name,'zoneName':file.stem,'x':float(row['fltPX']),'z':float(row['fltPY']),'y':float(row['fltPZ']),'radius':150})
                for key in ('nav_name','strSpawnerName'):
                    match=re.search(r'(?:^|\|)'+key+r'\|\d+\|([^|]+)',row.get('strObjVars',''))
                    if match:
                        self.points[file.stem+':'+match[1]]={'patrolPointName':match[1], 'zoneName':file.stem,
                            'x':float(row['fltPX']), 'z':float(row['fltPY']), 'y':float(row['fltPZ']), 'radius':150}
    def compile(self,kind,name):
        file=self.source/'quest_tables'/kind/(name+'.tab'); data=rows(file); first=data[0]
        self.provenance.append({'path':str(file.relative_to(self.source)), 'sha256':hashlib.sha256(file.read_bytes()).hexdigest()})
        col=lambda key:[r[key] for r in data if r.get(key)]
        number=lambda key,default=0:float(first.get(key) or default)
        def points(key):
            out=[]
            for i,ref in enumerate(col(key)):
                if ref not in self.points:
                    if kind=='destroy':
                        self.repairs.append({'quest':kind+':'+name,'omitted_defunct_waypoint':ref});continue
                    raise ValueError('Missing original navigation point '+ref)
                out.append(dict(self.points[ref],patrolNumber=i+1,escortNumber=i+1))
            return out
        def waves(prefix='attackShips'):
            return [col(prefix+str(i)) for i in range(1,9) if col(prefix+str(i))]
        def counted(values):return [{'shipName':n,'count':c} for n,c in collections.Counter(values).items()]
        q={'className':kind+'_'+name,'questType':kind,'questName':name,'questZone':first['questZone'],
           'creditReward':0,'itemReward':[], 'sourceAutoReward':number('autoReward')}
        ship_fields=['shipList','targetShipType','targetShipTypes','targetEscort','escortShipType','escortShipTypes','shipType','bossType','allyForce','enemyForce','pickupShip','deliveryShip']+[f'attackShips{i}' for i in range(1,9)]+[f'shipType{i}' for i in range(1,9)]
        for row in data:
            for field in ship_fields:
                value=row.get(field)
                if value and value not in self.ship_types:
                    if kind=='destroy' and field=='shipList':
                        self.repairs.append({'quest':kind+':'+name,'omitted_unregistered_optional_kill_type':value})
                        row[field]=''
                    else:raise ValueError('Unregistered native ship '+value)
        base=CLASSES[kind];timers=set();visited=set()
        while base and base not in visited:
            visited.add(base)
            script=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/space'/(base+'.lua')
            if not script.exists():break
            native=script.read_text();timers.update(re.findall(r'self.className,\s*"([^"]+)"',native))
            parent=re.search(r'\w+\s*=\s*(\w+):new',native);base=parent[1] if parent else None
        q['sourceTimedMethods']=sorted(timers | {'tick'})
        split=first.get('triggerSplitCondition','');target=first.get('triggerArg','').lower()
        q['sourceTrigger']=dict(condition=split,target=target,alternate=first.get('triggerArg2','').lower(),
            endsMission=number('triggerEndsMission'),on=number('triggerOn'),delay=number('triggerDelay'))
        if target:
            t,n=target.split(':');q.update(sideQuest=True,sideQuestType=t,sideQuestName=n,
                sideQuestSplitType={'success':1,'failure':2,'both':3,'triggerOn':4 if kind in ('patrol','patrol_duty') else 1}.get(split,0),
                sideQuestDelay=number('triggerDelay',2),sideQuestPatrolStart=number('triggerOn'))
            fail=first.get('triggerArg2','').lower() if split=='both' else target if split=='failure' else None
            if fail:q['sideFailQuestType'],q['sideFailQuestName']=fail.split(':')
        if kind in ('patrol','patrol_duty'):
            q['patrolPoints']=[dict(point) for _ in range(max(1,int(number('laps',1)))) for point in points('navPoints')]
            for i,p in enumerate(q['patrolPoints']):p['patrolNumber']=i+1
            assert q['patrolPoints'],'Empty patrol'
        elif kind=='assassinate':
            q.update(assassinateSpawns={'target':first['targetShipType'],'escorts':col('targetEscort')},
                targetPatrols=points('escortPath'),arrivalDelay=number('targetArrivalDelay',5),sourceMustDestroyEscort=bool(number('mustDestroyEscort')))
        elif kind=='destroy':
            locations=points('validSpawns')
            if col('validSpawns') and not locations:raise ValueError('No surviving original destroy waypoint')
            assert col('shipList'),'No registered eligible kill targets'
            q.update(killsRequired=number('killCount',1),shipTypes=col('shipList'),shipLocations=locations)
        elif kind=='destroy_duty':
            q.update(totalLevels=number('levelsPerDuty',1),totalRounds=number('roundsPerLevel',1),totalWaves=number('wavesPerRound',1),
                shipTypes=waves('shipType'),bossShip=first['bossType'],creditReward=number('reward'))
        elif kind=='destroy_surpriseattack':
            q['surpriseAttackShips']={'zone':first['questZone'],'spawns':[{'shipName':r['shipType'],'count':int(r.get('shipCount') or 1)} for r in data if r.get('shipType')]}
        elif kind in ('escort','escort_duty'):
            q.update(escortShips=col('escortShipType' if kind=='escort' else 'escortShipTypes'),
                escortPoints=points('escortPath' if kind=='escort' else 'escortPoints'),attackShips=waves(),
                attackDelay=number('attackPeriod',90),spawnAttackWaves=bool(waves()),checkPlayerDistance=not bool(number('noDistancePolling')),
                creditReward=number('reward'),creditKillBonus=number('killReward'),sourceDestroyIsSuccess=bool(number('destroyIsSuccess')))
        elif kind=='inspect':
            locations=points('validSpawns')
            if not locations:
                for ship in col('shipList'):locations.extend(self.spawns.get((first['questZone'],ship),[]))
                if locations:self.repairs.append({'quest':kind+':'+name,'inspect_location':'original matching ship spawner'})
            if not locations:raise ValueError('No original location for inspection target')
            q.update(inspectTargets=col('shipList'),inspectCargo=first.get('cargo',''),targetLocation=locations[0])
        elif kind in ('recovery','recovery_duty'):
            q.update(recoverShip=col('targetShipType' if kind=='recovery' else 'targetShipTypes')[0],
                preRecoveryPoints=points('escortPath'),recoveryPoints=points('recoveryPath'),escortShips=col('targetEscort'),
                recoveryConversationMobile=first.get('recoveryAppearance',''),arrivalDelay=number('targetArrivalDelay',5),
                recoveryDelay=number('targetRecoverTime',30),attackDelay=number('attackPeriod',90),attackShips=waves(),creditReward=number('reward'))
        elif kind in ('rescue','rescue_duty'):
            path=points('recoveryPath')
            q.update(rescueShip=col('targetShipType' if kind=='rescue' else 'targetShipTypes')[0],rescueLocation=path[0],
                escortPoints=path,arrivalDelay=number('targetArrivalDelay',5),attackDelay=number('attackPeriod',50),
                attackShips=[counted(w) for w in waves()],creditReward=number('reward'))
        else:
            q['sourceRows']=data
            if kind=='space_battle':
                assert col('enemyForce'),'Battle has no enemies'
                q.update(objectivePoints=points('battlePoint'),allies=col('allyForce'),enemies=col('enemyForce'))
            elif kind=='survival':q.update(objectivePoints=points('transmissionPoint'),attackShips=waves())
            else:q.update(objectivePoints=points('pickupPoint')+points('deliveryPoint'),attackShips=waves())
            expected=2 if kind=='delivery' else 1
            if len(q['objectivePoints'])!=expected:raise ValueError(f'{kind} requires {expected} objective points')
            if kind=='survival' and number('totalTransmissionTime')+number('transmissionStartDelay')<=0:
                raise ValueError('Survival requires a positive transmission duration')
        return q

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--source',type=Path,default=ROOT/'runtime/reference/pilot-progression');p.add_argument('--out',type=Path,default=ROOT/'runtime/server/pilot-source');a=p.parse_args()
    c=QuestCompiler(a.source); pending=set();query_refs=set()
    programs=set(json.loads((ROOT/'server/jtl/pilot/trainers.json').read_text()).values())
    for f in a.out.glob('*.lua'):
        if f.stem not in programs:continue
        text=f.read_text();pending.update(re.findall(r'"space_quest.grantQuest",player,"([^"]+)","([^"]+)"',text))
        query_refs.update(re.findall(r'"space_quest\.\w+",player,"([^"]+)","([^"]+)"',text))
    grants=sorted(pending);done={};errors={}
    while pending:
        kind,name=min(pending);pending.remove((kind,name));name=name.lower();key=kind+':'+name
        if key in done or key in errors:continue
        try:
            q=c.compile(kind,name);done[key]=q
            for target in (q['sourceTrigger']['target'],q['sourceTrigger']['alternate']):
                if target:pending.add(tuple(target.split(':')))
        except (FileNotFoundError,KeyError,IndexError,ValueError,AssertionError) as e:errors[key]=str(e)
    # A mission cannot be offered when a required downstream objective is absent.
    blocked=set(errors)
    while True:
        more={key for key,q in done.items() if any(t in blocked for t in (q['sourceTrigger']['target'],q['sourceTrigger']['alternate']))}
        if more<=blocked:break
        blocked|=more
    code=['-- Generated from original mission tables; do not edit.','PilotQuests.definitions='+lua(done),'PilotQuests.blocked='+lua({k:errors.get(k,'A chained objective is unavailable') for k in sorted(blocked)})]
    for key,q in sorted(done.items()):
        code.append('PilotQuests.bind('+json.dumps(key)+','+CLASSES[q['questType']]+')')
    a.out.mkdir(parents=True,exist_ok=True);(a.out/'quests.lua').write_text('\n'.join(code)+'\n')
    report={'direct_grants':len(grants),'compiled':len(done),'blocked':sorted(blocked),'errors':errors,'sources':c.provenance,'repairs':c.repairs,
            'grants':{':'.join(k):':'.join(k) not in blocked for k in grants},'query_only_missing':sorted(':'.join(k) for k in query_refs if ':'.join(k) not in done and ':'.join(k) not in errors)}
    (a.out/'quests.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({k:report[k] for k in ('direct_grants','compiled','errors')}))
if __name__=='__main__':main()
