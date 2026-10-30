extends Node3D

var vault_details = preload("res://vault_details.gd").new()
var game_settings = preload("res://game_settings.gd").new()
var pause_menu
var pickup_generation := 0
var feedback
var conveyor_visual
var scoop_feedback_total := 0
var settling_limit := 24
var pickup_visual_limit := 8
var run_active := false
var active_slot := 0
var played_seconds := 0.0
var autosave_seconds := 0.0
var save_requested := false
var save_thread: Thread
var last_save_error := ""
var start_screen: Control
var menu_camera: Camera3D
var save_status_label: Label
var save_notice_seconds := 0.0
var save_store = preload("res://save_store.gd").new()
const RUN_STATE = preload("res://run_state.gd")

const VAULT_WIDTH := 36.0
const VAULT_DEPTH := 36.0
const VAULT_TOP := 0.0
const VAULT_BOTTOM := -24.0
const COIN_PILE_BASE_Y := -1.60
const PICKUP_DELAY := 0.25
const PICKUP_RECOVERY := 0.12
const PICKUP_RANGE := 4.5
const BANK_RANGE := 3.5
const STARTING_CAPACITY := 25
const STARTING_COIN_COUNT := 1000000
const COIN_MASS_MAX_HEIGHT := 1.0
const COIN_MASS_EDGE_RATIO := 0.8
const COIN_PHYSICS_SUPPORT_HEIGHT := 0.0
const MASS_MESH_RESOLUTION := 96
const HEAP_COLLISION_RESOLUTION := 37
const PHYSICS_COIN_RADIUS := 0.31
const PHYSICS_COIN_THICKNESS := 0.075
const STATIC_COIN_GRID := 73

var ignore_mouse_motion := false
var mouse_released := false
var window_focused := true
var pickup_pending := false
var pickup_held := false
var carried_coins := 0
var banked_coins := 0
var capacity := STARTING_CAPACITY
var remaining_coins := STARTING_COIN_COUNT
var collection_range := PICKUP_RANGE
var pickup_amount := 1
var banking_multiplier := 1.0
var passive_income_rate := 0
var passive_income_timer := 0.0
var conveyor_pending := 0
var conveyor_cursor := 0
var conveyor_anchor := -1
const CONVEYOR_LAYER_HEIGHT := 0.10
const CONVEYOR_SURFACE_RELIEF := 0.28
const TOP_PLATFORM_SPAWN := Vector3(-11.5,1.1,-15.0)
var conveyor_order: Array[Dictionary] = []
var conveyor_versions := PackedInt32Array()
var conveyor_heap_ready := false
var conveyor_serial := 0
var total_coins_collected := 0
var skill_progression = preload("res://skill_progression.gd").new()
var pickup_delay := PICKUP_DELAY
var pickup_recovery := PICKUP_RECOVERY
var deposit_range := BANK_RANGE
var pickup_work_left := 0
var scoop_candidates: Array[int] = []
var scoop_eye := Vector3.ZERO
var coin_mass_visual: Node3D
var coin_mass_mesh: MeshInstance3D
var heap_collision_shape: CollisionShape3D
var heap_heightmap: HeightMapShape3D
var backing_coin_layers: Array[MultiMesh] = []
var stack_supports: MultiMesh
var stack_slots: Dictionary = {}
var stack_levels: PackedInt32Array = PackedInt32Array()
var surface_coins: MultiMesh
var surface_poses: Array[Transform3D] = []
var coin_blocker_bins: Dictionary = {}
var coin_blocker_serial := 0
var coin_skin_structure_bins: Dictionary = {}
var coin_skin_triangle_cache: Dictionary = {}
var coin_coverage_floor_cache: Dictionary = {}
const COIN_SKIN_PATCH_CELLS := 12
var coin_skin_patches: Dictionary = {}
var coin_skin_dirty_patches: Dictionary = {}
var coin_stair_treads: Array[Dictionary] = []
var structure_gap_seeds: Dictionary = {}
var structure_gap_poses: Dictionary = {}
var coin_stair_columns: PackedByteArray = PackedByteArray()
var finite_pile_ready := false
var column_capacity := PackedInt32Array()
var column_ceilings := PackedFloat32Array()
var column_floors := PackedFloat32Array()
var column_coins: PackedInt32Array = PackedInt32Array()
var column_backing_cursor: PackedInt32Array = PackedInt32Array()
const RESERVE_CHUNK_SIZE := 8
var reserve_column_cache: Dictionary = {}
var reserve_chunks: Dictionary = {}
var reserve_dirty_chunks: Dictionary = {}
var reserve_front_poses: Dictionary = {}
var target_coin_bins: Dictionary = {}
var coin_mesh_cache: Dictionary = {}
var reserve_coin_mesh: ArrayMesh
var settling_coins: Dictionary = {}
var surface_home_poses: Array[Transform3D] = []
var pickup_flights: Array[Dictionary] = []
var coin_support_dirty := false
var coin_support_timer := 0.0
var physics_coin_mesh: ArrayMesh
var physics_coin_material: ShaderMaterial
var physics_coin_shape: CylinderShape3D
var physics_coin_surface: PhysicsMaterial
var deposit_position := Vector3(-8.5, 0.0, -17.0)
var deposit_machine: Node3D
var deposit_balance_label: Label
var mass_is_targeted := false
var target_scan_timer := 0.0
var hud_view
var hud_label: Label
var hint_label: Label
var crosshair_bars: Array[ColorRect] = []
var crosshair_dot: ColorRect
var upgrade_overlay: Control
var player: CharacterBody3D
var camera: Camera3D
var mouse_sensitivity := 0.002

func _ready() -> void:
	game_settings.load_preferences()
	_setup_input()
	_build_lighting()
	_build_vault()
	_build_stairway()
	_build_architecture_details()
	vault_details.finish_fasteners(self)
	vault_details.finish_batches(self)
	_build_deposit_station()
	conveyor_visual=preload("res://conveyor_visual.gd").new()
	conveyor_visual.game=self
	add_child(conveyor_visual)
	_build_coin_pile()
	_build_player()
	_build_hud()
	feedback=preload("res://game_feedback.gd").new()
	feedback.game=self
	add_child(feedback)
	_build_upgrade_menu()
	_update_hud()
	game_settings.apply_to_game(self)
	pause_menu=preload("res://pause_menu.gd").new()
	pause_menu.game=self
	pause_menu.settings=game_settings
	add_child(pause_menu)
	get_window().focus_entered.connect(_on_game_focus_entered)
	get_window().focus_exited.connect(_on_game_focus_exited)
	window_focused = get_window().has_focus()
	_boot_title()
	get_tree().auto_accept_quit=false
	get_window().close_requested.connect(quit_game)
	_sync_mouse_capture()

func _process(delta: float) -> void:
	_sync_mouse_capture()
	_poll_save()
	if not run_active:return
	conveyor_visual.advance(delta)
	played_seconds+=delta
	autosave_seconds+=delta
	if autosave_seconds>=30.0 or (save_requested and autosave_seconds>=2.0):_start_autosave()
	if save_notice_seconds>0:
		save_notice_seconds=maxf(0,save_notice_seconds-delta)
		if save_notice_seconds==0 and last_save_error=="":save_status_label.text=""
	_tick_coin_settling(delta)
	_tick_pickup_flights(delta)
	_rebuild_dirty_reserves()
	if not coin_skin_dirty_patches.is_empty():_update_coin_skin_patches()
	coin_support_timer += delta
	if coin_support_dirty and coin_support_timer >= 0.12:
		_update_heap_collision_map()
		coin_support_dirty = false
		coin_support_timer = 0.0
	_tick_conveyor(delta)
	if upgrade_overlay != null and upgrade_overlay.visible:
		return
	if pickup_work_left > 0:_drain_pickup_work()
	if pickup_held and window_focused and not mouse_released:
		_collect_one_coin_from_mass()
	target_scan_timer += delta
	if target_scan_timer >= 0.07:
		target_scan_timer = 0.0
		_update_mass_target(_ray_intersects_coin_mass())

func _on_game_focus_entered() -> void:
	window_focused = true
	call_deferred("_sync_mouse_capture")

func _on_game_focus_exited() -> void:
	if not run_active:
		Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
		return
	pickup_held = false
	window_focused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if player != null:
		player.velocity = Vector3.ZERO
	if pause_menu != null:
		pause_menu.cancel_binding()
		pause_menu.open_menu()

func _sync_mouse_capture() -> void:
	if not run_active:
		Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
		return
	var desired := Input.MOUSE_MODE_VISIBLE
	if window_focused:
		if pause_menu != null and pause_menu.is_open:
			desired=Input.MOUSE_MODE_VISIBLE
		elif upgrade_overlay != null and upgrade_overlay.visible:
			desired = Input.MOUSE_MODE_CONFINED
		elif not mouse_released:
			desired = Input.MOUSE_MODE_CAPTURED
	if Input.mouse_mode != desired:
		if desired==Input.MOUSE_MODE_CAPTURED:ignore_mouse_motion=true
		Input.mouse_mode = desired

func _input(event: InputEvent) -> void:
	if not run_active:return
	if window_focused and (pause_menu == null or not pause_menu.is_open) and event.is_action_pressed("skill_tree") and not event.is_echo():
		if upgrade_overlay.visible:_close_upgrade_menu()
		else:_open_upgrade_menu()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_released("collect"):
		pickup_held = false
	# Capture the first click before UI controls can consume it; do not collect.
	if not window_focused or (pause_menu != null and pause_menu.is_open) or (upgrade_overlay != null and upgrade_overlay.visible):
		return
	if event is InputEventMouseButton and event.pressed and mouse_released:
		mouse_released = false
		_sync_mouse_capture()
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not run_active:return
	if not window_focused:
		return
	if upgrade_overlay != null and upgrade_overlay.visible:
		if event.is_action_pressed("ui_cancel"):
			_close_upgrade_menu()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("collect") and not event.is_echo():
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			mouse_released = false
			_sync_mouse_capture()
			return
		pickup_held = true
		_collect_one_coin_from_mass()
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if ignore_mouse_motion:
			ignore_mouse_motion=false
			return
		player.rotate_y(-event.relative.x * mouse_sensitivity)
		camera.rotate_x(event.relative.y*mouse_sensitivity*(1.0 if game_settings.options.invert_y else -1.0))
		camera.rotation.x = clampf(camera.rotation.x, deg_to_rad(-85), deg_to_rad(85))
	if event.is_action_pressed("ui_cancel"):
		pause_menu.open_menu()
		return
	if event.is_action_pressed("interact"):
		_try_interact()

func _physics_process(_delta: float) -> void:
	if not run_active:return
	if player == null or not window_focused or mouse_released or (upgrade_overlay != null and upgrade_overlay.visible):
		return
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := player.global_transform.basis * Vector3(input_dir.x, 0, input_dir.y)
	if direction.length() > 0.01:
		direction = direction.normalized()
	var move_speed := 5.0
	if Input.is_action_pressed("sprint"):
		move_speed *= 1.7
	player.velocity.x = direction.x * move_speed
	player.velocity.z = direction.z * move_speed
	if player.is_on_floor() and Input.is_action_just_pressed("jump"):
		player.velocity.y = 7.5
	elif not player.is_on_floor():
		player.velocity.y -= 20.0 * get_physics_process_delta_time()
	else:
		player.velocity.y = 0.0
	player.move_and_slide()
	_update_hint()

func _setup_input() -> void:
	game_settings.apply_bindings()

func _cancel_pickup() -> void:
	scoop_candidates.clear()
	pickup_work_left = 0
	pickup_generation+=1
	pickup_pending=false
	pickup_held=false

func _build_lighting() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-52, -25, 0)
	light.light_energy = 0.65
	add_child(light)
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("111a26")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b8ada0")
	env.ambient_light_energy = 0.40
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("96968e")
	sky_material.sky_horizon_color = Color("dfd3b2")
	sky_material.ground_bottom_color = Color("aa9458")
	var reflection_sky := Sky.new()
	reflection_sky.sky_material = sky_material
	env.sky = reflection_sky
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	world.environment = env
	add_child(world)
	var vault_light := OmniLight3D.new()
	vault_light.position = Vector3(2, 3, 0)
	vault_light.light_color = Color("ffe4a5")
	vault_light.light_energy = 0.75
	vault_light.omni_range = 32.0
	add_child(vault_light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-24, 145, 0)
	fill.light_color = Color("ffe8bd")
	fill.light_energy = 0.42
	add_child(fill)
	var stair_light := OmniLight3D.new()
	stair_light.position = Vector3(-15, -10, 0)
	stair_light.light_color = Color("91cfff")
	stair_light.light_energy = 2.0
	stair_light.omni_range = 16.0
	add_child(stair_light)
	var bottom_light := OmniLight3D.new()
	bottom_light.position = Vector3(0, -20, 0)
	bottom_light.light_color = Color("ffe4a5")
	bottom_light.light_energy = 2.5
	bottom_light.omni_range = 14.0
	add_child(bottom_light)

