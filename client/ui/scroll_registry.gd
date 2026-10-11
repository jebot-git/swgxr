extends Node
## One input arbiter per GUI viewport, including dynamically created XR panels.
const Drag=preload("res://ui/drag_scroll.gd")
func _ready()->void:
	get_tree().node_added.connect(added)
	visit(get_tree().root)
func visit(node:Node)->void:
	if node is Viewport:install.call_deferred(node)
	for child in node.get_children():visit(child)
func added(node:Node)->void:
	if node is Viewport:install.call_deferred(node)
func install(viewport:Viewport)->void:
	if not is_instance_valid(viewport) or viewport.has_node("UniversalDragScroll"):return
	var scroll:=Drag.new();scroll.name="UniversalDragScroll";viewport.add_child(scroll)
