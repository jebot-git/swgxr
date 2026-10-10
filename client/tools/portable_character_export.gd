extends RefCounted
const Exporter=preload("res://tools/character_exporter.gd")
static func run(tree:SceneTree)->void:
	var args:=OS.get_cmdline_user_args();args.remove_at(args.find("--character-vrm-export"));var options:Dictionary={}
	for index in range(0,args.size(),2):
		if index+1<args.size():options[args[index].trim_prefix("--")]=args[index+1]
	if not options.has("snapshot") or not options.has("output") or not options.has("report"):
		printerr("Required: -- --snapshot absolute.json --output absolute.glb --report absolute.json");tree.quit(2);return
	var source=JSON.parse_string(FileAccess.get_file_as_string(options.snapshot))
	var exporter:=Exporter.new();tree.root.add_child(exporter)
	var report:Dictionary=exporter.export_character(source if source is Dictionary else {},options.output)
	var file:=FileAccess.open(options.report,FileAccess.WRITE)
	if file==null:printerr("Cannot write export report");tree.quit(2);return
	file.store_string(JSON.stringify(report,"  "));file.close()
	print(JSON.stringify({"ok":report.get("ok",false),"errors":report.get("errors",[]),"output":options.output if report.get("ok",false) else ""}))
	exporter.free();tree.quit(0 if report.get("ok",false) else 1)
