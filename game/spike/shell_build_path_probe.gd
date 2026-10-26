extends SceneTree
## Windowed end-to-end proof of Shell 4/4 on one path, in the real main scene:
## the build grid inside the Toon terminal shell, a terminal built with the
## real BuildMode tools (a floor rectangle, a desk, a scanner, the Entrance
## tool snapped to landside door B and the Exit tool snapped to gate C), and
## one passenger walking road -> landside door B -> check-in -> security ->
## gate C's door -> the apron -> the plane door, until it makes the flight.
##
## Plates (near and far zoom, headings 0 and 180): the passenger on the road,
## at check-in, at security, at the gate C doorway and on the apron, the
## building far out with the roof drawn, and two frame strips: crossing the
## landside doorway and crossing gate C's doorway. Every plate projects the
## passenger (feet and head) inside the frame with a margin, and casts rays
## from the camera to its hips and chest against bodies baked from every drawn
## shell mesh at its current transform (glass left out): no ray may hit
## anything before the passenger. The control: far out, with the roof drawn,
## the rays to the passenger at the check-in desk must hit the roof. On a
## failure the probe prints PROBE_INVALID and exits 1; a guard thread calls
## OS.crash() on a stall. Plates go to tools/blender/out/shell-build-area/.
##
## Run (one windowed Godot run project-wide; take the slot lock first):
##   timeout 900 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/shell_build_path_probe.gd

const OUT_REL := "res://../tools/blender/out/shell-build-area"
const MARGIN_PX := 24.0
const HANG_MS := 60000
const SETTLE_MAX_FRAMES := 200
const TICKS_PER_FRAME := 20
const MAX_TICKS := 1900
const NEAR_M := 16.0
const FAR_M := 170.0
const TILE := Vector2i(480, 270)
const GLASS := "res://assets/materials/tp_glass.tres"
const ROOF_NAMES := ["Upper", "Canopy", "Lights_Upper", "Poles"]
const LANDSIDE_B := Vector2i(16, 29)
const GATE_C := Vector2i(16, 0)
const FLOOR_MIN := Vector2i(12, 0)
const FLOOR_MAX := Vector2i(20, 29)
const DESK := Vector2i(13, 20)
const SCANNER := Vector2i(16, 10)
const PLANE_DOOR := Vector2(-14.5, -106.5)

var _out_dir := ""
var _failed := false
var _guard := Thread.new()
var _lock := Mutex.new()
var _beat_ms := 0
var _stage := "boot"
var _stop := false
var _main: Node3D
var _cam: Camera3D
var _rig: TycoonCamera
var _view: ShellView
var _shell: Node3D
var _clock: SimClock
var _sim: PassengerSim
var _views: PassengerViews
var _mode: BuildMode
var _occluders: Node3D
var _plates: Array[Image] = []
var _id := 0
var _stages := {}
var _min_door_m := INF
var _min_gate_m := INF


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_beat("boot")
	_guard.start(_watch)
	_run.call_deferred()


func _run() -> void:
	randomize()
	var world_seed := randi()
	print("PROBE seed=%d" % world_seed)
	_main = (load("res://main/main.tscn") as PackedScene).instantiate()
	(_main.get_node("PassengerSim") as PassengerSim).auto_schedule = false
	root.add_child(_main)
	_clock = _main.get_node("SimClock") as SimClock
	_clock.seed_rng(world_seed)
	_clock.set_paused(true)
	(_main.get_node("PassengerHud") as CanvasLayer).visible = false
	(_main.get_node("BuildMenu") as CanvasLayer).visible = false
	_rig = _main.get_node("TycoonCamera") as TycoonCamera
	_cam = _rig.get_node("Camera3D") as Camera3D
	_cam.make_current()
	_view = _main.get_node("ShellView") as ShellView
	_shell = _main.get_node("Airside/Terminal") as Node3D
	_sim = _main.get_node("PassengerSim") as PassengerSim
	_views = _main.get_node("PassengerViews") as PassengerViews
	_mode = _main.get_node("BuildMode") as BuildMode
	await _frames(3)
	print("PROBE viewport=%s" % root.get_visible_rect().size)
	if not _check_frame() or not _build():
		_end()
		return
	_id = _sim.spawn_now(_main.get_node("FlightSim").flight_ids()[0])
	_views.selected_id = _id
	var p := _sim.get_passenger(_id)
	print("SPAWN id=%d stage=%d at=%s first=%s" % [_id, p.stage, p.at, _sim.world_position(p)])
	await _journey()
	_finish_checks()
	if not _plates.is_empty():
		_sheet(_plates, "contact_sheet.png", 4)
	_end()


