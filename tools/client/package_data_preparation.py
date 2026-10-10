"""Bundle conversion code and open-source definitions, never original assets."""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess
ROOT = Path(__file__).resolve().parents[2]

def package(destination):
    destination = Path(destination)
    selected = []
    for folder in ('tools/assets', 'tools/combat', 'tools/entertainment', 'tools/scout', 'tools/vehicles', 'tools/pets', 'tools/crafting', 'server'):
        selected.extend(p for p in (ROOT/folder).rglob('*') if p.is_file() and p.suffix in ('.py','.json','.md','.h') and not any(part in ('__pycache__','patches') for part in p.parts) and not p.name.startswith('test_'))
    selected.extend(ROOT/'tools/server'/n for n in ('export_ambient_npcs.py','export_combat_population.py'))
    selected.extend(ROOT/'tools/client'/n for n in ('prepare_game_data.py','game_data_plan.py','iso_media.py'))
    selected.append(ROOT/'client/combat/balance.json')
    # Parsed as data only; no realm config, accounts, binaries or databases.
    core=ROOT/'vendor/Core3'
    for name in subprocess.check_output(['git','-C',str(core),'ls-files'],text=True).splitlines():
        if name.startswith('MMOCoreORB/bin/scripts/') or (name.startswith('MMOCoreORB/src/') and Path(name).suffix in ('.h','.cpp','.idl')) or name in ('COPYING','README.md'):
            selected.append(core/name)
    files={}
    for source in sorted(set(selected)):
        relative=source.relative_to(ROOT);target=destination/relative
        target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,target)
        files[relative.as_posix()]=hashlib.sha256(source.read_bytes()).hexdigest()
    # Git-free provenance for installed clients, pinned to the same source.
    revision=subprocess.check_output(['git','-C',str(core),'rev-parse','HEAD'],text=True).strip()
    (destination/'vendor/Core3/REVISION').write_text(revision+'\n')
    files['vendor/Core3/REVISION']=hashlib.sha256((revision+'\n').encode()).hexdigest()
    signature=hashlib.sha256(json.dumps(files,sort_keys=True).encode()).hexdigest()
    (destination/'recipe.json').write_text(json.dumps(dict(schema=1,signature=signature,files=files),indent=2)+'\n')
    return dict(signature=signature,files=len(files),proprietary_assets=False)

if __name__=='__main__':
    import argparse
    p=argparse.ArgumentParser();p.add_argument('destination',type=Path)
    print(json.dumps(package(p.parse_args().destination)))
