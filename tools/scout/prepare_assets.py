#!/usr/bin/env python3
"""Original scout tools/camps and command icons, with the existing hash ledger."""
import hashlib,json,math,re,struct,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];SCRIPTS=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts'
sys.path.insert(0,str(ROOT/'tools/assets'))
from swg_formats import TreSet,parse_iff,cstring
from interior_layout import template_properties
from source_metadata import build as source_metadata
sources=TreSet(ROOT/'runtime/asset_sources/active_tre');provenance={}
def read(path):
 raw=sources.read(path);provenance[path]={'sha256':hashlib.sha256(raw).hexdigest(),'bytes':len(raw),'archive':sources.entries[path][0].name};return raw
templates=set();camps={};failures=[]
# Grenades share the physical trap grip/throw path. Only the original supported
# certified families are imported; generic poison/fallback supplies stay outside it.
templates.update('object/weapon/ranged/grenade/grenade_'+name+'.iff' for name in (
 'fragmentation_light','fragmentation','cryoban','glop','imperial_detonator','thermal_detonator','proton'))
for folder in ['object/tangible/scout','object/tangible/camp']:
 for p in (SCRIPTS/folder).rglob('*.lua'):
  if p.stem not in ('objects','serverobjects'):templates.add(str(p.relative_to(SCRIPTS)).replace('.lua','.iff'))
for p in (SCRIPTS/'object/building/poi').glob('scout_camp_*.lua'):
 templates.add(str(p.relative_to(SCRIPTS)).replace('.lua','.iff'))
 templates.update(re.findall(r'"(object/[^" ]+\.iff)"',p.read_text()))
for template in sorted(templates):
 if not template.startswith('object/building/poi/scout_camp_'):continue
 try:
  shared=str(Path(template).parent/('shared_'+Path(template).name));cdf=template_properties(read,shared)['clientDataFile'];root=parse_iff(read(cdf));children=[]
  for node in root.children[0].children:
   if node.tag!='CHL2':raise ValueError('Unsupported camp CDF tag '+node.tag)
   child,offset=cstring(node.data);values=struct.unpack('<17f',node.data[offset:])
   if any(values[4:]):raise ValueError('Unsupported nonzero camp child rotation/dynamics')
   children.append({'template':child.replace('/shared_','/'),'position':list(values[:3]),'heading_radians':math.radians(values[3]),'numeric_tail_hex':node.data[offset:].hex()});templates.add(child.replace('/shared_','/'))
  camps[template]={'source_cdf':cdf,'children':children,'layout':'Original CHL2 position and heading in degrees; remaining source fields zero.'}
 except Exception as exc:failures.append({'template':template,'error':str(exc)})
templates.update(['object/static/structure/general/campfire_fresh.iff','object/static/structure/general/campfire_smoldering.iff'])
args=[sys.executable,str(ROOT/'tools/assets/prepare_inventory.py')]
for template in sorted(templates):args+=['--template',template.replace('/shared_','/')]
subprocess.run(args,check=True,cwd=ROOT)
subprocess.run([sys.executable,str(ROOT/'tools/combat/prepare_abilities.py')],check=True,cwd=ROOT)
subprocess.run([sys.executable,str(ROOT/'tools/combat/prepare_grenades.py')],check=True,cwd=ROOT)
metadata=source_metadata(read,json.loads((ROOT/'runtime/assets/inventory/catalog.json').read_text()),provenance)
failures.extend(metadata.pop('failures'))
out=ROOT/'runtime/assets/scout';out.mkdir(parents=True,exist_ok=True)
(out/'catalog.json').write_text(json.dumps({'schema':2,'templates':sorted(templates),'camps':camps,'source_hashes':provenance,'failures':failures,'provenance_catalog':'../inventory/catalog.json',**metadata},indent=2))
print(json.dumps({'scout_templates':len(templates),'camp_layouts':len(camps),'failures':failures}))
if failures:raise SystemExit(1)