## The grid frame is the shell's and the camera's Home is on its centre.
func _check_frame() -> bool:
	var shell := _mode.shell
	var ok := (
		shell != null
		and _mode.grid.size == shell.grid_size
		and _mode.grid.origin.is_equal_approx(shell.grid_origin)
	)
	var home := Vector2(_rig.home_position.x, _rig.home_position.z)
	ok = ok and home.is_equal_approx(Vector2(shell.centre().x, shell.centre().z))
	print(
		(
			"FRAME grid size=%s origin=%s home=%s shell_centre=%s ok=%s"
			% [_mode.grid.size, _mode.grid.origin, _rig.home_position, shell.centre(), ok]
		)
	)
	if not ok:
		_invalid("BuildMode is not on the shell frame")
	return ok


## Builds the one-path terminal with the BuildMode tools, as a player would.
func _build() -> bool:
	var grid := _mode.grid
	_mode.set_tool(BuildMode.Tool.FLOOR)
	_mode.begin_area(grid.cell_to_world(FLOOR_MIN))
	_mode.move_area(grid.cell_to_world(FLOOR_MAX))
	var outcome := _mode.finish_area()
	var floors := 0
	for y in grid.size.y:
		for x in grid.size.x:
			floors += int(grid.floor_at(Vector2i(x, y)) != BuildGrid.FLOOR_NONE)
	print("BUILD floor placed=%d floor_cells=%d" % [outcome.placed if outcome else -1, floors])
	var results := {
		"desk": _tool(BuildMode.Tool.DESK, grid.cell_to_world(DESK)),
		"scanner": _tool(BuildMode.Tool.SCANNER, grid.cell_to_world(SCANNER)),
		"entrance_at_gate": _tool(BuildMode.Tool.ENTRANCE, grid.cell_to_world(GATE_C)),
		"entrance":
		_tool(BuildMode.Tool.ENTRANCE, grid.cell_to_world(LANDSIDE_B) + Vector3(1.2, 0.0, -2.0)),
		"exit": _tool(BuildMode.Tool.EXIT, grid.cell_to_world(GATE_C) + Vector3(-0.8, 0.0, 1.5)),
	}
	var ok := floors == (FLOOR_MAX.x - FLOOR_MIN.x + 1) * (FLOOR_MAX.y - FLOOR_MIN.y + 1)
	ok = ok and results["desk"].ok and results["scanner"].ok
	ok = ok and results["entrance_at_gate"].reason == BuildResult.Reason.DOOR_NOT_AT_SHELL_DOOR
	for door in [["entrance", LANDSIDE_B, 2], ["exit", GATE_C, 0]]:
		var result: BuildResult = results[door[0]]
		var record := grid.get_object(result.object_id) if result.ok else {}
		var placed: bool = result.ok and record["anchor"] == door[1] and record["facing"] == door[2]
		print("BUILD %s placed=%s record=%s" % [door[0], placed, record])
		ok = ok and placed
	_mode.set_tool(BuildMode.Tool.NONE)
	if not ok:
		_invalid("the one-path terminal was not built as planned")
	return ok


func _tool(tool: BuildMode.Tool, point: Vector3) -> BuildResult:
	_mode.set_tool(tool)
	var result := _mode.apply_at(point)
	print(
		(
			"BUILD tool=%d at=%s ok=%s reason=%d status='%s'"
			% [tool, point, result.ok, result.reason, _mode.status_text()]
		)
	)
	return result


## Steps the sim tick by tick and takes the plates at their moments.
func _journey() -> void:
	var p := _sim.get_passenger(_id)
	var road_mm := p.apron_total_mm()
	await _until(func() -> bool: return p.apron_mm >= road_mm * 0.35, "road")
	await _plate("road_near_h0", 0.0, NEAR_M)
	await _plate("road_far_h0", 0.0, FAR_M)
	await _until(func() -> bool: return _xz_of(p).y < -61.5, "porch")
	await _strip(
		"strip_landside_door_h0",
		0.0,
		_sim.grid.cell_to_world(LANDSIDE_B) + Vector3(0.0, 0.0, 1.2),
		func() -> bool: return _xz_of(p).y < -65.0,
		8
	)
	await _until(func() -> bool: return p.stage == Passenger.Stage.CHECKIN, "checkin")
	await _plate("checkin_near_h180", 180.0, NEAR_M)
	await _control_roof_hides_checkin()
	await _until(func() -> bool: return p.stage == Passenger.Stage.SECURITY, "security")
	await _plate("security_near_h0", 0.0, NEAR_M)
	await _until(func() -> bool: return p.stage == Passenger.Stage.TO_EXIT, "to_exit")
	await _until(func() -> bool: return _xz_of(p).y < -93.0, "near_gate")
	await _strip(
		"strip_gate_c_door_h180",
		180.0,
		_sim.grid.cell_to_world(GATE_C) + Vector3(0.0, 0.0, -1.5),
		func() -> bool: return _xz_of(p).y < -97.0,
		8
	)
	await _until(func() -> bool: return _xz_of(p).y < -100.5, "apron")
	await _plate("apron_near_h90", 90.0, NEAR_M)
	await _plate("apron_far_h180", 180.0, FAR_M)
	await _until(func() -> bool: return p.is_done(), "boarding")


