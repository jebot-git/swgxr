#!/usr/bin/env python3
"""Read-only capture of a live WiVRn performance feed and a selected Linux process.

WiVRn pacing values are smoothed estimates; GPU wait is not GPU rendering time.
No injection, process restart, input simulation or runtime settings changes.
"""
import argparse
from datetime import datetime, timezone
import json
import math
import os
from pathlib import Path
import time


def statistics(values):
    values=sorted(v for v in values if isinstance(v,(float,int)) and math.isfinite(v))
    if not values:return {'available':False,'samples':0}
    return {'available':True,'samples':len(values),'mean':sum(values)/len(values),
            **{f'p{p}':values[max(0,math.ceil(len(values)*p/100)-1)] for p in [50,95,99]},'max':values[-1]}


def proc_stat(path):
    text=path.read_text();fields=text[text.rfind(')')+2:].split()
    return {'cpu_ticks':int(fields[11])+int(fields[12]),'start_ticks':int(fields[19]),'rss_bytes':int(fields[21])*os.sysconf('SC_PAGE_SIZE')}


def process_sample(pid):
    root=Path('/proc')/str(pid)
    sample=proc_stat(root/'stat')
    sample['monotonic_ns']=time.monotonic_ns()
    sample['threads']={}
    for entry in (root/'task').iterdir():
        try:sample['threads'][entry.name]={'name':(entry/'comm').read_text().strip(),**proc_stat(entry/'stat')}
        except (OSError,ValueError,IndexError):pass
    clients={}
    for entry in (root/'fdinfo').iterdir():
        try:
            fields=dict(line.split(':',1) for line in entry.read_text().splitlines() if ':' in line)
            if 'drm-client-id' not in fields:continue
            key=fields.get('drm-pdev','').strip()+':'+fields['drm-client-id'].strip()
            clients[key]={k:int(v.strip().split()[0]) for k,v in fields.items() if k.startswith(('drm-engine-','drm-resident-')) and not k.startswith('drm-engine-capacity-')}
        except (OSError,ValueError):pass
    sample['drm_clients']=clients
    return sample


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--pid',type=int,required=True)
    p.add_argument('--app-id',type=int,required=True,help='WiVRn pacer ID; feed does not export PID mapping')
    p.add_argument('--duration',type=float,default=60)
    p.add_argument('--feed',type=Path,default=Path(os.environ.get('XDG_RUNTIME_DIR','/run/user/1000'))/'wivrn-pro/performance.json')
    p.add_argument('--output',type=Path,required=True)
    args=p.parse_args()
    if not 1<=args.duration<=600:p.error('duration must be1–600 seconds')
    args.output.mkdir(parents=True,exist_ok=True)
    command=(Path('/proc')/str(args.pid)/'cmdline').read_bytes().replace(b'\0',b' ').decode().strip()
    start=time.monotonic();next_proc=0;last_update=None;snapshots=[];process=[];errors=[]
    print(f'Capturing live PID {args.pid}, runtime app {args.app_id}, {args.duration:g} seconds',flush=True)
    with (args.output/'samples.jsonl').open('w') as raw:
        while time.monotonic()-start<args.duration:
            now=time.monotonic()
            try:
                data=json.loads(args.feed.read_text())
                if data.get('updated_ns')!=last_update:
                    last_update=data.get('updated_ns')
                    record={'monotonic_ns':time.monotonic_ns(),'runtime':data}
                    raw.write(json.dumps(record)+'\n');raw.flush();snapshots.append(record)
            except (OSError,ValueError) as exc:errors.append(str(exc))
            if now>=next_proc:
                try:
                    sample=process_sample(args.pid);process.append(sample)
                    raw.write(json.dumps({'process':sample})+'\n');raw.flush()
                except (OSError,ValueError,IndexError) as exc:errors.append(str(exc))
                next_proc=now+1
            time.sleep(.05)
    # Reject stale runtime observations and deduplicate app completion reports.
    apps=[];seen=set();stream_samples={}
    for record in snapshots:
        runtime=record['runtime'];now=record['monotonic_ns']
        for app in runtime.get('apps',[]):
            key=(runtime.get('session'),app['id'],app['completed'])
            if app['id']==args.app_id and 0<=now-app['updated_ns']<=2_000_000_000 and key not in seen:
                seen.add(key);apps.append(app)
        for stream in runtime.get('streams',[]):
            if 0<=now-stream['updated_ns']<=2_000_000_000:
                bucket=stream_samples.setdefault(stream['id'],[])
                if not bucket or bucket[-1]['updated_ns']!=stream['updated_ns']:bucket.append(stream)
    intervals=[];cpu=[];gpu=[];rss=[];ticks=os.sysconf('SC_CLK_TCK')
    for previous,current in zip(process,process[1:]):
        seconds=(current['monotonic_ns']-previous['monotonic_ns'])/1e9
        if current['start_ticks']!=previous['start_ticks']:errors.append('process PID was reused');continue
        cpu.append((current['cpu_ticks']-previous['cpu_ticks'])/ticks/seconds*100)
        busy=0
        for key,client in current['drm_clients'].items():
            if key in previous['drm_clients']:
                before=previous['drm_clients'][key]
                busy+=max(0,client.get('drm-engine-render',0)-before.get('drm-engine-render',0))
        gpu.append(busy/(seconds*1e9)*100)
        rss.append(current['rss_bytes']/1024**2)
    threads=[]
    if len(process)>1:
        elapsed=(process[-1]['monotonic_ns']-process[0]['monotonic_ns'])/1e9
        for tid,last in process[-1]['threads'].items():
            first=process[0]['threads'].get(tid)
            if first and first['start_ticks']==last['start_ticks']:
                threads.append({'tid':int(tid),'name':last['name'],'cpu_percent_one_core':100*(last['cpu_ticks']-first['cpu_ticks'])/ticks/elapsed})
    app_seconds=(apps[-1]['updated_ns']-apps[0]['updated_ns'])/1e9 if len(apps)>1 else 0
    delivered=apps[-1]['completed']-apps[0]['completed'] if app_seconds>0 else 0
    stream_report={}
    for sid,values in stream_samples.items():
        stream_report[str(sid)]={k:statistics([v.get(k) for v in values]) for k in ['encode_ms','delivery_ms','decode_ms','encode_display_ms']}
        stream_report[str(sid)].update({'received_frame_counter_delta':values[-1]['frames']-values[0]['frames'],'repeat_counter_delta':values[-1]['repeats']-values[0]['repeats']})
    sessions={r['runtime'].get('session') for r in snapshots}
    if len(sessions)!=1:errors.append('runtime session changed or no feed')
    report={'type':'live_vr_observation','utc':datetime.now(timezone.utc).isoformat(),'pid':args.pid,'command':command,'runtime_app_id':args.app_id,
        'app_pid_mapping':'Selected by runtime launch correlation; WiVRn feed does not expose PID/name mapping',
        'duration_seconds':time.monotonic()-start,'runtime_snapshot_count':len(snapshots),'unique_app_samples':len(apps),
        'passed':bool(apps) and len(process)>1 and not errors,'errors':errors,
        'target_hz':snapshots[-1]['runtime'].get('target_hz') if snapshots else None,
        'app_completed_frames':delivered,'app_observation_seconds':app_seconds,'app_completed_fps':delivered/app_seconds if app_seconds>0 else None,
        'sampled_smoothed_interval_ms':statistics([a['interval_ms'] for a in apps]),
        'sampled_smoothed_cpu_pacing_ms':statistics([a['cpu_ms'] for a in apps]),
        'sampled_smoothed_gpu_wait_ms':statistics([a['gpu_ms'] for a in apps]),
        'samples_over_refresh_budget_fraction':sum(a['interval_ms']>a['period_ms']*1.05 for a in apps)/len(apps) if apps else None,
        'process_cpu_percent_one_core':statistics(cpu),'process_render_engine_busy_percent':statistics(gpu),'process_rss_mib':statistics(rss),
        'threads_by_cpu':sorted(threads,key=lambda v:v['cpu_percent_one_core'],reverse=True)[:15],'streams':stream_report,
        'limitations':['Passive live workload; no synthetic crowd or input injected','Interval/CPU/GPU-wait values are WiVRn EMA-smoothed, sampled snapshots; percentile values are not raw per-frame percentiles','CPU pacing includes waiting/driver submission and is capped by runtime to three periods; it is not CPU execution time','GPU wait is delivery-to-completion wait, not full GPU render duration','Encode-to-display is not motion-to-photon latency','DRM render-engine activity is selected-process cumulative busy time; not total GPU utilization','No process restart, renderer/refresh change or competing GPU benchmark']}
    report['capture_valid']=report['passed']
    report['performance_target_met']=(report['app_completed_fps'] is not None and report['target_hz'] is not None and report['app_completed_fps']>=report['target_hz']*.98)
    report['performance_target_scope']='Average completed app frames within2% of reported refresh; not a raw-frame tail-latency test'
    (args.output/'summary.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({'passed':report['passed'],'completed_fps':report['app_completed_fps'],'sampled_interval_ms':report['sampled_smoothed_interval_ms'],'cpu_percent':report['process_cpu_percent_one_core'],'render_busy':report['process_render_engine_busy_percent'],'report':str(args.output/'summary.json')}),flush=True)
    return 0 if report['passed'] else 1

if __name__=='__main__':raise SystemExit(main())
