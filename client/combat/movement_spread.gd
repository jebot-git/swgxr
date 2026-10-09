extends RefCounted
## Movement changes the emitted bolt direction, never tracking or damage rolls.
const FULL_SPEED := 5.0
const DEAD_ZONE := 0.15
var speed := 0.0
var previous_head := Vector3.INF
var rng := RandomNumberGenerator.new()
func _init() -> void: rng.randomize()
func sample(velocity: Vector3, local_head: Vector3, delta: float, tracked: bool) -> void:
 if not tracked or not velocity.is_finite() or not local_head.is_finite() or not is_finite(delta) or delta <= 0 or delta > .25:
  speed=0;previous_head=Vector3.INF;return
 var room_speed:=0.0
 if previous_head.is_finite():
  var travel:=local_head-previous_head;travel.y=0
  # Recenter/teleport is not physical movement evidence.
  if travel.length()/delta<=10:room_speed=travel.length()/delta
 previous_head=local_head
 speed=minf(10,maxf(Vector2(velocity.x,velocity.z).length(),room_speed))
static func maximum(profile: Dictionary) -> float:
 var family:=str(profile.get("class",""));var path:=str(profile.get("template",""))
 if profile.get("native_family","")=="commando":return 0.0 if profile.get("commando_family","")=="pistol_launcher" else 6.0
 if family in ["holdout","pistol","heavy_pistol"] or "/pistol/" in path:return 0.0
 if family in ["carbine","burst_carbine"] or "/carbine/" in path:return 1.2
 if family in ["heavy","heavy_weapon","repeater"] or "/heavy/" in path:return 6.0
 if int(profile.get("hands",1))==2 or "/rifle/" in path:return 4.0
 return 0.0
func degrees(profile: Dictionary) -> float:
 return maximum(profile)*clampf((speed-DEAD_ZONE)/(FULL_SPEED-DEAD_ZONE),0,1)
static func cone(direction: Vector3, half_angle: float, radial: float, azimuth: float) -> Vector3:
 if half_angle<=0:return direction.normalized()
 var forward:=direction.normalized()
 var basis:=Basis.looking_at(forward,Vector3.RIGHT if absf(forward.y)>.99 else Vector3.UP)
 var cosine:=lerpf(1.0,cos(deg_to_rad(half_angle)),clampf(radial,0,1))
 var sine:=sqrt(maxf(0,1-cosine*cosine));var angle:=azimuth*TAU
 return (basis.x*sine*cos(angle)+basis.y*sine*sin(angle)+forward*cosine).normalized()
func apply(pose: Transform3D, profile: Dictionary) -> Transform3D:
 var angle:=degrees(profile)
 if angle>0:
  var direction:=cone(-pose.basis.z,angle,rng.randf(),rng.randf())
  pose.basis=Basis.looking_at(direction,Vector3.RIGHT if absf(direction.y)>.99 else Vector3.UP)
 return pose
