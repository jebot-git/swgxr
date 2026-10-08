import unittest
from unittest.mock import Mock
from server.combat_loadout_protocol import validate
from server.live_combat import LiveCombatHub
from server.remote_gateway import POST

class Loadouts(unittest.TestCase):
    def proposal(self,**changes):
        return dict(family='pistols',slots=['lethal_shot','','',''],ultimate='last_ditch',revision=2,**changes)
    def test_exact_shape_and_maximums(self):
        proposal=self.proposal();self.assertEqual(validate(proposal),proposal)
        for changed in (dict(slots=['a']*5),dict(slots=['a']*3),dict(slots=['a','a','','']),dict(ultimate='lethal_shot'),dict(revision=True),dict(revision=-1),dict(family='made_up'),dict(ultimate=[]),dict(slots=[None,'','','']),dict(extra=True)):
            with self.subTest(changed=changed),self.assertRaises(ValueError):validate(dict(proposal,**changed))
    def test_transport_preserves_owned_request(self):
        hub=LiveCombatHub();hub.sessions['tester']={'account':'tester','character_id':'42','id':'owned'}
        hub._exchange=Mock(return_value={'session_live':True})
        self.addCleanup(hub.sessions.clear)
        data=dict(character_id='42',session_id='owned',item_id='99',loadout=self.proposal())
        hub.request('tester','loadout',data)
        command=hub._exchange.call_args.args[1]
        self.assertEqual(command['loadout'],self.proposal());self.assertEqual(command['item_id'],'99')
        for changes in (dict(item_id='../wrong'),dict(session_id='foreign'),dict(character_id='43'),dict(loadout=None)):
            with self.subTest(changes=changes),self.assertRaises(ValueError):hub.request('tester','loadout',dict(data,**changes))
        self.assertEqual(hub._exchange.call_count,1)
    def test_gateway_route_is_exposed_through_existing_auth(self):
        self.assertIn('/combat/session/loadout',POST)

if __name__=='__main__':unittest.main()
