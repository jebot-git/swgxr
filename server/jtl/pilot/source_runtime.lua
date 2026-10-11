-- Shared engine bridge for mechanically converted original pilot conversations.
-- Core3 owns all persistent state, skills, faction, ships, inventory and quests.
PilotSource = { api = {}, programs = {}, constants = {}, tracks = {
 tatooinePrivateer = {"neutral", "SMUGGLER_SQUADRON"}, nabooPrivateer = {"neutral", "RSF_SQUADRON"}, corelliaPrivateer = {"neutral", "CORSEC_SQUADRON"},
 tatooineImperial = {"imperial", "STORM_SQUADRON"}, nabooImperial = {"imperial", "INQUISITION_SQUADRON"}, corelliaImperial = {"imperial", "BLACK_EPSILON_SQUADRON"},
 tatooineRebel = {"rebel", "CRIMSON_PHOENIX_SQUADRON"}, nabooRebel = {"rebel", "VORTEX_SQUADRON"}, corelliaRebel = {"rebel", "HAVOC_SQUADRON"}
}}
for name in pairs(PilotSource.tracks) do
 local planet,faction=string.match(name,"^(%l+)(%u%l+)$")
 PilotSource.constants["space_flags."..string.upper(faction).."_"..string.upper(planet)]=name
end
PilotSource.constants["space_quest.QUEST_SERIES_COMPLETED"]=1
PilotSource.constants.GENDER_MALE=0
PilotSource.constants["factions.FACTION_IMPERIAL"]="imperial"
PilotSource.constants["factions.FACTION_REBEL"]="rebel"
function PilotSource.abort(message) error({pilotMessage=message},0) end
function PilotSource.add(a,b) if type(a)=="string" or type(b)=="string" then return tostring(a)..tostring(b) end return a+b end
function PilotSource.values(array)
 local i=-1
 return function() i=i+1; if array and array[i]~=nil then return i,array[i] end end
end
function PilotSource.constant(name)
 if string.sub(name,1,7)=="SCRIPT_" then return 0 end
 local value=PilotSource.constants[name]
 if value==nil then value=_G[name] end
 assert(value~=nil,"Unmapped original pilot constant: "..name)
 return value
end
function PilotSource.get(p,key)
 if not SceneObject(p):isPlayerCreature() then return getQuestStatus("pilot_source.object."..SceneObject(p):getObjectID().."."..key) or "" end
 return readScreenPlayData(p,"pilot_source",key) or ""
end
function PilotSource.put(p,key,value)
 if type(value)=="userdata" then value=SceneObject(value):getObjectID() end
 if not SceneObject(p):isPlayerCreature() then
  setQuestStatus("pilot_source.object."..SceneObject(p):getObjectID().."."..key,value==nil and "" or tostring(value))
 else writeScreenPlayData(p,"pilot_source",key,value==nil and "" or tostring(value)) end
end
function PilotSource.track(p)
 local ghost=CreatureObject(p):getPlayerObject()
 if ghost==nil then return "" end
 local squad=PlayerObject(ghost):getSquadronType()
 for name,entry in pairs(PilotSource.tracks) do if _G[entry[2]]==squad then return name end end
 return ""
end
function PilotSource.faction(p)
 if SpaceHelpers:isImperialPilot(p) then return "imperial" end
 if SpaceHelpers:isRebelPilot(p) then return "rebel" end
 return "neutral"
end
function PilotSource.flag(p,key) return PilotSource.track(p)..".flag."..key end
function PilotSource.call(program,name,...)
 local handler=PilotSource.api[name]
 assert(handler~=nil,"Unmapped original pilot API: "..name)
 return handler(program,...)
