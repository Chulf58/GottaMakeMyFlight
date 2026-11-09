extends SceneTree
## Windowed plate probe for the airside props (board 4c08b8e5, Runway R11): the
## towbarless tug in pushback, the jet bridge docked at a medium and a large
## stand, the bridge over the passengers' apron walk, and the turn-off taxi
## signs at play range at 1x and 2.5x. It answers the item's three open
## questions with plates and numbers; it rules nothing.
##
## Run (one windowed Godot run project-wide; hold tools/blender/out/.windowed.lock):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game -s res://spike/airside_props_plates_probe.gd
##
## Boots main.tscn with the starter shell and a gate desk (StarterFlight), so the
## real ApronStand gives gate A its stand and the real Airside lays out its
## bridge and signs. No flight runs: the clock, the PlaneFleet and the main
## PlaneView stop processing, and the probe poses that PlaneView itself, as
## update_pose() does (FlightPose.pose, model_position_at, then the view's own
## _follow_props(), which places the tug and reports the door to the bridge).
## Every plate projects its subjects' bounds into the viewport with MARGIN_PX
## and casts camera rays at them (trimesh colliders on every mesh) before it is
## saved; on failure it prints PROBE_INVALID and exits 1. The play-range tug
## plates print the share of tug rays that reach the tug first (question a)
## without requiring it. The HUD is hidden. Prints the world seed.
##
## Numbers: the tug's reach past each model's nose and its gap to the wall
## (a), each sign's legend height in pixels at play range (b), and the bridge
## underside's clearance over the gate's walk (StandPlacement.walk_of) for
## models 05, 06 and 07 against a passenger's height (c).

const StarterFlight := preload("res://spike/starter_flight.gd")
const PASSENGER := preload("res://assets/people/tcp_male_character_01.glb")
const MAIN_SCENE := "res://main/main.tscn"
const OUT_REL := "res://../tools/blender/out/runway_r11"
const MARGIN_PX := 8.0
## The play camera (TycoonCamera): the medium angle step, its lens, its home
## distance.
const PLAY_PITCH_DEG := 54.0
const PLAY_FOV := 55.0
const PLAY_DISTANCE := 80.0
const PUSH_STRIP: Array[float] = [0.12, 0.55, 0.95]
## Walk samples: the step along the walk and the passenger's shoulder radius.
const WALK_STEP_M := 0.1
const BODY_RADIUS_M := 0.3
const SHEET_TILE := Vector2i(480, 270)
## Yaws tried, in order, for the close pushback strip (all north of the wall).
const STRIP_YAWS: Array[float] = [135.0, 225.0, 100.0, 260.0]
## Camera offsets from the walk's lowest point tried for the walk side plate.
const SIDE_EYES: Array[Vector3] = [
	Vector3(9.0, 0.6, -9.0),
	Vector3(4.0, 0.4, -10.0),
	Vector3(11.0, 0.3, -2.0),
	Vector3(6.0, 1.2, -6.0),
	Vector3(-1.0, 0.4, -11.0),
	Vector3(8.0, 0.8, 4.0),
	Vector3(-8.0, 0.6, 5.0),
]

var _out_dir := ""
var _failed := false
var _main: Node
var _cam: Camera3D
var _view: PlaneView
var _airside: Airside
var _gate := ""
var _stand: Dictionary = {}
var _plates: Array[String] = []


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	print("PROBE out_dir=", _out_dir)
	_run.call_deferred()


