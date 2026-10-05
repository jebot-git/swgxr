#!/usr/bin/env python3
"""Regenerate the scout patch against the pinned earlier Core3 patch stack."""
from pathlib import Path
import difflib,subprocess,tempfile,shutil
ROOT=Path(__file__).resolve().parents[2]
CORE=ROOT/'vendor/Core3';TARGET=ROOT/'server/patches/0025-scout.patch'
def paths(patch):return {Path(line[6:]) for line in patch.read_text().splitlines() if line.startswith('+++ b/')}
changed=paths(TARGET)
previous=[p for p in sorted(TARGET.parent.glob('*.patch')) if p.name<TARGET.name]
later=[p for p in sorted(TARGET.parent.glob('*.patch')) if p.name>TARGET.name]
needed=set(changed)
for patch in previous+later:needed.update(paths(patch))
for source in (ROOT/'server/scout').glob('*.h'):
 path=Path('MMOCoreORB/src/server/zone/objects/creature/commands')/source.name
 (CORE/path).write_bytes(source.read_bytes());changed.add(path)
with tempfile.TemporaryDirectory(prefix='swgxr-crafting-patch-') as directory:
 before=Path(directory)/'before';after=Path(directory)/'after';before.mkdir();after.mkdir();subprocess.run(['git','init','-q',str(before)],check=True)
 for path in needed:
  if (CORE/path).exists():
   dest=after/path;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(CORE/path,dest)
 for patch in reversed(later):subprocess.run(['git','-C',str(after),'apply','--reverse',str(patch)],check=True)
 for path in needed:
  original=subprocess.run(['git','-C',str(CORE),'show','HEAD:'+str(path)],capture_output=True)
  if original.returncode==0:
   dest=before/path;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(original.stdout)
 for patch in previous:subprocess.run(['git','-C',str(before),'apply',str(patch)],check=True)
 result=''
 for path in sorted(changed):
  a=before/path;b=after/path
  result+=''.join(difflib.unified_diff(a.read_text().splitlines(True) if a.exists() else [],b.read_text().splitlines(True),fromfile='a/'+str(path) if a.exists() else '/dev/null',tofile='b/'+str(path)))
 TARGET.write_text(result)
