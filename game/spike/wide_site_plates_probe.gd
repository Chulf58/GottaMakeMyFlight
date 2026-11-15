extends SceneTree
## Windowed plate probe for the wide site grid (board a91c3969, decision land-
## west-and-east-of-the-site-becomes-buyable-that-side-s-t): a new game from
## above in the owned-paving probe's framing (the look must be unchanged), the
## same after a locked side plot is refused (SiteDefinition.SIDE_LAND_OPEN) and
## two first-site plots are bought, a close-up of the start land's west edge
## at x -43 against the locked side land, and a distance shot of the whole 256 m
## frame. It rules nothing.
##
## Run (one windowed Godot run project-wide):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path <worktree>/game -s res://spike/wide_site_plates_probe.gd
##
## Boots main.tscn with the starter shell and a gate desk (StarterFlight). No
## flight runs. Every plate projects its subject points into the viewport with
## MARGIN_PX and casts camera rays at its targets (trimesh colliders on every
## shown mesh) before it is saved; on failure it prints PROBE_INVALID and exits
## 1. Prints the world seed.

const StarterFlight := preload("res://spike/starter_flight.gd")
const MAIN_SCENE := "res://main/main.tscn"
const OUT_REL := "res://../tools/blender/out/wide-site"
const MARGIN_PX := 8.0
## Side land beside the start land; refused while side land is locked.
const LOCKED_PLOT := Vector2i(3, 4)
## First-site plots bought: one north of the start land and one east of it.
const BUY: Array[Vector2i] = [Vector2i(4, 2), Vector2i(6, 4)]

var _out_dir := ""
var _main: Node
var _cam: Camera3D
var _mode: BuildMode
var _land: LandPlots
var _site: Node3D
var _origin := Vector3.ZERO
var _failed := false
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
	(_main.get_node("PlaneView") as Node).set_process(false)
	(_main.get_node("PlaneView2") as Node).set_process(false)
	_mode = _main.get_node("BuildMode")
	_land = _mode.land_tool.land
	_site = _main.get_node("Airside/Terminal")
	_origin = _mode.grid.origin
	await _frames(6)
	if not StarterFlight.add_gate_desk(_mode.grid):
		_end("the gate desk was refused")
		return
	await _frames(6)
	_show_hud(false)
	_cam = Camera3D.new()
	_cam.fov = 55.0
	_cam.far = 3000.0
	_main.add_child(_cam)
	_cam.make_current()
	_add_colliders(_main)
	await _frames(4)
	print("PROBE grid size=%s origin=%s owned=%s" % [_mode.grid.size, _origin, _land.owned_plots()])
	await _top_plate("01_new_game_top.png", Vector3(0, 0, -135), 190.0, _land.owned_plots())
	var locked := _land.buy(LOCKED_PLOT, null)
	print("PROBE side plot %s refused=%s reason=%s" % [LOCKED_PLOT, not locked.ok, locked.reason])
	if locked.ok or locked.reason != BuildResult.Reason.LOCKED:
		_end("the locked side plot %s was not refused as locked" % LOCKED_PLOT)
		return
	for plot in BUY:
		var result := _land.buy(plot, null)
		print("PROBE bought %s ok=%s" % [plot, result.ok])
		if not result.ok:
			_end("buying %s was refused" % plot)
			return
	_add_colliders(_main)
	await _frames(4)
	await _top_plate("02_first_site_plots_bought_top.png", Vector3(0, 0, -135), 190.0, BUY)
	await _join_plate("03_west_edge_locked.png", Vector3(-43.0, 0.2, -97.0), Vector2i(4, 4))
	await _distance_plate()
	_end("")


func _end(why: String) -> void:
	if why != "":
		_invalid(why)
	print("PROBE done failed=%s plates=%d" % [_failed, _plates.size()])
	quit(1 if _failed else 0)


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw


func _aim(focus: Vector3, yaw: float, pitch: float, distance: float) -> void:
	var y := deg_to_rad(yaw)
	var p := deg_to_rad(pitch)
	var back := Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p))
	_cam.look_at_from_position(focus + back * distance, focus, Vector3.UP)


## A point 2 m inside the south-west corner of `plot`, on the paving.
func _inside(plot: Vector2i) -> Vector3:
	var cells := _land.plot_cells(plot)
	return Vector3(_origin.x + cells.position.x + 2.0, 0.2, _origin.z + cells.end.y - 2.0)


