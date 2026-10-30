extends Control
var game
var content: VBoxContainer
var status: Label
var panel: PanelContainer
var font: SystemFont
var title: Label

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_STOP
	font=SystemFont.new()
	font.font_names=PackedStringArray(["Bahnschrift Condensed","Bahnschrift","DejaVu Sans"])
	font.font_weight=800
	font.font_italic=true
	var menu_theme := Theme.new()
	menu_theme.default_font=font
	menu_theme.default_font_size=22
	for state in ["normal","hover","pressed","disabled","focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color=Color("627064") if state=="hover" else Color("39443e")
		style.border_color=Color("ecc36c") if state in ["hover","focus"] else Color("161f1a")
		style.set_border_width_all(3)
		style.set_corner_radius_all(7)
		style.set_content_margin_all(10)
		style.shadow_size=4
		style.shadow_offset=Vector2(0,3)
		menu_theme.set_stylebox(state,"Button",style)
		menu_theme.set_color("font_color","Button",Color("f9e7b7"))
		menu_theme.set_color("font_disabled_color","Button",Color("a3a995"))
	self.theme=menu_theme
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code="shader_type canvas_item; void fragment(){ COLOR=vec4(0.015,0.022,0.018,mix(0.9,0.12,smoothstep(0.1,1.0,UV.x))); }"
	var shade_material := ShaderMaterial.new()
	shade_material.shader=shader
	shade.material=shade_material
	add_child(shade)
	panel=PanelContainer.new()
	panel.add_theme_stylebox_override("panel",StyleBoxEmpty.new())
	add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	content=VBoxContainer.new()
	content.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation",12)
	scroll.add_child(content)
	resized.connect(_layout)
	_layout()
	show_home()

func _layout() -> void:
	panel.position=Vector2(40 if size.x>850 else 20,20)
	panel.size=Vector2(minf(510,size.x-40),size.y-40)
	content.add_theme_constant_override("separation",8 if size.y<650 else 12)
	if is_instance_valid(title):title.add_theme_font_size_override("font_size",58 if size.y<650 else 78)
	for child in content.get_children():
		if child is Button:
			child.custom_minimum_size.y=42 if size.y<650 else 50
			child.add_theme_font_size_override("font_size",19 if size.y<650 else 22)
			for state in ["normal","hover","pressed","disabled","focus"]:
				var style: StyleBox=child.get_theme_stylebox(state).duplicate()
				style.content_margin_top=6 if size.y<650 else 10
				style.content_margin_bottom=6 if size.y<650 else 10
				child.add_theme_stylebox_override(state,style)

func _clear() -> void:
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()

func _label(value:String,point_size:int=18,tint:Color=Color("f6d481")) -> Label:
	var label := Label.new()
	label.text=value
	label.add_theme_font_size_override("font_size",point_size)
	label.add_theme_color_override("font_color",tint)
	label.add_theme_color_override("font_outline_color",Color("211b12"))
	label.add_theme_constant_override("outline_size",3)
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	content.add_child(label)
	return label

func _button(value:String,callback:Callable,gold:bool=false) -> Button:
	var button := Button.new()
	button.text=value
	button.alignment=HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.y=50
	button.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	if gold:
		for state in ["normal","hover","pressed","focus"]:
			var style := StyleBoxFlat.new()
			style.bg_color=Color("ffda7f") if state=="hover" else Color("edbd56")
			style.border_color=Color("654b1d")
			style.set_border_width_all(3)
			style.set_corner_radius_all(7)
			style.set_content_margin_all(12)
			button.add_theme_stylebox_override(state,style)
		button.add_theme_color_override("font_color",Color("24251b"))
		button.add_theme_color_override("font_hover_color",Color("24251b"))
		button.add_theme_color_override("font_focus_color",Color("24251b"))
	button.pressed.connect(callback)
	content.add_child(button)
	return button

func show_home(message:String="") -> void:
	_clear()
	var entries: Array=game.save_store.summaries()
	var coins := 0
	for entry in entries:
		if entry.valid:coins+=int(entry.data.stats.banked_coins)
	_label("COINS BANKED  %s" % game.hud_view.number(coins),22)
	_label("ACROSS YOUR SAVED VAULTS",13,Color("b4ae92"))
	title=_label("COIN\nVAULT 3D",78,Color("ffdc83"))
	title.add_theme_constant_override("outline_size",10)
	title.add_theme_color_override("font_shadow_color",Color("775322"))
	title.add_theme_constant_override("shadow_offset_y",5)
	var latest: int=game.save_store.latest_slot()
	var continue_button := _button("CONTINUE  /  SLOT %d" % latest if latest>0 else "CONTINUE  /  NO SAVES YET",func():_load(latest),true)
	continue_button.disabled=latest==0
	_button("NEW GAME",func():show_slots(true),latest==0)
	_button("SETTINGS",func():game.open_title_page("settings"))
	_button("HELP & CONTROLS",func():game.open_title_page("help"))
	_button("QUIT TO DESKTOP",game.quit_game)
	_label("YOUR SAVE FILES",15)
	var slots := HBoxContainer.new()
	slots.add_theme_constant_override("separation",8)
	content.add_child(slots)
	for entry in entries:
		var button := Button.new()
		button.text="SLOT %d\n%s" % [entry.slot,"PLAY" if entry.valid else ("UNREADABLE" if entry.exists else "EMPTY")]
		button.add_theme_font_size_override("font_size",16)
		button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y=48
		var slot: int=entry.slot
		button.pressed.connect(func():
			if entry.valid:_load(slot)
			else:show_slots(true)
		)
		slots.add_child(button)
	status=_label(message,15,Color("f0c58f"))
	_layout()

func show_slots(new_game:bool) -> void:
	_clear()
	_label("NEW VAULT" if new_game else "YOUR VAULTS",42)
	_label("Choose one of three save files. Starting over in an occupied slot requires confirmation.",18,Color("c8c1a8"))
	for entry in game.save_store.summaries():
		var slot: int=entry.slot
		var summary := "EMPTY / START A NEW GAME"
		if entry.valid:
			var stats: Dictionary=entry.data.stats
			summary="%s collected / %s banked\n%d skills / %d min played%s" % [game.hud_view.number(stats.total_coins_collected),game.hud_view.number(stats.banked_coins),entry.data.skills.size(),int(entry.data.played_seconds/60)," / RECOVERED BACKUP" if entry.backup else ""]
		elif entry.exists:summary="UNREADABLE / REPLACE WITH A NEW GAME"
		_button("SLOT %d\n%s" % [slot,summary],func():
			if entry.exists:_confirm_new(slot)
			else:_new(slot)
		)
	_button("BACK",show_home)
	status=_label("",15,Color("f0c58f"))

func _confirm_new(slot:int) -> void:
	_clear()
	_label("START OVER IN SLOT %d?" % slot,36)
	_label("This replaces the run in this slot. Your other save files will be kept.",20,Color("e7d9b5"))
	_button("START NEW GAME / REPLACE SLOT %d" % slot,func():_new(slot),true)
	_button("CANCEL",func():show_slots(true))
	status=_label("",15,Color("f0c58f"))

func _new(slot:int) -> void:
	status.text="Preparing your vault..."
	game.call_deferred("begin_run",slot,true)

func _load(slot:int) -> void:
	if slot<1:return
	status.text="Loading slot %d..." % slot
	game.call_deferred("begin_run",slot,false)

func show_error(message:String) -> void:
	show_home(message)

