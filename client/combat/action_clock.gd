extends RefCounted
## Four timestamps remove native processing time from the clock estimate.
var offset:=0.0
var best_delay:=INF
var ready:=false
var refreshed_at:=0.0
func observe(local_sent:float,server_received:float,server_sent:float,local_received:float)->bool:
	if not is_finite(server_received) or not is_finite(server_sent) or server_sent<server_received or local_received<local_sent:return false
	var delay:=maxf(0,(local_received-local_sent)-(server_sent-server_received))
	if local_received-refreshed_at>30:best_delay=INF;refreshed_at=local_received
	if delay>best_delay:return false
	best_delay=delay;offset=((server_received-local_sent)+(server_sent-local_received))*.5;ready=true;return true
