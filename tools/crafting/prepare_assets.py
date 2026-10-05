#!/usr/bin/env python3
"""Original SWG resource icons and bounded artisan item previews; no item grants."""
import hashlib,json,sys,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'tools/assets'));sys.path.insert(0,str(ROOT))
from server.character_protocol import assets
from prepare_datapad import Importer
OUT=ROOT/'runtime/assets/crafting';imp=Importer(ROOT/'runtime/assets/active_tre',OUT)
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
 import re
 templates=set()
 for source in (ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/object/draft_schematic').rglob('*.lua'):
  # Artisan recipes use general assembly/experimentation; include original result templates.
  text=source.read_text()
  if 'general_assembly' in text:
   templates.update(re.findall(r'targetTemplate\s*=\s*"([^"]+)"',text))
 for name in sorted(templates):args+=['--template',name]
subprocess.run(args,check=True,cwd=ROOT)
print(json.dumps({'resource_icons':len(icons),'source_files':len(imp.dependencies)}))
