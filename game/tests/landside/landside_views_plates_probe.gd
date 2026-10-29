extends SceneTree
## Windowed probe of the landside views in the real main.tscn (Landside 4/4).
##
## Run (one windowed Godot run project-wide; this probe holds the slot while it runs):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://tests/landside/landside_views_plates_probe.gd
##
## main.tscn boots with a random sim seed (printed), the starter terminal (the HUD's
## debug button), a check-in agent and a security officer hired, and surface lot spot 0
## built, and plays until the airport opened and the first car is on the map. Then the
## entrance door is removed: nobody can get out, so cars hold in the curb berths and in
## the lot and later cars queue on road_in, a jam that stands still long enough to
## photograph (the airport stays open once opened, so the flight goes on). The sim is
## stepped by the clock's own advance(), so LandsideViews draws through its real tick
## signal and alpha. Plates, each proving its subjects in frame (projected bounds inside
## the viewport with a margin) and hit by camera rays against colliders of every mesh in
## the scene (meshes the roof dissolve has dropped are left out), else PROBE_INVALID.
## The jam is a forced fixture: the entrance comes out with the grid's staff-reach check
## off for that one edit (a player could not make it), so the plates are evidence of how
## vehicles are drawn, faced, picked and described, not of congestion from play:
##   curb      a car in a berth and the two queued cars nearest the curb's stop
##   select    a queued car clicked through PassengerHud: ring and follow text
##   distance  the whole landside from 200 m
##   lot       DIAGNOSTIC: the provisional lot placement with the sim's 12 slots
##             (white posts), the access lane end (green) and the exit start (red),
##             so the mismatch between the authored slots and the vendor lot shows
##   strip     a driving car over 6 frames a third of a tick apart
## Every drawn vehicle's nose (basis.z) is checked against its lane: -x on road_in,
## road_out and in a berth, +z on the access lane and in a slot, and against the way it
## is drawn moving. Plates go to tools/blender/out/landside/views/.

const OUT_REL := "res://../tools/blender/out/landside/views"
const MAIN_SCENE := "res://main/main.tscn"
const CAMERA_RIG := "TycoonCamera"
const MARGIN_PX := 8.0
const HANG_LIMIT_MS := 120000
const TICK_LIMIT := 60000
const TICKS_PER_FRAME := 200
const GLASS := "res://assets/materials/tp_glass.tres"

var _out_dir := ""
var _failed := false
var _stage := "init"
var _heartbeat_ms := 0
var _guard_mutex := Mutex.new()
var _guard_stop := false
var _guard: Thread
var _plates: Array[Image] = []
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
	print("PROBE out_dir=", _out_dir)
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


## Guard thread: a frozen main thread never reaches _process, so check from here.
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
			OS.crash("landside views probe hung")


func _run() -> void:
	await _boot()
	if await _jam():
		await _plate_curb()
		await _plate_select()
		await _plate_distance()
		await _plate_lot()
		await _plate_strip()
	_sheet()
	_guard_mutex.lock()
	_guard_stop = true
	_guard_mutex.unlock()
	_guard.wait_to_finish()
	print("PROBE done failed=%s" % _failed)
	quit(1 if _failed else 0)


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


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


# ------------------------------------------------------------ the world


func _boot() -> void:
	_beat("boot")
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_clock = _main.get_node("SimClock")
	var sim_seed := randi()
	_clock.seed_rng(sim_seed)
	print("PROBE sim_seed=", sim_seed)
	root.add_child(_main)
	_clock.set_process(false)
	_landside = _main.get_node("LandsideSim")
	_views = _main.get_node("LandsideViews")
	_hud = _main.get_node("PassengerHud")
	_rig = _main.get_node(CAMERA_RIG)
	_cam = _main.get_node(CAMERA_RIG + "/Camera3D")
	var mode: BuildMode = _main.get_node("BuildMode")
	(mode.get_node("Ghost") as Node3D).visible = false
	_hud.press_starter_terminal()
	var staff: StaffSim = _main.get_node("Staff")
	staff.hire(StaffMember.Role.CHECKIN)
	staff.hire(StaffMember.Role.SECURITY)
	if not _landside.build_lot(0):
		_invalid("lot spot 0 could not be built")
	await _frames(10)


