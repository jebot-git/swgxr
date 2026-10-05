#!/usr/bin/env python3
"""Offline wire-layout tests. Does not claim live damage or NPC AI validation."""
import json
from pathlib import Path
import struct
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from server.combat_protocol import CREO, TANO, baseline, snapshot, apply_attribute_delta


def pack(fmt, *values):
    return struct.pack('<' + fmt, *values)


def ascii_string(value):
    raw = value.encode('ascii')
    return pack('H', len(raw)) + raw


def numbers(values, counter=1, fmt='i'):
    return pack('II', len(values), counter) + pack(fmt * len(values), *values)


def fixture(posture=0, health=800):
    # Independent pinned packet order: TANO3 then CREO3; TANO6 then CREO6.
    tano3 = (pack('f', 1) + ascii_string('mob/creature_names') + pack('I', 0)
             + ascii_string('kreetle') + pack('II', 0, 1) + ascii_string('')
             + numbers([], fmt='I') + pack('IIII B', 0, 7, 12, 1000, 1))
    creo3 = (tano3 + pack('BBQfiQ', posture, 0, 0, 0.75, 42, 1 << 60)
             + numbers([20, 0, 0, 30, 0, 0, 40, 0, 0], 11))
    creo6 = (pack('I', 0x76) + numbers([9007199254740993], fmt='Q')
             + pack('H', 3) + ascii_string('') + ascii_string('neutral')
             + pack('QQQQIQBII', 9007199254740995, 0, 0, 0, 0,
                    9007199254740993, 0, 0, 0)
             + numbers([health, 100, 100, 600, 100, 100, 400, 100, 100], 15)
             + numbers([1000, 100, 100, 900, 100, 100, 800, 100, 100], 12)
             + numbers([], fmt='Q') + ascii_string('') + pack('B', 0))
    return {'type': CREO, 'baseline3': creo3.hex(), 'baseline6': creo6.hex()}, tano3


class CombatProtocolTests(unittest.TestCase):
    def test_nine_pools_and_wounds(self):
        state = baseline(fixture()[0])
        self.assertTrue(state['complete'])
        for name, values in [('health', (800, 1000, 20)), ('action', (600, 900, 30)),
                             ('mind', (400, 800, 40))]:
            self.assertEqual(tuple(state['pools'][name].values()), values)
        self.assertEqual(len(state['pools']), 9)
        self.assertEqual(state['shock_wounds'], 42)
        self.assertEqual(state['states'], str(1 << 60))
        self.assertEqual(state['weapon_id'], '9007199254740995')
        self.assertEqual(state['target_id'], '9007199254740993')

    def test_posture_decides_life_state_not_zero_ham(self):
        for posture in [0, 12, 13, 14]:
            with self.subTest(posture=posture):
                state = baseline(fixture(posture, health=0)[0])
                self.assertEqual(state['dead'], posture == 14)
                self.assertEqual(state['incapacitated'], posture == 13)
                self.assertEqual(state['knocked_down'], posture == 12)

    def test_missing_baseline_is_incomplete(self):
        record, _ = fixture(); del record['baseline6']
        state = baseline(record)
        self.assertFalse(state['complete'])
        self.assertNotIn('ham', state)
        with self.assertRaises(ValueError): baseline({'type': CREO})

    def test_lair_condition_is_not_creature_ham(self):
        _, tano = fixture()
        state = baseline({'type': TANO, 'baseline3': tano.hex(),
                          'baseline6': (pack('I', 0x76) + numbers([], fmt='Q')).hex()})
        self.assertEqual((state['condition_damage'], state['max_condition']), (12, 1000))
        self.assertNotIn('ham', state)
        self.assertNotIn('dead', state)

    def test_reject_bad_wire_data(self):
        record, _ = fixture()
        for field in ('baseline3', 'baseline6'):
            for cut in (2, 12, 40):
                broken = dict(record); broken[field] = record[field][:cut]
                with self.assertRaises(ValueError): baseline(broken)
        with self.assertRaises(ValueError): baseline(fixture(posture=200)[0])

    def test_snapshot_identity_and_explicit_offline_status(self):
        record, _ = fixture()
        result = {'variables': {'scene': {'characterOid': '9007199254740993'},
                               'replication': {'objects': {'o9007199254740993': record}}}}
        state = snapshot(result, '9007199254740993')
        self.assertFalse(state['live'])
        self.assertTrue(state['player']['complete'])
        with self.assertRaises(ValueError): snapshot(result, '9007199254740992')

    def test_atomic_ham_delta_and_counter_wrap(self):
        current = {'counter': 0xffffffff, 'values': [100] * 9}
        delta = pack('IIBHi', 1, 0, 2, 3, 25)
        changed = apply_attribute_delta(current, delta)
        self.assertEqual(changed['values'][3], 25)
        self.assertEqual(current['values'][3], 100)
        self.assertEqual(changed['counter'], 0)
        for broken in [delta[:-1], delta + b'X', pack('IIBHi', 1, 4, 2, 3, 25),
                       pack('IIBHi', 1, 0, 2, 9, 25), pack('IIBHi', 1, 0, 1, 3, 25)]:
            with self.assertRaises(ValueError): apply_attribute_delta(current, broken)
            self.assertEqual(current['values'], [100] * 9)
        with self.assertRaises(ValueError): apply_attribute_delta(changed, delta)

    def test_archived_actual_core3_creature(self):
        paths = sorted((ROOT / 'runtime/server').glob('*.result.json'))
        found = False
        for path in paths:
            data = json.loads(path.read_text())
            scene = data.get('variables', {}).get('scene', {})
            if not scene.get('characterOid'): continue
            state = snapshot(data, scene['characterOid'])
            self.assertEqual(len(state['player']['wounds']['values']), 9)
            found = True
        if not found: self.skipTest('No archived original protocol capture available.')


if __name__ == '__main__':
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(CombatProtocolTests)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    report = {'test': 'core3_combat_protocol', 'passed': result.wasSuccessful(),
              'tests': result.testsRun, 'skipped': len(result.skipped),
              'live_core3_tested': False, 'damage_or_ai_tested': False}
    output = ROOT / 'runtime/evidence/combat-protocol.json'
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2) + '\n')
    raise SystemExit(not result.wasSuccessful())
