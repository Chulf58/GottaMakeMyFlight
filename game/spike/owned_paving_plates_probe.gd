extends SceneTree
## Windowed plate probe for the owned-plots paving (board 8cfe8ec6, decision
## site-paving-covers-only-the-owned-land-plots-and-grows-as-ea): a new game
## from above, the same after buying one north and one east plot, a close-up of
## a paving/grass edge, the starter stand's pad and taxi link over the grass
## with a plane parked, a close-up of the pad's edge, the road and forecourt,
## and a distance shot. It rules nothing.
##
## Run (one windowed Godot run project-wide):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path <worktree>/game -s res://spike/owned_paving_plates_probe.gd
##
## Boots main.tscn with the starter shell and a gate desk (StarterFlight), so
## the real Airside lays out the gate's stand, pad and taxi link, and the real
## OwnedPaving shows the paving. No flight runs. Every plate projects its
## subject points into the viewport with MARGIN_PX and casts camera rays at
## them (trimesh colliders on every mesh) before it is saved; on failure it
## prints PROBE_INVALID and exits 1. Prints the world seed.
##
## Numbers: along taxi in, pushback and taxi out, and along the parked plane's
## centre line and its main gear lines, the plane's ground height against the
## top surface under it (the site paving where the plot is owned, the taxi
## paving, else the grass at y -0.1): the worst float, the worst sink and the
## samples whose top surface is grass.

const StarterFlight := preload("res://spike/starter_flight.gd")
const MAIN_SCENE := "res://main/main.tscn"
const OUT_REL := "res://../tools/blender/out/owned-paving"
const MARGIN_PX := 8.0
const SHEET_TILE := Vector2i(480, 270)
const MODEL := "tp_plane_05a"
const GRASS_Y := -0.1
## The main gear sits about this far either side of the centre line.
const GEAR_HALF_M := 3.0

var _out_dir := ""
var _main: Node
var _cam: Camera3D
var _view: PlaneView
var _airside: Airside
var _mode: BuildMode
var _land: LandPlots
var _site: Node3D
var _stand: Dictionary = {}
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
	_view = _main.get_node("PlaneView")
	_view.set_process(false)
	(_main.get_node("PlaneView2") as Node).set_process(false)
	_airside = _main.get_node("Airside")
	_mode = _main.get_node("BuildMode")
	_land = _mode.land_tool.land
	_site = _main.get_node("Airside/Terminal")
	await _frames(6)
	if not StarterFlight.add_gate_desk(_mode.grid):
		_end("the gate desk was refused")
		return
	await _frames(6)
	if _airside.gate_stands.is_empty():
		_end("no gate got a stand")
		return
	var gate: String = _airside.gate_stands.keys()[0]
	_stand = _airside.gate_stands[gate]
	_view.gate = gate
	var at := StandPlacement.stand_point(_stand)
	print("PROBE gate=%s stand_point=%s pads=%s" % [gate, at, _airside.paving.pads])
	_show_hud(false)
	_cam = Camera3D.new()
	_cam.fov = 55.0
	_cam.far = 3000.0
	_main.add_child(_cam)
	_cam.make_current()
	_add_colliders(_main)
	_pose_parked()
	await _frames(4)
	_numbers("new game")
	await _top_plate("01_new_game_top.png")
	await _edge_plate()
	await _stand_plates(at)
	await _road_plate()
	for plot: Vector2i in [Vector2i(0, 2), Vector2i(2, 4)]:
		var result := _land.buy(plot, null)
		print("PROBE bought %s ok=%s" % [plot, result.ok])
		if not result.ok:
			_end("buying %s was refused" % plot)
			return
	_add_colliders(_main)
	await _frames(4)
	_numbers("after buying")
	await _top_plate("02_bought_north_east_top.png")
	await _distance_plate()
	_contact_sheet()
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


## Parks the main PlaneView's MODEL at the stand, as update_pose() does at the
## end of taxi in.
func _pose_parked() -> void:
	_view.show_model(MODEL)
	var pose := _pose_on(FlightSim.State.TAXI_IN, 1.0)
	_view.transform = pose
	_view.phase = FlightSim.State.TAXI_IN
	_view.visible = true
	_view.flight_id = "probe"
	_view._set_model_position(_view.model_position_at(FlightSim.State.TAXI_IN, pose, "medium"))
	_view._follow_props()
	_add_colliders(_view)


