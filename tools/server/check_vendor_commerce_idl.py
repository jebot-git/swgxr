#!/usr/bin/env python3
"""Check the changed Core3 schemas with its bundled compiler; not a C++ build."""
from pathlib import Path
import json, os, subprocess, tempfile
ROOT=Path(__file__).resolve().parents[2]
CORE=ROOT/'vendor/Core3/MMOCoreORB';SOURCE=CORE/'src'
engine=CORE/'utils/engine3/MMOEngine'
records=[]
with tempfile.TemporaryDirectory(prefix='swgxr-commerce-idl-') as directory:
 output=Path(directory)
 for source in ['server/zone/objects/auction/AuctionItem.idl','server/zone/managers/auction/AuctionManager.idl']:
  result=subprocess.run(['java','-cp',str(engine/'lib/idlc.jar'),'org.sr.idlc.compiler.Compiler','-cp',str(engine/'src'),'-outdir',os.path.relpath(output,SOURCE),'-sd',str(SOURCE),source],capture_output=True,text=True)
  record={'source':source,'exit_code':result.returncode,'output':result.stdout+result.stderr};records.append(record)
  generated=output/Path(source).with_suffix('.cpp')
  if result.returncode or 'error' in record['output'].lower() or not generated.exists():raise SystemExit(json.dumps(records,indent=2))
 body=(output/'server/zone/objects/auction/AuctionItem.cpp').read_text()
 assert 'TypeInfo<String >::parseFromBinaryStream(&swgxrSearchPolicy' in body
 assert 'return swgxrSearchPolicy != "local"' in body
record={'passed':True,'checks':records,'scope':'IDL generation and legacy-empty search policy; not native C++ compilation'}
path=ROOT/'runtime/evidence/vendor-commerce-idl.json';path.parent.mkdir(parents=True,exist_ok=True);path.write_text(json.dumps(record,indent=2)+'\n')
print(json.dumps(record))
