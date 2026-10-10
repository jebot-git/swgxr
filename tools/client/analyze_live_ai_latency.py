#!/usr/bin/env python3
"""Summarize opt-in live Godot traces and replay the previous NPC renderer.

Replay uses the identical received goals and observed frame times. It is a
counterfactual presentation comparison, not a second live-server benchmark.
"""
import argparse
from collections import defaultdict
import json
import math
from pathlib import Path
import statistics


def distribution(values):
    values = sorted(values)
    if not values:
        return {'count': 0}
    return {'count': len(values), 'p50': statistics.median(values),
            'p95': values[int((len(values)-1)*.95)], 'max': values[-1]}


def analyze(path):
    trace = json.loads(path.read_text())
    frames = trace['frames']
    start, end = frames[0]['at'], frames[-1]['at']
    routes = defaultdict(list)
    failures = []
    for row in trace['requests']:
        if start <= row['at'] <= end:
            routes[row['path']].append(row['elapsed_ms'])
            if not row['ok'] or row['error']:
                failures.append(row)
    state, actors = {}, defaultdict(lambda: defaultdict(list))
    for frame in frames:
        now, dt = frame['at'], frame['delta_ms']/1000
        if dt <= 0:
            continue
        for row in frame['actors']:
            key, goal, actual = row['id'], row['goal'], row['position']
            if key not in state:
                state[key] = dict(goal=goal, actual=actual, legacy=actual,
                                  last_change=now, last_at=now)
                continue
            previous = state[key]
            if now-previous['last_at'] > 1:
                previous.update(goal=goal, actual=actual, legacy=actual,
                                last_change=now, last_at=now)
                continue
            distance = math.dist(previous['goal'], goal)
            if distance > .01:
                actors[key]['source_step_m'].append(distance)
                actors[key]['source_gap_ms'].append((now-previous['last_change'])*1000)
                previous['last_change'] = now
            # The production renderer before this change: 14/s exponential
            # approach, with the >8m snap at packet receipt.
            legacy = previous['legacy']
            if distance > .01 and math.dist(legacy, goal) > 8:
                legacy = goal
            else:
                alpha = 1-math.exp(-14*dt)
                legacy = [a+(b-a)*alpha for a,b in zip(legacy, goal)]
            if now-start > 3:
                for name, point, before in [('current', actual, previous['actual']),
                                            ('previous_replay', legacy, previous['legacy'])]:
                    actors[key][name+'_frame_step_m'].append(math.dist(point, before))
                    actors[key][name+'_speed_mps'].append(math.dist(point, before)/dt)
                    actors[key][name+'_goal_gap_m'].append(math.dist(point, goal))
            previous.update(goal=goal, actual=actual, legacy=legacy, last_at=now)
    moving = {key: values for key, values in actors.items()
              if sum(values['source_step_m']) > 1 and len(values['source_step_m']) > 3}
    combined = defaultdict(list)
    for values in moving.values():
        for key, samples in values.items():
            combined[key].extend(samples)
    queues = [r['queue_ms'] for r in trace.get('native_queue', [])
              if start <= r['time_ms']/1000 <= end]
    motion_seen, motion_age, delivered_age = {}, [], []
    ahead_of_snapshots = 0
    snapshot_index, counters = 0, {}
    snapshots = sorted(trace.get('snapshots', []), key=lambda s: s['at'])
    for envelope in trace.get('motion', []):
        while snapshot_index < len(snapshots) and snapshots[snapshot_index]['at'] <= envelope['at']:
            counters.update({r['id']: r.get('movement_counter', -1) for r in snapshots[snapshot_index]['actors']})
            snapshot_index += 1
        for row in envelope['actors']:
            prior = motion_seen.get(row['id'])
            motion_seen[row['id']] = row['sequence']
            if prior is None or prior == row['sequence'] or not start <= envelope['at'] <= end:
                continue
            motion_age.append(row['age_ms'])
            delivered_age.append(row['age_ms'] + envelope['request_ms'])
            counter = int(counters.get(row['id'], -1))
            if counter >= 0 and 0 < ((int(row['movement_counter']) - counter) & 0xffffffff) < 0x80000000:
                ahead_of_snapshots += 1
    native_motion = {'new_endpoint_updates': len(motion_age),
                     'updates_ahead_of_latest_full_snapshot': ahead_of_snapshots,
                     'first_observed_bridge_age_ms': distribution(motion_age),
                     'conservative_client_age_ms': distribution(delivered_age),
                     'limits': 'Age starts at native bridge receipt. Client estimate adds whole HTTP duration; neither includes server-to-bridge transport. First observation of each actor is excluded.'}
    return {'source': str(path), 'duration_seconds': end-start,
            'frames': len(frames), 'renderer': trace['renderer'],
            'cleanup_completed': trace['cleanup_completed'],
            'harness_errors': trace['errors'], 'request_failures': failures,
            'routes_ms': {key: distribution(values) for key, values in routes.items()},
            'native_queue_ms': distribution(queues),
            'frame_ms': distribution([f['delta_ms'] for f in frames]),
            'max_player_excursion_m': max(math.dist(frames[0]['player'], f['player']) for f in frames),
            'moving_actor_count': len(moving), 'native_motion': native_motion,
            'motion': {key: distribution(samples) for key, samples in combined.items()},
            'actors': {key: {k: distribution(v) for k,v in values.items()} for key,values in moving.items()},
            'comparison_limits': 'Previous renderer replay uses identical received goals and actual frame times. Goal gap is visual distance to latest received target, not end-to-end latency. Frame-derived speeds include SceneTree sampling-phase error; use frame displacement for jump comparisons. No headset/GPU validation.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('traces', nargs='+', type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    reports = [analyze(path) for path in args.traces]
    args.output.write_text(json.dumps(reports, indent=2)+'\n')
    for report in reports:
        print(json.dumps({key: report[key] for key in ['source','frames','moving_actor_count','frame_ms','native_queue_ms','motion']}))


if __name__ == '__main__':
    main()