func _run() -> void:
	_main = load(MAIN_SCENE).instantiate()
	var clock: SimClock = _main.get_node("SimClock")
	var world_seed := randi()
	clock.seed_rng(world_seed)
	print("PROBE world_seed=%d" % world_seed)
	root.add_child(_main)
	clock.set_process(false)
	for fleet in _main.find_children("*", "PlaneFleet", true, false):
		fleet.set_process(false)
	_view = _main.get_node("PlaneView")
	_view.set_process(false)
	(_main.get_node("PlaneView2") as Node).set_process(false)
	_airside = _main.get_node("Airside")
	await _frames(6)
	if not StarterFlight.add_gate_desk((_main.get_node("BuildMode") as BuildMode).grid):
		_invalid("the gate desk was refused")
		_finish()
		return
	await _frames(6)
	if _airside.gate_stands.is_empty():
		_invalid("no gate got a stand")
		_finish()
		return
	_gate = _airside.gate_stands.keys()[0]
	_stand = _airside.gate_stands[_gate]
	_view.gate = _gate
	print(
		(
			"PROBE gate=%s stand=%s bridges=%d signs=%d"
			% [_gate, _stand, _airside.props.bridges.size(), _airside.props.signs.size()]
		)
	)
	if _airside.props.bridges.size() < 1 or _airside.props.signs.size() < 1:
		_invalid("the airside props were not laid out")
		_finish()
		return
	_show_hud(false)
	_cam = Camera3D.new()
	_cam.fov = PLAY_FOV
	_cam.far = 2000.0
	_main.add_child(_cam)
	_cam.make_current()
	_add_colliders(_main)
	await _tug_plates()
	await _bridge_plates()
	await _walk_plates()
	await _sign_plates()
	_contact_sheet()
	_finish()


func _finish() -> void:
	print("PROBE done failed=%s plates=%d" % [_failed, _plates.size()])
	quit(1 if _failed else 0)


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw


## Poses the main PlaneView with `model` of `plane_class` at pushback progress
## `t` in state `state`, as update_pose() does, and lets it place its props.
func _pose(model: String, plane_class: String, state: int, t: float) -> Node3D:
	_view.show_model(model)
	var path := _view._path(FlightSim.State.PUSHBACK, plane_class)
	var entry := _view._entry_dir(FlightSim.State.PUSHBACK, plane_class)
	var pose := FlightPose.pose(FlightSim.State.PUSHBACK, t, path, entry)
	pose.origin.y += PlaneView.ground_height_at(pose.origin)
	_view.transform = pose
	_view.phase = state
	_view.visible = true
	_view.flight_id = "probe"
	_view._set_model_position(_view.model_position_at(state, pose, plane_class))
	_view._follow_props()
	var model_node: Node3D = _view.get_node("Pivot").get_child(0)
	if model_node.find_children("*", "StaticBody3D", true, false).is_empty():
		_add_colliders(model_node)
	return model_node


func _tug_plates() -> void:
	var tug := _tug()
	var wall := float(_stand["wall_z"])
	for model: String in PlaneModels.PLANES:
		var cls := _class_of(model)
		var plane := _pose(model, cls, FlightSim.State.PUSHBACK, 0.0)
		await _frames(2)
		var box := _aabb_of(tug)
		var nose := _aabb_of(plane).end.z
		var gear := plane.global_transform * PlaneProps.nose_gear_contact(plane, model)
		var mount := (tug.find_child("Mount_NoseGear", true, false) as Node3D).global_position
		print(
			(
				(
					"TUG %s at the stand: mount %.4f m off the nose wheel, tug front z %.2f, nose z"
					+ " %.2f, front past the nose %.2f m, gap to the wall %.2f m, nose %.2f m ahead"
					+ " of the nose wheel"
				)
				% [
					model,
					mount.distance_to(gear),
					box.end.z,
					nose,
					box.end.z - nose,
					wall - box.end.z,
					nose - gear.z,
				]
			)
		)
	for model: String in ["tp_plane_03a", "tp_plane_07a"]:
		var cls := _class_of(model)
		var near := 26.0 if model == "tp_plane_03a" else 40.0
		for t in PUSH_STRIP:
			var plane := _pose(model, cls, FlightSim.State.PUSHBACK, t)
			await _frames(2)
			if not tug.visible:
				_invalid("%s t %.2f: the tug is hidden during pushback" % [model, t])
				continue
			var at := tug.global_position
			# From the first side off the terminal's that sees the tug.
			for yaw in STRIP_YAWS:
				_aim(at + Vector3(0.0, 0.8, 0.0), yaw, 14.0, near)
				await _frames(3)
				if _report_rays("TUG_EYE %s t %.2f yaw %d" % [model, t, yaw], tug) >= 0.25:
					break
			var name := "tug_%s_t%02d.png" % [model.substr(9, 2), roundi(t * 100.0)]
			if _prove(name, [tug], true) and _prove_seen(name, plane):
				await _save(name)
		# Question (a): the tug at play range, from four sides; rays only reported.
		var plane := _pose(model, cls, FlightSim.State.PUSHBACK, PUSH_STRIP[0])
		for yaw in [0.0, 90.0, 180.0, 270.0]:
			_aim(tug.global_position, yaw, PLAY_PITCH_DEG, PLAY_DISTANCE)
			await _frames(3)
			var name := "tug_%s_play_yaw%03d.png" % [model.substr(9, 2), roundi(yaw)]
			_report_rays("TUG_PLAY %s yaw %d" % [model, roundi(yaw)], tug)
			if yaw == 0.0 or yaw == 90.0:
				if _prove(name, [plane], true) and _prove(name + " tug", [tug], false):
					await _save(name)


