import threading,time,unittest
from server.request_gate import RequestGate,BackendBusy
class RequestGateTests(unittest.TestCase):
 def test_reentrant_and_exception_release(self):
  gate=RequestGate(.02,1)
  with self.assertRaises(ValueError):
   with gate:
    with gate:raise ValueError()
  with gate:pass
 def test_wait_deadline_does_not_enter(self):
  gate=RequestGate(.04,1);entered=threading.Event();release=threading.Event()
  def owner():
   with gate:entered.set();release.wait(1)
  thread=threading.Thread(target=owner);thread.start();entered.wait(1)
  before=time.monotonic()
  try:
   with self.assertRaises(BackendBusy):
    with gate:self.fail('Busy request entered')
   self.assertLess(time.monotonic()-before,.3)
  finally:release.set();thread.join()
  with gate:pass
 def test_waiters_are_bounded(self):
  gate=RequestGate(.3,1);started=threading.Event();result=[]
  def waiter():
   started.set()
   try:
    with gate:result.append('entered')
   except BackendBusy:result.append('busy')
  with gate:
   thread=threading.Thread(target=waiter);thread.start();started.wait(1)
   deadline=time.monotonic()+1
   while gate.waiters._value and time.monotonic()<deadline:time.sleep(.001)
   before=time.monotonic()
   # A different thread must not bypass the waiter cap through reentrancy.
   other=threading.Thread(target=waiter);other.start();other.join(.1)
   self.assertFalse(other.is_alive());self.assertEqual(result,['busy'])
   self.assertLess(time.monotonic()-before,.15)
  thread.join();self.assertIn('entered',result)

 def test_completed_response_does_not_hold_native_lane(self):
  gate=RequestGate(.02,1);entered=[]
  def other():
   with gate:entered.append(True)
  with gate:
   gate.release_completed()
   thread=threading.Thread(target=other);thread.start();thread.join(.2)
   self.assertEqual(entered,[True])
  with gate:pass