func _tick() -> void:
	_clock.set_paused(false)
	_clock.advance(SimClock.STEP)
	_clock.set_paused(true)


func _count(lane: LandsideVehicle.Lane, stage: int) -> int:
	var n := 0
	for id in _landside.vehicle_ids():
		var v := _landside.get_vehicle(id)
		if v.lane == lane and (stage < 0 or v.stage == stage) and _views.has_vehicle(id):
			n += 1
	return n


## Steps until a car stands in a berth and two cars queue on road_in on the map.
func _jam() -> bool:
	_stage = "jam"
	var closed := false
	while _clock.tick < TICK_LIMIT:
		for i in TICKS_PER_FRAME:
			_tick()
		_beat("jam %d" % _clock.tick)
		if not closed and _count(LandsideVehicle.Lane.ROAD_IN, -1) > 0:
			closed = true
			if not _remove_entrance():
				return false
		var berthed := _count(LandsideVehicle.Lane.BERTH, -1)
		var queued := _count(LandsideVehicle.Lane.ROAD_IN, LandsideVehicle.Stage.QUEUE)
		var parked := _count(LandsideVehicle.Lane.SLOT, -1)
		if berthed > 0 and queued >= 2 and parked > 0:
			print(
				(
					"JAM tick=%d berthed=%d queued=%d parked=%d drawn=%d"
					% [_clock.tick, berthed, queued, parked, _views.vehicle_count()]
				)
			)
			_views.draw()
			return true
		await process_frame
	_invalid(
		(
			"no jam by tick %d (berths %d, queued %d, parked %d)"
			% [
				_clock.tick,
				_count(LandsideVehicle.Lane.BERTH, -1),
				_count(LandsideVehicle.Lane.ROAD_IN, LandsideVehicle.Stage.QUEUE),
				_count(LandsideVehicle.Lane.SLOT, -1)
			]
		)
	)
	return false


# ------------------------------------------------------------ checks


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
	for i in mi.mesh.get_surface_count():
		var mat := mi.get_active_material(i)
		if mat != null and mat.resource_path == GLASS:
			continue
		var arrays := mi.mesh.surface_get_arrays(i)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if index.is_empty():
			faces.append_array(verts)
		else:
			for k in index:
				faces.append(verts[k])
	return faces


## A static body per visible mesh with a trimesh of its opaque surfaces; old ones go.
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


## Whether a dissolve material has fully dropped this mesh (dissolve >= 0.99).
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
	print(
		(
			"INFRAME %s screen=(%.0f,%.0f)-(%.0f,%.0f) size_px=(%.0f, %.0f) ok=%s"
			% [label, lo.x, lo.y, hi.x, hi.y, hi.x - lo.x, hi.y - lo.y, ok]
		)
	)
	if not ok:
		_invalid("%s: projected bounds leave the viewport" % label)
	return ok


## Rays from the camera to the subject's camera-facing opaque triangles: at least half
## must hit the subject first.
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
	var blockers := {}
	for t in targets:
		var from := _cam.global_position
		var q := PhysicsRayQueryParameters3D.create(from, t + (t - from).normalized() * 0.05)
		var hit := space.intersect_ray(q)
		if hit and subject.is_ancestor_of(hit.collider):
			hits += 1
		elif hit:
			var by: Node = hit.collider.get_parent()
			blockers[by.name] = int(blockers.get(by.name, 0)) + 1
	var ok := hits > 0 and hits * 2 >= targets.size()
	print(
		(
			"VISIBLE %s ray_hits=%d/%d ok=%s blocked_by=%s"
			% [label, hits, targets.size(), ok, blockers]
		)
	)
	if not ok:
		_invalid("%s: occluded or not hit (%d of %d rays)" % [label, hits, targets.size()])
	return ok


