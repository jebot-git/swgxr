import unittest
from copy import deepcopy
from unittest.mock import Mock, patch

from server import adapter, jtl_protocol as protocol, remote_gateway
from server.live_combat import LiveCombatHub, LiveConflict


class JtlProtocolTests(unittest.TestCase):
    def test_only_bounded_control_intent_reaches_native(self):
        raw = dict(sequence=2, throttle=.5, pitch=-1, yaw=0, roll=1,
                   zone='space_tatooine', ship_id='999', speed=9999, damage=999)
        out = protocol.command('control', raw)
        self.assertEqual(set(out), {'action','sequence','throttle','pitch','yaw','roll','zone'})
        for field, value in [('sequence',True),('sequence',0),('sequence',2**53),
                             ('throttle',-1),('pitch',float('nan')),('roll',2),('zone','space_yavin4')]:
            with self.subTest(field=field,value=value), self.assertRaises(ValueError):
                protocol.command('control',dict(raw,**{field:value}))

    def test_launch_is_terminal_bound_and_mutations_are_replayable(self):
        raw = dict(request_id='launch_001',terminal_id='123',launch_id='prepared_001',zone='tatooine')
        self.assertEqual(protocol.command('launch',raw)['terminal_id'],'123')
        for changed in ({'terminal_id':'0'},{'terminal_id':12},{'request_id':''},{'launch_id':''}):
            with self.assertRaises(ValueError):protocol.command('launch',dict(raw,**changed))
        with self.assertRaises(ValueError):protocol.command('command',dict(raw,command_id='destroy_all'))
        with self.assertRaises(ValueError):protocol.command('station',dict(raw,station_id='turret'))
        self.assertEqual(protocol.command('station',dict(raw,station_id='passenger'))['station_id'],'passenger')
        with self.assertRaises(ValueError):protocol.command('command',dict(raw,command_id='elevator_up'))
        self.assertEqual(protocol.command('command',dict(raw,command_id='elevator_up',interaction_id='92'))['interaction_id'],'92')

    def test_crew_and_boarding_ids_are_native_and_authorization_cannot_be_forged(self):
        base=dict(request_id='crew_00001',pilot_id='44',launch_id='prepared_001',crew_handshake_id='a'*24,
                  handshake_authorized=True,handshake_receipt_only=False,capacity=999)
        out=protocol.command('crew_join',base)
        self.assertEqual(set(out),{'action','request_id','pilot_id','launch_id','crew_handshake_id'})
        for changed in ({'pilot_id':'0'},{'pilot_id':44},{'launch_id':'../stage'}, {'crew_handshake_id':'b'*25}):
            with self.assertRaises(ValueError):protocol.command('crew_join',dict(base,**changed))
        for action,key in [('crew_remove','member_id'),('boarding_request','target_ship_id'),
                           ('boarding_accept','requester_id'),('boarding_decline','requester_id')]:
            self.assertEqual(protocol.command(action,dict(base,**{key:'45'}))[key],'45')
            with self.assertRaises(ValueError):protocol.command(action,dict(base,**{key:False}))
        self.assertEqual(protocol.command('crew_prepare',dict(base,terminal_id='90',ship_id='99'))['ship_id'],'99')

    def test_live_crew_join_requires_consumable_presence_and_preserves_retry_marker(self):
        from server.services_presence import HUB
        hub=LiveCombatHub();process=Mock();process.poll.return_value=None
        hub.sessions['tester']=dict(account='tester',character_id='42',id='owned',process=process)
        self.addCleanup(hub.sessions.clear)
        hub._exchange=Mock(return_value={'session_live':True})
        crew=dict(action='crew_join',request_id='crew_00001',pilot_id='44',launch_id='prepared_001',
                  crew_handshake_id='a'*24,handshake_authorized=True,handshake_receipt_only=False)
        data=dict(character_id='42',session_id='owned',jtl=crew)
        with patch.object(HUB,'authorize_crew_handshake',side_effect=ValueError('No handshake')):
            with self.assertRaises(ValueError):hub.request('tester','jtl',data)
            hub._exchange.assert_not_called()
        with patch.object(HUB,'authorize_crew_handshake',return_value={'receipt_only':True}) as authorize:
            hub.request('tester','jtl',data)
            authorize.assert_called_once_with('tester','42','44','prepared_001','crew_00001','a'*24)
            sent=hub._exchange.call_args.args[1]['jtl']
            self.assertTrue(sent['handshake_authorized'])
            self.assertTrue(sent['handshake_receipt_only'])

    def test_house_placement_contract_and_original_cells(self):
        raw = dict(request_id='decorate_001',item_id='123',cell_index=1,
                   placement_position=[0,.4,20],local_quaternion=[0,0,0,1],suspended=False)
        self.assertEqual(protocol.command('decorate',raw)['placement_position'],[0,.4,20])
        for changed in ({'cell_index':12},{'cell_index':True},{'local_quaternion':[0,0,0,0]},
                        {'placement_position':[0,65,0]},{'suspended':1}):
            with self.assertRaises(ValueError):protocol.command('decorate',dict(raw,**changed))
        with self.assertRaises(ValueError):protocol.command('recover',dict(request_id='recover_001',item_id='123'))
        hands=dict(left_hand=[0,1,0],right_hand=[.2,1,0])
        self.assertEqual(protocol.command('recover',dict(raw,**hands))['left_hand'],hands['left_hand'])

    def test_live_ownership_and_response_authority(self):
        hub=LiveCombatHub()
        process=Mock();process.poll.return_value=None
        hub.sessions['tester']=dict(account='tester',character_id='42',id='owned',process=process)
        self.addCleanup(hub.sessions.clear)
        mutation=dict(success=True,source_kind='core3_jtl',character_id='42',jtl=dict(aboard=True))
        reply=dict(session_live=True,mutation=mutation)
        hub._exchange=Mock(return_value=reply)
        with patch.object(adapter,'LIVE_COMBAT',hub):
            out=adapter.jtl_request('tester','42','status',dict(zone='space_tatooine'))
            self.assertTrue(out['state']['aboard'])
            self.assertIs(out['live_response'],reply)
            with self.assertRaises(LiveConflict):adapter.jtl_request('tester','43','status',{})
            with self.assertRaises(LiveConflict):adapter.jtl_request('tester','42','status',dict(live_session_id='stale'))
        self.assertEqual(hub._exchange.call_count,1)
        sent=hub._exchange.call_args.args[1]
        self.assertEqual(sent['jtl'],dict(action='status',zone='space_tatooine'))
        with self.assertRaises(ValueError):protocol.snapshot(mutation,'43')

    def test_public_routes_are_exact(self):
        for action in protocol.ACTIONS:self.assertIn('/jtl/'+action,remote_gateway.POST)
        self.assertNotIn('/jtl/spawn',remote_gateway.POST)
        self.assertIn('/services/skill_forget',remote_gateway.POST)

    def test_decoration_refreshes_authoritative_inventory(self):
        live=Mock();live.active_for.return_value={'id':'owned'}
        live.request.return_value={'mutation':dict(success=True,source_kind='core3_jtl',character_id='42',jtl={})}
        request=dict(request_id='decorate_001',item_id='12',cell_index=1,placement_position=[0,0,0],local_quaternion=[0,0,0,1],suspended=False)
        inventory={'source_kind':'core3_inventory','character_id':'42','items':[]}
        with patch.object(adapter,'LIVE_COMBAT',live),patch.object(adapter,'read_inventory',return_value=inventory) as read:
            self.assertEqual(adapter.jtl_request('tester','42','decorate',request)['inventory'],inventory)
            read.assert_called_once_with('tester','42')

    def test_rejected_control_preserves_remote_boarding_and_ground_ejection(self):
        for state in ({'space_active':True,'ship':{'id':'99','station':'interior'}},
                      {'space_active':False,'ship':{},'launch_stage':{}}):
            with self.subTest(state=state):
                live=Mock();live.active_for.return_value={'id':'owned'}
                response={'mutation':dict(success=False,source_kind='core3_jtl',character_id='42',
                    error_code='jtl_pilot_required',error='jtl_pilot_required',jtl=state),
                    'snapshot':{'player':{'id':'42','position':[3600,5,-4785],'zone':'tatooine'}},'sequence':7}
                live.request.return_value=response
                with patch.object(adapter,'LIVE_COMBAT',live),self.assertRaises(adapter.NativeJtlRejected) as error:
                    adapter.jtl_request('tester','42','control',dict(sequence=1,throttle=0,pitch=0,yaw=0,roll=0))
                out=error.exception.result
                self.assertFalse(out['ok'])
                self.assertEqual(out['source_kind'],'core3_jtl')
                self.assertEqual(out['state'],state)
                self.assertIs(out['live_response'],response)
                self.assertEqual(out['sequence'],7)
                self.assertEqual(out['error_code'],'jtl_pilot_required')

    def test_all_native_ship_roster_copies_use_original_appearance_decoder(self):
        crew={'id':'43','client_crc':10,'customization_hex':'',
              'appearance':{'client_crc':10,'customization_hex':'01010407ff03','hair_customization_hex':'01010402ff03',
                            'equipment':[{'client_crc':20,'customization_hex':'01010409ff03'}]}}
        state={'ship':{'crew':[crew]}}
        wire={'snapshot':{'player':{'jtl':deepcopy(state)},'jtl':deepcopy(state)},
              'mutation':{'jtl':deepcopy(state)}}
        hub=LiveCombatHub();self.addCleanup(hub.sessions.clear)
        with patch('server.live_combat.template_names',return_value={10:'object/creature/shared_human_male.iff',20:'object/tangible/wearables/shirt/shared_shirt_s01.iff'}),patch('server.character_protocol.customization_ids',return_value={'/shared_owner/index_color_1':4}):
            resolved=hub._resolve(wire)
        for value in (resolved['snapshot']['jtl'],resolved['snapshot']['player']['jtl'],resolved['mutation']['jtl']):
            row=value['ship']['crew'][0]['appearance']
            self.assertEqual(row['shared_template'],'object/creature/shared_human_male.iff')
            self.assertEqual(row['equipment'][0]['shared_template'],'object/tangible/wearables/shirt/shared_shirt_s01.iff')
            self.assertEqual(row['customization'],{'/shared_owner/index_color_1':7})
            self.assertEqual(row['hair_customization'],{'/shared_owner/index_color_1':2})
            self.assertEqual(row['equipment'][0]['customization'],{'/shared_owner/index_color_1':9})

    def test_reconnect_accepts_only_native_owned_ground_recovery_receipt(self):
        result=dict(variables=dict(scene=dict(terrain='terrain/space_tatooine.trn',characterOid='42'),
                    session=dict(source_kind='core3_session_status',character_id='42',location=dict(zone='tatooine',position=[1,2,3]))),zoneStats=dict(sceneReady=True))
        with patch.object(adapter,'invoke',return_value=result),patch.object(adapter,'appearance',return_value={'id':'42'}):
            self.assertEqual(adapter.select_character('tester','42')[1]['id'],'42')
            for changes in ({'character_id':'43'},{'source_kind':'core3_session_logout'},{'location':{'zone':'space_tatooine'}}):
                original=result['variables']['session']
                result['variables']['session']=dict(original,**changes)
                with self.assertRaises(adapter.BackendError):adapter.select_character('tester','42')
                result['variables']['session']=original
            result['variables']['scene']['terrain']='terrain/space_yavin4.trn'
            with self.assertRaises(adapter.BackendError):adapter.select_character('tester','42')

    def test_logout_keeps_original_space_receipt_without_stale_outer_ground_fence(self):
        from server.session_protocol import logout_command
        hub=LiveCombatHub();process=Mock();process.poll.return_value=None
        hub.sessions['tester']=dict(account='tester',character_id='42',id='owned',process=process)
        self.addCleanup(hub.sessions.clear)
        hub._exchange=Mock(return_value={'session_live':True})
        data=dict(character_id='42',session_id='owned',zone='space_tatooine',position=[0,.4,20],building_id='99',cell_index=1,request_id='logout_yacht_01')
        data['session']=logout_command(data)
        hub.request('tester','session',data)
        sent=hub._exchange.call_args.args[1]
        self.assertNotIn('zone',sent)
        self.assertEqual(sent['session'],data['session'])


if __name__ == '__main__':unittest.main()
