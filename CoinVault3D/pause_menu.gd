extends CanvasLayer

var game
var settings
var is_open := false
var page := "main"
var root_control: Control
var panel: PanelContainer
var content: VBoxContainer
var preferred_size := Vector2(460,380)
var draft: Dictionary = {}
var previous_display: Dictionary = {}
var display_seconds := 0.0
var display_label: Label
var pending_binding := ""
var pending_modifier: InputEventKey
var binding_buttons: Dictionary = {}
var status_label: Label
var resolution_control: OptionButton

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	layer=100
	root_control=Control.new()
	root_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_control.theme=_make_theme()
	add_child(root_control)
	var shade:=ColorRect.new()
	shade.color=Color(0.025,0.035,0.028,0.86)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter=Control.MOUSE_FILTER_STOP
	root_control.add_child(shade)
	var center:=CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_control.add_child(center)
	panel=PanelContainer.new()
	center.add_child(panel)
	var margin:=MarginContainer.new()
	for edge in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+edge,20)
	panel.add_child(margin)
	content=VBoxContainer.new()
	content.add_theme_constant_override("separation",10)
	margin.add_child(content)
	root_control.resized.connect(_layout_panel)
	_show_main()
	visible=false

func _make_theme() -> Theme:
	var theme:=Theme.new()
	var font:=SystemFont.new()
	font.font_names=PackedStringArray(["Bahnschrift","DejaVu Sans"])
	theme.default_font=font
	theme.default_font_size=17
	theme.set_color("font_color","Label",Color("e3ddc3"))
	var frame:=StyleBoxFlat.new()
	frame.bg_color=Color("242e27")
	frame.border_color=Color("8d8056")
	frame.set_border_width_all(2)
	frame.set_corner_radius_all(9)
	frame.shadow_color=Color(0,0,0,0.5)
	frame.shadow_size=10
	theme.set_stylebox("panel","PanelContainer",frame)
	for state in ["normal","hover","pressed","focus","disabled"]:
		var style:=StyleBoxFlat.new()
		style.bg_color=Color("344237") if state=="hover" else Color("19251e")
		style.border_color=Color("e2be69") if state in ["hover","focus"] else Color("5e674e")
		style.set_border_width_all(1)
		style.set_corner_radius_all(5)
		style.content_margin_left=12
		style.content_margin_right=12
		style.content_margin_top=7
		style.content_margin_bottom=7
		theme.set_stylebox(state,"Button",style)
		theme.set_stylebox(state,"OptionButton",style)
	for kind in ["Button","OptionButton","CheckButton"]:
		theme.set_color("font_color",kind,Color("eddb9f"))
		theme.set_color("font_hover_color",kind,Color("fff1bf"))
	return theme

func _layout_panel() -> void:
	if panel==null:return
	panel.custom_minimum_size=Vector2(minf(preferred_size.x,maxf(280,root_control.size.x-32)),minf(preferred_size.y,maxf(240,root_control.size.y-32)))

func _begin(title:String,caption:String,width:float=660,height:float=620) -> void:
	pending_binding=""
	pending_modifier=null
	binding_buttons.clear()
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	preferred_size=Vector2(width,height)
	_layout_panel()
	var heading:=Label.new()
	heading.text=title
	heading.add_theme_font_size_override("font_size",30)
	heading.add_theme_color_override("font_color",Color("f0cd7b"))
	content.add_child(heading)
	if caption!="":
		var subtitle:=_text(caption,14)
		subtitle.modulate=Color("b4baa2")
		content.add_child(subtitle)
	var divider:=ColorRect.new()
	divider.color=Color("667052")
	divider.custom_minimum_size.y=1
	content.add_child(divider)

func _text(value:String,size:int=17) -> Label:
	var label:=Label.new()
	label.text=value
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size",size)
	return label

func _button(value:String,callback:Callable,parent:Node=null) -> Button:
	if parent==null:parent=content
	var button:=Button.new()
	button.text=value
	button.custom_minimum_size.y=40
	button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _scroll_body() -> VBoxContainer:
	var scroll:=ScrollContainer.new()
	scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var body:=VBoxContainer.new()
	body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",12)
	scroll.add_child(body)
	return body