func _bridge_plates() -> void:
	var entry: Dictionary = _airside.props.bridges[_gate]
	var bridge: Node3D = entry["node"]
	for model: String in ["tp_plane_05a", "tp_plane_07a", "tp_plane_06a", "tp_plane_04a"]:
		var plane := _pose(model, _class_of(model), FlightSim.State.BOARDING, 0.0)
		await _frames(2)
		_add_colliders(bridge)
		var door: Vector3 = plane.global_transform * PlaneModels.PLANES[model]["doors"][0]
		var mount := (bridge.find_child("Mount_Door", true, false) as Node3D).global_position
		print(
			(
				"BRIDGE %s docked=%s Mount_Door %.4f m off the door %s slide %.2f pitch %.2f"
				% [
					model,
					entry["docked"],
					mount.distance_to(door),
					door,
					entry["pose"]["slide"],
					rad_to_deg(entry["pose"]["pitch"]),
				]
			)
		)
		# Question (c): the bridge underside over the gate's walk.
		_walk_clearance(model, bridge)
		if model == "tp_plane_04a":
			continue
		if not entry["docked"]:
			_invalid("%s: the bridge did not dock" % model)
		var far: float = {"tp_plane_05a": 34.0, "tp_plane_06a": 50.0}.get(model, 58.0)
		_aim(door.lerp(bridge.global_position, 0.5), 60.0, 32.0, far)
		await _frames(3)
		var name := "bridge_%s.png" % model.substr(9, 2)
		if _prove(name, [bridge], true) and _prove_seen(name, plane):
			await _save(name)


func _walk_plates() -> void:
	var plane := _pose("tp_plane_05a", PlaneClasses.MEDIUM, FlightSim.State.BOARDING, 0.0)
	await _frames(2)
	var bridge: Node3D = _airside.props.bridges[_gate]["node"]
	_add_colliders(bridge)
	var low := _walk_clearance("tp_plane_05a", bridge)
	var walk := _walk()
	var people: Array[Node3D] = []
	for at: Vector3 in [low["at"], walk[walk.size() - 1], walk[0].lerp(low["at"], 0.4)]:
		var person: Node3D = PASSENGER.instantiate()
		_main.add_child(person)
		person.global_position = Vector3(at.x, PlaneView.ground_height_at(at), at.z)
		person.rotation.y = PI
		_add_colliders(person)
		people.append(person)
	var height := _aabb_of(people[0]).size.y
	print("WALK passenger height %.2f m" % height)
	# Near level, from the first of these viewpoints that sees the passenger.
	var target: Vector3 = low["at"] + Vector3(0.0, 1.2, 0.0)
	var side_ok := false
	for eye: Vector3 in SIDE_EYES:
		_cam.look_at_from_position(target + eye, target, Vector3.UP)
		await _frames(3)
		if _report_rays("WALK_EYE %s" % eye, people[2]) >= 0.25:
			side_ok = true
			break
	if not side_ok:
		_invalid("walk_side.png: no viewpoint sees the passenger")
	elif (
		_prove("walk_side.png", [people[2]], true)
		and _prove("walk_side.png", [people[0]], false)
		and _prove_seen("walk_side.png", bridge)
	):
		await _save("walk_side.png")
	_aim(target, 60.0, 30.0, 24.0)
	await _frames(3)
	_report_rays("WALK_END passenger at the walk end", people[1])
	if _prove("walk_high.png", [people[0], bridge], true):
		await _save("walk_high.png")
	for person in people:
		person.queue_free()


