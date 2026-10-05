#!/usr/bin/env python3
"""Independent optimization toggles against a fixed real cantina desktop scene."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import subprocess
import sys
import time

from run_suite import ROOT, workloads, client_environment

VARIANTS = {
    'baseline': ['--no-portal-culling', '--no-hidden-animation', '--no-animation-cache'],
    'portal_only': ['--no-hidden-animation', '--no-animation-cache'],
    'cache_only': ['--no-portal-culling', '--no-hidden-animation'],
    'suspension_only': ['--no-portal-culling', '--no-animation-cache'],
    'combined': [],
}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--variants', default=','.join(VARIANTS))
    parser.add_argument('--duration', type=float, default=15)
    parser.add_argument('--warmup', type=float, default=5)
    parser.add_argument('--repeat', type=int, default=1)
    parser.add_argument('--headless', action='store_true', help='Functional smoke; no GPU/performance qualification')
    args = parser.parse_args()
    names = args.variants.split(',')
    if any(n not in VARIANTS for n in names) or not 1 <= args.repeat <= 5:
        parser.error('Invalid variants or repeat count')
    if not .2 <= args.duration <= 120 or not .1 <= args.warmup <= 30:
        parser.error('Invalid duration or warmup')
    if not args.headless and workloads():
        parser.error('Close other Godot processes before GPU timing comparisons')
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=True)
    results = []
    for repeat in range(args.repeat):
        # Reverse every other round to reduce simple thermal/order bias.
        for name in names if repeat % 2 == 0 else list(reversed(names)):
            if not args.headless and workloads():
                parser.error('Another Godot process appeared between captures')
            path = args.output / f'{repeat}-{name}.json'
            path.unlink(missing_ok=True)
            command = ['godot', '--path', str(ROOT/'client'), '--xr-mode', 'off', '--audio-driver', 'Dummy']
            command += ['--headless', '--max-fps', '120'] if args.headless else ['--display-driver', 'wayland', '--rendering-method', 'forward_plus', '--rendering-driver', 'vulkan']
            command += ['--script', 'res://benchmarks/cantina_optimization.gd', '--', '--offline', '--desktop',
                        '--position=-190.798396,-0.894992,22.327722', '--time-of-day=12',
                        f'--duration={args.duration}', f'--warmup={args.warmup}', f'--output={path}']
            command += VARIANTS[name]
            if not args.headless: command.append('--capture')
            start = time.monotonic()
            print(f'Running {repeat}: {name}', flush=True)
            try:
                run = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=300, env=client_environment())
                log, code = run.stdout+run.stderr, run.returncode
            except subprocess.TimeoutExpired as exc:
                log = str(exc.stdout or '') + str(exc.stderr or '')
                code = 124
            path.with_suffix('.log').write_text(log)
            try: report = json.loads(path.read_text())
            except (OSError, ValueError): report = {}
            passed = code == 0 and report.get('passed', False) and 'SCRIPT ERROR:' not in log
            results.append({'variant':name, 'repeat':repeat, 'passed':passed, 'exit_code':code,
                            'wall_seconds':time.monotonic()-start, 'command':command,
                            'report':str(path), 'views':[{k:v for k,v in view.items() if k!='snapshots'} for view in report.get('views',[])]})
            print(json.dumps(results[-1]), flush=True)
            if not passed: break
        if results and not results[-1]['passed']: break
    summary = {'utc':datetime.now(timezone.utc).isoformat(),'passed':bool(results) and all(r['passed'] for r in results),
               'gpu_tested':not args.headless,'live_headset_tested':False,'results':results,
               'performance_qualification':not args.headless and args.duration>=10,
               'limitations':['Fixed desktop mono scene, not live VR','Other Godot processes excluded; system-wide CPU/GPU isolation not enforced']}
    (args.output/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
    return 0 if summary['passed'] else 1

if __name__ == '__main__':
    sys.exit(main())
