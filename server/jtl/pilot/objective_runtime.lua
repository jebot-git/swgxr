-- Objectives missing from upstream Core3: original battle, transmission and
-- delivery tables, native ships/combat/docking, and native journal completion.
local roleIds={ally=1,enemy=2,attacker=3,target=4}
local roleNames={"ally","enemy","attacker","target"}
PilotObjectiveQuest = SpaceQuestLogic:new { className="PilotObjectiveQuest" }
registerScreenPlay("PilotObjectiveQuest",false)
function PilotObjectiveQuest:start() end
function PilotObjectiveQuest:key(p,s) return SceneObject(p):getObjectID()..":"..self.className..":"..s end
function PilotObjectiveQuest:get(p,s) return readData(self:key(p,s)) end
function PilotObjectiveQuest:set(p,s,v) writeData(self:key(p,s),v) end
function PilotObjectiveQuest:active(p) return p~=nil and SpaceHelpers:isSpaceQuestActive(p,self.questType,self.questName) end
function PilotObjectiveQuest:ship(p)
 local ship=SceneObject(p):getRootParent()
 if ship==nil or not SceneObject(ship):isShipObject() or SpaceHelpers:isInYacht(p) or not CreatureObject(p):isPilotingShip() then return nil end
 if ShipObject(ship):isShipDestroyed() or ShipObject(ship):isShipDisabled() then return nil end
 return ship
end
function PilotObjectiveQuest:task(p,n,complete)
 if complete then SpaceHelpers:completeSpaceQuestTask(p,self.questType,self.questName,n,false)
 else SpaceHelpers:activateSpaceQuestTask(p,self.questType,self.questName,n,true) end
end
function PilotObjectiveQuest:startQuest(p,npc)
 if p==nil then return end
 if npc=="" then npc=nil end
 SpaceHelpers:activateSpaceQuest(p,npc,self.questType,self.questName,true)
 if not self:active(p) then return end
 local generation=self:get(p,"generation")+1
 self:set(p,"generation",generation);self:set(p,"stage",1);self:set(p,"arrived",0);self:set(p,"started",0)
 self:set(p,"phaseTime",0);self:set(p,"wave",0);self:set(p,"target",0);self:set(p,"entered",0)
 self:set(p,"alliesSpawned",0);self:set(p,"enemiesSpawned",0)
 writeStringVectorSharedMemory(self:key(p,"ships"),{})
 createObserver(SHIPDOCKED,self.className,"dockedShip",p)
 createEvent(1000,self.className,"tick",p,tostring(generation))
end
function PilotObjectiveQuest:waypoint(p)
 SpaceHelpers:clearQuestWaypoint(p,self.className)
 local point=self.objectivePoints[self:get(p,"stage")]
 local ghost=CreatureObject(p):getPlayerObject()
 local waypoint=PlayerObject(ghost):addWaypoint(point.zoneName or self.questZone,"@spacequest/"..self.questType.."/"..self.questName..":title","",point.x,point.z,point.y,WAYPOINT_SPACE,true,true,WAYPOINTQUESTTASK)
 setQuestStatus(SceneObject(p):getObjectID()..":"..self.className..":waypointID",waypoint)
