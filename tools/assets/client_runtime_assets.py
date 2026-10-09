"""Conservative dependency closure for the portable client's converted data.

Keep every catalog alternative, including fallback and conditional content.
Source/provenance references inside retained JSON are preserved, but raw TREs
and developer-only files are not part of this client distribution.
"""
import hashlib
import json
from pathlib import Path
import posixpath
import re

SOURCE_SUFFIXES = {'.gd', '.cpp', '.h', '.tscn', '.godot'}
EXCLUDED = {'tests', 'tools', 'benchmarks', 'addons', '.godot', 'build'}
LITERAL = re.compile(r'runtime/assets/[A-Za-z0-9_./-]+')
REFERENCE = re.compile(rb'"([^"\n]*\.(?:json|png|jpg|jpeg|ogg|wav|mp3|flr|trn|fnt|lay|pob))"')
# Native geometry/terrain builders consume converted JSON, not original IFF
# binaries. UI uses the bundled TTF rather than source SWG bitmap-font records.
RUNTIME_SUFFIXES = {'.json', '.png', '.jpg', '.jpeg', '.ogg', '.wav', '.mp3'}


def select(root, paths):
    root = Path(root).resolve()
    all_files = {p.relative_to(root).as_posix(): p for p in paths}
    files = {name: p for name, p in all_files.items() if p.suffix.lower() in RUNTIME_SUFFIXES}
    roots, evidence, sources = set(), {}, {}

    def seed(path, reason):
        if path in files:
            roots.add(path)
            evidence.setdefault(path, []).append(reason)

    for path in sorted((root / 'client').rglob('*')):
        relative = path.relative_to(root / 'client')
        if path.suffix not in SOURCE_SUFFIXES or any(p in EXCLUDED for p in relative.parts):
            continue
        raw = path.read_bytes()
        name = path.relative_to(root).as_posix()
        sources[name] = hashlib.sha256(raw).hexdigest()
        for match in LITERAL.finditer(raw.decode(errors='replace')):
            value = match.group().rstrip('/')
            for candidate in (value, value + '/catalog.json', value + '/assets.json'):
                seed(candidate, name)

    # These loaders construct filenames at runtime instead of using full literals.
    seed('runtime/assets/entertainment/items/catalog.json', 'entertainment/controller.gd: items/catalog.json')
    for name in files:
        if name.startswith(('runtime/assets/combat/abilities/', 'runtime/assets/combat/player_postures/')):
            seed(name, 'ability_hologram.gd / avatar.gd: command or race filename')
        if name.startswith('runtime/assets/entertainment/') and name.count('/') == 3 and name.endswith('.png'):
            seed(name, 'ability_hologram.gd: fallback command icon')
        if '/services/' in name and name.endswith(('/screens.json', '/trainers.json')):
            seed(name, 'service_world.gd / datapad_map.gd: companion catalog')
    if not roots:
        raise ValueError('No client asset roots found; refusing an empty runtime distribution')

    visited, pending, references = set(), list(roots), {}
    while pending:
        name = pending.pop()
        if name in visited:
            continue
        visited.add(name)
        path = files[name]
        if path.suffix != '.json':
            continue
        # Avoid decoding millions of geometry numbers just to find filenames.
        raw = path.read_bytes()
        digest = hashlib.sha256(raw).hexdigest()
        if digest not in references:
            values = set()
            for match in REFERENCE.finditer(raw):
                values.add(json.loads(b'"' + match.group(1) + b'"'))
            references[digest] = values
        for value in references[digest]:
            if '/runtime/' in value:
                candidates = ['runtime/' + value.split('/runtime/', 1)[1]]
            elif value.startswith('runtime/'):
                candidates = [value]
            else:
                # Models resolve textures against their owning catalog directory;
                # world chunk paths resolve against the world directory. Retain
                # every existing ancestor match to avoid narrowing that behavior.
                parent, candidates = posixpath.dirname(name), []
                while parent.startswith('runtime/assets'):
                    candidates.append(posixpath.normpath(posixpath.join(parent, value)))
                    parent = posixpath.dirname(parent)
            pending.extend(p for p in candidates if p in files and p not in visited)
    excluded = sorted(set(all_files) - visited)
    report = dict(profile='client-runtime', method='Conservative client roots and transitive JSON paths; dynamic roots explicitly retained',
                  roots=sorted(roots), root_evidence=evidence, client_sources_sha256=sources,
                  included_files=len(visited), excluded_files=len(excluded), excluded_paths=excluded,
                  excluded_bytes=sum(all_files[p].stat().st_size for p in excluded))
    return [files[p] for p in sorted(visited)], report
