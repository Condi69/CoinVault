extends Control

signal hovered(id: String)
signal purchased(id: String)
var game
var progression
var revealed: Array[String] = []
var pan := Vector2.ZERO
var zoom := 1.0
var highlighted_id := ""
var hovered_id := ""
var press_id := ""
var press_at := Vector2.ZERO
var pan_at_press := Vector2.ZERO
var held_button := 0
var dragging := false
var initialized := false
var previous_layout_size := Vector2.ZERO
var user_navigated := false

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_STOP
	clip_contents=true
	focus_mode=Control.FOCUS_ALL
	mouse_exited.connect(func():_set_hover(""))
	resized.connect(_on_map_resized)
	visibility_changed.connect(func():
		held_button=0
		dragging=false
		_set_hover("")
	)

func refresh() -> void:
	revealed.clear()
	for id in progression.nodes:
		if progression.is_revealed(id):revealed.append(id)
	if not revealed.has(hovered_id):_set_hover("")
	if progression.purchased.has(highlighted_id):highlighted_id=""
	queue_redraw()

func _on_map_resized() -> void:
	if initialized and previous_layout_size.x>0 and previous_layout_size.y>0:
		pan+=(size-previous_layout_size)*0.5
	previous_layout_size=size
	if not initialized or not user_navigated:call_deferred("frame_revealed")
	queue_redraw()

func frame_revealed() -> void:
	if revealed.is_empty() or size.x<100 or size.y<100:return
	var bounds := Rect2(Vector2(-45,-45),Vector2(90,90))
	for id in revealed:bounds=bounds.expand(progression.nodes[id].at)
	bounds=bounds.grow(65)
	zoom=clampf(minf(size.x/maxf(bounds.size.x,1),size.y/maxf(bounds.size.y,1)),0.2,1.25)
	pan=size*0.5-bounds.get_center()*zoom
	initialized=true
	user_navigated=false
	previous_layout_size=size
	_set_hover("")
	queue_redraw()

func reset_gesture() -> void:
	held_button=0
	dragging=false
	_set_hover("")

func _gui_input(event:InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			zoom_at(event.position,1.12 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.0/1.12)
			accept_event()
		elif event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_MIDDLE,MOUSE_BUTTON_RIGHT]:
			if event.pressed:
				grab_focus()
				held_button=event.button_index
				press_id=hit_test(event.position)
				press_at=event.position
				pan_at_press=pan
				dragging=event.button_index!=MOUSE_BUTTON_LEFT
				if dragging:_set_hover("")
			elif held_button==event.button_index:
				if not dragging and press_id!="" and hit_test(event.position)==press_id:
					purchased.emit(press_id)
				held_button=0
				dragging=false
				_set_hover(hit_test(event.position))
			accept_event()
	elif event is InputEventMouseMotion:
		if held_button!=0:
			if event.position.distance_to(press_at)>5:dragging=true
			if dragging:
				user_navigated=true
				pan=pan_at_press+event.position-press_at
				_clamp_pan()
				_set_hover("")
				queue_redraw()
		else:_set_hover(hit_test(event.position))
		accept_event()

func zoom_at(at:Vector2,factor:float) -> void:
	user_navigated=true
	var world := (at-pan)/zoom
	zoom=clampf(zoom*factor,0.2,2.0)
	pan=at-world*zoom
	_clamp_pan()
	_set_hover(hit_test(at))
	queue_redraw()

func _clamp_pan() -> void:
	var bounds := Rect2(Vector2.ZERO,Vector2.ONE)
	for id in revealed:bounds=bounds.expand(progression.nodes[id].at)
	pan.x=clampf(pan.x,size.x*0.2-bounds.end.x*zoom,size.x*0.8-bounds.position.x*zoom)
	pan.y=clampf(pan.y,size.y*0.2-bounds.end.y*zoom,size.y*0.8-bounds.position.y*zoom)

func hit_test(at:Vector2) -> String:
	var world := (at-pan)/zoom
	for i in range(revealed.size()-1,-1,-1):
		var id: String=revealed[i]
		var node: Dictionary=progression.nodes[id]
		if world.distance_squared_to(node.at)<=pow(_radius(node)+6,2):return id
	return ""

func _radius(node:Dictionary) -> float:
	return 39.0 if node.kind=="major" else (25.0 if node.kind=="minor" else 31.0)

