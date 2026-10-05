#!/usr/bin/env python3
"""Convert a bounded Mos Eisley stage from locally supplied SWG TRE archives.

Only standard static mesh, LOD, portalized-building and basic shader data are
converted. No game data is fetched. Output is an ignored, user-local cache.
"""
from pathlib import Path
import argparse, hashlib, io, json, math, struct
from PIL import Image
from swg_formats import TreSet, parse_iff, cstring, refs
from archive_policy import CORE3_TRE_PRIORITY

ROOT=Path(__file__).resolve().parents[2]

def mirror(v):return [v[0],v[1],-v[2]]
def qmirror(q): # SWG stored w,x,y,z -> mirrored Godot x,y,z,w
    w,x,y,z=q;return [-x,-y,z,w]
def qrot(q,v):
    w,x,y,z=q;vx,vy,vz=v
    tx=2*(y*vz-z*vy);ty=2*(z*vx-x*vz);tz=2*(x*vy-y*vx)
    return [vx+w*tx+y*tz-z*ty,vy+w*ty+z*tx-x*tz,vz+w*tz+x*ty-y*tx]

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--tre-dir',type=Path,default=(ROOT/'runtime/assets/active_tre' if (ROOT/'runtime/assets/active_tre').exists() else ROOT/'runtime/assets/tre'))
    ap.add_argument('--out',type=Path,default=ROOT/'runtime/assets/mos_eisley')
    ap.add_argument('--radius',type=float,default=180)
    args=ap.parse_args();args.out.mkdir(parents=True,exist_ok=True)
    from static_assets import StaticAssets
    assets=StaticAssets(args.tre_dir,args.out);t=assets.t
    read=assets.read;failures=assets.failures;dependencies=assets.dependencies
    context_resources=['terrain/tatooine.trn','terrain/mun_tato_starport.lay','appearance/mun_tato_starport_s01_u01.pob']
    context_resources.extend(sorted(set(refs(read(context_resources[-1])))))
    context_resources=[p for p in context_resources if p.endswith(('.trn','.lay','.pob','.flr'))]
    for resource in context_resources:
        destination=args.out/'source'/resource;destination.parent.mkdir(parents=True,exist_ok=True);destination.write_bytes(read(resource))
    (args.out/'source_context.json').write_text(json.dumps({'resources':context_resources,'status':'Original source provenance; dedicated authored collision is exported separately.','terrain_implemented':'Separate streamed terrain manifest'},indent=2))
    snapshot='snapshot/tatooine.ws';r=parse_iff(read(snapshot));names=r.first('OTNL').data[4:].split(b'\0');nodes=[]
    for source in r.walk('NODE'):
        d=source.first('DATA').data;oid,parent,tid,cell=struct.unpack_from('<4I',d)
        nodes.append({'id':oid,'parent':parent,'template':names[tid].decode(),'cell':cell,'q':struct.unpack_from('<4f',d,16),'p':struct.unpack_from('<3f',d,32)})
    starport=next(n for n in nodes if n['id']==1106368);origin=starport['p'];instances=[];selected=[];cells={}
    for node in nodes:
        if node['parent'] or math.hypot(node['p'][0]-origin[0],node['p'][2]-origin[2])>args.radius:continue
        if not node['template'].startswith(('object/building/','object/static/','object/tangible/')):continue
        try:
            placed,definitions,_=assets.place(node,origin);instances.extend(placed);cells.update(definitions);selected.append(node)
        except Exception as error:failures.append({'resource':node['template'],'phase':'appearance','error':str(error)})
    from interior_layout import expand_layouts
    for node in expand_layouts(assets,selected):
        if not node['template'].startswith(('object/building/','object/static/','object/tangible/')):continue
        try:
            placed,definitions,_=assets.place(node,origin);instances.extend(placed);cells.update(definitions)
        except Exception as error:failures.append({'resource':node['template'],'phase':'interior_layout_appearance','error':str(error)})
    mesh_cache={key:json.loads((args.out/value['path']).read_text()) for key,value in assets.meshes.items()}
    textures={surface.get('texture','') for mesh in mesh_cache.values() for surface in mesh['surfaces']}
    # Actual foyer4 spawn verified by Godot grounding and wall-collision smoke.
    # Local Godot coordinates, relative to the snapshot starport origin.
    spawn=[-60.0,2.0,10.0];yaw=0.0
    archive_names=sorted(p.name for p in t.archives)
    missing_archives=[name for name in CORE3_TRE_PRIORITY if name not in archive_names]
    media_warning=('All 51 Core3 pre-CU archives are present; later CU archives excluded.' if not missing_archives else f'Incomplete Core3 pre-CU archive set: {len(missing_archives)} expected archives absent.')
    warnings=[media_warning,'Static stage only: no animated doors, NPCs, effects or original terrain synthesis.','Authored collision extents and all POB/appearance floors exported; NULL declares no blocking collider; missing or unsupported declarations explicitly report visual-mesh fallback.','Material conversion uses diffuse textures only; original multi-layer shaders are approximated.']
    scene={'schema_version':2,'collision_schema_version':1,'collisions':assets.collisions,'name':'Mos Eisley starport — original media stage','coordinate_system':'Godot Y-up right-handed; SWG Z mirrored; positions relative to origin','origin':list(origin),'spawn':spawn,'spawn_yaw':yaw,'meshes':mesh_cache,'instances':instances,'cells':cells,'warnings':warnings,'provenance':{'snapshot':snapshot,'starport_object_id':1106368,'spawn_cell':'foyer4','spawn_validation':'Godot grounded at y=0.639323; 2.6m locomotion and imported wall stop verified','source_media':'User supplied local installation media','tre_directory':str(args.tre_dir.resolve()),'archives':archive_names,'missing_expected_archives':missing_archives,'dependencies':dependencies},'statistics':{'meshes':len(mesh_cache),'instances':len(instances),'surfaces':sum(len(m['surfaces']) for m in mesh_cache.values()),'triangles':sum(sum(len(s['indices'])//3 for s in mesh_cache[i['mesh']]['surfaces']) for i in instances),'textures':len(textures-{''}),'cells':len(cells),'collision_definitions':len(assets.collisions),'conversion_failures':len(failures)}}
    (args.out/'collision_report.json').write_text(json.dumps(assets.collision_report(instances),indent=2))
    (args.out/'scene.json').write_text(json.dumps(scene,separators=(',',':')))
    (args.out/'conversion_report.json').write_text(json.dumps({'statistics':scene['statistics'],'warnings':warnings,'failures':failures,'selected_world_nodes':selected},indent=2))
    print(json.dumps({'scene':str(args.out/'scene.json'),'spawn':spawn,'statistics':scene['statistics'],'failures':failures[:15]},indent=2))

if __name__=='__main__':main()
