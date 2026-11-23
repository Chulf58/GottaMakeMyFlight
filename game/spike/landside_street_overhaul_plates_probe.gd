extends SceneTree
## Windowed probe of the landside street, tunnel portals, and curb dressing in
## the real main.tscn. DO NOT launch while another windowed Godot holds the slot.
##
## Run from repo root:
##   tools/godot.sh --display-driver windows --rendering-driver vulkan \
##     --audio-driver Dummy --path game -s res://spike/landside_street_overhaul_plates_probe.gd

const OUT_REL := "res://../tools/blender/out/landside_overhaul"
const MAIN_SCENE := "res://main/main.tscn"
const MARGIN_PX := 6.0
const HANG_LIMIT_MS := 120000
const TICK_LIMIT := 60000
const GLASS := "res://assets/materials/tp_glass.tres"

var _out_dir := ""
var _failed := false
var _stage := "init"
var _heartbeat_ms := 0
var _guard_mutex := Mutex.new()
var _guard_stop := false
var _guard: Thread
var _main: Node3D
var _clock: SimClock
var _landside: LandsideSim
var _views: LandsideViews
var _hud: PassengerHud
var _rig: TycoonCamera
var _cam: Camera3D


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_beat("init")
	_guard = Thread.new()
	_guard.start(_watch)
	_run.call_deferred()


func _process(_delta: float) -> bool:
	_beat(_stage)
	return false


func _beat(stage: String) -> void:
	_guard_mutex.lock()
	_stage = stage
	_heartbeat_ms = Time.get_ticks_msec()
	_guard_mutex.unlock()


func _watch() -> void:
	while true:
		OS.delay_msec(500)
		_guard_mutex.lock()
		var stop := _guard_stop
		var idle_ms := Time.get_ticks_msec() - _heartbeat_ms
		var stage := _stage
		_guard_mutex.unlock()
		if stop:
			return
		if idle_ms > HANG_LIMIT_MS:
			print("PROBE_INVALID hang stage=%s no heartbeat for %d ms" % [stage, idle_ms])
			OS.crash("landside street overhaul probe hung")


func _run() -> void:
	await _boot()
	await _plate_east_portal_car()
	await _plate_forecourt_closeup()
	await _plate_west_portal_car()
	await _plate_overview()
	_guard_mutex.lock()
	_guard_stop = true
	_guard_mutex.unlock()
	_guard.wait_to_finish()
	print("PROBE done failed=%s" % _failed)
	quit(1 if _failed else 0)


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _boot() -> void:
	_beat("boot")
	randomize()
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_clock = _main.get_node("SimClock")
	var sim_seed := randi()
	_clock.seed_rng(sim_seed)
	print("PROBE sim_seed=%d" % sim_seed)
	root.add_child(_main)
	_clock.set_process(false)
	_landside = _main.get_node("LandsideSim")
	_views = _main.get_node("LandsideViews")
	_hud = _main.get_node("PassengerHud")
	_rig = _main.get_node("TycoonCamera")
	_cam = _main.get_node("TycoonCamera/Camera3D")
	var mode: BuildMode = _main.get_node("BuildMode")
	(mode.get_node("Ghost") as Node3D).visible = false
	_hud.press_starter_terminal()
	var staff: StaffSim = _main.get_node("Staff")
	staff.hire(StaffMember.Role.CHECKIN)
	staff.hire(StaffMember.Role.SECURITY)
	staff.hire(StaffMember.Role.GATE)
	var built := [
		_landside.build_curb(0),
		_landside.build_lot(0),
		_landside.build_lot(1),
	]
	if built != [true, true, true]:
		_invalid("landside build refused: %s" % [built])
	await _frames(10)


func _tick() -> void:
	_clock.set_paused(false)
	_clock.advance(SimClock.STEP)
	_clock.set_paused(true)


func _book_more() -> void:
	var sim: PassengerSim = _main.get_node("PassengerSim")
	var flight := ""
	for id in sim.arrivals.booking_ids():
		flight = sim.arrivals.get_booking(id).flight_id
		break
	if flight != "":
		sim.arrivals.schedule(flight, 24)