func _build_vault() -> void:
	# Enclosed room and warm wall lights frame the coin field.
	_add_environment_box(Vector3(0,4.25,0),Vector3(36,0.5,36),"ceiling",false)
	for side in [-1.0, 1.0]:
		for offset in [-12.0, -4.0, 4.0, 12.0]:
			var lamp_position := Vector3(side * 17.35, 2.45, offset)
			_add_box_visual(lamp_position, Vector3(0.18, 0.20, 0.75), Color("edcf86"))
			var lamp := OmniLight3D.new()
			lamp.position = lamp_position + Vector3(-side * 0.7, -0.15, 0)
			lamp.light_color = Color("ffdf9e")
			lamp.light_energy = 1.25
			lamp.omni_range = 10.0
			add_child(lamp)
	# North opening is aligned with the stair entrance, not the wall.
	_add_guard_segment(Vector3(-14.1, 0, -14.1), Vector3(-13.3, 0, -14.1))
	_add_guard_segment(Vector3(-9.7, 0, -14.1), Vector3(14.1, 0, -14.1))
	_add_guard_segment(Vector3(-14.1, 0, 14.1), Vector3(14.1, 0, 14.1))
	_add_guard_segment(Vector3(-14.1, 0, -14.1), Vector3(-14.1, 0, 14.1))
	_add_guard_segment(Vector3(14.1, 0, -14.1), Vector3(14.1, 0, 14.1))
	# One narrow, deep vault with a walkable rim and an open central shaft.
	_add_environment_box(Vector3(0,VAULT_BOTTOM-0.35,0),Vector3(VAULT_WIDTH,0.7,VAULT_DEPTH),"floor")
	_add_environment_box(Vector3(0, -0.35, -16), Vector3(36, 0.7, 4),"floor")
	_add_environment_box(Vector3(0, -0.35, 16), Vector3(36, 0.7, 4),"floor")
	_add_environment_box(Vector3(-16, -0.35, 0), Vector3(4, 0.7, 28),"floor")
	_add_environment_box(Vector3(16, -0.35, 0), Vector3(4, 0.7, 28),"floor")
	# Reinforced walls and repeated steel ribs emphasize the shaft's depth.
	_add_environment_box(Vector3(0, -10, -18), Vector3(36, 28, 0.8),"wall")
	_add_environment_box(Vector3(0, -10, 18), Vector3(36, 28, 0.8),"wall")
	_add_environment_box(Vector3(-18, -10, 0), Vector3(0.8, 28, 36),"wall")
	_add_environment_box(Vector3(18, -10, 0), Vector3(0.8, 28, 36),"wall")
	for y in [-3.0, -9.0, -15.0, -21.0]:
		for offset in [-12.0, 0.0, 12.0]:
			_add_box_visual(Vector3(-17.48, y, offset), Vector3(0.12, 4.0, 0.36), Color("758291"))
			_add_box_visual(Vector3(17.48, y, offset), Vector3(0.12, 4.0, 0.36), Color("758291"))
			_add_box_visual(Vector3(offset, y, -17.48), Vector3(0.36, 4.0, 0.12), Color("758291"))
			_add_box_visual(Vector3(offset, y, 17.48), Vector3(0.36, 4.0, 0.12), Color("758291"))
	# Sealed steel hatch and hazard frame on the wall behind the service stations.
	_add_box_visual(Vector3(0, -10, -17.45), Vector3(12.0, 12.0, 0.24), Color("344350"))
	_add_box_visual(Vector3(-6.2, -10, -17.2), Vector3(0.34, 13.0, 0.28), Color("d5a439"))
	_add_box_visual(Vector3(6.2, -10, -17.2), Vector3(0.34, 13.0, 0.28), Color("d5a439"))
	_add_box_visual(Vector3(0, -3.5, -17.2), Vector3(12.7, 0.34, 0.28), Color("d5a439"))
	_add_box_visual(Vector3(0, -16.5, -17.2), Vector3(12.7, 0.34, 0.28), Color("d5a439"))
	_add_box_visual(Vector3(0, -10, -17.05), Vector3(0.24, 9.0, 0.16), Color("708194"))
	_add_box_visual(Vector3(0, -10, -17.05), Vector3(8.0, 0.24, 0.16), Color("708194"))
	_add_box_visual(Vector3(0, -0.02, -15.8), Vector3(32.0, 0.08, 0.14), Color("e0ad3d"))

func _add_environment_box(at: Vector3, size: Vector3, kind: String, cast_shadows: bool = true) -> void:
	var body:=_add_solid_box(at,size,Color.WHITE,cast_shadows)
	body.get_child(1).material_override=vault_details.material(kind)

func _build_architecture_details() -> void:
	for z in [-11.0,0.0,11.0]:
		vault_details.box(self,Vector3(0,3.95,z),Vector3(35.1,0.07,0.38),"steel")
		vault_details.box(self,Vector3(0,3.75,z),Vector3(35.1,0.34,0.09),"steel")
		vault_details.box(self,Vector3(0,3.56,z),Vector3(35.1,0.07,0.38),"steel")
	for x in [-11.0,11.0]:
		vault_details.box(self,Vector3(x,3.96,0),Vector3(0.28,0.06,35.1),"steel")
		vault_details.box(self,Vector3(x,3.84,0),Vector3(0.075,0.20,35.1),"steel")
		vault_details.box(self,Vector3(x,3.72,0),Vector3(0.28,0.06,35.1),"steel")
	for side in [-1.0,1.0]:
		vault_details.box(self,Vector3(0,-0.12,side*14.025),Vector3(28.2,0.18,0.10),"steel")
		vault_details.box(self,Vector3(side*14.025,-0.12,0),Vector3(0.10,0.18,28.2),"steel")
		for offset in [-12.0,-4.0,4.0,12.0]:
			vault_details.box(self,Vector3(side*17.49,2.45,offset),Vector3(0.14,0.32,0.88),"steel")
			for z in [-0.46,0.46]:
				vault_details.box(self,Vector3(side*17.34,2.45,offset+z),Vector3(0.16,0.32,0.05),"rail")

func _add_guard_segment(start: Vector3, finish: Vector3) -> void:
	var length := start.distance_to(finish)
	var guard := StaticBody3D.new()
	guard.name = "RailingGuard"
	guard.add_to_group("railing_guards")
	guard.position = (start + finish) * 0.5
	guard.rotation.y = atan2(finish.x - start.x, finish.z - start.z)
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.16, 1.05, length + 0.08)
	collider.shape = box
	collider.position.y = 0.525
	guard.add_child(collider)
	_register_coin_blocker(Transform3D(guard.basis,guard.position+Vector3(0,0.525,0)),box.size,false)
	add_child(guard)
	for height in [0.45,0.98]:
		vault_details.tube(guard,Vector3(0,height,-length*0.5),Vector3(0,height,length*0.5),0.043 if height>0.9 else 0.023,"handrail" if height>0.9 else "rail")
	var spans:=maxi(1,int(ceil(length/2.8)))
	for index in range(spans+1):
		var z:float=-length*0.5+length*float(index)/float(spans)
		vault_details.tube(guard,Vector3(0,0.04,z),Vector3(0,0.98,z),0.033,"rail")
		vault_details.tube(guard,Vector3(0,0.90,z),Vector3(0,1.02,z),0.051,"steel")
		vault_details.foot(guard,Vector3(0,0,z))

func _build_stairway() -> void:
	# Three-metre-wide flights stand clear of both wall and platform underside.
	_add_stair_flight(Vector3(-11.5, 0, -14), Vector3(-11.5, -6, 10))
	_add_stair_flight(Vector3(-10, -6, 11.5), Vector3(10, -12, 11.5))
	_add_stair_flight(Vector3(11.5, -12, 10), Vector3(11.5, -18, -10))
	_add_stair_flight(Vector3(10, -18, -11.5), Vector3(-10, -24, -11.5))
	for landing in [Vector3(-11.5, -6, 11.5), Vector3(11.5, -12, 11.5), Vector3(11.5, -18, -11.5), Vector3(-11.5, -24, -11.5)]:
		_add_environment_box(landing+Vector3(0,-0.15,0),Vector3(3,0.3,3),"tread")

func _add_stair_flight(start: Vector3, finish: Vector3) -> void:
	var horizontal := Vector2(finish.x - start.x, finish.z - start.z)
	var horizontal_length := horizontal.length()
	var drop := start.y - finish.y
	var slope := atan2(drop, horizontal_length)
	var yaw := atan2(horizontal.x, horizontal.y)
	var length_3d := sqrt(horizontal_length * horizontal_length + drop * drop)
	var local_basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, slope)
	var center := (start + finish) * 0.5
	center.y -= 0.275
	var flight := StaticBody3D.new()
	flight.transform = Transform3D(local_basis, center)
	add_child(flight)
	var collision := CollisionShape3D.new()
	var ramp_shape := BoxShape3D.new()
	ramp_shape.size = Vector3(3.0, 0.55, length_3d)
	collision.shape = ramp_shape
	flight.add_child(collision)
	_register_coin_blocker(flight.transform,ramp_shape.size)
	var ramp_visual := MeshInstance3D.new()
	var ramp_mesh := BoxMesh.new()
	ramp_mesh.size = Vector3(3.0, 0.55, length_3d)
	ramp_visual.mesh = ramp_mesh
	ramp_visual.material_override = vault_details.material("steel")
	flight.add_child(ramp_visual)
	for side in [-1.0, 1.0]:
		vault_details.tube(flight,Vector3(side*1.57,1.20,-length_3d*0.5),Vector3(side*1.57,1.20,length_3d*0.5),0.043,"handrail")
		vault_details.tube(flight,Vector3(side*1.57,0.72,-length_3d*0.5),Vector3(side*1.57,0.72,length_3d*0.5),0.023,"rail")
		vault_details.box(flight,Vector3(side*1.46,0.04,0),Vector3(0.10,0.32,length_3d),"steel")
		var spans:=maxi(1,int(ceil(length_3d/2.8)))
		for index in range(spans+1):
			var z:float=-length_3d*0.5+length_3d*float(index)/float(spans)
			vault_details.tube(flight,Vector3(side*1.57,0.25,z),Vector3(side*1.57,1.20,z),0.033,"rail")
			vault_details.foot(flight,Vector3(side*1.57,0.25,z))
		var guard_shape := CollisionShape3D.new()
		var guard_box := BoxShape3D.new()
		guard_box.size = Vector3(0.16, 1.05, length_3d)
		guard_shape.shape = guard_box
		guard_shape.position = Vector3(side * 1.57, 0.80, 0)
		flight.add_child(guard_shape)
	var tread_count := 24
	for step in range(tread_count):
		var tread := MeshInstance3D.new()
		var tread_mesh := BoxMesh.new()
		tread_mesh.size = Vector3(2.85, 0.14, horizontal_length / float(tread_count) + 0.02)
		tread.mesh = tread_mesh
		var fraction := (float(step)+0.5)/float(tread_count)
		var world_center := start.lerp(finish,fraction) + Vector3(0,drop/(2.0*float(tread_count))-0.055,0)
		var tread_world := Transform3D(Basis(Vector3.UP,yaw),world_center)
		tread.transform = flight.transform.affine_inverse() * tread_world
		_register_coin_blocker(tread_world,tread_mesh.size)
		coin_stair_treads.append({"inverse":tread_world.affine_inverse(),"half":tread_mesh.size*0.5,"top":world_center.y+0.07})
		tread.material_override = vault_details.material("tread")
		flight.add_child(tread)
		vault_details.box(tread,Vector3(0,0.076,tread_mesh.size.z*0.5-0.04),Vector3(2.83,0.012,0.075),"safety")