func _show_main() -> void:
	if not game.run_active:
		close_menu()
		return
	page="main"
	_begin("PAUSED",("COIN VAULT / SLOT %d" % game.active_slot)+(" / SAVED" if game.last_save_error=="" else ""),510,500)
	if game.last_save_error!="":content.add_child(_text("SAVE FAILED: "+game.last_save_error,15))
	var resume:=_button("RESUME",close_menu)
	_button("HELP & CONTROLS",_show_help)
	_button("SETTINGS",func():_show_settings("controls",true))
	_button("UNSTUCK / RETURN TO TOP",func():
		game.unstuck_player()
		game.save_run()
		close_menu()
	)
	_button("SAVE GAME",func():
		game.save_run()
		_show_main()
	)
	_button("SAVE & TITLE SCREEN",game.return_to_title)
	_button("SAVE & QUIT",_show_quit)
	if is_open:_focus_when_ready.call_deferred(resume)

func _focus_when_ready(button:Button) -> void:
	if is_instance_valid(button) and button.is_inside_tree() and button.is_visible_in_tree():button.grab_focus()

func open_menu() -> void:
	if is_open:return
	if game.run_active:game.save_run()
	is_open=true
	visible=true
	game._cancel_pickup()
	if game.upgrade_overlay.visible:game.upgrade_overlay.visible=false
	game.player.velocity=Vector3.ZERO
	game.hud_view.get_parent().visible=false
	get_tree().paused=true
	Engine.max_fps=mini(60,int(settings.options.fps_limit)) if int(settings.options.fps_limit)>0 else 60
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	if game.run_active:_show_main()

func close_menu() -> void:
	if not game.window_focused:return
	if not previous_display.is_empty():_revert_display(false)
	cancel_binding()
	is_open=false
	visible=false
	game._cancel_pickup()
	for action in settings.ACTIONS:Input.action_release(action)
	get_tree().paused=false
	Engine.max_fps=int(settings.options.fps_limit) if game.run_active else 30
	game.hud_view.get_parent().visible=game.run_active
	game.mouse_released=false
	game._sync_mouse_capture()

func _show_help() -> void:
	page="help"
	_begin("HELP & CONTROLS","Your current controls",650,640)
	var body:=_scroll_body()
	body.add_child(_text("Move the mouse to look around. Aim at a coin and hold the collect button. Bank your bag at the deposit station, then open the skill tree to spend your balance on skills."))
	for action in settings.ACTIONS:
		var row:=HBoxContainer.new()
		var caption:=_text(settings.NAMES[action])
		caption.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		row.add_child(caption)
		var binding:=Label.new()
		binding.text=settings.binding_label(action)+(" / Esc" if action=="pause_game" and settings.binding_label(action)!="Escape" else "")
		binding.add_theme_color_override("font_color",Color("f0cd7b"))
		row.add_child(binding)
		body.add_child(row)
	body.add_child(_text("Drag the skill tree with the mouse and use the wheel to zoom. Click an icon to buy; hover for its effect, price and requirements. Learned skills reveal only their immediate next choices. Large hexagons are milestone rewards. Coins removed by hand or conveyors count toward milestones. Deposit bonuses do not.",15))
	body.add_child(_text("Esc always opens the pause menu or takes you back. You can change the controls and mouse sensitivity in Settings.",15))
	_button("BACK",_show_main)

