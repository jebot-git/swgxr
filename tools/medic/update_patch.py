#!/usr/bin/env python3
"""Keep medical changes separate from concurrent terminal-service work."""
from pathlib import Path
import subprocess,tempfile,difflib
ROOT=Path(__file__).resolve().parents[2];CORE=ROOT/'vendor/Core3';TARGET=ROOT/'server/patches/0027-medic.patch'
base=Path('MMOCoreORB/src');commands=base/'server/zone/objects/creature/commands'
changed={base/'server/zone/objects/creature/CreatureObjectImplementation.cpp',base/'client/actions/ZoneInCharacterAction.cpp'}
changed.update(commands/(name+'.h') for name in ['SwgxrMedic','SwgxrMedicDrag','SwgxrVitalFeedback','SwgxrGathering','SwgxrInventory','SwgxrLiveCombat','GetAttributesBatchCommand','HealDamageCommand','HealWoundCommand','TendCommand','FirstAidCommand','QuickHealCommand'])
previous=[p for p in sorted(TARGET.parent.glob('*.patch')) if p.name<TARGET.name]
paths=set(changed)
for patch in previous:paths.update(Path(line[6:]) for line in patch.read_text().splitlines() if line.startswith('+++ b/'))
with tempfile.TemporaryDirectory(prefix='swgxr-medic-patch-') as directory:
 before=Path(directory);subprocess.run(['git','init','-q',str(before)],check=True)
 for path in paths:
  original=subprocess.run(['git','-C',str(CORE),'show','HEAD:'+str(path)],capture_output=True)
  if original.returncode==0:
   dest=before/path;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(original.stdout)
 for patch in previous:subprocess.run(['git','-C',str(before),'apply',str(patch)],check=True)
 result=''
 for path in sorted(changed):
  a=(before/path).read_text() if (before/path).exists() else ''
  b=(CORE/path).read_text()
  # These shared files also contain terminal work in progress. Derive only our
  # additions from the known earlier patch stack instead of absorbing that work.
  if path.name=='SwgxrLiveCombat.h':
   b=a.replace('#include "SwgxrScout.h"','#include "SwgxrScout.h"\n#include "SwgxrMedic.h"\n#include "SwgxrVitalFeedback.h"')
   b=b.replace('if(verb=="update"){','if(verb=="update"){\n   if(request.contains("medic_pose"))SwgxrMedicDrag::observe(c,request.at("medic_pose"));')
   b=b.replace('if(verb=="scout")','if(verb=="medic"){if(!s.transport.empty())throw std::runtime_error("native_transport_pending");return SwgxrMedic::run(c,request.at("medic"));}\n  if(verb=="scout")')
   b=b.replace('auto loc=location(c);','out["player"]["medical_drag"]=SwgxrMedicDrag::snapshot(c);out["player"]["vital_feedback"]=SwgxrVitalFeedback::snapshot(c->getObjectID());\n  auto loc=location(c);')
  elif path.name=='GetAttributesBatchCommand.h':
   start=a.index('\t\tif (creature->isPlayerCreature()',a.index('swgxr_scout_v1')-160);end=a.index('\n\t\tif (!checkStateMask',start)
   block=a[start:end];b=a[:end]+block.replace('SwgxrScout','SwgxrMedic').replace('scout','medic')+a[end:]
  elif path.name=='ZoneInCharacterAction.cpp':
   b=a.replace('const bool scout=','const bool medic=inventoryRequest.find("swgxr_medic_v1 ")==0;\n\t\t\tconst bool scout=')
   b=b.replace('field=scout?', 'field=medic?"swgxr.medic.snapshot":scout?').replace('core.setVar(scout?', 'core.setVar(medic?"medic":scout?')
  result+=''.join(difflib.unified_diff(a.splitlines(True),b.splitlines(True),fromfile='a/'+str(path) if a else '/dev/null',tofile='b/'+str(path)))
 TARGET.write_text(result)
 print(TARGET)
