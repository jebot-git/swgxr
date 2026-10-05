#!/usr/bin/env python3
"""Combine controlled XR engine and passive runtime measurements without conflating them."""
import argparse
import json
import math
from pathlib import Path

from capture_live_vr import statistics


def angular_distance(a, b):
    norm = math.sqrt(sum(v*v for v in a)*sum(v*v for v in b))
    return math.degrees(2*math.acos(min(1, abs(sum(x*y for x,y in zip(a,b)))/norm))) if norm else None


def summarize(root):
    engine = json.loads((root/'report.json').read_text())
    external = json.loads((root/'external-summary.json').read_text())
    phases = {}
    for name, phase in engine['phases'].items():
        samples = [s for s in engine['samples'] if s['measuring'] and s['phase']==name]
        reference = samples[0] if samples else None
        phases[name] = {
            'runtime': external['phases'].get(name, {}),
            'raw_callback_intervals': phase['summary'],
            'unfocused_frames': phase['unfocused_frames'],
            'monitor_samples': len(samples),
            'head_translation_from_first_phase_sample_m': statistics([
                math.dist(reference['head_position'], s['head_position']) for s in samples]),
            'head_rotation_from_first_phase_sample_degrees': statistics([
                angular_distance(reference['head_quaternion'], s['head_quaternion']) for s in samples]),
            'viewports': {view: {key: statistics([s['viewports'][view][key] for s in samples])
                                for key in ['cpu_ms','gpu_ms']}
                          for view in ['headset','spectator','root']},
            'draw_calls': statistics([s['draw_calls'] for s in samples]),
            'physics_ms': statistics([1000*s['physics_seconds'] for s in samples]),
            'frame_setup_cpu_ms': statistics([s['render_frame_setup_cpu_ms'] for s in samples]),
            'npc_body_players': statistics([s.get('npcs',{}).get('active_body_players') for s in samples]),
            'portal_views': statistics([s.get('portal_culling',{}).get('view_count') for s in samples]),
            'portal_hidden_instances': statistics([s.get('portal_culling',{}).get('hidden_instances') for s in samples]),
            'portal_fail_open_reasons': sorted({s.get('portal_culling',{}).get('view_tracking',{}).get('fail_open_reason','') for s in samples}),
        }
    return {'source_directory':str(root), 'engine_error':engine['error'], 'restored':engine['restored'],
            'external_capture_passed':external['passed'], 'phases':phases,
            'limits':['One ordered run, not randomized repeated trials or MMO capacity qualification.',
                      'Per-phase pose drift uses one-second snapshots; original report also retains per-frame drift from warmup origin.',
                      'Viewport GPU/CPU values are asynchronous samples, not whole-frame elapsed time.',
                      'Runtime completed FPS is application delivery; raw callback percentiles are not headset presentation percentiles.']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    args = parser.parse_args()
    root = args.directory.resolve()
    result = summarize(root)
    (root/'combined-summary.json').write_text(json.dumps(result,indent=2)+'\n')
    print('phase | completed FPS | callback p95 ms | headset GPU ms | main CPU % of core')
    for name, phase in result['phases'].items():
        runtime = phase['runtime']
        print(name, runtime.get('completed_fps'), phase['raw_callback_intervals'].get('p95_ms'),
              phase['viewports']['headset']['gpu_ms'].get('mean'),
              runtime.get('main_thread_percent_one_core',{}).get('mean'), sep=' | ')
    return 0 if result['external_capture_passed'] and result['restored'] and not result['engine_error'] else 1


if __name__=='__main__':
    raise SystemExit(main())