func _step_until_vehicle(lane: LandsideVehicle.Lane, x_lo: float, x_hi: float) -> Node3D:
	var booked := false
	while _clock.tick < TICK_LIMIT:
		for i in 10:
			_tick()
			for id in _landside.vehicle_ids():
				var v := _landside.get_vehicle(id)
				if not _views.has_vehicle(id) or v.lane != lane:
					continue
				var node := _views.node_for(id)
				if node.global_position.x >= x_lo and node.global_position.x <= x_hi:
					_views.draw()
					return node
		if not booked and _landside.vehicle_ids().size() > 0:
			booked = true
			_book_more()
		_beat("wait_vehicle lane=%d tick=%d" % [lane, _clock.tick])
		await process_frame
	return null


func _aim(
	label: String, focus: Vector3, distance: float, yaw: float, step: TycoonCamera.AngleStep
) -> void:
	_beat(label)
	_rig.stop_follow()
	_rig.set_angle_step(step)
	_rig.position = focus
	_rig.yaw = yaw
	_rig.distance = distance
	_rig.zoom(1.0)
	await create_timer(1.2).timeout
	await _frames(4)
	_views.draw()
	await _rebuild_colliders()


func _plate_east_portal_car() -> void:
	var car := await _step_until_vehicle(LandsideVehicle.Lane.ROAD_IN, 124.0, 134.5)
	if car == null:
		_invalid("no vehicle emerged cleanly from east portal")
		return
	var portal := _dressing().find_child("TunnelPortalEast", true, false) as Node3D
	await _aim("east_portal", Vector3(141.0, 1.5, -46.0), 54.0, -0.55, TycoonCamera.AngleStep.LOW)
	var ok := _prove_in_frame("east_portal/car", _aabb_of(car))
	ok = _prove_in_frame("east_portal/portal", _aabb_of(portal)) and ok
	ok = _prove_visible("east_portal/car", car) and ok
	ok = _prove_visible("east_portal/portal", portal) and ok
	_save(await _grab(), "godot_east_portal_car.png" if ok else "godot_east_portal_car_INVALID.png")


func _plate_forecourt_closeup() -> void:
	var car := await _step_until_vehicle(LandsideVehicle.Lane.BERTH, -34.0, -7.0)
	if car == null:
		_invalid("no vehicle reached curb berth for forecourt closeup")
		return
	var lamp := _dressing().find_child("ForecourtLamp_1", true, false) as Node3D
	await _aim("forecourt", Vector3(-18.0, 0.2, -55.0), 50.0, -0.58, TycoonCamera.AngleStep.LOW)
	var ok := _prove_in_frame("forecourt/car", _aabb_of(car))
	ok = _prove_in_frame("forecourt/lamp", _aabb_of(lamp)) and ok
	ok = _prove_visible("forecourt/car", car) and ok
	ok = _prove_visible("forecourt/lamp", lamp) and ok
	_save(
		await _grab(),
		"godot_forecourt_closeup.png" if ok else "godot_forecourt_closeup_INVALID.png"
	)


func _plate_west_portal_car() -> void:
	var car := await _step_until_vehicle(LandsideVehicle.Lane.ROAD_OUT, -134.5, -124.0)
	if car == null:
		_invalid("no vehicle drove into west portal")
		return
	var portal := _dressing().find_child("TunnelPortalWest", true, false) as Node3D
	await _aim("west_portal", Vector3(-141.0, 1.5, -46.0), 54.0, 0.55, TycoonCamera.AngleStep.LOW)
	var ok := _prove_in_frame("west_portal/car", _aabb_of(car))
	ok = _prove_in_frame("west_portal/portal", _aabb_of(portal)) and ok
	ok = _prove_visible("west_portal/car", car) and ok
	ok = _prove_visible("west_portal/portal", portal) and ok
	_save(await _grab(), "godot_west_portal_car.png" if ok else "godot_west_portal_car_INVALID.png")


func _plate_overview() -> void:
	var east := _dressing().find_child("TunnelPortalEast", true, false) as Node3D
	var west := _dressing().find_child("TunnelPortalWest", true, false) as Node3D
	await _aim("overview", Vector3(0.0, 0.0, -48.0), 275.0, 0.0, TycoonCamera.AngleStep.MEDIUM)
	var ok := _prove_in_frame("overview/east_portal", _aabb_of(east))
	ok = _prove_in_frame("overview/west_portal", _aabb_of(west)) and ok
	ok = _prove_visible("overview/east_portal", east) and ok
	ok = _prove_visible("overview/west_portal", west) and ok
	_save(await _grab(), "godot_overview.png" if ok else "godot_overview_INVALID.png")


func _dressing() -> LandsideStreetDressing:
	return _views.places().street_dressing()


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw


func _grab() -> Image:
	await _frames(4)
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	return img


