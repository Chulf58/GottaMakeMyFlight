extends SceneTree
## Windowed plate probe for the side-stand visuals (board 0793554d, Airside all
## around S8a; design airside-all-around-technical-design-one-route-source-per-
## con). Plates go under tools/blender/out/s8a_side_stands/.
##
## Run (one windowed Godot run project-wide; hold tools/blender/out/.windowed.lock):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://spike/side_stands_plates_probe.gd [-- --seed=N]
##
## Boots main.tscn with a new random world seed (printed; --seed=N replays),
## closes the intro (IntroClose), opens an east and a west exit in the starter
## shell and fills it, so the starter desk links east (gate A) and a second desk
## links west (gate B), as spike/side_gates_turnaround_probe.gd does. No flight
## runs: the clock is paused and the probe poses the main PlaneView itself at
## each gate's stand, as update_pose() does, so the real AirsideProps docks or
## folds the bridge from the drawn model. The HUD's CanvasLayers are hidden
## (anti_pattern a-plate-probe-s-occlusion-rays-see-only-meshes-so-a-hud-pane).
##
## Stages, each with plates at play distance and close up:
##  - W and E: the real west and east gates with planes 05 (docks), 04 (docks,
##    parked further out) and 03 (bridge folded, apron walk).
##  - outlines: build mode on, both gates' envelope outlines and captions.
##  - N: Airside given the starter's north exit stand alone as gate A.
##  - mixed: a north stand whose lane join is 14 m from the west spur, with the
##    real west gate (the near-spur link mitre).
##  - moved: the west gate's stand on a spur moved out to x -160, so the runway
##    stub at x -124 meets the lane mid-span from the north.
##  - cross: the mixed layout's north stand beside a west stand whose connector
##    crosses the north link's run-on to its wall line (Sol review).
##
## Every plate projects its subjects' bounds into the viewport with MARGIN_PX
## and casts camera rays at them (trimesh colliders on every mesh) before it is
## saved; on failure it prints PROBE_INVALID and exits 1. Numbers printed per
## parked plane: the plane's height and the ground there, the bridge root's
## height, the gap from the bridge's Mount_Door to the plane door, and what a
## ray straight down meets under the nose, tail, wing tips and door (the plane
## itself excluded).

const IntroClose := preload("res://spike/intro_close.gd")
const MAIN := "res://main/main.tscn"
const OUT_REL := "res://../tools/blender/out/s8a_side_stands"
const MARGIN_PX := 8.0
const MIN_SHARE := 0.25
const PLAY_PITCH_DEG := 54.0
const PLAY_FOV := 55.0
const PLAY_DISTANCE := 80.0
const CLOSE_PITCH_DEG := 38.0
const CLOSE_DISTANCE := 30.0
const SHEET_TILE := Vector2i(480, 270)
## ReferenceTerminal cells: the east and west exits and the west gate desk.
const EAST_EXIT := Vector2i(21, 4)
const WEST_EXIT := Vector2i(10, 8)
const WEST_DESK := Vector2i(12, 7)
const MODELS: Array[String] = ["tp_plane_05a", "tp_plane_04a", "tp_plane_03a"]
## The mixed layout's north stand: its lane join 14 m inside the west spur.
const NEAR_SPUR_JOIN_X := -110.0
const NEAR_SPUR_WALL_Z := -200.0
## The moved west spur.
const MOVED_LANE_X := -160.0
## Sol's review layout: a west stand whose connector crosses the near link.
const CROSS_SILL := Vector2(-33.0, -193.5)

var _out_dir := ""
## A prefix for every plate name (--tag=NAME), so a before and an after run
## keep their plates apart.
var _tag := ""
var _failed := false
var _main: Node
var _clock: SimClock
var _cam: Camera3D
var _view: PlaneView
var _airside: Airside
var _gates: GateDesks
var _grid: BuildGrid
var _plates: Array[String] = []


