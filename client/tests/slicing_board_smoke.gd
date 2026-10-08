extends SceneTree
const Board=preload("res://slicing/board.gd")
const Grid=preload("res://slicing/grid_view.gd")
var checks:=0
var errors:Array=[]
func check(value:bool,label:String)->void:
	checks+=1
	if not value:errors.append(label);push_error(label)
static func fixture(size:int,count:int)->Dictionary:
	var pairs:Array=[]
	for color in range(count):
		var y:=color%size;var z:=color/size
		pairs.append({"color":color,"ends":[{"cell":[0,y,z],"face":[-1,0,0]},{"cell":[size-1,y,z],"face":[1,0,0]}]})
	return {"size":size,"pairs":pairs,"preconnected":[]}
static func line(size:int,color:int)->Array:
	var values:Array=[]
	for x in range(size):values.append([x,color%size,color/size])
	return values
func _initialize()->void:call_deferred("run")
func run()->void:
	for size in [3,4,5]:
		for count in [2,3,4]:
			var board:=Board.new()
			check(board.configure(JSON.parse_string(JSON.stringify(fixture(size,count)))),"Native JSON grid/pairs configure %d/%d"%[size,count])
			for color in range(count):
				var ends:Array=board.pairs[color].ends
				board.sample(board.endpoint_position(ends[0])+Vector3.LEFT*.08,true)
				var started:Dictionary=board.sample(board.endpoint_position(ends[0]),true)
				check(started.action=="started","Touch endpoint starts that colored pipe")
				board.sample(board.center(ends[0].cell),true)
				board.sample(board.center(ends[1].cell),true)
				var connected:Dictionary=board.sample(board.endpoint_position(ends[1]),true)
				check(connected.action=="connected" and board.wires.has(color),"Swept tip traverses all intermediate cubes to matching endpoint")
				check(board.sample(board.endpoint_position(ends[1]),true).action.is_empty(),"Held endpoint contact cannot immediately detach finished pipe")
			check(board.complete() and board.paths().size()==count,"All disjoint pairs produce candidate completion")
			check(board.paths()[0].cells[0][0] is int,"JSON input normalizes to strict integer submit coordinates")
			var end:Dictionary=board.pairs[0].ends[0]
			board.sample(board.endpoint_position(end)+Vector3.LEFT*.08,true)
			check(board.sample(board.endpoint_position(end),true).action=="cut" and not board.complete(),"Touching connected endpoint detaches its complete line")
	var board:=Board.new();var challenge:=fixture(3,2);challenge.preconnected=[{"color":0,"cells":line(3,0)}]
	check(board.configure(challenge) and board.wires.has(0),"Native preconnection is rendered as an editable occupied path")
	check(not board.valid_path(1,[[0,1,0],[0,0,0],[1,0,0],[2,0,0],[2,1,0]]),"Shared cell rejects crossings including other endpoint cells")
	check(not board.valid_path(1,[[0,1,0],[1,2,0],[2,1,0]]),"Diagonal cell skipping is invalid")
	check(not board.valid_path(1,[[0,1,0],[1,1,0],[0,1,0],[1,1,0],[2,1,0]]),"Self-crossing cell reuse is invalid")
	check(not board.valid_path(1,[[0,1,0],[1,1,0],[2,1,1]]),"Matching color must reach its exact other endpoint")
	board.touch({"color":1,"end":0})
	check(not board.extend([0,0,0]) and board.active_color==1 and board.draft.size()==1,"Invalid occupied-cell contact is ignored without failing or removing valid progress")
	board.sample(Vector3.ZERO,false)
	var end:Dictionary=board.pairs[0].ends[0]
	check(board.sample(board.endpoint_position(end),true).action.is_empty() and board.wires.has(0),"Tracking reacquisition at endpoint cannot accidentally cut a wire")
	board.sample(Vector3(0,.3,0),true)
	check(board.sample(board.endpoint_position(end),true).action=="cut","Leaving contact shell rearms endpoint contact after tracking recovery")
	var bad:=fixture(3,2);bad.pairs[0].ends[0].face=[0,1,0]
	check(not Board.new().configure(bad),"Malformed non-wall endpoint fails closed")
	var grid:=Grid.new();root.add_child(grid);var board5:=Board.new();board5.configure(fixture(5,4));grid.configure(board5)
	check(grid.lattice.multimesh.instance_count==108 and grid.endpoints.multimesh.instance_count==8,"Largest lattice renders bounded mesh instances with eight labeled endpoints")
	for direction in [Vector3.RIGHT,Vector3.UP,Vector3.FORWARD]:
		var tube:Transform3D=grid.segment(Vector3.ZERO,direction*.1,.005)
		check((tube*Vector3(0,-.5,0)).is_equal_approx(Vector3.ZERO) and (tube*Vector3(0,.5,0)).is_equal_approx(direction*.1),"Pipe geometry scales along its local axis and reaches both adjacent cell centers")
	grid.free();await process_frame
	print(JSON.stringify({"checks":checks,"errors":errors,"authority":"local preview only","renderer":"dummy","tracking":"synthetic","headset_validated":false}));quit(0 if errors.is_empty() else 1)
