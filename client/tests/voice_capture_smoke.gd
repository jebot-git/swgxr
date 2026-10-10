extends SceneTree
## Opt-in Linux integration test: feed speech into the named virtual source.
## PULSE_SOURCE must also name it so driver fallback cannot open hardware.
class Probe extends "res://scripts/voice_codec.gd":
	var input_peak:=0.0
	func encode_pcm(pcm:PackedVector2Array)->void:
		for sample in pcm:input_peak=maxf(input_peak,sample.length())
		super.encode_pcm(pcm)
var failures:Array[String]=[]
var packets:=0
var peak:=0.0
func check(ok:bool,label:String)->void:
	if not ok:failures.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	if OS.get_environment("PULSE_SOURCE")!="swgxr_voice_regression_input":
		push_error("Set PULSE_SOURCE=swgxr_voice_regression_input; refusing default microphone capture.");quit(2);return
	check(ProjectSettings.get_setting("audio/driver/enable_input",false),"Project permits explicit capture")
	var selected:=""
	for device:String in AudioServer.get_input_device_list():
		if device=="swgxr_voice_regression_input":selected=device
	if selected.is_empty():
		push_error("Synthetic monitor source required; refusing microphone capture. Devices: "+str(AudioServer.get_input_device_list()));quit(2);return
	var codec=Probe.new();root.add_child(codec)
	codec.set_input_device(selected)
	codec.encoded_frame.connect(func(_packet:PackedByteArray):packets+=1)
	await create_timer(.1).timeout
	check(not codec.capture_enabled and not codec.transmitting and AudioServer.get_input_frames_available()==0,"Input remains off before explicit activation")
	codec.set_capture_enabled(true)
	check(codec.capture_enabled,"Synthetic monitor opens through production capture path: "+codec.status)
	await create_timer(.25).timeout
	check(packets==0,"Open input cannot emit before push-to-talk")
	codec.set_transmitting(true)
	for i in range(100):
		await create_timer(.02).timeout
		peak=maxf(peak,codec.level)
	check(peak>.001 and packets>10,"Captured synthetic PCM reaches native RNNoise and Opus")
	codec.set_capture_enabled(false)
	var stopped:=packets
	await create_timer(.1).timeout
	check(not codec.capture_enabled and not codec.transmitting and packets==stopped,"Mute closes capture and emission")
	var codec_input_peak:float=codec.input_peak
	codec.shutdown();codec.free()
	print(JSON.stringify({"passed":failures.is_empty(),"failures":failures,"driver":AudioServer.get_driver_name(),"source":selected,"packets":packets,"peak":peak,"input_peak":codec_input_peak,"hardware_microphone":false,"xr":false}))
	quit(0 if failures.is_empty() else 1)