func _sign_plates() -> void:
	var props := _airside.props
	for scale in [1.0, 2.5]:
		props.sign_scale = scale
		await _frames(2)
		_add_colliders(props)
		for i in props.signs.size():
			var sign := props.signs[i]
			var letter: String = props.turn_off_list[i]["loc"]
			for yaw in [180.0, 0.0]:
				_aim(
					sign.global_position + Vector3(0.0, 0.7 * scale, 0.0),
					yaw,
					PLAY_PITCH_DEG,
					PLAY_DISTANCE
				)
				await _frames(3)
				var glyph := sign.find_child("Glyph_Loc_" + letter, true, false) as Node3D
				var g := _aabb_of(glyph)
				var px := absf(
					_cam.unproject_position(g.position).y - _cam.unproject_position(g.end).y
				)
				var size := _aabb_of(sign).size
				print(
					(
						(
							"SIGN %s scale %.1f yaw %d: sign %.2f x %.2f m, legend %.2f m tall, %.1f px"
							+ " on a %d px screen"
						)
						% [
							letter,
							scale,
							roundi(yaw),
							size.x,
							size.y,
							g.size.y,
							px,
							roundi(root.get_visible_rect().size.y),
						]
					)
				)
				if i > 0 and yaw == 0.0:
					continue
				var name := (
					"sign_%s_x%02d_yaw%03d.png" % [letter, roundi(scale * 10.0), roundi(yaw)]
				)
				if _prove(name, [sign], true):
					await _save(name)
	props.sign_scale = 1.0


## The lowest bridge underside over the gate's walk for a docked `model`: casts
## up from each walk sample and BODY_RADIUS_M around it against the bridge's
## triangles. Prints and returns {"clearance", "at"}.
func _walk_clearance(model: String, bridge: Node3D) -> Dictionary:
	var tris := PackedVector3Array()
	for mi in _meshes(bridge):
		if not mi.is_visible_in_tree():
			continue
		for p in mi.mesh.get_faces():
			tris.append(mi.global_transform * p)
	var walk := _walk()
	if walk.size() < 2:
		_invalid("gate %s has no walk to its plane door" % _gate)
		return {"clearance": INF, "at": JetBridgePose.stand_door(_stand)}
	var best := {"clearance": INF, "at": walk[walk.size() - 1]}
	var covered := 0
	var samples := 0
	for i in range(1, walk.size()):
		var a: Vector3 = walk[i - 1]
		var b: Vector3 = walk[i]
		var steps := maxi(1, ceili(a.distance_to(b) / WALK_STEP_M))
		for k in steps + 1:
			var p := a.lerp(b, float(k) / steps)
			var ground := PlaneView.ground_height_at(p)
			var over := false
			for off: Vector3 in [
				Vector3.ZERO, Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK
			]:
				var from: Vector3 = Vector3(p.x, ground + 0.01, p.z) + off * BODY_RADIUS_M
				var hit := _lowest_hit(tris, from)
				if hit < INF:
					over = true
					if hit - ground < best["clearance"]:
						best = {"clearance": hit - ground, "at": Vector3(p.x, ground, p.z)}
			samples += 1
			covered += 1 if over else 0
	print(
		(
			(
				"WALK %s: walk %d points %.1f m, %d of %d samples under the bridge, lowest underside"
				+ " %.2f m over the ground at %s"
			)
			% [
				model,
				walk.size(),
				StandPlacement.walk_length(walk),
				covered,
				samples,
				best["clearance"],
				best["at"],
			]
		)
	)
	return best


func _lowest_hit(tris: PackedVector3Array, from: Vector3) -> float:
	var low := INF
	for i in range(0, tris.size(), 3):
		var hit: Variant = Geometry3D.ray_intersects_triangle(
			from, Vector3.UP, tris[i], tris[i + 1], tris[i + 2]
		)
		if hit != null:
			low = minf(low, (hit as Vector3).y)
	return low


func _walk() -> Array[Vector3]:
	var apron := _main.find_children("*", "ApronStand", true, false)[0] as ApronStand
	return StandPlacement.walk_of(apron.grid, apron.site, int(_stand["exit"]), _stand)


func _tug() -> Node3D:
	return (_view.get_node("Props") as PlaneProps).tug


func _class_of(model: String) -> String:
	for cls: String in PlaneClasses.CLASSES:
		if PlaneClasses.CLASSES[cls]["models"].has(model):
			return cls
	return PlaneClasses.MEDIUM