end
function PilotObjectiveQuest:spawn(p,types,role,target)
 local point=self.objectivePoints[self:get(p,"stage")]
 local ids=readStringVectorSharedMemory(self:key(p,"ships")) or {}
 local spawned={}
 for i,template in ipairs(types) do
  local offset=role=="ally" and -500 or role=="target" and 0 or 500
  local ship=spawnShipAgent(template,point.zoneName or self.questZone,point.x+offset,point.z,point.y+i*35)
  if ship==nil then self:failQuest(p,"true");return nil end
  ShipAiAgent(ship):setMissionOwner(p)
  local playerShip=self:ship(p)
  if playerShip then
   local faction=ShipObject(playerShip):getShipFactionHash()
   if role=="ally" or role=="target" then
    ShipAiAgent(ship):removeSpaceFactionEnemy(faction);ShipAiAgent(ship):addSpaceFactionAlly(faction)
   else ShipAiAgent(ship):removeSpaceFactionAlly(faction);ShipAiAgent(ship):addSpaceFactionEnemy(faction) end
  end
  ShipAiAgent(ship):setMinimumGuardPatrol(0);ShipAiAgent(ship):setMaximumGuardPatrol(role=="target" and 25 or 500);ShipAiAgent(ship):setGuardPatrol()
  local id=SceneObject(ship):getObjectID()
  writeData(id..":"..self.className..":owner",SceneObject(p):getObjectID())
  writeData(id..":"..self.className..":role",roleIds[role])
  createObserver(SHIPDESTROYED,self.className,"destroyedShip",ship)
  CreatureObject(p):addSpaceMissionObject(id,true)
  table.insert(ids,tostring(id));table.insert(spawned,ship)
  writeStringVectorSharedMemory(self:key(p,"ships"),ids)
  if target then ShipAiAgent(ship):engageShipTarget(target) end
 end
 writeStringVectorSharedMemory(self:key(p,"ships"),ids)
 self:set(p,role.."Count",self:get(p,role.."Count")+#spawned)
 return spawned
end
function PilotObjectiveQuest:destroyedShip(ship)
 if ship==nil then return 1 end
 local id=SceneObject(ship):getObjectID();local p=getSceneObject(readData(id..":"..self.className..":owner"))
 local role=roleNames[readData(id..":"..self.className..":role")]
 if p==nil or role==nil or not self:active(p) then return 1 end
 self:set(p,role.."Count",math.max(0,self:get(p,role.."Count")-1))
 if role=="target" or (role=="ally" and self:get(p,"allyCount")==0) then self:failQuest(p,"true")
 elseif role=="enemy" and self.questType=="space_battle" and self:get(p,"enemyCount")==0 then self:completeQuest(p,"true") end
 return 1
end
function PilotObjectiveQuest:attackWave(p)
 if #self.attackShips==0 then return end
 local wave=self:get(p,"wave")+1;self:set(p,"wave",wave)
 local row=self.sourceRows[1];local index=(wave-1)%#self.attackShips+1
 if row.attackListType=="random" then index=getRandomNumber(1,#self.attackShips) end
 self:spawn(p,self.attackShips[index],"attacker",self:ship(p))
end
function PilotObjectiveQuest:tick(p,generation)
 if not self:active(p) or tonumber(generation)~=self:get(p,"generation") then return end
 local ship=self:ship(p)
 local stage=self:get(p,"stage");local point=self.objectivePoints[stage]
 local inZone=SceneObject(p):getZoneName()==(point.zoneName or self.questZone)
 if self:get(p,"entered")==1 and (not inZone or ship==nil) then self:failQuest(p,"true");return end
 if not inZone or ship==nil then createEvent(1000,self.className,"tick",p,generation);return end
 if self:get(p,"entered")==0 then
  self:set(p,"entered",1)
  if stage==1 then self:task(p,0,true);self:task(p,1,false) end
  self:waypoint(p)
 end
 local dx=SceneObject(ship):getPositionX()-point.x
 local dy=SceneObject(ship):getPositionY()-point.y
 local dz=SceneObject(ship):getPositionZ()-point.z
 local distance=math.sqrt(dx*dx+dy*dy+dz*dz)
 local row=self.sourceRows[1];local now=getTimestamp()
 if self:get(p,"arrived")==0 and distance<=500 then
  self:set(p,"arrived",1);self:set(p,"phaseTime",now)
  self:task(p,stage==2 and 3 or 1,true);self:task(p,stage==2 and 4 or 2,false)
  if string.find(self.questType,"delivery",1,true) then
   local template=(self.questType=="delivery" and stage==1) and row.pickupShip or row.deliveryShip
   local targets=self:spawn(p,{template},"target")
   if not targets then return end
   local id=SceneObject(targets[1]):getObjectID();self:set(p,"target",id)
   writeScreenPlayData(p,"swgxr_docking",tostring(id),"spacequest/"..self.questType.."/"..self.questName)
   writeScreenPlayData(p,"swgxr_docking_task",tostring(id),tostring(stage==2 and 4 or 2))
  end
 end
 if self:get(p,"arrived")==1 then
  local elapsed=now-self:get(p,"phaseTime")
  if self.questType=="space_battle" then
   if self:get(p,"alliesSpawned")==0 and elapsed>=(tonumber(row.allyArrivalDelay) or 0) then
    self:set(p,"alliesSpawned",1);if not self:spawn(p,self.allies,"ally") then return end
   end
   if self:get(p,"enemiesSpawned")==0 and elapsed>=(tonumber(row.enemyArrivalDelay) or 0) then
    self:set(p,"enemiesSpawned",1);local enemies=self:spawn(p,self.enemies,"enemy",ship)
    if not enemies then return end
    for _,id in ipairs(readStringVectorSharedMemory(self:key(p,"ships")) or {}) do
     local ally=getSceneObject(tonumber(id))
     if ally and readData(id..":"..self.className..":role")==roleIds.ally then ShipAiAgent(ally):engageShipTarget(enemies[1]) end
    end
   end
  else
   local period=math.max(1,tonumber(row.attackPeriod) or 90)
   local first=tonumber(row.delayToFirstAttack) or period
   if elapsed>=first+self:get(p,"wave")*period then self:attackWave(p) end
   if self.questType=="survival" then
    if distance>2000 then self:failQuest(p,"true");return end
    local duration=(tonumber(row.totalTransmissionTime) or 0)+(tonumber(row.transmissionStartDelay) or 0)
    if duration>0 and elapsed>=duration then self:completeQuest(p,"true");return end
   end
  end
 end
 if self:active(p) then createEvent(1000,self.className,"tick",p,generation) end
end
function PilotObjectiveQuest:dockedShip(p,target)
 if not self:active(p) or target==nil or SceneObject(target):getObjectID()~=self:get(p,"target") then return 0 end
 local id=SceneObject(target):getObjectID();local stage=self:get(p,"stage")
 if not SpaceHelpers:isSpaceQuestTaskActive(p,self.questType,self.questName,stage==2 and 4 or 2) then return 0 end
 dropObserver(SHIPDESTROYED,self.className,"destroyedShip",target)
 CreatureObject(p):removeSpaceMissionObject(id,true)
 writeScreenPlayData(p,"swgxr_docking",tostring(id),"");writeScreenPlayData(p,"swgxr_docking_task",tostring(id),"")
 self:set(p,"target",0);self:task(p,stage==2 and 4 or 2,true)
 -- Pickup cannot satisfy delivery; the next rendezvous has a distinct ship ID.
 if stage<#self.objectivePoints then
  self:set(p,"stage",stage+1);self:set(p,"arrived",0);self:set(p,"wave",0)
  -- Some original deliveries cross sectors. Wait for the next rendezvous's
  -- sector instead of failing hyperspace travel or spawning it in the old one.
  local destination=self.objectivePoints[stage+1].zoneName or self.questZone
  if destination~=SceneObject(p):getZoneName() then self:set(p,"entered",0) end
  self:task(p,3,false);self:waypoint(p)
 else self:completeQuest(p,"true");return 1 end
 return 0
end
function PilotObjectiveQuest:cleanup(p)
 self:set(p,"generation",self:get(p,"generation")+1)
 dropObserver(SHIPDOCKED,self.className,"dockedShip",p)
 SpaceHelpers:clearQuestWaypoint(p,self.className)
 for _,id in ipairs(readStringVectorSharedMemory(self:key(p,"ships")) or {}) do
  local ship=getSceneObject(tonumber(id))
  writeScreenPlayData(p,"swgxr_docking",id,"");writeScreenPlayData(p,"swgxr_docking_task",id,"")
  CreatureObject(p):removeSpaceMissionObject(tonumber(id),true)
  if ship then dropObserver(SHIPDESTROYED,self.className,"destroyedShip",ship);SceneObject(ship):destroyObjectFromWorld() end
  deleteData(id..":"..self.className..":owner");deleteData(id..":"..self.className..":role")
 end
 writeStringVectorSharedMemory(self:key(p,"ships"),{})
 for _,role in ipairs({"ally","enemy","attacker","target"}) do self:set(p,role.."Count",0) end
end
function PilotObjectiveQuest:completeQuest(p,notify)
 if not self:active(p) then return end
 SpaceHelpers:completeSpaceQuest(p,self.questType,self.questName,notify~="false")
 self:cleanup(p)
 if self.sideQuest and (self.sideQuestSplitType==1 or self.sideQuestSplitType==3) then self:triggerCompletionSplitQuest(p) end
end
function PilotObjectiveQuest:failQuest(p,notify)
 if not self:active(p) then return end
 SpaceHelpers:failSpaceQuest(p,self.questType,self.questName,notify~="false");self:cleanup(p)
 if self.sideQuest and (self.sideQuestSplitType==2 or self.sideQuestSplitType==3) then self:triggerFailureSplitQuest(p) end
end
function PilotObjectiveQuest:resetQuest(p)
 if self:active(p) then SpaceHelpers:failSpaceQuest(p,self.questType,self.questName,false) end
 self:cleanup(p)
end
