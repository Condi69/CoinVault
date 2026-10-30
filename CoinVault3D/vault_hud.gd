extends Control

var scoop_label: Label
var scoop_hint: Label
var deposit_label: Label
var feedback_quality := 1
var scoop_seconds := 0.0
var deposit_seconds := 0.0
var frame_samples: Array[float] = []
var fps_label: Label
var fps_timer := 0.0
var bank_label: Label
var remaining_label: Label
var bag_label: Label
var amount_label: Label
var banked := 0
var carried := 0
var capacity := 25
var target_ratio := 0.0
var display_ratio := 0.0
var bank_pulse := 0.0
var initialized := false
var bag_rect := Rect2()
var outer := StyleBoxFlat.new()
var inner := StyleBoxFlat.new()
var gold := Color("f0cf80")

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var headline:=SystemFont.new()
	headline.font_names=PackedStringArray(["Bahnschrift Condensed","Bahnschrift","DejaVu Sans"])
	headline.font_weight=700
	headline.font_italic=true
	outer.bg_color=Color("171e1b")
	outer.border_color=Color("0b100d")
	outer.set_border_width_all(2)
	outer.set_corner_radius_all(7)
	outer.shadow_color=Color(0,0,0,0.36)
	outer.shadow_size=4
	outer.shadow_offset=Vector2(0,2)
	inner.bg_color=Color("2b332b")
	inner.border_color=Color("62634c")
	inner.set_border_width_all(1)
	inner.set_corner_radius_all(4)
	scoop_label=_label(24,headline)
	scoop_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	scoop_label.hide()
	scoop_hint=_label(12)
	scoop_hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	scoop_hint.hide()
	deposit_label=_label(18,headline)
	deposit_label.hide()
	fps_label=_label(14)
	fps_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	fps_label.visible=false
	bank_label=_label(25,headline)
	remaining_label=_label(12)
	remaining_label.modulate=Color("c6c5ac")
	bag_label=_label(20,headline)
	bag_label.text="BAG"
	amount_label=_label(19)
	amount_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	resized.connect(_layout)
	_layout()

func _label(font_size:int,font:Font=null) -> Label:
	var label:=Label.new()
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",gold)
	label.add_theme_color_override("font_outline_color",Color("111710"))
	label.add_theme_constant_override("outline_size",3)
	if font!=null:label.add_theme_font_override("font",font)
	add_child(label)
	return label

func _layout() -> void:
	fps_label.position=Vector2(maxf(16,size.x-244),19)
	fps_label.size=Vector2(220,48)
	scoop_label.position=Vector2(size.x*0.5-150,size.y*0.5+35)
	scoop_label.size=Vector2(300,32)
	scoop_hint.position=Vector2(size.x*0.5-150,size.y*0.5+68)
	scoop_hint.size=Vector2(300,20)
	deposit_label.position=Vector2(56,78)
	deposit_label.size=Vector2(320,28)
	var width:=minf(320.0,maxf(220.0,size.x-32.0))
	bag_rect=Rect2(Vector2((size.x-width)*0.5,size.y-76.0),Vector2(width,52))
	bank_label.position=Vector2(55,19)
	bank_label.size=Vector2(260,34)
	remaining_label.position=Vector2(56,52)
	remaining_label.size=Vector2(270,20)
	bag_label.position=bag_rect.position+Vector2(48,8)
	bag_label.size=Vector2(90,29)
	amount_label.position=bag_rect.position+Vector2(width-160,8)
	amount_label.size=Vector2(143,29)
	queue_redraw()

func number(value:int) -> String:
	var text:=str(value)
	var result:=""
	for index in range(text.length()):
		if index>0 and (text.length()-index)%3==0:result+=","
		result+=text[index]
	return result

func update_values(balance:int,bag:int,limit:int,remaining:int) -> void:
	if initialized and balance>banked:bank_pulse=1.0
	banked=balance
	carried=bag
	capacity=maxi(1,limit)
	target_ratio=clampf(float(carried)/float(capacity),0,1)
	if not initialized:display_ratio=target_ratio
	initialized=true
	bank_label.text=number(banked)
	remaining_label.text="IN VAULT  "+number(remaining)
	amount_label.text="%s / %s"%[number(carried),number(capacity)]
	amount_label.modulate=Color("e9a26c") if carried>=capacity else Color.WHITE
	queue_redraw()

func set_fps_visible(enabled:bool) -> void:
	fps_label.visible=enabled
	if enabled:fps_label.text="%d FPS" % Engine.get_frames_per_second()
	fps_timer=0.0
	frame_samples.clear()

