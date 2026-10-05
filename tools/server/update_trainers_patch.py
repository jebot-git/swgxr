#!/usr/bin/env python3
"""Regenerate ONLY the owned basic trainers patch against its pinned predecessors."""
import difflib,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];CORE=ROOT/'vendor/Core3'
OWNED=['MMOCoreORB/src/server/zone/objects/creature/commands/'+n for n in ['SwgxrServices.h','SwgxrLiveCombat.h','SwgxrTrainers.h','SwgxrTrainerCatalog.h']]
def main():
 patches=[p for p in sorted((ROOT/'server/patches').glob('*.patch'))if p.name<'0029-basic-trainers.patch']
 paths=set(OWNED)|{line[6:]for patch in patches for line in patch.read_text().splitlines()if line.startswith('+++ b/')}
 with tempfile.TemporaryDirectory(prefix='swgxr-trainers-patch-')as temp:
  tree=Path(temp);subprocess.run(['git','init','-q',str(tree)],check=True)
  for p in paths:
   old=subprocess.run(['git','-C',str(CORE),'show','HEAD:'+p],capture_output=True)
   if old.returncode==0:(tree/p).parent.mkdir(parents=True,exist_ok=True);(tree/p).write_bytes(old.stdout)
  for patch in patches:subprocess.run(['git','-C',str(tree),'apply',str(patch)],check=True)
  lines=[]
  for p in OWNED:
   baseline=(tree/p).read_text()if(tree/p).exists()else'';desired=(CORE/p).read_text()
   if p.endswith('SwgxrLiveCombat.h') and 'SwgxrVehicles' in desired and 'SwgxrVehicles' not in baseline:
    raise SystemExit('Preserving concurrent vehicle edits; pin their predecessor separately before regenerating trainers.')
   lines.extend(difflib.unified_diff(baseline.splitlines(True),desired.splitlines(True),fromfile='a/'+p if baseline else'/dev/null',tofile='b/'+p,n=3))
  target=ROOT/'server/patches/0029-basic-trainers.patch';target.write_text(''.join(lines))
  subprocess.run(['git','-C',str(tree),'apply',str(target)],check=True)
  for p in OWNED:assert (tree/p).read_bytes()==(CORE/p).read_bytes(),p
  print('Pinned trainers patch verified:',len(lines),'lines in',len(OWNED),'owned files')
if __name__=='__main__':main()