func _initialize() -> void:
	var world_seed := IntroClose.seed_or_random()
	print("PROBE world_seed=%d" % world_seed)
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tag="):
			_tag = arg.trim_prefix("--tag=") + "_"
	print("PROBE out_dir=%s tag=%s" % [_out_dir, _tag])
	DisplayServer.window_set_size(Vector2i(1600, 900))
	_main = load(MAIN).instantiate()
	_clock = _main.get_node("SimClock")
	_clock.seed_rng(world_seed)
	root.add_child(_main)
	current_scene = _main
	_clock.set_paused(true)
	_run.call_deferred()


func _run() -> void:
	await _frames(3)
	_grid = (_main.get_node("BuildMode") as BuildMode).grid
	_gates = _main.get_node("GateDesks")
	_airside = _main.get_node("Airside")
	_view = _main.get_node("PlaneView")
	var problem := IntroClose.close(_main)
	if problem != "":
		_invalid(problem)
		_finish()
		return
	_clock.set_paused(true)
	for fleet in _main.find_children("*", "PlaneFleet", true, false):
		fleet.set_process(false)
	_view.set_process(false)
	(_main.get_node("PlaneView2") as Node).set_process(false)
	if not _build_gates():
		_finish()
		return
	await _frames(4)
	_show_hud(false)
	(_main.get_node("TycoonCamera") as Node).set_process(false)
	_cam = Camera3D.new()
	_cam.fov = PLAY_FOV
	_cam.far = 3000.0
	_main.add_child(_cam)
	_cam.make_current()
	_add_colliders(_main)
	var real: Dictionary = _airside.gate_stands.duplicate(true)
	print("PROBE gates %s stands %s" % [_gates.bindings, real])
	var stages: Array[Callable] = [
		_side_plates.bind("B", real["B"]),
		_side_plates.bind("A", real["A"]),
		_outline_plate.bind(real),
		_north_plates,
		_mixed_plates.bind(real["B"]),
		_moved_plates.bind(real["B"]),
		_cross_plates,
	]
	for stage in stages:
		if not await stage.call():
			_finish()
			return
	_contact_sheet()
	_finish()


## Opens the east and west exits, fills the starter terminal (its gate desk
## links east, gate A) and places the west desk (gate B).
func _build_gates() -> bool:
	var at := ReferenceTerminal.offset_on(_grid)
	var edits: Array[BuildEdit] = [
		BuildEdit.remove_wall(EAST_EXIT + at, BuildGrid.Side.EAST),
		BuildEdit.place_object(&"exit_door", EAST_EXIT + at, 1),
		BuildEdit.remove_wall(WEST_EXIT + at, BuildGrid.Side.WEST),
		BuildEdit.place_object(&"exit_door", WEST_EXIT + at, 3),
	]
	for result in _grid.apply_batch(edits):
		if not result.ok:
			_invalid("a side exit was refused: %s" % result.reason_text())
			return false
	(_main.get_node("PassengerHud") as PassengerHud).press_starter_terminal()
	var desk := _grid.apply(BuildEdit.place_object(GateDesks.DESK, WEST_DESK + at, 0))
	if not desk.ok:
		_invalid("the west gate desk was refused: %s" % desk.reason_text())
		return false
	var sides := {}
	for gate: String in _airside.gate_stands:
		sides[gate] = StandPlacement.side_of(_airside.gate_stands[gate])
	print("PROBE sides %s" % [sides])
	if sides != {"A": StandPlacement.EAST, "B": StandPlacement.WEST}:
		_invalid("expected gate A east and gate B west, got %s" % [sides])
		return false
	return true


