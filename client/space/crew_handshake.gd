extends RefCounted
## A distinct, native launch-bound proof. This never creates a party or payment.
var submitted:Dictionary={}
func reset()->void:submitted.clear()
func take_ready(owner:String,records:Array)->Dictionary:
	for peer:Dictionary in records:
		var pilot:=str(peer.get("id",""));var launch:=str(peer.get("crew_launch_id",""));var proof:=str(peer.get("crew_handshake_id",""))
		if not peer.get("crew_handshake_ready",false) or pilot==owner or not pilot.is_valid_int() or int(pilot)<=0 or launch.is_empty():continue
		if proof.length()!=24 or not proof.is_valid_hex_number() or submitted.has(proof):continue
		submitted[proof]=true
		while submitted.size()>64:submitted.erase(submitted.keys()[0])
		return {"pilot_id":pilot,"launch_id":launch,"crew_handshake_id":proof,"request_id":"crew_"+proof}
	return {}
