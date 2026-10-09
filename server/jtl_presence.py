"""Short-lived POB tracking, anchored exclusively to successful native snapshots.

This cache cannot board a player, move a ship, select a cell, or alter appearance.
The native recipient roster decides which authenticated poses may be presented.
"""
from copy import deepcopy
import math
import threading
import time

try:
    from .multiplayer_sync import MultiplayerSync
except ImportError:
    from multiplayer_sync import MultiplayerSync


class JtlPresence:
    POSE_TTL = 0.75
    MAX_CREW = 20
    MAX_SESSIONS = 512
    BODY_TOLERANCE = 3.0

    def __init__(self, clock=time.monotonic):
        self.clock = clock
        self.lock = threading.RLock()
        self.sessions = {}

    @staticmethod
    def _id(value):
        if not isinstance(value, str) or not value.isascii() or not value.isdigit() or not 0 < int(value) < 2**64:
            raise ValueError('Native crew identity required.')
        return value

    @staticmethod
    def _cell(value):
        if type(value) is not int or not 0 <= value <= 256:
            raise ValueError('Native ship cell required.')
        return value

    @staticmethod
    def _point(value):
        point = MultiplayerSync.point(value)
        if any(abs(x) > 64 for x in point):
            raise ValueError('Bounded ship-local presentation required.')
        return point

    @classmethod
    def _pose(cls, data, current):
        if not isinstance(data, dict) or set(data) - {'sequence', 'position', 'heading_radians', 'cell_index', 'tracking', 'physical_posture'}:
            raise ValueError('Only ship-local presentation fields are accepted.')
        sequence = data.get('sequence')
        if type(sequence) is not int or not current['sequence'] < sequence <= 2**53 - 1:
            raise ValueError('Fresh crew presentation sequence required.')
        position, cell = cls._point(data.get('position')), cls._cell(data.get('cell_index'))
        if cell != current['cell'] or math.dist(position, current['position']) > cls.BODY_TOLERANCE:
            raise ValueError('Refresh native ship position before sharing tracking.')
        heading, posture = data.get('heading_radians', 0), data.get('physical_posture', 0)
        if type(heading) not in (int, float) or not math.isfinite(heading):
            raise ValueError('Finite crew presentation heading required.')
        if type(posture) is not int or not 0 <= posture <= 2:
            raise ValueError('Bounded crew posture required.')
        raw = data.get('tracking', {})
        if not isinstance(raw, dict) or set(raw) - {'head', 'left_hand', 'right_hand'}:
            raise ValueError('Only head and hand tracking is accepted.')
        tracking = {}
        for name in ('head', 'left_hand', 'right_hand'):
            value = raw.get(name, {'tracked': False})
            if not isinstance(value, dict) or type(value.get('tracked')) is not bool:
                raise ValueError('Explicit crew tracking validity required.')
            if not value['tracked']:
                tracking[name] = {'tracked': False}
                continue
            point, rotation = cls._point(value.get('position')), value.get('rotation')
            if math.dist(point, position) > 3 or not isinstance(rotation, list) or len(rotation) != 4 or any(type(v) not in (int, float) or not math.isfinite(v) for v in rotation):
                raise ValueError('Tracked transform exceeds physical reach.')
            norm = math.sqrt(sum(v*v for v in rotation))
            if not .9 <= norm <= 1.1:
                raise ValueError('Normalized crew tracking rotation required.')
            tracking[name] = {'tracked': True, 'position': point, 'rotation': [v/norm for v in rotation]}
        return {'id': current['character_id'], 'sequence': sequence, 'position': position,
                'heading_radians': heading, 'cell_index': cell, 'building_id': current['ship_id'],
                'ship_id': current['ship_id'], 'tracking': tracking, 'physical_posture': posture}

    def remove(self, account):
        with self.lock:
            self.sessions.pop(account.lower(), None)

    def invalidate(self, account):
        """Drop rejected tracking without allowing a stale sequence to replay."""
        with self.lock:
            current = self.sessions.get(account.lower())
            if current:
                current['pose'] = None

    def exchange(self, account, character_id, session_id, native_jtl, presentation=None):
        """Call only after native authentication and snapshot validation, never HTTP data."""
        result = {'crew_poses': [], 'crew_pose_ttl_ms': round(self.POSE_TTL * 1000)}
        key = account.lower()
        with self.lock:
            now = self.clock()
            for old in list(self.sessions):
                if now - self.sessions[old]['native_at'] > self.POSE_TTL:
                    # Keep a sequence floor for the active session, but discard its pose.
                    self.sessions[old]['pose'] = None
                if now - self.sessions[old]['native_at'] > 120:
                    del self.sessions[old]
            if not isinstance(native_jtl, dict):
                self.invalidate(account)
                raise ValueError('Native JtL presentation state required.')
            if native_jtl.get('space_active') is not True:
                self.sessions.pop(key, None)
                return result
            # A malformed native refresh must never keep publishing an old pose.
            # Reinstall the old pose only after every anchor/roster check succeeds.
            old_current = self.sessions.get(key)
            old_pose = old_current.get('pose') if old_current else None
            self.invalidate(account)
            ship = native_jtl.get('ship')
            if not isinstance(ship, dict):
                raise ValueError('Native active ship required.')
            ship_id, oid = self._id(ship.get('id')), self._id(str(character_id))
            position, cell = self._point(ship.get('player_position')), self._cell(ship.get('cell_index'))
            crew = ship.get('crew', [])
            if not isinstance(crew, list) or len(crew) > self.MAX_CREW:
                raise ValueError('Native crew exceeds presentation bounds.')
            visible = {}
            for row in crew:
                if not isinstance(row, dict):
                    raise ValueError('Native crew roster required.')
                peer_id = self._id(row.get('id'))
                if peer_id in visible:
                    raise ValueError('Unique native crew identities required.')
                visible[peer_id] = {'cell': self._cell(row.get('cell_index')),
                                    'position': self._point(row.get('position')),
                                    'appearance': deepcopy(row.get('appearance', {}))}
            current = self.sessions.get(key)
            if not current or (current['character_id'], current['session_id'], current['ship_id']) != (oid, session_id, ship_id):
                if current is None and len(self.sessions) >= self.MAX_SESSIONS:
                    raise ValueError('Crew presentation capacity reached.')
                current = {'character_id': oid, 'session_id': session_id, 'ship_id': ship_id,
                           'sequence': -1, 'pose': None, 'pose_at': -math.inf}
                self.sessions[key] = current
            if current.get('cell', cell) != cell:
                current['pose'] = None
            elif current is old_current:
                current['pose'] = old_pose
            current.update(position=position, cell=cell, native_at=now)
            if presentation is not None:
                try:
                    pose = self._pose(presentation, current)
                except ValueError:
                    current['pose'] = None
                    raise
                current.update(sequence=pose['sequence'], pose=pose, pose_at=now)
            for peer in self.sessions.values():
                row = visible.get(peer['character_id'])
                if peer is current or row is None or not peer['pose'] or peer['ship_id'] != ship_id or peer['cell'] != cell or row['cell'] != cell:
                    continue
                if now - peer['pose_at'] > self.POSE_TTL or now - peer['native_at'] > self.POSE_TTL or math.dist(peer['pose']['position'], row['position']) > self.BODY_TOLERANCE:
                    continue
                pose = deepcopy(peer['pose'])
                pose.update(age_ms=round((now - peer['pose_at']) * 1000), appearance=row['appearance'])
                result['crew_poses'].append(pose)
            return result


HUB = JtlPresence()