## Advances one tick at a time until `done` holds, at most MAX_TICKS in all.
func _until(done: Callable, stage: String) -> void:
	_beat(stage)
	var steps := 0
	while not done.call() and _clock.tick < MAX_TICKS:
		_tick()
		steps += 1
		if steps % TICKS_PER_FRAME == 0:
			await process_frame
			_beat(stage)
	await _frames(2)
	print("UNTIL %s tick=%d done=%s" % [stage, _clock.tick, done.call()])
	if not done.call():
		_invalid("%s never happened by tick %d" % [stage, _clock.tick])


func _tick() -> void:
	_clock.set_paused(false)
	_clock.advance(SimClock.STEP)
	_clock.set_paused(true)
	var p := _sim.get_passenger(_id)
	_stages[p.stage] = true
	var at := _xz_of(p)
	_min_door_m = minf(_min_door_m, at.distance_to(Vector2(-16.99, -64.35)))
	_min_gate_m = minf(_min_gate_m, at.distance_to(Vector2(-16.99, -95.25)))


func _xz_of(p: Passenger) -> Vector2:
	var at := _sim.world_position(p)
	return Vector2(at.x, at.z)


## The camera on the passenger at `yaw_deg` and `distance`; one proven plate.
func _plate(label: String, yaw_deg: float, distance: float) -> void:
	_beat(label)
	await _place(_subject(), yaw_deg, distance)
	_log_state(label)
	var ok := _in_frame(label, _subject_points()) and _clear_view(label)
	var img := await _grab_now()
	if ok:
		_keep(img, label + ".png")


## A strip: the camera fixed on `focus`, a frame every few ticks until
## `done`, at most `count` frames, each framed and proven like a plate.
func _strip(label: String, yaw_deg: float, focus: Vector3, done: Callable, count: int) -> void:
	_beat(label)
	await _place(focus, yaw_deg, NEAR_M * 0.8)
	var tiles: Array[Image] = []
	for i in count:
		for k in 6:
			_tick()
		await _frames(2)
		await _rebuild_occluders()
		var frame := "%s_%d" % [label, i]
		_log_state(frame)
		var ok := _in_frame(frame, _subject_points()) and _clear_view(frame)
		var img := await _grab_now()
		if ok:
			tiles.append(_tile(img))
		if done.call():
			break
	if tiles.size() < 3:
		_invalid("%s: only %d proven frames" % [label, tiles.size()])
		return
	_sheet(tiles, label + ".png", tiles.size())


## The control: far out the roof is drawn, so it must hide the passenger at
## the desk; otherwise the visibility rays prove nothing.
func _control_roof_hides_checkin() -> void:
	_beat("control")
	await _place(_subject(), 180.0, FAR_M)
	var hits := _ray_hits(_ray_points())
	var roof_hits := 0
	for piece in hits:
		roof_hits += int(piece in ROOF_NAMES)
	var ok := roof_hits == _ray_points().size()
	var level := _view.cutaway.roof_level
	print("CONTROL roof_level=%s ray_hits=%s roof_hits=%d ok=%s" % [level, hits, roof_hits, ok])
	if not ok:
		_invalid("control: the drawn roof did not block the rays to the passenger inside")


func _subject() -> Vector3:
	return _views.node_for(_id).global_position


## Feet and head of the passenger as drawn.
func _subject_points() -> Array:
	var at := _subject()
	return [at + Vector3(0.0, 0.05, 0.0), at + Vector3(0.0, 1.75, 0.0)]


func _ray_points() -> Array:
	var at := _subject()
	return [at + Vector3(0.0, 0.9, 0.0), at + Vector3(0.0, 1.5, 0.0)]


