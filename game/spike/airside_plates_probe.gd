extends SceneTree
## Windowed plate probe for the one-flight airside slice.
##
## Run (one windowed Godot run project-wide; hold game/.godot/windowed.lock):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game -s res://spike/airside_plates_probe.gd
##
## Plates: a top-down overview of the runway, taxi route and stand with the plane at the
## stand, and a frame strip of landing, taxiing and takeoff at 3x. The sim is stepped by
## hand (the clock's own process is off) with a 60 fps frame delta, so every frame is
## ticks, not wall time. Each plate proves the plane is in frame and hit by rays first;
## otherwise PROBE_INVALID is printed and the probe exits 1. Plates go to
## tools/blender/out/airside_flight/, or to the directory --out=<dir> names.
##
## The taxi paving stage (board 9afe06b6 part 7) sets the flight's tick through
## every ground state (TAXI_IN, PUSHBACK, TAXI_OUT), ray-casts down at the plane's
## point each TAXI_SAMPLE_TICKS, and prints the plane's z range and whether the
## surface under it is paving (a hit on the taxi paving, a runway piece or the site's
## paving; PAVED_OWNERS). Two top-down plates of the stand-to-lane connector show the
## plane on the connector and at the site paving's edge (z -210); each proves the plane,
## the lane point and the paving edge are in frame. Then the plane mid-taxi on the lane,
## from above and from a distance, with every paving strip in frame.
##
## --two-gate boots with no starter shell, builds a terminal with gates A and B 44 cells
## apart and runs only _two_gate_paving(). Every run prints its world seed.

const StarterFlight := preload("res://spike/starter_flight.gd")
const OUT_REL := "res://../tools/blender/out/airside_flight"
const MAIN_SCENE := "res://main/main.tscn"
const MARGIN_PX := 8.0
const HANG_LIMIT_MS := 90000
const FRAME := 1.0 / 60.0
const FOLLOW_DISTANCE := 75.0
## The taxi paving stage: ticks between samples, the nodes whose colliders are paving
## (a ray hit on anything else, the Ground grass included, is not), the site
## paving's north edge, and the top-down plates' height of view and the z they
## are centred on.
const TAXI_SAMPLE_TICKS := 5
const PAVED_OWNERS: Array[String] = [
	"/root/Main/Airside/TaxiPaving", "/root/Main/Airside/Runway", "/root/Main/Airside/Terminal"
]
const PAVING_EDGE_Z := -210.0
const TOP_VIEW_SIZE := 130.0
const TOP_VIEW_Z := -200.0
## The lane plates: the top-down view's height of view and centre (between TaxiWest and
## TaxiEast, over the lane), and the distance camera's offset from what it looks at.
const LANE_VIEW_SIZE := 170.0
const LANE_VIEW_X := -51.0
const LANE_VIEW_Z := -250.0
const DISTANCE_OFFSET := Vector3(110.0, 130.0, 150.0)
## The two-gate stage: ticks per state of the made-up timeline its poses are read on,
## and the terminal, in cells from ReferenceTerminal.offset_on() (gates4_plates_probe.gd's
## layout without seats): gate A's exit at x 20 and gate B's at x 64, 44 cells apart.
const POSE_STATE_TICKS := 1000
const TWO_GATE_FLOOR_MIN := Vector2i(10, 2)
const TWO_GATE_FLOOR_MAX := Vector2i(65, 17)
const TWO_GATE_DIVIDER_Y := 9
const TWO_GATE_ENTRANCE := Vector2i(18, 17)
const TWO_GATE_EXITS: Array[Vector2i] = [Vector2i(20, 2), Vector2i(64, 2)]
const TWO_GATE_DESKS: Array[Vector2i] = [Vector2i(19, 5), Vector2i(63, 5)]
const TWO_GATE_SCANNER_XS: Array[int] = [17, 19]
## Sim ticks sampled for the strip, four per row, with the states each row must show:
## landing (approach to touchdown), taxiing (TAXI_IN) and takeoff (the TAKEOFF state,
## ticks 3100 to 3300 from the first state).
const STRIP_ROWS := [
	["landing", [150, 228, 280, 345], [FlightSim.State.APPROACH, FlightSim.State.LANDING]],
	["taxiing", [420, 500, 580, 655], [FlightSim.State.TAXI_IN]],
	["takeoff", [3110, 3170, 3230, 3290], [FlightSim.State.TAKEOFF]],
]

