#!/usr/bin/env python3
"""Resolve original vehicle saddle art and player hardpoints from supplied TREs.

The invisible pv_* skeleton is NOT the vehicle body. Passenger seats and VR
controls extend the pre-CU single-rider tables; those offsets are labelled below.
"""
from pathlib import Path
import sys,json,struct,hashlib,argparse
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/assets'))
from prepare_characters import CharacterImporter
from static_assets import StaticAssets
from interior_layout import template_properties
from character_formats import datatable
from prepare_corpses import matrix
from character_animations import load_lat,resolve,decode_clip
from swg_formats import parse_iff,cstring
NAMES=('speederbike','speederbike_swoop','speederbike_flash','landspeeder_x34','landspeeder_x31','landspeeder_av21')
from yoke_geometry import steering_component
EXPORT_VERSION=3
def source_signature():
 paths=[Path(__file__),Path(__file__).with_name("yoke_geometry.py"),ROOT/'tools/assets/static_assets.py',ROOT/'tools/assets/shader_alpha.py',ROOT/'runtime/assets/characters/catalog.json']+sorted((ROOT/'runtime/assets/active_tre').glob('*.tre'))
 return hashlib.sha256(json.dumps([(str(p.relative_to(ROOT)),p.stat().st_size,p.stat().st_mtime_ns) for p in paths]).encode()).hexdigest()
def prepared(out,signature,required):
 try:
  catalog=json.loads((out/'catalog.json').read_text())
  if catalog.get('export_version')!=EXPORT_VERSION or catalog.get('source_signature')!=signature or catalog.get('failures'):return False
  for template in required:
   descriptor=catalog['items'][template];model=json.loads((out/descriptor['model']).read_text())
   shared=template.rsplit('/',1)[0]+'/shared_'+template.rsplit('/',1)[1]
   if catalog.get('aliases',{}).get(shared)!=template:return False
   if descriptor.get('status')!='ready' or not descriptor.get('seats') or not descriptor.get('controls') or not model.get('surfaces'):return False
   if any(not surface.get('vertices') or not surface.get('indices') or not (out/surface['texture']).is_file() for surface in model['surfaces']):return False
  return True
 except (OSError,ValueError,KeyError,TypeError):return False
