#!/usr/bin/env python3
"""Prepare the conservative source-defined Tatooine mobile appearance union.

No Lua executes and no entities spawn. Region lairs, all planet mobile files,
and planet-referencing screenplay strings supply dependencies, not live state.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/server'))
from export_combat_population import export
from export_ambient_npcs import table


def clean(text):
    # Lua comments must not consume '--' inside a quoted user-facing string.
    token = r'''"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|--\[\[.*?\]\]|--[^\n]*'''
    return re.sub(token, lambda m: re.sub(r'[^\n]', ' ', m[0]) if m[0].startswith('--') else m[0], text, flags=re.S)


def strings(text):
    return [m[1] for m in re.finditer(r'''["']([^"'\n\\]*)["']''', text)]

DEFAULT_CATALOGS = [ROOT / 'runtime/assets' / p / 'catalog.json' for p in (
    'combat_population/mos_eisley_easy', 'combat_population/native_current',
    'combat_population/tatooine', 'ambient_npcs')]


def source_union():
    manifest, _ = export()
    scripts = ROOT / 'vendor/Core3/MMOCoreORB/bin/scripts'
    sources = manifest['provenance']['files_sha256']
    paths = {}; texts = {}; failures = manifest['failures']; refs = {}; duplicate_registry = []
    def read(path):
        raw = path.read_bytes()
        sources[str(path.relative_to(ROOT))] = hashlib.sha256(raw).hexdigest()
        return clean(raw.decode())
    for path in (scripts / 'mobile').rglob('*.lua'):
        if any(p in path.parts for p in ('lair','spawn','outfits','dressgroup','conversations','weapon')):
            continue
        text = clean(path.read_text(errors='replace'))
        registered = re.findall(r'CreatureTemplates:addCreatureTemplate\(\s*\w+\s*,\s*"([^"]+)"\s*\)', text)
        # Literal calls to a one-parameter registration factory (the original
        # informant levels) are safely expanded without executing arbitrary Lua.
        factory=re.search(r'function\s+(\w+)\((\w+)\)',text)
        if factory:
            prefixes=re.findall(r'CreatureTemplates:addCreatureTemplate\(\s*\w+\s*,\s*"([^"]+)"\s*\.\.\s*'+re.escape(factory[2])+r'\s*\)',text)
            args=re.findall(r'\b'+re.escape(factory[1])+r'\("([^"]+)"\)',text)
            registered.extend(prefix+arg for prefix in prefixes for arg in args)
        for name in registered:
            if name in paths and paths[name] != path:
                same=set(strings(table(text,'templates')[0]))==set(strings(table(texts[name],'templates')[0]))
                duplicate_registry.append(dict(mobile=name,sources=[str(paths[name].relative_to(ROOT)),str(path.relative_to(ROOT))],identical_appearance_templates=same))
                if not same:failures.append(dict(mobile=name, error='Ambiguous registered source mobile with different appearance templates'))
                continue
            paths[name] = path; texts[name] = text
    selected = set(manifest['mobiles'])
    selected.update(name for name, path in paths.items() if 'tatooine' in path.relative_to(scripts / 'mobile').parts)
    screens = {}; dynamic = []
    for path in (scripts / 'screenplays').rglob('*.lua'):
        text = clean(path.read_text(errors='replace'))
        # Mixed-planet screenplays intentionally select a conservative superset.
        if 'tatooine' not in str(path).lower() and 'tatooine' not in strings(text):
            continue
        text = read(path); values = strings(text)
        names = sorted(set(values) & paths.keys()); selected.update(names)
        relative = str(path.relative_to(ROOT)); screens[relative] = names
        for name in names: refs.setdefault(name, []).append(relative)
        for match in re.finditer(r'\bspawnMobile\s*\(\s*([^,\n]+),\s*([^,\n]+)', text):
            literal = re.fullmatch(r'"([^"]+)"', match[2].strip())
            if literal and literal[1] not in paths:
                failures.append(dict(source=relative, mobile=literal[1], error='Unknown literal spawnMobile source'))
            elif not literal:
                dynamic.append(dict(source=relative, line=text.count('\n',0,match.start())+1,
                                    expression=match[2].strip(), policy='All literal registered-mobile strings in this screenplay selected; dynamic Lua execution not evaluated'))
    resolved = dict(manifest['mobiles'])
    def mobile(name, trail=()):
        if name in resolved: return resolved[name]
        if name in trail or name not in paths: raise ValueError('Unresolved source mobile '+name)
        text = read(paths[name]); parent = re.search(r'=\s*(\w+):new', text)
        inherited = mobile(parent[1], (*trail,name)) if parent and parent[1]!='Creature' else {}
        values = strings(table(text,'templates')[0]) or inherited.get('appearance_templates',[])
        templates = []
        for value in values:
            if value.startswith('object/'): templates.append(value)
            else:
                templates.extend(v for v in strings(read(scripts/'mobile/dressgroup'/f'{value}.lua')) if v.startswith('object/'))
        if not templates: raise ValueError('No original appearance templates for '+name)
        result = dict(source=str(paths[name].relative_to(ROOT)), appearance_templates=sorted(set(templates)), screenplay_references=refs.get(name,[]))
        # Record source equipment declarations without claiming the live random
        # outfit/weapon choice. Original CDF and existing catalog variants remain.
        for field in ('outfit','primaryWeapon','secondaryWeapon'):
            match = re.search(r'\b'+field+r'\s*=\s*"([^"]*)"',text)
            if match: result[field] = match[1]
            elif field in inherited: result[field] = inherited[field]
        resolved[name] = result; return result
    for name in sorted(selected):
        try: mobile(name)
        except (ValueError,OSError) as exc: failures.append(dict(mobile=name,error=str(exc)))
    templates = sorted({t for record in resolved.values() for t in record['appearance_templates']})
    manifest.update(mobiles=resolved, screenplay_sources=screens, dynamic_spawn_references=dynamic,duplicate_mobile_registrations=duplicate_registry,
                    selection_policy='Conservative union: all Tatooine mobile definitions, all referenced region lairs, all exact registered-mobile strings in Tatooine-named or Tatooine-referencing screenplays; no runtime Lua or spawn authority',
                    appearance_templates=templates)
    return manifest


def coverage(manifest, paths):
    catalogs = [(p,json.loads(p.read_text())) for p in paths if p.is_file()]
    records = {}
    for template in manifest['appearance_templates']:
        matches = [(p,c['races'][template]) for p,c in catalogs if template in c.get('races',{})]
        if matches:
            path, descriptor = matches[0]
            records[template] = dict(status='ready' if descriptor.get('appearance_complete',True) else 'partial', catalog=str(path.relative_to(ROOT)), failures=descriptor.get('appearance_failures',[]))
        else:
            shared=str(Path(template).parent/('shared_'+Path(template).name))
            related = [f for _,c in catalogs for f in c.get('failures',[]) if f.get('resource')==shared]
            records[template] = dict(status='missing',failures=related)
    return dict(schema_version=1,templates=records,counts={state:sum(v['status']==state for v in records.values()) for state in ('ready','partial','missing')},
                source_resolution_failures=manifest['failures'],dynamic_spawn_references=manifest['dynamic_spawn_references'],live_population=False,gpu_validated=False)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--planet',choices=['tatooine'],default='tatooine')
    parser.add_argument('--out',type=Path,default=ROOT/'runtime/assets/combat_population/tatooine_entities')
    parser.add_argument('--tre-dir',type=Path,default=ROOT/'runtime/assets/active_tre')
    parser.add_argument('--index-only',action='store_true')
    parser.add_argument('--retry-missing',action='store_true')
    args=parser.parse_args();args.out=args.out.resolve();args.out.mkdir(parents=True,exist_ok=True)
    manifest=source_union();(args.out/'sources.json').write_text(json.dumps(manifest,indent=2)+'\n')
    paths=DEFAULT_CATALOGS+[args.out/'catalog.json'];before=coverage(manifest,paths)
    selected=[key for key,value in before['templates'].items() if value['status']=='missing']
    previous=args.out/'attempted_templates.json'
    attempted=json.loads(previous.read_text()) if previous.exists() else []
    if not args.retry_missing:selected=[key for key in selected if key not in attempted]
    requests=dict(schema_version=1,mode='appearance_requests_only_no_spawn_positions',
                  instances=[dict(template=key,appearance_id=key,mood='neutral',mobile='') for key in selected],provenance=manifest['provenance'])
    payload=json.dumps(requests,indent=2)+'\n';digest=hashlib.sha256(payload.encode()).hexdigest()
    request=args.out/'selections'/f'{digest}.json';request.parent.mkdir(exist_ok=True);request.write_text(payload)
    (args.out/'appearance_requests.json').write_text(payload)
    print(json.dumps(dict(source_mobile_definitions=len(manifest['mobiles']),screenplays=len(manifest['screenplay_sources']),templates=len(manifest['appearance_templates']),to_prepare=len(selected),source_failures=manifest['failures'])),flush=True)
    if selected and not args.index_only:
        subprocess.run([sys.executable,str(ROOT/'tools/assets/prepare_npcs.py'),'--tre-dir',str(args.tre_dir),'--out',str(args.out),'--placements',str(request),'--merge'],check=True)
        previous.write_text(json.dumps(sorted(set(attempted+selected)),indent=2)+'\n')
        subprocess.run([sys.executable,str(ROOT/'tools/assets/refresh_npc_death_poses.py'),str(args.out)],check=True)
    report=coverage(manifest,paths);(args.out/'coverage.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report['counts']),flush=True)


if __name__=='__main__':main()