func _build_deposit_station() -> void:
	deposit_machine = Node3D.new()
	deposit_machine.name = "VaultCoinIntake"
	deposit_machine.position = deposit_position
	deposit_machine.scale = Vector3.ONE * 0.72
	add_child(deposit_machine)
	var teal := Color("244a48")
	var dark := Color("132b2b")
	var brass := Color("b99047")
	var cream := Color("b8ae8d")
	var oxide := Color("814e36")
	# Raised feet, plinth, and a framed enamel cabinet.
	for x in [-1.05, 1.05]:
		for z in [-0.32, 0.40]:
			_deposit_box(Vector3(x, 0.13, z), Vector3(0.32, 0.26, 0.32), Color("171d1c"))
	_deposit_box(Vector3(0, 0.34, 0.06), Vector3(2.85, 0.22, 1.18), dark)
	_deposit_box(Vector3(0, 0.47, 0.06), Vector3(2.72, 0.06, 1.12), brass)
	_deposit_box(Vector3(0, 1.20, 0), Vector3(2.52, 1.45, 0.96), teal)
	for x in [-1.25, 1.25]:
		_deposit_box(Vector3(x, 1.22, 0.05), Vector3(0.14, 1.50, 1.02), oxide)
	_deposit_box(Vector3(0, 1.98, 0.02), Vector3(2.78, 0.20, 1.12), oxide)
	_deposit_box(Vector3(0, 2.10, 0.02), Vector3(2.62, 0.05, 1.04), brass)
	# Recessed service door with hinges, locking wheel, and latch.
	_deposit_box(Vector3(0, 1.03, 0.50), Vector3(2.19, 0.92, 0.055), Color("101d1d"))
	_deposit_box(Vector3(0, 1.03, 0.55), Vector3(2.04, 0.79, 0.065), dark)
	for x in [-0.93, 0.93]:
		for y in [0.71, 1.34]:
			_deposit_round(Vector3(x, y, 0.60), 0.035, 0.025, brass)
	for y in [0.83, 1.20]:
		_deposit_box(Vector3(-1.07, y, 0.60), Vector3(0.10, 0.20, 0.07), brass)
	_deposit_round(Vector3(-0.27, 1.02, 0.64), 0.235, 0.10, brass)
	_deposit_round(Vector3(-0.27, 1.02, 0.71), 0.18, 0.04, oxide)
	for y in [0.96, 1.02, 1.08]:
		_deposit_box(Vector3(-0.27, y, 0.74), Vector3(0.18, 0.018, 0.018), brass)
	_deposit_box(Vector3(0.68, 1.01, 0.67), Vector3(0.30, 0.065, 0.08), brass)
	_deposit_round(Vector3(0.55, 1.01, 0.68), 0.058, 0.09, brass)
	# Deep black intake and a projecting, sloped metal tray.
	_deposit_box(Vector3(0, 1.72, 0.53), Vector3(2.14, 0.28, 0.045), Color("080f10"))
	var tray := _deposit_box(Vector3(0, 1.57, 0.96), Vector3(2.35, 0.07, 0.95), cream)
	tray.rotation.x = deg_to_rad(-9.0)
	_deposit_box(Vector3(0, 1.53, 1.43), Vector3(2.46, 0.16, 0.07), brass)
	for x in [-1.18, 1.18]:
		var cheek := _deposit_box(Vector3(x, 1.67, 0.96), Vector3(0.07, 0.25, 0.95), cream)
		cheek.rotation.x = deg_to_rad(-9.0)
		var brace := _deposit_box(Vector3(x * 0.87, 1.33, 0.93), Vector3(0.055, 0.07, 0.79), brass)
		brace.rotation.x = deg_to_rad(-30.0)
	for x in [-0.83, -0.42, 0.0, 0.42, 0.83]:
		_deposit_box(Vector3(x, 1.73, 0.59), Vector3(0.035, 0.20, 0.12), brass)
	# Side ventilation slots and casing fasteners.
	for y in [0.76, 0.92, 1.08, 1.24, 1.40]:
		for x in [-1.32, 1.32]:
			_deposit_box(Vector3(x, y, 0.02), Vector3(0.035, 0.045, 0.62), Color("111d1b"))
	# Freestanding counter housing above the intake.
	for x in [-0.95, 0.95]:
		_deposit_box(Vector3(x, 2.27, 0.0), Vector3(0.15, 0.36, 0.45), dark)
	_deposit_box(Vector3(0, 2.72, 0.05), Vector3(2.70, 0.88, 0.87), cream)
	_deposit_box(Vector3(0, 2.72, 0.50), Vector3(2.49, 0.64, 0.07), brass)
	_deposit_box(Vector3(0, 2.72, 0.55), Vector3(2.39, 0.56, 0.04), Color("080f10"))
	_build_deposit_screen()
	for x in [-1.24, 1.24]:
		for y in [2.38, 3.06]:
			_deposit_round(Vector3(x, y, 0.50), 0.027, 0.025, brass)
	_deposit_text("VAULT BALANCE", Vector3(0, 3.07, 0.51), 22, Color("263633"))
	_deposit_text("CV  /  COIN INTAKE", Vector3(0, 2.38, 0.51), 15, Color("263633"))
	_deposit_text("COIN DEPOSIT", Vector3(0, 0.57, 0.60), 20, Color("dbca94"))
	# Circular maker badge and an illuminated ready indicator.
	_deposit_round(Vector3(0, 3.35, 0.12), 0.22, 0.075, brass)
	_deposit_round(Vector3(0, 3.35, 0.17), 0.18, 0.025, teal)
	_deposit_text("CV", Vector3(0, 3.35, 0.195), 25, Color("e4ce94"))
	_deposit_round(Vector3(1.02, 3.19, 0.12), 0.065, 0.08, Color("63b593"))
	var body := StaticBody3D.new()
	body.name = "DepositCabinetCollision"
	_register_coin_blocker(Transform3D(Basis.IDENTITY,deposit_position+Vector3(0,1.6,0.08)*0.72),Vector3(2.8,3.1,1.2)*0.72)
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.8, 3.1, 1.2)
	collider.shape = box
	collider.position = Vector3(0, 1.6, 0.08)
	body.add_child(collider)
	deposit_machine.add_child(body)
	var fixture := _deposit_box(Vector3(-1.85, 3.15, -0.36), Vector3(0.70, 0.22, 0.12), Color("e8c675"))
	fixture.material_override.emission_enabled = true
	fixture.material_override.emission = Color("ffd78c")
	fixture.material_override.emission_energy_multiplier = 0.8
	var task_light := OmniLight3D.new()
	task_light.position = Vector3(-1.3, 2.8, 1.65)
	task_light.light_color = Color("ffe0aa")
	task_light.light_energy = 1.8
	task_light.omni_range = 5.0
	deposit_machine.add_child(task_light)
	_update_deposit_counter()

func _deposit_box(at: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	part.mesh = mesh
	part.position = at
	var material := _material(color)
	material.metallic = 0.55
	material.roughness = 0.37
	part.material_override = material
	deposit_machine.add_child(part)
	return part

func _deposit_round(at: Vector3, radius: float, depth: float, color: Color) -> void:
	var part := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = depth
	mesh.radial_segments = 24
	part.mesh = mesh
	part.position = at
	part.rotation.x = PI * 0.5
	var material := _material(color)
	material.metallic = 0.65
	material.roughness = 0.32
	part.material_override = material
	deposit_machine.add_child(part)

func _deposit_text(value: String, at: Vector3, size: int, color: Color) -> void:
	var label := Label3D.new()
	label.text = value
	label.position = at
	label.font_size = size
	label.pixel_size = 0.004
	label.modulate = color
	label.outline_size = 0
	deposit_machine.add_child(label)

func _build_deposit_screen() -> void:
	var viewport := SubViewport.new()
	viewport.name = "DepositScreen"
	viewport.size = Vector2i(1024, 240)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	deposit_machine.add_child(viewport)
	var screen := Panel.new()
	screen.size = Vector2(1024, 240)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("173f46")
	style.border_color = Color("71d4c6")
	style.set_border_width_all(7)
	style.set_corner_radius_all(48)
	screen.add_theme_stylebox_override("panel", style)
	viewport.add_child(screen)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Comic Sans MS", "Chalkboard SE", "DejaVu Sans"])
	font.font_weight = 700
	deposit_balance_label = Label.new()
	deposit_balance_label.position = Vector2(24, 18)
	deposit_balance_label.size = Vector2(976, 204)
	deposit_balance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	deposit_balance_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	deposit_balance_label.add_theme_font_override("font", font)
	deposit_balance_label.add_theme_font_size_override("font_size", 112)
	deposit_balance_label.add_theme_color_override("font_color", Color("fff0ad"))
	deposit_balance_label.add_theme_color_override("font_outline_color", Color("082c34"))
	deposit_balance_label.add_theme_constant_override("outline_size", 12)
	screen.add_child(deposit_balance_label)
	var display := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2.39, 0.56)
	display.mesh = quad
	display.position = Vector3(0, 2.72, 0.58)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture = viewport.get_texture()
	display.material_override = material
	deposit_machine.add_child(display)

func _update_deposit_counter() -> void:
	if deposit_balance_label == null:return
	var digits := str(banked_coins)
	var formatted := ""
	for index in range(digits.length()):
		if index > 0 and (digits.length() - index) % 3 == 0:formatted += ","
		formatted += digits[index]
	deposit_balance_label.text = formatted
	deposit_balance_label.add_theme_font_size_override("font_size", mini(112, int(850.0 / maxf(1, formatted.length() * 0.68))))
	deposit_balance_label.get_viewport().render_target_update_mode = SubViewport.UPDATE_ONCE

func _build_coin_pile() -> void:
	coin_mass_visual = Node3D.new()
	coin_mass_visual.position = Vector3(0, COIN_PILE_BASE_Y, 0)
	add_child(coin_mass_visual)
	var shader := Shader.new()
	shader.code = _coin_mass_shader_code()
	var top_material := ShaderMaterial.new()
	top_material.shader = shader
	top_material.set_shader_parameter("coin_grid", Vector2(float(STATIC_COIN_GRID), float(STATIC_COIN_GRID)))
	var side_material := ShaderMaterial.new()
	side_material.shader = shader
	side_material.set_shader_parameter("coin_grid", Vector2(float(STATIC_COIN_GRID), 32.0))

	coin_mass_mesh = MeshInstance3D.new()
	coin_mass_mesh.mesh = null
	coin_mass_mesh.material_override = top_material
	coin_mass_mesh.visible = false
	coin_mass_visual.add_child(coin_mass_mesh)
	var heap_collision := StaticBody3D.new()
	heap_collision_shape = CollisionShape3D.new()
	heap_heightmap = HeightMapShape3D.new()
	heap_collision_shape.shape = heap_heightmap
	heap_collision.add_child(heap_collision_shape)
	var floor_collision := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(VAULT_WIDTH - 0.2, 0.4, VAULT_DEPTH - 0.2)
	floor_collision.shape = floor_shape
	floor_collision.position.y = VAULT_BOTTOM-COIN_PILE_BASE_Y-0.2
	heap_collision.add_child(floor_collision)
	heap_collision.position = Vector3(0, COIN_PILE_BASE_Y, 0)
	add_child(heap_collision)
	_update_heap_collision_map()
	var width := VAULT_WIDTH - 0.2
	var depth := VAULT_DEPTH - 0.2
	var edge_height := 0.22
	_add_mass_side(Vector3(0, edge_height * 0.5, -depth * 0.5), Vector3(width, edge_height, 0.2), side_material)
	_add_mass_side(Vector3(0, edge_height * 0.5, depth * 0.5), Vector3(width, edge_height, 0.2), side_material)
	_add_mass_side(Vector3(-width * 0.5, edge_height * 0.5, 0), Vector3(0.2, edge_height, depth), side_material)
	_add_mass_side(Vector3(width * 0.5, edge_height * 0.5, 0), Vector3(0.2, edge_height, depth), side_material)
	_update_coin_mass_shape()
	_prepare_physics_coin_resources()
	_build_static_coin_layers()
	_build_collectible_coin_field()

func _update_heap_collision_map() -> void:
	if heap_heightmap == null:
		return
	heap_heightmap.map_width = HEAP_COLLISION_RESOLUTION
	heap_heightmap.map_depth = HEAP_COLLISION_RESOLUTION
	var heights := PackedFloat32Array()
	heights.resize(HEAP_COLLISION_RESOLUTION * HEAP_COLLISION_RESOLUTION)
	var half_width := float(HEAP_COLLISION_RESOLUTION - 1) * 0.5
	var remaining_ratio := 1.0
	for row in range(HEAP_COLLISION_RESOLUTION):
		var z := float(row) - half_width
		for column in range(HEAP_COLLISION_RESOLUTION):
			var x := float(column) - half_width
			heights[row * HEAP_COLLISION_RESOLUTION + column] = _walkable_coin_height(x, z) * remaining_ratio
	heap_heightmap.map_data = heights
	if coin_mass_mesh != null and not surface_poses.is_empty() and not run_active:
		_update_coin_skin_patches()

func _update_coin_skin_patches() -> void:
	coin_skin_dirty_patches.clear()
	if coin_mass_mesh!=null:coin_mass_mesh.hide()

func _mark_coin_skin_region(_index: int) -> void:
	pass

func _register_coin_blocker(blocker_transform: Transform3D, size: Vector3, occludes: bool = true) -> void:
	var bounds := blocker_transform * AABB(-size * 0.5, size)
	var blocker := {"inverse": blocker_transform.affine_inverse(), "half": size * 0.5, "bounds": bounds,"id":coin_blocker_serial,"occludes":occludes}
	coin_blocker_serial+=1
	for z in range(int(floor((bounds.position.z - 0.4) / 2.0)), int(floor((bounds.end.z + 0.4) / 2.0)) + 1):
		for x in range(int(floor((bounds.position.x - 0.4) / 2.0)), int(floor((bounds.end.x + 0.4) / 2.0)) + 1):
			var key := Vector2i(x,z)
			if not coin_blocker_bins.has(key):
				coin_blocker_bins[key] = []
			coin_blocker_bins[key].append(blocker)
			if not (size.x >= 35.0 and size.z >= 35.0 and size.y < 0.8):
				coin_skin_structure_bins[key] = true

func _coin_pose_is_clear(pose: Transform3D) -> bool:
	var world := Transform3D(Basis.IDENTITY, Vector3(0,COIN_PILE_BASE_Y,0)) * pose
	# Fill to the actual vault walls; the platform remains a solid overhang.
	if absf(world.origin.x) + PHYSICS_COIN_RADIUS > 17.59 or absf(world.origin.z) + PHYSICS_COIN_RADIUS > 17.59:
		return false
	var normal := world.basis.y.normalized()
	var half_height := PHYSICS_COIN_THICKNESS * 0.5 * pose.basis.y.length()
	var extent := Vector3(sqrt(maxf(0,1-normal.x*normal.x))*PHYSICS_COIN_RADIUS + absf(normal.x)*half_height, sqrt(maxf(0,1-normal.y*normal.y))*PHYSICS_COIN_RADIUS + absf(normal.y)*half_height, sqrt(maxf(0,1-normal.z*normal.z))*PHYSICS_COIN_RADIUS + absf(normal.z)*half_height)
	var bounds := AABB(world.origin-extent, extent*2.0)
	var key := Vector2i(int(floor(world.origin.x/2.0)),int(floor(world.origin.z/2.0)))
	for blocker in coin_blocker_bins.get(key, []):
		if not bounds.intersects(blocker.bounds):
			continue
		var inverse: Transform3D = blocker.inverse
		var center := inverse * world.origin
		var axis := (inverse.basis * normal).normalized()
		var projected := Vector3(sqrt(maxf(0,1-axis.x*axis.x))*PHYSICS_COIN_RADIUS + absf(axis.x)*half_height, sqrt(maxf(0,1-axis.y*axis.y))*PHYSICS_COIN_RADIUS + absf(axis.y)*half_height, sqrt(maxf(0,1-axis.z*axis.z))*PHYSICS_COIN_RADIUS + absf(axis.z)*half_height)
		var half: Vector3 = blocker.half
		if absf(center.x) < half.x+projected.x-0.001 and absf(center.y) < half.y+projected.y-0.001 and absf(center.z) < half.z+projected.z-0.001:
			return false
	return true

func _coin_stair_support(pose: Transform3D) -> Dictionary:
	var point := pose.origin + Vector3(0,COIN_PILE_BASE_Y,0)
	for tread in coin_stair_treads:
		var local: Vector3 = tread.inverse * point
		var half: Vector3 = tread.half
		if absf(local.x) > half.x-PHYSICS_COIN_RADIUS-0.015 or absf(local.z) > half.z-PHYSICS_COIN_RADIUS-0.015:
			continue
		var top: float = tread.top
		if top < point.y-0.28 or top > point.y+0.24:
			continue
		var supported := Transform3D(Basis(Vector3.UP, atan2(pose.basis.z.x,pose.basis.z.z)), Vector3(pose.origin.x,top-COIN_PILE_BASE_Y+PHYSICS_COIN_THICKNESS*0.5+0.008,pose.origin.z))
		return {"pose": supported}
	return {}