## Every drawn vehicle's nose against its lane, and against the way it is drawn moving.
func _check_noses(label: String) -> void:
	var checked := 0
	var moving := 0
	for id in _landside.vehicle_ids():
		if not _views.has_vehicle(id):
			continue
		var v := _landside.get_vehicle(id)
		var nose := _views.node_for(id).global_basis.z
		var want := Vector3.ZERO
		match v.lane:
			LandsideVehicle.Lane.ROAD_IN, LandsideVehicle.Lane.ROAD_OUT, LandsideVehicle.Lane.BERTH:
				want = Vector3(-1, 0, 0)
			LandsideVehicle.Lane.ACCESS, LandsideVehicle.Lane.SLOT:
				want = Vector3(0, 0, 1)
		var move := _views.pose_at(id, 0.55).origin - _views.pose_at(id, 0.45).origin
		var move_dot := nose.dot(move.normalized()) if move.length() > 0.01 else NAN
		print(
			(
				"NOSE %s vehicle=%d lane=%d stage=%d at=%s nose=(%.3f, %.3f, %.3f) want=%s move_dot=%s"
				% [
					label,
					id,
					v.lane,
					v.stage,
					_views.node_for(id).global_position,
					nose.x,
					nose.y,
					nose.z,
					want,
					move_dot
				]
			)
		)
		if want != Vector3.ZERO:
			checked += 1
			if nose.dot(want) < 0.99:
				_invalid("%s: vehicle %d faces %s, its lane runs %s" % [label, id, nose, want])
		if move.length() > 0.01:
			moving += 1
			if move_dot < 0.99:
				_invalid("%s: vehicle %d moves %s but faces %s" % [label, id, move, nose])
	print("NOSES %s checked=%d moving=%d" % [label, checked, moving])
	if checked == 0:
		_invalid("%s: no vehicle checked" % label)


## Removes the terminal's entrance door, so nobody gets out of a car any more.
func _remove_entrance() -> bool:
	var mode: BuildMode = _main.get_node("BuildMode")
	for id in mode.grid.object_ids():
		if mode.grid.get_object(id)["def"] == &"entrance_door":
			# Staff stand at their stations already; without the reach check the grid
			# would refuse an edit that leaves their spots unreachable from a door.
			mode.grid.check_staff_reach = false
			var result := mode.grid.apply(BuildEdit.remove_object(id))
			mode.grid.check_staff_reach = true
			if not result.ok:
				_invalid("the entrance door could not be removed: %s" % result.reason_text())
				return false
			(mode.get_node("BuildView") as BuildView).refresh(mode.grid)
			print("ENTRANCE removed at tick %d" % _clock.tick)
			return true
	_invalid("no entrance door to remove")
	return false


## Moves the camera, waits for the roof cutaway, and rebuilds colliders for it.
func _aim(label: String, focus: Vector3, distance: float, yaw: float) -> void:
	_beat(label)
	_rig.stop_follow()
	_rig.position = focus
	_rig.yaw = yaw
	_rig.distance = distance
	_rig.zoom(1.0)
	await create_timer(1.5).timeout
	await _frames(4)
	_views.draw()
	await _rebuild_colliders()
	print(
		(
			"CAMERA %s pos=%s focus=%s distance=%.1f yaw=%.2f"
			% [label, _cam.global_position, focus, distance, yaw]
		)
	)


func _keep(img: Image, file: String) -> void:
	_save(img, file)
	_plates.append(img)


# ------------------------------------------------------------ plates


## The berthed car nearest the stop and the two queued cars nearest the stop.
func _curb_subjects() -> Dictionary:
	var out := {}
	var queued: Array[LandsideVehicle] = []
	for id in _landside.vehicle_ids():
		var v := _landside.get_vehicle(id)
		if not _views.has_vehicle(id):
			continue
		if v.lane == LandsideVehicle.Lane.BERTH and not out.has("berth"):
			out["berth"] = id
		elif v.lane == LandsideVehicle.Lane.ROAD_IN and v.stage == LandsideVehicle.Stage.QUEUE:
			queued.append(v)
	queued.sort_custom(
		func(a: LandsideVehicle, b: LandsideVehicle) -> bool: return a.pos_mm > b.pos_mm
	)
	for i in mini(2, queued.size()):
		out["queue_%d" % (i + 1)] = queued[i].id
	return out


