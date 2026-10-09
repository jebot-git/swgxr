#!/usr/bin/env python3
"""Validate datapad map projection, source hashes, icons and original font atlas metrics."""
import argparse,hashlib,json,re
from pathlib import Path
from PIL import Image
from swg_formats import TreSet
ROOT=Path(__file__).resolve().parents[2]
def main():
 ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--catalog',type=Path,default=ROOT/'runtime/assets/datapad/catalog.json');ap.add_argument('--tre-dir',type=Path,default=ROOT/'runtime/asset_sources/active_tre');ap.add_argument('--report',type=Path,default=ROOT/'runtime/evidence/datapad-assets-validation.json');a=ap.parse_args();c=json.loads(a.catalog.read_text());base=a.catalog.parent;t=TreSet(a.tre_dir);errors=[];glyphs=0
 for path,record in c['provenance']['dependencies'].items():
  if hashlib.sha256(t.read(path)).hexdigest()!=record['sha256']:errors.append('Source hash mismatch: '+path)
 for key,planet in c['maps'].items():
  image=Image.open(base/planet['texture']);assert image.size==(planet['width'],planet['height']);assert planet['image_top']=='north/+Z' and planet['image_right']=='+X'
  lo_x,lo_z,hi_x,hi_z=planet['world_bounds']
  for point in planet['landmarks']:
   x,y,z=point['position']
   if not lo_x<=x<=hi_x or not lo_z<=z<=hi_z:errors.append('Landmark out of map: '+point['id'])
   u=(x-lo_x)/(hi_x-lo_x);v=(hi_z-z)/(hi_z-lo_z)
   if abs((lo_x+u*(hi_x-lo_x))-x)>1e-6 or abs((hi_z-v*(hi_z-lo_z))-z)>1e-6:errors.append('Map projection roundtrip: '+point['id'])
   if point.get('icon') not in c['icons']:errors.append('Missing landmark icon: '+point['id'])
 for name,icon in c['icons'].items():
  image=Image.open(base/icon['texture']);assert image.size==(icon['width'],icon['height'])
  if image.getchannel('A').getextrema()[1]==0:errors.append('Empty icon: '+name)
 for font in c['ui']['fonts']:
  pages=font['pages'];text=(base/font['path']).read_text()
  for line in text.splitlines():
   if not line.startswith('char '):continue
   glyphs+=1;v={k:int(n) for k,n in re.findall(r'(\w+)=(-?\d+)',line)};p=pages[v['page']]
   if v['width']<0 or v['height']<0 or v['x']<0 or v['y']<0 or v['x']+v['width']>p['width'] or v['y']+v['height']>p['height']:errors.append('Glyph outside atlas: '+font['id']+'/'+str(v['id']))
 for template,preview in c.get('template_previews',{}).items():
  image=Image.open(base/preview['preview_texture'])
  if image.width<32 or image.height<32 or image.getchannel('A').getextrema()[1]==0:errors.append('Empty object preview: '+template)
  model=ROOT/'runtime/assets/ambient_npcs'/preview['source_model']
  if model.exists() and hashlib.sha256(model.read_bytes()).hexdigest()!=preview['source_model_sha256']:errors.append('Stale source model preview: '+template)
 if c['starter_contents']['entries']:errors.append('Reference catalog must not grant starter possessions')
 report={'ok':not errors,'source_hashes':len(c['provenance']['dependencies']),'maps':len(c['maps']),'landmarks':sum(len(p['landmarks']) for p in c['maps'].values()),'icons':len(c['icons']),'font_glyphs':glyphs,'source_model_previews':len(c.get('template_previews',{})),'errors':errors};a.report.parent.mkdir(parents=True,exist_ok=True);a.report.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report));raise SystemExit(bool(errors))
if __name__=='__main__':main()
