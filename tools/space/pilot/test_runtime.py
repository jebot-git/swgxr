#!/usr/bin/env python3
"""Behavioral Lua tests using the real converted conversations and quest bridge.
This is isolated logic validation, not native-server or rendered-client evidence.
Requires development-only lupa==2.6.
"""
import json
import unittest
from pathlib import Path
from lupa import LuaRuntime
ROOT=Path(__file__).resolve().parents[3]
BOOT=r'''
Object={};function Object:new(o) o=o or {};setmetatable(o,{__index=self});return o end
conv_handler=Object:new{}
ScreenPlay=Object:new{};SpaceQuestLogic=ScreenPlay:new{}
function registerScreenPlay() end
function cancelEvent() end
function hasObserver() return false end
function createObserver() end
SPECIES_HUMAN=0;SPECIES_ZABRAK=6;SPECIES_WOOKIEE=4;SPECIES_ITHORIAN=33
FACTIONIMPERIAL=3679112276;FACTIONREBEL=370444368
STORM_SQUADRON=1;BLACK_EPSILON_SQUADRON=2;INQUISITION_SQUADRON=3
CORSEC_SQUADRON=4;RSF_SQUADRON=5;SMUGGLER_SQUADRON=6
HAVOC_SQUADRON=7;VORTEX_SQUADRON=8;CRIMSON_PHOENIX_SQUADRON=9
function CreatureObject(p) return p end;function PlayerObject(p) return p end;function SceneObject(p) return p end
function readScreenPlayData(p,s,k) return p.store[s..":"..k] or "" end
function writeScreenPlayData(p,s,k,v) p.store[s..":"..k]=v end
function isJtlEnabled() return true end
function grantStarterShip(p) p.ship=true end
function getSceneObject(id) return nil end
function giveItem(p,item) local v={template=item,store={}};function v:isPlayerCreature() return true end;function v:getTemplateObjectPath() return self.template end;function v:destroyObjectFromWorld() end;function v:destroyObjectFromDatabase() end;table.insert(p.items,v);return v end
SpaceHelpers={}
function SpaceHelpers:isPilot(p) return self:isImperialPilot(p) or self:isRebelPilot(p) or self:isNeutralPilot(p) end
function SpaceHelpers:isImperialPilot(p) return p.skills.pilot_imperial_navy_novice==true end
function SpaceHelpers:isRebelPilot(p) return p.skills.pilot_rebel_navy_novice==true end
function SpaceHelpers:isNeutralPilot(p) return p.skills.pilot_neutral_novice==true end
function SpaceHelpers:setSquadronType(p,v) p.squadron=v end
function SpaceHelpers:grantSpaceSkill(p,s,paid) p.skills[s]=true;if paid then p.xp=p.xp-100 end end
function SpaceHelpers:hasCertifiedShip(p) return p.ship==true end
function SpaceHelpers:hasCompletedPilotTier(p,f,t)
 for _,skill in ipairs({'droid','procedures','starships','weapons'}) do
  if not p.skills['pilot_'..f..'_'..skill..'_0'..t] then return false end
 end;return true
end
function SpaceHelpers:isSpaceQuestActive(p,t,n) return p.active[t..':'..n]==true end
function SpaceHelpers:isSpaceQuestComplete(p,t,n) return p.won[t..':'..n]==true end
function SpaceHelpers:clearSpaceQuest(p,t,n) p.active[t..':'..n]=nil;p.won[t..':'..n]=nil end
function SpaceHelpers:spaceCreditReward(p,v) p.credits=p.credits+v end
function SpaceHelpers:activateSpaceQuest(p,npc,t,n) p.active[t..':'..n]=true end
function SpaceHelpers:completeSpaceQuest(p,t,n) p.active[t..':'..n]=nil;p.won[t..':'..n]=true end
function SpaceHelpers:failSpaceQuest(p,t,n) p.active[t..':'..n]=nil;p.won[t..':'..n]=nil end
function LuaSkillManager() return {fulfillsSkillPrerequisitesAndXp=function(_,p,s) return p.xp>=100 end} end
Player=Object:new{}
function Player:isPlayerCreature() return true end
function Player:getObjectID() return 1 end
function getQuestStatus() return "" end
function Player:getPlayerObject() return self end
function Player:getSquadronType() return self.squadron end
function Player:getPilotTier() return self.tier end
function Player:incrementPilotTier() self.tier=self.tier+1 end
function Player:hasSkill(s) return self.skills[s]==true end
function Player:isInCombat() return false end
function Player:getFaction() return self.faction end
function Player:getFactionStanding(f) return self.standing[f] or 0 end
function Player:increaseFactionStanding(f,v) self.standing[f]=(self.standing[f] or 0)+v end
function Player:getSpecies() return self.species end
function Player:getGender() return 0 end
function Player:hasCertifiedShip() return self.ship end
function Player:getSlottedObject() return self end
function Player:getContainerObject(i) return self.items[i+1] end
function Player:getContainerObjectsSize() return #self.items end
function Player:getContainerVolumeLimit() return self.capacity end
function Player:sendSystemMessage(s) self.message=s end
function Player:doAnimation() end
function Player:playMusicMessage() end
function Player:getCustomObjectName() return 'Fixture' end
function newPlayer(faction)
 return Player:new{store={},skills={},active={},won={},standing={},items={},capacity=80,credits=0,xp=0,squadron=0,tier=0,faction=faction or 0,species=0,ship=false}
end
function clone(v,seen)
 if type(v)~='table' then return v end
 seen=seen or {};if seen[v] then return seen[v] end
 local out={};seen[v]=out;for k,value in pairs(v) do out[k]=clone(value,seen) end
 return setmetatable(out,getmetatable(v))
end
function context(name) return setmetatable({npc=newPlayer(),view={responses={}},factionRewards={}},{__index=_G[name]}) end
function step(name,p,response)
 local c=context(name)
 if response then c:OnNpcConversationResponse(c.npc,name,p,response) else c:OnStartNpcConversation(c.npc,p) end
 return c.view
end
QuestStub=Object:new{}
function QuestStub:startQuest(p,npc) SpaceHelpers:activateSpaceQuest(p,npc,self.questType,self.questName) end
function QuestStub:completeQuest(p) SpaceHelpers:completeSpaceQuest(p,self.questType,self.questName) end
function QuestStub:failQuest(p) SpaceHelpers:failSpaceQuest(p,self.questType,self.questName) end
function QuestStub:resetQuest(p) self:failQuest(p) end
'''

