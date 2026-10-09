#!/usr/bin/env python3
"""Controlled, source-derived Core3 FOLLOWING approach experiment.

Not a Core3 process, behavior-tree execution, navmesh or damage simulation.
Preserves the pinned movement arithmetic, including its squared-distance clamp
and displacement budget computed before currentSpeed's acceleration adjustment.
"""
import argparse
import csv
import hashlib
import json
import math
import os
from pathlib import Path
import re
import statistics
import sys

ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / 'vendor/Core3/MMOCoreORB'
sys.path.insert(0, str(ROOT / 'tools/assets'))
from swg_formats import TreSet, parse_iff


def distance(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


class Sources:
    def __init__(self): self.hashes = {}
    def read(self, path):
        path = CORE / path
        raw = path.read_bytes()
        self.hashes[str(path.relative_to(ROOT))] = hashlib.sha256(raw).hexdigest()
        return raw.decode()


def number(text, field):
    match = re.search(r'\b' + re.escape(field) + r'\s*=\s*(-?[\d.]+)', text)
    if not match: raise ValueError('Missing literal source field ' + field)
    return float(match[1])


def inputs(sources):
    ai = sources.read('src/server/zone/objects/creature/ai/AiAgentImplementation.cpp')
    # Explicit drift checks: this experiment must not quietly outlive its source.
    for snippet in ('float maxSpeed = newSpeed * updateTicks;',
                    'Math::min(maxSpeed, endDistanceSq - maxSquared + 0.1f)',
                    'newSpeed = currentSpeed + 0.4f;',
                    'Math::max(0.2f, (currentSpeed - 0.4f))',
                    'squaredDistanceTo(endMovementCoords.getWorldPosition()) > 4 * 4',
                    'Math::min(currentWeap->getIdealRange(), currentWeap->getMaxRange())'):
        if snippet not in ai: raise ValueError('Movement source changed: ' + snippet)
    interval = number(sources.read('src/server/zone/objects/creature/ai/AiAgent.idl'), 'BEHAVIORINTERVALMIN') / 1000
    sources.read('src/server/zone/objects/creature/ai/bt/leaf/Checks.cpp')
    sources.read('src/server/zone/objects/creature/ai/bt/leaf/FollowActions.h')
    sources.read('src/server/zone/objects/creature/ai/bt/leaf/SimpleActions.h')
    sources.read('bin/scripts/ai/default.lua')
    sources.read('src/server/zone/objects/creature/CreatureObjectImplementation.cpp')
    # SMAT/LSAT have no Core3 server-side appearance instance in this revision;
    # getTemplateRadius therefore returns zero, not collisionRadius=0.5.
    manager = sources.read('src/templates/manager/TemplateManager.cpp')
    scene = sources.read('src/server/zone/objects/scene/SceneObjectImplementation.cpp')
    assert re.search(r"case 'LSAT':\s*break;", manager)
    assert re.search(r"case 'SMAT':\s*break;", manager)
    assert 'templateObject->getAppearanceTemplate() == nullptr' in scene
    objects = sources.read('bin/scripts/object/mobile/objects.lua')
    tre = TreSet(ROOT / 'runtime/asset_sources/active_tre')
    profiles = []
    for mobile, template, weapon in [
        ('kreetle', 'kreetle', 'creature/creature_default_weapon'),
        ('desert_demon_marksman', 'dressed_tatooine_desert_demon_marksman', 'ranged/rifle/rifle_cdef')]:
        source_mobile = sources.read('bin/scripts/mobile/tatooine/' + mobile + '.lua')
        declaration = 'object_mobile_shared_' + template
        block = objects.split(declaration + ' =', 1)[1].split('ObjectTemplates:addClientTemplate', 1)[0]
        speed = re.search(r'\bspeed\s*=\s*\{\s*([\d.]+),\s*([\d.]+)\}', block)
        if not speed: raise ValueError('No source movement speeds')
        appearance = re.search(r'appearanceFilename\s*=\s*"([^"]+)"', block)[1]
        raw = tre.read(appearance)
        assert parse_iff(raw).tag in ('SMAT', 'LSAT')
        sources.hashes['tre:' + appearance] = hashlib.sha256(raw).hexdigest()
        weapon_data = sources.read('bin/scripts/object/weapon/' + weapon + '.lua')
        if mobile == 'desert_demon_marksman':
            group = sources.read('bin/scripts/mobile/weapon/groups/ranged_weapons.lua')
            assert 'object/weapon/' + weapon + '.iff' in group
            assert 'primaryWeapon = "ranged_weapons"' in source_mobile
        profiles.append({'mobile': mobile, 'weapon': weapon, 'run_speed_mps': float(speed[1]),
                         'walk_speed_mps': float(speed[2]), 'ideal_range_m': number(weapon_data, 'idealRange'),
                         'max_range_m': number(weapon_data, 'maxRange'), 'template_radius_m': 0.0,
                         'behavior_interval_s': interval})
    return profiles


class Approach:
    def __init__(self, profile, initial_distance):
        self.profile = profile
        self.position = (-initial_distance, 0.0)
        self.path_end = None
        self.current_speed = 0.0
        self.travelled = 0.0
        self.move_count = 0
        self.stop_count = 0
        self.arrival = max(2.0, min(profile['ideal_range_m'], profile['max_range_m']))

    def tick(self, target):
        p = self.profile
        interval = p['behavior_interval_s']
        # activateAiBehavior resets the next movement budget to MIN after
        # scheduling the previously calculated delay. Preserve that ordering.
        speed = p['run_speed_mps']
        budget = speed * interval
        separation = distance(self.position, target)
        squared = separation * separation
        threshold_squared = max(0.1, self.arrival * self.arrival)
        if squared <= threshold_squared:
            if self.current_speed > 0: self.stop_count += 1
            self.current_speed = 0.0
            self.path_end = None
            return interval
        if self.current_speed ** 2 * threshold_squared > squared and speed > 0.4:
            speed = max(0.2, self.current_speed - 0.4)
        elif self.current_speed < speed and speed - self.current_speed > 0.4:
            speed = self.current_speed + 0.4
        self.current_speed = speed
        if self.path_end is None or distance(self.path_end, target) > 4.0:
            self.path_end = target
        path_distance = distance(self.position, self.path_end)
        if path_distance < 1e-8:
            self.path_end = None
            return interval
        # Deliberately reproduce upstream; do not replace by separation-arrival.
        travel = min(path_distance, budget, squared - threshold_squared + 0.1)
        self.position = tuple(a + (b - a) * travel / path_distance for a, b in zip(self.position, self.path_end))
        self.travelled += travel; self.move_count += 1
        delay_ms = min(math.floor(travel / speed * 1000 + 0.5), round(interval * 1000))
        return max(10, delay_ms) / 1000


def simulate(profile, motion, player_speed, initial_distance, duration):
    agent = Approach(profile, initial_distance)
    velocity = {'standing': (0.0, 0.0), 'retreating': (player_speed, 0.0),
                'strafing': (0.0, player_speed)}[motion]
    next_tick = profile['behavior_interval_s']
    trace = []; arrival_time = None; range_time = None; arrival_travel = None
    # Uniform observation rate is separate from the event-driven AI cadence.
    for sample in range(round(duration * 100) + 1):
        now = sample / 100
        while next_tick <= now + 1e-8:
            target = tuple(v * next_tick for v in velocity)
            event_time = next_tick
            next_tick += agent.tick(target)
            if arrival_time is None and distance(agent.position, target) <= agent.arrival + 1e-8:
                arrival_time = event_time; arrival_travel = agent.travelled
        player = tuple(v * now for v in velocity)
        separation = distance(agent.position, player)
        eligible = separation <= profile['max_range_m'] + 1e-8
        if range_time is None and eligible: range_time = now
        trace.append({'time_s': now, 'player_x': player[0], 'player_y': player[1],
                      'mob_x': agent.position[0], 'mob_y': agent.position[1],
                      'distance_m': separation, 'reported_current_speed_mps': agent.current_speed,
                      'attack_range_eligible': int(eligible)})
    steady = [row for row in trace if row['time_s'] >= duration - 10]
    distances = [row['distance_m'] for row in steady]
    metrics = {'mobile': profile['mobile'], 'motion': motion, 'player_speed_mps': math.hypot(*velocity),
               'source_run_speed_mps': profile['run_speed_mps'], 'desired_distance_m': agent.arrival,
               'first_attack_range_s': range_time, 'first_arrival_radius_s': arrival_time,
               'mean_approach_speed_mps': arrival_travel / arrival_time if arrival_time else None,
               'steady_min_m': min(distances), 'steady_mean_m': statistics.mean(distances),
               'steady_max_m': max(distances), 'steady_attack_range_fraction': statistics.mean(row['attack_range_eligible'] for row in steady),
               'moves': agent.move_count, 'stops': agent.stop_count}
    return metrics, trace


def self_test(profiles):
    for profile in profiles:
        a = Approach(profile, 40)
        a.tick((0, 0))
        # Independent source-expression invariants expose the acceleration bug.
        assert math.isclose(a.travelled, profile['run_speed_mps'] * profile['behavior_interval_s'])
        assert math.isclose(a.current_speed, 0.4)
        a.position = (-a.arrival, 0)
        previous = a.position
        a.tick((0, 0))
        assert a.position == previous and a.current_speed == 0
        metrics, _ = simulate(profile, 'standing', 1, 40, 20)
        assert metrics['first_arrival_radius_s'] is not None
        assert metrics['steady_max_m'] <= a.arrival + 1e-6


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--player-speed', type=float, default=1.0)
    parser.add_argument('--initial-distance', type=float, default=40.0)
    parser.add_argument('--duration', type=float, default=60.0)
    parser.add_argument('--out', type=Path, default=ROOT / 'runtime/evidence/ai-approach')
    args = parser.parse_args()
    if not all(math.isfinite(v) for v in (args.player_speed, args.initial_distance, args.duration)) or not (0 <= args.player_speed <= 10 and 1 <= args.initial_distance <= 120 and 20 <= args.duration <= 300):
        parser.error('Use finite speed 0–10 m/s, distance 1–120 m and duration 20–300 s.')
    sources = Sources(); profiles = inputs(sources); self_test(profiles)
    args.out.mkdir(parents=True, exist_ok=True)
    results = []; traces = {}
    for profile in profiles:
        for motion in ('standing', 'retreating', 'strafing'):
            metrics, trace = simulate(profile, motion, args.player_speed, args.initial_distance, args.duration)
            key = profile['mobile'] + '-' + motion; traces[key] = trace; results.append(metrics)
            with (args.out / (key + '.csv')).open('w') as stream:
                writer = csv.DictWriter(stream, fieldnames=list(trace[0])); writer.writeheader(); writer.writerows(trace)
    report = {'kind': 'controlled_source_derived_simulation', 'live_core3': False,
              'inputs': {'initial_distance_m': args.initial_distance, 'duration_s': args.duration,
                         'slow_player_speed_mps': args.player_speed},
              'profiles': profiles, 'results': results, 'source_hashes': sources.hashes,
              'assumptions': ['Already aggroed and FOLLOWING with line of sight; open, level exterior ground.',
                              'Full-health upright mobs; no random evade, posture, flee, weapon switching or damage.',
                              'Marksman uses the CDEF rifle variant of its original ranged_weapons group.',
                              'Direct two-point paths with original >4 m target repath threshold.',
                              'Reported attack range is eligibility only, not queue execution or landed hits.',
                              'No navmesh, collision, task-scheduling latency, packet transport or HMD rendering validation.'],
              'source_quirks_preserved': ['Displacement budget uses runSpeed before currentSpeed acceleration.',
                                         'Arrival clamp subtracts squared distances, allowing a full step inside ideal range.']}
    (args.out / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    os.environ.setdefault('MPLCONFIGDIR', str(args.out / 'matplotlib-cache'))
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    fig, axes = plt.subplots(2, 2, figsize=(12, 7), layout='constrained')
    for row, profile in enumerate(profiles):
        for motion in ('standing', 'retreating', 'strafing'):
            trace = traces[profile['mobile'] + '-' + motion]
            for col in (0, 1):
                axes[row, col].plot([r['time_s'] for r in trace], [r['distance_m'] for r in trace], label=motion, lw=1.4)
        for col in (0, 1):
            ax = axes[row, col]
            ax.axhline(profile['ideal_range_m'], color='#555555', ls='--', lw=1, label='source ideal range')
            ax.set(xlabel='Time (s)', ylabel='Distance to player (m)', title=profile['mobile'].replace('_', ' '))
            ax.grid(alpha=.2)
        axes[row, 0].set_xlim(0, 12)
        axes[row, 1].set_xlim(args.duration - 10, args.duration)
        axes[row, 1].set_ylim(profile['ideal_range_m'] - 4, profile['ideal_range_m'] + 1)
    axes[0, 0].legend(fontsize=8)
    fig.suptitle('Core3 approach rules — controlled source simulation, not live server\n'
                 f'{args.initial_distance:g} m start; standing / retreat / strafe at {args.player_speed:g} m/s; upright, no evasion', fontsize=12)
    fig.savefig(args.out / 'approach.png', dpi=150); plt.close(fig)
    print(json.dumps(results, indent=2))


if __name__ == '__main__': main()