## Rays from the camera to the passenger's hips and chest; none may hit.
func _clear_view(label: String) -> bool:
	var hits := _ray_hits(_ray_points())
	var ok := hits.is_empty()
	print("VISIBLE %s rays=%d blocked_by=%s ok=%s" % [label, _ray_points().size(), hits, ok])
	if not ok:
		_invalid("%s: the passenger is hidden behind %s" % [label, hits])
	return ok


## The pieces the rays to `points` hit before reaching them.
func _ray_hits(points: Array) -> Array:
	var space := _cam.get_world_3d().direct_space_state
	var out := []
	for point in points:
		var q := PhysicsRayQueryParameters3D.create(_cam.global_position, point)
		var hit := space.intersect_ray(q)
		if hit:
			out.append(String((hit.collider as Node).get_meta("piece", "?")))
	return out


func _place(focus: Vector3, yaw_deg: float, distance: float) -> void:
	_rig.stop_follow()
	_rig.position = Vector3(focus.x, 0.0, focus.z)
	_rig.yaw = deg_to_rad(yaw_deg)
	_rig.distance = distance
	_rig.zoom(1.0)
	for i in SETTLE_MAX_FRAMES:
		await process_frame
		_beat(_stage)
		if _settled() and i > 4:
			break
	await RenderingServer.frame_post_draw
	if not _settled():
		_invalid("cutaway did not settle at yaw %.0f distance %.0f" % [yaw_deg, distance])
	await _rebuild_occluders()


func _settled() -> bool:
	var c := _view.cutaway
	if c.roof_level != c.roof_target:
		return false
	for side in 4:
		if c.side_levels[side] != c.side_target(side):
			return false
	return true


## One static body per drawn shell mesh from its faces at their current world
## positions (squashed pieces block as squashed), glass left out; hidden
## meshes (the gone roof, opened doors) get none.
func _rebuild_occluders() -> void:
	if _occluders != null:
		_occluders.free()
	_occluders = Node3D.new()
	_occluders.name = "ProbeOccluders"
	root.add_child(_occluders)
	for node in _shell.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if not mi.is_visible_in_tree():
			continue
		var faces := PackedVector3Array()
		var holes := _open_holes()
		for i in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(i)
			if mat != null and mat.resource_path == GLASS:
				continue
			var arrays := mi.mesh.surface_get_arrays(i)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if index.is_empty():
				for v in verts:
					faces.append(mi.global_transform * v)
			else:
				for k in index:
					faces.append(mi.global_transform * verts[k])
		faces = _outside_holes(faces, holes)
		if faces.is_empty():
			continue
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		shape.backface_collision = true
		var shape_node := CollisionShape3D.new()
		shape_node.shape = shape
		var body := StaticBody3D.new()
		body.set_meta("piece", _piece_name(mi))
		body.add_child(shape_node)
		_occluders.add_child(body)
	await physics_frame
	await physics_frame


## The hole boxes of the open doorways: the shaders discard the door bay's
## lintel and the porch letter sign inside them (ShellView.Doorway).
func _open_holes() -> Array[AABB]:
	var boxes: Array[AABB] = []
	for doorway in _view.doorways:
		if is_instance_valid(doorway.door) and not doorway.door.visible:
			boxes.append(doorway.hole)
			boxes.append(doorway.sign_hole)
	return boxes


## The triangles of `faces` whose centre is in none of `holes`.
func _outside_holes(faces: PackedVector3Array, holes: Array[AABB]) -> PackedVector3Array:
	if holes.is_empty():
		return faces
	var kept := PackedVector3Array()
	for t in range(0, faces.size(), 3):
		var centre := (faces[t] + faces[t + 1] + faces[t + 2]) / 3.0
		if not holes.any(func(box: AABB) -> bool: return box.has_point(centre)):
			kept.append_array([faces[t], faces[t + 1], faces[t + 2]])
	return kept


## The mesh's own name (Upper, Facade_N_03, ...), or its doorway jamb's.
func _piece_name(mi: MeshInstance3D) -> String:
	var node: Node = mi
	while node != null and node != _shell:
		if String(node.name).begins_with("Jamb_"):
			return String(node.name)
		node = node.get_parent()
	return String(mi.name)