## Plates of gate `gate` (stand `stand`) with each of MODELS parked.
func _side_plates(gate: String, stand: Dictionary) -> bool:
	var side := StandPlacement.side_of(stand)
	for model in MODELS:
		var plane := await _park(gate, model)
		var bridge: Node3D = _airside.props.bridges[gate]["node"]
		_report_parked(gate, stand, model, plane)
		var door: Vector3 = JetBridgePose.plane_door(stand, model)["door"]
		var shots := [["close", CLOSE_PITCH_DEG, CLOSE_DISTANCE]]
		if model == MODELS[0]:
			shots.append(["play", PLAY_PITCH_DEG, PLAY_DISTANCE])
		for shot: Array in shots:
			_aim_at_stand(stand, door, shot[1], shot[2])
			await _frames(3)
			var label := "%s_%s_%s" % [side, shot[0], model.trim_prefix("tp_plane_")]
			var whole: Array = [plane, bridge] if shot[0] == "play" else [bridge]
			# Close up the bridge must be whole in frame and the plane seen.
			if not _prove(label, whole):
				return false
			if _rays(label, plane) < MIN_SHARE:
				_invalid("%s: the plane is occluded" % label)
				return false
			await _save(label + ".png")
	_view.visible = false
	_view._follow_props()
	return true


## Both gates' envelope outlines and captions in build mode: the whole of both
## outlines from above, then the captions and the stands' door ends close.
func _outline_plate(stands: Dictionary) -> bool:
	var apron: ApronStand = _main.get_node("ApronStand")
	apron.set_building(true)
	await _frames(4)
	var links := apron.links_view()
	var outline: Array[Vector3] = []
	for path in links.envelope_paths():
		outline.append_array(Array(path))
	var near: Array[Vector3] = []
	for caption in links.gate_captions():
		near.append(caption.global_position)
	print("PROBE outlines %d captions %d" % [links.envelope_paths().size(), near.size()])
	if links.envelope_paths().size() != 2 or near.size() != 2:
		_invalid("expected two outlines and two captions")
		return false
	var box := AABB(outline[0], Vector3.ZERO)
	for p in outline:
		box = box.expand(p)
	var distance := maxf(box.size.x / 2.0 / 0.92, box.size.z / 2.0 / 0.52) * 1.15
	_aim(box.get_center(), 0.0, 89.0, distance)
	await _frames(3)
	if not _points_in_frame("outlines_top", outline):
		return false
	await _save("WE_build_outlines_top.png")
	for gate: String in stands:
		near.append(StandPlacement.door_point(stands[gate]))
	var centre := Vector3.ZERO
	for p in near:
		centre += p / near.size()
	_aim(centre, 0.0, PLAY_PITCH_DEG, PLAY_DISTANCE)
	await _frames(3)
	if not _points_in_frame("outlines_play", near):
		return false
	await _save("WE_build_outlines_play.png")
	apron.set_building(false)
	await _frames(2)
	return true


## The starter's north exit stand alone as gate A, with each model parked.
func _north_plates() -> bool:
	var north: Dictionary = {}
	for id in _grid.object_ids():
		var stand := StandPlacement.for_exit(_grid, id)
		if not stand.is_empty() and StandPlacement.side_of(stand) == StandPlacement.NORTH:
			north = stand
	if north.is_empty():
		_invalid("the starter shell has no north exit stand")
		return false
	if not await _set_stands({"A": north}):
		return false
	return await _side_plates("A", north)


## A north stand whose join is 14 m from the west spur, beside the west gate.
func _mixed_plates(west: Dictionary) -> bool:
	var door_x := NEAR_SPUR_JOIN_X + StandPlacement.DOOR_SIDE_M
	var near := StandPlacement.make(900, door_x, NEAR_SPUR_WALL_Z)
	if not await _set_stands({"A": near, "B": west}):
		return false
	var join := StandPlacement.lane_join(near)
	var spur_x := StandPlacement.lane_x_of(west)
	var corner := Vector3((join.x + spur_x) / 2.0, 0.0, StandPlacement.TAXI_LANE_Z + 8.0)
	print("PROBE mixed join %s spur_x %.2f" % [join, spur_x])
	return await _paving_plates("mixed", corner, _square(join))


