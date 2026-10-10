extends RefCounted
## StarAppearance's count-seeded ran1 stream and first-row colour ramp.
## Rasterised into a fixed angular cube; SWG used two-pixel point sprites.
const SIZE:=1024
var seed_value:int
var value:int
var table:Array[int]=[]
func seed_stream(count:int)->void:
	seed_value=maxi(1,absi(count));table.resize(32)
	for i in range(39,-1,-1):
		seed_value=seed_value*16807%2147483647
		if i<32:table[i]=seed_value
	value=table[0]
func random_real()->float:
	seed_value=seed_value*16807%2147483647
	var index:=int(value/67108864)
	value=table[index];table[index]=seed_value
	return minf(float(value)/2147483647.0,1.0-1.2e-7)
static func projection(d:Vector3)->Vector3:
	var a:=d.abs();var uv:Vector2;var face:int
	if a.x>=a.y and a.x>=a.z:
		face=3 if d.x>0 else 2;uv=Vector2(d.z if d.x>0 else -d.z,-d.y)/a.x
	elif a.y>=a.z:
		face=4 if d.y>0 else 5;uv=Vector2(d.x,-d.z if d.y>0 else d.z)/a.y
	else:
		face=0 if d.z<0 else 1;uv=Vector2(d.x if d.z<0 else -d.x,-d.y)/a.z
	return Vector3(uv.x*.5+.5,uv.y*.5+.5,face)
func build(count:int,ramp:Texture2D)->Cubemap:
	seed_stream(count)
	var images:Array[Image]=[]
	for face in range(6):images.append(Image.create(SIZE,SIZE,false,Image.FORMAT_RGBA8))
	var colors:Image=ramp.get_image() if ramp!=null else null
	for i in range(count):
		var color:=colors.get_pixel(i%colors.get_width(),0) if colors!=null else Color.WHITE
		color.a*=random_real()
		var z:=random_real()*2-1;var angle:=random_real()*TAU;var r:=sqrt(maxf(0,1-z*z))
		var uv:=projection(Vector3(r*cos(angle),r*sin(angle),-z))
		var target:Image=images[int(uv.z)]
		var x:=clampi(int(uv.x*SIZE),0,SIZE-1);var y:=clampi(int(uv.y*SIZE),0,SIZE-1)
		# Additive source stars, including their authored/seeded alpha.
		var previous:=target.get_pixel(x,y)
		target.set_pixel(x,y,Color(minf(1,previous.r+color.r*color.a),minf(1,previous.g+color.g*color.a),minf(1,previous.b+color.b*color.a),1))
	for source:Image in images:source.generate_mipmaps()
	var faces:Array[Image]=[images[3],images[2],images[4],images[5],images[0],images[1]]
	var result:=Cubemap.new();result.create_from_images(faces);return result