func _in_frame(label: String, points: Array) -> bool:
	var size := root.get_visible_rect().size
	var rect := Rect2(Vector2(MARGIN_PX, MARGIN_PX), size - Vector2(MARGIN_PX, MARGIN_PX) * 2.0)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var behind := false
	for point in points:
		behind = behind or _cam.is_position_behind(point)
		var s := _cam.unproject_position(point)
		lo = lo.min(s)
		hi = hi.max(s)
	var ok := not behind and rect.has_point(lo) and rect.has_point(hi)
	print(
		(
			"INFRAME %s screen=(%.0f,%.0f)-(%.0f,%.0f) height_px=%.0f ok=%s"
			% [label, lo.x, lo.y, hi.x, hi.y, hi.y - lo.y, ok]
		)
	)
	if not ok:
		_invalid("%s: the passenger leaves the frame" % label)
	return ok


func _log_state(label: String) -> void:
	var p := _sim.get_passenger(_id)
	print(
		(
			"STATE %s tick=%d stage=%d at=%s world=%s drawn=%s cam=%s roof=%.2f"
			% [
				label,
				_clock.tick,
				p.stage,
				p.at,
				_sim.world_position(p),
				_subject(),
				_cam.global_position,
				_view.cutaway.roof_level
			]
		)
	)


## The passenger made the flight along the one path.
func _finish_checks() -> void:
	var p := _sim.get_passenger(_id)
	var end := _sim.world_position(p)
	var wanted := [
		Passenger.Stage.SPAWNED,
		Passenger.Stage.CHECKIN,
		Passenger.Stage.SECURITY,
		Passenger.Stage.TO_EXIT,
		Passenger.Stage.APRON,
		Passenger.Stage.MADE,
	]
	var seen := wanted.filter(func(s: int) -> bool: return _stages.has(s))
	var ok := (
		p.stage == Passenger.Stage.MADE
		and _sim.made_count() == 1
		and seen.size() == wanted.size()
		and _min_door_m < 0.1
		and _min_gate_m < 0.1
		and Vector2(end.x, end.z).distance_to(PLANE_DOOR) < 0.01
	)
	print(
		(
			(
				"RESULT stage=%d made=%d outcome_tick=%d stages=%s min_landside_door_m=%.3f"
				+ " min_gate_c_door_m=%.3f end=%s odometer_mm=%d ok=%s"
			)
			% [
				p.stage,
				_sim.made_count(),
				p.outcome_tick,
				seen,
				_min_door_m,
				_min_gate_m,
				end,
				p.odometer_mm,
				ok
			]
		)
	)
	if not ok:
		_invalid("the passenger did not make the flight along the one path")


func _grab_now() -> Image:
	await _frames(2)
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	return img


func _tile(img: Image) -> Image:
	var tile := img.duplicate() as Image
	tile.resize(TILE.x, TILE.y, Image.INTERPOLATE_BILINEAR)
	return tile


func _keep(img: Image, file: String) -> void:
	_save(img, file)
	_plates.append(_tile(img))


func _sheet(tiles: Array[Image], file: String, per_row: int) -> void:
	var rows := ceili(float(tiles.size()) / per_row)
	var sheet := Image.create(
		per_row * (TILE.x + 6), rows * (TILE.y + 6), false, Image.FORMAT_RGBA8
	)
	sheet.fill(Color.WHITE)
	for i in tiles.size():
		var at := Vector2i((i % per_row) * (TILE.x + 6), (i / per_row) * (TILE.y + 6))
		sheet.blit_rect(tiles[i], Rect2i(Vector2i.ZERO, TILE), at)
	_save(sheet, file)


func _save(img: Image, file: String) -> void:
	var path := _out_dir.path_join(file)
	if img.save_png(path) != OK:
		_invalid("could not save %s" % path)
		return
	print("PLATE saved %s size=%s" % [path, img.get_size()])


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
		_beat(_stage)
	await RenderingServer.frame_post_draw


func _end() -> void:
	print("PROBE done failed=%s" % _failed)
	_lock.lock()
	_stop = true
	_lock.unlock()
	_guard.wait_to_finish()
	quit(1 if _failed else 0)


func _beat(stage: String) -> void:
	_lock.lock()
	_stage = stage
	_beat_ms = Time.get_ticks_msec()
	_lock.unlock()


func _watch() -> void:
	while true:
		OS.delay_msec(500)
		_lock.lock()
		var stop := _stop
		var stage := _stage
		var silent := Time.get_ticks_msec() - _beat_ms
		_lock.unlock()
		if stop:
			return
		if silent > HANG_MS:
			print("PROBE_INVALID hang: stage=%s silent_ms=%d" % [stage, silent])
			OS.crash("shell_build_path_probe: main thread stalled in %s" % stage)
