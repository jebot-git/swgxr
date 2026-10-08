extends RefCounted
## Local wire preview only. A complete board is submitted to Core3 for validation.
var size:=0
var cell_size:=0.1
var pairs:Array=[]
var wires:Dictionary={}
var active_color:=-1
var active_end:=-1
var draft:Array=[]
var contact_latch:=""
var previous_tip:=Vector3.ZERO
var have_tip:=false
var revision:=0
var error:=""
const CONTACT_RADIUS:=0.035

static func cell(value:Variant)->Vector3i:
	return Vector3i(int(value[0]),int(value[1]),int(value[2]))
func valid_cell(value:Variant)->bool:
	if not value is Array or value.size()!=3:return false
	for component in value:
		if not (component is int or component is float) or not is_finite(float(component)) or int(component)!=component or component<0 or component>=size:return false
	return true
func configure(challenge:Dictionary,meters:=0.1)->bool:
	size=int(challenge.get("size",0));cell_size=meters;pairs=[];wires={};active_color=-1;active_end=-1;draft=[];contact_latch="";have_tip=false;error="";revision+=1
	if size<3 or size>5 or not is_finite(meters) or meters<.05 or meters>.2:error="Unsupported grid dimensions";return false
	var incoming:Variant=challenge.get("pairs")
	if not incoming is Array or incoming.size()<2 or incoming.size()>4:error="Invalid pipe pairs";return false
	var colors:Dictionary={};var cells:Dictionary={}
	for pair in incoming:
		if not pair is Dictionary or not pair.get("color") is int and not pair.get("color") is float:error="Invalid pipe identity";return false
		var color:=int(pair.color)
		if color<0 or color>3 or pair.color!=color or colors.has(color) or not pair.get("ends") is Array or pair.ends.size()!=2:error="Invalid pipe identity";return false
		colors[color]=true
		for endpoint in pair.ends:
			if not endpoint is Dictionary or not valid_cell(endpoint.get("cell")) or not endpoint.get("face") is Array or endpoint.face.size()!=3:error="Invalid endpoint";return false
			var face:=Vector3i.ZERO
			for axis in range(3):
				var n:Variant=endpoint.face[axis]
				if not (n is int or n is float) or not is_finite(float(n)) or int(n)!=n or absi(int(n))>1:error="Invalid endpoint face";return false
				face[axis]=int(n)
			var point:=cell(endpoint.cell)
			if absi(face.x)+absi(face.y)+absi(face.z)!=1 or cells.has(point):error="Overlapping or invalid endpoints";return false
			for axis in range(3):
				if (face[axis]==-1 and point[axis]!=0) or (face[axis]==1 and point[axis]!=size-1):error="Endpoint must be on a cube wall";return false
			cells[point]=color
		var normalized:Dictionary=pair.duplicate(true);normalized.color=color
		for endpoint:Dictionary in normalized.ends:
			endpoint.cell=endpoint.cell.map(func(n):return int(n));endpoint.face=endpoint.face.map(func(n):return int(n))
		pairs.append(normalized)
	var connections:Variant=challenge.get("preconnected",[])
	if not connections is Array:error="Invalid initial wires";return false
	for connection in connections:
		if not connection is Dictionary or not connection.get("cells") is Array:error="Invalid initial wire";return false
		var color:=int(connection.get("color",-1))
		if wires.has(color) or not valid_path(color,connection.cells):error="Invalid initial wire";return false
		wires[color]=connection.cells.map(func(v):return v.map(func(n):return int(n)))
	return true
func pair_for(color:int)->Dictionary:
	for pair:Dictionary in pairs:
		if int(pair.color)==color:return pair
	return {}
func center(value:Array)->Vector3:
	return (Vector3(cell(value))+Vector3.ONE*.5)*cell_size-Vector3.ONE*size*cell_size*.5
func endpoint_position(endpoint:Dictionary)->Vector3:
	return center(endpoint.cell)+Vector3(cell(endpoint.face))*cell_size*.5
func occupied(point:Vector3i,except_color:=-1)->bool:
	for pair:Dictionary in pairs:
		if int(pair.color)==except_color:continue
		for endpoint:Dictionary in pair.ends:
			if cell(endpoint.cell)==point:return true
	for color in wires:
		if int(color)==except_color:continue
		for value:Array in wires[color]:
			if cell(value)==point:return true
	return false
