extends RefCounted
## Symmetric, release-armed chord; a lone main trigger returns to ordinary combat.
var armed:=false
var consumed:=false
var waiting:=false
var age:=0.0
var capturing:=false
func clear()->void:armed=false;consumed=false;waiting=false;age=0;capturing=false
func sample(delta:float,main:float,support:float,permitted:bool)->bool:
	capturing=false
	if not permitted or not is_finite(delta) or delta<=0 or delta>.1 or not is_finite(main) or not is_finite(support):clear();return false
	if main<.2 and support<.2:armed=true;consumed=false;waiting=false;age=0;return false
	if consumed:capturing=true;return false
	var down:bool=main>=.75;var off:bool=support>=.75
	if armed and (down or off):
		if waiting:age+=delta
		else:waiting=true;age=0
		if down and off and age<=.12:consumed=true;armed=false;capturing=true;return true
		if age>=.12:armed=false;waiting=false
		else:capturing=true;return false
	capturing=off
	return false
