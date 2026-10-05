"""Ephemeral tracked-hand presence; Core3 alone owns characters and money.

Registration is called only after an authenticated native services observation.
Tokens do not grant money authority. A mutually gripped hand contact authorizes
one explicit payment request, which must still pass the native TipCommand.
"""
import math
import re
import secrets
import threading
import time
from copy import deepcopy


class PresenceHub:
    MAX_ACTORS = 32
    AUTH_TTL = 120.0
    POSE_TTL = 1.0
    PROOF_TTL = 60.0
    CONTACT_TIME = 0.25

    def __init__(self, clock=time.monotonic):
        self.clock = clock
        self.lock = threading.RLock()
        self.actors = {}
        self.contacts = {}
        self.proofs = {}

    @staticmethod
    def point(value):
        if not isinstance(value, list) or len(value) != 3 or any(
            type(x) not in (int, float) or not math.isfinite(x) or abs(x) > 20000 for x in value
        ):
            raise ValueError('Finite three-dimensional tracked position required.')
        return list(value)

    @staticmethod
    def distance(a, b):
        return math.dist(a, b)

    def _prune(self, now):
        for oid, actor in list(self.actors.items()):
            if now - actor['authenticated'] > self.AUTH_TTL:
                del self.actors[oid]
        for pair, proof in list(self.proofs.items()):
            if now - proof['created'] > self.PROOF_TTL or any(oid not in self.actors for oid in pair):
                del self.proofs[pair]
        for pair in list(self.contacts):
            if any(oid not in self.actors for oid in pair):
                del self.contacts[pair]

    def register(self, account, character_id, native_state):
        """native_state must come from Core3, never directly from HTTP input."""
        oid = str(character_id)
        if not oid.isdigit() or int(oid) <= 0:
            raise ValueError('Owned native character required for hand presence.')
        position = self.point(native_state['position'])
        with self.lock:
            now = self.clock()
            self._prune(now)
            actor = self.actors.get(oid)
            if actor is None:
                if len(self.actors) >= self.MAX_ACTORS:
                    raise ValueError('Local hand-presence capacity reached.')
                actor = {'id': oid, 'account': account.lower(), 'token': secrets.token_urlsafe(32),
                         'seen': -math.inf, 'seq': -1, 'tracked': False, 'grip': False,
                         'wallet_held': False, 'position': position, 'hand': position}
                self.actors[oid] = actor
            if actor['account'] != account.lower():
                raise ValueError('Native presence ownership changed.')
            if 'cell_id' in actor and (actor['cell_id'] != str(native_state.get('cell_id', '0')) or actor['zone'] != str(native_state.get('zone', 'tatooine'))):
                self._invalidate_contacts(oid)
            actor.update(authenticated=now, anchor=position,
                         zone=str(native_state.get('zone', 'tatooine')),
                         cell_id=str(native_state.get('cell_id', '0')),
                         building_id=str(native_state.get('building_id', '0')),
                         cell_index=int(native_state.get('cell_index', 0)),
                         appearance=deepcopy(native_state.get('appearance', {})),
                         name=str(native_state.get('name', oid))[:96])
            return {'token': actor['token'], 'expires_in': self.AUTH_TTL, 'pose_ttl': self.POSE_TTL,
                    'sequence_floor': actor['seq']}

    def _near(self, a, b, radius=3.0):
        return a['zone'] == b['zone'] and a['cell_id'] == b['cell_id'] and self.distance(a['position'], b['position']) <= radius

    def _invalidate_contacts(self, oid):
        actor = self.actors.get(oid)
        if actor:
            actor.update(tracked=False, wallet_held=False, grip=False)
        for mapping in (self.contacts, self.proofs):
            for pair in list(mapping):
                if oid in pair: del mapping[pair]

    def update(self, account, character_id, token, payload):
        oid = str(character_id)
        with self.lock:
            now = self.clock()
            self._prune(now)
            actor = self.actors.get(oid)
            if actor is None or actor['account'] != account.lower() or not isinstance(token, str) or not secrets.compare_digest(actor['token'], token):
                raise ValueError('Hand presence needs a fresh authenticated Core3 observation.')
            if str(payload.get('building_id', actor['building_id'])) != actor['building_id'] or payload.get('cell_index', actor['cell_index']) != actor['cell_index']:
                self._invalidate_contacts(oid)
                raise ValueError('Refresh the native cell before publishing tracked hands.')
            seq = payload.get('sequence')
            if type(seq) is not int or seq <= actor['seq'] or seq > 2**53:
                raise ValueError('Fresh hand-pose sequence required.')
            position = self.point(payload.get('position'))
            hand = payload.get('hand', {})
            if not isinstance(hand, dict) or any(type(hand.get(k)) is not bool for k in ('tracked', 'grip')) or type(payload.get('wallet_held')) is not bool:
                raise ValueError('Tracked hand and wallet flags must be boolean.')
            hand_position = self.point(hand.get('position'))
            side = payload.get('main_hand_side', 'right')
            if side not in ('left', 'right'):
                raise ValueError('Tracked main hand side must be left or right.')
            heading = payload.get('heading_radians', 0)
            if type(heading) not in (int, float) or not math.isfinite(heading):
                raise ValueError('Finite presentation heading required.')
            if self.distance(position, actor['anchor']) > 64 or self.distance(position, hand_position) > 3:
                raise ValueError('Tracked hand is outside the authenticated character area.')
            actor.update(seq=seq, seen=now, position=position, hand=hand_position,
                         tracked=hand['tracked'], grip=hand['grip'], wallet_held=payload['wallet_held'], main_hand_side=side, heading=heading)
            peers = []
            for peer in self.actors.values():
                if peer is actor:
                    continue
                pair = tuple(sorted((oid, peer['id'])))
                fresh = now - peer['seen'] <= self.POSE_TTL and peer['tracked'] and actor['tracked']
                near = self._near(actor, peer)
                touching = fresh and near and actor['grip'] and peer['grip'] and self.distance(actor['hand'], peer['hand']) <= 0.16
                if touching:
                    contact = self.contacts.setdefault(pair, {'start': now, 'issued': False})
                    if not contact['issued'] and now - contact['start'] >= self.CONTACT_TIME:
                        for sender, receiver in ((actor, peer), (peer, actor)):
                            if sender['wallet_held']:
                                self.proofs[(sender['id'], receiver['id'])] = {'created': now, 'request_id': '', 'amount': None}
                        contact['issued'] = True
                else:
                    self.contacts.pop(pair, None)
                if fresh and self._near(actor, peer, 16):
                    proof = self.proofs.get((oid, peer['id']), {})
                    peers.append({'id': peer['id'], 'name': peer['name'], 'position': peer['position'],
                                  'hand_position': peer['hand'], 'grip': peer['grip'], 'fresh': True,
                                  'wallet_held': peer['wallet_held'],
                                  'appearance': peer['appearance'],
                                  'main_hand_side': peer.get('main_hand_side', 'right'),
                                  'heading_radians': peer.get('heading', 0),
                                  'handshake_authorized': bool(proof and not proof['request_id'])})
            return {'ok': True, 'source_kind': 'authenticated_hand_presence', 'character_id': oid,
                    'peers': peers[:31], 'pose_ttl': self.POSE_TTL}

    def authorize_payment(self, account, character_id, target_id, request_id, amount=None):
        with self.lock:
            now = self.clock()
            self._prune(now)
            sender, recipient = self.actors.get(str(character_id)), self.actors.get(str(target_id))
            if not sender or not recipient or sender['account'] != account.lower() or sender is recipient:
                raise ValueError('An authenticated nearby player is required.')
            if not re.fullmatch(r'[A-Za-z0-9_-]{8,64}', request_id or ''):
                raise ValueError('Unique payment request_id required.')
            if any(now - actor['seen'] > self.POSE_TTL or not actor['tracked'] for actor in (sender, recipient)) or not self._near(sender, recipient) or not sender['wallet_held']:
                raise ValueError('Keep the wallet held and remain near the tracked recipient.')
            proof = self.proofs.get((sender['id'], recipient['id']))
            if not proof or (proof['request_id'] and (proof['request_id'] != request_id or proof['amount'] != amount)):
                raise ValueError('Shake hands again before making another payment.')
            proof['request_id'], proof['amount'] = request_id, amount
            # Adapter-only identity for a temporary native recipient connection.
            # Never return this account/token-bearing authorization to clients.
            return {'sender_id': sender['id'], 'target_id': recipient['id'], 'request_id': request_id,
                    'target_account': recipient['account'], 'target_position': list(recipient['position']),
                    'target_zone': recipient['zone'], 'target_cell_id': recipient['cell_id'],
                    'target_building_id': recipient['building_id'], 'target_cell_index': recipient['cell_index']}

    def finish_payment(self, *_args, **_kwargs):
        # Bind even failures to the original key. A lost reply may represent a
        # committed native transaction; it must never authorize a new debit.
        pass


HUB = PresenceHub()
