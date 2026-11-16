extends SceneTree
## Windowed plate probe for the folded jet bridge (board b564cda3; ruling
## small-planes-the-jet-bridge-folds-back-against-the-terminal, v2 "Lower the
## folded box"): plane 03 at the north gate with the bridge folded to the
## vestibule's ground floor, close up, at play distance and at its apron door;
## the empty gate folded; plane 04 docked at the same gate, to show the docking
## bridge is unchanged; and plane 03 at a west gate, close up. It rules
## nothing.
##
## Run (one windowed Godot run project-wide; hold tools/blender/out/.windowed.lock):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path <worktree>/game -s res://spike/bridge_fold_plates_probe.gd
##
## Boots main.tscn with the starter shell and a gate desk (StarterFlight), so
## the real ApronStand gives gate A its stand. For the west plate the probe
## moves gate A to a west stand on the reference terminal's west wall (cells
## from ReferenceTerminal.FLOOR_MIN and AIRSIDE_MAX_Y plus offset_on(), never
## fixed cells). No flight runs: the clock, the fleets and the PlaneView stop
## processing, and the probe poses the view as update_pose() does, then lets
## it report its plane to the bridge (_follow_props()). Every plate projects
## its subjects' bounds into the viewport with MARGIN_PX and casts camera rays
## at them (trimesh colliders on every visible mesh, rebuilt after every fold
## change) before it is saved; on failure it prints PROBE_INVALID and exits 1.
## The HUD is hidden. Prints the world seed. The contact sheet is drawn as a
## labelled grid on the window and captured.

const StarterFlight := preload("res://spike/starter_flight.gd")
const MAIN_SCENE := "res://main/main.tscn"
const OUT_REL := "res://../tools/blender/out/bridge-fold"
const MARGIN_PX := 8.0
const SMALL := "tp_plane_03a"
const DOCKER := "tp_plane_04a"
## The play camera (TycoonCamera): the medium angle step, its lens, its home
## distance.
const PLAY_PITCH_DEG := 54.0
const PLAY_FOV := 55.0
const PLAY_DISTANCE := 80.0
const PLAY_YAW := 30.0
## Close views: yaw, pitch, distance; from the north-west, the planes' side, so
## the plane stands in front of the bridge.
const CLOSE := Vector3(210.0, 32.0, 20.0)
## The apron door view: yaw, pitch, distance.
const APRON_VIEW := Vector3(235.0, 24.0, 12.0)
## The west gate view: from the south-west, out over the west apron.
const WEST_VIEW := Vector3(300.0, 30.0, 20.0)
const SHEET_TILE := Vector2i(480, 270)
const SHEET_COLS := 3

var _out_dir := ""
var _failed := false
var _main: Node
var _cam: Camera3D
var _view: PlaneView
var _airside: Airside
var _gate := ""
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
		_finish_invalid("the gate desk was refused")
		return
	await _frames(6)
	if _airside.gate_stands.is_empty():
		_finish_invalid("no gate got a stand")
		return
	_gate = _airside.gate_stands.keys()[0]
	_show_hud(false)
	_cam = Camera3D.new()
	_cam.fov = PLAY_FOV
	_cam.far = 2000.0
	_main.add_child(_cam)
	_cam.make_current()
	_view.gate = _gate
	var a: Dictionary = _airside.props.bridges[_gate]
	var small := _pose(SMALL)
	await _frames(3)
	print(
		(
			"PROBE gate %s stand %s: model %s folded %s docked %s"
			% [_gate, a["stand"], a["model"], a["folded"], a["docked"]]
		)
	)
	if not a["folded"] or a["docked"]:
		_finish_invalid("the bridge is not folded at the 03")
		return
	await _refresh_colliders()
	await _small_plates(a, small)
	await _empty_plate(a)
	await _docked_plate(a)
	await _west_plate()
	await _contact_sheet()
	_finish()


## The 03 at the north gate: close, play distance and its apron door.
func _small_plates(a: Dictionary, small: Node3D) -> void:
	var bridge: Node3D = a["node"]
	var focus := _focus(bridge, small, SMALL)
	_aim(focus, CLOSE.x, CLOSE.y, CLOSE.z)
	await _frames(3)
	var name := "fold_03_after_close.png"
	if _prove(name, [bridge], true) and _prove_seen(name, small):
		await _save(name)
	_aim(focus, PLAY_YAW, PLAY_PITCH_DEG, PLAY_DISTANCE)
	await _frames(3)
	name = "fold_03_after_play.png"
	if _prove(name, [bridge, small], true):
		await _save(name)
	var door := (bridge.find_child("Mount_ApronDoor", true, false) as Node3D).global_position
	_aim(door + Vector3.UP * 1.1, APRON_VIEW.x, APRON_VIEW.y, APRON_VIEW.z)
	await _frames(3)
	name = "fold_03_apron_door_close.png"
	if _prove(name, [bridge], true) and _prove_seen(name, small):
		await _save(name)


