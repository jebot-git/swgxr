#!/usr/bin/env python3
"""Build a reviewable trusted-console loadout for one explicit native test character.

No HTTP administration route, password changes or implicit execution. Original
Core3 item, skill, droid-deed and pet completion implementations remain in use.
"""
import argparse,json,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def build_lua(manifest,character_id,name,tag):
 assert str(character_id).isdigit() and 0<int(character_id)<2**64
 assert re.fullmatch(r'[A-Za-z]{3,24}',name) and re.fullmatch(r'[a-z0-9_]{8,50}',tag)
 def lit(value):return json.dumps(value)
 def array(values):return '{'+','.join(lit(v)for v in values)+'}'
 guard=f'local p=getSceneObject({character_id});if p==nil or CreatureObject(p):getFirstName()~={lit(name)} then return "wrong_character" end'
 items=manifest['inventory_templates']
 lua=f'''\n-- BEGIN {tag} user-authorized isolated test character provisioning
function Tests:swgxrProvisionSkills()
 {guard}
 local ghost=PlayerObject(CreatureObject(p):getPlayerObject())
 if ghost:setSkillPoints(-1) or ghost:setSkillPoints(10001) then return "bounds_failed" end
 local skills={array(manifest['topological_skills'])};local count=0
 for _,skill in ipairs(skills) do
  if not CreatureObject(p):hasSkill(skill) then
   if not ghost:setSkillPoints(10000) then return "setter_failed" end
   awardSkill(p,skill)
  end
  if not CreatureObject(p):hasSkill(skill) then ghost:setSkillPoints(0);return "skill_failed:"..skill end
  count=count+1
 end
 ghost:setSkillPoints(0)
 return "skills:"..tostring(count)
end
function Tests:swgxrProvisionItems()
 {guard}
 local inv=SceneObject(p):getSlottedObject("inventory");local count=0
 local items={array(items)}
 for index,template in ipairs(items) do
  local key="item"..index
  if readScreenPlayData(p,{lit(tag)},key)=="" then
   local found=nil
   for i=0,SceneObject(inv):getContainerObjectsSize()-1 do
    local candidate=SceneObject(inv):getContainerObject(i)
    if SceneObject(candidate):getTemplateObjectPath()==template then found=candidate;break end
   end
   if found==nil then found=giveItem(inv,template,-1) end
   if found==nil then return "item_failed:"..template end
   writeScreenPlayData(p,{lit(tag)},key,tostring(SceneObject(found):getObjectID()))
  end
  count=count+1
 end
 return "items:"..tostring(count)
end
'''
 for i,row in enumerate(manifest['vehicle_devices']):
  lua+=f'''function Tests:swgxrProvisionVehicle{i}()
 {guard}
 local pad=SceneObject(p):getSlottedObject("datapad")
 for n=0,SceneObject(pad):getContainerObjectsSize()-1 do
  local item=SceneObject(pad):getContainerObject(n)
  if SceneObject(item):getTemplateObjectPath()=={lit(row['control_device'])} then return "vehicle_ready" end
 end
 local device=giveControlDevice(pad,{lit(row['control_device'])},{lit(row['template'])},-1,false)
 if device==nil then return "vehicle_failed" end
 SceneObject(device):sendTo(p);return "vehicle_ready"
end
'''
 for i,row in enumerate(manifest['droids']):
  lua+=f'''function Tests:swgxrProvisionDroid{i}()
 {guard}
 local key="droid{i}";if readScreenPlayData(p,{lit(tag)},key)~="" then return "already_done" end
 local inv=SceneObject(p):getSlottedObject("inventory");local deed=giveItem(inv,{lit(row['deed'])},-1)
 if deed==nil or not activateOwnedDroidDeed(p,deed) then return "droid_failed" end
 writeScreenPlayData(p,{lit(tag)},key,"done");return "droid_ready"
end
'''
 for i,row in enumerate(manifest['pets']):
  lua+=f'''function Tests:swgxrProvisionPet{i}()
 {guard}
 local key="pet{i}";if readScreenPlayData(p,{lit(tag)},key)~="" then return "already_done" end
 local player=SceneObject(p);local pet=spawnBabyMobile("tatooine",{lit(row['mobile'])},0,player:getPositionX()+2,player:getPositionZ(),player:getPositionY(),0,0)
 if pet==nil then return "spawn_failed" end
 if not grantCreaturePet(p,pet) then SceneObject(pet):destroyObjectFromWorld();SceneObject(pet):destroyObjectFromDatabase();return "pet_failed" end
 if grantCreaturePet(p,pet) then return "owned_regrant_failed" end
 writeScreenPlayData(p,{lit(tag)},key,tostring(SceneObject(pet):getObjectID()));return "pet_ready"
end
'''
 return lua+f'-- END {tag}\n'
def main():
 p=argparse.ArgumentParser();p.add_argument('--manifest',type=Path,required=True);p.add_argument('--character-id',required=True);p.add_argument('--name',required=True);p.add_argument('--tag',required=True);p.add_argument('--output',type=Path,required=True);args=p.parse_args();data=json.loads(args.manifest.read_text());text=build_lua(data,args.character_id,args.name,args.tag);args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(text);print(json.dumps({'script':str(args.output),'character_id':args.character_id,'skills':len(data['topological_skills']),'executed':False}))
if __name__=='__main__':main()