func _constrain_coin_slide(index: int, desired: Transform3D) -> Transform3D:
	var original := surface_poses[index]
	if coin_stair_columns[index] == 0:
		var border_blend := smoothstep(12.0,14.0,maxf(absf(desired.origin.x),absf(desired.origin.z)))
		var normal := desired.basis.y.normalized()
		var extent := sqrt(maxf(0.0,1.0-normal.y*normal.y))*PHYSICS_COIN_RADIUS+absf(normal.y)*PHYSICS_COIN_THICKNESS*0.5
		var ceiling := -COIN_PILE_BASE_Y-1.50-extent
		desired.origin.y = lerpf(desired.origin.y,minf(desired.origin.y,ceiling),border_blend)
	if coin_stair_columns[index] != 0:
		var support := _coin_stair_support(desired)
		if support.is_empty():
			return original
		desired = support.pose
		desired.origin.y += float(stack_levels[index])*(PHYSICS_COIN_THICKNESS+0.003)
	if _coin_pose_is_clear(desired):
		return desired
	# At a solid boundary, keep the permitted tangential component of the movement.
	var along_x := original
	along_x.origin.x = desired.origin.x
	var along_z := original
	along_z.origin.z = desired.origin.z
	var clear_x := _coin_pose_is_clear(along_x)
	var clear_z := _coin_pose_is_clear(along_z)
	if clear_x and (not clear_z or along_x.origin.distance_squared_to(desired.origin) <= along_z.origin.distance_squared_to(desired.origin)):
		return along_x
	if clear_z:
		return along_z
	return original

func _hide_blocked_column(index: int) -> void:
	if finite_pile_ready:
		_advance_coin_column(index)
		return
	var reserve := column_coins[index]
	column_coins[index] = 0
	for other in range(column_coins.size()):
		if other != index and column_coins[other] > 0 and coin_stair_columns[other] == 0:
			column_coins[other] += reserve
			if conveyor_heap_ready:_queue_conveyor_column(other)
			break
	surface_coins.set_instance_transform(index,Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO),surface_poses[index].origin))
	settling_coins.erase(index)

func _coin_skin_triangle_allowed(a: Vector3, b: Vector3, c: Vector3, cache_key: int) -> bool:
	var center := (a+b+c)/3.0 + Vector3(0,COIN_PILE_BASE_Y,0)
	var key := Vector2i(int(floor(center.x/2.0)),int(floor(center.z/2.0)))
	if not coin_skin_structure_bins.has(key) and minf(a.y,minf(b.y,c.y))+COIN_PILE_BASE_Y > VAULT_BOTTOM+0.4:
		return true
	var heights := Vector3(a.y,b.y,c.y)
	if coin_skin_triangle_cache.has(cache_key) and heights.is_equal_approx(coin_skin_triangle_cache[cache_key].heights):
		return coin_skin_triangle_cache[cache_key].allowed
	var allowed := _test_coin_skin_triangle(a,b,c,key)
	coin_skin_triangle_cache[cache_key] = {"heights":heights,"allowed":allowed}
	return allowed

func _test_coin_skin_triangle(a: Vector3, b: Vector3, c: Vector3, key: Vector2i) -> bool:
	var offset := Vector3(0,COIN_PILE_BASE_Y,0)
	var bounds := AABB(a+offset,Vector3.ZERO).expand(b+offset).expand(c+offset).grow(0.008)
	var center := bounds.get_center()
	var half := bounds.size*0.5
	for blocker in coin_blocker_bins.get(key,[]):
		if not bounds.intersects(blocker.bounds):
			continue
		var inverse: Transform3D = blocker.inverse
		var local := inverse*center
		var size := Vector3(absf(inverse.basis.x.x)*half.x+absf(inverse.basis.y.x)*half.y+absf(inverse.basis.z.x)*half.z,absf(inverse.basis.x.y)*half.x+absf(inverse.basis.y.y)*half.y+absf(inverse.basis.z.y)*half.z,absf(inverse.basis.x.z)*half.x+absf(inverse.basis.y.z)*half.y+absf(inverse.basis.z.z)*half.z)
		var box_half: Vector3=blocker.half
		if absf(local.x)<box_half.x+size.x and absf(local.y)<box_half.y+size.y and absf(local.z)<box_half.z+size.z:
			return false
	return true

func _coin_grid_point(row: int, column: int, layer: int = -1) -> Vector2:
	var step := 35.1 / float(STATIC_COIN_GRID - 1)
	var stagger := (float(row % 2) - 0.5) * step * 0.5
	var point := Vector2(-17.55 + float(column) * step + stagger, -17.55 + float(row) * step)
	var warp := Vector2(sin(point.y * 0.8 + point.x * 0.35) * 0.075, sin(point.x * 0.7 - point.y * 0.24) * 0.065)
	point += warp
	if layer >= 0:
		point += Vector2(step * (0.40 if layer == 0 else -0.25), step * (0.42 if layer == 0 else -0.35))
	return point

func _coin_row_height(x: float, row: int) -> float:
	var step := 35.1 / float(STATIC_COIN_GRID - 1)
	var stagger := (float(row % 2) - 0.5) * step * 0.5
	var grid_x := clampf((x + 17.55 - stagger) / step, 0.0, float(STATIC_COIN_GRID - 1))
	var x0 := int(grid_x)
	var x1 := mini(x0 + 1, STATIC_COIN_GRID - 1)
	return lerpf(surface_poses[row * STATIC_COIN_GRID + x0].origin.y, surface_poses[row * STATIC_COIN_GRID + x1].origin.y, grid_x - float(x0))

func _walkable_coin_height(x: float, z: float) -> float:
	if surface_poses.is_empty():
		return _coin_mass_height(x, z)
	var grid_z := clampf((z + 17.55) * float(STATIC_COIN_GRID - 1) / 35.1, 0.0, float(STATIC_COIN_GRID - 1))
	var z0 := int(grid_z)
	var z1 := mini(z0 + 1, STATIC_COIN_GRID - 1)
	var height := lerpf(_coin_row_height(x,z0),_coin_row_height(x,z1),grid_z-float(z0))
	return minf(height,-COIN_PILE_BASE_Y-0.1) if absf(x)>13.7 or absf(z)>13.7 else height

func _prepare_physics_coin_resources() -> void:
	physics_coin_mesh = _quality_coin_mesh(0)
	physics_coin_material = ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform bool simple_coins = false;
