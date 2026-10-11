#!/usr/bin/env python3
"""Reconcile later script keys with user-supplied Total Experience dialogue.
Existing strings remain original. Missing keys get authored functional labels
in a separate runtime map; no replacement proprietary media is downloaded.
"""
import argparse
import json
import re
import sys
from pathlib import Path
import javalang
from javalang import tree as T
from compile_quests import lua
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'tools/assets'))
from swg_formats import TreSet
from stf import string_table

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--source',type=Path,default=ROOT/'runtime/reference/pilot-progression');p.add_argument('--out',type=Path,default=ROOT/'runtime/server/pilot-source');a=p.parse_args()
    media=TreSet(ROOT/'runtime/asset_sources/active_tre');mapping=json.loads((ROOT/'server/jtl/pilot/trainers.json').read_text())
    skills=string_table(media.read('string/en/skl_n.stf'));missing={};options={};provenance=[]
    import hashlib
    for name in sorted(set(mapping.values())):
        resource='string/en/conversation/'+name+'.stf';raw=media.read(resource);strings=string_table(raw)
        provenance.append({'resource':resource,'archive':media.entries[resource][0].name,'sha256':hashlib.sha256(raw).hexdigest()})
        code=(a.out/(name+'.lua')).read_text();keys=set(re.findall(r'"(s_[0-9a-f]+)"',code));absent=keys-strings.keys()
        methods={m.name:m for m in javalang.parse.parse((a.source/(name+'.java')).read_text()).types[0].methods}
        def calls(node,seen=None):
            seen=set() if seen is None else seen;out=[]
            for _,n in node:
                if isinstance(n,T.MethodInvocation):
                    if n.member.startswith(name+'_action_') and n.member not in seen:
                        seen.add(n.member);out.extend(calls(methods[n.member],seen))
                    else:out.append(n)
            return out
        def literal(n):return n.value.strip('"') if isinstance(n,T.Literal) else ''
        for m in methods.values():
            for _,node in m:
                if not isinstance(node,T.IfStatement):continue
                condition=node.condition
                if not isinstance(condition,T.MethodInvocation) or condition.member!='equals' or condition.qualifier!='response':continue
                key=literal(condition.arguments[0])
                if key not in absent:continue
                effects=calls(node.then_statement);label='Continue briefing'
                grants=[n for n in effects if n.qualifier=='space_quest' and n.member=='grantQuest']
                training=[n for n in effects if n.qualifier=='skill' and n.member in ('purchaseSkill','noisyGrantSkill')]
                rewards=[n for n in effects if n.qualifier=='space_quest' and n.member=='giveReward']
                if grants:label='Accept assignment' if len(grants)==1 else 'Request next assignment'
                elif training:
                    skill=literal(training[0].arguments[1]);label='Enlist as a pilot' if skill.endswith('_novice') else 'Train '+skills.get(skill,'the next pilot skill')
                elif rewards:label='Collect mission reward'
                elif any(n.member=='grantNewbieShip' for n in effects):label='Request a training ship'
                elif any(n.member=='setSpaceFlag' and len(n.arguments)>1 and 'workingFor' in literal(n.arguments[1]) for n in effects):label='Accept transfer orders'
                elif any(n.member.startswith('npcEndConversation') for n in effects):label='Finish conversation'
                options['@conversation/'+name+':'+key]=label
        for key in sorted(absent):missing['@conversation/'+name+':'+key]=True
    titles={}
    for row in json.loads((a.out/'quests.json').read_text())['sources']:
        if not row['path'].startswith('quest_tables/'):continue
        key=row['path'].removeprefix('quest_tables/').removesuffix('.tab')
        strings=string_table(media.read('string/en/spacequest/'+key+'.stf'))
        titles[key.replace('/',':',1)]=strings.get('title',strings.get('title_d','Pilot assignment'))
    (a.out/'dialogue.lua').write_text('-- Supplied original titles plus authored compatibility labels.\nPilotSource.missingText='+lua(missing)+'\nPilotSource.optionLabels='+lua(options)+'\nPilotQuests.titles='+lua(titles)+'\n')
    (a.out/'dialogue.json').write_text(json.dumps({'missing_keys':len(missing),'authored_option_labels':options,'media':provenance,'excluded_later_rewards':'NGE ace medals are absent from supplied Total Experience media; original ace jacket/helmet/credit rewards remain.'},indent=2)+'\n')
    print(json.dumps({'missing_keys':len(missing),'authored_options':len(options),'quest_titles':len(titles)}))
if __name__=='__main__':main()