## The gate empty: the 03 withdrawn (its view hidden, so it stops reporting).
func _empty_plate(a: Dictionary) -> void:
	_view.visible = false
	_view._follow_props()
	await _frames(3)
	print("PROBE empty gate %s: model '%s' folded %s" % [_gate, a["model"], a["folded"]])
	if not a["folded"] or a["model"] != "":
		_invalid("the empty gate did not fold")
		return
	await _refresh_colliders()
	var bridge: Node3D = a["node"]
	_aim(bridge.global_position + bridge.global_basis.z * 4.0, CLOSE.x, CLOSE.y, CLOSE.z)
	await _frames(3)
	var name := "fold_empty_folded_close.png"
	if _prove(name, [bridge], true):
		await _save(name)


## A 04 at the same gate, docked, with the camera of the 03 close plate.
func _docked_plate(a: Dictionary) -> void:
	var docker := _pose(DOCKER)
	await _frames(3)
	print(
		(
			"PROBE gate %s: model %s folded %s docked %s"
			% [_gate, a["model"], a["folded"], a["docked"]]
		)
	)
	if a["folded"] or not a["docked"]:
		_invalid("the 04 at gate %s did not unfold and dock" % _gate)
		return
	await _refresh_colliders()
	var bridge: Node3D = a["node"]
	_aim(_focus(bridge, docker, DOCKER), CLOSE.x, CLOSE.y, CLOSE.z + 8.0)
	await _frames(3)
	var name := "fold_04_docked_gate_a_close.png"
	if _prove(name, [bridge], true) and _prove_seen(name, docker):
		await _save(name)


## Gate A moved to a west stand on the reference terminal's west wall, a 03
## parked there: the bridge folded, close up.
func _west_plate() -> void:
	var grid := (_main.get_node("BuildMode") as BuildMode).grid
	var cell := (
		ReferenceTerminal.offset_on(grid)
		+ Vector2i(
			ReferenceTerminal.FLOOR_MIN.x,
			roundi((ReferenceTerminal.FLOOR_MIN.y + ReferenceTerminal.AIRSIDE_MAX_Y) / 2.0)
		)
	)
	var stand := StandPlacement.for_cell(grid, cell, 900, StandPlacement.WEST)
	var ok := _airside.set_gate_stands({_gate: stand})
	await _frames(6)
	var a: Dictionary = _airside.props.bridges.get(_gate, {})
	print("PROBE west cell %s stand %s ok %s" % [cell, stand, ok])
	if not ok or a.is_empty() or StandPlacement.side_of(a["stand"]) != StandPlacement.WEST:
		_invalid("gate %s did not take the west stand" % _gate)
		return
	var small := _pose(SMALL)
	await _frames(3)
	print("PROBE west gate: model %s folded %s docked %s" % [a["model"], a["folded"], a["docked"]])
	if not a["folded"] or a["docked"]:
		_invalid("the bridge is not folded at the west 03")
		return
	await _refresh_colliders()
	var bridge: Node3D = a["node"]
	_aim(_focus(bridge, small, SMALL), WEST_VIEW.x, WEST_VIEW.y, WEST_VIEW.z)
	await _frames(3)
	var name := "fold_03_west_gate_close.png"
	if _prove(name, [bridge], true) and _prove_seen(name, small):
		await _save(name)


func _finish() -> void:
	print("PROBE done failed=%s plates=%d" % [_failed, _plates.size()])
	quit(1 if _failed else 0)


func _finish_invalid(msg: String) -> void:
	_invalid(msg)
	_finish()


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw


## Poses the view with `model` parked at its gate's stand in BOARDING, as
## update_pose() does, and lets it report to the bridge. Returns the model.
func _pose(model: String) -> Node3D:
	var cls := _class_of(model)
	_view.show_model(model)
	var path := _view._path(FlightSim.State.PUSHBACK, cls)
	var entry := _view._entry_dir(FlightSim.State.PUSHBACK, cls)
	var pose := FlightPose.pose(FlightSim.State.PUSHBACK, 0.0, path, entry)
	pose.origin.y += PlaneView.ground_height_at(pose.origin)
	_view.transform = pose
	_view.phase = FlightSim.State.BOARDING
	_view.visible = true
	_view.flight_id = "probe"
	_view._set_model_position(_view.model_position_at(FlightSim.State.BOARDING, pose, cls))
	_view._follow_props()
	return _view.get_node("Pivot").get_child(0)


