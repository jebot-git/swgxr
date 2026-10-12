"""Convert original POB rooms and fixed children using native hull definitions."""
import hashlib
import json
import re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def prepare_pob(assets,out,name):
    shared='object/ship/player/shared_player_'+name+'.iff'
    source=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/object/ship/player'/('player_'+name+'.lua')
    text=re.sub(r'--[^\n]*','',source.read_text())
    # Decorated YT inherits its complete cell/child layout from the standard hull.
    if 'childObjects' not in text:
        parent=re.search(r'=\s*object_ship_player_player_(\w+):new',text)
        if parent:text=(source.with_name('player_'+parent[1]+'.lua')).read_text()
    before=len(assets.failures)
    instances,cells,_=assets.place(dict(id=1,parent=0,template=shared,p=[0,0,0],q=[1,0,0,0]),[0,0,0])
    if not instances or not cells:raise ValueError('Original POB cells missing: '+name)
    children=[];omitted=[]
    for index,(template,fields) in enumerate(re.findall(r'\{\s*templateFile\s*=\s*"([^"]+)"([^}]+)\}',text.split('childObjects = {',1)[1].split('launchPoints',1)[0]),2):
        values={k:float(v) for k,v in re.findall(r'(\w+)\s*=\s*(-?[0-9.]+)',fields)}
        cell=int(values['cellid']);path=Path(template)
        node=dict(id=index,parent=1,template=str(path.parent/('shared_'+path.name)),cell_id=f'1:{cell}',building_object_id=1,source_cell_object_id=cell,p=[values['x'],values['z'],values['y']],q=[values['ow'],values['ox'],values['oy'],values['oz']])
        try:
            placed,_,_=assets.place(node,[0,0,0]);instances.extend(placed)
        except ValueError as error:
            # Empty original decorative warning-light housing, not a room,
            # control station or interaction target. Keep the exact blocker.
            if str(error)!='Source archive entry is empty: appearance/pob_station_warning_lighthousing.apt':raise
            omitted.append(dict(template=template,error=str(error)))
        children.append(dict(template=template,cell_index=cell,source_position=node['p']))
    failures=assets.failures[before:]
    if failures:raise ValueError('Incomplete POB '+name+': '+repr(failures))
    ids={i['collision_id'] for i in instances if 'collision_id' in i}
    meshes={key:json.loads((out/assets.meshes[key]['path']).read_text()) for key in {i['mesh'] for i in instances}}
    stage=dict(schema_version=1,origin=[0,0,0],spawn=[0,0,0],instances=instances,cells=cells,meshes=meshes,collisions={key:assets.collisions[key] for key in ids},provenance=assets.dependencies.copy(),conversion_failures=[])
    target=out/('pob_'+name+'.json');target.write_text(json.dumps(stage,separators=(',',':')))
    return dict(kind='pob',descriptor=target.name,sha256=hashlib.sha256(target.read_bytes()).hexdigest(),shared_template=shared,original_fixtures=children,omitted_decorations=omitted,station_source=dict(path=str(source.relative_to(ROOT)),sha256=hashlib.sha256(source.read_bytes()).hexdigest()))
