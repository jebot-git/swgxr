#!/usr/bin/env python3
"""Export deterministic ambient presentations of original Core3 city spawns.

Lua is parsed as data, never executed. Runtime-random choices are recorded;
the output is not a query of the live Core3 population or faction state.
"""
from pathlib import Path
import argparse, ast, hashlib, json, math, re, struct, subprocess, sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/assets'))
from swg_formats import TreSet, parse_iff
from prepare_stage import qrot, qmirror


def clean(text):
    return re.sub(r'--[^\n]*', lambda m: ' ' * len(m[0]), text)


def table(text, name):
    match = re.search(r'\b' + re.escape(name) + r'\s*=\s*\{', text)
    if not match:
        return '', 0
    depth = 1; start = match.end(); quote = ''
    for i in range(start, len(text)):
        c = text[i]
        if quote:
            if c == quote and text[i-1] != '\\': quote = ''
        elif c in '\"\'': quote = c
        elif c == '{': depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0: return text[start:i], start
    raise ValueError('Unclosed source table ' + name)


def strings(text):
    return [ast.literal_eval(s) for s in re.findall(r'"(?:[^"\\]|\\.)*"', text)]


def rows(text, name):
    body, offset = table(text, name)
    for match in re.finditer(r'\{([^{}]*)\}', body):
        try:
            values = ast.literal_eval('[' + re.sub(r'\b(true|false|nil)\b', lambda m: {'true':'True','false':'False','nil':'None'}[m[0]], match[1]) + ']')
            yield values, text.count('\n', 0, offset + match.start()) + 1
        except (ValueError, SyntaxError):
            continue


