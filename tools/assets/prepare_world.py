#!/usr/bin/env python3
"""Convert every source Tatooine static root placement into streamable chunks."""
from pathlib import Path
import argparse,collections,itertools,json,math,struct
from swg_formats import parse_iff
from static_assets import StaticAssets,mirror,qmirror,qrot
from character_formats import qmul
from interior_layout import expand_layouts
from planet_config import PLANETS, origin_for, path_for
ROOT=Path(__file__).resolve().parents[2]

def write(path,data):
 path.parent.mkdir(parents=True,exist_ok=True);temporary=path.with_suffix(path.suffix+'.tmp');temporary.write_text(json.dumps(data,separators=(',',':')));temporary.replace(path)

def refresh_interiors(args,assets,nodes,layout_nodes):
 manifest=json.loads((args.out/'world.json').read_text())
 if args.planet=='tatooine' and args.stage.exists():manifest['existing_stage_object_ids']=sorted({item['object_id'] for item in json.loads(args.stage.read_text()).get('instances',[])})
 assets.meshes.update(manifest['meshes']);assets.collisions.update(manifest['collisions']);assets.dependencies.update(manifest['provenance']['dependencies'])
 chunks={key:json.loads((args.out/info['path']).read_text()) for key,info in manifest['chunks'].items()};removed=0
 for chunk in chunks.values():
  before=len(chunk['instances']);chunk['instances']=[i for i in chunk['instances'] if 'source_layout' not in i];removed+=before-len(chunk['instances'])
 by_id={n['id']:n for n in nodes};origin=manifest['origin'];placed=[];skipped=[]
 for node in layout_nodes:
  if node['template'].startswith('object/soundobject/'):
   continue # Environment export owns original sound-object playback.
  try:
   instances,cells,limits=assets.place(node,origin)
   if not instances:raise ValueError('No static appearance')
   position=mirror([by_id[node['building_object_id']]['p'][i]-origin[i] for i in range(3)]);key=f'{math.floor(position[0]/manifest["chunk_size"])}:{math.floor(position[2]/manifest["chunk_size"])}'
   chunk=chunks[key];chunk['instances'].extend(instances);chunk['cells'].update(cells)
   for lo,hi in limits:
    chunk['bounds_min']=[min(chunk['bounds_min'][i],lo[i]) for i in range(3)];chunk['bounds_max']=[max(chunk['bounds_max'][i],hi[i]) for i in range(3)]
   placed.extend(instances)
  except Exception as error:skipped.append({'object_id':node['id'],'building_object_id':node['building_object_id'],'source_layout':node['source_layout'],'source_layout_index':node['source_layout_index'],'template':node['template'],'error':str(error)})
 for key,chunk in chunks.items():
  descriptor=manifest['chunks'][key];descriptor.update(bounds_min=chunk['bounds_min'],bounds_max=chunk['bounds_max'],instance_count=len(chunk['instances']),cell_count=len(chunk['cells']));write(args.out/descriptor['path'],chunk)
 manifest['meshes']=assets.meshes;manifest['collisions']=assets.collisions;manifest['provenance']['dependencies']=assets.dependencies
 stats=manifest['statistics'];layout_skipped=len(skipped)+sum(n['template'].startswith('object/soundobject/') for n in layout_nodes)
 stats['skipped_objects']=stats['skipped_objects']-stats.get('interior_layout_skipped_objects',0)+layout_skipped
 stats['conversion_failures']=stats['conversion_failures']-stats.get('interior_layout_conversion_failures',0)+len(assets.failures)
 stats.update(interior_layout_skipped_objects=layout_skipped,interior_layout_conversion_failures=len(assets.failures),placed_objects=len({i['object_id'] for chunk in chunks.values() for i in chunk['instances']}),authored_collision_definitions=sum(c['status']=='authored' for c in assets.collisions.values()),interior_layout_nodes=len(layout_nodes),interior_layout_instances=len(placed),interior_layout_buildings=len({n['building_object_id'] for n in layout_nodes}),instances=sum(len(c['instances']) for c in chunks.values()),meshes=len(assets.meshes),collision_definitions=len(assets.collisions),unique_triangles=sum(m['triangles'] for m in assets.meshes.values()),instanced_triangles=sum(assets.meshes[i['mesh']]['triangles'] for c in chunks.values() for i in c['instances']))
 report={'schema_version':1,'source_layout_nodes':len(layout_nodes),'placed_instances':len(placed),'placed_object_count':len({i['object_id'] for i in placed}),'removed_previous_instances':removed,'sound_object_nodes':sum(n['template'].startswith('object/soundobject/') for n in layout_nodes),'skipped_objects':skipped,'conversion_failures':assets.failures,'buildings':{str(oid):{'instances':sum(i['building_object_id']==oid for i in placed),'source_nodes':sum(n['building_object_id']==oid for n in layout_nodes)} for oid in sorted({n['building_object_id'] for n in layout_nodes})}}
 write(args.out/'interior_layout_report.json',report);write(args.out/'collision_report.json',assets.collision_report([i for chunk in chunks.values() for i in chunk['instances']]));write(args.out/'world.json',manifest)
 print(json.dumps({key:value for key,value in report.items() if key!='buildings'},indent=2),flush=True)

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--planet',choices=PLANETS,default='tatooine');p.add_argument('--tre-dir',type=Path,default=ROOT/'runtime/assets/active_tre');p.add_argument('--out',type=Path,default=None);p.add_argument('--chunk-size',type=int,default=256);p.add_argument('--refresh-interiors',action='store_true',help='Refresh only original ILF decorations in an existing world, preserving terrain and other placements');p.add_argument('--stage',type=Path,default=ROOT/'runtime/assets/mos_eisley/scene.json');args=p.parse_args();args.out=args.out or path_for(args.planet,"world")
 assert args.chunk_size>0
 assets=StaticAssets(args.tre_dir,args.out);snapshot=f'snapshot/{args.planet}.ws';root=parse_iff(assets.read(snapshot));names=root.first('OTNL').data[4:].split(b'\0');nodes=[]
 for node in root.walk('NODE'):
  data=node.first('DATA').data;oid,parent,tid,cell=struct.unpack_from('<4I',data);nodes.append({'id':oid,'parent':parent,'template':names[tid].decode(),'cell':cell,'q':struct.unpack_from('<4f',data,16),'p':struct.unpack_from('<3f',data,32)})
 # Snapshot child transforms are local to their parent cell/building.
 # Resolve the full authored hierarchy once; cell nodes supply ownership only.
 by_id={node['id']:node for node in nodes};resolved={}
 def resolve_node(node,trail=()):
  if node['id'] in resolved:return resolved[node['id']]
  if node['id'] in trail:raise ValueError('Snapshot parent cycle '+str(node['id']))
  result=dict(node)
  if node['parent']:
   if node['parent'] not in by_id:raise ValueError('Missing snapshot parent '+str(node['parent']))
   parent=resolve_node(by_id[node['parent']],trail+(node['id'],))
   result['p']=[a+b for a,b in zip(qrot(parent['q'],node['p']),parent['p'])]
   result['q']=qmul(parent['q'],node['q'])
   if parent['template']=='object/cell/shared_cell.iff':
    result['cell_id']=str(parent['parent'])+':'+str(parent['cell']);result['building_object_id']=parent['parent'];result['source_cell_object_id']=parent['id']
   elif 'cell_id' in parent:
    result.update({key:parent[key] for key in ('cell_id','building_object_id','source_cell_object_id')})
  resolved[node['id']]=result;return result
 nodes=[resolve_node(node) for node in nodes]
 snapshot_count=len(nodes);layout_nodes=expand_layouts(assets,nodes)
 if args.refresh_interiors:
  refresh_interiors(args,assets,nodes,layout_nodes);return
 nodes.extend(layout_nodes)
 elevation_outliers=[{'object_id':n['id'],'template':n['template'],'source_position':list(n['p'])} for n in nodes if not n['parent'] and abs(n['p'][1])>10000]
 origin=origin_for(args.planet);chunks={};skipped=[];placed=0;cell_count=0
 stage=json.loads(args.stage.read_text()) if args.planet=='tatooine' and args.stage.exists() else {};snapshot_failure_count=None;existing_ids=sorted({i['object_id'] for i in stage.get('instances',[])})
 for node in nodes:
  if 'source_layout' in node and snapshot_failure_count is None:snapshot_failure_count=len(assets.failures)
  if node['template']=='object/cell/shared_cell.iff':continue
  if not node['template'].startswith(('object/static/','object/building/','object/tangible/')):
   skipped.append({'object_id':node['id'],'template':node['template'],**{k:node[k] for k in ('source_layout','source_layout_index') if k in node},'reason':'nonstatic_template_category'});continue
  try:instances,cells,limits=assets.place(node,origin)
  except Exception as error:skipped.append({'object_id':node['id'],'template':node['template'],**{k:node[k] for k in ('source_layout','source_layout_index') if k in node},'reason':str(error)});continue
  if not instances:skipped.append({'object_id':node['id'],'template':node['template'],**{k:node[k] for k in ('source_layout','source_layout_index') if k in node},'reason':'no_static_appearance'});continue
  position=mirror([node['p'][i]-origin[i] for i in range(3)]);chunk_position=mirror([resolved[node['building_object_id']]['p'][i]-origin[i] for i in range(3)]) if 'building_object_id' in node else position;key=f'{math.floor(chunk_position[0]/args.chunk_size)}:{math.floor(chunk_position[2]/args.chunk_size)}';chunk=chunks.setdefault(key,{'instances':[],'cells':{},'bounds_min':[math.inf]*3,'bounds_max':[-math.inf]*3})
  chunk['instances'].extend(instances);chunk['cells'].update(cells)
  for lo,hi in limits:
   chunk['bounds_min']=[min(chunk['bounds_min'][i],lo[i]) for i in range(3)];chunk['bounds_max']=[max(chunk['bounds_max'][i],hi[i]) for i in range(3)]
  placed+=1
  if placed%500==0:print(f'{placed} objects, {len(assets.meshes)} meshes, {len(chunks)} chunks',flush=True)
 chunk_index={}
 for key,chunk in chunks.items():
  relative='chunks/'+key.replace(':','_')+'.json';write(args.out/relative,chunk);cell_count+=len(chunk['cells'])
  chunk_index[key]={'path':relative,'bounds_min':chunk['bounds_min'],'bounds_max':chunk['bounds_max'],'instance_count':len(chunk['instances']),'cell_count':len(chunk['cells'])}
 stats={'snapshot_nodes':snapshot_count,'interior_layout_nodes':len(layout_nodes),'interior_layout_conversion_failures':len(assets.failures)-(snapshot_failure_count if snapshot_failure_count is not None else len(assets.failures)),'interior_layout_skipped_objects':sum('source_layout' in item for item in skipped),'interior_layout_instances':sum('source_layout' in i for c in chunks.values() for i in c['instances']),'interior_layout_buildings':len({n['building_object_id'] for n in layout_nodes}),'snapshot_child_nodes':sum(bool(n['parent']) for n in nodes if 'source_layout' not in n),'root_objects':sum(not n['parent'] for n in nodes),'placed_objects':placed,'instances':sum(len(c['instances']) for c in chunks.values()),'meshes':len(assets.meshes),'chunks':len(chunks),'cells':cell_count,'collision_definitions':len(assets.collisions),'authored_collision_definitions':sum(c['status']=='authored' for c in assets.collisions.values()),'skipped_objects':len(skipped),'conversion_failures':len(assets.failures),'unique_triangles':sum(m['triangles'] for m in assets.meshes.values()),'instanced_triangles':sum(assets.meshes[i['mesh']]['triangles'] for c in chunks.values() for i in c['instances'])}
 manifest={'schema_version':2,'collision_schema_version':1,'collisions':assets.collisions,'planet':args.planet,'origin':list(origin),'coordinate_system':'Godot Y-up; SWG Z mirrored; positions relative to origin','chunk_size':args.chunk_size,'meshes':assets.meshes,'chunks':chunk_index,'existing_stage_object_ids':existing_ids,'statistics':stats,'source_elevation_outliers':elevation_outliers,'provenance':{'snapshot':snapshot,'tre_directory':str(args.tre_dir.resolve()),'dependencies':assets.dependencies},'warnings':['Source static snapshot roots and hierarchy-owned furnishings; no gameplay/NPC/particle/sound simulation.','POB interior geometry and floor/portal ownership are preserved; exterior-only streaming is supported by is_exterior.','Static materials use original diffuse textures and alpha classification; multipass effects remain approximate.','When retaining the existing Mos Eisley stage, skip existing_stage_object_ids to avoid duplicate geometry.']}
 write(args.out/'collision_report.json',assets.collision_report([i for c in chunks.values() for i in c['instances']]));write(args.out/'world.json',manifest);write(args.out/'conversion_report.json',{'statistics':stats,'skipped_objects':skipped,'failures':assets.failures,'source_elevation_outliers':elevation_outliers});print(json.dumps(stats,indent=2),flush=True)
if __name__=='__main__':main()
