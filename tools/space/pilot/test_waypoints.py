#!/usr/bin/env python3
"""Run real patrol/objective Lua with modeled engine callbacks, not live flight."""
import unittest
from pathlib import Path
from lupa import LuaRuntime
from test_runtime import BOOT, ROOT
from test_objectives import WORLD

WAYPOINTS = r'''
WAYPOINT_SPACE=7;WAYPOINTQUESTTASK=8;ZONESWITCHED=9
function cancelEvent(owner,method,p)
 for i=#events,1,-1 do if events[i].owner==owner and events[i].method==method then table.remove(events,i) end end
end
function getHashCode(v) return v end
function LuaShipObject(p) return p end
function Ship:getObjectName() return 'player_z95' end
function Ship:isPlayerShip() return true end
function Ship:getPilot() return self.pilot end
local spawn=spawnShipAgent
function spawnShipAgent(template,zone,x,z,y)
 local s=spawn(template,zone,x,z,y);s.zone=zone;return s
end
function SpaceHelpers:isSpaceQuestTaskComplete(p,t,n,task) return p.tasks[task]=='complete' end
function SpaceHelpers:sendQuestUpdate() end
function SpaceHelpers:sendQuestProgess() end
local statuses={}
function setQuestStatus(k,v) statuses[k]=v end
function getQuestStatus(k) return statuses[k] or '' end
function Player:addWaypoint(zone,name,desc,x,z,y,color,active,notify,special)
 nextId=nextId+1
 self.waypoint={id=nextId,zone=zone,name=name,position={x,z,y},active=active}
 return nextId
end
function SpaceHelpers:clearQuestWaypoint(p,class)
 if p.waypoint and p.waypoint.id==statuses[p.id..':'..class..':waypointID'] then p.waypoint=nil end
 statuses[p.id..':'..class..':waypointID']=nil
end
function enter(p,q,index)
 local area=Ship:new{id=1000+index};writeData(area.id..':'..q.className,index)
 return q:notifyEnteredQuestArea(area,p.ship)
end
function patrol(key)
 local p=newPlayer();p.id=1;p.zone='tatooine';p.tasks={};p.missions={}
 p.ship=spawnShipAgent('crafted_z95','space_tatooine',0,0,0);p.ship.pilot=p;objects[1]=p
 local q=PilotQuests.instances[key];q:startQuest(p,nil);return p,q
end
'''

