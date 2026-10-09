"""Exercise real routing and delivery logic without network sockets or audio I/O."""
import asyncio
from collections import deque
from copy import deepcopy
import json
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import patch
from types import SimpleNamespace

from server.voice_protocol import NativeVoiceState, VoiceError, CLIENT_HEADER, audible, granted
from server.voice_relay import Relay


class Writer:
    def __init__(self): self.closed=False;self.packets=[]
    def close(self): self.closed=True
    def write(self,packet): self.packets.append(packet)
    async def drain(self): pass


def state(oid, ship='500', **changes):
    value=dict(account=str(oid),character_id=str(oid),session_id='session'+str(oid),name='Crew',
        position=[0,0,0],zone='space_tatooine',zone_id='90',group_id='0',faction='neutral',
        scope='sector',ship_id=ship,building_id=ship,cell_index=1,updated_at=time.time(),ttl=4)
    value.update(changes)
    return value


def relay_with(*states):
    relay=object.__new__(Relay);relay.states={};relay.peers={}
    for source in states:
        key=source['account']
        peer=dict(key=key,claims=dict(a=key,c=source['character_id'],s=source['session_id']),
                  state=deepcopy(source),channel='proximity',epoch=1,seq=-1,queue=deque(),wake=asyncio.Event(),
                  writer=Writer(),speakers={},tokens=6.,token_time=time.monotonic())
        relay.states[key]=deepcopy(source);relay.peers[key]=peer
    return relay


