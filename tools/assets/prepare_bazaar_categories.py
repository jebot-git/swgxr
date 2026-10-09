#!/usr/bin/env python3
"""Export original GOT bazaar hierarchy with user-media localized labels.

The reference C++ header supplies numeric constants only; original labels remain
in ignored runtime data. Source NGE auction tree groups on 0xffffff00, sorts by
localized label, and places All first. No market inventory is manufactured.
"""
import argparse
import hashlib
import json
import re
import urllib.request
from pathlib import Path
from prepare_datapad import string_table
from prepare_services import ROOT, write
from swg_formats import TreSet

REFERENCE='https://github.com/SWG-Source/client-tools/blob/master/src/engine/shared/library/sharedGame/src/shared/objectTemplate/SharedObjectTemplate.h'
TREE_REFERENCE='https://github.com/SWG-Source/client-tools/blob/master/src/game/client/library/swgClientUserInterface/src/shared/page/SwgCuiAuctionFilter.cpp'
REFERENCE_COMMIT='949451032647e45e42c3aaef3f41b132c8af36e3'
REFERENCE_SHA256='fd028b3aed209cd40699b273adea9a4a9349404c72059488010b2e7e69e7a62a'
REFERENCE_RAW=f'https://raw.githubusercontent.com/SWG-Source/client-tools/{REFERENCE_COMMIT}/src/engine/shared/library/sharedGame/src/shared/objectTemplate/SharedObjectTemplate.h'


def reference_bytes(path):
    # Only a pinned public code enum is fetched. All art/data/STF labels still
    # come exclusively from the supplied local archives.
    if not path.exists():
        with urllib.request.urlopen(REFERENCE_RAW,timeout=30) as response:
            raw=response.read(100000)
        if hashlib.sha256(raw).hexdigest()!=REFERENCE_SHA256:
            raise ValueError('Pinned game-object enum source hash mismatch')
        path.parent.mkdir(parents=True,exist_ok=True)
        path.write_bytes(raw)
    return path.read_bytes()


def parse_types(text):
    rows={}; current=-1
    for line in text.splitlines():
        match=re.match(r'\s*GOT_([a-zA-Z0-9_]+)\s*(?:=\s*(0x[0-9a-fA-F]+|\d+))?\s*,',line)
        if not match: continue
        current=int(match[2],0) if match[2] else current+1
        rows[match[1]]=current
    if rows.get('none')!=0 or rows.get('weapon')!=0x20000 or rows.get('weapon_ranged_pistol')!=0x2000a:
        raise ValueError('Reference original game-object type enum is incompatible')
    return rows


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--types-header',type=Path,default=ROOT/'runtime/research/services/SharedObjectTemplate.h')
    p.add_argument('--tre-dir',type=Path,default=ROOT/'runtime/asset_sources/active_tre')
    p.add_argument('--out',type=Path,default=ROOT/'runtime/assets/services/bazaar_categories.json')
    args=p.parse_args()
    raw=reference_bytes(args.types_header); types=parse_types(raw.decode())
    tre=TreSet(args.tre_dir); label_path='string/en/got_n.stf'; label_bytes=tre.read(label_path); labels=string_table(label_bytes)
    available={name:ident for name,ident in types.items() if name in labels and name!='none'}
    roots={ident for ident in available.values() if ident&255==0}
    nodes=[{'id':0,'parent_id':-1,'label':'All','name':'none','children':[]}]
    for name,ident in available.items():
        parent=ident&0xffffff00
        if ident not in roots and parent not in roots: continue
        nodes.append({'id':ident,'parent_id':0 if ident in roots else parent,'label':labels[name],'name':name,'children':[]})
    nodes[1:]=sorted(nodes[1:],key=lambda n:(n['label'],n['id']))
    byid={n['id']:n for n in nodes}
    for node in nodes[1:]: byid[node['parent_id']]['children'].append(node['id'])
    result={'schema_version':1,'root_id':0,'mask':0xffffff00,'nodes':nodes,
            'source_policy':'Original labeled game-object categories/subtypes; Core3 auction category mask determines matching. Localized alphabetical order and All-first follow original client tree.',
            'limitations':['The later NGE commodity/got_exclusion table is absent from the supplied media; no arbitrary exclusion list was invented.',
                            'NGE per-template market leaves and server resource-class subtrees require corresponding native category filters and are not represented as invented numeric GOTs.'],
            'provenance':{'types_header':str(args.types_header.resolve()),'types_header_sha256':hashlib.sha256(raw).hexdigest(),'types_reference':REFERENCE_RAW if hashlib.sha256(raw).hexdigest()==REFERENCE_SHA256 else REFERENCE,'reference_commit':REFERENCE_COMMIT,'tree_reference':TREE_REFERENCE,
                          'labels':{'path':label_path,'archive':tre.entries[label_path][0].name,'sha256':hashlib.sha256(label_bytes).hexdigest()}}}
    write(args.out,result)
    print(json.dumps({'nodes':len(nodes),'root_categories':len(roots),'path':str(args.out)}))
if __name__=='__main__':main()
