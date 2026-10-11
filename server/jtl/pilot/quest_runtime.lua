-- Native quest journal remains authoritative. Screenplay data records only
-- outcomes the journal does not retain (failure/abort/reward receipts).
PilotQuests = {definitions={}, blocked={}, instances={}}
function PilotQuests.hasCertifiedNonNewbieShip(p) return CreatureObject(p):hasCertifiedShip(true,true) end
registerScreenPlay("PilotQuests",false)
function PilotQuests.cancel(p,q)
 for _,method in ipairs(q.sourceTimedMethods or {}) do cancelEvent(q.className,method,p) end
 if q.sideQuest then cancelEvent(q.sideQuestType.."_"..q.sideQuestName,"startQuest",p) end
 if q.sideFailQuestType and q.sideFailQuestType~="" then cancelEvent(q.sideFailQuestType.."_"..q.sideFailQuestName,"startQuest",p) end
end
function PilotQuests:onLogin(p)
 if p==nil then return 0 end
 for _,q in pairs(PilotQuests.instances) do
  if SpaceHelpers:isSpaceQuestActive(p,q.questType,q.questName) then
   q:resetQuest(p);q:startQuest(p,nil)
  end
 end
 return 0
end
local function key(kind,name) return kind..":"..string.lower(name) end
local function state(p,k,s) return PilotSource.get(p,"quest."..k.."."..s) end
local function put(p,k,s,v) PilotSource.put(p,"quest."..k.."."..s,v) end
function PilotQuests.query(p,op,kind,name,seen)
 if op=="hasQuest" and name==nil then
  for _,q in pairs(PilotQuests.definitions) do
   if (kind==nil or kind==q.questType) and SpaceHelpers:isSpaceQuestActive(p,q.questType,q.questName) then return true end
  end
  return false
 end
 if kind==nil or name==nil then return false end
 name=string.lower(name)
 local k=key(kind,name)
 local active=SpaceHelpers:isSpaceQuestActive(p,kind,name)
 local won=SpaceHelpers:isSpaceQuestComplete(p,kind,name)
 local outcome=state(p,k,"outcome")
 if op=="hasQuest" then return active end
 if op=="hasWonQuest" then return won end
 if op=="hasCompletedQuest" then return won or outcome=="failed" or outcome=="aborted" end
 if op=="hasFailedQuest" then return outcome=="failed" end
 if op=="hasAbortedQuest" then return outcome=="aborted" end
 if op=="hasReceivedReward" then
  -- Preserve receipts written by the previous native CorSec/RSF/Havoc scripts.
  return state(p,k,"rewarded")=="1" or getQuestStatus(SceneObject(p):getObjectID()..name..":reward")=="1"
 end
 local plain=string.gsub(op,"Recursive$","")
 assert(plain~=op,"Unknown pilot quest query "..op)
 seen=seen or {};if seen[k] then return false end;seen[k]=true
 local q=PilotQuests.definitions[k]
 local t=q and q.sourceTrigger
 local target=t and t.condition~="failure" and t.target or ""
 local localResult=PilotQuests.query(p,plain,kind,name)
 if plain=="hasCompletedQuest" and not localResult then return false end
 if (plain=="hasFailedQuest" or plain=="hasAbortedQuest") and localResult then return true end
 if target=="" then return localResult end
 local childType,childName=string.match(target,"^([^:]+):(.+)$")
 return PilotQuests.query(p,op,childType,childName,seen)
end
function PilotQuests.grant(p,npc,kind,name)
 name=string.lower(name)
 local k=key(kind,name);local quest=PilotQuests.instances[k]
 if not quest or PilotQuests.blocked[k] then
  PilotSource.abort("This pilot assignment is unavailable while its original mission data is being reconciled.")
 end
 if SpaceHelpers:isSpaceQuestActive(p,kind,name) then return false end
 -- Prevent replaying a completed story mission through stale dialogue actions.
 if SpaceHelpers:isSpaceQuestComplete(p,kind,name) and not string.find(kind,"_duty",1,true) then return false end
 quest:startQuest(p,npc)
 if not SpaceHelpers:isSpaceQuestActive(p,kind,name) then
  PilotSource.abort("This assignment could not be added to your datapad. Finish or abandon your current duty assignment and check datapad capacity, then try again.")
 end
 return true