func _show_settings(tab:String="controls",reset_draft:bool=true) -> void:
	page="settings"
	if reset_draft:draft=settings.options.duplicate(true)
	_begin("SETTINGS","Controls save when changed. Use Apply for the other settings.",720,660)
	var tabs:=HBoxContainer.new()
	content.add_child(tabs)
	_button("MOUSE & CONTROLS",func():_show_settings("controls",false),tabs)
	_button("DISPLAY",func():_show_settings("display",false),tabs)
	var body:=_scroll_body()
	if tab=="controls":_build_controls(body)
	else:_build_display(body)
	status_label=_text("",14)
	status_label.custom_minimum_size.y=22
	content.add_child(status_label)
	var footer:=HBoxContainer.new()
	content.add_child(footer)
	_button("APPLY",_apply_settings,footer)
	_button("DEFAULT OPTIONS",func():
		draft=settings.default_options()
		_show_settings(tab,false)
		status_label.text="Default options selected. Press Apply to use them."
	,footer)
	_button("BACK",_show_main,footer)

func _row(caption:String,parent:Node) -> HBoxContainer:
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",12)
	var label:=_text(caption)
	label.custom_minimum_size.x=190
	label.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	parent.add_child(row)
	return row

func _slider(caption:String,key:String,minimum:float,maximum:float,step:float,parent:Node,percent:bool=false) -> void:
	var row:=_row(caption,parent)
	var slider:=HSlider.new()
	slider.min_value=minimum
	slider.max_value=maximum
	slider.step=step
	slider.set_meta("setting",key)
	slider.value=draft[key]
	slider.custom_minimum_size=Vector2(140,32)
	slider.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var value:=Label.new()
	value.custom_minimum_size.x=62
	value.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	value.text=("%d%%"%int(slider.value*100)) if percent else ("%d°"%int(slider.value))
	slider.value_changed.connect(func(next:float):
		draft[key]=next
		value.text=("%d%%"%int(next*100)) if percent else ("%d°"%int(next))
	)

func _toggle(caption:String,key:String,parent:Node) -> void:
	var toggle:=CheckButton.new()
	toggle.text=caption
	toggle.set_meta("setting",key)
	toggle.button_pressed=draft[key]
	toggle.custom_minimum_size.y=34
	toggle.toggled.connect(func(value:bool):draft[key]=value)
	parent.add_child(toggle)

func _build_controls(body:VBoxContainer) -> void:
	_toggle("Sound effects","sfx_enabled",body)
	_slider("Effects volume","sfx_volume",0.0,1.0,0.05,body,true)
	_slider("Mouse sensitivity","sensitivity",0.25,3.0,0.05,body,true)
	_toggle("Invert vertical mouse look","invert_y",body)
	_slider("Field of view","fov",60,100,1,body)
	_toggle("Show crosshair","crosshair",body)
	body.add_child(_text("KEY & MOUSE BINDINGS",17))
	body.add_child(_text("Choose a binding, then press a key or mouse button. Esc cancels. If a binding is already used, the two actions swap.",14))
	for action in settings.ACTIONS:
		var row:=_row(settings.NAMES[action],body)
		var button:=_button(settings.binding_label(action),func():_begin_binding(action),row)
		button.custom_minimum_size.x=180
		binding_buttons[action]=button
	_button("RESET CONTROLS",func():
		settings.reset_bindings()
		settings.apply_bindings()
		var error:int=settings.save_preferences()
		_refresh_binding_buttons()
		status_label.text="Default controls restored." if error==OK else "Controls restored for this session; saving failed."
	,body)

