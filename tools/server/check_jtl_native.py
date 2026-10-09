#!/usr/bin/env python3
"""Syntax-check actual Core3 JtL and gameplay headers without linking/running Core3.

Use installed development headers or repeat --dependency-include for locally
available build SDK directories. This is not a replacement for the linked build.
"""
import argparse
import hashlib
import json
import subprocess
import tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
CORE=ROOT/'vendor/Core3/MMOCoreORB'
def main():
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument('--dependency-include',action='append',type=Path,default=[])
 parser.add_argument('--regenerate-account-idl',action='store_true')
 parser.add_argument('--output',type=Path,default=ROOT/'runtime/evidence/jtl/native-syntax.json')
 args=parser.parse_args()
 report={'scope':'production Core3 headers, syntax only; no linked server or runtime validation','commands':[]}
 if args.regenerate_account_idl:
  cmd=['java','-XX:TieredStopAtLevel=1','-client','-Xmx128M','-cp','utils/engine3/MMOEngine/lib/idlc.jar','org.sr.idlc.compiler.Compiler','-outdir','autogen','-cp','utils/engine3/MMOEngine/src','-nomocks','-silence','-rbcpp','-sd','src','server/login/account/Account.idl']
  result=subprocess.run(cmd,cwd=CORE,capture_output=True,text=True)
  report['commands'].append({'command':cmd,'cwd':str(CORE),'exit_code':result.returncode,'output':result.stdout+result.stderr})
  if result.returncode:raise SystemExit(result.stdout+result.stderr)
 includes=[CORE/'src',CORE/'src/autogen',CORE/'utils',CORE/'utils/engine3/MMOEngine/src',CORE/'src/server/zone/objects/creature/commands']+args.dependency_include
 with tempfile.TemporaryDirectory(prefix='swgxr-jtl-syntax-') as temp:
  source=Path(temp)/'jtl.cpp'
  source.write_text('#include <set>\n#include "server/zone/objects/player/PlayerObject.h"\n#include "server/zone/objects/tangible/Instrument.h"\n#include "server/zone/objects/creature/commands/CombatQueueCommand.h"\n#include "server/zone/objects/creature/commands/GetAttributesBatchCommand.h"\n')
  for unit in (source,CORE/'src/server/login/account/AccountImplementation.cpp',CORE/'src/server/zone/managers/space/SpaceManagerImplementation.cpp',CORE/'src/server/zone/objects/player/PlayerObjectImplementation.cpp',CORE/'src/server/zone/objects/ship/ShipObjectImplementation.cpp'):
   cmd=['c++','-std=gnu++14','-fsyntax-only','-DDEFAULT_DYNAMIC_CAST','-DODB_REFERENCES','-Wno-multichar']+['-I'+str(i)for i in includes]+[str(unit)]
   result=subprocess.run(cmd,cwd=ROOT,capture_output=True,text=True,timeout=120)
   report['commands'].append({'command':cmd,'cwd':str(ROOT),'exit_code':result.returncode,'output':result.stdout+result.stderr})
 report['passed']=all(row['exit_code']==0 for row in report['commands'])
 files=['src/server/login/account/Account.idl','src/server/login/account/AccountImplementation.cpp','src/server/zone/objects/creature/commands/SwgxrJtl.h','src/server/zone/objects/creature/commands/JtlPolicy.h','src/server/zone/objects/creature/commands/SwgxrJtlLifecycle.h','src/server/zone/objects/creature/commands/SwgxrPublicAppearance.h','src/server/zone/objects/player/PlayerObjectImplementation.cpp','src/server/zone/objects/ship/ShipObjectImplementation.cpp','src/server/zone/objects/creature/commands/SwgxrServices.h','src/server/zone/objects/creature/commands/SwgxrHousing.h','src/server/zone/objects/creature/commands/SwgxrLiveCombat.h']
 report['source_sha256']={name:hashlib.sha256((CORE/name).read_bytes()).hexdigest()for name in files}
 args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(json.dumps(report,indent=2)+'\n')
 print(json.dumps({'passed':report['passed'],'output':str(args.output)}));raise SystemExit(0 if report['passed']else 1)
if __name__=='__main__':main()
