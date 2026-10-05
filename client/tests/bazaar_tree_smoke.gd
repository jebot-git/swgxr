extends SceneTree
## Original media GOT/STF category hierarchy, mocked native filtered listing replies.
const ServicePanel=preload("res://scripts/service_panel.gd")
var requests: Array=[]
var failures: Array[String]=[]
var checks:=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures.append(message);push_error(message)
func _initialize() -> void: call_deferred("run")
static func source_categories() -> Array:
	var source: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/services/bazaar_categories.json"))
	var by_id: Dictionary={}
	for node: Dictionary in source.nodes: by_id[int(node.id)]=node
	var categories: Array=[{"id":0,"name":"All","label":"All","children":[]}]
	for id in by_id[0].children:
		var parent: Dictionary=by_id[int(id)].duplicate(true)
		parent.children=[]
		for child in by_id[int(id)].children: parent.children.append(by_id[int(child)].duplicate(true))
		categories.append(parent)
	return categories
func run() -> void:
	var categories:=source_categories()
	var panel:=ServicePanel.new();root.add_child(panel)
	panel.action_requested.connect(func(action,payload): requests.append({"action":action,"payload":payload}))
	var listing_rows: Array=[]
	for index in range(20): listing_rows.append({"id":str(100+index),"name":"Fixture listing","price":10,"buy_eligible":true})
	var record: Dictionary={"id":"10","kind":"bazaar","categories":categories,"listings":listing_rows,"page":0,"has_more":true,"category_id":0}
	panel.configure(record,{"cash":1000,"bank":1000})
	check(panel.category_rows[0].id==0 and panel.category_rows[0].label=="All","Original All root precedes source major categories")
	var weapon_index:=-1
	for index in range(categories.size()):
		if int(categories[index].id)==131072: weapon_index=index
	check(weapon_index>0,"Original weapon general type present with source GOT identifier")
	panel.category_offset=mini(weapon_index,13);panel.offset=3;panel.selected=5
	var root_offset: int=panel.category_offset
	panel.select_category(weapon_index)
	check(requests.back().payload.category_id==131072 and requests.back().payload.page==0,"Source general category sent for native pre-pagination filtering")
	check(panel.pending and panel.rows.is_empty(),"Parent listings hidden until native selected-category reply")
	check(panel.category_name=="Weapon" and panel.category_rows.size()==12,"Localized source name and exact original weapon children shown")
	record.category_id=131072;record.listings=listing_rows
	panel.configure(record,{"cash":1000,"bank":1000})
	check(panel.category_path.size()==1 and panel.category_id==131072,"Native filtered refresh preserves category path")
	panel.category_offset=3;panel.offset=2;panel.selected=4
	var pistol_index:=-1
	for index in range(panel.category_rows.size()):
		if int(panel.category_rows[index].id)==131082: pistol_index=index
	panel.select_category(pistol_index)
	check(requests.back().payload.category_id==131082 and panel.category_name=="Pistol","Source pistol subtype drives native filtering")
	check(panel.category_rows.is_empty() and panel.category_path.size()==2,"Leaf does not invent category children")
	record.category_id=131082;record.listings=[{"id":"900","name":"FWG5 pistol","price":100,"buy_eligible":true}]
	panel.configure(record,{"cash":1000,"bank":1000})
	panel.selected=0;panel.confirm()
	check(requests.back().action=="bazaar_buy" and requests.back().payload.category_id==131082 and requests.back().payload.page==0,"Purchase carries current browse context for refreshed results")
	panel.set_pending(false)
	panel.category_back()
	check(requests.back().payload.category_id==131072 and panel.category_offset==3 and panel.category_selected==pistol_index,"Back restores parent category selection and scroll")
	check(panel.offset==2 and panel.selected==4,"Back restores parent listing selection and scroll")
	record.category_id=131072;record.listings=listing_rows;panel.configure(record,{"cash":1000,"bank":1000})
	panel.category_back()
	check(requests.back().payload.category_id==0 and panel.category_offset==root_offset and panel.category_selected==weapon_index,"Second Back restores root category scroll and selected weapon node")
	check(panel.offset==3 and panel.selected==5 and panel.category_path.is_empty(),"Root browse selection preserved without stale child state")
	record.category_id=0;panel.configure(record,{"cash":1000,"bank":1000})
	var count:=requests.size()
	panel.click_at(Vector2(90,515))
	check(requests.size()==count,"Root Back is a safe no-op, not an unexpected refresh")
	panel.click_at(Vector2(520,515))
	check(requests.back().payload.page==1 and requests.back().payload.category_id==0,"Next native page retains source category filter")
	record.page=1;record.has_more=false;panel.configure(record,{"cash":1000,"bank":1000})
	count=requests.size();panel.click_at(Vector2(520,515))
	check(requests.size()==count,"Last native page cannot advance beyond has_more")
	panel.click_at(Vector2(420,515))
	check(requests.back().payload.page==0,"Previous native page available")
	panel.set_pending(false)
	panel.select_category(weapon_index)
	panel.set_pending(false);panel.message="Native filter failed"
	check(panel.rows.is_empty() and panel.category_id==131072,"Failed filter cannot expose parent listings under wrong category")
	panel.category_back()
	check(requests.back().payload.category_id==0,"Back remains available after rejected filter")
	panel.free()
	var result: Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"categories":"original GOT/STF user-media export","listing_replies":"mocked native envelopes","renderer":"headless dummy; XR disabled"}
	var file:=FileAccess.open(ProjectSettings.globalize_path("res://../runtime/evidence/bazaar-tree-smoke.json"),FileAccess.WRITE)
	if file!=null: file.store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify(result));quit(0 if failures.is_empty() else 1)
