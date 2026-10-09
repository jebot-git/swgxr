extends RefCounted
## Presentation of the owner's native PvE investigation. Never discovers a target.
const PROBE="object/tangible/mission/mission_bounty_droid_probot.iff"
const SEEKER="object/tangible/mission/mission_bounty_droid_seeker.iff"
static func droid_item(item:Dictionary)->bool:
	return str(item.get("template",item.get("shared_template",""))).replace("/shared_","/") in [PROBE,SEEKER]
static func progress_text(bounty:Dictionary)->String:
	if not bounty.get("pve_only",false):return "PvE bounty hunting only."
	if str(bounty.get("mission_id","")) in ["","0"]:return "Accept a PvE bounty at a bounty hunting terminal."
	var text:String={"informant":"Speak to a suitable bounty informant to obtain the target's bio-signature.","signature":"Bio-signature acquired. Activate an Arakyd probe droid from inventory.","probe_calling":"Arakyd probe launched. Wait for its planetary search.","probe_ready":"The probe is ready for its planetary search.","searching":"The droid is searching. Wait for its report.","tracking":"A seeker droid is tracking the target. Follow the latest reported waypoint.","target":"Follow the revealed waypoint. Use a seeker droid to find or track the target."}.get(str(bounty.get("stage","")),"Awaiting the next native bounty report.")
	if str(bounty.get("stage",""))=="target" and int(bounty.get("level",0))<=1:text="Follow the informant’s waypoint and defeat the PvE bounty target."
	if bounty.get("planet_known",false) and not str(bounty.get("planet","")).is_empty():text+="\n\nTarget planet: "+str(bounty.planet).capitalize()
	if not str(bounty.get("message","")).is_empty():text+="\n\n"+str(bounty.message)
	var waypoint:Dictionary=bounty.get("waypoint",{})
	if waypoint.get("active",false):
		text+="\n\nLatest report: "+str(waypoint.get("planet","")).capitalize()
		var point:Variant=waypoint.get("position")
		if point is Array and point.size()==3:text+=" · X %.0f, Z %.0f"%[float(point[0]),float(point[2])]
	return text
static func droid(bounty:Dictionary,item_id:String)->Dictionary:
	if not bounty.get("pve_only",false) or str(bounty.get("mission_id","")) in ["","0"]:return {}
	for row:Dictionary in bounty.get("droids",[]):
		if str(row.get("id",""))==item_id:return row
	return {}
static func launch_action(bounty:Dictionary,item_id:String)->String:
	var row:=droid(bounty,item_id)
	if row.get("kind","")!="seeker":return ""
	if row.get("track_enabled",false):return "bounty_track"
	return "bounty_seek" if row.get("find_enabled",false) else ""
static func choices(bounty:Dictionary,item_id:String)->Array:
	var row:=droid(bounty,item_id)
	if row.get("kind","")!="probe" or not row.get("call_enabled",false):return []
	var result:Array=[]
	for planet in bounty.get("planets",[]):
		if not planet is String:continue
		var id:=str(planet)
		if id.is_empty():continue
		result.append({"id":id,"name":id.capitalize(),"enabled":true,"description":"Launch this Arakyd probe to search "+id.capitalize()+".\n\nUses remaining: %d"%maxi(0,int(row.get("uses",0)))})
	return result
static func contacts(bounty:Dictionary)->Array:
	if not bounty.get("pve_only",false):return []
	var result:Array=[]
	for informant:Dictionary in bounty.get("informants",[]):
		var row:=informant.duplicate(true);row.kind="bounty_informant";row.confirm_action="bounty_informant";row.eligible=bool(row.get("can_contact",false));row.dialogue=progress_text(bounty)
		if not row.eligible:row.dialogue+="\n\nThis informant cannot provide a signature for your current assignment."
		result.append(row)
	return result
static func entry(bounty:Dictionary)->Dictionary:
	var id:=str(bounty.get("mission_id",""))
	if not bounty.get("pve_only",false) or id in ["","0"]:return {}
	return {"id":"bounty:"+id,"mission_id":id,"type":"bounty_mission","category":"data","name":"PvE bounty investigation","description":progress_text(bounty),"deletable":false}