def main():
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--ensure',action='store_true');parser.add_argument('--template',action='append',default=[],help='Require this exact owned native vehicle template; never substitute another hull');args=parser.parse_args()
 out=ROOT/'runtime/assets/vehicles';signature=source_signature();required=['object/mobile/vehicle/'+n+'.iff' for n in NAMES]+args.template
 unsupported=[p for p in args.template if p not in required[:len(NAMES)]]
 if unsupported:raise SystemExit('Native vehicle templates outside prepared source saddle/VR seat support: '+', '.join(unsupported))
 if args.ensure and prepared(out,signature,required):print('All six original vehicle models, textures and native saddle descriptors are ready.');return
 imp=CharacterImporter(ROOT/'runtime/assets/active_tre',out)
 static=StaticAssets(ROOT/'runtime/assets/active_tre',out);static.t=imp.t;static.dependencies=imp.dependencies
 logical={r['sat_or_skt_name']:r['logical_saddle_name'] for r in datatable(imp.read('datatables/mount/logical_saddle_name_map.iff'))}
 saddles={r['logical_saddle_name']:r for r in datatable(imp.read('datatables/mount/saddle_appearance_map.iff'))}
 poses={r['saddle_appearance_name']:r['rider_pose'] for r in datatable(imp.read('datatables/mount/rider_pose_map.iff'))}
 catalog={'schema_version':1,'export_version':EXPORT_VERSION,'source_signature':signature,'coordinate_system':'Godot XYZ Y-up -Z forward, original meters','items':{},'aliases':{},'failures':[]}
 for name in NAMES:
  template='object/mobile/vehicle/'+name+'.iff';shared=template.replace('/'+name+'.iff','/shared_'+name+'.iff')
  try:
   props=template_properties(imp.read,shared);saddle=saddles[logical[props['appearanceFilename']]];appearance=saddle['saddle_appearance_name']
   lod=cstring(parse_iff(imp.read(appearance)).first('NAME').data)[0];points={}
   for h in parse_iff(imp.read(lod)).walk('HPNT'):
    hardpoint_matrix=struct.unpack_from('<12f',h.data);key=cstring(h.data,48)[0]
    points[key]=[hardpoint_matrix[3],hardpoint_matrix[7],-hardpoint_matrix[11]]
   driver=points['player'];bike=name in ('speederbike','speederbike_swoop')
   # Pre-CU ships one player hardpoint. The second visible cockpit seat is
   # symmetric on these landspeeders; never invent a pillion on single bikes.
   seats=[{'id':'driver','position':driver,'source':'original player hardpoint','rider_pose':poses[appearance]}]
   if not bike:seats.append({'id':'passenger','position':[-driver[0],driver[1],driver[2]],'source':'VR extension: mirrored visible cockpit seat','rider_pose':poses[appearance]})
   controls=[[driver[0]+x,driver[1]+.30,driver[2]-.47] for x in (-.26,.26)]
   surfaces=[];meshes=[]
   for part in static.resolve(appearance):
    meshes.append(part['mesh']);data=json.loads((out/static.meshes[part['mesh']]['path']).read_text());surfaces+=data['surfaces']
   if not surfaces:raise ValueError('No original saddle triangles')
   vertices=[s['vertices'][i:i+3] for s in surfaces for i in range(0,len(s['vertices']),3)]
   lo=[min(p[i] for p in vertices) for i in range(3)];hi=[max(p[i] for p in vertices) for i in range(3)]
   model={'surfaces':surfaces,'source_appearance':appearance,'bounds_min':lo,'bounds_max':hi,'material_pipeline':'original_static'}
   relative='models/'+name+'.json';imp.write(relative,model)
   catalog['items'][template]={'status':'ready','template':template,'model':relative,'appearance':appearance,'source_pv_appearance':props['appearanceFilename'],'source_saddle':saddle,'source_hardpoints':points,'bounds_min':lo,'bounds_max':hi,'seats':seats,'controls':controls,'control_source':'VR interaction offsets relative to original driver hardpoint; tunable','kind':'bike' if bike else 'landspeeder','material_pipeline':'original_static'}
   catalog['aliases'][shared]=template
  except Exception as e:catalog['failures'].append({'template':template,'error':str(e)})
 catalog['rider_poses']={}
 characters=json.loads((ROOT/'runtime/assets/characters/catalog.json').read_text())
 for race,data in characters['races'].items():
  try:
   model=json.loads((ROOT/'runtime/assets/characters'/data['body']).read_text());bones=model['bones'];names={b['name']:i for i,b in enumerate(bones)}
   lat=model['animation_graph']['lat_bindings'][0]['lat'];_,entries=load_lat(imp,lat)
   exported={}
   for pose in ('vehicle_landspeeder','vehicle_speeder_bike','vehicle_swoop_bike'):
    leaf=resolve(entries['loop_riding'],{'rider_pose':pose,'gender':'f' if race.endswith('_female') else 'm'})[0]
    clip=decode_clip(imp,leaf['source'],bones,names)
    exported[pose]={'source':leaf['source'],'source_sha256':hashlib.sha256(imp.read(leaf['source'])).hexdigest(),'tracks':[{'name':t['name'],'position':t['positions'][0][1:],'rotation':t['rotations'][0][1:]} for t in clip['tracks']]}
   catalog['rider_poses'][race]=exported
  except Exception as e:catalog['failures'].append({'race':race,'phase':'rider_pose','error':str(e)})
 # Derive grip locations from the original human rider pose. This aligns
 # the invisible interaction zones with the source handles/wheel, not guessed
 # standing-controller offsets. Other avatar sizes still use physical reach.
 model=json.loads((ROOT/'runtime/assets/characters'/characters['races']['human_male']['body']).read_text())
 for d in catalog['items'].values():
  tracks={t['name']:t for t in catalog['rider_poses']['human_male'][d['seats'][0]['rider_pose']]['tracks']};posed=[]
  for bone in model['bones']:
   track=tracks.get(bone['name'],{});m=matrix(track.get('position',bone['rest_position']),track.get('rotation',bone['rest_rotation']))
   if bone['parent']>=0:m=posed[bone['parent']]@m
   posed.append(m)
  root=tracks['root']['position'];offset=[d['seats'][0]['position'][i]-root[i] for i in range(3)]
  d['controls']=[[float(posed[next(i for i,b in enumerate(model['bones']) if b['name']==name)][j,3])+offset[j] for j in range(3)] for name in ('hold_l','hold_r')]
  d['control_source']='Original human loop_riding hold_l/hold_r transforms, translated from source root to model driver hardpoint'
  d['control_bases']=[[[float(posed[next(i for i,b in enumerate(model['bones']) if b['name']==name)][row,col]) for row in range(3)] for col in range(3)] for name in ('hold_l','hold_r')]
  if d['kind']=='landspeeder':
   source_model=json.loads((out/d['model']).read_text())
   d['steering_geometry']=steering_component(source_model,d['controls'])
   d['steering_geometry']['model_sha256']=hashlib.sha256((out/d['model']).read_bytes()).hexdigest()
 catalog['dependencies']=imp.dependencies;catalog['conversion_failures']=static.failures
 imp.write('catalog.json',catalog)
 print(json.dumps({'vehicles':len(catalog['items']),'failures':catalog['failures']}))
 if catalog['failures']:raise SystemExit(1)
 if not prepared(out,signature,required):raise SystemExit('Converted vehicle catalog failed original model/texture/seat coverage validation')
if __name__=='__main__':main()