func _plate_curb() -> void:
	var subjects := _curb_subjects()
	print("CURB subjects %s" % [subjects])
	await _aim("curb", Vector3(-6.0, 0.0, -56.0), 48.0, -0.35)
	var ok := subjects.size() == 3
	for key in subjects:
		var node := _views.node_for(subjects[key])
		ok = _prove_in_frame("curb/%s vehicle %d" % [key, subjects[key]], _aabb_of(node)) and ok
		ok = _prove_visible("curb/%s vehicle %d" % [key, subjects[key]], node) and ok
	_check_noses("curb")
	var img := await _grab()
	_keep(img, "landside_views_curb.png" if ok else "landside_views_curb_INVALID.png")


func _plate_select() -> void:
	var subjects := _curb_subjects()
	var id: int = subjects.get("queue_1", 0)
	if id == 0:
		_invalid("select: no queued car")
		return
	await _aim("select", Vector3(-6.0, 0.0, -56.0), 48.0, -0.35)
	var at := _cam.unproject_position(_views.node_for(id).global_position + Vector3(0.0, 1.0, 0.0))
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = at
	_hud._unhandled_input(click)
	await _frames(30)
	var text := _hud.follow_text()
	print(
		(
			'SELECT clicked=%s vehicle=%d selected=%d following=%s text="%s"'
			% [at, id, _views.selected_id, _rig.is_following(), text]
		)
	)
	var ok := _views.selected_id == id and _rig.is_following() and text.contains("Flight")
	if not ok:
		_invalid("select: the click did not select vehicle %d with its text" % id)
	# The camera glided to the car: let the roof cutaway settle, then rebuild colliders.
	await create_timer(1.5).timeout
	_views.draw()
	await _rebuild_colliders()
	ok = _prove_in_frame("select/vehicle %d" % id, _aabb_of(_views.node_for(id))) and ok
	ok = _prove_visible("select/vehicle %d" % id, _views.node_for(id)) and ok
	var img := await _grab()
	_keep(img, "landside_views_select.png" if ok else "landside_views_select_INVALID.png")
	_rig.stop_follow()
	_views.selected_id = 0


func _plate_distance() -> void:
	await _aim("distance", Vector3(0.0, 0.0, -40.0), 200.0, 0.0)
	var subjects := _curb_subjects()
	var ok := not subjects.is_empty()
	for key in subjects:
		ok = _prove_in_frame("distance/%s" % key, _aabb_of(_views.node_for(subjects[key]))) and ok
		ok = _prove_visible("distance/%s" % key, _views.node_for(subjects[key])) and ok
	ok = _prove_in_frame("distance/lot", _aabb_of(_views.places().lot_node(0))) and ok
	ok = _prove_visible("distance/lot", _views.places().lot_node(0)) and ok
	_check_noses("distance")
	var img := await _grab()
	_keep(img, "landside_views_distance.png" if ok else "landside_views_distance_INVALID.png")


func _post(at: Vector3, color: Color) -> MeshInstance3D:
	var post := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.25
	mesh.bottom_radius = 0.25
	mesh.height = 3.0
	post.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	post.material_override = mat
	post.position = at + Vector3(0.0, 1.5, 0.0)
	return post


