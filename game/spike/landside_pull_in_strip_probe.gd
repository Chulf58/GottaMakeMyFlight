extends SceneTree
## Windowed strip of a car pulling into a curb berth in the real main.tscn: the berth's
## path (LandsidePaths) carries it from road_in into the berth, and LandsideViews draws
## it along that path, facing the way it drives.
##
## Run (one windowed Godot run project-wide; this probe holds the slot while it runs):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://spike/landside_pull_in_strip_probe.gd
##
## main.tscn boots with a random sim seed (printed), the starter terminal (the HUD's
## debug button) and a check-in agent and a security officer hired, and plays until a
## car on road_in takes a berth. The camera aims at the middle of its way in, and eight
## frames are taken evenly from there to the tick it stands in the berth (a fraction of
## a tick apart), the sim stepped by the clock's own advance(), so LandsideViews draws
## through its real tick signal and alpha. Every frame proves the car in frame (its
## projected bounds inside the viewport with a margin), frame 0 also hit by camera
## rays against colliders of every mesh in the scene, else PROBE_INVALID. Per frame it
## prints the car's position, nose and step: each step must be more than 0 and no
## longer than a lane step a tick allows over the frame gap, plus slack, the nose along
## the step (dot over 0.9), and the last frame in the berth (within 5 cm). The strip
## (four frames a row, two rows) goes to tools/blender/out/landside/pull_in/.

const OUT_REL := "res://../tools/blender/out/landside/pull_in"
const MAIN_SCENE := "res://main/main.tscn"
const CAMERA_RIG := "TycoonCamera"
const MARGIN_PX := 8.0
const HANG_LIMIT_MS := 120000
const TICK_LIMIT := 60000
const FRAMES := 8
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
			OS.crash("landside pull-in probe hung")


func _run() -> void:
	await _boot()
	await _plate_pull_in()
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
	_rig = _main.get_node(CAMERA_RIG)
	_cam = _main.get_node(CAMERA_RIG + "/Camera3D")
	var mode: BuildMode = _main.get_node("BuildMode")
	(mode.get_node("Ghost") as Node3D).visible = false
	(_main.get_node("PassengerHud") as PassengerHud).press_starter_terminal()
	var staff: StaffSim = _main.get_node("Staff")
	staff.hire(StaffMember.Role.CHECKIN)
	staff.hire(StaffMember.Role.SECURITY)
	await _frames(10)


func _tick() -> void:
	_clock.set_paused(false)
	_clock.advance(SimClock.STEP)
	_clock.set_paused(true)


## Steps until a drawn car has just left road_in for a berth's path; its id, or 0.
func _await_pull_in() -> int:
	_stage = "wait"
	var on_road := {}
	while _clock.tick < TICK_LIMIT:
		for id in _landside.vehicle_ids():
			on_road[id] = _landside.get_vehicle(id).lane == LandsideVehicle.Lane.ROAD_IN
		_tick()
		for id in _landside.vehicle_ids():
			var v := _landside.get_vehicle(id)
			var took: bool = v.lane == LandsideVehicle.Lane.BERTH and on_road.get(id, false)
			if took and v.stage == LandsideVehicle.Stage.DRIVE and _views.has_vehicle(id):
				return id
		if _clock.tick % 200 == 0:
			_beat("wait %d" % _clock.tick)
			await process_frame
	return 0


func _plate_pull_in() -> void:
	var id := await _await_pull_in()
	if id == 0:
		_invalid("no car took a berth by tick %d" % TICK_LIMIT)
		return
	var v := _landside.get_vehicle(id)
	var berth := _landside.definition.berth_position(v.stop)
	_views.draw()
	var start := _views.node_for(id).global_position
	print(
		(
			"PULL_IN vehicle=%d berth=%d at %s from %s tick=%d"
			% [id, v.stop, berth, start, _clock.tick]
		)
	)
	await _aim("pull_in", (start + berth) * 0.5, 22.0, 0.0)
	var strip := Image.create(1920, 540, false, Image.FORMAT_RGBA8)
	var last := Vector3.INF
	var left := ceili(float(_landside.paths.berth_stand[v.stop] - v.pos_mm) / LandsideSim.SPEED_MM)
	var gap := left / float(FRAMES - 1)
	var longest := gap * LandsideSim.SPEED_MM / 1000.0 + 0.01
	print("PULL_IN %d ticks to the berth, frames %.2f ticks apart" % [left, gap])
	for i in FRAMES:
		if i > 0:
			_clock.set_paused(false)
			_clock.advance(SimClock.STEP * gap)
			_clock.set_paused(true)
		_views.draw()
		var node := _views.node_for(id)
		if node == null:
			_invalid("frame %d: vehicle %d left the view" % [i, id])
			return
		var at := node.global_position
		var nose := node.global_basis.z
		var step := at - last if i > 0 else Vector3.ZERO
		print(
			(
				"STRIP frame=%d tick=%d alpha=%.2f stage=%d at=%s nose=%s step=%.3f nose_dot=%.3f"
				% [
					i,
					_clock.tick,
					_clock.alpha,
					v.stage,
					at,
					nose,
					step.length(),
					nose.dot(step.normalized()) if step.length() > 0.001 else NAN
				]
			)
		)
		if i > 0:
			if step.length() <= 0.001 and v.stage == LandsideVehicle.Stage.DRIVE:
				_invalid("frame %d: the car did not move while pulling in" % i)
			if step.length() > longest:
				_invalid("frame %d: the car jumped %.3f m" % [i, step.length()])
			if step.length() > 0.001 and nose.dot(step.normalized()) < 0.9:
				_invalid("frame %d: the car moves %s but faces %s" % [i, step, nose])
		last = at
		if not _prove_in_frame("pull_in/frame %d" % i, _aabb_of(node)):
			return
		if i == 0 and not _prove_visible("pull_in/frame 0", node):
			return
		var img := await _grab()
		var tile := img.get_region(Rect2i(Vector2i(320, 180), Vector2i(1280, 720)))
		tile.resize(480, 270, Image.INTERPOLATE_LANCZOS)
		strip.blit_rect(
			tile,
			Rect2i(Vector2i.ZERO, Vector2i(480, 270)),
			Vector2i((i % 4) * 480, floori(i / 4.0) * 270)
		)
	print("PULL_IN last at %s, %.2f m from the berth" % [last, last.distance_to(berth)])
	if last.distance_to(berth) > 0.05:
		_invalid("the car ended %.2f m from its berth" % last.distance_to(berth))
	var path := _out_dir.path_join("landside_pull_in_strip.png")
	if strip.save_png(path) != OK:
		_invalid("could not save %s" % path)
	else:
		print("PLATE saved %s" % path)


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