varying vec3 local_position;
varying vec3 local_normal;
varying float coin_tint;
void vertex() {
 coin_tint = 0.94 + fract(sin(dot(MODEL_MATRIX[3].xz, vec2(12.9898, 78.233))) * 43758.5453) * 0.12;
 local_position = VERTEX;
 local_normal = NORMAL;
}
void fragment() {
 if (simple_coins) {
  ALBEDO = vec3(0.69, 0.47, 0.04) * coin_tint;
  METALLIC = 0.75; ROUGHNESS = 0.32;
 } else {
 float radius = length(local_position.xz) / 0.31;
 float face = smoothstep(0.65, 0.95, abs(local_normal.y));
 float rim = smoothstep(0.85, 0.90, radius);
 float angle = atan(local_position.z, local_position.x);
 float milling = 0.5 + 0.5 * sin(angle * 72.0);
 float scratch_phase = radius * 240.0 + sin(angle * 13.0) * 0.7;
 float brushed = sin(scratch_phase) * 0.001 / (1.0 + fwidth(scratch_phase) * 3.0);
 float variation = 0.0;
 vec3 gold = mix(vec3(0.78, 0.51, 0.025), vec3(0.60, 0.43, 0.045), face);
 gold = mix(gold, vec3(0.90, 0.67, 0.075), rim * face * 0.65);
 ALBEDO = gold * coin_tint + vec3(brushed + variation) + (1.0-face) * milling * 0.035;
 METALLIC = 0.89;
 ROUGHNESS = mix(0.19, 0.30, face) + brushed;
 SPECULAR = 0.65;
 }
}
"""
	physics_coin_material.shader = shader

func _make_beveled_coin(segments: int = 40) -> ArrayMesh:
	# Revolved cross section: inset face, raised lip, bevel, and thick edge.
	var profile := [Vector2(0.0, -0.043), Vector2(0.275, -0.043), Vector2(0.298, -0.05), Vector2(0.31, -0.035), Vector2(0.31, 0.035), Vector2(0.298, 0.05), Vector2(0.275, 0.043), Vector2(0.0, 0.043)]
	if segments <= 8:
		profile = [Vector2(0.0,-0.043),Vector2(0.31,-0.043),Vector2(0.31,0.043),Vector2(0.0,0.043)]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring in range(profile.size() - 1):
		var inner: Vector2 = profile[ring]
		var outer: Vector2 = profile[ring + 1]
		var slope := Vector2(outer.x - inner.x, (outer.y - inner.y) * 0.75)
		var normal_2d := Vector2(slope.y, -slope.x).normalized()
		for segment in range(segments):
			var angle_a := TAU * float(segment) / float(segments)
			var angle_b := TAU * float(segment + 1) / float(segments)
			for corner in [Vector2(0, 0), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0), Vector2(0, 1), Vector2(1, 1)]:
				var point: Vector2 = inner if corner.x == 0 else outer
				var angle := angle_a if corner.y == 0 else angle_b
				surface.set_normal(Vector3(cos(angle) * normal_2d.x, normal_2d.y, sin(angle) * normal_2d.x))
				surface.add_vertex(Vector3(cos(angle) * point.x, point.y * 0.75, sin(angle) * point.x))
	return surface.commit()

func _build_static_coin_layers() -> void:
	var backing_mesh := _quality_coin_mesh(1)
	var random := RandomNumberGenerator.new()
	random.seed = 182460
	for layer in range(2):
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = backing_mesh
		mm.instance_count = STATIC_COIN_GRID * STATIC_COIN_GRID
		for row in range(STATIC_COIN_GRID):
			for column in range(STATIC_COIN_GRID):
				var point := _coin_grid_point(row, column, layer)
				var x := clampf(point.x+random.randf_range(-0.035,0.035),-17.26,17.26)
				var z := clampf(point.y+random.randf_range(-0.035,0.035),-17.26,17.26)
				var y := _coin_mass_height(x, z) - 0.065 - float(layer) * 0.085
				var normal := Vector3(-(_coin_mass_height(x + 0.12, z) - _coin_mass_height(x - 0.12, z)) / 0.24, 1.0, -(_coin_mass_height(x, z + 0.12) - _coin_mass_height(x, z - 0.12)) / 0.24).normalized()
				var local_basis := Basis(Quaternion(Vector3.UP, normal)) * Basis.from_euler(Vector3(random.randf_range(-0.025, 0.025), random.randf_range(0.0, TAU), random.randf_range(-0.025, 0.025)))
				var pose := Transform3D(local_basis,Vector3(x,y,z))
				if not _coin_pose_is_clear(pose):
					pose.basis = Basis.IDENTITY.scaled(Vector3.ZERO)
				mm.set_instance_transform(row*STATIC_COIN_GRID+column,pose)
		backing_coin_layers.append(mm)
		var visuals := MultiMeshInstance3D.new()
		visuals.multimesh = mm
		visuals.material_override = physics_coin_material
		coin_mass_visual.add_child(visuals)

func _build_collectible_coin_field() -> void:
	# The surface is a batched field, with no per-coin collision bodies.
	surface_coins = MultiMesh.new()
	surface_coins.transform_format = MultiMesh.TRANSFORM_3D
	surface_coins.mesh = physics_coin_mesh
	var count := STATIC_COIN_GRID * STATIC_COIN_GRID
	surface_coins.instance_count = count
	column_coins.resize(count)
	coin_stair_columns.resize(count)
	column_backing_cursor.resize(count)
	stack_levels.resize(count)
	var random := RandomNumberGenerator.new()
	random.seed = 820314
	for index in range(count):
		var column := index % STATIC_COIN_GRID
		var row := int(index / float(STATIC_COIN_GRID))
		var point := _coin_grid_point(row, column)
		var x := clampf(point.x+random.randf_range(-0.03,0.03),-17.26,17.26)
		var z := clampf(point.y+random.randf_range(-0.03,0.03),-17.26,17.26)
		var normal := Vector3(-(_coin_mass_height(x + 0.12, z) - _coin_mass_height(x - 0.12, z)) / 0.24, 1.0, -(_coin_mass_height(x, z + 0.12) - _coin_mass_height(x, z - 0.12)) / 0.24).normalized()
		var orientation := Basis(Quaternion(Vector3.UP, normal)) * Basis(Vector3.UP, random.randf_range(0.0, TAU))
		orientation = orientation * Basis(Vector3.RIGHT, random.randf_range(-0.075, 0.075))
		# Three interleaved height bands let neighboring discs overlap at their rims.
		var band := posmod(column - int(row / 2.0) - row, 3)
		if band == 2 and random.randf() < 0.28:
			band += 1
		stack_levels[index] = band
		var pose := Transform3D(orientation, Vector3(x, _coin_mass_height(x, z) + PHYSICS_COIN_THICKNESS * 0.5 + float(band) * 0.09 + random.randf_range(-0.003, 0.003), z))
		var support := _coin_stair_support(pose)
		if not support.is_empty():
			var levels := clampi(int(round((pose.origin.y-support.pose.origin.y)/(PHYSICS_COIN_THICKNESS+0.003))),0,2)
			pose = support.pose
			pose.origin.y += float(levels)*(PHYSICS_COIN_THICKNESS+0.003)
			coin_stair_columns[index] = 1
			stack_levels[index] = levels
		if not _coin_pose_is_clear(pose):
			var below := _clear_pose_below_structure(pose)
			if not below.is_empty():
				structure_gap_seeds[index]=pose
				pose=below.pose
				structure_gap_poses[index]=pose
				coin_stair_columns[index]=0
				stack_levels[index]=0
		surface_poses.append(pose)
		surface_home_poses.append(pose)
		var target_bin := Vector2i(floori(pose.origin.x), floori(pose.origin.z))
		if not target_coin_bins.has(target_bin):target_coin_bins[target_bin] = []
		target_coin_bins[target_bin].append(index)
		column_coins[index] = (1+stack_levels[index] if coin_stair_columns[index] != 0 else 1) if _coin_pose_is_clear(pose) else 0
		if column_coins[index] == 0:
			stack_levels[index] = 0
			pose.basis = Basis.IDENTITY.scaled(Vector3.ZERO)
		surface_coins.set_instance_transform(index,pose)
	var regular_columns := 0
	for index in range(count):
		if column_coins[index]>0:regular_columns+=1
	var ordinal := 0
	for index in range(count):
		if column_coins[index]>0:
			column_coins[index]=int(float(STARTING_COIN_COUNT)/regular_columns)+(1 if ordinal<STARTING_COIN_COUNT%regular_columns else 0)
			ordinal+=1
	var visual := MultiMeshInstance3D.new()
	visual.name = "CollectibleCoinField"
	visual.multimesh = surface_coins
	visual.material_override = physics_coin_material
	coin_mass_visual.add_child(visual)
	_build_coin_stack_supports()
	_initialize_finite_pile()
	_rebuild_finite_pile(false)
	_update_heap_collision_map()

func _build_coin_stack_supports() -> void:
	# Compact stacks use shared geometry, with no per-coin physics or scene nodes.
	var poses: Array[Transform3D] = []
	for index in range(surface_poses.size()):
		if column_coins[index] <= 0:
			continue
		var slots: Array[int] = []
		for level in range(1, stack_levels[index] + 1):
			var pose := surface_poses[index]
			pose.origin -= pose.basis.y * (float(level) * (PHYSICS_COIN_THICKNESS + 0.003))
			pose.origin += Vector3(sin(float(index * 11 + level * 7)), 0, cos(float(index * 5 + level * 13))) * 0.012
			if _coin_pose_is_clear(pose):
				slots.append(poses.size())
				poses.append(pose)
		if not slots.is_empty():
			stack_slots[index] = slots
	stack_supports = MultiMesh.new()
	stack_supports.transform_format = MultiMesh.TRANSFORM_3D
	stack_supports.mesh = _make_beveled_coin(20)
	stack_supports.instance_count = poses.size()
	for index in range(poses.size()):
		stack_supports.set_instance_transform(index, poses[index])
	var visual := MultiMeshInstance3D.new()
	visual.name = "ShortCoinStacks"
	visual.multimesh = stack_supports
	visual.material_override = physics_coin_material
	coin_mass_visual.add_child(visual)

func _refresh_coin_stack(index: int, pose: Transform3D) -> void:
	if not stack_slots.has(index):
		return
	var slots: Array = stack_slots[index]
	for level in range(slots.size()):
		var below := pose
		below.origin -= pose.basis.y * (float(level + 1) * (PHYSICS_COIN_THICKNESS + 0.003))
		below.origin += Vector3(sin(float(index * 11 + (level + 1) * 7)), 0, cos(float(index * 5 + (level + 1) * 13))) * 0.012
		if not _coin_pose_is_clear(below):
			below.basis = Basis.IDENTITY.scaled(Vector3.ZERO)
		stack_supports.set_instance_transform(slots[level], below)

func _coin_ray_distance(pose: Transform3D, origin: Vector3, direction: Vector3) -> float:
	# Intersect the tilted disc itself, rather than a large sphere around it.
	var inverse := pose.affine_inverse()
	var local_origin := inverse * origin
	var local_direction := inverse.basis * direction
	var half_height := PHYSICS_COIN_THICKNESS * 0.5
	var radius_squared := PHYSICS_COIN_RADIUS * PHYSICS_COIN_RADIUS
	var nearest := INF
	if absf(local_direction.y) > 0.00001:
		for face_y in [-half_height, half_height]:
			var distance: float = (face_y - local_origin.y) / local_direction.y
			var point := local_origin + local_direction * distance
			if distance > 0.0 and point.x * point.x + point.z * point.z <= radius_squared:
				nearest = minf(nearest, distance)
	var qa := local_direction.x * local_direction.x + local_direction.z * local_direction.z
	if qa > 0.00001:
		var qb := 2.0 * (local_origin.x * local_direction.x + local_origin.z * local_direction.z)
		var qc := local_origin.x * local_origin.x + local_origin.z * local_origin.z - radius_squared
		var discriminant := qb * qb - 4.0 * qa * qc
		if discriminant >= 0.0:
			for distance in [(-qb - sqrt(discriminant)) / (2.0 * qa), (-qb + sqrt(discriminant)) / (2.0 * qa)]:
				if distance > 0.0 and absf(local_origin.y + local_direction.y * distance) <= half_height:
					nearest = minf(nearest, distance)
	return nearest

func _coin_target_is_visible(distance: float) -> bool:
	var start:=camera.global_position
	var finish:=start-camera.global_transform.basis.z*maxf(0.0,distance-0.012)
	return _coin_segment_is_clear(start,finish)

func _coin_segment_is_clear(start:Vector3,finish:Vector3) -> bool:
	var checked:Dictionary={}
	var steps:=maxi(1,int(ceil(start.distance_to(finish)/0.5)))
	for step in range(steps+1):
		var point:=start.lerp(finish,float(step)/float(steps))
		var key:=Vector2i(int(floor(point.x/2.0)),int(floor(point.z/2.0)))
		for blocker in coin_blocker_bins.get(key,[]):
			if not blocker.occludes or checked.has(blocker.id):
				continue
			checked[blocker.id]=true
			var inverse:Transform3D=blocker.inverse
			var half:Vector3=blocker.half
			if AABB(-half,half*2.0).intersects_segment(inverse*start,inverse*finish)!=null:
				return false
	return true

func _find_visible_coin_near_aim() -> int:
	var origin := coin_mass_visual.to_local(camera.global_position)
	var direction := -camera.global_transform.basis.z.normalized()
	var chosen := -1
	var nearest := collection_range
	var finish := origin + direction * collection_range
	# Bins use actual starting poses, including stair-supported and edge columns.
	# One metre covers disc radius and the bounded horizontal settling displacement.
	var margin := 1.0
	for z in range(floori(minf(origin.z, finish.z) - margin), floori(maxf(origin.z, finish.z) + margin) + 1):
		for x in range(floori(minf(origin.x, finish.x) - margin), floori(maxf(origin.x, finish.x) + margin) + 1):
			for index in target_coin_bins.get(Vector2i(x,z), []):
				if column_coins[index] <= 0:
					continue
				var pose := surface_coins.get_instance_transform(index) if settling_coins.has(index) else surface_poses[index]
				var offset := pose.origin - origin
				var along := offset.dot(direction)
				if along < -PHYSICS_COIN_RADIUS or along > nearest + PHYSICS_COIN_RADIUS:
					continue
				if (offset - direction * along).length_squared() > 0.102:
					continue
				var distance := _coin_ray_distance(pose, origin, direction)
				if distance < nearest:
					chosen = index
					nearest = distance
	return chosen if chosen<0 or _coin_target_is_visible(nearest) else -1

func _mark_reserve_region(index: int) -> void:
	_mark_coin_skin_region(index)
	var row := int(index / float(STATIC_COIN_GRID))
	var column := index % STATIC_COIN_GRID
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			var x := column + dx
			var z := row + dz
			if x >= 0 and x < STATIC_COIN_GRID and z >= 0 and z < STATIC_COIN_GRID:
				reserve_dirty_chunks[Vector2i(int(x / float(RESERVE_CHUNK_SIZE)), int(z / float(RESERVE_CHUNK_SIZE)))] = true
				coin_coverage_floor_cache.erase(z*STATIC_COIN_GRID+x)

func _rebuild_dirty_reserves() -> void:
	if reserve_dirty_chunks.is_empty() or surface_poses.is_empty():
		return
	if reserve_coin_mesh == null:
		reserve_coin_mesh = _quality_coin_mesh(2)
	var started := Time.get_ticks_usec()
	for key in reserve_dirty_chunks.keys():
		_rebuild_reserve_chunk(key)
		reserve_dirty_chunks.erase(key)
		if Time.get_ticks_usec() - started >= 1500:
			break

func _rebuild_reserve_chunk(key: Vector2i) -> void:
	var poses: Array[Transform3D] = []
	for row in range(key.y * RESERVE_CHUNK_SIZE, mini((key.y + 1) * RESERVE_CHUNK_SIZE, STATIC_COIN_GRID)):
		for column in range(key.x * RESERVE_CHUNK_SIZE, mini((key.x + 1) * RESERVE_CHUNK_SIZE, STATIC_COIN_GRID)):
			var index := row * STATIC_COIN_GRID + column
			reserve_front_poses.erase(index)
			if column_coins[index] <= 0:
				continue
			var step := _finite_column_step(index) if finite_pile_ready else PHYSICS_COIN_THICKNESS+0.003
			var top := surface_poses[index]
			var lowest := top.origin.y
			# Fill exposed sides all the way to the deepest nearby column, not just two layers.
			for dz in range(-2, 3):
				for dx in range(-2, 3):
					var x := column + dx
					var z := row + dz
					if x >= 0 and x < STATIC_COIN_GRID and z >= 0 and z < STATIC_COIN_GRID:
						lowest = minf(lowest, surface_poses[z * STATIC_COIN_GRID + x].origin.y)
			var existing: int = stack_slots[index].size() if stack_slots.has(index) else 0
			var start_y := top.origin.y - float(existing) * step
			for layer_index in range(column_backing_cursor[index], backing_coin_layers.size()):
				start_y = minf(start_y, backing_coin_layers[layer_index].get_instance_transform(index).origin.y)
			start_y -= step
			var depth := maxf(lowest-0.30,column_floors[index]) if finite_pile_ready else lowest-0.30
			var available := maxi(0, column_coins[index] - 1 - existing - (backing_coin_layers.size() - column_backing_cursor[index]))
			var layers := mini(available,maxi(0,int(floor((start_y-depth)/step))+1))
			var signature := Vector3(start_y,depth,float(layers))
			if reserve_column_cache.has(index) and reserve_column_cache[index].signature==signature:
				var cached: Array=reserve_column_cache[index].poses
				poses.append_array(cached)
				if not cached.is_empty():reserve_front_poses[index]=cached[0]
				continue
			var column_poses: Array[Transform3D]=[]
			for level in range(layers):
				var anchor := surface_home_poses[index].origin
				var pose := Transform3D(Basis(Vector3.UP,float(index)*0.37).scaled(Vector3(1,maxf(1,step/PHYSICS_COIN_THICKNESS),1)),Vector3(anchor.x,start_y-float(level)*step,anchor.z))
				# Keep rim gaps staggered at successive depths, with no tall unsupported shaft.
				var phase := float(index * 13 + level * 19)
				pose.origin.x += sin(phase) * 0.010
				pose.origin.z += cos(phase) * 0.010
				pose.origin.x = clampf(pose.origin.x,-17.26,17.26)
				pose.origin.z = clampf(pose.origin.z,-17.26,17.26)
				if not _coin_pose_is_clear(pose):
					continue
				if not reserve_front_poses.has(index):
					reserve_front_poses[index] = pose
				poses.append(pose)
				column_poses.append(pose)
			reserve_column_cache[index]={"signature":signature,"poses":column_poses}
	var visual: MultiMeshInstance3D
	if reserve_chunks.has(key):
		visual = reserve_chunks[key]
	else:
		visual = MultiMeshInstance3D.new()
		visual.name = "ExcavationReserve_%d_%d" % [key.x, key.y]
		visual.material_override = physics_coin_material
		coin_mass_visual.add_child(visual)
		reserve_chunks[key] = visual
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = reserve_coin_mesh
	multimesh.instance_count = poses.size()
	for index in range(poses.size()):
		multimesh.set_instance_transform(index, poses[index])
	visual.multimesh = multimesh

func _advance_coin_column(index: int) -> void:
	if finite_pile_ready:
		settling_coins.erase(index)
		var pose := _finite_column_pose(index)
		_set_surface_pose(index,pose)
		surface_coins.set_instance_transform(index,pose if column_coins[index]>0 else Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO),pose.origin))
		reserve_front_poses.erase(index)
		_mark_reserve_region(index)
		return
	var previous := surface_coins.get_instance_transform(index)
	settling_coins.erase(index)
	if column_coins[index] <= 0:
		surface_coins.set_instance_transform(index, Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), previous.origin))
		return
	var next := previous
	if stack_slots.has(index) and not stack_slots[index].is_empty():
		# Promote the actual next coin in this stack, hiding its old render slot.
		var slot: int = stack_slots[index].pop_front()
		next = stack_supports.get_instance_transform(slot)
		stack_supports.set_instance_transform(slot, Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), next.origin))
		stack_levels[index] = maxi(0, stack_levels[index] - 1)
	elif column_backing_cursor[index] < backing_coin_layers.size():
		var layer := backing_coin_layers[column_backing_cursor[index]]
		next = layer.get_instance_transform(index)
		layer.set_instance_transform(index, Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), next.origin))
		column_backing_cursor[index] += 1
	elif reserve_front_poses.has(index):
		next = reserve_front_poses[index]
	else:
		# Deeper reserves are revealed below the removed coin, never at its old height.
		var phase := float(index * 31 + column_coins[index] * 17)
		next.origin = Vector3(surface_home_poses[index].origin.x + sin(phase) * 0.035, previous.origin.y - (PHYSICS_COIN_THICKNESS + 0.003), surface_home_poses[index].origin.z + cos(phase) * 0.035)
		next.basis = surface_home_poses[index].basis * Basis(Vector3.RIGHT, sin(phase * 0.7) * 0.035)
		next.origin.x = clampf(next.origin.x,-17.26,17.26)
		next.origin.z = clampf(next.origin.z,-17.26,17.26)
	if absf(next.basis.determinant())<0.00001:
		next=previous
		next.origin.y-=PHYSICS_COIN_THICKNESS+0.003
	if not _coin_pose_is_clear(next):
		var below := _clear_pose_below_structure(next)
		if below.is_empty():
			_hide_blocked_column(index)
			return
		next=below.pose
		coin_stair_columns[index]=0
	_set_surface_pose(index, next)
	surface_coins.set_instance_transform(index, next)
	reserve_front_poses.erase(index)
	_mark_reserve_region(index)

func _relax_coin_hole(index: int) -> void:
	if finite_pile_ready:return
	if column_coins[index] <= 0 or coin_stair_columns[index] != 0:
		return
	var row := int(index / float(STATIC_COIN_GRID))
	var column := index % STATIC_COIN_GRID
	var target := surface_poses[index]
	var donor := -1
	var highest := target.origin.y + 0.24
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var x := column + dx
			var z := row + dz
			if x < 0 or x >= STATIC_COIN_GRID or z < 0 or z >= STATIC_COIN_GRID:
				continue
			var neighbor := z * STATIC_COIN_GRID + x
			if neighbor != index and column_coins[neighbor] > 1 and surface_poses[neighbor].origin.y > highest:
				donor = neighbor
				highest = surface_poses[neighbor].origin.y
	if donor < 0:
		return
	var from := surface_coins.get_instance_transform(donor)
	target.origin.y = minf(highest-PHYSICS_COIN_THICKNESS-0.015,surface_home_poses[index].origin.y+0.06)
	target.basis = from.basis
	target = _constrain_coin_slide(index,target)
	if target.origin.distance_squared_to(surface_poses[index].origin)<0.000001 or not _coin_pose_is_clear(target):
		return
	# One existing neighboring coin slides into the hole: no coins are created.
	column_coins[donor] -= 1
	column_coins[index] += 1
	_advance_coin_column(donor)
	target.origin.y = minf(highest - PHYSICS_COIN_THICKNESS - 0.015, surface_home_poses[index].origin.y + 0.06)
	target.basis = from.basis
	_set_surface_pose(index, target)
	surface_coins.set_instance_transform(index, from)
	_refresh_coin_stack(index, target)
	if not settling_coins.has(index) and settling_coins.size() >= settling_limit:
		var oldest: int = settling_coins.keys()[0]
		surface_coins.set_instance_transform(oldest, surface_poses[oldest])
		_refresh_coin_stack(oldest, surface_poses[oldest])
		settling_coins.erase(oldest)
	settling_coins[index] = {"time": 0.0, "velocity": Vector3.ZERO, "delay": 0.025}
	reserve_front_poses.erase(index)
	_mark_reserve_region(index)

func _take_visible_coin_near_aim() -> bool:
	return _take_coin_at_index(_find_visible_coin_near_aim())

func _take_coin_at_index(chosen:int,settle_neighbors:bool=true) -> bool:
	if chosen < 0 or chosen >= column_coins.size() or column_coins[chosen] <= 0:return false
	_animate_collected_coin(surface_coins.get_instance_transform(chosen))
	column_coins[chosen] -= 1
	var row := int(chosen / float(STATIC_COIN_GRID))
	var column := chosen % STATIC_COIN_GRID
	var center := surface_poses[chosen].origin
	_advance_coin_column(chosen)
	if finite_pile_ready or not settle_neighbors:
		_mark_reserve_region(chosen)
		coin_support_dirty=true
		return true
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			var x := column + dx
			var z := row + dz
			if x < 0 or x >= STATIC_COIN_GRID or z < 0 or z >= STATIC_COIN_GRID:
				continue
			var index := z * STATIC_COIN_GRID + x
			if column_coins[index] <= 0:
				settling_coins.erase(index)
				surface_coins.set_instance_transform(index, Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), surface_poses[index].origin))
				if stack_slots.has(index):
					for slot in stack_slots[index]:
						stack_supports.set_instance_transform(slot, Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), surface_poses[index].origin))
				continue
			var rest := surface_poses[index]
			var home := surface_home_poses[index]
			var inward := center - rest.origin
			inward.y = 0.0
			var distance := inward.length()
			if index != chosen and distance > 0.95:
				continue
			var influence := maxf(0.0, 1.0 - distance / 1.05)
			var phase := float(index * 17 + column_coins[chosen] * 13)
			var drop := 0.0 if index == chosen else influence * 0.006
			if index != chosen:
				rest.origin.y = maxf(minf(home.origin.y - 0.68, rest.origin.y), rest.origin.y - drop)
			if index != chosen and distance > 0.01:
				var slide := inward.normalized() * influence * 0.012
				var offset := rest.origin + slide - home.origin
				offset.y = 0.0
				if offset.length() <= 0.07:
					rest.origin += slide
				var axis := Vector3(inward.z, 0, -inward.x).normalized()
				rest.basis = home.basis * Basis(axis, influence * 0.035 * sin(phase))

			rest = _constrain_coin_slide(index,rest)
			_set_surface_pose(index, rest)
			_refresh_coin_stack(index, rest)
			for layer_index in range(column_backing_cursor[index], backing_coin_layers.size()):
				var layer := backing_coin_layers[layer_index]
				var below := layer.get_instance_transform(index)
				below.origin.y -= drop
				below.origin.y = maxf(home.origin.y - 0.95, below.origin.y)
				layer.set_instance_transform(index, below)
			if not settling_coins.has(index) and settling_coins.size() >= settling_limit:
				surface_coins.set_instance_transform(index, rest)
				continue
			if index == chosen:
				continue
			var velocity: Vector3 = settling_coins[index].velocity if settling_coins.has(index) else Vector3.ZERO
			settling_coins[index] = {"time": 0.0, "velocity": velocity, "delay": 0.025 + fmod(phase, 7.0) * 0.008}
	_relax_coin_hole(chosen)
	coin_support_dirty = true
	return true

func _animate_collected_coin(pose: Transform3D) -> void:
	if pickup_flights.size() >= pickup_visual_limit:
		var oldest: Dictionary = pickup_flights.pop_front()
		oldest.mesh.queue_free()
	var coin := MeshInstance3D.new()
	coin.name = "CollectedCoinVisual"
	coin.mesh = physics_coin_mesh
	coin.material_override = physics_coin_material
	coin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(coin)
	var start := coin_mass_visual.global_transform * pose
	coin.global_transform = start
	pickup_flights.append({"mesh": coin, "start": start, "time": 0.0})

func _tick_pickup_flights(delta: float) -> void:
	for index in range(pickup_flights.size() - 1, -1, -1):
		var flight: Dictionary = pickup_flights[index]
		flight.time += delta
		var t: float = flight.time / 0.20
		var coin: MeshInstance3D = flight.mesh
		if t >= 1.0:
			coin.queue_free()
			pickup_flights.remove_at(index)
			continue
		var start: Transform3D = flight.start
		# A quick local flick disappears at the pickup, leaving the exposed layer visible.
		var flight_position := start.origin + Vector3.UP * sin(t * PI) * 0.14
		var spin := Basis(camera.global_transform.basis.x.normalized(), t * PI * 0.75)
		var size := 1.0 - smoothstep(0.08, 1.0, t)
		coin.global_transform = Transform3D((spin * start.basis).scaled(Vector3.ONE * maxf(size, 0.001)), flight_position)

func _tick_coin_settling(delta: float) -> void:
	# Bounded local contact response; nothing elsewhere in the pile is simulated.
	var dt := minf(delta, 0.033)
	for index in settling_coins.keys():
		var state: Dictionary = settling_coins[index]
		state.time += delta
		if state.time < state.delay:
			continue
		var rest := surface_poses[index]
		var moving := surface_coins.get_instance_transform(index)
		var velocity: Vector3 = state.velocity
		velocity += ((rest.origin - moving.origin) * 160.0 - velocity * 24.0) * dt
		moving.origin += velocity * dt
		moving.basis = moving.basis.slerp(rest.basis, 1.0 - exp(-14.0 * dt))
		state.velocity = velocity
		if not _coin_pose_is_clear(moving):
			moving = _constrain_coin_slide(index,moving)
		if state.time >= 0.65 or (state.time > 0.15 and moving.origin.distance_squared_to(rest.origin) < 0.000001 and velocity.length_squared() < 0.00001):
			surface_coins.set_instance_transform(index, rest)
			_refresh_coin_stack(index, rest)
			settling_coins.erase(index)
		else:
			surface_coins.set_instance_transform(index, moving)
			_refresh_coin_stack(index, moving)

func _coin_mass_shader_code() -> String:
	return """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;