class WaypointTests(unittest.TestCase):
 def setUp(self):
  self.lua=LuaRuntime(unpack_returned_tuples=True)
  self.lua.execute(BOOT);self.lua.execute(WORLD);self.lua.execute(WAYPOINTS)
  self.lua.execute('function require() end')
  base=ROOT/'vendor/Core3/MMOCoreORB/bin/scripts/screenplays/space'
  for name in ('SpaceQuestLogic','SpacePatrolScreenplay','SpaceDutyPatrolScreenplay'):
   self.lua.execute((base/(name+'.lua')).read_text())
  for name in ('source_runtime','quest_runtime','objective_runtime'):
   self.lua.execute((ROOT/'server/jtl/pilot'/(name+'.lua')).read_text())
  self.lua.execute('realBind=PilotQuests.bind;PilotQuests.bind=function() end')
  self.lua.execute((ROOT/'runtime/server/pilot-source/quests.lua').read_text())
  self.lua.execute('PilotQuests.bind=realBind;for k,q in pairs(PilotQuests.definitions) do if q.questType=="patrol" then PilotQuests.bind(k,SpacePatrolScreenplay) end end')

 def test_akal_sector_entry_order_and_three_dimensional_coordinates(self):
  self.lua.execute('''
local p,q=patrol('patrol:tatooine_imperial_1');assert(not p.waypoint)
q:enteredZone(p,nil,'space_naboo');assert(not p.waypoint)
p.zone=q.questZone;q:enteredZone(p,nil,q.questZone)
local point=q.patrolPoints[1];local first=p.waypoint.id
assert(p.waypoint.zone==q.questZone)
assert(p.waypoint.position[1]==point.x and p.waypoint.position[2]==point.z and p.waypoint.position[3]==point.y)
enter(p,q,2);assert(p.waypoint.id==first,'Out-of-order waypoint advanced the patrol')
enter(p,q,1);assert(p.waypoint.id~=first)
point=q.patrolPoints[2]
assert(p.waypoint.position[1]==point.x and p.waypoint.position[2]==point.z and p.waypoint.position[3]==point.y)
enter(p,q,2)
local found=false
for _,event in ipairs(events) do if event.owner=='destroy_surpriseattack_tatooine_imperial_1' and event.method=='startQuest' then found=true end end
assert(found,'Akal encounter not scheduled after its second waypoint')
q:completeQuest(p,'false')
local scheduled=0
for _,event in ipairs(events) do if event.owner=='destroy_surpriseattack_tatooine_imperial_1' and event.method=='startQuest' then scheduled=scheduled+1 end end
assert(scheduled==1,'Patrol completion cancelled the pending Akal encounter')
q:resetQuest(p);assert(not p.waypoint)
''')

 def test_last_point_completes_single_stop_privateer_patrol_and_schedules_followup(self):
  self.lua.execute('''
local p,q=patrol('patrol:tat_priv_quest_trans');p.zone=q.questZone;q:enteredZone(p,nil,q.questZone)
assert(p.waypoint and #q.patrolPoints==1)
enter(p,q,1);assert(not p.waypoint)
assert(p.won['patrol:tat_priv_quest_trans'],'Final waypoint disappeared without completing the patrol')
local count=0
for _,event in ipairs(events) do if event.owner=='assassinate_tat_priv_quest_trans' and event.method=='startQuest' then count=count+1 end end
assert(count==1,'Privateer follow-on not scheduled exactly once')
enter(p,q,1)
local again=0
for _,event in ipairs(events) do if event.owner=='assassinate_tat_priv_quest_trans' and event.method=='startQuest' then again=again+1 end end
assert(again==1,'Repeated area entry restarted the follow-on')
''')

 def test_delivery_replaces_waypoint_and_completion_clears_it(self):
  self.lua.execute('''
local p,q=fixture('delivery');q.objectivePoints={{x=13,z=47,y=-29},{x=900,z=-73,y=115}}
p.ship.x=13;p.ship.z=47;p.ship.y=-29;tick(p,q)
local first=p.waypoint.id;assert(p.waypoint.position[2]==47 and p.waypoint.position[3]==-29)
q:dockedShip(p,findShip('pickup'))
assert(p.waypoint.id~=first and p.waypoint.position[1]==900 and p.waypoint.position[2]==-73 and p.waypoint.position[3]==115)
p.ship.x=900;p.ship.z=-73;p.ship.y=115;tick(p,q);q:dockedShip(p,findShip('recipient'))
assert(p.won['delivery:test'] and not p.waypoint)
''')

 def test_delivery_can_cross_sectors_without_spawning_at_wrong_coordinates(self):
  self.lua.execute('''
local p,q=fixture('delivery')
q.objectivePoints[1].zoneName='space_tatooine';q.objectivePoints[2].zoneName='space_naboo'
tick(p,q);q:dockedShip(p,findShip('pickup'))
assert(p.waypoint.zone=='space_naboo' and p.tasks[3]=='active')
p.ship.x=1000;tick(p,q)
assert(p.active['delivery:test'] and not findShip('recipient'),'Delivery spawned in pickup sector')
p.zone='space_corellia';tick(p,q);assert(p.active['delivery:test'])
p.zone='space_naboo';tick(p,q)
assert(findShip('recipient') and p.tasks[3]=='complete' and p.tasks[4]=='active')
assert(p.tasks[1]=='complete','Delivery reactivated the pickup task on sector arrival')
q:dockedShip(p,findShip('recipient'));assert(p.won['delivery:test'] and not p.waypoint)
''')

 def test_all_original_cross_sector_deliveries(self):
  self.lua.execute('''
local count=0
for key,definition in pairs(PilotQuests.definitions) do
 if definition.questType=='delivery' and definition.objectivePoints[1].zoneName~=definition.objectivePoints[2].zoneName then
  count=count+1
  local p=fixture('delivery')
  local q=PilotObjectiveQuest:new(definition);q.sideQuest=false;q.attackShips={}
  local a,b=q.objectivePoints[1],q.objectivePoints[2]
  p.zone=a.zoneName;p.ship.x=a.x;p.ship.z=a.z;p.ship.y=a.y;q:startQuest(p,nil);tick(p,q)
  q:dockedShip(p,objects[q:get(p,'target')]);assert(p.waypoint.zone==b.zoneName,key)
  p.zone=b.zoneName;p.ship.x=b.x;p.ship.z=b.z;p.ship.y=b.y;tick(p,q)
  local recipient=objects[q:get(p,'target')];assert(recipient and recipient.zone==b.zoneName,key)
  q:dockedShip(p,recipient);assert(p.won[key] and not p.waypoint,key)
 end
end
assert(count==3,'Original cross-sector delivery coverage changed')
''')

 def test_all_original_patrols_that_finish_at_the_last_point(self):
  self.lua.execute('''
local count=0
for key,definition in pairs(PilotQuests.definitions) do
 if definition.questType=='patrol' and (not definition.sideQuest or definition.sideQuestSplitType~=4 or definition.sideQuestPatrolStart>=#definition.patrolPoints) then
  count=count+1
  local p,q=patrol(key);p.zone=q.questZone;q:enteredZone(p,nil,q.questZone)
  for i=1,#q.patrolPoints do
   assert(p.active[key] and p.waypoint,key)
   enter(p,q,i)
  end
  assert(p.won[key] and not p.waypoint,key)
 end
end
assert(count==3,'Original final-point patrol coverage changed')
''')

if __name__=='__main__':unittest.main()
