#!/usr/bin/env python3
"""Record the pet command and creature companion bridge on top of the existing Core3 patch stack."""
from pathlib import Path
import subprocess,tempfile,difflib
ROOT=Path(__file__).resolve().parents[2];CORE=ROOT/'vendor/Core3';TARGET=ROOT/'server/patches/0046-pet-commands.patch'
commands=Path('MMOCoreORB/src/server/zone/objects/creature/commands')
changed={commands/'SwgxrVehicles.h',commands/'SwgxrPets.h',commands/'SwgxrLiveCombat.h',commands/'pet/PetGuardCommand.h'}
previous=[p for p in sorted(TARGET.parent.glob('*.patch')) if p.name<TARGET.name]
paths=set(changed)
for patch in previous:paths.update(Path(line[6:]) for line in patch.read_text().splitlines() if line.startswith('+++ b/'))
with tempfile.TemporaryDirectory(prefix='swgxr-pet-patch-') as directory:
 before=Path(directory);subprocess.run(['git','init','-q',str(before)],check=True)
 for path in paths:
  original=subprocess.run(['git','-C',str(CORE),'show','HEAD:'+str(path)],capture_output=True)
  if original.returncode==0:
   dest=before/path;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(original.stdout)
 for patch in previous:subprocess.run(['git','-C',str(before),'apply',str(patch)],check=True)
 result=''
 for path in sorted(changed):
  a=(before/path).read_text() if (before/path).exists() else '';b=(CORE/path).read_text()
  result+=''.join(difflib.unified_diff(a.splitlines(True),b.splitlines(True),fromfile='a/'+str(path) if a else '/dev/null',tofile='b/'+str(path)))
 TARGET.write_text(result)
 subprocess.run(['git','-C',str(before),'apply',str(TARGET)],check=True)
 for path in changed:assert (before/path).read_bytes()==(CORE/path).read_bytes(),path
 print('Verified pet command patch against all predecessors:',TARGET)
