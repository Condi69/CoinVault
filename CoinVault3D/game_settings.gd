extends RefCounted

const ACTIONS := ["move_forward","move_back","move_left","move_right","jump","sprint","collect","interact","pause_game","skill_tree"]
const NAMES := {"move_forward":"Move forward","move_back":"Move backward","move_left":"Move left","move_right":"Move right","jump":"Jump","sprint":"Sprint (hold)","collect":"Collect coins (hold)","interact":"Deposit coins","pause_game":"Pause menu","skill_tree":"Open skill tree"}
var path := "user://preferences.cfg"
var bindings: Dictionary = {}
var options: Dictionary = {}

func _init() -> void:
	reset_bindings()
	options=default_options()

func default_options() -> Dictionary:
	return {"sensitivity":1.0,"invert_y":false,"fov":78.0,"crosshair":true,"show_fps":false,"coin_detail":0,"effects_quality":0,"sfx_enabled":true,"sfx_volume":0.6,"window_mode":0,"window_width":1280,"window_height":720,"vsync":true,"fps_limit":0,"msaa":0}

func reset_bindings() -> void:
	bindings={}
	var keys:=[KEY_W,KEY_S,KEY_A,KEY_D,KEY_SPACE,KEY_SHIFT,0,KEY_E,KEY_ESCAPE,KEY_Q]
	for index in range(ACTIONS.size()):
		bindings[ACTIONS[index]]={"kind":"mouse" if ACTIONS[index]=="collect" else "key","code":MOUSE_BUTTON_LEFT if ACTIONS[index]=="collect" else keys[index],"ctrl":false,"alt":false,"shift":false}

func load_preferences() -> void:
	var config:=ConfigFile.new()
	if config.load(path)!=OK:return
	for action in ACTIONS:
		var value=config.get_value("controls",action,bindings[action])
		if value is Dictionary and _valid_binding(value) and not (action!="pause_game" and value.kind=="key" and value.code==KEY_ESCAPE):bindings[action]=value.duplicate()
	for key in options:
		var value=config.get_value("settings",key,options[key])
		if typeof(value)==typeof(options[key]) or (value is int and options[key] is float):options[key]=value
	_sanitize_options()
	# A damaged preference file must not leave actions sharing a binding.
	for index in range(ACTIONS.size()):
		for other in range(index):
			if same_binding(bindings[ACTIONS[index]],bindings[ACTIONS[other]]):
				reset_bindings()
				return

func _sanitize_options() -> void:
	options.sensitivity=clampf(float(options.sensitivity),0.25,3.0)
	options.fov=clampf(float(options.fov),60.0,100.0)
	options.effects_quality=clampi(int(options.effects_quality),0,2)
	options.sfx_volume=clampf(float(options.sfx_volume),0,1)
	options.coin_detail=clampi(int(options.coin_detail),0,2)
	options.msaa=clampi(int(options.msaa),0,3)
	options.window_mode=clampi(int(options.window_mode),0,2)
	options.window_width=clampi(int(options.window_width),640,3840)
	options.window_height=clampi(int(options.window_height),360,2160)
	if not int(options.fps_limit) in [0,30,60,90,120,144,165,240]:options.fps_limit=0

func save_preferences() -> Error:
	var config:=ConfigFile.new()
	for action in ACTIONS:config.set_value("controls",action,bindings[action])
	for key in options:config.set_value("settings",key,options[key])
	return config.save(path)

func _valid_binding(value:Dictionary) -> bool:
	if not value.has("kind") or not value.has("code"):return false
	if value.kind=="key":return value.code is int and value.code>0 and value.code!=KEY_META
	return value.kind=="mouse" and value.code in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE,MOUSE_BUTTON_XBUTTON1,MOUSE_BUTTON_XBUTTON2]

func same_binding(a:Dictionary,b:Dictionary) -> bool:
	return a.kind==b.kind and a.code==b.code and bool(a.get("ctrl",false))==bool(b.get("ctrl",false)) and bool(a.get("alt",false))==bool(b.get("alt",false)) and bool(a.get("shift",false))==bool(b.get("shift",false))