## The west gate's stand on a spur moved out to MOVED_LANE_X.
func _moved_plates(west: Dictionary) -> bool:
	var moved := StandPlacement.with_lane_x(west, MOVED_LANE_X)
	if not await _set_stands({"B": moved}):
		return false
	var stub := Vector3(-StandPlacement.SIDE_LANE_X, 0.0, StandPlacement.TAXI_LANE_Z)
	print("PROBE moved lane_x %.2f stub %s" % [StandPlacement.lane_x_of(moved), stub])
	return await _paving_plates("moved", stub, _square(stub))


## Sol's review layout: the near-spur north stand beside a west stand whose
## connector crosses the north link's run-on to its wall line (z -200), so the
## two strips share [-109, -95] x [-205, -200].
func _cross_plates() -> bool:
	var door_x := NEAR_SPUR_JOIN_X + StandPlacement.DOOR_SIDE_M
	var near := StandPlacement.make(900, door_x, NEAR_SPUR_WALL_Z)
	var west := StandPlacement.make(901, CROSS_SILL.x, CROSS_SILL.y, StandPlacement.WEST)
	if not await _set_stands({"A": near, "B": west}):
		return false
	var shared := Rect2(-108.5, -204.5, 13.0, 4.0)
	var points: Array[Vector3] = [Vector3(shared.get_center().x, 0.0, shared.get_center().y)]
	for corner in [shared.position, shared.end, Vector2(shared.position.x, shared.end.y)]:
		points.append(Vector3(corner.x, 0.0, corner.y))
	print("PROBE cross shared ground %s" % shared)
	return await _paving_plates("cross", points[0], points)


## A top-down and a play-angle plate centred on `focus`, proving the points
## `square` in frame and the paving the first thing camera rays meet there.
func _paving_plates(label: String, focus: Vector3, square: Array[Vector3]) -> bool:
	_add_colliders(_airside.paving)
	for shot: Array in [["top", 89.0, 90.0, 0.0], ["play", PLAY_PITCH_DEG, PLAY_DISTANCE, 200.0]]:
		_aim(focus, shot[3], shot[1], shot[2])
		await _frames(3)
		var name := "%s_%s" % [label, shot[0]]
		if not _points_in_frame(name, square):
			return false
		if not _paving_seen(name, square):
			return false
		await _save(name + ".png")
	return true


## The centre and corners of the WIDTH_M square of lane around `at`, the
## corners 1 m inside its edges.
func _square(at: Vector3) -> Array[Vector3]:
	var half := TaxiPaving.WIDTH_M / 2.0 - 1.0
	var c := Vector3(at.x, 0.0, StandPlacement.TAXI_LANE_Z)
	return [
		c,
		c + Vector3(-half, 0.0, -half),
		c + Vector3(half, 0.0, -half),
		c + Vector3(half, 0.0, half),
		c + Vector3(-half, 0.0, half),
	]


## Gives Airside `stands` and checks they are still set a few frames later.
func _set_stands(stands: Dictionary) -> bool:
	_airside.set_gate_stands(stands)
	_airside.set_gate_classes({})
	await _frames(4)
	if _airside.gate_stands != stands:
		_invalid("Airside's stands were reset to %s" % [_airside.gate_stands])
		return false
	_add_colliders(_airside)
	return true


## Parks `model` at gate `gate`'s stand with the main PlaneView, as update_pose()
## does for a plane at the stand, and lets the bridge dock. Returns the model.
func _park(gate: String, model: String) -> Node3D:
	var plane_class := _class_of(model)
	_view.gate = gate
	_view.show_model(model)
	var path := _view._path(FlightSim.State.PUSHBACK, plane_class)
	var entry := _view._entry_dir(FlightSim.State.PUSHBACK, plane_class)
	var pose := FlightPose.pose(FlightSim.State.PUSHBACK, 0.0, path, entry)
	pose.origin.y += PlaneView.ground_height_at(pose.origin)
	_view.transform = pose
	_view.phase = FlightSim.State.BOARDING
	_view.visible = true
	_view.flight_id = "probe"
	_view._set_model_position(_view.model_position_at(_view.phase, pose, plane_class))
	_view._follow_props()
	await _frames(3)
	var node: Node3D = _view.get_node("Pivot").get_child(0)
	_add_colliders(node)
	# The bridge shows or hides its walkway with the model: colliders again.
	_add_colliders(_airside.props.bridges[gate]["node"])
	return node