var _out_dir := ""
## --two-gate: the two-gate paving stage only (_two_gate_paving()).
var _two_gate := false
var _failed := false
var _stage := "init"
var _heartbeat_ms := 0
var _guard_mutex := Mutex.new()
var _guard_stop := false
var _guard: Thread
var _main: Node3D
var _clock: SimClock
var _plane: Node3D
var _cam: Camera3D
var _rig: Node3D
## The tick the starter's first flight starts its first state: a new game boots
## closed and issues it ISSUE_LEAD_TICKS after the opening, so every sampled
## tick below is counted from here.
var _t0 := 0


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_dir = arg.get_slice("=", 1)
		elif arg == "--two-gate":
			_two_gate = true
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
			OS.crash("airside plates probe hung")


func _run() -> void:
	_main = load(MAIN_SCENE).instantiate()
	_clock = _main.get_node("SimClock")
	var world_seed := randi()
	_clock.seed_rng(world_seed)
	print("PROBE world_seed=%d two_gate=%s" % [world_seed, _two_gate])
	_clock.set_process(false)
	if _two_gate:
		(_main.get_node("BuildMode") as BuildMode).starter_shell = false
	root.add_child(_main)
	# A node that defines _process gets processing turned on when it becomes ready, so
	# turn the clock's off again now: only this probe steps it. Left on, the clock runs
	# on during the frames of each sample and the plane flies on from the rig.
	_clock.set_process(false)
	_rig = _main.get_node("TycoonCamera")
	_cam = _main.get_node("TycoonCamera/Camera3D")
	_plane = _main.get_node("PlaneView")
	await _frames(10)
	if _two_gate:
		await _two_gate_paving()
		_finish()
		return
	# The plane's timeline is the subject, not staffing: open the airport directly
	# (AirportGate.open() opens it ready or not), which issues the starter flight.
	# The shell has no gate desk, and a closed gate keeps the airport closed.
	if not StarterFlight.add_gate_desk((_main.get_node("BuildMode") as BuildMode).grid):
		_invalid("the gate desk was refused")
	# The gate's stand is made on the frames after the desk is placed.
	await _frames(4)
	var gate := _main.get_node("AirportGate") as AirportGate
	if not gate.open():
		_invalid("the airport did not open")
		_finish()
		return
	# The opening accepts the starter contract; its first occurrence is issued on
	# the next tick, which is stepped by hand.
	var starter := FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, 0)
	StarterFlight.advance_until(
		_clock, func() -> bool: return _sim().flight_ids().has(starter), 200
	)
	_t0 = _sim().state_start("GMF101-d0", 0)
	print("PROBE opened tick=%d first_state_tick=%d" % [_clock.tick, _t0])
	if _t0 <= 0:
		_invalid("the starter's first flight GMF101-d0 was not issued")
		_finish()
		return
	_add_colliders(_main)
	await physics_frame
	print("PROBE speed_set=", _clock.set_speed(3), " speed=", _clock.speed)
	await _strip()
	await _taxi_paving()
	await _overview()
	await _framing()
	await _stand_view()
	_finish()


func _finish() -> void:
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
	await _frames(3)
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	return img


func _save(img: Image, name: String) -> void:
	var path := _out_dir.path_join(name)
	var err := img.save_png(path)
	if err != OK:
		_invalid("could not save %s (error %d)" % [path, err])
		return
	print("PLATE saved %s size=%s" % [path, img.get_size()])


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node)
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		out.append(mi)
	return out