func binding_from_event(event:InputEvent) -> Dictionary:
	var binding:Dictionary={}
	if event is InputEventKey:
		var code:int=event.physical_keycode if event.physical_keycode!=0 else event.keycode
		if code==KEY_ESCAPE or code==KEY_META or event.meta_pressed or (event.alt_pressed and code in [KEY_TAB,KEY_F4]):return {}
		binding={"kind":"key","code":code,"ctrl":event.ctrl_pressed and code!=KEY_CTRL,"alt":event.alt_pressed and code!=KEY_ALT,"shift":event.shift_pressed and code!=KEY_SHIFT}
	elif event is InputEventMouseButton:
		binding={"kind":"mouse","code":event.button_index,"ctrl":event.ctrl_pressed,"alt":event.alt_pressed,"shift":event.shift_pressed}
	return binding if not binding.is_empty() and _valid_binding(binding) else {}

func rebind(action:String,binding:Dictionary) -> String:
	if not ACTIONS.has(action) or not _valid_binding(binding):return ""
	var swapped:=""
	for other in ACTIONS:
		if other!=action and same_binding(bindings[other],binding):
			bindings[other]=bindings[action].duplicate()
			swapped=other
			break
	bindings[action]=binding.duplicate()
	apply_bindings()
	return swapped

func apply_bindings() -> void:
	for action in ACTIONS:
		if not InputMap.has_action(action):InputMap.add_action(action)
		InputMap.action_erase_events(action)
		var binding:Dictionary=bindings[action]
		var event:InputEventWithModifiers
		if binding.kind=="key":
			var key:=InputEventKey.new()
			key.physical_keycode=binding.code
			event=key
		else:
			var button:=InputEventMouseButton.new()
			button.button_index=binding.code
			event=button
		event.ctrl_pressed=binding.get("ctrl",false)
		event.alt_pressed=binding.get("alt",false)
		event.shift_pressed=binding.get("shift",false)
		InputMap.action_add_event(action,event)

func binding_label(action:String) -> String:
	var binding:Dictionary=bindings[action]
	var label:=""
	if binding.get("ctrl",false):label+="Ctrl + "
	if binding.get("alt",false):label+="Alt + "
	if binding.get("shift",false):label+="Shift + "
	if binding.kind=="key":return label+OS.get_keycode_string(binding.code)
	var names:={MOUSE_BUTTON_LEFT:"Left Mouse",MOUSE_BUTTON_RIGHT:"Right Mouse",MOUSE_BUTTON_MIDDLE:"Middle Mouse",MOUSE_BUTTON_XBUTTON1:"Mouse 4",MOUSE_BUTTON_XBUTTON2:"Mouse 5"}
	return label+names.get(binding.code,"Mouse")

func apply_to_game(game:Node, apply_display:bool=true) -> void:
	_sanitize_options()
	game.apply_coin_detail()
	game.apply_scene_quality(int(options.effects_quality))
	if game.feedback!=null:game.feedback.configure(options)
	game.mouse_sensitivity=0.002*float(options.sensitivity)
	game.camera.fov=options.fov
	game.hud_view.set_fps_visible(bool(options.show_fps))
	for bar in game.crosshair_bars:bar.visible=options.crosshair
	game.crosshair_dot.visible=options.crosshair
	game.get_viewport().msaa_3d=options.msaa
	Engine.max_fps=options.fps_limit
	if not apply_display:return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if options.vsync else DisplayServer.VSYNC_DISABLED)
	var modes:=[DisplayServer.WINDOW_MODE_WINDOWED,DisplayServer.WINDOW_MODE_FULLSCREEN,DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
	var mode:int=modes[options.window_mode]
	if DisplayServer.window_get_mode()!=mode:DisplayServer.window_set_mode(mode)
	if options.window_mode==0:
		var screen:=DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
		var requested:=Vector2i(mini(options.window_width,screen.size.x),mini(options.window_height,screen.size.y))
		if DisplayServer.window_get_size()!=requested:
			DisplayServer.window_set_size(requested)
			DisplayServer.window_set_position(screen.position+Vector2i((screen.size-requested)/2.0))

func preset_values(index:int) -> Dictionary:
	return {"coin_detail":clampi(index,0,2),"msaa":[0,1,2][clampi(index,0,2)],"effects_quality":clampi(index,0,2)}

func detect_preset(values:Dictionary) -> int:
	for index in range(3):
		var preset := preset_values(index)
		if int(values.coin_detail)==preset.coin_detail and int(values.msaa)==preset.msaa and int(values.effects_quality)==preset.effects_quality:return index
	return -1