func _class_of(model: String) -> String:
	for cls: String in PlaneClasses.CLASSES:
		if PlaneClasses.CLASSES[cls]["models"].has(model):
			return cls
	return PlaneClasses.MEDIUM


## Halfway between the plane's front door and the bridge's root, a little up.
func _focus(bridge: Node3D, plane: Node3D, model: String) -> Vector3:
	var door: Vector3 = plane.global_transform * PlaneModels.PLANES[model]["doors"][0]
	return door.lerp(bridge.global_position, 0.5) + Vector3.UP


## Puts the camera `distance` from `focus`, `pitch` degrees above it, looking
## at it from yaw `yaw` (0: from the south, looking north).
func _aim(focus: Vector3, yaw: float, pitch: float, distance: float) -> void:
	var y := deg_to_rad(yaw)
	var p := deg_to_rad(pitch)
	var back := Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p))
	_cam.look_at_from_position(focus + back * distance, focus, Vector3.UP)


## Proves every subject's visible bounds lie in the viewport with MARGIN_PX
## and, when `need_rays`, that camera rays reach it first. A hidden subject,
## or one with no visible mesh, fails.
func _prove(label: String, subjects: Array, need_rays: bool) -> bool:
	var rect := Rect2(Vector2.ZERO, root.get_visible_rect().size).grow(-MARGIN_PX)
	for subject: Node3D in subjects:
		if not subject.is_visible_in_tree() or _visible(subject).is_empty():
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


## Casts rays from the camera at sampled surface points of `subject`'s visible
## meshes and prints the share that hit it first.
func _report_rays(label: String, subject: Node3D) -> float:
	var targets: Array[Vector3] = []
	var centre := _aabb_of(subject).get_center()
	for mi in _visible(subject):
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


## Draws every plate as a labelled tile on a CanvasLayer over the window,
## captures it and saves contact_sheet.png.
func _contact_sheet() -> void:
	if _plates.is_empty():
		return
	var layer := CanvasLayer.new()
	layer.layer = 100
	var back := ColorRect.new()
	back.color = Color(0.12, 0.12, 0.12)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(back)
	var grid := GridContainer.new()
	grid.columns = SHEET_COLS
	grid.position = Vector2(8, 8)
	layer.add_child(grid)
	for path in _plates:
		var tile := VBoxContainer.new()
		var label := Label.new()
		label.text = path.get_file()
		label.add_theme_font_size_override("font_size", 16)
		tile.add_child(label)
		var img := Image.load_from_file(path)
		img.resize(SHEET_TILE.x, SHEET_TILE.y)
		var rect := TextureRect.new()
		rect.texture = ImageTexture.create_from_image(img)
		rect.custom_minimum_size = Vector2(SHEET_TILE)
		tile.add_child(rect)
		grid.add_child(tile)
	root.add_child(layer)
	await _frames(4)
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	var used := grid.get_rect().grow(8.0)
	var sheet := img.get_region(Rect2i(Vector2i.ZERO, Vector2i(used.end)))
	var path := _out_dir.path_join("contact_sheet.png")
	sheet.save_png(path)
	print("PLATE saved %s" % path)
	layer.queue_free()


func _show_hud(on: bool) -> void:
	for layer in _main.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = on


## Rebuilds the trimesh colliders under the whole scene so that only visible
## meshes have one: a hidden walkway must neither occlude nor be hit.
func _refresh_colliders() -> void:
	for body in _main.find_children("*", "StaticBody3D", true, false):
		if body.has_meta(&"probe_col"):
			body.free()
	for mi in _visible(_main):
		mi.create_trimesh_collision()
		for body in mi.get_children():
			if body is StaticBody3D:
				body.set_meta(&"probe_col", true)
	await _frames(3)


## The MeshInstance3Ds at or under `node` that are on show and have a mesh.
func _visible(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var found := node.find_children("*", "MeshInstance3D", true, false)
	if node is MeshInstance3D:
		found.append(node)
	for mi: MeshInstance3D in found:
		if mi.is_visible_in_tree() and mi.mesh != null:
			out.append(mi)
	return out


func _aabb_of(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in _visible(node):
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box
