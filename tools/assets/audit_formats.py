#!/usr/bin/env python3
"""Read-only audit of retail resource versions relevant to Core3 startup."""
from pathlib import Path
import json,struct
from swg_formats import TreSet,parse_iff,cstring
ROOT=Path(__file__).resolve().parents[2]
def main():
    tre=TreSet(ROOT/'runtime/asset_sources/active_tre' if (ROOT/'runtime/asset_sources/active_tre').exists() else ROOT/'runtime/asset_sources/extracted/base/tre')
    path='abstract/slot/slot_definition/slot_definitions.iff'
    root=parse_iff(tre.read(path));data=root.first('DATA').data
    if root.tag not in ('0005','0006'):raise ValueError('Unsupported slot version '+root.tag)
    pos=0;slots=[]
    while pos<len(data):
        name,pos=cstring(data,pos);flags=list(data[pos:pos+3]);pos+=3
        alternate,pos=cstring(data,pos)
        unk4=struct.unpack_from('<H',data,pos)[0];pos+=2
        unk5=data[pos];pos+=1
        unk6=data[pos] if root.tag=='0006' else 0
        if root.tag=='0006':pos+=1
        assert name and name[0].isalpha()
        slots.append({'name':name,'flags':flags,'alternate':alternate,'unk4':unk4,'unk5':unk5,'unk6':unk6})
    assert pos==len(data)
    assert {'inventory','datapad','ghost','bank'}<=set(s['name'] for s in slots)
    result={'slot_path':path,'slot_archive':tre.entries[path][0].name,'slot_version':root.tag,'slot_payload_bytes':len(data),'slot_records':len(slots),'slot_schema':'cstring name; 3 u8; cstring alternate; u16 little endian; u8; optional u8 only in 0006','slots':slots,'critical_formats':[]}
    critical=ROOT/'runtime/server/critical-assets.json'
    if critical.exists():
        for resource in json.loads(critical.read_text()):
            p=resource['path']
            if p not in tre.entries:continue
            r=parse_iff(tre.read(p));forms=[]
            def walk(n,parent=''):
                if not n.children:return
                form=parent+n.tag
                if form not in forms:forms.append(form)
                for c in n.children:walk(c,form+'/')
            walk(r)
            result['critical_formats'].append({'path':p,'archive':tre.entries[p][0].name,'root':r.tag,'forms':forms})
    target=ROOT/'runtime/asset_reports/retail-format-audit.json';target.parent.mkdir(parents=True,exist_ok=True);target.write_text(json.dumps(result,indent=2))
    print(json.dumps({'report':str(target),'slot_version':root.tag,'slot_records':len(slots),'slot_payload_bytes':len(data),'critical_resources':len(result['critical_formats'])},indent=2))
if __name__=='__main__':main()