## Proves `points` lie in the viewport with MARGIN_PX and that a camera ray at
## each of `targets` hits `subject` (or a node under it) first.
func _prove(label: String, points: Array[Vector3], subject: Node, targets: Array[Vector3]) -> bool:
	var rect := Rect2(Vector2.ZERO, root.get_visible_rect().size).grow(-MARGIN_PX)
	for p in points:
		if _cam.is_position_behind(p):
			_invalid("%s: %s is behind the camera" % [label, p])
			return false
		var s := _cam.unproject_position(p)
		print("INFRAME %s %s screen=(%.0f,%.0f) ok=%s" % [label, p, s.x, s.y, rect.has_point(s)])
		if not rect.has_point(s):
			_invalid("%s: %s leaves the viewport" % [label, p])
			return false
	var space := _cam.get_world_3d().direct_space_state
	for t in targets:
		var q := PhysicsRayQueryParameters3D.create(
			_cam.global_position, t + (t - _cam.global_position).normalized() * 0.05
		)
		var hit := space.intersect_ray(q)
		var ok: bool = (
			not hit.is_empty() and (hit.collider == subject or subject.is_ancestor_of(hit.collider))
		)
		var name: String = hit.collider.get_parent().name if hit else "-"
		print("VISIBLE %s %s hit=%s ok=%s" % [label, t, name, ok])
		if not ok:
			_invalid("%s: %s is occluded" % [label, t])
			return false
	return true


func _top_plate(name: String, focus: Vector3, distance: float, plots: Array[Vector2i]) -> void:
	_aim(focus, 180.0, 72.0, distance)
	await _frames(3)
	var half := 43.0 if distance < 200.0 else 128.0
	var corners: Array[Vector3] = [
		Vector3(-half, 0.2, -210),
		Vector3(half, 0.2, -210),
		Vector3(half, 0.2, -60),
		Vector3(-half, 0.2, -60)
	]
	var targets: Array[Vector3] = []
	for plot in plots:
		targets.append(_inside(plot))
	print("PLATE %s owned=%s" % [name, _land.owned_plots()])
	if _prove(name, corners, _site, targets):
		await _save(name)


## A close-up of the edge at `seam` of the owned plot `plot`; the target is
## on the owned side.
func _join_plate(name: String, seam: Vector3, plot: Vector2i) -> void:
	_aim(seam, 160.0, 30.0, 18.0)
	await _frames(3)
	var points: Array[Vector3] = [seam + Vector3(0, 0, -4), seam + Vector3(0, 0, 4), seam]
	var step := -1.5 if seam.x < 0.0 else 1.5
	var targets: Array[Vector3] = [seam - Vector3(step, 0, 0)]
	var lot := _site.find_child("Lot_%d_%d" % [plot.x, plot.y], true, false)
	var kerbs := []
	for side in OwnedPaving.SIDES:
		var kerb := _site.find_child("Lot_%d_%d_%s" % [plot.x, plot.y, side], true, false)
		if kerb != null:
			kerbs.append("%s=%s" % [side, (kerb as Node3D).visible])
	print("PLATE %s %s visible=%s kerbs %s" % [name, lot.name, (lot as Node3D).visible, kerbs])
	if _prove(name, points, _site, targets):
		await _save(name)


func _distance_plate() -> void:
	_aim(Vector3(0, 0, -130), 150.0, 40.0, 420.0)
	await _frames(3)
	var points: Array[Vector3] = [
		Vector3(-128, 0.2, -210),
		Vector3(128, 0.2, -210),
		Vector3(128, 0.2, -60),
		Vector3(-128, 0.2, -60)
	]
	var targets: Array[Vector3] = [_inside(BUY[0]), _inside(BUY[1])]
	if _prove("04_distance", points, _site, targets):
		await _save("04_distance.png")


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


func _show_hud(on: bool) -> void:
	for layer in _main.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = on


## Trimesh colliders on every shown mesh; a hidden plot's collider is removed,
## so a ray passes through unowned land to the grass.
func _add_colliders(node: Node) -> void:
	var meshes: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		meshes.append(node)
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		meshes.append(mi)
	for mi in meshes:
		var bodies := mi.find_children("*", "StaticBody3D", false, false)
		if not mi.is_visible_in_tree():
			for body in bodies:
				body.free()
		elif mi.mesh != null and bodies.is_empty():
			mi.create_trimesh_collision()