func _save(img: Image, file: String) -> void:
	var path := _out_dir.path_join(file)
	if img.save_png(path) != OK:
		_invalid("could not save %s" % path)
		return
	print("PLATE saved %s size=%s" % [path, img.get_size()])


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node)
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		out.append(mi)
	return out


func _aabb_of(node: Node) -> AABB:
	var box := AABB()
	var first := true
	for mi in _meshes(node):
		if not mi.is_visible_in_tree():
			continue
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _opaque_faces(mi: MeshInstance3D) -> PackedVector3Array:
	var faces := PackedVector3Array()
	if mi.mesh == null:
		return faces
	for i in mi.mesh.get_surface_count():
		var mat := mi.get_active_material(i)
		if mat != null and mat.resource_path == GLASS:
			continue
		var arrays := mi.mesh.surface_get_arrays(i)
		var verts_any: Variant = arrays[Mesh.ARRAY_VERTEX]
		if verts_any == null:
			continue
		var verts: PackedVector3Array = verts_any
		var index_any: Variant = arrays[Mesh.ARRAY_INDEX]
		var index: PackedInt32Array = PackedInt32Array() if index_any == null else index_any
		if index.is_empty():
			faces.append_array(verts)
		else:
			for k in index:
				faces.append(verts[k])
	return faces


func _rebuild_colliders() -> void:
	for body in _main.find_children("ProbeBody", "StaticBody3D", true, false):
		body.free()
	for mi in _meshes(_main):
		if mi.mesh == null or mi.skin != null or not mi.is_visible_in_tree() or _dropped(mi):
			continue
		var faces := _opaque_faces(mi)
		if faces.is_empty():
			continue
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		shape.backface_collision = true
		var shape_node := CollisionShape3D.new()
		shape_node.shape = shape
		var body := StaticBody3D.new()
		body.name = "ProbeBody"
		body.add_child(shape_node)
		mi.add_child(body)
	await physics_frame
	await physics_frame


func _dropped(mi: MeshInstance3D) -> bool:
	for i in mi.mesh.get_surface_count():
		var mat := mi.get_active_material(i) as ShaderMaterial
		if mat != null:
			var amount: Variant = mat.get_shader_parameter("dissolve")
			if amount != null and float(amount) >= 0.99:
				return true
	return false


func _prove_in_frame(label: String, box: AABB) -> bool:
	var rect := Rect2(Vector2.ZERO, root.get_visible_rect().size).grow(-MARGIN_PX)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in 8:
		var p := box.get_endpoint(i)
		if _cam.is_position_behind(p):
			_invalid("%s: a corner is behind the camera" % label)
			return false
		var s := _cam.unproject_position(p)
		lo = lo.min(s)
		hi = hi.max(s)
	var ok := rect.has_point(lo) and rect.has_point(hi)
	print("INFRAME %s screen=(%.0f,%.0f)-(%.0f,%.0f) ok=%s" % [label, lo.x, lo.y, hi.x, hi.y, ok])
	if not ok:
		_invalid("%s: projected bounds leave viewport" % label)
	return ok


func _prove_visible(label: String, subject: Node3D) -> bool:
	var targets: Array[Vector3] = []
	for mi in _meshes(subject):
		if not mi.is_visible_in_tree():
			continue
		var faces := _opaque_faces(mi)
		var facing: Array[Vector3] = []
		for i in range(0, faces.size() - 2, 3):
			var a: Vector3 = mi.global_transform * faces[i]
			var b: Vector3 = mi.global_transform * faces[i + 1]
			var c: Vector3 = mi.global_transform * faces[i + 2]
			var mid := (a + b + c) / 3.0
			if (b - a).cross(c - a).dot(_cam.global_position - mid) < 0.0:
				facing.append(mid)
		var step := maxi(1, floori(facing.size() / 12.0))
		for i in range(0, facing.size(), step):
			targets.append(facing[i])
	var space := _cam.get_world_3d().direct_space_state
	var hits := 0
	for t in targets:
		var from := _cam.global_position
		var q := PhysicsRayQueryParameters3D.create(from, t + (t - from).normalized() * 0.05)
		var hit := space.intersect_ray(q)
		if hit and subject.is_ancestor_of(hit.collider):
			hits += 1
	var ok := hits > 0 and hits * 2 >= targets.size()
	print("VISIBLE %s ray_hits=%d/%d ok=%s" % [label, hits, targets.size(), ok])
	if not ok:
		_invalid("%s: occluded (%d/%d rays)" % [label, hits, targets.size()])
	return ok