class PilotRuntimeTests(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True);self.lua.execute(BOOT);self.g=self.lua.globals()
        for file in ('source_runtime','quest_runtime'):
            self.lua.execute((ROOT/'server/jtl/pilot'/(file+'.lua')).read_text())
        for name in set(json.loads((ROOT/'server/jtl/pilot/trainers.json').read_text()).values()):
            self.lua.execute((ROOT/'runtime/server/pilot-source'/(name+'.lua')).read_text())
        self.lua.execute("""
local nativePut=PilotSource.put
function PilotSource.put(p,key,value)
 if type(value)=='table' and value.template then value=value.template end
 nativePut(p,key,value)
end
PilotSource.api['utils.getObjIdScriptVar']=function(_,p,key)
 local value=PilotSource.get(p,'script.'..key)
 for _,item in ipairs(p.items) do if item.template==value then return item end end
end
""")
        from compile_quests import CLASSES
        for name in set(CLASSES.values()):self.g[name]=self.g.QuestStub
        self.lua.execute((ROOT/'runtime/server/pilot-source/quests.lua').read_text())

    def test_all_nine_recruitment_paths_reach_real_mission(self):
        entries=['tatooine_imperial_trainer_1','naboo_imperial_trainer_1','corellia_imperial_trainer_1',
                 'tatooine_rebel_trainer_1','naboo_rebel_trainer_1','corellia_rebel_trainer_1',
                 'tatooine_privateer_trainer_1','naboo_privateer_trainer_1','corellia_privateer_trainer']
        for name in entries:
            with self.subTest(name=name):
                faction=self.g.FACTIONIMPERIAL if '_imperial_' in name else self.g.FACTIONREBEL if '_rebel_' in name else 0
                p=self.g.newPlayer(faction)
                # Freelance enlistment is through the existing faction coordinator.
                if '_privateer_' in name:
                    p.skills['pilot_neutral_novice']=True;p.ship=True
                    self.g.PilotSource.api['space_flags.setSpaceTrack'](None,p,name.split('_')[0]+'Privateer')
                queue=[(p,None,[])];found=None;visited=set()
                while queue and len(visited)<600:
                    p,response,path=queue.pop(0);view=self.g.step(name,p,response)
                    active=list(p.active.keys())
                    if active:found=(active,path);break
                    state=(view.message,tuple(sorted(p.store.items())),tuple(sorted(p.skills.keys())),p.ship)
                    if state in visited:continue
                    visited.add(state)
                    for i,choice in sorted(view.responses.items()):
                        queue.append((self.g.clone(p),choice.split(':')[-1],path+[choice]))
                self.assertIsNotNone(found,(name,len(visited)))

                self.assertTrue(all(k in self.g.PilotQuests.instances for k in found[0]))

    def test_reward_once_and_capacity_retry(self):
        p=self.g.newPlayer();p.won['destroy:tatooine_imperial_2']=True
        reward=self.g.PilotQuests.reward
        self.assertTrue(reward(p,'destroy','tatooine_imperial_2',200,None))
        self.assertFalse(reward(p,'destroy','tatooine_imperial_2',200,None));self.assertEqual(p.credits,200)
        self.assertFalse(reward(p,'escort','tatooine_imperial_3',500,None))
        p.won['escort:tatooine_imperial_3']=True;p.capacity=0
        ok=self.lua.eval('function(p) return pcall(PilotQuests.reward,p,"escort","tatooine_imperial_3",500,"reward.iff") end')(p)[0]
        self.assertFalse(ok);self.assertEqual(p.credits,200)
        p.capacity=80;self.assertTrue(reward(p,'escort','tatooine_imperial_3',500,'reward.iff'))
        self.assertEqual(p.credits,700);self.assertEqual(len(p["items"]),1)

    def test_recursive_completion_failure_and_retry(self):
        p=self.g.newPlayer();q=self.g.PilotQuests;patrol='patrol:tatooine_imperial_1';child='destroy_surpriseattack:tatooine_imperial_1'
        p.won[patrol]=True
        self.assertFalse(q.query(p,'hasWonQuestRecursive','patrol','tatooine_imperial_1'))
        p.active[child]=True;q.instances[child].failQuest(q.instances[child],p,True)
        self.assertTrue(q.query(p,'hasFailedQuestRecursive','patrol','tatooine_imperial_1'))
        q.clear(p,'destroy_surpriseattack','tatooine_imperial_1')
        self.assertFalse(q.query(p,'hasFailedQuestRecursive','patrol','tatooine_imperial_1'))
        p.won[child]=True;self.assertTrue(q.query(p,'hasWonQuestRecursive','patrol','tatooine_imperial_1'))

    def test_hierarchical_flags_and_legacy_reward_receipts(self):
        p=self.g.newPlayer();api=self.g.PilotSource.api
        api['space_flags.setSpaceTrack'](None,p,'tatooineImperial')
        api['space_flags.setSpaceFlag'](None,p,'ss.findingAgent',True)
        self.assertTrue(api['space_flags.hasSpaceFlag'](None,p,'ss'))
        self.assertEqual(api['space_flags.getIntSpaceFlag'](None,p,'ss.findingAgent'),1)
        self.assertTrue(api['space_flags.getBooleanSpaceFlag'](None,p,'ss.findingAgent'))
        api['space_flags.removeSpaceFlag'](None,p,'ss')
        self.assertFalse(api['space_flags.hasSpaceFlag'](None,p,'ss.findingAgent'))
        self.lua.execute('function getQuestStatus(key) if key=="1corellia_rebel_4:reward" then return "1" end return "" end')
        p.won['assassinate:corellia_rebel_4']=True
        self.assertFalse(self.g.PilotQuests.reward(p,'assassinate','corellia_rebel_4',10000,None))
        self.assertEqual(p.credits,0)

    def test_tier_checks_use_native_faction_skill_names(self):
        p=self.g.newPlayer(self.g.FACTIONIMPERIAL);p.skills['pilot_imperial_navy_novice']=True
        for skill in ('droid','procedures','starships','weapons'):p.skills['pilot_imperial_navy_'+skill+'_01']=True
        self.assertTrue(self.g.PilotSource.api['space_flags.hasCompletedTierOne'](None,p))
        p.skills['pilot_imperial_navy_droid_01']=None
        self.assertFalse(self.g.PilotSource.api['space_flags.hasCompletedTierOne'](None,p))

if __name__=='__main__':unittest.main()
