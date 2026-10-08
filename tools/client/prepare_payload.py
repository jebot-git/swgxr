#!/usr/bin/env python3
"""Assemble client code, a path-capable Godot binary and converted assets locally."""
import argparse
from pathlib import Path
import shutil
import os
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[2]
EXCLUDED={'.git','__pycache__','editor','.sconsign.dblite','tre','jtl','tte','active_tre',
          'ambient_npcs_outfit_export','interior_audit','lair_reference_validation'}
EXCLUDED_SUFFIX={'.log','.pid','.iso','.tre','.db','.sqlite','.sqlite3','.pem','.key','.pyc','.o','.os','.a'}


def prepare(output, engine, engine_notices, root=ROOT):
    output, engine, root=Path(output).resolve(),Path(engine).resolve(strict=True),Path(root).resolve()
    # Some export templates disable path overrides and cannot run this layout.
    with tempfile.TemporaryDirectory() as temporary:
        probe=Path(temporary)
        (probe/'project.godot').write_text('config_version=5\n')
        (probe/'probe.gd').write_text('extends SceneTree\nfunc _initialize():\n\tprint("PAYLOAD_ENGINE_OK")\n\tquit()\n')
        result=subprocess.run([str(engine),'--headless','--xr-mode','off','--path',str(probe),
                               '--log-file',str(probe/'probe.log'),'--script',str(probe/'probe.gd')],
                              stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=30)
        if result.returncode or b'PAYLOAD_ENGINE_OK' not in result.stdout:
            raise ValueError('Engine must support --path and loose projects; use a path-capable Godot build')
    if output.exists(): raise ValueError('Use a new, empty payload destination')
    output.mkdir(parents=True)
    count=0
    def copy(source,target):
        nonlocal count
        if source.is_symlink(): raise ValueError('Unexpected payload symlink: '+str(source))
        target.parent.mkdir(parents=True,exist_ok=True)
        # Copies keep the release snapshot independent from subsequent edits/imports.
        shutil.copy2(source,target);count+=1
    def tree(source):
        if not source.is_dir(): raise ValueError('Required payload directory missing: '+str(source))
        for directory, dirs, files in os.walk(source,followlinks=False):
            dirs[:]=sorted(d for d in dirs if d not in EXCLUDED and not (Path(directory)/d).is_symlink())
            for name in sorted(files):
                path=Path(directory)/name
                if path.suffix.lower() in EXCLUDED_SUFFIX or name.startswith('.env'): continue
                rel=path.relative_to(root)
                if rel.parts[:3]==('client','native','src') or 'godot-cpp' in rel.parts:continue
                if rel.parts[:2] in (('client','tests'),('client','benchmarks'),('client','tools')):continue
                copy(path,output/rel)
    for directory in ('client','runtime/assets','runtime/combat/abilities','runtime/combat/player_postures'):
        tree(root/directory)
    copy(root/'runtime/combat/catalog.json',output/'runtime/combat/catalog.json')
    # Entertainment catalogs reference these assets; logs and test captures stay local.
    for directory in ('animations','audio','items','textures'):tree(root/'runtime/entertainment'/directory)
    copy(root/'runtime/entertainment/catalog.json',output/'runtime/entertainment/catalog.json')
    for source in (root/'runtime/entertainment').glob('*.png'):copy(source,output/source.relative_to(root))
    copy(engine,output/'engine/godot');(output/'engine/godot').chmod(0o755)
    notices=Path(engine_notices).resolve(strict=True)
    if not notices.is_dir() or not any(notices.iterdir()): raise ValueError('Supply the engine license/third-party notices directory')
    for path in notices.rglob('*'):
        if path.is_file(): copy(path,output/'engine/licenses'/path.relative_to(notices))
    if not (output/'client/.godot/global_script_class_cache.cfg').is_file(): raise ValueError('Import the project before preparing the payload')
    print('Prepared %d files in %s' % (count,output))
    return output

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',type=Path,required=True)
    p.add_argument('--engine',type=Path,required=True,help='Godot 4.7+ binary supporting --path (standard editor binary works)')
    p.add_argument('--engine-notices',type=Path,required=True,help='Engine license and third-party notices directory')
    prepare(**vars(p.parse_args()))