func _pose_on(state: int, t: float) -> Transform3D:
	var path := _view._path(state, "medium")
	var pose := FlightPose.pose(state, t, path, _view._entry_dir(state, "medium"))
	pose.origin.y += PlaneView.ground_height_at(pose.origin)
	return pose


## The top surface under world point `at`: the site paving where its plot is
## shown, the taxi paving, else the grass.
func _surface(at: Vector3) -> Dictionary:
	var top := GRASS_Y
	var what := "grass"
	var cell := _mode.grid.world_to_cell(at)
	if _land.in_site(_land.plot_of(cell)) and _land.owns_cell(cell):
		top = _site_top()
		what = "site"
	var taxi := _taxi_top(at)
	if taxi > top:
		top = taxi
		what = "taxi"
	return {"y": top, "what": what}


func _site_top() -> float:
	return PlaneView.SITE.ground_height


func _taxi_top(at: Vector3) -> float:
	var mesh := _airside.paving.mesh as ArrayMesh
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var best := -INF
	var p := Vector2(at.x, at.z)
	for t in range(0, index.size(), 3):
		if not is_equal_approx(uvs[index[t]].x, TaxiPaving.ASPHALT_U):
			continue
		var a := verts[index[t]]
		var b := verts[index[t + 1]]
		var c := verts[index[t + 2]]
		if (c - a).cross(b - a).normalized().y < 0.5:
			continue
		var a2 := Vector2(a.x, a.z)
		var b2 := Vector2(b.x, b.z)
		var c2 := Vector2(c.x, c.z)
		var w := _weights(p, a2, b2, c2)
		# Not strict: a point on an edge two triangles share counts for both.
		if minf(w.x, minf(w.y, w.z)) < -0.00001:
			continue
		best = maxf(best, a.y * w.x + b.y * w.y + c.y * w.z)
	return best


static func _weights(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> Vector3:
	var d := (b - a).cross(c - a)
	var wb := (p - a).cross(c - a) / d
	var wc := (b - a).cross(p - a) / d
	return Vector3(1.0 - wb - wc, wb, wc)


func _numbers(label: String) -> void:
	var samples: Array[Vector3] = []
	for state in PlaneView.ON_GROUND:
		for i in 101:
			samples.append(_pose_on(state, i / 100.0).origin)
	var parked_from := samples.size()
	var parked := _pose_on(FlightSim.State.TAXI_IN, 1.0)
	var foot := TaxiPaving.parked_footprint(StandPlacement.stand_point(_stand), MODEL)
	for side in [-GEAR_HALF_M, 0.0, GEAR_HALF_M]:
		var z := foot.position.y + 1.0
		while z < foot.end.y - 1.0:
			var p := Vector3(parked.origin.x + side, 0.0, z)
			p.y = PlaneView.ground_height_at(p)
			samples.append(p)
			z += 1.0
	# Where each sample lies: parked at the stand (the last ones), on the runway
	# (out of this lane's scope, counted only), on the lane, or on a link.
	var lane_north := StandPlacement.TAXI_LANE_Z - TaxiPaving.WIDTH_M / 2.0
	var lane_south := StandPlacement.TAXI_LANE_Z + TaxiPaving.WIDTH_M / 2.0
	var stats := {}
	var bad := false
	for i in samples.size():
		var p := samples[i]
		var where := "stand"
		if i < parked_from:
			if p.z < Airside.runway_south():
				where = "runway"
			elif p.z <= lane_south and p.z >= lane_north:
				where = "lane"
			else:
				where = "link"
		var under := _surface(p)
		if not stats.has(where):
			stats[where] = {"n": 0, "site": 0, "taxi": 0, "grass": 0, "float": 0.0, "sink": 0.0}
		var s: Dictionary = stats[where]
		s["n"] += 1
		s[under["what"]] += 1
		s["float"] = maxf(s["float"], p.y - float(under["y"]))
		s["sink"] = maxf(s["sink"], float(under["y"]) - p.y)
		if where != "runway" and (under["what"] == "grass" or p.y - float(under["y"]) > 0.04):
			bad = true
		if where != "runway" and float(under["y"]) - p.y > 0.001:
			bad = true
	for where: String in stats:
		var s: Dictionary = stats[where]
		print(
			(
				"NUMBERS %s %s samples=%d site=%d taxi=%d grass=%d worst_float=%.4f worst_sink=%.4f"
				% [label, where, s["n"], s["site"], s["taxi"], s["grass"], s["float"], s["sink"]]
			)
		)
	if bad:
		_invalid("%s: a plane sits on grass, sinks or floats" % label)


func _aim(focus: Vector3, yaw: float, pitch: float, distance: float) -> void:
	var y := deg_to_rad(yaw)
	var p := deg_to_rad(pitch)
	var back := Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p))
	_cam.look_at_from_position(focus + back * distance, focus, Vector3.UP)


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
		print(
			(
				"VISIBLE %s %s hit=%s ok=%s"
				% [label, t, hit.collider.get_parent().name if hit else "-", ok]
			)
		)
		if not ok:
			_invalid("%s: %s is occluded" % [label, t])
			return false
	return true


