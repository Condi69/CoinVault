extends RefCounted
const COUNT := 73*73
const STATS := ["carried_coins","banked_coins","capacity","remaining_coins","collection_range","pickup_amount","banking_multiplier","passive_income_rate","passive_income_timer","total_coins_collected","pickup_delay","pickup_recovery","deposit_range"]

static func capture(game:Node) -> Dictionary:
	var stats: Dictionary={}
	for key in STATS:stats[key]=game.get(key)
	var backing: Array=[]
	for mesh in game.backing_coin_layers:backing.append(mesh.buffer.duplicate())
	var reserves: Dictionary={}
	for key in game.reserve_chunks:reserves[key]=game.reserve_chunks[key].multimesh.buffer.duplicate()
	return {"finite_pile_version":1,"column_capacity":game.column_capacity.duplicate(),"column_ceilings":game.column_ceilings.duplicate(),"stair_gap_fix":1,"saved_at":Time.get_unix_time_from_system(),"played_seconds":game.played_seconds,"stats":stats,"skills":game.skill_progression.purchased.duplicate(),"player":game.player.transform,"camera_pitch":game.camera.rotation.x,"columns":game.column_coins.duplicate(),"cursors":game.column_backing_cursor.duplicate(),"levels":game.stack_levels.duplicate(),"poses":game.surface_poses.duplicate(),"surface_buffer":game.surface_coins.buffer.duplicate(),"backing":backing,"stack_buffer":game.stack_supports.buffer.duplicate(),"stack_slots":game.stack_slots.duplicate(true),"reserves":reserves,"reserve_front":game.reserve_front_poses.duplicate(),"reserve_dirty":game.reserve_dirty_chunks.duplicate(),"settling":game.settling_coins.duplicate(true),"conveyor_pending":game.conveyor_pending,"conveyor_cursor":game.conveyor_cursor,"conveyor_anchor":game.conveyor_anchor}

static func valid(data:Dictionary) -> bool:
	if data.has("finite_pile_version") and (not data.finite_pile_version is int or data.finite_pile_version!=1):return false
	if data.get("finite_pile_version",0)==1:
		if not data.get("column_capacity") is PackedInt32Array or data.column_capacity.size()!=COUNT:return false
		if not data.get("column_ceilings") is PackedFloat32Array or data.column_ceilings.size()!=COUNT:return false
		for i in range(COUNT):
			if data.column_capacity[i]<1 or data.column_capacity[i]>1000000 or not is_finite(data.column_ceilings[i]):return false
	if data.has("stair_gap_fix") and (not data.stair_gap_fix is int or data.stair_gap_fix not in [0,1]):return false
	for key in ["conveyor_pending","conveyor_cursor","conveyor_anchor"]:
		var value=data.get(key,-1 if key=="conveyor_anchor" else 0)
		if not value is int:return false
		if key=="conveyor_pending" and (value<0 or value>1000000):return false
		if key=="conveyor_cursor" and (value<0 or value>=COUNT):return false
		if key=="conveyor_anchor" and (value< -1 or value>=COUNT):return false
	for key in ["saved_at","played_seconds","camera_pitch"]:
		if not data.get(key) is float and not data.get(key) is int:return false
		if not is_finite(float(data[key])):return false
	if data.played_seconds<0 or data.saved_at<=0:return false
	if not data.get("stats") is Dictionary or not data.get("skills") is Dictionary:return false
	var stats: Dictionary=data.stats
	for key in STATS:
		if not stats.get(key) is int and not stats.get(key) is float:return false
		if not is_finite(float(stats[key])) or stats[key]<0 or stats[key]>1e15:return false
	if stats.capacity<1 or stats.carried_coins>stats.capacity or stats.remaining_coins>1000000 or stats.total_coins_collected+stats.remaining_coins!=1000000:return false
	if stats.pickup_amount<1 or stats.pickup_delay<0.01 or stats.pickup_recovery<0.01:return false
	if not data.get("player") is Transform3D or not data.player.origin.is_finite():return false
	if not data.player.basis.is_finite() or data.player.origin.length()>1000:return false
	if not data.get("columns") is PackedInt32Array or data.columns.size()!=COUNT:return false
	if not data.get("cursors") is PackedInt32Array or data.cursors.size()!=COUNT:return false
	if not data.get("levels") is PackedInt32Array or data.levels.size()!=COUNT:return false
	var total := 0
	for i in range(COUNT):
		if data.columns[i]<0 or data.columns[i]>1000000 or data.cursors[i]<0 or data.cursors[i]>2 or data.levels[i]<0 or data.levels[i]>10:return false
		if data.get("finite_pile_version",0)==1 and data.columns[i]>data.column_capacity[i]:return false
		total+=data.columns[i]
	if total!=stats.remaining_coins:return false
	if not data.get("poses") is Array or data.poses.size()!=COUNT:return false
	for pose in data.poses:
		if not pose is Transform3D or not pose.origin.is_finite() or not pose.basis.is_finite():return false
	if not _buffer_valid(data.get("surface_buffer"),COUNT*12):return false
	if not data.get("backing") is Array or data.backing.size()!=2:return false
	for buffer in data.backing:
		if not _buffer_valid(buffer,COUNT*12):return false
	if not _buffer_valid(data.get("stack_buffer"),-1):return false
	if not data.get("stack_slots") is Dictionary:return false
	for column in data.stack_slots:
		if not column is int or column<0 or column>=COUNT or not data.stack_slots[column] is Array:return false
		for index in data.stack_slots[column]:
			if not index is int or index<0 or index>=data.stack_buffer.size()/12:return false
	for key in ["reserves","reserve_front","reserve_dirty","settling"]:
		if not data.get(key) is Dictionary:return false
	for key in data.reserves:
		if not _chunk_valid(key) or not _buffer_valid(data.reserves[key],-1):return false
	for key in data.reserve_dirty:
		if not _chunk_valid(key):return false
	for key in data.reserve_front:
		if not key is int or key<0 or key>=COUNT or not data.reserve_front[key] is Transform3D:return false
	for key in data.settling:
		if not key is int or key<0 or key>=COUNT or not data.settling[key] is Dictionary:return false
		var state: Dictionary=data.settling[key]
		if not state.get("velocity") is Vector3 or not state.velocity.is_finite():return false
		for item in ["time","delay"]:
			if not state.get(item) is float or not is_finite(state[item]):return false
	var catalog=preload("res://skill_progression.gd").new()
	for id in data.skills:
		if not catalog.nodes.has(id) or data.skills[id]!=true:return false
		if catalog.nodes[id].required>stats.total_coins_collected:return false
		for parent in catalog.nodes[id].parents:
			if not data.skills.has(parent):return false
	return true