def qmul(a, b):
    w,x,y,z = a; v,i,j,k = b
    return [w*v-x*i-y*j-z*k, w*i+x*v+y*k-z*j, w*j-x*k+y*v+z*i, w*k+x*j-y*i+z*v]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--city', default='mos_eisley', help='Tatooine city suffix, or all')
    parser.add_argument('--out', type=Path, default=ROOT/'runtime/assets/ambient_npcs')
    parser.add_argument('--tre-dir', type=Path, default=ROOT/'runtime/assets/active_tre')
    args = parser.parse_args()
    scripts = ROOT/'vendor/Core3/MMOCoreORB/bin/scripts'
    sources = {}; skipped = []; dependencies = {}
    def read(path):
        data = path.read_bytes()
        sources[str(path.relative_to(ROOT))] = hashlib.sha256(data).hexdigest()
        return clean(data.decode())
    files = {}
    for path in (scripts/'mobile').rglob('*.lua'):
        if any(p in path.parts for p in ('dressgroup','conversations','lair','spawn')): continue
        if 'CreatureTemplates:addCreatureTemplate' in path.read_text(errors='replace'):
            files.setdefault(path.stem, path)
    def mobile(name, trail=()):
        if name in trail or name not in files: raise ValueError('unresolved mobile ' + name)
        text = read(files[name]); templates = strings(table(text, 'templates')[0])
        parent = re.search(r'=\s*(\w+):new', text)
        inherited = mobile(parent[1], (*trail, name)) if parent and parent[1] != 'Creature' else None
        expanded = []
        for template in templates:
            if template.startswith('object/'): expanded.append(template)
            else:
                group = scripts/'mobile/dressgroup'/f'{template}.lua'
                if group.exists(): expanded.extend(s for s in strings(read(group)) if s.startswith('object/'))
        if not expanded and inherited:
            chosen, inherited_scale, inherited_label, expanded, inherited_outfit, inherited_weapon = inherited
        else:
            if not expanded: raise ValueError('no source appearance templates for ' + name)
            chosen = expanded[int(hashlib.sha256(name.encode()).hexdigest()[:8],16) % len(expanded)]
            inherited_scale, inherited_label, inherited_outfit, inherited_weapon = (inherited[1], inherited[2], inherited[4], inherited[5]) if inherited else (1.0, name, '', '')
        scale = re.search(r'\bscale\s*=\s*([\d.]+)',text)
        label = re.search(r'\bobjectName\s*=\s*"([^"]+)"', text)
        outfit = re.search(r'\boutfit\s*=\s*"([^"]*)"', text)
        primary = re.search(r'\bprimaryWeapon\s*=\s*"([^"]*)"', text)
        return chosen, float(scale[1]) if scale else inherited_scale, label[1] if label else inherited_label, expanded, outfit[1] if outfit else inherited_outfit, primary[1] if primary else inherited_weapon
    def direct_tables(body):
        depth = 0; start = 0; quote = ''
        for index, char in enumerate(body):
            if quote:
                if char == quote and (index == 0 or body[index-1] != '\\'): quote = ''
            elif char in ('"', "'"): quote = char
            elif char == '{':
                if depth == 0: start = index + 1
                depth += 1
            elif char == '}':
                depth -= 1
                if depth < 0: raise ValueError('Unbalanced outfit table')
                if depth == 0: yield body[start:index], start
        if depth or quote: raise ValueError('Unclosed outfit table')
    outfit_cache = {}
    def resolve_outfit(name, mobile_name):
        if not name: return None
        if name not in outfit_cache:
            path = scripts/'mobile/outfits'/f'{name}.lua'; text = read(path)
            body, offset = table(text, name); variants = []
            for variant, variant_start in direct_tables(body):
                items = []
                for item, item_start in direct_tables(variant):
                    template = re.search(r'\bobjectTemplate\s*=\s*"([^"]+)"', item)
                    if not template: raise ValueError('Missing literal outfit objectTemplate in ' + name)
                    custom, _ = table(item, 'customizationVariables'); values = {}
                    for pair, _ in direct_tables(custom):
                        value = ast.literal_eval('[' + pair + ']')
                        if len(value) != 2 or not isinstance(value[0], str) or not isinstance(value[1], int): raise ValueError('Unsupported outfit customization in ' + name)
                        values[value[0]] = value[1]
                    items.append({'template':template[1], 'customization':values, 'source_file':str(path.relative_to(ROOT)), 'source_line':text.count('\n',0,offset+variant_start+item_start)+1})
                if not items: raise ValueError('Empty or unsupported outfit variant ' + name)
                variants.append(items)
            if not variants: raise ValueError('No literal outfit variants ' + name)
            outfit_cache[name] = (variants, str(path.relative_to(ROOT)))
        variants, path = outfit_cache[name]
        index = int(hashlib.sha256((mobile_name+':'+name).encode()).hexdigest()[:8],16) % len(variants)
        return {'name':name,'variant_index':index,'variant_count':len(variants),'items':variants[index], 'source_file':path,'source_sha256':sources[path], 'selection_policy':'deterministic source outfit variant; not live Core3 equipment state'}
    weapon_cache = {}
    def resolve_primary_weapon(name):
        if not name or name in ('unarmed', 'none'): return None
        if name in weapon_cache: return weapon_cache[name]
        if name.startswith('object/'):
            candidates = [name]; source_file = ''; source_line = 0
        else:
            path = scripts/'mobile/weapon/groups'/f'{name}.lua'
            if not path.exists(): path = scripts/'mobile/weapon'/f'{name}.lua'
            text = read(path)
            candidates = [candidate for candidate in strings(table(text, name)[0]) if candidate.startswith('object/')]
            source_file = str(path.relative_to(ROOT)); source_line = text.count('\n',0,text.index(candidates[0]))+1 if candidates else 0
        if not candidates: raise ValueError('No literal weapon templates for primary group ' + name)
        selected = candidates[0]
        record = {'group':name,'template':selected,'source_file':source_file,'source_line':source_line,'source_variant_index':0,'source_variant_count':len(candidates),'customization':{},'status':'selected','selection_policy':'first source-authored primary weapon variant for ambient presentation; not live equipped state; secondary omitted'}
        if any(category in selected for category in ('/creature/', '/droid/', '/unarmed/', '/vehicle/', '/turret/')):
            record.update(status='excluded',reason='Intrinsic, unarmed or vehicle weapon has no ambient loose-equipment presentation')
        weapon_cache[name] = record
        return record
    tre = TreSet(args.tre_dir); raw = tre.read('snapshot/tatooine.ws'); snapshot = parse_iff(raw)
    names = snapshot.first('OTNL').data[4:].split(b'\0'); nodes = {}
    for node in snapshot.walk('NODE'):
        data = node.first('DATA').data; oid,parent,tid,cell = struct.unpack_from('<4I',data)
        nodes[oid] = {'parent':parent,'template':names[tid].decode(),'cell':cell,'q':struct.unpack_from('<4f',data,16),'p':struct.unpack_from('<3f',data,32)}
    origin = list(nodes[1106368]['p'])
    def world_pose(oid):
        node = nodes[oid]
        if not node['parent']: return list(node['q']),list(node['p']),oid
        q,p,root = world_pose(node['parent']); rotated = qrot(q,node['p'])
        return qmul(q,node['q']), [p[i]+rotated[i] for i in range(3)], root
    city_files = sorted((scripts/'screenplays/cities').glob('tatooine_*.lua')) if args.city == 'all' else [scripts/'screenplays/cities'/f'tatooine_{args.city}.lua']
    entries = []
    for path in city_files:
        text = read(path)
        commoners = strings(table(text,'stationaryCommoners')[0]); citizens = strings(table(text,'stationaryNpcs')[0])
        for kind in ('mobiles','stationaryMobiles','gcwMobs'):
            for row_index,(row,line) in enumerate(rows(text,kind)):
                identity = f'{path.stem}:{kind}:{line}:{row_index}'
                try:
                    if kind == 'mobiles':
                        name = row[0]; xyz = list(map(float,row[2:5])); heading=float(row[5]); cell=int(row[6]); mood=row[7] if len(row)>7 else ''
                    elif kind == 'stationaryMobiles':
                        seed=int(hashlib.sha256(identity.encode()).hexdigest()[:8],16)
                        pool=citizens if seed%100<20 and citizens else commoners
                        name=pool[(seed//100)%len(pool)]; xyz=list(map(float,row[1:4])); heading=float(row[4]); cell=int(row[5]); mood=row[6] if len(row)>6 else ''
                    else:
                        start = 2 if isinstance(row[1], str) else 1
                        name=row[0]; xyz=list(map(float,row[start:start+3]));heading=float(row[start+3]);cell=int(row[start+4]);mood=row[start+5] if len(row)>start+5 else ''
                    template,scale,label,choices,outfit_name,primary_name = mobile(name)
                    try: outfit = resolve_outfit(outfit_name,name)
                    except (ValueError,SyntaxError,OSError) as error:
                        outfit = {'name':outfit_name,'variant_index':-1,'variant_count':0,'items':[],'resolution_error':str(error),'selection_policy':'unresolved source outfit; preserved placement, no substitute'}
                    try: primary_weapon = resolve_primary_weapon(primary_name)
                    except (ValueError,OSError) as error: primary_weapon = {'group':primary_name,'status':'unsupported','reason':str(error)}
                    world=list(xyz); q=[math.cos(math.radians(heading)/2),0,math.sin(math.radians(heading)/2),0]; cell_key=''; building=0
                    if cell:
                        if cell not in nodes: raise ValueError('source cell absent from retail snapshot: '+str(cell))
                        parentq,parentp,building=world_pose(cell); rotated=qrot(parentq,xyz)
                        world=[parentp[i]+rotated[i] for i in range(3)];q=qmul(parentq,q)
                        cell_key=f'{building}:{nodes[cell]["cell"]}'
                    position=[world[0]-origin[0],world[1]-origin[1],origin[2]-world[2]]
                    entries.append({'id':identity,'mobile':name,'label':label,'template':template,'appearance_id':template+(('#outfit='+outfit['name']+':'+str(outfit['variant_index'])) if outfit else '')+(('#weapon='+primary_weapon['template']) if primary_weapon and primary_weapon['status']=='selected' else ''),'source_xyz':xyz,
                        'source_world_xyz':world,'source_heading_degrees':heading,'source_cell_id':str(cell),'cell_id':cell_key,'building_object_id':str(building),
                        'position':position,'quaternion':qmirror(q),'scale':scale,'mood':mood,'source_file':str(path.relative_to(ROOT)),'source_line':line,
                        'core3_outfit':outfit,'source_primary_weapon':primary_weapon,'selection':{'kind':kind,'template_options':len(choices),'policy':'deterministic source variant; first GCW faction, not live server state'}})
                except (ValueError,IndexError,TypeError) as error:
                    skipped.append({'source':str(path.relative_to(ROOT)),'line':line,'table':kind,'row':row,'reason':str(error)})
    args.out.mkdir(parents=True,exist_ok=True)
    result={'schema_version':1,'planet':'tatooine','origin':origin,'catalog':'catalog.json','instances':entries,
        'statistics':{'placements':len(entries),'templates':len({e['template'] for e in entries}),'appearance_variants':len({e['appearance_id'] for e in entries}),'outfit_placements':sum(e['core3_outfit'] is not None for e in entries),'primary_weapon_placements':sum(e['source_primary_weapon'] is not None and e['source_primary_weapon']['status']=='selected' for e in entries),'excluded_primary_weapon_placements':sum(e['source_primary_weapon'] is not None and e['source_primary_weapon']['status']!='selected' for e in entries),'interior':sum(bool(e['cell_id']) for e in entries),'skipped':len(skipped)},
        'provenance':{'core3_commit':subprocess.check_output(['git','-C',str(ROOT/'vendor/Core3'),'rev-parse','HEAD'],text=True).strip(),'files_sha256':sources,
            'snapshot_sha256':hashlib.sha256(raw).hexdigest(),'snapshot_archive':tre.entries['snapshot/tatooine.ws'][0].name},
        'limitations':['Ambient local presentation only: no combat, dialogue, AI or live Core3 population authority.',
            'Runtime-random mobile/dressgroup choices use recorded deterministic source variants.',
            'GCW placements show the first source faction variant, not current server city control.',
            'Patrol paths and procedural encounter spawners are omitted.'], 'skipped':skipped}
    temporary=args.out/'placements.json.tmp';temporary.write_text(json.dumps(result,indent=2));temporary.replace(args.out/'placements.json')
    print(json.dumps(result['statistics']))


if __name__ == '__main__': main()