class SpaceVoicePolicyTests(unittest.TestCase):
    def test_sector_replaces_planet_and_is_distinct_per_native_zone(self):
        a,b=state(1),state(2,'600')
        self.assertEqual(set(granted(a)[0]),{'proximity','sector'})
        self.assertFalse(audible(a,b,'planet'));self.assertTrue(audible(a,b,'sector'))
        for changes in ({'zone':'space_naboo'}, {'zone_id':'91'}, {'zone':'tatooine','scope':'planet','ship_id':'0'}):
            self.assertFalse(audible(a,dict(b,**changes),'sector'))

    def test_proximity_shares_hull_without_requiring_party(self):
        a,b=state(1),state(2,position=[64,0,0],cell_index=2)
        self.assertTrue(audible(a,b,'proximity'))
        self.assertFalse(audible(a,b,'group'))
        b['position']=[64.01,0,0];self.assertFalse(audible(a,b,'proximity'))
        b.update(position=[0,0,0],ship_id='600');self.assertFalse(audible(a,b,'proximity'))

    def test_fighters_at_same_local_origin_cannot_hear_through_hulls(self):
        a=state(1,cell_index=0,building_id='0')
        b=state(2,'600',cell_index=0,building_id='0')
        self.assertFalse(audible(a,b,'proximity'));self.assertTrue(audible(a,b,'sector'))

    def test_group_and_faction_remain_independent_across_ship_and_ground(self):
        a=state(1,group_id='33',faction='rebel')
        b=state(2,'0',zone='naboo',zone_id='12',scope='planet',group_id='33',faction='rebel')
        self.assertTrue(audible(a,b,'group'));self.assertTrue(audible(a,b,'faction'))
        self.assertFalse(audible(a,b,'proximity'));self.assertFalse(audible(a,b,'planet'))

    def test_ground_interiors_with_equal_local_coordinates_are_isolated(self):
        a=state(1,'0',zone='tatooine',scope='planet',building_id='100')
        b=state(2,'0',zone='tatooine',scope='planet',building_id='101')
        self.assertFalse(audible(a,b,'proximity'));self.assertTrue(audible(a,b,'planet'))

    def test_native_publication_rejects_missing_or_inconsistent_space_metadata(self):
        with tempfile.TemporaryDirectory() as folder:
            now=[100.];cache=NativeVoiceState(Path(folder)/'voice.json',clock=lambda:now[0])
            player={'position':[0,0,0],'zone':'space_tatooine','building_id':'500','cell_index':1,
                    'voice':{'zone_id':'90','group_id':'0','faction':'neutral','scope':'sector','ship_id':'500'}}
            cache.publish('ALICE','1',player,session_id='native',live=True)
            self.assertEqual(cache.owned('alice','1','native')['ship_id'],'500')
            for change in ({'ship_id':'0'},{'scope':'planet'},{'ship_id':True},{'group_id':'-1'}):
                cache.publish('alice','1',dict(player,voice=dict(player['voice'],**change)),session_id='native',live=True)
                with self.assertRaises(VoiceError):cache.owned('alice','1','native')
                cache.publish('alice','1',player,session_id='native',live=True)
            cache.publish('alice','1',dict(player,voice={'zone_id':'90','group_id':'0','faction':'neutral'}),session_id='native',live=True)
            with self.assertRaises(VoiceError):cache.owned('alice','1','native')
            cache.publish('alice','1',player,session_id='native',live=True);now[0]+=4.01
            with self.assertRaises(VoiceError):cache.owned('alice','1','native')

    def test_live_voice_uses_published_ship_identity_without_ground_rpc(self):
        from server import adapter
        with patch.object(adapter.LIVE_COMBAT,'active_for',return_value={'id':'owned','character_id':'1'}), \
             patch.object(adapter.VOICE_STATE,'owned',return_value=state(1,session_id='owned')), \
             patch.object(adapter,'services_request') as services:
            out=adapter.voice_request('alice',{'character_id':'1','session_id':'owned','ship_id':'forged','zone':'naboo'})
            self.assertEqual(out['scope'],'sector');self.assertEqual(out['ship_id'],'500')
            self.assertIn('sector',out['channels']);self.assertNotIn('planet',out['channels']);services.assert_not_called()
            with self.assertRaises(ValueError):adapter.voice_request('alice',{'character_id':'1','session_id':'wrong'})

    def test_dead_live_voice_never_falls_back_to_a_ground_native_login(self):
        from server import adapter
        with patch.object(adapter.LIVE_COMBAT,'active_for',return_value=None), \
             patch.object(adapter,'services_request') as services,patch.object(adapter.VOICE_STATE,'owned') as cache:
            for identity in ({'session_id':'expired'},{'live_session_id':'expired'},{'zone':'space_tatooine'}):
                with self.subTest(identity=identity),self.assertRaises(ValueError):
                    adapter.voice_request('alice',dict(character_id='1',**identity))
            services.assert_not_called();cache.assert_not_called()

    def test_relay_hull_change_flushes_queue_and_emits_authoritative_context(self):
        relay=relay_with(state(1),state(2));a,b=relay.peers.values()
        relay.audio(a,CLIENT_HEADER.pack(1,0)+b'\x98\x00');self.assertEqual(len(b['queue']),1)
        relay.states['2']['ship_id']='600';relay.states['2']['building_id']='600'
        self.assertTrue(relay.sync_peer(b));self.assertEqual(b['epoch'],2)
        self.assertEqual(len(b['queue']),1)
        packet=b['queue'][0][1][3]
        start=4 if packet[1]==126 else 2
        message=json.loads(packet[start:])
        self.assertEqual((message['type'],message['scope'],message['ship_id']),('tuned','sector','600'))
        self.assertIsNone(b['queue'][0][1][0])

    def test_relay_automatic_planet_sector_transition_and_stale_session_close(self):
        relay=relay_with(state(1));a=relay.peers['1'];a['channel']='sector'
        relay.states['1'].update(zone='tatooine',scope='planet',ship_id='0',building_id='0')
        relay.sync_peer(a);self.assertEqual(a['channel'],'planet')
        relay.states['1'].update(zone='space_tatooine',scope='sector',ship_id='500')
        relay.sync_peer(a);self.assertEqual(a['channel'],'sector')
        relay.states['1']['session_id']='replacement'
        self.assertFalse(relay.sync_peer(a));self.assertTrue(a['writer'].closed);self.assertFalse(a['queue'])

    def test_inflight_old_epoch_after_native_hull_change_is_dropped(self):
        relay=relay_with(state(1),state(2));a,b=relay.peers.values()
        relay.states['1']['ship_id']='600'
        relay.audio(a,CLIENT_HEADER.pack(1,0)+b'\x98\x00')
        self.assertEqual(a['epoch'],2);self.assertFalse(a['writer'].closed)
        self.assertFalse(b['queue'])
        a['epoch_changed_at']-=1
        with self.assertRaises(VoiceError):relay.audio(a,CLIENT_HEADER.pack(1,1)+b'\x98\x00')

    def test_relay_routing_and_expiry_use_latest_native_state(self):
        relay=relay_with(state(1),state(2),state(3,'600'));a,b,c=relay.peers.values()
        relay.audio(a,CLIENT_HEADER.pack(1,0)+b'\x98\x00')
        self.assertEqual(len(b['queue']),1);self.assertFalse(c['queue'])
        for peer in relay.peers.values():relay.tune(peer,'sector');peer['queue'].clear()
        relay.audio(a,CLIENT_HEADER.pack(a['epoch'],0)+b'\x98\x00')
        self.assertEqual(len(b['queue']),1);self.assertEqual(len(c['queue']),1)
        relay.states['2']['updated_at']=time.time()-5
        relay.audio(a,CLIENT_HEADER.pack(a['epoch'],1)+b'\x98\x00')
        self.assertTrue(b['writer'].closed);self.assertFalse(b['queue'])
        relay.states.pop('1')
        with self.assertRaises(VoiceError):relay.audio(a,CLIENT_HEADER.pack(a['epoch'],2)+b'\x98\x00')

    def test_relay_state_refresh_handles_more_than_old_64k_cache(self):
        relay=object.__new__(Relay)
        with tempfile.TemporaryDirectory() as folder:
            relay.state_path=Path(folder)/'state.json'
            payload={str(oid):state(oid) for oid in range(1,301)}
            raw=json.dumps(payload);self.assertGreater(len(raw),65536)
            relay.state_path.write_text(raw);relay.refresh_states()
            self.assertEqual(len(relay.states),300)
            self.assertIsNotNone(relay.state({'a':'300','c':'300','s':'session300'}))
            relay.states['300']['group_id']=0
            self.assertIsNone(relay.state({'a':'300','c':'300','s':'session300'}))

    def test_hull_context_ack_survives_three_speaker_authorized_audio_burst(self):
        relay=relay_with(state(1,'600'),state(2,'600'),state(3,'600'),state(4,'500'))
        listener=relay.peers['4']
        relay.states['4'].update(ship_id='600',building_id='600')
        self.assertTrue(relay.sync_peer(listener));self.assertEqual(listener['epoch'],2)
        context=listener['queue'][0]
        self.assertIsNone(context[1][0])
        for oid in ('1','2','3'):
            for sequence in range(6):relay.audio(relay.peers[oid],CLIENT_HEADER.pack(1,sequence)+b'\x98\x00')
        self.assertEqual(len(listener['queue']),16)
        self.assertEqual(listener['queue'][0],context)
        self.assertEqual(sum(entry[1][0]is None for entry in listener['queue']),1)
        self.assertFalse(listener['writer'].closed)

    def test_all_control_queue_is_bounded_and_never_silently_loses_context(self):
        relay=relay_with(state(1));peer=relay.peers['1']
        for _ in range(16):relay.control(peer,'roster',peers=[])
        self.assertEqual(len(peer['queue']),16)
        relay.enqueue(peer,('another-speaker',1,1,b'audio'))
        self.assertEqual(len(peer['queue']),16);self.assertFalse(peer['writer'].closed)
        relay.control(peer,'tuned',epoch=99)
        self.assertTrue(peer['writer'].closed);self.assertFalse(peer['queue']);self.assertTrue(peer['closing'])
        relay.control(peer,'roster',peers=[]);self.assertFalse(peer['queue'])

    def test_replaced_connection_cannot_publish_or_consume_listener_budget(self):
        relay=relay_with(state(1),state(2));old=relay.peers['1'];listener=relay.peers['2']
        replacement=relay_with(state(1)).peers['1'];relay.peers['1']=replacement
        for sequence in range(6):
            with self.assertRaises(VoiceError):relay.audio(old,CLIENT_HEADER.pack(1,sequence)+b'\x98\x00')
        self.assertTrue(old['writer'].closed);self.assertFalse(listener['queue']);self.assertFalse(listener['speakers'])
        relay.audio(replacement,CLIENT_HEADER.pack(1,0)+b'\x98\x00')
        self.assertEqual(len(listener['queue']),1)