func valid_path(color:int,path:Array)->bool:
	var pair:=pair_for(color)
	if pair.is_empty() or path.size()<2 or path.size()>size*size*size:return false
	var seen:Dictionary={}
	var previous:=Vector3i.ZERO
	for index in range(path.size()):
		if not valid_cell(path[index]):return false
		var point:=cell(path[index])
		if seen.has(point) or occupied(point,color):return false
		if index>0:
			var difference:=point-previous
			if absi(difference.x)+absi(difference.y)+absi(difference.z)!=1:return false
		seen[point]=true;previous=point
	var start:=cell(pair.ends[0].cell);var end:=cell(pair.ends[1].cell)
	return (cell(path[0])==start and cell(path[-1])==end) or (cell(path[0])==end and cell(path[-1])==start)
func complete()->bool:
	if active_color>=0 or wires.size()!=pairs.size():return false
	for pair:Dictionary in pairs:
		if not wires.has(int(pair.color)) or not valid_path(int(pair.color),wires[int(pair.color)]):return false
	return true
func paths()->Array:
	var result:Array=[]
	for pair:Dictionary in pairs:
		var color:=int(pair.color)
		if wires.has(color):result.append({"color":color,"cells":wires[color].duplicate(true)})
	return result
func nearest_endpoint(tip:Vector3)->Dictionary:
	var nearest:Dictionary={};var distance:=CONTACT_RADIUS
	for pair:Dictionary in pairs:
		for index in range(2):
			var next:=tip.distance_to(endpoint_position(pair.ends[index]))
			if next<distance:nearest={"color":int(pair.color),"end":index};distance=next
	return nearest
func extend(value:Array)->bool:
	if active_color<0 or not valid_cell(value):return false
	var point:=cell(value)
	if occupied(point,active_color):error="That cube already carries another pipe";return false
	for index in range(draft.size()):
		if cell(draft[index])==point:
			if index<draft.size()-1:draft.resize(index+1);revision+=1
			return true
	var distance:=point-cell(draft[-1])
	if absi(distance.x)+absi(distance.y)+absi(distance.z)!=1:error="Move through an adjoining cube";return false
	draft.append(value.duplicate());revision+=1;error="";return true
func touch(endpoint:Dictionary)->String:
	var color:=int(endpoint.color);var index:=int(endpoint.end)
	if wires.has(color):
		wires.erase(color);active_color=-1;draft=[];revision+=1;error="";return "cut"
	if active_color==color and active_end!=index:
		if extend(pair_for(color).ends[index].cell) and valid_path(color,draft):
			wires[color]=draft.duplicate(true);active_color=-1;draft=[];revision+=1;return "connected"
		return "blocked"
	if active_color>=0:
		if color==active_color and index==active_end:active_color=-1;draft=[];revision+=1;return "cut"
		error="Finish or detach the current pipe first";return "blocked"
	active_color=color;active_end=index;draft=[pair_for(color).ends[index].cell.duplicate()];revision+=1;error="";return "started"
func sample(tip:Vector3,tracked:bool)->Dictionary:
	if not tracked or not tip.is_finite():have_tip=false;contact_latch="reacquire";return {"action":"","changed":false}
	var before:=revision;var action:=""
	var endpoint:=nearest_endpoint(tip)
	var key:="%d:%d"%[endpoint.color,endpoint.end] if not endpoint.is_empty() else ""
	if key.is_empty():contact_latch=""
	elif contact_latch=="reacquire":
		previous_tip=tip;have_tip=true;return {"action":"","changed":false,"complete":complete()}
	# A recovered tool must leave all endpoint shells before creating contact.
	if not key.is_empty() and key!=contact_latch and contact_latch!="reacquire":
		action=touch(endpoint);contact_latch=key
	elif active_color>=0:
		var origin:=previous_tip if have_tip else tip
		var distance:=origin.distance_to(tip)
		if distance<=.5:
			var steps:=maxi(1,ceili(distance/(cell_size*.2)))
			for index in range(1,steps+1):
				var current:=origin.lerp(tip,float(index)/steps)+Vector3.ONE*size*cell_size*.5
				var grid:=Vector3i(floori(current.x/cell_size),floori(current.y/cell_size),floori(current.z/cell_size))
				if not valid_cell([grid.x,grid.y,grid.z]):continue
				if not extend([grid.x,grid.y,grid.z]):action="blocked";break
		else:error="Tracking moved too far; return to the last cube";action="blocked"
	previous_tip=tip;have_tip=true
	return {"action":action,"changed":revision!=before,"complete":complete(),"error":error}