end
local api=PilotSource.api
api["hasSkill"]=function(_,p,name) return CreatureObject(p):hasSkill(name) end
api["space_quest.hasSkill"]=api["hasSkill"]
api["space_skill.hasSpaceSkills"]=function(_,p) return SpaceHelpers:isPilot(p) end
api["space_flags.hasAnyPilotSkill"]=api["space_skill.hasSpaceSkills"]
api["features.isSpaceEdition"]=function() return isJtlEnabled() end
api["ai_lib.isInCombat"]=function(_,p) return CreatureObject(p):isInCombat() end
api["space_flags.isNeutralPilot"]=function(_,p) return SpaceHelpers:isNeutralPilot(p) end
api["space_flags.isImperialPilot"]=function(_,p) return SpaceHelpers:isImperialPilot(p) end
api["space_flags.isRebelPilot"]=function(_,p) return SpaceHelpers:isRebelPilot(p) end
api["space_flags.isSpaceTrack"]=function(_,p,track) return PilotSource.track(p)==track end
api["space_flags.getSpaceTrack"]=function(_,p) return PilotSource.track(p) end
api["space_flags.setSpaceTrack"]=function(_,p,track)
 local entry=assert(PilotSource.tracks[track],"Unknown squadron")
 local current=PilotSource.track(p)
 assert(current=="" or current==track,"Surrender current pilot profession before switching squadrons")
 SpaceHelpers:setSquadronType(p,assert(_G[entry[2]],entry[2]))
 local ghost=PlayerObject(CreatureObject(p):getPlayerObject())
 if ghost:getPilotTier()<1 then ghost:incrementPilotTier() end
end
for index,word in ipairs({"One","Two","Three","Four"}) do
 local tier=index
 api["space_flags.hasCompletedTier"..word]=function(_,p) local faction=PilotSource.faction(p);return SpaceHelpers:hasCompletedPilotTier(p,faction=="neutral" and faction or faction.."_navy",tier) end
end
local flagChildren={ss={"ss.findingAgent","ss.huntingShip","ss.finishedQuest3"}}
api["space_flags.hasSpaceFlag"]=function(_,p,key)
 if PilotSource.get(p,PilotSource.flag(p,key))~="" then return true end
 for _,child in ipairs(flagChildren[key] or {}) do if PilotSource.get(p,PilotSource.flag(p,child))~="" then return true end end
 return false
end
api["space_flags.getIntSpaceFlag"]=function(_,p,key) return tonumber(PilotSource.get(p,PilotSource.flag(p,key))) or 0 end
api["space_flags.getBooleanSpaceFlag"]=function(_,p,key) return tonumber(PilotSource.get(p,PilotSource.flag(p,key)))==1 end
api["space_flags.setSpaceFlag"]=function(_,p,key,value) PilotSource.put(p,PilotSource.flag(p,key),(value==true or value==nil) and 1 or value==false and 0 or value) end
api["space_flags.removeSpaceFlag"]=function(_,p,key)
 PilotSource.put(p,PilotSource.flag(p,key),nil)
 for _,child in ipairs(flagChildren[key] or {}) do PilotSource.put(p,PilotSource.flag(p,child),nil) end
end
api["space_quest.hasCompletedQuestSeries"]=function(_,p,key) return PilotSource.get(p,"series."..key)=="1" end
api["space_quest.setQuestSeriesFlag"]=function(_,p,key,value) PilotSource.put(p,"series."..key,value) end
api["utils.setScriptVar"]=function(_,p,key,value) PilotSource.put(p,"script."..key,value) end
api["utils.removeScriptVar"]=function(_,p,key) PilotSource.put(p,"script."..key,nil) end
api["utils.hasScriptVar"]=function(_,p,key) return PilotSource.get(p,"script."..key)~="" end
api["utils.getIntScriptVar"]=function(_,p,key) return tonumber(PilotSource.get(p,"script."..key)) or 0 end
api["utils.getObjIdScriptVar"]=function(_,p,key) return getSceneObject(tonumber(PilotSource.get(p,"script."..key)) or 0) end
api["setObjVar"]=function(_,p,key,value) PilotSource.put(p,"obj."..key,value) end
api["removeObjVar"]=function(_,p,key) PilotSource.put(p,"obj."..key,nil) end
api["hasObjVar"]=function(_,p,key) return PilotSource.get(p,"obj."..key)~="" end
api["getStringObjVar"]=function(_,p,key) local value=PilotSource.get(p,"obj."..key);return value~="" and value or nil end
api["getIntObjVar"]=function(_,p,key) return tonumber(PilotSource.get(p,"obj."..key)) or 0 end
api["space_quest.isPlayerQualifiedForSkill"]=function(_,p,skill) return LuaSkillManager():fulfillsSkillPrerequisitesAndXp(p,skill) end
function PilotSource.syncTier(p)
 local f=PilotSource.faction(p);if f~="neutral" then f=f.."_navy" end
 local ghost=PlayerObject(CreatureObject(p):getPlayerObject())
 local tier=1
 for i=1,4 do if SpaceHelpers:hasCompletedPilotTier(p,f,i) then tier=i+1 else break end end
 while ghost:getPilotTier()<tier do ghost:incrementPilotTier() end
