#!/usr/bin/env python3
"""Non-stopping perf-event sample of an explicitly supplied existing main TID."""
import argparse,datetime,json,os,pathlib,signal,subprocess,sys,time
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--pid',type=int,required=True,help='Existing Godot main thread ID; no client signal or restart is performed.')
parser.add_argument('--output',type=pathlib.Path,required=True,help='New directory for collection metadata, maps and eu-stackprof artifacts.')
parser.add_argument('--seconds',type=float,default=20,help='Bounded collection duration, 1–60 seconds (default20).')
args=parser.parse_args()
pid=args.pid;out=args.output;duration=args.seconds
if pid<=0 or not 1<=duration<=60: parser.error('Require a positive PID and duration between1 and60seconds.')
if (out/'collector.log').exists(): parser.error('Output contains an existing collection; choose a new directory.')
out.mkdir(parents=True,exist_ok=True)
proc=pathlib.Path('/proc')/str(pid)
exe=os.readlink(proc/'exe')
if pathlib.Path(exe).name!='godot':raise SystemExit('Refusing non-Godot target '+exe)
def stat(path):
 raw=path.read_text();fields=raw[raw.rfind(')')+2:].split()
 return {'utime_ticks':int(fields[11]),'stime_ticks':int(fields[12]),'start_ticks':int(fields[19]),'state':fields[0]}
def threads():
 result={}
 for p in (proc/'task').iterdir():
  try:result[p.name]={'name':(p/'comm').read_text().strip(),**stat(p/'stat')}
  except FileNotFoundError:pass
 return result
before=threads();start=time.monotonic();stamp=datetime.datetime.now(datetime.timezone.utc).isoformat()
(out/'maps.txt').write_text((proc/'maps').read_text())
cmd=['eu-stackprof','-e','cycles:u:period=20000000','-vvv','-n','24','-o',str(out),'-p',str(pid)]
with (out/'collector.log').open('w') as log:
 collector=subprocess.Popen(cmd,stdout=log,stderr=subprocess.STDOUT)
 try:collector.wait(timeout=duration)
 except subprocess.TimeoutExpired:
  collector.send_signal(signal.SIGINT)
  try:collector.wait(timeout=10)
  except subprocess.TimeoutExpired:collector.kill();collector.wait()
end=time.monotonic();after=threads() if proc.exists() else {}
meta={'target_pid':pid,'target_exe':exe,'started_utc':stamp,'requested_seconds':duration,'elapsed_seconds':end-start,'collector_pid':collector.pid,'collector_exit':collector.returncode,'command':cmd,'threads_before':before,'threads_after':after,'clock_ticks':os.sysconf('SC_CLK_TCK'),'target_stopped_by_collector':False,'notes':['perf_event_open for main TID only, inherited by any newly created descendants.','Existing sibling threads are excluded; kernel cycles and blocked/wait wall time excluded.','SIGINT delivered only to profiler; no ptrace stop or client signal used.','This window is instrumented and is not a normal-play timing baseline.']}
if str(pid) in after and after[str(pid)]['start_ticks']==before[str(pid)]['start_ticks']:
 delta=sum(after[str(pid)][k]-before[str(pid)][k] for k in ['utime_ticks','stime_ticks'])
 meta['main_thread_cpu_percent']=100*delta/meta['clock_ticks']/(end-start)
(out/'collection.json').write_text(json.dumps(meta,indent=2)+'\n')
print(json.dumps({k:v for k,v in meta.items() if not k.startswith('threads_')},indent=2))