func _aabb_of(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in _meshes(node):
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _corners(box: AABB) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in 8:
		out.append(box.get_endpoint(i))
	return out


func _add_colliders(node: Node) -> void:
	for mi in _meshes(node):
		if mi.mesh != null:
			mi.create_trimesh_collision()


func _prove_in_frame(label: String, points: Array[Vector3]) -> bool:
	var rect := Rect2(Vector2.ZERO, root.get_visible_rect().size).grow(-MARGIN_PX)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in points:
		if _cam.is_position_behind(p):
			_invalid("%s: point %s is behind the camera" % [label, p])
			return false
		var s := _cam.unproject_position(p)
		lo = lo.min(s)
		hi = hi.max(s)
	var ok := rect.has_point(lo) and rect.has_point(hi)
	print("INFRAME %s screen=(%.0f,%.0f)-(%.0f,%.0f) ok=%s" % [label, lo.x, lo.y, hi.x, hi.y, ok])
	if not ok:
		_invalid("%s: projected bounds leave the viewport" % label)
	return ok


## Rays from the camera to sampled surface points of the subject; at least half must hit
## the subject first. Supporting evidence only: the plate itself shows visibility.
func _prove_visible(label: String, subject: Node3D) -> bool:
	var centre := _aabb_of(subject).get_center()
	var targets: Array[Vector3] = []
	for mi in _meshes(subject):
		var faces: PackedVector3Array = mi.mesh.get_faces()
		var step := maxi(1, floori(faces.size() / 8.0))
		for i in range(0, faces.size(), step):
			targets.append((mi.global_transform * faces[i]).lerp(centre, 0.05))
	var space := _cam.get_world_3d().direct_space_state
	var hits := 0
	for t in targets:
		var q := PhysicsRayQueryParameters3D.create(
			_cam.global_position, t + (t - _cam.global_position).normalized() * 0.05
		)
		var hit := space.intersect_ray(q)
		if hit and (hit.collider == subject or subject.is_ancestor_of(hit.collider)):
			hits += 1
	var ok := hits * 2 >= targets.size() and hits > 0
	print("VISIBLE %s ray_hits=%d/%d ok=%s" % [label, hits, targets.size(), ok])
	if not ok:
		_invalid("%s: occluded or not hit (%d of %d rays)" % [label, hits, targets.size()])
	return ok


## Steps the sim by 60 fps frames at the clock's speed until it reaches `target`.
func _step_to(target: int) -> void:
	var guard := 0
	while _clock.tick < target and guard < 100000:
		_clock.advance(FRAME)
		guard += 1


func _sim() -> FlightSim:
	return _main.get_node("FlightSim")


func _follow() -> void:
	var p: Vector3 = _plane.global_position
	# The focus is on the plane itself: a plane still in the air at the first sample,
	# with the focus on the ground under it, sits near the eye and leaves the frame.
	_rig.position = p
	_rig.bounds_half_extent = 400.0
	_rig.distance = FOLLOW_DISTANCE
	_rig.yaw = 0.0
	_rig.zoom(1.0)


func _strip() -> void:
	_beat("strip")
	var rows: Array[Image] = []
	for row in STRIP_ROWS:
		var frames: Array[Image] = []
		for target in row[1]:
			_step_to(_t0 + target)
			_plane.update_pose()
			# The first sample can come before the views have posed the plane (it is
			# hidden and at the origin), and following that point leaves the frame. Let
			# frames pass until the plane is shown, then follow where it is.
			var wait := 0
			while not _plane.visible and wait < 30:
				await process_frame
				_plane.update_pose()
				wait += 1
			_follow()
			await physics_frame
			await physics_frame
			await _frames(2)
			var model: Node3D = _plane.get_node("Pivot")
			var tag := "%s_t%d" % [row[0], _clock.tick]
			var state: int = _sim().state_of("GMF101-d0")
			if not row[2].has(state):
				_invalid("%s: flight state %d, the row needs one of %s" % [tag, state, row[2]])
				continue
			print(
				(
					"FRAME %s tick=%d state=%d pos=%s nose=%s pitch_deg=%.1f"
					% [
						tag,
						_clock.tick,
						_sim().state_of("GMF101-d0"),
						_plane.global_position,
						_plane.global_basis.z,
						rad_to_deg(asin(_plane.global_basis.z.y))
					]
				)
			)
			if not _plane.visible:
				_invalid("%s: plane hidden" % tag)
				continue
			if not (_prove_in_frame(tag, _corners(_aabb_of(model))) and _prove_visible(tag, model)):
				continue
			var img := await _grab()
			_save(img, "frame_%s.png" % tag)
			img.resize(640, 360, Image.INTERPOLATE_LANCZOS)
			frames.append(img)
		var line := Image.create(640 * frames.size(), 360, false, Image.FORMAT_RGBA8)
		for k in frames.size():
			line.blit_rect(frames[k], Rect2i(0, 0, 640, 360), Vector2i(k * 640, 0))
		rows.append(line)
	var sheet := Image.create(2560, 360 * rows.size(), false, Image.FORMAT_RGBA8)
	for r in rows.size():
		sheet.blit_rect(rows[r], Rect2i(Vector2i.ZERO, rows[r].get_size()), Vector2i(0, r * 360))
	_save(sheet, "frame_strip_3x.png")


## A straight-down orthographic view of the whole airfield with the plane at the stand,
## and marker spheres on every waypoint.
func _overview() -> void:
	_beat("overview")
	# The strip ran the clock to the end of the flight; rewind to mid-boarding through the
	# sim's own snapshot so the plane stands at the gate.
	var boarding := _sim().state_start("GMF101-d0", FlightSim.State.BOARDING) + 50
	var snap := _sim().to_snapshot()
	snap["tick"] = boarding
	snap["flights"][0]["state"] = FlightSim.State.BOARDING
	print("OVERVIEW restore=", _sim().from_snapshot(snap))
	_clock.tick = boarding
	_plane.update_pose()
	var airside: Node3D = _main.get_node("Airside")
	for m in airside.get_children():
		if m is Marker3D:
			var dot := MeshInstance3D.new()
			dot.mesh = SphereMesh.new()
			dot.scale = Vector3.ONE * 4.0
			dot.position = m.position + Vector3(0, 1, 0)
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(1, 0.2, 0.9)
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			dot.material_override = mat
			airside.add_child(dot)
	var top := Camera3D.new()
	top.projection = Camera3D.PROJECTION_ORTHOGONAL
	top.size = 290.0
	top.far = 1000.0
	_main.add_child(top)
	top.look_at_from_position(Vector3(0, 400, -100), Vector3(0, 0, -100), Vector3.FORWARD)
	top.make_current()
	_cam = top
	await _frames(4)
	var model: Node3D = _plane.get_node("Pivot")
	print(
		"OVERVIEW plane_state=", _sim().state_of("GMF101-d0"), " plane_pos=", _plane.global_position
	)
	var terminal: Node3D = airside.get_node("Terminal")
	var pts: Array[Vector3] = _corners(_aabb_of(model)) + _corners(_aabb_of(terminal))
	if _prove_in_frame("overview", pts):
		_save(await _grab(), "overview_top.png")


## Candidate default framings for the camera: projects the stand, the terminal's airside
## edge and the build grid corners, and saves a plate of each.
func _framing() -> void:
	_beat("framing")
	_cam = _main.get_node("TycoonCamera/Camera3D")
	_cam.make_current()
	var stand: Vector3 = _main.get_node("Airside/Stand").global_position
	var terminal: Node3D = _main.get_node("Airside/Terminal")
	var targets := {
		"stand": stand,
		"terminal_airside": terminal.global_position + Vector3(0, 8, -20),
		"terminal_centre": terminal.global_position + Vector3(0, 8, 0),
		"grid_nw": Vector3(-32, 0, -32),
		"grid_se": Vector3(32, 0, 32),
	}
	var shots := {"default": [Vector3.ZERO, 60.0], "airport": [Vector3(0, 0, -50), 120.0]}
	for key in shots:
		_rig.position = shots[key][0]
		_rig.distance = shots[key][1]
		_rig.yaw = 0.0
		_rig.zoom(1.0)
		await _frames(4)
		var rect := Rect2(Vector2.ZERO, root.get_visible_rect().size)
		for name in targets:
			var s := _cam.unproject_position(targets[name])
			print(
				(
					"FRAMING %s %s screen=(%.0f,%.0f) on_screen=%s"
					% [key, name, s.x, s.y, rect.has_point(s)]
				)
			)
		_save(await _grab(), "framing_%s.png" % key)


## The plane at the stand seen from the apron side (camera yawed to look south), to check
## it is nose-in at the terminal's airside face.
func _stand_view() -> void:
	_beat("stand_view")
	_plane.update_pose()
	_rig.position = Vector3(_plane.global_position.x, 0.0, _plane.global_position.z + 8.0)
	_rig.distance = 60.0
	_rig.yaw = PI
	_rig.zoom(1.0)
	await physics_frame
	await physics_frame
	await _frames(4)
	var model: Node3D = _plane.get_node("Pivot")
	if (
		_prove_in_frame("stand_view", _corners(_aabb_of(model)))
		and _prove_visible("stand_view", model)
	):
		_save(await _grab(), "stand_view.png")


## The plane's path over the ground states and what is under it.
func _taxi_paving() -> void:
	_beat("taxi_paving")
	var ground: Array[int] = [
		FlightSim.State.TAXI_IN, FlightSim.State.PUSHBACK, FlightSim.State.TAXI_OUT
	]
	var skip: Array[RID] = []
	for body in _plane.find_children("*", "StaticBody3D", true, false):
		skip.append((body as StaticBody3D).get_rid())
	var space := _plane.get_world_3d().direct_space_state
	var samples: Array[Dictionary] = []
	for state in ground:
		var from := _sim().state_start("GMF101-d0", state)
		var to := _sim().state_start("GMF101-d0", state + 1)
		for t in range(from, to, TAXI_SAMPLE_TICKS):
			_sim().tick = t
			_clock.tick = t
			_plane.update_pose()
			var at: Vector3 = _plane.global_position
			var hit := _surface_hit(space, at, skip)
			var y: float = hit.get("position", Vector3(0, -99, 0)).y
			var collider: Node = hit.get("collider")
			(
				samples
				. append(
					{
						"tick": t,
						"state": state,
						"at": at,
						"hit_y": y,
						"collider": collider.get_path() if collider != null else NodePath(),
						"paved": _is_paving(collider),
					}
				)
			)
	var last := {}
	for s in samples:
		if last.is_empty() or s["paved"] != last["paved"] or s["state"] != last["state"]:
			print(
				(
					"TAXI change tick=%d state=%d x=%.1f z=%.1f hit_y=%.2f hit=%s paved=%s"
					% [
						s["tick"],
						s["state"],
						s["at"].x,
						s["at"].z,
						s["hit_y"],
						s["collider"],
						s["paved"]
					]
				)
			)
		last = s
	for state in ground:
		var lo := INF
		var hi := -INF
		var grass := 0
		var on_taxi_paving := 0
		var count := 0
		var grass_lo := INF
		var grass_hi := -INF
		for s in samples:
			if s["state"] != state:
				continue
			count += 1
			lo = minf(lo, s["at"].z)
			hi = maxf(hi, s["at"].z)
			if str(s["collider"]).begins_with(PAVED_OWNERS[0]):
				on_taxi_paving += 1
			if not s["paved"]:
				grass += 1
				grass_lo = minf(grass_lo, s["at"].z)
				grass_hi = maxf(grass_hi, s["at"].z)
		print(
			(
				(
					"TAXI state=%d samples=%d z=[%.1f, %.1f] on_taxi_paving=%d on_grass=%d"
					+ " grass_z=[%.1f, %.1f]"
				)
				% [state, count, lo, hi, on_taxi_paving, grass, grass_lo, grass_hi]
			)
		)
	var in_state := samples.filter(func(c: Dictionary) -> bool: return c["state"] == ground[0])
	if in_state.is_empty():
		_invalid("taxi paving: no TAXI_IN samples")
		return
	var stand_x := float(_main.get_node("Airside/Stand").global_position.x)
	var top := Camera3D.new()
	top.projection = Camera3D.PROJECTION_ORTHOGONAL
	top.size = TOP_VIEW_SIZE
	top.far = 1000.0
	_main.add_child(top)
	top.look_at_from_position(
		Vector3(stand_x, 400, TOP_VIEW_Z), Vector3(stand_x, 0, TOP_VIEW_Z), Vector3.FORWARD
	)
	top.make_current()
	var rig_cam := _cam
	_cam = top
	var wanted := {"taxi_in_connector": -233.0, "taxi_in_paving_edge": PAVING_EDGE_Z}
	for label in wanted:
		var best := {}
		for c in in_state:
			if c["at"].z > PAVING_EDGE_Z + 60.0 or absf(c["at"].x - stand_x) > 1.0:
				continue
			if (
				best.is_empty()
				or absf(c["at"].z - wanted[label]) < absf(best["at"].z - wanted[label])
			):
				best = c
		if best.is_empty():
			_invalid("taxi paving %s: no TAXI_IN sample on the connector x %.1f" % [label, stand_x])
			continue
		_sim().tick = best["tick"]
		_clock.tick = best["tick"]
		_plane.update_pose()
		await _frames(4)
		print(
			(
				"TAXI plate %s tick=%d plane=%s paved=%s connector_x=%.1f"
				% [label, best["tick"], _plane.global_position, best["paved"], stand_x]
			)
		)
		var model: Node3D = _plane.get_node("Pivot")
		var marks: Array[Vector3] = _corners(_aabb_of(model))
		marks.append(Vector3(stand_x, 0.0, PAVING_EDGE_Z))
		marks.append(Vector3(stand_x, 0.0, StandPlacement.TAXI_LANE_Z))
		if _prove_in_frame(label, marks) and _prove_visible(label, model):
			_save(await _grab(), "taxi_%s.png" % label)
	await _lane_plates(in_state, stand_x, top)
	_cam = rig_cam
	rig_cam.make_current()
	top.queue_free()


## The first surface a ray straight down at `at` hits that the player can see: a hit
## on the collider of a hidden mesh (the build-mode guard area, the buyable-land fills)
## is passed through and the ray cast again. Colliders in `skip` are never hit.
func _surface_hit(space: PhysicsDirectSpaceState3D, at: Vector3, skip: Array[RID]) -> Dictionary:
	var exclude := skip.duplicate()
	for i in 16:
		var query := PhysicsRayQueryParameters3D.create(
			Vector3(at.x, 60.0, at.z), Vector3(at.x, -20.0, at.z)
		)
		query.exclude = exclude
		var hit := space.intersect_ray(query)
		var body: Node = hit.get("collider")
		var shown := body as Node3D
		if body != null and body.get_parent() is Node3D:
			shown = body.get_parent() as Node3D
		if body == null or shown == null or shown.is_visible_in_tree():
			return hit
		exclude.append(hit["rid"])
	return {}


## Whether `collider` is a paved surface: the taxi paving, a runway piece or the
## terminal site's paving. Anything else (the Ground grass, a hidden mesh's
## collider) is not.
func _is_paving(collider: Node) -> bool:
	if collider == null:
		return false
	var path := str(collider.get_path())
	for owner_path in PAVED_OWNERS:
		if path.begins_with(owner_path):
			return true
	return false


## The plane mid-taxi on the lane, halfway from the runway exit to its stand's join,
## seen from straight above and from a distance. Both prove the plane and the lane's
## and connectors' paving are in frame.
func _lane_plates(in_state: Array, stand_x: float, top: Camera3D) -> void:
	_beat("taxi_lane_plates")
	_show_hud(false)
	var exit_x := float(_main.get_node("Airside/TaxiEast").global_position.x)
	var half_x := (exit_x + stand_x) / 2.0
	var mid := {}
	for c in in_state:
		if absf(c["at"].z - StandPlacement.TAXI_LANE_Z) > 0.5:
			continue
		if mid.is_empty() or absf(c["at"].x - half_x) < absf(mid["at"].x - half_x):
			mid = c
	if mid.is_empty():
		_invalid("taxi lane: no TAXI_IN sample on the lane")
		return
	_sim().tick = mid["tick"]
	_clock.tick = mid["tick"]
	_plane.update_pose()
	print("TAXI plate lane tick=%d plane=%s paved=%s" % [mid["tick"], mid["at"], mid["paved"]])
	var paving := (_main.get_node("Airside") as Airside).paving
	var marks: Array[Vector3] = _corners(_aabb_of(_plane.get_node("Pivot")))
	for strip in paving.shown:
		var rect: Rect2 = strip["rect"]
		var south := minf(rect.end.y, PAVING_EDGE_Z)
		for x in [rect.position.x, rect.end.x]:
			marks.append(Vector3(x, 0.0, rect.position.y))
			marks.append(Vector3(x, 0.0, south))
	top.size = LANE_VIEW_SIZE
	top.look_at_from_position(
		Vector3(LANE_VIEW_X, 400, LANE_VIEW_Z),
		Vector3(LANE_VIEW_X, 0, LANE_VIEW_Z),
		Vector3.FORWARD
	)
	await _frames(4)
	var model: Node3D = _plane.get_node("Pivot")
	if _prove_in_frame("taxi_lane_top", marks) and _prove_visible("taxi_lane_top", model):
		_save(await _grab(), "taxi_lane_top.png")
	var far := Camera3D.new()
	far.fov = 50.0
	far.far = 2000.0
	_main.add_child(far)
	var lane_at := Vector3(LANE_VIEW_X, 0.0, LANE_VIEW_Z)
	far.look_at_from_position(lane_at + DISTANCE_OFFSET, lane_at, Vector3.UP)
	far.make_current()
	_cam = far
	await _frames(4)
	if _prove_in_frame("taxi_distance", marks) and _prove_visible("taxi_distance", model):
		_save(await _grab(), "taxi_distance.png")
	_cam = top
	top.make_current()
	far.queue_free()
	_show_hud(true)


## Shows or hides every HUD layer, so a paving plate shows the ground under the panels.
func _show_hud(on: bool) -> void:
	for layer in _main.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = on


## The two-gate layout (decision second-gate-needs-a-wider-terminal-the-12x16-starter-
## holds-o): one wide terminal with gate A's exit and desk and gate B's 44 cells east,
## as gates4_plates_probe.gd builds it without seats. No flight runs: each gate's
## ground routes are sampled through PlaneView.pose_at(), the plane's own pose
## function, with the view set to that gate, and the surface under each pose is
## ray-cast as in _taxi_paving(). Then a top-down plate of the lane and both
## connectors and a distance plate, each proving every strip is in frame.
func _two_gate_paving() -> void:
	_beat("two_gate_build")
	var mode := _main.get_node("BuildMode") as BuildMode
	(mode.get_node("Ghost") as Node3D).visible = false
	(_main.get_node("PassengerHud") as PassengerHud).dismiss_intro()
	if not _build_two_gates(mode):
		return
	await _frames(6)
	var airside := _main.get_node("Airside") as Airside
	var gates := airside.gate_stands.keys()
	gates.sort()
	print(
		(
			"TWO_GATE bindings=%s stands=%s exits_cells_apart=%d"
			% [
				(_main.get_node("GateDesks") as GateDesks).bindings,
				airside.gate_stands,
				TWO_GATE_EXITS[1].x - TWO_GATE_EXITS[0].x
			]
		)
	)
	if gates != ["A", "B"]:
		_invalid("two gates: the gate stands are %s, not A and B" % [gates])
		return
	_add_colliders(_main)
	await physics_frame
	var skip: Array[RID] = []
	for body in _plane.find_children("*", "StaticBody3D", true, false):
		skip.append((body as StaticBody3D).get_rid())
	var space := _plane.get_world_3d().direct_space_state
	var starts: Array[int] = []
	for state in FlightSim.State.DEPARTED + 1:
		starts.append(state * POSE_STATE_TICKS)
	var ground: Array[int] = [
		FlightSim.State.TAXI_IN, FlightSim.State.PUSHBACK, FlightSim.State.TAXI_OUT
	]
	for gate: String in gates:
		_plane.gate = gate
		for state in ground:
			var count := 0
			var grass := 0
			var on_taxi_paving := 0
			var lo := INF
			var hi := -INF
			for k in range(0, POSE_STATE_TICKS, TAXI_SAMPLE_TICKS):
				var pose: Dictionary = _plane.pose_at(starts, float(starts[state] + k))
				if pose.get("phase", -1) != state:
					_invalid("two gates: gate %s tick %d is not in state %d" % [gate, k, state])
					return
				var at: Vector3 = (pose["transform"] as Transform3D).origin
				var collider: Node = _surface_hit(space, at, skip).get("collider")
				count += 1
				lo = minf(lo, at.z)
				hi = maxf(hi, at.z)
				if collider != null and str(collider.get_path()).begins_with(PAVED_OWNERS[0]):
					on_taxi_paving += 1
				if not _is_paving(collider):
					grass += 1
					print(
						"TWO_GATE grass gate=%s state=%d at=%s hit=%s" % [gate, state, at, collider]
					)
			print(
				(
					(
						"TWO_GATE gate=%s state=%d samples=%d z=[%.1f, %.1f] on_taxi_paving=%d"
						+ " on_grass=%d"
					)
					% [gate, state, count, lo, hi, on_taxi_paving, grass]
				)
			)
	_plane.gate = FlightSim.DEFAULT_GATE
	await _two_gate_plates(airside)


## Builds the two-gate terminal through the grid, buying the land it needs.
func _build_two_gates(mode: BuildMode) -> bool:
	var grid := mode.grid
	var offset := ReferenceTerminal.offset_on(grid)
	var edits: Array[BuildEdit] = []
	var lo := TWO_GATE_FLOOR_MIN
	var hi := TWO_GATE_FLOOR_MAX
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y) + offset, BuildGrid.FLOOR_TILE, 1))
	for x in range(lo.x, hi.x + 1):
		if not TWO_GATE_EXITS.any(func(e: Vector2i) -> bool: return e.x == x):
			edits.append(BuildEdit.place_wall(Vector2i(x, lo.y) + offset, BuildGrid.Side.NORTH))
		if x != TWO_GATE_ENTRANCE.x:
			edits.append(BuildEdit.place_wall(Vector2i(x, hi.y) + offset, BuildGrid.Side.SOUTH))
		if not TWO_GATE_SCANNER_XS.has(x):
			edits.append(
				BuildEdit.place_wall(Vector2i(x, TWO_GATE_DIVIDER_Y) + offset, BuildGrid.Side.NORTH)
			)
	for y in range(lo.y, hi.y + 1):
		edits.append(BuildEdit.place_wall(Vector2i(lo.x, y) + offset, BuildGrid.Side.WEST))
		edits.append(BuildEdit.place_wall(Vector2i(hi.x, y) + offset, BuildGrid.Side.EAST))
	edits.append(BuildEdit.place_object(&"checkin_desk", Vector2i(11, 11) + offset, 0))
	for x in TWO_GATE_SCANNER_XS:
		edits.append(
			BuildEdit.place_object(
				&"security_scanner", Vector2i(x, TWO_GATE_DIVIDER_Y - 1) + offset, 0
			)
		)
	edits.append(BuildEdit.place_object(&"entrance_door", TWO_GATE_ENTRANCE + offset, 2))
	for i in TWO_GATE_EXITS.size():
		edits.append(BuildEdit.place_object(&"exit_door", TWO_GATE_EXITS[i] + offset, 0))
		edits.append(BuildEdit.place_object(GateDesks.DESK, TWO_GATE_DESKS[i] + offset, 0))
	var land := mode.land_tool.land
	for edit in edits:
		var plot: Vector2i = land.plot_of(edit.cell)
		while not land.is_owned(plot):
			var best := Vector2i(-1, -1)
			var best_d := 1 << 30
			for candidate in land.buyable_plots():
				var d := absi(candidate.x - plot.x) + absi(candidate.y - plot.y)
				if d < best_d:
					best_d = d
					best = candidate
			if best == Vector2i(-1, -1) or not land.buy(best, null).ok:
				_invalid("two gates: the land toward plot %s could not be bought" % plot)
				return false
	for edit in edits:
		var result := grid.apply(edit)
		if not result.ok:
			_invalid("two gates: edit at %s refused: %s" % [edit.cell, result.reason_text()])
			return false
	return true


