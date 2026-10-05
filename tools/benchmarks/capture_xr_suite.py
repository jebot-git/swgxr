#!/usr/bin/env python3
"""Tag passive WiVRn and /proc counters with the opt-in XR suite's phases."""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import time

from capture_live_vr import process_sample, statistics


def summarize(records, app_id):
    phases = {}
    sessions = set()
    for record in records:
        status = record.get('status', {})
        if not status.get('measuring', False):
            continue
        phase = str(status['phase'])
        bucket = phases.setdefault(phase, {'apps':[], 'process':[], 'target_hz':None})
        runtime = record.get('runtime', {})
        if runtime:
            sessions.add(runtime.get('session'))
            bucket['target_hz'] = runtime.get('target_hz')
        for app in runtime.get('apps', []):
            if app['id'] != app_id or not 0 <= record['monotonic_ns']-app['updated_ns'] <= 2_000_000_000:
                continue
            if not bucket['apps'] or app['completed'] != bucket['apps'][-1]['completed']:
                bucket['apps'].append(app)
        if 'process' in record:
            bucket['process'].append(record['process'])
    result = {}
    ticks = os.sysconf('SC_CLK_TCK')
    for name, values in phases.items():
        apps, samples = values['apps'], values['process']
        elapsed = (apps[-1]['updated_ns']-apps[0]['updated_ns'])/1e9 if len(apps)>1 else 0
        delivered = apps[-1]['completed']-apps[0]['completed'] if elapsed>0 else 0
        cpu, gpu, main = [], [], []
        for previous, current in zip(samples, samples[1:]):
            seconds = (current['monotonic_ns']-previous['monotonic_ns'])/1e9
            if seconds <= 0 or current['start_ticks'] != previous['start_ticks']:
                continue
            cpu.append(100*(current['cpu_ticks']-previous['cpu_ticks'])/ticks/seconds)
            pid = str(current['pid'])
            if pid in current['threads'] and pid in previous['threads']:
                main.append(100*(current['threads'][pid]['cpu_ticks']-previous['threads'][pid]['cpu_ticks'])/ticks/seconds)
            busy = sum(max(0,client.get('drm-engine-render',0)-previous['drm_clients'][key].get('drm-engine-render',0))
                       for key,client in current['drm_clients'].items() if key in previous['drm_clients'])
            gpu.append(100*busy/(seconds*1e9))
        result[name] = {'completed_fps':delivered/elapsed if elapsed else None,'observation_seconds':elapsed,
                        'completed_frames':delivered,'target_hz':values['target_hz'],
                        'smoothed_interval_ms':statistics([a['interval_ms'] for a in apps]),
                        'cpu_percent_one_core':statistics(cpu),'main_thread_percent_one_core':statistics(main),
                        'render_engine_busy_percent':statistics(gpu),'capture_valid':elapsed>=5 and bool(cpu)}
    return result, len(sessions)==1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pid',type=int,required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--feed',type=Path,default=Path('/run/user/1000/wivrn-pro/performance.json'))
    parser.add_argument('--timeout',type=float,default=600)
    args = parser.parse_args()
    root = args.output.resolve(); root.mkdir(parents=True,exist_ok=True)
    old = {a['id'] for a in json.loads((root/'runtime-before.json').read_text()).get('apps',[])}
    app_id = None; records = []; errors = []; last_phase = None; next_proc = 0
    deadline = time.monotonic()+args.timeout
    with (root/'external-samples.jsonl').open('w') as raw:
        while time.monotonic()<deadline:
            if not Path(f'/proc/{args.pid}').exists(): errors.append('Client exited');break
            try:
                status = json.loads((root/'status.json').read_text())
                runtime = json.loads(args.feed.read_text())
            except (FileNotFoundError,ValueError):
                time.sleep(.2);continue
            if app_id is None:
                candidates = [a['id'] for a in runtime.get('apps',[]) if a['id'] not in old and a['completed']>0]
                if len(candidates)>1: errors.append('Ambiguous runtime pacer correlation');break
                if candidates: app_id=candidates[0]
            state = (status.get('phase'),status.get('measuring'))
            if state!=last_phase: print('XR suite:',state,flush=True);last_phase=state
            record = {'monotonic_ns':time.monotonic_ns(),'status':status,'runtime':runtime}
            if time.monotonic()>=next_proc:
                try:
                    record['process']=process_sample(args.pid);record['process']['pid']=args.pid
                except (OSError,ValueError) as exc:errors.append(str(exc));break
                next_proc=time.monotonic()+1
            records.append(record);raw.write(json.dumps(record)+'\n');raw.flush()
            if status.get('phase') in ['done','cancelled','failed']:break
            time.sleep(.2)
        else:errors.append('Suite timeout')
    phases, stable = summarize(records, app_id)
    if not stable:errors.append('Missing or changing runtime session')
    expected = {'baseline','no_spectator','frozen_npc_animation','headset_half_resolution','scene_hidden','restore_baseline'}
    if set(phases) != expected:errors.append('Missing controlled measurement phases')
    final_status = records[-1].get('status', {}) if records else {}
    if final_status.get('phase') != 'done' or final_status.get('error') or final_status.get('io_error'):
        errors.append('Suite did not complete successfully')
    report = {'utc':datetime.now(timezone.utc).isoformat(),'pid':args.pid,'runtime_app_id':app_id,
              'passed':bool(phases) and not errors and all(p['capture_valid'] for p in phases.values()),'errors':errors,'phases':phases,
              'limits':['Same running OpenXR client; phases tagged by diagnostic status file',
                        'Runtime pacer selected by launch correlation; feed lacks authoritative PID mapping',
                        'WiVRn intervals are sampled smoothed estimates, not raw frame percentiles',
                        'CPU is measured per one core; DRM activity is selected-process render engine time',
                        'View direction and physical tracking can change; consult suite pose/focus drift evidence']}
    (root/'external-summary.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report),flush=True)
    return 0 if report['passed'] else 1


if __name__=='__main__':raise SystemExit(main())