end
api["skill.noisyGrantSkill"]=function(_,p,skill) SpaceHelpers:grantSpaceSkill(p,skill,false);PilotSource.syncTier(p) end
api["grantSkill"]=api["skill.noisyGrantSkill"]
api["skill.purchaseSkill"]=function(_,p,skill)
 if CreatureObject(p):hasSkill(skill) then return end
 assert(LuaSkillManager():fulfillsSkillPrerequisitesAndXp(p,skill),"Pilot training prerequisites changed")
 SpaceHelpers:grantSpaceSkill(p,skill,true)
 PilotSource.syncTier(p)
end
api["getSpecies"]=function(_,p) return CreatureObject(p):getSpecies() end
api["getGender"]=function(_,p) return CreatureObject(p):getGender() end
api["pvpGetAlignedFaction"]=function(_,p) return CreatureObject(p):getFaction() end
api["factions.getFaction"]=function(_,p) local f=CreatureObject(p):getFaction(); if f==FACTIONIMPERIAL then return "imperial" elseif f==FACTIONREBEL then return "rebel" end return "neutral" end
api["factions.isImperial"]=function(_,p) return CreatureObject(p):getFaction()==FACTIONIMPERIAL end
api["factions.isRebel"]=function(_,p) return CreatureObject(p):getFaction()==FACTIONREBEL end
api["factions.getFactionStanding"]=function(_,p,f) return PlayerObject(CreatureObject(p):getPlayerObject()):getFactionStanding(f) end
api["factions.addFactionStanding"]=function(program,p,f,value)
 program.factionRewards=program.factionRewards or {};table.insert(program.factionRewards,{p,f,value})
end
api["space_quest.hasCertifiedShip"]=function(_,p) return SpaceHelpers:hasCertifiedShip(p,true) end
api["space_quest.canGrantNewbieShip"]=function(_,p) return not SpaceHelpers:hasCertifiedShip(p,true) end
api["space_quest.grantNewbieShip"]=function(_,p,f)
 if not SpaceHelpers:hasCertifiedShip(p,true) then grantStarterShip(p,f) end
end
api["space_quest.hasCertifiedNonNewbieShip"]=function(_,p) return PilotQuests.hasCertifiedNonNewbieShip(p) end
for _,name in ipairs({"hasQuest","hasWonQuest","hasCompletedQuest","hasFailedQuest","hasAbortedQuest","hasReceivedReward","hasCompletedQuestRecursive","hasWonQuestRecursive","hasFailedQuestRecursive","hasAbortedQuestRecursive"}) do
 local operation=name
 api["space_quest."..name]=function(_,p,kind,name) return PilotQuests.query(p,operation,kind,name) end
end
api["space_quest.grantQuest"]=function(program,p,kind,name) return PilotQuests.grant(p,program.npc,kind,name) end
api["space_quest.giveReward"]=function(program,p,kind,name,credits,item)
 local rewarded=PilotQuests.reward(p,kind,name,credits,item)
 program.rewardGranted=rewarded
 return rewarded
end
api["space_quest.setQuestRewarded"]=function(_,p,kind,name) return PilotQuests.markRewarded(p,kind,name) end
api["space_quest.clearQuestFlags"]=function(_,p,kind,name) return PilotQuests.clear(p,kind,name) end
api["utils.getInventoryContainer"]=function(_,p) return SceneObject(p):getSlottedObject("inventory") end
api["getVolumeFree"]=function(_,p) return SceneObject(p):getContainerVolumeLimit()-SceneObject(p):getContainerObjectsSize() end
api["createObjectOverloaded"]=function(_,template,container) return giveItem(container,template,-1) end
api["isIdValid"]=function(_,p) return p~=nil end
api["getContents"]=function(_,p)
 local out={};for i=0,SceneObject(p):getContainerObjectsSize()-1 do out[i]=SceneObject(p):getContainerObject(i) end;return out