end
function PilotQuests.reward(p,kind,name,credits,item)
 local k=key(kind,name)
 if not PilotQuests.query(p,"hasWonQuest",kind,name) or PilotQuests.query(p,"hasReceivedReward",kind,name) then return false end
 if item~=nil and item~="" then
  local inventory=SceneObject(p):getSlottedObject("inventory")
  if inventory==nil or SceneObject(inventory):getContainerObjectsSize()>=SceneObject(inventory):getContainerVolumeLimit() then
   PilotSource.abort("Make room in your inventory, then speak to the trainer again to collect your reward.")
  end
  if giveItem(inventory,item,-1)==nil then error("Pilot reward item could not be created: "..item) end
 end
 -- Player mutation is serialized by the native service command. Its receipt and
 -- this flag both guard duplicate requests; save with the player's inventory.
 put(p,k,"rewarded","1")
 if credits and credits>0 then SpaceHelpers:spaceCreditReward(p,credits) end
 return true
end
function PilotQuests.markRewarded(p,kind,name)
 if not PilotQuests.query(p,"hasWonQuest",kind,name) then return false end
 put(p,key(kind,name),"rewarded","1");return true
end
function PilotQuests.clear(p,kind,name)
 name=string.lower(name)
 local k=key(kind,name);local q=PilotQuests.instances[k]
 if SpaceHelpers:isSpaceQuestActive(p,kind,name) and q then q:resetQuest(p) end
 SpaceHelpers:clearSpaceQuest(p,kind,name)
 put(p,k,"outcome",nil);put(p,k,"rewarded",nil)
end
function PilotQuests.bind(k,base)
 local definition=PilotQuests.definitions[k]
 assert(base~=nil,"Missing native pilot mission implementation: "..k)
 local q=base:new(definition)
 local start,complete,fail,reset=q.startQuest,q.completeQuest,q.failQuest,q.resetQuest
 function q:startQuest(p,npc)
  if p==nil or PilotQuests.blocked[k] or SpaceHelpers:isSpaceQuestActive(p,self.questType,self.questName) then return end
  -- Allocate the native mission before scheduling any objective work. Native
  -- duty limits/capacity can refuse activation without throwing an exception.
  if npc=="" then npc=nil end
  SpaceHelpers:activateSpaceQuest(p,npc,self.questType,self.questName,true)
  if not SpaceHelpers:isSpaceQuestActive(p,self.questType,self.questName) then return end
  put(p,k,"outcome",nil)
  if not hasObserver(LOGGEDIN,"PilotQuests","onLogin",p) then createObserver(LOGGEDIN,"PilotQuests","onLogin",p,1) end
  start(self,p,npc)
 end
 function q:completeQuest(p,notify)
  if p==nil or not SpaceHelpers:isSpaceQuestActive(p,self.questType,self.questName) then return end
  PilotQuests.cancel(p,self)
  if self.questType=="assassinate" and not self.sourceMustDestroyEscort and self.despawnTargetShips then self:despawnTargetShips(p) end
  complete(self,p,notify)
  if SpaceHelpers:isSpaceQuestComplete(p,self.questType,self.questName) then
   put(p,k,"outcome","won")
   if self.sourceAutoReward and self.sourceAutoReward>0 then PilotQuests.reward(p,self.questType,self.questName,self.sourceAutoReward) end
  end
 end
 function q:failQuest(p,notify)
  if p==nil or not SpaceHelpers:isSpaceQuestActive(p,self.questType,self.questName) then return end
  PilotQuests.cancel(p,self)
  put(p,k,"outcome","failed");fail(self,p,notify)
 end
 function q:resetQuest(p)
  if p==nil then return end
  PilotQuests.cancel(p,self)
  put(p,k,"outcome","aborted");reset(self,p)
 end
 if q.questType=="assassinate" and not q.sourceMustDestroyEscort then
  local destroyed=q.notifyShipDestroyed
  function q:notifyShipDestroyed(ship,killer)
   if ship~=nil then
    local id=SceneObject(ship):getObjectID()
    if readData(id..":"..self.className..":PrimaryTarget:")==1 then
     local p=getSceneObject(ShipAiAgent(ship):getMissionOwnerID())
     if p and SpaceHelpers:isSpaceQuestActive(p,self.questType,self.questName) then createEvent(1000,self.className,"completeQuest",p,"true");return 1 end
    end
   end
   return destroyed(self,ship,killer)
  end
 end
 if q.questType=="escort" and q.sourceDestroyIsSuccess then
  function q:notifyEscortShipDestroyed(ship,killer)
   if ship==nil then return 1 end
   local p=getSceneObject(ShipAiAgent(ship):getMissionOwnerID())
   if p and SpaceHelpers:isSpaceQuestActive(p,self.questType,self.questName) then self:completeQuest(p,"true") end
   return 1
  end
 end
 PilotQuests.instances[k]=q;_G[q.className]=q
 registerScreenPlay(q.className,true)
end
