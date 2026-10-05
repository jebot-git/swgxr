"""Bound native-RPC admission; reject before mutation instead of queuing indefinitely."""
import threading
class BackendBusy(RuntimeError):pass
class RequestGate:
 def __init__(self,timeout=3.0,waiting=4):
  self.lock=threading.RLock();self.waiters=threading.BoundedSemaphore(waiting);self.local=threading.local();self.timeout=timeout;self.occupied=threading.Event()
 def __enter__(self):
  depth=getattr(self.local,'depth',0)
  if depth:
   self.lock.acquire();self.local.depth=depth+1;return self
  if not self.waiters.acquire(False):raise BackendBusy('Core3 request queue is full; retry shortly')
  try:
   if not self.lock.acquire(timeout=self.timeout):raise BackendBusy('Core3 is processing another request; retry shortly')
  finally:self.waiters.release()
  self.local.depth=1;self.occupied.set();return self
 def release_completed(self):
  """HTTP response encoding/transmission is outside completed native transactions."""
  if getattr(self.local,'depth',0)==1:
   self.local.depth=0;self.occupied.clear();self.lock.release()
 def __exit__(self,*args):
  if not getattr(self.local,'depth',0):return
  self.local.depth-=1
  if self.local.depth==0:self.occupied.clear()
  self.lock.release()
