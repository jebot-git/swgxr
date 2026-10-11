extends RefCounted
## Same native grip capture and hand attachment semantics as ground vehicles.
var native:=SwgVehicleControls.new()
var state:Dictionary={}
var throttle:=0.0
var style:="yoke"
func reset()->void:
 native.reset();state={};throttle=0
func transform(pivot:Vector3)->Transform3D:
 var rotation:=Basis(Vector3.UP,float(state.get("yaw_angle",0)))*Basis(Vector3.BACK,float(state.get("wheel_angle",0)))
 var depth:=float(state.get("throttle_offset",0))
 if style=="stick":
  rotation=rotation*Basis(Vector3.RIGHT,depth/.18*.55)
  depth=0
 return Transform3D(rotation,pivot-rotation*pivot+Vector3(0,0,depth))
func sample(settings:RefCounted,frame:Transform3D,grips:Array,left:Transform3D,right:Transform3D,lg:float,rg:float,tracked:bool,stick:Vector2,delta:float,control_style:String="yoke")->Dictionary:
 style=control_style
 if style=="stick":
  # A central stick has one handhold. Preserve its current owner until released.
  if state.get("right_held",false) and rg>=.25:lg=0
  elif state.get("left_held",false) and lg>=.25:rg=0
  elif rg>.65:lg=0
 state=native.sample("flight_stick" if style=="stick" else "flight",frame,left,right,grips[0],grips[1],lg,rg,tracked,tracked,tracked)
 var output:Dictionary={"pitch":0.0,"yaw":0.0,"roll":0.0,"throttle":0.0}
 if not state.held:return output
 # SWG forward is +Z: negative pitch raises the nose; negative yaw turns left.
 output.pitch=settings.axis(-float(state.pitch),"pitch")
 output.yaw=settings.axis(-float(state.yaw),"yaw")
 output.roll=settings.axis(float(state.roll),"roll")
 throttle=clampf(throttle+settings.axis(stick.y,"throttle")*clampf(delta,0,.1)*.5,0,1)
 output.throttle=throttle
 return output
func hand_target(side:String,scene:Node3D)->Variant:
 if not state.get(side+"_held",false) or not is_instance_valid(scene.control_node):return null
 var point:Vector3=scene.control_grips()[0 if side=="left" else 1]
 return scene.control_node.global_transform*Transform3D(Basis(Vector3.RIGHT,PI/2),point)
func update_visual(scene:Node3D)->void:
 if is_instance_valid(scene.control_node):scene.control_node.transform=transform(scene.control_pivot())
