"""Transient shared performance presence, authenticated by Core3 entry snapshots.

Native performer sessions and accepted flourish receipts are projected here.
This presence bus never grants HAM, stats or XP. Spectator circles are visual;
automatic audience benefits come from separately observed native radius sessions.
"""
try:
 from .planets import SUPPORTED_PLANETS
except ImportError:
 from planets import SUPPORTED_PLANETS
import math
from copy import deepcopy
import secrets
import threading
import time
try:
    from .entertainment_catalog import catalog, context, eligible
    from .entertainer_protocol import audience_snapshot
    from .character_protocol import template_names
    from .weapon_protocol import owned
except ImportError:
    from entertainment_catalog import catalog, context, eligible
    from entertainer_protocol import audience_snapshot
    from character_protocol import template_names
    from weapon_protocol import owned


class PerformanceHub:
    # Presence expires quickly, but scene loading/focus pauses must not destroy
    # the account-bound credential issued before the client starts rendering.
    PRESENCE_IDLE_SECONDS = 15
    SESSION_IDLE_SECONDS = 3600
    # The client polls native entertainer status every five seconds. Missing
    # two polls makes the observation stale, not proof that a buff has expired.
    AUDIENCE_FRESH_SECONDS = 12
    def __init__(self, clock=time.monotonic):
        self.clock = clock
        self.lock = threading.RLock()
        self.sessions = {}
        self.bands = {}
        self.serial = 0

    def register(self, account, oid, result, position):
        ctx = context(result, oid)
        objects = result.get('variables', {}).get('replication', {}).get('objects', {})
        names = template_names()
        items = {key[1:]:names.get(r.get('templateCrc'), '').replace('/shared_', '/')
                 for key,r in objects.items() if owned(r,objects,str(oid))}
        zone=result.get('variables',{}).get('session',{}).get('location',{}).get('zone','tatooine')
        return self.register_observation(account, ctx, items, position, zone)

    def register_observation(self, account, ctx, items, position, zone="tatooine"):
        """Only call with trusted decoded observation, never HTTP client fields."""
        if zone not in SUPPORTED_PLANETS:raise ValueError('Unsupported performance area.')
        with self.lock:
            for token, actor in list(self.sessions.items()):
                if actor['id'] == ctx['character_id']: self._remove(token)
            token = secrets.token_urlsafe(32)
            self.sessions[token] = {'id':ctx['character_id'], 'account':account, 'context':ctx,
                'items':dict(items), 'item':'', 'band':'', 'position':self.point(position),
                'area':zone, 'seen':self.clock(), 'seq':-1, 'watching':{}, 'enabled':True}
            return {'token':token, 'context':ctx, 'radius':catalog()['circle_radius'],
                    'buff_authority':'native_core3', 'audience':self.audience_status(self.sessions[token], self.clock()),
                    'scope':'shared_adapter_presence'}

    def refresh_inventory(self, account, oid, items):
        with self.lock:
            for actor in self.sessions.values():
                if actor['account']==account and actor['id']==str(oid):
                    actor['items']={str(i['id']):str(i['template']).replace('/shared_', '/') for i in items}
                    if actor['item'] not in actor['items'] and actor['item'] not in actor.get('native_placed_items',{}): actor['item']=''

    def observe_native(self, account, oid, envelope):
        """Project an owned Core3 result; callers must never pass HTTP client data."""
        with self.lock:
            actor=self._actor(str(oid))
            if not actor or actor['account']!=account.lower():return
            if envelope.get('source_kind')!='core3_entertainer' or envelope.get('character_id')!=str(oid):raise ValueError('Native entertainer owner mismatch')
            sequence=envelope.get('sequence',0)
            if sequence and sequence<=actor.get('native_sequence',-1):return
            state=envelope.get('state',{});mutation=envelope.get('mutation',{})
            audience = audience_snapshot(state['audience']) if 'audience' in state else None
            actor['native_placed_items']={str(row['id']):str(row['template']).replace('/shared_', '/')
                for row in state.get('placed_instruments',[]) if row.get('playable') is True
                and str(row.get('id','')).isdigit() and '/instrument/' in str(row.get('template',''))}
            learned=list(state.get('skills',[]))
            actor['context']=dict(actor['context'],skills=learned,commands=list(state.get('commands',[])),
                flourishes=list(state.get('flourishes',[])),complete=True,entertainer='social_entertainer_novice' in learned)
            actor['native_sequence']=sequence;actor['native_bound']=True
            actor['area']=state.get('zone',actor['area'])
            actor['native_audience'] = audience
            actor['native_audience_seen'] = self.clock()
            actor['native_audience_zone'] = actor['area']
            performance=next((p for p in catalog()['performances'].values()if state.get('performing') and p['performance_index']==state.get('performance_index') and p['kind']==state.get('kind')), {})
            previous=actor.get('native_performance',{})
            actor['native_performance']=performance
            band=self.bands.get(actor['band']);now=self.clock()
            if performance and not band:
                self.serial+=1;bid=str(self.serial)
                band={'id':bid,'leader':actor['id'],'members':{actor['id']},'performance':{},'started':now,'flourish':{},'revision':0}
                self.bands[bid]=band;actor['band']=bid
            if band and band['leader']==actor['id'] and performance!=previous:
                band.update(performance=performance,started=now,flourish={},revision=band['revision']+1)
            if band and mutation.get('success') and mutation.get('operation')=='flourish' and not mutation.get('replayed'):
                band['flourish']={k:mutation[k]for k in ('index','command','level','effect_file','effect_position','target_id','duration','request_id')if k in mutation}
                band['flourish'].update(actor=actor['id'],time=now,source_kind='core3_entertainer',sequence=sequence)

    @staticmethod
    def point(value):
        if not isinstance(value,list) or len(value)!=3 or any(type(v) not in (int,float) or not math.isfinite(v) or abs(v)>20000 for v in value):
            raise ValueError('Invalid performance position.')
        return list(value)

    def _actor(self, oid):
        return next((a for a in self.sessions.values() if a['id']==oid), None)

    def _remove(self, token):
        actor = self.sessions.pop(token)
        self._leave(actor)

    def _leave(self, actor):
        band = self.bands.get(actor['band'])
        if band:
            if band['leader']==actor['id']:
                for member in self.sessions.values():
                    if member['band']==actor['band']: member['band']=''
                del self.bands[band['id']]
            else: band['members'].discard(actor['id'])
        actor['band']=''

    @staticmethod
    def near(a, b, radius):
        return a['area']==b['area'] and abs(a['position'][1]-b['position'][1])<=1.8 and math.hypot(a['position'][0]-b['position'][0],a['position'][2]-b['position'][2])<=radius

    def performance(self, actor, band):
        if not actor['enabled']:return {}
        if actor.get('native_bound'):return actor.get('native_performance',{})
        if not band.get('performance'): return {}
        leader = self._actor(band['leader'])
        if not leader or not self.near(actor,leader,50): return {}
        template = actor['items'].get(actor['item'],'')
        return next((p for p in eligible(actor['context']['skills'],template)
                     if p['name']==band['performance']['name'] and p['kind']==band['performance']['kind']), {})

    def audience_status(self, actor, now):
        audience = actor.get('native_audience')
        if audience is None:
            return {'status':'unobserved', 'observation_age_seconds':None,
                    'sequence':None, 'state':None}
        age = max(0.0, now - actor['native_audience_seen'])
        fresh = (age <= self.AUDIENCE_FRESH_SECONDS and actor['enabled']
                 and actor['area'] == actor['native_audience_zone'])
        return {'status':'fresh' if fresh else 'stale', 'observation_age_seconds':age,
                'sequence':actor.get('native_sequence', 0),
                'state':deepcopy(audience) if fresh else None}

    def update(self, account, data):
        with self.lock:
            now = self.clock()
            for token, actor in list(self.sessions.items()):
                idle = now-actor['seen']
                if idle > self.SESSION_IDLE_SECONDS:
                    self._remove(token)
                elif idle > self.PRESENCE_IDLE_SECONDS:
                    self._leave(actor)
                    actor['enabled'] = False
                    actor['watching'] = {}
                    # A fresh native observation must rebuild the projection on
                    # resume; an old cached performance cannot restart it itself.
                    actor.pop('native_performance', None)
            actor = self.sessions.get(data.get('token'))
            if not actor or actor['account']!=account: raise ValueError('Performance session expired; enter the character again.')
            seq = data.get('seq')
            if type(seq)!=int or seq<0: raise ValueError('Invalid performance sequence.')
            # Retries return state without replaying mutations/flourishes.
            if seq<=actor['seq']: return self.snapshot(actor,now)
            position = self.point(data.get('position'))
            area = data.get('area',actor['area'])
            if not isinstance(area,str) or area not in SUPPORTED_PLANETS: raise ValueError('Unsupported performance area.')
            item = str(data.get('item_id',''))
            if item and item not in actor['items'] and not (actor.get('native_bound') and item in actor.get('native_placed_items',{})):
                raise ValueError('Performance item is not owned or approved by the native placed-instrument state.')
            action = data.get('action','')
            if action not in ('','start_band','join','leave','perform','stop','flourish'): raise ValueError('Unknown performance action.')
            if actor.get('native_bound') and action in ('perform','stop','flourish'):
                action='' # Native receipts already project the exact accepted result.
            requested = None
            if action=='perform':
                requested = next((p for p in eligible(actor['context']['skills'],actor['items'].get(item,'')) if p['id']==data.get('performance_id')),None)
                if not requested: raise ValueError('This performance or instrument has not been learned.')
            actor.update(position=position,area=area,seen=now,seq=seq)
            actor['enabled'] = data.get('enabled',True) is True
            changed_item = item!=actor['item']
            actor['item']=item
            band = self.bands.get(actor['band'])
            if band and band['leader']==actor['id'] and not actor.get('native_bound') and (not actor['enabled'] or changed_item): band['performance']={}
            if action not in ('','leave','stop') and (not actor['enabled'] or not actor['context'].get('entertainer')):
                raise ValueError('An active entertainer is required.')
            if action=='start_band':
                if band: raise ValueError('Leave the current band first.')
                self.serial+=1
                bid=str(self.serial)
                band={'id':bid,'leader':actor['id'],'members':{actor['id']},'performance':{},'started':now,'flourish':{},'revision':0}
                self.bands[bid]=band
                actor['band']=bid
            elif action=='join':
                target = self.bands.get(str(data.get('band_id','')))
                leader = self._actor(target['leader']) if target else None
                if band or not leader or not self.near(actor,leader,catalog()['circle_radius']): raise ValueError('Stand inside an available band circle to join.')
                if len(target['members'])>=20: raise ValueError('Band is full.')
                target['members'].add(actor['id']); actor['band']=target['id']; band=target
            elif action=='leave': self._leave(actor)
            elif action in ('perform','stop'):
                if not band:
                    if action=='stop': return self.snapshot(actor,now)
                    # Solo performance gets the same projected audience circle.
                    self.serial+=1
                    bid=str(self.serial)
                    band={'id':bid,'leader':actor['id'],'members':{actor['id']},'performance':{},'started':now,'flourish':{},'revision':0}
                    self.bands[bid]=band; actor['band']=bid
                if band['leader']!=actor['id']: raise ValueError('Band members follow the leader; leave to perform solo.')
                performance = {}
                if action=='perform':
                    performance = requested
                band.update(performance=performance,started=now,flourish={},revision=band['revision']+1)
            elif action=='flourish':
                performance = self.performance(actor,band) if band else {}
                if not performance: raise ValueError('Perform before flourishing.')
                permitted = actor['context'].get('flourishes',[])
                if not permitted: raise ValueError('No learned flourishes.')
                if now-actor.get('last_flourish',-10)<5: raise ValueError('Flourish is recovering.')
                actor['last_flourish']=now
                band['flourish']={'actor':actor['id'],'index':secrets.choice(permitted),'time':now}
            return self.snapshot(actor,now)

    def snapshot(self, actor, now):
        visible=[]
        watching={}
        for band in self.bands.values():
            leader = self._actor(band['leader'])
            if not leader or leader['area']!=actor['area']: continue
            if math.dist(leader['position'],actor['position'])>catalog()['cull_distance']: continue
            members=[]
            for oid in sorted(band['members']):
                member=self._actor(oid)
                if not member: continue
                performance=self.performance(member,band)
                members.append({'id':oid,'position':member['position'],'performance_id':performance.get('id','')})
            visible.append({'id':band['id'],'leader':band['leader'],'position':leader['position'],'radius':catalog()['circle_radius'],
                'members':members,'performance':band['performance'],'started':band['started'],'revision':band['revision'],'flourish':band['flourish']})
            if band['performance'] and actor['id'] not in band['members'] and actor['enabled'] and self.near(actor,leader,catalog()['circle_radius']):
                since=actor['watching'].get(band['id'],{}).get('since',now)
                watching[band['id']]={'since':since,'seconds':now-since,'kind':band['performance']['kind'],
                    'presentation_only':True}
        actor['watching']=watching
        own=self.bands.get(actor['band'])
        playing=self.performance(actor,own) if own else {}
        return {'context':actor['context'],'native_authority':actor.get('native_bound',False),'server_time':now,'bands':visible,'band_id':actor['band'],'leader':own['leader'] if own else '',
                'performance_id':playing.get('id',''),'watching':watching,
                'buff_authority':'native_core3','audience':self.audience_status(actor,now),
                'source':'shared_adapter_presence'}


HUB = PerformanceHub()
