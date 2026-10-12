#!/usr/bin/env python3
"""Convert original hyperspace stages and sector effects from supplied media."""
import json, struct
from pathlib import Path
from prepare_space_sectors import SectorAssets, ROOT, dump
from swg_formats import parse_iff, cstring
from character_formats import datatable

def prepare():
    out=ROOT/'runtime/assets/space_effects'
    assets=SectorAssets(ROOT/'runtime/asset_sources/active_tre',out)
    assets.bounded_particle_graphs=True
    root=parse_iff(assets.read('scene/hyperspace.iff'))
    stages={}
    for tag,key in [('STG1','enter'),('STG3','leave')]:
        raw=root.first(tag).data
        duration=struct.unpack_from('<f',raw)[0]
        particle,offset=cstring(raw,4); effect,offset=cstring(raw,offset)
        distance=struct.unpack_from('<f',raw,offset)[0];sound,_=cstring(raw,offset+4)
        stages[key]=dict(duration=duration,particle=particle,effect=effect,offset=distance,
                         sound=assets.audio_importer.sound(sound) if sound else {})
        if particle:assets.particle(particle)
        if effect:assets.effect(effect)
    raw=root.first('STG2').data
    sound,_=cstring(raw,12)
    stages['travel']=dict(zip(('duration','speed','roll_rate'),struct.unpack_from('<3f',raw)))
    stages['travel']['sound']=assets.audio_importer.sound(sound) if sound else {}
    stages['countdown_sound']=assets.audio_importer.sound('sound/ship_hyperspace_countdown.snd')
    nebula={}
    for index,shader in enumerate(['shader/pt_nebulae_gas_4_2.sht','shader/pt_nebulae_gas_4_alpha_2.sht']):nebula[str(index)]=assets.shader_textures(shader)
    distant={}
    combat={'projectiles':{},'hits':{}}
    for row in datatable(assets.read('datatables/projectile/projectile.iff')):
        source=row['appearanceTemplateName']
        if source:combat['projectiles'][str(row['index'])]=assets.particle(source)
    for index,kind in enumerate(('shield','armor','component','chassis')):
        combat['hits'][str(index)]=assets.effect('clienteffect/combat_ship_hit_'+kind+'.cef')
    for descriptor in sorted((ROOT/'runtime/assets/jtl').glob('space_*.json')):
        data=json.loads(descriptor.read_text())
        for field in data.get('nebula',[]):
            if field.get('ambientSound'):assets.audio_importer.sound(field['ambientSound'])
        for row in data['environment'].get('distant',[]):
            if row['source'].endswith('.prt'):assets.particle(row['source'])
    dump(out/'assets.json',dict(schema_version=1,hyperspace=stages,nebula=nebula,combat=combat,
        effects=assets.effects,particles=assets.particles,sounds=assets.audio_importer.sounds,
        provenance={**assets.dependencies,**assets.audio_importer.dependencies},conversion_failures=assets.failures+assets.audio_importer.failures))
    # Seat clips and ship audio share this original-media preparation stage.
    from prepare_space_audio import prepare as prepare_audio
    prepare_audio()
    print(json.dumps(dict(stages=stages,failures=assets.failures)))
if __name__=='__main__':prepare()