func _set_hover(id:String) -> void:
	if hovered_id==id:return
	hovered_id=id
	hovered.emit(id)
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("111219"))
	var spacing := 40.0*zoom
	if spacing>=12:
		var offset := Vector2(fposmod(pan.x,spacing),fposmod(pan.y,spacing))
		for y in range(int(size.y/spacing)+1):
			for x in range(int(size.x/spacing)+1):draw_circle(offset+Vector2(x,y)*spacing,0.9,Color("282631"))
	draw_set_transform(pan,0,Vector2.ONE*zoom)
	for id in revealed:
		var node: Dictionary=progression.nodes[id]
		var tint := Color(progression.COLORS[node.branch])
		if node.parents.is_empty():
			draw_line(Vector2.ZERO,node.at,tint.darkened(0.62),2.0,true)
		else:
			for parent in node.parents:
				if revealed.has(parent):
					var owned: bool=progression.purchased.has(id)
					draw_line(progression.nodes[parent].at,node.at,tint.darkened(0.2 if owned else 0.65),3.0 if owned else 2.0,true)
	draw_circle(Vector2.ZERO,39,Color("24222c"))
	draw_arc(Vector2.ZERO,39,0,TAU,48,Color("b3a078"),2,true)
	draw_arc(Vector2.ZERO,31,0,TAU,48,Color("655d4b"),1,true)
	_draw_icon(5,Vector2.ZERO,Color("c9ba94"),1.2)
	for id in revealed:
		var node: Dictionary=progression.nodes[id]
		var at: Vector2=node.at
		var tint := Color(progression.COLORS[node.branch])
		var state := node_state(id)
		var radius := _radius(node)
		var can_buy_now := state=="ready"
		var owned := state=="learned"
		var rim := Color("88f0ad") if can_buy_now else (tint.darkened(0.48) if owned else Color("50535f"))
		var icon := tint if can_buy_now else (tint.darkened(0.32) if owned else Color("777785"))
		if can_buy_now:
			draw_circle(at,radius+7,Color(0.4,1.0,0.65,0.09))
		if hovered_id==id or highlighted_id==id:
			draw_arc(at,radius+10,0,TAU,48,Color("f4e6b9"),2,true)
		if node.kind=="major":
			var hex := PackedVector2Array()
			for point in range(7):hex.append(at+Vector2(cos(TAU*point/6.0-PI/6),sin(TAU*point/6.0-PI/6))*(radius+4))
			draw_colored_polygon(hex,Color("213b30") if can_buy_now else Color("1c1b26"))
			draw_polyline(hex,rim,3.5 if can_buy_now else 1.5,true)
		else:
			draw_circle(at,radius,Color("213b30") if can_buy_now else Color("1c1d26"))
			draw_arc(at,radius,0,TAU,48,rim,3.5 if can_buy_now else 1.5,true)
		_draw_icon([0,1,2,5,6][node.branch],at,icon,1.1 if node.kind=="major" else (0.72 if node.kind=="minor" else 0.9))
		_draw_state_badge(at+Vector2(radius*0.76,radius*0.68),state)
		if can_buy_now:
			var price: String=game.hud_view.number(node.cost)
			var price_font := ThemeDB.fallback_font
			var price_width := price_font.get_string_size(price,HORIZONTAL_ALIGNMENT_LEFT,-1,12).x
			draw_string(price_font,at+Vector2(-price_width*0.5,radius+20),price,HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("aff4c4"))
		if node.tier==1 and node.kind=="core":
			var text: String=progression.TITLES[node.branch].to_upper()
			var font := ThemeDB.fallback_font
			var width := font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,13).x
			draw_string(font,at+Vector2(-width/2,-radius-15),text,HORIZONTAL_ALIGNMENT_LEFT,-1,13,tint)
	draw_set_transform(Vector2.ZERO,0,Vector2.ONE)

