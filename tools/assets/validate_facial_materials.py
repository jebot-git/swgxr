#!/usr/bin/env python3
"""Validate imported facial layers and palette/texture selectors, without fake art."""
import argparse,json,math
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]

def validate(directory):
 catalog=json.loads((directory/'catalog.json').read_text());renderers={};shaders={};counts={'models':0,'material_surfaces':0,'rendered_face_surfaces':0}
 def image(path):assert (directory/path).read_bytes().startswith(b'\x89PNG'),path
 def palette(p):
  assert p['min']==0 and p['max']==len(p['colors'])-1
  assert p['variable_path'].startswith(('/private/','/shared_owner/'))
  assert all(len(c)==4 and all(math.isfinite(v) and 0<=v<=1 for v in c) for c in p['colors'])
 def selector(s):
  assert s['min']==0 and s['max']==len(s['textures'])-1
  assert 0<=s['default']<=s['max']
  for p in s['textures']:image(p)
 paths=set()
 for race in catalog['races'].values():
  paths.add(race['body']);paths.update(h['model'] for h in race['hair'])
  paths.update(x['model'] for x in race['default_outfit'])
  for outfit in race['profession_outfits'].values():paths.update(x['model'] for x in outfit)
 for path in paths:
  model=json.loads((directory/path).read_text());counts['models']+=1
  for part in model['parts']:
   for sf in part['mesh']['surfaces']:
    counts['material_surfaces']+=1;shaders[sf['shader']]=sf
    assert sf['color_mode'] in ('single','dual','dual_alpha')
    for p in sf['texture_bindings'].values():image(p)
    for s in sf['texture_selectors']:selector(s)
    for p in sf['palettes']:palette(p)
    recipe=sf.get('texture_renderer_definition')
    if not recipe:continue
    counts['rendered_face_surfaces']+=1;renderers[recipe['source']]=recipe
    assert recipe['supported'] and 1<=len(recipe['layers'])<=6
    assert set(recipe['operations'])<=set(['SSTC','SST1','STFP'])
    for layer in recipe['layers']:
     assert layer['mode'] in ('copy','alpha')
     assert len(layer['rect'])==4 and layer['rect'][2]>0 and layer['rect'][3]>0
     assert len(layer['uv_rect'])==4
     if 'texture' in layer:image(layer['texture'])
     if 'selector' in layer:selector(layer['selector'])
     if 'palette' in layer:palette(layer['palette'])
 counts.update(status='passed',source_renderers=len(renderers),source_layers=sum(len(r['layers']) for r in renderers.values()),source_shaders=len(shaders),shader_texture_selectors=sum(len(s['texture_selectors']) for s in shaders.values()),renderer_style_selectors=sum(sum('selector' in l for l in r['layers']) for r in renderers.values()),scope='All reachable facial recipes, original layer geometry, palette bounds, selector coverage, and texture PNG existence; GPU rendering tested separately.')
 (directory/'facial_validation_report.json').write_text(json.dumps(counts,indent=2)+'\n');return counts

if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--directory',type=Path,default=ROOT/'runtime/assets/characters');print(json.dumps(validate(p.parse_args().directory),indent=2))