uniform vec2 coin_grid=vec2(64.0);
void fragment() {
 ALBEDO=vec3(0.40,0.28,0.045);
 METALLIC=0.68;
 ROUGHNESS=0.52;
}
"""

func _coin_column_coverage_floor(index: int) -> float:
	if coin_coverage_floor_cache.has(index):
		return coin_coverage_floor_cache[index]
	var pose := surface_poses[index]
	var floor_y := pose.origin.y-PHYSICS_COIN_RADIUS*sqrt(maxf(0.0,1.0-pose.basis.y.normalized().y*pose.basis.y.normalized().y))-PHYSICS_COIN_THICKNESS*0.5
	for layer in backing_coin_layers:
		var below := layer.get_instance_transform(index)
		if not is_zero_approx(below.basis.determinant()):
			var normal := below.basis.y.normalized()
			floor_y=minf(floor_y,below.origin.y-PHYSICS_COIN_RADIUS*sqrt(maxf(0.0,1.0-normal.y*normal.y))-PHYSICS_COIN_THICKNESS*0.5)
	coin_coverage_floor_cache[index]=floor_y
	return floor_y

func _coin_coverage_height(x: float,z: float) -> float:
	if surface_poses.is_empty():
		return _coin_mass_height(x,z)-0.60
	var column := int(round((x+17.55)*float(STATIC_COIN_GRID-1)/35.1))
	var row := int(round((z+17.55)*float(STATIC_COIN_GRID-1)/35.1))
	var lowest := INF
	for dz in range(-2,3):
		for dx in range(-2,3):
			var ix:=clampi(column+dx,0,STATIC_COIN_GRID-1)
			var iz:=clampi(row+dz,0,STATIC_COIN_GRID-1)
			lowest=minf(lowest,_coin_column_coverage_floor(iz*STATIC_COIN_GRID+ix))
	return lowest-0.45

func _build_mass_surface(start_column: int = 0, start_row: int = 0, resolution: int = MASS_MESH_RESOLUTION) -> ArrayMesh:
	var stride := resolution+1
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	points.resize(stride*stride)
	normals.resize(points.size())
	uvs.resize(points.size())
	var width := VAULT_WIDTH-0.2
	var depth := VAULT_DEPTH-0.2
	for row in range(stride):
		var z := lerpf(-depth*0.5,depth*0.5,float(row+start_row)/float(MASS_MESH_RESOLUTION))
		for column in range(stride):
			var x := lerpf(-width*0.5,width*0.5,float(column+start_column)/float(MASS_MESH_RESOLUTION))
			var index := row*stride+column
			points[index] = Vector3(x,_coin_coverage_height(x,z),z)
			uvs[index] = Vector2(float(column+start_column)/float(MASS_MESH_RESOLUTION),float(row+start_row)/float(MASS_MESH_RESOLUTION))
	for row in range(stride):
		for column in range(stride):
			var left := points[row*stride+maxi(0,column-1)]
			var right := points[row*stride+mini(resolution,column+1)]
			var up := points[maxi(0,row-1)*stride+column]
			var down := points[mini(resolution,row+1)*stride+column]
			normals[row*stride+column] = Vector3(-(right.y-left.y)/(right.x-left.x),1.0,-(down.y-up.y)/(down.z-up.z)).normalized()
	var indices := PackedInt32Array()
	for row in range(resolution):
		for column in range(resolution):
			var a := row*stride+column
			var b := a+1
			var c := a+stride
			var d := c+1
			var cache_key := ((row+start_row)*MASS_MESH_RESOLUTION+column+start_column)*2
			if _coin_skin_triangle_allowed(points[a],points[c],points[b],cache_key):
				indices.append_array(PackedInt32Array([a,c,b]))
			if _coin_skin_triangle_allowed(points[b],points[c],points[d],cache_key+1):
				indices.append_array(PackedInt32Array([b,c,d]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

func _coin_mass_height(x: float, z: float) -> float:
	# Broad, warped contours blend into the lower perimeter without a cut-off shelf.
	var warped_x := x+sin(z*0.26)*0.65
	var warped_z := z+sin(x*0.22+1.3)*0.65
	var blend_x := smoothstep(5.8,13.3,absf(warped_x))
	var blend_z := smoothstep(5.8,13.3,absf(warped_z))
	var perimeter_blend := 1.0-(1.0-blend_x)*(1.0-blend_z)
	var broad_waves := sin(x*0.34+z*0.16)*0.28+cos(z*0.47-x*0.13)*0.17
	var ripple := sin(x*0.43+sin(z*0.27))*cos(z*0.37+sin(x*0.21))*0.055
	var small_heaps := sin(x*1.17+sin(z*0.71))*cos(z*1.03)*0.075
	var dents := 0.0
	for basin in [Vector4(-5.0,-3.0,3.2,0.56),Vector4(5.0,4.0,3.8,0.72),Vector4(0.0,-9.0,2.8,0.46),Vector4(9.0,-7.0,3.0,0.50),Vector4(-10.0,8.0,3.4,0.58)]:
		var dx: float=(x-basin.x)/basin.z
		var dz: float=(z-basin.y)/(basin.z*0.78)
		dents+=basin.w*exp(-(dx*dx+dz*dz))
	var inner := 1.2*tanh((0.94+broad_waves+ripple+small_heaps-dents)/1.2)
	var outer := -0.45+sin(x*0.31+z*0.13)*0.065+cos(z*0.37-x*0.11)*0.05+small_heaps*0.3
	return lerpf(inner,outer,perimeter_blend)

func _add_mass_side(_at:Vector3,_dimensions:Vector3,_finish:ShaderMaterial) -> void:
	pass

func _update_coin_mass_shape() -> void:
	if coin_mass_visual == null:
		return
	coin_mass_visual.scale.y = 1.0
	_update_heap_collision_map()

func _ray_intersects_coin_mass() -> bool:
	return _find_visible_coin_near_aim() >= 0

func _build_player() -> void:
	player = CharacterBody3D.new()
	player.position = TOP_PLATFORM_SPAWN
	player.rotation.y = PI
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.38
	capsule.height = 1.8
	collision.shape = capsule
	player.add_child(collision)
	camera = Camera3D.new()
	camera.position.y = 0.62
	camera.rotation.x = deg_to_rad(-34.0)
	camera.fov = 78.0
	camera.current = true
	player.add_child(camera)
	add_child(player)

func _update_mass_target(is_targeted: bool) -> void:
	if mass_is_targeted == is_targeted:
		return
	mass_is_targeted = is_targeted
	_set_crosshair_targeted(mass_is_targeted)

func _collect_one_coin_from_mass() -> void:
	if not run_active:return
	if get_tree().paused or not window_focused or mouse_released or pickup_pending or pickup_work_left > 0 or carried_coins >= capacity or not _ray_intersects_coin_mass():
		return
	pickup_pending = true
	var generation := pickup_generation
	await get_tree().create_timer(pickup_delay,false).timeout
	if generation!=pickup_generation:return
	if is_inside_tree() and window_focused and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not upgrade_overlay.visible:
		_finish_coin_pickup()
	await get_tree().create_timer(pickup_recovery,false).timeout
	if generation==pickup_generation:pickup_pending = false

func _finish_coin_pickup() -> void:
	if get_tree().paused or not run_active or pickup_work_left > 0:return
	var target := _find_visible_coin_near_aim()
	_update_mass_target(target >= 0)
	if target < 0 or carried_coins >= capacity or remaining_coins <= 0:return
	pickup_work_left = mini(pickup_amount, mini(capacity - carried_coins, remaining_coins))
	_prepare_scoop(target)
	_drain_pickup_work()

func _prepare_scoop(target:int) -> void:
	scoop_feedback_total=0
	scoop_candidates.clear()
	scoop_eye=coin_mass_visual.to_local(camera.global_position)
	var anchor := surface_poses[target].origin
	# A single action owns a local group, rather than re-aiming between its coins.
	var radius := collection_range
	for z in range(floori(anchor.z-radius-1),floori(anchor.z+radius+1)+1):
		for x in range(floori(anchor.x-radius-1),floori(anchor.x+radius+1)+1):
			for index in target_coin_bins.get(Vector2i(x,z),[]):
				if column_coins[index]<=0:continue
				var at := surface_poses[index].origin
				if Vector2(at.x-anchor.x,at.z-anchor.z).length_squared()<=radius*radius and at.distance_squared_to(scoop_eye)<=pow(collection_range+PHYSICS_COIN_RADIUS,2):
					scoop_candidates.append(index)
	scoop_candidates.sort_custom(func(a:int,b:int):return surface_poses[a].origin.distance_squared_to(anchor)<surface_poses[b].origin.distance_squared_to(anchor))
	scoop_candidates.erase(target)
	scoop_candidates.push_front(target)

func _take_next_scoop_coin() -> bool:
	var checked := scoop_candidates.size()
	for attempt in range(checked):
		var index: int=scoop_candidates.pop_front()
		if column_coins[index]<=0:continue
		var pose := surface_coins.get_instance_transform(index) if settling_coins.has(index) else surface_poses[index]
		if absf(pose.basis.determinant())<0.00001:continue
		var offset := pose.origin-scoop_eye
		if offset.length_squared()<0.00001:continue
		var direction := offset.normalized()
		var distance := _coin_ray_distance(pose,scoop_eye,direction)
		if distance>collection_range or distance<0:continue
		var start := coin_mass_visual.to_global(scoop_eye)
		var finish := coin_mass_visual.to_global(scoop_eye+direction*maxf(0,distance-0.012))
		if not _coin_segment_is_clear(start,finish):continue
		# Round-robin exposed columns: visibly remove separate discs before digging deeper.
		if _take_coin_at_index(index):
			if column_coins[index]>0:scoop_candidates.append(index)
			return true
	return false

func _drain_pickup_work() -> void:
	if get_tree().paused or not window_focused or upgrade_overlay.visible:return
	var started := Time.get_ticks_usec()
	var actual_collected := 0
	# Late-game scoops are distributed over frames, rather than a single long loop.
	while pickup_work_left > 0 and actual_collected < 4:
		if carried_coins + actual_collected >= capacity or actual_collected >= remaining_coins:
			pickup_work_left = 0
			break
		if not _take_next_scoop_coin():
			pickup_work_left = 0
			break
		pickup_work_left -= 1
		actual_collected += 1
		if Time.get_ticks_usec() - started >= 1500:break
	carried_coins += actual_collected
	remaining_coins -= actual_collected
	total_coins_collected += actual_collected
	if pickup_work_left==0:scoop_candidates.clear()
	if actual_collected > 0:
		scoop_feedback_total+=actual_collected
		feedback.scoop(scoop_feedback_total,carried_coins>=capacity)
		_update_hud()

func _try_interact() -> void:
	if player.global_position.distance_to(deposit_position) <= deposit_range:
		if carried_coins > 0:
			var deposited := int(round(float(carried_coins) * banking_multiplier))
			banked_coins += deposited
			feedback.deposit(deposited)
			carried_coins = 0
			_update_hud()
			request_save()
		return

func _update_hint() -> void:
	var key:String=game_settings.binding_label("interact")
	if player.global_position.distance_to(deposit_position)<=deposit_range:
		hint_label.text="[%s]  DEPOSIT %d COINS"%[key,carried_coins] if carried_coins>0 else "DEPOSIT STATION"
	elif carried_coins>=capacity:
		hint_label.text="BAG FULL · RETURN TO DEPOSIT"
	else:
		hint_label.text="[%s]  SKILL TREE" % game_settings.binding_label("skill_tree")

func _build_hud() -> void:
	var layer:=CanvasLayer.new()
	layer.name="GameHUD"
	add_child(layer)
	hud_view=preload("res://vault_hud.gd").new()
	layer.add_child(hud_view)
	hud_label=hud_view.bank_label
	hint_label=Label.new()
	hint_label.anchor_left=0.5
	hint_label.anchor_right=0.5
	hint_label.anchor_top=1.0
	hint_label.anchor_bottom=1.0
	hint_label.offset_top=-112
	hint_label.offset_bottom=-84
	hint_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	hint_label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	hint_label.add_theme_font_size_override("font_size",16)
	hint_label.add_theme_color_override("font_color",Color("e0d9bd"))
	hint_label.add_theme_color_override("font_outline_color",Color("10160f"))
	hint_label.add_theme_constant_override("outline_size",4)
	layer.add_child(hint_label)
	get_viewport().size_changed.connect(_layout_hud_hint)
	_layout_hud_hint()
	_build_crosshair(layer)

func _layout_hud_hint() -> void:
	var width:=minf(720.0,get_viewport().get_visible_rect().size.x-32.0)
	hint_label.offset_left=-width*0.5
	hint_label.offset_right=width*0.5

func _build_crosshair(layer: CanvasLayer) -> void:
	var root := Control.new()
	root.anchor_left = 0.5
	root.anchor_top = 0.5
	root.anchor_right = 0.5
	root.anchor_bottom = 0.5
	root.offset_left = -12
	root.offset_top = -12
	root.offset_right = 12
	root.offset_bottom = 12
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	var positions := [Vector2(10, 2), Vector2(10, 17), Vector2(2, 10), Vector2(17, 10)]
	var sizes := [Vector2(4, 6), Vector2(4, 6), Vector2(6, 4), Vector2(6, 4)]
	for index in range(4):
		var bar := ColorRect.new()
		bar.position = positions[index]
		bar.size = sizes[index]
		bar.color = Color("f2f5f7")
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(bar)
		crosshair_bars.append(bar)
	crosshair_dot = ColorRect.new()
	crosshair_dot.position = Vector2(10, 10)
	crosshair_dot.size = Vector2(4, 4)
	crosshair_dot.color = Color("f4c542")
	crosshair_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(crosshair_dot)

func _set_crosshair_targeted(targeted: bool) -> void:
	var tint := Color("82ffd2") if targeted else Color("f2f5f7")
	for bar in crosshair_bars:
		bar.color = tint
	crosshair_dot.color = Color("f4c542") if targeted else Color("f2f5f7")

func _update_hud() -> void:
	_update_deposit_counter()
	hud_view.update_values(banked_coins,carried_coins,capacity,remaining_coins)
	if upgrade_overlay != null:
		_update_upgrade_menu()

func _build_upgrade_menu() -> void:
	upgrade_overlay = preload("res://skill_tree.gd").new()
	upgrade_overlay.game = self
	hud_view.get_parent().add_child(upgrade_overlay)

func _open_upgrade_menu() -> void:
	_cancel_pickup()
	player.velocity = Vector3.ZERO
	upgrade_overlay.visible = true
	_update_upgrade_menu()
	_sync_mouse_capture()

func _close_upgrade_menu() -> void:
	_cancel_pickup()
	upgrade_overlay.visible = false
	mouse_released = false
	_sync_mouse_capture()

func _update_upgrade_menu() -> void:
	if upgrade_overlay.visible:upgrade_overlay.refresh()

func _add_3d_sign(text_value: String, at: Vector3, tint: Color, size: int) -> void:
	var sign_label := Label3D.new()
	sign_label.text = text_value
	sign_label.position = at
	sign_label.rotation.y = 0.0
	sign_label.modulate = tint
	sign_label.font_size = size
	sign_label.outline_size = 8
	sign_label.pixel_size = 0.01
	add_child(sign_label)

func _add_solid_box(at: Vector3, dimensions: Vector3, tint: Color, cast_shadows: bool = true) -> StaticBody3D:
	_register_coin_blocker(Transform3D(Basis.IDENTITY,at),dimensions)
	var body := StaticBody3D.new()
	body.position = at
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = dimensions
	shape_node.shape = shape
	body.add_child(shape_node)
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	visual.mesh = mesh
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.material_override = _material(tint)
	body.add_child(visual)
	add_child(body)
	return body

func _add_box_visual(at: Vector3, dimensions: Vector3, tint: Color) -> void:
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	visual.mesh = mesh
	visual.position = at
	visual.material_override = _material(tint)
	add_child(visual)

func _material(tint: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.roughness = 0.72
	return material

func _quality_coin_mesh(layer: int) -> ArrayMesh:
	var quality: int = int(game_settings.options.coin_detail)
	var segments: int = [[8, 6, 6], [24, 12, 8], [40, 16, 12]][quality][layer]
	if not coin_mesh_cache.has(segments):
		coin_mesh_cache[segments] = _make_beveled_coin(segments)
	return coin_mesh_cache[segments]

func apply_coin_detail() -> void:
	physics_coin_material.set_shader_parameter("simple_coins", int(game_settings.options.coin_detail) == 0)
	physics_coin_mesh = _quality_coin_mesh(0)
	surface_coins.mesh = physics_coin_mesh
	stack_supports.mesh = physics_coin_mesh
	for backing in backing_coin_layers:backing.mesh = _quality_coin_mesh(1)
	reserve_coin_mesh = _quality_coin_mesh(2)
	for visual in reserve_chunks.values():visual.multimesh.mesh = reserve_coin_mesh
	for flight in pickup_flights:flight.mesh.mesh = physics_coin_mesh


func _set_surface_pose(index: int, pose: Transform3D) -> void:
	var previous := surface_poses[index].origin
	var old_bin := Vector2i(floori(previous.x), floori(previous.z))
	var new_bin := Vector2i(floori(pose.origin.x), floori(pose.origin.z))
	if old_bin != new_bin:
		target_coin_bins[old_bin].erase(index)
		if not target_coin_bins.has(new_bin):target_coin_bins[new_bin] = []
		target_coin_bins[new_bin].append(index)
	surface_poses[index] = pose
	if conveyor_heap_ready:_queue_conveyor_column(index)

func _boot_title() -> void:
	menu_camera=Camera3D.new()
	menu_camera.position=Vector3(6,0.3,10)
	menu_camera.fov=78
	add_child(menu_camera)
	menu_camera.look_at(Vector3(-3,-1.4,-9))
	menu_camera.make_current()
	hud_view.get_parent().visible=false
	var layer := CanvasLayer.new()
	layer.layer=80
	add_child(layer)
	start_screen=preload("res://start_screen.gd").new()
	start_screen.game=self
	layer.add_child(start_screen)
	save_status_label=Label.new()
	save_status_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	save_status_label.offset_left=-330
	save_status_label.offset_right=-24
	save_status_label.offset_top=78
	save_status_label.offset_bottom=104
	save_status_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	save_status_label.add_theme_font_size_override("font_size",14)
	save_status_label.add_theme_constant_override("outline_size",3)
	save_status_label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	hud_view.get_parent().add_child(save_status_label)
	Engine.max_fps=30

func begin_run(slot:int,new_game:bool) -> void:
	if run_active:return
	if new_game:
		if not save_store.write_slot(slot,RUN_STATE.capture(self)):
			start_screen.show_error(save_store.error_message)
			return
	else:
		var data: Dictionary=save_store.read_slot(slot)
		if data.is_empty():
			start_screen.show_error(save_store.error_message if save_store.error_message!="" else "That save slot is empty.")
			return
		if not RUN_STATE.restore(self,data):
			start_screen.show_error("This save could not be restored. Its files have been kept.")
			return
	run_active=true
	active_slot=slot
	start_screen.hide()
	camera.make_current()
	hud_view.get_parent().visible=true
	mouse_released=false
	window_focused=get_window().has_focus() or DisplayServer.get_name()=="headless"
	game_settings.apply_to_game(self,false)
	autosave_seconds=0.0
	if not new_game:save_run()
	else:_save_notice(true)
	_sync_mouse_capture()

func open_title_page(page:String) -> void:
	pause_menu.open_menu()
	if page=="settings":pause_menu._show_settings("controls",true)
	else:pause_menu._show_help()

func request_save() -> void:
	if run_active:save_requested=true

func _save_notice(ok:bool) -> void:
	if save_status_label==null:return
	save_status_label.text="SLOT %d / SAVED" % active_slot if ok else "SAVE FAILED / Open pause menu to retry"
	save_status_label.modulate=Color("b8d5ae") if ok else Color("ff9c7c")
	save_notice_seconds=3.0 if ok else 0.0

func _poll_save() -> void:
	if save_thread!=null and not save_thread.is_alive():
		var result: Dictionary=save_thread.wait_to_finish()
		save_thread=null
		last_save_error=result.error
		_save_notice(result.ok)

func _join_save() -> void:
	if save_thread!=null:
		var result: Dictionary=save_thread.wait_to_finish()
		save_thread=null
		last_save_error=result.error

func _start_autosave() -> void:
	if not run_active or save_thread!=null:return
	var data: Dictionary=RUN_STATE.capture(self)
	var slot := active_slot
	var directory: String=save_store.directory
	save_requested=false
	autosave_seconds=0.0
	save_thread=Thread.new()
	var result := save_thread.start(func():
		var store=preload("res://save_store.gd").new()
		store.directory=directory
		var ok: bool=store.write_slot(slot,data)
		return {"ok":ok,"error":store.error_message}
	)
	if result!=OK:
		save_thread=null
		last_save_error="Could not start autosave. Use Save Game in the pause menu."
		_save_notice(false)

func save_run() -> bool:
	if not run_active:return true
	_join_save()
	var ok: bool=save_store.write_slot(active_slot,RUN_STATE.capture(self))
	last_save_error=save_store.error_message
	if ok:
		autosave_seconds=0.0
		save_requested=false
	_save_notice(ok)
	return ok

func return_to_title() -> void:
	if not save_run():
		pause_menu._show_main()
		return
	_cancel_pickup()
	run_active=false
	get_tree().paused=false
	get_tree().reload_current_scene()

func quit_game() -> void:
	if not save_run():
		pause_menu.open_menu()
		pause_menu._show_main()
		return
	get_tree().quit()

func _exit_tree() -> void:
	_join_save()

func _tick_conveyor(delta:float) -> void:
	if not run_active or get_tree().paused:return
	if remaining_coins<=0:
		conveyor_pending=0
		return
	if passive_income_rate>0:
		passive_income_timer+=delta
		if passive_income_timer>=1.0:
			var seconds := int(passive_income_timer)
			passive_income_timer-=seconds
			conveyor_pending=mini(remaining_coins,conveyor_pending+seconds*passive_income_rate)
	if conveyor_pending>0:_drain_conveyor()

func _invalidate_conveyor_order() -> void:
	conveyor_order.clear()
	conveyor_versions.clear()
	conveyor_heap_ready=false

func _build_conveyor_order() -> void:
	_invalidate_conveyor_order()
	conveyor_versions.resize(surface_poses.size())
	conveyor_serial=0
	conveyor_heap_ready=true
	for index in range(surface_poses.size()):_queue_conveyor_column(index)

func _conveyor_higher(a:Dictionary,b:Dictionary) -> bool:
	return a.band>b.band or (a.band==b.band and a.serial<b.serial)

func _conveyor_surface_bias(index:int) -> float:
	var at := surface_home_poses[index].origin
	# Broad spatial variation leaves mounds, with a small changing disc-level irregularity.
	var waves := sin(at.x*0.73+at.z*0.31)*0.16+cos(at.z*0.89-at.x*0.27)*0.08
	var grain := sin(float(index)*12.9898+float(column_coins[index])*7.233)*0.04
	return clampf(waves+grain,-CONVEYOR_SURFACE_RELIEF,CONVEYOR_SURFACE_RELIEF)

func _queue_conveyor_column(index:int) -> void:
	conveyor_versions[index]+=1
	if column_coins[index]<=0:return
	var entry := {"index":index,"band":floori((surface_poses[index].origin.y+_conveyor_surface_bias(index))/CONVEYOR_LAYER_HEIGHT),"version":conveyor_versions[index],"serial":conveyor_serial}
	conveyor_serial+=1
	conveyor_order.append(entry)
	var slot := conveyor_order.size()-1
	while slot>0:
		var parent := ((slot-1)>>1)
		if not _conveyor_higher(entry,conveyor_order[parent]):break
		conveyor_order[slot]=conveyor_order[parent]
		slot=parent
	conveyor_order[slot]=entry

func _pop_conveyor_column() -> Dictionary:
	var top: Dictionary=conveyor_order[0]
	var last: Dictionary=conveyor_order.pop_back()
	if not conveyor_order.is_empty():
		var slot := 0
		while slot*2+1<conveyor_order.size():
			var child := slot*2+1
			if child+1<conveyor_order.size() and _conveyor_higher(conveyor_order[child+1],conveyor_order[child]):child+=1
			if not _conveyor_higher(conveyor_order[child],last):break
			conveyor_order[slot]=conveyor_order[child]
			slot=child
		conveyor_order[slot]=last
	return top

func _next_conveyor_column() -> int:
	if not conveyor_heap_ready or conveyor_order.size()>surface_poses.size()*4:_build_conveyor_order()
	while not conveyor_order.is_empty():
		var entry := _pop_conveyor_column()
		var index: int=entry.index
		if column_coins[index]>0 and entry.version==conveyor_versions[index]:return index
	return -1

func unstuck_player() -> void:
	if not run_active:return
	_cancel_pickup()
	player.position=TOP_PLATFORM_SPAWN
	player.rotation=Vector3(0,PI,0)
	player.velocity=Vector3.ZERO
	camera.rotation=Vector3(deg_to_rad(-34.0),0,0)
	player.reset_physics_interpolation()
	camera.reset_physics_interpolation()
	request_save()

func _drain_conveyor() -> void:
	if not conveyor_heap_ready:_build_conveyor_order()
	var started := Time.get_ticks_usec()
	var removed := 0
	while conveyor_pending>0 and remaining_coins>removed and removed<32:
		var index := _next_conveyor_column()
		if index<0:break
		if not _take_coin_at_index(index,false):break
		conveyor_pending-=1
		removed+=1
		if Time.get_ticks_usec()-started>=1500:break
	if removed>0:
		if feedback!=null:feedback.play("conveyor")
		remaining_coins-=removed
		total_coins_collected+=removed
		banked_coins+=removed
		_update_hud()
	if remaining_coins==0:conveyor_pending=0

func apply_scene_quality(quality:int) -> void:
	settling_limit=[12,24,32][quality]
	pickup_visual_limit=[4,8,12][quality]
	if conveyor_visual!=null:conveyor_visual.quality=quality
	if hud_view!=null:hud_view.feedback_quality=quality
	for finish in vault_details.materials.values():finish.set_shader_parameter("simple_surfaces",quality==0)
	while pickup_flights.size()>pickup_visual_limit:
		var flight: Dictionary=pickup_flights.pop_front()
		flight.mesh.queue_free()
	while settling_coins.size()>settling_limit:
		var index: int=settling_coins.keys()[0]
		surface_coins.set_instance_transform(index,surface_poses[index])
		_refresh_coin_stack(index,surface_poses[index])
		settling_coins.erase(index)

func _clear_pose_below_structure(original:Transform3D) -> Dictionary:
	var pose := Transform3D(Basis(Vector3.UP,atan2(original.basis.z.x,original.basis.z.z)),original.origin)
	# Search only downwards; the flat disc fits against the underside of the solid.
	for step in range(1,301):
		pose.origin.y=original.origin.y-float(step)*0.02
		if pose.origin.y+COIN_PILE_BASE_Y<VAULT_BOTTOM+0.16:break
		if _coin_pose_is_clear(pose):return {"pose":pose}
	return {}

func _repair_legacy_structure_gaps() -> int:
	var fixed := 0
	var allowance := mini(160,maxi(1,int(float(remaining_coins)/float(STATIC_COIN_GRID*STATIC_COIN_GRID))))
	for index in structure_gap_seeds:
		if column_coins[index]!=0:continue
		# Only revive columns that were disabled at generation, never a player-dug hole.
		var initial_pose: Transform3D=structure_gap_seeds[index]
		if not surface_poses[index].origin.is_equal_approx(initial_pose.origin):continue
		var row := int(index/float(STATIC_COIN_GRID))
		var column: int=index%STATIC_COIN_GRID
		var local_top := -INF
		for dz in range(-5,6):
			for dx in range(-5,6):
				var x := column+dx
				var z := row+dz
				if x<0 or x>=STATIC_COIN_GRID or z<0 or z>=STATIC_COIN_GRID:continue
				var neighbor := z*STATIC_COIN_GRID+x
				if not structure_gap_seeds.has(neighbor) and column_coins[neighbor]>0 and coin_stair_columns[neighbor]==0:
					local_top=maxf(local_top,surface_poses[neighbor].origin.y)
		if not is_finite(local_top):continue
		var repaired_pose: Transform3D=structure_gap_poses[index]
		repaired_pose.origin.y=minf(repaired_pose.origin.y,local_top)
		if not _coin_pose_is_clear(repaired_pose):
			var below := _clear_pose_below_structure(repaired_pose)
			if below.is_empty():continue
			repaired_pose=below.pose
		var donor := -1
		var largest := 1
		for other in range(column_coins.size()):
			if not structure_gap_seeds.has(other) and column_coins[other]>largest:
				largest=column_coins[other]
				donor=other
		if donor<0:continue
		var amount := mini(allowance,column_coins[donor]-1)
		column_coins[donor]-=amount
		column_coins[index]=amount
		column_backing_cursor[index]=backing_coin_layers.size()
		stack_levels[index]=0
		stack_slots.erase(index)
		coin_stair_columns[index]=0
		var pose: Transform3D=repaired_pose
		_set_surface_pose(index,pose)
		surface_coins.set_instance_transform(index,pose)
		_mark_reserve_region(index)
		_mark_reserve_region(donor)
		fixed+=1
	while not reserve_dirty_chunks.is_empty():_rebuild_dirty_reserves()
	_invalidate_conveyor_order()
	return fixed

func _sync_stair_support_flags() -> void:
	for index in range(coin_stair_columns.size()):
		if coin_stair_columns[index]!=0 and _coin_stair_support(surface_poses[index]).is_empty():coin_stair_columns[index]=0

func _initialize_finite_pile() -> void:
	var count := surface_poses.size()
	column_capacity.resize(count)
	column_ceilings.resize(count)
	column_floors.resize(count)
	for index in range(count):
		column_capacity[index]=maxi(1,column_coins[index])
		column_ceilings[index]=surface_home_poses[index].origin.y
		var pose := Transform3D(Basis.IDENTITY,surface_home_poses[index].origin)
		pose.origin.y=VAULT_BOTTOM-COIN_PILE_BASE_Y+0.10
		for attempt in range(100):
			if _coin_pose_is_clear(pose):break
			pose.origin.y+=0.03
		column_floors[index]=pose.origin.y
	finite_pile_ready=true

func _finite_column_step(index:int) -> float:
	return maxf(PHYSICS_COIN_THICKNESS+0.003,(column_ceilings[index]-column_floors[index])/float(maxi(1,column_capacity[index]-1)))

func _finite_column_pose(index:int) -> Transform3D:
	var pose := Transform3D(Basis(Vector3.UP,float(index)*0.37),surface_home_poses[index].origin)
	pose.origin.y=column_floors[index]+float(maxi(0,column_coins[index]-1))*_finite_column_step(index)
	if not _coin_pose_is_clear(pose):
		var below := _clear_pose_below_structure(pose)
		if not below.is_empty():pose=below.pose
		else:pose.origin.y=column_floors[index]
	return pose

func _rebuild_finite_pile(normalize_budget:bool) -> void:
	if normalize_budget:
		var assigned := 0
		# Bound hidden reserve outliers before spreading their ledger across the floor.
		var average := float(remaining_coins)/float(column_coins.size())
		var legacy_limit := ceili(average)+maxi(2,ceili(average*0.1))
		for index in range(column_coins.size()):
			column_coins[index]=clampi(column_coins[index],0,mini(column_capacity[index],legacy_limit))
			assigned+=column_coins[index]
		var pending := remaining_coins-assigned
		while pending>0:
			var placed := 0
			for index in range(column_coins.size()):
				if pending==0:break
				if column_coins[index]<column_capacity[index]:
					column_coins[index]+=1
					pending-=1
					placed+=1
			if placed==0:break
		if pending<0:
			for index in range(column_coins.size()):
				var remove := mini(column_coins[index],-pending)
				column_coins[index]-=remove
				pending+=remove
				if pending==0:break
	settling_coins.clear()
	stack_slots.clear()
	stack_supports.instance_count=0
	stack_levels.fill(0)
	column_backing_cursor.fill(backing_coin_layers.size())
	coin_stair_columns.fill(0)
	for layer in backing_coin_layers:
		var hidden := PackedFloat32Array()
		hidden.resize(layer.instance_count*12)
		layer.buffer=hidden
		layer.visible_instance_count=0
	for visual in reserve_chunks.values():visual.queue_free()
	reserve_chunks.clear()
	reserve_column_cache.clear()
	reserve_front_poses.clear()
	reserve_dirty_chunks.clear()
	for index in range(column_coins.size()):
		var pose := _finite_column_pose(index)
		_set_surface_pose(index,pose)
		surface_coins.set_instance_transform(index,pose if column_coins[index]>0 else Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO),pose.origin))
		if column_coins[index]>0:
			var key := Vector2i(int(float(index%STATIC_COIN_GRID)/RESERVE_CHUNK_SIZE),int(float(index)/STATIC_COIN_GRID/RESERVE_CHUNK_SIZE))
			reserve_dirty_chunks[key]=true
	while not reserve_dirty_chunks.is_empty():_rebuild_dirty_reserves()
	_invalidate_conveyor_order()
	coin_skin_dirty_patches.clear()
	coin_mass_mesh.hide()