static func _chunk_valid(key:Variant) -> bool:
	return key is Vector2i and key.x>=0 and key.y>=0 and key.x<10 and key.y<10

static func _buffer_valid(buffer:Variant,expected:int) -> bool:
	if not buffer is PackedFloat32Array or buffer.size()%12!=0 or buffer.size()>3000000:return false
	if expected>=0 and buffer.size()!=expected:return false
	for value in buffer:
		if not is_finite(value):return false
	return true

static func restore(game:Node,data:Dictionary) -> bool:
	if not valid(data):return false
	for key in STATS:game.set(key,data.stats[key])
	game.conveyor_pending=mini(int(data.get("conveyor_pending",0)),game.remaining_coins)
	game.conveyor_cursor=int(data.get("conveyor_cursor",0))
	game.conveyor_anchor=int(data.get("conveyor_anchor",-1))
	game._invalidate_conveyor_order()
	game.played_seconds=data.played_seconds
	game.skill_progression.purchased=data.skills.duplicate()
	game.column_coins=data.columns.duplicate()
	game.column_backing_cursor=data.cursors.duplicate()
	game.stack_levels=data.levels.duplicate()
	game.surface_poses.assign(data.poses)
	game.surface_coins.buffer=data.surface_buffer
	for i in range(2):game.backing_coin_layers[i].buffer=data.backing[i]
	game.stack_supports.instance_count=int(data.stack_buffer.size()/12)
	game.stack_supports.buffer=data.stack_buffer
	game.stack_slots=data.stack_slots.duplicate(true)
	game.target_coin_bins.clear()
	for i in range(COUNT):
		var point: Vector3=game.surface_poses[i].origin
		var key := Vector2i(floori(point.x),floori(point.z))
		if not game.target_coin_bins.has(key):game.target_coin_bins[key]=[]
		game.target_coin_bins[key].append(i)
	game.reserve_coin_mesh=game._quality_coin_mesh(2)
	for visual in game.reserve_chunks.values():visual.queue_free()
	game.reserve_chunks.clear()
	game.reserve_column_cache.clear()
	for key in data.reserves:
		var visual := MultiMeshInstance3D.new()
		visual.name="ExcavationReserve_%d_%d" % [key.x,key.y]
		visual.material_override=game.physics_coin_material
		var mesh := MultiMesh.new()
		mesh.transform_format=MultiMesh.TRANSFORM_3D
		mesh.mesh=game.reserve_coin_mesh
		mesh.instance_count=int(data.reserves[key].size()/12)
		mesh.buffer=data.reserves[key]
		visual.multimesh=mesh
		game.coin_mass_visual.add_child(visual)
		game.reserve_chunks[key]=visual
	game.reserve_front_poses=data.reserve_front.duplicate()
	game.reserve_dirty_chunks=data.reserve_dirty.duplicate()
	game.settling_coins=data.settling.duplicate(true)
	if data.get("finite_pile_version",0)==1:
		game.column_capacity=data.column_capacity.duplicate()
		game.column_ceilings=data.column_ceilings.duplicate()
	else:
		game._rebuild_finite_pile(true)
	game._sync_stair_support_flags()
	game.coin_coverage_floor_cache.clear()
	game.coin_skin_triangle_cache.clear()
	for key in game.coin_skin_patches:game.coin_skin_dirty_patches[key]=true
	game._update_heap_collision_map()
	game.player.transform=data.player
	game.player.velocity=Vector3.ZERO
	game.camera.rotation.x=clampf(data.camera_pitch,deg_to_rad(-85),deg_to_rad(85))
	game._cancel_pickup()
	game._update_hud()
	return true

