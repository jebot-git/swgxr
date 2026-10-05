#!/usr/bin/env python3
"""Run bounded MMO viability targets. Results distinguish correctness from capacity."""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'tools'))
from client.launch_environment import client_environment
PROFILES = [(16, 16), (32, 24), (64, 32), (128, 64)]

def workloads():
    found = []
    for entry in Path('/proc').iterdir():
        if not entry.name.isdigit():
            continue
        try:
            command = (entry/'cmdline').read_bytes().replace(b'\0', b' ').decode(errors='replace').strip()
            name = (entry/'comm').read_text().strip()
        except (OSError, ProcessLookupError):
            continue
        if name.lower().startswith('godot'):
            found.append({'pid':int(entry.name),'command':command,'xr_enabled':'--xr-mode on' in command})
    return found

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mode', choices=['simulation','collision','render','all'], default='all')
    parser.add_argument('--tiers', default='16,32,64,128')
    parser.add_argument('--quick', action='store_true', help='Functional smoke only; insufficient duration for performance qualification')
    parser.add_argument('--duration',type=float,default=15)
    parser.add_argument('--warmup',type=float,default=5)
    parser.add_argument('--seed',type=int,default=42)
    parser.add_argument('--width',type=int,default=1600)
    parser.add_argument('--height',type=int,default=900)
    parser.add_argument('--views',type=int,choices=[1,2],default=1)
    parser.add_argument('--effects',choices=['optimized','source','surrogate','none'],default='optimized')
    parser.add_argument('--require-idle',action='store_true',help='Refuse a timing run if another Godot process is active')
    parser.add_argument('--output',type=Path)
    args=parser.parse_args()
    try: tiers=[int(t) for t in args.tiers.split(',')]
    except ValueError: parser.error('tiers must be comma-separated integers')
    if not tiers or any(t not in dict(PROFILES) for t in tiers): parser.error('tiers must be chosen from 16,32,64,128')
    if not (1<=args.duration<=600 and 0<=args.warmup<=60 and 256<=args.width<=8192 and 256<=args.height<=8192): parser.error('Invalid duration, warmup or resolution')
    context={'utc':datetime.now(timezone.utc).isoformat(),'platform':platform.platform(),'cpu':platform.processor(),'logical_cpus':os.cpu_count(),'concurrent_godot':workloads()}
    if args.require_idle and context['concurrent_godot']:
        parser.error('Other Godot workloads are active. Close them normally before an isolated timing run.')
    directory=(args.output or ROOT/'runtime/benchmarks'/datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')).resolve()
    directory.mkdir(parents=True,exist_ok=True)
    version=subprocess.run([os.environ.get('GODOT','godot'),'--version'],capture_output=True,text=True).stdout.strip()
    context['godot']=version
    (directory/'host.json').write_text(json.dumps(context,indent=2)+'\n')
    results=[]
    duration=2 if args.quick else args.duration
    warmup=.5 if args.quick else args.warmup
    contention_stop=False
    for mode in ['simulation','collision','render']:
        if contention_stop: break
        if args.mode not in [mode,'all']: continue
        for players in (tiers if mode!='collision' else [16]):
            npcs=dict(PROFILES)[players]
            if args.require_idle and workloads():
                results.append({'mode':mode,'players':players,'npcs':npcs,'correctness_pass':False,'failure':'competing_godot_started_between_profiles','concurrent_godot':workloads()})
                print('Stopping suite: another Godot session started.',flush=True)
                contention_stop=True
                break
            output=directory/f'{mode}-{players}p-{npcs}n.json'
            values={'players':players,'npcs':npcs,'duration':duration,'warmup':warmup,'seed':args.seed,'output':output}
            command=[os.environ.get('GODOT','godot'),'--path',str(ROOT/'client'),'--xr-mode','off','--audio-driver','Dummy','--rendering-method','forward_plus','--rendering-driver','vulkan']
            if mode=='simulation':
                command+=['--headless','--script','res://benchmarks/action_simulation.gd']
            elif mode=='collision':
                command+=['--headless','--script','res://tests/combat_collision_smoke.gd']
            else:
                if os.environ.get('WAYLAND_DISPLAY'):command+=['--display-driver','wayland']
                command+=['--script','res://benchmarks/render_viability.gd']
                values.update({'width':args.width,'height':args.height,'views':args.views,'effects':args.effects,'capture':directory/f'render-{players}p.png'})
            command+=['--']+[f'--{k}={v}' for k,v in values.items()]
            if mode=='collision': command+=['--benchmark']
            print(f'Running {mode}: {players} players + {npcs} NPCs',flush=True)
            started=time.monotonic()
            if output.exists():output.unlink() # Never accept stale evidence after a failed invocation.
            failure=''
            try:
                run=subprocess.run(command,cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=600,env=client_environment())
                log=run.stdout;exit_code=run.returncode
            except subprocess.TimeoutExpired as exc:
                log=exc.stdout or b''
                if isinstance(log,bytes):log=log.decode(errors='replace')
                exit_code=124;failure='benchmark_timeout'
            output.with_suffix('.log').write_text(log)
            try: report=json.loads(output.read_text())
            except (OSError,ValueError):report={};failure=failure or 'missing_or_invalid_report'
            if 'SCRIPT ERROR:' in log:failure=failure or 'script_error'
            result={'mode':mode,'players':players,'npcs':npcs,'report':str(output),'exit_code':exit_code,'wall_seconds':time.monotonic()-started,'failure':failure,'correctness_pass':exit_code==0 and not failure and report.get('passed',False),'timing_target_pass':report.get('timing_target_pass'),'render_targets':[s.get('target',{}) for s in report.get('scenarios',[])]}
            results.append(result)
            print(json.dumps(result),flush=True)
    summary={'suite':'SWGXR viability targets','passed':bool(results) and all(r['correctness_pass'] for r in results),'quick':args.quick,'renderer':'forward_plus','driver':'vulkan','views':args.views,'resolution_per_view':[args.width,args.height],'effects':args.effects,'host':context,'results':results,
             'qualification':{'no_other_godot_at_start':not context['concurrent_godot'],'cpu_isolation_enforced':False,'performance_duration_eligible':not args.quick and args.duration>=10,'live_headset_tested':False,'real_network_tested':False,'core3_load_tested':False,'supported_player_count_established':False}}
    (directory/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
    print('Summary: '+str(directory/'summary.json'),flush=True)
    return 0 if summary['passed'] else 1

if __name__=='__main__':sys.exit(main())