func _build_display(body:VBoxContainer) -> void:
	var preset_row := _row("Graphics preset",body)
	var preset := OptionButton.new()
	for caption in ["Custom","Low","Balanced","High"]:preset.add_item(caption)
	preset.selected=settings.detect_preset(draft)+1
	preset.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	preset_row.add_child(preset)
	preset.item_selected.connect(func(index:int):
		if index==0:return
		var values: Dictionary=settings.preset_values(index-1)
		for key in values:draft[key]=values[key]
		_show_settings("display",false)
		status_label.text="Graphics preset selected. Press Apply to use it."
	)
	var effects_row := _row("Scene effects",body)
	var effects := OptionButton.new()
	for caption in ["Minimal","Balanced","Full"]:effects.add_item(caption)
	effects.selected=draft.effects_quality
	effects.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	effects_row.add_child(effects)
	effects.item_selected.connect(func(index:int):
		draft.effects_quality=index
		preset.selected=settings.detect_preset(draft)+1
	)
	_toggle("Show FPS counter","show_fps",body)
	var detail_row := _row("Coin detail",body)
	var detail := OptionButton.new()
	for title in ["Low (faster)","Balanced","High"]:detail.add_item(title)
	detail.selected=draft.coin_detail
	detail.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	detail.item_selected.connect(func(index:int):
		draft.coin_detail=index
		preset.selected=settings.detect_preset(draft)+1
	)
	detail_row.add_child(detail)
	_button("USE PERFORMANCE SETTINGS",func():
		draft.window_mode=0
		draft.window_width=1280
		draft.window_height=720
		draft.coin_detail=0
		draft.effects_quality=0
		draft.msaa=0
		draft.fps_limit=60
		draft.show_fps=true
		_show_settings("display",false)
		status_label.text="720p window, Low detail, no MSAA, 60 FPS selected. Press Apply."
	,body)
	body.add_child(_text("Low is recommended for integrated graphics. Presets adjust coin detail, scene effects, and edge smoothing. Use Performance Settings also selects a 720p window and a 60 FPS cap.",14))
	var row:=_row("Display mode",body)
	var mode:=OptionButton.new()
	for caption in ["Windowed","Borderless fullscreen","Exclusive fullscreen"]:mode.add_item(caption)
	mode.selected=draft.window_mode
	mode.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(mode)
	row=_row("Window size",body)
	resolution_control=OptionButton.new()
	var sizes:=[Vector2i(1024,576),Vector2i(1280,720),Vector2i(1600,900),Vector2i(1920,1080),Vector2i(2560,1440)]
	for index in range(sizes.size()):
		var size:Vector2i=sizes[index]
		resolution_control.add_item("%d × %d"%[size.x,size.y])
		if size==Vector2i(draft.window_width,draft.window_height):resolution_control.selected=index
	resolution_control.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	resolution_control.disabled=draft.window_mode!=0
	row.add_child(resolution_control)
	resolution_control.item_selected.connect(func(index:int):
		draft.window_width=sizes[index].x
		draft.window_height=sizes[index].y
	)
	mode.item_selected.connect(func(index:int):
		draft.window_mode=index
		resolution_control.disabled=index!=0
	)
	_toggle("VSync","vsync",body)
	row=_row("Frame limit",body)
	var limit:=OptionButton.new()
	var limits:=[0,30,60,90,120,144,165,240]
	for index in range(limits.size()):
		limit.add_item("Unlimited" if limits[index]==0 else str(limits[index])+" FPS")
		if limits[index]==draft.fps_limit:limit.selected=index
	limit.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	limit.item_selected.connect(func(index:int):draft.fps_limit=limits[index])
	row.add_child(limit)
	row=_row("Edge smoothing",body)
	var aa:=OptionButton.new()
	for caption in ["Off","2× MSAA","4× MSAA","8× MSAA"]:aa.add_item(caption)
	aa.selected=draft.msaa
	aa.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	aa.item_selected.connect(func(index:int):
		draft.msaa=index
		preset.selected=settings.detect_preset(draft)+1
	)
	row.add_child(aa)
	body.add_child(_text("Window size applies in windowed mode. Fullscreen uses your display. Higher edge smoothing makes rails and coin rims smoother, with a higher graphics cost.",14))

func _begin_binding(action:String) -> void:
	cancel_binding()
	pending_binding=action
	binding_buttons[action].text="Press a key…"
	status_label.text="Press a key or mouse button. Esc cancels."

func _refresh_binding_buttons() -> void:
	for action in binding_buttons:binding_buttons[action].text=settings.binding_label(action)

func cancel_binding() -> void:
	if pending_binding!="" and is_instance_valid(status_label):status_label.text="Binding cancelled."
	pending_binding=""
	pending_modifier=null
	_refresh_binding_buttons()

