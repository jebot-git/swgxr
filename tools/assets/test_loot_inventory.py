#!/usr/bin/env python3
"""Verify every native generic junk appearance against supplied original media."""
import hashlib,json,re
from pathlib import Path
from PIL import Image
from prepare_inventory import InventoryImporter
from interior_layout import template_properties
ROOT=Path(__file__).resolve().parents[2]
def main():
 directory=ROOT/'runtime/assets/inventory';catalog=json.loads((directory/'catalog.json').read_text());items=catalog['items'];sources=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/loot/items/junk'
 references=set();hashes={}
 for path in sorted(sources.rglob('*.lua')):
  raw=path.read_bytes();references.update(re.findall(r'directObjectTemplate\s*=\s*"(object/[a-z0-9_/]+\.iff)"',raw.decode()));hashes[str(path.relative_to(ROOT))]=hashlib.sha256(raw).hexdigest()
 importer=InventoryImporter(ROOT/'runtime/asset_sources/active_tre',directory);errors=[];checked=[]
 for template in sorted(references):
  try:
   item=items[template];assert item['status']=='ready',item['failures'];data=(directory/item['model']).read_bytes();assert hashlib.sha256(data).hexdigest()==item['model_sha256'],'Model hash mismatch'
   props=template_properties(importer.read,item['shared_template']);assert (props.get('inventoryAppearanceFilename') or props.get('appearanceFilename'))==item['appearance'],'Original appearance differs'
   model=json.loads(data);assert model['source_appearance']==item['appearance'];assert model['surfaces']
   for surface in model['surfaces']:
    assert len(surface['indices'])>=3 and len(surface['vertices'])>=9
    with Image.open(directory/surface['texture']) as image:image.verify()
   checked.append(dict(template=template,appearance=item['appearance'],triangles=item['triangles']))
  except Exception as error:errors.append(dict(template=template,error=str(error)))
 unresolved=[dict(template=t,failures=items[t]['failures']) for t in catalog['loot_assets']['templates'] if items[t]['status']!='ready']
 report=dict(passed=not errors,junk_items=len(references),checked=checked,errors=errors,all_loot_templates=len(catalog['loot_assets']['templates']),other_unresolved=unresolved,source_hashes=hashes,proprietary_media_committed=False)
 (ROOT/'runtime/evidence/junk-appearance-validation.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({k:v for k,v in report.items() if k not in ('checked','source_hashes','other_unresolved')}));return 0 if not errors else 1
if __name__=='__main__':raise SystemExit(main())
