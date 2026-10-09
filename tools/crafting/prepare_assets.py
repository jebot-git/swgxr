#!/usr/bin/env python3
"""Original resource icons and artisan/specialist item previews; no item grants."""
import hashlib,json,sys,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'tools/assets'));sys.path.insert(0,str(ROOT))
from server.character_protocol import assets
from prepare_datapad import Importer
OUT=ROOT/'runtime/assets/crafting';imp=Importer(ROOT/'runtime/asset_sources/active_tre',OUT)
icons={}
for name in assets().entries:
 if name.startswith('texture/ui_res_') and name.endswith('.dds'):
  key=Path(name).stem.removeprefix('ui_res_');icons[key]=imp.image(name,'icons/'+key+'.png')
# Record original layout provenance, even though the physical panes use VR geometry.
for name in ['ui/ui_craft_assembly.inc','ui/ui_craft_experiment.inc','ui/ui_craft_customize.inc']:imp.read(name)
(OUT/'catalog.json').write_text(json.dumps({'icons':icons,'sources':imp.dependencies},indent=2))
args=[sys.executable,str(ROOT/'tools/assets/prepare_inventory.py')]
if len(sys.argv)>1:args+=['--snapshot',sys.argv[1]]
else:
 from server.artisan_catalog import recipe_previews
 from server.profession_catalog import catalog
 coverage=recipe_previews(ROOT/'vendor/Core3',catalog())
 (OUT/'professions.json').write_text(json.dumps(coverage,indent=2)+'\n')
 # Existing ready entries already retain their original source hashes. Preserve
 # them and extend coverage; prepare_inventory --refresh explicitly rebuilds all.
 existing_path=ROOT/'runtime/assets/inventory/catalog.json'
 existing=json.loads(existing_path.read_text()).get('items',{}) if existing_path.exists() else {}
 for name in coverage['templates']:
  if existing.get(name,{}).get('status')!='ready':args+=['--template',name]
subprocess.run(args,check=True,cwd=ROOT)
print(json.dumps({'resource_icons':len(icons),'source_files':len(imp.dependencies)}))

if len(sys.argv)==1:
 subprocess.run([sys.executable,str(ROOT/"tools/pets/prepare_bioengineer.py")],check=True,cwd=ROOT)
