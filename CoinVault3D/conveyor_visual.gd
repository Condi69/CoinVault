extends Node3D
var game
var belt_slats: MultiMesh
var belt_coins: MultiMesh
var status_text: Label3D
var clock := 0.0
var motion_timer := 1.0
var last_powered := false
var last_quality := -1
var quality := 1
var last_status := ""
var groups: Dictionary = {}
const CENTER := Vector3(-4.9,1.25,-16.4)

func _ready() -> void:
	_box(CENTER+Vector3(0,-0.16,0),Vector3(3.6,0.22,0.84),"244a48")
	for z in [-0.45,0.45]:
		_box(CENTER+Vector3(0,0.04,z),Vector3(3.75,0.16,0.08),"b99047")
	for x in [-1.4,1.4]:
		_box(CENTER+Vector3(x,-0.65,0),Vector3(0.12,1.0,0.65),"24342e")
		_box(CENTER+Vector3(x,-1.12,0),Vector3(0.42,0.08,0.82),"68746a")
	_box(CENTER+Vector3(1.55,0.28,0),Vector3(0.55,0.40,0.90),"244a48")
	_box(CENTER+Vector3(1.55,0.51,0),Vector3(0.65,0.07,1.0),"b99047")
	_box(CENTER+Vector3(-2.45,-0.04,0),Vector3(1.4,0.10,0.55),"68746a")
	for z in [-0.30,0.30]:_box(CENTER+Vector3(-2.45,0.04,z),Vector3(1.4,0.16,0.06),"b99047")
	for tint in groups:
		var mm := MultiMesh.new()
		mm.transform_format=MultiMesh.TRANSFORM_3D
		var mesh := BoxMesh.new()
		mesh.size=Vector3.ONE
		mm.mesh=mesh
		mm.instance_count=groups[tint].size()
		for i in range(mm.instance_count):mm.set_instance_transform(i,groups[tint][i])
		var visual := MultiMeshInstance3D.new()
		visual.multimesh=mm
		visual.material_override=_finish(tint)
		add_child(visual)
	belt_slats=_batch(Vector3(0.16,0.055,0.72),20,"172b28")
	var coin_mesh := CylinderMesh.new()
	coin_mesh.top_radius=0.10
	coin_mesh.bottom_radius=0.10
	coin_mesh.height=0.035
	coin_mesh.radial_segments=12
	belt_coins=MultiMesh.new()
	belt_coins.transform_format=MultiMesh.TRANSFORM_3D
	belt_coins.mesh=coin_mesh
	belt_coins.instance_count=12
	var coins := MultiMeshInstance3D.new()
	coins.multimesh=belt_coins
	coins.material_override=_finish("efc457")
	coins.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(coins)
	status_text=Label3D.new()
	status_text.position=CENTER+Vector3(0,0.7,0.12)
	status_text.font_size=28
	status_text.pixel_size=0.006
	status_text.modulate=Color("f4d68a")
	status_text.outline_size=4
	add_child(status_text)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size=Vector3(3.8,0.28,0.95)
	shape.shape=box
	shape.position=CENTER+Vector3(0,-0.10,0)
	body.add_child(shape)
	add_child(body)
	game._register_coin_blocker(Transform3D(Basis.IDENTITY,shape.position),box.size)
	advance(0)

func _box(at:Vector3,dimensions:Vector3,tint:String) -> void:
	if not groups.has(tint):groups[tint]=[]
	groups[tint].append(Transform3D(Basis.IDENTITY.scaled(dimensions),at))

func _finish(tint:String) -> StandardMaterial3D:
	var finish := StandardMaterial3D.new()
	finish.albedo_color=Color(tint)
	finish.metallic=0.45
	finish.roughness=0.5
	return finish

func _batch(dimensions:Vector3,count:int,tint:String) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format=MultiMesh.TRANSFORM_3D
	var mesh := BoxMesh.new()
	mesh.size=dimensions
	mm.mesh=mesh
	mm.instance_count=count
	var visual := MultiMeshInstance3D.new()
	visual.multimesh=mm
	visual.material_override=_finish(tint)
	visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visual)
	return mm

func advance(delta:float) -> void:
	var powered: bool=game.run_active and game.passive_income_rate>0 and (game.remaining_coins>0 or game.conveyor_pending>0)
	var text := "OFFLINE / LEARN CONVEYORS"
	if game.passive_income_rate>0:text="VAULT EMPTY" if game.remaining_coins<=0 else "AUTO BANKING / %d COINS PER SEC" % game.passive_income_rate
	if text!=last_status:
		status_text.text=text
		last_status=text
	if powered:clock+=delta*1.3
	motion_timer+=delta
	var state_changed: bool=powered!=last_powered or quality!=last_quality
	if not state_changed and (not powered or motion_timer<1.0/[15.0,30.0,60.0][quality]):return
	motion_timer=0.0
	last_powered=powered
	last_quality=quality
	for i in range(belt_slats.instance_count):
		var x := fposmod(float(i)*0.18-clock,3.6)-1.8
		belt_slats.set_instance_transform(i,Transform3D(Basis.IDENTITY,CENTER+Vector3(x,0,0)))
	var count: int=[4,8,12][quality] if powered else 0
	belt_coins.visible_instance_count=count
	for i in range(count):
		var x := 1.7-fposmod(clock+float(i)*3.4/count,3.4)
		belt_coins.set_instance_transform(i,Transform3D(Basis(Vector3.UP,float(i)),CENTER+Vector3(x,0.055,sin(float(i)*2.4)*0.20)))