## Puts the camera `distance` from `focus`, `pitch` degrees above it, looking
## at it from yaw `yaw` (0: from the south, looking north).
func _aim(focus: Vector3, yaw: float, pitch: float, distance: float) -> void:
	var y := deg_to_rad(yaw)
	var p := deg_to_rad(pitch)
	var back := Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p))
	_cam.look_at_from_position(focus + back * distance, focus, Vector3.UP)


## Proves every subject's bounds lie in the viewport with MARGIN_PX and, when
## `need_rays`, that camera rays reach it first. A hidden subject, or one with
## no visible mesh (whose bounds would be an empty box at the origin), fails.
func _prove(label: String, subjects: Array, need_rays: bool) -> bool:
	var rect := Rect2(Vector2.ZERO, root.get_visible_rect().size).grow(-MARGIN_PX)
	for subject: Node3D in subjects:
		var shown := _meshes(subject).filter(
			func(mi: MeshInstance3D) -> bool: return mi.is_visible_in_tree()
		)
		if not subject.is_visible_in_tree() or shown.is_empty():
			_invalid("%s: %s is hidden or has no visible mesh" % [label, subject.name])
			return false
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for i in 8:
			var p := _aabb_of(subject).get_endpoint(i)
			if _cam.is_position_behind(p):
				_invalid("%s: %s is behind the camera" % [label, subject.name])
				return false
			var s := _cam.unproject_position(p)
			lo = lo.min(s)
			hi = hi.max(s)
		var ok := rect.has_point(lo) and rect.has_point(hi)
		print(
			(
				"INFRAME %s %s screen=(%.0f,%.0f)-(%.0f,%.0f) ok=%s"
				% [label, subject.name, lo.x, lo.y, hi.x, hi.y, ok]
			)
		)
		if not ok:
			_invalid("%s: %s leaves the viewport" % [label, subject.name])
			return false
		if need_rays and _report_rays("VISIBLE %s %s" % [label, subject.name], subject) < 0.25:
			_invalid("%s: %s is occluded" % [label, subject.name])
			return false
	return true


## Proves camera rays reach `subject` first, without needing all of it in frame.
func _prove_seen(label: String, subject: Node3D) -> bool:
	if _report_rays("VISIBLE %s %s" % [label, subject.name], subject) < 0.25:
		_invalid("%s: %s is occluded" % [label, subject.name])
		return false
	return true


## Casts rays from the camera at sampled surface points of `subject` and prints
## the share that hit it first.
func _report_rays(label: String, subject: Node3D) -> float:
	var targets: Array[Vector3] = []
	var centre := _aabb_of(subject).get_center()
	for mi in _meshes(subject):
		if not mi.is_visible_in_tree():
			continue
		var faces: PackedVector3Array = mi.mesh.get_faces()
		var step := maxi(1, floori(faces.size() / 24.0))
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
	var share := float(hits) / maxf(1.0, targets.size())
	print("%s ray_hits=%d/%d share=%.2f" % [label, hits, targets.size(), share])
	return share


func _save(name: String) -> void:
	await _frames(2)
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	var path := _out_dir.path_join(name)
	if img.save_png(path) != OK:
		_invalid("could not save %s" % path)
		return
	_plates.append(path)
	print("PLATE saved %s" % path)


func _contact_sheet() -> void:
	if _plates.is_empty():
		return
	var cols := 4
	var rows := ceili(_plates.size() / float(cols))
	var sheet := Image.create(SHEET_TILE.x * cols, SHEET_TILE.y * rows, false, Image.FORMAT_RGBA8)
	for i in _plates.size():
		var img := Image.load_from_file(_plates[i])
		img.resize(SHEET_TILE.x, SHEET_TILE.y)
		sheet.blit_rect(
			img,
			Rect2i(Vector2i.ZERO, SHEET_TILE),
			Vector2i(i % cols, floori(i / float(cols))) * SHEET_TILE
		)
	var path := _out_dir.path_join("contact_sheet.png")
	sheet.save_png(path)
	print("PLATE saved %s" % path)


func _show_hud(on: bool) -> void:
	for layer in _main.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = on


func _add_colliders(node: Node) -> void:
	for mi in _meshes(node):
		if mi.mesh != null and mi.find_children("*", "StaticBody3D", false, false).is_empty():
			mi.create_trimesh_collision()


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
		if not mi.is_visible_in_tree():
			continue
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box