## Prints the parked plane's numbers (see the header).
func _report_parked(gate: String, stand: Dictionary, model: String, plane: Node3D) -> void:
	var entry: Dictionary = _airside.props.bridges[gate]
	var ground := JetBridgePose.ground_y(stand)
	var root: Transform3D = entry["root"]
	var at := JetBridgePose.pose_for(stand, model, entry["docked"], root.origin.y)
	var gap := -1.0
	if entry["docked"]:
		gap = (at["mounts"][&"Mount_Door"] as Vector3).distance_to(at["door"])
	print(
		(
			"PARKED %s %s %s plane_y=%.3f ground=%.3f root_y=%.3f docked=%s folded=%s door_gap=%.3f"
			% [
				gate,
				StandPlacement.side_of(stand),
				model,
				_view.global_position.y,
				ground,
				root.origin.y,
				entry["docked"],
				entry["folded"],
				gap
			]
		)
	)
	var box := _aabb_of(plane)
	var c := box.get_center()
	var probes := {
		"door": at["door"],
		"min_x": Vector3(box.position.x + 0.5, 0.0, c.z),
		"max_x": Vector3(box.end.x - 0.5, 0.0, c.z),
		"min_z": Vector3(c.x, 0.0, box.position.z + 0.5),
		"max_z": Vector3(c.x, 0.0, box.end.z - 0.5),
	}
	var exclude: Array[RID] = []
	for body in plane.find_children("*", "StaticBody3D", true, false):
		exclude.append((body as StaticBody3D).get_rid())
	var space := _cam.get_world_3d().direct_space_state
	var under := []
	for key: String in probes:
		var p: Vector3 = probes[key]
		var q := PhysicsRayQueryParameters3D.create(
			Vector3(p.x, 40.0, p.z), Vector3(p.x, -5.0, p.z)
		)
		q.exclude = exclude
		var hit := space.intersect_ray(q)
		var what := "nothing"
		if hit:
			what = "%s@%.3f" % [_owner_name(hit.collider), (hit.position as Vector3).y]
		under.append("%s=%s" % [key, what])
	print("UNDER %s %s %s" % [gate, model, " ".join(under)])
	print(
		(
			"PAVED %s %s %s"
			% [
				gate,
				model,
				TaxiPaving.paved(
					_airside.paving.shown, _airside.paving.pads, StandPlacement.stand_point(stand)
				)
			]
		)
	)


## The name of the nearest ancestor of `node` that is not a collision node.
func _owner_name(node: Node) -> String:
	var at := node
	while at != null and (at is StaticBody3D or at is CollisionShape3D):
		at = at.get_parent()
	return String(at.name) if at != null else "?"


## Aims the camera at `focus` from the apron side of `stand`: in its north
## twin's frame from the north-east (the door side), turned with the stand.
func _aim_at_stand(stand: Dictionary, focus: Vector3, pitch: float, distance: float) -> void:
	var p := deg_to_rad(pitch)
	var yaw := deg_to_rad(150.0)
	var back := Vector3(sin(yaw) * cos(p), 0.0, cos(yaw) * cos(p))
	back = StandPlacement.turn(stand, back)
	back.y = sin(p)
	_cam.look_at_from_position(focus + back * distance, focus, Vector3.UP)


## Puts the camera `distance` from `focus`, `pitch` degrees above it, looking at
## it from yaw `yaw` (0: from the south, looking north).
func _aim(focus: Vector3, yaw: float, pitch: float, distance: float) -> void:
	var y := deg_to_rad(yaw)
	var p := deg_to_rad(pitch)
	var back := Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p))
	var up := Vector3.UP if pitch < 85.0 else Vector3(0.0, 0.0, -1.0)
	_cam.look_at_from_position(focus + back * distance, focus, up)


