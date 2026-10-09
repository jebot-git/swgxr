"""Compile production audience lifecycle and inspiration application with native dependencies isolated."""
from pathlib import Path
import re
import subprocess
import tempfile
import unittest
from tests.test_pistoleer_native import method

ROOT=Path(__file__).resolve().parents[1]
NATIVE=ROOT/'vendor/Core3/MMOCoreORB/src/server/zone'


class EntertainerAudienceNative(unittest.TestCase):
    def test_native_lifecycle_and_inspiration_resources(self):
        with tempfile.TemporaryDirectory(prefix='swgxr-entertainer-audience-') as directory:
            path=Path(directory)
            source=(ROOT/'server/entertainer/SwgxrEntertainerAudience.h').read_text()
            (path/'audience.inc').write_text(source[source.index('class SwgxrEntertainerAudience'):source.rindex('#endif')])
            source=(NATIVE/'objects/player/sessions/EntertainingSessionImplementation.cpp').read_text()
            names=('activateEntertainerBuff','increaseEntertainerBuff')
            (path/'effects.inc').write_text('\n'.join(method(source,'void EntertainingSessionImplementation::'+name+'(') for name in names))
            source=(NATIVE/'objects/creature/buffs/BuffImplementation.cpp').read_text()
            guard=re.search(r'if \((!creo->isDead\(\).*buffType==BuffType::PERFORMANCE.*?)\) \{',source)[1]
            (path/'fill.inc').write_text('bool nativeFills(CreatureObject* creo,int buffType) {return '+guard+';}')
            result=subprocess.run(['c++','-std=c++17','-I'+directory,str(ROOT/'tests/entertainer_audience_native.cpp'),'-o',str(path/'check')],capture_output=True,text=True,timeout=60)
            self.assertEqual(result.returncode,0,result.stderr)
            result=subprocess.run([str(path/'check')],capture_output=True,text=True,timeout=15)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            print(result.stdout.strip())

    def test_installed_hooks_and_original_cleanup(self):
        self.assertEqual((ROOT/'server/entertainer/SwgxrEntertainerAudience.h').read_bytes(),(NATIVE/'objects/creature/commands/SwgxrEntertainerAudience.h').read_bytes())
        source=(NATIVE/'objects/player/sessions/EntertainingSessionImplementation.cpp').read_text()
        effects=method(source,'void EntertainingSessionImplementation::doEntertainerPatronEffects(')
        self.assertLess(effects.index('SwgxrEntertainerAudience::synchronize'),effects.index('getPatrons()'))
        self.assertIn('SwgxrEntertainerAudience::sourceID(patron, isDancing()) != creo->getObjectID()',effects)
        self.assertIn('SwgxrEntertainerAudience::deliver',effects)
        self.assertNotIn('SwgxrEntertainerAudience::deliver',method(source,'void EntertainingSessionImplementation::increaseEntertainerBuff('))
        self.assertIn('SwgxrEntertainerAudience::synchronize',method(source,'void EntertainingSessionImplementation::startEntertaining('))
        for name,stop in [('stopPlaying','stopListen'),('stopDancing','stopWatch')]:
            body=method(source,'void EntertainingSessionImplementation::'+name+'(')
            self.assertIn('while (patronDataMap.size() > 0)',body)
            self.assertIn('playerManager->'+stop,body)
            self.assertIn('patronDataMap.drop(patron)',body)
            self.assertIn('tickTask->cancel()',body)
        action=method(source,'void EntertainingSessionImplementation::activateAction(')
        self.assertIn('!SwgxrEntertainerAudience::available(entertainer)',action)
        self.assertIn('cancelSession(); return;',action)
        self.assertEqual(action.count('startTickTask();'),1)