class SpaceVoiceDeliveryTests(unittest.IsolatedAsyncioTestCase):
    async def test_replacement_with_equal_epoch_cannot_inherit_queued_old_audio(self):
        relay=relay_with(state(1),state(2));old,listener=relay.peers.values()
        relay.audio(old,CLIENT_HEADER.pack(1,0)+b'\x98\x00')
        replacement=relay_with(state(1)).peers['1'];relay.peers['1']=replacement
        # Equal numeric epochs are deliberate: account+epoch is not a connection fence.
        relay.audio(replacement,CLIENT_HEADER.pack(1,0)+b'\x98\x00')
        sender=asyncio.create_task(relay.send(listener))
        await asyncio.sleep(.01);sender.cancel()
        try:await sender
        except asyncio.CancelledError:pass
        self.assertEqual(sum(packet[0]&15==2 for packet in listener['writer'].packets),1)

    async def test_actual_tick_revokes_auth_and_drops_already_queued_voice(self):
        relay=relay_with(state(1),state(2));a,b=relay.peers.values()
        relay.audio(a,CLIENT_HEADER.pack(1,0)+b'\x98\x00')
        relay.refresh_states=lambda:None
        relay.credentials=SimpleNamespace(valid=lambda claims:claims['a']!='1')
        ticker=asyncio.create_task(relay.tick())
        await asyncio.sleep(.01);ticker.cancel()
        try:await ticker
        except asyncio.CancelledError:pass
        self.assertTrue(a['writer'].closed);self.assertTrue(a['revoked'])
        sender=asyncio.create_task(relay.send(b))
        await asyncio.sleep(.01);sender.cancel()
        try:await sender
        except asyncio.CancelledError:pass
        self.assertFalse(any(packet[0]&15==2 for packet in b['writer'].packets))

    async def test_already_queued_audio_cannot_cross_hull_change_or_expiry(self):
        for change in ('hull','expiry','remove'):
            with self.subTest(change=change):
                relay=relay_with(state(1),state(2));a,b=relay.peers.values()
                relay.audio(a,CLIENT_HEADER.pack(1,0)+b'\x98\x00')
                if change=='hull':relay.states['2']['ship_id']='600'
                elif change=='expiry':relay.states['1']['updated_at']=time.time()-5
                else:relay.states.pop('1')
                sender=asyncio.create_task(relay.send(b))
                await asyncio.sleep(.01);sender.cancel()
                try:await sender
                except asyncio.CancelledError:pass
                self.assertFalse(any(packet[0]&15==2 for packet in b['writer'].packets))


if __name__=='__main__':unittest.main()
