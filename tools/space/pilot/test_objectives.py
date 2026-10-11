#!/usr/bin/env python3
"""Exercise battle/survival/delivery lifecycle with a deterministic Lua engine harness.
This validates event handling, not native ship physics or combat damage.
"""
import unittest
from pathlib import Path
from lupa import LuaRuntime
from test_runtime import BOOT, ROOT
WORLD=r'''
LOGGEDIN=1;SHIPDOCKED=2;SHIPDESTROYED=3
local data={};local vectors={};objects={};clock=100;events={};nextId=10
function readData(k) return data[k] or 0 end
function writeData(k,v) data[k]=v end
function deleteData(k) data[k]=nil end
function readStringVectorSharedMemory(k) return vectors[k] end
function writeStringVectorSharedMemory(k,v) vectors[k]=v end
function getTimestamp() return clock end
function createEvent(ms,owner,method,p,arg) table.insert(events,{owner=owner,method=method,arg=arg}) end
function dropObserver() end
function getSceneObject(id) return objects[id] end
function ShipObject(p) return p end;function ShipAiAgent(p) return p end
function setQuestStatus() end
function getRandomNumber(a,b) return a end
function SpaceHelpers:isInYacht() return false end
function SpaceHelpers:clearQuestWaypoint() end
function SpaceHelpers:completeSpaceQuestTask(p,t,n,task) p.tasks[task]='complete' end
function SpaceHelpers:activateSpaceQuestTask(p,t,n,task) p.tasks[task]='active' end
function SpaceHelpers:isSpaceQuestTaskActive(p,t,n,task) return p.tasks[task]=='active' end
function Player:getRootParent() return self.ship end
function Player:getZoneName() return self.zone end
function Player:isPilotingShip() return true end
function Player:getObjectID() return self.id end
function Player:addWaypoint() return 100 end
function Player:addSpaceMissionObject(id) self.missions[id]=true end
function Player:removeSpaceMissionObject(id) self.missions[id]=nil end
Ship=Object:new{}
function Ship:getObjectID() return self.id end
function Ship:getPositionX() return self.x end
function Ship:getPositionY() return self.y end
function Ship:getPositionZ() return self.z end
function Ship:isShipObject() return true end
function Ship:isShipDestroyed() return false end
function Ship:isShipDisabled() return false end
function Ship:getShipFactionHash() return 1 end
function Ship:removeSpaceFactionEnemy() end
function Ship:addSpaceFactionAlly() end
function Ship:removeSpaceFactionAlly() end
function Ship:addSpaceFactionEnemy() end
function Ship:setMissionOwner(p) self.owner=p end
function Ship:setMinimumGuardPatrol() end
function Ship:setMaximumGuardPatrol() end
function Ship:setGuardPatrol() end
function Ship:engageShipTarget(target) self.target=target end
function Ship:destroyObjectFromWorld() objects[self.id]=nil end
function spawnShipAgent(template,zone,x,z,y)
 nextId=nextId+1;local s=Ship:new{id=nextId,x=x,y=y,z=z,template=template};objects[s.id]=s;return s
end
function fixture(kind)
 local p=newPlayer();p.id=1;p.zone='space_tatooine';p.tasks={};p.missions={};p.ship=spawnShipAgent('crafted_z95',p.zone,0,0,0);objects[1]=p
 local q=PilotObjectiveQuest:new{className='test_'..kind,questType=kind,questName='test',questZone=p.zone,
  sourceRows={{allyArrivalDelay='0',enemyArrivalDelay='0',attackPeriod='5',delayToFirstAttack='0',totalTransmissionTime='10',transmissionStartDelay='2',pickupShip='pickup',deliveryShip='recipient'}},
  objectivePoints={{x=0,z=0,y=0}},allies={'ally'},enemies={'enemy1','enemy2'},attackShips={{'raider'}}}
 if kind=='delivery' then q.objectivePoints[2]={x=1000,z=0,y=0} end
 q:startQuest(p,nil);return p,q
end
function tick(p,q) q:tick(p,tostring(q:get(p,'generation'))) end
function findShip(template) for _,s in pairs(objects) do if s.template==template then return s end end end
'''
class ObjectiveTests(unittest.TestCase):
 def setUp(self):
  self.lua=LuaRuntime(unpack_returned_tuples=True);self.lua.execute(BOOT);self.lua.execute(WORLD)
  self.lua.execute((ROOT/'server/jtl/pilot/objective_runtime.lua').read_text());self.g=self.lua.globals()
 def test_battle_requires_all_enemies_and_fails_on_allied_loss(self):
  self.lua.execute('''
local p,q=fixture('space_battle');q.sourceRows[1].allyArrivalDelay='';q.sourceRows[1].enemyArrivalDelay='';tick(p,q)
assert(p.active['space_battle:test'] and not p.won['space_battle:test'])
q:destroyedShip(findShip('enemy1'));assert(not p.won['space_battle:test'])
q:destroyedShip(findShip('enemy2'));assert(p.won['space_battle:test']);assert(next(p.missions)==nil)
local p,q=fixture('space_battle');tick(p,q);q:destroyedShip(findShip('ally'))
assert(not p.active['space_battle:test'] and not p.won['space_battle:test'])
''')
 def test_survival_timer_distance_and_stale_events(self):
  self.lua.execute('''
local p,q=fixture('survival');tick(p,q);assert(findShip('raider'))
clock=111;tick(p,q);assert(not p.won['survival:test'])
clock=112;tick(p,q);assert(p.won['survival:test'])
local p,q=fixture('survival');tick(p,q);p.ship.x=2001;tick(p,q);assert(not p.active['survival:test'])
local generation=q:get(p,'generation');q:resetQuest(p);q:startQuest(p,nil)
q:tick(p,tostring(generation));assert(q:get(p,'arrived')==0)
''')
 def test_delivery_requires_two_distinct_permitted_targets(self):
  self.lua.execute('''
local p,q=fixture('delivery');tick(p,q);local pickup=findShip('pickup')
local stranger=spawnShipAgent('unrelated',p.zone,0,0,0)
q:dockedShip(p,stranger);assert(q:get(p,'stage')==1)
p.tasks[2]='complete';q:dockedShip(p,pickup);assert(q:get(p,'stage')==1)
p.tasks[2]='active';q:dockedShip(p,pickup);assert(q:get(p,'stage')==2 and not p.won['delivery:test'])
q:dockedShip(p,pickup);assert(not p.won['delivery:test'])
p.ship.x=1000;tick(p,q);local delivery=findShip('recipient');assert(delivery.id~=pickup.id)
q:dockedShip(p,delivery);assert(p.won['delivery:test']);assert(next(p.missions)==nil)
assert(readScreenPlayData(p,'swgxr_docking',tostring(delivery.id))=='')
''')
 def test_no_pickup_and_destroyed_recipient(self):
  self.lua.execute('''
local p,q=fixture('delivery_no_pickup');tick(p,q);q:dockedShip(p,findShip('recipient'));assert(p.won['delivery_no_pickup:test'])
local p,q=fixture('delivery');tick(p,q);q:destroyedShip(findShip('pickup'));assert(not p.active['delivery:test'] and not p.won['delivery:test'])
''')
if __name__=='__main__':unittest.main()
