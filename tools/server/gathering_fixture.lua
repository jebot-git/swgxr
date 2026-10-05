-- Controlled disposable source-object fixture. Installed only by prepare_gathering_fixture.py.
function Tests:swgxrGatheringFixture(oid,phase)
 local player=getSceneObject(tonumber(oid))
 if player==nil or tonumber(oid)~=__FIXTURE_ID__ then return "wrong fixture" end
 local inv=SceneObject(player):getSlottedObject("inventory")
 if phase=="skills" then
  awardSkill(player,"crafting_artisan_survey_04")
  awardSkill(player,"outdoors_scout_novice")
 elseif phase=="corpse" then
  local animal=spawnMobile("tatooine","worrt",0,3602,5,-4780,0,0)
  if animal~=nil then
   local loot=SceneObject(animal):getSlottedObject("inventory")
   giveItem(loot,"object/tangible/food/foraged/foraged_fruit_s2.iff",-1)
   CreatureObject(animal):addCashCredits(123,true)
   -- Controlled native corpse state fixture; no native combat bridge is asserted.
   CreatureObject(animal):setHAM(0,0)
   CreatureObject(animal):setPosture(14) -- source CreaturePosture::DEAD
   writeData("swgxr_gathering_fixture:"..oid..":corpse",SceneObject(animal):getObjectID())
   CreatureObject(animal):setLootRights(player)
   CreatureObject(player):clearCombatState(1)
   print("SWGXR_CORPSE_ID "..SceneObject(animal):getObjectID().." dead="..tostring(CreatureObject(animal):isDead()))
  end
 elseif phase=="cleanup_corpse" then
  local body=getSceneObject(readData("swgxr_gathering_fixture:"..oid..":corpse"))
  if body~=nil then SceneObject(body):destroyObjectFromWorld();SceneObject(body):destroyObjectFromDatabase() end
 elseif phase=="clear_organic" then
  for i=SceneObject(inv):getContainerObjectsSize()-1,0,-1 do
   local item=SceneObject(inv):getContainerObject(i)
   if SceneObject(item):getTemplateObjectPath()=="object/resource_container/organic_food.iff" then
    SceneObject(item):destroyObjectFromWorld();SceneObject(item):destroyObjectFromDatabase()
   end
  end
 elseif phase=="fill" then
  for i=1,80 do
   if SceneObject(inv):getContainerObjectsSize()>=80 then break end
   giveItem(inv,"object/tangible/food/foraged/foraged_fruit_s3.iff",-1)
  end
 elseif phase=="clear_filler" then
  for i=SceneObject(inv):getContainerObjectsSize()-1,0,-1 do
   local item=SceneObject(inv):getContainerObject(i)
   if SceneObject(item):getTemplateObjectPath()=="object/tangible/food/foraged/foraged_fruit_s3.iff" then
    SceneObject(item):destroyObjectFromWorld();SceneObject(item):destroyObjectFromDatabase()
   end
  end
 end
 return "done"
end
