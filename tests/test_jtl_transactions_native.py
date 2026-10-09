"""Execute actual production stage, launch, docking, return and receipt branches."""
from pathlib import Path
import subprocess
import tempfile
import unittest
from tests.test_carbineer_native import method
ROOT=Path(__file__).resolve().parents[1]
class JtlTransactionsNative(unittest.TestCase):
 def test_native_transactions(self):
  source=(ROOT/'server/jtl/SwgxrJtl.h').read_text()
  signatures=(' static Json data(', ' static void save(', ' static bool atTerminal(', ' static void cancelStage(', ' static Json stage(', ' static void removeFromStage(', ' static void crewAction(', ' static void boardingAction(', ' static void eject(', 'static void recoverGround(', ' static void expire(', ' static Json boardingState(', ' static Json finish(')
  methods='\n'.join(method(source,key) for key in signatures)
  launch=method(source,'  if(action=="launch"){')
  prefix=method(source,' static Json run(').split('  if(action=="crew_prepare"',1)[0].replace(' static Json run(', ' static Json receipt(',1)
  methods+='\nstatic void launch(CreatureObject*c,ShipObject*s,const Json&r){auto action=r.at("action").get<std::string>();'+launch+'}\n'+prefix+'++actions;return finish(c,canonical,receipts);}\n'
  with tempfile.TemporaryDirectory(prefix='jtl-transactions-') as temp:
   p=Path(temp);(p/'jtl_transactions.inc').write_text(methods)
   live=(ROOT/'vendor/Core3/MMOCoreORB/src/server/zone/objects/creature/commands/SwgxrLiveCombat.h').read_text()
   (p/'jtl_dispatch.inc').write_text('static Json action(CreatureObject*c,Session&s,const Json&request){std::string requestedVerb="jtl";'+method(live,'  if(requestedVerb=="jtl"){')+'return Json::object();}')
   lease_methods=method(source,' struct Lease {')+';\n'+'\n'.join(method(source,key)for key in (' static std::map<uint64,Lease>& leases(', ' static std::mutex& leaseMutex(', ' static void watchdog(', ' static void attach(', ' static void touch(', ' static void detach(', ' static void disconnected('))
   (p/'jtl_lease.inc').write_text(lease_methods)
   build=subprocess.run(['c++','-std=c++17','-I'+temp,str(ROOT/'tests/jtl_transactions_native.cpp'),'-o',str(p/'check')],capture_output=True,text=True,timeout=60)
   self.assertEqual(build.returncode,0,build.stderr)
   run=subprocess.run([str(p/'check')],capture_output=True,text=True,timeout=15)
   self.assertEqual(run.returncode,0,run.stdout+run.stderr);print(run.stdout.strip())
if __name__=='__main__':unittest.main()