end
api["getTemplateName"]=function(_,p) return SceneObject(p):getTemplateObjectPath() end
api["destroyObject"]=function(_,p) if p~=nil then SceneObject(p):destroyObjectFromWorld();SceneObject(p):destroyObjectFromDatabase() end end
api["getName"]=function(_,p) return SceneObject(p):getCustomObjectName() end
api["doAnimationAction"]=function(_,p,animation) CreatureObject(p):doAnimation(animation) end
api["playMusic"]=function(_,p,music) CreatureObject(p):playMusicMessage(music) end
api["ai_lib.setDefaultCalmMood"]=function(_,p,mood) CreatureObject(p):setMoodString(mood) end
-- Cosmetic original-client operations; physics and HMD pose are never animated.
for _,name in ipairs({"faceTo","setName","setInvulnerable","pp.actor.set","pp.target.set","space_flags.restoreClientPath","space_flags.clearClientPath","playClientEffectLoc"}) do api[name]=function() end end
-- Post-NGE ground tutorial signal has no quest counterpart in the ground scope.
api["groundquests.sendSignal"]=function() end
api["getLocation"]=function(_,p) return {planet=SceneObject(p):getZoneName(),x=SceneObject(p):getPositionX(),y=SceneObject(p):getPositionZ(),z=SceneObject(p):getPositionY()} end
api["createWaypointInDatapad"]=function(_,p,point)
 local id=PlayerObject(CreatureObject(p):getPlayerObject()):addWaypoint(point.planet,"Pilot trainer","",point.x,point.y,point.z,WAYPOINT_BLUE,true,true,0)
 return getSceneObject(id)
end
api["setWaypointName"]=function(_,p,name) if p then SceneObject(p):setCustomObjectName(name) end end
api["setWaypointActive"]=function(_,p,active) if p then WaypointObject(p):setActive(active and 1 or 0) end end
-- Later-source medal additions are outside Total Experience's asset set.
-- The original mission's credits, jacket/helmet and mastery skill are retained.
api["createObjectInInventoryAllowOverload"]=function(program,template,p)
 assert(string.find(template,"_ace_pilot_",1,true),"Unmapped original inventory creation: "..template)
 program.suppressedLaterReward=true;return nil
end
api["static_item.createNewItemFunction"]=function(program,name,p)
 assert(name=="item_quest_reward_imperial_pilot_medal_01_01" or name=="item_quest_reward_rebel_pilot_medal_01_01" or name=="item_quest_reward_neutral_pilot_medal_01_01","Unmapped later static reward: "..name)
 program.suppressedLaterReward=true;return nil
end
api["setBioLink"]=function(_,item,p) assert(item==nil,"Unexpected post-TTE biolink item") end
api["prose.setStringId"]=function(_,prose,text) prose.stringId=text;return prose end
api["prose.setTO"]=function(_,prose,text) prose.target=text;return prose end
api["sendQuestSystemMessage"]=function(program,p,prose)
 if not program.suppressedLaterReward and prose.stringId then CreatureObject(p):sendSystemMessage(prose.stringId) end
end
function PilotSource.compatibilityMessage(p,hasOptions)
 local active={}
 for k,q in pairs(PilotQuests.definitions) do
  if SpaceHelpers:isSpaceQuestActive(p,q.questType,q.questName) then table.insert(active,(PilotQuests.titles or {})[k] or "Pilot assignment") end
 end
 table.sort(active)
 if #active>0 then return "Current assignment: "..table.concat(active,"; ")..". Your datapad contains the objectives and navigation waypoints." end
 if hasOptions then return "Pilot training and assignments. Choose a response below." end
 return "Speak to your squadron trainer when you are ready to continue your pilot assignments."
end
api["npcSpeak"]=function(program,_,message) program.view.message=type(message)=="table" and message.stringId or message end
api["npcSetConversationResponses"]=function(program,player,responses) program.view.responses=responses end
api["npcStartConversation"]=function(program,player,npc,_,message,fifth,sixth)
 local responses=sixth or fifth
 if message==nil and type(fifth)=="table" then message=fifth.stringId end
 program.view={message=message,responses=responses};return true
end
api["npcEndConversationWithMessage"]=function(program,player,message) program.view={message=message,responses={}} end
api["npcEndConversation"]=function(program) program.view.responses={} end
api["chat.chat"]=function(program,npc,player,message) program.view={message=message or player,responses={}} end

-- The original Storm transfer form has an inventory Read/Sign SUI. Present that
-- same explicit signing step in the existing trainer panel before handover.
function PilotSource.transferForm(p)
 local inventory=SceneObject(p):getSlottedObject("inventory")
 if not inventory then return nil end
 for i=0,SceneObject(inventory):getContainerObjectsSize()-1 do
  local item=SceneObject(inventory):getContainerObject(i)
  if item and SceneObject(item):getTemplateObjectPath()=="object/tangible/space/mission_objects/transfer_auth.iff" then return item end
 end
 return nil