## Proves each subject's bounds lie in the viewport with MARGIN_PX and that
## camera rays reach it first.
func _prove(label: String, subjects: Array) -> bool:
	var rect := Rect2(Vector2.ZERO, root.get_visible_rect().size).grow(-MARGIN_PX)
	for subject: Node3D in subjects:
		if not subject.is_visible_in_tree() or _visible_meshes(subject).is_empty():
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
		if _rays(label, subject) < MIN_SHARE:
			_invalid("%s: %s is occluded" % [label, subject.name])
			return false
	return true


## Proves every point of `points` projects inside the viewport with MARGIN_PX.
func _points_in_frame(label: String, points: Array[Vector3]) -> bool:
	var rect := Rect2(Vector2.ZERO, root.get_visible_rect().size).grow(-MARGIN_PX)
	if points.is_empty():
		_invalid("%s: nothing to frame" % label)
		return false
	for p in points:
		var s := _cam.unproject_position(p)
		var ok := not _cam.is_position_behind(p) and rect.has_point(s)
		print("INFRAME %s %s screen=(%.0f,%.0f) ok=%s" % [label, p, s.x, s.y, ok])
		if not ok:
			_invalid("%s: %s leaves the viewport" % [label, p])
			return false
	return true


## Proves a camera ray to each of `points` meets the taxi paving first.
func _paving_seen(label: String, points: Array[Vector3]) -> bool:
	var space := _cam.get_world_3d().direct_space_state
	var hits := 0
	for p in points:
		var to := p + (p - _cam.global_position).normalized() * 0.5
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(_cam.global_position, to))
		var what: String = _owner_name(hit.collider) if hit else "nothing"
		print("VISIBLE %s %s first=%s" % [label, p, what])
		hits += int(what == "TaxiPaving")
	if hits < points.size():
		var hidden := points.size() - hits
		_invalid("%s: the paving is hidden at %d of %d points" % [label, hidden, points.size()])
		return false
	return true


## Casts rays from the camera at sampled surface points of `subject` and
## prints the share that reach it first.
func _rays(label: String, subject: Node3D) -> float:
	var targets: Array[Vector3] = []
	var centre := _aabb_of(subject).get_center()
	for mi in _visible_meshes(subject):
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
	var seen := "ray_hits=%d/%d share=%.2f" % [hits, targets.size(), share]
	print("VISIBLE %s %s %s" % [label, subject.name, seen])
	return share


func _class_of(model: String) -> String:
	for plane_class: String in PlaneClasses.CLASSES:
		if PlaneClasses.CLASSES[plane_class]["models"].has(model):
			return plane_class
	return PlaneClasses.MEDIUM


func _save(name: String) -> void:
	await _frames(2)
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	var path := _out_dir.path_join(_tag + name)
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
	var path := _out_dir.path_join(_tag + "contact_sheet.png")
	sheet.save_png(path)
	print("PLATE saved %s" % path)


func _show_hud(on: bool) -> void:
	for layer in _main.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = on


## Gives every shown mesh under `node` a trimesh collider, replacing an old one.
func _add_colliders(node: Node) -> void:
	for mi in _meshes(node):
		for body in mi.find_children("*", "StaticBody3D", false, false):
			mi.remove_child(body)
			body.free()
		# A hidden mesh (an unowned plot's paving) must not stop a ray.
		var shown := mi.is_visible_in_tree()
		if shown and mi.mesh != null and mi.mesh.get_surface_count() > 0:
			mi.create_trimesh_collision()


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node)
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		out.append(mi)
	return out


func _visible_meshes(node: Node) -> Array[MeshInstance3D]:
	return _meshes(node).filter(func(mi: MeshInstance3D) -> bool: return mi.is_visible_in_tree())


func _aabb_of(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in _visible_meshes(node):
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _finish() -> void:
	print("PROBE done failed=%s plates=%d" % [_failed, _plates.size()])
	quit(1 if _failed else 0)
