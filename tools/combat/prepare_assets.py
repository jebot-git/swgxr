#!/usr/bin/env python3
"""Convert original weapon meshes, sound samples, CEF/PRT data and HUD art locally."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import struct
import sys
import subprocess

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/assets'))
from swg_formats import parse_iff, cstring
from static_assets import StaticAssets
from prepare_environment import EnvironmentImporter
from character_formats import datatable
from PIL import Image
from attachment_poses import bake
from export_catalog import template_path

CURVES = ('translation_x','translation_y','translation_z','rotation_x','rotation_y','rotation_z',
          'distance','shape_size','spread','rate','speed','inherit_velocity','cluster_count','cluster_radius','life','weight')


def profile_family(balance, override):
    return override.get('native_family', balance['classes'][override['class']].get('native_family', ''))


def curve(node):
    data = node.children[0].data
    interpolation, sample, count = struct.unpack_from('<3i', data)
    if len(data) != 12 + count*16:
        raise ValueError('Unsupported curve layout')
    return {'interpolation': interpolation, 'sample': sample,
            'points': [list(struct.unpack_from('<4f', data, 12+i*16)) for i in range(count)]}


class Assets(StaticAssets):
    def __init__(self, tre, out, *, bounded_particle_graphs=False):
        super().__init__(tre, out)
        self.audio_importer = EnvironmentImporter(tre, out)
        # Preserve original WAV samples or losslessly decode compressed originals.
        self.audio_importer.audio = self.audio
        self.effects, self.particles = {}, {}
        self.bounded_particle_graphs = bounded_particle_graphs
        self._particle_stack = set()

    def audio(self, source):
        raw = self.read(source)
        relative = 'audio/' + hashlib.sha256(raw).hexdigest()[:24] + '.wav'
        dest = self.out / relative
        dest.parent.mkdir(exist_ok=True)
        if not dest.exists():
            subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-i','pipe:0','-vn',
                            '-c:a','pcm_s16le','-y',str(dest)], input=raw, check=True)
        return relative

    def properties_all(self, path, trail=()):
        if path in trail: raise ValueError('Cyclic template')
        root = parse_iff(self.read(path)); result = {}
        derived = next(root.walk('DERV'), None)
        if derived: result.update(self.properties_all(cstring(derived.first('XXXX').data)[0],trail+(path,)))
        for node in root.walk('XXXX'):
            name, pos = cstring(node.data)
            raw = node.data[pos:]
            if raw[:1] == b'\1': result[name] = raw[1:]
        return result

    def particle(self, path):
        path = path.lower().replace('\\','/')
        if path in self.particles: return path
        if path in self._particle_stack: raise ValueError('Cyclic particle attachment '+path)
        self._particle_stack.add(path)
        try:
            return self._particle(path)
        finally:
            self._particle_stack.remove(path)

    def _particle(self, path):
        root = parse_iff(self.read(path)); emitters = []
        omissions = []
        if root.tag != 'PEFT': raise ValueError('Unsupported particle appearance '+root.tag)
        for emitter in root.walk('EMTR'):
            version = emitter.children[0]
            # The supplied 0009/0011/0012 emitters share this decoded prefix
            # and their tagged curves/quad data. Version-specific extensions
            # remain opaque, byte-for-byte, rather than guessed simulation.
            if version.tag not in ('0009', '0011', '0012'): raise ValueError('Unsupported EMTR '+version.tag)
            waves = [curve(n) for n in version.children if n.tag=='WVFM']
            if len(waves)!=16: raise ValueError('Unexpected emitter curves')
            data = next(n.data for n in version.children if n.tag=='0000')
            name,pos = cstring(data)
            def read(fmt):
                nonlocal pos
                values = struct.unpack_from('<'+fmt,data,pos);pos += struct.calcsize('<'+fmt)
                return values[0] if len(values)==1 else list(values)
            info = {'name':name,'source_version':version.tag,'curves':dict(zip(CURVES,waves))}
            for key, fmt in [('direction','i'),('generation','i'),('shape','i'),('loop_immediately','B'),
                             ('emitter_life_min','f'),('emitter_life_max','f'),('max_particles','f'),
                             ('one_shot','B'),('count_min','i'),('count_max','i'),('random_rotation','B'),
                             ('orientation','i'),('visible','B'),('description_count','i'),('particle_type','i')]:
                info[key] = read(fmt)
            info['sound'],pos = cstring(data,pos)
            info['local_space'] = read('B')
            info['ground_collision'] = read('B'); info['kill_on_collision'] = read('B')
            for flag in ('loop_immediately','one_shot','random_rotation','visible',
                         'local_space','ground_collision','kill_on_collision'):
                if info[flag] not in (0,1): raise ValueError('Unsupported emitter prefix '+flag)
            info['remaining_source_hex'] = data[pos:].hex()
            timing = version.first('PTIM').children[0]
            info['timing'] = list(struct.unpack('<4f2i',timing.data))
            quad = next((n for n in version.children if n.tag=='PTQD'),None)
            if quad is None:
                if not self.bounded_particle_graphs: raise ValueError('Unsupported non-quad particle')
                omissions.append({'emitter':name,'reason':'non_quad_particle'})
                continue
            base = quad.first('PTCL').children[0]
            qv = next(n for n in quad.children if n.tag=='0001')
            info['color'] = curve(base.first('CLRR'))
            basewaves = [curve(n) for n in base.children if n.tag=='WVFM']
            info['alpha'], info['speed_scale'] = basewaves[:2]
            info['rotation'],info['length'],info['width'] = [curve(n) for n in qv.children if n.tag=='WVFM']
            info['linked_size'] = bool(next(n.data[0] for n in qv.children if n.tag=='0000'))
            tex = qv.first('PTEX').first('0000').data
            shader, tp = cstring(tex)
            if self.bounded_particle_graphs:
                for attachment in base.walk('PATT'):
                    source = cstring(attachment.children[0].first('0000').data)[0]
                    if not source.lower().endswith('.prt'):
                        omissions.append({'emitter':name,'reason':'non_particle_attachment','source':source})
                        continue
                    child = self.particle(source)
                    # Original child emitter curves/textures are retained. The
                    # bounded runtime does not simulate nested moving emitters.
                    emitters.extend(self.particles[child]['emitters'])
                    omissions.append({'emitter':name,'reason':'attachment_motion_flattened','source':source})
                if not shader:
                    omissions.append({'emitter':name,'reason':'untextured_attachment_carrier'})
                    continue
            info['material'] = dict(self.material(shader))
            shader_root = parse_iff(self.read(shader))
            effects = [cstring(n.data)[0].lower().replace('\\','/') for n in shader_root.walk('NAME') if b'.eft' in n.data]
            info['material']['effect_sources'] = effects
            info['material']['additive'] = any(e.endswith('e_particle_emisadd.eft') for e in effects)
            info['texture_animation'] = list(struct.unpack_from('<iiififB',tex,tp))
            emitters.append(info)
        self.particles[path] = {'source':path,'emitters':emitters}
        if omissions: self.particles[path]['bounded_omissions'] = omissions
        return path

    def effect(self, path):
        path = path.lower().replace('\\','/')
        if path in self.effects: return path
        root = parse_iff(self.read(path)); appearances=[];sounds=[];lights=[];unsupported=[]
        for node in root.children[0].children:
            if node.tag=='CPAP':
                source,pos = cstring(node.data)
                appearances.append({'particle':self.particle(source),'duration':struct.unpack_from('<f',node.data,pos)[0]})
            elif node.tag=='PSND':
                sound = self.audio_importer.sound(cstring(node.data)[0].replace('\\','/').lower())
                if not sound: raise ValueError('Failed CEF sound')
                sounds.append(sound)
            elif node.tag=='CLGT':
                values=struct.unpack('<3B5f',node.data)
                lights.append({'color':[v/255 for v in values[:3]],'duration':values[3],'attenuation':list(values[4:7]),'range':values[7]})
            elif node.tag!='CAMS': unsupported.append(node.tag)
        self.effects[path] = {'source':path,'appearances':appearances,'sounds':sounds,'lights':lights,
                              'omitted_camera_shake_for_xr':True,'unsupported':unsupported}
        return path

    def reticle(self):
        source='texture/ui_target_aim.dds'
        im=Image.open(io.BytesIO(self.read(source))).convert('RGBA')
        (self.out/'ui').mkdir(exist_ok=True);im.save(self.out/'ui/target_aim.png')
        return {'source':source,'path':'ui/target_aim.png','size':list(im.size)}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tre-dir',type=Path,default=ROOT/'runtime/asset_sources/active_tre')
    parser.add_argument('--out',type=Path,default=ROOT/'runtime/assets/combat')
    args=parser.parse_args(); imp=Assets(args.tre_dir,args.out, bounded_particle_graphs=True)
    balance=json.loads((ROOT/'client/combat/balance.json').read_text())
    rows=datatable(imp.read('datatables/weapon/weapon.iff'));weapons={}
    for key, override in balance['weapons'].items():
        template = Path(template_path(key, override))
        shared = str(template.with_name('shared_'+template.name))
        melee = balance['classes'][override['class']].get('kind') == 'melee'
        try:
            properties=imp.properties_all(shared)
            parts=imp.resolve(shared)
            if not parts: raise ValueError('No original weapon mesh')
            if melee:
                arrangement=cstring(properties['arrangementDescriptorFilename'])[0]
                slots=[[s.decode('ascii') for s in arg.data.split(b'\0') if s] for arg in parse_iff(imp.read(arrangement)).walk('ARG ')]
                client_data=cstring(properties['clientDataFile'])[0]
                events={}
                for node in parse_iff(imp.read(client_data)).walk('CEFT'):
                    event,pos=cstring(node.data);source,_=cstring(node.data,pos)
                    if event in ('swing','hit'): events[event]=imp.effect(source)
                if not all(event in events for event in ('swing','hit')): raise ValueError('Original melee swing/hit event missing')
                weapons[key]={'kind':'melee','attachment':{'arrangement':arrangement,'slots':slots},'shared_template':shared,
                              'parts':parts,'client_data':client_data,'effects':events}
                continue
            muzzle=None; muzzle_metadata={}
            appearance=cstring(properties['appearanceFilename'])[0]
            hp_sources=[part['mesh'] for part in parts]
            while appearance.endswith('.apt'):
                appearance=cstring(parse_iff(imp.read(appearance)).first('NAME').data)[0]
            hp_sources.append(appearance)
            for hp_source in hp_sources:
                meshroot=parse_iff(imp.read(hp_source))
                for hp in meshroot.walk('HPNT'):
                    name=cstring(hp.data,48)[0]
                    # Original heavy models use muzzle2, including its unusual
                    # source orientation. Preserve the full transform for the rig.
                    if name=='muzzle' or (name=='muzzle2' and profile_family(balance, override)=='commando'):
                        matrix=struct.unpack_from('<12f',hp.data)
                        muzzle=[matrix[3],matrix[7],-matrix[11]]
                        muzzle_metadata={'muzzle_hardpoint':name,'muzzle_source':hp_source,
                                         'muzzle_source_matrix':list(matrix)}
            if muzzle is None: raise ValueError('Missing original muzzle hardpoint')
            index=struct.unpack_from('<i',properties['weaponEffectIndex'],1)[0]
            effect_id=cstring(properties.get('weaponEffect',b'bolt\0'))[0]
            row=next(r for r in rows if r['Weapon Effect Index']==index and r['Weapon Effect Id']==effect_id)
            arrangement=cstring(properties['arrangementDescriptorFilename'])[0]
            slots=[]
            for arg in parse_iff(imp.read(arrangement)).walk('ARG '):
                slots.append([s.decode('ascii') for s in arg.data.split(b'\0') if s])
            record={'attachment':{'arrangement':arrangement,'slots':slots},'shared_template':shared,'parts':parts,'muzzle':muzzle,**muzzle_metadata,'effect_row':row,'effects':{}}
            weapons[key]=record
            for phase,column in [('fire','Fire Client Effect'),('hit','Hit (Other) Client Effect'),('hit_creature','Hit (Creature) Client Effect')]:
                try: record['effects'][phase]=imp.effect(row[column])
                except Exception as e: imp.failures.append({'weapon':key,'phase':phase,'source':row[column],'error':str(e)})
            try: record['projectile']=imp.particle(row['Projectile Appearance Template'])
            except Exception as e: imp.failures.append({'weapon':key,'phase':'projectile','source':row['Projectile Appearance Template'],'error':str(e)})
        except Exception as e: imp.failures.append({'weapon':key,'phase':'model','error':str(e)})
    unarmed = {'effects': {}}
    for event in ('swing','hit'):
        source = f'clienteffect/combat_melee_{event}_unarmed.cef'
        try: unarmed['effects'][event] = imp.effect(source)
        except Exception as e: imp.failures.append({'phase':'unarmed','source':source,'error':str(e)})
    mounts={}
    character_dir=ROOT/'runtime/assets/characters'
    character_catalog=json.loads((character_dir/'catalog.json').read_text())
    for race,info in character_catalog['races'].items():
        try:
            model_path=character_dir/info.get('body',info.get('model',''))
            model_raw=model_path.read_bytes(); model=json.loads(model_raw)
            for skeleton in {b['source_skeleton'] for b in model['bones'] if b['source_skeleton'].endswith('.skt')}:
                imp.read(skeleton)
            mounts[race]={'model':str(model_path.relative_to(character_dir)), 'model_sha256':hashlib.sha256(model_raw).hexdigest(),
                          'mounts':bake(imp,model,{'hip':30,'back':50})}
        except Exception as e: imp.failures.append({'phase':'stow_mounts','race':race,'error':str(e)})
    reticle=imp.reticle()
    imp.dependencies.update(imp.audio_importer.dependencies)
    output={'schema':1,'unarmed':unarmed,'stow_mounts':mounts,'weapons':weapons,'meshes':imp.meshes,'effects':imp.effects,'particles':imp.particles,
            'sounds':imp.audio_importer.sounds,'reticle':reticle,'provenance':imp.dependencies,
            'failures':imp.failures+imp.audio_importer.failures,
            'limitations':['Source mesh and texture content retained. Godot lighting is not original SWG shader execution.',
            'Particle descriptions retained; runtime supports quad effects, not original engine pixel equivalence.',
            'Nested particle attachment motion is flattened; source emitters, textures and explicit omission records are retained.',
            'CEF camera shake intentionally suppressed: effects never drive the tracked head.',
            'CEF light colors, duration and range retained; Godot attenuation differs from the original engine.']}
    (args.out/'assets.json').write_text(json.dumps(output,separators=(',',':')))
    print(json.dumps({'weapons':len(weapons),'meshes':len(imp.meshes),'effects':len(imp.effects),'particles':len(imp.particles),'sounds':len(imp.audio_importer.sounds),'failures':output['failures']},indent=2))

if __name__=='__main__': main()