func _top_plate(name: String) -> void:
	_aim(Vector3(0, 0, -135), 180.0, 72.0, 190.0)
	await _frames(3)
	var corners: Array[Vector3] = [
		Vector3(-43, 0.2, -210),
		Vector3(43, 0.2, -210),
		Vector3(43, 0.2, -60),
		Vector3(-43, 0.2, -60)
	]
	var targets: Array[Vector3] = []
	for plot in _land.owned_plots():
		var cells := _land.plot_cells(plot)
		var mid := Vector2(cells.position.x + 2, cells.end.y - 2) + Vector2(-43, -210)
		targets.append(Vector3(mid.x, 0.2, mid.y))
	print("PLATE %s owned=%s" % [name, _land.owned_plots()])
	if await _prove_targets(name, corners, targets):
		await _save(name)


## Each target must hit a shown plot mesh first.
func _prove_targets(label: String, points: Array[Vector3], targets: Array[Vector3]) -> bool:
	if not _prove(label, points, _site, targets):
		return false
	return true


func _edge_plate() -> void:
	# The east edge of the start land: plot (1, 4) owned, (2, 4) not.
	var edge := Vector3(1.0, 0.2, -97.0)
	_aim(edge, 120.0, 28.0, 16.0)
	await _frames(3)
	var points: Array[Vector3] = [Vector3(1, 0.2, -101), Vector3(1, 0.2, -93), edge]
	var targets: Array[Vector3] = [Vector3(-0.5, 0.2, -97)]
	if _prove("03_edge", points, _site.find_child("Lot_1_4", true, false), targets):
		await _save("03_paving_grass_edge.png")


func _stand_plates(at: Vector3) -> void:
	var plane: Node3D = _view.get_node("Pivot").get_child(0)
	var north := at + Vector3(0, 0, -60)
	_aim(at + Vector3(0, 0, -25), 135.0, 35.0, 95.0)
	await _frames(3)
	var points: Array[Vector3] = [at + Vector3(0, 4, 0), north]
	var targets: Array[Vector3] = [at + Vector3(0, 3, 0)]
	if _prove("04_stand", points, plane, targets):
		await _save("04_stand_pad_link_plane.png")
	# The pad's edge over the grass, beside the parked plane.
	var pad: Rect2 = _airside.paving.pads[0]
	var corner := Vector3(pad.end.x, 0.18, maxf(pad.position.y, -150.0))
	_aim(corner, 60.0, 22.0, 22.0)
	await _frames(3)
	var edge_points: Array[Vector3] = [corner, corner + Vector3(0, 0, 6)]
	var edge_targets: Array[Vector3] = [corner + Vector3(-2.0, 0.0, 3.0)]
	print("PROBE pad=%s corner=%s" % [pad, corner])
	if _prove("05_pad_edge", edge_points, _airside.paving, edge_targets):
		await _save("05_pad_edge_closeup.png")


func _road_plate() -> void:
	var focus := Vector3(0, 0.2, -52)
	_aim(focus, 0.0, 30.0, 45.0)
	await _frames(3)
	var points: Array[Vector3] = [
		Vector3(-20, 0.2, -58), Vector3(20, 0.2, -58), Vector3(0, 0.1, -45)
	]
	var targets: Array[Vector3] = [Vector3(0, 0.1, -50), Vector3(-15, 0.1, -48)]
	if _prove("06_road", points, _site.find_child("Road", true, false), targets):
		await _save("06_road_forecourt.png")


func _distance_plate() -> void:
	var at := StandPlacement.stand_point(_stand)
	_aim(Vector3(0, 0, -130), 150.0, 40.0, 260.0)
	await _frames(3)
	var points: Array[Vector3] = [
		Vector3(-43, 0.2, -210), Vector3(43, 0.2, -60), at + Vector3(0, 4, 0)
	]
	var targets: Array[Vector3] = [Vector3(-30, 0.2, -70)]
	if _prove("07_distance", points, _site, targets):
		await _save("07_distance.png")


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