func _plate_lot() -> void:
	var markers := Node3D.new()
	markers.name = "ProbeMarkers"
	_main.add_child(markers)
	var spot: LandsideLotSpot = _landside.definition.lots[0]
	for slot in spot.slots:
		markers.add_child(_post(slot, Color.WHITE))
	markers.add_child(_post(spot.access[spot.access.size() - 1], Color(0.1, 0.8, 0.2)))
	markers.add_child(_post(spot.exit[0], Color(0.9, 0.1, 0.1)))
	await _aim("lot", Vector3(4.0, 0.0, -28.0), 60.0, 0.0)
	var lot := _views.places().lot_node(0)
	var ok := _prove_in_frame("lot/lot", _aabb_of(lot))
	ok = _prove_in_frame("lot/markers", _aabb_of(markers)) and ok
	var parked := 0
	for id in _landside.vehicle_ids():
		if _landside.get_vehicle(id).lane == LandsideVehicle.Lane.SLOT and _views.has_vehicle(id):
			parked += 1
			ok = _prove_in_frame("lot/parked %d" % id, _aabb_of(_views.node_for(id))) and ok
			ok = _prove_visible("lot/parked %d" % id, _views.node_for(id)) and ok
	print(
		(
			"LOT DIAGNOSTIC parked=%d lot_at=%s slots=%s gate=%s exit_start=%s"
			% [
				parked,
				lot.global_position,
				spot.slots,
				spot.access[spot.access.size() - 1],
				spot.exit[0]
			]
		)
	)
	_check_noses("lot")
	var img := await _grab()
	_keep(img, "landside_views_lot_DIAGNOSTIC.png" if ok else "landside_views_lot_INVALID.png")
	markers.free()


## A car driving on road_in, drawn over 6 frames a third of a tick apart.
func _plate_strip() -> void:
	_beat("strip")
	var id := 0
	var guard := 0
	while id == 0 and guard < 4000:
		_tick()
		guard += 1
		for vid in _landside.vehicle_ids():
			var v := _landside.get_vehicle(vid)
			if (
				v.lane == LandsideVehicle.Lane.ROAD_IN
				and v.stage == LandsideVehicle.Stage.DRIVE
				and v.pos_mm > 40000
				and _views.has_vehicle(vid)
			):
				id = vid
				break
	if id == 0:
		_invalid("strip: no car driving on road_in")
		return
	_views.draw()
	var start := _views.node_for(id).global_position
	await _aim("strip", start + Vector3(-2.0, 0.0, 0.0), 26.0, 0.0)
	var strip := Image.create(1920, 360, false, Image.FORMAT_RGBA8)
	var last_x := INF
	var advanced := 0
	for i in 6:
		if i > 0:
			_clock.set_paused(false)
			_clock.advance(SimClock.STEP / 3.0)
			_clock.set_paused(true)
		_views.draw()
		var node := _views.node_for(id)
		if node == null:
			_invalid("strip: vehicle %d left the view" % id)
			return
		var x := node.global_position.x
		print(
			(
				"STRIP frame=%d tick=%d alpha=%.2f vehicle=%d x=%.3f nose=%s"
				% [i, _clock.tick, _clock.alpha, id, x, node.global_basis.z]
			)
		)
		if x < last_x:
			advanced += 1 if i > 0 else 0
		last_x = x
		if not _prove_in_frame("strip/frame %d" % i, _aabb_of(node)):
			return
		if i == 0 and not _prove_visible("strip/frame 0", node):
			return
		var img := await _grab()
		var tile := img.duplicate() as Image
		tile.resize(320, 180, Image.INTERPOLATE_LANCZOS)
		var cut := Rect2i(Vector2i(0, 0), Vector2i(320, 180))
		strip.blit_rect(tile, cut, Vector2i(i * 320, 0))
		var zoomed := img.get_region(Rect2i(Vector2i(560, 240), Vector2i(800, 600)))
		zoomed.resize(320, 180, Image.INTERPOLATE_LANCZOS)
		strip.blit_rect(zoomed, cut, Vector2i(i * 320, 180))
	print("STRIP advanced_frames=%d of 5" % advanced)
	if advanced < 5:
		_invalid("strip: the car did not move -x every frame")
	_check_noses("strip")
	_save(strip, "landside_views_strip.png")


func _sheet() -> void:
	if _plates.is_empty():
		return
	var sheet := Image.create(1920, 1080, false, Image.FORMAT_RGBA8)
	for i in mini(_plates.size(), 4):
		var copy := _plates[i].duplicate() as Image
		copy.resize(960, 540, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(
			copy,
			Rect2i(Vector2i.ZERO, Vector2i(960, 540)),
			Vector2i((i % 2) * 960, floori(i / 2.0) * 540)
		)
	_save(sheet, "landside_views_contact_sheet.png")