func _draw_icon(branch:int,at:Vector2,tint:Color,scale_factor:float) -> void:
	# Original vector symbols; no external font or texture dependency.
	match branch:
		0:
			var points := PackedVector2Array()
			for p in [Vector2(-7,-8),Vector2(-14,3),Vector2(-12,14),Vector2(12,14),Vector2(14,3),Vector2(7,-8)]:points.append(at+p*scale_factor)
			points.append(points[0])
			draw_polyline(points,tint,2.5,true)
			draw_line(at+Vector2(-7,-11)*scale_factor,at+Vector2(7,-11)*scale_factor,tint,3,true)
			draw_circle(at+Vector2(0,4)*scale_factor,3*scale_factor,tint)
		1:
			draw_line(at+Vector2(-10,13)*scale_factor,at+Vector2(9,-12)*scale_factor,tint,4,true)
			draw_polyline(PackedVector2Array([at+Vector2(-10,-7)*scale_factor,at+Vector2(0,-15)*scale_factor,at+Vector2(13,-11)*scale_factor,at+Vector2(17,-2)*scale_factor]),tint,3,true)
		2:
			draw_arc(at,14*scale_factor,-PI*0.8,PI*0.8,32,tint,2.5,true)
			draw_arc(at,7*scale_factor,-PI*0.8,PI*0.8,24,tint,2,true)
			draw_circle(at,2*scale_factor,tint)
		3:
			for sign_value in [-1,1]:
				var center := at+Vector2(sign_value*7,sign_value*6)*scale_factor
				draw_ellipse_shape(center,Vector2(4,9)*scale_factor,tint)
		4:
			var points := PackedVector2Array()
			for p in [Vector2(3,-17),Vector2(-11,2),Vector2(-1,2),Vector2(-4,17),Vector2(12,-4),Vector2(3,-4)]:points.append(at+p*scale_factor)
			draw_colored_polygon(points,tint)
		5:
			draw_arc(at,14*scale_factor,0,TAU,40,tint,2.5,true)
			draw_arc(at,10*scale_factor,0,TAU,40,tint,1,true)
			draw_line(at+Vector2(0,-7)*scale_factor,at+Vector2(0,7)*scale_factor,tint,3,true)
		6:
			draw_rect(Rect2(at+Vector2(-16,-5)*scale_factor,Vector2(32,15)*scale_factor),tint,false,2)
			for x in [-10,0,10]:draw_circle(at+Vector2(x,5)*scale_factor,2*scale_factor,tint)
			for x in [-7,7]:draw_rect(Rect2(at+Vector2(x-4,-14)*scale_factor,Vector2(8,8)*scale_factor),tint,false,2)

func draw_ellipse_shape(center:Vector2,radii:Vector2,tint:Color) -> void:
	var points := PackedVector2Array()
	for i in range(25):points.append(center+Vector2(cos(TAU*i/24.0)*radii.x,sin(TAU*i/24.0)*radii.y))
	draw_polyline(points,tint,2.5,true)


func node_state(id:String) -> String:
	if progression.purchased.has(id):return "learned"
	if progression.can_buy(game,id):return "ready"
	if game.total_coins_collected<progression.nodes[id].required:return "milestone"
	return "coins"

func focus_node(id:String) -> void:
	if not revealed.has(id):return
	zoom=maxf(zoom,1.0)
	pan=size*0.5-progression.nodes[id].at*zoom
	user_navigated=true
	highlighted_id=id
	_set_hover("")
	queue_redraw()

func _draw_state_badge(at:Vector2,state:String) -> void:
	var tint := Color("88f0ad") if state=="ready" else (Color("a1acb1") if state=="learned" else Color("b0a0d4") if state=="milestone" else Color("d4b66c"))
	draw_circle(at,8,Color("151a1c"))
	draw_arc(at,8,0,TAU,24,tint,1.2,true)
	match state:
		"ready":
			draw_line(at+Vector2(-4,0),at+Vector2(4,0),tint,2,true)
			draw_line(at+Vector2(0,-4),at+Vector2(0,4),tint,2,true)
		"learned":
			draw_polyline(PackedVector2Array([at+Vector2(-4,0),at+Vector2(-1,3),at+Vector2(5,-4)]),tint,1.8,true)
		"coins":
			draw_arc(at,4.2,0,TAU,20,tint,1,true)
			draw_line(at+Vector2(0,-3),at+Vector2(0,3),tint,1.5,true)
		"milestone":
			draw_rect(Rect2(at+Vector2(-4,0),Vector2(8,5)),tint,false,1.2)
			draw_arc(at+Vector2(0,-1),3,PI,TAU,12,tint,1.2,true)


