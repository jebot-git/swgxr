#!/usr/bin/env python3
"""Export original space/interior music, ship thrusters and seated avatar poses."""
import hashlib,json
from pathlib import Path
from prepare_environment import EnvironmentImporter
from prepare_characters import CharacterImporter
from character_formats import datatable
from character_animations import load_lat,resolve,decode_clip
from swg_formats import parse_iff,cstring
ROOT=Path(__file__).resolve().parents[2]

def prepare():
 out=ROOT/'runtime/assets/space_audio';imp=EnvironmentImporter(ROOT/'runtime/asset_sources/active_tre',out)
 catalog=json.loads((ROOT/'runtime/assets/jtl/catalog.json').read_text());sectors={};ships={}
 for zone in catalog['sectors']:
  source='datatables/environment/'+zone+'.iff';rows=datatable(imp.read(source));row=next(r for r in rows if r['Weather Index']==0)
  sectors[zone]={'source':source}
  for role,col in [('music','First Music (2d .snd)'),('ambient','Day Ambient Sound 1 (2d .snd)')]:sectors[zone][role]=imp.sound(row[col]) if row[col] else ''
 interiors=datatable(imp.read('datatables/interior/interior.iff'))
 for template,entry in catalog['templates'].items():
  props=imp.properties(entry['shared_template']);pob=Path(props.get('portalLayoutFilename','')).stem
  row=next((r for r in interiors if r['PobName']==pob and r['Cell Name']=='default'),{})
  info={'interior':imp.sound(row['Day sound/ambient Sound (2d .snd)']) if row.get('Day sound/ambient Sound (2d .snd)') else '', 'pob':pob,'source':props.get('clientDataFile','')}
  if info['source'] and info['source'].lower() not in imp.t.entries:
   imp.failures.append(dict(source=info['source'],phase='ship_audio_cdf',error='Absent from supplied source media'))
  elif info['source']:
   root=parse_iff(imp.read(info['source']))
   for sound in root.walk('VSND'):
    values=[];offset=0
    for _ in range(5):value,offset=cstring(sound.data,offset);values.append(value)
    if 'engine' in values[0]:
     for role,value in zip(['idle','accel','decel','run'],values[1:]):info[role]=imp.sound(value) if value else ''
     break
  ships[template]=info
 root=parse_iff(imp.read('scene/game_music_manager.iff'));combat={}
 for tag,key in [('SENT','enter'),('SEXI','exit')]:combat[key]=[imp.sound(cstring(n.data)[0]) for n in root.walk(tag)]
 def effect_sounds(source):
  try:return [sound for n in parse_iff(imp.read(source)).walk('PSND') if (sound:=imp.sound(cstring(n.data)[0]))]
  except Exception as error:imp.failures.append(dict(source=source,phase='combat_audio',error=str(error)));return []
 projectiles={str(row['index']):effect_sounds(row['fireClientEffectTemplateName']) for row in datatable(imp.read('datatables/projectile/projectile.iff')) if row['fireClientEffectTemplateName']}
 hits={str(index):effect_sounds('clienteffect/combat_ship_hit_'+kind+'.cef') for index,kind in enumerate(['shield','armor','component','chassis'])}
 output=dict(schema_version=1,sectors=sectors,ships=ships,combat=combat,projectiles=projectiles,hits=hits,sounds=imp.sounds,provenance=imp.dependencies,failures=imp.failures,policy='Original environment/interior/CDF/SENT/SEXI and projectile table bindings. Blank source music remains silent. Native combat events drive a bounded five-second combat hold.')
 (out/'catalog.json').write_text(json.dumps(output,indent=2)+'\n')
 effects=ROOT/'runtime/assets/space_effects/assets.json';data=json.loads(effects.read_text());characters=json.loads((ROOT/'runtime/assets/characters/catalog.json').read_text());poses={}
 character=CharacterImporter(ROOT/'runtime/asset_sources/active_tre',out)
 for race,definition in characters['races'].items():
  model=json.loads((ROOT/'runtime/assets/characters'/definition['body']).read_text());bones=model['bones'];_,entries=load_lat(character,model['animation_graph']['lat_bindings'][0]['lat'])
  leaf=resolve(entries['loop_sitting_chair'],{'gender':'f' if race.endswith('_female') else 'm'})[0];clip=decode_clip(character,leaf['source'],bones,{b['name']:i for i,b in enumerate(bones)})
  poses[race]={'source':leaf['source'],'source_sha256':hashlib.sha256(character.read(leaf['source'])).hexdigest(),'tracks':[{'name':t['name'],'position':t['positions'][0][1:],'rotation':t['rotations'][0][1:]} for t in clip['tracks']]}
 data['seat_poses']=poses;data['seating_provenance']=character.dependencies;effects.write_text(json.dumps(data,separators=(',',':'))+'\n')
 print(json.dumps({'sectors':len(sectors),'ships':len(ships),'sounds':len(imp.sounds),'seated_races':len(poses),'failures':imp.failures}))
if __name__=='__main__':prepare()