end
function PilotSource.signTransfer(p)
 local item=PilotSource.transferForm(p)
 if not item then PilotSource.abort("Your transfer authorization must be in your backpack before you can sign it.") end
 PilotSource.put(item,"obj.signature",SceneObject(p):getCustomObjectName())
 CreatureObject(p):sendSystemMessage("@space/quest:signed")
end

function PilotSource.migrate(p)
 if PilotSource.get(p,"migration.version")=="1" then return end
 -- Existing Havoc characters used native journal/skill state rather than the
 -- original Java transfer flag. Import only an actual legacy reward receipt.
 if PilotSource.track(p)=="corelliaRebel" then
  local id=SceneObject(p):getObjectID()
  for _,quest in ipairs({"corellia_rebel_4","viopa_rebel_1","viopa_rebel_2","viopa_rebel_3","viopa_rebel_4"}) do
   if getQuestStatus(id..quest..":reward")=="1" then
    PilotSource.put(p,PilotSource.flag(p,"viopaPilot"),1);break
   end
  end
 end
 PilotSource.put(p,"migration.version",1)
end

function PilotSource.bind(name)
 local program=assert(_G[name],name)
 PilotSource.programs[name]=program
 local handler=conv_handler:new {programName=name}
 function handler:getNextConversationScreen(template,p,option,npc)
  local original=PilotSource.programs[self.programName]
  local context=setmetatable({npc=npc,view={responses={}},factionRewards={}},{__index=original})
  local session=CreatureObject(p):getConversationSession()
  local last=session and LuaConversationSession(session):getLastConversationScreen()
  local ok,problem=pcall(function()
  PilotSource.migrate(p)
  if CreatureObject(p):isInCombat() then PilotSource.abort("Finish combat before speaking to your pilot trainer.") end
  local isTransfer=self.programName=="tatooine_imperial_trainer_2" or self.programName=="tatooine_imperial_trainer_2b"
  local form=isTransfer and PilotSource.transferForm(p)
  if last~=nil and option>=0 and LuaConversationScreen(last):getOptionLink(option)=="__pilot_sign_transfer" then
   assert(isTransfer,"Transfer form is not supported by this trainer")
   PilotSource.signTransfer(p)
   context:OnStartNpcConversation(npc,p)
  elseif form and PilotSource.get(form,"obj.signature")~=SceneObject(p):getCustomObjectName() then
   context.view={message="@space/quest:ta_text",responses={[0]="@space/quest:sign"},transfer=true}
  elseif last~=nil and option>=0 then
   local screen=LuaConversationScreen(last)
   assert(option<screen:getOptionCount(),"Pilot conversation option expired")
   context:OnNpcConversationResponse(npc,self.programName,p,screen:getOptionLink(option))
  else context:OnStartNpcConversation(npc,p) end
  end)
  if not ok then
   if type(problem)=="table" and problem.pilotMessage then context.view={message=problem.pilotMessage,responses={},custom=true}
   else error(problem) end
  end
  if context.rewardGranted then
   for _,entry in ipairs(context.factionRewards) do PlayerObject(CreatureObject(entry[1]):getPlayerObject()):increaseFactionStanding(entry[2],entry[3]) end
  end
  local base=LuaConversationTemplate(template):getScreen("source")
  local clone=LuaConversationScreen(base):cloneScreen();local screen=LuaConversationScreen(clone)
  screen:removeAllOptions()
  local message=context.view.message
  assert(type(message)=="string" and message~="","Original pilot conversation returned no screen")
  if (PilotSource.missingText or {})[message] then
   context.view.custom=true;message=PilotSource.compatibilityMessage(p,next(context.view.responses or {})~=nil)
  end
  if context.view.custom then screen:setCustomDialogText(message) else screen:setDialogTextStringId(message) end
  screen:setDialogTextTU(CreatureObject(p):getFirstName())
  for _,text in PilotSource.values(context.view.responses) do
   local label=(PilotSource.missingText or {})[text] and ((PilotSource.optionLabels or {})[text] or "Continue briefing") or text
   screen:addOption(label,context.view.transfer and "__pilot_sign_transfer" or string.match(text,":([^:]+)$"))
  end
  screen:setStopConversation(screen:getOptionCount()==0)
  return clone
 end
 _G["swgxrPilotSource_"..name]=handler
end