## Top-down and distance plates of the two-gate paving.
func _two_gate_plates(airside: Airside) -> void:
	_beat("two_gate_plates")
	_show_hud(false)
	var marks: Array[Vector3] = []
	var west := INF
	var east := -INF
	for strip in airside.paving.shown:
		var rect: Rect2 = strip["rect"]
		west = minf(west, rect.position.x)
		east = maxf(east, rect.end.x)
		var south := minf(rect.end.y, PAVING_EDGE_Z)
		for x in [rect.position.x, rect.end.x]:
			marks.append(Vector3(x, 0.0, rect.position.y))
			marks.append(Vector3(x, 0.0, south))
	print("TWO_GATE strips=%s" % [airside.paving.shown])
	var centre := Vector3((west + east) / 2.0, 0.0, LANE_VIEW_Z)
	var aspect := root.get_visible_rect().size.aspect()
	var top := Camera3D.new()
	top.projection = Camera3D.PROJECTION_ORTHOGONAL
	top.size = maxf(LANE_VIEW_SIZE, (east - west + 60.0) / aspect)
	top.far = 1000.0
	_main.add_child(top)
	top.look_at_from_position(centre + Vector3.UP * 400.0, centre, Vector3.FORWARD)
	top.make_current()
	_cam = top
	await _frames(4)
	if _prove_in_frame("two_gate_top", marks):
		_save(await _grab(), "two_gate_top.png")
	var far := Camera3D.new()
	far.fov = 50.0
	far.far = 2000.0
	_main.add_child(far)
	far.look_at_from_position(centre + DISTANCE_OFFSET, centre, Vector3.UP)
	far.make_current()
	_cam = far
	await _frames(4)
	if _prove_in_frame("two_gate_distance", marks):
		_save(await _grab(), "two_gate_distance.png")
	top.queue_free()
	far.queue_free()