func _capture_binding(event:InputEvent) -> void:
	var binding:Dictionary=settings.binding_from_event(event)
	if binding.is_empty():
		status_label.text="Choose a keyboard key or a mouse button that can be held."
		return
	var action:=pending_binding
	var swapped:String=settings.rebind(action,binding)
	pending_binding=""
	pending_modifier=null
	_refresh_binding_buttons()
	var error:int=settings.save_preferences()
	status_label.text=settings.NAMES[action]+" → "+settings.binding_label(action)
	if swapped!="":status_label.text+=". "+settings.NAMES[swapped]+" → "+settings.binding_label(swapped)
	if error!=OK:status_label.text+=". Applies for this session; saving failed."

func _apply_settings() -> void:
	var display_changed:bool=false
	for key in ["window_mode","window_width","window_height"]:
		if settings.options[key]!=draft[key]:display_changed=true
	previous_display=settings.options.duplicate(true) if display_changed else {}
	settings.options=draft.duplicate(true)
	settings.apply_to_game(game)
	if display_changed:
		display_seconds=15.0
		_show_display_confirmation()
	else:
		status_label.text="Settings saved." if settings.save_preferences()==OK else "Settings applied for this session; saving failed."

func _show_display_confirmation() -> void:
	page="display_confirm"
	_begin("KEEP THESE SETTINGS?","The previous settings will return automatically.",520,320)
	display_label=_text("",20)
	display_label.size_flags_vertical=Control.SIZE_EXPAND_FILL
	content.add_child(display_label)
	_button("KEEP CHANGES",func():
		previous_display.clear()
		var error:int=settings.save_preferences()
		_show_settings("display",true)
		status_label.text="Settings saved." if error==OK else "Settings applied for this session; saving failed."
	)
	_button("REVERT",func():_revert_display(true))

func _revert_display(rebuild:bool=true) -> void:
	if previous_display.is_empty():return
	settings.options=previous_display.duplicate(true)
	previous_display.clear()
	settings.apply_to_game(game)
	if rebuild:
		_show_settings("display",true)
		status_label.text="Previous settings restored."

func _process(delta:float) -> void:
	if not is_open:return
	var cap:=mini(60,int(settings.options.fps_limit)) if int(settings.options.fps_limit)>0 else 60
	if Engine.max_fps!=cap:Engine.max_fps=cap
	if page!="display_confirm":return
	display_seconds-=delta
	display_label.text="Reverting in %d seconds…"%maxi(0,int(ceil(display_seconds)))
	if display_seconds<=0:_revert_display(true)

func _show_quit() -> void:
	page="quit"
	_begin("SAVE & QUIT?","Your run will be saved to slot %d before closing." % game.active_slot,500,300)
	_button("RETURN TO GAME",close_menu)
	_button("QUIT TO DESKTOP",game.quit_game)

func _back() -> void:
	if page=="display_confirm":_revert_display(true)
	elif page=="main":close_menu()
	else:_show_main()

func _input(event:InputEvent) -> void:
	if game==null or settings==null:return
	if not game.run_active and not is_open:return
	if pending_binding!="":
		if event is InputEventKey and event.pressed and (event.keycode==KEY_ESCAPE or event.physical_keycode==KEY_ESCAPE):
			cancel_binding()
		elif event is InputEventKey:
			var code:int=event.physical_keycode if event.physical_keycode!=0 else event.keycode
			if code in [KEY_SHIFT,KEY_CTRL,KEY_ALT,KEY_META]:
				if event.pressed:pending_modifier=event.duplicate()
				elif pending_modifier!=null:
					_capture_binding(pending_modifier)
			elif event.pressed and not event.echo:
				pending_modifier=null
				_capture_binding(event)
		elif event is InputEventMouseButton and event.pressed:_capture_binding(event)
		get_viewport().set_input_as_handled()
		return
	var escape:bool=event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_ESCAPE
	if escape or (event.is_action_pressed("pause_game") and not event.is_echo()):
		if not is_open:
			if game.upgrade_overlay.visible and escape:game._close_upgrade_menu()
			else:open_menu()
		else:_back()
		get_viewport().set_input_as_handled()



