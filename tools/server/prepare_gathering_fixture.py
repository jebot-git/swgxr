#!/usr/bin/env python3
"""Temporarily install a strictly bound disposable native gathering test fixture.

The corpse phase sets DEAD posture on a real source creature; this tests native
corpse interactions, not a native combat/death bridge. Restore removes the hook.
"""
import argparse,json,time
from pathlib import Path
from equipment_smoke import console
ROOT=Path(__file__).resolve().parents[2]
TARGET=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/tests/tests.lua'
BACKUP=ROOT/'runtime/server/gathering-tests-original.lua'

def main():
 p=argparse.ArgumentParser();p.add_argument('--fixture',type=Path);p.add_argument('--restore',action='store_true');p.add_argument('--phase',choices=['skills','corpse','cleanup_corpse','fill','clear_filler','clear_organic']);a=p.parse_args()
 if a.restore:
  if BACKUP.exists():TARGET.write_bytes(BACKUP.read_bytes());BACKUP.unlink();console('reloadscreenplays')
  return
 if a.fixture is None:p.error('--fixture is required')
 f=json.loads(a.fixture.read_text());assert f['account'].startswith('invtest') and f['name'].startswith('Ivtest') and str(f['id']).isdigit(), 'Only explicit disposable fixtures allowed'
 if not BACKUP.exists():BACKUP.write_bytes(TARGET.read_bytes())
 source=(ROOT/'tools/server/gathering_fixture.lua').read_text().replace('__FIXTURE_ID__',str(f['id']))
 TARGET.write_text(BACKUP.read_text()+'\n'+source);console('reloadscreenplays');time.sleep(.5)
 if a.phase:console('runLuaFunction Tests:swgxrGatheringFixture:'+str(f['id'])+':'+a.phase)
 print('Installed bounded fixture for character '+str(f['id'])+'. Restore after validation.')
if __name__=='__main__':main()
