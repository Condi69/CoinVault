extends Node
var game
var voices: Array[AudioStreamPlayer] = []
var clips: Dictionary = {}
var voice_cursor := 0
var last_pickup_ms := -1000
var last_conveyor_ms := -1000
var enabled := true
var level := 0.6

func _ready() -> void:
	clips.pickup=_tone([1440.0,2310.0,3180.0],0.12)
	clips.conveyor=_tone([90.0,145.0,230.0],0.09)
	clips.deposit=_tone([660.0,990.0,1320.0],0.28)
	clips.upgrade=_tone([880.0,1100.0,1760.0],0.24)
	for i in range(3):
		var voice := AudioStreamPlayer.new()
		voice.max_polyphony=1
		add_child(voice)
		voices.append(voice)

func _tone(frequencies:Array,duration:float) -> AudioStreamWAV:
	var rate := 22050
	var frames := int(rate*duration)
	var bytes := PackedByteArray()
	bytes.resize(frames*2)
	for i in range(frames):
		var t := float(i)/rate
		var envelope := minf(1,t*500)*exp(-t*22)*(1.0-t/duration)
		var sample := 0.0
		for harmonic in range(frequencies.size()):
			sample+=sin(TAU*float(frequencies[harmonic])*t)*envelope/(2.5+harmonic)
		bytes.encode_s16(i*2,int(clampf(sample,-1,1)*22000))
	var stream := AudioStreamWAV.new()
	stream.format=AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate=rate
	stream.stereo=false
	stream.data=bytes
	return stream

func configure(options:Dictionary) -> void:
	enabled=bool(options.sfx_enabled)
	level=float(options.sfx_volume)
	if not enabled or level<=0:
		for voice in voices:voice.stop()

func play(cue:String) -> void:
	if not enabled or level<=0 or not clips.has(cue):return
	var now := Time.get_ticks_msec()
	if cue=="pickup":
		if now-last_pickup_ms<75:return
		last_pickup_ms=now
	if cue=="conveyor":
		if now-last_conveyor_ms<250:return
		last_conveyor_ms=now
	var voice: AudioStreamPlayer=voices[voice_cursor]
	voice_cursor=(voice_cursor+1)%voices.size()
	voice.stream=clips[cue]
	voice.volume_db=linear_to_db(level*(0.07 if cue=="conveyor" else 0.45))
	voice.pitch_scale=1.0+float(voice_cursor-1)*0.035 if cue=="pickup" else 1.0
	voice.play()

func scoop(amount:int,full:bool) -> void:
	game.hud_view.show_scoop(amount,full)
	play("pickup")

func deposit(amount:int) -> void:
	game.hud_view.show_deposit(amount)
	play("deposit")