func _process(delta:float) -> void:
	if fps_label.visible:
		frame_samples.append(delta*1000.0)
		if frame_samples.size()>120:frame_samples.pop_front()
		fps_timer+=delta
		if fps_timer>=0.5:
			fps_timer=0.0
			var sorted := frame_samples.duplicate()
			sorted.sort()
			var median: float=sorted[int(sorted.size()/2.0)]
			var p95: float=sorted[mini(sorted.size()-1,int(sorted.size()*0.95))]
			fps_label.text="%d FPS | %.1f ms\n95%% frames: %.1f ms" % [Engine.get_frames_per_second(),median,p95]
	if scoop_seconds>0:
		if feedback_quality>0:queue_redraw()
		scoop_seconds=maxf(0,scoop_seconds-delta)
		var alpha := minf(1,scoop_seconds/0.22)
		scoop_label.modulate.a=alpha
		scoop_hint.modulate.a=alpha
		scoop_label.position.y=size.y*0.5+35-(1.0-minf(1,scoop_seconds))*8
		scoop_label.visible=scoop_seconds>0
		scoop_hint.visible=scoop_seconds>0
	if deposit_seconds>0:
		deposit_seconds=maxf(0,deposit_seconds-delta)
		deposit_label.modulate.a=minf(1,deposit_seconds/0.3)
		deposit_label.visible=deposit_seconds>0
	var previous:=display_ratio
	display_ratio=move_toward(display_ratio,target_ratio,delta*3.5)
	if bank_pulse>0.0:
		bank_pulse=maxf(0,bank_pulse-delta*4.5)
		bank_label.modulate=Color.WHITE.lerp(Color("fff3bd"),bank_pulse)
		queue_redraw()
	if not is_equal_approx(previous,display_ratio):queue_redraw()

func _draw() -> void:
	if bank_label==null:return
	if scoop_seconds>0 and feedback_quality>0:
		var alpha := minf(1,scoop_seconds/0.3)*0.55
		var pulse_radius := 19.0+(1.1-scoop_seconds)*9.0
		draw_arc(size*0.5,pulse_radius,0,TAU,40,Color(0.94,0.81,0.50,alpha),1.5,true)
	var center:=Vector2(35,35)
	var radius:=12.0+bank_pulse*0.7
	draw_circle(center+Vector2(0,2),radius,Color(0.05,0.045,0.02,0.65))
	draw_circle(center,radius,Color("edbb49"))
	draw_circle(center,radius-2.4,Color("d5a13c"))
	draw_arc(center,radius-0.8,PI*1.02,PI*1.94,24,Color("fff1af"),1.6,true)
	draw_arc(center,radius-2.3,0,TAU,32,Color("f6d673"),0.8,true)
	for index in range(12):
		var angle:=TAU*float(index)/12.0
		var direction:=Vector2(cos(angle),sin(angle))
		draw_line(center+direction*(radius-1.8),center+direction*(radius-0.3),Color("ad792b"),0.8,true)
	draw_line(center+Vector2(-2,-5),center+Vector2(-2,5),Color("f9df8a"),1.5,true)
	draw_line(center+Vector2(2,-5),center+Vector2(2,5),Color("f9df8a"),1.5,true)
	draw_style_box(outer,bag_rect)
	draw_style_box(inner,bag_rect.grow(-4))
	draw_line(bag_rect.position+Vector2(10,7),bag_rect.position+Vector2(bag_rect.size.x-10,7),Color(0.68,0.69,0.52,0.18),1,true)
	var icon:=bag_rect.position+Vector2(25,24)
	var body:=PackedVector2Array()
	for point in [Vector2(-3,-6),Vector2(-6,-1),Vector2(-7,4),Vector2(-4,8),Vector2(4,8),Vector2(7,4),Vector2(6,-1),Vector2(3,-6)]:body.append(icon+point)
	draw_colored_polygon(body,Color("f2e0a7"))
	draw_colored_polygon(PackedVector2Array([icon+Vector2(-5,-12),icon+Vector2(0,-10),icon+Vector2(5,-12),icon+Vector2(3,-7),icon+Vector2(-3,-7)]),Color("f2e0a7"))
	draw_line(icon+Vector2(-4,-6),icon+Vector2(4,-6),Color("a99561"),2,true)
	draw_circle(icon+Vector2(0,2),2.1,Color("b19b5b"))
	var bar:=Rect2(bag_rect.position+Vector2(12,43),Vector2(bag_rect.size.x-24,3))
	draw_rect(bar,Color("151e18"))
	if display_ratio>0.0:
		bar.size.x*=display_ratio
		draw_rect(bar,Color("d7aa4c") if carried<capacity else Color("d98a52"))

func show_scoop(amount:int,full:bool) -> void:
	scoop_label.text="+%s COINS" % number(amount)
	scoop_hint.text="BAG FULL / RETURN TO DEPOSIT" if full else "COLLECTED TO BAG"
	scoop_hint.add_theme_color_override("font_color",Color("f3a86f") if full else Color("d2d7be"))
	scoop_seconds=1.1
	scoop_label.modulate.a=1
	scoop_hint.modulate.a=1
	scoop_label.show()
	scoop_hint.show()

func show_deposit(amount:int) -> void:
	deposit_label.text="+%s BANKED" % number(amount)
	deposit_seconds=1.5
	deposit_label.modulate.a=1
	deposit_label.show()

