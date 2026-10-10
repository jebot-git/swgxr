"""Bounded presentation poses anchored to native Core3 sessions and world visibility.

This cache owns no gameplay, inventory, damage or payment authority. Native
transactions publish its world snapshots; high-rate tracking never enters the
serialized native command lane. Disconnect removes its ephemeral session state.
"""
from copy import deepcopy
from collections import deque
import math
import threading
import time


try:
    from .capacity import VISIBLE_PLAYERS
except ImportError:
    from capacity import VISIBLE_PLAYERS

class MultiplayerSync:
    MAX_VISIBLE_PLAYERS = VISIBLE_PLAYERS
    NATIVE_TTL = 15.0
    POSE_TTL = 0.75
    MIN_INTERVAL = 0.04

    def __init__(self, clock=time.monotonic):
        self.clock = clock
        self.lock = threading.RLock()
        self.sessions = {}
        self.events = deque(maxlen=256)
        self.event_sequence = 0

    @staticmethod
    def point(value):
        if not isinstance(value, list) or len(value) != 3 or any(type(v) not in (int, float) or not math.isfinite(v) or abs(v) > 20000 for v in value):
            raise ValueError('Finite bounded source position required')
        return list(value)

    @staticmethod
    def cell(value):
        building, index = value.get('building_id', '0'), value.get('cell_index', 0)
        if not isinstance(building, str) or not building.isdigit() or len(building) > 20 or type(index) is not int or not 0 <= index <= 256:
            raise ValueError('Original native building and cell required')
        return building if index else '0', index

    def remove(self, account):
        with self.lock:
            self.sessions.pop(account.lower(), None)

    @classmethod
    def speech_snapshot(cls, value):
        """Copy only the native recipient's normalized, bounded speech envelope."""
        if value is None:
            return {'sequence': 0, 'events': [], 'languages': []}
        if not isinstance(value, dict) or type(value.get('sequence')) is not int or not 0 <= value['sequence'] <= 2**53:
            raise ValueError('Invalid native NPC speech sequence')
        events, languages = value.get('events'), value.get('languages')
        if not isinstance(events, list) or len(events) > 32 or not isinstance(languages, list) or len(languages) > 11:
            raise ValueError('Native NPC speech exceeds presentation bounds')
        for event in events:
            if not isinstance(event, dict) or not isinstance(event.get('id'), str) or not 0 < len(event['id']) <= 96:
                raise ValueError('Stable native speech identity required')
            if type(event.get('age_ms')) is not int or not 0 <= event['age_ms'] <= 60000 or type(event.get('lifetime_ms')) is not int or not 0 < event['lifetime_ms'] <= 10000:
                raise ValueError('Bounded native speech lifetime required')
            cls.point(event.get('position'))
            cls.cell(event)
            if not isinstance(event.get('text'), str) or len(event['text']) > 2048:
                raise ValueError('Bounded native speech text required')
        return deepcopy(value)

    def _speech(self, current, now):
        """Cached presentation ages without new native requests or progress grants."""
        speech = deepcopy(current['npc_speech'])
        elapsed_ms = max(0, round((now - current['speech_at']) * 1000))
        active = []
        for event in speech['events']:
            event['age_ms'] += elapsed_ms
            if event['age_ms'] >= event['lifetime_ms']:
                continue
            if event.get('zone') != current['zone'] or self.cell(event) != current['cell']:
                continue
            active.append(event)
        speech['events'] = active
        return speech

    def publish(self, account, character_id, session_id, snapshot, sequence, command=None, mutation=None):
        if not isinstance(snapshot, dict) or not isinstance(snapshot.get('player'), dict):
            return
        world = snapshot.get('world')
        if not isinstance(world, dict) or world.get('source_kind') != 'core3_world':
            return
        if not isinstance(world.get('players'), list) or len(world['players']) > self.MAX_VISIBLE_PLAYERS or not isinstance(world.get('actors'), list) or len(world['actors']) > 96:
            raise ValueError('Native world snapshot exceeds the presentation budget')
        native = snapshot['player']
        position, cell = self.point(native.get('position')), self.cell(native)
        speech = self.speech_snapshot(native.get('npc_speech'))
        with self.lock:
            now = self.clock()
            # A disconnected native session cannot reserve a presentation slot forever.
            for key in list(self.sessions):
                if now - self.sessions[key]['native_at'] > self.NATIVE_TTL:
                    del self.sessions[key]
            current = self.sessions.get(account.lower())
            if current and current['session_id'] == session_id and int(sequence) <= current['revision']:
                return
            if not current or current['session_id'] != session_id:
                current = {'character_id': str(character_id), 'session_id': session_id,
                           'pose_sequence': -1, 'pose_at': -math.inf, 'pose': None, 'shots': {}}
                self.sessions[account.lower()] = current
            if current.get('cell', cell) != cell or current.get('zone',native.get('zone','tatooine')) != native.get('zone','tatooine'):
                current['pose'] = None
                current['shots'] = {}
                current['pose_at'] = -math.inf
            current.update(native_at=now, position=position, cell=cell,
                           zone=native.get('zone', 'tatooine'), revision=int(sequence),
                           npc_speech=speech, speech_at=now,
                           world=deepcopy(world))
            self._action(current, command or {}, mutation or {}, now)

    def _action(self, current, command, mutation, now):
        action = command.get('action')
        operation = mutation.get('mutation', mutation)
        if not isinstance(operation, dict) or operation.get('success') is not True or operation.get('replayed'):
            return
        if action in ('fire', 'impact', 'life'):
            kind = action
        elif action == 'gathering':
            kind = command.get('gathering', {}).get('action')
            if kind not in ('survey', 'deploy', 'collect'):
                return
        elif action in ('medic', 'scout', 'vehicles', 'crafting'):
            detail = command.get(action, {})
            name = detail.get('action', '')
            if name in ('status', 'open', 'select', ''):
                return
            kind = action + '_' + name
        else:
            return
        self.event_sequence += 1
        event = {'id': self.event_sequence, 'actor_id': current['character_id'],
                 'kind': kind, 'position': list(current['position'])}
        if action == 'fire':
            for field in ('origin', 'direction'):
                event[field] = self.point(command[field])
            weapon_id, shot_id = command.get('item_id'), command.get('shot_id')
            if isinstance(weapon_id, str) and weapon_id.isdigit() and len(weapon_id) <= 20:
                event['weapon_id'] = weapon_id
                if isinstance(shot_id, str) and 0 < len(shot_id) <= 128:
                    current['shots'][shot_id] = (weapon_id, now)
                    while len(current['shots']) > 256:
                        del current['shots'][next(iter(current['shots']))]
        if action == 'impact' and isinstance(command.get('target_id'), str):
            event['target_id'] = command['target_id']
            event['position'] = self.point(command.get('hit_position'))
            shot = current['shots'].get(command.get('shot_id'))
            if shot and now - shot[1] <= 30:
                event['weapon_id'] = shot[0]
        self.events.append({'at': now, 'zone': current['zone'], 'cell': current['cell'], 'event': event})

    def sync(self, account, data, motion=None):
        with self.lock:
            now = self.clock()
            current = self.sessions.get(account.lower())
            if not current or now-current['native_at'] > self.NATIVE_TTL or str(data.get('character_id', '')) != current['character_id'] or data.get('session_id') != current['session_id']:
                raise ValueError('A fresh owned native session is required for multiplayer sync')
            if any(data[key] != current['zone'] for key in ('zone','planet') if key in data):
                raise ValueError('Native source zone mismatch')
            sequence = data.get('sequence')
            if type(sequence) is not int or not current['pose_sequence'] < sequence <= 2**53:
                raise ValueError('Fresh presentation sequence required')
            cursor = data.get('event_sequence', -1)
            if type(cursor) is not int or not -1 <= cursor <= 2**53:
                raise ValueError('Valid public action cursor required')
            if now-current['pose_at'] < self.MIN_INTERVAL:
                raise ValueError('Presentation update rate exceeded')
            position, cell = self.point(data.get('position')), self.cell(data)
            if cell != current['cell'] or math.dist(position, current['position']) > 32:
                current['pose'] = None
                raise ValueError('Refresh the native position/cell before sharing tracking')
            heading = data.get('heading_radians', 0)
            if type(heading) not in (int, float) or not math.isfinite(heading):
                raise ValueError('Finite presentation heading required')
            physical_posture = data.get('physical_posture', 0)
            if type(physical_posture) is not int or not 0 <= physical_posture <= 2:
                raise ValueError('Bounded presentation posture required')
            raw = data.get('tracking', {})
            if not isinstance(raw, dict) or set(raw)-{'head', 'left_hand', 'right_hand'}:
                raise ValueError('Only head and hand presentation tracking is accepted')
            tracking = {}
            for name in ('head', 'left_hand', 'right_hand'):
                value = raw.get(name, {'tracked': False})
                if not isinstance(value, dict) or type(value.get('tracked')) is not bool:
                    raise ValueError('Explicit tracking validity required')
                if not value['tracked']:
                    tracking[name] = {'tracked': False}
                    continue
                point = self.point(value.get('position'))
                rotation = value.get('rotation')
                if math.dist(point, position) > 3 or not isinstance(rotation, list) or len(rotation) != 4 or any(type(v) not in (int, float) or not math.isfinite(v) for v in rotation):
                    raise ValueError('Tracked transform is outside the body presentation bounds')
                norm = math.sqrt(sum(v*v for v in rotation))
                if not .9 <= norm <= 1.1:
                    raise ValueError('Normalized tracked orientation required')
                tracking[name] = {'tracked': True, 'position': point, 'rotation': [v/norm for v in rotation]}
            current.update(pose_sequence=sequence, pose_at=now,
                           pose={'id': current['character_id'], 'sequence': sequence, 'position': position,
                                 'heading_radians': heading, 'building_id': cell[0], 'cell_index': cell[1],
                                 'tracking': tracking, 'physical_posture': physical_posture})
            visible = {str(row.get('id', '')): row for row in current['world']['players']}
            poses = []
            for peer in self.sessions.values():
                row = visible.get(peer['character_id'])
                if peer is current or row is None or not peer['pose'] or now-peer['pose_at'] > self.POSE_TTL or now-peer['native_at'] > self.NATIVE_TTL:
                    continue
                if peer['zone'] != current['zone'] or self.cell(row) != peer['cell']:
                    continue
                pose = deepcopy(peer['pose'])
                pose['age_ms'] = round((now-peer['pose_at'])*1000)
                poses.append(pose)
            visible_ids = set(visible) | {current['character_id']}
            events = [deepcopy(row['event']) for row in self.events
                      if row['event']['id'] > cursor and now-row['at'] <= 5
                      and row['event']['actor_id'] in visible_ids
                      and row['zone'] == current['zone'] and row['cell'] == current['cell']]
            try:
                from .native_motion import project
            except ImportError:
                from native_motion import project
            goals = project(motion, current['world'], current['character_id']) if motion else {}
            return {'motion': goals, 'ok': True, 'backend': 'core3', 'source_kind': 'core3_multiplayer_sync',
                    'character_id': current['character_id'], 'session_id': current['session_id'],
                    'sequence': sequence, 'zone': current['zone'], 'world_revision': current['revision'],
                    'world': deepcopy(current['world']) if data.get('world_revision', -1) != current['revision'] else None,
                    'world_age_ms': max(0, round((now-current['native_at'])*1000)),
                    'events': events[-64:], 'event_sequence': self.event_sequence,
                    'npc_speech': self._speech(current, now),
                    'poses': poses, 'pose_ttl_ms': round(self.POSE_TTL*1000)}


HUB = MultiplayerSync()
