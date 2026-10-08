#!/usr/bin/env python3
"""Audit explicit Lua crafting ranges and generate native armour references.

No Lua execution, asset copies, item mutation or database access. Optional
enhancements/layers are retained as bounded excess/channel credit at runtime.
"""
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT/'vendor/Core3/MMOCoreORB/bin/scripts'

def array(text, name):
    found = re.search(r'\b'+name+r'\s*=\s*\{([^}]*)\}', text)
    if not found: return []
    return [v.strip().strip('"') for v in found[1].split(',') if v.strip()]

def source(path):
    return re.sub(r'--[^\n]*', '', path.read_text())

def ranges(text):
    keys=array(text,'experimentalSubGroupTitles')
    low=array(text,'experimentalMin'); high=array(text,'experimentalMax')
    if len(keys)!=len(low) or len(keys)!=len(high): raise ValueError('Mismatched experimental arrays')
    return {k:(float(a),float(b)) for k,a,b in zip(keys,low,high)}

def generate():
    config=json.loads((ROOT/'server/combat/armour_balance.json').read_text())
    recipes={}
    for path in sorted((SCRIPTS/'object/draft_schematic').rglob('*.lua')):
        text=source(path)
        target=re.search(r'targetTemplate\s*=\s*"([^"]+)"',text)
        if not target: continue
        slots=array(text,'ingredientSlotType'); types=array(text,'resourceTypes'); contributions=array(text,'contribution')
        if not (len(slots)==len(types)==len(contributions)): continue
        components=[]
        for slot,name,weight in zip(slots,types,contributions):
            if slot not in ('1','2'): continue # optional layers/enhancements are separate
            if not name.startswith('object/'): continue
            component=SCRIPTS/name.replace('/shared_','/').replace('.iff','.lua')
            if not component.exists(): raise ValueError('Missing required component '+str(component))
            components.append((component,float(weight)/100))
        # Alternative recipes must not silently replace the ordinary recipe.
        recipes.setdefault(target[1],components)
    rows=[]; fallback=[]
    for path in sorted((SCRIPTS/'object/tangible/wearables/armor').rglob('*.lua')):
        text=source(path)
        registration=re.search(r'ObjectTemplates:addTemplate\([^,]+,\s*"([^"]+)"',text)
        if not registration or '/shared_' in registration[1]: continue
        kind=config['classes'][path.parent.name]
        values=ranges(text); combined=dict(values)
        combine=dict(zip(array(text,'experimentalSubGroupTitles'),array(text,'experimentalCombineType')))
        target=registration[1]
        for component,weight in recipes.get(target,[]):
            # Ordinary segment base values; optional component bonuses are not
            # included in the normalization denominator (they retain credit).
            for key,(low,high) in ranges(source(component)).items():
                if key in combined and combine.get(key) in ('1','2'):
                    a,b=combined[key]; combined[key]=(a+low*weight,b+high*weight)
        base=combined.get('armor_effectiveness',(0,80))
        special=combined.get('armor_special_effectiveness',base)
        if base[0]==base[1]: base=(0,80)
        if special[0]==special[1]: special=base
        if 'armor_effectiveness' not in values: fallback.append(target)
        enc=[combined.get('armor_'+pool+'_encumbrance',(0,100)) for pool in ('health','action','mind')]
        rows.append(dict(path=target,kind=kind,minimum=base[0],maximum=base[1],specialMinimum=special[0],specialMaximum=special[1],
                         encumbranceBest=sum(min(v) for v in enc),encumbranceWorst=sum(max(v) for v in enc)))
    if not rows: raise ValueError('No armour references')
    return rows,fallback

def install():
    rows,fallback=generate()
    model=(ROOT/'server/combat/ArmourModel.h').read_bytes()
    revision=hashlib.sha256(model+json.dumps(rows,sort_keys=True).encode()).hexdigest()
    out=ROOT/'vendor/Core3/MMOCoreORB/src/server/zone/objects/tangible/wearables'
    lines=['#pragma once','#include "ArmourModel.h"','namespace swgxr { namespace armour {',
           f'constexpr const char* REVISION = "{revision}";', 'constexpr ArmourReference REFERENCES[] = {']
    for row in rows:
        lines.append('{'+json.dumps(row['path'])+','+','.join(str(row[k]) for k in ('kind','minimum','maximum','specialMinimum','specialMaximum','encumbranceBest','encumbranceWorst'))+'},')
    lines+=['};','} }','']
    for name,data in [('ArmourModel.h',model),('ArmourReferences.h','\n'.join(lines).encode())]:
        path=out/name
        if not path.exists() or path.read_bytes()!=data: path.write_bytes(data)
    report=ROOT/'runtime/evidence/armour-reference-audit.json'
    report.parent.mkdir(parents=True,exist_ok=True)
    report.write_text(json.dumps(dict(revision=revision,references=rows,template_fallbacks=fallback),indent=2)+'\n')
    print(f'Armour v1: {len(rows)} references, {len(fallback)} explicit template fallbacks; {revision[:12]}')

if __name__=='__main__': install()
