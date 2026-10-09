extends PanelContainer
## Compact channel controls shared by the underside wrist display and desktop harness.
signal channel_requested(channel: String)
signal mode_requested(mode: String)
signal ptt_changed(held: bool)
const CHANNELS := {"proximity":"PROX","group":"GROUP","planet":"PLANET","sector":"SECTOR","faction":"FACTION"}
var state: Dictionary={"granted_channels":["proximity"],"reasons":{},"active_channel":"proximity","mic_mode":"muted","connected":false,"transmitting":false}
var buttons: Dictionary={}
var mode_buttons: Dictionary={}
var status: Label
var detail: Label
var talk: Button
var active := false
var blocked_reason := "Voice unavailable outside the world"
var hovered := ""
func _ready() -> void:
	theme=preload("res://scripts/datapad_theme.gd").build()
	add_theme_stylebox_override("panel",preload("res://scripts/datapad_theme.gd").frame(28,"wide"))
	custom_minimum_size=Vector2(640,320);size=custom_minimum_size
	var rows:=VBoxContainer.new();rows.add_theme_constant_override("separation",8);add_child(rows)
	status=Label.new();status.add_theme_font_size_override("font_size",24);rows.add_child(status)
	var channels:=HBoxContainer.new();rows.add_child(channels)
	for channel in CHANNELS:
		var button:=Button.new();button.text=CHANNELS[channel];button.toggle_mode=true;button.custom_minimum_size.y=48
		button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;button.focus_mode=Control.FOCUS_NONE
		button.pressed.connect(func():activate("channel:"+channel));channels.add_child(button);buttons[channel]=button
	var modes:=HBoxContainer.new();rows.add_child(modes)
	for mode in ["muted","vox","ptt"]:
		var button:=Button.new();button.text={"muted":"MIC OFF","vox":"VOICE ACTIVITY","ptt":"PUSH TO TALK"}[mode]
		button.add_theme_font_size_override("font_size",18);button.toggle_mode=true;button.custom_minimum_size.y=44
		button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;button.focus_mode=Control.FOCUS_NONE
		button.pressed.connect(func():activate("mode:"+mode));modes.add_child(button);mode_buttons[mode]=button
	talk=Button.new();talk.text="HOLD TO TALK";talk.custom_minimum_size.y=46;talk.focus_mode=Control.FOCUS_NONE
	talk.button_down.connect(func():if active and state.get("mic_mode")=="ptt":ptt_changed.emit(true))
	talk.button_up.connect(func():ptt_changed.emit(false));rows.add_child(talk)
	detail=Label.new();detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;detail.add_theme_font_size_override("font_size",18)
	detail.max_lines_visible=2;detail.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	detail.custom_minimum_size.y=42;detail.add_theme_color_override("font_color",Color("91bdcc"));rows.add_child(detail)
	refresh()
func apply_state(value: Dictionary) -> void:
	state=value.duplicate(true);refresh()
func set_active(value: bool, reason: String="") -> void:
	if active==value and blocked_reason==reason:return
	active=value;blocked_reason=reason
	if not active:ptt_changed.emit(false)
	refresh()
func refresh() -> void:
	if not is_instance_valid(status):return
	var channel:=str(state.get("desired_channel",state.get("active_channel","proximity")))
	var mode:=str(state.get("mic_mode","muted"))
	var mic:="TRANSMITTING" if state.get("transmitting",false) else ("MIC OFF" if mode=="muted" else "READY")
	if not state.get("context_confirmed",true):mic="UPDATING"
	elif not state.get("channel_confirmed",true):mic="UPDATING" if channel in state.get("granted_channels",[]) else "UNAVAILABLE"
	if not active:mic="PAUSED"
	status.text="VOICE  /  "+str(CHANNELS.get(channel,"PROX"))+"  ·  "+mic
	var space_scope:bool=state.get("scope","")=="sector" or "sector" in state.get("granted_channels",[])
	for key in buttons:
		buttons[key].visible=(not space_scope if key=="planet" else space_scope if key=="sector" else true)
		buttons[key].disabled=not active or not key in state.get("granted_channels",[])
		buttons[key].button_pressed=key==channel
		buttons[key].tooltip_text=str(state.get("reasons",{}).get(key,"Channel unavailable")) if buttons[key].disabled else ("This ship’s nearby crew · spatial · 64 m" if key=="proximity" and space_scope else "Nearby voices · spatial · 64 m" if key=="proximity" else "Current space sector · non-spatial" if key=="sector" else "Shared channel · non-spatial")
	for key in mode_buttons:
		mode_buttons[key].disabled=not active and key!="muted"
		mode_buttons[key].button_pressed=key==mode
	talk.disabled=not active or mode!="ptt" or not state.get("channel_confirmed",true)
	talk.text="HOLD TO TALK" if mode=="ptt" else ("MICROPHONE IS OFF" if mode=="muted" else "TRANSMIT WHEN SPEAKING")
	var message:=str(state.get("error",""))
	if not active:message=blocked_reason
	elif hovered.begins_with("channel:"):
		var key:=hovered.get_slice(":",1)
		if not key in state.get("granted_channels",[]):message=str(state.get("reasons",{}).get(key,"Channel unavailable"))
	if message.is_empty():message="Nearby voices · spatial · 64 m" if channel=="proximity" else "Shared channel · non-spatial"
	detail.text=message
func action_at(pixel: Vector2) -> String:
	for key in buttons:
		if buttons[key].visible and buttons[key].get_global_rect().has_point(pixel):return "channel:"+key
	for key in mode_buttons:
		if mode_buttons[key].get_global_rect().has_point(pixel):return "mode:"+key
	if talk.get_global_rect().has_point(pixel):return "talk"
	return ""
func set_hover(action: String) -> void:
	if hovered==action:return
	hovered=action;refresh()
func activate(action: String) -> void:
	if action.begins_with("channel:"):
		var key:=action.get_slice(":",1)
		if active and key in state.get("granted_channels",[]):channel_requested.emit(key)
	elif action.begins_with("mode:"):
		var mode:=action.get_slice(":",1)
		if mode in mode_buttons and (active or mode=="muted"):mode_requested.emit(mode)
